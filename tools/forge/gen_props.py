"""Props: the lived-in objects of Wickmere. Chunky but detailed.

    blender -b --python tools/forge/gen_props.py -- --kind barrel --palette hearthvale --seed 1

The rule from DESIGN §7.0 is "a barrel has staves and hoops": every prop is built from
real parts with modelled bevels, then given a little seeded asymmetry (jitter_verts, tilt,
per-part scale) so nothing reads as an extruded primitive. The palette decides the wood,
iron and cloth tones, so the same generator gives a Vale barrel or a Reedfolk one.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mathutils import Euler, Vector  # noqa: E402

from lib import build as B  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib.runner import run_generator  # noqa: E402

CHUNK = 1.1  # CONTRACTS §1: ~1.1x chunky stylisation on props
TAU = math.tau


def jit(rng, v, pct=0.06):
    return v * (1.0 + rng.uniform(-pct, pct))


def wood(pal, rng, wear=None, age=None, **kw):
    kw.setdefault("wear", wear if wear is not None else 0.35 + 0.4 * rng.random())
    kw.setdefault("age", age if age is not None else 0.3 + 0.45 * rng.random())
    return M.wood_planks(pal, **kw)


def iron(pal, rng, **kw):
    kw.setdefault("age", 0.4 + 0.45 * rng.random())
    kw.setdefault("wear", 0.45 + 0.35 * rng.random())
    return M.iron(pal, **kw)


def cloth(pal, rng, role="accent", **kw):
    kw.setdefault("age", 0.3 + 0.4 * rng.random())
    kw.setdefault("wear", 0.25 + 0.35 * rng.random())
    return M.dyed_cloth(pal, role=role, **kw)


def finish(parts, rng, collision="convex", materials=(), jitter=0.0, extra=None, tier=None):
    if jitter:
        for p in parts:
            S.jitter_verts(p, amount=jitter, scale=0.5, seed=rng.randrange(999))
    S.drop_to_ground(parts)
    spec = {"opaque_objs": parts, "collision": collision, "materials_used": list(materials)}
    if extra:
        spec["extra_meta"] = extra
    if tier:
        spec["tier"] = tier
    return spec


# =========================================================================================
# containers and vessels
# =========================================================================================

def barrel(pal, rng, params, variant):
    h = jit(rng, params.get("height", 0.9)) * CHUNK
    r = jit(rng, params.get("radius", 0.31)) * CHUNK
    bulge = params.get("bulge", 0.12) + rng.uniform(-0.02, 0.03)
    staves = int(params.get("staves", 18))
    w = wood(pal, rng, plank_len=h * 1.2, plank_w=2 * math.pi * r / staves, along="Z")
    metal = iron(pal, rng)
    prof = []
    n = 9
    for i in range(n + 1):
        t = i / n
        prof.append((r * (1.0 + bulge * math.sin(math.pi * t)), t * h))
    body = S.lathe("barrel_body", prof, segments=staves * 2, mat=w, close=False)
    # every second ring vertex pulled in a hair, so the staves read as separate boards
    for v in body.data.vertices:
        ang = math.atan2(v.co.y, v.co.x)
        if int(round((ang % TAU) / TAU * staves * 2)) % 2:
            v.co.x *= 0.985
            v.co.y *= 0.985
    S.shade_smooth(body, 40.0)
    inset = 0.035 * h
    parts = [body,
             S.cylinder("barrel_top", radius=r * 0.985, depth=0.03, vertices=staves * 2,
                        location=(0, 0, h - inset - 0.03), mat=w),
             S.cylinder("barrel_bot", radius=r * 0.985, depth=0.03, vertices=staves * 2,
                        location=(0, 0, inset), mat=w),
             S.cylinder("bung", radius=0.03, depth=0.02, vertices=12,
                        location=(r * 1.09, 0, h * 0.5), rotation=(0, 90, 0), mat=w)]
    for t in (0.12, 0.3, 0.7, 0.88):
        rr = r * (1.0 + bulge * math.sin(math.pi * t)) + 0.008
        parts.append(B.hoop("hoop", rr, 0.011, mat=metal, location=(0, 0, t * h), segments=staves * 2))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.004)


def crate(pal, rng, params, variant):
    w_ = jit(rng, params.get("width", 0.7)) * CHUNK
    d = jit(rng, params.get("depth", 0.7)) * CHUNK
    h = jit(rng, params.get("height", 0.6)) * CHUNK
    t = 0.028
    mat = wood(pal, rng, plank_len=w_, plank_w=0.14, along="X")
    dark = wood(pal, rng, plank_len=w_, plank_w=0.09, along="Z", base_hex="#6f5333", name="wood_frame")
    parts = []
    slats, gap = 4, 0.012
    sh = (h - gap * (slats + 1)) / slats
    for i in range(slats):
        z = gap + i * (sh + gap)
        parts += [S.cube("slat_f", (w_, t, sh), (0, -d / 2 + t / 2, z), mat=mat),
                  S.cube("slat_b", (w_, t, sh), (0, d / 2 - t / 2, z), mat=mat),
                  S.cube("slat_l", (t, d - 2 * t, sh), (-w_ / 2 + t / 2, 0, z), mat=mat),
                  S.cube("slat_r", (t, d - 2 * t, sh), (w_ / 2 - t / 2, 0, z), mat=mat)]
    parts += [S.cube("lid", (w_, d, t), (0, 0, h - t), mat=mat),
              S.cube("floor", (w_ - 2 * t, d - 2 * t, t), (0, 0, 0.0), mat=mat)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(S.cube("post", (t * 1.6, t * 1.6, h),
                                (sx * (w_ / 2 - t * 0.8), sy * (d / 2 - t * 0.8), 0), mat=dark))
    for p in parts:
        S.bevel(p, width=0.006, segments=2)
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.003)


def bucket(pal, rng, params, variant):
    h = jit(rng, 0.32) * CHUNK
    r0 = jit(rng, 0.13) * CHUNK
    r1 = r0 * 1.22
    w = wood(pal, rng, plank_len=h * 2, plank_w=2 * math.pi * r0 / 14, along="Z")
    metal = iron(pal, rng)
    body = S.lathe("bucket_body",
                   [(r0, 0.0), (r0, 0.02), (r0 * 0.9, 0.02), (r0 * 0.9, 0.035),
                    (r0 + (r1 - r0) * 0.1, 0.035), (r1, h), (r1 - 0.012, h),
                    (r0 + (r1 - r0) * 0.1 - 0.012, 0.047)], segments=28, mat=w)
    S.shade_smooth(body, 40.0)
    parts = [body]
    for t in (0.18, 0.82):
        parts.append(B.hoop("hoop", r0 + (r1 - r0) * t + 0.004, 0.007, mat=metal,
                            location=(0, 0, t * h), segments=28, flatten=2.0))
    pts = [(math.cos(math.pi * i / 12) * (r1 + 0.005), 0.0, h + math.sin(math.pi * i / 12) * r1 * 0.9)
           for i in range(13)]
    parts.append(S.tube_along("handle", pts, radius=0.006, segments=6, mat=metal))
    return finish(parts, rng, "convex", ["wood_planks", "iron"])


def sack(pal, rng, params, variant):
    """A slumped sack of grain: wider at the base, gathered and tied at the neck."""
    h = jit(rng, params.get("height", 0.62)) * CHUNK
    r = h * rng.uniform(0.30, 0.38)
    linen = M.canvas(pal, age=0.4 + 0.4 * rng.random(), wear=0.4, scale=0.5)
    cord = M.rope(pal, age=0.5, scale=0.15)
    prof = [(r * 0.86, 0.0), (r * 1.0, h * 0.12), (r * 1.03, h * 0.34), (r * 0.94, h * 0.55),
            (r * 0.74, h * 0.72), (r * 0.42, h * 0.84), (r * 0.20, h * 0.88),
            (r * 0.26, h * 0.95), (r * 0.30, h * 1.0), (r * 0.12, h * 1.03)]
    body = S.lathe("sack", prof, segments=20, mat=linen, close=True)
    # gathered folds: pinch the profile in a slow sine around the axis, stronger up top
    for v in body.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        f = 1.0 + 0.055 * math.cos(a * 7.0) * min(1.0, v.co.z / (h * 0.7))
        v.co.x *= f
        v.co.y *= f
    S.shade_smooth(body, 45.0)
    S.jitter_verts(body, amount=r * 0.04, scale=0.6, seed=rng.randrange(999))
    tie = B.rope_loop("tie", r * 0.27, 0.012, mat=cord, location=(0, 0, h * 0.90))
    return finish([body, tie], rng, "convex", ["canvas", "rope"])


def basket(pal, rng, params, variant):
    """Woven willow: uprights and a spiral weave, with a rolled rim."""
    h = jit(rng, params.get("height", 0.34)) * CHUNK
    r0 = jit(rng, 0.17) * CHUNK
    r1 = r0 * 1.3
    withy = M.wood_planks(pal, wear=0.4, age=0.5, base_hex="#b08a52", plank_len=2.0,
                          plank_w=0.03, name="withy")
    uprights = int(params.get("uprights", 15))
    parts = []
    for i in range(uprights):
        a = TAU * i / uprights
        pts = [(math.cos(a) * r0, math.sin(a) * r0, 0.0),
               (math.cos(a) * (r0 + r1) * 0.5, math.sin(a) * (r0 + r1) * 0.5, h * 0.5),
               (math.cos(a) * r1, math.sin(a) * r1, h)]
        parts.append(S.tube_along("up_%d" % i, pts, radius=0.006, segments=5, mat=withy))
    weaves = int(params.get("weaves", 9))
    for j in range(weaves):
        z = h * (j + 0.5) / weaves
        rr = r0 + (r1 - r0) * (z / h)
        pts = []
        steps = uprights * 4
        for k in range(steps + 1):
            t = k / steps
            a = TAU * t
            wob = math.sin(a * uprights + (j % 2) * math.pi) * 0.008
            pts.append(((rr + wob) * math.cos(a), (rr + wob) * math.sin(a), z + rng.uniform(-1, 1) * 0.002))
        parts.append(S.tube_along("weave_%d" % j, pts, radius=0.0055, segments=5, mat=withy, cap=False))
    parts.append(S.torus("rim", major=r1, minor=0.013, seg_major=uprights * 2, seg_minor=6,
                         location=(0, 0, h), mat=withy))
    parts.append(S.cylinder("base", radius=r0 * 0.98, depth=0.008, vertices=uprights, mat=withy))
    return finish(parts, rng, "convex", ["wood_planks"])


def chest(pal, rng, params, variant):
    w_ = jit(rng, params.get("width", 0.85)) * CHUNK
    d = jit(rng, 0.48) * CHUNK
    h = jit(rng, 0.46) * CHUNK
    body_h = h * 0.68
    lid_h = h - body_h
    mat = wood(pal, rng, plank_len=w_, plank_w=0.11, along="X")
    metal = iron(pal, rng, age=0.6)
    parts = B.plank_run("front", 4, w_, body_h / 4, 0.025, mat=mat, rng=rng, axis="X",
                        origin=(0, -d / 2, body_h / 2))
    for p in parts:
        p.rotation_euler = Euler((math.pi / 2, 0, 0))
        S.apply_transforms(p)
    parts = []
    t = 0.026
    parts += [S.cube("front", (w_, t, body_h), (0, -d / 2 + t / 2, 0), mat=mat),
              S.cube("back", (w_, t, body_h), (0, d / 2 - t / 2, 0), mat=mat),
              S.cube("left", (t, d - 2 * t, body_h), (-w_ / 2 + t / 2, 0, 0), mat=mat),
              S.cube("right", (t, d - 2 * t, body_h), (w_ / 2 - t / 2, 0, 0), mat=mat),
              S.cube("bottom", (w_ - 2 * t, d - 2 * t, t), (0, 0, 0), mat=mat)]
    # domed lid built from a lathe half-cylinder lying along X
    lid = S.lathe("lid", [(0.0, -d * 0.5), (lid_h * 0.82, -d * 0.42), (lid_h, -d * 0.1),
                          (lid_h, d * 0.1), (lid_h * 0.82, d * 0.42), (0.0, d * 0.5)],
                  segments=16, mat=mat, close=True)
    lid.rotation_euler = Euler((0, math.pi / 2, 0))
    S.apply_transforms(lid)
    lid.location = Vector((0, 0, body_h))
    S.apply_transforms(lid)
    # flatten the lower half of the dome so the lid sits flat on the box
    for v in lid.data.vertices:
        v.co.z = max(v.co.z, body_h)
    parts.append(lid)
    for p in parts:
        S.bevel(p, width=0.006, segments=2)
    for x in (-w_ * 0.3, w_ * 0.3):
        parts.append(B.iron_strap("strap", body_h + lid_h * 1.4, 0.05, 0.007, mat=metal,
                                  location=(x, -d / 2 - 0.004, body_h * 0.5), rotation=(90, 0, 90)))
    lock = S.cube("lock", (0.09, 0.02, 0.11), (0, -d / 2 - 0.012, body_h - 0.045), mat=metal)
    S.bevel(lock, width=0.008, segments=2)
    parts.append(lock)
    parts.append(S.cylinder("keyhole", radius=0.008, depth=0.03, vertices=8,
                            location=(0, -d / 2 - 0.02, body_h - 0.005), rotation=(90, 0, 0), mat=metal))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.003)


def cooking_pot(pal, rng, params, variant):
    r = jit(rng, params.get("radius", 0.19)) * CHUNK
    h = r * 1.5
    metal = iron(pal, rng, age=0.75, wear=0.5)
    body = S.lathe("pot", [(r * 0.52, 0.0), (r * 0.82, h * 0.12), (r, h * 0.42),
                           (r * 0.95, h * 0.72), (r * 0.86, h * 0.92), (r * 0.93, h),
                           (r * 0.84, h * 0.98), (r * 0.9, h * 0.7), (r * 0.72, h * 0.14),
                           (r * 0.46, 0.03)], segments=26, mat=metal, close=False)
    S.shade_smooth(body, 40.0)
    parts = [body]
    for sgn in (-1, 1):
        lug = S.sphere("lug_%d" % sgn, radius=r * 0.09, subdivisions=2,
                       location=(sgn * r * 0.93, 0, h * 0.86), mat=metal, scale=(1, 1.5, 1))
        S.apply_transforms(lug)
        parts.append(lug)
    pts = B.catenary((-r * 0.95, 0, h * 0.88), (r * 0.95, 0, h * 0.88), -r * 0.62, steps=14)
    parts.append(S.tube_along("bail", pts, radius=r * 0.035, segments=6, mat=metal))
    for i in range(3):
        a = TAU * i / 3
        parts.append(S.cylinder("foot_%d" % i, radius=r * 0.07, radius_top=r * 0.05, depth=r * 0.2,
                                vertices=7, location=(math.cos(a) * r * 0.36, math.sin(a) * r * 0.36, -r * 0.16),
                                mat=metal))
    return finish(parts, rng, "convex", ["iron"])


def _vessel(pal, rng, name, prof, segments, glaze_role="accent", handle=None, foot=None):
    mat = M.ceramic(pal, role=glaze_role, glaze=0.35 + 0.4 * rng.random(), age=0.3 + 0.4 * rng.random())
    body = S.lathe(name, prof, segments=segments, mat=mat, close=False)
    S.shade_smooth(body, 40.0)
    parts = [body]
    if handle:
        parts.append(S.tube_along("%s_handle" % name, handle, radius=prof[-1][0] * 0.09,
                                  segments=6, mat=mat))
    return parts, mat


def plate(pal, rng, params, variant):
    r = jit(rng, 0.11) * CHUNK
    prof = [(0.0, 0.0), (r * 0.34, 0.004), (r * 0.72, 0.012), (r * 0.94, 0.028), (r, 0.034),
            (r * 0.97, 0.030), (r * 0.9, 0.019), (r * 0.5, 0.008), (0.0, 0.006)]
    parts, _ = _vessel(pal, rng, "plate", prof, 24)
    return finish(parts, rng, "convex", ["ceramic"], jitter=0.0015)


def mug(pal, rng, params, variant):
    r = jit(rng, 0.045) * CHUNK
    h = r * 2.2
    prof = [(r * 0.86, 0.0), (r * 0.95, h * 0.08), (r, h * 0.5), (r * 1.02, h),
            (r * 0.9, h), (r * 0.88, h * 0.5), (r * 0.8, h * 0.08)]
    handle = B.catenary((r * 1.0, 0, h * 0.78), (r * 1.0, 0, h * 0.24), -r * 0.7, steps=10)
    handle = [(p.x + (0 if i in (0, len(handle) - 1) else r * 0.55), p.y, p.z) for i, p in enumerate(handle)]
    parts, _ = _vessel(pal, rng, "mug", prof, 18, handle=handle)
    return finish(parts, rng, "convex", ["ceramic"], jitter=0.0012)


def jug(pal, rng, params, variant):
    r = jit(rng, 0.085) * CHUNK
    h = r * 2.9
    prof = [(r * 0.5, 0.0), (r * 0.82, h * 0.08), (r, h * 0.32), (r * 0.88, h * 0.56),
            (r * 0.52, h * 0.76), (r * 0.42, h * 0.88), (r * 0.5, h), (r * 0.42, h * 0.98),
            (r * 0.34, h * 0.86), (r * 0.78, h * 0.56), (r * 0.9, h * 0.32), (r * 0.7, h * 0.09)]
    handle = B.catenary((r * 0.46, 0, h * 0.96), (r * 0.9, 0, h * 0.44), -r * 0.35, steps=10)
    handle = [(p.x + (0 if i in (0, len(handle) - 1) else r * 0.5), p.y, p.z) for i, p in enumerate(handle)]
    parts, mat = _vessel(pal, rng, "jug", prof, 20, handle=handle)
    # pinched spout
    top = parts[0]
    for v in top.data.vertices:
        if v.co.z > h * 0.93 and v.co.y < 0:
            v.co.y *= 1.35
            v.co.z += h * 0.03
    return finish(parts, rng, "convex", ["ceramic"], jitter=0.0015)


# =========================================================================================
# furniture
# =========================================================================================

def table_trestle(pal, rng, params, variant):
    """A plank top on trestle ends: the common hall table."""
    l = jit(rng, params.get("length", 1.9)) * CHUNK
    w_ = jit(rng, 0.78) * CHUNK
    h = 0.75 * CHUNK
    mat = wood(pal, rng, plank_len=l, plank_w=0.18, along="X")
    parts = B.plank_run("top", 4, l, w_ / 4, 0.038, mat=mat, rng=rng, sag=0.006,
                        origin=(0, 0, h - 0.019))
    for x in (-l * 0.34, l * 0.34):
        parts.append(S.cube("leg_l", (0.07, w_ * 0.82, h - 0.038), (x, 0, 0), mat=mat))
        parts.append(S.cube("foot", (0.1, w_ * 0.95, 0.055), (x, 0, 0), mat=mat))
        parts.append(S.cube("cap", (0.1, w_ * 0.7, 0.045), (x, 0, h - 0.083), mat=mat))
    parts.append(S.cube("stretcher", (l * 0.74, 0.06, 0.08), (0, 0, h * 0.30), mat=mat))
    for p in parts:
        S.bevel(p, width=0.007, segments=2)
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.003)


def table_round(pal, rng, params, variant):
    r = jit(rng, params.get("radius", 0.48)) * CHUNK
    h = 0.74 * CHUNK
    mat = wood(pal, rng, plank_len=r * 2, plank_w=0.16, along="X")
    top = S.cylinder("top", radius=r, depth=0.04, vertices=28, location=(0, 0, h - 0.04), mat=mat)
    S.bevel(top, width=0.008, segments=2)
    parts = [top, B.turned_leg("pillar", h - 0.04, r * 0.16, mat=mat, rng=rng, rings=4)]
    for i in range(3):
        a = TAU * i / 3 + rng.uniform(-0.1, 0.1)
        foot = S.cube("foot_%d" % i, (r * 0.62, 0.06, 0.05), (0, 0, 0), rotation=(0, 0, math.degrees(a)), mat=mat)
        foot.location = Vector((math.cos(a) * r * 0.31, math.sin(a) * r * 0.31, 0))
        S.apply_transforms(foot)
        S.bevel(foot, width=0.008, segments=2)
        parts.append(foot)
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.003)


def stool(pal, rng, params, variant):
    h = jit(rng, 0.46) * CHUNK
    r = jit(rng, 0.16) * CHUNK
    mat = wood(pal, rng, plank_len=0.4, plank_w=0.12, along="X")
    seat = S.cylinder("seat", radius=r, depth=0.035, vertices=18, location=(0, 0, h - 0.035), mat=mat)
    S.bevel(seat, width=0.009, segments=2)
    parts = [seat]
    for i in range(3):
        a = TAU * i / 3 + rng.uniform(-0.12, 0.12)
        x, y = math.cos(a) * r * 0.62, math.sin(a) * r * 0.62
        leg = S.cylinder("leg_%d" % i, radius=0.024, radius_top=0.018, depth=h - 0.035,
                         vertices=8, location=(x, y, 0), mat=mat)
        leg.rotation_euler = Euler((math.radians(math.sin(a) * 8), math.radians(-math.cos(a) * 8), 0))
        S.apply_transforms(leg)
        leg.location = Vector((x, y, 0))
        S.apply_transforms(leg)
        parts.append(leg)
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.002)


def chair(pal, rng, params, variant):
    seat_h = 0.46 * CHUNK
    w_ = jit(rng, 0.42) * CHUNK
    d = jit(rng, 0.40) * CHUNK
    back_h = jit(rng, 0.52) * CHUNK
    mat = wood(pal, rng, plank_len=0.5, plank_w=0.1, along="X")
    parts = [S.cube("seat", (w_, d, 0.032), (0, 0, seat_h - 0.032), mat=mat)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (w_ / 2 - 0.035), sy * (d / 2 - 0.035)
            hh = seat_h - 0.032 if sy < 0 else seat_h + back_h - 0.032
            parts.append(B.turned_leg("leg", hh, 0.021, mat=mat, location=(x, y, 0), rings=2, rng=rng))
    for z in (0.62, 0.86):
        parts.append(S.cube("splat", (w_ - 0.08, 0.02, 0.07),
                            (0, d / 2 - 0.035, seat_h + back_h * z), mat=mat))
    parts.append(S.cube("crest", (w_ - 0.02, 0.028, 0.055), (0, d / 2 - 0.035, seat_h + back_h - 0.055), mat=mat))
    for sy in (-1, 1):
        parts.append(S.cube("rung", (w_ - 0.08, 0.02, 0.02), (0, sy * (d / 2 - 0.035), seat_h * 0.36), mat=mat))
    for p in parts:
        if p.name.startswith(("seat", "splat", "crest", "rung")):
            S.bevel(p, width=0.005, segments=2)
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.002)


def bench(pal, rng, params, variant):
    l = jit(rng, params.get("length", 1.6)) * CHUNK
    w_ = jit(rng, 0.34) * CHUNK
    h = 0.45 * CHUNK
    mat = wood(pal, rng, plank_len=l, plank_w=0.17, along="X")
    parts = B.plank_run("seat", 2, l, w_ / 2, 0.042, mat=mat, rng=rng, sag=0.005, origin=(0, 0, h - 0.021))
    for x in (-l * 0.36, l * 0.36):
        slab = S.cube("end", (0.055, w_ * 0.9, h - 0.042), (x, 0, 0), mat=mat)
        S.bevel(slab, width=0.008, segments=2)
        parts.append(slab)
    parts.append(S.cube("brace", (l * 0.8, 0.045, 0.06), (0, 0, h * 0.3), mat=mat))
    return finish(parts, rng, "convex", ["wood_planks"], jitter=0.003)


def bed(pal, rng, params, variant):
    l = jit(rng, 1.95) * CHUNK
    w_ = jit(rng, 0.95) * CHUNK
    h = 0.42 * CHUNK
    mat = wood(pal, rng, plank_len=l, plank_w=0.14, along="X")
    linen = M.canvas(pal, age=0.35, wear=0.3, scale=0.6)
    blanket = cloth(pal, rng, role="accent", scale=0.5)
    t = 0.05
    parts = [S.cube("rail_l", (l, t, h * 0.55), (0, -w_ / 2 + t / 2, h * 0.32), mat=mat),
             S.cube("rail_r", (l, t, h * 0.55), (0, w_ / 2 - t / 2, h * 0.32), mat=mat),
             S.cube("head", (t, w_, h * 1.35), (-l / 2 + t / 2, 0, 0), mat=mat),
             S.cube("foot", (t, w_, h * 0.75), (l / 2 - t / 2, 0, 0), mat=mat)]
    for p in parts:
        S.bevel(p, width=0.008, segments=2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(B.turned_leg("leg", h * 0.35, 0.035, mat=mat,
                                      location=(sx * (l / 2 - 0.06), sy * (w_ / 2 - 0.06), 0),
                                      rings=1, rng=rng))
    # mattress: a sagging sack of straw
    mattress = S.box_centered("mattress", (l - 0.1, w_ - 0.09, h * 0.36),
                              (0, 0, h * 0.32 + h * 0.18), mat=linen)
    S.bevel(mattress, width=h * 0.12, segments=3, angle_deg=50)
    S.jitter_verts(mattress, amount=0.012, scale=0.8, seed=rng.randrange(999))
    parts.append(mattress)
    top_z = h * 0.32 + h * 0.36
    cover = S.box_centered("blanket", (l * 0.62, w_ - 0.06, h * 0.1), (l * 0.16, 0, top_z + h * 0.02), mat=blanket)
    S.bevel(cover, width=h * 0.04, segments=3, angle_deg=50)
    S.jitter_verts(cover, amount=0.014, scale=0.5, seed=rng.randrange(999))
    parts.append(cover)
    pillow = S.box_centered("pillow", (0.34, w_ * 0.5, h * 0.17), (-l * 0.34, 0, top_z + h * 0.04), mat=linen)
    S.bevel(pillow, width=h * 0.07, segments=3, angle_deg=55)
    S.jitter_verts(pillow, amount=0.01, scale=0.4, seed=rng.randrange(999))
    parts.append(pillow)
    return finish(parts, rng, "convex", ["wood_planks", "canvas", "dyed_cloth"])


def shelf(pal, rng, params, variant):
    w_ = jit(rng, 1.1) * CHUNK
    d = jit(rng, 0.26) * CHUNK
    h = jit(rng, 0.95) * CHUNK
    mat = wood(pal, rng, plank_len=w_, plank_w=0.13, along="X")
    metal = iron(pal, rng)
    parts = []
    for i, z in enumerate((0.12, 0.48, 0.86)):
        parts.append(board("shelf_%d" % i, w_, d, 0.028, mat=mat, location=(0, 0, h * z),
                           sag=0.004 * (3 - i), rng=rng) if False else
                     B.board("shelf_%d" % i, w_, d, 0.028, mat=mat, location=(0, 0, h * z),
                             sag=0.004 * (3 - i), rng=rng))
    for x in (-w_ * 0.42, w_ * 0.42):
        parts.append(S.cube("upright", (0.035, d, h), (x, 0, 0), mat=mat))
    for x in (-w_ * 0.42, w_ * 0.42):
        for z in (0.12, 0.86):
            parts.append(B.iron_strap("bracket", d * 0.8, 0.03, 0.005, mat=metal,
                                      location=(x, 0, h * z - 0.02), rotation=(0, 0, 90)))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.002)


def cupboard(pal, rng, params, variant):
    w_ = jit(rng, 0.95) * CHUNK
    d = jit(rng, 0.42) * CHUNK
    h = jit(rng, 1.65) * CHUNK
    mat = wood(pal, rng, plank_len=h, plank_w=0.15, along="Z")
    metal = iron(pal, rng, age=0.6)
    t = 0.03
    parts = [S.cube("side_l", (t, d, h), (-w_ / 2 + t / 2, 0, 0), mat=mat),
             S.cube("side_r", (t, d, h), (w_ / 2 - t / 2, 0, 0), mat=mat),
             S.cube("back", (w_ - 2 * t, t, h), (0, d / 2 - t / 2, 0), mat=mat),
             S.cube("top", (w_, d, t), (0, 0, h - t), mat=mat),
             S.cube("base", (w_, d, t * 1.6), (0, 0, 0), mat=mat)]
    for z in (0.34, 0.63):
        parts.append(S.cube("inner_shelf", (w_ - 2 * t, d - t, 0.022), (0, 0, h * z), mat=mat))
    door_w = (w_ - 2 * t) * 0.5 - 0.004
    for sx in (-1, 1):
        door = S.cube("door_%d" % sx, (door_w, 0.026, h * 0.62),
                      (sx * (door_w * 0.5 + 0.004), -d / 2 + 0.013, h * 0.3), mat=mat)
        S.bevel(door, width=0.006, segments=2)
        parts.append(door)
        for z in (0.36, 0.78):
            parts.append(B.iron_strap("hinge", door_w * 0.55, 0.028, 0.005, mat=metal,
                                      location=(sx * (door_w * 0.72), -d / 2 - 0.002, h * z),
                                      rotation=(90, 0, 0)))
        parts.append(S.sphere("knob_%d" % sx, radius=0.018, subdivisions=2,
                              location=(sx * 0.02, -d / 2 - 0.018, h * 0.56), mat=metal))
    for p in parts:
        if p.name.startswith(("side", "top", "base")):
            S.bevel(p, width=0.006, segments=2)
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.002)


# =========================================================================================
# light and fire
# =========================================================================================

def candle(pal, rng, params, variant):
    h = jit(rng, 0.16) * CHUNK
    r = 0.017 * CHUNK
    wax = M.wax(pal)
    body = S.lathe("candle", [(r, 0.0), (r * 1.02, h * 0.3), (r * 0.96, h * 0.72),
                              (r * 0.88, h * 0.9), (r * 0.5, h * 0.97), (r * 0.2, h)],
                   segments=14, mat=wax, close=True)
    S.shade_smooth(body, 45.0)
    # a run of wax down one side
    for v in body.data.vertices:
        if math.atan2(v.co.y, v.co.x) > 1.8 and v.co.z < h * 0.75:
            v.co.x *= 1.12
            v.co.y *= 1.12
    wick = S.cylinder("wick", radius=0.0016, depth=h * 0.07, vertices=5, location=(0, 0, h),
                      mat=M.soot(pal))
    return finish([body, wick], rng, "none", ["wax"])


def candlestick(pal, rng, params, variant):
    h = jit(rng, 0.19) * CHUNK
    metal = M.brass(pal, age=0.5 + 0.3 * rng.random(), wear=0.5, scale=0.1)
    wax = M.wax(pal)
    base_r = h * 0.28
    stick = S.lathe("stick", [(base_r, 0.0), (base_r * 0.95, h * 0.03), (base_r * 0.55, h * 0.07),
                              (base_r * 0.3, h * 0.13), (base_r * 0.22, h * 0.32),
                              (base_r * 0.38, h * 0.42), (base_r * 0.2, h * 0.52),
                              (base_r * 0.24, h * 0.72), (base_r * 0.5, h * 0.80),
                              (base_r * 0.42, h * 0.86), (base_r * 0.22, h * 0.88),
                              (base_r * 0.20, h)], segments=18, mat=metal, close=True)
    S.shade_smooth(stick, 40.0)
    cand = S.lathe("cand", [(base_r * 0.17, h), (base_r * 0.17, h * 1.55), (base_r * 0.1, h * 1.62)],
                   segments=12, mat=wax, close=True)
    wick = S.cylinder("wick", radius=0.0016, depth=h * 0.05, vertices=5, location=(0, 0, h * 1.62),
                      mat=M.soot(pal))
    return finish([stick, cand, wick], rng, "convex", ["brass", "wax"])


def _lantern_body(pal, rng, h, metal, glass, panes=4):
    parts = []
    r = h * 0.26
    parts.append(S.lathe("lan_base", [(r * 1.05, 0.0), (r * 0.95, h * 0.04), (r * 0.8, h * 0.07)],
                         segments=panes * 3, mat=metal, close=True))
    for i in range(panes):
        a = TAU * i / panes + math.pi / panes
        post = S.cube("post_%d" % i, (h * 0.02, h * 0.02, h * 0.56), (0, 0, h * 0.07),
                      rotation=(0, 0, math.degrees(a)), mat=metal)
        post.location = Vector((math.cos(a) * r * 0.76, math.sin(a) * r * 0.76, h * 0.07))
        S.apply_transforms(post)
        parts.append(post)
    pane = S.lathe("panes", [(r * 0.72, h * 0.08), (r * 0.72, h * 0.62)], segments=panes * 4,
                   mat=glass, close=False)
    parts.append(pane)
    parts.append(S.lathe("lan_roof", [(r * 1.15, h * 0.63), (r * 1.0, h * 0.70),
                                      (r * 0.55, h * 0.82), (r * 0.15, h * 0.88)],
                         segments=panes * 3, mat=metal, close=False))
    flame = S.sphere("flame", radius=r * 0.3, subdivisions=2, location=(0, 0, h * 0.3),
                     mat=M.ember(pal, heat=1.6, name="lantern_flame"), scale=(1, 1, 1.5))
    S.apply_transforms(flame)
    parts.append(flame)
    return parts, r


def lantern_hanging(pal, rng, params, variant):
    h = jit(rng, 0.34) * CHUNK
    metal = iron(pal, rng, age=0.65)
    glass = M.glass(pal)
    parts, r = _lantern_body(pal, rng, h, metal, glass)
    ring = S.torus("ring", major=r * 0.22, minor=h * 0.013, seg_major=16, seg_minor=6,
                   location=(0, 0, h * 0.98), rotation=(90, 0, 0), mat=metal)
    parts.append(ring)
    parts.append(S.cylinder("stem", radius=h * 0.012, depth=h * 0.12, vertices=7,
                            location=(0, 0, h * 0.86), mat=metal))
    return finish(parts, rng, "none", ["iron", "glass"], extra={"hangs": True, "emissive": True})


def lantern_standing(pal, rng, params, variant):
    h = jit(rng, 1.9) * CHUNK
    metal = M.brass(pal, age=0.6, wear=0.5, scale=0.08)
    glass = M.glass(pal)
    lan_h = h * 0.26
    parts, r = _lantern_body(pal, rng, lan_h, metal, glass)
    for p in parts:
        p.location.z += h - lan_h
        S.apply_transforms(p)
    post = S.lathe("post", [(h * 0.055, 0.0), (h * 0.05, h * 0.02), (h * 0.026, h * 0.06),
                            (h * 0.022, h * 0.5), (h * 0.028, h * 0.72),
                            (h * 0.022, h * 0.74), (h * 0.03, h - lan_h)],
                   segments=12, mat=metal, close=True)
    S.shade_smooth(post, 40.0)
    parts.append(post)
    return finish(parts, rng, "capsule", ["brass", "glass"], extra={"emissive": True})


def brazier(pal, rng, params, variant):
    h = jit(rng, 0.85) * CHUNK
    r = h * 0.33
    metal = iron(pal, rng, age=0.8, wear=0.6)
    bowl = S.lathe("bowl", [(r * 0.3, h * 0.6), (r * 0.7, h * 0.7), (r, h * 0.92), (r * 1.06, h),
                            (r * 0.96, h), (r * 0.9, h * 0.72), (r * 0.26, h * 0.63)],
                   segments=20, mat=metal, close=False)
    S.shade_smooth(bowl, 40.0)
    parts = [bowl]
    for i in range(3):
        a = TAU * i / 3
        leg = S.cylinder("leg_%d" % i, radius=h * 0.03, radius_top=h * 0.02, depth=h * 0.66,
                         vertices=7, location=(math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, 0),
                         rotation=(math.degrees(math.sin(a)) * 0.2, 0, 0), mat=metal)
        leg.rotation_euler = Euler((math.radians(math.sin(a) * 12), math.radians(-math.cos(a) * 12), 0))
        S.apply_transforms(leg)
        leg.location = Vector((math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, 0))
        S.apply_transforms(leg)
        parts.append(leg)
    parts.append(B.hoop("tie", r * 0.56, h * 0.015, mat=metal, location=(0, 0, h * 0.24), segments=18))
    coals = S.uv_sphere("coals", radius=r * 0.86, segments=18, rings=9, location=(0, 0, h * 0.86),
                        mat=M.ember(pal, heat=1.2, name="brazier_coals"), scale=(1, 1, 0.34))
    S.apply_transforms(coals)
    S.jitter_verts(coals, amount=r * 0.06, scale=0.4, seed=rng.randrange(999))
    parts.append(coals)
    return finish(parts, rng, "convex", ["iron", "ember"], extra={"emissive": True})


def chandelier(pal, rng, params, variant):
    r = jit(rng, 0.42) * CHUNK
    metal = iron(pal, rng, age=0.7)
    wax = M.wax(pal)
    parts = [B.hoop("ring", r, r * 0.035, mat=metal, segments=30, flatten=1.6, location=(0, 0, 0)),
             B.hoop("ring2", r * 0.62, r * 0.028, mat=metal, segments=26, flatten=1.6,
                    location=(0, 0, r * 0.26))]
    arms = int(params.get("arms", 6))
    for i in range(arms):
        a = TAU * i / arms
        x, y = math.cos(a) * r, math.sin(a) * r
        cup = S.lathe("cup_%d" % i, [(r * 0.09, 0.0), (r * 0.07, r * 0.03), (r * 0.045, r * 0.05)],
                      segments=10, mat=metal, close=True)
        cup.location = Vector((x, y, r * 0.02))
        S.apply_transforms(cup)
        parts.append(cup)
        c = S.cylinder("cand_%d" % i, radius=r * 0.035, radius_top=r * 0.030, depth=r * 0.4,
                       vertices=9, location=(x, y, r * 0.06), mat=wax)
        parts.append(c)
    for i in range(3):
        a = TAU * i / 3
        pts = B.catenary((math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, r * 0.24),
                         (0, 0, r * 1.15), -r * 0.05, steps=6)
        parts.append(S.tube_along("chain_%d" % i, pts, radius=r * 0.016, segments=5, mat=metal))
    parts.append(B.hoop("top_ring", r * 0.1, r * 0.02, mat=metal, segments=14, location=(0, 0, r * 1.18)))
    return finish(parts, rng, "none", ["iron", "wax"], extra={"hangs": True})


def campfire(pal, rng, params, variant):
    r = jit(rng, 0.52) * CHUNK
    stone = M.granite(pal, wear=0.5, age=0.6, scale=0.4)
    logs_mat = M.wood_planks(pal, wear=0.7, age=0.8, base_hex="#6a4e32", plank_len=0.8,
                             plank_w=0.08, along="X", name="firewood")
    parts = []
    n = int(params.get("stones", 9))
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.15, 0.15)
        rr = r * rng.uniform(0.9, 1.08)
        st = S.sphere("stone_%d" % i, radius=r * rng.uniform(0.13, 0.2), subdivisions=2,
                      location=(math.cos(a) * rr, math.sin(a) * rr, 0), mat=stone,
                      scale=(1.0, rng.uniform(0.7, 1.0), rng.uniform(0.6, 0.85)))
        S.apply_transforms(st)
        S.jitter_verts(st, amount=r * 0.02, scale=0.4, seed=rng.randrange(999))
        S.tilt(st, rng, max_deg=25)
        parts.append(st)
    for i in range(int(params.get("logs", 5))):
        a = TAU * i / 5 + rng.uniform(-0.2, 0.2)
        ln = r * rng.uniform(1.0, 1.35)
        log = S.cylinder("log_%d" % i, radius=r * rng.uniform(0.07, 0.1), depth=ln, vertices=8,
                         location=(0, 0, 0), rotation=(0, 74 + rng.uniform(-10, 10), math.degrees(a)),
                         mat=logs_mat, centered=True)
        log.location = Vector((math.cos(a) * r * 0.28, math.sin(a) * r * 0.28, r * 0.16))
        S.apply_transforms(log)
        parts.append(log)
    coals = S.uv_sphere("coals", radius=r * 0.4, segments=16, rings=8, location=(0, 0, r * 0.06),
                        mat=M.ember(pal, heat=1.5, name="campfire_coals"), scale=(1, 1, 0.45))
    S.apply_transforms(coals)
    parts.append(coals)
    return finish(parts, rng, "trimesh", ["granite", "wood_planks", "ember"],
                  extra={"emissive": True})


# =========================================================================================
# work
# =========================================================================================

def anvil(pal, rng, params, variant):
    l = jit(rng, 0.62) * CHUNK
    h = jit(rng, 0.32) * CHUNK
    metal = iron(pal, rng, age=0.6, wear=0.75)
    wood_mat = wood(pal, rng, age=0.8, plank_len=0.5, plank_w=0.3, along="Z")
    body = S.box_centered("body", (l * 0.52, l * 0.22, h * 0.34), (0, 0, h * 0.78), mat=metal)
    S.bevel(body, width=h * 0.03, segments=2)
    waist = S.box_centered("waist", (l * 0.3, l * 0.16, h * 0.3), (0, 0, h * 0.5), mat=metal)
    S.bevel(waist, width=h * 0.05, segments=2)
    foot = S.box_centered("foot", (l * 0.44, l * 0.24, h * 0.22), (0, 0, h * 0.26), mat=metal)
    S.bevel(foot, width=h * 0.04, segments=2)
    horn = S.cylinder("horn", radius=l * 0.1, radius_top=l * 0.015, depth=l * 0.3, vertices=14,
                      location=(-l * 0.26, 0, h * 0.78), rotation=(0, -90, 0), mat=metal)
    heel = S.box_centered("heel", (l * 0.16, l * 0.2, h * 0.3), (l * 0.3, 0, h * 0.76), mat=metal)
    S.bevel(heel, width=h * 0.03, segments=2)
    hardy = S.cube("hardy", (0.028, 0.028, h * 0.1), (l * 0.2, 0, h * 0.9), mat=metal)
    stump = S.lathe("stump", [(l * 0.3, 0.0), (l * 0.28, h * 0.08), (l * 0.26, h * 0.15)],
                    segments=12, mat=wood_mat, close=True)
    parts = [body, waist, foot, horn, heel, hardy, stump]
    return finish(parts, rng, "convex", ["iron", "wood_planks"], jitter=0.002)


def forge_hearth(pal, rng, params, variant):
    w_ = jit(rng, 1.5) * CHUNK
    d = jit(rng, 0.95) * CHUNK
    h = jit(rng, 0.82) * CHUNK
    stone = M.stone_blocks(pal, wear=0.55, age=0.7, scale=0.6, block_w=0.4, block_h=0.2)
    sooty = M.soot(pal)
    metal = iron(pal, rng, age=0.85)
    parts = []
    parts += B.stone_course("hearth", w_, h, d, mat=stone, rows=4, rng=rng)
    top = S.box_centered("top", (w_ * 1.02, d * 1.02, 0.06), (0, 0, h + 0.03), mat=stone)
    S.bevel(top, width=0.012, segments=2)
    parts.append(top)
    fire_r = min(w_, d) * 0.3
    pit = S.uv_sphere("pit", radius=fire_r, segments=18, rings=9, location=(0, 0, h + 0.06),
                      mat=sooty, scale=(1.35, 1.0, 0.42))
    S.apply_transforms(pit)
    parts.append(pit)
    coals = S.uv_sphere("coals", radius=fire_r * 0.72, segments=16, rings=8,
                        location=(0, 0, h + 0.07), mat=M.ember(pal, heat=2.0, name="forge_coals"),
                        scale=(1.3, 0.95, 0.3))
    S.apply_transforms(coals)
    parts.append(coals)
    hood = S.lathe("hood", [(w_ * 0.44, h + 0.62), (w_ * 0.4, h + 0.68), (w_ * 0.16, h + 1.0),
                            (w_ * 0.13, h + 1.15)], segments=14, mat=metal, close=False)
    parts.append(hood)
    for x in (-w_ * 0.4, w_ * 0.4):
        parts.append(S.cylinder("hood_post", radius=0.028, depth=0.62, vertices=8,
                                location=(x, 0, h + 0.06), mat=metal))
    return finish(parts, rng, "col_glb", ["stone_blocks", "iron", "ember"],
                  extra={"emissive": True})


def alembic(pal, rng, params, variant):
    h = jit(rng, 0.46) * CHUNK
    glass = M.glass(pal)
    metal = M.brass(pal, age=0.5, wear=0.5, scale=0.06)
    r = h * 0.26
    flask = S.lathe("flask", [(r * 0.28, 0.0), (r * 0.7, h * 0.08), (r, h * 0.26),
                              (r * 0.88, h * 0.44), (r * 0.36, h * 0.56), (r * 0.28, h * 0.62)],
                    segments=20, mat=glass, close=True)
    S.shade_smooth(flask, 40.0)
    head = S.lathe("head", [(r * 0.30, h * 0.62), (r * 0.62, h * 0.7), (r * 0.56, h * 0.82),
                            (r * 0.2, h * 0.92), (r * 0.1, h * 0.96)], segments=18, mat=glass, close=True)
    S.shade_smooth(head, 40.0)
    spout_pts = [(r * 0.5, 0, h * 0.74), (r * 1.2, 0, h * 0.66), (r * 1.7, 0, h * 0.42),
                 (r * 1.75, 0, h * 0.22)]
    spout = S.tube_along("spout", spout_pts, radius=r * 0.07, segments=7, mat=glass)
    stand = S.lathe("stand", [(r * 1.15, 0.0), (r * 1.1, h * 0.03), (r * 0.55, h * 0.06)],
                    segments=16, mat=metal, close=True)
    parts = [flask, head, spout, stand]
    for i in range(3):
        a = TAU * i / 3
        parts.append(S.cylinder("leg_%d" % i, radius=r * 0.05, depth=h * 0.1, vertices=6,
                                location=(math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, 0), mat=metal))
    return finish(parts, rng, "convex", ["glass", "brass"])


def rope_coil(pal, rng, params, variant):
    r = jit(rng, 0.26) * CHUNK
    cord = M.rope(pal, age=0.45 + 0.3 * rng.random(), scale=0.25, axis="Z")
    parts = []
    turns = int(params.get("turns", 4))
    for i in range(turns):
        rr = r * (1.0 - 0.10 * i)
        parts.append(B.rope_loop("coil_%d" % i, rr, 0.021, mat=cord, segments=30,
                                 location=(0, 0, 0.042 * i + 0.02), rng=rng))
    for p in parts:
        S.tilt(p, rng, max_deg=3)
    # a loose end trailing off the pile
    end = [(r * 0.95, 0, 0.042 * turns), (r * 1.35, r * 0.25, 0.03), (r * 1.7, r * 0.6, 0.018)]
    parts.append(S.tube_along("end", end, radius=0.021, segments=7, mat=cord))
    return finish(parts, rng, "convex", ["rope"])


def wheelbarrow(pal, rng, params, variant):
    l = jit(rng, 1.4) * CHUNK
    w_ = jit(rng, 0.6) * CHUNK
    mat = wood(pal, rng, plank_len=l, plank_w=0.12, along="X")
    metal = iron(pal, rng, age=0.7)
    parts = []
    tray_h = 0.26
    parts += B.plank_run("tray", 4, l * 0.52, w_ / 4, 0.022, mat=mat, rng=rng, origin=(0, 0, 0.38))
    for sy in (-1, 1):
        side = S.cube("side_%d" % sy, (l * 0.52, 0.022, tray_h),
                      (0, sy * w_ / 2, 0.38), rotation=(sy * -14, 0, 0), mat=mat)
        S.bevel(side, width=0.005, segments=2)
        parts.append(side)
    parts.append(S.cube("front", (0.022, w_ * 0.92, tray_h), (-l * 0.26, 0, 0.38), mat=mat))
    parts.append(S.cube("back", (0.022, w_ * 0.92, tray_h * 0.7), (l * 0.26, 0, 0.38), mat=mat))
    for sy in (-1, 1):
        parts.append(S.cube("handle_%d" % sy, (l, 0.045, 0.045),
                            (l * 0.1, sy * w_ * 0.38, 0.36), rotation=(0, -4, 0), mat=mat))
        parts.append(S.cube("leg_%d" % sy, (0.04, 0.04, 0.36), (l * 0.4, sy * w_ * 0.38, 0), mat=mat))
    wheel_r = 0.26
    wheel = S.cylinder("wheel", radius=wheel_r, depth=0.06, vertices=18,
                       location=(-l * 0.46, 0, wheel_r), rotation=(90, 0, 0), mat=mat, centered=True)
    parts.append(wheel)
    parts.append(B.hoop("tyre", wheel_r * 1.02, 0.03, mat=metal, location=(-l * 0.46, 0, wheel_r),
                        segments=22, flatten=1.4, rotation=(90, 0, 0)))
    parts.append(S.cylinder("axle", radius=0.018, depth=w_ * 0.5, vertices=8,
                            location=(-l * 0.46, -w_ * 0.25, wheel_r), rotation=(-90, 0, 0), mat=metal))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.003)


def cart(pal, rng, params, variant):
    l = jit(rng, 2.4) * CHUNK
    w_ = jit(rng, 1.25) * CHUNK
    mat = wood(pal, rng, plank_len=l, plank_w=0.15, along="X")
    metal = iron(pal, rng, age=0.7)
    wheel_r = 0.55 * CHUNK
    bed_z = wheel_r * 0.98
    parts = B.plank_run("bed", 6, l * 0.8, w_ / 6, 0.032, mat=mat, rng=rng, sag=0.004,
                        origin=(0, 0, bed_z))
    # Sides that read as sides. A 30 cm rail on a 2.4 m cart is a lip, and from across a
    # village square the whole thing looked like a shallow trough; a board, a capping rail
    # on posts above it and a headboard give it a body the eye can name.
    side_h = 0.46
    for sy in (-1, 1):
        parts.append(S.cube("board_%d" % sy, (l * 0.8, 0.035, side_h),
                            (0, sy * w_ / 2, bed_z + 0.016), mat=mat))
        parts.append(S.cube("cap_%d" % sy, (l * 0.84, 0.075, 0.06),
                            (0, sy * w_ / 2, bed_z + side_h + 0.016), mat=mat))
        parts.append(S.cube("beam_%d" % sy, (l * 0.86, 0.09, 0.09),
                            (0, sy * w_ * 0.36, bed_z - 0.06), mat=mat))
        for k in range(3):
            px = (k - 1) * l * 0.28
            parts.append(S.cube("stake_%d_%d" % (sy, k), (0.06, 0.06, side_h + 0.05),
                                (px, sy * (w_ / 2 + 0.03), bed_z + 0.016), mat=mat))
    parts.append(S.cube("head", (0.04, w_ * 0.96, side_h + 0.12), (-l * 0.4, 0, bed_z + 0.016), mat=mat))
    parts.append(S.cube("tail", (0.04, w_ * 0.96, side_h * 0.8), (l * 0.4, 0, bed_z + 0.016), mat=mat))
    for sy in (-1, 1):
        cx = l * 0.12
        hub = S.cylinder("hub_%d" % sy, radius=wheel_r * 0.17, depth=0.12, vertices=12,
                         location=(cx, sy * (w_ / 2 + 0.05), wheel_r), rotation=(90, 0, 0),
                         mat=mat, centered=True)
        parts.append(hub)
        # The felloe is the rim the cart actually stands on and it has to be thick enough to
        # read from ten metres; at wheel_r * 0.09, flattened, it vanished and left the iron
        # tyre looking like a bare hoop.
        parts.append(B.hoop("felloe_%d" % sy, wheel_r * 0.86, wheel_r * 0.15, mat=mat,
                            location=(cx, sy * (w_ / 2 + 0.05), wheel_r), segments=20, flatten=1.0,
                            rotation=(90, 0, 0)))
        parts.append(B.hoop("tyre_%d" % sy, wheel_r, wheel_r * 0.055, mat=metal,
                            location=(cx, sy * (w_ / 2 + 0.05), wheel_r), segments=26, flatten=1.3,
                            rotation=(90, 0, 0)))
        for k in range(8):
            a = TAU * k / 8 + rng.uniform(-0.05, 0.05)
            # Lay the spoke along X, spin it in the wheel's plane, and only then move it out
            # to the hub. Spinning the vertices after the transform had been applied turned
            # them about the world origin instead, which threw all sixteen spokes onto the
            # ground beside the cart -- the loose sticks under the axle.
            spoke = S.cylinder("spoke", radius=wheel_r * 0.06, depth=wheel_r * 0.8, vertices=6,
                               location=(0, 0, 0), mat=mat, centered=True)
            # Push it out along its own axis first, so it runs hub to felloe rather than
            # straddling the axle and stopping halfway to the rim.
            for v in spoke.data.vertices:
                v.co.z += wheel_r * 0.5
            spoke.rotation_euler = Euler((0, math.pi / 2 + a, 0), "XYZ")
            S.apply_transforms(spoke)
            spoke.location = Vector((cx, sy * (w_ / 2 + 0.05), wheel_r))
            S.apply_transforms(spoke)
            parts.append(spoke)
    parts.append(S.cylinder("axle", radius=0.05, depth=w_ + 0.18, vertices=10,
                            location=(l * 0.12, -(w_ / 2 + 0.09), wheel_r), rotation=(-90, 0, 0), mat=mat))
    # Shafts run forward and level, to where a horse would stand, and they are long enough
    # to say so. They used to drop towards the ground over half a metre, which read as
    # broken sticks dangling under the axle rather than as the front of a cart.
    for sy in (-1, 1):
        shaft = [(-l * 0.38, sy * w_ * 0.34, bed_z - 0.05),
                 (-l * 0.75, sy * w_ * 0.30, bed_z - 0.03),
                 (-l * 1.15, sy * w_ * 0.26, bed_z - 0.02),
                 (-l * 1.45, sy * w_ * 0.24, bed_z)]
        parts.append(S.tube_along("shaft_%d" % sy, shaft, radius=0.055, segments=8, mat=mat))
    # the swingle bar across the shaft ends, so the pair reads as a harness and not two poles
    parts.append(S.cube("swingle", (0.07, w_ * 0.52, 0.07), (-l * 1.42, 0, bed_z), mat=mat))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.003)


def hay_bale(pal, rng, params, variant):
    r = jit(rng, 0.52) * CHUNK
    w_ = jit(rng, 0.9) * CHUNK
    straw = M.straw(pal, age=0.3 + 0.3 * rng.random(), scale=0.5)
    cord = M.rope(pal, age=0.5, scale=0.12)
    body = S.cylinder("bale", radius=r, depth=w_, vertices=22, location=(0, -w_ / 2, r),
                      rotation=(-90, 0, 0), mat=straw)
    S.bevel(body, width=r * 0.1, segments=3, angle_deg=50)
    S.jitter_verts(body, amount=r * 0.035, scale=0.6, seed=rng.randrange(999))
    S.shade_smooth(body, 45.0)
    parts = [body]
    for y in (-w_ * 0.28, w_ * 0.28):
        loop = B.rope_loop("tie", r * 1.02, 0.014, mat=cord, segments=24)
        loop.rotation_euler = Euler((math.pi / 2, 0, 0))
        S.apply_transforms(loop)
        loop.location = Vector((0, y, r))
        S.apply_transforms(loop)
        parts.append(loop)
    return finish(parts, rng, "convex", ["straw", "rope"])


# =========================================================================================
# books and paper
# =========================================================================================

def book(pal, rng, params, variant):
    w_ = jit(rng, 0.16) * CHUNK
    d = jit(rng, 0.23) * CHUNK
    t = jit(rng, 0.045) * CHUNK
    leather_mat = M.leather(pal, age=0.5 + 0.3 * rng.random(), wear=0.55, scale=0.2)
    paper = M.parchment(pal, age=0.5 + 0.3 * rng.random(), scale=0.3)
    pages = S.box_centered("pages", (w_ * 0.94, d * 0.94, t * 0.72), (0, 0, t * 0.5), mat=paper)
    S.bevel(pages, width=t * 0.06, segments=2)
    S.jitter_verts(pages, amount=t * 0.03, scale=0.3, seed=rng.randrange(999))
    cover = S.box_centered("cover", (w_, d, t * 0.14), (0, 0, t * 0.93), mat=leather_mat)
    S.bevel(cover, width=t * 0.05, segments=2)
    back = S.box_centered("back", (w_, d, t * 0.14), (0, 0, t * 0.07), mat=leather_mat)
    S.bevel(back, width=t * 0.05, segments=2)
    spine = S.lathe("spine", [(t * 0.5, -d * 0.5), (t * 0.5, d * 0.5)], segments=12,
                    mat=leather_mat, close=True)
    spine.rotation_euler = Euler((0, math.pi / 2, 0))
    S.apply_transforms(spine)
    spine.location = Vector((-w_ * 0.5, 0, t * 0.5))
    S.apply_transforms(spine)
    return finish([pages, cover, back, spine], rng, "convex", ["leather", "parchment"])


def book_stack(pal, rng, params, variant):
    n = int(params.get("count", rng.randint(3, 5)))
    parts = []
    z = 0.0
    for i in range(n):
        w_ = jit(rng, 0.16, 0.12) * CHUNK
        d = jit(rng, 0.23, 0.12) * CHUNK
        t = jit(rng, 0.045, 0.25) * CHUNK
        leather_mat = M.leather(pal, age=0.4 + 0.5 * rng.random(), wear=0.5, scale=0.2,
                                base_hex=["#6e4a2b", "#4a3a52", "#5a2a24", "#3a4438"][i % 4],
                                name="leather_%d" % i)
        paper = M.parchment(pal, age=0.6, scale=0.3, name="parchment_%d" % i)
        a = rng.uniform(-12, 12)
        pages = S.box_centered("pages_%d" % i, (w_ * 0.94, d * 0.94, t * 0.72), (0, 0, z + t * 0.5),
                               rotation=(0, 0, a), mat=paper)
        S.bevel(pages, width=t * 0.06, segments=2)
        cover = S.box_centered("cover_%d" % i, (w_, d, t * 0.14), (0, 0, z + t * 0.93),
                               rotation=(0, 0, a), mat=leather_mat)
        S.bevel(cover, width=t * 0.05, segments=2)
        back = S.box_centered("back_%d" % i, (w_, d, t * 0.14), (0, 0, z + t * 0.07),
                              rotation=(0, 0, a), mat=leather_mat)
        S.bevel(back, width=t * 0.05, segments=2)
        parts += [pages, cover, back]
        z += t * 1.02
    return finish(parts, rng, "convex", ["leather", "parchment"])


def scroll(pal, rng, params, variant):
    l = jit(rng, 0.34) * CHUNK
    r = jit(rng, 0.028) * CHUNK
    paper = M.parchment(pal, age=0.5 + 0.35 * rng.random(), scale=0.25)
    wood_mat = wood(pal, rng, age=0.5, plank_len=0.4, plank_w=0.06, along="X")
    body = S.cylinder("scroll", radius=r, depth=l, vertices=18, location=(0, 0, r),
                      rotation=(0, 90, 0), mat=paper, centered=True)
    S.shade_smooth(body, 40.0)
    parts = [body]
    # the loose outer edge, lifted a little
    lip = S.plane("lip", size=(r * 2.4, l * 0.94), location=(0, r * 1.05, r * 1.1),
                  rotation=(76, 0, 90), mat=paper)
    S.solidify(lip, thickness=0.0015, offset=0)
    parts.append(lip)
    for sx in (-1, 1):
        parts.append(S.cylinder("rod_%d" % sx, radius=r * 0.3, depth=l * 1.18, vertices=8,
                                location=(0, 0, r), rotation=(0, 90, 0), mat=wood_mat, centered=True))
        parts.append(S.sphere("knob_%d" % sx, radius=r * 0.42, subdivisions=2,
                              location=(sx * l * 0.6, 0, r), mat=wood_mat))
    return finish(parts, rng, "convex", ["parchment", "wood_planks"])


# =========================================================================================
# structures and outdoor
# =========================================================================================

def fence_wattle(pal, rng, params, variant):
    w_ = params.get("width", 2.0)
    h = jit(rng, 1.1) * CHUNK
    mat = M.wood_planks(pal, wear=0.5, age=0.6, base_hex="#9a7a4a", plank_len=1.5, plank_w=0.04,
                        name="hazel")
    parts = B.wattle_panel("wattle", w_, h, mat=mat, uprights=8, weaves=11, rod_r=0.018, rng=rng)
    return finish(parts, rng, "col_glb", ["wood_planks"],
                  extra={"modular": True, "module_width_m": w_})


def fence_post_rail(pal, rng, params, variant):
    w_ = params.get("width", 2.4)
    h = jit(rng, 1.15) * CHUNK
    mat = wood(pal, rng, plank_len=w_, plank_w=0.1, along="X")
    parts = []
    for x in (-w_ / 2, w_ / 2):
        post = S.cube("post", (0.09, 0.09, h), (x, 0, 0), mat=mat)
        S.bevel(post, width=0.008, segments=2)
        S.tilt(post, rng, max_deg=2.5)
        post.location = Vector((x, 0, 0))
        S.apply_transforms(post)
        parts.append(post)
    for z in (0.42, 0.74):
        rail = B.board("rail", w_ * 1.02, 0.05, 0.075, mat=mat, location=(0, 0, h * z),
                       sag=0.012, rng=rng)
        rail.rotation_euler = Euler((math.pi / 2, 0, 0))
        S.apply_transforms(rail)
        rail.location = Vector((0, 0, h * z))
        S.apply_transforms(rail)
        parts.append(rail)
    return finish(parts, rng, "col_glb", ["wood_planks"],
                  extra={"modular": True, "module_width_m": w_})


def drystone_wall(pal, rng, params, variant):
    w_ = params.get("width", 2.5)
    h = jit(rng, 1.0) * CHUNK
    d = jit(rng, 0.5) * CHUNK
    mat = M.drystone(pal, wear=0.5, age=0.7, scale=0.8)
    parts = B.stone_course("wall", w_, h, d, mat=mat, rows=5, rng=rng)
    return finish(parts, rng, "col_glb", ["drystone"],
                  extra={"modular": True, "module_width_m": w_})


def drystone_wall_end(pal, rng, params, variant):
    w_ = params.get("width", 0.9)
    h = jit(rng, 1.0) * CHUNK
    d = jit(rng, 0.5) * CHUNK
    mat = M.drystone(pal, wear=0.5, age=0.7, scale=0.8)
    parts = B.stone_course("wall_end", w_, h, d, mat=mat, rows=5, rng=rng, batter=0.1)
    # the end is built of long "throughs" turned across the wall so it does not fall apart
    for i in range(4):
        z = h * (0.14 + 0.24 * i)
        b = S.box_centered("through_%d" % i, (d * 0.52, d * 1.02, h * 0.17),
                           (-w_ * 0.5 + d * 0.28, 0, z),
                           rotation=(rng.uniform(-3, 3), rng.uniform(-2, 2), rng.uniform(-4, 4)), mat=mat)
        S.bevel(b, width=d * 0.04, segments=2)
        S.jitter_verts(b, amount=d * 0.03, scale=0.5, seed=rng.randrange(999))
        parts.append(b)
    return finish(parts, rng, "col_glb", ["drystone"],
                  extra={"modular": True, "module_width_m": w_, "is_end": True})


def well(pal, rng, params, variant):
    r = jit(rng, 0.62) * CHUNK
    wall_h = 0.78 * CHUNK
    stone = M.drystone(pal, wear=0.5, age=0.75, scale=0.6)
    mat = wood(pal, rng, age=0.7, plank_len=1.2, plank_w=0.1, along="X")
    metal = iron(pal, rng, age=0.8)
    cord = M.rope(pal, age=0.6, scale=0.15)
    parts = []
    rings = 5
    for row in range(rings):
        z = wall_h * (row + 0.5) / rings
        n = 14
        for i in range(n):
            a = TAU * (i + (row % 2) * 0.5) / n + rng.uniform(-0.03, 0.03)
            bw = TAU * r / n * 0.92
            b = S.box_centered("stone_%d_%d" % (row, i), (bw, r * 0.34, wall_h / rings * 0.9),
                               (0, 0, z), rotation=(0, 0, math.degrees(a)), mat=stone)
            b.location = Vector((math.cos(a) * r, math.sin(a) * r, z))
            S.apply_transforms(b)
            S.bevel(b, width=bw * 0.07, segments=2)
            S.jitter_verts(b, amount=bw * 0.05, scale=0.5, seed=rng.randrange(999))
            parts.append(b)
    parts.append(S.lathe("coping", [(r * 1.24, wall_h), (r * 1.26, wall_h + 0.05),
                                    (r * 0.78, wall_h + 0.06), (r * 0.76, wall_h)],
                         segments=24, mat=stone, close=True))
    post_h = 1.5 * CHUNK
    for sy in (-1, 1):
        post = S.cube("post_%d" % sy, (0.11, 0.11, post_h), (0, sy * r * 1.05, wall_h), mat=mat)
        S.bevel(post, width=0.012, segments=2)
        parts.append(post)
    parts.append(S.cylinder("winder", radius=0.075, depth=r * 2.0, vertices=12,
                            location=(0, -r, wall_h + post_h * 0.82), rotation=(-90, 0, 0), mat=mat))
    parts.append(S.cylinder("crank", radius=0.02, depth=0.3, vertices=7,
                            location=(0, r * 1.1, wall_h + post_h * 0.82), rotation=(-90, 0, 0), mat=metal))
    parts.append(S.cylinder("handle", radius=0.018, depth=0.16, vertices=7,
                            location=(0.28, r * 1.3, wall_h + post_h * 0.82), rotation=(0, 0, 0), mat=mat))
    # roof: two pitched planes
    for sx in (-1, 1):
        roof = S.plane("roof_%d" % sx, size=(r * 1.5, r * 2.6),
                       location=(sx * r * 0.42, 0, wall_h + post_h * 1.02),
                       rotation=(0, sx * 38, 0), mat=mat)
        S.solidify(roof, thickness=0.03, offset=0)
        parts.append(roof)
    rope_pts = [(0, 0, wall_h + post_h * 0.78), (0, 0, wall_h * 0.5)]
    parts.append(S.tube_along("rope", rope_pts, radius=0.014, segments=6, mat=cord))
    bkt = S.lathe("bucket", [(0.1, 0.0), (0.13, 0.22), (0.12, 0.22), (0.09, 0.01)],
                  segments=14, mat=mat, close=True)
    bkt.location = Vector((0, 0, wall_h * 0.5 - 0.22))
    S.apply_transforms(bkt)
    parts.append(bkt)
    return finish(parts, rng, "col_glb", ["drystone", "wood_planks", "iron", "rope"])


def signpost(pal, rng, params, variant):
    h = jit(rng, 2.1) * CHUNK
    mat = wood(pal, rng, age=0.65, plank_len=0.8, plank_w=0.12, along="X")
    metal = iron(pal, rng, age=0.7)
    post = S.lathe("post", [(0.075, 0.0), (0.07, h * 0.9), (0.065, h * 0.94),
                            (0.078, h * 0.96), (0.03, h)], segments=10, mat=mat, close=True)
    S.tilt(post, rng, max_deg=2.5)
    parts = [post]
    arms = int(params.get("arms", rng.randint(2, 3)))
    for i in range(arms):
        z = h * (0.62 + 0.14 * i)
        a = rng.uniform(0, TAU)
        arm = S.cube("arm_%d" % i, (0.62, 0.035, 0.14), (0, 0, z), rotation=(0, 0, math.degrees(a)), mat=mat)
        # pointed end
        for v in arm.data.vertices:
            if v.co.x > 0.2:
                v.co.z = (v.co.z - z - 0.07) * 0.35 + z + 0.07
        arm.location = Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, z))
        S.apply_transforms(arm)
        S.bevel(arm, width=0.006, segments=2)
        parts.append(arm)
        parts.append(S.cylinder("nail_%d" % i, radius=0.01, depth=0.03, vertices=6,
                                location=(math.cos(a) * 0.05, math.sin(a) * 0.05, z),
                                rotation=(90, 0, math.degrees(a)), mat=metal))
    return finish(parts, rng, "capsule", ["wood_planks", "iron"])


def market_stall(pal, rng, params, variant):
    w_ = jit(rng, 2.2) * CHUNK
    d = jit(rng, 1.3) * CHUNK
    h = jit(rng, 2.2) * CHUNK
    mat = wood(pal, rng, age=0.5, plank_len=w_, plank_w=0.13, along="X")
    awning = cloth(pal, rng, role="accent", scale=0.8)
    parts = []
    table_h = 0.85 * CHUNK
    parts += B.plank_run("counter", 4, w_, d / 4, 0.03, mat=mat, rng=rng, origin=(0, 0, table_h))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(S.cube("leg", (0.07, 0.07, table_h),
                                (sx * (w_ / 2 - 0.08), sy * (d / 2 - 0.08), 0), mat=mat))
    for sx in (-1, 1):
        parts.append(S.cube("upright", (0.08, 0.08, h), (sx * (w_ / 2 - 0.06), -d / 2 + 0.06, 0), mat=mat))
        parts.append(S.cube("upright_b", (0.08, 0.08, h * 0.82),
                            (sx * (w_ / 2 - 0.06), d / 2 - 0.06, 0), mat=mat))
    parts.append(S.cube("ridge", (w_, 0.06, 0.06), (0, -d / 2 + 0.06, h - 0.03), mat=mat))
    parts.append(S.cube("ridge_b", (w_, 0.06, 0.06), (0, d / 2 - 0.06, h * 0.82 - 0.03), mat=mat))
    canopy = S.plane("canopy", size=(w_ * 1.06, d * 1.12), location=(0, 0, h * 0.92),
                     rotation=(-13, 0, 0), mat=awning, subdiv=8)
    for v in canopy.data.vertices:
        v.co.z -= 0.035 * math.sin(math.pi * (v.co.x / (w_ * 0.53) * 0.5 + 0.5)) * \
            math.sin(math.pi * (v.co.y / (d * 0.56) * 0.5 + 0.5))
    S.solidify(canopy, thickness=0.008, offset=0)
    S.shade_smooth(canopy, 40.0)
    parts.append(canopy)
    valance = B.cloth_sheet("valance", w_ * 1.06, 0.26, mat=awning,
                            location=(0, -d * 0.56, h * 0.86), rotation=(13, 0, 0), rng=rng,
                            segments=(12, 4), fold=0.02, sag=0.02)
    parts.append(valance)
    return finish(parts, rng, "col_glb", ["wood_planks", "dyed_cloth"])


def dock_post(pal, rng, params, variant):
    h = jit(rng, 2.0) * CHUNK
    r = jit(rng, 0.11) * CHUNK
    mat = M.driftwood(pal, plank_len=2.0, plank_w=0.2, along="Z", name="dock_wood")
    cord = M.rope(pal, age=0.7, scale=0.2)
    post = S.lathe("post", [(r * 1.1, 0.0), (r, h * 0.3), (r * 0.94, h * 0.7),
                            (r * 0.96, h * 0.92), (r * 0.82, h)], segments=12, mat=mat, close=True)
    S.jitter_verts(post, amount=r * 0.09, scale=1.2, seed=rng.randrange(999))
    S.tilt(post, rng, max_deg=5.0)
    parts = [post]
    for i in range(int(params.get("rope_turns", 4))):
        parts.append(B.rope_loop("lash_%d" % i, r * 1.16, 0.014, mat=cord, segments=18,
                                 location=(0, 0, h * (0.62 + 0.045 * i))))
    # a stub of rope trailing down
    parts.append(S.tube_along("tail", [(r * 1.1, 0, h * 0.62), (r * 1.6, r * 0.4, h * 0.3),
                                       (r * 1.9, r * 0.7, h * 0.05)], radius=0.014, segments=6, mat=cord))
    return finish(parts, rng, "capsule", ["driftwood", "rope"])


def boardwalk_plank(pal, rng, params, variant):
    """One boardwalk module: planks on two bearers, for Sedgemire's walkways."""
    w_ = params.get("width", 2.0)
    d = jit(rng, 1.4) * CHUNK
    mat = M.driftwood(pal, plank_len=w_, plank_w=0.18, along="X", name="board_wood")
    parts = B.plank_run("deck", 7, w_, d / 7, 0.035, mat=mat, rng=rng, sag=0.005, origin=(0, 0, 0.09))
    for x in (-w_ * 0.4, w_ * 0.4):
        parts.append(S.cube("bearer", (0.08, d * 1.02, 0.09), (x, 0, 0), mat=mat))
    return finish(parts, rng, "col_glb", ["driftwood"],
                  extra={"modular": True, "module_width_m": w_})


