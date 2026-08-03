#include "kuxir_config.h"
#include "kuxir_env.h"
#include "model.h"

#include <RocketSim.h>
#include <torch/torch.h>
#include <winsock2.h>
#include <ws2tcpip.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <thread>

int main() {
    try {
        auto cfg = KuxirConfig::load();
        RocketSim::Init(std::filesystem::absolute(cfg.meshes), true);
        const int action_count = static_cast<int>(KuxirEnv::action_table().size());
        ActorCritic net(action_count);
        const auto checkpoint = cfg.checkpoints / "latest.pt";
        if (!std::filesystem::exists(checkpoint)) {
            std::cerr << "Checkpoint missing: " << checkpoint << '\n'; return 2;
        }
        torch::serialize::InputArchive archive;
        archive.load_from(checkpoint.string(), torch::kCPU);
        net->load(archive);
        net->eval();
        uint64_t checkpoint_steps = 0;
        try { torch::Tensor meta; archive.read("meta", meta); checkpoint_steps = meta[0].item<int64_t>(); } catch (...) {}

        WSADATA wsa{};
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 3;
        SOCKET socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        sockaddr_in target{};
        target.sin_family = AF_INET; target.sin_port = htons(9273);
        inet_pton(AF_INET, "127.0.0.1", &target.sin_addr);

        KuxirEnv env(cfg, static_cast<uint64_t>(cfg.seed) + 0x4B55584952ULL);
        int visual_stage = 0;
        if (const char* value = std::getenv("RLK_VIS_STAGE")) {
            try { visual_stage = std::clamp(std::stoi(value), 0, 2); } catch (...) {}
        }
        env.reset(checkpoint_steps, visual_stage);
        std::array<float, kObsSize> obs{};
        std::vector<uint8_t> mask(action_count);
        uint64_t steps = 0;
        auto next_frame = std::chrono::steady_clock::now();
        std::cout << "RocketSimVis Kuxir playback: " << checkpoint << " (30 Hz)\n";
        for (;;) {
            env.observe(obs.data()); env.action_mask(mask.data(), action_count);
            int64_t action = 0;
            {
                torch::NoGradGuard guard;
                auto input = torch::from_blob(obs.data(), {1, kObsSize}, torch::kFloat32).clone();
                auto action_mask = torch::from_blob(mask.data(), {1, action_count}, torch::kUInt8).to(torch::kBool);
                action = net->forward(input).first.masked_fill(action_mask.logical_not(), -1e9).argmax(-1).item<int64_t>();
            }
            const auto result = env.step(action, action_count, checkpoint_steps + steps++);
            const auto packet = env.rocketsimvis_json();
            sendto(socket, packet.data(), static_cast<int>(packet.size()), 0,
                   reinterpret_cast<const sockaddr*>(&target), sizeof(target));
            next_frame += std::chrono::microseconds(33333);
            std::this_thread::sleep_until(next_frame);
        }
    } catch (const std::exception& e) {
        std::cerr << "Kuxir visualizer error: " << e.what() << '\n'; return 1;
    }
}
