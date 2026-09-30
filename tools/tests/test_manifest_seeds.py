#!/usr/bin/env python3
"""The forge manifest keeps the seeds of what is already built.

    python3 tools/tests/test_manifest_seeds.py     # or: python3 -m unittest discover tools/tests

`tools/forge/make_manifest.py` derives each entry's seed from a running counter over TABLES, so a
table added ahead of another re-rolls it, and build_assets.py then rebuilds it differently. The
weapons and the livestock were built before the impostor table joined TABLES; their seeds are
pinned, and this holds them to the numbers they were built with.
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(TOOLS, "forge"))

import make_manifest as mm  # noqa: E402

# what the village's beasts were built with (their meta.json hashes carry these)
LIVESTOCK = {("hen", "a"): 9111, ("hen", "b"): 9128, ("goose", "a"): 9164, ("sheep", "a"): 9217,
             ("sheep", "b"): 9234, ("pig", "a"): 9270, ("crab", "a"): 9323, ("crab", "b"): 9340}


class SeedsTest(unittest.TestCase):
    def setUp(self):
        self.entries = mm.build()

    def test_the_livestock_keep_the_seeds_they_were_built_with(self):
        got = {(e["kind"], e["variant"]): e["seed"] for e in self.entries
               if e["generator"] == "gen_props" and e["kind"] in {"hen", "goose", "sheep", "pig", "crab"}}
        self.assertEqual(got, LIVESTOCK)

    def test_the_weapons_are_pinned_to_their_own_seed(self):
        swords = [e for e in self.entries if e.get("name") == "sword_iron"]
        self.assertEqual(len(swords), 1)
        self.assertEqual(swords[0]["seed"], mm.WEAPON_SEED)

    def test_the_cliff_ledges_are_pinned_after_everything_else(self):
        ledges = [e for e in self.entries if e["kind"] == "cliff_ledge"]
        self.assertEqual(len(ledges), sum(v for _k, _r, v, _p in mm.LEDGES))
        self.assertEqual(ledges[0]["seed"], mm.LEDGE_SEED)
        # after them only tables pinned to seeds of their own, which re-roll nothing before them:
        # the cliff faces (FACE_SEED), the Choir's fallen colossus and the start's waystones
        after = self.entries[self.entries.index(ledges[-1]) + 1:]
        pinned = {"cliff_face": mm.FACE_SEED, "choir_colossus": mm.CHOIR_FALLEN_SEED, "waystone": mm.WAYSTONE_SEED}
        self.assertTrue(all(e["kind"] in pinned for e in after),
                        "the ledges are the manifest's last table but for pinned ones: %s"
                        % sorted({e["kind"] for e in after}))
        for kind, first in pinned.items():
            run = [e for e in after if e["kind"] == kind]
            if run:
                self.assertEqual(run[0]["seed"], first, "%s starts from its own seed" % kind)

    def test_no_two_entries_are_the_same_asset(self):
        names = []
        for e in self.entries:
            names.append((e["generator"], e.get("name") or "%s|%s|%s" % (e["kind"], e["palette"], e["variant"])))
        self.assertEqual(len(names), len(set(names)))


if __name__ == "__main__":
    unittest.main()
