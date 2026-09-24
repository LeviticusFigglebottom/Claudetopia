#!/usr/bin/env python3
"""Weather the shipped dead ash trees and char stumps to the dead_bark lib/materials.py now makes,
without rebuilding them.

    python3 tools/forge/weather_dead_wood.py game/assets/models/trees/cinderlea_dead_ash_tree_a ...
        [--smooth] [--dry-run]

Over the ash heath's black soil every dead ash tree read as crumpled white paper: a near-white
bark (sRGB 0.57 across the atlas) on limbs three or four sides round, each edge of which the
smoothing angle split, so every limb was a row of lit and unlit facets. lib/materials.py's
dead_bark is now a weathered ash-grey, streaked down the grain and rotting at the foot, and
gen_trees.py smooths the dead ash tree whole. A rebuild makes that; this makes the shipped assets
match it without one, because the forge grows its trees with Blender's Sapling add-on, which
Blender 4.2 no longer carries (it moved to the extensions platform), so a machine with 4.2 cannot
rebuild a tree at all.

For each asset folder:
  * the bark albedo is darkened in sRGB (x0.64, which takes the old atlas's spread onto the new
    material's: a median of 0.54 to 0.35), streaked along the grain (the V axis of the forge's
    cylinder unwrap) and laid with umber rot, most of it within 2.5 m of the ground, the height
    of each texel read from the mesh itself;
  * with --smooth, the bark meshes' normals (every level but the impostor) are recomputed smooth
    across every edge, as a whole-tree smoothing angle would have exported them;
  * the impostor pictures are darkened by the same factor, so the far tree matches the near one.

It is deterministic (fixed seeds) and idempotent only in the sense that running it twice darkens
twice: run it once, on the assets as the forge made them. Re-measure the impostor calibration
afterwards (game/world/impostor_calibration.json; tools_gd/lod_review.tscn --calibrate), since it
was taken against the white bark.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

import numpy as np
import pygltflib
from PIL import Image, ImageDraw
from scipy import ndimage

VALUE = 0.64                    # sRGB value scale: old atlas median 0.54 -> 0.35
ROT_SRGB = np.array([0x3a, 0x2d, 0x25]) / 255.0
DAMP_SRGB = np.array([0x26, 0x2a, 0x20]) / 255.0
COMP = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}
NUM = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


# --- glTF access ------------------------------------------------------------------------------

def _view(g, blob, acc_i):
    acc = g.accessors[acc_i]
    bv = g.bufferViews[acc.bufferView]
    fmt, size = COMP[acc.componentType]
    n = NUM[acc.type]
    stride = bv.byteStride or size * n
    base = (bv.byteOffset or 0) + (acc.byteOffset or 0)
    return acc, fmt, size, n, stride, base


def read(g, blob, acc_i) -> np.ndarray:
    acc, fmt, size, n, stride, base = _view(g, blob, acc_i)
    if stride == size * n:
        dt = {"f": "<f4", "H": "<u2", "I": "<u4", "B": "u1"}[fmt]
        return np.frombuffer(blob, dtype=dt, count=acc.count * n, offset=base).reshape(acc.count, n).astype(np.float64)
    out = np.zeros((acc.count, n))
    for i in range(acc.count):
        out[i] = struct.unpack_from("<" + fmt * n, blob, base + i * stride)
    return out


def write_vec3(g, blob: bytearray, acc_i, values: np.ndarray) -> None:
    acc, fmt, size, n, stride, base = _view(g, blob, acc_i)
    assert fmt == "f" and n == 3
    for i in range(acc.count):
        struct.pack_into("<fff", blob, base + i * stride, *values[i])


def bark_primitives(g):
    """(mesh name, primitive) for every primitive not drawn with an impostor or card material."""
    out = []
    for mesh in g.meshes:
        for prim in mesh.primitives:
            mat = g.materials[prim.material].name if prim.material is not None else ""
            if "impostor" in mat or "foliage" in mat or "card" in mat:
                continue
            out.append((mesh.name, prim))
    return out


def smooth_normals(pos: np.ndarray, idx: np.ndarray) -> np.ndarray:
    """Area-weighted vertex normals shared by every vertex at one position: no edge is split."""
    key = np.round(pos, 4)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    tri = idx.reshape(-1, 3)
    a, b, c = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    fn = np.cross(b - a, c - a)                          # length is twice the area
    acc = np.zeros((inv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, inv[tri[:, k]], fn)
    n = acc[inv]
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return np.where(ln > 1e-12, n / np.maximum(ln, 1e-12), np.array([0.0, 1.0, 0.0]))


# --- the albedo -----------------------------------------------------------------------------

def height_in_uv(g, blob, size: int) -> np.ndarray:
    """Each texel's height above the tree's foot (metres), from the LOD0 bark triangles."""
    img = Image.new("F", (size, size), -1.0)
    draw = ImageDraw.Draw(img)
    for name, prim in bark_primitives(g):
        if "_LOD" in name:
            continue
        pos = read(g, blob, prim.attributes.POSITION)
        uv = read(g, blob, prim.attributes.TEXCOORD_0)
        idx = read(g, blob, prim.indices).astype(np.int64).reshape(-1)
        y0 = pos[:, 1].min()
        for t in idx.reshape(-1, 3):
            poly = [(float(uv[i, 0] * size), float(uv[i, 1] * size)) for i in t]
            draw.polygon(poly, fill=float(pos[t, 1].mean() - y0))
    h = np.asarray(img, dtype=np.float32)
    # fill the gutters from the nearest drawn texel, so the margins weather like their island
    missing = h < 0
    if missing.any() and (~missing).any():
        _, (iy, ix) = ndimage.distance_transform_edt(missing, return_indices=True)
        h = h[iy, ix]
    return np.maximum(h, 0.0)


def field(shape, sigma, seed) -> np.ndarray:
    rng = np.random.default_rng(seed)
    f = ndimage.gaussian_filter(rng.standard_normal(shape), sigma, mode="wrap")
    f -= f.min()
    return f / max(f.max(), 1e-9)


def weather_albedo(rgb: np.ndarray, height: np.ndarray, seed: int) -> np.ndarray:
    """rgb in sRGB 0..1 (h, w, 3)."""
    h, w = rgb.shape[:2]
    out = rgb * VALUE
    # streaks down the grain: long along V (the image's rows), narrow across it
    s = field((h, w), (h / 22.0, w / 170.0), seed)
    silver = np.clip((s - 0.58) / 0.17, 0.0, 1.0)[..., None] * 0.35
    stain = np.clip((0.42 - s) / 0.14, 0.0, 1.0)[..., None] * 0.45
    grey = out.mean(axis=2, keepdims=True)
    out = out * (1.0 - silver) + np.minimum(1.0, (0.7 * out + 0.3 * grey) * 1.25) * silver
    out = out * (1.0 - stain) + out * 0.7 * stain
    # rot at the foot, in soft patches
    r = field((h, w), (w / 60.0, w / 60.0), seed + 1)
    low = np.clip((2.5 - height) / 2.3, 0.0, 1.0) + 0.25
    rot = (np.clip((r - 0.45) / 0.2, 0.0, 1.0) * np.clip(low, 0.0, 1.0) * 0.75)[..., None]
    out = out * (1.0 - rot) + ROT_SRGB * rot
    damp = rot * np.clip(low, 0.0, 1.0)[..., None] * 0.6
    out = out * (1.0 - damp) + DAMP_SRGB * damp
    # only the painted texels: the atlas's empty background stays as the bake left it
    painted = (rgb.mean(axis=2) > 0.01)[..., None]
    return np.where(painted, np.clip(out, 0.0, 1.0), rgb)


# --- one asset ------------------------------------------------------------------------------

def weather(folder: Path, smooth: bool, dry: bool, seed: int = 20260924) -> dict:
    name = folder.name
    glb_path = folder / ("%s.glb" % name)
    g = pygltflib.GLTF2().load(str(glb_path))
    blob = bytearray(g.binary_blob())
    report = {"asset": name}

    alb_path = folder / ("%s_albedo.png" % name)
    im = Image.open(alb_path)
    mode = im.mode
    arr = np.asarray(im.convert("RGBA")).astype(np.float64) / 255.0
    height = height_in_uv(g, bytes(blob), arr.shape[0])
    before = float(np.median(arr[..., :3].mean(axis=2)[arr[..., :3].mean(axis=2) > 0.02]))
    arr[..., :3] = weather_albedo(arr[..., :3], height, seed + sum(map(ord, name)))
    after = float(np.median(arr[..., :3].mean(axis=2)[arr[..., :3].mean(axis=2) > 0.02]))
    report["albedo median"] = "%.2f -> %.2f" % (before, after)
    if not dry:
        out = Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8), "RGBA")
        (out if mode == "RGBA" else out.convert(mode)).save(alb_path, optimize=True)

    for imp in sorted(folder.glob("*_impostor_albedo.png")):
        a = np.asarray(Image.open(imp).convert("RGBA")).astype(np.float64) / 255.0
        a[..., :3] *= VALUE
        if not dry:
            Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), "RGBA").save(imp, optimize=True)
        report[imp.name] = "x%.2f" % VALUE

    if smooth:
        moved = 0
        for mesh_name, prim in bark_primitives(g):
            pos = read(g, bytes(blob), prim.attributes.POSITION)
            idx = read(g, bytes(blob), prim.indices).astype(np.int64).reshape(-1)
            old = read(g, bytes(blob), prim.attributes.NORMAL)
            new = smooth_normals(pos, idx)
            moved += int((np.einsum("ij,ij->i", old, new) < 0.999).sum())
            write_vec3(g, blob, prim.attributes.NORMAL, new)
        report["normals smoothed"] = moved
        if not dry:
            g.set_binary_blob(bytes(blob))
            g.save_binary(str(glb_path))
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--smooth", action="store_true", help="recompute the bark normals smooth")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    for f in args.folders:
        print(weather(Path(f), args.smooth, args.dry_run))
    return 0


if __name__ == "__main__":
    sys.exit(main())
