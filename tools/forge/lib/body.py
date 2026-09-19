"""Procedural humanoid body, head, eyes, hair and beards for WM_Humanoid_v1.

Pipeline (Blender): lofted primitives (numpy) -> voxel remesh (one smooth manifold with
proper joint blends) -> smooth -> decimate -> UVs -> skin weights -> analytic morph targets.
Heads use the same pipeline at a finer voxel size; eyes are separate spheres; hair and
beards are shells derived from head regions (so they fit every head preset).

Everything here is deterministic for a given parameter set.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig
from .rig import Skeleton, FWD, UP, LEFT

# --------------------------------------------------------------------------------------
# numpy mesh helpers
# --------------------------------------------------------------------------------------

class MeshData:
    """Vertex/face accumulator (faces are lists of vertex indices, tris or quads)."""

    def __init__(self):
        self.verts: List[np.ndarray] = []
        self.faces: List[List[int]] = []
        self._n = 0

    def add(self, verts: np.ndarray, faces: Sequence[Sequence[int]]) -> None:
        off = self._n
        self.verts.append(np.asarray(verts, float))
        self.faces.extend([[int(i) + off for i in f] for f in faces])
        self._n += len(verts)

    def merge(self, other: "MeshData") -> None:
        for v, f in zip(other.verts, []):
            pass
        vs = other.vertices()
        self.add(vs, other.faces)

    def vertices(self) -> np.ndarray:
        return np.concatenate(self.verts, axis=0) if self.verts else np.zeros((0, 3))

    def to_blender(self, name: str):
        import bpy
        me = bpy.data.meshes.new(name)
        vs = self.vertices()
        me.from_pydata([tuple(v) for v in vs], [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        return ob


def perp_frame(d: np.ndarray, front: np.ndarray = FWD) -> Tuple[np.ndarray, np.ndarray]:
    """Two unit vectors (u, v) perpendicular to d; u is `front` projected."""
    d = rig._unit(d)
    u = front - np.dot(front, d) * d
    if np.linalg.norm(u) < 1e-6:
        u = UP - np.dot(UP, d) * d
    u = rig._unit(u)
    v = np.cross(d, u)
    return u, v


def superellipse(n: int, e: float = 2.0, phase: float = 0.0) -> np.ndarray:
    """(n, 2) points of a unit superellipse |x|^e + |y|^e = 1."""
    a = np.linspace(0, 2 * math.pi, n, endpoint=False) + phase
    c, s = np.cos(a), np.sin(a)
    x = np.sign(c) * np.abs(c) ** (2.0 / e)
    y = np.sign(s) * np.abs(s) ** (2.0 / e)
    return np.stack([x, y], axis=1)


def ring_points(center: np.ndarray, u: np.ndarray, v: np.ndarray, ru: float, rv: float, n: int,
                e: float = 2.0, flatten_v_neg: float = 0.0, shift_u: float = 0.0, shift_v: float = 0.0) -> np.ndarray:
    """Ring in the plane spanned by u,v around center.  `flatten_v_neg` (0..1) squashes the
    -v half (e.g. flat soles); shifts move the ring within its plane."""
    pts2 = superellipse(n, e)
    x = pts2[:, 0] * ru + shift_u
    y = pts2[:, 1] * rv
    if flatten_v_neg > 0:
        neg = y < 0
        y[neg] *= (1.0 - flatten_v_neg)
    y = y + shift_v
    return center[None, :] + x[:, None] * u[None, :] + y[:, None] * v[None, :]


def loft_rings(rings: Sequence[np.ndarray], cap_start: bool = True, cap_end: bool = True, close: bool = False) -> Tuple[np.ndarray, List[List[int]]]:
    """Connect rings (same point count) into quads; optional triangle-fan caps."""
    n = len(rings[0])
    verts = list(np.concatenate(rings, axis=0))
    faces: List[List[int]] = []
    m = len(rings)
    for i in range(m - 1 if not close else m):
        a = i * n
        b = ((i + 1) % m) * n
        for j in range(n):
            j2 = (j + 1) % n
            faces.append([a + j, a + j2, b + j2, b + j])
    if cap_start and not close:
        c = len(verts)
        verts.append(rings[0].mean(axis=0))
        for j in range(n):
            faces.append([c, (j + 1) % n, j])
    if cap_end and not close:
        c = len(verts)
        verts.append(rings[-1].mean(axis=0))
        a = (m - 1) * n
        for j in range(n):
            faces.append([c, a + j, a + (j + 1) % n])
    return np.asarray(verts), faces


def tube(md: MeshData, path: Sequence[np.ndarray], radii: Sequence[Tuple[float, float]], n: int = 20, e: float = 2.0,
         front: np.ndarray = FWD, shifts: Optional[Sequence[Tuple[float, float]]] = None, round_ends: bool = True,
         exps: Optional[Sequence[float]] = None, flatten: Optional[Sequence[float]] = None) -> None:
    """A lofted tube along a polyline `path` with per-station (ru, rv) radii (u = front, v = the
    other perpendicular).  Rounded ends are added as shrinking rings."""
    path = [np.asarray(p, float) for p in path]
    rings = []
    m = len(path)
    for i, p in enumerate(path):
        if i == 0:
            d = path[1] - path[0]
        elif i == m - 1:
            d = path[-1] - path[-2]
        else:
            d = rig._unit(path[i + 1] - path[i]) + rig._unit(path[i] - path[i - 1])
        u, v = perp_frame(d, front)
        ru, rv = radii[i]
        su, sv = (shifts[i] if shifts else (0.0, 0.0))
        ee = exps[i] if exps else e
        fl = flatten[i] if flatten else 0.0
        if i == 0 and round_ends:
            d0 = rig._unit(path[1] - path[0])
            for k in (0.55, 0.85):
                a = math.acos(k)
                rings.append(ring_points(p - d0 * math.sin(a) * min(ru, rv) * 0.9, u, v, ru * k, rv * k, n, ee, fl, su * k, sv * k))
        rings.append(ring_points(p, u, v, ru, rv, n, ee, fl, su, sv))
        if i == m - 1 and round_ends:
            d1 = rig._unit(path[-1] - path[-2])
            for k in (0.85, 0.55):
                a = math.acos(k)
                rings.append(ring_points(p + d1 * math.sin(a) * min(ru, rv) * 0.9, u, v, ru * k, rv * k, n, ee, fl, su * k, sv * k))
    verts, faces = loft_rings(rings, True, True)
    md.add(verts, faces)


def ellipsoid(md: MeshData, center: np.ndarray, radii: Tuple[float, float, float], nu: int = 16, nv: int = 12,
              rot: Optional[np.ndarray] = None) -> None:
    center = np.asarray(center, float)
    verts = []
    faces = []
    for i in range(nv + 1):
        th = math.pi * i / nv
        for j in range(nu):
            ph = 2 * math.pi * j / nu
            p = np.array([radii[0] * math.sin(th) * math.cos(ph), radii[1] * math.sin(th) * math.sin(ph), radii[2] * math.cos(th)])
            if rot is not None:
                p = rot @ p
            verts.append(center + p)
    for i in range(nv):
        for j in range(nu):
            a = i * nu + j
            b = i * nu + (j + 1) % nu
            c = (i + 1) * nu + (j + 1) % nu
            d = (i + 1) * nu + j
            if i == 0:
                faces.append([a, c, d])
            elif i == nv - 1:
                faces.append([a, b, c])
            else:
                faces.append([a, b, c, d])
    md.add(np.asarray(verts), faces)


def capsule(md: MeshData, a: np.ndarray, b: np.ndarray, ra: float, rb: Optional[float] = None, n: int = 14, front=FWD) -> None:
    rb = ra if rb is None else rb
    tube(md, [a, b], [(ra, ra), (rb, rb)], n=n, front=front, round_ends=True)


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def gauss3(p: np.ndarray, c: np.ndarray, s: Tuple[float, float, float]) -> np.ndarray:
    d = (p - np.asarray(c)) / np.asarray(s)
    return np.exp(-0.5 * np.sum(d * d, axis=1))


# --------------------------------------------------------------------------------------
# body style
# --------------------------------------------------------------------------------------

@dataclass
class BodyStyle:
    """Shape knobs beyond `Proportions` (all 0..1 unless noted)."""
    muscle: float = 0.35
    belly: float = 0.2
    chest: float = 0.5
    shoulders: float = 0.5
    hands: float = 1.12     # slightly large hands read well
    feet: float = 1.05

    @staticmethod
    def from_dict(d: Optional[dict]) -> "BodyStyle":
        b = BodyStyle()
        for k, v in (d or {}).items():
            if hasattr(b, k):
                setattr(b, k, float(v))
        return b


# --------------------------------------------------------------------------------------
# body primitives
# --------------------------------------------------------------------------------------

def build_body_primitives(skel: Skeleton, style: BodyStyle) -> MeshData:
    """Union of lofted parts approximating the body (to be voxel-remeshed)."""
    p = skel.props
    J = skel.J
    s = p.height / rig.DEFAULT_HEIGHT
    bulk = p.bulk * (0.9 + 0.2 * (0.5 + 0.5 * p.build)) if False else p.bulk
    fem = p.feminine
    md = MeshData()

    hip = J["Hips"]; spine = J["Spine"]; chest = J["Chest"]; neck = J["Neck"]; head = J["Head"]
    hipj_l = J["UpperLeg.L"]
    z_crotch = hipj_l[2] - 0.06 * s
    # -- torso loft (z stations) ---------------------------------------------------------
    torso_len = neck[2] - hip[2]
    hipw = (0.165 + 0.02 * fem) * bulk * s * (0.9 + 0.2 * p.hip_width)
    stations = [  # (z, half-width, half-depth, y-centre offset (+ back), exponent)
        (z_crotch, hipw * 0.72, 0.085 * bulk * s, 0.01 * s, 2.4),
        (hipj_l[2] + 0.02 * s, hipw, 0.115 * bulk * s, 0.012 * s, 2.5),
        (hip[2] + 0.06 * s, hipw * 0.96, 0.110 * bulk * s, 0.008 * s, 2.4),
        (spine[2] + 0.02 * s, (0.145 - 0.02 * fem) * bulk * s, 0.098 * bulk * s, 0.0, 2.3),      # waist
        (chest[2] - 0.01 * s, (0.160 - 0.01 * fem) * bulk * s, 0.108 * bulk * s, 0.0, 2.3),
        (chest[2] + 0.09 * s, (0.172 + 0.02 * style.chest) * bulk * s, (0.116 + 0.02 * style.chest) * bulk * s, -0.004 * s, 2.4),  # chest
        (chest[2] + 0.16 * s, 0.170 * bulk * s, 0.105 * bulk * s, 0.0, 2.6),
        (neck[2] - 0.005 * s, 0.135 * bulk * s, 0.085 * bulk * s, 0.004 * s, 2.6),
        (neck[2] + 0.025 * s, 0.085 * bulk * s, 0.065 * bulk * s, 0.008 * s, 2.2),
    ]
    rings = []
    n = 28
    for z, hw, hd, yo, e in stations:
        c = np.array([0.0, yo, z])
        rings.append(ring_points(c, LEFT, -FWD, hw, hd, n, e))
    verts, faces = loft_rings(rings, True, True)
    md.add(verts, faces)
    # buttocks and (feminine) bust as soft ellipsoids
    for sx in (1, -1):
        ellipsoid(md, np.array([sx * 0.075 * s, 0.075 * bulk * s, hipj_l[2] + 0.02 * s]), (0.085 * bulk * s, 0.07 * bulk * s, 0.085 * bulk * s), 14, 10)
        if fem > 0.05:
            ellipsoid(md, np.array([sx * 0.075 * s, -0.085 * bulk * s, chest[2] + 0.06 * s]), (0.06 * fem * s + 0.02 * s, 0.055 * fem * s + 0.02 * s, 0.055 * fem * s + 0.02 * s), 14, 10)
    if style.belly > 0:
        ellipsoid(md, np.array([0.0, -0.045 * bulk * s, spine[2] - 0.01 * s]), (0.12 * bulk * s, (0.07 + 0.07 * style.belly) * bulk * s, 0.11 * bulk * s), 16, 12)
    # -- neck --------------------------------------------------------------------------
    tube(md, [neck - UP * 0.01 * s, head + UP * 0.04 * s], [(0.062 * bulk * s, 0.058 * bulk * s), (0.058 * bulk * s, 0.056 * bulk * s)], n=16)
    # -- shoulders: deltoid balls + trapezius slope ---------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        sh = J[f"UpperArm.{side}"]
        ellipsoid(md, sh + np.array([sx * 0.012 * s, 0.0, 0.01 * s]), ((0.072 + 0.02 * style.shoulders - 0.012 * fem) * bulk * s, 0.072 * bulk * s, 0.07 * bulk * s), 16, 12)
        trap_a = np.array([sx * 0.04 * s, 0.015 * s, neck[2] + 0.005 * s])
        trap_b = np.array([sx * 0.16 * s, 0.01 * s, sh[2] + 0.02 * s])
        capsule(md, trap_a, trap_b, 0.055 * bulk * s, 0.045 * bulk * s, n=14)
    # -- arms --------------------------------------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        sh, el, wr, tip = J[f"UpperArm.{side}"], J[f"LowerArm.{side}"], J[f"Hand.{side}"], J[f"HandTip.{side}"]
        d = rig._unit(el - sh)
        ua = 0.062 * bulk * s * (1 + 0.15 * style.muscle - 0.08 * fem)
        fa = 0.052 * bulk * s * (1 + 0.1 * style.muscle - 0.06 * fem)
        path = [sh + d * 0.02 * s, sh + d * 0.12 * s, el - d * 0.06 * s, el, el + d * 0.07 * s, wr - d * 0.04 * s, wr]
        radii = [(ua * 0.95, ua * 0.95), (ua, ua * 0.96), (ua * 0.84, ua * 0.84), (0.047 * bulk * s, 0.046 * bulk * s),
                 (fa, fa * 0.95), (0.040 * bulk * s, 0.034 * bulk * s), (0.034 * bulk * s, 0.028 * bulk * s)]
        tube(md, path, radii, n=18, round_ends=True)
        # hand: mitten + thumb.  Palm normal = arm-frame "v" (up/out); fingers along d.
        u, v = perp_frame(d, FWD)      # u = forward, v = d x u
        hs = style.hands * p.hand_size * s
        palm_len, palm_w, palm_t = 0.085 * hs, 0.082 * hs, 0.030 * hs
        hpath = [wr - d * 0.01 * s, wr + d * palm_len * 0.45, wr + d * palm_len, wr + d * (palm_len + 0.05 * hs), wr + d * (palm_len + 0.085 * hs)]
        hr = [(0.034 * hs, 0.026 * hs), (palm_w * 0.5, palm_t * 0.55), (palm_w * 0.52, palm_t * 0.5), (palm_w * 0.46, palm_t * 0.42), (palm_w * 0.34, palm_t * 0.33)]
        # the hand's flat plane must contain the forward direction: ru along u (forward) = width
        tube(md, hpath, hr, n=18, e=2.6, round_ends=True)
        # thumb: from the palm's forward edge near the wrist, pointing forward-out
        tb0 = wr + d * 0.025 * hs + u * palm_w * 0.42
        tb1 = tb0 + rig._unit(u * 0.8 + d * 0.5 - v * 0.15 * sx * 0) * 0.055 * hs
        capsule(md, tb0, tb1, 0.016 * hs, 0.013 * hs, n=10, front=UP)
    # -- legs --------------------------------------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        hj, kn, an = J[f"UpperLeg.{side}"], J[f"LowerLeg.{side}"], J[f"Foot.{side}"]
        th = 0.092 * bulk * s * (1 + 0.1 * style.muscle + 0.05 * fem)
        path = [hj + UP * 0.03 * s + LEFT * sx * 0.01 * s, hj - UP * 0.10 * s, kn + UP * 0.10 * s, kn, kn - UP * 0.10 * s, an + UP * 0.10 * s, an + UP * 0.02 * s]
        radii = [(th * 1.05, th * 1.0), (th * 0.98, th * 0.94), (0.070 * bulk * s, 0.068 * bulk * s), (0.062 * bulk * s, 0.060 * bulk * s),
                 (0.066 * bulk * s, 0.070 * bulk * s), (0.046 * bulk * s, 0.045 * bulk * s), (0.040 * bulk * s, 0.038 * bulk * s)]
        shifts = [(0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.012 * s, 0.0), (0.006 * s, 0.0), (0.0, 0.0)]  # calf back
        # u = forward; shift_u positive = forward.  Calf bulge sits backward -> negative shift.
        shifts = [(a * -1, b) for a, b in shifts]
        tube(md, path, radii, n=20, shifts=shifts, round_ends=True)
        # foot: heel ball + lofted wedge along the foot, flat sole
        fs = style.feet * p.foot_size * s
        heel = an + np.array([0.0, 0.055 * fs, -an[2] + 0.04 * fs])
        toe_tip = J[f"ToeTip.{side}"]
        ball = J[f"Toe.{side}"]
        fpath = [heel + np.array([0.0, 0.012 * fs, 0.0]), an + np.array([0.0, 0.0, -an[2] + 0.045 * fs]), (an + ball) / 2 + np.array([0.0, 0.0, -((an + ball) / 2)[2] + 0.04 * fs]),
                 ball + np.array([0.0, 0.0, -ball[2] + 0.028 * fs]), toe_tip + np.array([0.0, 0.01 * fs, -toe_tip[2] + 0.022 * fs])]
        fr = [(0.036 * fs, 0.04 * fs), (0.042 * fs, 0.048 * fs), (0.048 * fs, 0.04 * fs), (0.055 * fs, 0.03 * fs), (0.05 * fs, 0.024 * fs)]
        tube(md, fpath, fr, n=16, e=2.8, front=UP, flatten=[0.75, 0.8, 0.85, 0.85, 0.85], round_ends=True)
        ellipsoid(md, an + np.array([0.0, 0.0, 0.0]), (0.045 * bulk * s, 0.05 * bulk * s, 0.045 * bulk * s), 12, 8)
    return md


# --------------------------------------------------------------------------------------
# head
# --------------------------------------------------------------------------------------

@dataclass
class HeadStyle:
    skull_width: float = 1.0
    skull_depth: float = 1.0
    jaw_width: float = 1.0
    chin: float = 1.0          # chin length/prominence
    nose: float = 1.0          # nose size
    nose_bridge: float = 1.0
    brow: float = 1.0
    cheeks: float = 1.0
    ears: float = 1.0
    eye_spacing: float = 1.0
    eye_size: float = 1.0
    mouth_width: float = 1.0
    lips: float = 1.0
    forehead: float = 1.0

    @staticmethod
    def from_dict(d: Optional[dict]) -> "HeadStyle":
        h = HeadStyle()
        for k, v in (d or {}).items():
            if hasattr(h, k):
                setattr(h, k, float(v))
        return h


def head_landmarks(skel: Skeleton, hs: HeadStyle) -> dict:
    """Key positions used by the head builder, eyes and the face painter."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT * p.head_size
    fem = p.feminine
    head = skel.J["Head"]
    top = skel.J["HeadTop"]
    hl = top[2] - head[2]                    # head bone length (~0.245)
    eye_z = head[2] + hl * 0.465
    skull_c = np.array([0.0, 0.008 * s, head[2] + hl * 0.56])
    skull_r = np.array([0.077 * hs.skull_width * (1 - 0.03 * fem), 0.094 * hs.skull_depth, 0.100 * (0.96 + 0.08 * hs.forehead)]) * s
    face_y = skull_c[1] - skull_r[1] * 0.93   # y of the face plane at eye level
    return {
        "s": s, "head": head, "top": top, "eye_z": eye_z, "skull_c": skull_c, "skull_r": skull_r, "face_y": face_y,
        "eye_x": 0.031 * hs.eye_spacing * s, "eye_r": 0.0125 * hs.eye_size * s,
        "eye_c_y": face_y + 0.019 * s,        # eyeball centre a little behind the face plane
        "nose_tip": np.array([0.0, face_y - 0.024 * hs.nose * s, eye_z - 0.040 * s]),
        "mouth_z": head[2] + hl * 0.20, "mouth_w": 0.026 * hs.mouth_width * s,
        "chin_z": head[2] - 0.012 * hs.chin * s,
        "brow_z": eye_z + 0.024 * s,
        "ear_c": np.array([0.078 * hs.skull_width * s, 0.012 * s, eye_z - 0.004 * s]),
    }


