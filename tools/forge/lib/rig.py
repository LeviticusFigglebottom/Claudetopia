"""WM_Humanoid_v1 rig (docs/CONTRACTS.md §2).

Pure-Python skeleton definition (usable without Blender: tests, animation authoring,
stick-figure previews) plus a Blender builder at the bottom (imported lazily).

Conventions (Blender space, before glTF export): character faces -Y, up is +Z,
the character's LEFT is +X.  Feet flat at z = 0.  Every bone's local Y axis runs
head -> tail; local Z points towards the character's front (or up, for the feet),
which is what `EditBone.align_roll` gives.  `Skeleton.rest` reproduces exactly the
matrices Blender builds, so animation code can do forward kinematics without bpy.

Proportions: see `Proportions`.  Bone lengths scale from the parameters; clips are
authored on the default proportions and retarget by bone-local rotation only.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict, field
from typing import Dict, List, Optional, Tuple

import numpy as np

# --------------------------------------------------------------------------------------
# Contract: bone names and hierarchy
# --------------------------------------------------------------------------------------

DEFORM_BONES: List[Tuple[str, Optional[str]]] = [
    ("Hips", "Root"), ("Spine", "Hips"), ("Chest", "Spine"), ("Neck", "Chest"), ("Head", "Neck"),
    ("Shoulder.L", "Chest"), ("UpperArm.L", "Shoulder.L"), ("LowerArm.L", "UpperArm.L"), ("Hand.L", "LowerArm.L"),
    ("Shoulder.R", "Chest"), ("UpperArm.R", "Shoulder.R"), ("LowerArm.R", "UpperArm.R"), ("Hand.R", "LowerArm.R"),
    ("UpperLeg.L", "Hips"), ("LowerLeg.L", "UpperLeg.L"), ("Foot.L", "LowerLeg.L"), ("Toe.L", "Foot.L"),
    ("UpperLeg.R", "Hips"), ("LowerLeg.R", "UpperLeg.R"), ("Foot.R", "LowerLeg.R"), ("Toe.R", "Foot.R"),
]
DEFORM_NAMES = [n for n, _ in DEFORM_BONES]
# socket name -> parent deform bone
SOCKET_BONES: Dict[str, str] = {
    "Socket.WeaponR": "Hand.R", "Socket.WeaponL": "Hand.L", "Socket.ShieldL": "LowerArm.L",
    "Socket.Back": "Chest", "Socket.HipL": "Hips", "Socket.Head": "Head", "Socket.Lantern": "Hand.L",
}
ALL_BONES: List[str] = ["Root"] + DEFORM_NAMES + list(SOCKET_BONES.keys())
PARENT: Dict[str, Optional[str]] = {"Root": None}
PARENT.update(dict(DEFORM_BONES))
PARENT.update(SOCKET_BONES)
RIG_ID = "WM_Humanoid_v1"

DEFAULT_HEIGHT = 1.78
A_POSE_DEG = 35.0  # arms this far below horizontal


def mirror_name(name: str) -> str:
    if name.endswith(".L"):
        return name[:-2] + ".R"
    if name.endswith(".R"):
        return name[:-2] + ".L"
    return name


# --------------------------------------------------------------------------------------
# Proportions
# --------------------------------------------------------------------------------------

@dataclass
class Proportions:
    """Continuous body proportion parameters.  1.0 / 0.5 are the defaults."""
    height: float = DEFAULT_HEIGHT
    bulk: float = 1.0            # overall thickness of limbs/torso (mesh radii)
    shoulder_width: float = 1.0
    hip_width: float = 1.0
    limb_length: float = 1.0     # legs+arms relative to torso (height kept constant)
    neck_length: float = 1.0
    head_size: float = 1.0
    build: float = 0.5           # 0 slight .. 1 heavy (mesh morph, not bone lengths)
    age: float = 0.3             # 0 young .. 1 old (posture + skin)
    feminine: float = 0.0        # 0 .. 1 (mesh morph + narrower shoulders / wider hips)
    hand_size: float = 1.0
    foot_size: float = 1.0

    @staticmethod
    def from_dict(d: Optional[dict]) -> "Proportions":
        p = Proportions()
        for k, v in (d or {}).items():
            if hasattr(p, k):
                setattr(p, k, float(v))
        return p

    def to_dict(self) -> dict:
        return asdict(self)


# --------------------------------------------------------------------------------------
# Joint layout
# --------------------------------------------------------------------------------------

def joint_positions(p: Proportions) -> Dict[str, np.ndarray]:
    """Joint positions (Blender space, metres) for proportions `p`.

    Returns a dict of named points: the head of every bone plus the tips
    (HeadTop, HandTip.L/R, ToeTip.L/R, Root at the origin)."""
    s = p.height / DEFAULT_HEIGHT
    head_len = 0.245 * p.head_size * s          # chin-ish (head bone head) to top of skull
    neck_len = 0.085 * p.neck_length * s
    leg = 0.965 * p.limb_length * s              # ground -> hip joint
    leg = min(leg, p.height - head_len - neck_len - 0.36 * s)  # keep a real torso
    torso = p.height - head_len - neck_len - leg  # hip joint -> neck base (C7-ish)
    torso = max(torso, 0.30 * s)

    hip_x = 0.100 * (0.9 + 0.2 * p.hip_width) * (1.0 + 0.10 * p.feminine) * s
    shoulder_x = 0.205 * (0.8 + 0.2 * p.shoulder_width) * (1.0 - 0.09 * p.feminine) * s
    hip_z = leg
    pelvis_z = hip_z + 0.025 * s
    spine_z = pelvis_z + torso * 0.24
    chest_z = pelvis_z + torso * 0.53
    neck_z = pelvis_z + torso * 0.95                   # neck base
    head_z = neck_z + neck_len
    top_z = head_z + head_len
    shoulder_z = neck_z - 0.01 * s
    clav_x = 0.03 * s

    # legs: knee a little forward of the hip/ankle line; ankle slightly above ground
    knee_z = leg * 0.53
    ankle_z = 0.085 * s
    foot_len = 0.245 * p.foot_size * s
    ball = foot_len * 0.62
    up_arm = 0.300 * p.limb_length * s
    lo_arm = 0.262 * p.limb_length * s
    hand_len = 0.185 * p.hand_size * s
    a = math.radians(A_POSE_DEG)
    d = np.array([math.cos(a), 0.0, -math.sin(a)])  # left arm direction at rest

    J: Dict[str, np.ndarray] = {}
    J["Root"] = np.array([0.0, 0.0, 0.0])
    J["Hips"] = np.array([0.0, 0.0, pelvis_z])
    J["Spine"] = np.array([0.0, 0.0, spine_z])
    J["Chest"] = np.array([0.0, 0.0, chest_z])
    J["Neck"] = np.array([0.0, 0.0, neck_z])
    J["Head"] = np.array([0.0, 0.0, head_z])
    J["HeadTop"] = np.array([0.0, 0.0, top_z])
    for side, sx in (("L", 1.0), ("R", -1.0)):
        sh = np.array([sx * shoulder_x, 0.0, shoulder_z])
        J[f"Shoulder.{side}"] = np.array([sx * clav_x, 0.0, shoulder_z - 0.01 * s])
        J[f"UpperArm.{side}"] = sh
        dd = d * np.array([sx, 1.0, 1.0])
        J[f"LowerArm.{side}"] = sh + dd * up_arm
        J[f"Hand.{side}"] = J[f"LowerArm.{side}"] + dd * lo_arm
        J[f"HandTip.{side}"] = J[f"Hand.{side}"] + dd * hand_len
        hx = sx * hip_x
        J[f"UpperLeg.{side}"] = np.array([hx, 0.0, hip_z])
        J[f"LowerLeg.{side}"] = np.array([hx * 1.05, -0.02 * s, knee_z])
        J[f"Foot.{side}"] = np.array([hx * 1.08, 0.0, ankle_z])
        J[f"Toe.{side}"] = np.array([hx * 1.08, -ball, 0.018 * s])
        J[f"ToeTip.{side}"] = np.array([hx * 1.08, -foot_len, 0.012 * s])
    return J


BONE_TAIL: Dict[str, str] = {
    "Root": "Hips", "Hips": "Spine", "Spine": "Chest", "Chest": "Neck", "Neck": "Head", "Head": "HeadTop",
    "Shoulder.L": "UpperArm.L", "UpperArm.L": "LowerArm.L", "LowerArm.L": "Hand.L", "Hand.L": "HandTip.L",
    "Shoulder.R": "UpperArm.R", "UpperArm.R": "LowerArm.R", "LowerArm.R": "Hand.R", "Hand.R": "HandTip.R",
    "UpperLeg.L": "LowerLeg.L", "LowerLeg.L": "Foot.L", "Foot.L": "Toe.L", "Toe.L": "ToeTip.L",
    "UpperLeg.R": "LowerLeg.R", "LowerLeg.R": "Foot.R", "Foot.R": "Toe.R", "Toe.R": "ToeTip.R",
}

FWD = np.array([0.0, -1.0, 0.0])
UP = np.array([0.0, 0.0, 1.0])
LEFT = np.array([1.0, 0.0, 0.0])
MIRROR = np.diag([-1.0, 1.0, 1.0])


def _unit(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def frame_from_dir(y: np.ndarray, align: np.ndarray) -> np.ndarray:
    """3x3 rotation with columns (X, Y, Z): Y = bone direction, Z as close as possible
    to `align` (Blender's EditBone.align_roll)."""
    y = _unit(y)
    z = align - np.dot(align, y) * y
    if np.linalg.norm(z) < 1e-6:
        z = UP - np.dot(UP, y) * y
    z = _unit(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


def rot_axis(axis: np.ndarray, ang: float) -> np.ndarray:
    axis = _unit(np.asarray(axis, dtype=float))
    x, y, z = axis
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([
        [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def mat_to_quat(m: np.ndarray) -> np.ndarray:
    """Rotation matrix -> quaternion (w, x, y, z)."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return np.array([0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s])
    i = int(np.argmax(np.diag(m)))
    if i == 0:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return np.array([(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s])
    if i == 1:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return np.array([(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s])
    s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return np.array([(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s])


def quat_to_mat(q: np.ndarray) -> np.ndarray:
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def quat_slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        return _unit(a + (b - a) * t)
    th = math.acos(min(1.0, d))
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


# --------------------------------------------------------------------------------------
# Skeleton: rest matrices, anatomical frames, FK, 2-bone IK
# --------------------------------------------------------------------------------------

@dataclass
class Bone:
    name: str
    parent: Optional[str]
    head: np.ndarray
    tail: np.ndarray
    rest: np.ndarray            # 4x4 armature-space rest matrix (== Blender bone.matrix_local)
    rest_local: np.ndarray      # 4x4 relative to parent rest
    deform: bool = True
    anat: np.ndarray = field(default_factory=lambda: np.eye(3))  # anatomical frame (columns f, s, t)

    @property
    def length(self) -> float:
        return float(np.linalg.norm(self.tail - self.head))


def _socket_defs(J: Dict[str, np.ndarray], p: Proportions) -> Dict[str, Tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """Socket bones: name -> (head, tail, align).  Positions are in armature space (rest)."""
    s = p.height / DEFAULT_HEIGHT
    a = math.radians(A_POSE_DEG)
    dl = np.array([math.cos(a), 0.0, -math.sin(a)])
    dr = dl * np.array([-1, 1, 1])
    # hand: palm faces inward (towards body / down-in).  Grip origin sits in the palm centre,
    # blade axis (+Y of socket) points along fingers-forward: perpendicular to the arm, forward.
    palm_l = J["Hand.L"] + dl * 0.07 * s + np.array([0.0, 0.0, -0.02 * s])
    palm_r = J["Hand.R"] + dr * 0.07 * s + np.array([0.0, 0.0, -0.02 * s])
    out = {
        "Socket.WeaponR": (palm_r, palm_r + FWD * 0.12 * s, UP),
        "Socket.WeaponL": (palm_l, palm_l + FWD * 0.12 * s, UP),
        "Socket.Lantern": (palm_l + np.array([0, 0, -0.02 * s]), palm_l + np.array([0, 0, -0.14 * s]), FWD),
        "Socket.ShieldL": (J["LowerArm.L"] + dl * 0.12 * s + np.array([0.0, -0.045 * s, 0.0]),
                           J["LowerArm.L"] + dl * 0.12 * s + np.array([0.0, -0.045 * s, 0.0]) + UP * 0.12 * s, FWD),
        "Socket.Back": (J["Chest"] + np.array([0.0, 0.14 * s, 0.10 * s]),
                        J["Chest"] + np.array([0.0, 0.14 * s, 0.22 * s]), FWD),
        "Socket.HipL": (J["Hips"] + np.array([0.13 * s, 0.03 * s, -0.04 * s]),
                        J["Hips"] + np.array([0.13 * s, 0.03 * s, -0.16 * s]), FWD),
        "Socket.Head": (J["HeadTop"] + np.array([0.0, 0.0, -0.02 * s]), J["HeadTop"] + np.array([0.0, 0.0, 0.10 * s]), FWD),
    }
    return out


class Skeleton:
    """Rest skeleton for given proportions, with FK/IK helpers."""

    def __init__(self, props: Optional[Proportions] = None):
        self.props = props or Proportions()
        self.J = joint_positions(self.props)
        self.bones: Dict[str, Bone] = {}
        self.order: List[str] = []
        J = self.J
        for name in ["Root"] + DEFORM_NAMES:
            head = J[name].copy()
            tail = J[BONE_TAIL[name]].copy()
            if name == "Root":
                tail = head + UP * 0.12
            align = UP if name.startswith(("Foot", "Toe")) else FWD
            self._add(name, PARENT[name], head, tail, align, deform=(name != "Root"))
        for name, (head, tail, align) in _socket_defs(J, self.props).items():
            self._add(name, PARENT[name], head, tail, align, deform=False)
        self._build_anat_frames()

    def _add(self, name, parent, head, tail, align, deform):
        R = frame_from_dir(tail - head, align)
        rest = np.eye(4)
        rest[:3, :3] = R
        rest[:3, 3] = head
        if parent is None:
            rest_local = rest.copy()
        else:
            rest_local = np.linalg.inv(self.bones[parent].rest) @ rest
        self.bones[name] = Bone(name, parent, np.asarray(head, float), np.asarray(tail, float), rest, rest_local, deform)
        self.order.append(name)

    # -- anatomical frames ------------------------------------------------------------
    def _build_anat_frames(self):
        """Columns (f, s, t) of an orthonormal frame in armature space (right-side bones use
        the mirrored left frame; see `pose_rotation`).  Meanings, positive direction:
          axial (Root, Hips, Spine, Chest, Neck, Head): f bend forward, s lean left, t turn left
          UpperLeg: f thigh forward, s abduct (out), t rotate outward (toes out)
          LowerLeg: f knee bend (heel back), s -, t -
          Foot/Toe: f toes up, s roll (sole out), t toes turn out
          Shoulder: f forward (protract), s up (shrug), t -
          UpperArm: f forward (flex), s up/out (abduct), t rotate so palm turns up/forward
          LowerArm: f elbow bend (hand forward/up), s -, t pronate (palm down)
          Hand: f fingers forward/palm-ward (flex), s fingers up (radial), t twist
        """
        for name, b in self.bones.items():
            base = name[:-2] if name[-2:] in (".L", ".R") else name
            left = name if not name.endswith(".R") else mirror_name(name)
            d = _unit(self.bones[left].tail - self.bones[left].head)
            if base in ("Root", "Hips", "Spine", "Chest", "Neck", "Head") or name.startswith("Socket"):
                A = np.eye(3)
            elif base == "UpperLeg":
                f = _unit(-LEFT - np.dot(-LEFT, d) * d)       # about character right
                s = FWD
                A = np.stack([f, s, np.cross(f, s)], axis=1)
            elif base == "LowerLeg":
                f = _unit(LEFT - np.dot(LEFT, d) * d)
                s = -FWD
                A = np.stack([f, s, np.cross(f, s)], axis=1)
            elif base in ("Foot", "Toe"):
                f = _unit(-LEFT - np.dot(-LEFT, d) * d)       # toes up
                t = UP
                s = np.cross(t, f)
                A = np.stack([f, s, np.cross(f, s)], axis=1)
            elif base == "Shoulder":
                f = -UP                                        # forward protraction
                s = FWD                                        # shrug up
                A = np.stack([f, s, np.cross(f, s)], axis=1)
            elif base in ("UpperArm", "LowerArm", "Hand"):
                f = _unit(-LEFT - np.dot(-LEFT, d) * d)       # flex forward
                s = FWD                                        # abduct up/out
                A = np.stack([f, s, np.cross(f, s)], axis=1)
            else:
                A = np.eye(3)
            if name.endswith(".R"):
                A = MIRROR @ A
            b.anat = A

    def pose_rotation(self, name: str, f_deg: float, s_deg: float, t_deg: float) -> np.ndarray:
        """Bone-local 3x3 rotation for anatomical angles (degrees)."""
        b = self.bones[name]
        A = b.anat
        R = rot_axis(np.array([1.0, 0, 0]), math.radians(f_deg)) @ \
            rot_axis(np.array([0, 1.0, 0]), math.radians(s_deg)) @ \
            rot_axis(np.array([0, 0, 1.0]), math.radians(t_deg))
        R_arm = A @ R @ np.linalg.inv(A)
        M = b.rest[:3, :3]
        return M.T @ R_arm @ M

    def local_to_anat(self, name: str, R_local: np.ndarray) -> np.ndarray:
        """Inverse of pose_rotation up to Euler decomposition: returns R in the anatomical frame."""
        b = self.bones[name]
        M = b.rest[:3, :3]
        R_arm = M @ R_local @ M.T
        return np.linalg.inv(b.anat) @ R_arm @ b.anat

    def local_translation(self, name: str, world_offset: np.ndarray) -> np.ndarray:
        """Bone-local translation for an offset given in armature space (at rest orientation)."""
        M = self.bones[name].rest[:3, :3]
        return M.T @ np.asarray(world_offset, float)

    # -- forward kinematics -----------------------------------------------------------
    def fk(self, pose: Dict[str, Tuple[np.ndarray, np.ndarray]]) -> Dict[str, np.ndarray]:
        """pose: bone -> (R_local 3x3, t_local 3) (missing bones = rest).  Returns 4x4 world
        matrices per bone (armature space)."""
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

    def joint_world(self, W: Dict[str, np.ndarray], name: str) -> np.ndarray:
        return W[name][:3, 3]

    def tail_world(self, W: Dict[str, np.ndarray], name: str) -> np.ndarray:
        b = self.bones[name]
        return (W[name] @ np.array([0.0, b.length, 0.0, 1.0]))[:3]

    # -- two-bone IK ------------------------------------------------------------------
    def ik_two_bone(self, W: Dict[str, np.ndarray], upper: str, lower: str, target: np.ndarray,
                    pole: np.ndarray, end_align: Optional[np.ndarray] = None) -> Tuple[np.ndarray, np.ndarray]:
        """Solve local rotations for `upper`/`lower` so the tail of `lower` reaches `target`.
        `W` must contain the current world matrix of upper's parent.  `pole` is a world
        direction the bend (knee/elbow) should point towards.  Returns (R_upper, R_lower)
        as bone-local rotation matrices (matching `pose_rotation` output space)."""
        bu, bl = self.bones[upper], self.bones[lower]
        l1, l2 = bu.length, bl.length
        Wp = W[bu.parent]
        root = (Wp @ bu.rest_local)[:3, 3]
        to = target - root
        dist = float(np.linalg.norm(to))
        dist = min(max(dist, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
        dirv = _unit(to)
        # angle at the root between dir and the upper bone (law of cosines)
        cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
        ang = math.acos(max(-1.0, min(1.0, cos_a)))
        pole_p = pole - np.dot(pole, dirv) * dirv
        if np.linalg.norm(pole_p) < 1e-6:
            pole_p = UP - np.dot(UP, dirv) * dirv
        pole_p = _unit(pole_p)
        up_dir = math.cos(ang) * dirv + math.sin(ang) * pole_p       # upper bone direction
        knee = root + up_dir * l1
        lo_dir = _unit(target - knee)
        # bend-plane normal: for a leg the knee points along pole, so bone Z (front) ~ pole
        align_u = bu.rest[:3, 2]
        align_l = bl.rest[:3, 2]
        # keep the bones' own "front" (Z at rest) tracking the pole direction sign-wise
        z_ref_u = pole_p if np.dot(align_u, pole) >= 0 else -pole_p
        z_ref_l = pole_p if np.dot(align_l, pole) >= 0 else -pole_p
        Wu_t = frame_from_dir(up_dir, z_ref_u)
        Wl_t = frame_from_dir(lo_dir, z_ref_l)
        Ru = (Wp[:3, :3] @ bu.rest_local[:3, :3]).T @ Wu_t
        Wu = Wp[:3, :3] @ bu.rest_local[:3, :3] @ Ru
        Rl = (Wu @ bl.rest_local[:3, :3]).T @ Wl_t
        return Ru, Rl

    def aim_rotation(self, W: Dict[str, np.ndarray], name: str, direction: np.ndarray, front: np.ndarray) -> np.ndarray:
        """Local rotation so that bone `name` (whose parent world matrix is in W) points along
        `direction` with its Z (front) axis as close as possible to `front`."""
        b = self.bones[name]
        Wp = W[b.parent] if b.parent else np.eye(4)
        Wt = frame_from_dir(direction, front)
        return (Wp[:3, :3] @ b.rest_local[:3, :3]).T @ Wt

    # -- summaries --------------------------------------------------------------------
    def lengths(self) -> Dict[str, float]:
        return {n: self.bones[n].length for n in self.order}

    def describe(self) -> str:
        lines = [f"{RIG_ID}: height {self.props.height:.3f} m"]
        for n in self.order:
            b = self.bones[n]
            lines.append(f"  {n:16s} parent={b.parent!s:12s} head={np.round(b.head, 3)} len={b.length:.3f} deform={b.deform}")
        return "\n".join(lines)


# --------------------------------------------------------------------------------------
# Blender builder
# --------------------------------------------------------------------------------------

def build_armature(skel: Skeleton, name: str = "Armature"):
    """Create a Blender armature object matching `skel` (bone matrices identical to
    `skel.bones[*].rest`).  Socket bones are non-deforming.  Returns the object."""
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
        # align_roll: Z axis towards the reference direction used in frame_from_dir
        z = b.rest[:3, 2]
        eb.align_roll(Vector(z.tolist()))
        ebs[n] = eb
    for n in skel.order:
        par = skel.bones[n].parent
        if par:
            ebs[n].parent = ebs[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    # verify
    worst = 0.0
    for n in skel.order:
        m = np.array(arm_data.bones[n].matrix_local)
        worst = max(worst, float(np.abs(m - skel.bones[n].rest).max()))
    if worst > 1e-4:
        raise RuntimeError(f"armature/skeleton mismatch: {worst}")
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


def rig_manifest(skel: Skeleton) -> dict:
    return {
        "rig": RIG_ID,
        "height": skel.props.height,
        "proportions": skel.props.to_dict(),
        "bones": [{"name": n, "parent": skel.bones[n].parent, "head": [round(float(v), 4) for v in skel.bones[n].head],
                   "length": round(skel.bones[n].length, 4), "deform": skel.bones[n].deform} for n in skel.order],
        "sockets": list(SOCKET_BONES.keys()),
    }


if __name__ == "__main__":
    sk = Skeleton()
    print(sk.describe())