def rowboat(pal, rng, params, variant):
    l = jit(rng, 3.4) * CHUNK
    w_ = jit(rng, 1.25) * CHUNK
    h = jit(rng, 0.55) * CHUNK
    mat = M.driftwood(pal, plank_len=l, plank_w=0.12, along="X", name="boat_wood")
    tarry = M.wood_planks(pal, wear=0.4, age=0.8, base_hex="#3a3128", plank_len=l, plank_w=0.12,
                          along="X", name="boat_tar")
    parts = []
    strakes = 5
    for s in range(strakes):
        f = s / float(strakes - 1)
        z = h * f
        prof = []
        n = 18
        for i in range(n + 1):
            t = i / n
            x = (t - 0.5) * l
            # hull half-breadth: a fine entry, full midships, narrow run aft
            b = math.sin(math.pi * min(1.0, max(0.0, (t - 0.03) / 0.94))) ** 0.7
            y = w_ * 0.5 * b * (0.52 + 0.48 * f)
            prof.append((x, y, z + (0.06 * h if (t < 0.06 or t > 0.94) else 0.0) * (1 - f)))
        strake = S.tube_along("strake_%d" % s, [(x, y, zz) for (x, y, zz) in prof],
                              radius=h * 0.075, segments=6, mat=mat if s else tarry)
        parts.append(strake)
        strake2 = S.tube_along("strake_m%d" % s, [(x, -y, zz) for (x, y, zz) in prof],
                               radius=h * 0.075, segments=6, mat=mat if s else tarry)
        parts.append(strake2)
    # hull skin between the strakes: a lofted surface approximated by a squashed lathe
    hull = S.uv_sphere("hull", radius=1.0, segments=26, rings=14, mat=mat,
                       scale=(l * 0.5, w_ * 0.46, h * 0.98))
    S.apply_transforms(hull)
    hull.location = Vector((0, 0, h))
    S.apply_transforms(hull)
    cut = S.box_centered("cut", (l * 2, w_ * 2, h * 2), (0, 0, h * 2))
    S.boolean(hull, cut, "DIFFERENCE")
    inner = S.uv_sphere("inner", radius=1.0, segments=22, rings=12,
                        scale=(l * 0.46, w_ * 0.40, h * 0.92))
    S.apply_transforms(inner)
    inner.location = Vector((0, 0, h * 1.06))
    S.apply_transforms(inner)
    S.boolean(hull, inner, "DIFFERENCE")
    S.shade_smooth(hull, 40.0)
    parts.append(hull)
    for t in (0.32, 0.52, 0.72):
        bw = w_ * math.sin(math.pi * t) ** 0.7
        parts.append(S.cube("thwart", (0.2, bw * 0.96, 0.03),
                            ((t - 0.5) * l, 0, h * 0.78), mat=mat))
    for sy in (-1, 1):
        oar_pts = [((0.05) * l, sy * w_ * 0.5, h * 0.8), (-0.3 * l, sy * w_ * 0.72, h * 0.55),
                   (-0.5 * l, sy * w_ * 0.8, h * 0.45)]
        parts.append(S.tube_along("oar_%d" % sy, oar_pts, radius=0.028, radius_end=0.05,
                                  segments=7, mat=mat))
    return finish(parts, rng, "col_glb", ["driftwood"], extra={"floats": True})


