#!/usr/bin/env python3
"""Wickmere item art: the belt's and the weapon set's pictures, painted rather than inked.

The icon set in gen_ui_textures.py is a pen drawing on paper (a few strokes, one ink): it reads on a
page of the journal, but on the belt, over the world, it read as a flat glyph (playtest 09-30: "the
hotbar icons look primitive"). These are small paintings in the same "tended paper" palette:
every part is a filled shape lit from the upper left (dark, body and light tones of its material),
darkened toward its own edges, grained, glazed where it is glass or metal, and drawn round with the
same dark ink the UI writes in, with a soft shadow under it. Shapes are laid out in unit space and
painted at 4x, then brought down.

Also the belt's own chrome: a socket (a dark-oak well with a brass bezel), the same lit for the hand
that holds the weapon, the strap the sockets sit on, and the key's brass tab.

Written by gen_ui_textures.py's "items" group (game/assets/ui/items/, listed under the manifest's
`item_art`); run alone for a contact sheet:
    python3 tools/ui/gen_item_art.py --sheet /tmp/item_art.png
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 4
INK = (40, 30, 22)

# material ramps: (dark, body, light)
STEEL = ((70, 76, 84), (150, 158, 166), (228, 232, 236))
IRON = ((52, 54, 58), (108, 110, 114), (184, 186, 188))
BRASS = ((96, 66, 22), (170, 132, 58), (236, 206, 128))
BRONZE = ((84, 52, 24), (150, 98, 48), (222, 170, 104))
OAK = ((46, 30, 18), (98, 66, 40), (150, 110, 70))
ASH = ((92, 70, 44), (160, 128, 86), (214, 188, 140))
YEW = ((86, 44, 22), (150, 86, 44), (212, 150, 90))
LEATHER = ((52, 30, 18), (110, 64, 36), (168, 110, 66))
CLOTH = ((88, 72, 52), (160, 140, 108), (214, 198, 164))
CORK = ((92, 62, 34), (152, 112, 70), (204, 166, 116))
BREAD = ((110, 58, 20), (184, 116, 50), (236, 186, 110))
CHEESE = ((160, 112, 30), (222, 178, 70), (250, 228, 150))
MEAT = ((96, 30, 26), (164, 62, 48), (216, 120, 96))
BONE = ((150, 138, 112), (214, 204, 180), (246, 240, 226))
LEAF = ((30, 60, 26), (70, 116, 50), (140, 180, 90))
WAX = ((170, 150, 110), (226, 210, 170), (252, 244, 220))
HEMP = ((110, 86, 50), (176, 146, 96), (224, 200, 150))
GLASS = ((120, 140, 140), (190, 206, 204), (246, 250, 248))
LIQUIDS = {
    "red": ((100, 14, 20), (178, 34, 38), (246, 110, 96)),
    "blue": ((20, 40, 96), (44, 96, 178), (130, 190, 246)),
    "green": ((24, 70, 30), (60, 142, 58), (160, 222, 120)),
    "amber": ((120, 66, 10), (206, 136, 30), (250, 210, 110)),
    "violet": ((56, 20, 80), (116, 58, 150), (196, 150, 226)),
    "bile": ((40, 50, 18), (88, 104, 30), (170, 186, 80)),
}
EMBER = ((150, 40, 10), (236, 120, 30), (255, 226, 140))


def _fbm(w: int, h: int, rng: np.random.Generator, octaves: int = 4, base: int = 6) -> np.ndarray:
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        small = rng.random((n + 1, n + 1)).astype(np.float32)
        img = Image.fromarray((small * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
        out += np.asarray(img, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.55
    return out / tot


class Painter:
    """Paints lit, edged, grained shapes in unit space on an RGBA canvas at SS x the final size."""

    def __init__(self, size: int, rng: np.random.Generator, light=(-0.62, -0.78)):
        self.size = size
        self.n = size * SS
        self.rgb = np.zeros((self.n, self.n, 3), np.float32)
        self.a = np.zeros((self.n, self.n), np.float32)
        self.rng = rng
        self.light = np.array(light, np.float32) / np.linalg.norm(light)
        ys, xs = np.mgrid[0:self.n, 0:self.n].astype(np.float32)
        self.x = xs / self.n
        self.y = ys / self.n
        self.grain = _fbm(self.n, self.n, rng, 5, 8)

    # -- masks ------------------------------------------------------------------------------
    def _mask(self, draw_fn) -> np.ndarray:
        img = Image.new("L", (self.n, self.n), 0)
        draw_fn(ImageDraw.Draw(img), self.n)
        return np.asarray(img, np.float32) / 255.0

    def poly_mask(self, pts) -> np.ndarray:
        return self._mask(lambda d, n: d.polygon([(x * n, y * n) for x, y in pts], fill=255))

    def ellipse_mask(self, c, rx, ry=None) -> np.ndarray:
        ry = rx if ry is None else ry
        return self._mask(lambda d, n: d.ellipse([(c[0] - rx) * n, (c[1] - ry) * n, (c[0] + rx) * n, (c[1] + ry) * n], fill=255))

    def line_mask(self, pts, width) -> np.ndarray:
        def f(d, n):
            p = [(x * n, y * n) for x, y in pts]
            d.line(p, fill=255, width=max(1, int(width * n)), joint="curve")
            r = width * n / 2
            for x, y in (p[0], p[-1]):
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        return self._mask(f)

    # -- painting ---------------------------------------------------------------------------
    def paint(self, mask: np.ndarray, ramp, *, alpha: float = 1.0, edge: float = 0.05, grain: float = 0.10,
              gloss: float = 0.0, streak: float = 0.0, flat: float = 0.0, streak_dir=(1.0, 0.0)) -> np.ndarray:
        """Fills `mask` with the material `ramp`, lit from the upper left across the shape's extent."""
        if mask.max() <= 0.0:
            return mask
        ys, xs = np.nonzero(mask > 0.5)
        if len(xs) == 0:
            ys, xs = np.nonzero(mask > 0.0)
        cx, cy = xs.mean() / self.n, ys.mean() / self.n
        r = max((xs.max() - xs.min()), (ys.max() - ys.min())) / self.n * 0.5 + 1e-3
        t = ((self.x - cx) * self.light[0] + (self.y - cy) * self.light[1]) / r
        t = np.clip(0.5 + 0.5 * t, 0.0, 1.0) * (1.0 - flat) + 0.5 * flat
        dark, body, lite = (np.array(c, np.float32) for c in ramp)
        lo = dark + (body - dark) * np.clip(t * 2.0, 0, 1)[..., None]
        col = np.where((t < 0.5)[..., None], lo, body + (lite - body) * np.clip(t * 2.0 - 1.0, 0, 1)[..., None])
        # darker toward the shape's own edges: it is round, not cut from card
        if edge > 0.0:
            b = np.asarray(Image.fromarray((mask * 255).astype(np.uint8), "L").filter(
                ImageFilter.GaussianBlur(edge * self.n)), np.float32) / 255.0
            col *= (0.62 + 0.38 * np.clip((b - 0.2) / 0.65, 0, 1))[..., None]
        if grain > 0.0:
            col *= (1.0 - grain + grain * 2.0 * self.grain)[..., None]
        if streak > 0.0:
            # brushed metal, wood grain: fine stripes across the given direction
            u = self.x * streak_dir[1] - self.y * streak_dir[0]
            s = np.sin(u * self.n * 0.35 + self.grain * 9.0)
            col *= (1.0 + streak * 0.5 * s)[..., None]
        if gloss > 0.0:
            g = np.clip(t - 0.72, 0, 1) / 0.28
            col += (g ** 2 * gloss * 255.0)[..., None]
        self._over(col, mask * alpha)
        return mask

    def _over(self, col: np.ndarray, m: np.ndarray) -> None:
        m = np.clip(m, 0.0, 1.0)
        out_a = m + self.a * (1.0 - m)
        safe = np.maximum(out_a, 1e-5)
        self.rgb = (col * m[..., None] + self.rgb * (self.a * (1.0 - m))[..., None]) / safe[..., None]
        self.a = out_a

    def stroke(self, pts, width, colour, alpha=1.0, blur=0.0) -> None:
        m = self.line_mask(pts, width)
        if blur > 0:
            m = np.asarray(Image.fromarray((m * 255).astype(np.uint8), "L").filter(
                ImageFilter.GaussianBlur(blur * self.n)), np.float32) / 255.0
        col = np.broadcast_to(np.array(colour, np.float32), self.rgb.shape)
        self._over(col, m * alpha)

    def shine(self, pts, width=0.02, alpha=0.7) -> None:
        """A glint of light along a lit edge."""
        self.stroke(pts, width, (255, 250, 236), alpha, blur=0.006)

    def glow(self, c, r, colour, strength=0.8) -> None:
        d = np.sqrt((self.x - c[0]) ** 2 + (self.y - c[1]) ** 2) / r
        g = np.clip(1.0 - d, 0, 1) ** 2 * strength
        self.rgb = self.rgb * (1 - g[..., None] * 0.0) + np.array(colour, np.float32) * g[..., None] * 0.9
        self.rgb = np.minimum(self.rgb, 255.0)
        self.a = np.maximum(self.a, g * 0.85)

    def finish(self, ink: float = 0.028, shadow: bool = True) -> Image.Image:
        """Draws the whole round in ink, adds a shadow under it and brings it down to size."""
        a8 = Image.fromarray((np.clip(self.a, 0, 1) * 255).astype(np.uint8), "L")
        k = max(3, int(ink * self.n) | 1)
        grown = np.asarray(a8.filter(ImageFilter.MaxFilter(k)), np.float32) / 255.0
        grown = np.asarray(Image.fromarray((grown * 255).astype(np.uint8), "L").filter(
            ImageFilter.GaussianBlur(SS * 0.35)), np.float32) / 255.0
        ink_a = np.clip(grown - self.a, 0, 1) * 0.92
        rgb = self.rgb * self.a[..., None] + np.array(INK, np.float32) * ink_a[..., None]
        alpha = np.clip(self.a + ink_a, 0, 1)
        rgb = rgb / np.maximum(alpha, 1e-5)[..., None]
        img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8), "RGBA")
        if shadow:
            sh_a = img.split()[3].filter(ImageFilter.GaussianBlur(SS * 1.6)).point(lambda v: int(v * 0.55))
            sh = Image.new("RGBA", img.size, (22, 14, 8, 0))
            sh.putalpha(sh_a)
            base = Image.new("RGBA", img.size, (0, 0, 0, 0))
            base.alpha_composite(sh, (int(SS * 1.2), int(SS * 2.0)))
            base.alpha_composite(img)
            img = base
        return img.resize((self.size, self.size), Image.LANCZOS)


