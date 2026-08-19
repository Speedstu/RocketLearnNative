# SideSwipe OMEN Ceiling Stack

This stack keeps the current verified transfer contract: **72 observations / 16 discrete actions / tick-skip 6**.

## One-click setup

Run from the repository root on Windows:

```bat
SETUP_SIDESWIPE_OMEN_AUTO.bat
```

It installs/builds the Windows prerequisites, reconstructs the SHA-256 verified SideSwipe simulator source, verifies the 16-action contract, fetches the current rolling champion, builds the local trainer/evaluator, wires the best local champion into the one-instance lab, creates Desktop shortcuts, and starts the curriculum unless `-NoTrainingStart` is used on the PowerShell script.

## Ceiling training

`START_SIDESWIPE_CEILING_TRAINING.bat` runs a resumable high-level curriculum. Each stage trains a candidate from the current champion. The champion is never replaced unless the candidate passes both a phase-1 and a fresh confirmation evaluation in 1v1 and 2v2. After the curriculum, four ceiling-search recipes are tried per generation. The search stops after two consecutive complete generations fail to produce a statistically confirmed promotion.

That stop condition is a **measured plateau for this policy contract and search space**, not a claim that the theoretical Rocket League Sideswipe skill ceiling has been solved.

## RLBot-like one-instance lab

`START_SIDESWIPE_RLBOT_LAB.bat` is the robust default: one custom policy controls the local car in a single real Sideswipe emulator instance against the native Exhibition bot. The resolver automatically uses a locally promoted ceiling champion when one exists, otherwise the rolling cloud champion.

`START_SIDESWIPE_RLBOT_BOTVBOT.bat` is the experimental two-custom-policy path. It remains fail-closed until read-only runtime discovery and validation succeeds on the installed Sideswipe build.

Use only in offline Training/Exhibition/private controlled testing. The setup intentionally does not automate Epic account credentials and does not enable unvalidated internal writes.
