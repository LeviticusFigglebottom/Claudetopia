#!/usr/bin/env python3
"""The ash erodes (worldgen.landforms.ash_erosion): a smooth ash hill comes out with gullies down its
flanks, deepest where the most water gathers, slump scars and wind hollows, so its form breaks up at
20 to 200 m; the same inputs give the same land; and a pad and a road keep their ground.

    python3 -m pytest tools/world/tests/test_ash_erosion.py
"""
from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import landforms as LF  # noqa: E402
from worldgen.grid import Grid, smoothstep  # noqa: E402
from worldgen.heights import HeightContext  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402


def _ctx(n=512, size=2048.0):
    g = Grid(size, n)
    bank = NoiseBank(8471, g)
    X, Z = g.mesh(np.float64)
    r = SimpleNamespace(index=0, id="core:region/cinderlea", province="choir_plateau", shape="ash_plateau",
                        landforms=["ash_erosion"])
    rf = SimpleNamespace(weights=[np.ones((n, n), np.float32)])
    lake = SimpleNamespace(sd=np.full((n, n), 5000.0, np.float32), level=np.zeros((n, n), np.float32))
    ctx = HeightContext(grid=g, bank=bank, regions=[r], rf=rf, lake=lake, places=[])
    # a broad smooth ash dome 120 m high, 1.4 km across: the mounds round the Stair Head
    d = np.hypot(X, Z)
    h = (20.0 + 120.0 * np.clip(1.0 - (d / 700.0) ** 2, 0.0, 1.0) ** 1.5).astype(np.float32)
    h = np.broadcast_to(h, (n, n)).astype(np.float32)
    return ctx, r, h, X, Z


def _band_rms(a: np.ndarray, spacing: float, lo_m: float, hi_m: float) -> float:
    """RMS of `a` in the wavelengths lo_m..hi_m."""
    n = a.shape[0]
    f = np.fft.fftfreq(n, d=spacing)
    k = np.hypot(*np.meshgrid(f, f))
    band = (k >= 1.0 / hi_m) & (k <= 1.0 / lo_m)
    spec = np.fft.fft2(a - a.mean())
    return float(np.sqrt((np.abs(spec[band]) ** 2).sum()) / n / n)


class AshErosion(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ctx, cls.r, cls.h, cls.X, cls.Z = _ctx()
        cls.delta = LF.ash_erosion(cls.ctx, cls.h, cls.r)

    def test_the_dome_breaks_up_at_20_to_200_m(self):
        sp = self.ctx.grid.spacing
        before = _band_rms(self.h, sp, 20.0, 200.0)
        after = _band_rms(self.h + self.delta, sp, 20.0, 200.0)
        self.assertGreater(after, 2.0 * before, (before, after))

    def test_gullies_run_down_the_flanks_and_the_flat_top_is_gentler(self):
        d = np.hypot(self.X, self.Z)
        d = np.broadcast_to(d, self.h.shape)
        flank = (d > 350.0) & (d < 650.0)
        top = d < 150.0
        cut_flank = float(np.percentile(-self.delta[flank], 99))
        self.assertGreater(cut_flank, 2.5)
        self.assertLess(float(-self.delta.min()), LF.GULLY_M + 4.5)   # (a gully and a slump's hollow at most)
        # gullies on the flanks are deeper than the swales on the top
        self.assertGreater(cut_flank, float(np.percentile(-self.delta[top], 99)))

    def test_the_same_inputs_give_the_same_land(self):
        again = LF.ash_erosion(self.ctx, self.h, self.r)
        np.testing.assert_array_equal(again, self.delta)

    def test_a_pad_and_a_sightline_keep_their_ground(self):
        ctx = self.ctx
        _h, delta = LF.apply(ctx, self.h, discs=[(300.0, 0.0, 26.0)], lines=[(-600.0, -300.0, 600.0, -300.0)])
        g = ctx.grid
        near = np.broadcast_to(np.hypot(self.X - 300.0, self.Z), self.h.shape) < 1.3 * 26.0
        self.assertEqual(float(np.abs(delta[near]).max()), 0.0)
        corridor = LF.line_mask(g, [(-600.0, -300.0, 600.0, -300.0)], LF.LINE_CORRIDOR_M)
        self.assertLessEqual(float(delta[corridor].max()), 0.0)


if __name__ == "__main__":
    unittest.main()
