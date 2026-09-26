#!/usr/bin/env python3
"""An elite or a miniboss out in the country does not stand within earshot of a road
(worldgen.encounters.road_clear_for): the cartographer found the Glass Falls bell-bearer 23 m off
its road, hearing every traveller at 28, and the Bell Garden's on the Choir to Last Camp road.

    python3 -m pytest tools/world/tests/test_encounter_roads.py
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import encounters as ENC  # noqa: E402

PACK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "game", "content", "packs", "core")


class EncounterRoads(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defs = ENC._enemy_defs(PACK)

    def test_the_bell_bearer_stands_back_35_m(self):
        self.assertGreaterEqual(ENC.road_clear_for(self.defs["core:enemy/bell_bearer"]), 35.0)

    def test_every_elite_and_miniboss_is_out_of_notice_of_the_road(self):
        n = 0
        for eid, e in self.defs.items():
            if e.get("archetype") == "elite" or "miniboss" in (e.get("tags") or []):
                per = e.get("perception", {}) or {}
                notice = max(float(per.get("sight_range", 0.0)), float(per.get("hearing", 0.0)))
                self.assertGreaterEqual(ENC.road_clear_for(e), notice + ENC.NOTICE_CLEAR_M, eid)
                n += 1
        self.assertGreater(n, 3)

    def test_the_rest_keep_the_verge_rule(self):
        wolfish = next(e for e in self.defs.values() if e.get("archetype") not in ("elite",)
                       and "miniboss" not in (e.get("tags") or []))
        self.assertEqual(ENC.road_clear_for(wolfish), ENC.ROAD_CLEAR_M)


if __name__ == "__main__":
    unittest.main()