def build_head_primitives(skel: Skeleton, hs: HeadStyle) -> MeshData:
    L = head_landmarks(skel, hs)
    s = L["s"]; fem = skel.props.feminine
    md = MeshData()
    ellipsoid(md, L["skull_c"], tuple(L["skull_r"]), 24, 18)
    # forehead/temple fill: slightly boxier front upper skull
    ellipsoid(md, L["skull_c"] + np.array([0.0, -0.02 * s, 0.02 * s]), (L["skull_r"][0] * 0.9, L["skull_r"][1] * 0.78, L["skull_r"][2] * 0.85), 18, 14)
    # jaw loft: from the cheekbone level to the chin
    eye_z = L["eye_z"]
    face_y = L["face_y"]
    jw = hs.jaw_width * (1 - 0.06 * fem)
    stations = [
        (eye_z + 0.005 * s, 0.076 * jw * s, 0.088 * s, 0.006 * s, 2.3),
        (eye_z - 0.035 * s, 0.072 * jw * s, 0.082 * s, 0.0, 2.4),
        (L["mouth_z"] + 0.005 * s, 0.060 * jw * s, 0.070 * s, -0.008 * s, 2.5),
        (L["mouth_z"] - 0.022 * s, 0.047 * jw * s, 0.056 * s, -0.016 * s, 2.5),
        (L["chin_z"] + 0.004 * s, 0.032 * jw * s, 0.036 * s, -0.022 * hs.chin * s, 2.2),
    ]
    rings = [ring_points(np.array([0.0, yo, z]), LEFT, -FWD, hw, hd, 24, e) for z, hw, hd, yo, e in stations]
    verts, faces = loft_rings(rings, True, True)
    md.add(verts, faces)
    # cheekbones
    for sx in (1, -1):
        ellipsoid(md, np.array([sx * 0.052 * s, face_y + 0.030 * s, eye_z - 0.030 * s]), (0.030 * hs.cheeks * s, 0.034 * s, 0.028 * s), 12, 10)
    # brow ridge
    capsule(md, np.array([-0.048 * s, face_y + 0.006 * s, L["brow_z"]]), np.array([0.048 * s, face_y + 0.006 * s, L["brow_z"]]),
            (0.013 + 0.004 * hs.brow - 0.004 * fem) * s, n=12, front=UP)
    # nose: bridge to tip, wings
    bridge = np.array([0.0, face_y - 0.002 * s, eye_z + 0.004 * s])
    tip = L["nose_tip"]
    tube(md, [bridge, (bridge + tip) / 2 + np.array([0.0, -0.004 * s, 0.0]), tip],
         [(0.010 * hs.nose_bridge * s, 0.009 * s), (0.012 * hs.nose * s, 0.011 * s), (0.016 * hs.nose * s, 0.014 * s)], n=12, front=UP)
    for sx in (1, -1):
        ellipsoid(md, tip + np.array([sx * 0.012 * hs.nose * s, 0.010 * s, 0.002 * s]), (0.011 * hs.nose * s, 0.011 * s, 0.009 * s), 10, 8)
    # ears
    for sx in (1, -1):
        c = L["ear_c"] * np.array([sx, 1, 1])
        rot = rig.rot_axis(UP, math.radians(-12.0 * sx)) @ rig.rot_axis(FWD, math.radians(8.0 * sx))
        ellipsoid(md, c, (0.009 * s, 0.017 * hs.ears * s, 0.030 * hs.ears * s), 12, 10, rot=rot)
    # neck stub (so the head closes at the bottom and meets the neck)
    tube(md, [L["head"] - UP * 0.03 * s, L["head"] + UP * 0.05 * s], [(0.052 * s, 0.05 * s), (0.056 * s, 0.056 * s)], n=16)
    return md


