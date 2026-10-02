"""Weapons and shields, as they are held: swords, a rapier, greatswords, daggers, a knife, axes,
maces, spears, a staff, war hammers, bows, and the shields worn on the forearm.

    blender -b --python tools/forge/gen_weapons.py -- --kind sword --params finish=iron --name sword_iron

Every weapon is built where the hand holds it (CONTRACTS §2): the middle of the grip is the
origin, and the blade or the head runs up +Z, which the glTF export turns into the socket's +Y.
A blade's edges lie along ±Y and its flats face ±X, so a sword held out at rest shows its flat
to the side and its edges up and down, the way a hand holds one. Nothing is dropped to the
ground: `attaches_to` names the socket, and the asset is placed by the hand, not the floor.

A two-handed grip runs on down from the origin for the other hand. A bow is held in the left
hand with its stave along ±Y, the arrow's way +Z and the string behind the grip at -Z. A shield
hangs on the forearm (Socket.ShieldL), its face outward along +X.

`finish` is the metal (or bone) the item is made of, from its def's material: iron, bronze
(bell bronze), ashen (the Ash-knights' blackened iron) or bone, with a wooden or leather-bound
grip to match. The style is the props': real parts with modelled bevels and a little seeded
asymmetry, painted in the shared material library.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402
import numpy as np  # noqa: E402

from lib import build as B  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import scene as S  # noqa: E402
from lib.runner import run_generator  # noqa: E402
from gen_props import _leaf_blade, jit, tool_wood  # noqa: E402

TAU = math.tau
# Held things are not chunked in length (a sword's reach is a gameplay number, and a blade a
# tenth too long reads as a toy); the stylisation goes into their sections, a little stouter.
STOUT = 1.12
FINISHES = ("iron", "bronze", "ashen", "bone")


# --- materials -----------------------------------------------------------------------------

def _finish(params) -> str:
    f = str(params.get("finish", "iron"))
    if f not in FINISHES:
        raise ValueError("finish must be one of %s, not %r" % (FINISHES, f))
    return f


def blade_mat(pal, rng, finish):
    """The working metal: ground bright along the edges, darker in the flats."""
    if finish == "bronze":
        return M.bronze(pal, age=0.28, wear=0.85, scale=0.14, name="blade_bronze")
    if finish == "ashen":
        return M.blackened_iron(pal, age=0.35, wear=0.75, scale=0.14, name="blade_ashen")
    if finish == "bone":
        return M.bone(pal, age=0.35, wear=0.55, scale=0.10, name="blade_bone")
    return M.steel(pal, age=0.14 + 0.08 * rng.random(), wear=0.9, scale=0.16, name="blade_iron")


def fitting_mat(pal, rng, finish):
    """Guards, pommels, bands, bosses: the same metal, older."""
    if finish == "bronze":
        return M.bell_bronze_patina(pal, age=0.55, wear=0.7, scale=0.08, name="fitting_bronze")
    if finish == "ashen":
        return M.blackened_iron(pal, age=0.55, wear=0.6, scale=0.08, name="fitting_ashen")
    if finish == "bone":
        return M.bone(pal, age=0.5, wear=0.5, scale=0.08, name="fitting_bone")
    return M.iron(pal, age=0.45 + 0.1 * rng.random(), wear=0.75, scale=0.08, name="fitting_iron")


def grip_mat(pal, finish):
    hexes = {"iron": "#3b2616", "bronze": "#4a2415", "ashen": "#1d1815", "bone": "#5a4230"}
    return M.leather(pal, age=0.65, wear=0.55, scale=0.04, base_hex=hexes[finish], name="grip_%s" % finish)


def haft_mat(pal, rng, base_hex="#7a5c34", name="haft_wood"):
    # a haft is one cleft stave: a few long soft tones, no rings (gen_props.tool_wood)
    return tool_wood(pal, rng, scale=0.6, wear=0.28, age=0.5, base_hex=base_hex, relief=0.08,
                     grain=0.1, along="Z", name=name)


# --- parts ---------------------------------------------------------------------------------

def _solid(name, verts, faces, mat, smooth_angle=38.0):
    """A closed mesh from vertices and faces, its normals made to face out."""
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = S.bm_to_object(bm, name, mat, smooth=False)
    S.shade_smooth(ob, smooth_angle)
    return ob


def _straight_blade(name, length, w_base, w_mid, thick, mat, base_z=0.0, point=0.16, fuller=0.62,
                    single=False, rings=16):
    """A blade built ring by ring up +Z: edges on ±Y, flats on ±X, a fuller down the middle for
    `fuller` of its length, a distal taper, and a point over the last `point` of it. `single`
    gives a knife's section: one edge on +Y and a flat back on -Y.

    The section is the blade: a plate with a bevelled rim reads as cut from card (gen_props'
    `_leaf_blade` says the same of spear heads)."""
    verts, faces = [], []
    for i in range(rings + 1):
        t = i / rings
        z = base_z + t * length
        if t <= 1.0 - point:
            w = w_base + (w_mid - w_base) * t / (1.0 - point)
        else:
            u = (t - (1.0 - point)) / point
            w = w_mid * max(0.0, 1.0 - u ** 1.7) ** 0.75
        th = thick * (1.0 - 0.5 * t)
        if i == rings:
            verts.append((0.0, w_mid * 0.18 if single else 0.0, z))
            break
        dip = 0.28 if (fuller > 0.0 and t < fuller) else 1.0
        if single:
            ring = [(0.0, w * 0.5), (th * 0.28, w * 0.28), (th * 0.5, 0.0), (th * 0.5, -w * 0.5),
                    (0.0, -w * 0.52), (-th * 0.5, -w * 0.5), (-th * 0.5, 0.0), (-th * 0.28, w * 0.28)]
        else:
            ring = [(0.0, w * 0.5), (th * 0.5, w * 0.24), (th * 0.5 * dip, 0.0), (th * 0.5, -w * 0.24),
                    (0.0, -w * 0.5), (-th * 0.5, -w * 0.24), (-th * 0.5 * dip, 0.0), (-th * 0.5, w * 0.24)]
        verts += [(x, y, z) for (x, y) in ring]
    tip = len(verts) - 1
    for i in range(rings - 1):
        a, b = i * 8, (i + 1) * 8
        for k in range(8):
            faces.append((a + k, a + (k + 1) % 8, b + (k + 1) % 8, b + k))
    a = (rings - 1) * 8
    for k in range(8):
        faces.append((a + k, a + (k + 1) % 8, tip))
    faces.append(tuple(reversed(range(8))))
    return _solid(name, verts, faces, mat, 38.0)


def _grip(name, z0, z1, r, mat, rng, wrap=True):
    """A leather-bound grip from z0 to z1, swelling a little in the middle, with the thong wound
    round it in a spiral."""
    L = z1 - z0
    prof = [(r * 0.90, z0), (r * 1.0, z0 + L * 0.12), (r * 1.08, z0 + L * 0.5), (r * 1.0, z0 + L * 0.88),
            (r * 0.92, z1)]
    parts = [S.lathe(name, prof, segments=10, mat=mat, close=True)]
    if wrap:
        turns = max(4, int(L / 0.014))
        pts = []
        n = turns * 9
        phase = rng.uniform(0.0, TAU)
        for i in range(n + 1):
            f = i / n
            z = z0 + L * (0.06 + 0.88 * f)
            prof_r = r * (1.0 + 0.08 * math.sin(math.pi * (z - z0) / L))
            a = phase + TAU * turns * f
            pts.append((math.cos(a) * prof_r * 1.02, math.sin(a) * prof_r * 1.02, z))
        parts.append(S.tube_along(name + "_thong", pts, radius=r * 0.13, segments=5, mat=mat))
    return parts


def _guard(name, span, bar, z, mat, curl=0.012, block=None):
    """A cross-guard lying along Y at height z, its quillons curling a little toward the blade,
    with a block at its middle where the blade seats."""
    parts = []
    for side in (-1.0, 1.0):
        pts = [(0.0, 0.0, z), (0.0, side * span * 0.28, z + curl * 0.15), (0.0, side * span * 0.5, z + curl)]
        parts.append(S.tube_along("%s_%d" % (name, int(side)), pts, radius=bar, segments=8, radius_end=bar * 0.78,
                                  mat=mat))
        parts.append(S.sphere("%s_finial_%d" % (name, int(side)), radius=bar * 1.05, subdivisions=1,
                              location=(0.0, side * span * 0.5, z + curl), mat=mat))
    bw, bd, bh = block or (bar * 2.2, bar * 3.4, bar * 2.6)
    blk = S.box_centered(name + "_block", (bw, bd, bh), (0.0, 0.0, z + bh * 0.2), mat=mat)
    S.bevel(blk, width=bar * 0.35, segments=2, angle_deg=40)
    parts.append(blk)
    return parts


def _pommel(name, z, r, mat, style="wheel"):
    """A pommel under the grip: a wheel seen edge-on across the blade's flat, or a pear."""
    if style == "pear":
        prof = [(0.0, z - r * 1.3), (r * 0.7, z - r * 1.15), (r, z - r * 0.55), (r * 0.82, z - r * 0.05),
                (r * 0.42, z + r * 0.25), (r * 0.36, z + r * 0.45)]
        return S.lathe(name, prof, segments=12, mat=mat, close=True)
    prof = [(0.0, -r * 0.42), (r * 0.62, -r * 0.40), (r, -r * 0.18), (r, r * 0.18), (r * 0.62, r * 0.40),
            (0.0, r * 0.42)]
    ob = S.lathe(name, prof, segments=16, mat=mat, close=True)
    # a wheel pommel's faces look out to the flats (±X)
    ob.rotation_euler = Euler((0.0, math.radians(90.0), 0.0))
    ob.location = (0.0, 0.0, z)
    S.apply_transforms(ob)
    return ob


