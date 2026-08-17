#!/usr/bin/env python3
"""One-instance SideSwipe offline bridge.

Two modes:
  discover  - read-only UE4 inventory/property discovery and profile suggestions.
  run       - state -> exact 72D policy host -> controls, only when a validated
              runtime profile explicitly enables writes.

This intentionally fails closed. Public matchmaking is not supported.
"""
from __future__ import annotations
import argparse, json, os, pathlib, queue, re, subprocess, sys, threading, time
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config"
LOGS = ROOT / "logs"
AGENT = pathlib.Path(__file__).with_name("ue_agent.js")
DEFAULT_PROFILE = CONFIG / "runtime_profile.json"
DISCOVERY = LOGS / "discovery.json"

KEYWORDS = ["ball", "car", "vehicle", "pawn", "controller", "bot", "boost", "jump", "dodge", "flip", "throttle", "steer"]
STATE_HINTS = {
    "x": ["locationx", "posx", "positionx", "x"], "y": ["locationz", "locationy", "posy", "positiony", "y"],
    "vx": ["velocityx", "linearvelocityx", "velx"], "vy": ["velocityz", "velocityy", "vely"],
    "theta": ["rotation", "yaw", "angle"], "omega": ["angularvelocity", "angvel", "rotationrate"],
    "boost": ["boostamount", "boost", "boostmeter"], "on_ground": ["onground", "grounded", "floor"],
    "has_flip": ["hasflip", "hasdodge", "candodge"], "jumping": ["jumping", "isjumping"],
    "flip_timer": ["dodgetimer", "fliptimer"], "air_time": ["airtime", "timesinceground"],
    "spin": ["angularvelocity", "spin"]
}
CONTROL_HINTS = {
    "drive": ["throttle", "drive", "steer", "horizontalinput"],
    "pitch": ["pitchinput", "verticalinput", "pitch"],
    "jump": ["jumpinput", "jump", "pressedjump"],
    "boost": ["boostinput", "boostpressed", "boosting"]
}

def dump(path: pathlib.Path, obj: Any):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")

def load(path: pathlib.Path, default=None):
    try: return json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError: return default

def connect_frida(package: str, timeout: float = 15):
    try: import frida
    except Exception as e: raise SystemExit(f"frida Python absent: {e}. Relance INSTALL.bat")
    transport=os.environ.get("SS_FRIDA_TRANSPORT","server").lower()
    if transport == "gadget":
        # adb forward tcp:27042 tcp:27042 is prepared by the launcher.
        dev = frida.get_device_manager().add_remote_device("127.0.0.1:27042")
        procs=dev.enumerate_processes()
        if not procs: raise RuntimeError("Frida Gadget ne répond pas sur 127.0.0.1:27042")
        pid=procs[0].pid
    else:
        dev = frida.get_usb_device(timeout=int(timeout))
        try: pid = dev.get_process(package).pid
        except Exception:
            apps = dev.enumerate_applications()
            app = next((a for a in apps if a.identifier == package), None)
            if not app: raise RuntimeError(f"Package {package} absent de l'émulateur")
            pid = dev.spawn([package]); dev.resume(pid); time.sleep(3)
    session = dev.attach(pid)
    src = AGENT.read_text(encoding="utf-8")
    script = session.create_script(src)
    events=[]
    def on_message(m, data):
        if m.get("type") == "send": events.append(m.get("payload")); print("[agent]", m.get("payload"), file=sys.stderr)
        elif m.get("type") == "error": print("[agent-error]", m.get("stack") or m, file=sys.stderr)
    script.on("message", on_message); script.load()
    return dev, session, script, events

def rpc(script):
    # Newer Frida exposes exports_sync; keep fallback for older bindings.
    return getattr(script, "exports_sync", script.exports)

def normalize(s: str) -> str: return re.sub(r"[^a-z0-9]", "", s.lower())

def score_props(props):
    out={"state":{}, "controls":{}}
    for bucket,hints in ((out["state"],STATE_HINTS),(out["controls"],CONTROL_HINTS)):
        for target, names in hints.items():
            best=None; bs=0
            for p in props:
                n=normalize(p.get("name",""));
                for h in names:
                    hn=normalize(h)
                    sc = 100 if n == hn else (70 if hn in n else 0)
                    if sc > bs: best,bs=p,sc
            if best: bucket[target]={"score":bs, **best}
    return out

