#pragma once

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <thread>

struct Config {
    int envs = 96;
    int env_threads = 8;
    int tick_skip = 8;
    int rollout_decisions = 256;
    int epochs = 3;
    int minibatch = 32768;
    int save_every_updates = 10;
    int version_every_updates = 100;
    int opponent_refresh_updates = 10;
    int max_episode_decisions = 900;
    int seed = 1337;
    float gamma = 0.995f;
    float gae_lambda = 0.95f;
    float clip = 0.2f;
    float entropy = 0.015f;
    float value_coef = 0.5f;
    float lr = 1.5e-4f;
    float max_grad_norm = 0.5f;
    float past_version_prob = 0.20f;
    std::filesystem::path meshes = "collision_meshes";
    std::filesystem::path checkpoints = "checkpoints/soccar_2v2_from_scratch";

    static int env_int(const char* name, int fallback) {
        if (const char* s = std::getenv(name)) try { return std::stoi(s); } catch (...) {}
        return fallback;
    }
    static float env_float(const char* name, float fallback) {
        if (const char* s = std::getenv(name)) try { return std::stof(s); } catch (...) {}
        return fallback;
    }
    static std::filesystem::path env_path(const char* name, std::filesystem::path fallback) {
        if (const char* s = std::getenv(name); s && *s) return s;
        return fallback;
    }
    static Config load() {
        Config c;
        c.envs = env_int("RLN_ENVS", c.envs);
        c.env_threads = env_int("RLN_ENV_THREADS", std::min<int>(8, std::max(1u, std::thread::hardware_concurrency())));
        c.tick_skip = env_int("RLN_TICK_SKIP", c.tick_skip);
        c.rollout_decisions = env_int("RLN_ROLLOUT_DECISIONS", c.rollout_decisions);
        c.epochs = env_int("RLN_EPOCHS", c.epochs);
        c.minibatch = env_int("RLN_MINIBATCH", c.minibatch);
        c.save_every_updates = env_int("RLN_SAVE_EVERY", c.save_every_updates);
        c.version_every_updates = env_int("RLN_VERSION_EVERY", c.version_every_updates);
        c.opponent_refresh_updates = env_int("RLN_OPPONENT_REFRESH", c.opponent_refresh_updates);
        c.max_episode_decisions = env_int("RLN_MAX_EPISODE_DECISIONS", c.max_episode_decisions);
        c.seed = env_int("RLN_SEED", c.seed);
        c.gamma = env_float("RLN_GAMMA", c.gamma);
        c.gae_lambda = env_float("RLN_GAE_LAMBDA", c.gae_lambda);
        c.clip = env_float("RLN_CLIP", c.clip);
        c.entropy = env_float("RLN_ENTROPY", c.entropy);
        c.value_coef = env_float("RLN_VALUE_COEF", c.value_coef);
        c.lr = env_float("RLN_LR", c.lr);
        c.max_grad_norm = env_float("RLN_MAX_GRAD_NORM", c.max_grad_norm);
        c.past_version_prob = env_float("RLN_PAST_VERSION_PROB", c.past_version_prob);
        c.meshes = env_path("RLN_MESHES", c.meshes);
        c.checkpoints = env_path("RLN_CHECKPOINTS", c.checkpoints);
        c.envs = std::max(1, c.envs);
        c.env_threads = std::clamp(c.env_threads, 1, c.envs);
        c.tick_skip = std::max(1, c.tick_skip);
        c.rollout_decisions = std::max(1, c.rollout_decisions);
        c.minibatch = std::max(1, c.minibatch);
        c.max_episode_decisions = std::max(1, c.max_episode_decisions);
        c.past_version_prob = std::clamp(c.past_version_prob, 0.0f, 0.5f);
        c.opponent_refresh_updates = std::max(1, c.opponent_refresh_updates);
        return c;
    }
};
