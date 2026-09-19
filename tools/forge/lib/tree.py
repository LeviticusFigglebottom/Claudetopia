"""Sapling-driven tree building: trunk, branches, leaf-cluster cards, impostor LOD2.

Blender's `add_curve_sapling` add-on grows believable branching from a parameter set; we
convert its curve to a mesh, give it our bark material, and replace its flat leaf quads
with cards UV-mapped into a leaf-cluster atlas drawn by lib.textures. The result has real
volume (branches in three dimensions, cards facing outward) rather than a cone of planes.
"""
from __future__ import annotations

import math
import random

import addon_utils
import bmesh
import bpy
from mathutils import Euler, Vector

from . import scene as S

_ENABLED = False


def enable_sapling() -> None:
    global _ENABLED
    if not _ENABLED:
        addon_utils.enable("add_curve_sapling", default_set=False, persistent=True)
        _ENABLED = True


# Sapling defaults we always set; species dicts override.
BASE = dict(
    do_update=True, chooseSet="0", bevel=True, prune=False, showLeaves=True, useArm=False,
    handleType="0", levels=3, ratio=0.015, ratioPower=1.3, minRadius=0.0015, closeTip=False,
    rootFlare=1.2, autoTaper=True, taper=(1, 1, 1, 1), radiusTweak=(1, 1, 1, 1),
    resU=3, bevelRes=3, nrings=0, splitByLen=True, rMode="rotate", splitHeight=0.2,
    branchDist=1.2, leafShape="rect", leafDist="6", leafangle=-35.0, horzLeaves=False,
    leafScaleT=0.0, leafScaleV=0.2, leafRotate=137.5, leafRotateV=25.0, leafDownAngleV=12.0,
    useOldDownAngle=False, useParentAngle=True, armLevels=2, boneStep=(1, 1, 1, 1),
    makeMesh=False, armAnim=False, previewArm=False, leafAnim=False,
)


def grow(params: dict, seed: int):
    """Run Sapling and return (trunk_object, leaf_object|None)."""
    enable_sapling()
    before = set(bpy.context.scene.objects)
    kw = dict(BASE)
    kw.update(params)
    kw["seed"] = int(seed) % 100000
    bpy.ops.curve.tree_add(**kw)
    new = [o for o in bpy.context.scene.objects if o not in before]
    curve = next((o for o in new if o.type == "CURVE"), None)
    leaves = next((o for o in new if o.type == "MESH" and o is not curve), None)
    if curve is None:
        raise RuntimeError("sapling produced no curve")
    S.select_only([curve])
    bpy.ops.object.convert(target="MESH")
    trunk = bpy.context.view_layer.objects.active
    trunk.name = "trunk"
    trunk.data.name = "trunk"
    for o in new:
        if o is not curve and o is not leaves and o.name in bpy.context.scene.objects:
            S.delete([o])
    return trunk, leaves


def cap_resolution(sap: dict, budget: str = "normal", quick: bool = False) -> dict:
    """Bound Sapling's cost while keeping each species' relative character.

    Sapling's `leaves` is per parent branch, so a plain count explodes into tens of
    thousands of quads; `branches` multiplies down the levels the same way. Caps are
    applied as minimums against the species values, so a species that asks for less keeps
    its sparser look.
    """
    caps = {
        "normal": dict(bevel=1, resU=2, curve=(9, 6, 4, 2), branches=(0, 30, 14, 0)),
        "hero": dict(bevel=2, resU=2, curve=(11, 8, 5, 3), branches=(0, 34, 18, 0)),
        "small": dict(bevel=1, resU=2, curve=(7, 5, 3, 2), branches=(0, 34, 18, 0)),
    }[budget]
    if quick:
        caps = dict(bevel=1, resU=1, curve=(5, 4, 2, 1), branches=(0, 16, 6, 0))
    sap = dict(sap)
    sap["bevelRes"] = caps["bevel"]
    sap["resU"] = caps["resU"]
    cr = list(sap.get("curveRes", (8, 6, 4, 2)))
    sap["curveRes"] = tuple(min(c, caps["curve"][i]) for i, c in enumerate(cr[:4]))
    br = list(sap.get("branches", (0, 28, 14, 0)))
    sap["branches"] = tuple(min(b, caps["branches"][i]) for i, b in enumerate(br[:4]))
    return sap