def tent(pal, rng, params, variant):
    l = jit(rng, 2.6) * CHUNK
    w_ = jit(rng, 2.0) * CHUNK
    h = jit(rng, 1.6) * CHUNK
    canvas_mat = M.canvas(pal, age=0.5 + 0.35 * rng.random(), wear=0.45, scale=1.0)
    mat = wood(pal, rng, age=0.6, plank_len=2.0, plank_w=0.08, along="Z")
    cord = M.rope(pal, age=0.5, scale=0.15)
    parts = []
    for sy in (-1, 1):
        panel = S.plane("panel_%d" % sy, size=(l, math.hypot(w_ / 2, h) * 1.02),
                        location=(0, sy * w_ * 0.25, h * 0.5), mat=canvas_mat, subdiv=10)
        ang = math.degrees(math.atan2(h, w_ / 2))
        panel.rotation_euler = Euler((math.radians(sy * (90 - ang)), 0, 0))
        S.apply_transforms(panel)
        panel.location = Vector((0, sy * w_ * 0.25, h * 0.5))
        S.apply_transforms(panel)
        for v in panel.data.vertices:
            v.co.z -= 0.03 * math.sin(math.pi * (v.co.x / (l * 0.5) * 0.5 + 0.5))
        S.solidify(panel, thickness=0.008, offset=0)
        S.shade_smooth(panel, 45.0)
        parts.append(panel)
    back = S.mesh_from_pydata("back", [(l * 0.5, -w_ / 2, 0), (l * 0.5, w_ / 2, 0), (l * 0.5, 0, h)],
                              [(0, 1, 2)], mat=canvas_mat)
    S.solidify(back, thickness=0.008, offset=0)
    parts.append(back)
    for sx in (-1, 1):
        parts.append(S.cylinder("pole_%d" % sx, radius=0.035, depth=h * 1.05,
                                vertices=8, location=(sx * l * 0.5, 0, 0), mat=mat))
    parts.append(S.cylinder("ridge", radius=0.03, depth=l * 1.05, vertices=8,
                            location=(-l * 0.52, 0, h), rotation=(0, 90, 0), mat=mat))
    for sx in (-1, 1):
        for sy in (-1, 1):
            a = (sx * l * 0.52, 0, h * 1.0)
            b = (sx * (l * 0.5 + 0.7), sy * 0.5, 0.0)
            parts.append(S.tube_along("guy_%d_%d" % (sx, sy), [a, b], radius=0.008, segments=5, mat=cord))
            parts.append(S.cylinder("peg", radius=0.015, radius_top=0.0, depth=0.22, vertices=6,
                                    location=b, rotation=(20, 0, 0), mat=mat))
    return finish(parts, rng, "col_glb", ["canvas", "wood_planks", "rope"])


