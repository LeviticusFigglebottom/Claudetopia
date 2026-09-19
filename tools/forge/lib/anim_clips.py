"""The Wickmere humanoid clip library: every clip named in docs/CONTRACTS.md §3.

Clips are built from the generators in `anim.py` on the default proportions.  Combat clips
are authored so they read at a glance:

* a **telegraph** — the wind-up is a distinct, held silhouette lasting at least ~0.2 s
  (0.35 s+ on heavies) with the weapon clearly *back*, so a player can react;
* a **strike** — short, fast, travelling a long arc, with the hips and chest leading;
* a **follow-through** — the body commits past the impact and then settles, which is what
  sells weight and what makes the recovery window legible.

Weapon-bearing clips drive the hands by IK on the weapon grip (`Hand.R@grip` and
`Hand.R@aim`), so the blade traces an actual arc through space rather than whatever a pile
of joint angles happens to produce.
"""
from __future__ import annotations

import math
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig, anim
from .anim import (HIPS_POS, ClipBuilder, GaitParams, Pose, arc_point, body_point, breathing,
                   fall_clip, gait_clip, head_look, mirror_pose, pose_add, roll_clip, stance_feet,
                   sway, two_hand_grip)
from .rig import Skeleton, FWD, UP, LEFT

BACK = -FWD
RIGHT = -LEFT


# --------------------------------------------------------------------------------------
# stances and guards
# --------------------------------------------------------------------------------------

STAND: Pose = anim.STAND
GUARDS: Dict[str, Pose] = {
    "1h": anim.GUARD_1H,
    "2h": anim.GUARD_2H,
    "dagger": anim.GUARD_DAGGER,
    "unarmed": anim.GUARD_UNARMED,
}
# (lateral spread, left foot forward, right foot forward, left yaw, right yaw)
STANCES: Dict[str, Tuple[float, float, float, float, float]] = {
    "idle": (0.012, 0.0, 0.0, 7.0, -7.0),
    "combat": (0.035, 0.150, -0.105, 12.0, -26.0),
    "wide": (0.055, 0.180, -0.150, 14.0, -30.0),
    "crouch": (0.045, 0.100, -0.080, 10.0, -22.0),
}


def set_stance(cb: ClipBuilder, name: str = "combat") -> None:
    sp, fl, fr, yl, yr = STANCES[name]
    stance_feet(cb.feet, spread=sp, forward_l=fl, forward_r=fr, yaw_l=yl, yaw_r=yr)


def guard_of(kind: str) -> Pose:
    return dict(GUARDS[kind])


# --------------------------------------------------------------------------------------
# arc attacks
# --------------------------------------------------------------------------------------

class ArcKey:
    """One beat of a swing: when, where on the arc, and what the body does."""

    def __init__(self, t: float, angle: float, ease: str = "smooth", torso: Optional[Pose] = None,
                 radius: float = 1.0, lead: Optional[float] = None, hand_extra: Optional[Pose] = None):
        self.t = t
        self.angle = angle
        self.ease = ease
        self.torso = torso or {}
        self.radius = radius
        self.lead = lead
        self.hand_extra = hand_extra or {}


def _angle_at(keys: Sequence["ArcKey"], t: float) -> float:
    """The swing angle at normalised time t, honouring each key's easing."""
    if t <= keys[0].t:
        return keys[0].angle
    if t >= keys[-1].t:
        return keys[-1].angle
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a.t <= t <= b.t:
            x = anim.ease(b.ease, (t - a.t) / max(b.t - a.t, 1e-9))
            return a.angle + (b.angle - a.angle) * x
    return keys[-1].angle


def hit_window_from_arc(keys: Sequence["ArcKey"], arc: Tuple[float, float], samples: int = 400) -> Tuple[float, float]:
    """When the blade is inside the dangerous part of its arc.

    Deriving the hit window from the geometry rather than guessing times means the damage
    window always matches what the player sees, however the timing of the swing is retuned."""
    lo, hi = min(arc), max(arc)
    ts = [i / (samples - 1) for i in range(samples)]
    ang = [_angle_at(keys, t) for t in ts]
    # The guard pose can sit inside the arc too, so take the contiguous window around the
    # fastest part of the swing — the strike — not every moment the blade is in range.
    speed = [abs(ang[min(i + 1, samples - 1)] - ang[max(i - 1, 0)]) for i in range(samples)]
    peak = int(np.argmax(speed))
    # The fastest instant is usually just *before* the blade enters the arc (a snappy strike
    # accelerates from the wind-up), so take the first moment at or after the peak that is
    # inside the arc and grow the window around it.
    inside = [i for i in range(peak, samples) if lo <= ang[i] <= hi]
    if not inside:
        raise ValueError("swing never enters the hit arc after its fastest moment")
    i0 = i1 = inside[0]
    while i0 > 0 and lo <= ang[i0 - 1] <= hi:
        i0 -= 1
    while i1 < samples - 1 and lo <= ang[i1 + 1] <= hi:
        i1 += 1
    return ts[i0], ts[i1]