def head_sculpt(verts: np.ndarray, normals: np.ndarray, skel: Skeleton, hs: HeadStyle) -> np.ndarray:
    """Post-remesh analytic sculpting: eye sockets (almond dishes that the eyeballs sit in),
    philtrum/mouth groove, slight chin cleft.  Returns displaced vertices."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    out = verts.copy()
    for sx in (1, -1):
        c = np.array([sx * L["eye_x"], L["face_y"], L["eye_z"]])
        d = (verts - c) / np.array([0.030 * hs.eye_size * s, 0.03 * s, 0.0075 * hs.eye_size * s])
        w = np.exp(-0.5 * np.sum(d * d, axis=1))
        # push inward along +Y (back), only near the front surface
        front = np.clip(-normals[:, 1], 0, 1)
        out[:, 1] += 0.013 * s * w * front
    # mouth line groove
    d = (verts - np.array([0.0, L["face_y"] + 0.012 * s, L["mouth_z"]])) / np.array([L["mouth_w"] * 1.1, 0.03 * s, 0.004 * s])
    w = np.exp(-0.5 * np.sum(d * d, axis=1))
    front = np.clip(-normals[:, 1], 0, 1)
    out[:, 1] += 0.004 * s * w * front
    return out


# --------------------------------------------------------------------------------------
# eyes
# --------------------------------------------------------------------------------------

def eye_mesh(center: np.ndarray, r: float, nu: int = 20, nv: int = 14) -> Tuple[np.ndarray, List[List[int]], np.ndarray]:
    """UV sphere whose pole faces forward (-Y); uv = (azimuth around forward axis, polar angle
    from forward / pi).  Returns verts, faces, uvs-per-vertex."""
    verts, faces, uvs = [], [], []
    for i in range(nv + 1):
        th = math.pi * i / nv
        for j in range(nu + 1):
            ph = 2 * math.pi * j / nu
            # forward axis = -Y; ring plane spanned by X and Z
            p = np.array([r * math.sin(th) * math.cos(ph), -r * math.cos(th), r * math.sin(th) * math.sin(ph)])
            verts.append(center + p)
            uvs.append((j / nu, th / math.pi))
    for i in range(nv):
        for j in range(nu):
            a = i * (nu + 1) + j
            b = a + 1
            c = a + nu + 2
            d = a + nu + 1
            if i == 0:
                faces.append([a, c, d])
            elif i == nv - 1:
                faces.append([a, b, c])
            else:
                faces.append([a, b, c, d])
    return np.asarray(verts), faces, np.asarray(uvs)


# --------------------------------------------------------------------------------------
# hair and beards (shells from head regions, built in numpy from the head mesh arrays)
# --------------------------------------------------------------------------------------

def _region_shell(verts: np.ndarray, normals: np.ndarray, faces: np.ndarray, mask: np.ndarray, offset: np.ndarray,
                  thickness_back: float = 0.0) -> Tuple[np.ndarray, List[List[int]], np.ndarray]:
    """Extract faces whose vertices are all in `mask`, offset their vertices along normals by
    `offset` (per-vertex), and close the boundary with a rim back to an inner shell so the
    piece has thickness (looks solid from all angles).  Returns verts, faces, source indices."""
    keep = mask[faces].all(axis=1)
    f = faces[keep]
    used = np.unique(f)
    remap = -np.ones(len(verts), dtype=int)
    remap[used] = np.arange(len(used))
    outer = verts[used] + normals[used] * offset[used][:, None]
    inner = verts[used] + normals[used] * (thickness_back)[None] if False else verts[used] - normals[used] * 0.002
    fo = remap[f]
    faces_out: List[List[int]] = [list(map(int, tri)) for tri in fo]
    n_out = len(used)
    # inner shell (flipped)
    faces_in = [[int(i) + n_out for i in tri[::-1]] for tri in fo]
    # boundary edges -> rim quads
    edges: Dict[Tuple[int, int], int] = {}
    for tri in fo:
        for k in range(3):
            a, b = int(tri[k]), int(tri[(k + 1) % 3])
            key = (min(a, b), max(a, b))
            edges[key] = edges.get(key, 0) + 1
    rim = []
    for tri in fo:
        for k in range(3):
            a, b = int(tri[k]), int(tri[(k + 1) % 3])
            if edges[(min(a, b), max(a, b))] == 1:
                rim.append([a, b, b + n_out, a + n_out])
    allv = np.concatenate([outer, inner], axis=0)
    return allv, faces_out + faces_in + rim, np.concatenate([used, used])


def scalp_mask(verts: np.ndarray, skel: Skeleton, hs: HeadStyle, hairline: float = 1.0, sides: float = 1.0, nape: float = 1.0) -> np.ndarray:
    """Vertices on the scalp: above a hairline that dips at the temples, above the ears at the
    sides, down to the nape at the back."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    eye_z = L["eye_z"]
    fy = L["face_y"]
    front = -y / max(abs(fy), 1e-6)         # 1 at the face plane, 0 at the centre, -1 at the back
    frontness = np.clip((-y - 0.0) / 0.09 / s, -1, 1)
    # hairline height: forehead top at the front, ear top at the sides, nape at the back
    z_front = eye_z + (0.058 + 0.01 * (1 - hairline)) * s
    z_side = eye_z + 0.028 * s * sides
    z_back = eye_z - (0.06 + 0.02 * nape) * s
    ff = np.clip(frontness, 0, 1)
    bb = np.clip(-frontness, 0, 1)
    zl = z_side * (1 - ff - bb) + z_front * ff + z_back * bb
    # temple dips
    temple = np.exp(-0.5 * (((np.abs(x) - 0.06 * s) / (0.02 * s)) ** 2)) * np.clip(frontness, 0, 1)
    zl = zl + temple * 0.012 * s
    m = z > zl
    # exclude the face/front below the brow no matter what
    m &= ~((frontness > 0.55) & (z < eye_z + 0.05 * s))
    return m


