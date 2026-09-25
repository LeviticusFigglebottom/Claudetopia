#!/usr/bin/env python3
"""Scattered rock is seated in the ground and comes in groups (worldgen.cells SEAT_*, CLUMP).

Playtest 5 had "rocks jut from slopes": a boulder stood upright on a slope with the middle of its
foot on the ground has its downhill side over air. Seated, it leans back with the slope and its
downhill edge is in the ground; and a boulder has smaller stones round it, most below it.

    python3 -m pytest tools/world/tests/test_rock_seating.py
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

from worldgen import cells as CELLS  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

BOULDER = "res://assets/models/rocks/skerrow_boulder_a/skerrow_boulder_a.glb"
SLAB = "res://assets/models/rocks/skerrow_cliff_slab_a/skerrow_cliff_slab_a.glb"
LOG = "res://assets/models/rocks/briarwold_fallen_log_a/briarwold_fallen_log_a.glb"


def _base_plane(row, half: float, toward_deg: float, along: float) -> float:
    """The height of a seated rock's foot, `along` metres from its pivot toward `toward_deg`."""
    lean = math.radians(float(row[6]))
    t = math.radians(float(row[7]))
    # the foot's plane is tipped by the lean about the axis across it: along the lean's own bearing
    # it falls by tan(lean) a metre
    return float(row[1]) - along * math.tan(lean) * math.cos(math.radians(toward_deg) - t)


class Seating(unittest.TestCase):
    def test_a_rock_on_a_slope_has_its_downhill_edge_in_the_ground(self):
        g = Grid(512.0, 128)
        X, _ = g.mesh()
        H = np.broadcast_to(0.45 * X, (g.n, g.n)).astype(np.float32)     # rising to +x at 0.45
        rng = np.random.default_rng(3)
        x = rng.uniform(-150.0, 150.0, 200)
        z = rng.uniform(-150.0, 150.0, 200)
        y = sample_bilinear(H, g, x, z).astype(np.float32)
        half = np.full(200, 1.4)
        tall = np.full(200, 1.6)
        ys, lean, toward = CELLS.seat_on_ground(H, g, x, z, y, half, tall, CELLS.SEAT_TILT, CELLS.SEAT_EMBED,
                                                np.random.default_rng(4))
        slope_deg = math.degrees(math.atan(0.45))
        self.assertTrue(np.all(lean >= CELLS.SEAT_TILT[0] * slope_deg - 0.5))
        self.assertTrue(np.all(lean <= CELLS.SEAT_TILT[1] * slope_deg + 0.5))
        # top carried downhill: toward -x
        self.assertTrue(np.all(np.abs(np.abs(toward) - 180.0) < 1.0), toward[:5])
        for k in range(200):
            row = [x[k], ys[k], z[k], 0.0, 1.0, "#ffffff", lean[k], toward[k]]
            down_edge = _base_plane(row, half[k], 180.0, half[k])
            ground = 0.45 * (x[k] - half[k])
            self.assertLess(down_edge, ground - 0.1 * tall[k] + 1e-3, "rock %d floats on its downhill side" % k)
            up_edge = _base_plane(row, half[k], 0.0, half[k])
            # and it is not swallowed: no more than SEAT_MAX_SINK of it under its pivot's ground
            self.assertGreater(float(ys[k]), float(y[k]) - CELLS.SEAT_MAX_SINK * tall[k] - 1e-3)
            self.assertLess(up_edge, 0.45 * (x[k] + half[k]), "the uphill edge is buried")

    def test_on_level_ground_a_rock_stands_upright_and_is_sunk_a_little(self):
        g = Grid(512.0, 128)
        H = np.full((g.n, g.n), 20.0, dtype=np.float32)
        x = np.array([0.0, 30.0]); z = np.array([0.0, -40.0])
        ys, lean, _ = CELLS.seat_on_ground(H, g, x, z, np.full(2, 20.0, dtype=np.float32), np.full(2, 1.0),
                                           np.full(2, 2.0), CELLS.SEAT_TILT, CELLS.SEAT_EMBED,
                                           np.random.default_rng(1))
        self.assertTrue(np.all(lean == 0.0))
        self.assertTrue(np.all((ys < 20.0 - 2.0 * CELLS.SEAT_EMBED[0] + 1e-3) & (ys > 20.0 - 2.0 * CELLS.SEAT_EMBED[1] - 1e-3)))

    def test_which_rules_are_seated_and_clumped(self):
        self.assertIsNotNone(CELLS._seat_cfg({}, "rocks/mossy_boulder"))
        self.assertIsNone(CELLS._seat_cfg({"seat": False}, "rocks/mossy_boulder"))
        self.assertIsNone(CELLS._seat_cfg({}, "flora/fern"))
        self.assertEqual(CELLS._seat_cfg({}, "rocks/fallen_log")["tilt"], CELLS.SEAT_LYING["tilt"])
        self.assertIsNotNone(CELLS._clump_cfg({}, "rocks/granite_slab"))
        for alone in ("rocks/scree_rubble", "rocks/giant_bone", "rocks/fallen_log", "rocks/driftwood"):
            self.assertIsNone(CELLS._clump_cfg({}, alone), alone)
        self.assertIsNone(CELLS._clump_cfg({"clump": False}, "rocks/boulder"))


