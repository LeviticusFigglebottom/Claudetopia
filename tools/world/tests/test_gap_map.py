#!/usr/bin/env python3
"""The gap map measures what it says it measures.

    python3 -m pytest tools/world/tests/test_gap_map.py
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)
sys.path.insert(0, os.path.join(TOOLS_WORLD, "atlas"))

import gap_map as G  # noqa: E402


def thing(x, z, r=0.0, cls="poi"):
    return {"id": "t%d_%d" % (x, z), "name": "", "kind": "", "x": float(x), "z": float(z), "r": r, "cls": cls}


class GapMap(unittest.TestCase):
    def test_a_road_with_things_at_its_ends_only_is_one_gap(self):
        road = [("r", [(0.0, 0.0), (1000.0, 0.0)])]
        m = G.road_gaps(road, [thing(0, 0), thing(1000, 0)], near=60, thin=300, step=5)
        self.assertAlmostEqual(m["road_km"], 1.0, places=3)
        self.assertEqual(len(m["thin"]), 1)
        # from the last point within 60 m of the first thing to the first within 60 m of the second
        self.assertAlmostEqual(m["thin"][0]["length_m"], 880.0, delta=6.0)

    def test_a_thing_beside_the_road_halves_the_gap(self):
        road = [("r", [(0.0, 0.0), (1000.0, 0.0)])]
        m = G.road_gaps(road, [thing(0, 0), thing(1000, 0), thing(500, 40)], near=60, thin=300, step=5)
        self.assertEqual(len(m["thin"]), 2)
        self.assertLess(m["longest_m"], 420.0)

    def test_a_thing_too_far_off_the_road_does_not_count(self):
        road = [("r", [(0.0, 0.0), (1000.0, 0.0)])]
        m = G.road_gaps(road, [thing(0, 0), thing(1000, 0), thing(500, 90)], near=60, thin=300, step=5)
        self.assertEqual(len(m["thin"]), 1)

    def test_a_settlement_counts_out_to_its_radius(self):
        road = [("r", [(0.0, 0.0), (1000.0, 0.0)])]
        m = G.road_gaps(road, [thing(0, 0, r=300.0, cls="place"), thing(1000, 0)], near=60, thin=300, step=5)
        self.assertAlmostEqual(m["thin"][0]["length_m"], 1000.0 - 360.0 - 60.0, delta=6.0)

    def test_short_gaps_are_not_thin(self):
        road = [("r", [(0.0, 0.0), (400.0, 0.0)])]
        m = G.road_gaps(road, [thing(0, 0), thing(400, 0)], near=60, thin=300, step=5)
        self.assertEqual(m["thin"], [])
        self.assertEqual(m["thin_km"], 0.0)

    def test_the_committed_map_measures(self):
        m = G.measure()
        self.assertGreater(m["road"]["road_km"], 50.0)
        self.assertGreater(len(m["things"]), 250)
        self.assertLessEqual(m["road"]["thin_km"], m["road"]["road_km"])


if __name__ == "__main__":
    unittest.main()
