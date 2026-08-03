#include "kuxir_env.h"

#include <RLConst.h>
#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>

using namespace RocketSim;

namespace {
float dot(const Vec& a, const Vec& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
float length(const Vec& value) { return std::sqrt(dot(value, value)); }
Vec normalized(const Vec& value) { const float size = length(value); return size > 1e-5f ? value / size : Vec{}; }
float clamp01(float value) { return std::clamp(value, 0.f, 1.f); }
float clamp11(float value) { return std::clamp(value, -1.f, 1.f); }
float sign_nonzero(float value) { return value >= 0.f ? 1.f : -1.f; }
bool finite_vec(const Vec& value) { return std::isfinite(value.x) && std::isfinite(value.y) && std::isfinite(value.z); }
void put_vec(float*& out, const Vec& value, float scale) {
    *out++ = value.x * scale; *out++ = value.y * scale; *out++ = value.z * scale;
}
}

const std::vector<CarControls>& KuxirEnv::action_table() {
    static const std::vector<CarControls> actions = [] {
        std::vector<CarControls> result;
        auto add = [&](float throttle, float steer, float pitch, float yaw, float roll,
                       bool jump, bool boost, bool handbrake) {
            CarControls c;
            c.throttle = throttle; c.steer = steer; c.pitch = pitch; c.yaw = yaw; c.roll = roll;
            c.jump = jump; c.boost = boost; c.handbrake = handbrake;
            result.push_back(c);
        };
        add(0, 0, 0, 0, 0, false, false, false);
        for (float throttle : {-1.f, 0.f, 1.f}) for (float steer : {-1.f, -0.5f, 0.f, 0.5f, 1.f}) {
            if (throttle == 0.f && steer == 0.f) continue;
            add(throttle, steer, 0, steer, 0, false, false, std::abs(steer) > 0.75f && throttle >= 0.f);
            if (throttle > 0.f) add(throttle, steer, 0, steer, 0, false, true, false);
        }
        for (float pitch : {-1.f, 0.f, 1.f}) for (float yaw : {-1.f, 0.f, 1.f}) for (float roll : {-1.f, 0.f, 1.f}) {
            if (pitch == 0.f && yaw == 0.f && roll == 0.f) continue;
            add(1, yaw, pitch, yaw, roll, false, false, false);
            add(1, yaw, pitch, yaw, roll, false, true, false);
        }
        for (float pitch : {-1.f, 0.f, 1.f}) for (float yaw : {-1.f, 0.f, 1.f}) {
            add(1, yaw, pitch, yaw, 0, true, false, false);
            add(1, yaw, pitch, yaw, 0, true, true, false);
        }
        return result;
    }();
    return actions;
}

KuxirEnv::KuxirEnv(const KuxirConfig& cfg, uint64_t seed) : cfg_(cfg), rng_(seed) {
    arena_ = Arena::Create(GameMode::SOCCAR);
    car_ = arena_->AddCar(Team::BLUE);
    auto mutator = arena_->GetMutatorConfig();
    mutator.boostUsedPerSecond = RLConst::BOOST_USED_PER_SECOND;
    mutator.carSpawnBoostAmount = 35.f;
    mutator.demoMode = DemoMode::DISABLED;
    arena_->SetMutatorConfig(mutator);
    reset(0);
}

KuxirEnv::~KuxirEnv() { delete arena_; }

int KuxirEnv::curriculum_stage(uint64_t steps, std::mt19937_64& rng) {
    const int roll = std::uniform_int_distribution<int>(0, 99)(rng);
    if (steps < 100'000'000ULL) return 0;
    if (steps < 300'000'000ULL) return roll < 70 ? 0 : 1;
    if (steps < 800'000'000ULL) return roll < 40 ? 0 : (roll < 85 ? 1 : 2);
    return roll < 20 ? 0 : (roll < 50 ? 1 : 2);
}

void KuxirEnv::reset(uint64_t global_steps, int stage_override) {
    arena_->ResetToRandomKickoff(static_cast<int>(rng_()));
    episode_steps_ = 0;
    post_pinch_steps_ = -1;
    last_pinch_ = false;
    setup_completed_ = false;
    drag_started_ = false;
    release_created_ = false;
    aerial_committed_ = false;
    flip_attempted_ = false;
    last_pinch_speed_ = 0.f;
    stage_ = stage_override >= 0 ? std::clamp(stage_override, 0, 2) : curriculum_stage(global_steps, rng_);

    const float side = (rng_() & 1ULL) ? 1.f : -1.f;
    std::uniform_real_distribution<float> unit(0.f, 1.f);
    BallState ball = arena_->ball->GetState();
    CarState car = car_->GetState();
    ball.angVel = Vec{};
    car.angVel = Vec{};
    car.boost = 15.f + unit(rng_) * 30.f;

    // Every stage is the same real Kuxir setup: car and ball on the ground,
    // perfectly normal (90 degrees) to the side wall, car directly behind the
    // ball. Difficulty only changes distance and initial momentum.
    const float y = -3000.f + unit(rng_) * 3800.f;
    float wall_distance, car_gap, ball_speed, car_speed;
    if (stage_ == 0) {
        wall_distance = 2600.f + unit(rng_) * 600.f;
        car_gap = 450.f + unit(rng_) * 200.f;
        ball_speed = 300.f + unit(rng_) * 300.f;
        car_speed = 850.f + unit(rng_) * 500.f;
    } else if (stage_ == 1) {
        wall_distance = 3200.f + unit(rng_) * 550.f;
        car_gap = 600.f + unit(rng_) * 300.f;
        ball_speed = 120.f + unit(rng_) * 280.f;
        car_speed = 650.f + unit(rng_) * 450.f;
    } else {
        // Keep the ball on the selected half so its x sign remains the wall side.
        wall_distance = 3600.f + unit(rng_) * 350.f;
        car_gap = 800.f + unit(rng_) * 350.f;
        ball_speed = unit(rng_) * 220.f;
        car_speed = 450.f + unit(rng_) * 400.f;
    }
    const float ball_x = side * (RLConst::ARENA_EXTENT_X - wall_distance);
    const Vec outward(side, 0, 0);
    ball.pos = Vec(ball_x, y, RLConst::BALL_REST_Z);
    ball.vel = outward * ball_speed;
    ball.angVel = Vec(0, ball.vel.x / RLConst::BALL_COLLISION_RADIUS_SOCCAR, 0);
    car.pos = Vec(ball_x - side * car_gap, y, RLConst::CAR_SPAWN_REST_Z);
    car.rotMat = RotMat::LookAt(outward, Vec(0, 0, 1));
    car.vel = outward * car_speed;

    arena_->ball->SetState(ball);
    car_->SetState(car);
    // Resolve ground suspension once before exposing the state.
    arena_->Step(1);
    previous_ball_ = arena_->ball->GetState();
    const auto current_car = car_->GetState();
    previous_hit_tick_ = current_car.ballHitInfo.tickCountWhenHit;
    previous_potential_ = potential(current_car, previous_ball_);
}

float KuxirEnv::potential(const CarState& car, const BallState& ball) const {
    const Vec to_ball = ball.pos - car.pos;
    const float distance = length(to_ball);
    const float side = sign_nonzero(ball.pos.x);
    const float wall_gap = RLConst::ARENA_EXTENT_X - std::abs(ball.pos.x);
    const float facing = clamp01((dot(car.rotMat.forward, normalized(to_ball)) + 0.2f) / 1.2f);
    const float proximity = std::exp(-distance / 1200.f);
    const float behind = clamp01(side * (ball.pos.x - car.pos.x) / 450.f);
    const float control = std::exp(-distance / 500.f) * facing * behind;
    const float closing = clamp01((dot(car.vel - ball.vel, normalized(to_ball)) + 300.f) / 1800.f);
    if (release_created_) {
        return 0.35f * proximity + 0.35f * facing + 0.30f * closing;
    }
    if (drag_started_ && wall_gap < 1200.f) {
        const float spacing = std::exp(-std::abs(distance - 480.f) / 260.f) * behind;
        return 0.20f * proximity + 0.25f * facing + 0.20f * closing + 0.35f * spacing;
    }
    return 0.25f * proximity + 0.25f * facing + 0.20f * closing + 0.30f * control;
}

bool KuxirEnv::state_is_sane() const {
    const auto car = car_->GetState();
    const auto ball = arena_->ball->GetState();
    const bool bounds_ok = finite_vec(car.pos) && finite_vec(car.vel) && finite_vec(ball.pos) && finite_vec(ball.vel) &&
           std::abs(car.pos.x) < RLConst::ARENA_EXTENT_X + 25.f &&
           std::abs(car.pos.y) < RLConst::ARENA_EXTENT_Y + 25.f && car.pos.z > -25.f && car.pos.z < 2150.f &&
           std::abs(ball.pos.x) < RLConst::ARENA_EXTENT_X + 120.f &&
           std::abs(ball.pos.y) < RLConst::ARENA_EXTENT_Y + 120.f && ball.pos.z > 0.f && ball.pos.z < 2200.f;
    if (!bounds_ok) return false;
    if (episode_steps_ == 0) {
        const float side = sign_nonzero(ball.pos.x);
        return car.pos.z < 80.f && ball.pos.z < 150.f &&
               std::abs(car.pos.y - ball.pos.y) < 5.f &&
               side * (ball.pos.x - car.pos.x) > 180.f &&
               dot(car.rotMat.forward, Vec(side, 0, 0)) > 0.995f;
    }
    return true;
}

void KuxirEnv::observe(float* output) const {
    std::fill(output, output + kObsSize, 0.f);
    float* out = output;
    const auto car = car_->GetState();
    const auto ball = arena_->ball->GetState();
    put_vec(out, car.pos, 1.f / 5500.f);
    put_vec(out, car.vel, 1.f / 2300.f);
    put_vec(out, car.angVel, 1.f / 5.5f);
    put_vec(out, car.rotMat.forward, 1.f);
    put_vec(out, car.rotMat.right, 1.f);
    put_vec(out, car.rotMat.up, 1.f);
    *out++ = car.boost / 100.f;
    *out++ = car.isOnGround;
    *out++ = car.hasJumped;
    *out++ = car.hasDoubleJumped;
    *out++ = car.hasFlipped;
    *out++ = car.isFlipping;
    *out++ = clamp01(car.jumpTime / 0.25f);
    *out++ = clamp01(car.flipTime / 0.7f);
    *out++ = clamp01(car.airTime / 2.f);
    put_vec(out, ball.pos, 1.f / 5500.f);
    put_vec(out, ball.vel, 1.f / 6000.f);
    put_vec(out, ball.angVel, 1.f / 6.f);
    const Vec relative = ball.pos - car.pos;
    const Vec relative_velocity = ball.vel - car.vel;
    put_vec(out, relative, 1.f / 7000.f);
    put_vec(out, relative_velocity, 1.f / 7000.f);
    *out++ = clamp01(length(relative) / 6000.f);
    *out++ = clamp11(dot(car.rotMat.forward, normalized(relative)));
    const float side = sign_nonzero(ball.pos.x);
    *out++ = side;
    *out++ = clamp01((RLConst::ARENA_EXTENT_X - std::abs(ball.pos.x)) / 1800.f);
    *out++ = clamp01((RLConst::ARENA_EXTENT_X - std::abs(car.pos.x)) / 1800.f);
    *out++ = clamp11(-side * ball.vel.x / 3000.f);
    *out++ = clamp11(ball.vel.y / 6000.f);
    *out++ = clamp11(ball.vel.z / 3000.f);
    const Vec goal(0, RLConst::ARENA_EXTENT_Y, 320.f);
    const Vec to_goal = goal - ball.pos;
    put_vec(out, to_goal, 1.f / 11000.f);
    *out++ = clamp11(dot(normalized(ball.vel), normalized(to_goal)));
    *out++ = clamp01(length(ball.vel) / 6000.f);
    // Explicit mechanic phase: ground drag, released spacing, aerial commit.
    *out++ = release_created_ ? 0.f : 1.f;
    *out++ = release_created_ && !aerial_committed_ ? 1.f : 0.f;
    *out++ = aerial_committed_ ? 1.f : 0.f;
    *out++ = clamp01(episode_steps_ / static_cast<float>(cfg_.max_episode_decisions));
    *out++ = last_pinch_;
    *out++ = clamp01(last_pinch_speed_ / 6000.f);
    const auto& controls = car.lastControls;
    *out++ = controls.throttle; *out++ = controls.steer; *out++ = controls.pitch;
    *out++ = controls.yaw; *out++ = controls.roll; *out++ = controls.jump;
    *out++ = controls.boost; *out++ = controls.handbrake;
    for (float horizon : {0.10f, 0.25f, 0.50f}) {
        const Vec future = ball.pos + ball.vel * horizon;
        put_vec(out, future - car.pos, 1.f / 7000.f);
    }
}

void KuxirEnv::action_mask(uint8_t* output, int action_count) const {
    const auto car = car_->GetState();
    const auto& actions = action_table();
    for (int i = 0; i < action_count; ++i) {
        const auto& action = actions[i];
        bool valid = true;
        if (car.isOnGround && !action.jump && (std::abs(action.pitch) > 0.1f || std::abs(action.roll) > 0.1f)) valid = false;
        if (!car.isOnGround && action.handbrake) valid = false;
        if (!car.HasFlipOrJump() && action.jump) valid = false;
        if (car.boost < 0.1f && action.boost) valid = false;
        output[i] = valid ? 1 : 0;
    }
}

KuxirStepResult KuxirEnv::step(int64_t action, int action_count, uint64_t global_steps) {
    KuxirStepResult result;
    result.stage = stage_;
    car_->controls = action_table()[std::clamp<int64_t>(action, 0, action_count - 1)];
    const auto pre_ball = arena_->ball->GetState();
    const float pre_speed = length(pre_ball.vel);
    arena_->Step(cfg_.tick_skip);
    ++episode_steps_;
    const auto car = car_->GetState();
    const auto ball = arena_->ball->GetState();
    result.touched = car.ballHitInfo.isValid && car.ballHitInfo.tickCountWhenHit != previous_hit_tick_;
    if (result.touched) previous_hit_tick_ = car.ballHitInfo.tickCountWhenHit;

    const float now_potential = potential(car, ball);
    result.reward += std::clamp((now_potential - previous_potential_) * 0.20f, -0.08f, 0.08f) - 0.0005f;
    previous_potential_ = now_potential;

    const float current_wall_gap = RLConst::ARENA_EXTENT_X - std::abs(ball.pos.x);
    const float previous_wall_gap = RLConst::ARENA_EXTENT_X - std::abs(pre_ball.pos.x);
    const float side_now = sign_nonzero(ball.pos.x);
    const Vec to_ball_now = ball.pos - car.pos;
    const float car_ball_distance = length(to_ball_now);
    const bool car_behind_ball = side_now * (ball.pos.x - car.pos.x) > 80.f;
    const float outward_progress = previous_wall_gap - current_wall_gap;
    const bool controlled_drag = drag_started_ && !release_created_ && car.isOnGround && car_behind_ball &&
                                 car_ball_distance < 500.f && ball.pos.z < 210.f;
    if (controlled_drag && current_wall_gap > 700.f && outward_progress > 0.f) {
        // Finite progress reward: transport the ball, but do not stay glued at the wall.
        result.reward += std::min(0.018f, outward_progress / 2200.f);
    }
    const float separation_speed = side_now * (ball.vel.x - car.vel.x);
    const bool release_window = current_wall_gap > 350.f && current_wall_gap < 1050.f;
    if (!release_created_ && drag_started_ && release_window && car.isOnGround && car_behind_ball &&
        car_ball_distance > 300.f && car_ball_distance < 850.f && separation_speed > 120.f && ball.pos.z < 220.f) {
        release_created_ = true;
        setup_completed_ = true;
        result.setup_touch = true;
        result.reward += 1.8f;
    }
    if (drag_started_ && !release_created_ && current_wall_gap < 700.f && car_ball_distance < 280.f) {
        result.reward -= 0.025f;
    }
    if (release_created_ && !aerial_committed_ && current_wall_gap < 550.f &&
        !car.isOnGround && car.lastControls.boost && car_ball_distance < 950.f) {
        aerial_committed_ = true;
        result.aerial_commit = true;
        result.reward += 1.25f;
    }
    if (aerial_committed_ && !flip_attempted_ && car.isFlipping && current_wall_gap < 300.f &&
        car_ball_distance < 320.f && car_behind_ball && ball.pos.z > 140.f) {
        flip_attempted_ = true;
        result.flip_attempt = true;
        result.reward += 1.4f;
    }
    if (release_created_ && !aerial_committed_ && current_wall_gap < 210.f && car.isOnGround) {
        result.reward -= 0.035f;
    }
    if (aerial_committed_ && !flip_attempted_ && current_wall_gap < 170.f) {
        result.reward -= 0.025f;
    }

    if (result.touched) {
        const float speed = length(ball.vel);
        const float side = sign_nonzero(car.ballHitInfo.ballPos.x);
        const float wall_gap = RLConst::ARENA_EXTENT_X - std::abs(car.ballHitInfo.ballPos.x);
        const float inward = -side * ball.vel.x;
        const float impulse = length(ball.vel - pre_ball.vel);
        const Vec goal(0, RLConst::ARENA_EXTENT_Y, 320.f);
        const float aim = clamp01((dot(normalized(ball.vel), normalized(goal - ball.pos)) + 0.15f) / 1.15f);
        const float speed_score = clamp01((speed - 2800.f) / 3200.f);
        const float inward_score = clamp01(inward / 2600.f);
        const float impulse_score = clamp01((impulse - 300.f) / 2200.f);
        result.pinch_quality = 0.40f * speed_score + 0.25f * aim + 0.20f * inward_score + 0.15f * impulse_score;
        result.pinch_speed = speed;
        result.touch_speed = speed;
        result.inward_speed = inward;
        result.touch_impulse = impulse;
        result.flip_contact = car.isFlipping;
        result.wall_touch = wall_gap < 260.f;
        // A fast ball near the wall is not necessarily a pinch. Requiring a
        // large contact impulse prevents the policy from farming ordinary wall
        // taps or inheriting speed from the setter.
        result.pinch = release_created_ && aerial_committed_ && result.flip_contact &&
                       wall_gap < 180.f && car.ballHitInfo.ballPos.z > 180.f &&
                       speed > 2700.f && impulse > 900.f && inward > 450.f && ball.vel.y > 500.f;
        result.developing_pinch = !result.pinch && release_created_ && aerial_committed_ &&
                                  wall_gap < 210.f && car.ballHitInfo.ballPos.z > 150.f &&
                                  result.flip_contact && speed > 1750.f && impulse > 550.f &&
                                  inward > 120.f;
        result.fast_pinch = result.pinch && speed > 4200.f;
        if (result.pinch) {
            const float elite_speed = clamp01((speed - 3000.f) / 2500.f);
            result.reward += 10.f + 14.f * result.pinch_quality + std::max(0.f, speed - pre_speed) / 400.f
                           + 25.f * elite_speed * elite_speed + (result.fast_pinch ? 15.f : 0.f);
            last_pinch_ = true;
            last_pinch_speed_ = speed;
            post_pinch_steps_ = 0;
        } else if (result.developing_pinch) {
            // Directionally correct rear-quarter compression from the video,
            // before it reaches strict Kuxir speed. This curriculum rung is
            // explicit and much smaller than a real pinch reward.
            result.reward += 2.f + 4.f * result.pinch_quality +
                             std::max(0.f, speed - 2200.f) / 300.f +
                             (result.flip_contact ? 0.75f : 0.f);
            if (post_pinch_steps_ < 0) post_pinch_steps_ = 0;
        } else if (wall_gap < 260.f) {
            const float weak_scale = global_steps < 100'000'000ULL ? 1.f : (global_steps < 300'000'000ULL ? 0.55f : 0.25f);
            const float developing_speed = clamp01((speed - 1400.f) / 1600.f);
            const float developing_impulse = clamp01((impulse - 400.f) / 1200.f);
            const float developing_inward = clamp01((inward - 100.f) / 1200.f);
            const float developing_goalward = clamp01((ball.vel.y - 100.f) / 1500.f);
            const bool useful_contact = release_created_ && aerial_committed_ && result.flip_contact &&
                                        speed > 1450.f && impulse > 450.f && inward > 80.f;
            result.reward += useful_contact
                ? 1.25f + 0.45f * weak_scale * (0.45f * developing_speed + 0.65f * developing_impulse +
                                0.55f * developing_inward + 0.35f * developing_goalward +
                                (result.flip_contact ? 0.30f : 0.f))
                : (release_created_ ? -0.20f : -0.45f);
            if (post_pinch_steps_ < 0) post_pinch_steps_ = 0;
        } else {
            const float outward = side * ball.vel.x;
            const bool correct_push = outward > 250.f && std::abs(ball.vel.y) < 650.f &&
                                      car.ballHitInfo.ballPos.z < 190.f;
            if (correct_push && !result.flip_contact) {
                if (!drag_started_) {
                    drag_started_ = true;
                    result.reward += 0.35f;
                }
            } else if (result.flip_contact && wall_gap > 500.f) {
                // A flip is useful at the wall for compression, but an early
                // flip launches the ball and leaves the car unable to pinch.
                result.reward -= 0.85f;
            } else if (!correct_push) {
                result.reward -= 0.5f;
                if (stage_ < 2) result.done = true;
            }
        }
    }

    result.goal = arena_->IsBallScored();
    if (result.goal) {
        result.pinch_goal = last_pinch_ && ball.pos.y > 0.f;
        result.reward += result.pinch_goal ? 28.f + last_pinch_speed_ / 300.f : -2.f;
        result.done = true;
    }
    if (post_pinch_steps_ >= 0) {
        ++post_pinch_steps_;
        if (post_pinch_steps_ >= 100) result.done = true;
    }
    if (episode_steps_ >= cfg_.max_episode_decisions) result.done = true;
    if (ball.pos.y < -5000.f || std::abs(ball.pos.x) > 4200.f || ball.pos.z > 2100.f || !state_is_sane()) result.done = true;

    previous_ball_ = ball;
    if (result.done) reset(global_steps);
    return result;
}

std::string KuxirEnv::rocketsimvis_json() const {
    std::ostringstream out;
    out << std::setprecision(7);
    auto vec = [&](const Vec& value) { out << '[' << value.x << ',' << value.y << ',' << value.z << ']'; };
    auto phys = [&](const PhysState& state) {
        out << "{\"pos\":"; vec(state.pos);
        out << ",\"forward\":"; vec(state.rotMat.forward);
        out << ",\"up\":"; vec(state.rotMat.up);
        out << ",\"vel\":"; vec(state.vel);
        out << ",\"ang_vel\":"; vec(state.angVel);
        out << '}';
    };
    out << "{\"ball_phys\":"; phys(arena_->ball->GetState());
    const auto car = car_->GetState();
    out << ",\"cars\":[{\"team_num\":0,\"phys\":"; phys(car);
    out << ",\"controls\":{\"throttle\":" << car_->controls.throttle
        << ",\"steer\":" << car_->controls.steer << ",\"pitch\":" << car_->controls.pitch
        << ",\"yaw\":" << car_->controls.yaw << ",\"roll\":" << car_->controls.roll
        << ",\"boost\":" << (car_->controls.boost ? "true" : "false")
        << ",\"jump\":" << (car_->controls.jump ? "true" : "false")
        << ",\"handbrake\":" << (car_->controls.handbrake ? "true" : "false") << '}'
        << ",\"boost_amount\":" << car.boost << ",\"on_ground\":" << (car.isOnGround ? "true" : "false")
        << ",\"has_flipped_or_double_jumped\":" << ((car.hasFlipped || car.hasDoubleJumped) ? "true" : "false")
        << ",\"is_demoed\":false}],\"boost_pad_states\":[";
    for (int i = 0; i < 34; ++i) { if (i) out << ','; out << "true"; }
    out << "]}";
    return out.str();
}
