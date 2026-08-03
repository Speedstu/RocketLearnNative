#pragma once
#include "config.h"
#include "heatseeker_env.h"
#include "model.h"
#include "thread_pool.h"
#include <memory>
#include <random>

class Trainer {
public:
    explicit Trainer(Config config);
    void run(bool smoke);
private:
    Config cfg_;
    int actions_;
    torch::Device device_;
    ActorCritic net_;
    ActorCritic opponent_{nullptr};
    std::unique_ptr<torch::optim::Adam> optimizer_;
    std::vector<std::unique_ptr<HeatseekerEnv>> envs_;
    ThreadPool pool_;
    uint64_t global_steps_=0, update_=0;
    uint64_t opponent_version_=0;
    std::mt19937_64 league_rng_;
    void checkpoint(bool versioned);
    bool load_latest();
    bool refresh_opponent();
};
