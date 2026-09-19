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
    # Bell profile: flaring lip, waisted shoulder, domed crown. Modelled as a shell so the
    # inside is real geometry (you can stand under it).
    prof_outer = [
        (r * 1.00, 0.00), (r * 0.985, 0.045), (r * 0.90, 0.10), (r * 0.79, 0.19),
        (r * 0.72, 0.30), (r * 0.685, 0.43), (r * 0.66, 0.56), (r * 0.62, 0.68),
        (r * 0.545, 0.785), (r * 0.42, 0.875), (r * 0.25, 0.945), (r * 0.10, 0.985),
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

    # The hill it is buried in: a chalk mound swallowing a third of the bell, with the
    # white scar the fall cut (WORLD_BIBLE §6.1).
    if params.get("mound", True):
        ground = M.chalk_rock(pal, wear=0.5, age=0.6, scale=h * 0.06)
        mound = S.uv_sphere("mound", radius=r * 1.85, segments=40, rings=20, mat=ground,
                            scale=(1.0, 1.0, 0.34))
        S.apply_transforms(mound)
        mound.location = Vector((0, r * 0.55, -r * 0.22))
        S.apply_transforms(mound)
        cut = S.box_centered("mcut", size=(r * 8, r * 8, r * 4), location=(0, 0, -r * 2.0 - r * 0.22))
        S.boolean(mound, cut, "DIFFERENCE")
        _weather(mound, rng, amount=r * 0.05, scale=h * 0.3, seed=rng.randrange(999))
        S.shade_smooth(mound, 42.0)
        tris = S.tri_count(mound)
        if tris > 4000:
            S.decimate(mound, 4000.0 / tris)
            S.shade_smooth(mound, 42.0)
        parts.append(mound)

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
    stone = M.limestone(pal, wear=0.55, age=0.8, scale=length * 0.05)
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
    # Arms folded across the chest (the Choir holds a note; the hands are cupped).
    for sgn in (-1, 1):
        upper = S.cylinder("arm_u%d" % sgn, radius=hem_r * 0.13, radius_top=hem_r * 0.11,
                           depth=h * 0.16, vertices=14,
                           location=(sgn * hem_r * 0.50, 0, h * 0.90),
                           rotation=(0, sgn * 118, 0), mat=stone)
        parts.append(upper)
        fore = S.cylinder("arm_f%d" % sgn, radius=hem_r * 0.11, radius_top=hem_r * 0.09,
                          depth=h * 0.17, vertices=14,
                          location=(sgn * hem_r * 0.40, -hem_r * 0.30, h * 0.775),
                          rotation=(-74, 0, sgn * 26), mat=stone)
        parts.append(fore)
        hand = S.sphere("hand%d" % sgn, radius=hem_r * 0.11, subdivisions=3,
                        location=(sgn * hem_r * 0.14, -hem_r * 0.40, h * 0.755), mat=stone,
                        scale=(1.0, 1.25, 0.7))
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


KINDS = {
    "cracked_toll": cracked_toll,
    "fallen_hand": fallen_hand,
    "choir_colossus": choir_colossus,
    "the_lamp": the_lamp,
    "sayers_spire": sayers_spire,
}


if __name__ == "__main__":
    run_generator("Wickmere landmark generator", KINDS, "landmarks", "gen_landmarks")
