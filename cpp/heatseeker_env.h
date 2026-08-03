#pragma once

#include "config.h"
#include "model.h"

#include <RocketSim.h>
#include <array>
#include <memory>
#include <random>
#include <vector>

struct StepResult {
    std::array<float, 4> rewards{};
    bool done = false;
    bool goal = false;
    int scoring_team = -1;
    int touches = 0;
};

class HeatseekerEnv {
public:
    HeatseekerEnv(const Config& cfg, uint64_t seed);
    ~HeatseekerEnv();
    HeatseekerEnv(const HeatseekerEnv&) = delete;
    HeatseekerEnv& operator=(const HeatseekerEnv&) = delete;

    void reset(uint64_t global_steps, int kickoff_percent_override = -1);
    void observe(float* output) const;
    void action_masks(uint8_t* output, int action_count) const;
    StepResult step(const int64_t* actions, int action_count, uint64_t global_steps);
    std::string rocketsimvis_json() const;
    static const std::vector<RocketSim::CarControls>& action_table();
    RocketSim::BallState ball_state() const { return arena_->ball->GetState(); }

private:
    const Config& cfg_;
    RocketSim::Arena* arena_ = nullptr;
    std::array<RocketSim::Car*, 4> cars_{};
    mutable std::mt19937_64 rng_;
    int episode_steps_ = 0;
    int no_touch_steps_ = 0;
    std::array<float, 4> previous_distance_{};
    std::array<uint64_t, 4> previous_hit_tick_{};
    RocketSim::BallState previous_ball_{};

    void build_one_obs(int agent, float* out) const;
    float shaped_reward(int agent, const RocketSim::CarState& car, const RocketSim::BallState& ball,
                        bool touched, float pre_ball_speed, bool goal, int scoring_team) const;
};
