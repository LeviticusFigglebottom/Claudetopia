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


# The timber a region's joiners actually work in, where the palette alone does not say it.
#
# `wood_planks` starts from one oak-brown and mixes in a fifth of the palette's `earth`
# role, and the six regions' earth roles are all a red-brown within a few percent of each
# other: measured off the baked albedo, a Briarwold trestle came out eight units of 255
# from a Hearthvale one. Nobody would call that "a Hearthvale oak fence or a Briarwold
# black-ash one", which is what tools/forge/README.md promises and what makes a per-region
# prop worth building at all -- a second set of meshes in the same colour gives
# `PropLibrary` nothing to choose between but the seed.
#
# So a region whose identity names a timber gets that timber. Briarwold's flora list opens
# `giant_oak, black_ash`: the wood under the canopy is the dark, olive-brown, close-grained
# ash it is named for. Only regions listed here differ, and only props built after this
# change, so no asset already in the tree moves.
TIMBER = {
    "briarwold": {"base_hex": "#4a3b28", "tint": 0.34},
}


def wood(pal, rng, wear=None, age=None, **kw):
    kw.setdefault("wear", wear if wear is not None else 0.35 + 0.4 * rng.random())
    kw.setdefault("age", age if age is not None else 0.3 + 0.45 * rng.random())
    for k, v in TIMBER.get(getattr(pal, "short", ""), {}).items():
        kw.setdefault(k, v)
    return M.wood_planks(pal, **kw)


def iron(pal, rng, **kw):
    kw.setdefault("age", 0.4 + 0.45 * rng.random())
    kw.setdefault("wear", 0.45 + 0.35 * rng.random())
    return M.iron(pal, **kw)


def tool_wood(pal, rng, scale=0.8, wear=0.30, age=0.55, base_hex="#7a5c34", relief=0.10,
              name="tool_wood", **kw):
    """Timber for something you hold: a haft, a shaft, a carved bowl, a block.

    Every length in `wood_planks` is in units of `scale`, and `scale` is itself a feature
    size in metres whose default of 1.0 means "features a metre across". Picking it for a
    hand-sized object is squeezed from both ends and the middle is narrow:

    * too large and `paint_blocks` lays its three tones down across more than the whole
      object, so the thing takes one arbitrary stop of the ramp. That is what made the
      anvil's stump a flat cream drum, and it is why anything over about a quarter of a
      metre wants a scale well under its own size;
    * too small and the brush strokes quilt: they land every `scale`/4 metres, so a
      quarter-metre scale draws upholstery across a whetstone's block.

    Under about 0.3 m across, stay near 0.8 and let the object be one tone -- a spoon *is*
    one tone. Past that, come down to roughly a third of the object's size.

    `relief` is separate and is the one that bit hardest. `wood_planks` bumps its normal
    over an absolute 15 mm, which does not follow `scale` at all, so shrinking the grain
    only makes the corrugation finer and never shallower: at any scale a spoon came out
    fluted like a scallop shell. A tenth is about right for anything hand-sized.

    `relief` was only half of that fault, and the render said so: a hammer haft, a spear
    shaft and a spoon all still came out of the first build ringed like a screw thread,
    because the grain that draws those rings is in the *albedo* and `relief` only touches
    the normal. The grain wave bands every `scale`/22.5 metres -- 31 mm at the 0.70 a haft
    asks for, around a haft 18 mm thick. `grain` divides that frequency, and a quarter is
    about right: two or three soft lengthwise tones, which is one cleft stave.

    The plank size is set past anything this is used for, because nothing here is a sawn
    board: a spoon is carved from one billet and a haft cleft from one stave, and a plank
    joint crossing either is a lie. `wear` is low for the same reason the stump was cream:
    edge wear lightens convex edges, and a hand-sized object bevelled all over is convex
    nearly everywhere, so a wear of 0.7 bleaches the whole of it."""
    kw.setdefault("plank_len", 12.0)
    kw.setdefault("plank_w", 4.0)
    kw.setdefault("grain", 0.25)
    return M.wood_planks(pal, wear=wear, age=age, scale=scale, base_hex=base_hex, name=name, **kw)


def stand_up(parts, deg_x):
    """Tip a whole prop back by `deg_x` about the world origin, every part together.

    The obvious spelling -- set `rotation_euler` on each part and apply -- is wrong for any
    part that still carries an object-level placement, and about half of what this file
    builds does: `S.sphere(location=...)`, `B.board(location=...)` and every other
    primitive keep their `location` on the object, so applying a rotation turns them about
    their own origin and leaves them exactly where they were while the rest of the prop
    swings away. Baking the placement into the vertices first puts every part in world
    coordinates, and then one rotation about the origin moves them all.

    Until this existed a spear's socket rivet hung in the air a hand's breadth off the
    shaft, and a shield's six boss rivets stayed in a flat ring at the height the boss had
    been before the shield stood up -- four of the six floating clear of the board."""
    for p in parts:
        S.apply_transforms(p)
        p.rotation_euler = Euler((math.radians(deg_x), 0.0, 0.0))
        S.apply_transforms(p)


def cloth_mat(pal, rng, role="accent", **kw):
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
    blanket = cloth_mat(pal, rng, role="accent", scale=0.5)
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
    """An anvil on its stump.

    The iron is about 0.30 m from foot to face, which is what an anvil *is*; the rest of a
    smith's working height is the block it stands on, and that block was missing. Without it
    the face sat at 0.371 m and the work clips — authored against the 0.750 m placeholder in
    `HouseInterior._placeholder_size` — had the smith hammering at his knees.

    So `face_height` is fixed rather than jittered and chunked: it is an ergonomic
    measurement (knuckle height, near enough), not a stylisation. The chunkiness goes into
    the iron and the timber, and the stump takes up whatever is left over."""
    l = jit(rng, 0.62) * CHUNK
    ah = jit(rng, 0.30) * CHUNK                          # foot to face, the iron alone
    face = float(params.get("face_height", 0.72))        # where the work lands
    sh = max(0.12, face - ah)                            # so the stump is the difference
    metal = iron(pal, rng, age=0.6, wear=0.75, scale=0.22)
    # 0.20 and not the stump's own 0.4 m: `paint_blocks` lays its three tones down at the
    # material's `scale`, so a scale near the object's size drops the whole thing on one
    # arbitrary stop of the ramp -- which is how the stump first came out a flat cream.
    #
    # It came out cream anyway, because that was not the whole of it. Hearthvale timber is
    # a pale honey by design -- the trestle table is the same colour and is meant to be --
    # and a stump dressed in it reads as a plinth of soft stone with an anvil balanced on
    # top. What tells you it is a block of oak is that it is darker than the furniture:
    # this one stands in a forge under fifty years of scale and quench water. So the base
    # goes to a wet dark brown and the wear that lightens convex edges comes down to almost
    # nothing, because a nine-sided billet is convex everywhere and edge wear was bleaching
    # the whole of it back to cream. `age` stays middling on purpose although this is an
    # old block: age takes saturation out as well as value (`sat = 1 - 0.2 * age`), and at
    # 0.95 the dark brown came back as a grey-olive, which reads as wet stone and lands
    # the block back where it started.
    oak = tool_wood(pal, rng, scale=0.20, wear=0.10, age=0.50, base_hex="#402c16",
                    tint=0.16, relief=0.30, grain=0.45, along="Z", name="stump_oak")
    parts = []
    # A length of vale oak hewn to nine flats and stood on the beaten floor. Nine sides put
    # 40 degrees between facets, more than the exporter's 35 degree smoothing angle, so it
    # stays faceted and reads as axe-work; an odd number and a per-facet radius keep it from
    # reading as a turned drum, and one band rather than two keeps it from reading as a keg.
    # As wide as the anvil's own foot and no wider. At l * 0.30 the block was 0.41 m across
    # and 0.39 m tall -- as broad as it was high, which is a keg or a plinth and not a
    # length of trunk. The foot is l * 0.46 long, so a block a little narrower than the
    # anvil is long stands the iron on timber with nothing to spare, which is what a
    # smith's block looks like from across a yard.
    sr = max(l * 0.245, 0.155)
    sides = 9
    log = S.lathe("stump", [(sr * 1.10, 0.0), (sr * 1.02, sh * 0.13), (sr * 0.97, sh * 0.52),
                            (sr * 0.99, sh * 0.86), (sr * 0.955, sh)],
                  segments=sides, mat=oak, close=True)
    facet = [rng.uniform(0.93, 1.05) for _ in range(sides)]
    for v in log.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if rr > 1e-6:
            f = facet[int(round((math.atan2(v.co.y, v.co.x) % TAU) / TAU * sides)) % sides]
            v.co.x *= f
            v.co.y *= f
    S.jitter_verts(log, amount=sr * 0.04, scale=0.22, seed=rng.randrange(999))
    parts.append(log)
    band_metal = iron(pal, rng, age=0.85, wear=0.5, scale=0.14)
    parts.append(B.hoop("band", sr * 1.0, 0.013, mat=band_metal,
                        location=(0, 0, sh * 0.84), segments=20, flatten=2.6))
    # Foot, waist and body overlap by a few millimetres each. They did not, at first, and
    # the daylight through the joint between the foot and the waist was plain in the render.
    body = S.box_centered("body", (l * 0.52, l * 0.22, ah * 0.38), (0, 0, sh + ah * 0.81), mat=metal)
    S.bevel(body, width=ah * 0.03, segments=2)
    waist = S.box_centered("waist", (l * 0.3, l * 0.16, ah * 0.42), (0, 0, sh + ah * 0.45), mat=metal)
    S.bevel(waist, width=ah * 0.05, segments=2)
    foot = S.box_centered("foot", (l * 0.46, l * 0.26, ah * 0.26), (0, 0, sh + ah * 0.13), mat=metal)
    S.bevel(foot, width=ah * 0.04, segments=2)
    horn = S.cylinder("horn", radius=l * 0.1, radius_top=l * 0.015, depth=l * 0.3, vertices=14,
                      location=(-l * 0.26, 0, sh + ah * 0.81), rotation=(0, -90, 0), mat=metal)
    heel = S.box_centered("heel", (l * 0.16, l * 0.2, ah * 0.34), (l * 0.3, 0, sh + ah * 0.79), mat=metal)
    S.bevel(heel, width=ah * 0.03, segments=2)
    hardy = S.cube("hardy", (0.028, 0.028, ah * 0.09), (l * 0.2, 0, sh + ah * 0.98), mat=metal)
    parts += [foot, waist, body, horn, heel, hardy]
    # Staples over the base, which is how an anvil is actually held to its block.
    for sx in (-1, 1):
        parts.append(B.iron_strap("staple_%d" % sx, l * 0.30, 0.026, 0.007, mat=band_metal,
                                  location=(sx * l * 0.20, 0, sh + ah * 0.02), rotation=(0, 0, 90)))
    return finish(parts, rng, "convex", ["iron", "wood_planks"], jitter=0.002,
                  extra={"face_height": round(sh + ah, 3)})


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
# hand tools, arms and linen
#
# Everything here is between 0.05 m and 1.8 m, which is a tenth of what the rest of this
# file makes, and that matters to the *materials* more than to the geometry: every builder
# in materials.py sizes its paint blocks, grain and grit off `scale`, in metres, and the
# default of 1.0 means "features a metre across". On a 0.25 m spoon that is one flat tone
# and no grain at all. So each of these passes a scale near its own size, and the plank
# parameters are given in the scaled space (a length in metres is `metres / scale`).
# =========================================================================================

def _fold_path(rng, length, layers, gap, slack=0.0, rough=0.0, fold_w=1.0):
    """A cloth's own centre-line as it is folded: runs, and the arcs where it turns back.

    Returned as [(x, z), ...]. The turn is a half-ellipse rather than a crease, so the fold
    is a roll you can see round. `rough` unsettles it: the layers take their own thicknesses
    and their own slow undulation, which is the difference between linen put away and a rag
    dropped where it was finished with."""
    pts = []
    n_run, n_fold = 12, 6
    d = 1
    half = length * 0.5
    z = 0.0
    for k in range(layers):
        g = gap * (1.0 + rough * rng.uniform(-0.25, 0.75))
        f = 1.0 - slack * rng.random()
        xa, xb = (-half, half * f) if d > 0 else (half, -half * f)
        k1, k2 = rng.uniform(1.4, 2.6), rng.uniform(3.1, 4.7)
        p1, p2 = rng.uniform(0, TAU), rng.uniform(0, TAU)
        for i in range(n_run + 1):
            t = i / n_run
            wob = math.sin(t * math.pi) * g * 0.12
            wob += rough * g * (math.sin(t * math.pi * k1 + p1) * 0.45
                                + math.sin(t * math.pi * k2 + p2) * 0.25)
            pts.append((xa + (xb - xa) * t, z + wob))
        if k == layers - 1:
            break
        r = g * 0.5
        for i in range(1, n_fold + 1):
            phi = -math.pi * 0.5 + math.pi * i / n_fold
            pts.append((xb + d * math.cos(phi) * r * fold_w, z + r + math.sin(phi) * r))
        z += g
        d = -d
    return pts


