"""Procedural alpha textures drawn in Python (PIL + numpy): leaf clusters, grass blades,
petals, berries, fungus. Baking a leaf card in Cycles is wasteful; these are drawn.

Output is an RGBA atlas plus a matching normal and ORM map so every foliage material has
the same three-texture shape as a baked one. The drawing is painterly by construction:
each leaf is a filled silhouette with a soft two-tone gradient, a midrib, a lighter rim
where the sun catches it, and a little per-leaf hue jitter. No photographic detail.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from . import palette as P


# --- small helpers ----------------------------------------------------------------------

def _to8(c):
    """Linear rgb -> 0..255 sRGB tuple."""
    return tuple(int(round(max(0.0, min(1.0, v)) * 255)) for v in P.linear_to_srgb(c[:3]))


def _vary(rng, c, hue=0.02, sat=0.12, val=0.18):
    import colorsys
    s = P.linear_to_srgb(c[:3])
    h, sv, v = colorsys.rgb_to_hsv(*s)
    h = (h + rng.uniform(-hue, hue)) % 1.0
    sv = max(0.0, min(1.0, sv * (1 + rng.uniform(-sat, sat))))
    v = max(0.0, min(1.0, v * (1 + rng.uniform(-val, val))))
    return P.srgb_to_linear(colorsys.hsv_to_rgb(h, sv, v))


def _rot(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


# --- leaf silhouettes -------------------------------------------------------------------

def leaf_outline(shape: str, n: int = 26) -> list[tuple[float, float]]:
    """Unit leaf pointing +y, width ~1, length ~2, centred on the stalk at (0, 0)."""
    pts = []
    for i in range(n + 1):
        t = i / n
        y = t * 2.0
        if shape == "oval":
            w = math.sin(math.pi * t) ** 0.75
        elif shape == "lance":
            w = math.sin(math.pi * t) ** 1.5 * (1.0 - 0.3 * t)
        elif shape == "lobed":  # oak
            w = math.sin(math.pi * t) ** 0.7 * (1.0 + 0.28 * math.sin(t * math.pi * 5.0))
        elif shape == "round":
            w = math.sin(math.pi * t) ** 0.45
        elif shape == "needle":
            w = (1.0 - t) * 0.35 + 0.08
        elif shape == "toothed":  # hawthorn / rowan leaflet
            w = math.sin(math.pi * t) ** 0.8 * (1.0 + 0.18 * math.sin(t * math.pi * 9.0))
        elif shape == "heart":
            w = math.sin(math.pi * (0.12 + 0.88 * t)) ** 0.6
        elif shape == "fern":
            w = math.sin(math.pi * t) ** 0.9 * (1.0 + 0.35 * math.sin(t * math.pi * 12.0))
        else:
            w = math.sin(math.pi * t) ** 0.8
        pts.append((w * 0.5, y))
    back = [(-x, y) for (x, y) in reversed(pts)]
    return pts + back


def _tile(points, pad, img_size):
    """Integer bounding box around `points`, padded and clipped to the image."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x0 = max(0, int(math.floor(min(xs) - pad)))
    y0 = max(0, int(math.floor(min(ys) - pad)))
    x1 = min(img_size[0], int(math.ceil(max(xs) + pad)))
    y1 = min(img_size[1], int(math.ceil(max(ys) + pad)))
    if x1 <= x0 or y1 <= y0:
        return None
    return x0, y0, x1, y1


def _aa_mask(tw, th, shapes):
    """A soft-edged mask: the shape is drawn several times larger and box-filtered down.

    PIL has no anti-aliased polygon or ellipse fill, and a fern pinna is a dozen pixels
    across in its atlas cell, so without this every leaflet is a visible staircase. The
    supersample factor falls as the element grows, because the cost is quadratic and a
    large shape's edge is already a small fraction of it.
    """
    big = max(tw, th)
    ss = 4 if big <= 96 else (3 if big <= 224 else 2)
    img = Image.new("L", (tw * ss, th * ss), 0)
    d = ImageDraw.Draw(img)
    for kind, pts in shapes:
        if kind == "polygon":
            d.polygon([(x * ss, y * ss) for (x, y) in pts], fill=255)
        else:
            x0, y0, x1, y1 = pts
            d.ellipse([x0 * ss, y0 * ss, x1 * ss, y1 * ss], fill=255)
    return img.resize((tw, th), Image.BOX)


