#include "kuxir_ppo.h"

#include <torch/cuda.h>
#include <c10/cuda/CUDAFunctions.h>
#include <c10/macros/Export.h>
#include <cuda_runtime_api.h>

#include <chrono>
#include <iomanip>
#include <iostream>

using torch::indexing::Slice;
namespace at::cuda { TORCH_CUDA_CPP_API cudaDeviceProp* getCurrentDeviceProperties(); }

KuxirTrainer::KuxirTrainer(KuxirConfig config)
    : cfg_(std::move(config)), actions_(static_cast<int>(KuxirEnv::action_table().size())),
      device_(c10::cuda::device_count() > 0 ? torch::kCUDA : torch::kCPU), net_(actions_), pool_(cfg_.env_threads) {
    torch::set_num_threads(1);
    if (device_.is_cuda()) (void)at::cuda::getCurrentDeviceProperties();
    net_->to(device_);
    optimizer_ = std::make_unique<torch::optim::Adam>(
        net_->parameters(), torch::optim::AdamOptions(cfg_.lr).eps(1e-5));
    envs_.reserve(cfg_.envs);
    for (int i = 0; i < cfg_.envs; ++i)
        envs_.push_back(std::make_unique<KuxirEnv>(cfg_, cfg_.seed + i * 104729ULL));
    std::filesystem::create_directories(cfg_.checkpoints / "versions");
    load_latest();
}

bool KuxirTrainer::load_latest() {
    const auto path = cfg_.checkpoints / "latest.pt";
    if (!std::filesystem::exists(path)) return false;
    try {
        torch::serialize::InputArchive archive;
        archive.load_from(path.string());
        net_->load(archive);
        optimizer_->load(archive);
        torch::Tensor meta;
        archive.read("meta", meta);
        global_steps_ = meta[0].item<int64_t>();
        update_ = meta[1].item<int64_t>();
        std::cout << "[resume] steps=" << global_steps_ << " update=" << update_ << '\n';
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[resume-warning] " << e.what() << '\n';
        return false;
    }
}

void KuxirTrainer::checkpoint(bool versioned) {
    torch::serialize::OutputArchive archive;
    net_->save(archive);
    optimizer_->save(archive);
    archive.write("meta", torch::tensor({static_cast<int64_t>(global_steps_), static_cast<int64_t>(update_)}));
    const auto tmp = cfg_.checkpoints / "latest.tmp.pt";
    const auto dst = cfg_.checkpoints / "latest.pt";
    archive.save_to(tmp.string());
    std::error_code ec;
    std::filesystem::remove(dst, ec); ec.clear();
    std::filesystem::rename(tmp, dst, ec);
    if (ec) throw std::runtime_error("atomic latest checkpoint failed: " + ec.message());
    if (versioned) {
        const auto version = cfg_.checkpoints / "versions" / (std::to_string(global_steps_) + ".pt");
        const auto version_tmp = std::filesystem::path(version.string() + ".tmp");
        std::filesystem::copy_file(dst, version_tmp, std::filesystem::copy_options::overwrite_existing);
        std::filesystem::remove(version, ec); ec.clear();
        std::filesystem::rename(version_tmp, version, ec);
        if (ec) throw std::runtime_error("atomic version checkpoint failed: " + ec.message());
    }
}

