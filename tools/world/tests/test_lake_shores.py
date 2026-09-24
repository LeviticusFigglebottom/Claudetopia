#!/usr/bin/env python3
"""A pool drawn with a short shore keeps the land round it.

    python3 -m pytest tools/world/tests/test_lake_shores.py

`geography.apply_lakes` shapes a lake's shore for a few hundred metres round it: shingle, a bank
back to the land, and the ground held over the water so no dry hollow sits beside it. That suits
the Mere in its basin. A pool drawn at the foot of a fall got the same. On a 1024 build, the
Weaver's Linn flattened a basin three hundred metres across into the wold, 187 m deep at most,
fall and all, and the Blackgill Pot raised the valleys within 700 m of it to its level: one by
109 m, 380 m away. A lake's `shore_m` scales every one of those distances.
"""
from __future__ import annotations

import math
import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import geography as GEO  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

PLATEAU_M = 200.0
LEVEL_M = 150.0
RADIUS_M = 25.0


def _pool(shore_m=None) -> dict:
    ring = [[RADIUS_M * math.cos(a), RADIUS_M * math.sin(a)] for a in np.linspace(0.0, 2.0 * math.pi, 16, endpoint=False)]
    lake = {"id": "test_pool", "polygon": ring, "level_m": LEVEL_M, "depth_m": 5}
    if shore_m is not None:
        lake["shore_m"] = shore_m
    return {"lakes": [lake], "roads": []}


def _shape(atlas: dict, land: np.ndarray, grid: Grid) -> np.ndarray:
    wt = GEO.waters(grid, atlas, {})
    ctx = SimpleNamespace(grid=grid, f=lambda *a, **k: np.zeros((grid.n, grid.n), dtype=np.float32),
                          rock=None, peak=None)
    return GEO.apply_lakes(ctx, land.copy(), wt), wt


class ShortShore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(2048.0, 512)                       # 4 m texels
        n = cls.grid.n
        c = cls.grid.x0 + (np.arange(n) + 0.5) * cls.grid.spacing
        cls.r = np.hypot(c[None, :], c[:, None])            # metres from the pool's middle
        # a plateau with a valley 60 m under the pool's level, 300 m off to the east
        land = np.full((n, n), PLATEAU_M, dtype=np.float32)
        cls.valley = (np.abs(c[None, :] - 330.0) < 20.0) & np.ones((n, 1), bool)
        land[cls.valley] = LEVEL_M - 60.0
        cls.land = land
        cls.short, cls.wt = _shape(_pool(shore_m=40.0), land, cls.grid)
        cls.default, _ = _shape(_pool(), land, cls.grid)

    def test_the_land_past_a_short_shore_is_as_it_was(self):
        past = self.r > RADIUS_M + 2.0 * 40.0
        self.assertTrue(np.array_equal(self.short[past], self.land[past]))

    def test_a_short_shore_does_not_fill_a_valley_beyond_it(self):
        self.assertTrue(np.array_equal(self.short[self.valley], self.land[self.valley]))

    def test_the_pool_holds_water(self):
        middle = self.r < 8.0
        self.assertTrue(bool((self.short[middle] < LEVEL_M - 1.0).all()))

    def test_the_default_shore_is_the_basin_it_always_was(self):
        # (what the Mere is shaped with: the plateau 150 m out comes down toward the water, and
        # the valley 300 m off is filled most of the way up toward the water's level)
        ring = (self.r > 170.0) & (self.r < 180.0)
        self.assertLess(float(self.default[ring].max()), PLATEAU_M - 20.0)
        self.assertGreater(float(self.default[self.valley & (self.r < 400.0)].min()), LEVEL_M - 60.0 + 30.0)


if __name__ == "__main__":
    unittest.main()