def _haft(name, z0, z1, r0, r1, mat, rng, bow=0.0):
    n = 8
    pts = [(math.sin(i / n * math.pi) * bow, 0.0, z0 + (z1 - z0) * i / n) for i in range(n + 1)]
    ob = S.tube_along(name, pts, radius=r0, segments=10, radius_end=r1, mat=mat)
    S.shade_smooth(ob, 45.0)
    return ob


def _band(name, z, r, h, mat):
    ob = S.lathe(name, [(r * 1.0, z - h * 0.5), (r * 1.06, z - h * 0.3), (r * 1.06, z + h * 0.3), (r * 1.0, z + h * 0.5)],
                 segments=12, mat=mat, close=True)
    return ob


def _prism(name, outline, thickness_at, mat):
    """A plate whose outline lies in the YZ plane, thick along X by `thickness_at(y, z)`: an axe
    head, a hammer's flange. Front and back faces follow the outline; the rim joins them."""
    n = len(outline)
    verts = []
    for (y, z) in outline:
        verts.append((thickness_at(y, z) * 0.5, y, z))
    for (y, z) in outline:
        verts.append((-thickness_at(y, z) * 0.5, y, z))
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j, j))
    return _solid(name, verts, faces, mat, 40.0)


def _spear_head(name, z, length, width, thick, mat):
    """gen_props' leaf blade, turned so its edges lie along ±Y like every other blade here."""
    ob = _leaf_blade(name, length, width, thick, mat, base_z=z, rib=1.0)
    ob.rotation_euler = Euler((0.0, 0.0, math.radians(90.0)))
    S.apply_transforms(ob)
    return ob


def done(parts, rng, socket, materials, jitter=0.0, extra=None):
    if jitter:
        for p in parts:
            S.jitter_verts(p, amount=jitter, scale=0.5, seed=rng.randrange(999))
    meta = {"attaches_to": socket, "grip_origin": True}
    meta.update(extra or {})
    return {"opaque_objs": parts, "collision": "none", "materials_used": list(materials),
            "extra_meta": meta, "ground": False}


# --- swords ---------------------------------------------------------------------------------

def sword(pal, rng, params, variant):
    """An arming sword: a straight double-edged blade about three-quarters of a metre, a
    cross-guard, a leather grip for one hand and a wheel pommel."""
    finish = _finish(params)
    blade_l = jit(rng, params.get("blade", 0.74), 0.03)
    grip_l = jit(rng, params.get("grip", 0.12), 0.04)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    hide = grip_mat(pal, finish)
    g0, g1 = -grip_l * 0.5, grip_l * 0.5
    parts = _grip("grip", g0, g1, 0.0145 * STOUT, hide, rng)
    parts += _guard("guard", jit(rng, 0.19, 0.06), 0.0085 * STOUT, g1 + 0.006, metal, curl=0.014)
    parts.append(_pommel("pommel", g0 - 0.018, 0.027 * STOUT, metal, "wheel"))
    parts.append(_straight_blade("blade", blade_l, 0.052 * STOUT, 0.040 * STOUT, 0.0085 * STOUT, steel,
                                 base_z=g1 + 0.012, point=0.14, fuller=0.66))
    return done(parts, rng, "Socket.WeaponR", ["iron", "leather"], jitter=0.0004)


def rapier(pal, rng, params, variant):
    """A Tollmere rapier: a long narrow blade, a swept knuckle guard and a pear pommel."""
    finish = _finish(params)
    blade_l = jit(rng, params.get("blade", 0.92), 0.02)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    hide = grip_mat(pal, finish)
    g0, g1 = -0.055, 0.055
    parts = _grip("grip", g0, g1, 0.0125 * STOUT, hide, rng)
    parts += _guard("guard", 0.17, 0.0065 * STOUT, g1 + 0.004, metal, curl=-0.01)
    # the knuckle bow: from the guard's front quillon round the fingers to the pommel
    bow = [(0.0, -0.085, g1 + 0.004), (0.0, -0.07, g1 - 0.035), (0.0, -0.062, (g0 + g1) * 0.5),
           (0.0, -0.05, g0 - 0.004), (0.0, -0.022, g0 - 0.018)]
    parts.append(S.tube_along("knuckle_bow", bow, radius=0.0055 * STOUT, segments=7, mat=metal))
    # two rings over the ricasso, one each side of the blade
    for s in (-1.0, 1.0):
        parts.append(B.rope_loop("ring_%d" % int(s), 0.022, 0.0042, mat=metal, segments=16,
                                 location=(0.0, 0.0, 0.0)))
        ring = parts[-1]
        ring.rotation_euler = Euler((0.0, math.radians(90.0), 0.0))
        ring.location = (s * 0.014, 0.0, g1 + 0.03)
        S.apply_transforms(ring)
    parts.append(_pommel("pommel", g0 - 0.02, 0.018 * STOUT, metal, "pear"))
    parts.append(_straight_blade("blade", blade_l, 0.026 * STOUT, 0.018 * STOUT, 0.0075 * STOUT, steel,
                                 base_z=g1 + 0.01, point=0.08, fuller=0.3))
    return done(parts, rng, "Socket.WeaponR", ["iron", "leather"], jitter=0.0003)


def greatsword(pal, rng, params, variant):
    """A two-handed sword: a blade of a metre and more, a long grip with room for both hands
    running down from the origin, a broad straight guard and a heavy pommel."""
    finish = _finish(params)
    blade_l = jit(rng, params.get("blade", 1.12), 0.03)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    hide = grip_mat(pal, finish)
    g0, g1 = -0.24, 0.06
    parts = _grip("grip", g0, g1, 0.016 * STOUT, hide, rng)
    parts += _guard("guard", jit(rng, 0.30, 0.05), 0.011 * STOUT, g1 + 0.008, metal, curl=0.006)
    parts.append(_pommel("pommel", g0 - 0.025, 0.034 * STOUT, metal, "wheel" if finish != "bone" else "pear"))
    parts.append(_straight_blade("blade", blade_l, 0.064 * STOUT, 0.050 * STOUT, 0.010 * STOUT, steel,
                                 base_z=g1 + 0.016, point=0.12, fuller=0.55))
    if finish == "bone":
        # a kingbone blade is ground from one long bone: knuckled where the joint was
        parts.append(S.sphere("knuckle", radius=0.036, subdivisions=2, location=(0.0, 0.0, g1 + 0.05), mat=steel,
                              scale=(0.5, 1.2, 0.8)))
    return done(parts, rng, "Socket.WeaponR", ["iron", "leather"], jitter=0.0005, extra={"two_handed": True})


def dagger(pal, rng, params, variant):
    """A dagger: a short tapering double-edged blade, a small guard and a round pommel."""
    finish = _finish(params)
    blade_l = jit(rng, params.get("blade", 0.25), 0.07)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    hide = grip_mat(pal, finish)
    g0, g1 = -0.048, 0.048
    parts = _grip("grip", g0, g1, 0.0135 * STOUT, hide, rng)
    parts += _guard("guard", jit(rng, 0.085, 0.12), 0.0068 * STOUT, g1 + 0.004, metal, curl=0.006)
    parts.append(_pommel("pommel", g0 - 0.012, 0.018 * STOUT, metal, "pear"))
    parts.append(_straight_blade("blade", blade_l, 0.038 * STOUT, 0.024 * STOUT, 0.0078 * STOUT, steel,
                                 base_z=g1 + 0.01, point=0.3, fuller=0.45, rings=12))
    return done(parts, rng, "Socket.WeaponR", ["iron", "leather"], jitter=0.0003)


def knife(pal, rng, params, variant):
    """A hunting knife: a single-edged blade with a dropped point, no guard to speak of, and a
    wooden handle riveted through the tang."""
    finish = _finish(params)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng, base_hex="#6a4a2c", name="handle_wood")
    g0, g1 = -0.052, 0.05
    handle = S.lathe("handle", [(0.013, g0), (0.0155, g0 + 0.02), (0.0165, g0 + 0.055), (0.0142, g1)],
                     segments=10, mat=wood, close=True)
    handle.scale = (0.78, 1.0, 1.0)
    S.apply_transforms(handle)
    parts = [handle]
    for k, z in enumerate((g0 + 0.025, g1 - 0.022)):
        parts.append(S.cylinder("rivet_%d" % k, radius=0.0032, depth=0.026, vertices=8, location=(0.0, 0.0, z),
                                rotation=(0, 90, 0), mat=metal, centered=True))
    parts.append(_band("bolster", g1 + 0.004, 0.0142, 0.012, metal))
    parts.append(_straight_blade("blade", jit(rng, 0.18, 0.04), 0.030 * STOUT, 0.028 * STOUT, 0.0072 * STOUT, steel,
                                 base_z=g1 + 0.009, point=0.34, fuller=0.0, single=True, rings=12))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks"], jitter=0.0003)


# --- hafted ---------------------------------------------------------------------------------

