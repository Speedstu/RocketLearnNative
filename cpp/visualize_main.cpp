#include "config.h"
#include "soccar_env.h"
#include "model.h"

#include <RocketSim.h>
#include <torch/torch.h>
#include <winsock2.h>
#include <ws2tcpip.h>

#include <array>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <thread>
#include <vector>

int main() {
    try {
        auto cfg = Config::load();
        RocketSim::Init(std::filesystem::absolute(cfg.meshes), true);

        const int action_count = static_cast<int>(SoccarEnv::action_table().size());
        ActorCritic net(action_count);
        const auto checkpoint = cfg.checkpoints / "latest.pt";
        if (!std::filesystem::exists(checkpoint)) {
            std::cerr << "Checkpoint missing: " << checkpoint << '\n';
            return 2;
        }

        torch::serialize::InputArchive archive;
        archive.load_from(checkpoint.string(), torch::kCPU);
        net->load(archive);
        net->eval();

        uint64_t checkpoint_steps = 0;
        try {
            torch::Tensor meta;
            archive.read("meta", meta);
            checkpoint_steps = static_cast<uint64_t>(meta[0].item<int64_t>());
        } catch (...) {}

        WSADATA wsa{};
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 3;

        SOCKET socket_fd = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (socket_fd == INVALID_SOCKET) return 4;

        sockaddr_in target{};
        target.sin_family = AF_INET;
        target.sin_port = htons(9273);
        inet_pton(AF_INET, "127.0.0.1", &target.sin_addr);

        SoccarEnv env(cfg, static_cast<uint64_t>(cfg.seed) + 0x524C5649ULL);
        std::array<float, 4 * kObsSize> obs{};
        std::vector<uint8_t> masks(4 * action_count);
        std::array<int64_t, 4> actions{};

        uint64_t steps = 0;
        auto next_frame = std::chrono::steady_clock::now();

        std::cout << "Python RocketSimVis playback: " << checkpoint
                  << " (CPU inference, UDP 9273, 15 Hz)\n";

        for (;;) {
            env.observe(obs.data());
            env.action_masks(masks.data(), action_count);

            torch::NoGradGuard guard;
            auto x = torch::from_blob(obs.data(), {4, kObsSize}, torch::kFloat32).clone();
            auto mask = torch::from_blob(masks.data(), {4, action_count}, torch::kUInt8).to(torch::kBool);
            auto logits = net->forward(x).first.masked_fill(mask.logical_not(), -1e9);
            auto selected = logits.argmax(-1).to(torch::kCPU);
            std::memcpy(actions.data(), selected.data_ptr<int64_t>(), sizeof(actions));

            env.step(actions.data(), action_count, checkpoint_steps + steps);
            steps += 4;

            const auto packet = env.rocketsimvis_json();
            sendto(socket_fd, packet.data(), static_cast<int>(packet.size()), 0,
                   reinterpret_cast<const sockaddr*>(&target), sizeof(target));

            next_frame += std::chrono::microseconds(66667);
            std::this_thread::sleep_until(next_frame);
        }
    } catch (const std::exception& e) {
        std::cerr << "Visualizer playback error: " << e.what() << '\n';
        return 1;
    }
}
