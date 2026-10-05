#!/usr/bin/env python3
"""No pad's skirt dams a valley into a dry pit.

    python3 -m pytest tools/world/tests/test_pad_dams.py

The owner's Briar crash (2026-09-30): Fernhold's lodge pad, levelled at 274 m, was laid over the
head of a stream valley; its western skirt filled the valley's way out and left a dry pit 52 m
deep and 60 m across at the settlement's edge, walled at seventy degrees on the pad side.
`roads.drain_pad_dams` fills every such hollow back to where it would spill.
"""
from __future__ import annotations

import json
import os
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS_WORLD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOLS_WORLD))
GEN = os.environ.get("WICKMERE_GENERATED", os.path.join(REPO, "game", "world", "generated"))
sys.path.insert(0, TOOLS_WORLD)

from worldgen import roads as RD  # noqa: E402
from worldgen.grid import Grid  # noqa: E402


def _closed_depth(h: np.ndarray, outlet: np.ndarray | None = None) -> np.ndarray:
    from skimage.morphology import reconstruction
    h = h.astype(np.float64)
    seed = np.full_like(h, h.max())
    edge = np.zeros(h.shape, dtype=bool)
    edge[0, :] = edge[-1, :] = edge[:, 0] = edge[:, -1] = True
    if outlet is not None:
        edge |= outlet
    seed[edge] = h[edge]
    return reconstruction(seed, h, method="erosion") - h


class SyntheticDam(unittest.TestCase):
    """A valley running east under a pad set level with the hills either side of it."""

    def setUp(self):
        self.g = Grid(1024.0, 256)
        X, Z = self.g.mesh(np.float64)
        # land at 100 m falling east at 1 in 5, with a valley 60 m deep along z = 0
        land = 100.0 - 0.2 * X
        valley = 60.0 * np.exp(-(Z / 40.0) ** 2)
        self.H0 = (land - valley + 0.0 * X).astype(np.float32)
        self.place = {"id": "test:place/lodge", "kind": "lodge", "position": [100.0, 0.0]}

    def test_the_pad_dams_the_valley_and_the_drain_opens_it(self):
        H = self.H0.copy()
        # levelled at the hills' height, the way a median over a valley's rims sets it
        H, _m, levels = RD.apply_pads(self.g, H, [self.place], fixed_levels={"test:place/lodge": 80.0})
        before = _closed_depth(H)
        self.assertGreater(float(before.max()), 20.0, "the synthetic pad should dam the valley")
        H2, report = RD.drain_pad_dams(self.g, H.copy(), [self.place])
        after = _closed_depth(H2)
        self.assertEqual(len(report), 1)
        self.assertLessEqual(float(after.max()), RD.DAM_DELL_M + 0.3)
        # the pad itself is not touched
        j, i = self.g.clamp_index(*self.g.to_tex(100.0, 0.0))
        self.assertAlmostEqual(float(H2[int(i), int(j)]), float(H[int(i), int(j)]), places=3)
        # nothing is dug, only filled
        self.assertTrue(bool((H2 >= H - 1e-4).all()))

    def test_a_shallow_hollow_and_an_outlet_are_left_alone(self):
        X, Z = self.g.mesh(np.float64)
        H = np.full((self.g.n, self.g.n), 50.0, dtype=np.float32)
        # a shakehole 5 m deep on the skirt, and a pit 20 m deep that is a lake (an outlet)
        H -= (5.0 * np.clip(1.0 - ((X - 140.0) ** 2 + Z ** 2) / 15.0 ** 2, 0, 1)).astype(np.float32)
        lake = ((X - 60.0) ** 2 + Z ** 2) < 12.0 ** 2
        H = np.where(lake, 30.0, H).astype(np.float32)
        H2, report = RD.drain_pad_dams(self.g, H.copy(), [self.place], outlet=lake)
        self.assertEqual(report, [])
        self.assertTrue(np.array_equal(H2, H))


    def test_a_level_core_in_a_hollow_is_left_level(self):
        """A settlement whose level ground reaches into a hollow a skirt closed keeps it level: the
        fill goes round it (Ormhold, 0.7 m out of level on a third of it before)."""
        X, Z = self.g.mesh(np.float64)
        town = {"id": "test:place/town", "kind": "village", "position": [0.0, 0.0]}
        r = RD.pad_level_radius(town)
        H = np.full((self.g.n, self.g.n), 60.0, dtype=np.float32)
        # a closed hollow 9 m deep whose floor takes in the town's west side
        H -= (9.0 * np.clip(1.0 - ((X + r) ** 2 + Z ** 2) / 30.0 ** 2, 0, 1)).astype(np.float32)
        core = X ** 2 + Z ** 2 <= r * r
        H = np.where(core, 51.0, H).astype(np.float32)
        H2, report = RD.drain_pad_dams(self.g, H.copy(), [town])
        self.assertTrue(report, "the hollow is filled")
        self.assertTrue(np.array_equal(H2[core], H[core]), "and the town's level ground is not")


    def test_a_pad_on_a_basin_floor_is_not_walled_in(self):
        """A basin of the country's own is filled no higher than the pad laid on its floor: filled to
        where it would spill, Wassail Knap's valley stood 17 m over its pad all round (w4096l)."""
        X, Z = self.g.mesh(np.float64)
        poi = {"id": "test:poi/knap", "kind": "delve", "position": [0.0, 0.0], "pad_radius_m": 46}
        r = RD.pad_level_radius(poi)
        # a closed basin 24 m deep and 300 m across, the pad on its floor a little over the lowest of it
        H = (90.0 - 24.0 * np.clip(1.0 - (X ** 2 + Z ** 2) / 150.0 ** 2, 0, 1)).astype(np.float32)
        core = X ** 2 + Z ** 2 <= r * r
        level = 70.0
        H = np.where(core, level, H).astype(np.float32)
        H2, report = RD.drain_pad_dams(self.g, H.copy(), [poi])
        self.assertTrue(report, "the basin touches the pad's skirt")
        raised = H2 > H + 1e-3
        self.assertTrue(bool(raised.any()), "the basin's floor round the pad is filled")
        self.assertLessEqual(float(H2[raised].max()), level + 1e-3, "the fill stands over the pad")
        self.assertTrue(np.array_equal(H2[core], H[core]))