def arc_attack(skel: Skeleton, name: str, length: float, *, guard: str, centre: Tuple[float, float, float],
               normal: np.ndarray, ref: np.ndarray, radius: float, keys: Sequence[ArcKey],
               hit: Optional[Tuple[float, float]] = None, hit_arc: Optional[Tuple[float, float]] = None,
               cancel_ok: Optional[float] = None, cancel_delay: float = 0.09, two_handed: bool = False,
               lead: float = 0.0, grip_sep: float = 0.14, steps: Sequence[tuple] = (),
               stance: str = "combat", side: str = "R", off_hand: Optional[Callable[[float], Pose]] = None,
               extra_events: Sequence[Tuple[float, str]] = ()) -> ClipBuilder:
    """A melee swing whose weapon grip follows a circular arc.

    `centre` is body-relative (forward, left, up) from the Chest joint; `normal` is the axis
    of the swing plane and `ref` the direction of angle 0.  `keys` give the angle over time.
    The blade points radially outward from the centre, rotated by `lead` degrees in the
    plane (a positive lead makes the blade trail the hand, which reads as a heavier weapon).
    """
    cb = ClipBuilder(skel, name, length, loop=False, grounded=True)
    set_stance(cb, stance)
    s = skel.props.height / rig.DEFAULT_HEIGHT
    g = guard_of(guard)
    c = body_point(skel, *centre)
    n = rig._unit(np.asarray(normal, float))
    hand = f"Hand.{side}"
    other = "L" if side == "R" else "R"
    for st_side, t0, t1, (fwd, left), h in steps:
        base = skel.J[f"Foot.{st_side}"].copy()
        sp, fl, fr, _, _ = STANCES[stance]
        base[0] += (sp if st_side == "L" else -sp)
        base[1] -= (fl if st_side == "L" else fr)
        cb.feet.step(st_side, t0, t1, base + FWD * fwd * s + LEFT * left * s, height=h * s)
    for k in keys:
        grip = arc_point(c, n, ref, radius * s * k.radius, k.angle)
        radial = rig._unit(grip - c)
        aim = rig.rot_axis(n, math.radians(k.lead if k.lead is not None else lead)) @ radial
        pose: Pose = dict(g)
        pose.update(k.torso)
        pose[f"{hand}@grip"] = tuple(grip)
        pose[f"{hand}@aim"] = tuple(aim)
        if two_handed:
            pose[f"Hand.{other}@grip"] = tuple(two_hand_grip(grip, aim, grip_sep * s))
            pose[f"Hand.{other}@aim"] = tuple(aim)
        pose.update(k.hand_extra)
        cb.key(k.t * length, pose, k.ease)
    if off_hand is not None:
        cb.layer(off_hand)
    if hit is None:
        if hit_arc is None:
            raise ValueError(f"{name}: give hit or hit_arc")
        hit = hit_window_from_arc(keys, hit_arc)
    co = cancel_ok * length if cancel_ok is not None else min(hit[1] * length + cancel_delay, length - 0.02)
    cb.events_at(hit_start=hit[0] * length, hit_end=hit[1] * length, cancel_ok=co)
    for t, ev in extra_events:
        cb.event(t * length, ev)
    return cb


def _torso(f: float = 0.0, side: float = 0.0, turn: float = 0.0, hips_turn: float = 0.0,
           head_turn: float = 0.0, fwd: float = 0.0, left: float = 0.0, up: float = 0.0,
           shoulder: Optional[Tuple[float, float]] = None, side_r: str = "R") -> Pose:
    """Axial pose shorthand: the spine bends `f` forward, leans `side` left and turns `turn`
    left, split down the chain so the chest leads and the head counter-rotates a little."""
    p: Pose = {
        "Hips": (f * 0.25, side * 0.30, hips_turn),
        "Spine": (f * 0.40, side * 0.35, turn * 0.42),
        "Chest": (f * 0.35, side * 0.35, turn * 0.58),
        "Neck": (-f * 0.25, -side * 0.2, head_turn * 0.4),
        "Head": (-f * 0.20, -side * 0.2, head_turn * 0.6),
        HIPS_POS: (fwd, left, up),
    }
    if shoulder is not None:
        p[f"Shoulder.{side_r}"] = (shoulder[0], shoulder[1], 0.0)
    return p


# --------------------------------------------------------------------------------------
# locomotion
# --------------------------------------------------------------------------------------

