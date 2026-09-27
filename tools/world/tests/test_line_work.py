#!/usr/bin/env python3
"""The build's last line-work pass (worldgen.linework.prune): a run of rail, hedge or wall too short
that meets nothing is taken out, and so is a gate post with no boundary beside it (triage 16:
"random, unconnected fence segments"); and a hedge stands only as a field's boundary near a farm,
off the roads and the approaches to a place, not beside a wall, and with its gateways (triage 17:
"too abundant ... they merely cut off the open world").

    python3 -m pytest tools/world/tests/test_line_work.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import hedges as HG  # noqa: E402
from worldgen import linework as LW  # noqa: E402

RAIL = "res://assets/models/props/hearthvale_fence_post_rail_a/hearthvale_fence_post_rail_a.glb"
HEDGE = "res://assets/models/props/hearthvale_hedge_segment_a/hearthvale_hedge_segment_a.glb"
POST = "res://assets/models/props/hearthvale_gate_post_a/hearthvale_gate_post_a.glb"
TREE = "res://assets/models/trees/hearthvale_oak_a/hearthvale_oak_a.glb"
WALL = "res://assets/models/props/skerrow_drystone_wall_a/skerrow_drystone_wall_a.glb"
## a hamlet 300 m off the test lines: they are its fields, and it is too far off for them to meet it
FARM = [(0.0, 300.0, 20.0)]


def _run(buckets: dict, asset: str, piece_m: float, xs: list, zs: list, key=(0, 0)) -> int:
    """Lays a run as the builders do (hedges.pieces_along); returns how many pieces."""
    got = HG.pieces_along(xs, zs, piece_m, per_stretch=True)
    rows = buckets.setdefault(key, {}).setdefault(asset, [])
    for mx, mz, yaw, sx in got:
        rows.append([round(mx, 2), 10.0, round(mz, 2), round(yaw, 1), 1.0, "#ffffff", 0.0, 0.0, [round(sx, 3), 1.0, 1.0]])
    return len(got)


def _count(buckets: dict, asset: str) -> int:
    return sum(len(by.get(asset, [])) for by in buckets.values())


class LineWork(unittest.TestCase):
    """The runs and the posts, with no gateways cut in the hedges."""

    def setUp(self):
        patch = mock.patch.object(LW, "GATE_LEN_M", 0.0)
        patch.start()
        self.addCleanup(patch.stop)

    def test_a_short_rail_meeting_nothing_goes(self):
        b: dict = {}
        _run(b, RAIL, 2.35, [0.0, 30.0], [0.0, 0.0])
        LW.prune(b, [], [])
        self.assertEqual(_count(b, RAIL), 0)

    def test_a_rail_meeting_a_field_hedge_stays(self):
        b: dict = {}
        n = _run(b, RAIL, 2.35, [0.0, 30.0], [0.0, 0.0])
        # the field's boundary comes in to meet the rail's end, a couple of metres short of it
        _run(b, HEDGE, 2.1, [32.0, 32.0, 90.0], [3.0, 60.0, 60.0])
        LW.prune(b, FARM, [])
        self.assertEqual(_count(b, RAIL), n)

    def test_a_long_rail_stays_alone(self):
        b: dict = {}
        n = _run(b, RAIL, 2.35, [0.0, 120.0], [0.0, 0.0])
        LW.prune(b, [], [])
        self.assertEqual(_count(b, RAIL), n)

    def test_a_short_rail_at_a_settlement_stays(self):
        b: dict = {}
        n = _run(b, RAIL, 2.35, [0.0, 30.0], [0.0, 0.0])
        LW.prune(b, [(60.0, 0.0, 40.0)], [])
        self.assertEqual(_count(b, RAIL), n)

    def test_a_closed_pen_stays(self):
        b: dict = {}
        n = _run(b, RAIL, 2.35, [0.0, 6.0, 6.0, 0.0, 0.0], [0.0, 0.0, 6.0, 6.0, 0.0])
        LW.prune(b, [], [])
        self.assertEqual(_count(b, RAIL), n)

    def test_a_short_hedge_stub_goes_and_a_hedge_field_stays(self):
        b: dict = {}
        _run(b, HEDGE, 2.1, [500.0, 508.0], [0.0, 0.0])
        n = _run(b, HEDGE, 2.1, [0.0, 80.0, 80.0], [0.0, 0.0, 60.0])
        LW.prune(b, FARM, [])
        self.assertEqual(_count(b, HEDGE), n)

    def test_a_gate_post_needs_its_boundary(self):
        b: dict = {}
        _run(b, HEDGE, 2.1, [0.0, 80.0], [0.0, 0.0])
        b[(0, 0)][POST] = [[81.5, 10.0, 0.5, 0.0, 1.0, "#ffffff"], [40.0, 10.0, 40.0, 0.0, 1.0, "#ffffff"]]
        got = LW.prune(b, FARM, [])
        self.assertEqual(got["lone_posts"], 1)
        self.assertEqual(b[(0, 0)][POST], [[81.5, 10.0, 0.5, 0.0, 1.0, "#ffffff"]])

    def test_the_rest_of_the_cell_is_left_alone(self):
        b: dict = {}
        _run(b, RAIL, 2.35, [0.0, 30.0], [0.0, 0.0])
        b[(0, 0)][TREE] = [[5.0, 10.0, 5.0, 0.0, 1.0, "#ffffff"]]
        LW.prune(b, [], [])
        self.assertEqual(b, {(0, 0): {TREE: [[5.0, 10.0, 5.0, 0.0, 1.0, "#ffffff"]]}})

    def test_piece_ends_join_across_their_overlap(self):
        # pieces laid end to end are one run however they turn
        b: dict = {}
        _run(b, HEDGE, 2.1, [0.0, 20.0, 20.0 + 20.0 * math.cos(1.0)], [0.0, 0.0, 20.0 * math.sin(1.0)])
        P = LW._Pieces(b)
        _, label, open_end = LW._runs(P, "hedge")
        self.assertEqual(len(set(label.tolist())), 1)
        self.assertEqual(int(open_end.sum()), 2)


class Hedges(unittest.TestCase):
    """Where a hedge stands at all."""

    def test_a_hedge_far_from_any_farm_goes(self):
        b: dict = {}
        _run(b, HEDGE, 2.1, [0.0, 80.0, 80.0], [0.0, 0.0, 60.0])
        got = LW.prune(b, [(0.0, 900.0, 20.0)], [])
        self.assertEqual(_count(b, HEDGE), 0)
        self.assertGreater(got["hedges"]["far_from_farms"], 0)

    def test_a_hedge_along_a_road_goes_and_one_crossing_to_it_stays(self):
        b: dict = {}
        road = [[-100.0, -8.0], [200.0, -8.0]]
        _run(b, HEDGE, 2.1, [0.0, 80.0], [0.0, 0.0])                   # along it, 8 m off
        _run(b, HEDGE, 2.1, [120.0, 120.0], [-3.0, 60.0], key=(1, 0))   # a boundary coming down to it
        got = LW.prune(b, [(0.0, 900.0, 20.0), (120.0, 440.0, 20.0)], [road])
        self.assertEqual(len(b.get((0, 0), {}).get(HEDGE, [])), 0)
        self.assertGreater(len(b[(1, 0)][HEDGE]), 20)
        self.assertGreater(got["hedges"]["along_roads"], 0)

    def test_no_hedge_on_the_way_into_a_place(self):
        b: dict = {}
        road = [[0.0, 0.0], [0.0, 600.0]]                      # into a hamlet at its far end
        _run(b, HEDGE, 2.1, [40.0, 40.0, 70.0], [300.0, 400.0, 400.0])    # a field's corner beside it
        got = LW.prune(b, [(0.0, 620.0, 20.0)], [road])
        self.assertEqual(_count(b, HEDGE), 0)
        self.assertGreater(got["hedges"]["on_approaches"], 0)

    def test_a_hedge_beside_a_wall_goes(self):
        b: dict = {}
        _run(b, WALL, 2.4, [0.0, 60.0], [0.0, 0.0])
        _run(b, HEDGE, 2.1, [0.0, 60.0], [3.0, 3.0])
        got = LW.prune(b, FARM, [])
        self.assertEqual(_count(b, HEDGE), 0)
        self.assertGreater(got["hedges"]["doubling"], 0)

    def test_a_long_hedge_has_its_gateways(self):
        b: dict = {}
        n = _run(b, HEDGE, 2.1, [0.0, 200.0], [0.0, 0.0])
        LW.prune(b, FARM, [])
        xs = sorted(r[0] for r in b[(0, 0)][HEDGE])
        gaps = [q - p for p, q in zip(xs, xs[1:]) if q - p > 4.0]
        self.assertGreaterEqual(len(gaps), 4)
        self.assertTrue(all(g >= LW.GATE_LEN_M - 2.2 for g in gaps), gaps)
        self.assertGreater(len(xs), n * 0.6)


if __name__ == "__main__":
    unittest.main()
