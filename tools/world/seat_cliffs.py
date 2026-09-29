#!/usr/bin/env python3
"""Seat the cliff face pieces of an installed world's cells in their slopes (worldgen.cliff_seat).

The world build seats each cliff piece as it lays it (crags.cliff_faces). This applies the same
rules to cells already written, so an installed world takes them without a build: every
`*_cliff_face_*` row in game/world/generated/cells/*.json is turned and leaned to lie in the plane
of the ground under it, sized to the face it dresses, and moved along the slope's normal until the
lowest fifth of its front stands SEAT_SHOW_M out of the ground; one that cannot be, or that stands
alone, goes. Each lies in its plane however the ground tilts across it, turned in it by its own
twist (it was yawed about the vertical, which rolled it out of the plane by as much). The proud
crag ledges and sea-cliff beds go back into their hills, level (cliff_seat.settle_ledges). Then
the steep faces still bare more than FILL_GAP_M from rock are filled with smaller pieces of the
region's kit, seated the same way (cliff_seat.fill_gaps; `--no-fill` leaves them), off the roads,
the pads and the water. Only the cells that changed are written, in the build's own JSON. A second
run moves no piece already seated, and adds pieces only where a gap is still left.

It needs the installed ground at full resolution. A build leaves it as heights.r32 (4096 x 4096,
not committed); otherwise dump the Terrain3D regions the game loads:

    DUMP_OUT=/tmp/h godot --headless --path game --audio-driver Dummy -s res://tools_gd/dump_heights.gd
    python3 tools/world/seat_cliffs.py --heights /tmp/h [--dry-run] [--stats before.json]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from worldgen import cliff_seat as CS  # noqa: E402
from worldgen.grid import Grid  # noqa: E402

WORLD = os.path.join(REPO, "game", "world", "generated")
## the assets this reads and writes (every other row in a cell is left as it is)
ROCK = "/rocks/"


def load_heights(path: str, manifest: dict) -> np.ndarray:
    """The installed ground, [z, x] at the manifest's grid: a build's heights.r32, or a directory
    of dump_heights.gd's region files (Terrain3D's regions of 1024 samples, named by location)."""
    n = int(manifest["grid"])
    if os.path.isfile(path):
        return np.fromfile(path, dtype=np.float32).reshape(n, n)
    H = load_regions(path, manifest, ".r32", np.float32)
    if np.isnan(H).any():
        raise SystemExit("seat_cliffs: %d texels of the ground missing from %s" % (int(np.isnan(H).sum()), path))
    return H


## Terrain3D's regions as the game loads them: this many samples a side
REGION_SAMPLES = 1024


def region_files(path: str, manifest: dict, suffix: str) -> list:
    """[(file, i0, j0)]: each of dump_heights.gd's region files with `suffix` in the directory
    `path` (named by the region's location, terrain3d-01_00: x -1, z 0), and where its first sample
    falls in the manifest's grid (row i0, column j0)."""
    spacing = float(manifest.get("spacing_m", 2.0))
    ox, oz = (float(v) for v in manifest["origin"])
    k = REGION_SAMPLES
    out = []
    for f in sorted(glob.glob(os.path.join(path, "terrain3d*" + suffix))):
        m = re.match(r"terrain3d([-_])(\d+)([-_])(\d+)" + re.escape(suffix) + "$", os.path.basename(f))
        if not m:
            continue
        rx = int(m.group(2)) * (-1 if m.group(1) == "-" else 1)
        rz = int(m.group(4)) * (-1 if m.group(3) == "-" else 1)
        out.append((f, int(round((rz * k * spacing - oz) / spacing)), int(round((rx * k * spacing - ox) / spacing))))
    return out


def load_regions(path: str, manifest: dict, suffix: str, dtype, channels: int = 0) -> np.ndarray:
    """A whole-world map [z, x(, channel)] out of dump_heights.gd's region files with `suffix`
    (.r32 heights, .ctl control words, .rgba colour); NaN or 0 where no region covers it."""
    n = int(manifest["grid"])
    k = REGION_SAMPLES
    shape = (n, n, channels) if channels else (n, n)
    A = np.full(shape, np.nan, dtype=dtype) if np.dtype(dtype).kind == "f" else np.zeros(shape, dtype=dtype)
    for f, i0, j0 in region_files(path, manifest, suffix):
        a = np.fromfile(f, dtype=dtype).reshape((k, k, channels) if channels else (k, k))
        ii0, jj0 = max(i0, 0), max(j0, 0)
        ii1, jj1 = min(i0 + k, n), min(j0 + k, n)
        if ii1 > ii0 and jj1 > jj0:
            A[ii0:ii1, jj0:jj1] = a[ii0 - i0:ii1 - i0, jj0 - j0:jj1 - j0]
    return A


def summary(m: dict) -> dict:
    r = m["rows"]
    if not len(r):
        return {"pieces": 0}
    q = lambda a, p: round(float(np.percentile(a, p)), 2)  # noqa: E731
    return {
        "pieces": int(len(r)),
        "front_out_median_m": q(r[:, 0], 50), "front_out_mean_m": round(float(r[:, 0].mean()), 2),
        "front_out_p90_m": q(r[:, 0], 90),
        "worst_tenth_out_median_m": q(r[:, 1], 50), "worst_tenth_out_p90_m": q(r[:, 1], 90),
        "size_over_fit_median": q(r[:, 2], 50), "size_over_fit_p90": q(r[:, 2], 90),
        "too_big_share": round(float((r[:, 2] > 1.0 + 1e-3).mean()), 3),
        "slope_deg_p10": q(r[:, 3], 10), "slope_deg_median": q(r[:, 3], 50), "under_min_slope_share": round(float((r[:, 3] < CS.SEAT_MIN_SLOPE_DEG).mean()), 3),
        "back_shows_m_p90": q(r[:, 4], 90),
        "scale_median": q(r[:, 5], 50), "lean_deg_median": q(r[:, 6], 50),
        "front_shown_share_median": q(r[:, 7], 50), "front_shown_share_p10": q(r[:, 7], 10),
    }


## a piece laid in a gap keeps this far off a road's edge and a settlement's pad
ROAD_CLEAR_M = 4.0
PAD_CLEAR_M = 10.0


def blocked_ground(world: str, manifest: dict, g: Grid, H: np.ndarray) -> np.ndarray:
    """[z, x] bool: where no piece may be laid in a gap: the roads (roads.json) and ROAD_CLEAR_M
    past their edges, the settlements' pads (pois.json) and PAD_CLEAR_M past them, and the water
    (runtime/water, and ground under its level)."""
    from scipy import ndimage

    n = g.n
    lines = np.zeros((n, n), dtype=bool)
    half = 0.0
    with open(os.path.join(world, "roads.json"), "r", encoding="utf-8") as f:
        for road in json.load(f):
            half = max(half, 0.5 * float(road.get("width_m", 4.0)))
            p = np.asarray(road["points"], dtype=np.float64).reshape(-1, 2)
            for a, b in zip(p[:-1], p[1:]):
                k = max(2, int(np.hypot(*(b - a)) / (0.5 * g.spacing)) + 1)
                t = np.linspace(0.0, 1.0, k)[:, None]
                q = a + (b - a) * t
                j, i = g.clamp_index(*g.to_tex(q[:, 0], q[:, 1]))
                lines[i, j] = True
    out = ndimage.distance_transform_edt(~lines) * g.spacing <= half + ROAD_CLEAR_M
    del lines
    X, Z = g.mesh(np.float32)
    with open(os.path.join(world, "pois.json"), "r", encoding="utf-8") as f:
        for poi in json.load(f):
            r = float(poi.get("radius_flat_m", 0.0) or 0.0)
            if r <= 0.0:
                continue
            x, z = float(poi["pos"][0]), float(poi["pos"][2])
            reach = r + PAD_CLEAR_M
            j0, i0 = g.clamp_index(*g.to_tex(x - reach, z - reach))
            j1, i1 = g.clamp_index(*g.to_tex(x + reach, z + reach))
            sub = (X[:, j0:j1 + 1] - x) ** 2 + (Z[i0:i1 + 1, :] - z) ** 2 <= reach * reach
            out[i0:i1 + 1, j0:j1 + 1] |= sub
    rt = manifest.get("runtime", {})
    if rt.get("water") and rt.get("water_level"):
        k = int(rt.get("grid", 1024))
        wm = np.fromfile(os.path.join(world, rt["water"]), dtype=np.uint8).reshape(k, k)
        wl = np.fromfile(os.path.join(world, rt["water_level"]), dtype=np.float32).reshape(k, k)
        f = n // k
        wet = np.kron(wm > 0, np.ones((f, f), dtype=bool))
        level = np.kron(wl, np.ones((f, f), dtype=np.float32))
        out |= ndimage.binary_dilation(wet, iterations=2) | (H < level + 0.5)
    return out


def drop_off_ground(buckets: dict, H: np.ndarray, g: Grid) -> int:
    """Any cliff piece floating or buried (worldgen.offground's net, which the build runs after
    every pass) taken out: the ones laid in gaps are checked as the build would."""
    from worldgen import offground as OFF
    from worldgen.cells import asset_bounds

    gone = 0
    for by in buckets.values():
        for asset in list(by):
            if CS.FACE_PART not in asset or not by[asset]:
                continue
            rows = by[asset]
            half, height = asset_bounds(asset, REPO)
            fl, bu = OFF.off_ground(H, g, [r[0] for r in rows], [r[1] for r in rows], [r[2] for r in rows],
                                    [r[4] for r in rows], half, height)
            bad = fl | bu
            if bad.any():
                gone += int(bad.sum())
                by[asset] = [r for r, b in zip(rows, bad) if not b]
    return gone


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--world", default=WORLD)
    ap.add_argument("--heights", default=None, help="heights.r32, or a directory of dump_heights.gd's region files")
    ap.add_argument("--dry-run", action="store_true", help="write nothing")
    ap.add_argument("--measure", action="store_true", help="only measure the pieces as they stand")
    ap.add_argument("--stats", help="write the before and after measures here (JSON)")
    ap.add_argument("--no-fill", action="store_true", help="seat what is there, add no pieces to the bare faces")
    args = ap.parse_args()

    with open(os.path.join(args.world, "world_manifest.json"), "r", encoding="utf-8") as f:
        manifest = json.load(f)
    heights = args.heights or os.path.join(args.world, "heights.r32")
    if not os.path.exists(heights):
        raise SystemExit("seat_cliffs: no %s; dump the installed ground with tools_gd/dump_heights.gd (see --help)" % heights)
    H = load_heights(heights, manifest)
    g = Grid(float(manifest["size_m"]), int(manifest["grid"]), float(manifest.get("cell_size_m", 256.0)))

    # only the rock is held (the whole world's rows, some six million, were more than a shared
    # machine could keep beside the maps); the rest of a cell is read again when it is written
    cells: dict = {}
    buckets: dict = {}
    for path in sorted(glob.glob(os.path.join(args.world, "cells", "*.json"))):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        key = tuple(int(v) for v in data["cell"])
        cells[key] = path
        buckets[key] = {a: rows for a, rows in data["instances"].items() if ROCK in a}
        del data
    before = summary(CS.measure(buckets, H, g, REPO))
    Hs_grad = CS.smoothed_grad(H, g)
    steep = CS.face_mask(H, g, Hs_grad)
    before["cover"] = CS.gap_stats(CS.cover_map(buckets, g, REPO), steep, g)
    print("[seat_cliffs] before: %s" % json.dumps(before))
    if args.measure:
        return 0
    got = CS.settle(buckets, H, g, REPO)
    got.pop("feet", None)
    print("[seat_cliffs] %s" % json.dumps(got))
    got["ledges"] = CS.settle_ledges(buckets, H, g, REPO)
    print("[seat_cliffs] ledges: %s" % json.dumps(got["ledges"]))
    if not args.no_fill:
        blocked = blocked_ground(args.world, manifest, g, H)
        filled = CS.fill_gaps(buckets, H, g, REPO, int(manifest.get("seed", 0)),
                              clear=lambda x, z: not blocked[g.clamp_index(*g.to_tex(x, z))[::-1]],
                              steep=steep)
        del filled["cover"]
        filled["off_ground"] = drop_off_ground(buckets, H, g)
        got["fill"] = filled
        print("[seat_cliffs] fill: %s" % json.dumps(filled))
    C = CS.cover_map(buckets, g, REPO)
    after = summary(CS.measure(buckets, H, g, REPO))
    after["cover"] = CS.gap_stats(C, steep, g)
    print("[seat_cliffs] after: %s" % json.dumps(after))
    if args.stats:
        with open(args.stats, "w", encoding="utf-8") as f:
            json.dump({"before": before, "after": after, "settle": got}, f, indent=1)
    stray = [k for k in buckets if k not in cells]
    if stray:
        raise SystemExit("seat_cliffs: pieces moved into cells the world does not have: %s" % stray)
    if args.dry_run:
        return 0
    written = 0
    for key, path in cells.items():
        with open(path, "r", encoding="utf-8") as f:
            was = f.read()
        data = json.loads(was)
        rock = buckets.get(key, {})
        inst = {}
        for a, rows in data["instances"].items():
            if ROCK in a:
                rows = rock.get(a, [])
            if rows:
                inst[a] = rows
        for a, rows in rock.items():
            if a not in inst and rows:
                inst[a] = rows
        data["instances"] = inst
        now = json.dumps(data, separators=(",", ":"))
        if now != was:
            with open(path, "w", encoding="utf-8") as f:
                f.write(now)
            written += 1
    print("[seat_cliffs] %d cells written" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
