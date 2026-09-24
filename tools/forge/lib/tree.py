"""Tree meshes in Blender: grown wood, leaf-clump cards, hanging curtains, and the budget trim.

The branching itself is grown in lib/grow.py (pure numpy; Sapling, which this used to drive, is
gone from Blender 4.2 and its decimated output shattered every tree). Here the grown tubes become
one wood mesh with its own tiling UVs and smooth normals, and each leaf clump becomes a card
facing out of the crown, mapped into the sunlit or the shaded row of the species' atlas by how
exposed the clump is.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

from . import scene as S

## The per-face attribute that says in what order a budget may take a face's branch away: lower
## goes first. A whole branch shares one value, so a trim takes branches, never parts of them.
DROP_RANK = "forge_drop_rank"


def wood_object(name: str, V, N, UV, T, rank=None, mat=None):
    """A mesh object from grow.wood_mesh's arrays: positions, per-vertex normals (kept as custom
    normals, so the seam where a tube's UV wraps is not a crease), one UV layer and, per
    triangle, its branch's drop rank."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in V], [], [tuple(map(int, t)) for t in T])
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    loop_v = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", loop_v)
    uv.data.foreach_set("uv", np.asarray(UV, dtype=np.float32)[loop_v].reshape(-1))
    for p in me.polygons:
        p.use_smooth = True
    if rank is not None:
        attr = me.attributes.new(DROP_RANK, "INT", "FACE")
        attr.data.foreach_set("value", np.asarray(rank, dtype=np.int32))
    me.normals_split_custom_set_from_vertices([tuple(map(float, n)) for n in N])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    return ob


def trim_to_budget(obj, budget: int) -> int:
    """Bring a tree's wood under a triangle budget by taking whole branches away (DESIGN §7.0).

    This used to decimate, and a collapse decimator does not know what a branch is: it cut every
    limb into loose three-sided shards and the forest read as broken. Now a budget takes the
    branches the grower ranked least important (`forge_drop_rank`, a twig before the limb it grows
    on), or, on a mesh without ranks, whole connected pieces smallest first. Wood is never sliced;
    a mesh that cannot fit by dropping pieces is left over budget and says so in the count."""
    tris = S.tri_count(obj)
    if tris <= budget:
        return tris
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    layer = bm.faces.layers.int.get(DROP_RANK)
    groups: dict = {}
    if layer is not None:
        for f in bm.faces:
            groups.setdefault(f[layer], []).append(f)
        order = sorted(groups)                           # lowest rank dropped first
    else:
        seen = set()
        sizes = {}
        k = 0
        for f0 in bm.faces:
            if f0 in seen:
                continue
            stack, group = [f0], []
            while stack:
                f = stack.pop()
                if f in seen:
                    continue
                seen.add(f)
                group.append(f)
                for e in f.edges:
                    stack.extend(nf for nf in e.link_faces if nf not in seen)
            groups[k] = group
            co = np.array([v.co[:] for f in group for v in f.verts])
            sizes[k] = float((co.max(0) - co.min(0)).max())
            k += 1
        biggest = max(sizes, key=sizes.get)
        order = [g for g in sorted(sizes, key=sizes.get) if g != biggest]
    doomed = []
    for g in order:
        if tris <= budget:
            break
        faces = groups[g]
        doomed.extend(faces)
        tris -= sum(max(1, len(f.verts) - 2) for f in faces)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return S.tri_count(obj)


def _frame(nrm: Vector):
    ref = Vector((0.0, 0.0, 1.0)) if abs(nrm.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = nrm.cross(ref)
    u.normalize()
    v = nrm.cross(u)
    v.normalize()
    return u, v


def clump_cards(name: str, mat, points, sizes, exposure, rng: random.Random, crown_centre,
                cells: int = 2, sun_share: float = 0.5, droop_deg: float = 0.0, flat: float = 0.0):
    """One card per leaf clump, turned to face out of the crown with enough scatter that the cards
    do not all agree (a halo of edge-on cards reads as black needles), UV-mapped to a random
    column of the atlas and to its sunlit (top) or shaded (bottom) row by the clump's exposure.
    `flat` tips cards toward horizontal (a pine's layered sprays, a yew's shelves)."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    centre = Vector(crown_centre)
    cut = np.quantile(exposure, 1.0 - sun_share) if len(exposure) else 0.5
    for p, s, e in zip(points, sizes, exposure):
        c = Vector(tuple(map(float, p)))
        out = c - centre
        out.z *= 0.6
        if out.length < 1e-4:
            out = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.5))
        out.normalize()
        wob = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if wob.length < 1e-5:
            wob = Vector((0, 0, 1))
        wob.normalize()
        nrm = out * 0.6 + wob * 0.4 + Vector((0, 0, 1)) * flat
        if nrm.length < 1e-5:
            nrm = Vector((0, 0, 1))
        nrm.normalize()
        ua, va = _frame(nrm)
        roll = rng.uniform(0, math.tau)
        ua, va = ua * math.cos(roll) + va * math.sin(roll), va * math.cos(roll) - ua * math.sin(roll)
        if droop_deg:
            va = va - Vector((0.0, 0.0, 1.0)) * math.sin(math.radians(droop_deg) * rng.uniform(0.4, 1.0))
            va.normalize()
        half = float(s) * 0.5
        vs = [bm.verts.new(c + ua * (su * half) + va * (sv * half))
              for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        f = bm.faces.new(vs)
        col = rng.randrange(cells)
        # UV row cells-1 is the atlas' top image row: the sunlit one
        row = (cells - 1) if e >= cut else rng.randrange(cells - 1) if cells > 2 else 0
        corners = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        if rng.random() < 0.5:
            corners = [(1.0 - u, v) for (u, v) in corners]
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv_layer].uv = ((col + u) * cell, (row + v) * cell)
    if not bm.faces:
        bm.free()
        return None
    return S.bm_to_object(bm, name, mat, smooth=False)


def hanging_cards(positions, name: str, mat, rng: random.Random, length=(1.2, 3.0), width=(0.35, 0.8),
                  cells: int = 2, sway: float = 0.25, rows=None):
    """Vertical cards hanging from the given points: moss beards, willow curtains. `rows`, when
    given, is the atlas row (UV) for each card; otherwise rows are random."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    for k, (pos, _n) in enumerate(positions):
        pos = Vector(tuple(map(float, pos)))
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
        cx = rng.randrange(cells)
        cy = rows[k] if rows is not None else rng.randrange(cells)
        corners = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv_layer].uv = ((cx + u) * cell, (cy + v) * cell)
    if not bm.faces:
        bm.free()
        return None
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def trunk_tris(trunk) -> int:
    return S.tri_count(trunk)
