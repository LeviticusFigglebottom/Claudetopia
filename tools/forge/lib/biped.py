"""A giant's two legs: the rig and the posing shared by the stone-thrall and the warden.

On lib/creature_rig.Rig. The bones (any of them may be left out of a body that lacks it):

    Hips > Spine > Chest > Neck > Head > Jaw
    Chest > Shoulder.L > UpperArm.L > Forearm.L > Hand.L        (and .R)
    Hips > Thigh.L > Shin.L > Foot.L                             (and .R)

`BPose` says what the body does -- the hips' place and lean, the back's bend and twist, the head,
where each hand reaches (in the body's own frame, carried with the chest) and where each foot is
set (on the ground, in the armature's frame) -- and `pose()` turns it into a Poser: the legs and
the arms by two-bone IK, the feet laid along the ground, the hands aimed along the forearm.
`walk()` makes a loop from footfalls: each foot planted for its share of the cycle, the hips
rising over the planted leg and swaying to it, the arms swinging against the legs.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Dict, Optional, Tuple

import numpy as np

from .anim import FPS
from .rig import rot_axis, UP, FWD, LEFT
from .creature_rig import Rig, Poser, RigClip, _u

SIDES = ("L", "R")


def make_rig(rig_id: str, J: Dict[str, Tuple[float, float, float]], height: float) -> Rig:
    """J: the joints' heads at rest, left side only (mirrored), plus the tips: HeadTip, JawTip,
    Hand.L tip as HandTip.L, Foot.L tip as Toe.L."""
    P = {k: np.array(v, float) for k, v in J.items()}
    for k in list(P):
        if k.endswith(".L"):
            P[k[:-2] + ".R"] = P[k] * np.array([-1.0, 1.0, 1.0])
    bones = [("Hips", None, P["Hips"], P["Spine"], -FWD), ("Spine", "Hips", P["Spine"], P["Chest"], -FWD),
             ("Chest", "Spine", P["Chest"], P["Neck"], -FWD), ("Neck", "Chest", P["Neck"], P["Head"], -FWD),
             ("Head", "Neck", P["Head"], P["HeadTip"], UP)]
    if "Jaw" in P:
        bones.append(("Jaw", "Head", P["Jaw"], P["JawTip"], UP))
    for s in SIDES:
        bones += [("Shoulder." + s, "Chest", P["Shoulder." + s], P["UpperArm." + s], UP),
                  ("UpperArm." + s, "Shoulder." + s, P["UpperArm." + s], P["Forearm." + s], FWD),
                  ("Forearm." + s, "UpperArm." + s, P["Forearm." + s], P["Hand." + s], FWD),
                  ("Hand." + s, "Forearm." + s, P["Hand." + s], P["HandTip." + s], FWD),
                  ("Thigh." + s, "Hips", P["Thigh." + s], P["Shin." + s], FWD),
                  ("Shin." + s, "Thigh." + s, P["Shin." + s], P["Foot." + s], FWD),
                  ("Foot." + s, "Shin." + s, P["Foot." + s], P["Toe." + s], UP)]
    rig = Rig(rig_id, bones, height=height)
    rig.points = P
    return rig


@dataclass
class BPose:
    lift: float = 0.0
    ahead: float = 0.0
    side: float = 0.0
    lean: float = 0.0          # the whole body pitched forward over the hips, degrees
    roll: float = 0.0          # the left side down, degrees
    yaw: float = 0.0           # turned to the left, degrees
    bend: float = 0.0          # the back bent forward (spine and chest), degrees
    twist: float = 0.0         # the chest turned to the left against the hips, degrees
    side_bend: float = 0.0     # the back bent to the left, degrees
    neck: float = 0.0          # the head lowered at the neck, degrees
    head: float = 0.0          # nodded down, degrees
    head_turn: float = 0.0
    jaw: float = 0.0
    hands: Dict[str, np.ndarray] = field(default_factory=dict)   # side -> offset from the rest hand, chest frame
    hand_abs: Dict[str, np.ndarray] = field(default_factory=dict)  # side -> armature-space target
    elbow: Dict[str, np.ndarray] = field(default_factory=dict)   # side -> pole (chest frame)
    fist: Dict[str, float] = field(default_factory=dict)         # side -> the hand bent down, degrees
    feet: Dict[str, np.ndarray] = field(default_factory=dict)    # side -> ankle (armature), else at rest
    toe: Dict[str, float] = field(default_factory=dict)          # side -> the foot's pitch, toes down, degrees
    knee: Dict[str, np.ndarray] = field(default_factory=dict)    # side -> knee pole
    foot_dir: Dict[str, np.ndarray] = field(default_factory=dict)  # side -> the foot's line (armature)
    pivot: Optional[np.ndarray] = None


def chest_frame(rig: Rig, p: Poser) -> np.ndarray:
    """The chest's world transform against its rest: a point carried rigidly with the chest."""
    return p.world("Chest") @ np.linalg.inv(rig.bones["Chest"].rest)


