"""Ground flora: grass, reeds, ferns, flowers, heather, fungus, moss, vines, lilies.

The grasses' blades are drawn a centimetre or so wide on a 1024 atlas: at 3 cm and thirty to a
cell on 512, a clump seen from a rider's saddle at one to three metres read as a handful of
broad green paddles (the ride capture on the Hearthvale verge), cabbage leaves, not grass.

    blender -b --python tools/forge/gen_flora.py -- --kind grass_clump --palette hearthvale --seed 3

These are low-triangle alpha cards: a few crossed or fanned quads carrying a drawn atlas
(lib.textures), so a scattered field costs almost nothing. Every material is named
*_foliage, which is the contract that makes the Godot import step swap in the wind shader
(CONTRACTS.md §4).
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import cli  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib import textures as T  # noqa: E402
from lib.runner import run_generator  # noqa: E402


# --- card builders ---------------------------------------------------------------------

def fan_cards(name, mat, rng, count=5, width=0.5, height=0.5, cells=2, radius=0.12, tilt=12.0,
              bow=0.0, anchor_bottom=True, pitch=0.0):
    """A rosette of upright quads around a point: the standard clump.

    Cards are spread over a small radius and rolled to different headings so the clump has
    depth from every side; `bow` leans the top of each card outward so the silhouette is a
    tuft rather than a cross."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    for i in range(count):
        head = math.tau * (i + rng.uniform(-0.22, 0.22)) / count
        dx, dy = math.cos(head), math.sin(head)
        px, py = dx * radius * rng.uniform(0.0, 1.0), dy * radius * rng.uniform(0.0, 1.0)
        w = width * rng.uniform(0.82, 1.2)
        h = height * rng.uniform(0.78, 1.25)
        lean = math.radians(rng.uniform(-tilt, tilt))
        out = Vector((dx, dy, 0.0)) * (bow * h)
        base = Vector((px, py, 0.0))
        # card lies in the plane containing (dx, dy) and Z
        right = Vector((-dy, dx, 0.0))
        corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
        verts = []
        for (u, v) in corners:
            p = base + right * (u * w) + Vector((0, 0, v * h)) + out * v
            p += Vector((math.sin(lean) * v * h * 0.3, math.cos(lean) * 0.0, 0.0))
            if pitch:
                p += Vector((dx, dy, 0.0)) * (math.sin(math.radians(pitch)) * v * h)
            if not anchor_bottom:
                p -= Vector((0, 0, h * 0.5))
            verts.append(bm.verts.new(p))
        f = bm.faces.new(verts)
        cx, cy = rng.randrange(cells), rng.randrange(cells)
        flip = rng.random() < 0.5
        cs = [(1.0 - u - 0.5 + 0.5 if flip else u + 0.5, v) for (u, v) in corners]
        for loop, (u, v) in zip(f.loops, cs):
            loop[uv].uv = ((cx + u) * cell, (cy + v) * cell)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def flat_cards(name, mat, rng, count=3, size=0.5, cells=2, spread=0.25, jitter_z=0.02):
    """Horizontal quads lying on the ground or on water: lily pads, moss patches."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = spread * math.sqrt(rng.random())
        c = Vector((math.cos(a) * d, math.sin(a) * d, rng.uniform(0, jitter_z)))
        s = size * rng.uniform(0.7, 1.3)
        roll = rng.uniform(0, math.tau)
        corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
        verts = []
        for (u, v) in corners:
            x = (u * math.cos(roll) - v * math.sin(roll)) * s
            y = (u * math.sin(roll) + v * math.cos(roll)) * s
            verts.append(bm.verts.new(c + Vector((x, y, 0.0))))
        f = bm.faces.new(verts)
        cx, cy = rng.randrange(cells), rng.randrange(cells)
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv].uv = ((cx + u + 0.5) * cell, (cy + v + 0.5) * cell)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def shelf_cards(name, mat, rng, count=4, size=0.3, cells=2, height=1.2, radius=0.2):
    """Cards angled out of a vertical surface: bracket fungus on a trunk."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    for i in range(count):
        a = rng.uniform(-0.9, 0.9)
        z = height * rng.uniform(0.1, 1.0)
        s = size * rng.uniform(0.7, 1.3)
        base = Vector((math.sin(a) * radius, -math.cos(a) * radius, z))
        right = Vector((math.cos(a), math.sin(a), 0.0))
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
        verts = []
        for (u, v) in corners:
            p = base + right * (u * s) + out * (v * s * 0.85) + Vector((0, 0, -v * s * 0.18))
            verts.append(bm.verts.new(p))
        f = bm.faces.new(verts)
        cx, cy = rng.randrange(cells), rng.randrange(cells)
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv].uv = ((cx + u + 0.5) * cell, (cy + 1.0 - v) * cell)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def _mat(out_dir, name, names, threshold=0.42):
    m = M.foliage_material(name, out_dir / names["albedo"], out_dir / names["normal"],
                           out_dir / names["orm"], threshold=threshold)
    m["forge_textures"] = dict(names)
    return m


