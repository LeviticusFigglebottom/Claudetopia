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


class Tint(unittest.TestCase):
    """The colour map tints the grass and does not paint it: Terrain3D multiplies it over the albedo,
    and at x2 chroma clipped at 0.40 w4096c's Hearthvale was (230, 230, 128), mustard grass. With
    the regions' own palettes no channel is more than about halved, the downs keep their blue, and
    each region keeps its own cast (Sedgemire's teal-olive, the Briarwold's green)."""

    def test_green_stays_green_and_each_region_keeps_its_cast(self):
        from worldgen.regions import load_regions

        repo = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
        real = {r.shape: r for r in load_regions(os.path.join(repo, "game", "content", "packs", "core", "regions",
                                                              "regions.json"))}
        ctx, rf = _world()
        for r in ctx.regions:
            r.palette = real[r.shape].palette
        col = SF.colour_map(ctx, rf, work_n=N // 4)[..., :3].astype(np.float32) / 255.0
        far = (ctx.field_d > 12) & (ctx.road_d > 20)      # the fields, off the hedge lines and roads
        med = {}
        for r in ctx.regions:
            c = col[(ctx.owner == r.index) & far]
            ratio = c.min(axis=1) / np.maximum(c.max(axis=1), 1e-3)
            self.assertGreater(float(np.percentile(ratio, 1)), 0.62, r.shape)
            med[r.shape] = np.median(c, axis=0)
        self.assertGreater(float(med["downs"][2]), 0.7, "the downs' blue is halved: mustard grass")
        self.assertLess(float(med["delta"][0]), 0.88, "Sedgemire has lost its cast")
        self.assertLess(float(med["forest_rise"][2]), 0.88, "the Briarwold has lost its cast")
        self.assertGreater(float(np.abs(med["delta"] - med["downs"]).max()), 0.1)


def _ramp(shape: str):
    """One region of `shape` on a ramp whose slope climbs from level to 58 degrees across x."""
    n = 512
    g = Grid(1024.0, n); bank = NoiseBank(9, g)
    X, Z = g.mesh(); X = np.broadcast_to(X, (n, n)).astype(np.float64); Z = np.broadcast_to(Z, (n, n))
    a = 1.6 / 1024.0
    # the slope a * (x + 512) along x, summed texel by texel into heights
    H = (20.0 + np.cumsum(np.broadcast_to(a * (X[0] + 512.0), (n, n)) * g.spacing, axis=1)).astype(np.float32)
    regions = [SimpleNamespace(index=0, shape=shape, palette=["#88aa55", "#aabb66", "#ddcc88"], id="r0")]
    owner = np.zeros((n, n), np.uint8)
    class RF:
        def weight_at(self, k, m):
            return np.ones((m, m), np.float32) if k == 0 else np.zeros((m, m), np.float32)
    lake = SimpleNamespace(sd=np.full((n, n), 5000.0, np.float32), cliffness=np.zeros((n, n), np.float32),
                           island_sd=np.full((n, n), 5000.0, np.float32), causeway=np.zeros((n, n), np.float32))
    far = np.full((n, n), 1e5, np.float32)
    ctx = SF.SurfaceContext(g, bank, H, regions, owner, np.zeros((n, n), np.uint8), np.zeros((n, n), np.float32),
                            np.full((n, n), 0.4, np.float32), far, far, np.full((n, n), 5.0, np.float32),
                            np.zeros((n, n), bool), lake, [], rf=RF(), field_labels=np.zeros((n, n), np.int32),
                            field_d=far, sea=np.zeros((n, n), bool), shore=np.zeros((n, n), np.uint8))
    return ctx


class Steep(unittest.TestCase):
    """Steep ground is not grass painted down a wall: past about 30 degrees the earth shows, past about
    42 it is scree and rock with the turf in patches, and what a player cannot walk up is bare rock
    (surface.STEEP; the playtest-6 bank)."""

    GRASS = {SF.SLOTS[k] for k in SF.STEEP_THINS}

    def shares(self, shape):
        ctx = _ramp(shape)
        base, overlay, blend = SF.control_maps(ctx)
        deg = np.degrees(np.arctan(ctx.slope))
        f = blend.astype(np.float32) / 255.0
        grass = np.isin(base, list(self.GRASS)) * (1.0 - f) + np.isin(overlay, list(self.GRASS)) * f
        _e, scree, rock = (SF.SLOTS[k] for k in SF.STEEP[shape][1])
        stone = np.isin(base, [scree, rock]) * (1.0 - f) + np.isin(overlay, [scree, rock]) * f
        out = {}
        for lo, hi in ((5, 20), (29, 33), (40, 44), (52, 58)):
            m = (deg >= lo) & (deg < hi)
            m[:, :4] = False; m[:, -4:] = False
            out[lo] = (float(grass[m].mean()), float(stone[m].mean()))
        return out, base, deg

    def test_grass_gives_way_to_earth_then_scree_then_bare_rock(self):
        for shape in ("downs", "lake_basin", "forest_rise", "ash_plateau"):
            got, base, deg = self.shares(shape)
            gentle, earthy, scree, sheer = got[5], got[29], got[40], got[52]
            if shape != "ash_plateau":
                self.assertGreater(gentle[0], 0.6, (shape, got))
            self.assertLess(sheer[0], 0.08, (shape, got))
            self.assertGreater(sheer[1], 0.85, (shape, got))
            self.assertLess(scree[0], 0.45, (shape, got))
            self.assertGreater(scree[1], 0.3, (shape, got))
            # a band where the turf gives out, not a line: over 4 degrees or more of slope each
            # contour is part grass and part not
            if shape != "ash_plateau":
                mixed = 0
                for d in range(10, 58):
                    m = (deg >= d) & (deg < d + 1)
                    on = float(np.isin(base[m], list(self.GRASS)).mean()) if m.any() else 0.0
                    mixed += 0.1 < on < 0.9
                self.assertGreaterEqual(mixed, 4, shape)


if __name__ == "__main__":
    unittest.main()
