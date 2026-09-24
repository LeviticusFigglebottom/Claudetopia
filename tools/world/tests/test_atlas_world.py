#!/usr/bin/env python3
"""A world built from the atlas is the land the atlas draws.

    python3 -m pytest tools/world/tests/test_atlas_world.py

The committed atlas (tools/world/atlas/atlas.json) is built small, heights only, and held to its
own drawing: the sea outside the coast, every lake at its level with its islands dry, every range
and peak at its height, every province on its own ground, every river falling to the water it
runs into, the start on dry land, and the region the game reads under each province. The landing
it draws under a cliff (a shelf, a stair, a pad) is built at 1024 and held to it. Then a wood is
drawn on it, and the build is held to planting it.
"""
from __future__ import annotations

import copy
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
sys.path.insert(0, TOOLS_WORLD)

from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import geography as GEO  # noqa: E402
from worldgen.grid import Grid  # noqa: E402
from worldgen.heights import EROSION_DEPTH  # noqa: E402

SIZE = 512
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
PACK = os.path.join(REPO, "game", "content", "packs", "core")


def build(out: str, *extra) -> dict:
    proc = subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", str(SIZE),
                           "--out", out, *extra], capture_output=True, text=True, timeout=1500)
    if proc.returncode != 0:
        raise AssertionError("build failed:\n%s\n%s" % (proc.stdout[-3000:], proc.stderr[-3000:]))
    with open(os.path.join(out, "world_manifest.json"), "r", encoding="utf-8") as f:
        return json.load(f)