def _atlas_dir(ctx):
    return ctx["out_dir"]


# --- kinds --------------------------------------------------------------------------------
# Each returns a spec for export.finish_asset. `ctx` carries out_dir, name, quick.

def grass_clump(pal, rng, params, variant, ctx):
    greens = [pal.tint(P.lin("#5f8a3c"), "green", 0.45),
              pal.tint(P.lin("#7a9a48"), "green", 0.30),
              pal.tint(P.lin("#4e7a34"), "green", 0.35),
              pal.tint(P.lin("#c2a15a"), "warm", 0.35)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], greens, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 1024, blades=84, width=0.011, lean=0.5,
                          seed_head=pal.tint(P.lin("#c9a24a"), "warm", 0.4), bend=0.85,
                          tip_color=pal.tint(P.lin("#b8a462"), "warm", 0.3))
    mat = _mat(ctx["out_dir"], "%s_grass_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.32, 0.55))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 6), width=h * 1.5,
                   height=h, radius=h * 0.28, bow=0.1, tilt=14)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def grey_grass(pal, rng, params, variant, ctx):
    # Grass on the ash heath: grey-brown, a warm straw, one blade in four dried to ochre, and a
    # char-dark one. It was drawn from the palette's mid and light greys (sRGB 0.56 across the
    # atlas), and on the black soil every tuft read as white litter scattered over the ground.
    greys = [pal.tint(P.lin("#5f5a50"), "mid", 0.3), pal.tint(P.lin("#6e604a"), "earth", 0.25),
             pal.tint(P.lin("#86683a"), "earth", 0.2), pal.tint(P.lin("#433f39"), "dark", 0.25)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], greys, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 1024, blades=70, width=0.012, lean=0.55,
                          tip_taper=0.95, roughness=0.9, bend=0.85)
    mat = _mat(ctx["out_dir"], "%s_greygrass_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.25, 0.45))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 5), width=h * 1.6,
                   height=h, radius=h * 0.3, bow=0.18, tilt=20)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def meadow_grass(pal, rng, params, variant, ctx):
    """Meadow: long grass gone to seed, knee high and a stride across. A grass clump is a tuft a
    hand across, and scattered over a field at any count a machine can draw it read as single
    strands on a lawn; a field of this reads as a meadow at a tenth of the count."""
    greens = [pal.tint(P.lin("#5f8a3c"), "green", 0.45),
              pal.tint(P.lin("#86a24c"), "green", 0.30),
              pal.tint(P.lin("#b9a05a"), "warm", 0.35),
              pal.tint(P.lin("#6f9446"), "green", 0.4)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], greens, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 1024, blades=120, width=0.009, lean=0.5,
                          seed_head=pal.tint(P.lin("#c9aa62"), "warm", 0.4), bend=0.9,
                          tip_color=pal.tint(P.lin("#c2ad6a"), "warm", 0.3))
    mat = _mat(ctx["out_dir"], "%s_meadow_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.55, 0.85))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 11), width=h * 1.9,
                   height=h, radius=h * 0.85, bow=0.16, tilt=16)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def marram(pal, rng, params, variant, ctx):
    """Marram on the dunes: stiff grey-green blades rolled to a point, a straw-dead one in three,
    standing up out of the sand in a tussock wider than it is tall. It is what holds a dune, and
    what a dune is seen by: the crest combed pale by the wind, the slack below it bare."""
    cols = [pal.tint(P.lin("#8a9a7a"), "mid", 0.25), pal.tint(P.lin("#a3ad86"), "light", 0.2),
            pal.tint(P.lin("#c2b184"), "warm", 0.25), pal.tint(P.lin("#6f7f62"), "green", 0.2)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, blades=34, width=0.022, lean=0.42,
                          tip_taper=0.95, bend=0.35, roughness=0.82)
    mat = _mat(ctx["out_dir"], "%s_marram_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.6, 0.9))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 8), width=h * 1.4,
                   height=h, radius=h * 0.35, bow=0.08, tilt=22)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def sedge_tussock(pal, rng, params, variant, ctx):
    """A tussock of sedge on the marsh: a knee-high fountain of arching leaves from one crown, green
    over last year's dead straw. The fen is walked from one to the next."""
    cols = [pal.tint(P.lin("#5d7a3a"), "green", 0.35), pal.tint(P.lin("#7c8f45"), "green", 0.3),
            pal.tint(P.lin("#a98f5a"), "warm", 0.3), pal.tint(P.lin("#8b7a4e"), "earth", 0.25)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, blades=40, width=0.026, lean=0.7,
                          tip_taper=0.9, bend=1.3)
    mat = _mat(ctx["out_dir"], "%s_sedge_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.45, 0.7))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 10), width=h * 1.3,
                   height=h, radius=h * 0.16, bow=0.3, tilt=34)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def wrack(pal, rng, params, variant, ctx):
    """Wrack along the tide line: bladder- and serrated wrack torn off the rocks and left by the
    sea in a dark olive-brown drift, lying flat on the sand and the shingle."""
    # broad straps, tangled and lying every way: drawn as wide blades bent over on themselves,
    # olive to rust-brown, and laid flat
    # (wet weed is near black; the ochre it dries to is only at the tips of the oldest)
    cols = [P.lin("#2a2712"), P.lin("#332c14"), P.lin("#3d3317"), P.lin("#23261a"),
            pal.tint(P.lin("#4e4020"), "earth", 0.1)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, blades=14, width=0.05, lean=0.9,
                          tip_taper=0.55, bend=1.5, roughness=0.35)
    mat = _mat(ctx["out_dir"], "%s_wrack_foliage" % ctx["name"], names, threshold=0.45)
    ob = flat_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 6),
                    size=params.get("size", rng.uniform(0.5, 0.8)), spread=0.7, jitter_z=0.03)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"]}


