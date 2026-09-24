#!/usr/bin/env python3
"""Crags (worldgen.crags): rock set into the steep faces, oriented to them and embedded, and
outcrops on the crests; none on a road, a pad or water, or standing into a sightline.

    python3 -m pytest tools/world/tests/test_crags.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import crags as CR  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

K = {"EYE_M": 1.65, "LANDMARK_DEFAULT_M": 6.0, "LANDMARK_M": {}, "CLEARANCE_M": 2.0, "MAX_SIGHT_M": 4200.0,
     "FOREGROUND_M": 140.0}
SLAB = "res://assets/models/rocks/skerrow_cliff_slab_a/skerrow_cliff_slab_a.glb"
BOULDER = "res://assets/models/rocks/skerrow_boulder_a/skerrow_boulder_a.glb"


class Crags(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # a valley running along z: flat floor, walls climbing 1 in 1 either side from |x| = 120 to
        # 220 m, and a level top with a crest beyond
        cls.grid = g = Grid(1024.0, 256)
        X, Z = g.mesh()
        X = np.broadcast_to(X, (g.n, g.n)).astype(np.float64)
        ax = np.abs(X)
        H = np.where(ax < 120.0, 100.0, np.where(ax < 220.0, 100.0 + (ax - 120.0), 200.0))
        H = H + 12.0 * np.exp(-((ax - 330.0) / 25.0) ** 2)          # a crest
        cls.H = H.astype(np.float32)
        n = g.n
        cls.owner = np.zeros((n, n), dtype=np.uint8)
        cls.water = np.zeros((n, n), dtype=np.uint8)
        cls.water_d = np.full((n, n), 1e6, dtype=np.float32)
        # a road across the east wall at z = 0
        Zb = np.broadcast_to(Z, (n, n))
        cls.road_d = np.where(X > 0, np.abs(Zb), 1e6).astype(np.float32)
        cls.road_w = np.full((n, n), 4.0, dtype=np.float32)
        cls.pad = np.zeros((n, n), dtype=bool)
        cls.regions = [SimpleNamespace(index=0, shape="mountains", art_short="skerrow")]
        cls.index = {"rocks": {"skerrow_cliff_slab_a": SLAB, "skerrow_boulder_a": BOULDER}}
        # a sightline across the west wall at z = -250, from the valley floor to the brow above it:
        # 25 m over the middle of the wall
        cls.claims = [((0.0, -250.0), (-240.0, -250.0), "ruins", 20.0, 20.0)]
        rows, cls.counts = CR.place(g, cls.H, cls.owner, cls.water, cls.water_d, cls.road_d, cls.road_w, cls.pad,
                                    cls.regions, cls.claims, K, cls.index, NoiseBank(11, g), 5, repo_root=REPO)
        cls.faces = np.array([r[:5] + [0.0] + r[6:] for by in rows.values() for r in by.get(SLAB, [])], dtype=np.float64)
        cls.crests = np.array([r[:5] + [0.0] + r[6:] for by in rows.values() for r in by.get(BOULDER, [])], dtype=np.float64)

    def ground(self, x, z):
        return sample_bilinear(self.H, self.grid, np.asarray(x), np.asarray(z)).astype(np.float64)

    def test_the_faces_are_dressed_and_the_flats_are_not(self):
        self.assertGreater(len(self.faces), 100)
        ax = np.abs(self.faces[:, 0])
        # on the walls (a piece is set back into the hill along its normal by a metre or two)
        self.assertTrue(np.all((ax > 110.0) & (ax < 230.0)), "a face piece off the walls")

    def test_a_face_piece_looks_out_downhill_and_leans_into_the_hill(self):
        east = self.faces[self.faces[:, 0] > 0]
        west = self.faces[self.faces[:, 0] < 0]
        # the east wall rises toward +x: it looks out toward -x (a yaw of -90), and leans toward +x (0)
        yaw_e = (east[:, 3] + 360.0) % 360.0
        self.assertTrue(np.all(np.abs(yaw_e - 270.0) < 1.0))
        self.assertTrue(np.all(np.abs(((east[:, 7] + 360.0) % 360.0)) < 1.0))
        yaw_w = (west[:, 3] + 360.0) % 360.0
        self.assertTrue(np.all(np.abs(yaw_w - 90.0) < 1.0))
        self.assertTrue(np.all(np.abs(((west[:, 7] + 360.0) % 360.0) - 180.0) < 1.0))
        # a 45 degree face: leaned back 0.7 of the 45 degrees from upright
        self.assertAlmostEqual(float(np.median(self.faces[:, 6])), CR.FACE_LEAN_SHARE * 45.0, delta=0.5)
        # and none leans further than a face just over 35 degrees asks (its foot and brow)
        self.assertTrue(np.all(self.faces[:, 6] <= CR.FACE_LEAN_SHARE * (90.0 - 35.0) + 0.1))

    def test_every_piece_is_set_into_the_ground(self):
        g = self.ground(self.faces[:, 0], self.faces[:, 2])
        self.assertTrue(np.all(self.faces[:, 1] < g), "a face piece stands on the ground, not in it")
        gc = self.ground(self.crests[:, 0], self.crests[:, 2])
        self.assertTrue(np.all(self.crests[:, 1] < gc))

    def test_it_is_sized_to_the_face(self):
        # the walls are 141 m along the slope: every piece is as big as the pieces go
        self.assertGreater(float(np.median(self.faces[:, 4])), 0.9 * CR.FACE_SCALE[1])

    def test_outcrops_stand_on_the_convex_edges_and_the_crest(self):
        self.assertGreater(len(self.crests), 5)
        ax = np.abs(self.crests[:, 0])
        # the brow of each wall (from 180 m, where the ground stands over its surroundings) and the crest
        on = ((ax > 170.0) & (ax < 250.0)) | (np.abs(ax - 330.0) < 40.0)
        self.assertTrue(np.all(on), "an outcrop off the brows and the crest: %s" % ax[~on])

    def test_none_on_the_road_or_in_the_sightline(self):
        on_road = (self.faces[:, 0] > 0) & (np.abs(self.faces[:, 2]) < 2.0 + CR.ROAD_CLEAR_M)
        self.assertFalse(on_road.any())
        # under the line across the west wall, whatever stands keeps its top under the ray
        (ax, az), (bx, bz), _k, _a, _b = self.claims[0]
        near = (self.faces[:, 0] < -140.0) & (np.abs(self.faces[:, 2] - az) < CR.SIGHTLINE_CORRIDOR_M)
        eye = 100.0 + K["EYE_M"]
        top = float(self.ground(np.array([bx]), np.array([bz]))[0]) + K["LANDMARK_DEFAULT_M"]
        for r in self.faces[near]:
            t = (r[0] - ax) / (bx - ax)
            g = float(self.ground(np.array([r[0]]), np.array([r[2]]))[0])
            self.assertLess(g + 6.4 * r[4], eye + (top - eye) * t - K["CLEARANCE_M"], "a crag stands in the line")
        # and the corridor is not simply bare: the wall below the ray is dressed
        corridor = (self.faces[:, 0] < -110.0) & (np.abs(self.faces[:, 2] - az) < CR.SIGHTLINE_CORRIDOR_M)
        self.assertGreater(int(corridor.sum()), 0)


if __name__ == "__main__":
    unittest.main()
