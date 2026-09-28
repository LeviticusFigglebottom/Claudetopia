"""The face's sliders as morph targets on every head (triage 39). Pure Python and numpy.

A head is one of eight presets, each built again as a woman's (`<face>_f`). On top of that every
head now carries a morph target per slider -- jaw width, chin, cheekbones, nose, eyes, brow, lips,
the length of the face, the ears -- and one for the years (`face_age`). The game sets each to the
person's value between -1 and 1 (age 0..1): `HumanoidModel._apply_fits`, `CharacterAppearance.face`.

How a target is made, for one head:

* a **warp**: a smooth displacement laid on the finished mesh round the part it moves (the eye
  scaled about its centre, the brow lifted, the chin let down), so the painted skin goes with
  the geometry -- the lips' colour stays on the lips when the mouth is widened;
* and, for the sliders the head's own builder has a knob for (`HeadStyle`), a **projection** onto
  the head as the builder makes it with that knob turned: every vertex keeps the distance it had
  from its own field, measured now from the new one, so a hump grows on the bridge of the nose or
  a ridge over the eyes the way the builder would have made it, not as a bump laid over the old.

Nothing moves above the brow or behind the ears but the ears themselves: the vault is the same
for every face and every slider, because hair, hoods and helms are built once against it
(`vault_moves` measures it; tests/test_face_morphs checks it). A part that lies on the face
(a beard, the hair's sideburns and fringe, a hood's opening) takes the same targets, carried
over from the nearest skin (`transfer`), so it goes with the face it is worn on.

The targets are stored sparse (only the vertices a slider moves), with normals, which is what the
glTF exporter writes for the asymmetry targets the heads already carry."""
from __future__ import annotations

import math
from dataclasses import replace
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig, body as bodylib
from .rig import Skeleton

PREFIX = "face_"
# The sliders, in the order the Naming groups them. Each runs -1..1 in the game; 0 is the head as
# built. Their names are the record's keys (CharacterAppearance.FACE_SLIDERS says the same).
SLIDERS: List[str] = [
    "jaw_width", "chin_length", "chin_projection",
    "cheekbones", "cheek_fullness",
    "nose_length", "nose_width", "nose_bridge",
    "eye_size", "eye_spacing", "eye_tilt",
    "brow_height", "brow_ridge",
    "lip_fullness", "mouth_width",
    "face_length", "ear_size",
]
AGE = "age"
TARGETS: List[str] = SLIDERS + [AGE]


def target_name(slider: str) -> str:
    return PREFIX + slider


# -- helpers --------------------------------------------------------------------------------------

def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def _gauss(V: np.ndarray, c, r) -> np.ndarray:
    return np.exp(-0.5 * np.sum(((V - np.asarray(c, float)) / np.asarray(r, float)) ** 2, axis=1))


def _ramp(d: np.ndarray, full: float, zero: float) -> np.ndarray:
    """1 up to `full`, easing to 0 at `zero` (distances)."""
    return 1.0 - _smooth((d - full) / max(zero - full, 1e-9))


def _theta(V: np.ndarray, L: dict) -> np.ndarray:
    return bodylib.head_angle(V, L)


def face_mask(V: np.ndarray, L: dict) -> np.ndarray:
    """1 over the face, from under the chin to a little above the brow and round to in front of the
    ears; 0 over the vault, behind the ears and down the neck, where nothing may move."""
    s, z = L["s"], V[:, 2]
    top = 1.0 - _smooth((z - (L["brow_z"] + 0.014 * s)) / (0.016 * s))
    low = _smooth((z - (L["chin_z"] - 0.046 * s)) / (0.030 * s))
    side = 1.0 - _smooth((_theta(V, L) - 74.0) / 22.0)
    return top * low * side


def ear_mask(V: np.ndarray, L: dict) -> np.ndarray:
    """1 over each ear and the skin just round it, 0 a finger's width away."""
    s = L["s"]
    out = np.zeros(len(V))
    for sx in (1.0, -1.0):
        ec = L["ear_c"] * np.array([sx, 1.0, 1.0])
        rad = np.array([0.020 * s, 0.026 * s, L["ear_r"][2] * 1.25])
        k = np.linalg.norm((V - ec) / rad, axis=1)
        out = np.maximum(out, 1.0 - _smooth((k - 0.85) / 0.5))
    return out