def barley_tuft(pal, rng, params, variant, ctx):
    cols = [pal.tint(P.lin("#c9a24a"), "warm", 0.5), pal.tint(P.lin("#dcc06a"), "light", 0.35),
            pal.tint(P.lin("#8f7a34"), "earth", 0.3)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 1024, blades=46, width=0.012, lean=0.25,
                          seed_head=pal.tint(P.lin("#e0c274"), "warm", 0.4), bend=0.9)
    mat = _mat(ctx["out_dir"], "%s_barley_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.7, 1.0))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 5), width=h * 0.9,
                   height=h, radius=h * 0.16, bow=0.05, tilt=8)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def reeds(pal, rng, params, variant, ctx):
    cols = [pal.tint(P.lin("#7f8a46"), "green", 0.35), pal.tint(P.lin("#c9b26a"), "accent", 0.4),
            pal.tint(P.lin("#4f6a44"), "dark", 0.25)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, blades=16, width=0.024, lean=0.24,
                          tip_taper=0.8, bend=1.1)
    mat = _mat(ctx["out_dir"], "%s_reed_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(1.3, 2.0))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 6), width=h * 0.55,
                   height=h, radius=h * 0.12, bow=0.06, tilt=10)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def bulrush(pal, rng, params, variant, ctx):
    cols = [pal.tint(P.lin("#6f8a4a"), "green", 0.3), pal.tint(P.lin("#93a05a"), "accent", 0.25)]
    names = T.blade_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], cols, seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, blades=12, width=0.028, lean=0.16,
                          tip_taper=0.7, bend=1.2, seed_head=P.lin("#4a3524"))
    mat = _mat(ctx["out_dir"], "%s_bulrush_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(1.5, 2.2))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 5), width=h * 0.45,
                   height=h, radius=h * 0.1, bow=0.04, tilt=7)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["grass_blades"]}