class AtlasToHeights(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = tempfile.mkdtemp(prefix="wickmere_atlas_")
        cls.man = build(cls.out, "--only", "heights")
        n = int(cls.man["grid"])
        cls.n = n
        cls.grid = Grid(8192.0, n)
        cls.H = np.fromfile(os.path.join(cls.out, "heights.r32"), dtype="<f4").reshape(n, n)
        cls.W = np.fromfile(os.path.join(cls.out, "water_mask.u8"), dtype=np.uint8).reshape(n, n)
        cls.R = np.fromfile(os.path.join(cls.out, "region_mask.u8"), dtype=np.uint8).reshape(n, n)
        rt = cls.man["runtime"]
        g = int(rt["grid"])
        cls.rt_n = g
        cls.levels = np.fromfile(os.path.join(cls.out, rt["water_level"]), dtype="<f4").reshape(g, g)
        with open(os.path.join(cls.out, "rivers.json"), "r", encoding="utf-8") as f:
            cls.rivers = {r["id"]: r for r in json.load(f)}
        cls.atlas = ATLAS.load()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.out, ignore_errors=True)

    def tex(self, x, z):
        j = int(round((x + 4096.0) / self.grid.spacing))
        i = int(round((z + 4096.0) / self.grid.spacing))
        return min(max(i, 0), self.n - 1), min(max(j, 0), self.n - 1)

    def test_the_sea_is_outside_the_coast(self):
        land = GEO.land_mask(self.grid, self.atlas)
        sd = GEO.signed_distance(self.grid, land)
        far = sd > 300.0
        if far.any():
            self.assertLess(float(self.H[far].max()), -1.0, "the open sea stands above the water")
        inland = sd < -500.0
        lakes = np.zeros_like(land)
        for lake in self.atlas.get("lakes", []):
            lakes |= GEO.polygon_mask(self.grid, lake["polygon"])
        dry = inland & ~lakes
        self.assertGreater(float((self.H[dry] > 0.0).mean()), 0.99, "the land is under the sea")

    def test_every_lake_stands_at_its_level_with_its_islands_dry(self):
        f = self.n // self.rt_n
        for lake in self.atlas.get("lakes", []):
            water = GEO.polygon_mask(self.grid, lake["polygon"])
            isl = np.zeros_like(water)
            for s in lake.get("islands", []):
                isl |= GEO.polygon_mask(self.grid, s["polygon"])
            # an island's foot and a causeway's bank stand in the water, and are not its bed
            off = GEO.signed_distance(self.grid, isl) > 60.0 if isl.any() else np.ones_like(isl)
            places = {p["id"]: p for p in ATLAS._content(PACK)[1] + ATLAS._content(PACK)[2]}
            for _road, p, q in GEO.causeway_legs(self.atlas, places):
                lf = GEO.line_field(self.grid, [p, q], 80.0)
                i0, i1, j0, j1 = lf.window
                off[i0:i1, j0:j1] &= lf.d > 60.0
            # and a place or a point of interest drawn in the water (a jetty, the Bell-Buoys)
            # stands on a pad of its own over it
            from worldgen import roads as RD
            X, Z = self.grid.mesh()
            for p in places.values():
                px, pz = float(p["position"][0]), float(p["position"][1])
                if ATLAS.point_in_polygon(px, pz, lake["polygon"]):
                    off &= (X - px) ** 2 + (Z - pz) ** 2 > (1.6 * RD.pad_radius(p) + self.grid.spacing) ** 2
            # the middle of the lake: 150 m in, or the inner half of a pool smaller than that
            sd = GEO.signed_distance(self.grid, water)
            deep = (sd < -min(150.0, 0.5 * float(-sd.min()))) & ~isl & off
            self.assertGreater(float((self.W[deep] > 0).mean()), 0.97, "%s is dry in the middle" % lake["id"])
            self.assertLess(float(self.H[deep].max()), lake["level_m"], "%s's bed rises out of it" % lake["id"])
            lv = self.levels[deep[::f, ::f]]
            self.assertTrue(np.allclose(lv, lake["level_m"], atol=0.01), "%s's water is not at %s m" % (lake["id"], lake["level_m"]))
            for s in lake.get("islands", []):
                m = GEO.polygon_mask(self.grid, s["polygon"])
                core = (GEO.signed_distance(self.grid, m) < -30.0)
                if core.any():
                    self.assertGreater(float(self.H[core].max()), lake["level_m"] + 2.0, "an island of %s is awash" % lake["id"])

    def test_the_ranges_and_peaks_stand_at_their_heights(self):
        k = max(1, int(80.0 / self.grid.spacing))
        for rg in self.atlas.get("ranges", []):
            for x, z, crest in rg["ridge"][1:-1]:
                i, j = self.tex(x, z)
                top = float(self.H[max(i - k, 0):i + k + 1, max(j - k, 0):j + k + 1].max())
                self.assertGreater(top, 0.75 * crest, "%s at (%.0f, %.0f): %.0f m, drawn %.0f" % (rg["id"], x, z, top, crest))
                self.assertLess(top, 1.3 * crest + 30.0, "%s at (%.0f, %.0f): %.0f m, drawn %.0f" % (rg["id"], x, z, top, crest))
        for pk in self.atlas.get("peaks", []):
            i, j = self.tex(*pk["at"])
            r = max(1, int(0.2 * pk["radius_m"] / self.grid.spacing))
            top = float(self.H[max(i - r, 0):i + r + 1, max(j - r, 0):j + r + 1].max())
            self.assertGreater(top, 0.8 * pk["height_m"])

    def test_every_province_stands_on_its_own_ground(self):
        lakes = np.zeros((self.n, self.n), dtype=bool)
        for lake in self.atlas.get("lakes", []):
            lakes |= GEO.polygon_mask(self.grid, lake["polygon"])
        near_range = np.zeros_like(lakes)
        for rg in self.atlas.get("ranges", []):
            lf = GEO.line_field(self.grid, [[p[0], p[1]] for p in rg["ridge"]], rg["width_m"])
            i0, i1, j0, j1 = lf.window
            near_range[i0:i1, j0:j1] |= lf.d < rg["width_m"]
        land = GEO.land_mask(self.grid, self.atlas)
        coast_sd = GEO.signed_distance(self.grid, land)
        for prov in self.atlas["provinces"]:
            inside = GEO.signed_distance(self.grid, GEO.polygon_mask(self.grid, prov["polygon"])) < -400.0
            own = inside & ~lakes & ~near_range & (coast_sd < -300.0)
            if own.sum() < 20:
                continue
            h = self.H[own]
            base, relief = prov["base_height_m"], prov["relief_m"]
            cut = EROSION_DEPTH.get(prov["biome"], 15.0)
            low, mid = float(np.percentile(h, 5)), float(np.percentile(h, 50))
            self.assertGreater(low, base - cut - 12.0, "%s: its low ground is %.0f m, drawn %.0f" % (prov["id"], low, base))
            self.assertLess(mid, base + relief + 20.0, "%s: its middle ground is %.0f m, drawn %.0f + %.0f" % (prov["id"], mid, base, relief))
            self.assertGreater(float(np.percentile(h, 95)) - low, 0.25 * relief, "%s has none of its relief" % prov["id"])

    def test_every_river_falls_to_the_water_it_runs_into(self):
        self.assertEqual(set(self.rivers), {rv["id"] for rv in self.atlas.get("rivers", [])})
        for rv in self.atlas.get("rivers", []):
            built = self.rivers[rv["id"]]
            self.assertLessEqual(built["surface_to_m"], built["surface_from_m"])
            # the surface the game draws the water at is given at every point, and falls
            surface = np.asarray(built["surface_m"], dtype=np.float64)
            self.assertEqual(surface.shape[0], len(built["points"]))
            self.assertLessEqual(float(np.diff(surface).max()), 0.01, "%s runs uphill" % rv["id"])
            self.assertAlmostEqual(float(surface[0]), built["surface_from_m"], places=1)
            self.assertAlmostEqual(float(surface[-1]), built["surface_to_m"], places=1)
            mx, mz = rv["path"][-1]
            lake = ATLAS.lake_at(self.atlas, mx, mz)
            if lake is not None:
                # A river falls at least 5 cm a point (hydro.atlas_rivers). One whose source this
                # grid puts too low to fall to its lake ends under the lake's level instead: at
                # 16 m texels the Blackgill's head comes out 30 m lower than at 2 m, under its
                # pot's 189 m, where the full build has it at 218 m and falling to 189.
                drop = 0.05 * (len(built["points"]) - 1)
                if built["surface_from_m"] - drop >= lake["level_m"]:
                    self.assertAlmostEqual(built["surface_to_m"], lake["level_m"], places=1)
                else:
                    self.assertLess(built["surface_to_m"], lake["level_m"])
            elif not ATLAS.on_land(self.atlas, mx, mz):
                self.assertLess(built["surface_to_m"], 0.0)

    def test_the_start_is_on_dry_land(self):
        start = self.atlas.get("start")
        if not start:
            self.skipTest("the atlas has no start")
        self.assertIn("start", self.man)
        x, y, z = self.man["start"]["pos"]
        i, j = self.tex(x, z)
        self.assertEqual(int(self.W[i, j]), 0, "the start is in the water")
        self.assertGreater(y, 0.5)

    def test_an_authored_pad_stands_where_the_atlas_says(self):
        pads = self.atlas.get("pads", [])
        if not pads:
            self.skipTest("the atlas authors no pad")
        from worldgen import roads as RD

        things = {p["id"]: p for p in ATLAS._content(PACK)[1] + ATLAS._content(PACK)[2]}
        for pad in pads:
            place = dict(things[pad["place"]])
            if pad.get("radius_m"):
                place["pad_radius_m"] = pad["radius_m"]
            x, z = (float(v) for v in place["position"][:2])
            i, j = self.tex(x, z)
            y = float(self.H[i, j])
            self.assertAlmostEqual(y, pad["level_m"], delta=0.3, msg="%s stands at %.2f m" % (pad["place"], y))
            r = 0.6 * RD.pad_radius(place)
            k = max(1, int(r / self.grid.spacing))
            i, j = self.tex(x, z)
            core = self.H[max(i - k, 0):i + k + 1, max(j - k, 0):j + k + 1]
            wet = self.W[max(i - k, 0):i + k + 1, max(j - k, 0):j + k + 1]
            self.assertLess(float(np.abs(core - pad["level_m"]).max()), 1.0, "%s's pad is not flat" % pad["place"])
            self.assertEqual(int(wet.sum()), 0, "%s's pad is awash" % pad["place"])

    def test_the_game_reads_each_provinces_region(self):
        ids = self.man["regions"]
        lakes = [lk["polygon"] for lk in self.atlas.get("lakes", [])]
        land = GEO.land_mask(self.grid, self.atlas)
        for prov in self.atlas["provinces"]:
            m = GEO.polygon_mask(self.grid, prov["polygon"]) & land
            for poly in lakes:
                m &= ~GEO.polygon_mask(self.grid, poly)
            sd = GEO.signed_distance(self.grid, m)
            k = int(np.argmin(sd))
            got = int(self.R.ravel()[k])
            self.assertLess(got, len(ids), "the middle of %s is open water" % prov["id"])
            self.assertEqual(ids[got], prov["region"], "the middle of %s reads as %s" % (prov["id"], ids[got]))


