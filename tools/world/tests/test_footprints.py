#!/usr/bin/env python3
"""Nothing stands inside a landmark (worldgen.footprints): the trees, rocks and made things inside a
forge scene's box, turned by its yaw, go; grass stays, and so does everything outside the box.

    python3 -m pytest tools/world/tests/test_footprints.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import footprints as FP  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.rows import Rows, pack_rgb  # noqa: E402

SCENE = "res://assets/models/landmarks/test_nave_a/test_nave_a.glb"
TREE = "res://assets/models/trees/sedgemire_alder_a/sedgemire_alder_a.glb"
ROCK = "res://assets/models/rocks/sedgemire_boulder_a/sedgemire_boulder_a.glb"
GRASS = "res://assets/models/flora/sedgemire_grass_clump_a/sedgemire_grass_clump_a.glb"


class Footprints(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        d = os.path.join(self.root, "game", "assets", "models", "landmarks", "test_nave_a")
        os.makedirs(d)
        # a ruin 60 m long down its +z and 20 m across, its tower at the origin
        with open(os.path.join(d, "test_nave_a.meta.json"), "w") as f:
            json.dump({"bounds": {"min": [-10.0, 0.0, -5.0], "max": [10.0, 40.0, 55.0]}}, f)
        self.g = Grid(1024.0, 256)
        # turned a quarter: its +z runs down the world's +x (Godot's yaw about +Y)
        self.scenes = [{"scene": SCENE, "pos": [0.0, 0.0, 0.0], "yaw": 90.0}]

    def _rows(self, pts):
        r = Rows()
        pts = np.asarray(pts, dtype=np.float64)
        n = len(pts)
        r.add_arrays(pts[:, 0], np.zeros(n), pts[:, 1], np.zeros(n), np.ones(n), pack_rgb(np.ones((n, 3))))
        return r

    def test_clears_inside_the_turned_box_only(self):
        inside = [(30.0, 0.0), (50.0, 8.0), (2.0, -9.0)]
        outside = [(0.0, 30.0), (-20.0, 0.0), (70.0, 0.0), (30.0, 15.0)]
        key = self.g.written_cell(0.0, 0.0)
        buckets = {key: {TREE: self._rows(inside + outside), ROCK: [[30.0, 0.0, 0.0, 0.0, 1.0, "#fff"]],
                         GRASS: self._rows(inside)}}
        gone = FP.clear(buckets, self.scenes, self.g, self.root)
        self.assertEqual(gone.get("trees"), len(inside))
        self.assertEqual(gone.get("rocks"), 1)
        left = buckets[key][TREE].xz()
        for p in outside:
            self.assertTrue(any(np.allclose(p, q) for q in left), p)
        self.assertNotIn(ROCK, buckets[key])
        self.assertEqual(len(buckets[key][GRASS]), len(inside), "grass is not cleared")

    def test_a_tree_just_past_the_wall_still_goes(self):
        # its crown overhangs the wall: trees are cleared 2.5 m past the box
        key = self.g.written_cell(0.0, 0.0)
        buckets = {key: {TREE: self._rows([(30.0, 12.0), (30.0, 14.0)])}}
        FP.clear(buckets, self.scenes, self.g, self.root)
        self.assertEqual(len(buckets[key][TREE]), 1)

    def test_a_scene_without_bounds_clears_nothing(self):
        key = self.g.written_cell(0.0, 0.0)
        buckets = {key: {TREE: self._rows([(1.0, 1.0)])}}
        gone = FP.clear(buckets, [{"scene": "res://scenes/pois/hand_built.tscn", "pos": [0, 0, 0], "yaw": 0}],
                        self.g, self.root)
        self.assertEqual(gone, {})
        self.assertEqual(len(buckets[key][TREE]), 1)


if __name__ == "__main__":
    unittest.main()