def cloth(pal, rng, params, variant):
    """Folded linen, or a rag dropped where it was put down.

    The folds are geometry: the cloth is one strip swept along a path that doubles back on
    itself, so each fold is a roll you can see round, and the face carries ripples along its
    own normal. A flat plane with a cloth texture on it reads as paper at any distance."""
    crumpled = bool(params.get("crumpled", variant % 2 == 1))
    w_ = jit(rng, params.get("width", 0.21)) * CHUNK
    l = jit(rng, params.get("length", 0.25)) * CHUNK
    if crumpled:
        # A working rag. Layers of one even thickness read as folded card however good the
        # material is, so these differ in thickness, undulate along their own length, and
        # are then broken up by a jitter at 5 cm -- smaller than the rag, which is the
        # point: `finish`'s own jitter is fixed at 0.5 m and would only shift it sideways.
        mat = cloth_mat(pal, rng, role="earth", tint=0.5, age=0.85, wear=0.55, scale=0.30)
        used = "dyed_cloth"
        # The layers must not eat each other: the ripple runs on both faces of a fold with
        # no phase relation between them, so twice the ripple has to stay inside the
        # thinnest gap `rough` can produce, or the rag opens black slits where it folds.
        gap = 0.027 * CHUNK
        path = _fold_path(rng, l, 3, gap, slack=0.42, rough=0.62, fold_w=1.30)
        ripple, droop, jit_a = 0.0085, 0.006, 0.0026
    else:
        # washstand linen, folded and put away; its folds are pressed, not rolled
        mat = M.canvas(pal, age=0.35 + 0.3 * rng.random(), wear=0.30, scale=0.30)
        used = "canvas"
        gap = 0.019 * CHUNK
        path = _fold_path(rng, l, 3, gap, slack=0.06, rough=0.22, fold_w=0.85)
        ripple, droop, jit_a = 0.0085, 0.005, 0.0016
    body = B.cloth_run("cloth", path, w_, mat=mat, rng=rng, ripple=ripple, across=12,
                       thickness=0.0035, edge_droop=droop, wander=0.032 if crumpled else 0.018)
    S.shade_smooth(body, 50.0)
    S.jitter_verts(body, amount=jit_a, scale=0.05, seed=rng.randrange(999))
    if crumpled:
        S.tilt(body, rng, max_deg=3.0)
    else:
        body.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
        S.apply_transforms(body)
    return finish([body], rng, "convex", [used], extra={"crumpled": crumpled})


def spoon(pal, rng, params, variant):
    """A carved wooden spoon, lying bowl-down.

    It stands in for the ladle and the flour scoop as well, so the bowl is deep and wide
    rather than delicate: a shallow tasting spoon would look wrong hanging on a pot rack."""
    l = jit(rng, params.get("length", 0.25)) * CHUNK
    br = jit(rng, 0.042) * CHUNK          # bowl radius before it is drawn out into an oval
    depth = br * 0.68
    # No plank joint should ever cross a spoon: it is carved from one billet. The grain
    # wave in wood_planks is tied to `scale`, which is what gives it any grain at all here.
    mat = tool_wood(pal, rng, scale=0.80, wear=0.28, age=0.5, relief=0.06,
                    along="X", name="spoon_wood")
    t = br * 0.16                          # wall thickness
    prof = [(0.0, 0.0), (br * 0.45, depth * 0.10), (br * 0.80, depth * 0.40),
            (br * 0.97, depth * 0.86), (br, depth * 1.02),
            (br * 0.90, depth * 1.03), (br * 0.80, depth * 0.72),
            (br * 0.46, depth * 0.34), (0.0, t)]
    bowl = S.lathe("bowl", prof, segments=22, mat=mat, close=False)
    bowl.scale = Vector((1.28, 0.86, 1.0))
    S.apply_transforms(bowl)
    S.shade_smooth(bowl, 45.0)
    bowl.location = Vector((-l * 0.30, 0.0, 0.0))
    S.apply_transforms(bowl)
    # The handle leaves the bowl at its rim and settles again at the tip, so the spoon rests
    # on the bowl's underside and on its knob the way one actually lies on a table.
    #
    # It starts *in* the wall, not over the middle of the dish. It used to begin a bowl
    # radius in and a bowl depth up, which put the open mouth of the tube four millimetres
    # clear of the bowl's inner floor: the first render showed a handle hanging in the air
    # above an empty dish with a dark hole at its end. The bowl is scaled 1.28 in x after
    # it is lathed, so the wall on the handle's side stands at x = 0.90 * br * 1.28 from
    # the bowl's centre, and at that radius its two surfaces are at 0.67 and 1.03 of the
    # depth -- which is the band the tube's axis has to be in to be inside the timber.
    bowl_cx = -l * 0.30
    x0, x1 = bowl_cx + br * 1.28 * 0.90, l * 0.52
    path = [(x0, 0.0, depth * 0.85), (x0 + (x1 - x0) * 0.24, 0.0, depth * 0.94),
            (x0 + (x1 - x0) * 0.52, 0.0, depth * 0.84),
            (x0 + (x1 - x0) * 0.79, 0.0, depth * 0.64), (x1, 0.0, depth * 0.56)]
    handle = S.tube_along("handle", path, radius=br * 0.21, segments=8,
                          radius_end=br * 0.30, mat=mat)
    # Oval in section, wide across and thin through: a round dowel reads as a lollipop.
    _oval_along_x(handle, path, flat=0.72, wide=1.16)
    S.shade_smooth(handle, 45.0)
    knob = S.sphere("knob", radius=br * 0.30, subdivisions=2, location=(x1, 0, depth * 0.56),
                    mat=mat, scale=(0.7, 1.16, 0.74))
    S.apply_transforms(knob)
    parts = [bowl, handle, knob]
    for p in parts:
        S.jitter_verts(p, amount=0.0009, scale=0.09, seed=rng.randrange(999))
    return finish(parts, rng, "convex", ["wood_planks"])


def _oval_along_x(ob, path, flat=0.75, wide=1.15):
    """Squash a swept tube into an oval section about its own centre-line.

    `tube_along` sweeps a circle, and a circular section is what makes a carved handle or a
    hammer haft read as a dowel. The centre-line height is interpolated from the path so the
    squash follows the curve instead of flattening the whole object onto one plane."""
    xs = [p[0] for p in path]
    zs = [p[2] for p in path]

    def cz(x):
        if x <= xs[0]:
            return zs[0]
        for i in range(len(xs) - 1):
            if x <= xs[i + 1]:
                t = (x - xs[i]) / max(1e-9, xs[i + 1] - xs[i])
                return zs[i] + (zs[i + 1] - zs[i]) * t
        return zs[-1]

    for v in ob.data.vertices:
        c = cz(v.co.x)
        v.co.z = c + (v.co.z - c) * flat
        v.co.y *= wide


def _forged_leg(name, plan, z_mid, thick, mat, r_boss, r_tip):
    """One leg of a pair of tongs: a bar swept through a plan curve, then flattened.

    `plan` is [(x, y), ...] from the jaw tip to the rein end, passing through the boss at
    the origin; the bar is thickest at the boss and drawn down at both ends, which is the
    shape a leg takes under the hammer."""
    n = len(plan)
    pts = [(x, y, z_mid) for (x, y) in plan]
    ob = S.tube_along(name, pts, radius=r_boss, segments=7, mat=mat)
    # radius profile by hand: tube_along only tapers linearly end to end
    for v in ob.data.vertices:
        d = min(range(n), key=lambda i: (plan[i][0] - v.co.x) ** 2 + (plan[i][1] - v.co.y) ** 2)
        t = d / (n - 1)
        # 1.0 at the boss (mid), r_tip/r_boss at either end
        f = r_tip / r_boss + (1.0 - r_tip / r_boss) * math.sin(math.pi * t) ** 0.7
        v.co.x = plan[d][0] + (v.co.x - plan[d][0]) * f
        v.co.y = plan[d][1] + (v.co.y - plan[d][1]) * f
        v.co.z = z_mid + (v.co.z - z_mid) * f * thick
    return ob


def tongs(pal, rng, params, variant):
    """A smith's tongs, lying flat as they lie on the tool rack.

    Two legs riveted at the boss, jaws one side and reins the other, each leg a flat forged
    bar. The pair sit one above the other through their whole length, which is what a rivet
    through two bars actually gives you."""
    l = jit(rng, params.get("length", 0.46)) * CHUNK
    jaw = l * 0.27
    rein = l * 0.73
    metal = iron(pal, rng, age=0.55, wear=0.8, scale=0.14)
    bar = 0.009 * CHUNK
    parts = []
    # Jaws open a little, as tongs left on a rack are -- except the pair that still has the
    # work in them, which close on it. The docstring claimed that pair existed before the
    # code did; `variant` was not read at all and both pairs came out the same shape.
    gripping = bool(params.get("gripping", variant % 2 == 1))
    spread = params.get("spread", (bar * 1.15 if gripping else 0.016 + 0.020 * rng.random()))
    for sgn in (1, -1):
        plan = [(-jaw, sgn * spread * 0.55), (-jaw * 0.66, sgn * spread * 0.80),
                (-jaw * 0.30, sgn * spread * 0.55), (0.0, 0.0),
                (rein * 0.18, -sgn * bar * 1.5), (rein * 0.45, -sgn * bar * 2.6),
                (rein * 0.74, -sgn * bar * 3.2), (rein, -sgn * bar * 3.5)]
        z = bar * (1.55 if sgn > 0 else 0.55)
        leg = _forged_leg("leg_%d" % sgn, plan, z, 0.80, metal, bar * 1.25, bar * 0.62)
        S.shade_smooth(leg, 34.0)
        parts.append(leg)
    parts.append(S.cylinder("rivet", radius=bar * 0.72, depth=bar * 2.9, vertices=10,
                            location=(0, 0, -bar * 0.15), mat=metal))
    for z in (-bar * 0.2, bar * 2.7):
        parts.append(S.sphere("rivet_head", radius=bar * 0.95, subdivisions=2,
                              location=(0, 0, z), mat=metal, scale=(1, 1, 0.45)))
    if gripping:
        # A short bar of stock held in the jaws, standing out past the tips: it is what
        # makes the second pair a different silhouette and not merely a different seed.
        stock = S.box_centered("stock", (jaw * 1.30, bar * 0.95, bar * 1.05),
                               (-jaw * 1.05, 0.0, bar * 1.05), mat=metal)
        S.bevel(stock, width=bar * 0.16, segments=2, angle_deg=45)
        S.apply_transforms(stock)
        parts.append(stock)
    for p in parts:
        S.apply_transforms(p)
        S.jitter_verts(p, amount=0.0007, scale=0.07, seed=rng.randrange(999))
    return finish(parts, rng, "convex", ["iron"], extra={"gripping": gripping})


def hammer(pal, rng, params, variant):
    """A smith's cross-peen hand hammer, lying on its side.

    Built as its own thing and not as a pair of tongs: the smith's work clips are authored
    around a hammer, and a hammer is a head with an eye and a haft through it, which is a
    different silhouette from anything else on the rack (PROGRESS: "The smith has no
    hammer")."""
    haft_l = jit(rng, params.get("length", 0.33)) * CHUNK
    hw = jit(rng, 0.062) * CHUNK          # half the head's length, along Y
    hz = jit(rng, 0.022) * CHUNK          # half the head's depth
    metal = iron(pal, rng, age=0.5, wear=0.85, scale=0.10)
    ash = tool_wood(pal, rng, scale=0.70, wear=0.26, age=0.45, base_hex="#8a6c3e",
                    relief=0.08, along="X", name="haft_wood")
    parts = []
    eye = S.box_centered("eye", (hz * 1.66, hw * 0.62, hz * 2.0), (0, 0, 0), mat=metal)
    S.bevel(eye, width=hz * 0.13, segments=2, angle_deg=45)
    parts.append(eye)
    # A primitive keeps its `location` as an object transform, so a vertex edit after one is
    # built is in the primitive's OWN coordinates and not the ones its location implies. Both
    # of these tapers were first written against the placed coordinates, matched nothing at
    # all, and shipped a hammer whose head was a plain brick at both ends.
    face = S.box_centered("face", (hz * 1.58, hw * 0.60, hz * 1.80), (0, hw * 0.60, 0), mat=metal)
    for v in face.data.vertices:                       # local y in [-0.30, +0.30] * hw
        if v.co.y > hw * 0.24:
            v.co.x *= 0.87
            v.co.z *= 0.87
    S.bevel(face, width=hz * 0.17, segments=3, angle_deg=45)
    parts.append(face)
    # the peen: drawn down to a rounded chisel edge lying across the haft
    peen = S.box_centered("peen", (hz * 1.46, hw * 0.96, hz * 1.70), (0, -hw * 0.78, 0), mat=metal)
    for v in peen.data.vertices:                       # local y in [-0.48, +0.48] * hw
        if v.co.y < -hw * 0.30:
            k = (-v.co.y / hw - 0.30) / 0.18
            v.co.x *= 1.0 - 0.86 * min(1.0, k)
            v.co.z *= 1.0 - 0.10 * min(1.0, k)
    S.bevel(peen, width=hz * 0.09, segments=3, angle_deg=45)
    parts.append(peen)
    x0, x1 = -hz * 0.9, haft_l
    path = [(x0, 0, 0), (hz * 1.6, 0, -hz * 0.06), (haft_l * 0.45, 0, -hz * 0.16),
            (haft_l * 0.80, 0, -hz * 0.22), (x1, 0, -hz * 0.26)]
    haft = S.tube_along("haft", path, radius=hz * 0.42, segments=9, radius_end=hz * 0.56, mat=ash)
    _oval_along_x(haft, path, flat=1.12, wide=0.80)
    S.shade_smooth(haft, 45.0)
    parts.append(haft)
    # the wedge that holds the head on, stood proud of the eye
    wedge = S.box_centered("wedge", (hz * 0.28, hw * 0.48, hz * 0.34), (0, 0, hz * 0.95), mat=metal)
    S.bevel(wedge, width=hz * 0.04, segments=2)
    parts.append(wedge)
    for p in parts:
        S.jitter_verts(p, amount=0.0008, scale=0.08, seed=rng.randrange(999))
    return finish(parts, rng, "convex", ["iron", "wood_planks"])


def _leaf_blade(name, length, width, thick, mat, base_z=0.0, rib=1.0):
    """A leaf-shaped blade with a diamond section: spear heads, and any socketed point.

    Built ring by ring rather than as a solidified outline, because the section *is* the
    blade — a flat plate with a bevel around it reads as a cardboard cut-out."""
    prof = []
    n = 11
    for i in range(n + 1):
        t = i / n
        f = ((1.0 - t) ** 0.55) * (0.62 + 0.90 * math.sin(math.pi * t ** 0.8))
        prof.append((t, f))
    peak = max(f for _, f in prof)
    verts = []
    faces = []
    for i, (t, f) in enumerate(prof):
        z = base_z + t * length
        w = width * 0.5 * f / peak
        th = thick * 0.5 * (1.0 - t) ** 0.45 * (0.55 + 0.45 * rib)
        if i == n:
            verts.append((0.0, 0.0, z))
            break
        verts += [(w, 0.0, z), (0.0, th, z), (-w, 0.0, z), (0.0, -th, z)]
    tip = len(verts) - 1
    for i in range(n - 1):
        a, b = i * 4, (i + 1) * 4
        for k in range(4):
            faces.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
    a = (n - 1) * 4
    for k in range(4):
        faces.append((a + k, a + (k + 1) % 4, tip))
    faces.append((3, 2, 1, 0))
    ob = S.mesh_from_pydata(name, verts, faces, mat=mat, smooth=False)
    S.shade_smooth(ob, 32.0)
    return ob


