"""Landmarks: the silhouettes each region is known by (WORLD_BIBLE §6, DESIGN §4.1).

    blender -b --python tools/forge/gen_landmarks.py -- --kind cracked_toll --palette hearthvale

These are hero pieces (up to ~40 000 triangles, 2048 textures) and they are *walkable*:
the Toll's lip is a cave mouth you can go into, the Hand's palm is a floor, the Lamp has a
gallery. Collision is a simplified mesh (<name>_col.glb) so the player can stand on them.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib.runner import run_generator  # noqa: E402

TAU = math.tau


def _weather(obj, rng, amount, scale, seed):
    """Big-scale surface weathering for hero pieces: dents, cracks and sag."""
    t = S.new_texture("weather_%d" % seed, "CLOUDS", noise_scale=scale, noise_depth=3,
                      noise_basis="ORIGINAL_PERLIN")
    off = Vector((seed * 5.1 % 19.0, seed * 3.3 % 17.0, seed * 7.9 % 13.0))
    obj.location += off
    S.apply_transforms(obj, location=True, rotation=False, scale=False)
    S.displace(obj, t, strength=amount, mid_level=0.5, direction="NORMAL", coords="GLOBAL")
    obj.location -= off
    S.apply_transforms(obj, location=True, rotation=False, scale=False)


# --- the Cracked Toll (Hearthvale) -------------------------------------------------------

def cracked_toll(pal, rng, params, variant):
    """A bronze bell 40 m tall, half-buried in the hillside: its lip is a cave you can walk
    into, its crown a lookout, and a crack runs up one side (WORLD_BIBLE §6.1)."""
    h = params.get("height", 40.0)
    r = h * 0.46
    metal = M.bell_bronze_patina(pal, age=0.85 + 0.12 * rng.random(), wear=0.55, scale=h * 0.08)
    # Bell profile: a lip that flares out of the ground, a long waist drawn in hard, a shoulder
    # and a domed crown. Modelled as a shell so the inside is real geometry (you can stand under
    # it). From the farms only the shoulder and crown show over the trees, and the first profile
    # (a crown rounded like a dome straight off a barely tapered side) read there as a dome
    # (playtest 6): the crown is flatter now with a turned shoulder under it, and the sides slope
    # out all the way down, concave, from a waist a little over half the lip, so any part of it
    # that shows over the trees reads as a bell.
    prof_outer = [
        (r * 1.00, 0.00), (r * 0.96, 0.05), (r * 0.87, 0.12), (r * 0.78, 0.20),
        (r * 0.70, 0.30), (r * 0.645, 0.40), (r * 0.605, 0.50), (r * 0.57, 0.62),
        (r * 0.545, 0.76), (r * 0.52, 0.835), (r * 0.47, 0.90), (r * 0.37, 0.95),
        (r * 0.20, 0.98), (r * 0.06, 1.0),
    ]
    thickness = r * 0.085
    prof = [(x, y * h) for (x, y) in prof_outer]
    inner = []
    for i, (x, y) in enumerate(reversed(prof)):
        f = 1.0 - i / float(len(prof) - 1)
        t = thickness * (0.55 + 0.75 * f)  # thickest at the lip, as a real bell is
        inner.append((max(0.02, x - t), y + (thickness * 0.35 if i == len(prof) - 1 else 0.0)))
    ring = prof + inner
    segs = int(params.get("segments", 56))
    bell = S.lathe("bell", ring, segments=segs, mat=metal, close=False)
    bmesh_fix(bell)
    S.shade_smooth(bell, 38.0)

    # The crack: a wedge cut from the lip up the side, wide at the bottom.
    crack_w = r * 0.20
    cutters = []
    steps = 7
    for i in range(steps):
        f = i / float(steps)
        z = h * (0.02 + 0.52 * f)
        w = crack_w * (1.0 - f) ** 1.5 + r * 0.012
        box = S.box_centered("crack_%d" % i, size=(w, r * 3.0, h * 0.10),
                             location=(0, 0, z), rotation=(0, rng.uniform(-3, 3), 0))
        box.rotation_euler = Euler((0, 0, math.radians(rng.uniform(-6, 6))), "XYZ")
        S.apply_transforms(box)
        cutters.append(box)
    for c in cutters:
        S.boolean(bell, c, "DIFFERENCE")
    # The crack carried on round: from the top of the split it runs on, jagged and narrower,
    # round the whole bell between the waist and the shoulder, with a branch down each flank, so
    # some of it shows from every bearing. Each notch cuts the outer half of the wall, not
    # through it.
    def radius_at(zf):
        """The outer radius (metres) at a height given as a fraction of the bell's."""
        for (x0, y0), (x1, y1) in zip(prof_outer, prof_outer[1:]):
            if y0 <= zf <= y1:
                return x0 + (x1 - x0) * (zf - y0) / max(y1 - y0, 1e-6)
        return prof_outer[-1][0]
    notch_d = thickness * 0.7
    runs = [
        # (start angle deg, end angle deg, start height, end height, steps, width)
        (90.0, 450.0, 0.54, 0.80, 44, r * 0.035),     # round the waist and shoulder
        (10.0, 25.0, 0.62, 0.22, 9, r * 0.025),       # a branch down the east flank
        (200.0, 188.0, 0.70, 0.30, 9, r * 0.025),     # and the west
        (300.0, 315.0, 0.76, 0.46, 7, r * 0.02),      # and a short one at the back
    ]
    for (a0, a1, z0, z1, n, wid) in runs:
        for i in range(n):
            f = i / float(n - 1)
            a = math.radians(a0 + (a1 - a0) * f + rng.uniform(-2.5, 2.5))
            zf = z0 + (z1 - z0) * f + rng.uniform(-0.012, 0.012)
            rr = radius_at(zf)
            seg = TAU * rr / float(n) * abs(a1 - a0) / 360.0 * 1.25 if abs(a1 - a0) > 30 else h * 0.06
            notch = S.box_centered("crackrun", size=(notch_d * 2.0, max(seg, wid * 2.0), wid * rng.uniform(0.8, 1.6)),
                                   location=(math.cos(a) * rr, math.sin(a) * rr, zf * h),
                                   rotation=(rng.uniform(-25, 25), 0, math.degrees(a)))
            S.apply_transforms(notch)
            S.boolean(bell, notch, "DIFFERENCE")

    # Bite a doorway out of the lip on the opposite side, big enough to walk into.
    door = S.cylinder("door", radius=h * 0.075, depth=r * 3.0, vertices=14,
                      location=(0, -r * 1.2, h * 0.01), rotation=(-90, 0, 0))
    S.boolean(bell, door, "DIFFERENCE")
    S.shade_smooth(bell, 38.0)
    _weather(bell, rng, amount=r * 0.012, scale=h * 0.22, seed=rng.randrange(999))

    parts = [bell]
    # Crown: the canons (loops) a bell hangs from, flattened by the fall into a lookout.
    for i in range(6):
        a = TAU * i / 6
        loop = S.torus("canon_%d" % i, major=r * 0.13, minor=r * 0.042, seg_major=18, seg_minor=7,
                       location=(math.cos(a) * r * 0.115, math.sin(a) * r * 0.115, h * 1.0),
                       rotation=(72, 0, math.degrees(a) + 90), mat=metal)
        parts.append(loop)
    cap = S.lathe("crown_cap", [(r * 0.20, h * 0.975), (r * 0.235, h * 1.005), (r * 0.16, h * 1.03),
                                (0.0, h * 1.035)], segments=segs // 2, mat=metal)
    parts.append(cap)
    # Soundbow ring: the thickened band a bell is struck on.
    bow = S.torus("soundbow", major=r * 0.965, minor=r * 0.055, seg_major=segs, seg_minor=9,
                  location=(0, 0, h * 0.055), mat=metal)
    bow.scale = (1, 1, 0.7)
    S.apply_transforms(bow)
    parts.append(bow)
    # The mould lines: a heavy band where the shoulder turns, a lighter pair above and below
    # it, and one at the foot of the waist -- the rings a founder's mould leaves, which catch
    # the light and say "bell" from any side, over the trees as much as close to.
    for (zf, minor) in [(0.745, 0.05), (0.715, 0.022), (0.775, 0.022), (0.30, 0.026)]:
        rr = radius_at(zf)
        band = S.torus("mould_%d" % int(zf * 1000), major=rr + r * minor * 0.4, minor=r * minor,
                       seg_major=segs, seg_minor=8, location=(0, 0, h * zf), mat=metal)
        band.scale = (1, 1, 0.8)
        S.apply_transforms(band)
        parts.append(band)

    # The hill it is buried in. Not a disc round the foot: a chalk down that rises behind
    # the bell so a third of it is swallowed, with the white scar the fall cut down the
    # near face (WORLD_BIBLE §6.1). The bell itself is subtracted from the hill, so the
    # ground meets the bronze instead of clipping through it.
    if params.get("mound", True):
        ground = M.chalk_rock(pal, wear=0.5, age=0.6, scale=h * 0.06)
        mound = S.uv_sphere("mound", radius=1.0, segments=44, rings=22, mat=ground,
                            scale=(r * 3.1, r * 2.5, r * 1.35))
        S.apply_transforms(mound)
        mound.location = Vector((0, r * 1.5, -r * 0.35))
        S.apply_transforms(mound)
        # shear the hill so its crest leans away and the near face is a slope, not a dome
        for v in mound.data.vertices:
            f = max(0.0, (v.co.y - r * 0.2) / (r * 3.2))
            v.co.z += f * r * 0.85
        cut = S.box_centered("mcut", size=(r * 12, r * 12, r * 6), location=(0, 0, -r * 3.0))
        S.boolean(mound, cut, "DIFFERENCE")
        # the scar: a gouge running down the near face on the line the Toll came in on
        scar = S.box_centered("scar", size=(r * 0.95, r * 4.2, r * 0.9),
                              location=(r * 0.35, -r * 0.6, r * 0.55), rotation=(-22, 0, 7))
        S.boolean(mound, scar, "DIFFERENCE")
        # carve the bell's own volume out of the hill
        socket = S.lathe("socket", [(x * 1.03, z) for (x, z) in prof], segments=segs // 2, close=True)
        S.boolean(mound, socket, "DIFFERENCE")
        _weather(mound, rng, amount=r * 0.05, scale=h * 0.3, seed=rng.randrange(999))
        S.shade_smooth(mound, 42.0)
        # A chalk down is green on top; the chalk only shows where the ground was torn
        # open. Faces that lie flat get turf, and the steep cut faces of the scar and the
        # collar of bare ground round the bronze keep the chalk, which is what makes the
        # scar read as a scar rather than the whole hill as a meringue.
        turf = M.moss(pal, age=0.5, tint=0.45, scale=h * 0.045, name="toll_turf")
        bare_r = r * 1.3
        S.assign_material_to_faces(
            mound, turf,
            lambda poly: poly.normal.z > 0.62 and math.hypot(poly.center.x, poly.center.y) > bare_r)
        tris = S.tri_count(mound)
        if tris > 6000:
            S.decimate(mound, 6000.0 / tris)
            S.shade_smooth(mound, 42.0)
        parts.append(mound)
        # The ground heaved up round the lip where the bell drove into it: a low collar of torn
        # turf all the way round, highest against the bronze, with the chalk showing on its
        # steep inner lip; the doorway's side is left open to walk in by.
        # (low enough -- a twenty-fifth of the height -- that the flare still shows above it)
        heave = S.lathe("heave", [(r * 2.15, -h * 0.01), (r * 1.7, h * 0.008), (r * 1.4, h * 0.022),
                                  (r * 1.15, h * 0.036), (r * 1.03, h * 0.04), (r * 0.97, h * 0.02),
                                  (r * 0.97, -h * 0.01)], segments=segs, mat=turf, close=True)
        _weather(heave, rng, amount=r * 0.04, scale=h * 0.12, seed=rng.randrange(999))
        heave_socket = S.lathe("hsocket", [(x * 1.02, z) for (x, z) in prof], segments=segs // 2, close=True)
        S.boolean(heave, heave_socket, "DIFFERENCE")
        walk_in = S.box_centered("walkin", size=(h * 0.19, r * 1.6, h * 0.2), location=(0, -r * 1.35, h * 0.1))
        S.boolean(heave, walk_in, "DIFFERENCE")
        S.assign_material_to_faces(heave, ground, lambda poly: poly.normal.z < 0.45)
        S.shade_smooth(heave, 42.0)
        parts.append(heave)

    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["bell_bronze_patina", "chalk_rock"],
            "extra_meta": {"walkable": ["lip", "crown"], "height_m": h,
                           "place": "core:place/cracked_toll"}}


def bmesh_fix(obj):
    """Weld the lathe seam and recompute normals after building a shell profile."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# --- the Fallen Hand (Skerrow) -----------------------------------------------------------

def _finger(name, mat, rng, base, direction, length, radius, curl=0.35, segments=9):
    """One finger: three phalanges with knuckle swellings, curling slightly inward."""
    parts = []
    d = Vector(direction).normalized()
    up = Vector((0, 0, 1))
    side = d.cross(up).normalized()
    pos = Vector(base)
    fracs = (0.42, 0.33, 0.25)
    for i, frac in enumerate(fracs):
        ln = length * frac
        r = radius * (1.0 - 0.14 * i)
        pts = []
        for k in range(4):
            t = k / 3.0
            bend = curl * (i + t) / len(fracs)
            p = pos + d * (ln * t) - up * (ln * t * bend * 0.55)
            p += side * math.sin(t * math.pi) * ln * 0.02 * rng.uniform(-1, 1)
            pts.append(p)
        shaft = S.tube_along("%s_ph%d" % (name, i), pts, radius=r * 0.84, segments=segments,
                             radius_end=r * 0.76, mat=mat)
        parts.append(shaft)
        knuckle = S.sphere("%s_kn%d" % (name, i), radius=r, subdivisions=3, location=pos, mat=mat,
                           scale=(1.0, 1.0, 0.92))
        S.apply_transforms(knuckle)
        parts.append(knuckle)
        pos = pts[-1]
    tip = S.sphere("%s_tip" % name, radius=radius * 0.62, subdivisions=3, location=pos, mat=mat,
                   scale=(1.15, 1.0, 0.8))
    S.apply_transforms(tip)
    parts.append(tip)
    return parts


def fallen_hand(pal, rng, params, variant):
    """A giant's stone hand 60 m long, palm up, fingers as tall as towers, with a clan
    shrine in its cup (WORLD_BIBLE §6.5). The palm is a walkable floor."""
    length = params.get("length", 60.0)
    # At length*0.05 the pattern is one blob across sixty metres and the hand bakes out as
    # flat bone; halving the scale puts a couple of metres between tonal changes, which is
    # what a weathered surface this size needs to stop reading as plastic.
    stone = M.limestone(pal, wear=0.6, age=0.9, scale=length * 0.026)
    palm_l = length * 0.40
    palm_w = length * 0.34
    palm_t = length * 0.10

    # Palm: a dished slab, thicker at the heel, hollowed so it holds water and a shrine.
    palm = S.uv_sphere("palm", radius=1.0, segments=44, rings=24, mat=stone)
    palm.scale = Vector((palm_w * 0.5, palm_l * 0.5, palm_t))
    S.apply_transforms(palm)
    cut = S.box_centered("pcut", size=(palm_w * 3, palm_l * 3, palm_t * 2),
                         location=(0, 0, -palm_t * 1.02))
    S.boolean(palm, cut, "DIFFERENCE")
    # the cup
    dish = S.uv_sphere("dish", radius=1.0, segments=36, rings=20,
                       scale=(palm_w * 0.34, palm_l * 0.34, palm_t * 0.95))
    S.apply_transforms(dish)
    dish.location = Vector((0, -palm_l * 0.03, palm_t * 0.72))
    S.apply_transforms(dish)
    S.boolean(palm, dish, "DIFFERENCE")
    S.shade_smooth(palm, 40.0)
    _weather(palm, rng, amount=length * 0.004, scale=length * 0.16, seed=rng.randrange(999))
    parts = [palm]

    # Fingers fanning off the far edge, index to little, plus a thumb off the side.
    finger_len = length * 0.42
    for i in range(4):
        f = i / 3.0
        x = (-0.34 + 0.23 * i) * palm_w
        spread = math.radians(-16 + 11 * i)
        scale = (1.0, 0.98, 0.9, 0.78)[i]
        base = Vector((x, palm_l * 0.42, palm_t * 0.18))
        d = Vector((math.sin(spread), math.cos(spread), 0.16))
        parts += _finger("finger%d" % i, stone, rng, base, d, finger_len * scale,
                         length * 0.046 * scale, curl=0.30 + 0.06 * f)
    thumb_base = Vector((-palm_w * 0.46, -palm_l * 0.06, palm_t * 0.2))
    parts += _finger("thumb", stone, rng, thumb_base, Vector((-0.75, 0.55, 0.25)),
                     finger_len * 0.72, length * 0.055, curl=0.22)

    # Wrist: a broken stump, torn off rather than cut.
    wrist = S.cylinder("wrist", radius=palm_w * 0.34, radius_top=palm_w * 0.30, depth=length * 0.16,
                       vertices=22, location=(0, -palm_l * 0.48, palm_t * 0.1),
                       rotation=(-96, 0, 0), mat=stone)
    _weather(wrist, rng, amount=length * 0.008, scale=length * 0.08, seed=rng.randrange(999))
    parts.append(wrist)

    for p in parts:
        if p is not palm:
            _weather(p, rng, amount=length * 0.002, scale=length * 0.09, seed=rng.randrange(999))
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["limestone"],
            "extra_meta": {"walkable": ["palm"], "length_m": length,
                           "place": "core:place/fallen_hand"}}


# --- the Sunken Choir colossus (Cinderlea) -------------------------------------------------

def choir_colossus(pal, rng, params, variant):
    """One of the twelve headless robed colossi, ~50 m, weathered fused stone, old gilding
    in the folds (WORLD_BIBLE §6.6). Twelve of these make the Choir ring."""
    h = params.get("height", 50.0)
    stone = M.fused_stone(pal, wear=0.45, age=0.85, gilding=params.get("gilding", 0.35),
                          scale=h * 0.05)
    parts = []
    # Robe: a lathed bell of cloth, wider at the hem, with vertical folds.
    hem_r = h * 0.20
    prof = [
        (hem_r * 1.02, 0.0), (hem_r * 1.04, h * 0.02), (hem_r * 0.97, h * 0.10),
        (hem_r * 0.90, h * 0.24), (hem_r * 0.84, h * 0.38), (hem_r * 0.79, h * 0.50),
        (hem_r * 0.76, h * 0.60), (hem_r * 0.78, h * 0.68), (hem_r * 0.72, h * 0.75),
        (hem_r * 0.58, h * 0.80), (hem_r * 0.40, h * 0.83),
    ]
    folds = int(params.get("folds", 26))
    robe = S.lathe("robe", prof, segments=folds * 2, mat=stone, close=True)
    for v in robe.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = math.cos(a * folds)
        f = 1.0 + 0.035 * k * (0.35 + 0.65 * min(1.0, v.co.z / (h * 0.7)))
        v.co.x *= f
        v.co.y *= f
    S.shade_smooth(robe, 34.0)
    parts.append(robe)
    # Shoulders and chest above the robe.
    torso = S.lathe("torso", [(hem_r * 0.40, h * 0.82), (hem_r * 0.52, h * 0.86),
                              (hem_r * 0.60, h * 0.90), (hem_r * 0.56, h * 0.95),
                              (hem_r * 0.34, h * 0.975)], segments=folds, mat=stone)
    parts.append(torso)
    # The neck, snapped off: the Choir is headless, and the break is the point.
    neck = S.cylinder("neck", radius=hem_r * 0.20, radius_top=hem_r * 0.17, depth=h * 0.035,
                      vertices=18, location=(0, 0, h * 0.97), mat=stone)
    _weather(neck, rng, amount=h * 0.004, scale=h * 0.02, seed=rng.randrange(999))
    parts.append(neck)
    # Arms folded across the body: upper arms hang close to the sides, forearms come in and
    # meet at the waist. Built as swept tubes rather than cylinders so the elbow bends;
    # straight cylinders off the shoulders read as a crossbar, not as arms.
    for sgn in (-1, 1):
        shoulder = Vector((sgn * hem_r * 0.52, 0.0, h * 0.905))
        elbow = Vector((sgn * hem_r * 0.60, -hem_r * 0.16, h * 0.775))
        wrist = Vector((sgn * hem_r * 0.26, -hem_r * 0.40, h * 0.715))
        arm = S.tube_along("arm%d" % sgn, [shoulder,
                                           shoulder.lerp(elbow, 0.55) + Vector((sgn * hem_r * 0.03, 0, 0)),
                                           elbow,
                                           elbow.lerp(wrist, 0.5) + Vector((0, -hem_r * 0.05, 0)),
                                           wrist],
                           radius=hem_r * 0.135, segments=12, radius_end=hem_r * 0.085, mat=stone)
        parts.append(arm)
        hand = S.sphere("hand%d" % sgn, radius=hem_r * 0.105, subdivisions=3,
                        location=(sgn * hem_r * 0.13, -hem_r * 0.44, h * 0.705), mat=stone,
                        scale=(1.0, 1.3, 0.72))
        S.apply_transforms(hand)
        parts.append(hand)
    # Plinth of fused stone, cracked and sunk.
    plinth = S.cylinder("plinth", radius=hem_r * 1.35, radius_top=hem_r * 1.22, depth=h * 0.045,
                        vertices=folds, location=(0, 0, -h * 0.042), mat=stone)
    _weather(plinth, rng, amount=h * 0.004, scale=h * 0.06, seed=rng.randrange(999))
    parts.append(plinth)

    for p in parts:
        _weather(p, rng, amount=h * 0.0016, scale=h * 0.11, seed=rng.randrange(999))
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["fused_stone"],
            "extra_meta": {"height_m": h, "headless": True, "place": "core:place/sunken_choir",
                           "ring_count": 12}}


# --- the Lamp (Brightwater lighthouse) ------------------------------------------------------

def the_lamp(pal, rng, params, variant):
    """The lighthouse whose light sweeps the Mere at night (WORLD_BIBLE §6.2): lime-washed
    tapering tower, brass gallery and lantern room."""
    h = params.get("height", 34.0)
    base_r = h * 0.135
    top_r = base_r * 0.56
    walls = M.plaster_limewash(pal, wear=0.5, age=0.6, scale=h * 0.06)
    stone = M.stone_blocks(pal, wear=0.5, age=0.6, scale=h * 0.05, block_w=1.2, block_h=0.5)
    metal = M.brass(pal, age=0.6, wear=0.5, scale=h * 0.02)
    iron = M.iron(pal, age=0.7, wear=0.6, scale=h * 0.02)
    glass = M.glass(pal)
    parts = []
    body_h = h * 0.80
    tower = S.lathe("tower", [(base_r * 1.16, 0.0), (base_r * 1.12, body_h * 0.035),
                              (base_r, body_h * 0.06),
                              (base_r * 0.86, body_h * 0.35), (base_r * 0.74, body_h * 0.62),
                              (top_r, body_h)], segments=34, mat=walls, close=False)
    parts.append(tower)
    plinth = S.lathe("plinth", [(base_r * 1.30, 0.0), (base_r * 1.28, h * 0.02),
                                (base_r * 1.16, h * 0.055)], segments=34, mat=stone, close=True)
    parts.append(plinth)
    # Painted bands: a second lathe shell just proud of the tower, in the region's accent.
    band_mat = M.plaster_limewash(pal, wear=0.6, age=0.5, scale=h * 0.06,
                                  base_hex="#b8432f", name="lamp_band")
    for (z0, z1) in ((0.24, 0.36), (0.60, 0.72)):
        zz0, zz1 = body_h * z0, body_h * z1
        r0 = base_r + (top_r - base_r) * z0
        r1 = base_r + (top_r - base_r) * z1
        band = S.lathe("band_%.2f" % z0, [(r0 * 1.012, zz0), (r1 * 1.012, zz1)], segments=34,
                       mat=band_mat, close=False)
        parts.append(band)
    # Gallery: corbel ring, deck, brass railing.
    gal_z = body_h
    gal_r = top_r * 1.75
    corbel = S.lathe("corbel", [(top_r * 1.02, gal_z - h * 0.05), (gal_r, gal_z - h * 0.008),
                                (gal_r, gal_z)], segments=34, mat=stone, close=False)
    parts.append(corbel)
    deck = S.cylinder("deck", radius=gal_r, depth=h * 0.012, vertices=34, location=(0, 0, gal_z), mat=stone)
    parts.append(deck)
    rail_h = h * 0.045
    for i in range(22):
        a = TAU * i / 22
        post = S.cylinder("post_%d" % i, radius=h * 0.0045, depth=rail_h, vertices=6,
                          location=(math.cos(a) * gal_r * 0.93, math.sin(a) * gal_r * 0.93, gal_z + h * 0.012),
                          mat=metal)
        parts.append(post)
    for rz in (0.55, 1.0):
        ring = S.torus("rail_%.2f" % rz, major=gal_r * 0.93, minor=h * 0.005, seg_major=40, seg_minor=6,
                       location=(0, 0, gal_z + h * 0.012 + rail_h * rz), mat=metal)
        parts.append(ring)
    # Lantern room: glazed drum with vertical astragals, domed cap and a finial.
    lan_r = top_r * 1.02
    lan_h = h * 0.115
    lz = gal_z + h * 0.014
    drum = S.lathe("lantern_glass", [(lan_r, lz), (lan_r, lz + lan_h)], segments=26, mat=glass, close=False)
    parts.append(drum)
    for i in range(12):
        a = TAU * i / 12
        bar = S.cylinder("astragal_%d" % i, radius=h * 0.004, depth=lan_h, vertices=5,
                         location=(math.cos(a) * lan_r * 1.02, math.sin(a) * lan_r * 1.02, lz), mat=metal)
        parts.append(bar)
    dome = S.lathe("dome", [(lan_r * 1.12, lz + lan_h), (lan_r * 1.05, lz + lan_h * 1.12),
                            (lan_r * 0.72, lz + lan_h * 1.45), (lan_r * 0.30, lz + lan_h * 1.68),
                            (0.0, lz + lan_h * 1.78)], segments=26, mat=metal, close=False)
    parts.append(dome)
    finial = S.cylinder("finial", radius=h * 0.006, radius_top=0.0, depth=h * 0.045, vertices=8,
                        location=(0, 0, lz + lan_h * 1.78), mat=metal)
    parts.append(finial)
    # Door and two windows, cut so the tower reads as inhabited.
    door = S.box_centered("door", size=(base_r * 0.52, base_r * 3, h * 0.075),
                          location=(0, -base_r, h * 0.037))
    S.boolean(tower, door, "DIFFERENCE")
    for i, z in enumerate((0.26, 0.48, 0.68)):
        a = TAU * (i * 0.37)
        wz = body_h * z
        wr = base_r + (top_r - base_r) * z
        win = S.box_centered("win_%d" % i, size=(wr * 0.30, wr * 3, h * 0.03),
                             location=(0, 0, wz), rotation=(0, 0, math.degrees(a)))
        S.boolean(tower, win, "DIFFERENCE")
    S.shade_smooth(tower, 38.0)
    # a lantern-room emissive core so the light reads at night
    core = S.sphere("lamp_core", radius=lan_r * 0.42, subdivisions=2,
                    location=(0, 0, lz + lan_h * 0.5), mat=M.ember(pal, heat=1.4, name="lamp_flame"))
    parts.append(core)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["plaster_limewash", "stone_blocks", "brass", "glass"],
            "extra_meta": {"height_m": h, "emissive": True, "place": "core:place/the_lamp"}}


# --- the Sayers' Spire (Brightwater) ---------------------------------------------------------

def sayers_spire(pal, rng, params, variant):
    """A black Oroth stalk with a brass crown of human construction (WORLD_BIBLE §6.2):
    the Builders' shaft is smooth and faintly flowing, the crown is riveted and patinated."""
    h = params.get("height", 68.0)
    r = h * 0.055
    oroth = M.fused_stone(pal, wear=0.35, age=0.6, gilding=0.12, scale=h * 0.04)
    crown_mat = M.brass(pal, age=0.75, wear=0.5, scale=h * 0.012)
    parts = []
    # The stalk: not a cylinder but a slowly twisting, slightly asymmetric blade of stone.
    stalk_h = h * 0.80
    prof = []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        rr = r * (1.0 - 0.52 * t ** 1.25) * (1.0 + 0.09 * math.sin(t * math.pi * 2.3))
        prof.append((rr, stalk_h * t))
    stalk = S.lathe("stalk", prof, segments=9, mat=oroth, close=True,
                    twist=params.get("twist", 0.012))
    for v in stalk.data.vertices:
        f = v.co.z / stalk_h
        v.co.x *= 1.0 + 0.16 * f  # leans into a blade rather than a tube
        v.co.y *= 1.0 - 0.10 * f
    S.subdivide(stalk, levels=1)
    S.shade_smooth(stalk, 30.0)
    _weather(stalk, rng, amount=r * 0.03, scale=h * 0.2, seed=rng.randrange(999))
    parts.append(stalk)
    base = S.lathe("spire_base", [(r * 1.9, 0.0), (r * 1.75, h * 0.012), (r * 1.25, h * 0.05),
                                  (r * 1.02, h * 0.09)], segments=9, mat=oroth, close=True)
    parts.append(base)
    # The crown: a brass cage the Sayers built on top, ring beams and ribs, with a bell.
    cz = stalk_h
    cr = r * 0.82
    for i, (rz, rr) in enumerate(((0.0, 1.0), (0.42, 1.55), (0.80, 1.35), (1.0, 0.85))):
        ring = S.torus("crown_ring_%d" % i, major=cr * rr, minor=h * 0.0045, seg_major=26, seg_minor=6,
                       location=(0, 0, cz + h * 0.17 * rz), mat=crown_mat)
        parts.append(ring)
    for i in range(10):
        a = TAU * i / 10
        pts = []
        for k in range(6):
            t = k / 5.0
            rr = cr * (1.0 + 0.62 * math.sin(t * math.pi * 0.95))
            pts.append((math.cos(a) * rr, math.sin(a) * rr, cz + h * 0.17 * t))
        rib = S.tube_along("crown_rib_%d" % i, pts, radius=h * 0.004, segments=6, mat=crown_mat)
        parts.append(rib)
    bell = S.lathe("crown_bell", [(cr * 0.52, cz + h * 0.055), (cr * 0.47, cz + h * 0.085),
                                  (cr * 0.36, cz + h * 0.115), (cr * 0.16, cz + h * 0.135),
                                  (cr * 0.06, cz + h * 0.142)], segments=20, mat=crown_mat, close=False)
    parts.append(bell)
    spike = S.cylinder("crown_spike", radius=h * 0.006, radius_top=0.0, depth=h * 0.06, vertices=8,
                       location=(0, 0, cz + h * 0.17), mat=crown_mat)
    parts.append(spike)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["fused_stone", "brass"],
            "extra_meta": {"height_m": h, "place": "core:place/sayers_spire"}}


# --- the Grandfather (Briarwold) ----------------------------------------------------------

def grandfather(pal, rng, params, variant):
    """The dead tree the Woodfolk live in: 90 m tall, 30 m across, hollow, lit in its knots.

    WORLD_BIBLE Briarwold. This is the largest single object in the game and it has to read
    from most of the region, so the silhouette does the work: a colossal flared bole, a
    trunk that snapped rather than tapered away, and three heavy limbs left of a crown that
    is long gone. Close to, it has to read as a town -- the split in the bole is a doorway
    the height of a house, the knots are windows with light behind them, and the rope walks
    spiral the outside, because a town inside a tree has to get up it somehow.

    The bole is a shell, not a post: it is hollowed, so from the doorway you see up inside.
    """
    h = params.get("height", 90.0)
    across = params.get("across", 30.0)
    # Briarwold's own tree, dead but still barked: black ash, deep-fissured, lichened. At
    # the default one-metre feature size a thirty-metre bole bakes out speckled like
    # concrete, so the bark is scaled to the thing it is on.
    bark = M.black_ash_bark(pal, age=0.9, tint=0.28, scale=3.4)
    inner = M.driftwood(pal, wear=0.7, age=0.85, scale=h * 0.03, name="grandfather_inner")
    deck = M.wood_planks(pal, wear=0.65, age=0.7, scale=1.2, name="grandfather_deck")
    glow = M.ember(pal, heat=1.15, name="grandfather_knot_light")
    parts = []

    # The bole. Widest at the root flare, drawn in hard above it, then near-parallel to the
    # break: a dead trunk that lost its crown keeps its girth far further up than a live one.
    r = across * 0.5
    prof = [
        (r * 1.00, 0.0), (r * 0.94, h * 0.015), (r * 0.80, h * 0.05),
        (r * 0.68, h * 0.11), (r * 0.60, h * 0.20), (r * 0.55, h * 0.32),
        (r * 0.51, h * 0.45), (r * 0.47, h * 0.58), (r * 0.43, h * 0.70),
        (r * 0.39, h * 0.80), (r * 0.35, h * 0.88), (r * 0.30, h * 0.95),
        (r * 0.26, h * 0.99),
    ]
    segs = int(params.get("segments", 40))
    trunk = S.lathe("bole", prof, segments=segs, mat=bark, close=False,
                    twist=rng.uniform(-0.06, 0.06))
    # Lean the whole tree a little: nothing this old stands plumb.
    trunk.rotation_euler = Euler((math.radians(rng.uniform(1.6, 3.4)), 0.0,
                                  rng.uniform(0, TAU)), "XYZ")
    S.apply_transforms(trunk)

    # Hollow it. A shell about a metre and a half thick, which is what the rooms are cut into.
    wall = params.get("wall", 1.6)
    void = S.lathe("void", [(max(0.4, rr - wall), zz) for (rr, zz) in prof],
                   segments=segs, close=True)
    void.rotation_euler = trunk.rotation_euler.copy()
    S.apply_transforms(void)
    S.boolean(trunk, void, "DIFFERENCE")

    # The doorway: a split in the bole the height of a house, and the way in.
    door_h = h * 0.1
    door = S.box_centered("door", size=(across * 0.26, across * 1.2, door_h),
                          location=(0.0, -r * 0.75, door_h * 0.5 - 0.4))
    S.boolean(trunk, door, "DIFFERENCE")
    # An arched head to it, so it reads as a door and not as a saw cut.
    arch = S.cylinder("arch", radius=across * 0.13, depth=across * 1.2, vertices=16,
                      location=(0.0, -r * 1.35, door_h - 0.4), rotation=(-90, 0, 0), centered=False)
    S.boolean(trunk, arch, "DIFFERENCE")

    # Knots: the windows, scattered up the trunk on every side, each with a light behind it.
    knots = int(params.get("knots", 26))
    lights = []
    for i in range(knots):
        f = 0.10 + 0.82 * (i / max(1, knots - 1)) ** 0.85
        a = rng.uniform(0, TAU)
        rad = _profile_radius(prof, f * h) * 1.25
        kr = across * rng.uniform(0.018, 0.045)
        pos = Vector((math.cos(a) * rad, math.sin(a) * rad, f * h))
        cut = S.uv_sphere("knot_%d" % i, radius=kr, segments=12, rings=8,
                          scale=(1.0, 1.0, rng.uniform(0.6, 1.1)))
        S.apply_transforms(cut)
        cut.location = pos
        S.apply_transforms(cut)
        S.boolean(trunk, cut, "DIFFERENCE")
        # The light sits just inside the hole, so the knot glows from within.
        if rng.random() < 0.72:
            lamp = S.uv_sphere("knotlight_%d" % i, radius=kr * 0.72, segments=10, rings=6,
                               mat=glow)
            lamp.location = Vector((pos.x * 0.86, pos.y * 0.86, pos.z))
            S.apply_transforms(lamp)
            lights.append(lamp)

    # The break. A dead giant did not taper away politely, it snapped, and this is the edge
    # the region sees against the sky -- the one silhouette detail worth paying for.
    for i in range(int(params.get("break_teeth", 7))):
        a = TAU * (i + rng.uniform(-0.25, 0.25)) / int(params.get("break_teeth", 7))
        top_r = _profile_radius(prof, h)
        bite = S.box_centered("break_%d" % i,
                              size=(top_r * rng.uniform(0.5, 1.1), top_r * rng.uniform(0.5, 1.2),
                                    h * rng.uniform(0.02, 0.07)),
                              location=(math.cos(a) * top_r * rng.uniform(0.55, 1.05),
                                        math.sin(a) * top_r * rng.uniform(0.55, 1.05), h),
                              rotation=(rng.uniform(-22, 22), rng.uniform(-22, 22), 0))
        S.boolean(trunk, bite, "DIFFERENCE")
    S.shade_smooth(trunk, 38.0)
    _weather(trunk, rng, amount=across * 0.022, scale=h * 0.09, seed=rng.randrange(999))
    parts.append(trunk)
    parts += lights

    # A sleeve of the inner wood showing through the doorway, so the bole is not a paper
    # tube when you stand in the opening.
    sleeve = S.lathe("sleeve", [(max(0.35, rr - wall - 0.25), zz) for (rr, zz) in prof],
                     segments=max(12, segs // 2), mat=inner, close=False)
    sleeve.rotation_euler = trunk.rotation_euler.copy()
    S.apply_transforms(sleeve)
    S.shade_smooth(sleeve, 38.0)
    parts.append(sleeve)

    # Root buttresses: what makes thirty metres across believable at the foot.
    roots = int(params.get("roots", 9))
    for i in range(roots):
        a = TAU * (i + rng.uniform(-0.18, 0.18)) / roots
        rh = h * rng.uniform(0.055, 0.11)
        reach = r * rng.uniform(0.55, 1.0)
        bm = bmesh.new()
        steps = 8
        inner_e, outer_e = [], []
        for k in range(steps + 1):
            f = k / steps
            z = rh * (f ** 0.75)
            inner_e.append(bm.verts.new((r * 0.86, 0.0, z)))
            outer_e.append(bm.verts.new((r * 0.86 + reach * (1 - f) ** 1.7, 0.0, z * 0.2)))
        for a0, b0, a1, b1 in zip(inner_e, outer_e, inner_e[1:], outer_e[1:]):
            bm.faces.new((a0, b0, b1, a1))
        root = S.bm_to_object(bm, "root_%d" % i, bark, smooth=True)
        S.solidify(root, thickness=r * rng.uniform(0.12, 0.2), offset=0.0)
        S.bevel(root, width=r * 0.03, segments=2, angle_deg=40)
        root.rotation_euler = Euler((0, 0, a), "XYZ")
        S.apply_transforms(root)
        S.jitter_verts(root, amount=r * 0.02, scale=3.0, seed=rng.randrange(999))
        parts.append(root)

    # Three heavy limbs, all that is left of the crown, and the broken stubs of others.
    for i in range(3):
        a = TAU * i / 3 + rng.uniform(-0.3, 0.3)
        base_z = h * rng.uniform(0.62, 0.80)
        rad0 = _profile_radius(prof, base_z)
        start = Vector((math.cos(a) * rad0 * 0.9, math.sin(a) * rad0 * 0.9, base_z))
        reach = across * rng.uniform(0.9, 1.5)
        rise = h * rng.uniform(0.06, 0.13)
        pts = [start,
               start + Vector((math.cos(a) * reach * 0.42, math.sin(a) * reach * 0.42, rise * 0.7)),
               start + Vector((math.cos(a + 0.22) * reach * 0.78, math.sin(a + 0.22) * reach * 0.78, rise)),
               start + Vector((math.cos(a + 0.5) * reach, math.sin(a + 0.5) * reach, rise * 0.78))]
        limb = S.tube_along("limb_%d" % i, pts, radius=rad0 * 0.46, segments=12,
                            radius_end=rad0 * 0.17, mat=bark)
        S.shade_smooth(limb, 40.0)
        parts.append(limb)
    for i in range(int(params.get("stubs", 6))):
        a = rng.uniform(0, TAU)
        z = h * rng.uniform(0.35, 0.9)
        rad0 = _profile_radius(prof, z)
        stub = S.cylinder("stub_%d" % i, radius=rad0 * rng.uniform(0.11, 0.2),
                          radius_top=rad0 * rng.uniform(0.05, 0.11),
                          depth=rad0 * rng.uniform(0.5, 1.2), vertices=9,
                          location=(math.cos(a) * rad0 * 0.85, math.sin(a) * rad0 * 0.85, z),
                          rotation=(0, 74, math.degrees(a)), mat=bark)
        parts.append(stub)

    # The rope walks. A town inside a tree has to get up it, and from a distance these are
    # the thing that says someone lives here rather than that a tree died here.
    turns = params.get("walk_turns", 2.4)
    walk_lo, walk_hi = h * 0.06, h * 0.78
    ring = int(params.get("walk_segments", 96))
    prev = None
    for i in range(ring + 1):
        f = i / ring
        z = walk_lo + (walk_hi - walk_lo) * f
        a = TAU * turns * f
        rad = _profile_radius(prof, z) * 1.06
        pos = Vector((math.cos(a) * rad, math.sin(a) * rad, z))
        if prev is not None and i % 2 == 0:
            span = (pos - prev).length
            plank = S.box_centered("walk_%d" % i, size=(across * 0.09, span * 1.5, 0.22),
                                   mat=deck)
            ang = math.atan2(pos.y - prev.y, pos.x - prev.x)
            plank.rotation_euler = Euler((0, 0, ang - math.pi / 2), "XYZ")
            S.apply_transforms(plank)
            plank.location = (pos + prev) * 0.5
            S.apply_transforms(plank)
            parts.append(plank)
            mid = (pos + prev) * 0.5
            if i % 6 == 0:
                parts.append(S.cylinder("walkpost_%d" % i, radius=0.22, depth=h * 0.035,
                                        vertices=7,
                                        location=(mid.x, mid.y, mid.z - h * 0.035), mat=deck))
                # the handrail post, which is what gives the spiral its edge against the sky
                parts.append(S.cylinder("rail_%d" % i, radius=0.14, depth=1.1, vertices=6,
                                        location=(mid.x, mid.y, mid.z + 0.1), mat=deck))
        prev = pos
    # A landing outside the doorway, where the walks start.
    parts.append(S.box_centered("landing", size=(across * 0.34, across * 0.2, 0.16),
                                location=(0.0, -r * 0.92, h * 0.055), mat=deck))

    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["dead_bark", "driftwood", "wood_planks", "ember"],
            "extra_meta": {"walkable": ["landing", "walk"], "height_m": h,
                           "across_m": across, "hollow": True,
                           "place": "core:place/grandfather"}}


def _profile_radius(prof, z):
    """Radius of a lathe profile at height z, linearly interpolated."""
    if z <= prof[0][1]:
        return prof[0][0]
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z <= z1:
            t = (z - z0) / max(1e-6, z1 - z0)
            return r0 + (r1 - r0) * t
    return prof[-1][0]


# --- the Chalk Hound (Hearthvale) ---------------------------------------------------------

def chalk_hound(pal, rng, params, variant):
    """A hill figure: turf cut away to show the chalk under the down.

    WORLD_BIBLE Hearthvale. This is not an object standing on the ground, it is a figure
    *in* it, so it is built as a shallow shell that lies on the slope -- a trench floor of
    bare chalk with a turf lip round it. From the far side of the valley the outline has to
    read as a hound; standing in it you are in a chalk cutting a little deeper than a grave,
    and the eye is a ring you can lie down in.

    It is laid out flat in XY, running nose-east, so a placer can drop it on a slope and
    rotate it to the fall of the hill.
    """
    length = params.get("length", 58.0)
    scale = length / 58.0
    chalk = M.chalk_rock(pal, wear=0.3, age=0.35, scale=6.0, name="hound_chalk")
    depth = params.get("depth", 0.55)
    parts = []

    # The figure, as the strokes a hill-cutter would actually cut: a long body, a deep
    # chest, a thrown-back head, four legs at full stretch, a tail up.
    # (x, y, half-width) polylines in metres, nose towards +x.
    strokes = [
        # body and haunch
        ([(-16, 0.5), (-8, 1.4), (0, 1.6), (8, 1.2), (15, 0.4)], 3.4),
        # chest and shoulder
        ([(9, 0.0), (13, 1.8), (16, 2.6)], 2.6),
        # neck and head, thrown back and up
        ([(15, 1.0), (20, 3.4), (24, 5.6), (27.5, 6.2)], 1.9),
        # muzzle
        ([(27, 6.2), (30.5, 6.0)], 1.1),
        # foreleg, forward
        ([(13, -0.6), (17, -5.0), (21, -8.6)], 1.3),
        # foreleg, tucked
        ([(10.5, -0.6), (12, -4.4), (10, -7.8)], 1.2),
        # hind leg, driving back
        ([(-11, -0.4), (-16, -4.2), (-22, -6.8)], 1.5),
        # hind leg, gathered
        ([(-7, -0.6), (-8.5, -4.6), (-12, -7.4)], 1.3),
        # tail, up and streaming
        ([(-16, 0.8), (-22, 2.6), (-27, 5.4)], 1.0),
    ]
    bm = bmesh.new()
    for (pts, half) in strokes:
        pts = [(x * scale, y * scale) for (x, y) in pts]
        hw = half * scale
        left, right = [], []
        n = len(pts)
        for i, (x, y) in enumerate(pts):
            # taper the stroke towards its far end, the way a cut limb thins
            t = i / max(1, n - 1)
            w = hw * (1.0 - 0.45 * t)
            if i == 0:
                dx, dy = pts[1][0] - x, pts[1][1] - y
            elif i == n - 1:
                dx, dy = x - pts[-2][0], y - pts[-2][1]
            else:
                dx, dy = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln, dx / ln
            left.append(bm.verts.new((x + nx * w, y + ny * w, 0.0)))
            right.append(bm.verts.new((x - nx * w, y - ny * w, 0.0)))
        for a0, b0, a1, b1 in zip(left, right, left[1:], right[1:]):
            bm.faces.new((a0, b0, b1, a1))
    floor = S.bm_to_object(bm, "hound_floor", chalk, smooth=False)
    # Sink it: the figure is a cutting, so its floor sits below the turf line, and give it
    # walls by thickening downward -- those cut faces are the sides of the trench.
    #
    # What it must NOT have is a turf skin over the top. The first cut of this laid a
    # copy of the whole figure in grass above the chalk, so the hound was a green hound on
    # a green down, which is no hill figure at all. The white is the entire point; the turf
    # around it is the terrain's job, not the forge's.
    for v in floor.data.vertices:
        v.co.z -= depth
    S.subdivide(floor, levels=2, simple=False)
    S.jitter_verts(floor, amount=depth * 0.22, scale=2.0, seed=rng.randrange(999))
    S.solidify(floor, thickness=depth * 1.25, offset=1.0)
    parts.append(floor)

    # There is deliberately no turf here. A hill figure is the chalk; the grass around it
    # is the down, which is the terrain's, not the forge's. Two attempts at a turf lip both
    # ended up skinning the whole figure green -- a green hound on a green down, which is
    # no hill figure at all -- and the honest answer is that the forge should ship the cut
    # and nothing else.

    # The eye: a ring of cut chalk with a hollow in the middle, sized so a person fits.
    eye = Vector((26.0 * scale, 5.4 * scale, -depth))
    socket = S.lathe("eye", [(0.0, 0.0), (1.05, 0.0), (1.25, 0.34), (1.9, 0.44), (2.0, 0.0)],
                     segments=22, mat=chalk, close=True)
    socket.location = eye
    S.apply_transforms(socket)
    S.jitter_verts(socket, amount=0.06, scale=1.2, seed=rng.randrange(999))
    parts.append(socket)

    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "trimesh", "tier": "hero",
            "materials_used": ["chalk_rock"],
            "extra_meta": {"lies_on_ground": True, "length_m": length, "cut_depth_m": depth,
                           "eye_centre_m": [round(eye.x, 2), round(eye.y, 2)],
                           "place": "core:place/chalk_hound"}}


# --- the Drowned Nave (Sedgemire) ----------------------------------------------------------

def drowned_nave(pal, rng, params, variant):
    """An Oroth spire leaning fifteen degrees out of the marsh, its lower half flooded.

    WORLD_BIBLE Sedgemire: 120 m, leaning 15 degrees, lower half under water. What is built
    here is what shows -- the upper spire and the tops of the nave arcade around its foot,
    with the waterline written on the stone: black weed below it, pale fused stone above.
    It is the thing you see before you go down, so the lean is the whole silhouette and it
    must be unmistakable from across the fen.
    """
    h = params.get("height", 120.0)
    lean = math.radians(params.get("lean_deg", 15.0))
    # How much of it stands above the fen. The rest is the deep place.
    show = params.get("above_water", 0.52)
    stone = M.fused_stone(pal, wear=0.4, age=0.8, gilding=params.get("gilding", 0.18), scale=h * 0.045)
    drowned = M.drowned_stone(pal, age=0.9, scale=h * 0.03, name="nave_drowned")
    parts = []

    # The spire: an Oroth tower, square-shouldered at the base and drawn to a point, with
    # the flutes that mark Builders' work.
    flutes = int(params.get("flutes", 16))
    # A hundred-and-twenty-metre tower ten metres across its foot. At h * 0.055 it came out
    # a needle: correct in height and unreadable as a building, which for the thing the fen
    # is named after is the wrong failure.
    base_r = h * 0.092
    # Square-shouldered for two thirds and then drawn to a point: a tower with a spire on
    # it, which is a different silhouette from a cone and the one a nave actually has.
    prof = [
        (base_r * 1.22, 0.0), (base_r * 1.12, h * 0.05), (base_r * 1.04, h * 0.14),
        (base_r * 1.00, h * 0.28), (base_r * 0.97, h * 0.44), (base_r * 0.95, h * 0.58),
        (base_r * 1.06, h * 0.62), (base_r * 0.99, h * 0.655),
        (base_r * 0.74, h * 0.72), (base_r * 0.52, h * 0.82), (base_r * 0.30, h * 0.91),
        (base_r * 0.12, h * 0.97), (0.0, h),
    ]
    spire = S.lathe("spire", prof, segments=flutes * 2, mat=stone, close=True)
    for v in spire.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        f = 1.0 + 0.045 * math.cos(a * flutes)
        v.co.x *= f
        v.co.y *= f
    S.shade_smooth(spire, 34.0)
    _weather(spire, rng, amount=base_r * 0.05, scale=h * 0.08, seed=rng.randrange(999))
    # Below the waterline the stone is black with weed. The line is the point of the thing.
    water_z = h * (1.0 - show)
    S.assign_material_to_faces(spire, drowned, lambda poly: poly.center.z < water_z)
    parts.append(spire)

    # The nave arcade: what is left of the church around the spire's foot, gable ends and
    # column tops breaking the water in two rows.
    bays = int(params.get("bays", 9))
    span = base_r * 1.9
    for row in (-1, 1):
        for i in range(bays):
            t = (i - (bays - 1) * 0.5) / max(1, bays - 1)
            x = t * h * 0.30
            drop = abs(t) * h * 0.06          # the far bays have sunk further
            col_h = h * 0.13 - drop + rng.uniform(-1.5, 1.5)
            if col_h < h * 0.02:
                continue
            col = S.cylinder("pier_%d_%d" % (row, i), radius=base_r * 0.17,
                             radius_top=base_r * 0.145, depth=col_h, vertices=10,
                             location=(x, row * span, water_z - h * 0.03), mat=stone)
            S.assign_material_to_faces(col, drowned, lambda poly: poly.center.z < water_z)
            parts.append(col)
            # a broken length of the arcade's head, where the arch has not yet fallen
            if rng.random() < 0.55:
                cap = S.box_centered("arcade_%d_%d" % (row, i),
                                     size=(base_r * rng.uniform(0.5, 1.0), base_r * 0.5,
                                           base_r * 0.34),
                                     location=(x, row * span, water_z - h * 0.03 + col_h),
                                     rotation=(rng.uniform(-8, 8), rng.uniform(-6, 6), 0),
                                     mat=stone)
                parts.append(cap)
    # The west gable, the one wall still standing to its full height.
    gable_verts = [(-h * 0.34, 0.0, water_z - h * 0.04), (-h * 0.34, 0.0, water_z + h * 0.16),
                   (-h * 0.30, 0.0, water_z + h * 0.24), (-h * 0.26, 0.0, water_z + h * 0.15),
                   (-h * 0.26, 0.0, water_z - h * 0.04)]
    gable = S.mesh_from_pydata("gable", [(x, -span * 1.05, z) for (x, _y, z) in gable_verts],
                               [(0, 1, 2, 3, 4)], smooth=False)
    gable.data.materials.append(stone)
    S.solidify(gable, thickness=span * 2.1, offset=1.0)
    S.bevel(gable, width=base_r * 0.05, segments=2, angle_deg=40)
    _weather(gable, rng, amount=base_r * 0.06, scale=h * 0.05, seed=rng.randrange(999))
    S.assign_material_to_faces(gable, drowned, lambda poly: poly.center.z < water_z)
    parts.append(gable)

    # Lean the whole ruin. Everything tilts together: it went down as one building.
    for o in parts:
        o.rotation_euler = Euler((lean, 0.0, 0.0), "XYZ")
        S.apply_transforms(o)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "tier": "hero",
            "materials_used": ["fused_stone", "drowned_stone"],
            "extra_meta": {"height_m": h, "lean_deg": params.get("lean_deg", 15.0),
                           "waterline_m": round(water_z, 2), "leads_to_deep_place": True,
                           "place": "core:place/drowned_nave"}}


