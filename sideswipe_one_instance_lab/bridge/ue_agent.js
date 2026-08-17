'use strict';

/*
 * SideSwipe One-Instance Lab - UE4 runtime discovery agent
 * Offline / Exhibition only.
 *
 * Reflection layout follows the public UE4.27 layout used by frida-ue4dump
 * (MIT, gmh5225). This file is an independent, reduced implementation with
 * fail-closed writes and runtime profile overrides; it does not hard-code
 * SideSwipe gameplay object offsets.
 */

const C = {
  FUObjectItemSize: 0x18,
  FUObjectArray_TUObjectArray: 0x10,
  TUObjectArray_NumElements: 0x14,
  FNameStride: 0x2,
  FNamePool_Blocks: 0x10,
  FNameEntry_LenBit: 6,
  FNameEntry_String: 0x2,
  UObject_ClassPrivate: 0x10,
  UObject_FNameIndex: 0x18,
  UObject_OuterPrivate: 0x20,
  UStruct_SuperStruct: 0x40,
  UStruct_ChildProperties: 0x50,
  FField_Class: 0x8,
  FField_Next: 0x20,
  FField_Name: 0x28,
  UProperty_ElementSize: 0x38,
  UProperty_OffsetInternal: 0x4c,
  UBoolProperty_ByteOffset: 0x89,
  UBoolProperty_ByteMask: 0x8a,
  UBoolProperty_FieldMask: 0x8b,
};

let moduleName = 'libUE4.so';
let mod = null;
let GUObjectArray = null;
let GName = null;
let gnameHook = null;
let profile = {};

function hex(p) { return p ? p.toString() : null; }
function safe(fn, fallback = null) { try { return fn(); } catch (_) { return fallback; } }
function ptrFrom(v) {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number') return ptr(v);
  const s = String(v);
  if (s.startsWith('0x')) return ptr(s);
  return ptr(parseInt(s, 10));
}
function modulePtr(offsetOrAbsolute) {
  if (offsetOrAbsolute === null || offsetOrAbsolute === undefined) return null;
  const p = ptrFrom(offsetOrAbsolute);
  if (!p) return null;
  if (p.compare(mod.base) >= 0) return p;
  return mod.base.add(p);
}


function findExport(name) {
  let p = safe(() => mod.findExportByName(name));
  if (!p) p = safe(() => Module.findExportByName(moduleName, name));
  return p;
}

function findSymbolLike(needle) {
  const low = needle.toLowerCase();
  let syms = [];
  try { syms = mod.enumerateSymbols(); } catch (_) {}
  for (const s of syms) if ((s.name || '').toLowerCase().includes(low)) return s.address;
  let exps = [];
  try { exps = mod.enumerateExports(); } catch (_) {}
  for (const e of exps) if ((e.name || '').toLowerCase().includes(low)) return e.address;
  return null;
}

function tryResolveGlobals(opts) {
  opts = opts || {};
  GUObjectArray = modulePtr(opts.guobject_offset || opts.guobject || null);
  GName = modulePtr(opts.gname_offset || opts.gname || null);

  if (!GUObjectArray) {
    GUObjectArray = findExport('GUObjectArray');
    if (!GUObjectArray) GUObjectArray = findSymbolLike('GUObjectArray');
  }
  if (!GName) {
    GName = findExport('GName');
    if (!GName) GName = findSymbolLike('GName');
  }

  // UE4.27 Android often does not export GName. The public UE4 dump method
  // observes FName equality and captures x8 on arm64. Fail silently on other
  // architectures; the host will report that a runtime override is needed.
  if (!GName && Process.arch === 'arm64' && !gnameHook) {
    const eq = findExport('_Zeq12FNameEntryId5EName') || findSymbolLike('_Zeq12FNameEntryId5EName');
    if (eq) {
      gnameHook = Interceptor.attach(eq.add(8), {
        onEnter(args) {
          const x8 = this.context.x8;
          if (x8 && !x8.isNull()) {
            GName = x8;
            try { gnameHook.detach(); } catch (_) {}
            gnameHook = null;
            send({type:'global', name:'GName', address:hex(GName), source:'arm64-fname-hook'});
          }
        }
      });
    }
  }
}

function getFName(index) {
  if (!GName || index <= 0) return 'None';
  return safe(() => {
    const block = index >>> 16;
    const off = index & 0xffff;
    const poolOff = Process.platform === 'linux' ? 0x30 : 0xc0;
    const pool = GName.add(poolOff);
    const chunk = pool.add(C.FNamePool_Blocks + block * Process.pointerSize).readPointer();
    if (chunk.isNull()) return 'None';
    const entry = chunk.add(C.FNameStride * off);
    const header = entry.readU16();
    const len = header >>> C.FNameEntry_LenBit;
    const wide = (header & 1) !== 0;
    if (len <= 0 || len >= 250) return 'None';
    return wide ? entry.add(C.FNameEntry_String).readUtf16String(len) : entry.add(C.FNameEntry_String).readUtf8String(len);
  }, 'None');
}

