#!/usr/bin/env python3
"""The texture rules and the colour map, worked a band of rows at a time (surface._Band), give the
maps they gave worked whole, texel for texel: the band size changes nothing but the memory.

    python3 -m pytest tools/world/tests/test_surface_bands.py
"""
from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import surface as SF  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.noise import NoiseBank, upsample  # noqa: E402

N = 512


def _world():
    n = N
    g = Grid(2048.0, n); bank = NoiseBank(7, g)
    X, Z = g.mesh(); X = np.broadcast_to(X, (n, n)); Z = np.broadcast_to(Z, (n, n))
    H = (60 + 40*np.sin(X/210.0)*np.cos(Z/170.0) + 0.05*X).astype(np.float32)
    shapes = ["downs", "lake_basin", "delta", "forest_rise", "mountains", "ash_plateau"]
    pal = ["#88aa55", "#aabb66", "#ddcc88", "#556633", "#998877", "#445566"]
    regions = [SimpleNamespace(index=i, shape=sh, palette=pal, id="r%d" % i) for i, sh in enumerate(shapes)]
    owner = (((X + 1024) // 400 + (Z + 1024) // 700) % 6).astype(np.uint8)
    class RF:
        def weight_at(self, k, m):
            o = owner if m == n else owner[::n//m, ::n//m]
            return (o == k).astype(np.float32)
    lake = SimpleNamespace(sd=(np.hypot(X - 300, Z + 200) - 180).astype(np.float32), cliffness=np.clip(X / 1024, 0, 1).astype(np.float32),
                           island_sd=(np.hypot(X - 300, Z + 200) - 40).astype(np.float32), causeway=(np.abs(Z + 200) < 4).astype(np.float32))
    water = (lake.sd < 0).astype(np.uint8)
    moist = (0.5 + 0.4*np.sin(X/90.0)).astype(np.float32)
    river_d = np.abs(X + 500).astype(np.float32); road_d = np.abs(Z - 300).astype(np.float32); road_w = np.full((n, n), 5.0, np.float32)
    pad = np.hypot(X + 200, Z - 300) < 40
    places = [{"id": "core:place/tamwick", "kind": "village", "position": [-200, 300]}, {"id": "core:place/tollmere", "kind": "city", "position": [300, -200]}]
    labels = (((X + 1024) // 150) * 20 + (Z + 1024) // 150).astype(np.int32); field_d = np.minimum(np.abs(((X + 1024) % 150) - 75), np.abs(((Z + 1024) % 150) - 75)).astype(np.float32)
    sea = (Z > 900); shore = np.zeros((n, n), np.uint8); shore[Z > 880] = 1
    return SF.SurfaceContext(g, bank, H, regions, owner, water, np.zeros((n, n), np.float32), moist, river_d, road_d,
                             road_w, pad, lake, places, rf=RF(), field_labels=labels, field_d=field_d, sea=sea,
                             shore=shore), RF()


class Bands(unittest.TestCase):
    def maps(self, rows: int):
        was = SF.BAND_ROWS
        SF.BAND_ROWS = rows
        try:
            ctx, rf = _world()
            return SF.control_maps(ctx), SF.colour_map(ctx, rf, work_n=N // 4)
        finally:
            SF.BAND_ROWS = was

    def test_any_band_gives_the_whole_world_s_maps(self):
        (cw, colw), (cb, colb) = self.maps(N), self.maps(37)
        for a, b in zip(cw, cb):
            np.testing.assert_array_equal(a, b)
        np.testing.assert_array_equal(colw, colb)

    def test_a_band_upsampled_is_the_rows_of_the_whole_upsampled(self):
        rng = np.random.default_rng(3)
        for m, n in ((256, 1024), (128, 512), (512, 512)):
            a = rng.standard_normal((m, m)).astype(np.float32)
            whole = upsample(a, n, order=1)
            for r0 in (0, 13, n - 40):
                np.testing.assert_array_equal(SF._band_up(a, n, r0, r0 + 40), whole[r0:r0 + 40])


if __name__ == "__main__":
    unittest.main()
