# RocketLearn Native — Heatseeker

Native C++20/Rust implementation of the useful RocketLearn training loop, without Python, Redis, GigaLearn, or the Python GIL. The C++ process owns RocketSim environments, batched LibTorch inference, GAE/PPO learning, curriculum, metrics, and atomic checkpoints. The Rust supervisor owns lifecycle, logging, and crash recovery.

The design keeps RocketLearn's important training properties: PPO with GAE, stochastic discrete policy, shared self-play policy, observation/action masking, advantage normalization, automatic checkpoints, immutable policy versions, resume, and evaluation-ready version artifacts. On one machine it replaces serialized Redis rollouts with an in-process structure-of-arrays pipeline and one batched GPU call per decision step.

## Heatseeker training

- True RocketSim `GameMode::HEATSEEKER`, 2v2, infinite boost, 120 Hz physics, 15 Hz decisions.
- 128-value team-mirrored observation with physics, orientation, teammates/opponents, Heatseeker target/speed, relative state and short-horizon ball projections.
- Masked 52-action table covering ground recovery, boost lines, jumps, fast aerials, air steering and rolls.
- From-scratch state-setter curriculum: reachable defensive returns, genuine Heatseeker kickoffs, then randomized high/fast rallies. The reset mix is 10% kickoff in stage 1, 25% in stage 2, and 15% in stage 3; all non-kickoff states explicitly arm RocketSim's `yTargetDir`, target speed, and hit timer so homing physics are active immediately. Genuine kickoffs intentionally keep `yTargetDir=0` until the first car touch, matching Heatseeker rules.
- Sparse zero-sum goals plus low-weight approach/facing/goal-side shaping, strong-return, aerial-touch and defensive-danger rewards. Reward magnitudes keep the actual objective dominant.
- Independent deterministic 2v2 TrueSkill league over immutable checkpoints. `skill_ratings.tsv` reports a baseline-relative `skill_rating` at 40 points per TrueSkill mu and its 95% uncertainty; old versions remain opponents, so progress is measured instead of inferred from training reward.
- RocketLearn-style past-version play in 20% of arenas. Only the current-policy side enters PPO in those games; opponent actions come from a frozen recent checkpoint, preventing policy forgetting without contaminating the on-policy batch.
- PPO defaults: gamma 0.995, lambda 0.95, clip 0.2, 3 epochs, Adam, gradient clipping, orthogonal init and LayerNorm.

## Run

`heatseeker\BUILD.bat` builds the C++ trainer and Rust supervisor. `heatseeker\START_TRAINING.bat` starts a minimized, automatically restarting background supervisor. `heatseeker\MONITOR.ps1` tails the current log. Checkpoints are under `checkpoints/heatseeker_from_scratch`.

`heatseeker\BUILD_EVALUATOR.bat` builds the CPU evaluator and `heatseeker\START_EVALUATOR.bat` runs its continuous checkpoint league without taking GPU time from training. Ratings are stored atomically in `checkpoints/heatseeker_from_scratch/skill_ratings.tsv`; detailed match output is in `logs/skill-evaluator.log`.
The highest conservative score (`mu - 2 sigma`) is also promoted atomically to `best.pt`, with its step count in `best_version.txt`, so a temporary regression never overwrites the strongest verified bot.

## Kuxir Pinch specialist

The Heatseeker run is paused and preserved. The independent Kuxir project uses `rocket_kuxir_native.exe`, `rocket-kuxir-supervisor.exe`, and `checkpoints/kuxir_pinch_from_scratch`; it never reads or overwrites Heatseeker checkpoints.

The curriculum is deliberately mechanical rather than generic Soccar:

- every stage starts car and ball on the ground, exactly perpendicular to the side wall, with the car directly behind the ball; stages only increase approach distance and reduce initial momentum;
- the policy must push the ball straight into the wall, follow it up naturally, then air-roll/flip into the rear quarter for the pinch—there are no teleported wall states;
- a pinch only counts during an actual flip contact near the side wall, with a 900+ uu/s impulse and the ball leaving inward, toward the opponent goal, above 2700 uu/s; 4200+ uu/s remains the separately tracked elite-speed objective;
- weak wall contacts are only a temporary curriculum reward and decay as training advances. Pinch speed, direction, goal conversion, and strict pinch quality dominate later learning.

Build and launch with `kuxir_pinch\BUILD_KUXIR.bat` and `kuxir_pinch\START_KUXIR_TRAINING.bat`. Tail the current run with `kuxir_pinch\MONITOR_KUXIR.ps1`. The build and launch scripts for RocketSimVis are in the same folder.

The native data path was benchmarked without changing PPO semantics or precision. Reusing rollout buffers/results, computing `log_softmax` once, and increasing the batch from 256 environments/8 workers to 512/12 raised steady throughput from roughly 53–54k to 69–71k transitions/s. Tick skip remains 4 for the contact timing precision a Kuxir pinch needs, and PPO remains three epochs with 32,768-sample minibatches.

Kuxir overrides use the `RLK_` prefix: `RLK_ENVS`, `RLK_ENV_THREADS`, `RLK_ROLLOUT_DECISIONS`, `RLK_MINIBATCH`, `RLK_EPOCHS`, `RLK_LR`, `RLK_ENTROPY`, `RLK_MAX_EPISODE_DECISIONS`, `RLK_CHECKPOINTS`, and `RLK_MESHES`.

`heatseeker\START_VISUALIZER.bat` launches ZealanL's RocketSimVis plus a native CPU-inference playback of the current `latest.pt`. The C++ player sends RocketSimVis-compatible JSON directly over UDP port 9273. Playback is deliberately separate from the training arenas, so watching it does not stall rollout collection or move the live training state.

RocketSim is included under `third_party/RocketSim`. LibTorch and the CUDA 11.8 headers are intentionally excluded from Git because of their size; place them under `third_party/libtorch` and `third_party/cuda118-sdk` before building. The project has no GigaLearn source or binary dependency.

The AMD/ZLUDA launcher uses the separately maintained custom ZLUDA/HIP runtime. It defaults to `D:\GigaLearnCPP_GLAZE_DISCRETE` for compatibility with the original machine; friends can point it elsewhere by setting `RL_RUNTIME_ROOT` before building or launching.

Generated builds, checkpoints, logs, SDK binaries, videos, and virtual environments are excluded from the repository. Clone with `--recurse-submodules` to obtain the optional legacy Python RocketSimVis visualizer.
