#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, shutil, tempfile, zipfile
import lief

def clone_info(z: zipfile.ZipInfo, name=None, stored=None):
    n=zipfile.ZipInfo(name or z.filename, z.date_time)
    n.comment=z.comment; n.extra=z.extra; n.internal_attr=z.internal_attr; n.external_attr=z.external_attr
    n.create_system=z.create_system; n.flag_bits=z.flag_bits & ~0x1
    n.compress_type = zipfile.ZIP_STORED if stored else z.compress_type
    return n

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',type=pathlib.Path,required=True); ap.add_argument('--output',type=pathlib.Path,required=True); ap.add_argument('--gadget',type=pathlib.Path,required=True); ap.add_argument('--config',type=pathlib.Path,required=True)
    a=ap.parse_args(); a.output.mkdir(parents=True,exist_ok=True)
    apks=sorted(a.input.glob('*.apk'))
    target=None; ue_name=None
    for apk in apks:
        with zipfile.ZipFile(apk) as z:
            for n in z.namelist():
                if n.endswith('/libUE4.so') and 'arm64-v8a' in n:
                    target=apk; ue_name=n; break
        if target: break
    if not target: raise SystemExit('lib/arm64-v8a/libUE4.so introuvable dans les APK installés')
    print('[gadget] UE4 split:',target.name,ue_name)
    with tempfile.TemporaryDirectory(prefix='ssbot-patch-') as td:
        td=pathlib.Path(td); ue=td/'libUE4.so'; patched=td/'libUE4.patched.so'
        with zipfile.ZipFile(target) as z: ue.write_bytes(z.read(ue_name))
        binary=lief.parse(str(ue))
        if binary is None: raise SystemExit('LIEF ne peut pas parser libUE4.so')
        libs=[str(x) for x in binary.libraries]
        if 'libssbridge.so' not in libs: binary.add_library('libssbridge.so')
        binary.write(str(patched))
        if patched.stat().st_size < 10_000_000: raise SystemExit('libUE4 patchée anormalement petite')
        for apk in apks:
            out=a.output/apk.name
            with zipfile.ZipFile(apk,'r') as zin, zipfile.ZipFile(out,'w',allowZip64=True) as zout:
                for info in zin.infolist():
                    name=info.filename
                    up=name.upper()
                    if up.startswith('META-INF/') and (up.endswith('.RSA') or up.endswith('.DSA') or up.endswith('.EC') or up.endswith('.SF') or up.endswith('MANIFEST.MF')):
                        continue
                    data=patched.read_bytes() if (apk==target and name==ue_name) else zin.read(name)
                    stored=name.endswith('.so')
                    zout.writestr(clone_info(info,stored=stored),data)
                if apk==target:
                    base=str(pathlib.PurePosixPath(ue_name).parent)
                    for name,data in ((base+'/libssbridge.so',a.gadget.read_bytes()),(base+'/libssbridge.config.so',a.config.read_bytes())):
                        zi=zipfile.ZipInfo(name); zi.compress_type=zipfile.ZIP_STORED; zi.external_attr=0o100644<<16
                        zout.writestr(zi,data)
    print('[ok] unsigned patched set:',a.output)
if __name__=='__main__': main()