def spear(pal, rng, params, variant):
    """An ash spear standing on its butt, leaning as a spear leans in a rack.

    Upright and not laid flat: the rack these go on is 1.8 m of wall and the placement
    gives every item its own random yaw, so a two-metre shaft laid down would swing out
    across the room. Standing, it keeps a hand's-breadth footprint at any yaw."""
    # Length is not chunked. A storey is 2.75 m, the rack stands things 0.78 m up and the
    # ceiling joists hang at about 2.6 m, so 1.1x here is the difference between a spear in
    # a rack and a spear through the ceiling. The stylisation goes into the shaft instead.
    h = jit(rng, params.get("height", 1.62))
    blade_l = h * 0.145
    shaft_r = 0.0165 * CHUNK
    metal = iron(pal, rng, age=0.45, wear=0.7, scale=0.12)
    # grain 0.09, for the same reason as the pitchfork: on a shaft this long even a quarter
    # of the default frequency is thirteen bands, and thirteen bands around a stick is a
    # thread, not ash.
    ash = tool_wood(pal, rng, scale=0.55, wear=0.25, age=0.5, base_hex="#8a6c3e",
                    relief=0.10, grain=0.09, along="Z", name="shaft_wood")
    cord = M.rope(pal, age=0.6, scale=0.05)
    shaft_top = h - blade_l - h * 0.035
    bow = h * 0.012 * rng.uniform(-1.0, 1.0)
    path = [(math.sin(i / 8.0 * math.pi) * bow, 0.0, shaft_top * i / 8.0) for i in range(9)]
    shaft = S.tube_along("shaft", path, radius=shaft_r * 1.06, segments=9,
                         radius_end=shaft_r * 0.92, mat=ash)
    S.shade_smooth(shaft, 45.0)
    parts = [shaft]
    # socket: a cone swaged down onto the shaft, with its seam rivet
    parts.append(S.lathe("socket", [(shaft_r * 1.18, shaft_top - h * 0.055),
                                    (shaft_r * 1.22, shaft_top - h * 0.030),
                                    (shaft_r * 1.05, shaft_top + h * 0.012),
                                    (shaft_r * 0.85, shaft_top + h * 0.034)],
                         segments=12, mat=metal, close=True))
    _zr = shaft_top - h * 0.030
    parts.append(S.sphere("socket_rivet", radius=shaft_r * 0.30, subdivisions=2,
                          location=(math.sin(_zr / shaft_top * math.pi) * bow + shaft_r * 1.1,
                                    0, _zr), mat=metal, scale=(0.5, 1, 1)))
    # A leaf, not a needle. At h * 0.036 the blade was four times as long as it was wide
    # and the render gave a knitting needle on a stick; a spear head you can name at a
    # glance is nearer two and a half to one.
    blade = _leaf_blade("blade", blade_l, h * 0.060, shaft_r * 1.05, metal,
                        base_z=shaft_top + h * 0.020, rib=1.0)
    blade.rotation_euler = Euler((0, 0, rng.uniform(0, TAU)))
    S.apply_transforms(blade)
    parts.append(blade)
    # butt ferrule, and a grip whipping of cord two hands down from the head
    parts.append(S.lathe("ferrule", [(shaft_r * 1.16, 0.0), (shaft_r * 1.20, h * 0.022),
                                     (shaft_r * 1.03, h * 0.050)],
                         segments=12, mat=metal, close=True))
    # On the shaft's own centre-line, not on the Z axis: the shaft is bowed by up to a
    # whole shaft radius at mid-height, so a ring hung on the axis bites into the stave on
    # one side and hangs off it on the other.
    for k in range(5):
        z = shaft_top * 0.62 + k * shaft_r * 0.66
        parts.append(B.rope_loop("whip_%d" % k, shaft_r * 1.05, shaft_r * 0.30, mat=cord,
                                 segments=12,
                                 location=(math.sin(z / shaft_top * math.pi) * bow, 0.0, z)))
    lean = params.get("lean", rng.uniform(3.5, 7.5)) * (1 if rng.random() < 0.5 else -1)
    stand_up(parts, lean)
    return finish(parts, rng, "convex", ["iron", "wood_planks", "rope"])


def _dome_strap(name, length, width, thick, dome, angle, mat, rng, rivets=3, steps=16):
    """An iron strap laid across a dished shield, following the dish.

    A straight bar set at one height over a domed board sinks into it at the middle and
    lifts off it at the ends: what you get is four floating tabs round a boss, not two
    straps crossing. So the bar is swept along the board's own surface.

    Built as a four-sided bar divided only along its length, which is the shape a strap
    actually is and costs a few dozen triangles. A box put through a subdivision fine enough
    to follow the dish is also divided across its width and through its thickness, and the
    first shield built that way came out at ten thousand triangles for a three-quarter-metre
    prop, against the five hundred to six thousand DESIGN 7.0 allows an ordinary one."""
    hw, ht = width * 0.5, thick
    verts, faces = [], []
    for i in range(steps + 1):
        x = (i / steps - 0.5) * length
        z0 = dome(abs(x)) - thick * 0.25
        verts += [(x, -hw, z0), (x, hw, z0), (x, hw, z0 + ht), (x, -hw, z0 + ht)]
    for i in range(steps):
        a, b = i * 4, (i + 1) * 4
        for k in range(4):
            faces.append((a + k, b + k, b + (k + 1) % 4, a + (k + 1) % 4))
    faces.append((3, 2, 1, 0))
    e = steps * 4
    faces.append((e, e + 1, e + 2, e + 3))
    ob = S.mesh_from_pydata(name, verts, faces, mat=mat, smooth=False)
    S.bevel(ob, width=thick * 0.30, segments=2, angle_deg=35)
    parts = [ob]
    for i in range(rivets):
        f = (i + 0.5) / rivets
        x = length * 0.5 * (0.18 + 0.78 * f)
        for sx in (-1, 1):
            parts.append(S.sphere("%s_rivet_%d_%d" % (name, i, sx), radius=thick * 0.62,
                                  subdivisions=1, location=(sx * x, 0, dome(x) + thick * 0.7),
                                  mat=mat, scale=(1, 1, 0.55)))
    joined = S.join(parts, name)
    joined.rotation_euler = Euler((0, 0, angle))
    S.apply_transforms(joined)
    return joined


def shield(pal, rng, params, variant):
    """A round board shield, stood on its rim and leaning back against what is behind it.

    Dished rather than flat, with an iron boss, a hide-bound rim and two straps across the
    face. Standing is the honest pose: on a rack at chest height a leaning shield reads as
    hung on the wall, which is where a shield lives, and it keeps a small footprint at the
    random yaw the placement gives it."""
    r = jit(rng, params.get("radius", 0.34)) * CHUNK
    # `along="XZ"`, not "X": the board is lathed flat and then stood up, and that rotation
    # is applied into object space, so plank rows asked for in the XY plane would run
    # through the twelve millimetres of board thickness and never be seen.
    # grain 0.08 across a 0.75 m board. The quarter a hand tool wants bands it every 53 mm,
    # which on a face this wide is fourteen stripes and reads as corduroy rather than as
    # boards; at 0.08 it is four soft tones across the face and the plank joints, which are
    # a separate pattern, are what the eye picks up.
    board = tool_wood(pal, rng, scale=0.30, wear=0.30, age=0.6, base_hex="#7d6138",
                      relief=0.16, grain=0.08, plank_len=2.6, plank_w=0.52, along="XZ",
                      name="shield_board")
    metal = iron(pal, rng, age=0.6, wear=0.7, scale=0.16)
    hide = M.leather(pal, age=0.75, wear=0.4, scale=0.10, base_hex="#4a3320")
    face_z = r * 0.075
    front = [(0.0, 1.00), (0.40, 0.86), (0.74, 0.54), (0.95, 0.10), (1.0, -0.16)]

    def dome(rr):
        """The height of the board's front face at radius `rr`, from the lathe profile."""
        t = min(1.0, rr / r)
        for (a, za), (b, zb) in zip(front, front[1:]):
            if t <= b:
                k = (t - a) / max(1e-9, b - a)
                return face_z * (za + (zb - za) * k)
        return face_z * front[-1][1]

    prof = [(r * a, face_z * z) for (a, z) in front]
    prof += [(r * 0.985, -face_z * 0.52), (r * 0.72, -face_z * 0.26),
             (r * 0.38, -face_z * 0.05), (0.0, face_z * 0.05)]
    disc = S.lathe("board", prof, segments=28, mat=board, close=False)
    S.shade_smooth(disc, 42.0)
    S.jitter_verts(disc, amount=r * 0.008, scale=0.12, seed=rng.randrange(999))
    parts = [disc]
    parts.append(B.hoop("rim", r * 0.995, r * 0.030, mat=hide, location=(0, 0, -face_z * 0.05),
                        segments=28, flatten=1.45))
    for i, a in enumerate((0.42, 2.51)):
        parts.append(_dome_strap("strap_%d" % i, r * 1.88, r * 0.125, r * 0.028, dome, a,
                                 metal, rng))
    bo = r * 0.23
    seat = dome(bo * 1.42)
    parts.append(S.lathe("boss", [(bo * 1.42, seat), (bo * 1.36, seat + face_z * 0.22),
                                  (bo * 1.00, seat + face_z * 0.36), (bo * 0.86, seat + face_z * 0.82),
                                  (bo * 0.44, seat + face_z * 1.16), (0.0, seat + face_z * 1.24)],
                         segments=20, mat=metal, close=True))
    S.shade_smooth(parts[-1], 40.0)
    for i in range(6):
        a = TAU * i / 6 + 0.3
        rr = bo * 1.22
        parts.append(S.sphere("boss_rivet_%d" % i, radius=bo * 0.11, subdivisions=1,
                              location=(math.cos(a) * rr, math.sin(a) * rr, dome(rr)),
                              mat=metal, scale=(1, 1, 0.55)))
    # the grip behind the boss, seen when the shield is leaned face-out
    parts.append(B.board("grip", r * 0.86, r * 0.10, r * 0.035, mat=board,
                         location=(0, 0, -face_z * 0.42), rotation=(0, 0, 90)))
    lean = params.get("lean", rng.uniform(9.0, 15.0))
    stand_up(parts, 90.0 - lean)
    return finish(parts, rng, "convex", ["wood_planks", "iron", "leather"])


def pitchfork(pal, rng, params, variant):
    """A hayfork: ash shaft, forged socket, three drawn tines, stood tines-up.

    Also the written stand-in for a scythe, so the head is kept plainly agricultural rather
    than specific to hay."""
    h = jit(rng, params.get("height", 1.68)) * CHUNK
    shaft_r = 0.0185 * CHUNK
    tine_l = h * 0.21
    metal = iron(pal, rng, age=0.7, wear=0.8, scale=0.13)
    # grain 0.09: the wave bands every scale/(22.5*grain) metres, so on a 1.4 m shaft the
    # 0.25 a hand tool wants would still be thirteen rings of tone around a stick. Five is
    # a stave; thirteen is a screw thread, which is what the first render showed.
    ash = tool_wood(pal, rng, scale=0.55, wear=0.28, age=0.65, base_hex="#7f6236",
                    relief=0.10, grain=0.09, along="Z", name="shaft_wood")
    shaft_top = h - tine_l - h * 0.045
    bow = h * 0.016 * rng.uniform(-1.0, 1.0)
    # Sixteen segments, not eight: the hand swell below is the shaft's own vertices, and
    # eight rings over a metre and a half put two of them inside the grip.
    path = [(math.sin(i / 16.0 * math.pi) * bow, 0.0, shaft_top * i / 16.0) for i in range(17)]
    shaft = S.tube_along("shaft", path, radius=shaft_r * 1.10, segments=9,
                         radius_end=shaft_r * 0.94, mat=ash)
    S.shade_smooth(shaft, 45.0)
    parts = [shaft]
    parts.append(S.lathe("socket", [(shaft_r * 1.20, shaft_top - h * 0.060),
                                    (shaft_r * 1.26, shaft_top - h * 0.028),
                                    (shaft_r * 1.10, shaft_top + h * 0.018),
                                    (shaft_r * 0.96, shaft_top + h * 0.042)],
                         segments=12, mat=metal, close=True))
    spread = h * 0.052
    z0 = shaft_top + h * 0.036
    for i in (-1, 0, 1):
        pts = []
        for k in range(7):
            t = k / 6.0
            pts.append((i * spread * t ** 0.75, 0.0,
                        z0 + tine_l * t - tine_l * 0.06 * math.sin(math.pi * t)))
        parts.append(S.tube_along("tine_%d" % i, pts, radius=shaft_r * 0.46, segments=7,
                                  radius_end=shaft_r * 0.06, mat=metal))
    parts.append(B.hoop("collar", shaft_r * 1.22, shaft_r * 0.16, mat=metal,
                        location=(0, 0, shaft_top - h * 0.050), segments=14, flatten=1.6))
    # A worn swell where two generations of hands have held it -- and it is the shaft's own
    # vertices, not a separate piece. As its own lathe on the Z axis it was inside the
    # shaft at one end and outside it at the other, because the shaft tapers and bows
    # besides, and the two surfaces crossing drew a hard dark seam down the render. Swept
    # along the shaft's real centre-line instead it stayed concentric but still left the
    # crevice where a ten-sided sleeve cuts a nine-sided stick: a sawtooth ring of ambient
    # occlusion at each end of the grip, which is not what worn ash looks like. One
    # surface has no crevice to occlude.
    gz0, gz1 = h * 0.16, h * 0.35
    for v in shaft.data.vertices:
        if gz0 <= v.co.z <= gz1:
            t = (v.co.z - gz0) / (gz1 - gz0)
            cx = math.sin(v.co.z / shaft_top * math.pi) * bow
            f = 1.0 + 0.16 * math.sin(math.pi * t) ** 0.7
            v.co.x = cx + (v.co.x - cx) * f
            v.co.y *= f
    lean = params.get("lean", rng.uniform(4.0, 9.0)) * (1 if rng.random() < 0.5 else -1)
    stand_up(parts, lean)
    return finish(parts, rng, "convex", ["iron", "wood_planks"])


