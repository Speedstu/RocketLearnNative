#pragma once

#include <torch/torch.h>

constexpr int kObsSize = 128;

struct ActorCriticImpl : torch::nn::Module {
    torch::nn::Linear fc1{nullptr}, fc2{nullptr}, fc3{nullptr}, actor{nullptr}, critic{nullptr};
    torch::nn::LayerNorm ln1{nullptr}, ln2{nullptr};

    explicit ActorCriticImpl(int actions)
        : fc1(register_module("fc1", torch::nn::Linear(kObsSize, 512))),
          fc2(register_module("fc2", torch::nn::Linear(512, 512))),
          fc3(register_module("fc3", torch::nn::Linear(512, 256))),
          actor(register_module("actor", torch::nn::Linear(256, actions))),
          critic(register_module("critic", torch::nn::Linear(256, 1))),
          ln1(register_module("ln1", torch::nn::LayerNorm(torch::nn::LayerNormOptions({512})))),
          ln2(register_module("ln2", torch::nn::LayerNorm(torch::nn::LayerNormOptions({512})))) {
        for (auto& module : modules(false)) {
            if (auto* linear = module->as<torch::nn::Linear>()) {
                torch::nn::init::orthogonal_(linear->weight, std::sqrt(2.0));
                torch::nn::init::constant_(linear->bias, 0.0);
            }
        }
        torch::nn::init::orthogonal_(actor->weight, 0.01);
        torch::nn::init::orthogonal_(critic->weight, 1.0);
    }

    std::pair<torch::Tensor, torch::Tensor> forward(torch::Tensor x) {
        x = torch::silu(ln1(fc1(x)));
        x = torch::silu(ln2(fc2(x)));
        x = torch::silu(fc3(x));
        return {actor(x), critic(x).squeeze(-1)};
    }
};
TORCH_MODULE(ActorCritic);

