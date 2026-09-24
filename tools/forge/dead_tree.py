#!/usr/bin/env python3
"""Grow a bare dead tree as one piece of wood, and put it in a forge tree's GLB in place of its
trunk (LOD0 and LOD1), with a bark texture that tiles along the wood.

    python3 tools/forge/dead_tree.py game/assets/models/trees/cinderlea_dead_ash_tree_a [--seed N]

Why this exists. The forge grows its trees with Blender's Sapling, then trims the wood to a
triangle budget. A living tree hides the result under its leaves; a dead one is nothing but wood,
and the trim had left Cinderlea's dead ash trees as 630 separate three-sided prisms, an 8 m trunk
in 18 triangles, every limb and twig a loose triangular shard -- black paper flags at a distance
and a shattered tree up close. (Blender 4.2 no longer carries Sapling, so they could not be grown
again here either.)

This grows the tree directly: a trunk that leans and kinks a little, which forks and forks again
into limbs and twigs by the pipe rule (a parent's cross-section is its children's summed), each
branch a tapered tube starting inside its parent, so the wood is continuous and every twig ends
in a point. Tubes are 7-sided on the trunk and limbs and 4-sided on the twigs; LOD1 is the same
tree with the finest twigs left off and fewer sides. UVs run round the wood (u, one turn) and
along it (v, metres), with a tiling bark texture painted here: the weathered ash-grey of
lib/materials.dead_bark -- streaks down the grain, cracks, rot toward the foot.

The GLB's other parts (the impostor quad, materials, samplers) are kept; the bark's albedo,
normal and ORM PNGs are replaced by the tiling ones. Re-render the impostor afterwards
(build_assets.py --force --only <name>_impostor) and re-measure its calibration.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
import pygltflib
from PIL import Image
from scipy import ndimage

# --- the tree -------------------------------------------------------------------------------


class Branch:
    def __init__(self, pts: np.ndarray, radii: np.ndarray, level: int):
        self.pts = pts          # (k, 3) points along the axis
        self.radii = radii      # (k,) radius at each point
        self.level = level


def _rot(axis: np.ndarray, angle: float) -> np.ndarray:
    axis = axis / (np.linalg.norm(axis) + 1e-9)
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def _perp(d: np.ndarray) -> np.ndarray:
    a = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    p = np.cross(d, a)
    return p / np.linalg.norm(p)


def grow(rng: np.random.Generator, height: float) -> list[Branch]:
    out: list[Branch] = []

    def limb(base, direction, length, r0, level, max_level):
        segs = max(3, int(length / (0.55 if level == 0 else 0.4)))
        pts = [base]
        d = direction / np.linalg.norm(direction)
        step = length / segs
        # dead wood reaches up, then droops a little at the ends; it kinks where it grew
        for i in range(segs):
            d = d + rng.normal(0, 0.16 if level else 0.07, 3)
            d[1] += (0.05 if level < 2 else -0.04)
            d = d / np.linalg.norm(d)
            pts.append(pts[-1] + d * step)
        pts = np.array(pts)
        t = np.linspace(0.0, 1.0, len(pts))
        tip = 0.004 if level >= max_level else r0 * 0.35
        radii = r0 * (1.0 - t) + tip * t
        out.append(Branch(pts, radii, level))
        if level >= max_level:
            return
        # children along the upper part of this branch, the pipe rule sharing its section
        n = int(rng.integers(3, 5)) if level <= 1 else int(rng.integers(2, 4))
        starts = np.sort(rng.uniform(0.45 if level == 0 else 0.3, 0.95, n))
        for k, u in enumerate(starts):
            i = min(int(u * (len(pts) - 1)), len(pts) - 2)
            here = pts[i]
            ax = pts[i + 1] - pts[i]
            ax = ax / np.linalg.norm(ax)
            around = _rot(ax, rng.uniform(0, 2 * math.pi) + k * 2.1)
            tilt = math.radians(rng.uniform(22, 48))
            cd = _rot(around @ _perp(ax), tilt) @ ax
            r_here = radii[i]
            cr = r_here * math.sqrt(1.0 / (n + 0.6)) * rng.uniform(0.85, 1.05)
            clen = length * rng.uniform(0.6, 0.85) * (1.0 - 0.3 * u) * (1.25 if level == 0 else 1.0)
            limb(here - ax * r_here * 0.5, cd, clen, cr, level + 1, max_level)

    trunk_len = height * rng.uniform(0.62, 0.72)
    lean = np.array([rng.normal(0, 0.12), 1.0, rng.normal(0, 0.12)])
    limb(np.zeros(3), lean, trunk_len, height * 0.03, 0, 4)
    return out


# --- the mesh -------------------------------------------------------------------------------

def tube(b: Branch, sides: int):
    """Vertices, normals, UVs and triangles of a tapered tube along a branch, closed at the tip."""
    pts, radii = b.pts, b.radii
    k = len(pts)
    V, N, UV, T = [], [], [], []
    # parallel transport of a frame along the axis, so the tube does not twist
    d0 = pts[1] - pts[0]
    d0 /= np.linalg.norm(d0)
    n0 = _perp(d0)
    along = 0.0
    frames = []
    for i in range(k):
        d = (pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)])
        d /= np.linalg.norm(d)
        n0 = n0 - d * np.dot(n0, d)
        n0 /= np.linalg.norm(n0)
        frames.append((d, n0, np.cross(d, n0)))
    for i in range(k):
        d, n, bnorm = frames[i]
        if i > 0:
            along += np.linalg.norm(pts[i] - pts[i - 1])
        for j in range(sides + 1):
            a = 2 * math.pi * j / sides
            rad = math.cos(a) * n + math.sin(a) * bnorm
            V.append(pts[i] + rad * radii[i])
            N.append(rad)
            # u: once round the wood (the bark's width is 0.5 m of it at any girth); v: metres
            UV.append((j / sides * max(1.0, 2 * math.pi * radii[i] / 0.5), along / 1.2))
    for i in range(k - 1):
        for j in range(sides):
            a = i * (sides + 1) + j
            b2 = a + sides + 1
            T += [(a, b2, a + 1), (a + 1, b2, b2 + 1)]
    return np.array(V), np.array(N), np.array(UV), np.array(T)


def build(branches: list[Branch], lod: int):
    V, N, UV, T = [], [], [], []
    off = 0
    for b in branches:
        if lod == 1 and b.level >= 4:
            continue
        sides = (7 if b.level <= 1 else 5 if b.level == 2 else 4 if b.level == 3 else 3) if lod == 0 \
            else (5 if b.level <= 1 else 3)
        bb = b
        if lod == 1 and len(b.pts) > 4:
            keep = np.unique(np.r_[np.arange(0, len(b.pts), 2), len(b.pts) - 1])
            bb = Branch(b.pts[keep], b.radii[keep], b.level)
        v, n, uv, t = tube(bb, sides)
        V.append(v); N.append(n); UV.append(uv); T.append(t + off)
        off += len(v)
    return (np.concatenate(V).astype(np.float32), np.concatenate(N).astype(np.float32),
            np.concatenate(UV).astype(np.float32), np.concatenate(T).astype(np.uint32))


# --- the bark -------------------------------------------------------------------------------

def _pnoise(n, rng, sx, sy):
    """Seamless noise, stretched: sx, sy are feature sizes in pixels."""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    spec = (rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))) \
        * np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2))
    out = np.real(np.fft.ifft2(spec))
    return (out - out.mean()) / (out.std() + 1e-9)


def bark_textures(size: int, seed: int):
    """Albedo (sRGB, RGB), normal (RGB, +Y up) and ORM for weathered dead ash wood; v is along the
    grain (image rows)."""
    rng = np.random.default_rng(seed)
    grain = _pnoise(size, rng, 3.0, 60.0)          # long along the grain (y), narrow across
    streak = _pnoise(size, rng, 10.0, 140.0)
    blot = _pnoise(size, rng, 60.0, 60.0)
    crack = np.clip((np.abs(_pnoise(size, rng, 4.0, 90.0)) - 1.6) * 2.0, 0.0, 1.0)
    base = np.array([0.45, 0.43, 0.40])            # silvered ash-grey, sRGB
    v = 1.0 + 0.10 * grain + 0.12 * streak + 0.06 * blot - 0.45 * crack
    alb = base[None, None, :] * v[..., None]
    silver = np.clip(streak - 0.8, 0.0, 1.0)[..., None]
    alb = alb * (1 - 0.35 * silver) + np.array([0.60, 0.59, 0.56]) * 0.35 * silver
    rot = np.clip(blot - 0.9, 0.0, 1.0)[..., None]
    alb = alb * (1 - 0.6 * rot) + np.array([0.24, 0.19, 0.15]) * 0.6 * rot
    alb = np.clip(alb, 0.0, 1.0)
    h = 0.5 + 0.08 * grain + 0.05 * streak - 0.35 * crack
    gy, gx = np.gradient(ndimage.gaussian_filter(h, 0.8, mode="wrap"))
    nrm = np.dstack([-gx * 6.0, gy * 6.0, np.ones_like(h)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    rough = np.clip(0.86 + 0.06 * grain + 0.08 * crack, 0.0, 1.0)
    orm = np.dstack([np.clip(1.0 - 0.5 * crack, 0, 1), rough, np.zeros_like(h)])
    to8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    return to8(alb), to8(nrm * 0.5 + 0.5), to8(orm)


# --- the GLB --------------------------------------------------------------------------------

def _pad4(b: bytes) -> bytes:
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def rewrite(glb_path: Path, lods: dict) -> dict:
    """Replace the LOD0 and LOD1 meshes' single primitive with new geometry; rebuild the buffer."""
    g = pygltflib.GLTF2().load(str(glb_path))
    old = g.binary_blob()
    blob = bytearray()
    views, accs = [], []

    def add(arr: np.ndarray, target, comp, typ, minmax=False):
        data = _pad4(arr.tobytes())
        views.append(pygltflib.BufferView(buffer=0, byteOffset=len(blob), byteLength=arr.nbytes, target=target))
        blob.extend(data)
        acc = pygltflib.Accessor(bufferView=len(views) - 1, componentType=comp, count=len(arr), type=typ)
        if minmax:
            acc.min = [float(x) for x in arr.min(0)]
            acc.max = [float(x) for x in arr.max(0)]
        accs.append(acc)
        return len(accs) - 1

    tris = {}
    for mesh in g.meshes:
        for prim in mesh.primitives:
            lod = 1 if mesh.name.endswith("_LOD1") else (2 if mesh.name.endswith("_LOD2") else 0)
            if lod in lods:
                V, N, UV, T = lods[lod]
                prim.attributes.POSITION = add(V, 34962, 5126, "VEC3", True)
                prim.attributes.NORMAL = add(N, 34962, 5126, "VEC3")
                prim.attributes.TEXCOORD_0 = add(UV, 34962, 5126, "VEC2")
                prim.indices = add(T.reshape(-1), 34963, 5125, "SCALAR")
                tris[mesh.name] = int(len(T))
            else:
                # copy this primitive's accessors across as they were
                for key in ("POSITION", "NORMAL", "TEXCOORD_0", "TANGENT"):
                    ai = getattr(prim.attributes, key)
                    if ai is None:
                        continue
                    a = g.accessors[ai]
                    bv = g.bufferViews[a.bufferView]
                    raw = old[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
                    views.append(pygltflib.BufferView(buffer=0, byteOffset=len(blob), byteLength=bv.byteLength,
                                                      byteStride=bv.byteStride, target=bv.target))
                    blob.extend(_pad4(raw))
                    a2 = pygltflib.Accessor(bufferView=len(views) - 1, byteOffset=a.byteOffset, componentType=a.componentType,
                                            count=a.count, type=a.type, min=a.min, max=a.max, normalized=a.normalized)
                    accs.append(a2)
                    setattr(prim.attributes, key, len(accs) - 1)
                a = g.accessors[prim.indices]
                bv = g.bufferViews[a.bufferView]
                raw = old[(bv.byteOffset or 0):(bv.byteOffset or 0) + bv.byteLength]
                views.append(pygltflib.BufferView(buffer=0, byteOffset=len(blob), byteLength=bv.byteLength, target=bv.target))
                blob.extend(_pad4(raw))
                accs.append(pygltflib.Accessor(bufferView=len(views) - 1, byteOffset=a.byteOffset, componentType=a.componentType,
                                               count=a.count, type=a.type, min=a.min, max=a.max))
                prim.indices = len(accs) - 1
                tris[mesh.name] = int(a.count // 3)
    g.bufferViews = views
    g.accessors = accs
    g.buffers = [pygltflib.Buffer(byteLength=len(blob))]
    g.set_binary_blob(bytes(blob))
    g.save_binary(str(glb_path))
    return tris


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folder")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    folder = Path(args.folder)
    name = folder.name
    meta_path = folder / ("%s.meta.json" % name)
    meta = json.loads(meta_path.read_text())
    height = float(meta.get("height_m", 9.0))
    seed = args.seed or int(meta.get("seed", 1)) * 7919 + 13
    rng = np.random.default_rng(seed)
    branches = grow(rng, height)
    lods = {0: build(branches, 0), 1: build(branches, 1)}
    tris = rewrite(folder / ("%s.glb" % name), lods)
    alb, nrm, orm = bark_textures(512, seed)
    Image.fromarray(alb, "RGB").save(folder / ("%s_albedo.png" % name), optimize=True)
    Image.fromarray(nrm, "RGB").save(folder / ("%s_normal.png" % name), optimize=True)
    Image.fromarray(orm, "RGB").resize((256, 256)).save(folder / ("%s_orm.png" % name), optimize=True)
    V = lods[0][0]
    meta["bounds"] = {"min": [round(float(x), 3) for x in V.min(0)], "max": [round(float(x), 3) for x in V.max(0)],
                      "height": round(float(V[:, 1].max()), 3),
                      "radius": round(float(np.hypot(V[:, 0], V[:, 2]).max()), 3)}
    for m in meta.get("meshes", []):
        if m["name"] in tris:
            m["tris"] = tris[m["name"]]
    meta["tris"] = [tris.get(name, 0), tris.get(name + "_LOD1", 0), tris.get(name + "_LOD2", 0)]
    meta["dead_tree"] = {"generator": "tools/forge/dead_tree.py", "seed": seed, "branches": len(branches)}
    meta_path.write_text(json.dumps(meta, indent=1) + "\n")
    print("%s: %d branches, LOD0 %d tris, LOD1 %d tris, height %.1f m" % (
        name, len(branches), tris.get(name, 0), tris.get(name + "_LOD1", 0), float(V[:, 1].max())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
