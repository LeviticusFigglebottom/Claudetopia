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
            k = int(np.argmax(np.maximum(above, below)))
            excess = float(max(above[k], below[k]))
            if excess > tol:
                worst.append("%s: %.1f m %s the ground on both sides at (%.0f, %.0f), allowed %.1f m"
                             % (r["id"], excess, "above" if above[k] >= below[k] else "below",
                                q[k, 0], q[k, 1], tol))
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