# --------------------------------------------------------------------------------------------
# shape helpers
# --------------------------------------------------------------------------------------------

def along(p0, p1, profile):
    """A polygon along the axis p0 -> p1: `profile` is [(t, half-width left, half-width right)]."""
    ax = np.array(p1, float) - np.array(p0, float)
    ln = np.linalg.norm(ax)
    u = ax / ln
    nrm = np.array([-u[1], u[0]])
    left, right = [], []
    for row in profile:
        t, wl = row[0], row[1]
        wr = row[2] if len(row) > 2 else wl
        c = np.array(p0, float) + ax * t
        left.append(tuple(c + nrm * wl))
        right.append(tuple(c - nrm * wr))
    return left + right[::-1]


def lerp(p0, p1, t):
    return (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)


DIAG0, DIAG1 = (0.17, 0.85), (0.84, 0.15)


def _blade_weapon(p: Painter, *, blade_len: float, blade_w: float, guard_w: float, grip_len: float,
                  steel=STEEL, guard=BRASS, grip=LEATHER, pommel=BRASS, fuller: bool = True,
                  p0=DIAG0, p1=DIAG1, point: float = 0.10):
    """A straight blade on the diagonal: pommel, grip, guard, blade (t runs from the pommel)."""
    g0 = grip_len * 0.12
    guard_t = grip_len
    tip = min(0.99, guard_t + blade_len)
    p.paint(p.poly_mask(along(p0, p1, [(g0, 0.034), (guard_t, 0.030)])), grip, streak=0.25, streak_dir=(1, 1))
    for k in np.linspace(g0 + 0.02, guard_t - 0.02, 5):
        p.stroke([lerp(p0, p1, k - 0.004), lerp(p0, p1, k + 0.004)], 0.05, INK, alpha=0.35)
    p.paint(p.poly_mask(along(p0, p1, [(guard_t + 0.005, blade_w), (tip - point, blade_w * 0.86), (tip, 0.0)])),
            steel, gloss=0.35, streak=0.08, streak_dir=(1, -1))
    if fuller:
        a, b = lerp(p0, p1, guard_t + 0.04), lerp(p0, p1, tip - point - 0.04)
        p.stroke([a, b], blade_w * 0.45, steel[0], alpha=0.45)
        p.shine([lerp(p0, p1, guard_t + 0.06), lerp(p0, p1, tip - 0.06)], 0.012, 0.55)
    gc = lerp(p0, p1, guard_t)
    ax = np.array(p1) - np.array(p0)
    ax /= np.linalg.norm(ax)
    nrm = np.array([-ax[1], ax[0]])
    p.paint(p.poly_mask(along(tuple(np.array(gc) + nrm * guard_w), tuple(np.array(gc) - nrm * guard_w),
                              [(0.0, 0.018), (0.5, 0.030), (1.0, 0.018)])), guard, gloss=0.3)
    pc = lerp(p0, p1, g0 - 0.01)
    p.paint(p.ellipse_mask(pc, 0.052), pommel, gloss=0.45)


