#!/usr/bin/env python3
"""tools/capture/relative_plan.py: a plan's coordinates said as places come back to the same
points, and the hand-written plans say their cameras as places (docs/COORDINATES.md).

The round trip is checked on synthetic ground, which needs nothing built.
"""
from __future__ import annotations

import json
import math
import os
import sys
import unittest

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(TOOLS, "capture"))

import relative_plan as rp  # noqa: E402

HAND_PLANS = ("streets", "start", "opening_scout", "gait", "roll", "first_fight", "starts_warrior_ranger")


class SlopeGround:
    """Ground that rises a metre every ten metres east."""

    def height(self, x: float, z: float) -> float:
        return 0.1 * x + 20.0


PLACES = {"core:place/a": (100.0, 200.0), "core:place/b": (900.0, -300.0)}


class RoundTrip(unittest.TestCase):
    def test_a_camera_comes_back_where_it_stood(self):
        g = SlopeGround()
        plan = {"shots": [{"label": "one", "pos": [130.0, 0.0, 150.0], "height_above_ground": 1.7,
                           "look_at": [880.0, 55.0, -280.0], "fov": 60}]}
        report = rp.convert_plan(plan, PLACES, g)
        shot = plan["shots"][0]
        self.assertEqual(list(shot.keys()), ["label", "at", "look", "fov"], "the plan keeps its order")
        self.assertEqual(shot["at"]["place"], "core:place/a")
        self.assertEqual(shot["look"]["place"], "core:place/b")
        for label, want, got in report:
            self.assertLess(math.dist(want, got), 0.01, label)

    def test_north_is_minus_z_and_east_is_plus_x(self):
        g = SlopeGround()
        north = rp.spec_of(PLACES, g, 100.0, 100.0, 0.0)
        east = rp.spec_of(PLACES, g, 200.0, 200.0, 0.0)
        self.assertAlmostEqual(north["bearing"], 0.0, places=3)
        self.assertAlmostEqual(east["bearing"], 90.0, places=3)

    def test_a_gait_stands_at_a_place(self):
        plan = {"gait": {"pos": [140.0, 0.0, 200.0], "heading": 90.0}}
        rp.convert_plan(plan, PLACES, SlopeGround())
        self.assertEqual(list(plan["gait"].keys()), ["at", "heading"])
        self.assertAlmostEqual(plan["gait"]["at"]["distance"], 40.0, places=2)


class HandPlans(unittest.TestCase):
    """The plans written by hand say every camera as a place, so a redrawn map moves them."""

    def test_no_hand_plan_holds_coordinates(self):
        for name in HAND_PLANS:
            with open(os.path.join(TOOLS, "capture", "plans", name + ".json"), "r", encoding="utf-8") as f:
                plan = json.load(f)
            for shot in plan.get("shots", []) + plan.get("sequences", []):
                for key in ("pos", "look_at"):
                    self.assertNotIn(key, shot, "%s: %s still has %s" % (name, shot.get("label"), key))
                if "body" in shot:
                    self.assertIsInstance(shot["body"], dict, "%s: %s stands its body at coordinates" % (name, shot.get("label")))
            gait = plan.get("gait")
            if gait:
                self.assertNotIn("pos", gait, "%s: the gait still stands at coordinates" % name)


if __name__ == "__main__":
    unittest.main()
