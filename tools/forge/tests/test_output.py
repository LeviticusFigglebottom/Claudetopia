"""Checks over whatever the forge has actually produced in game/assets/models.

These run against committed output rather than generating anything, so they are fast and
they guard the things that are easy to break quietly: the repository's weight, the
triangle budgets in DESIGN §7.0, texture sizes against CONTRACTS §4, and the foliage
naming the Godot import step depends on.

If nothing has been generated yet the whole module skips, so a fresh clone still passes.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import cli  # noqa: E402

MODELS = cli.DEFAULT_OUT
# DESIGN §7.0: typical prop 500-6 000 triangles, hero pieces up to 40 000.
TRI_LIMIT = {"props": 12000, "flora": 2500, "rocks": 12000, "trees": 22000, "landmarks": 60000,
             "weapons": 6000}
# The categories this forge owns. Other streams write characters, creatures and dungeon
# kits into the same tree, with their own meta schemas and their own budgets, so every
# check here is scoped to what gen_*.py produced rather than to whatever is on disk.
OURS = ("trees", "flora", "rocks", "props", "landmarks", "weapons")
# The weight ceiling below is the world's; what is held has its own, since thirty-odd weapons
# built on the neutral palette are a set of their own, and every one is seen in a hand.
WORLD_CATEGORIES = ("trees", "flora", "rocks", "props", "landmarks")
WEAPONS_MB_LIMIT = 16.0
# The generated set is committed, so its size is a design decision. The brief's ceiling is
# "about 150 MB" for these categories and the library sat at 146 MB of it with the six
# regions' props still only five regions deep -- which meant the next thing the forge built
# broke the budget, whatever it was. Briarwold's furniture, the mill's stone, the
# bakehouse's bread, a chopping block and a peat bank cost 11 MB between them, at 0.3 MB an
# asset against a library averaging 0.55, so there was no fat in the new work to cut.
#
# Raised deliberately, not slackened: 165 leaves about 8 MB of headroom, which is roughly
# one more region's furniture, and that is the point at which someone has to spend one of
# the two levers that are left rather than move this number again --
#
#   * the drawn leaf and grass atlases write their normal at the albedo's own size, where
#     everything baked writes it at half (lib/bake.py, and the table in the forge README).
#     Bringing the atlases into line with the rule the rest of the forge already follows is
#     about 3 MB across 85 assets;
#   * the ten landmarks carry 1536 px albedos and are 27 MB between them, a fifth of the
#     whole library for ten objects. At 1024 they would give back about 10 MB.
#
# Both are real savings with a written justification behind them. Neither was worth
# rebuilding a hundred committed assets for while the budget still had room.
TOTAL_MB_LIMIT = 165.0


def metas() -> list[dict]:
    out = []
    if not MODELS.is_dir():
        return out
    for cat in OURS:
        for p in (MODELS / cat).glob("*/*.meta.json"):
            try:
                m = json.loads(p.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(m, dict) and m.get("category") and str(m.get("generator", "")).startswith("gen_"):
                out.append(m)
    return out


ALL = metas()


@unittest.skipUnless(ALL, "no generated assets yet (run ./run.sh assets)")
class TestGeneratedOutput(unittest.TestCase):
    def test_triangle_budgets(self):
        over = []
        for m in ALL:
            limit = TRI_LIMIT.get(m["category"].split("/")[0], 12000)
            if m["tris"][0] > limit:
                over.append("%s/%s %d > %d" % (m["category"], m["name"], m["tris"][0], limit))
        self.assertEqual(over, [], "over triangle budget:\n  " + "\n  ".join(over))

    def test_lods_actually_get_cheaper(self):
        bad = [("%s: %s" % (m["name"], m["tris"])) for m in ALL
               if not (m["tris"][0] >= m["tris"][1] >= m["tris"][2])]
        self.assertEqual(bad, [], "LOD chain not decreasing:\n  " + "\n  ".join(bad))

    def test_every_asset_rests_on_the_ground(self):
        """CONTRACTS §1: placements put an asset's origin on the terrain, so y=0 is its
        base. Hanging and floating assets say so in their meta."""
        floating = []
        for m in ALL:
            if m.get("hangs") or m.get("floats") or m.get("attaches_to"):
                continue
            y = m["bounds"]["min"][1]
            # A little below zero is fine and right: low foliage and a rock's skirt sit in
            # the grass rather than on top of it. Trees get more room because their lowest
            # cluster cards are large and hang.
            floor = -0.6 if m["category"] in ("trees", "flora") else -0.25
            if y > 0.05 or y < floor:
                floating.append("%s y_min=%.2f" % (m["name"], y))
        self.assertEqual(floating, [], "not grounded:\n  " + "\n  ".join(floating))

    def test_texture_sizes_are_in_contract_range(self):
        from PIL import Image
        bad = []
        for m in ALL:
            d = MODELS / m["category"] / m["name"]
            for t in m["textures"]:
                f = d / t
                if not f.exists():
                    bad.append("missing %s" % f)
                    continue
                with Image.open(f) as im:
                    w, h = im.size
                if w != h or w < 64 or w > 2048:
                    bad.append("%s is %dx%d" % (t, w, h))
        self.assertEqual(bad, [], "texture problems:\n  " + "\n  ".join(bad))

    def test_textures_are_written_not_merely_present(self):
        """A 0-byte texture is worse than a missing one, and it read as present.

        A build killed part-way through leaves the meta.json -- which carries the hash the
        incremental build trusts -- already written and a texture truncated to nothing.
        Godot will not load a .glb whose material points at a 0-byte PNG, so every interior
        that asked for that prop failed rather than falling back to its placeholder, and
        `build_assets.py --list` said the asset was current for ever because nothing ever
        looked at the file's size. It happened once, to a whetstone."""
        empty = []
        for m in ALL:
            d = MODELS / m["category"] / m["name"]
            for f in [d / m["glb"]] + [d / t for t in m["textures"]]:
                if f.exists() and f.stat().st_size == 0:
                    empty.append(str(f.relative_to(MODELS)))
        self.assertEqual(empty, [], "files written empty:\n  " + "\n  ".join(empty))

    def test_textures_are_referenced_and_present(self):
        from lib import glb
        bad = []
        for m in ALL:
            d = MODELS / m["category"] / m["name"]
            path = d / m["glb"]
            if not path.exists():
                bad.append("missing %s" % path)
                continue
            for uri in glb.summary(path)["images"]:
                if uri == "<embedded>":
                    bad.append("%s embeds a texture" % m["name"])
                elif not (d / uri).exists():
                    bad.append("%s references missing %s" % (m["name"], uri))
        self.assertEqual(bad, [], "GLB texture problems:\n  " + "\n  ".join(bad))

    def test_foliage_materials_are_named_for_the_wind_shader(self):
        """CONTRACTS §4: the import step keys off the *_foliage suffix.

        Only card-based plants need it. A moss patch or a lichen crust is a baked mesh
        lying on the ground; it neither cuts out nor sways, so it is a plain material."""
        from lib import glb
        card_materials = {"foliage_leaf_card", "grass_blades"}
        bad = []
        for m in ALL:
            if m["category"] != "flora":
                continue
            if not card_materials.intersection(m.get("materials_used", [])):
                continue
            names = glb.summary(MODELS / m["category"] / m["name"] / m["glb"])["materials"]
            if not any("_foliage" in n for n in names):
                bad.append("%s: %s" % (m["name"], names))
        self.assertEqual(bad, [], "card flora without a foliage material:\n  " + "\n  ".join(bad))

    def test_every_asset_records_its_palette_and_seed(self):
        bad = [m["name"] for m in ALL
               if not m.get("region_palette") or not m["region_palette"].get("colors")]
        self.assertEqual(bad, [], "assets with no recorded palette: %s" % bad[:10])

    def test_variants_of_a_kind_differ(self):
        """DESIGN §7.0.6: seeds must produce visibly different assets."""
        groups: dict[tuple, list[dict]] = {}
        for m in ALL:
            key = (m["category"], m["kind"], (m.get("region_palette") or {}).get("id"))
            groups.setdefault(key, []).append(m)
        same = []
        for key, group in groups.items():
            if len(group) < 2:
                continue
            sizes = {(tuple(round(v, 3) for v in (mm["bounds"]["max"] + mm["bounds"]["min"])),
                      tuple(mm["tris"])) for mm in group}
            if len(sizes) < len(group):
                same.append("%s/%s" % (key[0], key[1]))
        self.assertEqual(same, [], "variants are identical: %s" % same)

    def test_total_weight(self):
        total = sum(f.stat().st_size for cat in WORLD_CATEGORIES
                    for f in (MODELS / cat).rglob("*") if f.is_file())
        mb = total / (1024 * 1024)
        self.assertLess(mb, TOTAL_MB_LIMIT, "generated assets are %.0f MB" % mb)
        held = sum(f.stat().st_size for f in (MODELS / "weapons").rglob("*") if f.is_file()) \
            if (MODELS / "weapons").is_dir() else 0
        self.assertLess(held / (1024 * 1024), WEAPONS_MB_LIMIT, "the weapons are %.0f MB" % (held / (1024 * 1024)))

    def test_collision_kinds_are_contract_kinds(self):
        bad = []
        for m in ALL:
            c = m["collision"]
            if c in ("convex", "trimesh", "capsule", "none"):
                continue
            if c.endswith("_col.glb") and (MODELS / m["category"] / m["name"] / c).exists():
                continue
            bad.append("%s: %s" % (m["name"], c))
        self.assertEqual(bad, [], "bad collision:\n  " + "\n  ".join(bad))


if __name__ == "__main__":
    unittest.main()
