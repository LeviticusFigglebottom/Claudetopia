"""Tiling bark, painted per species (pure numpy + PIL; no bpy).

The grown trees (lib/grow.py) are tubes whose UVs run round the wood (u) and along it (v) at one
scale on every limb, so their bark is one tile that repeats, not an atlas baked off one trunk:
the same crisp furrows on a hawthorn's twig and a giant oak's bole, and one set of maps shared by
every variant of a species. Rows of the image run along the grain.

Each style is a few seamless noise fields (FFT-filtered, so they wrap) and, for plated barks, a
wrapping Voronoi: oak's interlacing furrows are the zero-crossings of noise stretched along the
grain, a pine's plates and a yew's flakes are cells, a rowan's smooth grey skin carries lenticels.
Colour is kept broad and low in detail -- a painted surface, not a photograph -- and nudged toward
the region's own earth colour.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

# style, base, light, dark (sRGB hex), accent (lichen/moss or the second flake colour), feature scale
STYLES = {
    "oak": ("furrowed", "#5f564b", "#8b8172", "#2a241e", "#7b8a55", 1.0),
    "giant_oak": ("furrowed", "#534b41", "#7f7666", "#1f1a15", "#5f7a3a", 1.4),
    "apple": ("scaly", "#66584a", "#8f8170", "#342a22", "#8a8a62", 0.8),
    "hawthorn": ("scaly", "#625c55", "#8a847a", "#2e2925", "#7b8656", 0.7),
    "yew": ("flaky", "#7a4230", "#a3674a", "#3a1f18", "#6d5c62", 0.9),
    "black_ash": ("furrowed", "#403c38", "#67625a", "#1b1816", "#5b6a48", 0.8),
    "hardy_pine": ("plated", "#7d4c33", "#b07550", "#2e211b", "#5d5048", 1.0),
    "rowan": ("smooth", "#7f7a73", "#a29d94", "#3f3a35", "#8a9068", 1.0),
    "juniper": ("shreddy", "#6a4634", "#93684f", "#2c1d16", "#7a6e62", 0.6),
    "willow": ("furrowed", "#5b5247", "#857a69", "#251f1a", "#6f7d4c", 1.2),
    "alder": ("furrowed", "#4b433b", "#6c6358", "#1f1a16", "#667348", 0.7),
    "willow_pollard": ("furrowed", "#665c4f", "#8e8373", "#2b241e", "#788a50", 1.0),
    "lime": ("ridged", "#6b6358", "#8f8778", "#2f2a24", "#7c8858", 1.0),
    "birch": ("birch", "#d9d4c8", "#efebe2", "#26211d", "#9a9a86", 1.0),
    "hazel": ("smooth", "#7a5a44", "#9c7a5e", "#3b2a20", "#8a8a66", 1.0),
    "dead_ash_tree": ("furrowed", "#75726c", "#9b9890", "#34302c", "#8a8578", 0.8),
    "char_stump": ("charred", "#1f1b19", "#4a4541", "#0b0909", "#6e6258", 1.0),
}


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur that wraps (the tile's edges meet), by FFT; 2-D or 2-D x channels.
    Plain numpy, because Blender's bundled numpy is too old for the system's scipy."""
    n0, n1 = a.shape[:2]
    fy = np.fft.fftfreq(n0)[:, None]
    fx = np.fft.fftfreq(n1)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    if a.ndim == 3:
        return np.dstack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g)) for c in range(a.shape[2])])
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def _hex(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def noise(n: int, rng, sx: float, sy: float) -> np.ndarray:
    """Seamless gaussian noise; sx, sy are feature sizes in pixels across and along the grain."""
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    spec = (rng.standard_normal((n, n)) + 1j * rng.standard_normal((n, n))) \
        * np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2))
    out = np.real(np.fft.ifft2(spec))
    return (out - out.mean()) / (out.std() + 1e-9)


