"""Nothing grows or lies inside a landmark.

A place's pad is cleared of scatter to its flat radius, but a landmark can be far bigger than its
pad: the Drowned Nave's ruin runs 65 m from its tower and 30 m across, and the alders and willows
at 25-50 m from the place stood inside its walls. Every scene the forge built (a landmark: its
meta has bounds) takes the trees, rocks and made things out of its own footprint, the meta's box
turned by the scene's yaw as WorldStreamer turns it, with a margin for a tree's crown.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

## what a landmark clears, and how far past its box: a tree's crown overhangs its trunk
CLEAR = (("/trees/", 2.5), ("/rocks/", 0.5), ("/props/", 0.5))


def _bounds(scene: str, repo_root: str):
    """(min, max) of a forge scene's box, Godot axes, or None where it has no meta."""
    if not scene.startswith("res://") or not scene.endswith(".glb"):
        return None
    path = os.path.join(repo_root, os.path.splitext(scene.replace("res://", "game/", 1))[0] + ".meta.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            b = json.load(f).get("bounds") or {}
    except (OSError, ValueError):
        return None
    if "min" not in b or "max" not in b:
        return None
    return np.asarray(b["min"], dtype=np.float64), np.asarray(b["max"], dtype=np.float64)


def inside(xz: np.ndarray, pos, yaw_deg: float, lo, hi, margin: float) -> np.ndarray:
    """Which of the world points `xz` [n, 2] stand within `margin` of a scene's box (`lo`, `hi`,
    its local Godot axes) with the scene at `pos` turned `yaw_deg` about +Y."""
    a = math.radians(float(yaw_deg))
    c, s = math.cos(a), math.sin(a)
    dx = xz[:, 0] - float(pos[0])
    dz = xz[:, 1] - float(pos[2])
    lx = dx * c - dz * s
    lz = dx * s + dz * c
    return (lx >= lo[0] - margin) & (lx <= hi[0] + margin) & (lz >= lo[2] - margin) & (lz <= hi[2] + margin)


def clear(buckets: dict, scenes: list, grid, repo_root: str) -> dict:
    """Take out of `buckets` ({(cx, cz): {asset: rows}}) whatever CLEAR names inside a forge scene's
    footprint (`scenes`: entries with scene, pos, yaw). Returns {kind: count}."""
    from .rows import Rows

    gone: dict = {}
    for sc in scenes:
        box = _bounds(str(sc.get("scene", "")), repo_root)
        if box is None:
            continue
        lo, hi = box
        reach = float(np.hypot(max(abs(lo[0]), abs(hi[0])), max(abs(lo[2]), abs(hi[2])))) + max(m for _p, m in CLEAR)
        x, z = float(sc["pos"][0]), float(sc["pos"][2])
        c0x, c0z = grid.cell_of(np.array([x - reach]), np.array([z - reach]))
        c1x, c1z = grid.cell_of(np.array([x + reach]), np.array([z + reach]))
        for cx in range(int(c0x[0]), int(c1x[0]) + 1):
            for cz in range(int(c0z[0]), int(c1z[0]) + 1):
                by = buckets.get((cx, cz))
                if not by:
                    continue
                for asset in list(by):
                    margin = next((m for p, m in CLEAR if p in asset), None)
                    if margin is None:
                        continue
                    rows = by[asset]
                    xz = rows.xz() if isinstance(rows, Rows) else \
                        np.array([(float(r[0]), float(r[2])) for r in rows], dtype=np.float64).reshape(-1, 2)
                    if not len(xz):
                        continue
                    hit = inside(xz, sc["pos"], float(sc.get("yaw", 0.0)), lo, hi, margin)
                    if not hit.any():
                        continue
                    kind = next(p for p, _m in CLEAR if p in asset).strip("/")
                    gone[kind] = gone.get(kind, 0) + int(hit.sum())
                    if isinstance(rows, Rows):
                        rows.keep(~hit)
                        if not len(rows):
                            del by[asset]
                        continue
                    keep = [r for r, h in zip(rows, hit) if not h]
                    if keep:
                        by[asset] = keep
                    else:
                        del by[asset]
    return gone