def locomotion_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}

    idle = ClipBuilder(skel, "Idle", 4.0, loop=True, grounded=True)
    set_stance(idle, "idle")
    idle.key(0.0, pose_add(STAND, {"Shoulder.L": (0, 1, 0), "Shoulder.R": (0, 1, 0)}))
    idle.layer(breathing(period=4.0, amount=1.0))
    idle.layer(head_look(period=6.5, yaw=9.0, pitch=3.0))
    idle.layer(sway(period=5.0, amount=1.0))
    out["Idle"] = idle

    gi = ClipBuilder(skel, "Idle_Combat", 2.4, loop=True, grounded=True)
    set_stance(gi, "combat")
    g = guard_of("1h")
    gi.key(0.0, g)
    gi.key(1.2, pose_add(g, _torso(f=2, turn=-3, up=-0.012, left=0.010)), "smooth")
    gi.key(2.4, g, "smooth")
    gi.layer(breathing(period=2.4, amount=1.3))
    gi.layer(head_look(period=3.2, yaw=4.0, pitch=1.5))
    out["Idle_Combat"] = gi

    out["Walk"] = gait_clip(skel, "Walk", GaitParams(
        speed=1.55, period=1.0, duty=0.62, step_height=0.055, hip_bob=0.026, hip_sway=0.022,
        hip_yaw=6.5, hip_roll=3.0, lean=3.0, arm_swing=25.0, arm_bend=20.0, arm_bend_swing=16.0))

    out["Run"] = gait_clip(skel, "Run", GaitParams(
        speed=5.0, period=0.62, duty=0.40, step_height=0.155, hip_bob=0.048, hip_sway=0.016,
        hip_yaw=9.0, hip_roll=4.0, lean=13.0, arm_swing=42.0, arm_bend=78.0, arm_bend_swing=22.0,
        hands_up=True, flight=True, knee_lift=1.25, head_bob=0.6))

    out["Walk_Back"] = gait_clip(skel, "Walk_Back", GaitParams(
        speed=1.15, period=1.15, duty=0.60, direction=(0.0, -1.0), step_height=0.045,
        hip_bob=0.020, hip_sway=0.020, hip_yaw=3.0, hip_roll=2.5, lean=-3.0, arm_swing=16.0,
        arm_bend=24.0, arm_bend_swing=10.0))

    out["Strafe_L"] = gait_clip(skel, "Strafe_L", GaitParams(
        speed=1.9, period=0.95, duty=0.58, direction=(1.0, 0.0), step_height=0.055,
        hip_bob=0.018, hip_sway=0.010, hip_yaw=2.0, hip_roll=2.0, lean=2.0, arm_swing=8.0,
        arm_bend=30.0, arm_bend_swing=8.0, stance_width=1.2))
    out["Strafe_R"] = gait_clip(skel, "Strafe_R", GaitParams(
        speed=1.9, period=0.95, duty=0.58, direction=(-1.0, 0.0), step_height=0.055,
        hip_bob=0.018, hip_sway=0.010, hip_yaw=2.0, hip_roll=2.0, lean=2.0, arm_swing=8.0,
        arm_bend=30.0, arm_bend_swing=8.0, stance_width=1.2))

    sneak = ClipBuilder(skel, "Sneak_Idle", 3.6, loop=True, grounded=True)
    set_stance(sneak, "crouch")
    sneak.key(0.0, anim.CROUCH)
    sneak.layer(breathing(period=3.6, amount=0.7))
    sneak.layer(head_look(period=4.2, yaw=12.0, pitch=4.0))
    out["Sneak_Idle"] = sneak

    out["Sneak_Walk"] = gait_clip(skel, "Sneak_Walk", GaitParams(
        speed=0.95, period=1.35, duty=0.66, step_height=0.045, hip_bob=0.014, hip_sway=0.024,
        hip_yaw=4.0, hip_roll=2.0, lean=10.0, arm_swing=10.0, arm_bend=52.0, arm_bend_swing=8.0,
        crouch=0.185, heel_roll=0.25, stance_width=1.25, head_bob=0.3,
        extra_pose={"Spine": (16, 0, 0), "Chest": (6, 0, 0), "Neck": (-14, 0, 0), "Head": (-8, 0, 0),
                    "UpperArm.L": (10, 4, 0), "UpperArm.R": (10, 4, 0)}))

    # -- jump ---------------------------------------------------------------------------
    js = ClipBuilder(skel, "Jump_Start", 0.34, loop=False, grounded=True)
    set_stance(js, "idle")
    js.key(0.0, STAND)
    js.key(0.16, pose_add(STAND, {"Spine": (26, 0, 0), "Chest": (10, 0, 0), "Neck": (-18, 0, 0),
                                  "UpperArm.L": (-28, -6, 0), "UpperArm.R": (-28, -6, 0),
                                  "LowerArm.L": (34, 0, 0), "LowerArm.R": (34, 0, 0),
                                  HIPS_POS: (0.02, 0, -0.215)}), "in2")
    js.key(0.34, pose_add(STAND, {"Spine": (-6, 0, 0), "Chest": (-4, 0, 0), "Neck": (6, 0, 0),
                                  "UpperArm.L": (108, -20, 0), "UpperArm.R": (108, -20, 0),
                                  "LowerArm.L": (18, 0, 0), "LowerArm.R": (18, 0, 0),
                                  "Foot.L": (-34, 0, 0), "Foot.R": (-34, 0, 0),
                                  HIPS_POS: (0.02, 0, 0.055)}), "out")
    js.feet.pitch_fn["L"] = lambda t: -math.radians(42.0) * anim.clamp01((t - 0.2) / 0.14)
    js.feet.pitch_fn["R"] = js.feet.pitch_fn["L"]
    js.event(0.17, "footstep_l")
    js.event(0.17, "footstep_r")
    js.event(0.30, "jump_off")
    out["Jump_Start"] = js

    jl = ClipBuilder(skel, "Jump_Loop", 0.7, loop=True, grounded=False)
    air = {"Spine": (8, 0, 0), "Chest": (4, 0, 0), "Neck": (-6, 0, 0),
           "UpperArm.L": (62, -18, 0), "UpperArm.R": (62, -18, 0), "LowerArm.L": (54, 0, 0), "LowerArm.R": (54, 0, 0),
           "UpperLeg.L": (44, 6, 0), "UpperLeg.R": (14, 6, 0), "LowerLeg.L": (58, 0, 0), "LowerLeg.R": (26, 0, 0),
           "Foot.L": (-16, 0, 0), "Foot.R": (-24, 0, 0)}
    jl.key(0.0, air)
    jl.key(0.35, pose_add(air, {"UpperLeg.L": (-6, 0, 0), "UpperLeg.R": (10, 0, 0), "LowerLeg.L": (-8, 0, 0),
                                "UpperArm.L": (6, 4, 0), "UpperArm.R": (6, 4, 0), "Spine": (-3, 0, 0)}), "smooth")
    jl.key(0.7, air, "smooth")
    out["Jump_Loop"] = jl

    jland = ClipBuilder(skel, "Jump_Land", 0.52, loop=False, grounded=True)
    set_stance(jland, "idle")
    jland.key(0.0, {"Spine": (10, 0, 0), "Neck": (-8, 0, 0), "UpperArm.L": (40, -16, 0), "UpperArm.R": (40, -16, 0),
                    "LowerArm.L": (30, 0, 0), "LowerArm.R": (30, 0, 0), HIPS_POS: (0.0, 0, 0.045)}, "smooth")
    jland.key(0.14, {"Spine": (32, 0, 0), "Chest": (12, 0, 0), "Neck": (-22, 0, 0), "Head": (-8, 0, 0),
                     "UpperArm.L": (-22, -10, 0), "UpperArm.R": (-22, -10, 0),
                     "LowerArm.L": (56, 0, 0), "LowerArm.R": (56, 0, 0), HIPS_POS: (0.045, 0, -0.245)}, "snap")
    jland.key(0.32, {"Spine": (16, 0, 0), "Chest": (6, 0, 0), "Neck": (-10, 0, 0), "Head": (-4, 0, 0),
                     "UpperArm.L": (6, -30, 0), "UpperArm.R": (6, -30, 0),
                     "LowerArm.L": (28, 0, 0), "LowerArm.R": (28, 0, 0), HIPS_POS: (0.02, 0, -0.105)}, "out")
    jland.key(0.52, STAND, "out2")
    jland.event(0.10, "footstep_l")
    jland.event(0.11, "footstep_r")
    jland.event(0.30, "cancel_ok")
    out["Jump_Land"] = jland

    fall = ClipBuilder(skel, "Fall_Loop", 1.1, loop=True, grounded=False)
    base = {"Spine": (-6, 0, 0), "Chest": (-4, 0, 0), "Neck": (-10, 0, 0), "Head": (-6, 0, 0),
            "UpperArm.L": (96, -26, 0), "UpperArm.R": (96, -26, 0), "LowerArm.L": (40, 0, 0), "LowerArm.R": (40, 0, 0),
            "UpperLeg.L": (28, 10, 0), "UpperLeg.R": (10, 8, 0), "LowerLeg.L": (46, 0, 0), "LowerLeg.R": (30, 0, 0),
            "Foot.L": (-20, 0, 0), "Foot.R": (-20, 0, 0)}
    fall.key(0.0, base)
    fall.key(0.55, pose_add(base, {"UpperArm.L": (10, 8, 0), "UpperArm.R": (-10, 6, 0), "LowerArm.L": (12, 0, 0),
                                   "UpperLeg.L": (-16, 0, 0), "UpperLeg.R": (14, 0, 0), "Spine": (4, 3, 0),
                                   "Chest": (0, -3, 0), "Head": (0, 0, 8)}), "smooth")
    fall.key(1.1, base, "smooth")
    out["Fall_Loop"] = fall
    return out


