#!/usr/bin/env python3
"""The atlas is checked before anything is built from it.

    python3 -m pytest tools/world/tests/test_atlas.py

tools/world/atlas/SCHEMA.md is what a cartographer writes to; worldgen/atlas.py holds an atlas
to it. These tests build small atlases against a small content pack of their own, so they say
exactly which mistake each check catches, and then hold the committed atlas to the real packs.
"""
from __future__ import annotations

import copy
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
sys.path.insert(0, TOOLS_WORLD)

from worldgen import atlas as ATLAS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
PACK = os.path.join(REPO, "game", "content", "packs", "core")

SQUARE = [[-3000, -3000], [3000, -3000], [3000, 3000], [-3000, 3000]]


def _atlas() -> dict:
    """Two provinces split at x = 0 on a square island, a lake in the east, a river into it."""
    return {
        "version": 1, "world_size_m": 8192, "sea_level_m": 0,
        "provinces": [
            {"id": "west", "region": "core:region/west", "polygon": [[-3000, -3000], [0, -3000], [0, 3000], [-3000, 3000]],
             "biome": "downs", "base_height_m": 40, "relief_m": 30, "character": "rolling"},
            {"id": "east", "region": "core:region/east", "polygon": [[0, -3000], [3000, -3000], [3000, 3000], [0, 3000]],
             "biome": "lake_basin", "base_height_m": 12, "relief_m": 10, "character": "flat",
             "landform": ["raised_beaches"]},
        ],
        "coast": {"polygon": SQUARE, "seabed_m": -25},
        "lakes": [{"id": "mere", "polygon": [[1000, -500], [2000, -500], [2000, 500], [1000, 500]], "level_m": 8,
                   "depth_m": 12, "islands": [{"polygon": [[1400, -100], [1600, -100], [1600, 100], [1400, 100]],
                                               "height_m": 15}]}],
        "rivers": [{"id": "core:river/brook", "path": [[-2000, 0], [-500, 100], [1100, 0]], "width_m": [3, 7]}],
        "ranges": [{"id": "wall", "ridge": [[-2500, -2500, 300], [2500, -2500, 350]], "width_m": 1200,
                    "profile": "scarp", "face": "right"}],
        "roads": [{"from": "core:place/westby", "to": "core:place/eastby", "kind": "road"}],
        "start": {"at": [-1500, 1500], "facing_deg": 90},
    }


def _pack(tmp: str) -> str:
    os.makedirs(os.path.join(tmp, "regions"))
    os.makedirs(os.path.join(tmp, "places"))
    os.makedirs(os.path.join(tmp, "pois"))
    with open(os.path.join(tmp, "regions", "regions.json"), "w") as f:
        json.dump([{"id": "core:region/west"}, {"id": "core:region/east"}], f)
    with open(os.path.join(tmp, "places", "places.json"), "w") as f:
        json.dump([{"id": "core:place/westby", "kind": "village", "region": "core:region/west", "position": [-1500, 0]},
                   {"id": "core:place/eastby", "kind": "town", "region": "core:region/east", "position": [2500, 1500]}], f)
    with open(os.path.join(tmp, "pois", "pois.json"), "w") as f:
        json.dump([{"id": "core:poi/stones", "kind": "standing_stones", "region": "core:region/west",
                    "position": [-2000, -1000]}], f)
    return tmp


