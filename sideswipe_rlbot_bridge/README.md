# SideSwipe RLBot Bridge v2

Private-match / local test bridge for the SideSwipe PPO policy. It deliberately does not bypass anti-cheat or inject into the game process: state comes from the Android display stream and controls go through the emulator's normal multitouch input device over ADB.

## Implemented

- Exact 72-float observation contract through the same `SideSwipeEnv::observe()` used for training.
- 16-action policy inference from a local `.pt` file or checkpoint directory.
- Persistent multitouch input: analog stick + jump + boost can be held simultaneously.
- Persistent H.264 capture decoded by FFmpeg, with `adb screencap` fallback.
- Physics-aided hidden-state observer using the same SideSwipe simulator as training.
- Automatic resolution scaling from the calibration reference resolution.
- Tracking watchdog that releases all controls when ball/car tracking is lost.
- `--observe-only` / `--dry-run` calibration mode.
- One-bot and two-emulator bot-vs-bot launchers.
- Rolling champion downloader with fallback to `checkpoints/sideswipe_from_scratch/latest.pt`.

## Intended use

Private matches, bot-vs-bot evaluation and controlled transfer testing. Do not use this bridge to automate public/ranked matchmaking.

The v2 source changes are in `sideswipe_play_v2.patch`; scripts can be copied into `D:\RocketLearnNative` by `INSTALL_RLBOT_BRIDGE.ps1` from the downloadable bridge package.
