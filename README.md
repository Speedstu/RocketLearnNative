# RocketLearn Native

Native C++20/Rust Rocket League reinforcement-learning trainer built around RocketSim and LibTorch.

The repository contains one clean baseline: **standard Soccar 2v2 self-play**. The training loop keeps PPO/GAE, stochastic discrete actions, batched inference, checkpoint resume/versioning, past-policy league sampling, and the TrueSkill evaluator.

## Included

- `rocket_learn_native`: Soccar 2v2 PPO trainer.
- `rocket_learn_evaluator`: deterministic 2v2 checkpoint evaluator.
- `rocket_learn_visualizer`: UDP playback sender for the Python renderer.
- `RocketSimVis`: public Python RocketSimVis submodule.
- Rust supervisor for restart/log handling.

The private renderer source is not part of the active project.

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

## Python RocketSimVis

Install dependencies once:

```bat
python -m pip install -r RocketSimVis\requirements.txt
```

Then:

```bat
BUILD_VISUALIZER.bat
START_VISUALIZER.bat
```

Playback uses the standard RocketSimVis JSON protocol over UDP port `9273`.
