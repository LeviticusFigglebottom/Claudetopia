#!/usr/bin/env python3
"""The roads are signed: a fingerpost at every junction out in the country whose arms name real
places down the roads they point along, and a stone naming each settlement where a road comes in.

    python3 -m unittest tools.world.tests.test_signposts

Checked against the tracked world's built roads (game/world/generated/roads.json) and the content
packs; skipped with a reason where the world has not been built.
"""
from __future__ import annotations

import json
import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "atlas"))
sys.path.insert(0, os.path.dirname(HERE))

import signposts as S  # noqa: E402

def near_town(m: dict, x: float, z: float, spare: float) -> bool:
    return any(p["settlement"] and math.hypot(p["at"][0] - x, p["at"][1] - z) < p["pad"] + S.SETTLEMENT_SPARE_M + spare
               for p in m["places"])


HAVE_WORLD = os.path.exists(os.path.join(S.GEN, "roads.json")) and os.path.exists(os.path.join(S.GEN, "pois.json"))


class Miles(unittest.TestCase):
    def test_a_distance_is_cut_in_quarter_miles(self):
        self.assertEqual(S.miles(50.0), "¼", "never less than a quarter")
        self.assertEqual(S.miles(800.0), "½")
        self.assertEqual(S.miles(1609.0), "1")
        self.assertEqual(S.miles(2000.0), "1¼")
        self.assertEqual(S.miles(3620.0), "2¼")


class TheScenesExist(unittest.TestCase):
    def test_every_scene_the_signpost_data_names_exists(self):
        # a scenes entry for a file that is not there is skipped by the streamer, with a warning,
        # at every one of the town stones
        with open(S.OUT, "r", encoding="utf-8") as f:
            data = json.load(f)
        for path in {data.get("town_stone_scene", "")} | {S.TOWN_STONE_SCENE}:
            self.assertTrue(path.startswith("res://"), path)
            self.assertTrue(os.path.exists(os.path.join(S.REPO, "game", path[len("res://"):])),
                            "the signpost data names %s, which is not in game/" % path)


class TheBuildStandsThem(unittest.TestCase):
    """worldgen.roadside stands a signpost row at each fingerpost of signposts.json, and a town
    stone scene at each town stone, on a small made-up world."""

    def test_a_fingerpost_and_a_town_stone_are_stood(self):
        from types import SimpleNamespace
        from worldgen import cells as CELLS
        from worldgen import roadside as RS
        from worldgen.grid import Grid
        g = Grid(1024.0, 256, 256.0)
        n = g.n
        X, Z = g.mesh(np.float64)
        X = np.broadcast_to(X, (n, n))
        H = np.full((n, n), 40.0, dtype=np.float32)
        owner = np.zeros((n, n), dtype=np.uint8)
        slope = np.full((n, n), 0.02, dtype=np.float32)
        water = np.zeros((n, n), dtype=np.uint8)
        pad = np.zeros((n, n), dtype=bool)
        regions = [SimpleNamespace(index=0, shape="downs", art_short="hearthvale", palette=["#90a060"])]
        roads = [SimpleNamespace(id="test:road/a", points=np.array([[-400.0, 0.0], [400.0, 0.0]]), width=4.0)]
        data = {"town_stone_scene": "res://world/pois/town_stone.tscn",
                "fingerposts": [{"at": [12.0, 9.0]}],
                "town_stones": [{"at": [-200.0, 5.0], "yaw": 90.0, "place": "core:place/testby"}]}
        index = CELLS.asset_index(S.REPO)
        beside = RS.place(g, H, owner, slope, water, pad, np.full((n, n), 1e6, np.float32), regions, roads, [],
                          index, 3, signposts=data)
        posts = [r for by in beside.values() for a, rows in by.items() if "signpost" in a for r in rows]
        self.assertTrue(any(abs(r[0] - 12.0) < 0.01 and abs(r[2] - 9.0) < 0.01 for r in posts), "no signpost at the fingerpost")
        path = os.path.join(os.environ.get("TMPDIR", "/tmp"), "signposts_test_%d.json" % os.getpid())
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        try:
            stones = RS.town_stones(g, H, path)
        finally:
            os.unlink(path)
        self.assertEqual(len(stones), 1)
        self.assertEqual(stones[0]["props"]["place_id"], "core:place/testby")
        self.assertAlmostEqual(stones[0]["pos"][1], 40.0, places=1)


