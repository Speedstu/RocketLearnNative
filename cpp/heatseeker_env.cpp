#include "heatseeker_env.h"

#include <RLConst.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <iomanip>
#include <sstream>

using namespace RocketSim;

namespace {
float clampf(float x, float lo = -1.f, float hi = 1.f) { return std::clamp(x, lo, hi); }
float dot(const Vec& a, const Vec& b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
float length(const Vec& v) { return std::sqrt(dot(v, v)); }
Vec normalized(const Vec& v) { float l = length(v); return l > 1e-4f ? v / l : Vec{}; }
void put_vec(float*& p, Vec v, float scale, float sign) {
    *p++ = v.x * scale * sign; *p++ = v.y * scale * sign; *p++ = v.z * scale;
}
}

const std::vector<CarControls>& HeatseekerEnv::action_table() {
    static const std::vector<CarControls> table = [] {
        std::vector<CarControls> a;
        auto add = [&](float throttle, float steer, float pitch, float yaw, float roll,
                       bool jump, bool boost, bool handbrake) {
            CarControls c; c.throttle=throttle; c.steer=steer; c.pitch=pitch; c.yaw=yaw; c.roll=roll;
            c.jump=jump; c.boost=boost; c.handbrake=handbrake; a.push_back(c);
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

HeatseekerEnv::HeatseekerEnv(const Config& cfg, uint64_t seed) : cfg_(cfg), rng_(seed) {
    arena_ = Arena::Create(GameMode::HEATSEEKER);
    cars_[0] = arena_->AddCar(Team::BLUE); cars_[1] = arena_->AddCar(Team::BLUE);
    cars_[2] = arena_->AddCar(Team::ORANGE); cars_[3] = arena_->AddCar(Team::ORANGE);
    auto mut = arena_->GetMutatorConfig();
    mut.boostUsedPerSecond = 0.f;
    mut.carSpawnBoostAmount = 100.f;
    mut.demoMode = DemoMode::NORMAL;
    arena_->SetMutatorConfig(mut);
    reset(0);
}

HeatseekerEnv::~HeatseekerEnv() { delete arena_; }

void HeatseekerEnv::reset(uint64_t global_steps, int kickoff_percent_override) {
    arena_->ResetToRandomKickoff(static_cast<int>(rng_()));
    episode_steps_ = no_touch_steps_ = 0;
    const int curriculum = global_steps < 20'000'000 ? 0 : (global_steps < 100'000'000 ? 1 : 2);
    const int default_kickoff_percent = curriculum == 0 ? 10 : (curriculum == 1 ? 25 : 15);
    const int kickoff_percent = kickoff_percent_override >= 0 ? kickoff_percent_override : default_kickoff_percent;
    const bool true_kickoff = std::uniform_int_distribution<int>(0, 99)(rng_) < std::clamp(kickoff_percent, 0, 100);

    // A true Heatseeker kickoff deliberately has hsInfo.yTargetDir == 0:
    // RocketSim activates homing on the first car touch, like the real mode.
    // Every other reset starts inside an active rally with the homing internals
    // armed, so the learner does not spend most experience on ballistic Soccar.
    if (!true_kickoff) {
        const float max_height = curriculum == 0 ? 900.f : (curriculum == 1 ? 1400.f : 1800.f);
        const float launch_speed = curriculum == 0 ? 2200.f : (curriculum == 1 ? 2850.f : 3600.f);
        const float target_speed = curriculum == 0 ? 2900.f : (curriculum == 1 ? 3400.f : 4100.f);
        std::uniform_real_distribution<float> ux(-2600.f, 2600.f), uz(180.f, max_height);
        std::uniform_real_distribution<float> uv(-550.f, 550.f);
        BallState b = arena_->ball->GetState();
        b.pos = Vec(ux(rng_), (rng_() & 1) ? -1800.f : 1800.f, uz(rng_));
        const float target = b.pos.y > 0 ? -1.f : 1.f;
        b.vel = normalized(Vec(uv(rng_), target * 5120.f - b.pos.y, 500.f + uv(rng_))) * launch_speed;
        b.hsInfo.yTargetDir = target;
        b.hsInfo.curTargetSpeed = target_speed;
        b.hsInfo.timeSinceHit = 1.f;
        arena_->ball->SetState(b);
        if (curriculum == 0) {
            // Early learning must see many reachable saves. Put the defending
            // pair on the incoming line, then let later curriculum use genuine
            // Heatseeker kickoffs and high-speed randomized shots.
            const bool blue_defends = target < 0.f;
            const int first = blue_defends ? 0 : 2;
            const float defend_y = blue_defends ? -3000.f : 3000.f;
            const float yaw = blue_defends ? 1.5707963f : -1.5707963f;
            const float center_x = b.pos.x * 0.35f;
            for (int k = 0; k < 2; ++k) {
                auto c = cars_[first + k]->GetState();
                c.pos = Vec(center_x + (k == 0 ? -360.f : 360.f), defend_y + (k == 0 ? 0.f : (blue_defends ? -700.f : 700.f)), RLConst::CAR_SPAWN_REST_Z);
                c.vel = Vec{}; c.angVel = Vec{}; c.rotMat = Angle(yaw).ToRotMat(); c.boost = 100.f;
                cars_[first + k]->SetState(c);
            }
        }
    }
    previous_ball_ = arena_->ball->GetState();
    for (int i=0;i<4;++i) {
        const auto s = cars_[i]->GetState();
        previous_distance_[i] = length(previous_ball_.pos - s.pos);
        previous_hit_tick_[i] = s.ballHitInfo.tickCountWhenHit;
    }
}

void HeatseekerEnv::build_one_obs(int agent, float* out) const {
    std::fill(out, out + kObsSize, 0.f);
    float* p = out;
    const auto self = cars_[agent]->GetState();
    const auto ball = arena_->ball->GetState();
    const float sign = cars_[agent]->team == Team::BLUE ? 1.f : -1.f;
    put_vec(p, self.pos, 1.f/5500.f, sign); put_vec(p, self.vel, 1.f/2300.f, sign); put_vec(p, self.angVel, 1.f/5.5f, sign);
    put_vec(p, self.rotMat.forward, 1.f, sign); put_vec(p, self.rotMat.right, 1.f, sign); put_vec(p, self.rotMat.up, 1.f, sign);
    *p++=self.boost/100.f; *p++=self.isOnGround; *p++=self.HasFlipOrJump(); *p++=self.isDemoed;
    put_vec(p, ball.pos, 1.f/5500.f, sign); put_vec(p, ball.vel, 1.f/6000.f, sign); put_vec(p, ball.angVel, 1.f/6.f, sign);
    *p++=ball.hsInfo.yTargetDir*sign; *p++=ball.hsInfo.curTargetSpeed/6000.f; *p++=clampf(ball.hsInfo.timeSinceHit/3.f,0,1);
    Vec rel = ball.pos-self.pos, relv=ball.vel-self.vel;
    put_vec(p, rel, 1.f/7000.f, sign); put_vec(p, relv, 1.f/7000.f, sign);
    *p++=clampf(dot(self.rotMat.forward, normalized(rel))); *p++=clampf(length(rel)/8000.f,0,1);
    for (int j=0;j<4;++j) if (j!=agent) {
        auto o=cars_[j]->GetState();
        put_vec(p,o.pos-self.pos,1.f/11000.f,sign); put_vec(p,o.vel,1.f/2300.f,sign);
        put_vec(p,o.rotMat.forward,1.f,sign); *p++=o.boost/100.f; *p++=(cars_[j]->team==cars_[agent]->team)?1.f:-1.f;
        *p++=o.isOnGround; *p++=o.isDemoed;
    }
    for (float t : {0.25f,0.5f,0.9f}) {
        Vec future=ball.pos+ball.vel*t;
        future.x=std::clamp(future.x,-4096.f,4096.f); future.y=std::clamp(future.y,-5120.f,5120.f); future.z=std::clamp(future.z,92.f,2044.f);
        put_vec(p,future-self.pos,1.f/8000.f,sign);
    }
    *p++=clampf((ball.pos.y-self.pos.y)*sign/6000.f);
    *p++=clampf(std::abs(self.pos.x)/4096.f,0,1);
    *p++=clampf(ball.pos.z/2044.f,0,1);
}

void HeatseekerEnv::observe(float* output) const {
    for (int i=0;i<4;++i) build_one_obs(i, output + i*kObsSize);
}

void HeatseekerEnv::action_masks(uint8_t* output, int action_count) const {
    const auto& table=action_table();
    for(int i=0;i<4;++i){
        auto s=cars_[i]->GetState();
        for(int a=0;a<action_count;++a){
            const auto& c=table[a]; bool ok=true;
            if(s.isOnGround && (std::abs(c.pitch)>0.1f || std::abs(c.roll)>0.1f) && !c.jump) ok=false;
            if(!s.isOnGround && c.handbrake) ok=false;
            if(s.boost<0.1f && c.boost) ok=false;
            if(!s.HasFlipOrJump() && c.jump) ok=false;
            output[i*action_count+a]=ok?1:0;
        }
    }
}

float HeatseekerEnv::shaped_reward(int agent, const CarState& car, const BallState& ball,
                                   bool touched, float pre_ball_speed, bool goal, int scoring_team) const {
    const int team = cars_[agent]->team == Team::BLUE ? 0 : 1;
    float r=0.f;
    if(goal) r += scoring_team==team ? 12.f : -12.f;
    const Vec to_ball=ball.pos-car.pos; const float dist=length(to_ball);
    r += clampf((previous_distance_[agent]-dist)/500.f)*0.08f;
    r += std::max(0.f,dot(car.rotMat.forward,normalized(to_ball)))*0.003f;
    const float own_y=team==0?-5120.f:5120.f;
    const bool goal_side=team==0 ? car.pos.y<ball.pos.y : car.pos.y>ball.pos.y;
    r += goal_side?0.002f:-0.003f;
    if(touched){
        const float attack=team==0?1.f:-1.f;
        const float outbound=ball.vel.y*attack;
        r += 2.0f + std::max(0.f,outbound/6000.f)*3.0f;
        if(previous_ball_.vel.y*attack < -400.f && outbound>400.f) r += 5.0f;
        r += std::max(0.f,(length(ball.vel)-pre_ball_speed)/1500.f);
        if(ball.pos.z>300.f) r += std::min(3.f,ball.pos.z/700.f);
    }
    if(std::abs(ball.pos.y-own_y)<1800.f && ((team==0&&ball.vel.y<0)||(team==1&&ball.vel.y>0)))
        r += std::max(0.f,1.f-dist/3500.f)*0.01f;
    return r;
}

StepResult HeatseekerEnv::step(const int64_t* actions, int action_count, uint64_t global_steps) {
    StepResult result; const auto& table=action_table();
    for(int i=0;i<4;++i) cars_[i]->controls=table[std::clamp<int64_t>(actions[i],0,action_count-1)];
    const float pre_speed=length(arena_->ball->GetState().vel);
    arena_->Step(cfg_.tick_skip);
    ++episode_steps_;
    auto ball=arena_->ball->GetState();
    std::array<bool,4> touched{};
    for(int i=0;i<4;++i){ auto s=cars_[i]->GetState(); touched[i]=s.ballHitInfo.isValid&&s.ballHitInfo.tickCountWhenHit!=previous_hit_tick_[i]; if(touched[i]){++result.touches; previous_hit_tick_[i]=s.ballHitInfo.tickCountWhenHit;} }
    no_touch_steps_=result.touches?0:no_touch_steps_+1;
    result.goal=arena_->IsBallScored();
    if(result.goal) result.scoring_team=ball.pos.y>0?0:1;
    result.done=result.goal||episode_steps_>=cfg_.max_episode_decisions||no_touch_steps_>=225;
    for(int i=0;i<4;++i){auto s=cars_[i]->GetState();result.rewards[i]=shaped_reward(i,s,ball,touched[i],pre_speed,result.goal,result.scoring_team);previous_distance_[i]=length(ball.pos-s.pos);}
    previous_ball_=ball;
    if(result.done) reset(global_steps);
    return result;
}

std::string HeatseekerEnv::rocketsimvis_json() const {
    std::ostringstream out;
    out << std::setprecision(7);
    auto vec = [&](const Vec& v) { out << '[' << v.x << ',' << v.y << ',' << v.z << ']'; };
    auto phys = [&](const PhysState& state) {
        out << "{\"pos\":"; vec(state.pos);
        out << ",\"forward\":"; vec(state.rotMat.forward);
        out << ",\"up\":"; vec(state.rotMat.up);
        out << ",\"vel\":"; vec(state.vel);
        out << ",\"ang_vel\":"; vec(state.angVel);
        out << '}';
    };
    out << "{\"ball_phys\":";
    phys(arena_->ball->GetState());
    out << ",\"cars\":[";
    for (int i = 0; i < 4; ++i) {
        if (i) out << ',';
        const auto car = cars_[i]->GetState();
        out << "{\"team_num\":" << (cars_[i]->team == Team::BLUE ? 0 : 1) << ",\"phys\":";
        phys(car);
        out << ",\"controls\":{\"throttle\":" << cars_[i]->controls.throttle
            << ",\"steer\":" << cars_[i]->controls.steer
            << ",\"pitch\":" << cars_[i]->controls.pitch
            << ",\"yaw\":" << cars_[i]->controls.yaw
            << ",\"roll\":" << cars_[i]->controls.roll
            << ",\"boost\":" << (cars_[i]->controls.boost ? "true" : "false")
            << ",\"jump\":" << (cars_[i]->controls.jump ? "true" : "false")
            << ",\"handbrake\":" << (cars_[i]->controls.handbrake ? "true" : "false") << '}'
            << ",\"boost_amount\":" << car.boost
            << ",\"on_ground\":" << (car.isOnGround ? "true" : "false")
            << ",\"has_flipped_or_double_jumped\":" << ((car.hasFlipped || car.hasDoubleJumped) ? "true" : "false")
            << ",\"is_demoed\":" << (car.isDemoed ? "true" : "false") << '}';
    }
    out << "],\"boost_pad_states\":[";
    for (int i = 0; i < 34; ++i) { if (i) out << ','; out << "true"; }
    out << "]}";
    return out.str();
}
