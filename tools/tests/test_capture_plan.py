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


class RaisedOverTheCrowns(unittest.TestCase):
    """A vista with no clear vantage stands over the tallest crown round it, not just 36 m up."""

    def test_the_fallback_vista_is_over_a_giant_oak(self):
        class Flat:
            def high_points(self, x, z, radius, count=12, samples=220, apart_m=30.0):
                return [(x, z, 100.0)]

            def high_point(self, x, z, radius, samples=96):
                return (x, z, 100.0)

            def low_point(self, x, z, radius, samples=140):
                return (x + 400.0, z, 90.0)

            def at(self, x, z):
                return 100.0

        # a giant oak on the vantage itself, its crown 41 m over the ground
        sc = _scatter_with([(0.0, 0.0, 100.0, 14.0, 141.0)])
        cam, _look, found = plan.vista_camera(Flat(), sc, 0.0, 0.0, 400.0, 0.0, "test_vista")
        self.assertFalse(found)
        self.assertFalse(sc.in_crown(*cam), "the raised vista at %.1f m is in the crown" % cam[1])


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

    def test_every_ground_frame_is_a_frame_of_the_region(self):
        # briarwold_ground1 once passed every check above and photographed sky over fog from ten
        # metres inside the world's east edge; briarwold_ground2 passed them and photographed a
        # giant oak and a cliff ledge. These are the checks on the frame itself.
        import frame_check as fc
        ground, props = fc.PP.Ground(GEN), fc.Props(GEN)
        bad = []
        for s in self.plans["default"]:
            if "_ground" in s["label"]:
                f = fc.faults(s, ground, props)
                if f:
                    bad.append("%s: %s" % (s["label"], "; ".join(f)))
        self.assertEqual(bad, [], "\n".join(bad))

    def test_every_poi_frame_holds_its_poi(self):
        # the POI plan's 391 cameras, each checked as a POI's shot: nothing against the lens, the
        # trunks before the POI not filling the frame, and the ground and the crowns leaving the
        # view to reach the POI's own ground
        import frame_check as fc
        with open(os.path.join(TOOLS, "capture", "plans", "pois.json"), "r", encoding="utf-8") as f:
            shots = json.load(f)["shots"]
        ground, props = fc.PP.Ground(GEN), fc.Props(GEN)
        bad = []
        for s in shots:
            f = fc.faults(s, ground, props, poi=True)
            if f:
                bad.append("%s: %s" % (s["label"], "; ".join(f)))
        self.assertEqual(bad, [], "\n".join(bad))



class FrameChecks(unittest.TestCase):
    """The frame checks (tools/capture/frame_check.py) on ground and things made up for them."""

    def _world(self, heights=None, discs=()):
        import numpy as np
        import frame_check as fc
        import make_pois_plan as pp
        g = pp.Ground.__new__(pp.Ground)
        g.n, g.spacing, g.off = 256, 4.0, 0.0
        g.origin = [-512.0, -512.0]
        g.h = (np.zeros((256, 256)) if heights is None else heights).astype(np.float32)
        g.water = np.zeros((256, 256), np.uint8)
        props = fc.Props.__new__(fc.Props)
        props.half = 4096.0
        props._things = []
        props._r = {}
        props.around = lambda x, z, rings=1: iter(discs)
        return fc, g, props

    def _shot(self, cam, look):
        return {"pos": [cam[0], 2.2, cam[1]], "look_at": [look[0], 2.0, look[1]], "fov": 60.0}

    def test_open_level_ground_is_clear(self):
        fc, g, props = self._world()
        self.assertEqual(fc.faults(self._shot((0, 0), (0, 400)), g, props), [])

    def test_a_camera_at_the_edge_looking_out_is_a_fault(self):
        fc, g, props = self._world()
        f = fc.faults(self._shot((4086, 0), (4575, 0)), g, props)
        self.assertTrue(any("edge" in x for x in f), f)

    def test_a_ledge_in_front_is_a_fault_by_its_own_extent(self):
        # a cliff ledge 3 m round standing 14.5 m off: its near side is 11.5 m from the lens
        fc, g, props = self._world(discs=[(0.0, 14.5, 3.0, False)])
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("in front of the lens" in x for x in f), f)
        # a camera standing inside a landmark's footprint, its centre behind the lens, is under it
        fc, g, props = self._world(discs=[(0.0, -2.0, 43.5, False)])
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("in front of the lens" in x for x in f), f)
        # the same ledge behind the lens is not in the frame
        fc, g, props = self._world(discs=[(0.0, -14.5, 3.0, False)])
        self.assertEqual(fc.faults(self._shot((0, 0), (0, 400)), g, props), [])

    def test_a_tree_is_as_wide_as_its_crown_where_the_lens_is_level_with_it(self):
        # the yew 7 m in front of hearthvale_ground1: a trunk 0.13 m round, a crown 3.5 m round
        # that hangs to below eye height
        fc, _g, props = self._world()
        yew = props.disc("res://assets/models/trees/hearthvale_yew_a/hearthvale_yew_a.glb", 0.0, 0.0, 7.0, 1.327)
        self.assertGreater(fc.extent_at(yew, 2.2), 2.5)
        # a giant oak at twice its size is its trunk at eye height on its own ground...
        oak = props.disc("res://assets/models/trees/briarwold_giant_oak_c/briarwold_giant_oak_c.glb",
                         0.0, 0.0, 20.0, 2.0)
        self.assertLess(fc.extent_at(oak, 2.2), 6.0)
        # ...and its crown, 41 m round, to a lens on the slope thirty metres above its foot
        self.assertGreater(fc.extent_at(oak, 30.0), 30.0)

    def test_a_camera_on_a_point_of_interest_is_a_fault(self):
        fc, g, props = self._world()
        props._things = [{"name": "the Drowned Nave", "x": 18.0, "z": 0.0, "r": 0.0}]
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("Drowned Nave" in x for x in f), f)

    def test_trunks_filling_the_frame_are_a_fault(self):
        # three giant oaks, 4.8 m round, 25-30 m off across the view
        oaks = [(-14.0, 25.0, 4.8, True), (0.0, 30.0, 4.8, True), (14.0, 25.0, 4.8, True)]
        fc, g, props = self._world(discs=oaks)
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("trunks fill" in x for x in f), f)

    def test_a_wood_level_with_the_lens_is_a_frame_of_leaves(self):
        # briarwold_ground2's: a camera on a slope looking level into the crowns of the wood below
        wood = [(float(x), float(z), 0.2, True, 0.2, 9.0, -20.0, 20.0)
                for x in range(-60, 61, 15) for z in range(30, 200, 15)]
        fc, g, props = self._world(discs=wood)
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("half the frame is stopped" in x for x in f), f)
        # the same wood with its crowns high over the lens is trunks, and the view runs under them
        wood = [(x, z, r, t, tr, cr, 12.0, 30.0) for x, z, r, t, tr, cr, _lo, _hi in wood]
        fc, g, props = self._world(discs=wood)
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertFalse(any("half the frame is stopped" in x for x in f), f)

    def test_a_rise_in_front_cutting_the_view_is_a_fault(self):
        import numpy as np
        h = np.zeros((256, 256))
        h[128 + 15:128 + 18, :] = 6.0          # a bank 60-72 m in front (+z), 6 m high
        fc, g, props = self._world(heights=h)
        f = fc.faults(self._shot((0, 0), (0, 400)), g, props)
        self.assertTrue(any("cuts the line of sight" in x for x in f), f)


