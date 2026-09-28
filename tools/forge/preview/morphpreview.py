"""A built head drawn with its face sliders set, in numpy: the GLB's own mesh, texture and morph
targets, rasterised front and in profile. For judging the sliders without the engine.

    python3 morphpreview.py <out.png> --sliders [head]         # every slider at -1 and +1
    python3 morphpreview.py <out.png> --faces head:k=v,k=v;head:k=v ...   # a row of faces
"""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "forge"))
import numpy as np
from PIL import Image, ImageDraw
from forge.lib import glb, face_morphs as FM

HEADS = ROOT / "game" / "assets" / "models" / "characters" / "heads"


def load(head):
    path = HEADS / head / (head + ".glb")
    j, b = glb.read_glb(path)
    out = []
    for mi, m in enumerate(j["meshes"]):
        p = m["primitives"][0]
        V = glb.read_array(j, b, p["attributes"]["POSITION"])
        T = glb.read_array(j, b, p["indices"]).astype(int).reshape(-1, 3)
        UV = glb.read_array(j, b, p["attributes"]["TEXCOORD_0"])
        names = glb.morph_target_names(j, mi)
        targets = {n: glb.read_array(j, b, t["POSITION"]) for n, t in zip(names, p.get("targets", []))}
        tex = None
        if "material" in p:
            mat = j["materials"][p["material"]]
            ref = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if ref is not None:
                uri = j["images"][j["textures"][ref["index"]]["source"]].get("uri")
                if uri:
                    tex = np.asarray(Image.open(path.parent / uri).convert("RGB"), float) / 255.0
        out.append((m["name"], V, T, UV, targets, tex))
    return out


def raster(meshes, weights, view="front", n=220):
    img = np.full((n, n, 3), 0.33)
    zb = np.full((n, n), np.inf)
    # glTF frame: Y up, +Z forward (the face looks down +Z)
    allV = np.concatenate([m[1] for m in meshes if m[0].startswith("Head")])
    c = np.array([0.0, allV[:, 1].max() - 0.165, allV[:, 2].mean()])
    half = 0.135
    key = np.array([0.45, 0.50, 0.75]); key /= np.linalg.norm(key)
    for name, V, T, UV, targets, tex in meshes:
        P = V.copy()
        for k, w in weights.items():
            t = targets.get(FM.target_name(k))
            if t is not None:
                P = P + t * w
        fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
        N = np.zeros_like(P)
        for k in range(3):
            np.add.at(N, T[:, k], fn)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
        if view == "front":
            sx, sy, depth = P[:, 0], P[:, 1], -P[:, 2]
            facing = N[:, 2]
        else:   # from the head's left, looking along -X
            sx, sy, depth = -P[:, 2], P[:, 1], -P[:, 0]
            facing = N[:, 0]
        X = (sx - (c[0] if view == "front" else -c[2]) + half) / (2 * half) * n
        Y = (c[1] + half - sy) / (2 * half) * n
        shade = np.clip(N @ key, 0, 1) * 0.75 + 0.30
        for tri in T:
            if facing[tri].mean() < -0.05:
                continue
            xs, ys = X[tri], Y[tri]
            x0, x1 = int(max(np.floor(xs.min()), 0)), int(min(np.ceil(xs.max()), n - 1))
            y0, y1 = int(max(np.floor(ys.min()), 0)), int(min(np.ceil(ys.max()), n - 1))
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9:
                continue
            a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
            b_ = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
            cc = 1 - a - b_
            inside = (a >= 0) & (b_ >= 0) & (cc >= 0)
            if not inside.any():
                continue
            z = a * depth[tri[0]] + b_ * depth[tri[1]] + cc * depth[tri[2]]
            iy, ix = np.nonzero(inside)
            zz = z[inside]
            py, px = iy + y0, ix + x0
            closer = zz < zb[py, px]
            if not closer.any():
                continue
            py, px = py[closer], px[closer]
            aa, bb, cw = a[inside][closer], b_[inside][closer], cc[inside][closer]
            zb[py, px] = zz[closer]
            if tex is not None:
                uv = aa[:, None] * UV[tri[0]] + bb[:, None] * UV[tri[1]] + cw[:, None] * UV[tri[2]]
                h, w = tex.shape[:2]
                col = tex[np.clip((uv[:, 1] % 1) * h, 0, h - 1).astype(int), np.clip((uv[:, 0] % 1) * w, 0, w - 1).astype(int)]
            else:
                col = np.full((len(py), 3), 0.8)
            sh = aa * shade[tri[0]] + bb * shade[tri[1]] + cw * shade[tri[2]]
            img[py, px] = np.clip(col * sh[:, None] * 1.1, 0, 1)
    return (img * 255).astype(np.uint8)


def sliders_sheet(out, head):
    meshes = load(head)
    n = 200
    names = FM.TARGETS
    cols = [("front", -1), ("front", 1), ("side", -1), ("side", 1)]
    sheet = Image.new("RGB", (n * len(cols) + 120, n * len(names)), (30, 30, 30))
    dr = ImageDraw.Draw(sheet)
    for r, name in enumerate(names):
        dr.text((6, r * n + n // 2), name, fill=(230, 230, 230))
        for ci, (view, w) in enumerate(cols):
            if name == FM.AGE:
                w = 0.0 if w < 0 else 1.0
            sheet.paste(Image.fromarray(raster(meshes, {name: w}, view, n)), (120 + ci * n, r * n))
        print(" ", name, flush=True)
    sheet.save(out)


def faces_row(out, specs):
    n = 240
    sheet = Image.new("RGB", (n * len(specs), n * 2), (30, 30, 30))
    for i, spec in enumerate(specs):
        head, _, kv = spec.partition(":")
        w = {k: float(v) for k, v in (p.split("=") for p in kv.split(",") if p)}
        meshes = load(head)
        sheet.paste(Image.fromarray(raster(meshes, w, "front", n)), (i * n, 0))
        sheet.paste(Image.fromarray(raster(meshes, w, "side", n)), (i * n, n))
    sheet.save(out)


if __name__ == "__main__":
    out = sys.argv[1]
    if sys.argv[2] == "--sliders":
        sliders_sheet(out, sys.argv[3] if len(sys.argv) > 3 else "default")
    else:
        faces_row(out, sys.argv[3].split(";"))
    print("wrote", out)
