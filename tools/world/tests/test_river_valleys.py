#!/usr/bin/env python3
"""A river held level through high ground runs in a gorge, not in a slot.

    python3 -m pytest tools/world/tests/test_river_valleys.py

`hydro.carve_river_valleys` holds the land beside a river under its valley side, out to half the
valley's width. It used to fade back to the untouched land over the last fifth of that width, and
where a river is held level through a ridge the fade was a wall. On the final build of the drawn
atlas the Brindle Beck, the Rudd Beck and the Rib Beck ran through the Skerrow dales' southern
ridge in slots 90 to 110 m wide, and the Brindle Beck's walls fell 55 m in one 9.4 m step. Past
the valley, a gorge wall now climbs at GORGE_GRADE until it meets the land.

Cut as a plane, that wall was a smooth ramp a hundred metres across in rough fell. With the
build's noise bank, its line wanders as spurs and gullies and its face has a grain (WanderingWall).
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import hydro as HY  # noqa: E402
from worldgen import paths  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

PLATEAU_M = 120.0
WATER_M = 60.0
WIDTH_M = 9.0
## the river runs down a column of texel centres, so a texel's distance from it is exact
RIVER_X = 1.0


def _river(valley_m=None) -> HY.River:
    """A straight river down the middle of the window, held at WATER_M through the plateau."""
    pts = paths.resample_polyline(np.array([[RIVER_X, -900.0], [RIVER_X, 900.0]]), 20.0)
    k = pts.shape[0]
    return HY.River(id="test:river/held", points=pts, width=np.full(k, WIDTH_M, np.float32),
                    surface=np.full(k, WATER_M, np.float32), valley_m=valley_m)


class GorgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(2048.0, 1024)                      # 2 m texels, as a full build
        n = cls.grid.n
        x = cls.grid.x0 + (np.arange(n) + 0.5) * cls.grid.spacing
        cls.dist = np.abs(np.broadcast_to(x[None, :] - RIVER_X, (n, n)))   # metres from the river
        land = np.full((n, n), PLATEAU_M, dtype=np.float32)
        # a hollow east of the river that lies under the valley side: a gorge leaves it be
        cls.hollow = (x[None, :] > 130.0) & (x[None, :] < 170.0) & np.ones((n, 1), bool)
        land[cls.hollow] = 50.0
        cls.land = land
        cls.carved = HY.carve_river_valleys(cls.grid, land.copy(), [_river()])
        cls.reach = HY.VALLEY_WIDTHS * WIDTH_M * 0.5
        # the rows away from the river's ends, where the valley is a straight cut
        cls.rows = slice(n // 2 - 300, n // 2 + 300)

    def test_no_side_is_steeper_than_a_gorge_wall(self):
        h = self.carved[self.rows].astype(np.float64)
        gz, gx = np.gradient(h, self.grid.spacing)
        steep = np.hypot(gx, gz)
        near = self.dist[self.rows] < 120.0
        self.assertLess(float(steep[near].max()), HY.GORGE_GRADE * 1.1,
                        "the valley's side is a wall %.1f steep" % steep[near].max())

    def test_the_valley_floor_climbs_from_the_banks(self):
        row = self.carved[self.grid.n // 2]
        d = self.dist[self.grid.n // 2]
        for want_d in (10.0, 30.0, 50.0):
            j = int(np.argmin(np.abs(d - want_d) + (np.arange(d.size) < self.grid.n // 2) * 1e9))
            want = WATER_M + 1.0 + HY.VALLEY_GRADE * (d[j] - WIDTH_M * 0.5)
            self.assertAlmostEqual(float(row[j]), want, delta=0.05)

    def test_the_gorge_wall_meets_the_land_and_stops(self):
        # 71.9 m at the valley's edge, then 1.2 a metre: the plateau at 120 m is met 40 m on
        top = WATER_M + 1.0 + HY.VALLEY_GRADE * (self.reach - WIDTH_M * 0.5)
        meets = self.reach + (PLATEAU_M - top) / HY.GORGE_GRADE
        west = self.dist[self.rows] > meets + 3.0
        west &= (np.arange(self.grid.n)[None, :] < self.grid.n // 2)
        self.assertTrue(np.array_equal(self.carved[self.rows][west], self.land[self.rows][west]))
        cut = (self.dist[self.rows] > self.reach + 5.0) & (self.dist[self.rows] < meets - 5.0)
        self.assertTrue(bool((self.carved[self.rows][cut] < PLATEAU_M - 1.0).all()),
                        "the land between the valley and the plateau was not cut back")

    def test_land_under_the_valley_side_is_left_as_it_was(self):
        hollow = self.hollow[self.rows]
        self.assertTrue(np.array_equal(self.carved[self.rows][hollow], self.land[self.rows][hollow]))

    def test_a_river_with_no_valley_leaves_the_land_to_its_banks(self):
        out = HY.carve_river_valleys(self.grid, self.land.copy(), [_river(valley_m=0.0)])
        self.assertTrue(np.array_equal(out, self.land))


class RiverHead(unittest.TestCase):
    """A river that rises in the middle of the plateau and runs south through it."""

    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(2048.0, 1024)
        n = cls.grid.n
        c = cls.grid.x0 + (np.arange(n) + 0.5) * cls.grid.spacing
        cls.x = np.broadcast_to(c[None, :], (n, n))
        cls.z = np.broadcast_to(c[:, None], (n, n))
        cls.land = np.full((n, n), PLATEAU_M, dtype=np.float32)
        pts = paths.resample_polyline(np.array([[RIVER_X, 0.0], [RIVER_X, 900.0]]), 20.0)
        k = pts.shape[0]
        river = HY.River(id="test:river/head", points=pts, width=np.full(k, WIDTH_M, np.float32),
                         surface=np.full(k, WATER_M, np.float32))
        cls.carved = HY.carve_river_valleys(cls.grid, cls.land.copy(), [river])
        cls.reach = HY.VALLEY_WIDTHS * WIDTH_M * 0.5

    def test_the_land_behind_the_source_is_left_as_it_was(self):
        # the Rudd Beck's head cut a bowl into the fell behind it, and took 5 m off the Fallen
        # Hand's knoll 80 m up the fell after the saddle under its line had been cut
        behind = self.z < -2.0
        self.assertTrue(np.array_equal(self.carved[behind], self.land[behind]))

    def test_the_valley_comes_in_down_the_river(self):
        across = np.abs(self.x - RIVER_X) < 30.0
        cut = self.land - self.carved
        near = float(cut[across & (np.abs(self.z - 10.0) < 2.0)].max())
        full = float(cut[across & (np.abs(self.z - 400.0) < 2.0)].max())
        self.assertLess(near, full * 0.5, "the valley is at %.1f of its depth 10 m from the source" % (near / full))
        # and down the river it is the whole valley: 58 m cut out of the plateau at the bank
        self.assertAlmostEqual(full, PLATEAU_M - (WATER_M + 1.0 + HY.VALLEY_GRADE * 0.0), delta=1.5)


class NarrowHead(unittest.TestCase):
    """A beck two metres wide at its head is water along its whole line, on the diagonal too.

    Its water is one texel wide at 2 m texels, and on the diagonal its texels meet only at their
    corners. The water mask's speck filter counted them side by side, and on the final build of
    the drawn atlas the heads of the Cressbourne, the Blackgill and Weaver's Gill were dry for
    stretches of their first hundred metres (test_roads: test_no_river_is_dammed)."""

    def test_a_diagonal_line_of_water_is_kept_and_a_lone_texel_is_not(self):
        from types import SimpleNamespace

        grid = Grid(512.0, 256)                          # 2 m texels, as a full build
        n = grid.n
        H = np.full((n, n), 10.0, dtype=np.float32)
        line = np.zeros((n, n), dtype=bool)
        for k in range(30):
            line[100 + k, 60 + k] = True                 # thirty texels corner to corner
        line[20, 200] = True                             # and one alone
        river_d = np.where(line, 0.0, 1e6).astype(np.float32)
        lake = SimpleNamespace(in_lake=lambda h: np.zeros(h.shape, dtype=bool),
                               level=np.zeros((n, n), dtype=np.float32))
        out = HY.water_maps(grid, H, lake, np.zeros((n, n), dtype=bool), [], river_d,
                            np.full((n, n), 11.0, dtype=np.float32), np.full((n, n), 2.0, dtype=np.float32),
                            np.zeros((n, n), dtype=np.int32), [], None)
        wet = out.mask > 0
        self.assertEqual(int(wet[100:130, 60:90].sum()), 30, "the diagonal beck is broken into specks")
        self.assertFalse(bool(wet[20, 200]), "a lone wet texel is noise and is dropped")


class Meanders(unittest.TestCase):
    """A drawn river wanders between its drawn points, and not in steep country or by a bridge.

    Built on the atlas's lines, the rivers ran ruler-straight for hundreds of metres between their
    points, and read as canals on the chart and from the ground."""

    PATH = [[-600.0, -600.0], [0.0, -100.0], [700.0, 0.0]]

    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(2048.0, 512)
        n = cls.grid.n
        cls.flat = np.full((n, n), 50.0, dtype=np.float32)
        x = cls.grid.x0 + (np.arange(n) + 0.5) * cls.grid.spacing
        cls.steep = (50.0 + 0.3 * np.broadcast_to(x[None, :], (n, n))).astype(np.float32)

    def off_line(self, line):
        from worldgen import atlas as ATLAS

        return np.array([ATLAS.distance_to_path(float(x), float(z), self.PATH) for x, z in line])

    def test_it_wanders_and_passes_every_drawn_point(self):
        line = HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a")
        off = self.off_line(line)
        self.assertGreater(float(off.max()), 20.0, "the river is still its drawn line")
        self.assertLess(float(off.max()), 70.0)
        for v in self.PATH:
            self.assertLess(float(np.hypot(line[:, 0] - v[0], line[:, 1] - v[1]).min()), 0.01)
        gaps = np.linalg.norm(np.diff(line, axis=0), axis=1)
        self.assertLessEqual(float(gaps.max()), 21.0)

    def test_it_is_the_same_river_every_build(self):
        a = HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a")
        b = HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a")
        self.assertTrue(np.array_equal(a, b))

    def test_it_is_straighter_down_a_steep_valley(self):
        flat = self.off_line(HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a"))
        steep = self.off_line(HY.meander(self.PATH, (6.0, 10.0), self.steep, self.grid, "test:river/a"))
        self.assertLess(float(np.percentile(steep, 90)), 0.75 * float(np.percentile(flat, 90)))

    def test_it_keeps_to_its_line_by_a_bridge(self):
        bridge = np.array([[-300.0, -350.0]])
        line = HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a", bridge)
        near = np.hypot(line[:, 0] - bridge[0, 0], line[:, 1] - bridge[0, 1]) < HY.AVOID_NEAR_M
        self.assertTrue(near.any())
        self.assertLess(float(self.off_line(line[near]).max()), 1.0)

    def test_the_atlas_can_hold_a_river_to_its_line(self):
        line = HY.meander(self.PATH, (6.0, 10.0), self.flat, self.grid, "test:river/a", scale=0.0)
        self.assertLess(float(self.off_line(line).max()), 0.01)


class Falls(unittest.TestCase):
    """Down its falls a river's water follows the face, and its channel is cut to the water there,
    not left hanging under it. Drawn straight between points 20 m apart down a cliff between
    them, the channel cut a trench into the land above the cliff and built a levee over its foot;
    and a texel took the level the river last had in it, not the level by its centre, so down a
    fall the bed was cut to the water further down."""

    SP = 2.0     # the texel of the 4096 build

    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(512.0, int(512.0 / cls.SP))
        X, Z = cls.grid.mesh()
        X = np.broadcast_to(X, (cls.grid.n, cls.grid.n))
        Z = np.broadcast_to(Z, (cls.grid.n, cls.grid.n))
        # a cliff falling 2.5 in 1 from x = 0 to 30, on a hillside falling across the river
        cls.H = (np.where(X < 0, 200.0 - 0.1 * X, np.where(X < 30, 200.0 - 2.5 * X, 125.0 - 0.1 * (X - 30)))
                 - 0.6 * Z).astype(np.float32)
        cls.bank = NoiseBank(4242, cls.grid)

    def carve(self, step):
        from worldgen.grid import sample_bilinear

        line = np.array([[-193.0, 0.0], [207.0, 0.0]])
        fine = paths.resample_polyline(line, HY.FALL_SAMPLE_M)
        h = sample_bilinear(self.H, self.grid, fine[:, 0], fine[:, 1]).astype(np.float64)
        keep = HY.fall_points(fine, h) if step is None else np.arange(0, fine.shape[0], int(step / HY.FALL_SAMPLE_M))
        pts, h = fine[keep], h[keep]
        surf = HY._monotone_profile(h, float(h[0] - 0.5), float(h[-1] - 1.0))
        r = HY.River(id="x", points=pts, width=np.full(len(pts), 5.0, dtype=np.float32), surface=surf)
        Hc, *_ = HY.carve_rivers(self.grid, self.H.copy(), [r], self.bank)
        x = np.arange(pts[0, 0], pts[-1, 0], 0.5)
        z = np.zeros_like(x)
        water = np.interp(x, pts[:, 0], surf)
        return pts, water - sample_bilinear(Hc, self.grid, x, z), sample_bilinear(Hc - self.H, self.grid, x, z)

    def test_a_steep_stretch_keeps_its_points_close_and_a_gentle_one_does_not(self):
        pts, _over, _dh = self.carve(None)
        gaps = np.diff(pts[:, 0])
        at = pts[1:, 0]
        self.assertTrue(np.allclose(gaps[(at > 0.0) & (at < 30.0)], HY.FALL_SAMPLE_M))
        self.assertTrue(np.allclose(gaps[(at < -40.0) | (at > 70.0)], HY.RIVER_STEP_M))

    def test_the_water_sits_in_its_channel_down_the_fall(self):
        _pts, over, _dh = self.carve(None)
        self.assertEqual(int((over > 3.0).sum()), 0, "the water hangs %.1f m over its bed" % over.max())

    def test_the_channel_follows_the_face(self):
        _p, _o, dh20 = self.carve(20.0)
        _p, _o, dh = self.carve(None)
        # drawn every 20 m: a trench above the cliff and a levee at its foot
        self.assertGreater(float(dh20.max()), 3.5)
        self.assertLess(float(dh.max()), 2.0, "the bed is built %.1f m out over the land" % dh.max())
        self.assertLess(float(-dh.min()), 0.5 * float(-dh20.min()))

    def test_a_texel_takes_the_level_by_its_centre(self):
        grid = Grid(64.0, 32)
        line = np.array([[-30.0, 0.3], [30.0, 0.3]])
        value = np.array([100.0, 40.0])
        mask = np.zeros((grid.n, grid.n), dtype=bool)
        out = np.zeros((grid.n, grid.n), dtype=np.float32)
        paths.rasterise_polyline(line, grid, value=value, out_mask=mask, out_value=out, at_centre=True)
        i, j = np.nonzero(mask)
        x = grid.x0 + j * grid.spacing
        self.assertLess(float(np.abs(out[i, j] - np.interp(x, line[:, 0], value)).max()), 1.0)


class LandformsBesideARiver(unittest.TestCase):
    """No landform digs a pit below a river's water beside it (landforms.river_guard). A limestone
    scar across the Brindle Beck's head took its bed 9.7 m under the water, and the river's ribbon
    hung over the hole."""

    def test_a_pit_by_the_river_stops_over_its_water_and_one_away_from_it_does_not(self):
        from worldgen import landforms as LF

        n = 64
        H = np.full((n, n), 102.0, dtype=np.float32)
        river_d = np.broadcast_to(np.abs(np.arange(n, dtype=np.float32) * 2.0 - 20.0)[None, :], (n, n)).copy()
        surf = np.full((n, n), 100.0, dtype=np.float32)
        width = np.full((n, n), 6.0, dtype=np.float32)
        delta = np.full((n, n), -8.0, dtype=np.float32)          # a pit everywhere
        delta[0, :] = 3.0                                        # and a rise in one row
        out = LF.river_guard(H, delta, river_d, surf, width)
        near = river_d[1:] <= 3.0 + LF.RIVER_GUARD_M
        self.assertTrue(np.allclose((H + out)[1:][near], 100.5))
        self.assertTrue(np.allclose(out[1:][~near], -8.0))
        self.assertTrue(np.allclose(out[0], 3.0), "a landform may still raise the land")


class WanderingWall(unittest.TestCase):
    """The same gorge through a flat plateau, carved with a noise bank as a build carves it."""

    @classmethod
    def setUpClass(cls):
        cls.grid = Grid(2048.0, 1024)
        n = cls.grid.n
        x = cls.grid.x0 + (np.arange(n) + 0.5) * cls.grid.spacing
        cls.dist = np.abs(np.broadcast_to(x[None, :] - RIVER_X, (n, n)))
        cls.west = np.broadcast_to(np.arange(n)[None, :] < n // 2, (n, n))
        land = np.full((n, n), PLATEAU_M, dtype=np.float32)
        cls.plane = HY.carve_river_valleys(cls.grid, land.copy(), [_river()])
        cls.carved = HY.carve_river_valleys(cls.grid, land.copy(), [_river()], NoiseBank(8471, cls.grid))
        cls.reach = HY.VALLEY_WIDTHS * WIDTH_M * 0.5
        cls.rows = slice(n // 2 - 300, n // 2 + 300)

    def test_the_banks_are_as_they_were(self):
        banks = self.dist[self.rows] <= WIDTH_M * 0.5 + 2.0
        self.assertTrue(np.array_equal(self.carved[self.rows][banks], self.plane[self.rows][banks]))

    def test_the_valley_floor_rolls_and_stays_over_the_water(self):
        # a smooth ramp a hundred metres wide read from above as a made thing
        floor = (self.dist[self.rows] > WIDTH_M * 0.5 + 2.0 + HY.FLOOR_INTO_M) & (self.dist[self.rows] < self.reach)
        off = self.carved[self.rows][floor] - self.plane[self.rows][floor]
        self.assertGreater(float(off.std()), 0.5, "the floor is still a plane")
        self.assertGreaterEqual(float(self.carved[self.rows][floor].min()), WATER_M + HY.FLOOR_OVER_M - 1e-3)

    def test_the_wall_wanders_along_the_river(self):
        # where the wall's top meets the plateau, row by row, on the west side: a plane meets it
        # at one distance; this one stands out and falls back by metres
        h = self.carved[self.rows]
        cut = (h < PLATEAU_M - 0.01) & self.west[self.rows]
        meet = np.array([self.dist[self.rows][r, np.nonzero(cut[r])[0].min()] for r in range(h.shape[0])])
        self.assertGreater(float(meet.std()), 4.0)

    def test_a_wall_with_a_grain_is_still_no_cliff(self):
        # the slot fell at 6.6; a wall with its grain stays well under that, and mostly near 1.2
        h = self.carved[self.rows].astype(np.float64)
        gz, gx = np.gradient(h, self.grid.spacing)
        steep = np.hypot(gx, gz)[self.dist[self.rows] < 150.0]
        self.assertLess(float(steep.max()), 3.5)
        self.assertLess(float(np.percentile(steep, 95)), 2.0)


if __name__ == "__main__":
    unittest.main()
