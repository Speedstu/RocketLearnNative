#include <torch/torch.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr int kMaxCars = 4;
constexpr int kObs = 72;
constexpr int kActions = 16;
constexpr float FIELD_HALF_X = 2560.f;
constexpr float CEILING = 2688.f;
constexpr float NV = 2800.f;
constexpr float BALL_ANG_HARD_CAP = 8.f;
constexpr float MAX_ANG_SPEED = 9.16f;
constexpr float BOOST_MAX = 100.f;
constexpr float DODGE_TIME = 0.18f;
constexpr float SUPERSONIC = 2000.f;

struct Ball { float x=0,y=0,vx=0,vy=0,spin=0; };
struct Car {
    int team=0;
    float x=0,y=0,vx=0,vy=0,theta=0,omega=0,boost=0;
    bool on_ground=false, has_flip=false, jumping=false;
    float flip_timer=0, air_time=0;
};
struct Control { float drive=0, pitch=0; bool jump=false, boost=false; };

float len(float x,float y){ return std::sqrt(x*x+y*y); }

const std::vector<Control>& actions(){
    static const std::vector<Control> a = {
        {0,0,false,false},{1,0,false,false},{-1,0,false,false},{1,0,false,true},
        {-1,0,false,true},{0,0,false,true},{0,0,true,false},{1,0,true,false},
        {-1,0,true,false},{0,-1,false,false},{0,1,false,false},{0,-1,false,true},
        {0,1,false,true},{0,-1,true,false},{0,1,true,false},{1,0,true,true}
    };
    return a;
}

struct SideSwipeNetImpl : torch::nn::Module {
    explicit SideSwipeNetImpl(int action_count)
        : fc1(register_module("fc1", torch::nn::Linear(kObs, 512))),
          fc2(register_module("fc2", torch::nn::Linear(512, 512))),
          fc3(register_module("fc3", torch::nn::Linear(512, 256))),
          actor(register_module("actor", torch::nn::Linear(256, action_count))),
          critic(register_module("critic", torch::nn::Linear(256, 1))),
          ln1(register_module("ln1", torch::nn::LayerNorm(torch::nn::LayerNormOptions({512})))),
          ln2(register_module("ln2", torch::nn::LayerNorm(torch::nn::LayerNormOptions({512})))) {}
    std::pair<torch::Tensor,torch::Tensor> forward(const torch::Tensor& x){
        auto h=torch::silu(ln1(fc1(x))); h=torch::silu(ln2(fc2(h))); h=torch::silu(fc3(h));
        return {actor(h), critic(h).squeeze(-1)};
    }
    torch::nn::Linear fc1,fc2,fc3,actor,critic; torch::nn::LayerNorm ln1,ln2;
};
TORCH_MODULE(SideSwipeNet);

void observe(const Ball& b, const std::vector<Car>& cars, int car, float* out){
    const Car& me=cars.at(car); const float mirror=me.team==0?1.f:-1.f;
    const float bx=b.x*mirror,bvx=b.vx*mirror,spin=b.spin*mirror;
    const float px=me.x*mirror,pvx=me.vx*mirror;
    const float ct=std::cos(me.theta)*mirror, st=std::sin(me.theta), speed=len(me.vx,me.vy);
    int k=0;
    out[k++]=bx/FIELD_HALF_X; out[k++]=b.y/CEILING; out[k++]=bvx/NV; out[k++]=b.vy/NV; out[k++]=spin/BALL_ANG_HARD_CAP;
    out[k++]=px/FIELD_HALF_X; out[k++]=me.y/CEILING; out[k++]=pvx/NV; out[k++]=me.vy/NV; out[k++]=ct; out[k++]=st;
    out[k++]=me.omega*mirror/MAX_ANG_SPEED; out[k++]=me.boost/BOOST_MAX; out[k++]=me.on_ground?1.f:0.f; out[k++]=me.has_flip?1.f:0.f;
    out[k++]=me.jumping?1.f:0.f; out[k++]=me.flip_timer/DODGE_TIME; out[k++]=std::min(me.air_time,3.f)/3.f; out[k++]=speed/NV; out[k++]=speed>SUPERSONIC?1.f:0.f;
    const float rx=bx-px, ry=b.y-me.y, dist=std::max(1.f,len(rx,ry));
    out[k++]=rx/FIELD_HALF_X; out[k++]=ry/CEILING; out[k++]=(bvx-pvx)/NV; out[k++]=(b.vy-me.vy)/NV; out[k++]=dist/FIELD_HALF_X; out[k++]=(ct*rx+st*ry)/dist;
    out[k++]=(FIELD_HALF_X-px)/FIELD_HALF_X; out[k++]=(FIELD_HALF_X-bx)/FIELD_HALF_X; out[k++]=bx>px?1.f:0.f; out[k++]=px<-FIELD_HALF_X*.5f?1.f:0.f;
    int slot=0;
    for(int i=0;i<(int)cars.size() && slot<kMaxCars-1;i++){
        if(i==car) continue; const Car& o=cars[i]; const float ox=o.x*mirror,ovx=o.vx*mirror;
        // Contract 2026081602 is trained with transfer_safe_obs=1.  Do not
        // leak privileged opponent state (exact facing/omega/boost/flip) here.
        float other_ct, other_st;
        const float ospeed=len(ovx,o.vy);
        if(ospeed>250.f){ other_ct=ovx/ospeed; other_st=o.vy/ospeed; }
        else { other_ct=o.team==me.team?1.f:-1.f; other_st=0.f; }
        out[k++]=1.f; out[k++]=o.team==me.team?1.f:0.f; out[k++]=ox/FIELD_HALF_X; out[k++]=o.y/CEILING; out[k++]=ovx/NV; out[k++]=o.vy/NV;
        out[k++]=other_ct; out[k++]=other_st; out[k++]=0.f; out[k++]=0.5f;
        out[k++]=o.on_ground?1.f:0.f; out[k++]=0.5f; out[k++]=(ox-px)/FIELD_HALF_X; out[k++]=(o.y-me.y)/CEILING; ++slot;
    }
    for(;slot<kMaxCars-1;slot++) for(int j=0;j<14;j++) out[k++]=0.f;
    if(k!=kObs) throw std::runtime_error("observation contract mismatch");
}

