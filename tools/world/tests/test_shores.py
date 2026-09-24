#!/usr/bin/env python3
"""The shores (worldgen.shores): each stretch of the sea's shore given its kind and shaped to it,
the marsh cut with creeks and pools, and every shore classed as built; nothing moved on a road,
a pad or under a sightline.

    python3 -m pytest tools/world/tests/test_shores.py
"""
from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)

from worldgen import shores as SH  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

COAST_Z = 300.0
CAVE = (-500.0, 312.0, 18.0, "core:poi/test_cave")


def _atlas() -> dict:
    # land is everything north of z = 300 (the sea to the south); cliffs along its western half
    # and a beach along its eastern; a pad at the cliff's foot, at 4 m
    return {"coast": {"polygon": [[-1024, -1024], [1024, -1024], [1024, COAST_Z], [-1024, COAST_Z]],
                      "cliffs": [{"height_m": 60, "path": [[-1000, COAST_Z], [-40, COAST_Z]]}]},
            "pads": [{"place": CAVE[3], "level_m": 4, "radius_m": CAVE[2]}]}


class Shores(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(2048.0, 512)
        n = g.n
        X, Z = g.mesh()
        X = np.broadcast_to(X, (n, n)).astype(np.float32)
        Z = np.broadcast_to(Z, (n, n)).astype(np.float32)
        land = Z < COAST_Z
        cliff = land & (X < -40.0)
        H = np.where(land, 0.8 + (COAST_Z - Z) * 0.04, -3.0 - (Z - COAST_Z) * 0.08)
        H = np.where(cliff, np.maximum(H, 60.0), H)
        cls.H0 = H.astype(np.float32)
        cls.X, cls.Z = X, Z
        cls.bank = NoiseBank(7, g)
        cls.regions = [SimpleNamespace(index=0, shape="downs", art_short="hearthvale")]
        cls.rf = SimpleNamespace(owner_at=lambda k: np.zeros((k, k), dtype=np.uint8),
                                 weight_at=lambda r, k: np.ones((k, k), dtype=np.float32))
        # a road down to the beach at x = 600, and a sightline across the cliffs at x = -300
        cls.road_d = np.abs(X - 600.0).astype(np.float32)
        cls.road_w = np.full((n, n), 4.0, dtype=np.float32)
        cls.sight = np.abs(X + 300.0) < 12.0
        cls.discs = [CAVE]
        cls.plan = SH.plan(g, _atlas(), cls.bank, cls.rf, cls.regions, 5, cls.discs, cls.road_d, cls.road_w,
                           cls.sight, H=cls.H0)
        cls.keep = cls.road_d <= cls.road_w * 0.5 + SH.ROAD_CLEAR_M
        cls.H = SH.shape(g, cls.H0.copy(), cls.plan, cls.bank, cls.discs, keep=cls.keep, no_raise=cls.sight)

    def at(self, arr, x, z):
        return float(sample_bilinear(arr, self.grid, np.array([x]), np.array([z]))[0])

    def test_the_cliff_is_cliff_and_the_beach_is_not(self):
        gp = self.plan.gp
        cls = self.plan.cls
        j, i = gp.to_tex(np.array([-600.0, 500.0]), np.array([COAST_Z - 4.0, COAST_Z - 4.0]))
        j, i = gp.clamp_index(j, i)
        self.assertEqual(int(cls[i[0], j[0]]), SH.CLIFF)
        self.assertIn(int(cls[i[1], j[1]]), (SH.SAND, SH.SHINGLE, SH.ROCK))
        self.assertEqual(self.plan.counts["cliff"] > 0, True)

    def test_nothing_moves_on_a_road(self):
        on = self.keep
        self.assertTrue(np.array_equal(self.H[on], self.H0[on]), "the shore moved the ground under a road")

    def test_nothing_is_raised_under_a_sightline(self):
        s = self.sight
        self.assertLessEqual(float((self.H[s] - self.H0[s]).max()), 1e-4)

    def test_the_pad_keeps_its_level(self):
        x, z, r, _ = CAVE
        core = (self.X - x) ** 2 + (self.Z - z) ** 2 <= (0.5 * r) ** 2
        # the pad core in the fixture is sea; it is only ever raised (never lowered) and never
        # above the pad's level
        self.assertTrue((self.H[core] >= self.H0[core] - 1e-4).all())
        self.assertLessEqual(float(self.H[core].max()), 4.0 + 1e-3)

    def test_a_low_pad_at_a_cliff_foot_gets_a_shelf(self):
        self.assertEqual([s["id"] for s in self.plan.shelves], [CAVE[3]])
        x, z = CAVE[0], CAVE[1] + 20.0
        self.assertGreater(self.at(self.H, x, z), 2.5, "no rock shelf at the pad's level out into the water")
        self.assertLess(self.at(self.H0, x, z), 0.0)

    def test_the_cliff_has_a_platform_or_plunges(self):
        # along the cliff's foot, where the plan gives a platform, the rock is at the water
        gp = self.plan.gp
        xs = np.arange(-950.0, -100.0, 10.0)
        zs = np.full(xs.shape, COAST_Z + 8.0)
        plat = sample_bilinear(self.plan.plat, gp, xs, zs)
        h = sample_bilinear(self.H, self.grid, xs, zs)
        wide = plat > 20.0
        if wide.any():
            self.assertGreater(float(np.median(h[wide])), -0.8)
        # and it is never raised into dry land a metre over the sea, but at the pad's shelf, a
        # stack, a skerry or a cove
        clear = np.ones(xs.shape, dtype=bool)
        for c in self.plan.coves + self.plan.stacks + self.plan.skerries + self.plan.shelves:
            clear &= (xs - c["x"]) ** 2 + (zs - c["z"]) ** 2 > (c["r"] + 45.0) ** 2
        self.assertTrue(clear.any())
        self.assertLess(float(h[clear].max()), SH.PLATFORM_TOP_M + SH.PLATFORM_RIDGE_M + 0.05)

    def test_every_change_is_near_the_coast(self):
        moved = np.abs(self.H - self.H0) > 1e-4
        far = np.abs(self.Z - COAST_Z) > SH.BAND_M + 40.0
        near_thing = np.zeros_like(moved)
        for c in self.plan.coves + self.plan.stacks + self.plan.skerries:
            near_thing |= (self.X - c["x"]) ** 2 + (self.Z - c["z"]) ** 2 < (c["r"] * 2.0 + 30.0) ** 2
        self.assertFalse((moved & far & ~near_thing).any())

    def test_the_same_inputs_shape_the_same_shore(self):
        again = SH.plan(self.grid, _atlas(), NoiseBank(7, self.grid), self.rf, self.regions, 5, self.discs,
                        self.road_d, self.road_w, self.sight, H=self.H0)
        self.assertEqual(again.counts, self.plan.counts)
        self.assertTrue(np.array_equal(again.cls, self.plan.cls))

    def test_classes_as_built(self):
        wet = (self.H < 0.0).astype(np.uint8)
        level = np.where(wet > 0, 0.0, -1000.0).astype(np.float32)
        cls, d = SH.classify(self.grid, self.H, wet, level, self.plan, None, self.rf, self.regions, self.bank)
        self.assertEqual(cls.shape, self.plan.cls.shape)
        # negative on the water, positive on the land
        f = self.grid.n // cls.shape[0]
        w = wet[::f, ::f] > 0
        self.assertTrue((d[w] < 0).all() and (d[~w] > 0).all())
        # nothing classed far from the water but a sandy bay's dunes
        far = np.abs(d) > SH.SHORE_REACH_M
        self.assertTrue(np.isin(cls[far], [0, SH.SAND]).all())
        # the water under the cliff laps cliff or rock
        gp = self.plan.gp
        j, i = gp.to_tex(np.array([-600.0]), np.array([COAST_Z + 30.0]))
        j, i = gp.clamp_index(j, i)
        self.assertIn(int(cls[i[0], j[0]]), (SH.CLIFF, SH.ROCK))


class Marsh(unittest.TestCase):
    def test_creeks_hold_water_off_the_roads(self):
        g = Grid(2048.0, 512)
        n = g.n
        H = np.full((n, n), 0.9, dtype=np.float32)
        table = np.full((n, n), 1.25, dtype=np.float32)
        regions = [SimpleNamespace(index=0, shape="delta", art_short="sedgemire")]
        rf = SimpleNamespace(owner_at=lambda k: np.zeros((k, k), dtype=np.uint8),
                             weight_at=lambda r, k: np.ones((k, k), dtype=np.float32))
        X, _ = g.mesh()
        keep = np.broadcast_to(np.abs(X) < 6.0, (n, n))
        out, water = SH.marsh(g, H.copy(), rf, regions, table, NoiseBank(3, g), keep=keep)
        self.assertGreater(int(water.sum()), 100, "no creeks or pools cut")
        self.assertFalse(water[keep].any())
        self.assertTrue(np.array_equal(out[keep], H[keep]))
        # every wet texel lies under the table
        self.assertTrue((out[water] < table[water]).all())
        # and read back without carving, the same water
        _, again = SH.marsh(g, out.copy(), rf, regions, table, NoiseBank(3, g), keep=keep, carve=False)
        self.assertTrue(np.array_equal(again, water))


if __name__ == "__main__":
    unittest.main()
