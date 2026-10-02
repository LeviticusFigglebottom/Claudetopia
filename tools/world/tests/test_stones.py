#!/usr/bin/env python3
"""The stones the build sets (worldgen/stones.py) stand off the roads.

    python3 -m pytest tools/world/tests/test_stones.py

On w4096h a stone of the pair flanking one road where it tops a rise stood in the carriageway of
another road crossing there (the Charter Delf's new track): the seat audit's on_road.
"""
from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import roads as RD  # noqa: E402
from worldgen import stones as ST  # noqa: E402
from worldgen.grid import Grid  # noqa: E402


class FlankingStonesTest(unittest.TestCase):
    def test_a_pair_flanking_one_road_keeps_off_another(self):
        g = Grid(1024.0, 256)
        X, Z = g.mesh(np.float64)
        # a rise along x = 0, a road over it north to south, and a track along it 8 m to the east,
        # where the east stone of the pair would stand
        H = np.broadcast_to(60.0 - 0.05 * np.abs(Z) + 0.0 * X, (g.n, g.n)).astype(np.float32)
        a = np.stack([np.zeros(60), np.linspace(-300.0, 300.0, 60)], axis=1)
        b = np.stack([np.full(60, 8.0), np.linspace(-300.0, 300.0, 60)], axis=1)
        roads = [RD.Road(id="core:road/a", points=a, width=5.0, elevation=np.zeros(60)),
                 RD.Road(id="core:road/b", points=b, width=3.5, elevation=np.zeros(60))]
        d = np.broadcast_to(np.minimum(np.abs(X - 0.0), np.abs(X - 8.0)) + 0.0 * Z, (g.n, g.n))
        region = SimpleNamespace(index=1, art_short="skerrow", short="skerrow")
        owner = np.ones((g.n, g.n), dtype=np.int32)
        zero = np.zeros((g.n, g.n), dtype=np.uint8)
        index = {"rocks": {"skerrow_standing_stone_a": "res://assets/models/rocks/skerrow_standing_stone_a/skerrow_standing_stone_a.glb"}}
        out = ST.place(g, H, owner, np.zeros((g.n, g.n), dtype=np.float32), zero, d.astype(np.float32),
                       zero.astype(bool), [region], [], roads, index, seed=7)
        rows = [r for by in out.values() for rs in by.values() for r in rs]
        self.assertTrue(rows, "no stones were set at all")
        for r in rows:
            self.assertGreater(min(abs(r[0] - 0.0), abs(r[0] - 8.0)), ST.STONE_ROAD_CLEAR_M, r)


if __name__ == "__main__":
    unittest.main()
