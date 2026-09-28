"""Hair cards (triage 47): hair and beards as layered strips of strands, not solid shells.

A shell of hair (cloth.hair) is a solid, and however it is shaded it reads as a helmet or a few
glossy clumps, with a hard edge on the forehead. Real-time hair is drawn as cards: narrow strips
laid along the way the hair is combed, each textured with a clump of strands whose gaps are cut
out, layered so the inner cards give the mass and the outer ones the broken outline.

What a style becomes here, all in one mesh and one material:

* **the scalp cap** -- a thin skin a millimetre over the scalp, lit as hair, its roots painted
  dark. Its `density` (1 inside the hairline) falls off over a centimetre past the hairline, and
  the shader thins it grain by grain (`hair_grain.png`), so the hairline fades onto the forehead
  instead of ending on a line. Where a style is shaved (`Groom.strip`) the cap keeps a stubble's
  density and is drawn as stubble is: grains with the skin between.
* **cards** -- strips combed along the style's own guide curves (cloth.flow_field, the same comb
  the shell was grown by, walked for hundreds of guides at once in `comb_many`), in layers: dense
  wide cards close to the scalp, medium ones over them, a few wispy ones on top, and short fine
  cards along the hairline. More of them near the parting and the crown, where hair grows
  thickest. Each card's UV runs root (v 0) to tip (v 1) along one of the atlas's clumps.
* **solid strand tubes** -- plaits, a bun's coil, a tail's body: a few-sided tube wrapped in the
  same atlas with its gaps filled, which reads as tightly bound hair.

The strand atlas (`strand_atlas`, `game/assets/textures/characters/hair_strands.png`) is shared by
every style and beard: eight clumps side by side, strands running down, alpha cut out. R is the
strand's value, G an id per strand (the shine's shift), B how near the front of the clump it is.

Per-vertex data the shader (`hair_cards.gdshader`) reads:
    UV      the atlas (cards, u in [0, 1)); u in [1, 2) the atlas with its gaps filled (tubes);
            u >= 2 the cap, in metres / CAP_TILE for the tiling grain
    UV2     x root (0) to tip (1); y density (1 full, falling off past the hairline)
    TANGENT the strand's direction, root to tip (Kajiya-Kay runs along it)
    NORMAL  the hair mass's outward normal, not the card's own: both faces of a card are lit as
            the mass is, so a card seen edge-on or from inside is not black
    COLOR   r a random per card, g how free it is to sway (0 on the scalp), b its layer (0 inner,
            1 outer), a 1

Pure numpy: no Blender. `attach_cards` writes the cards into a part's GLB as a second mesh beside
the shell, which the game keeps as the far level of detail (HumanoidModel: the cards to
CARDS_RANGE, the shell beyond)."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig, sdf, body as bodylib, cloth
from .rig import Skeleton

DOWN = np.array([0.0, 0.0, -1.0])

# ----------------------------------------------------------------------------------------------
# the strand atlas
# ----------------------------------------------------------------------------------------------

ATLAS_W = 1024
ATLAS_H = 1024
CELLS = 8
CELL_PX = ATLAS_W // CELLS
# a cap's grain tiles every CAP_TILE metres
CAP_TILE = 0.030
# which cells each kind of card draws from
CELL_OF = {"dense": (0, 1), "medium": (2, 3), "wispy": (4, 5), "fine": (6,), "wavy": (7,)}


@dataclass
class ClumpSpec:
    strands: int
    clumps: int            # how many sub-clumps the strands gather into towards the tip
    pull: float            # how far they gather (0 none, 1 to a point)
    length: Tuple[float, float]
    width: Tuple[float, float]   # strand width in pixels at the root
    wander: float          # pixels of slow drift
    wave: float = 0.0      # pixels of wave (curls)
    waves: float = 0.0     # waves down the cell


CLUMPS = [
    ClumpSpec(78, 3, 0.55, (0.80, 1.00), (1.6, 2.6), 3.0),
    ClumpSpec(66, 2, 0.60, (0.78, 1.00), (1.6, 2.4), 3.5),
    ClumpSpec(46, 3, 0.65, (0.62, 1.00), (1.4, 2.2), 4.0),
    ClumpSpec(40, 2, 0.70, (0.60, 1.00), (1.4, 2.2), 4.5),
    ClumpSpec(20, 2, 0.45, (0.40, 1.00), (1.2, 1.9), 6.0),
    ClumpSpec(15, 1, 0.40, (0.35, 1.00), (1.2, 1.8), 7.0),
    ClumpSpec(11, 1, 0.20, (0.45, 1.00), (1.0, 1.5), 5.0),
    ClumpSpec(44, 3, 0.55, (0.60, 1.00), (1.4, 2.2), 3.0, wave=7.0, waves=5.5),
]


def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def strand_atlas(seed: int = 4747, w: int = ATLAS_W, h: int = ATLAS_H) -> np.ndarray:
    """(h, w, 4) float in 0..1: the eight clumps, roots at the top. Colour is spread into the
    transparent texels round the strands (so the mips do not darken towards the gaps)."""
    rng = np.random.default_rng(seed)
    cw = w // CELLS
    out = np.zeros((h, w, 4))
    rows = np.arange(h)
    v = (rows + 0.5) / h
    for ci, spec in enumerate(CLUMPS):
        C = np.zeros((h, cw, 3))
        A = np.zeros((h, cw))
        margin = 7.0
        centres = rng.uniform(margin + 10, cw - margin - 10, spec.clumps)
        # back to front: the first strands drawn are the deepest
        order = np.arange(spec.strands)
        for k in order:
            depth = (k + 1) / spec.strands                   # 0 deep .. 1 in front
            x0 = rng.uniform(margin, cw - margin)
            clump = centres[np.argmin(np.abs(centres - x0))]
            length = rng.uniform(*spec.length)
            w0 = rng.uniform(*spec.width)
            ph = rng.uniform(0, 2 * math.pi, 3)
            drift = (spec.wander * (np.sin(v * 2.1 * math.pi + ph[0]) * 0.6 + np.sin(v * 5.3 * math.pi + ph[1]) * 0.4))
            pull = spec.pull * rng.uniform(0.6, 1.2)
            x = x0 + (clump - x0) * pull * np.clip(v / max(length, 1e-3), 0, 1) ** 1.6 + drift
            if spec.wave > 0:
                x = x + spec.wave * rng.uniform(0.7, 1.2) * np.sin(v * spec.waves * 2 * math.pi + ph[2])
            x = np.clip(x, 3.0, cw - 4.0)
            u = v / max(length, 1e-3)
            width = w0 * (1.0 - 0.55 * np.clip(u, 0, 1) ** 2)
            # the strand ends over its last tenth, and starts a little in from the root row
            fade = (1.0 - _smooth((u - 0.88) / 0.12)) * _smooth(v / 0.012)
            value = rng.uniform(0.55, 1.0) * (0.80 + 0.20 * depth)
            sid = rng.uniform(0.0, 1.0)
            live = u < 1.0
            for dx in range(-3, 4):
                col = np.floor(x).astype(int) + dx
                ok = live & (col >= 0) & (col < cw)
                d = np.abs(col + 0.5 - x)
                a = np.clip(width * 0.5 + 0.5 - d, 0.0, 1.0) * fade
                a = np.where(ok, a, 0.0)
                r, cc = rows[ok], col[ok]
                aa = a[ok]
                # a strand is a little lighter along its middle
                lit = value * (0.85 + 0.15 * np.clip(1.0 - d[ok] / np.maximum(width[ok] * 0.5, 0.5), 0, 1))
                src = np.stack([lit, np.full(len(lit), sid), np.full(len(lit), depth)], axis=1)
                C[r, cc] = src * aa[:, None] + C[r, cc] * (1.0 - aa[:, None])
                A[r, cc] = aa + A[r, cc] * (1.0 - aa)
        out[:, ci * cw:(ci + 1) * cw, :3] = C
        out[:, ci * cw:(ci + 1) * cw, 3] = A
    # colour spread into the gaps: a blur of the premultiplied colour over the blur of alpha
    rgb, a = out[..., :3], out[..., 3]
    pre, al = rgb * a[..., None], a.copy()
    for _ in range(4):
        pre = _box_blur(pre, 3)
        al = _box_blur(al[..., None], 3)[..., 0]
    fill = pre / np.maximum(al[..., None], 1e-4)
    fill = np.where(al[..., None] > 1e-4, fill, np.array([0.7, 0.5, 0.5]))
    out[..., :3] = np.where(a[..., None] > 0.02, rgb / np.maximum(a[..., None], 1e-4) * a[..., None]
                            + fill * (1 - a[..., None]), fill)
    return np.clip(out, 0.0, 1.0)


def _box_blur(img: np.ndarray, r: int) -> np.ndarray:
    """A box blur along both axes that does not wrap (each cell's columns stay its own)."""
    out = img
    for ax in (0, 1):
        c = np.cumsum(np.pad(out, [(r + 1, r) if i == ax else (0, 0) for i in range(out.ndim)], mode="edge"), axis=ax)
        n = out.shape[ax]
        hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax)
        lo = np.take(c, np.arange(0, n), axis=ax)
        out = (hi - lo) / (2 * r + 1)
    return out


