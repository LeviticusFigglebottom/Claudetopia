#!/usr/bin/env python3
"""Checks tools/ui/gen_map.py against a small synthetic world written on the fly.

Run:  python3 tools/ui/tests/test_gen_map.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "ui"))

import gen_map  # noqa: E402


GRID = 96
SIZE_M = 8192.0


def write_synthetic_world(world_dir: Path) -> None:
    """A tiny world in the shape CONTRACTS §6 describes: a hill, a lake, a road, a river."""
    world_dir.mkdir(parents=True, exist_ok=True)
    ys, xs = np.mgrid[0:GRID, 0:GRID].astype(np.float32)
    cx = cy = (GRID - 1) / 2.0
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / (GRID * 0.5)
    heights = (120.0 * np.clip(1.0 - d, 0.0, 1.0) ** 1.5 + 6.0).astype("<f4")
    heights[ys > GRID * 0.80] = -4.0                       # water along the south edge
    heights.tofile(world_dir / "heights.r32")

    region_mask = np.zeros((GRID, GRID), np.uint8)
    region_mask[:, GRID // 2:] = 1
    region_mask[heights < 8.0] = 255
    region_mask.tofile(world_dir / "region_mask.u8")

    water = (heights < 8.0).astype(np.uint8)
    water.tofile(world_dir / "water_mask.u8")

    (world_dir / "roads.json").write_text(json.dumps(
        [{"id": "road_0", "points": [[-3000, -3000], [0, 0], [2500, 2000]], "width_m": 6.0}]))
    (world_dir / "rivers.json").write_text(json.dumps(
        [{"id": "river_0", "points": [[-1000, -3500], [-400, -800], [0, 2000]], "width_m": 12.0}]))
    (world_dir / "world_manifest.json").write_text(json.dumps({
        "seed": 7, "size_m": SIZE_M, "spacing_m": SIZE_M / GRID, "origin": [-SIZE_M / 2, -SIZE_M / 2],
        "grid": GRID, "sea_level": 0, "lake_level": 8,
        "regions": ["core:region/hearthvale", "core:region/briarwold"],
        "cell_size_m": 256, "cells": [32, 32],
    }))


def check(condition: bool, message: str, failures: list[str]) -> None:
    print(("  ok   " if condition else "  FAIL ") + message)
    if not condition:
        failures.append(message)


def main() -> int:
    failures: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="wickmere_map_"))
    try:
        world_dir = tmp / "generated"
        out_dir = tmp / "out"
        write_synthetic_world(world_dir)

        loaded = gen_map.read_world(world_dir)
        check(loaded is not None, "the synthetic world is read back", failures)
        check(loaded["heights"].shape == (GRID, GRID), "heights come back as grid x grid", failures)
        check(len(loaded["roads"]) == 1 and len(loaded["rivers"]) == 1, "roads and rivers load", failures)

        size = 256
        info = gen_map.build(world_dir, out_dir, size=size)
        png = out_dir / "world_map.png"
        check(png.exists(), "a chart is written", failures)
        check((out_dir / "world_map.json").exists(), "the transform is written beside it", failures)
        check(not info["synthetic"], "a real world is not reported as synthetic", failures)
        check(abs(float(info["size_m"]) - SIZE_M) < 0.01, "the manifest's extent is carried through", failures)

        image = Image.open(png)
        check(image.size == (size, size), "the chart is the size asked for, got %s" % (image.size,), failures)
        check(image.mode == "RGB", "the chart is RGB", failures)

        pixels = np.asarray(image, np.float32)
        check(float(pixels.std()) > 8.0, "the chart is not a flat colour (std %.1f)" % pixels.std(), failures)
        distinct = len(np.unique(pixels.reshape(-1, 3), axis=0))
        check(distinct > 2000, "the chart has real variety (%d distinct colours)" % distinct, failures)

        # the water along the south edge must read colder than the hill in the middle
        south = pixels[int(size * 0.92), :, :]
        middle = pixels[int(size * 0.45), :, :]
        blueness = lambda row: float((row[:, 2] - row[:, 0]).mean())
        check(blueness(south) > blueness(middle) + 8.0,
              "water is painted cooler than land (%.1f vs %.1f)" % (blueness(south), blueness(middle)), failures)

        # the transform must put the world's origin at the top left and its far corner bottom right
        origin = info["origin"]
        check(abs(origin[0] + SIZE_M / 2) < 0.01 and abs(origin[1] + SIZE_M / 2) < 0.01,
              "the origin is the north-west corner", failures)

        # a world with nothing generated still paints a chart, from the region definitions
        synth_out = tmp / "synth"
        synth_info = gen_map.build(tmp / "nothing_here", synth_out, size=192)
        check(synth_info["synthetic"], "a missing world falls back to the region definitions", failures)
        check((synth_out / "world_map.png").exists(), "the fallback chart is written too", failures)
        check(len(synth_info["regions"]) >= 5, "the fallback covers every region", failures)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    if failures:
        print("RESULT: FAIL (%d)" % len(failures))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
