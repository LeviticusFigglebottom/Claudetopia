#!/usr/bin/env python3
"""Every tree stands with its whole foot in the ground (worldgen.trees), not on its pivot with its
roots' downhill side over air (playtest 6, 1.webp).

    python3 -m pytest tools/world/tests/test_tree_seating.py
    WICKMERE_GENERATED=<build dir> python3 -m pytest tools/world/tests/test_tree_seating.py   # a built world
"""
from __future__ import annotations

import glob
import json
import os
import subprocess
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import trees as TR  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.rows import Rows, pack_rgb  # noqa: E402

## how far over the ground any point of a tree's foot may stand
FLOAT_M = 0.15
OAK = "res://assets/models/trees/briarwold_giant_oak_a/briarwold_giant_oak_a.glb"
THORN = "res://assets/models/trees/hearthvale_hawthorn_a/hearthvale_hawthorn_a.glb"


class Table(unittest.TestCase):
    def test_the_table_is_current_with_the_forge_s_trees(self):
        r = subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "tree_contacts.py"), "--check"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_every_tree_has_a_foot(self):
        t = TR.load_table()
        self.assertGreater(len(t), 50)
        for name, (pts, h) in t.items():
            self.assertGreater(len(pts), 3, name)
            self.assertTrue(np.all(pts[:, 1] < 1.6), name)


class Seated(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(512.0, 256)                    # 2 m texels
        X, Z = g.mesh(np.float64)
        cls.H = (100.0 + 0.35 * X + 0.12 * Z).astype(np.float32)
        cls.table = TR.load_table()
        rng = np.random.default_rng(4)
        n = 300
        x, z = rng.uniform(-200, 200, n), rng.uniform(-200, 200, n)
        cls.x, cls.z = x, z
        yaw = rng.uniform(0, 360, n)
        sc = rng.uniform(0.85, 1.3, n)
        y = sample_bilinear(cls.H, g, x, z)
        rows = Rows()
        rows.add_arrays(np.round(x, 2), y, np.round(z, 2), yaw, sc, pack_rgb(np.ones((n, 3))))
        lists = [[round(float(x[i]), 2), round(float(y[i]), 2), round(float(z[i]), 2), round(float(yaw[i]), 1),
                  round(float(sc[i]), 3), "#ffffff"] for i in range(n)]
        cls.buckets = {(0, 0): {OAK: rows, THORN: lists}}
        cls.counts = TR.seat(cls.buckets, g, cls.H, cls.table)

    def test_no_foot_stands_over_the_ground_unless_capped(self):
        for asset in (OAK, THORN):
            name = os.path.splitext(os.path.basename(asset))[0]
            pts, h = self.table[name]
            rows = list(self.buckets[(0, 0)][asset])
            fl = TR.floating(self.H, self.grid, rows, pts)
            g0 = sample_bilinear(self.H, self.grid, np.array([r[0] for r in rows]), np.array([r[2] for r in rows]))
            sink = g0 - np.array([r[1] for r in rows])
            cap = TR.SEAT_CAP_M + TR.SEAT_CAP_PER_M * h * np.array([r[4] for r in rows])
            free = sink < cap - 0.02
            self.assertTrue(free.any(), name)
            self.assertLess(float(fl[free].max()), FLOAT_M, "%s: a foot %.2f m over the ground" % (name, fl[free].max()))
            self.assertTrue(np.all(sink <= cap + 0.02), name)

    def test_a_giant_oak_on_this_slope_goes_down_further_than_a_thorn(self):
        def mean_sink(asset):
            rows = list(self.buckets[(0, 0)][asset])
            g0 = sample_bilinear(self.H, self.grid, np.array([r[0] for r in rows]), np.array([r[2] for r in rows]))
            return float(np.mean(g0 - np.array([r[1] for r in rows])))
        self.assertGreater(mean_sink(OAK), mean_sink(THORN) + 0.3)
        self.assertEqual(self.counts["trees"], 600)


class BuiltWorld(unittest.TestCase):
    """On a built world (WICKMERE_GENERATED with heights.r32): no tree's foot stands more than
    FLOAT_M over the ground, except those the cap holds up (counted, and few)."""

    def test_no_tree_s_foot_stands_over_the_ground(self):
        gen = os.environ.get("WICKMERE_GENERATED", os.path.join(REPO, "game", "world", "generated"))
        if not os.path.exists(os.path.join(gen, "heights.r32")):
            raise unittest.SkipTest("no full-resolution heights at %s" % gen)
        m = json.load(open(os.path.join(gen, "world_manifest.json")))
        n = int(m["grid"])
        g = Grid(float(m["size_m"]), n, float(m.get("cell_size_m", 256)))
        H = np.fromfile(os.path.join(gen, "heights.r32"), dtype="<f4").reshape(n, n)
        table = TR.load_table()
        worst, over, capped, total = 0.0, [], 0, 0
        for fn in sorted(glob.glob(os.path.join(gen, "cells", "*.json")))[::7]:
            d = json.load(open(fn))
            for asset, rows in d["instances"].items():
                if "/trees/" not in asset or not rows:
                    continue
                name = os.path.splitext(os.path.basename(asset))[0]
                if name not in table:
                    continue
                pts, h = table[name]
                fl = TR.floating(H, g, rows, pts)
                g0 = sample_bilinear(H, g, np.array([r[0] for r in rows]), np.array([r[2] for r in rows]))
                sink = g0 - np.array([r[1] for r in rows])
                cap = TR.SEAT_CAP_M + TR.SEAT_CAP_PER_M * h * np.array([r[4] for r in rows])
                held = sink >= cap - 0.02
                capped += int(held.sum())
                total += len(rows)
                bad = (fl > FLOAT_M) & ~held
                for r, f in zip(np.array(rows, dtype=object)[bad], fl[bad]):
                    over.append("%s at (%.0f, %.0f) %.2f m" % (name, r[0], r[2], f))
        self.assertGreater(total, 100)
        self.assertEqual(over[:10], [], "%d trees with a foot over the ground" % len(over))
        self.assertLess(capped / total, 0.03, "%d of %d trees held up by the cap" % (capped, total))


if __name__ == "__main__":
    unittest.main()