def _periodic_noise(n: int, rng, sx: float, sy: float) -> np.ndarray:
    """Tileable noise: white noise through a Gaussian in frequency, `sx`, `sy` its feature size
    in texels across and down."""
    f = np.fft.fftfreq(n)
    FX, FY = np.meshgrid(f, f)
    g = np.exp(-0.5 * ((FX * sx * 2 * math.pi) ** 2 + (FY * sy * 2 * math.pi) ** 2))
    z = np.real(np.fft.ifft2(np.fft.fft2(rng.normal(size=(n, n))) * g))
    z = (z - z.mean()) / max(z.std(), 1e-9)
    return z


def grain_tile(size: int = 256, seed: int = 4748) -> np.ndarray:
    """(size, size, 4) float, tiling: R the grain a thinning cap is cut by -- short dark hairs
    (strong) on a breaking-up ground (weaker), so as the density falls the ground goes first and
    the hairs last, and a shaved scalp is dots of stubble with skin between; G streaks drawn out
    down the tile (the painted roots along the comb); B fine noise."""
    rng = np.random.default_rng(seed)
    n = size
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    dots = np.zeros((n, n))
    count = int(n * n / 70)
    P = rng.uniform(0, n, (count, 2))
    strength = rng.uniform(0.62, 1.0, count)
    ang = rng.normal(0.0, 0.35, count)
    for (px, py), st, a in zip(P, strength, ang):
        dx = (xx - px + n / 2) % n - n / 2
        dy = (yy - py + n / 2) % n - n / 2
        ca, sa = math.cos(a), math.sin(a)
        u = dx * ca - dy * sa
        w = dx * sa + dy * ca
        r = np.sqrt((u / 1.0) ** 2 + (w / 2.4) ** 2)
        dots = np.maximum(dots, st * np.clip(1.4 - r, 0.0, 1.0))
    ground = _periodic_noise(n, rng, 2.5, 6.0)
    ground = np.clip(0.30 + 0.12 * ground, 0.0, 0.6)
    R = np.maximum(dots, ground)
    G = np.clip(0.5 + 0.22 * _periodic_noise(n, rng, 0.8, 9.0), 0, 1)
    B = np.clip(0.5 + 0.25 * _periodic_noise(n, rng, 1.0, 1.0), 0, 1)
    return np.stack([R, G, B, np.ones_like(R)], axis=-1)


# ----------------------------------------------------------------------------------------------
# geometry: the pieces a head of hair is built from
# ----------------------------------------------------------------------------------------------

class Builder:
    """Collects vertices and triangles with every attribute the shader reads."""

    def __init__(self):
        self.P, self.N, self.T, self.UV, self.UV2, self.COL, self.idx = [], [], [], [], [], [], []
        self.n = 0
        self.cards = 0

    def add(self, P, N, T, UV, UV2, COL, tris):
        k = len(P)
        self.P.append(np.asarray(P, float)); self.N.append(np.asarray(N, float))
        self.T.append(np.asarray(T, float)); self.UV.append(np.asarray(UV, float))
        self.UV2.append(np.asarray(UV2, float)); self.COL.append(np.asarray(COL, float))
        self.idx.append(np.asarray(tris, np.int64) + self.n)
        self.n += k

    def arrays(self) -> Dict[str, np.ndarray]:
        if not self.P:
            return {}
        return {"P": np.concatenate(self.P), "N": _unit(np.concatenate(self.N)), "T": _unit(np.concatenate(self.T)),
                "UV": np.concatenate(self.UV), "UV2": np.concatenate(self.UV2), "COL": np.concatenate(self.COL),
                "tris": np.concatenate(self.idx)}


def _unit(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def resample(C: np.ndarray, seg: float, k_min: int = 2, k_max: int = 18) -> np.ndarray:
    """A polyline resampled evenly along its length into about `seg`-long segments."""
    d = np.linalg.norm(np.diff(C, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(d)])
    if arc[-1] < 1e-5:
        return C[:1]
    k = int(np.clip(math.ceil(arc[-1] / seg), k_min, k_max))
    t = np.linspace(0.0, arc[-1], k + 1)
    return np.stack([np.interp(t, arc, C[:, i]) for i in range(3)], axis=1)


def ribbon(b: Builder, C: np.ndarray, out: np.ndarray, w_root: float, w_tip: float, cell: int, rng,
           layer: float, sway: np.ndarray, twist: float = 0.0, density: float = 1.0, solid: bool = False,
           v_span: Tuple[float, float] = (0.0, 1.0), widen: Optional[np.ndarray] = None) -> None:
    """One card along the centreline C (K+1 points), facing `out` (the mass's normal at each point).
    It narrows from `w_root` to `w_tip`, turned `twist` radians about its own length (so cards are
    not all flat to the head), and is mapped across atlas cell `cell`, root to tip down it."""
    K1 = len(C)
    if K1 < 2:
        return
    seg = np.diff(C, axis=0)
    t = _unit(np.concatenate([seg[:1], seg[:-1] + seg[1:], seg[-1:]], axis=0))
    side = _unit(np.cross(t, out))
    nrm = _unit(np.cross(side, t))
    if twist:
        side = _unit(side * math.cos(twist) + nrm * math.sin(twist))
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(seg, axis=1))])
    u = arc / max(arc[-1], 1e-9)
    width = w_root + (w_tip - w_root) * u ** 1.2
    if widen is not None:
        width = width * widen
    L = C - side * (width * 0.5)[:, None]
    R = C + side * (width * 0.5)[:, None]
    P = np.empty((K1 * 2, 3))
    P[0::2], P[1::2] = L, R
    u0 = (cell * CELL_PX + 2.0) / ATLAS_W
    u1 = ((cell + 1) * CELL_PX - 2.0) / ATLAS_W
    if rng.random() < 0.5:
        u0, u1 = u1, u0
    if solid:
        u0, u1 = u0 + 1.0, u1 + 1.0
    vv = v_span[0] + (v_span[1] - v_span[0]) * u
    UV = np.empty((K1 * 2, 2))
    UV[0::2, 0], UV[1::2, 0] = u0, u1
    UV[0::2, 1] = UV[1::2, 1] = vv
    UV2 = np.stack([np.repeat(u, 2), np.full(K1 * 2, density)], axis=1)
    rnd = rng.random()
    COL = np.stack([np.full(K1 * 2, rnd), np.repeat(sway, 2), np.full(K1 * 2, layer), np.ones(K1 * 2)], axis=1)
    i = np.arange(K1 - 1) * 2
    tris = np.concatenate([np.stack([i, i + 1, i + 2], 1), np.stack([i + 1, i + 3, i + 2], 1)])
    b.add(P, np.repeat(nrm, 2, axis=0), np.repeat(t, 2, axis=0), UV, UV2, COL, tris)
    b.cards += 1