def bedroll(pal, rng, params, variant):
    l = jit(rng, 1.85) * CHUNK
    w_ = jit(rng, 0.68) * CHUNK
    canvas_mat = M.canvas(pal, age=0.55, wear=0.5, scale=0.6)
    blanket = cloth(pal, rng, role="earth", scale=0.5)
    cord = M.rope(pal, age=0.5, scale=0.12)
    if params.get("rolled", rng.random() < 0.45):
        r = w_ * 0.28
        body = S.cylinder("roll", radius=r, depth=l * 0.55, vertices=20, location=(0, 0, r),
                          rotation=(0, 90, 0), mat=blanket, centered=True)
        S.jitter_verts(body, amount=r * 0.06, scale=0.5, seed=rng.randrange(999))
        S.shade_smooth(body, 45.0)
        parts = [body]
        for x in (-l * 0.18, l * 0.18):
            loop = B.rope_loop("tie", r * 1.06, 0.012, mat=cord, segments=18)
            loop.rotation_euler = Euler((0, math.pi / 2, 0))
            S.apply_transforms(loop)
            loop.location = Vector((x, 0, r))
            S.apply_transforms(loop)
            parts.append(loop)
        return finish(parts, rng, "convex", ["dyed_cloth", "rope"], extra={"rolled": True})
    mat_base = S.box_centered("mat", (l, w_, 0.06), (0, 0, 0.03), mat=canvas_mat)
    S.bevel(mat_base, width=0.02, segments=3, angle_deg=50)
    S.jitter_verts(mat_base, amount=0.012, scale=0.5, seed=rng.randrange(999))
    cover = S.box_centered("cover", (l * 0.7, w_ * 0.98, 0.05), (l * 0.12, 0, 0.085), mat=blanket)
    S.bevel(cover, width=0.018, segments=3, angle_deg=50)
    S.jitter_verts(cover, amount=0.014, scale=0.4, seed=rng.randrange(999))
    pillow = S.box_centered("bundle", (0.28, w_ * 0.6, 0.12), (-l * 0.38, 0, 0.1), mat=canvas_mat)
    S.bevel(pillow, width=0.05, segments=3, angle_deg=55)
    S.jitter_verts(pillow, amount=0.012, scale=0.3, seed=rng.randrange(999))
    return finish([mat_base, cover, pillow], rng, "convex", ["canvas", "dyed_cloth"])


