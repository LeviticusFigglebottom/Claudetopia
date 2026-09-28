"""The woman's body, her faces and her clothes' fit (triage 2026-09-27 item 21). Pure Python.

Every generic body the forge made was a man's. The woman's is `BODY_VARIANTS["woman"]`: her shape
in the mesh (body_scene's `feminine`) on the default rig's joints exactly, so every clip and every
garment works on her; each face again as `<name>_f`; and every grown garment carries a morph target
fitting it to her (`character_forge ALWAYS_FITTED`, `fit_parts.py`). The file checks skip when the
parts have not been built."""
from __future__ import annotations

import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FORGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.dirname(FORGE))
sys.path.insert(0, FORGE)

import numpy as np

from forge.lib import rig, glb, body as bodylib
from forge.lib.rig import Skeleton
import character_forge as CF

CHARS = CF.OUT_ROOT
WOMAN_GLB = os.path.join(CHARS, "bodies", "woman", "woman.glb")
RIG_GLB = os.path.join(CHARS, "humanoid_rig", "humanoid_rig.glb")


def woman_skeleton() -> Skeleton:
    return CF.variant_skeleton(rig.Proportions.from_dict(CF.BODY_VARIANTS["woman"]))


def inverse_binds(path: str) -> dict:
    """Joint name -> inverse bind matrix, off a GLB's first skin."""
    g, b = glb.read_glb(path)
    skin = g["skins"][0]
    rows = glb.read_accessor(g, b, skin["inverseBindMatrices"]) if "inverseBindMatrices" in skin else None
    if rows is None:
        return {}
    return {g["nodes"][j].get("name"): np.asarray(rows[i], float).reshape(4, 4) for i, j in enumerate(skin["joints"])}


class TestTheWomansBody(unittest.TestCase):

    def test_she_is_on_the_default_rigs_joints(self):
        # feminine moves the hips and the shoulders in joint_positions; her body must not, or it is
        # a skeleton of its own and every clip lands on the wrong shoulders
        base = Skeleton(rig.Proportions())
        her = woman_skeleton()
        self.assertEqual(her.props.feminine, 1.0, "the mesh is not shaped as a woman's")
        for name in base.J:
            self.assertLess(float(np.abs(base.J[name] - her.J[name]).max()), 1e-9, name)

    def test_her_shape_is_a_womans(self):
        base = Skeleton(rig.Proportions())
        her = woman_skeleton()
        man = bodylib.body_scene(base)
        woman = bodylib.body_scene(her)
        J = base.J
        # in front of the chest, a little below it: inside her, outside him
        front = bodylib.bust_shape(her, 1, 1.0, 1.0)["apex"] + np.array([0.0, 0.006, 0.0])
        self.assertLess(float(woman.eval(front[None])[0]), 0.0, "no bust")
        self.assertGreater(float(man.eval(front[None])[0]), 0.0)
        # wider at the hip, narrower at the waist
        hip = np.array([[0.150, 0.015, J["UpperLeg.L"][2] + 0.03]])
        self.assertLess(float(woman.eval(hip)[0]), float(man.eval(hip)[0]), "her hips are no wider")
        waist = np.array([[0.118, 0.0, J["Spine"][2] + 0.02]])
        self.assertGreater(float(woman.eval(waist)[0]), float(man.eval(waist)[0]), "her waist is no narrower")
        # and a man's clothes are fitted over no drape
        self.assertEqual(bodylib.garment_drape(base), [])
        self.assertTrue(bodylib.garment_drape(her))

    def test_the_built_body_is_skinned_to_the_rigs_bones(self):
        if not (os.path.exists(WOMAN_GLB) and os.path.exists(RIG_GLB)):
            self.skipTest("the woman's body or the rig has not been built")
        hers, rigs = inverse_binds(WOMAN_GLB), inverse_binds(RIG_GLB)
        self.assertTrue(hers, "her body has no skin")
        for name, m in hers.items():
            if name in rigs:
                self.assertLess(float(np.abs(m - rigs[name]).max()), 1e-4, "%s is not the rig's bone" % name)
        meta = json.load(open(WOMAN_GLB.replace(".glb", ".meta.json")))
        self.assertEqual(meta["params"]["proportions"]["feminine"], 1.0)
        self.assertGreater(glb.mesh_triangles(WOMAN_GLB), 5000, "a body with no mesh in it")
        self.assertLessEqual(meta["tris"][0], 12000, "over the body's budget")


