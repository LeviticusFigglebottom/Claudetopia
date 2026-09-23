#!/usr/bin/env python3
"""Draw the atlas: the country as tools/world/atlas/atlas.json describes it, and everything the
content packs stand on it.

    python3 tools/world/atlas/render_map.py                    # docs/atlas/wickmere_atlas.png
    python3 tools/world/atlas/render_map.py --out my.png --size 2400
    python3 tools/world/atlas/render_map.py --coverage         # also shade ground far from anything
    python3 tools/world/atlas/render_map.py --world /tmp/w     # the land a build made, with the atlas over it

Provinces are coloured by biome and shaded by the land the atlas describes (preview.py's reading
of it; with --world, the heights and water of a world built from it), with water, woods, rivers and roads over them, every settlement
named, every point of interest drawn as a symbol of its kind (named where there is room), the
Hearthstones ringed, and the start marked with the way it faces. The panel beside the map gives
the density figures the atlas was drawn to.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import preview as PV  # noqa: E402

REPO = PV.REPO
FONTS = os.path.join(REPO, "game", "assets", "fonts")
OUT_DEFAULT = os.path.join(REPO, "docs", "atlas", "wickmere_atlas.png")

BIOME = {
    "downs": (196, 186, 104),
    "lake_basin": (160, 184, 132),
    "delta": (112, 146, 128),
    "forest_rise": (70, 116, 62),
    "mountains": (150, 146, 150),
    "ash_plateau": (150, 146, 138),
}
SEA = (92, 118, 134)
HUSH = (150, 152, 156)
LAKE = (96, 142, 170)
RIVER = (70, 120, 160)
SNOW = (238, 240, 244)
FOREST = {
    "ancient": (44, 84, 44), "oakwood": (68, 104, 52), "pine": (58, 88, 70), "wetwood": (70, 104, 84),
    "limewood": (104, 132, 70), "deadwood": (196, 196, 190), "orchard": (120, 150, 60),
}
ROAD = {
    "highway": ((126, 58, 34), 4.2), "road": ((140, 84, 46), 3.0), "lane": ((150, 104, 64), 2.2),
    "track": ((150, 116, 80), 1.6), "causeway": ((90, 84, 80), 5.0), "stair": ((84, 70, 62), 2.0),
}
# drawn in this order, so the greater roads lie over the lesser where they meet
ROAD_ORDER = ["track", "stair", "lane", "road", "highway", "causeway"]
INK = (40, 32, 26)
PAPER = (236, 226, 204)
REGION_NAME = {
    "core:region/hearthvale": "HEARTHVALE", "core:region/brightwater": "BRIGHTWATER",
    "core:region/sedgemire": "SEDGEMIRE", "core:region/briarwold": "THE BRIARWOLD",
    "core:region/skerrow": "SKERROW HEIGHTS", "core:region/cinderlea": "CINDERLEA",
}
SETTLEMENT = {"city": 11, "town": 8, "village": 6, "hamlet": 5, "fort": 6, "lodge": 4, "camp": 5,
              "ruin_village": 5}


def font(name: str, size: int):
    path = os.path.join(FONTS, name)
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


class Chart:
    def __init__(self, atlas: PV.Atlas, size: int):
        self.a = atlas
        self.size = size
        self.scale = size / PV.SIZE_M

    def px(self, x: float, z: float) -> tuple:
        return ((x + PV.HALF_M) * self.scale, (z + PV.HALF_M) * self.scale)

    def up(self, field: np.ndarray, order: int = 1) -> np.ndarray:
        f = self.size / field.shape[0]
        return ndimage.zoom(field, f, order=order)[: self.size, : self.size]


def load_built(world: str, n: int) -> tuple:
    """A built world's heights and water (tools/world/build_world.py --out), resampled to n x n."""
    import json
    with open(os.path.join(world, "world_manifest.json"), "r", encoding="utf-8") as f:
        man = json.load(f)
    g = int(man["grid"])
    H = np.fromfile(os.path.join(world, "heights.r32"), dtype="<f4").reshape(g, g)
    W = np.fromfile(os.path.join(world, "water_mask.u8"), dtype=np.uint8).reshape(g, g)
    if g != n:
        H = ndimage.zoom(H, n / g, order=1)[:n, :n]
        W = ndimage.zoom(W, n / g, order=0)[:n, :n]
    return H.astype(np.float32), W > 0