def tube(b: Builder, C: np.ndarray, radii: np.ndarray, cell: int, rng, sides: int = 5, layer: float = 0.6,
         sway: Optional[np.ndarray] = None, wraps: float = 1.0) -> None:
    """A solid tube of strands along C: a plait's strand, a bun's coil, a tail's body. The atlas
    runs along it with its gaps filled (u + 1)."""
    K1 = len(C)
    if K1 < 2:
        return
    seg = np.diff(C, axis=0)
    t = _unit(np.concatenate([seg[:1], seg[:-1] + seg[1:], seg[-1:]], axis=0))
    ref = np.array([0.0, 0.0, 1.0])
    a0 = _unit(np.cross(t, ref) + 1e-9 * np.array([1.0, 0.0, 0.0]))
    # parallel transport the frame so the tube does not twist
    A = np.empty_like(t)
    A[0] = a0[0]
    for k in range(1, K1):
        v = A[k - 1] - t[k] * np.dot(A[k - 1], t[k])
        A[k] = v / max(np.linalg.norm(v), 1e-9)
    Bn = np.cross(t, A)
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(seg, axis=1))])
    u = arc / max(arc[-1], 1e-9)
    radii = np.asarray(radii, float)
    if radii.ndim == 0:
        radii = np.full(K1, float(radii))
    elif len(radii) != K1:
        radii = np.interp(u, np.linspace(0.0, 1.0, len(radii)), radii)
    ring = np.linspace(0.0, 2 * math.pi, sides + 1)
    P, N, T, UV, UV2, COL = [], [], [], [], [], []
    rnd = rng.random()
    u0 = (cell * CELL_PX + 2.0) / ATLAS_W + 1.0
    du = (CELL_PX - 4.0) / ATLAS_W
    sw = np.zeros(K1) if sway is None else sway
    for j, th in enumerate(ring):
        d = A * math.cos(th) + Bn * math.sin(th)
        P.append(C + d * radii[:, None])
        N.append(d)
        T.append(t)
        UV.append(np.stack([np.full(K1, u0 + du * (j / sides)), u * wraps], axis=1))
        UV2.append(np.stack([u, np.ones(K1)], axis=1))
        COL.append(np.stack([np.full(K1, rnd), sw, np.full(K1, layer), np.ones(K1)], axis=1))
    P, N, T = np.concatenate(P), np.concatenate(N), np.concatenate(T)
    UV, UV2, COL = np.concatenate(UV), np.concatenate(UV2), np.concatenate(COL)
    tris = []
    for j in range(sides):
        a = j * K1 + np.arange(K1 - 1)
        c = (j + 1) * K1 + np.arange(K1 - 1)
        tris.append(np.stack([a, c, a + 1], 1))
        tris.append(np.stack([a + 1, c, c + 1], 1))
    b.add(P, N, T, UV, UV2, COL, np.concatenate(tris))


def ellipsoid_mesh(b: Builder, c: np.ndarray, R: np.ndarray, cell: int, rng, n_u: int = 10, n_v: int = 7,
                   flow: Optional[Callable] = None, layer: float = 0.3) -> None:
    """A solid, low ellipsoid in the atlas (a bun's core under its coil)."""
    th = np.linspace(0, 2 * math.pi, n_u + 1)
    ph = np.linspace(0.12, math.pi - 0.12, n_v)
    TH, PH = np.meshgrid(th, ph)
    d = np.stack([np.cos(TH) * np.sin(PH), np.sin(TH) * np.sin(PH), np.cos(PH)], axis=-1).reshape(-1, 3)
    P = c + d * R
    N = _unit(d / R)
    tang = _unit(np.cross(N, np.array([0.0, 0.0, 1.0])) + 1e-6)
    u0 = (cell * CELL_PX + 2.0) / ATLAS_W + 1.0
    du = (CELL_PX - 4.0) / ATLAS_W
    UV = np.stack([u0 + du * (TH.ravel() / (2 * math.pi)), PH.ravel() / math.pi], axis=1)
    UV2 = np.stack([np.full(len(P), 0.5), np.ones(len(P))], axis=1)
    COL = np.stack([np.full(len(P), rng.random()), np.zeros(len(P)), np.full(len(P), layer), np.ones(len(P))], axis=1)
    tris = []
    w = n_u + 1
    for i in range(n_v - 1):
        for j in range(n_u):
            a, bb, cc, dd = i * w + j, i * w + j + 1, (i + 1) * w + j, (i + 1) * w + j + 1
            tris += [[a, cc, bb], [bb, cc, dd]]
    b.add(P, N, tang, UV, UV2, COL, np.array(tris))


# ----------------------------------------------------------------------------------------------
# guides: many locks combed at once
# ----------------------------------------------------------------------------------------------

def comb_many(head, P0: np.ndarray, flow, length: np.ndarray, off0: np.ndarray, lift: np.ndarray,
              release_z: float, s: float, body=None, twist: Optional[np.ndarray] = None, cov=None,
              spill: float = 0.0, sinks: Sequence[np.ndarray] = (), step: float = 0.004,
              clear: Optional[float] = None, stop_below: Optional[Callable[[np.ndarray], np.ndarray]] = None
              ) -> List[np.ndarray]:
    """cloth.comb for many locks at once, step by step together: above `release_z` a lock hugs
    the skull at its own offset (off0 + lift * u^1.6), below it hangs, kept off the head and the
    body. A lock stops near a sink, where it leaves the covered scalp by more than `spill`
    (above the release), or where its step jumps (a projection off a degenerate gradient)."""
    N = len(P0)
    if N == 0:
        return []
    # a start the projection onto the scalp threw off (a degenerate gradient flings a point
    # kilometres) is no lock at all
    P0 = np.asarray(P0, float)
    sane = np.all(np.isfinite(P0), axis=1) & (np.abs(head.eval(np.nan_to_num(P0)) - off0) < 0.004 * s)
    n_steps = np.maximum(2, (np.asarray(length) / step).astype(int))
    M = int(n_steps.max())
    pts = np.full((N, M + 1, 3), np.nan)
    pts[:, 0] = P0
    p = np.array(P0, float)
    alive = np.ones(N, bool)
    hanging = p[:, 2] < release_z
    for i in range(M):
        act = alive & (i < n_steps)
        if not act.any():
            break
        idx = np.nonzero(act)[0]
        pa = p[idx]
        u = (i + 1) / n_steps[idx]
        f = flow(pa)
        if twist is not None:
            f = np.einsum("nij,nj->ni", twist[idx], f)
        o = off0[idx] + lift[idx] * u ** 1.6
        h = hanging[idx]
        q = np.empty_like(pa)
        hi = ~h
        if hi.any():
            nrm = head.gradient(pa[hi])
            ft = f[hi] - nrm * np.sum(f[hi] * nrm, axis=1, keepdims=True)
            small = np.linalg.norm(ft, axis=1) < 1e-6
            if small.any():
                ft[small] = DOWN - nrm[small] * (nrm[small] @ DOWN)[:, None]
            qh = pa[hi] + _unit(ft) * step
            qh = cloth._onto(head, qh, o[hi], iters=2)
            q[hi] = qh
        if h.any():
            qq = pa[h] + _unit(0.22 * f[h] + DOWN) * step
            oh = o[h]
            dh = head.eval(qq)
            need = dh < oh
            if need.any():
                qq[need] += head.gradient(qq[need]) * (oh[need] - dh[need])[:, None]
            if body is not None:
                c = clear if clear is not None else 0.008 * s + 0.5 * oh
                c = np.broadcast_to(c, (len(qq),))
                db = body.eval(qq)
                need = db < c
                if need.any():
                    qq[need] += body.gradient(qq[need]) * np.minimum(c[need] - db[need], 2.0 * step)[:, None]
            q[h] = qq
        bad = ~np.all(np.isfinite(q), axis=1) | (np.linalg.norm(q - pa, axis=1) > 4.0 * step)
        stop = bad.copy()
        for k_ in sinks:
            stop |= np.linalg.norm(q - k_, axis=1) < 0.018 * s
        if cov is not None:
            above = q[:, 2] >= release_z
            cq = cov(np.where(np.isfinite(q), q, 0.0))
            stop |= above & (cq < -spill * s) & ~h
        if stop_below is not None:
            stop |= stop_below(np.where(np.isfinite(q), q, 0.0))
        good = ~stop
        gi = idx[good]
        pts[gi, i + 1] = q[good]
        p[gi] = q[good]
        hanging[gi] |= q[good][:, 2] < release_z
        alive[idx[stop]] = False
    return [row[~np.isnan(row[:, 0])] if ok else row[:0] for row, ok in zip(pts, sane)]


def curled_many(lines: List[np.ndarray], head, amp: np.ndarray, period: np.ndarray, phase: np.ndarray):
    return [cloth._curled(C, head, a, pr, ph) for C, a, pr, ph in zip(lines, amp, period, phase)]


def seed_weighted(head, L: dict, cov_fn, n: int, min_cov: float, rng, weight=None) -> np.ndarray:
    """About `n` points over the scalp inside the hairline, more of them where `weight` is higher."""
    if n <= 0:
        return np.zeros((0, 3))
    cand = cloth.seed_scalp(head, L, cov_fn, n * 4, min_cov, rng)
    if len(cand) == 0:
        return cand
    w = np.ones(len(cand)) if weight is None else np.maximum(weight(cand), 1e-3)
    k = min(n, len(cand))
    pick = rng.choice(len(cand), k, replace=False, p=w / w.sum())
    return cand[np.sort(pick)]


