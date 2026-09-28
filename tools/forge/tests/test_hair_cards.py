"""Hair cards (triage 47): the strand atlas, and the cards written into each hair style and beard.
Pure Python; the file checks skip for a part whose cards have not been built.

What must hold: the atlas is strands with gaps (not a solid), every card lies on or over the scalp
and never inside it, a close cut's cards stand no further off the head than its shell (so it still
sits under a hood), every strand direction is a direction, each kind of geometry is mapped where
the shader looks for it, and a beard's cards fit every jaw the shell fits."""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FORGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.dirname(FORGE))
sys.path.insert(0, FORGE)

import numpy as np

from forge.lib import glb, rig, cloth, hair_cards as HC
import character_forge as CF
import hair_cards as tool


def _to_forge(v):
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)


def _cards(path, name):
    g, b = glb.read_glb(path)
    for mi, m in enumerate(g["meshes"]):
        if m.get("name") == name + "_cards":
            a = m["primitives"][0]["attributes"]
            out = {k: glb.read_array(g, b, v) for k, v in a.items()}
            out["targets"] = glb.morph_target_names(g, mi)
            out["tris"] = glb.read_array(g, b, m["primitives"][0]["indices"]).astype(int).reshape(-1, 3)
            return out
    return None


def _built():
    for sub, table in (("hair", cloth.HAIR_STYLES), ("beards", cloth.BEARD_STYLES)):
        for name in table:
            if name in tool.NO_CARDS:
                continue
            path = os.path.join(tool.PARTS, sub, name, name + ".glb")
            if os.path.exists(path):
                c = _cards(path, name)
                if c is not None:
                    yield sub, name, path, c


class TestTheAtlas(unittest.TestCase):
    def test_strands_with_gaps_rooted_at_the_top(self):
        a = HC.strand_atlas(h=128)
        self.assertEqual(a.shape, (128, HC.ATLAS_W, 4))
        cw = HC.CELL_PX
        for c in range(HC.CELLS):
            A = a[:, c * cw:(c + 1) * cw, 3]
            cover = A.mean()
            self.assertGreater(cover, 0.03, "cell %d is empty" % c)
            self.assertLess(cover, 0.9, "cell %d is a solid, not strands" % c)
            # thinner at the tips than at the roots
            self.assertGreater(A[: 128 // 3].mean(), A[-128 // 8:].mean(), "cell %d does not thin to its tips" % c)

    def test_the_grain_tiles(self):
        g = HC.grain_tile(64)
        # opposite edges continue each other (a tile's seam is no harder than its inside)
        seam = np.abs(g[0, :, 1] - g[-1, :, 1]).mean()
        inside = np.abs(np.diff(g[:, :, 1], axis=0)).mean()
        self.assertLess(seam, inside * 3.0)


class TestTheCards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parts = list(_built())
        if not cls.parts:
            raise unittest.SkipTest("no cards built")
        cls.skel = CF.variant_skeleton(rig.Proportions())
        cls.head = cloth.head_field(cls.skel)

    def test_nothing_inside_the_scalp(self):
        for sub, name, path, c in self.parts:
            P = _to_forge(c["POSITION"])
            d = self.head.eval(P)
            inside = (d < -0.0015).mean()
            self.assertLess(inside, 0.01, "%s: %.1f%% of its cards are inside the head" % (name, inside * 100))

    def test_close_cuts_stay_under_a_hood(self):
        for sub, name, path, c in self.parts:
            if name not in HC.CLOSE:
                continue
            reach = tool._shell_reach(path, name, self.head)
            d = self.head.eval(_to_forge(c["POSITION"]))
            self.assertLess(float(np.percentile(d, 99)), reach + 0.003,
                            "%s: its cards stand %.1f mm off, its shell %.1f" % (name, np.percentile(d, 99) * 1000, reach * 1000))

    def test_what_the_shader_reads(self):
        for sub, name, path, c in self.parts:
            t = c["TANGENT"][:, :3]
            self.assertLess(np.abs(np.linalg.norm(t, axis=1) - 1.0).max(), 0.02, "%s: a strand direction is not one" % name)
            u = c["TEXCOORD_0"][:, 0]
            cap = u >= 2.0
            # every triangle is one kind: a cap triangle straying under u 2 is drawn as a card
            T = c["tris"]
            kinds = np.floor(np.clip(u, 0.0, 2.0))[T]
            self.assertTrue((kinds.min(axis=1) == kinds.max(axis=1)).all(), "%s mixes kinds in a triangle" % name)
            self.assertTrue(cap.any(), "%s has no cap" % name)
            self.assertTrue((u < 1.0).any(), "%s has no cards" % name)
            uv2 = c["TEXCOORD_1"]
            self.assertTrue(((uv2 >= -1e-4) & (uv2 <= 1.0001)).all(), "%s: root-to-tip or density out of 0..1" % name)
            # the cap fades: some of it thins out past the hairline
            self.assertTrue((uv2[cap, 1] < 0.5).any(), "%s: the cap does not fade at its edge" % name)
            self.assertIn("face_jaw_width", c["targets"], "%s: the cards do not follow the face" % name)
            if sub == "beards":
                for h in CF.HEAD_PRESETS:
                    if h != "default":
                        self.assertIn(h, c["targets"], "%s: the cards do not fit the %s jaw" % (name, h))

    def test_shaved_sides_are_stubble_not_a_crop(self):
        for sub, name, path, c in self.parts:
            if name != "shaved_sides":
                continue
            P = _to_forge(c["POSITION"])
            u = c["TEXCOORD_0"][:, 0]
            side = (u >= 2.0) & (np.abs(P[:, 0]) > 0.065)
            self.assertTrue(side.any())
            dens = c["TEXCOORD_1"][side, 1]
            self.assertLess(float(np.median(dens)), 0.7, "the shaved sides are drawn full")
            self.assertGreater(float(np.median(dens)), 0.2, "the shaved sides are bare")
            cards = (u < 1.0) & (np.abs(P[:, 0]) > 0.07) & (P[:, 2] < 1.62)
            self.assertLess(cards.mean(), 0.02, "cards grow on the shaved sides")


if __name__ == "__main__":
    unittest.main()
