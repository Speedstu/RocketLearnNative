#pragma once

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <thread>

struct KuxirConfig {
    int envs = 512;
    int env_threads = 12;
    int tick_skip = 4;
    int rollout_decisions = 256;
    int epochs = 3;
    int minibatch = 32768;
    int save_every_updates = 10;
    int version_every_updates = 100;
    int max_episode_decisions = 300;
    int seed = 7331;
    float gamma = 0.995f;
    float gae_lambda = 0.95f;
    float clip = 0.2f;
    float entropy = 0.018f;
    float value_coef = 0.5f;
    float lr = 1.5e-4f;
    float max_grad_norm = 0.5f;
    std::filesystem::path meshes = "collision_meshes";
    std::filesystem::path checkpoints = "checkpoints/kuxir_pinch_from_scratch";

    static int env_int(const char* name, int fallback) {
        if (const char* value = std::getenv(name)) try { return std::stoi(value); } catch (...) {}
        return fallback;
    }
    static float env_float(const char* name, float fallback) {
        if (const char* value = std::getenv(name)) try { return std::stof(value); } catch (...) {}
        return fallback;
    }
    static std::filesystem::path env_path(const char* name, std::filesystem::path fallback) {
        if (const char* value = std::getenv(name); value && *value) return value;
        return fallback;
    }
    static KuxirConfig load() {
        KuxirConfig c;
        c.envs = env_int("RLK_ENVS", c.envs);
        c.env_threads = env_int("RLK_ENV_THREADS", c.env_threads);
        c.tick_skip = env_int("RLK_TICK_SKIP", c.tick_skip);
        c.rollout_decisions = env_int("RLK_ROLLOUT_DECISIONS", c.rollout_decisions);
        c.epochs = env_int("RLK_EPOCHS", c.epochs);
        c.minibatch = env_int("RLK_MINIBATCH", c.minibatch);
        c.save_every_updates = env_int("RLK_SAVE_EVERY", c.save_every_updates);
        c.version_every_updates = env_int("RLK_VERSION_EVERY", c.version_every_updates);
        c.max_episode_decisions = env_int("RLK_MAX_EPISODE_DECISIONS", c.max_episode_decisions);
        c.seed = env_int("RLK_SEED", c.seed);
        c.gamma = env_float("RLK_GAMMA", c.gamma);
        c.gae_lambda = env_float("RLK_GAE_LAMBDA", c.gae_lambda);
        c.clip = env_float("RLK_CLIP", c.clip);
        c.entropy = env_float("RLK_ENTROPY", c.entropy);
        c.value_coef = env_float("RLK_VALUE_COEF", c.value_coef);
        c.lr = env_float("RLK_LR", c.lr);
        c.max_grad_norm = env_float("RLK_MAX_GRAD_NORM", c.max_grad_norm);
        c.meshes = env_path("RLK_MESHES", c.meshes);
        c.checkpoints = env_path("RLK_CHECKPOINTS", c.checkpoints);
        c.envs = std::max(1, c.envs);
        c.env_threads = std::clamp(c.env_threads, 1, c.envs);
        c.minibatch = std::max(1024, c.minibatch);
        c.max_episode_decisions = std::max(32, c.max_episode_decisions);
        return c;
    }
};
