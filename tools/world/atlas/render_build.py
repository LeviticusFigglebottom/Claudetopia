#!/usr/bin/env python3
"""Draw a built world's land with its atlas over it, to see whether the land is the map.

    python3 tools/world/atlas/render_build.py                          # game/world/generated
    python3 tools/world/atlas/render_build.py --world /tmp/w --out /tmp/map.png --size 2048

The land is the built heights, hill-shaded from the north-west and tinted by height (sea and
lake water from the built water mask, in blue); the built roads are drawn in dark red, the
built rivers in blue. Over that, in thin lines, the atlas: province outlines in white with their
names, the coast in cyan, lakes in pale blue, ranges along their crests in brown, peaks as
triangles, valleys dashed, forests in green, the authored roads' via points as small dots, and
the start as a star. Places and POIs from the content packs are dots, settlements larger.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import atlas as ATLAS  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")

## height tints, metres -> RGB, interpolated
TINTS = [(-30, (40, 70, 110)), (0, (70, 110, 150)), (0.01, (196, 190, 150)), (20, (150, 170, 110)),
         (80, (120, 150, 90)), (160, (150, 140, 100)), (300, (140, 120, 100)), (480, (170, 160, 150)),
         (650, (235, 235, 235))]


def _tint(h: np.ndarray) -> np.ndarray:
    xs = [t[0] for t in TINTS]
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for c in range(3):
        out[..., c] = np.interp(h, xs, [t[1][c] for t in TINTS])
    return out


def _load_world(world: str, size: int) -> tuple:
    man = json.load(open(os.path.join(world, "world_manifest.json")))
    n = int(man["grid"])
    H = np.fromfile(os.path.join(world, "heights.r32"), dtype="<f4").reshape(n, n)
    wpath = os.path.join(world, "water_mask.u8")
    W = np.fromfile(wpath, dtype=np.uint8).reshape(n, n) if os.path.exists(wpath) else np.zeros((n, n), np.uint8)
    f = max(n // size, 1)
    Hs = H[:n // f * f, :n // f * f].reshape(n // f, f, n // f, f).mean(axis=(1, 3))
    Ws = W[:n // f * f, :n // f * f].reshape(n // f, f, n // f, f).max(axis=(1, 3))
    return Hs, Ws, float(man.get("size_m", 8192.0)), man


def render(world: str, atlas: dict, out: str, size: int = 1536) -> str:
    Hs, Ws, size_m, _man = _load_world(world, size)
    m = Hs.shape[0]
    px = size_m / m
    gz, gx = np.gradient(Hs.astype(np.float64), px)
    # light from the north-west, high
    lx, lz, ly = -0.6, -0.6, 0.55
    norm = np.sqrt(gx * gx + gz * gz + 1.0)
    shade = np.clip((-gx * lx - gz * lz + ly) / norm / math.sqrt(lx * lx + lz * lz + ly * ly), 0.0, 1.0)
    rgb = _tint(Hs) * (0.45 + 0.75 * shade[..., None])
    water = Ws > 0
    rgb[water] = rgb[water] * 0.35 + np.array([60, 110, 170], np.float32) * 0.65
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    if img.size[0] != size:
        img = img.resize((size, size), Image.BILINEAR)
    d = ImageDraw.Draw(img)
    k = size / size_m

    def P(x, z):
        return ((x + size_m / 2.0) * k, (z + size_m / 2.0) * k)

    def poly(pts, colour, width=1, closed=True):
        q = [P(p[0], p[1]) for p in pts]
        if closed:
            q = q + [q[0]]
        d.line(q, fill=colour, width=width)

    # what was built
    for name, colour, w in (("roads.json", (120, 20, 20), 2), ("rivers.json", (30, 70, 200), 2)):
        path = os.path.join(world, name)
        if os.path.exists(path):
            for item in json.load(open(path)):
                q = [P(p[0], p[1]) for p in item["points"]]
                if len(q) > 1:
                    d.line(q, fill=colour, width=w)
    # what was drawn
    for prov in atlas.get("provinces", []):
        poly(prov["polygon"], (255, 255, 255), 1)
        cx = sum(p[0] for p in prov["polygon"]) / len(prov["polygon"])
        cz = sum(p[1] for p in prov["polygon"]) / len(prov["polygon"])
        d.text(P(cx, cz), prov.get("name", prov["id"]), fill=(255, 255, 255))
    coast = atlas.get("coast", {})
    if coast.get("polygon"):
        poly(coast["polygon"], (0, 230, 230), 2)
    for isl in coast.get("islands", []):
        poly(isl, (0, 230, 230), 2)
    for cl in coast.get("cliffs", []):
        poly(cl["path"], (255, 120, 0), 3, closed=False)
    for lake in atlas.get("lakes", []):
        poly(lake["polygon"], (170, 210, 255), 2)
        for isl in lake.get("islands", []):
            poly(isl["polygon"], (170, 210, 255), 1)
    for rng in atlas.get("ranges", []):
        poly([[p[0], p[1]] for p in rng["ridge"]], (110, 60, 20), 3, closed=False)
        for p in rng["ridge"]:
            d.text(P(p[0], p[1]), "%d" % p[2], fill=(90, 40, 10))
    for pk in atlas.get("peaks", []):
        x, y = P(*pk["at"])
        d.polygon([(x, y - 7), (x - 6, y + 5), (x + 6, y + 5)], outline=(90, 40, 10))
        d.text((x + 7, y - 6), "%s %d" % (pk.get("name", ""), pk["height_m"]), fill=(90, 40, 10))
    for v in atlas.get("valleys", []):
        q = [P(p[0], p[1]) for p in v["path"]]
        for a, b in zip(q[::2], q[1::2]):
            d.line([a, b], fill=(60, 60, 160), width=2)
    for f in atlas.get("forests", []):
        poly(f["polygon"], (20, 140, 40), 2)
    for rd in atlas.get("roads", []):
        for p in rd.get("via", []):
            x, y = P(*p)
            d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(255, 220, 0))
    # the places the content packs put there
    for fn in (("places", "places.json"), ("pois", "pois.json")):
        path = os.path.join(PACK, *fn)
        if not os.path.exists(path):
            continue
        for p in json.load(open(path)):
            pos = p.get("position")
            if not pos:
                continue
            x, y = P(float(pos[0]), float(pos[1]))
            big = p.get("kind") in ATLAS.SETTLEMENT_KINDS
            r = 3.5 if big else 2.0
            d.ellipse([x - r, y - r, x + r, y + r], fill=(0, 0, 0) if big else (60, 60, 60))
            if big:
                d.text((x + 5, y - 5), p.get("name", p["id"]), fill=(0, 0, 0))
    st = atlas.get("start")
    if st:
        x, y = P(*st["at"])
        pts = []
        for i in range(10):
            a = math.radians(i * 36.0 - 90.0)
            r = 9.0 if i % 2 == 0 else 4.0
            pts.append((x + r * math.cos(a), y + r * math.sin(a)))
        d.polygon(pts, fill=(255, 40, 40))
        b = math.radians(float(st.get("facing_deg", 0.0)))
        d.line([(x, y), (x + 22 * math.sin(b), y - 22 * math.cos(b))], fill=(255, 40, 40), width=2)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", default=GEN)
    ap.add_argument("--atlas", default=ATLAS.ATLAS_PATH)
    ap.add_argument("--out", default=os.path.join(REPO, "captures", "atlas_map.png"))
    ap.add_argument("--size", type=int, default=1536)
    a = ap.parse_args(argv)
    print(render(a.world, ATLAS.load(a.atlas), a.out, a.size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
