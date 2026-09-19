#!/usr/bin/env python3
"""Cave and dungeon forge for Wickmere.

Procedural generation is the BASE LAYER only. A recipe says what the place is and what
happens in it, beat by beat; this builds geometry that fits those beats, shaped by
whatever formed the place. Hand-placed detail is layered on afterwards in Godot from the
`features` list and the anchors this writes out.

    tools/interiors/cave_forge.py recipes/hollin_barrow.json --out game/assets/models/dungeon

Outputs per recipe (see docs/CONTRACTS.md §4 for the layout):
    <name>/<name>.glb        the cave shell, vertex-coloured with baked cavity shading
    <name>/<name>_col.glb    decimated collision shell
    <name>/<name>.meta.json  chambers, floors, light shafts, water, anchors, shortcut, beats
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

import numpy as np
import trimesh
from scipy import ndimage
from skimage import measure

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sdf  # noqa: E402

# How big a chamber each size word means: (radius_x, radius_y, radius_z) in metres.
SIZES = {
    "squeeze": (1.6, 1.5, 1.6),
    "tight": (2.6, 2.2, 2.6),
    "small": (4.0, 3.0, 4.0),
    "medium": (6.5, 4.2, 6.5),
    "large": (10.0, 6.5, 10.0),
    "huge": (16.0, 10.0, 16.0),
    "cathedral": (22.0, 16.0, 22.0),
}

# Each formation has its own grammar: how it digs, how rough it is, what it leaves behind.
FORMATIONS = {
    # Dissolved and scoured by moving water: smooth, winding, rounded, pools at the bottom.
    "water": {
        "tunnel": "round", "tunnel_radius": 2.1, "radius_jitter": 0.45,
        "noise_amp": 1.15, "noise_base": 7, "noise_octaves": 5, "fillet": 2.6,
        "turn_deg": (35, 85), "chamber_squash": 1.0, "floor_flatten": 0.15,
        "stalactites": 0.5, "stalagmites": 0.35, "columns": 0.15, "rubble": 0.1,
        "detail_amp": 0.3, "detail_base": 34, "fine_amp": 0.22, "fine_base": 60,
        "scallop": 0.45, "water_bias": 0.7, "ceiling_lift": 0.1,
    },
    # Cut by people following a vein: straight runs, square section, props, spoil heaps.
    "mining": {
        "tunnel": "box", "tunnel_radius": 1.5, "radius_jitter": 0.16,
        "noise_amp": 0.62, "noise_base": 10, "noise_octaves": 4, "fillet": 0.7,
        "turn_deg": (0, 30), "chamber_squash": 0.8, "floor_flatten": 0.75,
        "stalactites": 0.05, "stalagmites": 0.0, "columns": 0.0, "rubble": 0.55,
        "detail_amp": 0.16, "detail_base": 44, "fine_amp": 0.12, "fine_base": 80,
        "scallop": 0.1, "water_bias": 0.2, "ceiling_lift": 0.0,
    },
    # Dug and worn by something living: bulbous chambers, irregular bores, gouges.
    "creature": {
        "tunnel": "round", "tunnel_radius": 1.9, "radius_jitter": 0.7,
        "noise_amp": 1.5, "noise_base": 12, "noise_octaves": 5, "fillet": 3.2,
        "turn_deg": (40, 100), "chamber_squash": 1.15, "floor_flatten": 0.2,
        "stalactites": 0.2, "stalagmites": 0.2, "columns": 0.05, "rubble": 0.3,
        "detail_amp": 0.42, "detail_base": 30, "fine_amp": 0.3, "fine_base": 55,
        "scallop": 0.8, "water_bias": 0.25, "ceiling_lift": 0.2,
    },
    # Built, then fallen in: straight masonry corridors interrupted by collapse.
    "crypt": {
        "tunnel": "box", "tunnel_radius": 1.7, "radius_jitter": 0.22,
        "noise_amp": 0.95, "noise_base": 9, "noise_octaves": 4, "fillet": 1.1,
        "turn_deg": (0, 45), "chamber_squash": 0.75, "floor_flatten": 0.7,
        "stalactites": 0.1, "stalagmites": 0.05, "columns": 0.35, "rubble": 0.7,
        "detail_amp": 0.36, "detail_base": 36, "fine_amp": 0.24, "fine_base": 64,
        "scallop": 0.2, "water_bias": 0.3, "ceiling_lift": 0.0,
    },
    # Oroth work that never fell: vast, regular, cold, still standing.
    "builder": {
        "tunnel": "box", "tunnel_radius": 2.6, "radius_jitter": 0.05,
        "noise_amp": 0.22, "noise_base": 14, "noise_octaves": 3, "fillet": 0.5,
        "turn_deg": (0, 25), "chamber_squash": 0.7, "floor_flatten": 0.9,
        "stalactites": 0.0, "stalagmites": 0.0, "columns": 0.6, "rubble": 0.25,
        "detail_amp": 0.1, "detail_base": 50, "fine_amp": 0.07, "fine_base": 90,
        "scallop": 0.05, "water_bias": 0.35, "ceiling_lift": 0.0,
    },
    # Ice: smooth, translucent-looking, scalloped by melt, few formations.
    "ice": {
        "tunnel": "round", "tunnel_radius": 2.3, "radius_jitter": 0.3,
        "noise_amp": 0.85, "noise_base": 6, "noise_octaves": 4, "fillet": 3.0,
        "turn_deg": (25, 70), "chamber_squash": 1.05, "floor_flatten": 0.45,
        "stalactites": 0.6, "stalagmites": 0.3, "columns": 0.2, "rubble": 0.05,
        "detail_amp": 0.22, "detail_base": 32, "fine_amp": 0.14, "fine_base": 58,
        "scallop": 0.6, "water_bias": 0.15, "ceiling_lift": 0.15,
    },
}


# ---------------------------------------------------------------------------------------
# Layout: turn a list of authored beats into chambers placed in three dimensions.
# ---------------------------------------------------------------------------------------

def layout(recipe: dict, rng: np.random.Generator) -> tuple[dict, list]:
    """Place every beat in space. Authored `pos` wins; otherwise the walk decides.

    The walk turns by the formation's turn range at each step, descends by each beat's
    `drop`, and pushes chambers apart afterwards so unrelated rooms do not merge.
    """
    form = FORMATIONS[recipe.get("formed_by", "water")]
    beats = recipe["beats"]
    by_id = {b["id"]: b for b in beats}
    chambers: dict[str, dict] = {}
    heading = math.radians(float(recipe.get("start_heading_deg", 0.0)))
    cursor = np.array(recipe.get("start", [0.0, 0.0, 0.0]), dtype=np.float64)

    for i, beat in enumerate(beats):
        size = SIZES[beat.get("size", "medium")]
        radii = np.array(size, dtype=np.float64)
        radii[1] *= form["chamber_squash"]
        radii *= 1.0 + rng.uniform(-0.12, 0.12, 3)
        if "pos" in beat:
            pos = np.array(beat["pos"], dtype=np.float64)
        elif "branch_from" in beat:
            parent = chambers[beat["branch_from"]]
            ang = heading + math.radians(rng.uniform(60, 130) * rng.choice([-1.0, 1.0]))
            reach = parent["radii"][0] + radii[0] + rng.uniform(5.0, 12.0)
            pos = parent["pos"] + np.array([math.cos(ang) * reach, float(beat.get("drop", 0.0)), math.sin(ang) * reach])
        elif i == 0:
            pos = cursor.copy()
        else:
            prev = chambers[beats[i - 1]["id"]]
            lo, hi = form["turn_deg"]
            turn = math.radians(rng.uniform(lo, hi)) * rng.choice([-1.0, 1.0])
            heading += turn
            reach = prev["radii"][0] + radii[0] + rng.uniform(4.0, 11.0)
            drop = float(beat.get("drop", 0.0))
            pos = prev["pos"] + np.array([math.cos(heading) * reach, drop, math.sin(heading) * reach])
        chambers[beat["id"]] = {
            "id": beat["id"], "pos": pos, "radii": radii, "beat": beat,
            "role": beat.get("role", "chamber"),
        }

    # Relax: unrelated chambers should not overlap, or the place reads as one blob.
    links = [tuple(l) for l in recipe.get("links", [])]
    linked = {(a, b) for a, b in links} | {(b, a) for a, b in links}
    ids = list(chambers)
    pinned = {b["id"] for b in beats if "pos" in b}
    for _ in range(60):
        moved = 0.0
        for a in ids:
            for b in ids:
                if a >= b or (a, b) in linked:
                    continue
                ca, cb = chambers[a], chambers[b]
                delta = cb["pos"] - ca["pos"]
                dist = float(np.linalg.norm(delta)) or 1e-6
                want = float(ca["radii"].max() + cb["radii"].max()) * 1.25
                if dist < want:
                    push = (want - dist) * 0.5
                    step = delta / dist * push
                    if a not in pinned:
                        ca["pos"] -= step
                    if b not in pinned:
                        cb["pos"] += step
                    moved += push
        if moved < 0.05:
            break
    return chambers, links


# ---------------------------------------------------------------------------------------
# Field: build the signed-distance field for the open space.
# ---------------------------------------------------------------------------------------

def build_field(recipe: dict, chambers: dict, links: list, rng: np.random.Generator, voxel: float):
    form = FORMATIONS[recipe.get("formed_by", "water")]
    pts = np.array([c["pos"] for c in chambers.values()])
    rad = np.array([c["radii"] for c in chambers.values()])
    margin = float(rad.max()) + 8.0
    bmin = pts.min(axis=0) - margin
    bmax = pts.max(axis=0) + margin
    X, Y, Z, shape, origin = sdf.grid(bmin, bmax, voxel)
    voxels = int(np.prod(shape))
    if voxels > 42_000_000:
        raise SystemExit(f"grid too large ({shape}, {voxels/1e6:.1f}M voxels); raise --voxel")

    field = np.full(shape, 1e6, dtype=np.float32)
    fillet = form["fillet"]

    for c in chambers.values():
        blob = sdf.ellipsoid(X, Y, Z, c["pos"], c["radii"])
        field = sdf.smooth_union(field, blob, fillet)

    for a, b in links:
        ca, cb = chambers[a], chambers[b]
        base = form["tunnel_radius"] * (1.0 + rng.uniform(-form["radius_jitter"], form["radius_jitter"]))
        wide = float(max(ca["beat"].get("link_radius", 0.0), cb["beat"].get("link_radius", 0.0)))
        r = max(base, wide)
        # Tunnels bend: cut them as two segments through a displaced midpoint.
        mid = (ca["pos"] + cb["pos"]) * 0.5
        span = float(np.linalg.norm(cb["pos"] - ca["pos"]))
        bend = rng.normal(0.0, span * 0.10, 3)
        bend[1] *= 0.45
        mid = mid + bend
        for p, q in ((ca["pos"], mid), (mid, cb["pos"])):
            if form["tunnel"] == "box":
                seg = sdf.box_tunnel(X, Y, Z, p, q, r * 0.95, r * 1.25)
            else:
                seg = sdf.capsule(X, Y, Z, p, q, r * rng.uniform(0.85, 1.05), r * rng.uniform(0.9, 1.2))
            field = sdf.smooth_union(field, seg, fillet * 0.8)

    # Vertical shafts: light from above, and a way down.
    shafts = []
    for c in chambers.values():
        beat = c["beat"]
        if not beat.get("light_shaft"):
            continue
        top = float(bmax[1]) + 2.0
        head = c["pos"] + np.array([rng.uniform(-1.5, 1.5), 0.0, rng.uniform(-1.5, 1.5)])
        radius = float(beat.get("shaft_radius", 1.5))
        shaft = sdf.capsule(X, Y, Z, head, [head[0] + rng.uniform(-2, 2), top, head[2] + rng.uniform(-2, 2)], radius, radius * 1.6)
        field = sdf.smooth_union(field, shaft, fillet * 0.6)
        shafts.append({"pos": [float(head[0]), float(c["pos"][1]), float(head[2])], "radius": radius, "chamber": c["id"], "top": top})

    # Formations: stalactites, stalagmites, columns, and fallen rubble.
    detail_seed = rng.integers(0, 1 << 30)
    drng = np.random.default_rng(int(detail_seed))
    for c in chambers.values():
        r = c["radii"]
        area = float(r[0] * r[2])
        for kind, density, sign in (("stalactites", form["stalactites"], -1), ("stalagmites", form["stalagmites"], 1)):
            count = int(area * density * 0.05)
            for _ in range(count):
                ang = drng.uniform(0, math.tau)
                dist = math.sqrt(drng.uniform(0, 1)) * r[0] * 0.85
                x = c["pos"][0] + math.cos(ang) * dist
                z = c["pos"][2] + math.sin(ang) * dist
                y = c["pos"][1] + (r[1] * 0.92 if sign < 0 else -r[1] * 0.92)
                length = drng.uniform(0.6, 1.0) * r[1] * drng.uniform(0.35, 0.8)
                width = drng.uniform(0.15, 0.45) * (1.6 if sign > 0 else 1.0)
                spike = sdf.cone(X, Y, Z, (x, y, z), length * sign, width)
                field = np.minimum(field, -spike) if False else sdf.smooth_subtract(field, -spike, 0.25)
        if form["columns"] > 0 and drng.random() < form["columns"] and r[1] > 3.0:
            ang = drng.uniform(0, math.tau)
            dist = drng.uniform(0.3, 0.7) * r[0]
            cx = c["pos"][0] + math.cos(ang) * dist
            cz = c["pos"][2] + math.sin(ang) * dist
            col = sdf.capsule(X, Y, Z, (cx, c["pos"][1] - r[1], cz), (cx, c["pos"][1] + r[1], cz), drng.uniform(0.5, 1.1), drng.uniform(0.6, 1.3))
            field = sdf.smooth_subtract(field, col, 0.6)
        if form["rubble"] > 0:
            for _ in range(int(area * form["rubble"] * 0.03)):
                ang = drng.uniform(0, math.tau)
                dist = math.sqrt(drng.uniform(0, 1)) * r[0] * 0.9
                pos = (c["pos"][0] + math.cos(ang) * dist, c["pos"][1] - r[1] * drng.uniform(0.75, 0.98), c["pos"][2] + math.sin(ang) * dist)
                heap = sdf.sphere(X, Y, Z, pos, drng.uniform(0.5, 1.8))
                field = sdf.smooth_subtract(field, heap, 0.5)

    # Roughness in three bands, because a blend of primitives is not a cave wall.
    # Large: the overall wander of the rock face. Medium: broken relief you read as
    # blocks and bulges. Fine: the surface the light actually catches.
    field = field + sdf.fbm(shape, rng, octaves=form["noise_octaves"], base=form["noise_base"], gain=0.55) * form["noise_amp"]
    field = field + sdf.fbm(shape, rng, octaves=2, base=form["detail_base"], gain=0.6) * form["detail_amp"]
    field = field + sdf.fbm(shape, rng, octaves=1, base=form["fine_base"]) * form["fine_amp"]
    if form["scallop"] > 0:
        # Scalloping: shallow scoops, directional, the mark of the thing that dug here.
        scoops = sdf.fbm(shape, rng, octaves=2, base=int(form["detail_base"] * 0.7), gain=0.5)
        field = field + np.abs(scoops) * form["scallop"] * 0.30

    # Floors: flatten the bottom of the open space so it is walkable.
    flat = form["floor_flatten"]
    if flat > 0:
        for c in chambers.values():
            floor_y = c["pos"][1] - c["radii"][1] * 0.92
            near = (np.abs(X - c["pos"][0]) < c["radii"][0] * 1.4) & (np.abs(Z - c["pos"][2]) < c["radii"][2] * 1.4)
            below = near & (Y < floor_y)
            if not below.any():
                continue
            field = np.where(below, np.maximum(field, (floor_y - Y) * 1.0), field)
        # Tunnels get a floor too, or the player walks a pipe.
        for a, b in links:
            ca, cb = chambers[a], chambers[b]
            lo = min(ca["pos"][1] - ca["radii"][1] * 0.9, cb["pos"][1] - cb["radii"][1] * 0.9)
            hi = max(ca["pos"][1] - ca["radii"][1] * 0.9, cb["pos"][1] - cb["radii"][1] * 0.9)
            if hi - lo > 6.0:
                continue  # a real drop; leave it as a drop
            seg_lo = min(ca["pos"][0], cb["pos"][0]) - 4, min(ca["pos"][2], cb["pos"][2]) - 4
            seg_hi = max(ca["pos"][0], cb["pos"][0]) + 4, max(ca["pos"][2], cb["pos"][2]) + 4
            box = (X > seg_lo[0]) & (X < seg_hi[0]) & (Z > seg_lo[1]) & (Z < seg_hi[1]) & (Y < lo - 0.6)
            if box.any():
                field = np.where(box, np.maximum(field, (lo - 0.6 - Y) * 1.0), field)

    # Seal the volume: no holes out of the world except the shafts we cut on purpose.
    field[0, :, :] = np.maximum(field[0, :, :], 1.0)
    field[-1, :, :] = np.maximum(field[-1, :, :], 1.0)
    field[:, 0, :] = np.maximum(field[:, 0, :], 1.0)
    field[:, :, 0] = np.maximum(field[:, :, 0], 1.0)
    field[:, :, -1] = np.maximum(field[:, :, -1], 1.0)
    for s in shafts:
        i = int((s["pos"][0] - origin[0]) / voxel)
        k = int((s["pos"][2] - origin[2]) / voxel)
        rad_v = int(s["radius"] * 2.0 / voxel) + 1
        i0, i1 = max(i - rad_v, 0), min(i + rad_v, shape[0])
        k0, k1 = max(k - rad_v, 0), min(k + rad_v, shape[2])
        field[i0:i1, -1, k0:k1] = -1.0
    return field, origin, shape, shafts


# ---------------------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------------------

def to_mesh(field: np.ndarray, origin: np.ndarray, voxel: float, recipe: dict) -> trimesh.Trimesh:
    verts, faces, _normals, _ = measure.marching_cubes(field, level=0.0, spacing=(voxel, voxel, voxel))
    verts = verts + origin
    # Faces should look into the open space, not out into the rock.
    faces = faces[:, ::-1]
    mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
    parts = mesh.split(only_watertight=False)
    if len(parts) > 1:
        parts = sorted(parts, key=lambda m: len(m.faces), reverse=True)
        keep = [p for p in parts if len(p.faces) > len(parts[0].faces) * 0.02]
        mesh = trimesh.util.concatenate(keep)
    trimesh.smoothing.filter_taubin(mesh, lamb=0.5, nu=-0.53, iterations=int(recipe.get("smoothing", 2)))
    return mesh


def cavity_shade(mesh: trimesh.Trimesh, field: np.ndarray, origin: np.ndarray, voxel: float, palette: list[str]) -> np.ndarray:
    """Vertex colours: RGB is the stone's own colour, ALPHA carries baked cavity occlusion.

    Keeping occlusion out of the RGB lets the shader decide how hard to apply it, so a
    tight crawl reads dark without crushing the whole cave to black.
    """
    air = (field < 0).astype(np.float32)
    openness = ndimage.uniform_filter(air, size=9, mode="constant", cval=0.0)
    wide = ndimage.uniform_filter(air, size=25, mode="constant", cval=0.0)
    idx = np.clip(((mesh.vertices - origin) / voxel).astype(int), 0, np.array(field.shape) - 1)
    near = openness[idx[:, 0], idx[:, 1], idx[:, 2]]
    far = wide[idx[:, 0], idx[:, 1], idx[:, 2]]
    ao = np.clip(0.42 + 0.72 * near + 0.5 * far, 0.30, 1.0)

    # Stone colour varies with height: silt and damp low down, bare rock at the ceiling,
    # plus a slow large-scale mottle so a wall is never one flat colour.
    y = mesh.vertices[:, 1]
    y_norm = (y - y.min()) / max(float(y.max() - y.min()), 1e-6)
    floor_c = np.array(hex_rgb(palette[1] if len(palette) > 1 else "#4a4239"), dtype=np.float32)
    mid_c = np.array(hex_rgb(palette[0] if palette else "#7b7368"), dtype=np.float32)
    roof_c = np.array(hex_rgb(palette[2] if len(palette) > 2 else "#9a9186"), dtype=np.float32)
    low = np.clip(y_norm * 2.0, 0.0, 1.0)[:, None]
    high = np.clip((y_norm - 0.5) * 2.0, 0.0, 1.0)[:, None]
    col = floor_c[None, :] * (1.0 - low) + mid_c[None, :] * low
    col = col * (1.0 - high) + roof_c[None, :] * high

    # Patchy discolouration sampled from the field itself, so stains follow the rock
    # rather than floating over it in smooth waves.
    stain = ndimage.uniform_filter(np.abs(field), size=5, mode="nearest")
    st = stain[idx[:, 0], idx[:, 1], idx[:, 2]]
    st = (st - st.min()) / max(float(st.max() - st.min()), 1e-6)
    col = col * (0.88 + st[:, None] * 0.34)
    col = np.clip(col, 0.0, 1.0)

    rgba = np.concatenate([col, ao[:, None]], axis=1)
    return (rgba * 255).astype(np.uint8)


def hex_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ---------------------------------------------------------------------------------------
# Anchors: where the floor is, where things can stand, where the water sits.
# ---------------------------------------------------------------------------------------


def decimate_keeping_colour(mesh: trimesh.Trimesh, target: int) -> trimesh.Trimesh:
    """Quadric decimation that carries vertex colour across by nearest-vertex lookup."""
    colours = None
    if hasattr(mesh.visual, "vertex_colors") and mesh.visual.vertex_colors is not None:
        colours = np.asarray(mesh.visual.vertex_colors).copy()
    out = mesh.simplify_quadric_decimation(face_count=target)
    if colours is not None and len(out.vertices):
        tree = __import__("scipy.spatial", fromlist=["cKDTree"]).cKDTree(mesh.vertices)
        _, idx = tree.query(out.vertices, k=1)
        out.visual.vertex_colors = colours[idx]
    return out


def split_by_chamber(mesh: trimesh.Trimesh, chambers: dict) -> dict:
    """Assign each face to its nearest chamber so each room is its own drawable chunk."""
    ids = list(chambers)
    if len(ids) < 2:
        return {ids[0] if ids else "shell": mesh}
    centres = np.array([chambers[i]["pos"] for i in ids])
    centroids = mesh.vertices[mesh.faces].mean(axis=1)
    tree = __import__("scipy.spatial", fromlist=["cKDTree"]).cKDTree(centres)
    _, owner = tree.query(centroids, k=1)
    colours = np.asarray(mesh.visual.vertex_colors) if hasattr(mesh.visual, "vertex_colors") else None
    out = {}
    for j, cid in enumerate(ids):
        sel = owner == j
        if not sel.any():
            continue
        faces = mesh.faces[sel]
        used = np.unique(faces)
        remap = np.full(len(mesh.vertices), -1, dtype=np.int64)
        remap[used] = np.arange(len(used))
        part = trimesh.Trimesh(vertices=mesh.vertices[used], faces=remap[faces], process=False)
        if colours is not None:
            part.visual.vertex_colors = colours[used]
        out[cid] = part
    return out


def find_anchors(field: np.ndarray, origin: np.ndarray, voxel: float, chambers: dict, rng: np.random.Generator) -> dict:
    air = field < 0
    shape = field.shape
    out = {}
    for c in chambers.values():
        cx = int((c["pos"][0] - origin[0]) / voxel)
        cz = int((c["pos"][2] - origin[2]) / voxel)
        rx = max(int(c["radii"][0] / voxel), 2)
        rz = max(int(c["radii"][2] / voxel), 2)
        i0, i1 = max(cx - rx, 0), min(cx + rx, shape[0])
        k0, k1 = max(cz - rz, 0), min(cz + rz, shape[2])
        floors = []
        step = max(1, int(1.1 / voxel))
        for i in range(i0, i1, step):
            for k in range(k0, k1, step):
                column = air[i, :, k]
                if not column.any():
                    continue
                j = int(np.argmax(column))  # lowest air voxel in this column
                headroom = int(np.sum(column[j:j + int(2.2 / voxel)]))
                if headroom < int(1.9 / voxel):
                    continue
                floors.append((
                    float(origin[0] + i * voxel), float(origin[1] + j * voxel), float(origin[2] + k * voxel)))
        if not floors:
            continue
        arr = np.array(floors)
        lowest = float(arr[:, 1].min())
        out[c["id"]] = {
            "floor_points": [[round(v, 2) for v in p] for p in arr[rng.permutation(len(arr))[:60]].tolist()],
            "floor_y": round(lowest, 2),
            "centre": [round(float(c["pos"][0]), 2), round(lowest, 2), round(float(c["pos"][2]), 2)],
            "radii": [round(float(v), 2) for v in c["radii"]],
            "role": c["role"],
            "area": round(float(len(floors)) * (step * voxel) ** 2, 1),
        }
    return out


def build(recipe: dict, out_root: str, voxel_override: float | None = None, quiet: bool = False) -> dict:
    t0 = time.time()
    name = recipe["name_slug"]
    seed = int(recipe.get("seed", 1))
    rng = np.random.default_rng(seed)
    voxel = float(voxel_override or recipe.get("voxel", 0.45))

    chambers, links = layout(recipe, rng)
    field, origin, shape, shafts = build_field(recipe, chambers, links, rng, voxel)
    mesh = to_mesh(field, origin, voxel, recipe)
    palette = recipe.get("palette", [])
    mesh.visual.vertex_colors = cavity_shade(mesh, field, origin, voxel, palette)
    anchors = find_anchors(field, origin, voxel, chambers, rng)

    # Water sits at the lowest floor of any chamber marked wet.
    water = []
    for c in chambers.values():
        depth = float(c["beat"].get("water", 0.0))
        if depth <= 0.0 or c["id"] not in anchors:
            continue
        water.append({
            "chamber": c["id"],
            "level": round(anchors[c["id"]]["floor_y"] + depth, 2),
            "centre": anchors[c["id"]]["centre"],
            "extent": [round(float(c["radii"][0]) * 1.2, 2), round(float(c["radii"][2]) * 1.2, 2)],
        })

    folder = os.path.join(out_root, name)
    os.makedirs(folder, exist_ok=True)

    # Budget: a dungeon shell is one surface, so without chunking nothing can be culled.
    # Decimate to a sane wall density, then split by nearest chamber so the renderer can
    # throw away the rooms you are not standing in.
    # Decimation flattens rock into planes, so the budget is generous: chunking is what
    # buys the performance, and a cap only stops a runaway.
    # The budget is for the whole shell, not per chamber: standing in one chamber you see
    # through the openings into several others, so a ten-chamber dungeon is not allowed
    # ten chambers' worth of triangles in view. Measured by tools_gd/perf_probe.
    target = int(recipe.get("target_tris", 0)) or min(len(mesh.faces),
        max(200_000, 40_000 * max(len(chambers), 1)), 360_000)
    if len(mesh.faces) > target * 1.15:
        mesh = decimate_keeping_colour(mesh, target)
    chunks = split_by_chamber(mesh, chambers)
    scene = trimesh.Scene()
    for chamber_id, part in chunks.items():
        scene.add_geometry(part, node_name=f"shell_{chamber_id}", geom_name=f"shell_{chamber_id}")
    scene.export(os.path.join(folder, f"{name}.glb"))

    col_target = max(int(len(mesh.faces) * 0.22), 3000)
    collision = decimate_keeping_colour(mesh, col_target) if len(mesh.faces) > col_target * 1.2 else mesh
    collision.export(os.path.join(folder, f"{name}_col.glb"))

    entrance = next((c for c in chambers.values() if c["role"] == "entrance"), next(iter(chambers.values())))
    meta = {
        "id": recipe["id"],
        "name": recipe.get("name", name),
        "generator": "cave_forge",
        "version": 1,
        "seed": seed,
        "voxel": voxel,
        "formed_by": recipe.get("formed_by"),
        "formed_by_story": recipe.get("formed_by_story", ""),
        "story": recipe.get("story", ""),
        "who_was_here": recipe.get("who_was_here", ""),
        "unique_object": recipe.get("unique_object", ""),
        "bounds": [[round(float(v), 2) for v in origin], [round(float(origin[i] + (shape[i] - 1) * voxel), 2) for i in range(3)]],
        "tris": int(len(mesh.faces)),
        "collision_tris": int(len(collision.faces)),
        "chunks": {k: int(len(v.faces)) for k, v in chunks.items()},
        "entrance": anchors.get(entrance["id"], {}).get("centre", [0, 0, 0]),
        "chambers": anchors,
        "links": [list(l) for l in links],
        "light_shafts": shafts,
        "water": water,
        "shortcut": recipe.get("shortcut"),
        "beats": [{k: v for k, v in b.items() if k != "pos"} for b in recipe["beats"]],
        "features": recipe.get("features", []),
        "encounters": recipe.get("encounters", []),
        "palette": palette,
        "ambience": recipe.get("ambience", []),
    }
    with open(os.path.join(folder, f"{name}.meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    if not quiet:
        biggest = max(chunks.values(), key=lambda m: len(m.faces))
        print(f"{name}: {len(mesh.faces):,} tris in {len(chunks)} chunks "
              f"(largest {len(biggest.faces):,}), {len(collision.faces):,} collision, "
              f"{len(anchors)} chambers, {len(shafts)} shafts, {len(water)} water, "
              f"grid {shape}, {time.time() - t0:.1f}s")
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("recipes", nargs="+")
    ap.add_argument("--out", default="game/assets/models/dungeon")
    ap.add_argument("--voxel", type=float, default=None)
    args = ap.parse_args()
    for path in args.recipes:
        recipe = json.load(open(path))
        recipe.setdefault("name_slug", os.path.splitext(os.path.basename(path))[0])
        build(recipe, args.out, args.voxel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
