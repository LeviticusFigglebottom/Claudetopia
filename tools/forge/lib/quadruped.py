"""WM_Quadruped_v1: the rig every hoofed four-legged animal shares (docs/CONTRACTS.md §2b).

Pure Python and numpy, like `rig.py`: tests, the gait generator and previews use it without
Blender, and `build_armature` at the bottom makes the Blender armature from it.

The horse, the deer and whatever hoofed beast comes after share the bone names below. What
differs is `QuadProportions`: the height at the withers, the body's length, the legs', the neck's
and the head's, and the bulk. The gaits are authored on each animal's own skeleton by one
generator (`quad_clips.py`) from footfall timings, so a new species needs no new rig code.

Conventions are the humanoid's (CONTRACTS §1): Blender space, the animal faces -Y, up is +Z,
its LEFT is +X, the soles on z = 0. Every bone's local Y runs head -> tail; its local Z is
aligned to the reference direction given in `_ALIGN` (up for the spine, the neck, the head and
the tail; forward for the legs), which is what `EditBone.align_roll` gives.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict, field
from typing import Dict, List, Optional, Tuple

import numpy as np

from .rig import frame_from_dir, rot_axis, mat_to_quat, quat_to_mat, min_rot, FWD, UP, LEFT

RIG_ID = "WM_Quadruped_v1"

# --------------------------------------------------------------------------------------
# Contract: bone names and hierarchy
# --------------------------------------------------------------------------------------

LEG_FORE = ["Scapula", "Humerus", "Forearm", "FrontCannon", "FrontPastern", "FrontHoof"]
LEG_HIND = ["Thigh", "Gaskin", "HindCannon", "HindPastern", "HindHoof"]

DEFORM_BONES: List[Tuple[str, Optional[str]]] = [
    ("Hips", "Root"),
    ("Spine1", "Hips"), ("Spine2", "Spine1"), ("Chest", "Spine2"),
    ("Neck1", "Chest"), ("Neck2", "Neck1"), ("Head", "Neck2"), ("Jaw", "Head"),
    ("Ear.L", "Head"), ("Ear.R", "Head"),
    ("Tail1", "Hips"), ("Tail2", "Tail1"), ("Tail3", "Tail2"),
]
for _side in ("L", "R"):
    _prev = "Chest"
    for _n in LEG_FORE:
        DEFORM_BONES.append((f"{_n}.{_side}", _prev))
        _prev = f"{_n}.{_side}"
    _prev = "Hips"
    for _n in LEG_HIND:
        DEFORM_BONES.append((f"{_n}.{_side}", _prev))
        _prev = f"{_n}.{_side}"

DEFORM_NAMES = [n for n, _ in DEFORM_BONES]
# socket -> parent deform bone (non-deforming, for BoneAttachment3D)
SOCKET_BONES: Dict[str, str] = {
    "Socket.Saddle": "Spine2",   # the lowest point of the seat; the rider's hips sit on it
    "Socket.Bit": "Head",        # the bit ring on the near (left) side; the reins run from it
    "Socket.Pack": "Spine1",     # behind the saddle: bags, a bedroll, a load
    "Socket.Head": "Head",       # on the poll: antlers, a halter's plume
}
ALL_BONES: List[str] = ["Root"] + DEFORM_NAMES + list(SOCKET_BONES.keys())
PARENT: Dict[str, Optional[str]] = {"Root": None}
PARENT.update(dict(DEFORM_BONES))
PARENT.update(SOCKET_BONES)

FEET = ["FL", "FR", "HL", "HR"]      # fore left, fore right, hind left, hind right


def foot_bones(foot: str) -> List[str]:
    side = foot[1]
    names = LEG_FORE if foot[0] == "F" else LEG_HIND
    return [f"{n}.{side}" for n in names]


def mirror_name(name: str) -> str:
    if name.endswith(".L"):
        return name[:-2] + ".R"
    if name.endswith(".R"):
        return name[:-2] + ".L"
    return name


# --------------------------------------------------------------------------------------
# Proportions
# --------------------------------------------------------------------------------------

DEFAULT_WITHERS = 1.50       # a cob of about fifteen hands


@dataclass
class QuadProportions:
    """What makes a horse a horse and a deer a deer. 1.0 is the default horse's."""
    withers: float = DEFAULT_WITHERS   # height at the withers, m (the skin's top, standing square)
    body_length: float = 1.0           # the trunk, shoulder to buttock
    leg_length: float = 1.0            # the legs against the trunk's depth
    neck_length: float = 1.0
    head_size: float = 1.0
    bulk: float = 1.0                  # the barrel's girth and the limbs' thickness (mesh)
    width: float = 1.0                 # how far apart the legs stand
    tail_length: float = 1.0
    cannon: float = 1.0                # the cannons' share of the lower leg (a deer's are long)

    @staticmethod
    def from_dict(d: Optional[dict]) -> "QuadProportions":
        p = QuadProportions()
        for k, v in (d or {}).items():
            if hasattr(p, k):
                setattr(p, k, float(v))
        return p

    def to_dict(self) -> dict:
        return asdict(self)