def _composite(rgb, alpha, hgt, box, mask_img, colour_img, height_img):
    """Paste one drawn element into the three layers, inside `box` only.

    Working on a local tile rather than the whole atlas is what makes drawing a few hundred
    leaves per cluster affordable: every blur and every array op touches a few thousand
    pixels instead of a quarter of a million."""
    x0, y0, x1, y1 = box
    m = np.asarray(mask_img, dtype=np.float32) / 255.0
    sel = m > 0.5
    if not sel.any():
        return
    region = (x0, y0, x1, y1)
    cur_rgb = np.asarray(rgb.crop(region), dtype=np.uint8).copy()
    np.copyto(cur_rgb, np.asarray(colour_img, dtype=np.uint8), where=sel[..., None])
    rgb.paste(Image.fromarray(cur_rgb), region)
    cur_a = np.asarray(alpha.crop(region), dtype=np.float32)
    alpha.paste(Image.fromarray(np.maximum(cur_a, m * 255.0).astype(np.uint8)), region)
    if height_img is not None:
        cur_h = np.asarray(hgt.crop(region), dtype=np.uint8).copy()
        np.copyto(cur_h, np.asarray(height_img, dtype=np.uint8), where=sel)
        hgt.paste(Image.fromarray(cur_h), region)


def draw_leaf(layers, cx, cy, size, angle, color, shape="oval", rng=None, curl=0.0, vein=0.45,
              rim=0.35, narrow=1.0):
    """Paint one leaf: filled silhouette, soft two-tone gradient, rim light and a midrib.

    `size` is a half-length: the leaf runs 2*size along its axis and about `size` across.
    `narrow` squeezes it across that axis without shortening it, which is how a fern pinna
    or a willow leaf is made from the same outlines as a fat oak one.
    """
    rgb, alpha, hgt = layers
    rng = rng or random.Random(0)
    outline = leaf_outline(shape)
    pts = []
    for (x, y) in outline:
        # gentle curl along the leaf
        xx = x * narrow + curl * (y / 2.0) ** 2
        p = _rot((xx * size, (y - 1.0) * size * 0.5), angle)
        pts.append((cx + p[0], cy - p[1]))
    blur_pad = max(2.0, size * 0.5)
    box = _tile(pts, blur_pad, rgb.size)
    if box is None:
        return
    x0, y0, x1, y1 = box
    tw, th = x1 - x0, y1 - y0
    lpts = [(px - x0, py - y0) for (px, py) in pts]

    lay = _aa_mask(tw, th, [("polygon", lpts)])

    base = _to8(color)
    dark = _to8([c * 0.62 for c in color])
    light = _to8([min(1.0, c * 1.45) for c in color])
    grad = Image.new("RGB", (tw, th), base)
    gd = ImageDraw.Draw(grad)
    # half the leaf darker (light from the top-left of the card)
    gd.polygon(lpts[: len(lpts) // 2 + 1] + [lpts[0]], fill=dark)
    grad = grad.filter(ImageFilter.GaussianBlur(max(1.0, size * 0.18)))
    # rim light near the tip
    tip = _rot((0.0, size * 0.85), angle)
    tx, ty = cx + tip[0] - x0, cy - tip[1] - y0
    rr = max(1.5, size * 0.42 * (0.6 + rim))
    ImageDraw.Draw(grad).ellipse([tx - rr, ty - rr, tx + rr, ty + rr], fill=light)
    grad = grad.filter(ImageFilter.GaussianBlur(max(1.0, size * 0.22)))

    hh = Image.new("L", (tw, th), 128)
    hd = ImageDraw.Draw(hh)
    a = _rot((0.0, -size * 0.5), angle)
    b = _rot((0.0, size * 1.0), angle)
    hd.line([(cx + a[0] - x0, cy - a[1] - y0), (cx + b[0] - x0, cy - b[1] - y0)],
            fill=int(200 * vein + 55), width=max(1, int(size * 0.06)))
    for k in range(3):
        f = 0.25 + 0.25 * k
        p0 = _rot((0.0, (f * 1.5 - 0.5) * size), angle)
        for sgn in (-1, 1):
            p1 = _rot((sgn * size * 0.35 * (1 - f * 0.5), (f * 1.5 - 0.15) * size), angle)
            hd.line([(cx + p0[0] - x0, cy - p0[1] - y0), (cx + p1[0] - x0, cy - p1[1] - y0)],
                    fill=int(170 * vein + 55), width=1)
    hh = hh.filter(ImageFilter.GaussianBlur(max(0.8, size * 0.05)))
    _composite(rgb, alpha, hgt, box, lay, grad, hh)


# --- normal / ORM from a height map -------------------------------------------------------

def normal_from_height(height: np.ndarray, strength: float = 1.6) -> np.ndarray:
    h = height.astype(np.float32) / 255.0
    gx = np.zeros_like(h)
    gy = np.zeros_like(h)
    gx[:, 1:-1] = (h[:, 2:] - h[:, :-2]) * 0.5
    gy[1:-1, :] = (h[2:, :] - h[:-2, :]) * 0.5
    nx = -gx * strength
    ny = gy * strength  # OpenGL +Y up
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def orm_from(alpha: np.ndarray, height: np.ndarray, roughness: float = 0.72, ao_strength: float = 0.35) -> np.ndarray:
    a = alpha.astype(np.float32) / 255.0
    # cheap AO: blurred coverage - the middle of a dense cluster is darker
    cov = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), dtype=np.float32) / 255.0
    ao = np.clip(1.0 - cov * ao_strength, 0.0, 1.0)
    h = height.astype(np.float32) / 255.0
    rough = np.clip(roughness + (0.5 - h) * 0.12, 0.05, 1.0)
    met = np.zeros_like(ao)
    return (np.dstack([ao, rough, met]) * 255).astype(np.uint8)


