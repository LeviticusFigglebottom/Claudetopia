"""Writers for game/world/generated/ (docs/CONTRACTS.md section 6).

Everything here is a build artifact: binary maps at the full grid, JSON for splines, POIs and
cells, plus a small low-resolution copy of heights, regions, water and water level that the
runtime uses for queries without touching Terrain3D.
"""
from __future__ import annotations

import json
import os

import numpy as np

from .grid import Grid
from .noise import downsample

RUNTIME_N = 1024


def _write(path: str, data: bytes) -> int:
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def pack_control(base: np.ndarray, overlay: np.ndarray, blend: np.ndarray, nav: np.ndarray | None = None,
                 hole: np.ndarray | None = None) -> np.ndarray:
    """Terrain3D's packed control word (see its docs/controlmap_format.md).

    base id  bits 32-28, overlay id 27-23, blend 22-15, uv angle 14-11, uv scale 10-8,
    hole bit 3, navigation bit 2, autoshader bit 1. Packing it here (rather than in GDScript,
    a pixel at a time) is the difference between a second and several minutes on a 4096 map.
    """
    c = ((base.astype(np.uint32) & 0x1F) << 27) \
        | ((overlay.astype(np.uint32) & 0x1F) << 22) \
        | ((blend.astype(np.uint32) & 0xFF) << 14)
    if nav is not None:
        c |= (nav.astype(np.uint32) & 1) << 1
    if hole is not None:
        c |= (hole.astype(np.uint32) & 1) << 2
    return c.astype("<u4")


def write_maps(out_dir: str, grid: Grid, H: np.ndarray, region_mask: np.ndarray, base: np.ndarray,
               overlay: np.ndarray, blend: np.ndarray, colour: np.ndarray, water: np.ndarray,
               flow: np.ndarray, nav: np.ndarray | None = None, terrain: bool = True,
               textures: bool = True) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    sizes = {}
    if terrain:
        sizes["heights.r32"] = _write(os.path.join(out_dir, "heights.r32"), np.ascontiguousarray(H, dtype="<f4").tobytes())
        sizes["region_mask.u8"] = _write(os.path.join(out_dir, "region_mask.u8"), np.ascontiguousarray(region_mask, dtype=np.uint8).tobytes())
        sizes["water_mask.u8"] = _write(os.path.join(out_dir, "water_mask.u8"), np.ascontiguousarray(water, dtype=np.uint8).tobytes())
        sizes["flow.rg8"] = _write(os.path.join(out_dir, "flow.rg8"), np.ascontiguousarray(flow, dtype=np.uint8).tobytes())
    if textures:
        sizes["texture_base.u8"] = _write(os.path.join(out_dir, "texture_base.u8"), np.ascontiguousarray(base, dtype=np.uint8).tobytes())
        sizes["texture_overlay.u8"] = _write(os.path.join(out_dir, "texture_overlay.u8"), np.ascontiguousarray(overlay, dtype=np.uint8).tobytes())
        sizes["texture_blend.u8"] = _write(os.path.join(out_dir, "texture_blend.u8"), np.ascontiguousarray(blend, dtype=np.uint8).tobytes())
        sizes["color.rgba8"] = _write(os.path.join(out_dir, "color.rgba8"), np.ascontiguousarray(colour, dtype=np.uint8).tobytes())
        # control.u32: the same three maps packed the way Terrain3D stores them, so the
        # in-engine import tool can hand the bytes to an Image without touching a pixel.
        ctrl = pack_control(base, overlay, blend, nav)
        sizes["control.u32"] = _write(os.path.join(out_dir, "control.u32"), np.ascontiguousarray(ctrl).tobytes())
    return sizes