def _outward(head, C: np.ndarray, axis_c: np.ndarray, release_z: float, s: float) -> np.ndarray:
    """The hair mass's outward normal along a lock: off the skull while it lies on the head,
    away from the head's vertical axis where it hangs."""
    g = head.gradient(C)
    rad = C - axis_c
    rad[:, 2] = 0.0
    rad = _unit(rad + np.array([0.0, 1e-4, 0.0]))
    w = np.clip((release_z + 0.02 * s - C[:, 2]) / (0.05 * s), 0.0, 1.0)[:, None] if release_z > -1e8 \
        else np.zeros((len(C), 1))
    # far below the head the sampled field is a box's distance: trust the axis there
    far = np.clip((head.eval(C) - 0.02 * s) / (0.03 * s), 0.0, 1.0)[:, None]
    w = np.maximum(w, far)
    return _unit(g * (1.0 - w) + rad * w)


# ----------------------------------------------------------------------------------------------
# a head of hair
# ----------------------------------------------------------------------------------------------

@dataclass
class Layer:
    name: str
    seeds: float        # times the style's `seeds` (or a count when the style has none)
    off: float          # offset from the scalp as a fraction of `base`
    lift: float         # times the style's lift
    width: float        # card width, times the lock radius (x2 = the lock's diameter)
    length: float       # times the style's length
    kind: str           # atlas cells
    tip: float = 0.45   # tip width / root width
    twist: float = 0.35  # radians of random turn about the card's length


LAYERS = [
    Layer("inner", 1.25, 0.30, 0.25, 2.3, 0.92, "dense", tip=0.60, twist=0.20),
    Layer("mid", 1.10, 0.62, 0.70, 1.9, 1.00, "medium", tip=0.50),
    Layer("outer", 0.55, 0.95, 1.25, 1.3, 1.05, "wispy", tip=0.40, twist=0.55),
]
# styles cut close, with no locks of their own: short cards lying flat, in two layers
CLOSE_CARDS = {"cropped": (380, 0.022), "receding": (320, 0.020), "hood_friendly": (360, 0.034)}
# the close cuts worn under a hood: nothing may stand further off the scalp than the shell did
CLOSE = ("cropped", "hood_friendly", "shaven", "receding", "cropped_curls")
HANG_WIDEN = (0.9, 0.6, 0.2)   # how much wider each layer's cards grow where the hair hangs
SEG = 0.010          # a card's segment length on the head (m at 1.78)
SEG_HANG = 0.022     # ...and where it hangs


def _clear_ears(C: np.ndarray, L: dict, s: float, margin: float = 0.020) -> np.ndarray:
    """Hair falling past an ear lies over it, not on it: points closer than `margin` to the ear's
    room (bodylib.ear_clearance) are moved out from the ear, so the ear slider (which grows the
    ear under the hair) does not bring it through."""
    c = bodylib.ear_clearance(C, L, margin * s)
    if (c >= 0).all():
        return C
    C = C.copy()
    for sx in (1.0, -1.0):
        ec = L["ear_c"] * np.array([sx, 1.0, 1.0])
        near = (c < 0) & (np.sign(C[:, 0]) == sx)
        if near.any():
            d = C[near] - ec
            d[:, 2] *= 0.3
            C[near] = C[near] + _unit(d) * (-c[near])[:, None]
    return C


def _card_segments(C: np.ndarray, release_z: float, s: float, curl: bool) -> np.ndarray:
    if curl:
        return resample(C, 0.0060 * s, 2, 16)
    hang = (C[:, 2] < release_z).mean() if release_z > -1e8 else 0.0
    return resample(C, (SEG + (SEG_HANG - SEG) * hang) * s, 2, 16)


