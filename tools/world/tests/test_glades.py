#!/usr/bin/env python3
"""A place in the deep wood whose def asks for a glade (`glade_m`) has the trees taken off a disc round
it and off a way to its nearest road, and nothing else: the Windthrow, Tinehold and the Charter Delf
stood in the Greatwood's canopy, every view of them near black.

    python3 -m pytest tools/world/tests/test_glades.py
"""
from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import trees as TR  # noqa: E402
from worldgen.rows import Rows  # noqa: E402

OAK = "res://assets/models/trees/briarwold_giant_oak_a/briarwold_giant_oak_a.glb"
## its height, as the contact table has it: a crown reaching 0.4 of that
TABLE = {"briarwold_giant_oak_a": (None, 28.7)}
CROWN = 28.7 * TR.GLADE_CROWN_PER_H
FERN = "res://assets/models/flora/briarwold_fern_a/briarwold_fern_a.glb"


def _wood():
    """Trees and ferns every 4 m over 200 m square round the origin, in one cell."""
    rows = []
    for x in range(-100, 101, 4):
        for z in range(-100, 101, 4):
            rows.append([float(x), 10.0, float(z), 0.0, 1.0, "#ffffff"])
    oaks = Rows()
    oaks.extend(rows)
    return {(0, 0): {OAK: oaks, FERN: [list(r) for r in rows]}}


class Glades(unittest.TestCase):
    def setUp(self):
        # a road running north-south 60 m east of the place
        self.roads = [SimpleNamespace(points=np.array([[60.0, -200.0], [60.0, 200.0]]))]
        self.pois = [{"id": "core:poi/glade", "position": [0.0, 0.0], "glade_m": 30.0},
                     {"id": "core:poi/no_glade", "position": [-80.0, -80.0]}]

    def test_the_glade_finds_its_road(self):
        g = TR.glades(self.pois, self.roads)
        self.assertEqual(len(g), 1)
        (c, r, road, w) = g[0]
        self.assertEqual(c, (0.0, 0.0))
        self.assertEqual(r, 30.0)
        self.assertAlmostEqual(road[0], 60.0)
        self.assertAlmostEqual(road[1], 0.0)
        self.assertEqual(w, TR.GLADE_APPROACH_M)

    def test_trees_go_off_the_disc_and_the_way_and_nothing_else(self):
        buckets = _wood()
        before = len(buckets[(0, 0)][OAK])
        out = TR.clear_glades(buckets, TR.glades(self.pois, self.roads), TABLE)
        left = buckets[(0, 0)][OAK]
        xz = left.xz() if isinstance(left, Rows) else np.array([(r[0], r[2]) for r in left])
        d = np.hypot(xz[:, 0], xz[:, 1])
        self.assertFalse((d < 30.0).any(), "a tree is left in the glade")
        self.assertFalse((d - CROWN < 30.0).any(), "a crown reaches over the glade")
        on_way = (xz[:, 0] >= 0.0) & (xz[:, 0] <= 62.0) & (np.abs(xz[:, 1]) < TR.GLADE_APPROACH_M * 0.5 + CROWN)
        self.assertFalse(on_way.any(), "a tree's crown is over the way to the road")
        self.assertTrue(((d > 30.0 + CROWN + 2.0) & ~on_way).sum() > 0, "the wood beyond stands")
        self.assertEqual(out["trees"], before - len(left))
        self.assertEqual(out["by_glade"], [out["trees"]])
        # the low cover is not touched
        self.assertEqual(len(buckets[(0, 0)][FERN]), before)

    def test_no_glade_no_change(self):
        buckets = _wood()
        before = len(buckets[(0, 0)][OAK])
        out = TR.clear_glades(buckets, TR.glades([self.pois[1]], self.roads), TABLE)
        self.assertEqual(out["trees"], 0)
        self.assertEqual(len(buckets[(0, 0)][OAK]), before)


if __name__ == "__main__":
    unittest.main()
