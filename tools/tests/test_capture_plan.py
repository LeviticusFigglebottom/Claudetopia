#!/usr/bin/env python3
"""The capture plans' cameras stand in the open.

    python3 tools/tests/test_capture_plan.py     # or: python3 -m unittest discover tools/tests

One of the Briarwold's seven frames in the drop-test sheet was a photograph of leaves: the vista
camera stood twelve metres up inside a giant oak's crown, and the landmark camera looked at the
Grandfather through the crowns on the rise in front of it. The drop test scored both. The plan
generator now knows where every crown is and how tall it stands (tools/capture/make_default_plan.py);
this is what keeps it knowing. A camera on the ground has the other fault: its first ground shot
stood twelve metres from a giant oak a quarter of a turn off its look, and a third of the frame was
bark. A ground shot now keeps the trunks out of the front of its view.

The crown model is checked on synthetic trees, which needs nothing built. The committed plans are
checked against the built world, and skip with a reason when there is none.
"""
from __future__ import annotations

import json
import math
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "capture"))

import make_default_plan as plan  # noqa: E402

GEN = os.path.join(REPO, "game", "world", "generated")
RAISED = ("_landmark", "_vista", "_approach")


def _scatter_with(trees: list) -> plan.Scatter:
    """A Scatter holding `trees` (x, z, ground, reach, top), each in the cell it stands in."""
    sc = plan.Scatter()

    def cell(cx, cz):
        mine = [t for t in trees
                if int((t[0] + sc.half) // sc.cell_m) == cx and int((t[1] + sc.half) // sc.cell_m) == cz]
        return ([(t[0], t[1]) for t in mine], mine)
    sc._cell = cell  # type: ignore[assignment]
    return sc


class CrownModel(unittest.TestCase):
    """A tree is a cylinder of crown on a trunk; a lens or a line is blocked only inside it."""

    def setUp(self):
        # a giant oak: 14 m of reach, standing on ground at 100 m, 41 m tall
        self.sc = _scatter_with([(0.0, 0.0, 100.0, 14.0, 141.0)])

    def test_a_lens_in_the_crown_is_in_the_crown(self):
        self.assertTrue(self.sc.in_crown(10.0, 112.0, 0.0), "twelve metres up, ten from the trunk")

    def test_a_lens_above_the_tree_is_clear(self):
        self.assertFalse(self.sc.in_crown(10.0, 155.0, 0.0), "fifty-five metres up is over the oak")

    def test_a_lens_beside_the_crown_is_clear(self):
        self.assertFalse(self.sc.in_crown(20.0, 112.0, 0.0), "twenty metres off is beside it")

    def test_a_line_through_the_crown_is_blocked(self):
        hits = self.sc.crowns_across((-50.0, 120.0, 0.0), (50.0, 120.0, 0.0), 0.0, 200.0)
        self.assertEqual(hits, 1)

    def test_a_line_over_the_tree_is_clear(self):
        hits = self.sc.crowns_across((-50.0, 160.0, 0.0), (50.0, 150.0, 0.0), 0.0, 200.0)
        self.assertEqual(hits, 0)

    def test_a_line_past_the_tree_is_clear(self):
        hits = self.sc.crowns_across((-50.0, 120.0, 30.0), (50.0, 120.0, 30.0), 0.0, 200.0)
        self.assertEqual(hits, 0)

    def test_only_the_asked_for_stretch_counts(self):
        hits = self.sc.crowns_across((-50.0, 120.0, 0.0), (50.0, 120.0, 0.0), 0.0, 20.0)
        self.assertEqual(hits, 0, "the tree is fifty metres along; the first twenty are clear")


class ViewClear(unittest.TestCase):
    """A camera at eye height does not stand with its nose against a trunk."""

    def setUp(self):
        # the Briarwold's giant oak: twelve metres out, twenty-five degrees off the look, 14 m of reach
        a = math.radians(25.0)
        self.oak = (12.0 * math.cos(a), 12.0 * math.sin(a), 100.0, 14.0, 141.0)

    def test_a_giant_tree_just_off_the_look_fills_the_frame(self):
        self.assertFalse(_scatter_with([self.oak]).view_clear(0.0, 0.0, 0.0))

    def test_the_same_tree_behind_the_lens_does_not(self):
        self.assertTrue(_scatter_with([self.oak]).view_clear(0.0, 0.0, 180.0))

    def test_a_small_tree_eight_metres_out_is_part_of_the_view(self):
        hawthorn = (8.0, 0.0, 100.0, 3.0, 109.0)
        self.assertTrue(_scatter_with([hawthorn]).view_clear(0.0, 0.0, 0.0))

    def test_a_ground_shot_backs_away_from_the_trunk(self):
        sc = _scatter_with([self.oak])
        x, z = sc.clear_spot(0.0, 0.0, 180.0, want=5.5, look_deg=0.0)
        self.assertLess(x, 0.0, "it steps back along its bearing")
        self.assertTrue(sc.view_clear(x, z, 0.0))

    def test_without_a_look_the_search_is_what_it_was(self):
        self.assertEqual(_scatter_with([self.oak]).clear_spot(0.0, 0.0, 180.0, want=5.5), (0.0, 0.0))


@unittest.skipUnless(os.path.exists(os.path.join(GEN, "world_manifest.json")),
                     "the world has not been built (./run.sh world)")
class CommittedPlans(unittest.TestCase):
    """Every raised camera in default.json and horizon.json has a clear lens, every ground one a clear view."""

    @classmethod
    def setUpClass(cls):
        cls.scatter = plan.Scatter()
        cls.plans = {}
        for name in ("default", "horizon"):
            with open(os.path.join(TOOLS, "capture", "plans", name + ".json"), "r", encoding="utf-8") as f:
                cls.plans[name] = json.load(f)["shots"]

    def test_no_raised_camera_is_in_a_crown(self):
        for name, shots in self.plans.items():
            for s in shots:
                if not s["label"].endswith(RAISED):
                    continue
                x, y, z = s["pos"]
                self.assertFalse(self.scatter.in_crown(x, y, z),
                                 "%s: %s stands in a tree's crown" % (name, s["label"]))

    def test_the_vistas_see_past_their_own_trees(self):
        for s in self.plans["default"]:
            if not s["label"].endswith("_vista"):
                continue
            hits = self.scatter.crowns_across(tuple(s["pos"]), tuple(s["look_at"]), 0.0, plan.LINE_TREE_REACH_M)
            self.assertEqual(hits, 0, "%s looks into a crown within %.0f m" % (s["label"], plan.LINE_TREE_REACH_M))

    def test_no_ground_shot_looks_at_a_trunk(self):
        for s in self.plans["default"]:
            if "_ground" not in s["label"]:
                continue
            x, _y, z = s["pos"]
            tx, _ty, tz = s["look_at"]
            look = math.degrees(math.atan2(tz - z, tx - x))
            self.assertTrue(self.scatter.view_clear(x, z, look), "%s stands with a trunk in its view" % s["label"])


if __name__ == "__main__":
    unittest.main()