def _normals(V: np.ndarray, T: np.ndarray) -> np.ndarray:
    """Area-weighted vertex normals, welded across the texture's seams (vertices at one place
    share one normal, as the smooth-shaded head does)."""
    key = np.round(V / 1e-5).astype(np.int64)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.ravel()
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    acc = np.zeros((weld.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, weld[T[:, k]], fn)
    n = acc[weld]
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


class _Field:
    """A head's field, evaluated where it is asked, with a gradient."""

    def __init__(self, scene, eps: float = 0.0006):
        self.sc, self.eps = scene, eps

    def eval(self, P):
        return self.sc.eval(np.asarray(P, float))

    def gradient(self, P, d=None):
        # central differences: a one-sided step leans one way, and the two sides of a face that
        # should move as mirrors of each other did not (an ear 4 mm off its twin)
        P = np.asarray(P, float)
        g = np.empty_like(P)
        for i in range(3):
            o = np.zeros(3)
            o[i] = self.eps
            g[:, i] = (self.eval(P + o) - self.eval(P - o)) / (2.0 * self.eps)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def _project(V: np.ndarray, P: np.ndarray, base: _Field, new: _Field, iters: int = 3,
             max_step: float = 0.006) -> np.ndarray:
    """Each vertex (now at P) stood off `new` by the distance V had from `base`."""
    keep = base.eval(V)
    P = P.copy()
    for _ in range(iters):
        d = new.eval(P)
        step = np.clip(d - keep, -max_step, max_step)
        P = P - new.gradient(P, d) * step[:, None]
    return P


# -- the sliders ------------------------------------------------------------------------------------
#
# Each returns the +1 target's move of the head's vertices V (and of each eye's), in metres, in the
# forge's frame (Z up, -Y forward). A slider at -1 is the same move reversed: the game sets the
# weight negative, and every warp here is linear in its amount, so -1 is as much the other way.

class _Head:
    """What the sliders are computed against: the head's skeleton, style, landmarks and mesh."""

    def __init__(self, skel: Skeleton, hs: Optional[bodylib.HeadStyle], V: np.ndarray, T: np.ndarray):
        self.skel, self.hs = skel, hs or bodylib.HeadStyle()
        self.L = bodylib.head_landmarks(skel, self.hs)
        self.s = float(self.L["s"])
        self.V, self.T = np.asarray(V, float), np.asarray(T, int)
        self.N = _normals(self.V, self.T)
        self.face = face_mask(self.V, self.L)
        self.ears = ear_mask(self.V, self.L)
        self._base: Optional[_Field] = None

    @property
    def base(self) -> _Field:
        if self._base is None:
            self._base = _Field(bodylib.head_scene(self.skel, self.hs))
        return self._base

    def styled(self, **knobs) -> _Field:
        """The head as its builder makes it with some of its style's knobs turned by `knobs`."""
        hs = replace(self.hs, **{k: getattr(self.hs, k) + v for k, v in knobs.items()})
        return _Field(bodylib.head_scene(self.skel, hs))

    def aged(self, years: float, **knobs) -> _Field:
        skel = _with_props(self.skel, replace(self.skel.props, age=years))
        hs = replace(self.hs, **{k: getattr(self.hs, k) + v for k, v in knobs.items()})
        return _Field(bodylib.head_scene(skel, hs))

    def project(self, new: _Field, mask: np.ndarray, warp: Optional[np.ndarray] = None) -> np.ndarray:
        """The move onto `new`, only where `mask` > 0 (and faded by it), after `warp`."""
        V = self.V
        move = np.zeros_like(V) if warp is None else warp.copy()
        sel = mask > 1e-3
        if np.any(sel):
            P = _project(V[sel], V[sel] + move[sel], self.base, new)
            move[sel] = move[sel] + (P - (V[sel] + move[sel])) * mask[sel, None]
        return move

    def eye_centres(self) -> List[Tuple[float, np.ndarray]]:
        L = self.L
        return [(sx, np.array([sx * L["eye_x"], L["eye_c_y"], L["eye_z"]])) for sx in (1.0, -1.0)]


def _with_props(skel: Skeleton, props: rig.Proportions) -> Skeleton:
    """The same joints, other proportions for the mesh (age is a mesh-only knob for a head)."""
    out = Skeleton.__new__(Skeleton)
    out.__dict__.update(skel.__dict__)
    out.props = props
    return out


def _eye_profile(V: np.ndarray, c: np.ndarray, er: float, full: float, zero: float) -> np.ndarray:
    return _ramp(np.linalg.norm(V - c, axis=1), full * er, zero * er)


def _jaw_width(h: _Head):
    return h.project(h.styled(jaw_width=0.15), h.face), None


def _chin_length(h: _Head):
    L, s, V = h.L, h.s, h.V
    x, z = V[:, 0], V[:, 2]
    # from nothing at the mouth to all of it at the point of the chin, and under the chin back to
    # nothing at the throat; the width of the chin and the front of the jaw, not its angle
    down = _smooth((L["mouth_z"] - 0.004 * s - z) / (L["mouth_z"] - L["chin_z"] - 0.010 * s))
    under = 1.0 - _smooth((L["chin_z"] - 0.006 * s - z) / (0.036 * s))
    wide = _ramp(np.abs(x), 0.020 * s, 0.056 * s)
    w = down * under * wide * (1.0 - _smooth((_theta(V, L) - 60.0) / 30.0))
    return np.outer(w, [0.0, -0.0012 * s, -0.0075 * s]), None


def _chin_projection(h: _Head):
    L, s, V = h.L, h.s, h.V
    c = [0.0, L["face_y"], L["chin_z"] + 0.016 * s]
    w = _gauss(V, c, [0.020 * s, 0.040 * s, 0.020 * s]) * (V[:, 1] < L["face_y"] + 0.040 * s)
    return np.outer(w, [0.0, -0.0065 * s, 0.0010 * s]), None


def _cheekbones(h: _Head):
    L, s, V = h.L, h.s, h.V
    move = np.zeros_like(V)
    for sx in (1.0, -1.0):
        c = [sx * 0.049 * s, L["face_y"] + 0.018 * s, L["cheek_z"] + 0.004 * s]
        w = _gauss(V, c, [0.017 * s, 0.028 * s, 0.013 * s])
        # out along the skin, and a little up and out: the malar stands higher, not only prouder
        move += w[:, None] * (h.N * 0.0045 * s + np.array([sx * 0.0014 * s, 0.0, 0.0010 * s]))
    return move * h.face[:, None], None


def _cheek_fullness(h: _Head):
    L, s, V = h.L, h.s, h.V
    Z = lambda f: L["chin_z"] + L["V"] * f
    move = np.zeros_like(V)
    for sx in (1.0, -1.0):
        c = [sx * 0.045 * s, L["face_y"] + 0.020 * s, Z(0.27)]
        w = _gauss(V, c, [0.020 * s, 0.030 * s, 0.026 * s])
        move += w[:, None] * h.N * 0.0052 * s
    return move * h.face[:, None], None


def _nose_region(h: _Head) -> Tuple[np.ndarray, np.ndarray]:
    """How far down the nose each vertex is (0 at the root, 1 at the tip and below it), and a
    weight that holds the move to the nose itself."""
    L, s, V = h.L, h.s, h.V
    tip = L["nose_tip"]
    root_z = L["nose_root_z"]
    t = np.clip((root_z - V[:, 2]) / max(root_z - tip[2], 1e-6), 0.0, 1.0)
    # below the tip: the wings and the columella come with it, and the lip under them does not
    below = 1.0 - _smooth((L["nose_base_z"] - 0.002 * s - V[:, 2]) / (0.008 * s))
    wide = _ramp(np.abs(V[:, 0]), 0.016 * s, 0.030 * s)
    front = _smooth((L["face_y"] + 0.026 * s - V[:, 1]) / (0.012 * s))
    return t, below * wide * front


def _nose_length(h: _Head):
    t, w = _nose_region(h)
    s, L = h.s, h.L
    # a longer nose is longer at the tip: its base on the lip goes a third as far (dropped whole
    # onto the lip, it came down into a moustache)
    tip_z, base_z = float(L["nose_tip"][2]), float(L["nose_base_z"])
    base = 0.35 + 0.65 * np.clip((h.V[:, 2] - base_z) / max(tip_z - base_z, 1e-6), 0.0, 1.0)
    w = w * t ** 1.3 * base
    return np.outer(w, [0.0, -0.0028 * s, -0.0052 * s]), None


def _nose_width(h: _Head):
    L, s, V = h.L, h.s, h.V
    tip = L["nose_tip"]
    c = [0.0, tip[1] + 0.010 * s, tip[2] - 0.004 * s]
    w = _gauss(V, c, [0.020 * s, 0.024 * s, 0.014 * s]) * h.face
    move = np.zeros_like(V)
    move[:, 0] = 0.30 * V[:, 0] * w
    return move, None


def _nose_bridge(h: _Head):
    t, w = _nose_region(h)
    return h.project(h.styled(nose_bridge=0.36), np.clip(w * 1.2, 0.0, 1.0) * h.face), None


def _eye_size(h: _Head):
    er = float(h.L["eye_r"])
    k = 0.14
    move = np.zeros_like(h.V)
    eyes = {}
    for sx, c in h.eye_centres():
        w = _eye_profile(h.V, c, er, 1.30, 2.5)
        move += (h.V - c) * (k * w)[:, None]
        eyes[sx] = lambda E, c=c: (E - c) * k
    return move, eyes


def _eye_spacing(h: _Head):
    er = float(h.L["eye_r"])
    d = 0.0032 * h.s
    move = np.zeros_like(h.V)
    eyes = {}
    for sx, c in h.eye_centres():
        w = _eye_profile(h.V, c, er, 1.45, 3.0)
        move[:, 0] += sx * d * w
        eyes[sx] = lambda E, sx=sx: np.tile([sx * d, 0.0, 0.0], (len(E), 1))
    return move, eyes


def _eye_tilt(h: _Head):
    er = float(h.L["eye_r"])
    a = math.radians(8.5)
    move = np.zeros_like(h.V)
    for sx, c in h.eye_centres():
        w = _eye_profile(h.V, c, er, 1.30, 2.6)
        # about the forward axis through the eye, the outer corner up (the eye is round: it turns
        # with its lids and shows nothing)
        q = h.V - c
        ang = sx * a * w
        x2 = q[:, 0] * np.cos(ang) - q[:, 2] * np.sin(ang)
        z2 = q[:, 0] * np.sin(ang) + q[:, 2] * np.cos(ang)
        move[:, 0] += x2 - q[:, 0]
        move[:, 2] += z2 - q[:, 2]
    return move, None


def _brow_height(h: _Head):
    L, s, V = h.L, h.s, h.V
    band = np.exp(-0.5 * ((V[:, 2] - (L["brow_z"] + 0.003 * s)) / (0.0075 * s)) ** 2)
    wide = _ramp(np.abs(V[:, 0]), 0.050 * s, 0.072 * s)
    w = band * wide * (1.0 - _smooth((_theta(V, L) - 70.0) / 20.0))
    return np.outer(w, [0.0, 0.0, 0.0046 * s]), None


def _brow_ridge(h: _Head):
    return h.project(h.styled(brow=0.34), h.face), None


def _lip_fullness(h: _Head):
    return h.project(h.styled(lips=0.45), h.face), None


def _mouth_width(h: _Head):
    L, s, V = h.L, h.s, h.V
    c = [0.0, L["face_y"], L["mouth_z"]]
    w = _gauss(V, c, [0.034 * s, 0.040 * s, 0.013 * s]) * h.face
    warp = np.zeros_like(V)
    warp[:, 0] = 0.18 * V[:, 0] * w
    return h.project(h.styled(mouth_width=0.18), h.face * _ramp(np.abs(V[:, 2] - L["mouth_z"]), 0.014 * s, 0.030 * s),
                     warp), None


def _face_length(h: _Head):
    L, s, V = h.L, h.s, h.V
    z = V[:, 2]
    top = L["eye_z"] - 0.012 * s
    f = np.clip((top - z) / max(top - L["chin_z"], 1e-6), 0.0, 1.0)
    # under the chin it goes back to nothing at the throat
    f = f * (1.0 - _smooth((L["chin_z"] - 0.004 * s - z) / (0.040 * s)))
    w = f * (1.0 - _smooth((_theta(V, L) - 55.0) / 40.0))
    return np.outer(w, [0.0, -0.0012 * s, -0.0085 * s]), None


def _ear_size(h: _Head):
    return h.project(h.styled(ears=0.24), h.ears), None


def _age(h: _Head):
    """The years: the lower lid's fold, the naso-labial line and the thinner cheek the builder
    makes for an old head, the lips thinner, the ears a little longer; and gravity: the jowls,
    the tip of the nose and the outer brow come down."""
    L, s, V = h.L, h.s, h.V
    Z = lambda f: L["chin_z"] + L["V"] * f
    warp = np.zeros_like(V)
    for sx in (1.0, -1.0):
        w = _gauss(V, [sx * 0.040 * s, L["face_y"] + 0.022 * s, Z(0.15)], [0.017 * s, 0.030 * s, 0.020 * s])
        warp += np.outer(w, [sx * 0.0012 * s, 0.0, -0.0036 * s])
        w = _gauss(V, [sx * 0.046 * s, L["face_y"], L["brow_z"]], [0.012 * s, 0.030 * s, 0.009 * s])
        warp += np.outer(w, [0.0, 0.0, -0.0016 * s])
    w = _gauss(V, L["nose_tip"], [0.012 * s, 0.020 * s, 0.010 * s])
    warp += np.outer(w, [0.0, 0.0, -0.0016 * s])
    warp *= h.face[:, None]
    mask = np.maximum(h.face, h.ears)
    return h.project(h.aged(0.95, lips=-0.14, ears=0.08), mask, warp), None


BUILDERS: Dict[str, Callable[[_Head], tuple]] = {
    "jaw_width": _jaw_width, "chin_length": _chin_length, "chin_projection": _chin_projection,
    "cheekbones": _cheekbones, "cheek_fullness": _cheek_fullness,
    "nose_length": _nose_length, "nose_width": _nose_width, "nose_bridge": _nose_bridge,
    "eye_size": _eye_size, "eye_spacing": _eye_spacing, "eye_tilt": _eye_tilt,
    "brow_height": _brow_height, "brow_ridge": _brow_ridge,
    "lip_fullness": _lip_fullness, "mouth_width": _mouth_width,
    "face_length": _face_length, "ear_size": _ear_size, AGE: _age,
}


def head_targets(skel: Skeleton, hs: Optional[bodylib.HeadStyle], V: np.ndarray, T: np.ndarray,
                 eyes: Optional[Dict[float, np.ndarray]] = None, only: Optional[Sequence[str]] = None
                 ) -> Tuple[Dict[str, np.ndarray], Dict[float, Dict[str, np.ndarray]]]:
    """Every slider's +1 move of the head mesh V (triangles T), and of each eye's vertices (keyed
    by side, +1 the left). Returns ({slider: moves}, {side: {slider: moves}})."""
    h = _Head(skel, hs, V, T)
    out: Dict[str, np.ndarray] = {}
    eye_out: Dict[float, Dict[str, np.ndarray]] = {sx: {} for sx in (eyes or {})}
    for name in (only or TARGETS):
        move, eye_fn = BUILDERS[name](h)
        out[name] = move
        if eye_fn and eyes:
            for sx, E in eyes.items():
                if sx in eye_fn:
                    eye_out[sx][name] = eye_fn[sx](np.asarray(E, float))
    return out, eye_out


def vault_moves(skel: Skeleton, hs: Optional[bodylib.HeadStyle], V: np.ndarray, move: np.ndarray) -> float:
    """The largest move (metres) over the part of the head hair, hoods and helms are built against:
    above the brow's band and behind the ears, the ears themselves left out."""
    L = bodylib.head_landmarks(skel, hs)
    s = L["s"]
    vault = (V[:, 2] > L["brow_z"] + 0.034 * s) | (bodylib.head_angle(V, L) > 100.0)
    vault &= ear_mask(V, L) < 1e-3
    vault &= V[:, 2] > L["chin_z"] - 0.050 * s          # the neck's own seam is its own test
    return float(np.linalg.norm(move[vault], axis=1).max()) if np.any(vault) else 0.0


def normal_moves(V: np.ndarray, T: np.ndarray, move: np.ndarray) -> np.ndarray:
    """What a target does to the normals: the welded normals of the moved mesh less the mesh's."""
    return _normals(V + move, T) - _normals(V, T)


# -- carrying the face's moves onto what lies on it ------------------------------------------------

def transfer(head_V: np.ndarray, head_moves: Dict[str, np.ndarray], part_V: np.ndarray,
             near: float = 0.010, far: float = 0.034, k: int = 4) -> Dict[str, np.ndarray]:
    """Each face target carried onto a part worn over the face (a beard, hair, a hood): every vertex
    of the part moves as the skin under it does, the mean of the nearest few skin vertices' moves,
    all of it within `near` of the skin and none of it past `far` (a braid down the back, a cloak's
    hem stay where they are)."""
    return _transfer(head_V, head_moves, part_V, near, far, k)


def _transfer(head_V, head_moves, part_V, near, far, k):
    head_V = np.asarray(head_V, float)
    part_V = np.asarray(part_V, float)
    try:
        from scipy.spatial import cKDTree
        d, idx = cKDTree(head_V).query(part_V, k=k)
    except Exception:  # no scipy: brute force in blocks
        d = np.empty((len(part_V), k))
        idx = np.empty((len(part_V), k), int)
        for a in range(0, len(part_V), 512):
            D = np.linalg.norm(part_V[a:a + 512, None, :] - head_V[None, :, :], axis=2)
            ii = np.argpartition(D, k, axis=1)[:, :k]
            dd = np.take_along_axis(D, ii, axis=1)
            o = np.argsort(dd, axis=1)
            idx[a:a + 512] = np.take_along_axis(ii, o, axis=1)
            d[a:a + 512] = np.take_along_axis(dd, o, axis=1)
    # steeply by distance: a part goes with the skin right under it, not a neighbourhood's average
    wts = 1.0 / np.maximum(d, 1e-4) ** 4
    wts /= wts.sum(axis=1, keepdims=True)
    fade = _ramp(d[:, 0], near, far)
    out = {}
    for name, M in head_moves.items():
        m = np.einsum("nk,nkc->nc", wts, M[idx])
        out[name] = m * fade[:, None]
    return out


# -- the face's own coordinates, for marks drawn in the engine --------------------------------------

UV2_SPAN = 0.40


def face_coords(skel: Skeleton, hs: Optional[bodylib.HeadStyle], V: np.ndarray) -> np.ndarray:
    """Where each vertex is on the face, the same on every head: across it as the arc round the
    vault's axis from the middle of the face (metres, + to the head's left), and up it from the
    eye line (metres), mapped into 0..1 over UV2_SPAN. Written as the head's second UV set, so a
    mark drawn at a place on the face (a scar through the brow, woad across the cheeks) lands at
    that place on every head and goes with the skin when a slider moves it."""
    L = bodylib.head_landmarks(skel, hs)
    V = np.asarray(V, float)
    ang = np.arctan2(V[:, 0], -(V[:, 1] - L["skull_c"][1]))
    u = ang * 0.080 * L["s"]
    v = V[:, 2] - L["eye_z"]
    return np.stack([0.5 + u / UV2_SPAN, 0.5 - v / UV2_SPAN], axis=1)