def banner(pal, rng, params, variant):
    w_ = jit(rng, 0.8) * CHUNK
    h = jit(rng, 2.1) * CHUNK
    fabric = cloth(pal, rng, role="accent", scale=1.2)
    mat = wood(pal, rng, age=0.5, plank_len=1.0, plank_w=0.06, along="X")
    metal = M.brass(pal, age=0.5, wear=0.4, scale=0.06)
    sheet = B.cloth_sheet("banner", w_, h, mat=fabric, location=(0, 0, h * 1.05), rng=rng,
                          segments=(10, 14), fold=w_ * 0.035, sag=h * 0.03)
    # swallow-tail hem
    for v in sheet.data.vertices:
        if v.co.z < -h * 0.86:
            v.co.z += (h * 0.16) * (1.0 - abs(v.co.x) / (w_ * 0.5))
    S.shade_smooth(sheet, 45.0)
    pole = S.cylinder("pole", radius=0.024, depth=h * 1.12, vertices=10, location=(0, 0, 0), mat=mat)
    cross = S.cylinder("cross", radius=0.016, depth=w_ * 1.1, vertices=8,
                       location=(-w_ * 0.55, 0, h * 1.06), rotation=(0, 90, 0), mat=mat)
    finial = S.cylinder("finial", radius=0.026, radius_top=0.0, depth=0.12, vertices=8,
                        location=(0, 0, h * 1.12), mat=metal)
    return finish([sheet, pole, cross, finial], rng, "capsule", ["dyed_cloth", "wood_planks", "brass"])