# --------------------------------------------------------------------------------------------
# the pictures
# --------------------------------------------------------------------------------------------

def a_sword(p):
    _blade_weapon(p, blade_len=0.72, blade_w=0.046, guard_w=0.13, grip_len=0.22)


def a_greatsword(p):
    _blade_weapon(p, blade_len=0.76, blade_w=0.060, guard_w=0.17, grip_len=0.24, p0=(0.12, 0.90), p1=(0.90, 0.10),
                  guard=IRON, pommel=IRON)


def a_dagger(p):
    p0, p1 = (0.16, 0.86), (0.82, 0.16)
    _blade_weapon(p, blade_len=0.60, blade_w=0.068, guard_w=0.11, grip_len=0.36, grip=ASH, guard=IRON,
                  pommel=IRON, fuller=False, p0=p0, p1=p1, point=0.2)
    p.shine([lerp(p0, p1, 0.42), lerp(p0, p1, 0.86)], 0.012, 0.6)


def a_axe(p):
    p0, p1 = (0.22, 0.90), (0.62, 0.12)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.030), (1.0, 0.026)])), ASH, streak=0.3, streak_dir=(0.45, -0.9))
    head = [(0.52, 0.18), (0.80, 0.10), (0.90, 0.26), (0.86, 0.46), (0.74, 0.44), (0.62, 0.34), (0.52, 0.34)]
    p.paint(p.poly_mask(head), IRON, gloss=0.25, grain=0.14)
    p.shine([(0.84, 0.13), (0.91, 0.27), (0.87, 0.44)], 0.018, 0.7)
    p.paint(p.poly_mask([(0.49, 0.18), (0.58, 0.16), (0.60, 0.36), (0.50, 0.37)]), LEATHER)


def a_mace(p):
    p0, p1 = (0.24, 0.88), (0.62, 0.30)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.030), (1.0, 0.026)])), OAK, streak=0.3, streak_dir=(0.5, -0.9))
    c = (0.66, 0.26)
    for a in np.linspace(0, math.tau, 7, endpoint=False):
        tip = (c[0] + math.cos(a) * 0.20, c[1] + math.sin(a) * 0.20)
        p.paint(p.poly_mask(along(c, tip, [(0.0, 0.05), (1.0, 0.012)])), IRON, gloss=0.2)
    p.paint(p.ellipse_mask(c, 0.12), IRON, gloss=0.4)
    p.paint(p.ellipse_mask((0.22, 0.90), 0.04), IRON)


def a_hammer(p):
    p0, p1 = (0.22, 0.90), (0.58, 0.22)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.032), (1.0, 0.030)])), OAK, streak=0.3, streak_dir=(0.5, -0.9))
    head = along((0.36, 0.08), (0.86, 0.40), [(0.0, 0.10), (1.0, 0.10)])
    p.paint(p.poly_mask(head), IRON, gloss=0.3, grain=0.14)
    p.shine([(0.40, 0.03), (0.86, 0.32)], 0.016, 0.5)
    p.paint(p.poly_mask(along((0.52, 0.16), (0.66, 0.26), [(0.0, 0.11), (1.0, 0.11)])), BRASS, gloss=0.3)


def a_spear(p):
    p0, p1 = (0.10, 0.92), (0.86, 0.14)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.028), (0.80, 0.028)])), ASH, streak=0.3, streak_dir=(1, 1))
    p.paint(p.poly_mask(along(p0, p1, [(0.72, 0.040), (0.80, 0.040)])), LEATHER)
    p.paint(p.poly_mask(along(p0, p1, [(0.78, 0.026), (0.86, 0.090), (0.99, 0.0)])), STEEL, gloss=0.4)
    p.shine([lerp(p0, p1, 0.84), lerp(p0, p1, 0.97)], 0.012, 0.6)


