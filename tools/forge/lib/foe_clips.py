"""The clips of a forged four-legged foe on WM_Quadruped_v1: a dog, a boar, a reptile.

Pure numpy, on lib/quad_clips.py's poses and solver. What a foe's AI and combat brain play
(game/actors/enemy/enemy.gd, game/actors/shared/actor.gd, CONTRACTS §3):

    Idle, Idle_Combat                         standing; squared up to a foe, snarling
    Walk, Trot, Run, Walk_Back                the gaits, each with its `speed` (CreatureModel picks
    Strafe_L, Strafe_R, Turn_L90, Turn_R90    by ground speed and plays at speed / `speed`)
    Attack_1, Attack_2 (Attack_3 ...)         each with `cocked`, `hit_start`, `hit_end`, `cancel_ok`:
                                              the game stretches the wind-up to its telegraph and
                                              holds at `cocked` (AnimationDriver.windup_plan)
    Hit, Stagger                              a flinch; thrown off its feet a moment
    Knockdown, Get_Up                         rolled onto its side and held; back up
    Death                                     down on its side, the last frame held

A leg that leaves the body's side plane (a beast lying on its side) is posed with `free_foot`:
its toe, the directions of its pad, toes and metacarpus, and the way its elbow or stifle bends,
all in the armature's frame. `FoeSolver` solves those as it solves a standing leg.
"""
from __future__ import annotations

import math
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np

from .anim import FPS
from .rig import mat_to_quat
from .quadruped import QuadSkeleton, FEET, foot_bones, DEFORM_NAMES
from .quad_clips import (QuadClip, QuadPose, FootPose, GaitSpec, gait_clip, gait_pose, _FoldSolver, sag, sag_angle,
                         smooth, bump, wave, pitch_up, yaw_left, roll_left, hit_clip)


def _u(v) -> np.ndarray:
    v = np.asarray(v, float)
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


def _lerp(a, b, t):
    return a + (b - a) * t


class FoeSolver(_FoldSolver):
    """The quadruped's solver, and legs given by direction (free_foot) as well as by angle. `splay`
    bends the elbows and the knees out from the body as well as back and forward: a reptile's
    sprawl (0 for an upright leg)."""

    splay = 0.0

    def _leg(self, pose: dict, foot: str, fp: FootPose) -> None:
        if not getattr(fp, "free", False):
            if not self.splay:
                return super()._leg(pose, foot, fp)
            if isinstance(fp.cannon, tuple):
                sk = self.skel
                bones = foot_bones(foot)
                C = fp.toe - sk.bones[bones[-1]].length * sag(fp.hoof)
                F = C - sk.bones[bones[-2]].length * sag(fp.pastern)
                W = sk.fk(pose)
                line = sag_angle(F - W[bones[0]][:3, 3])
                share = 1.0 if foot[0] == "F" else self.HIND_CANNON_SHARE
                fp = FootPose(toe=fp.toe, hoof=fp.hoof, pastern=fp.pastern,
                              cannon=self._rest_cannon[foot] + share * (line - self._rest_line[foot]) + fp.cannon[1],
                              planted=fp.planted)
            return self._splayed_leg(pose, foot, fp)
        sk = self.skel
        bones = foot_bones(foot)
        hoof, past, can = bones[-1], bones[-2], bones[-3]
        lo, up = bones[-4], bones[-5]
        toe = np.asarray(fp.toe, float)
        C = toe - sk.bones[hoof].length * _u(fp.hoof)
        F = C - sk.bones[past].length * _u(fp.pastern)
        K = F - sk.bones[can].length * _u(fp.cannon)
        W = sk.fk(pose)
        Ru, Rl, err = sk.two_bone(W, up, lo, K, np.asarray(fp.pole, float))
        self.reach_error = max(self.reach_error, err * 0.25)    # a lying leg may not reach: not a gait's fault
        pose[up] = (Ru, None)
        pose[lo] = (Rl, None)
        W = sk.fk(pose)
        k_at = sk.tail_world(W, lo)
        pose[can] = (sk.aim(W, can, F - k_at), None)
        W = sk.fk(pose)
        f_at = sk.tail_world(W, can)
        pose[past] = (sk.aim(W, past, C - f_at), None)
        W = sk.fk(pose)
        c_at = sk.tail_world(W, past)
        pose[hoof] = (sk.aim(W, hoof, toe - c_at), None)


def _splayed_leg(self, pose: dict, foot: str, fp: FootPose) -> None:
    """Solver._leg with the elbow and the knee bent out to the side by `splay`."""
    sk = self.skel
    bones = foot_bones(foot)
    fore = foot[0] == "F"
    hoof, past, can = bones[-1], bones[-2], bones[-3]
    lo, up = bones[-4], bones[-5]
    toe = np.asarray(fp.toe, float)
    x = toe[0]
    C = toe - sk.bones[hoof].length * sag(fp.hoof)
    F = C - sk.bones[past].length * sag(fp.pastern)
    W = sk.fk(pose)
    top = bones[0]
    line = sag_angle(F - W[top][:3, 3])
    if fore:
        d = (line - self._rest_line[foot]) * self.SCAPULA_SHARE
        pose[top] = (sk.local_turn(top, pitch_up(d)), None)
        W = sk.fk(pose)
    share = 1.0 if fore else self.HIND_CANNON_SHARE
    cannon = fp.cannon if fp.cannon is not None else self._rest_cannon[foot] + share * (line - self._rest_line[foot])
    K = F - sk.bones[can].length * sag(cannon)
    K[0] = x + (sk.bones[can].head[0] - sk.bones[can].tail[0])
    sx = 1.0 if foot[1] == "L" else -1.0
    pole = np.array([sx * self.splay, 1.0 if fore else -1.0, 0.0])
    Ru, Rl, err = sk.two_bone(W, up, lo, K, pole)
    self.reach_error = max(self.reach_error, err)
    pose[up] = (Ru, None)
    pose[lo] = (Rl, None)
    W = sk.fk(pose)
    pose[can] = (sk.aim(W, can, F - sk.tail_world(W, lo)), None)
    W = sk.fk(pose)
    pose[past] = (sk.aim(W, past, C - sk.tail_world(W, can)), None)
    W = sk.fk(pose)
    pose[hoof] = (sk.aim(W, hoof, toe - sk.tail_world(W, past)), None)


