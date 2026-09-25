#!/usr/bin/env python3
"""The land steps at every waterfall (worldgen.falls): the pad is level at the foot in front of the
face and at the top behind it, and a river through it falls there.

The batch 3 shots had every waterfall POI as a face of rock standing up out of level ground with
the sky behind it, towers of blocks, and the river ran level across the pad with no drop to fall.

    python3 -m pytest tools/world/tests/test_falls.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import falls as FA  # noqa: E402
from worldgen import hydro as HY  # noqa: E402
from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402

BIG = [[-2000.0, -2000.0], [2000.0, -2000.0], [2000.0, 2000.0], [-2000.0, 2000.0]]


def _land(grid: Grid) -> np.ndarray:
    """A dale falling east at 1 in 16, its floor along z = 0 and its sides rising 1 in 5."""
    X, Z = grid.mesh(np.float64)
    return (100.0 - X / 16.0 + 0.2 * np.abs(Z)).astype(np.float32)


class RiverFall(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.grid = g = Grid(1024.0, 512)                   # 2 m texels, as a full build
        cls.H0 = _land(g)
        cls.atlas = {"coast": {"polygon": BIG},
                     "rivers": [{"id": "test:river/beck", "path": [[-480.0, 0.0], [480.0, 0.0]], "width_m": [6, 8]}]}
        cls.poi = {"id": "core:poi/test_force", "kind": "waterfall", "position": [0.0, 4.0],
                   "unique_feature": "the beck dropping in a single white sheet"}
        cls.steps = FA.plan(g, cls.H0, cls.atlas, [cls.poi])
        cls.step = cls.steps[cls.poi["id"]]
        cls.H, _mask, cls.levels = RD.apply_pads(g, cls.H0.copy(), [cls.poi], steps=cls.steps)

    def h(self, x, z) -> float:
        return float(sample_bilinear(self.H, self.grid, np.array([x]), np.array([z]))[0])

    def test_it_faces_downstream_on_its_river(self):
        self.assertEqual(self.step.river, "test:river/beck")
        self.assertEqual(self.step.form, "single")
        self.assertAlmostEqual(self.step.fx, 1.0, places=3)
        self.assertAlmostEqual(self.step.facing_deg, 90.0, places=1)

    def test_the_pad_is_level_at_the_foot_in_front_and_at_the_top_behind(self):
        s = self.step
        self.assertAlmostEqual(s.top - s.foot, 11.0, places=3)
        self.assertAlmostEqual(self.levels[self.poi["id"]], s.foot, places=3)
        # the foot, from the face's line forward over the level core
        for x in (-5.0, 0.0, 6.0, 12.0):
            self.assertAlmostEqual(self.h(x, 4.0), s.foot, delta=0.05, msg="at x %.0f" % x)
        # the top, behind it
        for x in (-10.0, -13.0):
            self.assertAlmostEqual(self.h(x, 4.0), s.top, delta=0.05, msg="at x %.0f" % x)
        # and nothing like a ramp: the whole drop within STEP_RUN_M and a texel
        run = [x for x in np.arange(-12.0, -4.0, 0.25) if s.foot + 0.5 < self.h(x, 4.0) < s.top - 0.5]
        self.assertLessEqual(max(run) - min(run), FA.STEP_RUN_M + self.grid.spacing)

    def test_the_top_is_no_higher_than_the_river_comes_from(self):
        # the dale falls 1 in 16: the land 8 m behind the face is the top, and higher land upstream
        # does not raise it
        behind = float(sample_bilinear(self.H0, self.grid, np.array([-14.0]), np.array([4.0]))[0])
        self.assertLessEqual(self.step.top, behind + 0.5)

    def test_the_river_falls_at_the_face(self):
        rivers = HY.atlas_rivers(self.grid, self.H, self.atlas, None, avoid=[(0.0, 4.0)], pins=self.step.pins())
        falls = rivers[0].falls
        at = [f for f in falls if abs(f["top"][0] + 7.0) < 8.0]
        self.assertEqual(len(at), 1, falls)
        f = at[0]
        self.assertGreater(f["height_m"], 9.5)
        self.assertEqual(f["kind"], "fall")
        self.assertAlmostEqual(f["facing_deg"], 90.0, delta=15.0)


class RiverThroughAHollow(unittest.TestCase):
    def test_the_top_is_no_higher_than_the_lowest_land_the_river_crosses_above_it(self):
        # the river crosses a hollow 300 m above the fall, 12 m under the land there: its surface
        # is held at the hollow's level from there on, so a step with its top at the land's
        # level stood the river under the lip, and the carve cut the step away
        g = Grid(1024.0, 512)
        X, Z = g.mesh(np.float64)
        H0 = _land(g) - 18.0 * np.exp(-(((X + 300.0) / 40.0) ** 2)) * np.ones_like(Z)
        H0 = H0.astype(np.float32)
        atlas = {"coast": {"polygon": BIG},
                 "rivers": [{"id": "test:river/beck", "path": [[-480.0, 0.0], [480.0, 0.0]], "width_m": [6, 8]}]}
        poi = {"id": "core:poi/test_force", "kind": "waterfall", "position": [0.0, 4.0],
               "unique_feature": "a single white sheet"}
        step = FA.plan(g, H0, atlas, [poi])[poi["id"]]
        hollow = float(np.min(sample_bilinear(H0, g, np.linspace(-360, -240, 61), np.zeros(61))))
        self.assertLessEqual(step.top, hollow + 1e-3)
        self.assertAlmostEqual(step.top - step.foot, 11.0, places=3)
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi], steps={poi["id"]: step})
        rivers = HY.atlas_rivers(g, H, atlas, None, avoid=[(0.0, 4.0)], pins=step.pins())
        at = [f for f in rivers[0].falls if abs(f["top"][0] + 7.0) < 8.0]
        self.assertEqual(len(at), 1, rivers[0].falls)
        self.assertGreater(at[0]["height_m"], 9.5)


class OffTheRivers(unittest.TestCase):
    def test_a_fall_off_the_rivers_faces_down_its_slope_and_stands_its_three_tiers(self):
        g = Grid(1024.0, 512)
        H0 = _land(g)
        poi = {"id": "core:poi/test_sisters", "kind": "waterfall", "position": [0.0, 200.0],
               "unique_feature": "three terraced falls with a stone on the middle ledge"}
        steps = FA.plan(g, H0, {"coast": {"polygon": BIG}, "rivers": []}, [poi])
        s = steps[poi["id"]]
        self.assertEqual(s.river, "")
        self.assertEqual(s.form, "terraced")
        # the dale side falls toward z = 0 (-z) and a little east
        want = math.degrees(math.atan2(1.0 / 16.0, -0.2)) % 360.0
        self.assertAlmostEqual(s.facing_deg, want, delta=3.0)
        self.assertAlmostEqual(s.top - s.foot, 13.8, places=3)
        H, _m, levels = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        # each tier's ledge level behind its face: 4.6 m a tier
        for k, behind in enumerate((5.5, 11.5, 17.0)):
            x, z = -s.fx * behind, 200.0 - s.fz * behind
            got = float(sample_bilinear(H, g, np.array([x]), np.array([z]))[0])
            self.assertAlmostEqual(got, s.foot + 4.6 * (k + 1), delta=0.3, msg="tier %d" % k)

    def test_a_staged_build_reads_the_steps_back(self):
        s = FA.Step(id="core:poi/x", form="glass", x=10.0, z=-20.0, fx=0.6, fz=0.8, foot=40.0,
                    faces=[(7.0, 13.0)], river="")
        entry = {"place_id": "core:poi/x", "pos": [10.0, 40.0, -20.0], "fall": s.entry()}
        back = FA.from_entries([entry])["core:poi/x"]
        xs, zs = np.array([10.0, 0.0, -5.0]), np.array([-20.0, -30.0, -35.0])
        np.testing.assert_allclose(back.rise(xs, zs), s.rise(xs, zs), atol=1e-3)
        self.assertAlmostEqual(back.top, 53.0)

    def test_the_forms_are_the_dressing_s(self):
        self.assertEqual(FA.form_of("three falls stepping down the granite stair"), "terraced")
        self.assertEqual(FA.form_of("a dry waterfall of black glass, climbable"), "glass")
        self.assertEqual(FA.form_of("the Wold Water dropping in a single rope of white"), "single")


if __name__ == "__main__":
    unittest.main()


def falls_missing(pois: list, rivers: list) -> list:
    """For every waterfall POI whose `fall` names a river: each face must be a fall in rivers.json on
    that river, its top at the face's lip (within LIP_M across the ground and 1 m in height), its
    foot at the face's foot, facing the step's way. Returns what is not."""
    import math as _m
    from worldgen import falls as _FA

    LIP_M = 8.0
    by_id = {r["id"]: r for r in rivers}
    bad = []
    for e in pois:
        f = e.get("fall")
        if not f or not f.get("river"):
            continue
        r = by_id.get(f["river"])
        if r is None:
            bad.append("%s: no river %s" % (e["place_id"], f["river"]))
            continue
        a = _m.radians(f["facing_deg"])
        fx, fz = _m.sin(a), _m.cos(a)
        x, _, z = e["pos"]
        level = f["foot_m"]
        for face in f["faces"]:
            lip = (x - fx * (face["behind_m"] + _FA.STEP_RUN_M), z - fz * (face["behind_m"] + _FA.STEP_RUN_M))
            top_y, foot_y = level + face["drop_m"], level
            level = top_y
            ok = False
            for fl in r.get("falls", []):
                tx, ty, tz = fl["top"]
                near = _m.hypot(tx - lip[0], tz - lip[1]) <= LIP_M + 10.5    # (the river may run 10 m off)
                d_face = abs(((fl["facing_deg"] - f["facing_deg"] + 180.0) % 360.0) - 180.0)
                if near and ty >= top_y - 1.0 - 0.4 and fl["foot"][1] <= foot_y + 1.0 and d_face < 35.0:
                    ok = True
            if not ok:
                bad.append("%s: no fall on %s at the lip of its face %.0f m back (top %.1f, foot %.1f)"
                           % (e["place_id"], f["river"], face["behind_m"], top_y, foot_y))
    return bad


class CoarseTexels(unittest.TestCase):
    """At 8 m texels (a 1024 preview) the step is smeared over two texels, and the river read off the
    land ramped down it under FALL_DROP_GRADE: no fall in rivers.json (the Kharrow Force on b4)."""

    def test_a_river_10_m_off_the_centre_on_a_steep_dale_still_falls_at_the_face(self):
        g = Grid(2048.0, 256)
        X, Z = g.mesh(np.float64)
        H0 = (500.0 - X / 5.0 + 0.3 * np.abs(Z - 10.0)).astype(np.float32)   # the Kharrow's fall line
        atlas = {"coast": {"polygon": BIG},
                 "rivers": [{"id": "test:river/water", "path": [[-900.0, 10.0], [900.0, 10.0]], "width_m": [6, 9]}]}
        poi = {"id": "core:poi/test_force", "kind": "waterfall", "position": [0.0, 0.0],
               "unique_feature": "leaping in one fall"}
        steps = FA.plan(g, H0, atlas, [poi])
        st = steps[poi["id"]]
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        rivers = HY.atlas_rivers(g, H, atlas, None, avoid=[(0.0, 0.0)], pins=st.pins(), steps=[st])
        entry = {"place_id": poi["id"], "pos": [0.0, st.foot, 0.0], "fall": st.entry()}
        rv = [{"id": r.id, "falls": r.falls} for r in rivers]
        self.assertEqual(falls_missing([entry], rv), [])

    def test_three_tiers_are_three_falls(self):
        g = Grid(2048.0, 256)
        X, Z = g.mesh(np.float64)
        H0 = (300.0 - X / 6.0 + 0.3 * np.abs(Z)).astype(np.float32)
        atlas = {"coast": {"polygon": BIG},
                 "rivers": [{"id": "test:river/beck", "path": [[-900.0, 3.0], [900.0, 3.0]], "width_m": [5, 7]}]}
        poi = {"id": "core:poi/test_sisters", "kind": "waterfall", "position": [0.0, 0.0],
               "unique_feature": "three terraced falls"}
        steps = FA.plan(g, H0, atlas, [poi])
        st = steps[poi["id"]]
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        rivers = HY.atlas_rivers(g, H, atlas, None, avoid=[(0.0, 0.0)], pins=st.pins(), steps=[st])
        entry = {"place_id": poi["id"], "pos": [0.0, st.foot, 0.0], "fall": st.entry()}
        self.assertEqual(falls_missing([entry], [{"id": r.id, "falls": r.falls} for r in rivers]), [])


class ShallowTiers(unittest.TestCase):
    """At 2 m texels (the 4096), terraced steps of 1.3 to 2.9 m a face, 6 m apart, were not falls in
    rivers.json: each tier's drop over the 3 m the step takes was under FALL_DROP_GRADE, and a 1.3 m
    one under FALL_MIN_HEIGHT_M (the Three Sisters' and the Blackgill's, on the second 4096)."""

    def _tiers(self, drop: float, offset: float):
        g = Grid(1024.0, 512)
        X, Z = g.mesh(np.float64)
        H0 = (190.0 - X / 40.0 + 0.25 * np.abs(Z - offset)).astype(np.float32)
        atlas = {"coast": {"polygon": BIG},
                 "rivers": [{"id": "test:river/gill", "path": [[-480.0, offset], [480.0, offset]], "width_m": [3, 5]}]}
        foot = float(sample_bilinear(H0, g, np.array([0.0]), np.array([offset]))[0])
        st = FA.Step(id="core:poi/test_gill", form="terraced", x=0.0, z=0.0, fx=1.0, fz=0.0, foot=foot,
                     faces=[(2.0, drop), (8.0, drop), (14.0, drop)], river="test:river/gill")
        steps = {st.id: st}
        poi = {"id": st.id, "kind": "waterfall", "position": [0.0, 0.0]}
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi], steps=steps)
        rivers = HY.atlas_rivers(g, H, atlas, None, avoid=[(0.0, 0.0)], pins=st.pins(), steps=[st])
        entry = {"place_id": st.id, "pos": [0.0, st.foot, 0.0], "fall": st.entry()}
        return falls_missing([entry], [{"id": r.id, "falls": r.falls} for r in rivers]), rivers[0].falls

    def test_three_tiers_of_1_3_m_are_three_falls(self):
        missing, falls = self._tiers(1.3, 6.3)
        self.assertEqual(missing, [])
        near = [f for f in falls if abs(f["top"][0]) < 25.0]
        self.assertEqual(len(near), 3, near)
        self.assertTrue(all(f["kind"] == "fall" for f in near))

    def test_three_tiers_of_2_9_m_are_three_falls(self):
        missing, falls = self._tiers(2.88, 3.6)
        self.assertEqual(missing, [])
        self.assertEqual(len([f for f in falls if abs(f["top"][0]) < 25.0]), 3)


class BuiltWorld(unittest.TestCase):
    """Every stepped fall on a river is a fall in rivers.json, on the world that was built
    (WICKMERE_GENERATED, default game/world/generated; skipped where it has no `fall` yet)."""

    def test_every_stepped_fall_is_a_river_fall(self):
        import json as _json
        gen = os.environ.get("WICKMERE_GENERATED",
                             os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "game", "world", "generated"))
        path = os.path.join(gen, "pois.json")
        if not os.path.exists(path):
            raise unittest.SkipTest("no built world at %s" % gen)
        pois = _json.load(open(path))
        if not any(e.get("fall") for e in pois):
            raise unittest.SkipTest("a world built before the falls' steps")
        rivers = _json.load(open(os.path.join(gen, "rivers.json")))
        self.assertEqual(falls_missing(pois, rivers), [])