def fern(pal, rng, params, variant, ctx):
    names = T.frond_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                          pal.tint(P.lin("#3d6a2a"), "green", 0.4), seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, fronds=6, pinnae=15, shape="lance", curl=0.5)
    mat = _mat(ctx["out_dir"], "%s_fern_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.45, 0.75))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 7), width=h * 1.15,
                   height=h, radius=h * 0.26, bow=0.22, tilt=16)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"]}


def bracken(pal, rng, params, variant, ctx):
    names = T.frond_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                          pal.tint(P.lin("#5a6a26"), "green", 0.3), seed=rng.randrange(9999),
                          size=256 if ctx["quick"] else 512, fronds=6, pinnae=13, shape="toothed",
                          curl=0.35, tip_color=pal.tint(P.lin("#8c4a2a"), "warm", 0.4))
    mat = _mat(ctx["out_dir"], "%s_bracken_foliage" % ctx["name"], names)
    h = params.get("height", rng.uniform(0.6, 0.95))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 5), width=h * 1.5,
                   height=h, radius=h * 0.25, bow=0.3, tilt=20)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"]}


def _flower(pal, rng, params, ctx, leaf_hex, flower_hex, form, second_hex=None, height=(0.35, 0.6),
            stems=7, leaf_shape="lance", tag="flower", cards=5, bow=0.12, eye_hex=None):
    names = T.flower_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], P.lin(leaf_hex), P.lin(flower_hex),
                           seed=rng.randrange(9999), size=256 if ctx["quick"] else 512, form=form,
                           stems=stems, leaf_shape=leaf_shape,
                           second_color=P.lin(second_hex) if second_hex else None,
                           eye_color=P.lin(eye_hex) if eye_hex else None)
    mat = _mat(ctx["out_dir"], "%s_%s_foliage" % (ctx["name"], tag), names)
    h = params.get("height", rng.uniform(*height))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", cards),
                   width=h * 1.1, height=h, radius=h * 0.2, bow=bow, tilt=12)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"]}


def foxglove(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#3d6a2a", "#a45a9a", "spike", second_hex="#c98ab8",
                   height=(0.9, 1.35), stems=5, tag="foxglove")


def poppy(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#5f7a3a", "#b23a2e", "head", height=(0.4, 0.62),
                   stems=8, leaf_shape="fern", tag="poppy")


def buttercup(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#4f7a34", "#e8c21e", "head", height=(0.3, 0.5),
                   stems=11, leaf_shape="fern", tag="buttercup", cards=5)


def oxeye_daisy(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#4f7a34", "#f0ece0", "head", eye_hex="#e0b22a",
                   height=(0.42, 0.68), stems=9, leaf_shape="lance", tag="daisy", cards=5)


def red_poppy_single(pal, rng, params, variant, ctx):
    """Cinderlea's one red poppy per square kilometre (WORLD_BIBLE §6.6)."""
    return _flower(pal, rng, params, ctx, "#6a6a52", "#c0261c", "head", height=(0.3, 0.42),
                   stems=1, leaf_shape="fern", tag="poppy", cards=3)


def cow_parsley(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#4f7a34", "#efe7d2", "umbel", height=(0.8, 1.2),
                   stems=6, leaf_shape="fern", tag="parsley", bow=0.18)


def heather(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#4a5b3a", "#6e4a8a", "spike", second_hex="#a06ab0",
                   height=(0.22, 0.38), stems=13, leaf_shape="needle", tag="heather", cards=6, bow=0.25)


def marsh_marigold(pal, rng, params, variant, ctx):
    return _flower(pal, rng, params, ctx, "#3f7a52", "#e8a93f", "head", height=(0.25, 0.4),
                   stems=7, leaf_shape="round", tag="marigold", bow=0.22)


