#!/usr/bin/env python3
"""Side-view stick sheets of the quadruped's clips, without Blender: the fastest look at a gait.

    python3 tools/forge/preview/quadpreview.py out.png [Walk Trot ...] [--frames 8] [--deer]

One row per clip, `--frames` poses across its length, drawn from the animal's left side (the far
legs lighter). The body is carried forward at the clip's speed across each row, so a planted hoof
stands on one spot of the ground line: a hoof that slides draws a smear of dots.
"""
from __future__ import annotations

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

from forge.lib.quadruped import QuadSkeleton, QuadProportions, FEET, foot_bones  # noqa: E402
from forge.lib import quad_clips as qc  # noqa: E402

DEER = QuadProportions(withers=1.2, body_length=0.9, leg_length=1.15, neck_length=1.1, head_size=0.8,
                       bulk=0.7, cannon=1.2, tail_length=0.35)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("clips", nargs="*")
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--deer", action="store_true")
    ap.add_argument("--sheep", action="store_true")
    ap.add_argument("--scale", type=float, default=110.0, help="pixels per metre")
    a = ap.parse_args(argv)
    if a.sheep:
        from forge.lib import sheep_body as sb
        sk = QuadSkeleton(sb.EWE)
        solver = qc.make_solver(sk)
        lib = qc.build_sheep_clips(solver)
    elif a.deer:
        from forge.lib import deer_body as db
        sk = QuadSkeleton(db.RED)
        solver = qc.make_solver(sk)
        lib = qc.build_deer_clips(solver)
    else:
        sk = QuadSkeleton(None)
        solver = qc.make_solver(sk)
        lib = qc.build_clips(solver)
    a.scale *= 1.5 / sk.props.withers
    names = a.clips or list(lib.keys())
    S = a.scale
    cell_w = int(2.9 * S)
    W_img = cell_w * a.frames + 40
    row_h = int(2.4 * S)
    img = Image.new("RGB", (W_img, row_h * len(names) + 10), (246, 242, 232))
    d = ImageDraw.Draw(img)
    for r, name in enumerate(names):
        clip = lib[name]
        speed = float(clip.extra.get("speed", 0.0))
        y0 = row_h * (r + 1) - 12
        d.line([(0, y0), (W_img, y0)], fill=(150, 140, 120))
        d.text((6, row_h * r + 6), f"{name}  {clip.length:.2f}s  speed {speed}", fill=(40, 30, 20))
        n = a.frames
        for i in range(n):
            t = clip.length * i / (n if clip.loop else max(1, n - 1))
            R, th = solver.solve(clip.sample(t))
            pose = {k: (v, th if k == "Hips" else None) for k, v in R.items()}
            W = sk.fk(pose)
            ox = 20 + cell_w * i + int(1.5 * S)

            def P(v):
                # side view from the left: -Y (forward) to the left of the image... draw forward to the right
                return (ox + (-v[1]) * S, y0 - v[2] * S)
            for b in sk.order:
                if b == "Root" or b.startswith("Socket"):
                    continue
                far = b.endswith(".R")
                col = (170, 160, 150) if far else (60, 40, 30)
                if b.startswith(("Front", "Humerus", "Forearm", "Scapula")):
                    col = (180, 150, 140) if far else (150, 40, 30)
                if b.startswith(("Hind", "Thigh", "Gaskin")):
                    col = (140, 160, 180) if far else (30, 60, 140)
                d.line([P(W[b][:3, 3]), P(sk.tail_world(W, b))], fill=col, width=3 if not far else 2)
            qp = clip.sample(t)
            for f in FEET:
                p = sk.tail_world(W, foot_bones(f)[-1])
                fp = qp.feet.get(f)
                if fp is not None and fp.planted:
                    x, y = P(p)
                    d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(20, 150, 40))
    img.save(a.out)
    print(a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
