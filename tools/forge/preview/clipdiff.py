"""Per-clip numeric difference between two rig GLBs' animations (by clip name, channel target name and path).

    python3 tools/forge/preview/clipdiff.py <a.glb> <b.glb>"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import numpy as np
import transplant_clips as T

a_path, b_path = sys.argv[1:3]
ja, ba = T.load(a_path)
jb, bb = T.load(b_path)


def acc(j, b, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = T._NCOMP[a["type"]]
    dt = T._COMP[a["componentType"]]
    raw = b[bv.get("byteOffset", 0) + a.get("byteOffset", 0):]
    return np.frombuffer(raw, dtype=dt, count=a["count"] * n).reshape(a["count"], n).astype(float)


def clips(j, b):
    out = {}
    for an in j.get("animations", []):
        ch = {}
        for c in an["channels"]:
            s = an["samplers"][c["sampler"]]
            node = j["nodes"][c["target"]["node"]]["name"]
            ch[(node, c["target"]["path"])] = (acc(j, b, s["input"]), acc(j, b, s["output"]))
        out[an["name"]] = ch
    return out


ca, cb = clips(ja, ba), clips(jb, bb)
same, diff = [], []
for name in sorted(set(ca) | set(cb)):
    if name not in ca or name not in cb:
        diff.append((name, "missing in " + ("A" if name not in ca else "B")))
        continue
    worst = 0.0
    note = ""
    for key in set(ca[name]) | set(cb[name]):
        if key not in ca[name] or key not in cb[name]:
            note = "channel %s missing" % (key,)
            worst = 1e9
            continue
        (ta, va), (tb, vb) = ca[name][key], cb[name][key]
        if ta.shape != tb.shape or va.shape != vb.shape:
            note = "shape %s %s vs %s" % (key, va.shape, vb.shape)
            worst = 1e9
            continue
        worst = max(worst, float(np.abs(ta - tb).max()), float(np.abs(va - vb).max()))
    (same if worst < 1e-5 else diff).append((name, "%.3g %s" % (worst, note)))
print("identical (<1e-5):", len(same))
print("differing:", diff)
