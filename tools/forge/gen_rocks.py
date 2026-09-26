"""Rocks: boulders, cliff slabs, scree, standing stones and Skerrow's giant bones.

    blender -b --python tools/forge/gen_rocks.py -- --kind boulder --palette skerrow --seed 2 --variant b

Rock silhouette comes from a displacement stack: sharp Voronoi facets first (so the stone
has planes and edges, not lumps), then a mid-scale musgrave for mass, then a fine cloud
for grain. Facets are kept by flat shading below the auto-smooth angle; weight comes from
a wide base and a slight downward bias.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib.runner import run_generator  # noqa: E402

# Which stone a region is made of (WORLD_BIBLE §6 geology).
REGION_STONE = {
    "hearthvale": "chalk_rock", "brightwater": "granite", "sedgemire": "granite",
    "briarwold": "granite", "skerrow": "limestone", "cinderlea": "fused_stone", "neutral": "granite",
}


def stone_material(pal, params, rng, kind_default=None, **kw):
    name = params.get("stone") or kind_default or REGION_STONE.get(pal.short, "granite")
    kw.setdefault("wear", 0.35 + 0.4 * rng.random())
    kw.setdefault("age", 0.4 + 0.5 * rng.random())
    return M.by_name(name, pal, **kw), name


def _displace_stack(obj, rng, facet=0.38, mass=0.2, grain=0.06, facet_scale=0.9, mass_scale=0.35,
                    grain_scale=0.12, seed=0):
    """Sharp facets, then mass, then grain. Voronoi first is what gives a rock planes."""
    t1 = S.new_texture("facet_%d" % seed, "VORONOI", noise_scale=facet_scale, noise_intensity=1.0)
    t1.distance_metric = "DISTANCE"
    t1.color_mode = "INTENSITY"
    t2 = S.new_texture("mass_%d" % seed, "MUSGRAVE", noise_scale=mass_scale, noise_intensity=0.7)
    t2.musgrave_type = "FBM"
    t2.octaves = 3
    t3 = S.new_texture("grain_%d" % seed, "CLOUDS", noise_scale=grain_scale, noise_depth=2)
    for nm, tex, strength in (("d1", t1, facet), ("d2", t2, mass), ("d3", t3, grain)):
        if strength <= 0.0:
            continue
        m = S.add_modifier(obj, "DISPLACE", nm, texture=tex, strength=strength, mid_level=0.5,
                           direction="NORMAL", texture_coords="LOCAL")
        S.apply_modifier(obj, m)


def _rock_body(name, rng, radius=1.0, subdiv=4, squash=(1.0, 1.0, 0.72), facet=0.38, mass=0.2,
               grain=0.06, mat=None, seed=0, flatten_base=True, budget=1400):
    ob = S.sphere(name, radius=radius, subdivisions=subdiv, mat=mat, smooth=True)
    ob.scale = Vector(squash)
    S.apply_transforms(ob)
    # seed the noise by moving the object through the texture field, then moving back
    off = Vector((seed * 3.1 % 17.0, seed * 7.7 % 13.0, seed * 2.3 % 11.0))
    ob.location += off
    S.apply_transforms(ob, location=True, rotation=False, scale=False)
    # Mass and grain only. Displacing along the normal by a Voronoi distance field pushes a
    # spike out of the middle of every cell, which gives popcorn, not stone; the planes a
    # rock breaks along are cut below instead, by dissolving the surface into facets.
    # Blender's legacy textures take a feature SIZE, not a frequency: the old scales
    # divided by the radius, so a bigger rock got finer noise and the "mass" layer was
    # actually grain. Mass has to be a good fraction of the rock to be mass.
    _displace_stack(ob, rng, 0.0, mass * radius * 1.6, grain * radius,
                    mass_scale=0.62 * radius, grain_scale=0.13 * radius, seed=seed)
    ob.location -= off
    S.apply_transforms(ob, location=True, rotation=False, scale=False)
    if flatten_base:
        # push the lowest vertices up onto a plane so the rock sits, and does not float
        lo, hi = S.bounds([ob])
        cut = lo.z + (hi.z - lo.z) * 0.12
        for v in ob.data.vertices:
            if v.co.z < cut:
                v.co.z = cut + (v.co.z - cut) * 0.18
    tris = S.tri_count(ob)
    if tris > budget:
        S.decimate(ob, budget / float(tris))
    if facet > 0.0:
        # Facets: merge near-coplanar faces into single planes with straight edges. A wider
        # angle breaks the rock into fewer, larger planes, which is the difference between
        # a pebble and a quarried block.
        S.decimate(ob, 1.0, planar_deg=4.0 + 13.0 * min(1.0, facet * 2.2))
        S.jitter_verts(ob, amount=radius * grain * 0.25, scale=1.6 * radius, seed=seed + 7)
    # A low auto-smooth angle keeps the facet edges hard while the relief inside a plane
    # still reads as one surface.
    S.shade_smooth(ob, 18.0)
    return ob


# --- kinds --------------------------------------------------------------------------------

def boulder(pal, rng, params, variant):
    mat, stone = stone_material(pal, params, rng)
    r = params.get("radius", rng.uniform(0.9, 1.9))
    ob = _rock_body("boulder", rng, radius=r, subdiv=5,
                    squash=(1.0, rng.uniform(0.75, 1.0), rng.uniform(0.6, 0.85)),
                    facet=rng.uniform(0.3, 0.45), mass=rng.uniform(0.14, 0.26), grain=0.05,
                    mat=mat, seed=rng.randrange(9999), budget=2200)
    S.tilt(ob, rng, max_deg=6.0)
    S.drop_to_ground([ob])
    parts = [ob]
    # a couple of split-off chips resting against the base
    for i in range(rng.randint(1, 3)):
        c = _rock_body("chip_%d" % i, rng, radius=r * rng.uniform(0.14, 0.3), subdiv=3,
                       squash=(1.0, rng.uniform(0.6, 0.9), rng.uniform(0.4, 0.7)),
                       facet=0.42, mass=0.18, grain=0.05, mat=mat, seed=rng.randrange(9999), budget=260)
        a = rng.uniform(0, math.tau)
        c.location = Vector((math.cos(a) * r * rng.uniform(0.85, 1.15), math.sin(a) * r * rng.uniform(0.85, 1.15), 0.0))
        S.tilt(c, rng, max_deg=25.0)
        S.apply_transforms(c)
        parts.append(c)
    S.drop_to_ground(parts)
    # A displaced blob unwraps far better as a sphere than as a thousand face islands.
    return {"opaque_objs": parts, "collision": "convex", "materials_used": [stone],
            "unwrap_mode": "sphere"}


def cliff_slab(pal, rng, params, variant):
    """A modular slab that tiles side by side into a cliff face or a quarry wall."""
    mat, stone = stone_material(pal, params, rng)
    w = params.get("width", 4.0)
    h = params.get("height", 6.0)
    d = params.get("depth", 2.2)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = S.bm_to_object(bm, "slab", mat, smooth=True)
    ob.scale = Vector((w, d, h))
    S.apply_transforms(ob)
    for v in ob.data.vertices:
        v.co.z += h * 0.5
    S.subdivide(ob, levels=4, simple=True)
    # Displace only the front face and the top: the sides and back stay flat so slabs tile.
    vg = ob.vertex_groups.new(name="front")
    weights = {}
    for v in ob.data.vertices:
        edge_x = 1.0 - min(1.0, abs(v.co.x) / (w * 0.5) * 1.12)
        front = max(0.0, -v.co.y / (d * 0.5))
        top = max(0.0, (v.co.z - h * 0.6) / (h * 0.4))
        w8 = max(0.0, min(1.0, max(front, top) * edge_x))
        weights[v.index] = w8
        vg.add([v.index], w8, "REPLACE")

    # A cliff face is bedded, then jointed: horizontal ledges where the beds part, cut by
    # near-vertical joints into blocks that stand proud or have fallen away. That is a
    # structure with a horizon in it, and no noise texture has one -- displacing a Voronoi
    # field along the normal gave cells radiating every way, which is why these slabs read
    # as shattered glass rather than as stone. Blender's legacy wood texture only bands
    # along X, so the beds are built directly from the vertex height instead, which is
    # exact and needs no coordinate gymnastics.
    beds = rng.randint(7, 11)
    bed_phase = rng.uniform(0.0, 1.0)
    blocks = rng.randint(4, 7)
    for v in ob.data.vertices:
        w8 = weights.get(v.index, 0.0)
        if w8 <= 0.0:
            continue
        t = v.co.z / max(h, 1e-6)
        course = t * beds + bed_phase
        row = math.floor(course)
        # Each bed steps out from the one above: a sawtooth, eased so the ledge has a lip.
        # Beds are not all the same thickness, and a face where they are reads as shelving.
        thick = 0.55 + 0.55 * ((((row * 2179) % 53) / 53.0))
        ledge = (((course - row) ** thick) - 0.5)
        # Blocks along the bed, offset course by course so the joints never line up. A
        # cheap integer hash keeps it deterministic without another random stream.
        col = math.floor((v.co.x / max(w, 1e-6) + 0.5) * blocks + row * 0.37)
        jog = (((col * 1367 + row * 911) % 97) / 97.0) - 0.5
        v.co.y -= w8 * (ledge * w * 0.11 + jog * w * 0.15)
    seed = rng.randrange(9999)
    # A cliff face is bedded, then jointed: horizontal ledges where the beds part, cut by
    # vertical joints into blocks that stand out or fall away. A Voronoi field displaced
    # along the normal gives none of that -- it gives shattered glass, cells radiating in
    # every direction with no horizon in them, which is what these slabs read as. The three
    # layers below are the three things a quarry face actually has.
    #
    # A little rough over the beds, so the blocks are quarried and not machined.
    t1 = S.new_texture("crough_%d" % seed, "CLOUDS", noise_scale=w * 0.13, noise_depth=3)
    m = S.add_modifier(ob, "DISPLACE", "d1", texture=t1, strength=w * 0.07, mid_level=0.5,
                       direction="NORMAL", texture_coords="LOCAL", vertex_group="front")
    S.apply_modifier(ob, m)
    # Break the crest. A straight top edge is what made a slab read as a poster on a stand
    # rather than as the end of a cliff; the sides stay flat so slabs still tile.
    crest = ob.vertex_groups.new(name="crest")
    for v in ob.data.vertices:
        f = max(0.0, (v.co.z - h * 0.74) / (h * 0.26))
        crest.add([v.index], min(1.0, f) * (1.0 - min(1.0, abs(v.co.x) / (w * 0.5) * 1.1)), "REPLACE")
    t3 = S.new_texture("ccrest_%d" % seed, "CLOUDS", noise_scale=w * 0.35, noise_depth=2)
    m = S.add_modifier(ob, "DISPLACE", "d3", texture=t3, strength=-h * 0.26, mid_level=0.42,
                       direction="Z", texture_coords="LOCAL", vertex_group="crest")
    S.apply_modifier(ob, m)
    tris = S.tri_count(ob)
    if tris > 3000:
        S.decimate(ob, 3000.0 / tris)
    S.decimate(ob, 1.0, planar_deg=7.0)
    S.shade_smooth(ob, 20.0)
    # rubble at the foot
    parts = [ob]
    for i in range(rng.randint(3, 6)):
        c = _rock_body("rubble_%d" % i, rng, radius=rng.uniform(0.18, 0.5), subdiv=3,
                       squash=(1.0, rng.uniform(0.6, 0.95), rng.uniform(0.4, 0.75)),
                       facet=0.45, mass=0.18, grain=0.05, mat=mat, seed=rng.randrange(9999), budget=220)
        c.location = Vector((rng.uniform(-w * 0.45, w * 0.45), -d * 0.5 - rng.uniform(0.1, 0.8), 0.0))
        S.tilt(c, rng, max_deg=30.0)
        S.apply_transforms(c)
        parts.append(c)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "materials_used": [stone],
            "extra_meta": {"modular": True, "module_width_m": w}}


def basalt_columns(pal, rng, params, variant):
    """A face of columnar basalt: hexagonal columns packed side by side, tallest at the back and
    stepping down to the front, their tops broken off at different heights, and fallen drums at
    the foot. It stands where a cliff_slab would, its face toward -Y, so the same placement
    serves both: a crag of Cinderlea's old lava instead of a bedded limestone scar."""
    mat, stone = stone_material(pal, params, rng, kind_default="basalt")
    w = params.get("width", 4.0)
    d = params.get("depth", 2.4)
    h = params.get("height", 6.0)
    r = params.get("column_radius", 0.42)
    # a hexagonal packing: centres a column's width apart along x, rows 0.866 of it apart
    step = r * 1.72
    rows = max(2, int(d / (step * 0.866)))
    cols = max(3, int(w / step))
    parts = []
    tops = []
    for row in range(rows):
        # the back row stands tallest; the front row is broken down to a third of it
        back = row / max(rows - 1, 1)
        for c in range(cols + (row % 2)):
            x = (c - (cols - 1 + (row % 2)) * 0.5) * step + rng.uniform(-0.04, 0.04) * r
            y = (back - 0.5) * d + rng.uniform(-0.04, 0.04) * r
            if abs(x) > w * 0.5 + r * 0.5:
                continue
            edge = abs(x) / (w * 0.5)
            ch = h * (0.35 + 0.65 * back) * (1.0 - 0.3 * edge ** 2) * rng.uniform(0.78, 1.05)
            if rng.random() < 0.12:
                ch *= rng.uniform(0.35, 0.6)          # one snapped off low
            ob = S.cylinder("col_%d_%d" % (row, c), radius=r * rng.uniform(0.92, 1.04), depth=ch,
                            vertices=rng.choice((5, 6, 6, 6, 7)), mat=mat, smooth=False)
            ob.rotation_euler = Euler((0.0, 0.0, math.radians(rng.uniform(0, 60))), "XYZ")
            ob.location = Vector((x, y, 0.0))
            S.apply_transforms(ob)
            # the top is a joint too: tipped a few degrees, not sawn flat
            for v in ob.data.vertices:
                if v.co.z > ch * 0.5:
                    v.co.z += (v.co.x - x) * rng.uniform(-0.12, 0.12) + (v.co.y - y) * rng.uniform(-0.12, 0.12)
            S.bevel(ob, width=r * 0.06, segments=1, angle_deg=40)
            parts.append(ob)
            tops.append(ch)
    # drums fallen from the front, lying at the foot
    for i in range(rng.randint(3, 6)):
        ln = rng.uniform(0.5, 1.4)
        ob = S.cylinder("drum_%d" % i, radius=r * rng.uniform(0.85, 1.0), depth=ln, vertices=6, mat=mat,
                        smooth=False, centered=True)
        ob.rotation_euler = Euler((math.radians(90 + rng.uniform(-15, 15)), 0.0,
                                   math.radians(rng.uniform(0, 180))), "XYZ")
        ob.location = Vector((rng.uniform(-w * 0.45, w * 0.45), -d * 0.5 - rng.uniform(0.3, 1.2), r * 0.8))
        S.apply_transforms(ob)
        S.bevel(ob, width=r * 0.06, segments=1, angle_deg=40)
        parts.append(ob)
    S.drop_to_ground(parts)
    total = sum(S.tri_count(p) for p in parts)
    if total > 3200:
        for p in parts:
            S.decimate(p, 3200.0 / total)
    return {"opaque_objs": parts, "collision": "col_glb", "materials_used": [stone],
            "extra_meta": {"columns": len(tops), "tallest_m": round(max(tops), 2) if tops else 0.0}}


