#include "soccar_env.h"

#include <algorithm>
#include <cmath>

using namespace RocketSim;

namespace {
float clampf(float x, float lo = -1.f, float hi = 1.f) { return std::clamp(x, lo, hi); }
float dot(const Vec& a, const Vec& b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
float length(const Vec& v) { return std::sqrt(dot(v, v)); }
Vec normalized(const Vec& v) {
    const float l = length(v);
    return l > 1e-4f ? v / l : Vec{};
}
void put_vec(float*& p, Vec v, float scale, float sign) {
    *p++ = v.x * scale * sign;
    *p++ = v.y * scale * sign;
    *p++ = v.z * scale;
}
}

const std::vector<CarControls>& SoccarEnv::action_table() {
    static const std::vector<CarControls> table = [] {
        std::vector<CarControls> a;
        auto add = [&](float throttle, float steer, float pitch, float yaw, float roll,
                       bool jump, bool boost, bool handbrake) {
            CarControls c;
            c.throttle = throttle; c.steer = steer; c.pitch = pitch; c.yaw = yaw; c.roll = roll;
            c.jump = jump; c.boost = boost; c.handbrake = handbrake;
            a.push_back(c);
        };

        add(0,0,0,0,0,false,false,false);
        for (float t : {-1.f, 0.f, 1.f}) for (float s : {-1.f, 0.f, 1.f}) {
            if (t == 0 && s == 0) continue;
            add(t,s,0,s,0,false,false,std::abs(s)>0.5f && t>=0);
            if (t > 0) add(t,s,0,s,0,false,true,false);
        }
        for (float s : {-1.f, 0.f, 1.f}) {
            add(1,s,-1,s,0,true,false,false);
            add(1,s,-1,s,0,true,true,false);
            add(1,s,1,s,0,true,false,false);
        }
        for (float pitch : {-1.f, 0.f, 1.f}) for (float yaw : {-1.f, 0.f, 1.f}) {
            if (pitch == 0 && yaw == 0) continue;
            add(1,yaw,pitch,yaw,0,false,false,false);
            add(1,yaw,pitch,yaw,0,false,true,false);
        }
        for (float roll : {-1.f, 1.f}) {
            add(1,0,0,0,roll,false,false,false);
            add(1,0,-1,0,roll,false,true,false);
            add(1,0,0,0,roll,true,false,false);
        }
        return a;
    }();
    return table;
}

SoccarEnv::SoccarEnv(const Config& cfg, uint64_t seed) : cfg_(cfg), rng_(seed) {
    arena_ = Arena::Create(GameMode::SOCCAR);
    cars_[0] = arena_->AddCar(Team::BLUE);
    cars_[1] = arena_->AddCar(Team::BLUE);
    cars_[2] = arena_->AddCar(Team::ORANGE);
    cars_[3] = arena_->AddCar(Team::ORANGE);
    reset(0);
}

SoccarEnv::~SoccarEnv() { delete arena_; }

void SoccarEnv::reset(uint64_t global_steps) {
    (void)global_steps;
    arena_->ResetToRandomKickoff(static_cast<int>(rng_()));
    episode_steps_ = 0;
    previous_ball_ = arena_->ball->GetState();
    for (int i = 0; i < 4; ++i) {
        const auto s = cars_[i]->GetState();
        previous_distance_[i] = length(previous_ball_.pos - s.pos);
        previous_hit_tick_[i] = s.ballHitInfo.tickCountWhenHit;
    }
}

void SoccarEnv::build_one_obs(int agent, float* out) const {
    std::fill(out, out + kObsSize, 0.f);
    float* p = out;

    const auto self = cars_[agent]->GetState();
    const auto ball = arena_->ball->GetState();
    const float sign = cars_[agent]->team == Team::BLUE ? 1.f : -1.f;

    put_vec(p, self.pos, 1.f/5500.f, sign);
    put_vec(p, self.vel, 1.f/2300.f, sign);
    put_vec(p, self.angVel, 1.f/5.5f, sign);
    put_vec(p, self.rotMat.forward, 1.f, sign);
    put_vec(p, self.rotMat.right, 1.f, sign);
    put_vec(p, self.rotMat.up, 1.f, sign);
    *p++ = self.boost / 100.f;
    *p++ = self.isOnGround;
    *p++ = self.HasFlipOrJump();
    *p++ = self.isDemoed;

    put_vec(p, ball.pos, 1.f/5500.f, sign);
    put_vec(p, ball.vel, 1.f/2300.f, sign);
    put_vec(p, ball.angVel, 1.f/6.f, sign);

    const Vec rel = ball.pos - self.pos;
    const Vec relv = ball.vel - self.vel;
    put_vec(p, rel, 1.f/7000.f, sign);
    put_vec(p, relv, 1.f/4600.f, sign);
    *p++ = clampf(dot(self.rotMat.forward, normalized(rel)));
    *p++ = clampf(length(rel) / 8000.f, 0.f, 1.f);

    for (int j = 0; j < 4; ++j) if (j != agent) {
        const auto other = cars_[j]->GetState();
        put_vec(p, other.pos - self.pos, 1.f/11000.f, sign);
        put_vec(p, other.vel, 1.f/2300.f, sign);
        put_vec(p, other.rotMat.forward, 1.f, sign);
        *p++ = other.boost / 100.f;
        *p++ = cars_[j]->team == cars_[agent]->team ? 1.f : -1.f;
        *p++ = other.isOnGround;
        *p++ = other.isDemoed;
    }

    for (float t : {0.25f, 0.5f, 0.9f}) {
        Vec future = ball.pos + ball.vel * t;
        future.x = std::clamp(future.x, -4096.f, 4096.f);
        future.y = std::clamp(future.y, -5120.f, 5120.f);
        future.z = std::clamp(future.z, 92.f, 2044.f);
        put_vec(p, future - self.pos, 1.f/8000.f, sign);
    }

    *p++ = clampf(ball.pos.y * sign / 5120.f);
    *p++ = clampf(ball.vel.y * sign / 2300.f);
    *p++ = clampf(std::abs(self.pos.x) / 4096.f, 0.f, 1.f);
    *p++ = clampf(ball.pos.z / 2044.f, 0.f, 1.f);
}

void SoccarEnv::observe(float* output) const {
    for (int i = 0; i < 4; ++i)
        build_one_obs(i, output + i * kObsSize);
}

void SoccarEnv::action_masks(uint8_t* output, int action_count) const {
    const auto& table = action_table();
    for (int i = 0; i < 4; ++i) {
        const auto s = cars_[i]->GetState();
        for (int a = 0; a < action_count; ++a) {
            const auto& c = table[a];
            bool ok = true;
            if (s.isOnGround && (std::abs(c.pitch) > 0.1f || std::abs(c.roll) > 0.1f) && !c.jump) ok = false;
            if (!s.isOnGround && c.handbrake) ok = false;
            if (s.boost < 0.1f && c.boost) ok = false;
            if (!s.HasFlipOrJump() && c.jump) ok = false;
            output[i * action_count + a] = ok ? 1 : 0;
        }
    }
}

float SoccarEnv::shaped_reward(int agent, const CarState& car, const BallState& ball,
                               bool touched, float pre_ball_speed, bool goal, int scoring_team) const {
    const int team = cars_[agent]->team == Team::BLUE ? 0 : 1;
    const float attack = team == 0 ? 1.f : -1.f;

    float r = 0.f;
    if (goal) r += scoring_team == team ? 10.f : -10.f;

    const Vec to_ball = ball.pos - car.pos;
    const float dist = length(to_ball);
    r += clampf((previous_distance_[agent] - dist) / 500.f) * 0.03f;
    r += std::max(0.f, dot(car.rotMat.forward, normalized(to_ball))) * 0.001f;
    r += clampf(ball.vel.y * attack / 2300.f) * 0.002f;

    const bool goal_side = team == 0 ? car.pos.y < ball.pos.y : car.pos.y > ball.pos.y;
    r += goal_side ? 0.001f : -0.001f;

    if (touched) {
        r += 0.5f;
        const float speed_gain = std::max(0.f, length(ball.vel) - pre_ball_speed);
        r += std::min(0.5f, speed_gain / 3000.f);
        r += std::max(0.f, ball.vel.y * attack / 2300.f) * 0.5f;
        if (ball.pos.z > 300.f) r += std::min(0.25f, ball.pos.z / 4000.f);
    }
    return r;
}

StepResult SoccarEnv::step(const int64_t* actions, int action_count, uint64_t global_steps) {
    StepResult result;
    const auto& table = action_table();

    for (int i = 0; i < 4; ++i)
        cars_[i]->controls = table[std::clamp<int64_t>(actions[i], 0, action_count - 1)];

    const float pre_speed = length(arena_->ball->GetState().vel);
    arena_->Step(cfg_.tick_skip);
    ++episode_steps_;

    const auto ball = arena_->ball->GetState();
    std::array<bool, 4> touched{};

    for (int i = 0; i < 4; ++i) {
        const auto s = cars_[i]->GetState();
        touched[i] = s.ballHitInfo.isValid && s.ballHitInfo.tickCountWhenHit != previous_hit_tick_[i];
        if (touched[i]) {
            ++result.touches;
            previous_hit_tick_[i] = s.ballHitInfo.tickCountWhenHit;
        }
    }

    result.goal = arena_->IsBallScored();
    if (result.goal) result.scoring_team = ball.pos.y > 0 ? 0 : 1;
    result.done = result.goal || episode_steps_ >= cfg_.max_episode_decisions;

    for (int i = 0; i < 4; ++i) {
        const auto s = cars_[i]->GetState();
        result.rewards[i] = shaped_reward(i, s, ball, touched[i], pre_speed, result.goal, result.scoring_team);
        previous_distance_[i] = length(ball.pos - s.pos);
    }

    previous_ball_ = ball;
    if (result.done) reset(global_steps);
    return result;
}
