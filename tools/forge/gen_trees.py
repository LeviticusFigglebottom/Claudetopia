"""Trees keyed by region flora (WORLD_BIBLE §6, regions.json identity.flora).

    blender -b --python tools/forge/gen_trees.py -- --kind oak --palette hearthvale --seed 1 --variant a
    ... --params '{"age": "sapling"}'      # or "veteran"; "mature" is the default

Species: hearthvale oak / apple / hawthorn / yew; briarwold giant_oak / black_ash;
skerrow hardy_pine / rowan / juniper; sedgemire willow / alder; cinderlea dead_ash_tree /
char_stump; brightwater willow_pollard / lime.

Each tree is grown as whole wood by lib/grow.py -- the species' own habit and crown, every
branch one tapered tube from inside its parent to a point -- with a tiling bark painted for the
species (lib/bark.py), and leaf-clump cards on its finest twigs mapped into the species' leaf
atlas, the sunlit row for clumps on the crown's rim and the shaded row for clumps inside it.
LOD1 is the same tree with whole twigs taken away and fewer sides; LOD2 is the impostor
(gen_impostors.py draws the final one).

A species' bark and leaf maps are shared by all its variants, in
`trees/_species/<region>_<kind>/`: one set of maps per species, not one per tree.
"""
from __future__ import annotations

import math
import os
import random
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

from lib import bark as BK  # noqa: E402
from lib import cli  # noqa: E402
from lib import export as E  # noqa: E402
from lib import grow as G  # noqa: E402
from lib import impostor as IMP  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib import textures as T  # noqa: E402
from lib import tree as TR  # noqa: E402


# --- species table -----------------------------------------------------------------------------
# The look of each species' leaves (the atlas) and its size. Its form -- habit, crown, branching --
# is lib/grow.FORMS; its bark is lib/bark.STYLES.
SPECIES = {
    # ---- Hearthvale -----------------------------------------------------------------------------
    "oak": dict(height=(8.5, 12.0), leaf_hex="#4a7630", leaf_shapes=("lobed", "oval", "lobed"),
                leaf_scale=0.30, autumn_hex="#8f7a30", autumn=0.05),
    "apple": dict(height=(4.2, 5.6), leaf_hex="#5a8636", leaf_shapes=("oval", "oval", "round"), leaf_scale=0.28,
                  fruit_hex="#b23a2e", fruit_r=0.030, fruit_count=6),
    "hawthorn": dict(height=(3.6, 5.2), leaf_hex="#3f6b2a", leaf_shapes=("toothed", "lobed"), leaf_scale=0.24,
                     fruit_hex="#96241f", fruit_r=0.018, fruit_count=9),
    "yew": dict(height=(5.0, 7.5), leaf_hex="#23452a", leaf_shapes=("needle", "lance"), leaf_scale=0.2,
                fruit_hex="#a8301f", fruit_r=0.013, fruit_count=5, flat=0.12),
    # ---- Briarwold ------------------------------------------------------------------------------
    "giant_oak": dict(height=(26.0, 34.0), leaf_hex="#2f5724", leaf_shapes=("lobed", "oval", "lobed"),
                      leaf_scale=0.28, moss=90, tier="hero"),
    "black_ash": dict(height=(14.0, 19.0), leaf_hex="#3d6429", leaf_shapes=("lance", "toothed"), leaf_scale=0.26,
                      moss=20),
    # ---- Skerrow --------------------------------------------------------------------------------
    "hardy_pine": dict(height=(9.0, 13.5), leaf_hex="#2d4c31", leaf_shapes=("needle", "needle", "lance"),
                       leaf_scale=0.22, flat=0.25),
    "rowan": dict(height=(5.5, 7.8), leaf_hex="#4b7236", leaf_shapes=("toothed", "lance"), leaf_scale=0.22,
                  fruit_hex="#c03418", fruit_r=0.016, fruit_count=12),
    "juniper": dict(height=(1.6, 2.6), leaf_hex="#35523b", leaf_shapes=("needle", "needle"), leaf_scale=0.2,
                    fruit_hex="#3f4a6a", fruit_r=0.012, fruit_count=8, shrub=True),
    # ---- Sedgemire ------------------------------------------------------------------------------
    "willow": dict(height=(7.5, 11.0), leaf_hex="#6a8a40", leaf_shapes=("lance", "lance", "needle"),
                   leaf_scale=0.2, droop=40.0, weep=dict(count=320, length=(1.8, 3.8), width=(0.9, 1.4))),
    "alder": dict(height=(6.5, 9.5), leaf_hex="#3d6636", leaf_shapes=("round", "oval"), leaf_scale=0.26,
                  fruit_hex="#4a3a28", fruit_r=0.014, fruit_count=7),
    # the lowland trees every region's wood edges share (the scatter lends them across regions)
    "birch": dict(height=(9.0, 14.0), leaf_hex="#6f9a3e", leaf_shapes=("oval", "toothed"), leaf_scale=0.18,
                  autumn_hex="#c9a933", autumn=0.08, droop=20.0),
    "hazel": dict(height=(3.5, 5.5), leaf_hex="#557f32", leaf_shapes=("round", "oval"), leaf_scale=0.28,
                  shrub=True),
    # ---- Cinderlea ------------------------------------------------------------------------------
    "dead_ash_tree": dict(height=(7.0, 11.5), leaf_hex=None),
    "char_stump": dict(height=(1.5, 2.6), leaf_hex=None, budget="small"),
    # ---- Brightwater ----------------------------------------------------------------------------
    "willow_pollard": dict(height=(3.8, 5.2), leaf_hex="#6a8a3e", leaf_shapes=("lance", "needle"), leaf_scale=0.2),
    "lime": dict(height=(9.0, 13.0), leaf_hex="#588a38", leaf_shapes=("heart", "heart", "round"), leaf_scale=0.28),
}

