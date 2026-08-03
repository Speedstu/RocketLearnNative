#include "config.h"
#include "ppo.h"
#include <RocketSim.h>
#include <iostream>

int main(int argc,char**argv){
    try{
        auto cfg=Config::load();bool smoke=argc>1&&std::string(argv[1])=="--smoke";
        RocketSim::Init(std::filesystem::absolute(cfg.meshes),true);
        Trainer trainer(std::move(cfg));trainer.run(smoke);return 0;
    }catch(const c10::Error&e){std::cerr<<"TORCH_ERROR: "<<e.what()<<'\n';return 2;}catch(const std::exception&e){std::cerr<<"ERROR: "<<e.what()<<'\n';return 1;}
}