# The default horse, as joint positions at withers 1.50 m (y back, z up; left legs at +x). The
# spine line is the vertebrae's, eight centimetres under the withers' skin.
_TRUNK_Z = 1.10            # the trunk's joints above this; the legs' below it
_J0: Dict[str, Tuple[float, float, float]] = {
    "Hips": (0.0, 0.40, 1.42),          # the lumbosacral joint: the croup turns about it
    "TailHead": (0.0, 0.76, 1.40),
    "Spine1": (0.0, 0.40, 1.42),
    "Spine2": (0.0, 0.08, 1.44),
    "Chest": (0.0, -0.24, 1.44),
    "Neck1": (0.0, -0.52, 1.36),        # the neck's root, in front of the withers
    "Neck2": (0.0, -0.72, 1.58),
    "Head": (0.0, -0.88, 1.80),         # the poll
    "Muzzle": (0.0, -1.20, 1.30),
    "Jaw": (0.0, -0.94, 1.62),          # the jaw's hinge under the ear
    "Chin": (0.0, -1.12, 1.30),
    "Ear.L": (0.075, -0.86, 1.86), "EarTip.L": (0.10, -0.84, 2.01),
    "Tail1": (0.0, 0.76, 1.40), "Tail2": (0.0, 0.88, 1.24), "Tail3": (0.0, 0.93, 1.02),
    "TailTip": (0.0, 0.95, 0.80),
    # the foreleg
    "Scapula.L": (0.10, -0.30, 1.40),   # the scapula's top, under the withers
    "Humerus.L": (0.17, -0.50, 1.06),   # the point of the shoulder
    "Forearm.L": (0.16, -0.34, 0.84),   # the elbow
    "FrontCannon.L": (0.15, -0.37, 0.48),   # the knee (carpus)
    "FrontPastern.L": (0.15, -0.37, 0.17),  # the fetlock
    "FrontHoof.L": (0.15, -0.43, 0.075),    # the coronet
    "FrontToe.L": (0.15, -0.51, 0.0),       # the toe of the hoof, on the ground
    # the hind leg
    "Thigh.L": (0.16, 0.52, 1.18),      # the hip joint
    "Gaskin.L": (0.19, 0.33, 0.84),     # the stifle
    "HindCannon.L": (0.16, 0.58, 0.54),     # the hock
    "HindPastern.L": (0.15, 0.55, 0.17),    # the fetlock
    "HindHoof.L": (0.15, 0.49, 0.075),      # the coronet
    "HindToe.L": (0.15, 0.415, 0.0),
}
BONE_TAIL: Dict[str, str] = {
    "Hips": "TailHead", "Spine1": "Spine2", "Spine2": "Chest", "Chest": "Neck1", "Neck1": "Neck2",
    "Neck2": "Head", "Head": "Muzzle", "Jaw": "Chin", "Ear.L": "EarTip.L", "Ear.R": "EarTip.R",
    "Tail1": "Tail2", "Tail2": "Tail3", "Tail3": "TailTip",
}
for _side in ("L", "R"):
    BONE_TAIL.update({
        f"Scapula.{_side}": f"Humerus.{_side}", f"Humerus.{_side}": f"Forearm.{_side}",
        f"Forearm.{_side}": f"FrontCannon.{_side}", f"FrontCannon.{_side}": f"FrontPastern.{_side}",
        f"FrontPastern.{_side}": f"FrontHoof.{_side}", f"FrontHoof.{_side}": f"FrontToe.{_side}",
        f"Thigh.{_side}": f"Gaskin.{_side}", f"Gaskin.{_side}": f"HindCannon.{_side}",
        f"HindCannon.{_side}": f"HindPastern.{_side}", f"HindPastern.{_side}": f"HindHoof.{_side}",
        f"HindHoof.{_side}": f"HindToe.{_side}",
    })

