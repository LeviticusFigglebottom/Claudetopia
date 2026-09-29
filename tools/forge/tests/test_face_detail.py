#!/usr/bin/env python3
"""The face's modelled detail reaches the lighting, and the marks of a life are where a face has them.

    python3 tools/forge/tests/test_face_detail.py

A head is decimated to a few thousand triangles, and its lids, nostrils and the line of its lips
live on in a normal map baked from the field itself (paint.sdf_detail_normal). These check the
bake's convention on a patch whose answer is known -- a bump on a plane, with u along +x and v
along +y: its normal tilts towards +u on the bump's +x slope and towards +v (OpenGL, green up) on
its +y slope -- and that the face marks put ruddiness on the cheeks and not the brow."""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import numpy as np

from forge.lib import rig, paint, body as bodylib


class _Bump:
    """A plane z=0 with a bump at the origin, smoothly joined."""

    def eval(self, P):
        plane = P[:, 2]
        bump = np.linalg.norm(P - np.array([0.0, 0.0, -0.004]), axis=1) - 0.007
        k = 0.002
        h = np.clip(0.5 + 0.5 * (bump - plane) / k, 0, 1)
        return bump * (1 - h) + plane * h - k * h * (1 - h)


class TestFaceDetail(unittest.TestCase):
    def test_the_detail_normal_is_in_the_mesh_tangent_frame(self):
        size = 64
        xs = np.linspace(-0.02, 0.02, size)
        X, Y = np.meshgrid(xs, xs)
        maps = {"pos": np.stack([X, Y, np.zeros_like(X)], axis=-1),
                "nrm": np.tile([0.0, 0.0, 1.0], (size, size, 1)), "mask": np.ones((size, size), bool),
                "tan": np.tile([1.0, 0.0, 0.0], (size, size, 1)), "bit": np.tile([0.0, 1.0, 0.0], (size, size, 1))}
        n = paint.sdf_detail_normal(_Bump(), maps) * 2.0 - 1.0
        c = size // 2
        east, north, flat = n[c, c + 6], n[c + 6, c], n[c, 2]
        self.assertGreater(east[0], 0.2)
        self.assertLess(abs(east[1]), 0.06)
        self.assertGreater(north[1], 0.2)
        self.assertLess(abs(north[0]), 0.06)
        self.assertGreater(flat[2], 0.99)

    def test_ruddiness_is_on_the_cheeks_not_the_brow(self):
        skel = rig.Skeleton(rig.Proportions())
        L = bodylib.head_landmarks(skel)
        rgb, alpha = paint.face_marks(L, seed=3)
        s = L["s"]
        cheek = np.array([[L["eye_x"] * 1.45, L["face_y"] + 0.020 * s, L["eye_z"] - 0.046 * s]])
        brow = np.array([[0.0, L["face_y"], L["brow_z"] + 0.030 * s]])
        up = np.array([[0.0, -1.0, 0.0]])
        self.assertGreater(float(rgb(cheek, up)[0, 1]), 0.4)
        self.assertLess(float(rgb(brow, up)[0, 1]), 0.2)
        # the forehead takes the sun
        self.assertGreater(float(alpha(brow, up)[0, 0]), 0.5)


if __name__ == "__main__":
    unittest.main()