FoeSolver._splayed_leg = _splayed_leg


def free_foot(toe, hoof, pastern, cannon, pole, planted: bool = False) -> FootPose:
    fp = FootPose(toe=np.asarray(toe, float), hoof=0.0, pastern=0.0, cannon=None, planted=planted)
    fp.hoof = _u(hoof)
    fp.pastern = _u(pastern)
    fp.cannon = _u(cannon)
    fp.free = True
    fp.pole = _u(pole)
    return fp


def default_pole(foot: str) -> np.ndarray:
    return np.array([0.0, 1.0, 0.0]) if foot[0] == "F" else np.array([0.0, -1.0, 0.0])


def make_solver(skel: QuadSkeleton) -> FoeSolver:
    return FoeSolver(skel)


def trunk_xf(solver, qp: QuadPose) -> Tuple[np.ndarray, Callable[[np.ndarray], np.ndarray]]:
    """The trunk's turn, and where a point carried rigidly by the trunk at rest goes in pose `qp`."""
    hb = solver.skel.bones["Hips"]
    Rt = yaw_left(qp.yaw) @ pitch_up(qp.pitch) @ roll_left(qp.roll)
    pivot = hb.head if qp.pivot is None else np.asarray(qp.pivot, float)
    off = np.array([qp.side, -qp.ahead, qp.lift])
    return Rt, (lambda p: pivot + Rt @ (np.asarray(p, float) - pivot) + off)


def stand(solver) -> Dict[str, FootPose]:
    return {f: FootPose(toe=r.toe.copy(), hoof=r.hoof, pastern=r.pastern) for f, r in solver.rest.items()}


def as_free(solver, f: str, fp: FootPose) -> FootPose:
    """A standing foot given by angles, as a free one (for blending into a lying pose)."""
    if getattr(fp, "free", False):
        return fp
    can = fp.cannon if isinstance(fp.cannon, (int, float)) else solver._rest_cannon[f]
    return free_foot(fp.toe, sag(fp.hoof), sag(fp.pastern), sag(can), default_pole(f), fp.planted)


def blend_feet(solver, a: Dict[str, FootPose], b: Dict[str, FootPose], t: float) -> Dict[str, FootPose]:
    if t <= 0.0:
        return a
    if t >= 1.0:
        return b
    out = {}
    for f in FEET:
        fa, fb = as_free(solver, f, a[f]), as_free(solver, f, b[f])
        out[f] = free_foot(_lerp(fa.toe, fb.toe, t), _lerp(fa.hoof, fb.hoof, t), _lerp(fa.pastern, fb.pastern, t),
                           _lerp(fa.cannon, fb.cannon, t), _lerp(fa.pole, fb.pole, t), t < 0.5 and fa.planted)
    return out


def blend_pose(a: QuadPose, b: QuadPose, t: float, solver) -> QuadPose:
    """Every number of a and b mixed by t (feet as free legs)."""
    out = QuadPose()
    for name in ("lift", "ahead", "side", "pitch", "roll", "yaw", "loin", "bend", "neck", "neck_turn", "head",
                 "head_turn", "jaw", "tail", "tail_swing"):
        setattr(out, name, _lerp(getattr(a, name), getattr(b, name), t))
    out.ears = (_lerp(a.ears[0], b.ears[0], t), _lerp(a.ears[1], b.ears[1], t))
    out.ear_turn = (_lerp(a.ear_turn[0], b.ear_turn[0], t), _lerp(a.ear_turn[1], b.ear_turn[1], t))
    pa = solver.skel.bones["Hips"].head if a.pivot is None else a.pivot
    pb = solver.skel.bones["Hips"].head if b.pivot is None else b.pivot
    out.pivot = _lerp(np.asarray(pa, float), np.asarray(pb, float), t)
    fa = a.feet or stand(solver)
    fb = b.feet or stand(solver)
    out.feet = blend_feet(solver, fa, fb, t)
    return out


# --------------------------------------------------------------------------------------
# A temperament: what differs between a wolf's clips and a boar's
# --------------------------------------------------------------------------------------

class Kind:
    """Scale and manner. `k` is the beast's size against a 0.80 m wolf; lengths in clips scale by it."""

    def __init__(self, skel: QuadSkeleton, family: str = "canid", **kw):
        self.skel = skel
        self.family = family
        self.k = skel.props.withers / 0.80
        self.tail_carriage = kw.get("tail_carriage", 0.0)     # a wolf's hangs; a boar's is up
        self.lie_side = kw.get("lie_side", 1.0)                # falls on its right side (1) or left (-1)
        self.lie_height = kw.get("lie_height", 0.15)           # the trunk's middle lying on its side, m at k=1
        self.sternal = kw.get("sternal", 0.24)                 # the back's height lying on the brisket
        self.ears_back = kw.get("ears_back", 35.0)
        self.lie_roll = kw.get("lie_roll", 84.0)              # on its side (84), or on its back (180)
        self.speeds = kw.get("speeds", {})
        self.cycles = kw.get("cycles", {})                     # frames a gait's cycle takes, by name
        self.turn = kw.get("turn", 90.0)                       # degrees a turn-on-the-spot cycle turns