def beard_mask(verts: np.ndarray, normals: np.ndarray, skel: Skeleton, hs: HeadStyle, moustache: bool = True, cheeks: float = 1.0) -> np.ndarray:
    L = head_landmarks(skel, hs)
    s = L["s"]
    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    eye_z = L["eye_z"]; mouth_z = L["mouth_z"]; chin_z = L["chin_z"]
    lower_face = (z < mouth_z + 0.012 * s) & (z > chin_z - 0.03 * s) & (y < 0.04 * s)
    # jawline sides up to below the cheekbones
    jaw = (z < eye_z - 0.045 * s) & (z > chin_z - 0.03 * s) & (np.abs(x) > 0.03 * s) & (y < 0.05 * s) & (normals[:, 2] < 0.6)
    m = lower_face | (jaw & (cheeks > 0.5))
    # keep off the lips: exclude the mouth slit region unless moustache (above the mouth)
    mouth = (np.abs(x) < L["mouth_w"] * 1.05) & (np.abs(z - mouth_z) < 0.007 * s) & (y < 0.0)
    m &= ~mouth
    if not moustache:
        m &= ~((z > mouth_z) & (np.abs(x) < L["mouth_w"] * 1.3) & (y < 0.0))
    # never under the neck stub / far back
    m &= normals[:, 2] > -0.85
    return m


