#!/usr/bin/env python3
"""Roads sit on the land, and rivers run under them.

    python3 -m pytest tools/world/tests/test_roads.py

Two kinds of check. The first are quick and synthetic: the profile a road is graded to, the
router that lays it, and the kinds of place it serves. The second march every road and river
of the world that was actually built (`game/world/generated`, the full 4096 build, which is the
only one whose hills are the hills the game has) and skip, saying so, if there is none.

The fault these exist for: `carve_roads` used to limit a road's profile to 11% by *lifting* it,
and the router charged for climbing and nothing for descending, so the road from Kharrow Hold
down to the Mere was routed over the edge of the mountain and then graded 150 m above the
ground on both sides of it -- a knife-edge arete, invisible to every audit and obvious from
the ground. Nothing measured it, so nothing stopped it coming back.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
import tempfile
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
# WICKMERE_GENERATED points the built-world checks at a build somewhere else (a scratch --out)
GEN = os.environ.get("WICKMERE_GENERATED", os.path.join(REPO, "game", "world", "generated"))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import hydro as HY  # noqa: E402
from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

## How far past its own carve the ground beside a road is read, and how much that ground may
## differ from the road. The carve holds a road to `cut_fill_m(width)` of the ground under it
## (2.4 m for a track, 3.6 m for a town road); the ground read here is `half + shoulder + 2` m
## off the centre line, far enough that on a hillside or across the crest of a ridge the land
## itself falls away from the road by a few metres more. So the bar is the carve's own
## tolerance plus `SIDE_SLACK_M`: an embankment or a cutting passes, an arete does not.
SIDE_PAST_CARVE_M = 2.0
SIDE_SLACK_M = 3.0


def settlement_fabric() -> dict:
    """kind -> count, read out of Settlement.FABRIC, the table the exterior builds from."""
    path = os.path.join(REPO, "game", "world", "exteriors", "settlement.gd")
    text = open(path, encoding="utf-8").read()
    body = text[text.index("const FABRIC := {"):]
    body = body[:body.index("\n}")]
    return {k: int(v) for k, v in re.findall(r'"([a-z_]+)":\s*\{"count":\s*(\d+)', body)}


class ProfileTest(unittest.TestCase):
    """`grade_profile`: never out of the band, and at the grade wherever the band allows."""

    def test_a_road_down_a_cliff_stays_on_the_ground(self):
        # 150 m down in 200 m of road: nothing can be graded at 11% here, and the old profile
        # answered that by standing the road on stilts of earth
        s = np.arange(0.0, 600.0, 12.0)
        ground = np.where(s < 200.0, 300.0, np.where(s > 400.0, 150.0, 300.0 - 0.75 * (s - 200.0)))
        tol = RD.cut_fill_m(5.0)
        e = RD.grade_profile(ground, 12.0, tol, pins={0: 300.0, s.size - 1: 150.0})
        self.assertLessEqual(float(np.abs(e - ground).max()), tol + 1e-4)

    def test_where_the_band_allows_the_grade_is_kept(self):
        # a 9% hillside with bumps on it smaller than the band: the road rides over them
        s = np.arange(0.0, 1200.0, 12.0)
        rng = np.random.default_rng(3)
        ground = 0.09 * s + rng.normal(0.0, 1.0, s.size)
        e = RD.grade_profile(ground, 12.0, RD.cut_fill_m(5.0))
        grade = np.abs(np.diff(e)) / 12.0
        self.assertLessEqual(float(grade.max()), RD.MAX_GRADE + 1e-3)
        self.assertLessEqual(float(np.abs(e - ground).max()), RD.cut_fill_m(5.0) + 1e-4)

    def test_pins_hold_and_are_kept_inside_the_band(self):
        s = np.arange(0.0, 240.0, 12.0)
        ground = np.full(s.shape, 50.0)
        e = RD.grade_profile(ground, 12.0, 2.0, pins={0: 51.0, 10: 80.0, s.size - 1: 49.5})
        self.assertAlmostEqual(float(e[0]), 51.0, places=3)
        self.assertAlmostEqual(float(e[-1]), 49.5, places=3)
        self.assertAlmostEqual(float(e[10]), 52.0, places=3, msg="a pin outside the band is pulled in")

    def test_the_tolerance_is_what_the_carve_allows(self):
        # the carve's steepest side slope is 1.5x its mean across the shoulder
        for w in (4.0, 4.5, 5.0, 6.0):
            steepest = 1.5 * RD.cut_fill_m(w) / RD.shoulder_m(w)
            self.assertAlmostEqual(steepest, RD.BATTER, places=6)


class RouterTest(unittest.TestCase):
    """`_route`: grade costs both ways, past the design grade it costs a lot, turns cost."""

    def test_it_zigzags_up_a_steep_slope_instead_of_climbing_it(self):
        n, spacing = 96, 16.0
        z = np.arange(n, dtype=np.float64)[:, None] * spacing
        h = np.broadcast_to(0.35 * z, (n, n)).copy()            # a 35% hillside, rising south
        area = np.ones((n, n))
        start, goal = (8, 48), (48, 48)                         # 640 m apart, 224 m of climb
        for a, b in ((start, goal), (goal, start)):             # and the same either way
            route = RD._route(h, area, spacing, a, b, margin=40, headings=RD._HEADINGS16)
            self.assertGreater(len(route), 2)
            pts = np.array(route, dtype=np.float64) * spacing
            length = float(np.hypot(*np.diff(pts, axis=0).T).sum())
            climb = abs(float(h[b] - h[a]))
            self.assertGreater(length, 1.8 * 640.0, "the road went straight up the hill")
            self.assertLess(climb / length, 0.20)

    def test_descending_costs_as_much_as_climbing(self):
        n, spacing = 64, 16.0
        rng = np.random.default_rng(5)
        h = np.cumsum(np.cumsum(rng.normal(0, 1.0, (n, n)), axis=0), axis=1) * 0.2
        area = np.ones((n, n))
        a, b = (5, 5), (55, 50)
        up = RD._route(h, area, spacing, a, b, margin=20)
        down = RD._route(h, area, spacing, b, a, margin=20)
        costs = RD._edge_costs(h, area, spacing)

        def cost(route):
            total = 0.0
            for (i0, j0), (i1, j1) in zip(route[:-1], route[1:]):
                total += costs[RD._HEADINGS8.index((i1 - i0, j1 - j0))][i0, j0]
            return total

        self.assertAlmostEqual(cost(up), cost(list(reversed(down))), delta=1e-6 + 0.02 * cost(up))


class SettlementKindsTest(unittest.TestCase):
    def test_every_kind_the_exterior_builds_is_a_kind_the_roads_serve(self):
        """`camp` has been in ROAD_KINDS since the first commit; this keeps the lists together.

        A place whose kind has a fabric but no road stands in the country with no way to it,
        and a pad sized by a count the exterior does not use is the wrong size of town.
        """
        fabric = settlement_fabric()
        self.assertIn("camp", fabric)
        self.assertEqual(set(RD.ROAD_KINDS), set(fabric))
        self.assertEqual(RD.FABRIC_COUNT, fabric)
        self.assertEqual(set(RD.ROAD_WIDTH), set(fabric))


class ChannelTest(unittest.TestCase):
    """`keep_channels`: a pad or a road laid across a river is cut back through."""

    def test_a_pad_over_a_river_does_not_dam_it(self):
        grid = Grid(512.0, 128)
        n = grid.n
        X, Z = grid.mesh(np.float64)
        river_d = np.abs(np.broadcast_to(X, (n, n))).astype(np.float32)   # a river along x = 0
        river_w = np.full((n, n), 8.0, dtype=np.float32)
        surf = np.full((n, n), 10.0, dtype=np.float32)
        carved = np.where(river_d <= 4.0, 8.5, 11.0 + 0.1 * river_d).astype(np.float32)
        laid = np.full((n, n), 12.0, dtype=np.float32)                       # a pad over all of it
        out = HY.keep_channels(grid, laid, carved, river_d, river_w, surf)
        self.assertTrue((out[river_d <= 4.0] <= surf[river_d <= 4.0] - 1.0).all())
        # and where a road crosses, it is a ford you can wade
        road_d = np.abs(np.broadcast_to(Z, (n, n))).astype(np.float32)
        road_w = np.full((n, n), 5.0, dtype=np.float32)
        out = HY.keep_channels(grid, laid, carved, river_d, river_w, surf, road_d, road_w)
        ford = (river_d <= 4.0) & (road_d <= 2.5)
        self.assertTrue(np.allclose(out[ford], 10.0 - HY.FORD_DEPTH_M))
        self.assertTrue((out[river_d > 40.0] == laid[river_d > 40.0]).all(), "far from the river, untouched")


class CampPadTest(unittest.TestCase):
    def test_a_camp_pad_holds_its_camp_and_no_more(self):
        """poi_builders.camp reaches 12.7 m from its fire (a kiln's log pile); the pad's level core
        is 0.7 of its radius. The 30 m pad a camp had was the size of a hamlet's."""
        place = {"id": "core:poi/clanless_camp", "kind": "camp"}
        r = RD.pad_radius(place)
        self.assertEqual(r, RD.CAMP_PAD_M)
        self.assertGreaterEqual(RD.pad_level_radius(place), 12.7 + 1.0)
        self.assertLess(r, RD.pad_radius({"id": "core:place/x", "kind": "hamlet"}))

    def test_a_camp_that_is_a_place_keeps_its_ground(self):
        """Pilgrim's Ash is a camp the settlement builder raises, with a chapter-house door 26 m
        out (door_plan.json); it keeps the pad it had."""
        self.assertEqual(RD.pad_radius({"id": "core:place/pilgrims_ash", "kind": "camp"}), 30.0)


class PadLevelRadiusTest(unittest.TestCase):
    """A pad is level out to `pad_level_radius` (pois.json `radius_level_m`), not past it, and its
    skirt ends at `pad_reach`. `radius_flat_m` (`pad_radius`) is what it was: the game is tuned to
    it. Grandfather Hollow is level to 72 m, for a ring of houses outside its street."""

    def test_level_to_the_level_radius_and_left_alone_past_the_skirt(self):
        from worldgen.grid import Grid

        grid = Grid(1024.0, 512)
        X, Z = grid.mesh()
        H0 = np.broadcast_to(100.0 + 0.3 * X + 0.1 * Z, (grid.n, grid.n)).astype(np.float32).copy()
        places = [{"id": "core:place/a_town", "kind": "town", "position": [-200.0, 0.0]},
                  {"id": "core:poi/a_camp", "kind": "camp", "position": [200.0, 150.0]},
                  {"id": "core:poi/a_ruin", "kind": "ruins", "position": [250.0, 250.0]},
                  {"id": "core:place/grandfather_hollow", "kind": "town", "position": [150.0, -250.0]}]
        H, _mask, levels = RD.apply_pads(grid, H0.copy(), places)
        for p in places:
            r = RD.pad_level_radius(p)
            d = np.hypot(X - p["position"][0], Z - p["position"][1])
            self.assertLess(float(np.abs(H[d <= r] - levels[p["id"]]).max()), 1e-3,
                            "%s is not level to its %.1f m" % (p["id"], r))
            self.assertGreater(float(np.abs(H[(d > r + 4.0) & (d < r + 8.0)] - levels[p["id"]]).max()), 0.05,
                               "%s is level past its %.1f m" % (p["id"], r))
            reach = RD.pad_reach(p)
            far = (d > reach + grid.spacing) & (d < reach + 20.0)
            self.assertTrue(np.array_equal(H[far], H0[far]), "%s's skirt reaches past %.1f m" % (p["id"], reach))
        self.assertEqual(RD.pad_level_radius(places[3]), 72.0)

    def test_radius_flat_m_is_what_it_was(self):
        self.assertEqual(RD.pad_radius({"id": "core:poi/a_ruin", "kind": "ruins"}), 25.0)
        self.assertEqual(RD.pad_radius({"id": "core:poi/a_camp", "kind": "camp"}), 22.0)
        self.assertAlmostEqual(RD.pad_radius({"id": "core:place/grandfather_hollow", "kind": "town"}),
                               20.0 + 7.5 * math.sqrt(34), places=6)
        # a settlement is level to its whole radius, where its houses go; a point of interest
        # keeps its level core of 0.7
        for place in ({"id": "core:place/a_town", "kind": "town"}, {"id": "core:place/a_hamlet", "kind": "hamlet"},
                      {"id": "core:place/pilgrims_ash", "kind": "camp"}):
            self.assertEqual(RD.pad_level_radius(place), RD.pad_radius(place), place["id"])
        for place in ({"id": "core:poi/a_ruin", "kind": "ruins"}, {"id": "core:poi/a_camp", "kind": "camp"}):
            self.assertAlmostEqual(RD.pad_level_radius(place), 0.7 * RD.pad_radius(place), places=6)


class RingTownTest(unittest.TestCase):
    """Grandfather Hollow's streets: a closed ring 48 m out round the tree, the four roads stopped on
    its outer edge, and a spur in to the door at 304 degrees."""

    PLACE = {"id": "core:place/grandfather_hollow", "kind": "town", "position": [2750.0, 450.0]}

    def _roads(self):
        cx, cz = self.PLACE["position"]
        roads = []
        for n, deg in enumerate((304.0, 263.0, 110.0, 44.0)):
            b = math.radians(deg)
            t = np.arange(0.0, 400.0 + 1e-9, 12.0)
            pts = np.stack([cx + t * math.sin(b), cz + t * math.cos(b)], axis=1)
            if n % 2 == 0:
                pts = pts[::-1]                              # ends at the town
            e = np.linspace(180.0, 200.0, len(pts))
            roads.append(RD.Road(id="core:road/r%d" % n, points=pts, width=5.0, elevation=e, ground=e.copy()))
        return roads

    def test_the_ring_the_spur_and_the_roads_ending_on_the_ring(self):
        cx, cz = self.PLACE["position"]
        roads = self._roads()
        out = RD.add_streets(roads, [self.PLACE], {self.PLACE["id"]: 181.2})
        by_id = {r.id: r for r in out}
        self.assertNotIn("core:road/grandfather_hollow_street_cross", by_id)
        ring = by_id["core:road/grandfather_hollow_street"]
        self.assertTrue(np.allclose(ring.points[0], ring.points[-1]), "the ring is not closed")
        self.assertTrue(np.allclose(np.hypot(ring.points[:, 0] - cx, ring.points[:, 1] - cz), 48.0))
        self.assertEqual(ring.width, 6.0)
        self.assertTrue(np.allclose(ring.elevation, 181.2))
        door = by_id["core:road/grandfather_hollow_door"]
        self.assertEqual(door.width, 4.0)
        r_door = np.hypot(door.points[:, 0] - cx, door.points[:, 1] - cz)
        self.assertAlmostEqual(float(r_door[0]), 48.0, places=6)
        self.assertAlmostEqual(float(r_door[-1]), 41.0, places=6)
        bearing = math.degrees(math.atan2(door.points[-1, 0] - cx, door.points[-1, 1] - cz)) % 360.0
        self.assertAlmostEqual(bearing, 304.0, places=6)
        # roads.json keeps more than four points of it: the game reads fewer as a stub
        # (test_world_data.test_rivers_and_roads_are_sane); built with four, the batch2 world failed it
        from worldgen import output as OUT
        for r in (door, ring):
            self.assertGreater(len(OUT._road_keep(np.asarray(r.points))), 4, r.id)
        for n in range(4):
            r = by_id["core:road/r%d" % n]
            end = r.points[-1] if n % 2 == 0 else r.points[0]
            other = r.points[0] if n % 2 == 0 else r.points[-1]
            self.assertAlmostEqual(float(np.hypot(end[0] - cx, end[1] - cz)), 51.0, places=6)
            self.assertGreater(float(np.hypot(other[0] - cx, other[1] - cz)), 390.0)
            self.assertGreater(float(np.hypot(r.points[:, 0] - cx, r.points[:, 1] - cz).min()), 51.0 - 1e-6)
            self.assertEqual(len(r.points), len(r.elevation))
            self.assertEqual(len(r.points), len(r.ground))


class RingTownCurlTest(unittest.TestCase):
    """A road routed to the tree that comes onto the level ground on the far side does not curl
    round the ring through the houses: from the level ground it runs straight in."""

    def test_straight_in_from_the_level_ground(self):
        place = RingTownTest.PLACE
        cx, cz = place["position"]
        a = np.radians(np.linspace(0.0, 270.0, 60))
        arc = np.stack([cx + 62.0 * np.sin(a), cz + 62.0 * np.cos(a)], axis=1)
        approach = np.stack([np.full(20, cx), cz + np.linspace(300.0, 70.0, 20)], axis=1)
        inward = np.stack([cx - np.linspace(55.0, 0.0, 12), np.full(12, cz)], axis=1)
        pts = np.concatenate([approach, arc, inward])
        e = np.full(len(pts), 182.0)
        road = RD.Road(id="core:road/curl", points=pts, width=4.0, elevation=e, ground=e.copy())
        out = {r.id: r for r in RD.add_streets([road], [place], {place["id"]: 182.0})}
        r = out["core:road/curl"]
        d = np.hypot(r.points[:, 0] - cx, r.points[:, 1] - cz)
        self.assertAlmostEqual(float(d[-1]), 51.0, places=6)
        inside = d < RD.RING_TOWNS[place["id"]]["flat_m"] - 1e-6
        bearing = np.degrees(np.arctan2(r.points[inside, 0] - cx, r.points[inside, 1] - cz))
        self.assertLess(float(np.ptp(bearing)), 1e-6, "the road curls round inside the level ground")
        self.assertEqual(len(r.points), len(r.elevation))


class StreetsTest(unittest.TestCase):
    """`add_streets`: a through street along the most opposed approaches, a cross street where
    a third road comes in across it."""

    @staticmethod
    def _town_with(bearings):
        place = {"id": "core:place/testford", "kind": "village", "position": [0.0, 0.0]}
        roads = []
        for n, deg in enumerate(bearings):
            a = math.radians(deg)
            t = np.arange(0.0, 400.0 + 1e-9, 4.0)[::-1]
            pts = np.stack([t * math.cos(a), t * math.sin(a)], axis=1)   # ends at the centre
            roads.append(RD.Road(id="core:road/r%d" % n, points=pts, width=5.0,
                                 elevation=np.zeros(len(pts), dtype=np.float32)))
        out = RD.add_streets(roads, [place], {"core:place/testford": 10.0})
        return {r.id.split("/")[-1] for r in out[len(roads):]}

    def test_pilgrims_ash_keeps_its_crossing(self):
        """The bearings Pilgrim's Ash's roads leave it on, measured on the default build: the
        through street from -10 to 156 degrees, and the side road at -74 (64 and 130 degrees
        off its legs). Under the old threshold of 0.55 it had no cross street."""
        self.assertEqual(self._town_with([-10.0, 156.0, -74.0]), {"testford_street", "testford_street_cross"})

    def test_a_road_along_the_street_is_not_a_crossing(self):
        self.assertEqual(self._town_with([0.0, 180.0, 20.0]), {"testford_street"})


class WrittenLineTest(unittest.TestCase):
    """roads.json is the laid line thinned to the spacing the game reads, not a new line."""

    def test_the_written_points_are_laid_points_with_both_ends(self):
        from worldgen import output as OUT

        # a line laid every 4 m along its length, bending the way a road does
        turn = np.arange(100) * 4.0 / 60.0
        steps = 4.0 * np.stack([np.cos(turn), np.sin(turn)], axis=1)
        laid = np.vstack([[0.0, 0.0], np.cumsum(steps, axis=0)])
        keep = OUT._road_keep(laid)
        self.assertEqual(int(keep[0]), 0)
        self.assertEqual(int(keep[-1]), len(laid) - 1)
        self.assertTrue((np.diff(keep) > 0).all())
        gaps = np.linalg.norm(np.diff(laid[keep], axis=0), axis=1)
        self.assertLessEqual(float(gaps.max()), OUT.ROAD_OUT_STEP_M + 0.5)
        # a short street is still a line of points (the game's own test wants more than four)
        for n in (6, 9, 20):
            self.assertGreaterEqual(len(OUT._road_keep(laid[:n])), OUT.ROAD_OUT_MIN_POINTS)


class SpurTest(unittest.TestCase):
    """A road does not go out to a via point on a knoll and come back down the same line.

    On the final build of the drawn atlas 25 roads did, and the land under five of them stood
    metres off their grade where the two legs lay side by side (test_the_carved_land_is_the_graded_road)."""

    def test_an_out_and_back_spur_is_cut(self):
        out = np.stack([np.zeros(30), np.arange(30) * 4.0], axis=1)            # north 116 m
        up = np.stack([np.full(20, 6.0), 116.0 - np.arange(20) * 4.0], axis=1)  # back south beside it
        on = np.stack([np.linspace(6.0, 206.0, 40), np.full(40, 40.0)], axis=1)  # then east
        pts = np.vstack([out, up, on])
        ground = np.where(np.arange(pts.shape[0]) < 10, 10.0, 10.0)
        ground = ground + np.concatenate([np.clip(out[:, 1] - 40.0, 0, None) * 0.3,
                                          np.clip(up[:, 1] - 40.0, 0, None) * 0.3, np.zeros(40)])
        cut = RD.cut_spurs(pts, ground)
        self.assertLess(float(cut[:, 1].max()), 60.0, "the road still goes up the knoll")
        self.assertTrue(np.array_equal(cut[0], pts[0]) and np.array_equal(cut[-1], pts[-1]))

    def test_a_switchback_is_not_a_spur(self):
        # two legs of a zigzag lie side by side, but at different heights: both are kept
        a = np.stack([np.arange(30) * 4.0, np.zeros(30)], axis=1)
        b = np.stack([116.0 - np.arange(30) * 4.0, np.full(30, 8.0)], axis=1)
        pts = np.vstack([a, b])
        ground = np.arange(pts.shape[0]) * 0.4                                  # climbing 0.1
        self.assertEqual(RD.cut_spurs(pts, ground).shape[0], pts.shape[0])


class LandmarkFootTest(unittest.TestCase):
    """A road to a landmark that stands solid on its place stops at its foot. The Sunken Choir's
    head colossus stands on the Choir's own position, 27 m across at the foot, and the Stair Path
    the start's waystones walk ran on into it (test_the_start)."""

    def test_a_road_stops_on_the_circle_round_what_it_leads_to(self):
        laid = np.stack([np.linspace(0.0, 100.0, 26), np.zeros(26)], axis=1)
        into = RD.stop_short(laid, (100.0, 0.0), 16.5, at_end=True)
        self.assertAlmostEqual(float(np.hypot(*(into[-1] - [100.0, 0.0]))), 16.5, places=6)
        self.assertTrue(np.array_equal(into[0], laid[0]))
        away = RD.stop_short(laid, (0.0, 0.0), 16.5, at_end=False)
        self.assertAlmostEqual(float(np.hypot(*away[0])), 16.5, places=6)
        self.assertTrue(np.array_equal(away[-1], laid[-1]))
        # a road that never comes near is left as it was
        self.assertTrue(np.array_equal(RD.stop_short(laid, (500.0, 0.0), 16.5), laid))

    def test_the_choir_s_colossus_is_solid_and_the_road_stops_clear_of_it(self):
        import build_world as B

        solid = B.solid_at_places([{"id": "core:place/sunken_choir", "position": [-210, 3240]}], REPO)
        foot = solid.get("core:place/sunken_choir", 0.0)
        # the colossus reaches 13.5 m across the ground; the road stops a body's width and more
        # beyond that, and inside the 45 m that counts as reaching the Choir
        self.assertGreater(foot, 13.5 + 1.0)
        self.assertLess(foot, 45.0)


class StalePadsTest(unittest.TestCase):
    """A staged build may not reuse a heightmap whose pads are somewhere else."""

    def test_a_moved_poi_refuses_a_staged_build(self):
        import build_world as BW

        places = [{"id": "core:place/a", "kind": "village", "position": [0, 0]}]
        pois = [{"id": "core:poi/b", "kind": "tower", "position": [300, 40]}]
        before = BW.pad_fingerprint(BW.pad_targets_for(places, pois))
        moved = [{"id": "core:poi/b", "kind": "tower", "position": [320, 40]}]
        after = BW.pad_fingerprint(BW.pad_targets_for(places, moved))
        self.assertNotEqual(before, after)
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "world_manifest.json"), "w", encoding="utf-8") as f:
                json.dump({"pad_fingerprint": before}, f)
            BW.refuse_stale_pads(tmp, before)                   # the same pads: fine
            with self.assertRaises(SystemExit):
                BW.refuse_stale_pads(tmp, after)

    def test_the_staged_build_itself_refuses(self):
        import build_world as BW

        with tempfile.TemporaryDirectory() as tmp:
            n = 256
            np.zeros((n, n), dtype="<f4").tofile(os.path.join(tmp, "heights.r32"))
            with open(os.path.join(tmp, "world_manifest.json"), "w", encoding="utf-8") as f:
                json.dump({"pad_fingerprint": "00000000"}, f)
            args = SimpleNamespace(size=n, seed=None, out=tmp, only="cells")
            with self.assertRaises(SystemExit) as caught:
                BW.build(args)
            self.assertIn("moved", str(caught.exception))