# --- Eelfathom Pool (Sedgemire) ------------------------------------------------------------

def eelfathom(pal, rng, params, variant):
    """What the Reedfolk built at the pool that answers a few seconds late.

    WORLD_BIBLE Sedgemire: the pool itself is terrain; this is the mark on it. Reedfolk
    build in stilts, boardwalk and lantern pole, and they bury their dead off jetties, so
    what stands at a pool nobody trusts is a water-burial jetty: a walk out over the water
    that stops short, lantern poles down its length, and a ring of stones set in the shallows
    where the reflection is watched. Built around the origin so a placer can sit it on the
    pool's own edge.
    """
    reach = params.get("reach", 14.0)
    deck = M.wood_planks(pal, wear=0.7, age=0.8, scale=1.0, plank_len=1.6, plank_w=0.22,
                         name="eelfathom_deck")
    post = M.driftwood(pal, wear=0.75, age=0.85, scale=0.9, name="eelfathom_post")
    iron = M.iron(pal, age=0.85, wear=0.7, scale=0.3, name="eelfathom_iron")
    glass = M.glass(pal, name="eelfathom_glass")
    flame = M.ember(pal, heat=0.9, name="eelfathom_flame")
    stone = M.drowned_stone(pal, age=0.8, scale=1.4, name="eelfathom_stone")
    parts = []

    width = params.get("width", 2.1)
    # The walk. It stops short of the middle, because nobody goes further.
    boards = int(reach / 0.42)
    for i in range(boards):
        y = i * 0.42
        sag = (i / max(1, boards - 1)) ** 2 * 0.22
        b = S.box_centered("board_%d" % i, size=(width, 0.36, 0.06),
                           location=(rng.uniform(-0.03, 0.03), y, -sag),
                           rotation=(0, rng.uniform(-1.4, 1.4), 0), mat=deck)
        parts.append(b)
    for sx in (-1, 1):
        parts.append(S.box_centered("stringer_%d" % sx, size=(0.12, reach, 0.16),
                                    location=(sx * width * 0.42, reach * 0.5, -0.16), mat=deck))
    # Stilts, driven in pairs, deeper and more crooked the further out they go.
    pairs = max(3, int(reach / 3.2))
    for i in range(pairs):
        y = (i + 0.4) * (reach / pairs)
        f = i / max(1, pairs - 1)
        for sx in (-1, 1):
            p = S.cylinder("stilt_%d_%d" % (i, sx), radius=0.15, radius_top=0.12,
                           depth=1.4 + f * 1.6, vertices=8,
                           location=(sx * width * 0.42, y, -(1.4 + f * 1.6) - 0.16),
                           rotation=(rng.uniform(-4, 4), rng.uniform(-4, 4), 0), mat=post)
            parts.append(p)
    # Lantern poles down the length: the one thing visible across a fen at night.
    for i in range(int(params.get("lanterns", 4))):
        y = reach * (0.18 + 0.72 * i / max(1, int(params.get("lanterns", 4)) - 1))
        sx = 1 if i % 2 == 0 else -1
        ph = rng.uniform(2.6, 3.4)
        parts.append(S.cylinder("pole_%d" % i, radius=0.09, depth=ph, vertices=7,
                                location=(sx * width * 0.5, y, 0.0),
                                rotation=(rng.uniform(-3, 3), rng.uniform(-3, 3), 0), mat=post))
        top = Vector((sx * width * 0.5, y, ph))
        parts.append(S.torus("hook_%d" % i, major=0.16, minor=0.03, seg_major=12, seg_minor=6,
                             location=(top.x - sx * 0.13, top.y, top.z - 0.04),
                             rotation=(90, 0, 0), mat=iron))
        parts.append(S.cylinder("lantern_%d" % i, radius=0.17, depth=0.34, vertices=8,
                                location=(top.x - sx * 0.26, top.y, top.z - 0.42), mat=glass))
        parts.append(S.uv_sphere("flame_%d" % i, radius=0.08, segments=8, rings=5,
                                 location=(top.x - sx * 0.26, top.y, top.z - 0.26), mat=flame))
    # The watching ring: stones set in the shallows around the jetty's head, where the
    # reflection is looked at. Set, not scattered -- somebody placed these.
    ring_n = int(params.get("ring", 9))
    for i in range(ring_n):
        a = TAU * i / ring_n
        rr = reach * 0.46
        sh = rng.uniform(0.5, 1.1)
        st = S.cylinder("set_%d" % i, radius=rng.uniform(0.2, 0.34),
                        radius_top=rng.uniform(0.14, 0.26), depth=sh, vertices=7,
                        location=(math.cos(a) * rr, reach + math.sin(a) * rr * 0.7, -0.35),
                        rotation=(rng.uniform(-9, 9), rng.uniform(-9, 9), 0), mat=stone)
        S.jitter_verts(st, amount=0.05, scale=0.8, seed=rng.randrange(999))
        parts.append(st)
    # The end post, taller than the rest, where the dead are let go.
    parts.append(S.cylinder("endpost", radius=0.2, radius_top=0.16, depth=3.6, vertices=9,
                            location=(0.0, reach + 0.3, -0.2), mat=post))
    parts.append(S.torus("endring", major=0.3, minor=0.05, seg_major=16, seg_minor=6,
                         location=(0.0, reach + 0.3, 3.1), rotation=(90, 0, 0), mat=iron))

    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb",
            "materials_used": ["wood_planks", "driftwood", "iron", "glass", "ember",
                               "drowned_stone"],
            "extra_meta": {"walkable": ["board", "stringer"], "reach_m": reach,
                           "stands_in_water": True, "place": "core:place/eelfathom"}}


KINDS = {
    "cracked_toll": cracked_toll,
    "fallen_hand": fallen_hand,
    "choir_colossus": choir_colossus,
    "the_lamp": the_lamp,
    "sayers_spire": sayers_spire,
    "grandfather": grandfather,
    "chalk_hound": chalk_hound,
    "drowned_nave": drowned_nave,
    "eelfathom": eelfathom,
}


if __name__ == "__main__":
    run_generator("Wickmere landmark generator", KINDS, "landmarks", "gen_landmarks")