# --------------------------------------------------------------------------------------
# Blender pipeline (bpy imported lazily)
# --------------------------------------------------------------------------------------

def _bpy():
    import bpy
    return bpy


def select_only(ob) -> None:
    bpy = _bpy()
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def tri_count(ob) -> int:
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def mesh_arrays(ob) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(verts (n,3), vertex normals (n,3), triangles (m,3)) in object space."""
    me = ob.data
    me.calc_loop_triangles()
    n = len(me.vertices)
    verts = np.empty(n * 3)
    me.vertices.foreach_get("co", verts)
    normals = np.empty(n * 3)
    me.vertices.foreach_get("normal", normals)
    tris = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tris)
    return verts.reshape(-1, 3), normals.reshape(-1, 3), tris.reshape(-1, 3)


def set_verts(ob, verts: np.ndarray) -> None:
    ob.data.vertices.foreach_set("co", np.asarray(verts, float).ravel())
    ob.data.update()


def remesh_smooth_decimate(ob, voxel: float, smooth_iters: int = 6, smooth_factor: float = 0.6,
                           target_tris: Optional[int] = None) -> None:
    """Voxel-remesh `ob` in place (unions overlapping parts), smooth the voxel staircase and
    collapse-decimate to `target_tris` (symmetric on X)."""
    bpy = _bpy()
    select_only(ob)
    m = ob.modifiers.new("Remesh", 'REMESH')
    m.mode = 'VOXEL'
    m.voxel_size = voxel
    m.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=m.name)
    if smooth_iters > 0:
        sm = ob.modifiers.new("Smooth", 'SMOOTH')
        sm.factor = smooth_factor
        sm.iterations = smooth_iters
        bpy.ops.object.modifier_apply(modifier=sm.name)
    if target_tris:
        tris = tri_count(ob)
        if tris > target_tris:
            dm = ob.modifiers.new("Decimate", 'DECIMATE')
            dm.decimate_type = 'COLLAPSE'
            dm.ratio = target_tris / tris
            dm.use_symmetry = True
            dm.symmetry_axis = 'X'
            dm.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=dm.name)
    for p in ob.data.polygons:
        p.use_smooth = True


def smart_uv(ob, angle_deg: float = 66.0, margin: float = 0.02) -> None:
    bpy = _bpy()
    select_only(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle_deg), island_margin=margin, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')


def cylindrical_uv(ob, axis_center: np.ndarray, z0: float, z1: float) -> None:
    """UVs by cylindrical projection around a vertical axis (heads): u = angle (seam at the
    back), v = height.  Per-loop so the seam does not smear."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0]
    verts = np.array([v.co[:] for v in me.vertices])
    rel = verts - np.asarray(axis_center, float)
    ang = np.arctan2(rel[:, 0], -rel[:, 1])          # 0 at the front (-Y), +/-pi at the back
    u_all = 0.5 + ang / (2 * math.pi)
    v_all = (verts[:, 2] - z0) / max(z1 - z0, 1e-6)
    for poly in me.polygons:
        us = [u_all[me.loops[l].vertex_index] for l in poly.loop_indices]
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for l, u in zip(poly.loop_indices, us):
            uv.data[l].uv = (u, v_all[me.loops[l].vertex_index])