void KuxirTrainer::run(bool smoke, int benchmark_updates) {
    const int env_count = cfg_.envs;
    const int horizon = smoke ? 2 : cfg_.rollout_decisions;
    const int sample_count = env_count * horizon;
    if (smoke) { cfg_.epochs = 1; cfg_.minibatch = sample_count; }
    const auto cpu_float = torch::TensorOptions().dtype(torch::kFloat32).device(torch::kCPU);
    const auto cpu_long = torch::TensorOptions().dtype(torch::kInt64).device(torch::kCPU);
    const auto cpu_bool = torch::TensorOptions().dtype(torch::kBool).device(torch::kCPU);

    // Reuse the large rollout buffers and result array every update. This
    // removes allocator pressure without changing samples, PPO, or precision.
    auto obs = torch::empty({horizon, env_count, kObsSize}, cpu_float);
    auto masks = torch::empty({horizon, env_count, actions_}, cpu_bool);
    auto actions = torch::empty({horizon, env_count}, cpu_long);
    auto old_log_probs = torch::empty({horizon, env_count}, cpu_float);
    auto values = torch::empty({horizon, env_count}, cpu_float);
    auto rewards = torch::empty({horizon, env_count}, cpu_float);
    auto dones = torch::empty({horizon, env_count}, cpu_bool);
    auto next_obs = torch::empty({env_count, kObsSize}, cpu_float);
    std::vector<KuxirStepResult> results(env_count);

    std::cout << "[kuxir-native] device=" << (device_.is_cuda() ? "cuda" : "cpu")
              << " envs=" << env_count << " threads=" << cfg_.env_threads
              << " tick_skip=" << cfg_.tick_skip << " actions=" << actions_
              << " obs=" << kObsSize << '\n' << std::flush;

    int completed_updates = 0;
    for (;;) {
        const auto started = std::chrono::steady_clock::now();
        int goals = 0, touches = 0, wall_touches = 0, setup_touches = 0, aerial_commits = 0, flip_attempts = 0, flip_contacts = 0, developing_pinches = 0, pinches = 0, fast_pinches = 0, pinch_goals = 0;
        int stage_episodes[3] = {0, 0, 0};
        int stage_touches[3] = {0, 0, 0};
        int stage_pinches[3] = {0, 0, 0};
        double pinch_speed_sum = 0.0, pinch_quality_sum = 0.0, wall_speed_sum = 0.0, wall_impulse_sum = 0.0;
        float max_pinch_speed = 0.f, max_wall_speed = 0.f, max_inward_speed = 0.f, max_wall_impulse = 0.f;

        for (int t = 0; t < horizon; ++t) {
            float* obs_ptr = obs[t].data_ptr<float>();
            auto* mask_ptr = reinterpret_cast<uint8_t*>(masks[t].data_ptr<bool>());
            pool_.parallel_for(env_count, [&](int e) {
                envs_[e]->observe(obs_ptr + e * kObsSize);
                envs_[e]->action_mask(mask_ptr + e * actions_, actions_);
            });
            {
                torch::NoGradGuard no_grad;
                const auto input = obs[t].to(device_, true);
                const auto mask = masks[t].to(device_, true);
                auto [logits, value] = net_->forward(input);
                logits = logits.masked_fill(mask.logical_not(), -1e9);
                const auto log_probs = torch::log_softmax(logits, -1);
                const auto action = log_probs.exp().multinomial(1).squeeze(1);
                const auto chosen_log_prob = log_probs.gather(1, action.unsqueeze(1)).squeeze(1);
                actions[t].copy_(action.cpu());
                old_log_probs[t].copy_(chosen_log_prob.cpu());
                values[t].copy_(value.cpu());
            }

            const auto* action_ptr = actions[t].data_ptr<int64_t>();
            float* reward_ptr = rewards[t].data_ptr<float>();
            auto* done_ptr = reinterpret_cast<uint8_t*>(dones[t].data_ptr<bool>());
            pool_.parallel_for(env_count, [&](int e) {
                results[e] = envs_[e]->step(action_ptr[e], actions_, global_steps_);
            });
            for (int e = 0; e < env_count; ++e) {
                const auto& result = results[e];
                reward_ptr[e] = result.reward;
                done_ptr[e] = result.done;
                goals += result.goal; touches += result.touched; pinches += result.pinch;
                const int stage = std::clamp(result.stage, 0, 2);
                stage_episodes[stage] += result.done;
                stage_touches[stage] += result.touched;
                stage_pinches[stage] += result.pinch;
                fast_pinches += result.fast_pinch; pinch_goals += result.pinch_goal;
                setup_touches += result.setup_touch;
                aerial_commits += result.aerial_commit;
                flip_attempts += result.flip_attempt;
                flip_contacts += result.flip_contact;
                developing_pinches += result.developing_pinch;
                if (result.wall_touch) {
                    ++wall_touches; wall_speed_sum += result.touch_speed; wall_impulse_sum += result.touch_impulse;
                    max_wall_speed = std::max(max_wall_speed, result.touch_speed);
                    max_inward_speed = std::max(max_inward_speed, result.inward_speed);
                    max_wall_impulse = std::max(max_wall_impulse, result.touch_impulse);
                }
                if (result.pinch) {
                    pinch_speed_sum += result.pinch_speed;
                    pinch_quality_sum += result.pinch_quality;
                    max_pinch_speed = std::max(max_pinch_speed, result.pinch_speed);
                }
            }
            global_steps_ += env_count;
        }

        pool_.parallel_for(env_count, [&](int e) {
            envs_[e]->observe(next_obs.data_ptr<float>() + e * kObsSize);
        });
        torch::Tensor next_value;
        {
            torch::NoGradGuard no_grad;
            next_value = net_->forward(next_obs.to(device_, true)).second.cpu();
        }
        auto advantages = torch::zeros_like(rewards);
        auto last_advantage = torch::zeros({env_count}, cpu_float);
        for (int t = horizon - 1; t >= 0; --t) {
            const auto nonterminal = dones[t].logical_not().to(torch::kFloat32);
            const auto following_value = t == horizon - 1 ? next_value : values[t + 1];
            const auto delta = rewards[t] + cfg_.gamma * following_value * nonterminal - values[t];
            last_advantage = delta + cfg_.gamma * cfg_.gae_lambda * nonterminal * last_advantage;
            advantages[t] = last_advantage;
        }
        const auto returns = advantages + values;
        const auto flat_obs = obs.reshape({sample_count, kObsSize}).to(device_);
        const auto flat_masks = masks.reshape({sample_count, actions_}).to(device_);
        const auto flat_actions = actions.reshape({sample_count}).to(device_);
        const auto flat_old_log_probs = old_log_probs.reshape({sample_count}).to(device_);
        const auto flat_returns = returns.reshape({sample_count}).to(device_);
        auto flat_advantages = advantages.reshape({sample_count}).to(device_);
        flat_advantages = (flat_advantages - flat_advantages.mean()) / (flat_advantages.std() + 1e-8);

        double policy_sum = 0, value_sum = 0, entropy_sum = 0, kl_sum = 0;
        int batches = 0;
        net_->train();
        for (int epoch = 0; epoch < cfg_.epochs; ++epoch) {
            const auto order = torch::randperm(sample_count,
                torch::TensorOptions().dtype(torch::kInt64).device(device_));
            for (int begin = 0; begin < sample_count; begin += cfg_.minibatch) {
                const int end = std::min(sample_count, begin + cfg_.minibatch);
                const auto index = order.index({Slice(begin, end)});
                auto [logits, value] = net_->forward(flat_obs.index_select(0, index));
                logits = logits.masked_fill(flat_masks.index_select(0, index).logical_not(), -1e9);
                const auto log_probs = torch::log_softmax(logits, -1);
                const auto probabilities = log_probs.exp();
                const auto new_log_prob = log_probs.gather(
                    1, flat_actions.index_select(0, index).unsqueeze(1)).squeeze(1);
                const auto old_log_prob = flat_old_log_probs.index_select(0, index);
                const auto ratio = (new_log_prob - old_log_prob).exp();
                const auto batch_advantage = flat_advantages.index_select(0, index);
                const auto unclipped = ratio * batch_advantage;
                const auto clipped = torch::clamp(ratio, 1 - cfg_.clip, 1 + cfg_.clip) * batch_advantage;
                const auto policy_loss = -torch::minimum(unclipped, clipped).mean();
                const auto value_loss = torch::mse_loss(value, flat_returns.index_select(0, index));
                const auto entropy = -(probabilities * log_probs).sum(-1).mean();
                const auto loss = policy_loss + cfg_.value_coef * value_loss - cfg_.entropy * entropy;
                optimizer_->zero_grad();
                loss.backward();
                torch::nn::utils::clip_grad_norm_(net_->parameters(), cfg_.max_grad_norm);
                optimizer_->step();
                policy_sum += policy_loss.item<double>(); value_sum += value_loss.item<double>();
                entropy_sum += entropy.item<double>(); kl_sum += (old_log_prob - new_log_prob).mean().item<double>();
                ++batches;
            }
        }

        ++update_;
        ++completed_updates;
        const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
        const double sps = sample_count / elapsed;
        const double average_speed = pinches ? pinch_speed_sum / pinches : 0.0;
        const double average_quality = pinches ? pinch_quality_sum / pinches : 0.0;
        const double average_wall_speed = wall_touches ? wall_speed_sum / wall_touches : 0.0;
        const double average_wall_impulse = wall_touches ? wall_impulse_sum / wall_touches : 0.0;
        std::cout << std::fixed << std::setprecision(4)
                  << "[kuxir " << update_ << "] steps=" << global_steps_
                  << " sps=" << std::setprecision(0) << sps << std::setprecision(4)
                  << " reward=" << rewards.mean().item<float>()
                  << " goals=" << goals << " touches=" << touches << " wall=" << wall_touches << " setups=" << setup_touches
                  << " aerials=" << aerial_commits
                  << " flip_attempts=" << flip_attempts
                  << " flip_contacts=" << flip_contacts << " developing=" << developing_pinches << " pinches=" << pinches
                  << " fast=" << fast_pinches << " pinch_goals=" << pinch_goals
                  << " avg_speed=" << std::setprecision(0) << average_speed << " max_speed=" << max_pinch_speed
                  << " wall_speed=" << average_wall_speed << " wall_max=" << max_wall_speed
                  << " impulse=" << average_wall_impulse << " impulse_max=" << max_wall_impulse
                  << " inward_max=" << max_inward_speed
                  << " stage_ep=" << stage_episodes[0] << '/' << stage_episodes[1] << '/' << stage_episodes[2]
                  << " stage_touch=" << stage_touches[0] << '/' << stage_touches[1] << '/' << stage_touches[2]
                  << " stage_pinch=" << stage_pinches[0] << '/' << stage_pinches[1] << '/' << stage_pinches[2]
                  << std::setprecision(4) << " quality=" << average_quality
                  << " policy=" << policy_sum / batches << " value=" << value_sum / batches
                  << " entropy=" << entropy_sum / batches << " kl=" << kl_sum / batches << '\n' << std::flush;

        if (smoke) { checkpoint(false); return; }
        if (benchmark_updates > 0 && completed_updates >= benchmark_updates) return;
        if (update_ % cfg_.save_every_updates == 0)
            checkpoint(update_ % cfg_.version_every_updates == 0);
    }
}