def axe(pal, rng, params, variant):
    """A bearded war axe on an ash haft: the grip at the origin, the haft running up to a head
    whose bit faces +Y, and a hand's breadth of haft below the hand ending in a swell."""
    finish = _finish(params)
    long_haft = bool(params.get("long", False))
    top = jit(rng, 0.62 if long_haft else 0.46, 0.03)
    butt = -0.16 if long_haft else -0.10
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng)
    hide = grip_mat(pal, finish)
    r = 0.0145 * STOUT
    parts = [_haft("haft", butt, top + 0.02, r * 1.08, r * 0.92, wood, rng, bow=rng.uniform(-0.004, 0.004))]
    parts.append(S.lathe("butt_swell", [(r * 1.05, butt - 0.004), (r * 1.35, butt + 0.012), (r * 1.1, butt + 0.035)],
                         segments=10, mat=wood, close=True))
    parts += _grip("grip", -0.06, 0.07, r * 1.04, hide, rng)
    # the head: eye round the haft, a bearded bit out along +Y
    eye = r * 1.25
    bit = jit(rng, 0.13 if long_haft else 0.105, 0.05)
    h_eye = 0.075
    drop = 0.045 if not long_haft else 0.06
    outline = [(-eye * 1.35, top), (eye * 1.05, top), (bit * 0.55, top + 0.006), (bit, top + 0.028),
               (bit * 1.04, top - h_eye * 0.35), (bit * 0.98, top - h_eye - drop * 0.4),
               (bit * 0.8, top - h_eye - drop), (bit * 0.46, top - h_eye - drop * 0.35),
               (eye * 1.05, top - h_eye), (-eye * 1.35, top - h_eye)]

    def th(y, z):
        if y <= eye * 1.05:
            return r * 2.6
        f = min(1.0, max(0.0, (y - eye * 1.05) / max(1e-6, bit - eye * 1.05)))
        return max(0.003, r * 2.6 * (1.0 - f) ** 1.3)

    head = _prism("head", outline, th, steel)
    S.bevel(head, width=0.0025, segments=2, angle_deg=35)
    parts.append(head)
    parts.append(_band("eye_collar", top - h_eye * 0.5, r * 1.9, h_eye * 0.95, metal))
    parts.append(S.box_centered("wedge", (r * 0.5, r * 1.6, 0.008), (0.0, 0.0, top + 0.004), mat=metal))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0004)


def mace(pal, rng, params, variant):
    """A flanged mace: an iron-bound haft and a head of six flanges round a core."""
    finish = _finish(params)
    top = jit(rng, 0.42, 0.03)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng)
    hide = grip_mat(pal, finish)
    r = 0.014 * STOUT
    parts = [_haft("haft", -0.1, top, r, r * 0.95, wood, rng)]
    parts += _grip("grip", -0.065, 0.065, r * 1.05, hide, rng)
    parts.append(_pommel("pommel", -0.112, 0.02 * STOUT, metal, "pear"))
    for k, z in enumerate((0.12, 0.22)):
        parts.append(_band("band_%d" % k, z, r, 0.012, metal))
    core_h = 0.13
    z0 = top - core_h * 0.2
    parts.append(S.lathe("core", [(r * 1.2, z0 - 0.02), (r * 1.55, z0), (r * 1.6, z0 + core_h * 0.7),
                                  (r * 1.1, z0 + core_h), (0.0, z0 + core_h + 0.012)], segments=12, mat=steel,
                         close=True))
    flanges = int(params.get("flanges", 6))
    for i in range(flanges):
        a = TAU * i / flanges
        outline = [(r * 1.2, z0), (0.052, z0 + 0.02), (0.058, z0 + core_h * 0.55), (0.04, z0 + core_h * 0.92),
                   (r * 1.1, z0 + core_h)]
        fl = _prism("flange_%d" % i, outline, lambda y, z: 0.0075 if y < 0.04 else 0.004, steel)
        fl.rotation_euler = Euler((0.0, 0.0, a))
        S.apply_transforms(fl)
        S.bevel(fl, width=0.0015, segments=1, angle_deg=35)
        parts.append(fl)
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0004)


def spear(pal, rng, params, variant):
    """A spear held for the thrust: the hand a third of the way down a shaft two metres and
    more long, a leaf head at the top and a ferrule at the butt."""
    finish = _finish(params)
    length = jit(rng, params.get("length", 2.2), 0.02)
    hold = length * 0.4                     # from the butt to the hand
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng)
    r = 0.0145 * STOUT
    butt, top = -hold, length - hold
    head_l = float(params.get("head", 0.26))
    parts = [_haft("shaft", butt, top - head_l * 0.2, r * 1.02, r * 0.9, wood, rng,
                   bow=rng.uniform(-0.006, 0.006))]
    parts.append(S.lathe("socket", [(r * 1.18, top - head_l * 0.42), (r * 1.22, top - head_l * 0.3),
                                    (r * 1.02, top - head_l * 0.12), (r * 0.8, top - head_l * 0.02)],
                         segments=10, mat=metal, close=True))
    parts.append(_spear_head("head", top - head_l * 0.08, head_l, 0.062 * STOUT, r * 1.1, steel))
    parts.append(S.lathe("ferrule", [(r * 1.1, butt - 0.012), (r * 1.18, butt + 0.01), (r * 1.02, butt + 0.05)],
                         segments=10, mat=metal, close=True))
    cord = M.rope(pal, age=0.55, scale=0.05)
    for k in range(6):
        parts.append(B.rope_loop("whip_%d" % k, r * 1.02, r * 0.26, mat=cord,
                                 segments=10, location=(0.0, 0.0, -0.05 + k * r * 0.62)))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "rope"], jitter=0.0005,
                extra={"two_handed": True})


def staff(pal, rng, params, variant):
    """A walking and fighting staff of ash, the hand at the middle, knotted and a little bent,
    its head wound with cord and capped."""
    length = jit(rng, params.get("length", 1.75), 0.03)
    finish = _finish(params)
    wood = haft_mat(pal, rng, base_hex="#6d5230", name="staff_wood")
    metal = fitting_mat(pal, rng, finish)
    r = 0.0165 * STOUT
    butt, top = -length * 0.45, length * 0.55
    n = 10
    bend = rng.uniform(0.01, 0.02)
    pts = [(math.sin(i / n * math.pi * 1.3) * bend, math.sin(i / n * 2.1) * bend * 0.5, butt + (top - butt) * i / n)
           for i in range(n + 1)]
    shaft = S.tube_along("staff", pts, radius=r * 0.95, segments=10, radius_end=r * 1.15, mat=wood)
    S.jitter_verts(shaft, amount=0.0012, scale=0.2, seed=rng.randrange(999))
    parts = [shaft]
    for k in range(3):
        z = butt + (top - butt) * rng.uniform(0.2, 0.8)
        parts.append(S.sphere("knot_%d" % k, radius=r * 0.55, subdivisions=1,
                              location=(pts[5][0] + r * 0.8, 0.0, z), mat=wood, scale=(0.6, 1.0, 1.4)))
    parts.append(S.lathe("cap", [(r * 1.15, top - 0.03), (r * 1.3, top - 0.01), (r * 0.9, top + 0.025), (0.0, top + 0.03)],
                         segments=10, mat=metal, close=True))
    parts.append(S.lathe("shoe", [(r * 0.95, butt - 0.015), (r * 1.05, butt + 0.02)], segments=10, mat=metal, close=True))
    cord = M.rope(pal, age=0.5, scale=0.05)
    for k in range(5):
        parts.append(B.rope_loop("wind_%d" % k, r * 1.18, r * 0.2, mat=cord, segments=10,
                                 location=(pts[-2][0], pts[-2][1], top - 0.07 - k * r * 0.5)))
    return done(parts, rng, "Socket.WeaponR", ["wood_planks", "iron", "rope"], jitter=0.0)


def warhammer(pal, rng, params, variant):
    """A two-handed bell-metal war hammer: a long haft bound in bands, and a head with a broad
    face on +Y and a beak behind it."""
    finish = _finish(params)
    top = jit(rng, 0.78, 0.03)
    butt = -0.3
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng, base_hex="#6e5232")
    hide = grip_mat(pal, finish)
    r = 0.017 * STOUT
    parts = [_haft("haft", butt, top + 0.03, r * 1.05, r * 0.95, wood, rng)]
    parts += _grip("grip", -0.26, 0.07, r * 1.03, hide, rng)
    for k, z in enumerate((0.2, 0.42, 0.62)):
        parts.append(_band("band_%d" % k, z, r, 0.018, metal))
    hz = top - 0.02
    block = S.box_centered("head_block", (0.075, 0.1, 0.085), (0.0, 0.02, hz), mat=steel)
    S.bevel(block, width=0.008, segments=2, angle_deg=40)
    parts.append(block)
    face = S.cylinder("face", radius=0.048, depth=0.05, vertices=14, location=(0.0, 0.085, hz), rotation=(90, 0, 0),
                      mat=steel, centered=True)
    S.bevel(face, width=0.006, segments=2, angle_deg=40)
    parts.append(face)
    beak = _prism("beak", [(-0.03, hz + 0.035), (-0.03, hz - 0.035), (-0.1, hz - 0.012), (-0.15, hz - 0.03),
                           (-0.1, hz + 0.01)], lambda y, z: 0.03 if y > -0.06 else 0.014, steel)
    S.bevel(beak, width=0.003, segments=1, angle_deg=35)
    parts.append(beak)
    parts.append(S.lathe("finial", [(r * 1.1, top + 0.02), (r * 1.3, top + 0.05), (0.0, top + 0.07)], segments=10,
                         mat=metal, close=True))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0005,
                extra={"two_handed": True})


