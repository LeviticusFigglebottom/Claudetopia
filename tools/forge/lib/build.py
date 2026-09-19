"""Small construction helpers shared by the prop, architecture and landmark generators.

These are the pieces hand-made objects are actually made of: boards with chamfers, turned
legs, forged straps and hinges, woven panels, tapered staves. Keeping them here means a
chair and a cart use the same joinery, which is what makes a set look made by one culture.
"""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Euler, Vector

from . import scene as S

TAU = math.tau


def board(name, length, width, thickness, mat=None, location=(0, 0, 0), rotation=None,
          chamfer=0.006, sag=0.0, rng=None, warp=0.0):
    """A sawn board lying along X, centred on its own middle, with chamfered arrises.

    `sag` bows it downward (an old shelf), `warp` twists it slightly: both are what stop a
    row of boards reading as extruded rectangles."""
    ob = S.box_centered(name, size=(length, width, thickness), location=location, rotation=rotation, mat=mat)
    if sag or warp:
        for v in ob.data.vertices:
            t = v.co.x / max(1e-6, length * 0.5)
            v.co.z -= sag * (1.0 - t * t)
            v.co.z += warp * t * (v.co.y / max(1e-6, width * 0.5))
    if chamfer > 0:
        S.bevel(ob, width=chamfer, segments=2, angle_deg=40)
    if rng is not None:
        S.jitter_verts(ob, amount=thickness * 0.06, scale=length * 0.6, seed=rng.randrange(999))
    return ob


def plank_run(name, count, length, width, thickness, gap=0.004, mat=None, rng=None, sag=0.0,
              axis="Y", origin=(0, 0, 0)):
    """A row of boards side by side: a table top, a door, a boardwalk, a cart bed."""
    rng = rng or random.Random(0)
    parts = []
    span = count * width + (count - 1) * gap
    for i in range(count):
        off = -span * 0.5 + width * 0.5 + i * (width + gap)
        loc = Vector(origin)
        if axis == "Y":
            loc.y += off
        else:
            loc.x += off
        b = board("%s_%d" % (name, i), length, width * rng.uniform(0.93, 1.03), thickness, mat=mat,
                  location=loc, sag=sag * rng.uniform(0.5, 1.0), rng=rng,
                  warp=thickness * rng.uniform(-0.25, 0.25))
        if axis != "Y":
            b.rotation_euler = Euler((0, 0, math.pi / 2))
            S.apply_transforms(b)
            b.location = loc
            S.apply_transforms(b)
        parts.append(b)
    return parts


def turned_leg(name, height, top_r, mat=None, location=(0, 0, 0), rings=3, taper=0.62, rng=None,
               segments=12):
    """A lathe-turned leg with collars: the difference between a chair and four sticks."""
    rng = rng or random.Random(0)
    prof = [(top_r * 1.05, 0.0), (top_r * 1.12, height * 0.03), (top_r * 0.88, height * 0.07)]
    for i in range(rings):
        z = height * (0.18 + 0.62 * i / max(1, rings - 1))
        r = top_r * (1.0 - (1.0 - taper) * (z / height)) * rng.uniform(0.94, 1.02)
        prof.append((r * 0.82, z - height * 0.025))
        prof.append((r * 1.14, z))
        prof.append((r * 0.86, z + height * 0.025))
    prof.append((top_r * taper, height * 0.9))
    prof.append((top_r * 1.02, height * 0.97))
    prof.append((top_r * 0.95, height))
    ob = S.lathe(name, prof, segments=segments, mat=mat, close=True)
    ob.location = Vector(location)
    S.apply_transforms(ob)
    return ob


def tapered_post(name, height, r_base, r_top, mat=None, location=(0, 0, 0), sides=8, lean=0.0,
                 rng=None):
    ob = S.cylinder(name, radius=r_base, radius_top=r_top, depth=height, vertices=sides,
                    location=location, mat=mat)
    if lean and rng is not None:
        ob.rotation_euler = Euler((math.radians(rng.uniform(-lean, lean)),
                                   math.radians(rng.uniform(-lean, lean)), 0))
        S.apply_transforms(ob)
    return ob


