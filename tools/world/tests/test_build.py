#!/usr/bin/env python3
"""Build a small world into a temporary directory and check what came out.

    python3 tools/world/tests/test_build.py          # or: python3 -m unittest discover tools/world/tests

The build is run at --size 1024 (8 m per texel), which takes about 25 seconds and exercises
every stage: regions, heights, drainage, the Mere, pads, rivers, roads, water, textures,
colour, POIs and cells. The assertions are the parts of docs/CONTRACTS.md §6 that other
streams rely on, plus the geography the world bible promises.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)

SIZE = 1024
PACK = os.path.join(REPO, "game", "content", "packs", "core")


def build_once(out_dir: str) -> dict:
    cmd = [sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", str(SIZE), "--out", out_dir]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    if proc.returncode != 0:
        raise AssertionError("build failed:\n%s\n%s" % (proc.stdout[-4000:], proc.stderr[-4000:]))
    with open(os.path.join(out_dir, "world_manifest.json"), "r", encoding="utf-8") as f:
        return json.load(f)


class WorldBuildTest(unittest.TestCase):
    out_dir = ""
    manifest: dict = {}

    @classmethod
    def setUpClass(cls) -> None:
        cls.out_dir = tempfile.mkdtemp(prefix="wickmere_world_")
        cls.manifest = build_once(cls.out_dir)
        n = cls.manifest["grid"]
        cls.n = n
        cls.spacing = float(cls.manifest["spacing_m"])
        cls.H = np.fromfile(os.path.join(cls.out_dir, "heights.r32"), dtype="<f4").reshape(n, n)
        cls.region = np.fromfile(os.path.join(cls.out_dir, "region_mask.u8"), dtype=np.uint8).reshape(n, n)
        cls.water = np.fromfile(os.path.join(cls.out_dir, "water_mask.u8"), dtype=np.uint8).reshape(n, n)
        cls.base = np.fromfile(os.path.join(cls.out_dir, "texture_base.u8"), dtype=np.uint8).reshape(n, n)
        cls.overlay = np.fromfile(os.path.join(cls.out_dir, "texture_overlay.u8"), dtype=np.uint8).reshape(n, n)
        cls.blend = np.fromfile(os.path.join(cls.out_dir, "texture_blend.u8"), dtype=np.uint8).reshape(n, n)
        cls.colour = np.fromfile(os.path.join(cls.out_dir, "color.rgba8"), dtype=np.uint8).reshape(n, n, 4)
        with open(os.path.join(PACK, "places", "places.json"), "r", encoding="utf-8") as f:
            cls.places = json.load(f)
        with open(os.path.join(PACK, "regions", "regions.json"), "r", encoding="utf-8") as f:
            cls.regions = json.load(f)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.out_dir, ignore_errors=True)

    # --- helpers ---------------------------------------------------------------------------
    def tex(self, x: float, z: float):
        j = int(round((x + 4096.0) / self.spacing))
        i = int(round((z + 4096.0) / self.spacing))
        return min(max(i, 0), self.n - 1), min(max(j, 0), self.n - 1)

    def height_at(self, x: float, z: float) -> float:
        i, j = self.tex(x, z)
        return float(self.H[i, j])

    def region_at(self, x: float, z: float) -> str:
        i, j = self.tex(x, z)
        idx = int(self.region[i, j])
        ids = self.manifest["regions"]
        return ids[idx] if idx < len(ids) else "open_water"

    # --- the contract ------------------------------------------------------------------------
    def test_manifest_fields(self):
        m = self.manifest
        for key in ["seed", "size_m", "spacing_m", "origin", "grid", "sea_level", "lake_level",
                    "regions", "cell_size_m", "cells", "runtime"]:
            self.assertIn(key, m)
        self.assertEqual(m["size_m"], 8192)
        self.assertEqual(m["cell_size_m"], 256)
        self.assertEqual(m["cells"], [32, 32])
        self.assertEqual(m["origin"], [-4096.0, -4096.0])
        self.assertEqual(m["lake_level"], 8)
        self.assertEqual(len(m["regions"]), len(self.regions))
        self.assertEqual(m["grid"] * m["spacing_m"], m["size_m"])

    def test_every_contract_file_exists_with_the_right_size(self):
        n = self.n
        expected = {
            "heights.r32": n * n * 4,
            "region_mask.u8": n * n,
            "texture_base.u8": n * n,
            "texture_overlay.u8": n * n,
            "texture_blend.u8": n * n,
            "color.rgba8": n * n * 4,
            "water_mask.u8": n * n,
            "flow.rg8": n * n * 2,
            "control.u32": n * n * 4,
        }
        for name, size in expected.items():
            path = os.path.join(self.out_dir, name)
            self.assertTrue(os.path.exists(path), "%s is missing" % name)
            self.assertEqual(os.path.getsize(path), size, "%s is the wrong size" % name)
        for name in ["rivers.json", "roads.json", "pois.json", "world_manifest.json"]:
            self.assertTrue(os.path.exists(os.path.join(self.out_dir, name)), "%s is missing" % name)

    def test_runtime_copies(self):
        rt = self.manifest["runtime"]
        g = int(rt["grid"])
        for key, per_texel in (("heights", 4), ("regions", 1), ("water", 1), ("water_level", 4)):
            path = os.path.join(self.out_dir, rt[key])
            self.assertTrue(os.path.exists(path), "%s is missing" % rt[key])
            self.assertEqual(os.path.getsize(path), g * g * per_texel)

    def test_control_map_packing(self):
        """control.u32 must decode back to the base/overlay/blend maps (Terrain3D's format)."""
        ctrl = np.fromfile(os.path.join(self.out_dir, "control.u32"), dtype="<u4").reshape(self.n, self.n)
        np.testing.assert_array_equal((ctrl >> 27) & 0x1F, self.base)
        np.testing.assert_array_equal((ctrl >> 22) & 0x1F, self.overlay)
        np.testing.assert_array_equal((ctrl >> 14) & 0xFF, self.blend)
        self.assertTrue(((ctrl >> 2) & 1 == 0).all(), "no holes should be punched")

    def test_cells_cover_the_world(self):
        cells_dir = os.path.join(self.out_dir, "cells")
        files = [f for f in os.listdir(cells_dir) if f.endswith(".json")]
        self.assertEqual(len(files), 32 * 32)
        total = 0
        for name in ("16_16.json", "20_25.json", "6_10.json"):
            with open(os.path.join(cells_dir, name), "r", encoding="utf-8") as f:
                cell = json.load(f)
            cx, cz = (int(v) for v in name[:-5].split("_"))
            self.assertEqual(cell["cell"], [cx, cz])
            for key in ("region", "instances", "scenes", "spawns", "lights"):
                self.assertIn(key, cell)
            for asset, rows in cell["instances"].items():
                self.assertTrue(asset.startswith("res://assets/models/"))
                for row in rows:
                    self.assertEqual(len(row), 6)
                    x, y, z = float(row[0]), float(row[1]), float(row[2])
                    self.assertEqual(int((x + 4096) // 256), cx)
                    self.assertEqual(int((z + 4096) // 256), cz)
                    self.assertAlmostEqual(y, self.height_at(x, z), delta=3.0)
                    self.assertTrue(row[5].startswith("#") and len(row[5]) == 7)
                total += len(rows)
        self.assertGreater(total, 0, "the sampled cells have no scatter at all")

    # --- the geography -----------------------------------------------------------------------
    def test_height_extremes(self):
        self.assertLess(self.H.min(), 0.0, "there is no sea")
        self.assertGreater(self.H.max(), 550.0, "the northern peaks are too low")
        self.assertLess(self.H.max(), 900.0, "something spikes above the mountains")
        self.assertFalse(np.isnan(self.H).any())

    def test_regions_are_where_their_places_are(self):
        misplaced = []
        for p in self.places:
            x, z = p["position"]
            got = self.region_at(x, z)
            if got == "open_water" and p["kind"] == "deep_place":
                continue                      # the Sunken Barge is meant to be under the Mere
            if got != p["region"]:
                misplaced.append("%s -> %s" % (p["id"], got))
        self.assertEqual(misplaced, [], "places fell outside their region")

    def test_every_region_owns_a_fair_share_of_the_map(self):
        counts = np.bincount(self.region.ravel(), minlength=256)
        land = counts[:len(self.manifest["regions"])].sum()
        for i, rid in enumerate(self.manifest["regions"]):
            share = counts[i] / land
            self.assertGreater(share, 0.04, "%s covers only %.1f%% of the land" % (rid, 100 * share))

    def test_the_mere_and_the_sea(self):
        # the Mere: water at the lake level, deep in the middle, with the island dry
        self.assertTrue(self.water[self.tex(0.0, -700.0)] != 0, "the middle of the Mere is dry")
        self.assertLess(self.height_at(0.0, -700.0), 8.0)
        self.assertGreater(self.height_at(0.0, -150.0), 8.0, "Tollmere's island is under water")
        # the Grey Sea in the west, land in the east
        self.assertLess(self.height_at(-4000.0, 0.0), 0.0)
        self.assertGreater(self.height_at(3900.0, 0.0), 100.0, "the Thornmarch should rise")
        water_fraction = float((self.water != 0).mean())
        self.assertTrue(0.05 < water_fraction < 0.35, "water covers %.1f%% of the map" % (100 * water_fraction))

    def test_settlements_are_flat_and_dry(self):
        for p in self.places:
            if p["kind"] not in ("city", "town", "village", "hamlet", "fort", "camp"):
                continue
            x, z = p["position"]
            i, j = self.tex(x, z)
            self.assertEqual(int(self.water[i, j]), 0, "%s stands in water" % p["id"])
            r = max(2, int(30.0 / self.spacing))
            patch = self.H[i - r:i + r, j - r:j + r]
            self.assertLess(float(patch.max() - patch.min()), 6.0,
                            "%s's pad is not flat (%.1f m of relief)" % (p["id"], float(np.ptp(patch))))

    def test_rivers_run_downhill_into_the_water(self):
        with open(os.path.join(self.out_dir, "rivers.json"), "r", encoding="utf-8") as f:
            rivers = json.load(f)
        self.assertGreaterEqual(len(rivers), 3)
        ids = {r["id"] for r in rivers}
        self.assertIn("core:river/mere_outflow", ids)
        for r in rivers:
            self.assertGreaterEqual(len(r["points"]), 8)
            self.assertLessEqual(r["surface_to_m"], r["surface_from_m"] + 0.01, "%s runs uphill" % r["id"])
            self.assertTrue(4.0 <= r["width_m"] <= 14.0)
            # the mouth ends in standing water
            mx, mz = r["points"][-1]
            i, j = self.tex(mx, mz)
            near = self.water[max(i - 3, 0):i + 4, max(j - 3, 0):j + 4]
            self.assertTrue(near.any(), "%s does not reach any water" % r["id"])

    def test_roads_connect_the_settlements(self):
        with open(os.path.join(self.out_dir, "roads.json"), "r", encoding="utf-8") as f:
            roads = json.load(f)
        self.assertGreaterEqual(len(roads), 8)
        named = set()
        for r in roads:
            self.assertTrue(4.0 <= r["width_m"] <= 6.0)
            self.assertGreaterEqual(len(r["points"]), 4)
            for part in r["id"].split("/")[-1].split("_"):
                named.add(part)
        for town in ("merrowby", "tollmere", "isseva", "kharrow", "hollow"):
            self.assertTrue(any(town in n for n in named), "no road reaches %s" % town)

    def test_texture_rules_put_the_right_ground_in_each_region(self):
        names = self.manifest["texture_slots"]
        self.assertEqual(len(names), 21)

        def top_slot(x, z, radius=150.0):
            i, j = self.tex(x, z)
            k = max(1, int(radius / self.spacing))
            patch = self.base[i - k:i + k, j - k:j + k]
            counts = np.bincount(patch.ravel(), minlength=21)
            return [names[m] for m in np.argsort(counts)[::-1][:3]]

        self.assertIn("vale_grass", top_slot(1400.0, 2600.0))           # the downs
        self.assertTrue({"peat", "mud", "sand_flats"} & set(top_slot(-3000.0, -800.0)))   # the marsh
        self.assertIn("forest_floor", top_slot(3000.0, 600.0))          # the wold
        self.assertTrue({"limestone", "scree", "heather"} & set(top_slot(0.0, -3000.0)))  # the karst
        self.assertTrue({"ash_soil", "grey_grass", "fused_stone"} & set(top_slot(-2000.0, 2600.0)))
        self.assertIn("lake_bed", top_slot(0.0, -700.0))                # under the Mere
        # snow only on the tops
        snow = self.base == names.index("snow")
        if snow.any():
            self.assertGreater(float(self.H[snow].min()), 380.0, "snow is lying too low")

    def test_colour_map_separates_the_regions(self):
        """The drop test's automated proxy: region palettes must not all average to the same tint."""
        tints = {}
        for i, rid in enumerate(self.manifest["regions"]):
            mask = self.region == i
            if mask.sum() < 100:
                continue
            rgb = self.colour[..., :3][mask].astype(np.float32).mean(axis=0) / 255.0
            tints[rid] = rgb / max(rgb.mean(), 1e-5)
        self.assertGreaterEqual(len(tints), 5)
        keys = list(tints)
        worst = min(
            float(np.abs(tints[a] - tints[b]).sum())
            for k, a in enumerate(keys) for b in keys[k + 1:]
        )
        self.assertGreater(worst, 0.03, "two regions have nearly the same colour cast")

    def test_determinism(self):
        """Same seed, same world: the builder is a pure function of its inputs."""
        other = tempfile.mkdtemp(prefix="wickmere_world_again_")
        try:
            subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"),
                            "--size", "512", "--out", other], check=True, capture_output=True, timeout=600)
            first = os.path.join(other, "heights.r32")
            with open(first, "rb") as f:
                a = f.read()
            subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"),
                            "--size", "512", "--out", other], check=True, capture_output=True, timeout=600)
            with open(first, "rb") as f:
                b = f.read()
            self.assertEqual(a, b, "two builds with the same seed differ")
        finally:
            shutil.rmtree(other, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