def a_bow(p):
    # the stave's curve, its grip wrapped, a string and an arrow across it
    pts_l = []
    pts_r = []
    for t in np.linspace(0, 1, 40):
        y = 0.08 + t * 0.84
        s = (t - 0.5) * 2.0
        x = 0.30 + 0.30 * (1 - s * s) ** 0.9 - 0.05 * s ** 4
        w = 0.044 * (1.0 - 0.5 * abs(s)) + 0.012
        pts_l.append((x - w, y))
        pts_r.append((x + w, y))
    p.paint(p.poly_mask(pts_l + pts_r[::-1]), YEW, streak=0.2, streak_dir=(0, 1), gloss=0.2)
    p.paint(p.poly_mask([(0.55, 0.42), (0.65, 0.42), (0.65, 0.58), (0.55, 0.58)]), LEATHER)
    p.stroke([(0.30, 0.09), (0.30, 0.91)], 0.010, (226, 214, 180))
    p0, p1 = (0.24, 0.50), (0.92, 0.50)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.018), (0.86, 0.018)])), ASH)
    p.paint(p.poly_mask(along(p0, p1, [(0.84, 0.045), (1.0, 0.0)])), IRON, gloss=0.3)
    p.paint(p.poly_mask([(0.24, 0.50), (0.34, 0.45), (0.38, 0.45), (0.30, 0.50), (0.38, 0.55), (0.34, 0.55)]),
            ((120, 30, 24), (180, 60, 44), (230, 130, 100)))


def a_crossbow(p):
    p.paint(p.poly_mask(along((0.50, 0.94), (0.50, 0.20), [(0.0, 0.065), (0.3, 0.058), (1.0, 0.045)])), OAK,
            streak=0.3, streak_dir=(0, 1))
    prod = []
    for t in np.linspace(0, 1, 30):
        x = 0.10 + 0.80 * t
        y = 0.30 - 0.12 * (1 - ((t - 0.5) * 2) ** 2)
        prod.append((x, y))
    p.paint(p.poly_mask([(x, y - 0.032) for x, y in prod] + [(x, y + 0.032) for x, y in prod[::-1]]), IRON, gloss=0.3)
    p.stroke([(0.11, 0.31), (0.50, 0.52), (0.89, 0.31)], 0.014, (226, 214, 180))
    p.paint(p.poly_mask(along((0.50, 0.50), (0.50, 0.10), [(0.0, 0.018), (0.84, 0.018), (0.85, 0.045), (1.0, 0.0)])), IRON, gloss=0.3)
    p.paint(p.poly_mask([(0.44, 0.60), (0.56, 0.60), (0.56, 0.70), (0.44, 0.70)]), BRASS, gloss=0.3)


def a_staff(p):
    p0, p1 = (0.24, 0.94), (0.62, 0.24)
    prof = [(0.0, 0.022), (0.3, 0.028), (0.32, 0.036), (0.36, 0.028), (0.7, 0.030), (0.72, 0.040),
            (0.76, 0.030), (1.0, 0.034)]
    p.paint(p.poly_mask(along(p0, p1, prof)), ASH, streak=0.35, streak_dir=(0.5, -0.9))
    # the head: a knot of the ash split round a stone
    c = (0.66, 0.18)
    p.paint(p.poly_mask([(0.56, 0.30), (0.52, 0.14), (0.60, 0.04), (0.66, 0.12), (0.74, 0.03), (0.82, 0.14),
                         (0.76, 0.30), (0.66, 0.28)]), ASH, streak=0.3)
    p.glow(c, 0.16, (170, 210, 250), 0.5)
    p.paint(p.ellipse_mask(c, 0.062, 0.075), LIQUIDS["blue"], gloss=0.7)
    p.shine([(0.64, 0.14), (0.66, 0.13)], 0.018, 0.8)


def a_shield(p):
    c = (0.50, 0.52)
    p.paint(p.ellipse_mask(c, 0.40), OAK, streak=0.25, streak_dir=(1, 0))
    for x in (0.36, 0.50, 0.64):
        p.stroke([(x, 0.14), (x, 0.90)], 0.006, OAK[0], alpha=0.6)
    ring = p.ellipse_mask(c, 0.40) - p.ellipse_mask(c, 0.345)
    p.paint(np.clip(ring, 0, 1), BRASS, gloss=0.3, edge=0.01)
    p.paint(p.ellipse_mask(c, 0.12), BRASS, gloss=0.6)
    for a in np.linspace(0, math.tau, 8, endpoint=False):
        p.paint(p.ellipse_mask((c[0] + math.cos(a) * 0.372, c[1] + math.sin(a) * 0.372), 0.018), BRASS, gloss=0.5, edge=0.0)


def a_sword_shield(p):
    c = (0.42, 0.56)
    p.paint(p.ellipse_mask(c, 0.33), OAK, streak=0.25, streak_dir=(1, 0))
    ring = p.ellipse_mask(c, 0.33) - p.ellipse_mask(c, 0.285)
    p.paint(np.clip(ring, 0, 1), BRASS, gloss=0.3, edge=0.01)
    p.paint(p.ellipse_mask(c, 0.10), BRASS, gloss=0.6)
    _blade_weapon(p, blade_len=0.72, blade_w=0.040, guard_w=0.11, grip_len=0.22, p0=(0.30, 0.94), p1=(0.92, 0.10))


def _bottle(p, liquid, *, full=0.62):
    """A round flask: glass, the draught in it to `full`, a cork."""
    body = p.ellipse_mask((0.50, 0.63), 0.28, 0.27)
    neck = p.poly_mask([(0.42, 0.18), (0.58, 0.18), (0.58, 0.42), (0.42, 0.42)])
    glass = np.clip(body + neck, 0, 1)
    p.paint(glass, GLASS, alpha=0.55, edge=0.03, grain=0.02, gloss=0.2)
    level = 0.36 + (1 - full) * 0.54
    liq = body * (p.y > level)
    p.paint(np.clip(liq * 1.0, 0, 1), LIQUIDS[liquid], gloss=0.35, edge=0.06, grain=0.05)
    p.stroke([(0.27, level + 0.005), (0.73, level + 0.005)], 0.010, LIQUIDS[liquid][2], alpha=0.6)
    p.paint(p.poly_mask([(0.40, 0.08), (0.60, 0.08), (0.58, 0.21), (0.42, 0.21)]), CORK, grain=0.2)
    p.paint(p.poly_mask([(0.39, 0.19), (0.61, 0.19), (0.61, 0.23), (0.39, 0.23)]), LEATHER)
    p.shine([(0.33, 0.56), (0.36, 0.47), (0.42, 0.42)], 0.024, 0.75)
    p.shine([(0.62, 0.80), (0.68, 0.72)], 0.012, 0.35)