def build_hair_cards(skel: Skeleton, name: str, g: "cloth.Groom", body=None, hs=None, seed: int = 0,
                     max_off: Optional[float] = None) -> Tuple[Dict[str, np.ndarray], dict]:
    """The cards for one hair style: (arrays, report). `max_off` caps how far any card stands off
    the scalp (a close cut that must stay under a hood)."""
    s = cloth._s(skel)
    head = cloth._head_field(skel, hs)
    L = bodylib.head_landmarks(skel, hs)
    rng = np.random.default_rng(seed + 4747)

    def cov_all(P):
        return bodylib.scalp_field(P, skel, hs, g.front, g.sides, g.back, g.recede)

    if g.strip > 0.0:
        def cov(P):
            return np.minimum(cov_all(P), g.strip * s - np.abs(P[:, 0]))
    else:
        cov = cov_all
    flow = cloth.flow_field(g, L)
    sinks = cloth._sinks(g, L)
    sink = cloth._sink(g, L)
    release_z = L["chin_z"] + L["V"] * g.release if g.release > 0 else -1e9
    crown = cloth._crown(L)
    base = g.base * s
    b = Builder()
    report = {"layers": {}}
    hangs = g.release > 0 or g.extra in ("braid", "twin_braids", "tail")
    hang_top = L["nape_z"] if hangs else -1e9

    def sway_of(C):
        if not hangs:
            return np.zeros(len(C))
        return np.clip((hang_top - C[:, 2]) / (0.25 * s), 0.0, 1.0) ** 1.5

    # -- the cap -------------------------------------------------------------------------------
    rows, cols = 20, 40
    ph = np.radians(np.linspace(0.0, 128.0, rows))
    az = np.linspace(0.0, 2 * math.pi, cols)
    PH, AZ = np.meshgrid(ph, az, indexing="ij")
    # azimuth 0 at the back, so the seam where it wraps lies down the back of the head
    dirs = np.stack([np.sin(PH) * np.sin(AZ), np.sin(PH) * np.cos(AZ), np.cos(PH)], axis=-1).reshape(-1, 3)
    dirs[:cols] = [0.0, 0.0, 1.0]
    centre = np.array([0.0, L["skull_c"][1], L["skull_c"][2] - 0.01 * s])
    stubble = 0.52

    def density(P):
        d_all = _smooth((cov_all(P) + 0.005 * s) / (0.017 * s))
        if g.strip > 0.0:
            inner = _smooth((cov(P) + 0.004 * s) / (0.010 * s))
            d = np.maximum(inner, np.minimum(d_all, stubble))
        else:
            d = d_all
        if g.flow in ("side_part", "centre_part"):
            # the parting shows a line of scalp, in front of the crown
            px = g.part_x * s
            front = P[:, 1] < crown[1]
            d = d * (1.0 - 0.30 * np.exp(-0.5 * ((P[:, 0] - px) / (0.0022 * s)) ** 2) * front)
        return d

    R_uv = float(np.mean(L["skull_r"]))
    AZg = AZ.reshape(-1)
    PHg = PH.reshape(-1)
    # the cap's grain in metres over the scalp, from the grid itself (so the seam down the back
    # is a clean jump in u, not a smear across the whole tile)
    uv_all = np.stack([2.0 + AZg * R_uv * np.maximum(np.sin(PHg), 0.25) / CAP_TILE, PHg * R_uv / CAP_TILE], axis=1)
    off_cap = 0.0008 * s
    n_cap = _cap_indexed(b, head, centre, dirs, (rows, cols), density, flow, uv_all, off_cap)
    report["cap_tris"] = n_cap

    # -- the cards -----------------------------------------------------------------------------
    px = g.part_x * s

    def weight(P):
        w = np.ones(len(P))
        if g.flow in ("side_part", "centre_part"):
            w += 1.6 * np.exp(-0.5 * ((P[:, 0] - px) / (0.018 * s)) ** 2) * (P[:, 1] < crown[1] + 0.02 * s)
        w += 1.0 * np.exp(-0.5 * np.sum(((P - crown) / (0.035 * s)) ** 2, axis=1))
        return w

    lim = max_off if max_off is not None else 1e9
    guides_total = 0
    # a style whose locks keep their thickness to the ends (a full cut) keeps wider tips
    tip_k = float(np.clip(1.0 + 0.9 * (0.62 - g.taper), 0.8, 1.35))
    if g.seeds > 0:
        for li, lay in enumerate(LAYERS):
            # curls cost more segments a card: fewer of them, each wider
            n = int(round(g.seeds * lay.seeds * (0.72 if g.curl > 0.0 else 1.0)))
            starts = seed_weighted(head, L, cov, n, 0.004 * s, rng, weight)
            if len(starts) == 0:
                continue
            m = len(starts)
            length = rng.uniform(*g.length, m) * s * lay.length * rng.uniform(0.9, 1.08, m)
            off0 = np.minimum(np.full(m, base * lay.off), lim)
            lift = np.minimum(g.lift * s * lay.lift * rng.uniform(0.6, 1.3, m), np.maximum(lim - off0, 0.0))
            twist = None
            if g.jitter > 0:
                nr = head.gradient(starts)
                twist = np.stack([rig.rot_axis(nr[k], math.radians(rng.uniform(-g.jitter, g.jitter) * (1.2 if li == 2 else 1.0)))
                                  for k in range(m)])
            P0 = cloth._onto(head, starts, off0)
            lines = comb_many(head, P0, flow, length, off0, lift, release_z, s, body=body, twist=twist, cov=cov,
                              spill=g.spill, sinks=sinks, clear=cloth.HANG_CLEAR * s + 0.004 * s * li)
            if g.curl > 0.0:
                lines = curled_many(lines, head, g.curl * s * rng.uniform(0.8, 1.2, m),
                                    g.curl_period * s * rng.uniform(0.85, 1.15, m), rng.uniform(0, 2 * math.pi, m))
            r0 = g.radius * s
            kind = "wavy" if g.curl > 0.0 and lay.kind != "dense" else lay.kind
            count = 0
            for C in lines:
                if len(C) < 3:
                    continue
                Cs = _card_segments(C, release_z, s, g.curl > 0.0)
                if len(Cs) < 2:
                    continue
                Cs = _clear_ears(Cs, L, s)
                out = _outward(head, Cs, L["skull_c"], release_z, s)
                w = lay.width * r0 * rng.uniform(0.8, 1.2)
                cell = int(rng.choice(CELL_OF[kind]))
                # where it hangs, hair spreads round the shoulders and the back over a much wider
                # girth than the scalp's: the cards widen there so the mass stays closed
                widen = None
                if release_z > -1e8:
                    widen = 1.0 + HANG_WIDEN[li] * np.clip((release_z - Cs[:, 2]) / (0.06 * s), 0.0, 1.0)
                ribbon(b, Cs, out, w, w * lay.tip * tip_k,
                       cell, rng, layer=li / 2.0, sway=sway_of(Cs), twist=rng.uniform(-lay.twist, lay.twist),
                       widen=widen)
                count += 1
            report["layers"][lay.name] = count
            guides_total += count
    elif name in CLOSE_CARDS:
        n, ln = CLOSE_CARDS[name]
        for li, (frac, offk, kind, wk) in enumerate([(0.6, 0.35, "dense", 1.0), (0.4, 0.75, "medium", 0.8)]):
            m = int(n * frac)
            starts = seed_weighted(head, L, cov, m, 0.003 * s, rng, weight)
            m = len(starts)
            off0 = np.minimum(np.full(m, base * offk), lim)
            lift = np.minimum(np.full(m, 0.0008 * s * (li + 1)), np.maximum(lim - off0, 0.0))
            length = ln * s * rng.uniform(0.75, 1.2, m)
            P0 = cloth._onto(head, starts, off0)
            lines = comb_many(head, P0, flow, length, off0, lift, -1e9, s, cov=cov, spill=0.004, step=0.003)
            for C in lines:
                if len(C) < 3:
                    continue
                Cs = resample(C, 0.008 * s, 2, 6)
                out = _outward(head, Cs, L["skull_c"], -1e9, s)
                w = 0.013 * s * wk * rng.uniform(0.8, 1.2)
                ribbon(b, Cs, out, w, w * 0.55, int(rng.choice(CELL_OF[kind])), rng, layer=0.3 + 0.5 * li,
                       sway=np.zeros(len(Cs)), twist=rng.uniform(-0.15, 0.15))
                guides_total += 1
        report["layers"]["close"] = guides_total

    # -- the hairline: fine short cards just inside it, combed along the flow -------------------
    if g.seeds > 0 or name in CLOSE_CARDS:
        def near_line(P):
            c = cov(P)
            return np.where((c > 0.001 * s) & (c < 0.012 * s), 1.0, 1e-3)
        cand = cloth.seed_scalp(head, L, cov, 900, 0.001 * s, rng)
        cand = cand[(cov(cand) < 0.012 * s)] if len(cand) else cand
        # the front and the temples, where it is seen
        if len(cand):
            th = bodylib.head_angle(cand, L)
            cand = cand[th < 110.0]
        k = min(len(cand), 70)
        if k:
            starts = cand[rng.choice(len(cand), k, replace=False)]
            off0 = np.minimum(np.full(k, 0.0012 * s), lim)
            lines = comb_many(head, cloth._onto(head, starts, off0), flow, rng.uniform(0.014, 0.026, k) * s,
                              off0, np.minimum(np.full(k, 0.0012 * s), lim - off0), release_z, s, cov=cov,
                              spill=0.004, step=0.003)
            n_fine = 0
            for C in lines:
                if len(C) < 3:
                    continue
                Cs = resample(C, 0.007 * s, 2, 5)
                out = _outward(head, Cs, L["skull_c"], -1e9, s)
                w = 0.008 * s * rng.uniform(0.8, 1.2)
                ribbon(b, Cs, out, w, w * 0.6, CELL_OF["fine"][0], rng, layer=0.9, sway=np.zeros(len(Cs)),
                       twist=rng.uniform(-0.2, 0.2))
                n_fine += 1
            report["layers"]["hairline"] = n_fine

    # -- the extras ----------------------------------------------------------------------------
    if g.extra == "tail" and sink is not None:
        _tail(b, g, sink, head, body, s, rng, sway_of)
    if g.extra == "braid" and sink is not None:
        _braid(b, sink, body, head, L, s, rng, sway_of)
    if g.extra == "twin_braids":
        neck = float(skel.J["Neck"][2])
        for sx, k_ in zip((1.0, -1.0), sinks):
            over = [k_ + np.array([-0.002 * sx, -0.010, -0.045]) * s,
                    np.array([0.050 * sx * s, -0.026 * s, neck + 0.004 * s]),
                    np.array([0.066 * sx * s, -0.066 * s, neck - 0.070 * s]),
                    np.array([0.070 * sx * s, -0.110 * s, neck - 0.150 * s])]

            def clear(C, neck=neck):
                return 0.012 + (cloth.HANG_CLEAR - 0.012) * np.clip((neck + 0.010 * s - C[:, 2]) / (0.040 * s), 0.0, 1.0)
            _braid(b, k_, body, head, L, s, rng, sway_of, width=0.86, through=over, clear=clear)
    if g.extra in ("bun", "chignon") and sink is not None:
        _bun(b, sink, s, rng, size=1.0 if g.extra == "bun" else 1.18)
    if g.extra == "crown":
        arc, out = cloth._crown_arc(head, L, s, g.base * s + 0.0070 * s)
        _, lines = cloth._plait(arc, s, width=0.74, taper_to=0.80, out_hint=out)
        for C in lines:
            tube(b, resample(C, 0.009 * s, 2, 60), 0.0086 * s * 0.74, int(rng.choice(CELL_OF["dense"])), rng,
                 sides=5, layer=0.7, wraps=3.0)
        if sink is not None:
            _bun(b, sink, s, rng, size=0.95)
    report["cards"] = b.cards
    report["guides"] = guides_total
    arrays = b.arrays()
    report["tris"] = int(len(arrays["tris"])) if arrays else 0
    report["hangs"] = hangs
    return arrays, report


def _cap_indexed(b, surf, centre, dirs, shape, density, flow, uv_all, off) -> int:
    """The cap (`_cap_core`) with the grid's own UVs. Returns the triangles kept."""
    kept = _cap_core(surf, centre, dirs, shape, density, flow, off)
    if kept is None:
        return 0
    used, arrays = kept
    b.add(arrays["P"], arrays["N"], arrays["T"], uv_all[used], arrays["UV2"], arrays["COL"], arrays["tris"])
    return len(arrays["tris"])