def clapper(pal, rng, params, variant):
    """The bearers' clapper: a bell's clapper taken down and hafted, a long shaft and a heavy
    pear of bell metal at its end."""
    finish = _finish(params)
    top = jit(rng, 0.74, 0.03)
    butt = -0.3
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng, base_hex="#5e452a")
    hide = grip_mat(pal, finish)
    r = 0.016 * STOUT
    parts = [_haft("haft", butt, top, r * 1.05, r * 0.9, wood, rng)]
    parts += _grip("grip", -0.26, 0.07, r * 1.03, hide, rng)
    parts.append(S.lathe("stem", [(r * 0.9, top - 0.05), (r * 0.8, top + 0.05), (r * 1.1, top + 0.08)], segments=10,
                         mat=metal, close=True))
    parts.append(S.lathe("ball", [(r * 1.1, top + 0.08), (0.05, top + 0.13), (0.072, top + 0.2), (0.066, top + 0.26),
                                  (0.036, top + 0.3), (0.0, top + 0.31)], segments=16, mat=steel, close=True))
    parts.append(B.hoop("eye_ring", 0.02, 0.006, mat=metal, location=(0.0, 0.0, top + 0.04), segments=12, flatten=1.0))
    return done(parts, rng, "Socket.WeaponR", ["bronze", "wood_planks", "leather"], jitter=0.0004,
                extra={"two_handed": True})


# --- bows -----------------------------------------------------------------------------------

def bow(pal, rng, params, variant):
    """A braced bow in the left hand: the stave along ±Y through a bound grip at the origin, the
    limbs sweeping back toward the archer (-Z) and the string between the nocks."""
    finish = _finish(params)
    half = jit(rng, params.get("half", 0.72), 0.03)
    brace = 0.16
    wood = haft_mat(pal, rng, base_hex="#8a6a3a", name="stave_wood") if finish != "bone" else \
        M.bone(pal, age=0.4, wear=0.5, scale=0.08, name="stave_bone")
    hide = grip_mat(pal, "iron")
    string_mat = M.rope(pal, age=0.3, scale=0.02, name="bowstring")
    n = 12
    parts = []
    for side in (-1.0, 1.0):
        pts = []
        for i in range(n + 1):
            f = i / n
            y = side * half * f
            z = -brace * (f ** 1.8) * 0.9
            pts.append((0.0, y, z))
        limb = S.tube_along("limb_%d" % int(side), pts, radius=0.017, segments=8, radius_end=0.007, mat=wood)
        limb.scale = (0.7, 1.0, 1.0)
        S.apply_transforms(limb)
        parts.append(limb)
        parts.append(S.lathe("nock_%d" % int(side), [(0.008, 0.0), (0.011, 0.012), (0.0, 0.03)], segments=8,
                             mat=hide if finish != "bone" else wood))
        nock = parts[-1]
        nock.rotation_euler = Euler((math.radians(-90.0 * side), 0.0, 0.0))
        nock.location = (0.0, side * half, -brace * 0.9)
        S.apply_transforms(nock)
    grip = S.lathe("grip", [(0.017, -0.06), (0.021, -0.045), (0.021, 0.045), (0.017, 0.06)], segments=10, mat=hide,
                   close=True)
    grip.rotation_euler = Euler((math.radians(90.0), 0.0, 0.0))
    S.apply_transforms(grip)
    grip.scale = (0.8, 1.0, 1.0)
    S.apply_transforms(grip)
    parts.append(grip)
    parts.append(S.tube_along("string", [(0.0, -half * 0.985, -brace * 0.9), (0.0, half * 0.985, -brace * 0.9)],
                              radius=0.0016, segments=5, mat=string_mat))
    return done(parts, rng, "Socket.WeaponL", ["wood_planks", "leather", "rope"], jitter=0.0)


def quiver(pal, rng, params, variant):
    """A hip quiver of stiff leather with a handful of arrows in it (triage 55): the tube hangs
    down -Z from its mouth at the origin, the arrows' nocks and fletching stand up out of it, and
    the draw hand takes one by its nock (anim_clips.BOW_QUIVER). HeldItems hangs it at the right
    hip of a body holding a bow."""
    depth = jit(rng, params.get("depth", 0.50), 0.02)
    r = 0.046
    hide = M.leather(pal, age=0.55, wear=0.5, scale=0.06, base_hex="#5b3a22", name="quiver_leather")
    band = M.leather(pal, age=0.7, wear=0.6, scale=0.04, base_hex="#2f1f14", name="quiver_band")
    wood = haft_mat(pal, rng, base_hex="#a07a48", name="shaft_wood")
    feather = M.dyed_cloth(pal, color=M.P.lin("#d8d0bc"), age=0.3, wear=0.2, scale=0.02, name="fletching")
    parts = [S.lathe("tube", [(r * 0.86, -depth), (r * 0.95, -depth + 0.02), (r, -depth * 0.5), (r * 1.06, -0.02),
                              (r * 1.1, 0.0), (r * 0.98, 0.004)], segments=12, mat=hide, close=False)]
    parts.append(S.lathe("base", [(0.0, -depth - 0.012), (r * 0.9, -depth - 0.01), (r * 0.92, -depth + 0.012)],
                         segments=12, mat=band, close=True))
    for k, z in enumerate((-0.05, -depth + 0.07)):
        parts.append(B.rope_loop("band_%d" % k, r * 1.08, 0.006, mat=band, segments=12, location=(0.0, 0.0, z)))
    n = 7
    for i in range(n):
        a = TAU * i / n + rng.uniform(-0.2, 0.2)
        rr = r * (0.35 if i else 0.0) + rng.uniform(0.0, 0.012)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        top = rng.uniform(0.10, 0.13)
        lean = (x * 0.5, y * 0.5)
        parts.append(S.tube_along("shaft_%d" % i, [(x, y, -0.25), (x + lean[0], y + lean[1], top)], radius=0.0045,
                                  segments=5, mat=wood))
        for j in range(3):
            fa = TAU * j / 3 + rng.uniform(0.0, 1.0)
            vane = S.box_centered("vane_%d_%d" % (i, j), size=(0.0012, 0.013, 0.075),
                                  location=(x + lean[0] + math.cos(fa) * 0.008, y + lean[1] + math.sin(fa) * 0.008, top - 0.045),
                                  mat=feather)
            vane.rotation_euler = Euler((0.0, 0.0, fa))
            S.apply_transforms(vane)
            parts.append(vane)
    return done(parts, rng, "Hips", ["leather", "wood_planks", "cloth"], jitter=0.0)


def scythe(pal, rng, params, variant):
    """A war-scythe, the hedge wight's: a long ash snath held a third of the way up, and at its top
    a long thin blade set out along +Y like an axe's bit (so it leads its sweep as the other
    blades here do), curving down toward its point, its edge on the underside."""
    finish = _finish(params)
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng, base_hex="#6b5436", name="snath_wood")
    hide = grip_mat(pal, finish)
    r = 0.0145 * STOUT
    butt, top = -0.5, jit(rng, 1.22, 0.02)
    parts = [_haft("snath", butt, top + 0.03, r * 1.05, r * 0.9, wood, rng, bow=rng.uniform(0.01, 0.02))]
    parts += _grip("grip", -0.07, 0.08, r * 1.04, hide, rng)
    # the nib: a short handle out of the snath for the other hand
    parts.append(S.tube_along("nib", [(0.0, 0.0, 0.46), (0.0, -0.11, 0.49), (0.0, -0.13, 0.5)],
                              radius=r * 0.75, segments=8, radius_end=r * 0.7, mat=wood))
    length = jit(rng, 0.64, 0.03)
    n = 9
    spine, edge = [], []
    for i in range(n + 1):
        f = i / n
        y = length * f
        droop = 0.13 * f ** 1.8
        spine.append((y, top + 0.018 - droop))
        edge.append((y, top - 0.075 * (1.0 - f) ** 0.7 - droop))
    outline = [(-r * 1.4, top + 0.018), (-r * 1.4, top - 0.075)] + edge[:-1] + list(reversed(spine))

    def th(y, z):
        return max(0.0025, 0.009 * (1.0 - min(1.0, y / length)) + 0.003)

    blade = _prism("blade", outline, th, steel)
    S.bevel(blade, width=0.0015, segments=1, angle_deg=35)
    parts.append(blade)
    parts.append(_band("tang_ring", top - 0.03, r * 1.35, 0.05, metal))
    parts.append(S.lathe("ferrule", [(r * 1.0, butt - 0.01), (r * 1.1, butt + 0.01), (r * 1.0, butt + 0.04)],
                         segments=10, mat=metal, close=True))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0004,
                extra={"two_handed": True})


