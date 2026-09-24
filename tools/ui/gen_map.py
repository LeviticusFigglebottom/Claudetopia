#!/usr/bin/env python3
"""Wickmere world chart: paint the map the player carries.

Reads the world builder's output from game/world/generated/ (CONTRACTS §6):

    world_manifest.json   {"seed", "size_m", "origin", "grid", "regions", ...}
    heights.r32           float32 little-endian, grid x grid, row-major, row = z
    region_mask.u8        region index per texel (255 = open water)
    water_mask.u8         1 where there is water at the surface
    roads.json            [{"id", "points": [[x, z], ...], "width_m"}]
    rivers.json           same shape

and paints a chart on parchment: relief in ink washes with a hatched shadow
side, region tints taken from each region's own palette, water with shore
lines, roads and rivers drawn with the same wobbling nib as the rest of the UI,
and region names hand-lettered in Cinzel.

When the generated world is not there yet, `--synthetic` builds a stand-in from
the region definitions in the core content pack (their map centre, radius,
shape and relief), so the chart is still the shape of Wickmere and the real one
simply replaces it when `./run.sh world` has run.

Usage:
    python3 tools/ui/gen_map.py                      # game/assets/ui/map/
    python3 tools/ui/gen_map.py --size 2048
    python3 tools/ui/gen_map.py --world <dir> --out <dir>

Writes <out>/world_map.png and <out>/world_map.json, the second holding the
world-to-pixel transform the map screen needs.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_ui_textures import (  # noqa: E402  (same package, shared drawing kit)
    PALETTES, Nib, fbm, over, parchment, to_image, _upscale,
)

ROOT = Path(__file__).resolve().parents[2]
WORLD_DEFAULT = ROOT / "game" / "world" / "generated"
OUT_DEFAULT = ROOT / "game" / "assets" / "ui" / "map"
REGIONS_JSON = ROOT / "game" / "content" / "packs" / "core" / "regions" / "regions.json"
PLACES_JSON = ROOT / "game" / "content" / "packs" / "core" / "places" / "places.json"
FONT_DISPLAY = ROOT / "game" / "assets" / "fonts" / "Cinzel-Variable.ttf"

WATER = (70, 104, 128)
WATER_DEEP = (44, 72, 96)


# --------------------------------------------------------------------------------------
# reading the world
# --------------------------------------------------------------------------------------

def load_regions() -> list[dict]:
    if not REGIONS_JSON.exists():
        return []
    return json.loads(REGIONS_JSON.read_text())


def load_places() -> list[dict]:
    if not PLACES_JSON.exists():
        return []
    return json.loads(PLACES_JSON.read_text())


def read_world(world_dir: Path) -> dict | None:
    """The real thing, if the world builder has run."""
    manifest_path = world_dir / "world_manifest.json"
    if not manifest_path.exists():
        return None
    manifest = json.loads(manifest_path.read_text())
    grid = int(manifest.get("grid", 4096))
    out: dict = {"manifest": manifest, "grid": grid}

    heights_path = world_dir / "heights.r32"
    if heights_path.exists():
        data = np.fromfile(heights_path, dtype="<f4")
        if data.size >= grid * grid:
            out["heights"] = data[: grid * grid].reshape((grid, grid))
    for name, key in (("region_mask.u8", "regions"), ("water_mask.u8", "water")):
        path = world_dir / name
        if path.exists():
            data = np.fromfile(path, dtype=np.uint8)
            if data.size >= grid * grid:
                out[key] = data[: grid * grid].reshape((grid, grid))
    for name, key in (("roads.json", "roads"), ("rivers.json", "rivers")):
        path = world_dir / name
        if path.exists():
            out[key] = json.loads(path.read_text())
    return out


def synthetic_world(size_m: float = 8192.0, grid: int = 1024, seed: int = 20260919) -> dict:
    """A stand-in world built from the region definitions, for when the real one is not
    generated yet. Same arrays and the same manifest shape as the world builder writes:
    land across the whole basin, the Mere in the middle of it, and each region's own
    relief and roughness raising the ground where that region sits."""
    rng = np.random.default_rng(seed)
    regions = load_regions()
    half = size_m * 0.5
    ys, xs = np.mgrid[0:grid, 0:grid].astype(np.float32)
    world_x = (xs + 0.5) / grid * size_m - half
    world_z = (ys + 0.5) / grid * size_m - half

    noise = fbm(grid, grid, rng, octaves=7, base=5, persistence=0.55)
    ridges = fbm(grid, grid, rng, octaves=6, base=9, persistence=0.62)
    heights = (22.0 + 26.0 * noise).astype(np.float32)

    region_weight = np.zeros((len(regions), grid, grid), np.float32)
    lake = np.zeros((grid, grid), np.float32)
    ids: list[str] = []
    for index, region in enumerate(regions):
        ids.append(region["id"])
        m = region.get("map", {})
        cx, cz = (list(m.get("center", [0, 0])) + [0, 0])[:2]
        radius = float(m.get("radius", 2000.0))
        base = float(m.get("base_height", 30.0))
        relief = float(m.get("relief", 40.0))
        rough = float(m.get("roughness", 0.3))
        d = np.sqrt((world_x - float(cx)) ** 2 + (world_z - float(cz)) ** 2)
        falloff = np.clip(1.0 - d / (radius * 1.25), 0.0, 1.0) ** 1.3
        region_weight[index] = falloff
        local = (base - 22.0) + relief * (0.30 + 0.70 * noise) \
            + relief * 0.9 * (ridges - 0.5) * (0.4 + 1.6 * rough)
        heights += local * falloff
        lake_radius = float(m.get("lake_radius", 0.0))
        if lake_radius > 0.0:
            wobble = lake_radius * (0.80 + 0.42 * ridges)
            lake = np.maximum(lake, np.clip(1.0 - d / wobble, 0.0, 1.0) ** 0.55)

    lake_level = 8.0
    heights -= lake * (heights - (lake_level - 26.0))
    # a marsh and its tide flats to the west, where Sedgemire runs out into the Grey Sea
    west = np.clip((-world_x - half * (0.80 + 0.10 * noise)) / (half * 0.16), 0.0, 1.0)
    heights -= west * (heights - (lake_level - 6.0))

    strongest = region_weight.max(axis=0) if len(regions) else np.zeros((grid, grid), np.float32)
    region_mask = np.where(strongest > 0.02,
                           region_weight.argmax(axis=0).astype(np.uint8), np.uint8(255))
    water = (heights < lake_level).astype(np.uint8)
    region_mask = np.where(water == 1, np.uint8(255), region_mask)

    manifest = {
        "seed": seed, "size_m": size_m, "spacing_m": size_m / grid,
        "origin": [-half, -half], "grid": grid, "sea_level": 0, "lake_level": lake_level,
        "regions": ids, "cell_size_m": 256, "cells": [32, 32], "synthetic": True,
    }
    return {"manifest": manifest, "grid": grid, "heights": heights.astype(np.float32),
            "regions": region_mask, "water": water,
            "roads": synthetic_roads(), "rivers": synthetic_rivers()}


def synthetic_roads() -> list[dict]:
    """The roads a chart would show: the ways between the six settlements."""
    places = {p["id"]: p for p in load_places()}

    def pos(place_id: str) -> list[float]:
        p = places.get(place_id, {})
        xz = p.get("position", [0, 0])
        return [float(xz[0]), float(xz[1])]

    links = [
        ("core:place/merrowby", "core:place/tollmere"),
        ("core:place/merrowby", "core:place/tamwick"),
        ("core:place/merrowby", "core:place/wardens_rest"),
        ("core:place/tollmere", "core:place/gullhithe"),
        ("core:place/tollmere", "core:place/kharrow_hold"),
        ("core:place/tollmere", "core:place/isseva"),
        ("core:place/tollmere", "core:place/grandfather_hollow"),
        ("core:place/merrowby", "core:place/pilgrims_ash"),
    ]
    roads = []
    for i, (a, b) in enumerate(links):
        if a not in places or b not in places:
            continue
        pa, pb = pos(a), pos(b)
        points = []
        for t in np.linspace(0.0, 1.0, 12):
            wob = math.sin(t * 5.0 + i) * 120.0 * math.sin(math.pi * t)
            points.append([pa[0] + (pb[0] - pa[0]) * t + wob,
                           pa[1] + (pb[1] - pa[1]) * t - wob * 0.6])
        roads.append({"id": "road_%d" % i, "points": points, "width_m": 6.0})
    return roads


def synthetic_rivers() -> list[dict]:
    return [
        {"id": "larkbourne", "points": [[1700, 3000], [1250, 2600], [900, 2100],
                                        [600, 1400], [300, 700], [120, 100]], "width_m": 12.0},
        {"id": "reed_channel", "points": [[-900, -300], [-1600, -420], [-2300, -500],
                                          [-3100, -640], [-3800, -900]], "width_m": 20.0},
        {"id": "skerr_falls", "points": [[300, -3400], [200, -2800], [80, -2200],
                                         [-60, -1500], [-120, -800]], "width_m": 9.0},
    ]


# --------------------------------------------------------------------------------------
# painting
# --------------------------------------------------------------------------------------

def resize_field(field: np.ndarray, size: int, nearest: bool = False) -> np.ndarray:
    img = Image.fromarray(field.astype(np.float32), mode="F")
    return np.asarray(img.resize((size, size), Image.NEAREST if nearest else Image.BILINEAR),
                      dtype=np.float32)


def _blur_field(field: np.ndarray, radius: float) -> np.ndarray:
    """Gaussian blur on a float field (PIL will not blur mode "F")."""
    lo, hi = float(field.min()), float(field.max())
    span = max(hi - lo, 1e-6)
    norm = ((field - lo) / span * 255.0).astype(np.uint8)
    blurred = np.asarray(Image.fromarray(norm).filter(ImageFilter.GaussianBlur(radius)), np.float32)
    return blurred / 255.0 * span + lo


def hillshade(heights: np.ndarray, strength: float = 1.0) -> np.ndarray:
    """Light from the north-west, as every chart has had since charts began."""
    gz, gx = np.gradient(heights)
    slope = np.sqrt(gx * gx + gz * gz)
    light = (-gx * 0.7 - gz * 0.7) / (slope + 1.0)
    return np.clip(0.5 + light * strength, 0.0, 1.0)


def ink_wash(shade: np.ndarray, steps: int = 5) -> np.ndarray:
    """Quantise the shading into a few washes, the way a painter would lay them."""
    q = np.clip(shade, 0.0, 1.0)
    return np.floor(q * steps) / max(steps - 1, 1)


def paint(world: dict, size: int, seed: int = 4242) -> tuple[Image.Image, dict]:
    rng = np.random.default_rng(seed)
    pal = PALETTES["warm"]
    manifest = world["manifest"]
    size_m = float(manifest.get("size_m", 8192))
    origin = manifest.get("origin", [-size_m / 2, -size_m / 2])
    grid = int(world.get("grid", 1024))

    heights = world.get("heights")
    if heights is None:
        heights = np.zeros((grid, grid), np.float32)
    heights_small = resize_field(heights, size)
    water = world.get("water")
    water_small = resize_field(water.astype(np.float32), size) if water is not None else np.zeros((size, size), np.float32)
    region_small = resize_field(world["regions"].astype(np.float32), size, nearest=True) \
        if world.get("regions") is not None else np.full((size, size), 255.0)

    base = np.asarray(parchment(size, size, rng, pal, vignette=0.26, stains=7,
                                fibre=0.17, edge=0.03).convert("RGB"), np.float32)

    # region tints: each region's own first palette colour, laid on thin
    regions = load_regions()
    ids = list(manifest.get("regions", [r["id"] for r in regions]))
    by_id = {r["id"]: r for r in regions}
    tint = np.zeros((size, size, 3), np.float32)
    tint_mask = np.zeros((size, size), np.float32)
    for index, region_id in enumerate(ids):
        region = by_id.get(region_id)
        if region is None:
            continue
        palette = region.get("identity", {}).get("palette", ["#8a8a80"])
        colour = np.asarray(_hex(palette[0]), np.float32)
        m = (np.abs(region_small - index) < 0.5).astype(np.float32)
        m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(size / 42.0)), np.float32) / 255.0
        tint += colour[None, None, :] * m[..., None]
        tint_mask = np.maximum(tint_mask, m)
    tint_strength = 0.16 * tint_mask
    rgb = base * (1.0 - tint_strength[..., None]) + tint * tint_strength[..., None]

    # relief: washes of ink on the shaded side, paper left alone on the lit side
    smooth = _blur_field(heights_small, size / 150.0)
    shade = ink_wash(hillshade(smooth * (900.0 / max(size, 1)), 1.9), 4)
    dark = np.clip(1.0 - shade, 0.0, 1.0) ** 1.2
    dark = _blur_field(dark, size / 420.0)
    grain = fbm(size, size, rng, octaves=4, base=7, persistence=0.6)
    dark = dark * (0.78 + 0.34 * grain)
    land = (water_small < 0.5).astype(np.float32)
    rgb = rgb * (1.0 - (dark * 0.50 * land)[..., None]) \
        + np.asarray(pal["ink"], np.float32) * (dark * 0.50 * land)[..., None]

    # high ground gets a second, drier wash so the moors read as high
    if heights_small.max() > heights_small.min():
        high = np.clip((smooth - np.percentile(smooth, 55))
                       / max(np.percentile(smooth, 99) - np.percentile(smooth, 55), 1.0), 0.0, 1.0)
        rgb = rgb * (1.0 - (high * 0.24 * land)[..., None]) \
            + np.asarray(pal["paper_edge"], np.float32) * (high * 0.24 * land)[..., None]

    # water
    wet = np.clip(water_small, 0.0, 1.0)
    depth = np.clip((float(manifest.get("lake_level", 8)) - heights_small) / 40.0, 0.0, 1.0) * wet
    water_rgb = np.asarray(WATER, np.float32)[None, None, :] * (1.0 - depth[..., None]) \
        + np.asarray(WATER_DEEP, np.float32)[None, None, :] * depth[..., None]
    wet_soft = np.asarray(Image.fromarray((wet * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(size / 700.0)), np.float32) / 255.0
    rgb = rgb * (1.0 - (wet_soft * 0.78)[..., None]) + water_rgb * (wet_soft * 0.78)[..., None]

    chart = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    # shore lines, rivers, roads and lettering, all drawn with the same nib
    nib = Nib(size, size, rng)
    _draw_shore(nib, wet, size)
    for river in world.get("rivers", []):
        _draw_line(nib, river.get("points", []), origin, size_m, WATER_DEEP, 0.0022, jitter=0.0022)
    for road in world.get("roads", []):
        _draw_line(nib, road.get("points", []), origin, size_m, pal["ink_soft"], 0.0016,
                   jitter=0.0018, dashed=True)
    chart = over(chart, nib.bake(grain=0.4, blur=0.6))

    letters = Nib(size, size, rng)
    for index, region_id in enumerate(ids):
        region = by_id.get(region_id)
        if region is None:
            continue
        name = str(region.get("name", "")).upper()
        homes = [_to_uv(float(pl["position"][0]), float(pl["position"][1]), origin, size_m)
                 for pl in load_places() if pl.get("region") == region_id and len(pl.get("position", [])) >= 2]
        u, v = _label_uv(region_small, index, region, origin, size_m,
                         half_width=len(name) * LABEL_SIZE * LABEL_ASPECT * 0.5, homes=homes)
        if not (0.02 < u < 0.98 and 0.02 < v < 0.98):
            continue
        letters.text(name, (u, v), LABEL_SIZE, pal["ink"], FONT_DISPLAY, alpha=205)
    chart = over(chart, letters.bake(grain=0.35, blur=0.5))

    # border and a compass rose in the corner
    edge = Nib(size, size, rng)
    edge.rect(0.012, 0.012, 0.988, 0.988, pal["ink"], width=0.0026, jitter=0.0024)
    edge.rect(0.020, 0.020, 0.980, 0.980, pal["ink_soft"], width=0.0012, jitter=0.0024)
    _compass_rose(edge, pal, 0.915, 0.905, 0.052)
    chart = over(chart, edge.bake(grain=0.35, blur=0.5))

    info = {
        "file": "world_map.png", "size_px": size, "size_m": size_m, "origin": origin,
        "regions": ids, "lake_level": manifest.get("lake_level", 8),
        "synthetic": bool(manifest.get("synthetic", False)),
        "_doc": "world to pixel: px = (world_xz - origin) / size_m * size_px, z is +south",
    }
    return chart, info


def _hex(text: str) -> tuple[int, int, int]:
    t = text.lstrip("#")
    return int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16)


def _to_uv(x: float, z: float, origin, size_m: float) -> tuple[float, float]:
    return (x - float(origin[0])) / size_m, (z - float(origin[1])) / size_m


LABEL_SIZE = 0.019          # a region name's letter height, as a fraction of the chart
LABEL_ASPECT = 0.74         # Cinzel capitals: width per letter over height
ROSE_BOX = (0.84, 0.83)     # the compass rose's corner: no name is lettered over it


def _label_uv(region_small: np.ndarray, index: int, region: dict, origin, size_m: float,
              half_width: float = 0.0, homes: list | None = None) -> tuple[float, float]:
    """Where a region's name is lettered: well inside the region as the region mask has it, so
    the name goes where the region is however the map has been drawn; of the ground deep inside
    it, the part nearest the places people live in it (else its middle); and with the whole name
    on the chart and off the compass rose. Only a region the mask does not have is lettered at
    its map block's `center`, which is a point written down once and left behind when the map is
    redrawn (docs/COORDINATES.md)."""
    mask = np.abs(region_small - index) < 0.5
    if mask.any():
        from scipy import ndimage
        h, w = mask.shape
        inside = ndimage.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
        us = (np.arange(w) + 0.5) / w
        vs = (np.arange(h) + 0.5) / h
        room = ((us[None, :] >= half_width + 0.03) & (us[None, :] <= 0.97 - half_width)
                & (vs[:, None] >= 0.06) & (vs[:, None] <= 0.94)
                & ~((us[None, :] + half_width >= ROSE_BOX[0]) & (vs[:, None] >= ROSE_BOX[1])))
        deep = inside * room
        if deep.max() <= 0.0:
            deep = inside
        rows, cols = np.nonzero(deep >= 0.5 * deep.max())
        if homes:
            tu = sum(hm[0] for hm in homes) / len(homes)
            tv = sum(hm[1] for hm in homes) / len(homes)
        else:
            ci, cj = np.nonzero(mask)
            tu, tv = (cj.mean() + 0.5) / w, (ci.mean() + 0.5) / h
        k = int(np.argmin(((cols + 0.5) / w - tu) ** 2 + ((rows + 0.5) / h - tv) ** 2))
        return (cols[k] + 0.5) / w, (rows[k] + 0.5) / h
    m = region.get("map", {})
    cx, cz = (list(m.get("center", [0, 0])) + [0, 0])[:2]
    return _to_uv(float(cx), float(cz), origin, size_m)


def _draw_line(nib: Nib, points, origin, size_m: float, colour, width: float,
               jitter: float = 0.002, dashed: bool = False) -> None:
    uv = [_to_uv(float(p[0]), float(p[1]), origin, size_m) for p in points if len(p) >= 2]
    if len(uv) < 2:
        return
    if dashed:
        for i in range(0, len(uv) - 1, 2):
            nib.stroke(uv[i:i + 2], width, colour, jitter=jitter, taper=0.0, alpha=225)
    else:
        nib.stroke(uv, width, colour, jitter=jitter, taper=0.1)


def _draw_shore(nib: Nib, wet: np.ndarray, size: int) -> None:
    """One inked line where the water meets the land, from the mask's own edge."""
    mask = (wet > 0.5).astype(np.uint8) * 255
    img = Image.fromarray(mask)
    edge = np.asarray(img.filter(ImageFilter.FIND_EDGES), np.float32)
    ys, xs = np.nonzero(edge > 40)
    if ys.size == 0:
        return
    step = max(1, ys.size // 2200)
    for i in range(0, ys.size, step):
        u = (xs[i] + 0.5) / size
        v = (ys[i] + 0.5) / size
        nib.circle((u, v), 0.0016, WATER_DEEP, width=0.0, fill=WATER_DEEP, segments=5,
                   jitter=0.0012, alpha=190)


def _compass_rose(nib: Nib, pal: dict, cx: float, cy: float, r: float) -> None:
    nib.circle((cx, cy), r, pal["ink"], width=0.0022, jitter=0.0022)
    nib.circle((cx, cy), r * 0.58, pal["ink_soft"], width=0.0012, jitter=0.0022)
    for k in range(4):
        a = k * math.tau / 4 - math.pi / 2
        tip = (cx + math.cos(a) * r * 1.22, cy + math.sin(a) * r * 1.22)
        left = (cx + math.cos(a + 1.35) * r * 0.30, cy + math.sin(a + 1.35) * r * 0.30)
        right = (cx + math.cos(a - 1.35) * r * 0.30, cy + math.sin(a - 1.35) * r * 0.30)
        nib.poly([tip, left, (cx, cy), right], pal["metal"] if k % 2 == 0 else pal["ink_soft"],
                 alpha=170, jitter=0.002)
        nib.stroke([tip, left, (cx, cy), right], 0.0020, pal["ink"], closed=True, jitter=0.0024)
    nib.text("N", (cx, cy - r * 1.55), 0.022, pal["ink"], FONT_DISPLAY)


# --------------------------------------------------------------------------------------

def build(world_dir: Path, out_dir: Path, size: int = 1536, force_synthetic: bool = False) -> dict:
    world = None if force_synthetic else read_world(world_dir)
    if world is None:
        world = synthetic_world()
    if world.get("regions") is None:
        world["regions"] = np.full((world["grid"], world["grid"]), 255, np.uint8)
    chart, info = paint(world, size)
    out_dir.mkdir(parents=True, exist_ok=True)
    chart.convert("RGB").save(out_dir / "world_map.png")
    (out_dir / "world_map.json").write_text(json.dumps(info, indent=1) + "\n")
    return info


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--world", type=Path, default=WORLD_DEFAULT)
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT)
    ap.add_argument("--size", type=int, default=1536)
    ap.add_argument("--synthetic", action="store_true", help="ignore the generated world")
    args = ap.parse_args()
    info = build(args.world, args.out, args.size, args.synthetic)
    print("[map] %s chart %dpx -> %s" % ("synthetic" if info["synthetic"] else "world",
                                         info["size_px"], args.out))


if __name__ == "__main__":
    main()
