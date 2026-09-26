"""The far herd's mesh: a quadruped's smallest LOD in its bind pose, with its parts in the vertex
colours, for the vertex-animated MultiMesh the water agent draws past about 150 m.

The layout is theirs (a message of 2026-09-25):

    R  0 off the legs; on a leg, which one: 0.25 fore left, 0.5 fore right, 0.75 hind left,
       1.0 hind right -- constant down the leg (the shader hinges each at its top vertex)
    G  neck and head, 0 at the withers rising to 1 at the muzzle (graze bends, not hinges)
    B  tail, 0 at its root to 1 at its tip
    A  1

Standing square, +Z forward in glTF (Blender's -Y), feet on y = 0, metres, the same proportions
as the rigged near LOD so the swap does not pop. `herd_colours` is pure numpy and reads the
skin weights; `export_bind` is the Blender half.
"""
from __future__ import annotations

from typing import Sequence

import numpy as np

from .quadruped import QuadSkeleton

LEGS = (
    (0.25, ("Forearm.L", "FrontCannon.L", "FrontPastern.L", "FrontHoof.L")),
    (0.50, ("Forearm.R", "FrontCannon.R", "FrontPastern.R", "FrontHoof.R")),
    (0.75, ("Gaskin.L", "HindCannon.L", "HindPastern.L", "HindHoof.L")),
    (1.00, ("Gaskin.R", "HindCannon.R", "HindPastern.R", "HindHoof.R")),
)
NECK = ("Neck1", "Neck2", "Head", "Jaw", "Ear.L", "Ear.R")
TAIL = ("Tail1", "Tail2", "Tail3")
FAR_TRIS = 590


def _smooth(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _arc_param(P: np.ndarray, line: np.ndarray) -> np.ndarray:
    """Each point's position along a polyline, 0 at its start and 1 at its end, by arc length."""
    seg = np.diff(line, axis=0)
    L = np.linalg.norm(seg, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(L)])
    best = np.full(len(P), np.inf)
    out = np.zeros(len(P))
    for i in range(len(seg)):
        u = np.clip(((P - line[i]) @ seg[i]) / max(float(seg[i] @ seg[i]), 1e-12), 0.0, 1.0)
        d = np.linalg.norm(P - (line[i] + u[:, None] * seg[i]), axis=1)
        take = d < best
        best[take] = d[take]
        out[take] = (cum[i] + u[take] * L[i]) / cum[-1]
    return out


def herd_colours(P: np.ndarray, W: np.ndarray, bones: Sequence[str], skel: QuadSkeleton) -> np.ndarray:
    """RGBA (n,4) for vertices P (n,3, Blender space, at bind) with skin weights W (n, len(bones))."""
    col = {b: j for j, b in enumerate(bones)}
    Wn = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)

    def wsum(names):
        return sum((Wn[:, col[b]] for b in names if b in col), np.zeros(len(P)))

    out = np.zeros((len(P), 4))
    out[:, 3] = 1.0
    legw = np.stack([wsum(names) for _, names in LEGS], axis=1)
    k = np.argmax(legw, axis=1)
    on_leg = legw[np.arange(len(P)), k] > 0.5
    out[on_leg, 0] = np.array([v for v, _ in LEGS])[k[on_leg]]
    J = skel.J
    neck_line = np.array([J["Chest"], J["Neck1"], J["Neck2"], J["Head"], J["Muzzle"]])
    out[:, 1] = _arc_param(P, neck_line) * _smooth(0.2, 0.6, wsum(NECK)) * (~on_leg)
    wt = wsum(TAIL)
    tail = wt > 0.3
    if tail.any():
        d = np.linalg.norm(P - J["TailHead"], axis=1)
        out[:, 2] = np.where(tail, d / max(float(d[tail].max()), 1e-6), 0.0) * _smooth(0.3, 0.7, wt)
    return np.clip(out, 0.0, 1.0)


def export_bind(src, skel: QuadSkeleton, bones: Sequence[str], path: str, tris: int = FAR_TRIS, log=print) -> str:
    """Copy the body object `src` (skinned, at bind, without its tack), take it under `tris`, paint the herd colours
    from its weights, and write it alone as a GLB with no skin."""
    import bpy
    from . import body as bodylib
    ob = src.copy()
    ob.data = src.data.copy()
    bpy.context.collection.objects.link(ob)
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # the coat alone: callers pass the body, not the LOD with the tack joined in, whose straps and
    # irons stopped the collapse short of the budget (the cob's first try stuck at 1195 triangles)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # a mesh read back from a GLB is split at every UV seam: weld it first, or its "largest
    # part" is one UV island (the ewe's first try kept 85 triangles and no legs)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    seen, parts = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, part = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            part.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        parts.append(part)
    # specks only (an eye, a buckle): a body that surface nets or a collapse left in pieces keeps
    # all of them
    total = sum(len(p) for p in parts)
    drop = [v for part in parts if len(part) < 0.02 * total for v in part]
    if drop:
        bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    for _ in range(6):
        n = bodylib.tri_count(ob)
        if n <= tris:
            break
        bodylib.decimate(ob, int(tris * 0.97), symmetry=False)
        if bodylib.tri_count(ob) >= n:
            break
    W = bodylib.weight_matrix(ob, bones)
    P = np.array([v.co[:] for v in ob.data.vertices])
    C = herd_colours(P, W, bones, skel)
    me = ob.data
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    attr = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    attr.data.foreach_set("color", C.astype(np.float32).ravel())
    me.color_attributes.active_color = attr
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_skins=False, export_animations=False,
                              export_colors=True, export_normals=True, export_texcoords=True,
                              export_materials='NONE')
    legs = [int(np.sum(np.isclose(C[:, 0], v))) for v, _ in LEGS]
    log("far herd mesh: %d tris, leg verts %s, neck verts %d, tail verts %d -> %s" % (
        bodylib.tri_count(ob), legs, int(np.sum(C[:, 1] > 0.05)), int(np.sum(C[:, 2] > 0.05)), path))
    bpy.data.objects.remove(ob, do_unlink=True)
    return path
