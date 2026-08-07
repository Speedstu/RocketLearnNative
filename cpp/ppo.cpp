#include "ppo.h"
#include <torch/cuda.h>
#include <c10/cuda/CUDAFunctions.h>
#include <c10/macros/Export.h>
#include <cuda_runtime_api.h>
#include <chrono>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <algorithm>
#include <random>

using torch::indexing::Slice;
namespace at::cuda { TORCH_CUDA_CPP_API cudaDeviceProp* getCurrentDeviceProperties(); }

Trainer::Trainer(Config config)
    : cfg_(std::move(config)), actions_(static_cast<int>(SoccarEnv::action_table().size())),
      device_(c10::cuda::device_count()>0?torch::kCUDA:torch::kCPU), net_(actions_), pool_(cfg_.env_threads),
      league_rng_(cfg_.seed ^ 0x9e3779b97f4a7c15ULL) {
    torch::set_num_threads(1);
    if (device_.is_cuda()) (void)at::cuda::getCurrentDeviceProperties();
    net_->to(device_);
    optimizer_=std::make_unique<torch::optim::Adam>(net_->parameters(),torch::optim::AdamOptions(cfg_.lr).eps(1e-5));
    envs_.reserve(cfg_.envs);
    for(int i=0;i<cfg_.envs;++i) envs_.push_back(std::make_unique<SoccarEnv>(cfg_,cfg_.seed+i*7919ULL));
    std::filesystem::create_directories(cfg_.checkpoints/"versions");
    load_latest();
}