class Scattered(unittest.TestCase):
    """A rock rule scattered over a hillside: the boulders in groups, the stones below them, every
    one seated."""

    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(1024.0, 256, 256.0)
        X, Z = g.mesh()
        H = np.broadcast_to(0.3 * X + 0.1 * Z, (g.n, g.n)).astype(np.float32) + 200.0
        n = g.n
        cls.H = H
        zeros = np.zeros((n, n), dtype=np.uint8)
        world = CELLS.ScatterWorld(g, H, zeros, np.full((n, n), 0.5, dtype=np.float32), zeros,
                                   np.full((n, n), 1e6, dtype=np.float32), np.zeros((n, n), dtype=np.float32),
                                   np.zeros((n, n), dtype=bool), np.full((n, n), math.hypot(0.3, 0.1), dtype=np.float32),
                                   NoiseBank(5, g), [])
        region = SimpleNamespace(index=0, shape="mountains", art_short="skerrow", flora=[], palette=["#a0a0a0"])
        rules = {"defaults": {}, "flora": {}, "rocks": {"mountains": [
            {"asset": "rocks/mossy_boulder", "density": 3.0, "scale": [0.8, 1.6], "cluster": 0.0}]}}
        cls.out = CELLS.scatter(world, rules, [region], 7, repo_root=REPO)
        rows = np.array([r[:5] + r[6:8] for by in cls.out.values() for rows in by.values() for r in rows],
                        dtype=np.float64)
        # (off the grid's edge, where the slope is read against the clamped border)
        cls.rows = rows[(np.abs(rows[:, 0]) < 480.0) & (np.abs(rows[:, 2]) < 480.0)]

    def test_every_rock_is_seated(self):
        self.assertGreater(len(self.rows), 300)
        ground = sample_bilinear(self.H, self.grid, self.rows[:, 0], self.rows[:, 2])
        self.assertTrue(np.all(self.rows[:, 1] < ground), "a rock with its pivot over the ground")
        self.assertTrue(np.all(self.rows[:, 5] > 5.0), "a rock upright on a 17 degree slope")

    def test_boulders_come_in_groups_with_stones_below_them(self):
        # (the boulders are 0.8 to 1.6, their stones CLUMP["scale"] of that)
        big = self.rows[self.rows[:, 4] >= 0.8]
        small = self.rows[self.rows[:, 4] < 0.8 * CELLS.CLUMP["scale"][1]]
        # about three hundred boulders on a hundred hectares at 3 a hectare, and about as many stones
        self.assertGreater(len(self.rows), 1.7 * 3.0 * 96.0)
        self.assertGreater(len(small), 0.5 * len(big))
        # each stone within a few metres of a bigger rock, and most of them downhill of it
        below = 0
        for s in small:
            d = np.hypot(big[:, 0] - s[0], big[:, 2] - s[2])
            k = int(np.argmin(d))
            self.assertLess(d[k], 15.0)
            if s[1] < big[k, 1]:
                below += 1
        self.assertGreater(below / len(small), 0.6)

    def test_the_same_seed_scatters_the_same_rock(self):
        g = self.grid
        n = g.n
        zeros = np.zeros((n, n), dtype=np.uint8)
        world = CELLS.ScatterWorld(g, self.H, zeros, np.full((n, n), 0.5, dtype=np.float32), zeros,
                                   np.full((n, n), 1e6, dtype=np.float32), np.zeros((n, n), dtype=np.float32),
                                   np.zeros((n, n), dtype=bool), np.full((n, n), math.hypot(0.3, 0.1), dtype=np.float32),
                                   NoiseBank(5, g), [])
        region = SimpleNamespace(index=0, shape="mountains", art_short="skerrow", flora=[], palette=["#a0a0a0"])
        rules = {"defaults": {}, "flora": {}, "rocks": {"mountains": [
            {"asset": "rocks/mossy_boulder", "density": 3.0, "scale": [0.8, 1.6], "cluster": 0.0}]}}
        self.assertEqual(CELLS.scatter(world, rules, [region], 7, repo_root=REPO), self.out)


if __name__ == "__main__":
    unittest.main()
