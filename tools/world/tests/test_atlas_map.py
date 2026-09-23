#!/usr/bin/env python3
"""The map is the one the atlas was drawn to be.

    python3 -m pytest tools/world/tests/test_atlas_map.py

test_atlas.py holds any atlas to its schema. This holds the committed one to the brief it was
drawn to (docs/ATLAS.md): every place and point of interest stands on the map, in its own region
and inside the coast; the rivers run downhill to water; the country is full, no walkable ground
far from something worth walking to and no stretch of road without something on it; every town
has a road; the start looks at the Choir; and nothing any quest, conversation or person names
has gone missing. The density figures come from tools/world/atlas/preview.py, the atlas's own
coarse reading of its land, so they hold whatever the builder does with the detail.
"""
from __future__ import annotations

import glob
import json
import math
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)
sys.path.insert(0, os.path.join(TOOLS_WORLD, "atlas"))

from worldgen import atlas as ATLAS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
PACK = os.path.join(REPO, "game", "content", "packs", "core")

## The brief's rule is "no walkable point more than about 400 m from a notable location, nothing
## on a road more than about 250 m". The preview's land is coarse, so the test allows the "about":
## a sliver of ground or a few metres of road past the round number is not a hole in the map.
REACH_M = 400.0
REACH_SLACK_M = 150.0          # nowhere walkable further than this past REACH_M
SHARE_OVER_REACH = 0.01        # and no more than this share of the walkable ground past REACH_M at all
ROAD_REACH_M = 250.0
ROAD_SLACK_M = 50.0
## A river may cut down through a knoll the preview's hills put in its way; it may not climb a range.
RIVER_RISE_M = 110.0

## Where a point of interest may stand off dry land: a bridge or a causeway over its water, a wreck
## in the shallows, a thing in the Mere (the Bell-Buoys), and the one the Hush has: the Stair itself.
WET_KINDS = ("bridge", "wreck", "strange", "deep_place")
OFF_THE_COAST = ("core:poi/hushline_stair",)
SETTLEMENTS = ("city", "town", "village", "hamlet", "fort", "lodge")


