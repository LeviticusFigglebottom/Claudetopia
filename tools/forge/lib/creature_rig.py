"""A free-form creature rig: the weaver's eight legs, a thrall's or a warden's giant frame, a wisp.

Pure numpy, like quadruped.py: a `Rig` is a list of bones (name, parent, head, tail, the direction
its Z leans to), with forward kinematics, `aim` (the smallest turn putting a bone along a direction,
from where its parent carries it: no twist creeps in), `turn` (a turn given in the armature's
axes about the bone's head) and two-bone IK. A `RigClip` samples a pose -- bone -> local rotation,
and the Hips' translation -- and bakes to anim.BakedClip, so character_forge.push_clip lays it on
the armature as every other clip in the forge.

Conventions are the forge's (CONTRACTS §1): Blender space, faces -Y, left +X, up +Z, ground z = 0.
The bone that carries the body (and is translated) is always `Hips`, under a non-deforming `Root`.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from .anim import BakedClip, FPS
from .rig import frame_from_dir, rot_axis, mat_to_quat, min_rot, FWD, UP, LEFT


def _u(v) -> np.ndarray:
    v = np.asarray(v, float)
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


@dataclass
class RBone:
    name: str
    parent: Optional[str]
    head: np.ndarray
    tail: np.ndarray
    rest: np.ndarray
    rest_local: np.ndarray
    deform: bool = True

    @property
    def length(self) -> float:
        return float(np.linalg.norm(self.tail - self.head))


class Rig:
    def __init__(self, rig_id: str, bones: Sequence[Tuple], height: float = 1.0):
        """bones: (name, parent, head, tail[, align[, deform]]) in parent-first order, after Root."""
        self.rig_id = rig_id
        self.height = height
        self.bones: Dict[str, RBone] = {}
        self.order: List[str] = []
        self._add("Root", None, np.zeros(3), np.array([0.0, 0.0, 0.12]) * max(height, 0.3), FWD, False)
        for b in bones:
            name, parent, head, tail = b[0], b[1], np.asarray(b[2], float), np.asarray(b[3], float)
            align = np.asarray(b[4], float) if len(b) > 4 and b[4] is not None else UP
            deform = bool(b[5]) if len(b) > 5 else True
            self._add(name, parent or "Root", head, tail, align, deform)

    def _add(self, name, parent, head, tail, align, deform):
        R = frame_from_dir(tail - head, align)
        if abs(float(np.dot(_u(tail - head), _u(align)))) > 0.98:
            R = frame_from_dir(tail - head, FWD if abs(_u(tail - head)[1]) < 0.9 else UP)
        rest = np.eye(4)
        rest[:3, :3] = R
        rest[:3, 3] = head
        rest_local = rest.copy() if parent is None else np.linalg.inv(self.bones[parent].rest) @ rest
        self.bones[name] = RBone(name, parent, head, tail, rest, rest_local, deform)
        self.order.append(name)

    @property
    def deform_names(self) -> List[str]:
        return [n for n in self.order if self.bones[n].deform]

    @property
    def J(self) -> Dict[str, np.ndarray]:
        return {n: b.head for n, b in self.bones.items()}

    def fk(self, pose: Dict[str, Tuple[Optional[np.ndarray], Optional[np.ndarray]]]) -> Dict[str, np.ndarray]:
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

    def tail_world(self, W, name: str) -> np.ndarray:
        b = self.bones[name]
        return (W[name] @ np.array([0.0, b.length, 0.0, 1.0]))[:3]

    def local_turn(self, name: str, R_arm: np.ndarray) -> np.ndarray:
        """The local rotation for a turn given in armature axes (at rest) about the bone's head."""
        M = self.bones[name].rest[:3, :3]
        return M.T @ R_arm @ M

    def carried(self, W, name: str) -> np.ndarray:
        """Bone `name`'s world frame with its own local rotation left at rest."""
        b = self.bones[name]
        return (W[b.parent] @ b.rest_local)[:3, :3]

    def aim(self, W, name: str, direction) -> np.ndarray:
        """The local rotation pointing bone `name` along `direction` by the smallest turn from where
        its parent carries it."""
        C = self.carried(W, name)
        R_world = min_rot(C[:, 1], _u(direction)) @ C
        return C.T @ R_world

    def two_bone(self, W, upper: str, lower: str, target, pole) -> Tuple[np.ndarray, np.ndarray, float]:
        bu, bl = self.bones[upper], self.bones[lower]
        l1, l2 = bu.length, bl.length
        root = (W[bu.parent] @ bu.rest_local)[:3, 3]
        to = np.asarray(target, float) - root
        want = float(np.linalg.norm(to))
        dist = min(max(want, abs(l1 - l2) + 1e-4, 0.2 * (l1 + l2)), l1 + l2 - 1e-4)
        dirv = to / max(want, 1e-9)
        cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
        ang = math.acos(max(-1.0, min(1.0, cos_a)))
        pole = np.asarray(pole, float)
        pp = pole - np.dot(pole, dirv) * dirv
        if np.linalg.norm(pp) < 1e-6:
            pp = UP - np.dot(UP, dirv) * dirv
        pp = _u(pp)
        up_dir = math.cos(ang) * dirv + math.sin(ang) * pp
        joint = root + up_dir * l1
        end = root + dirv * dist
        Ru = self.aim(W, upper, up_dir)
        pose_u = dict()
        Wu = np.eye(4)
        Wu[:3, :3] = self.carried(W, upper) @ Ru
        Wu[:3, 3] = root
        Wt = dict(W)
        Wt[upper] = Wu
        Rl = self.aim(Wt, lower, end - joint)
        del pose_u
        return Ru, Rl, abs(want - dist)