class PoiCameras(unittest.TestCase):
    """A point of interest's camera stands where it sees the POI, not inside the hill beside it
    (the Oskel Drip's, on the approach side of a dale at eye height, stood in the dale side)."""

    def _ground(self, heights):
        import numpy as np
        import make_pois_plan as pp
        g = pp.Ground.__new__(pp.Ground)
        g.n = heights.shape[0]
        g.spacing = 4.0
        g.origin = [-g.n * 2.0, -g.n * 2.0]
        g.off = 0.0
        g.h = heights.astype(np.float32)
        g.water = np.zeros(heights.shape, np.uint8)
        return pp, g

    def test_flat_ground_keeps_the_approach(self):
        import numpy as np
        pp, g = self._ground(np.zeros((64, 64)))
        cam = pp.camera_for([0.0, 0.0, 0.0], "cave", 0.0, g, None)
        self.assertAlmostEqual(cam[0], 0.0, delta=0.5)
        self.assertAlmostEqual(cam[2], 34.0, delta=0.5)

    def test_a_camera_behind_a_ridge_moves_to_where_it_sees(self):
        import numpy as np
        h = np.zeros((64, 64))
        h[36:40, :] = 12.0                      # a ridge 16-32 m on the approach side (+z)
        pp, g = self._ground(h)
        pos = [0.0, 0.0, 0.0]
        cam = pp.camera_for(pos, "cave", 0.0, g, None)
        self.assertTrue(g.clear(cam, (0.0, 1.5, 0.0)), "the camera sees the POI: %s" % cam)
        self.assertGreater(cam[1], g.height(cam[0], cam[2]), "and stands above its ground")

    def _trunks(self, discs):
        import make_pois_plan as pp
        t = pp.Trunks.__new__(pp.Trunks)
        t.around = lambda x, z, rings=1: iter(discs)
        return t

    def test_a_thick_trunk_near_the_lens_fills_the_frame(self):
        # the Moss Bed's: a giant oak at twice its size, a trunk 4.8 m round, 13.6 m off and
        # just to the left of the POI, is bark across a third of the picture
        t = self._trunks([(-10.0, 9.2, 4.8)])
        cam, look = (0.0, 1.65, 0.0), (0.0, 1.5, 30.0)
        self.assertGreater(t.in_frame(cam, look), 0.12)
        self.assertAlmostEqual(t.clearance(0.0, 0.0), math.hypot(10.0, 9.2) - 4.8, places=3)
        # the same oak at scale 1 behind the lens is nothing
        t = self._trunks([(0.0, -12.0, 2.4)])
        self.assertEqual(t.in_frame(cam, look), 0.0)

    def test_a_trunk_on_the_line_blocks_it_by_its_own_thickness(self):
        t = self._trunks([(3.0, 15.0, 4.0)])
        self.assertTrue(t.across((0.0, 1.65, 0.0), (0.0, 1.5, 30.0), 20.0))
        t = self._trunks([(6.0, 15.0, 4.0)])
        self.assertFalse(t.across((0.0, 1.65, 0.0), (0.0, 1.5, 30.0), 20.0))


if __name__ == "__main__":
    unittest.main()