def pose(rig: Rig, bp: BPose) -> Poser:
    p = Poser(rig)
    R = rot_axis(UP, math.radians(bp.yaw)) @ rot_axis(LEFT, math.radians(bp.lean)) @ rot_axis(FWD, math.radians(-bp.roll))
    p.move_hips(R, np.array([bp.side, -bp.ahead, bp.lift]), pivot=bp.pivot)
    for name, share in (("Spine", 0.45), ("Chest", 0.55)):
        p.turn(name, rot_axis(UP, math.radians(bp.twist * share)) @ rot_axis(LEFT, math.radians(bp.bend * share))
               @ rot_axis(FWD, math.radians(-bp.side_bend * share)))
    p.turn("Neck", rot_axis(LEFT, math.radians(bp.neck)) @ rot_axis(UP, math.radians(bp.head_turn * 0.5)))
    p.turn("Head", rot_axis(LEFT, math.radians(bp.head)) @ rot_axis(UP, math.radians(bp.head_turn * 0.5)))
    if "Jaw" in rig.bones:
        p.turn("Jaw", rot_axis(LEFT, math.radians(bp.jaw)))
    # the arms: each hand to its target, the elbow out and back
    for s in SIDES:
        if "UpperArm." + s not in rig.bones:
            continue
        sx = 1.0 if s == "L" else -1.0
        M = chest_frame(rig, p)
        rest_hand = rig.points["Hand." + s]
        if s in bp.hand_abs:
            target = np.asarray(bp.hand_abs[s], float)
        else:
            off = bp.hands.get(s, np.zeros(3))
            target = (M @ np.append(rest_hand + off, 1.0))[:3]
        pole_b = bp.elbow.get(s, np.array([sx * 0.6, 1.0, 0.0]))
        pole = M[:3, :3] @ pole_b
        p.two_bone("UpperArm." + s, "Forearm." + s, target, pole)
        fa = p.tail("Forearm." + s) - p.world("Forearm." + s)[:3, 3]
        down = M[:3, :3] @ np.array([0.0, 0.0, -1.0])
        f = math.radians(bp.fist.get(s, 0.0))
        p.aim("Hand." + s, _u(fa) * math.cos(f) + down * math.sin(f) if f else fa)
    # the legs: each ankle to its place, the knee forward, the foot along the ground
    for s in SIDES:
        rest_ankle = rig.points["Foot." + s]
        ankle = np.asarray(bp.feet.get(s, rest_ankle), float)
        hips_R = p.world("Hips")[:3, :3] @ rig.bones["Hips"].rest[:3, :3].T
        pole = bp.knee.get(s, hips_R @ np.array([0.0, -1.0, 0.15]))
        p.two_bone("Thigh." + s, "Shin." + s, ankle, pole)
        rest_dir = rig.points["Toe." + s] - rig.points["Foot." + s]
        d = bp.foot_dir.get(s) if s in bp.foot_dir else rot_axis(LEFT, math.radians(bp.toe.get(s, 0.0))) @ rest_dir
        p.aim("Foot." + s, d)
    return p


