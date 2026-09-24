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
from .anim import FPS

BACK = -FWD
RIGHT = -LEFT


# --------------------------------------------------------------------------------------
# stances and guards
# --------------------------------------------------------------------------------------

STAND: Pose = anim.STAND
# Standing at rest: the weight on the left leg, the pelvis over that foot and dropped on the free side,
# the chest tipped back against it; the shoulders let down and the arms hanging at the sides, the
# elbows soft and a touch behind, the hands beside the thighs with the fingers turned in towards them.
# The wrists hang 23 cm out from the pelvis centre, 5 cm outside the default body's hip: close enough
# to read as arms at rest, far enough for the hand to clear a skirt, a gambeson or a fauld.  STAND held
# the arms some 10 degrees out with the wrists at 29 cm, which read as an A-pose.
RELAXED: Pose = pose_add(STAND, {
    "UpperArm.L": (-8, -3, -5), "UpperArm.R": (-8, -4, -12),
    "Hand.L": (0, -5, 0), "Hand.R": (0, -3, 0),
    "Hips": (0, -3, 3), "Spine": (0, 1.2, -1.5), "Chest": (0, 1.4, -1.5),
    "Shoulder.L": (0, -2, 0), "Shoulder.R": (0, -2, 0),
    HIPS_POS: (0.0, 0.018, -0.006)})
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