def auto_weights(ob, arm) -> bool:
    """Blender bone-heat automatic weights; returns True if every vertex got a weight."""
    bpy = _bpy()
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    except Exception as e:  # pragma: no cover
        print("auto weights failed:", e)
        return False
    missing = sum(1 for v in ob.data.vertices if not v.groups)
    if missing:
        print("auto weights left %d verts unweighted" % missing)
    return missing == 0


def weight_matrix(ob, bones: Sequence[str]) -> np.ndarray:
    """(n_verts, len(bones)) weights from vertex groups."""
    gi = {g.name: g.index for g in ob.vertex_groups}
    n = len(ob.data.vertices)
    W = np.zeros((n, len(bones)))
    col = {gi[b]: j for j, b in enumerate(bones) if b in gi}
    for v in ob.data.vertices:
        for g in v.groups:
            if g.group in col:
                W[v.index, col[g.group]] = g.weight
    return W


def apply_weight_matrix(ob, bones: Sequence[str], W: np.ndarray, threshold: float = 0.004) -> None:
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    for j, b in enumerate(bones):
        vg = ob.vertex_groups.new(name=b)
        idx = np.nonzero(W[:, j] > threshold)[0]
        for vi in idx:
            vg.add([int(vi)], float(W[vi, j]), 'REPLACE')


def segment_weights(verts: np.ndarray, skel: Skeleton, bones: Sequence[str], sharpness: float = 2.6) -> np.ndarray:
    """Distance-to-bone-segment weights with a smooth falloff (the fallback/seed field)."""
    n = len(verts)
    W = np.zeros((n, len(bones)))
    for bi, b in enumerate(bones):
        bb = skel.bones[b]
        a, t = bb.head, bb.tail
        ab = t - a
        l2 = max(float(np.dot(ab, ab)), 1e-9)
        u = np.clip(((verts - a) @ ab) / l2, 0.0, 1.0)
        d = np.linalg.norm(verts - (a + u[:, None] * ab), axis=1)
        r = 0.04 + 0.45 * bb.length
        W[:, bi] = np.exp(-((d / r) ** sharpness))
    return W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)