# =========================================================================================
# bells and burial
# =========================================================================================

def _bell(pal, rng, h, patina=0.6):
    metal = M.bell_bronze_patina(pal, age=patina, wear=0.5, scale=h * 0.5)
    r = h * 0.46
    prof = [(r, 0.0), (r * 0.98, h * 0.05), (r * 0.9, h * 0.11), (r * 0.78, h * 0.2),
            (r * 0.71, h * 0.32), (r * 0.68, h * 0.46), (r * 0.63, h * 0.6),
            (r * 0.54, h * 0.74), (r * 0.4, h * 0.85), (r * 0.22, h * 0.94), (r * 0.12, h)]
    inner = [(max(0.004, x - r * 0.1 * (0.6 + 0.8 * (1 - z / h))), z) for (x, z) in reversed(prof)]
    body = S.lathe("bell", prof + inner, segments=26, mat=metal, close=False)
    S.shade_smooth(body, 38.0)
    parts = [body]
    parts.append(S.lathe("crown", [(r * 0.18, h), (r * 0.22, h * 1.03), (r * 0.12, h * 1.06)],
                         segments=14, mat=metal, close=True))
    for i in range(4):
        a = TAU * i / 4
        parts.append(S.torus("canon_%d" % i, major=r * 0.13, minor=r * 0.04, seg_major=14,
                             seg_minor=6, location=(math.cos(a) * r * 0.11, math.sin(a) * r * 0.11, h * 1.03),
                             rotation=(70, 0, math.degrees(a) + 90), mat=metal))
    clapper = S.sphere("clapper", radius=r * 0.16, subdivisions=2, location=(0, 0, h * 0.18), mat=metal)
    parts.append(clapper)
    parts.append(S.cylinder("clapper_rod", radius=r * 0.03, depth=h * 0.6, vertices=7,
                            location=(0, 0, h * 0.2), mat=metal))
    return parts, metal, r


