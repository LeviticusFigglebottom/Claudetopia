"""Texture painting for the character forge: bake 3D procedural functions into UV maps.

A character's UVs come from Blender's smart projection, so their layout is unknown at
authoring time.  Painting therefore happens in *3D*: this module rasterises the mesh's UV
triangles, recovers the surface position and normal behind every texel, and hands them to
a function that returns colour.  The same function then works on any head, any UV layout
and any resolution, and there are no seams to hide because neighbouring texels of a seam
sample the same 3D neighbourhood.

numpy + PIL only (both available inside Blender's Python).
"""
from __future__ import annotations

import math
from typing import Callable, Dict, Optional, Sequence, Tuple

import numpy as np

RGB = Tuple[float, float, float]
PaintFn = Callable[[np.ndarray, np.ndarray], np.ndarray]     # (pos (n,3), normal (n,3)) -> rgb (n,3)


# --------------------------------------------------------------------------------------
# colour helpers
# --------------------------------------------------------------------------------------

def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(np.asarray(c, float), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def mix(a, b, t) -> np.ndarray:
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    t = np.asarray(t, float)
    if a.ndim == 1 and t.ndim >= 1:
        a = np.broadcast_to(a, (len(t), 3))
    if b.ndim == 1 and t.ndim >= 1:
        b = np.broadcast_to(b, (len(t), 3))
    if t.ndim == 1 and a.ndim == 2:
        t = t[:, None]
    return a + (b - a) * t


def hsv_shift(rgb: np.ndarray, dh: float = 0.0, ds: float = 1.0, dv: float = 1.0) -> np.ndarray:
    """Cheap HSV tweak on an (n,3) array."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.max(rgb, axis=-1)
    mn = np.min(rgb, axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-9
    idx = (mx == r) & m
    h[idx] = ((g - b)[idx] / d[idx]) % 6
    idx = (mx == g) & m
    h[idx] = ((b - r)[idx] / d[idx]) + 2
    idx = (mx == b) & m
    h[idx] = ((r - g)[idx] / d[idx]) + 4
    h = (h / 6.0 + dh) % 1.0
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0) * ds
    v = mx * dv
    s = np.clip(s, 0, 1)
    v = np.clip(v, 0, 1)
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    out = np.zeros_like(rgb)
    for k, (rr, gg, bb) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel, 0] = rr[sel]
        out[sel, 1] = gg[sel]
        out[sel, 2] = bb[sel]
    return out


# --------------------------------------------------------------------------------------
# value noise (3D, seeded, no dependencies)
# --------------------------------------------------------------------------------------

class Noise:
    def __init__(self, seed: int = 0, size: int = 64):
        self.size = size
        rng = np.random.default_rng(seed)
        self.g = rng.random((size, size, size)).astype(np.float32)

    def at(self, p: np.ndarray, freq: float = 1.0) -> np.ndarray:
        q = np.asarray(p, float) * freq
        i = np.floor(q).astype(np.int64)
        f = q - i
        f = f * f * (3 - 2 * f)
        s = self.size
        c = {}
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    c[(dx, dy, dz)] = self.g[(i[:, 0] + dx) % s, (i[:, 1] + dy) % s, (i[:, 2] + dz) % s]
        x00 = c[(0, 0, 0)] + (c[(1, 0, 0)] - c[(0, 0, 0)]) * f[:, 0]
        x10 = c[(0, 1, 0)] + (c[(1, 1, 0)] - c[(0, 1, 0)]) * f[:, 0]
        x01 = c[(0, 0, 1)] + (c[(1, 0, 1)] - c[(0, 0, 1)]) * f[:, 0]
        x11 = c[(0, 1, 1)] + (c[(1, 1, 1)] - c[(0, 1, 1)]) * f[:, 0]
        y0 = x00 + (x10 - x00) * f[:, 1]
        y1 = x01 + (x11 - x01) * f[:, 1]
        return y0 + (y1 - y0) * f[:, 2]

    def fbm(self, p: np.ndarray, freq: float = 1.0, octaves: int = 4, gain: float = 0.5, lac: float = 2.03) -> np.ndarray:
        out = np.zeros(len(p))
        amp = 1.0
        tot = 0.0
        for _ in range(octaves):
            out = out + self.at(p, freq) * amp
            tot += amp
            amp *= gain
            freq *= lac
        return out / max(tot, 1e-9)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((np.asarray(x, float) - e0) / max(e1 - e0, 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gauss(p: np.ndarray, c, s) -> np.ndarray:
    d = (p - np.asarray(c, float)) / np.asarray(s, float)
    return np.exp(-0.5 * np.sum(d * d, axis=1))


def ellipse_mask(p: np.ndarray, c, r, soft: float = 0.25) -> np.ndarray:
    """1 inside an axis-aligned ellipsoid, fading over `soft` of the radius."""
    d = np.linalg.norm((p - np.asarray(c, float)) / np.asarray(r, float), axis=1)
    return 1.0 - smoothstep(1.0 - soft, 1.0, d)


# --------------------------------------------------------------------------------------
# UV rasteriser
# --------------------------------------------------------------------------------------

def surface_maps(ob, size: int = 1024, pad: int = 4) -> Dict[str, np.ndarray]:
    """For every texel of the UV layout, the 3D position and normal behind it.

    Returns {"pos": (size,size,3), "nrm": (size,size,3), "mask": (size,size) bool}.
    `pad` dilates the covered area so bilinear filtering never samples empty texels."""
    me = ob.data
    me.calc_loop_triangles()
    nv = len(me.vertices)
    co = np.empty(nv * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    nrm = np.empty(nv * 3)
    me.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)
    uv_layer = me.uv_layers.active
    if uv_layer is None:
        raise ValueError(f"{ob.name} has no UV map")
    nl = len(me.loops)
    uvs = np.empty(nl * 2)
    uv_layer.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    tri_loops = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("loops", tri_loops)
    tri_loops = tri_loops.reshape(-1, 3)
    tri_verts = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tri_verts)
    tri_verts = tri_verts.reshape(-1, 3)

    pos_map = np.zeros((size, size, 3))
    nrm_map = np.zeros((size, size, 3))
    mask = np.zeros((size, size), dtype=bool)
    uv_px = uvs * size - 0.5
    for t in range(len(tri_verts)):
        a, b, c = uv_px[tri_loops[t]]
        x0 = max(int(math.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(math.ceil(max(a[0], b[0], c[0]))) + 1, size)
        y0 = max(int(math.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(math.ceil(max(a[1], b[1], c[1]))) + 1, size)
        if x1 <= x0 or y1 <= y0:
            continue
        xs = np.arange(x0, x1)
        ys = np.arange(y0, y1)
        gx, gy = np.meshgrid(xs, ys)
        px = gx.ravel().astype(float)
        py = gy.ravel().astype(float)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / d
        w1 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / d
        w2 = 1.0 - w0 - w1
        eps = -0.002
        inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
        if not inside.any():
            continue
        vi = tri_verts[t]
        P = (co[vi[0]] * w0[inside, None] + co[vi[1]] * w1[inside, None] + co[vi[2]] * w2[inside, None])
        N = (nrm[vi[0]] * w0[inside, None] + nrm[vi[1]] * w1[inside, None] + nrm[vi[2]] * w2[inside, None])
        yy = gy.ravel()[inside]
        xx = gx.ravel()[inside]
        pos_map[yy, xx] = P
        nrm_map[yy, xx] = N
        mask[yy, xx] = True
    # dilate into the gutter
    for _ in range(pad):
        holes = ~mask
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
            take = holes & src
            if not take.any():
                continue
            pos_map[take] = np.roll(np.roll(pos_map, dy, axis=0), dx, axis=1)[take]
            nrm_map[take] = np.roll(np.roll(nrm_map, dy, axis=0), dx, axis=1)[take]
            mask = mask | take
            holes = ~mask
    ln = np.linalg.norm(nrm_map, axis=2, keepdims=True)
    nrm_map = nrm_map / np.maximum(ln, 1e-9)
    return {"pos": pos_map, "nrm": nrm_map, "mask": mask}


def paint(maps: Dict[str, np.ndarray], fn: PaintFn, background: RGB = (0.5, 0.5, 0.5)) -> np.ndarray:
    """Run a 3D paint function over the baked surface maps; returns (size,size,3) sRGB floats."""
    size = maps["pos"].shape[0]
    img = np.empty((size, size, 3))
    img[:, :] = np.asarray(background, float)
    m = maps["mask"]
    if m.any():
        img[m] = np.clip(fn(maps["pos"][m], maps["nrm"][m]), 0.0, 1.0)
    return img


def save_png(img: np.ndarray, path: str) -> str:
    from PIL import Image
    a = np.clip(np.asarray(img, float), 0.0, 1.0)
    # images are authored in sRGB space already; flip Y for glTF's UV origin
    Image.fromarray((a[::-1] * 255.0 + 0.5).astype(np.uint8)).save(path)
    return path


def save_png_gray(img: np.ndarray, path: str) -> str:
    from PIL import Image
    a = np.clip(np.asarray(img, float), 0.0, 1.0)
    Image.fromarray((a[::-1] * 255.0 + 0.5).astype(np.uint8)).save(path)
    return path


def orm_image(occlusion: np.ndarray, roughness: np.ndarray, metallic: np.ndarray) -> np.ndarray:
    """Pack occlusion/roughness/metallic into one RGB image (CONTRACTS §4)."""
    return np.stack([np.clip(occlusion, 0, 1), np.clip(roughness, 0, 1), np.clip(metallic, 0, 1)], axis=-1)


# --------------------------------------------------------------------------------------
# skin, faces, eyes
# --------------------------------------------------------------------------------------

# Skin tones are a base colour plus the colour the skin goes where blood is close to the
# surface (cheeks, nose, ears, knuckles); painted storybook skin lives on that contrast.
SKIN_TONES: Dict[str, Dict[str, str]] = {
    "porcelain": {"base": "#f0d2bd", "shadow": "#cf9f88", "blush": "#e08472", "lip": "#c4715f"},
    "fair": {"base": "#e9c3a4", "shadow": "#c08f72", "blush": "#d67a63", "lip": "#b8624f"},
    "wheat": {"base": "#dcae87", "shadow": "#ad7d5c", "blush": "#c46d55", "lip": "#a75a46"},
    "olive": {"base": "#c69769", "shadow": "#8f6a45", "blush": "#ab5f45", "lip": "#8f4c39"},
    "amber": {"base": "#b07b4c", "shadow": "#7c5433", "blush": "#94502f", "lip": "#7c4129"},
    "umber": {"base": "#8a5a36", "shadow": "#5d3a21", "blush": "#743d22", "lip": "#5f3220"},
    "deep": {"base": "#5f3b24", "shadow": "#3d2415", "blush": "#502c17", "lip": "#432416"},
    "ebony": {"base": "#42281a", "shadow": "#291810", "blush": "#3a2113", "lip": "#2f1b11"},
}
HAIR_COLOURS: Dict[str, str] = {
    "black": "#1d1917", "soot": "#2a2521", "dark_brown": "#3b2a1e", "brown": "#5a3b25",
    "chestnut": "#6d3f22", "auburn": "#8a3f22", "ginger": "#a8501f", "sand": "#a98a58",
    "flax": "#c7ab74", "ash_blond": "#cdbf9a", "grey": "#9a958e", "white": "#d9d5cd",
}
EYE_COLOURS: Dict[str, str] = {
    "brown": "#5a3a1e", "dark_brown": "#3a2412", "hazel": "#8a6a2a", "amber": "#a5762a",
    "green": "#4a7a4a", "grey_green": "#6e8472", "blue": "#3f6d94", "pale_blue": "#7fa3bd",
    "grey": "#78807f", "red": "#8e2b22",
}


def skin_tone(name_or_hex: str) -> Dict[str, np.ndarray]:
    if name_or_hex in SKIN_TONES:
        d = SKIN_TONES[name_or_hex]
    else:
        base = hex_rgb(name_or_hex)
        d = {"base": name_or_hex,
             "shadow": "#%02x%02x%02x" % tuple(int(c * 255) for c in np.clip(base * 0.68, 0, 1)),
             "blush": "#%02x%02x%02x" % tuple(int(c * 255) for c in np.clip(base * np.array([1.02, 0.72, 0.66]), 0, 1)),
             "lip": "#%02x%02x%02x" % tuple(int(c * 255) for c in np.clip(base * np.array([0.86, 0.58, 0.54]), 0, 1))}
    return {k: hex_rgb(v) for k, v in d.items()}


def morality_tint(rgb: np.ndarray, hearth: float = 0.0, hollow: float = 0.0) -> np.ndarray:
    """DESIGN.md §5.11: Hearth tiers warm the skin, Hollow tiers drain it to a pallor."""
    out = rgb
    if hearth > 0.01:
        warm = np.array([1.06, 0.99, 0.90])
        out = mix(out, np.clip(out * warm + np.array([0.05, 0.025, 0.0]) * hearth, 0, 1), min(hearth, 1.0))
    if hollow > 0.01:
        grey = np.mean(out, axis=-1, keepdims=True)
        pale = np.clip(mix(out, np.repeat(grey, 3, axis=-1) * 1.08 + 0.05, 0.75), 0, 1)
        out = mix(out, pale, min(hollow, 1.0))
    return out


def skin_paint(landmarks: dict, tone: str = "wheat", seed: int = 0, *, face: bool = True,
               brow_colour: str = "dark_brown", age: float = 0.3, hearth: float = 0.0,
               hollow: float = 0.0, veins: float = 0.0, freckles: float = 0.0,
               lip_strength: float = 1.0, stubble: float = 0.0, beard_colour: Optional[str] = None) -> PaintFn:
    """Paint function for skin.

    Painted rather than modelled, per DESIGN.md §7: the eyelids, lashes, brows and lips are
    texture, so the mesh stays light and the face keeps its shape under animation.
    `landmarks` is `body.head_landmarks(...)`; for the body pass the same dict (the face
    features simply fall outside the body's vertex positions).
    """
    t = skin_tone(tone)
    n = Noise(seed, 48)
    L = landmarks
    s = L["s"]
    hair_rgb = hex_rgb(HAIR_COLOURS.get(brow_colour, HAIR_COLOURS["dark_brown"]))
    beard_rgb = hex_rgb(HAIR_COLOURS.get(beard_colour or brow_colour, HAIR_COLOURS["dark_brown"]))
    eye_x, eye_z, eye_r = L["eye_x"], L["eye_z"], L["eye_r"]
    face_y, mouth_z, mouth_w = L["face_y"], L["mouth_z"], L["mouth_w"]
    chin_z, brow_z = L["chin_z"], L["brow_z"]

    def fn(p: np.ndarray, nrm: np.ndarray) -> np.ndarray:
        base = np.broadcast_to(t["base"], (len(p), 3)).copy()
        # large-scale painterly variation and a little fine grain
        big = n.fbm(p, freq=6.0, octaves=3)
        fine = n.fbm(p, freq=48.0, octaves=2)
        c = mix(base, t["shadow"], 0.18 * big + 0.05 * fine)
        c = c * (0.97 + 0.06 * big)[:, None]
        # downward-facing surfaces sit in their own shadow: cheap, and it reads as painted form
        down = np.clip(-nrm[:, 2], 0, 1)
        c = mix(c, t["shadow"], 0.22 * down)
        up = np.clip(nrm[:, 2], 0, 1)
        c = mix(c, np.clip(c * 1.10 + 0.03, 0, 1), 0.25 * up)
        if freckles > 0.01:
            f = n.at(p, 260.0)
            spots = smoothstep(0.62, 0.72, f) * freckles
            cheeks = gauss(p, [eye_x, face_y + 0.02 * s, eye_z - 0.035 * s], [0.05 * s, 0.05 * s, 0.035 * s]) + \
                gauss(p, [-eye_x, face_y + 0.02 * s, eye_z - 0.035 * s], [0.05 * s, 0.05 * s, 0.035 * s]) + \
                gauss(p, [0.0, face_y, eye_z - 0.02 * s], [0.03 * s, 0.05 * s, 0.03 * s]) * 0.8
            c = mix(c, t["shadow"] * 0.85, np.clip(spots * np.clip(cheeks, 0, 1), 0, 1) * 0.55)
        if face:
            # cheek and nose warmth
            blush = (gauss(p, [eye_x * 1.55, face_y + 0.024 * s, eye_z - 0.050 * s], [0.032 * s, 0.035 * s, 0.028 * s]) +
                     gauss(p, [-eye_x * 1.55, face_y + 0.024 * s, eye_z - 0.050 * s], [0.032 * s, 0.035 * s, 0.028 * s]) +
                     0.7 * gauss(p, [0.0, face_y - 0.004 * s, L["nose_tip"][2]], [0.022 * s, 0.03 * s, 0.020 * s]) +
                     0.5 * gauss(p, [L["ear_c"][0], L["ear_c"][1], L["ear_c"][2]], [0.02 * s, 0.03 * s, 0.03 * s]) +
                     0.5 * gauss(p, [-L["ear_c"][0], L["ear_c"][1], L["ear_c"][2]], [0.02 * s, 0.03 * s, 0.03 * s]))
            c = mix(c, t["blush"], np.clip(blush, 0, 1) * 0.42)
            # eye socket shading
            for sx in (1, -1):
                sock = gauss(p, [sx * eye_x, face_y + 0.012 * s, eye_z + 0.002 * s],
                             [eye_r * 2.1, 0.022 * s, eye_r * 1.5])
                c = mix(c, t["shadow"], np.clip(sock, 0, 1) * 0.20)
            # lids and lashes: a dark rim around the eye opening, heavier above
            for sx in (1, -1):
                d = (p - np.array([sx * eye_x, L["eye_c_y"], eye_z])) / np.array([eye_r * 1.30, eye_r * 1.9, eye_r * 0.80])
                rad = np.linalg.norm(d[:, [0, 2]], axis=1)
                near = np.exp(-0.5 * (d[:, 1] ** 2))
                rim = smoothstep(0.62, 0.95, rad) * (1.0 - smoothstep(1.02, 1.30, rad)) * near
                upper = np.clip((p[:, 2] - eye_z) / (eye_r * 0.7), -1, 1)
                weight = np.clip(0.45 + 0.55 * upper, 0, 1)
                c = mix(c, np.clip(hair_rgb * 0.75, 0, 1), np.clip(rim * weight, 0, 1) * 0.62)
            # brows
            for sx in (1, -1):
                bx = (p[:, 0] - sx * eye_x * 1.02) / (eye_r * 2.0)
                arch = brow_z + 0.004 * s - 0.010 * s * np.clip(bx * sx, -1.2, 1.2) ** 2
                bz = (p[:, 2] - arch) / (0.0072 * s)
                by = (p[:, 1] - (face_y + 0.016 * s)) / (0.030 * s)
                m = np.exp(-0.5 * (bz ** 2 + by ** 2)) * (1.0 - smoothstep(0.80, 1.25, np.abs(bx)))
                thick = 1.0 - 0.35 * smoothstep(0.3, 1.1, np.abs(bx))
                c = mix(c, hair_rgb, np.clip(m * thick, 0, 1) * 0.80)
            # lips
            lipd = np.abs(p[:, 2] - mouth_z) / (0.011 * s)
            lipx = np.abs(p[:, 0]) / (mouth_w * 0.92)
            lipy = (p[:, 1] - (face_y + 0.022 * s)) / (0.020 * s)
            lipm = np.exp(-0.5 * (lipd ** 2 + lipy ** 2)) * (1.0 - smoothstep(0.85, 1.15, lipx))
            c = mix(c, t["lip"], np.clip(lipm, 0, 1) * 0.85 * lip_strength)
            line = np.exp(-0.5 * (((p[:, 2] - mouth_z) / (0.0030 * s)) ** 2 + lipy ** 2)) * (1.0 - smoothstep(0.8, 1.05, lipx))
            c = mix(c, np.clip(t["lip"] * 0.45, 0, 1), np.clip(line, 0, 1) * 0.8)
            if stubble > 0.01:
                jaw = (1.0 - smoothstep(mouth_z + 0.018 * s, mouth_z + 0.050 * s, p[:, 2])) * \
                    smoothstep(chin_z - 0.05 * s, chin_z - 0.01 * s, p[:, 2]) * \
                    (1.0 - smoothstep(0.02 * s, 0.06 * s, p[:, 1]))
                nolip = 1.0 - np.clip(lipm * 1.4, 0, 1)
                grain = 0.5 + 0.5 * n.at(p, 320.0)
                c = mix(c, beard_rgb, np.clip(jaw * nolip * grain, 0, 1) * 0.42 * stubble)
            if age > 0.5:
                a = (age - 0.5) / 0.5
                crease = np.exp(-0.5 * (((p[:, 2] - (brow_z + 0.020 * s)) / (0.006 * s)) ** 2)) * \
                    (1.0 - smoothstep(0.045 * s, 0.075 * s, np.abs(p[:, 0]))) * \
                    (1.0 - smoothstep(0.02 * s, 0.05 * s, p[:, 1]))
                c = mix(c, t["shadow"], np.clip(crease, 0, 1) * 0.30 * a)
        if veins > 0.01:
            # DESIGN.md §5.11: Hollow tiers show dark veins under the skin
            v = n.fbm(p, freq=22.0, octaves=3)
            ridges = 1.0 - np.abs(v * 2.0 - 1.0)
            vein = smoothstep(0.86, 0.995, ridges)
            near_skin = np.clip(0.4 + 0.6 * np.abs(nrm[:, 2]), 0, 1)
            c = mix(c, np.array([0.16, 0.13, 0.20]), np.clip(vein * near_skin, 0, 1) * 0.65 * veins)
        c = morality_tint(c, hearth, hollow)
        return c
    return fn


def skin_orm(landmarks: dict, seed: int = 0, age: float = 0.3, oily: float = 0.35) -> Tuple[PaintFn, PaintFn]:
    """(occlusion, roughness) paint functions for skin; metallic is always zero."""
    n = Noise(seed + 77, 32)

    def occ(p, nrm):
        down = np.clip(-nrm[:, 2], 0, 1)
        v = 1.0 - 0.30 * down - 0.10 * n.fbm(p, freq=9.0, octaves=2)
        return np.repeat(np.clip(v, 0, 1)[:, None], 3, axis=1)

    def rough(p, nrm):
        base = 0.62 - 0.12 * oily + 0.10 * age
        v = base + 0.10 * (n.fbm(p, freq=26.0, octaves=3) - 0.5)
        return np.repeat(np.clip(v, 0.1, 0.98)[:, None], 3, axis=1)
    return occ, rough


def iris_texture(size: int = 256, colour: str = "brown", seed: int = 0, glint: float = 0.0,
                 red_eye: float = 0.0) -> np.ndarray:
    """The eyeball texture.  The eye mesh is UV-sphered with v=0 at the pupil, so the iris,
    limbal ring and sclera are simply bands in v, with fibres painted in u."""
    base = hex_rgb(EYE_COLOURS.get(colour, EYE_COLOURS["brown"]))
    if red_eye > 0.01:
        base = mix(base, hex_rgb(EYE_COLOURS["red"]), min(red_eye, 1.0))
    rng = np.random.default_rng(seed)
    u = (np.arange(size) + 0.5) / size
    v = (np.arange(size) + 0.5) / size
    U, V = np.meshgrid(u, v)
    img = np.zeros((size, size, 3))
    sclera = np.array([0.93, 0.92, 0.89])
    # v is the polar angle / pi: 0 at the pupil centre
    pupil_r, iris_r, limb_r = 0.055, 0.135, 0.150
    fibre = 0.5 + 0.5 * np.sin(U * 2 * math.pi * 38 + rng.random() * 6.28)
    fibre = fibre * (0.5 + 0.5 * np.sin(U * 2 * math.pi * 17 + 1.7))
    radial = np.clip((V - pupil_r) / max(iris_r - pupil_r, 1e-6), 0, 1)
    iris = mix(np.clip(base * 0.62, 0, 1).reshape(1, 1, 3).repeat(size, 0).repeat(size, 1).reshape(-1, 3),
               np.clip(base * 1.25 + 0.04, 0, 1).reshape(1, 1, 3).repeat(size, 0).repeat(size, 1).reshape(-1, 3),
               (0.35 + 0.65 * radial).ravel()).reshape(size, size, 3)
    iris = iris * (0.82 + 0.30 * fibre[..., None] * radial[..., None])
    out = np.where((V < iris_r)[..., None], iris, sclera.reshape(1, 1, 3))
    # limbal ring, pupil, corner shading of the sclera
    ring = smoothstep(iris_r - 0.022, iris_r, V) * (1.0 - smoothstep(limb_r, limb_r + 0.012, V))
    out = out * (1.0 - 0.75 * ring[..., None])
    pup = 1.0 - smoothstep(pupil_r - 0.012, pupil_r, V)
    out = out * (1.0 - 0.94 * pup[..., None])
    shade = smoothstep(0.30, 0.62, V)
    out = out * (1.0 - 0.30 * shade[..., None])
    if glint > 0.01:
        g = np.exp(-0.5 * ((((U - 0.30) % 1.0 - 0.0) / 0.03) ** 2 + ((V - 0.055) / 0.03) ** 2))
        out = np.clip(out + g[..., None] * np.array([1.0, 0.92, 0.72]) * glint, 0, 1)
    return np.clip(out, 0, 1)


def hair_paint(colour: str = "brown", seed: int = 0, grey: float = 0.0) -> PaintFn:
    """Strand-flavoured colour for hair and beard shells."""
    base = hex_rgb(HAIR_COLOURS.get(colour, HAIR_COLOURS["brown"]))
    n = Noise(seed + 13, 32)

    def fn(p, nrm):
        strand = n.fbm(p * np.array([3.0, 1.0, 1.0]), freq=120.0, octaves=2)
        big = n.fbm(p, freq=14.0, octaves=3)
        c = np.broadcast_to(base, (len(p), 3)).copy()
        c = mix(c, np.clip(base * 0.45, 0, 1), 0.45 * strand)
        c = mix(c, np.clip(base * 1.5 + 0.06, 0, 1), 0.30 * smoothstep(0.55, 0.95, big) * np.clip(nrm[:, 2], 0, 1))
        if grey > 0.01:
            g = smoothstep(0.35, 0.85, n.fbm(p, freq=9.0, octaves=2))
            c = mix(c, np.array([0.80, 0.78, 0.75]), np.clip(g * grey, 0, 1))
        return np.clip(c, 0, 1)
    return fn