class SightlineSaddles(unittest.TestCase):
    """The land is cut under an authored sightline by a saddle's depth, and no more."""

    K = {"EYE_M": 1.65, "LANDMARK_M": {}, "LANDMARK_DEFAULT_M": 6.0, "CLEARANCE_M": 2.0,
         "FOREGROUND_M": 140.0, "MAX_SIGHT_M": 4200.0, "RAY_STEPS": 64}

    def _ground(self, hump_m):
        grid = Grid(8192.0, 1024)
        X, Z = grid.mesh()
        # flat at 20 m, with a ridge across the line at x = 0 standing `hump_m` over it
        H = (20.0 + hump_m * np.exp(-(X / 60.0) ** 2) + 0.0 * Z).astype(np.float32)
        return grid, H

    def _clear(self, grid, H):
        import sightlines as SL

        class Hs:
            def at(self, x, z):
                from worldgen.grid import sample_bilinear
                return float(sample_bilinear(H, grid, np.array([x]), np.array([z]))[0])
        a = (-600.0, float(H[512, 437]), 0.0)
        b = (600.0, float(H[512, 587]), 0.0)
        blocked, worst, _ = SL.blocked_at(Hs(), a, b, self.K, "")
        return blocked, worst

    def test_a_shoulder_in_the_way_is_given_a_saddle(self):
        sys.path.insert(0, os.path.dirname(TOOLS_WORLD))
        grid, H = self._ground(12.0)
        self.assertTrue(self._clear(grid, H)[0], "the ridge should block the line to begin with")
        done = GEO.honour_sightlines(grid, H, [((-600.0, 0.0), (600.0, 0.0), "", 25.0, 25.0)], self.K)
        self.assertEqual(len(done), 1)
        self.assertTrue(done[0][3], "a twelve-metre shoulder is within a saddle's depth")
        blocked, worst = self._clear(grid, H)
        self.assertFalse(blocked, "the line is still refused, %.2f m over" % worst)
        # the saddle is a notch, not a trench: a hundred metres off the line the ridge stands
        self.assertGreater(float(H[512 + int(100 / 8), 512]), 31.0)

    def test_a_mountain_in_the_way_is_left_and_said(self):
        grid, H = self._ground(200.0)
        before = H.copy()
        done = GEO.honour_sightlines(grid, H, [((-600.0, 0.0), (600.0, 0.0), "", 25.0, 25.0)], self.K)
        self.assertEqual(len(done), 1)
        self.assertFalse(done[0][3])
        self.assertTrue(np.array_equal(before, H), "a refused line must leave the land alone")

    def test_a_hidden_valley_is_left_hidden(self):
        grid, H = self._ground(12.0)
        before = H.copy()
        done = GEO.honour_sightlines(grid, H, [((-600.0, 0.0), (600.0, 0.0), "hidden_valley", 25.0, 25.0)], self.K)
        self.assertEqual(done, [])
        self.assertTrue(np.array_equal(before, H))