class TestHerBust(unittest.TestCase):
    """Item 46: the bust was one ball each side, high, close in, and blended so wide that the two
    filled the valley between them and stood out as one shelf. It is placed and shaped as anatomy
    has it now, and sized by a slider the body and her clothes carry as morph targets."""

    def setUp(self):
        self.her = woman_skeleton()
        style = CF.variant_style("woman")
        self.scene = bodylib.body_scene(self.her, style)
        td = self.her.props.bulk * (0.88 + 0.34 * self.her.props.build)
        self.shape = {sx: bodylib.bust_shape(self.her, sx, td, 1.0) for sx in (1, -1)}

    def _front(self, x, z, scene=None):
        """The body's front along a line from before her, at (x, z)."""
        sc = scene or self.scene
        ys = np.linspace(-0.30, 0.0, 1501)
        P = np.stack([np.full_like(ys, x), ys, np.full_like(ys, z)], axis=1)
        d = sc.eval(P)
        return float(ys[int(np.argmax(d < 0.0))])

    def test_it_sits_where_a_bust_does(self):
        H = self.her.props.height
        a, b = self.shape[1]["apex"], self.shape[-1]["apex"]
        self.assertTrue(0.70 * H < a[2] < 0.74 * H, "the bust point at %.2f of her height" % (a[2] / H))
        self.assertTrue(0.15 < a[0] - b[0] < 0.20, "the bust points %.0f mm apart" % ((a[0] - b[0]) * 1000))
        # the apex is where the body is furthest forward over the chest
        y_apex = self._front(a[0], a[2])
        self.assertLess(y_apex, self._front(a[0], a[2] + 0.05) - 0.010, "no slope above the bust point")
        self.assertLess(y_apex, self._front(a[0], a[2] - 0.05) - 0.010, "no fold under the bust")

    def test_the_valley_between_is_not_filled(self):
        a = self.shape[1]["apex"]
        y_apex = self._front(a[0], a[2])
        y_mid = self._front(0.0, a[2])
        self.assertGreater(y_mid - y_apex, 0.005, "the breastbone is %.0f mm behind the bust points: a shelf"
                           % ((y_mid - y_apex) * 1000))

    def test_the_top_is_a_slope_not_a_ledge(self):
        a = self.shape[1]["apex"]
        zs = np.linspace(a[2] + 0.10, a[2], 21)
        ys = np.array([self._front(a[0], z) for z in zs])
        steps = np.diff(ys)
        # going down, the front comes steadily forward: never back, and never a step
        self.assertLessEqual(float(steps.max()), 0.0015, "the upper pole dips")
        self.assertLess(float(-steps.min()), 0.012, "a ledge of %.0f mm in 5 mm" % (-steps.min() * 1000))

    def test_the_slider_sizes_it(self):
        a = self.shape[1]["apex"]
        ys = []
        for size in (0.8, 1.0, 1.2):
            st = CF.variant_style("woman")
            st.bust = size
            ys.append(self._front(a[0], a[2], bodylib.body_scene(self.her, st)))
        self.assertLess(ys[2], ys[1] - 0.003)
        self.assertLess(ys[1], ys[0] - 0.003)

    def test_the_built_body_and_her_clothes_carry_it(self):
        if not os.path.exists(WOMAN_GLB):
            self.skipTest("the woman's body has not been built")
        g, _ = glb.read_glb(WOMAN_GLB)
        names = [n for m in g["meshes"] for n in m.get("extras", {}).get("targetNames", [])]
        self.assertIn("bust", names, "her body has no bust slider: fit_parts.py --bust")
        root = os.path.join(CHARS, "clothing")
        for name in ("tunic", "kirtle", "brigandine"):
            path = os.path.join(root, name, name + ".glb")
            if not os.path.exists(path):
                continue
            g, _ = glb.read_glb(path)
            names = [n for m in g["meshes"] for n in m.get("extras", {}).get("targetNames", [])]
            self.assertIn("woman_bust", names, "%s does not follow her bust slider" % name)