def bell_small(pal, rng, params, variant):
    h = jit(rng, params.get("height", 0.22)) * CHUNK
    parts, metal, r = _bell(pal, rng, h, patina=0.4 + 0.3 * rng.random())
    # the small cousins hung in Hearthvale's trees: a loop of cord at the crown
    cord = M.rope(pal, age=0.5, scale=0.1)
    parts.append(B.rope_loop("hanger", r * 0.16, 0.006, mat=cord, location=(0, 0, h * 1.1)))
    return finish(parts, rng, "convex", ["bell_bronze_patina", "rope"], extra={"hangs": True})


def bell_medium(pal, rng, params, variant):
    h = jit(rng, params.get("height", 0.95)) * CHUNK
    parts, metal, r = _bell(pal, rng, h, patina=0.8)
    mat = wood(pal, rng, age=0.7, plank_len=1.0, plank_w=0.12, along="X")
    headstock = S.cube("headstock", (r * 1.6, r * 0.5, r * 0.34), (0, 0, h * 1.06), mat=mat)
    S.bevel(headstock, width=r * 0.04, segments=2)
    parts.append(headstock)
    for sx in (-1, 1):
        parts.append(S.cylinder("gudgeon_%d" % sx, radius=r * 0.09, depth=r * 0.3, vertices=10,
                                location=(sx * r * 0.82, 0, h * 1.06 + r * 0.17),
                                rotation=(0, 90, 0), mat=metal))
    return finish(parts, rng, "convex", ["bell_bronze_patina", "wood_planks"])