def _resample(points, step):
    p = np.asarray(points, dtype=np.float64)
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t = np.append(np.arange(0.0, s[-1], step), s[-1])
    return np.stack([np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])], axis=1)


class BuiltWorldTest(unittest.TestCase):
    """Every road and river of the world that was actually built."""

    @classmethod
    def setUpClass(cls) -> None:
        if not os.path.exists(os.path.join(GEN, "heights.r32")):
            raise unittest.SkipTest("no built world in game/world/generated; run ./run.sh world")
        with open(os.path.join(GEN, "world_manifest.json"), "r", encoding="utf-8") as f:
            man = json.load(f)
        cls.n = int(man["grid"])
        cls.spacing = float(man["spacing_m"])
        cls.ox, cls.oz = (float(v) for v in man["origin"])
        cls.H = np.fromfile(os.path.join(GEN, "heights.r32"), dtype="<f4").reshape(cls.n, cls.n)
        cls.W = np.fromfile(os.path.join(GEN, "water_mask.u8"), dtype=np.uint8).reshape(cls.n, cls.n)
        rt = man["runtime"]
        cls.g = int(rt["grid"])
        cls.WL = np.fromfile(os.path.join(GEN, rt["water_level"]), dtype="<f4").reshape(cls.g, cls.g)
        with open(os.path.join(GEN, "roads.json"), "r", encoding="utf-8") as f:
            cls.roads = json.load(f)
        with open(os.path.join(GEN, "rivers.json"), "r", encoding="utf-8") as f:
            cls.rivers = json.load(f)
        path = os.path.join(GEN, "road_profiles.json")
        cls.profiles = {}
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                cls.profiles = {p["id"]: p for p in json.load(f)}
        path = os.path.join(GEN, "pois.json")
        cls.pads = []
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                cls.pads = [(float(e["pos"][0]), float(e["pos"][2]), float(e.get("radius_flat_m", 25.0)))
                            for e in json.load(f)]

    def _bilinear(self, A, x, z, spacing, n):
        fj = np.clip((x - self.ox) / spacing, 0, n - 1.001)
        fi = np.clip((z - self.oz) / spacing, 0, n - 1.001)
        j0 = np.floor(fj).astype(np.int64)
        i0 = np.floor(fi).astype(np.int64)
        tj, ti = fj - j0, fi - i0
        a = A[i0, j0] * (1 - tj) + A[i0, j0 + 1] * tj
        b = A[i0 + 1, j0] * (1 - tj) + A[i0 + 1, j0 + 1] * tj
        return a * (1 - ti) + b * ti

    def _surface(self, x, z):
        """The ground, or the water standing on it: what you would see standing there."""
        h = self._bilinear(self.H, x, z, self.spacing, self.n)
        j = np.clip(np.rint((x - self.ox) / self.spacing).astype(np.int64), 0, self.n - 1)
        i = np.clip(np.rint((z - self.oz) / self.spacing).astype(np.int64), 0, self.n - 1)
        wet = self.W[i, j] > 0
        level = self._bilinear(self.WL, x, z, (self.n * self.spacing) / self.g, self.g)
        return np.where(wet, np.maximum(h, level), h)

    def test_no_road_stands_above_or_below_the_ground_either_side_of_it(self):
        """The arete, measured from outside: the land beside every road, past its carve.

        A road may stand above the ground on both sides of it by as much as the ground under it
        already did -- a road along a spur between two gorges is on the spur -- plus what its
        carve may add, `cut_fill_m(width)`, plus `SIDE_SLACK_M` for the land's own curvature
        across the shoulder. The same the other way for a road down a gully. On the build this
        pass started from (which wrote no record, so nothing is discounted) it reads the road
        from Gullhithe to Kharrow Hold 150.1 m above both sides of it, against 6.6 m allowed.
        """
        worst = []
        for r in self.roads:
            q = _resample(r["points"], 4.0)
            if q.shape[0] < 3:
                continue
            d = np.gradient(q, axis=0)
            d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
            nx, nz = -d[:, 1], d[:, 0]
            w = float(r["width_m"])
            off = 0.5 * w + RD.shoulder_m(w) + SIDE_PAST_CARVE_M
            tol = RD.cut_fill_m(w) + SIDE_SLACK_M
            centre = self._surface(q[:, 0], q[:, 1])
            left = self._surface(q[:, 0] - nx * off, q[:, 1] - nz * off)
            right = self._surface(q[:, 0] + nx * off, q[:, 1] + nz * off)
            above = centre - np.maximum(left, right)          # an embankment standing proud
            below = np.minimum(left, right) - centre          # a cutting sunk into the land
            # the land the road was laid on, where the builder recorded it: a spur or a gully
            # the road runs along is the land's relief, not the road's
            p = self.profiles.get(r["id"])
            if p is not None and len(p["ground_m"]) == len(r["points"]):
                pts = np.asarray(r["points"], dtype=np.float64)
                seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
                s_pts = np.concatenate([[0.0], np.cumsum(seg)])
                s_q = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(q, axis=0), axis=1))])
                ground = np.interp(s_q, s_pts, np.asarray(p["ground_m"], dtype=np.float64))
                spur = np.maximum(ground - np.maximum(left, right), 0.0)
                gully = np.maximum(np.minimum(left, right) - ground, 0.0)
            else:
                # No record (a world built before there was one). The carved road is not the
                # land it was laid on -- taking it for that would excuse every arete -- so
                # nothing is discounted.
                spur = gully = np.zeros_like(centre)
            excess_up = above - spur
            excess_down = below - gully
            k = int(np.argmax(np.maximum(excess_up, excess_down)))
            excess = float(max(excess_up[k], excess_down[k]))
            if excess > tol:
                up = excess_up[k] >= excess_down[k]
                worst.append("%s: %.1f m %s the ground on both sides at (%.0f, %.0f), %.1f m more "
                             "than the land under it, allowed %.1f m"
                             % (r["id"], float(above[k] if up else below[k]), "above" if up else "below",
                                q[k, 0], q[k, 1], excess, tol))
        self.assertEqual(worst, [], "\n".join(worst))

    def test_every_road_is_graded_within_its_carve_of_the_ground(self):
        """The builder's own record of each road: its level, and the land it was graded against.

        Once a road is carved the land under it is gone from heights.r32, so the builder keeps
        both in `road_profiles.json`, and this is where the stated tolerance is held exactly: a
        road stands no more than `cut_fill_m(width)` above or below the ground under it.
        """
        if not self.profiles:
            self.skipTest("this build wrote no road_profiles.json")
        over = []
        for rid, p in self.profiles.items():
            e = np.asarray(p["elevation_m"], dtype=np.float64)
            g = np.asarray(p["ground_m"], dtype=np.float64)
            tol = RD.cut_fill_m(float(p["width_m"])) + 0.02        # the file rounds to a centimetre
            dev = np.abs(e - g)
            if dev.size and float(dev.max()) > tol:
                k = int(np.argmax(dev))
                over.append("%s: %.2f m off its ground at point %d, allowed %.2f m" % (rid, dev[k], k, tol))
        self.assertEqual(over, [], "\n".join(over))
        self.assertEqual(set(self.profiles), {r["id"] for r in self.roads})

    def test_the_carved_land_is_the_graded_road(self):
        """And heights.r32 carries that level where the road runs, so the record is the road.

        Away from the places (whose pads are flattened again after the roads) and the rivers
        (which are cut back through a road as a ford), the land under a road's centre line is
        the level it was graded to, give or take the crown and where another road crosses it.
        """
        if not self.profiles:
            self.skipTest("this build wrote no road_profiles.json")
        river_pts = np.concatenate([_resample(rv["points"], 4.0) for rv in self.rivers]) if self.rivers else None
        river_w = max((float(rv.get("width_to_m", rv["width_m"])) for rv in self.rivers), default=0.0)
        worst = []
        for r in self.roads:
            p = self.profiles[r["id"]]
            pts = np.asarray(r["points"], dtype=np.float64)
            e = np.asarray(p["elevation_m"], dtype=np.float64)
            keep = np.ones(pts.shape[0], dtype=bool)
            for x, z, radius in self.pads:
                keep &= np.hypot(pts[:, 0] - x, pts[:, 1] - z) > 1.7 * radius
            if river_pts is not None:
                for k in np.flatnonzero(keep):
                    if float(np.hypot(river_pts[:, 0] - pts[k, 0], river_pts[:, 1] - pts[k, 1]).min()) < river_w * 2.6 + 14.0:
                        keep[k] = False
            if not keep.any():
                continue
            h = self._bilinear(self.H, pts[keep, 0], pts[keep, 1], self.spacing, self.n)
            dev = np.abs(h - e[keep])
            tol = RD.cut_fill_m(float(r["width_m"]))
            if float(dev.max()) > tol:
                k = int(np.argmax(dev))
                worst.append("%s: the land is %.2f m off the graded road at (%.0f, %.0f), allowed %.2f"
                             % (r["id"], dev[k], pts[keep][k, 0], pts[keep][k, 1], tol))
        self.assertEqual(worst, [], "\n".join(worst))

    def test_no_river_is_dammed(self):
        """Along every river's centre line there is water, wherever a road or a pad crosses it."""
        dry_runs = []
        for rv in self.rivers:
            q = _resample(rv["points"], self.spacing)
            j = np.clip(np.rint((q[:, 0] - self.ox) / self.spacing).astype(np.int64), 0, self.n - 1)
            i = np.clip(np.rint((q[:, 1] - self.oz) / self.spacing).astype(np.int64), 0, self.n - 1)
            wet = self.W[i, j] > 0
            run = 0
            for k, v in enumerate(wet):
                run = 0 if v else run + 1
                if run * self.spacing > 6.0:
                    dry_runs.append("%s dry at (%.0f, %.0f)" % (rv["id"], q[k, 0], q[k, 1]))
                    run = -10 ** 9          # one report per run
        self.assertEqual(dry_runs, [], "\n".join(dry_runs))


if __name__ == "__main__":
    unittest.main()