def crossbow(pal, rng, params, variant):
    """A crossbow in the left hand, held by the fore-stock at the origin as a bow is held by its
    grip. The stock runs back along -Z to the butt, where the right hand and the cheek meet it at
    the aim. The steel prod crosses the stock at the nose, along X, its tips swept back by the
    spanned string, and the string is caught on the nut. Up in the hand is -Y (the socket's +Z), so
    the bolt's rail is on the -Y side and the trigger lever and the stirrup are on the +Y side."""
    finish = _finish(params)
    wood = haft_mat(pal, rng, base_hex="#6f5130", name="stock_wood")
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    hide = grip_mat(pal, finish)
    cord = M.rope(pal, age=0.45, scale=0.03, name="crossbow_lashing")
    string_mat = M.rope(pal, age=0.3, scale=0.02, name="crossbow_string")
    nose = jit(rng, 0.17, 0.015)
    butt = -jit(rng, 0.60, 0.02)
    span = jit(rng, 0.30, 0.02)
    sweep = jit(rng, 0.075, 0.01)
    top = -0.026                      # the stock's upper face, where the bolt lies
    prod_z = nose - 0.035
    nut_z = -0.11
    parts = []
    # the stock: a beam that thickens toward the butt and drops below the bolt's line there
    stock = S.tube_along("stock", [(0.0, 0.0, nose), (0.0, 0.002, 0.0), (0.0, 0.012, -0.24),
                                   (0.0, 0.032, -0.42), (0.0, 0.052, butt)],
                         radius=0.022, segments=8, radius_end=0.036, mat=wood)
    stock.scale = (0.72, 1.0, 1.0)
    S.apply_transforms(stock)
    S.jitter_verts(stock, amount=0.0008, scale=0.2, seed=rng.randrange(999))
    parts.append(stock)
    # the rail the bolt lies in, from the nut to the nose
    parts.append(S.box_centered("rail", size=(0.014, 0.006, nose - nut_z + 0.02),
                                location=(0.0, top + 0.002, (nose + nut_z) * 0.5), mat=wood))
    # the prod: two tapering steel arms from the middle, their tips swept back toward the string
    n = 8
    for side in (-1.0, 1.0):
        pts = []
        for i in range(n + 1):
            f = i / n
            pts.append((side * span * f, top - 0.004, prod_z - sweep * (f ** 2)))
        arm = S.tube_along("prod_%d" % int(side), pts, radius=0.011, segments=8, radius_end=0.0055, mat=steel)
        arm.scale = (1.0, 1.25, 0.6)
        S.apply_transforms(arm)
        parts.append(arm)
    # the lashing that holds the prod to the stock
    for k in range(3):
        parts.append(B.rope_loop("lash_%d" % k, 0.024, 0.0035, mat=cord, segments=10,
                                 location=(0.0, 0.0, prod_z - 0.012 + k * 0.012)))
    # the string, spanned from each tip to the nut
    for side in (-1.0, 1.0):
        parts.append(S.tube_along("string_%d" % int(side),
                                  [(side * span * 0.99, top - 0.004, prod_z - sweep * 0.98), (0.0, top - 0.006, nut_z)],
                                  radius=0.0017, segments=5, mat=string_mat))
    # the nut the string is caught on, across the stock
    nut = S.cylinder("nut", radius=0.009, depth=0.03, vertices=10, location=(0.0, top - 0.004, nut_z),
                     rotation=(0.0, 90.0, 0.0), mat=metal, centered=True)
    S.apply_transforms(nut)
    parts.append(nut)
    # the trigger lever under the stock, reaching back toward the right hand
    parts.append(S.tube_along("lever", [(0.0, 0.018, nut_z), (0.0, 0.045, nut_z - 0.07), (0.0, 0.07, nut_z - 0.25)],
                              radius=0.0045, segments=6, radius_end=0.0035, mat=metal))
    # the stirrup at the nose, for a foot when it is spanned
    stirrup = S.torus("stirrup", major=0.045, minor=0.0055, seg_major=16, seg_minor=6,
                      location=(0.0, 0.012, nose + 0.035), rotation=(0.0, 90.0, 0.0), mat=metal)
    stirrup.scale = (1.0, 1.0, 0.8)
    S.apply_transforms(stirrup)
    parts.append(stirrup)
    # a band at the nose, and the leather where the left hand holds it
    parts.append(S.lathe("band", [(0.024, nose - 0.012), (0.026, nose - 0.006), (0.026, nose + 0.002), (0.024, nose + 0.006)],
                         segments=10, mat=metal, close=True))
    parts.append(S.lathe("grip", [(0.021, -0.055), (0.025, -0.045), (0.025, 0.045), (0.021, 0.055)],
                         segments=10, mat=hide, close=True))
    return done(parts, rng, "Socket.WeaponL", ["wood_planks", "iron", "leather", "rope"], jitter=0.0)


# --- shields --------------------------------------------------------------------------------

def shield(pal, rng, params, variant):
    """A round shield worn on the left forearm: boards under a hide rim, an iron boss and two
    straps, its face outward along +X. `finish` iron gives the Warden's round shield, `wood` an
    oak one with a wooden boss, `bone` the clans' shield faced with bone plates."""
    finish = str(params.get("finish", "iron"))
    r = jit(rng, params.get("radius", 0.33), 0.03)
    offset = float(params.get("offset", 0.06))
    if finish == "bone":
        board = M.bone(pal, age=0.5, wear=0.45, scale=0.12, name="shield_bone")
        metal = M.bone(pal, age=0.7, wear=0.4, scale=0.06, name="boss_bone")
    else:
        board = tool_wood(pal, rng, scale=0.3, wear=0.3, age=0.6, base_hex="#7d6138" if finish != "wood" else "#6b4f2c",
                          relief=0.16, grain=0.08, plank_len=2.6, plank_w=0.5, along="XZ", name="shield_board")
        metal = fitting_mat(pal, rng, "iron") if finish != "wood" else board
    hide = M.leather(pal, age=0.75, wear=0.4, scale=0.08, base_hex="#4a3320", name="shield_hide")
    face_z = r * 0.07
    front = [(0.0, 1.0), (0.4, 0.86), (0.74, 0.54), (0.95, 0.1), (1.0, -0.16)]
    prof = [(r * a, face_z * z) for (a, z) in front]
    prof += [(r * 0.985, -face_z * 0.52), (r * 0.72, -face_z * 0.26), (r * 0.38, -face_z * 0.05), (0.0, face_z * 0.05)]
    disc = S.lathe("board", prof, segments=28, mat=board, close=False)
    S.jitter_verts(disc, amount=r * 0.006, scale=0.12, seed=rng.randrange(999))
    parts = [disc]
    parts.append(B.hoop("rim", r * 0.995, r * 0.03, mat=hide, location=(0, 0, -face_z * 0.05), segments=28,
                        flatten=1.45))
    bo = r * 0.23
    parts.append(S.lathe("boss", [(bo * 1.42, face_z * 0.9), (bo * 1.36, face_z * 1.1), (bo, face_z * 1.3),
                                  (bo * 0.86, face_z * 1.8), (bo * 0.44, face_z * 2.1), (0.0, face_z * 2.2)],
                         segments=20, mat=metal, close=True))
    if finish in ("iron", "bone"):
        for i, a in enumerate((0.42, 2.51)):
            strap = S.box_centered("strap_%d" % i, (r * 1.8, r * 0.11, r * 0.02), (0.0, 0.0, face_z * 0.95), mat=metal)
            strap.rotation_euler = Euler((0.0, 0.0, a))
            S.apply_transforms(strap)
            S.bevel(strap, width=r * 0.006, segments=1)
            parts.append(strap)
    # the grip behind the boss, and the forearm strap the socket sits in
    parts.append(B.board("grip", r * 0.5, r * 0.09, r * 0.035, mat=board, location=(0, 0, -face_z * 0.4),
                         rotation=(0, 0, 90)))
    parts.append(B.board("arm_strap", r * 0.9, r * 0.12, r * 0.012, mat=hide, location=(0, 0, -face_z * 0.55)))
    # the disc was lathed facing +Z: turn it to face outward (+X), and stand it off the arm
    for p in parts:
        p.rotation_euler = Euler((0.0, math.radians(90.0), 0.0))
        S.apply_transforms(p)
        p.location = (offset, 0.0, 0.0)
        S.apply_transforms(p)
    return done(parts, rng, "Socket.ShieldL", ["wood_planks", "iron", "leather"], jitter=0.0)


# --- the bosses' own tools, and what they carry about them --------------------------------------
#
# A boss is known across a hall by what is in its hands: the overman's pick, the digger-king's spade,
# the founder's sledge, the lampman's lamp on its pole. Each is built as the weapons above are (the
# grip's middle at the origin, the working end up +Z and leading along +Y), so it goes into the hand
# with no transform of its own; the carried ones (a bell on a yoke, a speaking-trumpet) are hung on
# the body by EnemyDress `carry` and stand in their own frame, +Z up, facing -Y (the body's front).

def _chain(name, pts, link, wire, mat):
    """A chain of iron links along the polyline `pts`, each link turned a quarter to the last."""
    parts = []
    path = [Vector(p) for p in pts]
    seg = []
    for a, b in zip(path[:-1], path[1:]):
        n = max(1, int((b - a).length / (link * 1.6)))
        for i in range(n):
            seg.append((a.lerp(b, (i + 0.5) / n), (b - a).normalized()))
    for i, (c, d) in enumerate(seg):
        ob = S.torus("%s_%d" % (name, i), major=link * 0.5, minor=wire, seg_major=10, seg_minor=5, mat=mat)
        ob.scale = (1.0, 0.62, 1.0)
        S.apply_transforms(ob)
        # the link's long axis (its local X after the squash) along the chain, each turned 90 degrees
        q = Vector((1.0, 0.0, 0.0)).rotation_difference(d)
        ob.rotation_mode = "QUATERNION"
        roll = Euler((math.radians(90.0 * (i % 2)), 0.0, 0.0)).to_quaternion()
        ob.rotation_quaternion = q @ roll
        ob.location = c
        S.apply_transforms(ob)
        parts.append(ob)
    return parts