def _rows(sub: str) -> list:
    out = []
    for path in sorted(glob.glob(os.path.join(PACK, sub, "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            out.extend(json.load(f))
    return out


class _Map(unittest.TestCase):
    atlas: dict = {}
    places: list = []
    pois: list = []

    @classmethod
    def setUpClass(cls):
        cls.atlas = ATLAS.load()
        cls.places = _rows("places")
        cls.pois = _rows("pois")
        cls.where = {d["id"]: d for d in cls.places + cls.pois if d.get("position")}


class EveryLocationIsOnTheMap(_Map):
    def test_each_stands_inside_the_coast(self):
        bad = []
        for d in self.places + self.pois:
            x, z = d["position"][0], d["position"][1]
            if d["id"] in OFF_THE_COAST or d.get("kind") == "edge":
                continue
            lake = ATLAS.lake_at(self.atlas, x, z)
            if not ATLAS.on_land(self.atlas, x, z):
                bad.append("%s at (%.0f, %.0f) is in the sea" % (d["id"], x, z))
            elif lake is not None and d.get("kind") not in WET_KINDS:
                bad.append("%s at (%.0f, %.0f) is in %s" % (d["id"], x, z, lake["id"]))
        self.assertEqual(bad, [], "\n".join(bad))

    def test_each_stands_in_a_province_of_its_own_region(self):
        bad = []
        for d in self.places + self.pois:
            x, z = d["position"][0], d["position"][1]
            if d["id"] in OFF_THE_COAST or d.get("kind") == "edge":
                continue
            prov, _depth = ATLAS.province_at(self.atlas, x, z)
            if prov is None or prov["region"] != d["region"]:
                bad.append("%s (%s) stands in %s" % (d["id"], d["region"], prov["id"] if prov else "no province"))
        self.assertEqual(bad, [], "\n".join(bad))

    def test_no_two_stand_on_one_spot(self):
        seen = {}
        bad = []
        for d in self.places + self.pois:
            key = (round(d["position"][0] / 20.0), round(d["position"][1] / 20.0))
            if key in seen and seen[key] != d["id"] and not (
                    {seen[key], d["id"]} == {"core:place/grandfather_hollow", "core:place/grandfather"}):
                bad.append("%s and %s" % (seen[key], d["id"]))
            seen[key] = d["id"]
        self.assertEqual(bad, [], "these stand within twenty metres of each other: " + ", ".join(bad))


class NothingNamedIsMissing(_Map):
    def test_every_place_and_poi_a_quest_conversation_or_person_names_exists(self):
        names = re.compile(r"core:(?:place|poi)/[a-z0-9_]+")
        missing = set()
        for path in glob.glob(os.path.join(PACK, "**", "*.json"), recursive=True):
            with open(path, "r", encoding="utf-8") as f:
                for ref in names.findall(f.read()):
                    if ref not in self.where:
                        missing.add("%s (in %s)" % (ref, os.path.relpath(path, PACK)))
        self.assertEqual(sorted(missing), [], "named but not on the map")


class TheRiversRunDownhill(unittest.TestCase):
    def test_no_river_climbs_a_range(self):
        import preview as PV
        land = PV.Atlas.load(res=16.0)
        bad = ["%s rises %.0f m at (%.0f, %.0f)" % (r["id"], r["worst_rise_m"], r["worst_at"][0], r["worst_at"][1])
               for r in land.river_profiles() if r["worst_rise_m"] > RIVER_RISE_M]
        self.assertEqual(bad, [], "\n".join(bad))

    def test_every_river_ends_in_water(self):
        doc = ATLAS.load()
        ends = {rv["id"]: rv["path"][-1] for rv in doc.get("rivers", [])}
        for rid, (x, z) in ends.items():
            wet = ATLAS.lake_at(doc, x, z) is not None or not ATLAS.on_land(doc, x, z)
            joins = any(ATLAS.distance_to_path(x, z, other["path"]) <= ATLAS.CONFLUENCE_M
                        for other in doc["rivers"] if other["id"] != rid)
            self.assertTrue(wet or joins, "%s ends on dry ground at (%.0f, %.0f)" % (rid, x, z))


class TheCountryIsFull(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import preview as PV
        cls.PV = PV
        cls.land = PV.Atlas.load(res=16.0)
        cls.survey = cls.land.survey()

    def test_no_walkable_ground_is_far_from_somewhere(self):
        s = self.survey
        self.assertLessEqual(s["max_gap_m"], REACH_M + REACH_SLACK_M,
                             "the furthest walkable ground is %.0f m from anything" % s["max_gap_m"])
        self.assertLessEqual(s["share_over_reach"], SHARE_OVER_REACH,
                             "%.1f%% of the walkable ground is over %.0f m from anything: %s" % (
                                 100 * s["share_over_reach"], REACH_M,
                                 ["%.0f m at (%.0f, %.0f)" % (g["worst_m"], g["at"][0], g["at"][1]) for g in s["gaps"]]))

    def test_no_road_runs_long_without_somewhere_on_it(self):
        bad = ["%s: %.0f m at (%.0f, %.0f)" % (r["road"], r["worst_m"], r["at"][0], r["at"][1])
               for r in self.survey["roads_over_reach"] if r["worst_m"] > ROAD_REACH_M + ROAD_SLACK_M]
        self.assertEqual(bad, [], "\n".join(bad))

    def test_there_are_well_over_two_hundred_places_to_go(self):
        self.assertGreaterEqual(self.survey["locations"], 250)


class TheRoads(_Map):
    def test_every_settlement_has_a_road(self):
        ends = set()
        for r in self.atlas.get("roads", []):
            ends.add(r["from"])
            ends.add(r["to"])
        bad = [d["id"] for d in self.places if d.get("kind") in SETTLEMENTS and d["id"] not in ends]
        self.assertEqual(bad, [], "no road reaches " + ", ".join(bad))

    def test_every_road_is_a_road_between_two_different_places(self):
        seen = set()
        for r in self.atlas.get("roads", []):
            self.assertNotEqual(r["from"], r["to"])
            key = tuple(sorted((r["from"], r["to"])))
            self.assertNotIn(key, seen, "two roads between %s and %s" % key)
            seen.add(key)


class TheStart(_Map):
    def test_the_start_looks_at_the_choir(self):
        st = self.atlas["start"]
        x, z = st["at"]
        cx, cz = self.where["core:place/sunken_choir"]["position"][:2]
        bearing = math.degrees(math.atan2(cx - x, -(cz - z))) % 360.0
        off = abs((st["facing_deg"] - bearing + 180.0) % 360.0 - 180.0)
        self.assertLess(off, 15.0, "the start faces %.0f, the Choir is at %.0f" % (st["facing_deg"], bearing))

    def test_the_start_is_the_head_of_the_stair(self):
        st = self.atlas["start"]
        hx, hz = self.where["core:poi/stair_head"]["position"][:2]
        self.assertLess(math.hypot(st["at"][0] - hx, st["at"][1] - hz), 60.0)
        self.assertEqual(st.get("place"), "core:poi/stair_head")


if __name__ == "__main__":
    unittest.main()
