"""Props generator: chunky-but-detailed hand-made objects (a barrel has staves and hoops).

    blender -b --python tools/forge/gen_props.py -- --kind barrel --palette hearthvale --seed 1 --variant a

Every kind is a function (pal, rng, params, variant) -> spec for export.finish_asset. Parts
are built from primitives with modelled bevels and a little seeded asymmetry, given
materials from lib.materials, and baked to one atlas per asset.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib.runner import run_generator  # noqa: E402

CHUNK = 1.1  # CONTRACTS §1: ~1.1x chunky stylisation on props


def jit(rng, v, pct=0.06):
    return v * (1.0 + rng.uniform(-pct, pct))


# --- barrel -----------------------------------------------------------------------------

def barrel(pal, rng, params, variant):
    h = jit(rng, params.get("height", 0.9)) * CHUNK
    r = jit(rng, params.get("radius", 0.31)) * CHUNK
    bulge = params.get("bulge", 0.12) + rng.uniform(-0.02, 0.03)
    staves = params.get("staves", 18)
    wood = M.wood_planks(pal, wear=0.5 + 0.3 * rng.random(), age=0.4 + 0.4 * rng.random(),
                         plank_len=h * 1.2, plank_w=2 * math.pi * r / staves, along="Z", scale=1.0)
    metal = M.iron(pal, age=0.5 + 0.4 * rng.random(), wear=0.6)
    # body: revolve a bulged profile; alternate vertices pulled in a hair so staves read
    prof = []
    n = 9
    for i in range(n + 1):
        t = i / n
        z = t * h
        rr = r * (1.0 + bulge * math.sin(math.pi * t))
        prof.append((rr, z))
    body = S.lathe("barrel_body", prof, segments=staves * 2, mat=wood, close=False)
    for v in body.data.vertices:
        # groove between staves: every second ring vertex slightly inward
        ang = math.atan2(v.co.y, v.co.x)
        k = int(round((ang % (2 * math.pi)) / (2 * math.pi) * staves * 2)) % 2
        if k == 1:
            v.co.x *= 0.985
            v.co.y *= 0.985
    S.shade_smooth(body, 40.0)
    # heads (top and bottom) set into the body
    inset = 0.035 * h
    top = S.cylinder("barrel_top", radius=r * 0.985, depth=0.03, vertices=staves * 2, location=(0, 0, h - inset - 0.03), mat=wood)
    bot = S.cylinder("barrel_bot", radius=r * 0.985, depth=0.03, vertices=staves * 2, location=(0, 0, inset), mat=wood)
    # bung
    bung = S.cylinder("bung", radius=0.03, depth=0.02, vertices=12, location=(r * 1.09, 0, h * 0.5), rotation=(0, 90, 0), mat=wood)
    parts = [body, top, bot, bung]
    # hoops: flattened tori
    for t in (0.12, 0.3, 0.7, 0.88):
        rr = r * (1.0 + bulge * math.sin(math.pi * t)) + 0.008
        hoop = S.torus("hoop", major=rr, minor=0.011, seg_major=staves * 2, seg_minor=6, location=(0, 0, t * h), mat=metal)
        hoop.scale = (1, 1, 2.2)
        S.apply_transforms(hoop)
        parts.append(hoop)
    for p in parts:
        S.jitter_verts(p, amount=0.004, scale=0.5, seed=rng.randrange(1000))
    return {"opaque_objs": parts, "collision": "convex", "materials_used": ["wood_planks", "iron"]}


# --- crate ---------------------------------------------------------------------------------

def crate(pal, rng, params, variant):
    w = jit(rng, params.get("width", 0.7)) * CHUNK
    d = jit(rng, params.get("depth", 0.7)) * CHUNK
    h = jit(rng, params.get("height", 0.6)) * CHUNK
    t = 0.028
    wood = M.wood_planks(pal, wear=0.5 + 0.3 * rng.random(), age=0.3 + 0.5 * rng.random(), plank_len=w, plank_w=0.14, along="X")
    dark = M.wood_planks(pal, wear=0.4, age=0.7, plank_len=w, plank_w=0.09, along="Z", base_hex="#6f5333", name="wood_frame")
    parts = []
    # slatted faces: horizontal slats with small gaps on four sides, solid top/bottom
    slats = 4
    gap = 0.012
    sh = (h - gap * (slats + 1)) / slats
    for i in range(slats):
        z = gap + i * (sh + gap)
        parts.append(S.cube("slat_f", size=(w, t, sh), location=(0, -d / 2 + t / 2, z), mat=wood))
        parts.append(S.cube("slat_b", size=(w, t, sh), location=(0, d / 2 - t / 2, z), mat=wood))
        parts.append(S.cube("slat_l", size=(t, d - 2 * t, sh), location=(-w / 2 + t / 2, 0, z), mat=wood))
        parts.append(S.cube("slat_r", size=(t, d - 2 * t, sh), location=(w / 2 - t / 2, 0, z), mat=wood))
    parts.append(S.cube("lid", size=(w, d, t), location=(0, 0, h - t), mat=wood))
    parts.append(S.cube("floor", size=(w - 2 * t, d - 2 * t, t), location=(0, 0, 0.0), mat=wood))
    # corner posts and edge frames
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(S.cube("post", size=(t * 1.6, t * 1.6, h), location=(sx * (w / 2 - t * 0.8), sy * (d / 2 - t * 0.8), 0), mat=dark))
    for p in parts:
        S.bevel(p, width=0.006, segments=2)
        S.jitter_verts(p, amount=0.003, scale=0.4, seed=rng.randrange(1000))
    return {"opaque_objs": parts, "collision": "convex", "materials_used": ["wood_planks"]}


# --- bucket ------------------------------------------------------------------------------

def bucket(pal, rng, params, variant):
    h = jit(rng, 0.32) * CHUNK
    r0 = jit(rng, 0.13) * CHUNK
    r1 = r0 * 1.22
    wood = M.wood_planks(pal, wear=0.6, age=0.6, plank_len=h * 2, plank_w=2 * math.pi * r0 / 14, along="Z")
    metal = M.iron(pal, age=0.6, wear=0.5)
    body = S.lathe("bucket_body", [(r0, 0.0), (r0, 0.02), (r0 * 0.9, 0.02), (r0 * 0.9, 0.035), (r0 + (r1 - r0) * 0.1, 0.035),
                                   (r1, h), (r1 - 0.012, h), (r0 + (r1 - r0) * 0.1 - 0.012, 0.035 + 0.012)],
                   segments=28, mat=wood, close=True)
    S.shade_smooth(body, 40.0)
    parts = [body]
    for t in (0.18, 0.82):
        rr = r0 + (r1 - r0) * t + 0.004
        hoop = S.torus("hoop", major=rr, minor=0.007, seg_major=28, seg_minor=6, location=(0, 0, t * h), mat=metal)
        hoop.scale = (1, 1, 2.0)
        S.apply_transforms(hoop)
        parts.append(hoop)
    # handle: rope-like arc of iron
    pts = []
    for i in range(13):
        a = math.pi * i / 12
        pts.append((math.cos(a) * (r1 + 0.005), 0.0, h + math.sin(a) * r1 * 0.9))
    handle = S.tube_along("handle", pts, radius=0.006, segments=6, mat=metal)
    parts.append(handle)
    return {"opaque_objs": parts, "collision": "convex", "materials_used": ["wood_planks", "iron"]}


KINDS = {
    "barrel": barrel,
    "crate": crate,
    "bucket": bucket,
}


if __name__ == "__main__":
    run_generator("Wickmere props generator", KINDS, "props", "gen_props")
