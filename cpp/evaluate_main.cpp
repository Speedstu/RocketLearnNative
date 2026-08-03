#include "config.h"
#include "heatseeker_env.h"
#include "model.h"
#include "thread_pool.h"

#include <RocketSim.h>
#include <torch/torch.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace fs = std::filesystem;

namespace {
struct Rating {
    uint64_t version = 0;
    double mu = 0.0;
    double sigma = 8.3333333333;
    uint64_t games = 0, wins = 0, losses = 0, draws = 0;
};

double normal_pdf(double x) {
    constexpr double inv_sqrt_2pi = 0.39894228040143267794;
    return inv_sqrt_2pi * std::exp(-0.5 * x * x);
}

double normal_cdf(double x) {
    return 0.5 * std::erfc(-x / std::sqrt(2.0));
}

// TrueSkill update for two teams containing two identical policy copies each.
// It matches RocketLearn's version-league semantics while keeping the first
// random checkpoint as the fixed reporting origin.
void rate_win(Rating& winner, Rating& loser) {
    constexpr double beta = 25.0 / 6.0;
    constexpr double tau = 25.0 / 300.0;
    const double sw2 = winner.sigma * winner.sigma + tau * tau;
    const double sl2 = loser.sigma * loser.sigma + tau * tau;
    const double c = std::sqrt(4.0 * beta * beta + 2.0 * sw2 + 2.0 * sl2);
    const double t = 2.0 * (winner.mu - loser.mu) / c;
    const double cdf = std::max(normal_cdf(t), 1e-12);
    const double v = normal_pdf(t) / cdf;
    const double w = v * (v + t);
    winner.mu += sw2 / c * v;
    loser.mu -= sl2 / c * v;
    winner.sigma = std::max(1.0, std::sqrt(std::max(1e-9, sw2 * (1.0 - sw2 / (c * c) * w))));
    loser.sigma = std::max(1.0, std::sqrt(std::max(1e-9, sl2 * (1.0 - sl2 / (c * c) * w))));
}

std::map<uint64_t, Rating> load_ratings(const fs::path& path) {
    std::map<uint64_t, Rating> ratings;
    std::ifstream in(path);
    std::string line;
    std::getline(in, line);
    while (std::getline(in, line)) {
        std::istringstream row(line);
        Rating r;
        if (row >> r.version >> r.mu >> r.sigma >> r.games >> r.wins >> r.losses >> r.draws)
            ratings[r.version] = r;
    }
    return ratings;
}

void save_ratings(const fs::path& path, const std::map<uint64_t, Rating>& ratings) {
    const fs::path tmp = path.string() + ".tmp";
    std::ofstream out(tmp, std::ios::trunc);
    out << "version\tmu\tsigma\tgames\twins\tlosses\tdraws\tskill_rating\tconfidence_95\n";
    const double baseline = ratings.empty() ? 0.0 : ratings.begin()->second.mu;
    for (const auto& [version, r] : ratings) {
        out << version << '\t' << std::setprecision(10) << r.mu << '\t' << r.sigma << '\t'
            << r.games << '\t' << r.wins << '\t' << r.losses << '\t' << r.draws << '\t'
            << std::llround(40.0 * (r.mu - baseline)) << '\t'
            << std::llround(80.0 * r.sigma) << '\n';
    }
    out.close();
    std::error_code ec;
    fs::remove(path, ec);
    fs::rename(tmp, path, ec);
    if (ec) throw std::runtime_error("cannot atomically save ratings: " + ec.message());

    if (ratings.empty()) return;
    const auto best = std::max_element(ratings.begin(), ratings.end(), [](const auto& a, const auto& b) {
        return a.second.mu - 2.0 * a.second.sigma < b.second.mu - 2.0 * b.second.sigma;
    });
    const fs::path best_id_path = path.parent_path() / "best_version.txt";
    uint64_t old_best = 0;
    { std::ifstream best_in(best_id_path); best_in >> old_best; }
    if (old_best != best->first) {
        const fs::path source = path.parent_path() / "versions" / (std::to_string(best->first) + ".pt");
        const fs::path best_tmp = path.parent_path() / "best.tmp.pt";
        const fs::path best_path = path.parent_path() / "best.pt";
        if (fs::exists(source)) {
            fs::copy_file(source, best_tmp, fs::copy_options::overwrite_existing);
            std::error_code best_ec;
            fs::remove(best_path, best_ec);
            fs::rename(best_tmp, best_path, best_ec);
            if (!best_ec) {
                const fs::path id_tmp = best_id_path.string() + ".tmp";
                { std::ofstream id_out(id_tmp, std::ios::trunc); id_out << best->first << '\n'; }
                fs::remove(best_id_path, best_ec);
                fs::rename(id_tmp, best_id_path, best_ec);
            }
        }
    }
}

std::vector<uint64_t> discover_versions(const fs::path& dir) {
    std::vector<uint64_t> versions;
    if (!fs::exists(dir)) return versions;
    for (const auto& entry : fs::directory_iterator(dir)) {
        if (!entry.is_regular_file() || entry.path().extension() != ".pt") continue;
        try { versions.push_back(std::stoull(entry.path().stem().string())); } catch (...) {}
    }
    std::sort(versions.begin(), versions.end());
    return versions;
}

ActorCritic load_policy(const fs::path& path, int actions) {
    ActorCritic policy(actions);
    torch::serialize::InputArchive archive;
    archive.load_from(path.string(), torch::kCPU);
    policy->load(archive);
    policy->eval();
    return policy;
}

struct MatchStats {
    int wins = 0, losses = 0, draws = 0;
    // +1 current win, -1 current loss, 0 timeout/draw, in observed order.
    std::vector<int8_t> outcomes;
};

MatchStats play_batch(const Config& cfg, const fs::path& current_path,
                      const fs::path& opponent_path, uint64_t current_version,
                      int target_games) {
    const int actions = static_cast<int>(HeatseekerEnv::action_table().size());
    auto current = load_policy(current_path, actions);
    auto opponent = load_policy(opponent_path, actions);
    constexpr int env_count = 16;
    ThreadPool pool(std::min(4, cfg.env_threads));
    std::vector<std::unique_ptr<HeatseekerEnv>> envs;
    const auto batch_salt = static_cast<uint64_t>(std::chrono::high_resolution_clock::now().time_since_epoch().count());
    for (int i = 0; i < env_count; ++i)
        envs.push_back(std::make_unique<HeatseekerEnv>(cfg, current_version ^ batch_salt ^ (104729ULL * i)));

    const auto float_opts = torch::TensorOptions().dtype(torch::kFloat32).device(torch::kCPU);
    const auto bool_opts = torch::TensorOptions().dtype(torch::kBool).device(torch::kCPU);
    const auto long_opts = torch::TensorOptions().dtype(torch::kInt64).device(torch::kCPU);
    auto obs = torch::empty({env_count, 4, kObsSize}, float_opts);
    auto masks = torch::empty({env_count, 4, actions}, bool_opts);
    auto selected = torch::empty({env_count, 4}, long_opts);
    MatchStats stats;
    torch::NoGradGuard no_grad;

    while (stats.wins + stats.losses + stats.draws < target_games) {
        float* op = obs.data_ptr<float>();
        uint8_t* mp = reinterpret_cast<uint8_t*>(masks.data_ptr<bool>());
        pool.parallel_for(env_count, [&](int e) {
            envs[e]->observe(op + e * 4 * kObsSize);
            envs[e]->action_masks(mp + e * 4 * actions, actions);
        });
        auto flat_obs = obs.reshape({env_count * 4, kObsSize});
        auto flat_mask = masks.reshape({env_count * 4, actions});
        auto current_logits = current->forward(flat_obs).first.masked_fill(flat_mask.logical_not(), -1e9);
        auto opponent_logits = opponent->forward(flat_obs).first.masked_fill(flat_mask.logical_not(), -1e9);
        auto current_actions = current_logits.argmax(-1).reshape({env_count, 4});
        auto opponent_actions = opponent_logits.argmax(-1).reshape({env_count, 4});
        auto* dst = selected.data_ptr<int64_t>();
        auto* ca = current_actions.data_ptr<int64_t>();
        auto* oa = opponent_actions.data_ptr<int64_t>();
        for (int e = 0; e < env_count; ++e) {
            const bool current_blue = (e & 1) == 0;
            for (int a = 0; a < 4; ++a)
                dst[e * 4 + a] = ((a < 2) == current_blue) ? ca[e * 4 + a] : oa[e * 4 + a];
        }
        std::vector<StepResult> results(env_count);
        pool.parallel_for(env_count, [&](int e) {
            results[e] = envs[e]->step(dst + e * 4, actions, current_version);
        });
        for (int e = 0; e < env_count && stats.wins + stats.losses + stats.draws < target_games; ++e) {
            if (!results[e].done) continue;
            if (!results[e].goal) { ++stats.draws; stats.outcomes.push_back(0); continue; }
            const bool current_blue = (e & 1) == 0;
            const bool current_scored = results[e].scoring_team == (current_blue ? 0 : 1);
            if (current_scored) { ++stats.wins; stats.outcomes.push_back(1); }
            else { ++stats.losses; stats.outcomes.push_back(-1); }
        }
    }
    return stats;
}
}

