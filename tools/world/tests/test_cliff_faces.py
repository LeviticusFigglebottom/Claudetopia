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


class Roll(unittest.TestCase):
    """A piece lies in its plane however that plane tilts across it and however it is turned in it
    (the row's lean and toward tilt its up anywhere; its yaw turns it about that up)."""

    def test_the_rotation_round_trips(self):
        rng = np.random.default_rng(3)
        for _ in range(50):
            row = [0.0, 0.0, 0.0, float(rng.uniform(-180, 180)), 1.0, "#ffffff",
                   float(rng.uniform(0.0, 60.0)), float(rng.uniform(-180, 180))]
            R = CS.row_basis(row)
            yaw, lean, toward = CS.row_angles(R)
            self.assertLess(np.abs(CS.row_basis([0, 0, 0, yaw, 1.0, "", lean, toward]) - R).max(), 1e-6)

    def test_a_turned_piece_rolls_with_its_slope(self):
        with tempfile.TemporaryDirectory() as tmp:
            _fake_kit(tmp)
            asset = "res://assets/models/rocks/skerrow_cliff_face_a/skerrow_cliff_face_a.glb"
            prof = CS.profile(asset, tmp)
            g = Grid(512.0, 256)
            X, Z = g.mesh(np.float64)
            # a 60-degree face falling to the south-east
            b, c = -1.2, -1.25
            H = (400.0 + b * X + c * Z).astype(np.float32) * np.ones((g.n, g.n), np.float32)
            hs = CS.smoothed_grad(H, g)
            N = np.array([-b, 1.0, -c]) / math.sqrt(1.0 + b * b + c * c)
            for turn in (-9.0, 0.0, 9.0):
                # laid in the plane turned `turn`, then stood 3 m out of it and rolled 8 degrees
                # out of it, as a piece yawed about the vertical was
                row = CS._laid(asset, prof, 0.0, 0.0, 0.8, turn, H, g, hs)
                row[0], row[1], row[2] = row[0] + 3.0 * N[0], row[1] + 3.0 * N[1], row[2] + 3.0 * N[2]
                row[6] = row[6] + 8.0
                new, why = CS.seat(row, prof, H, g, hs)
                self.assertEqual(why, "")
                front = CS.row_basis(new)[:, 2]
                self.assertLess(math.degrees(math.acos(min(1.0, float(front @ N)))), 1.0, new)
                self.assertAlmostEqual(CS.twist(new, b, c), turn, delta=1.5)
                # its front's lowest fifth at the ground across its whole width, not one edge out
                p = CS.protrusion(new, prof, H, g, hs)
                self.assertLess(float(np.ptp(p)), prof.spread * 0.8 * 1.5 + 0.5)