def hillshade(h: np.ndarray, res: float) -> np.ndarray:
    gz, gx = np.gradient(h, res)
    out = np.zeros_like(h)
    for az, w in ((315, 0.55), (270, 0.2), (0, 0.25)):
        a = math.radians(az)
        alt = math.radians(42)
        lx, lz, ly = math.sin(a) * math.cos(alt), -math.cos(a) * math.cos(alt), math.sin(alt)
        n = np.sqrt(gx * gx * 4 + gz * gz * 4 + 1.0)
        out += w * ((-gx * 2 * lx - gz * 2 * lz + ly) / n)
    return np.clip(out, 0.0, 1.0)


def draw_symbol(d: ImageDraw.ImageDraw, kind: str, x: float, y: float, r: float, hearth: bool) -> None:
    ink = INK
    if hearth:
        d.ellipse([x - r - 3.5, y - r - 3.5, x + r + 3.5, y + r + 3.5], outline=(214, 150, 40), width=2)
    if kind == "tower":
        d.polygon([(x - r * 0.55, y + r), (x + r * 0.55, y + r), (x + r * 0.35, y - r), (x - r * 0.35, y - r)],
                  fill=(92, 80, 70), outline=ink)
        d.rectangle([x - r * 0.5, y - r - 2, x + r * 0.5, y - r], fill=ink)
    elif kind == "shrine":
        d.ellipse([x - r * 0.8, y - r * 0.8, x + r * 0.8, y + r * 0.8], fill=(238, 214, 150), outline=ink)
        d.line([x, y - r * 0.55, x, y + r * 0.55], fill=ink, width=2)
        d.line([x - r * 0.4, y - r * 0.15, x + r * 0.4, y - r * 0.15], fill=ink, width=2)
    elif kind == "bridge":
        d.arc([x - r, y - r * 0.6, x + r, y + r * 1.2], 200, 340, fill=ink, width=3)
        d.line([x - r * 1.1, y - r * 0.2, x + r * 1.1, y - r * 0.2], fill=ink, width=2)
    elif kind == "waterfall":
        for k in (-1, 0, 1):
            d.line([x + k * r * 0.45, y - r, x + k * r * 0.45, y + r], fill=(40, 90, 150), width=2)
        d.line([x - r, y - r, x + r, y - r], fill=ink, width=2)
    elif kind == "ruins":
        d.rectangle([x - r, y + r * 0.3, x + r, y + r * 0.7], fill=(120, 110, 100), outline=ink)
        d.line([x - r * 0.6, y + r * 0.3, x - r * 0.6, y - r], fill=ink, width=2)
        d.line([x + r * 0.6, y + r * 0.3, x + r * 0.6, y - r * 0.4], fill=ink, width=2)
    elif kind == "giant_bones":
        d.arc([x - r, y - r, x + r, y + r], 180, 360, fill=(250, 246, 236), width=3)
        d.arc([x - r * 0.55, y - r * 0.55, x + r * 0.55, y + r * 0.55], 180, 360, fill=(250, 246, 236), width=2)
        d.line([x - r, y, x + r, y], fill=ink, width=1)
    elif kind == "strange_tree":
        d.ellipse([x - r, y - r, x + r, y + r * 0.4], fill=(52, 92, 48), outline=ink)
        d.line([x, y + r * 0.3, x, y + r], fill=ink, width=2)
    elif kind == "wreck":
        d.chord([x - r, y - r * 0.6, x + r, y + r * 0.9], 0, 180, fill=(110, 80, 50), outline=ink)
        d.line([x, y - r, x, y + r * 0.2], fill=ink, width=2)
    elif kind == "hidden_valley":
        d.arc([x - r, y - r * 0.4, x + r, y + r * 1.2], 180, 360, fill=ink, width=2)
        d.ellipse([x - 2, y + r * 0.1, x + 2, y + r * 0.1 + 4], fill=ink)
    elif kind == "standing_stones":
        for k in (-1, 0, 1):
            d.rectangle([x + k * r * 0.6 - 1.4, y - r * (0.9 if k == 0 else 0.6), x + k * r * 0.6 + 1.4, y + r * 0.6],
                        fill=(90, 90, 96), outline=ink)
    elif kind == "camp":
        d.polygon([(x - r, y + r * 0.8), (x + r, y + r * 0.8), (x, y - r)], fill=(214, 168, 90), outline=ink)
    elif kind == "strange":
        d.regular_polygon((x, y, r * 0.9), 5, rotation=18, fill=(200, 60, 60), outline=ink)
    elif kind in ("deep_place", "interior_dungeon"):
        d.pieslice([x - r, y - r, x + r, y + r], 180, 360, fill=(30, 26, 24), outline=ink)
        d.rectangle([x - r, y, x + r, y + r * 0.5], fill=(30, 26, 24))
    elif kind in ("landmark", "poi"):
        d.regular_polygon((x, y, r), 4, rotation=45, fill=(170, 120, 60), outline=ink)
    elif kind == "edge":
        d.line([x - r, y - r, x + r, y + r], fill=(120, 40, 40), width=2)
        d.line([x - r, y + r, x + r, y - r], fill=(120, 40, 40), width=2)
    else:
        d.ellipse([x - r * 0.6, y - r * 0.6, x + r * 0.6, y + r * 0.6], fill=(160, 160, 160), outline=ink)