def iron_strap(name, length, width, thickness, mat=None, location=(0, 0, 0), rotation=None,
               bend_r=0.0, rng=None):
    """A forged strap: a flat bar with rounded ends and a couple of rivet bumps."""
    ob = S.box_centered(name, size=(length, width, thickness), location=(0, 0, 0), mat=mat)
    S.bevel(ob, width=min(width, thickness) * 0.35, segments=2, angle_deg=50)
    parts = [ob]
    n = max(2, int(length / max(0.06, width * 2.5)))
    for i in range(n):
        x = -length * 0.5 + length * (i + 0.5) / n
        rivet = S.sphere("%s_rivet_%d" % (name, i), radius=thickness * 1.15, subdivisions=2,
                         location=(x, 0, thickness * 0.5), mat=mat, scale=(1, 1, 0.55))
        S.apply_transforms(rivet)
        parts.append(rivet)
    joined = S.join(parts, name)
    if rotation is not None:
        joined.rotation_euler = Euler([math.radians(a) for a in rotation], "XYZ")
    joined.location = Vector(location)
    S.apply_transforms(joined)
    return joined


def hoop(name, radius, minor, mat=None, location=(0, 0, 0), segments=28, flatten=2.0, rotation=None):
    ob = S.torus(name, major=radius, minor=minor, seg_major=segments, seg_minor=6,
                 location=location, rotation=rotation, mat=mat)
    ob.scale = (1, 1, flatten)
    S.apply_transforms(ob)
    return ob


def wattle_panel(name, width, height, mat=None, uprights=7, weaves=9, rod_r=0.016, rng=None,
                 location=(0, 0, 0)):
    """Woven hazel: uprights with horizontal rods threading front and back of each.

    Hearthvale's fences and Sedgemire's screens are the same weave in different woods."""
    rng = rng or random.Random(0)
    parts = []
    for i in range(uprights):
        x = -width * 0.5 + width * (i + 0.5) / uprights
        p = S.cylinder("%s_up_%d" % (name, i), radius=rod_r * rng.uniform(0.9, 1.15),
                       radius_top=rod_r * 0.8, depth=height * rng.uniform(0.98, 1.06),
                       vertices=7, location=(x, 0, 0), mat=mat)
        S.tilt(p, rng, max_deg=1.6)
        p.location = Vector((x, rng.uniform(-1, 1) * rod_r * 0.3, 0))
        S.apply_transforms(p)
        parts.append(p)
    depth = rod_r * 1.5
    for j in range(weaves):
        z = height * (j + 0.5) / weaves
        pts = []
        steps = uprights * 3
        for k in range(steps + 1):
            t = k / steps
            x = -width * 0.55 + width * 1.1 * t
            y = math.sin(t * math.pi * uprights + (j % 2) * math.pi) * depth
            pts.append((x, y, z + rng.uniform(-1, 1) * rod_r * 0.25))
        rod = S.tube_along("%s_w_%d" % (name, j), pts, radius=rod_r * rng.uniform(0.7, 0.95),
                           segments=6, mat=mat)
        parts.append(rod)
    for p in parts:
        p.location += Vector(location)
        S.apply_transforms(p)
    return parts


def rope_loop(name, radius, thickness, mat=None, location=(0, 0, 0), turns=1, segments=28,
              sag=0.0, rng=None):
    pts = []
    n = segments * max(1, turns)
    for i in range(n + 1):
        t = i / n
        a = TAU * turns * t
        r = radius * (1.0 + 0.02 * math.sin(a * 3))
        z = sag * math.sin(math.pi * t)
        pts.append((math.cos(a) * r, math.sin(a) * r, z))
    return S.tube_along(name, pts, radius=thickness, segments=6, mat=mat, cap=True)


def catenary(p0, p1, sag, steps=14):
    """Points along a hanging line between two anchors: ropes, chains, banners' tops."""
    a, b = Vector(p0), Vector(p1)
    pts = []
    for i in range(steps + 1):
        t = i / steps
        p = a.lerp(b, t)
        p.z -= sag * math.sin(math.pi * t)
        pts.append(p)
    return pts


