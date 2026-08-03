# Kuxir Pinch training record

## 2026-08-03 — reference-video correction (current run)

- The supplied 63-second reference was inspected frame by frame. The required setup is strictly ground-started: car and ball aligned on the same lateral line, both travelling at 90 degrees into the side wall; the car pushes the ball up the curved wall, follows it, then air-rolls/flips into the rear quarter.
- All wall-teleport setters were rejected and archived. Every curriculum stage now starts both objects on the ground and differs only in wall distance, car-ball gap, initial speed and available boost. RocketSim uses normal boost consumption.
- Reset validation checks ground height, same `y`, exact outward heading, car-behind-ball ordering and arena bounds. A compiled audit passed 30,000/30,000 randomized resets across all stages; invalid runtime states terminate immediately.
- RocketSimVis defaults to stage 0, so playback now always demonstrates the perpendicular ground approach rather than a random wall spawn. `RLK_VIS_STAGE=1` or `2` selects the longer variants.
- The corrected from-scratch run produced its first strict flip pinches by 1.6–2.3M transitions, including 2732 and 3211 uu/s contacts; wall-contact peaks reached 3569 uu/s. Training remained stable around 67–69k SPS with no NaN or crash.
- After removing a repeat-touch setup reward, `setups` now count only the one-time event where the pushed ball actually reaches/climbs the wall. The easiest perpendicular approach remains exclusive through 100M transitions; longer approaches enter at 100M and 300M instead of prematurely at 30M/120M.
- User visual review found the perpendicular geometry correct but too close to the wall. Stage wall distances were increased from 650–1000 / 1050–1700 / 1550–2500 uu to 1400–2000 / 2200–3400 / 3200–3850 uu. The final maximum is capped only by the same-side Soccar field geometry.
- Superseded wall-spawn checkpoints are preserved only under `checkpoints/kuxir_rejected_*` and are never resumed by the current trainer.

## 2026-08-03 — launch

- Heatseeker is paused and its latest/best checkpoints are preserved separately.
- Kuxir trainer starts from scratch with 512 one-car RocketSim arenas, 12 environment workers, tick skip 4, 90 masked discrete controls, PPO/GAE, and the existing 512-512-256 actor-critic.
- Equivalent short benchmarks improved from about 53–54k SPS at 256 arenas/8 workers to 69–71k SPS at 512/12. Training math, precision, epochs, and transition content are unchanged.
- The first 3.3M transitions were stable at about 70k SPS. Wall touches rose from roughly 350/update to over 1,000/update; the first strict 2900+ uu/s wall pinches appeared at 1.4M. No NaN, crash, or checkpoint failure occurred.
- Do not broaden the curriculum before the scheduled 30M transition gate; stage 1 is intentionally teaching repeatable contact and compression first.

## 2026-08-03 — early-run correction and curriculum gate

- The first reward version developed ordinary-wall-touch farming: touches exceeded 12,000/update while policy entropy collapsed near 2.2 and strict pinch speed stayed on the threshold. That rejected checkpoint is preserved under `checkpoints/kuxir_rejected_touch_farming_20260803_2118` for diagnosis only.
- Strict classification now also requires a real 500+ uu/s contact impulse, 450+ uu/s inward exit, and 3000+ uu/s total speed. Temporary wall-contact shaping has no unconditional positive reward.
- The corrected run held 67–70k SPS without NaN or crashes. At 28–30M it produced roughly 30–40 strict pinches/update around 3.17k uu/s while retaining about 4.0 policy entropy.
- Stage instrumentation at 38–62M proved the initial ground-to-wall setter was too abrupt: it yielded only 7–26 contacts and zero strict pinches per update. The stage-2 approach was shortened to the wall seam and the rolling-ball/car velocity ranges were made continuous with stage 1. High-speed strict pinches now have a convex bonus, while only 4200+ contacts receive the explicit fast-pinch bonus.
- A second check through 103M showed the shortened ground entry improved contacts but still produced zero strict pinches in that branch. Stage 2 is therefore now an explicit bridge: 85% long wall chases and 15% seam entries before 120M, then 65/35. This preserves the successful close-contact distribution while progressively introducing the harder entry instead of creating a sparse-reward cliff.
- At 110M, per-stage counters exposed another curriculum leak: the stage-one-hot observation let the network silo a successful contact controller in stage 1 while stage 2 remained reward-sparse. Setter IDs were removed from policy input (physics already identify every situation), and the wall-chase distance now overlaps the close-contact distribution. Metrics retain stage labels for monitoring, but the policy must learn one transferable Kuxir controller.
- After the 120M gate, the infield setter generated contacts but no pinches. Its required first touch had incorrectly inherited the generic off-wall penalty. A bounded `setup_touch` reward now recognizes only touches that send the ball outward toward the side wall and forward; it remains much smaller than the strict-pinch reward and is logged separately, so setup learning cannot masquerade as pinch skill.

## 2026-08-03 — validated handoff

- Removing the stage silo worked immediately: from 112.9M onward, the bridge branch produced 4–22 strict pinches/update instead of zero, while the close-contact branch retained 90–130/update and pinch goals continued.
- The 120M curriculum transition was stable: the new infield branch began producing 0–9 valid outward setup touches/update, the two learned branches retained strict pinches, SPS remained about 67–69k, entropy stayed near 4.08–4.10, and there were no NaNs, crashes, or checkpoint failures.
- Training remains supervised in the background and resumes atomically from `latest.pt`. Do not judge the 4200+ fast-pinch objective from this early curriculum phase; current strict contacts are roughly 3.2–3.55k uu/s and speed/goal bonuses remain active.
