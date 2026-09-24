#!/usr/bin/env python3
"""The drainage gathers a hillside's water into gills, not a comb.

    python3 -m pytest tools/world/tests/test_erosion.py

The fault this exists for: a dale side the atlas draws as one even plane was carved by the
drainage pass with parallel rills a few cells apart, straight down the fall line, the whole
length of the Skerrow dales' south-facing slopes. D8 routing on an even slope sends every cell
straight down, and the flow lines only meet where the grid's own diagonals make them; the carve
then deepens every one of them. heights.apply_drainage now routes the water over the land plus
a few metres of broad unevenness (ROUTE_JITTER_M over ROUTE_JITTER_WL), which is what a real
hillside has, and the water gathers into a few gills.

The hillside here is synthetic and small (2 km square at the drainage pass's 8 m), with the
same kinds of noise on it the provinces put on theirs.
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import erosion as ER  # noqa: E402
from worldgen import heights as HM  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

N = 256                 # cells across
CELL_M = 8.0            # the drainage pass's lattice (heights.apply_drainage's work_n at 8192 m)
GRADE = 0.2             # a dale side: 20 m down in every 100 m, south-facing
STRONG = 0.5            # a channel at least this deep in the 0..1 channel field is a gill, not a rill
SEEDS = (1, 2, 3)


def hillside_channels(seed: int, jitter_m: float) -> np.ndarray:
    """The channel field of one even slope with a province's broad and fine noise on it."""
    grid = Grid(N * CELL_M, N, 256.0)
    bank = NoiseBank(seed, grid)
    z = (np.arange(N, dtype=np.float32) * CELL_M)[:, None] * np.ones((1, N), np.float32)
    h = 300.0 - GRADE * z + 1.5 * bank.field(7, 2.0, 200, 900) + 0.6 * bank.field(9, 1.6, 16, 120)
    jitter = jitter_m * bank.field(611, 2.0, *HM.ROUTE_JITTER_WL) if jitter_m else None
    return ER.channel_field(h.astype(np.float32), CELL_M, jitter=jitter)


def strong_channels_across(chan: np.ndarray, row: int) -> int:
    """How many separate channels deeper than STRONG a contour halfway down the slope crosses."""
    line = chan[row]
    peak = (line[1:-1] > line[:-2]) & (line[1:-1] >= line[2:]) & (line[1:-1] > STRONG)
    return int(peak.sum())


class HillsideTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        row = N // 2
        cls.plain = [strong_channels_across(hillside_channels(s, 0.0), row) for s in SEEDS]
        cls.jittered = [strong_channels_across(hillside_channels(s, HM.ROUTE_JITTER_M), row) for s in SEEDS]

    def test_routed_as_it_stands_the_slope_is_combed(self):
        # the fault, so that the next test is measuring something: one rill every 100 m or so
        width_m = N * CELL_M
        self.assertGreater(sum(self.plain) / len(SEEDS), width_m / 150.0, self.plain)

    def test_the_jitter_gathers_the_water_into_gills(self):
        self.assertLessEqual(sum(self.jittered) * 3, sum(self.plain), (self.jittered, self.plain))
        spacing_m = N * CELL_M * len(SEEDS) / max(sum(self.jittered), 1)
        self.assertGreater(spacing_m, 300.0, self.jittered)

    def test_every_hillside_still_has_a_gill(self):
        self.assertTrue(all(k >= 1 for k in self.jittered), self.jittered)


if __name__ == "__main__":
    unittest.main()
