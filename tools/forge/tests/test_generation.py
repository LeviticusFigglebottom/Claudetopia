"""End-to-end: build one tiny asset under `blender -b` and check what lands on disk.

This is the only test that needs Blender. It runs a real generator through a real bake and
export, then verifies the output against CONTRACTS.md §4: the file layout, the meta
record, the LOD meshes, the external texture references and the Godot import sidecars.

Skipped (not failed) when Blender is not on PATH, so the pure-Python suite still runs
anywhere.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import cli  # noqa: E402
from lib import glb  # noqa: E402

FORGE = Path(__file__).resolve().parents[1]
BLENDER = os.environ.get("BLENDER", "blender")
TIMEOUT = int(os.environ.get("FORGE_TEST_TIMEOUT", "600"))


def blender_available() -> bool:
    return shutil.which(BLENDER) is not None


@unittest.skipUnless(blender_available(), "blender not on PATH")
class TestEndToEnd(unittest.TestCase):
    """One small prop, generated for real. `mug` is the cheapest asset the forge makes:
    a lathed vessel with a handle, small enough for a 256 atlas."""

    out: Path
    tmp: tempfile.TemporaryDirectory
    name = "hearthvale_mug_a"
    result: subprocess.CompletedProcess

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name)
        cmd = [BLENDER, "-b", "--python", str(FORGE / "gen_props.py"), "--",
               "--kind", "mug", "--palette", "hearthvale", "--seed", "42", "--variant", "a",
               "--res", "128", "--out", str(cls.out)]
        cls.result = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        if "FORGE_OK" not in self.result.stdout:
            self.fail("generator failed:\n%s\n%s"
                      % (self.result.stdout[-3000:], self.result.stderr[-2000:]))

    def paths(self):
        return cli.output_paths(self.out, "props", self.name)

    def test_files_match_the_contract(self):
        p = self.paths()
        for key in ("glb", "meta", "albedo", "normal", "orm"):
            self.assertTrue(p[key].exists(), "missing %s" % p[key].name)
            self.assertGreater(p[key].stat().st_size, 200, "%s is suspiciously small" % p[key].name)

    def test_meta_record(self):
        meta = json.loads(self.paths()["meta"].read_text())
        self.assertEqual(meta["name"], self.name)
        self.assertEqual(meta["category"], "props")
        self.assertEqual(meta["generator"], "gen_props")
        self.assertEqual(meta["kind"], "mug")
        self.assertEqual(meta["seed"], 42)
        self.assertIn(meta["collision"], ("convex", "trimesh", "capsule", "none"))
        self.assertEqual(len(meta["tris"]), 3)
        self.assertGreater(meta["tris"][0], 50)
        self.assertGreaterEqual(meta["tris"][0], meta["tris"][1])
        self.assertGreaterEqual(meta["tris"][1], meta["tris"][2])
        self.assertEqual(meta["hash"], cli.asset_hash("gen_props", meta["version"], self.name,
                                                      "mug", {}, 42, "core:region/hearthvale"))
        self.assertEqual(meta["region_palette"]["id"], "core:region/hearthvale")
        self.assertEqual(len(meta["region_palette"]["colors"]), 6)
        for key in ("min", "max", "radius", "height"):
            self.assertIn(key, meta["bounds"])

    def test_scale_is_metres(self):
        """CONTRACTS.md §1: metres. A mug is a hand-sized object, not a barrel."""
        meta = json.loads(self.paths()["meta"].read_text())
        h = meta["bounds"]["height"]
        self.assertGreater(h, 0.05, "mug is sub-centimetre; units are wrong")
        self.assertLess(h, 0.35, "mug is bigger than a bucket; units are wrong")

    def test_sits_on_the_ground(self):
        meta = json.loads(self.paths()["meta"].read_text())
        self.assertAlmostEqual(meta["bounds"]["min"][1], 0.0, delta=0.02,
                               msg="asset does not rest on y=0")

    def test_glb_has_lod_meshes(self):
        s = glb.summary(self.paths()["glb"])
        names = [m["name"] for m in s["meshes"]]
        self.assertIn(self.name, names)
        self.assertIn("%s_LOD1" % self.name, names)
        self.assertIn("%s_LOD2" % self.name, names)
        by_name = {m["name"]: m["tris"] for m in s["meshes"]}
        self.assertGreater(by_name[self.name], by_name["%s_LOD2" % self.name])

    def test_textures_are_external_not_embedded(self):
        """The PNGs sit next to the GLB (CONTRACTS.md §4); carrying a second embedded copy
        would double the committed size for nothing."""
        s = glb.summary(self.paths()["glb"])
        self.assertTrue(s["images"], "no images referenced")
        for uri in s["images"]:
            self.assertNotEqual(uri, "<embedded>")
            self.assertTrue((self.paths()["dir"] / uri).exists(), "dangling %s" % uri)

    def test_material_is_one_principled_material(self):
        s = glb.summary(self.paths()["glb"])
        self.assertEqual(len(s["materials"]), 1, s["materials"])
        gltf, _ = glb.read_glb(self.paths()["glb"])
        mat = gltf["materials"][0]
        pbr = mat["pbrMetallicRoughness"]
        self.assertIn("baseColorTexture", pbr)
        self.assertIn("metallicRoughnessTexture", pbr)
        self.assertIn("normalTexture", mat)
        self.assertIn("occlusionTexture", mat)

    def test_texture_size_respects_override(self):
        from PIL import Image
        with Image.open(self.paths()["albedo"]) as im:
            self.assertEqual(im.size, (128, 128))
        with Image.open(self.paths()["normal"]) as im:
            self.assertEqual(im.size, (128, 128))
        with Image.open(self.paths()["orm"]) as im:
            self.assertEqual(im.size, (64, 64), "ORM should be written at half size")

    def test_albedo_is_not_blank(self):
        """A black atlas is the classic forge failure (UVs at 0,0), so assert real colour."""
        import numpy as np
        from PIL import Image
        with Image.open(self.paths()["albedo"]) as im:
            a = np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0
        lit = a.reshape(-1, 3).max(axis=1)
        covered = float((lit > 0.04).mean())
        self.assertGreater(covered, 0.35, "most of the atlas is unbaked black")
        painted = a.reshape(-1, 3)[lit > 0.04]
        self.assertGreater(float(painted.std()), 0.01, "atlas is a flat colour, not painted")

    def test_import_sidecars(self):
        p = self.paths()
        for f in (p["glb"], p["albedo"], p["normal"], p["orm"]):
            imp = Path(str(f) + ".import")
            self.assertTrue(imp.exists(), "missing %s" % imp.name)
            text = imp.read_text()
            self.assertIn("uid://", text)
            # Built out of tree here, so source_file is the absolute path; res:// form is
            # covered by test_paths.TestPaths.test_res_path.
            self.assertIn("source_file=\"%s\"" % f, text)
        glb_import = Path(str(p["glb"]) + ".import")
        self.assertIn("import_script/path=\"res://tools_gd/glb_post_import.gd\"",
                      glb_import.read_text())
        # True, and it has been since "a real LOD ladder for trees, and mesh LODs for the
        # scatter" turned it on -- "a MultiMesh has no visibility ranges and was drawing
        # LOD0 to the horizon". The sidecar writer was changed there and this assertion was
        # not, so the end-to-end suite has been red ever since; it only runs where Blender
        # is on PATH, which is why nothing noticed.
        self.assertIn("meshes/generate_lods=true", glb_import.read_text())
        normal_import = Path(str(p["normal"]) + ".import").read_text()
        self.assertIn("compress/normal_map=1", normal_import)

    def test_rerun_is_deterministic(self):
        """Same seed, same asset: DESIGN §7.0.6 requires seeds to be reproducible."""
        with tempfile.TemporaryDirectory() as td:
            cmd = [BLENDER, "-b", "--python", str(FORGE / "gen_props.py"), "--",
                   "--kind", "mug", "--palette", "hearthvale", "--seed", "42", "--variant", "a",
                   "--res", "128", "--out", td]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
            self.assertIn("FORGE_OK", r.stdout, r.stdout[-2000:] + r.stderr[-1000:])
            a = json.loads(self.paths()["meta"].read_text())
            b = json.loads((cli.output_paths(td, "props", self.name)["meta"]).read_text())
            self.assertEqual(a["tris"], b["tris"])
            self.assertEqual(a["hash"], b["hash"])
            self.assertEqual(a["bounds"], b["bounds"])


@unittest.skipUnless(blender_available(), "blender not on PATH")
class TestVariantsDiffer(unittest.TestCase):
    """DESIGN §7.0.6: seeds must produce visibly different assets."""

    def test_two_seeds_give_different_geometry(self):
        metas = []
        with tempfile.TemporaryDirectory() as td:
            for seed, variant in ((11, "a"), (97, "b")):
                cmd = [BLENDER, "-b", "--python", str(FORGE / "gen_rocks.py"), "--",
                       "--kind", "boulder", "--palette", "skerrow", "--seed", str(seed),
                       "--variant", variant, "--res", "128", "--quick", "--out", td]
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
                self.assertIn("FORGE_OK", r.stdout, r.stdout[-2000:] + r.stderr[-1000:])
                name = "skerrow_boulder_%s" % variant
                metas.append(json.loads(cli.output_paths(td, "rocks", name)["meta"].read_text()))
        a, b = metas
        self.assertNotEqual(a["bounds"], b["bounds"], "two seeds produced the same boulder")


@unittest.skipUnless(blender_available(), "blender not on PATH")
class TestFoliageContract(unittest.TestCase):
    """Foliage materials must be named *_foliage so the import step swaps in the wind
    shader (CONTRACTS.md §4), and their albedo must carry alpha."""

    def test_flora_material_naming_and_alpha(self):
        with tempfile.TemporaryDirectory() as td:
            cmd = [BLENDER, "-b", "--python", str(FORGE / "gen_flora.py"), "--",
                   "--kind", "grass_clump", "--palette", "hearthvale", "--seed", "5",
                   "--variant", "a", "--res", "128", "--out", td]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
            self.assertIn("FORGE_OK", r.stdout, r.stdout[-2000:] + r.stderr[-1000:])
            name = "hearthvale_grass_clump_a"
            p = cli.output_paths(td, "flora", name)
            s = glb.summary(p["glb"])
            self.assertTrue(any(m.endswith("_foliage") for m in s["materials"]),
                            "no *_foliage material in %s" % s["materials"])
            meta = json.loads(p["meta"].read_text())
            self.assertEqual(meta["collision"], "none", "ground flora should not collide")
            self.assertLess(meta["tris"][0], 200, "flora cards must stay cheap")
            from PIL import Image
            albedo = p["dir"] / [t for t in meta["textures"] if t.endswith("_albedo.png")][0]
            with Image.open(albedo) as im:
                self.assertEqual(im.mode, "RGBA", "foliage albedo needs an alpha channel")
                import numpy as np
                alpha = np.asarray(im)[..., 3]
                self.assertGreater(float((alpha < 8).mean()), 0.2, "card has no cut-out")
                self.assertGreater(float((alpha > 200).mean()), 0.05, "card is entirely cut out")


if __name__ == "__main__":
    unittest.main()
