# RocketLearn Native

C++20/Rust Rocket League RL trainer built around RocketSim and LibTorch.

The main baseline here is normal Soccar 2v2 self-play with PPO/GAE. It has batched inference, checkpoint resume/versioning, old-policy sampling and a separate evaluator.

## Clone

```bat
git clone --recurse-submodules https://github.com/Speedstu/RocketLearnNative.git
cd RocketLearnNative
```

Already cloned without submodules:

```bat
git submodule update --init --recursive
```

## Train

```bat
BUILD.bat
START_TRAINING.bat
```

## Evaluate

```bat
BUILD_EVALUATOR.bat
START_EVALUATOR.bat
```

`rocket_learn_native` is the trainer and `rocket_learn_evaluator` is the deterministic 2v2 evaluator. There is also a small Rust supervisor for restart/log handling.

Most experiment-specific launchers live next to the main scripts. They are there because I use this repo as a working training tree, not as a polished library.