# Which region each species belongs to (used by the manifest and for sanity checks).
REGION_OF = {
    "oak": "hearthvale", "apple": "hearthvale", "hawthorn": "hearthvale", "yew": "hearthvale",
    "giant_oak": "briarwold", "black_ash": "briarwold",
    "hardy_pine": "skerrow", "rowan": "skerrow", "juniper": "skerrow",
    "willow": "sedgemire", "alder": "sedgemire",
    "dead_ash_tree": "cinderlea", "char_stump": "cinderlea",
    "willow_pollard": "brightwater", "lime": "brightwater",
    "birch": "hearthvale", "hazel": "hearthvale",
}

# Budgets, unchanged from the Sapling trees they replace: the wood at LOD0 (DESIGN §7.0), and
# LOD1 split between wood and canopy -- the rung that decides what a wooded region costs.
TRUNK_BUDGET = {"normal": 4200, "hero": 3800, "small": 4200}
LOD1_TRUNK_TRIS = 900
LOD1_CARD_TRIS = 420
CARDS_BIG = 1150     # trees over 6 m
CARDS_SMALL = 760    # shrubs and small trees
LEAVES_PER_CELL = 230
# The sunlit and the shaded row of a leaf atlas, as multipliers on the species' green: warm and
# bright on the rim of the crown, cool and dark inside it. A painted tree is lit as one mass.
SUN_TONE = (1.18, 1.14, 0.9)
SHADE_TONE = (0.68, 0.74, 0.82)


def species_dir(out_root, kind: str, pal) -> Path:
    return Path(out_root) / "trees" / "_species" / ("%s_%s" % (pal.short, kind))