class TheLanding(unittest.TestCase):
    """Every landing the atlas draws is built as drawn: each rock shelf flat and dry at its height,
    each stair no steeper than a stair and down to the pad it serves, each authored pad at its
    level, and a pad by the sea above the water all the way to its edge.

    A new game starts on one: the Hushline Stair's pad on a shelf under the Stair Head's cliff,
    where the first fight is. At 1024 a texel is 8 m, which a 70 m shelf and a 26 m pad can be
    read at; the 512 build above cannot.
    """

    @classmethod
    def setUpClass(cls):
        cls.atlas = ATLAS.load()
        cls.shelves = cls.atlas.get("coast", {}).get("shelves", [])
        cls.stairs = [r for r in cls.atlas.get("roads", []) if r.get("kind") == "stair"]
        cls.pads = {p["place"]: p for p in cls.atlas.get("pads", [])}
        if not (cls.shelves or cls.stairs or cls.pads):
            raise unittest.SkipTest("the atlas draws no landing")
        cls.tmp = tempfile.mkdtemp(prefix="wickmere_landing_")
        out = os.path.join(cls.tmp, "world")
        proc = subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", "1024",
                               "--only", "heights", "--out", out], capture_output=True, text=True, timeout=1500)
        if proc.returncode != 0:
            raise AssertionError(proc.stdout[-3000:] + proc.stderr[-3000:])
        n = 1024
        cls.grid = Grid(8192.0, n)
        cls.H = np.fromfile(os.path.join(out, "heights.r32"), dtype="<f4").reshape(n, n)
        cls.W = np.fromfile(os.path.join(out, "water_mask.u8"), dtype=np.uint8).reshape(n, n)
        with open(os.path.join(out, "roads.json"), "r", encoding="utf-8") as f:
            cls.roads = {r["id"]: r for r in json.load(f)}
        with open(os.path.join(out, "road_profiles.json"), "r", encoding="utf-8") as f:
            cls.profiles = {r["id"]: r for r in json.load(f)}
        _regions, places, pois = ATLAS._content(PACK)
        cls.things = {p["id"]: p for p in list(places) + list(pois)}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def disc(self, x, z, r):
        X, Z = self.grid.mesh()
        return (X - x) ** 2 + (Z - z) ** 2 <= r * r

    def test_every_shelf_is_flat_dry_rock_at_its_height(self):
        if not self.shelves:
            self.skipTest("no shelf")
        for shelf in self.shelves:
            m = GEO.polygon_mask(self.grid, shelf["polygon"])
            core = GEO.signed_distance(self.grid, m) < -12.0
            self.assertGreater(int(core.sum()), 8, "a shelf too small to read at 8 m")
            h = self.H[core]
            self.assertLess(float(np.abs(h - shelf["height_m"]).max()), 1.2,
                            "a shelf drawn at %.1f m is %.1f..%.1f m" % (shelf["height_m"], h.min(), h.max()))
            self.assertEqual(int(self.W[core].sum()), 0, "a shelf is awash")

    def test_every_stair_goes_down_no_steeper_than_a_stair(self):
        if not self.stairs:
            self.skipTest("no stair")
        for spec in self.stairs:
            rid = spec.get("id") or "core:road/%s_%s" % (spec["from"].split("/")[-1], spec["to"].split("/")[-1])
            self.assertIn(rid, self.roads)
            self.assertEqual(self.roads[rid]["width_m"], 3.0)
            e = np.asarray(self.profiles[rid]["elevation_m"], dtype=np.float64)
            pts = np.asarray(self.roads[rid]["points"], dtype=np.float64)
            seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
            grade = np.abs(np.diff(e)) / np.maximum(seg, 1e-6)
            self.assertLessEqual(float(grade.max()), 0.72, "%s is %.2f at its steepest" % (rid, grade.max()))
            for end, level in ((spec["from"], e[0]), (spec["to"], e[-1])):
                if end in self.pads:
                    self.assertAlmostEqual(float(level), float(self.pads[end]["level_m"]), delta=0.3,
                                           msg="%s arrives at %s at %.2f m" % (rid, end, level))
            # and the ground it was graded into is still under it: nothing laid after the roads
            # (the shelf's broken edge once) cuts a hole in it. At 8 m a texel on a bank graded a
            # half is up to 1.5 m off the road's own line; the hole was 6.5 m.
            ii = np.clip(np.rint((pts[:, 1] - self.grid.z0) / self.grid.spacing).astype(int), 0, self.grid.n - 1)
            jj = np.clip(np.rint((pts[:, 0] - self.grid.x0) / self.grid.spacing).astype(int), 0, self.grid.n - 1)
            off = np.abs(self.H[ii, jj].astype(np.float64) - e)
            k = int(np.argmax(off))
            self.assertLess(float(off[k]), 2.5, "%s's ground at (%.0f, %.0f) is %.2f m off its step"
                            % (rid, pts[k, 0], pts[k, 1], off[k]))

    def test_every_authored_pad_is_flat_and_dry_at_its_level(self):
        if not self.pads:
            self.skipTest("no authored pad")
        from worldgen import roads as RD
        for place_id, pad in self.pads.items():
            place = dict(self.things[place_id])
            if pad.get("radius_m"):
                place["pad_radius_m"] = pad["radius_m"]
            r = RD.pad_radius(place)
            x, z = (float(v) for v in place["position"][:2])
            core = self.disc(x, z, 0.65 * r)
            h = self.H[core]
            self.assertLess(float(np.abs(h - pad["level_m"]).max()), 0.3,
                            "%s's pad is %.2f..%.2f m, drawn at %.2f" % (place_id, h.min(), h.max(), pad["level_m"]))
            self.assertEqual(int(self.W[core].sum()), 0, "%s's pad is awash" % place_id)

    def test_a_pad_by_the_sea_is_above_it_to_its_edge(self):
        # the first fight stands on the Hushline's pad: nothing in its footprint may be under
        # the sea or within a metre of it
        near = [(pid, p) for pid, p in self.pads.items() if p["level_m"] < 10.0]
        if not near:
            self.skipTest("no authored pad by the sea")
        from worldgen import roads as RD
        for place_id, pad in near:
            place = dict(self.things[place_id])
            if pad.get("radius_m"):
                place["pad_radius_m"] = pad["radius_m"]
            x, z = (float(v) for v in place["position"][:2])
            foot = self.disc(x, z, RD.pad_radius(place))
            self.assertGreaterEqual(float(self.H[foot].min()), 1.0,
                                    "%s's footprint goes down to %.2f m" % (place_id, self.H[foot].min()))
            self.assertEqual(int(self.W[foot].sum()), 0, "%s's footprint is in the water" % place_id)


