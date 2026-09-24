"""Output paths, naming, seeding, the manifest and the GLB writer (pure Python)."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import build_assets  # noqa: E402
from lib import cli  # noqa: E402
from lib import glb  # noqa: E402


class TestNaming(unittest.TestCase):
    def test_default_name_includes_region(self):
        self.assertEqual(cli.default_name("hearthvale", "oak", "a"), "hearthvale_oak_a")
        self.assertEqual(cli.default_name("neutral", "barrel", "c"), "barrel_c")

    def test_validate_name_rejects_bad_names(self):
        for bad in ("Oak", "oak-a", "oak a", "", "1oak", "oak/a"):
            with self.assertRaises(ValueError, msg=bad):
                cli.validate_name(bad)
        for good in ("hearthvale_oak_a", "bone_rib_b", "well"):
            cli.validate_name(good)

    def test_variant_letters_and_indices(self):
        self.assertEqual(cli.variant_index("a"), 0)
        self.assertEqual(cli.variant_index("c"), 2)
        self.assertEqual(cli.variant_index(3), 3)
        self.assertEqual(cli.variant_index("3"), 3)
        self.assertEqual(cli.variant_letter(0), "a")
        self.assertEqual(cli.variant_letter(25), "z")

    def test_seeds_are_stable_and_distinct(self):
        a = cli.derive_seed(7, 0, "oak")
        self.assertEqual(a, cli.derive_seed(7, 0, "oak"))
        self.assertNotEqual(a, cli.derive_seed(7, 1, "oak"))
        self.assertNotEqual(a, cli.derive_seed(8, 0, "oak"))
        self.assertNotEqual(a, cli.derive_seed(7, 0, "apple"))


class TestPaths(unittest.TestCase):
    def test_layout_matches_contract(self):
        """CONTRACTS.md §4: models/<category>/<name>/<name>.{glb,meta.json,_*.png}"""
        with tempfile.TemporaryDirectory() as td:
            p = cli.output_paths(td, "trees", "hearthvale_oak_a")
            self.assertEqual(p["glb"].name, "hearthvale_oak_a.glb")
            self.assertEqual(p["meta"].name, "hearthvale_oak_a.meta.json")
            self.assertEqual(p["albedo"].name, "hearthvale_oak_a_albedo.png")
            self.assertEqual(p["normal"].name, "hearthvale_oak_a_normal.png")
            self.assertEqual(p["orm"].name, "hearthvale_oak_a_orm.png")
            self.assertEqual(p["col"].name, "hearthvale_oak_a_col.glb")
            self.assertEqual(p["dir"].parent.name, "trees")
            self.assertEqual(p["dir"].name, "hearthvale_oak_a")

    def test_nested_category(self):
        with tempfile.TemporaryDirectory() as td:
            d = cli.asset_dir(td, "architecture/vale", "cottage_a")
            self.assertTrue(d.is_dir())
            self.assertTrue(d.as_posix().endswith("architecture/vale/cottage_a"))

    def test_asset_dir_rejects_bad_name(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(ValueError):
                cli.asset_dir(td, "props", "Bad Name")

    def test_res_path(self):
        p = cli.REPO_ROOT / "game" / "assets" / "models" / "trees" / "x" / "x.glb"
        self.assertEqual(cli.res_path(None, p), "res://assets/models/trees/x/x.glb")

    def test_hash_changes_with_every_input(self):
        base = dict(generator="gen_trees", version=1, name="a", kind="oak", params={"x": 1},
                    seed=3, palette="core:region/hearthvale")
        h = cli.asset_hash(**base)
        self.assertEqual(h, cli.asset_hash(**base))
        for key, value in (("version", 2), ("name", "b"), ("kind", "apple"),
                           ("params", {"x": 2}), ("seed", 4), ("palette", "core:region/skerrow")):
            other = dict(base)
            other[key] = value
            self.assertNotEqual(h, cli.asset_hash(**other), "hash ignores %s" % key)

    def test_param_key_order_does_not_matter(self):
        a = cli.asset_hash("g", 1, "n", "k", {"a": 1, "b": 2}, 1, None)
        b = cli.asset_hash("g", 1, "n", "k", {"b": 2, "a": 1}, 1, None)
        self.assertEqual(a, b)


class TestArgParsing(unittest.TestCase):
    def test_parse_basic(self):
        args = cli.parse("t", ["prog.py", "--", "--kind", "oak", "--palette", "hearthvale",
                               "--seed", "9", "--variant", "b", "--params", '{"height_m": 8}'])
        self.assertEqual(args.kind, "oak")
        self.assertEqual(args.seed, 9)
        self.assertEqual(args.variant, "b")
        self.assertEqual(args.variant_index, 1)
        self.assertEqual(args.params, {"height_m": 8})
        self.assertEqual(args.palette_short, "hearthvale")

    def test_bad_params_json(self):
        with self.assertRaises(SystemExit):
            cli.parse("t", ["prog.py", "--", "--params", "not json"])
        with self.assertRaises(SystemExit):
            cli.parse("t", ["prog.py", "--", "--params", "[1,2]"])


class TestManifest(unittest.TestCase):
    def setUp(self):
        self.entries = build_assets.load_manifest()

    def test_manifest_loads_and_is_complete(self):
        self.assertGreater(len(self.entries), 100)
        for e in self.entries:
            for key in ("generator", "kind", "name", "category", "seed", "variant", "params"):
                self.assertIn(key, e)
            cli.validate_name(e["name"])

    def test_names_are_unique(self):
        seen = {}
        for e in self.entries:
            key = (e["category"], e["name"])
            self.assertNotIn(key, seen, "duplicate asset %s/%s" % key)
            seen[key] = True

    def test_generators_exist(self):
        for e in self.entries:
            script = build_assets.FORGE_DIR / ("%s.py" % e["generator"])
            self.assertTrue(script.exists(), "missing generator %s" % script)

    def test_categories_are_contract_categories(self):
        allowed = set(cli.CATEGORIES)
        for e in self.entries:
            self.assertIn(e["category"].split("/")[0], allowed, e["category"])

    def test_palettes_are_real_regions(self):
        from lib import palette as P
        known = set(P.region_ids())
        for e in self.entries:
            if e["palette"]:
                self.assertIn(e["palette"], known, "%s has unknown palette" % e["name"])

    def test_every_region_is_represented(self):
        from lib import palette as P
        used = {e["palette"] for e in self.entries if e["palette"]}
        for rid in P.region_ids():
            self.assertIn(rid, used, "no assets for %s" % rid)

    def test_variants_per_kind(self):
        """DESIGN §7.0.6: seeds must produce visibly different assets, so most kinds ship
        more than one variant and no two variants of a kind share a seed."""
        by_kind: dict[tuple, list] = {}
        for e in self.entries:
            by_kind.setdefault((e["generator"], e["kind"], e["palette"]), []).append(e)
        multi = [k for k, v in by_kind.items() if len(v) > 1]
        self.assertGreater(len(multi), 20)
        for key, group in by_kind.items():
            seeds = [g["seed"] for g in group]
            self.assertEqual(len(seeds), len(set(seeds)), "repeated seed in %s" % (key,))

    def test_build_command_shape(self):
        e = self.entries[0]
        cmd = build_assets.build_command(e, Path("/tmp/out"), False, 0)
        self.assertIn("--", cmd)
        self.assertEqual(cmd[1], "-b")
        self.assertIn("--kind", cmd)
        self.assertIn(e["kind"], cmd)
        json.loads(cmd[cmd.index("--params") + 1])

    def test_is_current_false_when_missing(self):
        with tempfile.TemporaryDirectory() as td:
            self.assertFalse(build_assets.is_current(self.entries[0], Path(td), 1))

    def test_is_current_true_when_hash_matches(self):
        e = self.entries[0]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            d = cli.asset_dir(root, e["category"], e["name"])
            (d / ("%s.glb" % e["name"])).write_bytes(b"x")
            (d / ("%s.meta.json" % e["name"])).write_text(json.dumps({
                "hash": build_assets.entry_hash(e, 1), "textures": []}))
            self.assertTrue(build_assets.is_current(e, root, 1))
            # a forge version bump invalidates everything
            self.assertFalse(build_assets.is_current(e, root, 2))

    def test_every_tree_has_an_impostor_entry_and_every_impostor_a_tree(self):
        trees = {e["name"] for e in self.entries if e["generator"] == "gen_trees"}
        impostors = [e for e in self.entries if e["generator"] == "gen_impostors"]
        self.assertEqual({build_assets.impostor_source(e) for e in impostors}, trees)
        for e in impostors:
            self.assertEqual(e["category"], "trees")
            self.assertTrue(e["name"].endswith("_impostor"), e["name"])

    def test_impostor_is_current_only_while_its_tree_is_the_one_it_drew(self):
        e = next(x for x in self.entries if x["generator"] == "gen_impostors")
        tree = build_assets.impostor_source(e)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            d = cli.asset_dir(root, e["category"], tree)
            (d / ("%s.glb" % tree)).write_bytes(b"x")
            (d / "a.png").write_bytes(b"x")
            (d / "n.png").write_bytes(b"x")
            meta = {"hash": "tree-1", "textures": [], "impostor": {
                "hash": build_assets.entry_hash(e, 1), "source_hash": "tree-1",
                "albedo": "a.png", "normal": "n.png"}}
            (d / ("%s.meta.json" % tree)).write_text(json.dumps(meta))
            self.assertTrue(build_assets.is_current(e, root, 1))
            # the tree was rebuilt: its hash moved, so its picture is stale
            meta["hash"] = "tree-2"
            (d / ("%s.meta.json" % tree)).write_text(json.dumps(meta))
            self.assertFalse(build_assets.is_current(e, root, 1))
            # a rebuilt tree's meta has no impostor block at all
            del meta["impostor"]
            (d / ("%s.meta.json" % tree)).write_text(json.dumps(meta))
            self.assertFalse(build_assets.is_current(e, root, 1))

    def test_is_current_false_when_texture_missing(self):
        e = self.entries[0]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            d = cli.asset_dir(root, e["category"], e["name"])
            (d / ("%s.glb" % e["name"])).write_bytes(b"x")
            (d / ("%s.meta.json" % e["name"])).write_text(json.dumps({
                "hash": build_assets.entry_hash(e, 1), "textures": ["gone_albedo.png"]}))
            self.assertFalse(build_assets.is_current(e, root, 1))


class TestGlbWriter(unittest.TestCase):
    def _minimal(self):
        gltf = {
            "asset": {"version": "2.0"},
            "buffers": [{"byteLength": 16}],
            "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 8},
                            {"buffer": 0, "byteOffset": 8, "byteLength": 8}],
            "accessors": [{"bufferView": 0, "componentType": 5126, "count": 2, "type": "VEC3"}],
            "images": [{"name": "x_albedo", "bufferView": 1, "mimeType": "image/png"}],
            "textures": [{"source": 0}],
            "materials": [{"name": "x_mat", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
            "meshes": [{"name": "x", "primitives": [{"attributes": {"POSITION": 0}}]}],
            "nodes": [{"name": "x", "mesh": 0}],
        }
        return gltf, bytes(range(16))

    def test_round_trip(self):
        gltf, bin_chunk = self._minimal()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.glb"
            glb.write_glb(p, gltf, bin_chunk)
            back, back_bin = glb.read_glb(p)
            self.assertEqual(back["meshes"][0]["name"], "x")
            self.assertEqual(back_bin[:16], bin_chunk)

    def test_externalise_images_rewrites_uri_and_drops_data(self):
        gltf, bin_chunk = self._minimal()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.glb"
            glb.write_glb(p, gltf, bin_chunk)
            before = p.stat().st_size
            uris = glb.externalise_images(p, {"x_mat": {"baseColorTexture": "x_albedo.png"}})
            self.assertEqual(uris, ["x_albedo.png"])
            after_gltf, after_bin = glb.read_glb(p)
            self.assertEqual(after_gltf["images"][0]["uri"], "x_albedo.png")
            self.assertNotIn("bufferView", after_gltf["images"][0])
            self.assertLess(len(after_bin), len(bin_chunk))
            self.assertLessEqual(p.stat().st_size, before)
            # the surviving accessor must still point at valid data
            acc = after_gltf["accessors"][0]
            view = after_gltf["bufferViews"][acc["bufferView"]]
            self.assertEqual(view["byteLength"], 8)

    def test_externalise_leaves_unknown_materials_alone(self):
        gltf, bin_chunk = self._minimal()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.glb"
            glb.write_glb(p, gltf, bin_chunk)
            self.assertEqual(glb.externalise_images(p, {"other": {"baseColorTexture": "y.png"}}), [])
            after, _ = glb.read_glb(p)
            self.assertIn("bufferView", after["images"][0])

    def test_replace_mesh_geometry_then_prune(self):
        """gen_impostors' surgery: one mesh's geometry swapped for a quad, and everything the
        old primitive and its material used taken out of the file -- nothing else moved."""
        gltf, bin_chunk = self._minimal()
        gltf["meshes"][0]["primitives"][0]["material"] = 0
        # a second mesh with its own material and image, to be replaced
        gltf["images"].append({"name": "old", "bufferView": 1, "mimeType": "image/png"})
        gltf["textures"].append({"source": 1})
        gltf["materials"].append({"name": "old_mat",
                                  "pbrMetallicRoughness": {"baseColorTexture": {"index": 1}}})
        gltf["meshes"].append({"name": "x_LOD2", "primitives": [{"attributes": {"POSITION": 0},
                                                                  "material": 1}]})
        gltf["nodes"].append({"name": "x_LOD2", "mesh": 1})
        gltf["images"].append({"uri": "x_impostor_albedo.png"})
        gltf["textures"].append({"source": 2})
        gltf["materials"][1] = {"name": "x_impostor",
                                "pbrMetallicRoughness": {"baseColorTexture": {"index": 2}}}
        quad = [[-1.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 2.0, 0.0], [-1.0, 2.0, 0.0]]
        new_bin = glb.replace_mesh_geometry(gltf, bin_chunk, "x_LOD2", quad, [[0.0, 0.0, 1.0]] * 4,
                                            [[0, 1], [1, 1], [1, 0], [0, 0]], [0, 1, 2, 0, 2, 3], 1)
        new_bin = glb.prune(gltf, new_bin)
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.glb"
            glb.write_glb(p, gltf, new_bin)
            s = glb.summary(p)
        self.assertEqual([m["tris"] for m in s["meshes"]], [0, 2])
        self.assertEqual(s["materials"], ["x_mat", "x_impostor"])
        # the old image (embedded) is gone; the first mesh's accessor still reads its 8 bytes
        self.assertEqual(s["images"], ["<embedded>", "x_impostor_albedo.png"])
        pos = gltf["accessors"][gltf["meshes"][1]["primitives"][0]["attributes"]["POSITION"]]
        self.assertEqual(pos["min"], [-1.0, 0.0, 0.0])
        self.assertEqual(pos["max"], [1.0, 2.0, 0.0])
        first = gltf["accessors"][gltf["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
        self.assertEqual(gltf["bufferViews"][first["bufferView"]]["byteLength"], 8)

    def test_prune_refuses_what_it_does_not_understand(self):
        gltf, bin_chunk = self._minimal()
        gltf["skins"] = [{"joints": [0]}]
        with self.assertRaises(ValueError):
            glb.prune(gltf, bin_chunk)

    def test_summary(self):
        gltf, bin_chunk = self._minimal()
        gltf["accessors"][0]["count"] = 9
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "a.glb"
            glb.write_glb(p, gltf, bin_chunk)
            s = glb.summary(p)
            self.assertEqual(s["meshes"][0]["tris"], 3)
            self.assertEqual(s["materials"], ["x_mat"])


class TestLod1Repair(unittest.TestCase):
    """lib/lod_repair.py: a LOD1 bark triangle bridging two branches of the full tree is taken
    out, the ones lying on the bark stay, every vertex attribute survives, and a second pass
    finds nothing."""

    @staticmethod
    def _tree() -> tuple[dict, bytes]:
        gltf = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0}], "bufferViews": [],
                "accessors": [], "materials": [{"name": "t_mat"}, {"name": "t_leaf_foliage"}],
                "meshes": [], "nodes": []}
        out = bytearray()

        def mesh(name: str, positions: list, indices: list, material: int) -> None:
            pos = glb._append_accessor(gltf, out, positions, "VEC3", 5126, 34962, with_bounds=True)
            nrm = glb._append_accessor(gltf, out, [[0.0, 0.0, 1.0]] * len(positions), "VEC3", 5126, 34962)
            uv = glb._append_accessor(gltf, out, [[0.0, 0.0]] * len(positions), "VEC2", 5126, 34962)
            idx = glb._append_accessor(gltf, out, indices, "SCALAR", 5123, 34963)
            gltf["meshes"].append({"name": name, "primitives": [{
                "attributes": {"POSITION": pos, "NORMAL": nrm, "TEXCOORD_0": uv},
                "indices": idx, "material": material, "mode": 4}]})
            gltf["nodes"].append({"name": name, "mesh": len(gltf["meshes"]) - 1})

        # the full tree: two upright branches four metres tall, six metres apart
        branches = [[-0.1, 0, 0], [0.1, 0, 0], [0.1, 4, 0], [-0.1, 4, 0],
                    [5.9, 0, 0], [6.1, 0, 0], [6.1, 4, 0], [5.9, 4, 0]]
        mesh("t", branches, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7], 0)
        # LOD1: one triangle on each branch, and a bridge across the gap between them
        lod1 = [[-0.1, 0, 0], [0.1, 0, 0], [0.0, 4, 0], [5.9, 0, 0], [6.1, 0, 0], [6.0, 4, 0]]
        mesh("t_LOD1", lod1, [0, 1, 2, 3, 4, 5, 2, 5, 1], 0)
        # leaf cards far off the bark are cards, not bark, and are never touched
        mesh("t_cards_LOD1", [[3, 8, 0], [4, 8, 0], [4, 9, 0]], [0, 1, 2], 1)
        gltf["buffers"][0]["byteLength"] = len(out)
        return gltf, bytes(out)

    def test_the_bridge_goes_and_the_bark_stays(self):
        from lib import lod_repair
        gltf, bin_chunk = self._tree()
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "t.glb"
            glb.write_glb(p, gltf, bin_chunk)
            rep = lod_repair.repair_lod1(p, "t", 4.0)
            self.assertEqual(rep["dropped"], 1, rep)
            s = {m["name"]: m["tris"] for m in glb.summary(p)["meshes"]}
            self.assertEqual(s, {"t": 4, "t_LOD1": 2, "t_cards_LOD1": 1})
            after, after_bin = glb.read_glb(p)
            prim = after["meshes"][1]["primitives"][0]
            self.assertEqual(sorted(prim["attributes"]), ["NORMAL", "POSITION", "TEXCOORD_0"])
            tris = lod_repair.accessor_array(after, after_bin, prim["indices"]).reshape(-1, 3).tolist()
            self.assertEqual(tris, [[0, 1, 2], [3, 4, 5]], "the two triangles on the bark, in order")
            again = lod_repair.repair_lod1(p, "t", 4.0)
            self.assertEqual(again["dropped"], 0, "a second pass finds nothing to drop")

    def test_the_tolerance_grows_with_the_tree(self):
        from lib import lod_repair
        self.assertEqual(lod_repair.tolerance(4.0), lod_repair.TOL_MIN)
        self.assertGreater(lod_repair.tolerance(30.0), lod_repair.TOL_MIN)


class TestGodotImportSidecars(unittest.TestCase):
    def test_uid_is_stable_and_well_formed(self):
        # Import lib.export lazily: it imports bpy, which only exists inside Blender.
        try:
            from lib.export import godot_uid
        except ImportError:
            self.skipTest("export.py needs Blender")
        a = godot_uid("res://assets/models/trees/x/x.glb")
        self.assertEqual(a, godot_uid("res://assets/models/trees/x/x.glb"))
        self.assertNotEqual(a, godot_uid("res://assets/models/trees/y/y.glb"))
        self.assertTrue(a.startswith("uid://"))
        self.assertTrue(all(c in "abcdefghijklmnopqrstuvwxy012345678" for c in a[6:]))


if __name__ == "__main__":
    unittest.main()