def whetstone(pal, rng, params, variant):
    """A hone stone, dished in the middle by years of the same stroke.

    Its own mesh rather than a stand-in, because a whetstone is a 0.2 m block and the thing
    it used to borrow was a 0.46 m pair of tongs."""
    l = jit(rng, params.get("length", 0.20)) * CHUNK
    w_ = jit(rng, 0.052) * CHUNK
    t = jit(rng, 0.040) * CHUNK
    # Not granite. Granite carries a heavy speckle, a yellow lichen and a strong facet
    # field; at a 0.2 m object's scale those turn a hone into a lump of coal in snow. Lake
    # stone is the substance a hone actually is -- dark, close-grained, faintly glossy where
    # it has been rubbed -- and it takes the local palette like every other material here.
    #
    # `scale` is a feature size in metres and 0.10 was near the stone's own thickness, so
    # lake_stone's bedding banded it every seven millimetres and its 40 mm bedding bump --
    # an absolute, not a fraction of `scale` -- stood the bands proud: the first render
    # gave a hone whose sides were courses of stacked slate. A hone is close-grained; it
    # wants one tone, so the features go well past the object and the relief comes down.
    stone = M.lake_stone(pal, wear=0.30, age=0.35, tint=0.10, scale=0.45, relief=0.10,
                         name="hone_stone")
    body = S.box_centered("hone", (l, w_, t), (0, 0, 0), mat=stone)
    S.subdivide(body, levels=3, simple=True)   # dissolved back to the dish below
    dish = t * params.get("dish", 0.20 + 0.16 * rng.random())
    for v in body.data.vertices:
        u = abs(v.co.x) / (l * 0.5)
        k = abs(v.co.y) / (w_ * 0.5)
        hollow = dish * max(0.0, 1.0 - u ** 2.2) * max(0.0, 1.0 - k ** 3.0)
        if v.co.z > 0:
            v.co.z -= hollow
        else:
            v.co.z += hollow * 0.35
    # Everything but the dished face is still flat, and a flat face cut into sixty-four
    # pieces is sixty-three wasted triangles on a 0.2 m object. The planar dissolve keeps
    # the curvature and gives the rest back.
    S.decimate(body, ratio=1.0, planar_deg=4.0)
    S.bevel(body, width=min(w_, t) * 0.16, segments=2, angle_deg=40)
    S.jitter_verts(body, amount=0.0012, scale=0.05, seed=rng.randrange(999))
    S.shade_smooth(body, 36.0)
    parts = [body]
    if params.get("bedded", variant % 2 == 1):
        # bedded in an oak block, the way a hone that lives on one bench is kept
        oak = tool_wood(pal, rng, scale=0.60, wear=0.25, age=0.7, relief=0.09,
                        along="X", name="hone_block")
        bed = S.box_centered("block", (l * 1.18, w_ * 2.1, t * 0.72), (0, 0, -t * 0.62), mat=oak)
        S.bevel(bed, width=t * 0.07, segments=2, angle_deg=40)
        S.jitter_verts(bed, amount=0.0012, scale=0.08, seed=rng.randrange(999))
        parts.append(bed)
    # One tilt for the whole assembly, not one for the hone alone: tilting the stone inside
    # its block sank one end of it into the oak and lifted the other clear of it.
    rot = Euler((math.radians(rng.uniform(-2.0, 2.0)), math.radians(rng.uniform(-2.0, 2.0)),
                 rng.uniform(0.0, TAU)), "XYZ")
    for p in parts:
        S.apply_transforms(p)
        p.rotation_euler = rot
        S.apply_transforms(p)
    return finish(parts, rng, "convex", ["lake_stone", "wood_planks"])


# =========================================================================================
# the mill, the bakehouse, the woodpile and the peat bank
#
# The last four kinds an interior asks for by name and the forge had never made. The first
# two were drawn as labelled placeholders in Maud's bakehouse and Pennywort's Mill; the
# other two were worn by a village work station as a crate and a bucket, because a chopping
# block and a peat bank did not exist to wear.
# =========================================================================================

def _hewn_billet(name, radius, height, mat, rng, sides=9, taper=0.955, jitter=0.04):
    """A length of trunk hewn to an odd number of flats and stood on its end.

    Nine sides put 40 degrees between facets, more than the exporter's 35 degree smoothing
    angle, so it stays faceted and reads as axe-work rather than as a turned drum; an odd
    number and a per-facet radius stop it reading as a barrel."""
    log = S.lathe(name, [(radius * 1.10, 0.0), (radius * 1.02, height * 0.13),
                         (radius * 0.97, height * 0.52), (radius * 0.99, height * 0.86),
                         (radius * taper, height)],
                  segments=sides, mat=mat, close=True)
    facet = [rng.uniform(0.93, 1.05) for _ in range(sides)]
    for v in log.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if rr > 1e-6:
            f = facet[int(round((math.atan2(v.co.y, v.co.x) % TAU) / TAU * sides)) % sides]
            v.co.x *= f
            v.co.y *= f
    S.jitter_verts(log, amount=radius * jitter, scale=0.22, seed=rng.randrange(999))
    return log


def loaf(pal, rng, params, variant):
    """A baked loaf, risen and scored, for Maud's bread shelf.

    Three of these stand in a row on one shelf, so the two variants have to differ in
    silhouette and not only in seed: a round cob scored with a cross, and a long batch loaf
    with diagonal slashes down its back. The scores are cut into the mesh rather than drawn
    in the texture, because what says `bread` at two metres is the split crust catching the
    light along its edge, and a painted line does not catch anything."""
    long_loaf = bool(params.get("long", variant % 2 == 1))
    w_ = jit(rng, params.get("width", 0.20))
    l = w_ * (1.55 if long_loaf else 1.0)
    # 0.076 and not the 0.090 `HouseInterior._placeholder_size` writes down, because the
    # written size is the finished loaf and this one is the dough: the scores lift a
    # shoulder either side of every cut, and at 0.090 the baked loaf came out at 0.114 m
    # and 27% over its own spec.
    h = jit(rng, params.get("height", 0.076))
    crust = M.bread(pal, bake=0.55 + 0.35 * rng.random(), flour=0.35 + 0.3 * rng.random(),
                    scale=0.22, name="loaf_crust")
    # Five subdivisions and then decimated back: the scores are cut into the mesh, and at
    # four the sphere had too few vertices across a score to carry one.
    body = S.sphere("loaf", radius=0.5, subdivisions=5, mat=crust)
    S.apply_transforms(body)
    # The dough sits down on the tray and rises up and outward: wider at the waist than at
    # the foot, and flat underneath. A plain squashed ball reads as a stone.
    for v in body.data.vertices:
        t = v.co.z + 0.5                        # 0 at the bottom of the ball, 1 at the top
        flare = 0.82 + 0.30 * math.sin(math.pi * min(1.0, t * 0.92))
        v.co.x *= l * flare
        v.co.y *= w_ * flare
        # The underside is flat: the bottom fifth of the ball is folded onto the peel, so
        # the loaf sits on a base the width of its waist instead of balancing on a point.
        v.co.z = h * max(0.0, t - 0.20) / 0.80
    # The scores: valleys where the baker's blade opened the crust, with the crust lifted
    # into a shoulder on either side. One smooth function of the distance from the cut, and
    # not a valley term plus a separate lip term: the first pass added the lip only to the
    # vertices that fell in a narrow band, and on a sphere whose vertices are nowhere near
    # a grid that gave a ring of spikes -- a bread roll in a paper crown. (u^2 - 1)e^(-u^2/2)
    # is -1 at the cut, rises to a shoulder about one and a half widths out and dies away,
    # and every vertex is somewhere on it.
    cuts = ([(0.0, 1.0), (1.0, 0.0)] if not long_loaf
            else [(0.80, 0.60)] * 3)
    offs = [0.0, 0.0] if not long_loaf else [-l * 0.62, 0.0, l * 0.62]
    sigma = w_ * 0.115
    for (dx, dy), off in zip(cuts, offs):
        n = math.hypot(dx, dy)
        dx, dy = dx / n, dy / n
        for v in body.data.vertices:
            # fades out down the sides: a blade opens the crown, not the waist
            lift = min(1.0, max(0.0, (v.co.z / h - 0.30) / 0.50))
            if lift <= 0.0:
                continue
            u = abs((v.co.x - off) * dy - v.co.y * dx) / sigma
            if u > 3.2:
                continue
            v.co.z += h * 0.34 * lift * (u * u - 1.0) * math.exp(-u * u * 0.5)
    S.jitter_verts(body, amount=w_ * 0.010, scale=0.09, seed=rng.randrange(999))
    S.shade_smooth(body, 38.0)
    S.decimate(body, ratio=0.30)
    body.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
    S.apply_transforms(body)
    return finish([body], rng, "convex", ["bread"], extra={"long": long_loaf})


