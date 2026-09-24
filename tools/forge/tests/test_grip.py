#!/usr/bin/env python3
"""The closed hand (forge/lib/grip.py): a fist round the haft, and the game told where the haft is.

    python3 tools/forge/tests/test_grip.py

Pure numpy on the forge's own skeleton; it needs no Blender, no Godot and no built rig."""
from __future__ import annotations

import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import numpy as np

from forge.lib import grip, rig
from forge.lib.rig import Skeleton

MODEL_GD = os.path.join(ROOT, "game", "actors", "shared", "humanoid_model.gd")


def _hand_points(skel: Skeleton, side: str) -> np.ndarray:
    """Points along each finger's and the thumb's open centre line, and a sheet of palm points."""
    fingers, thumb, _ = grip.chains(skel, 1.0, side)
    pts = []
    for ch in fingers + [thumb]:
        J = grip.joints(ch, ch.open)
        for k in range(3):
            for f in np.linspace(0.1, 1.0, 5):
                pts.append(J[k] + (J[k + 1] - J[k]) * f)
    wr, d, fwd, up = grip.hand_frame(skel, side)
    # the middle of the palm: clear of the thumb's heel, which goes with the thumb
    for a in np.linspace(0.03, 0.07, 4):
        for b in np.linspace(-0.022, 0.0, 4):
            pts.append(wr + d * a + fwd * b)
    return np.array(pts)


class TestGrip(unittest.TestCase):
    def setUp(self):
        self.skel = Skeleton(rig.Proportions())

    def test_the_fist_closes_round_the_haft(self):
        """Every fingertip ends up on the haft's far side, near it; the palm does not move."""
        for side in ("L", "R"):
            fingers, thumb, _ = grip.chains(self.skel, 1.0, side)
            c, axis = grip.haft(self.skel, side)
            for ch in fingers:
                ang = grip.fist_angles(ch, c, axis, grip.HAFT_R, 1.0)
                tip_open = grip.joints(ch, ch.open)[3]
                tip = grip.joints(ch, ang)[3]
                v_open, v = tip_open - c, tip - c
                rho = np.linalg.norm(v - np.dot(v, axis) * axis)
                self.assertLess(rho, grip.HAFT_R + ch.radius + 0.012,
                                "%s %s: the tip stands %.3f m off the haft" % (side, ch.name, rho))
                self.assertGreater(rho, grip.HAFT_R * 0.8, "%s %s: the tip is inside the haft" % (side, ch.name))
                self.assertGreater(sum(ang), 120.0, "%s %s curls only %.0f degrees" % (side, ch.name, sum(ang)))
            P = _hand_points(self.skel, side)
            Q = grip.grip_positions(self.skel, 1.0, P, side)
            moved = np.linalg.norm(Q - P, axis=1)
            self.assertTrue((moved[-16:] < 1e-9).all(), "%s: the palm moved" % side)
            self.assertGreater(float(moved[:-16].max()), 0.05, "%s: the fingers did not close" % side)

    def test_the_hands_mirror(self):
        """The left fist is the right one mirrored."""
        P = _hand_points(self.skel, "R")
        Q = grip.grip_positions(self.skel, 1.0, P, "R")
        m = np.array([-1.0, 1.0, 1.0])
        Q_l = grip.grip_positions(self.skel, 1.0, P * m, "L")
        self.assertLess(float(np.abs(Q_l - Q * m).max()), 1e-6)

    def test_the_game_knows_where_the_haft_is(self):
        """HumanoidModel.GRIP_OFFSET is the forge's grip_offset: a held thing put there sits in the fist."""
        text = open(MODEL_GD).read()
        m = re.search(r'const GRIP_OFFSET := \{"R": Vector3\(([^)]*)\), "L": Vector3\(([^)]*)\)\}', text)
        self.assertIsNotNone(m, "HumanoidModel has no GRIP_OFFSET")
        for side, got in (("R", m.group(1)), ("L", m.group(2))):
            want = grip.grip_offset(self.skel, side)
            gd = np.array([float(x) for x in got.split(",")])
            self.assertLess(float(np.abs(gd - want).max()), 2e-4,
                            "GRIP_OFFSET[%s] is %s; the forge's fist is round %s" % (side, gd, np.round(want, 4)))


if __name__ == "__main__":
    unittest.main()
