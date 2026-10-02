#!/usr/bin/env python3
"""The dithered owner (the map the scatter and the ground's textures read) dissolves a border into
patches of the two provinces either side of it, and puts no province anywhere else: before, the
noise of every one of the twenty-two provinces counted at every texel, and a few texels in every
few hundred metres went to some far province -- a Briarwold giant oak with its bracken growing
on Cinderlea's ash plain beside the Founders' Delf.

    python3 -m pytest tools/world/tests/test_dithered_owner.py
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen.grid import Grid  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402
from worldgen.regions import RegionField, dithered_owner  # noqa: E402

N = 512
P = 22            # as many provinces as the atlas has
BLEND_M = 300.0   # geography.province_field's default blend


def _field() -> tuple[Grid, RegionField]:
    """P provinces in strips across a 4 km square, weighted as geography.province_field weights
    them: exp(-signed distance / (blend / 8)), normalised."""
    g = Grid(4096.0, N)
    X, _ = g.mesh()
    X = np.broadcast_to(X, (N, N)).astype(np.float32)
    width = g.size_m / P
    edges = g.x0 + width * np.arange(P + 1)
    scores = np.empty((P, N, N), dtype=np.float32)
    for k in range(P):
        # signed distance to the strip: negative inside
        sd = np.maximum(edges[k] - X, X - edges[k + 1])
        scores[k] = sd / (BLEND_M / 8.0)
    owner = np.argmin(scores, axis=0).astype(np.uint8)
    w = np.exp(-(scores - scores.min(axis=0)[None]))
    w /= w.sum(axis=0)[None]
    return g, RegionField(grid=g, weights=w.astype(np.float32), owner=owner)


class DitheredOwner(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.g, cls.rf = _field()
        cls.out = dithered_owner(cls.rf, N, NoiseBank(8471, cls.g))

    def test_no_province_far_from_its_own_land(self):
        """Every texel's dithered owner has its own land (the hard owner) within a blend's reach."""
        reach_m = BLEND_M * 0.5
        far = 0
        for k in range(P):
            got = self.out == k
            if not got.any():
                continue
            d = ndimage.distance_transform_edt(self.rf.owner != k) * self.g.spacing
            far += int((got & (d > reach_m)).sum())
        self.assertEqual(far, 0, "%d texels went to a province more than %.0f m from its land" % (far, reach_m))

    def test_borders_still_dissolve(self):
        """Near the borders the two sides still interleave: some texels within 60 m of a border
        go to the neighbour."""
        crossed = int((self.out != self.rf.owner).sum())
        self.assertGreater(crossed, N * P // 4, "the borders no longer dissolve (%d texels crossed)" % crossed)

    def test_every_texel_owned(self):
        self.assertTrue(int(self.out.max()) < P)


if __name__ == "__main__":
    unittest.main()
