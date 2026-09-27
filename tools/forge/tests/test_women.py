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
        c, _ = bodylib.bust_mass(her, 1, 1.0, 1.0)
        front = c + np.array([0.0, -0.030, 0.0])
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


if __name__ == "__main__":
    unittest.main()
