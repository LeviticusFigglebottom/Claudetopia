"""Humanoid animation DSL and generators for WM_Humanoid_v1 (docs/CONTRACTS.md §3).

Pure Python + numpy; Blender is only needed by `bake_to_blender`.

Vocabulary
----------
* A *pose* is a dict `bone -> (f, s, t)` of anatomical angles in degrees (see
  `rig.Skeleton._build_anat_frames` for the meaning per bone), plus the optional key
  `"Hips@pos": (forward, left, up)` in metres (offset from the rest hips position).
  Missing bones mean "rest".
* A *track* is a list of keys `(time, pose, ease)`; sampling interpolates each channel
  between neighbouring keys with the ease of the key being approached.
* *Layers* are additive functions `t -> pose` (breathing, head look, sway).
* `ClipBuilder` assembles keys, layers, events and an optional *foot plan*.  When
  legs are "grounded", leg bones are solved by two-bone IK so the feet stay planted
  where the plan says (no sliding), whatever the hips do.
* Generators (`gait_clip`, `swing_clip`, `roll_clip`, `fall_clip`) produce ClipBuilders.
* `BakedClip` holds per-frame bone-local (quaternion, translation) ready for Blender.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig
from .rig import Skeleton, FWD, UP, LEFT

BACKWARD = -FWD

Pose = Dict[str, Tuple[float, ...]]
FPS = 30
HIPS_POS = "Hips@pos"
LEG_BONES = ["UpperLeg.L", "LowerLeg.L", "Foot.L", "Toe.L", "UpperLeg.R", "LowerLeg.R", "Foot.R", "Toe.R"]
ARM_BONES = ["Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R"]
AXIAL_BONES = ["Hips", "Spine", "Chest", "Neck", "Head"]


# --------------------------------------------------------------------------------------
# easing
# --------------------------------------------------------------------------------------

def ease(kind: str, x: float) -> float:
    x = min(1.0, max(0.0, x))
    if kind == "linear":
        return x
    if kind == "smooth":
        return x * x * (3 - 2 * x)
    if kind == "smoother":
        return x * x * x * (x * (x * 6 - 15) + 10)
    if kind == "in":          # slow start, fast end (anticipation build-up)
        return x * x * x
    if kind == "in2":
        return x * x
    if kind == "out":         # fast start, slow end (strike, settle)
        return 1 - (1 - x) ** 3
    if kind == "out2":
        return 1 - (1 - x) ** 2
    if kind == "snap":        # very fast start (impact)
        return 1 - (1 - x) ** 5
    if kind == "hold":        # step at the end
        return 0.0 if x < 1.0 else 1.0
    if kind == "overshoot":   # goes past the target and comes back
        s = 1.70158
        x -= 1
        return x * x * ((s + 1) * x + s) + 1
    if kind == "bounce":
        return 1 - abs(math.cos(x * math.pi * 1.5)) * (1 - x) ** 2
    raise ValueError(kind)


def lerp(a: float, b: float, x: float) -> float:
    return a + (b - a) * x


def clamp01(x: float) -> float:
    return min(1.0, max(0.0, x))


def phase_window(t: float, t0: float, t1: float) -> float:
    """0..1 progress of t through [t0, t1], clamped."""
    if t1 <= t0:
        return 1.0 if t >= t1 else 0.0
    return clamp01((t - t0) / (t1 - t0))


# --------------------------------------------------------------------------------------
# pose algebra
# --------------------------------------------------------------------------------------

def _chan_len(bone: str) -> int:
    return 3


def pose_add(*poses: Pose) -> Pose:
    out: Dict[str, np.ndarray] = {}
    for p in poses:
        for k, v in p.items():
            v = np.asarray(v, dtype=float)
            out[k] = out[k] + v if k in out else v.copy()
    return {k: tuple(v) for k, v in out.items()}


def pose_scale(p: Pose, s: float) -> Pose:
    return {k: tuple(np.asarray(v, float) * s) for k, v in p.items()}


def pose_lerp(a: Pose, b: Pose, x: float) -> Pose:
    keys = set(a) | set(b)
    out: Pose = {}
    for k in keys:
        va = np.asarray(a.get(k, (0.0, 0.0, 0.0)), float)
        vb = np.asarray(b.get(k, (0.0, 0.0, 0.0)), float)
        out[k] = tuple(va + (vb - va) * x)
    return out


def mirror_pose(p: Pose) -> Pose:
    """Left/right mirror.  Anatomical frames are mirrored for .R bones, so limb angles copy
    across unchanged; axial side/turn channels flip sign; hips lateral offset flips."""
    out: Pose = {}
    for k, v in p.items():
        if k == HIPS_POS:
            out[k] = (v[0], -v[1], v[2])
        elif k.endswith(".L") or k.endswith(".R"):
            out[rig.mirror_name(k)] = tuple(v)
        else:
            out[k] = (v[0], -v[1], -v[2])
    return out


# --------------------------------------------------------------------------------------
# tracks
# --------------------------------------------------------------------------------------

@dataclass
class Key:
    t: float
    pose: Pose
    ease: str = "smooth"


class Track:
    """Keyed channels with per-key easing; channels missing in a key hold their
    previous value (or rest) so authors only need to write what changes... unless
    `sparse=False`, where missing channels are treated as rest (0)."""

    def __init__(self, loop: bool = False, length: float = 1.0, sparse: bool = True):
        self.keys: List[Key] = []
        self.loop = loop
        self.length = length
        self.sparse = sparse

    def key(self, t: float, pose: Pose, ease_kind: str = "smooth") -> "Track":
        self.keys.append(Key(t, dict(pose), ease_kind))
        self.keys.sort(key=lambda k: k.t)
        return self

    def channels(self) -> List[str]:
        out: List[str] = []
        for k in self.keys:
            for c in k.pose:
                if c not in out:
                    out.append(c)
        return out

    def _channel_keys(self, c: str) -> List[Tuple[float, np.ndarray, str]]:
        """Explicit key list for one channel.  Sparse semantics: a key that does not mention
        the channel holds the channel's value from the previous key (rest before the first
        mention), so a channel first keyed at K_j eases in from rest at K_{j-1}."""
        ks = []
        # Angle channels default to rest (zero) before their first mention, so a bone keyed
        # late eases in from rest.  Target channels ("Hand.R@ik" and friends) have no rest
        # pose, so they hold their first keyed value instead.
        first = next((np.asarray(k.pose[c], float) for k in self.keys if c in k.pose), np.zeros(3))
        prev = first.copy() if "@" in c and c != HIPS_POS else np.zeros(3)
        for k in self.keys:
            if c in k.pose:
                prev = np.asarray(k.pose[c], float)
                ks.append((k.t, prev, k.ease))
            else:
                ks.append((k.t, prev.copy(), k.ease))
        return ks

    def sample(self, t: float) -> Pose:
        out: Pose = {}
        for c in self.channels():
            ks = self._channel_keys(c)
            if not ks:
                continue
            if self.loop and len(ks) > 1:
                # wrap: append first key at t+length for seamless loops
                t0, v0, e0 = ks[0]
                ks = ks + [(t0 + self.length, v0, e0)]
                tt = t % self.length
                if tt < ks[0][0]:
                    tt += self.length
            else:
                tt = t
            if tt <= ks[0][0]:
                out[c] = tuple(ks[0][1])
                continue
            if tt >= ks[-1][0]:
                out[c] = tuple(ks[-1][1])
                continue
            for i in range(len(ks) - 1):
                ta, va, _ = ks[i]
                tb, vb, eb = ks[i + 1]
                if ta <= tt <= tb:
                    x = ease(eb, (tt - ta) / max(tb - ta, 1e-9))
                    out[c] = tuple(va + (vb - va) * x)
                    break
        return out


# --------------------------------------------------------------------------------------
# foot plan (for grounded legs)
# --------------------------------------------------------------------------------------

@dataclass
class FootStep:
    t_lift: float
    t_land: float
    to_pos: np.ndarray          # ankle target at landing (armature space)
    height: float = 0.08
    to_yaw: float = 0.0         # radians, toes direction (0 = forward)
    ease_kind: str = "smooth"


@dataclass
class FootState:
    pos: np.ndarray
    yaw: float = 0.0
    pitch: float = 0.0          # radians; + = toes up
    planted: bool = True


class FootPlan:
    """Where each foot is over time.  Feet start planted at their rest ankle position
    (or `start`), steps move them with a lifted arc.  `pitch(t)` can be authored too."""

    def __init__(self, skel: Skeleton):
        self.skel = skel
        self.start: Dict[str, Tuple[np.ndarray, float]] = {
            "L": (skel.J["Foot.L"].copy(), 0.0), "R": (skel.J["Foot.R"].copy(), 0.0)}
        self.steps: Dict[str, List[FootStep]] = {"L": [], "R": []}
        self.pitch_fn: Dict[str, Optional[Callable[[float], float]]] = {"L": None, "R": None}
        self.pos_fn: Dict[str, Optional[Callable[[float], Optional[Tuple[np.ndarray, float, float]]]]] = {"L": None, "R": None}

    def place(self, side: str, pos, yaw: float = 0.0) -> "FootPlan":
        self.start[side] = (np.asarray(pos, float), yaw)
        return self

    def step(self, side: str, t_lift: float, t_land: float, to_pos, height: float = 0.08, to_yaw: float = 0.0,
             ease_kind: str = "smooth") -> "FootPlan":
        self.steps[side].append(FootStep(t_lift, t_land, np.asarray(to_pos, float), height, to_yaw, ease_kind))
        self.steps[side].sort(key=lambda s: s.t_lift)
        return self

    def state(self, side: str, t: float) -> FootState:
        if self.pos_fn[side] is not None:
            r = self.pos_fn[side](t)
            if r is not None:
                planted = True
                if len(r) == 4:
                    pos, yaw, pitch, planted = r
                else:
                    pos, yaw, pitch = r
                return FootState(np.asarray(pos, float), yaw, pitch, bool(planted))
        pos, yaw = self.start[side]
        pos = pos.copy()
        planted = True
        pitch = 0.0
        for st in self.steps[side]:
            if t >= st.t_land:
                pos, yaw = st.to_pos.copy(), st.to_yaw
            elif t >= st.t_lift:
                x = phase_window(t, st.t_lift, st.t_land)
                xe = ease(st.ease_kind, x)
                p = pos + (st.to_pos - pos) * xe
                p[2] += st.height * math.sin(math.pi * x)
                yaw = lerp(yaw, st.to_yaw, xe)
                pitch = math.radians(-20.0) * math.sin(math.pi * x) * (1 - x) + math.radians(12.0) * math.sin(math.pi * x) * x
                pos, planted = p, False
                break
        if self.pitch_fn[side] is not None:
            pitch += self.pitch_fn[side](t)
        return FootState(pos, yaw, pitch, planted)


# --------------------------------------------------------------------------------------
# baked clips
# --------------------------------------------------------------------------------------

@dataclass
class BakedClip:
    name: str
    length: float
    loop: bool
    fps: int
    events: List[Tuple[float, str]]
    bones: List[str]
    quats: Dict[str, np.ndarray]     # bone -> (F, 4) w,x,y,z (local)
    hips_pos: np.ndarray             # (F, 3) bone-local translation of Hips
    extra: dict = field(default_factory=dict)

    @property
    def frames(self) -> int:
        return int(self.quats[self.bones[0]].shape[0])

    def sidecar(self) -> dict:
        d = {"loop": self.loop, "length": round(self.length, 4),
             "events": [{"t": round(t, 4), "name": n} for t, n in sorted(self.events)]}
        d.update(self.extra)
        return d


# --------------------------------------------------------------------------------------
# clip builder
# --------------------------------------------------------------------------------------

class ClipBuilder:
    def __init__(self, skel: Skeleton, name: str, length: float, loop: bool = False, fps: int = FPS,
                 grounded: bool = True, sparse: bool = True):
        self.skel = skel
        self.name = name
        self.length = float(length)
        self.loop = loop
        self.fps = fps
        self.track = Track(loop=loop, length=length, sparse=sparse)
        self.layers: List[Callable[[float], Pose]] = []
        self.events: List[Tuple[float, str]] = []
        self.grounded = grounded
        self.feet = FootPlan(skel)
        self.knee_pole = np.array([0.0, -1.0, 0.0])
        self.extra: dict = {}
        # direct per-frame override: fn(t, pose) -> pose  (used by generators)
        self.post: List[Callable[[float, Pose], Pose]] = []
        # per-frame local matrix overrides (bone -> (R, t)) computed by solvers
        self.solvers: List[Callable[[float, Dict[str, np.ndarray], Dict[str, Tuple[np.ndarray, np.ndarray]]], None]] = []

    # authoring ---------------------------------------------------------------------
    def key(self, t: float, pose: Pose, ease_kind: str = "smooth") -> "ClipBuilder":
        self.track.key(t, pose, ease_kind)
        return self

    def layer(self, fn: Callable[[float], Pose]) -> "ClipBuilder":
        self.layers.append(fn)
        return self

    def event(self, t: float, name: str) -> "ClipBuilder":
        self.events.append((float(t), name))
        return self

    def events_at(self, **kw) -> "ClipBuilder":
        for n, t in kw.items():
            self.event(t, n)
        return self

    # sampling ------------------------------------------------------------------------
    def sample_pose(self, t: float) -> Pose:
        p = self.track.sample(t)
        for fn in self.layers:
            p = pose_add(p, fn(t))
        for fn in self.post:
            p = fn(t, p)
        return p

    def local_pose(self, t: float, pose: Optional[Pose] = None) -> Dict[str, Tuple[np.ndarray, np.ndarray]]:
        """Resolve the anatomical pose at t into bone-local (R, translation) for every bone,
        solving grounded legs by IK."""
        sk = self.skel
        pose = self.sample_pose(t) if pose is None else pose
        local: Dict[str, Tuple[np.ndarray, np.ndarray]] = {}
        for bone, v in pose.items():
            if "@" in bone:
                continue
            if bone not in sk.bones:
                raise KeyError(f"{self.name}: unknown bone {bone}")
            local[bone] = (sk.pose_rotation(bone, *v), None)
        hp = pose.get(HIPS_POS, (0.0, 0.0, 0.0))
        hips_world = FWD * hp[0] + LEFT * hp[1] + UP * hp[2]
        R_h = local.get("Hips", (None, None))[0]
        local["Hips"] = (R_h, sk.local_translation("Hips", hips_world))
        for side in ("L", "R"):
            if f"Hand.{side}@grip" in pose:
                # authored by where the weapon grip should be: solve for the hand that puts
                # the socket there (two passes are enough, the offset is short and rigid)
                p2 = dict(pose)
                p2[f"Hand.{side}@ik"] = tuple(np.asarray(pose[f"Hand.{side}@grip"], float))
                for _ in range(2):
                    self._solve_arm(local, side, p2)
                    Wg = sk.fk(local)
                    socket = "Socket.WeaponL" if side == "L" else "Socket.WeaponR"
                    off = sk.joint_world(Wg, socket) - sk.joint_world(Wg, f"Hand.{side}")
                    p2[f"Hand.{side}@ik"] = tuple(np.asarray(pose[f"Hand.{side}@grip"], float) - off)
                self._solve_arm(local, side, p2)
            elif f"Hand.{side}@ik" in pose:
                self._solve_arm(local, side, pose)
        if self.grounded:
            W = sk.fk(local)
            for side in ("L", "R"):
                fs = self.feet.state(side, t)
                self._solve_leg(W, local, side, fs)
        for s in self.solvers:
            W = sk.fk(local)
            s(t, W, local)
        return local

    def _solve_arm(self, local, side: str, pose: Pose) -> None:
        """Place the hand at `Hand.S@ik` (armature space) by two-bone IK, then, if
        `Hand.S@aim` is given, roll the hand so the weapon socket's +Y (the blade) points
        that way; `Hand.S@roll` twists about the blade."""
        sk = self.skel
        up, lo, hand = f"UpperArm.{side}", f"LowerArm.{side}", f"Hand.{side}"
        target = np.asarray(pose[f"Hand.{side}@ik"], float)
        W = sk.fk(local)
        sh = sk.joint_world(W, up)
        to = target - sh
        pole = pose.get(f"Hand.{side}@pole")
        if pole is None:
            # elbow hangs down and back, and out to the side, relative to the reach direction
            out = LEFT if side == "L" else -LEFT
            p = -UP * 1.0 + BACKWARD * 0.55 + out * 0.45
            # when reaching high the elbow swings outward rather than down
            if to[2] > 0.15:
                p = out * 1.0 - UP * 0.35 + BACKWARD * 0.3
            pole = p
        pole = np.asarray(pole, float)
        Ru, Rl = sk.ik_two_bone(W, up, lo, target, pole)
        local[up] = (Ru, None)
        local[lo] = (Rl, None)
        aim = pose.get(f"Hand.{side}@aim")
        if aim is None:
            local[hand] = (sk.pose_rotation(hand, *pose.get(hand, (0.0, 0.0, 0.0))), None)
            return
        W2 = sk.fk(local)
        socket = "Socket.WeaponL" if side == "L" else "Socket.WeaponR"
        srl = sk.bones[socket].rest_local[:3, :3]
        v_hand = srl @ np.array([0.0, 1.0, 0.0])          # blade direction in Hand-local space
        parent_R = (W2[lo] @ sk.bones[hand].rest_local)[:3, :3]
        a_local = parent_R.T @ rig._unit(np.asarray(aim, float))
        R = rig.min_rot(v_hand, a_local)
        roll = float(pose.get(f"Hand.{side}@roll", (0.0, 0.0, 0.0))[0]) if f"Hand.{side}@roll" in pose else 0.0
        if abs(roll) > 1e-6:
            R = rig.rot_axis(a_local, math.radians(roll)) @ R
        local[hand] = (R, None)

    def _solve_leg(self, W, local, side: str, fs: FootState) -> None:
        sk = self.skel
        up, lo, ft, toe = f"UpperLeg.{side}", f"LowerLeg.{side}", f"Foot.{side}", f"Toe.{side}"
        yaw_R = rig.rot_axis(UP, fs.yaw)
        pole = yaw_R @ self.knee_pole
        # pole slightly outward so knees do not knock
        pole = pole + (LEFT if side == "L" else -LEFT) * 0.15
        # foot bone target orientation: rest foot frame, pitched then yawed
        fb = sk.bones[ft]
        rest_dir = fb.tail - fb.head
        lateral = np.cross(UP, rest_dir)
        lateral = lateral / np.linalg.norm(lateral)
        pitch_R = rig.rot_axis(lateral, -fs.pitch)   # + pitch = toes up
        Rw = yaw_R @ pitch_R
        # ankle target: the plan gives the ankle position for a flat foot; when pitched about
        # the heel (toes up) or the ball (toes down) the ankle moves accordingly
        ankle = fs.pos.copy()
        if fs.pitch > 1e-4:      # heel pivot
            heel = fb.head + np.array([0.0, 0.06, -fb.head[2]]) * (sk.props.height / rig.DEFAULT_HEIGHT)
            off = fb.head - heel
            ankle = fs.pos - off + Rw @ off if False else fs.pos + (Rw @ off - off)
        elif fs.pitch < -1e-4:   # ball pivot
            ball = sk.J[toe]
            off = fb.head - ball
            ankle = fs.pos + (Rw @ off - off)
        Ru, Rl = sk.ik_two_bone(W, up, lo, ankle, pole)
        local[up] = (Ru, None)
        local[lo] = (Rl, None)
        W2 = sk.fk(local)
        foot_dir = Rw @ rest_dir
        foot_front = Rw @ fb.rest[:3, 2]
        local[ft] = (sk.aim_rotation(W2, ft, foot_dir, foot_front), None)
        # toes: keep flat on the ground when the heel is up
        if fs.pitch < -1e-4:
            local[toe] = (sk.pose_rotation(toe, math.degrees(-fs.pitch) * 0.8, 0, 0), None)
        else:
            local[toe] = (sk.pose_rotation(toe, 0, 0, 0), None)

    # baking --------------------------------------------------------------------------
    def bake(self) -> BakedClip:
        sk = self.skel
        n = int(round(self.length * self.fps))
        n = max(n, 1)
        times = [i / self.fps for i in range(n + 1)]
        bones = [b for b in sk.order if b != "Root" and not b.startswith("Socket")]
        quats = {b: np.zeros((n + 1, 4)) for b in bones}
        hips = np.zeros((n + 1, 3))
        prev: Dict[str, np.ndarray] = {}
        for i, t in enumerate(times):
            local = self.local_pose(t)
            for b in bones:
                R, tr = local.get(b, (None, None))
                q = rig.mat_to_quat(R) if R is not None else np.array([1.0, 0, 0, 0])
                if b in prev and np.dot(prev[b], q) < 0:
                    q = -q
                prev[b] = q
                quats[b][i] = q
                if b == "Hips" and tr is not None:
                    hips[i] = tr
        return BakedClip(self.name, self.length, self.loop, self.fps, list(self.events), bones, quats, hips, dict(self.extra))


# --------------------------------------------------------------------------------------
# body-relative authoring helpers
# --------------------------------------------------------------------------------------

def body_point(skel: Skeleton, fwd: float, left: float, up: float, origin: str = "Chest") -> np.ndarray:
    """A point in armature space from body-relative offsets (metres at the default height,
    scaled with the character).  Handy for authoring where a hand or a weapon should be."""
    s = skel.props.height / rig.DEFAULT_HEIGHT
    return skel.J[origin] + (FWD * fwd + LEFT * left + UP * up) * s


def arc_point(centre: np.ndarray, normal: np.ndarray, ref: np.ndarray, radius: float, angle_deg: float) -> np.ndarray:
    """A point on a circle: `ref` is the direction from the centre at angle 0, `normal` the
    axis the angle turns about (right-handed)."""
    n = rig._unit(np.asarray(normal, float))
    r0 = np.asarray(ref, float)
    r0 = rig._unit(r0 - np.dot(r0, n) * n)
    return np.asarray(centre, float) + (rig.rot_axis(n, math.radians(angle_deg)) @ r0) * radius


def two_hand_grip(right_hand: np.ndarray, blade_dir: np.ndarray, sep: float = 0.135) -> np.ndarray:
    """Where the left hand goes on a two-handed grip: below the right hand on the haft."""
    return np.asarray(right_hand, float) - rig._unit(np.asarray(blade_dir, float)) * sep


# --------------------------------------------------------------------------------------
# additive layers
# --------------------------------------------------------------------------------------

def breathing(period: float = 3.4, amount: float = 1.0, phase: float = 0.0) -> Callable[[float], Pose]:
    def fn(t: float) -> Pose:
        b = math.sin(2 * math.pi * t / period + phase)
        return {"Chest": (-1.2 * amount * b, 0, 0), "Spine": (0.6 * amount * b, 0, 0), "Neck": (0.8 * amount * b, 0, 0),
                "Shoulder.L": (0, 1.5 * amount * b, 0), "Shoulder.R": (0, 1.5 * amount * b, 0),
                HIPS_POS: (0, 0, 0.003 * amount * b)}
    return fn


def head_look(period: float = 5.0, yaw: float = 8.0, pitch: float = 3.0, phase: float = 0.0) -> Callable[[float], Pose]:
    def fn(t: float) -> Pose:
        a = 2 * math.pi * t / period + phase
        y = yaw * (0.6 * math.sin(a) + 0.4 * math.sin(2.3 * a + 1.0))
        p = pitch * math.sin(1.7 * a + 0.5)
        return {"Head": (p, 0, y * 0.7), "Neck": (p * 0.4, 0, y * 0.3)}
    return fn


def sway(period: float = 4.0, amount: float = 1.0, phase: float = 0.0) -> Callable[[float], Pose]:
    def fn(t: float) -> Pose:
        a = 2 * math.pi * t / period + phase
        return {HIPS_POS: (0.004 * amount * math.sin(a * 0.7), 0.006 * amount * math.sin(a), 0),
                "Spine": (0, 0.8 * amount * math.sin(a + 0.3), 0), "Chest": (0, -0.5 * amount * math.sin(a + 0.3), 0)}
    return fn


def periodic(fn_period: float, fn: Callable[[float], Pose]) -> Callable[[float], Pose]:
    return lambda t: fn((t % fn_period) / fn_period)


# --------------------------------------------------------------------------------------
# pose vocabulary (default proportions, degrees)
# --------------------------------------------------------------------------------------

ARMS_DOWN: Pose = {"UpperArm.L": (4, -46, 0), "UpperArm.R": (4, -46, 0), "LowerArm.L": (14, 0, 0), "LowerArm.R": (14, 0, 0),
                   "Hand.L": (0, 0, 0), "Hand.R": (0, 0, 0)}
STAND: Pose = pose_add(ARMS_DOWN, {"Spine": (2, 0, 0), "Chest": (-1, 0, 0), "Neck": (2, 0, 0), "Head": (-2, 0, 0)})
# one-handed guard: right hand raised, weapon in front; left forearm up as if holding a shield
GUARD_1H: Pose = {"Hips": (0, 0, -12), "Spine": (6, 0, 4), "Chest": (4, 0, 8), "Neck": (0, 0, -4), "Head": (2, 0, 0),
                  "Shoulder.R": (6, 4, 0), "UpperArm.R": (48, -22, 10), "LowerArm.R": (98, 0, 0), "Hand.R": (-10, 18, 0),
                  "Shoulder.L": (12, 2, 0), "UpperArm.L": (52, -32, 0), "LowerArm.L": (92, 0, 0), "Hand.L": (0, 0, 0),
                  HIPS_POS: (0.0, 0.0, -0.03)}
GUARD_2H: Pose = {"Hips": (0, 0, -22), "Spine": (8, 0, 8), "Chest": (6, 0, 12), "Neck": (0, 0, -10), "Head": (2, 0, -8),
                  "Shoulder.R": (8, 6, 0), "UpperArm.R": (60, -28, 0), "LowerArm.R": (100, 0, 0), "Hand.R": (-10, 10, 0),
                  "Shoulder.L": (14, 4, 0), "UpperArm.L": (58, -34, 0), "LowerArm.L": (84, 0, 0), "Hand.L": (-10, -10, 0),
                  HIPS_POS: (0.0, 0.0, -0.04)}
GUARD_DAGGER: Pose = {"Hips": (0, 0, -14), "Spine": (12, 0, 6), "Chest": (6, 0, 6), "Neck": (-2, 0, -4),
                      "UpperArm.R": (38, -34, 0), "LowerArm.R": (110, 0, 0), "Hand.R": (-14, 0, 0),
                      "UpperArm.L": (50, -28, 0), "LowerArm.L": (100, 0, 0), HIPS_POS: (0.0, 0.0, -0.06)}
GUARD_UNARMED: Pose = {"Hips": (0, 0, -18), "Spine": (10, 0, 8), "Chest": (6, 0, 8), "Neck": (-2, 0, -6),
                       "UpperArm.R": (50, -30, 0), "LowerArm.R": (125, 0, 0), "Hand.R": (-20, 0, 0),
                       "UpperArm.L": (62, -30, 0), "LowerArm.L": (120, 0, 0), "Hand.L": (-20, 0, 0), HIPS_POS: (0.0, 0.0, -0.05)}
CROUCH: Pose = {"Spine": (26, 0, 0), "Chest": (10, 0, 0), "Neck": (-18, 0, 0), "Head": (-10, 0, 0),
                "UpperArm.L": (30, -36, 0), "UpperArm.R": (30, -36, 0), "LowerArm.L": (60, 0, 0), "LowerArm.R": (60, 0, 0),
                HIPS_POS: (0.02, 0.0, -0.24)}


def stance_feet(plan: FootPlan, spread: float = 0.0, forward_l: float = 0.0, forward_r: float = 0.0,
                yaw_l: float = 0.0, yaw_r: float = 0.0) -> None:
    """Set starting foot positions: extra lateral spread and per-foot forward offsets (m)."""
    sk = plan.skel
    l = sk.J["Foot.L"].copy(); r = sk.J["Foot.R"].copy()
    l[0] += spread; r[0] -= spread
    l[1] -= forward_l; r[1] -= forward_r
    plan.place("L", l, math.radians(yaw_l)); plan.place("R", r, math.radians(yaw_r))


# --------------------------------------------------------------------------------------
# gait generator
# --------------------------------------------------------------------------------------

@dataclass
class GaitParams:
    speed: float = 1.5            # m/s along `direction`
    period: float = 1.0           # cycle seconds
    duty: float = 0.62            # stance fraction per foot
    direction: Tuple[float, float] = (0.0, 1.0)   # (left, forward) unit direction of travel
    step_height: float = 0.07
    hip_bob: float = 0.025
    hip_sway: float = 0.02
    hip_yaw: float = 6.0          # degrees pelvis rotation
    hip_roll: float = 3.0
    lean: float = 3.0             # forward lean degrees (spine)
    arm_swing: float = 26.0
    arm_bend: float = 22.0        # elbow bend baseline
    arm_bend_swing: float = 18.0
    arm_adduct: float = -44.0     # UpperArm side (A-pose -> arms down)
    hands_up: bool = False        # run: forearms pumping ~90 deg
    crouch: float = 0.0           # hips drop (m) (sneak)
    stance_width: float = 1.0     # multiplier on lateral foot spacing
    heel_roll: float = 1.0        # 0 = flat-footed
    chest_counter: float = 1.0
    head_bob: float = 1.0
    flight: bool = False
    torso_forward: float = 0.0    # hips forward offset (m)
    extra_pose: Pose = field(default_factory=dict)
    knee_lift: float = 1.0


def gait_clip(skel: Skeleton, name: str, gp: GaitParams, footstep_events: bool = True) -> ClipBuilder:
    """Cyclic in-place locomotion with foot-lock.  Left foot contacts at phase 0, right at 0.5.
    The planted foot slides *backwards* along the travel direction at `speed` (the world moves,
    the character stays), so there is no foot sliding when the game moves the actor at that speed."""
    cb = ClipBuilder(skel, name, gp.period, loop=True, grounded=True)
    cb.extra["speed"] = round(gp.speed, 3)
    s = skel.props.height / rig.DEFAULT_HEIGHT
    T = gp.period
    d = np.array([gp.direction[0], gp.direction[1]], float)
    d = d / max(np.linalg.norm(d), 1e-9)
    travel_dir = LEFT * d[0] + FWD * d[1]            # armature-space unit vector of travel
    L = gp.speed * gp.duty * T                        # planted-foot travel
    ankle_l0 = skel.J["Foot.L"].copy(); ankle_r0 = skel.J["Foot.R"].copy()
    lateral_dir = np.cross(UP, travel_dir)
    lateral_dir /= max(np.linalg.norm(lateral_dir), 1e-9)
    backward = abs(d[1]) > 0.5 and d[1] < 0
    strafing = abs(d[0]) > 0.5
    ankle_z = ankle_l0[2]
    heel_off = np.array([0.0, 0.06 * s, -ankle_z])   # ankle -> heel
    ball = skel.J["Toe.L"]
    ball_off = ball - ankle_l0                        # ankle -> ball (left)

    def foot_fn(side: str):
        base = (ankle_l0 if side == "L" else ankle_r0).copy()
        base[0] *= gp.stance_width
        contact = 0.0 if side == "L" else 0.5
        sign = 1.0 if side == "L" else -1.0

        def fn(t: float):
            ph = ((t / T) - contact) % 1.0           # 0 at contact
            if ph < gp.duty:                         # stance
                u = ph / gp.duty
                along = (0.5 - u) * L                # + ahead at contact, - behind at lift
                pos = base + travel_dir * along
                if strafing:
                    pos = pos + travel_dir * 0.0
                pitch = 0.0
                if gp.heel_roll > 0 and not backward and not strafing:
                    # heel strike: toes up, flatten during first 18%; heel rise last 28%
                    if u < 0.18:
                        pitch = math.radians(16.0) * (1 - u / 0.18) * gp.heel_roll
                    elif u > 0.72:
                        k = (u - 0.72) / 0.28
                        pitch = -math.radians(38.0) * (k * k) * gp.heel_roll
                elif gp.heel_roll > 0 and backward:
                    if u < 0.2:
                        pitch = -math.radians(20.0) * (1 - u / 0.2) * gp.heel_roll
                    elif u > 0.8:
                        pitch = math.radians(10.0) * ((u - 0.8) / 0.2) * gp.heel_roll
                return pos, 0.0, pitch, True
            # swing: from lift point to next contact point
            v = (ph - gp.duty) / (1 - gp.duty)
            start = base - travel_dir * (0.5 * L)
            end = base + travel_dir * (0.5 * L)
            # ease: quick lift, decelerating landing
            ve = v * v * (3 - 2 * v)
            pos = start + (end - start) * ve
            h = gp.step_height * s * gp.knee_lift * math.sin(math.pi * v) ** 0.9
            pos = pos + UP * h
            if strafing:
                # crossing foot passes in front of the planted one
                pos = pos + FWD * 0.16 * s * math.sin(math.pi * v)
            pitch = 0.0
            if gp.heel_roll > 0 and not strafing:
                if backward:
                    pitch = math.radians(-14.0) * (1 - v) + math.radians(-25.0) * v * (1 - v)
                else:
                    # from toes-down (toe-off) to toes-up (heel strike)
                    pitch = math.radians(-30.0) * (1 - v) ** 2 + math.radians(18.0) * v * v
            return pos, 0.0, pitch, False
        return fn

    cb.feet.pos_fn["L"] = foot_fn("L")
    cb.feet.pos_fn["R"] = foot_fn("R")

    # hips height: keep every planted foot reachable, plus bob
    leg_len = skel.bones["UpperLeg.L"].length + skel.bones["LowerLeg.L"].length
    hip_j = skel.J["UpperLeg.L"]
    stand_hip_z = skel.J["Hips"][2]

    def body_pose(t: float) -> Pose:
        ph = (t / T) % 1.0
        w = 2 * math.pi * ph
        # bob: highest at mid-stance of either leg (ph ~ duty/2 and 0.5+duty/2), lowest just after contact
        mid = gp.duty * 0.5
        bob = -gp.hip_bob * s * (0.5 + 0.5 * math.cos(2 * (w - 2 * math.pi * mid)))
        if gp.flight:
            bob = gp.hip_bob * s * (0.5 + 0.5 * math.cos(2 * (w - 2 * math.pi * mid))) * 1.0 - gp.hip_bob * s
        # reachability: for each planted foot compute max hip height
        z_max = 1e9
        for side, fn in (("L", cb.feet.pos_fn["L"]), ("R", cb.feet.pos_fn["R"])):
            pos, _, pitch = fn(t)[:3]
            phc = ((t / T) - (0.0 if side == "L" else 0.5)) % 1.0
            if phc < gp.duty:
                hx = hip_j[0] * (1 if side == "L" else -1)
                horiz = math.hypot(pos[0] - hx, pos[1] - hip_j[1])
                reach = leg_len * 0.985
                if pitch < 0:
                    # heel raised: the ankle is higher, effectively
                    pass
                if reach > horiz:
                    z_max = min(z_max, math.sqrt(reach * reach - horiz * horiz) + pos[2] + abs(math.sin(pitch)) * 0.09 * s)
        z_hip_joint = stand_hip_z - 0.025 * s
        z_target = min(z_hip_joint + bob - gp.crouch * s, z_max) if z_max < 1e8 else z_hip_joint + bob - gp.crouch * s
        dz = z_target - z_hip_joint
        # lateral sway toward the stance leg; yaw with the swing leg; pelvic drop
        sway_x = gp.hip_sway * s * math.sin(w + math.pi * 0.5 * 0 + 0.0)  # + toward left at left mid-stance
        sway_x = gp.hip_sway * s * math.sin(w - 2 * math.pi * mid + math.pi / 2)
        yaw = gp.hip_yaw * math.cos(w)            # left hip forward at left contact
        roll = gp.hip_roll * math.sin(w - 2 * math.pi * mid)
        if strafing or backward:
            yaw *= 0.4
        pose: Pose = {
            HIPS_POS: (gp.torso_forward * s, sway_x * (1 if not strafing else 0.5), dz),
            "Hips": (gp.lean * 0.3, roll, yaw),
            "Spine": (gp.lean * 0.5 + 1.5, -roll * 0.5, -yaw * 0.5 * gp.chest_counter),
            "Chest": (gp.lean * 0.3 + 0.5 * math.cos(2 * w), -roll * 0.4, -yaw * 0.6 * gp.chest_counter),
            "Neck": (-gp.lean * 0.4 + 1.0 * gp.head_bob * math.cos(2 * w), 0, yaw * 0.1),
            "Head": (-gp.lean * 0.4 - 1.0 * gp.head_bob * math.cos(2 * w + 0.6), 0, 0),
        }
        # arms: counter-swing.  Left leg forward at ph=0 -> left arm back.
        sw = gp.arm_swing
        for side, sign in (("L", -1.0), ("R", 1.0)):
            swing = sign * sw * math.cos(w)                     # + forward
            fwd_amt = clamp01(swing / max(sw, 1e-6))
            if gp.hands_up:
                bend = gp.arm_bend + gp.arm_bend_swing * fwd_amt
            else:
                bend = gp.arm_bend + gp.arm_bend_swing * fwd_amt
            pose[f"Shoulder.{side}"] = (swing * 0.12, 0.0, 0.0)
            pose[f"UpperArm.{side}"] = (swing, gp.arm_adduct + 2.0 * fwd_amt, 8.0)
            pose[f"LowerArm.{side}"] = (bend, 0.0, 0.0)
            pose[f"Hand.{side}"] = (-6.0, 0.0, 0.0)
        if strafing:
            lean_dir = -1.0 if d[0] > 0 else 1.0    # lean into travel (left travel -> lean left = +s)
            pose["Spine"] = (pose["Spine"][0], -lean_dir * 4.0, pose["Spine"][2])
            pose["Chest"] = (pose["Chest"][0], -lean_dir * 3.0, pose["Chest"][2])
        return pose_add(pose, gp.extra_pose)

    cb.layers.append(body_pose)
    if footstep_events:
        cb.event(0.03 * T, "footstep_l")
        cb.event(0.53 * T, "footstep_r")
    return cb


# --------------------------------------------------------------------------------------
# swing generator (melee attacks)
# --------------------------------------------------------------------------------------

@dataclass
class SwingBeat:
    t: float
    pose: Pose
    ease: str = "smooth"


def swing_clip(skel: Skeleton, name: str, length: float, guard: Pose, beats: Sequence[SwingBeat],
               hit: Tuple[float, float], cancel_ok: float, steps: Sequence[Tuple[str, float, float, Tuple[float, float], float]] = (),
               stance: Tuple[float, float, float] = (0.0, 0.0, 0.0), return_to_guard: bool = True,
               guard_return_ease: str = "smooth") -> ClipBuilder:
    """Attack clip: starts and ends in `guard`; `beats` are absolute-time poses (full overrides
    merged over the guard); `steps` move feet: (side, t_lift, t_land, (forward, left) offset from
    the rest ankle, height).  `stance` = (spread, forward_l, forward_r)."""
    cb = ClipBuilder(skel, name, length, loop=False, grounded=True)
    stance_feet(cb.feet, *stance)
    s = skel.props.height / rig.DEFAULT_HEIGHT
    for side, t0, t1, (fwd, left), h in steps:
        base = skel.J[f"Foot.{side}"].copy()
        base[0] += (stance[0] if side == "L" else -stance[0])
        target = base + FWD * fwd * s + LEFT * left * s
        cb.feet.step(side, t0, t1, target, height=h * s)
    cb.key(0.0, guard, "smooth")
    for b in beats:
        cb.key(b.t, pose_add(guard, b.pose) if False else {**guard, **b.pose}, b.ease)
    if return_to_guard:
        cb.key(length, guard, guard_return_ease)
    cb.events_at(hit_start=hit[0], hit_end=hit[1], cancel_ok=cancel_ok)
    return cb


# --------------------------------------------------------------------------------------
# roll generator (dodges)
# --------------------------------------------------------------------------------------

def roll_clip(skel: Skeleton, name: str, direction: str, length: float = 0.75, guard: Optional[Pose] = None) -> ClipBuilder:
    """Tucked roll in place.  direction in F/B/L/R.  The whole body turns about a horizontal
    axis while tucking; legs are FK (not grounded)."""
    cb = ClipBuilder(skel, name, length, loop=False, grounded=False)
    guard = guard or GUARD_1H
    s = skel.props.height / rig.DEFAULT_HEIGHT
    # rotation sign: forward roll = bend forward (Hips f +)
    tuck: Pose = {"Spine": (36, 0, 0), "Chest": (28, 0, 0), "Neck": (18, 0, 0), "Head": (10, 0, 0),
                  "UpperLeg.L": (95, 10, 0), "UpperLeg.R": (95, 10, 0), "LowerLeg.L": (125, 0, 0), "LowerLeg.R": (125, 0, 0),
                  "Foot.L": (-20, 0, 0), "Foot.R": (-20, 0, 0),
                  "UpperArm.L": (70, -30, 0), "UpperArm.R": (70, -30, 0), "LowerArm.L": (110, 0, 0), "LowerArm.R": (110, 0, 0)}
    if direction == "F":
        spin = lambda k: {"Hips": (360.0 * k, 0, 0)}
        crouch_pose: Pose = {"Spine": (30, 0, 0), "Chest": (10, 0, 0), "Neck": (-10, 0, 0),
                             "UpperLeg.L": (70, 8, 0), "UpperLeg.R": (70, 8, 0), "LowerLeg.L": (100, 0, 0), "LowerLeg.R": (100, 0, 0),
                             "Foot.L": (-30, 0, 0), "Foot.R": (-30, 0, 0), "UpperArm.L": (60, -30, 0), "UpperArm.R": (60, -30, 0),
                             "LowerArm.L": (60, 0, 0), "LowerArm.R": (60, 0, 0)}
    elif direction == "B":
        spin = lambda k: {"Hips": (-360.0 * k, 0, 0)}
        crouch_pose = {"Spine": (24, 0, 0), "Chest": (8, 0, 0), "Neck": (-6, 0, 0),
                       "UpperLeg.L": (80, 8, 0), "UpperLeg.R": (80, 8, 0), "LowerLeg.L": (110, 0, 0), "LowerLeg.R": (110, 0, 0),
                       "Foot.L": (-30, 0, 0), "Foot.R": (-30, 0, 0), "UpperArm.L": (50, -30, 0), "UpperArm.R": (50, -30, 0),
                       "LowerArm.L": (70, 0, 0), "LowerArm.R": (70, 0, 0)}
    else:
        sign = 1.0 if direction == "L" else -1.0
        spin = lambda k: {"Hips": (0, sign * 360.0 * k, 0)}
        crouch_pose = {"Spine": (20, 0, 0), "Chest": (8, 0, 0), "Neck": (-6, 0, 0),
                       "UpperLeg.L": (70, 12, 0), "UpperLeg.R": (70, 12, 0), "LowerLeg.L": (100, 0, 0), "LowerLeg.R": (100, 0, 0),
                       "Foot.L": (-30, 0, 0), "Foot.R": (-30, 0, 0), "UpperArm.L": (50, -20, 0), "UpperArm.R": (50, -20, 0),
                       "LowerArm.L": (70, 0, 0), "LowerArm.R": (70, 0, 0)}
    hip_z = skel.J["Hips"][2]
    # The body's radius while tucked ~0.32 m: hips travel down to ~0.3 m above ground mid-roll.
    keys = [
        (0.0, {**guard, HIPS_POS: (0, 0, 0)}, "smooth"),
        (0.16, {**crouch_pose, HIPS_POS: (0.02, 0, -(hip_z - 0.55 * s))}, "in2"),
        (0.30, {**tuck, HIPS_POS: (0.0, 0, -(hip_z - 0.36 * s))}, "smooth"),
        (0.62, {**tuck, HIPS_POS: (0.0, 0, -(hip_z - 0.38 * s))}, "linear"),
        (0.80, {**crouch_pose, HIPS_POS: (0.0, 0, -(hip_z - 0.62 * s))}, "smooth"),
        (1.0, {**guard, HIPS_POS: (0, 0, 0)}, "out2"),
    ]
    for k, pose, e in keys:
        cb.key(k * length, pose, e)
    # spin as a post layer so the hips turn a full circle between 0.16 and 0.80
    def spin_layer(t: float) -> Pose:
        k = phase_window(t, 0.16 * length, 0.80 * length)
        k = ease("smooth", k)
        return spin(k)
    cb.layer(spin_layer)
    cb.event(0.25 * length, "roll_start")
    cb.event(0.85 * length, "cancel_ok")
    return cb


# --------------------------------------------------------------------------------------
# fall generator (deaths, knockdown)
# --------------------------------------------------------------------------------------

def fall_clip(skel: Skeleton, name: str, length: float, direction: str = "B", start: Optional[Pose] = None,
              stagger_pose: Optional[Pose] = None, settle: bool = True) -> ClipBuilder:
    """Collapse to the ground: a short stagger, the knees give, the body lands and settles.
    direction: 'B' onto the back, 'F' onto the front, 'L'/'R' onto a side, 'K' knees-first crumple."""
    cb = ClipBuilder(skel, name, length, loop=False, grounded=False)
    s = skel.props.height / rig.DEFAULT_HEIGHT
    hip_z = skel.J["Hips"][2]
    start = start or STAND
    cb.key(0.0, start, "smooth")
    if direction == "B":
        stagger = stagger_pose or {"Spine": (-14, 0, 0), "Chest": (-10, 0, 0), "Neck": (-10, 0, 0), "Head": (-6, 0, 0),
                                   "UpperArm.L": (40, -20, 0), "UpperArm.R": (40, -20, 0), "LowerArm.L": (40, 0, 0), "LowerArm.R": (40, 0, 0),
                                   "UpperLeg.L": (10, 4, 0), "UpperLeg.R": (-8, 4, 0), "LowerLeg.L": (20, 0, 0), "LowerLeg.R": (14, 0, 0),
                                   HIPS_POS: (-0.06, 0, -0.03)}
        landed: Pose = {"Hips": (-84, 0, 0), "Spine": (-4, 0, 0), "Chest": (-4, 0, 0), "Neck": (4, 0, 0), "Head": (4, 0, 0),
                        "UpperArm.L": (10, -20, 0), "UpperArm.R": (30, 20, 0), "LowerArm.L": (30, 0, 0), "LowerArm.R": (60, 0, 0),
                        "UpperLeg.L": (12, 6, 0), "UpperLeg.R": (6, 4, 0), "LowerLeg.L": (28, 0, 0), "LowerLeg.R": (10, 0, 0),
                        "Foot.L": (-30, 0, 0), "Foot.R": (-40, 0, 0), HIPS_POS: (-0.30, 0, -(hip_z - 0.16 * s))}
        mid: Pose = {"Hips": (-40, 0, 0), "Spine": (-10, 0, 0), "Chest": (-8, 0, 0), "Neck": (-14, 0, 0), "Head": (-8, 0, 0),
                     "UpperArm.L": (60, -10, 0), "UpperArm.R": (60, -10, 0), "LowerArm.L": (40, 0, 0), "LowerArm.R": (40, 0, 0),
                     "UpperLeg.L": (30, 6, 0), "UpperLeg.R": (40, 4, 0), "LowerLeg.L": (70, 0, 0), "LowerLeg.R": (60, 0, 0),
                     "Foot.L": (-20, 0, 0), "Foot.R": (-20, 0, 0), HIPS_POS: (-0.18, 0, -(hip_z - 0.45 * s))}
    elif direction == "F":
        stagger = stagger_pose or {"Spine": (18, 0, 0), "Chest": (12, 0, 0), "Neck": (6, 0, 0), "Head": (6, 0, 0),
                                   "UpperArm.L": (20, -30, 0), "UpperArm.R": (20, -30, 0), "LowerArm.L": (30, 0, 0), "LowerArm.R": (30, 0, 0),
                                   "UpperLeg.L": (14, 4, 0), "UpperLeg.R": (-4, 4, 0), "LowerLeg.L": (30, 0, 0), "LowerLeg.R": (10, 0, 0),
                                   HIPS_POS: (0.04, 0, -0.05)}
        mid = {"Hips": (50, 0, 0), "Spine": (10, 0, 0), "Chest": (6, 0, 0), "Neck": (-10, 0, 0), "Head": (-10, 0, 0),
               "UpperArm.L": (70, -10, 0), "UpperArm.R": (70, -10, 0), "LowerArm.L": (50, 0, 0), "LowerArm.R": (50, 0, 0),
               "UpperLeg.L": (60, 6, 0), "UpperLeg.R": (70, 6, 0), "LowerLeg.L": (90, 0, 0), "LowerLeg.R": (80, 0, 0),
               "Foot.L": (-30, 0, 0), "Foot.R": (-30, 0, 0), HIPS_POS: (0.12, 0, -(hip_z - 0.48 * s))}
        landed = {"Hips": (86, 0, 0), "Spine": (-6, 0, 0), "Chest": (-6, 0, 0), "Neck": (-10, 0, 20), "Head": (-14, 0, 20),
                  "UpperArm.L": (80, 10, 0), "UpperArm.R": (30, -20, 0), "LowerArm.L": (70, 0, 0), "LowerArm.R": (20, 0, 0),
                  "UpperLeg.L": (6, 8, 0), "UpperLeg.R": (-4, 6, 0), "LowerLeg.L": (24, 0, 0), "LowerLeg.R": (6, 0, 0),
                  "Foot.L": (-40, 0, 0), "Foot.R": (-40, 0, 0), HIPS_POS: (0.30, 0, -(hip_z - 0.20 * s))}
    elif direction == "K":   # crumple: knees, then fold sideways to the right
        stagger = stagger_pose or {"Spine": (6, 0, 0), "Neck": (10, 0, 0), "Head": (10, 0, 0),
                                   "UpperArm.L": (10, -36, 0), "UpperArm.R": (10, -36, 0), "LowerArm.L": (10, 0, 0), "LowerArm.R": (10, 0, 0),
                                   HIPS_POS: (0, 0, -0.04)}
        mid = {"Spine": (20, 0, 0), "Chest": (10, 0, 0), "Neck": (16, 0, 0), "Head": (14, 0, 0),
               "UpperArm.L": (10, -30, 0), "UpperArm.R": (10, -30, 0), "LowerArm.L": (20, 0, 0), "LowerArm.R": (20, 0, 0),
               "UpperLeg.L": (10, 6, 0), "UpperLeg.R": (10, 6, 0), "LowerLeg.L": (135, 0, 0), "LowerLeg.R": (135, 0, 0),
               "Foot.L": (-50, 0, 0), "Foot.R": (-50, 0, 0), HIPS_POS: (0.0, 0, -(hip_z - 0.50 * s))}
        landed = {"Hips": (30, -78, 20), "Spine": (14, 8, 0), "Chest": (10, 4, 0), "Neck": (10, 0, 0), "Head": (6, 0, 0),
                  "UpperArm.L": (40, -40, 0), "UpperArm.R": (60, 10, 0), "LowerArm.L": (60, 0, 0), "LowerArm.R": (90, 0, 0),
                  "UpperLeg.L": (40, 10, 0), "UpperLeg.R": (30, 4, 0), "LowerLeg.L": (110, 0, 0), "LowerLeg.R": (90, 0, 0),
                  "Foot.L": (-40, 0, 0), "Foot.R": (-40, 0, 0), HIPS_POS: (-0.05, -0.20, -(hip_z - 0.24 * s))}
    else:
        raise ValueError(direction)
    cb.key(0.16 * length, stagger, "out")
    cb.key(0.46 * length, mid, "in2")
    cb.key(0.66 * length, landed, "out")
    if settle:
        # A body that lands and then holds the landing pose reads as a dropped mannequin.
        # What sells a death is what happens AFTER the impact: the limbs keep going a little,
        # find nothing to hold them, and give.  Three decaying keys -- flop out, fall back,
        # one last slump -- and the arms travel furthest because nothing is bracing them.
        roll = 1.0 if direction in ("B", "K") else -1.0

        def give(base: Pose, amt: float) -> Pose:
            out = dict(base)
            for bone, delta in (
                ("UpperArm.L", (-26.0, -16.0, 0.0)), ("UpperArm.R", (-24.0, 14.0, 0.0)),
                ("LowerArm.L", (-34.0, 0.0, 0.0)), ("LowerArm.R", (-30.0, 0.0, 0.0)),
                ("Hand.L", (-16.0, 0.0, -10.0)), ("Hand.R", (-14.0, 0.0, 10.0)),
                ("Neck", (5.0, 0.0, 7.0 * roll)), ("Head", (4.0, 0.0, 9.0 * roll)),
                ("Chest", (3.0, 0.0, 0.0)), ("Spine", (2.0, 0.0, 0.0)),
                ("UpperLeg.L", (-6.0, 5.0, 0.0)), ("UpperLeg.R", (-5.0, -4.0, 0.0)),
                ("LowerLeg.L", (-12.0, 0.0, 0.0)), ("LowerLeg.R", (-10.0, 0.0, 0.0)),
                ("Foot.L", (-10.0, 0.0, 6.0)), ("Foot.R", (-9.0, 0.0, -6.0)),
            ):
                out[bone] = tuple(np.asarray(base.get(bone, (0.0, 0.0, 0.0)), float)
                                  + np.asarray(delta, float) * amt)
            return out

        # the limbs overshoot past where the body stopped, because they have their own weight
        cb.key(0.74 * length, give(landed, 1.00), "out")
        # and come back most of the way, slowly, with no muscle left to stop them cleanly
        cb.key(0.86 * length, give(landed, 0.62), "smooth")
        # a last settling: the chest sinks, the head finishes rolling, a hand turns over
        final = give(landed, 0.78)
        final["Chest"] = tuple(np.asarray(final["Chest"], float) + np.array([2.0, 0.0, 0.0]))
        final["Hand.R"] = tuple(np.asarray(final["Hand.R"], float) + np.array([0.0, 0.0, 14.0]))
        cb.key(0.96 * length, final, "smooth")
        cb.key(length, final, "linear")
    cb.event(0.62 * length, "body_land")
    return cb
