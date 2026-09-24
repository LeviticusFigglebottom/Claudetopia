#!/usr/bin/env python3
"""The land drawn along a line is smooth across it, and the upsampled land stays inside itself.

    python3 -m pytest tools/world/tests/test_land_lines.py

Two faults the hill-shading of the first full build of the drawn atlas showed:

* Every range's flanks, all down the Skerrow dales, were combed with dashes. `line_field` measured
  each texel to the nearest *sample* of the line, found through a distance transform of the samples
  rasterised, and a few hundred metres out that is tens of samples off the foot of the
  perpendicular: the distance and the arc position (and a range's crest height with it) came in
  steps of centimetres. It now projects onto the segments themselves.
* Upsampled from 2048 to 4096 with a cubic spline, the Skerrow Wall's 470 m sea cliff rang to 96 m
  under the seabed at its foot. `heights.upsample_held` holds the cubic inside the range of each
  coarse texel's neighbours.
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import geography as GEO  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.heights import upsample_held  # noqa: E402
from worldgen.noise import upsample  # noqa: E402

RIDGE = [[-900.0, -600.0], [-300.0, -80.0], [250.0, 40.0], [900.0, 700.0]]


class LineFieldTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(8192.0, 2048)
        cls.lf = GEO.line_field(cls.grid, RIDGE, 500.0)

    def test_the_distance_is_to_the_line_itself(self):
        i0, i1, j0, j1 = self.lf.window
        rng = np.random.default_rng(3)
        for _ in range(200):
            i, j = int(rng.integers(0, i1 - i0)), int(rng.integers(0, j1 - j0))
            x = self.grid.x0 + (j0 + j) * self.grid.spacing
            z = self.grid.z0 + (i0 + i) * self.grid.spacing
            want = ATLAS.distance_to_path(x, z, RIDGE)
            if want > 480.0:
                continue
            self.assertAlmostEqual(float(self.lf.d[i, j]), want, delta=1e-3)

    def test_the_arc_position_is_the_foot_of_the_perpendicular(self):
        # a range's crest height is read at this position; in steps, it combed the flanks
        pts = np.asarray(RIDGE)
        seg = np.diff(pts, axis=0)
        lens = np.linalg.norm(seg, axis=1)
        cum = np.concatenate([[0.0], np.cumsum(lens)])
        i0, i1, j0, j1 = self.lf.window
        rng = np.random.default_rng(5)
        checked = 0
        for _ in range(300):
            i, j = int(rng.integers(0, i1 - i0)), int(rng.integers(0, j1 - j0))
            x = self.grid.x0 + (j0 + j) * self.grid.spacing
            z = self.grid.z0 + (i0 + i) * self.grid.spacing
            u = np.clip(((x - pts[:-1, 0]) * seg[:, 0] + (z - pts[:-1, 1]) * seg[:, 1]) / lens ** 2, 0.0, 1.0)
            d2 = (x - pts[:-1, 0] - u * seg[:, 0]) ** 2 + (z - pts[:-1, 1] - u * seg[:, 1]) ** 2
            q = int(np.argmin(d2))
            if d2[q] > 480.0 ** 2:
                continue
            want = (cum[q] + u[q] * lens[q]) / cum[-1]
            self.assertAlmostEqual(float(self.lf.t[i, j]), want, delta=1e-5)
            checked += 1
        self.assertGreater(checked, 100)


class UpsampleHeldTest(unittest.TestCase):
    def test_a_cliff_does_not_ring(self):
        a = np.full((64, 64), -26.0, dtype=np.float32)
        a[:, 32:] = 470.0
        up = upsample_held(a, 128)
        self.assertGreaterEqual(float(up.min()), -26.0 - 1e-3)
        self.assertLessEqual(float(up.max()), 470.0 + 1e-3)
        plain = upsample(a, 128, order=3)
        self.assertLess(float(plain.min()), -40.0, "the plain cubic should ring, or this test measures nothing")

    def test_a_smooth_slope_is_the_cubic(self):
        x = np.linspace(0.0, 1.0, 64, dtype=np.float32)
        a = (120.0 * x[None, :] + 30.0 * np.sin(3.0 * x)[:, None]).astype(np.float32)
        diff = np.abs(upsample_held(a, 128) - upsample(a, 128, order=3))
        self.assertLess(float(np.percentile(diff, 99)), 0.05)


if __name__ == "__main__":
    unittest.main()