function uClass(obj) { return safe(() => obj.add(C.UObject_ClassPrivate).readPointer()); }
function uName(obj) { return safe(() => getFName(obj.add(C.UObject_FNameIndex).readU32()), 'None'); }
function uClassName(obj) { const c = uClass(obj); return c && !c.isNull() ? uName(c) : 'None'; }
function validObject(obj) {
  return safe(() => !!obj && !obj.isNull() && !uClass(obj).isNull() && obj.add(C.UObject_FNameIndex).readU32() > 0, false);
}

function objectCount() {
  if (!GUObjectArray) return 0;
  return safe(() => GUObjectArray.add(C.FUObjectArray_TUObjectArray).add(C.TUObjectArray_NumElements).readU32(), 0);
}
function objectAt(i) {
  if (!GUObjectArray || i < 0) return null;
  return safe(() => {
    const tu = GUObjectArray.add(C.FUObjectArray_TUObjectArray).readPointer();
    const chunkPtr = tu.add(Math.floor(i / 0x10000) * Process.pointerSize).readPointer();
    return chunkPtr.add((i % 0x10000) * C.FUObjectItemSize).readPointer();
  });
}

function classProperties(clazz, maxItems) {
  const out = [];
  const seen = new Set();
  let c = clazz;
  while (c && !c.isNull() && out.length < maxItems) {
    let f = safe(() => c.add(C.UStruct_ChildProperties).readPointer());
    let guard = 0;
    while (f && !f.isNull() && guard++ < 1024 && out.length < maxItems) {
      const key = hex(f); if (seen.has(key)) break; seen.add(key);
      const name = safe(() => getFName(f.add(C.FField_Name).readU32()), 'None');
      const fc = safe(() => f.add(C.FField_Class).readPointer());
      const type = fc && !fc.isNull() ? safe(() => getFName(fc.readU32()), 'Unknown') : 'Unknown';
      const offset = safe(() => f.add(C.UProperty_OffsetInternal).readU32(), -1);
      const size = safe(() => f.add(C.UProperty_ElementSize).readU32(), -1);
      const extra = {};
      if ((type || '').toLowerCase().includes('bool')) {
        extra.byte_offset=safe(() => f.add(C.UBoolProperty_ByteOffset).readU8(),0);
        extra.byte_mask=safe(() => f.add(C.UBoolProperty_ByteMask).readU8(),1);
        extra.field_mask=safe(() => f.add(C.UBoolProperty_FieldMask).readU8(),1);
      }
      if (name !== 'None' && offset >= 0) out.push(Object.assign({name, type, offset, size, owner:uName(c)},extra));
      f = safe(() => f.add(C.FField_Next).readPointer());
    }
    c = safe(() => c.add(C.UStruct_SuperStruct).readPointer());
  }
  return out;
}

function searchObjects(terms, limit) {
  terms = (terms || []).map(x => String(x).toLowerCase()).filter(Boolean);
  const n = Math.min(objectCount(), 2000000);
  const out = [];
  for (let i=0; i<n && out.length<limit; i++) {
    const o = objectAt(i); if (!validObject(o)) continue;
    const name = uName(o), cls = uClassName(o);
    const hay = (name + ' ' + cls).toLowerCase();
    if (!terms.length || terms.some(t => hay.includes(t))) {
      out.push({index:i, address:hex(o), name, class_name:cls});
    }
  }
  return out;
}

function findObject(selector) {
  if (!selector) return null;
  if (selector.address) return ptrFrom(selector.address);
  const terms = [];
  if (selector.name_contains) terms.push(String(selector.name_contains).toLowerCase());
  if (selector.class_contains) terms.push(String(selector.class_contains).toLowerCase());
  const n = objectCount();
  let occurrence = selector.occurrence || 0;
  for (let i=0;i<n;i++) {
    const o=objectAt(i); if(!validObject(o)) continue;
    const name=uName(o).toLowerCase(), cls=uClassName(o).toLowerCase();
    if (selector.name_contains && !name.includes(String(selector.name_contains).toLowerCase())) continue;
    if (selector.class_contains && !cls.includes(String(selector.class_contains).toLowerCase())) continue;
    if (occurrence-- > 0) continue;
    return o;
  }
  return null;
}