def trim_to_budget(trunk, budget: int) -> int:
    """Decimate the grown trunk down to a triangle budget (DESIGN §7.0)."""
    tris = S.tri_count(trunk)
    if tris > budget:
        S.decimate(trunk, budget / float(tris))
    return S.tri_count(trunk)


def cards_from_leaves(leaves, name: str, mat, rng: random.Random, cells: int = 2,
                      scale: float = 1.0, jitter: float = 0.25, keep: float = 1.0,
                      droop_deg: float = 0.0, target: int | None = None, min_z: float = 0.0):
    """Turn Sapling's leaf quads into atlas-mapped cluster cards.

    Each quad becomes one card: it is scaled about its own centre, tilted a little, and its
    UVs are rewritten to one random cell of the `cells`x`cells` atlas (with a random flip),
    so no two cards show the same picture.
    """
    if leaves is None:
        raise RuntimeError("no leaf object to build cards from")
    me = leaves.data
    S.apply_transforms(leaves)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.verify()
    faces = list(bm.faces)
    if min_z > 0.0:
        # Sapling puts leaf points on the lowest branches too; at card scale those bury
        # half a cluster in the ground. Nothing grows out of the soil, so drop them.
        buried = [f for f in faces if f.calc_center_median().z < min_z]
        if buried and len(buried) < len(faces):
            bmesh.ops.delete(bm, geom=buried, context="FACES")
            faces = [f for f in faces if f.is_valid]
    if target is not None and faces:
        keep = min(keep, target / float(len(faces)))
    if keep < 1.0:
        rng.shuffle(faces)
        drop = faces[int(len(faces) * keep):]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        faces = [f for f in faces if f.is_valid]
    cell = 1.0 / cells
    for f in faces:
        if not f.is_valid or len(f.loops) != 4:
            continue
        c = f.calc_center_median()
        n = f.normal.copy()
        s = scale * rng.uniform(1.0 - jitter, 1.0 + jitter)
        # random roll about the card normal keeps clusters from lining up
        roll = rng.uniform(0, math.tau)
        droop = math.radians(droop_deg) * rng.uniform(0.4, 1.0) if droop_deg else 0.0
        axis = n.cross(Vector((0, 0, 1)))
        for v in f.verts:
            d = v.co - c
            d = d * s
            d.rotate(Euler((0, 0, 0)))
            if roll:
                d.rotate(_axis_rot(n, roll))
            if droop and axis.length > 1e-5:
                d.rotate(_axis_rot(axis.normalized(), droop))
            v.co = c + d
        cx = rng.randrange(cells)
        cy = rng.randrange(cells)
        flip = rng.random() < 0.5
        corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        if flip:
            corners = [(1.0 - u, v) for (u, v) in corners]
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv_layer].uv = ((cx + u) * cell, (cy + v) * cell)
    bm.to_mesh(me)
    bm.free()
    me.update()
    leaves.name = name
    me.name = name
    me.materials.clear()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = False
    return leaves


def _axis_rot(axis, angle):
    from mathutils import Matrix
    return Matrix.Rotation(angle, 4, axis).to_euler()


def card_positions(leaves, n: int, rng: random.Random) -> list:
    """Sample n face centres (and normals) from a leaf mesh: where to hang extra cards."""
    me = leaves.data
    polys = list(me.polygons)
    if not polys:
        return []
    out = []
    for _ in range(n):
        p = polys[rng.randrange(len(polys))]
        c = Vector(p.center)
        out.append((c, Vector(p.normal)))
    return out