class TestTheFacesForm(unittest.TestCase):
    """Item 45: the heads were low in detail -- a round tube of a nose with a ball each side whose
    ends read as a ring through it, lips as two sausages, the philtrum's ridges hanging below the
    nose as a drop. The forms are anatomy's now; these check the ones a player reads first."""

    @classmethod
    def setUpClass(cls):
        cls.faces = {}
        for fem in (0.0, 1.0):
            skel = rig.Skeleton(rig.Proportions(feminine=fem))
            cls.faces[fem] = (bodylib.head_landmarks(skel), bodylib.head_scene(skel, flat=True))

    @staticmethod
    def _front(sc, x, z, y0=-0.16, y1=0.0):
        ys = np.linspace(y0, y1, 1601)
        d = sc.eval(np.stack([np.full_like(ys, x), ys, np.full_like(ys, z)], axis=1))
        return float(ys[int(np.argmax(d < 0.0))])

    def test_the_nostrils_open_downwards_and_hide_from_the_front(self):
        for fem, (L, sc) in self.faces.items():
            s, tip = L["s"], L["nose_tip"]
            nw = 1 - 0.17 * fem
            # a probe coming up from under the nose, behind the tip, goes further up into a nostril
            # than beside it under the columella: the nostril is a hollow that opens downwards
            zs = np.linspace(tip[2] - 0.030 * s, tip[2] + 0.010 * s, 801)

            def hit(x, y):
                d = sc.eval(np.stack([np.full_like(zs, x), np.full_like(zs, y), zs], axis=1))
                return float(zs[int(np.argmax(d < 0.0))]) if (d < 0).any() else -1.0
            deepest = max(hit(0.0050 * s, float(tip[1]) + dy * s) - hit(0.0, float(tip[1]) + dy * s)
                          for dy in (0.002, 0.004, 0.006, 0.008))
            self.assertGreater(deepest, 0.003 * s,
                               "no nostril opens under the %s nose" % ("woman's" if fem else "man's"))
            # seen from the front at the nostril's height, the tip and the wings are what show
            self.assertLess(self._front(sc, 0.0055 * s, tip[2] - 0.0076 * nw * s), float(tip[1]) + 0.004 * s,
                            "the nostril is seen from the front")

    def test_the_nose_has_wings_not_balls(self):
        L, sc = self.faces[0.0]
        s, tip = L["s"], L["nose_tip"]
        # across the base of the nose, the wings stand forward of the cheek beside them, and there is
        # no gap between the wing and the tip (the old balls stood apart with the cheek between)
        z = tip[2] - 0.005 * s
        xs = np.linspace(0.0, 0.030, 31) * s
        ys = np.array([self._front(sc, x, z) for x in xs])
        wing = ys[(xs > 0.008 * s) & (xs < 0.016 * s)]
        cheek = ys[xs > 0.024 * s]
        self.assertLess(float(wing.max()), float(cheek.min()) - 0.004 * s, "no wings on the nose")
        steps = np.diff(ys[xs < 0.016 * s])
        self.assertLess(float(-steps.min()), 0.006 * s, "a notch between the tip and its wing")

    def test_the_lips_have_a_red_and_an_edge(self):
        for fem, (L, sc) in self.faces.items():
            s, mz = L["s"], L["mouth_z"]
            upper = self._front(sc, 0.0, mz + 0.0035 * s)
            skin = self._front(sc, 0.0, mz + 0.0120 * s)
            lower = self._front(sc, 0.0, mz - 0.0050 * s)
            under = self._front(sc, 0.0, mz - 0.0150 * s)
            self.assertLess(upper, skin - 0.0010 * s, "the upper lip stands no prouder than the skin over it")
            self.assertLess(lower, under - 0.0020 * s, "no groove under the lower lip")
            # the philtrum: the middle of the upper lip's skin a little behind the columns either side
            z = 0.5 * (mz + 0.012 * s + L["nose_base_z"])
            self.assertGreater(self._front(sc, 0.0, z), self._front(sc, 0.0048 * s, z) - 0.0002 * s,
                               "no philtrum")

    def test_the_built_heads_are_in_their_budget(self):
        import json
        root = os.path.join(ROOT, "game", "assets", "models", "characters", "heads")
        if not os.path.isdir(root):
            self.skipTest("heads not built")
        for name in sorted(os.listdir(root)):
            meta = os.path.join(root, name, name + ".meta.json")
            if os.path.exists(meta):
                tris = json.load(open(meta))["tris"][0]
                self.assertLessEqual(tris, 20000, "%s: %d triangles" % (name, tris))