def _cap_core(surf, centre, dirs, shape, density_fn, flow, off, reach: float = 0.25):
    """The base layer: rays out from `centre` (inside the surface) along a (rows, cols) grid of
    directions, the surface found along each (the first crossing, then halved down) and the cap
    stood `off` off it. Triangles with no density at any corner, or stretched across a gap where
    neighbouring rays found different surfaces, are dropped. Returns (the grid indices kept, their
    arrays), or None."""
    n = len(dirs)
    t_hit = np.full(n, np.nan)
    t = np.zeros(n)
    step = 0.002
    for _ in range(int(reach / step)):
        t = t + step
        d = surf.eval(centre + dirs * t[:, None])
        hit = np.isnan(t_hit) & (d > 0)
        t_hit[hit] = t[hit]
        if not np.isnan(t_hit).any():
            break
    ok = ~np.isnan(t_hit)
    lo = np.where(ok, t_hit - step, 0.0)
    hi = np.where(ok, t_hit, 0.0)
    for _ in range(14):
        mid = 0.5 * (lo + hi)
        outside = surf.eval(centre + dirs * mid[:, None]) > 0
        hi = np.where(outside, mid, hi)
        lo = np.where(outside, lo, mid)
    S = centre + dirs * (0.5 * (lo + hi))[:, None]
    nrm = surf.gradient(S)
    P = S + nrm * off
    dens = np.where(ok, density_fn(S), 0.0)
    rows, cols = shape
    idx = np.arange(n).reshape(rows, cols)
    a = idx[:-1, :-1].ravel()
    bb = idx[:-1, 1:].ravel()
    c = idx[1:, :-1].ravel()
    d = idx[1:, 1:].ravel()
    tris = np.concatenate([np.stack([a, c, bb], 1), np.stack([bb, c, d], 1)])
    keep = (dens[tris].max(axis=1) > 0.02) & ok[tris].all(axis=1)
    e = np.max(np.stack([np.linalg.norm(P[tris[:, i]] - P[tris[:, (i + 1) % 3]], axis=1) for i in range(3)], 1), 1)
    keep &= e < 0.035
    # the pole row is one point repeated: drop the degenerate halves there
    area = np.linalg.norm(np.cross(P[tris[:, 1]] - P[tris[:, 0]], P[tris[:, 2]] - P[tris[:, 0]]), axis=1)
    keep &= area > 1e-9
    tris = tris[keep]
    if not len(tris):
        return None
    used = np.unique(tris)
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    Pu, Nu, Du = P[used], nrm[used], dens[used]
    f = flow(Pu)
    tang = _unit(f - Nu * np.sum(f * Nu, axis=1, keepdims=True) + 1e-7)
    UV2 = np.stack([np.zeros(len(Pu)), Du], axis=1)
    COL = np.stack([np.full(len(Pu), 0.5), np.zeros(len(Pu)), np.zeros(len(Pu)), np.ones(len(Pu))], axis=1)
    return used, {"P": Pu, "N": Nu, "T": tang, "UV2": UV2, "COL": COL, "tris": remap[tris]}


def _braid(b, start, body, head, L, s, rng, sway_of, width: float = 1.0, through=None, clear=cloth.HANG_CLEAR):
    """A plait of three solid strands with a tie and a tuft of cards below it (cloth._braid_prims'
    own lines)."""
    _, lines = cloth._braid_prims(start, body, head, L, s, width=width, through=through, clear=clear)
    if not lines:
        return
    strands, tuft = lines[:3], lines[3]
    for C in strands:
        Cs = resample(C, 0.009 * s, 2, 60)
        u = np.linspace(0, 1, len(Cs))
        r = 0.0086 * s * width * (1.0 - 0.45 * u)
        tube(b, Cs, r, int(rng.choice(CELL_OF["dense"])), rng, sides=5, layer=0.7, sway=sway_of(Cs), wraps=4.0)
    # the tie, and the tuft below it as a few cards fanned round
    end = tuft[0]
    ax = _unit(tuft[-1] - tuft[0])
    ring = []
    side = _unit(np.cross(ax, np.array([0.0, -1.0, 0.0])) + 1e-9)
    bn = np.cross(ax, side)
    for k in range(9):
        a = 2 * math.pi * k / 9
        ring.append(end + (side * math.cos(a) + bn * math.sin(a)) * 0.0080 * s)
    ring.append(ring[0])
    tube(b, np.array(ring), 0.0030 * s, CELL_OF["dense"][0], rng, sides=4, layer=0.4, sway=sway_of(np.array(ring)))
    for k in range(6):
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        o = (side * math.cos(a) + bn * math.sin(a))
        C = np.array([end + o * 0.004 * s, end + ax * 0.022 * s * width + o * 0.007 * s,
                      end + ax * 0.048 * s * width * rng.uniform(0.85, 1.1) + o * 0.005 * s])
        C = resample(C, 0.008 * s, 2, 6)
        ribbon(b, C, np.repeat(o[None], len(C), 0), 0.013 * s * width, 0.006 * s, int(rng.choice(CELL_OF["medium"])),
               rng, layer=0.8, sway=sway_of(C))


def _bun(b, at, s, rng, size: float = 1.0):
    """A bun: a solid core and the coil wound over it (cloth._bun_prims' line)."""
    R = np.array([0.032, 0.027, 0.030]) * s * size
    ellipsoid_mesh(b, at, R * 0.86, int(rng.choice(CELL_OF["dense"])), rng)
    _, lines = cloth._bun_prims(at, s, size=size)
    C = resample(lines[0], 0.006 * s, 2, 90)
    tube(b, C, 0.0090 * s * size, int(rng.choice(CELL_OF["dense"])), rng, sides=6, layer=0.8, wraps=5.0)


def _tail(b, g, sink, head, body, s, rng, sway_of):
    """A tail: the tie, its gathered body as a solid tube, and cards hanging round it."""
    out = head.gradient(sink[None])[0]
    tie = sink + out * 0.012 * s
    side = _unit(np.cross(out, np.array([0.0, 0.0, 1.0])) + 1e-9)
    bn = np.cross(out, side)
    ring = [tie + (side * math.cos(a) + bn * math.sin(a)) * 0.0105 * s for a in np.linspace(0, 2 * math.pi, 11)]
    tube(b, np.array(ring), 0.0036 * s, CELL_OF["dense"][0], rng, sides=4, layer=0.4)
    centre = cloth.comb(head, tie + out * 0.010 * s, lambda P: np.tile(np.array([0.0, 0.30, -1.0]), (len(P), 1)),
                        g.tail_len * s, lambda u: 0.020 * s, release_z=1e9, s=s, body=body, step=0.005,
                        clear=cloth.HANG_CLEAR * s + 0.010 * s)
    if len(centre) < 4:
        return
    # the gathered root, drawn back from the tie into the tail
    root = np.array([tie - out * 0.004 * s, tie + out * 0.006 * s, centre[min(3, len(centre) - 1)]])
    tube(b, resample(root, 0.005 * s, 2, 6), np.array([0.014, 0.015, 0.013]) * s, CELL_OF["dense"][1], rng,
         sides=7, layer=0.5)
    Cs = resample(centre, 0.012 * s, 2, 30)
    u = np.linspace(0.0, 1.0, len(Cs))
    radii = (0.012 + 0.010 * np.sin(np.pi * np.clip(u * 1.6, 0.0, 1.0)) * (1.0 - 0.3 * u) - 0.006 * u ** 2) * s
    tube(b, Cs, radii * 0.70, int(rng.choice(CELL_OF["dense"])), rng, sides=6, layer=0.3, sway=sway_of(Cs), wraps=2.0)
    seg = np.diff(Cs, axis=0)
    tang = _unit(np.concatenate([seg, seg[-1:]], axis=0))
    sd = _unit(np.cross(tang, np.array([0.0, 0.0, 1.0])) + 1e-9)
    bk = _unit(np.cross(sd, tang))
    for i in range(22):
        ang = 2.0 * math.pi * i / 22.0 + rng.uniform(-0.2, 0.2)
        spread = rng.uniform(0.75, 1.05)
        o = np.cos(ang) * sd + np.sin(ang) * bk
        end = int(len(Cs) * rng.uniform(0.7, 1.0))
        C = (Cs + o * (radii[:, None] * spread))[:max(end, 3)]
        if g.curl > 0.0:
            C = cloth._curled(C, head, g.curl * s, g.curl_period * s, rng.uniform(0.0, 2.0 * math.pi))
        w = 0.022 * s * rng.uniform(0.8, 1.15)
        kind = "wispy" if i % 3 == 0 else "medium"
        ribbon(b, C, o[:len(C)], w, w * 0.4, int(rng.choice(CELL_OF[kind])), rng,
               layer=0.6 + 0.4 * (i % 3 == 0), sway=sway_of(C), twist=rng.uniform(-0.3, 0.3))


# ----------------------------------------------------------------------------------------------
# beards
# ----------------------------------------------------------------------------------------------