class Labels:
    """Places labels where they do not cover another label or a symbol."""

    def __init__(self, size: int):
        self.boxes = []
        self.size = size

    def free(self, box) -> bool:
        x0, y0, x1, y1 = box
        if x0 < 2 or y0 < 2 or x1 > self.size - 2 or y1 > self.size - 2:
            return False
        for b in self.boxes:
            if not (x1 < b[0] or x0 > b[2] or y1 < b[1] or y0 > b[3]):
                return False
        return True

    def reserve(self, box) -> None:
        self.boxes.append(box)

    def place(self, d: ImageDraw.ImageDraw, text: str, x: float, y: float, fnt, fill=INK, halo=PAPER,
              offsets=None, force=False, gap: float = 8.0) -> bool:
        """Put `text` beside the point (x, y), `gap` pixels clear of it (the symbol's own half-size
        and a little), trying each side in turn."""
        w, h = d.textbbox((0, 0), text, font=fnt)[2:]
        g = gap
        offsets = offsets or [(g, -h / 2), (-g - w, -h / 2), (-w / 2, -h - g + 1), (-w / 2, g - 1), (g, -h - 3),
                              (g, 3), (-g - w, -h - 3), (-g - w, 3)]
        for ox, oy in offsets:
            box = (x + ox - 2, y + oy - 1, x + ox + w + 2, y + oy + h + 2)
            if force or self.free(box):
                d.text((x + ox, y + oy), text, font=fnt, fill=fill, stroke_width=2, stroke_fill=halo)
                self.reserve(box)
                return True
        return False


