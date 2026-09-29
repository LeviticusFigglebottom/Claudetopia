"""The pieces of a line (a hedge, a drystone wall, a post-and-rail) set on the ground along their whole
length, and no stub of one left standing alone.

A line piece was set down at the ground under its middle. A drystone wall module is 2.4 m long;
laid across a 1 in 2 bank, its downhill end stood 0.6 m over the ground. The 4096 shots for playtest 6
("fences along roads that seem randomly placed, missing or clipping") had a Skerrow wall piece
standing out over a brow. A boundary broken by the slope and water checks also left runs of one or
two pieces in open ground. `seat` puts each piece's middle at the lower of the ground under its two
ends, less LINE_SINK_M, so both ends are in the ground. It then takes out every piece with fewer than
STUB_NEIGHBOURS of its own kind within STUB_REACH_M.

A level piece down a steep bank has its uphill end deep in the ground: of w4096c's walls 1,728 had
that end buried by more than a metre of their 1.42 m, and the steepest by 1.89 m. A piece now
follows the ground along its run, pitched with the slope (the row's lean pair, toward its low end)
up to PITCH_MAX_DEG for its kind and never more, so nothing stands up on end. Where the ground is
steeper than that, the piece is stepped: split into up to SPLIT_MAX shorter pieces (the ninth
field's stretch along its run), each set down on its own stretch of ground, so no piece's uphill
end is buried more than STEP_MAX_M past its sink. A rail module is not split: in the near ring
Wayside builds post-and-rail from the rows as upright posts with rails following the ground, and a
split would stand posts every 0.8 m.
"""
from __future__ import annotations

import math
import os

import numpy as np

from .grid import Grid, sample_bilinear
from .rows import Rows

## a line's kinds, and each piece's half-length at scale one (its run lies along its own +X)
HALF_M = {"drystone_wall_end": 0.45, "drystone_wall": 1.2, "hedge_segment": 1.05, "fence_post_rail": 1.18}
LINE_SINK_M = 0.08
STUB_REACH_M = 5.5
STUB_NEIGHBOURS = 2
STUB_PASSES = 6
## how far a piece is pitched along its run, at most, and how far past its sink its uphill end may
## be buried before it is stepped: split into up to SPLIT_MAX pieces (none for a rail or a wall end)
PITCH_MAX_DEG = {"drystone_wall_end": 20.0, "drystone_wall": 20.0, "hedge_segment": 24.0, "fence_post_rail": 24.0}
STEP_MAX_M = 0.3
SPLIT_MAX = {"drystone_wall_end": 1, "drystone_wall": 3, "hedge_segment": 3, "fence_post_rail": 1}
PITCH_MIN_DEG = 0.25
## a piece whose uphill end is still buried this far once pitched and stepped stands on a crag
CLIFF_BURIED_M = 0.8


def _kind(asset: str) -> str | None:
    name = os.path.basename(asset)
    for k in HALF_M:                        # (the wall's end before the wall: it is its prefix)
        if "_" + k + "_" in name:
            return k
    return None


def _ends(H: np.ndarray, grid: Grid, x, z, ux, uz, h) -> tuple:
    """Ground at a piece's + end, its - end and its middle."""
    return (sample_bilinear(H, grid, x + ux * h, z + uz * h), sample_bilinear(H, grid, x - ux * h, z - uz * h),
            sample_bilinear(H, grid, x, z))


def _pitched(e_plus, e_minus, mid, h, cap_deg: float) -> tuple:
    """(y at the piece's pivot, its pitch in degrees, +1 where its + end is the low one else -1,
    how far past its sink its uphill end is buried):
    pitched with the ground along its run up to `cap_deg`, and set down so both ends and the middle
    are in the ground by LINE_SINK_M."""
    drop = e_minus - e_plus                         # > 0: the + end is the low one
    tan = np.minimum(np.abs(drop) / np.maximum(2.0 * h, 1e-6), math.tan(math.radians(cap_deg)))
    low, high = np.minimum(e_plus, e_minus), np.maximum(e_plus, e_minus)
    y = np.minimum(np.minimum(low + h * tan, high - h * tan), mid) - LINE_SINK_M
    # what its uphill end is buried past its sink
    buried = high - (y + LINE_SINK_M) - h * tan
    return y, np.degrees(np.arctan(tan)), np.where(drop > 0.0, 1.0, -1.0), buried


def _stubs(buckets: dict) -> int:
    """Takes out every line piece with fewer than STUB_NEIGHBOURS of its own family within
    STUB_REACH_M; returns how many."""
    from scipy.spatial import cKDTree

    where: dict = {}
    for key, by_asset in buckets.items():
        for asset, rows in by_asset.items():
            kind = _kind(asset)
            if kind is None or isinstance(rows, Rows) or not rows:
                continue
            family = "drystone_wall" if kind.startswith("drystone_wall") else kind
            pts = np.array([(float(r[0]), float(r[2])) for r in rows], dtype=np.float64)
            where.setdefault(family, []).append((key, asset, pts))
    gone = 0
    for family, parts in where.items():
        pts = np.concatenate([p for _, _, p in parts])
        tree = cKDTree(pts)
        near = np.array([len(n) - 1 for n in tree.query_ball_point(pts, STUB_REACH_M)])
        at = 0
        for key, asset, p in parts:
            keep = near[at:at + p.shape[0]] >= STUB_NEIGHBOURS
            at += p.shape[0]
            if keep.all():
                continue
            gone += int((~keep).sum())
            rows = buckets[key][asset]
            buckets[key][asset] = [r for r, k in zip(rows, keep) if k]
            if not buckets[key][asset]:
                del buckets[key][asset]
    return gone


