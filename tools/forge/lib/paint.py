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


def stroke_xz(p: np.ndarray, pts: Sequence[Tuple[float, float]], width: float,
              soft: float = 0.45, y_centre: float = 0.0, y_depth: float = 0.03,
              taper: bool = True) -> np.ndarray:
    """A brush stroke through control points in the (x, z) plane of the face.

    Face features are *lines* — a brow, a lash, the seam of the lips — and a line painted as
    a chain of gaussian blobs (what this used to do) spreads into a smudge that reads as a
    bruise at any distance.  This measures the real distance to the polyline instead, so a
    stroke has a width and an end, and `taper` thins it towards the ends like a brush lifting.
    """
    P = np.asarray(pts, float)
    x, z = p[:, 0], p[:, 2]
    best = np.full(len(p), 1e9)
    frac = np.zeros(len(p))
    total = float(np.sum(np.linalg.norm(np.diff(P, axis=0), axis=1))) or 1.0
    walked = 0.0
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        ab = b - a
        l2 = max(float(ab @ ab), 1e-12)
        t = np.clip(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / l2, 0.0, 1.0)
        d = np.hypot(x - (a[0] + t * ab[0]), z - (a[1] + t * ab[1]))
        seg = float(math.sqrt(l2))
        closer = d < best
        frac = np.where(closer, (walked + t * seg) / total, frac)
        best = np.minimum(best, d)
        walked += seg
    w = width
    if taper:
        w = width * (0.35 + 0.65 * np.sin(np.clip(frac, 0, 1) * math.pi) ** 0.55)
    m = 1.0 - smoothstep(1.0 - soft, 1.0, best / np.maximum(w, 1e-9))
    # only on the front of the face; the same (x, z) exists again on the back of the skull
    near = 1.0 - smoothstep(y_depth * 0.6, y_depth, np.abs(p[:, 1] - y_centre))
    return m * near


def ellipse_mask(p: np.ndarray, c, r, soft: float = 0.25) -> np.ndarray:
    """1 inside an axis-aligned ellipsoid, fading over `soft` of the radius."""
    d = np.linalg.norm((p - np.asarray(c, float)) / np.asarray(r, float), axis=1)
    return 1.0 - smoothstep(1.0 - soft, 1.0, d)


def sdf_occlusion(scene, p: np.ndarray, nrm: np.ndarray, radius: float = 0.05,
                  samples: int = 5, strength: float = 1.0) -> np.ndarray:
    """Ambient occlusion straight from the shape's own distance field.

    Step out along the surface normal; wherever the field says we are still close to
    material, the point is in a crease.  This is what turns a flat-coloured garment into a
    painted one — an armpit, the inside of an elbow, the fold under a hem and the gap
    between two fingers all darken because the geometry says they should, and it costs a
    handful of field lookups instead of a ray tracer.

    Returns 0 (fully occluded) .. 1 (open).
    """
    occ = np.zeros(len(p))
    total = 0.0
    for i in range(1, samples + 1):
        h = radius * i / samples
        w = 1.0 / (2.0 ** i)
        d = scene.eval(p + nrm * h)
        occ += w * np.clip((h - d) / max(h, 1e-6), 0.0, 1.0)
        total += w
    return np.clip(1.0 - strength * (occ / max(total, 1e-9)), 0.0, 1.0)


def exposure(occ: np.ndarray, power: float = 2.0) -> np.ndarray:
    """Where a surface sticks out — the places that scuff, fade and catch light."""
    return np.clip(occ, 0, 1) ** power


# --------------------------------------------------------------------------------------
# UV rasteriser
# --------------------------------------------------------------------------------------

def surface_maps(ob, size: int = 1024, pad: int = 4, tangents: bool = False) -> Dict[str, np.ndarray]:
    """For every texel of the UV layout, the 3D position and normal behind it.

    Returns {"pos": (size,size,3), "nrm": (size,size,3), "mask": (size,size) bool}.
    `pad` dilates the covered area so bilinear filtering never samples empty texels.
    `tangents` adds "tan" and "bit": the directions in which u and v (Blender's, v up) grow,
    for baking a tangent-space normal map. Each is averaged over the corners that share a
    vertex and a UV (a UV seam splits them, as MikkTSpace does) and interpolated like the normal."""
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
    corner_T = corner_B = None
    tan_map = bit_map = None
    if tangents:
        P0, P1, P2 = co[tri_verts[:, 0]], co[tri_verts[:, 1]], co[tri_verts[:, 2]]
        U0, U1, U2 = uvs[tri_loops[:, 0]], uvs[tri_loops[:, 1]], uvs[tri_loops[:, 2]]
        e1, e2 = P1 - P0, P2 - P0
        d1, d2 = U1 - U0, U2 - U0
        det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
        r = np.where(np.abs(det) > 1e-14, 1.0 / np.where(np.abs(det) > 1e-14, det, 1.0), 0.0)
        Tf = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) * r[:, None]
        Bf = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) * r[:, None]
        Tf /= np.maximum(np.linalg.norm(Tf, axis=1, keepdims=True), 1e-12)
        Bf /= np.maximum(np.linalg.norm(Bf, axis=1, keepdims=True), 1e-12)
        keys = np.stack([tri_verts.ravel(), np.round(uvs[tri_loops.ravel()] * 8192.0).astype(np.int64)[:, 0],
                         np.round(uvs[tri_loops.ravel()] * 8192.0).astype(np.int64)[:, 1]], axis=1)
        _, inv = np.unique(keys, axis=0, return_inverse=True)
        inv = inv.ravel()
        accT = np.zeros((int(inv.max()) + 1, 3))
        accB = np.zeros_like(accT)
        np.add.at(accT, inv, np.repeat(Tf, 3, axis=0))
        np.add.at(accB, inv, np.repeat(Bf, 3, axis=0))
        corner_T = accT[inv].reshape(-1, 3, 3)
        corner_B = accB[inv].reshape(-1, 3, 3)
        tan_map = np.zeros((size, size, 3))
        bit_map = np.zeros((size, size, 3))
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
        if tangents:
            cT, cB = corner_T[t], corner_B[t]
            tan_map[yy, xx] = cT[0] * w0[inside, None] + cT[1] * w1[inside, None] + cT[2] * w2[inside, None]
            bit_map[yy, xx] = cB[0] * w0[inside, None] + cB[1] * w1[inside, None] + cB[2] * w2[inside, None]
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
            if tangents:
                tan_map[take] = np.roll(np.roll(tan_map, dy, axis=0), dx, axis=1)[take]
                bit_map[take] = np.roll(np.roll(bit_map, dy, axis=0), dx, axis=1)[take]
            mask = mask | take
            holes = ~mask
    ln = np.linalg.norm(nrm_map, axis=2, keepdims=True)
    nrm_map = nrm_map / np.maximum(ln, 1e-9)
    out = {"pos": pos_map, "nrm": nrm_map, "mask": mask}
    if tangents:
        out["tan"], out["bit"] = tan_map, bit_map
    return out


