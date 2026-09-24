"""What a GLB's morph targets do: for each mesh, each target's name, how many vertices it moves and how
far, read straight from the file (sparse accessors included). With --render, the meshes drawn in the
rest pose with the named targets on, round a hand, with the fist's haft.

    python3 tools/forge/preview/morphcheck.py <glb> [<glb> ...] [--render=<out.png> --on=grip_R --side=R]"""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "forge"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
import transplant_clips as T
import lbspreview as LP
from forge.lib import rig, grip


def accessor(j, b, i):
    """An accessor's values as floats, sparse substitutions applied."""
    a = j["accessors"][i]
    n = T._NCOMP[a["type"]]
    dt = np.dtype(T._COMP[a["componentType"]])
    if "bufferView" in a:
        v = j["bufferViews"][a["bufferView"]]
        start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        out = np.frombuffer(b, dtype=dt, count=a["count"] * n, offset=start).reshape(a["count"], n).astype(float)
    else:
        out = np.zeros((a["count"], n))
    if "sparse" in a:
        sp = a["sparse"]
        iv = j["bufferViews"][sp["indices"]["bufferView"]]
        idx = np.frombuffer(b, dtype=np.dtype(T._COMP[sp["indices"]["componentType"]]), count=sp["count"],
                            offset=iv.get("byteOffset", 0) + sp["indices"].get("byteOffset", 0))
        vv = j["bufferViews"][sp["values"]["bufferView"]]
        vals = np.frombuffer(b, dtype=dt, count=sp["count"] * n,
                             offset=vv.get("byteOffset", 0) + sp["values"].get("byteOffset", 0)).reshape(-1, n)
        out = out.copy()
        out[idx.astype(int)] = vals
    return out


def morphs(path):
    """[(mesh name, target names, [delta arrays (n,3) in the glTF frame])]."""
    j, b = T.load(path)
    res = []
    for m in j.get("meshes", []):
        names = (m.get("extras") or {}).get("targetNames", [])
        for p in m["primitives"]:
            deltas = [accessor(j, b, t["POSITION"]) for t in p.get("targets", []) if "POSITION" in t]
            res.append((m.get("name", "?"), names, deltas))
    return res


def main():
    paths = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    for pth in paths:
        for name, names, deltas in morphs(pth):
            for k, d in enumerate(deltas):
                moved = np.linalg.norm(d, axis=1)
                print("%s  %-14s %-10s moves %5d vertices, at most %.3f m" % (
                    Path(pth).name, name, names[k] if k < len(names) else k, int((moved > 1e-6).sum()), moved.max()))
    if "render" not in opts:
        return
    on = opts.get("on", "grip_R")
    side = opts.get("side", "R")
    skel = rig.Skeleton(rig.Proportions())
    meshes = []
    colours = [np.array([0.79, 0.64, 0.49]), np.array([0.36, 0.25, 0.16]), np.array([0.55, 0.40, 0.25])]
    for i, pth in enumerate(paths):
        loaded = LP.load(pth)
        md = morphs(pth)
        for (nm, V, J, Wt, I, bones), (_, names, deltas) in zip(loaded, md):
            if on in names:
                d = deltas[names.index(on)]
                # glTF (x, y up, z forward) to the forge frame, as LP.load converts positions
                V = V + np.stack([d[:, 0], -d[:, 2], d[:, 1]], axis=1)
            meshes.append((V, I, colours[min(i, 2)]))
    c, axis = grip.haft(skel, side)
    HV, HI = __import__("gripcheck").cylinder(c, axis, grip.HAFT_R * 0.96, 0.09)
    meshes.append((HV, HI, np.array([0.30, 0.20, 0.12])))
    wr, dd, fwd, up = grip.hand_frame(skel, side)
    centre = wr + dd * 0.09
    panels = []
    for view in (20, 70, 140, 250):
        ms = []
        for V, I, col in meshes:
            keep = (np.linalg.norm(V[I] - centre, axis=2) < 0.14).all(axis=1)
            ms.append((V - np.array([centre[0], centre[1], 0.0]), I[keep], col))
        panels.append(LP.raster(ms, view, size=(360, 360), centre_z=float(centre[2]), scale=2200.0))
    Image.fromarray((np.clip(np.concatenate(panels, axis=1), 0, 1) * 255).astype(np.uint8)).save(opts["render"])
    print("wrote", opts["render"])


if __name__ == "__main__":
    main()
