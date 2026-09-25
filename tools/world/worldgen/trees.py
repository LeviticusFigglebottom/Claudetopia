"""Every tree is set into the ground at its whole foot, not at its pivot.

A tree was set down with its pivot (the middle of its trunk's foot) on the ground, at the ground's
height there. The roots and the flare reach out a metre or two past the trunk, five for the Briarwold's
giant oaks. On a slope, their downhill side stood over air, and the hedges, orchards and roadside
took the height of the nearest texel, not the ground under the pivot. Playtest 6 (1.webp) had a big
tree standing on the spikes of its roots with its trunk's foot clear of the soil.

`seat` goes over every tree in the buckets once they are all placed. It takes each tree's foot, the
points of it under 0.35 m that tools/world/tree_contacts.py read off the forge's mesh, turns them by
the row's yaw and scales them by its scale. It then sets the tree's pivot so that the highest of
them, measured over the ground where it stands, is SEAT_UNDER_M under that ground. The sink below
the ground at the pivot is capped at SEAT_CAP_M plus SEAT_CAP_PER_M of the tree's height, so no
tree on a crag is swallowed to its crown.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from .grid import Grid, sample_bilinear
from .rows import Rows

TABLE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tree_contacts.json")
SEAT_UNDER_M = 0.05
SEAT_CAP_M = 0.45
SEAT_CAP_PER_M = 0.05
## what is under a pivot on level ground: the forge grows each tree's foot a little into it
SEAT_MIN_SINK_M = 0.0


def load_table(path: str = TABLE) -> dict:
    """{asset name: (points [k, 3] at scale one, height m)}."""
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f).get("trees", {})
    return {k: (np.asarray(v["contacts"], dtype=np.float64).reshape(-1, 3), float(v.get("height_m", 5.0)))
            for k, v in raw.items() if v.get("contacts")}


def sink_for(H: np.ndarray, grid: Grid, x: np.ndarray, z: np.ndarray, yaw_deg: np.ndarray, scale: np.ndarray,
             pts: np.ndarray, height: float) -> tuple:
    """(pivot heights, sink under the ground at the pivot) for trees of one asset at (x, z)."""
    a = np.radians(yaw_deg.astype(np.float64))[:, None]
    c, s = np.cos(a), np.sin(a)
    px, py, pz = pts[None, :, 0], pts[None, :, 1], pts[None, :, 2]
    sc = scale.astype(np.float64)[:, None]
    # Godot's Basis(UP, a): x' = x cos a + z sin a, z' = -x sin a + z cos a
    wx = x[:, None] + sc * (px * c + pz * s)
    wz = z[:, None] + sc * (-px * s + pz * c)
    ground = sample_bilinear(H, grid, wx.ravel(), wz.ravel()).reshape(wx.shape)
    g0 = sample_bilinear(H, grid, x, z)
    # each foot point's height is pivot + scale * y: the pivot that puts the highest of them
    # SEAT_UNDER_M under its own ground
    want = np.min(ground - sc * py, axis=1) - SEAT_UNDER_M
    cap = SEAT_CAP_M + SEAT_CAP_PER_M * height * scale.astype(np.float64)
    y = np.maximum(np.minimum(want, g0 - SEAT_MIN_SINK_M), g0 - cap)
    return y.astype(np.float32), (g0 - y).astype(np.float32)


def seat(buckets: dict, grid: Grid, H: np.ndarray, table: dict | None = None) -> dict:
    """Set every tree in `buckets` into the ground at its whole foot (in place). Returns
    {"trees", "sunk_over_0_5_m", "capped"}."""
    table = load_table() if table is None else table
    counts = {"trees": 0, "sunk_over_0_5_m": 0, "capped": 0}
    for by_asset in buckets.values():
        for asset, rows in by_asset.items():
            if "/trees/" not in asset:
                continue
            name = os.path.splitext(os.path.basename(asset))[0]
            got = table.get(name)
            if got is None or not len(rows):
                continue
            pts, height = got
            if isinstance(rows, Rows):
                chunks = [c for c in rows._chunks]
            else:
                chunks = [rows]
            for c in chunks:
                if isinstance(c, list):
                    if not c:
                        continue
                    arr = np.array([(float(r[0]), float(r[2]), float(r[3]), float(r[4])) for r in c], dtype=np.float64)
                    y, sink = sink_for(H, grid, arr[:, 0], arr[:, 1], arr[:, 2], arr[:, 3], pts, height)
                    for r, v in zip(c, y.tolist()):
                        r[1] = round(v, 2)
                else:
                    y, sink = sink_for(H, grid, c["x"].astype(np.float64), c["z"].astype(np.float64), c["yaw"], c["scale"],
                                       pts, height)
                    c["y"] = y
                counts["trees"] += int(sink.size)
                counts["sunk_over_0_5_m"] += int((sink > 0.5).sum())
                cap = SEAT_CAP_M + SEAT_CAP_PER_M * height
                counts["capped"] += int((sink >= cap * 0.999).sum())
    return counts


def floating(H: np.ndarray, grid: Grid, rows: list, pts: np.ndarray) -> np.ndarray:
    """For rows [x, y, z, yaw, scale, ...] of one tree: how far the highest point of each one's foot
    stands over the ground under it (negative where the whole foot is in the ground)."""
    arr = np.array([(float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in rows], dtype=np.float64)
    a = np.radians(arr[:, 3])[:, None]
    c, s = np.cos(a), np.sin(a)
    sc = arr[:, 4][:, None]
    wx = arr[:, 0][:, None] + sc * (pts[None, :, 0] * c + pts[None, :, 2] * s)
    wz = arr[:, 2][:, None] + sc * (-pts[None, :, 0] * s + pts[None, :, 2] * c)
    ground = sample_bilinear(H, grid, wx.ravel(), wz.ravel()).reshape(wx.shape)
    return np.max(arr[:, 1][:, None] + sc * pts[None, :, 1] - ground, axis=1)