def fallen_log(pal, rng, params, variant):
    """A trunk that came down in a storm and has lain a few winters: bark still on, the snapped
    top ragged, a few limbs broken to stubs, moss on its upper side, and a third of its girth
    settled into the ground. It lies along X."""
    bark = M.by_name(params.get("bark", "oak_bark"), pal, age=0.95, tint=0.3)
    mossy = params.get("moss", True)
    moss = M.by_name("moss", pal) if mossy else None
    length = params.get("length", rng.uniform(5.0, 8.5))
    r = params.get("radius", rng.uniform(0.28, 0.46))
    ob = S.cylinder("log", radius=r, radius_top=r * rng.uniform(0.62, 0.8), depth=length, vertices=12,
                    mat=bark, smooth=True, centered=True)
    ob.rotation_euler = Euler((0.0, math.radians(90.0), math.radians(rng.uniform(-4, 4))), "XYZ")
    S.apply_transforms(ob)
    S.subdivide(ob, levels=1, simple=True)
    S.jitter_verts(ob, amount=r * 0.12, scale=0.6, seed=rng.randrange(999))
    parts = [ob]
    # limbs broken to stubs, most on the upper side
    lo, hi = params.get("stubs", (3, 6))
    for i in range(rng.randint(lo, hi)):
        x = rng.uniform(-length * 0.4, length * 0.45)
        a = rng.uniform(-70, 70) if rng.random() < 0.8 else rng.uniform(100, 260)
        ln = rng.uniform(0.35, 1.2)
        st = S.cylinder("stub_%d" % i, radius=r * rng.uniform(0.18, 0.32), radius_top=r * 0.12, depth=ln,
                        vertices=6, mat=bark, smooth=True)
        st.rotation_euler = Euler((math.radians(a), math.radians(rng.uniform(-35, 35)), 0.0), "XYZ")
        st.location = Vector((x, 0.0, 0.0))
        S.apply_transforms(st)
        parts.append(st)
    # moss on whatever faces up
    if mossy:
        for p in parts:
            S.assign_material_to_faces(p, moss, lambda poly: poly.normal.z > 0.55 and rng.random() < 0.7)
    # settled a third of its girth into the ground
    settle = params.get("settle", 0.65)
    for p in parts:
        for v in p.data.vertices:
            v.co.z += r * settle
    used = [params.get("bark", "oak_bark")] + (["moss"] if mossy else [])
    return {"opaque_objs": parts, "collision": "convex", "materials_used": used,
            "extra_meta": {"length_m": round(length, 2)}}