def voronoi(n: int, rng, cells_x: int, cells_y: int, warp=None):
    """Wrapping Voronoi on an n x n tile: (F2 - F1 in pixels, cell id)."""
    pts = []
    for j in range(cells_y):
        for i in range(cells_x):
            pts.append(((i + rng.uniform(0.1, 0.9)) * n / cells_x, (j + rng.uniform(0.1, 0.9)) * n / cells_y))
    pts = np.array(pts)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    if warp is not None:
        xx = xx + warp[0]
        yy = yy + warp[1]
    f1 = np.full((n, n), 1e9, np.float32)
    f2 = np.full((n, n), 1e9, np.float32)
    cid = np.zeros((n, n), np.int32)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx % n, n - dx % n)
        dy = np.abs(yy - py)
        dy = np.minimum(dy % n, n - dy % n)
        d = np.sqrt(dx * dx * (cells_x / cells_y) ** 0 + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cid = np.where(closer, k, cid)
        f1 = np.where(closer, d, f1)
    return f2 - f1, cid


def paint(kind: str, size: int = 512, seed: int = 0, tint=None, tint_amount: float = 0.12):
    """(albedo sRGB RGB uint8, normal RGB uint8 (+Y up), orm RGB uint8) for a species' bark."""
    style, base, light, dark, accent, scale = STYLES.get(kind, STYLES["oak"])
    rng = np.random.default_rng(seed)
    n = size
    base, light, dark, accent = _hex(base), _hex(light), _hex(dark), _hex(accent)
    if tint is not None:
        t = np.asarray(tint[:3], dtype=float)
        base = base * (1 - tint_amount) + t * tint_amount
        light = light * (1 - tint_amount * 0.6) + t * tint_amount * 0.6
    broad = noise(n, rng, 90, 140)                      # the painter's big, soft variation
    patch = noise(n, rng, 45, 45)
    height = np.zeros((n, n))
    mix_light = np.zeros((n, n))
    mix_dark = np.zeros((n, n))
    accent_w = np.clip((patch - 1.0) * 0.8, 0, 0.55)
    if style in ("furrowed", "ridged"):
        # interlacing furrows: where noise stretched along the grain crosses zero
        across = 20.0 * scale if style == "furrowed" else 12.0 * scale
        f = noise(n, rng, across, 120.0 * scale)
        f2 = noise(n, rng, across * 0.45, 60.0 * scale)
        field = f + 0.3 * f2
        width = 0.42 if style == "furrowed" else 0.3
        crack = 1.0 - np.clip(np.abs(field) / width, 0.0, 1.0)
        crack = crack ** 1.6
        ridge = np.clip(np.abs(field) - width, 0, 2.0)
        height = 0.55 + 0.25 * np.tanh(ridge) - 0.6 * crack
        mix_light = np.clip(np.tanh(ridge * 1.2) * 0.6 + 0.12 * broad, 0, 1)
        mix_dark = np.clip(crack * 1.1, 0, 1)
        if style == "ridged":
            mix_light *= 0.6
    elif style in ("scaly", "flaky", "plated"):
        cx = {"scaly": 7, "flaky": 5, "plated": 4}[style]
        cy = {"scaly": 11, "flaky": 7, "plated": 7}[style]
        warp = (noise(n, rng, 60, 60) * 5, noise(n, rng, 60, 60) * 5)
        edge, cid = voronoi(n, rng, max(2, int(cx / scale)), max(2, int(cy / scale)), warp)
        w = {"scaly": 5.0, "flaky": 4.0, "plated": 8.0}[style]
        crack = 1.0 - np.clip(edge / w, 0, 1)
        per = rng.uniform(-1, 1, cid.max() + 1)[cid]
        dome = np.clip(edge / (w * 4), 0, 1) ** 0.5
        height = 0.35 + 0.45 * dome - 0.45 * crack + 0.05 * per
        mix_light = np.clip(0.35 * dome + 0.25 * per + 0.1 * broad, 0, 1)
        mix_dark = np.clip(crack, 0, 1)
        if style == "flaky":
            # a yew's two colours: fresh red-brown where old plates have fallen, purple-grey where not
            accent_w = np.clip(0.55 * (per > 0.15) * dome, 0, 0.6)
        if style == "plated":
            accent_w = np.clip((patch - 0.6) * 0.5, 0, 0.35)
    elif style == "smooth":
        height = 0.55 + 0.04 * noise(n, rng, 20, 20)
        lent = noise(n, rng, 2.5, 1.2)                  # lenticels: short dashes across the grain
        dash = np.clip((lent - 2.3) * 2.0, 0, 1)
        height -= 0.25 * dash
        mix_light = np.clip(0.2 + 0.25 * broad, 0, 1)
        mix_dark = np.clip(dash * 0.8 + np.clip(noise(n, rng, 6, 90) - 1.8, 0, 1) * 0.5, 0, 1)
    elif style == "birch":
        # white papery skin, dark lenticel bands across the grain, and dark fissured patches
        height = 0.55 + 0.03 * noise(n, rng, 25, 25)
        band = noise(n, rng, 14, 2.2)
        dash = np.clip((band - 1.9) * 1.6, 0, 1)
        blotch = np.clip((noise(n, rng, 30, 70) - 1.2) * 1.3, 0, 1)
        fis = 1.0 - np.clip(np.abs(noise(n, rng, 10, 60)) / 0.25, 0, 1)
        dark_patch = np.clip(blotch * (0.4 + fis), 0, 1)
        height -= 0.3 * dash + 0.25 * dark_patch * fis
        mix_light = np.clip(0.4 + 0.2 * broad, 0, 1)
        mix_dark = np.clip(dash * 0.85 + dark_patch * 0.8, 0, 1)
        accent_w = np.clip((patch - 1.4) * 0.3, 0, 0.25)
    elif style == "shreddy":
        fib = noise(n, rng, 6.0 * scale, 140)
        strip = np.clip(fib * 0.8, -1, 1)
        crack = np.clip((np.abs(fib) < 0.18) * 1.0, 0, 1)
        height = 0.5 + 0.25 * strip - 0.3 * crack
        mix_light = np.clip(0.5 * strip + 0.1 * broad, 0, 1)
        mix_dark = crack * 0.9
    elif style == "charred":
        warp = (noise(n, rng, 25, 25) * 8, noise(n, rng, 25, 25) * 8)
        edge, cid = voronoi(n, rng, 9, 6, warp)
        crack = 1.0 - np.clip(edge / 3.0, 0, 1)
        per = rng.uniform(-1, 1, cid.max() + 1)[cid]
        height = 0.45 + 0.3 * np.clip(edge / 12, 0, 1) - 0.45 * crack
        mix_light = np.clip(0.15 * per + 0.2 * np.clip(noise(n, rng, 40, 60) - 0.8, 0, 1), 0, 1)
        mix_dark = crack
        accent_w = np.clip((patch - 1.3) * 0.5, 0, 0.3)
    alb = base[None, None, :] * (1.0 + 0.10 * broad[..., None])
    alb = alb * (1 - mix_light[..., None]) + light * mix_light[..., None]
    alb = alb * (1 - accent_w[..., None]) + accent * accent_w[..., None]
    alb = alb * (1 - mix_dark[..., None]) + dark * mix_dark[..., None]
    alb = np.clip(alb, 0.0, 1.0)
    # soften: a painted surface has no pixel grain
    alb = blur(alb, 0.7)
    h = blur(height, 1.0)
    gy, gx = np.gradient(h)
    k = 7.0
    nrm = np.dstack([-gx * k * n / 512, gy * k * n / 512, np.ones_like(h)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    ao = np.clip(1.0 - 0.65 * mix_dark, 0, 1)
    rough = np.clip(0.82 + 0.1 * mix_dark - 0.05 * mix_light, 0, 1)
    orm = np.dstack([ao, rough, np.zeros_like(h)])
    to8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    return to8(alb), to8(nrm * 0.5 + 0.5), to8(orm)


def write(out_dir, prefix: str, kind: str, size: int = 512, seed: int = 0, tint=None) -> dict:
    """Paint and save <prefix>_albedo/_normal/_orm.png; returns the file names by slot."""
    from pathlib import Path
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    alb, nrm, orm = paint(kind, size, seed, tint)
    names = {"albedo": "%s_albedo.png" % prefix, "normal": "%s_normal.png" % prefix, "orm": "%s_orm.png" % prefix}
    # a painted bark has a few hundred colours, not millions: a palette PNG is a third the size
    # and Godot compresses it to the same VRAM texture
    _save_atomic(Image.fromarray(alb, "RGB").quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE),
                 out_dir / names["albedo"])
    _save_atomic(Image.fromarray(nrm, "RGB"), out_dir / names["normal"])
    _save_atomic(Image.fromarray(orm, "RGB").resize((size // 4, size // 4), Image.BILINEAR), out_dir / names["orm"])
    return names


def _save_atomic(img, path) -> None:
    """Write beside and rename, so two builds of one species never leave a torn file."""
    import os
    tmp = path.with_name(".%s.%d.tmp.png" % (path.name, os.getpid()))
    img.save(tmp, optimize=True)
    os.replace(tmp, path)