def cloth_sheet(name, width, height, mat=None, location=(0, 0, 0), rotation=None, segments=(10, 12),
                fold=0.02, sag=0.03, rng=None, hang=True):
    """A hanging cloth: a subdivided plane with vertical folds and a sagging hem."""
    rng = rng or random.Random(0)
    sx, sy = segments
    bm = bmesh.new()
    verts = []
    for j in range(sy + 1):
        row = []
        for i in range(sx + 1):
            u = i / sx
            v = j / sy
            x = (u - 0.5) * width
            z = -v * height if hang else (v - 0.5) * height
            y = math.sin(u * math.pi * 3.0 + rng.random() * 0.2) * fold * (0.35 + 0.65 * v)
            z += sag * math.sin(u * math.pi) * v
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for j in range(sy):
        for i in range(sx):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = S.bm_to_object(bm, name, mat, smooth=True)
    S.solidify(ob, thickness=max(0.004, width * 0.004), offset=0.0)
    if rotation is not None:
        ob.rotation_euler = Euler([math.radians(a) for a in rotation], "XYZ")
    ob.location = Vector(location)
    S.apply_transforms(ob)
    return ob


def stone_course(name, length, height, depth, mat=None, rows=4, rng=None, location=(0, 0, 0),
                 irregular=0.22, batter=0.06):
    """A drystone wall run: individual stones, each its own block, leaning inward.

    Every stone is a separate box with its own jitter, which is why the wall reads as
    stacked rather than extruded."""
    rng = rng or random.Random(0)
    parts = []
    row_h = height / rows
    for r in range(rows):
        z = row_h * (r + 0.5)
        inset = batter * height * (r / max(1, rows - 1))
        x = -length * 0.5
        offset = rng.uniform(0, 0.5)
        while x < length * 0.5 - 1e-3:
            w = row_h * rng.uniform(1.0, 2.1) * (1.0 + irregular * rng.uniform(-1, 1))
            w = min(w, length * 0.5 - x)
            if w < row_h * 0.35:
                break
            d = (depth - inset * 2) * rng.uniform(0.86, 1.0)
            h = row_h * rng.uniform(0.82, 1.0)
            b = S.box_centered("%s_%d_%d" % (name, r, len(parts)), size=(w * 0.96, d, h),
                               location=(x + w * 0.5, rng.uniform(-1, 1) * depth * 0.04, z),
                               rotation=(rng.uniform(-3, 3), rng.uniform(-2, 2), rng.uniform(-4, 4)),
                               mat=mat)
            S.bevel(b, width=min(w, h) * 0.09, segments=2, angle_deg=40)
            S.jitter_verts(b, amount=min(w, h) * 0.05, scale=w * 0.8, seed=rng.randrange(999))
            parts.append(b)
            x += w + rng.uniform(0.0, row_h * 0.06)
        _ = offset
    # coping stones set on edge along the top
    x = -length * 0.5
    while x < length * 0.5 - 1e-3:
        w = row_h * rng.uniform(0.5, 0.85)
        w = min(w, length * 0.5 - x)
        if w < row_h * 0.2:
            break
        b = S.box_centered("%s_cope_%d" % (name, len(parts)), size=(w * 0.95, depth * 0.72, row_h * 1.25),
                           location=(x + w * 0.5, 0, height + row_h * 0.55),
                           rotation=(rng.uniform(-8, 8), rng.uniform(-4, 4), rng.uniform(-6, 6)), mat=mat)
        S.bevel(b, width=w * 0.1, segments=2, angle_deg=40)
        S.jitter_verts(b, amount=w * 0.06, scale=w, seed=rng.randrange(999))
        parts.append(b)
        x += w
    for p in parts:
        p.location += Vector(location)
        S.apply_transforms(p)
    return parts


def thatch_mass(name, width, length, height, mat=None, rng=None, location=(0, 0, 0), courses=6,
                overhang=0.12):
    """A thatched roof mass: overlapping courses with a rounded ridge and a ragged eave."""
    rng = rng or random.Random(0)
    parts = []
    for c in range(courses):
        f = c / max(1, courses - 1)
        z = height * f
        w = width * (1.0 - 0.92 * f) + overhang
        seg = S.box_centered("%s_%d" % (name, c), size=(w, length, height / courses * 1.6),
                             location=(0, 0, z), mat=mat)
        S.bevel(seg, width=height / courses * 0.3, segments=3, angle_deg=50)
        S.jitter_verts(seg, amount=height * 0.012, scale=length * 0.3, seed=rng.randrange(999))
        parts.append(seg)
    for p in parts:
        p.location += Vector(location)
        S.apply_transforms(p)
    return parts