def driftwood(pal, rng, params, variant):
    """Driftwood on the tide line: a trunk or a bough the sea has had for a year, stripped of its
    bark and silvered, its limbs worn down to knuckles, lying on the sand rather than sunk in the
    ground. It lies along X."""
    p = {"bark": "driftwood_log", "moss": False, "stubs": (0, 2), "settle": 0.3,
         "length": rng.uniform(2.2, 5.5), "radius": rng.uniform(0.12, 0.28)}
    p.update(params)
    return fallen_log(pal, rng, p, variant)


def scree(pal, rng, params, variant):
    """A cluster of small angular stones: one instance covers a patch of slope."""
    mat, stone = stone_material(pal, params, rng)
    n = int(params.get("count", rng.randint(14, 22)))
    spread = params.get("spread", 1.9)
    parts = []
    for i in range(n):
        r = rng.uniform(0.07, 0.26) * (1.6 if i < 3 else 1.0)
        c = _rock_body("scree_%d" % i, rng, radius=r, subdiv=3,
                       squash=(1.0, rng.uniform(0.55, 0.95), rng.uniform(0.35, 0.7)),
                       facet=rng.uniform(0.4, 0.55), mass=0.16, grain=0.05, mat=mat,
                       seed=rng.randrange(9999), budget=180, flatten_base=False)
        a = rng.uniform(0, math.tau)
        d = spread * math.sqrt(rng.random())
        c.location = Vector((math.cos(a) * d, math.sin(a) * d, 0.0))
        c.rotation_euler = Euler((rng.uniform(0, math.pi), rng.uniform(0, math.pi), rng.uniform(0, math.tau)))
        S.apply_transforms(c)
        parts.append(c)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "trimesh", "materials_used": [stone],
            "unwrap_mode": "sphere"}