def canid_gaits(K: Kind) -> List[GaitSpec]:
    k = K.k
    sp = {"Walk": 1.25, "Trot": 2.9, "Run": 6.2}
    sp.update(K.speeds)
    tail = K.tail_carriage
    return [
        GaitSpec("Walk", speed=sp["Walk"] * k ** 0.5, cycle=20 / FPS, duty=0.6,
                 footfalls={"HL": 0.0, "FL": 0.22, "HR": 0.5, "FR": 0.72},
                 lift=0.06 * k, fold=0.55, bob=0.008 * k, bobs=2, bob_at=0.05, nod=4.0, nods=2, nod_at=0.3,
                 roll=1.5, carriage=4.0, tail=tail, ears=-4.0),
        GaitSpec("Trot", speed=sp["Trot"] * k ** 0.5, cycle=14 / FPS, duty=0.4,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.085 * k, fold=0.85, bob=0.018 * k, bobs=2, bob_at=0.2, nod=2.5, nods=2, nod_at=0.25,
                 carriage=8.0, tail=tail + 4.0, ears=4.0),
        GaitSpec("Run", speed=sp["Run"] * k ** 0.5, cycle=(10 if K.family == "canid" else 8) / FPS, duty=0.21,
                 footfalls={"HL": 0.0, "HR": 0.09, "FR": 0.42, "FL": 0.52},
                 lift=0.11 * k, fold=1.0, bob=0.03 * k, bobs=1, bob_at=0.3, pitch=6.0, pitch_at=0.85,
                 nod=6.0, nods=1, nod_at=0.6, flex=13.0 if K.family == "canid" else 6.0, flex_at=0.75,
                 carriage=12.0 if K.family == "canid" else 2.0, tail=tail + 12.0, ears=24.0),
        GaitSpec("Walk_Back", speed=-0.9 * k ** 0.5, cycle=24 / FPS, duty=0.65,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.05 * k, fold=0.4, bob=0.006 * k, bobs=2, nod=3.0, nods=2, carriage=10.0, tail=tail - 8.0,
                 ears=20.0),
        GaitSpec("Turn_L90", speed=0.0, cycle=27 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.05 * k, fold=0.45, bob=0.006 * k, bobs=2, nod=3.0, carriage=6.0, turn=90.0, tail=tail),
        GaitSpec("Turn_R90", speed=0.0, cycle=27 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.05 * k, fold=0.45, bob=0.006 * k, bobs=2, nod=3.0, carriage=6.0, turn=-90.0, tail=tail),
    ]


def strafe_clip(solver, g: GaitSpec, name: str, way: float) -> QuadClip:
    """A walk whose planted feet travel across the body, not along it: the beast sidles one way
    (way +1: to its left) while it keeps its face to what it is watching. The feet's line is turned
    60 degrees, so the legs pass rather than cross; the head is turned a little toward the way."""
    ang = math.radians(60.0) * way
    c, sn = math.cos(ang), math.sin(ang)

    def sample(t: float) -> QuadPose:
        qp = gait_pose(solver, g, (t / g.cycle) % 1.0)
        for f, fp in qp.feet.items():
            r = solver.rest[f].toe
            d = fp.toe - r
            # +Y (planted feet carried back, the body going forward) is turned toward -X for a left way
            fp.toe = np.array([r[0] + d[0] * c - d[1] * sn, r[1] + d[0] * sn + d[1] * c, fp.toe[2]])
        qp.neck_turn += 8.0 * way
        qp.roll += 3.0 * way
        return qp
    frames = g.cycle * FPS
    events = [(round((g.footfalls[f] % 1.0) * g.cycle, 4), "hoof_" + f.lower()) for f in FEET]
    return QuadClip(name, g.cycle, True, sample, sorted(events),
                    {"speed": round(abs(g.speed), 4), "side": way, "gait": {"duty": g.duty, "footfalls": dict(g.footfalls)}})


# --------------------------------------------------------------------------------------
# Standing
# --------------------------------------------------------------------------------------

def idle_clip(solver, K: Kind, length: float = 4.0) -> QuadClip:
    """At ease but watching: the flanks breathing, the head turning to look about, an ear swivelling
    to a sound, the tail stirring; a dog pants a little, its jaw dropping open."""
    def sample(t: float) -> QuadPose:
        qp = QuadPose(feet=stand(solver))
        u = t / length
        b = math.sin(2 * math.pi * u * 4)
        qp.lift = 0.003 * K.k * b
        qp.loin = 0.8 * b
        qp.neck = 12.0 + 3.0 * math.sin(2 * math.pi * u)
        qp.neck_turn = 14.0 * math.sin(2 * math.pi * (u + 0.1)) * smooth(abs(math.sin(2 * math.pi * u)) * 1.4)
        qp.head = 2.0 * math.sin(2 * math.pi * (2 * u + 0.2))
        qp.head_turn = 6.0 * math.sin(2 * math.pi * (u + 0.15))
        e1 = bump(((u - 0.2) % 1.0) / 0.15) if ((u - 0.2) % 1.0) < 0.15 else 0.0
        qp.ears = (-6.0 + 30.0 * e1, -6.0)
        qp.ear_turn = (35.0 * e1, 0.0)
        qp.tail = K.tail_carriage + 3.0 * math.sin(2 * math.pi * u)
        qp.tail_swing = 8.0 * math.sin(2 * math.pi * 2 * u)
        if K.family == "canid":
            qp.jaw = 7.0 + 4.0 * math.sin(2 * math.pi * u * 8)
        return qp
    return QuadClip("Idle", length, True, sample, [], {})


def combat_idle_clip(solver, K: Kind, length: float = 2.0) -> QuadClip:
    """Squared up to a foe: the forehand low and the weight forward over braced forelegs, the head
    down and level with the eyes on you, the ears flat back, the lips drawn off the teeth; the body
    rocks a little on its legs, ready."""
    k = K.k

    def sample(t: float) -> QuadPose:
        u = t / length
        feet = stand(solver)
        for f in ("FL", "FR"):
            feet[f].toe[1] -= 0.05 * k
            feet[f].pastern += 6.0
        qp = QuadPose(feet=feet)
        sway = math.sin(2 * math.pi * u)
        qp.lift = -0.05 * k + 0.006 * k * math.sin(2 * math.pi * u * 2)
        qp.ahead = 0.025 * k * sway
        qp.pitch = -4.0
        qp.loin = 4.0
        qp.neck = 16.0
        qp.head = -14.0
        qp.head_turn = 3.0 * math.sin(2 * math.pi * (u + 0.3))
        qp.jaw = (9.0 if K.family == "canid" else 4.0) + 3.0 * max(0.0, math.sin(2 * math.pi * u * 3))
        qp.ears = (K.ears_back, K.ears_back)
        qp.tail = K.tail_carriage - 6.0 if K.family == "canid" else K.tail_carriage + 10.0
        qp.tail_swing = 3.0 * sway
        return qp
    return QuadClip("Idle_Combat", length, True, sample, [], {})


# --------------------------------------------------------------------------------------
# Attacks
# --------------------------------------------------------------------------------------

