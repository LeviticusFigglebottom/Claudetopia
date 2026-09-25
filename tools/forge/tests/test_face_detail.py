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