class TestHerFacesAndClothes(unittest.TestCase):

    def test_every_face_has_a_womans_cut(self):
        if not os.path.isdir(os.path.join(CHARS, "heads", "default_f")):
            self.skipTest("the women's faces have not been built")
        for name in CF.HEAD_PRESETS:
            path = os.path.join(CHARS, "heads", name + CF.FEMININE_HEAD, name + CF.FEMININE_HEAD + ".meta.json")
            self.assertTrue(os.path.exists(path), "no woman's cut of the %s face" % name)
            meta = json.load(open(path))
            self.assertEqual(meta["params"].get("feminine"), 1.0, name)
            self.assertEqual(meta["params"]["head"], bodylib.HeadStyle.from_dict(CF.HEAD_PRESETS[name]).to_dict(),
                             "the woman's %s face is not the same face" % name)

    def test_every_grown_garment_is_fitted_to_her(self):
        root = os.path.join(CHARS, "clothing")
        if not os.path.exists(WOMAN_GLB) or not os.path.isdir(root):
            self.skipTest("nothing built")
        checked = 0
        for name in sorted(os.listdir(root)):
            if name.endswith("_child"):
                continue
            meta_path = os.path.join(root, name, name + ".meta.json")
            if not os.path.exists(meta_path):
                continue
            meta = json.load(open(meta_path))
            if meta["params"].get("bone"):
                continue
            self.assertIn("woman", meta.get("fits", []), "%s is not cut for a woman" % name)
            g, b = glb.read_glb(os.path.join(root, name, name + ".glb"))
            for n in g["nodes"]:
                if "mesh" not in n or "skin" not in n:
                    continue
                mesh = g["meshes"][n["mesh"]]
                names = mesh.get("extras", {}).get("targetNames", [])
                self.assertIn("woman", names, "%s/%s has no woman's target" % (name, mesh.get("name")))
                for p in mesh["primitives"]:
                    t = p["targets"][names.index("woman")]
                    self.assertEqual(g["accessors"][t["POSITION"]]["count"],
                                     g["accessors"][p["attributes"]["POSITION"]]["count"])
                    self.assertEqual(len(p["targets"]), len(names))
                    # a fit is centimetres, not the metres a stray field reading throws a hem
                    lo, hi = g["accessors"][t["POSITION"]]["min"], g["accessors"][t["POSITION"]]["max"]
                    self.assertLess(max(abs(v) for v in lo + hi), 0.08, "%s moves too far" % name)
            checked += 1
        self.assertGreater(checked, 20)

    def test_a_fit_written_again_replaces_itself(self):
        # fit_parts.py may be run over parts that already carry the target: once, not twice
        import struct
        gltf = {"buffers": [{"byteLength": 36}], "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}],
                "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
                "meshes": [{"name": "m", "primitives": [{"attributes": {"POSITION": 0},
                                                         "targets": [{"POSITION": 0, "NORMAL": 0}]}],
                            "extras": {"targetNames": ["grip_L"]}}]}
        bin_chunk = struct.pack("<9f", *range(9))
        bin_chunk = glb.set_morph_target(gltf, bin_chunk, 0, "woman", [[0.01, 0, 0]] * 3)
        bin_chunk = glb.set_morph_target(gltf, bin_chunk, 0, "woman", [[0.02, 0, 0]] * 3)
        mesh = gltf["meshes"][0]
        self.assertEqual(mesh["extras"]["targetNames"], ["grip_L", "woman"])
        targets = mesh["primitives"][0]["targets"]
        self.assertEqual(len(targets), 2)
        self.assertIn("NORMAL", targets[1], "every target must carry the same attributes")
        self.assertAlmostEqual(glb.read_accessor(gltf, bin_chunk, targets[1]["POSITION"])[2][0], 0.02, places=6)
        self.assertEqual(glb.read_accessor(gltf, bin_chunk, 0)[1], [3.0, 4.0, 5.0], "the mesh itself moved")

    def test_the_table_lists_her(self):
        data = json.load(open(os.path.join(FORGE, "characters.json")))
        self.assertIn("woman", data["body_variants"])
        self.assertEqual(sorted(data["feminine_heads"]), sorted(n + CF.FEMININE_HEAD for n in CF.HEAD_PRESETS))


