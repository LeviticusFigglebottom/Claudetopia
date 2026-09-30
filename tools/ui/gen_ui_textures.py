#!/usr/bin/env python3
"""Wickmere UI texture generation — "tended paper".

Draws every UI texture procedurally with PIL/numpy: parchment panels with fibrous
noise, stains and a vignette; brass and dark-oak nine-patch frames; button states;
sliders, checkboxes, tabs, tooltips, scrollbars, focus rings; progress-bar fills;
the compass strip and its cardinal glyphs; map marker glyphs for every place and
POI kind; a hand-drawn icon set; and the cursor.

Nothing is hand-placed pixel art: shapes are polylines drawn with a wobbling,
pressure-varying nib at 4x supersample, broken up by an ink-grain field, then
downsampled. Deep places get a cold-bronze / ash variant of every chrome piece.

Usage:
    python3 tools/ui/gen_ui_textures.py                 # write game/assets/ui/
    python3 tools/ui/gen_ui_textures.py --out /tmp/ui   # elsewhere
    python3 tools/ui/gen_ui_textures.py --only icons    # one group
    python3 tools/ui/gen_ui_textures.py --only items    # the belt's painted item art (gen_item_art.py)
"""
from __future__ import annotations

import argparse
import sys
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
OUT_DEFAULT = ROOT / "game" / "assets" / "ui"
FONT_DIR = ROOT / "game" / "assets" / "fonts"
SS = 4  # supersampling factor for every drawn shape

# --------------------------------------------------------------------------------------
# palettes. "warm" is the settled world (parchment, brass, dark oak); "deep" is what the
# UI swaps to in deep places and dangerous regions (ashen paper, cold bronze, ash ink).
# --------------------------------------------------------------------------------------

PALETTES = {
    "warm": {
        "paper_hi": (236, 223, 196),
        "paper_lo": (210, 192, 158),
        "paper_edge": (166, 142, 104),
        "stain": (150, 118, 72),
        "ink": (44, 34, 26),
        "ink_soft": (92, 74, 56),
        "metal": (158, 124, 58),        # brass, antique rather than polished
        "metal_hi": (206, 176, 104),
        "metal_lo": (82, 60, 22),
        "wood": (74, 53, 36),           # dark oak
        "wood_hi": (112, 82, 54),
        "wood_lo": (38, 26, 17),
        "accent": (178, 58, 46),
    },
    "deep": {
        "paper_hi": (198, 195, 187),
        "paper_lo": (168, 165, 157),
        "paper_edge": (116, 114, 108),
        "stain": (96, 96, 92),
        "ink": (38, 40, 40),
        "ink_soft": (86, 90, 90),
        "metal": (104, 118, 112),       # cold bronze
        "metal_hi": (150, 166, 158),
        "metal_lo": (46, 56, 54),
        "wood": (74, 74, 70),           # ash
        "wood_hi": (106, 106, 100),
        "wood_lo": (40, 40, 38),
        "accent": (120, 146, 158),
    },
}

BAR_COLOURS = {
    "health": ((168, 68, 46), (110, 38, 28)),        # red ochre
    "stamina": ((150, 160, 62), (96, 104, 34)),      # green gold
    "mana": ((74, 127, 168), (38, 74, 110)),         # lantern blue
    "poise": ((232, 226, 210), (168, 160, 142)),     # bone white
    "boss": ((176, 138, 62), (104, 76, 28)),         # bronze
    "xp": ((200, 162, 78), (128, 96, 40)),
}


# --------------------------------------------------------------------------------------
# noise helpers
# --------------------------------------------------------------------------------------

def _upscale(a: np.ndarray, w: int, h: int) -> np.ndarray:
    img = Image.fromarray(a.astype(np.float32), mode="F")
    return np.asarray(img.resize((w, h), Image.BICUBIC), dtype=np.float32)


def fbm(w: int, h: int, rng: np.random.Generator, octaves: int = 5, base: int = 4,
        persistence: float = 0.5, aniso: float = 1.0, wrap: bool = False) -> np.ndarray:
    """Fractal value noise in 0..1. `aniso` > 1 stretches features horizontally.
    `wrap` makes the field seamless so it can tile (nine-patch centres)."""
    out = np.zeros((h, w), np.float32)
    amp, total, cells = 1.0, 0.0, base
    for _ in range(octaves):
        cx = max(2, int(round(cells / aniso)))
        cy = max(2, int(round(cells * aniso)))
        grid = rng.random((cy + 1, cx + 1)).astype(np.float32)
        if wrap:
            grid[-1, :] = grid[0, :]
            grid[:, -1] = grid[:, 0]
        out += amp * _upscale(grid, w, h)
        total += amp
        amp *= persistence
        cells *= 2
    n = out / max(total, 1e-6)
    lo, hi = float(n.min()), float(n.max())
    return (n - lo) / max(hi - lo, 1e-6)


