#!/usr/bin/env python3
import json, math, re, shutil, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'challengers')
eval_bin = Path(sys.argv[2] if len(sys.argv) > 2 else './build/sideswipe_eval')
base = Path(sys.argv[3] if len(sys.argv) > 3 else 'base/latest.pt')
outdir = Path(sys.argv[4] if len(sys.argv) > 4 else 'final_champion')

if not base.exists():
    raise SystemExit(f'base checkpoint missing: {base}')

candidates = sorted(p for p in root.iterdir() if p.is_dir() and (p / 'latest.pt').exists())
if not candidates:
    raise SystemExit(f'no challenger checkpoints found in {root}')

FIELD_RE = re.compile(r'\b(W|L|D)=([0-9]+)')
SCORE_RE = re.compile(r'\bscore=([0-9.]+)')
Z = 1.645
MODE_WEIGHT = {1: 0.60, 2: 0.40}


def evaluate(candidate: Path, mode: int, episodes: int, seed: int):
    cmd = [str(eval_bin), '--candidate', str(candidate), '--opponent', str(base),
           '--episodes', str(episodes), '--team-size', str(mode), '--seed', str(seed)]
    text = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
    print(text, end='')
    score_match = SCORE_RE.search(text)
    fields = {k: int(v) for k, v in FIELD_RE.findall(text)}
    if not score_match or set(fields) != {'W', 'L', 'D'}:
        raise RuntimeError('could not parse evaluator output: ' + text)
    n = fields['W'] + fields['L'] + fields['D']
    if n != episodes:
        raise RuntimeError(f'evaluator episode count mismatch: expected {episodes}, got {n}')
    score = float(score_match.group(1))
    exact_score = (fields['W'] + 0.5 * fields['D']) / n
    if abs(score - exact_score) > 5e-4:
        raise RuntimeError(f'evaluator score mismatch: printed={score} exact={exact_score}')
    return {
        'mode': mode, 'episodes': n, 'seed': seed,
        'wins': fields['W'], 'losses': fields['L'], 'draws': fields['D'],
        'score': exact_score, 'output': text.strip(),
    }


def aggregate(rows):
    scores = {r['mode']: r['score'] for r in rows}
    ns = {r['mode']: r['episodes'] for r in rows}
    combined = sum(MODE_WEIGHT[m] * scores[m] for m in MODE_WEIGHT)
    variance_bound = sum((MODE_WEIGHT[m] ** 2) * 0.25 / ns[m] for m in MODE_WEIGHT)
    lcb = combined - Z * math.sqrt(variance_bound)
    qualifies = lcb > 0.5 and scores[1] >= 0.505 and scores[2] >= 0.490
    return {
        'score_1v1': scores[1], 'score_2v2': scores[2],
        'combined_score': combined, 'combined_lcb95': lcb,
        'qualifies': qualifies,
    }

records = []
for idx, c in enumerate(candidates):
    phase1 = [
        evaluate(c / 'latest.pt', 1, 1000, 2026082000 + idx * 20 + 1),
        evaluate(c / 'latest.pt', 2, 600, 2026082000 + idx * 20 + 2),
    ]
    agg1 = aggregate(phase1)
    rec = {'challenger': c.name, 'phase1': phase1, 'phase1_summary': agg1}
    records.append(rec)

qualified = [r for r in records if r['phase1_summary']['qualifies']]
qualified.sort(key=lambda r: r['phase1_summary']['combined_lcb95'], reverse=True)
selected = 'base'
selected_path = base
confirmation = None

if qualified:
    best = qualified[0]
    c = root / best['challenger'] / 'latest.pt'
    phase2 = [
        evaluate(c, 1, 1500, 2026089001),
        evaluate(c, 2, 900, 2026089002),
    ]
    agg2 = aggregate(phase2)
    confirmation = {'challenger': best['challenger'], 'rows': phase2, 'summary': agg2}
    if agg2['qualifies']:
        selected = best['challenger']
        selected_path = c

outdir.mkdir(parents=True, exist_ok=True)
shutil.copy2(selected_path, outdir / 'latest.pt')
manifest = {
    'selection_rule': {
        'mode_weights': MODE_WEIGHT,
        'one_sided_z': Z,
        'variance_bound_per_game': 0.25,
        'requirements': 'combined LCB95 > 0.5, 1v1 >= 0.505, 2v2 >= 0.490; then repeat on fresh larger evaluation',
    },
    'selected': selected,
    'challengers': records,
    'confirmation': confirmation,
}
(outdir / 'generation_manifest.json').write_text(json.dumps(manifest, indent=2))
print(f'PROMOTED={selected}')
if confirmation:
    print('CONFIRM_LCB95=', confirmation['summary']['combined_lcb95'])