def standing_stone(pal, rng, params, variant):
    """A raised menhir; Briarwold's are carved with lines kept oiled (WORLD_BIBLE §6.4)."""
    mat, stone = stone_material(pal, params, rng, kind_default=params.get("stone"))
    h = params.get("height", rng.uniform(2.6, 4.2))
    w = h * rng.uniform(0.22, 0.34)
    d = w * rng.uniform(0.45, 0.75)
    prof = []
    steps = 9
    for i in range(steps + 1):
        t = i / steps
        # tapers toward the top, widest a third of the way up
        k = (0.78 + 0.32 * math.sin(math.pi * min(1.0, t * 1.35))) * (1.0 - 0.28 * t)
        prof.append((w * 0.5 * k, t * h))
    ob = S.lathe("menhir", prof, segments=9, mat=mat, close=True, twist=rng.uniform(-0.05, 0.05))
    ob.scale = Vector((1.0, d / w, 1.0))
    S.apply_transforms(ob)
    S.subdivide(ob, levels=2, simple=True)
    seed = rng.randrange(9999)
    _displace_stack(ob, rng, facet=w * 0.22, mass=w * 0.12, grain=w * 0.03,
                    facet_scale=1.4 / h, mass_scale=0.6 / h, grain_scale=0.2 / h, seed=seed)
    S.shade_smooth(ob, 30.0)
    parts = [ob]
    carve = params.get("carved", pal.short == "briarwold")
    if carve:
        # carved lines: shallow grooves cut around the stone with a boolean of thin boxes
        lines = int(params.get("carve_lines", rng.randint(4, 7)))
        cutters = []
        for i in range(lines):
            z = h * (0.28 + 0.55 * i / max(1, lines - 1)) + rng.uniform(-0.04, 0.04) * h
            box = S.box_centered("cut_%d" % i, size=(w * 2.4, d * 2.4, h * 0.016), location=(0, 0, z),
                                 rotation=(rng.uniform(-6, 6), rng.uniform(-4, 4), 0))
            cutters.append(box)
        for c in cutters:
            S.boolean(ob, c, "DIFFERENCE")
        S.shade_smooth(ob, 30.0)
    tris = S.tri_count(ob)
    if tris > 2600:
        S.decimate(ob, 2600.0 / tris)
        S.shade_smooth(ob, 30.0)
    # base stones packed round the foot
    for i in range(rng.randint(3, 6)):
        c = _rock_body("base_%d" % i, rng, radius=w * rng.uniform(0.18, 0.34), subdiv=3,
                       squash=(1.0, 0.8, 0.55), facet=0.42, mass=0.18, grain=0.05, mat=mat,
                       seed=rng.randrange(9999), budget=200)
        a = math.tau * i / 5 + rng.uniform(-0.4, 0.4)
        c.location = Vector((math.cos(a) * w * 0.62, math.sin(a) * d * 0.7, 0.0))
        S.tilt(c, rng, max_deg=22.0)
        S.apply_transforms(c)
        parts.append(c)
    S.tilt(ob, rng, max_deg=3.5)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "convex", "materials_used": [stone],
            "unwrap_mode": "sphere", "extra_meta": {"carved": bool(carve)}}


# --- giant bones (Skerrow: bones you can walk inside) ---------------------------------------

def _bone_material(pal, rng):
    return M.bone(pal, age=0.5 + 0.4 * rng.random(), wear=0.4 + 0.3 * rng.random())


def bone_rib(pal, rng, params, variant):
    """A giant rib arc: a curved tapering shaft you can walk under."""
    mat = _bone_material(pal, rng)
    span = params.get("span", rng.uniform(7.0, 12.0))
    rise = span * rng.uniform(0.62, 0.9)
    pts = []
    n = 16
    for i in range(n + 1):
        t = i / n
        a = math.pi * (0.06 + 0.88 * t)
        x = -math.cos(a) * span * 0.5
        z = math.sin(a) * rise
        y = math.sin(t * math.pi * 1.4) * span * 0.06
        pts.append((x, y, z))
    r0 = span * 0.055
    ob = S.tube_along("rib", pts, radius=r0, segments=10, radius_end=r0 * 0.4, mat=mat)
    # the head end swells where it met the spine
    head = S.sphere("rib_head", radius=r0 * 1.7, subdivisions=3, location=pts[0], mat=mat,
                    scale=(1.3, 0.8, 0.9))
    S.apply_transforms(head)
    parts = [ob, head]
    for p in parts:
        S.jitter_verts(p, amount=r0 * 0.09, scale=span * 0.35, seed=rng.randrange(999))
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb", "materials_used": ["bone"],
            "unwrap_mode": "sphere"}


def bone_finger(pal, rng, params, variant):
    """A single giant finger bone half-sunk in the scree: three phalanges."""
    mat = _bone_material(pal, rng)
    total = params.get("length", rng.uniform(4.5, 7.5))
    parts = []
    x = 0.0
    for i, frac in enumerate((0.44, 0.33, 0.23)):
        ln = total * frac
        r = total * (0.075 - 0.016 * i)
        pts = [(x, 0, 0), (x + ln * 0.5, 0, ln * 0.06), (x + ln, 0, 0)]
        shaft = S.tube_along("phal_%d" % i, pts, radius=r * 0.78, segments=10, mat=mat)
        parts.append(shaft)
        for e, px in ((0, x), (1, x + ln)):
            knuckle = S.sphere("knuckle_%d_%d" % (i, e), radius=r, subdivisions=3,
                               location=(px, 0, 0), mat=mat, scale=(0.9, 1.15, 1.05))
            S.apply_transforms(knuckle)
            parts.append(knuckle)
        x += ln * 1.01
    for p in parts:
        S.jitter_verts(p, amount=total * 0.006, scale=total * 0.3, seed=rng.randrange(999))
    joined_rot = rng.uniform(-14, 14)
    for p in parts:
        p.rotation_euler = Euler((0, math.radians(joined_rot), math.radians(rng.uniform(0, 360) * 0)), "XYZ")
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "convex", "materials_used": ["bone"],
            "unwrap_mode": "sphere"}


