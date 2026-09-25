#!/usr/bin/env python3
"""Nothing is left in the air or under the hill (worldgen.offground): a row whose whole footprint is
more than OFF_M under its foot is floating, one whose top is more than OFF_M under all of its ground
is buried, and both go; a ledge on a sheer face, its foot at the face's foot and its back in the
cliff, stays.

    python3 -m pytest tools/world/tests/test_offground.py
"""
from __future__ import annotations

import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import offground as OFF  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.rows import Rows, pack_rgb  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
BOULDER = "res://assets/models/rocks/hearthvale_boulder_a/hearthvale_boulder_a.glb"


class OffGround(unittest.TestCase):
    def setUp(self):
        self.g = Grid(512.0, 256)
        X, Z = self.g.mesh(np.float64)
        # a beach at half a metre under a sheer 110 m cliff at x = 0 (the w4096c cove)
        self.H = np.where(X < 0.0, 110.0, 0.5 + 0.0 * Z).astype(np.float32)

    def test_on_the_beach_and_against_the_cliff_stay_in_the_air_and_the_hill_go(self):
        rows = [[40.0, 0.3, 10.0, 0.0, 1.0, "#ffffff"],        # on the beach under the cliff: stays
                [2.0, 0.3, 20.0, 0.0, 1.0, "#ffffff"],         # at the cliff's foot: stays
                [40.0, 60.0, 30.0, 0.0, 1.0, "#ffffff"],       # 60 m over the beach: floating
                [-40.0, 20.0, 40.0, 0.0, 1.0, "#ffffff"]]      # 90 m under the fell top: buried
        buckets = {(1, 1): {BOULDER: [list(r) for r in rows]}}
        got = OFF.sweep(buckets, self.g, self.H, REPO)
        self.assertEqual(got, {"boulder_a": [1, 1]})
        left = buckets[(1, 1)][BOULDER]
        self.assertEqual([r[2] for r in left], [10.0, 20.0])

    def test_scatter_arrays_are_swept_as_rows_are(self):
        r = Rows()
        r.add_arrays([40.0, 40.0], [0.3, 30.0], [10.0, 12.0], [0.0, 0.0], [1.0, 1.0], pack_rgb(np.ones((2, 3))))
        r.extend([[-40.0, 20.0, 40.0, 0.0, 1.0, "#ffffff"]])
        buckets = {(1, 1): {BOULDER: r}}
        got = OFF.sweep(buckets, self.g, self.H, REPO)
        self.assertEqual(got, {"boulder_a": [1, 1]})
        self.assertEqual(len(buckets[(1, 1)][BOULDER]), 1)
        self.assertEqual(list(buckets[(1, 1)][BOULDER])[0][2], 10.0)


if __name__ == "__main__":
    unittest.main()