def build_beard_cards(skel: Skeleton, name: str, st: "cloth.BeardStyle", hs=None, seed: int = 0, body=None
                      ) -> Tuple[Dict[str, np.ndarray], dict]:
    s = cloth._s(skel)
    head = cloth._head_field(skel, hs)
    L = bodylib.head_landmarks(skel, hs)
    rng = np.random.default_rng(seed + 9047)
    if st.region == "moustache":
        def cov(P):
            return bodylib.moustache_field(P, skel, hs)
    elif st.region == "chops":
        def cov(P):
            c = bodylib.beard_field(P, None, skel, hs, moustache=False)
            return np.minimum(c, np.abs(P[:, 0]) - 0.030 * s)
    else:
        chin_only = st.region == "chin"

        def cov(P):
            return bodylib.beard_field(P, None, skel, hs, moustache=True, chin_only=chin_only)
    if st.region == "moustache":
        mid = np.array([0.0, L["face_y"], L["mouth_z"] + 0.02 * s])

        def flow(P):
            v = P - mid
            v[:, 2] = -0.9 * np.abs(v[:, 0]) / 0.03 - 0.4
            return cloth._unit_rows(v)
    else:
        def flow(P):
            v = np.stack([-0.35 * P[:, 0] / 0.05, np.full(len(P), -0.25), np.full(len(P), -1.0)], axis=1)
            return cloth._unit_rows(v)
    surf = head
    mass_sc = None
    if st.mass > 0:
        m = st.mass * s
        top = np.array([0.0, L["face_y"] + 0.016 * s, L["chin_z"] + 0.006 * s])
        low = np.array([0.0, L["face_y"] + 0.022 * s, L["chin_z"] - max(st.hang * 0.80, 0.02) * s])
        gon = L["gonion"]
        mass_sc = sdf.Scene()
        mass_sc.union(sdf.ellipsoid(top, [m * 1.60, m * 0.80, m * 0.80], k=0.010 * s))
        for sx in (1, -1):
            dx = np.array([sx * m * 0.45, 0.0, 0.0])
            mass_sc.union(sdf.round_cone(top + dx, low + dx * 0.25, m * 0.80, m * 0.30, k=0.012 * s), k=0.012 * s)
            gg = gon * np.array([sx, 1.0, 1.0]) + np.array([0.0, -0.004 * s, -0.004 * s])
            mass_sc.union(sdf.round_cone(top + dx * 1.2, gg, m * 0.62, m * 0.34, k=0.012 * s), k=0.012 * s)
        # cards lie on the mass's surface a little inside it: it is hair, not a solid
        surf = cloth._MinField(head, _Shrunk(mass_sc, 0.004 * s))
    b = Builder()
    report = {"layers": {}}
    base = st.base * s

    def density(P):
        c = cov(P)
        d = _smooth((c + 0.003 * s) / (0.014 * s))
        if mass_sc is not None:
            d = np.maximum(d, _smooth((0.004 * s - mass_sc.eval(P)) / (0.004 * s)))
        return d

    # -- the cap over the beard line and the mass ------------------------------------------------
    rows, cols = 18, 34
    el = np.radians(np.linspace(-88.0, 30.0, rows))
    az = np.radians(np.linspace(-118.0, 118.0, cols))
    EL, AZ = np.meshgrid(el, az, indexing="ij")
    dirs = np.stack([np.sin(AZ) * np.cos(EL), -np.cos(AZ) * np.cos(EL), np.sin(EL)], axis=-1).reshape(-1, 3)
    centre = np.array([0.0, L["face_y"] + 0.055 * s, L["mouth_z"] + 0.004 * s])
    R_uv = 0.07 * s
    uv_all = np.stack([2.0 + AZ.ravel() * R_uv / CAP_TILE, EL.ravel() * R_uv / CAP_TILE], axis=1)
    n_cap = _cap_indexed(b, surf, centre, dirs, (rows, cols), density, flow, uv_all, 0.0006 * s)
    report["cap_tris"] = n_cap

    # -- cards -----------------------------------------------------------------------------------
    total = 0
    if st.region == "moustache":
        n = max(st.seeds, 10) * 3
        # the lip is a small target for points thrown over the whole lower face
        cand = cloth._face_points(head, L, rng, n * 80)
        cand = cand[cov(cand) > 0.0015 * s]
        if len(cand) > n:
            cand = cand[rng.choice(len(cand), n, replace=False)]
        for li, (kind, offk, wk) in enumerate([("dense", 0.35, 2.6), ("medium", 0.75, 2.0), ("fine", 1.0, 1.3)]):
            pick = cand[li::3]
            m = len(pick)
            if not m:
                continue
            length = rng.uniform(*st.length, m) * s
            off0 = np.full(m, base * offk)
            P0 = cloth._onto(head, pick, off0)
            lines = comb_many(head, P0, flow, length, off0, np.full(m, 0.0012 * s), -1e9, s, step=0.0025)
            for C in lines:
                if len(C) < 3:
                    continue
                Cs = resample(C, 0.006 * s, 2, 8)
                out = _unit(head.gradient(Cs))
                w = st.radius * s * wk * rng.uniform(0.85, 1.15)
                ribbon(b, Cs, out, w, w * 0.35, int(rng.choice(CELL_OF[kind])), rng, layer=li / 2.0,
                       sway=np.zeros(len(Cs)), twist=rng.uniform(-0.25, 0.25))
                total += 1
    else:
        n_face = int(st.clumps * (0.55 if mass_sc is not None else 1.0) * 2.4)
        cand = cloth._face_points(head, L, rng, n_face * 14)
        cand = cand[cov(cand) > 0.0015 * s]
        mouth = (np.abs(cand[:, 0]) < L["mouth_w"] * 1.35) & (cand[:, 2] > L["mouth_z"] - 0.014 * s)
        cand = cand[~mouth]
        if len(cand) > n_face:
            cand = cand[rng.choice(len(cand), n_face, replace=False)]
        seeds_all = [cand]
        if mass_sc is not None:
            n_mass = int(st.clumps * 0.45 * 2.6)
            c0 = np.array([0.0, L["face_y"] + 0.018 * s, L["chin_z"] - 0.010 * s])
            d = cloth._unit_rows(rng.normal(0.0, 1.0, (n_mass * 8, 3)) * np.array([1.0, 0.5, 0.9])
                                 + np.array([0.0, -0.9, -0.2]))
            mc = cloth._onto(surf, c0 + d * 0.06 * s, 0.0, iters=6)
            ok = (mc[:, 2] < L["mouth_z"] - 0.010 * s) & (mc[:, 1] < c0[1] + 0.010 * s)
            mc = mc[ok & np.all(np.isfinite(mc), axis=1)]
            if len(mc) > n_mass:
                mc = mc[rng.choice(len(mc), n_mass, replace=False)]
            seeds_all.append(mc)
        S0 = np.concatenate(seeds_all, axis=0)
        rng.shuffle(S0)
        LAY = [("dense", 0.30, 2.5, 1.0), ("medium", 0.65, 2.0, 1.05), ("wavy", 0.95, 1.5, 1.1)]
        for li, (kind, offk, wk, lk) in enumerate(LAY):
            pick = S0[li::3]
            m = len(pick)
            if not m:
                continue
            length = rng.uniform(*st.clump_len, m) * s * lk * 1.25
            off0 = np.full(m, st.clump_r * s * offk)
            P0 = cloth._onto(surf, pick, off0)
            lines = comb_many(surf, P0, flow, length, off0, np.full(m, 0.0008 * s), -1e9, s, step=0.0025)
            for C in lines:
                if len(C) < 3:
                    continue
                Cs = resample(C, 0.006 * s, 2, 10)
                out = _unit(surf.gradient(Cs))
                w = st.clump_r * s * wk * rng.uniform(0.85, 1.15)
                ribbon(b, Cs, out, w, w * 0.30, int(rng.choice(CELL_OF[kind])), rng, layer=li / 2.0,
                       sway=np.zeros(len(Cs)), twist=rng.uniform(-0.3, 0.3))
                total += 1
        if mass_sc is not None:
            # the ends: wisps from the bottom of the mass, hanging a little free of it
            low_z = L["chin_z"] - max(st.hang * 0.80, 0.02) * s
            k = 26
            c0 = np.array([0.0, L["face_y"] + 0.020 * s, low_z + 0.012 * s])
            d = cloth._unit_rows(rng.normal(0, 1, (k * 6, 3)) * np.array([1.0, 0.6, 0.3]) + np.array([0, -0.5, -1.0]))
            mc = cloth._onto(surf, c0 + d * 0.03 * s, 0.002 * s, iters=6)
            mc = mc[np.all(np.isfinite(mc), axis=1) & (mc[:, 2] < low_z + 0.03 * s)]
            if len(mc) > k:
                mc = mc[rng.choice(len(mc), k, replace=False)]
            m = len(mc)
            if m:
                lines = comb_many(surf, mc, flow, rng.uniform(0.02, 0.035, m) * s + st.hang * 0.3 * s,
                                  np.full(m, 0.002 * s), np.full(m, 0.001 * s), low_z + 0.01 * s, s, body=body,
                                  step=0.003, clear=cloth.HANG_CLEAR * s)
                for C in lines:
                    if len(C) < 3:
                        continue
                    Cs = resample(C, 0.008 * s, 2, 8)
                    out = _outward(head, Cs, np.array([0.0, L["face_y"] + 0.03 * s, 0.0]), -1e9, s)
                    w = 0.010 * s * rng.uniform(0.8, 1.2)
                    ribbon(b, Cs, out, w, w * 0.3, int(rng.choice(CELL_OF["wispy"])), rng, layer=1.0,
                           sway=np.zeros(len(Cs)), twist=rng.uniform(-0.4, 0.4))
                    total += 1
    report["cards"] = total
    arrays = b.arrays()
    report["tris"] = int(len(arrays["tris"])) if arrays else 0
    report["hangs"] = False
    return arrays, report