def discover(args):
    profile=load(args.profile,{}) or {}
    init={"module":profile.get("module","libUE4.so"),
          "guobject_offset":profile.get("guobject_offset"), "gname_offset":profile.get("gname_offset"), "profile":profile}
    dev,session,script,events=connect_frida(args.package)
    ex=rpc(script)
    try:
        try:
            st=ex.init(json.dumps(init))
        except Exception as e:
            msg=str(e)
            result={"timestamp":time.time(),"status":{},"objects":[],"candidates":[],"events":events,
                    "blocked":"UE4 module/runtime not visible through current Frida transport: "+msg,
                    "recommended_next":"If this is the x86_64 AVD running translated ARM64 Sideswipe, run PREPARE_INTERNAL_GADGET.bat for the reversible offline ARM64 Gadget backend."}
            dump(DISCOVERY,result)
            print('[blocked]',result['blocked'])
            print('[next]',result['recommended_next'])
            return 7
        print("[ue]",json.dumps(st,indent=2))
        if not st.get("gname") or not st.get("guobject") or not st.get("object_count"):
            print("[discover] Les globals UE4 ne sont pas encore tous résolus; attente du hook FName...", file=sys.stderr)
            deadline=time.time()+args.wait_globals
            while time.time()<deadline:
                time.sleep(.5); st=ex.status()
                if st.get("gname") and st.get("guobject") and st.get("object_count"): break
        result={"timestamp":time.time(),"status":st,"objects":[],"candidates":[],"events":events}
        if not st.get("gname") or not st.get("guobject") or not st.get("object_count"):
            result["blocked"]="UE4 globals unresolved. Supply guobject_offset/gname_offset for this build in runtime_profile.json."
            dump(DISCOVERY,result); print(f"[blocked] {result['blocked']}\nLog: {DISCOVERY}")
            return 3
        objs=ex.search(json.dumps(KEYWORDS),args.limit)
        result["objects"]=objs
        for o in objs:
            try: props=ex.properties(o["address"],512)
            except Exception: props=[]
            scored=score_props(props)
            if scored["state"] or scored["controls"]:
                result["candidates"].append({"object":o,"properties":props,"matches":scored})
        dump(DISCOVERY,result)
        print(f"[ok] discovery: {DISCOVERY} ({len(objs)} objets / {len(result['candidates'])} candidats)")
        # Build a best-effort, READ-ONLY suggestion. It never enables writes.
        def field_spec(m, default=0):
            if not m: return None
            typ=(m.get("type") or "").lower()
            t="boolbit" if "bool" in typ else ("i32" if "int" in typ else "f32")
            out={"offset":m.get("offset",0),"type":t,"default":default,"source_name":m.get("name"),"confidence":m.get("score",0)}
            if t=="boolbit": out.update(byte_offset=m.get("byte_offset",0),byte_mask=m.get("byte_mask",1),field_mask=m.get("field_mask",1))
            return out
        ballcand=next((c for c in result["candidates"] if "ball" in ((c["object"].get("name","")+" "+c["object"].get("class_name","")).lower())),None)
        carcands=[c for c in result["candidates"] if any(k in ((c["object"].get("name","")+" "+c["object"].get("class_name","")).lower()) for k in ("car","vehicle","pawn"))][:4]
        controllercands=[c for c in result["candidates"] if "controller" in ((c["object"].get("name","")+" "+c["object"].get("class_name","")).lower()) and c["matches"]["controls"]][:4]
        ballmap={}
        if ballcand:
            for key in ("x","y","vx","vy","spin"):
                fs=field_spec(ballcand["matches"]["state"].get(key),0)
                if fs: ballmap[key]=fs
        cars=[]
        for idx,c in enumerate(carcands):
            fmap={}
            defaults={"boost":50,"has_flip":1,"on_ground":0,"jumping":0,"flip_timer":0,"air_time":0,"theta":0,"omega":0,"x":0,"y":0,"vx":0,"vy":0}
            for key,default in defaults.items():
                fs=field_spec(c["matches"]["state"].get(key),default)
                if fs: fmap[key]=fs
            cars.append({"team":idx%2,"selector":{"name_contains":c["object"].get("name"),"class_contains":c["object"].get("class_name"),"occurrence":0},"fields":fmap})
        targets=[]
        for c in controllercands:
            fmap={}
            for key in ("drive","pitch","jump","boost"):
                fs=field_spec(c["matches"]["controls"].get(key),0)
                if fs: fs["writable"]=False; fmap[key]=fs
            targets.append({"selector":{"name_contains":c["object"].get("name"),"class_contains":c["object"].get("class_name"),"occurrence":0},"fields":fmap})
        suggest={"module":init["module"],"guobject_offset":profile.get("guobject_offset"),"gname_offset":profile.get("gname_offset"),
                 "validated":False,"offline_only":True,
                 "state":{"ball":{"selector":({"name_contains":ballcand["object"].get("name"),"class_contains":ballcand["object"].get("class_name"),"occurrence":0} if ballcand else {}),"fields":ballmap},"cars":cars},
                 "controls":{"enabled":False,"fields":{},"targets":targets},
                 "notes":"Auto-discovery READ-ONLY suggestion. Stable name/class selectors are preferred; validate every field and telemetry in Exhibition before enabling writes."}
        sug=CONFIG/"runtime_profile.suggested.json"; dump(sug,suggest); print(f"[ok] profile suggestion (writes OFF): {sug}")
        return 0
    finally:
        try: session.detach()
        except Exception: pass

