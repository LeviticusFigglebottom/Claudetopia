"""The POI content is one file a region, and every reader reads every file (docs/WORLD_LIFE.md).

* each pois/<region>.json holds that region's POIs only; a file whose name starts with `_` (another
  agent's showcase, say) may hold any;
* no id is in two files;
* the registry the world build reads keeps the one-file registry's order for the POIs it had
  (worldgen/content.py), so the split changed no build, and a new POI follows them;
* the encounter, item and book files named for a region are about that region's places.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

TOOLS_WORLD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
sys.path.insert(0, TOOLS_WORLD)

from worldgen import content as CONTENT  # noqa: E402


class PoiFiles(unittest.TestCase):
    def test_every_region_has_its_file_and_holds_only_its_own(self):
        names = [os.path.basename(p) for p in CONTENT.files(PACK, "pois")]
        for r in CONTENT.REGIONS:
            self.assertIn("%s.json" % r, names)
        for row, name in CONTENT.rows(PACK, "pois", with_file=True):
            if name.startswith("_"):
                continue
            self.assertIn(name[:-5], CONTENT.REGIONS, "%s: a POI file is named for a region, or starts with _" % name)
            self.assertEqual(CONTENT.region_of(row), name[:-5], "%s is in %s" % (row.get("id"), name))

    def test_no_id_is_in_two_files(self):
        seen = {}
        for row, name in CONTENT.rows(PACK, "pois", with_file=True):
            pid = row.get("id")
            self.assertNotIn(pid, seen, "%s is in %s and %s" % (pid, seen.get(pid), name))
            seen[pid] = name

    def test_the_registry_keeps_the_one_files_order(self):
        with open(CONTENT.LEGACY_ORDER, encoding="utf-8") as f:
            legacy = json.load(f)
        reg = [r["id"] for r in CONTENT.poi_registry(PACK)]
        kept = [i for i in legacy if i in set(reg)]
        self.assertEqual(reg[:len(kept)], kept)
        self.assertEqual(len(reg), len(CONTENT.rows(PACK, "pois")))

    def test_a_new_file_is_read_and_follows(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "pois"))
            first = CONTENT.poi_registry(PACK)[0]
            with open(os.path.join(tmp, "pois", "_showcase.json"), "w") as f:
                json.dump([{"id": "core:poi/zz_new", "region": "core:region/skerrow", "position": [0, 0]}], f)
            with open(os.path.join(tmp, "pois", "skerrow.json"), "w") as f:
                json.dump([{"id": "core:poi/aa_new", "region": "core:region/skerrow", "position": [1, 1]}, first], f)
            self.assertEqual([r["id"] for r in CONTENT.poi_registry(tmp)],
                             [first["id"], "core:poi/zz_new", "core:poi/aa_new"])


class RegionFiles(unittest.TestCase):
    """encounters/pois_<region>.json, encounters/wayside_<region>.json, items/ and books/
    wayside_<region>.json: each about its own region's places."""

    @classmethod
    def setUpClass(cls):
        cls.region = {r["id"]: CONTENT.region_of(r) for r in CONTENT.poi_registry(PACK)}
        with open(os.path.join(PACK, "places", "places.json"), encoding="utf-8") as f:
            cls.region.update({r["id"]: CONTENT.region_of(r) for r in json.load(f)})

    def _named(self, sub, prefix):
        for row, name in CONTENT.rows(PACK, sub, with_file=True):
            stem = name[:-5]
            if stem.startswith(prefix + "_") and stem[len(prefix) + 1:] in CONTENT.REGIONS:
                yield row, stem[len(prefix) + 1:]

    def test_encounters_are_at_their_regions_places(self):
        n = 0
        for prefix in ("pois", "wayside"):
            for row, region in self._named("encounters", prefix):
                self.assertEqual(self.region.get(row.get("place")), region, "%s in %s" % (row.get("id"), region))
                n += 1
        self.assertGreater(n, 200)

    def test_wayside_items_and_books_are_their_regions(self):
        lies = {}
        for row, region in self._named("encounters", "wayside"):
            for thing in row.get("lies", []):
                lies[thing["item"]] = region
        reads = {}
        for row, region in self._named("items", "wayside"):
            self.assertEqual(lies.get(row["id"], region), region, row["id"])
            if row.get("reads"):
                reads[row["reads"]] = region
        for row, region in self._named("books", "wayside"):
            self.assertEqual(reads.get(row["id"], region), region, row["id"])


if __name__ == "__main__":
    unittest.main()