def pick(pal, rng, params, variant):
    """A miner's pick: an oak haft worn to one man's hands, held two-handed, and across its top an
    iron head drawn to a point along +Y and to a chisel behind. `chalk` whitens the haft and the
    iron with the dust of a chalk face."""
    finish = _finish(params)
    chalk = float(params.get("chalk", 0.0))
    top = jit(rng, 0.62, 0.02)
    butt = -0.30
    steel = blade_mat(pal, rng, finish)
    metal = fitting_mat(pal, rng, finish)
    wood = haft_mat(pal, rng, base_hex="#b9ab90" if chalk > 0.5 else "#6e5232", name="pick_haft")
    hide = grip_mat(pal, finish)
    r = 0.017 * STOUT
    parts = [_haft("haft", butt, top + 0.04, r * 1.12, r * 0.96, wood, rng, bow=rng.uniform(-0.005, 0.005))]
    parts.append(S.lathe("butt_swell", [(r * 1.1, butt - 0.004), (r * 1.4, butt + 0.015), (r * 1.15, butt + 0.04)],
                         segments=10, mat=wood, close=True))
    parts += _grip("grip", -0.26, -0.04, r * 1.05, hide, rng)
    hz = top
    # the eye round the haft, and two arms out of it curving down: a point to +Y, a chisel to -Y
    parts.append(S.box_centered("eye", (0.046, 0.06, 0.07), (0.0, 0.0, hz), mat=steel))
    S.bevel(parts[-1], width=0.008, segments=2, angle_deg=40)
    for side, reach, end_w in ((1.0, 0.27, 0.004), (-1.0, 0.2, 0.016)):
        pts = []
        for i in range(9):
            f = i / 8
            pts.append((0.0, side * (0.02 + reach * f), hz + 0.01 - 0.07 * f ** 1.6))
        arm = S.tube_along("arm_%d" % int(side), pts, radius=0.022, segments=8, radius_end=end_w, mat=steel)
        arm.scale = (0.75, 1.0, 1.0)
        S.apply_transforms(arm)
        parts.append(arm)
    parts.append(S.box_centered("wedge", (r * 0.6, r * 1.8, 0.01), (0.0, 0.0, hz + 0.038), mat=metal))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0006,
                extra={"two_handed": True})


def drift_hook(pal, rng, params, variant):
    """A shift-captain's drift hook: a long ash pole bound in brass, held a third of the way up, and
    at its top a forged iron hook for drawing the tubs along the drift, its bill leading along +Y and
    curling back down, a spike above it."""
    finish = _finish(params)
    iron_ = M.iron(pal, age=0.55, wear=0.7, scale=0.08, name="hook_iron")
    brass = M.brass(pal, age=0.6, wear=0.6, scale=0.06, name="hook_brass")
    wood = haft_mat(pal, rng, base_hex="#6a5236", name="pole_wood")
    hide = grip_mat(pal, finish)
    r = 0.016 * STOUT
    butt, top = -0.55, jit(rng, 1.25, 0.02)
    parts = [_haft("pole", butt, top, r * 1.05, r * 0.92, wood, rng, bow=rng.uniform(0.006, 0.014))]
    parts += _grip("grip", -0.08, 0.08, r * 1.04, hide, rng)
    for k, z in enumerate((0.42, 0.78, top - 0.12)):
        parts.append(_band("brass_%d" % k, z, r, 0.03, brass))
    parts.append(S.lathe("ferrule", [(r * 1.0, butt - 0.02), (r * 1.15, butt + 0.01), (r * 1.0, butt + 0.06)],
                         segments=10, mat=brass, close=True))
    parts.append(S.lathe("socket", [(r * 1.15, top - 0.08), (r * 1.25, top), (r * 0.9, top + 0.06)],
                         segments=10, mat=iron_, close=True))
    # the hook: out along +Y and round and down, tapering to its bill
    pts = []
    for i in range(13):
        t = i / 12
        a = math.pi * 1.15 * t
        pts.append((0.0, 0.085 * math.sin(a) + 0.01, top + 0.06 + 0.085 * (1.0 - math.cos(a)) * 0.9 - 0.07 * t * t))
    hook = S.tube_along("hook", pts, radius=0.016, segments=8, radius_end=0.004, mat=iron_)
    hook.scale = (0.7, 1.0, 1.0)
    S.apply_transforms(hook)
    parts.append(hook)
    parts.append(S.tube_along("spike", [(0.0, 0.0, top + 0.04), (0.0, -0.01, top + 0.2)], radius=0.012, segments=8,
                              radius_end=0.002, mat=iron_))
    return done(parts, rng, "Socket.WeaponR", ["iron", "brass", "wood_planks"], jitter=0.0005,
                extra={"two_handed": True})


def seal_staff(pal, rng, params, variant):
    """A receiver's staff of office: a tall black staff ending in the barrow's great seal, a disc of
    iron as broad as a hand is long, its face (the struck mark) leading along +Y, ringed and bossed."""
    finish = _finish(params)
    iron_ = M.blackened_iron(pal, age=0.5, wear=0.55, scale=0.08, name="seal_iron")
    brass = M.brass(pal, age=0.75, wear=0.45, scale=0.06, name="seal_brass")
    wood = haft_mat(pal, rng, base_hex="#2e2620", name="staff_black")
    r = 0.016 * STOUT
    butt, top = -0.6, jit(rng, 1.2, 0.02)
    parts = [_haft("staff", butt, top, r * 1.0, r * 1.05, wood, rng)]
    for k, z in enumerate((-0.12, 0.12, 0.62, top - 0.06)):
        parts.append(_band("ring_%d" % k, z, r, 0.022, brass))
    parts.append(S.lathe("shoe", [(r * 0.9, butt - 0.03), (r * 1.1, butt + 0.01), (r * 1.0, butt + 0.06)],
                         segments=10, mat=iron_, close=True))
    # the seal: a thick disc across the top, face to +Y, a boss behind for the hand to strike it
    sz = top + 0.11
    disc = S.cylinder("seal", radius=0.11, depth=0.05, vertices=22, location=(0.0, 0.03, sz), rotation=(90, 0, 0),
                      mat=iron_, centered=True)
    S.bevel(disc, width=0.008, segments=2, angle_deg=40)
    parts.append(disc)
    parts.append(B.hoop("seal_rim", 0.105, 0.009, mat=brass, location=(0.0, 0.058, sz), rotation=(90, 0, 0),
                        flatten=1.0))
    parts.append(B.hoop("seal_ring", 0.055, 0.007, mat=brass, location=(0.0, 0.058, sz), rotation=(90, 0, 0),
                        flatten=1.0))
    parts.append(S.lathe("neck", [(r * 1.1, top - 0.02), (r * 1.5, top + 0.03), (0.03, sz - 0.06)],
                         segments=10, mat=iron_, close=True))
    parts.append(S.sphere("boss", radius=0.035, subdivisions=2, location=(0.0, -0.01, sz), mat=brass))
    return done(parts, rng, "Socket.WeaponR", ["iron", "brass", "wood_planks"], jitter=0.0004,
                extra={"two_handed": True})


def spade(pal, rng, params, variant):
    """A barrow-digger's spade: an ash shaft with a crutch at its foot for the hands, and at its top
    a wooden blade shod in iron, its face leading along +Y and its cutting edge up."""
    finish = _finish(params)
    iron_ = M.iron(pal, age=0.75, wear=0.85, scale=0.08, name="shoe_iron")
    wood = haft_mat(pal, rng, base_hex="#6e5638", name="spade_wood")
    hide = grip_mat(pal, finish)
    r = 0.018 * STOUT
    butt, top = -0.42, jit(rng, 0.62, 0.02)
    parts = [_haft("shaft", butt, top, r * 1.05, r * 1.0, wood, rng, bow=rng.uniform(-0.004, 0.004))]
    parts += _grip("grip", -0.06, 0.08, r * 1.04, hide, rng)
    # the crutch handle across the foot of the shaft
    parts.append(S.tube_along("crutch", [(-0.075, 0.0, butt - 0.01), (0.0, 0.0, butt - 0.035), (0.075, 0.0, butt - 0.01)],
                              radius=r * 0.95, segments=8, mat=wood))
    # the blade: a tapered board, flats facing +-Y, widening up to the shod edge
    bz = top - 0.02
    blade_h, w0, w1 = 0.34, 0.15, 0.2
    outline = [(-w0 * 0.5, bz), (w0 * 0.5, bz), (w1 * 0.5, bz + blade_h * 0.85), (w1 * 0.45, bz + blade_h),
               (-w1 * 0.45, bz + blade_h), (-w1 * 0.5, bz + blade_h * 0.85)]
    blade = _prism("blade", outline, lambda y, z: 0.03 - 0.016 * (z - bz) / blade_h, wood)
    # _prism lays the outline in YZ with its thickness on X; turn it so the face leads along +Y
    blade.rotation_euler = Euler((0.0, 0.0, math.radians(90.0)))
    S.apply_transforms(blade)
    S.bevel(blade, width=0.004, segments=1, angle_deg=35)
    parts.append(blade)
    shoe = S.box_centered("shoe", (w1 * 1.02, 0.026, 0.06), (0.0, 0.0, bz + blade_h - 0.02), mat=iron_)
    S.bevel(shoe, width=0.006, segments=2, angle_deg=40)
    parts.append(shoe)
    for sx in (-1.0, 1.0):
        parts.append(S.box_centered("strap_%d" % int(sx), (0.022, 0.034, blade_h * 0.8),
                                    (sx * w0 * 0.42, 0.0, bz + blade_h * 0.42), mat=iron_))
    parts.append(S.lathe("collar", [(r * 1.1, bz - 0.07), (r * 1.4, bz - 0.02), (r * 1.6, bz + 0.03)],
                         segments=10, mat=iron_, close=True))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "leather"], jitter=0.0006,
                extra={"two_handed": True})