def checkpoint(path: str|None):
    if path:
        p=pathlib.Path(path); return p
    for p in (ROOT/"checkpoints"/"champion.pt", pathlib.Path(r"D:\RocketLearnNative\checkpoints\sideswipe_from_scratch\latest.pt")):
        if p.exists(): return p
    raise SystemExit("Aucun checkpoint. Lance GET_CHAMPION.bat (ou passe --blue/--orange).")

def policy_line(snap):
    b=snap["ball"]; cars=snap["cars"]
    vals=["S",str(len(cars)),str(b.get("x",0)),str(b.get("y",0)),str(b.get("vx",0)),str(b.get("vy",0)),str(b.get("spin",0))]
    for c in cars:
        vals += [str(int(c.get("team",0))),str(c.get("x",0)),str(c.get("y",0)),str(c.get("vx",0)),str(c.get("vy",0)),
                 str(c.get("theta",0)),str(c.get("omega",0)),str(c.get("boost",50)),str(int(bool(c.get("on_ground",0)))),
                 str(int(bool(c.get("has_flip",1)))),str(int(bool(c.get("jumping",0)))),str(c.get("flip_timer",0)),str(c.get("air_time",0))]
    return " ".join(vals)

def parse_controls(line):
    t=line.split();
    if len(t)<2 or t[0]!="C": raise ValueError(f"policy host: {line}")
    n=int(t[1]); out=[]; k=2
    for _ in range(n):
        out.append({"action":int(t[k]),"drive":float(t[k+1]),"pitch":float(t[k+2]),"jump":t[k+3]=="1","boost":t[k+4]=="1"}); k+=5
    return out

def run_bridge(args):
    p=load(args.profile)
    if not p: raise SystemExit(f"Profil absent: {args.profile}. Lance DISCOVER_INTERNAL.bat")
    if not p.get("validated") or not p.get("offline_only"):
        raise SystemExit("Profil non validé/offline. Le bridge refuse les writes. Valide runtime_profile.json en Exhibition.")
    if not (p.get("controls") or {}).get("enabled"):
        raise SystemExit("controls.enabled=false. Le bridge reste volontairement read-only.")
    blue=checkpoint(args.blue); orange=checkpoint(args.orange) if args.orange else blue
    host=ROOT/"bin"/"sideswipe_policy_host.exe"
    if not host.exists(): raise SystemExit("policy host absent. Relance INSTALL.bat")
    dev,session,script,events=connect_frida(args.package); ex=rpc(script)
    proc=None
    try:
        st=ex.init(json.dumps({"module":p.get("module","libUE4.so"),"guobject_offset":p.get("guobject_offset"),"gname_offset":p.get("gname_offset"),"profile":p}))
        if not st.get("object_count"): raise RuntimeError("UE4 object array unresolved")
        proc=subprocess.Popen([str(host),"--blue",str(blue),"--orange",str(orange)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=sys.stderr,text=True,bufsize=1)
        period=1.0/max(1,args.hz); missed=0; frames=0; start=time.monotonic()
        print(f"[run] OFFLINE dual-policy @ {args.hz} Hz | blue={blue.name} orange={orange.name}")
        while True:
            tic=time.monotonic()
            try:
                snap=ex.snapshot(json.dumps(p)); missed=0
                proc.stdin.write(policy_line(snap)+"\n"); proc.stdin.flush(); line=proc.stdout.readline().strip()
                actions=parse_controls(line)
                writes=ex.apply(json.dumps(p),json.dumps(actions))
                if writes<=0: raise RuntimeError("0 control writes")
                frames+=1
                if frames%max(1,args.hz*5)==0: print(f"[run] frames={frames} hz={frames/max(.001,time.monotonic()-start):.1f} writes={writes}")
            except KeyboardInterrupt: break
            except Exception as e:
                missed+=1
                if missed>=args.max_misses: raise RuntimeError(f"watchdog after {missed} misses: {e}")
            time.sleep(max(0,period-(time.monotonic()-tic)))
    finally:
        if proc:
            try: proc.terminate()
            except Exception: pass
        try: session.detach()
        except Exception: pass
    return 0

def main():
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest="cmd",required=True)
    d=sub.add_parser("discover"); d.add_argument("--package",default="com.Psyonix.RL2D"); d.add_argument("--profile",type=pathlib.Path,default=DEFAULT_PROFILE); d.add_argument("--limit",type=int,default=400); d.add_argument("--wait-globals",type=float,default=12)
    r=sub.add_parser("run"); r.add_argument("--package",default="com.Psyonix.RL2D"); r.add_argument("--profile",type=pathlib.Path,default=DEFAULT_PROFILE); r.add_argument("--blue"); r.add_argument("--orange"); r.add_argument("--hz",type=int,default=30); r.add_argument("--max-misses",type=int,default=10)
    a=ap.parse_args(); LOGS.mkdir(parents=True,exist_ok=True); CONFIG.mkdir(parents=True,exist_ok=True)
    return discover(a) if a.cmd=="discover" else run_bridge(a)
if __name__=="__main__": raise SystemExit(main())
