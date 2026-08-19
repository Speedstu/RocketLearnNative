from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Tuple

Z95 = 1.645
MODE_WEIGHTS = {1: 0.60, 2: 0.40}
MIN_MODE = {1: 0.505, 2: 0.505}
SCORE_RE = re.compile(r"\bscore=([0-9.]+)")
FIELD_RE = re.compile(r"\b(W|L|D)=([0-9]+)")

BASE_ENV = {
    "RLS_ENVS": "1024",
    "RLS_ENV_THREADS": "12",
    "RLS_TORCH_THREADS": "1",
    "RLS_MIXED": "1",
    "RLS_TRANSFER_SAFE_OBS": "1",
    "RLS_TICK_SKIP": "6",
    "RLS_ROLLOUT_DECISIONS": "128",
    "RLS_EPOCHS": "3",
    "RLS_MINIBATCH": "32768",
    "RLS_NO_TOUCH_SECONDS": "5",
    "RLS_SAVE_EVERY": "10",
    "RLS_VERSION_EVERY": "25",
    "RLS_PAST_POOL": "24",
    "RLS_LR": "0.000045",
    "RLS_ENTROPY": "0.0070",
    "RLS_PAST_RATIO": "0.48",
    "RLS_RATIO_1V1": "0.72",
    "RLS_TEAM_SPIRIT": "0.32",
    "RLS_MECH_LATE_SCALE": "0.76",
    "RLS_GAMMA": "0.9970",
    "RLS_GAE_LAMBDA": "0.960",
    "RLS_CLIP": "0.18",
    "RLS_W_FLIP_RESET": "2.30",
    "RLS_W_PURPLE": "1.60",
    "RLS_W_MUSTY": "0.26",
    "RLS_W_AIR_DRIBBLE": "0.44",
    "RLS_W_RESET_SEEK": "0.013",
}

CURRICULUM = [
    ("fundamentals-refresh", 1, 70, {
        "RLS_LR": "0.000025", "RLS_ENTROPY": "0.0055", "RLS_PAST_RATIO": "0.58",
        "RLS_RATIO_1V1": "0.78", "RLS_TEAM_SPIRIT": "0.30", "RLS_MECH_LATE_SCALE": "0.45",
        "RLS_GAMMA": "0.9975", "RLS_GAE_LAMBDA": "0.965",
        "RLS_W_FLIP_RESET": "1.20", "RLS_W_PURPLE": "0.90", "RLS_W_MUSTY": "0.10",
        "RLS_W_AIR_DRIBBLE": "0.24", "RLS_W_RESET_SEEK": "0.006",
    }),
    ("advanced-mechanics", 3, 120, {
        "RLS_LR": "0.000035", "RLS_ENTROPY": "0.0070", "RLS_PAST_RATIO": "0.52",
        "RLS_RATIO_1V1": "0.70", "RLS_TEAM_SPIRIT": "0.32", "RLS_MECH_LATE_SCALE": "0.90",
        "RLS_GAMMA": "0.9975", "RLS_GAE_LAMBDA": "0.970", "RLS_CLIP": "0.17",
        "RLS_W_FLIP_RESET": "2.80", "RLS_W_PURPLE": "1.95", "RLS_W_MUSTY": "0.34",
        "RLS_W_AIR_DRIBBLE": "0.58", "RLS_W_RESET_SEEK": "0.017",
    }),
    ("duel-pressure", 3, 120, {
        "RLS_LR": "0.000030", "RLS_ENTROPY": "0.0058", "RLS_PAST_RATIO": "0.60",
        "RLS_RATIO_1V1": "0.84", "RLS_TEAM_SPIRIT": "0.26", "RLS_MECH_LATE_SCALE": "0.72",
        "RLS_GAMMA": "0.9980", "RLS_GAE_LAMBDA": "0.970", "RLS_CLIP": "0.16",
    }),
    ("team-strategy", 3, 120, {
        "RLS_LR": "0.000030", "RLS_ENTROPY": "0.0060", "RLS_PAST_RATIO": "0.58",
        "RLS_RATIO_1V1": "0.48", "RLS_TEAM_SPIRIT": "0.48", "RLS_MECH_LATE_SCALE": "0.72",
        "RLS_GAMMA": "0.9980", "RLS_GAE_LAMBDA": "0.970", "RLS_CLIP": "0.16",
    }),
    ("long-horizon", 3, 150, {
        "RLS_LR": "0.000025", "RLS_ENTROPY": "0.0055", "RLS_PAST_RATIO": "0.62",
        "RLS_RATIO_1V1": "0.66", "RLS_TEAM_SPIRIT": "0.38", "RLS_MECH_LATE_SCALE": "0.70",
        "RLS_GAMMA": "0.9990", "RLS_GAE_LAMBDA": "0.980", "RLS_CLIP": "0.15",
    }),
]

