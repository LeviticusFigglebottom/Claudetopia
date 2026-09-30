#!/usr/bin/env python3
"""A pad's shape (worldgen.roads.pad_shape), and a standing stone set down by its stub.

    python3 -m pytest tools/world/tests/test_pad_shapes.py

Brightwater found the Hush Hole reading as a mound with a door and Cadbrae's slate cut as a raised
disc: the level pad took away the slope a cave's bank and a quarry's benches need. A cave's, a
quarry's and a cave-mouthed delve's pad now keep the land's slope; the Kilnway's lava mouth has its
trench sunk into its pad, which the game cannot dig at runtime. And the forge's standing stones run
0.6 m under their ground line (`buried_m`), which the world's seating now sets them down by.
"""
from __future__ import annotations

import json
import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import cells as CELLS  # noqa: E402
from worldgen import falls as FA  # noqa: E402
from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402

KILNWAY_TRENCH = {"bearing_deg": 213, "length_m": 10, "ramp_m": 8, "width_m": 5, "depth_m": 2.3, "side_m": 2.5,
                  "behind_m": 18, "head_width_m": 20, "head_from_m": -4}


def slope_land(g: Grid, grade: float = 0.3) -> np.ndarray:
    X, Z = g.mesh()
    return np.broadcast_to(100.0 + grade * Z, (g.n, g.n)).astype(np.float32).copy()