def bone_skull_fragment(pal, rng, params, variant):
    """A broken piece of a giant skull: a domed shell with an orbit and a torn edge."""
    mat = _bone_material(pal, rng)
    r = params.get("radius", rng.uniform(2.6, 4.0))
    dome = S.uv_sphere("skull", radius=r, segments=28, rings=16, mat=mat, scale=(1.0, 0.85, 0.78))
    S.apply_transforms(dome)
    # keep the upper shell, cut the rest away with a big box
    cutter = S.box_centered("cut", size=(r * 4, r * 4, r * 2), location=(0, 0, -r * 0.95))
    S.boolean(dome, cutter, "DIFFERENCE")
    # tear one side off
    tear = S.box_centered("tear", size=(r * 3, r * 3, r * 3),
                          location=(r * 1.35, r * 0.4, 0), rotation=(0, 0, rng.uniform(-25, 25)))
    S.boolean(dome, tear, "DIFFERENCE")
    S.solidify(dome, thickness=r * 0.09, offset=1.0)
    # eye socket
    orbit = S.sphere("orbit", radius=r * 0.3, subdivisions=3, location=(-r * 0.45, -r * 0.62, r * 0.1),
                     scale=(1.25, 1.0, 0.95))
    S.apply_transforms(orbit)
    S.boolean(dome, orbit, "DIFFERENCE")
    S.jitter_verts(dome, amount=r * 0.02, scale=r * 0.5, seed=rng.randrange(999))
    S.shade_smooth(dome, 36.0)
    tris = S.tri_count(dome)
    if tris > 3200:
        S.decimate(dome, 3200.0 / tris)
        S.shade_smooth(dome, 36.0)
    S.tilt(dome, rng, max_deg=18.0)
    S.drop_to_ground([dome])
    return {"opaque_objs": [dome], "collision": "col_glb", "materials_used": ["bone"],
            "unwrap_mode": "sphere"}


def bone_vertebra(pal, rng, params, variant):
    """A giant vertebra: a drum-shaped centrum with a spinous process and two wings."""
    mat = _bone_material(pal, rng)
    r = params.get("radius", rng.uniform(1.2, 2.0))
    body = S.lathe("centrum", [(r * 0.86, 0), (r * 0.98, r * 0.12), (r * 0.7, r * 0.55),
                               (r * 0.98, r * 0.98), (r * 0.86, r * 1.1)], segments=22, mat=mat)
    parts = [body]
    # neural arch
    arch = S.torus("arch", major=r * 0.62, minor=r * 0.22, seg_major=20, seg_minor=8,
                   location=(0, -r * 0.1, r * 1.55), rotation=(90, 0, 0), mat=mat)
    arch.scale = (1.0, 1.25, 1.0)
    S.apply_transforms(arch)
    parts.append(arch)
    spine = S.cylinder("spinous", radius=r * 0.3, radius_top=r * 0.14, depth=r * 1.5,
                       vertices=10, location=(0, -r * 0.1, r * 1.9), rotation=(12, 0, 0), mat=mat)
    parts.append(spine)
    for sgn in (-1, 1):
        wing = S.cylinder("wing_%d" % sgn, radius=r * 0.26, radius_top=r * 0.12, depth=r * 0.95,
                          vertices=9, location=(sgn * r * 0.55, -r * 0.05, r * 1.2),
                          rotation=(0, sgn * 62, 0), mat=mat)
        parts.append(wing)
    for p in parts:
        S.jitter_verts(p, amount=r * 0.02, scale=r * 0.8, seed=rng.randrange(999))
    S.tilt(body, rng, max_deg=10.0)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "convex", "materials_used": ["bone"],
            "unwrap_mode": "sphere"}


def sunken_masonry(pal, rng, params, variant):
    """Cut and squared blocks half-drowned in the fen.

    Not a rock shape, and deliberately so: a delta has no cliffs, and this is a story
    object rather than geology -- something was built here and the fen came up and took it.
    The dressed faces stay readable, with the silt line doing the talking: pale worked
    stone above it, green-black and slick below. Flat on the bottom so it sits in the peat,
    and tilted differently per variant so a field of them never lines up.
    """
    dressed = M.stone_blocks(pal, wear=0.5, age=0.75, scale=0.9, block_w=0.85, block_h=0.42,
                             name="masonry_dressed")
    drowned = M.drowned_stone(pal, age=0.85, scale=0.8, name="masonry_drowned")
    n = int(params.get("blocks", rng.randint(2, 3)))
    # Where the water sat. Everything under it went green; the line itself is the point.
    silt = params.get("silt_line", rng.uniform(0.26, 0.42))
    parts = []
    cursor = 0.0
    for i in range(n):
        w = rng.uniform(0.85, 1.5)
        d = rng.uniform(0.55, 0.9)
        h = rng.uniform(0.45, 0.8)
        ob = S.box_centered("block_%d" % i, size=(w, d, h), location=(0, 0, h * 0.5), mat=dressed)
        S.bevel(ob, width=min(w, d, h) * 0.055, segments=2, angle_deg=50)
        S.subdivide(ob, levels=2, simple=True)
        # Weathering, not erosion: the block keeps its corners and its cut faces, it has
        # only lost its polish. A displaced blob here would throw away the whole point.
        S.jitter_verts(ob, amount=min(w, d) * 0.022, scale=0.5, seed=rng.randrange(999))
        ob.location = Vector((cursor, rng.uniform(-0.25, 0.25), 0.0))
        ob.rotation_euler = Euler((math.radians(rng.uniform(-9, 9) + (variant % 2) * 4.0),
                                   math.radians(rng.uniform(-7, 7)),
                                   math.radians(rng.uniform(0, 360))), "XYZ")
        S.apply_transforms(ob)
        # Sit it back on the ground: the tilt lifted a corner.
        S.drop_to_ground([ob])
        S.assign_material_to_faces(ob, drowned, lambda poly: poly.center.z < silt)
        parts.append(ob)
        cursor += w * rng.uniform(0.55, 0.95)
    # A course of smaller rubble spilled off the end, so it reads as a ruin and not a crate.
    for i in range(rng.randint(2, 4)):
        c = _rock_body("rubble_%d" % i, rng, radius=rng.uniform(0.12, 0.26), subdiv=3,
                       squash=(1.0, rng.uniform(0.7, 1.0), rng.uniform(0.45, 0.8)),
                       facet=0.5, mass=0.16, grain=0.04, mat=drowned,
                       seed=rng.randrange(9999), budget=200)
        a = rng.uniform(0, math.tau)
        c.location = Vector((cursor * rng.uniform(-0.1, 1.05) + math.cos(a) * 0.5,
                             math.sin(a) * 0.6, 0.0))
        S.tilt(c, rng, max_deg=25.0)
        S.apply_transforms(c)
        parts.append(c)
    S.drop_to_ground(parts)
    return {"opaque_objs": parts, "collision": "col_glb",
            "materials_used": ["stone_blocks", "drowned_stone"],
            "extra_meta": {"silt_line_m": round(silt, 3), "blocks": n}}