class Poser:
    """Builds one pose bone by bone in hierarchy order, so each bone's aim sees its parents posed."""

    def __init__(self, rig: Rig):
        self.rig = rig
        self.pose: Dict[str, Tuple[Optional[np.ndarray], Optional[np.ndarray]]] = {}
        self._W = None

    def W(self):
        if self._W is None:
            self._W = self.rig.fk(self.pose)
        return self._W

    def set(self, name: str, R: Optional[np.ndarray] = None, t: Optional[np.ndarray] = None) -> None:
        old = self.pose.get(name, (None, None))
        self.pose[name] = (R if R is not None else old[0], t if t is not None else old[1])
        self._W = None

    def turn(self, name: str, R_arm: np.ndarray) -> None:
        """Turns bone `name` by R_arm (armature axes at rest), on top of nothing (sets its local)."""
        self.set(name, self.rig.local_turn(name, R_arm))

    def aim(self, name: str, direction) -> None:
        self.set(name, self.rig.aim(self.W(), name, direction))

    def two_bone(self, upper: str, lower: str, target, pole) -> float:
        Ru, Rl, err = self.rig.two_bone(self.W(), upper, lower, target, pole)
        self.set(upper, Ru)
        self.set(lower, Rl)
        return err

    def move_hips(self, R_arm: np.ndarray, offset, pivot=None) -> None:
        """The whole body turned by R_arm about `pivot` (the hips' head) and moved by `offset`."""
        hb = self.rig.bones["Hips"]
        pv = hb.head if pivot is None else np.asarray(pivot, float)
        new_head = pv + R_arm @ (hb.head - pv) + np.asarray(offset, float)
        self.set("Hips", self.rig.local_turn("Hips", R_arm), hb.rest[:3, :3].T @ (new_head - hb.head))

    def world(self, name: str) -> np.ndarray:
        return self.W()[name]

    def tail(self, name: str) -> np.ndarray:
        return self.rig.tail_world(self.W(), name)