_NECK_BASE = np.array(_J0["Neck1"])
_LEG_JOINTS = {"Scapula", "Humerus", "Forearm", "FrontCannon", "FrontPastern", "FrontHoof", "FrontToe",
               "Thigh", "Gaskin", "HindCannon", "HindPastern", "HindHoof", "HindToe"}
_NECK_JOINTS = {"Neck2", "Head", "Muzzle", "Jaw", "Chin", "Ear", "EarTip"}
_HEAD_JOINTS = {"Muzzle", "Jaw", "Chin", "Ear", "EarTip"}
_TAIL_JOINTS = {"Tail2", "Tail3", "TailTip"}


def joint_positions(p: QuadProportions) -> Dict[str, np.ndarray]:
    """Joint positions (Blender space, metres) for proportions `p`: every bone's head and the
    tips (TailHead, Muzzle, Chin, EarTip.*, TailTip, FrontToe.*, HindToe.*)."""
    s = p.withers / DEFAULT_WITHERS
    # a longer leg raises the trunk; the trunk's own depth scales with the withers alone
    leg_top = _TRUNK_Z * p.leg_length
    J: Dict[str, np.ndarray] = {}
    src = dict(_J0)
    for k in list(src):
        if k.endswith(".L"):
            src[k[:-2] + ".R"] = (-src[k][0],) + tuple(src[k][1:])
    for name, (x, y, z) in src.items():
        base = name[:-2] if name[-2:] in (".L", ".R") else name
        if base in _LEG_JOINTS and z < _TRUNK_Z:
            # the leg: heights scale with the leg; the lower leg's joints move by `cannon`
            zz = z * p.leg_length
            if base in ("FrontCannon", "HindCannon"):
                # the knee or hock: `cannon` stretches the cannon below it
                zz = (0.17 + (z - 0.17) * p.cannon) * p.leg_length
            v = np.array([x * p.width, y * p.body_length, zz])
        else:
            v = np.array([x * p.width, y * p.body_length, (z - _TRUNK_Z) + leg_top])
        J[name] = v * s
    # the neck and head hang off the neck's root: scale them about it
    root = J["Neck1"].copy()
    for name in list(J):
        base = name[:-2] if name[-2:] in (".L", ".R") else name
        if base in _NECK_JOINTS:
            x, y, z = src[name]
            off = np.array([x * p.width, y, z - _NECK_BASE[2] + 0.0]) - np.array([0.0, _NECK_BASE[1], 0.0])
            off = off * s * p.neck_length
            J[name] = root + off
    # the head's own parts scale about the poll
    poll = J["Head"].copy()
    for name in list(J):
        base = name[:-2] if name[-2:] in (".L", ".R") else name
        if base in _HEAD_JOINTS:
            x, y, z = src[name]
            hx, hy, hz = src["Head"]
            off = np.array([x * p.width, y - hy, z - hz]) * s * p.head_size
            J[name] = poll + off
    # the tail hangs from its head
    th = J["Tail1"].copy()
    for name in _TAIL_JOINTS:
        x, y, z = src[name]
        tx, ty, tz = src["Tail1"]
        J[name] = th + np.array([0.0, y - ty, z - tz]) * s * p.tail_length
    return J