# Stone for a ledge that no material builds by that name: the granite recipe in another colour.
LEDGE_STONE = {
    "basalt": {"base_hex": "#3b3b3f", "tint_role": "cool", "lichen": 0.12, "facet": 0.8},
    "sandstone": {"base_hex": "#a4825c", "tint_role": "warm", "lichen": 0.2, "facet": 0.45},
}
# A ledge's least triangles: over world/scatter_lod.gd's SOLID_MIN_TRIS (1500), with a margin.
LEDGE_MIN_TRIS = 1650
LEDGE_BY_REGION = {"hearthvale": "chalk_rock", "skerrow": "limestone", "briarwold": "granite",
                   "cinderlea": "basalt", "brightwater": "sandstone", "sedgemire": "granite"}


def cliff_ledge(pal, rng, params, variant):
    """A ledge of bedded rock that tiles end to end into a cliff: two to four beds, each standing
    out a little further than the one below it, parted by a worn groove; the lowest bed undercut
    and the top one a lip that overhangs; the front broken into blocks along each bed. Its two
    ends are cut to the beds' own profile and nothing else, so two ledges side by side meet as one
    face, and a row of them reads as one run of rock; stacked, each row set back, they step down a
    fall or a crag in ledges.

    params: width (5.0; keep it, rows are laid at it), height (by variant: 3.0, 4.2, 2.1),
    depth (3.4), stone (limestone, granite, chalk_rock, basalt or sandstone; by region)."""
    stone_name = params.get("stone") or LEDGE_BY_REGION.get(pal.short, "granite")
    if stone_name in LEDGE_STONE:
        kw = dict(LEDGE_STONE[stone_name])
        mat = M.granite(pal, wear=0.4 + 0.3 * rng.random(), age=0.5 + 0.4 * rng.random(),
                        name="%s_%s" % (stone_name, pal.short), **kw)
        used = "granite"
    else:
        mat, used = stone_material(pal, {"stone": stone_name}, rng)
    w = float(params.get("width", 5.0))
    h = float(params.get("height", (3.0, 4.2, 2.1)[variant % 3]))
    d = float(params.get("depth", 3.4))
    beds = int(params.get("beds", max(2, min(4, round(h / 1.1)))))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = S.bm_to_object(bm, "ledge", mat, smooth=True)
    ob.scale = Vector((w, d, h))
    S.apply_transforms(ob)
    for v in ob.data.vertices:
        v.co.z += h * 0.5
    S.subdivide(ob, levels=5, simple=True)
    # The beds' own profile, the same at every x: how far the face stands out at height z. The
    # upper beds stand further out, the top one a lip over the rest; the lowest is cut back under
    # it, and between two beds the parting is worn into a groove.
    lip = d * 0.16
    undercut = d * 0.12
    thick = [1.0 + 0.5 * rng.random() for _ in range(beds)]
    total = sum(thick)
    tops = []
    acc = 0.0
    for t in thick:
        acc += t / total * h
        tops.append(acc)

    # The beds pinch and swell along the face: their partings are wavy lines, not rules. The wave
    # dies away over the last half-metre at each end, so the ends still meet the next ledge's.
    ph1, ph2 = rng.uniform(0.0, math.tau), rng.uniform(0.0, math.tau)
    amp = min(0.16, h * 0.045)

    def end_fade(x, reach=0.5):
        return max(0.0, min(1.0, (w * 0.5 - abs(x)) / reach))

    def wave(x):
        return (amp * math.sin(x * 1.25 + ph1) + amp * 0.55 * math.sin(x * 2.9 + ph2)) * end_fade(x)

    def bed_of(z, x=0.0):
        zz = z + wave(x)
        for i, top in enumerate(tops):
            if zz <= top + 1e-6:
                lo = tops[i - 1] if i > 0 else 0.0
                return i, max(0.0, min(1.0, (zz - lo) / max(top - lo, 1e-6)))
        return beds - 1, 1.0

    def profile(z, x=0.0):
        i, f = bed_of(z, x)
        out = lip * (i / max(beds - 1, 1)) - (undercut if i == 0 else 0.0)
        # A bed's front is a plane, broken where the beds part: a sharp V worn into each parting,
        # the bed below's top edge and the bed above's foot. (A bed bulging out between its
        # partings, as the first ledges had it, laid the face in pillows.)
        top_edge = max(0.0, 1.0 - (1.0 - f) / 0.14) if i < beds - 1 else 0.0
        foot = max(0.0, 1.0 - f / 0.14) if i > 0 else 0.0
        out -= d * 0.07 * max(top_edge, foot)
        return out

    # The joints: a crag's beds are cut by cracks at no regular spacing, a block here a stride
    # long and there a hand's breadth, the cracks leaning a little, and one or two of them (the
    # master joints) running down through every bed. Each block stands out or has weathered back
    # by its own amount, and now and then one has fallen out altogether. (A fixed number of
    # blocks a bed, offset bed to bed, laid the face in courses like a wall.)
    masters = [rng.uniform(-w * 0.3, w * 0.3) for _ in range(rng.randint(1, 2))]
    joints = []
    for i in range(beds):
        xs = [(m + rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12)) for m in masters]
        x = -w * 0.5 + rng.uniform(0.25, 1.3)
        while x < w * 0.5 - 0.25:
            if all(abs(x - m) > 0.35 for m, _s in xs):
                xs.append((x, rng.uniform(-0.35, 0.35)))
            step = rng.uniform(0.35, 1.2) if rng.random() < 0.45 else rng.uniform(1.2, 2.6)
            x += step
        xs.sort()
        joints.append(xs)
    mids = [((tops[i - 1] if i > 0 else 0.0) + tops[i]) * 0.5 for i in range(beds)]
    stand = {}

    def block_at(x, z, i):
        """The block (bed, index) a point is in, and how far it is from the nearest crack."""
        n = 0
        near = 9.0
        for jx, slant in joints[i]:
            at = jx + slant * (z - mids[i])
            if x > at:
                n += 1
            near = min(near, abs(x - at))
        return n, near

    def block_out(x, z, i):
        n, near = block_at(x, z, i)
        key = (i, n)
        if key not in stand:
            r = rng.random()
            if r < 0.1:
                stand[key] = -0.16 * d            # fallen out
            elif r < 0.22:
                stand[key] = 0.09 * d             # a boss standing proud
            else:
                stand[key] = rng.uniform(-0.06, 0.06) * d
        # the crack itself, worn open
        crack = -0.045 * d * max(0.0, 1.0 - near / 0.13)
        return stand[key] + crack

    # The crest: some of the top bed's blocks are broken off lower, a notch in the skyline; and
    # the front edge of the top is rounded by the weather.
    notch = {}

    def crest_drop(x, z):
        n, _near = block_at(x, z, beds - 1)
        if n not in notch:
            notch[n] = rng.uniform(0.18, 0.55) * thick[-1] / total * h if rng.random() < 0.4 else 0.0
        return notch[n]

    for v in ob.data.vertices:
        front = max(0.0, min(1.0, -v.co.y / (d * 0.5)))
        x, z = v.co.x, v.co.z
        e = end_fade(x)
        if front > 0.0:
            i, _f = bed_of(z, x)
            dy = profile(z, x) + block_out(x, z, i) * e
            v.co.y -= dy * front
        if z > h - 1e-4 or z > tops[-2 if beds > 1 else 0] + 1e-4:
            # the top bed's crest: notched where a block has broken off, rounded at the front
            drop = crest_drop(x, z) * e * max(0.0, min(1.0, front * 1.6 + 0.2))
            top_d = h - z
            if top_d < drop:
                v.co.z = h - drop
            arris = max(0.0, 1.0 - top_d / 0.3) * max(0.0, front - 0.7) / 0.3
            v.co.z -= 0.14 * arris * e
    # the crest: the top is weathered uneven, but meets the next ledge at the same height
    seed = rng.randrange(9999)
    crest = ob.vertex_groups.new(name="crest")
    rough = ob.vertex_groups.new(name="rough")
    for v in ob.data.vertices:
        end = max(0.0, min(1.0, (w * 0.5 - abs(v.co.x)) / 0.6))
        top = max(0.0, (v.co.z - h * 0.85) / (h * 0.15))
        crest.add([v.index], min(1.0, top) * end, "REPLACE")
        front = max(0.0, min(1.0, -v.co.y / (d * 0.5) + 0.2))
        rough.add([v.index], front * end, "REPLACE")
    t1 = S.new_texture("lcrest_%d" % seed, "CLOUDS", noise_scale=w * 0.22, noise_depth=2)
    m = S.add_modifier(ob, "DISPLACE", "d1", texture=t1, strength=-h * 0.14, mid_level=0.35,
                       direction="Z", texture_coords="LOCAL", vertex_group="crest")
    S.apply_modifier(ob, m)
    # quarried, not machined: a rough over the face, off the ends
    t2 = S.new_texture("lrough_%d" % seed, "CLOUDS", noise_scale=w * 0.05, noise_depth=3)
    m = S.add_modifier(ob, "DISPLACE", "d2", texture=t2, strength=d * 0.03, mid_level=0.5,
                       direction="NORMAL", texture_coords="LOCAL", vertex_group="rough")
    S.apply_modifier(ob, m)
    tris = S.tri_count(ob)
    if tris > 3000:
        S.decimate(ob, 3000.0 / tris)
    # Broken planes and hard edges, as a rock face has, rather than a smooth relief: coplanar
    # faces are merged, at the widest angle that still leaves the mesh LEDGE_MIN_TRIS. A ledge is
    # laid tens of thousands of times over the sea cliffs, and the world streamer gives an opaque
    # piece its LOD ladder only at SOLID_MIN_TRIS (1500) and over (world/scatter_lod.gd); under it,
    # it is drawn whole at every distance. At one angle for all, the short ledges came to 1,272.
    whole = ob.data.copy()
    for ang in (11.0, 8.0, 6.0, 4.5, 3.0):
        trial = whole.copy()
        old_mesh = ob.data
        ob.data = trial
        if old_mesh is not whole and old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)
        S.decimate(ob, 1.0, planar_deg=ang)
        if S.tri_count(ob) >= LEDGE_MIN_TRIS:
            break
    S.shade_smooth(ob, 16.0)
    S.drop_to_ground([ob])
    return {"opaque_objs": [ob], "collision": "col_glb", "materials_used": [used], "tier": "field",
            "extra_meta": {"modular": True, "module_width_m": w, "beds": beds,
                           "lip_m": lip, "stone": stone_name}}