def bite_clip(solver, K: Kind, name: str = "Attack_1", length: float = 0.8, reach: float = 0.12,
              shake: float = 12.0) -> QuadClip:
    """The snap: drawn back and down over the hind legs, the lips off the teeth; then the head and
    the forehand thrust forward with the jaws open, a forefoot stepping in, the jaws shut on
    `hit_start` and the head wrenched side to side as it lets go."""
    k = K.k
    cocked, strike, hs, he, ok = 0.20, 0.27, 0.30, 0.42, 0.62

    def sample(t: float) -> QuadPose:
        feet = stand(solver)
        draw = smooth(t / cocked) * (1.0 - smooth((t - cocked) / (strike - cocked)))
        go = smooth((t - cocked) / (hs - cocked)) * (1.0 - smooth((t - he) / (length - he)))
        qp = QuadPose(feet=feet)
        qp.lift = -0.05 * k * draw - 0.02 * k * go
        qp.ahead = -0.04 * k * draw + reach * k * go
        qp.pitch = 3.0 * draw - 4.0 * go
        qp.neck = -6.0 * draw + 18.0 * go
        qp.head = -10.0 * draw - 16.0 * go
        open_ = smooth((t - 0.10) / (cocked - 0.10)) * (1.0 - smooth((t - hs + 0.02) / 0.05))
        qp.jaw = 8.0 + 34.0 * open_
        shake_t = (t - he) / 0.18
        qp.neck_turn = shake * math.sin(2 * math.pi * shake_t * 1.5) * bump(shake_t) if 0.0 < shake_t < 1.0 else 0.0
        qp.ears = (K.ears_back, K.ears_back)
        qp.tail = K.tail_carriage + 6.0 * go
        # the near forefoot steps in with the thrust
        step = smooth((t - cocked) / 0.1) * (1.0 - smooth((t - he - 0.1) / 0.2))
        lift = bump(min(1.0, max(0.0, (t - cocked) / 0.1))) if t < cocked + 0.1 else 0.0
        feet["FL"].toe[1] -= 0.10 * k * step
        feet["FL"].toe[2] += 0.04 * k * lift
        feet["FL"].planted = lift < 0.05
        return qp
    return QuadClip(name, length, False, sample,
                    [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")], {})


def lunge_clip(solver, K: Kind, name: str = "Attack_2", length: float = 1.15, height: float = 0.12,
               rear: float = 11.0) -> QuadClip:
    """The spring: a long crouch, the hind legs gathered under and the forehand flat to the ground;
    then up and forward off the hind legs, the forelegs reaching, the jaws wide -- they shut on
    `hit_start` at the top -- and down on to the forefeet and back to standing."""
    k = K.k
    sk = solver.skel
    hip = sk.bones["Thigh.L"].head.copy()
    hip[0] = 0.0
    cocked, strike, hs, he, ok = 0.38, 0.44, 0.52, 0.64, 0.86
    land = 0.72

    def sample(t: float) -> QuadPose:
        feet = stand(solver)
        crouch = smooth(t / cocked) * (1.0 - smooth((t - cocked) / 0.08))
        air = smooth((t - cocked) / (hs - cocked)) * (1.0 - smooth((t - hs) / (land - hs)))
        reach = smooth((t - cocked) / (hs - cocked)) * (1.0 - smooth((t - land) / (length - land)))
        qp = QuadPose(feet=feet)
        qp.pivot = hip
        qp.lift = -0.09 * k * crouch + height * k * air
        qp.ahead = -0.05 * k * crouch + 0.26 * k * reach
        qp.pitch = -7.0 * crouch + rear * air
        qp.loin = 6.0 * crouch - 6.0 * air
        qp.neck = 10.0 * crouch - 8.0 * air
        qp.head = -12.0 * crouch + 6.0 * air
        open_ = smooth((t - cocked + 0.06) / 0.1) * (1.0 - smooth((t - hs + 0.01) / 0.06))
        qp.jaw = 6.0 + 40.0 * open_
        qp.ears = (K.ears_back, K.ears_back)
        qp.tail = K.tail_carriage + 14.0 * air
        for f in ("HL", "HR"):
            feet[f].toe[1] -= 0.08 * k * crouch
            feet[f].pastern += 14.0 * crouch
        # the forefeet leave the ground and reach forward and up, in the body's own frame, and land ahead
        if air > 0.01:
            Rt, xf = trunk_xf(solver, qp)
            for f in ("FL", "FR"):
                r = solver.rest[f]
                toe_b = r.toe + np.array([0.0, -0.24 * k * air, 0.20 * k * air])
                st_ = as_free(solver, f, feet[f])
                fwd = np.array([0.0, -1.0, -0.6])
                reach_ = free_foot(xf(toe_b), Rt @ _u(fwd), Rt @ _u(fwd), Rt @ _u(np.array([0.0, -0.5, -1.0])),
                                   default_pole(f))
                w = smooth(air * 1.4)
                feet[f] = free_foot(_lerp(st_.toe, reach_.toe, w), _lerp(st_.hoof, reach_.hoof, w),
                                    _lerp(st_.pastern, reach_.pastern, w), _lerp(st_.cannon, reach_.cannon, w),
                                    default_pole(f))
        elif reach > 0.0:
            for f in ("FL", "FR"):
                feet[f].toe[1] -= 0.12 * k * reach
        return qp
    return QuadClip(name, length, False, sample,
                    [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (land, "land"),
                     (ok, "cancel_ok")], {})


def gore_clip(solver, K: Kind, name: str = "Attack_1", length: float = 0.95) -> QuadClip:
    """The gore: the head dropped low between the forelegs, the snout near the ground, then a short
    rush and the head flung up and to the side, the tusks ripping upward through `hit_start`."""
    k = K.k
    cocked, strike, hs, he, ok = 0.30, 0.36, 0.42, 0.56, 0.72

    def sample(t: float) -> QuadPose:
        feet = stand(solver)
        low = smooth(t / cocked) * (1.0 - smooth((t - cocked) / (hs - cocked)))
        toss = bump((t - cocked) / (length - cocked), 0.25) if t > cocked else 0.0
        qp = QuadPose(feet=feet)
        qp.lift = -0.05 * k * low
        qp.ahead = -0.03 * k * low + 0.04 * k * toss
        qp.pitch = -6.0 * low + 3.0 * toss
        qp.lift = qp.lift - 0.02 * k * toss
        qp.neck = 20.0 * low - 14.0 * toss
        qp.head = 10.0 * low - 18.0 * toss
        qp.neck_turn = 18.0 * toss
        qp.head_turn = 12.0 * toss
        qp.ears = (K.ears_back, K.ears_back)
        qp.tail = K.tail_carriage + 10.0 * toss
        qp.jaw = 10.0 * toss
        return qp
    return QuadClip(name, length, False, sample,
                    [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")], {})


def charge_clip(solver, K: Kind, name: str = "Attack_2", length: float = 1.2) -> QuadClip:
    """The charge's wind-up and its blow: a forefoot scraping the ground twice with the head down and
    the back humped, then off -- the game runs it at the foe -- and the tusks hooked up at the end."""
    k = K.k
    cocked, strike, hs, he, ok = 0.62, 0.7, 0.78, 0.94, 1.06

    def sample(t: float) -> QuadPose:
        feet = stand(solver)
        set_ = smooth(t / 0.25) * (1.0 - smooth((t - cocked) / (hs - cocked)))
        toss = bump((t - cocked) / (length - cocked), 0.3) if t > cocked else 0.0
        qp = QuadPose(feet=feet)
        qp.lift = -0.05 * k * set_
        qp.loin = 8.0 * set_
        qp.pitch = -5.0 * set_ + 10.0 * toss
        qp.ahead = 0.08 * k * toss
        qp.neck = 18.0 * set_ - 14.0 * toss
        qp.head = 10.0 * set_ - 18.0 * toss
        qp.neck_turn = 20.0 * toss
        qp.ears = (K.ears_back, K.ears_back)
        qp.tail = K.tail_carriage + 25.0 * set_
        # the scrape: the near forefoot raked back along the ground, twice
        for c0 in (0.08, 0.32):
            w = (t - c0) / 0.22
            if 0.0 < w < 1.0:
                feet["FL"].toe[1] += 0.14 * k * math.sin(math.pi * w)
                feet["FL"].toe[2] += 0.05 * k * bump(w, 0.3) * (1.0 if w < 0.4 else 0.0)
                feet["FL"].planted = w > 0.4
        return qp
    return QuadClip(name, length, False, sample,
                    [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok"),
                     (0.15, "scrape"), (0.39, "scrape")], {})


def reptile_gaits(K: Kind) -> List[GaitSpec]:
    """A reptile's walk is a slow diagonal trot with the body swung from side to side; its run the
    same, quicker, the belly carried higher. Short legs make short strides: the cadence carries it."""
    k = K.k
    sp = {"Walk": 0.8, "Trot": 1.4, "Run": 3.2}
    sp.update(K.speeds)
    cy = {"Walk": 20, "Trot": 14, "Run": 8, "Walk_Back": 22, "Turn": 26}
    cy.update(K.cycles)
    tn = K.turn
    return [
        GaitSpec("Walk", speed=sp["Walk"] * k ** 0.5, cycle=cy["Walk"] / FPS, duty=0.7,
                 footfalls={"HL": 0.0, "FR": 0.05, "HR": 0.5, "FL": 0.55},
                 lift=0.05 * k, fold=0.4, bob=0.006 * k, bobs=2, nod=2.0, carriage=0.0, ears=0.0),
        GaitSpec("Trot", speed=sp["Trot"] * k ** 0.5, cycle=cy["Trot"] / FPS, duty=0.55,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.07 * k, fold=0.6, bob=0.012 * k, bobs=2, nod=2.0, carriage=-2.0, ears=0.0),
        GaitSpec("Run", speed=sp["Run"] * k ** 0.5, cycle=cy["Run"] / FPS, duty=0.45,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.09 * k, fold=0.8, bob=0.02 * k, bobs=2, nod=3.0, carriage=-4.0, ears=0.0),
        GaitSpec("Walk_Back", speed=-0.5 * k ** 0.5, cycle=cy["Walk_Back"] / FPS, duty=0.7,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.04 * k, fold=0.4, bob=0.005 * k, bobs=2, nod=2.0, ears=0.0),
        GaitSpec("Turn_L90", speed=0.0, cycle=cy["Turn"] / FPS, duty=0.65,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}, lift=0.04 * k, fold=0.4, bob=0.004 * k,
                 nod=2.0, turn=tn),
        GaitSpec("Turn_R90", speed=0.0, cycle=cy["Turn"] / FPS, duty=0.65,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}, lift=0.04 * k, fold=0.4, bob=0.004 * k,
                 nod=2.0, turn=-tn),
    ]


def undulating(clip: QuadClip, sway: float) -> QuadClip:
    """The body swung from side to side with the stride, the head held to its line and the tail
    whipping the other way: how a lizard walks."""
    cyc = clip.length

    def sample(t: float) -> QuadPose:
        qp = clip.sample(t)
        ph = (t / cyc) % 1.0
        w = math.sin(2 * math.pi * ph)
        qp.bend += sway * w
        qp.yaw += -0.3 * sway * w
        qp.neck_turn += -0.6 * sway * w
        qp.tail_swing += -1.6 * sway * math.sin(2 * math.pi * (ph - 0.12))
        return qp
    return QuadClip(clip.name, clip.length, clip.loop, sample, clip.events, clip.extra)


def death_roll_clip(solver, K: Kind, name: str = "Attack_2", length: float = 2.0) -> QuadClip:
    """The death roll: the jaws snap shut on you and the whole body spins over along its length,
    once, legs tucked, the tail flailing; then it rights itself. The blow is the bite (`hit_start`)."""
    k = K.k
    cocked, hs, he, ok = 0.40, 0.52, 0.76, 1.5

    def sample(t: float) -> QuadPose:
        u = t / length
        lunge = smooth(t / cocked) * (1.0 - smooth((t - hs) / 0.3))
        spin = smooth((t - hs) / (1.25 - hs))
        qp = QuadPose(feet=stand(solver))
        qp.ahead = 0.15 * k * lunge
        qp.lift = -0.03 * k * lunge
        qp.jaw = 30.0 * smooth((t - 0.1) / (cocked - 0.1)) * (1.0 - smooth((t - hs + 0.03) / 0.05))
        qp.neck = -8.0 * lunge
        if spin > 0.0:
            # rolled about its own length, the trunk's middle on the ground's line
            rot = 360.0 * spin
            mid_z = 0.5 * (solver.skel.J["Chest"][2] + solver.skel.J["Forearm.L"][2])
            qp.pivot = np.array([0.0, solver.skel.bones["Hips"].head[1], mid_z])
            qp.roll = -rot
            qp.lift += 0.06 * k * math.sin(math.pi * spin)
            Rt, xf = trunk_xf(solver, qp)
            for f in FEET:
                r = solver.rest[f]
                tucked = r.toe + np.array([-0.5 * r.toe[0], 0.0, 0.12 * k])
                w = math.sin(math.pi * spin)
                toe_b = r.toe * (1.0 - w) + tucked * w
                qp.feet[f] = free_foot(xf(toe_b), Rt @ sag(r.hoof), Rt @ sag(r.pastern), Rt @ sag(solver._rest_cannon[f]),
                                       Rt @ default_pole(f))
            qp.tail_swing = 40.0 * math.sin(2 * math.pi * spin * 2)
        return qp
    return QuadClip(name, length, False, sample,
                    [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")], {})


def scrabble_clip(solver, K: Kind, name: str = "Attack_2", length: float = 0.95) -> QuadClip:
    """The drake's scrabble: up on its hind legs and on to you, the forefeet raking down at
    `hit_start`, the jaws open."""
    k = K.k
    sk = solver.skel
    hip = sk.bones["Thigh.L"].head.copy()
    hip[0] = 0.0
    cocked, hs, he, ok = 0.34, 0.48, 0.6, 0.76

    def sample(t: float) -> QuadPose:
        up = smooth(t / cocked) * (1.0 - smooth((t - hs) / (length - hs)))
        rake = smooth((t - cocked) / (hs - cocked)) * (1.0 - smooth((t - he) / 0.2))
        feet = stand(solver)
        qp = QuadPose(feet=feet)
        qp.pivot = hip
        qp.pitch = 35.0 * up - 15.0 * rake
        qp.ahead = 0.12 * k * rake
        qp.jaw = 25.0 * up
        qp.neck = -10.0 * up
        qp.tail = -10.0 * up
        Rt, xf = trunk_xf(solver, qp)
        if up > 0.02:
            for f in ("FL", "FR"):
                r = solver.rest[f]
                claw = r.toe + np.array([0.0, -0.08 * k - 0.1 * k * rake, 0.12 * k * (1.0 - rake)])
                st_ = as_free(solver, f, feet[f])
                fr = free_foot(xf(claw), Rt @ np.array([0.0, -0.4, -1.0]), Rt @ np.array([0.0, -0.6, -1.0]),
                               Rt @ np.array([0.0, -0.3, -1.0]), Rt @ default_pole(f))
                w = smooth(up * 1.6)
                feet[f] = free_foot(_lerp(st_.toe, fr.toe, w), _lerp(st_.hoof, fr.hoof, w), _lerp(st_.pastern, fr.pastern, w),
                                    _lerp(st_.cannon, fr.cannon, w), default_pole(f))
        return qp
    return QuadClip(name, length, False, sample, [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")], {})


def rise_clip(solver, K: Kind, lurk: QuadClip, length: float = 0.5) -> QuadClip:
    """From the belly up on to its legs in one heave, the jaws opening: an ambusher roused."""
    def sample(t: float) -> QuadPose:
        w = smooth(t / length)
        qp = blend_pose(lurk.sample(0.0), standing_pose(solver, K), w, solver)
        qp.jaw = 25.0 * bump(t / length, 0.6)
        qp.ahead += 0.08 * K.k * bump(t / length)
        return qp
    return QuadClip("Rise", length, False, sample, [(0.8 * length, "cancel_ok")], {})


def lurk_clip(solver, K: Kind, length: float = 4.0) -> QuadClip:
    """Flat on its belly, still as a log: the sallowjaw's wait (and every reptile's rest)."""
    sk = solver.skel

    def sample(t: float) -> QuadPose:
        u = t / length
        qp = QuadPose()
        qp.lift = -(sk.J["Forearm.L"][2] - 0.02 * K.k) * 0.75
        Rt, xf = trunk_xf(solver, qp)
        feet = {}
        for f in FEET:
            r = solver.rest[f]
            out = np.array([np.sign(r.toe[0]) * 0.06 * K.k, 0.0, 0.0])
            feet[f] = free_foot(r.toe + out, sag(r.hoof + 20.0), sag(r.pastern + 30.0), sag(solver._rest_cannon[f] + 50.0),
                                np.array([np.sign(r.toe[0]) * 1.2, 1.0 if f[0] == "F" else -1.0, 0.3]))
        qp.feet = feet
        qp.tail_swing = 3.0 * math.sin(2 * math.pi * u)
        qp.jaw = 2.0
        return qp
    return QuadClip("Idle", length, True, sample, [], {})


# --------------------------------------------------------------------------------------
# Struck, thrown, killed
# --------------------------------------------------------------------------------------

def flinch_clip(solver, K: Kind) -> QuadClip:
    base = hit_clip(solver, 0.45)

    def sample(t: float) -> QuadPose:
        qp = base.sample(t)
        qp.tail = K.tail_carriage - 15.0 * bump(t / 0.45, 0.22) if K.family == "canid" else qp.tail
        qp.jaw = 18.0 * bump(t / 0.45, 0.2)
        return qp
    return QuadClip("Hit", 0.45, False, sample, [(0.01, "hit_react"), (0.3, "cancel_ok")], {})


def stagger_clip(solver, K: Kind, length: float = 0.9) -> QuadClip:
    """Rocked off its footing: thrown back and to one side, a hind foot and a forefoot stepping
    wide to catch it, the head shaken; then square again."""
    k = K.k

    def sample(t: float) -> QuadPose:
        u = t / length
        hit = bump(u, 0.18)
        wob = math.sin(2 * math.pi * u * 2.0) * (1.0 - smooth(u))
        feet = stand(solver)
        qp = QuadPose(feet=feet)
        qp.ahead = -0.08 * k * hit
        qp.side = -0.05 * k * hit
        qp.lift = -0.05 * k * hit
        qp.roll = -9.0 * hit + 4.0 * wob
        qp.pitch = 6.0 * hit
        qp.yaw = 8.0 * hit
        qp.neck = -14.0 * hit + 6.0 * wob
        qp.neck_turn = 18.0 * wob
        qp.head = -10.0 * hit
        qp.jaw = 16.0 * hit
        qp.ears = (K.ears_back * hit + 10.0, K.ears_back * hit + 10.0)
        qp.tail = K.tail_carriage - 10.0 * hit
        for f, w0, dx, dy in (("HR", 0.12, -0.08, 0.06), ("FR", 0.30, -0.06, -0.02)):
            w = (u - w0) / 0.22
            if 0.0 < w < 1.0:
                feet[f].toe[2] += 0.05 * k * bump(w)
                feet[f].planted = False
            sh = smooth(w)
            back = smooth((u - 0.65) / 0.3)
            feet[f].toe[0] += dx * k * sh * (1.0 - back)
            feet[f].toe[1] += dy * k * sh * (1.0 - back)
        return qp
    return QuadClip("Stagger", length, False, sample, [(0.01, "hit_react"), (0.7, "cancel_ok")], {})


def lying_pose(solver, K: Kind, kick: float = 0.0, head_down: float = 1.0, limp: float = 0.0) -> QuadPose:
    """On its side on the ground, the legs out from the body and a little bent; `kick` paddles them,
    `limp` lets them out straight and slack (dead)."""
    sk = solver.skel
    k = K.k
    side = K.lie_side
    qp = QuadPose()
    hips = sk.bones["Hips"].head
    mid_z = 0.5 * (sk.J["Chest"][2] + sk.J["Forearm.L"][2])
    qp.pivot = np.array([0.0, hips[1], mid_z])
    qp.roll = -side * K.lie_roll
    qp.lift = -(mid_z - K.lie_height * k)
    qp.side = -side * 0.02 * k
    Rt, xf = trunk_xf(solver, qp)
    feet = {}
    for f in FEET:
        r = solver.rest[f]
        fore = f[0] == "F"
        phase = {"FL": 0.0, "FR": 0.5, "HL": 0.25, "HR": 0.75}[f]
        paddle = kick * math.sin(2 * math.pi * phase)
        reach = (-0.10 if fore else 0.08) * k * (1.0 - limp) + (-0.05 if fore else 0.10) * k * limp
        toe_b = r.toe + np.array([0.0, reach + paddle * 0.06 * k, (0.06 * (1.0 - limp) + 0.02) * k])
        # the upper legs lie over the lower ones
        if (f[1] == "L") == (side > 0):
            toe_b = toe_b + np.array([-side * 0.0, 0.0, 0.03 * k])
        hoof = sag(r.hoof + 35.0 * (1.0 - limp) + 10.0 * limp)
        past = sag(r.pastern + 25.0 * (1.0 - limp))
        can = sag(solver._rest_cannon[f] + (-12.0 if fore else 18.0) * (1.0 - limp))
        feet[f] = free_foot(xf(toe_b), Rt @ hoof, Rt @ past, Rt @ can, Rt @ default_pole(f))
    qp.feet = feet
    # the head: along the ground, the neck turned down (the body's right is the world's down)
    qp.neck = -10.0
    qp.neck_turn = -side * 22.0 * head_down
    qp.head_turn = -side * 14.0 * head_down
    qp.head = -6.0
    qp.tail = K.tail_carriage
    qp.tail_swing = -side * 20.0
    return qp


def sternal_pose(solver, K: Kind) -> QuadPose:
    """Down on its brisket, the forelegs out in front along the ground, the hind legs folded
    under: the half-way pose of getting up."""
    sk = solver.skel
    k = K.k
    qp = QuadPose()
    hips = sk.bones["Hips"].head
    qp.lift = -(hips[2] - K.sternal * k)
    qp.pitch = 2.0
    feet = {}
    for f in FEET:
        r = solver.rest[f]
        fore = f[0] == "F"
        b = foot_bones(f)
        ln = sum(sk.bones[n].length for n in b[-3:])
        if fore:
            toe = np.array([r.toe[0], r.toe[1] - 0.20 * k, 0.0])
            d = np.array([0.0, -1.0, -0.12])
            feet[f] = free_foot(toe, d, d, np.array([0.0, -1.0, -0.25]), default_pole(f))
        else:
            hip = sk.bones[b[0]].head
            toe = np.array([r.toe[0] * 1.15, hip[1] - 0.10 * k, 0.0])
            d = np.array([0.0, -1.0, -0.15])
            feet[f] = free_foot(toe, d, d, np.array([0.0, -1.0, -0.1]), np.array([0.0, -1.0, 0.4]))
        del ln
    qp.feet = feet
    qp.neck = 0.0
    qp.head = 0.0
    qp.tail = K.tail_carriage - 10.0
    return qp


def standing_pose(solver, K: Kind) -> QuadPose:
    qp = QuadPose(feet=stand(solver))
    qp.tail = K.tail_carriage
    return qp


def knockdown_clip(solver, K: Kind, length: float = 1.6) -> QuadClip:
    """Bowled over: thrown on to its side in the first third, legs paddling to find the ground,
    the head lifting to look; the last frame held until Get_Up."""
    fall = 0.45

    def sample(t: float) -> QuadPose:
        u = t / length
        kick = 0.8 * (1.0 - smooth((u - 0.4) / 0.5)) * math.sin(2 * math.pi * t * 2.2)
        lie = lying_pose(solver, K, kick=kick, head_down=0.4 + 0.6 * smooth((u - 0.5) / 0.4))
        w = smooth(t / fall)
        qp = blend_pose(standing_pose(solver, K), lie, w, solver)
        # thrown: the body is lifted a little off its feet on the way over
        qp.lift += 0.06 * K.k * bump(t / fall, 0.35)
        qp.jaw = 20.0 * bump(u, 0.2)
        qp.ears = (K.ears_back, K.ears_back)
        return qp
    return QuadClip("Knockdown", length, False, sample, [(0.02, "hit_react"), (fall, "body_land")], {"held": True})


def get_up_clip(solver, K: Kind, length: float = 0.8) -> QuadClip:
    """From its side to its brisket, and up: forelegs first, then the quarters."""
    def sample(t: float) -> QuadPose:
        u = t / length
        a = smooth(u / 0.45)
        b = smooth((u - 0.4) / 0.6)
        lie = lying_pose(solver, K, head_down=0.3)
        st = sternal_pose(solver, K)
        qp = blend_pose(lie, st, a, solver)
        # rolling up off the side, the body is lifted clear of the ground it lay on
        qp.lift += 0.07 * K.k * bump(a, 0.5)
        if b > 0:
            qp = blend_pose(qp, standing_pose(solver, K), b, solver)
        qp.ears = (K.ears_back * (1.0 - b), K.ears_back * (1.0 - b))
        return qp
    return QuadClip("Get_Up", length, False, sample, [(0.6 * length, "cancel_ok")], {})


def death_clip(solver, K: Kind, length: float = 2.0) -> QuadClip:
    """Killed: the hind legs go first, it sits back and sags, and goes over on its side; a last
    stretch of the legs and the head let down along the ground. The last frame is held."""
    def sample(t: float) -> QuadPose:
        u = t / length
        sag_k = smooth(u / 0.3)
        over = smooth((u - 0.22) / 0.33)
        limp = smooth((u - 0.55) / 0.35)
        kick = 0.5 * bump((u - 0.55) / 0.3) if 0.55 < u < 0.85 else 0.0
        st = standing_pose(solver, K)
        st.lift -= 0.12 * K.k * sag_k
        st.pitch = 6.0 * sag_k
        st.neck = 10.0 * sag_k
        st.head = 8.0 * sag_k
        for f in ("HL", "HR"):
            st.feet[f].toe[1] -= 0.08 * K.k * sag_k
            st.feet[f].pastern += 20.0 * sag_k
        lie = lying_pose(solver, K, kick=kick, head_down=0.5 + 0.5 * limp, limp=limp)
        qp = blend_pose(st, lie, over, solver)
        qp.jaw = 14.0 * smooth((u - 0.5) / 0.3)
        qp.ears = (K.ears_back * 0.6, K.ears_back * 0.6)
        return qp
    return QuadClip("Death", length, False, sample, [(0.02, "death_start"), (0.55 * length, "body_land")], {"held": True})


# --------------------------------------------------------------------------------------
# A foe's whole set
# --------------------------------------------------------------------------------------

def kind_for(spec) -> Kind:
    st = spec.style
    if spec.family == "canid":
        return Kind(spec.skel, "canid", tail_carriage=-8.0 if getattr(st, "kind", "") != "thorn" else 10.0)
    return Kind(spec.skel, spec.family, **spec.extra.get("kind", {}))


def build(spec) -> Dict[str, QuadClip]:
    """Every clip of this foe, by name."""
    solver = solver_for(spec)
    K = kind_for(spec)
    clips: Dict[str, QuadClip] = {}
    gaits = reptile_gaits(K) if spec.family == "reptile" else canid_gaits(K)
    for g in gaits:
        clips[g.name] = gait_clip(solver, g)
        if spec.family == "reptile" and not g.turn:
            clips[g.name] = undulating(clips[g.name], 14.0 if g.name != "Run" else 9.0)
    walk = [g for g in gaits if g.name == "Walk"][0]
    side_walk = GaitSpec("Strafe", speed=walk.speed * 0.8, cycle=walk.cycle, duty=walk.duty, footfalls=walk.footfalls,
                         lift=walk.lift, fold=walk.fold, bob=walk.bob, nod=2.0, carriage=10.0, tail=walk.tail, ears=15.0)
    clips["Strafe_L"] = strafe_clip(solver, side_walk, "Strafe_L", 1.0)
    clips["Strafe_R"] = strafe_clip(solver, side_walk, "Strafe_R", -1.0)
    clips["Idle"] = idle_clip(solver, K)
    clips["Idle_Combat"] = combat_idle_clip(solver, K)
    if spec.family == "boar":
        clips["Attack_1"] = gore_clip(solver, K)
        clips["Attack_2"] = charge_clip(solver, K)
    elif spec.family == "reptile":
        clips["Attack_1"] = bite_clip(solver, K, reach=0.18, shake=6.0)
        clips["Attack_2"] = death_roll_clip(solver, K) if spec.style.kind == "croc" else scrabble_clip(solver, K)
        if spec.style.kind == "croc":
            # it waits flat as a log; Idle_Combat is its high stance; Rise is the log coming alive
            clips["Idle"] = lurk_clip(solver, K)
            clips["Rise"] = rise_clip(solver, K, clips["Idle"])
    else:
        clips["Attack_1"] = bite_clip(solver, K)
        clips["Attack_2"] = lunge_clip(solver, K)
    clips["Hit"] = flinch_clip(solver, K)
    clips["Stagger"] = stagger_clip(solver, K)
    clips["Knockdown"] = knockdown_clip(solver, K)
    clips["Get_Up"] = get_up_clip(solver, K)
    clips["Death"] = death_clip(solver, K)
    for name, fn in spec.extra.get("clips", {}).items():
        clips[name] = fn(solver, K)
    return clips


def solver_for(spec) -> FoeSolver:
    s = make_solver(spec.skel)
    s.splay = float(spec.extra.get("splay", 0.0))
    return s


# --------------------------------------------------------------------------------------
# Previews without Blender: segment weights and linear blend skinning
# --------------------------------------------------------------------------------------

def mesh_weights(spec, verts: np.ndarray) -> np.ndarray:
    from . import body as bodylib
    return bodylib.segment_weights(verts, spec.skel, DEFORM_NAMES, sharpness=2.6)


def pose_matrices(spec, clip: QuadClip, t: float, solver=None) -> Dict[str, np.ndarray]:
    solver = solver or solver_for(spec)
    R, th = solver.solve(clip.sample(t))
    pose = {n: (r, th if n == "Hips" else None) for n, r in R.items()}
    return spec.skel.fk(pose)


def pose_mesh(spec, clip: QuadClip, t: float, verts: np.ndarray, W: np.ndarray) -> np.ndarray:
    sk = spec.skel
    Wm = pose_matrices(spec, clip, t)
    out = np.zeros_like(verts)
    vh = np.concatenate([verts, np.ones((len(verts), 1))], axis=1)
    for i, b in enumerate(DEFORM_NAMES):
        w = W[:, i]
        if not np.any(w > 1e-4):
            continue
        M = Wm[b] @ np.linalg.inv(sk.bones[b].rest)
        out += w[:, None] * (vh @ M.T)[:, :3]
    return out