# bones whose Z is aligned up (the axial chain); the legs align Z forward (-Y)
_ALIGN_UP = {"Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "Tail1", "Tail2", "Tail3"}


def _align_for(name: str) -> np.ndarray:
    if name in _ALIGN_UP:
        return UP
    return FWD


def frame_lateral(y: np.ndarray, lateral: np.ndarray = -LEFT) -> np.ndarray:
    """3x3 rotation, columns (X, Y, Z): Y along the bone, X as near `lateral` as it goes. A leg
    swings in the body's side plane, so its bones keep X across the body however far they fold:
    a frame aligned to the front (`frame_from_dir(y, FWD)`) spins round when a hoof folds back
    past pointing straight behind. At rest it is the same frame (X = -LEFT when Z = FWD)."""
    y = np.asarray(y, float)
    y = y / np.linalg.norm(y)
    x = lateral - np.dot(lateral, y) * y
    if np.linalg.norm(x) < 1e-6:
        x = -LEFT
    x = x / np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def is_leg(name: str) -> bool:
    base = name[:-2] if name[-2:] in (".L", ".R") else name
    return base in LEG_FORE or base in LEG_HIND


def bone_frame(name: str, direction: np.ndarray) -> np.ndarray:
    """The frame bone `name` takes pointing along `direction`: its rest frame's rule."""
    if is_leg(name):
        return frame_lateral(direction)
    return frame_from_dir(direction, _align_for(name))


# --------------------------------------------------------------------------------------
# Skeleton
# --------------------------------------------------------------------------------------

@dataclass
class QBone:
    name: str
    parent: Optional[str]
    head: np.ndarray
    tail: np.ndarray
    rest: np.ndarray            # 4x4 armature-space rest matrix (== Blender bone.matrix_local)
    rest_local: np.ndarray      # 4x4 relative to the parent's rest
    deform: bool = True

    @property
    def length(self) -> float:
        return float(np.linalg.norm(self.tail - self.head))


def _socket_defs(J: Dict[str, np.ndarray], p: QuadProportions) -> Dict[str, Tuple[np.ndarray, np.ndarray, np.ndarray]]:
    s = p.withers / DEFAULT_WITHERS
    seat = J["Spine2"] + np.array([0.0, -0.10 * s * p.body_length, 0.155 * s])
    bit = J["Head"] + (J["Muzzle"] - J["Head"]) * 0.80 + np.array([0.055 * s * p.head_size, 0.0, 0.0])
    pack = J["Spine1"] + np.array([0.0, 0.02 * s, 0.15 * s])
    poll = J["Head"] + np.array([0.0, 0.0, 0.05 * s * p.head_size])
    return {
        "Socket.Saddle": (seat, seat + UP * 0.12 * s, FWD),
        "Socket.Bit": (bit, bit + LEFT * 0.06 * s, UP),
        "Socket.Pack": (pack, pack + UP * 0.12 * s, FWD),
        "Socket.Head": (poll, poll + UP * 0.12 * s, FWD),
    }


class QuadSkeleton:
    """The rest skeleton for proportions `p`, with forward kinematics and the solvers the gait
    generator uses."""

    def __init__(self, props: Optional[QuadProportions] = None):
        self.props = props or QuadProportions()
        self.J = joint_positions(self.props)
        self.bones: Dict[str, QBone] = {}
        self.order: List[str] = []
        J = self.J
        root_head = np.zeros(3)
        self._add("Root", None, root_head, root_head + UP * 0.12, FWD, deform=False)
        for name in DEFORM_NAMES:
            head = J[name].copy()
            tail = J[BONE_TAIL[name]].copy()
            self._add(name, PARENT[name], head, tail, _align_for(name), deform=True)
        for name, (head, tail, align) in _socket_defs(J, self.props).items():
            self._add(name, PARENT[name], head, tail, align, deform=False)

    def _add(self, name, parent, head, tail, align, deform):
        R = frame_lateral(tail - head) if is_leg(name) else frame_from_dir(tail - head, align)
        rest = np.eye(4)
        rest[:3, :3] = R
        rest[:3, 3] = head
        rest_local = rest.copy() if parent is None else np.linalg.inv(self.bones[parent].rest) @ rest
        self.bones[name] = QBone(name, parent, np.asarray(head, float), np.asarray(tail, float), rest, rest_local, deform)
        self.order.append(name)

    # -- kinematics -------------------------------------------------------------------
    def fk(self, pose: Dict[str, Tuple[Optional[np.ndarray], Optional[np.ndarray]]]) -> Dict[str, np.ndarray]:
        """pose: bone -> (R_local 3x3 or None, t_local 3 or None). Returns 4x4 armature-space
        matrices for every bone."""
        W: Dict[str, np.ndarray] = {}
        for name in self.order:
            b = self.bones[name]
            P = np.eye(4)
            if name in pose:
                R, t = pose[name]
                if R is not None:
                    P[:3, :3] = R
                if t is not None:
                    P[:3, 3] = t
            local = b.rest_local @ P
            W[name] = local if b.parent is None else W[b.parent] @ local
        return W

    def tail_world(self, W: Dict[str, np.ndarray], name: str) -> np.ndarray:
        b = self.bones[name]
        return (W[name] @ np.array([0.0, b.length, 0.0, 1.0]))[:3]

    def local_for_world(self, W: Dict[str, np.ndarray], name: str, R_world: np.ndarray) -> np.ndarray:
        """The local rotation that gives bone `name` the armature-space orientation `R_world`,
        its parent's world matrix already in W."""
        b = self.bones[name]
        Wp = W[b.parent][:3, :3] if b.parent else np.eye(3)
        return (Wp @ b.rest_local[:3, :3]).T @ R_world

    def local_turn(self, name: str, R_arm: np.ndarray) -> np.ndarray:
        """The local rotation for a turn `R_arm` given in armature axes (at rest) about the bone's
        own head: a nod of the neck is `rot_axis(LEFT, a)` whatever the bone's roll."""
        M = self.bones[name].rest[:3, :3]
        return M.T @ R_arm @ M

    def aim(self, W: Dict[str, np.ndarray], name: str, direction: np.ndarray) -> np.ndarray:
        """Local rotation pointing bone `name` along `direction`, framed by its rest frame's rule."""
        return self.local_for_world(W, name, bone_frame(name, direction))

    def two_bone(self, W: Dict[str, np.ndarray], upper: str, lower: str, target: np.ndarray,
                 pole: np.ndarray) -> Tuple[np.ndarray, np.ndarray, float]:
        """Local rotations for `upper` and `lower` putting the tail of `lower` on `target`, the
        joint between them bending toward `pole`. Returns (R_upper, R_lower, reach error m)."""
        bu, bl = self.bones[upper], self.bones[lower]
        l1, l2 = bu.length, bl.length
        Wp = W[bu.parent]
        root = (Wp @ bu.rest_local)[:3, 3]
        to = np.asarray(target, float) - root
        want = float(np.linalg.norm(to))
        dist = min(max(want, abs(l1 - l2) + 1e-4, 0.25 * (l1 + l2)), l1 + l2 - 1e-4)
        dirv = to / max(want, 1e-9)
        cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
        ang = math.acos(max(-1.0, min(1.0, cos_a)))
        pole_p = pole - np.dot(pole, dirv) * dirv
        if np.linalg.norm(pole_p) < 1e-6:
            pole_p = FWD - np.dot(FWD, dirv) * dirv
        pole_p = pole_p / np.linalg.norm(pole_p)
        up_dir = math.cos(ang) * dirv + math.sin(ang) * pole_p
        joint = root + up_dir * l1
        end = root + dirv * dist
        lo_dir = end - joint
        lo_dir /= np.linalg.norm(lo_dir)
        Ru = self.local_for_world(W, upper, bone_frame(upper, up_dir))
        Wu = np.eye(4)
        Wu[:3, :3] = Wp[:3, :3] @ bu.rest_local[:3, :3] @ Ru
        Wu[:3, 3] = root
        Wtmp = dict(W)
        Wtmp[upper] = Wu
        Rl = self.local_for_world(Wtmp, lower, bone_frame(lower, lo_dir))
        return Ru, Rl, abs(want - dist)

    # -- summaries --------------------------------------------------------------------
    def describe(self) -> str:
        lines = [f"{RIG_ID}: withers {self.props.withers:.3f} m"]
        for n in self.order:
            b = self.bones[n]
            lines.append(f"  {n:18s} parent={b.parent!s:16s} head={np.round(b.head, 3)} len={b.length:.3f}")
        return "\n".join(lines)


def rig_manifest(skel: QuadSkeleton) -> dict:
    return {
        "rig": RIG_ID,
        "withers": skel.props.withers,
        "proportions": skel.props.to_dict(),
        "bones": [{"name": n, "parent": skel.bones[n].parent, "head": [round(float(v), 4) for v in skel.bones[n].head],
                   "length": round(skel.bones[n].length, 4), "deform": skel.bones[n].deform} for n in skel.order],
        "sockets": list(SOCKET_BONES.keys()),
    }


# --------------------------------------------------------------------------------------
# Blender
# --------------------------------------------------------------------------------------

def build_armature(skel: QuadSkeleton, name: str = "Armature"):
    """A Blender armature whose bone matrices are exactly `skel`'s rest matrices."""
    import bpy
    from mathutils import Vector
    arm_data = bpy.data.armatures.new(RIG_ID)
    arm_data.display_type = 'OCTAHEDRAL'
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = {}
    for n in skel.order:
        b = skel.bones[n]
        eb = arm_data.edit_bones.new(n)
        eb.head = Vector(b.head.tolist())
        eb.tail = Vector(b.tail.tolist())
        eb.use_connect = False
        eb.use_deform = b.deform
        eb.align_roll(Vector(b.rest[:3, 2].tolist()))
        ebs[n] = eb
    for n in skel.order:
        par = skel.bones[n].parent
        if par:
            ebs[n].parent = ebs[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    worst = 0.0
    for n in skel.order:
        m = np.array(arm_data.bones[n].matrix_local)
        worst = max(worst, float(np.abs(m - skel.bones[n].rest).max()))
    if worst > 1e-4:
        raise RuntimeError(f"armature/skeleton mismatch: {worst}")
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


if __name__ == "__main__":
    print(QuadSkeleton().describe())
