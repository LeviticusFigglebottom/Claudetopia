#!/usr/bin/env python3
"""No tree's crown reaches over a town (worldgen.trees.clear_off_towns).

The scatter keeps a tree's trunk off a town's pad, and nothing kept its crown off it: the Briarwold's
giant oaks are 40 m across with leaves down to the ground, and those standing at the edge of
Fernhold's pad came through the lodge's houses (the owner, 2026-10-02). These check the pass on a
synthetic wood and on the installed world's start towns.

    python3 -m pytest tools/world/tests/test_crowns_off_towns.py
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

from worldgen import trees as TR  # noqa: E402
from worldgen.rows import Rows  # noqa: E402

OAK = "res://assets/models/trees/briarwold_giant_oak_a/briarwold_giant_oak_a.glb"
ASH = "res://assets/models/trees/briarwold_black_ash_a/briarwold_black_ash_a.glb"
FERN = "res://assets/models/flora/briarwold_fern_a/briarwold_fern_a.glb"
GENERATED = os.path.join(REPO, "game", "world", "generated")
## The four fighting-style starts (docs/FIGHTING_STYLE_STARTS.md), the towns their openings stand in.
STARTS = ("core:place/fernhold", "core:place/wardens_rest", "core:place/gullhithe", "core:place/moreva")


def _wood(asset: str, step: int = 4):
    """One tree of `asset` every `step` m over 240 m square round the origin, turned every way, and
    ferns among them, in one cell."""
    rows = []
    for i, x in enumerate(range(-120, 121, step)):
        for j, z in enumerate(range(-120, 121, step)):
            rows.append([float(x), 10.0, float(z), float((i * 37 + j * 71) % 360), 1.0 + 0.5 * ((i + j) % 3) / 2.0, "#ffffff"])
    trees = Rows()
    trees.extend(rows)
    return {(0, 0): {asset: trees, FERN: [list(r) for r in rows]}}


def _crown_reach(asset: str, rows, cx: float, cz: float) -> np.ndarray:
    lo, hi = TR.crown_box(asset, REPO)
    xz = rows.xz() if isinstance(rows, Rows) else np.array([(r[0], r[2]) for r in rows], dtype=np.float64).reshape(-1, 2)
    yaw = rows.column(3, "yaw") if isinstance(rows, Rows) else np.array([r[3] for r in rows], dtype=np.float64)
    scale = rows.column(4, "scale") if isinstance(rows, Rows) else np.array([r[4] for r in rows], dtype=np.float64)
    return TR.crown_distance(cx, cz, xz, yaw, scale, lo, hi)


class CrownsOffTowns(unittest.TestCase):
    def test_the_crown_box_is_the_forges(self):
        lo, hi = TR.crown_box(OAK, REPO)
        # the giant oak reaches about 20 m from its trunk at scale one, further on one side
        self.assertGreater(float(max(abs(lo).max(), abs(hi).max())), 18.0)
        self.assertIsNone(TR.crown_box("res://assets/models/trees/nothing/nothing.glb", REPO))

    def test_a_point_under_a_turned_crown(self):
        # a box from x -1..9, z -1..1 at scale one: turned 90 degrees about +Y its long side lies along -z
        lo, hi = np.array([-1.0, -1.0]), np.array([9.0, 1.0])
        xz = np.array([[0.0, 0.0]])
        under = TR.crown_distance(0.0, -8.0, xz, np.array([90.0]), np.array([1.0]), lo, hi)
        beside = TR.crown_distance(8.0, 0.0, xz, np.array([90.0]), np.array([1.0]), lo, hi)
        self.assertAlmostEqual(float(under[0]), 0.0)
        self.assertGreater(float(beside[0]), 6.0)
        # scaled twice, it reaches twice as far
        self.assertAlmostEqual(float(TR.crown_distance(0.0, -16.0, xz, np.array([90.0]), np.array([2.0]), lo, hi)[0]), 0.0)

    def test_no_crown_reaches_the_town_and_the_wood_round_it_stays(self):
        for asset in (OAK, ASH):
            buckets = _wood(asset)
            before = len(buckets[(0, 0)][asset])
            pad = 36.8
            out = TR.clear_off_towns(buckets, [(0.0, 0.0, pad)], REPO)
            left = buckets[(0, 0)][asset]
            reach = _crown_reach(asset, left, 0.0, 0.0)
            self.assertGreaterEqual(float(reach.min()), pad + TR.TOWN_CROWN_CLEAR_M - 1e-6,
                                    "%s: a crown still reaches the town" % asset)
            self.assertEqual(out["trees"], before - len(left))
            self.assertEqual(out["by_town"], [out["trees"]])
            # only what reached: a tree whose crown stops short of the town is still there
            self.assertGreater(len(left), before // 2, "%s: the wood round the town was cleared too" % asset)
            # and the ground's low cover is not the pass's
            self.assertEqual(len(buckets[(0, 0)][FERN]), before)

    def test_a_giant_oak_is_kept_further_off_than_an_ash(self):
        oaks, ashes = _wood(OAK), _wood(ASH)
        TR.clear_off_towns(oaks, [(0.0, 0.0, 36.8)], REPO)
        TR.clear_off_towns(ashes, [(0.0, 0.0, 36.8)], REPO)
        near_oak = float(np.hypot(*oaks[(0, 0)][OAK].xz().T).min())
        near_ash = float(np.hypot(*ashes[(0, 0)][ASH].xz().T).min())
        self.assertGreater(near_oak, near_ash + 10.0)


def _installed_towns() -> dict:
    """{place id: (x, z, pad radius)} for the start towns, off the installed world's pois.json."""
    path = os.path.join(GENERATED, "pois.json")
    if not os.path.exists(path):
        return {}
    out = {}
    for e in json.load(open(path, encoding="utf-8")):
        if e.get("place_id") in STARTS:
            out[e["place_id"]] = (float(e["pos"][0]), float(e["pos"][2]), float(e["radius_flat_m"]))
    return out