@dataclass
class RigClip:
    name: str
    length: float
    loop: bool
    sample: Callable[[float], Poser]
    events: List[Tuple[float, str]] = field(default_factory=list)
    extra: dict = field(default_factory=dict)

    def bake(self, rig: Rig, fps: int = FPS) -> BakedClip:
        n = int(round(self.length * fps)) + (0 if self.loop else 1)
        bones = rig.deform_names
        quats = {b: np.zeros((n, 4)) for b in bones}
        hips = np.zeros((n, 3))
        prev: Dict[str, np.ndarray] = {}
        for i in range(n):
            t = min(i / fps, self.length)
            p = self.sample(t)
            for b in bones:
                R = p.pose.get(b, (None, None))[0]
                q = mat_to_quat(R) if R is not None else np.array([1.0, 0.0, 0.0, 0.0])
                if b in prev and float(np.dot(prev[b], q)) < 0.0:
                    q = -q
                prev[b] = q
                quats[b][i] = q
            th = p.pose.get("Hips", (None, None))[1]
            hips[i] = th if th is not None else 0.0
        return BakedClip(name=self.name, length=self.length, loop=self.loop, fps=fps,
                         events=list(self.events), bones=bones, quats=quats, hips_pos=hips, extra=dict(self.extra))


def manifest(rig: Rig) -> dict:
    return {"rig": rig.rig_id,
            "bones": [{"name": n, "parent": rig.bones[n].parent, "head": [round(float(v), 4) for v in rig.bones[n].head],
                       "length": round(rig.bones[n].length, 4), "deform": rig.bones[n].deform} for n in rig.order]}


def build_armature(rig: Rig, name: str = "Armature"):
    import bpy
    from mathutils import Vector
    arm_data = bpy.data.armatures.new(rig.rig_id)
    arm_data.display_type = 'OCTAHEDRAL'
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = {}
    for n in rig.order:
        b = rig.bones[n]
        eb = arm_data.edit_bones.new(n)
        eb.head = Vector(b.head.tolist())
        eb.tail = Vector(b.tail.tolist())
        eb.use_connect = False
        eb.use_deform = b.deform
        eb.align_roll(Vector(b.rest[:3, 2].tolist()))
        ebs[n] = eb
    for n in rig.order:
        par = rig.bones[n].parent
        if par:
            ebs[n].parent = ebs[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    worst = 0.0
    for n in rig.order:
        m = np.array(arm_data.bones[n].matrix_local)
        worst = max(worst, float(np.abs(m - rig.bones[n].rest).max()))
    if worst > 1e-4:
        raise RuntimeError(f"armature/rig mismatch: {worst}")
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return arm


def pose_matrices(rig: Rig, poser: Poser) -> Dict[str, np.ndarray]:
    return rig.fk(poser.pose)


def segment_weights(rig: Rig, verts: np.ndarray, sharpness: float = 2.6, spread: float = 0.4) -> np.ndarray:
    names = rig.deform_names
    W = np.zeros((len(verts), len(names)))
    for i, b in enumerate(names):
        bb = rig.bones[b]
        a, t = bb.head, bb.tail
        ab = t - a
        l2 = max(float(ab @ ab), 1e-9)
        u = np.clip(((verts - a) @ ab) / l2, 0.0, 1.0)
        d = np.linalg.norm(verts - (a + u[:, None] * ab), axis=1)
        r = 0.02 + spread * bb.length
        W[:, i] = np.exp(-((d / r) ** sharpness))
    return W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)


def pose_mesh(rig: Rig, poser: Poser, verts: np.ndarray, W: np.ndarray) -> np.ndarray:
    Wm = rig.fk(poser.pose)
    out = np.zeros_like(verts)
    vh = np.concatenate([verts, np.ones((len(verts), 1))], axis=1)
    for i, b in enumerate(rig.deform_names):
        w = W[:, i]
        if not np.any(w > 1e-4):
            continue
        M = Wm[b] @ np.linalg.inv(rig.bones[b].rest)
        out += w[:, None] * (vh @ M.T)[:, :3]
    return out