def hanging_cards(positions, name: str, mat, rng: random.Random, length=(1.2, 3.0), width=(0.35, 0.8),
                  cells: int = 2, sway: float = 0.25):
    """Vertical cards hanging from the given points: moss beards, vines, willow curtains."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    for (pos, _n) in positions:
        ln = rng.uniform(*length)
        wd = rng.uniform(*width)
        ang = rng.uniform(0, math.tau)
        dx, dy = math.cos(ang) * wd * 0.5, math.sin(ang) * wd * 0.5
        drift = Vector((rng.uniform(-sway, sway), rng.uniform(-sway, sway), 0.0)) * ln
        verts = [
            bm.verts.new(pos + Vector((-dx, -dy, 0.0))),
            bm.verts.new(pos + Vector((dx, dy, 0.0))),
            bm.verts.new(pos + Vector((dx, dy, 0.0)) + Vector((0, 0, -ln)) + drift),
            bm.verts.new(pos + Vector((-dx, -dy, 0.0)) + Vector((0, 0, -ln)) + drift),
        ]
        f = bm.faces.new(verts)
        cx, cy = rng.randrange(cells), rng.randrange(cells)
        corners = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv_layer].uv = ((cx + u) * cell, (cy + v) * cell)
    if not bm.faces:
        bm.free()
        return None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def buttress(trunk, rng: random.Random, count: int = 6, height: float = 4.0, reach: float = 2.2,
             thickness: float = 0.9, mat=None):
    """Root buttresses flaring from the base of a colossal trunk."""
    parts = []
    for i in range(count):
        a = math.tau * (i + rng.uniform(-0.15, 0.15)) / count
        h = height * rng.uniform(0.75, 1.2)
        r = reach * rng.uniform(0.8, 1.25)
        t = thickness * rng.uniform(0.8, 1.2)
        bm = bmesh.new()
        # a tapering fin: inner edge climbs the trunk, outer edge runs out along the ground
        steps = 7
        inner, outer = [], []
        for k in range(steps + 1):
            f = k / steps
            z = h * (f ** 0.8)
            inner.append(bm.verts.new((0.0, 0.0, z)))
            outer.append(bm.verts.new((r * (1 - f) ** 1.6, 0.0, z * 0.25 + 0.05)))
        for a0, b0, a1, b1 in zip(inner, outer, inner[1:], outer[1:]):
            bm.faces.new((a0, b0, b1, a1))
        me_ob = S.bm_to_object(bm, "buttress_%d" % i, mat, smooth=True)
        S.solidify(me_ob, thickness=t, offset=0.0)
        S.bevel(me_ob, width=t * 0.25, segments=2, angle_deg=40)
        me_ob.rotation_euler = Euler((0, 0, a), "XYZ")
        S.apply_transforms(me_ob)
        S.jitter_verts(me_ob, amount=t * 0.12, scale=1.5, seed=rng.randrange(1000))
        parts.append(me_ob)
    return parts


def bark_relief(trunk, strength: float = 0.02, scale: float = 0.35, seed: int = 0) -> None:
    """Low-frequency displacement so the trunk is not a smooth tube."""
    t = S.new_texture("bark_%d" % seed, "CLOUDS", noise_scale=scale, noise_depth=2, noise_basis="ORIGINAL_PERLIN")
    off = Vector((seed * 3.7 % 11.0, seed * 5.3 % 7.0, 0.0))
    trunk.location += off
    S.apply_transforms(trunk, location=True, rotation=False, scale=False)
    S.displace(trunk, t, strength=strength, mid_level=0.5, direction="NORMAL", coords="GLOBAL")
    trunk.location -= off
    S.apply_transforms(trunk, location=True, rotation=False, scale=False)


def trunk_tris(trunk) -> int:
    return S.tri_count(trunk)