SEARCH_RECIPES = [
    ("precision-duel", 110, {
        "RLS_LR": "0.000022", "RLS_ENTROPY": "0.0048", "RLS_PAST_RATIO": "0.64",
        "RLS_RATIO_1V1": "0.80", "RLS_TEAM_SPIRIT": "0.30", "RLS_GAMMA": "0.9985",
        "RLS_GAE_LAMBDA": "0.975", "RLS_CLIP": "0.15", "RLS_MECH_LATE_SCALE": "0.70",
    }),
    ("balanced-ceiling", 130, {
        "RLS_LR": "0.000026", "RLS_ENTROPY": "0.0058", "RLS_PAST_RATIO": "0.60",
        "RLS_RATIO_1V1": "0.66", "RLS_TEAM_SPIRIT": "0.38", "RLS_GAMMA": "0.9985",
        "RLS_GAE_LAMBDA": "0.975", "RLS_CLIP": "0.16", "RLS_MECH_LATE_SCALE": "0.76",
    }),
    ("mechanics-ceiling", 130, {
        "RLS_LR": "0.000024", "RLS_ENTROPY": "0.0062", "RLS_PAST_RATIO": "0.60",
        "RLS_RATIO_1V1": "0.68", "RLS_TEAM_SPIRIT": "0.34", "RLS_GAMMA": "0.9980",
        "RLS_GAE_LAMBDA": "0.975", "RLS_CLIP": "0.16", "RLS_MECH_LATE_SCALE": "0.90",
        "RLS_W_FLIP_RESET": "2.95", "RLS_W_PURPLE": "2.00", "RLS_W_MUSTY": "0.35",
        "RLS_W_AIR_DRIBBLE": "0.60", "RLS_W_RESET_SEEK": "0.018",
    }),
    ("team-ceiling", 130, {
        "RLS_LR": "0.000024", "RLS_ENTROPY": "0.0055", "RLS_PAST_RATIO": "0.64",
        "RLS_RATIO_1V1": "0.52", "RLS_TEAM_SPIRIT": "0.50", "RLS_GAMMA": "0.9987",
        "RLS_GAE_LAMBDA": "0.978", "RLS_CLIP": "0.15", "RLS_MECH_LATE_SCALE": "0.72",
    }),
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def atomic_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def run_live(cmd: List[str], env: Dict[str, str], cwd: Path, log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8", errors="replace") as log:
        log.write("\n$ " + subprocess.list2cmdline(cmd) + "\n")
        log.flush()
        proc = subprocess.Popen(cmd, cwd=str(cwd), env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, bufsize=1,
                                encoding="utf-8", errors="replace")
        assert proc.stdout is not None
        for line in proc.stdout:
            print(line, end="", flush=True)
            log.write(line)
        rc = proc.wait()
    if rc != 0:
        raise RuntimeError(f"command failed rc={rc}: {subprocess.list2cmdline(cmd)}")


def eval_once(eval_bin: Path, candidate: Path, opponent: Path, mode: int, episodes: int,
              seed: int, cwd: Path) -> Dict:
    cmd = [str(eval_bin), "--candidate", str(candidate), "--opponent", str(opponent),
           "--episodes", str(episodes), "--team-size", str(mode), "--seed", str(seed)]
    out = subprocess.check_output(cmd, cwd=str(cwd), text=True, stderr=subprocess.STDOUT,
                                  encoding="utf-8", errors="replace")
    print(out, end="")
    fields = {k: int(v) for k, v in FIELD_RE.findall(out)}
    score_m = SCORE_RE.search(out)
    if set(fields) != {"W", "L", "D"} or not score_m:
        raise RuntimeError("could not parse evaluator output:\n" + out)
    n = fields["W"] + fields["L"] + fields["D"]
    if n != episodes:
        raise RuntimeError(f"evaluator episode count mismatch: expected {episodes}, got {n}")
    exact = (fields["W"] + 0.5 * fields["D"]) / n
    return {"mode": mode, "episodes": n, "seed": seed, "wins": fields["W"],
            "losses": fields["L"], "draws": fields["D"], "score": exact,
            "output": out.strip()}


def aggregate(rows: List[Dict]) -> Dict:
    by_mode = {}
    for mode in (1, 2):
        rr = [r for r in rows if r["mode"] == mode]
        n = sum(r["episodes"] for r in rr)
        w = sum(r["wins"] for r in rr)
        d = sum(r["draws"] for r in rr)
        by_mode[mode] = {"episodes": n, "score": (w + 0.5 * d) / n}
    combined = sum(MODE_WEIGHTS[m] * by_mode[m]["score"] for m in (1, 2))
    variance = sum((MODE_WEIGHTS[m] ** 2) * 0.25 / by_mode[m]["episodes"] for m in (1, 2))
    lcb = combined - Z95 * math.sqrt(variance)
    qualifies = lcb > 0.5 and all(by_mode[m]["score"] >= MIN_MODE[m] for m in (1, 2))
    return {
        "score_1v1": by_mode[1]["score"], "score_2v2": by_mode[2]["score"],
        "episodes_1v1": by_mode[1]["episodes"], "episodes_2v2": by_mode[2]["episodes"],
        "combined_score": combined, "combined_lcb95": lcb, "qualifies": qualifies,
    }


def evaluate_candidate(eval_bin: Path, cand: Path, parent: Path, seed_base: int,
                       cwd: Path, confirmation: bool = False) -> Tuple[List[Dict], Dict]:
    if confirmation:
        spec = [(1, 500, seed_base + 1), (1, 500, seed_base + 2),
                (2, 300, seed_base + 11), (2, 300, seed_base + 12)]
    else:
        spec = [(1, 300, seed_base + 1), (1, 300, seed_base + 2),
                (2, 200, seed_base + 11), (2, 200, seed_base + 12)]
    rows = [eval_once(eval_bin, cand, parent, m, ep, seed, cwd) for m, ep, seed in spec]
    return rows, aggregate(rows)


def load_state(path: Path) -> Dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"schema": 1, "curriculum_index": 0, "generation": 0, "no_improve": 0,
            "plateau": False, "history": [], "created_at": time.time()}


def save_state(path: Path, state: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def candidate_env(checkpoint_dir: Path, seed: int, force_stage: int, overrides: Dict[str, str]) -> Dict[str, str]:
    env = os.environ.copy()
    env.update(BASE_ENV)
    env.update(overrides)
    env["RLS_CHECKPOINTS"] = str(checkpoint_dir)
    env["RLS_SEED"] = str(seed)
    env["RLS_FORCE_STAGE"] = str(force_stage)
    env.setdefault("WANDB_DISABLED", "true")
    env.setdefault("WANDB_MODE", "disabled")
    return env


def prepare_candidate(parent: Path, out_dir: Path) -> None:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "versions").mkdir(parents=True, exist_ok=True)
    atomic_copy(parent, out_dir / "latest.pt")
    atomic_copy(parent, out_dir / "versions" / "000000000_parent.pt")


def train_candidate(train_bin: Path, parent: Path, runs_dir: Path, name: str, updates: int,
                    seed: int, force_stage: int, overrides: Dict[str, str], cwd: Path) -> Path:
    run_dir = runs_dir / name
    prepare_candidate(parent, run_dir)
    env = candidate_env(run_dir, seed, force_stage, overrides)
    print(f"\n=== TRAIN {name} | updates={updates} | stage={force_stage} ===")
    run_live([str(train_bin), "--train-updates", str(updates)], env, cwd, run_dir / "train.log")
    ckpt = run_dir / "latest.pt"
    if not ckpt.exists() or ckpt.stat().st_size < 100_000:
        raise RuntimeError(f"candidate checkpoint missing/too small: {ckpt}")
    return ckpt


def promote(candidate: Path, champion: Path, archive_dir: Path, lab_dir: Path | None, record: Dict) -> str:
    old_sha = sha256(champion)
    archive_dir.mkdir(parents=True, exist_ok=True)
    atomic_copy(champion, archive_dir / f"{int(time.time())}_{old_sha[:12]}.pt")
    atomic_copy(candidate, champion)
    new_sha = sha256(champion)
    meta = {"source": "local-ceiling-supervisor", "sha256": new_sha,
            "promoted_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "record": record}
    (champion.parent / "champion.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    if lab_dir:
        lab_ckpt = lab_dir / "checkpoints" / "local_ceiling_champion.pt"
        atomic_copy(champion, lab_ckpt)
        (lab_dir / "checkpoints" / "local_ceiling_champion.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return new_sha


def main() -> int:
    ap = argparse.ArgumentParser(description="SideSwipe current-contract ceiling curriculum + conservative promotion loop")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent))
    ap.add_argument("--max-generations", type=int, default=50)
    ap.add_argument("--skip-curriculum", action="store_true")
    ap.add_argument("--reset-state", action="store_true")
    args = ap.parse_args()
    root = Path(args.root).resolve(); repo = root.parent; bin_dir = root / "bin"
    train_bin = bin_dir / ("sideswipe_train.exe" if os.name == "nt" else "sideswipe_train")
    eval_bin = bin_dir / ("sideswipe_eval.exe" if os.name == "nt" else "sideswipe_eval")
    champion = root / "checkpoints" / "champion.pt"; state_path = root / "state" / "ceiling_state.json"
    runs_dir = root / "runs"; archive_dir = root / "checkpoints" / "archive"
    lab_dir = repo / "sideswipe_one_instance_lab"; lab_dir = lab_dir if lab_dir.exists() else None
    for p in (train_bin, eval_bin, champion):
        if not p.exists(): print(f"[fatal] missing: {p}", file=sys.stderr); return 2
    if args.reset_state and state_path.exists(): state_path.unlink()
    state = load_state(state_path); state["champion_sha256"] = sha256(champion); save_state(state_path, state)
    print("============================================================")
    print(" SIDESWIPE CEILING SUPERVISOR | 72 OBS / 16 ACTION CONTRACT")
    print("============================================================")
    print("Champion:", champion); print("SHA256  :", state["champion_sha256"])
    print("Rule    : never promote without phase1 + fresh confirmation gate")
    print("Stop    : 2 consecutive no-improvement search generations")
    try:
        if not args.skip_curriculum:
            while state.get("curriculum_index", 0) < len(CURRICULUM):
                idx = state["curriculum_index"]
                name, force_stage, updates, overrides = CURRICULUM[idx]
                parent_sha = sha256(champion); run_name = f"curr_{idx:02d}_{name}"
                cand = train_candidate(train_bin, champion, runs_dir, run_name, updates, 2026100000 + idx * 1000, force_stage, overrides, repo)
                rows1, s1 = evaluate_candidate(eval_bin, cand, champion, 2026110000 + idx * 100, repo, False)
                rec = {"kind": "curriculum", "name": name, "parent_sha": parent_sha,
                       "phase1": s1, "phase1_rows": rows1, "updates": updates, "overrides": overrides}
                if s1["qualifies"]:
                    rows2, s2 = evaluate_candidate(eval_bin, cand, champion, 2026120000 + idx * 100, repo, True)
                    rec["confirmation"] = s2; rec["confirmation_rows"] = rows2
                    if s2["qualifies"]:
                        rec["promoted"] = True; rec["new_sha"] = promote(cand, champion, archive_dir, lab_dir, rec)
                        print(f"[PROMOTED] curriculum {name} -> {rec['new_sha'][:16]}")
                    else: rec["promoted"] = False; print(f"[REJECT] {name}: confirmation gate failed")
                else: rec["promoted"] = False; print(f"[REJECT] {name}: phase1 gate failed")
                state["history"].append(rec); state["curriculum_index"] = idx + 1
                state["champion_sha256"] = sha256(champion); save_state(state_path, state)
        while state.get("generation", 0) < args.max_generations and not state.get("plateau", False):
            gen = state["generation"] + 1; parent_sha = sha256(champion)
            print(f"\n################ GENERATION {gen} | parent={parent_sha[:16]} ################")
            qualified = []; gen_records = []
            for ridx, (recipe, updates, overrides) in enumerate(SEARCH_RECIPES):
                local = dict(overrides); entropy = float(local.get("RLS_ENTROPY", BASE_ENV["RLS_ENTROPY"]))
                local["RLS_ENTROPY"] = f"{max(0.0035, entropy * (0.985 ** (gen - 1))):.6f}"
                seed = 2026200000 + gen * 10000 + ridx * 100; run_name = f"g{gen:03d}_{recipe}"
                cand = train_candidate(train_bin, champion, runs_dir, run_name, updates, seed, 3, local, repo)
                rows1, s1 = evaluate_candidate(eval_bin, cand, champion, 2026210000 + gen * 1000 + ridx * 20, repo, False)
                rec = {"recipe": recipe, "path": str(cand), "phase1": s1,
                       "phase1_rows": rows1, "updates": updates, "overrides": local}
                gen_records.append(rec)
                if s1["qualifies"]: qualified.append((s1["combined_lcb95"], rec, cand))
            qualified.sort(key=lambda x: x[0], reverse=True)
            gen_record = {"kind": "search", "generation": gen, "parent_sha": parent_sha,
                          "candidates": gen_records, "promoted": False}
            if qualified:
                _, best_rec, best_cand = qualified[0]
                rows2, s2 = evaluate_candidate(eval_bin, best_cand, champion, 2026290000 + gen * 100, repo, True)
                gen_record["confirmation_candidate"] = best_rec["recipe"]; gen_record["confirmation"] = s2; gen_record["confirmation_rows"] = rows2
                if s2["qualifies"]:
                    gen_record["promoted"] = True; new_sha = promote(best_cand, champion, archive_dir, lab_dir, gen_record)
                    gen_record["new_sha"] = new_sha; state["no_improve"] = 0
                    print(f"[PROMOTED] gen={gen} recipe={best_rec['recipe']} sha={new_sha[:16]}")
                else: state["no_improve"] = state.get("no_improve", 0) + 1; print(f"[NO PROMOTION] gen={gen}: fresh confirmation failed")
            else: state["no_improve"] = state.get("no_improve", 0) + 1; print(f"[NO PROMOTION] gen={gen}: no phase1 qualifier")
            state["generation"] = gen; state["history"].append(gen_record); state["champion_sha256"] = sha256(champion)
            if state["no_improve"] >= 2:
                state["plateau"] = True
                state["plateau_reason"] = "Two consecutive full search generations produced no statistically confirmed improvement for the current 72-observation / 16-action policy contract."
                print("\n[PLATEAU] current contract search plateau verified after 2 consecutive misses.")
            save_state(state_path, state)
        print("\n=== SUPERVISOR COMPLETE ==="); print("Champion SHA256:", sha256(champion)); print("Plateau:", bool(state.get("plateau"))); print("State:", state_path)
        return 0
    except KeyboardInterrupt:
        state["interrupted_at"] = time.time(); save_state(state_path, state)
        print("\n[stopped] Ctrl+C received. Checkpoints/state preserved; rerun to resume."); return 130
    except Exception as exc:
        state["last_error"] = repr(exc); state["last_error_at"] = time.time(); save_state(state_path, state)
        print(f"\n[fatal] {exc}", file=sys.stderr); return 1

if __name__ == "__main__":
    raise SystemExit(main())
