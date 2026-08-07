# RocketLearn Native

Native C++20/Rust Rocket League reinforcement-learning trainer built around RocketSim and LibTorch.

The repository contains one clean baseline: **standard Soccar 2v2 self-play**. The training loop keeps PPO/GAE, stochastic discrete actions, batched inference, checkpoint resume/versioning, past-policy league sampling, and the TrueSkill evaluator.

## Included

- `rocket_learn_native`: Soccar 2v2 PPO trainer.
- `rocket_learn_evaluator`: deterministic 2v2 checkpoint evaluator.
- Rust supervisor for restart/log handling.


## Clone

```bat
git clone --recurse-submodules https://github.com/Speedstu/RocketLearnNative.git
cd RocketLearnNative
```

For an existing clone:

```bat
git submodule update --init --recursive
```

## Build and train

```bat
BUILD.bat
START_TRAINING.bat
```

## Evaluator

```bat
BUILD_EVALUATOR.bat
START_EVALUATOR.bat
```


Install dependencies once:

```bat
```

Then:

```bat
```