def sledge(pal, rng, params, variant):
    """A founder's sledge: a long hickory haft and a great iron head set across it, both faces
    banded, the one that leads along +Y crowned with bell bronze from the moulds it has broken."""
    finish = _finish(params)
    iron_ = M.iron(pal, age=0.7, wear=0.8, scale=0.1, name="sledge_iron")
    bronze = M.bell_bronze_patina(pal, age=0.6, wear=0.7, scale=0.08, name="sledge_bronze")
    wood = haft_mat(pal, rng, base_hex="#6a4e30", name="sledge_haft")
    hide = grip_mat(pal, finish)
    r = 0.02 * STOUT
    butt, top = -0.38, jit(rng, 0.66, 0.02)
    parts = [_haft("haft", butt, top + 0.05, r * 1.1, r * 0.95, wood, rng)]
    parts += _grip("grip", -0.34, -0.02, r * 1.04, hide, rng)
    parts.append(_band("band", 0.3, r, 0.03, iron_))
    hz = top
    head = S.cylinder("head", radius=0.075, depth=0.36, vertices=12, location=(0.0, 0.0, hz), rotation=(90, 0, 0),
                      mat=iron_, centered=True)
    S.bevel(head, width=0.01, segments=2, angle_deg=40)
    parts.append(head)
    for y, m in ((0.17, bronze), (-0.17, iron_)):
        parts.append(B.hoop("face_band_%d" % int(y * 100), 0.078, 0.012, mat=m, location=(0.0, y, hz),
                            rotation=(90, 0, 0), flatten=1.0))
    parts.append(S.cylinder("face", radius=0.068, depth=0.03, vertices=12, location=(0.0, 0.19, hz), rotation=(90, 0, 0),
                            mat=bronze, centered=True))
    return done(parts, rng, "Socket.WeaponR", ["iron", "bell_bronze_patina", "wood_planks"], jitter=0.0008,
                extra={"two_handed": True})


def lamp_pole(pal, rng, params, variant):
    """The lampman's lamp on its pole: a winch-bar of iron-shod oak held two-handed, and from a hook
    at its top the sea-mouth lamp on a short chain, its glass lit."""
    finish = _finish(params)
    iron_ = M.iron(pal, age=0.8, wear=0.6, scale=0.1, name="pole_iron")
    wood = haft_mat(pal, rng, base_hex="#5a4632", name="winch_bar")
    hide = grip_mat(pal, finish)
    r = 0.02 * STOUT
    butt, top = -0.62, jit(rng, 1.25, 0.02)
    parts = [_haft("pole", butt, top, r * 1.05, r * 0.9, wood, rng, bow=rng.uniform(0.005, 0.012))]
    parts += _grip("grip", -0.1, 0.1, r * 1.04, hide, rng)
    parts.append(S.lathe("shoe", [(r * 1.0, butt - 0.05), (r * 1.2, butt), (r * 1.05, butt + 0.08)],
                         segments=10, mat=iron_, close=True))
    # the crook at the top, out along +Y, and the lamp hanging from it on three links
    crook = [(0.0, 0.0, top - 0.04), (0.0, 0.05, top + 0.06), (0.0, 0.14, top + 0.08), (0.0, 0.2, top + 0.03)]
    parts.append(S.tube_along("crook", crook, radius=0.012, segments=8, radius_end=0.009, mat=iron_))
    hang = Vector((0.0, 0.2, top + 0.01))
    parts += _chain("lamp_chain", [hang, hang + Vector((0.0, 0.0, -0.12))], 0.04, 0.0045, iron_)
    from gen_props import _lantern_body
    glass = M.glass(pal, color=M.P.lin("#f2d79a"), name="lamp_glass")
    body, lr = _lantern_body(pal, rng, 0.3, iron_, glass)
    for ob in body:
        ob.location = (ob.location[0], ob.location[1] + 0.2, ob.location[2] + top - 0.43)
        S.apply_transforms(ob)
    parts += body
    parts.append(S.torus("lamp_ring", major=0.025, minor=0.005, seg_major=12, seg_minor=5,
                         location=(0.0, 0.2, top - 0.15), rotation=(90, 0, 0), mat=iron_))
    return done(parts, rng, "Socket.WeaponR", ["iron", "glass", "wood_planks"], jitter=0.0004,
                extra={"two_handed": True, "emissive": True, "lamp": [0.0, top - 0.3, -0.2]})


def rasp(pal, rng, params, variant):
    """A farrier's rasp, held as a short sword: a flat bar of steel forty centimetres long, its
    flats (±X) cut across in teeth, tapering to a blunt end, on a wooden handle."""
    finish = _finish(params)
    steel = M.iron(pal, age=0.35, wear=0.9, scale=0.05, name="rasp_steel")
    wood = haft_mat(pal, rng, base_hex="#7a5a36", name="rasp_handle")
    parts = []
    parts.append(S.lathe("handle", [(0.012, -0.075), (0.018, -0.06), (0.02, 0.0), (0.017, 0.055), (0.012, 0.065)],
                         segments=10, mat=wood, close=True))
    parts.append(S.lathe("ferrule", [(0.014, 0.06), (0.016, 0.065), (0.016, 0.08), (0.013, 0.085)], segments=10,
                         mat=steel, close=True))
    L = jit(rng, 0.4, 0.02)
    z0 = 0.085
    outline = [(-0.021, z0), (0.021, z0), (0.02, z0 + L * 0.85), (0.012, z0 + L), (-0.012, z0 + L), (-0.02, z0 + L * 0.85)]
    bar = _prism("bar", outline, lambda y, z: 0.009, steel)
    S.bevel(bar, width=0.0015, segments=1, angle_deg=35)
    parts.append(bar)
    # the teeth: rows of small ridges across both flats
    n = int(L / 0.012)
    for i in range(n):
        z = z0 + 0.015 + i * 0.012
        for sx in (-1.0, 1.0):
            t = S.box_centered("tooth_%d_%d" % (i, int(sx)), (0.0022, 0.038, 0.0035), (sx * 0.0046, 0.0, z), mat=steel)
            t.rotation_euler = Euler((math.radians(18.0 * sx), 0.0, 0.0))
            S.apply_transforms(t)
            parts.append(t)
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks"], jitter=0.0)


def leister(pal, rng, params, variant):
    """An eel spear, the Reedfolk's leister: a long shaft held two-handed and at its head a fan of
    flat barbed tines on a crossbar, spread along ±Y like a comb, for pinning an eel in the mud."""
    finish = _finish(params)
    iron_ = M.iron(pal, age=0.8, wear=0.55, scale=0.06, name="tine_iron")
    wood = haft_mat(pal, rng, base_hex="#5d4c38", name="leister_shaft")
    cord = M.rope(pal, age=0.6, scale=0.05)
    r = 0.016 * STOUT
    butt, top = -0.8, jit(rng, 1.45, 0.02)
    parts = [_haft("shaft", butt, top, r * 1.0, r * 0.88, wood, rng, bow=rng.uniform(-0.01, 0.01))]
    for k in range(5):
        parts.append(B.rope_loop("lash_%d" % k, r * 1.08, r * 0.24, mat=cord, segments=10,
                                 location=(0.0, 0.0, top - 0.02 - k * r * 0.6)))
    bar = S.box_centered("crossbar", (0.03, 0.24, 0.03), (0.0, 0.0, top + 0.02), mat=wood)
    S.bevel(bar, width=0.006, segments=2, angle_deg=40)
    parts.append(bar)
    tines = 7
    for i in range(tines):
        y = -0.105 + 0.21 * i / (tines - 1)
        spread = y * 0.35
        base = (0.0, y, top + 0.02)
        tip = (0.0, y + spread, top + 0.36 - abs(y) * 0.4)
        parts.append(S.tube_along("tine_%d" % i, [base, (0.0, y + spread * 0.5, top + 0.2), tip], radius=0.007,
                                  segments=6, radius_end=0.0025, mat=iron_))
        # a barb on the inside of each tine, turned back
        bz = top + 0.27 - abs(y) * 0.3
        parts.append(S.tube_along("barb_%d" % i, [(0.0, y + spread * 0.8, bz), (0.0, y + spread * 0.8 - 0.012, bz - 0.04)],
                                  radius=0.004, segments=5, radius_end=0.0015, mat=iron_))
    return done(parts, rng, "Socket.WeaponR", ["iron", "wood_planks", "rope"], jitter=0.0004,
                extra={"two_handed": True})