def seat(buckets: dict, grid: Grid, H: np.ndarray) -> dict:
    """In place: the stubs taken out, then every line piece in `buckets` pitched with the ground
    along its run (up to its kind's cap) and set down on it at both its ends, stepped into shorter
    pieces where the ground is steeper than the cap; a piece (or a step of one) still buried more
    than CLIFF_BURIED_M is on a crag, where nobody walls, and is taken out. Returns {"pieces",
    "stubs", "pitched", "split", "on_cliffs", "steepest_pitch_deg"}."""
    # taking out a stub can leave its neighbour one: again until none is left (w4096c's one pass
    # left 737)
    gone, passes = _stubs(buckets), 1
    while passes < STUB_PASSES:
        more = _stubs(buckets)
        gone += more
        passes += 1
        if more == 0:
            break
    counts = {"pieces": 0, "stubs": gone, "pitched": 0, "split": 0, "on_cliffs": 0,
              "steepest_pitch_deg": 0.0}
    moved: list = []                                # (key, asset, row) for a piece stepped into another cell
    for key, by_asset in buckets.items():
        for asset, rows in by_asset.items():
            kind = _kind(asset)
            if kind is None or isinstance(rows, Rows) or not rows:
                continue
            # a piece's length is its run's own scale: the ninth field's x where a run was laid
            # stretched to its line (hedges._lay_runs), else its uniform scale
            arr = np.array([(float(r[0]), float(r[2]), float(r[3]),
                             float(r[8][0]) if len(r) > 8 else float(r[4])) for r in rows], dtype=np.float64)
            a = np.radians(arr[:, 2])
            ux, uz = np.cos(a), -np.sin(a)          # the piece's own +X on the ground
            h = HALF_M[kind] * arr[:, 3]
            cap = PITCH_MAX_DEG[kind]
            e_plus, e_minus, mid = _ends(H, grid, arr[:, 0], arr[:, 1], ux, uz, h)
            y, pitch, sign, buried = _pitched(e_plus, e_minus, mid, h, cap)
            # stepped where the uphill end is buried too deep once pitched
            n = np.clip(np.ceil(buried / STEP_MAX_M - 1e-9), 1, SPLIT_MAX[kind]).astype(int)
            out: list = []
            for i, r in enumerate(rows):
                if n[i] == 1:
                    if buried[i] > CLIFF_BURIED_M:
                        counts["on_cliffs"] += 1
                        continue
                    out.append(_row(r, float(y[i]), float(pitch[i]), float(sign[i]), ux[i], uz[i], None))
                    continue
                counts["split"] += 1
                k = int(n[i])
                t = (np.arange(k) + 0.5) / k * 2.0 - 1.0           # the pieces' middles along the run
                sx, sz = arr[i, 0] + ux[i] * h[i] * t, arr[i, 1] + uz[i] * h[i] * t
                hk = np.full(k, h[i] / k)
                ep, em, md = _ends(H, grid, sx, sz, ux[i], uz[i], hk)
                yk, pk, gk, bk = _pitched(ep, em, md, hk, cap)
                for j in range(k):
                    if bk[j] > CLIFF_BURIED_M:
                        counts["on_cliffs"] += 1
                        continue
                    piece = list(r)
                    piece[0], piece[2] = round(float(sx[j]), 2), round(float(sz[j]), 2)
                    got = _row(piece, float(yk[j]), float(pk[j]), float(gk[j]), ux[i], uz[i], 1.0 / k)
                    home = grid.written_cell(got[0], got[2])
                    if home != tuple(key):
                        moved.append((home, asset, got))
                    else:
                        out.append(got)
            rows[:] = out
            counts["pieces"] += len(out)
            counts["pitched"] += int((pitch >= PITCH_MIN_DEG).sum())
            counts["steepest_pitch_deg"] = max(counts["steepest_pitch_deg"], round(float(pitch.max()), 1))
    for home, asset, row in moved:
        buckets.setdefault(home, {}).setdefault(asset, []).append(row)
        counts["pieces"] += 1
    return counts


def _row(r: list, y: float, pitch: float, sign: float, ux: float, uz: float, along: float | None) -> list:
    """A line piece's row set down at `y`, pitched `pitch` toward its low end (`sign` along its
    +X), and stretched `along` its run where it is one of a stepped piece's parts."""
    out = list(r[:6])
    out[1] = round(y, 2)
    stretched = len(r) > 8
    if pitch < PITCH_MIN_DEG and along is None and not stretched:
        return out
    toward = math.degrees(math.atan2(sign * uz, sign * ux)) if pitch >= PITCH_MIN_DEG else 0.0
    out += [round(pitch, 2) if pitch >= PITCH_MIN_DEG else 0.0, round(toward, 1)]
    if along is not None or stretched:
        s = float(r[4])
        sx, sy, sz = (float(v) for v in r[8]) if stretched else (s, s, s)
        out.append([round(sx * (along if along is not None else 1.0), 3), sy, sz])
    return out
