#!/usr/bin/env python3
"""Build a small world into a temporary directory and check what came out.

    python3 tools/world/tests/test_build.py          # or: python3 -m unittest discover tools/world/tests

The build is run at --size 1024 (8 m per texel) from the committed atlas and exercises every
stage: provinces, heights, drainage, the coast and the lakes, pads, rivers, roads, water,
textures, colour, POIs and cells. The assertions are the parts of docs/CONTRACTS.md §6 that other
streams rely on, plus the geography the atlas draws: they read where things are from the atlas,
so a new map is held to its own drawing and not to the old one's coordinates.
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

from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import geography as GEO  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

SIZE = 1024
PACK = os.path.join(REPO, "game", "content", "packs", "core")


## How long a whole build may take. The drawn atlas's scatter draws its candidates in metres, not
## texels, so it costs about as much at 1024 as at 4096. It was 430 to 840 s of a 512 build, and a
## 1024 build ran past fifteen minutes on a busy machine; reading each field only where a
## candidate still stands a chance (`ScatterFields`) took it from 426 s to 69 s of a 1024 build,
## which now takes under three minutes. The limit is left generous for a busy machine.
BUILD_TIMEOUT_S = 2400


def build_once(out_dir: str) -> dict:
    cmd = [sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", str(SIZE), "--out", out_dir]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=BUILD_TIMEOUT_S)
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
        cls.atlas = ATLAS.load()
        cls.grid = Grid(8192.0, n)

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

    def deepest_inside(self, poly, not_in=(), on_land=False, with_depth=False) -> tuple:
        """(i, j) of the texel furthest inside `poly` (and outside every polygon in `not_in`, and
        on the land when `on_land`); with `with_depth`, (i, j, how far inside it is in metres)."""
        m = GEO.polygon_mask(self.grid, poly)
        if on_land:
            m &= GEO.land_mask(self.grid, self.atlas)
            # and in from the edge of the world, which the distance does not count as an edge
            e = max(1, int(300.0 / self.spacing))
            m[:e] = m[-e:] = False
            m[:, :e] = m[:, -e:] = False
        for other in not_in:
            m &= ~GEO.polygon_mask(self.grid, other)
        sd = GEO.signed_distance(self.grid, m)
        k = int(np.argmin(sd))
        if with_depth:
            return k // self.n, k % self.n, -float(sd.ravel()[k])
        return k // self.n, k % self.n

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
        lakes = self.atlas.get("lakes", [])
        if lakes:
            biggest = max(lakes, key=lambda lk: ATLAS.polygon_area(lk["polygon"]))
            self.assertEqual(m["lake_level"], biggest["level_m"])
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

    def test_every_pad_says_how_far_it_is_level(self):
        """pois.json's `radius_level_m` is how far out a pad is truly level, and where a
        settlement's houses may stand (CONTRACTS 6); `radius_flat_m` is the pad's radius as it
        was. Every settlement is level out to its `radius_level_m`, give or take the roads and
        rivers laid over it."""
        from worldgen import roads as RD

        with open(os.path.join(self.out_dir, "pois.json"), "r", encoding="utf-8") as f:
            pois = {e["place_id"]: e for e in json.load(f)}
        for pid, e in pois.items():
            self.assertIn("radius_level_m", e, "%s has no radius_level_m" % pid)
            if pid not in RD.RING_TOWNS:
                self.assertLessEqual(e["radius_level_m"], e["radius_flat_m"] + 1e-6, pid)
        hollow = pois["core:place/grandfather_hollow"]
        self.assertEqual(hollow["radius_level_m"], 72.0)
        places = {p["id"]: p for p in self.places}
        self.assertAlmostEqual(hollow["radius_flat_m"], RD.pad_radius(places["core:place/grandfather_hollow"]))
        X, Z = self.grid.mesh()
        for pid, p in places.items():
            if RD.FABRIC_COUNT.get(p.get("kind"), 0) <= 0 or pid not in pois:
                continue
            x, y, z = pois[pid]["pos"]
            r = float(pois[pid]["radius_level_m"])
            if pid not in RD.RING_TOWNS:
                # level to its whole radius: the fabric's houses go out to radius - 8
                self.assertAlmostEqual(r, float(pois[pid]["radius_flat_m"]), places=1, msg=pid)
            disc = ((X - x) ** 2 + (Z - z) ** 2 <= r * r) & (self.water == 0)
            level = float(np.median(self.H[disc]))
            share = float((np.abs(self.H[disc] - level) < 0.3).mean())
            self.assertGreater(share, 0.95, "%s is level on only %.0f%% of its %.1f m" % (pid, 100 * share, r))

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
                    # six fields, and the lean pair after them for a bent tree or a seated rock
                    self.assertIn(len(row), (6, 8, 9))
                    x, y, z = float(row[0]), float(row[1]), float(row[2])
                    self.assertEqual(int((x + 4096) // 256), cx)
                    self.assertEqual(int((z + 4096) // 256), cz)
                    self.assertAlmostEqual(y, self.height_at(x, z), delta=3.0)
                    self.assertTrue(row[5].startswith("#") and len(row[5]) == 7)
                total += len(rows)
        self.assertGreater(total, 0, "the sampled cells have no scatter at all")

    # --- the geography -----------------------------------------------------------------------
    def test_height_extremes(self):
        if not all(ATLAS.on_land(self.atlas, x, z) for x, z in ((-4000, -4000), (4000, -4000), (-4000, 4000), (4000, 4000))):
            self.assertLess(self.H.min(), 0.0, "there is no sea")
        tops = [p[2] for rg in self.atlas.get("ranges", []) for p in rg["ridge"]]
        tops += [pk["height_m"] for pk in self.atlas.get("peaks", [])]
        tops += [pv["base_height_m"] + pv["relief_m"] for pv in self.atlas["provinces"]]
        self.assertGreater(self.H.max(), 0.8 * max(tops), "the highest ground is too low")
        self.assertLess(self.H.max(), 1.25 * max(tops) + 40.0, "something spikes above the mountains")
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

    def test_the_lakes_and_the_sea(self):
        # every lake: water at its level in the middle, and its islands dry
        for lake in self.atlas.get("lakes", []):
            islands = [s["polygon"] for s in lake.get("islands", [])]
            i, j = self.deepest_inside(lake["polygon"], islands)
            self.assertTrue(self.water[i, j] != 0, "the middle of %s is dry" % lake["id"])
            self.assertLess(float(self.H[i, j]), lake["level_m"])
            for s in lake.get("islands", []):
                i, j = self.deepest_inside(s["polygon"])
                self.assertGreater(float(self.H[i, j]), lake["level_m"], "an island of %s is under water" % lake["id"])
        # the sea, as far from the land as it gets
        land = GEO.land_mask(self.grid, self.atlas)
        if not land.all():
            k = int(np.argmax(GEO.signed_distance(self.grid, land)))
            self.assertLess(float(self.H.ravel()[k]), 0.0, "the open sea is not under the sea")
        # every range's crest stands near the height drawn for it
        for rg in self.atlas.get("ranges", []):
            mid = rg["ridge"][len(rg["ridge"]) // 2]
            i, j = self.tex(mid[0], mid[1])
            k = max(1, int(60.0 / self.spacing))
            top = float(self.H[max(i - k, 0):i + k + 1, max(j - k, 0):j + k + 1].max())
            self.assertGreater(top, 0.75 * mid[2], "%s stands %.0f m at %s, drawn %.0f" % (rg["id"], top, mid[:2], mid[2]))
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
        drawn = {rv["id"]: rv for rv in self.atlas.get("rivers", [])}
        self.assertEqual({r["id"] for r in rivers}, set(drawn))
        for r in rivers:
            # a river's line is written every 20 m: it has two points or more, and no gap longer
            # than 30 m, which would be a chord across what it should have followed (the atlas
            # draws Weaver's Gill into its linn in 93 m, six points)
            pts = np.asarray([[p[0], p[-1]] for p in r["points"]], dtype=np.float64)
            self.assertGreaterEqual(len(pts), 2, "%s has no line" % r["id"])
            self.assertLessEqual(float(np.linalg.norm(np.diff(pts, axis=0), axis=1).max()), 30.0,
                                 "%s's line has a gap" % r["id"])
            self.assertLessEqual(r["surface_to_m"], r["surface_from_m"] + 0.01, "%s runs uphill" % r["id"])
            w0, w1 = drawn[r["id"]]["width_m"]
            self.assertTrue(min(w0, w1) - 0.01 <= r["width_m"] <= max(w0, w1) + 0.01)
            # the mouth ends in standing water
            mx, mz = r["points"][-1]
            i, j = self.tex(mx, mz)
            near = self.water[max(i - 3, 0):i + 4, max(j - 3, 0):j + 4]
            self.assertTrue(near.any(), "%s does not reach any water" % r["id"])

    def test_the_drawn_roads_are_built(self):
        with open(os.path.join(self.out_dir, "roads.json"), "r", encoding="utf-8") as f:
            roads = json.load(f)
        built = {r["id"]: r for r in roads}
        for spec in self.atlas.get("roads", []):
            rid = spec.get("id") or "core:road/%s_%s" % (spec["from"].split("/")[-1], spec["to"].split("/")[-1])
            self.assertIn(rid, built, "the road %s - %s was not built" % (spec["from"], spec["to"]))
            r = built[rid]
            self.assertTrue(3.0 <= r["width_m"] <= 6.0)
            self.assertGreaterEqual(len(r["points"]), 4)

    def test_texture_rules_put_the_right_ground_in_each_region(self):
        names = self.manifest["texture_slots"]
        self.assertEqual(len(names), 21)

        def top_slot(x, z, radius=150.0):
            i, j = self.tex(x, z)
            k = max(1, int(radius / self.spacing))
            # clamped: a window off the edge of the array is empty, and an empty count says
            # the last three slots are the commonest
            patch = self.base[max(i - k, 0):i + k, max(j - k, 0):j + k]
            counts = np.bincount(patch.ravel(), minlength=21)
            return [names[m] for m in np.argsort(counts)[::-1][:3]]

        expect = {"downs": {"vale_grass"}, "delta": {"peat", "mud", "sand_flats"},
                  "forest_rise": {"forest_floor"}, "mountains": {"limestone", "scree", "heather", "snow", "vale_grass"},
                  "ash_plateau": {"ash_soil", "grey_grass", "fused_stone"},
                  "lake_basin": {"vale_grass", "shingle", "lake_bed", "mud"}}
        lakes = [lk["polygon"] for lk in self.atlas.get("lakes", [])]
        for prov in self.atlas["provinces"]:
            i, j = self.deepest_inside(prov["polygon"], lakes, on_land=True)
            x, z = -4096.0 + j * self.spacing, -4096.0 + i * self.spacing
            got = set(top_slot(x, z))
            self.assertTrue(expect[prov["biome"]] & got, "%s (%s) at (%.0f, %.0f) is %s"
                            % (prov["id"], prov["biome"], x, z, sorted(got)))
        for lake in self.atlas.get("lakes", []):
            i, j, depth = self.deepest_inside(lake["polygon"], [s["polygon"] for s in lake.get("islands", [])],
                                              with_depth=True)
            # A drawn tarn is a hundred metres across, and its water begins some thirty metres
            # inside its line (SCHEMA.md): a 150 m window round its middle is mostly its shore
            # and the fell round it. So the window is half as wide as the middle is deep inside.
            radius = min(150.0, max(0.5 * depth, 2.0 * self.spacing))
            self.assertIn("lake_bed", top_slot(-4096.0 + j * self.spacing, -4096.0 + i * self.spacing, radius),
                          "%s, %.0f m inside its line" % (lake["id"], depth))
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
        """Same seed, same world: the builder is a pure function of its inputs.

        The heights are final before the textures and the scatter begin, so two heights builds
        say what two whole builds would about heights.r32. A whole build of the drawn atlas
        spends seven to fifteen minutes in the scatter at any size (its candidates are drawn in
        metres), and ran past this test's ten minutes on a busy machine. Two whole 512 builds
        of it were byte for byte the same in every file, cells and all."""
        other = tempfile.mkdtemp(prefix="wickmere_world_again_")
        try:
            subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"),
                            "--size", "512", "--only", "heights", "--out", other],
                           check=True, capture_output=True, timeout=600)
            first = os.path.join(other, "heights.r32")
            with open(first, "rb") as f:
                a = f.read()
            subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"),
                            "--size", "512", "--only", "heights", "--out", other],
                           check=True, capture_output=True, timeout=600)
            with open(first, "rb") as f:
                b = f.read()
            self.assertEqual(a, b, "two builds with the same seed differ")
        finally:
            shutil.rmtree(other, ignore_errors=True)


class CellFiling(unittest.TestCase):
    """A thing is filed in the cell its written coordinates stand in. A grass tuft at x = -2304.004
    was filed by its unrounded position in cell 6, written as -2304.0, and read as cell 7's
    (test_cells_cover_the_world, on a 1024 build of the drawn atlas)."""

    def test_a_row_is_filed_where_it_is_written(self):
        grid = Grid(8192.0, 1024)
        self.assertEqual(grid.written_cell(-2304.004, 0.0), (7, 16))
        self.assertEqual(grid.written_cell(-2304.006, 0.0), (6, 16))
        self.assertEqual(grid.written_cell(-5000.0, 5000.0), (0, 31))


class ScatterFields(unittest.TestCase):
    """The scatter reads each field only where a candidate still stands a chance
    (`ScatterWorld.field`), and what it reads is what reading them all at once read (`sample`):
    so the scatter is the same to the byte, and costs a tenth of what it did."""

    def test_each_field_is_the_one_the_whole_sample_gave(self):
        from worldgen import cells as CELLS

        grid = Grid(8192.0, 128)
        rng = np.random.default_rng(3)
        n = grid.n

        def f32():
            return rng.normal(0.0, 1.0, (n, n)).astype(np.float32)

        world = CELLS.ScatterWorld(grid, f32(), rng.integers(0, 5, (n, n)).astype(np.uint8), f32(),
                                   rng.integers(0, 2, (n, n)).astype(np.uint8), f32(), f32(),
                                   rng.random((n, n)) > 0.8, f32(), None, [], water_d=f32(), field_d=f32(),
                                   pad_t=f32(), tpi=f32(), forests={"oakwood": f32(), "pinewood": f32()})
        x = rng.uniform(-4000.0, 4000.0, 5000).astype(np.float32)
        z = rng.uniform(-4000.0, 4000.0, 5000).astype(np.float32)
        whole = world.sample(x, z)
        some = np.arange(0, 5000, 7)
        for name, vals in whole.items():
            one = world.field(name, x[some], z[some])
            self.assertEqual(one.dtype, vals.dtype, name)
            self.assertTrue(np.array_equal(one, vals[some]), name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