def crook(pal, rng, params, variant):
    """A barrow-wife's crook: a tall staff of black thorn held two-handed, its head bent over into
    a hook along +Y, and from the hook her lamp on a cord, long gone out."""
    finish = _finish(params)
    wood = haft_mat(pal, rng, base_hex="#3a2e24", name="crook_wood")
    iron_ = M.iron(pal, age=0.9, wear=0.4, scale=0.08, name="lamp_iron")
    cord = M.rope(pal, age=0.8, scale=0.05)
    r = 0.017 * STOUT
    butt, top = -0.75, jit(rng, 1.05, 0.02)
    n = 10
    pts = [(math.sin(i / n * 2.0) * 0.012, 0.0, butt + (top - butt) * i / n) for i in range(n + 1)]
    staff = S.tube_along("staff", pts, radius=r * 0.95, segments=10, radius_end=r * 0.9, mat=wood)
    S.jitter_verts(staff, amount=0.0012, scale=0.2, seed=rng.randrange(999))
    parts = [staff]
    # the hook: up, over toward +Y and down
    hook = []
    for i in range(15):
        a = math.pi * 1.25 * i / 14
        hook.append((pts[-1][0], 0.09 * (1.0 - math.cos(a)), top + 0.1 * math.sin(a) + 0.02 * i / 14))
    parts.append(S.tube_along("hook", [pts[-1]] + hook, radius=r * 0.9, segments=10, radius_end=r * 0.65, mat=wood))
    for k in range(3):
        parts.append(S.sphere("knot_%d" % k, radius=r * 0.6, subdivisions=1,
                              location=(r * 0.7, 0.0, butt + (top - butt) * (0.3 + 0.2 * k)), mat=wood,
                              scale=(0.7, 1.0, 1.3)))
    # the dead lamp, hanging from the hook's end on its cord
    end = Vector(hook[-1])
    cord_end = end + Vector((0.0, 0.0, -0.16))
    parts.append(S.tube_along("lamp_cord", [end, end + Vector((0.0, 0.004, -0.08)), cord_end], radius=0.0035,
                              segments=5, mat=cord))
    from gen_props import _lantern_body
    dead = M.glass(pal, color=M.P.lin("#4a4a44"), name="dead_glass")
    body, lr = _lantern_body(pal, rng, 0.24, iron_, dead)
    # no flame: it went out a hundred years ago
    body = [ob for ob in body if not ob.name.startswith("flame")]
    for ob in body:
        ob.location = (ob.location[0] + end.x, ob.location[1] + end.y, ob.location[2] + cord_end.z - 0.21)
        S.apply_transforms(ob)
    parts += body
    return done(parts, rng, "Socket.WeaponR", ["wood_planks", "iron", "glass", "rope"], jitter=0.0004,
                extra={"two_handed": True})


def censer(pal, rng, params, variant):
    """A chorister's censer, swung as a flail: a short bronze rod for the hand, three chains, and a
    pierced globe of bell bronze with a lid, held up the socket's +Z as the hand swings it."""
    finish = _finish(params)
    metal = M.bell_bronze_patina(pal, age=0.55, wear=0.7, scale=0.06, name="censer_bronze")
    iron_ = M.iron(pal, age=0.6, wear=0.5, scale=0.05, name="censer_chain")
    parts = [S.lathe("rod", [(0.013, -0.09), (0.016, -0.08), (0.016, 0.07), (0.02, 0.085), (0.008, 0.1)],
                     segments=10, mat=metal, close=True)]
    parts.append(B.hoop("rod_ring", 0.022, 0.005, mat=metal, location=(0.0, 0.0, 0.1), flatten=1.0))
    gz = 0.44
    for k in range(3):
        a = TAU * k / 3
        foot = Vector((math.cos(a) * 0.075, math.sin(a) * 0.075, gz - 0.02))
        parts += _chain("chain_%d" % k, [Vector((0.0, 0.0, 0.11)), foot], 0.026, 0.003, iron_)
    globe = S.uv_sphere("globe", radius=0.085, segments=16, rings=10, location=(0.0, 0.0, gz + 0.05), mat=metal,
                        scale=(1.0, 1.0, 0.85))
    S.apply_transforms(globe)
    parts.append(globe)
    parts.append(B.hoop("globe_rim", 0.087, 0.008, mat=metal, location=(0.0, 0.0, gz + 0.05), flatten=1.0))
    parts.append(S.lathe("lid", [(0.04, gz + 0.115), (0.03, gz + 0.15), (0.012, gz + 0.19), (0.0, gz + 0.2)],
                         segments=10, mat=metal, close=True))
    parts.append(S.lathe("foot", [(0.0, gz - 0.04), (0.04, gz - 0.035), (0.03, gz - 0.01)], segments=10, mat=metal,
                         close=True))
    return done(parts, rng, "Socket.WeaponR", ["bell_bronze_patina", "iron"], jitter=0.0003)


def trumpet(pal, rng, params, variant):
    """A Sayer's speaking-trumpet of beaten brass as long as an arm: a mouthpiece, a long cone
    flaring to a bell a forearm wide, ringed with the Circle's brass ribs. Carried on the back,
    standing in its own frame up +Z, the bell at the top."""
    brass = M.brass(pal, age=0.45, wear=0.7, scale=0.1, name="trumpet_brass")
    L = jit(rng, 0.8, 0.02)
    prof = [(0.012, 0.0), (0.016, 0.03), (0.018, L * 0.2), (0.026, L * 0.45), (0.045, L * 0.7), (0.09, L * 0.88),
            (0.16, L * 0.98), (0.17, L)]
    inner = [(max(0.006, x - 0.004), z) for (x, z) in reversed(prof)]
    body = S.lathe("horn", prof + inner, segments=20, mat=brass, close=False)
    S.shade_smooth(body, 40.0)
    parts = [body]
    for k, f in enumerate((0.25, 0.5, 0.72, 0.86, 0.97)):
        z = L * f
        rr = float(np.interp(z, [p[1] for p in prof], [p[0] for p in prof]))
        parts.append(B.hoop("rib_%d" % k, rr + 0.004, 0.005, mat=brass, location=(0.0, 0.0, z), flatten=1.0))
    parts.append(S.lathe("mouth", [(0.0, -0.03), (0.022, -0.028), (0.016, -0.005), (0.013, 0.0)], segments=12,
                         mat=brass, close=True))
    return done(parts, rng, "Socket.Back", ["brass"], jitter=0.0)


def tuning_bell(pal, rng, params, variant):
    """The founders' great tuning-bell on its yoke of chain: a bell three hands high, hung mouth
    down from a beam across the shoulders, the chains running from the beam's ends down to the
    canons. Carried on the back, standing in its own frame up +Z, the beam at the top."""
    from gen_props import _bell
    iron_ = M.iron(pal, age=0.8, wear=0.6, scale=0.1, name="yoke_iron")
    wood = haft_mat(pal, rng, base_hex="#4e3a26", name="yoke_wood")
    h = jit(rng, 0.62, 0.02)
    bell, metal, r = _bell(pal, rng, h, patina=0.5)
    parts = list(bell)
    beam_z = h * 1.32
    beam = S.box_centered("yoke", (r * 2.9, 0.1, 0.09), (0.0, 0.0, beam_z), mat=wood)
    S.bevel(beam, width=0.015, segments=2, angle_deg=40)
    parts.append(beam)
    for sx in (-1.0, 1.0):
        top = Vector((sx * r * 1.25, 0.0, beam_z - 0.04))
        bottom = Vector((sx * r * 0.14, 0.0, h * 1.05))
        parts += _chain("yoke_chain_%d" % int(sx), [top, bottom], 0.05, 0.007, iron_)
        parts.append(B.hoop("yoke_band_%d" % int(sx), 0.075, 0.01, mat=iron_, location=(sx * r * 1.25, 0.0, beam_z),
                            rotation=(0, 90, 0), flatten=1.0))
    # the founders' marks round the waist of the bell: a raised band and a ring of bosses
    parts.append(B.hoop("waist", r * 0.72, 0.009, mat=metal, location=(0.0, 0.0, h * 0.4), flatten=1.0))
    for k in range(10):
        a = TAU * k / 10
        parts.append(S.sphere("boss_%d" % k, radius=0.014, subdivisions=1,
                              location=(math.cos(a) * r * 0.74, math.sin(a) * r * 0.74, h * 0.3), mat=metal))
    return done(parts, rng, "Socket.Back", ["bell_bronze_patina", "iron", "wood_planks"], jitter=0.0)


KINDS = {
    "sword": sword, "rapier": rapier, "greatsword": greatsword, "dagger": dagger, "knife": knife,
    "axe": axe, "mace": mace, "spear": spear, "staff": staff, "warhammer": warhammer, "clapper": clapper,
    "bow": bow, "shield": shield, "crossbow": crossbow, "scythe": scythe, "quiver": quiver,
    "pick": pick, "drift_hook": drift_hook, "seal_staff": seal_staff, "spade": spade, "sledge": sledge,
    "lamp_pole": lamp_pole, "rasp": rasp, "leister": leister, "crook": crook, "censer": censer,
    "trumpet": trumpet, "tuning_bell": tuning_bell,
}


if __name__ == "__main__":
    run_generator(__doc__, KINDS, category="weapons", generator="gen_weapons")
