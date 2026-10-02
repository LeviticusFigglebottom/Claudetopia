#!/usr/bin/env python3
"""A look at a forged foe's body without Blender: mesh its SDF scene and draw four views.

    python3 tools/forge/preview/beastmesh.py <foe> out.png [--spacing 0.01] [--paint] [--views yaw,pitch;...]

The foes are lib/foe_specs.py's. `--paint` colours the mesh with the forge's albedo; `--clip
Name@t` poses it first (segment weights, linear blend skinning), for a quick look at a clip's frame.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

from forge.lib import sdf  # noqa: E402
from forge.lib import foe_specs  # noqa: E402
from forge.preview.horsemesh import raster, view, tris_of  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("foe")
    ap.add_argument("out")
    ap.add_argument("--spacing", type=float, default=0.0)
    ap.add_argument("--px", type=int, default=520)
    ap.add_argument("--zoom", type=float, default=1.0)
    ap.add_argument("--paint", action="store_true")
    ap.add_argument("--views", default="")
    ap.add_argument("--at", default="", help="joint name or x,y,z the views centre on")
    ap.add_argument("--crop", type=float, default=0.0, help="with --at: mesh only this far round it, m")
    ap.add_argument("--per-row", type=int, default=1)
    ap.add_argument("--clips", default="", help="Name@t,Name@t: pose the mesh at these frames, one row each")
    a = ap.parse_args(argv)
    t0 = time.time()
    sp = foe_specs.spec(a.foe)
    skel = sp.skel
    sc = sp.scene()
    grid = []
    spacing = a.spacing or sp.spacing * 1.8
    if a.crop and a.at:
        c = np.array(skel.J[a.at]) if a.at in skel.J else np.array([float(x) for x in a.at.split(",")])
        F, origin, _ = sc.grid(spacing, box=(c - a.crop, c + a.crop))
        grid[:] = [F, origin, spacing]
        v, q = sdf.surface_nets(F, origin, spacing)
        v = sdf.taubin_smooth(v, q, iters=6)
    elif "parts" in sp.extra:
        vs, qs, off = [], [], 0
        for pname, psc in sp.extra["parts"]().items():
            pv, pq = sdf.mesh_from_scene(psc, spacing)
            vs.append(pv)
            qs.append(np.asarray(pq) + off)
            off += len(pv)
        v, q = np.concatenate(vs), np.concatenate(qs)
    else:
        v, q = sdf.mesh_from_scene(sc, spacing, grid_out=grid)
    tris = tris_of(v, q)
    print("%s: %d verts, %d tris, %.1fs" % (a.foe, len(v), len(tris), time.time() - t0))
    col = np.array([0.62, 0.55, 0.46])
    if a.paint:
        from forge.lib import foe_paint
        field = sdf.SampledField.from_grid(*grid)
        nrm = sdf.vertex_normals(v, q)
        albedo, _, _ = foe_paint.painter(sp, field)
        col = np.clip(albedo(v, nrm) * 1.15, 0, 1)
        print("painted %.1fs" % (time.time() - t0))
    lo, hi = v.min(axis=0), v.max(axis=0)
    centre = 0.5 * (lo + hi)
    extent = float(max(hi[1] - lo[1], hi[2] - lo[2], hi[0] - lo[0]))
    if a.at:
        centre = np.array(skel.J[a.at]) if a.at in skel.J else np.array([float(x) for x in a.at.split(",")])
    views = [view(0, 0), view(90, 0), view(215, 20), view(320, 12)]
    if a.views:
        views = [view(*[float(x) for x in vv.split(",")]) for vv in a.views.split(";")]
    rows = []
    poses = [p for p in a.clips.split(",") if p] or [""]
    free = sp.family not in foe_specs.QUADS
    if a.clips:
        from forge.lib import foe_clips
        from forge.lib import creature_rig as cr
        clips = sp.extra["module"].build_clips() if free else foe_clips.build(sp)
        W = cr.segment_weights(skel, v) if free else foe_clips.mesh_weights(sp, v)
    for pose in poses:
        vv = v
        if pose:
            name, t = pose.split("@")
            vv = cr.pose_mesh(skel, clips[name].sample(float(t)), v, W) if free else \
                foe_clips.pose_mesh(sp, clips[name], float(t), v, W)
        tiles = [raster([(vv, tris, col)], R, (a.px, a.px), a.zoom * a.px / (1.25 * extent), centre) for R in views]
        tile = np.concatenate(tiles, axis=1)
        if pose:
            from PIL import ImageDraw
            im = Image.fromarray(tile)
            ImageDraw.Draw(im).text((6, 4), pose, fill=(40, 30, 20))
            tile = np.asarray(im)
        rows.append(tile)
    per = max(1, a.per_row)
    while len(rows) % per:
        rows.append(np.full_like(rows[0], 240))
    lines = [np.concatenate(rows[i:i + per], axis=1) for i in range(0, len(rows), per)]
    Image.fromarray(np.concatenate(lines, axis=0)).save(a.out)
    print(a.out, "%.1fs" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
