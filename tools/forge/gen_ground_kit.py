"""The kit the country is lined with: hedge segments, gate posts and milestones.

    blender -b --python tools/forge/gen_ground_kit.py -- --kind hedge_segment \
        --palette hearthvale --seed 3 --variant a --out game/assets/models

These exist because the landscape's *line-work* is made of things repeated end to end, and
nothing in the forge was cheap enough to repeat. A hedgerow along every field boundary in
Hearthvale is some tens of kilometres of hedge; the nearest asset was `trees/hawthorn` at
5 610 triangles, so a continuous hedge would have cost more than the rest of the world put
together. A hedge segment here is 2.2 m of hedge in about a hundred triangles: a few woody
stems and a run of leaf cards carrying the same drawn atlas the flora uses, so it reads as
one hedge when laid end to end rather than as a row of bushes.

Kinds:

  hedge_segment   2.2 m of hedge, made to be laid end to end along a field boundary
  gate_post       the post at a gap in a hedge, where a track goes through
  milestone       a leaning stone at the roadside, for distances the road already knows

Like `gen_flora`, this uses its own `main()` rather than `lib.runner`, because the drawn
atlases have to be written into the asset's own directory while it is being built.
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

CHUNK = 1.1


def jit(rng, v, pct=0.06):
    return v * rng.uniform(1.0 - pct, 1.0 + pct)


def _foliage_material(out_dir, name, names, threshold=0.42):
    m = M.foliage_material(name, out_dir / names["albedo"], out_dir / names["normal"],
                           out_dir / names["orm"], threshold=threshold)
    m["forge_textures"] = dict(names)
    return m


def _leaf_run(name, mat, rng, length, height, depth, cards=9, cells=2):
    """Leaf cards along a straight run, facing across it and along it.

    The cards are spread down the length rather than rosetted around a point, which is the
    whole difference between a hedge and a bush: laid end to end, the run continues.
    """
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    cell = 1.0 / cells
    corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
    for i in range(cards):
        t = (i + 0.5) / cards
        x = (t - 0.5) * length + rng.uniform(-0.06, 0.06) * length
        # alternate the cards across the hedge's width so it has a body from either side
        y = (rng.uniform(-0.5, 0.5)) * depth
        # cards turn a little off the line so the run is not a flat billboard fence
        head = math.radians(rng.uniform(-38.0, 38.0)) + (0.0 if i % 2 else math.pi)
        w = length / cards * rng.uniform(3.0, 4.2)
        h = height * rng.uniform(0.82, 1.0)
        base = Vector((x, y, 0.0))
        right = Vector((math.cos(head), math.sin(head), 0.0))
        verts = []
        for (u, v) in corners:
            p = base + right * (u * w) + Vector((0.0, 0.0, v * h))
            # the top of a laid hedge is ragged, not a clipped line
            p += Vector((0.0, 0.0, rng.uniform(-0.04, 0.07) * height * v))
            verts.append(bm.verts.new(p))
        f = bm.faces.new(verts)
        cx, cy = rng.randrange(cells), rng.randrange(cells)
        flip = rng.random() < 0.5
        cs = [((1.0 - u - 0.5) if flip else (u + 0.5), v) for (u, v) in corners]
        for loop, (u, v) in zip(f.loops, cs):
            loop[uv].uv = ((cx + u) * cell, (cy + v) * cell)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S.bm_to_object(bm, name, mat, smooth=False)


def hedge_segment(pal, rng, params, variant, ctx):
    """2.2 m of hawthorn hedge: a few stems, a run of leaf cards, and a ragged top."""
    length = float(params.get("length", 2.2))
    height = jit(rng, float(params.get("height", 1.75)))
    depth = jit(rng, float(params.get("depth", 0.85)))
    wood = M.oak_bark(pal, age=0.7, tint=0.25, scale=0.5, name="hedge_wood")
    parts = []
    # Stems: thin, leaning, and stopping short of the top, so the leaf run sits on woody
    # growth rather than floating. Three of them at 8 sides is 96 triangles' worth of trunk
    # before decimation, which is the whole budget this asset is allowed.
    stems = int(params.get("stems", 3))
    for i in range(stems):
        x = ((i + 0.5) / stems - 0.5) * length * rng.uniform(0.8, 1.0)
        r = length * rng.uniform(0.016, 0.026)
        # Stems stop well inside the leaf mass. At 0.55 to 0.78 of the hedge's height they
        # stood proud of the foliage like a row of bare poles, which is what the first review
        # render showed: a hedge is woody underneath and green on top, and the wood that
        # shows is at the bottom.
        st = S.cylinder("stem_%d" % i, radius=r, radius_top=r * 0.55,
                        depth=height * rng.uniform(0.34, 0.48), vertices=5,
                        location=(x, rng.uniform(-0.12, 0.12) * depth, 0.0), mat=wood)
        st.rotation_euler = Euler((math.radians(rng.uniform(-9, 9)),
                                   math.radians(rng.uniform(-7, 7)), 0.0))
        S.apply_transforms(st)
        for v in st.data.vertices:
            v.co.z += st.dimensions.z * 0.5
        parts.append(st)
    # A hedge is green in every region that has one. Tinting 0.42 of the way to the palette's
    # "green" role bleached Brightwater's hedges white, because that region's six colours are
    # lake blue, lime white, slate, brass, terracotta and deep blue -- it has no green at all,
    # and the role falls back to the nearest thing. A sixth of the way is enough to carry the
    # region's cast without turning hawthorn into limewash.
    greens = pal.tint(P.lin("#38601f"), "green", 0.16)
    names = T.leaf_cluster_atlas(ctx["out_dir"], "%s_atlas" % ctx["name"], greens,
                                 shapes=("toothed", "oval"), seed=rng.randrange(9999),
                                 size=256 if ctx["quick"] else 512, leaves_per_cell=60,
                                 leaf_scale=0.15, lobes=3, spread=0.36,
                                 twig_color=pal.tint(P.lin("#4a3a2a"), "earth", 0.3))
    mat = _foliage_material(ctx["out_dir"], "%s_hedge_foliage" % ctx["name"], names)
    cards = _leaf_run("%s_cards" % ctx["name"], mat, rng, length, height, depth,
                      cards=int(params.get("cards", 12)))
    return {"opaque_objs": parts, "card_objs": [cards], "collision": "none",
            "materials_used": ["oak_bark", "foliage_leaf_card"],
            # the placer lays these end to end and needs to know how much hedge one is
            "extra_meta": {"modular": True, "module_length_m": round(length, 3)}}


def gate_post(pal, rng, params, variant, ctx):
    """The post at a gap in a hedge: squared oak, weathered, with a strap hinge."""
    h = jit(rng, float(params.get("height", 1.35))) * CHUNK
    w = jit(rng, 0.17) * CHUNK
    mat = M.wood_planks(pal, wear=0.6, age=0.7, scale=0.6, plank_len=h, plank_w=w,
                        name="gate_oak")
    metal = M.iron(pal, age=0.7, wear=0.6)
    post = S.cube("post", (w, w, h), (0, 0, 0), mat=mat)
    S.bevel(post, width=0.012, segments=2)
    S.tilt(post, rng, max_deg=3.0)
    parts = [post]
    for z in (h * 0.34, h * 0.72):
        parts.append(S.cube("strap", (w * 1.25, w * 0.22, w * 0.3), (0, 0, z), mat=metal))
    return {"opaque_objs": parts, "collision": "convex",
            "materials_used": ["wood_planks", "iron"]}


def milestone(pal, rng, params, variant, ctx):
    """A leaning stone at the roadside, its face dressed flat for the cutting."""
    h = jit(rng, float(params.get("height", 0.82))) * CHUNK
    w = jit(rng, 0.34) * CHUNK
    d = jit(rng, 0.19) * CHUNK
    stone = M.limestone(pal, wear=0.6, age=0.8, scale=0.5, name="milestone_stone")
    ob = S.cube("stone", (w, d, h), (0, 0, 0), mat=stone)
    # taper the head and round the shoulders: a dressed stone, not a brick
    for v in ob.data.vertices:
        t = (v.co.z + h * 0.5) / h
        v.co.x *= 1.0 - 0.22 * t * t
        v.co.y *= 1.0 - 0.16 * t * t
    S.bevel(ob, width=0.018, segments=2)
    S.jitter_verts(ob, amount=0.006, scale=0.6, seed=rng.randrange(999))
    S.tilt(ob, rng, max_deg=6.0)
    return {"opaque_objs": [ob], "collision": "convex", "materials_used": ["limestone"]}


KINDS = {
    "hedge_segment": hedge_segment,
    "gate_post": gate_post,
    "milestone": milestone,
}


def main():
    import random

    from lib import export as E

    args = cli.parse("Wickmere ground kit generator")
    if args.list:
        for k in sorted(KINDS):
            print(k)
        return
    kind = args.kind or "hedge_segment"
    if kind not in KINDS:
        raise SystemExit("unknown kind %r; --list shows them" % kind)
    pal = P.get_palette(args.palette)
    seed = cli.derive_seed(args.seed, args.variant_index, kind)
    name = args.name or cli.default_name(pal.short, kind, args.variant)
    cli.validate_name(name)
    S.reset()
    rng = random.Random(seed)
    # props, including the hedge: the streamer reads the category for view range and shadow
    # casting, and hedgerow line-work has to read further out than a herb does
    category = args.category or "props"
    out_dir = cli.asset_dir(args.out, category, name)
    ctx = {"out_dir": out_dir, "name": name, "quick": args.quick, "pal": pal}
    spec = KINDS[kind](pal, rng, dict(args.params), args.variant_index, ctx)
    E.finish_asset(ground=True, out_root=args.out, category=category, name=name,
                   generator="gen_ground_kit", seed=args.seed, kind=kind,
                   params=dict(args.params), pal=pal, quick=args.quick, res=args.res,
                   write_import=not args.no_import_files, rng=rng, card_keep=(0.6, 0.35),
                   **spec)


if __name__ == "__main__":
    main()
