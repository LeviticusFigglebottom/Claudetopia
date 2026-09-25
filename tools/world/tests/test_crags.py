#!/usr/bin/env python3
"""Crags (worldgen.crags): rock set into the steep faces, oriented to them and embedded, and
outcrops on the crests; none on a road, a pad or water, or standing into a sightline.

    python3 -m pytest tools/world/tests/test_crags.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import crags as CR  # noqa: E402
from worldgen.grid import Grid, sample_bilinear  # noqa: E402
from worldgen.noise import NoiseBank  # noqa: E402

K = {"EYE_M": 1.65, "LANDMARK_DEFAULT_M": 6.0, "LANDMARK_M": {}, "CLEARANCE_M": 2.0, "MAX_SIGHT_M": 4200.0,
     "FOREGROUND_M": 140.0}
SLAB = "res://assets/models/rocks/skerrow_cliff_slab_a/skerrow_cliff_slab_a.glb"
BOULDER = "res://assets/models/rocks/skerrow_boulder_a/skerrow_boulder_a.glb"


class Crags(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # a valley running along z: flat floor, walls climbing 1 in 1 either side from |x| = 120 to
        # 220 m, and a level top with a crest beyond
        cls.grid = g = Grid(1024.0, 256)
        X, Z = g.mesh()
        X = np.broadcast_to(X, (g.n, g.n)).astype(np.float64)
        ax = np.abs(X)
        H = np.where(ax < 120.0, 100.0, np.where(ax < 220.0, 100.0 + (ax - 120.0), 200.0))
        H = H + 12.0 * np.exp(-((ax - 330.0) / 25.0) ** 2)          # a crest
        cls.H = H.astype(np.float32)
        n = g.n
        cls.owner = np.zeros((n, n), dtype=np.uint8)
        cls.water = np.zeros((n, n), dtype=np.uint8)
        cls.water_d = np.full((n, n), 1e6, dtype=np.float32)
        # a road across the east wall at z = 0
        Zb = np.broadcast_to(Z, (n, n))
        cls.road_d = np.where(X > 0, np.abs(Zb), 1e6).astype(np.float32)
        cls.road_w = np.full((n, n), 4.0, dtype=np.float32)
        cls.pad = np.zeros((n, n), dtype=bool)
        cls.regions = [SimpleNamespace(index=0, shape="mountains", art_short="skerrow")]
        cls.index = {"rocks": {"skerrow_cliff_slab_a": SLAB, "skerrow_boulder_a": BOULDER}}
        # a sightline across the west wall at z = -250, from the valley floor to the brow above it:
        # 25 m over the middle of the wall
        cls.claims = [((0.0, -250.0), (-240.0, -250.0), "ruins", 20.0, 20.0)]
        rows, cls.counts = CR.place(g, cls.H, cls.owner, cls.water, cls.water_d, cls.road_d, cls.road_w, cls.pad,
                                    cls.regions, cls.claims, K, cls.index, NoiseBank(11, g), 5, repo_root=REPO)
        cls.faces = np.array([r[:5] + [0.0] + r[6:] for by in rows.values() for r in by.get(SLAB, [])], dtype=np.float64)
        cls.crests = np.array([r[:5] + [0.0] + r[6:] for by in rows.values() for r in by.get(BOULDER, [])], dtype=np.float64)

    def ground(self, x, z):
        return sample_bilinear(self.H, self.grid, np.asarray(x), np.asarray(z)).astype(np.float64)

    def test_the_faces_are_dressed_and_the_flats_are_not(self):
        self.assertGreater(len(self.faces), 100)
        ax = np.abs(self.faces[:, 0])
        # on the walls (a piece is set back into the hill along its normal by a metre or two)
        self.assertTrue(np.all((ax > 110.0) & (ax < 230.0)), "a face piece off the walls")

    def test_a_face_piece_looks_out_downhill_and_leans_into_the_hill(self):
        east = self.faces[self.faces[:, 0] > 0]
        west = self.faces[self.faces[:, 0] < 0]
        # the east wall rises toward +x: it looks out toward -x (a yaw of -90), and leans toward +x (0)
        yaw_e = (east[:, 3] + 360.0) % 360.0
        self.assertTrue(np.all(np.abs(yaw_e - 270.0) < 1.0))
        self.assertTrue(np.all(np.abs(((east[:, 7] + 360.0) % 360.0)) < 1.0))
        yaw_w = (west[:, 3] + 360.0) % 360.0
        self.assertTrue(np.all(np.abs(yaw_w - 90.0) < 1.0))
        self.assertTrue(np.all(np.abs(((west[:, 7] + 360.0) % 360.0) - 180.0) < 1.0))
        # a 45 degree face: leaned back 0.7 of the 45 degrees from upright
        self.assertAlmostEqual(float(np.median(self.faces[:, 6])), CR.FACE_LEAN_SHARE * 45.0, delta=0.5)
        # and none leans further than a face just over 35 degrees asks (its foot and brow)
        self.assertTrue(np.all(self.faces[:, 6] <= CR.FACE_LEAN_SHARE * (90.0 - 35.0) + 0.1))

    def test_every_piece_is_set_into_the_ground(self):
        g = self.ground(self.faces[:, 0], self.faces[:, 2])
        self.assertTrue(np.all(self.faces[:, 1] < g), "a face piece stands on the ground, not in it")
        gc = self.ground(self.crests[:, 0], self.crests[:, 2])
        self.assertTrue(np.all(self.crests[:, 1] < gc))

    def test_it_is_sized_to_the_face(self):
        # the walls are 141 m along the slope: every piece is as big as the pieces go
        self.assertGreater(float(np.median(self.faces[:, 4])), 0.9 * CR.FACE_SCALE[1])

    def test_outcrops_stand_on_the_convex_edges_and_the_crest(self):
        self.assertGreater(len(self.crests), 5)
        ax = np.abs(self.crests[:, 0])
        # the brow of each wall (from 180 m, where the ground stands over its surroundings) and the crest
        on = ((ax > 170.0) & (ax < 250.0)) | (np.abs(ax - 330.0) < 40.0)
        self.assertTrue(np.all(on), "an outcrop off the brows and the crest: %s" % ax[~on])

    def test_an_outcrop_on_a_slope_leans_with_it_and_its_downhill_edge_is_in_the_ground(self):
        # (playtest 5: "rocks jut from slopes"; the outcrops are seated as the scatter's rock is)
        from worldgen import cells as CELLS

        c = self.crests
        g0 = self.ground(c[:, 0], c[:, 2])
        d = 3.0
        s = np.abs((self.ground(c[:, 0] + d, c[:, 2]) - self.ground(c[:, 0] - d, c[:, 2])) / (2 * d))
        on_slope = s > 0.12
        self.assertGreater(int(on_slope.sum()), 2)
        self.assertTrue(np.all(c[on_slope, 6] > 0.0), "an outcrop upright on a slope")
        half = CELLS.asset_bounds(BOULDER, REPO)[0] * c[:, 4]
        # the foot's downhill edge: the pivot less the lean's share of the slope over the half-width
        edge = c[:, 1] - half * np.tan(np.radians(c[:, 6]))
        ground_edge = g0 - half * s
        self.assertTrue(np.all(edge[on_slope] < ground_edge[on_slope] + 0.05), "an outcrop floating downhill")

    def test_none_on_the_road_or_in_the_sightline(self):
        on_road = (self.faces[:, 0] > 0) & (np.abs(self.faces[:, 2]) < 2.0 + CR.ROAD_CLEAR_M)
        self.assertFalse(on_road.any())
        # under the line across the west wall, whatever stands keeps its top under the ray
        (ax, az), (bx, bz), _k, _a, _b = self.claims[0]
        near = (self.faces[:, 0] < -140.0) & (np.abs(self.faces[:, 2] - az) < CR.SIGHTLINE_CORRIDOR_M)
        eye = 100.0 + K["EYE_M"]
        top = float(self.ground(np.array([bx]), np.array([bz]))[0]) + K["LANDMARK_DEFAULT_M"]
        for r in self.faces[near]:
            t = (r[0] - ax) / (bx - ax)
            g = float(self.ground(np.array([r[0]]), np.array([r[2]]))[0])
            self.assertLess(g + 6.4 * r[4], eye + (top - eye) * t - K["CLEARANCE_M"], "a crag stands in the line")
        # and the corridor is not simply bare: the wall below the ray is dressed
        corridor = (self.faces[:, 0] < -110.0) & (np.abs(self.faces[:, 2] - az) < CR.SIGHTLINE_CORRIDOR_M)
        self.assertGreater(int(corridor.sum()), 0)


# --- the cliff ledge -------------------------------------------------------------------------------

LEDGE_H = {"a": 3.0, "b": 4.2, "c": 2.1}


def _fake_ledges(root: str, region: str = "skerrow") -> dict:
    """An asset index with this region's three ledges (and a boulder), their metas under `root` as
    the forge writes them: 5 m wide, the back 1.7 m behind the origin, the lip 2.5 m in front."""
    import json

    index = {"rocks": {}}
    for v, h in LEDGE_H.items():
        name = "%s_cliff_ledge_%s" % (region, v)
        d = os.path.join(root, "game", "assets", "models", "rocks", name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name + ".meta.json"), "w") as f:
            json.dump({"bounds": {"min": [-2.5, 0.0, -1.7], "max": [2.5, h, 2.5], "height": h},
                       "module_width_m": 5.0, "modular": True}, f)
        index["rocks"][name] = "res://assets/models/rocks/%s/%s.glb" % (name, name)
    name = "%s_boulder_a" % region
    d = os.path.join(root, "game", "assets", "models", "rocks", name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + ".meta.json"), "w") as f:
        json.dump({"bounds": {"min": [-1.0, 0.0, -1.0], "max": [1.0, 1.6, 1.0], "height": 1.6}}, f)
    index["rocks"][name] = "res://assets/models/rocks/%s/%s.glb" % (name, name)
    return index


def _rows(out: dict, part: str) -> list:
    return [(a, r) for by in out.values() for a, rows in by.items() if part in a for r in rows]


class Ledges(unittest.TestCase):
    """Where a region has the forge's ledges, its faces are runs of them along the contour, stacked
    up the face; its steep brows take a short run; and every ledge is seated, not floating."""

    @classmethod
    def setUpClass(cls):
        import tempfile

        cls.tmp = tempfile.TemporaryDirectory()
        cls.index = _fake_ledges(cls.tmp.name)
        base = Crags
        base.setUpClass()
        cls.base = base
        cls.grid, cls.H, cls.claims = base.grid, base.H, base.claims
        cls.road_d, cls.road_w = base.road_d, base.road_w
        rows, cls.counts = CR.place(cls.grid, cls.H, base.owner, base.water, base.water_d, cls.road_d, cls.road_w,
                                    base.pad, base.regions, cls.claims, K, cls.index, NoiseBank(11, cls.grid), 5,
                                    repo_root=cls.tmp.name)
        cls.ledges = _rows(rows, "_cliff_ledge_")
        cls.slabs = _rows(rows, "cliff_slab")
        cls.boulders = _rows(rows, "_boulder_")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def ground(self, x, z):
        return float(sample_bilinear(self.H, self.grid, np.array([x]), np.array([z]))[0])

    def h_of(self, asset):
        return LEDGE_H[asset.split("_cliff_ledge_")[1][0]]

    def test_the_faces_are_ledges_not_slabs(self):
        self.assertEqual(self.slabs, [])
        self.assertGreater(self.counts["ledge"], 60)
        on_faces = [r for a, r in self.ledges if 110.0 < abs(r[0]) < 232.0]
        self.assertGreater(len(on_faces), 0.9 * len(self.ledges))

    def test_a_ledge_looks_down_its_face(self):
        for a, r in self.ledges:
            if not 125.0 < abs(r[0]) < 215.0:
                continue                    # the foot and the brow turn
            want = 270.0 if r[0] > 0 else 90.0
            self.assertLess(abs(((r[3] + 360.0) % 360.0) - want), CR.LEDGE_YAW_JITTER_DEG + 3.0, r)
            self.assertEqual(r[6], 0.0)     # upright: its beds are level

    def test_every_ledge_is_seated_and_its_back_is_in_the_hill(self):
        for a, r in self.ledges:
            x, y, z, yaw, s = r[0], r[1], r[2], math.radians(r[3]), r[4]
            dx, dz = math.sin(yaw), math.cos(yaw)
            h = self.h_of(a)
            foot = 1.7 * (1.0 - 2.0 * CR.LEDGE_UNDERCUT) * s
            # its foot is under the ground at its front, or on the ledge below it
            self.assertLessEqual(y, self.ground(x + dx * foot, z + dz * foot) + h * s, r)
            # and no more than LEDGE_BACK_SHOW_M of its flat back stands over the hill behind it
            back = self.ground(x - dx * 1.7 * s, z - dz * 1.7 * s)
            self.assertLessEqual(y + h * s - back, (CR.LEDGE_BACK_SHOW_M + 0.6) * s + 0.05, r)

    def test_a_run_is_one_level_and_one_scale_with_its_ends_meeting(self):
        runs: dict = {}
        for a, r in self.ledges:
            runs.setdefault((round(r[1], 2), r[4], a, r[0] > 0), []).append(r)
        long_runs = [v for v in runs.values() if len(v) >= 3]
        self.assertGreater(len(long_runs), 5)
        for v in long_runs:
            z = np.sort([r[2] for r in v])
            gaps = np.diff(z)
            step = CR.LEDGE_STEP * 5.0 * v[0][4]
            # the modules in a run stand one step apart along the face (a straight contour here)
            near = gaps[gaps < 1.5 * step]
            self.assertTrue(np.allclose(near, step, atol=0.35), (step, near))

    def test_a_run_has_a_boulder_at_each_cut_end(self):
        runs: dict = {}
        for a, r in self.ledges:
            runs.setdefault((round(r[1], 2), r[4], r[0] > 0), []).append(r)
        bx = np.array([r[0] for a, r in self.boulders])
        bz = np.array([r[2] for a, r in self.boulders])
        checked = 0
        for v in runs.values():
            v = sorted(v, key=lambda r: r[2])
            if max(abs(r[0]) for r in v) > 215.0 or min(abs(r[0]) for r in v) < 125.0:
                continue                    # the brows and the feet turn: this is for the straight faces
            half = 2.5 * v[0][4]
            for end, out in ((v[0], -1.0), (v[-1], 1.0)):
                want = end[2] + out * half
                near = (np.abs(bx - end[0]) < 4.0 * v[0][4]) & (np.abs(bz - want) < 2.5)
                self.assertTrue(near.any(), "no boulder at the end of the run at %s" % (end[:3],))
                checked += 1
        self.assertGreater(checked, 10)

    def test_a_row_is_slid_along_the_face_from_the_row_below(self):
        rows: dict = {}
        for a, r in self.ledges:
            rows.setdefault((round(r[1], 2), r[4], r[0] > 0), []).append((a, r))
        pairs = moved = 0
        for (y, s, side), v in rows.items():
            step = CR.LEDGE_STEP * 5.0 * s

            def phase(zz):
                return float(np.angle(np.mean(np.exp(2j * np.pi * np.mod(np.array(zz), step) / step)))) / (2.0 * np.pi)

            for (yb, sb, sideb), w in rows.items():
                if sb != s or sideb != side:
                    continue
                if abs(yb + (self.h_of(w[0][0]) - CR.LEDGE_SEAT_M) * s - y) > 0.02:
                    continue
                zs = [r[2] for a, r in v]
                zb = [r[2] for a, r in w]
                if max(zs) < min(zb) - 1.0 or min(zs) > max(zb) + 1.0:
                    continue
                d = abs(phase(zs) - phase(zb))
                d = min(d, 1.0 - d)
                pairs += 1
                moved += int(d > 0.1)
        self.assertGreater(pairs, 5)
        self.assertGreater(moved, 0.6 * pairs, (moved, pairs))

    def test_rows_stand_on_the_row_below(self):
        tops: dict = {}
        for a, r in self.ledges:
            tops.setdefault(r[4], set()).add(round(r[1] + (self.h_of(a) - CR.LEDGE_SEAT_M) * r[4], 2))
        stacked = sum(1 for a, r in self.ledges if round(r[1], 2) in tops.get(r[4], ()))
        self.assertGreater(stacked, 10, "no ledge stands on another")

    def test_none_on_the_road_or_in_the_sightline(self):
        for a, r in self.ledges:
            if r[0] > 0:
                self.assertGreater(abs(r[2]), 2.0 + CR.ROAD_CLEAR_M - 0.5, r)
        (ax, az), (bx, bz), _k, _a, _b = self.claims[0]
        eye = 100.0 + K["EYE_M"]
        top = self.ground(bx, bz) + K["LANDMARK_DEFAULT_M"]
        for a, r in self.ledges:
            if r[0] < -120.0 and abs(r[2] - az) < CR.SIGHTLINE_CORRIDOR_M:
                t = (r[0] - ax) / (bx - ax)
                self.assertLess(r[1] + self.h_of(a) * r[4], eye + (top - eye) * t - K["CLEARANCE_M"])

    def test_the_same_inputs_lay_the_same_crags(self):
        base = self.base
        again, _ = CR.place(self.grid, self.H, base.owner, base.water, base.water_d, self.road_d, self.road_w,
                            base.pad, base.regions, self.claims, K, self.index, NoiseBank(11, self.grid), 5,
                            repo_root=self.tmp.name)
        self.assertEqual(sorted(tuple(r[:5]) for a, r in _rows(again, "_cliff_ledge_")),
                         sorted(tuple(r[:5]) for a, r in self.ledges))


class SeaCliff(unittest.TestCase):
    """A sea cliff is dressed from the water to its top in rows of ledges whose beds run level
    along it; a cave's pad at its foot keeps its mouth; nothing stands over the cliff's top."""

    TOP = 60.0
    COAST = 300.0
    PAD = (100.0, 292.0, 18.0, 4.0)

    @classmethod
    def setUpClass(cls):
        import tempfile

        cls.tmp = tempfile.TemporaryDirectory()
        cls.index = _fake_ledges(cls.tmp.name)
        cls.grid = g = Grid(1024.0, 256)
        n = g.n
        X, Z = g.mesh()
        Z = np.broadcast_to(Z, (n, n))
        X = np.broadcast_to(X, (n, n))
        # a plateau at 60 m to z = 300, the sea beyond it; the wall between is one texel; and a
        # stack in the sea, a pillar 40 m high and 24 m across
        H = np.where(Z < cls.COAST, cls.TOP + 0.5 * np.sin(X / 37.0), -6.0)
        stack = np.hypot(X + 200.0, Z - cls.COAST - 60.0) < 12.0
        cls.H = np.where(stack, 40.0, H).astype(np.float32)
        cls.owner = np.zeros((n, n), dtype=np.uint8)
        cls.regions = [SimpleNamespace(index=0, shape="mountains", art_short="skerrow")]
        cls.road_d = np.full((n, n), 1e6, dtype=np.float32)
        cls.road_w = np.full((n, n), 4.0, dtype=np.float32)
        atlas = {"coast": {"cliffs": [{"height_m": cls.TOP, "path": [[-420.0, cls.COAST], [420.0, cls.COAST]]}]}}
        stacks = [{"x": -200.0, "z": cls.COAST + 60.0, "r": 12.0, "top": 40.0}]
        out, cls.counts = CR.coast_walls(g, cls.H, atlas, cls.owner, cls.regions, cls.road_d, cls.road_w, [cls.PAD],
                                         [], K, cls.index, 5, repo_root=cls.tmp.name, stacks=stacks)
        cls.ledges = _rows(out, "_cliff_ledge_")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def h_of(self, asset):
        return LEDGE_H[asset.split("_cliff_ledge_")[1][0]]

    def wall(self):
        return [(a, r) for a, r in self.ledges if abs(r[2] - self.COAST) < 12.0]

    def test_the_cliff_is_dressed_along_its_length(self):
        s = float(np.clip(self.TOP * CR.WALL_SCALE_PER_M, *CR.WALL_SCALE))
        cols = {round(r[0], 1) for a, r in self.wall()}
        # 840 m of cliff at a column every 0.94 x 5 m x its scale
        self.assertGreater(len(cols), 0.8 * 840.0 / (CR.LEDGE_STEP * 5.0 * s))
        self.assertEqual(self.counts["walls"], 1)

    def beds(self) -> dict:
        by: dict = {}
        for a, r in self.wall():
            by.setdefault(round(r[1], 2), []).append(r)
        return by

    def test_the_beds_run_level_along_the_cliff(self):
        by = self.beds()
        s = self.wall()[0][1][4]
        # each bed stands at one height the whole length of the cliff
        for y, v in by.items():
            if len(v) >= 10:
                xs = [r[0] for r in v]
                self.assertGreater(max(xs) - min(xs), 600.0, y)
        # and the beds are the one sequence: none within a bed's thickness of another
        gaps = np.diff(sorted(by))
        self.assertTrue((gaps >= (min(LEDGE_H.values()) - CR.LEDGE_SEAT_M) * s - 0.01).all(), gaps)

    def test_the_joints_do_not_line_up_from_bed_to_bed(self):
        s = self.wall()[0][1][4]
        step = CR.LEDGE_STEP * 5.0 * s
        by = self.beds()
        levels = sorted(y for y in by if len(by[y]) >= 20)

        def phase(v):
            xs = np.array([r[0] for r in v])
            return float(np.angle(np.mean(np.exp(2j * np.pi * np.mod(xs, step) / step)))) / (2.0 * np.pi)

        ph = [phase(by[y]) for y in levels]
        apart = [min(abs(a - b), 1.0 - abs(a - b)) for a, b in zip(ph, ph[1:])]
        self.assertGreater(len(apart), 3)
        self.assertGreater(sum(1 for d in apart if d > 0.1), len(apart) // 2, (levels, ph))

    def test_soft_beds_are_weathered_back_and_the_bays_bare(self):
        by = self.beds()
        s = self.wall()[0][1][4]
        counts = sorted(len(v) for v in by.values() if len(v) >= 10)
        # the hard beds run on across the bays; the others stand on the buttresses alone
        self.assertGreater(counts[-1], 1.4 * counts[0], counts)
        # a soft bed is weathered back along the whole cliff: somewhere a gap of more than a bed
        levels = sorted(by)
        self.assertTrue((np.diff(levels) > (max(LEDGE_H.values()) - CR.LEDGE_SEAT_M) * s + 0.01).any(), levels)
        # but never two together
        self.assertTrue((np.diff(levels) < 2.0 * (max(LEDGE_H.values()) - CR.LEDGE_SEAT_M) * s + 0.01).all(), levels)

    def test_a_ledge_stands_proud_of_the_wall_and_under_its_top(self):
        for a, r in self.wall():
            x, y, z, yaw, s = r[0], r[1], r[2], math.radians(r[3]), r[4]
            h = self.h_of(a)
            self.assertLess(abs(((r[3] + 180.0) % 360.0) - 180.0), 1.0, r)
            # it looks out to sea (+z), its foot out over the water and its back in the rock
            foot_z = z + math.cos(yaw) * 1.7 * (1.0 - 2.0 * CR.LEDGE_UNDERCUT) * s
            back_z = z - math.cos(yaw) * 1.7 * s
            at = lambda zz: float(sample_bilinear(self.H, self.grid, np.array([x]), np.array([zz]))[0])  # noqa: E731
            self.assertLess(at(foot_z), y + 0.5 * h * s, r)
            if y + h * s < self.TOP - 1.0:
                self.assertGreater(at(back_z), y + 0.5 * h * s, r)
            self.assertLessEqual(y + h * s, self.TOP + 0.5 + CR.WALL_OVERSHOOT_M, r)
            # and nothing entirely under the sea
            self.assertGreater(y + h * s, -0.3)

    def test_the_cave_keeps_its_mouth(self):
        px, pz, pr, lvl = self.PAD
        over = []
        for a, r in self.ledges:
            if math.hypot(r[0] - px, r[2] - pz) < pr + CR.WALL_PAD_CLEAR_M:
                self.assertGreaterEqual(r[1], lvl + CR.WALL_PAD_HEADROOM_M - 1e-6, r)
                over.append(r)
        self.assertGreater(len(over), 0, "the wall over the cave is bare")

    def test_the_stack_takes_the_same_beds(self):
        ring = [(a, r) for a, r in self.ledges if math.hypot(r[0] + 200.0, r[2] - self.COAST - 60.0) < 20.0]
        self.assertGreater(len(ring), 6)
        self.assertEqual(self.counts["stack_ledges"], len(ring))
        for a, r in ring:
            self.assertLessEqual(r[1] + self.h_of(a) * r[4], 40.0 + CR.WALL_OVERSHOOT_M + 1e-6)
        # its beds are the cliff's: the same ledge at the same height
        wall_beds = {(round(r[1], 2), a) for a, r in self.wall()}
        self.assertTrue({(round(r[1], 2), a) for a, r in ring} <= wall_beds)


if __name__ == "__main__":
    unittest.main()
