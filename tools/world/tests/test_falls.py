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

    def test_a_staged_build_reads_the_face_line_back(self):
        s = FA.Step(id="core:poi/x", form="single", x=10.0, z=-20.0, fx=0.6, fz=0.8, foot=40.0,
                    faces=[(6.0, 11.0)], river="", line=FA.face_line("single", "core:poi/x", 17.5))
        entry = {"place_id": "core:poi/x", "pos": [10.0, 40.0, -20.0], "fall": s.entry()}
        back = FA.from_entries([entry])["core:poi/x"]
        X, Z = np.meshgrid(np.linspace(-40.0, 60.0, 41), np.linspace(-70.0, 30.0, 41))
        # (the facing comes back to a tenth of a degree: 4 cm at 50 m, on a face 3.7 m of rise a metre)
        np.testing.assert_allclose(back.rise(X, Z), s.rise(X, Z), atol=0.3)

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


def caves_without_a_face(pois: list, H, grid) -> list:
    """For every cave POI's `cave`: the ground must rise at least 4 m over the mouth's floor within
    6 m behind its mouth, on the facing's line. Returns what does not."""
    import math as _m

    bad = []
    for e in pois:
        c = e.get("cave")
        if not c:
            continue
        a = _m.radians(c["facing_deg"])
        fx, fz = _m.sin(a), _m.cos(a)
        x, _, z = e["pos"]
        b = c["mouth_behind_m"]
        us = np.linspace(b, b + 6.0, 13)
        h = sample_bilinear(H, grid, x - fx * us, z - fz * us)
        if float(h.max()) - float(c["mouth_m"]) < 4.0:
            bad.append("%s: rises %.1f m in the 6 m behind its mouth" % (e["place_id"], float(h.max()) - c["mouth_m"]))
    return bad


class FaceLine(unittest.TestCase):
    """A fall's face is not a straight wall across its pad: it bows with the dressing's face, and past
    it its wings swing forward round the pool, wandering, and lower toward their ends (the w4096c
    Glass, Hanging and Skarl falls read as straight walls)."""

    def test_the_middle_is_the_dressing_s_bow_and_the_wings_swing_round_the_level_ground(self):
        for form, (behind, _d) in (("single", FA.FORMS["single"][0]), ("glass", FA.FORMS["glass"][0]),
                                   ("terraced", FA.FORMS["terraced"][0])):
            level_r = 17.5
            line = FA.face_line(form, "core:poi/test_" + form, level_r)
            v, fw, keep = (np.array(c) for c in zip(*line))
            self.assertEqual(float(np.interp(0.0, v, fw)), 0.0)
            # the dressing's own bow (poi_builders._rock_face): its outer column 2 modules across
            width = FA.DRESS_WIDTH_M[form]
            cols = max(int(math.ceil(width / FA.DRESS_MODULE_M)), 3)
            cols += 1 if cols % 2 == 0 else 0
            n = int(cols / 2)
            t = n / cols
            self.assertAlmostEqual(float(np.interp(n * FA.DRESS_MODULE_M, v, fw)), 4.0 * 0.18 * width * t * t, delta=0.3)
            self.assertTrue(np.all(keep[np.abs(v) <= level_r] == 1.0), form)
            b0 = behind
            # the wings: well forward, and lower, at the ends; and the face in front of the centre
            # never inside the level ground's radius
            for side in (-1.0, 1.0):
                self.assertGreater(float(np.interp(side * 36.0, v, fw)), b0 + 5.0, (form, side))
                self.assertLess(float(np.interp(side * 44.0, v, keep)), 0.85, (form, side))
            u = fw - behind
            front = u > 0.0
            self.assertTrue(np.all(np.hypot(v[front], u[front]) >= level_r - 0.5), form)
            # and each fall's wings are its own: not a mirror image, nor another fall's
            self.assertGreater(float(np.abs(fw - fw[::-1]).max()), 1.0)
        other = FA.face_line("single", "core:poi/another", 17.5)
        self.assertGreater(max(abs(a[1] - b[1]) for a, b in zip(FA.face_line("single", "core:poi/test_single", 17.5), other)), 1.0)

    def test_the_land_follows_the_line(self):
        g = Grid(512.0, 256)
        H0 = np.full((g.n, g.n), 100.0, dtype=np.float32)
        poi = {"id": "core:poi/test_line", "kind": "waterfall", "position": [0.0, 0.0]}
        st = FA.Step(id=poi["id"], form="single", x=0.0, z=0.0, fx=0.0, fz=1.0, foot=100.0, faces=[(6.0, 11.0)],
                     line=FA.face_line("single", poi["id"], RD.pad_level_radius(poi)))
        H, _m, _l = RD.apply_pads(g, H0.copy(), [poi], steps={poi["id"]: st})
        # across the facing (+z) is -x here: v = -x
        for v in (0.0, 10.0, -10.0, 22.0, -22.0):
            fw, keep = st.forward(np.array([v]))
            u_face = float(fw[0]) - 6.0
            ahead = float(sample_bilinear(H, g, np.array([-v]), np.array([u_face + 2.0]))[0])
            behind = float(sample_bilinear(H, g, np.array([-v]), np.array([u_face - 5.0]))[0])
            self.assertLess(ahead, 100.6, v)
            self.assertGreater(behind - ahead, 0.6 * 11.0 * float(keep[0]), v)

