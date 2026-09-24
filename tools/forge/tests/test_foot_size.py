#!/usr/bin/env python3
"""The modelled foot is a real foot's length, whatever the skeleton's toe bone says.

    python3 tools/forge/tests/test_foot_size.py

Measured on the body's own field: the extent of the left foot along the ground, heel to toe."""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import numpy as np

from forge.lib import rig, sdf, body as bodylib


class TestFootSize(unittest.TestCase):
    def test_a_foot_is_a_foot_long(self):
        skel = rig.Skeleton(rig.Proportions())
        st = bodylib.BodyStyle()
        foot = sdf.group(bodylib._foot_parts(skel, st, "L"))
        an = skel.J["Foot.L"]
        ys = np.arange(-0.40, 0.20, 0.002)
        zs = np.arange(0.0, 0.06, 0.004)
        Y, Z = np.meshgrid(ys, zs, indexing="ij")
        P = np.stack([np.full(Y.size, an[0]), Y.ravel(), Z.ravel()], axis=1)
        inside = (foot.fn(P) < 0).reshape(Y.shape).any(axis=1)
        length = float(ys[inside].max() - ys[inside].min())
        # a man of 1.78 m has a foot of 26-27 cm; the old one was 34
        self.assertGreater(length, 0.24, "the foot is %.1f cm long" % (length * 100))
        self.assertLess(length, 0.275, "the foot is %.1f cm long: a clown's" % (length * 100))


if __name__ == "__main__":
    unittest.main()
