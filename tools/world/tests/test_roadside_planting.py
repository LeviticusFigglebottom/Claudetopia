#!/usr/bin/env python3
"""A road through open country has its own planting (roadside.planting): a verge, a hedge or a
wall in runs along it, and the odd tree. And nothing made or grown stands in the water (dry.sweep).

Playtest 5: "the world still feels empty between places". A road was its carriageway and its
rails, with the scatter going on either side as if it were not there.

    python3 -m pytest tools/world/tests/test_roadside_planting.py
"""
from __future__ import annotations

import json
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
from worldgen import dry as DRY  # noqa: E402
from worldgen import hydro as HY  # noqa: E402
from worldgen import roadside as RS  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

WIDTH = 5.0
RIVER_X = 100.0
PAD = (-300.0, 0.0, 40.0)
FIELD_M = 60.0


class Planting(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(1024.0, 512, 256.0)
        n = g.n
        X, Z = g.mesh(np.float64)
        X = np.broadcast_to(X, (n, n))
        Z = np.broadcast_to(Z, (n, n))
        cls.H = (50.0 + 0.02 * X).astype(np.float32)
        owner = np.zeros((n, n), dtype=np.uint8)
        slope = np.full((n, n), 0.02, dtype=np.float32)
        cls.water = (np.abs(X - RIVER_X) < 4.0).astype(np.uint8)
        cls.pad = np.hypot(X - PAD[0], Z - PAD[1]) < PAD[2]
        road_d = np.abs(Z).astype(np.float32)
        road_w = np.full((n, n), WIDTH, dtype=np.float32)
        cls.regions = [SimpleNamespace(index=0, shape="downs", art_short="hearthvale", palette=["#90a060", "#7a9050"])]
        roads = [SimpleNamespace(id="test:road/a", points=np.array([[-480.0, 0.0], [480.0, 0.0]]), width=WIDTH)]
        with open(os.path.join(TOOLS_WORLD, "scatter_rules.json"), "r", encoding="utf-8") as f:
            rules = json.load(f)
        index = CELLS.asset_index(REPO)
        # fields along the road: 60 m strips, a different field each side, and none past x = 300
        # (open country, where no frontage may stand)
        cls.labels = np.where(X < 300.0, (np.floor((X + 512.0) / FIELD_M) * 2 + (Z > 0)).astype(np.int32), -1)
        cls.beside = RS.place(g, cls.H, owner, slope, cls.water, cls.pad, np.full((n, n), 1e6, np.float32),
                              cls.regions, roads, [], index, 3, field_labels=cls.labels)
        cls.out = RS.planting(g, cls.H, owner, slope, cls.water, cls.pad, road_d, road_w, cls.regions, roads,
                              index, 3, rules=rules, beside=cls.beside, field_labels=cls.labels)
        cls.rows = [(a, r) for by in cls.out.values() for a, rows in by.items() for r in rows]

    def of(self, part: str) -> np.ndarray:
        return np.array([r[:3] for a, r in self.rows if part in a], dtype=np.float64).reshape(-1, 3)

    def test_a_verge_lines_the_road(self):
        verge = self.of("/flora/")
        # both sides, over most of the road's dry, unpadded length (the rails keep some of it)
        self.assertGreater(len(verge), 0.6 * 1.2 * 2 * (960.0 - 2 * PAD[2] - 8.0))
        off = np.abs(verge[:, 2])
        self.assertTrue(np.all(off > WIDTH * 0.5 + 0.4), "a plant on the carriageway")
        self.assertTrue(np.all(off < WIDTH * 0.5 + 3.8), "a verge plant out in the field")
        self.assertGreater((verge[:, 2] > 0).mean(), 0.35)
        self.assertLess((verge[:, 2] > 0).mean(), 0.65)

    def test_a_hedge_runs_along_part_of_it(self):
        hedge = self.of("hedge_segment")
        self.assertGreater(len(hedge), 20)
        off = np.abs(hedge[:, 2]) - WIDTH * 0.5
        self.assertTrue(np.all((off > 2.3) & (off < 3.5)))
        # in runs, not everywhere: under 80% of the road's length on either side
        self.assertLess(len(hedge) * 2.1, 0.8 * 2 * 960.0)

    def _runs(self, pts: np.ndarray, gap: float) -> list:
        """Runs of points along x on each side of the road: [(side, x0, x1)]."""
        out = []
        for side in (1.0, -1.0):
            xs = np.sort(pts[np.sign(pts[:, 2]) == side][:, 0])
            if xs.size == 0:
                continue
            start = xs[0]
            for a, b in zip(xs, xs[1:]):
                if b - a > gap:
                    out.append((side, start, a))
                    start = b
            out.append((side, start, xs[-1]))
        return out

    def test_a_frontage_is_one_field_s_edge_from_boundary_to_boundary(self):
        # (playtest 6: fences along roads randomly placed, starting and ending in the middle of nothing)
        for part, gap in (("hedge_segment", 4.0), ("fence_post_rail", 4.0)):
            pts = np.array([r[:3] for by in list(self.out.values()) + list(self.beside.values())
                            for a, rows in by.items() if part in a for r in rows], dtype=np.float64).reshape(-1, 3)
            self.assertGreater(len(pts), 10, part)
            self.assertTrue(np.all(pts[:, 0] < 300.0), "%s out in the open country" % part)
            for side, x0, x1 in self._runs(pts, gap):
                self.assertGreaterEqual(x1 - x0, RS.FRONTAGE_MIN_M - 3.0, "%s: a stub of a run" % part)
                for end in (x0, x1):
                    # at a field's boundary (within the inset and a step), or where the pad or the river cut it
                    to_edge = abs(((end + 512.0) % FIELD_M + FIELD_M / 2) % FIELD_M - FIELD_M / 2)
                    cut = min(abs(end - (PAD[0] - PAD[2])), abs(end - (PAD[0] + PAD[2])), abs(end - RIVER_X),
                              abs(abs(end) - 480.0), abs(end - 300.0))   # (or the road's end, or the open country's edge)
                    self.assertTrue(to_edge < RS.FRONTAGE_INSET_M + 5.0 or cut < 12.0,
                                    "%s run ends in the middle of a field at x %.1f" % (part, end))

    def test_a_field_is_railed_or_hedged_not_both(self):
        rails = np.array([r[:3] for by in self.beside.values() for a, rows in by.items() if "fence_post_rail" in a
                          for r in rows], dtype=np.float64).reshape(-1, 3)
        hedge = self.of("hedge_segment")
        lab = lambda p: (np.floor((p[:, 0] + 512.0) / FIELD_M) * 2 + (p[:, 2] > 0)).astype(int)
        self.assertFalse(set(lab(rails).tolist()) & set(lab(hedge).tolist()))

    def test_the_odd_tree_stands_back_from_it(self):
        trees = self.of("/trees/")
        self.assertGreater(len(trees), 3)
        self.assertLess(len(trees), 30)
        self.assertTrue(np.all(np.abs(trees[:, 2]) > WIDTH * 0.5 + 3.0))

    def test_none_on_the_pad_in_the_water_or_on_the_rails(self):
        allp = np.array([r[:3] for _, r in self.rows], dtype=np.float64)
        self.assertFalse(np.any(np.hypot(allp[:, 0] - PAD[0], allp[:, 2] - PAD[1]) < PAD[2] - 2.0), "on the pad")
        self.assertFalse(np.any(np.abs(allp[:, 0] - RIVER_X) < 3.0), "in the river")
        rails = np.array([r[:3] for by in self.beside.values() for rows in by.values() for r in rows])
        if rails.size:
            hedge = self.of("hedge_segment")
            d = np.min(np.hypot(hedge[:, None, 0] - rails[None, :, 0], hedge[:, None, 2] - rails[None, :, 2]), axis=1)
            self.assertGreater(float(d.min()), RS.VERGE_CLEAR_M - 1e-6)

    def test_every_row_stands_on_the_ground(self):
        for _, r in self.rows[:500]:
            self.assertAlmostEqual(r[1], 50.0 + 0.02 * r[0], delta=0.1)


class Dry(unittest.TestCase):
    def test_a_prop_or_tree_in_a_river_is_taken_out_and_rock_and_reeds_are_not(self):
        g = Grid(512.0, 64, 256.0)                        # 8 m texels: the river is under two of them
        river = HY.River(id="test:river/b", points=np.array([[0.0, -200.0], [0.0, 200.0]]),
                         width=np.array([6.0, 6.0], dtype=np.float32), surface=np.array([10.0, 9.0], dtype=np.float32))
        mask = np.zeros((g.n, g.n), dtype=np.uint8)       # and not in the mask at all
        cart = "res://assets/models/props/briarwold_cart_a/briarwold_cart_a.glb"
        tree = "res://assets/models/trees/briarwold_oak_a/briarwold_oak_a.glb"
        rock = "res://assets/models/rocks/briarwold_boulder_a/briarwold_boulder_a.glb"
        reed = "res://assets/models/flora/briarwold_reeds_a/briarwold_reeds_a.glb"
        buckets = {(1, 1): {cart: [[1.0, 9.5, 20.0, 0, 1, "#fff"], [9.0, 9.5, 20.0, 0, 1, "#fff"]],
                            tree: [[-2.5, 9.5, 5.0, 0, 1, "#fff"]],
                            rock: [[0.5, 9.0, 0.0, 0, 1, "#fff"]], reed: [[2.0, 9.0, 0.0, 0, 1, "#fff"]]}}
        dropped = DRY.sweep(buckets, g, [river], mask)
        self.assertEqual(dropped, {cart: 1, tree: 1})
        self.assertEqual([r[0] for r in buckets[(1, 1)][cart]], [9.0])
        self.assertNotIn(tree, buckets[(1, 1)])
        self.assertIn(rock, buckets[(1, 1)])
        self.assertIn(reed, buckets[(1, 1)])


if __name__ == "__main__":
    unittest.main()