def smooth_weights(W: np.ndarray, tris: np.ndarray, iters: int = 4, factor: float = 0.45) -> np.ndarray:
    """Laplacian smoothing of the weight field across mesh edges (kills creasing at joints)."""
    n = W.shape[0]
    edges = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]], axis=0)
    for _ in range(iters):
        acc = np.zeros_like(W)
        cnt = np.zeros(n)
        np.add.at(acc, edges[:, 0], W[edges[:, 1]])
        np.add.at(acc, edges[:, 1], W[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        W = (1.0 - factor) * W + factor * acc / np.maximum(cnt, 1)[:, None]
        W = np.maximum(W, 0.0)
        W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return W


def limit_influences(W: np.ndarray, max_influences: int = 4) -> np.ndarray:
    n = W.shape[0]
    idx = np.argsort(-W, axis=1)
    keep = np.zeros_like(W)
    for k in range(min(max_influences, W.shape[1])):
        keep[np.arange(n), idx[:, k]] = W[np.arange(n), idx[:, k]]
    return keep / np.maximum(keep.sum(axis=1, keepdims=True), 1e-9)


def skin_to_armature(ob, arm, skel: Skeleton, smooth_iters: int = 3, max_influences: int = 4) -> str:
    """Skin `ob` to `arm`.  Bone-heat automatic weights when they succeed (they respect the
    surface, so no bleed across a gap), seeded segment weights otherwise; then smoothing
    across edges and a 4-influence limit for glTF.  Returns the method used."""
    bpy = _bpy()
    method = "auto"
    if not auto_weights(ob, arm):
        method = "segment"
        verts, normals, tris = mesh_arrays(ob)
        W = segment_weights(verts, skel, rig.DEFORM_NAMES)
        apply_weight_matrix(ob, rig.DEFORM_NAMES, W)
        if not ob.modifiers or not any(m.type == 'ARMATURE' for m in ob.modifiers):
            mod = ob.modifiers.new("Armature", 'ARMATURE')
            mod.object = arm
            ob.parent = arm
    verts, normals, tris = mesh_arrays(ob)
    W = weight_matrix(ob, rig.DEFORM_NAMES)
    empty = W.sum(axis=1) < 1e-6
    if empty.any():
        seed = segment_weights(verts, skel, rig.DEFORM_NAMES)
        W[empty] = seed[empty]
    W = smooth_weights(W, tris, iters=smooth_iters)
    W = limit_influences(W, max_influences)
    apply_weight_matrix(ob, rig.DEFORM_NAMES, W)
    return method


def transfer_weights(dst_ob, src_verts: np.ndarray, src_W: np.ndarray, arm, bones: Sequence[str] = rig.DEFORM_NAMES,
                     k: int = 4, smooth: int = 2) -> None:
    """Skin a garment/part by copying weights from the nearest body vertices (inverse-distance
    over k neighbours), then smoothing.  Keeps every part deforming exactly like the body."""
    verts, normals, tris = mesh_arrays(dst_ob)
    d2 = ((verts[:, None, :] - src_verts[None, :, :]) ** 2).sum(axis=2) if len(src_verts) * len(verts) < 4_000_000 else None
    if d2 is None:
        # chunked nearest-neighbour to keep memory sane
        W = np.zeros((len(verts), len(bones)))
        chunk = max(1, 4_000_000 // max(len(src_verts), 1))
        for i in range(0, len(verts), chunk):
            part = verts[i:i + chunk]
            dd = ((part[:, None, :] - src_verts[None, :, :]) ** 2).sum(axis=2)
            idx = np.argsort(dd, axis=1)[:, :k]
            w = 1.0 / np.maximum(np.take_along_axis(dd, idx, axis=1), 1e-8)
            w /= w.sum(axis=1, keepdims=True)
            W[i:i + chunk] = np.einsum("nk,nkb->nb", w, src_W[idx])
    else:
        idx = np.argsort(d2, axis=1)[:, :k]
        w = 1.0 / np.maximum(np.take_along_axis(d2, idx, axis=1), 1e-8)
        w /= w.sum(axis=1, keepdims=True)
        W = np.einsum("nk,nkb->nb", w, src_W[idx])
    if smooth:
        W = smooth_weights(W, tris, iters=smooth, factor=0.4)
    W = limit_influences(W)
    apply_weight_matrix(dst_ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in dst_ob.modifiers):
        mod = dst_ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    dst_ob.parent = arm


# --------------------------------------------------------------------------------------
# morph targets (analytic displacement fields)
# --------------------------------------------------------------------------------------

def body_morphs(verts: np.ndarray, normals: np.ndarray, skel: Skeleton) -> Dict[str, np.ndarray]:
    """name -> displaced vertex array for the body.  Fields are smooth bumps along normals."""
    J = skel.J
    s = skel.props.height / rig.DEFAULT_HEIGHT
    z = verts[:, 2]
    x = verts[:, 0]
    hip, spine, chest, neck = J["Hips"][2], J["Spine"][2], J["Chest"][2], J["Neck"][2]
    front = np.clip(-normals[:, 1], 0, 1)
    back = np.clip(normals[:, 1], 0, 1)
    side = np.abs(normals[:, 0])
    torso = smoothstep((z - (hip - 0.12 * s)) / (0.06 * s)) * (1 - smoothstep((z - (neck - 0.02 * s)) / (0.05 * s))) * (np.abs(x) < 0.22 * s)
    arms = ((np.abs(x) > 0.20 * s) & (z > chest - 0.05 * s)).astype(float)
    legs = ((z < hip - 0.02 * s) & (np.abs(x) < 0.25 * s)).astype(float)
    out: Dict[str, np.ndarray] = {}

    def disp(field: np.ndarray, amount: float) -> np.ndarray:
        return normals * (field * amount)[:, None]

    belly = gauss3(verts, np.array([0.0, -0.09 * s, spine - 0.02 * s]), (0.17 * s, 0.14 * s, 0.13 * s)) * front
    chest_f = gauss3(verts, np.array([0.0, -0.10 * s, chest + 0.08 * s]), (0.20 * s, 0.12 * s, 0.10 * s)) * front
    love = gauss3(verts, np.array([0.0, 0.02 * s, hip + 0.02 * s]), (0.2 * s, 0.16 * s, 0.10 * s)) * side
    butt = gauss3(verts, np.array([0.0, 0.10 * s, hip - 0.04 * s]), (0.16 * s, 0.10 * s, 0.10 * s)) * back
    thigh = legs * smoothstep((z - (hip - 0.45 * s)) / (0.1 * s)) * (1 - smoothstep((z - (hip - 0.05 * s)) / (0.04 * s)))
    upper_arm = arms * smoothstep((z - (chest - 0.05 * s)) / (0.08 * s))
    neck_f = gauss3(verts, np.array([0.0, 0.0, neck + 0.04 * s]), (0.08 * s, 0.08 * s, 0.05 * s))
    calf = legs * gauss3(verts, np.array([0.0, 0.02 * s, hip - 0.62 * s]), (0.3 * s, 0.1 * s, 0.08 * s))
    heavy = 0.075 * belly + 0.025 * chest_f + 0.03 * love + 0.035 * butt + 0.022 * thigh + 0.022 * upper_arm + 0.014 * neck_f + 0.012 * calf + 0.006 * torso
    out["heavy"] = verts + disp(heavy, s)
    slight = -(0.022 * torso + 0.012 * thigh + 0.012 * upper_arm + 0.02 * belly + 0.01 * butt + 0.006 * calf)
    out["slight"] = verts + disp(slight, s)
    muscular = 0.02 * chest_f + 0.018 * upper_arm + 0.014 * thigh + 0.012 * calf + gauss3(verts, np.array([0.0, 0.06 * s, chest + 0.06 * s]), (0.16 * s, 0.1 * s, 0.12 * s)) * back * 0.015 - 0.01 * belly
    out["muscular"] = verts + disp(muscular, s)
    bust = (gauss3(verts, np.array([0.07 * s, -0.11 * s, chest + 0.065 * s]), (0.055 * s, 0.06 * s, 0.05 * s)) +
            gauss3(verts, np.array([-0.07 * s, -0.11 * s, chest + 0.065 * s]), (0.055 * s, 0.06 * s, 0.05 * s))) * front
    waist = gauss3(verts, np.array([0.0, 0.0, spine + 0.03 * s]), (0.3 * s, 0.3 * s, 0.05 * s)) * side
    hips_w = gauss3(verts, np.array([0.0, 0.0, hip - 0.05 * s]), (0.3 * s, 0.3 * s, 0.07 * s)) * side
    feminine = 0.03 * bust - 0.02 * waist + 0.02 * hips_w + 0.012 * butt - 0.008 * upper_arm - 0.006 * neck_f
    out["feminine"] = verts + disp(feminine, s)
    old = 0.02 * belly - 0.006 * chest_f + 0.006 * neck_f - 0.006 * upper_arm - 0.004 * thigh
    out["old"] = verts + disp(old, s)
    return out


def head_morphs(verts: np.ndarray, normals: np.ndarray, skel: Skeleton, hs: HeadStyle) -> Dict[str, np.ndarray]:
    L = head_landmarks(skel, hs)
    s = L["s"]
    eye_z, mouth_z, chin_z = L["eye_z"], L["mouth_z"], L["chin_z"]
    fy = L["face_y"]
    out: Dict[str, np.ndarray] = {}

    def disp(field: np.ndarray, amount: float) -> np.ndarray:
        return normals * (field * amount)[:, None]

    jowl = (gauss3(verts, np.array([0.05 * s, fy + 0.04 * s, mouth_z - 0.01 * s]), (0.03 * s, 0.035 * s, 0.03 * s)) +
            gauss3(verts, np.array([-0.05 * s, fy + 0.04 * s, mouth_z - 0.01 * s]), (0.03 * s, 0.035 * s, 0.03 * s)))
    chin = gauss3(verts, np.array([0.0, fy + 0.02 * s, chin_z - 0.01 * s]), (0.04 * s, 0.04 * s, 0.025 * s))
    cheek = (gauss3(verts, np.array([0.05 * s, fy + 0.03 * s, eye_z - 0.035 * s]), (0.028 * s, 0.03 * s, 0.028 * s)) +
             gauss3(verts, np.array([-0.05 * s, fy + 0.03 * s, eye_z - 0.035 * s]), (0.028 * s, 0.03 * s, 0.028 * s)))
    neck = (verts[:, 2] < L["head"][2] + 0.03 * s).astype(float)
    out["heavy"] = verts + disp(0.012 * jowl + 0.012 * chin + 0.008 * cheek + 0.006 * neck, s)
    out["slight"] = verts + disp(-0.010 * cheek - 0.005 * jowl - 0.004 * chin, s)
    jaw_side = np.abs(normals[:, 0]) * ((verts[:, 2] < eye_z - 0.03 * s) & (verts[:, 2] > chin_z - 0.02 * s) & (verts[:, 1] < 0.03 * s))
    brow = gauss3(verts, np.array([0.0, fy, L["brow_z"]]), (0.06 * s, 0.03 * s, 0.012 * s))
    out["feminine"] = verts + disp(-0.008 * jaw_side - 0.004 * brow + 0.004 * cheek - 0.004 * chin, s)
    out["old"] = verts + disp(0.006 * jowl - 0.006 * cheek + 0.003 * chin, s)
    return out


def add_shape_keys(ob, targets: Dict[str, np.ndarray]) -> None:
    if ob.data.shape_keys is None:
        ob.shape_key_add(name="Basis", from_mix=False)
    for name, verts in targets.items():
        kb = ob.shape_key_add(name=name, from_mix=False)
        kb.data.foreach_set("co", np.asarray(verts, float).ravel())
        kb.value = 0.0


def apply_morph_mix(verts: np.ndarray, morphs: Dict[str, np.ndarray], mix: Dict[str, float]) -> np.ndarray:
    """Bake a weighted morph mix into vertices (the forge exports baked bodies, not shape keys,
    so Godot only has to pick a variant)."""
    out = verts.copy()
    for name, w in mix.items():
        if abs(w) < 1e-4 or name not in morphs:
            continue
        out += (morphs[name] - verts) * w
    return out
