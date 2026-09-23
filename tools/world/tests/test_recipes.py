#!/usr/bin/env python3
"""The parts of the world that are off by default stay off, and still build when asked for.

    python3 -m pytest tools/world/tests/test_recipes.py

`build_world.RECIPES` names them: `landforms` (worldgen/landforms.py) and `cover` (the scatter
rules' `cover` block and the per-region line-work). A default build must be the world as it
was without them, because the next `./run.sh world` in the main checkout is a default build;
and a recipe nobody builds rots, so each is built here once, small.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)

from worldgen import cells as CELLS  # noqa: E402

RULES = os.path.join(TOOLS_WORLD, "scatter_rules.json")
SIZE = 256


def _at(node, dotted: str):
    for step in dotted.split("."):
        node = node[int(step)] if isinstance(node, list) else node[step]
    return node


class RulesTest(unittest.TestCase):
    def test_the_default_rules_are_the_file_without_its_recipes(self):
        with open(RULES, "r", encoding="utf-8") as f:
            raw = json.load(f)
        raw.pop("recipes")
        self.assertEqual(CELLS.load_rules(RULES), raw)

    def test_every_cover_patch_lands_on_a_rule_that_exists(self):
        with open(RULES, "r", encoding="utf-8") as f:
            patch = json.load(f)["recipes"]["cover"]
        self.assertTrue(patch)
        base = CELLS.load_rules(RULES)
        cover = CELLS.load_rules(RULES, ["cover"])
        for dotted, value in patch.items():
            parent = dotted.rsplit(".", 1)[0]
            _at(base, parent)                      # a typo in a path is a KeyError here
            self.assertEqual(_at(cover, dotted), value, dotted)
        self.assertNotIn("marram", base["flora"])
        self.assertIn("marram", cover["flora"])


class AssetLookupTest(unittest.TestCase):
    """`assets_for`: a region's own variants of a kind, and not a longer kind's."""

    INDEX = {"props": {"skerrow_drystone_wall_a": "A", "skerrow_drystone_wall_b": "B",
                       "skerrow_drystone_wall_end_a": "E", "hearthvale_hedge_segment_a": "H"},
             "rocks": {"skerrow_bone_rib_a": "R", "skerrow_bone_skull_fragment_a": "S"}}

    def test_a_wall_is_laid_with_wall_and_not_with_its_ends(self):
        # a third of every run Skerrow was given was an end piece: a wall of stubs
        self.assertEqual(sorted(CELLS.assets_for(self.INDEX, "props/drystone_wall", "skerrow")), ["A", "B"])
        self.assertEqual(CELLS.assets_for(self.INDEX, "props/drystone_wall_end", "skerrow"), ["E"])

    def test_a_kind_with_no_variants_of_its_own_is_still_a_family(self):
        # `rocks/bone` is a prefix on purpose: the giants' fingers, ribs and skulls
        self.assertEqual(sorted(CELLS.assets_for(self.INDEX, "rocks/bone", "skerrow")), ["R", "S"])

    def test_another_regions_variant_is_still_better_than_none(self):
        self.assertEqual(CELLS.assets_for(self.INDEX, "props/hedge_segment", "brightwater"), ["H"])


class BuildTest(unittest.TestCase):
    def test_an_unknown_recipe_is_refused(self):
        import build_world as BW

        with tempfile.TemporaryDirectory() as tmp:
            args = SimpleNamespace(size=SIZE, seed=None, out=tmp, only=None, recipe=["nonsense"])
            with self.assertRaises(SystemExit):
                BW.build(args)

    def test_both_recipes_build_and_are_recorded(self):
        def build(out, *extra):
            subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", str(SIZE),
                            "--out", out, *extra], check=True, capture_output=True, timeout=900)
            with open(os.path.join(out, "world_manifest.json"), "r", encoding="utf-8") as f:
                man = json.load(f)
            h = np.fromfile(os.path.join(out, "heights.r32"), dtype="<f4")
            return man, h

        # the default side needs only its land; the recipe side is built whole, because most of
        # `cover` is in the scatter, the hedges and the roadside (the scatter is by the hectare,
        # so even this small a build plants the whole world: a couple of minutes)
        with tempfile.TemporaryDirectory() as plain, tempfile.TemporaryDirectory() as made:
            man0, h0 = build(plain, "--only", "heights")
            man1, h1 = build(made, "--recipe", "landforms", "--recipe", "cover")
        self.assertEqual(man0["recipes"], [])
        self.assertEqual(man1["recipes"], ["cover", "landforms"])
        self.assertGreater(float(np.abs(h1 - h0).max()), 1.0, "the landforms recipe changed nothing")
        self.assertGreater(man1["scatter_instances"], 0)


if __name__ == "__main__":
    unittest.main()