def smooth(x: float) -> float:
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def bump(x: float, peak: float = 0.5) -> float:
    x = min(1.0, max(0.0, x))
    if x < peak:
        return math.sin(0.5 * math.pi * x / peak) ** 2
    return math.sin(0.5 * math.pi * (1.0 - x) / (1.0 - peak)) ** 2


def walk(rig: Rig, name: str, speed: float, cycle: float, duty: float = 0.62, lift: float = 0.18,
         bob: float = 0.05, sway: float = 0.06, arm_swing: float = 0.25, lean: float = 6.0,
         way: Tuple[float, float] = (0.0, 1.0), turn: float = 0.0, extra_fn: Callable = None,
         stance_w: float = 1.0) -> RigClip:
    """A lumbering loop: the left foot lands at phase 0, the right at 0.5; a planted foot stays put
    while the body goes on at `speed` (its travel is `way` in the body's frame, +Y back: forward)."""
    stride = speed * cycle
    stance = stride * duty
    wv = np.array([way[0], way[1], 0.0])
    P = rig.points

    def sample(t: float) -> Poser:
        ph = (t / cycle) % 1.0
        bp = BPose(lean=lean)
        for s, land in (("L", 0.0), ("R", 0.5)):
            u = (ph - land) % 1.0
            rest = P["Foot." + s].copy()
            rest[0] *= stance_w
            if turn:
                a0, a1 = math.radians(turn * duty * 0.5), -math.radians(turn * duty * 0.5)
            if u < duty:
                w = u / duty
                if turn:
                    a = a0 + (a1 - a0) * w
                    pos = rot_axis(UP, a) @ rest
                    pos[2] = rest[2]
                else:
                    pos = rest + wv * stance * (w - 0.5)
                bp.toe[s] = -12.0 * smooth((w - 0.75) / 0.25)
            else:
                w = (u - duty) / (1.0 - duty)
                sw = 0.5 - 0.5 * math.cos(math.pi * w)
                if turn:
                    a = a1 + (a0 - a1) * sw
                    pos = rot_axis(UP, a) @ rest
                    pos[2] = rest[2]
                else:
                    pos = rest + wv * stance * (0.5 - sw)
                pos = pos + np.array([0.0, 0.0, lift * math.sin(math.pi * w)])
                bp.toe[s] = 18.0 * math.sin(math.pi * w) - 12.0 * (1.0 - smooth(w / 0.3))
            bp.feet[s] = pos
        # the body rides over the planted foot: down at each landing, swaying to the side bearing
        bp.lift = -bob * 0.5 + bob * 0.5 * math.cos(4 * math.pi * (ph - 0.25))
        bp.side = sway * math.cos(2 * math.pi * ph)
        bp.roll = 3.0 * math.cos(2 * math.pi * ph)
        bp.twist = 6.0 * math.sin(2 * math.pi * ph)
        bp.yaw = -2.0 * math.sin(2 * math.pi * ph)
        for s, sgn in (("L", -1.0), ("R", 1.0)):
            sw_ = sgn * math.sin(2 * math.pi * ph) * arm_swing
            bp.hands[s] = np.array([0.0, sw_ * way[1], 0.04 * abs(sw_)])
        bp.neck = 4.0 * math.cos(4 * math.pi * ph)
        if extra_fn:
            extra_fn(bp, ph)
        return pose(rig, bp)
    extra = {"speed": round(speed * (1.0 if way[1] >= 0 else -1.0), 4)} if not turn else {"turn": turn}
    if way[0] and not way[1]:
        extra = {"speed": round(speed, 4), "side": way[0]}
    return RigClip(name, cycle, True, sample, [(0.0, "footstep_l"), (round(cycle * 0.5, 4), "footstep_r")], extra)