# --------------------------------------------------------------------------------------
# dodges
# --------------------------------------------------------------------------------------

def dodge_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out = {}
    for d in ("F", "B", "L", "R"):
        cb = roll_clip(skel, f"Dodge_{d}", d, length=0.70, guard=guard_of("1h"))
        out[f"Dodge_{d}"] = cb
    return out


# --------------------------------------------------------------------------------------
# melee
# --------------------------------------------------------------------------------------

# Swing planes.  `normal` is the axis the arc turns about, `ref` the angle-0 direction.
#   vertical  : normal = LEFT, ref = UP    -> 0 overhead, +90 in front, +180 underneath
#   horizontal: normal = UP,   ref = FWD   -> 0 straight ahead, +90 to the character's left
#   diagonal  : a blend of the two, so the blade comes down across the body
PLANE_V = (LEFT, UP)
PLANE_H = (UP, FWD)


def plane_diag(tilt_deg: float) -> Tuple[np.ndarray, np.ndarray]:
    """A swing plane tilted from vertical towards horizontal by `tilt_deg`, i.e. the
    shoulder-to-hip diagonal every sword drill starts with."""
    n = rig.rot_axis(FWD, math.radians(tilt_deg)) @ LEFT
    return rig._unit(n), UP


def melee_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}
    shield_up: Pose = {"Shoulder.L": (14, 4, 0), "UpperArm.L": (54, -30, 0), "LowerArm.L": (94, 0, 0), "Hand.L": (0, 0, 0)}

    # -- 1H light 1: diagonal cut from the right shoulder down across the body ------------
    n, r0 = plane_diag(34.0)
    out["Attack_1H_Light_1"] = arc_attack(
        skel, "Attack_1H_Light_1", 0.78, guard="1h", centre=(0.02, -0.06, 0.20), normal=n, ref=r0,
        radius=0.54, lead=16.0,
        keys=[
            ArcKey(0.00, 96, "smooth", pose_add(guard_of("1h"), {})),
            # telegraph: blade cocked back over the right shoulder, chest turned away
            ArcKey(0.26, -46, "out2", pose_add(_torso(f=-4, side=-3, turn=-30, hips_turn=-12, head_turn=16),
                                               shield_up, {"Shoulder.R": (-8, 10, 0)})),
            ArcKey(0.36, -52, "smooth", pose_add(_torso(f=-2, side=-3, turn=-33, hips_turn=-14, head_turn=18),
                                                 shield_up, {"Shoulder.R": (-10, 12, 0)})),
            # strike: hips and chest whip through, blade sweeps down-left
            ArcKey(0.50, 78, "snap", pose_add(_torso(f=12, side=6, turn=30, hips_turn=18, head_turn=-8, fwd=0.07),
                                              shield_up, {"Shoulder.R": (16, -2, 0)})),
            ArcKey(0.60, 118, "out", pose_add(_torso(f=20, side=10, turn=42, hips_turn=24, head_turn=-12, fwd=0.09),
                                              shield_up, {"Shoulder.R": (20, -6, 0)})),
            ArcKey(0.78, 132, "out2", pose_add(_torso(f=22, side=11, turn=45, hips_turn=26, fwd=0.09), shield_up)),
            ArcKey(1.00, 96, "smooth", guard_of("1h")),
        ],
        hit_arc=(20, 118),
        steps=[("L", 0.30, 0.50, (0.22, 0.02), 0.045)])

    # -- 1H light 2: backhand horizontal return, left to right ---------------------------
    out["Attack_1H_Light_2"] = arc_attack(
        skel, "Attack_1H_Light_2", 0.72, guard="1h", centre=(0.06, -0.04, 0.12), normal=UP, ref=FWD,
        radius=0.55, lead=20.0,
        keys=[
            ArcKey(0.00, 4, "smooth", guard_of("1h")),
            ArcKey(0.24, 86, "out2", pose_add(_torso(f=4, side=4, turn=34, hips_turn=16, head_turn=-14, left=0.03),
                                              {"Shoulder.R": (-4, 8, 0), "Shoulder.L": (18, 2, 0),
                                               "UpperArm.L": (62, -22, 0), "LowerArm.L": (104, 0, 0)})),
            ArcKey(0.34, 94, "smooth", pose_add(_torso(f=5, side=5, turn=37, hips_turn=18, head_turn=-16, left=0.03),
                                                {"Shoulder.R": (-6, 9, 0), "Shoulder.L": (18, 2, 0),
                                                 "UpperArm.L": (64, -22, 0), "LowerArm.L": (104, 0, 0)})),
            ArcKey(0.50, -34, "snap", pose_add(_torso(f=8, side=-4, turn=-32, hips_turn=-18, head_turn=14, fwd=0.05),
                                               {"Shoulder.R": (14, 0, 0), "Shoulder.L": (2, 2, 0),
                                                "UpperArm.L": (34, -34, 0), "LowerArm.L": (70, 0, 0)})),
            ArcKey(0.62, -62, "out", pose_add(_torso(f=12, side=-7, turn=-44, hips_turn=-24, head_turn=18, fwd=0.05),
                                              {"Shoulder.R": (16, -4, 0), "UpperArm.L": (28, -36, 0), "LowerArm.L": (60, 0, 0)})),
            ArcKey(1.00, 4, "smooth", guard_of("1h")),
        ],
        hit_arc=(-52, 54),
        steps=[("R", 0.34, 0.54, (0.14, -0.06), 0.04)])

    # -- 1H light 3: rising cut into a thrust (the finisher) -----------------------------
    n3, r3 = plane_diag(-24.0)
    out["Attack_1H_Light_3"] = arc_attack(
        skel, "Attack_1H_Light_3", 0.88, guard="1h", centre=(0.04, -0.07, 0.06), normal=n3, ref=r3,
        radius=0.52, lead=8.0,
        keys=[
            ArcKey(0.00, 92, "smooth", guard_of("1h")),
            ArcKey(0.26, 156, "out2", pose_add(_torso(f=16, side=-6, turn=-22, hips_turn=-10, head_turn=10, up=-0.05),
                                               shield_up, {"Shoulder.R": (-6, 2, 0)})),
            ArcKey(0.36, 162, "smooth", pose_add(_torso(f=18, side=-7, turn=-24, hips_turn=-12, head_turn=11, up=-0.06),
                                                 shield_up, {"Shoulder.R": (-8, 2, 0)})),
            ArcKey(0.52, 34, "snap", pose_add(_torso(f=-8, side=4, turn=22, hips_turn=14, fwd=0.08, up=0.02),
                                              shield_up, {"Shoulder.R": (12, 8, 0)})),
            ArcKey(0.62, 6, "out", pose_add(_torso(f=-12, side=6, turn=30, hips_turn=18, fwd=0.11, up=0.03),
                                            shield_up, {"Shoulder.R": (16, 10, 0)}), radius=1.10),
            ArcKey(0.74, 10, "out2", pose_add(_torso(f=-10, side=5, turn=28, hips_turn=16, fwd=0.10), shield_up), radius=1.06),
            ArcKey(1.00, 92, "smooth", guard_of("1h")),
        ],
        hit_arc=(10, 140),
        steps=[("L", 0.30, 0.54, (0.30, 0.0), 0.05), ("R", 0.60, 0.78, (0.10, 0.0), 0.03)])

    # -- 1H heavy: a long, obvious overhead.  The telegraph is the whole point ------------
    out["Attack_1H_Heavy"] = arc_attack(
        skel, "Attack_1H_Heavy", 1.48, guard="1h", centre=(0.02, -0.05, 0.16), normal=LEFT, ref=UP,
        radius=0.56, lead=24.0, stance="wide",
        keys=[
            ArcKey(0.00, 84, "smooth", guard_of("1h")),
            # wind-up: blade all the way back and up, weight on the back foot, chest open
            ArcKey(0.22, -58, "out2", pose_add(_torso(f=-14, side=-4, turn=-24, hips_turn=-10, head_turn=12, fwd=-0.06, up=-0.02),
                                               shield_up, {"Shoulder.R": (-14, 14, 0)})),
            ArcKey(0.46, -74, "smooth", pose_add(_torso(f=-18, side=-5, turn=-28, hips_turn=-12, head_turn=14, fwd=-0.08, up=-0.03),
                                                 shield_up, {"Shoulder.R": (-16, 16, 0)})),
            ArcKey(0.56, -66, "in2", pose_add(_torso(f=-14, side=-4, turn=-24, hips_turn=-10, head_turn=12, fwd=-0.06, up=-0.02),
                                              shield_up, {"Shoulder.R": (-14, 14, 0)})),
            ArcKey(0.70, 96, "snap", pose_add(_torso(f=26, side=2, turn=10, hips_turn=8, fwd=0.10, up=-0.04),
                                              shield_up, {"Shoulder.R": (22, -4, 0)})),
            ArcKey(0.80, 132, "out", pose_add(_torso(f=40, side=4, turn=14, hips_turn=10, fwd=0.12, up=-0.10),
                                              shield_up, {"Shoulder.R": (26, -10, 0)})),
            ArcKey(0.88, 138, "out2", pose_add(_torso(f=42, side=4, turn=15, hips_turn=10, fwd=0.12, up=-0.11), shield_up)),
            ArcKey(1.00, 84, "smooth", guard_of("1h")),
        ],
        hit_arc=(24, 126), cancel_delay=0.12,
        steps=[("L", 0.52, 0.72, (0.34, 0.0), 0.07)],
        extra_events=[(0.20, "telegraph")])

    # -- 2H light 1: diagonal chop with both hands ---------------------------------------
    n2, r2 = plane_diag(28.0)
    out["Attack_2H_Light_1"] = arc_attack(
        skel, "Attack_2H_Light_1", 0.98, guard="2h", centre=(0.10, -0.03, 0.12), normal=n2, ref=r2,
        radius=0.56, lead=18.0, two_handed=True, stance="wide",
        keys=[
            ArcKey(0.00, 86, "smooth", guard_of("2h")),
            ArcKey(0.28, -44, "out2", _torso(f=-8, side=-4, turn=-32, hips_turn=-16, head_turn=16, fwd=-0.04)),
            ArcKey(0.42, -52, "smooth", _torso(f=-10, side=-5, turn=-36, hips_turn=-18, head_turn=18, fwd=-0.05)),
            ArcKey(0.58, 74, "snap", _torso(f=16, side=6, turn=26, hips_turn=18, head_turn=-8, fwd=0.08, up=-0.03)),
            ArcKey(0.70, 116, "out", _torso(f=30, side=10, turn=38, hips_turn=24, head_turn=-12, fwd=0.10, up=-0.08)),
            ArcKey(0.80, 124, "out2", _torso(f=32, side=11, turn=40, hips_turn=25, fwd=0.10, up=-0.09)),
            ArcKey(1.00, 86, "smooth", guard_of("2h")),
        ],
        hit_arc=(16, 116), cancel_delay=0.11,
        steps=[("L", 0.36, 0.60, (0.28, 0.02), 0.055)])

    # -- 2H light 2: horizontal sweep ----------------------------------------------------
    out["Attack_2H_Light_2"] = arc_attack(
        skel, "Attack_2H_Light_2", 0.96, guard="2h", centre=(0.12, 0.0, 0.05), normal=UP, ref=FWD,
        radius=0.58, lead=22.0, two_handed=True, stance="wide",
        keys=[
            ArcKey(0.00, 10, "smooth", guard_of("2h")),
            ArcKey(0.28, -78, "out2", _torso(f=-2, side=-5, turn=-44, hips_turn=-24, head_turn=22, left=-0.03)),
            ArcKey(0.42, -88, "smooth", _torso(f=-2, side=-6, turn=-48, hips_turn=-26, head_turn=24, left=-0.03)),
            ArcKey(0.60, 52, "snap", _torso(f=10, side=5, turn=40, hips_turn=26, head_turn=-14, fwd=0.06)),
            ArcKey(0.72, 92, "out", _torso(f=14, side=8, turn=54, hips_turn=34, head_turn=-18, fwd=0.06, left=0.04)),
            ArcKey(0.82, 100, "out2", _torso(f=14, side=8, turn=56, hips_turn=35, fwd=0.05, left=0.04)),
            ArcKey(1.00, 10, "smooth", guard_of("2h")),
        ],
        hit_arc=(-56, 60), cancel_delay=0.11,
        steps=[("R", 0.34, 0.56, (0.10, -0.14), 0.05), ("L", 0.60, 0.78, (0.10, 0.10), 0.04)])

    # -- 2H heavy: a committed overhead, the slowest and loudest telegraph in the set -----
    out["Attack_2H_Heavy"] = arc_attack(
        skel, "Attack_2H_Heavy", 1.92, guard="2h", centre=(0.10, -0.02, 0.14), normal=LEFT, ref=UP,
        radius=0.60, lead=26.0, two_handed=True, stance="wide",
        keys=[
            ArcKey(0.00, 80, "smooth", guard_of("2h")),
            ArcKey(0.20, -30, "out2", _torso(f=-12, turn=-18, hips_turn=-8, head_turn=8, fwd=-0.05, up=-0.03)),
            ArcKey(0.40, -76, "smooth", _torso(f=-22, turn=-24, hips_turn=-10, head_turn=12, fwd=-0.09, up=-0.05)),
            ArcKey(0.54, -84, "smooth", _torso(f=-24, turn=-26, hips_turn=-11, head_turn=13, fwd=-0.10, up=-0.06)),
            ArcKey(0.62, -72, "in2", _torso(f=-20, turn=-22, hips_turn=-9, head_turn=11, fwd=-0.08, up=-0.05)),
            ArcKey(0.76, 92, "snap", _torso(f=30, turn=8, hips_turn=6, fwd=0.10, up=-0.06)),
            ArcKey(0.86, 140, "out", _torso(f=48, turn=12, hips_turn=8, fwd=0.14, up=-0.16)),
            ArcKey(0.93, 146, "out2", _torso(f=50, turn=12, hips_turn=8, fwd=0.14, up=-0.17)),
            ArcKey(1.00, 80, "smooth", guard_of("2h")),
        ],
        hit_arc=(20, 132), cancel_delay=0.14,
        steps=[("L", 0.58, 0.78, (0.38, 0.0), 0.08)],
        extra_events=[(0.18, "telegraph")])

    # -- dagger 1: a short, fast stab ----------------------------------------------------
    dg = guard_of("dagger")
    d1 = ClipBuilder(skel, "Attack_Dagger_1", 0.52, loop=False, grounded=True)
    set_stance(d1, "combat")
    back = body_point(skel, -0.10, -0.20, 0.08)
    thrust = body_point(skel, 0.52, -0.04, 0.02)
    mid = body_point(skel, 0.12, -0.16, 0.06)
    fwd_aim = tuple(rig._unit(FWD + UP * -0.10))
    d1.key(0.00, {**dg, "Hand.R@grip": tuple(mid), "Hand.R@aim": fwd_aim})
    d1.key(0.18, pose_add(dg, _torso(f=6, turn=-22, hips_turn=-10, head_turn=10, fwd=-0.04)) |
           {"Hand.R@grip": tuple(back), "Hand.R@aim": tuple(rig._unit(FWD * 0.4 + UP * 0.2))}, "out2")
    d1.key(0.24, pose_add(dg, _torso(f=6, turn=-24, hips_turn=-11, head_turn=11, fwd=-0.04)) |
           {"Hand.R@grip": tuple(back), "Hand.R@aim": tuple(rig._unit(FWD * 0.4 + UP * 0.2))}, "smooth")
    d1.key(0.40, pose_add(dg, _torso(f=10, turn=26, hips_turn=16, fwd=0.10)) |
           {"Hand.R@grip": tuple(thrust), "Hand.R@aim": fwd_aim}, "snap")
    d1.key(0.50, pose_add(dg, _torso(f=12, turn=28, hips_turn=18, fwd=0.11)) |
           {"Hand.R@grip": tuple(thrust + FWD * 0.03), "Hand.R@aim": fwd_aim}, "out")
    d1.key(1.00, {**dg, "Hand.R@grip": tuple(mid), "Hand.R@aim": fwd_aim}, "smooth")
    for k in d1.track.keys:
        k.t *= 0.52
    d1.events_at(hit_start=0.20, hit_end=0.29, cancel_ok=0.36)
    d1.feet.step("L", 0.16, 0.30, skel.J["Foot.L"] + FWD * 0.22 + LEFT * 0.035, height=0.04)
    out["Attack_Dagger_1"] = d1

    # -- dagger 2: a slash across the throat ---------------------------------------------
    out["Attack_Dagger_2"] = arc_attack(
        skel, "Attack_Dagger_2", 0.48, guard="dagger", centre=(0.14, -0.04, 0.16), normal=UP, ref=FWD,
        radius=0.40, lead=30.0, stance="combat",
        keys=[
            ArcKey(0.00, 6, "smooth", dg),
            ArcKey(0.26, -62, "out2", pose_add(dg, _torso(f=4, turn=-30, hips_turn=-14, head_turn=14))),
            ArcKey(0.34, -68, "smooth", pose_add(dg, _torso(f=4, turn=-32, hips_turn=-15, head_turn=15))),
            ArcKey(0.56, 56, "snap", pose_add(dg, _torso(f=8, turn=32, hips_turn=18, fwd=0.07))),
            ArcKey(0.68, 78, "out", pose_add(dg, _torso(f=10, turn=40, hips_turn=22, fwd=0.07, left=0.03))),
            ArcKey(1.00, 6, "smooth", dg),
        ],
        hit_arc=(-62, 60))

    # -- unarmed ---------------------------------------------------------------------------
    ug = guard_of("unarmed")
    p1 = ClipBuilder(skel, "Attack_Unarmed_1", 0.52, loop=False, grounded=True)
    set_stance(p1, "combat")
    fist_home_r = body_point(skel, 0.20, -0.14, 0.14)
    fist_back_r = body_point(skel, 0.02, -0.20, 0.16)
    fist_out_r = body_point(skel, 0.56, -0.05, 0.14)
    p1.key(0.00, {**ug, "Hand.R@grip": tuple(fist_home_r), "Hand.R@aim": tuple(FWD)})
    p1.key(0.30 * 0.52, pose_add(ug, _torso(f=2, turn=-20, hips_turn=-10, head_turn=8, fwd=-0.03)) |
           {"Hand.R@grip": tuple(fist_back_r), "Hand.R@aim": tuple(FWD)}, "out2")
    p1.key(0.42 * 0.52, pose_add(ug, _torso(f=2, turn=-22, hips_turn=-11, head_turn=9, fwd=-0.03)) |
           {"Hand.R@grip": tuple(fist_back_r), "Hand.R@aim": tuple(FWD)}, "smooth")
    p1.key(0.62 * 0.52, pose_add(ug, _torso(f=6, turn=30, hips_turn=22, fwd=0.09)) |
           {"Hand.R@grip": tuple(fist_out_r), "Hand.R@aim": tuple(FWD)}, "snap")
    p1.key(0.74 * 0.52, pose_add(ug, _torso(f=8, turn=32, hips_turn=24, fwd=0.10)) |
           {"Hand.R@grip": tuple(fist_out_r + FWD * 0.02), "Hand.R@aim": tuple(FWD)}, "out")
    p1.key(0.52, {**ug, "Hand.R@grip": tuple(fist_home_r), "Hand.R@aim": tuple(FWD)}, "smooth")
    p1.events_at(hit_start=0.62 * 0.52 - 0.02, hit_end=0.78 * 0.52, cancel_ok=0.86 * 0.52)
    out["Attack_Unarmed_1"] = p1

    p2 = ClipBuilder(skel, "Attack_Unarmed_2", 0.58, loop=False, grounded=True)
    set_stance(p2, "combat")
    L = 0.58
    fist_home_l = body_point(skel, 0.22, 0.12, 0.14)
    hook_back_l = body_point(skel, 0.02, 0.26, 0.12)
    hook_out_l = body_point(skel, 0.44, -0.10, 0.18)
    p2.key(0.00, {**ug, "Hand.L@grip": tuple(fist_home_l), "Hand.L@aim": tuple(FWD)})
    p2.key(0.30 * L, pose_add(ug, _torso(f=2, turn=24, hips_turn=12, head_turn=-10, left=0.03)) |
           {"Hand.L@grip": tuple(hook_back_l), "Hand.L@aim": tuple(rig._unit(FWD + LEFT * 0.5))}, "out2")
    p2.key(0.42 * L, pose_add(ug, _torso(f=2, turn=26, hips_turn=13, head_turn=-11, left=0.03)) |
           {"Hand.L@grip": tuple(hook_back_l), "Hand.L@aim": tuple(rig._unit(FWD + LEFT * 0.5))}, "smooth")
    p2.key(0.64 * L, pose_add(ug, _torso(f=8, turn=-32, hips_turn=-22, fwd=0.08)) |
           {"Hand.L@grip": tuple(hook_out_l), "Hand.L@aim": tuple(rig._unit(FWD - LEFT * 0.4))}, "snap")
    p2.key(0.76 * L, pose_add(ug, _torso(f=10, turn=-36, hips_turn=-24, fwd=0.08)) |
           {"Hand.L@grip": tuple(hook_out_l + (-LEFT) * 0.04), "Hand.L@aim": tuple(rig._unit(FWD - LEFT * 0.5))}, "out")
    p2.key(L, {**ug, "Hand.L@grip": tuple(fist_home_l), "Hand.L@aim": tuple(FWD)}, "smooth")
    p2.events_at(hit_start=0.64 * L - 0.02, hit_end=0.80 * L, cancel_ok=0.88 * L)
    out["Attack_Unarmed_2"] = p2

    # -- riposte: a stylish committed thrust after a parry --------------------------------
    rp = ClipBuilder(skel, "Riposte", 0.95, loop=False, grounded=True)
    set_stance(rp, "combat")
    g1 = guard_of("1h")
    R = 0.95
    coil = body_point(skel, -0.02, -0.22, 0.14)
    lunge = body_point(skel, 0.62, -0.02, -0.02)
    rp.key(0.00, {**g1, "Hand.R@grip": tuple(body_point(skel, 0.20, -0.12, 0.10)), "Hand.R@aim": tuple(FWD)})
    rp.key(0.24 * R, pose_add(g1, _torso(f=-6, turn=-26, hips_turn=-12, head_turn=12, fwd=-0.06, up=-0.04)) |
           {"Hand.R@grip": tuple(coil), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.25))}, "out2")
    rp.key(0.36 * R, pose_add(g1, _torso(f=-6, turn=-28, hips_turn=-13, head_turn=13, fwd=-0.07, up=-0.05)) |
           {"Hand.R@grip": tuple(coil), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.25))}, "smooth")
    rp.key(0.54 * R, pose_add(g1, _torso(f=18, turn=24, hips_turn=16, fwd=0.16, up=-0.10)) |
           {"Hand.R@grip": tuple(lunge), "Hand.R@aim": tuple(rig._unit(FWD - UP * 0.06))}, "snap")
    rp.key(0.66 * R, pose_add(g1, _torso(f=20, turn=26, hips_turn=18, fwd=0.18, up=-0.12)) |
           {"Hand.R@grip": tuple(lunge + FWD * 0.04), "Hand.R@aim": tuple(rig._unit(FWD - UP * 0.06))}, "out")
    rp.key(R, {**g1, "Hand.R@grip": tuple(body_point(skel, 0.20, -0.12, 0.10)), "Hand.R@aim": tuple(FWD)}, "smooth")
    rp.feet.step("L", 0.32 * R, 0.56 * R, skel.J["Foot.L"] + FWD * 0.42 + LEFT * 0.035, height=0.06)
    rp.events_at(hit_start=0.50 * R, hit_end=0.68 * R, cancel_ok=0.80 * R)
    out["Riposte"] = rp

    # -- backstab: a downward stab into a target's back -----------------------------------
    bs = ClipBuilder(skel, "Backstab", 1.15, loop=False, grounded=True)
    set_stance(bs, "combat")
    B = 1.15
    high = body_point(skel, 0.10, -0.24, 0.34)
    low = body_point(skel, 0.34, -0.06, -0.24)
    down = tuple(rig._unit(-UP + FWD * 0.45))
    bs.key(0.00, {**dg, "Hand.R@grip": tuple(body_point(skel, 0.16, -0.16, 0.06)), "Hand.R@aim": tuple(FWD)})
    bs.key(0.26 * B, pose_add(dg, _torso(f=-8, turn=-20, hips_turn=-8, head_turn=10, up=0.02)) |
           {"Hand.R@grip": tuple(high), "Hand.R@aim": down}, "out2")
    bs.key(0.40 * B, pose_add(dg, _torso(f=-10, turn=-22, hips_turn=-9, head_turn=11, up=0.03)) |
           {"Hand.R@grip": tuple(high), "Hand.R@aim": down}, "smooth")
    bs.key(0.54 * B, pose_add(dg, _torso(f=34, turn=12, hips_turn=8, fwd=0.10, up=-0.14)) |
           {"Hand.R@grip": tuple(low), "Hand.R@aim": down}, "snap")
    bs.key(0.70 * B, pose_add(dg, _torso(f=40, turn=14, hips_turn=10, fwd=0.11, up=-0.18)) |
           {"Hand.R@grip": tuple(low - UP * 0.05), "Hand.R@aim": down}, "out")
    bs.key(0.86 * B, pose_add(dg, _torso(f=30, turn=10, hips_turn=8, fwd=0.08, up=-0.12)) |
           {"Hand.R@grip": tuple(low - UP * 0.04), "Hand.R@aim": down}, "smooth")
    bs.key(B, {**dg, "Hand.R@grip": tuple(body_point(skel, 0.16, -0.16, 0.06)), "Hand.R@aim": tuple(FWD)}, "smooth")
    bs.events_at(hit_start=0.50 * B, hit_end=0.66 * B, cancel_ok=0.90 * B)
    out["Backstab"] = bs
    return out