def render(atlas: PV.Atlas, out: str, size: int = 2400, coverage: bool = False, world: str = "",
           colours: int = 0) -> dict:
    ch = Chart(atlas, size)
    doc = atlas.doc
    survey = atlas.survey()

    # --- ground colour by province, shaded by the land -----------------------------------------
    base = np.zeros((atlas.grid.n, atlas.grid.n, 3), np.float32)
    idx = atlas.province_index
    for k, p in enumerate(doc["provinces"]):
        col = np.array(BIOME[p["biome"]], np.float32)
        # a province is a little lighter or darker than its neighbours of the same biome
        col = col * (0.94 + 0.12 * ((zlib.crc32(p["id"].encode()) % 7) / 6.0))
        base[idx == k] = col
    base = ndimage.gaussian_filter(base, sigma=(3, 3, 0))
    H = atlas.heights
    built_water = None
    if world:
        H, built_water = load_built(world, atlas.grid.n)
    snow = np.clip((H - 520.0) / 90.0, 0.0, 1.0)[..., None]
    base = base * (1 - snow * 0.85) + np.array(SNOW, np.float32) * snow * 0.85
    shade = hillshade(H, atlas.res)
    img = base * (0.55 + 0.75 * shade[..., None])

    # woods
    for f in doc.get("forests", []):
        m = atlas.grid.polygon_mask(f["polygon"]) & atlas.land
        col = np.array(FOREST[f["kind"]], np.float32)
        a = 0.35 + 0.4 * float(f["density"])
        img[m] = img[m] * (1 - a) + col * a * (0.6 + 0.6 * shade[m][:, None])

    # water
    sea = ~atlas.land
    hush = sea & (atlas.grid.zs > 3000) & (atlas.grid.xs > -3400)
    img[sea] = np.array(SEA, np.float32) * (0.9 + 0.1 * shade[sea][:, None])
    img[hush] = np.array(HUSH, np.float32)
    lake = atlas.lake_id >= 0
    img[lake] = np.array(LAKE, np.float32)
    if built_water is not None:
        # the water where the build put it: the sea off the coast, lakes and rivers inland. A lake's
        # bed may go below the sea's level, so which water is which comes from the atlas, not the depth.
        dry_lake = ~built_water & lake
        img[dry_lake] = base[dry_lake] * (0.55 + 0.75 * shade[dry_lake][:, None])
        img[built_water & sea] = np.array(SEA, np.float32)
        img[built_water & hush] = np.array(HUSH, np.float32)
        img[built_water & ~sea] = np.array(LAKE, np.float32)
        if coverage:
            # where the atlas draws a lake and the build left the ground dry: its shore band
            img[dry_lake] = img[dry_lake] * 0.5 + np.array((200, 60, 60), np.float32) * 0.5
    img = np.clip(img, 0, 255).astype(np.uint8)
    im = Image.fromarray(img, "RGB").resize((size, size), Image.BICUBIC)

    if coverage:
        dist = survey["distance"]
        over = np.clip((dist - 250.0) / 300.0, 0.0, 1.0) * atlas.walkable
        red = Image.fromarray((over * 170).astype(np.uint8), "L").resize((size, size), Image.BILINEAR)
        im = Image.composite(Image.new("RGB", (size, size), (200, 30, 30)), im, red)

    d = ImageDraw.Draw(im, "RGBA")

    # the Hush's mist, and the sea's name
    f_sea = font("Spectral-Italic.ttf", max(16, size // 90))
    x, y = ch.px(-1200, 3960)
    d.text((x, y), "t h e   H u s h", font=f_sea, fill=(230, 230, 232), anchor="mm")
    x, y = ch.px(-4000, 400)
    d.text((x, y), "Grey\nSea", font=f_sea, fill=(220, 230, 236), anchor="mm", align="center")

    # shores
    edge = ndimage.binary_dilation(atlas.land) & ~atlas.land
    if built_water is not None:
        # a lake's shore where the build put its water, not quite where the atlas drew the line
        body = built_water & lake
        lake_edge = ndimage.binary_dilation(body) & ~built_water
    else:
        lake_edge = ndimage.binary_dilation(lake) & ~lake
    e = Image.fromarray(((edge | lake_edge) * 255).astype(np.uint8), "L").resize((size, size), Image.NEAREST)
    im.paste((52, 70, 84), mask=e.filter(ImageFilter.MaxFilter(3)))
    d = ImageDraw.Draw(im, "RGBA")

    # cliffs along the coast
    for c in doc["coast"].get("cliffs", []):
        pts = [ch.px(p[0], p[1]) for p in c["path"]]
        d.line(pts, fill=(60, 50, 44, 200), width=3)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            L = math.hypot(x1 - x0, y1 - y0)
            n = int(L / 9)
            for s in range(n):
                t = (s + 0.5) / max(n, 1)
                px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                nx, ny = -(y1 - y0) / L, (x1 - x0) / L
                d.line([px, py, px + nx * 5, py + ny * 5], fill=(60, 50, 44, 170), width=1)

    # rivers
    for rv in doc.get("rivers", []):
        pts = [ch.px(p[0], p[1]) for p in rv["path"]]
        w0, w1 = rv["width_m"]
        n = len(pts)
        for k in range(n - 1):
            w = (w0 + (w1 - w0) * k / max(n - 2, 1))
            d.line([pts[k], pts[k + 1]], fill=RIVER, width=max(2, int(1.2 + w * ch.scale * 2.2)))
    # dry beds
    for v in doc.get("valleys", []):
        if v["id"] == "the_glassbed":
            d.line([ch.px(p[0], p[1]) for p in v["path"]], fill=(30, 30, 34), width=4)

    # roads
    for road, pts in sorted(atlas.road_paths(), key=lambda rp: ROAD_ORDER.index(rp[0].get("kind", "road"))):
        col, w = ROAD[road.get("kind", "road")]
        xy = [ch.px(x, z) for x, z in pts]
        w = max(1, int(round(w * size / 2400)))
        if road.get("kind") == "stair":
            # a line with its steps across it
            d.line(xy, fill=col, width=w)
            tick = 2.0 + 2.5 * size / 2400
            for (x0, y0), (x1, y1) in zip(xy, xy[1:]):
                L = math.hypot(x1 - x0, y1 - y0)
                if L < 1e-6:
                    continue
                nx, ny = -(y1 - y0) / L * tick, (x1 - x0) / L * tick
                for s in range(0, int(L / 5) + 1):
                    a = s * 5 / L
                    cx, cy = x0 + (x1 - x0) * a, y0 + (y1 - y0) * a
                    d.line([cx - nx, cy - ny, cx + nx, cy + ny], fill=col, width=max(1, w // 2))
        elif road.get("kind") == "track":
            for (x0, y0), (x1, y1) in zip(xy, xy[1:]):
                L = math.hypot(x1 - x0, y1 - y0)
                n = max(1, int(L / 7))
                for s in range(0, n, 2):
                    a0, a1 = s / n, min((s + 1) / n, 1.0)
                    d.line([x0 + (x1 - x0) * a0, y0 + (y1 - y0) * a0, x0 + (x1 - x0) * a1, y0 + (y1 - y0) * a1],
                           fill=col, width=w)
        else:
            d.line(xy, fill=(250, 240, 220), width=w + 2, joint="curve")
            d.line(xy, fill=col, width=w, joint="curve")

    labels = Labels(size)
    f_region = font("Cinzel-Variable.ttf", max(20, size // 44))
    f_prov = font("Spectral-Italic.ttf", max(12, size // 150))
    f_town = font("Spectral-SemiBold.ttf", max(12, size // 130))
    f_place = font("Spectral-Regular.ttf", max(10, size // 175))
    f_poi = font("Spectral-Italic.ttf", max(9, size // 215))
    f_peak = font("Spectral-Italic.ttf", max(9, size // 200))

    # peaks
    for pk in doc.get("peaks", []):
        x, y = ch.px(*pk["at"])
        d.polygon([(x - 6, y + 5), (x + 6, y + 5), (x, y - 7)], fill=(70, 60, 56), outline=(250, 250, 250))
        labels.reserve((x - 7, y - 8, x + 7, y + 6))
        labels.place(d, "%s %d" % (pk.get("name", pk["id"]), round(pk["height_m"])), x, y, f_peak, fill=(50, 44, 40))

    # symbols first, so labels keep off them
    locs = atlas.locations()
    order = sorted(locs, key=lambda l: -SETTLEMENT.get(l[2], 0))
    for lid, name, kind, region, x, z, dd in order:
        px, py = ch.px(x, z)
        if ":place/" in lid and kind in SETTLEMENT:
            r = SETTLEMENT[kind] * size / 2400
            if kind == "city":
                d.rectangle([px - r, py - r, px + r, py + r], fill=(160, 40, 36), outline=INK, width=2)
            elif kind in ("town",):
                d.rectangle([px - r, py - r, px + r, py + r], fill=(196, 72, 48), outline=INK, width=2)
            elif kind == "fort":
                d.regular_polygon((px, py, r * 1.2), 6, fill=(120, 90, 70), outline=INK)
            elif kind == "camp":
                d.polygon([(px - r, py + r), (px + r, py + r), (px, py - r)], fill=(214, 120, 60), outline=INK)
            elif kind == "ruin_village":
                d.ellipse([px - r, py - r, px + r, py + r], fill=(150, 150, 150), outline=INK, width=2)
            else:
                d.ellipse([px - r, py - r, px + r, py + r], fill=(222, 120, 70), outline=INK, width=2)
            if "shrine" in dd.get("tags", []):
                d.ellipse([px - r - 4, py - r - 4, px + r + 4, py + r + 4], outline=(214, 150, 40), width=2)
            labels.reserve((px - r - 3, py - r - 3, px + r + 3, py + r + 3))
        else:
            r = 5.2 * size / 2400
            draw_symbol(d, kind, px, py, r, bool(dd.get("hearthstone", False)))
            labels.reserve((px - r - 2, py - r - 2, px + r + 2, py + r + 2))

    # the start and its first view
    st = doc.get("start")
    if st:
        x, y = ch.px(*st["at"])
        fd = math.radians(st["facing_deg"])
        half = math.radians(53.5)
        L = 1450 * ch.scale
        wedge = [(x, y)]
        for k in range(21):
            a = fd - half + 2 * half * k / 20
            wedge.append((x + math.sin(a) * L, y - math.cos(a) * L))
        d.polygon(wedge, fill=(255, 240, 180, 38), outline=(255, 214, 120, 120))
        d.line([x, y, x + math.sin(fd) * 70, y - math.cos(fd) * 70], fill=(180, 20, 20), width=3)
        d.regular_polygon((x, y, 11), 5, rotation=0, fill=(230, 30, 30), outline=(255, 255, 255))
        labels.place(d, "START: the Stair Head", x, y + 4, f_town, fill=(170, 20, 20),
                     offsets=[(14, -2), (-190, 8)], force=True)

    # names: regions, provinces, settlements, then everything else where it fits
    for rid, label in REGION_NAME.items():
        pts = [p for p in doc["provinces"] if p["region"] == rid]
        if not pts:
            continue
        # the region's name at the middle of its largest province, spaced out
        big = max(pts, key=lambda p: PV.polygon_area(p["polygon"]))
        m = atlas.grid.polygon_mask(big["polygon"]) & atlas.land & (atlas.lake_id < 0)
        if not m.any():
            continue
        dt = ndimage.distance_transform_edt(m)
        i, j = np.unravel_index(np.argmax(dt), dt.shape)
        x, y = ch.px(float(atlas.grid.xs[0, j]), float(atlas.grid.zs[i, 0]))
        text = " ".join(label)
        w, h = d.textbbox((0, 0), text, font=f_region)[2:]
        # kept whole on the sheet: a name near the edge is pulled in rather than cut off
        x = min(max(x, w / 2 + size * 0.02), size - w / 2 - size * 0.02)
        y = min(max(y, h / 2 + size * 0.02), size - h / 2 - size * 0.02)
        d.text((x - w / 2, y - h / 2), text, font=f_region, fill=(60, 44, 30, 150), stroke_width=3,
               stroke_fill=(250, 240, 220, 150))
    for p in doc["provinces"]:
        m = atlas.grid.polygon_mask(p["polygon"]) & atlas.land & (atlas.lake_id < 0)
        if not m.any():
            continue
        dt = ndimage.distance_transform_edt(m)
        i, j = np.unravel_index(np.argmax(dt), dt.shape)
        x, y = ch.px(float(atlas.grid.xs[0, j]), float(atlas.grid.zs[i, 0]))
        labels.place(d, p.get("name", p["id"]), x, y + size / 55, f_prov, fill=(70, 50, 36),
                     offsets=[(-60, 0), (-60, 18), (-60, -22)])
    for lk in doc.get("lakes", []):
        m = atlas.grid.polygon_mask(lk["polygon"])
        i, j = np.unravel_index(np.argmax(ndimage.distance_transform_edt(m)), m.shape)
        x, y = ch.px(float(atlas.grid.xs[0, j]), float(atlas.grid.zs[i, 0]))
        if lk["id"] == "the_mere":
            x, y = ch.px(600, -500)
        labels.place(d, lk.get("name", lk["id"]), x, y, f_prov, fill=(24, 50, 90), halo=(200, 220, 236),
                     offsets=[(-40, -8), (6, -8), (-40, 8)])

    for lid, name, kind, region, x, z, dd in order:
        px, py = ch.px(x, z)
        if ":place/" in lid and kind in ("city", "town"):
            labels.place(d, name, px, py, f_town, gap=SETTLEMENT[kind] * size / 2400 + 8)
    for lid, name, kind, region, x, z, dd in order:
        px, py = ch.px(x, z)
        if ":place/" in lid and kind not in ("city", "town"):
            labels.place(d, name, px, py, f_place, gap=SETTLEMENT.get(kind, 5.2) * size / 2400 + 7)
    for lid, name, kind, region, x, z, dd in order:
        px, py = ch.px(x, z)
        if ":poi/" in lid:
            labels.place(d, name, px, py, f_poi, fill=(50, 40, 34), gap=5.2 * size / 2400 + 6)

    # scale bar and compass
    x0, y0 = size * 0.035, size * 0.965
    km = 1000 * ch.scale
    for k in range(4):
        d.rectangle([x0 + k * km / 2, y0, x0 + (k + 1) * km / 2, y0 + 8], fill=INK if k % 2 == 0 else PAPER, outline=INK)
    d.text((x0, y0 - 22), "0        1 km        2 km", font=f_poi, fill=PAPER, stroke_width=2, stroke_fill=INK)
    cx, cy = size * 0.955, size * 0.1
    d.polygon([(cx, cy - 30), (cx - 9, cy), (cx, cy - 6), (cx + 9, cy)], fill=INK)
    d.text((cx, cy - 44), "N", font=f_town, fill=INK, anchor="mm", stroke_width=2, stroke_fill=PAPER)

    # --- the panel ---------------------------------------------------------------------------
    panel_w = int(size * 0.27)
    sheet = Image.new("RGB", (size + panel_w, size), PAPER)
    sheet.paste(im, (0, 0))
    d = ImageDraw.Draw(sheet)
    X = size + 26
    Y = 30
    f_title = font("Cinzel-Variable.ttf", max(28, size // 38))
    f_head = font("Spectral-SemiBold.ttf", max(14, size // 120))
    f_text = font("Spectral-Regular.ttf", max(12, size // 150))
    d.text((X, Y), "WICKMERE", font=f_title, fill=INK)
    Y += int(size / 26)
    d.text((X, Y), "the atlas, drawn by hand" + (" (over a built world)" if world else ""), font=f_head,
           fill=(90, 70, 50))
    Y += int(size / 50)
    rows = [
        "8.19 km square; %.1f km² of land, %.1f km² walkable" % (survey["land_km2"], survey["walkable_km2"]),
        "%d locations: %d places, %d points of interest" % (survey["locations"], survey["places"], survey["pois"]),
        "%.1f locations per walkable km²" % survey["per_km2_walkable"],
        "furthest walkable ground from one: %.0f m" % survey["max_gap_m"],
        "95%% of the ground within %.0f m; mean %.0f m" % (survey["p95_gap_m"], survey["mean_gap_m"]),
        "%.1f km of road; worst gap on a road %.0f m" % (
            survey["road_km"], survey["roads_over_reach"][0]["worst_m"] if survey["roads_over_reach"] else 0.0),
    ]
    for r_ in rows:
        d.text((X, Y), r_, font=f_text, fill=INK)
        Y += int(size / 95)
    Y += 14
    d.text((X, Y), "Provinces, by biome", font=f_head, fill=INK)
    Y += int(size / 70)
    for biome, col in BIOME.items():
        d.rectangle([X, Y + 2, X + 26, Y + 16], fill=col, outline=INK)
        names = ", ".join(p.get("name", p["id"]) for p in doc["provinces"] if p["biome"] == biome)
        lines = wrap(d, "%s: %s" % (biome.replace("_", " "), names), f_text, panel_w - 80)
        for ln in lines:
            d.text((X + 36, Y), ln, font=f_text, fill=INK)
            Y += int(size / 105)
        Y += 4
    Y += 12
    d.text((X, Y), "Settlements", font=f_head, fill=INK)
    Y += int(size / 70)
    for kind, label in (("city", "city"), ("town", "town"), ("village", "village or hamlet"), ("fort", "fort"),
                        ("lodge", "lodge or steading"), ("camp", "camp"), ("ruin_village", "dead village")):
        r = SETTLEMENT[kind] * size / 2400
        cx, cy = X + 12, Y + 9
        if kind in ("city", "town"):
            d.rectangle([cx - r, cy - r, cx + r, cy + r], fill=(160, 40, 36) if kind == "city" else (196, 72, 48), outline=INK)
        elif kind == "fort":
            d.regular_polygon((cx, cy, r * 1.2), 6, fill=(120, 90, 70), outline=INK)
        elif kind == "camp":
            d.polygon([(cx - r, cy + r), (cx + r, cy + r), (cx, cy - r)], fill=(214, 120, 60), outline=INK)
        elif kind == "ruin_village":
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 150, 150), outline=INK)
        else:
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(222, 120, 70), outline=INK)
        d.text((X + 36, Y), label, font=f_text, fill=INK)
        Y += int(size / 95)
    Y += 12
    d.text((X, Y), "Points of interest", font=f_head, fill=INK)
    Y += int(size / 70)
    counts = {}
    for l in locs:
        counts[l[2]] = counts.get(l[2], 0) + 1
    for kind in ("tower", "shrine", "bridge", "waterfall", "ruins", "giant_bones", "strange_tree", "wreck",
                 "hidden_valley", "standing_stones", "camp", "strange", "deep_place", "landmark"):
        if kind == "camp":
            n = sum(1 for l in locs if l[2] == "camp" and ":poi/" in l[0])
        else:
            n = counts.get(kind, 0) + (counts.get("interior_dungeon", 0) if kind == "deep_place" else 0) + \
                (counts.get("poi", 0) if kind == "landmark" else 0)
        draw_symbol(d, kind, X + 12, Y + 9, 7, False)
        d.text((X + 36, Y), "%s (%d)" % (kind.replace("_", " "), n), font=f_text, fill=INK)
        Y += int(size / 95)
    draw_symbol(d, "shrine", X + 12, Y + 9, 7, True)
    d.text((X + 36, Y), "a Hearthstone (ringed in gold)", font=f_text, fill=INK)
    Y += int(size / 70)
    d.text((X, Y), "Roads", font=f_head, fill=INK)
    Y += int(size / 70)
    for kind in ("highway", "road", "lane", "track", "causeway", "stair"):
        col, w = ROAD[kind]
        d.line([X, Y + 9, X + 28, Y + 9], fill=col, width=max(1, int(w)))
        if kind == "stair":
            for tx in range(X + 2, X + 28, 5):
                d.line([tx, Y + 4, tx, Y + 14], fill=col, width=1)
        d.text((X + 36, Y), kind, font=f_text, fill=INK)
        Y += int(size / 95)
    Y += 10
    d.regular_polygon((X + 12, Y + 9, 9), 5, fill=(230, 30, 30), outline=(255, 255, 255))
    d.text((X + 36, Y), "the start, facing the Choir; the pale wedge is the first view", font=f_text, fill=INK)
    Y += int(size / 70)
    if coverage and survey["gaps"]:
        d.text((X, Y), "Walkable ground over %d m from anything" % PV.REACH_M, font=f_head, fill=(150, 30, 30))
        Y += int(size / 70)
        for g in survey["gaps"][:8]:
            d.text((X, Y), "%.3f km² at (%d, %d), worst %d m" % (g["area_km2"], g["at"][0], g["at"][1], g["worst_m"]),
                   font=f_text, fill=(120, 30, 30))
            Y += int(size / 105)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    if colours:
        # a paper map for the repository: a palette keeps it a few megabytes smaller
        sheet = sheet.quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    sheet.save(out, optimize=True)
    return survey


def wrap(d, text, fnt, width):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textbbox((0, 0), t, font=fnt)[2] > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    return lines


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--atlas", default=PV.ATLAS_PATH)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--size", type=int, default=2400)
    ap.add_argument("--coverage", action="store_true", help="shade walkable ground far from any location")
    ap.add_argument("--world", default="", help="a built world's directory: draw its heights and water under the atlas")
    ap.add_argument("--colours", type=int, default=0, help="save with a palette of this many colours (smaller file)")
    args = ap.parse_args(argv)
    atlas = PV.Atlas.load(args.atlas)
    s = render(atlas, args.out, args.size, args.coverage, args.world, args.colours)
    print("%s: %d locations (%d places, %d POIs), %.1f km2 walkable, %.1f per km2, furthest %.0f m, "
          "%d gaps over %d m, %.1f km of road" % (
              os.path.relpath(args.out), s["locations"], s["places"], s["pois"], s["walkable_km2"],
              s["per_km2_walkable"], s["max_gap_m"], len(s["gaps"]), PV.REACH_M, s["road_km"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