def write_runtime(out_dir: str, grid: Grid, H: np.ndarray, region_mask: np.ndarray, water: np.ndarray,
                  water_level: np.ndarray) -> dict:
    """Low-resolution copies for TerrainProvider queries (height, region, water) without Terrain3D."""
    n = min(RUNTIME_N, grid.n)
    d = os.path.join(out_dir, "runtime")
    os.makedirs(d, exist_ok=True)
    f = grid.n // n
    h_lo = downsample(H.astype(np.float32), n)
    r_lo = region_mask[::f, ::f].copy()
    w_lo = water[::f, ::f].copy()
    # The water level map is *filled*: every texel carries the level of the nearest water, so
    # the runtime water surface mesh can interpolate it without hitting a -1000 hole at the shore.
    # Visibility is the mask's job, not the level's.
    from scipy import ndimage
    wet = water > 0
    if wet.any():
        idx = ndimage.distance_transform_edt(~wet, return_distances=False, return_indices=True)
        filled = water_level[idx[0], idx[1]].astype(np.float32)
    else:
        filled = np.zeros_like(water_level, dtype=np.float32)
    lvl_lo = filled[::f, ::f].copy()
    _write(os.path.join(d, "heights_%d.r32" % n), np.ascontiguousarray(h_lo, dtype="<f4").tobytes())
    _write(os.path.join(d, "regions_%d.u8" % n), np.ascontiguousarray(r_lo, dtype=np.uint8).tobytes())
    _write(os.path.join(d, "water_%d.u8" % n), np.ascontiguousarray(w_lo, dtype=np.uint8).tobytes())
    _write(os.path.join(d, "water_level_%d.r32" % n), np.ascontiguousarray(lvl_lo, dtype="<f4").tobytes())
    return {"grid": n, "heights": "runtime/heights_%d.r32" % n, "regions": "runtime/regions_%d.u8" % n,
            "water": "runtime/water_%d.u8" % n, "water_level": "runtime/water_level_%d.r32" % n}


def write_splines(out_dir: str, rivers: list, roads: list) -> None:
    riv = [{"id": r.id, "points": [[round(float(x), 1), round(float(z), 1)] for x, z in r.points],
            "width_m": round(float(np.mean(r.width)), 2),
            "width_from_m": round(float(r.width[0]), 2), "width_to_m": round(float(r.width[-1]), 2),
            "surface_from_m": round(float(r.surface[0]), 2), "surface_to_m": round(float(r.surface[-1]), 2)}
           for r in rivers]
    rds = [{"id": r.id, "points": [[round(float(x), 1), round(float(z), 1)] for x, z in r.points],
            "width_m": round(float(r.width), 2)} for r in roads]
    with open(os.path.join(out_dir, "rivers.json"), "w", encoding="utf-8") as f:
        json.dump(riv, f, indent=1)
    with open(os.path.join(out_dir, "roads.json"), "w", encoding="utf-8") as f:
        json.dump(rds, f, indent=1)


def write_pois(out_dir: str, pois: list) -> None:
    with open(os.path.join(out_dir, "pois.json"), "w", encoding="utf-8") as f:
        json.dump(pois, f, indent=1)


def write_cells(out_dir: str, grid: Grid, buckets: dict, cell_regions: dict, scenes_by_cell: dict,
                spawns_by_cell: dict | None = None) -> int:
    d = os.path.join(out_dir, "cells")
    os.makedirs(d, exist_ok=True)
    written = 0
    for cz in range(grid.cells):
        for cx in range(grid.cells):
            key = (cx, cz)
            data = {
                "cell": [cx, cz],
                "region": cell_regions.get(key, ""),
                "instances": buckets.get(key, {}),
                "scenes": scenes_by_cell.get(key, []),
                "spawns": (spawns_by_cell or {}).get(key, []),
                "lights": [],
            }
            with open(os.path.join(d, "%d_%d.json" % (cx, cz)), "w", encoding="utf-8") as f:
                json.dump(data, f, separators=(",", ":"))
            written += 1
    return written


def write_manifest(out_dir: str, grid: Grid, seed: int, regions: list, runtime: dict, extra: dict) -> None:
    manifest = {
        "seed": int(seed),
        "size_m": int(grid.size_m),
        "spacing_m": grid.spacing,
        "origin": [grid.x0, grid.z0],
        "grid": grid.n,
        "sea_level": 0,
        "lake_level": 8,
        "regions": [r.id for r in regions],
        "cell_size_m": int(grid.cell_size_m),
        "cells": [grid.cells, grid.cells],
        "runtime": runtime,
    }
    manifest.update(extra)
    with open(os.path.join(out_dir, "world_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