def gravestone(pal, rng, params, variant):
    h = jit(rng, params.get("height", 0.85)) * CHUNK
    w_ = h * rng.uniform(0.44, 0.62)
    t = w_ * rng.uniform(0.16, 0.24)
    stone = M.limestone(pal, wear=0.5, age=0.85, scale=0.5)
    shape = params.get("shape", ["round", "gable", "slab"][variant % 3])
    if shape == "round":
        prof = []
        n = 14
        for i in range(n + 1):
            f = i / n
            z = h * f
            if f < 0.72:
                x = w_ * 0.5
            else:
                k = (f - 0.72) / 0.28
                x = w_ * 0.5 * math.sqrt(max(0.0, 1.0 - k * k))
            prof.append((x, z))
        verts = [(x, -t / 2, z) for (x, z) in prof] + [(-x, -t / 2, z) for (x, z) in reversed(prof)]
        body = S.mesh_from_pydata("stone", verts, [tuple(range(len(verts)))], smooth=False)
        body.data.materials.append(stone)
        S.solidify(body, thickness=t, offset=0)
    elif shape == "gable":
        verts = [(-w_ / 2, 0, 0), (w_ / 2, 0, 0), (w_ / 2, 0, h * 0.72), (0, 0, h),
                 (-w_ / 2, 0, h * 0.72)]
        body = S.mesh_from_pydata("stone", verts, [(0, 1, 2, 3, 4)], smooth=False)
        body.data.materials.append(stone)
        S.solidify(body, thickness=t, offset=0)
    else:
        body = S.cube("stone", (w_, t, h), (0, 0, 0), mat=stone)
    S.bevel(body, width=t * 0.12, segments=2, angle_deg=40)
    S.jitter_verts(body, amount=t * 0.09, scale=0.5, seed=rng.randrange(999))
    S.tilt(body, rng, max_deg=6.0)
    parts = [body]
    # a low kerb and a little grass-caught base stone
    base = S.box_centered("base", (w_ * 1.3, t * 2.0, h * 0.09), (0, 0, h * 0.045), mat=stone)
    S.bevel(base, width=t * 0.1, segments=2)
    S.jitter_verts(base, amount=t * 0.06, scale=0.5, seed=rng.randrange(999))
    parts.append(base)
    return finish(parts, rng, "convex", ["limestone"], extra={"shape": shape})


def coffin(pal, rng, params, variant):
    l = jit(rng, 1.95) * CHUNK
    w_ = jit(rng, 0.52) * CHUNK
    h = jit(rng, 0.36) * CHUNK
    mat = wood(pal, rng, age=0.7, wear=0.5, plank_len=l, plank_w=0.13, along="X")
    metal = iron(pal, rng, age=0.8)
    # tapered hexagonal plan: wide at the shoulders, narrow at head and foot
    def plan(z):
        pts = []
        for (t, k) in ((0.0, 0.45), (0.22, 1.0), (0.62, 0.82), (1.0, 0.42)):
            pts.append(((t - 0.5) * l, w_ * 0.5 * k))
        return pts
    outline = plan(0)
    verts = [(x, y, 0) for (x, y) in outline] + [(x, -y, 0) for (x, y) in reversed(outline)]
    base = S.mesh_from_pydata("coffin", verts, [tuple(range(len(verts)))], mat=mat, smooth=False)
    S.solidify(base, thickness=h, offset=1.0)
    S.bevel(base, width=0.012, segments=2, angle_deg=40)
    parts = [base]
    lid = S.mesh_from_pydata("lid", [(x, y, h) for (x, y) in outline] +
                             [(x, -y, h) for (x, y) in reversed(outline)],
                             [tuple(range(len(verts)))], mat=mat, smooth=False)
    S.solidify(lid, thickness=0.03, offset=1.0)
    S.bevel(lid, width=0.008, segments=2, angle_deg=40)
    parts.append(lid)
    for x in (-l * 0.3, 0.0, l * 0.3):
        parts.append(B.iron_strap("band", w_ * 1.05, 0.045, 0.006, mat=metal,
                                  location=(x, 0, h + 0.033), rotation=(0, 0, 90)))
    return finish(parts, rng, "convex", ["wood_planks", "iron"], jitter=0.003)


def sarcophagus(pal, rng, params, variant):
    l = jit(rng, 2.2) * CHUNK
    w_ = jit(rng, 0.9) * CHUNK
    h = jit(rng, 0.72) * CHUNK
    stone = M.fused_stone(pal, wear=0.45, age=0.85, gilding=0.2, scale=0.5)
    box = S.box_centered("box", (l, w_, h * 0.72), (0, 0, h * 0.36), mat=stone)
    S.bevel(box, width=0.03, segments=3, angle_deg=45)
    # recessed panels down the long sides
    for sy in (-1, 1):
        for i in range(3):
            x = (i - 1) * l * 0.3
            cut = S.box_centered("panel_%d_%d" % (sy, i), (l * 0.22, 0.06, h * 0.38),
                                 (x, sy * (w_ * 0.5 - 0.02), h * 0.38))
            S.boolean(box, cut, "DIFFERENCE")
    lid = S.lathe("lid", [(0.0, -l * 0.5), (h * 0.3, -l * 0.44), (h * 0.34, 0.0),
                          (h * 0.3, l * 0.44), (0.0, l * 0.5)], segments=14, mat=stone, close=True)
    lid.rotation_euler = Euler((0, math.pi / 2, 0))
    S.apply_transforms(lid)
    lid.scale = Vector((1.0, w_ / (h * 0.68), 1.0))
    S.apply_transforms(lid)
    lid.location = Vector((0, 0, h * 0.72))
    S.apply_transforms(lid)
    for v in lid.data.vertices:
        v.co.z = max(v.co.z, h * 0.72)
    S.shade_smooth(lid, 38.0)
    parts = [box, lid]
    for p in parts:
        S.jitter_verts(p, amount=0.006, scale=1.2, seed=rng.randrange(999))
    return finish(parts, rng, "convex", ["fused_stone"], tier=None)


KINDS = {
    # containers and vessels
    "barrel": barrel, "crate": crate, "bucket": bucket, "sack": sack, "basket": basket,
    "chest": chest, "cooking_pot": cooking_pot, "plate": plate, "mug": mug, "jug": jug,
    # furniture
    "table_trestle": table_trestle, "table_round": table_round, "stool": stool, "chair": chair,
    "bench": bench, "bed": bed, "shelf": shelf, "cupboard": cupboard,
    # light and fire
    "candle": candle, "candlestick": candlestick, "lantern_hanging": lantern_hanging,
    "lantern_standing": lantern_standing, "brazier": brazier, "chandelier": chandelier,
    "campfire": campfire,
    # work
    "anvil": anvil, "forge_hearth": forge_hearth, "alembic": alembic, "rope_coil": rope_coil,
    "wheelbarrow": wheelbarrow, "cart": cart, "hay_bale": hay_bale,
    # books and paper
    "book": book, "book_stack": book_stack, "scroll": scroll,
    # structures and outdoor
    "fence_wattle": fence_wattle, "fence_post_rail": fence_post_rail,
    "drystone_wall": drystone_wall, "drystone_wall_end": drystone_wall_end,
    "well": well, "signpost": signpost, "market_stall": market_stall,
    "dock_post": dock_post, "boardwalk_plank": boardwalk_plank, "rowboat": rowboat,
    "tent": tent, "bedroll": bedroll, "banner": banner,
    # bells and burial
    "bell_small": bell_small, "bell_medium": bell_medium, "gravestone": gravestone,
    "coffin": coffin, "sarcophagus": sarcophagus,
}


if __name__ == "__main__":
    run_generator("Wickmere props generator", KINDS, "props", "gen_props")