def a_potion_red(p): _bottle(p, "red")
def a_potion_blue(p): _bottle(p, "blue")
def a_potion_green(p): _bottle(p, "green")
def a_potion_amber(p): _bottle(p, "amber")
def a_potion_violet(p): _bottle(p, "violet")
def a_poison(p): _bottle(p, "bile", full=0.48)


def a_hearth_flask(p):
    # a pilgrim's flask: flat round body sewn in leather, a brass neck, an ember's light in its window
    p.paint(p.ellipse_mask((0.50, 0.60), 0.33, 0.31), LEATHER, streak=0.1)
    ring = p.ellipse_mask((0.50, 0.60), 0.33, 0.31) - p.ellipse_mask((0.50, 0.60), 0.29, 0.27)
    p.paint(np.clip(ring, 0, 1), BRASS, gloss=0.35, edge=0.01)
    for a in np.linspace(0, math.tau, 18, endpoint=False):
        x, y = 0.50 + math.cos(a) * 0.31, 0.60 + math.sin(a) * 0.29
        p.stroke([(x - 0.004, y), (x + 0.004, y)], 0.01, (230, 210, 170), alpha=0.35)
    p.glow((0.50, 0.62), 0.20, (255, 150, 60), 0.55)
    p.paint(p.ellipse_mask((0.50, 0.62), 0.12, 0.12), EMBER, gloss=0.6, edge=0.03)
    p.paint(p.poly_mask([(0.43, 0.14), (0.57, 0.14), (0.58, 0.31), (0.42, 0.31)]), BRASS, gloss=0.4)
    p.paint(p.poly_mask([(0.41, 0.08), (0.59, 0.08), (0.59, 0.15), (0.41, 0.15)]), OAK)
    p.shine([(0.30, 0.50), (0.36, 0.40)], 0.02, 0.5)


def a_bread(p):
    loaf = p.ellipse_mask((0.50, 0.58), 0.40, 0.27) * (p.y < 0.76)
    p.paint(np.clip(loaf, 0, 1), BREAD, gloss=0.15, grain=0.16)
    p.paint(p.poly_mask([(0.10, 0.70), (0.90, 0.70), (0.86, 0.80), (0.14, 0.80)]), (BREAD[0], BREAD[0], BREAD[1]))
    for x in (0.32, 0.48, 0.64):
        p.stroke([(x - 0.06, 0.44), (x + 0.05, 0.60)], 0.030, BREAD[0], alpha=0.8)
        p.stroke([(x - 0.05, 0.46), (x + 0.05, 0.60)], 0.012, (250, 226, 170), alpha=0.6)
    p.shine([(0.26, 0.44), (0.42, 0.35)], 0.02, 0.35)


def a_cheese(p):
    wedge = [(0.10, 0.68), (0.84, 0.30), (0.90, 0.46), (0.90, 0.66), (0.16, 0.84)]
    p.paint(p.poly_mask(wedge), CHEESE, grain=0.12)
    p.paint(p.poly_mask([(0.10, 0.68), (0.84, 0.30), (0.90, 0.46), (0.16, 0.80)]), (CHEESE[1], CHEESE[2], CHEESE[2]), edge=0.02)
    p.paint(p.poly_mask([(0.84, 0.30), (0.90, 0.46), (0.90, 0.66), (0.86, 0.50)]), ((150, 60, 30), (190, 80, 40), (220, 120, 70)))
    for c, r in (((0.40, 0.70), 0.04), ((0.62, 0.62), 0.03), ((0.28, 0.76), 0.025), ((0.74, 0.56), 0.02)):
        p.paint(p.ellipse_mask(c, r), (CHEESE[0], CHEESE[0], CHEESE[1]), edge=0.0)


def a_meat(p):
    p.paint(p.poly_mask(along((0.62, 0.38), (0.90, 0.10), [(0.0, 0.035), (1.0, 0.030)])), BONE)
    p.paint(p.ellipse_mask((0.88, 0.08), 0.045), BONE, edge=0.01)
    p.paint(p.ellipse_mask((0.94, 0.14), 0.045), BONE, edge=0.01)
    p.paint(p.ellipse_mask((0.42, 0.58), 0.33, 0.27), MEAT, gloss=0.25, grain=0.14)
    p.stroke([(0.24, 0.52), (0.40, 0.44), (0.56, 0.46)], 0.02, MEAT[2], alpha=0.5)
    p.stroke([(0.22, 0.66), (0.44, 0.60), (0.62, 0.64)], 0.014, MEAT[0], alpha=0.6)


def a_drink(p):
    body = [(0.22, 0.26), (0.70, 0.26), (0.68, 0.88), (0.24, 0.88)]
    p.paint(p.poly_mask(body), OAK, streak=0.3, streak_dir=(0, 1))
    for y in (0.36, 0.78):
        p.paint(p.poly_mask([(0.21, y), (0.71, y), (0.71, y + 0.05), (0.21, y + 0.05)]), IRON, gloss=0.3, edge=0.01)
    handle = p.ellipse_mask((0.72, 0.56), 0.16, 0.20) - p.ellipse_mask((0.72, 0.56), 0.09, 0.13)
    p.paint(np.clip(handle * (p.x > 0.70), 0, 1), OAK)
    foam = np.clip(p.ellipse_mask((0.34, 0.24), 0.14, 0.09) + p.ellipse_mask((0.52, 0.22), 0.14, 0.10)
                   + p.ellipse_mask((0.64, 0.26), 0.10, 0.08), 0, 1)
    p.paint(foam, WAX, grain=0.05)