function readScalar(base, spec, def) {
  if (!spec) return def;
  const a = base.add(parseInt(spec.offset || 0));
  return safe(() => {
    switch (spec.type || 'f32') {
      case 'f64': return a.readDouble();
      case 'i32': return a.readS32();
      case 'u32': return a.readU32();
      case 'i16': return a.readS16();
      case 'u16': return a.readU16();
      case 'i8': return a.readS8();
      case 'u8': return a.readU8();
      case 'bool8': return a.readU8() ? 1 : 0;
      case 'boolbit': { const b=a.add(parseInt(spec.byte_offset||0)).readU8(); return (b & parseInt(spec.byte_mask||1)) ? 1 : 0; }
      case 'ptr': return hex(a.readPointer());
      default: return a.readFloat();
    }
  }, def);
}
function writeScalar(base, spec, val) {
  if (!spec || spec.writable !== true) return false;
  const a = base.add(parseInt(spec.offset || 0));
  return safe(() => {
    switch (spec.type || 'f32') {
      case 'f64': a.writeDouble(+val); break;
      case 'i32': a.writeS32(val|0); break;
      case 'u32': a.writeU32(val>>>0); break;
      case 'i16': a.writeS16(val|0); break;
      case 'u16': a.writeU16(val>>>0); break;
      case 'i8': a.writeS8(val|0); break;
      case 'u8': case 'bool8': a.writeU8(val ? 1 : 0); break;
      case 'boolbit': { const q=a.add(parseInt(spec.byte_offset||0)); const mask=parseInt(spec.byte_mask||1); const old=q.readU8(); q.writeU8(val ? (old|mask) : (old & (~mask & 0xff))); break; }
      default: a.writeFloat(+val); break;
    }
    return true;
  }, false);
}

function objectFields(obj, fields) {
  const out = {};
  for (const [k,s] of Object.entries(fields || {})) out[k] = readScalar(obj, s, s.default === undefined ? 0 : s.default);
  return out;
}

function snapshotWithProfile(p) {
  if (!p || !p.state) throw new Error('runtime profile has no state mapping');
  const ballObj = findObject(p.state.ball && p.state.ball.selector);
  if (!ballObj) throw new Error('ball selector did not resolve');
  const ball = objectFields(ballObj, p.state.ball.fields);
  const cars = [];
  for (const c of (p.state.cars || [])) {
    const o = findObject(c.selector); if (!o) continue;
    const f = objectFields(o, c.fields);
    f.team = c.team|0; f._address = hex(o); cars.push(f);
  }
  if (!cars.length) throw new Error('no car selectors resolved');
  return {ball, cars, ts: Date.now()};
}

function applyWithProfile(p, actions) {
  if (!p || !p.controls || p.controls.enabled !== true) throw new Error('control writes are not enabled in runtime profile');
  let writes=0;
  for (let i=0;i<actions.length;i++) {
    const cp=(p.state.cars || [])[i]; if(!cp) continue;
    const target=((p.controls.targets || [])[i]) || cp;
    const o=findObject(target.selector || cp.selector); if(!o) continue;
    const map=target.fields || p.controls.fields || {};
    const a=actions[i] || {};
    writes += writeScalar(o,map.drive,a.drive) ? 1:0;
    writes += writeScalar(o,map.pitch,a.pitch) ? 1:0;
    writes += writeScalar(o,map.jump,a.jump?1:0) ? 1:0;
    writes += writeScalar(o,map.boost,a.boost?1:0) ? 1:0;
  }
  return writes;
}

rpc.exports = {
  init(optsJson) {
    const opts = optsJson ? JSON.parse(optsJson) : {};
    moduleName = opts.module || 'libUE4.so';
    profile = opts.profile || {};
    mod = Process.getModuleByName(moduleName);
    tryResolveGlobals(opts);
    return {module:moduleName, base:hex(mod.base), size:mod.size, arch:Process.arch,
            guobject:hex(GUObjectArray), gname:hex(GName), object_count:objectCount()};
  },
  status() {
    return {module:moduleName, base:mod?hex(mod.base):null, arch:Process.arch,
            guobject:hex(GUObjectArray), gname:hex(GName), object_count:objectCount()};
  },
  retryglobals(optsJson) { const o=optsJson?JSON.parse(optsJson):{}; tryResolveGlobals(o); return this.status(); },
  search(termsJson, limit) { return searchObjects(JSON.parse(termsJson||'[]'), Math.min(limit||200,1000)); },
  properties(address, limit) {
    const o=ptrFrom(address); if(!validObject(o)) return [];
    return classProperties(uClass(o), Math.min(limit||512,2048));
  },
  snapshot(profileJson) { return snapshotWithProfile(profileJson?JSON.parse(profileJson):profile); },
  apply(profileJson, actionsJson) { return applyWithProfile(profileJson?JSON.parse(profileJson):profile, JSON.parse(actionsJson||'[]')); }
};
