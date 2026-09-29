#!/usr/bin/env python3
"""The gap map measures what it says it measures.

    python3 -m pytest tools/world/tests/test_gap_map.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)
sys.path.insert(0, os.path.join(TOOLS_WORLD, "atlas"))

import gap_map as G  # noqa: E402
from worldgen import atlas as ATLAS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
DRESSING = os.path.join(REPO, "game", "world", "pois", "poi_dressing.gd")
## how close a find may stand to any other location (the proposer asks 110 m; hand-placed finds
## may come a little nearer where the ground asks it)
FIND_CLEAR_M = 100.0


def _json(*parts):
    import json
    with open(os.path.join(PACK, *parts), encoding="utf-8") as f:
        return json.load(f)


def _dir(sub, prefix=""):
    """Every row of every sub/<prefix>*.json: the POIs and the wayside finds are one file a region."""
    import glob
    import json
    out = []
    for path in sorted(glob.glob(os.path.join(PACK, sub, prefix + "*.json"))):
        with open(path, encoding="utf-8") as f:
            out.extend(json.load(f))
    return out


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

    def test_an_off_road_find_is_seen_over_flat_ground_and_not_through_a_hill(self):
        import numpy as np
        H = np.zeros((64, 64), np.float32)
        size = 640.0                                   # 10 m cells, centred on 0
        self.assertTrue(G._sees(H, size, (-200.0, 0.0), (200.0, 0.0)))
        H[:, 30:34] = 20.0                             # a ridge across the line
        self.assertFalse(G._sees(H, size, (-200.0, 0.0), (200.0, 0.0)))

    def test_the_committed_map_measures(self):
        m = G.measure()
        self.assertGreater(m["road"]["road_km"], 50.0)
        self.assertGreater(len(m["things"]), 250)
        self.assertLessEqual(m["road"]["thin_km"], m["road"]["road_km"])



class WaysideFinds(unittest.TestCase):
    """Every wayside find is a small, authored point of interest a pace off a road: standing where
    its region is, clear of every other location, in a kind the kit builds, with something lying
    there to pick up (docs/ATLAS.md section 17)."""

    @classmethod
    def setUpClass(cls):
        import re
        cls.pois = _dir("pois")
        cls.places = _json("places", "places.json")
        cls.finds = [p for p in cls.pois if p.get("wayside")]
        text = open(DRESSING, encoding="utf-8").read()
        body = text[text.index("const KINDS_BUILT"):]
        cls.built = set(re.findall(r'"([a-z_]+)"', body[:body.index("]")]))
        cls.atlas = ATLAS.load()
        cls.items = {i["id"]: i for i in _dir("items", "wayside")}
        cls.items.update({i["id"]: i for i in _json("items", "weapons.json")})
        cls.books = {b["id"]: b for b in _dir("books", "wayside")}
        cls.encs = _dir("encounters", "wayside")

    def test_there_are_finds(self):
        self.assertGreaterEqual(len(self.finds), 50)

    def test_each_is_written_and_claims_no_sightline(self):
        for p in self.finds:
            for key in ("name", "unique_feature", "story", "hook", "encounter", "region"):
                self.assertTrue(str(p.get(key, "")).strip(), "%s has no %s" % (p["id"], key))
            self.assertEqual(p.get("visible_from", []), [], "%s: a find is come upon, not seen from afar" % p["id"])
            self.assertFalse(p.get("hearthstone"), "%s: a find keeps no Hearthstone" % p["id"])

    def test_each_is_a_kind_the_kit_builds(self):
        for p in self.finds:
            self.assertIn(p["kind"], self.built, "%s: nothing dresses a %s yet" % (p["id"], p["kind"]))

    def test_each_stands_on_dry_land_in_its_own_region(self):
        for p in self.finds:
            x, z = p["position"]
            self.assertTrue(ATLAS.on_land(self.atlas, x, z), "%s is in the sea" % p["id"])
            self.assertIsNone(ATLAS.lake_at(self.atlas, x, z), "%s is in a lake" % p["id"])
            prov, _ = ATLAS.province_at(self.atlas, x, z)
            self.assertEqual(prov["region"], p["region"], "%s stands in %s" % (p["id"], prov["id"]))

    def test_each_stands_clear_of_every_other_location(self):
        others = [(q["id"], q["position"]) for q in self.pois + self.places if q.get("position")]
        for p in self.finds:
            x, z = p["position"]
            for qid, pos in others:
                if qid == p["id"]:
                    continue
                d = math.hypot(pos[0] - x, pos[1] - z)
                self.assertGreaterEqual(d, FIND_CLEAR_M, "%s is %.0f m from %s" % (p["id"], d, qid))

    def test_each_has_something_lying_there(self):
        lying = {}
        for e in self.encs:
            lying.setdefault(e["place"], []).extend(e.get("lies", []))
        for p in self.finds:
            things = lying.get(p["id"], [])
            self.assertTrue(things, "%s: nothing lies there" % p["id"])
            for l in things:
                item = self.items.get(l.get("item", ""))
                self.assertIsNotNone(item, "%s: %s is no item" % (p["id"], l))
                if item.get("reads"):
                    self.assertIn(item["reads"], self.books, "%s: %s reads nothing" % (p["id"], item["id"]))

    def test_each_weapon_lying_at_a_find_is_a_weapon_and_the_story_says_so(self):
        weapons = {i["id"] for i in _json("items", "weapons.json")}
        pois = {p["id"]: p for p in self.finds}
        laid = 0
        for e in self.encs:
            for l in e.get("lies", []):
                if l.get("item") in weapons:
                    laid += 1
                    self.assertIn(e["place"], pois, "%s lies at %s, which is not a find" % (l["item"], e["place"]))
        self.assertGreaterEqual(laid, 8, "weapons lie out in the country, one or two a province")

    def test_no_two_finds_share_a_name_or_a_hook(self):
        names = [p["name"] for p in self.pois + self.places]
        hooks = [p["hook"] for p in self.pois if p.get("hook")]
        for p in self.finds:
            self.assertEqual(names.count(p["name"]), 1, "two places are called %s" % p["name"])
            self.assertEqual(hooks.count(p["hook"]), 1, "%s's hook is used twice" % p["id"])


if __name__ == "__main__":
    unittest.main()