def radial(w: int, h: int, power: float = 2.0) -> np.ndarray:
    """0 at the centre, 1 at the corners."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xs - (w - 1) / 2.0) / max(w / 2.0, 1.0)
    dy = (ys - (h - 1) / 2.0) / max(h / 2.0, 1.0)
    return np.clip(np.sqrt(dx * dx + dy * dy) / math.sqrt(2.0), 0.0, 1.0) ** power


def _lerp_rgb(a, b, t: np.ndarray) -> np.ndarray:
    t = t[..., None]
    return np.asarray(a, np.float32) * (1.0 - t) + np.asarray(b, np.float32) * t


def to_image(rgb: np.ndarray, alpha: np.ndarray | None = None) -> Image.Image:
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        alpha = np.full(rgb.shape[:2], 255, np.uint8)
    else:
        alpha = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


# --------------------------------------------------------------------------------------
# parchment
# --------------------------------------------------------------------------------------

def parchment(w: int, h: int, rng: np.random.Generator, pal: dict, *, vignette: float = 0.30,
              stains: int = 3, fibre: float = 0.16, edge: float = 0.0,
              wrap: bool = False, tone_amount: float = 1.0) -> Image.Image:
    """A sheet of fibrous, faintly stained paper. `tone_amount` flattens the large-scale
    blotching, which matters for a nine-patch centre that will be stretched a long way."""
    blotch = fbm(w, h, rng, octaves=5, base=3, persistence=0.55, wrap=wrap)
    tone = np.clip((blotch * 0.9 + 0.05) * tone_amount + (1.0 - tone_amount) * 0.35, 0.0, 1.0)
    rgb = _lerp_rgb(pal["paper_hi"], pal["paper_lo"], tone)

    # fibres: long thin streaks both ways, a paper grain rather than a pattern
    for aniso, amount in ((6.0, fibre), (1.0 / 6.0, fibre * 0.6)):
        f = fbm(w, h, rng, octaves=4, base=6, persistence=0.6, aniso=aniso, wrap=wrap)
        rgb *= (1.0 - amount * 0.5 + amount * f)[..., None]

    # stains: soft irregular blooms of a darker tea colour
    for _ in range(stains):
        cx, cy = rng.random() * w, rng.random() * h
        rad = (0.14 + 0.26 * rng.random()) * max(w, h)
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / rad
        wobble = fbm(w, h, rng, octaves=3, base=3, persistence=0.6) * 0.55 + 0.72
        mask = np.clip(1.0 - d / wobble, 0.0, 1.0) ** 1.8
        mask *= 0.10 + 0.10 * rng.random()
        rgb = rgb * (1.0 - mask[..., None]) + np.asarray(pal["stain"], np.float32) * mask[..., None]

    if vignette > 0.0:
        v = radial(w, h, 1.7) * vignette
        rgb = rgb * (1.0 - v[..., None]) + np.asarray(pal["paper_edge"], np.float32) * v[..., None]

    if edge > 0.0:  # darkened, slightly ragged border as if the sheet were cut and handled
        ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
        b = np.minimum(np.minimum(xs, w - 1 - xs), np.minimum(ys, h - 1 - ys))
        band = np.clip(1.0 - b / max(edge * min(w, h), 1.0), 0.0, 1.0) ** 2
        band *= 0.35 + 0.35 * fbm(w, h, rng, octaves=3, base=8, persistence=0.6)
        rgb = rgb * (1.0 - band[..., None]) + np.asarray(pal["paper_edge"], np.float32) * band[..., None]

    grain = (rng.random((h, w)).astype(np.float32) - 0.5) * 7.0
    return to_image(rgb + grain[..., None])


# --------------------------------------------------------------------------------------
# the nib: wobbling, pressure-varying ink strokes
# --------------------------------------------------------------------------------------

class Nib:
    """Draws on an RGBA layer at SS scale with a hand-held feel."""

    def __init__(self, w: int, h: int, rng: np.random.Generator):
        self.w, self.h = w * SS, h * SS
        self.img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.rng = rng

    # -- geometry helpers (all inputs are in 0..1 unit space) --------------------------
    def _p(self, pt) -> tuple[float, float]:
        return pt[0] * self.w, pt[1] * self.h

    def _wobble(self, pts, jitter: float, steps_per_seg: int = 9):
        """Resample a polyline and push each sample along a smooth random walk."""
        out = []
        drift = np.array([0.0, 0.0])
        amp = jitter * SS
        for i in range(len(pts) - 1):
            a, b = np.array(self._p(pts[i])), np.array(self._p(pts[i + 1]))
            seg = max(2, int(steps_per_seg * max(1.0, np.linalg.norm(b - a) / (0.1 * self.w))))
            for s in range(seg):
                t = s / seg
                drift = drift * 0.86 + self.rng.normal(0.0, amp * 0.5, 2)
                drift = np.clip(drift, -amp * 2.0, amp * 2.0)
                out.append(tuple(a + (b - a) * t + drift))
        out.append(tuple(np.array(self._p(pts[-1])) + drift))
        return out

    def stroke(self, pts, width: float, colour, *, jitter: float = 0.0028,
               taper: float = 0.35, closed: bool = False, alpha: int = 255):
        """A polyline in unit space. `width` is a fraction of the texture's short side."""
        if closed:
            pts = list(pts) + [pts[0]]
        path = self._wobble(pts, jitter)
        base = width * min(self.w, self.h)
        n = len(path)
        pressure = 1.0 + 0.16 * np.sin(np.linspace(0, self.rng.random() * 6.0 + 3.0, n))
        for i, (x, y) in enumerate(path):
            t = i / max(n - 1, 1)
            ends = 1.0 if closed else (1.0 - taper * (1.0 - min(t, 1.0 - t) * 4.0) if min(t, 1.0 - t) < 0.25 else 1.0)
            r = max(0.55, base * 0.5 * pressure[i] * max(ends, 0.25))
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=(*colour, alpha))

    def poly(self, pts, colour, *, alpha: int = 255, jitter: float = 0.0022):
        path = self._wobble(list(pts) + [pts[0]], jitter)
        self.d.polygon(path, fill=(*colour, alpha))

    def circle(self, c, r: float, colour, *, width: float = 0.03, fill=None, segments: int = 44,
               jitter: float = 0.0022, squash: float = 1.0, alpha: int = 255):
        pts = [(c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * squash)
               for a in np.linspace(0, math.tau, segments, endpoint=False)]
        if fill is not None:
            self.poly(pts, fill, jitter=jitter, alpha=alpha)
        if width > 0:
            self.stroke(pts, width, colour, closed=True, jitter=jitter, alpha=alpha)

    def arc(self, c, r: float, a0: float, a1: float, colour, *, width: float = 0.03,
            squash: float = 1.0, jitter: float = 0.0022, segments: int = 28, alpha: int = 255):
        pts = [(c[0] + math.cos(a) * r, c[1] + math.sin(a) * r * squash)
               for a in np.linspace(a0, a1, segments)]
        self.stroke(pts, width, colour, jitter=jitter, taper=0.2, alpha=alpha)

    def rect(self, x0, y0, x1, y1, colour, *, width: float = 0.03, fill=None, jitter: float = 0.0022):
        pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        if fill is not None:
            self.poly(pts, fill, jitter=jitter)
        if width > 0:
            self.stroke(pts, width, colour, closed=True, jitter=jitter)

    def text(self, s: str, c, size: float, colour, font_path: Path, *, alpha: int = 255):
        """Centred display type, used for the compass glyphs."""
        px = max(8, int(size * min(self.w, self.h)))
        font = ImageFont.truetype(str(font_path), px)
        try:
            font.set_variation_by_axes([620])
        except Exception:
            pass
        box = self.d.textbbox((0, 0), s, font=font, anchor="lt")
        x, y = self._p(c)
        self.d.text((x - (box[2] - box[0]) / 2 - box[0], y - (box[3] - box[1]) / 2 - box[1]),
                    s, font=font, fill=(*colour, alpha))

    # -- finishing ---------------------------------------------------------------------
    def bake(self, grain: float = 0.34, blur: float = 0.6) -> Image.Image:
        """Break the ink up with paper grain, soften, and downsample to final size."""
        arr = np.asarray(self.img, dtype=np.float32)
        a = arr[..., 3]
        if grain > 0.0:
            n = fbm(self.w, self.h, self.rng, octaves=5, base=10, persistence=0.62)
            a *= (1.0 - grain) + grain * (n * 1.45)
        arr[..., 3] = np.clip(a, 0, 255)
        img = Image.fromarray(arr.astype(np.uint8), "RGBA")
        if blur > 0.0:
            img = img.filter(ImageFilter.GaussianBlur(blur * SS * 0.5))
        return img.resize((self.w // SS, self.h // SS), Image.LANCZOS)


def over(base: Image.Image, layer: Image.Image, offset=(0, 0)) -> Image.Image:
    out = base.convert("RGBA").copy()
    out.alpha_composite(layer.convert("RGBA"), offset)
    return out


def drop_shadow(layer: Image.Image, offset=(1, 2), blur: float = 1.6, opacity: float = 0.40,
                colour=(30, 22, 16)) -> Image.Image:
    a = layer.split()[3].filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    sh = Image.new("RGBA", layer.size, (*colour, 0))
    sh.putalpha(a)
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.alpha_composite(sh, offset)
    out.alpha_composite(layer)
    return out


# --------------------------------------------------------------------------------------
# mouldings: a brass or dark-oak band around the edge of a nine-patch
# --------------------------------------------------------------------------------------

def _edge_fields(w: int, h: int):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    left, right = xs, (w - 1) - xs
    top, bottom = ys, (h - 1) - ys
    dist = np.minimum(np.minimum(left, right), np.minimum(top, bottom))
    # which edge is nearest: 0 left, 1 right, 2 top, 3 bottom
    which = np.argmin(np.stack([left, right, top, bottom]), axis=0)
    return dist, which


def moulding(w: int, h: int, margin: int, rng: np.random.Generator, pal: dict,
             kind: str = "metal", *, studs: bool = True, inner_rule: bool = True) -> Image.Image:
    """A bevelled band of brass (kind='metal') or dark oak (kind='wood') around the edge.
    The centre is transparent so it can be laid over paper."""
    base = np.asarray(pal[kind], np.float32)
    hi = np.asarray(pal[kind + "_hi"], np.float32)
    lo = np.asarray(pal[kind + "_lo"], np.float32)
    dist, which = _edge_fields(w, h)
    t = np.clip(dist / max(margin, 1), 0.0, 1.2)
    band = (dist < margin - 0.5).astype(np.float32)

    # bevel profile across the band: dark at the outer lip, a ridge at 0.42, shade inwards
    ridge = np.exp(-((t - 0.42) ** 2) / 0.045)
    inner_fall = np.clip((t - 0.62) / 0.38, 0.0, 1.0)
    shade = 0.24 + 0.62 * ridge - 0.42 * inner_fall - 0.55 * np.clip(1.0 - t / 0.22, 0.0, 1.0)

    # light from the upper left: top and left edges catch it, bottom and right fall away
    lightness = np.select([which == 0, which == 1, which == 2, which == 3],
                          [0.16, -0.22, 0.22, -0.26], default=0.0)
    shade = shade + lightness

    if kind == "wood":
        grain_h = fbm(w, h, rng, octaves=4, base=5, persistence=0.6, aniso=7.0)
        grain_v = fbm(w, h, rng, octaves=4, base=5, persistence=0.6, aniso=1.0 / 7.0)
        grain = np.where((which >= 2), grain_h, grain_v)
        shade = shade - 0.30 + 0.42 * grain
    else:
        mottle = fbm(w, h, rng, octaves=4, base=7, persistence=0.55)
        shade = shade + 0.20 * (mottle - 0.5)
        # a few pale scratches along the band
        scratch = fbm(w, h, rng, octaves=3, base=24, persistence=0.7, aniso=9.0)
        shade = shade + 0.16 * np.clip(scratch - 0.72, 0.0, 1.0) * 4.0

    shade = np.clip(shade, -1.0, 1.4)
    rgb = np.where(shade[..., None] >= 0.0,
                   base + (hi - base) * np.clip(shade, 0.0, 1.4)[..., None],
                   base + (base - lo) * shade[..., None])

    alpha = band * 255.0
    # soften the outer and inner lips a touch so the band does not read as a hard rectangle
    alpha *= np.clip(dist / 1.2, 0.0, 1.0)
    alpha *= np.clip((margin - dist) / 1.2, 0.0, 1.0) * 0.0 + 1.0
    edge_soft = np.clip((margin - dist) / 1.6, 0.0, 1.0)
    alpha = np.where(dist < margin, alpha * (0.35 + 0.65 * np.clip(edge_soft * 2.0, 0.0, 1.0)), 0.0)

    img = to_image(rgb, alpha)

    nib = Nib(w, h, rng)
    ink = pal["ink"]
    o = 1.0 / max(w, h)
    nib.rect(o * 1.2, o * 1.2, 1 - o * 1.2, 1 - o * 1.2, ink, width=0.010, jitter=0.0016)
    if inner_rule:
        mx, my = (margin - 1.0) / w, (margin - 1.0) / h
        nib.rect(mx, my, 1 - mx, 1 - my, ink, width=0.008, jitter=0.0016)
    img = over(img, nib.bake(grain=0.5, blur=0.5))

    if studs:
        sn = Nib(w, h, rng)
        r = (margin * 0.30) / min(w, h)
        for cx, cy in ((margin * 0.5 / w, margin * 0.5 / h), (1 - margin * 0.5 / w, margin * 0.5 / h),
                       (margin * 0.5 / w, 1 - margin * 0.5 / h), (1 - margin * 0.5 / w, 1 - margin * 0.5 / h)):
            sn.circle((cx, cy), r, pal["ink"], width=0.012, fill=pal[kind + "_hi"], jitter=0.0012)
            sn.circle((cx - r * 0.22, cy - r * 0.22), r * 0.34, pal[kind + "_hi"], width=0.0,
                      fill=pal[kind + "_hi"], jitter=0.001)
        img = over(img, sn.bake(grain=0.28, blur=0.45))
    return img


# --------------------------------------------------------------------------------------
# panels, frames, buttons and the rest of the chrome
# --------------------------------------------------------------------------------------

PANEL_SIZE = 192
PANEL_MARGIN = 28


def panel(rng, pal, *, frame: str | None, size: int = PANEL_SIZE, margin: int = PANEL_MARGIN,
          rule: bool = True, paper_vignette: float = 0.0) -> Image.Image:
    """Parchment nine-patch, optionally banded with brass ('metal') or oak ('wood')."""
    img = parchment(size, size, rng, pal, vignette=paper_vignette, stains=0, fibre=0.08,
                    wrap=True, edge=(margin * 0.92) / size, tone_amount=0.30)
    if rule:
        nib = Nib(size, size, rng)
        inset = (margin * 0.55 if frame else margin * 0.42) / size
        nib.rect(inset, inset, 1 - inset, 1 - inset, pal["ink_soft"], width=0.007, jitter=0.0018)
        img = over(img, nib.bake(grain=0.55, blur=0.5))
    if frame:
        img = over(img, moulding(size, size, margin, rng, pal, frame))
    return img


SMALL_SIZE = 64
SMALL_MARGIN = 13


def small_panel(rng, pal, *, frame: str = "metal", size: int = SMALL_SIZE,
                margin: int = SMALL_MARGIN) -> Image.Image:
    """A light nine-patch for HUD chrome — quick slots, prompts, toasts — where the full
    brass moulding would swallow the thing it frames."""
    img = parchment(size, size, rng, pal, vignette=0.0, stains=0, fibre=0.07, wrap=True,
                    edge=(margin * 0.9) / size, tone_amount=0.35)
    band = moulding(size, size, margin, rng, pal, frame, studs=False, inner_rule=False)
    return over(img, band)


def button(rng, pal, state: str, w: int = 160, h: int = 56, margin: int = 18) -> Image.Image:
    """Normal / hover / pressed / disabled: a small paper tablet held by a metal rule."""
    tone = {"normal": 0.0, "hover": 0.10, "pressed": -0.13, "disabled": -0.06}[state]
    img = parchment(w, h, rng, pal, vignette=0.0, stains=0, fibre=0.07, wrap=True,
                    edge=(margin * 0.8) / min(w, h) * (1.5 if state == "pressed" else 1.0),
                    tone_amount=0.35)
    arr = np.asarray(img, np.float32)
    if state == "disabled":  # washed out and greyer
        grey = arr[..., :3].mean(axis=2, keepdims=True)
        arr[..., :3] = arr[..., :3] * 0.42 + grey * 0.58
    arr[..., :3] = np.clip(arr[..., :3] * (1.0 + tone), 0, 255)
    if state == "pressed":  # inset: darken the top and left inner edge
        dist, which = _edge_fields(w, h)
        inner = np.clip(1.0 - dist / (margin * 0.9), 0.0, 1.0) ** 1.6
        dark = np.select([which == 2, which == 0], [0.34, 0.24], default=0.0) * inner
        arr[..., :3] *= (1.0 - dark)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

    nib = Nib(w, h, rng)
    ink = pal["ink"] if state != "disabled" else pal["ink_soft"]
    metal = pal["metal_hi"] if state == "hover" else pal["metal"]
    mx, my = 4.0 / w, 4.0 / h
    nib.rect(mx, my, 1 - mx, 1 - my, ink, width=0.028, jitter=0.0022)
    ix, iy = 9.0 / w, 9.0 / h
    if state == "disabled":  # a broken rule, as if the entry were struck through
        for k in range(6):
            x0 = ix + (1 - 2 * ix) * (k / 6.0)
            x1 = x0 + (1 - 2 * ix) / 6.0 * 0.62
            nib.stroke([(x0, iy), (x1, iy)], 0.018, metal, jitter=0.002)
            nib.stroke([(x0, 1 - iy), (x1, 1 - iy)], 0.018, metal, jitter=0.002)
    else:
        nib.stroke([(ix, iy), (1 - ix, iy)], 0.020, metal, jitter=0.002)
        nib.stroke([(ix, 1 - iy), (1 - ix, 1 - iy)], 0.020, metal, jitter=0.002)
    if state == "hover":  # small brass corner ticks light up
        for sx, sy in ((ix, iy), (1 - ix, iy), (ix, 1 - iy), (1 - ix, 1 - iy)):
            dx = 0.028 if sx < 0.5 else -0.028
            dy = 0.085 if sy < 0.5 else -0.085
            nib.stroke([(sx, sy), (sx + dx, sy + dy)], 0.020, pal["metal_hi"], jitter=0.002)
    return over(img, nib.bake(grain=0.42, blur=0.55))


def slider_track(rng, pal, w: int = 96, h: int = 16) -> Image.Image:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dist, which = _edge_fields(w, h)
    groove = np.clip(1.0 - np.abs((np.mgrid[0:h, 0:w][0] - (h - 1) / 2.0)) / (h * 0.30), 0.0, 1.0)
    base = np.asarray(pal["wood"], np.float32)
    lo = np.asarray(pal["wood_lo"], np.float32)
    hi = np.asarray(pal["wood_hi"], np.float32)
    grain = fbm(w, h, rng, octaves=4, base=6, persistence=0.6, aniso=8.0, wrap=True)
    rgb = base + (lo - base) * (groove ** 1.4)[..., None] + (hi - base) * (0.30 * grain)[..., None]
    alpha = np.clip(groove * 3.0, 0.0, 1.0) * 255.0
    img = to_image(rgb, alpha)
    nib = Nib(w, h, rng)
    nib.stroke([(0.0, 0.5), (1.0, 0.5)], 0.10, pal["ink"], jitter=0.0016, taper=0.0, alpha=150)
    return over(img, nib.bake(grain=0.4, blur=0.5))


def slider_grabber(rng, pal, size: int = 28) -> Image.Image:
    nib = Nib(size, size, rng)
    nib.circle((0.5, 0.5), 0.36, pal["ink"], width=0.055, fill=pal["metal"], jitter=0.0018)
    nib.arc((0.5, 0.5), 0.26, math.pi * 0.75, math.pi * 1.55, pal["metal_hi"], width=0.055)
    nib.circle((0.5, 0.5), 0.10, pal["metal_lo"], width=0.0, fill=pal["metal_lo"], jitter=0.0014)
    return drop_shadow(nib.bake(grain=0.24, blur=0.5), offset=(1, 1), blur=1.2, opacity=0.45)


def checkbox(rng, pal, checked: bool, size: int = 32) -> Image.Image:
    nib = Nib(size, size, rng)
    nib.rect(0.16, 0.16, 0.84, 0.84, pal["ink"], width=0.05, jitter=0.004)
    if checked:
        nib.stroke([(0.28, 0.52), (0.44, 0.70), (0.76, 0.26)], 0.085, pal["accent"], jitter=0.005)
    return nib.bake(grain=0.34, blur=0.5)


def radio(rng, pal, checked: bool, size: int = 32) -> Image.Image:
    nib = Nib(size, size, rng)
    nib.circle((0.5, 0.5), 0.33, pal["ink"], width=0.05, jitter=0.003)
    if checked:
        nib.circle((0.5, 0.5), 0.16, pal["accent"], width=0.0, fill=pal["accent"], jitter=0.004)
    return nib.bake(grain=0.34, blur=0.5)


def tab(rng, pal, active: bool, w: int = 96, h: int = 44, margin: int = 14) -> Image.Image:
    img = parchment(w, h, rng, pal, vignette=0.0, stains=0, fibre=0.10, wrap=True,
                    edge=(margin * 0.75) / min(w, h) * (0.8 if active else 1.4), tone_amount=0.35)
    arr = np.asarray(img, np.float32)
    if not active:
        grey = arr[..., :3].mean(axis=2, keepdims=True)
        arr[..., :3] = np.clip(arr[..., :3] * 0.80 + grey * 0.14, 0, 255)
    # the bottom edge of an inactive tab is shaded away from the page
    fade = np.clip((np.mgrid[0:h, 0:w][0] - h * 0.62) / (h * 0.38), 0.0, 1.0)
    if not active:
        arr[..., :3] *= (1.0 - 0.22 * fade)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    nib = Nib(w, h, rng)
    mx, my = 3.0 / w, 3.0 / h
    nib.stroke([(mx, 1.0), (mx, my), (1 - mx, my), (1 - mx, 1.0)], 0.030, pal["ink"], jitter=0.0022, taper=0.0)
    if active:
        nib.stroke([(8.0 / w, 8.0 / h), (1 - 8.0 / w, 8.0 / h)], 0.034, pal["metal"], jitter=0.002)
    return over(img, nib.bake(grain=0.42, blur=0.55))


def tooltip(rng, pal, size: int = 96, margin: int = 20) -> Image.Image:
    img = parchment(size, size, rng, pal, vignette=0.0, stains=0, fibre=0.13, wrap=True,
                    edge=(margin * 0.85) / size, tone_amount=0.35)
    arr = np.asarray(img, np.float32)
    arr[..., :3] = np.clip(arr[..., :3] * 0.92, 0, 255)
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    nib = Nib(size, size, rng)
    m = 4.0 / size
    nib.rect(m, m, 1 - m, 1 - m, pal["ink"], width=0.024, jitter=0.003)
    nib.rect(m * 2.4, m * 2.4, 1 - m * 2.4, 1 - m * 2.4, pal["metal"], width=0.012, jitter=0.003)
    return over(img, nib.bake(grain=0.45, blur=0.55))


def scroll_track(rng, pal, w: int = 16, h: int = 64) -> Image.Image:
    img = parchment(w, h, rng, pal, vignette=0.0, stains=0, fibre=0.09, wrap=True, edge=0.30)
    arr = np.asarray(img, np.float32)
    arr[..., :3] *= 0.86
    arr[..., 3] *= 0.7
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def scroll_grabber(rng, pal, w: int = 16, h: int = 64) -> Image.Image:
    img = moulding(w, h, 4, rng, pal, "metal", studs=False, inner_rule=False)
    fill = Image.new("RGBA", (w, h), (*pal["metal"], 200))
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    base.alpha_composite(fill, (3, 3))
    return over(base, img)


def focus_ring(rng, pal, size: int = 64, margin: int = 14) -> Image.Image:
    """A sketched ink rectangle: the focused control looks circled by a pen."""
    nib = Nib(size, size, rng)
    m = 6.0 / size
    for k in range(2):
        j = 0.0 if k == 0 else 0.006
        nib.rect(m + j, m + j, 1 - m - j, 1 - m - j, pal["ink"], width=0.034, jitter=0.007)
    return nib.bake(grain=0.30, blur=0.5)


def bar_track(rng, pal, w: int = 48, h: int = 24, margin: int = 8) -> Image.Image:
    img = parchment(w, h, rng, pal, vignette=0.0, stains=0, fibre=0.10, wrap=True,
                    edge=(margin * 0.9) / min(w, h))
    arr = np.asarray(img, np.float32)
    arr[..., :3] *= 0.74
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    nib = Nib(w, h, rng)
    m = 2.5 / min(w, h)
    nib.rect(m, m, 1 - m, 1 - m, pal["ink"], width=0.055, jitter=0.004)
    return over(img, nib.bake(grain=0.45, blur=0.5))


def bar_fill(rng, pal, kind: str, w: int = 48, h: int = 24) -> Image.Image:
    """A tileable wash of colour with a brushed edge, for a nine-patch progress fill."""
    hi, lo = BAR_COLOURS[kind]
    wash = fbm(w, h, rng, octaves=4, base=4, persistence=0.6, aniso=3.0, wrap=True)
    band = np.clip(np.abs(np.mgrid[0:h, 0:w][0] - (h - 1) / 2.0) / (h / 2.0), 0.0, 1.0)
    t = np.clip(0.30 + 0.55 * wash + 0.45 * band ** 2, 0.0, 1.0)
    rgb = _lerp_rgb(hi, lo, t)
    # a lighter lick along the upper third, like paint pulled with a brush
    lick = np.exp(-((np.mgrid[0:h, 0:w][0] / max(h - 1, 1) - 0.32) ** 2) / 0.02)
    rgb = np.clip(rgb + lick[..., None] * 34.0 * (0.4 + 0.6 * wash)[..., None], 0, 255)
    alpha = np.clip(1.0 - band ** 3 * 0.55, 0.0, 1.0) * 255.0
    return to_image(rgb, alpha)


# --------------------------------------------------------------------------------------
# the icon set: 32 hand-drawn marks, each a few strokes in unit space
# --------------------------------------------------------------------------------------

W_MAIN = 0.072
W_FINE = 0.048
WARM = (158, 72, 52)     # embers, wax, liquid heat
COOL = (74, 110, 142)    # gemstone, lantern glass


def _i_sword(n, ink, ac):
    n.poly([(0.50, 0.06), (0.60, 0.24), (0.59, 0.60), (0.41, 0.60), (0.40, 0.24)], ac, alpha=90)
    n.stroke([(0.50, 0.06), (0.60, 0.24), (0.59, 0.60)], W_MAIN, ink)
    n.stroke([(0.50, 0.06), (0.40, 0.24), (0.41, 0.60)], W_MAIN, ink)
    n.stroke([(0.26, 0.63), (0.74, 0.63)], W_MAIN, ink)
    n.stroke([(0.50, 0.63), (0.50, 0.86)], W_MAIN, ink)
    n.circle((0.50, 0.90), 0.065, ink, width=W_FINE, fill=ac, alpha=160)


def _i_axe(n, ink, ac):
    n.stroke([(0.12, 0.94), (0.70, 0.30)], W_MAIN * 1.3, ink)
    outer = [(0.58 + math.cos(a) * 0.36, 0.34 + math.sin(a) * 0.28)
             for a in np.linspace(-math.pi / 2, math.pi / 2, 9)]
    inner = [(0.58 + math.cos(a) * 0.10, 0.34 + math.sin(a) * 0.28)
             for a in np.linspace(math.pi / 2, -math.pi / 2, 7)]
    head = outer + inner
    n.poly(head, ac, alpha=150)
    n.stroke(head, W_MAIN * 0.95, ink, closed=True)


def _i_bow(n, ink, ac):
    n.arc((0.18, 0.50), 0.44, -math.pi * 0.44, math.pi * 0.44, ink, width=W_MAIN)
    n.stroke([(0.30, 0.12), (0.30, 0.88)], W_FINE, ink)
    n.stroke([(0.22, 0.50), (0.84, 0.50)], W_FINE, ink)
    n.stroke([(0.72, 0.42), (0.84, 0.50), (0.72, 0.58)], W_FINE, ink)


def _i_staff(n, ink, ac):
    n.stroke([(0.30, 0.94), (0.56, 0.38)], W_MAIN * 1.15, ink)
    for a in np.linspace(0.0, math.tau, 7, endpoint=False):
        n.stroke([(0.60 + math.cos(a) * 0.17, 0.26 + math.sin(a) * 0.17),
                  (0.60 + math.cos(a) * 0.32, 0.26 + math.sin(a) * 0.32)], W_FINE, ink)
    n.circle((0.60, 0.26), 0.17, ink, width=W_MAIN, fill=ac, alpha=160)
    n.circle((0.60, 0.26), 0.17, ink, width=W_MAIN)


def _i_shield(n, ink, ac):
    body = [(0.18, 0.14), (0.82, 0.14), (0.80, 0.52), (0.50, 0.90), (0.20, 0.52)]
    n.poly(body, ac, alpha=80)
    n.stroke(body, W_MAIN, ink, closed=True)
    n.stroke([(0.50, 0.18), (0.50, 0.84)], W_FINE, ink)
    n.stroke([(0.24, 0.44), (0.50, 0.56), (0.76, 0.44)], W_FINE, ink)


def _i_helm(n, ink, ac):
    shell = [(0.16, 0.80), (0.16, 0.52), (0.28, 0.24), (0.50, 0.16), (0.72, 0.24), (0.84, 0.52),
             (0.84, 0.80), (0.66, 0.88), (0.34, 0.88)]
    n.poly(shell, ac, alpha=100)
    n.stroke(shell, W_MAIN, ink, closed=True)
    n.poly([(0.24, 0.46), (0.44, 0.44), (0.44, 0.60), (0.24, 0.60)], ink, alpha=235)
    n.poly([(0.56, 0.44), (0.76, 0.46), (0.76, 0.60), (0.56, 0.60)], ink, alpha=235)
    n.poly([(0.45, 0.44), (0.55, 0.44), (0.55, 0.84), (0.45, 0.84)], ink, alpha=235)
    n.stroke([(0.18, 0.72), (0.82, 0.72)], W_FINE * 0.7, ink)


def _i_tunic(n, ink, ac):
    body = [(0.34, 0.16), (0.50, 0.24), (0.66, 0.16), (0.86, 0.32), (0.74, 0.46),
            (0.72, 0.86), (0.28, 0.86), (0.26, 0.46), (0.14, 0.32)]
    n.poly(body, ac, alpha=70)
    n.stroke(body, W_MAIN, ink, closed=True)
    n.stroke([(0.34, 0.16), (0.50, 0.34), (0.66, 0.16)], W_FINE, ink)


def _i_boots(n, ink, ac):
    shape = [(0.30, 0.14), (0.58, 0.14), (0.56, 0.58), (0.84, 0.66), (0.86, 0.84), (0.28, 0.84)]
    n.poly(shape, ac, alpha=70)
    n.stroke(shape, W_MAIN, ink, closed=True)
    n.stroke([(0.30, 0.26), (0.58, 0.26)], W_FINE, ink)
    n.stroke([(0.30, 0.74), (0.86, 0.74)], W_FINE, ink)


def _i_ring(n, ink, ac):
    n.circle((0.50, 0.58), 0.30, ink, width=W_MAIN)
    n.circle((0.50, 0.58), 0.17, ink, width=W_FINE * 0.8)
    n.poly([(0.50, 0.06), (0.63, 0.20), (0.50, 0.34), (0.37, 0.20)], COOL, alpha=185)
    n.stroke([(0.50, 0.06), (0.63, 0.20), (0.50, 0.34), (0.37, 0.20)], W_FINE, ink, closed=True)


def _i_amulet(n, ink, ac):
    n.stroke([(0.16, 0.12), (0.50, 0.54)], W_FINE, ink)
    n.stroke([(0.84, 0.12), (0.50, 0.54)], W_FINE, ink)
    drop = [(0.50, 0.44), (0.68, 0.64), (0.50, 0.92), (0.32, 0.64)]
    n.poly(drop, COOL, alpha=160)
    n.stroke(drop, W_MAIN, ink, closed=True)


def _i_potion(n, ink, ac):
    n.circle((0.50, 0.64), 0.26, ink, width=W_MAIN, fill=WARM, alpha=170)
    n.circle((0.50, 0.64), 0.26, ink, width=W_MAIN)
    n.stroke([(0.40, 0.42), (0.40, 0.18), (0.60, 0.18), (0.60, 0.42)], W_MAIN, ink)
    n.stroke([(0.36, 0.14), (0.64, 0.14)], W_MAIN, ink)
    n.arc((0.50, 0.66), 0.20, math.pi * 0.10, math.pi * 0.90, ink, width=W_FINE * 0.8)


def _i_food(n, ink, ac):
    loaf = [(0.50 + math.cos(a) * 0.38, 0.62 - math.sin(a) * 0.36)
            for a in np.linspace(math.pi, 0.0, 13)] + [(0.86, 0.80), (0.14, 0.80)]
    n.poly(loaf, ac, alpha=95)
    n.stroke(loaf, W_MAIN, ink, closed=True)
    for x in (0.34, 0.50, 0.66):
        n.stroke([(x - 0.09, 0.50), (x + 0.03, 0.66)], W_FINE, ink)


def _i_ingredient(n, ink, ac):
    n.stroke([(0.50, 0.94), (0.52, 0.30)], W_MAIN, ink)
    for side, y in ((1, 0.42), (-1, 0.52), (1, 0.62), (-1, 0.72)):
        leaf = [(0.51, y), (0.51 + side * 0.24, y - 0.14), (0.51 + side * 0.30, y + 0.02), (0.51, y + 0.06)]
        n.poly(leaf, ac, alpha=90)
        n.stroke(leaf, W_FINE * 0.8, ink, closed=True)
    n.circle((0.52, 0.22), 0.10, ink, width=W_FINE, fill=WARM, alpha=175)


def _i_book(n, ink, ac):
    n.stroke([(0.50, 0.24), (0.50, 0.84)], W_FINE, ink)
    left = [(0.50, 0.24), (0.14, 0.32), (0.12, 0.80), (0.50, 0.84)]
    right = [(0.50, 0.24), (0.86, 0.32), (0.88, 0.80), (0.50, 0.84)]
    n.poly(left, ac, alpha=60)
    n.poly(right, ac, alpha=60)
    n.stroke(left, W_MAIN, ink, closed=True)
    n.stroke(right, W_MAIN, ink, closed=True)
    for y in (0.44, 0.56, 0.68):
        n.stroke([(0.20, y), (0.42, y - 0.02)], W_FINE * 0.7, ink)
        n.stroke([(0.58, y - 0.02), (0.80, y)], W_FINE * 0.7, ink)


def _i_key(n, ink, ac):
    n.circle((0.28, 0.30), 0.17, ink, width=W_MAIN)
    n.stroke([(0.38, 0.42), (0.82, 0.86)], W_MAIN, ink)
    n.stroke([(0.62, 0.66), (0.50, 0.78)], W_MAIN, ink)
    n.stroke([(0.72, 0.76), (0.60, 0.88)], W_MAIN, ink)


def _i_coin(n, ink, ac):
    n.circle((0.50, 0.50), 0.36, ink, width=W_MAIN, fill=ac, alpha=120)
    n.circle((0.50, 0.50), 0.36, ink, width=W_MAIN)
    n.circle((0.50, 0.50), 0.27, ink, width=W_FINE * 0.6)
    body = [(0.38, 0.62), (0.40, 0.48), (0.46, 0.40), (0.54, 0.40), (0.60, 0.48), (0.62, 0.62)]
    n.poly(body, ink, alpha=215)
    n.stroke([(0.34, 0.62), (0.66, 0.62)], W_FINE * 0.9, ink)


def _i_hammer(n, ink, ac):
    head = [(0.14, 0.12), (0.62, 0.10), (0.78, 0.22), (0.78, 0.36), (0.62, 0.48), (0.14, 0.46)]
    n.poly(head, ac, alpha=120)
    n.stroke(head, W_MAIN, ink, closed=True)
    n.stroke([(0.26, 0.12), (0.26, 0.46)], W_FINE * 0.8, ink)
    n.stroke([(0.60, 0.11), (0.60, 0.47)], W_FINE * 0.8, ink)
    n.stroke([(0.42, 0.48), (0.50, 0.96)], W_MAIN * 1.6, ink)


def _i_alembic(n, ink, ac):
    n.circle((0.34, 0.64), 0.24, ink, width=W_MAIN, fill=ac, alpha=120)
    n.circle((0.34, 0.64), 0.24, ink, width=W_MAIN)
    n.arc((0.34, 0.66), 0.17, math.pi * 0.08, math.pi * 0.92, ink, width=W_FINE * 0.8)
    n.stroke([(0.26, 0.42), (0.28, 0.16), (0.42, 0.16), (0.42, 0.42)], W_MAIN, ink)
    n.arc((0.60, 0.30), 0.22, math.pi * 1.05, math.pi * 1.98, ink, width=W_FINE)
    n.stroke([(0.82, 0.40), (0.84, 0.72)], W_FINE, ink)
    n.stroke([(0.72, 0.74), (0.96, 0.74), (0.92, 0.90), (0.76, 0.90)], W_FINE, ink, closed=True)


def _i_name_table(n, ink, ac):
    top = [(0.08, 0.40), (0.92, 0.26), (0.92, 0.42), (0.08, 0.56)]
    n.poly(top, ac, alpha=110)
    n.stroke(top, W_MAIN, ink, closed=True)
    for k, y in enumerate((0.36, 0.30)):
        n.stroke([(0.20, y + 0.11 - k * 0.02), (0.80, y - 0.02 - k * 0.02)], W_FINE * 0.9, ink)
    n.stroke([(0.18, 0.54), (0.22, 0.92)], W_MAIN, ink)
    n.stroke([(0.84, 0.42), (0.80, 0.92)], W_MAIN, ink)
    n.stroke([(0.20, 0.82), (0.82, 0.74)], W_FINE * 0.8, ink)


def _i_quest(n, ink, ac):
    sheet = [(0.22, 0.16), (0.78, 0.12), (0.80, 0.84), (0.24, 0.88)]
    n.poly(sheet, ac, alpha=60)
    n.stroke(sheet, W_MAIN, ink, closed=True)
    for y in (0.32, 0.44, 0.56, 0.68):
        n.stroke([(0.32, y), (0.68, y - 0.02)], W_FINE * 0.7, ink)
    n.circle((0.72, 0.80), 0.09, ink, width=W_FINE, fill=ac)


def _i_rumour(n, ink, ac):
    bubble = [(0.16, 0.24), (0.84, 0.20), (0.86, 0.62), (0.44, 0.66), (0.28, 0.86), (0.30, 0.64), (0.14, 0.62)]
    n.poly(bubble, ac, alpha=60)
    n.stroke(bubble, W_MAIN, ink, closed=True)
    for x in (0.34, 0.50, 0.66):
        n.circle((x, 0.42), 0.045, ink, width=0.0, fill=ink)


def _i_bestiary(n, ink, ac):
    head = [(0.26, 0.44), (0.50, 0.34), (0.74, 0.44), (0.70, 0.76), (0.50, 0.88), (0.30, 0.76)]
    n.poly(head, ac, alpha=70)
    n.stroke(head, W_MAIN, ink, closed=True)
    n.stroke([(0.30, 0.44), (0.16, 0.20), (0.34, 0.26)], W_MAIN, ink)
    n.stroke([(0.70, 0.44), (0.84, 0.20), (0.66, 0.26)], W_MAIN, ink)
    n.circle((0.40, 0.56), 0.05, ink, width=0.0, fill=ink)
    n.circle((0.60, 0.56), 0.05, ink, width=0.0, fill=ink)
    n.stroke([(0.42, 0.74), (0.58, 0.74)], W_FINE * 0.8, ink)


def _i_map(n, ink, ac):
    sheet = [(0.10, 0.26), (0.36, 0.16), (0.64, 0.28), (0.90, 0.18), (0.88, 0.76), (0.62, 0.86), (0.36, 0.74), (0.12, 0.84)]
    n.poly(sheet, ac, alpha=55)
    n.stroke(sheet, W_MAIN, ink, closed=True)
    n.stroke([(0.36, 0.16), (0.36, 0.74)], W_FINE * 0.7, ink)
    n.stroke([(0.64, 0.28), (0.64, 0.86)], W_FINE * 0.7, ink)
    n.stroke([(0.20, 0.62), (0.40, 0.48), (0.58, 0.62), (0.80, 0.40)], W_FINE, ink)


def _i_settings(n, ink, ac):
    n.circle((0.50, 0.50), 0.24, ink, width=W_MAIN, fill=ac, alpha=110)
    n.circle((0.50, 0.50), 0.24, ink, width=W_MAIN)
    n.circle((0.50, 0.50), 0.10, ink, width=W_FINE * 0.8)
    for k in range(8):
        a = k * math.tau / 8 + 0.2
        n.stroke([(0.50 + math.cos(a) * 0.26, 0.50 + math.sin(a) * 0.26),
                  (0.50 + math.cos(a) * 0.40, 0.50 + math.sin(a) * 0.40)], W_MAIN * 0.9, ink)


def _i_save(n, ink, ac):
    n.circle((0.50, 0.44), 0.28, ink, width=W_MAIN, fill=WARM, alpha=175)
    n.circle((0.50, 0.44), 0.28, ink, width=W_MAIN)
    n.arc((0.50, 0.44), 0.16, 0.6, 4.2, ink, width=W_FINE)
    n.stroke([(0.34, 0.66), (0.26, 0.94), (0.44, 0.84)], W_FINE, ink, closed=True)
    n.stroke([(0.66, 0.66), (0.74, 0.94), (0.56, 0.84)], W_FINE, ink, closed=True)


def _i_load(n, ink, ac):
    sheet = [(0.14, 0.24), (0.86, 0.24), (0.86, 0.84), (0.14, 0.84)]
    n.poly(sheet, ac, alpha=55)
    n.stroke(sheet, W_MAIN, ink, closed=True)
    n.stroke([(0.14, 0.24), (0.50, 0.58), (0.86, 0.24)], W_FINE, ink)
    n.stroke([(0.50, 0.04), (0.50, 0.40)], W_MAIN, ink)
    n.stroke([(0.40, 0.30), (0.50, 0.42), (0.60, 0.30)], W_MAIN, ink)


def _i_gesture(n, ink, ac):
    fingers = ((0.32, 0.30), (0.46, 0.18), (0.60, 0.22), (0.72, 0.34))
    for x, top in fingers:
        n.stroke([(x, 0.64), (x, top)], 0.105, ac, taper=0.0, alpha=140)
    palm = [(0.24, 0.92), (0.22, 0.58), (0.34, 0.48), (0.74, 0.48), (0.82, 0.62), (0.76, 0.92)]
    n.poly(palm, ac, alpha=140)
    n.stroke(palm, W_MAIN, ink, closed=True)
    for x, top in fingers:
        n.stroke([(x - 0.055, 0.56), (x - 0.055, top)], W_FINE * 0.9, ink)
        n.stroke([(x + 0.055, 0.56), (x + 0.055, top)], W_FINE * 0.9, ink)
        n.arc((x, top), 0.055, math.pi, math.tau, ink, width=W_FINE * 0.9)
    n.stroke([(0.24, 0.66), (0.10, 0.50)], W_MAIN, ink)


def _i_lock(n, ink, ac):
    body = [(0.22, 0.46), (0.78, 0.46), (0.78, 0.90), (0.22, 0.90)]
    n.poly(body, ac, alpha=90)
    n.stroke(body, W_MAIN, ink, closed=True)
    n.arc((0.50, 0.46), 0.20, math.pi, math.tau, ink, width=W_MAIN)
    n.circle((0.50, 0.64), 0.07, ink, width=0.0, fill=ink)
    n.stroke([(0.50, 0.66), (0.50, 0.78)], W_FINE, ink)


def _i_eye(n, ink, ac):
    n.arc((0.50, 0.50), 0.40, math.pi * 0.10, math.pi * 0.90, ink, width=W_MAIN, squash=0.80)
    n.arc((0.50, 0.50), 0.40, math.pi * 1.10, math.pi * 1.90, ink, width=W_MAIN, squash=0.80)
    n.circle((0.50, 0.50), 0.14, ink, width=W_FINE, fill=ac)
    n.circle((0.50, 0.50), 0.05, ink, width=0.0, fill=ink)
    n.stroke([(0.22, 0.26), (0.30, 0.34)], W_FINE * 0.7, ink)
    n.stroke([(0.78, 0.26), (0.70, 0.34)], W_FINE * 0.7, ink)


def _i_skull(n, ink, ac):
    dome = [(0.24, 0.62), (0.22, 0.34), (0.38, 0.16), (0.62, 0.16), (0.78, 0.34), (0.76, 0.62), (0.64, 0.70), (0.36, 0.70)]
    n.poly(dome, ac, alpha=70)
    n.stroke(dome, W_MAIN, ink, closed=True)
    n.circle((0.38, 0.44), 0.10, ink, width=0.0, fill=ink)
    n.circle((0.62, 0.44), 0.10, ink, width=0.0, fill=ink)
    n.poly([(0.50, 0.52), (0.56, 0.62), (0.44, 0.62)], ink)
    n.stroke([(0.36, 0.70), (0.36, 0.86), (0.64, 0.86), (0.64, 0.70)], W_MAIN, ink)
    for x in (0.44, 0.50, 0.56):
        n.stroke([(x, 0.72), (x, 0.86)], W_FINE * 0.6, ink)


def _i_bell(n, ink, ac):
    body = [(0.22, 0.74), (0.28, 0.40), (0.42, 0.22), (0.58, 0.22), (0.72, 0.40), (0.78, 0.74)]
    n.poly(body, ac, alpha=90)
    n.stroke(body, W_MAIN, ink, closed=True)
    n.stroke([(0.18, 0.74), (0.82, 0.74)], W_MAIN, ink)
    n.circle((0.50, 0.86), 0.07, ink, width=W_FINE, fill=ac, alpha=160)
    n.arc((0.50, 0.22), 0.09, math.pi, math.tau, ink, width=W_FINE)


def _i_hearth(n, ink, ac):
    n.stroke([(0.04, 0.30), (0.96, 0.30)], W_MAIN * 1.3, ink)
    n.stroke([(0.10, 0.30), (0.10, 0.92), (0.90, 0.92), (0.90, 0.30)], W_MAIN, ink)
    mouth = [(0.24, 0.92), (0.24, 0.56), (0.50, 0.40), (0.76, 0.56), (0.76, 0.92)]
    n.poly(mouth, ac, alpha=110)
    n.stroke(mouth, W_FINE, ink)
    flame = [(0.50, 0.50), (0.62, 0.68), (0.57, 0.82), (0.50, 0.88), (0.43, 0.82), (0.38, 0.68)]
    n.poly(flame, WARM, alpha=200)
    n.stroke(flame, W_FINE * 0.9, ink, closed=True)
    n.stroke([(0.30, 0.88), (0.48, 0.80)], W_FINE * 0.8, ink)
    n.stroke([(0.70, 0.88), (0.52, 0.80)], W_FINE * 0.8, ink)


ICONS = {
    "sword": _i_sword, "axe": _i_axe, "bow": _i_bow, "staff": _i_staff, "shield": _i_shield,
    "helm": _i_helm, "tunic": _i_tunic, "boots": _i_boots, "ring": _i_ring, "amulet": _i_amulet,
    "potion": _i_potion, "food": _i_food, "ingredient": _i_ingredient, "book": _i_book,
    "key": _i_key, "coin": _i_coin, "hammer": _i_hammer, "alembic": _i_alembic,
    "name_table": _i_name_table, "quest": _i_quest, "rumour": _i_rumour, "bestiary": _i_bestiary,
    "map": _i_map, "settings": _i_settings, "save": _i_save, "load": _i_load,
    "gesture": _i_gesture, "lock": _i_lock, "eye": _i_eye, "skull": _i_skull,
    "bell": _i_bell, "hearth": _i_hearth,
}


def icon(name: str, rng, pal, size: int = 64) -> Image.Image:
    nib = Nib(size, size, rng)
    ICONS[name](nib, pal["ink"], pal["paper_edge"])
    return nib.bake(grain=0.30, blur=0.5)


# --------------------------------------------------------------------------------------
# map / compass marker glyphs: one per place kind and per POI kind
# --------------------------------------------------------------------------------------

MW = 0.085   # marker stroke width


def _roof(n, ink, ac, x, y, w, h):
    pts = [(x - w, y), (x, y - h), (x + w, y)]
    n.poly(pts, ac, alpha=70)
    n.stroke(pts, MW, ink)
    n.stroke([(x - w, y), (x + w, y)], MW, ink)


def _m_town(n, ink, ac):
    _roof(n, ink, ac, 0.28, 0.72, 0.16, 0.22)
    _roof(n, ink, ac, 0.62, 0.72, 0.20, 0.28)
    n.stroke([(0.10, 0.80), (0.90, 0.80)], MW, ink)
    n.stroke([(0.62, 0.44), (0.62, 0.30)], MW * 0.8, ink)


def _m_city(n, ink, ac):
    body = [(0.14, 0.80), (0.14, 0.44), (0.86, 0.44), (0.86, 0.80)]
    n.poly(body, ac, alpha=70)
    n.stroke(body, MW, ink, closed=True)
    for x in (0.20, 0.38, 0.56, 0.74):
        n.stroke([(x, 0.44), (x, 0.30), (x + 0.10, 0.30), (x + 0.10, 0.44)], MW * 0.8, ink)
    n.stroke([(0.46, 0.30), (0.50, 0.16), (0.54, 0.30)], MW * 0.8, ink)


def _m_village(n, ink, ac):
    _roof(n, ink, ac, 0.36, 0.74, 0.18, 0.24)
    _roof(n, ink, ac, 0.68, 0.74, 0.14, 0.18)
    n.stroke([(0.12, 0.80), (0.88, 0.80)], MW, ink)


def _m_hamlet(n, ink, ac):
    _roof(n, ink, ac, 0.50, 0.72, 0.22, 0.28)
    n.stroke([(0.20, 0.80), (0.80, 0.80)], MW, ink)


def _m_camp(n, ink, ac):
    tent = [(0.22, 0.80), (0.50, 0.24), (0.78, 0.80)]
    n.poly(tent, ac, alpha=70)
    n.stroke(tent, MW, ink, closed=True)
    n.stroke([(0.50, 0.24), (0.50, 0.80)], MW * 0.7, ink)
    n.stroke([(0.50, 0.18), (0.62, 0.12)], MW * 0.7, ink)


def _m_fort(n, ink, ac):
    body = [(0.24, 0.84), (0.24, 0.40), (0.76, 0.40), (0.76, 0.84)]
    n.poly(body, ac, alpha=70)
    n.stroke(body, MW, ink, closed=True)
    for x in (0.26, 0.44, 0.62):
        n.stroke([(x, 0.40), (x, 0.26), (x + 0.12, 0.26), (x + 0.12, 0.40)], MW * 0.8, ink)


def _m_lodge(n, ink, ac):
    roof = [(0.18, 0.80), (0.50, 0.30), (0.82, 0.80)]
    n.poly(roof, ac, alpha=70)
    n.stroke(roof, MW, ink, closed=True)
    n.stroke([(0.34, 0.56), (0.66, 0.56)], MW * 0.8, ink)
    n.stroke([(0.50, 0.30), (0.38, 0.12)], MW * 0.7, ink)
    n.stroke([(0.50, 0.30), (0.62, 0.12)], MW * 0.7, ink)


def _m_deep_place(n, ink, ac):
    n.arc((0.50, 0.80), 0.34, math.pi, math.tau, ink, width=MW)
    n.stroke([(0.16, 0.80), (0.84, 0.80)], MW, ink)
    mouth = [(0.34, 0.80), (0.38, 0.62), (0.50, 0.54), (0.62, 0.62), (0.66, 0.80)]
    n.poly(mouth, ink, alpha=210)
    n.stroke([(0.44, 0.72), (0.50, 0.66), (0.56, 0.72)], MW * 0.6, ac)


def _m_interior_dungeon(n, ink, ac):
    _m_deep_place(n, ink, ac)
    n.stroke([(0.22, 0.86), (0.78, 0.86)], MW * 0.7, ink)


def _m_ruin_village(n, ink, ac):
    n.stroke([(0.16, 0.80), (0.24, 0.48), (0.40, 0.62)], MW, ink)
    n.stroke([(0.52, 0.80), (0.56, 0.40), (0.72, 0.58), (0.76, 0.34)], MW, ink)
    n.stroke([(0.10, 0.82), (0.90, 0.82)], MW, ink)


def _m_landmark(n, ink, ac):
    star = [(0.50, 0.10), (0.60, 0.40), (0.90, 0.50), (0.60, 0.60), (0.50, 0.90),
            (0.40, 0.60), (0.10, 0.50), (0.40, 0.40)]
    n.poly(star, ac, alpha=120)
    n.stroke(star, MW * 0.8, ink, closed=True)


def _m_shrine(n, ink, ac):
    stone = [(0.34, 0.86), (0.36, 0.48), (0.50, 0.38), (0.64, 0.48), (0.66, 0.86)]
    n.poly(stone, ac, alpha=80)
    n.stroke(stone, MW, ink, closed=True)
    flame = [(0.50, 0.08), (0.60, 0.26), (0.50, 0.36), (0.40, 0.26)]
    n.poly(flame, ac, alpha=170)
    n.stroke(flame, MW * 0.7, ink, closed=True)


def _m_poi(n, ink, ac):
    n.circle((0.50, 0.50), 0.30, ink, width=MW)
    n.circle((0.50, 0.50), 0.09, ink, width=0.0, fill=ink)


def _m_edge(n, ink, ac):
    for y in (0.36, 0.64):
        pts = [(0.08 + 0.84 * t, y + 0.08 * math.sin(t * 7.0)) for t in np.linspace(0, 1, 9)]
        n.stroke(pts, MW * 0.8, ink)
    for x in (0.24, 0.50, 0.76):
        n.stroke([(x, 0.42), (x, 0.58)], MW * 0.6, ink)


def _m_quest_area(n, ink, ac):
    for k, r in enumerate((0.40, 0.30, 0.20)):
        n.circle((0.50, 0.50), r, ink, width=MW * 0.5, jitter=0.010 + 0.004 * k, segments=30)


def _m_bridge(n, ink, ac):
    n.arc((0.50, 0.74), 0.34, math.pi, math.tau, ink, width=MW)
    n.stroke([(0.10, 0.74), (0.90, 0.74)], MW * 0.7, ink)
    n.stroke([(0.24, 0.74), (0.24, 0.90)], MW * 0.8, ink)
    n.stroke([(0.76, 0.74), (0.76, 0.90)], MW * 0.8, ink)
    n.stroke([(0.10, 0.56), (0.90, 0.56)], MW * 0.8, ink)


def _m_tower(n, ink, ac):
    body = [(0.36, 0.88), (0.38, 0.34), (0.62, 0.34), (0.64, 0.88)]
    n.poly(body, ac, alpha=70)
    n.stroke(body, MW, ink, closed=True)
    n.stroke([(0.28, 0.34), (0.72, 0.34)], MW, ink)
    n.stroke([(0.30, 0.34), (0.30, 0.22), (0.70, 0.22), (0.70, 0.34)], MW * 0.8, ink)


def _m_waterfall(n, ink, ac):
    n.stroke([(0.16, 0.28), (0.84, 0.28)], MW, ink)
    for x in (0.32, 0.50, 0.68):
        n.stroke([(x, 0.30), (x - 0.03, 0.74)], MW * 0.9, ink, jitter=0.006)
    n.arc((0.50, 0.84), 0.26, math.pi * 1.05, math.pi * 1.95, ink, width=MW * 0.7, squash=0.5)


def _m_standing_stones(n, ink, ac):
    for x, h in ((0.24, 0.30), (0.50, 0.22), (0.76, 0.32)):
        s = [(x - 0.09, 0.86), (x - 0.07, h), (x + 0.07, h - 0.03), (x + 0.09, 0.86)]
        n.poly(s, ac, alpha=70)
        n.stroke(s, MW * 0.9, ink, closed=True)
    n.stroke([(0.14, 0.88), (0.86, 0.88)], MW * 0.7, ink)


def _m_giant_bones(n, ink, ac):
    n.arc((0.50, 0.90), 0.38, math.pi * 1.05, math.pi * 1.95, ink, width=MW, squash=1.3)
    n.arc((0.50, 0.96), 0.26, math.pi * 1.05, math.pi * 1.95, ink, width=MW * 0.9, squash=1.3)
    n.stroke([(0.50, 0.18), (0.50, 0.90)], MW * 0.7, ink)


def _m_strange_tree(n, ink, ac):
    n.stroke([(0.50, 0.90), (0.50, 0.46)], MW, ink, jitter=0.006)
    n.stroke([(0.50, 0.58), (0.28, 0.40), (0.20, 0.22)], MW * 0.8, ink, jitter=0.008)
    n.stroke([(0.50, 0.52), (0.72, 0.36), (0.84, 0.18)], MW * 0.8, ink, jitter=0.008)
    n.stroke([(0.50, 0.46), (0.46, 0.20)], MW * 0.7, ink, jitter=0.008)


def _m_wreck(n, ink, ac):
    hull = [(0.14, 0.62), (0.86, 0.54), (0.72, 0.84), (0.26, 0.86)]
    n.poly(hull, ac, alpha=70)
    n.stroke(hull, MW, ink, closed=True)
    n.stroke([(0.60, 0.58), (0.44, 0.14)], MW * 0.8, ink)
    n.stroke([(0.44, 0.14), (0.64, 0.30)], MW * 0.6, ink)


def _m_ruins(n, ink, ac):
    for x, top in ((0.28, 0.32), (0.56, 0.44), (0.76, 0.26)):
        s = [(x - 0.08, 0.86), (x - 0.07, top), (x + 0.07, top + 0.06), (x + 0.08, 0.86)]
        n.poly(s, ac, alpha=60)
        n.stroke(s, MW * 0.85, ink, closed=True)
    n.stroke([(0.12, 0.88), (0.88, 0.88)], MW * 0.7, ink)


def _m_hidden_valley(n, ink, ac):
    n.stroke([(0.06, 0.78), (0.30, 0.34), (0.48, 0.70)], MW, ink)
    n.stroke([(0.52, 0.72), (0.72, 0.28), (0.94, 0.76)], MW, ink)
    n.stroke([(0.44, 0.84), (0.58, 0.84)], MW * 0.7, ink)


def _m_strange(n, ink, ac):
    pts = []
    for k in range(48):
        t = k / 47.0
        a = t * math.tau * 1.9
        r = 0.06 + 0.34 * t
        pts.append((0.50 + math.cos(a) * r, 0.50 + math.sin(a) * r))
    n.stroke(pts, MW * 0.9, ink, jitter=0.005)


def _m_reticle(n, ink, ac):
    n.circle((0.50, 0.50), 0.30, ink, width=MW * 0.7)
    for a in np.linspace(0.0, math.tau, 4, endpoint=False):
        a += math.pi / 4.0
        n.stroke([(0.50 + math.cos(a) * 0.34, 0.50 + math.sin(a) * 0.34),
                  (0.50 + math.cos(a) * 0.48, 0.50 + math.sin(a) * 0.48)], MW * 0.8, ink)
    n.circle((0.50, 0.50), 0.07, ink, width=0.0, fill=ink)


# the kinds the drawn map asked for next (docs/ATLAS.md, section 10)

def _m_cave(n, ink, ac):
    hill = [(0.08, 0.84), (0.30, 0.36), (0.58, 0.22), (0.92, 0.84)]
    n.poly(hill, ac, alpha=70)
    n.stroke(hill, MW, ink)
    mouth = [(0.36, 0.84), (0.38, 0.62), (0.50, 0.52), (0.62, 0.62), (0.64, 0.84)]
    n.poly(mouth, ink, alpha=220)
    n.stroke([(0.06, 0.86), (0.94, 0.86)], MW * 0.8, ink)


def _m_farmstead(n, ink, ac):
    _roof(n, ink, ac, 0.30, 0.66, 0.16, 0.20)
    barn = [(0.48, 0.66), (0.66, 0.38), (0.88, 0.66)]
    n.poly(barn, ac, alpha=70)
    n.stroke(barn, MW, ink, closed=True)
    n.stroke([(0.08, 0.82), (0.92, 0.82)], MW * 0.8, ink)
    for x in (0.14, 0.34, 0.54, 0.74):
        n.stroke([(x, 0.74), (x, 0.88)], MW * 0.7, ink)


def _m_mill(n, ink, ac):
    _roof(n, ink, ac, 0.34, 0.80, 0.20, 0.30)
    n.circle((0.70, 0.56), 0.22, ink, width=MW * 0.9)
    for k in range(4):
        a = k * math.pi / 4.0
        n.stroke([(0.70 - math.cos(a) * 0.22, 0.56 - math.sin(a) * 0.22),
                  (0.70 + math.cos(a) * 0.22, 0.56 + math.sin(a) * 0.22)], MW * 0.5, ink)
    n.stroke([(0.10, 0.84), (0.92, 0.84)], MW * 0.8, ink)


def _m_waystone(n, ink, ac):
    stone = [(0.40, 0.84), (0.40, 0.26), (0.50, 0.16), (0.60, 0.26), (0.60, 0.84)]
    n.poly(stone, ac, alpha=80)
    n.stroke(stone, MW, ink, closed=True)
    for y in (0.34, 0.44, 0.54):
        n.stroke([(0.45, y), (0.55, y)], MW * 0.5, ink)
    n.arc((0.74, 0.80), 0.10, 0.0, math.pi, ink, width=MW * 0.7)
    n.stroke([(0.12, 0.86), (0.88, 0.86)], MW * 0.7, ink)


def _m_market_field(n, ink, ac):
    field = [(0.10, 0.84), (0.10, 0.46), (0.90, 0.46), (0.90, 0.84)]
    n.poly(field, ac, alpha=50)
    n.stroke(field, MW * 0.8, ink, closed=True)
    n.stroke([(0.34, 0.84), (0.34, 0.18), (0.66, 0.18), (0.66, 0.84)], MW * 0.8, ink)
    bell = [(0.42, 0.40), (0.44, 0.24), (0.56, 0.24), (0.58, 0.40)]
    n.poly(bell, ac, alpha=170)
    n.stroke(bell, MW * 0.7, ink, closed=True)


def _m_quarry(n, ink, ac):
    face = [(0.08, 0.84), (0.08, 0.30), (0.30, 0.30), (0.30, 0.48), (0.52, 0.48), (0.52, 0.66),
            (0.92, 0.66), (0.92, 0.84)]
    n.poly(face, ac, alpha=70)
    n.stroke(face, MW * 0.9, ink, closed=True)
    n.stroke([(0.74, 0.66), (0.74, 0.18), (0.58, 0.30)], MW * 0.7, ink)
    n.stroke([(0.58, 0.30), (0.58, 0.46)], MW * 0.5, ink)


def _m_shieling(n, ink, ac):
    n.arc((0.30, 0.76), 0.20, math.pi, math.tau, ink, width=MW, squash=0.8)
    n.stroke([(0.10, 0.76), (0.50, 0.76)], MW, ink)
    n.circle((0.72, 0.66), 0.17, ink, width=MW * 0.8, jitter=0.012, segments=18)
    n.stroke([(0.06, 0.86), (0.94, 0.86)], MW * 0.7, ink)


def _m_vista(n, ink, ac):
    n.stroke([(0.08, 0.52), (0.30, 0.40), (0.48, 0.48), (0.70, 0.34), (0.92, 0.46)], MW * 0.8, ink)
    for x, y, r in ((0.34, 0.80, 0.08), (0.34, 0.68, 0.06), (0.34, 0.58, 0.045)):
        n.circle((x, y), r, ink, width=MW * 0.6, fill=ac)
    n.stroke([(0.56, 0.78), (0.86, 0.78)], MW * 0.8, ink)
    n.stroke([(0.60, 0.78), (0.60, 0.88)], MW * 0.6, ink)
    n.stroke([(0.82, 0.78), (0.82, 0.88)], MW * 0.6, ink)


# the wayside kinds (world/pois: cairns, folds, wells and the rest along the roads)

def _m_cairn(n, ink, ac):
    for x, y, rx in ((0.34, 0.78, 0.16), (0.64, 0.78, 0.15), (0.48, 0.56, 0.15), (0.50, 0.34, 0.10)):
        n.circle((x, y), rx, ink, width=MW * 0.8, fill=ac, segments=16, jitter=0.012)
    n.stroke([(0.50, 0.24), (0.50, 0.10)], MW * 0.7, ink)
    n.stroke([(0.10, 0.90), (0.90, 0.90)], MW * 0.7, ink)


def _m_tally_post(n, ink, ac):
    n.stroke([(0.50, 0.90), (0.50, 0.14)], MW, ink)
    for y, dx in ((0.26, 0.20), (0.40, 0.16), (0.54, 0.22)):
        n.stroke([(0.50, y), (0.50 + dx * 0.5, y + 0.10), (0.50 + dx, y + 0.20)], MW * 0.6, ink, jitter=0.008)
    n.stroke([(0.20, 0.90), (0.80, 0.90)], MW * 0.7, ink)


def _m_fold(n, ink, ac):
    n.circle((0.50, 0.54), 0.34, ink, width=MW, jitter=0.014, segments=26)
    n.poly([(0.44, 0.88), (0.56, 0.88), (0.56, 0.80), (0.44, 0.80)], ac, alpha=255)
    n.stroke([(0.44, 0.92), (0.44, 0.78)], MW * 0.7, ink)
    n.stroke([(0.56, 0.92), (0.56, 0.78)], MW * 0.7, ink)
    n.circle((0.46, 0.50), 0.07, ink, width=MW * 0.5, fill=ac)
    n.circle((0.60, 0.56), 0.06, ink, width=MW * 0.5, fill=ac)


def _m_lantern_post(n, ink, ac):
    n.stroke([(0.40, 0.90), (0.40, 0.16), (0.66, 0.16)], MW, ink)
    n.stroke([(0.66, 0.16), (0.66, 0.28)], MW * 0.6, ink)
    lamp = [(0.58, 0.30), (0.74, 0.30), (0.72, 0.52), (0.60, 0.52)]
    n.poly(lamp, ac, alpha=190)
    n.stroke(lamp, MW * 0.7, ink, closed=True)
    n.stroke([(0.24, 0.90), (0.56, 0.90)], MW * 0.7, ink)


def _m_well(n, ink, ac):
    n.stroke([(0.28, 0.88), (0.28, 0.24)], MW, ink)
    n.stroke([(0.72, 0.88), (0.72, 0.24)], MW, ink)
    _roof(n, ink, ac, 0.50, 0.24, 0.30, 0.14)
    n.stroke([(0.50, 0.26), (0.50, 0.50)], MW * 0.5, ink)
    n.poly([(0.44, 0.50), (0.56, 0.50), (0.55, 0.60), (0.45, 0.60)], ink, alpha=200)
    ring = [(0.20, 0.66), (0.80, 0.66), (0.80, 0.88), (0.20, 0.88)]
    n.poly(ring, ac, alpha=90)
    n.stroke(ring, MW, ink, closed=True)


def _m_hut(n, ink, ac):
    roof = [(0.16, 0.66), (0.50, 0.24), (0.84, 0.66)]
    n.poly(roof, ac, alpha=70)
    n.stroke(roof, MW, ink, closed=True)
    n.stroke([(0.26, 0.66), (0.26, 0.86), (0.74, 0.86), (0.74, 0.66)], MW * 0.9, ink)
    n.stroke([(0.44, 0.86), (0.44, 0.72), (0.56, 0.72), (0.56, 0.86)], MW * 0.6, ink)


def _m_grave(n, ink, ac):
    n.arc((0.50, 0.88), 0.34, math.pi, math.tau, ink, width=MW * 0.8, squash=0.35)
    n.stroke([(0.50, 0.80), (0.50, 0.16)], MW, ink)
    n.stroke([(0.32, 0.34), (0.68, 0.34)], MW, ink)
    n.stroke([(0.10, 0.90), (0.90, 0.90)], MW * 0.7, ink)


def _m_beacon(n, ink, ac):
    n.stroke([(0.24, 0.90), (0.40, 0.52)], MW, ink)
    n.stroke([(0.76, 0.90), (0.60, 0.52)], MW, ink)
    basket = [(0.30, 0.52), (0.70, 0.52), (0.64, 0.64), (0.36, 0.64)]
    n.poly(basket, ac, alpha=90)
    n.stroke(basket, MW * 0.8, ink, closed=True)
    flame = [(0.50, 0.10), (0.64, 0.34), (0.58, 0.50), (0.42, 0.50), (0.36, 0.34)]
    n.poly(flame, ac, alpha=200)
    n.stroke(flame, MW * 0.7, ink, closed=True)


def _m_peat_cut(n, ink, ac):
    bank = [(0.08, 0.40), (0.60, 0.40), (0.60, 0.62), (0.92, 0.62), (0.92, 0.86), (0.08, 0.86)]
    n.poly(bank, ac, alpha=60)
    n.stroke(bank, MW * 0.9, ink, closed=True)
    for x in (0.20, 0.34, 0.48):
        n.stroke([(x, 0.46), (x, 0.80)], MW * 0.5, ink)
    n.stroke([(0.76, 0.56), (0.76, 0.14)], MW * 0.8, ink)
    n.stroke([(0.70, 0.56), (0.82, 0.56)], MW * 0.8, ink)


def _m_player(n, ink, ac):
    head = [(0.50, 0.12), (0.76, 0.76), (0.50, 0.62), (0.24, 0.76)]
    n.poly(head, ac, alpha=200)
    n.stroke(head, MW * 0.9, ink, closed=True)


def _m_default(n, ink, ac):
    n.circle((0.50, 0.50), 0.28, ink, width=MW)
    n.stroke([(0.50, 0.14), (0.50, 0.86)], MW * 0.6, ink)
    n.stroke([(0.14, 0.50), (0.86, 0.50)], MW * 0.6, ink)


MARKERS = {
    "town": _m_town, "city": _m_city, "village": _m_village, "hamlet": _m_hamlet,
    "camp": _m_camp, "fort": _m_fort, "lodge": _m_lodge, "deep_place": _m_deep_place,
    "interior_dungeon": _m_interior_dungeon, "ruin_village": _m_ruin_village,
    "landmark": _m_landmark, "shrine": _m_shrine, "poi": _m_poi, "edge": _m_edge,
    "quest_area": _m_quest_area, "bridge": _m_bridge, "tower": _m_tower,
    "waterfall": _m_waterfall, "standing_stones": _m_standing_stones,
    "giant_bones": _m_giant_bones, "strange_tree": _m_strange_tree, "wreck": _m_wreck,
    "ruins": _m_ruins, "hidden_valley": _m_hidden_valley, "strange": _m_strange,
    "cave": _m_cave, "farmstead": _m_farmstead, "mill": _m_mill, "waystone": _m_waystone,
    "market_field": _m_market_field, "quarry": _m_quarry, "shieling": _m_shieling, "vista": _m_vista,
    "cairn": _m_cairn, "tally_post": _m_tally_post, "fold": _m_fold, "lantern_post": _m_lantern_post,
    "well": _m_well, "hut": _m_hut, "grave": _m_grave, "beacon": _m_beacon, "peat_cut": _m_peat_cut,
    "player": _m_player, "reticle": _m_reticle, "default": _m_default,
}


def marker(name: str, rng, pal, size: int = 48) -> Image.Image:
    nib = Nib(size, size, rng)
    MARKERS[name](nib, pal["ink"], pal["paper_edge"])
    return nib.bake(grain=0.26, blur=0.45)


# --------------------------------------------------------------------------------------
# compass, cursor and the decorative marks
# --------------------------------------------------------------------------------------

CINZEL = FONT_DIR / "Cinzel-Variable.ttf"


def compass_strip(rng, pal, w: int = 512, h: int = 44) -> Image.Image:
    img = parchment(w, h, rng, pal, vignette=0.18, stains=1, fibre=0.14)
    arr = np.asarray(img, np.float32)
    # brass rails top and bottom
    ys = np.mgrid[0:h, 0:w][0].astype(np.float32)
    for centre, thick in ((3.0, 2.6), (h - 4.0, 2.6)):
        rail = np.clip(1.0 - np.abs(ys - centre) / thick, 0.0, 1.0) ** 0.8
        arr[..., :3] = arr[..., :3] * (1 - rail[..., None]) + np.asarray(pal["metal"], np.float32) * rail[..., None]
        hi = np.clip(1.0 - np.abs(ys - (centre - 0.9)) / 1.1, 0.0, 1.0)
        arr[..., :3] = np.clip(arr[..., :3] + hi[..., None] * 42.0, 0, 255)
    # fade out at both ends so the strip dissolves into the screen
    xs = np.mgrid[0:h, 0:w][1].astype(np.float32)
    fade = np.clip(np.minimum(xs, (w - 1) - xs) / (w * 0.18), 0.0, 1.0) ** 1.4
    arr[..., 3] *= fade * 0.94
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def cardinal(letter: str, rng, pal, w: int = 48, h: int = 32) -> Image.Image:
    nib = Nib(w, h, rng)
    nib.text(letter, (0.5, 0.46), 0.80 if len(letter) == 1 else 0.52, pal["ink"], CINZEL)
    return nib.bake(grain=0.30, blur=0.45)


def compass_tick(rng, pal, major: bool, w: int = 8, h: int = 20) -> Image.Image:
    nib = Nib(w, h, rng)
    nib.stroke([(0.5, 0.10), (0.5, 0.80 if major else 0.48)], 0.24 if major else 0.18,
               pal["ink"] if major else pal["ink_soft"], jitter=0.004, taper=0.2)
    return nib.bake(grain=0.38, blur=0.4)


def cursor(rng, pal, size: int = 32) -> Image.Image:
    nib = Nib(size, size, rng)
    nib.poly([(0.06, 0.04), (0.60, 0.50), (0.38, 0.54), (0.50, 0.86), (0.36, 0.92), (0.24, 0.60), (0.08, 0.72)],
             pal["paper_hi"], alpha=235, jitter=0.002)
    nib.stroke([(0.06, 0.04), (0.60, 0.50), (0.38, 0.54), (0.50, 0.86), (0.36, 0.92), (0.24, 0.60), (0.08, 0.72)],
               0.055, pal["ink"], closed=True, jitter=0.003)
    return nib.bake(grain=0.20, blur=0.35)


def bell_mark(rng, pal, size: int = 256) -> Image.Image:
    """The cracked bell that stands over the title."""
    nib = Nib(size, size, rng)
    ink, ac = pal["ink"], pal["metal"]
    body = [(0.20, 0.72), (0.26, 0.42), (0.40, 0.24), (0.60, 0.24), (0.74, 0.42), (0.80, 0.72)]
    nib.poly(body, ac, alpha=120, jitter=0.0016)
    nib.stroke(body, 0.030, ink, closed=True, jitter=0.0022)
    nib.stroke([(0.15, 0.72), (0.85, 0.72)], 0.034, ink, jitter=0.002)
    nib.stroke([(0.17, 0.78), (0.83, 0.78)], 0.016, ink, jitter=0.002)
    nib.arc((0.50, 0.24), 0.075, math.pi, math.tau, ink, width=0.024)
    nib.circle((0.50, 0.85), 0.055, ink, width=0.018, fill=ac, jitter=0.002)
    # the crack
    nib.stroke([(0.63, 0.72), (0.60, 0.60), (0.66, 0.52), (0.60, 0.40), (0.64, 0.30)], 0.020, ink, jitter=0.010)
    # the ring, in faint arcs either side
    for k, r in enumerate((0.46, 0.55)):
        a = 0.30 + k * 0.06
        nib.arc((0.50, 0.52), r, math.pi * (1.10 + a), math.pi * (1.42 + a), ink, width=0.012, alpha=120)
        nib.arc((0.50, 0.52), r, math.pi * (1.58 - a), math.pi * (1.90 - a), ink, width=0.012, alpha=120)
    return nib.bake(grain=0.30, blur=0.6)


def rule_line(rng, pal, w: int = 64, h: int = 16) -> Image.Image:
    """The stretchable part of a rule: an inked line with a little wobble."""
    nib = Nib(w, h, rng)
    nib.stroke([(0.0, 0.5), (1.0, 0.5)], 0.20, pal["ink"], jitter=0.004, taper=0.0)
    return nib.bake(grain=0.24, blur=0.4)


def rule_mark(rng, pal, w: int = 40, h: int = 24) -> Image.Image:
    """The brass lozenge that sits in the middle of a rule."""
    nib = Nib(w, h, rng)
    dia = [(0.50, 0.12), (0.80, 0.5), (0.50, 0.88), (0.20, 0.5)]
    nib.poly(dia, pal["metal"], jitter=0.004)
    nib.stroke(dia, 0.10, pal["ink"], closed=True, jitter=0.004)
    return nib.bake(grain=0.20, blur=0.45)


def divider(rng, pal, w: int = 384, h: int = 24) -> Image.Image:
    nib = Nib(w, h, rng)
    nib.stroke([(0.02, 0.5), (0.43, 0.5)], 0.22, pal["ink"], jitter=0.004, taper=0.5)
    nib.stroke([(0.57, 0.5), (0.98, 0.5)], 0.22, pal["ink"], jitter=0.004, taper=0.5)
    dia = [(0.50, 0.14), (0.565, 0.5), (0.50, 0.86), (0.435, 0.5)]
    nib.poly(dia, pal["metal"], jitter=0.004)
    nib.stroke(dia, 0.11, pal["ink"], closed=True, jitter=0.004)
    return nib.bake(grain=0.22, blur=0.5)


def smudge(rng, pal, size: int = 96) -> Image.Image:
    """A soft ink wash: quest areas are smudges, never pins."""
    n = fbm(size, size, rng, octaves=4, base=3, persistence=0.6)
    r = radial(size, size, 1.0)
    mask = np.clip(1.0 - r / (0.52 + 0.30 * n), 0.0, 1.0) ** 1.5
    mask = mask * (0.55 + 0.45 * n)
    rgb = np.zeros((size, size, 3), np.float32) + np.asarray(pal["ink_soft"], np.float32)
    img = to_image(rgb, mask * 225.0)
    return img.filter(ImageFilter.GaussianBlur(size * 0.03))


def quest_pin(rng, pal, size: int = 64) -> Image.Image:
    """The tracked objective's mark on the compass and the chart: a seal of red wax pressed on a
    split ribbon, the ribbon's two tails hanging to a point below it, with a star struck in the
    wax. Unlike the place glyphs (ink line-work with a pale wash) it is solid and coloured, so it
    reads as the one thing to go to; its tails point at the spot."""
    nib = Nib(size, size, rng)
    ink, wax, ribbon = pal["ink"], pal["accent"], pal["metal"]

    def mix(a, b, t):
        return tuple(int(round(a[i] * (1.0 - t) + b[i] * t)) for i in range(3))

    cx, cy, r = 0.50, 0.38, 0.27
    # the ribbon's two tails, swallow-cut, meeting under the seal and falling to the point
    for side in (-1.0, 1.0):
        tail = [(cx + side * 0.05, cy + 0.10), (cx + side * 0.20, cy + 0.14),
                (cx + side * 0.07, 0.95), (cx + side * 0.015, 0.84)]
        nib.poly(tail, mix(ribbon, pal["paper_hi"], 0.15), jitter=0.002)
        nib.stroke(tail, MW * 0.40, ink, closed=True, jitter=0.002)
    # the wax: a blob that spread as it was poured, not a circle
    blob = []
    for a in np.linspace(0.0, math.tau, 26, endpoint=False):
        wob = 1.0 + 0.07 * math.sin(a * 5.0 + rng.random() * 6.0) + rng.normal(0.0, 0.025)
        blob.append((cx + math.cos(a) * r * wob, cy + math.sin(a) * r * wob))
    nib.poly(blob, mix(wax, ink, 0.12), jitter=0.002)
    nib.stroke(blob, MW * 0.55, mix(wax, ink, 0.55), closed=True, jitter=0.0025)
    # the pressed face, a shade lighter, and a star struck into it
    nib.circle((cx, cy), r * 0.66, mix(wax, ink, 0.45), width=MW * 0.32, fill=wax)
    star = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r * (0.46 if k % 2 == 0 else 0.19)
        star.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    nib.poly(star, mix(wax, ink, 0.50), jitter=0.0015)
    # a lick of light where the wax is thickest
    nib.arc((cx, cy), r * 0.82, math.pi * 1.10, math.pi * 1.38, mix(wax, pal["paper_hi"], 0.55), width=MW * 0.30)
    return drop_shadow(nib.bake(grain=0.14, blur=0.40), offset=(1, 1), blur=1.2, opacity=0.45)


def quest_tick(rng, pal, size: int = 48) -> Image.Image:
    """A step done in the tracker: a quick ink tick with a wash of wax under it."""
    nib = Nib(size, size, rng)
    wash = tuple(int(round(pal["accent"][i] * 0.35 + pal["paper_hi"][i] * 0.65)) for i in range(3))
    nib.circle((0.50, 0.52), 0.30, wash, width=0.0, fill=wash, alpha=150)
    nib.stroke([(0.22, 0.52), (0.42, 0.72), (0.80, 0.24)], MW * 1.25, pal["ink"], jitter=0.004, taper=0.45)
    return nib.bake(grain=0.24, blur=0.45)


def quest_plate(rng, pal, w: int = 256, h: int = 96) -> Image.Image:
    """The tracker's backing: a strip of parchment hung from a brass rail on its left, fading into
    the country on its right, so the words sit on paper without a box round them."""
    img = parchment(w, h, rng, pal, vignette=0.16, stains=1, fibre=0.07, tone_amount=0.5)
    arr = np.asarray(img, np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    # the rail: brass, lit along its top edge
    rail = np.clip(1.0 - np.abs(xs - 3.5) / 2.6, 0.0, 1.0) ** 0.8
    arr[..., :3] = arr[..., :3] * (1 - rail[..., None]) + np.asarray(pal["metal"], np.float32) * rail[..., None]
    hi = np.clip(1.0 - np.abs(xs - 2.6) / 1.0, 0.0, 1.0)
    arr[..., :3] = np.clip(arr[..., :3] + hi[..., None] * 38.0, 0, 255)
    # feathered: gone by the right edge, soft at top and bottom, a ragged fibre edge throughout
    ragged = fbm(w, h, rng, octaves=3, base=6, persistence=0.6)
    fade_r = np.clip(((w - 1) - xs) / (w * 0.27), 0.0, 1.0) ** 1.3
    fade_v = np.clip(np.minimum(ys, (h - 1) - ys) / (5.0 + 3.0 * ragged), 0.0, 1.0)
    arr[..., 3] = 255.0 * fade_r * fade_v * 0.86
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def torn_sheet(rng, pal, w: int = 512, h: int = 512) -> Image.Image:
    """A sheet of paper with a torn, feathered edge: laid over anything without a seam."""
    img = parchment(w, h, rng, pal, vignette=0.24, stains=4, fibre=0.16)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    b = np.minimum(np.minimum(xs, w - 1 - xs), np.minimum(ys, h - 1 - ys)) / (0.16 * min(w, h))
    ragged = fbm(w, h, rng, octaves=4, base=7, persistence=0.6) * 0.55 + 0.35
    alpha = np.clip((b - ragged) / 0.7, 0.0, 1.0) ** 0.8
    arr = np.asarray(img, np.float32)
    arr[..., 3] = alpha * 255.0
    # the torn lip is a little darker, the way a fibre edge catches the light
    lip = np.clip(1.0 - np.abs(b - ragged - 0.35) / 0.5, 0.0, 1.0) * alpha
    arr[..., :3] = arr[..., :3] * (1.0 - 0.28 * lip)[..., None] + np.asarray(pal["paper_edge"], np.float32) * (0.28 * lip)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def menu_backdrop(rng, pal, w: int = 1280, h: int = 720) -> Image.Image:
    """A drawn chart of the basin for the main menu to pan across slowly."""
    img = parchment(w, h, rng, pal, vignette=0.36, stains=6, fibre=0.18, edge=0.05)
    nib = Nib(w, h, rng)
    ink, soft, metal = pal["ink"], pal["ink_soft"], pal["metal"]

    # the Mere: a lake a little left of centre, with hatched shores
    lake = []
    for k in range(40):
        a = k / 40.0 * math.tau
        rr = 0.115 + 0.026 * math.sin(a * 3.0 + 1.2) + 0.018 * math.sin(a * 5.0)
        lake.append((0.46 + math.cos(a) * rr * 0.9, 0.50 + math.sin(a) * rr * 1.5))
    nib.poly(lake, soft, alpha=52, jitter=0.0016)
    nib.stroke(lake, 0.0040, ink, closed=True, jitter=0.0030)
    for k in range(3):
        ring = [(0.46 + (x - 0.46) * (1.05 + 0.045 * k), 0.50 + (y - 0.50) * (1.05 + 0.045 * k)) for x, y in lake]
        nib.stroke(ring, 0.0016, soft, closed=True, jitter=0.0040, alpha=110)

    # hill ranges: rows of small arcs, denser to the north
    for _ in range(190):
        x, y = rng.random(), rng.random()
        if 0.32 < x < 0.60 and 0.30 < y < 0.70:
            continue
        s = 0.012 + 0.020 * rng.random() * (1.3 - y)
        nib.stroke([(x - s, y), (x - s * 0.3, y - s * 0.85), (x + s * 0.35, y), (x + s * 0.8, y - s * 0.6), (x + s * 1.4, y)],
                   0.0016, ink, jitter=0.0035, alpha=170)
    # forest tufts to the east
    for _ in range(120):
        x = 0.70 + rng.random() * 0.28
        y = 0.18 + rng.random() * 0.64
        s = 0.007 + 0.006 * rng.random()
        nib.circle((x, y), s, ink, width=0.0014, jitter=0.006, segments=9, alpha=150)
        nib.stroke([(x, y + s), (x, y + s * 2.1)], 0.0012, ink, alpha=150)
    # ash stipple to the south
    for _ in range(260):
        x = 0.16 + rng.random() * 0.46
        y = 0.74 + rng.random() * 0.24
        nib.circle((x, y), 0.0022, soft, width=0.0, fill=soft, jitter=0.004, segments=6, alpha=120)
    # roads: dashed lines wandering between the settlements
    for a, b in (((0.20, 0.62), (0.44, 0.40)), ((0.44, 0.40), (0.74, 0.30)), ((0.44, 0.40), (0.56, 0.74))):
        pts = [(a[0] + (b[0] - a[0]) * t + 0.012 * math.sin(t * 9.0),
                a[1] + (b[1] - a[1]) * t + 0.012 * math.cos(t * 7.0)) for t in np.linspace(0, 1, 26)]
        for i in range(0, len(pts) - 2, 2):
            nib.stroke(pts[i:i + 2], 0.0022, metal, jitter=0.002, alpha=190)
    # a compass rose in the lower right
    cx, cy, R = 0.845, 0.815, 0.062
    nib.circle((cx, cy), R, ink, width=0.0022, jitter=0.0024)
    nib.circle((cx, cy), R * 0.62, soft, width=0.0014, jitter=0.0024)
    for k in range(4):
        a = k * math.tau / 4 - math.pi / 2
        p = (cx + math.cos(a) * R * 1.25, cy + math.sin(a) * R * 1.25)
        l = (cx + math.cos(a + 1.35) * R * 0.30, cy + math.sin(a + 1.35) * R * 0.30)
        r = (cx + math.cos(a - 1.35) * R * 0.30, cy + math.sin(a - 1.35) * R * 0.30)
        nib.poly([p, l, (cx, cy), r], metal if k % 2 == 0 else soft, alpha=150, jitter=0.002)
        nib.stroke([p, l, (cx, cy), r], 0.0020, ink, closed=True, jitter=0.0026)
    nib.text("N", (cx, cy - R * 1.60), 0.026, ink, CINZEL)
    # border rule
    nib.rect(0.022, 0.032, 0.978, 0.968, ink, width=0.0030, jitter=0.0030)
    nib.rect(0.030, 0.045, 0.970, 0.955, soft, width=0.0014, jitter=0.0030)
    return over(img, nib.bake(grain=0.42, blur=0.55))


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------

SEED = 20260919


def _rng(salt: str) -> np.random.Generator:
    """A stable stream per texture: regenerating one file never disturbs the others."""
    return np.random.default_rng(abs(hash((SEED, salt))) % (2 ** 63))


def build(out: Path, only: str = "") -> dict:
    out.mkdir(parents=True, exist_ok=True)
    (out / "icons").mkdir(exist_ok=True)
    (out / "markers").mkdir(exist_ok=True)
    manifest: dict = {
        "_doc": "Generated by tools/ui/gen_ui_textures.py; read by ui/theme/theme_builder.gd. "
                "margin is [left, top, right, bottom] in pixels for nine-patch styleboxes.",
        "textures": {}, "variants": {}, "icons": [], "markers": [],
    }
    # regenerating one group must not drop the other groups from the manifest
    existing = out / "ui_textures.json"
    if only and existing.exists():
        manifest = json.loads(existing.read_text())
        manifest.setdefault("textures", {})
        manifest.setdefault("variants", {})
        manifest.setdefault("icons", [])
        manifest.setdefault("markers", [])

    def want(group: str) -> bool:
        return only in ("", group)

    def put(name: str, img: Image.Image, margin=None, tile: bool = False, sub: str = "") -> None:
        rel = f"{sub}/{name}.png" if sub else f"{name}.png"
        img.save(out / rel)
        entry: dict = {"file": rel, "size": list(img.size)}
        if margin:
            entry["margin"] = list(margin)
        if tile:
            entry["tile"] = True
        manifest["textures"][name] = entry

    for variant, pal in PALETTES.items():
        sfx = "" if variant == "warm" else "_deep"
        v: dict = {}

        if want("panels"):
            put(f"paper_sheet{sfx}", parchment(512, 512, _rng("sheet" + sfx), pal,
                                               vignette=0.34, stains=5, fibre=0.17, edge=0.035))
            v["sheet"] = f"paper_sheet{sfx}"
            put(f"torn_sheet{sfx}", torn_sheet(_rng("torn" + sfx), pal))
            v["torn"] = f"torn_sheet{sfx}"

            put(f"panel_parchment{sfx}", panel(_rng("panel" + sfx), pal, frame=None),
                margin=[PANEL_MARGIN] * 4, tile=True)
            v["panel"] = f"panel_parchment{sfx}"

            metal_name = "panel_brass" if variant == "warm" else "panel_bronze"
            wood_name = "panel_oak" if variant == "warm" else "panel_ash"
            put(metal_name, panel(_rng(metal_name), pal, frame="metal"), margin=[PANEL_MARGIN] * 4, tile=True)
            put(wood_name, panel(_rng(wood_name), pal, frame="wood"), margin=[PANEL_MARGIN] * 4, tile=True)
            v["panel_metal"], v["panel_wood"] = metal_name, wood_name

            fm = "frame_brass" if variant == "warm" else "frame_bronze"
            fw = "frame_oak" if variant == "warm" else "frame_ash"
            put(fm, moulding(PANEL_SIZE, PANEL_SIZE, PANEL_MARGIN, _rng(fm), pal, "metal"),
                margin=[PANEL_MARGIN] * 4)
            put(fw, moulding(PANEL_SIZE, PANEL_SIZE, PANEL_MARGIN, _rng(fw), pal, "wood"),
                margin=[PANEL_MARGIN] * 4)
            v["frame_metal"], v["frame_wood"] = fm, fw

            put(f"tooltip{sfx}", tooltip(_rng("tooltip" + sfx), pal), margin=[20] * 4, tile=True)
            v["tooltip"] = f"tooltip{sfx}"

            small_metal = f"panel_small{sfx}"
            small_wood = f"panel_small_wood{sfx}"
            put(small_metal, small_panel(_rng(small_metal), pal, frame="metal"),
                margin=[SMALL_MARGIN] * 4, tile=True)
            put(small_wood, small_panel(_rng(small_wood), pal, frame="wood"),
                margin=[SMALL_MARGIN] * 4, tile=True)
            put(f"frame_small{sfx}", moulding(SMALL_SIZE, SMALL_SIZE, SMALL_MARGIN,
                _rng("frame_small" + sfx), pal, "metal", studs=False, inner_rule=False),
                margin=[SMALL_MARGIN] * 4)
            v["panel_small"] = small_metal
            v["panel_small_wood"] = small_wood
            v["frame_small"] = f"frame_small{sfx}"

        if want("buttons"):
            states = {}
            for st in ("normal", "hover", "pressed", "disabled"):
                nm = f"button_{st}{sfx}"
                put(nm, button(_rng(nm), pal, st), margin=[18, 14, 18, 14], tile=True)
                states[st] = nm
            v["button"] = states
            put(f"focus_ring{sfx}", focus_ring(_rng("focus" + sfx), pal), margin=[14] * 4)
            v["focus"] = f"focus_ring{sfx}"
            for act, nm in ((True, f"tab_active{sfx}"), (False, f"tab_inactive{sfx}")):
                put(nm, tab(_rng(nm), pal, act), margin=[14, 14, 14, 2], tile=True)
            v["tab"] = {"active": f"tab_active{sfx}", "inactive": f"tab_inactive{sfx}"}

        if want("widgets"):
            put(f"slider_track{sfx}", slider_track(_rng("strack" + sfx), pal), margin=[6, 6, 6, 6], tile=True)
            put(f"slider_grabber{sfx}", slider_grabber(_rng("sgrab" + sfx), pal))
            put(f"scroll_track{sfx}", scroll_track(_rng("scrolltrack" + sfx), pal), margin=[4, 6, 4, 6], tile=True)
            put(f"scroll_grabber{sfx}", scroll_grabber(_rng("scrollgrab" + sfx), pal), margin=[4, 6, 4, 6], tile=True)
            put(f"check_on{sfx}", checkbox(_rng("chkon" + sfx), pal, True))
            put(f"check_off{sfx}", checkbox(_rng("chkoff" + sfx), pal, False))
            put(f"radio_on{sfx}", radio(_rng("radon" + sfx), pal, True))
            put(f"radio_off{sfx}", radio(_rng("radoff" + sfx), pal, False))
            v["slider"] = {"track": f"slider_track{sfx}", "grabber": f"slider_grabber{sfx}"}
            v["scroll"] = {"track": f"scroll_track{sfx}", "grabber": f"scroll_grabber{sfx}"}
            v["check"] = {"on": f"check_on{sfx}", "off": f"check_off{sfx}"}
            v["radio"] = {"on": f"radio_on{sfx}", "off": f"radio_off{sfx}"}

        if want("bars"):
            put(f"bar_track{sfx}", bar_track(_rng("bartrack" + sfx), pal), margin=[8] * 4, tile=True)
            v["bar_track"] = f"bar_track{sfx}"
            if variant == "warm":
                fills = {}
                for kind in BAR_COLOURS:
                    nm = f"fill_{kind}"
                    put(nm, bar_fill(_rng(nm), pal, kind), margin=[6, 6, 6, 6], tile=True)
                    fills[kind] = nm
                manifest["fills"] = fills

        if want("compass"):
            put(f"compass_strip{sfx}", compass_strip(_rng("compass" + sfx), pal))
            v["compass_strip"] = f"compass_strip{sfx}"
            if variant == "warm":
                for letter in ("N", "NE", "E", "SE", "S", "SW", "W", "NW"):
                    put(f"compass_{letter.lower()}", cardinal(letter, _rng("card" + letter), pal))
                put("compass_tick_major", compass_tick(_rng("tickM"), pal, True))
                put("compass_tick_minor", compass_tick(_rng("tickm"), pal, False))

        if want("marks"):
            if variant == "warm":
                put("mark_bell", bell_mark(_rng("bellmark"), pal))
                put("divider", divider(_rng("divider"), pal), margin=[24, 0, 24, 0])
                put("rule_line", rule_line(_rng("rule_line"), pal), margin=[8, 0, 8, 0])
                put("rule_mark", rule_mark(_rng("rule_mark"), pal))
                put("smudge", smudge(_rng("smudge"), pal))
                put("cursor", cursor(_rng("cursor"), pal))
                put("menu_backdrop", menu_backdrop(_rng("backdrop"), pal))
            else:
                put("divider_deep", divider(_rng("divider_deep"), pal), margin=[24, 0, 24, 0])
                put("rule_line_deep", rule_line(_rng("rule_line_deep"), pal), margin=[8, 0, 8, 0])
                put("rule_mark_deep", rule_mark(_rng("rule_mark_deep"), pal))
                put("smudge_deep", smudge(_rng("smudge_deep"), pal))

        manifest["variants"].setdefault(variant, {}).update(v)

    if want("quest"):
        for variant, qpal in PALETTES.items():
            sfx = "" if variant == "warm" else "_deep"
            put(f"quest_plate{sfx}", quest_plate(_rng("quest_plate" + sfx), qpal), margin=[12, 12, 72, 12])
            manifest["variants"].setdefault(variant, {})["quest_plate"] = f"quest_plate{sfx}"
            put(f"quest_pin{sfx}", quest_pin(_rng("quest_pin" + sfx), qpal))
            manifest["variants"][variant]["quest_pin"] = f"quest_pin{sfx}"
        put("quest_tick", quest_tick(_rng("quest_tick"), PALETTES["warm"]))

    pal = PALETTES["warm"]
    if want("icons"):
        manifest["icons"] = []
        for name in sorted(ICONS):
            put(name, icon(name, _rng("icon" + name), pal), sub="icons")
            manifest["icons"].append(name)
    if want("markers"):
        manifest["markers"] = []
        for name in sorted(MARKERS):
            put(name, marker(name, _rng("marker" + name), pal), sub="markers")
            manifest["markers"].append(name)

    if want("items"):
        # the belt's and the weapon set's painted pictures, and the belt's chrome (gen_item_art.py)
        import gen_item_art as items
        (out / "items").mkdir(exist_ok=True)
        manifest["item_art"] = []
        for name in sorted(items.ART):
            put("item_" + name, items.art(name, _rng("item" + name)), sub="items")
            manifest["item_art"].append(name)
        put("belt_socket", items.socket(_rng("belt_socket")), margin=[14, 14, 14, 14])
        put("belt_socket_lit", items.socket(_rng("belt_socket"), lit=True), margin=[14, 14, 14, 14])
        put("belt_strap", items.strap(_rng("belt_strap")), margin=[22, 10, 22, 10])
        put("belt_key_tab", items.key_tab(_rng("belt_key_tab")), margin=[8, 8, 8, 8])

    manifest["palette"] = {k: {kk: list(vv) for kk, vv in p.items()} for k, p in PALETTES.items()}
    manifest["bar_colours"] = {k: [list(a), list(b)] for k, (a, b) in BAR_COLOURS.items()}
    (out / "ui_textures.json").write_text(json.dumps(manifest, indent=1, sort_keys=False) + "\n")
    return manifest


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT)
    ap.add_argument("--only", default="", help="panels|buttons|widgets|bars|compass|marks|icons|markers|quest|items")
    args = ap.parse_args()
    m = build(args.out, args.only)
    print("[ui] wrote %d textures, %d icons, %d markers -> %s"
          % (len(m["textures"]), len(m["icons"]), len(m["markers"]), args.out))


if __name__ == "__main__":
    main()
