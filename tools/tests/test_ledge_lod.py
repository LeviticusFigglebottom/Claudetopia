#!/usr/bin/env python3
"""Every cliff ledge keeps its LOD ladder in the world streamer.

    python3 tools/tests/test_ledge_lod.py     # or: python3 -m unittest discover tools/tests

The world streamer gives an opaque scatter asset its LOD ladder only when its LOD0 has at least
SOLID_MIN_TRIS triangles (game/world/scatter_lod.gd); anything lighter is drawn whole at every
distance. The cliff ledges are laid tens of thousands of times over the sea cliffs and the crags,
most of them seen from far off, and the first crag-like rebuild left three of them under it
(1,272 for Skerrow's short one): about 7 M triangles of ledges in the worst view against 3.75 M.
This reads the threshold from the streamer and each ledge's triangle counts from its meta.
"""
from __future__ import annotations

import glob
import json
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ROCKS = os.path.join(REPO, "game", "assets", "models", "rocks")
SCATTER_LOD = os.path.join(REPO, "game", "world", "scatter_lod.gd")


class LedgeLodTest(unittest.TestCase):
    def test_every_ledge_is_heavy_enough_for_its_ladder_and_has_one(self):
        m = re.search(r"const SOLID_MIN_TRIS\s*:=\s*(\d+)", open(SCATTER_LOD, encoding="utf-8").read())
        self.assertIsNotNone(m, "scatter_lod.gd no longer says SOLID_MIN_TRIS the way this reads it")
        floor = int(m.group(1))
        metas = sorted(glob.glob(os.path.join(ROCKS, "*_cliff_ledge_*", "*_cliff_ledge_?.meta.json")))
        self.assertGreaterEqual(len(metas), 13, "the ledges are built")
        for path in metas:
            meta = json.load(open(path, encoding="utf-8"))
            tris = [mm["tris"] for mm in meta["meshes"]]
            name = os.path.basename(path)
            self.assertEqual(len(tris), 3, "%s: LOD0, LOD1 and LOD2" % name)
            self.assertGreaterEqual(tris[0], floor, "%s: LOD0 %d triangles, under the ladder's %d" % (name, tris[0], floor))
            self.assertLess(tris[2], tris[0] * 0.3, "%s: its LOD2 is a real saving" % name)


if __name__ == "__main__":
    unittest.main()