def a_pie(p):
    p.paint(p.ellipse_mask((0.50, 0.60), 0.40, 0.24), (BREAD[0], BREAD[1], BREAD[1]))
    p.paint(p.ellipse_mask((0.50, 0.55), 0.36, 0.20), BREAD, gloss=0.2, grain=0.14)
    for a in np.linspace(0, math.tau, 16, endpoint=False):
        p.paint(p.ellipse_mask((0.50 + math.cos(a) * 0.36, 0.56 + math.sin(a) * 0.21), 0.035), BREAD, edge=0.0)
    for x in (0.40, 0.50, 0.60):
        p.stroke([(x, 0.48), (x + 0.02, 0.58)], 0.018, BREAD[0], alpha=0.8)


def a_herb(p):
    p.stroke([(0.50, 0.94), (0.48, 0.60), (0.54, 0.20)], 0.024, LEAF[0])
    for side, y, s in ((1, 0.30, 0.9), (-1, 0.40, 1.0), (1, 0.52, 1.1), (-1, 0.62, 1.0), (1, 0.74, 0.8)):
        base = (0.50, y)
        tip = (0.50 + side * 0.30 * s, y - 0.12 * s)
        p.paint(p.poly_mask(along(base, tip, [(0.0, 0.01), (0.45, 0.07 * s), (1.0, 0.0)])), LEAF, gloss=0.15)
        p.stroke([base, lerp(base, tip, 0.85)], 0.008, LEAF[0], alpha=0.6)
    p.paint(p.ellipse_mask((0.55, 0.16), 0.05), ((120, 60, 120), (180, 110, 190), (230, 190, 240)))


def a_torch(p):
    p0, p1 = (0.30, 0.94), (0.58, 0.40)
    p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.028), (1.0, 0.036)])), OAK, streak=0.3, streak_dir=(0.5, -0.9))
    p.paint(p.poly_mask(along((0.55, 0.46), (0.66, 0.26), [(0.0, 0.07), (1.0, 0.08)])), CLOTH, streak=0.3)
    for t in (0.25, 0.55, 0.85):
        a = lerp((0.55, 0.46), (0.66, 0.26), t)
        p.stroke([(a[0] - 0.07, a[1] + 0.03), (a[0] + 0.07, a[1] - 0.03)], 0.012, LEATHER[0], alpha=0.7)
    p.glow((0.66, 0.16), 0.30, (255, 170, 70), 0.55)
    flame = [(0.58, 0.28), (0.54, 0.16), (0.62, 0.02), (0.66, 0.12), (0.74, 0.04), (0.76, 0.20), (0.72, 0.30)]
    p.paint(p.poly_mask(flame), EMBER, gloss=0.4, edge=0.02, grain=0.05)
    p.paint(p.poly_mask([(0.62, 0.28), (0.61, 0.18), (0.66, 0.10), (0.70, 0.20), (0.68, 0.28)]),
            ((250, 200, 90), (255, 236, 160), (255, 252, 230)), edge=0.0)


def a_lantern(p):
    p.stroke([(0.38, 0.16), (0.50, 0.04), (0.62, 0.16)], 0.02, BRASS[0])
    p.paint(p.poly_mask([(0.28, 0.16), (0.72, 0.16), (0.66, 0.26), (0.34, 0.26)]), BRASS, gloss=0.35)
    p.glow((0.50, 0.54), 0.30, (255, 190, 90), 0.55)
    p.paint(p.poly_mask([(0.32, 0.26), (0.68, 0.26), (0.66, 0.80), (0.34, 0.80)]),
            ((180, 110, 40), (240, 180, 90), (255, 236, 170)), alpha=0.9, gloss=0.3)
    p.paint(p.poly_mask([(0.47, 0.62), (0.45, 0.52), (0.50, 0.40), (0.55, 0.52), (0.53, 0.62)]),
            ((250, 200, 90), (255, 236, 160), (255, 252, 230)), edge=0.0)
    for x in (0.32, 0.50, 0.68):
        p.stroke([(x, 0.26), (x - (x - 0.5) * 0.06, 0.80)], 0.022, BRASS[0])
    p.paint(p.poly_mask([(0.28, 0.80), (0.72, 0.80), (0.74, 0.90), (0.26, 0.90)]), BRASS, gloss=0.35)


def a_candle(p):
    p.paint(p.ellipse_mask((0.50, 0.84), 0.28, 0.08), BRASS, gloss=0.3)
    p.paint(p.poly_mask([(0.40, 0.36), (0.60, 0.36), (0.60, 0.82), (0.40, 0.82)]), WAX)
    p.stroke([(0.58, 0.38), (0.59, 0.52)], 0.02, WAX[2], alpha=0.8)
    p.glow((0.50, 0.24), 0.22, (255, 180, 80), 0.5)
    p.paint(p.poly_mask([(0.46, 0.34), (0.45, 0.24), (0.50, 0.10), (0.55, 0.24), (0.54, 0.34)]), EMBER, edge=0.01)


def a_lockpick(p):
    for p0, p1, hook in (((0.14, 0.86), (0.80, 0.22), 1), ((0.24, 0.90), (0.88, 0.34), -1)):
        p.paint(p.poly_mask(along(p0, p1, [(0.0, 0.026), (1.0, 0.018)])), STEEL, gloss=0.4)
        tip = p1
        p.stroke([tip, (tip[0] + 0.06, tip[1] + 0.06 * hook)], 0.026, STEEL[1])
        p.paint(p.poly_mask(along(p0, lerp(p0, p1, 0.25), [(0.0, 0.046), (1.0, 0.046)])), LEATHER)


def a_rope(p):
    for k, r in enumerate((0.34, 0.27, 0.20)):
        ring = p.ellipse_mask((0.50, 0.54), r, r * 0.86) - p.ellipse_mask((0.50, 0.54), r - 0.06, (r - 0.06) * 0.86)
        p.paint(np.clip(ring, 0, 1), HEMP, grain=0.15, streak=0.4, streak_dir=(1, 1), edge=0.015)
    p.paint(p.poly_mask(along((0.66, 0.74), (0.90, 0.92), [(0.0, 0.03), (1.0, 0.03)])), HEMP, streak=0.4)


