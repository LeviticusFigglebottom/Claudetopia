"""Pose skinned GLBs with the forge's own FK and linear blend skinning, and rasterise them flat-shaded:
a quick look at how a body and its clothes deform in a clip, without Blender or Godot.

    python3 lbspreview.py <out.png> <clip>@<t> <glb>[:<mesh substring>][=<hex colour>] ...

A weight hook can be given with --hook=<module>:<function>; it receives (bone_names, V (n,3) forge frame,
W (n,bones)) per mesh and returns new W, for trying weight rules before building them."""
import importlib
import math
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import glb, rig, anim_clips

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def acc(g, b, i):
    a = g["accessors"][i]
    bv = g["bufferViews"][a["bufferView"]]
    n = _N[a["type"]]
    dt = _COMP[a["componentType"]]
    stride = bv.get("byteStride")
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    if stride and stride != n * np.dtype(dt).itemsize:
        raw = np.frombuffer(b, dtype=np.uint8, count=stride * a["count"], offset=off).reshape(a["count"], stride)
        arr = raw[:, :n * np.dtype(dt).itemsize].copy().view(dt).reshape(a["count"], n)
    else:
        arr = np.frombuffer(b, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)
    arr = arr.astype(float)
    if a.get("normalized"):
        arr = arr / float(np.iinfo(dt).max)
    return arr


def load(path, want=None):
    g, b = glb.read_glb(path)
    skin = g["skins"][0]
    names = [g["nodes"][j]["name"] for j in skin["joints"]]
    out = []
    for m in g["meshes"]:
        if want and want.lower() not in m["name"].lower():
            continue
        for p in m["primitives"]:
            at = p["attributes"]
            if "JOINTS_0" not in at:
                continue
            P = acc(g, b, at["POSITION"])
            V = np.stack([P[:, 0], -P[:, 2], P[:, 1]], axis=1)       # glTF Y-up -> forge Z-up
            J = acc(g, b, at["JOINTS_0"]).astype(int)
            Wt = acc(g, b, at["WEIGHTS_0"])
            I = acc(g, b, p["indices"]).astype(int).reshape(-1, 3)
            out.append((m["name"], V, J, Wt, I, names))
    return out


def pose_matrices(skel, clip, t):
    clips = {}
    clips.update(anim_clips.locomotion_clips(skel))
    if clip not in clips:
        for fn in (anim_clips.melee_clips, anim_clips.defence_clips, anim_clips.ranged_clips):
            try:
                clips.update(fn(skel))
            except Exception:
                pass
    if clip == "rest":
        return {b: np.eye(4) for b in skel.bones}
    W = skel.fk(clips[clip].local_pose(t))
    return {b: W[b] @ np.linalg.inv(skel.bones[b].rest) for b in skel.bones if b in W}


def skin(V, J, Wt, names, S):
    out = np.zeros_like(V)
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    for k in range(J.shape[1]):
        for ji in np.unique(J[:, k]):
            sel = J[:, k] == ji
            M = S.get(names[ji], np.eye(4))
            out[sel] += Wt[sel, k:k + 1] * (Vh[sel] @ M.T)[:, :3]
    return out


def raster(meshes, view_deg, size=(420, 620), centre_z=1.0, scale=300.0):
    Hh, Ww = size[1], size[0]
    img = np.zeros((Hh, Ww, 3)) + np.array([0.62, 0.66, 0.70])
    zb = np.full((Hh, Ww), -1e9)
    a = math.radians(view_deg)
    R = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
    light = np.array([0.35, -0.8, 0.5]); light /= np.linalg.norm(light)
    for V, I, col in meshes:
        Q = V @ R.T
        sx = Q[:, 0] * scale + Ww / 2
        sy = (centre_z - Q[:, 2]) * scale + Hh / 2
        depth = -Q[:, 1]                     # towards the camera at -y
        A, B, C = Q[I[:, 0]], Q[I[:, 1]], Q[I[:, 2]]
        nrm = np.cross(B - A, C - A)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        shade = np.abs(nrm @ light) * 0.75 + 0.25
        for t in range(len(I)):
            i0, i1, i2 = I[t]
            xs = np.array([sx[i0], sx[i1], sx[i2]]); ys = np.array([sy[i0], sy[i1], sy[i2]])
            x0, x1 = int(max(0, np.floor(xs.min()))), int(min(Ww - 1, np.ceil(xs.max())))
            y0, y1 = int(max(0, np.floor(ys.min()))), int(min(Hh - 1, np.ceil(ys.max())))
            if x1 < x0 or y1 < y0:
                continue
            px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-12:
                continue
            l0 = ((ys[1] - ys[2]) * (px - xs[2]) + (xs[2] - xs[1]) * (py - ys[2])) / d
            l1 = ((ys[2] - ys[0]) * (px - xs[2]) + (xs[0] - xs[2]) * (py - ys[2])) / d
            l2 = 1 - l0 - l1
            ins = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
            if not ins.any():
                continue
            z = l0 * depth[i0] + l1 * depth[i1] + l2 * depth[i2]
            yy, xx = np.nonzero(ins)
            yy += y0; xx += x0
            zz = z[ins]
            closer = zz > zb[yy, xx]
            zb[yy[closer], xx[closer]] = zz[closer]
            cc = np.asarray(col)
            if cc.ndim == 2:
                cc = cc[t]
            img[yy[closer], xx[closer]] = cc * shade[t]
    return img


def main():
    out = sys.argv[1]
    clip, t = sys.argv[2].split("@")
    hook = None
    views = [0, 35, 90]
    items = []
    wmode = None
    for a in sys.argv[3:]:
        if a.startswith("--weights="):
            wmode = a[10:].split(",")
        elif a.startswith("--hook="):
            mod, fn = a[7:].split(":")
            hook = getattr(importlib.import_module(mod), fn)
        elif a.startswith("--views="):
            views = [float(v) for v in a[8:].split(",")]
        else:
            items.append(a)
    skel = rig.Skeleton(rig.Proportions())
    S = pose_matrices(skel, clip, float(t))
    meshes = []
    for it in items:
        col = "c9a27e"
        if "=" in it:
            it, col = it.split("=")
        want = None
        if ":" in it:
            it, want = it.split(":")
        c = np.array([int(col[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
        for name, V, J, Wt, I, names in load(it, want):
            if hook is not None:
                Wt = hook(name, names, V, J, Wt)
            if wmode:
                # red, green, blue = the summed weights of the first, second, third bone named
                full = np.zeros((len(V), len(names)))
                for k in range(J.shape[1]):
                    np.add.at(full, (np.arange(len(V)), J[:, k]), Wt[:, k])
                chans = []
                for bn in wmode[:3]:
                    idx = [i for i, n in enumerate(names) if n in bn.split("+")]
                    chans.append(full[:, idx].sum(axis=1) if idx else np.zeros(len(V)))
                while len(chans) < 3:
                    chans.append(np.zeros(len(V)))
                vc = np.stack(chans, axis=1) * 0.85 + 0.12
                c = vc[I].mean(axis=1)
            meshes.append((skin(V, J, Wt, names, S), I, c))
    panels = [raster(meshes, v) for v in views]
    img = np.concatenate(panels, axis=1)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