class TestAWomansFace(unittest.TestCase):
    """Triage 22: the first women's faces were the men's with a jaw 7 % narrower, and in play they
    read as men. Her face is her own below the brow: a narrower, higher jaw to a small chin, a
    brow with hardly a ridge, a smaller nose, fuller lips and larger eyes, a slighter neck -- and
    above the brow the same vault, so every hair, hood and helm fits both."""

    def setUp(self):
        self.man = Skeleton(rig.Proportions())
        self.her = Skeleton(rig.Proportions(feminine=1.0))

    def test_the_vault_and_the_eye_line_are_his(self):
        m, w = bodylib.head_landmarks(self.man), bodylib.head_landmarks(self.her)
        for k in ("skull_c", "skull_r", "top"):
            self.assertLess(float(np.abs(np.asarray(m[k]) - np.asarray(w[k])).max()), 1e-9, k)
        for k in ("eye_z", "brow_z", "hairline_z", "chin_z", "face_y"):
            self.assertAlmostEqual(float(m[k]), float(w[k]), places=9, msg=k)

    def test_her_features_are_a_womans(self):
        m, w = bodylib.head_landmarks(self.man), bodylib.head_landmarks(self.her)
        self.assertLess(w["gonion"][0], m["gonion"][0] * 0.92, "her jaw is no narrower")
        self.assertGreater(w["gonion"][2], m["gonion"][2], "the angle of her jaw is no higher")
        self.assertGreater(w["nose_tip"][1], m["nose_tip"][1] + 0.003, "her nose stands as far out")
        self.assertGreater(w["eye_r"], m["eye_r"], "her eyes are no larger")
        self.assertLess(w["stations"][1][1], m["stations"][1][1] * 0.85, "her chin is no smaller")

    def test_the_head_is_shaped_by_them(self):
        man = bodylib.head_scene(self.man, flat=True)
        her = bodylib.head_scene(self.her, flat=True)
        L = bodylib.head_landmarks(self.man)
        s = L["s"]
        # a point on the man's brow ridge, over the eye: inside him, outside her
        brow = np.array([[L["eye_x"], float(L["face_y"]) - 0.006 * s, float(L["brow_z"])]])
        self.assertGreater(float(her.eval(brow)[0]), float(man.eval(brow)[0]) + 0.001, "her brow is his ridge")
        # the corner of his jaw
        g = np.asarray(L["gonion"], float)[None]
        self.assertGreater(float(her.eval(g)[0]), float(man.eval(g)[0]) + 0.003, "her jaw is his")
        # and the side of the neck under it
        neck = np.array([[0.046 * s, 0.012 * s, float(L["chin_z"]) - 0.050 * s]])
        self.assertGreater(float(her.eval(neck)[0]), float(man.eval(neck)[0]), "her neck is his")

    def test_she_is_painted_as_a_woman(self):
        from forge.lib import paint
        L = bodylib.head_landmarks(self.her)
        s = L["s"]
        sx = 1.0
        # on the brow line two thirds out, and at the outer corner of the eye past the lid
        mid_brow = np.array([[sx * L["eye_x"] + sx * L["eye_r"] * 0.65, float(L["face_y"]) + 0.012 * s,
                              float(L["brow_z"]) + 0.0060 * s]])
        corner = np.array([[sx * (L["eye_x"] + L["eye_r"] * 1.55), float(L["face_y"]) + 0.006 * s,
                            float(L["eye_z"]) + L["eye_r"] * 0.28]])
        up = np.array([[0.0, -1.0, 0.0]])
        hers = paint.skin_paint(L, "wheat", 0, feminine=1.0)
        his = paint.skin_paint(L, "wheat", 0, feminine=0.0)
        self.assertLess(float(hers(corner, up).sum()), float(his(corner, up).sum()) - 0.05,
                        "no lash line out past the corner of her eye")


