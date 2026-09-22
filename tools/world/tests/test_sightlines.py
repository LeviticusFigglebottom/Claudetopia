#!/usr/bin/env python3
"""The authored sightlines, marched over the world that was actually built.

    python3 tools/world/tests/test_sightlines.py
    python3 -m unittest discover tools/world/tests

DESIGN §4: "each POI names at least one other POI it should be visible from". Thirty-six of
those claims were refused by the land and ten POIs could not be seen from anywhere, which the
world-building answered by moving POIs and replacing vantages (PROGRESS.md, "Sightlines,
answered"). Nothing stopped it happening again: a POI moved fifty metres, a landmark height
corrected, or a change to the terrain generator puts a hill back in the way, and the only
symptom is that surveying from a vista quietly finds less than it used to.

So this fails the build if it happens. It uses `tools/sightlines.py` itself — the same ray,
the same constants read out of `place_discovery.gd`, the same heightmap the game samples — so
there is one model of what is visible and not two.

It reads `game/world/generated`, the full 4096 build, rather than building its own: a 1024
build smooths exactly the hills that block these lines, so it would answer a different
question and pass while the real world was dark. If the world has not been built the test
says so and skips, and `./run.sh world` is the fix.
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(REPO, "tools"))

GEN = os.path.join(REPO, "game", "world", "generated")

# A line into a valley that is called hidden is the way in rather than the place, so the land
# refusing it is the valley doing its job and not a fault in the placement. Three of the five
# are refused and two are not, which is allowed both ways: you can be shown the way in. Every
# other line must hold.
HIDDEN_KIND = "hidden_valley"


class SightlineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not os.path.exists(os.path.join(GEN, "heights.r32")):
            raise unittest.SkipTest("no built world in game/world/generated; run ./run.sh world")
        import sightlines
        cls.sl = sightlines
        cls.k = sightlines.constants()
        cls.hs = sightlines.Heights()
        cls.pos = sightlines.positions()
        cls.kd = sightlines.kinds()
        cls.nm = sightlines.names()
        cls.claims = sightlines.claims()
        cls.clear = []
        cls.blocked = []
        cls.veiled = []
        cls.missing = []
        for vantage, target in cls.claims:
            if vantage not in cls.pos or target not in cls.pos:
                cls.missing.append((vantage, target))
                continue
            is_blocked, worst, dist = sightlines.blocked_at(
                cls.hs, cls.pos[vantage], cls.pos[target], cls.k, cls.kd.get(target, ""))
            row = (vantage, target, worst, dist)
            if not is_blocked:
                cls.clear.append(row)
            elif cls.kd.get(target) == HIDDEN_KIND:
                cls.veiled.append(row)
            else:
                cls.blocked.append(row)

    def say(self, rows):
        return "\n".join(
            "    %s -> %s  %.0f m, ground %.0f m over the line"
            % (self.nm.get(v, v), self.nm.get(t, t), d, w) for v, t, w, d in rows)

    def test_every_authored_sightline_has_a_pad(self):
        self.assertEqual(self.missing, [], "a sightline names something the world never placed")

    def test_the_authored_count_has_not_shrunk(self):
        # The composition rule is DESIGN §4's; answering a refused line means replacing it with
        # one the land agrees with, not deleting it.
        self.assertGreaterEqual(len(self.claims), 90,
                                "there were 90 authored sightlines and now there are %d"
                                % len(self.claims))

    def test_no_sightline_is_blocked_by_the_land(self):
        self.assertEqual(
            self.blocked, [],
            "%d authored sightlines the land refuses:\n%s\n"
            "  Move the POI, correct its kind's height in place_discovery.gd, or give the line\n"
            "  a vantage the land agrees with; tools/sightlines.py --verbose shows the rest."
            % (len(self.blocked), self.say(self.blocked)))

    def test_every_poi_can_be_seen_from_somewhere(self):
        seen = {t for _, t, _, _ in self.clear}
        dark = sorted({t for _, t in self.claims} - seen)
        dark = [t for t in dark if self.kd.get(t) != HIDDEN_KIND]
        self.assertEqual(
            dark, [],
            "%d POIs no vantage can see, so they can only be found by walking into them:\n%s"
            % (len(dark), "\n".join("    %s (%s)" % (self.nm.get(t, t), self.kd.get(t, ""))
                                    for t in dark)))

    def test_the_exemption_is_only_for_hidden_valleys(self):
        # The exemption above is the one place this check looks away, so it is pinned: nothing
        # but a hidden valley may use it, and it may not grow.
        self.assertTrue(all(self.kd.get(t) == HIDDEN_KIND for _, t, _, _ in self.veiled))
        self.assertLessEqual(len(self.veiled), 3,
                             "%d lines are exempt as hidden valleys, and three were:\n%s"
                             % (len(self.veiled), self.say(self.veiled)))


if __name__ == "__main__":
    unittest.main()
