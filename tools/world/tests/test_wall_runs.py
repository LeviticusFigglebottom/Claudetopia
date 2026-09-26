#!/usr/bin/env python3
"""A wall or a hedge is laid end to end along its boundary (worldgen.hedges._lay_runs), not a piece
per boundary texel: on w4096d the seat audit found 10,229 gaps of 1-4 m in the middle of Skerrow's
drystone walls, staggered blocks with daylight between them where a diagonal boundary's texels
stepped and where it turned. Along a traced line every piece meets the next, through a straight
diagonal and round a corner, and seating one (worldgen.lines.seat) keeps its stretch.

    python3 -m pytest tools/world/tests/test_wall_runs.py
"""
from __future__ import annotations

import math
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import hedges as HG  # noqa: E402
from worldgen import lines as LN  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

WALL = "res://assets/models/props/skerrow_drystone_wall_a/skerrow_drystone_wall_a.glb"
PIECE_M = 2.4


def _ends(row):
    """A laid piece's two ends on the ground, from its middle, yaw and stretched length."""
    a = math.radians(row[3])
    ux, uz = math.cos(a), -math.sin(a)
    half = 0.5 * PIECE_M * row[8][0]
    return (row[0] - ux * half, row[2] - uz * half), (row[0] + ux * half, row[2] + uz * half)


class WallRuns(unittest.TestCase):
    def setUp(self):
        self.g = Grid(512.0, 256)                   # 2 m texels
        self.H = np.zeros((256, 256), dtype=np.float32)

    def _lay(self, mask):
        out: dict = {}
        n = HG._lay_runs(out, self.g, self.H, mask, [WALL], PIECE_M, np.random.default_rng(3))
        rows = [r for by in out.values() for r in by.get(WALL, [])]
        self.assertEqual(n, len(rows))
        return rows

    def _bare(self, rows, mask, tips, ends_m=6.0, off_m=0.8):
        """The boundary texels no piece covers (its middle line within 0.8 m of the texel, along
        its stretched length), leaving out those within `ends_m` of a run's two ends."""
        segs = np.array([[*a, *b] for a, b in (_ends(r) for r in rows)])
        ii, jj = np.nonzero(mask)
        px = self.g.x0 + jj * self.g.spacing
        pz = self.g.z0 + ii * self.g.spacing
        ax, az, bx, bz = segs[:, 0], segs[:, 1], segs[:, 2], segs[:, 3]
        dx, dz = bx - ax, bz - az
        L2 = dx * dx + dz * dz
        bare = []
        for x, z in zip(px, pz):
            t = np.clip(((x - ax) * dx + (z - az) * dz) / L2, 0.0, 1.0)
            d = np.hypot(ax + t * dx - x, az + t * dz - z)
            if d.min() > off_m and all(math.hypot(x - a, z - b) > ends_m for a, b in tips):
                bare.append((x, z))
        return bare

    def test_a_diagonal_boundary_is_one_straight_wall(self):
        mask = np.zeros((256, 256), dtype=bool)
        for k in range(20, 120):
            mask[k, k] = True
            mask[k, k + 1] = True                   # a staircase two texels thick in places
        rows = self._lay(mask)
        length = math.hypot(100 * 2.0, 100 * 2.0)
        self.assertAlmostEqual(len(rows), length / PIECE_M, delta=3)
        # (its ends are pinned to where the boundary ends, so the last piece or two may bend to it)
        mid = [r for r in rows if min(math.hypot(r[0] - e[0], r[2] - e[1]) for e in
                                      ((self.g.x0 + 40.0, self.g.z0 + 40.0), (self.g.x0 + 240.0, self.g.z0 + 238.0))) > 6.0]
        yaws = np.array([r[3] for r in mid])
        self.assertLess(float(np.ptp(yaws)), 6.0, "a straight boundary is a straight wall, not a zigzag")
        tips = [(self.g.x0 + 40.0, self.g.z0 + 40.0), (self.g.x0 + 240.0, self.g.z0 + 238.0)]
        # (a band two texels thick is thinned to one side of it: its far texels are 1.4 m off)
        self.assertEqual(self._bare(rows, mask, tips, off_m=1.5), [])

    def test_a_turn_leaves_no_gap(self):
        mask = np.zeros((256, 256), dtype=bool)
        mask[40, 40:120] = True                     # east, then a right angle south
        mask[40:120, 119] = True
        rows = self._lay(mask)
        # (the line is simplified to straight stretches and a corner stays a corner, less the one
        # corner texel the thinning cuts, 1.4 m off)
        self.assertEqual(self._bare(rows, mask, [], ends_m=0.0, off_m=1.5), [], "the corner is walled round")
        # and consecutive pieces overlap: every piece's end is inside its neighbour's length
        ends = [_ends(r) for r in rows]
        joined = 0
        for k in range(len(ends) - 1):
            joined += min(math.hypot(p[0] - q[0], p[1] - q[1]) for p in ends[k] for q in ends[k + 1]) < 1.0
        self.assertGreaterEqual(joined, len(ends) - 2)

    def test_seating_keeps_the_stretch(self):
        mask = np.zeros((256, 256), dtype=bool)
        mask[60, 30:90] = True
        out: dict = {}
        HG._lay_runs(out, self.g, self.H, mask, [WALL], PIECE_M, np.random.default_rng(1))
        before = sorted(r[8][0] for by in out.values() for r in by[WALL])
        # a slope along the run, so every piece is pitched
        X, _Z = self.g.mesh()
        H = (0.08 * np.broadcast_to(X, self.H.shape)).astype(np.float32)
        LN.seat(out, self.g, H)
        after = sorted(r[8][0] for by in out.values() for r in by[WALL])
        self.assertEqual(len(before), len(after))
        self.assertTrue(np.allclose(before, after, atol=1e-3))


if __name__ == "__main__":
    unittest.main()
