#!/usr/bin/env python3
"""No tree stands into an authored sightline (worldgen.trees.clear_sightlines), as no rock does.

The build cuts the land under a `visible_from` line and keeps rock out of its corridor; the trees
were the last thing between a place and the vantage said to see it (the Hum Stone, hidden from Rook
Mill by the Brow's thorn and oak). These check the pass on a synthetic world: every tree whose
trunk is in a line's corridor between the two pads and whose top reaches the ray is taken, and
nothing else is.

    python3 -m pytest tools/world/tests/test_tree_sightlines.py
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)
sys.path.insert(0, os.path.join(REPO, "tools"))

import sightlines as SIGHT  # noqa: E402
from worldgen import crags as CR  # noqa: E402
from worldgen import trees as TR  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.rows import Rows, pack_rgb  # noqa: E402

THORN = "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"
OAK = "res://assets/models/trees/hearthvale_oak_d/hearthvale_oak_d.glb"
STONE = "res://assets/models/rocks/hearthvale_boulder_a/hearthvale_boulder_a.glb"
TABLE = {"hearthvale_hawthorn_a": (np.zeros((1, 3)), 4.2), "hearthvale_oak_d": (np.zeros((1, 3)), 12.1)}
GROUND_M = 100.0
VANTAGE = (-300.0, 0.0)
TARGET = (300.0, 0.0)
KIND = "ruins"
PAD_A, PAD_B = 20.0, 30.0


def world(trench: tuple | None = None, ridge: tuple | None = None):
    """A flat 1 km square at GROUND_M, with optionally a trench (x0, x1, depth) or a ridge
    (x0, x1, height) across the line."""
    g = Grid(1024.0, 256)
    xs, zs = g.coords(np.float64)
    H = np.full((g.n, g.n), GROUND_M, dtype=np.float32)
    X = np.broadcast_to(xs[None, :], H.shape)
    for band, sign in ((trench, -1.0), (ridge, 1.0)):
        if band is not None:
            x0, x1, d = band
            H[(X >= x0) & (X <= x1)] += sign * d
    return g, H


def claims():
    return [(VANTAGE, TARGET, KIND, PAD_A, PAD_B)]


def scatter_rows(rng, n: int, spread_z: float = 40.0) -> np.ndarray:
    """[n, 5] x, z, yaw, scale of trees strewn over the line's whole length and either side."""
    x = rng.uniform(-420.0, 420.0, n)
    z = rng.uniform(-spread_z, spread_z, n)
    return np.stack([x, z, rng.uniform(0, 360, n), rng.uniform(0.8, 1.2, n)], axis=1)


def as_rows(arr: np.ndarray, H, g) -> Rows:
    r = Rows()
    y = sample_bilinear(H, g, arr[:, 0], arr[:, 1])
    r.add_arrays(arr[:, 0], y, arr[:, 1], arr[:, 2], arr[:, 3], pack_rgb(np.full((len(arr), 3), 0.5)))
    return r


def line_at(H, g, k, t):
    eye = float(sample_bilinear(H, g, np.array([VANTAGE[0]]), np.array([VANTAGE[1]]))[0]) + k["EYE_M"]
    top = float(sample_bilinear(H, g, np.array([TARGET[0]]), np.array([TARGET[1]]))[0]) \
        + k["LANDMARK_M"].get(KIND, k["LANDMARK_DEFAULT_M"])
    return eye + (top - eye) * t - k["CLEARANCE_M"] - TR.SIGHT_TREE_SPARE_M


def standing_into(buckets, H, g, k) -> list:
    """Every tree left whose trunk is in the corridor between the pads and whose top reaches the ray."""
    ln = TARGET[0] - VANTAGE[0]
    bad = []
    for by_asset in buckets.values():
        for asset, rows in by_asset.items():
            if "/trees/" not in asset:
                continue
            height = TABLE[os.path.splitext(os.path.basename(asset))[0]][1]
            for r in rows:
                x, z, sc = float(r[0]), float(r[2]), float(r[4])
                t = (x - VANTAGE[0]) / ln
                if not (PAD_A / ln < t < 1.0 - PAD_B / ln) or abs(z) >= TR.SIGHT_TREE_CORRIDOR_M:
                    continue
                ground = float(sample_bilinear(H, g, np.array([x]), np.array([z]))[0])
                line = line_at(H, g, k, t)
                if ground + height * sc > line and ground <= line:
                    bad.append((asset.split("/")[-2], round(x), round(z)))
    return bad


