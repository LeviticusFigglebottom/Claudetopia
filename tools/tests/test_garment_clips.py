#!/usr/bin/env python3
"""The legs stay inside the clothes when the wearer runs (playtest 5: "running legs clip the
clothes"), measured on the GLBs the game ships, posed by the rig's own clips.

    python3 tools/tests/test_garment_clips.py     # or: python3 -m pytest tools/tests/test_garment_clips.py

Two things were wrong, and each is held here:
- Every skirt (the tunic's, the skirt, dress, robe, wrap skirt, kilt and coat) is a solid loft
  cut off by a plane at its hem, and a solid is meshed closed: each had a flat floor across its
  bottom with the legs standing through it. In a stride the floor swung up with the thighs and
  the legs cut through it. The forge now drops it (cloth.Garment.open_below).
- The kilt gave the hips 45 % of the thighs' swing at the top and 10 % at the hem, so a running
  thigh came out through its front. It goes with the thighs whole now, as the skirts do, and
  the robe, the wrap skirt and the coat go with the shins below the knee as well.

tools/forge/preview/clipcheck.py is the measuring tool: a body vertex under the cloth at rest
that is drawn outside it in a pose has come through.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "forge" / "preview"))

import clipcheck as C  # noqa: E402

SKIRTS = ["tunic", "skirt", "dress", "robe", "wrap_skirt", "kilt", "coat"]
CHILD_SKIRTS = ["tunic_child", "dress_child"]
LEGS = ["UpperLeg", "LowerLeg", "Foot", "Hips"]
# (part, worn over it, most leg vertices drawn through it at any of 8 samples of the Run or the
# Sprint). Measured on the parts built at b1517550 (Run / Sprint): kilt 2/2, skirt 3/3, dress
# 3/2, robe 7/14, wrap skirt 10/25, tunic over trousers 3/5, coat over trousers 5/8. Before:
# the kilt 97/115 and the tunic over trousers 35/58, most of it through the floor under the hem.
# The narrow wrap skirt and the robe to the ankle are what is left: a shin at the full stretch of
# the Sprint still comes out under a raised knee.
STRIDES = [("kilt", "", 6), ("skirt", "", 6), ("dress", "", 6), ("robe", "", 18), ("wrap_skirt", "", 30),
           ("tunic", "trousers", 8), ("coat", "trousers", 12)]


def floor_area(part: "C.Part", tol: float = 0.005) -> float:
    """m^2 of faces facing down within `tol` of the part's lowest point: a floor under a skirt."""
    V, I = part.V, part.I
    n = C.tri_normals(V, I, part.N)
    A, B, Cc = V[I[:, 0]], V[I[:, 1]], V[I[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(B - A, Cc - A), axis=1)
    low = (V[I, 1] < V[:, 1].min() + tol).all(axis=1) & (n[:, 1] < -0.5)
    return float(area[low].sum())


class SkirtsAreOpen(unittest.TestCase):
    def test_no_floor_under_a_skirt(self):
        bad = []
        for name in SKIRTS + CHILD_SKIRTS:
            path = C.CHARS / "clothing" / name / (name + ".glb")
            if not path.exists():
                continue
            a = floor_area(C.Part(path))
            if a > 0.003:
                bad.append("%s %.4f m2" % (name, a))
        self.assertEqual(bad, [], "a floor across the hem, with the legs standing through it: %s" % bad)


class AStrideStaysInside(unittest.TestCase):
    rig = None
    body = None

    @classmethod
    def setUpClass(cls):
        cls.rig = C.Rig()
        cls.body = C.Part(C.RIG, want={"Body"})

    def test_run_and_sprint(self):
        bad = []
        for name, under, most in STRIDES:
            inner = C.Merged([self.body, C.Part(C.part_path(under))]) if under else self.body
            part = C.Part(C.part_path(name))
            for clip in ("Run", "Sprint"):
                _, _, samples = C.measure(self.rig, inner, part, clip, 8, 0.002, only=LEGS)
                worst = max(samples, key=lambda s: len(s["through"]))
                if len(worst["through"]) > most:
                    bad.append("%s%s in %s@%.2f: %d leg vertices through (at most %d)"
                               % (name, " over " + under if under else "", clip, worst["t"],
                                  len(worst["through"]), most))
        self.assertEqual(bad, [], "\n".join(bad))


if __name__ == "__main__":
    unittest.main()