def a_bell(p):
    body = [(0.50, 0.14), (0.64, 0.20), (0.68, 0.46), (0.82, 0.74), (0.18, 0.74), (0.32, 0.46), (0.36, 0.20)]
    p.paint(p.poly_mask(body), BRONZE, gloss=0.45)
    p.paint(p.poly_mask([(0.14, 0.72), (0.86, 0.72), (0.86, 0.80), (0.14, 0.80)]), BRONZE, gloss=0.3)
    p.paint(p.ellipse_mask((0.50, 0.86), 0.06), IRON)
    p.stroke([(0.44, 0.14), (0.50, 0.06), (0.56, 0.14)], 0.02, BRONZE[0])
    p.shine([(0.36, 0.64), (0.40, 0.30)], 0.02, 0.5)


def a_pouch(p):
    body = [(0.22, 0.44), (0.78, 0.44), (0.86, 0.72), (0.70, 0.90), (0.30, 0.90), (0.14, 0.72)]
    p.paint(p.poly_mask(body), LEATHER, grain=0.14)
    p.paint(p.poly_mask([(0.30, 0.26), (0.70, 0.26), (0.78, 0.46), (0.22, 0.46)]), (LEATHER[0], LEATHER[1], LEATHER[1]))
    p.stroke([(0.24, 0.46), (0.76, 0.46)], 0.02, HEMP[1])
    p.paint(p.ellipse_mask((0.50, 0.47), 0.05), BRASS, gloss=0.5)


def a_key(p):
    p0, p1 = (0.18, 0.82), (0.80, 0.22)
    ring = p.ellipse_mask((0.28, 0.72), 0.14) - p.ellipse_mask((0.28, 0.72), 0.07)
    p.paint(np.clip(ring, 0, 1), IRON, gloss=0.35, edge=0.01)
    p.paint(p.poly_mask(along((0.36, 0.64), p1, [(0.0, 0.026), (1.0, 0.022)])), IRON, gloss=0.35)
    p.paint(p.poly_mask(along((0.66, 0.36), (0.78, 0.48), [(0.0, 0.03), (1.0, 0.03)])), IRON, gloss=0.3)


ART = {
    "sword": a_sword, "greatsword": a_greatsword, "dagger": a_dagger, "axe": a_axe, "mace": a_mace,
    "hammer": a_hammer, "spear": a_spear, "bow": a_bow, "crossbow": a_crossbow, "staff": a_staff,
    "shield": a_shield, "sword_shield": a_sword_shield,
    "potion_red": a_potion_red, "potion_blue": a_potion_blue, "potion_green": a_potion_green,
    "potion_amber": a_potion_amber, "potion_violet": a_potion_violet, "poison": a_poison,
    "hearth_flask": a_hearth_flask, "bread": a_bread, "cheese": a_cheese, "meat": a_meat,
    "drink": a_drink, "pie": a_pie, "herb": a_herb, "torch": a_torch, "lantern": a_lantern,
    "candle": a_candle, "lockpick": a_lockpick, "rope": a_rope, "bell": a_bell, "pouch": a_pouch,
    "key": a_key,
}


def art(name: str, rng: np.random.Generator, size: int = 96) -> Image.Image:
    p = Painter(size, rng)
    ART[name](p)
    return p.finish()


# --------------------------------------------------------------------------------------------
# the belt's chrome
# --------------------------------------------------------------------------------------------

def _ramp_fill(mask, ramp, t):
    dark, body, lite = (np.array(c, np.float32) for c in ramp)
    lo = dark + (body - dark) * np.clip(t * 2.0, 0, 1)[..., None]
    return np.where((t < 0.5)[..., None], lo, body + (lite - body) * np.clip(t * 2.0 - 1.0, 0, 1)[..., None])


def socket(rng: np.random.Generator, size: int = 64, lit: bool = False) -> Image.Image:
    """A belt socket: a rounded square dark-oak well, sunk, with a brass bezel round it."""
    n = size * SS
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) / n
    grain = _fbm(n, n, rng, 5, 6)

    def rrect(inset, radius):
        img = Image.new("L", (n, n), 0)
        ImageDraw.Draw(img).rounded_rectangle([inset * n, inset * n, (1 - inset) * n, (1 - inset) * n],
                                              radius=radius * n, fill=255)
        return np.asarray(img, np.float32) / 255.0

    outer = rrect(0.02, 0.16)
    bezel_in = rrect(0.085, 0.11)
    well = rrect(0.10, 0.10)
    t_lit = np.clip(0.5 + 0.5 * ((0.5 - xs) * 0.6 + (0.5 - ys) * 0.8) * 1.6, 0, 1)
    brass = ((80, 56, 20), (140, 106, 46), (200, 170, 100)) if not lit else ((140, 100, 36), (214, 172, 84), (252, 232, 160))
    col_bezel = _ramp_fill(outer, brass, t_lit) * (0.85 + 0.3 * grain)[..., None]
    # the well: dark oak, lit from the far side (it is sunk), a vignette to its edges
    t_well = 1.0 - t_lit
    col_well = _ramp_fill(well, ((26, 18, 12), (52, 36, 24), (86, 62, 40)), t_well * 0.8)
    wood = 0.9 + 0.2 * np.sin(ys * n * 0.12 + grain * 10.0)
    col_well *= wood[..., None]
    b = np.asarray(Image.fromarray((well * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(n * 0.06)),
                   np.float32) / 255.0
    col_well *= (0.45 + 0.55 * np.clip((b - 0.3) / 0.6, 0, 1))[..., None]
    if lit:
        glow = np.clip(1.0 - np.sqrt((xs - 0.5) ** 2 + (ys - 0.5) ** 2) / 0.42, 0, 1) ** 2
        col_well += (np.array((120, 84, 36), np.float32) * glow[..., None] * 0.6)
    rgb = np.where((well > 0.5)[..., None], col_well, col_bezel)
    # the bezel's inner lip, a dark line where brass meets the well
    lip = np.clip(bezel_in - well, 0, 1)
    rgb = rgb * (1 - lip[..., None] * 0.6)
    # rivets at the corners
    for cx, cy in ((0.07, 0.07), (0.93, 0.07), (0.07, 0.93), (0.93, 0.93)):
        d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
        r = np.clip(1.0 - d / 0.026, 0, 1)
        rgb = rgb * (1 - (r > 0)[..., None] * 0.4) + np.array(brass[2], np.float32) * (r ** 0.5)[..., None] * 0.6
    alpha = outer
    ink = np.clip(np.asarray(Image.fromarray((outer * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(9)),
                             np.float32) / 255.0 - outer, 0, 1)
    rgb = rgb * alpha[..., None] + np.array(INK, np.float32) * ink[..., None]
    a = np.clip(alpha + ink, 0, 1)
    rgb = rgb / np.maximum(a, 1e-5)[..., None]
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), "RGBA")
    return img.resize((size, size), Image.LANCZOS)


