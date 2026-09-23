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
import math
import re
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


class LeanTest(unittest.TestCase):
    """The wind-bent trees: CONTRACTS section 6's optional [lean_deg, lean_toward_deg]."""

    def test_only_a_leaning_rule_on_its_own_landform_leans(self):
        rng = np.random.default_rng(1)
        water_d = np.array([5.0, 100.0, 800.0], dtype=np.float32)
        self.assertEqual(CELLS.lean_of({}, "lake_basin", water_d, rng), (None, None))
        cfg = {"lean": {"lake_basin": [6.0, 16.0]}, "wind_toward": [0.8, 0.6]}
        self.assertEqual(CELLS.lean_of(cfg, "downs", water_d, rng), (None, None))
        lean, toward = CELLS.lean_of(cfg, "lake_basin", water_d, rng)
        self.assertEqual(lean.shape, (3,))
        self.assertTrue((lean >= 0.7 * 6.0 - 1e-4).all() and (lean <= 16.0 + 1e-4).all())
        self.assertGreater(float(lean[0]), float(lean[2]), "a tree at the water leans more than one inland")
        self.assertTrue((np.abs(toward - 36.87) < 45.0).all())

    def test_the_trees_lean_the_way_the_atmosphere_blows(self):
        path = os.path.join(os.path.dirname(os.path.dirname(TOOLS_WORLD)), "game", "systems",
                            "atmosphere", "atmosphere.gd")
        text = open(path, encoding="utf-8").read()
        m = re.search(r'"wm_wind_dir",\s*Vector3\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)', text)
        self.assertIsNotNone(m, "atmosphere.gd no longer sets wm_wind_dir the way this reads it")
        wx, wz = float(m.group(1)), float(m.group(3))
        rules = CELLS.load_rules(RULES, ["cover"])
        tx, tz = rules["defaults"]["wind_toward"]
        self.assertAlmostEqual(math.atan2(tz, tx), math.atan2(wz, wx), places=3)
        self.assertIn("lake_basin", rules["flora"]["willow_pollard"]["lean"])


class RoadClearTest(unittest.TestCase):
    """The landform goes on after the roads and stays off them (landforms.road_clear)."""

    def test_a_road_keeps_the_ground_it_was_laid_on(self):
        from worldgen import landforms as LF
        from worldgen import roads as RD

        edge = 0.5 * 6.0 + RD.shoulder_m(6.0) + LF.ROAD_CLEAR_M       # 17.8 m for a town road
        d = np.array([0.0, 3.0, 13.8, edge, edge + 15.0, edge + LF.ROAD_FADE_M, 1e6], dtype=np.float32)
        w = np.full_like(d, 6.0)
        w[-1] = 0.0                                                     # no road anywhere near
        c = LF.road_clear(d, w)
        self.assertTrue((c[:4] == 0.0).all(), "under the road, its shoulder, and past its carve")
        self.assertAlmostEqual(float(c[4]), 0.5, places=5)
        self.assertEqual(float(c[5]), 1.0, "all of it back thirty metres on")
        self.assertEqual(float(c[6]), 1.0, "and everywhere there is no road")


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
            lengths: dict = {}
            cells = os.path.join(made, "cells")
            for name in os.listdir(cells):
                with open(os.path.join(cells, name), "r", encoding="utf-8") as f:
                    for rows in json.load(f)["instances"].values():
                        for row in rows:
                            lengths[len(row)] = lengths.get(len(row), 0) + 1
        self.assertEqual(set(lengths), {6, 8}, "a scatter row is six fields, or eight with a lean")
        self.assertGreater(lengths[8], 0, "no tree in Brightwater leans")
        self.assertEqual(man0["recipes"], [])
        self.assertEqual(man1["recipes"], ["cover", "landforms"])
        self.assertGreater(float(np.abs(h1 - h0).max()), 1.0, "the landforms recipe changed nothing")
        self.assertGreater(man1["scatter_instances"], 0)


if __name__ == "__main__":
    unittest.main()
