#pragma once

#include "config.h"
#include "model.h"

#include <RocketSim.h>
#include <array>
#include <random>
#include <vector>

struct StepResult {
    std::array<float, 4> rewards{};
    bool done = false;
    bool goal = false;
    int scoring_team = -1;
    int touches = 0;
};

class SoccarEnv {
public:
    SoccarEnv(const Config& cfg, uint64_t seed);
    ~SoccarEnv();
    SoccarEnv(const SoccarEnv&) = delete;
    SoccarEnv& operator=(const SoccarEnv&) = delete;

    void reset(uint64_t global_steps);
    void observe(float* output) const;
    void action_masks(uint8_t* output, int action_count) const;
    StepResult step(const int64_t* actions, int action_count, uint64_t global_steps);
    static const std::vector<RocketSim::CarControls>& action_table();

private:
    const Config& cfg_;
    RocketSim::Arena* arena_ = nullptr;
    std::array<RocketSim::Car*, 4> cars_{};
    mutable std::mt19937_64 rng_;
    int episode_steps_ = 0;
    std::array<float, 4> previous_distance_{};
    std::array<uint64_t, 4> previous_hit_tick_{};
    RocketSim::BallState previous_ball_{};

    void build_one_obs(int agent, float* out) const;
    float shaped_reward(int agent, const RocketSim::CarState& car, const RocketSim::BallState& ball,
                        bool touched, float pre_ball_speed, bool goal, int scoring_team) const;
};
