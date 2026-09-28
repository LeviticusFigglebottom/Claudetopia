#!/usr/bin/env python3
"""Steep faces are covered in large cliff pieces, not left as the heightmap's sheet nor carpeted in
small ledges (worldgen.crags.cliff_faces; the w4096d ground review's "cliffside rocks that look flat
and out of place"): no steep face taller than CLIFF_MIN_H is left bare, no piece's back stands more
than CLIFF_BACK_CLEAR_M clear of the hill, and the pieces are few and big.

    python3 -m pytest tools/world/tests/test_cliff_faces.py
"""
from __future__ import annotations

import json
import math
import os
import sys
import tempfile
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import cliff_seat as CS  # noqa: E402
from worldgen import crags as CR  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402

FACES = {"a": ([-10.0, 0.0, -4.0], [10.0, 16.0, 4.5]), "b": ([-7.0, 0.0, -4.0], [7.0, 24.0, 4.5]),
         "c": ([-12.0, 0.0, -3.5], [12.0, 10.0, 4.0])}


def _fake_kit(root: str) -> dict:
    index = {"rocks": {}}
    for kind, variants in (("cliff_face", FACES), ("scree", {"a": ([-1, 0, -1], [1, 0.8, 1])}),
                           ("boulder", {"a": ([-1, 0, -1], [1, 1.6, 1])})):
        for v, (lo, hi) in variants.items():
            name = "skerrow_%s_%s" % (kind, v)
            d = os.path.join(root, "game", "assets", "models", "rocks", name)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, name + ".meta.json"), "w") as f:
                json.dump({"bounds": {"min": lo, "max": hi, "height": hi[1] - lo[1]}}, f)
            index["rocks"][name] = "res://assets/models/rocks/%s/%s.glb" % (name, name)
    return index