def sdf_detail_normal(field, maps: Dict[str, np.ndarray], eps: float = 0.0004, max_move: float = 0.004,
                      iters: int = 3, chunk: int = 60000, box=None, feather: float = 0.012) -> np.ndarray:
    """A tangent-space normal map (OpenGL, +Y up the UV's v) of the field's own surface, baked
    onto the mesh that was meshed and decimated from it.

    A head is meshed at a few millimetres and decimated to a few thousand triangles, and what a
    face is read by close to -- the edge of a lid, the rim of a nostril, the line of the lips,
    the fold under the eye -- is smaller than that and went with the triangles. Each texel's
    point on the mesh is walked onto the field's zero set and the field's normal there is
    written in the mesh's own tangent frame, so the lighting finds the detail the geometry
    lost. Where the mesh is further than `max_move` from the field (or the walk fails) the mesh's
    own normal is kept, as it is outside `box` (lo, hi), where the field was not sampled; the
    last `feather` metres inside the box ease from one to the other, or the box's edge showed
    as a line across the cheeks and the brow (the field's smooth normal and the decimated mesh's
    faceted one are not the same even where there is no detail).
    `maps` must come from surface_maps(..., tangents=True)."""
    size = maps["pos"].shape[0]
    out = np.zeros((size, size, 3))
    out[..., :] = (0.5, 0.5, 1.0)
    m = maps["mask"]
    idx = np.nonzero(m)
    P_all, N_all = maps["pos"][m], maps["nrm"][m]
    T_all, B_all = maps["tan"][m], maps["bit"][m]
    res = np.zeros((len(P_all), 3))

    def grad(Q):
        g = np.empty_like(Q)
        for a in range(3):
            o = np.zeros(3)
            o[a] = eps
            g[:, a] = field.eval(Q + o) - field.eval(Q - o)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    for c0 in range(0, len(P_all), chunk):
        P = P_all[c0:c0 + chunk]
        N = N_all[c0:c0 + chunk]
        T = T_all[c0:c0 + chunk]
        B = B_all[c0:c0 + chunk]
        Q = P.copy()
        for _ in range(iters):
            d = field.eval(Q)
            Q = Q - grad(Q) * d[:, None]
        G = grad(Q)
        moved = np.linalg.norm(Q - P, axis=1)
        bad = (moved > max_move) | ~np.all(np.isfinite(G), axis=1) | (np.sum(G * N, axis=1) < 0.25)
        if box is not None:
            lo, hi = np.asarray(box[0], float), np.asarray(box[1], float)
            bad |= np.any((P < lo) | (P > hi), axis=1)
        G[bad] = N[bad]
        T = T - N * np.sum(T * N, axis=1, keepdims=True)
        T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
        NxT = np.cross(N, T)
        sgn = np.sign(np.sum(NxT * B, axis=1))
        sgn[sgn == 0] = 1.0
        Bo = NxT * sgn[:, None]
        n = np.stack([np.sum(G * T, axis=1), np.sum(G * Bo, axis=1), np.sum(G * N, axis=1)], axis=1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        if box is not None and feather > 0.0:
            lo, hi = np.asarray(box[0], float), np.asarray(box[1], float)
            inset = np.min(np.minimum(P - lo, hi - P), axis=1)
            w = np.clip(inset / feather, 0.0, 1.0)[:, None]
            n = n * w + np.array([0.0, 0.0, 1.0]) * (1.0 - w)
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        res[c0:c0 + chunk] = n
    out[idx] = res * 0.5 + 0.5
    return out


def blend_normals(base: np.ndarray, detail: np.ndarray) -> np.ndarray:
    """Two encoded tangent-space normal maps laid one over the other ("whiteout" blend)."""
    a = base * 2.0 - 1.0
    b = detail * 2.0 - 1.0
    n = np.stack([a[..., 0] + b[..., 0], a[..., 1] + b[..., 1], a[..., 2] * b[..., 2]], axis=-1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    return n * 0.5 + 0.5


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


def save_png_rgba(img: np.ndarray, path: str) -> str:
    """An (h, w, 4) image, flipped for glTF's UV origin like save_png."""
    from PIL import Image
    a = np.clip(np.asarray(img, float), 0.0, 1.0)
    Image.fromarray((a[::-1] * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(path)
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
               lip_strength: float = 1.0, stubble: float = 0.0, beard_colour: Optional[str] = None,
               scene=None, occ_radius: float = 0.05, warm_points: Optional[Sequence] = None) -> PaintFn:
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
    # No face is symmetric: one brow sits higher, one fold is deeper, one cheek takes more colour.
    # Mirrored marks were a large part of why the heads read as mannequins.
    arng = np.random.default_rng(seed + 313)
    brow_lift = {sx: float(arng.uniform(-0.0028, 0.0028)) * s for sx in (1, -1)}
    fold_k = {sx: float(arng.uniform(0.80, 1.25)) for sx in (1, -1)}
    blush_k = {sx: float(arng.uniform(0.80, 1.20)) for sx in (1, -1)}
    lid_k = {sx: float(arng.uniform(0.85, 1.15)) for sx in (1, -1)}

    def fn(p: np.ndarray, nrm: np.ndarray) -> np.ndarray:
        base = np.broadcast_to(t["base"], (len(p), 3)).copy()
        # large-scale painterly variation and a little fine grain
        big = n.fbm(p, freq=6.0, octaves=3)
        fine = n.fbm(p, freq=48.0, octaves=2)
        c = mix(base, t["shadow"], 0.16 * big + 0.015 * fine)
        c = c * (0.97 + 0.06 * big)[:, None]
        # A painter's mottle: broad patches a few centimetres across that lean warm or cool, as
        # a skin laid in with a loaded brush does, rather than a grain (the fine term above was
        # most of what read as plastic close to).
        if face:
            mot = n.fbm(p + 3.7, freq=14.0, octaves=2) - 0.5
            c = c * (1.0 + mot[:, None] * np.array([0.10, 0.02, -0.07]))
        # real occlusion: armpits, the inside of the elbow, behind the knee, between the
        # fingers, under the jaw.  Without this the skin is one flat value.
        if scene is not None:
            ao = sdf_occlusion(scene, p, nrm, radius=occ_radius, samples=5, strength=0.95)
            # A face gets a third of the body's dose.  Every hollow on a head is an eye
            # socket or a temple, and painting those at full strength is how a warm
            # complexion turns into a skull at the distance the player is standing.
            deep, lift = (0.20, 0.26) if face else (0.55, 0.18)
            c = mix(c, np.clip(t["shadow"] * 0.82, 0, 1), (1.0 - ao) * deep)
            # and the opposite: the exposed high points bleach a little towards the light
            c = mix(c, np.clip(t["base"] * 1.12 + 0.04, 0, 1), exposure(ao, 3.0) * lift)
        # downward-facing surfaces sit in their own shadow: cheap, and it reads as painted form
        down = np.clip(-nrm[:, 2], 0, 1)
        c = mix(c, t["shadow"], 0.16 * down)
        up = np.clip(nrm[:, 2], 0, 1)
        c = mix(c, np.clip(c * 1.10 + 0.03, 0, 1), 0.22 * up)
        # warmth where the blood runs close to the surface: hands, feet, knees, elbows
        if warm_points:
            warm = np.zeros(len(p))
            for wc, wr in warm_points:
                warm = np.maximum(warm, gauss(p, wc, wr))
            c = mix(c, t["blush"], np.clip(warm, 0, 1) * 0.30)
        if freckles > 0.01:
            f = n.at(p, 260.0)
            spots = smoothstep(0.62, 0.72, f) * freckles
            cheeks = gauss(p, [eye_x, face_y + 0.02 * s, eye_z - 0.035 * s], [0.05 * s, 0.05 * s, 0.035 * s]) + \
                gauss(p, [-eye_x, face_y + 0.02 * s, eye_z - 0.035 * s], [0.05 * s, 0.05 * s, 0.035 * s]) + \
                gauss(p, [0.0, face_y, eye_z - 0.02 * s], [0.03 * s, 0.05 * s, 0.03 * s]) * 0.8
            c = mix(c, t["shadow"] * 0.85, np.clip(spots * np.clip(cheeks, 0, 1), 0, 1) * 0.55)
        if face:
            fy = face_y
            # -- warmth first: the base for a storybook face is a warm, lit complexion, and
            # every dark mark below is a soft-edged stroke, not a smudge.
            lit = (gauss(p, [0.0, fy - 0.004 * s, L["brow_z"] + 0.030 * s], [0.055 * s, 0.045 * s, 0.030 * s]) * 0.8 +
                   gauss(p, [0.0, fy - 0.010 * s, L["nose_tip"][2] + 0.020 * s], [0.018 * s, 0.030 * s, 0.030 * s]) * 0.7 +
                   gauss(p, [eye_x * 1.45, fy + 0.012 * s, eye_z - 0.038 * s], [0.030 * s, 0.032 * s, 0.026 * s]) * 0.9 +
                   gauss(p, [-eye_x * 1.45, fy + 0.012 * s, eye_z - 0.038 * s], [0.030 * s, 0.032 * s, 0.026 * s]) * 0.9 +
                   gauss(p, [0.0, fy + 0.004 * s, chin_z + 0.030 * s], [0.026 * s, 0.030 * s, 0.022 * s]) * 0.6)
            highlight = np.clip(t["base"] * 1.10 + 0.045, 0, 1)
            c = mix(c, highlight, np.clip(lit, 0, 1) * 0.40)
            # cheek, nose and ear warmth — where the blood is near the surface
            # (weathered faces carry more colour here than the old third of the way: a flat,
            # even complexion was the other half of the mannequin)
            blush = (blush_k[1] * gauss(p, [eye_x * 1.50, fy + 0.020 * s, eye_z - 0.046 * s], [0.030 * s, 0.030 * s, 0.026 * s]) +
                     blush_k[-1] * gauss(p, [-eye_x * 1.50, fy + 0.020 * s, eye_z - 0.046 * s], [0.030 * s, 0.030 * s, 0.026 * s]) +
                     0.85 * gauss(p, [0.0, fy - 0.004 * s, L["nose_tip"][2]], [0.016 * s, 0.022 * s, 0.017 * s]) +
                     0.45 * gauss(p, [L["ear_c"][0], L["ear_c"][1], L["ear_c"][2]], [0.016 * s, 0.024 * s, 0.026 * s]) +
                     0.45 * gauss(p, [-L["ear_c"][0], L["ear_c"][1], L["ear_c"][2]], [0.016 * s, 0.024 * s, 0.026 * s]))
            # (the person's own ruddiness is laid over this at runtime: face_marks, channel G)
            c = mix(c, t["blush"], np.clip(blush, 0, 1) * (0.30 + 0.06 * age))
            # The three bands a painter lays a face in: the forehead a little golden, the middle
            # (cheeks, nose, ears) the warmest, the jaw, the chin and round the mouth cooler, where
            # a beard's shadow is even on a shaved face; the sockets cool and a shade darker.
            nz = float(L["nose_tip"][2])
            upper = smoothstep(L["brow_z"] - 0.006 * s, L["brow_z"] + 0.020 * s, p[:, 2])
            lower = 1.0 - smoothstep(L["mouth_z"] - 0.012 * s, nz - 0.004 * s, p[:, 2])
            middle = np.clip(1.0 - upper - lower, 0.0, 1.0)
            front = smoothstep(0.0, 0.5, -nrm[:, 1] + 0.3)
            tint = (1.0 + (upper * front)[:, None] * np.array([0.035, 0.012, -0.050])
                    + (middle * front)[:, None] * np.array([0.050, -0.020, -0.035])
                    + (lower * front)[:, None] * np.array([-0.050, -0.012, 0.030]))
            c = c * tint
            for sx in (1, -1):
                sock_c = gauss(p, [sx * eye_x, fy + 0.004 * s, eye_z + eye_r * 0.20],
                               [eye_r * 1.55, 0.020 * s, eye_r * 1.30])
                c = c * (1.0 + np.clip(sock_c, 0, 1)[:, None] * np.array([-0.075, -0.045, 0.000]))
            # a shade darker under the brow ridge, along its whole length, and under the nose
            under_brow = stroke_xz(p, [(-eye_x - eye_r * 1.2, eye_z + eye_r * 1.05), (0.0, eye_z + eye_r * 0.95),
                                       (eye_x + eye_r * 1.2, eye_z + eye_r * 1.05)],
                                   width=eye_r * 0.55, soft=0.95, y_centre=fy + 0.004 * s, y_depth=0.034 * s)
            c = mix(c, t["shadow"], np.clip(under_brow, 0, 1) * 0.16)
            # -- eyes -------------------------------------------------------------------
            # The marks below were kept faint so that none of them "won at 30 pixels", and at
            # portrait distance the face then had nothing to read by: a brow, an eye, a nose and
            # a mouth have to show as shapes in the Naming's whole figure, and as features in
            # its face view.  They are darker and wider now, and still soft-edged strokes.
            # The lash line was a near-black arc at 95 %: at any distance it read as eyeliner. It is
            # the skin's own deep shadow with a little of the hair in it now, and the upper lid
            # carries the eye: a soft shadow from the lashes to the crease.
            lash_col = np.clip(mix(t["shadow"] * 0.52, hair_rgb * 0.60, 0.35), 0, 1)
            for sx in (1, -1):
                ex = sx * eye_x
                inner, outer = ex - sx * eye_r * 1.15, ex + sx * eye_r * 1.30
                # a soft, warm recess under the brow only: not a ring round the whole eye
                sock = gauss(p, [ex, fy - 0.004 * s, eye_z + eye_r * 0.85],
                             [eye_r * 1.25, 0.016 * s, eye_r * 0.85])
                c = mix(c, t["shadow"], np.clip(sock, 0, 1) * 0.26)
                # the inner corner, where the socket meets the side of the nose
                corner = gauss(p, [ex - sx * eye_r * 1.35, fy - 0.004 * s, eye_z + eye_r * 0.15],
                               [eye_r * 0.45, 0.014 * s, eye_r * 0.60])
                c = mix(c, t["shadow"] * 0.92, np.clip(corner, 0, 1) * 0.30)
                # the crease of the upper lid: a soft line above the lashes
                crease = stroke_xz(p, [(inner + sx * eye_r * 0.10, eye_z + eye_r * 0.62),
                                       (ex, eye_z + eye_r * 1.02),
                                       (outer - sx * eye_r * 0.05, eye_z + eye_r * 0.55)],
                                   width=eye_r * 0.22, soft=0.95, y_centre=fy + 0.008 * s, y_depth=0.030 * s)
                c = mix(c, t["shadow"] * 0.88, np.clip(crease, 0, 1) * 0.40 * lid_k[sx])
                # the upper lid itself, between the lashes and the crease: a shade darker than
                # the brow bone above it, so the eye has a lid over it and does not stare
                lidband = stroke_xz(p, [(inner + sx * eye_r * 0.05, eye_z + eye_r * 0.40),
                                        (ex, eye_z + eye_r * 0.80),
                                        (outer, eye_z + eye_r * 0.36)],
                                    width=eye_r * 0.40, soft=0.95, y_centre=fy + 0.006 * s, y_depth=0.030 * s)
                lid_shadow = np.clip(mix(t["shadow"] * 0.86, t["blush"] * 0.80, 0.25), 0, 1)
                c = mix(c, lid_shadow, np.clip(lidband, 0, 1) * 0.48 * lid_k[sx])
                # upper lash: a dark arc hugging the top of the opening, thickest mid-eye; the
                # line that makes an eye an eye at any distance
                lash = stroke_xz(p, [(inner, eye_z + eye_r * 0.14),
                                     (ex - sx * eye_r * 0.30, eye_z + eye_r * 0.54),
                                     (ex + sx * eye_r * 0.45, eye_z + eye_r * 0.47),
                                     (outer + sx * eye_r * 0.12, eye_z + eye_r * 0.08)],
                                 width=eye_r * 0.30, soft=0.80, y_centre=fy + 0.006 * s, y_depth=0.030 * s)
                c = mix(c, lash_col, np.clip(lash, 0, 1) * 0.70)
                # lower lid: a light catch, which is what stops an eye reading as a hole
                lid = stroke_xz(p, [(inner + sx * eye_r * 0.15, eye_z - eye_r * 0.52),
                                    (ex, eye_z - eye_r * 0.66),
                                    (outer - sx * eye_r * 0.20, eye_z - eye_r * 0.44)],
                                width=eye_r * 0.16, soft=0.85, y_centre=fy + 0.006 * s, y_depth=0.030 * s)
                c = mix(c, np.clip(t["base"] * 1.16 + 0.05, 0, 1), np.clip(lid, 0, 1) * 0.50)
                # brow: a stroke that rises from the inner end and falls away outside, fuller
                # at its head than its tail
                bz = L["brow_z"] + brow_lift[sx]
                brow = stroke_xz(p, [(ex - sx * eye_r * 0.95, bz - 0.004 * s),
                                     (ex - sx * eye_r * 0.20, bz + 0.004 * s),
                                     (ex + sx * eye_r * 0.65, bz + 0.005 * s),
                                     (ex + sx * eye_r * 1.55, bz - 0.006 * s)],
                                 width=0.0072 * s, soft=0.75, y_centre=fy + 0.012 * s, y_depth=0.034 * s)
                head = stroke_xz(p, [(ex - sx * eye_r * 0.90, bz - 0.003 * s),
                                     (ex + sx * eye_r * 0.30, bz + 0.004 * s)],
                                 width=0.0084 * s, soft=0.75, y_centre=fy + 0.012 * s, y_depth=0.034 * s)
                brow_col = mix(np.clip(hair_rgb * 0.85, 0, 1), t["shadow"] * 0.55, 0.30)
                # A face is read by its brows before anything else at a distance; at 9.5 mm and
                # 82 % they read as two dark bars in the engine close to (the faces pass's face
                # frame). Fuller at the head than the tail, and lighter.
                # laid in hair by hair, not filled: a strand grain along the brow, so close to it
                # reads as hair and not as a painted bar
                # (fine and faint: coarse and strong, it broke the brow into blotches)
                grain = n.at(p * np.array([0.20, 1.0, 1.0]) + 5.1, 1100.0)
                hairs = 0.80 + 0.20 * smoothstep(0.30, 0.70, grain)
                c = mix(c, brow_col, np.clip(np.maximum(brow, head * 0.9), 0, 1) * hairs * (0.72 - 0.10 * float(age > 0.7)))
            # -- mouth ------------------------------------------------------------------
            mw = mouth_w
            # The lips' depth is the face's own mouth station, 4 mm proud of it.  At the eye
            # line's depth plus 2 cm, which is where this sat, the lips of every head lay 3 cm
            # in front of it: the seam was masked out entirely and the lips came through at a
            # fifth of their colour, and the mouth was the feature that never read.
            mouth_front = float(L["stations"][3][2]) if "stations" in L else fy - 0.006 * s
            lip_y = mouth_front - 0.004 * s
            # the lips themselves: a soft warm shape, upper a little darker than lower
            upper = np.exp(-0.5 * ((((p[:, 2] - (mouth_z + 0.0060 * s)) / (0.0052 * s)) ** 2) +
                                   (((p[:, 1] - lip_y) / (0.018 * s)) ** 2))) * \
                (1.0 - smoothstep(0.80, 1.05, np.abs(p[:, 0]) / (mw * 0.86)))
            lower = np.exp(-0.5 * ((((p[:, 2] - (mouth_z - 0.0070 * s)) / (0.0060 * s)) ** 2) +
                                   (((p[:, 1] - lip_y) / (0.018 * s)) ** 2))) * \
                (1.0 - smoothstep(0.80, 1.05, np.abs(p[:, 0]) / (mw * 0.78)))
            # a lip is darker than the skin round it before it is redder: taken a third of the way
            # to the skin's shadow, the mouth still reads and no longer looks painted on
            lip_c = mix(t["lip"], t["shadow"], 0.34)
            c = mix(c, np.clip(lip_c * 0.92, 0, 1), np.clip(upper, 0, 1) * 0.74 * lip_strength)
            c = mix(c, np.clip(lip_c * 1.06 + 0.02, 0, 1), np.clip(lower, 0, 1) * 0.62 * lip_strength)
            # the seam: a warm dark line that curves with the mouth, never a black slot
            seam = stroke_xz(p, [(-mw * 0.90, mouth_z - 0.0030 * s),
                                 (-mw * 0.40, mouth_z + 0.0012 * s),
                                 (0.0, mouth_z),
                                 (mw * 0.40, mouth_z + 0.0012 * s),
                                 (mw * 0.90, mouth_z - 0.0030 * s)],
                             width=0.0036 * s, soft=0.70, y_centre=lip_y, y_depth=0.024 * s)
            c = mix(c, np.clip(t["lip"] * 0.42, 0, 1), np.clip(seam, 0, 1) * 0.82 * lip_strength)
            # the corners of the mouth, tucked in
            for sx in (1, -1):
                cn = gauss(p, [sx * mw * 0.93, lip_y + 0.004 * s, mouth_z - 0.0025 * s],
                           [0.0030 * s, 0.010 * s, 0.0032 * s])
                c = mix(c, np.clip(t["shadow"] * 0.80, 0, 1), np.clip(cn, 0, 1) * 0.40 * lip_strength)
            # a light catch on the lower lip and a soft shadow under it: this is what makes
            # a closed mouth read as lips rather than a cut
            shine = stroke_xz(p, [(-mw * 0.34, mouth_z - 0.0072 * s), (mw * 0.34, mouth_z - 0.0072 * s)],
                              width=0.0030 * s, soft=0.9, y_centre=lip_y - 0.002 * s, y_depth=0.020 * s)
            c = mix(c, np.clip(t["base"] * 1.18 + 0.06, 0, 1), np.clip(shine, 0, 1) * 0.30)
            under = np.exp(-0.5 * ((((p[:, 2] - (mouth_z - 0.0155 * s)) / (0.0055 * s)) ** 2) +
                                   (((p[:, 1] - (lip_y + 0.004 * s)) / (0.020 * s)) ** 2))) * \
                (1.0 - smoothstep(0.7, 1.0, np.abs(p[:, 0]) / (mw * 0.85)))
            c = mix(c, t["shadow"], np.clip(under, 0, 1) * 0.32)
            # the nose: nostrils, the shadow the tip throws on the lip below it, and the crease
            # round each wing, which is what gives a nose its width from the front
            nt = L["nose_tip"]
            # The nostrils are under the tip and behind it, so they are painted only where the
            # surface faces down: centred 2 mm in front of the tip, 14 mm deep, they darkened the
            # front of the tip itself on a long nose (the hawk's read as a dark-tipped nose).
            under_tip = smoothstep(0.15, 0.55, -nrm[:, 2])
            for sx in (1, -1):
                nos = gauss(p, [sx * 0.0082 * s, nt[1] + 0.004 * s, nt[2] - 0.0065 * s],
                            [0.0046 * s, 0.009 * s, 0.0038 * s]) * under_tip
                c = mix(c, np.clip(t["shadow"] * 0.80, 0, 1), np.clip(nos, 0, 1) * 0.62)
                wing = stroke_xz(p, [(sx * 0.0150 * s, nt[2] + 0.0060 * s),
                                     (sx * 0.0180 * s, nt[2] - 0.0010 * s),
                                     (sx * 0.0130 * s, nt[2] - 0.0075 * s)],
                                 width=0.0024 * s, soft=0.9, y_centre=nt[1] + 0.012 * s, y_depth=0.022 * s)
                c = mix(c, t["shadow"], np.clip(wing, 0, 1) * 0.52)
                # the line from the wing of the nose to the corner of the mouth, which every adult
                # face has, deeper with age: it is most of what gives a face its expression
                fold = stroke_xz(p, [(sx * 0.0190 * s, nt[2] - 0.0020 * s),
                                     (sx * 0.0265 * s, mouth_z + 0.0070 * s),
                                     (sx * (mouth_w * 1.05), mouth_z - 0.0060 * s)],
                                 width=0.0030 * s, soft=0.9, y_centre=nt[1] + 0.022 * s, y_depth=0.026 * s)
                c = mix(c, t["shadow"], np.clip(fold, 0, 1) * (0.20 + 0.26 * age) * fold_k[sx])
            below = gauss(p, [0.0, nt[1] + 0.014 * s, nt[2] - 0.014 * s], [0.010 * s, 0.012 * s, 0.006 * s])
            c = mix(c, t["shadow"], np.clip(below, 0, 1) * 0.24)
            # under the cheekbone: a soft plane of shadow that gives a face its bones
            for sx in (1, -1):
                hollow_c = gauss(p, [sx * eye_x * 1.62, fy + 0.012 * s, eye_z - 0.074 * s],
                                 [0.016 * s, 0.028 * s, 0.020 * s])
                c = mix(c, t["shadow"], np.clip(hollow_c, 0, 1) * 0.24)
                # weathering: a little shadow under each eye, more with years
                bag = stroke_xz(p, [(sx * eye_x - sx * eye_r * 0.8, eye_z - eye_r * 1.05),
                                    (sx * eye_x, eye_z - eye_r * 1.25),
                                    (sx * eye_x + sx * eye_r * 0.9, eye_z - eye_r * 0.95)],
                                width=eye_r * 0.35, soft=0.95, y_centre=fy + 0.004 * s, y_depth=0.030 * s)
                c = mix(c, np.clip(mix(t["shadow"], t["blush"] * 0.7, 0.2), 0, 1),
                        np.clip(bag, 0, 1) * (0.18 + 0.24 * age))
                # crow's feet: three short lines fanning from the outer corner, from the thirties on
                if age > 0.25:
                    a_cf = min((age - 0.25) / 0.5, 1.0)
                    ox = sx * (eye_x + eye_r * 1.45)
                    for dz, dx in ((0.30, 0.95), (0.0, 1.05), (-0.32, 0.90)):
                        cf = stroke_xz(p, [(ox, eye_z + eye_r * dz * 0.4),
                                           (ox + sx * eye_r * dx, eye_z + eye_r * dz * 1.4)],
                                       width=eye_r * 0.10, soft=0.9, y_centre=fy + 0.020 * s, y_depth=0.030 * s)
                        c = mix(c, t["shadow"], np.clip(cf, 0, 1) * 0.30 * a_cf * fold_k[-sx])
            if stubble > 0.01:
                jaw = (1.0 - smoothstep(mouth_z + 0.018 * s, mouth_z + 0.050 * s, p[:, 2])) * \
                    smoothstep(chin_z - 0.05 * s, chin_z - 0.01 * s, p[:, 2]) * \
                    (1.0 - smoothstep(0.02 * s, 0.06 * s, p[:, 1]))
                nolip = 1.0 - np.clip((upper + lower) * 1.4, 0, 1)
                grain = 0.5 + 0.5 * n.at(p, 320.0)
                c = mix(c, beard_rgb, np.clip(jaw * nolip * grain, 0, 1) * 0.38 * stubble)
            if age > 0.6:
                # marionette lines: from the corners of the mouth down towards the jaw
                a_m = (age - 0.6) / 0.4
                for sx in (1, -1):
                    ml = stroke_xz(p, [(sx * mw * 1.02, mouth_z - 0.004 * s),
                                       (sx * mw * 1.10, mouth_z - 0.020 * s)],
                                   width=0.0026 * s, soft=0.9, y_centre=lip_y + 0.006 * s, y_depth=0.026 * s)
                    c = mix(c, t["shadow"], np.clip(ml, 0, 1) * 0.30 * a_m * fold_k[sx])
            if age > 0.35:
                a = min((age - 0.35) / 0.5, 1.0)
                for dz in (0.020, 0.030):
                    crease = stroke_xz(p, [(-0.040 * s, L["brow_z"] + dz * s),
                                           (0.0, L["brow_z"] + (dz + 0.003) * s),
                                           (0.040 * s, L["brow_z"] + dz * s)],
                                       width=0.0026 * s, soft=0.9, y_centre=fy + 0.012 * s, y_depth=0.030 * s)
                    c = mix(c, t["shadow"], np.clip(crease, 0, 1) * 0.22 * a)
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


AGE_INK = np.array([0.74, 0.62, 0.58])   # what a line does to the skin under it, as a multiplier


def dots(p: np.ndarray, cell: float, keep: float, r_lo: float, r_hi: float, seed: int = 0) -> np.ndarray:
    """Round spots scattered through space: one candidate per `cell`-sized cube, jittered, kept
    with probability `keep`, each `r_lo`..`r_hi` in radius, soft at the rim. 0..1 coverage.

    Freckles were value noise thresholded, and value noise is aligned to its lattice: the spots
    came out as squares and bars, a camouflage pattern over the face rather than freckles."""
    rng = np.random.default_rng(seed)
    table = rng.random((5, 32, 32, 32))
    q = np.asarray(p, float) / cell
    i0 = np.floor(q).astype(np.int64)
    out = np.zeros(len(q))
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = i0 + np.array([dx, dy, dz])
                ix, iy, iz = c[:, 0] % 32, c[:, 1] % 32, c[:, 2] % 32
                centre = c + np.stack([table[0, ix, iy, iz], table[1, ix, iy, iz], table[2, ix, iy, iz]], axis=1)
                r = (r_lo + (r_hi - r_lo) * table[3, ix, iy, iz]) / cell
                d = np.linalg.norm(q - centre, axis=1)
                cov = np.clip((r - d) / np.maximum(r * 0.45, 1e-9), 0.0, 1.0) * (table[4, ix, iy, iz] < keep)
                out = np.maximum(out, cov)
    return out


def face_marks(landmarks: dict, seed: int = 0) -> Tuple[Callable, Callable]:
    """What a life puts on a face, as four masks the engine lays over a young, even bake by the
    person (skin.gdshader `marks_tex`, HumanoidModel.face_marks_for):

      R  the lines of age (age_lines)
      G  ruddiness: the cheeks, the nose, the ears and a little of the chin, mottled where the
         small veins are
      B  freckles: dots over the nose, the cheeks and the forehead, where the sun falls
      A  weathering: the sun and the wind on the forehead, the nose, the cheekbones and the tops
         of the ears

    Returns (rgb, alpha) paint functions."""
    L = landmarks
    s = L["s"]
    eye_x, eye_z = L["eye_x"], L["eye_z"]
    fy, nt, chin_z, brow_z = L["face_y"], L["nose_tip"], L["chin_z"], L["brow_z"]
    ec = L["ear_c"]
    n = Noise(seed + 211, 48)
    ink = age_lines(landmarks, seed)

    def rgb(p: np.ndarray, nrm: np.ndarray) -> np.ndarray:
        age = (1.0 - ink(p, nrm)[:, 0]) / (1.0 - AGE_INK[0])
        cheeks = sum(gauss(p, [sx * eye_x * 1.45, fy + 0.020 * s, eye_z - 0.046 * s],
                           [0.034 * s, 0.034 * s, 0.030 * s]) for sx in (1, -1))
        nose = gauss(p, [0.0, fy - 0.004 * s, nt[2]], [0.018 * s, 0.024 * s, 0.020 * s])
        ears = sum(gauss(p, [sx * ec[0], ec[1], ec[2]], [0.020 * s, 0.026 * s, 0.030 * s]) for sx in (1, -1))
        chin = gauss(p, [0.0, fy + 0.004 * s, chin_z + 0.020 * s], [0.020 * s, 0.020 * s, 0.016 * s])
        veins = 0.70 + 0.60 * n.fbm(p, freq=90.0, octaves=2)
        ruddy = np.clip(np.maximum.reduce([cheeks, nose * 0.95, ears * 0.75, chin * 0.35]) * veins, 0, 1)
        sun = np.clip(np.maximum.reduce([
            sum(gauss(p, [sx * eye_x * 1.30, fy + 0.012 * s, eye_z - 0.030 * s],
                      [0.030 * s, 0.030 * s, 0.026 * s]) for sx in (1, -1)),
            gauss(p, [0.0, fy - 0.004 * s, 0.5 * (nt[2] + L["nose_root_z"])], [0.016 * s, 0.030 * s, 0.030 * s]),
            gauss(p, [0.0, fy + 0.006 * s, brow_z + 0.020 * s], [0.040 * s, 0.040 * s, 0.020 * s]) * 0.7]), 0, 1)
        # small round spots, thickest over the nose and the tops of the cheeks, where the sun is
        spots = dots(p, 0.0034 * s, 0.60, 0.0006 * s, 0.0013 * s, seed + 5)
        freckles = np.clip(spots * np.clip(sun * 1.4, 0, 1), 0, 1)
        return np.stack([np.clip(age, 0, 1), ruddy, freckles], axis=1)

    def alpha(p: np.ndarray, nrm: np.ndarray) -> np.ndarray:
        sun = np.maximum.reduce([
            gauss(p, [0.0, fy + 0.004 * s, brow_z + 0.030 * s], [0.060 * s, 0.050 * s, 0.035 * s]),
            gauss(p, [0.0, fy - 0.004 * s, 0.5 * (nt[2] + L["nose_root_z"])], [0.016 * s, 0.030 * s, 0.034 * s]),
            sum(gauss(p, [sx * eye_x * 1.50, fy + 0.012 * s, eye_z - 0.036 * s],
                      [0.030 * s, 0.030 * s, 0.026 * s]) for sx in (1, -1)),
            sum(gauss(p, [sx * ec[0], ec[1], ec[2] + 0.020 * s], [0.016 * s, 0.024 * s, 0.016 * s]) for sx in (1, -1)) * 0.8])
        # the rest of a face weathers too, less, and unevenly
        w = np.clip(0.30 + 0.70 * sun, 0, 1) * (0.70 + 0.60 * n.fbm(p, freq=20.0, octaves=2))
        return np.repeat(np.clip(w, 0, 1)[:, None], 3, axis=1)
    return rgb, alpha


def age_lines(landmarks: dict, seed: int = 0) -> PaintFn:
    """The lines years put on a face, as a multiplier over the skin (white where there are none):
    the forehead's creases, the two furrows between the brows, crow's feet, the fold from nose to
    mouth, the lines down from the corners of the mouth and the shadow under the eyes. Every head
    is baked young; the engine lays this over it by the record's age (skin.gdshader `age_tex`),
    so one head serves a girl and her grandmother and the old look old."""
    L = landmarks
    s = L["s"]
    eye_x, eye_z, eye_r = L["eye_x"], L["eye_z"], L["eye_r"]
    fy, mouth_z, mw = L["face_y"], L["mouth_z"], L["mouth_w"]
    nt = L["nose_tip"]
    mouth_front = float(L["stations"][3][2]) if "stations" in L else fy - 0.006 * s
    lip_y = mouth_front - 0.004 * s
    rng = np.random.default_rng(seed + 717)
    side_k = {sx: float(rng.uniform(0.8, 1.2)) for sx in (1, -1)}
    tilt = float(rng.uniform(-0.002, 0.002)) * s

    def fn(p: np.ndarray, nrm: np.ndarray) -> np.ndarray:
        ink = np.zeros(len(p))

        def add(mask, k):
            nonlocal ink
            ink = np.maximum(ink, np.clip(mask, 0, 1) * k)
        # forehead: three shallow arcs, the upper ones shorter
        for i, dz in enumerate((0.018, 0.028, 0.038)):
            half = (0.046 - 0.006 * i) * s
            add(stroke_xz(p, [(-half, L["brow_z"] + dz * s - tilt),
                              (0.0, L["brow_z"] + (dz + 0.004) * s),
                              (half, L["brow_z"] + dz * s + tilt)],
                          width=0.0024 * s, soft=0.9, y_centre=fy + 0.014 * s, y_depth=0.034 * s), 0.55 - 0.08 * i)
        for sx in (1, -1):
            k = side_k[sx]
            # the furrow between the brows
            add(stroke_xz(p, [(sx * 0.0060 * s, L["brow_z"] - 0.004 * s), (sx * 0.0045 * s, L["brow_z"] + 0.012 * s)],
                          width=0.0020 * s, soft=0.9, y_centre=fy + 0.004 * s, y_depth=0.028 * s), 0.40 * k)
            # crow's feet
            ox = sx * (eye_x + eye_r * 1.45)
            for dz, dx in ((0.35, 1.05), (0.0, 1.20), (-0.38, 1.0)):
                add(stroke_xz(p, [(ox, eye_z + eye_r * dz * 0.4), (ox + sx * eye_r * dx, eye_z + eye_r * dz * 1.5)],
                              width=eye_r * 0.10, soft=0.9, y_centre=fy + 0.020 * s, y_depth=0.034 * s), 0.50 * k)
            # under the eye: a fold and its shadow
            add(stroke_xz(p, [(sx * eye_x - sx * eye_r * 0.8, eye_z - eye_r * 1.05),
                              (sx * eye_x, eye_z - eye_r * 1.30),
                              (sx * eye_x + sx * eye_r * 0.9, eye_z - eye_r * 0.95)],
                          width=eye_r * 0.30, soft=0.95, y_centre=fy + 0.004 * s, y_depth=0.030 * s), 0.36 * k)
            # nose to mouth, deeper
            add(stroke_xz(p, [(sx * 0.0190 * s, nt[2] - 0.0020 * s),
                              (sx * 0.0265 * s, mouth_z + 0.0070 * s),
                              (sx * (mw * 1.05), mouth_z - 0.0060 * s)],
                          width=0.0030 * s, soft=0.9, y_centre=nt[1] + 0.022 * s, y_depth=0.026 * s), 0.46 * k)
            # the corners of the mouth, down towards the jaw
            add(stroke_xz(p, [(sx * mw * 1.02, mouth_z - 0.004 * s), (sx * mw * 1.12, mouth_z - 0.024 * s)],
                          width=0.0026 * s, soft=0.9, y_centre=lip_y + 0.006 * s, y_depth=0.026 * s), 0.42 * k)
            # a hollow under the cheekbone
            add(gauss(p, [sx * eye_x * 1.62, fy + 0.012 * s, eye_z - 0.074 * s], [0.016 * s, 0.028 * s, 0.020 * s]), 0.26)
        return 1.0 - ink[:, None] * (1.0 - AGE_INK[None, :])
    return fn


def warm_points_for(skel, landmarks: dict) -> List[Tuple[np.ndarray, Tuple[float, float, float]]]:
    """Where skin reddens: knuckles, the heel of the hand, elbows, knees, the ball of the
    foot, ears and the nose.  Painting these keeps a limb from being one plastic value."""
    s = float(skel.props.height / 1.78)
    J = skel.J
    out: List[Tuple[np.ndarray, Tuple[float, float, float]]] = []
    r_hand = (0.055 * s, 0.055 * s, 0.055 * s)
    r_joint = (0.060 * s, 0.060 * s, 0.055 * s)
    for side in ("L", "R"):
        out.append((J[f"Hand.{side}"] * 0.35 + J[f"HandTip.{side}"] * 0.65, r_hand))
        out.append((J[f"LowerArm.{side}"], r_joint))
        out.append((J[f"LowerLeg.{side}"] + np.array([0.0, -0.02 * s, 0.0]), r_joint))
        out.append((J[f"Toe.{side}"], (0.055 * s, 0.070 * s, 0.040 * s)))
    return out


def skin_orm(landmarks: dict, seed: int = 0, age: float = 0.3, oily: float = 0.35,
             scene=None, occ_radius: float = 0.05) -> Tuple[PaintFn, PaintFn]:
    """(occlusion, roughness) paint functions for skin; metallic is always zero."""
    n = Noise(seed + 77, 32)

    def occ(p, nrm):
        down = np.clip(-nrm[:, 2], 0, 1)
        v = 1.0 - 0.22 * down - 0.08 * n.fbm(p, freq=9.0, octaves=2)
        if scene is not None:
            v = v * (0.30 + 0.70 * sdf_occlusion(scene, p, nrm, radius=occ_radius, samples=5))
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
    # (a larger iris than it was, 0.205: the white round a small one made every face stare)
    pupil_r, iris_r, limb_r = 0.084, 0.238, 0.258
    fibre = 0.5 + 0.5 * np.sin(U * 2 * math.pi * 38 + rng.random() * 6.28)
    fibre = fibre * (0.5 + 0.5 * np.sin(U * 2 * math.pi * 17 + 1.7))
    radial = np.clip((V - pupil_r) / max(iris_r - pupil_r, 1e-6), 0, 1)
    iris = mix(np.clip(base * 0.62, 0, 1).reshape(1, 1, 3).repeat(size, 0).repeat(size, 1).reshape(-1, 3),
               np.clip(base * 1.25 + 0.04, 0, 1).reshape(1, 1, 3).repeat(size, 0).repeat(size, 1).reshape(-1, 3),
               (0.35 + 0.65 * radial).ravel()).reshape(size, size, 3)
    iris = iris * (0.82 + 0.30 * fibre[..., None] * radial[..., None])
    out = np.where((V < iris_r)[..., None], iris, sclera.reshape(1, 1, 3))
    # limbal ring, pupil, corner shading of the sclera
    ring = smoothstep(iris_r - 0.030, iris_r, V) * (1.0 - smoothstep(limb_r, limb_r + 0.016, V))
    out = out * (1.0 - 0.75 * ring[..., None])
    pup = 1.0 - smoothstep(pupil_r - 0.016, pupil_r, V)
    out = out * (1.0 - 0.94 * pup[..., None])
    shade = smoothstep(0.30, 0.62, V)
    out = out * (1.0 - 0.30 * shade[..., None])
    # the shadow the upper lid and its lashes throw on the eye: the top of the iris and the white
    # just under the lid (u 0.25 is straight up on the eye mesh)
    du = np.minimum(np.abs(U - 0.25), 1.0 - np.abs(U - 0.25))
    lid = np.exp(-0.5 * (du / 0.11) ** 2) * smoothstep(0.10, 0.20, V) * (1.0 - smoothstep(0.34, 0.46, V))
    out = out * (1.0 - 0.42 * lid[..., None])
    spec = np.exp(-0.5 * ((((U - 0.17) % 1.0 - 0.0) / 0.022) ** 2 + ((V - 0.095) / 0.028) ** 2))
    out = np.clip(out + spec[..., None] * np.array([1.0, 0.99, 0.95]) * 0.85, 0, 1)
    if glint > 0.01:
        g = np.exp(-0.5 * ((((U - 0.30) % 1.0 - 0.0) / 0.03) ** 2 + ((V - 0.075) / 0.035) ** 2))
        out = np.clip(out + g[..., None] * np.array([1.0, 0.92, 0.72]) * glint, 0, 1)
    return np.clip(out, 0, 1)


def strand_directions(P: np.ndarray, nrm: np.ndarray, flow_fn=None, locks: Sequence[np.ndarray] = (),
                      reach: float = 0.012) -> np.ndarray:
    """The way the hair runs at each point: along the nearest combed lock where there is one
    within `reach`, along the style's flow elsewhere, always lying in the surface."""
    f = flow_fn(P) if flow_fn is not None else np.tile(np.array([0.0, 0.0, -1.0]), (len(P), 1))
    if locks:
        A = np.concatenate([l[:-1] for l in locks if len(l) > 1], axis=0)
        B = np.concatenate([l[1:] for l in locks if len(l) > 1], axis=0)
        D = B - A
        L2 = np.maximum(np.sum(D * D, axis=1), 1e-12)
        best = np.full(len(P), np.inf)
        idx = np.zeros(len(P), dtype=np.int64)
        chunk = max(1, 4_000_000 // max(len(A), 1))
        for i in range(0, len(P), chunk):
            Q = P[i:i + chunk]
            t = np.clip(np.einsum("nij,ij->ni", Q[:, None, :] - A[None], D) / L2[None], 0.0, 1.0)
            d2 = np.sum((Q[:, None, :] - (A[None] + t[..., None] * D[None])) ** 2, axis=2)
            j = np.argmin(d2, axis=1)
            best[i:i + chunk] = d2[np.arange(len(Q)), j]
            idx[i:i + chunk] = j
        near = best < reach * reach
        f[near] = D[idx[near]] / np.sqrt(L2[idx[near]])[:, None]
    f = f - nrm * np.sum(f * nrm, axis=1, keepdims=True)
    return f / np.maximum(np.linalg.norm(f, axis=1, keepdims=True), 1e-9)


def hair_strands(colour: str = "brown", seed: int = 0, *, flow_fn=None, locks: Sequence[np.ndarray] = (),
                 scalp=None, field=None, s: float = 1.0):
    """(albedo, orm, height) paint functions for combed hair.

    The grain runs along the hair: noise is read in the plane across each strand's direction,
    so it smears into stripes that follow the comb, in two sizes -- the clump and the strand.
    Value does the rest, as it does in a painting: dark at the roots and down in the grooves
    between locks (the part's own field gives the occlusion), light along the crests, and a
    soft band of shine where the hair turns up to the sky. The colour stays the bake's one
    brown; the game tints it by ratio (CharacterAppearance.hair_tint)."""
    base = hex_rgb(HAIR_COLOURS.get(colour, HAIR_COLOURS["brown"]))
    n = Noise(seed + 13, 64)
    n2 = Noise(seed + 29, 64)

    def _grain(P, nrm):
        f = strand_directions(P, nrm, flow_fn, locks)
        Q = P - f * np.sum(P * f, axis=1, keepdims=True)
        clump = n.fbm(Q, freq=240.0 / s, octaves=2)
        strand = n2.at(Q, 820.0 / s)
        return clump, strand

    def _root(P):
        if scalp is None:
            return np.ones(len(P))
        return np.clip(scalp.eval(P) / (0.010 * s), 0.0, 1.0)

    def _occ(P, nrm):
        if field is None:
            return np.ones(len(P))
        return sdf_occlusion(field, P, nrm, radius=0.010 * s, samples=4, strength=1.0)

    def albedo(P, nrm):
        clump, strand = _grain(P, nrm)
        root = _root(P)
        occ = _occ(P, nrm)
        v = 0.66 + 0.34 * clump + 0.10 * (strand - 0.5)
        v = v * (0.66 + 0.34 * root) * (0.50 + 0.50 * occ)
        crest = exposure(occ, 3.0)
        v = v + 0.20 * crest * (0.5 + clump)
        up = np.clip(nrm[:, 2], 0.0, 1.0)
        shine = smoothstep(0.45, 0.80, up) * (1.0 - smoothstep(0.92, 1.0, up))
        v = v + 0.16 * shine * (0.4 + 0.8 * clump)
        c = np.clip(base * 1.25 + 0.02, 0, 1) * v[:, None]
        return np.clip(c, 0.0, 1.0)

    def orm(P, nrm):
        clump, strand = _grain(P, nrm)
        occ = _occ(P, nrm)
        r = 0.58 + 0.16 * (1.0 - clump) + 0.10 * (1.0 - occ)
        return np.stack([np.clip(0.55 + 0.45 * occ, 0, 1), np.clip(r, 0.3, 0.95), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        clump, strand = _grain(P, nrm)
        return 0.7 * clump + 0.3 * strand

    return albedo, orm, height


def hair_paint(colour: str = "brown", seed: int = 0, grey: float = 0.0) -> PaintFn:
    """Strand-flavoured colour for hair and beard shells."""
    base = hex_rgb(HAIR_COLOURS.get(colour, HAIR_COLOURS["brown"]))
    n = Noise(seed + 13, 32)

    def fn(p, nrm):
        strand = n.fbm(p * np.array([3.0, 1.0, 1.0]), freq=120.0, octaves=2)
        big = n.fbm(p, freq=14.0, octaves=3)
        c = np.broadcast_to(base, (len(p), 3)).copy()
        # lighter overall and less contrasty than before: a dark head of hair baked at full
        # strength goes to a black shell once the engine's own shading is on top of it
        c = np.clip(c * 1.22 + 0.035, 0, 1)
        c = mix(c, np.clip(base * 0.62, 0, 1), 0.34 * strand)
        c = mix(c, np.clip(base * 1.9 + 0.12, 0, 1), 0.42 * smoothstep(0.45, 0.92, big) * np.clip(nrm[:, 2], 0, 1))
        if grey > 0.01:
            g = smoothstep(0.35, 0.85, n.fbm(p, freq=9.0, octaves=2))
            c = mix(c, np.array([0.80, 0.78, 0.75]), np.clip(g * grey, 0, 1))
        return np.clip(c, 0, 1)
    return fn
