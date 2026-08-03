#pragma once

#include "kuxir_config.h"
#include "model.h"

#include <RocketSim.h>
#include <cstdint>
#include <random>
#include <string>
#include <vector>

struct KuxirStepResult {
    int stage = 0;
    float reward = 0.f;
    bool done = false;
    bool goal = false;
    bool touched = false;
    bool wall_touch = false;
    bool setup_touch = false;
    bool aerial_commit = false;
    bool flip_attempt = false;
    bool flip_contact = false;
    bool developing_pinch = false;
    bool pinch = false;
    bool fast_pinch = false;
    bool pinch_goal = false;
    float pinch_speed = 0.f;
    float pinch_quality = 0.f;
    float touch_speed = 0.f;
    float inward_speed = 0.f;
    float touch_impulse = 0.f;
};

class KuxirEnv {
public:
    KuxirEnv(const KuxirConfig& cfg, uint64_t seed);
    ~KuxirEnv();
    KuxirEnv(const KuxirEnv&) = delete;
    KuxirEnv& operator=(const KuxirEnv&) = delete;

    void reset(uint64_t global_steps, int stage_override = -1);
    void observe(float* output) const;
    void action_mask(uint8_t* output, int action_count) const;
    KuxirStepResult step(int64_t action, int action_count, uint64_t global_steps);
    std::string rocketsimvis_json() const;
    bool state_is_sane() const;
    static const std::vector<RocketSim::CarControls>& action_table();

private:
    const KuxirConfig& cfg_;
    RocketSim::Arena* arena_ = nullptr;
    RocketSim::Car* car_ = nullptr;
    mutable std::mt19937_64 rng_;
    int episode_steps_ = 0;
    int stage_ = 0;
    int post_pinch_steps_ = -1;
    float previous_potential_ = 0.f;
    uint64_t previous_hit_tick_ = ~0ULL;
    bool last_pinch_ = false;
    bool setup_completed_ = false;
    bool drag_started_ = false;
    bool release_created_ = false;
    bool aerial_committed_ = false;
    bool flip_attempted_ = false;
    float last_pinch_speed_ = 0.f;
    RocketSim::BallState previous_ball_{};

    float potential(const RocketSim::CarState& car, const RocketSim::BallState& ball) const;
    static int curriculum_stage(uint64_t global_steps, std::mt19937_64& rng);
};
