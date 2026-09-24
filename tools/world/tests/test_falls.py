#!/usr/bin/env python3
"""The land steps at every waterfall (worldgen.falls): the pad is level at the foot in front of the
face and at the top behind it, and a river through it falls there.

The batch 3 shots had every waterfall POI as a face of rock standing up out of level ground with
the sky behind it, towers of blocks, and the river ran level across the pad with no drop to fall.

    python3 -m pytest tools/world/tests/test_falls.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import falls as FA  # noqa: E402
from worldgen import hydro as HY  # noqa: E402
from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402

BIG = [[-2000.0, -2000.0], [2000.0, -2000.0], [2000.0, 2000.0], [-2000.0, 2000.0]]


def _land(grid: Grid) -> np.ndarray:
    """A dale falling east at 1 in 16, its floor along z = 0 and its sides rising 1 in 5."""
    X, Z = grid.mesh(np.float64)
    return (100.0 - X / 16.0 + 0.2 * np.abs(Z)).astype(np.float32)


class RiverFall(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(1024.0, 512)                   # 2 m texels, as a full build
        cls.H0 = _land(g)
        cls.atlas = {"coast": {"polygon": BIG},
                     "rivers": [{"id": "test:river/beck", "path": [[-480.0, 0.0], [480.0, 0.0]], "width_m": [6, 8]}]}
        cls.poi = {"id": "core:poi/test_force", "kind": "waterfall", "position": [0.0, 4.0],
                   "unique_feature": "the beck dropping in a single white sheet"}
        cls.steps = FA.plan(g, cls.H0, cls.atlas, [cls.poi])
        cls.step = cls.steps[cls.poi["id"]]
        cls.H, _mask, cls.levels = RD.apply_pads(g, cls.H0.copy(), [cls.poi], steps=cls.steps)

    def h(self, x, z) -> float:
        return float(sample_bilinear(self.H, self.grid, np.array([x]), np.array([z]))[0])

    def test_it_faces_downstream_on_its_river(self):
        self.assertEqual(self.step.river, "test:river/beck")
        self.assertEqual(self.step.form, "single")
        self.assertAlmostEqual(self.step.fx, 1.0, places=3)
        self.assertAlmostEqual(self.step.facing_deg, 90.0, places=1)

    def test_the_pad_is_level_at_the_foot_in_front_and_at_the_top_behind(self):
        s = self.step
        self.assertAlmostEqual(s.top - s.foot, 11.0, places=3)
        self.assertAlmostEqual(self.levels[self.poi["id"]], s.foot, places=3)
        # the foot, from the face's line forward over the level core
        for x in (-5.0, 0.0, 6.0, 12.0):
            self.assertAlmostEqual(self.h(x, 4.0), s.foot, delta=0.05, msg="at x %.0f" % x)
        # the top, behind it
        for x in (-10.0, -13.0):
            self.assertAlmostEqual(self.h(x, 4.0), s.top, delta=0.05, msg="at x %.0f" % x)
        # and nothing like a ramp: the whole drop within STEP_RUN_M and a texel
        run = [x for x in np.arange(-12.0, -4.0, 0.25) if s.foot + 0.5 < self.h(x, 4.0) < s.top - 0.5]
        self.assertLessEqual(max(run) - min(run), FA.STEP_RUN_M + self.grid.spacing)

    def test_the_top_is_no_higher_than_the_river_comes_from(self):
        # the dale falls 1 in 16: the land 8 m behind the face is the top, and higher land upstream
        # does not raise it
        behind = float(sample_bilinear(self.H0, self.grid, np.array([-14.0]), np.array([4.0]))[0])
        self.assertLessEqual(self.step.top, behind + 0.5)

    def test_the_river_falls_at_the_face(self):
        rivers = HY.atlas_rivers(self.grid, self.H, self.atlas, None, avoid=[(0.0, 4.0)])
        falls = rivers[0].falls
        at = [f for f in falls if abs(f["top"][0] + 7.0) < 8.0]
        self.assertEqual(len(at), 1, falls)
        f = at[0]
        self.assertGreater(f["height_m"], 9.5)
        self.assertEqual(f["kind"], "fall")
        self.assertAlmostEqual(f["facing_deg"], 90.0, delta=15.0)


class OffTheRivers(unittest.TestCase):
    def test_a_fall_off_the_rivers_faces_down_its_slope_and_stands_its_three_tiers(self):
        g = Grid(1024.0, 512)
        H0 = _land(g)
        poi = {"id": "core:poi/test_sisters", "kind": "waterfall", "position": [0.0, 200.0],
               "unique_feature": "three terraced falls with a stone on the middle ledge"}
        steps = FA.plan(g, H0, {"coast": {"polygon": BIG}, "rivers": []}, [poi])
        s = steps[poi["id"]]
        self.assertEqual(s.river, "")
        self.assertEqual(s.form, "terraced")
        # the dale side falls toward z = 0 (-z) and a little east
        want = math.degrees(math.atan2(1.0 / 16.0, -0.2)) % 360.0
        self.assertAlmostEqual(s.facing_deg, want, delta=3.0)
        self.assertAlmostEqual(s.top - s.foot, 13.8, places=3)
        H, _m, levels = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        # each tier's ledge level behind its face: 4.6 m a tier
        for k, behind in enumerate((5.5, 11.5, 17.0)):
            x, z = -s.fx * behind, 200.0 - s.fz * behind
            got = float(sample_bilinear(H, g, np.array([x]), np.array([z]))[0])
            self.assertAlmostEqual(got, s.foot + 4.6 * (k + 1), delta=0.3, msg="tier %d" % k)

    def test_a_staged_build_reads_the_steps_back(self):
        s = FA.Step(id="core:poi/x", form="glass", x=10.0, z=-20.0, fx=0.6, fz=0.8, foot=40.0,
                    faces=[(7.0, 13.0)], river="")
        entry = {"place_id": "core:poi/x", "pos": [10.0, 40.0, -20.0], "fall": s.entry()}
        back = FA.from_entries([entry])["core:poi/x"]
        xs, zs = np.array([10.0, 0.0, -5.0]), np.array([-20.0, -30.0, -35.0])
        np.testing.assert_allclose(back.rise(xs, zs), s.rise(xs, zs), atol=1e-3)
        self.assertAlmostEqual(back.top, 53.0)

    def test_the_forms_are_the_dressing_s(self):
        self.assertEqual(FA.form_of("three falls stepping down the granite stair"), "terraced")
        self.assertEqual(FA.form_of("a dry waterfall of black glass, climbable"), "glass")
        self.assertEqual(FA.form_of("the Wold Water dropping in a single rope of white"), "single")


if __name__ == "__main__":
    unittest.main()
