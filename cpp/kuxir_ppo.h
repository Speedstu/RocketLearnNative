#pragma once

#include "kuxir_config.h"
#include "kuxir_env.h"
#include "model.h"
#include "thread_pool.h"

#include <memory>

class KuxirTrainer {
public:
    explicit KuxirTrainer(KuxirConfig config);
    void run(bool smoke, int benchmark_updates = 0);

private:
    KuxirConfig cfg_;
    int actions_;
    torch::Device device_;
    ActorCritic net_;
    std::unique_ptr<torch::optim::Adam> optimizer_;
    std::vector<std::unique_ptr<KuxirEnv>> envs_;
    ThreadPool pool_;
    uint64_t global_steps_ = 0;
    uint64_t update_ = 0;

    bool load_latest();
    void checkpoint(bool versioned);
};