@unittest.skipUnless(HAVE_WORLD, "the world has not been built (./run.sh world)")
class TheRoadsAreSigned(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.m = S.load()
        with open(S.OUT, "r", encoding="utf-8") as f:
            cls.data = json.load(f)
        cls.posts = cls.data["fingerposts"]
        cls.stones = cls.data["town_stones"]
        cls.roads = {r["id"]: r for r in cls.m["roads"]}
        cls.by_id = {p["id"]: p for p in cls.m["places"]}

    def test_the_file_is_the_world_s(self):
        # a rebuilt road network is signed again by running signposts.py
        fresh = S.build()
        self.assertEqual(fresh["fingerposts"], self.posts, "signposts.json is not the world's: run tools/world/atlas/signposts.py")
        self.assertEqual(fresh["town_stones"], self.stones, "signposts.json is not the world's: run tools/world/atlas/signposts.py")

    def test_every_parting_of_two_roads_out_in_the_country_has_a_fingerpost(self):
        # Found here a second way, not the file's: where two roads within 5 m of each other step
        # apart and, within 80 m further along, are more than 20 m apart, they have parted. Unless that is in a
        # settlement, or every way out of it ends where you stand, a fingerpost stands within 100 m.
        missing = []
        ids = list(self.roads)
        for i, a in enumerate(ids):
            A = self.roads[a]["pts"]
            for b in ids[i + 1:]:
                B = self.roads[b]["pts"]
                d = np.hypot(A[:, None, 0] - B[None, :, 0], A[:, None, 1] - B[None, :, 1]).min(axis=1)
                step = int(80.0 / S.STEP_M)
                for k in range(1, len(A) - 1):
                    if d[k] >= 5.0:
                        continue
                    # the last point they share before one goes its own way, either way along
                    ahead = d[k + 1:k + 1 + step]
                    behind = d[max(0, k - step):k][::-1]
                    parts = (d[k + 1] >= 5.0 and ahead.max() > 20.0) or (d[k - 1] >= 5.0 and behind.max() > 20.0)
                    if not parts:
                        continue
                    x, z = float(A[k][0]), float(A[k][1])
                    # (the two ways of finding a parting place it up to 25 m apart along the road, so
                    # one on a town's outskirts' edge is the town's by either)
                    if near_town(self.m, x, z, 25.0) or len(S.destinations(self.m, (x, z))) < 2:
                        continue
                    if not any(math.hypot(p["at"][0] - x, p["at"][1] - z) < 100.0 for p in self.posts):
                        missing.append("%s / %s at (%.0f, %.0f)" % (a.split("/")[-1], b.split("/")[-1], x, z))
        # one line a place is enough to read
        seen, report = set(), []
        for line in missing:
            key = line.split(" at ")[1]
            if key not in seen:
                seen.add(key)
                report.append(line)
        self.maxDiff = None
        self.assertEqual(report[:40], [], "%d partings with no fingerpost" % len(report))

    def test_every_arm_names_a_real_place_down_the_road_it_points_along(self):
        bad = []
        for p in self.posts:
            x, z = p["at"]
            self.assertGreaterEqual(len(p["arms"]), 2, "a fingerpost at (%.0f, %.0f) with one way" % (x, z))
            for arm in p["arms"]:
                place = self.by_id.get(arm["place"])
                road = self.roads.get(arm["road"])
                if place is None or road is None:
                    bad.append("%s: no such place or road" % arm["place"])
                    continue
                P = road["pts"]
                dist = np.hypot(P[:, 0] - x, P[:, 1] - z)
                k = int(np.argmin(dist))
                if dist[k] > S.REACH_M:
                    bad.append("%s: its road does not pass the post" % arm["name"])
                    continue
                # the named place is at one end of the road, and the arm's miles are the road's run
                runs = []
                for sign, end in ((1, P[-1]), (-1, P[0])):
                    if math.hypot(end[0] - place["at"][0], end[1] - place["at"][1]) < S.END_M:
                        runs.append(S.run_m(P, k, sign))
                if not runs:
                    bad.append("%s: not at either end of %s" % (arm["name"], arm["road"]))
                elif min(abs(r - arm["metres"]) for r in runs) > 60.0:
                    bad.append("%s: %d m on the arm, %d m along the road" % (arm["name"], arm["metres"], min(runs)))
                elif arm["miles"] != S.miles(arm["metres"]):
                    bad.append("%s: %s is not %d m" % (arm["name"], arm["miles"], arm["metres"]))
        self.assertEqual(bad, [])

    def test_the_posts_and_stones_stand_off_the_carriageway(self):
        on_road = ["post (%.0f, %.0f)" % tuple(p["at"]) for p in self.posts if S.road_edge_m(self.m, *p["at"]) < S.POST_CLEAR_M - 0.05]
        on_road += ["stone %s (%.0f, %.0f)" % (s["name"], s["at"][0], s["at"][1]) for s in self.stones
                    if S.road_edge_m(self.m, *s["at"]) < S.STONE_CLEAR_M - 0.05]
        self.assertEqual(on_road, [])

    def test_every_road_into_a_settlement_passes_its_stone(self):
        missing = []
        for p in self.m["places"]:
            if not p["settlement"]:
                continue
            mine = [s for s in self.stones if s["place"] == p["id"]]
            for rid, road in self.roads.items():
                P = road["pts"]
                ends_here = min(math.hypot(P[0][0] - p["at"][0], P[0][1] - p["at"][1]),
                                math.hypot(P[-1][0] - p["at"][0], P[-1][1] - p["at"][1])) < S.END_M
                # a road from the town that never leaves it (the Grandfather Hollow's door) has no way in
                if not ends_here or float(np.hypot(P[:, 0] - p["at"][0], P[:, 1] - p["at"][1]).max()) < p["pad"] + S.STONE_OUT_M:
                    continue
                if not any(float(np.hypot(P[:, 0] - s["at"][0], P[:, 1] - s["at"][1]).min()) < 20.0 for s in mine):
                    missing.append("%s into %s" % (rid.split("/")[-1], p["name"]))
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