class _Shrunk:
    """A scene's field offset inward by `d` (its surface pulled in)."""

    def __init__(self, sc, d):
        self.sc, self.d = sc, d

    def eval(self, P):
        return self.sc.eval(np.asarray(P, float)) + self.d


# ----------------------------------------------------------------------------------------------
# into the part's GLB
# ----------------------------------------------------------------------------------------------

def to_gltf(v: np.ndarray) -> np.ndarray:
    return np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1)


def skin_weights(V: np.ndarray, weight_fn=None) -> np.ndarray:
    """(n, len(DEFORM_NAMES)) weights: rigid to the head, or the hanging hair's own."""
    bones = list(rig.DEFORM_NAMES)
    if weight_fn is None:
        W = np.zeros((len(V), len(bones)))
        W[:, bones.index("Head")] = 1.0
        return W
    return bodylib.limit_influences(np.asarray(weight_fn(V), float))


def attach_cards(path: str, name: str, arrays: Dict[str, np.ndarray], W: np.ndarray,
                 targets: Optional[Dict[str, np.ndarray]] = None) -> int:
    """Write `<name>_cards` into the part's GLB beside its shell (replacing an earlier one): one
    primitive with every attribute, skinned by `W` (vertices x DEFORM_NAMES), with `targets`
    (name -> forge-space position deltas) as sparse morph targets. Returns its triangle count."""
    from . import glb
    gltf, bin_chunk = glb.read_glb(path)
    mesh_name = name + "_cards"
    # an earlier build's cards come out first
    for ni, nd in enumerate(gltf["nodes"]):
        if nd.get("name") == mesh_name and "mesh" in nd:
            old = nd["mesh"]
            gltf["meshes"][old] = {"name": "_dropped", "primitives": []}
            for other in gltf["nodes"]:
                if other.get("children") and ni in other["children"]:
                    other["children"] = [c for c in other["children"] if c != ni]
            nd.pop("mesh", None)
            nd.pop("skin", None)
            nd["name"] = "_dropped"
    gltf, bin_chunk = _drop_marked(gltf, bin_chunk)
    skin = gltf["skins"][0]
    joint_names = [gltf["nodes"][j]["name"] for j in skin["joints"]]
    bones = list(rig.DEFORM_NAMES)
    col_of = np.array([joint_names.index(bn) for bn in bones])
    order = np.argsort(-W, axis=1)[:, :4]
    wv = np.take_along_axis(W, order, axis=1)
    wv = wv / np.maximum(wv.sum(axis=1, keepdims=True), 1e-9)
    jv = col_of[order]
    jv = np.where(wv > 0, jv, 0)
    out = bytearray(bin_chunk)

    def view(data: bytes, target=34962):
        return glb._append_view(gltf, out, data, target)

    def acc(arr, comp, kind, normalized=False, bounds=False, target=34962):
        a = np.ascontiguousarray(arr)
        v = view(a.tobytes(), target)
        d = {"bufferView": v, "componentType": comp, "count": int(a.shape[0]), "type": kind}
        if normalized:
            d["normalized"] = True
        if bounds:
            d["min"] = [float(x) for x in a.min(axis=0)]
            d["max"] = [float(x) for x in a.max(axis=0)]
        gltf["accessors"].append(d)
        return len(gltf["accessors"]) - 1

    P = to_gltf(arrays["P"]).astype("<f4")
    N = to_gltf(arrays["N"]).astype("<f4")
    T = np.concatenate([to_gltf(arrays["T"]), np.ones((len(P), 1))], axis=1).astype("<f4")
    attrs = {
        "POSITION": acc(P, 5126, "VEC3", bounds=True),
        "NORMAL": acc(N, 5126, "VEC3"),
        "TANGENT": acc(T, 5126, "VEC4"),
        "TEXCOORD_0": acc(arrays["UV"].astype("<f4"), 5126, "VEC2"),
        "TEXCOORD_1": acc(arrays["UV2"].astype("<f4"), 5126, "VEC2"),
        "COLOR_0": acc(arrays["COL"].astype("<f4"), 5126, "VEC4"),
        "JOINTS_0": acc(jv.astype("u1"), 5121, "VEC4"),
        "WEIGHTS_0": acc(wv.astype("<f4"), 5126, "VEC4"),
    }
    tris = arrays["tris"].reshape(-1)
    if len(P) < 65535:
        ind = acc(tris.astype("<u2").reshape(-1, 1), 5123, "SCALAR", target=34963)
    else:
        ind = acc(tris.astype("<u4").reshape(-1, 1), 5125, "SCALAR", target=34963)
    gltf["accessors"][ind]["type"] = "SCALAR"
    mats = gltf.setdefault("materials", [])
    mat_name = "WM_%s_cards" % name
    mi = next((i for i, m in enumerate(mats) if m.get("name") == mat_name), None)
    if mi is None:
        mats.append({"name": mat_name, "doubleSided": True, "alphaMode": "MASK", "alphaCutoff": 0.5,
                     "pbrMetallicRoughness": {"baseColorFactor": [0.40, 0.28, 0.19, 1.0],
                                              "metallicFactor": 0.0, "roughnessFactor": 0.7}})
        mi = len(mats) - 1
    gltf["meshes"].append({"name": mesh_name, "primitives": [{"attributes": attrs, "indices": ind,
                                                               "material": mi, "mode": 4}]})
    mesh_i = len(gltf["meshes"]) - 1
    gltf["nodes"].append({"name": mesh_name, "mesh": mesh_i, "skin": 0})
    node_i = len(gltf["nodes"]) - 1
    arm = next(i for i, nd in enumerate(gltf["nodes"]) if nd.get("name") == "Armature")
    gltf["nodes"][arm].setdefault("children", []).insert(1, node_i)
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    bin_chunk = bytes(out)
    for tname, D in (targets or {}).items():
        bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, mesh_i, tname, to_gltf(D))
    bin_chunk = glb.compact(gltf, bin_chunk)
    glb.write_glb(path, gltf, bin_chunk)
    return int(len(tris) // 3)


def _drop_marked(gltf: dict, bin_chunk: bytes):
    """Take out the nodes and meshes an earlier `attach_cards` marked `_dropped`, renumbering."""
    from . import glb
    nodes = gltf["nodes"]
    keep_n = [i for i, nd in enumerate(nodes) if nd.get("name") != "_dropped"]
    if len(keep_n) == len(nodes):
        return gltf, bin_chunk
    nmap = {o: i for i, o in enumerate(keep_n)}
    meshes = gltf["meshes"]
    keep_m = [i for i, m in enumerate(meshes) if m.get("name") != "_dropped"]
    mmap = {o: i for i, o in enumerate(keep_m)}
    new_nodes = []
    for o in keep_n:
        nd = dict(nodes[o])
        if "children" in nd:
            nd["children"] = [nmap[c] for c in nd["children"] if c in nmap]
        if "mesh" in nd:
            nd["mesh"] = mmap[nd["mesh"]]
        new_nodes.append(nd)
    gltf["nodes"] = new_nodes
    gltf["meshes"] = [meshes[i] for i in keep_m]
    for sk in gltf.get("skins", []):
        sk["joints"] = [nmap[j] for j in sk["joints"]]
        if "skeleton" in sk:
            sk["skeleton"] = nmap[sk["skeleton"]]
    for sc in gltf.get("scenes", []):
        sc["nodes"] = [nmap[n] for n in sc["nodes"] if n in nmap]
    return gltf, glb.compact(gltf, bin_chunk)