def save_set(out_dir, prefix: str, rgb: Image.Image, alpha: Image.Image, height: Image.Image,
             roughness: float = 0.72, normal_strength: float = 1.6, size: int | None = None) -> dict:
    """Write <prefix>_albedo.png (RGBA), _normal.png, _orm.png; returns {kind: filename}."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    a = np.asarray(alpha)
    h = np.asarray(height)
    alb = Image.merge("RGBA", (*rgb.split(), alpha))
    nrm = Image.fromarray(normal_from_height(h, normal_strength))
    orm = Image.fromarray(orm_from(a, h, roughness))
    if size and size != alb.size[0]:
        alb = alb.resize((size, size), Image.LANCZOS)
        nrm = nrm.resize((size, size), Image.LANCZOS)
    small = max(64, (size or alb.size[0]) // 2)
    orm = orm.resize((small, small), Image.LANCZOS)
    names = {"albedo": "%s_albedo.png" % prefix, "normal": "%s_normal.png" % prefix, "orm": "%s_orm.png" % prefix}
    alb.save(out_dir / names["albedo"], optimize=True)
    nrm.save(out_dir / names["normal"], optimize=True)
    orm.save(out_dir / names["orm"], optimize=True)
    return names


def new_layers(size: int, bg=(0, 0, 0)):
    return (Image.new("RGB", (size, size), bg), Image.new("L", (size, size), 0), Image.new("L", (size, size), 128))


# --- atlases ------------------------------------------------------------------------------

def leaf_cluster_atlas(out_dir, prefix: str, color, shapes=("oval",), seed: int = 0, size: int = 512,
                       cells: int = 2, leaves_per_cell: int = 70, leaf_scale: float = 0.15,
                       autumn=None, autumn_amount: float = 0.0, fruit=None, fruit_r: float = 0.0,
                       fruit_count: int = 0, droop: float = 0.0, roughness: float = 0.7,
                       lobes: int = 4, spread: float = 0.40, twigs: bool = True, twig_color=None,
                       depth_shade: float = 0.55, row_tones=None) -> dict:
    """A `cells`x`cells` atlas of leaf clusters; every card UV picks one cell.

    `row_tones`, one (r, g, b) multiplier per image row of cells (top row first), paints each
    row in its own light: the grown trees give a clump on the sunlit rim of the crown the top
    row and one deep inside it the bottom, so a crown is shaded as one mass.

    A cluster is built as a few overlapping *lobes* of many small leaves, drawn back to
    front with the back leaves darkened, so the card reads as a volume with a ragged
    silhouette rather than a flat blob. 2-3 cluster shapes per species come from `shapes`.
    """
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            shape = shapes[(cy * cells + cx) % len(shapes)]
            cxx, cyy = ox + cs * 0.5, oy + cs * 0.5
            # lobe centres: an irregular ring plus the middle, so the outline is ragged
            centres = [(cxx + rng.uniform(-0.06, 0.06) * cs, cyy + rng.uniform(-0.06, 0.06) * cs, 1.0)]
            for li in range(lobes):
                a = math.tau * (li + rng.uniform(-0.18, 0.18)) / lobes
                d = cs * spread * rng.uniform(0.55, 1.0)
                centres.append((cxx + math.cos(a) * d, cyy + math.sin(a) * d * 0.88 + droop * cs * 0.1,
                                rng.uniform(0.62, 1.0)))
            if twigs:
                tw = twig_color if twig_color is not None else [c * 0.45 for c in color]
                for (px, py, w) in centres[1:]:
                    _blade(rgb, alpha, hgt, cxx, cyy, math.hypot(px - cxx, py - cyy),
                           (px - cxx), cs * 0.006, tw, bend=0.1, taper=0.55, rng=rng)
            n = leaves_per_cell + rng.randint(-6, 6)
            # draw in depth order: back (darker, smaller) first
            leaves = []
            for i in range(n):
                px0, py0, w = centres[rng.randrange(len(centres))]
                t = rng.random() ** 0.6
                a = rng.uniform(0, math.tau)
                px = px0 + math.cos(a) * t * cs * 0.20 * w
                py = py0 + math.sin(a) * t * cs * 0.18 * w + droop * t * cs * 0.12
                depth = rng.random()
                leaves.append((depth, px, py, w, t))
            leaves.sort()
            for (depth, px, py, w, t) in leaves:
                col = color
                if autumn is not None and rng.random() < autumn_amount:
                    col = autumn
                col = _vary(rng, col, hue=0.025, sat=0.14, val=0.16)
                # back leaves sit in shadow; front leaves catch the light
                f = depth_shade + (1.0 - depth_shade) * depth
                col = [c * f for c in col]
                if row_tones:
                    tone = row_tones[cy % len(row_tones)]
                    col = [c * t for c, t in zip(col, tone)]
                sz = cs * leaf_scale * rng.uniform(0.62, 1.25) * (0.8 + 0.3 * depth)
                ang = rng.uniform(0, math.tau)
                draw_leaf((rgb, alpha, hgt), px, py, sz, ang, col, shape=shape, rng=rng,
                          curl=rng.uniform(-0.3, 0.3), rim=0.3 + 0.4 * depth)
            if fruit is not None and fruit_count:
                for i in range(fruit_count):
                    px0, py0, w = centres[rng.randrange(len(centres))]
                    a = rng.uniform(0, math.tau)
                    t = rng.random() ** 0.5
                    px = px0 + math.cos(a) * t * cs * 0.16
                    py = py0 + math.sin(a) * t * cs * 0.14 + cs * 0.03
                    r = cs * fruit_r * rng.uniform(0.85, 1.15)
                    _blob(rgb, alpha, hgt, px, py, r, _vary(rng, fruit, hue=0.01, sat=0.1, val=0.12))
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def _blob(rgb, alpha, hgt, cx, cy, r, color):
    """A round element with a highlight: a berry, an apple, a floret."""
    box = _tile([(cx - r, cy - r), (cx + r, cy + r)], max(2.0, r * 0.8), rgb.size)
    if box is None:
        return
    x0, y0, x1, y1 = box
    tw, th = x1 - x0, y1 - y0
    lx, ly = cx - x0, cy - y0
    lay = _aa_mask(tw, th, [("ellipse", (lx - r, ly - r, lx + r, ly + r))])
    base = _to8(color)
    light = _to8([min(1.0, c * 1.7) for c in color])
    grad = Image.new("RGB", (tw, th), base)
    ImageDraw.Draw(grad).ellipse([lx - r * 0.85, ly - r * 0.9, lx + r * 0.1, ly - r * 0.05], fill=light)
    grad = grad.filter(ImageFilter.GaussianBlur(max(1.0, r * 0.45)))
    yy, xx = np.mgrid[0:th, 0:tw]
    bulge = np.clip(1.0 - (((xx - lx) ** 2 + (yy - ly) ** 2) / max(1.0, r * r)), 0.0, 1.0)
    hh = Image.fromarray((128 + bulge * 110).astype(np.uint8))
    _composite(rgb, alpha, hgt, box, lay, grad, hh)


def _margin_bleed(rgb, alpha, iterations: int = 3) -> None:
    """Grow opaque colour into transparent texels so mipmaps do not bleed black."""
    a = np.asarray(alpha, dtype=np.uint8)
    c = np.asarray(rgb, dtype=np.uint8).copy()
    mask = a > 8
    for _ in range(iterations):
        filled = mask.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(np.roll(c, dy, 0), dx, 1)
            shm = np.roll(np.roll(mask, dy, 0), dx, 1)
            take = shm & ~filled
            c[take] = sh[take]
            filled |= shm
        mask = filled
    rgb.paste(Image.fromarray(c))


def blade_atlas(out_dir, prefix: str, colors, seed: int = 0, size: int = 512, cells: int = 2,
                blades: int = 26, width: float = 0.035, lean: float = 0.35, tip_taper: float = 0.85,
                seed_head=None, roughness: float = 0.75, bend: float = 0.5, tip_color=None) -> dict:
    """Grass / reed / cottongrass blades rising from the bottom of each atlas cell. With
    `tip_color`, one blade in three is dried toward it over its upper half (a painted clump is
    green at the root and straw at some tips, not one green)."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            for i in range(blades + rng.randint(-4, 4)):
                x0 = ox + cs * rng.uniform(0.08, 0.92)
                y0 = oy + cs * 0.99
                hgt_px = cs * rng.uniform(0.45, 0.95)
                lean_x = rng.uniform(-lean, lean) * hgt_px
                w = cs * width * rng.uniform(0.7, 1.35)
                col = _vary(rng, colors[rng.randrange(len(colors))], hue=0.025, sat=0.2, val=0.25)
                tip = _vary(rng, tip_color, val=0.15) if tip_color is not None and rng.random() < 0.16 else None
                _blade(rgb, alpha, hgt, x0, y0, hgt_px, lean_x, w, col, bend=bend, taper=tip_taper, rng=rng,
                       tip=tip)
                # a quarter of thirty blades carry a head; with more, finer blades, the same count
                if seed_head is not None and rng.random() < 0.25 * min(1.0, 30.0 / max(blades, 1)):
                    tipx = x0 + lean_x
                    tipy = y0 - hgt_px
                    _blob(rgb, alpha, hgt, tipx, tipy, cs * 0.018, _vary(rng, seed_head))
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def _blade(rgb, alpha, hgt, x0, y0, h, lean_x, w, color, bend=0.5, taper=0.85, rng=None, segments=8, tip=None):
    rng = rng or random.Random(0)
    left, right, mid = [], [], []
    for i in range(segments + 1):
        t = i / segments
        x = x0 + lean_x * (t ** (1 + bend))
        y = y0 - h * t
        ww = w * (1.0 - taper * t) + w * 0.12
        left.append((x - ww, y))
        right.append((x + ww, y))
        mid.append((x, y))
    # Blades come to a point. Holding a floor width to the last segment ended every reed
    # in a blunt square, and a bed of squared-off strips does not read as reeds at any
    # distance; the tip is the one part of a blade the eye checks.
    poly = left[:-1] + [mid[-1]] + list(reversed(right[:-1]))
    box = _tile(poly, max(2.0, w * 2.0), rgb.size)
    if box is None:
        return
    x0, y0, x1, y1 = box
    tw, th = x1 - x0, y1 - y0
    lpoly = [(px - x0, py - y0) for (px, py) in poly]
    lmid = [(px - x0, py - y0) for (px, py) in mid]
    lay = _aa_mask(tw, th, [("polygon", lpoly)])
    base = _to8(color)
    dark = _to8([c * 0.55 for c in color])
    light = _to8([min(1.0, c * 1.5) for c in color])
    grad = Image.new("RGB", (tw, th), dark)
    gd = ImageDraw.Draw(grad)
    gd.line(lmid, fill=base, width=max(1, int(w * 1.6)))
    gd.line(lmid[len(lmid) // 2:], fill=light, width=max(1, int(w * 0.9)))
    if tip is not None:
        # dried from the top: the last third of the blade in the tip's straw
        gd.line(lmid[3 * len(lmid) // 4:], fill=_to8(tip), width=max(1, int(w * 1.3)))
    grad = grad.filter(ImageFilter.GaussianBlur(max(0.8, w * 0.5)))
    rib = Image.new("L", (tw, th), 0)
    ImageDraw.Draw(rib).line(lmid, fill=230, width=max(1, int(w)))
    rib = rib.filter(ImageFilter.GaussianBlur(max(0.8, w * 0.6)))
    hh = Image.fromarray((110 + np.asarray(rib, dtype=np.float32) * 0.5).astype(np.uint8))
    _composite(rgb, alpha, hgt, box, lay, grad, hh)


def flower_atlas(out_dir, prefix: str, leaf_color, flower_color, seed: int = 0, size: int = 512, cells: int = 2,
                 form: str = "spike", stems: int = 7, leaf_shape: str = "lance", second_color=None,
                 eye_color=None,
                 roughness: float = 0.7) -> dict:
    """Flowering plants: foxglove/heather spikes, poppy/marigold heads, cow parsley umbels."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            # basal leaves
            for i in range(9):
                px = ox + cs * rng.uniform(0.2, 0.8)
                py = oy + cs * rng.uniform(0.82, 0.98)
                draw_leaf((rgb, alpha, hgt), px, py, cs * rng.uniform(0.1, 0.17), rng.uniform(-2.6, -0.5),
                          _vary(rng, leaf_color), shape=leaf_shape, rng=rng, curl=rng.uniform(-0.2, 0.2))
            for s in range(stems + rng.randint(-1, 2)):
                x0 = ox + cs * rng.uniform(0.15, 0.85)
                y0 = oy + cs * 0.98
                h = cs * rng.uniform(0.5, 0.92)
                lean_x = rng.uniform(-0.25, 0.25) * h
                stem_col = [c * 0.75 for c in leaf_color]
                _blade(rgb, alpha, hgt, x0, y0, h, lean_x, cs * 0.008, stem_col, bend=0.4, taper=0.4, rng=rng)
                tipx, tipy = x0 + lean_x, y0 - h
                fc = flower_color if (second_color is None or rng.random() < 0.65) else second_color
                if form == "spike":
                    for k in range(9):
                        t = k / 9.0
                        r = cs * 0.022 * (1.0 - 0.45 * t)
                        bx = tipx + rng.uniform(-1, 1) * cs * 0.012 + lean_x * 0.06
                        by = tipy + t * h * 0.42
                        _blob(rgb, alpha, hgt, bx, by, r, _vary(rng, fc, hue=0.015, sat=0.12, val=0.15))
                elif form == "head":
                    r = cs * rng.uniform(0.035, 0.055)
                    for k in range(6):
                        a = math.tau * k / 6 + rng.uniform(-0.2, 0.2)
                        draw_leaf((rgb, alpha, hgt), tipx + math.cos(a) * r * 0.5, tipy + math.sin(a) * r * 0.5,
                                  r * 1.5, a + math.pi / 2, _vary(rng, fc, hue=0.01, sat=0.1, val=0.15),
                                  shape="round", rng=rng)
                    # the eye: dark, or its own colour (an ox-eye daisy's yellow)
                    eye = [c * 0.3 for c in fc] if eye_color is None else list(eye_color)
                    _blob(rgb, alpha, hgt, tipx, tipy, r * (0.32 if eye_color is None else 0.42), eye)
                elif form == "umbel":
                    for k in range(16):
                        a = math.tau * k / 16
                        rr = cs * rng.uniform(0.03, 0.06)
                        _blob(rgb, alpha, hgt, tipx + math.cos(a) * rr, tipy + math.sin(a) * rr * 0.5,
                              cs * 0.009, _vary(rng, fc, hue=0.005, sat=0.1, val=0.12))
                elif form == "berry":
                    for k in range(7):
                        a = math.tau * k / 7
                        rr = cs * 0.022
                        _blob(rgb, alpha, hgt, tipx + math.cos(a) * rr, tipy + math.sin(a) * rr,
                              cs * 0.014, _vary(rng, fc, hue=0.01, sat=0.1, val=0.15))
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def frond_atlas(out_dir, prefix: str, color, seed: int = 0, size: int = 512, cells: int = 2,
                fronds: int = 5, pinnae: int = 13, shape: str = "lance", curl: float = 0.5,
                roughness: float = 0.72, tip_color=None) -> dict:
    """Ferns and bracken: arching fronds of paired pinnae."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            for f in range(fronds + rng.randint(-1, 2)):
                x0 = ox + cs * rng.uniform(0.25, 0.75)
                y0 = oy + cs * 0.97
                h = cs * rng.uniform(0.55, 0.95)
                lean = rng.uniform(-0.55, 0.55)
                col = _vary(rng, color, hue=0.02, sat=0.15, val=0.2)
                pts = []
                for i in range(pinnae + 1):
                    t = i / pinnae
                    x = x0 + lean * h * (t ** 1.6)
                    y = y0 - h * t
                    pts.append((x, y, t))
                _blade(rgb, alpha, hgt, x0, y0, h, lean * h, cs * 0.008, [c * 0.8 for c in col], bend=0.6, taper=0.6, rng=rng)
                for i, (x, y, t) in enumerate(pts[1:]):
                    # Longest pinnae low on the frond, narrowing to a point at the tip. This
                    # ran the other way round, which gives a bottle brush: the frond grew
                    # wider the higher it went and ended in a blunt fan.
                    # draw_leaf's size is a half-length, so a pinna is 2*ln long and ln
                    # wide. At the old 0.105 that was three times the rachis spacing and
                    # the leaflets fused into one strap; they have to be able to show gaps.
                    ln = cs * 0.075 * math.sin(math.pi * (0.15 + 0.85 * t)) * rng.uniform(0.82, 1.12)
                    if ln < 1.5:
                        continue
                    c2 = col if tip_color is None or t < 0.7 else _vary(rng, tip_color)
                    # The rachis leans, so its pinnae lean with it; and they sweep forward
                    # towards the tip rather than standing square to the stalk. Before this
                    # one side of every frond pointed down and the other up, which is what
                    # made a fern read as a stack of blocks instead of a feather.
                    rach = -math.atan2(lean * 1.6 * (t ** 0.6), 1.0)
                    for sgn in (-1, 1):
                        # Pinnae alternate rather than pairing exactly, and each sits a
                        # little along the rachis from its partner.
                        stagger = (0.5 * sgn + rng.uniform(-0.25, 0.25)) * (h / pinnae)
                        ang = rach + sgn * (1.15 - 0.45 * t)
                        draw_leaf((rgb, alpha, hgt), x, y + stagger, ln, ang, c2, shape=shape,
                                  rng=rng, curl=sgn * curl * 0.4, narrow=0.42, vein=0.25)
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def leaf_strand_atlas(out_dir, prefix: str, color, seed: int = 0, size: int = 512, cells: int = 2,
                      strands: int = 7, leaf_scale: float = 0.05, row_tones=None, roughness: float = 0.7) -> dict:
    """Hanging strands of narrow leaves (a weeping willow's curtain): each cell is a few whips
    falling from its top edge, a slender leaf every few pixels down them, pointing down."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            tone = row_tones[cy % len(row_tones)] if row_tones else (1.0, 1.0, 1.0)
            for i in range(strands + rng.randint(-1, 2)):
                x0 = ox + cs * (0.12 + 0.76 * (i + rng.uniform(0.2, 0.8)) / strands)
                length = cs * rng.uniform(0.7, 0.97)
                sway = rng.uniform(-0.08, 0.08) * cs
                k = 0
                y = oy + cs * 0.02
                while y < oy + length:
                    t = (y - oy) / length
                    x = x0 + sway * t * t
                    depth = rng.random()
                    col = _vary(rng, color, hue=0.02, sat=0.12, val=0.15)
                    col = [c * (0.6 + 0.4 * depth) * tn for c, tn in zip(col, tone)]
                    side = -1 if k % 2 else 1
                    ang = math.pi / 2 + side * rng.uniform(0.25, 0.6)
                    sz = cs * leaf_scale * rng.uniform(0.8, 1.2) * (1.0 - 0.35 * t)
                    draw_leaf((rgb, alpha, hgt), x + side * sz * 0.5, y + sz * 0.6, sz, ang, col, shape="lance",
                              rng=rng, curl=rng.uniform(-0.2, 0.2), rim=0.3 + 0.4 * depth, narrow=0.45)
                    y += cs * leaf_scale * rng.uniform(0.35, 0.6)
                    k += 1
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def moss_strand_atlas(out_dir, prefix: str, color, seed: int = 0, size: int = 512, cells: int = 2,
                      strands: int = 40, roughness: float = 0.85) -> dict:
    """Hanging moss / lichen beards: strands falling from the top of the cell."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            for i in range(strands + rng.randint(-6, 6)):
                x0 = ox + cs * rng.uniform(0.05, 0.95)
                y0 = oy + cs * 0.02
                h = cs * rng.uniform(0.35, 0.95)
                col = _vary(rng, color, hue=0.02, sat=0.2, val=0.3)
                _blade(rgb, alpha, hgt, x0, y0 + h, h, rng.uniform(-0.1, 0.1) * h, cs * rng.uniform(0.006, 0.013),
                       col, bend=0.2, taper=0.5, rng=rng)
                # little tufts along the strand
                for k in range(int(h / (cs * 0.09))):
                    ty = y0 + h * (0.15 + 0.85 * rng.random())
                    _blob(rgb, alpha, hgt, x0 + rng.uniform(-2, 2), ty, cs * 0.011, [c * 1.1 for c in col])
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def bracket_atlas(out_dir, prefix: str, color, rim_color=None, seed: int = 0, size: int = 256, cells: int = 2,
                  roughness: float = 0.8) -> dict:
    """Bracket fungus shelves seen from the front (for a simple card + a small mesh)."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            for i in range(4):
                r = cs * rng.uniform(0.18, 0.34)
                px = ox + cs * rng.uniform(0.3, 0.7)
                py = oy + cs * rng.uniform(0.35, 0.8)
                col = _vary(rng, color, hue=0.02, sat=0.15, val=0.2)
                lay = Image.new("L", rgb.size, 0)
                ImageDraw.Draw(lay).pieslice([px - r, py - r * 0.75, px + r, py + r * 0.75], 180, 360, fill=255)
                base = _to8(col)
                grad = Image.new("RGB", rgb.size, base)
                gd = ImageDraw.Draw(grad)
                for k in range(4):
                    kr = r * (1 - 0.2 * k)
                    shade = _to8([c * (0.7 + 0.12 * k) for c in col])
                    gd.arc([px - kr, py - kr * 0.75, px + kr, py + kr * 0.75], 180, 360, fill=shade, width=max(1, int(r * 0.1)))
                if rim_color is not None:
                    gd.arc([px - r, py - r * 0.75, px + r, py + r * 0.75], 180, 360, fill=_to8(rim_color), width=max(1, int(r * 0.09)))
                grad = grad.filter(ImageFilter.GaussianBlur(max(1.0, r * 0.08)))
                m = np.asarray(lay, dtype=np.float32) / 255.0
                rgb_a = np.asarray(rgb, dtype=np.float32)
                np.copyto(rgb_a, np.asarray(grad, dtype=np.float32), where=(m[..., None] > 0.5))
                rgb.paste(Image.fromarray(rgb_a.astype(np.uint8)))
                a = np.maximum(np.asarray(alpha, dtype=np.float32), m * 255)
                alpha.paste(Image.fromarray(a.astype(np.uint8)))
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)


def pad_atlas(out_dir, prefix: str, color, flower_color=None, seed: int = 0, size: int = 256, cells: int = 2,
              roughness: float = 0.35) -> dict:
    """Waterlily pads seen from above: a notched disc with radial veins."""
    rng = random.Random(seed)
    rgb, alpha, hgt = new_layers(size)
    cs = size // cells
    for cy in range(cells):
        for cx in range(cells):
            ox, oy = cx * cs, cy * cs
            px, py = ox + cs * 0.5, oy + cs * 0.5
            r = cs * rng.uniform(0.36, 0.45)
            col = _vary(rng, color, hue=0.02, sat=0.12, val=0.15)
            lay = Image.new("L", rgb.size, 0)
            d = ImageDraw.Draw(lay)
            d.ellipse([px - r, py - r, px + r, py + r], fill=255)
            a0 = rng.uniform(0, 360)
            # the pad's characteristic notch: a narrow wedge cut to the centre
            d.pieslice([px - r * 1.05, py - r * 1.05, px + r * 1.05, py + r * 1.05], a0, a0 + 13, fill=0)
            base = _to8(col)
            grad = Image.new("RGB", rgb.size, base)
            gd = ImageDraw.Draw(grad)
            gd.ellipse([px - r * 0.55, py - r * 0.6, px + r * 0.3, py + r * 0.2], fill=_to8([min(1.0, c * 1.35) for c in col]))
            for k in range(12):
                a = math.tau * k / 12
                gd.line([(px, py), (px + math.cos(a) * r, py + math.sin(a) * r)], fill=_to8([c * 0.7 for c in col]), width=1)
            grad = grad.filter(ImageFilter.GaussianBlur(max(1.0, r * 0.12)))
            m = np.asarray(lay, dtype=np.float32) / 255.0
            rgb_a = np.asarray(rgb, dtype=np.float32)
            np.copyto(rgb_a, np.asarray(grad, dtype=np.float32), where=(m[..., None] > 0.5))
            rgb.paste(Image.fromarray(rgb_a.astype(np.uint8)))
            al = np.maximum(np.asarray(alpha, dtype=np.float32), m * 255)
            alpha.paste(Image.fromarray(al.astype(np.uint8)))
            if flower_color is not None and rng.random() < 0.5:
                fx, fy = px + r * 0.45, py - r * 0.35
                for k in range(8):
                    a = math.tau * k / 8
                    draw_leaf((rgb, alpha, hgt), fx, fy, cs * 0.07, a, _vary(rng, flower_color), shape="round", rng=rng)
    _margin_bleed(rgb, alpha)
    return save_set(out_dir, prefix, rgb, alpha, hgt, roughness=roughness)