bool Trainer::refresh_opponent() {
    const auto dir = cfg_.checkpoints / "versions";
    std::vector<std::pair<uint64_t, std::filesystem::path>> versions;
    if (!std::filesystem::exists(dir)) return false;
    for (const auto& entry : std::filesystem::directory_iterator(dir)) {
        if (!entry.is_regular_file() || entry.path().extension() != ".pt") continue;
        try { versions.emplace_back(std::stoull(entry.path().stem().string()), entry.path()); } catch (...) {}
    }
    if (versions.empty()) return false;
    std::sort(versions.begin(), versions.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    const size_t recent_begin = versions.size() > 8 ? versions.size() - 8 : 0;
    size_t chosen = versions.size() - 1;
    if ((league_rng_() & 1ULL) && chosen > recent_begin)
        chosen = std::uniform_int_distribution<size_t>(recent_begin, chosen)(league_rng_);
    try {
        ActorCritic loaded(actions_);
        torch::serialize::InputArchive archive;
        archive.load_from(versions[chosen].second.string(), torch::kCPU);
        loaded->load(archive);
        loaded->to(device_);
        loaded->eval();
        opponent_ = loaded;
        opponent_version_ = versions[chosen].first;
        return true;
    } catch (const std::exception& e) {
        std::cerr << "[league-warning] unable to load " << versions[chosen].second << ": " << e.what() << '\n';
        return false;
    }
}

bool Trainer::load_latest(){
    auto path=cfg_.checkpoints/"latest.pt"; if(!std::filesystem::exists(path))return false;
    try{torch::serialize::InputArchive ar;ar.load_from(path.string());net_->load(ar);optimizer_->load(ar);torch::Tensor meta;ar.read("meta",meta);global_steps_=meta[0].item<int64_t>();update_=meta[1].item<int64_t>();std::cout<<"[resume] steps="<<global_steps_<<" update="<<update_<<'\n';return true;}catch(const std::exception&e){std::cerr<<"[resume-warning] "<<e.what()<<'\n';return false;}
}

void Trainer::checkpoint(bool versioned){
    torch::serialize::OutputArchive ar;net_->save(ar);optimizer_->save(ar);ar.write("meta",torch::tensor({(int64_t)global_steps_,(int64_t)update_}));
    auto tmp=cfg_.checkpoints/"latest.tmp.pt", dst=cfg_.checkpoints/"latest.pt";ar.save_to(tmp.string());
    std::error_code ec;std::filesystem::remove(dst,ec);std::filesystem::rename(tmp,dst);
    if(versioned){
        auto v=cfg_.checkpoints/"versions"/(std::to_string(global_steps_)+".pt");
        auto vtmp=std::filesystem::path(v.string()+".tmp");
        std::filesystem::copy_file(dst,vtmp,std::filesystem::copy_options::overwrite_existing);
        std::error_code vec;std::filesystem::remove(v,vec);vec.clear();std::filesystem::rename(vtmp,v,vec);
        if(vec)throw std::runtime_error("atomic version checkpoint failed: "+vec.message());
    }
}

void Trainer::run(bool smoke){
    const int E=cfg_.envs,A=4,T=smoke?2:cfg_.rollout_decisions,N=E*A*T;
    if(smoke){cfg_.epochs=1;cfg_.minibatch=N;}
    auto cpu_f=torch::TensorOptions().dtype(torch::kFloat32).device(torch::kCPU);
    auto cpu_l=torch::TensorOptions().dtype(torch::kInt64).device(torch::kCPU);
    auto cpu_b=torch::TensorOptions().dtype(torch::kBool).device(torch::kCPU);
    std::cout<<"[native] device="<<(device_.is_cuda()?"cuda":"cpu")<<" envs="<<E<<" threads="<<cfg_.env_threads<<" actions="<<actions_<<" obs="<<kObsSize<<'\n';
    for(;;){
        auto start=std::chrono::steady_clock::now();
        if (!opponent_ || update_ % cfg_.opponent_refresh_updates == 0) refresh_opponent();
        std::vector<uint8_t> league_env(E, 0), current_blue(E, 1);
        std::vector<int64_t> opponent_rows;
        int league_count = 0;
        if (opponent_) {
            std::bernoulli_distribution use_past(cfg_.past_version_prob), blue_side(0.5);
            for (int e = 0; e < E; ++e) {
                league_env[e] = use_past(league_rng_);
                current_blue[e] = blue_side(league_rng_);
                if (!league_env[e]) continue;
                ++league_count;
                const int old_start = current_blue[e] ? 2 : 0;
                opponent_rows.push_back(e * 4 + old_start);
                opponent_rows.push_back(e * 4 + old_start + 1);
            }
        }
        auto obs=torch::empty({T,E,4,kObsSize},cpu_f),masks=torch::empty({T,E,4,actions_},cpu_b),acts=torch::empty({T,E,4},cpu_l);
        auto oldlp=torch::empty({T,E,4},cpu_f),vals=torch::empty({T,E,4},cpu_f),rews=torch::empty({T,E,4},cpu_f),dones=torch::empty({T,E},cpu_b),learn=torch::ones({T,E,4},cpu_b);
        auto* learn_ptr=reinterpret_cast<uint8_t*>(learn.data_ptr<bool>());
        for (int t = 0; t < T; ++t) for (int e = 0; e < E; ++e) if (league_env[e]) {
            const int old_start = current_blue[e] ? 2 : 0;
            learn_ptr[(t * E + e) * 4 + old_start] = 0;
            learn_ptr[(t * E + e) * 4 + old_start + 1] = 0;
        }
        torch::Tensor opponent_index;
        if (!opponent_rows.empty()) opponent_index = torch::tensor(opponent_rows, cpu_l).to(device_);
        int goals=0,touches=0;
        for(int t=0;t<T;++t){
            float* op=obs[t].data_ptr<float>();uint8_t* mp=(uint8_t*)masks[t].data_ptr<bool>();
            pool_.parallel_for(E,[&](int e){envs_[e]->observe(op+e*4*kObsSize);envs_[e]->action_masks(mp+e*4*actions_,actions_);});
            torch::NoGradGuard ng;
            auto x=obs[t].reshape({E*4,kObsSize}).to(device_,true);auto mask=masks[t].reshape({E*4,actions_}).to(device_,true);
            auto [logits,value]=net_->forward(x);logits=logits.masked_fill(mask.logical_not(),-1e9);
            auto probs=torch::softmax(logits,-1);auto action=probs.multinomial(1).squeeze(-1);auto lp=torch::log_softmax(logits,-1).gather(1,action.unsqueeze(1)).squeeze(1);
            if (!opponent_rows.empty()) {
                auto old_obs=x.index_select(0,opponent_index),old_mask=mask.index_select(0,opponent_index);
                auto old_logits=opponent_->forward(old_obs).first.masked_fill(old_mask.logical_not(),-1e9);
                auto old_action=torch::softmax(old_logits,-1).multinomial(1).squeeze(-1);
                action.index_put_({opponent_index},old_action);
            }
            acts[t].copy_(action.reshape({E,4}).cpu());oldlp[t].copy_(lp.reshape({E,4}).cpu());vals[t].copy_(value.reshape({E,4}).cpu());
            auto* ap=acts[t].data_ptr<int64_t>();auto* rp=rews[t].data_ptr<float>();auto* dp=(uint8_t*)dones[t].data_ptr<bool>();
            std::vector<StepResult> results(E);
            pool_.parallel_for(E,[&](int e){results[e]=envs_[e]->step(ap+e*4,actions_,global_steps_);});
            for(int e=0;e<E;++e){for(int a=0;a<4;++a)rp[e*4+a]=results[e].rewards[a];dp[e]=results[e].done;goals+=results[e].goal;touches+=results[e].touches;}
            global_steps_+=E*4;
        }
        auto nextobs=torch::empty({E,4,kObsSize},cpu_f);pool_.parallel_for(E,[&](int e){envs_[e]->observe(nextobs.data_ptr<float>()+e*4*kObsSize);});
        torch::Tensor nextv;{torch::NoGradGuard ng;nextv=net_->forward(nextobs.reshape({E*4,kObsSize}).to(device_)).second.reshape({E,4}).cpu();}
        auto adv=torch::zeros_like(rews),last=torch::zeros({E,4},cpu_f);
        for(int t=T-1;t>=0;--t){auto nonterm=dones[t].logical_not().to(torch::kFloat32).unsqueeze(-1);auto nv=t==T-1?nextv:vals[t+1];auto delta=rews[t]+cfg_.gamma*nv*nonterm-vals[t];last=delta+cfg_.gamma*cfg_.gae_lambda*nonterm*last;adv[t]=last;}
        auto returns=adv+vals;
        auto valid=learn.reshape({N}).nonzero().squeeze(1);
        auto flatobs=obs.reshape({N,kObsSize}).index_select(0,valid).to(device_),flatmask=masks.reshape({N,actions_}).index_select(0,valid).to(device_),flatact=acts.reshape({N}).index_select(0,valid).to(device_);
        auto flatlp=oldlp.reshape({N}).index_select(0,valid).to(device_),flatret=returns.reshape({N}).index_select(0,valid).to(device_),flatadv=adv.reshape({N}).index_select(0,valid).to(device_);
        const int train_n=static_cast<int>(flatadv.size(0));
        flatadv=(flatadv-flatadv.mean())/(flatadv.std()+1e-8);
        double polsum=0,valsum=0,entsum=0,klsum=0;int batches=0;
        net_->train();
        for(int epoch=0;epoch<cfg_.epochs;++epoch){auto order=torch::randperm(train_n,torch::TensorOptions().dtype(torch::kInt64).device(device_));for(int begin=0;begin<train_n;begin+=cfg_.minibatch){int end=std::min(train_n,begin+cfg_.minibatch);auto idx=order.index({Slice(begin,end)});auto [logits,value]=net_->forward(flatobs.index_select(0,idx));auto bm=flatmask.index_select(0,idx);logits=logits.masked_fill(bm.logical_not(),-1e9);auto logpall=torch::log_softmax(logits,-1),probs=torch::softmax(logits,-1);auto nlp=logpall.gather(1,flatact.index_select(0,idx).unsqueeze(1)).squeeze(1);auto olp=flatlp.index_select(0,idx);auto ratio=(nlp-olp).exp();auto ba=flatadv.index_select(0,idx);auto pg1=ratio*ba,pg2=torch::clamp(ratio,1-cfg_.clip,1+cfg_.clip)*ba;auto pl=-torch::minimum(pg1,pg2).mean();auto vl=torch::mse_loss(value,flatret.index_select(0,idx));auto ent=-(probs*logpall).sum(-1).mean();auto loss=pl+cfg_.value_coef*vl-cfg_.entropy*ent;optimizer_->zero_grad();loss.backward();torch::nn::utils::clip_grad_norm_(net_->parameters(),cfg_.max_grad_norm);optimizer_->step();polsum+=pl.item<double>();valsum+=vl.item<double>();entsum+=ent.item<double>();klsum+=(olp-nlp).mean().item<double>();++batches;}}
        ++update_;auto elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();double sps=N/elapsed;
        std::cout<<std::fixed<<std::setprecision(4)<<"[update "<<update_<<"] steps="<<global_steps_<<" sps="<<std::setprecision(0)<<sps<<std::setprecision(4)<<" reward="<<rews.mean().item<float>()<<" goals="<<goals<<" touches="<<touches<<" policy="<<polsum/batches<<" value="<<valsum/batches<<" entropy="<<entsum/batches<<" kl="<<klsum/batches<<" past="<<opponent_version_<<" league_envs="<<league_count<<'\n'<<std::flush;
        if(smoke){checkpoint(false);return;}if(update_%cfg_.save_every_updates==0)checkpoint(update_%cfg_.version_every_updates==0);
    }
}
