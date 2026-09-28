#!/usr/bin/env python3
"""The ground round the cliff pieces is painted rock and rubble, tinted to their rock
(worldgen.rock_paint; triage 42's leftovers: rock met grass with a hard edge, and the bare face
between two pieces read as dark earth).

    python3 -m pytest tools/world/tests/test_rock_paint.py
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import cliff_seat as CS  # noqa: E402
from worldgen import output as OUT  # noqa: E402
from worldgen import rock_paint as RP  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.surface import SLOTS  # noqa: E402

GRASS = SLOTS["vale_grass"]
GRANITE = SLOTS["granite"]


class RockPaint(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        name = "skerrow_cliff_face_a"
        d = os.path.join(cls.tmp.name, "game", "assets", "models", "rocks", name)
        os.makedirs(d)
        with open(os.path.join(d, name + ".meta.json"), "w") as f:
            json.dump({"bounds": {"min": [-10.0, 0.0, -4.0], "max": [10.0, 16.0, 4.5], "height": 16.0}}, f)
        from PIL import Image
        Image.fromarray(np.full((16, 16, 3), 150, np.uint8)).save(os.path.join(d, name + "_albedo.png"))
        cls.asset = "res://assets/models/rocks/%s/%s.glb" % (name, name)
        cls.g = g = Grid(512.0, 256)
        X, Z = g.mesh(np.float64)
        X = np.broadcast_to(X, (g.n, g.n))
        Z = np.broadcast_to(Z, (g.n, g.n))
        # a 60-degree face 50 m high (top at z = 0, foot at z = 29) onto a meadow
        cls.H = np.clip(50.0 - math.tan(math.radians(60.0)) * Z, 0.0, 50.0).astype(np.float32)
        hs = CS.smoothed_grad(cls.H, g)
        prof = CS.profile(cls.asset, cls.tmp.name)
        cls.rows = []
        for x in (-30.0, 0.0):
            row = CS._laid(cls.asset, prof, x, 24.0, 0.8, 0.0, cls.H, g, hs)
            new, _ = CS.seat(row, prof, cls.H, g, hs)
            cls.rows.append(new)
        cls.buckets = {(1, 1): {cls.asset: cls.rows}}
        n = g.n
        cls.base = np.where(np.hypot(*hs) > 1.0, GRANITE, GRASS).astype(np.uint8)
        cls.overlay = cls.base.copy()
        cls.blend = np.zeros((n, n), np.uint8)
        cls.colour = np.full((n, n, 4), 240, np.uint8)
        cls.w = RP.weights(cls.buckets, cls.H, g, cls.tmp.name, 1)
        cls.painted = RP.paint_control(cls.base, cls.overlay, cls.blend, cls.w)
        RP.paint_colour(cls.colour, cls.w)
        top = np.where(cls.blend >= 128, cls.overlay, cls.base)
        cls.top = top

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def _at(self, x, z):
        j, i = self.g.clamp_index(*self.g.to_tex(x, z))
        return int(i), int(j)

    def test_rock_under_the_pieces(self):
        prof = CS.profile(self.asset, self.tmp.name)
        for r in self.rows:
            ii, jj = CS.raster(CS.footprint(r, prof, True), self.g)
            self.assertGreater(ii.size, 20)
            self.assertGreater(float((self.top[ii, jj] == RP.CRAG).mean()), 0.95)

    def test_the_gap_between_two_pieces_reads_as_rock(self):
        # half way between the pieces (x = -15), on the face
        i, j = self._at(-15.0, 22.0)
        self.assertEqual(self.top[i, j], RP.CRAG)
        # and the face far from any rock keeps its own texture
        i, j = self._at(200.0, 22.0)
        self.assertEqual(self.top[i, j], GRANITE)

    def test_rubble_below_the_lower_edge_fading_into_the_grass(self):
        # the pieces' lower edges are 2-3 m up the face, whose foot is at z = 29; on the meadow
        # below, rubble, thinning out
        def talus(z):
            i, j = self._at(0.0, z)
            v = self.w["talus"][(self.w["i"] == i) & (self.w["j"] == j)]
            return float(v[0]) if v.size else 0.0
        vals = [talus(z) for z in (30.0, 33.0, 36.0, 45.0)]
        self.assertGreater(vals[0], 0.3, vals)
        self.assertGreater(vals[0], vals[2] - 0.05, vals)
        self.assertEqual(vals[3], 0.0, vals)
        # the grass far off is left alone, colour and all
        i, j = self._at(0.0, 120.0)
        self.assertEqual(self.top[i, j], GRASS)
        self.assertTrue((self.colour[i, j] == 240).all())

    def test_tinted_to_the_rock(self):
        # the crag under a piece draws at the piece's rock as the game draws it, times CRAG_TONE
        crag_draw, _t = RP.slot_draws()
        i, j = self._at(0.0, 23.0)
        mult = RP._lin(self.colour[i, j, :3].astype(np.float32) / 255.0)
        want = RP.rock_tint(self.asset, self.tmp.name) * RP.CRAG_TONE / crag_draw
        self.assertLess(float(np.abs(mult - np.clip(want, 0, 1)).max()), 0.03)
        self.assertEqual(int(self.colour[i, j, 3]), 240)          # the roughness is kept

    def test_tinted_to_the_rock_as_the_game_draws_it(self):
        # the painted stone's value range (RockPaint: 0.028-0.24), not the forge's picture (the
        # Skerrow's at a third, Cinderlea's at a fiftieth)
        for name in ("skerrow_cliff_face_b", "cinderlea_cliff_face_c", "hearthvale_cliff_ledge_a"):
            t = RP.rock_tint("res://assets/models/rocks/%s/%s.glb" % (name, name), REPO)
            self.assertTrue(0.027 <= float(t.mean()) <= 0.241, (name, t))

    def test_rubble_on_dark_ground_is_darker_than_the_rock(self):
        # talus on the ash: between the rock and the ash, not a pale ring round the scarp
        w = {"i": np.array([0]), "j": np.array([0]), "crag": np.array([0.0], np.float32),
             "talus": np.array([0.9], np.float32), "tint": np.array([[0.2, 0.2, 0.2]], np.float32)}
        base, over, bl = (np.full((1, 1), SLOTS["ash_soil"], np.uint8), np.full((1, 1), SLOTS["ash_soil"], np.uint8),
                          np.zeros((1, 1), np.uint8))
        RP.paint_control(base, over, bl, w)
        col = np.full((1, 1, 4), 255, np.uint8)
        RP.paint_colour(col, w)
        drawn = RP._lin(col[0, 0, :3].astype(np.float32) / 255.0) * RP.slot_draws()[1]
        ash = RP.ground_draws()[SLOTS["ash_soil"]]
        self.assertLess(float(drawn.mean()), 0.2 * RP.TALUS_TONE)
        self.assertGreater(float(drawn.mean()), float(ash.mean()))

    def test_the_control_words_keep_their_other_bits(self):
        base = np.array([[3, 7]], np.uint8)
        over = np.array([[5, 1]], np.uint8)
        bl = np.array([[10, 200]], np.uint8)
        c = OUT.pack_control(base, over, bl, nav=np.array([[1, 0]], np.uint8)) | np.uint32(0x3F0)
        b2, o2, l2 = RP.unpack_control(c)
        self.assertTrue((b2 == base).all() and (o2 == over).all() and (l2 == bl).all())
        again = RP.repack_control(c, np.array([[21, 22]]), o2, l2)
        self.assertTrue(((again & 0x3FFF) == (c & 0x3FFF)).all())
        self.assertEqual(RP.unpack_control(again)[0].tolist(), [[21, 22]])

    def test_slot_values_in_step_with_the_importer(self):
        src = open(os.path.join(REPO, "game", "tools_gd", "import_terrain.gd"), encoding="utf-8").read()
        for name, value in (("crag", RP.CRAG_VALUE), ("talus", RP.TALUS_VALUE)):
            m = re.search(r'\{"name": "%s", "tile_m": [\d.]+, "value": ([\d.]+)' % name, src)
            self.assertIsNotNone(m, name)
            self.assertAlmostEqual(float(m.group(1)), value)
        names = re.findall(r'\{"name": "(\w+)"', src)
        self.assertEqual(names.index("crag"), RP.CRAG)
        self.assertEqual(names.index("talus"), RP.TALUS)


if __name__ == "__main__":
    unittest.main()