def millstone(pal, rng, params, variant):
    """A dressed millstone lying flat on the mill floor: two metres across, eyed and harped.

    The thing that makes a disc of gritstone a millstone is the dressing -- the furrows cut
    from the eye out to the skirt in straight-sided groups, so the meal is cut and driven
    outward rather than merely crushed. They are cut into the mesh for the same reason the
    loaf's scores are: this stone is the centre of a room a player walks around, and a
    furrow that is only a dark line in the albedo vanishes the moment the light moves."""
    r = jit(rng, params.get("radius", 1.0))
    h = jit(rng, params.get("thickness", 0.40))
    eye = r * params.get("eye", 0.21)
    harps = int(params.get("harps", 12))
    # Granite's defaults are a boulder's: grey, cool and a third covered in yellow lichen,
    # which on a two-metre disc under a mill roof read as a pale mossy cheese. A working
    # stone is swept, wetted and dressed every week and grows nothing; it is the warm dry
    # colour of quarried grit. Same rock, different life.
    stone = M.granite(pal, wear=0.45, age=0.7, tint=0.16, tint_role="earth",
                      base_hex="#5d544a", lichen=0.0, facet=0.35, scale=0.60,
                      name="mill_grit")
    metal = iron(pal, rng, age=0.85, wear=0.55, scale=0.18)
    segs = 120        # ten segments to a furrow group, so the land has a shape to read
    # An annulus in section: up the eye, out across the grinding face, down the skirt and
    # back under. The profile closes on itself, so no cap is wanted at either end.
    face_ring = [0.30, 0.52, 0.72, 0.87, 0.96]
    prof = [(eye, h * 0.06), (eye * 1.03, h * 0.94), (eye * 1.12, h)]
    for f in face_ring:
        # The face is worn hollow: a stone that has ground for a generation is lowest a
        # third of the way out and lifts again at the skirt where the meal leaves it.
        prof.append((r * f, h - h * 0.045 * math.sin(math.pi * min(1.0, f / 0.96))))
    prof += [(r, h * 0.88), (r, h * 0.12), (r * 0.96, 0.0),
             (eye * 1.30, 0.0), (eye, h * 0.06)]
    disc = S.lathe("stone", prof, segments=segs, mat=stone, close=False)
    # the harp: groups of furrows, each group a straight-sided land falling to a deep edge
    for v in disc.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if v.co.z < h * 0.80 or rr < eye * 1.25 or rr > r * 0.99:
            continue
        a = (math.atan2(v.co.y, v.co.x) % TAU) / TAU * harps
        t = a - math.floor(a)                    # 0 at the cutting edge, 1 at the back
        # Deep enough to be seen from standing height across a mill floor. At a fortieth of
        # the thickness the dressing was there in the mesh and invisible in the render,
        # which is the same as not being there.
        v.co.z -= h * 0.16 * (1.0 - t) ** 2.2
    S.jitter_verts(disc, amount=r * 0.004, scale=0.35, seed=rng.randrange(999))
    # 22 degrees, not 30: the furrow's cutting edge is a hard step and the smoothing angle
    # is what decides whether it stays one.
    S.shade_smooth(disc, 22.0)
    parts = [disc]
    # The rynd: the iron cross bedded in the eye that the spindle drives the stone by.
    for i in range(2):
        parts.append(B.iron_strap("rynd_%d" % i, eye * 2.5, eye * 0.42, eye * 0.16,
                                  mat=metal, location=(0, 0, h - eye * 0.10),
                                  rotation=(0, 0, 90 * i)))
    parts.append(S.lathe("rynd_boss", [(eye * 0.52, h - eye * 0.16), (eye * 0.58, h + eye * 0.10),
                                       (eye * 0.30, h + eye * 0.16), (0.0, h + eye * 0.16)],
                         segments=16, mat=metal, close=True))
    # a lifting band round the skirt, and the two eyes it is slung from
    parts.append(B.hoop("band", r * 1.005, h * 0.045, mat=metal,
                        location=(0, 0, h * 0.50), segments=segs // 2, flatten=2.4))
    for sx in (-1, 1):
        parts.append(S.sphere("lug_%d" % sx, radius=h * 0.085, subdivisions=2,
                              location=(sx * r * 1.01, 0, h * 0.50), mat=metal,
                              scale=(0.6, 1.0, 1.0)))
    return finish(parts, rng, "trimesh", ["granite", "iron"])


def chopping_block(pal, rng, params, variant):
    """A block with an axe left standing in it: the shape that says `firewood` at a glance.

    A village work station wears one prop and has to be read across a yard, so the axe is
    what the prop is for -- a bare stump is a seat, a bollard or a bit of scenery, and only
    the helve standing out of the end names the work. It is left bitten in at an angle,
    because an axe parked upright in a block looks placed and an axe leaning looks used."""
    r = jit(rng, params.get("radius", 0.21)) * CHUNK
    h = jit(rng, params.get("height", 0.44)) * CHUNK
    oak = tool_wood(pal, rng, scale=0.24, wear=0.12, age=0.55, base_hex="#4a331c",
                    tint=0.16, relief=0.28, grain=0.40, along="Z", name="block_oak")
    end = tool_wood(pal, rng, scale=0.20, wear=0.18, age=0.35, base_hex="#7a5c34",
                    tint=0.22, relief=0.10, grain=0.30, along="Z", name="block_end")
    metal = iron(pal, rng, age=0.5, wear=0.85, scale=0.11)
    helve_wood = tool_wood(pal, rng, scale=0.55, wear=0.24, age=0.45, base_hex="#8a6c3e",
                           relief=0.08, grain=0.12, along="X", name="helve_wood")
    block = _hewn_billet("block", r, h, oak, rng, sides=9)
    # The end grain is a different surface from the bark side and a chopping block is all
    # end grain on top: pale, split and hacked. It is a second material on the billet's own
    # top faces, not a disc laid over them -- a disc standing two millimetres proud read as
    # a lid, and the block as a barrel.
    S.assign_material_to_faces(block, end,
                               lambda f: f.normal.z > 0.7 and f.center.z > h * 0.90)
    parts = [block]
    # the axe, bitten in off centre and leaning back over the block
    lean = params.get("lean", rng.uniform(26.0, 38.0))
    bx = r * rng.uniform(-0.25, 0.25)
    hl = jit(rng, 0.46) * CHUNK
    hlen, bw, bd = 0.150, 0.056, 0.016      # head length, half its depth, half its thickness
    bite = 0.026                            # how far the edge is in, measured from the top
    # The head is built with its edge on the local z=0 plane and its eye above, so placing
    # the axe is a matter of saying where the edge bit and not of solving for the middle.
    # Built centred on the origin, the first version buried all but a couple of millimetres
    # of a hand's-breadth head in the block: the render gave a stick standing in a stump.
    head = S.box_centered("axe_head", (hlen, bd * 2.0, bw * 2.0), (0, 0, bw), mat=metal)
    for v in head.data.vertices:            # drawn down to a cutting edge at -x, and flared
        if v.co.x < -hlen * 0.14:
            v.co.y *= 0.22
            v.co.z = bw + (v.co.z - bw) * 1.24
    S.bevel(head, width=0.005, segments=2, angle_deg=45)
    eye = S.cylinder("axe_eye", radius=bd * 1.55, radius_top=bd * 1.40, depth=bw * 1.7,
                     vertices=10, location=(hlen * 0.40, 0, bw * 0.35), mat=metal)
    helve = S.tube_along("helve", [(hlen * 0.40, 0.0, bw * 0.6), (hlen * 0.40, 0.0, bw + hl * 0.40),
                                   (hlen * 0.34, 0.0, bw + hl * 0.72), (hlen * 0.24, 0.0, bw + hl)],
                         radius=bd * 0.98, segments=8, radius_end=bd * 1.25, mat=helve_wood)
    S.shade_smooth(helve, 45.0)
    axe = [head, eye, helve]
    yaw = rng.uniform(0.0, TAU)
    for p in axe:
        S.apply_transforms(p)
        p.rotation_euler = Euler((0.0, math.radians(-lean), 0.0))
        S.apply_transforms(p)
        p.location = Vector((bx, 0.0, h - bite))
        S.apply_transforms(p)
        p.rotation_euler = Euler((0.0, 0.0, yaw))
        S.apply_transforms(p)
    parts += axe
    # splits and a chip or two left where they fell
    chip_wood = tool_wood(pal, rng, scale=0.30, wear=0.22, age=0.4, base_hex="#7a5c34",
                          relief=0.10, grain=0.30, along="X", name="chip_wood")
    for i in range(int(params.get("chips", 3))):
        a = rng.uniform(0, TAU)
        d = r * rng.uniform(1.15, 1.75)
        c = S.box_centered("chip_%d" % i, (rng.uniform(0.05, 0.09), rng.uniform(0.018, 0.032),
                                           rng.uniform(0.012, 0.022)),
                           (math.cos(a) * d, math.sin(a) * d, 0.010), mat=chip_wood)
        S.bevel(c, width=0.003, segments=1, angle_deg=40)
        S.apply_transforms(c)
        S.tilt(c, rng, max_deg=22.0)
        S.jitter_verts(c, amount=0.002, scale=0.06, seed=rng.randrange(999))
        parts.append(c)
    return finish(parts, rng, "convex", ["wood_planks", "iron"])


def peat_stack(pal, rng, params, variant):
    """Cut peat stacked to dry, with the spade left standing in the bank beside it.

    A peat rickle is built loose on purpose -- turves laid across each other with the wind
    left a way through -- so this is not a wall of bricks: each course crosses the one
    under it, every turf is its own slab with its own lean, and the top course is short
    because a stack is built until the barrow is empty."""
    w_ = jit(rng, params.get("width", 0.96)) * CHUNK
    d = jit(rng, params.get("depth", 0.62)) * CHUNK
    courses = int(params.get("courses", 5))
    # One turf is a brick, not a sleeper. Cut with a spade it comes out about the length of
    # a forearm and a hand across; the first pass ran each one the whole depth of the stack
    # and gave a timber crib with a peat texture on it.
    tw, tt = 0.135, 0.078                                 # a turf across, and its thickness
    peat = M.wet_mud(pal, age=0.85, tint=0.12, scale=0.30, base_hex="#241a12",
                     name="cut_peat")
    parts = []
    for c in range(courses):
        z = tt * (c + 0.5) * 0.98
        across = (c % 2 == 0)
        span, run = (w_, d) if across else (d, w_)
        n = max(3, int(span / (tw * 1.10)) - (1 if c == courses - 1 else 0))
        rows = max(2, int(round(run / (tw * 2.1))))
        for i in range(n):
            off = -span * 0.5 + span * (i + 0.5) / n
            for j in range(rows):
                roff = -run * 0.5 + run * (j + 0.5) / rows
                tl = (run / rows) * rng.uniform(0.86, 0.97)
                loc = (off, roff, z) if across else (roff, off, z)
                tww = tw * rng.uniform(0.84, 0.96)
                size = (tww, tl, tt * rng.uniform(0.86, 1.0)) if across \
                    else (tl, tww, tt * rng.uniform(0.86, 1.0))
                t = S.box_centered("turf_%d_%d_%d" % (c, i, j), size, loc, mat=peat)
                S.bevel(t, width=0.007, segments=2, angle_deg=40)
                S.apply_transforms(t)
                t.rotation_euler = Euler((math.radians(rng.uniform(-4, 4)),
                                          math.radians(rng.uniform(-4, 4)),
                                          math.radians(rng.uniform(-6, 6))))
                S.apply_transforms(t)
                S.jitter_verts(t, amount=0.006, scale=0.07, seed=rng.randrange(999))
                parts.append(t)
    # the tusker: a long-handled peat spade with a wing on one side of the blade
    metal = iron(pal, rng, age=0.7, wear=0.85, scale=0.11)
    ash = tool_wood(pal, rng, scale=0.55, wear=0.26, age=0.5, base_hex="#8a6c3e",
                    relief=0.10, grain=0.09, along="Z", name="tusker_wood")
    sx = w_ * 0.52 + 0.11
    sh = jit(rng, 1.24)
    shaft_r = 0.019
    shaft = S.tube_along("tusker", [(sx, 0.0, 0.10), (sx, 0.0, sh * 0.55), (sx, 0.0, sh)],
                         radius=shaft_r * 1.05, segments=8, radius_end=shaft_r * 0.92, mat=ash)
    S.shade_smooth(shaft, 45.0)
    parts.append(shaft)
    parts.append(B.board("tusker_grip", 0.15, 0.036, 0.026, mat=ash,
                         location=(sx, 0, sh), rotation=(0, 0, 90), chamfer=0.006))
    blade = S.box_centered("tusker_blade", (0.052, 0.008, 0.26), (sx, 0.0, 0.10), mat=metal)
    S.bevel(blade, width=0.004, segments=2, angle_deg=45)
    parts.append(blade)
    wing = S.box_centered("tusker_wing", (0.008, 0.075, 0.175), (sx - 0.026, 0.036, 0.13),
                          mat=metal)
    S.bevel(wing, width=0.003, segments=2, angle_deg=45)
    parts.append(wing)
    for p in parts[-4:]:
        S.apply_transforms(p)
        p.rotation_euler = Euler((0.0, math.radians(params.get("spade_lean", 11.0)), 0.0))
        S.apply_transforms(p)
    # `tier="tiny"` forces a 256 atlas although the stack is more than a metre across.
    # `pick_resolution` goes on the bounding radius, which is the right rule for a prop
    # whose surface is one continuous thing; this one is fifty separate blocks of one dark,
    # near-featureless peat, and at 512 it was the heaviest asset in the props tree for no
    # visible return. Checked against the 512 bake side by side before it was cut.
    return finish(parts, rng, "convex", ["wet_mud", "iron", "wood_planks"], tier="tiny")


# =========================================================================================
# the props the stand-ins were lying about the size of
#
# `PropLibrary.STAND_IN` lets a kind the forge has not built borrow the nearest mesh it has,
# and eleven of those borrowings were wrong about *scale*: a pair of boots drawn as a
# three-quarter-metre sack, a hand lantern as a two-metre standing one, a brewing copper as
# a cooking pot a third of its height, a bowl as a 34 mm plate. A labelled box admits what
# it is; a sack pretending to be a boot does not, and it is the character moving past it
# that gives the lie away.
#
# Every one of these is built to the size `HouseInterior._placeholder_size` writes down,
# because that table is the only written specification of how big these things are. They
# run from 0.06 m to 0.95 m, so every material takes a feature scale near its own object's
# size (tools/forge/README.md, "The scale constant").
# =========================================================================================

def _clay(pal, rng, role, scale, top_z, relief=0.25, name="clay", **kw):
    """Earthenware for something you could pick up: glaze poured from this object's own rim.

    `ceramic`'s glaze mask is a height in object-space metres and its default band, 50 to
    250 mm, is a mug's. Below 50 mm -- which is all of a bowl and most of a jar -- the whole
    term reads zero and the pot comes out unglazed but for the drips."""
    kw.setdefault("glaze", 0.4 + 0.35 * rng.random())
    kw.setdefault("age", 0.3 + 0.4 * rng.random())
    return M.ceramic(pal, role=role, scale=scale, glaze_z=top_z, relief=relief, name=name, **kw)


def bowl(pal, rng, params, variant):
    """A deep earthenware bowl: what is on the table in every hearth room in the country.

    It stood in as `plate`, which is a 34 mm dish for a 90 mm bowl -- the difference between
    the thing you eat off and the thing you eat out of, and the one that holds the stew."""
    r = jit(rng, params.get("radius", 0.097)) * CHUNK
    h = jit(rng, params.get("height", 0.081)) * CHUNK
    foot = r * 0.44
    t = r * 0.085                                     # the wall, thrown thick
    mat = _clay(pal, rng, "cool" if variant % 2 else "earth", 0.30, (h * 0.52, h * 1.02),
                name="bowl_clay")
    # Outside up from the foot, over the rim, and back down the inside to the floor. Both
    # ends of the profile are on the axis, so the poles close the shell without a cap.
    prof = [(0.0, 0.003), (foot * 0.86, 0.0), (foot, 0.002), (foot * 1.04, h * 0.15),
            (r * 0.78, h * 0.50), (r * 0.96, h * 0.86), (r, h * 0.97), (r * 0.99, h),
            (r * 0.99 - t, h * 0.985), (r * 0.94 - t, h * 0.84), (r * 0.76 - t, h * 0.50),
            (foot * 0.92, h * 0.19), (foot * 0.5, h * 0.155), (0.0, h * 0.15)]
    body = S.lathe("bowl", prof, segments=26, mat=mat, close=False)
    S.shade_smooth(body, 42.0)
    # Thrown, not moulded: the rim is never quite round and never quite level.
    for v in body.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        f = 1.0 + 0.012 * math.cos(a * 3.0 + 0.7)
        v.co.x *= f
        v.co.y *= f
        v.co.z += 0.004 * h * math.sin(a * 2.0) * (v.co.z / max(h, 1e-6))
    S.jitter_verts(body, amount=r * 0.008, scale=0.07, seed=rng.randrange(999))
    body.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
    S.apply_transforms(body)
    return finish([body], rng, "convex", ["ceramic"])


def _plate_disc(name, r, rim_h, mat):
    """One plate: a shallow well, a canted flange and a foot, thin enough to stack."""
    prof = [(0.0, rim_h * 0.10), (r * 0.30, rim_h * 0.12), (r * 0.46, rim_h * 0.05),
            (r * 0.52, rim_h * 0.06), (r * 0.58, rim_h * 0.22), (r * 0.86, rim_h * 0.74),
            (r, rim_h), (r * 0.985, rim_h * 0.92), (r * 0.82, rim_h * 0.60),
            (r * 0.54, rim_h * 0.12), (r * 0.40, rim_h * 0.02), (0.0, rim_h * 0.04)]
    ob = S.lathe(name, prof, segments=18, mat=mat, close=False)
    S.shade_smooth(ob, 40.0)
    return ob


def plate_stack(pal, rng, params, variant):
    """Plates put away in a stack on the sideboard: six of them, nested, none quite square.

    A stack is not a plate: it borrowed one and came out 34 mm tall for a thing written down
    at 90. Nesting is what makes six plates 81 mm rather than 204 -- each sits down inside
    the one below and only its flange shows, which is also what says `stack` at a glance."""
    n = int(params.get("count", 6 if variant % 2 == 0 else 5))
    r = jit(rng, params.get("radius", 0.096)) * CHUNK
    rim = 0.0185 * CHUNK
    step = 0.0128 * CHUNK
    # Two clays for the set, not one per plate: a bake is per material slot, and six of
    # them costs six ambient-occlusion passes for a difference nobody can see. Two
    # alternating is what a household's plates look like anyway -- bought in twos.
    clays = [_clay(pal, rng, role, 0.34, (rim * 0.3, rim * 1.1), glaze=0.3 + 0.25 * rng.random(),
                   name="plate_clay_%d" % k) for k, role in enumerate(("light", "earth"))]
    parts = []
    for i in range(n):
        mat = clays[i % 2]
        rr = r * rng.uniform(0.975, 1.0)
        p = _plate_disc("plate_%d" % i, rr, rim, mat)
        # A hand puts each one down a little off the last: a stack of plates squared up to
        # the millimetre is a machined column, and the flange edges are the whole read.
        p.location = Vector((rng.uniform(-1, 1) * r * 0.02, rng.uniform(-1, 1) * r * 0.02,
                             step * i))
        S.apply_transforms(p)
        p.rotation_euler = Euler((math.radians(rng.uniform(-1.1, 1.1)),
                                  math.radians(rng.uniform(-1.1, 1.1)),
                                  rng.uniform(0.0, TAU)))
        S.apply_transforms(p)
        parts.append(p)
    return finish(parts, rng, "convex", ["ceramic"], extra={"count": n})


def paper_stack(pal, rng, params, variant):
    """Loose leaves on a writing desk, squared up by hand and not by a press.

    It stood in as a scroll: 340 mm of rolled parchment for a 60 mm pile of flat sheets."""
    w_ = jit(rng, params.get("width", 0.200))
    d = jit(rng, params.get("depth", 0.148))
    loose = int(params.get("loose", 4 if variant % 2 == 0 else 3))
    parts = []
    papers = [M.parchment(pal, age=0.30 + 0.22 * k + 0.1 * rng.random(), scale=0.26,
                          name="leaf_paper_%d" % k) for k in range(3)]
    # A pile of paper is one block and a few loose sheets, not nine slabs. Nine chamfered
    # 3.5 mm boards is what the first render showed and it read as a stack of *planks*:
    # every sheet the same thickness, every edge the same arris, nothing in the pile
    # thinner than a floorboard. A real sheet is a tenth of a millimetre, so the body of
    # the pile has to be one mass whose *edge* is where the sheets are, and only the top
    # few are worth modelling one at a time.
    block_h = 0.026 * (1.0 + 0.2 * rng.random())
    block = B.board("block", w_, d, block_h, mat=papers[0], chamfer=0.0006,
                    location=(0, 0, block_h * 0.5))
    # The block's sides are not square: a hand-squared pile splays a little, and the splay
    # is what carries the light down the cut edge and says "many sheets".
    for v in block.data.vertices:
        f = 1.0 + 0.020 * (v.co.z / block_h + 0.5)
        v.co.x *= f
        v.co.y *= f
    S.jitter_verts(block, amount=0.0009, scale=0.04, seed=rng.randrange(999))
    parts.append(block)
    z = block_h
    for i in range(loose):
        t = 0.0016
        leaf = B.board("leaf_%d" % i, w_ * rng.uniform(0.94, 1.0), d * rng.uniform(0.93, 1.0),
                       t, mat=papers[(i + 1) % 3], chamfer=0.0004, rng=None,
                       sag=t * rng.uniform(-0.6, 0.6), warp=t * rng.uniform(-2.4, 2.4))
        leaf.location = Vector((rng.uniform(-1, 1) * w_ * 0.045, rng.uniform(-1, 1) * d * 0.05,
                                z + t * 0.5))
        S.apply_transforms(leaf)
        leaf.rotation_euler = Euler((0, 0, math.radians(rng.uniform(-5.0, 5.0))))
        S.apply_transforms(leaf)
        parts.append(leaf)
        z += t * rng.uniform(1.1, 1.8)
    # The top sheet has lifted at one corner, which is the only thing that says paper and
    # not a block of wood once the light is on it.
    curl = parts[-1]
    for v in curl.data.vertices:
        u = max(0.0, (v.co.x / (w_ * 0.5) + 0.35) / 1.35) * max(0.0, (v.co.y / (d * 0.5) + 0.5) / 1.5)
        v.co.z += 0.013 * u ** 2.0
    S.shade_smooth(curl, 50.0)
    return finish(parts, rng, "convex", ["parchment"], extra={"loose": loose})


def phial(pal, rng, params, variant):
    """A stoppered glass phial with something dark in it: the alchemist's own measure.

    Nell's stillroom stands seven of these on two shelves and they all drew a 286 mm jug for
    a thing written down at 130. The fill is a second lathe inside the glass rather than a
    tint on it: what tells you a bottle is not empty is the line across it."""
    h = jit(rng, params.get("height", 0.112)) * CHUNK
    r = jit(rng, params.get("radius", 0.026)) * CHUNK
    squat = bool(params.get("squat", variant % 2 == 1))
    if squat:
        r, h = r * 1.28, h * 0.88
    glass = M.glass(pal, name="phial_glass")
    fill = M.glass(pal, color=P.lin(params.get("fill_hex", "#4a2f52" if variant % 2 else "#5a5220")),
                   name="phial_fill")
    cork = tool_wood(pal, rng, scale=0.8, wear=0.12, age=0.3, base_hex="#b09a68",
                     relief=0.05, grain=0.2, name="cork_wood")
    seal = M.wax(pal, color=P.lin("#6a2a22"), name="phial_seal")
    neck_r = r * 0.42
    shoulder = h * (0.52 if squat else 0.62)
    prof = [(0.0, 0.002), (r * 0.78, 0.0), (r * 0.94, h * 0.05), (r, h * 0.22),
            (r * 0.98, shoulder), (r * 0.62, shoulder + h * 0.10),
            (neck_r * 1.06, shoulder + h * 0.16), (neck_r, h * 0.92),
            (neck_r * 1.20, h * 0.96), (neck_r * 1.14, h)]
    body = S.lathe("phial", prof, segments=18, mat=glass, close=True)
    S.shade_smooth(body, 40.0)
    parts = [body]
    level = h * (0.30 + 0.22 * rng.random())
    inner = [(0.0, r * 0.02), (r * 0.74, r * 0.01), (r * 0.90, h * 0.06),
             (r * 0.94, level * 0.7), (r * 0.93, level), (0.0, level)]
    parts.append(S.lathe("fill", inner, segments=18, mat=fill, close=False))
    S.shade_smooth(parts[-1], 40.0)
    parts.append(S.cylinder("cork", radius=neck_r * 0.96, radius_top=neck_r * 0.88,
                            depth=h * 0.085, location=(0, 0, h - h * 0.02), vertices=12,
                            mat=cork))
    # A blob of sealing wax over the cork, pressed down with a thumb and not with a seal:
    # the Order's plate is a Name-table's business, and this is a herbwife's shelf.
    blob = S.lathe("seal", [(neck_r * 1.24, h + h * 0.045), (neck_r * 1.30, h + h * 0.065),
                            (neck_r * 0.92, h + h * 0.095), (0.0, h + h * 0.10)],
                   segments=14, mat=seal, close=True)
    S.jitter_verts(blob, amount=neck_r * 0.10, scale=0.05, seed=rng.randrange(999))
    parts.append(blob)
    for p in parts:
        S.apply_transforms(p)
        p.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
        S.apply_transforms(p)
    return finish(parts, rng, "convex", ["glass", "wood_planks", "wax"],
                  extra={"squat": squat})


def jar(pal, rng, params, variant):
    """A stoneware ingredient jar with a cloth cover tied over its mouth.

    Written at the same 130 mm as the phial and a different object: wide-shouldered, opaque,
    and shut with cloth and cord rather than cork and wax, so an ingredient shelf and a
    bottle shelf in the same stillroom do not draw the same thing twice."""
    h = jit(rng, params.get("height", 0.108)) * CHUNK
    r = jit(rng, params.get("radius", 0.040)) * CHUNK
    clay = _clay(pal, rng, "earth", 0.26, (h * 0.55, h * 1.05), glaze=0.55,
                 name="jar_clay")
    linen = M.canvas(pal, age=0.5, wear=0.4, scale=0.16)
    cord = M.rope(pal, age=0.55, scale=0.05)
    mouth = r * 0.62
    t = r * 0.10
    prof = [(0.0, 0.003), (r * 0.62, 0.0), (r * 0.80, h * 0.06), (r, h * 0.34),
            (r * 0.96, h * 0.56), (r * 0.70, h * 0.78), (mouth * 1.02, h * 0.88),
            (mouth, h), (mouth - t, h), (mouth - t, h * 0.90),
            (r * 0.64 - t, h * 0.78), (r * 0.90 - t, h * 0.54), (r * 0.92 - t, h * 0.32),
            (r * 0.70 - t, h * 0.08), (0.0, h * 0.06)]
    body = S.lathe("jar", prof, segments=22, mat=clay, close=False)
    S.shade_smooth(body, 42.0)
    parts = [body]
    # The cover: a disc of linen pushed down into the mouth and sagging in the middle, then
    # whipped round the neck with cord. Lathed rather than sheeted, because B.cloth_sheet
    # hangs from its top edge and this one is stretched over a hole.
    cover = S.lathe("cover", [(0.0, h * 0.965), (mouth * 0.55, h * 0.975),
                              (mouth * 0.92, h * 1.01), (mouth * 1.12, h * 1.02),
                              (mouth * 1.30, h * 0.975), (mouth * 1.34, h * 0.93)],
                    segments=20, mat=linen, close=False)
    S.solidify(cover, thickness=0.0014, offset=0.0)
    S.jitter_verts(cover, amount=mouth * 0.05, scale=0.04, seed=rng.randrange(999))
    S.shade_smooth(cover, 50.0)
    parts.append(cover)
    parts.append(B.rope_loop("tie", mouth * 1.22, 0.0028, mat=cord, segments=18,
                             location=(0, 0, h * 0.945)))
    for p in parts:
        S.apply_transforms(p)
        p.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
        S.apply_transforms(p)
    return finish(parts, rng, "convex", ["ceramic", "canvas", "rope"])


def mortar(pal, rng, params, variant):
    """An apothecary's mortar: a deep, thick-walled stone cup with a pouring lip.

    Tall rather than wide, which is what a mortar for seeds and bark is and what the written
    140 x 220 mm says. It borrowed a 456 mm cooking pot. No pestle: the room places one of
    those itself, and a mortar with its pestle standing in it is 320 mm and a lie again."""
    h = jit(rng, params.get("height", 0.200)) * CHUNK
    r = jit(rng, params.get("radius", 0.068)) * CHUNK
    # Quarried grit, not Brightwater's lake stone. The first pass used lake stone for its
    # `relief` parameter and got what lake stone is: near-black, cold-highlighted, wet. On
    # a vale herbwife's bench that read as a dark green vase. This is the millstone's route
    # -- granite with a warm dry base and no lichen, because a mortar lives under a roof and
    # is washed every day -- and the relief is down to a fifth because `_rock_common` bumps
    # over an absolute 50 mm, which is a quarter of this object.
    # Darker than it looks it should be. The review scene reads two stops light (the forge
    # README's warning), and at #8e877a the mortar came out of it the same value as the wax
    # candle standing beside it -- which means an albedo near white, and stone is not near
    # white. The wick and the candle are the reference that catches this.
    stone = M.granite(pal, wear=0.26, age=0.45, tint=0.13, tint_role="earth",
                      base_hex="#6b6459", lichen=0.0, facet=0.22, scale=0.36, relief=0.20,
                      name="mortar_grit")
    foot = r * 0.62
    rim = r * 1.30                                    # the mouth is the widest part of it
    t = r * 0.34                                      # walls a mortar can be hit in
    # A mortar is a cone with a heavy foot: narrow where it is held, wide where the pestle
    # works. Built the other way up -- straight-sided and rim-width all the way down -- a
    # 0.22 m one reads as a vase, which is what the first render showed.
    prof = [(0.0, 0.004), (foot * 0.86, 0.0), (foot * 1.06, h * 0.03), (foot * 1.02, h * 0.11),
            (r * 0.74, h * 0.30), (r * 0.98, h * 0.58), (rim * 0.96, h * 0.86),
            (rim, h * 0.95), (rim * 1.02, h),
            (rim * 1.02 - t * 0.7, h), (rim * 0.92 - t, h * 0.88), (r * 0.80 - t, h * 0.56),
            (r * 0.54 - t, h * 0.32), (foot * 0.62, h * 0.20), (foot * 0.34, h * 0.17),
            (0.0, h * 0.165)]
    body = S.lathe("mortar", prof, segments=24, mat=stone, close=False)
    S.shade_smooth(body, 40.0)
    # The lip: one side of the rim drawn out and dropped, so it pours.
    for v in body.data.vertices:
        if v.co.z < h * 0.78:
            continue
        a = math.atan2(v.co.y, v.co.x)
        k = max(0.0, math.cos(a)) ** 4.0
        f = 1.0 + 0.20 * k
        v.co.x *= f
        v.co.y *= f
        v.co.z -= h * 0.075 * k * (v.co.z - h * 0.78) / (h * 0.22)
    S.jitter_verts(body, amount=r * 0.010, scale=0.06, seed=rng.randrange(999))
    body.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
    S.apply_transforms(body)
    return finish([body], rng, "convex", ["lake_stone"])


def candle_stub(pal, rng, params, variant):
    """What is left of a candle, guttered down into a clay saucer.

    Twenty-five of these are scattered through the shipping interiors -- on tables, beside
    beds, at shrines -- and every one drew a whole fresh 181 mm candle for a thing written
    down at 130. A stub is not a candle: it is short, it has run down one side, and it sits
    in a pool of itself. The wick is burnt, so it is black and bent over."""
    saucer_r = jit(rng, params.get("radius", 0.042)) * CHUNK
    # Two-thirds burnt and half burnt, not a wick in a puddle: the written 130 mm is the
    # whole object, so a stub much under 90 mm is a lie in the other direction and a
    # half-used candle is what is beside a bed anyway.
    stub = jit(rng, params.get("stub", 0.102 if variant % 2 == 0 else 0.088)) * CHUNK
    # Fatter than a fresh candle and much shorter: the forge's `candle` is 17 mm across and
    # 181 mm tall, and the two have to be different objects at a glance on the same table.
    r = 0.0196 * CHUNK
    dish = _clay(pal, rng, "light", 0.14, (0.004, 0.016), glaze=0.3, age=0.6,
                 relief=0.2, name="stub_dish")
    wax = M.wax(pal, name="stub_wax")
    parts = []
    saucer = S.lathe("saucer", [(0.0, 0.0), (saucer_r * 0.62, 0.0011), (saucer_r * 0.82, 0.006),
                                (saucer_r, 0.013), (saucer_r * 0.96, 0.0125),
                                (saucer_r * 0.74, 0.0055), (0.0, 0.004)],
                     segments=18, mat=dish, close=False)
    S.shade_smooth(saucer, 40.0)
    parts.append(saucer)
    base = 0.0045
    # The pool it has wept into the saucer, then the stub, then the crater the flame burnt
    # down into the top of it.
    pool = S.lathe("pool", [(0.0, base), (r * 1.7, base), (r * 2.05, base * 0.7),
                            (r * 2.1, base * 0.35), (0.0, base * 0.3)],
                   segments=16, mat=wax, close=False)
    S.jitter_verts(pool, amount=r * 0.10, scale=0.03, seed=rng.randrange(999))
    parts.append(pool)
    top = base + stub
    # The crater is the whole read: a candle that has burnt is lower in the middle than at
    # its edge, because the wall stands while the well melts. A straight-sided cylinder
    # with a domed top is a *new* candle, and that is what the first render gave -- the
    # thing it was standing in as, at the right height.
    body = S.lathe("stub", [(0.0, base * 0.9), (r * 1.18, base * 0.9), (r * 1.04, base + stub * 0.20),
                            (r, base + stub * 0.66), (r * 1.02, top - r * 0.22),
                            (r * 0.96, top),                       # the standing wall
                            (r * 0.80, top - r * 0.16),            # and down into the well
                            (r * 0.46, top - r * 0.52), (r * 0.18, top - r * 0.66),
                            (0.0, top - r * 0.62)],
                  segments=16, mat=wax, close=False)
    S.shade_smooth(body, 45.0)
    # The wall is burnt down further on one side, so the well is open and the run of wax
    # has somewhere to come from. One smooth function of the angle: a threshold gives a
    # notch with two hard corners, which reads as a chip out of a new candle.
    side = rng.uniform(0.0, TAU)
    for v in body.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = max(0.0, math.cos(a - side)) ** 2.0
        if v.co.z > top - r * 0.30:
            v.co.z -= r * 0.62 * k
        # and a run of wax down that same side, all the way into the pool
        if v.co.z < top - r * 0.5:
            f = 1.0 + 0.34 * k * (1.0 - (v.co.z - base) / max(stub, 1e-6)) ** 0.5
            v.co.x *= f
            v.co.y *= f
    S.jitter_verts(body, amount=r * 0.06, scale=0.04, seed=rng.randrange(999))
    parts.append(body)
    # The wick: burnt, so it is black, it has bent over, and it stands up out of the well
    # rather than off the top of a dome. It is four millimetres of geometry and it is the
    # difference between a candle that has been lit and one that has not.
    wick_top = top + r * 0.30
    parts.append(S.tube_along("wick", [(0, 0, top - r * 0.62), (r * 0.08, 0, top - r * 0.10),
                                       (r * 0.30, r * 0.08, top + r * 0.14),
                                       (r * 0.62, r * 0.20, wick_top)],
                              radius=r * 0.085, segments=5, radius_end=r * 0.040,
                              mat=M.soot(pal, name="wick_soot")))
    for p in parts:
        S.apply_transforms(p)
        p.rotation_euler = Euler((0, 0, rng.uniform(0.0, TAU)))
        S.apply_transforms(p)
    return finish(parts, rng, "convex", ["ceramic", "wax", "soot"],
                  extra={"burnt_down": stub < 0.075})


def _boot(name, length, height, mat, sole_mat, rng, slump=0.0):
    """One boot, stood on its sole.

    What says `boot` from across a room is an **L**: a low foot with an instep, a leg that
    goes up from the back of it, and a cuff at the top wider than the leg. The first pass
    had none of those. It laid a plank of a sole the full length of the prop, put one
    tapering sausage on top of it and then flopped the leg over until it lay along the
    ground -- and the render gave a pale slumped bundle on a board, which is very nearly the
    sack it was standing in as. So the sole stops at the toe and the heel, the instep is a
    separate rise, the leg stands, and only the cuff slumps."""
    parts = []
    # A foot is nearly as wide and as deep as it is long is not true, but a *boot* is much
    # closer to it than the first two passes allowed. At a foot radius of 0.11 of the
    # length the upper was 57 mm across, the sole board under it was 87 mm, and the render
    # showed a skinny sausage standing on a plank that stuck out all round it. The foot
    # governs: the sole is cut to the foot's own footprint and nothing protrudes.
    r_foot = length * 0.170
    sole_t = height * 0.070
    toe_x = length * 0.32
    ankle_x = -length * 0.20
    z0 = sole_t
    path = [(toe_x, 0.0, z0 + r_foot * 0.80), (length * 0.13, 0.0, z0 + r_foot * 0.88),
            (-length * 0.04, 0.0, z0 + r_foot * 1.10), (ankle_x, 0.0, z0 + r_foot * 1.34)]
    foot = S.tube_along("%s_foot" % name, path, radius=r_foot, segments=12,
                        radius_end=r_foot * 0.80, mat=mat)
    # Squashed down and left full width: a boot is flatter than it is narrow.
    _oval_along_x(foot, path, flat=0.78, wide=1.00)
    # And its underside is flat, because the boot has been walked on. This is what lets the
    # sole be a thin dark line at the bottom of the upper instead of a board underneath it:
    # a plate the foot merely rests on reads as a plank however well it is cut, and two of
    # them at two yaws read as a pair of skis, which is what the second render showed.
    for v in foot.data.vertices:
        if v.co.z < sole_t * 1.05:
            v.co.z = sole_t * 1.05
    # And the toe is round. `tube_along` caps its ends with a flat n-gon, and a swept toe
    # aimed at the camera showed that cap as a disc -- a boot with the end sawn off. The
    # last ring is drawn in and forward into a dome instead.
    for v in foot.data.vertices:
        if v.co.x > toe_x - 1e-4:
            dy, dz = v.co.y, v.co.z - (z0 + r_foot * 0.80)
            v.co.y *= 0.55
            v.co.z = (z0 + r_foot * 0.80) + dz * 0.55
            v.co.x += r_foot * 0.42 * (1.0 - min(1.0, math.hypot(dy, dz) / max(r_foot, 1e-6)) ** 2)
    S.shade_smooth(foot, 46.0)
    parts.append(foot)
    foot_lo, foot_hi = ankle_x - r_foot * 0.74, toe_x + r_foot * 0.94
    sole = B.board("%s_sole" % name, foot_hi - foot_lo, r_foot * 1.94, sole_t * 1.1, mat=sole_mat,
                   location=((foot_hi + foot_lo) * 0.5, 0, sole_t * 0.55),
                   chamfer=sole_t * 0.30)
    # Tapered to a round toe and pinched at the waist. Clamped at both ends: `B.board`
    # chamfers before it returns, and a chamfer puts vertices a hair outside the board's
    # own half-length, so `t` went fractionally negative and a negative number to the power
    # 0.6 is a complex one -- which arrives as "assigned value not a number", a long way
    # from here.
    half = (foot_hi - foot_lo) * 0.5
    for v in sole.data.vertices:
        t = min(1.0, max(0.0, (v.co.x / half + 1.0) * 0.5))          # 0 heel, 1 toe
        v.co.y *= 0.70 + 0.30 * math.sin(math.pi * min(1.0, t * 0.86)) ** 0.5
    S.bevel(sole, width=sole_t * 0.24, segments=2, angle_deg=40)
    parts.append(sole)
    # The leg. It stands: a boot pulled off keeps its shape for years, and a leg lying on
    # the floor is a glove. `slump` leans it back and pulls the cuff over, no further.
    cuff_r = r_foot * 1.02
    top = height - cuff_r * 0.30
    ankle_z = z0 + r_foot * 1.12
    lean = -length * (0.04 + 0.13 * slump)
    leg = [(ankle_x, 0.0, ankle_z),
           (ankle_x + lean * 0.30, slump * length * 0.02, ankle_z + (top - ankle_z) * 0.40),
           (ankle_x + lean * 0.72, slump * length * 0.05, ankle_z + (top - ankle_z) * 0.76),
           (ankle_x + lean, slump * length * 0.09, top)]
    shaft = S.tube_along("%s_leg" % name, leg, radius=r_foot * 0.82, segments=12,
                         radius_end=cuff_r * 0.94, mat=mat)
    S.shade_smooth(shaft, 46.0)
    parts.append(shaft)
    # The cuff: a rolled rim round the mouth of the leg. It is the one part of a boot that
    # is bigger than what is under it, and it is what tells the eye the thing is hollow.
    # Set square to the leg, not to the floor: a rim lying flat on top of a leaning tube
    # cuts into it on one side and floats off it on the other.
    tilt_y = math.degrees(math.atan2(lean * 0.28, max(top - ankle_z, 1e-6) * 0.24))
    cuff = B.hoop("%s_cuff" % name, cuff_r, r_foot * 0.16, mat=mat, segments=20, flatten=1.15,
                  rotation=(0, tilt_y, 0))
    cuff.location = Vector((ankle_x + lean, slump * length * 0.09, top))
    S.apply_transforms(cuff)
    parts.append(cuff)
    for p in parts:
        S.jitter_verts(p, amount=length * 0.004, scale=0.05, seed=rng.randrange(999))
    return parts


def boots(pal, rng, params, variant):
    """A pair of boots left by the door, which is what four of the shipping houses say
    about the person who lives in them.

    They drew a sack: 0.71 m of grain for a 0.18 m pair of boots, and a sack is the one
    shape in the library least like a boot. `small_boots` -- the child's pair in Hallam's
    forge and Tallissa's stilt-house -- is written at the same height and stands in as
    these, because a child's boots beside an adult's is a scene and not an error.

    The leather is dark and its edge wear is almost off. This is the anvil stump's lesson
    again: `edge_wear` lightens convex edges, a boot is convex nearly everywhere, and the
    first pair came out of the review render the colour of unbleached linen at a wear of
    0.5 -- which on a pale slumped shape is exactly the sack again."""
    h = jit(rng, params.get("height", 0.172)) * CHUNK
    l = jit(rng, params.get("length", 0.255)) * CHUNK
    hide = M.leather(pal, age=0.80, wear=0.14, tint=0.10, scale=0.20, base_hex="#3a2716",
                     name="boot_hide")
    sole = M.leather(pal, age=0.90, wear=0.10, tint=0.08, scale=0.14, base_hex="#241a11",
                     name="boot_sole")
    parts = []
    # Not a mirrored pair: they were kicked off, so they do not stand square to each other
    # and one has slumped further than the other.
    for i, sy in enumerate((-1, 1)):
        slump = (0.20, 0.75)[i] * rng.uniform(0.85, 1.15)
        boot = _boot("boot_%d" % i, l, h * (1.0 - 0.06 * slump), hide, sole, rng, slump=slump)
        # A small splay. At twenty-odd degrees each the pair crossed and read as skis.
        yaw = math.radians(sy * rng.uniform(4.0, 13.0))
        for p in boot:
            S.apply_transforms(p)
            p.rotation_euler = Euler((math.radians(sy * -slump * 5.0), 0.0, yaw))
            S.apply_transforms(p)
            p.location = Vector((rng.uniform(-1, 1) * l * 0.04, sy * l * 0.17, 0.0))
            S.apply_transforms(p)
        parts += boot
    return finish(parts, rng, "convex", ["leather"])


def lantern_hand(pal, rng, params, variant):
    """A hand lantern: a candle behind four panes, with a bail to carry it by.

    The kind an interior asks for by the name `lantern` -- one stands on the Bell
    Chapter-House's roll desk and one on Pellam's -- and it was drawing
    `lantern_standing`, which is a 2.03 m post with a lamp on the end of it, for a thing
    written down at 0.22. The bail is most of the difference between a hand lantern and a
    box with a light in it, and it is included in the written height because it is what you
    pick the thing up by."""
    h = jit(rng, params.get("height", 0.168)) * CHUNK
    metal = iron(pal, rng, age=0.6, wear=0.65, scale=0.10)
    glass = M.glass(pal)
    parts, r = _lantern_body(pal, rng, h, metal, glass)
    # The bail: a half-hoop standing off the roof line, taller than it is wide, which is
    # what a bucket handle is and what this is.
    top = float(params.get("bail_top", 0.205)) * CHUNK
    anchor = h * 0.60
    pts = B.catenary((-r * 1.02, 0.0, anchor), (r * 1.02, 0.0, anchor), -(top - anchor), steps=11)
    parts.append(S.tube_along("bail", pts, radius=h * 0.014, segments=6, mat=metal))
    for sx in (-1, 1):
        parts.append(S.sphere("bail_eye_%d" % sx, radius=h * 0.026, subdivisions=2,
                              location=(sx * r * 1.02, 0.0, anchor), mat=metal,
                              scale=(1.0, 0.55, 1.0)))
    S.apply_transforms(parts[-1])
    # A ring at the crown of the bail, for the nail it hangs on when it is not carried.
    parts.append(S.torus("ring", major=h * 0.032, minor=h * 0.009, seg_major=14, seg_minor=6,
                         location=(0, 0, top + h * 0.028), rotation=(90, 0, 0), mat=metal))
    return finish(parts, rng, "convex", ["iron", "glass"], extra={"emissive": True})


def copper(pal, rng, params, variant):
    """A brewing copper on its setting: the vessel Corwen's brewhouse is built around.

    It drew a 0.46 m cooking pot for a 0.95 m vessel, which halved the one object in the
    room that the room exists for. What makes a copper a copper and not a big pot is that it
    is *set*: bedded into a low round of stone with a fire mouth under it, so the rim stands
    at working height and the flames go under the metal and nowhere else."""
    rim_h = float(params.get("height", 0.95))
    r = jit(rng, params.get("radius", 0.325))
    set_h = rim_h * params.get("setting", 0.44)
    bronze = M.bronze(pal, age=0.62, wear=0.55, scale=0.34, name="copper_metal")
    stone = M.stone_blocks(pal, wear=0.55, age=0.7, scale=0.45, block_w=0.20, block_h=0.10,
                           name="setting_stone")
    sooty = M.soot(pal, name="setting_soot")
    metal = iron(pal, rng, age=0.8, wear=0.5, scale=0.16)
    parts = []
    # The setting, course by course round a circle, with a mouth left in the front two
    # courses. Leaving the stones out is how the mouth is cut: the setting is forty separate
    # blocks, so a boolean would have to find them all and a gap is what a mason leaves.
    rows = 4
    mouth_half = math.radians(28.0)
    for row in range(rows):
        z = set_h * (row + 0.5) / rows
        n = 15
        for i in range(n):
            a = TAU * (i + (row % 2) * 0.5) / n + rng.uniform(-0.02, 0.02)
            if row < 2 and abs(math.atan2(math.sin(a), math.cos(a))) < mouth_half:
                continue
            # The blocks touch. At 0.93 of the arc they stood 7% apart and the staggered
            # courses lined the gaps up, so the render gave a cairn of loose sugar cubes
            # with daylight between them holding up half a tonne of copper. Stones in a
            # setting are bedded in mortar and overlap their neighbours a little; 1.04
            # with a 0.96 course height leaves the bed joint and closes the perpends.
            bw = TAU * r / n * 1.04
            b = S.box_centered("set_%d_%d" % (row, i), (bw, r * 0.30, set_h / rows * 0.96),
                               (0, 0, z), rotation=(0, 0, math.degrees(a)), mat=stone)
            b.location = Vector((math.cos(a) * r, math.sin(a) * r, z))
            S.apply_transforms(b)
            # One bevel segment, not two. Sixty setting stones at two segments is 108
            # triangles each and put the whole prop at 8 060 -- twice the forge hearth,
            # which is the heaviest comparable fixture in the library -- for an arris
            # nobody can see on a 0.2 m block of a stone setting.
            S.bevel(b, width=bw * 0.055, segments=1, angle_deg=40)
            S.jitter_verts(b, amount=bw * 0.03, scale=0.4, seed=rng.randrange(999))
            parts.append(b)
    # The back of the fire mouth: a sooted recess, so the gap reads as a hole into a
    # firebox and not as a hole through the prop.
    recess = S.lathe("firebox", [(r * 0.86, 0.0), (r * 0.86, set_h * 0.52)], segments=18,
                     mat=sooty, close=True)
    parts.append(recess)
    lintel = S.box_centered("lintel", (r * 0.80, r * 0.34, set_h / rows * 0.8),
                            (r * 0.97, 0, set_h * 0.5 + set_h / rows * 0.1),
                            rotation=(0, 0, 90), mat=stone)
    S.bevel(lintel, width=0.012, segments=2, angle_deg=40)
    S.jitter_verts(lintel, amount=0.008, scale=0.3, seed=rng.randrange(999))
    parts.append(lintel)
    # The vessel: bedded in at the setting's top, bellied, and open at the rim.
    vr = r * 1.04
    body_z = set_h * 0.78
    t = 0.014
    prof = [(0.0, body_z * 0.62), (r * 0.52, body_z * 0.66), (r * 0.86, body_z * 0.86),
            (vr * 0.99, set_h * 1.02), (vr, rim_h * 0.76), (vr * 0.965, rim_h * 0.95),
            (vr * 1.03, rim_h), (vr * 1.03 - t, rim_h),
            (vr * 0.94 - t, rim_h * 0.94), (vr * 0.975 - t, rim_h * 0.74),
            (r * 0.84 - t, body_z * 0.88), (r * 0.50, body_z * 0.72), (0.0, body_z * 0.70)]
    vessel = S.lathe("copper", prof, segments=30, mat=bronze, close=False)
    S.shade_smooth(vessel, 40.0)
    S.jitter_verts(vessel, amount=vr * 0.006, scale=0.5, seed=rng.randrange(999))
    parts.append(vessel)
    # A riveted band below the rim, and the two lugs it is lifted out by.
    parts.append(B.hoop("band", vr * 1.005, rim_h * 0.016, mat=bronze,
                        location=(0, 0, rim_h * 0.86), segments=30, flatten=2.6))
    for i in range(16):
        a = TAU * i / 16
        parts.append(S.sphere("rivet_%d" % i, radius=rim_h * 0.011, subdivisions=1,
                              location=(math.cos(a) * vr * 1.02, math.sin(a) * vr * 1.02,
                                        rim_h * 0.86),
                              mat=bronze, scale=(0.55, 0.55, 1.0)))
        S.apply_transforms(parts[-1])
    for sy in (-1, 1):
        lug = S.torus("lug_%d" % sy, major=rim_h * 0.055, minor=rim_h * 0.011, seg_major=16,
                      seg_minor=6, location=(0, sy * vr * 1.02, rim_h * 0.80),
                      rotation=(0, 90, 0), mat=metal)
        parts.append(lug)
    # The tap, low on the front where the wort comes off.
    tap_z = set_h * 1.10
    parts.append(S.cylinder("tap", radius=rim_h * 0.022, radius_top=rim_h * 0.016,
                            depth=r * 0.34, location=(vr * 0.92, 0, tap_z),
                            rotation=(0, 90, 0), vertices=10, mat=metal))
    parts.append(S.cylinder("tap_key", radius=rim_h * 0.008, depth=rim_h * 0.075,
                            location=(vr * 1.18, 0, tap_z), rotation=(90, 0, 0), vertices=7,
                            mat=metal))
    return finish(parts, rng, "col_glb", ["stone_blocks", "bronze", "iron", "soot"],
                  extra={"rim_height": round(rim_h, 3)})


# =========================================================================================
# the Name-table
# =========================================================================================

def name_table(pal, rng, params, variant):
    """A Name-table: the bench a Toll-Knight writes a note into iron at (DESIGN §5.8).

    Named in the design, in the enchanting skill's own definition and in two item
    descriptions, and until now there was no mesh for one: the only Name-table in the
    country -- the Bell Chapter-House at Pilgrim's Ash, in Cadwen's recipe -- stood in as a
    trestle table and was written down as owed.

    The Tolling Order is grim, kind and doomed (WORLD_BIBLE §4), and it keeps a vigil in a
    fallen bell on an ash heath. So there is nothing on this that the forge cannot justify:
    a single heavy baulk of dark timber, iron-strapped legs, one plate of bell bronze let
    into the top with the Order's note cut into it, and a small bowl for the Ember Motes
    that pay for the writing. No carving, no inlay, no gilding. The mark is *cut* rather
    than painted for the reason the millstone's furrows and the loaf's scores are cut: what
    a player sees of a 0.34 m plate across a cell is the light caught in the groove, and a
    line in the albedo catches nothing.
    """
    l = jit(rng, params.get("length", 1.40), 0.02)
    w_ = jit(rng, params.get("width", 0.78), 0.02)
    top_z = float(params.get("top_height", 0.745))
    slab_t = 0.105
    # One baulk, not a plank run: the plank size is set well past the slab so no joint
    # crosses it, which is the same reason a spoon is one billet. The grain is down to two
    # or three lengths of tone rather than the default's banding.
    # Dark, and the tint kept right down. `wood_planks` mixes its tint from the palette's
    # `earth` role, and Cinderlea's earth is the faded gold of old gilding -- the one warm
    # light colour in a region of ash grey, char black and bone. At a fifth it lifted a
    # near-black baulk to the pale olive of the Hearthvale trestle standing beside it in
    # the review render, which is the one thing this bench must not look like.
    timber = tool_wood(pal, rng, scale=0.46, wear=0.10, age=0.55, base_hex="#221a12",
                       tint=0.06, relief=0.55, grain=0.30, plank_len=3.4, plank_w=1.3,
                       along="X", name="name_slab")
    strap = iron(pal, rng, age=0.72, wear=0.45, scale=0.18)
    bronze = M.bell_bronze_patina(pal, age=0.80, wear=0.55, scale=0.22, name="note_bronze")
    parts = []
    slab = B.board("slab", l, w_, slab_t, mat=timber, location=(0, 0, top_z - slab_t * 0.5),
                   chamfer=0.009, sag=0.003, rng=rng)
    parts.append(slab)
    # Two end frames. The posts stand square and the feet are one baulk laid flat, because
    # a bench that is written at rather than eaten off does not get moved and does not need
    # to fold: the Order's furniture is the Order's -- heavy, plain, and older than whoever
    # is using it.
    post = 0.085
    leg_h = top_z - slab_t
    for sx in (-1, 1):
        x = sx * (l * 0.5 - 0.17)
        for sy in (-1, 1):
            p = S.cube("post_%d_%d" % (sx, sy), (post, post, leg_h),
                       (x, sy * (w_ * 0.5 - 0.15), 0.0), mat=timber)
            S.bevel(p, width=0.006, segments=2)
            parts.append(p)
        foot = S.cube("foot_%d" % sx, (post * 1.5, w_ * 0.80, 0.075), (x, 0, 0.0), mat=timber)
        S.bevel(foot, width=0.008, segments=2)
        parts.append(foot)
        head = S.cube("head_%d" % sx, (post * 1.35, w_ * 0.74, 0.070), (x, 0, leg_h - 0.070),
                      mat=timber)
        S.bevel(head, width=0.008, segments=2)
        parts.append(head)
        # The straps: over the head where the leg takes the slab, and round the foot.
        for z, ln in ((leg_h - 0.035, w_ * 0.80), (0.038, w_ * 0.86)):
            parts.append(B.iron_strap("strap_%d_%.0f" % (sx, z * 100), ln, 0.050, 0.008,
                                      mat=strap, location=(x, 0, z), rotation=(0, 0, 90)))
    # One stretcher low down, strapped at both ends: what stops the frame racking.
    parts.append(S.cube("stretcher", (l * 0.62, 0.075, 0.085), (0, 0, leg_h * 0.30), mat=timber))
    S.bevel(parts[-1], width=0.007, segments=2)
    for sx in (-1, 1):
        parts.append(B.iron_strap("tie_%d" % sx, 0.135, 0.044, 0.007, mat=strap,
                                  location=(sx * l * 0.30, 0, leg_h * 0.30 + 0.043),
                                  rotation=(0, 0, 0)))
    # The plate, let into the slab so it stands a couple of millimetres proud, with the
    # Order's note cut into it. Two subtractions: the bell's mouth as a ring, and the stem
    # standing off its shoulder.
    pl, pw, pt = 0.34, 0.26, 0.016
    plate_z = top_z - 0.004
    plate = S.box_centered("plate", (pl, pw, pt), (0, 0, plate_z + pt * 0.5 - 0.004),
                           mat=bronze)
    S.bevel(plate, width=0.0035, segments=2, angle_deg=45)
    # Cut deep. The first pass sank the cutters so only their shoulders broke the surface
    # and the mark was four millimetres of groove on a 0.34 m plate -- there in the mesh and
    # gone in the render, which is the millstone's furrow all over again. A third of the
    # plate's thickness is a groove the light sits in.
    ring_c = (-0.022, -0.030)
    ring = S.torus("mark_ring", major=0.058, minor=0.010, seg_major=28, seg_minor=8,
                   location=(ring_c[0], ring_c[1], plate_z + pt * 0.5 + 0.0015))
    S.boolean(plate, ring, "DIFFERENCE")
    stem = S.box_centered("mark_stem", (0.016, 0.140, 0.020),
                          (ring_c[0] + 0.058, ring_c[1] + 0.062,
                           plate_z + pt * 0.5 + 0.0035))
    S.boolean(plate, stem, "DIFFERENCE")
    S.shade_smooth(plate, 30.0)
    parts.append(plate)
    # The mote bowl: bell bronze, shallow, standing on the slab where a right hand falls.
    # Ember Motes "hover a finger's breadth above the palm" (core:item/ember_mote), so it
    # is open -- a cup with a lid would be a reliquary, and this is a working bench.
    br = 0.058
    bowl_z = top_z - 0.002
    cup = S.lathe("mote_bowl", [(0.0, bowl_z + 0.004), (br * 0.52, bowl_z), (br * 0.80, bowl_z + 0.002),
                                (br * 0.96, bowl_z + 0.030), (br, bowl_z + 0.052),
                                (br * 0.94, bowl_z + 0.052), (br * 0.86, bowl_z + 0.030),
                                (br * 0.44, bowl_z + 0.012), (0.0, bowl_z + 0.010)],
                  segments=22, mat=bronze, close=False)
    cup.location = Vector((l * 0.30, -w_ * 0.16, 0.0))
    S.apply_transforms(cup)
    S.shade_smooth(cup, 40.0)
    parts.append(cup)
    for p in parts:
        S.jitter_verts(p, amount=0.0016, scale=0.6, seed=rng.randrange(999))
    return finish(parts, rng, "convex", ["wood_planks", "iron", "bell_bronze_patina"],
                  extra={"station": "name_table", "work_height": round(top_z, 3)})


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
    awning = cloth_mat(pal, rng, role="accent", scale=0.8)
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
    parts = [post]
    for i in range(int(params.get("rope_turns", 4))):
        parts.append(B.rope_loop("lash_%d" % i, r * 1.16, 0.014, mat=cord, segments=18,
                                 location=(0, 0, h * (0.62 + 0.045 * i))))
    # a stub of rope trailing down
    parts.append(S.tube_along("tail", [(r * 1.1, 0, h * 0.62), (r * 1.6, r * 0.4, h * 0.3),
                                       (r * 1.9, r * 0.7, h * 0.05)], radius=0.014, segments=6, mat=cord))
    # The whole post leans, lashings and all, and the lean comes last. Tilting the post
    # first and then hanging the ropes on the Z axis puts the rings a hand's breadth off
    # the timber at two metres up: they missed it entirely and hung in the air beside it.
    # That was invisible only because `rope_loop` was also dropping their height and
    # burying them in the mud at the foot, where five degrees of lean moves nothing.
    stand_up(parts, rng.uniform(-5.0, 5.0))
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
    blanket = cloth_mat(pal, rng, role="earth", scale=0.5)
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
    fabric = cloth_mat(pal, rng, role="accent", scale=1.2)
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
    # hand tools, arms and linen
    "cloth": cloth, "spoon": spoon, "tongs": tongs, "hammer": hammer, "spear": spear,
    "shield": shield, "pitchfork": pitchfork, "whetstone": whetstone,
    # the mill, the bakehouse, the woodpile and the peat bank
    "loaf": loaf, "millstone": millstone, "chopping_block": chopping_block,
    "peat_stack": peat_stack,
    # the kinds the stand-ins were lying about the size of
    "bowl": bowl, "plate_stack": plate_stack, "paper_stack": paper_stack, "phial": phial,
    "jar": jar, "mortar": mortar, "candle_stub": candle_stub, "boots": boots,
    "lantern_hand": lantern_hand, "copper": copper,
    # the Tolling Order's bench
    "name_table": name_table,
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