class BuiltFernhold(unittest.TestCase):
    """The pit as the last world build left it, and what the drain makes of it (at 8 m texels)."""

    def test_the_fernhold_pit_is_drained(self):
        path = os.path.join(GEN, "runtime", "heights_1024.r32")
        man = os.path.join(GEN, "world_manifest.json")
        if not (os.path.exists(path) and os.path.exists(man)):
            self.skipTest("no built world")
        with open(man, "r", encoding="utf-8") as f:
            size = float(json.load(f)["size_m"])
        g = Grid(size, 1024)
        H = np.fromfile(path, dtype="<f4").reshape(1024, 1024).copy()
        water = np.fromfile(os.path.join(GEN, "runtime", "water_1024.u8"), dtype="u1").reshape(1024, 1024) > 0
        place = {"id": "core:place/fernhold", "kind": "lodge", "position": [3350.0, 230.0]}
        j, i = g.clamp_index(*g.to_tex(3272.0, 216.0))
        win = (slice(int(i) - 40, int(i) + 40), slice(int(j) - 40, int(j) + 40))
        depth0 = _closed_depth(H[win], water[win])
        H2, report = RD.drain_pad_dams(g, H, [place], outlet=water)
        depth1 = _closed_depth(H2[win], water[win])
        # the pit's own floor (other hollows in the window are the country's, not the pad's)
        at = (40, 40)
        if float(depth0[at]) > RD.DAM_MIN_M:
            self.assertTrue(report, "a pit %.1f m deep by Fernhold and nothing drained" % depth0[at])
        self.assertLessEqual(float(depth1[at]), RD.DAM_DELL_M + 1.0,
                             "the pit by Fernhold is still %.1f m deep" % depth1[at])
        print("fernhold pit: %.1f m deep before, %.1f m after; %s" % (depth0[at], depth1[at], report))


if __name__ == "__main__":
    unittest.main()
