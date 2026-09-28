"""The face's sliders (triage 39): morph targets on every head, written by lib/face_morphs.py and
face_morphs.py. Pure Python; the file checks skip when the parts have not been built.

The vault is shared by every face, and hair, hoods and helms are built once against it: no slider
may move it. What lies over the face (hair, beards, hoods) carries the same targets and goes with the
skin under it, so a jaw at its widest does not come through a beard or a hood."""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FORGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.dirname(FORGE))
sys.path.insert(0, FORGE)

import numpy as np

from forge.lib import glb, face_morphs as FM
import character_forge as CF
import face_morphs as tool

HEADS = os.path.join(CF.OUT_ROOT, "heads")


def _head_path(name):
    return os.path.join(HEADS, name, name + ".glb")


def _mesh_targets(path, pred):
    """{target name: (V glTF, delta)} for the first mesh whose name passes `pred`."""
    g, b = glb.read_glb(path)
    for mi, m in enumerate(g["meshes"]):
        if pred(m.get("name", "")):
            p = m["primitives"][0]
            V = glb.read_array(g, b, p["attributes"]["POSITION"])
            names = glb.morph_target_names(g, mi)
            return V, {n: glb.read_array(g, b, t["POSITION"]) for n, t in zip(names, p.get("targets", []))}, p
    return None, {}, None


class TestTheSliders(unittest.TestCase):
    """The recipe itself, on the default head's own mesh."""

    @classmethod
    def setUpClass(cls):
        if not os.path.exists(_head_path("default")):
            raise unittest.SkipTest("heads not built")
        cls.skel, cls.hs, cls.V, cls.T, cls.moves = tool.head_moves(_head_path("default"), "default")

    def test_every_slider_moves_the_face(self):
        for name in FM.TARGETS:
            m = np.linalg.norm(self.moves[name], axis=1).max()
            # a slider at its end is a person, not a caricature: a few millimetres, never a centimetre
            self.assertGreater(m, 0.0012, "%s hardly moves (%.1f mm)" % (name, m * 1000))
            self.assertLess(m, 0.0100, "%s moves %.1f mm" % (name, m * 1000))

    def test_the_vault_never_moves(self):
        for name in FM.TARGETS:
            self.assertLess(FM.vault_moves(self.skel, self.hs, self.V, self.moves[name]), 1e-4,
                            "%s moves the vault the hair is built on" % name)

    def test_the_neck_seam_never_moves(self):
        # the neck meets the body's collar at its foot: every slider leaves it where it is
        foot = self.V[:, 2] < self.V[:, 2].min() + 0.02
        for name in FM.TARGETS:
            self.assertLess(float(np.linalg.norm(self.moves[name][foot], axis=1).max()), 1e-5, name)

    def test_the_sliders_are_symmetric(self):
        # the left of the face moves as the right does, mirrored (asymmetry is its own target)
        from scipy.spatial import cKDTree
        mirror = self.V * np.array([-1.0, 1.0, 1.0])
        d, idx = cKDTree(self.V).query(mirror)
        ok = d < 2e-4
        for name in FM.TARGETS:
            M = self.moves[name]
            back = M[idx[ok]] * np.array([-1.0, 1.0, 1.0])
            self.assertLess(float(np.abs(back - M[ok]).max()), 0.0008, "%s is lopsided" % name)


class TestTheBuiltHeads(unittest.TestCase):
    def test_every_head_carries_them(self):
        names = [n for n in sorted(os.listdir(HEADS))] if os.path.isdir(HEADS) else []
        if not names:
            self.skipTest("heads not built")
        for name in names:
            path = _head_path(name)
            if not os.path.exists(path):
                continue
            self.assertTrue(tool.has_sliders(path), "%s has no face sliders: run face_morphs.py" % name)
            _, eye, _ = _mesh_targets(path, lambda n: n == "Eye_L")
            for t in ("eye_size", "eye_spacing"):
                self.assertIn(FM.target_name(t), eye, "%s's eye does not move with %s" % (name, t))
            _, _, p = _mesh_targets(path, lambda n: n.startswith("Head"))
            self.assertIn("TEXCOORD_1", p["attributes"], "%s has no face coordinates" % name)

    def test_the_womans_vault_is_left_alone_too(self):
        if not os.path.exists(_head_path("hawk_f")):
            self.skipTest("heads not built")
        skel, hs, V, T, moves = tool.head_moves(_head_path("hawk_f"), "hawk_f")
        for name, M in moves.items():
            self.assertLess(FM.vault_moves(skel, hs, V, M), 1e-4, name)


class TestWhatLiesOverTheFace(unittest.TestCase):
    """Every part over the face carries every target, and at a slider's end it has kept its place
    over the skin: the gap between a vertex near the face and the skin under it hardly changes."""

    @classmethod
    def setUpClass(cls):
        if not os.path.exists(_head_path("default")):
            raise unittest.SkipTest("heads not built")
        cls.headV, cls.head_moves_ = _mesh_targets(_head_path("default"), lambda n: n.startswith("Head"))[:2]

    def test_they_go_with_the_face(self):
        from scipy.spatial import cKDTree
        seen = 0
        # every mesh of a part: the shell, and the strand cards beside it (triage 47)
        meshes = [(kind, name, path, pred) for kind, name, path in tool.parts()
                  for pred in (lambda n: not n.endswith("_cards"), lambda n, c=name + "_cards": n == c)]
        for kind, name, path, pred in meshes:
            V, targets, _ = _mesh_targets(path, pred)
            if V is None:
                continue
            for t in FM.TARGETS:
                self.assertIn(FM.target_name(t), targets, "%s %s has no %s" % (kind, name, t))
            tree = cKDTree(self.headV)
            d0, i0 = tree.query(V)
            near = d0 < 0.012
            if not near.any():
                continue
            for t in FM.TARGETS:
                for w in (1.0, -1.0):
                    H = self.headV + self.head_moves_[FM.target_name(t)] * w
                    P = V + targets[FM.target_name(t)] * w
                    # the gap to the same skin the vertex lay over
                    gap0 = np.linalg.norm(V[near] - self.headV[i0[near]], axis=1)
                    gap1 = np.linalg.norm(P[near] - H[i0[near]], axis=1)
                    worst = float((gap0 - gap1).max())
                    self.assertLess(worst, 0.0025, "%s %s: %s at %+d closes on the skin by %.1f mm"
                                    % (kind, name, t, w, worst * 1000))
            seen += 1
        if seen == 0:
            self.skipTest("no parts built")


class TestTheGlbWriter(unittest.TestCase):
    def test_a_target_written_again_replaces_itself(self):
        path = _head_path("default")
        if not os.path.exists(path):
            self.skipTest("heads not built")
        g, b = glb.read_glb(path)
        mi = [i for i, m in enumerate(g["meshes"]) if m["name"].startswith("Head")][0]
        n = glb.morph_target_names(g, mi)
        count = g["accessors"][g["meshes"][mi]["primitives"][0]["attributes"]["POSITION"]]["count"]
        size0 = len(glb.compact(g, b))
        b = glb.add_sparse_morph_target(g, b, mi, "face_jaw_width", np.zeros((count, 3)))
        b = glb.compact(g, b)
        self.assertEqual(sorted(glb.morph_target_names(g, mi)), sorted(n))
        self.assertLessEqual(len(b), size0)
