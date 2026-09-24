#!/usr/bin/env python3
"""A shelf's seaward edge is broken the way the sea breaks rock, and the pad on it is left whole.

    python3 -m pytest tools/world/tests/test_shelf_edge.py

The landing under the Stair Head was drawn as a clean arc two hundred metres across, and built as
one it read as something laid out with a compass. `geography.break_shelf_edges` lets the drawn
edge wander in and out (spurs and bites), lays blocks fallen from the face in the water under it,
and cuts each of the shelf's `notches` down into the sea for a stair to go down. None of it may
touch the pad the first fight stands on, and the pad's own skirt may not fill the sea at the foot
of the face (`roads.PAD_DROP_M`).

Synthetic and small: a kilometre square at 2 m, the mainland to the north, a half-round shelf at
4 m running out from it into a sea 4 m deep, and a pad of 26 m on the shelf.
"""
from __future__ import annotations

import math
import os
import sys
import unittest

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import geography as GEO  # noqa: E402
from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

TOP = 4.0
PAD = (0.0, 38.0, 26.0)          # x, z, radius: its footprint reaches z = 64
NOTCH = (0.0, 70.0)              # on the seaward edge, due south of the pad
# a half-round shelf from the land (z < 0) out to z = 70, 220 m across, drawn back under the land
SHELF = [[-110.0, -20.0]] + [[-110.0 * math.cos(a), 70.0 * math.sin(a)] for a in np.linspace(0.0, math.pi, 25)] \
    + [[110.0, -20.0]]
MAINLAND = [[-512.0, -512.0], [512.0, -512.0], [512.0, 0.0], [-512.0, 0.0]]


def world():
    grid = Grid(1024.0, 512)
    X, Z = grid.mesh()
    land = GEO.polygon_mask(grid, MAINLAND)
    shelf = GEO.polygon_mask(grid, SHELF)
    H = np.where(land, 60.0, -4.0 + 0.0 * X + 0.0 * Z).astype(np.float32)
    H[shelf] = TOP
    atlas = {"coast": {"polygon": MAINLAND, "shelves": [{"polygon": SHELF, "height_m": TOP, "bank_m": 90,
                                                          "notches": [list(NOTCH)]}]}}
    return grid, H, shelf, atlas


class ShelfEdgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid, cls.H0, cls.shelf, cls.atlas = world()
        cls.H = GEO.break_shelf_edges(cls.grid, cls.H0.copy(), cls.atlas, NoiseBank(8471, cls.grid),
                                      keep_discs=[PAD])
        X, Z = cls.grid.mesh()
        cls.X = X + 0.0 * Z
        cls.Z = Z + 0.0 * X

    def at(self, x, z):
        j = int(round((x - self.grid.x0) / self.grid.spacing))
        i = int(round((z - self.grid.z0) / self.grid.spacing))
        return float(self.H[i, j])

    def test_the_pad_is_left_whole(self):
        px, pz, r = PAD
        foot = (self.X - px) ** 2 + (self.Z - pz) ** 2 <= r * r
        self.assertTrue(np.array_equal(self.H[foot], self.H0[foot]))
        self.assertGreaterEqual(float(self.H[foot].min()), TOP)

    def test_the_seaward_edge_wanders_in_and_out(self):
        # where the shelf top ends along rays out from the middle of the half-round, away from the pad
        ends = []
        for a in np.radians(np.linspace(20.0, 60.0, 30)):
            for side in (-1.0, 1.0):
                ux, uz = side * math.cos(a), math.sin(a)
                drawn = 1.0 / math.hypot(ux / 110.0, uz / 70.0)
                last = 0.0
                for s in np.arange(10.0, drawn + 20.0, 1.0):
                    if self.at(ux * s, uz * s) >= TOP - 0.5:
                        last = s
                ends.append(last - drawn)
        ends = np.asarray(ends)
        self.assertGreater(float(ends.max()), 2.0, "no spur runs out past the drawn edge")
        self.assertLess(float(ends.min()), -2.0, "no bite is cut into the drawn edge")
        self.assertLess(float(np.abs(ends).max()), GEO.SHELF_EDGE_M + 3.0)

    def test_blocks_lie_in_the_water_at_its_foot(self):
        out = ~self.shelf & (self.Z > 0.0)
        grew = out & (self.H > 0.0) & (self.H < TOP - 1.0)
        self.assertGreater(int(grew.sum()), 10, "no fallen block stands out of the water")

    def test_the_notch_goes_down_into_the_sea(self):
        nx, nz = NOTCH
        self.assertLessEqual(self.at(nx, nz - GEO.SHELF_NOTCH_IN_M - 2.0), TOP + 0.01)
        self.assertGreater(self.at(nx, nz - GEO.SHELF_NOTCH_IN_M - 2.0), TOP - 0.5, "the shelf behind the notch is cut")
        self.assertLess(self.at(nx, nz - 3.0), TOP - 1.0, "the notch's inner end is not a step down")
        self.assertLess(self.at(nx, nz), 0.0, "the notch does not reach the water")

    def test_the_land_behind_is_not_touched(self):
        land = GEO.polygon_mask(self.grid, MAINLAND) & ~self.shelf
        self.assertTrue(np.array_equal(self.H[land], self.H0[land]))

    def test_the_back_edge_and_a_road_across_the_shelf_are_left_alone(self):
        # The Hushline's stair comes down the bank graded to the landing, so for tens of metres the
        # land behind the shelf's back edge is at the shelf's own height. Measured only from the
        # ground standing over the shelf, that back edge was broken too, and a bite cut 6.5 m of
        # sea through the stair. Here the land behind comes down to 4.5 m for 30 m, and a road
        # runs across the shelf from the land to the sea.
        X = self.X
        Z = self.Z
        low_bank = (Z < -20.0) & (Z > -50.0) & (np.abs(X) < 60.0)
        H0 = np.where(low_bank, TOP + 0.5, self.H0).astype(np.float32)
        road = np.abs(X + 30.0) < 4.0
        H = GEO.break_shelf_edges(self.grid, H0.copy(), self.atlas, NoiseBank(8471, self.grid),
                                  keep_discs=[PAD], keep=road)
        back = self.shelf & (Z < -10.0)
        self.assertTrue(np.array_equal(H[back], H0[back]), "the shelf's back edge was broken")
        self.assertTrue(np.array_equal(H[road], H0[road]), "the road across the shelf was cut")
        # and the seaward edge is still broken either side of the road
        edge = ~self.shelf & (Z > 0.0) & (np.abs(X) < 110.0)
        self.assertFalse(np.array_equal(H[edge], H0[edge]))

    def test_a_bitten_edge_leaves_no_rib_of_the_drawn_arc(self):
        # The coast drawn over the Hushline's shelf stands a band of land a few metres wide at the
        # cliff's height just outside the shelf's seaward edge. Cut only inside the polygon, the
        # drawn arc was left standing as a rib with the bites behind it as pools. Here that band is
        # 3 m wide at the shelf's height, and the fallen blocks are left out.
        grid, H0, shelf, atlas = world()
        sd = GEO.signed_distance(grid, shelf)
        H0 = np.where((sd > 0.0) & (sd <= 3.0) & (self.Z > 0.0), TOP, H0).astype(np.float32)
        keep_blocks = GEO.SHELF_BLOCKS_PER_100M
        GEO.SHELF_BLOCKS_PER_100M = 0.0
        try:
            H = GEO.break_shelf_edges(grid, H0.copy(), atlas, NoiseBank(8471, grid), keep_discs=[PAD])
        finally:
            GEO.SHELF_BLOCKS_PER_100M = keep_blocks
        # A rib is the band still standing with water on both sides of it across the edge: 6 m in
        # toward the shelf (a bite) and 6 m out (the sea). The notch, due south, has walls of its own.
        gi, gj = np.gradient(ndimage.gaussian_filter(sd, 2.0))
        norm = np.maximum(np.hypot(gi, gj), 1e-6)
        ii, jj = np.nonzero((sd > 0.0) & (sd <= 3.0) & (self.Z > 0.0) & (H > 1.0) & (np.abs(self.X) > 12.0))
        ribs = []
        k = 3
        for i, j in zip(ii, jj):
            ui, uj = gi[i, j] / norm[i, j], gj[i, j] / norm[i, j]
            a = (int(round(i - k * ui)), int(round(j - k * uj)))
            b = (int(round(i + k * ui)), int(round(j + k * uj)))
            if H[a] < 0.0 and H[b] < 0.0:
                ribs.append("(%.0f, %.0f): %.1f m" % (float(self.X[i, j]), float(self.Z[i, j]), float(H[i, j])))
        self.assertEqual(ribs, [], "the drawn arc stands as a rib beyond its bites")

    def test_a_coast_drawn_over_the_shelf_does_not_hold_its_edge(self):
        # The Hushline's coast polygon has a lobe over the whole shelf, with a low cliff along the
        # shelf's seaward edge. Measured from the coast, the edge had nowhere to wander and was
        # built as the clean arc it was drawn as.
        lobe = [[-512.0, -512.0], [512.0, -512.0], [512.0, 0.0], [110.0, 0.0]] \
            + [[110.0 * math.cos(a), 70.0 * math.sin(a)] for a in np.linspace(0.0, math.pi, 25)] \
            + [[-110.0, 0.0], [-512.0, 0.0]]
        atlas = {"coast": {"polygon": lobe, "shelves": self.atlas["coast"]["shelves"]}}
        H = GEO.break_shelf_edges(self.grid, self.H0.copy(), atlas, NoiseBank(8471, self.grid), keep_discs=[PAD])
        self.assertTrue(np.array_equal(H, self.H), "the coast polygon changed how the shelf was broken")


class AuthoredPadSkirtTest(unittest.TestCase):
    def test_an_authored_pads_skirt_does_not_fill_the_sea_below_the_face(self):
        grid, H0, _shelf, _atlas = world()
        place = {"id": "core:poi/landing", "kind": "hidden_valley", "position": [0.0, 50.0], "pad_radius_m": 26.0}
        H, _mask, levels = RD.apply_pads(grid, H0.copy(), [place], fixed_levels={place["id"]: TOP})
        self.assertEqual(levels[place["id"]], TOP)
        # 22 to 34 m out from the pad's middle is on its flat and its skirt, and over the sea past the face
        j = int(round((0.0 - grid.x0) / grid.spacing))
        for z in (72.0, 76.0, 84.0):
            i = int(round((z - grid.z0) / grid.spacing))
            self.assertEqual(float(H[i, j]), float(H0[i, j]), "the skirt filled the sea at z = %.0f" % z)
        # while an ordinary pad's skirt does blend out over it
        H2, _m, _l = RD.apply_pads(grid, H0.copy(), [dict(place, id="core:poi/other")])
        i = int(round((76.0 - grid.z0) / grid.spacing))
        self.assertGreater(float(H2[i, j]), float(H0[i, j]))


if __name__ == "__main__":
    unittest.main()