void action_mask(const Car& me, bool* out){
    const bool can_jump=me.on_ground||me.has_flip||me.jumping, has_boost=me.boost>1.f;
    const auto& table=actions();
    for(int i=0;i<kActions;i++){
        bool ok=true; const auto& c=table[i];
        if(c.jump&&!can_jump) ok=false; if(c.boost&&!has_boost) ok=false;
        if(me.on_ground&&std::fabs(c.pitch)>.6f&&!c.jump) ok=false;
        out[i]=ok;
    }
    out[0]=true;
}

struct Policy {
    SideSwipeNet net{kActions};
    explicit Policy(const std::string& ckpt){
        torch::serialize::InputArchive ar; ar.load_from(ckpt, torch::kCPU); net->load(ar); net->eval();
    }
    int choose(const std::vector<float>& obs, const bool* mask){
        torch::NoGradGuard ng;
        auto x=torch::from_blob((void*)obs.data(),{1,kObs},torch::TensorOptions().dtype(torch::kFloat32)).clone();
        auto logits=net->forward(x).first.squeeze(0);
        for(int i=0;i<kActions;i++) if(!mask[i]) logits.index_put_({i},-1e9);
        return logits.argmax().item<int>();
    }
};

std::string arg(int argc,char**argv,const std::string& key,const std::string& fallback=""){
    for(int i=1;i+1<argc;i++) if(argv[i]==key) return argv[i+1]; return fallback;
}

bool parse_state(const std::string& line, Ball& b, std::vector<Car>& cars){
    std::istringstream ss(line); std::string tag; int n=0; ss>>tag>>n;
    if(tag!="S"||n<1||n>kMaxCars) return false;
    if(!(ss>>b.x>>b.y>>b.vx>>b.vy>>b.spin)) return false;
    cars.assign(n,{});
    for(int i=0;i<n;i++){
        int ground=0,flip=0,jump=0;
        if(!(ss>>cars[i].team>>cars[i].x>>cars[i].y>>cars[i].vx>>cars[i].vy>>cars[i].theta>>cars[i].omega>>cars[i].boost>>ground>>flip>>jump>>cars[i].flip_timer>>cars[i].air_time)) return false;
        cars[i].on_ground=ground!=0; cars[i].has_flip=flip!=0; cars[i].jumping=jump!=0;
    }
    return true;
}
}

int main(int argc,char**argv){
    try{
        const std::string blue=arg(argc,argv,"--blue");
        const std::string orange=arg(argc,argv,"--orange",blue);
        if(blue.empty()||!std::filesystem::exists(blue)) throw std::runtime_error("--blue checkpoint missing");
        if(orange.empty()||!std::filesystem::exists(orange)) throw std::runtime_error("--orange checkpoint missing");
        torch::set_num_threads(1);
        Policy blue_policy(blue), orange_policy(orange);
        std::cerr<<"[policy-host] obs="<<kObs<<" actions="<<kActions<<" blue="<<blue<<" orange="<<orange<<"\n";
        std::string line; Ball ball; std::vector<Car> cars;
        while(std::getline(std::cin,line)){
            if(line=="PING"){ std::cout<<"PONG\n"<<std::flush; continue; }
            if(!parse_state(line,ball,cars)){ std::cout<<"ERR bad_state\n"<<std::flush; continue; }
            std::cout<<"C "<<cars.size();
            for(int i=0;i<(int)cars.size();i++){
                std::vector<float> obs(kObs); bool mask[kActions]; observe(ball,cars,i,obs.data()); action_mask(cars[i],mask);
                const int a=(cars[i].team==0?blue_policy:orange_policy).choose(obs,mask);
                Control c=actions()[a]; if(cars[i].team==1) c.pitch=-c.pitch;
                std::cout<<' '<<a<<' '<<c.drive<<' '<<c.pitch<<' '<<(c.jump?1:0)<<' '<<(c.boost?1:0);
            }
            std::cout<<"\n"<<std::flush;
        }
    }catch(const std::exception& e){ std::cerr<<"[fatal] "<<e.what()<<"\n"; return 2; }
    return 0;
}