def _publish(src_dir: Path, dst_dir: Path, names: dict) -> None:
    """Halve the normal map (as the baked assets do: at a tree's distances its detail is the
    albedo's), then move freshly drawn maps into the shared folder by rename, so two variants building at once
    never leave a half-written file there (they draw the same bytes from the same seed)."""
    dst_dir.mkdir(parents=True, exist_ok=True)
    from PIL import Image
    if "normal" in names:
        p = src_dir / names["normal"]
        with Image.open(p) as im:
            half = im.resize((max(64, im.size[0] // 2),) * 2, Image.LANCZOS)
        half.save(p, optimize=True)
    for f in names.values():
        tmp = dst_dir / (".%s.%d" % (f, os.getpid()))
        shutil.copyfile(src_dir / f, tmp)
        os.replace(tmp, dst_dir / f)


def species_maps(out_root, kind: str, spec: dict, pal, quick: bool) -> dict:
    """Paint (or repaint) the species' shared bark and leaf maps; returns their names by role."""
    d = species_dir(out_root, kind, pal)
    stem = "%s_%s" % (pal.short, kind)
    seed = cli.derive_seed(7, 0, stem)
    out = {}
    size = 256 if quick else 512
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        earth = P.linear_to_srgb(pal.role("earth"))
        names = BK.write(tdp, "%s_bark" % stem, kind, size=size, seed=seed, tint=earth)
        _publish(tdp, d, names)
        out["bark"] = names
        if spec.get("leaf_hex"):
            green = pal.tint(P.lin(spec["leaf_hex"]), "green", 0.18)
            names = T.leaf_cluster_atlas(
                tdp, "%s_leaf" % stem, green, shapes=spec.get("leaf_shapes", ("oval",)), seed=seed + 1,
                size=size, cells=2, leaves_per_cell=int(LEAVES_PER_CELL * (0.45 if quick else 1.0)),
                leaf_scale=spec.get("leaf_scale", 0.25) * 0.42,
                autumn=P.lin(spec["autumn_hex"]) if spec.get("autumn_hex") else None,
                autumn_amount=spec.get("autumn", 0.0),
                fruit=P.lin(spec["fruit_hex"]) if spec.get("fruit_hex") else None,
                fruit_r=spec.get("fruit_r", 0.0), fruit_count=spec.get("fruit_count", 0),
                droop=0.25 if spec.get("droop") else 0.0, row_tones=[SUN_TONE, SHADE_TONE])
            _publish(tdp, d, names)
            out["leaf"] = names
            if spec.get("weep"):
                names = T.leaf_strand_atlas(tdp, "%s_weep" % stem, green, seed=seed + 2, size=size, strands=11,
                                            leaf_scale=0.075,
                                            row_tones=[SUN_TONE, SHADE_TONE])
                _publish(tdp, d, names)
                out["weep"] = names
            if spec.get("moss"):
                names = T.moss_strand_atlas(tdp, "%s_moss" % stem, pal.tint(P.lin("#7d8a5a"), "green", 0.35),
                                            seed=seed + 3, size=256)
                _publish(tdp, d, names)
                out["moss"] = names
    return {role: {slot: "../_species/%s/%s" % (d.name, f) for slot, f in names.items()}
            for role, names in out.items()}, d


def _mat(kind: str, name: str, names: dict, species: Path, foliage: bool):
    files = {k: species / Path(v).name for k, v in names.items()}
    if foliage:
        m = M.foliage_material(name, files["albedo"], files["normal"], files["orm"])
    else:
        m = M.image_material(name, files["albedo"], files["normal"], files["orm"], roughness=0.85)
    m["forge_textures"] = dict(names)
    return m


def build_tree(kind: str, pal, rng, params: dict, variant: int, out_root, name: str, quick: bool, seed: int):
    spec = dict(SPECIES[kind])
    form = G.FORMS[kind]
    age = str(params.get("age", "mature"))
    if age not in G.AGES:
        raise SystemExit("unknown age %r (have %s)" % (age, ", ".join(G.AGES)))
    h0, h1 = spec["height"]
    height = float(params.get("height_m") or rng.uniform(h0, h1) * G.AGES[age]["height"])
    tree = G.grow(kind, seed, height, age)
    tier = spec.get("tier") or spec.get("budget") or "normal"
    sides = G.SIDES["hero" if tier == "hero" else "small" if height < 4.0 else "normal"]
    budget = int(TRUNK_BUDGET.get(tier, 4200) // (3 if quick else 1))
    keep0 = G.trim(tree.branches, budget, sides)
    kept0 = set(keep0)
    keep1 = [i for i in G.trim(tree.branches, LOD1_TRUNK_TRIS, G.SIDES["lod1"], stride=2) if i in kept0]
    maps, sdir = species_maps(out_root, kind, spec, pal, quick)
    bark_w = form.get("bark_w", 0.5)
    bark_mat = _mat(kind, "%s_bark" % name, maps["bark"], sdir, foliage=False)
    rank_of = {bi: k for k, bi in enumerate(G.drop_order(tree.branches))}
    V, N, UV, Tr, R = G.wood_mesh(tree, keep0, sides, bark_w)
    wood = TR.wood_object(name, V, N, UV, Tr, [rank_of[int(b)] for b in R], bark_mat)
    V1, N1, UV1, T1, R1 = G.wood_mesh(tree, keep1, G.SIDES["lod1"], bark_w, stride=2)
    wood1 = TR.wood_object("%s_LOD1" % name, V1, N1, UV1, T1, [rank_of[int(b)] for b in R1], bark_mat)

    cards = []
    textures = {"bark": maps["bark"]}
    lrng = np.random.default_rng(seed + 11)
    if spec.get("leaf_hex") and form.get("leaf"):
        target = int((CARDS_BIG if height > 6 else CARDS_SMALL) * (0.55 if age == "sapling" else 1.0)
                     * (0.35 if quick else 1.0))
        if spec.get("weep"):
            target = int(target * 0.6)
        pts, axes, sizes, expo = G.leaf_points(tree, keep0, form, lrng, target)
        # nothing grows out of the soil: a clump that would bury its card in the grass goes
        ok = pts[:, 2] - sizes * 0.45 > (0.02 if spec.get("shrub") else min(0.6, height * 0.08))
        pts, sizes, expo = pts[ok], sizes[ok], expo[ok]
        leaf_mat = _mat(kind, "%s_leaf" % name, maps["leaf"], sdir, foliage=True)
        textures["leaf"] = maps["leaf"]
        shape, R_, z0, z1, cxy = tree.crown
        centre = (cxy[0], cxy[1], z0 + (z1 - z0) * 0.45)
        c = TR.clump_cards("%s_leaves" % name, leaf_mat, pts, sizes, expo, rng, centre,
                           droop_deg=spec.get("droop", 0.0), flat=spec.get("flat", 0.0))
        if c:
            cards.append(c)
        if spec.get("weep") and not quick:
            # the curtain: strands of leaves hanging from the whips, longest at the crown's rim
            w = dict(spec["weep"])
            hang = [b for i, b in enumerate(tree.branches) if i in kept0 and b.hang]
            anchors = []
            for b in hang:
                for u in np.linspace(0.35, 1.0, 4):
                    k = min(len(b.pts) - 1, int(u * (len(b.pts) - 1)))
                    anchors.append(b.pts[k])
            rng.shuffle(anchors)
            anchors = anchors[:w["count"]]
            weep_mat = _mat(kind, "%s_weep" % name, maps["weep"], sdir, foliage=True)
            textures["weep"] = maps["weep"]
            rows = [1 if rng.random() < 0.55 else 0 for _ in anchors]
            curtain = TR.hanging_cards([(a, None) for a in anchors], "%s_weep" % name, weep_mat, rng,
                                       length=w["length"], width=w["width"], sway=0.08, rows=rows)
            if curtain:
                # no strand reaches into the ground
                for v in curtain.data.vertices:
                    v.co.z = max(v.co.z, 0.35)
                cards.append(curtain)
        if spec.get("moss") and not quick and age != "sapling":
            limbs = [b for i, b in enumerate(tree.branches) if i in kept0 and b.level in (1, 2) and not b.root]
            anchors = []
            for _ in range(int(spec["moss"])):
                b = limbs[rng.randrange(len(limbs))]
                k = rng.randrange(len(b.pts))
                anchors.append((b.pts[k] - np.array([0, 0, b.radii[k]]), None))
            moss_mat = _mat(kind, "%s_moss" % name, maps["moss"], sdir, foliage=True)
            textures["moss"] = maps["moss"]
            beard = TR.hanging_cards(anchors, "%s_mossbeard" % name, moss_mat, rng, cells=2,
                                     length=(0.8, 2.6) if height > 20 else (0.4, 1.2),
                                     width=(0.4, 1.0) if height > 20 else (0.25, 0.5), sway=0.1)
            if beard:
                cards.append(beard)
    trunk_r = G.trunk_radius_at(tree, 1.0)
    return wood, wood1, cards, textures, height, spec, tree, trunk_r


def main():
    args = cli.parse("Wickmere tree generator")
    if args.list:
        for k in sorted(SPECIES):
            print("%s (%s)" % (k, REGION_OF.get(k, "-")))
        return
    kind = args.kind or "oak"
    if kind not in SPECIES:
        raise SystemExit("unknown species %r; --list shows them" % kind)
    pal = P.get_palette(args.palette or REGION_OF.get(kind))
    seed = cli.derive_seed(args.seed, args.variant_index, kind)
    name = args.name or cli.default_name(pal.short, kind, args.variant)
    cli.validate_name(name)
    S.reset()
    rng = random.Random(seed)
    category = args.category or "trees"
    out_dir = cli.asset_dir(args.out, category, name)
    wood, wood1, cards, textures, height, spec, tree, trunk_r = build_tree(
        kind, pal, rng, dict(args.params), args.variant_index, Path(args.out), name, args.quick, seed)

    # Settle the tree on the ground here, not in finish_asset: its roots go a little under the
    # surface (so it stands on a slope without a gap) and finish_asset would lift them out.
    lo = min(v.co.z for v in wood.data.vertices)
    lift = -0.5 - lo if lo < -0.5 else 0.0
    for o in [wood, wood1] + cards:
        o.location.z += lift
        S.apply_transforms(o)

    lod2, impostor_tex = None, None
    if not args.quick and args.params.get("impostor", True):
        # A stand-in picture for LOD2 until gen_impostors draws the tree from eight sides.
        lod2, impostor_tex = IMP.crossed_cards([wood] + cards, out_dir, "%s_impostor" % name, name,
                                               size=512 if height > 12 else 256,
                                               samples=16, cards=4)
    card_tris = sum(S.tri_count(o) for o in cards) or 1
    lod1_cards = min(0.5, max(0.04, LOD1_CARD_TRIS / card_tris))
    bark_tex = textures["bark"]
    meta = E.finish_asset(
        out_root=args.out, category=category, name=name, generator="gen_trees",
        seed=args.seed, kind=kind, params=dict(args.params), pal=pal, opaque_objs=None,
        card_objs=cards or None, baked_objs=[(wood, bark_tex, [wood1])], collision="capsule",
        collision_params={"radius": round(max(0.12, trunk_r * 1.05), 3), "height": round(height, 2)},
        quick=args.quick, tier=spec.get("tier"), rng=rng, smooth_angle=180.0,
        lod_ratios=(0.2,), card_keep=(lod1_cards,), impostor=lod2, impostor_textures=impostor_tex,
        materials_used=["%s_bark" % kind, "foliage_leaf_card"], ground=False,
        extra_meta={"species": kind, "region": REGION_OF.get(kind, ""), "height_m": round(height, 2),
                    "age": str(args.params.get("age", "mature")),
                    "grown": {"generator": "tools/forge/lib/grow.py", "seed": seed,
                              "branches": len(tree.branches)}})
    # the shared maps' sidecars are written with the tree's (write_import_sidecars normalises
    # the ../_species path), so the shared folder imports like any other
    return meta


if __name__ == "__main__":
    main()