class AtlasCheck(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.pack = _pack(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def errors_of(self, doc):
        errors, _warnings = ATLAS.check(doc, self.pack)
        return errors

    def assertRefused(self, doc, fragment):
        errors = self.errors_of(doc)
        self.assertTrue(any(fragment in e for e in errors), "expected %r among %s" % (fragment, errors))

    def test_a_good_atlas_passes(self):
        errors, warnings = ATLAS.check(_atlas(), self.pack)
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])

    def test_the_shape_is_checked_first(self):
        doc = _atlas()
        doc["provinces"][0]["biome"] = "tundra"
        doc["provinces"][1].pop("character")
        doc["surprise"] = 1
        errors = self.errors_of(doc)
        self.assertTrue(any("'tundra' is not one of" in e for e in errors), errors)
        self.assertTrue(any("missing 'character'" in e for e in errors), errors)
        self.assertTrue(any("unknown field 'surprise'" in e for e in errors), errors)

    def test_a_province_needs_a_region_the_packs_have(self):
        doc = _atlas()
        doc["provinces"][1]["region"] = "core:region/nowhere"
        self.assertRefused(doc, "no region core:region/nowhere")

    def test_a_polygon_may_not_cross_itself(self):
        doc = _atlas()
        doc["forests"] = [{"polygon": [[-2000, -2000], [-1000, -1000], [-2000, -1000], [-1000, -2000]],
                           "kind": "oakwood", "density": 0.8}]
        self.assertRefused(doc, "crosses itself")

    def test_a_river_ends_in_water(self):
        doc = _atlas()
        doc["rivers"][0]["path"] = [[-2000, 0], [-500, 100]]
        self.assertRefused(doc, "is not in the sea, a lake or another river")
        doc["rivers"][0]["path"] = [[-2000, 0], [-3500, 100]]       # out to sea is a mouth
        self.assertEqual(self.errors_of(doc), [])

    def test_a_place_stands_in_its_own_region(self):
        doc = _atlas()
        doc["provinces"][0]["polygon"] = [[-3000, -3000], [-2000, -3000], [-2000, 3000], [-3000, 3000]]
        doc["provinces"][1]["polygon"] = [[-2000, -3000], [3000, -3000], [3000, 3000], [-2000, 3000]]
        self.assertRefused(doc, "core:place/westby (core:region/west) stands in province east")

    def test_a_settlement_is_not_in_the_water(self):
        doc = _atlas()
        doc["lakes"][0]["polygon"] = [[1000, 1000], [2900, 1000], [2900, 2000], [1000, 2000]]
        doc["lakes"][0]["islands"] = []
        doc["rivers"][0]["path"] = [[-2000, 0], [1100, 1100]]
        self.assertRefused(doc, "core:place/eastby stands in mere")

    def test_a_road_runs_between_places_that_exist(self):
        doc = _atlas()
        doc["roads"].append({"from": "core:place/westby", "to": "core:place/atlantis"})
        self.assertRefused(doc, "no place or POI core:place/atlantis")

    def test_the_start_is_on_dry_land(self):
        doc = _atlas()
        doc["start"]["at"] = [3500, 0]
        self.assertRefused(doc, "is in the sea")
        doc["start"]["at"] = [1200, 0]
        self.assertRefused(doc, "is in a lake")

    def test_a_scarp_says_which_way_it_faces(self):
        doc = _atlas()
        doc["ranges"][0].pop("face")
        self.assertRefused(doc, "a scarp needs a face")

    def test_an_island_stands_above_its_lake(self):
        doc = _atlas()
        doc["lakes"][0]["islands"][0]["height_m"] = 6
        self.assertRefused(doc, "is under the lake's surface")

    def test_an_authored_pad_stands_clear_of_the_water(self):
        doc = _atlas()
        doc["pads"] = [{"place": "core:poi/stones", "level_m": 0.6}]
        self.assertRefused(doc, "within a metre of the water")
        doc["pads"] = [{"place": "core:poi/stones", "level_m": 5.0, "radius_m": 30}]
        self.assertEqual(self.errors_of(doc), [])
        doc["pads"].append({"place": "core:poi/nowhere", "level_m": 5.0})
        self.assertRefused(doc, "no place or POI core:poi/nowhere")

    def test_a_shelf_off_the_coast_is_a_warning(self):
        doc = _atlas()
        doc["coast"]["shelves"] = [{"polygon": [[3200, 0], [3400, 0], [3400, 200], [3200, 200]], "height_m": 4}]
        errors, warnings = ATLAS.check(doc, self.pack)
        self.assertEqual(errors, [])
        self.assertTrue(any("sea runs between it and the land" in w for w in warnings), warnings)
        doc["coast"]["shelves"][0]["polygon"][0] = [2900, 0]
        _errors, warnings = ATLAS.check(doc, self.pack)
        self.assertFalse(any("sea runs between" in w for w in warnings), warnings)

    def test_a_settlement_without_a_road_is_a_warning(self):
        doc = _atlas()
        doc["roads"] = []
        errors, warnings = ATLAS.check(doc, self.pack)
        self.assertEqual(errors, [])
        self.assertTrue(any("core:place/westby (village) has no road" in w for w in warnings), warnings)

    def test_the_schema_file_is_the_one_the_validator_reads(self):
        schema = ATLAS.load_schema()
        self.assertEqual(schema["properties"]["world_size_m"]["const"], 8192)
        doc = copy.deepcopy(_atlas())
        doc["world_size_m"] = 4096
        self.assertRefused(doc, "world_size_m: must be 8192")


@unittest.skipUnless(os.path.exists(ATLAS.ATLAS_PATH), "no tools/world/atlas/atlas.json yet")
class CommittedAtlas(unittest.TestCase):
    def test_the_committed_atlas_has_no_errors(self):
        errors, _warnings = ATLAS.check(ATLAS.load(), PACK)
        self.assertEqual(errors, [], "\n".join(errors))


if __name__ == "__main__":
    unittest.main()