class CliffFaces(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        index = _fake_kit(cls.tmp.name)
        cls.grid = g = Grid(1024.0, 512)                     # 2 m texels, as a full build
        X, Z = g.mesh(np.float64)
        X, Z = np.broadcast_to(X, (g.n, g.n)), np.broadcast_to(Z, (g.n, g.n))
        # a plateau at 60 m falling to a shore at 2 m over a wall 1-in-0.5 at z = 0..30 (a sea
        # cliff), with a gorge 25 m deep cut into the plateau along x = 200 (walls 1 in 0.6)
        H = np.where(Z < 0.0, 60.0, np.where(Z < 29.0, 60.0 - 2.0 * Z, 2.0))
        gorge = np.clip(25.0 - np.maximum(np.abs(X - 200.0) - 8.0, 0.0) / 0.6, 0.0, 25.0) * (Z < -40.0)
        cls.H = (H - gorge + 0.3 * np.sin(X / 13.0)).astype(np.float32)
        n = g.n
        zeros = np.zeros((n, n), np.uint8)
        cls.rows, cls.counts, cls.feet = CR.cliff_faces(
            g, cls.H, zeros, zeros, np.full((n, n), 1e6, np.float32), np.full((n, n), 4.0, np.float32),
            np.zeros((n, n), bool), [SimpleNamespace(index=0, shape="mountains", art_short="skerrow")], [], {},
            index, 5, repo_root=cls.tmp.name)
        cls.pieces = [(a, r) for by in cls.rows.values() for a, rows in by.items() if "_cliff_face_" in a for r in rows]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_no_steep_face_is_left_bare(self):
        g = self.grid
        gz, gx = np.gradient(self.H.astype(np.float64), g.spacing)
        steep = np.hypot(gx, gz) >= 1.2
        ii, jj = np.nonzero(steep)
        # (away from the window's edge, where a face runs out of the grid)
        x, z = g.x0 + jj * g.spacing, g.z0 + ii * g.spacing
        inner = (np.abs(x) < 440.0) & (np.abs(z) < 440.0)
        x, z = x[inner], z[inner]
        self.assertGreater(x.size, 200)
        feet = np.array([(f[0], f[1], f[2]) for f in self.feet])
        d = np.hypot(x[:, None] - feet[None, :, 0], z[:, None] - feet[None, :, 1]) - feet[None, :, 2]
        covered = (d.min(axis=1) < 6.0).mean()
        self.assertGreater(float(covered), 0.9, "%.0f%% of the steep face bare" % (100 * (1 - covered)))

    def test_no_piece_stands_clear_of_the_face(self):
        self.assertGreater(len(self.pieces), 10)
        for a, r in self.pieces:
            lo, hi = (np.array(v, dtype=np.float64) for v in FACES[a.split("_cliff_face_")[1][0]])
            pts = CR.back_points(r, lo, hi)
            gy = sample_bilinear(self.H, self.grid, pts[:, 0], pts[:, 2])
            self.assertLessEqual(float(np.max(pts[:, 1] - gy)), CR.CLIFF_BACK_CLEAR_M + 1e-6, r)

    def test_few_big_pieces_not_a_carpet(self):
        # the sea cliff is 880 m of face, 58 m high, in the window: a column of pieces every 10 m
        # or more along it, each 14 to 24 m across and scaled up to its height, two or three up the
        # face (a ledge module every 5 m, bed on bed, was the carpet: some 800 here)
        sea = [(a, r) for a, r in self.pieces if -20.0 < r[2] < 45.0]
        self.assertLess(len(sea), 3 * 880.0 / 10.0)
        widths = [(FACES[a.split("_cliff_face_")[1][0]][1][0] - FACES[a.split("_cliff_face_")[1][0]][0][0]) * r[4]
                  for a, r in sea]
        self.assertGreater(float(np.median(widths)), 12.0)
        self.assertTrue(all(r[4] >= CR.CLIFF_SCALE[0] - 1e-6 for a, r in self.pieces))
        self.assertGreater(self.counts["talus"], 0)

    def test_pieces_sit_in_the_face_not_out_of_it(self):
        # triage 42: the lowest fifth of a piece's front stands SEAT_SHOW_M out of the ground, not
        # its whole depth, and no tenth of it stands out further than proud_max
        hs = CS.smoothed_grad(self.H, self.grid)
        for a, r in self.pieces:
            prof = CS.profile(a, self.tmp.name)
            p = CS.protrusion(r, prof, self.H, self.grid, hs)
            self.assertLess(abs(CS.front_level(p) - CS.SEAT_SHOW_M), 0.35, r)
            self.assertLessEqual(float(np.percentile(p, 90)), CS.proud_max(prof, float(r[4])) + 1e-6, r)

    def test_pieces_lie_in_the_slope(self):
        # leaned back to the face's angle: a 1-in-0.5 wall is 63 degrees, so 27 back (those
        # whose foot is on the wall itself, not at its brink or its foot)
        n = 0
        for a, r in self.pieces:
            if 4.0 < r[2] < 24.0 and abs(r[0]) < 400.0:
                self.assertAlmostEqual(float(r[6]), 90.0 - math.degrees(math.atan(2.0)), delta=8.0, msg=str(r))
                n += 1
        self.assertGreater(n, 5)

    def test_no_piece_stands_alone(self):
        pieces = [(None, a, r, 0.5 * CS.profile(a, self.tmp.name).w * float(r[4])) for a, r in self.pieces]
        self.assertTrue(all(CS.drop_lone(pieces)))

    def test_the_small_ledges_under_a_piece_go(self):
        f = self.feet[0]
        wall = "res://assets/models/rocks/skerrow_cliff_ledge_a/skerrow_cliff_ledge_a.glb"
        buckets = {(1, 1): {wall: [[f[0], 30.0, f[1], 0.0, 1.0, "#ffffff"], [f[0] + 300.0, 1.0, f[1] + 300.0, 0.0, 1.0, "#ffffff"]]}}
        self.assertEqual(CR.clear_under_faces(buckets, self.feet), 1)
        self.assertEqual(len(buckets[(1, 1)][wall]), 1)


class Seat(unittest.TestCase):
    """worldgen.cliff_seat on its own, as tools/world/seat_cliffs.py runs it over installed cells."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        _fake_kit(cls.tmp.name)
        cls.asset = "res://assets/models/rocks/skerrow_cliff_face_a/skerrow_cliff_face_a.glb"
        cls.prof = CS.profile(cls.asset, cls.tmp.name)
        cls.g = g = Grid(512.0, 256)
        X, Z = g.mesh(np.float64)
        Z = np.broadcast_to(Z, (g.n, g.n))
        X = np.broadcast_to(X, (g.n, g.n))
        # a 55-degree face 60 m high from z = 0 (top, north) to z = 42 (foot), and west of x = -150
        # a 25-degree bank of the same height
        k = np.where(X < -150.0, math.tan(math.radians(25.0)), math.tan(math.radians(55.0)))
        cls.H = np.clip(60.0 - k * Z, 0.0, 60.0).astype(np.float32)
        cls.hs = CS.smoothed_grad(cls.H, g)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _stood_out(self, x):
        # as crags.cliff_faces used to leave one: its foot at the face's foot, leaned back 30
        # degrees, and set "as far forward as its back is in the hill"
        for z in np.arange(60.0, 0.0, -0.5):
            row = [x, -1.0, float(z), 0.0, 1.0, "#ffffff", 30.0, -90.0]
            if CS.back_show(row, self.prof, self.H, self.g) <= CS.SEAT_BACK_CLEAR_M:
                return row
        raise AssertionError("no place for it")

    def test_a_piece_stood_out_is_seated_flush(self):
        row = self._stood_out(40.0)
        before = float(np.median(CS.protrusion(row, self.prof, self.H, self.g, self.hs)))
        new, why = CS.seat(row, self.prof, self.H, self.g, self.hs)
        self.assertEqual(why, "")
        after = CS.protrusion(new, self.prof, self.H, self.g, self.hs)
        self.assertGreater(before, 3.0)
        self.assertAlmostEqual(CS.front_level(after), CS.SEAT_SHOW_M, delta=0.1)
        self.assertAlmostEqual(float(new[6]), 35.0, delta=4.0)            # lies in the 55-degree face
        self.assertLessEqual(CS.back_show(new, self.prof, self.H, self.g), CS.SEAT_BACK_CLEAR_M)
        # and seating it again moves nothing
        again, _ = CS.seat(new, self.prof, self.H, self.g, self.hs)
        self.assertLess(max(abs(float(a) - float(b)) for a, b in zip(again[:5], new[:5]) if not isinstance(a, str)), 0.1)

    def test_no_rock_on_a_grass_bank(self):
        z = 60.0 / math.tan(math.radians(25.0)) * 0.5
        row = [-200.0, 30.0, z, 0.0, 0.8, "#ffffff", 30.0, -90.0]
        new, why = CS.seat(row, self.prof, self.H, self.g, self.hs)
        self.assertIsNone(new)
        self.assertEqual(why, "gentle")

    def test_held_to_its_face(self):
        # a piece scaled to 1.5 on a face 73 m long up the slope is not cut, but its width is held
        # to the steep ground across (all of it here) and its length to the face's
        row = self._stood_out(60.0)
        row[4] = 1.5
        new, _why = CS.seat(row, self.prof, self.H, self.g, self.hs)
        self.assertIsNotNone(new)
        self.assertLessEqual(self.prof.h * float(new[4]), CS.SEAT_RELIEF_FIT * 60.0 / math.sin(math.radians(55.0)) + 1e-6)

    def test_a_lone_piece_goes(self):
        rows = [(None, self.asset, [0.0, 0.0, 0.0], 10.0), (None, self.asset, [22.0, 0.0, 0.0], 10.0),
                (None, self.asset, [200.0, 0.0, 0.0], 10.0)]
        self.assertEqual(CS.drop_lone(rows), [True, True, False])


class TallWall(unittest.TestCase):
    """A sea wall 300 m high (the Skerrow wall is 480) is dressed to its top, not six pieces up it."""

    def test_pieces_reach_the_top(self):
        with tempfile.TemporaryDirectory() as tmp:
            index = _fake_kit(tmp)
            g = Grid(512.0, 256)
            _X, Z = g.mesh(np.float64)
            Z = np.broadcast_to(Z, (g.n, g.n))
            H = np.where(Z < 0.0, 300.0, np.where(Z < 60.0, 300.0 - 5.0 * Z, 0.0)).astype(np.float32)
            n = g.n
            zeros = np.zeros((n, n), np.uint8)
            rows, _counts, _feet = CR.cliff_faces(
                g, H, zeros, zeros, np.full((n, n), 1e6, np.float32), np.full((n, n), 4.0, np.float32),
                np.zeros((n, n), bool), [SimpleNamespace(index=0, shape="mountains", art_short="skerrow")], [], {},
                index, 5, repo_root=tmp)
            tops = [r[1] + r[4] * 24.0 for by in rows.values() for a, rs in by.items() if "_cliff_face_" in a for r in rs]
            self.assertGreater(max(tops), 250.0)


if __name__ == "__main__":
    unittest.main()