def _arc_at(keys: Sequence["ArcKey"], t: float, lead: float) -> Tuple[float, float, float]:
    """The swing's angle, radius (a fraction of the arc's) and lead at normalised time t, each
    eased between the keys as the angle is."""
    def lead_of(k: "ArcKey") -> float:
        return k.lead if k.lead is not None else lead
    if t <= keys[0].t:
        k = keys[0]
        return k.angle, k.radius, lead_of(k)
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a.t <= t <= b.t:
            x = anim.ease(b.ease, (t - a.t) / max(b.t - a.t, 1e-9))
            return (a.angle + (b.angle - a.angle) * x, a.radius + (b.radius - a.radius) * x,
                    lead_of(a) + (lead_of(b) - lead_of(a)) * x)
    k = keys[-1]
    return k.angle, k.radius, lead_of(k)


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
               extra_events: Sequence[Tuple[float, str]] = (), entry: Optional[Pose] = None) -> ClipBuilder:
    """A melee swing whose weapon grip follows a circular arc.

    `entry`, for a swing that only ever follows another in a chain, is the pose the swing begins in:
    the one before it, as it is at its cancel_ok, when the chain hands over. The swing moves from it
    to its first key (which is then later than 0) off the arc, then keeps to the arc. The engine's
    cross-fade composes each bone's turn from its rest, one clip's over the other's, and between
    two very different hands that swung a spear's butt through the chest.

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
    if entry is not None:
        if keys[0].t <= 0.0:
            raise ValueError(f"{name}: a swing with an entry begins its arc after 0")
        cb.key(0.0, dict(entry))
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

    # Between keys the track would carry the grip along the chord, and a swing that turns a
    # hundred degrees or more between two keys cuts across its own arc, through the head and the
    # chest (the heavies' hands went 6 cm into the torso). Keep the grip on the arc: the angle,
    # the radius and the lead eased between the keys as the keys ease.
    def on_arc(t: float, p: Pose) -> Pose:
        u = t / length
        if entry is not None and u < keys[0].t:
            return p            # coming from the entry, off the arc
        ang, rad, ld = _arc_at(keys, u, lead)
        grip = arc_point(c, n, ref, radius * s * rad, ang)
        aim = rig.rot_axis(n, math.radians(ld)) @ rig._unit(grip - c)
        p = dict(p)
        p[f"{hand}@grip"] = tuple(grip)
        p[f"{hand}@aim"] = tuple(aim)
        if two_handed:
            p[f"Hand.{other}@grip"] = tuple(two_hand_grip(grip, aim, grip_sep * s))
            p[f"Hand.{other}@aim"] = tuple(aim)
        return p
    cb.post.append(on_arc)
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


## How a struck body goes into its flinch. "snap" put 70% of the throw into the first frame at 60 Hz,
## so a stagger's hand jumped 49 cm in one frame and the body read as popping, not struck; "out2" is
## 31-37%, and the blow still lands inside a frame or two.
REACT_EASE = "out2"


def reaction_clip(skel: Skeleton, name: str, length: float, guard: Pose, push: Tuple[float, float],
                  stagger: bool) -> "ClipBuilder":
    """A body struck and thrown along `push` (forward, left, in the body's frame): a light flinch
    (0.42 s) or a stagger (1.05 s) that steps to keep its feet, from a guard and back to it.

    The spine gives along the push and turns away from the blow's side, the head whips the other
    way a little, the arms fly out off the guard, and the hips are carried along the push. A
    stagger is the same, twice over and held longer, and takes three steps the way it was thrown:
    the foot on the far side leads, so the legs never cross."""
    s = skel.props.height / rig.DEFAULT_HEIGHT
    pf, pl = push
    amp = 2.1 if stagger else 1.0
    cb = ClipBuilder(skel, name, length, loop=False, grounded=True)
    set_stance(cb, "combat")
    flail = {"Shoulder.R": (-8, 6, 0), "UpperArm.R": (-12, 8, 0), "UpperArm.L": (-10, 6, 0)}
    if stagger:
        flail = {"UpperArm.R": (-30, 22, 0), "UpperArm.L": (-28, 22, 0), "LowerArm.R": (-14, 0, 0), "LowerArm.L": (-12, 0, 0)}

    def thrown(k: float, arms: float) -> Pose:
        p = _torso(f=26.0 * pf * amp * k, side=26.0 * pl * amp * k, turn=-15.0 * pl * amp * k,
                   head_turn=8.0 * pl * amp * k,
                   fwd=0.055 * pf * amp * k * s, left=0.055 * pl * amp * k * s, up=-0.02 * amp * k * s)
        for b, v in flail.items():
            p[b] = (v[0] * arms, v[1] * arms, v[2] * arms)
        return pose_add(guard, p)

    if not stagger:
        cb.key(0.0, guard)
        cb.key(0.10, thrown(1.0, 1.0), REACT_EASE)
        cb.key(0.22, thrown(0.3, 0.3), "smooth")
        cb.key(0.42, guard, "out2")
        cb.event(0.01, "hit_react")
        cb.event(0.26, "cancel_ok")
        return cb
    cb.key(0.0, guard)
    cb.key(0.15, thrown(1.0, 1.0), REACT_EASE)
    cb.key(0.34, thrown(0.85, 0.8), "smooth")
    cb.key(0.58, thrown(0.5, 0.5), "smooth")
    cb.key(0.80, thrown(0.18, 0.15), "out")
    cb.key(1.05, guard, "out2")
    way = FWD * pf + LEFT * pl
    sp, fl, fr = STANCES["combat"][0], STANCES["combat"][1], STANCES["combat"][2]
    if abs(pl) > 0.5:
        lead = "L" if pl > 0 else "R"
        other = "R" if lead == "L" else "L"
        order = ((lead, 0.05, 0.26, 0.22), (other, 0.24, 0.46, 0.20), (lead, 0.46, 0.68, 0.12))
    else:
        order = (("R", 0.05, 0.26, 0.26), ("L", 0.24, 0.46, 0.30), ("R", 0.46, 0.68, 0.18))
    for side, t0, t1, d in order:
        base = skel.J[f"Foot.{side}"].copy() + LEFT * (sp if side == "L" else -sp) + FWD * (fl if side == "L" else fr)
        cb.feet.step(side, t0 * length / 1.05, t1 * length / 1.05, base + way * d * s, height=0.05 * s)
        cb.event(t1 * length / 1.05, "footstep_l" if side == "L" else "footstep_r")
    cb.event(0.01, "hit_react")
    cb.event(0.86, "cancel_ok")
    return cb


def hips_still(fn: Callable[[float], Pose]) -> Callable[[float], Pose]:
    """A layer with its movement of the hips taken out: the upper body sways and breathes over legs
    that stand still. The relaxed Idle's bent legs turned at every joint to keep the feet down while
    the hips swayed, and the engine's import thins those curves: the feet the bake holds still
    wandered 2 mm, and the foot planter snapped them back and forth for a second after every stop."""
    def fn2(t: float) -> Pose:
        p = dict(fn(t))
        p.pop(HIPS_POS, None)
        return p
    return fn2


def hanging_arms(period: float, amount: float = 1.0) -> Callable[[float], Pose]:
    """The arms go on hanging while a breath lifts the shoulders: the breathing layer's shoulder
    roll, taken back at the upper arm.  Without it every breath swung the hands of the relaxed
    Idle 3 cm out from the thighs and back."""
    def fn(t: float) -> Pose:
        b = math.sin(2 * math.pi * t / period)
        return {"UpperArm.L": (0, -1.5 * amount * b, 0), "UpperArm.R": (0, -1.5 * amount * b, 0)}
    return fn


# --------------------------------------------------------------------------------------
# locomotion
# --------------------------------------------------------------------------------------

def locomotion_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}

    idle = ClipBuilder(skel, "Idle", 4.0, loop=True, grounded=True)
    # The weight sits on the left leg (RELAXED's hips), and the feet stand where the foot planter
    # and the turns on the spot put them: in the "rest" stance, the free right foot 3.5 cm forward
    # and turned out 13 degrees, a stop from a walk went on stepping for 1.1 s and an about-face
    # slid the feet 7.4 cm settling into it (test_locomotion_blend).
    set_stance(idle, "idle")
    idle.key(0.0, RELAXED)
    idle.layer(hips_still(breathing(period=4.0, amount=1.0)))
    idle.layer(hanging_arms(period=4.0, amount=1.0))
    idle.layer(head_look(period=6.5, yaw=9.0, pitch=3.0))
    idle.layer(hips_still(sway(period=5.0, amount=1.0)))
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

    # The three gaits of DESIGN §5.2, each at the ground speed the game moves the body at, so the
    # game plays it at rate 1 and nothing slides. Measured on the default rig (tools/forge/tests):
    # hips 4.0 / 4.0 / 4.2 cm below standing on average and 5.1 / 5.3 / 6.3 cm peak to peak, where
    # the first Walk and Run went 13.5 and 25.2 cm deep at every contact. Cadences 125, 171 and 200
    # steps a minute; knees at mid-stance 23, 40 and 46 degrees; lean 4, 8 and 13 degrees.
    # Every loop is a whole number of frames (29 at 30 fps here, where it was 0.96 s, 28.8 frames):
    # the bake samples each frame, and a cycle that ends between two of them cannot close on a key.
    out["Walk"] = gait_clip(skel, "Walk", GaitParams(
        speed=1.8, period=29.0 / FPS, duty=0.60, contact_ahead=0.38, bob_mode="walk", hip_drop=0.02,
        hip_bob=0.012, soft_reach=0.05, heel_strike=18.0, land_pitch=18.0, heel_rise=60.0,
        heel_rise_from=0.5, swing_from_pitch=-60.0, step_height=0.10, swing_peak=0.75,
        hip_sway=0.02, hip_yaw=8.0, hip_roll=3.0, lean=4.0, arm_swing=24.0, arm_bend=18.0,
        arm_bend_swing=14.0))

    # A slow run, between the brisk walk and the jog: the pace a locked-on body goes at on the
    # diagonal ahead (3.64 m/s), where a walk and a jog blended half and half put their feet down
    # for different shares of a stride and the feet slid 11 cm a stride.
    out["Trot"] = gait_clip(skel, "Trot", GaitParams(
        speed=3.6, period=22.0 / FPS, duty=0.36, contact_ahead=0.34, bob_mode="run", hip_drop=0.03,
        hip_bob=0.02, soft_reach=0.05, heel_strike=8.0, land_pitch=8.0, heel_rise=65.0,
        heel_rise_from=0.4, swing_from_pitch=-65.0, step_height=0.18, swing_peak=0.72,
        knee_drive=0.06, swing_settle=0.7, hip_sway=0.013, hip_yaw=7.0, hip_roll=3.5, lean=7.0,
        arm_swing=32.0, arm_bend=75.0, arm_bend_swing=14.0, hands_up=True, head_bob=0.65))

    # The default gait (the contract's name for it is Run): a jog.
    out["Run"] = gait_clip(skel, "Run", GaitParams(
        speed=5.0, period=0.70, duty=0.28, contact_ahead=0.33, bob_mode="run", hip_drop=0.035,
        hip_bob=0.025, soft_reach=0.05, heel_strike=6.0, land_pitch=6.0, heel_rise=72.0,
        heel_rise_from=0.35, swing_from_pitch=-72.0, step_height=0.24, swing_peak=0.7,
        knee_drive=0.10, swing_settle=0.5, hip_sway=0.012, hip_yaw=7.0, hip_roll=4.0, lean=9.0,
        arm_swing=38.0, arm_bend=80.0, arm_bend_swing=16.0, hands_up=True, head_bob=0.6))

    out["Sprint"] = gait_clip(skel, "Sprint", GaitParams(
        speed=7.8, period=0.60, duty=0.21, contact_ahead=0.34, bob_mode="run", hip_drop=0.04,
        hip_bob=0.03, soft_reach=0.06, heel_strike=4.0, land_pitch=4.0, heel_rise=75.0,
        heel_rise_from=0.3, swing_from_pitch=-75.0, step_height=0.36, swing_peak=0.6,
        knee_drive=0.26, swing_settle=0.15, hip_sway=0.012, hip_yaw=9.0, hip_roll=4.0, lean=15.0,
        arm_swing=55.0, arm_bend=85.0, arm_bend_swing=10.0, hands_up=True, head_bob=0.6))

    # The backpedal and the side-steps are the locked-on pace (Player.LOCKED_BACK and LOCKED_SIDE,
    # DECISIONS "Locked on, the pace goes by the way you go"), on the stride model. Made at 1.15
    # and 1.9 m/s on the first model, they were played at 1.57x and 1.58x to keep up: five steps a
    # second sideways. A backpedal is short quick steps, down on the ball and rolled back onto the
    # heel; a side-step at 3 m/s is a shuffle with a little flight, the swing foot passing in front
    # of the planted one, the spine leaning into the way it goes.
    out["Walk_Back"] = gait_clip(skel, "Walk_Back", GaitParams(
        speed=1.8, period=18.0 / FPS, duty=0.52, direction=(0.0, -1.0), contact_ahead=0.42,
        bob_mode="walk", hip_drop=0.025, hip_bob=0.010, soft_reach=0.04, heel_strike=12.0,
        land_pitch=12.0, heel_rise=22.0, heel_rise_from=0.62, swing_from_pitch=18.0,
        step_height=0.065, swing_peak=0.8, hip_sway=0.015, hip_yaw=3.0, hip_roll=2.0, lean=3.0,
        arm_swing=12.0, arm_bend=28.0, arm_bend_swing=8.0))

    # A side-step is short and quick: legs can spread sideways only so far before the hips have to
    # drop to reach. At 0.95 s and duty 0.58 each foot swept 1.05 m sideways and the hips fell
    # 21.3 cm at every step (19.8 cm peak to peak), a bounce that read as a crouch whenever the
    # player was locked on. At 3 m/s, 14 frames and duty 0.42 each foot sweeps 0.59 m.
    for name, way in (("Strafe_L", 1.0), ("Strafe_R", -1.0)):
        out[name] = gait_clip(skel, name, GaitParams(
            speed=3.0, period=14.0 / FPS, duty=0.42, direction=(way, 0.0), contact_ahead=0.5,
            bob_mode="run", hip_drop=0.03, hip_bob=0.012, soft_reach=0.05, heel_strike=0.0,
            land_pitch=0.0, heel_rise=0.0, swing_from_pitch=12.0, step_height=0.075, swing_peak=0.8,
            hip_sway=0.008, hip_yaw=2.0, hip_roll=2.0, lean=3.0, arm_swing=6.0, arm_bend=34.0,
            arm_bend_swing=6.0, stance_width=1.25, swing_cross=0.16, side_lean=4.0))

    # Turning on the spot (DESIGN §5.2): the body is turned in code and these are played at the
    # rate it turns, a cycle for every `turn` degrees, the way a gait is played at the ground's
    # speed. A quarter turn is two steps round; the about-face is quicker and wider, the lead foot
    # opening a long pivot step and the other swinging round after it.
    spread, toe_out = STANCES["idle"][0], STANCES["idle"][3]
    out["Turn_L90"] = anim.turn_clip(skel, "Turn_L90", 90.0, 21.0 / FPS, 0.06, 0.44, 0.50, 0.90,
                                     spread=spread, toe_out=toe_out)
    out["Turn_R90"] = anim.turn_clip(skel, "Turn_R90", -90.0, 21.0 / FPS, 0.06, 0.44, 0.50, 0.90,
                                     spread=spread, toe_out=toe_out)
    out["Turn_L180"] = anim.turn_clip(skel, "Turn_L180", 180.0, 18.0 / FPS, 0.04, 0.40, 0.46, 0.86,
                                      pivot=0.6, step_height=0.08, look=18.0, spread=spread, toe_out=toe_out)
    out["Turn_R180"] = anim.turn_clip(skel, "Turn_R180", -180.0, 18.0 / FPS, 0.04, 0.40, 0.46, 0.86,
                                      pivot=0.6, step_height=0.08, look=18.0, spread=spread, toe_out=toe_out)

    sneak = ClipBuilder(skel, "Sneak_Idle", 3.6, loop=True, grounded=True)
    set_stance(sneak, "crouch")
    sneak.key(0.0, anim.CROUCH)
    sneak.layer(breathing(period=3.6, amount=0.7))
    sneak.layer(head_look(period=4.2, yaw=12.0, pitch=4.0))
    out["Sneak_Idle"] = sneak

    # A crouched prowl at the game's sneak speed (1.5 m/s; it was 0.95 against a game speed of 2.1).
    out["Sneak_Walk"] = gait_clip(skel, "Sneak_Walk", GaitParams(
        speed=1.5, period=35.0 / FPS, duty=0.62, contact_ahead=0.42, bob_mode="walk", hip_bob=0.008,
        soft_reach=0.04, heel_strike=16.0, land_pitch=16.0, heel_rise=40.0, heel_rise_from=0.6,
        swing_from_pitch=-40.0, step_height=0.07, swing_peak=0.85,
        hip_sway=0.024, hip_yaw=4.0, hip_roll=2.0, lean=10.0, arm_swing=10.0, arm_bend=52.0,
        arm_bend_swing=8.0, crouch=0.185, heel_roll=0.25, stance_width=1.25, head_bob=0.3,
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
                                              shield_up, {"Shoulder.R": (26, -10, 0)}), lead=36.0),
            ArcKey(0.88, 138, "out2", pose_add(_torso(f=42, side=4, turn=15, hips_turn=10, fwd=0.12, up=-0.11), shield_up), lead=40.0),
            ArcKey(1.00, 84, "smooth", guard_of("1h")),
        ],
        hit_arc=(24, 126), cancel_delay=0.12,
        steps=[("L", 0.52, 0.72, (0.34, 0.0), 0.07)],
        extra_events=[(0.20, "telegraph")])

    # -- 2H light 1: diagonal chop with both hands ---------------------------------------
    # The two-handed swings keep the blade pointing out from the arc's middle, so whatever is
    # behind the hands points back at the chest: a greatsword's pommel went 4-9 cm into the torso
    # and a spear's or a staff's butt, 0.9-1.2 m behind the hand, went through it (test_attack_motion
    # now holds every weapon's butt end). The keys where the butt came round at the body lay the blade
    # further back along the arc (`lead`), and the sweep's wind-up holds the hands a little further
    # out, so the butt passes beside the body.
    n2, r2 = plane_diag(28.0)
    out["Attack_2H_Light_1"] = arc_attack(
        skel, "Attack_2H_Light_1", 0.98, guard="2h", centre=(0.10, -0.03, 0.12), normal=n2, ref=r2,
        radius=0.56, lead=18.0, two_handed=True, stance="wide",
        keys=[
            ArcKey(0.00, 86, "smooth", guard_of("2h")),
            ArcKey(0.28, -44, "out2", _torso(f=-8, side=-4, turn=-32, hips_turn=-16, head_turn=16, fwd=-0.04), lead=50.0),
            ArcKey(0.42, -52, "smooth", _torso(f=-10, side=-5, turn=-36, hips_turn=-18, head_turn=18, fwd=-0.05), lead=55.0),
            ArcKey(0.58, 74, "snap", _torso(f=16, side=6, turn=26, hips_turn=18, head_turn=-8, fwd=0.08, up=-0.03)),
            ArcKey(0.70, 116, "out", _torso(f=30, side=10, turn=38, hips_turn=24, head_turn=-12, fwd=0.10, up=-0.08)),
            ArcKey(0.80, 124, "out2", _torso(f=32, side=11, turn=40, hips_turn=25, fwd=0.10, up=-0.09)),
            ArcKey(1.00, 86, "smooth", guard_of("2h")),
        ],
        hit_arc=(16, 116), cancel_delay=0.11,
        steps=[("L", 0.36, 0.60, (0.28, 0.02), 0.055)])

    # -- 2H light 2: horizontal sweep (the wind-up's hands held out: see 2H light 1) --------
    # It only ever follows the chop, handed over at the chop's cancel_ok: it begins in the chop's
    # pose there and comes round onto its own arc by 0.12.
    l1 = out["Attack_2H_Light_1"]
    l1_cancel = next(t for t, ev in l1.events if ev == "cancel_ok")
    out["Attack_2H_Light_2"] = arc_attack(
        skel, "Attack_2H_Light_2", 0.96, guard="2h", centre=(0.12, 0.0, 0.05), normal=UP, ref=FWD,
        radius=0.58, lead=22.0, two_handed=True, stance="wide", entry=l1.sample_pose(l1_cancel),
        keys=[
            ArcKey(0.12, 10, "smooth", guard_of("2h"), lead=45.0),
            ArcKey(0.28, -78, "out2", _torso(f=-2, side=-5, turn=-44, hips_turn=-24, head_turn=22, left=-0.03), radius=1.08, lead=26.0),
            ArcKey(0.42, -88, "smooth", _torso(f=-2, side=-6, turn=-48, hips_turn=-26, head_turn=24, left=-0.03), radius=1.08, lead=30.0),
            ArcKey(0.60, 52, "snap", _torso(f=10, side=5, turn=40, hips_turn=26, head_turn=-14, fwd=0.06)),
            ArcKey(0.72, 92, "out", _torso(f=14, side=8, turn=54, hips_turn=34, head_turn=-18, fwd=0.06, left=0.04)),
            ArcKey(0.82, 100, "out2", _torso(f=14, side=8, turn=56, hips_turn=35, fwd=0.05, left=0.04)),
            ArcKey(1.00, 10, "smooth", guard_of("2h")),
        ],
        hit_arc=(-56, 60), cancel_delay=0.11,
        steps=[("R", 0.34, 0.56, (0.10, -0.14), 0.05), ("L", 0.60, 0.78, (0.10, 0.10), 0.04)])

    # -- 2H heavy: a committed overhead, the slowest and loudest telegraph in the set -----
    # (the blade laid back through the wind-up, the strike and the follow-through: see 2H light 1)
    out["Attack_2H_Heavy"] = arc_attack(
        skel, "Attack_2H_Heavy", 1.92, guard="2h", centre=(0.10, -0.02, 0.14), normal=LEFT, ref=UP,
        radius=0.60, lead=26.0, two_handed=True, stance="wide",
        keys=[
            ArcKey(0.00, 80, "smooth", guard_of("2h")),
            ArcKey(0.20, -30, "out2", _torso(f=-12, turn=-18, hips_turn=-8, head_turn=8, fwd=-0.05, up=-0.03), lead=50.0),
            ArcKey(0.40, -76, "smooth", _torso(f=-22, turn=-24, hips_turn=-10, head_turn=12, fwd=-0.09, up=-0.05), lead=60.0),
            ArcKey(0.54, -84, "smooth", _torso(f=-24, turn=-26, hips_turn=-11, head_turn=13, fwd=-0.10, up=-0.06), lead=60.0),
            ArcKey(0.62, -72, "in2", _torso(f=-20, turn=-22, hips_turn=-9, head_turn=11, fwd=-0.08, up=-0.05), lead=50.0),
            ArcKey(0.76, 92, "snap", _torso(f=30, turn=8, hips_turn=6, fwd=0.10, up=-0.06), lead=40.0),
            ArcKey(0.86, 140, "out", _torso(f=48, turn=12, hips_turn=8, fwd=0.14, up=-0.16), lead=55.0),
            ArcKey(0.93, 146, "out2", _torso(f=50, turn=12, hips_turn=8, fwd=0.14, up=-0.17), lead=60.0),
            ArcKey(1.00, 80, "smooth", guard_of("2h")),
        ],
        hit_arc=(20, 132), cancel_delay=0.14,
        steps=[("L", 0.58, 0.78, (0.38, 0.0), 0.08)],
        extra_events=[(0.18, "telegraph")])

    # -- dagger 1: a short, fast stab ----------------------------------------------------
    dg = guard_of("dagger")
    d1 = ClipBuilder(skel, "Attack_Dagger_1", 0.52, loop=False, grounded=True)
    set_stance(d1, "combat")
    # the chamber: the hand cocked beside the ribs, not behind the back. From behind the back the
    # stab's first frame moved the grip 40 cm, and the engine's blend between the baked frames
    # swung the blade 9 cm through the torso on its way out.
    back = body_point(skel, 0.06, -0.26, 0.02)
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
    coil = body_point(skel, -0.01, -0.31, 0.14)
    lunge = body_point(skel, 0.62, -0.02, -0.02)
    rp.key(0.00, {**g1, "Hand.R@grip": tuple(body_point(skel, 0.22, -0.17, 0.08)), "Hand.R@aim": tuple(FWD)})
    rp.key(0.24 * R, pose_add(g1, _torso(f=-6, turn=-26, hips_turn=-12, head_turn=12, fwd=-0.06, up=-0.04)) |
           {"Hand.R@grip": tuple(coil), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.25))}, "out2")
    rp.key(0.36 * R, pose_add(g1, _torso(f=-6, turn=-28, hips_turn=-13, head_turn=13, fwd=-0.07, up=-0.05)) |
           {"Hand.R@grip": tuple(coil), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.25))}, "smooth")
    rp.key(0.54 * R, pose_add(g1, _torso(f=18, turn=24, hips_turn=16, fwd=0.16, up=-0.10)) |
           {"Hand.R@grip": tuple(lunge), "Hand.R@aim": tuple(rig._unit(FWD - UP * 0.06))}, "snap")
    rp.key(0.66 * R, pose_add(g1, _torso(f=20, turn=26, hips_turn=18, fwd=0.18, up=-0.12)) |
           {"Hand.R@grip": tuple(lunge + FWD * 0.04), "Hand.R@aim": tuple(rig._unit(FWD - UP * 0.06))}, "out")
    rp.key(R, {**g1, "Hand.R@grip": tuple(body_point(skel, 0.22, -0.17, 0.08)), "Hand.R@aim": tuple(FWD)}, "smooth")
    rp.feet.step("L", 0.32 * R, 0.56 * R, skel.J["Foot.L"] + FWD * 0.42 + LEFT * 0.035, height=0.06)
    rp.events_at(hit_start=0.50 * R, hit_end=0.68 * R, cancel_ok=0.80 * R)
    out["Riposte"] = rp

    # -- backstab: a stab driven down and forward into a target's back ------------------------
    # The player closes to 1.2 m of the foe (Player._tick_riposte) and its back is a body's radius
    # nearer. The stab once went to 0.34 m ahead, nearly straight down, and a film showed it
    # striking the ground a metre short of the back it was scored on. It now drives from over the
    # shoulder to 0.6 m ahead, the point forward and down, and a sword's point reaches the back at
    # the small of it.
    bs = ClipBuilder(skel, "Backstab", 1.15, loop=False, grounded=True)
    set_stance(bs, "combat")
    B = 1.15
    high = body_point(skel, 0.10, -0.24, 0.34)
    low = body_point(skel, 0.60, -0.12, -0.10)
    down = tuple(rig._unit(-UP * 0.55 + FWD))
    bs.key(0.00, {**dg, "Hand.R@grip": tuple(body_point(skel, 0.20, -0.20, 0.06)), "Hand.R@aim": tuple(FWD)})
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
    bs.key(B, {**dg, "Hand.R@grip": tuple(body_point(skel, 0.20, -0.20, 0.06)), "Hand.R@aim": tuple(FWD)}, "smooth")
    bs.events_at(hit_start=0.50 * B, hit_end=0.66 * B, cancel_ok=0.90 * B)
    out["Backstab"] = bs
    return out


# --------------------------------------------------------------------------------------
# defence, reactions and deaths
# --------------------------------------------------------------------------------------

def defence_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}
    s = skel.props.height / rig.DEFAULT_HEIGHT

    # shield high and angled across the chest, sword cocked behind it
    block: Pose = {
        "Hips": (2, 0, -16), "Spine": (10, 0, 6), "Chest": (8, 0, 10), "Neck": (-4, 0, -6), "Head": (2, 0, -6),
        "Shoulder.L": (22, 8, 0), "UpperArm.L": (74, -18, 0), "LowerArm.L": (96, 0, -18), "Hand.L": (-8, 0, 0),
        "Shoulder.R": (4, 4, 0), "UpperArm.R": (36, -30, 0), "LowerArm.R": (104, 0, 0), "Hand.R": (-12, 16, 0),
        HIPS_POS: (0.0, 0.0, -0.055),
    }
    bi = ClipBuilder(skel, "Block_Idle", 2.0, loop=True, grounded=True)
    set_stance(bi, "combat")
    bi.key(0.0, block)
    bi.key(1.0, pose_add(block, {"Spine": (2, 0, 0), "Chest": (1, 0, 0), HIPS_POS: (0, 0, -0.008)}), "smooth")
    bi.key(2.0, block, "smooth")
    bi.layer(breathing(period=2.0, amount=1.1))
    out["Block_Idle"] = bi

    bh = ClipBuilder(skel, "Block_Hit", 0.42, loop=False, grounded=True)
    set_stance(bh, "combat")
    bh.key(0.0, block)
    bh.key(0.07, pose_add(block, {"Hips": (-6, 0, 8), "Spine": (-10, 0, -6), "Chest": (-8, 0, -8), "Neck": (8, 0, 4),
                                  "Shoulder.L": (-16, 4, 0), "UpperArm.L": (-14, 6, 0), "LowerArm.L": (14, 0, 0),
                                  HIPS_POS: (-0.075, 0.0, -0.035)}), "snap")
    bh.key(0.20, pose_add(block, {"Spine": (-3, 0, -2), "UpperArm.L": (-5, 2, 0), HIPS_POS: (-0.030, 0, -0.012)}), "out")
    bh.key(0.42, block, "out2")
    bh.feet.step("R", 0.05, 0.20, skel.J["Foot.R"] + BACK * 0.13 * s - LEFT * STANCES["combat"][0] + FWD * STANCES["combat"][2], height=0.025 * s)
    bh.event(0.02, "block_impact")
    bh.event(0.28, "cancel_ok")
    out["Block_Hit"] = bh

    pr = ClipBuilder(skel, "Parry", 0.48, loop=False, grounded=True)
    set_stance(pr, "combat")
    pr.key(0.0, block)
    pr.key(0.10, pose_add(block, {"Chest": (0, 0, -10), "Spine": (0, 0, -6), "Shoulder.L": (-6, 2, 0),
                                  "UpperArm.L": (-8, -6, 0), "LowerArm.L": (-10, 0, 0)}), "in2")
    # the deflect: shield sweeps out and across, body opens
    pr.key(0.20, pose_add(block, {"Hips": (0, 0, 10), "Spine": (-6, -4, 16), "Chest": (-4, -4, 22), "Neck": (6, 0, -10),
                                  "Head": (2, 0, -12), "Shoulder.L": (16, 10, 0), "UpperArm.L": (22, 18, -20),
                                  "LowerArm.L": (-24, 0, 26), "Hand.L": (10, 0, 0), HIPS_POS: (0.02, -0.03, -0.02)}), "snap")
    pr.key(0.32, pose_add(block, {"Spine": (-2, -2, 6), "Chest": (-2, -2, 8), "UpperArm.L": (8, 6, -8),
                                  "LowerArm.L": (-8, 0, 8)}), "out")
    pr.key(0.48, block, "out2")
    pr.event(0.06, "parry_window")
    pr.event(0.20, "parry_hit")
    pr.event(0.30, "cancel_ok")
    out["Parry"] = pr

    # -- reactions ----------------------------------------------------------------------
    hl = ClipBuilder(skel, "Hit_Light", 0.42, loop=False, grounded=True)
    set_stance(hl, "combat")
    g = guard_of("1h")
    hl.key(0.0, g)
    hl.key(0.10, pose_add(g, {"Hips": (-5, 3, 6), "Spine": (-12, 5, -10), "Chest": (-10, 6, -12),
                              "Neck": (10, -4, 8), "Head": (12, -4, 10),
                              "Shoulder.R": (-10, 6, 0), "UpperArm.R": (-14, 8, 0), "UpperArm.L": (-10, 6, 0),
                              HIPS_POS: (-0.055, 0.02, -0.02)}), REACT_EASE)
    hl.key(0.22, pose_add(g, {"Spine": (-4, 2, -3), "Chest": (-3, 2, -4), "Neck": (3, 0, 2),
                              HIPS_POS: (-0.022, 0.008, -0.008)}), "smooth")
    hl.key(0.42, g, "out2")
    hl.event(0.01, "hit_react")
    hl.event(0.26, "cancel_ok")
    out["Hit_Light"] = hl

    hh = ClipBuilder(skel, "Hit_Heavy", 0.78, loop=False, grounded=True)
    set_stance(hh, "combat")
    hh.key(0.0, g)
    hh.key(0.15, pose_add(g, {"Hips": (-12, 6, 14), "Spine": (-24, 10, -20), "Chest": (-20, 12, -24),
                              "Neck": (20, -8, 16), "Head": (22, -8, 18),
                              "Shoulder.R": (-18, 12, 0), "UpperArm.R": (-30, 16, 0), "LowerArm.R": (-20, 0, 0),
                              "Shoulder.L": (-14, 10, 0), "UpperArm.L": (-24, 14, 0),
                              HIPS_POS: (-0.135, 0.05, -0.055)}), REACT_EASE)
    hh.key(0.34, pose_add(g, {"Hips": (-4, 2, 6), "Spine": (-8, 4, -8), "Chest": (-6, 4, -10), "Neck": (8, -2, 6),
                              "Head": (8, -2, 6), "UpperArm.R": (-10, 6, 0), "UpperArm.L": (-8, 4, 0),
                              HIPS_POS: (-0.055, 0.018, -0.030)}), "smooth")
    hh.key(0.56, pose_add(g, {"Spine": (-2, 0, -2), HIPS_POS: (-0.018, 0.004, -0.012)}), "smooth")
    hh.key(0.78, g, "out2")
    hh.feet.step("R", 0.06, 0.26, skel.J["Foot.R"] + BACK * 0.26 * s - LEFT * STANCES["combat"][0] + FWD * STANCES["combat"][2], height=0.045 * s)
    hh.feet.step("L", 0.22, 0.42, skel.J["Foot.L"] + BACK * 0.14 * s + LEFT * STANCES["combat"][0] + FWD * STANCES["combat"][1], height=0.035 * s)
    hh.event(0.01, "hit_react")
    hh.event(0.50, "cancel_ok")
    out["Hit_Heavy"] = hh

    stg = ClipBuilder(skel, "Stagger", 1.05, loop=False, grounded=True)
    set_stance(stg, "combat")
    stg.key(0.0, g)
    stg.key(0.15, pose_add(g, {"Hips": (-14, 8, 16), "Spine": (-28, 12, -22), "Chest": (-22, 14, -26),
                               "Neck": (24, -10, 18), "Head": (26, -10, 20),
                               "UpperArm.R": (-36, 20, 0), "UpperArm.L": (-30, 18, 0),
                               "LowerArm.R": (-16, 0, 0), "LowerArm.L": (-14, 0, 0),
                               HIPS_POS: (-0.155, 0.06, -0.075)}), REACT_EASE)
    stg.key(0.34, pose_add(g, {"Hips": (-6, -4, -8), "Spine": (-14, -6, 12), "Chest": (-10, -8, 14),
                               "Neck": (14, 4, -8), "Head": (14, 4, -10),
                               "UpperArm.R": (-20, 26, 0), "UpperArm.L": (-24, 28, 0),
                               HIPS_POS: (-0.200, -0.045, -0.095)}), "smooth")
    stg.key(0.58, pose_add(g, {"Hips": (-3, 3, 6), "Spine": (-8, 4, -8), "Chest": (-6, 5, -10),
                               "Neck": (8, -2, 6), "Head": (8, -2, 6),
                               "UpperArm.R": (-12, 16, 0), "UpperArm.L": (-14, 18, 0),
                               HIPS_POS: (-0.150, 0.030, -0.070)}), "smooth")
    stg.key(0.80, pose_add(g, {"Spine": (-3, 0, -3), "Chest": (-2, 0, -4), HIPS_POS: (-0.070, 0.006, -0.030)}), "out")
    stg.key(1.05, g, "out2")
    for side, t0, t1, d, lat in (("R", 0.05, 0.26, 0.30, 0.0), ("L", 0.24, 0.46, 0.34, -0.06), ("R", 0.46, 0.68, 0.20, 0.04)):
        base = skel.J[f"Foot.{side}"].copy()
        base[0] += (STANCES["combat"][0] if side == "L" else -STANCES["combat"][0])
        base[1] -= (STANCES["combat"][1] if side == "L" else STANCES["combat"][2])
        stg.feet.step(side, t0 * 1.05, t1 * 1.05, base + BACK * d * s + LEFT * lat * s, height=0.05 * s)
        stg.event(t1 * 1.05, "footstep_l" if side == "L" else "footstep_r")
    stg.event(0.01, "hit_react")
    stg.event(0.86, "cancel_ok")
    out["Stagger"] = stg

    # -- the same, taken from behind and from either side -------------------------------------
    # Hit_Light and Stagger above are a blow from the front; these are the blow from the other
    # three ways (the game picks by where the blow came from, Impact.reaction). _B is struck from
    # behind (thrown forward), _L from the left (thrown to the right), _R from the right.
    for way, push in (("B", (1.0, 0.0)), ("L", (0.0, -1.0)), ("R", (0.0, 1.0))):
        out["Hit_Light_" + way] = reaction_clip(skel, "Hit_Light_" + way, 0.42, g, push, stagger=False)
        out["Stagger_" + way] = reaction_clip(skel, "Stagger_" + way, 1.05, g, push, stagger=True)

    kd = fall_clip(skel, "Knockdown", 1.15, direction="B", start=g, settle=True)
    kd.event(0.02, "hit_react")
    out["Knockdown"] = kd

    # -- get up ---------------------------------------------------------------------------
    gu = ClipBuilder(skel, "Get_Up", 1.45, loop=False, grounded=False)
    hip_z = float(skel.J["Hips"][2])
    down: Pose = {"Hips": (-84, 0, 0), "Spine": (-4, 0, 0), "Chest": (-4, 0, 0), "Neck": (4, 0, 0), "Head": (4, 0, 0),
                  "UpperArm.L": (10, -20, 0), "UpperArm.R": (30, 20, 0), "LowerArm.L": (30, 0, 0), "LowerArm.R": (60, 0, 0),
                  "UpperLeg.L": (12, 6, 0), "UpperLeg.R": (6, 4, 0), "LowerLeg.L": (28, 0, 0), "LowerLeg.R": (10, 0, 0),
                  "Foot.L": (-30, 0, 0), "Foot.R": (-40, 0, 0), HIPS_POS: (-0.30, 0, -(hip_z - 0.16 * s))}
    roll_up: Pose = {"Hips": (-56, -24, 14), "Spine": (10, 10, 10), "Chest": (8, 8, 12), "Neck": (6, 0, -8), "Head": (8, 0, -10),
                     "UpperArm.L": (52, -6, 0), "UpperArm.R": (78, 18, 0), "LowerArm.L": (70, 0, 0), "LowerArm.R": (94, 0, 0),
                     "UpperLeg.L": (56, 14, 0), "UpperLeg.R": (30, 8, 0), "LowerLeg.L": (86, 0, 0), "LowerLeg.R": (46, 0, 0),
                     "Foot.L": (-26, 0, 0), "Foot.R": (-34, 0, 0), HIPS_POS: (-0.18, -0.06, -(hip_z - 0.26 * s))}
    kneel: Pose = {"Hips": (16, 0, 10), "Spine": (26, 0, 6), "Chest": (16, 0, 8), "Neck": (-14, 0, -8), "Head": (-8, 0, -8),
                   "UpperArm.L": (44, -24, 0), "UpperArm.R": (40, -26, 0), "LowerArm.L": (56, 0, 0), "LowerArm.R": (52, 0, 0),
                   "UpperLeg.L": (82, 10, 0), "UpperLeg.R": (46, 8, 0), "LowerLeg.L": (96, 0, 0), "LowerLeg.R": (118, 0, 0),
                   "Foot.L": (-16, 0, 0), "Foot.R": (-44, 0, 0), HIPS_POS: (0.04, 0.0, -(hip_z - 0.46 * s))}
    crouch: Pose = {"Spine": (30, 0, 4), "Chest": (12, 0, 4), "Neck": (-20, 0, -4), "Head": (-8, 0, -4),
                    "UpperArm.L": (26, -34, 0), "UpperArm.R": (24, -34, 0), "LowerArm.L": (40, 0, 0), "LowerArm.R": (38, 0, 0),
                    "UpperLeg.L": (74, 8, 0), "UpperLeg.R": (62, 8, 0), "LowerLeg.L": (98, 0, 0), "LowerLeg.R": (92, 0, 0),
                    "Foot.L": (-26, 0, 0), "Foot.R": (-22, 0, 0), HIPS_POS: (0.05, 0.0, -0.30 * s)}
    gu.key(0.00, down, "linear")
    gu.key(0.22, roll_up, "smooth")
    gu.key(0.52, kneel, "out")
    gu.key(0.82, crouch, "smooth")
    gu.key(1.10, pose_add(STAND, {"Spine": (8, 0, 0), "Neck": (-4, 0, 0), HIPS_POS: (0.01, 0, -0.045)}), "out")
    gu.key(1.45, STAND, "out2")
    gu.event(0.55, "footstep_r")
    gu.event(0.86, "footstep_l")
    gu.event(1.15, "cancel_ok")
    out["Get_Up"] = gu

    da = fall_clip(skel, "Death_A", 2.30, direction="B", start=g, settle=True)
    da.event(0.02, "death_start")
    out["Death_A"] = da
    db = fall_clip(skel, "Death_B", 2.10, direction="K", start=g, settle=True)
    db.event(0.02, "death_start")
    out["Death_B"] = db
    return out


# --------------------------------------------------------------------------------------
# ranged and magic
# --------------------------------------------------------------------------------------

def ranged_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}
    s = skel.props.height / rig.DEFAULT_HEIGHT

    bow_hand = body_point(skel, 0.50, 0.16, 0.10)          # left hand holds the bow out front
    bow_aim = tuple(rig._unit(UP))                         # bow limbs run vertically
    nock_home = body_point(skel, 0.44, 0.10, 0.10)
    draw_anchor = body_point(skel, 0.04, -0.13, 0.26)      # right hand at the cheek
    archer: Pose = {"Hips": (0, 0, -34), "Spine": (2, 0, 16), "Chest": (2, 0, 22), "Neck": (0, 0, -26),
                    "Head": (0, 0, -30), "Shoulder.L": (10, 4, 0), "Shoulder.R": (0, 8, 0)}

    def archer_clip(name: str, length: float, loop: bool = False) -> ClipBuilder:
        cb = ClipBuilder(skel, name, length, loop=loop, grounded=True)
        stance_feet(cb.feet, spread=0.04, forward_l=0.06, forward_r=-0.16, yaw_l=40.0, yaw_r=-52.0)
        return cb

    bow_low = body_point(skel, 0.26, 0.20, -0.30)       # bow held down at the side
    nock_low = body_point(skel, 0.20, -0.02, -0.26)
    bd = archer_clip("Bow_Draw", 0.86)
    # Key the hand targets from the first frame: an IK channel has no rest pose, so if it
    # first appears mid-clip the arm is already there and the raise never reads.
    bd.key(0.00, pose_add(STAND, {"Hips": (0, 0, -14), "Chest": (0, 0, 8), "Neck": (0, 0, -12), "Head": (0, 0, -12)}) |
           {"Hand.L@grip": tuple(bow_low), "Hand.L@aim": tuple(rig._unit(UP * 0.4 + FWD * 0.2)),
            "Hand.R@grip": tuple(nock_low), "Hand.R@aim": tuple(FWD)})
    bd.key(0.40, pose_add(archer, {}) | {"Hand.L@grip": tuple(bow_hand), "Hand.L@aim": bow_aim,
                                         "Hand.R@grip": tuple(nock_home), "Hand.R@aim": tuple(FWD)}, "out2")
    bd.key(0.86, pose_add(archer, {"Shoulder.R": (-10, 12, 0), "Chest": (0, 0, 26)}) |
           {"Hand.L@grip": tuple(bow_hand), "Hand.L@aim": bow_aim,
            "Hand.R@grip": tuple(draw_anchor), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.1))}, "in2")
    bd.event(0.38, "bow_raised")
    bd.event(0.82, "bow_drawn")
    out["Bow_Draw"] = bd

    ba = archer_clip("Bow_Aim", 2.2, loop=True)
    drawn = pose_add(archer, {"Shoulder.R": (-10, 12, 0), "Chest": (0, 0, 26)}) | \
        {"Hand.L@grip": tuple(bow_hand), "Hand.L@aim": bow_aim,
         "Hand.R@grip": tuple(draw_anchor), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.1))}
    ba.key(0.0, drawn)
    ba.key(1.1, dict(drawn, **{"Hand.L@grip": tuple(bow_hand + UP * 0.012 * s + LEFT * 0.008 * s),
                               "Spine": (3, 0, 16), "Neck": (-1, 0, -26)}), "smooth")
    ba.key(2.2, drawn, "smooth")
    ba.layer(breathing(period=2.2, amount=0.8))
    out["Bow_Aim"] = ba

    br = archer_clip("Bow_Release", 0.62)
    br.key(0.0, drawn)
    br.key(0.07, dict(drawn, **{"Hand.R@grip": tuple(draw_anchor + BACK * 0.14 * s + LEFT * 0.05 * s),
                                "Hand.R@aim": tuple(BACK), "Shoulder.R": (-16, 16, 0), "Chest": (0, 0, 32),
                                "Head": (0, 0, -30)}), "snap")
    br.key(0.26, dict(drawn, **{"Hand.R@grip": tuple(draw_anchor + BACK * 0.10 * s + LEFT * 0.03 * s),
                                "Hand.R@aim": tuple(BACK), "Shoulder.R": (-8, 10, 0)}), "out")
    br.key(0.62, pose_add(STAND, {"Hips": (0, 0, -20), "Chest": (0, 0, 12), "Neck": (0, 0, -16), "Head": (0, 0, -16),
                                  "UpperArm.L": (30, -30, 0), "LowerArm.L": (40, 0, 0),
                                  "UpperArm.R": (18, -36, 0), "LowerArm.R": (34, 0, 0)}), "smooth")
    br.event(0.03, "release")
    br.event(0.34, "cancel_ok")
    out["Bow_Release"] = br

    # -- magic ("Saying"): gather at the chest, then push the shape out ------------------
    cast_home = body_point(skel, 0.24, -0.06, 0.02)
    cast_out = body_point(skel, 0.52, -0.04, 0.10)
    cast_gather = body_point(skel, 0.16, -0.10, -0.02)

    cq = ClipBuilder(skel, "Cast_Quick", 0.68, loop=False, grounded=True)
    set_stance(cq, "combat")
    cq.key(0.00, pose_add(STAND, {"Spine": (2, 0, -6), "Chest": (2, 0, -8)}) |
           {"Hand.R@grip": tuple(cast_home), "Hand.R@aim": tuple(FWD)})
    cq.key(0.26, pose_add(STAND, {"Spine": (8, 0, -18), "Chest": (6, 0, -22), "Neck": (-4, 0, 12), "Head": (-2, 0, 14),
                                  "Shoulder.R": (-8, 8, 0), HIPS_POS: (-0.04, 0, -0.03)}) |
           {"Hand.R@grip": tuple(cast_gather), "Hand.R@aim": tuple(rig._unit(UP + FWD * 0.2))}, "out2")
    cq.key(0.36, pose_add(STAND, {"Spine": (9, 0, -20), "Chest": (7, 0, -24), "Neck": (-4, 0, 13), "Head": (-2, 0, 15),
                                  "Shoulder.R": (-9, 9, 0), HIPS_POS: (-0.045, 0, -0.035)}) |
           {"Hand.R@grip": tuple(cast_gather), "Hand.R@aim": tuple(rig._unit(UP + FWD * 0.2))}, "smooth")
    cq.key(0.50, pose_add(STAND, {"Spine": (-2, 0, 14), "Chest": (-2, 0, 18), "Neck": (2, 0, -8), "Shoulder.R": (14, -2, 0),
                                  HIPS_POS: (0.06, 0, 0.0)}) |
           {"Hand.R@grip": tuple(cast_out), "Hand.R@aim": tuple(FWD)}, "snap")
    cq.key(0.68, pose_add(STAND, {"Spine": (2, 0, -4), "Chest": (2, 0, -6)}) |
           {"Hand.R@grip": tuple(cast_home), "Hand.R@aim": tuple(FWD)}, "out")
    cq.events_at(hit_start=0.46, hit_end=0.54, cancel_ok=0.58)
    cq.event(0.44, "cast_release")
    out["Cast_Quick"] = cq

    cl_ = ClipBuilder(skel, "Cast_Long", 1.55, loop=False, grounded=True)
    set_stance(cl_, "combat")
    both_up = {"Shoulder.L": (10, 10, 0), "Shoulder.R": (10, 10, 0)}
    cl_.key(0.00, pose_add(STAND, both_up) |
            {"Hand.R@grip": tuple(cast_home), "Hand.R@aim": tuple(FWD),
             "Hand.L@grip": tuple(body_point(skel, 0.24, 0.14, 0.02)), "Hand.L@aim": tuple(FWD)})
    cl_.key(0.45, pose_add(STAND, both_up, {"Spine": (-8, 0, 0), "Chest": (-6, 0, 0), "Neck": (10, 0, 0), "Head": (10, 0, 0),
                                            HIPS_POS: (-0.02, 0, 0.01)}) |
            {"Hand.R@grip": tuple(body_point(skel, 0.20, -0.22, 0.34)), "Hand.R@aim": tuple(UP),
             "Hand.L@grip": tuple(body_point(skel, 0.20, 0.22, 0.34)), "Hand.L@aim": tuple(UP)}, "out2")
    cl_.key(0.85, pose_add(STAND, both_up, {"Spine": (-10, 0, 0), "Chest": (-8, 0, 0), "Neck": (12, 0, 0), "Head": (12, 0, 0),
                                            HIPS_POS: (-0.02, 0, 0.012)}) |
            {"Hand.R@grip": tuple(body_point(skel, 0.22, -0.24, 0.38)), "Hand.R@aim": tuple(UP),
             "Hand.L@grip": tuple(body_point(skel, 0.22, 0.24, 0.38)), "Hand.L@aim": tuple(UP)}, "smooth")
    cl_.key(1.10, pose_add(STAND, {"Spine": (16, 0, 0), "Chest": (10, 0, 0), "Neck": (-12, 0, 0), "Head": (-8, 0, 0),
                                   HIPS_POS: (0.08, 0, -0.04)}) |
            {"Hand.R@grip": tuple(body_point(skel, 0.54, -0.14, 0.06)), "Hand.R@aim": tuple(FWD),
             "Hand.L@grip": tuple(body_point(skel, 0.54, 0.14, 0.06)), "Hand.L@aim": tuple(FWD)}, "snap")
    cl_.key(1.55, pose_add(STAND, both_up) |
            {"Hand.R@grip": tuple(cast_home), "Hand.R@aim": tuple(FWD),
             "Hand.L@grip": tuple(body_point(skel, 0.24, 0.14, 0.02)), "Hand.L@aim": tuple(FWD)}, "out")
    cl_.events_at(hit_start=1.06, hit_end=1.18, cancel_ok=1.26)
    cl_.event(0.40, "cast_charge")
    cl_.event(1.04, "cast_release")
    out["Cast_Long"] = cl_

    cloop = ClipBuilder(skel, "Cast_Loop", 1.8, loop=True, grounded=True)
    set_stance(cloop, "combat")
    hold = pose_add(STAND, {"Spine": (4, 0, -10), "Chest": (4, 0, -12), "Neck": (-2, 0, 6), "Head": (-2, 0, 6),
                            "Shoulder.R": (6, 8, 0), "Shoulder.L": (6, 6, 0), HIPS_POS: (0.0, 0, -0.02)})
    hold_ik = {"Hand.R@grip": tuple(body_point(skel, 0.40, -0.10, 0.12)), "Hand.R@aim": tuple(FWD),
               "Hand.L@grip": tuple(body_point(skel, 0.28, 0.16, 0.04)), "Hand.L@aim": tuple(rig._unit(FWD + UP * 0.3))}
    cloop.key(0.0, hold | hold_ik)
    cloop.key(0.9, pose_add(hold, {"Spine": (2, 0, -8), "Chest": (2, 0, -10)}) |
              dict(hold_ik, **{"Hand.R@grip": tuple(body_point(skel, 0.43, -0.12, 0.15))}), "smooth")
    cloop.key(1.8, hold | hold_ik, "smooth")
    cloop.layer(breathing(period=1.8, amount=0.9))
    out["Cast_Loop"] = cloop

    th = ClipBuilder(skel, "Throw", 0.76, loop=False, grounded=True)
    set_stance(th, "combat")
    th.key(0.00, pose_add(STAND, {}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.20, -0.14, 0.02)), "Hand.R@aim": tuple(FWD)})
    th.key(0.26, pose_add(STAND, {"Spine": (-4, 0, -18), "Chest": (-4, 0, -24), "Neck": (6, 0, 14), "Head": (4, 0, 16),
                                  "Shoulder.R": (-12, 12, 0), HIPS_POS: (-0.06, 0, 0.0)}) |
           {"Hand.R@grip": tuple(body_point(skel, -0.14, -0.22, 0.30)), "Hand.R@aim": tuple(rig._unit(BACK + UP * 0.4))}, "out2")
    th.key(0.38, pose_add(STAND, {"Spine": (-5, 0, -20), "Chest": (-5, 0, -26), "Neck": (7, 0, 15), "Head": (5, 0, 17),
                                  "Shoulder.R": (-13, 13, 0), HIPS_POS: (-0.065, 0, 0.0)}) |
           {"Hand.R@grip": tuple(body_point(skel, -0.16, -0.23, 0.32)), "Hand.R@aim": tuple(rig._unit(BACK + UP * 0.4))}, "smooth")
    th.key(0.52, pose_add(STAND, {"Spine": (14, 0, 20), "Chest": (10, 0, 26), "Neck": (-8, 0, -10), "Head": (-6, 0, -12),
                                  "Shoulder.R": (18, -4, 0), HIPS_POS: (0.09, 0, -0.02)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.50, -0.06, 0.26)), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.25))}, "snap")
    th.key(0.64, pose_add(STAND, {"Spine": (18, 0, 24), "Chest": (12, 0, 30), "Neck": (-10, 0, -12), "Head": (-8, 0, -14),
                                  "Shoulder.R": (20, -8, 0), HIPS_POS: (0.10, 0, -0.04)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.52, 0.04, 0.02)), "Hand.R@aim": tuple(rig._unit(FWD - UP * 0.2))}, "out")
    th.key(0.76, pose_add(STAND, {}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.20, -0.14, 0.02)), "Hand.R@aim": tuple(FWD)}, "out2")
    th.feet.step("L", 0.30, 0.50, skel.J["Foot.L"] + FWD * 0.26 * s + LEFT * STANCES["combat"][0] - FWD * STANCES["combat"][1], height=0.05 * s)
    th.events_at(hit_start=0.48, hit_end=0.56, cancel_ok=0.62)
    th.event(0.50, "throw_release")
    out["Throw"] = th
    return out


# --------------------------------------------------------------------------------------
# life: work, talk, gestures, rest
# --------------------------------------------------------------------------------------

def _rel(skel: Skeleton) -> Pose:
    """Relaxed standing pose used as the base of most life clips."""
    return dict(STAND)


def work_cycle(skel: Skeleton, name: str, length: float, *, hand_path: Sequence[Tuple[float, tuple, str]],
               torso: Sequence[Tuple[float, Pose]] = (), aim: Optional[Sequence[Tuple[float, tuple]]] = None,
               two_handed: bool = False, grip_sep: float = 0.16, events: Sequence[Tuple[float, str]] = (),
               loop: bool = True, stance: str = "idle", base: Optional[Pose] = None,
               off_hand: Optional[Sequence[Tuple[float, tuple]]] = None) -> ClipBuilder:
    """A looping manual-labour cycle driven by where the working hand goes.

    `hand_path` is [(t_frac, (fwd, left, up), ease)]; `torso` adds axial poses at times;
    `aim` gives the tool direction (defaults to pointing away from the chest)."""
    cb = ClipBuilder(skel, name, length, loop=loop, grounded=True)
    set_stance(cb, stance)
    b = base if base is not None else _rel(skel)
    aim_at = {t: a for t, a in (aim or ())}
    torso_at = {t: p for t, p in torso}
    off_at = {t: a for t, a in (off_hand or ())}
    for t, off, ez in hand_path:
        # Anchored to the HIPS, not the chest.  An anvil, a quern and a loom stand at fixed
        # heights, so where a working hand goes has to depend only on how far the body is
        # off the ground.  Anchored to the chest, every contact drifted the moment the head
        # or the neck changed length -- which is exactly what happened this pass.
        p = body_point(skel, *off, origin="Hips")
        a = np.asarray(aim_at.get(t, tuple(rig._unit(p - skel.J["Chest"]))), float)
        pose: Pose = dict(b)
        pose.update(torso_at.get(t, {}))
        pose["Hand.R@grip"] = tuple(p)
        pose["Hand.R@aim"] = tuple(rig._unit(a))
        if two_handed:
            pose["Hand.L@grip"] = tuple(two_hand_grip(p, a, grip_sep * skel.props.height / rig.DEFAULT_HEIGHT))
            pose["Hand.L@aim"] = tuple(rig._unit(a))
        elif t in off_at:
            pose["Hand.L@grip"] = tuple(body_point(skel, *off_at[t]))
            pose["Hand.L@aim"] = tuple(FWD)
        cb.key(t * length, pose, ez)
    for t, e in events:
        cb.event(t * length, e)
    return cb


def life_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    out: Dict[str, ClipBuilder] = {}
    s = skel.props.height / rig.DEFAULT_HEIGHT
    hip_z = float(skel.J["Hips"][2])
    rel = _rel(skel)

    # -- interact / pick up ---------------------------------------------------------------
    it = ClipBuilder(skel, "Interact", 0.92, loop=False, grounded=True)
    set_stance(it, "idle")
    it.key(0.00, rel)
    it.key(0.30, pose_add(rel, {"Spine": (12, 0, -10), "Chest": (6, 0, -12), "Neck": (-8, 0, 6), "Head": (-6, 0, 8),
                                "Shoulder.R": (12, 4, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.44, -0.10, -0.06)), "Hand.R@aim": tuple(FWD)}, "out2")
    it.key(0.50, pose_add(rel, {"Spine": (14, 0, -12), "Chest": (8, 0, -14), "Neck": (-9, 0, 7), "Head": (-7, 0, 9),
                                "Shoulder.R": (14, 4, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.50, -0.09, -0.05)), "Hand.R@aim": tuple(FWD)}, "smooth")
    it.key(0.66, pose_add(rel, {"Spine": (12, 0, -10), "Chest": (6, 0, -12), "Shoulder.R": (10, 4, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.42, -0.10, -0.04)), "Hand.R@aim": tuple(FWD)}, "out")
    it.key(0.92, rel, "smooth")
    it.event(0.50, "interact")
    out["Interact"] = it

    pu = ClipBuilder(skel, "Pick_Up", 1.20, loop=False, grounded=True)
    set_stance(pu, "idle")
    crouch_down = {"Spine": (40, 0, -8), "Chest": (16, 0, -10), "Neck": (-26, 0, 6), "Head": (-14, 0, 8),
                   "UpperLeg.L": (0, 6, 0), "UpperLeg.R": (0, 6, 0), HIPS_POS: (0.06, 0.0, -0.34)}
    pu.key(0.00, rel)
    pu.key(0.40, pose_add(rel, crouch_down) |
           {"Hand.R@grip": tuple(body_point(skel, 0.30, -0.10, -0.62)), "Hand.R@aim": tuple(-UP)}, "out2")
    pu.key(0.56, pose_add(rel, crouch_down) |
           {"Hand.R@grip": tuple(body_point(skel, 0.31, -0.10, -0.63)), "Hand.R@aim": tuple(-UP)}, "smooth")
    pu.key(0.90, pose_add(rel, {"Spine": (8, 0, -6), "Chest": (4, 0, -6), "Shoulder.R": (6, 2, 0), HIPS_POS: (0.01, 0, -0.04)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.30, -0.12, -0.22)), "Hand.R@aim": tuple(rig._unit(FWD - UP))}, "out")
    pu.key(1.20, rel, "smooth")
    pu.event(0.52, "pick_up")
    out["Pick_Up"] = pu

    # -- sitting ---------------------------------------------------------------------------
    seat_drop = 0.42 * s
    sit_pose: Pose = {"Hips": (-8, 0, 0), "Spine": (10, 0, 0), "Chest": (4, 0, 0), "Neck": (-6, 0, 0), "Head": (-2, 0, 0),
                      "UpperLeg.L": (86, 10, 0), "UpperLeg.R": (86, 10, 0), "LowerLeg.L": (84, 0, 0), "LowerLeg.R": (84, 0, 0),
                      "Foot.L": (4, 0, 0), "Foot.R": (4, 0, 0),
                      "UpperArm.L": (18, -34, 0), "UpperArm.R": (18, -34, 0), "LowerArm.L": (54, 0, 0), "LowerArm.R": (54, 0, 0),
                      HIPS_POS: (-0.14, 0.0, -seat_drop)}
    sd = ClipBuilder(skel, "Sit_Down", 1.30, loop=False, grounded=False)
    sd.key(0.00, rel)
    sd.key(0.34, pose_add(rel, {"Spine": (12, 0, 0), "Neck": (-8, 0, 0), "UpperLeg.L": (18, 6, 0), "UpperLeg.R": (18, 6, 0),
                                "LowerLeg.L": (22, 0, 0), "LowerLeg.R": (22, 0, 0),
                                "UpperArm.L": (14, -32, 0), "UpperArm.R": (14, -32, 0),
                                HIPS_POS: (-0.06, 0, -0.10)}), "out2")
    sd.key(0.86, pose_add(sit_pose, {"Spine": (16, 0, 0)}), "in2")
    sd.key(1.05, pose_add(sit_pose, {"Spine": (6, 0, 0)}), "out")
    sd.key(1.30, sit_pose, "out2")
    sd.event(0.84, "sit")
    out["Sit_Down"] = sd

    si = ClipBuilder(skel, "Sit_Idle", 4.4, loop=True, grounded=False)
    si.key(0.0, sit_pose)
    si.key(2.2, pose_add(sit_pose, {"Spine": (3, 2, -4), "Chest": (2, 2, -5), "Head": (2, 0, 8),
                                    "UpperArm.R": (4, 2, 0), "LowerArm.R": (-6, 0, 0)}), "smooth")
    si.key(4.4, sit_pose, "smooth")
    si.layer(breathing(period=4.4, amount=0.9))
    si.layer(head_look(period=5.6, yaw=10.0, pitch=3.0))
    out["Sit_Idle"] = si

    su = ClipBuilder(skel, "Stand_Up", 1.25, loop=False, grounded=False)
    su.key(0.00, sit_pose)
    su.key(0.26, pose_add(sit_pose, {"Spine": (26, 0, 0), "Chest": (10, 0, 0), "Neck": (-16, 0, 0),
                                     "UpperArm.L": (30, -30, 0), "UpperArm.R": (30, -30, 0)}), "out2")
    su.key(0.72, pose_add(rel, {"Spine": (22, 0, 0), "Chest": (8, 0, 0), "Neck": (-14, 0, 0),
                                "UpperLeg.L": (28, 6, 0), "UpperLeg.R": (28, 6, 0),
                                "LowerLeg.L": (34, 0, 0), "LowerLeg.R": (34, 0, 0),
                                "UpperArm.L": (16, -32, 0), "UpperArm.R": (16, -32, 0),
                                HIPS_POS: (0.02, 0, -0.13)}), "in2")
    su.key(1.00, pose_add(rel, {"Spine": (6, 0, 0), HIPS_POS: (0.0, 0, -0.03)}), "out")
    su.key(1.25, rel, "out2")
    su.event(0.62, "stand")
    su.event(0.70, "footstep_l")
    out["Stand_Up"] = su

    sl = ClipBuilder(skel, "Sleep_Idle", 5.0, loop=True, grounded=False)
    lie: Pose = {"Hips": (-88, 0, 6), "Spine": (4, 0, 0), "Chest": (2, 0, 0), "Neck": (6, 0, 14), "Head": (4, 0, 16),
                 "UpperArm.L": (26, 22, 0), "UpperArm.R": (14, -14, 0), "LowerArm.L": (62, 0, 0), "LowerArm.R": (36, 0, 0),
                 "UpperLeg.L": (16, 10, 0), "UpperLeg.R": (6, 6, 0), "LowerLeg.L": (30, 0, 0), "LowerLeg.R": (12, 0, 0),
                 "Foot.L": (-26, 0, 0), "Foot.R": (-30, 0, 0), HIPS_POS: (-0.28, 0.0, -(hip_z - 0.17 * s))}
    sl.key(0.0, lie)
    sl.key(2.5, pose_add(lie, {"Chest": (-3, 0, 0), "Spine": (-2, 0, 0), "Neck": (-2, 0, 0),
                               "UpperArm.R": (3, -2, 0)}), "smooth")
    sl.key(5.0, lie, "smooth")
    out["Sleep_Idle"] = sl

    # -- work ------------------------------------------------------------------------------
    out["Work_Hammer"] = work_cycle(
        skel, "Work_Hammer", 32.0 / FPS,
        hand_path=[(0.00, (0.34, -0.14, 0.2876), "smooth"), (0.34, (0.16, -0.20, 0.6076), "out2"),
                   (0.46, (0.14, -0.21, 0.6276), "smooth"), (0.62, (0.36, -0.12, 0.1676), "snap"),
                   (0.72, (0.38, -0.11, 0.1376), "out"), (1.00, (0.34, -0.14, 0.2876), "smooth")],
        aim=[(0.00, tuple(rig._unit(FWD - UP * 0.4))), (0.34, tuple(rig._unit(UP + BACK * 0.3))),
             (0.46, tuple(rig._unit(UP + BACK * 0.35))), (0.62, tuple(rig._unit(FWD * 0.3 - UP))),
             (0.72, tuple(-UP)), (1.00, tuple(rig._unit(FWD - UP * 0.4)))],
        torso=[(0.00, {"Spine": (16, 0, -6), "Chest": (8, 0, -8), "Neck": (-12, 0, 4)}),
               (0.34, {"Spine": (10, 0, -14), "Chest": (6, 0, -16), "Neck": (-8, 0, 10), "Head": (-6, 0, 8)}),
               (0.46, {"Spine": (9, 0, -15), "Chest": (5, 0, -17), "Neck": (-7, 0, 11), "Head": (-5, 0, 9)}),
               (0.62, {"Spine": (24, 0, -4), "Chest": (12, 0, -5), "Neck": (-18, 0, 2), "Head": (-10, 0, 2),
                       HIPS_POS: (0.02, 0, -0.03)}),
               (0.72, {"Spine": (26, 0, -3), "Chest": (13, 0, -4), "Neck": (-19, 0, 2), "Head": (-11, 0, 2),
                       HIPS_POS: (0.02, 0, -0.035)}),
               (1.00, {"Spine": (16, 0, -6), "Chest": (8, 0, -8), "Neck": (-12, 0, 4)})],
        events=[(0.60, "work_hit"), (0.60, "hit_start"), (0.66, "hit_end")])

    out["Work_Chop"] = work_cycle(
        skel, "Work_Chop", 41.0 / FPS, two_handed=True, grip_sep=0.17, stance="wide",
        hand_path=[(0.00, (0.30, -0.06, 0.3276), "smooth"), (0.36, (0.02, -0.16, 0.7076), "out2"),
                   (0.50, (0.00, -0.17, 0.7276), "smooth"), (0.68, (0.34, -0.04, -0.0724), "snap"),
                   (0.78, (0.36, -0.03, -0.1124), "out"), (1.00, (0.30, -0.06, 0.3276), "smooth")],
        aim=[(0.00, tuple(rig._unit(FWD - UP * 0.2))), (0.36, tuple(rig._unit(UP + BACK * 0.45))),
             (0.50, tuple(rig._unit(UP + BACK * 0.5))), (0.68, tuple(rig._unit(FWD * 0.25 - UP))),
             (0.78, tuple(-UP)), (1.00, tuple(rig._unit(FWD - UP * 0.2)))],
        torso=[(0.00, {"Spine": (12, 0, 0), "Chest": (6, 0, 0), "Neck": (-10, 0, 0)}),
               (0.36, {"Spine": (-8, 0, -10), "Chest": (-6, 0, -12), "Neck": (10, 0, 8), "Head": (8, 0, 6),
                       HIPS_POS: (-0.03, 0, 0.01)}),
               (0.50, {"Spine": (-9, 0, -11), "Chest": (-7, 0, -13), "Neck": (11, 0, 9), "Head": (9, 0, 7),
                       HIPS_POS: (-0.035, 0, 0.012)}),
               (0.68, {"Spine": (36, 0, 4), "Chest": (16, 0, 5), "Neck": (-26, 0, -2), "Head": (-14, 0, -2),
                       HIPS_POS: (0.05, 0, -0.10)}),
               (0.78, {"Spine": (40, 0, 5), "Chest": (18, 0, 6), "Neck": (-28, 0, -2), "Head": (-15, 0, -2),
                       HIPS_POS: (0.05, 0, -0.12)}),
               (1.00, {"Spine": (12, 0, 0), "Chest": (6, 0, 0), "Neck": (-10, 0, 0)})],
        events=[(0.66, "work_hit"), (0.66, "hit_start"), (0.72, "hit_end")])

    out["Work_Stir"] = work_cycle(
        skel, "Work_Stir", 2.0, stance="idle",
        # The stir circle used to sit 9 cm beyond the arm's reach, so the IK locked the
        # elbow straight for the whole loop and the hand ended up wherever the arm stopped
        # rather than on the target -- which is why this was the one work clip that still
        # drifted when the shoulder moved.  It now runs at about 88% extension.
        hand_path=[(0.00, (0.28, -0.11, 0.2600), "linear"), (0.25, (0.33, -0.02, 0.2600), "linear"),
                   (0.50, (0.28, 0.07, 0.2600), "linear"), (0.75, (0.23, -0.02, 0.2600), "linear"),
                   (1.00, (0.28, -0.11, 0.2600), "linear")],
        aim=[(t, tuple(rig._unit(-UP + FWD * 0.25))) for t in (0.0, 0.25, 0.5, 0.75, 1.0)],
        torso=[(0.00, {"Spine": (16, 0, -6), "Chest": (8, 0, -6), "Neck": (-12, 0, 4), "Head": (-8, 0, 4)}),
               (0.50, {"Spine": (18, 0, 2), "Chest": (9, 0, 2), "Neck": (-13, 0, -2), "Head": (-9, 0, -2)}),
               (1.00, {"Spine": (16, 0, -6), "Chest": (8, 0, -6), "Neck": (-12, 0, 4), "Head": (-8, 0, 4)})],
        events=[(0.02, "work_stir")])

    out["Work_Dig"] = work_cycle(
        skel, "Work_Dig", 56.0 / FPS, two_handed=True, grip_sep=0.22, stance="wide",
        hand_path=[(0.00, (0.32, -0.02, 0.0676), "smooth"), (0.20, (0.30, -0.06, 0.3076), "out2"),
                   (0.36, (0.34, -0.02, -0.1724), "snap"), (0.46, (0.34, -0.02, -0.2124), "out"),
                   (0.66, (0.24, 0.10, 0.0876), "smooth"), (0.82, (0.14, 0.24, 0.2876), "out"),
                   (1.00, (0.32, -0.02, 0.0676), "smooth")],
        aim=[(0.00, tuple(rig._unit(FWD * 0.4 - UP))), (0.20, tuple(rig._unit(FWD * 0.3 - UP))),
             (0.36, tuple(rig._unit(FWD * 0.2 - UP))), (0.46, tuple(rig._unit(FWD * 0.2 - UP))),
             (0.66, tuple(rig._unit(FWD * 0.2 - UP * 0.6))), (0.82, tuple(rig._unit(LEFT * 0.5 - UP * 0.4))),
             (1.00, tuple(rig._unit(FWD * 0.4 - UP)))],
        torso=[(0.00, {"Spine": (26, 0, 0), "Chest": (12, 0, 0), "Neck": (-18, 0, 0), "Head": (-10, 0, 0),
                       HIPS_POS: (0.03, 0, -0.06)}),
               (0.20, {"Spine": (16, 0, -6), "Chest": (8, 0, -6), "Neck": (-12, 0, 4), HIPS_POS: (0.01, 0, -0.02)}),
               (0.36, {"Spine": (34, 0, 2), "Chest": (16, 0, 2), "Neck": (-24, 0, 0), "Head": (-12, 0, 0),
                       HIPS_POS: (0.05, 0, -0.13)}),
               (0.46, {"Spine": (36, 0, 2), "Chest": (17, 0, 2), "Neck": (-25, 0, 0), "Head": (-13, 0, 0),
                       HIPS_POS: (0.05, 0, -0.14)}),
               (0.66, {"Spine": (24, 0, 12), "Chest": (12, 0, 14), "Neck": (-16, 0, -8), "Head": (-8, 0, -8),
                       HIPS_POS: (0.02, 0, -0.06)}),
               (0.82, {"Spine": (8, 0, 22), "Chest": (4, 0, 26), "Neck": (-4, 0, -14), "Head": (-2, 0, -14),
                       HIPS_POS: (-0.01, 0.02, 0.0)}),
               (1.00, {"Spine": (26, 0, 0), "Chest": (12, 0, 0), "Neck": (-18, 0, 0), "Head": (-10, 0, 0),
                       HIPS_POS: (0.03, 0, -0.06)})],
        events=[(0.36, "work_dig"), (0.36, "hit_start"), (0.44, "hit_end")])

    # -- talk and gestures -------------------------------------------------------------------
    def gesture(name: str, length: float, keys: Sequence[Tuple[float, Pose, str]], loop: bool = False,
                stance: str = "idle", layers: Sequence[Callable[[float], Pose]] = (),
                events: Sequence[Tuple[float, str]] = ()) -> ClipBuilder:
        cb = ClipBuilder(skel, name, length, loop=loop, grounded=True)
        set_stance(cb, stance)
        for t, p, ez in keys:
            cb.key(t * length, pose_add(rel, p), ez)
        for l in layers:
            cb.layer(l)
        for t, e in events:
            cb.event(t * length, e)
        return cb

    out["Talk_1"] = gesture("Talk_1", 3.2, loop=True, keys=[
        (0.00, {"UpperArm.R": (18, -30, 0), "LowerArm.R": (52, 0, 0), "Hand.R": (-10, 10, 0)}, "smooth"),
        (0.18, {"UpperArm.R": (34, -22, 0), "LowerArm.R": (64, 0, 0), "Hand.R": (-18, 16, 0),
                "Spine": (0, 0, -5), "Chest": (0, 0, -7), "Neck": (0, 0, 4), "Head": (-3, 0, 5)}, "out"),
        (0.36, {"UpperArm.R": (22, -28, 0), "LowerArm.R": (48, 0, 0), "Hand.R": (-8, 6, 0),
                "Chest": (0, 0, -2), "Head": (2, 0, 0)}, "smooth"),
        (0.56, {"UpperArm.R": (38, -18, 0), "LowerArm.R": (70, 0, 0), "Hand.R": (-20, 20, 0),
                "UpperArm.L": (10, -38, 0), "LowerArm.L": (30, 0, 0),
                "Spine": (0, 0, 4), "Chest": (0, 0, 6), "Head": (-2, 0, -4)}, "out"),
        (0.78, {"UpperArm.R": (20, -30, 0), "LowerArm.R": (50, 0, 0), "Hand.R": (-10, 8, 0), "Head": (2, 0, 2)}, "smooth"),
        (1.00, {"UpperArm.R": (18, -30, 0), "LowerArm.R": (52, 0, 0), "Hand.R": (-10, 10, 0)}, "smooth"),
    ], layers=[breathing(period=3.2, amount=0.9), head_look(period=2.6, yaw=6.0, pitch=2.5)])

    out["Talk_2"] = gesture("Talk_2", 3.6, loop=True, keys=[
        (0.00, {"UpperArm.L": (16, -32, 0), "UpperArm.R": (16, -32, 0), "LowerArm.L": (46, 0, 0), "LowerArm.R": (46, 0, 0)}, "smooth"),
        (0.22, {"UpperArm.L": (30, -22, 0), "UpperArm.R": (30, -22, 0), "LowerArm.L": (70, 0, 0), "LowerArm.R": (70, 0, 0),
                "Hand.L": (-16, -14, 0), "Hand.R": (-16, 14, 0), "Spine": (-4, 0, 0), "Chest": (-3, 0, 0),
                "Neck": (6, 0, 0), "Head": (6, 0, 0)}, "out"),
        (0.44, {"UpperArm.L": (18, -30, 0), "UpperArm.R": (18, -30, 0), "LowerArm.L": (50, 0, 0), "LowerArm.R": (50, 0, 0),
                "Spine": (2, 0, 0), "Head": (-2, 0, 0)}, "smooth"),
        (0.66, {"UpperArm.L": (10, -36, 0), "UpperArm.R": (34, -20, 0), "LowerArm.R": (60, 0, 0),
                "Hand.R": (-14, 18, 0), "Spine": (0, 0, -6), "Chest": (0, 0, -8), "Head": (0, 0, 6)}, "out"),
        (1.00, {"UpperArm.L": (16, -32, 0), "UpperArm.R": (16, -32, 0), "LowerArm.L": (46, 0, 0), "LowerArm.R": (46, 0, 0)}, "smooth"),
    ], layers=[breathing(period=3.6, amount=0.9), head_look(period=3.0, yaw=7.0, pitch=3.0)])

    out["Wave"] = gesture("Wave", 1.55, keys=[
        (0.00, {}, "smooth"),
        (0.22, {"Shoulder.R": (8, 10, 0), "UpperArm.R": (44, 24, 0), "LowerArm.R": (88, 0, 0), "Hand.R": (0, 10, 0),
                "Spine": (0, 0, -6), "Chest": (0, 0, -8), "Head": (-2, 0, 6)}, "out"),
        (0.40, {"Shoulder.R": (8, 10, 0), "UpperArm.R": (44, 24, 0), "LowerArm.R": (88, 0, -24), "Hand.R": (0, 10, -12),
                "Chest": (0, 0, -8), "Head": (-2, 0, 6)}, "smooth"),
        (0.56, {"Shoulder.R": (8, 10, 0), "UpperArm.R": (44, 24, 0), "LowerArm.R": (88, 0, 22), "Hand.R": (0, 10, 12),
                "Chest": (0, 0, -8), "Head": (-2, 0, 6)}, "smooth"),
        (0.72, {"Shoulder.R": (8, 10, 0), "UpperArm.R": (44, 24, 0), "LowerArm.R": (88, 0, -20), "Hand.R": (0, 10, -10),
                "Chest": (0, 0, -8), "Head": (-2, 0, 6)}, "smooth"),
        (1.00, {}, "smooth"),
    ], events=[(0.24, "gesture")])

    out["Bow_Gesture"] = gesture("Bow_Gesture", 1.85, keys=[
        (0.00, {}, "smooth"),
        (0.14, {"Spine": (-6, 0, 0), "Chest": (-4, 0, 0), "Neck": (6, 0, 0)}, "out2"),
        (0.40, {"Spine": (34, 0, 0), "Chest": (16, 0, 0), "Neck": (-8, 0, 0), "Head": (-6, 0, 0),
                "UpperArm.L": (6, -38, 0), "UpperArm.R": (22, -24, 0), "LowerArm.R": (66, 0, 0),
                "Hand.R": (-16, 14, 0), HIPS_POS: (0.04, 0, -0.03)}, "out"),
        (0.62, {"Spine": (36, 0, 0), "Chest": (17, 0, 0), "Neck": (-9, 0, 0), "Head": (-7, 0, 0),
                "UpperArm.L": (6, -38, 0), "UpperArm.R": (24, -22, 0), "LowerArm.R": (68, 0, 0),
                "Hand.R": (-18, 16, 0), HIPS_POS: (0.04, 0, -0.035)}, "smooth"),
        (1.00, {}, "out2"),
    ], events=[(0.42, "gesture")])

    out["Laugh"] = gesture("Laugh", 1.9, keys=[
        (0.00, {}, "smooth"),
        (0.16, {"Spine": (-10, 0, 0), "Chest": (-8, 0, 0), "Neck": (16, 0, 0), "Head": (18, 0, 0),
                "UpperArm.L": (12, -34, 0), "UpperArm.R": (12, -34, 0), "LowerArm.R": (60, 0, 0),
                "Hand.R": (-14, 8, 0)}, "out"),
        (0.30, {"Spine": (-4, 0, 0), "Chest": (-3, 0, 0), "Neck": (10, 0, 0), "Head": (11, 0, 0),
                "UpperArm.R": (14, -32, 0), "LowerArm.R": (66, 0, 0)}, "smooth"),
        (0.44, {"Spine": (-10, 0, 0), "Chest": (-8, 0, 0), "Neck": (16, 0, 0), "Head": (18, 0, 0),
                "UpperArm.R": (12, -34, 0), "LowerArm.R": (60, 0, 0)}, "smooth"),
        (0.58, {"Spine": (-5, 0, 0), "Chest": (-4, 0, 0), "Neck": (11, 0, 0), "Head": (12, 0, 0),
                "UpperArm.R": (14, -32, 0), "LowerArm.R": (66, 0, 0)}, "smooth"),
        (0.74, {"Spine": (-8, 0, 0), "Chest": (-6, 0, 0), "Neck": (13, 0, 0), "Head": (14, 0, 0)}, "smooth"),
        (1.00, {}, "smooth"),
    ], events=[(0.16, "gesture")])

    out["Rude"] = gesture("Rude", 1.4, keys=[
        (0.00, {}, "smooth"),
        (0.18, {"Shoulder.R": (10, 6, 0), "UpperArm.R": (36, -12, 0), "LowerArm.R": (92, 0, 0), "Hand.R": (-24, 14, 0),
                "Spine": (0, 0, -6), "Chest": (0, 0, -8), "Head": (2, 0, 8), "Neck": (0, 0, 4)}, "snap"),
        (0.34, {"Shoulder.R": (12, 8, 0), "UpperArm.R": (48, -6, 0), "LowerArm.R": (98, 0, 0), "Hand.R": (-28, 18, 0),
                "Spine": (0, 0, -8), "Chest": (0, 0, -10), "Head": (4, 0, 10), "Neck": (0, 0, 5),
                HIPS_POS: (0.03, 0, 0.0)}, "out"),
        (0.62, {"Shoulder.R": (12, 8, 0), "UpperArm.R": (46, -8, 0), "LowerArm.R": (96, 0, 0), "Hand.R": (-26, 16, 0),
                "Chest": (0, 0, -10), "Head": (4, 0, 10)}, "smooth"),
        (1.00, {}, "smooth"),
    ], events=[(0.20, "gesture")])

    out["Dance"] = gesture("Dance", 2.4, loop=True, stance="idle", keys=[
        (0.00, {"UpperArm.L": (16, -14, 0), "UpperArm.R": (16, -14, 0), "LowerArm.L": (76, 0, 0), "LowerArm.R": (76, 0, 0),
                "Hips": (0, 4, 10), "Spine": (0, 4, 6), "Chest": (0, 3, 8), "Head": (0, 0, -8),
                HIPS_POS: (0.0, 0.03, -0.03)}, "smooth"),
        (0.25, {"UpperArm.L": (34, 6, 0), "UpperArm.R": (4, -30, 0), "LowerArm.L": (84, 0, 0), "LowerArm.R": (54, 0, 0),
                "Hips": (0, -2, -6), "Spine": (2, -2, -4), "Chest": (2, -2, -6), "Head": (0, 0, 6),
                HIPS_POS: (0.0, -0.02, 0.005)}, "smooth"),
        (0.50, {"UpperArm.L": (16, -14, 0), "UpperArm.R": (16, -14, 0), "LowerArm.L": (76, 0, 0), "LowerArm.R": (76, 0, 0),
                "Hips": (0, -4, -10), "Spine": (0, -4, -6), "Chest": (0, -3, -8), "Head": (0, 0, 8),
                HIPS_POS: (0.0, -0.03, -0.03)}, "smooth"),
        (0.75, {"UpperArm.L": (4, -30, 0), "UpperArm.R": (34, 6, 0), "LowerArm.L": (54, 0, 0), "LowerArm.R": (84, 0, 0),
                "Hips": (0, 2, 6), "Spine": (2, 2, 4), "Chest": (2, 2, 6), "Head": (0, 0, -6),
                HIPS_POS: (0.0, 0.02, 0.005)}, "smooth"),
        (1.00, {"UpperArm.L": (16, -14, 0), "UpperArm.R": (16, -14, 0), "LowerArm.L": (76, 0, 0), "LowerArm.R": (76, 0, 0),
                "Hips": (0, 4, 10), "Spine": (0, 4, 6), "Chest": (0, 3, 8), "Head": (0, 0, -8),
                HIPS_POS: (0.0, 0.03, -0.03)}, "smooth"),
    ], events=[(0.0, "footstep_l"), (0.5, "footstep_r")])

    out["Cheer"] = gesture("Cheer", 1.7, keys=[
        (0.00, {}, "smooth"),
        (0.12, {"Spine": (12, 0, 0), "Neck": (-8, 0, 0), "UpperArm.L": (-16, -30, 0), "UpperArm.R": (-16, -30, 0),
                "LowerArm.L": (40, 0, 0), "LowerArm.R": (40, 0, 0), HIPS_POS: (0.02, 0, -0.08)}, "in2"),
        (0.30, {"Spine": (-10, 0, 0), "Chest": (-8, 0, 0), "Neck": (12, 0, 0), "Head": (12, 0, 0),
                "Shoulder.L": (-6, 16, 0), "Shoulder.R": (-6, 16, 0),
                "UpperArm.L": (158, 14, 0), "UpperArm.R": (158, 14, 0), "LowerArm.L": (14, 0, 0), "LowerArm.R": (14, 0, 0),
                HIPS_POS: (0.0, 0, 0.03)}, "out"),
        (0.52, {"Spine": (-8, 0, 0), "Chest": (-6, 0, 0), "Neck": (10, 0, 0), "Head": (10, 0, 0),
                "Shoulder.L": (-6, 16, 0), "Shoulder.R": (-6, 16, 0),
                "UpperArm.L": (150, 18, 0), "UpperArm.R": (150, 18, 0), "LowerArm.L": (22, 0, 0), "LowerArm.R": (22, 0, 0)}, "smooth"),
        (0.70, {"Spine": (-10, 0, 0), "Neck": (12, 0, 0), "Head": (12, 0, 0),
                "UpperArm.L": (158, 14, 0), "UpperArm.R": (158, 14, 0), "LowerArm.L": (14, 0, 0), "LowerArm.R": (14, 0, 0)}, "smooth"),
        (1.00, {}, "smooth"),
    ], events=[(0.28, "gesture")])

    out["Cower"] = gesture("Cower", 2.6, loop=True, stance="idle", keys=[
        (0.00, {"Spine": (34, 0, 0), "Chest": (14, 0, 0), "Neck": (-16, 0, 0), "Head": (-12, 0, 0),
                "Shoulder.L": (18, 14, 0), "Shoulder.R": (18, 14, 0),
                "UpperArm.L": (62, 6, 0), "UpperArm.R": (62, 6, 0), "LowerArm.L": (118, 0, 0), "LowerArm.R": (118, 0, 0),
                "UpperLeg.L": (18, 6, 0), "UpperLeg.R": (18, 6, 0), "LowerLeg.L": (22, 0, 0), "LowerLeg.R": (22, 0, 0),
                HIPS_POS: (0.05, 0, -0.14)}, "smooth"),
        (0.50, {"Spine": (38, 0, 3), "Chest": (16, 0, 3), "Neck": (-18, 0, -2), "Head": (-14, 0, -3),
                "Shoulder.L": (20, 16, 0), "Shoulder.R": (20, 16, 0),
                "UpperArm.L": (66, 4, 0), "UpperArm.R": (66, 4, 0), "LowerArm.L": (122, 0, 0), "LowerArm.R": (122, 0, 0),
                "UpperLeg.L": (20, 6, 0), "UpperLeg.R": (20, 6, 0), "LowerLeg.L": (24, 0, 0), "LowerLeg.R": (24, 0, 0),
                HIPS_POS: (0.055, 0, -0.16)}, "smooth"),
        (1.00, {"Spine": (34, 0, 0), "Chest": (14, 0, 0), "Neck": (-16, 0, 0), "Head": (-12, 0, 0),
                "Shoulder.L": (18, 14, 0), "Shoulder.R": (18, 14, 0),
                "UpperArm.L": (62, 6, 0), "UpperArm.R": (62, 6, 0), "LowerArm.L": (118, 0, 0), "LowerArm.R": (118, 0, 0),
                "UpperLeg.L": (18, 6, 0), "UpperLeg.R": (18, 6, 0), "LowerLeg.L": (22, 0, 0), "LowerLeg.R": (22, 0, 0),
                HIPS_POS: (0.05, 0, -0.14)}, "smooth"),
    ])

    pt = ClipBuilder(skel, "Point", 1.5, loop=False, grounded=True)
    set_stance(pt, "idle")
    pt.key(0.00, rel)
    pt.key(0.24, pose_add(rel, {"Spine": (0, 0, -8), "Chest": (0, 0, -12), "Neck": (0, 0, 8), "Head": (0, 0, 10),
                                "Shoulder.R": (14, 6, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.56, -0.10, 0.12)), "Hand.R@aim": tuple(FWD)}, "out")
    pt.key(0.90, pose_add(rel, {"Spine": (0, 0, -8), "Chest": (0, 0, -12), "Neck": (0, 0, 8), "Head": (0, 0, 10),
                                "Shoulder.R": (14, 6, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.58, -0.10, 0.13)), "Hand.R@aim": tuple(FWD)}, "smooth")
    pt.key(1.50, rel, "smooth")
    pt.event(0.26, "gesture")
    out["Point"] = pt

    dr = ClipBuilder(skel, "Drink", 2.0, loop=False, grounded=True)
    set_stance(dr, "idle")
    cup_low = body_point(skel, 0.26, -0.14, -0.10)
    cup_lip = body_point(skel, 0.12, -0.05, 0.28)
    dr.key(0.00, rel | {"Hand.R@grip": tuple(cup_low), "Hand.R@aim": tuple(UP)})
    dr.key(0.30, pose_add(rel, {"Shoulder.R": (10, 8, 0)}) |
           {"Hand.R@grip": tuple(cup_lip), "Hand.R@aim": tuple(UP)}, "out2")
    dr.key(0.50, pose_add(rel, {"Shoulder.R": (10, 8, 0), "Neck": (-16, 0, 0), "Head": (-14, 0, 0),
                                "Spine": (-4, 0, 0)}) |
           {"Hand.R@grip": tuple(cup_lip + UP * 0.03 * s), "Hand.R@aim": tuple(rig._unit(UP + FWD * 0.55))}, "smooth")
    dr.key(0.72, pose_add(rel, {"Shoulder.R": (10, 8, 0), "Neck": (-16, 0, 0), "Head": (-14, 0, 0),
                                "Spine": (-4, 0, 0)}) |
           {"Hand.R@grip": tuple(cup_lip + UP * 0.03 * s), "Hand.R@aim": tuple(rig._unit(UP + FWD * 0.6))}, "smooth")
    dr.key(1.00, rel | {"Hand.R@grip": tuple(cup_low), "Hand.R@aim": tuple(UP)}, "out")
    for k in dr.track.keys:
        k.t *= 2.0
    dr.event(1.05, "drink")
    out["Drink"] = dr

    ea = ClipBuilder(skel, "Eat", 2.1, loop=False, grounded=True)
    set_stance(ea, "idle")
    food_low = body_point(skel, 0.28, -0.12, -0.06)
    food_mouth = body_point(skel, 0.14, -0.04, 0.26)
    ea.key(0.00, rel | {"Hand.R@grip": tuple(food_low), "Hand.R@aim": tuple(FWD)})
    ea.key(0.30 * 2.1, pose_add(rel, {"Shoulder.R": (10, 6, 0), "Neck": (-4, 0, 0)}) |
           {"Hand.R@grip": tuple(food_mouth), "Hand.R@aim": tuple(rig._unit(BACK + UP * 0.2))}, "out2")
    ea.key(0.42 * 2.1, pose_add(rel, {"Shoulder.R": (10, 6, 0), "Neck": (-6, 0, 0), "Head": (-4, 0, 0)}) |
           {"Hand.R@grip": tuple(food_mouth + BACK * 0.01 * s), "Hand.R@aim": tuple(rig._unit(BACK + UP * 0.2))}, "smooth")
    ea.key(0.56 * 2.1, pose_add(rel, {"Shoulder.R": (8, 4, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.22, -0.10, 0.06)), "Hand.R@aim": tuple(FWD)}, "out")
    ea.key(0.74 * 2.1, pose_add(rel, {"Neck": (3, 0, 4), "Head": (3, 0, 5), "Chest": (1, 0, 0)}) |
           {"Hand.R@grip": tuple(body_point(skel, 0.24, -0.11, 0.0)), "Hand.R@aim": tuple(FWD)}, "smooth")
    ea.key(2.1, rel | {"Hand.R@grip": tuple(food_low), "Hand.R@aim": tuple(FWD)}, "smooth")
    ea.event(0.40 * 2.1, "eat")
    out["Eat"] = ea

    rd = ClipBuilder(skel, "Read", 4.2, loop=True, grounded=True)
    set_stance(rd, "idle")
    book: Pose = {"Spine": (8, 0, 0), "Chest": (2, 0, 0), "Neck": (-16, 0, 0), "Head": (-12, 0, 0),
                  "Shoulder.L": (16, 6, 0), "Shoulder.R": (16, 6, 0)}
    bl = body_point(skel, 0.30, 0.13, -0.02)
    brr = body_point(skel, 0.30, -0.13, -0.02)
    rd.key(0.0, pose_add(rel, book) | {"Hand.L@grip": tuple(bl), "Hand.L@aim": tuple(rig._unit(FWD + UP * 0.2)),
                                       "Hand.R@grip": tuple(brr), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.2))})
    rd.key(2.1, pose_add(rel, book, {"Head": (-12, 0, 6), "Neck": (-16, 0, 4)}) |
           {"Hand.L@grip": tuple(bl + UP * 0.006 * s), "Hand.L@aim": tuple(rig._unit(FWD + UP * 0.22)),
            "Hand.R@grip": tuple(brr + UP * 0.006 * s), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.22))}, "smooth")
    rd.key(4.2, pose_add(rel, book) | {"Hand.L@grip": tuple(bl), "Hand.L@aim": tuple(rig._unit(FWD + UP * 0.2)),
                                       "Hand.R@grip": tuple(brr), "Hand.R@aim": tuple(rig._unit(FWD + UP * 0.2))}, "smooth")
    rd.layer(breathing(period=4.2, amount=0.8))
    out["Read"] = rd
    return out


# --------------------------------------------------------------------------------------
# the whole library
# --------------------------------------------------------------------------------------

def build_clips(skel: Skeleton) -> Dict[str, ClipBuilder]:
    """Every clip in CONTRACTS §3, in contract order."""
    clips: Dict[str, ClipBuilder] = {}
    clips.update(locomotion_clips(skel))
    clips.update(dodge_clips(skel))
    clips.update(melee_clips(skel))
    clips.update(defence_clips(skel))
    clips.update(ranged_clips(skel))
    clips.update(life_clips(skel))
    _mark_cocked(clips)
    return clips


def _mark_cocked(clips: Dict[str, ClipBuilder]) -> None:
    """Puts a `cocked` event on every clip with a blow: the moment its wind-up has drawn the weapon
    (or the fist, or the hand that casts) all the way back, the key that opens the hold before the
    strike's snap. The game's AnimationDriver holds a foe's picture there when its authored
    telegraph is longer than the clip's own wind-up, instead of playing the whole wind-up in slow
    motion (an enemy's telegraph is gameplay timing, and its clip is only a picture of it)."""
    for cb in clips.values():
        if not any(n == "hit_start" for _, n in cb.events) or any(n == "cocked" for _, n in cb.events):
            continue
        keys = cb.track.keys
        snaps = [i for i, k in enumerate(keys) if k.ease == "snap" and i > 0]
        if not snaps:
            continue
        i = snaps[0]
        cocked = keys[i - 2].t if i >= 2 else keys[i - 1].t
        hs = next(t for t, n in cb.events if n == "hit_start")
        if 0.0 < cocked < hs:
            cb.event(cocked, "cocked")


REQUIRED_CLIPS: List[str] = [
    "Idle", "Idle_Combat", "Walk", "Walk_Back", "Trot", "Run", "Sprint", "Strafe_L", "Strafe_R", "Sneak_Idle",
    "Sneak_Walk", "Turn_L90", "Turn_R90", "Turn_L180", "Turn_R180", "Jump_Start", "Jump_Loop", "Jump_Land", "Fall_Loop",
    "Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R",
    "Attack_1H_Light_1", "Attack_1H_Light_2", "Attack_1H_Light_3", "Attack_1H_Heavy",
    "Attack_2H_Light_1", "Attack_2H_Light_2", "Attack_2H_Heavy",
    "Attack_Dagger_1", "Attack_Dagger_2", "Attack_Unarmed_1", "Attack_Unarmed_2",
    "Riposte", "Backstab",
    "Block_Idle", "Block_Hit", "Parry", "Hit_Light", "Hit_Heavy", "Stagger", "Knockdown",
    "Hit_Light_B", "Hit_Light_L", "Hit_Light_R", "Stagger_B", "Stagger_L", "Stagger_R",
    "Get_Up", "Death_A", "Death_B",
    "Bow_Draw", "Bow_Aim", "Bow_Release", "Cast_Quick", "Cast_Long", "Cast_Loop", "Throw",
    "Interact", "Pick_Up", "Sit_Down", "Sit_Idle", "Stand_Up", "Sleep_Idle",
    "Work_Hammer", "Work_Chop", "Work_Stir", "Work_Dig", "Talk_1", "Talk_2", "Wave",
    "Bow_Gesture", "Laugh", "Rude", "Dance", "Cheer", "Cower", "Point", "Drink", "Eat", "Read",
]
ATTACK_CLIPS = [c for c in REQUIRED_CLIPS if c.startswith("Attack_")] + ["Riposte", "Backstab"]
LOCOMOTION_CLIPS = ["Walk", "Walk_Back", "Trot", "Run", "Sprint", "Strafe_L", "Strafe_R", "Sneak_Walk"]
## The gaits the game blends in phase and plays stride-matched: each carries its ground speed in
## the sidecar (`speed`), and each puts its left foot down at phase 0 and its right at 0.5.
GAIT_CLIPS = ["Walk", "Trot", "Run", "Sprint", "Sneak_Walk", "Walk_Back", "Strafe_L", "Strafe_R"]
## The turns on the spot, played at the rate the body turns: each carries the angle one cycle
## covers in the sidecar (`turn`, degrees, + to the left).
TURN_CLIPS = ["Turn_L90", "Turn_R90", "Turn_L180", "Turn_R180"]


def check_contract(clips: Dict[str, ClipBuilder]) -> List[str]:
    """Problems against CONTRACTS §3: missing clips, missing events, unloopable loops."""
    problems: List[str] = []
    for name in REQUIRED_CLIPS:
        if name not in clips:
            problems.append(f"missing clip {name}")
    for name in ATTACK_CLIPS:
        c = clips.get(name)
        if c is None:
            continue
        have = {e for _, e in c.events}
        for ev in ("hit_start", "hit_end", "cancel_ok"):
            if ev not in have:
                problems.append(f"{name}: missing event {ev}")
    for name in LOCOMOTION_CLIPS:
        c = clips.get(name)
        if c is None:
            continue
        have = {e for _, e in c.events}
        for ev in ("footstep_l", "footstep_r"):
            if ev not in have:
                problems.append(f"{name}: missing event {ev}")
    for name, c in clips.items():
        for t, e in c.events:
            if t < 0 or t > c.length + 1e-6:
                problems.append(f"{name}: event {e} at {t:.3f} outside 0..{c.length:.3f}")
        # a loop is baked a frame at a time, and closes only on a frame: 0.96 s of walk ended
        # between two, and the game played the step after the last one twice
        frames = c.length * c.fps
        if c.loop and abs(frames - round(frames)) > 1e-6:
            problems.append(f"{name}: a loop of {c.length:.4f} s is {frames:.2f} frames, not a whole number")
    for name in TURN_CLIPS:
        c = clips.get(name)
        if c is not None and "turn" not in c.extra:
            problems.append(f"{name}: no `turn` angle for the game to play it by")
    return problems