# A cliff face's size by variant: (width, height, depth). A tall one for the sea cliffs and the gorge
# walls, a broad one, and a squat one for a crag's lower face or a step.
FACE_DIMS = ((20.0, 16.0, 8.0), (14.0, 24.0, 8.0), (24.0, 10.0, 7.0))
FACE_MIN_TRIS = 3200
FACE_MAX_TRIS = 7000


def cliff_face(pal, rng, params, variant):
    """A large piece of cliff, 10 to 24 m, to be sunk into a steep face of the terrain so the face is
    rock and not the heightmap's stretched sheet: the Skyrim and Dark Souls way, a few big meshes
    over a wall, not a carpet of small blocks. It is bedded (six to nine beds of their own
    thickness, each standing out or weathered back by its own amount, one or two of the upper ones
    an overhanging lip), cut by joints (a few master joints down through every bed, and cracks at no
    regular spacing within a bed, each block standing proud, set back or fallen out), and massed by
    a broad swell over the whole face. It is not a module: its sides curl back into the hill and its
    crest is broken, so pieces laid overlapping read as one face. Its back and base are plain, to
    be buried.

    params: width, height, depth (by variant: FACE_DIMS), stone (by region, as a ledge's)."""
    stone_name = params.get("stone") or LEDGE_BY_REGION.get(pal.short, "granite")
    if stone_name in LEDGE_STONE:
        kw = dict(LEDGE_STONE[stone_name])
        mat = M.granite(pal, wear=0.4 + 0.3 * rng.random(), age=0.5 + 0.4 * rng.random(),
                        name="%s_%s_face" % (stone_name, pal.short), **kw)
        used = "granite"
    else:
        mat, used = stone_material(pal, {"stone": stone_name}, rng)
    w0, h0, d0 = FACE_DIMS[variant % len(FACE_DIMS)]
    w = float(params.get("width", w0))
    h = float(params.get("height", h0))
    d = float(params.get("depth", d0))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    ob = S.bm_to_object(bm, "face", mat, smooth=True)
    ob.scale = Vector((w, d, h))
    S.apply_transforms(ob)
    for v in ob.data.vertices:
        v.co.z += h * 0.5
    S.subdivide(ob, levels=6, simple=True)

    # the beds: thicknesses of their own, and how far each stands out (+) or is weathered back (-)
    beds = int(params.get("beds", max(6, min(9, round(h / 2.4)))))
    thick = [0.6 + rng.random() for _ in range(beds)]
    total = sum(thick)
    tops, acc = [], 0.0
    for t in thick:
        acc += t / total * h
        tops.append(acc)
    out_by_bed = [rng.uniform(-0.06, 0.06) * d for _ in range(beds)]
    for i in rng.sample(range(beds // 2, beds), k=min(2, beds - beds // 2)):
        out_by_bed[i] = rng.uniform(0.08, 0.14) * d          # an overhanging lip
    ph = [rng.uniform(0.0, math.tau) for _ in range(4)]

    def wave(x):
        return 0.35 * math.sin(x * 0.45 + ph[0]) + 0.2 * math.sin(x * 1.1 + ph[1])

    def bed_of(z, x):
        zz = z + wave(x)
        for i, top in enumerate(tops):
            if zz <= top + 1e-6:
                lo = tops[i - 1] if i > 0 else 0.0
                return i, max(0.0, min(1.0, (zz - lo) / max(top - lo, 1e-6)))
        return beds - 1, 1.0

    masters = [rng.uniform(-w * 0.4, w * 0.4) for _ in range(rng.randint(3, 5))]
    joints = []
    for i in range(beds):
        xs = [(m + rng.uniform(-0.3, 0.3), rng.uniform(-0.15, 0.15)) for m in masters]
        x = -w * 0.5 + rng.uniform(0.5, 2.5)
        while x < w * 0.5 - 0.5:
            if all(abs(x - m) > 0.8 for m, _s in xs):
                xs.append((x, rng.uniform(-0.3, 0.3)))
            x += rng.uniform(0.8, 2.2) if rng.random() < 0.5 else rng.uniform(2.2, 5.0)
        xs.sort()
        joints.append(xs)
    mids = [((tops[i - 1] if i > 0 else 0.0) + tops[i]) * 0.5 for i in range(beds)]
    stand = {}

    def block(x, z, i):
        n, near = 0, 99.0
        for jx, slant in joints[i]:
            at = jx + slant * (z - mids[i])
            if x > at:
                n += 1
            near = min(near, abs(x - at))
        key = (i, n)
        if key not in stand:
            r = rng.random()
            stand[key] = (-0.1 * d if r < 0.08 else (0.06 * d if r < 0.2 else rng.uniform(-0.035, 0.035) * d))
        crack = -0.05 * d * max(0.0, 1.0 - near / 0.35)
        return stand[key] + crack

    crest_drop = {}
    for v in ob.data.vertices:
        x, z = v.co.x, v.co.z
        front = max(0.0, min(1.0, -v.co.y / (d * 0.5)))
        # the sides curl back into the hill over the outer quarter, more toward the top
        side = max(0.0, (abs(x) - w * 0.3) / (w * 0.2))
        curl = side * side * d * (0.55 + 0.35 * z / h)
        if front > 0.0:
            i, f = bed_of(z, x)
            dy = out_by_bed[i] + block(x, z, i)
            # the parting between two beds, worn into a groove
            if 0 < i and f < 0.12:
                dy -= 0.06 * d * (1.0 - f / 0.12)
            if i < beds - 1 and f > 0.9:
                dy -= 0.04 * d * (f - 0.9) / 0.1
            v.co.y -= dy * front
        v.co.y += curl * max(front, 0.2)
        # the crest: blocks of the top bed broken off lower, and the whole top line wandering
        if z > tops[-2] - 1e-4 if beds > 1 else z > 0.8 * h:
            n = int((x / w + 0.5) * 7 + 0.5)
            if n not in crest_drop:
                crest_drop[n] = rng.uniform(0.0, 0.5) * (h - tops[-2]) if rng.random() < 0.5 else 0.0
            top_line = h - crest_drop[n] - 0.6 * h * side * side
            if v.co.z > top_line:
                v.co.z = top_line + (v.co.z - top_line) * 0.15
        # and the base spread and plain, to be buried
        if z < 0.08 * h:
            v.co.y += (1.0 - z / (0.08 * h)) * 0.1 * d * front
    seed = rng.randrange(9999)
    # the swell of the whole face, and a weathered rough over it
    t1 = S.new_texture("fswell_%d" % seed, "CLOUDS", noise_scale=w * 0.3, noise_depth=2)
    m = S.add_modifier(ob, "DISPLACE", "d1", texture=t1, strength=d * 0.12, mid_level=0.5,
                       direction="NORMAL", texture_coords="LOCAL")
    S.apply_modifier(ob, m)
    t2 = S.new_texture("frough_%d" % seed, "CLOUDS", noise_scale=w * 0.03, noise_depth=3)
    m = S.add_modifier(ob, "DISPLACE", "d2", texture=t2, strength=d * 0.025, mid_level=0.5,
                       direction="NORMAL", texture_coords="LOCAL")
    S.apply_modifier(ob, m)
    tris = S.tri_count(ob)
    if tris > FACE_MAX_TRIS * 2:
        S.decimate(ob, FACE_MAX_TRIS * 2.0 / tris)
    whole = ob.data.copy()
    for ang in (9.0, 6.0, 4.0, 2.5):
        trial = whole.copy()
        old_mesh = ob.data
        ob.data = trial
        if old_mesh is not whole and old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)
        S.decimate(ob, 1.0, planar_deg=ang)
        if S.tri_count(ob) >= FACE_MIN_TRIS:
            break
    if S.tri_count(ob) > FACE_MAX_TRIS:
        S.decimate(ob, FACE_MAX_TRIS / float(S.tri_count(ob)))
    S.shade_smooth(ob, 18.0)
    S.drop_to_ground([ob])
    return {"opaque_objs": [ob], "collision": "col_glb", "materials_used": [used],
            "extra_meta": {"stone": stone_name, "face_depth_m": d, "face_width_m": w, "face_height_m": h}}


KINDS = {
    "boulder": boulder,
    "cliff_slab": cliff_slab,
    "cliff_ledge": cliff_ledge,
    "cliff_face": cliff_face,
    "basalt_columns": basalt_columns,
    "fallen_log": fallen_log,
    "driftwood": driftwood,
    "scree": scree,
    "standing_stone": standing_stone,
    "sunken_masonry": sunken_masonry,
    "bone_rib": bone_rib,
    "bone_finger": bone_finger,
    "bone_skull_fragment": bone_skull_fragment,
    "bone_vertebra": bone_vertebra,
}


if __name__ == "__main__":
    run_generator("Wickmere rock generator", KINDS, "rocks", "gen_rocks")
