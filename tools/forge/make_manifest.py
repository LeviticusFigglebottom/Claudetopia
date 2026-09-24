#!/usr/bin/env python3
"""Regenerate tools/forge/manifest.json from the region/species tables below.

The manifest is committed; this script exists so the set of assets is edited in one
readable place (which species, which regions, how many variants) rather than by hand in
JSON. Seeds are derived from a walking counter so adding a line does not reshuffle the
assets before it.

    python3 tools/forge/make_manifest.py
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

FORGE = Path(__file__).resolve().parent
LETTERS = "abcdefghij"


def region(r: str) -> str:
    return "core:region/%s" % r


# (kind, region, variants, params) ----------------------------------------------------------

TREES = [
    ("oak", "hearthvale", 3, None),
    ("apple", "hearthvale", 3, None),
    ("hawthorn", "hearthvale", 2, None),
    ("yew", "hearthvale", 2, None),
    ("giant_oak", "briarwold", 2, None),
    ("black_ash", "briarwold", 3, None),
    ("hardy_pine", "skerrow", 3, None),
    ("rowan", "skerrow", 2, None),
    ("juniper", "skerrow", 2, None),
    ("willow", "sedgemire", 2, None),
    ("alder", "sedgemire", 2, None),
    ("dead_ash_tree", "cinderlea", 3, None),
    ("char_stump", "cinderlea", 2, None),
    ("willow_pollard", "brightwater", 2, None),
    ("lime", "brightwater", 2, None),
]

ROCKS = [
    ("boulder", "hearthvale", 2, None),
    ("boulder", "briarwold", 2, None),
    ("boulder", "skerrow", 3, None),
    ("boulder", "cinderlea", 2, None),
    ("boulder", "brightwater", 2, None),
    ("boulder", "sedgemire", 2, None),
    ("cliff_slab", "skerrow", 3, None),
    ("cliff_slab", "hearthvale", 2, {"stone": "chalk_rock"}),
    ("cliff_slab", "briarwold", 2, {"stone": "granite"}),
    ("cliff_slab", "cinderlea", 2, None),
    # Brightwater's own stone. The region is named for the lake and the rule that scatters
    # its shore had nothing of its own to land on, so it was borrowing Briarwold's
    # forest-green granite and Skerrow's mountain grey.
    ("cliff_slab", "brightwater", 2, {"stone": "lake_stone", "width": 3.2, "height": 4.2,
                                      "depth": 1.7}),
    # Dressed stone, not geology: a delta has no cliffs, and the fen took something built.
    ("sunken_masonry", "sedgemire", 2, None),
    ("scree", "skerrow", 3, None),
    ("scree", "cinderlea", 2, None),
    ("scree", "briarwold", 2, None),
    ("scree", "hearthvale", 2, {"stone": "chalk_rock"}),
    ("standing_stone", "briarwold", 3, None),
    ("standing_stone", "hearthvale", 2, {"carved": False}),
    ("standing_stone", "skerrow", 2, {"carved": False}),
    ("bone_rib", "skerrow", 3, None),
    ("bone_finger", "skerrow", 2, None),
    ("bone_skull_fragment", "skerrow", 2, None),
    ("bone_vertebra", "skerrow", 2, None),
]

FLORA = [
    ("grass_clump", "hearthvale", 3, None),
    ("grass_clump", "briarwold", 2, None),
    ("grass_clump", "brightwater", 2, None),
    ("grass_clump", "sedgemire", 2, None),
    ("grass_clump", "skerrow", 2, None),
    ("grey_grass", "cinderlea", 3, None),
    ("barley_tuft", "hearthvale", 2, None),
    ("reeds", "sedgemire", 3, None),
    ("reeds", "brightwater", 2, None),
    ("bulrush", "sedgemire", 2, None),
    ("fern", "briarwold", 3, None),
    ("fern", "sedgemire", 2, None),
    ("bracken", "briarwold", 2, None),
    ("bracken", "skerrow", 2, None),
    ("foxglove", "briarwold", 2, None),
    ("poppy", "hearthvale", 2, None),
    ("red_poppy_single", "cinderlea", 1, None),
    ("cow_parsley", "hearthvale", 2, None),
    ("cow_parsley", "brightwater", 1, None),
    ("heather", "skerrow", 3, None),
    ("marsh_marigold", "sedgemire", 2, None),
    ("briar_vine", "briarwold", 3, None),
    ("bracket_fungus", "briarwold", 2, None),
    ("hanging_moss", "briarwold", 2, None),
    ("hanging_moss", "sedgemire", 1, None),
    ("moss_patch", "briarwold", 2, None),
    ("moss_patch", "sedgemire", 1, None),
    ("waterlily_pad", "brightwater", 2, None),
    ("waterlily_pad", "sedgemire", 1, None),
    ("lichen_crust", "skerrow", 2, None),
]

# Props are largely region-neutral objects tinted by whoever made them; the palette picks
# the wood, iron and cloth tones, so the same generator gives a Vale barrel or a Reedfolk one.
PROPS = [
    # containers and vessels
    ("barrel", "hearthvale", 2, None), ("barrel", "brightwater", 1, None),
    ("crate", "hearthvale", 2, None), ("crate", "brightwater", 1, None),
    ("sack", "hearthvale", 2, None),
    ("basket", "hearthvale", 2, None), ("basket", "sedgemire", 1, None),
    ("bucket", "hearthvale", 2, None),
    ("chest", "hearthvale", 2, None),
    ("cooking_pot", "hearthvale", 1, None),
    ("plate", "hearthvale", 1, None), ("mug", "hearthvale", 2, None), ("jug", "hearthvale", 1, None),
    # furniture
    ("table_trestle", "hearthvale", 2, None), ("table_round", "hearthvale", 1, None),
    ("stool", "hearthvale", 2, None), ("chair", "hearthvale", 2, None),
    ("bench", "hearthvale", 2, None), ("bed", "hearthvale", 2, None),
    ("shelf", "hearthvale", 1, None), ("cupboard", "hearthvale", 1, None),
    # light
    ("candle", "hearthvale", 1, None), ("candlestick", "hearthvale", 2, None),
    ("lantern_hanging", "sedgemire", 2, None), ("lantern_standing", "brightwater", 2, None),
    ("brazier", "cinderlea", 2, None), ("chandelier", "brightwater", 1, None),
    ("campfire", "hearthvale", 2, None),
    # work
    ("anvil", "hearthvale", 1, None), ("forge_hearth", "hearthvale", 1, None),
    ("alembic", "brightwater", 1, None), ("rope_coil", "sedgemire", 2, None),
    ("wheelbarrow", "hearthvale", 1, None), ("cart", "hearthvale", 2, None),
    ("hay_bale", "hearthvale", 2, None),
    # books and paper
    ("book", "hearthvale", 2, None), ("book_stack", "hearthvale", 2, None),
    ("scroll", "brightwater", 2, None),
    # structures and outdoor
    ("fence_wattle", "hearthvale", 2, None), ("fence_post_rail", "hearthvale", 2, None),
    ("drystone_wall", "skerrow", 2, None), ("drystone_wall_end", "skerrow", 1, None),
    ("well", "hearthvale", 1, None), ("signpost", "hearthvale", 2, None),
    ("market_stall", "brightwater", 2, None),
    ("dock_post", "sedgemire", 2, None), ("boardwalk_plank", "sedgemire", 2, None),
    ("rowboat", "sedgemire", 2, None),
    ("tent", "cinderlea", 2, None), ("bedroll", "cinderlea", 2, None),
    ("banner", "brightwater", 2, None),
    # bells and burial
    ("bell_small", "hearthvale", 2, None), ("bell_medium", "cinderlea", 1, None),
    ("gravestone", "hearthvale", 3, None), ("coffin", "hearthvale", 1, None),
    ("sarcophagus", "cinderlea", 1, None),
]

# Hand tools, arms and linen: what the shipping house interiors ask for by the dozen and
# the forge had never made. A second props table rather than eight more lines in PROPS,
# because `build()` walks the tables in order to derive seeds from one walking counter: a
# line added anywhere but the very end renumbers everything after it, and appending inside
# PROPS would have quietly reseeded -- and so rebuilt, differently -- all ten landmarks.
PROP_TOOLS = [
    ("cloth", "hearthvale", 2, None),
    ("spoon", "hearthvale", 2, None),
    ("tongs", "hearthvale", 2, None),
    ("hammer", "hearthvale", 2, None),
    ("spear", "hearthvale", 2, None),
    ("shield", "hearthvale", 2, None),
    ("pitchfork", "hearthvale", 1, None),
    ("whetstone", "hearthvale", 2, None),
]

# The last four kinds a shipping room asks for by name. `loaf` and `millstone` were drawn
# as labelled placeholders in Maud's bakehouse and Pennywort's Mill; `chopping_block` and
# `peat_stack` are what a village work station wants to wear instead of the crate and the
# bucket `settlement.gd` dresses `chop` and `dig` in for want of anything better.
PROP_WORK = [
    ("loaf", "hearthvale", 2, None),
    ("millstone", "hearthvale", 1, None),
    ("chopping_block", "hearthvale", 2, None),
    ("chopping_block", "briarwold", 1, None),
    ("peat_stack", "skerrow", 2, None),
]

# Briarwold's own furniture. Of the kinds the forge built, Briarwold was the only one of
# the six regions with none at all, so every prop in a woodfolk room was borrowed out of
# another region's timber and `PropLibrary`'s per-region choice had nothing to choose
# between. These are the eight kinds the shipping interiors ask for most often. It is the
# same generator with a different palette, which is the whole point of the palette: a
# black-ash trestle instead of a vale oak one, from one table.
PROPS_BRIARWOLD = [
    ("table_trestle", "briarwold", 2, None),
    ("chair", "briarwold", 2, None),
    ("stool", "briarwold", 2, None),
    ("bed", "briarwold", 2, None),
    ("chest", "briarwold", 2, None),
    ("shelf", "briarwold", 1, None),
    ("barrel", "briarwold", 2, None),
    ("crate", "briarwold", 2, None),
]

# The ten kinds whose stand-ins lied about their size. `PropLibrary.STAND_IN` let each of
# them borrow the nearest mesh the forge had built, and the borrowed mesh was the wrong
# scale: a hand lantern drew a two-metre standing one, a pair of boots drew a sack, a
# brewing copper drew a cooking pot a third of its height. Regions are the ones whose
# interiors actually place the kind (`tools/prop_heights.py`): nearly all of this is vale
# work, and the one exception is the hand lantern, which the Bell Chapter-House at Pilgrim's
# Ash wants as well as Pellam's roll house.
#
# Two variants where a room stands several of a kind in a row and one everywhere else.
PROPS_SIZED = [
    ("bowl", "hearthvale", 2, None),
    ("plate_stack", "hearthvale", 1, None),
    ("paper_stack", "hearthvale", 1, None),
    ("phial", "hearthvale", 2, None),
    ("jar", "hearthvale", 1, None),
    ("mortar", "hearthvale", 1, None),
    ("candle_stub", "hearthvale", 2, None),
    ("boots", "hearthvale", 2, None),
    ("lantern_hand", "hearthvale", 1, None),
    ("lantern_hand", "cinderlea", 1, None),
    ("copper", "hearthvale", 1, None),
]

# The Name-table (DESIGN §5.8). Enchanting is written at one, the skill's own definition
# and two item descriptions name one, and there was no mesh: the only one in the country --
# the Bell Chapter-House at Pilgrim's Ash -- stood in as a trestle table and was written
# down as owed. Cinderlea, because the Tolling Order is Cinderlea's and keeps its vigil
# there; one, because there is one.
PROPS_ORDER = [
    ("name_table", "cinderlea", 1, None),
]

LANDMARKS = [
    ("cracked_toll", "hearthvale", 1, None),
    ("fallen_hand", "skerrow", 1, None),
    ("choir_colossus", "cinderlea", 2, None),
    ("the_lamp", "brightwater", 1, None),
    ("sayers_spire", "brightwater", 1, None),
    # The four the placer names and had nothing to place: a tree-town, a hill figure, a
    # flooded nave and the mark the Reedfolk left at a pool they do not trust.
    ("grandfather", "briarwold", 1, None),
    ("chalk_hound", "hearthvale", 1, None),
    ("drowned_nave", "sedgemire", 1, None),
    ("eelfathom", "sedgemire", 1, None),
]

# The kit the country is lined with (tools/forge/gen_ground_kit.py). A hedge segment is
# 2.2 m of hedge in 66 triangles, which is what lets every field boundary in the Vale carry
# one; the nearest existing asset was a 5 610-triangle hawthorn, and a hedge built out of
# those would have cost more than the rest of the world together. Hearthvale and Brightwater
# are the two shapes `worldgen/fields.py` encloses, so they are the two that need hedges.
GROUND_KIT = [
    ("hedge_segment", "hearthvale", 2, None),
    ("hedge_segment", "brightwater", 2, None),
    ("gate_post", "hearthvale", 1, None),
    ("milestone", "hearthvale", 2, None),
]

# A village's stock (world/exteriors/livestock.gd): hens in the yards, geese on the green,
# sheep in the paddock and a pig in its sty. The Vale's, for every region: a village in any of
# them keeps the same beasts, and the palette would only move the hides a shade.
PROPS_LIVESTOCK = [
    ("hen", "hearthvale", 2, None),
    ("goose", "hearthvale", 1, None),
    ("sheep", "hearthvale", 2, None),
    ("pig", "hearthvale", 1, None),
    ("crab", "sedgemire", 2, None),
]

# The picture each tree is drawn as once it is a few dozen pixels tall (gen_impostors.py):
# eight views of it in an atlas, and its LOD2 made one quad that turns to face the eye. It
# reads the tree TREES built rather than growing one, so it names the same kind, region and
# variants, its entry is called <tree>_impostor, and build_assets.py builds it after the trees.
# `recipe` is the impostor generator's own version: bump it to draw every impostor again.
IMPOSTORS = [(kind, reg, variants, {"recipe": 1}) for kind, reg, variants, _params in TREES]

# What is held (tools/forge/gen_weapons.py): each named for its kind and what it is made of,
# which is how game/actors/shared/held_items.gd finds the one an item is drawn with. The region
# palette only tints, and a sword is not a region's, so they are built on the neutral one.
# (kind, finish, name, extra params)
WEAPONS = [
    ("sword", "iron", "sword_iron", None), ("sword", "bronze", "sword_bronze", None),
    ("sword", "ashen", "sword_ashen", None), ("rapier", "iron", "rapier_iron", None),
    ("greatsword", "iron", "greatsword_iron", None), ("greatsword", "bronze", "greatsword_bronze", None),
    ("greatsword", "ashen", "greatsword_ashen", None), ("greatsword", "bone", "greatsword_bone", None),
    ("dagger", "iron", "dagger_iron", None), ("dagger", "bronze", "dagger_bronze", None),
    ("dagger", "ashen", "dagger_ashen", None), ("knife", "iron", "knife_iron", None),
    ("axe", "iron", "axe_iron", None), ("axe", "bronze", "axe_bronze", None), ("axe", "ashen", "axe_ashen", None),
    ("axe", "iron", "axe_long_iron", {"long": True}),
    ("mace", "iron", "mace_iron", None), ("mace", "bronze", "mace_bronze", None), ("mace", "ashen", "mace_ashen", None),
    ("spear", "iron", "spear_iron", None), ("spear", "bronze", "spear_bronze", None),
    ("spear", "ashen", "spear_ashen", None), ("spear", "iron", "spear_long_iron", {"length": 2.9, "head": 0.34}),
    ("staff", "iron", "staff_iron", None), ("warhammer", "bronze", "warhammer_bronze", None),
    ("clapper", "bronze", "clapper_bronze", None), ("bow", "iron", "bow_wood", None), ("bow", "bone", "bow_bone", None),
    ("shield", "iron", "shield_iron", None), ("shield", "wood", "shield_wood", None),
    ("shield", "bone", "shield_bone", None), ("crossbow", "iron", "crossbow_iron", None),
]


WEAPON_SEED = 9111


def weapon_entries(seed: int) -> list[dict]:
    out = []
    for i, (kind, finish, name, extra) in enumerate(WEAPONS):
        params = {"finish": finish}
        params.update(extra or {})
        out.append({"generator": "gen_weapons", "kind": kind, "palette": None, "variant": "a",
                    "seed": seed + i * 17, "name": name, "category": "weapons", "params": params})
    return out


# Crags. Cinderlea's are old lava: columns of basalt where its ground falls away (the world
# builder's crags pass stands them on its steep faces, as it does the other regions' cliff slabs).
ROCKS_CRAGS = [
    ("basalt_columns", "cinderlea", 2, None),
]

# Order is load-bearing: `build()` walks the tables with one running counter to derive
# seeds, so a line added anywhere but at the end of the last table renumbers -- and so
# rebuilds, differently -- everything after it. New work goes on the end.
TABLES = [("gen_trees", TREES), ("gen_rocks", ROCKS), ("gen_flora", FLORA),
          ("gen_props", PROPS), ("gen_landmarks", LANDMARKS), ("gen_props", PROP_TOOLS),
          ("gen_props", PROP_WORK), ("gen_props", PROPS_BRIARWOLD),
          ("gen_props", PROPS_SIZED), ("gen_props", PROPS_ORDER),
          ("gen_ground_kit", GROUND_KIT), ("gen_impostors", IMPOSTORS), ("gen_rocks", ROCKS_CRAGS)]

# The livestock were built as the table after GROUND_KIT, before the impostors joined TABLES, so
# the running counter stood at this seed for them then; pinned here, as the weapons are, so the
# impostors above do not re-roll them. (The weapons start from the same number, on another
# generator, so no asset shares a name or a hash with another.)
LIVESTOCK_SEED = 9111


def livestock_entries(seed: int) -> list[dict]:
    out = []
    for kind, reg, variants, params in PROPS_LIVESTOCK:
        for i in range(variants):
            e = {"generator": "gen_props", "kind": kind, "palette": region(reg),
                 "variant": LETTERS[i], "seed": seed + i * 17}
            if params:
                e["params"] = params
            out.append(e)
        seed += 53
    return out


def build() -> list[dict]:
    entries: list[dict] = []
    seed = 101
    for generator, table in TABLES:
        for kind, reg, variants, params in table:
            for i in range(variants):
                e = {"generator": generator, "kind": kind, "palette": region(reg),
                     "variant": LETTERS[i], "seed": seed + i * 17}
                if params:
                    e["params"] = params
                if generator == "gen_impostors":
                    e["name"] = "%s_%s_%s_impostor" % (reg, kind, LETTERS[i])
                entries.append(e)
            seed += 53
    # The weapons were forged before the impostor table joined TABLES, so their seeds are pinned
    # to where the running counter stood then; a table added above must not re-roll them.
    entries += weapon_entries(WEAPON_SEED)
    entries += livestock_entries(LIVESTOCK_SEED)
    return entries


def main() -> None:
    entries = build()
    out = {
        "version": 1,
        "note": "Wickmere generated assets. Edit tools/forge/make_manifest.py, not this file. "
                "Build with ./run.sh assets.",
        "assets": entries,
    }
    path = FORGE / "manifest.json"
    path.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    counts = Counter(e["generator"] for e in entries)
    print("wrote %d entries to %s" % (len(entries), path))
    for g, n in sorted(counts.items()):
        print("  %-16s %3d" % (g, n))


if __name__ == "__main__":
    main()