class PadShapeTest(unittest.TestCase):

    def test_the_shape_by_kind_and_by_def(self):
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "cave"}), "slope")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "quarry"}), "slope")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "delve"}), "slope")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "delve", "mouth": "lava"}), "level")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "ruins"}), "level")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "ruins", "pad_shape": "slope"}), "slope")
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "cave", "pad_shape": "level"}), "level")
        # a trench without its numbers is a level pad; a settlement is always level
        self.assertEqual(RD.pad_shape({"id": "core:poi/a", "kind": "delve", "pad_shape": "trench"}), "level")
        self.assertEqual(RD.pad_shape({"id": "core:place/a", "kind": "village"}), "level")

    def test_the_build_carries_the_shape_from_the_def(self):
        import build_world as BW
        pads = {p["id"]: p for p in BW.pad_targets_for([], BW.load_poi_registry(BW.PACK))}
        kiln = pads["core:poi/the_kilnway"]
        self.assertEqual(RD.pad_shape(kiln), "trench")
        self.assertEqual(kiln["mouth"], "lava")
        self.assertEqual(RD.pad_radius(kiln), 34.0)
        for pid in ("core:poi/the_hush_hole", "core:poi/cadbrae_slate_cut"):
            self.assertEqual(RD.pad_shape(pads[pid]), "slope", pid)
        # the trench lies inside the level core, where the pad is laid whole
        g = Grid(256.0, 256)
        X, Z = g.mesh()
        sunk = RD.trench_depth(kiln["trench"], X[:, :] + 0.0 * Z, Z + 0.0 * X)
        d = np.hypot(X + 0.0 * Z, Z + 0.0 * X)
        self.assertLessEqual(float(d[sunk > 0.0].max()), RD.pad_level_radius(kiln) + 1.0)

    def test_a_sloped_pad_keeps_the_slope_and_a_level_one_does_not(self):
        g = Grid(512.0, 256)
        H0 = slope_land(g, 0.3)
        quarry = {"id": "core:poi/q", "kind": "quarry", "position": [0.0, 0.0]}
        ruin = {"id": "core:poi/r", "kind": "ruins", "position": [0.0, 0.0]}
        for poi, want in ((quarry, 0.3), (ruin, RD.PAD_TILT_MAX)):
            H, _m, levels = RD.apply_pads(g, H0.copy(), [poi])
            hz = sample_bilinear(H, g, np.array([0.0, 0.0]), np.array([-10.0, 10.0]))
            grade = float(hz[1] - hz[0]) / 20.0
            self.assertAlmostEqual(grade, want, delta=0.02, msg=poi["kind"])
        # laid again it stays the same (the build lays its pads three times)
        H1, _m, _l = RD.apply_pads(g, H0.copy(), [quarry])
        H2, _m, _l = RD.apply_pads(g, H1.copy(), [quarry])
        X, Z = g.mesh()
        core = np.hypot(X, Z) <= RD.pad_level_radius(quarry)
        self.assertLess(float(np.abs(H2 - H1)[core].max()), 0.05)

    def test_a_sloped_pad_keeps_a_bank_and_softens_a_bump(self):
        """A quarry cut at the foot of a bank keeps the bank; a knob on its floor is softened."""
        g = Grid(512.0, 256)
        X, Z = g.mesh()
        X, Z = X + 0.0 * Z, Z + 0.0 * X
        H0 = (100.0 + 12.0 * np.clip((X - 8.0) / 10.0, 0.0, 1.0)            # a bank from x 8 to 18
              + 1.5 * np.exp(-((X + 8.0) ** 2 + Z ** 2) / 8.0)).astype(np.float32)   # a knob at x -8
        poi = {"id": "core:poi/q", "kind": "quarry", "position": [0.0, 0.0]}
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi])
        at = lambda x: float(sample_bilinear(H, g, np.array([x]), np.array([0.0]))[0])
        self.assertGreater(at(16.0) - at(2.0), 8.0)          # the bank is still there, inside the core
        self.assertLess(at(-8.0) - 100.0, 0.9)               # the knob is not
        Hl, _m, _l = RD.apply_pads(g, H0.copy(), [dict(poi, pad_shape="level")])
        self.assertLess(float(sample_bilinear(Hl, g, np.array([16.0]), np.array([0.0]))[0]) - 100.0, 3.0)

    def test_a_cave_in_a_bank_keeps_the_bank(self):
        """A cave's rise over a sloped pad: the slope in front of the mouth, the face at the mouth,
        and the land's own slope going on up behind it, never a knoll standing off it."""
        g = Grid(512.0, 256)
        H0 = slope_land(g, 0.35)          # rising to the south (+z)
        poi = {"id": "core:poi/cave", "kind": "cave", "position": [0.0, 0.0]}
        steps = FA.caves(g, H0, [poi], {}, {poi["id"]: RD.pad_level_radius(poi)})
        st = steps[poi["id"]]
        self.assertLess(st.fz, -0.9)                       # faces down the slope, north
        H, _m, levels = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        front = float(sample_bilinear(H, g, np.array([0.0]), np.array([-8.0]))[0])
        self.assertAlmostEqual(front, 100.0 - 8.0 * 0.35, delta=0.6)
        # behind the mouth: at least the face over the foot, and the slope carrying on up from there
        z = np.array([6.0, 12.0, 17.0])
        behind = sample_bilinear(H, g, np.zeros(3), z)
        self.assertTrue(np.all(behind >= st.foot + FA.CAVE_FACE_M - 0.3), behind)
        self.assertTrue(np.all(np.diff(behind) >= -0.05), behind)
        # and it is the slope's own line where that stands higher than the face, never raised over it
        line = 100.0 + 0.35 * z
        self.assertTrue(np.all(behind - line <= FA.CAVE_FACE_M + 0.5), behind - line)
        self.assertTrue(np.all(behind >= line - 0.3), behind - line)

    def test_the_trench_is_sunk_into_the_pad(self):
        g = Grid(512.0, 512)
        X, Z = g.mesh()
        H0 = np.full((g.n, g.n), 60.0, dtype=np.float32)
        poi = {"id": "core:poi/kilnway", "kind": "delve", "position": [0.0, 0.0], "pad_radius_m": 34,
               "pad_shape": "trench", "trench": KILNWAY_TRENCH, "mouth": "lava"}
        H, _m, levels = RD.apply_pads(g, H0.copy(), [poi])
        H, _m, levels = RD.apply_pads(g, H, [poi])            # laid again: the same trench, no deeper
        self.assertAlmostEqual(levels[poi["id"]], 60.0, delta=0.3)
        b = math.radians(213.0)
        fx, fz = math.sin(b), math.cos(b)

        def at(u, v):
            return float(sample_bilinear(H, g, np.array([u * fx - v * fz]), np.array([u * fz + v * fx]))[0])

        # the floor from the throat's head out to the ramp, the ramp up to the heath, the heath beside
        for u in (-15.0, -4.0, 0.0, 2.0):
            self.assertAlmostEqual(at(u, 0.0), levels[poi["id"]] - 2.3, delta=0.25, msg=u)
        self.assertGreater(at(6.0, 0.0), levels[poi["id"]] - 2.0)
        self.assertAlmostEqual(at(11.0, 0.0), levels[poi["id"]], delta=0.3)
        self.assertAlmostEqual(at(0.0, 7.0), levels[poi["id"]], delta=0.3)
        # the head behind the mouth is wide: 10 m out to the side, still the floor
        self.assertAlmostEqual(at(-12.0, 9.5), levels[poi["id"]] - 2.3, delta=0.3)
        self.assertAlmostEqual(at(-12.0, 13.5), levels[poi["id"]], delta=0.3)

    def test_the_kilnway_def_matches_its_mouth(self):
        """The def's trench is the lava mouth's own (site_exterior.gd: the mouth 4 m in, the trench's
        floor 2.5 m either side of its line, its ramp from 2 m out to 10), dug RISE deep."""
        rows = json.load(open(os.path.join(REPO, "game", "content", "packs", "core", "pois", "_interiors_showcase.json")))
        kiln = [r for r in rows if r["id"] == "core:poi/the_kilnway"][0]
        self.assertEqual(kiln["pad_shape"], "trench")
        t = kiln["trench"]
        src = open(os.path.join(REPO, "game", "world", "sites", "site_exterior.gd")).read()
        rise = float(src.split("const RISE := ")[1].split()[0])
        tube_w = float(src.split("const TUBE_W := ")[1].split()[0])
        self.assertAlmostEqual(t["depth_m"], rise)
        self.assertAlmostEqual(t["width_m"] / 2.0, tube_w - 0.5)
        self.assertEqual(t["head_from_m"], -4)


class BuriedStubTest(unittest.TestCase):

    def test_standing_stones_are_set_down_by_their_stub(self):
        from worldgen import stones as ST
        index = CELLS.asset_index(REPO)
        stones = [p for n, p in sorted(index.get("rocks", {}).items()) if "_standing_stone_" in n]
        if not stones:
            self.skipTest("no standing stones built")
        for path in stones:
            self.assertGreater(CELLS.asset_buried(path, REPO), 0.5, path)
        self.assertEqual(CELLS.asset_buried("res://assets/models/rocks/nothing/nothing.glb", REPO), 0.0)
        g = Grid(256.0, 128)
        H = np.full((g.n, g.n), 10.0, dtype=np.float32)
        out: dict = {}
        ST._put(out, g, H, 3.0, 4.0, 0.0, 1.2, stones[0], "#ffffff")
        row = list(list(out.values())[0].values())[0][0]
        self.assertAlmostEqual(row[1], 10.0 - 1.2 * CELLS.asset_buried(stones[0], REPO), delta=0.01)


if __name__ == "__main__":
    unittest.main()
