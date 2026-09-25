#!/usr/bin/env python3
"""A cell's instances kept as arrays (worldgen.rows.Rows) write the rows the lists wrote.

    python3 -m pytest tools/world/tests/test_rows.py
"""
from __future__ import annotations

import json
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen.cells import _hex  # noqa: E402
from worldgen.rows import Rows, pack_rgb  # noqa: E402


def _as_lists(x, y, z, yaw, scale, tints, lean=None, toward=None) -> list:
    """The rows as the scatter wrote them when they were lists."""
    out = []
    for t in range(x.size):
        row = [round(float(x[t]), 2), round(float(y[t]), 2), round(float(z[t]), 2),
               round(float(yaw[t]), 1), round(float(scale[t]), 3), _hex(tints[t])]
        if lean is not None:
            row += [round(float(lean[t]), 1), round(float(toward[t]), 1)]
        out.append(row)
    return out


class RowsTest(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(9)
        n = 5000
        self.x = np.round(rng.uniform(-4096.0, 4096.0, n), 2)
        self.z = np.round(rng.uniform(-4096.0, 4096.0, n), 2)
        self.y = rng.uniform(-30.0, 800.0, n).astype(np.float32)
        self.yaw = rng.uniform(0.0, 360.0, n).astype(np.float32)
        self.scale = rng.uniform(0.3, 2.2, n).astype(np.float32)
        self.tints = np.clip(rng.uniform(0.2, 1.1, (n, 3)), 0.25, 1.0)
        self.lean = rng.uniform(0.0, 30.0, n).astype(np.float32)
        self.toward = rng.uniform(-180.0, 180.0, n).astype(np.float32)

    def test_the_arrays_give_back_the_lists_value_for_value(self):
        r = Rows()
        r.add_arrays(self.x, self.y, self.z, self.yaw, self.scale, pack_rgb(self.tints), self.lean, self.toward)
        want = _as_lists(self.x, self.y, self.z, self.yaw, self.scale, self.tints, self.lean, self.toward)
        self.assertEqual(len(r), len(want))
        self.assertEqual(list(r), want)
        self.assertEqual(json.dumps({"i": r}, default=Rows.as_json), json.dumps({"i": want}))

    def test_lists_added_after_keep_their_order_and_keep_filters_both(self):
        r = Rows()
        r.add_arrays(self.x[:3], self.y[:3], self.z[:3], self.yaw[:3], self.scale[:3], pack_rgb(self.tints[:3]))
        r.extend([[1.0, 2.0, 3.0, 4.0, 1.0, "#ffffff", 0.0, 0.0, [1.0, 1.0, 2.0]]])
        r.add_arrays(self.x[3:5], self.y[3:5], self.z[3:5], self.yaw[3:5], self.scale[3:5], pack_rgb(self.tints[3:5]))
        rows = list(r)
        self.assertEqual(len(rows), 6)
        self.assertEqual(rows[3][8], [1.0, 1.0, 2.0])
        np.testing.assert_allclose(r.xz()[:, 0], [row[0] for row in rows], atol=0.006)
        r.keep(np.array([True, False, True, False, True, True]))
        self.assertEqual(list(r), [rows[0], rows[2], rows[4], rows[5]])
        self.assertEqual(len(r), 4)


if __name__ == "__main__":
    unittest.main()