def briar_vine(pal, rng, params, variant, ctx):
    """Thorn vines thick as arms (WORLD_BIBLE §6.4): a woody arch plus leaf cards."""
    wood = M.by_name("oak_bark", pal, age=0.8, tint=0.3)
    span = params.get("span", rng.uniform(1.8, 3.2))
    parts = []
    for i in range(rng.randint(2, 4)):
        pts = []
        n = 9
        rise = span * rng.uniform(0.35, 0.65)
        phase = rng.uniform(0, math.tau)
        for k in range(n + 1):
            t = k / n
            a = math.pi * t
            pts.append((math.cos(a + phase * 0.1) * span * 0.5 * (1 + 0.1 * math.sin(t * 6)),
                        math.sin(phase) * span * 0.18 * math.sin(t * math.pi * 1.5),
                        math.sin(a) * rise))
        r = span * rng.uniform(0.016, 0.03)
        v = S.tube_along("vine_%d" % i, pts, radius=r, segments=6, radius_end=r * 0.55, mat=wood)
        v.rotation_euler = Euler((0, 0, rng.uniform(0, math.tau)))
        S.apply_transforms(v)
        parts.append(v)
        # thorns
        for k in range(rng.randint(6, 12)):
            t = rng.random()
            idx = min(n, int(t * n))
            base = Vector(pts[idx])
            th = S.cylinder("thorn", radius=r * 0.45, radius_top=0.0, depth=r * 2.6, vertices=5,
                            location=base, rotation=(rng.uniform(-70, 70), rng.uniform(-70, 70), 0), mat=wood)
            th.rotation_euler.rotate(Euler((0, 0, v.rotation_euler.z)))
            S.apply_transforms(th)
            parts.append(th)
    names = T.leaf_cluster_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                                 pal.tint(P.lin("#2f5226"), "green", 0.3), shapes=("toothed", "oval"),
                                 seed=rng.randrange(9999), size=256 if ctx["quick"] else 512,
                                 leaves_per_cell=45, leaf_scale=0.16, lobes=3, spread=0.3)
    mat = _mat(ctx["out_dir"], "%s_briar_foliage" % ctx["name"], names)
    leafcards = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 8),
                          width=span * 0.28, height=span * 0.26, radius=span * 0.35, bow=0.0,
                          tilt=30, anchor_bottom=False)
    for v in leafcards.data.vertices:
        v.co.z += span * 0.3
    return {"opaque_objs": parts, "card_objs": [leafcards], "collision": "trimesh",
            "materials_used": ["oak_bark", "foliage_leaf_card"]}


def bracket_fungus(pal, rng, params, variant, ctx):
    names = T.bracket_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                            pal.tint(P.lin("#b09258"), "warm", 0.3),
                            rim_color=pal.tint(P.lin("#e8dcc0"), "light", 0.3),
                            seed=rng.randrange(9999), size=128 if ctx["quick"] else 256)
    mat = _mat(ctx["out_dir"], "%s_fungus_foliage" % ctx["name"], names, threshold=0.5)
    ob = shelf_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 5),
                     size=params.get("size", rng.uniform(0.3, 0.5)), height=params.get("height", 1.4),
                     radius=params.get("radius", 0.42))
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"],
            "extra_meta": {"attaches_to": "trunk"}}


def hanging_moss(pal, rng, params, variant, ctx):
    names = T.moss_strand_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                                pal.tint(P.lin("#7d8a5a"), "green", 0.4), seed=rng.randrange(9999),
                                size=128 if ctx["quick"] else 256)
    mat = _mat(ctx["out_dir"], "%s_moss_foliage" % ctx["name"], names, threshold=0.4)
    h = params.get("height", rng.uniform(1.2, 2.4))
    ob = fan_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 4), width=h * 0.5,
                   height=h, radius=h * 0.14, bow=0.0, tilt=6)
    for v in ob.data.vertices:
        v.co.z -= h  # hangs down from its origin
    return {"card_objs": [ob], "collision": "none", "materials_used": ["moss"],
            "extra_meta": {"hangs": True}}


def moss_patch(pal, rng, params, variant, ctx):
    """A ground/rock moss patch: a flat mesh with the moss material baked on."""
    mat = M.moss(pal, age=0.2 + 0.4 * rng.random())
    r = params.get("radius", rng.uniform(0.5, 0.9))
    ob = S.plane("%s_patch" % ctx["name"], size=(r * 2, r * 2), subdiv=10, mat=mat)
    for v in ob.data.vertices:
        d = math.hypot(v.co.x, v.co.y) / r
        v.co.z = max(0.0, (1.0 - d * d)) * r * 0.12 + rng.uniform(-0.004, 0.004)
    S.shade_smooth(ob, 40.0)
    return {"opaque_objs": [ob], "collision": "none", "materials_used": ["moss"]}