class ClearSightlines(unittest.TestCase):
    def setUp(self):
        self.k = SIGHT.constants()
        self.rng = np.random.default_rng(7)

    def test_no_tree_trunk_stands_in_the_corridor_into_the_line(self):
        g, H = world()
        thorns = scatter_rows(self.rng, 600)
        oaks = scatter_rows(self.rng, 200)
        buckets = {(0, 0): {THORN: as_rows(thorns, H, g)},
                   (1, 0): {OAK: [[float(a[0]), 0.0, float(a[1]), float(a[2]), float(a[3]), "#808080"] for a in oaks]}}
        before = sum(len(r) for b in buckets.values() for r in b.values())
        self.assertTrue(standing_into(buckets, H, g, self.k), "the synthetic scatter has trees in the way to begin with")
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        after = sum(len(r) for b in buckets.values() for r in b.values())
        self.assertEqual(standing_into(buckets, H, g, self.k), [])
        self.assertEqual(before - after, got["trees"])
        self.assertEqual(sum(got["by_claim"]), got["trees"])
        self.assertEqual(sum(got["by_asset"].values()), got["trees"])
        self.assertGreater(got["trees"], 0)

    def test_nothing_out_of_the_corridor_or_on_the_pads_is_taken(self):
        g, H = world()
        rows = np.array([[0.0, TR.SIGHT_TREE_CORRIDOR_M + 0.5, 0.0, 1.0],     # just out of the corridor
                         [0.0, -(TR.SIGHT_TREE_CORRIDOR_M + 3.0), 0.0, 1.0],
                         [VANTAGE[0] + PAD_A * 0.5, 0.0, 0.0, 1.0],           # on the vantage's pad
                         [TARGET[0] - PAD_B * 0.5, 0.0, 0.0, 1.0],            # on the target's pad
                         [TARGET[0] + 40.0, 0.0, 0.0, 1.0],                   # past the target
                         [VANTAGE[0] - 40.0, 0.0, 0.0, 1.0]])                 # behind the vantage
        buckets = {(0, 0): {OAK: as_rows(rows, H, g)}}
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        self.assertEqual(got["trees"], 0)
        self.assertEqual(len(buckets[(0, 0)][OAK]), len(rows))

    def test_a_tree_in_the_way_is_taken_and_a_stone_is_not(self):
        g, H = world()
        on_line = np.array([[0.0, 0.0, 0.0, 1.0], [-100.0, 5.0, 90.0, 1.0], [150.0, -8.0, 10.0, 1.0]])
        buckets = {(0, 0): {OAK: as_rows(on_line, H, g), STONE: as_rows(on_line, H, g)}}
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        self.assertEqual(got["trees"], 3)
        self.assertNotIn(OAK, buckets[(0, 0)], "an emptied asset is dropped from its cell")
        self.assertEqual(len(buckets[(0, 0)][STONE]), 3, "rock is the crags' to keep out, not this pass's")

    def test_a_tree_down_in_a_dip_under_the_line_is_left(self):
        g, H = world(trench=(-60.0, 60.0, 30.0))
        rows = np.array([[0.0, 0.0, 0.0, 1.0], [30.0, 4.0, 0.0, 1.0]])
        buckets = {(0, 0): {OAK: as_rows(rows, H, g)}}
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        self.assertEqual(got["trees"], 0, "a 12 m oak 30 m down a dip does not reach a line across its top")

    def test_a_tree_on_land_that_already_stands_into_the_line_is_left(self):
        g, H = world(ridge=(-20.0, 20.0, 25.0))
        rows = np.array([[0.0, 0.0, 0.0, 1.0]])
        buckets = {(0, 0): {OAK: as_rows(rows, H, g)}}
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        self.assertEqual(got["trees"], 0, "where the land blocks the line, the land is the line's to answer")

    def test_a_line_seen_from_high_ground_keeps_the_wood_under_it(self):
        g, H = world()
        xs, _ = g.coords(np.float64)
        X = np.broadcast_to(xs[None, :], H.shape)
        H = np.where(X < -250.0, GROUND_M + 60.0, H).astype(np.float32)     # the vantage on a 60 m scarp
        rows = np.array([[-50.0, 0.0, 0.0, 1.0], [100.0, 3.0, 0.0, 1.0]])
        buckets = {(0, 0): {OAK: as_rows(rows, H, g)}}
        got = TR.clear_sightlines(buckets, g, H, claims(), self.k, table=TABLE)
        self.assertEqual(got["trees"], 0, "a line looking down over a wood does not fell it")

    def test_the_corridor_is_narrower_than_the_rock_s_and_the_build_clears_before_it_seats(self):
        self.assertLessEqual(TR.SIGHT_TREE_CORRIDOR_M, CR.SIGHTLINE_CORRIDOR_M)
        self.assertGreaterEqual(TR.SIGHT_TREE_CORRIDOR_M, 6.0)
        src = open(os.path.join(TOOLS_WORLD, "build_world.py"), encoding="utf-8").read()
        self.assertIn("TR.clear_sightlines(", src)
        self.assertLess(src.index("TR.clear_sightlines("), src.index("TR.seat(buckets"))


if __name__ == "__main__":
    unittest.main()
