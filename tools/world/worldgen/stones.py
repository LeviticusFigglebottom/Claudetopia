"""Standing stones, placed by hand rather than by density.

The whole point of a standing stone is that a person put it there. Scattered at so many per
hectare it is a rock; set in a ring, or in a pair flanking a road where it climbs a ridge, or
alone on a skyline, it is a thing somebody meant. So these are a small number of deliberate
groups per region, and there is no rule for them in scatter_rules.json on purpose.

Three kinds of setting, all of which read from a distance:

* a ring at the Standing Moot, which is what that place is
* pairs flanking a road at the point where it crosses the highest ground on its way
* single stones on local skylines, spaced far enough apart that each one is an event

They come out in the same shape as scattered instances, so the streamer draws them in the
same MultiMesh as everything else and nothing downstream needs to know they were special.
"""
from __future__ import annotations

import math
import os

import numpy as np

from .cells import asset_buried
from .grid import Grid, sample_bilinear

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def _assets(index: dict, region_short: str) -> list:
    """The standing stones the forge built for this region, in path form."""
    rocks = index.get("rocks", {})
    out = [path for name, path in sorted(rocks.items())
           if name.startswith(region_short + "_standing_stone")]
    return out


def _put(out: dict, grid: Grid, H: np.ndarray, x: float, z: float, yaw: float, scale: float,
         asset: str, tint) -> None:
    # set down by the stub the forge ran on under its ground line (`buried_m`, as PoiKit.place does)
    y = float(sample_bilinear(H, grid, np.array([x], dtype=np.float32),
                              np.array([z], dtype=np.float32))[0]) - asset_buried(asset, REPO) * scale
    key = grid.written_cell(x, z)
    out.setdefault(key, {}).setdefault(asset, []).append(
        [round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), round(scale, 3), tint])


def place(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
          road_d: np.ndarray, pad_mask: np.ndarray, regions: list, places: list, roads: list,
          index: dict, seed: int, tint: str = "#ffffff") -> dict:
    """Returns {(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint], ...]}}."""
    out: dict = {}
    rng = np.random.default_rng(np.random.SeedSequence([seed, 4242]))
    by_short = {p["id"].split("/")[-1]: p for p in places}
    n = grid.n

    def standable(x: float, z: float) -> bool:
        j, i = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
        j, i = int(np.clip(j[0], 0, n - 1)), int(np.clip(i[0], 0, n - 1))
        return bool(water[i, j] == 0 and pad_mask[i, j] == 0 and slope[i, j] < 0.5)

    for region in regions:
        assets = _assets(index, region.art_short)
        if not assets:
            continue
        mine = owner == region.index

        def here(p, region=region) -> bool:
            """Whether a place stands in this province (a region may have several)."""
            j, i = grid.to_tex(np.array([float(p["position"][0])]), np.array([float(p["position"][1])]))
            j, i = int(np.clip(j[0], 0, n - 1)), int(np.clip(i[0], 0, n - 1))
            return int(owner[i, j]) == region.index

        # --- the ring, where a place is a stone circle ------------------------------------
        for short, count, radius in (("standing_moot", 11, 21.0),):
            p = by_short.get(short)
            if p is None or p.get("region", "").split("/")[-1] != region.short or not here(p):
                continue
            cx, cz = float(p["position"][0]), float(p["position"][1])
            start = float(rng.uniform(0.0, 2.0 * math.pi))
            for k in range(count):
                a = start + 2.0 * math.pi * k / count + float(rng.normal(0.0, 0.035))
                r = radius * float(rng.uniform(0.95, 1.06))
                x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
                if not standable(x, z):
                    continue
                # every stone faces the centre, which is what makes a ring read as a ring
                yaw = math.degrees(math.atan2(cx - x, cz - z)) + float(rng.normal(0.0, 6.0))
                _put(out, grid, H, x, z, yaw, float(rng.uniform(0.9, 1.35)),
                     assets[int(rng.integers(0, len(assets)))], tint)

        # --- pairs flanking a road where it crosses the high ground -----------------------
        for road in roads:
            pts = np.asarray(road.points, dtype=np.float64)
            if pts.shape[0] < 12:
                continue
            xs = pts[:, 0].astype(np.float32)
            zs = pts[:, 1].astype(np.float32)
            j, i = grid.to_tex(xs, zs)
            j = np.clip(j, 0, n - 1).astype(np.int32)
            i = np.clip(i, 0, n - 1).astype(np.int32)
            if not mine[i, j].any():
                continue
            hs = np.where(mine[i, j], H[i, j], -1e9)
            k = int(np.argmax(hs))
            if hs[k] < -1e8 or k < 2 or k > pts.shape[0] - 3:
                continue
            x0, z0 = float(pts[k][0]), float(pts[k][1])
            d = pts[k + 1] - pts[k - 1]
            nrm = float(np.hypot(d[0], d[1]))
            if nrm < 1e-3:
                continue
            px, pz = -float(d[1]) / nrm, float(d[0]) / nrm
            for side in (-1.0, 1.0):
                off = 7.0 + float(rng.uniform(0.0, 2.5))
                x, z = x0 + px * off * side, z0 + pz * off * side
                if not standable(x, z):
                    continue
                # square to the road, so the pair reads as a gate rather than two rocks
                yaw = math.degrees(math.atan2(float(d[0]) / nrm, float(d[1]) / nrm))
                _put(out, grid, H, x, z, yaw + float(rng.normal(0.0, 4.0)),
                     float(rng.uniform(1.0, 1.3)), assets[int(rng.integers(0, len(assets)))], tint)

        # --- single stones on local skylines ----------------------------------------------
        # Candidate summits on a coarse lattice, then the highest few that are far enough apart
        # that each is its own event on its own horizon.
        step = max(n // 96, 1)
        sub = H[::step, ::step]
        sub_owner = mine[::step, ::step]
        sub_slope = slope[::step, ::step]
        hi = np.where(sub_owner & (sub_slope < 0.34), sub, -1e9)
        flat = hi.ravel()
        order = np.argsort(flat)[::-1][:400]
        chosen: list = []
        for idx in order:
            if len(chosen) >= 4:
                break
            ii, jj = divmod(int(idx), hi.shape[1])
            x = grid.x0 + jj * step * grid.spacing
            z = grid.z0 + ii * step * grid.spacing
            if flat[idx] < -1e8 or not standable(x, z):
                continue
            j0, i0 = grid.to_tex(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
            if float(road_d[int(np.clip(i0[0], 0, n - 1)), int(np.clip(j0[0], 0, n - 1))]) < 30.0:
                continue
            if any(math.hypot(x - cx, z - cz) < 700.0 for cx, cz in chosen):
                continue
            chosen.append((x, z))
            _put(out, grid, H, x, z, float(rng.uniform(0.0, 360.0)),
                 float(rng.uniform(1.15, 1.5)), assets[int(rng.integers(0, len(assets)))], tint)
    return out