def strap(rng: np.random.Generator, w: int = 128, h: int = 48) -> Image.Image:
    """The strap the sockets sit on: dark oak-stained leather, stitched along both edges, bound in
    brass at its ends (a nine-patch: its ends are its margins)."""
    n_w, n_h = w * SS, h * SS
    ys, xs = np.mgrid[0:n_h, 0:n_w].astype(np.float32)
    ys /= n_h
    xs /= n_w
    grain = _fbm(n_w, n_h, rng, 5, 6)
    img = Image.new("L", (n_w, n_h), 0)
    ImageDraw.Draw(img).rounded_rectangle([0, 0.10 * n_h, n_w - 1, 0.90 * n_h], radius=0.18 * n_h, fill=255)
    m = np.asarray(img, np.float32) / 255.0
    t = np.clip(1.0 - (ys - 0.10) / 0.8, 0, 1)
    col = _ramp_fill(m, ((30, 20, 14), (62, 42, 28), (104, 74, 50)), t * 0.9)
    col *= (0.82 + 0.3 * grain)[..., None]
    # stitches
    for y in (0.22, 0.78):
        on = (np.abs(ys - y) < 0.022) & (np.mod(xs * n_w / SS, 7.0) < 4.0)
        col[on] = np.array((190, 160, 110), np.float32) * 0.8
    # brass end caps
    cap = ((xs < 0.12) | (xs > 0.88)) & (m > 0.5)
    tb = np.clip(0.5 + (0.5 - ys) * 1.2, 0, 1)
    brass = _ramp_fill(m, BRASS, tb)
    col[cap] = brass[cap] * (0.85 + 0.3 * grain[cap])[..., None]
    for cx in (0.06, 0.94):
        d = np.sqrt(((xs - cx) * n_w / n_h) ** 2 + (ys - 0.5) ** 2)
        r = np.clip(1.0 - d / 0.12, 0, 1)
        col = col * (1 - (r > 0)[..., None] * 0.3) + np.array(BRASS[2], np.float32) * (r ** 0.6)[..., None] * 0.5
    ink = np.clip(np.asarray(Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(7)),
                             np.float32) / 255.0 - m, 0, 1)
    rgb = col * m[..., None] + np.array(INK, np.float32) * ink[..., None]
    a = np.clip(m + ink, 0, 1)
    rgb = rgb / np.maximum(a, 1e-5)[..., None]
    out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), "RGBA")
    return out.resize((w, h), Image.LANCZOS)


def key_tab(rng: np.random.Generator, w: int = 32, h: int = 24) -> Image.Image:
    """The brass tab a socket's key is stamped on (nine-patch, 8 px margins)."""
    n_w, n_h = w * SS, h * SS
    ys = np.mgrid[0:n_h, 0:n_w][0].astype(np.float32) / n_h
    img = Image.new("L", (n_w, n_h), 0)
    ImageDraw.Draw(img).rounded_rectangle([SS, SS, n_w - SS, n_h - SS], radius=0.3 * n_h, fill=255)
    m = np.asarray(img, np.float32) / 255.0
    col = _ramp_fill(m, BRASS, np.clip(1.0 - ys, 0, 1))
    col *= (0.9 + 0.2 * _fbm(n_w, n_h, rng, 4, 4))[..., None]
    ink = np.clip(np.asarray(Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(5)),
                             np.float32) / 255.0 - m, 0, 1)
    rgb = col * m[..., None] + np.array(INK, np.float32) * ink[..., None]
    a = np.clip(m + ink, 0, 1)
    rgb = rgb / np.maximum(a, 1e-5)[..., None]
    out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), "RGBA")
    return out.resize((w, h), Image.LANCZOS)


def contact_sheet(path: Path, rng_for) -> None:
    names = sorted(ART)
    cols = 8
    cell = 112
    rows = (len(names) + cols - 1) // cols + 1
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (58, 44, 32, 255))
    for i, name in enumerate(names):
        s = socket(rng_for("socket"), 104, lit=(i % 5 == 0))
        sheet.alpha_composite(s, ((i % cols) * cell + 4, (i // cols) * cell + 4))
        a = art(name, rng_for("art" + name), 80)
        sheet.alpha_composite(a, ((i % cols) * cell + 16, (i // cols) * cell + 16))
    y = (rows - 1) * cell
    sheet.alpha_composite(strap(rng_for("strap"), 512, 48), (8, y + 10))
    sheet.alpha_composite(key_tab(rng_for("tab"), 64, 48), (540, y + 10))
    sheet.convert("RGB").save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", type=Path, required=True)
    args = ap.parse_args()
    contact_sheet(args.sheet, lambda salt: np.random.default_rng(abs(hash(salt)) % (2 ** 32)))
    print("[items] sheet ->", args.sheet)