def waterlily_pad(pal, rng, params, variant, ctx):
    names = T.pad_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"],
                        pal.tint(P.lin("#3f6a3a"), "green", 0.35),
                        flower_color=pal.tint(P.lin("#f1ece0"), "light", 0.3),
                        seed=rng.randrange(9999), size=128 if ctx["quick"] else 256)
    mat = _mat(ctx["out_dir"], "%s_lily_foliage" % ctx["name"], names, threshold=0.5)
    ob = flat_cards("%s_cards" % ctx["name"], mat, rng, count=params.get("cards", 4),
                    size=params.get("size", rng.uniform(0.6, 1.0)), spread=0.45, jitter_z=0.015)
    return {"card_objs": [ob], "collision": "none", "materials_used": ["foliage_leaf_card"],
            "extra_meta": {"floats": True}}


def lichen_crust(pal, rng, params, variant, ctx):
    """A flat crust for limestone pavements: no cards, just a painted disc."""
    mat = M.moss(pal, age=0.8, tint=0.15, name="lichen")
    r = params.get("radius", rng.uniform(0.35, 0.7))
    ob = S.plane("%s_crust" % ctx["name"], size=(r * 2, r * 2), subdiv=6, mat=mat)
    for v in ob.data.vertices:
        v.co.z = rng.uniform(0.0, 0.006)
    return {"opaque_objs": [ob], "collision": "none", "materials_used": ["moss"]}


KINDS = {
    "grass_clump": grass_clump,
    "grey_grass": grey_grass,
    "barley_tuft": barley_tuft,
    "meadow_grass": meadow_grass,
    "marram": marram,
    "sedge_tussock": sedge_tussock,
    "wrack": wrack,
    "buttercup": buttercup,
    "oxeye_daisy": oxeye_daisy,
    "reeds": reeds,
    "bulrush": bulrush,
    "fern": fern,
    "bracken": bracken,
    "foxglove": foxglove,
    "poppy": poppy,
    "red_poppy_single": red_poppy_single,
    "cow_parsley": cow_parsley,
    "heather": heather,
    "marsh_marigold": marsh_marigold,
    "briar_vine": briar_vine,
    "bracket_fungus": bracket_fungus,
    "hanging_moss": hanging_moss,
    "moss_patch": moss_patch,
    "waterlily_pad": waterlily_pad,
    "lichen_crust": lichen_crust,
}


def main():
    """Flora needs the output directory while building (the atlases are drawn there), so it
    uses its own main rather than the shared runner."""
    import random

    from lib import export as E

    args = cli.parse("Wickmere flora generator")
    if args.list:
        for k in sorted(KINDS):
            print(k)
        return
    kind = args.kind or "grass_clump"
    if kind not in KINDS:
        raise SystemExit("unknown kind %r; --list shows them" % kind)
    pal = P.get_palette(args.palette)
    seed = cli.derive_seed(args.seed, args.variant_index, kind)
    name = args.name or cli.default_name(pal.short, kind, args.variant)
    cli.validate_name(name)
    S.reset()
    rng = random.Random(seed)
    category = args.category or "flora"
    out_dir = cli.asset_dir(args.out, category, name)
    ctx = {"out_dir": out_dir, "name": name, "quick": args.quick, "pal": pal}
    spec = KINDS[kind](pal, rng, dict(args.params), args.variant_index, ctx)
    extra = spec.get("extra_meta") or {}
    ground = not (extra.get("hangs") or extra.get("floats") or extra.get("attaches_to"))
    E.finish_asset(ground=ground, out_root=args.out, category=category, name=name, generator="gen_flora",
                   seed=args.seed, kind=kind, params=dict(args.params), pal=pal, quick=args.quick,
                   res=args.res, write_import=not args.no_import_files, rng=rng,
                   card_keep=(0.6, 0.35), **spec)


if __name__ == "__main__":
    main()