class ForestsGrow(unittest.TestCase):
    """A small full build (256, cells and all) of the atlas with a test wood drawn on it: the wood is
    planted and the ground beside it is only the biome's own; and nothing that fights stands by
    the roads out of the start."""

    # an oakwood in the open downs between Merrowby and Tamwick, and an equal square beside it
    WOOD = [[1300.0, 2900.0], [1700.0, 2900.0], [1700.0, 3200.0], [1300.0, 3200.0]]
    BESIDE = [[1800.0, 2900.0], [2200.0, 2900.0], [2200.0, 3200.0], [1800.0, 3200.0]]

    @classmethod
    def setUpClass(cls):
        cls.atlas = copy.deepcopy(ATLAS.load())
        cls.atlas.setdefault("forests", []).append({"id": "test_wood", "polygon": cls.WOOD, "kind": "oakwood",
                                                    "density": 1.0})
        cls.tmp = tempfile.mkdtemp(prefix="wickmere_woods_")
        path = os.path.join(cls.tmp, "atlas.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cls.atlas, f)
        cls.out = os.path.join(cls.tmp, "world")
        proc = subprocess.run([sys.executable, os.path.join(TOOLS_WORLD, "build_world.py"), "--size", "256",
                               "--atlas", path, "--out", cls.out], capture_output=True, text=True, timeout=1500)
        if proc.returncode != 0:
            raise AssertionError(proc.stdout[-2000:] + proc.stderr[-2000:])
        cls.cells = []
        for name in os.listdir(os.path.join(cls.out, "cells")):
            with open(os.path.join(cls.out, "cells", name), "r", encoding="utf-8") as f:
                cls.cells.append(json.load(f))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def oaks_in(self, poly):
        x0, x1 = min(p[0] for p in poly), max(p[0] for p in poly)
        z0, z1 = min(p[1] for p in poly), max(p[1] for p in poly)
        count = 0
        for cell in self.cells:
            for asset, rows in cell["instances"].items():
                if "/trees/" not in asset or "oak" not in asset or "giant" in asset:
                    continue
                count += sum(1 for r in rows if x0 <= r[0] <= x1 and z0 <= r[2] <= z1)
        return count / ((x1 - x0) * (z1 - z0) / 1e4)

    def test_a_drawn_wood_is_planted(self):
        inside, outside = self.oaks_in(self.WOOD), self.oaks_in(self.BESIDE)
        self.assertGreater(inside, 15.0, "the wood has %.1f oaks a hectare" % inside)
        self.assertGreater(inside, 4.0 * max(outside, 0.5), "a wood of %.1f a hectare beside %.1f" % (inside, outside))

    def test_nothing_that_fights_stands_by_the_roads_out_of_the_start(self):
        from worldgen import encounters as ENC
        start = (self.atlas.get("start") or {}).get("place")
        if not start:
            self.skipTest("the atlas has no start")
        with open(os.path.join(self.out, "roads.json"), "r", encoding="utf-8") as f:
            roads = {r["id"]: r for r in json.load(f)}
        ids = {str(s.get("id") or "core:road/%s_%s" % (s["from"].split("/")[-1], s["to"].split("/")[-1]))
               for s in self.atlas.get("roads", []) if start in (s.get("from"), s.get("to"))}
        ways = [np.asarray(roads[i]["points"])[:, :2] for i in ids if i in roads]
        self.assertTrue(ways, "no road out of the start was built")
        at = np.array([[sp["pos"][0], sp["pos"][2]] for cell in self.cells for sp in cell.get("spawns", [])
                       if sp.get("kind") == "enemy"], dtype=np.float64)
        self.assertGreater(at.shape[0], 100, "the build placed almost nothing to fight")
        d = ENC.distance_to_paths(at[:, 0], at[:, 1], ways)
        self.assertGreaterEqual(float(d.min()), ENC.START_WAY_CLEAR_M,
                                "something stands %.1f m from a road out of the start" % d.min())


if __name__ == "__main__":
    unittest.main()
