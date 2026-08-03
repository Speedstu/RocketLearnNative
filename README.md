# RocketLearn Native 

Native C++20/Rust implementation of the useful RocketLearn training loop, without Python, Redis, GigaLearn, or the Python GIL. The C++ process owns RocketSim environments, batched LibTorch inference, GAE/PPO learning, curriculum, metrics, and atomic checkpoints. The Rust supervisor owns lifecycle, logging, and crash recovery.

The design keeps RocketLearn's important training properties: PPO with GAE, stochastic discrete policy, shared self-play policy, observation/action masking, advantage normalization, automatic checkpoints, immutable policy versions, resume, and evaluation-ready version artifacts. On one machine it replaces serialized Redis rollouts with an in-process structure-of-arrays pipeline and one batched GPU call per decision step.

Generated builds, checkpoints, logs, SDK binaries, videos, and virtual environments are excluded from the repository. Clone with `--recurse-submodules` to obtain the optional legacy Python RocketSimVis visualizer.