class Fill(unittest.TestCase):
    """The bare steep ground between the pieces is filled with smaller pieces, seated the same way,
    staggered and of mixed sizes (the Skerrow's "parallel columns of rock with bare terrain")."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        _fake_kit(cls.tmp.name)
        cls.g = g = Grid(512.0, 256)
        X, Z = g.mesh(np.float64)
        Z = np.broadcast_to(Z, (g.n, g.n))
        X = np.broadcast_to(X, (g.n, g.n))
        # a 60-degree face 70 m high, top at z = 0, foot at z = 40, with a little relief along it
        cls.H = (np.clip(70.0 - math.tan(math.radians(60.0)) * Z, 0.0, 70.0) + 1.5 * np.sin(X / 17.0)).astype(np.float32)
        cls.hs = CS.smoothed_grad(cls.H, g)
        # columns of pieces every 40 m along it, as the seated build left the Skerrow wall
        cls.asset = "res://assets/models/rocks/skerrow_cliff_face_a/skerrow_cliff_face_a.glb"
        prof = CS.profile(cls.asset, cls.tmp.name)
        cls.buckets = {}
        for x in np.arange(-200.0, 201.0, 40.0):
            for z in (8.0, 26.0):
                row = CS._laid(cls.asset, prof, float(x), z, 0.7, 0.0, cls.H, g, cls.hs)
                new, _ = CS.seat(row, prof, cls.H, g, cls.hs)
                if new is not None:
                    cls.buckets.setdefault(g.written_cell(new[0], new[2]), {}).setdefault(cls.asset, []).append(new)
        cls.steep = CS.face_mask(cls.H, g, cls.hs)
        inner = np.zeros_like(cls.steep)
        inner[:, 40:216] = True
        cls.steep &= inner
        cls.before = CS.gap_stats(CS.cover_map(cls.buckets, g, cls.tmp.name), cls.steep, g)
        was = {id(r) for by in cls.buckets.values() for v in by.values() for r in v}
        cls.got = CS.fill_gaps(cls.buckets, cls.H, g, cls.tmp.name, 7, steep=cls.steep)
        cls.after = CS.gap_stats(cls.got["cover"], cls.steep, g)
        cls.added = [r for by in cls.buckets.values() for v in by.values() for r in v if id(r) not in was]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_the_face_is_covered(self):
        self.assertLess(self.before["within_3m"], 0.8)
        self.assertGreater(self.after["within_3m"], 0.95, self.after)
        self.assertLessEqual(self.after["bare_to_rock_m_p99"], 6.0, self.after)

    def test_the_new_pieces_are_seated(self):
        self.assertGreater(len(self.added), 20)
        prof = CS.profile(self.asset, self.tmp.name)
        for r in self.added:
            p = CS.protrusion(r, prof, self.H, self.g, self.hs)
            self.assertLess(abs(CS.front_level(p) - CS.SEAT_SHOW_M), 0.35, r)
            self.assertLessEqual(CS.back_show(r, prof, self.H, self.g), CS.SEAT_BACK_CLEAR_M + 0.1, r)
            self.assertTrue(CS.seated(r, prof, self.H, self.g, self.hs), r)

    def test_mixed_sizes_and_turns_not_rows(self):
        sc = np.array([float(r[4]) for r in self.added])
        self.assertGreater(float(sc.max() / sc.min()), 1.6)
        tw = np.array([CS.twist(r, 0.0, -math.tan(math.radians(60.0))) for r in self.added])
        self.assertGreater(float(np.std(tw)), 6.0)
        # not in columns or rows: the gaps between neighbours along and up the face are irregular
        xs = np.sort(np.array([float(r[0]) for r in self.added]))
        dx = np.diff(xs)
        self.assertGreater(float(np.std(dx) / max(np.mean(dx), 1e-6)), 0.5)
        zs = np.array([float(r[2]) for r in self.added])
        self.assertGreater(len(np.unique(np.round(zs / 2.0))), 8)


class ProudLedge(unittest.TestCase):
    def test_a_proud_bed_goes_back_level(self):
        with tempfile.TemporaryDirectory() as tmp:
            name = "skerrow_cliff_ledge_a"
            d = os.path.join(tmp, "game", "assets", "models", "rocks", name)
            os.makedirs(d)
            with open(os.path.join(d, name + ".meta.json"), "w") as f:
                json.dump({"bounds": {"min": [-2.5, 0.0, -1.7], "max": [2.5, 2.2, 2.4], "height": 2.2}}, f)
            asset = "res://assets/models/rocks/%s/%s.glb" % (name, name)
            prof = CS.profile(asset, tmp)
            g = Grid(256.0, 128)
            _X, Z = g.mesh(np.float64)
            H = np.broadcast_to(np.clip(40.0 - 1.5 * Z, 0.0, 40.0), (g.n, g.n)).astype(np.float32)
            hs = CS.smoothed_grad(H, g)
            # a bed facing down the slope (+z), its front 2.5 m out over the fall
            row = [0.0, 20.0, 12.0, 0.0, 1.0, "#ffffff", 2.0, -90.0]
            before = CS.front_level(CS.protrusion(row, prof, H, g, hs))
            self.assertGreater(before, CS.LEDGE_PROUD_M)
            new = CS.seat_ledge(row, prof, H, g, hs)
            self.assertIsNotNone(new)
            self.assertEqual(new[1], row[1])                       # level: its course is not broken
            self.assertLess(new[2], row[2])                        # back into the hill
            self.assertLessEqual(CS.front_level(CS.protrusion(new, prof, H, g, hs)), CS.LEDGE_PROUD_M)
            self.assertIsNone(CS.seat_ledge(new, prof, H, g, hs))  # and it stays


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
            # one broken face, not columns (the Skerrow's crags, cliff_faces_fill.jpg): the broad
            # variants mixed in with the tall `b`, and a course not laid straight over the one below
            P = [(a.split("_cliff_face_")[1][0], r) for by in rows.values() for a, rs in by.items()
                 if "_cliff_face_" in a for r in rs]
            share = {v: sum(1 for w, _r in P if w == v) / len(P) for v in FACES}
            self.assertLess(max(share.values()), 0.6, share)
            self.assertGreaterEqual(sum(1 for s in share.values() if s >= 0.15), 2, share)
            xs = np.array([r[0] for _v, r in P])
            zs = np.array([r[2] for _v, r in P])
            aligned = []
            for k in range(len(P)):
                m = (np.abs(zs - zs[k]) > 4.0) & (np.abs(zs - zs[k]) < 30.0)
                if m.any():
                    aligned.append(float(np.min(np.abs(xs[m] - xs[k]))) < 1.5)
            # (stacked on the fall line, as before, 46% had a piece within 1.5 m straight above or below)
            self.assertLess(float(np.mean(aligned)), 0.3)


if __name__ == "__main__":
    unittest.main()