class TestHerHairAndClothes(unittest.TestCase):
    WOMENS_HAIR = ("long_loose", "shoulder", "twin_braids", "crown_braid", "chignon")
    WOMENS_CUTS = ("kirtle", "long_skirt", "fitted_tunic", "bodice", "shawl")

    def test_the_forge_offers_them(self):
        from forge.lib import cloth
        for h in self.WOMENS_HAIR:
            self.assertIn(h, cloth.HAIR_STYLES)
        for g in self.WOMENS_CUTS:
            self.assertIn(g, cloth.CLOTHING_BUILDERS)
        data = json.load(open(os.path.join(FORGE, "characters.json")))
        self.assertTrue(set(self.WOMENS_HAIR) <= set(data["hair_styles"]), "characters.json is stale")
        self.assertTrue(set(self.WOMENS_CUTS) <= set(data["clothing"]), "characters.json is stale")

    def test_the_game_offers_every_style_the_forge_makes(self):
        import re
        src = open(os.path.join(os.path.dirname(os.path.dirname(FORGE)), "game", "actors", "shared",
                                "character_appearance.gd")).read()
        m = re.search(r"const HAIR_STYLES: Array\[String\] = \[([^\]]*)\]", src)
        self.assertIsNotNone(m)
        offered = set(re.findall(r'"([a-z_]+)"', m.group(1)))
        from forge.lib import cloth
        self.assertEqual(offered, set(cloth.HAIR_STYLES), "the Naming's styles and the forge's differ")

    def test_the_plaited_crown_lies_over_the_head(self):
        from forge.lib import cloth
        skel = Skeleton(rig.Proportions())
        L = bodylib.head_landmarks(skel)
        head = cloth._head_field(skel)
        P, out = cloth._crown_arc(head, L, L["s"], 0.013)
        # from above one ear over the top to above the other, on the scalp, behind the hairline
        self.assertAlmostEqual(float(P[0, 0]), -float(P[-1, 0]), places=3)
        mid = P[len(P) // 2]
        self.assertGreater(float(mid[2]), float(L["hairline_z"]), "the plait is not over the top")
        self.assertGreater(float(mid[1]), float(L["face_y"]) + 0.04, "the plait is on the brow")
        self.assertLess(float(np.abs(np.linalg.norm(P - np.asarray(L["skull_c"]), axis=1)).max()), 0.14)

    def test_built_hair_and_cuts(self):
        missing = [h for h in self.WOMENS_HAIR
                   if not os.path.exists(os.path.join(CHARS, "hair", h, h + ".glb"))]
        missing += [g for g in self.WOMENS_CUTS
                    if not os.path.exists(os.path.join(CHARS, "clothing", g, g + ".glb"))]
        if len(missing) == len(self.WOMENS_HAIR) + len(self.WOMENS_CUTS):
            self.skipTest("the women's hair and cuts have not been built")
        self.assertEqual(missing, [], "not built")
        for g in self.WOMENS_CUTS:
            meta = json.load(open(os.path.join(CHARS, "clothing", g, g + ".meta.json")))
            self.assertIn("woman", meta.get("fits", []), "%s is not fitted to her" % g)


class TestTheThirdPass(unittest.TestCase):
    """Triage 29: her brows read as a frown, the nape of every tunic was a ragged notch, her
    sleeves stood as far off her arms as off a man's."""

    def test_her_brows_are_lighter_and_not_lower(self):
        """Her brows were lifted in the third pass and let down again in the face-materials pass
        (triage 40), which read the lifted arch as a surprised stare: they stay no lower than his,
        and lighter."""
        from forge.lib import paint
        skel = Skeleton(rig.Proportions(feminine=1.0))
        L = bodylib.head_landmarks(skel)
        s = L["s"]
        # up a line through the brow two thirds of the way out: where it is darkest, and how dark
        zs = np.linspace(float(L["brow_z"]) - 0.008 * s, float(L["brow_z"]) + 0.016 * s, 49)
        P = np.stack([np.full_like(zs, L["eye_x"] + L["eye_r"] * 0.65),
                      np.full_like(zs, float(L["face_y"]) + 0.012 * s), zs], axis=1)
        up = np.tile([0.0, -1.0, 0.0], (len(P), 1))
        lum = {}
        for fem in (0.0, 1.0):
            c = paint.skin_paint(L, "wheat", 0, feminine=fem)(P, up).sum(axis=1)
            lum[fem] = (float(zs[int(np.argmin(c))]), float(c.min()))
        self.assertGreaterEqual(lum[1.0][0], lum[0.0][0] - 0.001 * s, "her brow sits lower than his")
        self.assertGreater(lum[1.0][1], lum[0.0][1] + 0.05, "her brow is as dark as his")

    def test_her_eye_has_no_cave_over_it(self):
        from forge.lib import sdf
        skel = Skeleton(rig.Proportions(feminine=1.0))
        L = bodylib.head_landmarks(skel)
        sc = bodylib.head_scene(skel, flat=True)
        er = float(L["eye_r"])
        # the face's surface along rays from the front, down through the brow to the lid, a little
        # inside and outside the eye: it never steps back more than 5 mm between neighbours (the
        # socket and the crease under a man's brow are an overhang, and on her they were a slot)
        ys = np.linspace(-0.12, 0.0, 1200)
        for xo in (-0.6, 0.0, 0.8):
            prev = None
            for z in np.linspace(float(L["eye_z"]) + 2.0 * er, float(L["eye_z"]) + 0.5 * er, 25):
                P = np.stack([np.full_like(ys, float(L["eye_x"]) + xo * er), ys, np.full_like(ys, z)], axis=1)
                d = sc.eval(P)
                y = float(ys[int(np.argmax(d < 0))])
                if prev is not None:
                    self.assertLess(y - prev, 0.005, "a step into the face over her eye at %+.1f radii" % xo)
                prev = y

    def test_the_nape_is_closed(self):
        from forge.lib import cloth
        skel = Skeleton(rig.Proportions())
        neck = float(skel.J["Neck"][2])
        s = cloth._s(skel)
        for collar in (0.012, -0.030):
            reg = cloth.torso_region(skel, top=0.90, hem=0.44, sleeves=0.9, collar=collar)
            # behind, against the nape: covered, whatever the neckline is in front
            nape = np.array([[0.0, 0.095 * s, neck + 0.004 * s]])
            self.assertGreater(float(reg(nape)[0]), 0.9, "the back of the neck is bare (collar %+.3f)" % collar)
            # behind and to the side, 5 cm up the neck: cut (the sleeves' reach put two tabs there)
            tab = np.array([[0.060 * s, 0.075 * s, neck + 0.050 * s]])
            self.assertLess(float(reg(tab)[0]), 0.1, "cloth stands up the side of the neck (collar %+.3f)" % collar)

    def test_she_wears_her_sleeves_closer(self):
        from forge.lib import cloth
        skel = Skeleton(rig.Proportions())
        snug = cloth.BODY_SNUG["woman"](skel)
        J = skel.J
        on_arm = ((J["UpperArm.L"] + J["LowerArm.L"]) * 0.5)[None] + np.array([[0.0, -0.05, 0.0]])
        on_hip = np.array([[0.12, 0.0, float(J["UpperLeg.L"][2])]])
        d0 = np.array([0.016])
        self.assertLess(float(snug(on_arm, d0)[0]), 0.012, "a sleeve 16 mm off her arm stays there")
        self.assertAlmostEqual(float(snug(on_hip, d0)[0]), 0.016, places=4, msg="the fit moved off the arms")
        self.assertAlmostEqual(float(snug(on_arm, np.array([0.005]))[0]), 0.005, places=4,
                               msg="a close fit was pulled into her")


if __name__ == "__main__":
    unittest.main()