int main(int argc, char** argv) {
    try {
#ifdef _WIN32
        const HANDLE singleton = CreateMutexW(nullptr, TRUE, L"Local\\RocketLearnNativeSkillEvaluator");
        if (!singleton || GetLastError() == ERROR_ALREADY_EXISTS) {
            std::cerr << "[evaluator] another evaluator is already running\n";
            if (singleton) CloseHandle(singleton);
            return 0;
        }
#endif
        Config cfg = Config::load();
        torch::set_num_threads(4);
        RocketSim::Init(fs::absolute(cfg.meshes), true);
        const fs::path versions_dir = cfg.checkpoints / "versions";
        const fs::path ratings_path = cfg.checkpoints / "skill_ratings.tsv";
        const bool once = argc > 1 && std::string(argv[1]) == "--once";
        uint64_t refinement_round = 0;
        std::cout << "[evaluator] deterministic 2v2 TrueSkill league; scale=40 rating/mu\n";

        do {
            auto ratings = load_ratings(ratings_path);
            const auto versions = discover_versions(versions_dir);
            // Introduce only one version at a time. Like RocketLearn, a new
            // checkpoint inherits the previous version's estimated mean but
            // receives wide uncertainty, then earns its place through games.
            if (ratings.empty() && !versions.empty()) {
                Rating r; r.version = versions.front(); r.mu = 0.0; r.sigma = 1.0;
                ratings[r.version] = r;
                save_ratings(ratings_path, ratings);
            } else {
                const auto unseen = std::find_if(versions.begin(), versions.end(),
                    [&](uint64_t version) { return !ratings.contains(version); });
                const bool existing_stable = ratings.size() == 1 || std::all_of(std::next(ratings.begin()), ratings.end(),
                    [](const auto& item) { return item.second.games >= 96 && item.second.sigma <= 2.0; });
                if (unseen != versions.end() && existing_stable) {
                    Rating r; r.version = *unseen; r.mu = ratings.rbegin()->second.mu; r.sigma = 25.0 / 3.0;
                    ratings[r.version] = r;
                    save_ratings(ratings_path, ratings);
                }
            }
            if (ratings.size() >= 2) {
                auto target = std::find_if(std::next(ratings.begin()), ratings.end(),
                    [](const auto& item) { return item.second.games < 96 || item.second.sigma > 2.0; });
                const bool refinement = target == ratings.end();
                if (refinement) target = std::prev(ratings.end());
                auto opponent = std::prev(target);
                if (refinement && ratings.size() > 2) {
                    ++refinement_round;
                    if (refinement_round % 3 == 1) {
                        // Re-test the newest policy against the strongest
                        // conservative checkpoint to expose forgetting/cycles.
                        opponent = std::max_element(ratings.begin(), target, [](const auto& a, const auto& b) {
                            return a.second.mu - 2.0 * a.second.sigma < b.second.mu - 2.0 * b.second.sigma;
                        });
                    } else if (refinement_round % 3 == 2) {
                        // TrueSkill gains the most information from a near-even
                        // opponent, as in RocketLearn's fairness sampling.
                        opponent = ratings.begin();
                        double best_gap = std::abs(opponent->second.mu - target->second.mu);
                        for (auto candidate = std::next(ratings.begin()); candidate != target; ++candidate) {
                            const double gap = std::abs(candidate->second.mu - target->second.mu);
                            if (gap < best_gap) { best_gap = gap; opponent = candidate; }
                        }
                    }
                }
                if (target == ratings.begin()) { std::this_thread::sleep_for(std::chrono::seconds(30)); continue; }
                const int games = target->second.games < 96 ? 32 : 16;
                std::cout << "[match] " << target->first << " vs " << opponent->first << " games=" << games << '\n';
                MatchStats result;
                try {
                    result = play_batch(cfg, versions_dir / (std::to_string(target->first) + ".pt"),
                                        versions_dir / (std::to_string(opponent->first) + ".pt"),
                                        target->first, games);
                } catch (const std::exception& e) {
                    // A checkpoint can be temporarily unavailable because of
                    // antivirus/indexing or an interrupted copy. Long-running
                    // evaluation must retry instead of silently dying.
                    std::cerr << "[match-warning] " << e.what() << "; retrying\n" << std::flush;
                    std::this_thread::sleep_for(std::chrono::seconds(10));
                    continue;
                }
                for (int8_t outcome : result.outcomes) {
                    if (outcome > 0) rate_win(target->second, opponent->second);
                    else if (outcome < 0) rate_win(opponent->second, target->second);
                }
                target->second.games += games; opponent->second.games += games;
                target->second.wins += result.wins; target->second.losses += result.losses; target->second.draws += result.draws;
                opponent->second.wins += result.losses; opponent->second.losses += result.wins; opponent->second.draws += result.draws;
                save_ratings(ratings_path, ratings);
                const double baseline = ratings.begin()->second.mu;
                std::cout << std::fixed << std::setprecision(3)
                          << "[rating] version=" << target->first
                          << " result=" << result.wins << '-' << result.losses << '-' << result.draws
                          << " mu=" << target->second.mu << " sigma=" << target->second.sigma
                          << " skill_rating=" << std::llround(40.0 * (target->second.mu - baseline)) << '\n' << std::flush;
            }
            if (!once) std::this_thread::sleep_for(std::chrono::seconds(30));
        } while (!once);
        return 0;
    } catch (const c10::Error& e) {
        std::cerr << "TORCH_ERROR: " << e.what() << '\n'; return 2;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << '\n'; return 1;
    }
}
