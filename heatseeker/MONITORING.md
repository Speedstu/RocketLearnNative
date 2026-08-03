# Continuous training record

## 2026-08-03 — 200M agent transitions

- Native trainer, Rust supervisor, and CPU TrueSkill evaluator are alive; checkpoints continue atomically every 10 updates and immutable versions every 100 updates.
- PPO remains numerically stable: KL is about `0.0008`, entropy about `3.25`, with no NaN, crash, or resume failure.
- Past-version play is active in about 20% of arenas. Only the current-policy team is admitted to PPO, preserving on-policy correctness.
- Mean touches/update rose from `59.1` over updates 1300–1600 to `67.3` over 1700–2000 (`+13.9%`), while goals/update stayed essentially flat (`387.0` to `386.5`). This is the expected early interception signal, so no reward/state-setter change is justified yet.
- The pre-league version chain regressed relative to the 29.5M checkpoint. `best.pt` therefore remains that conservative TrueSkill winner. The first fully league-trained versions are only now entering evaluation; do not infer a plateau before several hundred million transitions.
- Capacity expansion is gated on a sustained, statistically supported plateau around 5–10B transitions, per the objective. It is intentionally not triggered at this early stage.

Evaluation policy: 96+ deterministic 2v2 games per version, alternating team colors, TrueSkill uncertainty target `sigma <= 2`, plus continuing newest-vs-predecessor, newest-vs-best, and closest-rating refinement games. `skill_rating = 40 * (mu - baseline_mu)` and `confidence_95 = 80 * sigma`.

## 2026-08-03 — 342M agent transitions

- All three processes are still continuously alive; current throughput is about `58.8k` agent transitions/s with league play enabled. No crash, NaN, KL spike, checkpoint failure, or evaluator error occurred.
- Interception learning is sustained rather than noise: mean touches/update increased `76.6 -> 85.0 -> 93.0` across the 200–250M, 250–300M, and 300–343M windows. Touches per goal increased `0.20 -> 0.22 -> 0.24`; goals/update stayed flat around `388`, so the improvement is not caused by longer/easier episodes.
- TrueSkill recovered from the pre-league regression. The verified best moved from 29.5M to 265.4M (`best.pt`), and the 334.2M checkpoint reached rating `56 ± 92` while still being refined. This is early positive league evidence, not a plateau.
- Entropy remains healthy near `3.22` (maximum for 43 actions is about `3.76`) and KL remains near `0.001`, so exploration and PPO update size remain appropriate. No hyperparameter intervention is justified.

## 2026-08-03 — 553M agent transitions

- Trainer/supervisor/evaluator have remained alive without restart. Throughput holds near `58.4k` transitions/s; PPO remains stable (`KL ~0.0011`, entropy `3.16`) with no NaN or evaluator error.
- Learning accelerated through the requested 200–500M region. Mean touches/update progressed `105.7 -> 123.2 -> 141.4 -> 165.6` across 350–400M, 400–450M, 450–500M, and 500–554M. Touches per goal rose `0.274 -> 0.319 -> 0.369 -> 0.432`, while goals/update stayed near `383–386`.
- The verified TrueSkill curve is now clearly positive: ratings reached `100` at 373.6M, `148` at 452.2M, `196` at 511.2M, and `241 ± 82` at 540.7M. The conservative best was promoted to 540.7M (`best.pt`).
- This is sustained improvement, not a plateau. Keep reward, network size, PPO settings, curriculum, and league ratio unchanged; intervention now would discard a healthy learning regime.

## 2026-08-03 — 553–561M reliability maintenance

- At 553M, learning remained strongly positive: mean touches/update rose from `105.7` (350–400M) to `165.6` (500–554M), touch/goal from `0.274` to `0.432`, and TrueSkill reached a verified `241 ± 82` at 540.7M. `best.pt` advanced accordingly.
- Closed a long-horizon checkpoint race before it could manifest: immutable version files are now copied to a temporary name and atomically renamed. The evaluator also retries transient checkpoint-load failures instead of exiting.
- Both binaries rebuilt cleanly. Training resumed from update 5670, completed the one-time ZLUDA warmup, returned to about `59k` transitions/s, and successfully emitted atomic `560332800.pt` with no leftover temporary file. Evaluator and supervisor remain alive.