class StartTownsInTheInstalledWorld(unittest.TestCase):
    """The installed world, as a player gets it: no tree's crown over any of the four start towns,
    nor over the gardens and yards round them. (Built before the pass, w4096j had 35 trees' crowns
    over Fernhold, 12 over Wardens' Rest, 8 over Moreva and 2 over Gullhithe.)"""

    def test_no_crown_over_a_start_town(self):
        towns = _installed_towns()
        if not towns:
            self.skipTest("no installed world")
        manifest = json.load(open(os.path.join(GENERATED, "world_manifest.json"), encoding="utf-8"))
        cell_m = float(manifest["cell_size_m"])
        ox, oz = manifest["origin"]
        found = []
        for place, (x, z, pad) in sorted(towns.items()):
            cx, cz = int((x - ox) // cell_m), int((z - oz) // cell_m)
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    path = os.path.join(GENERATED, "cells", "%d_%d.json" % (cx + dx, cz + dz))
                    if not os.path.exists(path):
                        continue
                    cell = json.load(open(path, encoding="utf-8"))
                    for asset, rows in cell.get("instances", {}).items():
                        if "/trees/" not in asset or TR.crown_box(asset, REPO) is None or not rows:
                            continue
                        reach = _crown_reach(asset, rows, x, z)
                        for k in np.flatnonzero(reach < pad + TR.TOWN_CROWN_CLEAR_M - 0.05):
                            r = rows[int(k)]
                            found.append("%s: %s at (%.0f, %.0f), %.0f m from the middle, its crown %.1f m from it (pad %.1f m)"
                                         % (place.split("/")[-1], asset.split("/")[-1], r[0], r[2],
                                            math.hypot(r[0] - x, r[2] - z), float(reach[k]), pad))
        self.assertEqual(found, [], "%d crowns over a start town:\n  %s" % (len(found), "\n  ".join(found[:40])))


if __name__ == "__main__":
    unittest.main()
