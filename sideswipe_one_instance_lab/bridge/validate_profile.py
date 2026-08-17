#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math, pathlib, statistics, sys, time
import orchestrator as core

ROOT=pathlib.Path(__file__).resolve().parents[1]

def finite(v):
    try: return math.isfinite(float(v))
    except Exception: return False

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--package',default='com.Psyonix.RL2D'); ap.add_argument('--profile',type=pathlib.Path,default=ROOT/'config/runtime_profile.json'); ap.add_argument('--seconds',type=float,default=12); ap.add_argument('--hz',type=int,default=20)
    a=ap.parse_args(); p=core.load(a.profile)
    if not p: raise SystemExit('profile absent')
    dev,session,script,events=core.connect_frida(a.package); ex=core.rpc(script)
    samples=[]; errors=[]
    try:
        st=ex.init(json.dumps({'module':p.get('module','libUE4.so'),'guobject_offset':p.get('guobject_offset'),'gname_offset':p.get('gname_offset'),'profile':p}))
        deadline=time.monotonic()+a.seconds; period=1/max(1,a.hz)
        while time.monotonic()<deadline:
            t=time.monotonic()
            try: samples.append(ex.snapshot(json.dumps(p)))
            except Exception as e: errors.append(str(e))
            time.sleep(max(0,period-(time.monotonic()-t)))
    finally:
        try: session.detach()
        except Exception: pass
    report={'samples':len(samples),'errors':len(errors),'error_examples':errors[:10],'checks':{},'pass':False}
    if len(samples)<max(20,a.hz*3):
        report['checks']['enough_samples']=False
    else:
        report['checks']['enough_samples']=True
        counts=[len(s.get('cars',[])) for s in samples]
        report['checks']['car_count_stable']=min(counts)>=2 and len(set(counts))<=2
        vals=[]
        for s in samples:
            b=s.get('ball',{}); vals += [b.get(k) for k in ('x','y','vx','vy')]
            for c in s.get('cars',[]): vals += [c.get(k) for k in ('x','y','vx','vy','theta','boost')]
        report['checks']['finite']=all(finite(x) for x in vals)
        # Very permissive sanity bounds: catch wrong offsets/NaN without assuming exact engine scale.
        num=[abs(float(x)) for x in vals if finite(x)]
        report['checks']['not_memory_garbage']=bool(num) and max(num)<1e8
        # State must actually move during a live Exhibition sample.
        bx=[float(s['ball'].get('x',0)) for s in samples if finite(s.get('ball',{}).get('x'))]
        by=[float(s['ball'].get('y',0)) for s in samples if finite(s.get('ball',{}).get('y'))]
        motion=(max(bx)-min(bx) if bx else 0)+(max(by)-min(by) if by else 0)
        report['checks']['live_motion']=motion>1e-3
        report['pass']=all(report['checks'].values()) and len(errors)<=max(2,len(samples)//20)
    out=ROOT/'logs/profile_validation.json'; core.dump(out,report)
    print(json.dumps(report,indent=2)); print('[report]',out)
    if report['pass']:
        print('[PASS] State mapping looks coherent/readable. Control mapping is still NOT automatically trusted.')
        return 0
    print('[FAIL] Profile remains unvalidated; do not enable controls.')
    return 3
if __name__=='__main__': raise SystemExit(main())