class Caves(unittest.TestCase):
    """A cave has a hillside to be a cave in: a knoll raised behind its mouth on level ground, a shelf
    cut into ground that rises (the w4096c Kharrow Hole: a black box on flat ground)."""

    def _cave(self, H0, fixed=None, pad_radius=None):
        g = Grid(1024.0, 512)
        poi = {"id": "core:poi/test_hole", "kind": "cave", "position": [10.0, 20.0]}
        if pad_radius:
            poi["pad_radius_m"] = pad_radius
        steps = FA.caves(g, H0, [poi], fixed, {poi["id"]: RD.pad_level_radius(poi)})
        st = steps[poi["id"]]
        H, _m, levels = RD.apply_pads(g, H0.copy(), [poi], fixed_levels=fixed, steps=steps)
        entry = {"place_id": poi["id"], "pos": [10.0, levels[poi["id"]], 20.0], "cave": st.cave_entry()}
        return g, st, H, entry

    def test_on_level_ground_a_knoll_rises_behind_the_mouth(self):
        g = Grid(1024.0, 512)
        H0 = np.full((g.n, g.n), 50.0, dtype=np.float32)
        g, st, H, entry = self._cave(H0)
        self.assertEqual(caves_without_a_face([entry], H, g), [])
        self.assertIsNotNone(entry["cave"]["face_half_width_m"])
        # a knoll, not a scarp across the pad: back at the ground 20 m aside of the facing's line
        px, pz = -st.fz, st.fx
        side = float(sample_bilinear(H, g, np.array([10.0 - st.fx * 10.0 + px * 20.0]),
                                     np.array([20.0 - st.fz * 10.0 + pz * 20.0]))[0])
        self.assertLess(side, 50.5)
        self.assertAlmostEqual(entry["cave"]["mouth_m"], 50.0, places=2)

    def test_on_a_slope_the_pad_is_a_shelf_cut_into_it_facing_downhill(self):
        g = Grid(1024.0, 512)
        X, Z = g.mesh(np.float64)
        H0 = (100.0 - 0.8 * (Z - 20.0) + 0.0 * X).astype(np.float32)       # rising to -z
        g, st, H, entry = self._cave(H0)
        self.assertEqual(caves_without_a_face([entry], H, g), [])
        self.assertIsNone(entry["cave"]["face_half_width_m"])
        self.assertLess(abs(((entry["cave"]["facing_deg"] + 180.0) % 360.0) - 180.0), 16.0)   # it looks out along +z
        self.assertGreater(entry["cave"]["face_top_m"] - entry["cave"]["mouth_m"], FA.CAVE_FACE_M)

    def test_a_pad_the_atlas_fixes_keeps_its_level(self):
        g = Grid(1024.0, 512)
        X, Z = g.mesh(np.float64)
        H0 = np.where(Z < 0.0, 60.0, 4.0 + 0.0 * X).astype(np.float32)          # a cliff behind a shelf
        g, st, H, entry = self._cave(H0, {"core:poi/test_hole": 4.0})
        self.assertAlmostEqual(entry["cave"]["mouth_m"], 4.0, places=3)
        self.assertEqual(caves_without_a_face([entry], H, g), [])

    def test_an_authored_landing_is_level_to_its_radius_and_the_mouth_is_at_its_edge(self):
        """The Hushline's sea-cave: the atlas draws an 18 m landing at 4 m under a 117 m cliff. Cut
        three metres in, its shelf stood the cliff's height on the landing."""
        g = Grid(1024.0, 512)
        X, Z = g.mesh(np.float64)
        H0 = np.where(Z < 5.0, 120.0, 4.0 + 0.0 * X).astype(np.float32)     # the cliff 15 m behind
        g, st, H, entry = self._cave(H0, {"core:poi/test_hole": 4.0}, pad_radius=18.0)
        level_r = RD.PAD_LEVEL * 18.0
        self.assertAlmostEqual(entry["cave"]["mouth_behind_m"], level_r, places=3)
        self.assertEqual(caves_without_a_face([entry], H, g), [])
        ii, jj = np.nonzero((X - 10.0) ** 2 + (Z - 20.0) ** 2 <= (0.65 * 18.0) ** 2)
        self.assertLess(float(np.abs(H[ii, jj] - 4.0).max()), 0.3)

    def test_a_staged_build_reads_the_cave_back(self):
        st = FA.Step(id="core:poi/x", form="cave", x=5.0, z=-3.0, fx=0.0, fz=1.0, foot=20.0,
                     faces=[(3.0, 6.0)], half_width=8.0, taper=10.0)
        back = FA.from_entries([{"place_id": "core:poi/x", "pos": [5.0, 20.0, -3.0], "cave": st.cave_entry()}])["core:poi/x"]
        xs, zs = np.array([5.0, 12.0, 30.0]), np.array([-12.0, -12.0, -12.0])
        np.testing.assert_allclose(back.rise(xs, zs), st.rise(xs, zs), atol=1e-3)


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

    def test_every_cave_has_a_face_behind_its_mouth(self):
        import json as _json
        gen = os.environ.get("WICKMERE_GENERATED",
                             os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "game", "world", "generated"))
        if not os.path.exists(os.path.join(gen, "heights.r32")):
            raise unittest.SkipTest("no full-resolution heights at %s" % gen)
        pois = _json.load(open(os.path.join(gen, "pois.json")))
        if not any(e.get("cave") for e in pois):
            raise unittest.SkipTest("a world built before the caves' faces")
        m = _json.load(open(os.path.join(gen, "world_manifest.json")))
        n = int(m["grid"])
        g = Grid(float(m["size_m"]), n)
        H = np.fromfile(os.path.join(gen, "heights.r32"), dtype="<f4").reshape(n, n)
        self.assertEqual(caves_without_a_face(pois, H, g), [])
