#include "kuxir_config.h"
#include "kuxir_ppo.h"

#include <RocketSim.h>
#include <iostream>

int main(int argc, char** argv) {
    try {
        auto config = KuxirConfig::load();
        const bool smoke = argc > 1 && std::string(argv[1]) == "--smoke";
        const bool benchmark = argc > 1 && std::string(argv[1]) == "--benchmark";
        RocketSim::Init(std::filesystem::absolute(config.meshes), true);
        if (argc > 1 && std::string(argv[1]) == "--audit-states") {
            KuxirEnv env(config, static_cast<uint64_t>(config.seed));
            for (int stage = 0; stage < 3; ++stage) {
                for (int i = 0; i < 10000; ++i) {
                    env.reset(stage == 0 ? 0 : (stage == 1 ? 60'000'000ULL : 150'000'000ULL), stage);
                    if (!env.state_is_sane()) {
                        std::cerr << env.rocketsimvis_json() << '\n';
                        throw std::runtime_error("invalid Kuxir state at stage " + std::to_string(stage));
                    }
                }
            }
            std::cout << "[state-audit] 30000/30000 valid\n";
            return 0;
        }
        KuxirTrainer trainer(std::move(config));
        trainer.run(smoke, benchmark ? 5 : 0);
        return 0;
    } catch (const c10::Error& e) {
        std::cerr << "TORCH_ERROR: " << e.what() << '\n'; return 2;
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << '\n'; return 1;
    }
}
