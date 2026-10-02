#!/usr/bin/env python3
"""A look at the horse's body and tack without Blender: mesh the SDF scenes and draw them.

    python3 tools/forge/preview/horsemesh.py out.png [--spacing 0.014] [--no-tack] [--deer]

Four orthographic views (the near side, the front, three-quarters from behind, and above), each
triangle filled and lit from the upper left by a small numpy z-buffer rasteriser: slow-ish (a
minute) but honest about the silhouette, which is what the SDF gets wrong first.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

from forge.lib import sdf  # noqa: E402
from forge.lib.quadruped import QuadSkeleton  # noqa: E402
from forge.lib import horse_body as hb  # noqa: E402
from forge.preview.quadpreview import DEER  # noqa: E402

COLOURS = {"body": (0.72, 0.58, 0.40), "cloth": (0.45, 0.20, 0.16), "saddle": (0.36, 0.22, 0.12),
           "straps": (0.30, 0.18, 0.10), "irons": (0.55, 0.55, 0.58), "bridle": (0.30, 0.18, 0.10)}


def tris_of(verts, quads):
    q = np.asarray(quads)
    return np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]], axis=0)


def raster(meshes, R, size, scale, centre):
    """meshes: [(verts, tris, rgb)]. R: 3x3 view rotation (rows: right, up, toward viewer)."""
    W, H = size
    zb = np.full((H, W), -1e9)
    img = np.ones((H, W, 3)) * np.array([0.95, 0.93, 0.88])
    light = np.array([-0.5, 0.6, 0.62])
    light /= np.linalg.norm(light)
    for verts, tris, rgb in meshes:
        V = (verts - centre) @ R.T
        sx = V[:, 0] * scale + W / 2
        sy = -V[:, 1] * scale + H / 2
        sz = V[:, 2]
        percol = np.ndim(rgb) == 2
        a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
        n = np.cross(V[b] - V[a], V[c] - V[a])
        nl = np.linalg.norm(n, axis=1)
        n = n / np.maximum(nl[:, None], 1e-12)
        fill = np.array([0.6, -0.2, 0.5])
        fill /= np.linalg.norm(fill)
        # smooth shading: normals at the vertices, the shade interpolated across each triangle
        vn = np.zeros_like(V)
        for j in range(3):
            np.add.at(vn, tris[:, j], n * nl[:, None])
        vn /= np.maximum(np.linalg.norm(vn, axis=1)[:, None], 1e-12)
        vshade = 0.28 + 0.55 * np.clip(vn @ light, 0, 1) + 0.22 * np.clip(vn @ fill, 0, 1) + 0.12 * np.clip(vn[:, 2], 0, 1)
        for i in range(len(tris)):
            if n[i, 2] <= 0:
                continue
            xs = sx[tris[i]]
            ys = sy[tris[i]]
            x0, x1 = int(max(0, math.floor(xs.min()))), int(min(W - 1, math.ceil(xs.max())))
            y0, y1 = int(max(0, math.floor(ys.min()))), int(min(H - 1, math.ceil(ys.max())))
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (xa, xb, xc), (ya, yb, yc) = xs, ys
            den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
            if abs(den) < 1e-12:
                continue
            l1 = ((yb - yc) * (gx - xc) + (xc - xb) * (gy - yc)) / den
            l2 = ((yc - ya) * (gx - xc) + (xa - xc) * (gy - yc)) / den
            l3 = 1 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            if not inside.any():
                continue
            z = l1 * sz[tris[i][0]] + l2 * sz[tris[i][1]] + l3 * sz[tris[i][2]]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            win = inside & (z > sub)
            sub[win] = z[win]
            sh = l1 * vshade[tris[i][0]] + l2 * vshade[tris[i][1]] + l3 * vshade[tris[i][2]]
            if percol:
                ta, tb, tc = tris[i]
                col = (l1[win][:, None] * rgb[ta] + l2[win][:, None] * rgb[tb] + l3[win][:, None] * rgb[tc])
                img[y0:y1 + 1, x0:x1 + 1][win] = col * sh[win][:, None]
            else:
                img[y0:y1 + 1, x0:x1 + 1][win] = np.array(rgb)[None, :] * sh[win][:, None]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def view(yaw_deg, pitch_deg):
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    # camera looks along -toward; start with the viewer on the horse's left (+X), up +Z
    right = np.array([0.0, -1.0, 0.0])
    up = np.array([0.0, 0.0, 1.0])
    toward = np.array([1.0, 0.0, 0.0])
    Rz = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    right, toward = Rz @ right, Rz @ toward
    # pitch: tilt the camera down to look from above
    toward2 = toward * math.cos(p) + up * math.sin(p)
    up2 = up * math.cos(p) - toward * math.sin(p)
    return np.stack([right, up2, toward2])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--spacing", type=float, default=0.016)
    ap.add_argument("--no-tack", action="store_true")
    ap.add_argument("--deer", action="store_true")
    ap.add_argument("--sheep", action="store_true")
    ap.add_argument("--stag", action="store_true", help="with --deer: the ruff and the antlers")
    ap.add_argument("--hart", action="store_true", help="the grey hart: the old stag, his rack and his coat")
    ap.add_argument("--px", type=int, default=560)
    ap.add_argument("--zoom", type=float, default=1.0)
    ap.add_argument("--paint", action="store_true", help="colour the body with the coat's albedo")
    ap.add_argument("--at", default="", help="x,y,z the views centre on")
    ap.add_argument("--views", default="", help="yaw,pitch;yaw,pitch;... (default: side, end, 3/4 behind, above)")
    a = ap.parse_args(argv)
    t0 = time.time()
    if a.sheep:
        from forge.lib import sheep_body as sb
        sk = QuadSkeleton(sb.EWE)
        scene = sb.sheep_scene(sk)
        a.no_tack = True
    else:
        if a.hart:
            a.deer = True
            from forge.lib import deer_body as db
            from forge import horse_forge as hf0
            sk = QuadSkeleton(db.HART)
            hst = hf0.hart_style()
            scene = db.deer_scene(sk, hst)
            scene.prims[-1:-1] = db.antler_scene(sk, hst.points).prims
        elif a.deer:
            from forge.lib import deer_body as db
            sk = QuadSkeleton(db.RED)
            scene = db.deer_scene(sk, db.DeerStyle(ruff=1.0 if a.stag else 0.0))
            if a.stag:
                scene.prims[-1:-1] = db.antler_scene(sk).prims
        else:
            sk = QuadSkeleton(None)
            scene = hb.horse_scene(sk, hb.HorseStyle())
    grid = []
    v, q = sdf.mesh_from_scene(scene, a.spacing, grid_out=grid)
    print("body %d verts, %d quads, %.1fs" % (len(v), len(q), time.time() - t0))
    meshes = [(v, tris_of(v, q), COLOURS["body"])]
    if a.paint and a.hart:
        from forge import horse_forge as hf
        albedo, _, _ = hf.deer_paint(sk, sdf.SampledField.from_grid(*grid), hst, "hart")
        meshes = [(v, tris_of(v, q), albedo(v, sdf.vertex_normals(v, q)) * 1.15)]
    elif a.paint and not a.deer:
        from forge import horse_forge as hf
        field0 = sdf.SampledField.from_grid(*grid)
        if a.sheep:
            albedo, _, _ = hf.sheep_paint(sk, field0, sb.SheepStyle())
        else:
            albedo, _, _ = hf.coat_paint(sk, field0)
        nrm = sdf.vertex_normals(v, q)
        meshes = [(v, tris_of(v, q), albedo(v, nrm) * 1.15)]
        print("painted %.1fs" % (time.time() - t0))
    if not a.no_tack and not a.deer:
        field = sdf.SampledField.from_grid(*grid)
        for name, sc in hb.tack_scenes(sk, field).items():
            tv, tq = sdf.mesh_from_scene(sc, min(a.spacing, 0.006), smooth_iters=2)
            print("  %s: %d quads" % (name, len(tq)))
            if len(tq):
                meshes.append((tv, tris_of(tv, tq), COLOURS[name]))
    centre = np.array([0.0, -0.1, 1.0]) * (sk.props.withers / 1.5)
    if a.at:
        centre = np.array([float(x) for x in a.at.split(",")])
    views = [view(0, 0), view(90, 0), view(215, 20), view(0, -60) if a.sheep else view(0, 89)]
    if a.views:
        views = [view(*[float(x) for x in v.split(",")]) for v in a.views.split(";")]
    tiles = []
    for R in views:
        tiles.append(raster(meshes, R, (a.px, a.px), a.zoom * a.px / (2.9 * sk.props.withers / 1.5), centre))
    while len(tiles) % 2:
        tiles.append(np.full_like(tiles[0], 240))
    rows = [np.concatenate(tiles[i:i + 2], axis=1) for i in range(0, len(tiles), 2)]
    Image.fromarray(np.concatenate(rows, axis=0)).save(a.out)
    print(a.out, "%.1fs" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
