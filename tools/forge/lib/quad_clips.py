"""The clips of WM_Quadruped_v1 (docs/CONTRACTS.md §3b): gaits from footfall timings, and the
mount's other clips, on any hoofed beast's skeleton.

Pure Python and numpy. A clip is a function of time returning a `QuadPose` -- the trunk's rise
and rocking, the spine's bend, the neck's and head's carriage, the tail, the ears, and for each
hoof where its toe is and how far its hoof, pastern and cannon are turned -- and `solve` turns a
QuadPose into bone-local rotations: the axial chain by turns about its joints, each leg from the
toe up (hoof, pastern, cannon by angle; the two bones above the knee or hock by two-bone IK from
the shoulder or hip), the scapula swinging with its leg.

Angles in a leg's side plane are measured from straight down, positive with the lower end
forward (`sag`): a cannon at 0 stands plumb, a hoof at 45° has its toe ahead of its coronet, and
a folded hoof in the swing, sole to the sky, is near -120°.

`GaitSpec` is the whole of a gait: its speed, its cycle, the share of it each hoof is down, the
phase at which each lands (the hind left at 0, CONTRACTS §3b), and how the trunk, head and legs
move with it. `gait_clip` makes a looping clip from one. A clip made at the speed in its spec
leaves every planted toe standing still on the ground (`toe_slip` measures it).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from .anim import BakedClip, FPS
from .rig import rot_axis, mat_to_quat, UP, LEFT, FWD
from .quadruped import QuadSkeleton, QuadProportions, FEET, foot_bones, DEFORM_NAMES

AXIAL = ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "Ear.L", "Ear.R",
         "Tail1", "Tail2", "Tail3"]


def sag(theta_deg: float) -> np.ndarray:
    """A unit direction in the side plane, `theta` from straight down, + with its end forward."""
    t = math.radians(theta_deg)
    return np.array([0.0, -math.sin(t), -math.cos(t)])


def sag_angle(v: np.ndarray) -> float:
    return math.degrees(math.atan2(-float(v[1]), -float(v[2])))


def pitch_up(deg: float) -> np.ndarray:
    """A turn raising the front (-Y) end, about the body's left axis."""
    return rot_axis(LEFT, math.radians(-deg))


def yaw_left(deg: float) -> np.ndarray:
    return rot_axis(UP, math.radians(deg))


def roll_left(deg: float) -> np.ndarray:
    """A turn dropping the left side (+X), about the body's forward axis."""
    return rot_axis(FWD, math.radians(-deg))


def smooth(x: float) -> float:
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def bump(x: float, peak: float = 0.5) -> float:
    """0 at 0 and 1, 1 at `peak`; smooth on both sides."""
    x = min(1.0, max(0.0, x))
    if x < peak:
        return math.sin(0.5 * math.pi * x / peak) ** 2
    return math.sin(0.5 * math.pi * (1.0 - x) / (1.0 - peak)) ** 2


def wave(phase: float, per_cycle: float = 1.0, at: float = 0.0) -> float:
    """1 at phase `at` (and every 1/per_cycle after it), -1 halfway between."""
    return math.cos(2.0 * math.pi * per_cycle * (phase - at))


# --------------------------------------------------------------------------------------
# The pose, and turning it into bone rotations
# --------------------------------------------------------------------------------------

@dataclass
class FootPose:
    toe: np.ndarray                 # the toe's tip, armature space (the body's own frame)
    hoof: float                     # sag of coronet -> toe
    pastern: float                  # sag of fetlock -> coronet
    cannon: Optional[float] = None  # sag of knee/hock -> fetlock; None: the leg's column
    planted: bool = True            # on the ground and bearing weight


@dataclass
class QuadPose:
    lift: float = 0.0                       # the trunk's rise, m
    ahead: float = 0.0                      # the trunk's shift forward, m
    side: float = 0.0                       # the trunk's shift to the left, m
    pitch: float = 0.0                      # the trunk's front up, degrees, about `pivot`
    roll: float = 0.0                       # left side down, degrees
    yaw: float = 0.0                        # front to the left, degrees
    pivot: Optional[np.ndarray] = None      # what the trunk rocks about; the hips' head if None
    loin: float = 0.0                       # the back's arch (+ roaches up), degrees, over Spine1..Chest
    bend: float = 0.0                       # the back bent to the left, degrees
    neck: float = 0.0                       # the neck lowered, degrees (at Neck1 and Neck2)
    neck_turn: float = 0.0                  # the neck turned to the left, degrees
    head: float = 0.0                       # the head nodded down at the poll, degrees
    head_turn: float = 0.0
    jaw: float = 0.0                        # open, degrees
    ears: Tuple[float, float] = (0.0, 0.0)  # each ear laid back (+) or pricked forward (-), degrees
    ear_turn: Tuple[float, float] = (0.0, 0.0)  # each ear turned out, degrees
    tail: float = 0.0                       # the tail raised, degrees
    tail_swing: float = 0.0                 # the tail swung to the left, degrees
    feet: Dict[str, FootPose] = field(default_factory=dict)


def rest_feet(skel: QuadSkeleton) -> Dict[str, FootPose]:
    """Each hoof standing square where the rest pose has it."""
    out = {}
    W = skel.fk({})
    for f in FEET:
        bones = foot_bones(f)
        hoof, past, can = bones[-1], bones[-2], bones[-3]
        toe = skel.tail_world(W, hoof)
        out[f] = FootPose(toe=toe.copy(),
                          hoof=sag_angle(skel.bones[hoof].tail - skel.bones[hoof].head),
                          pastern=sag_angle(skel.bones[past].tail - skel.bones[past].head),
                          cannon=None)
    return out


class Solver:
    """Turns QuadPoses into bone-local rotations for one skeleton."""

    # how much of a foreleg's swing the scapula takes, turning about its top
    SCAPULA_SHARE = 0.5
    HIND_CANNON_SHARE = 0.6
    # where each pair's stance is centred, against its rest toe, as a share of the stance's length
    # (+ behind): a hind hoof lands near under the hip and pushes off well behind it
    HIND_BACK = 0.15
    FORE_BACK = 0.0
    # the pelvis tilts with the hind legs a little, about the lumbosacral joint
    def __init__(self, skel: QuadSkeleton):
        self.skel = skel
        self.rest = rest_feet(skel)
        W = skel.fk({})
        self._rest_line: Dict[str, float] = {}
        self._rest_cannon: Dict[str, float] = {}
        for f in FEET:
            bones = foot_bones(f)
            top = bones[0]
            fet = skel.bones[bones[-2]].head
            self._rest_line[f] = sag_angle(fet - skel.bones[top].head)
            can = bones[-3]
            self._rest_cannon[f] = sag_angle(skel.bones[can].tail - skel.bones[can].head)
        self.reach_error = 0.0      # the worst the IK fell short, over everything solved

    def solve(self, qp: QuadPose) -> Tuple[Dict[str, np.ndarray], np.ndarray]:
        sk = self.skel
        R: Dict[str, np.ndarray] = {}
        # the trunk: the hips carry everything; rocking is about `pivot`
        hb = sk.bones["Hips"]
        Rt = yaw_left(qp.yaw) @ pitch_up(qp.pitch) @ roll_left(qp.roll)
        pivot = hb.head if qp.pivot is None else np.asarray(qp.pivot, float)
        new_head = pivot + Rt @ (hb.head - pivot) + np.array([qp.side, -qp.ahead, qp.lift])
        R["Hips"] = sk.local_turn("Hips", Rt)
        t_hips = hb.rest[:3, :3].T @ (new_head - hb.head)
        # the back: the arch and the bend shared over its three joints
        for name, share in (("Spine1", 0.4), ("Spine2", 0.35), ("Chest", 0.25)):
            R[name] = sk.local_turn(name, yaw_left(qp.bend * share) @ pitch_up(qp.loin * share))
        R["Neck1"] = sk.local_turn("Neck1", yaw_left(qp.neck_turn * 0.55) @ pitch_up(-qp.neck * 0.6))
        R["Neck2"] = sk.local_turn("Neck2", yaw_left(qp.neck_turn * 0.45) @ pitch_up(-qp.neck * 0.4))
        R["Head"] = sk.local_turn("Head", yaw_left(qp.head_turn) @ pitch_up(-qp.head))
        R["Jaw"] = sk.local_turn("Jaw", pitch_up(-qp.jaw))
        for i, side in enumerate(("L", "R")):
            sx = 1.0 if side == "L" else -1.0
            R[f"Ear.{side}"] = sk.local_turn(f"Ear.{side}", yaw_left(sx * qp.ear_turn[i]) @ pitch_up(-qp.ears[i]))
        # the tail: raised at its root, swung along its length
        R["Tail1"] = sk.local_turn("Tail1", yaw_left(qp.tail_swing * 0.3) @ pitch_up(qp.tail * 0.7))
        R["Tail2"] = sk.local_turn("Tail2", yaw_left(qp.tail_swing * 0.35) @ pitch_up(qp.tail * 0.3))
        R["Tail3"] = sk.local_turn("Tail3", yaw_left(qp.tail_swing * 0.35))
        pose = {n: (r, None) for n, r in R.items()}
        pose["Hips"] = (R["Hips"], t_hips)
        feet = dict(self.rest)
        feet.update(qp.feet)
        for f in FEET:
            self._leg(pose, f, feet[f])
        return {n: pose[n][0] for n in pose}, t_hips

    def _leg(self, pose: dict, foot: str, fp: FootPose) -> None:
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
        top_at = W[top][:3, 3]
        line = sag_angle(F - top_at)
        if fore:
            # the scapula swings with its leg, about its top
            d = (line - self._rest_line[foot]) * self.SCAPULA_SHARE
            pose[top] = (sk.local_turn(top, pitch_up(d)), None)
            W = sk.fk(pose)
        # a foreleg in stance is a locked column, knee straight; the hind cannon turns with its
        # column by only part, the hock taking the rest
        share = 1.0 if fore else self.HIND_CANNON_SHARE
        cannon = fp.cannon if fp.cannon is not None else self._rest_cannon[foot] + share * (line - self._rest_line[foot])
        K = F - sk.bones[can].length * sag(cannon)
        K[0] = x + (sk.bones[can].head[0] - sk.bones[can].tail[0])
        pole = np.array([0.0, 1.0, 0.0]) if fore else np.array([0.0, -1.0, 0.0])   # elbow back, stifle forward
        Ru, Rl, err = sk.two_bone(W, up, lo, K, pole)
        self.reach_error = max(self.reach_error, err)
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


# --------------------------------------------------------------------------------------
# Clips
# --------------------------------------------------------------------------------------

@dataclass
class QuadClip:
    name: str
    length: float
    loop: bool
    sample: Callable[[float], QuadPose]
    events: List[Tuple[float, str]] = field(default_factory=list)
    extra: dict = field(default_factory=dict)

    def bake(self, solver: Solver, fps: int = FPS) -> BakedClip:
        n = int(round(self.length * fps)) + (0 if self.loop else 1)
        bones = [b for b in DEFORM_NAMES]
        quats = {b: np.zeros((n, 4)) for b in bones}
        hips = np.zeros((n, 3))
        prev: Dict[str, np.ndarray] = {}
        for i in range(n):
            t = min(i / fps, self.length)
            R, th = solver.solve(self.sample(t))
            for b in bones:
                q = mat_to_quat(R[b]) if b in R else np.array([1.0, 0.0, 0.0, 0.0])
                # keep each track on one side of the sphere so the keys interpolate the short way
                if b in prev and float(np.dot(prev[b], q)) < 0.0:
                    q = -q
                prev[b] = q
                quats[b][i] = q
            hips[i] = th
        return BakedClip(name=self.name, length=self.length, loop=self.loop, fps=fps,
                         events=list(self.events), bones=bones, quats=quats, hips_pos=hips,
                         extra=dict(self.extra))


@dataclass
class GaitSpec:
    name: str
    speed: float                    # m/s; negative backs
    cycle: float                    # s, a whole number of frames
    duty: float                     # the share of the cycle each hoof is down
    footfalls: Dict[str, float]     # phase of each landing; HL at 0
    lift: float = 0.10              # the toe's height at the top of its swing, m (fore; hind 0.8x)
    fold: float = 0.5               # how far the knee and hock fold in the swing, 0..1
    bob: float = 0.02               # the trunk's rise and fall, m
    bobs: int = 2                   # rises per cycle
    bob_at: float = 0.0             # phase of the first low point
    pitch: float = 0.0              # the trunk's rocking, degrees
    pitch_at: float = 0.0           # phase at which the front is highest
    nod: float = 4.0                # the head's nod, degrees
    nods: int = 2
    nod_at: float = 0.0             # phase of the head's lowest point
    flex: float = 0.0               # the loin's bend, degrees
    flex_at: float = 0.0            # phase of the back's greatest arch
    roll: float = 0.0               # the trunk's sway side to side, degrees
    carriage: float = 0.0           # the neck lowered (+) or raised (-) against rest, degrees
    tail: float = 0.0               # the tail's carriage, degrees
    ears: float = -6.0              # pricked forward
    reach: float = 0.0              # the fore toes land this far ahead of their rest, m
    tuck: float = 0.0               # the hind toes land this far ahead of theirs, m
    turn: float = 0.0               # degrees one cycle turns the body (turns on the spot)


def _stance(phase: float, land: float, duty: float) -> Tuple[bool, float]:
    """(down?, progress 0..1 through the stance or the swing) for a hoof landing at `land`."""
    u = (phase - land) % 1.0
    if u < duty:
        return True, u / duty
    return False, (u - duty) / (1.0 - duty)


def gait_pose(solver: Solver, g: GaitSpec, phase: float) -> QuadPose:
    rest = solver.rest
    stride = g.speed * g.cycle                  # ground covered per cycle
    stance_len = stride * g.duty                # how far a planted hoof travels, body-relative
    qp = QuadPose()
    feet: Dict[str, FootPose] = {}
    centre = np.array([0.0, 0.08 * solver.skel.props.withers / 1.5, 0.0])
    for f in FEET:
        r = rest[f]
        fore = f[0] == "F"
        down, w = _stance(phase, g.footfalls[f], g.duty)
        land_off = -(g.reach if fore else g.tuck)          # toward -Y is forward
        lift = g.lift * (1.0 if fore else 0.8)
        base = r.toe.copy()
        base[1] += land_off * 0.5 + stance_len * (solver.FORE_BACK if fore else solver.HIND_BACK)
        if g.turn:
            # on the spot: a planted hoof goes round the body's middle the other way
            ang_land = g.turn * g.duty * 0.5
            ang_off = -g.turn * g.duty * 0.5
            def at(ang):
                rr = yaw_left(ang)
                return centre + rr @ (base - centre)
            if down:
                toe = at(ang_land + (ang_off - ang_land) * w)
                toe[2] = 0.0
                hoof, past, can = r.hoof, r.pastern, None
            else:
                a = ang_off + (ang_land - ang_off) * smooth(w)
                toe = at(a)
                toe[2] = lift * bump(w, 0.45)
                hoof = r.hoof - 60.0 * g.fold * bump(w, 0.4)
                past = r.pastern - 40.0 * g.fold * bump(w, 0.4)
                can = None
            feet[f] = FootPose(toe=toe, hoof=hoof, pastern=past, cannon=can, planted=down)
            continue
        front = base[1] - stance_len * 0.5          # where it lands (forward is -Y)
        back = base[1] + stance_len * 0.5           # where it lifts
        if down:
            y = front + (back - front) * w
            toe = np.array([base[0], y, 0.0])
            # the fetlock sinks under the load, most in mid-stance
            load = math.sin(math.pi * w) * (0.35 + 0.65 * min(1.0, abs(g.speed) / 8.0))
            past = r.pastern + 16.0 * load
            hoof = r.hoof
            # break-over: the heel rises and the hoof tips onto its toe
            if w > 0.72:
                k = smooth((w - 0.72) / 0.28)
                hoof = r.hoof - 40.0 * k
                past = past - 45.0 * k
            feet[f] = FootPose(toe=toe, hoof=hoof, pastern=past, cannon=None)
        else:
            # the swing: up and folded early, reaching forward late, landing flat
            y = back + (front - back) * (0.5 - 0.5 * math.cos(math.pi * w))
            z = lift * bump(w, 0.4)
            f_fold = g.fold * bump(w, 0.38)
            hoof = r.hoof - 40.0 - 110.0 * f_fold if w < 0.5 else r.hoof - (40.0 + 110.0 * f_fold) * (1.0 - smooth((w - 0.5) / 0.5))
            past = r.pastern - 45.0 - 60.0 * f_fold if w < 0.5 else r.pastern - (45.0 + 60.0 * f_fold) * (1.0 - smooth((w - 0.5) / 0.5))
            # the cannon folds back under the knee (fore) or swings under the belly (hind)
            if fore:
                extra = -95.0 * f_fold
            else:
                extra = -55.0 * f_fold
            feet[f] = FootPose(toe=np.array([base[0], y, z]), hoof=hoof, pastern=past, cannon=None, planted=False)
            feet[f].cannon = ("fold", extra)   # resolved below, once the column's angle is known
    qp.feet = feet
    qp.lift = -g.bob * 0.5 - g.bob * 0.5 * wave(phase, g.bobs, g.bob_at)
    qp.pitch = g.pitch * wave(phase, 1.0, g.pitch_at)
    qp.loin = g.flex * wave(phase, 1.0, g.flex_at)
    qp.roll = g.roll * math.sin(2.0 * math.pi * phase)
    qp.neck = g.carriage + g.nod * 0.6 * wave(phase, g.nods, g.nod_at)
    qp.head = g.nod * 0.4 * wave(phase, g.nods, g.nod_at)
    qp.tail = g.tail
    qp.tail_swing = 6.0 * math.sin(2.0 * math.pi * (phase - 0.15))
    qp.ears = (g.ears, g.ears)
    qp.pivot = np.array([0.0, 0.05, 1.10]) * solver.skel.props.withers / 1.5
    if g.turn:
        qp.neck_turn = 0.25 * g.turn * 0.3
        qp.head_turn = 0.25 * g.turn * 0.2
        qp.bend = 0.25 * g.turn * 0.12
    return qp


class _FoldSolver(Solver):
    """Resolves a swing's cannon fold, given as ("fold", degrees), against the leg's column."""

    def _leg(self, pose: dict, foot: str, fp: FootPose) -> None:
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
        super()._leg(pose, foot, fp)


def make_solver(skel: QuadSkeleton) -> Solver:
    return _FoldSolver(skel)


def gait_clip(solver: Solver, g: GaitSpec) -> QuadClip:
    frames = g.cycle * FPS
    if abs(frames - round(frames)) > 1e-6:
        raise ValueError(f"{g.name}: a cycle of {g.cycle} s is {frames:.2f} frames, not a whole number")
    events = []
    for f in FEET:
        events.append((round((g.footfalls[f] % 1.0) * g.cycle, 4), "hoof_" + f.lower()))
    extra = {"speed": round(abs(g.speed), 4)} if not g.turn else {"turn": g.turn}
    if g.speed < 0:
        extra["speed"] = round(g.speed, 4)
    extra["gait"] = {"duty": g.duty, "footfalls": dict(g.footfalls)}
    return QuadClip(g.name, g.cycle, True, lambda t, g=g: gait_pose(solver, g, (t / g.cycle) % 1.0),
                    sorted(events), extra)


# The horse's gaits. Speeds are the game's (DECISIONS 2026-09-24); the footfalls CONTRACTS §3b's.
def horse_gaits() -> List[GaitSpec]:
    return [
        GaitSpec("Walk", speed=1.8, cycle=30 / FPS, duty=0.60,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.10, fold=0.45, bob=0.018, bobs=2, bob_at=0.05, nod=5.0, nods=2, nod_at=0.30,
                 roll=1.5, carriage=4.0, tail=0.0, ears=-4.0),
        GaitSpec("Trot", speed=3.8, cycle=21 / FPS, duty=0.38,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.16, fold=0.75, bob=0.04, bobs=2, bob_at=0.21, nod=2.0, nods=2, nod_at=0.25,
                 carriage=-2.0, tail=6.0, ears=-8.0),
        GaitSpec("Canter", speed=7.0, cycle=16 / FPS, duty=0.28,
                 footfalls={"HR": 0.80, "HL": 0.0, "FR": 0.02, "FL": 0.22},
                 lift=0.18, fold=0.85, bob=0.06, bobs=1, bob_at=0.15, pitch=5.0, pitch_at=0.75,
                 nod=9.0, nods=1, nod_at=0.65, flex=4.0, flex_at=0.75, carriage=2.0, tail=14.0,
                 ears=-6.0, reach=0.0, tuck=0.0),
        GaitSpec("Gallop", speed=11.5, cycle=13 / FPS, duty=0.21,
                 footfalls={"HR": 0.87, "HL": 0.0, "FR": 0.22, "FL": 0.34},
                 lift=0.22, fold=1.0, bob=0.06, bobs=1, bob_at=0.25, pitch=4.0, pitch_at=0.9,
                 nod=8.0, nods=1, nod_at=0.6, flex=7.0, flex_at=0.75, carriage=10.0, tail=22.0,
                 ears=4.0, reach=0.0, tuck=0.0),
        GaitSpec("Walk_Back", speed=-1.0, cycle=36 / FPS, duty=0.6,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.08, fold=0.35, bob=0.012, bobs=2, nod=3.0, nods=2, carriage=-6.0, ears=6.0),
        GaitSpec("Turn_L90", speed=0.0, cycle=39 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.09, fold=0.4, bob=0.01, bobs=2, nod=3.0, carriage=4.0, turn=90.0, ears=-4.0),
        GaitSpec("Turn_R90", speed=0.0, cycle=39 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.09, fold=0.4, bob=0.01, bobs=2, nod=3.0, carriage=4.0, turn=-90.0, ears=-4.0),
    ]


def toe_slip(solver: Solver, clip: QuadClip, speed: float, samples: int = 60) -> float:
    """The farthest any hoof strays over the ground while it is planted, in metres, with the body
    carried forward at `speed` (and turned by the clip's `turn`): 0 for a clip whose planted
    hooves stand still."""
    sk = solver.skel
    turn = float(clip.extra.get("turn", 0.0))
    centre = np.array([0.0, 0.08 * sk.props.withers / 1.5, 0.0])
    worst = 0.0
    landed: Dict[str, np.ndarray] = {}
    dt = clip.length / samples
    for i in range(samples + 1):
        t = i * dt
        qp = clip.sample(t)
        R, th = solver.solve(qp)
        pose = {n: (r, th if n == "Hips" else None) for n, r in R.items()}
        W = sk.fk(pose)
        yaw = yaw_left(turn * t / clip.length)
        for f in FEET:
            p = sk.tail_world(W, foot_bones(f)[-1])
            p = centre + yaw @ (p - centre) + np.array([0.0, -speed * t, 0.0])
            planted = qp.feet[f].planted if f in qp.feet else True
            if not planted:
                landed.pop(f, None)
                continue
            if f not in landed:
                landed[f] = p
            worst = max(worst, float(np.linalg.norm(p - landed[f])))
    return worst


# --------------------------------------------------------------------------------------
# The mount's other clips
# --------------------------------------------------------------------------------------

def _stand(solver: Solver) -> Dict[str, FootPose]:
    return {f: FootPose(toe=r.toe.copy(), hoof=r.hoof, pastern=r.pastern) for f, r in solver.rest.items()}


def _looped(t: float, length: float, period: float) -> float:
    """A phase that repeats a whole number of times in `length`, as near `period` as fits."""
    n = max(1, round(length / period))
    return (t / length * n) % 1.0


def idle_clip(solver: Solver, length: float = 6.0) -> QuadClip:
    """Standing square and at ease: breathing, the head looking about, an ear turning to a
    sound, the tail at the flies."""
    def sample(t: float) -> QuadPose:
        qp = QuadPose(feet=_stand(solver))
        b = _looped(t, length, 3.0)
        qp.lift = 0.004 * math.sin(2 * math.pi * b)
        qp.loin = 0.6 * math.sin(2 * math.pi * b)
        u = t / length
        qp.neck = 6.0 + 4.0 * math.sin(2 * math.pi * u)
        qp.neck_turn = 9.0 * math.sin(2 * math.pi * (u + 0.1)) * smooth(abs(math.sin(2 * math.pi * u)) * 1.5)
        qp.head = 3.0 * math.sin(2 * math.pi * (2 * u + 0.2))
        # the near ear swivels back to listen, twice; the far one flicks once
        e1 = bump(((u - 0.15) % 1.0) / 0.18) if ((u - 0.15) % 1.0) < 0.18 else 0.0
        e2 = bump(((u - 0.62) % 1.0) / 0.12) if ((u - 0.62) % 1.0) < 0.12 else 0.0
        qp.ears = (-4.0 + 35.0 * e1, -4.0 + 20.0 * e2)
        qp.ear_turn = (40.0 * e1, 25.0 * e2)
        sw = ((u - 0.4) % 1.0)
        qp.tail_swing = 28.0 * math.sin(2 * math.pi * sw / 0.25) * bump(sw / 0.25) if sw < 0.25 else 0.0
        qp.tail = -4.0
        qp.jaw = 0.0
        return qp
    return QuadClip("Idle", length, True, sample, [], {})


def graze_clip(solver: Solver, length: float = 4.0) -> QuadClip:
    """Head down in the grass, chewing, the tail swinging now and then. The forehand sinks a little
    over the fore legs (one set forward) and the neck is let right down, the face near vertical:
    the muzzle comes to about 0.25 m, into the grass the world draws."""
    sk = solver.skel
    hip = sk.bones["Thigh.L"].head.copy()
    hip[0] = 0.0

    def sample(t: float) -> QuadPose:
        qp = QuadPose(feet=_stand(solver))
        u = t / length
        qp.pivot = hip
        qp.pitch = -8.0
        qp.neck = 110.0 + 3.0 * math.sin(2 * math.pi * u)
        qp.head = -76.0 + 2.0 * math.sin(2 * math.pi * 2 * u)
        qp.neck_turn = 6.0 * math.sin(2 * math.pi * u)
        qp.jaw = 6.0 * max(0.0, math.sin(2 * math.pi * 6 * u))
        qp.ears = (10.0, 12.0)
        qp.ear_turn = (20.0, 20.0)
        qp.tail_swing = 14.0 * math.sin(2 * math.pi * u)
        qp.feet["FL"].toe[1] -= 0.16
        qp.feet["FL"].pastern += 6.0
        return qp
    return QuadClip("Graze", length, True, sample, [], {})


def stop_clip(solver: Solver, length: float = 1.1) -> QuadClip:
    """The halt from a canter: the hind legs come under and slide, the forehand braces, and the
    horse settles square. The body's deceleration is the game's; the hooves here only plant."""
    def sample(t: float) -> QuadPose:
        u = t / length
        feet = _stand(solver)
        k_in = smooth(u / 0.3)
        k_out = smooth((u - 0.55) / 0.45)
        k = k_in * (1.0 - k_out)
        for f in FEET:
            fore = f[0] == "F"
            fp = feet[f]
            if fore:
                fp.toe[1] += -0.22 * k
                fp.pastern += 10.0 * k
            else:
                fp.toe[1] += -0.34 * k
                fp.pastern += 18.0 * k
        # a hind hoof that has to come from under the belly steps: the right hind a beat late
        if 0.62 < u < 0.82:
            w = (u - 0.62) / 0.2
            feet["HR"].toe[2] = 0.07 * bump(w)
            feet["HR"].planted = False
        qp = QuadPose(feet=feet)
        qp.pitch = 7.0 * k
        qp.lift = -0.09 * k
        qp.pivot = solver.skel.bones["Thigh.L"].head.copy()
        qp.pivot[0] = 0.0
        qp.neck = -12.0 * k
        qp.head = -8.0 * k + 4.0 * k_out
        qp.tail = 10.0 * (1.0 - k_out)
        qp.ears = (-6.0, -6.0)
        return qp
    return QuadClip("Stop", length, False, sample, [(0.12, "hoof_hl"), (0.14, "hoof_hr"), (0.3, "slide")], {})


def rear_clip(solver: Solver, length: float = 2.2) -> QuadClip:
    """Up on the hind legs and down again: a refusal, or a flourish on command."""
    sk = solver.skel
    hip = sk.bones["Thigh.L"].head.copy()
    hip[0] = 0.0

    def sample(t: float) -> QuadPose:
        u = t / length
        feet = _stand(solver)
        crouch = bump(u / 0.3, 0.8) if u < 0.3 else 0.0
        up = smooth((u - 0.18) / 0.3) * (1.0 - smooth((u - 0.66) / 0.3))
        qp = QuadPose(feet=feet)
        qp.pivot = hip
        qp.pitch = 52.0 * up
        qp.lift = -0.07 * crouch - 0.10 * up
        # the hind legs come under the body and take its weight, hocks deep
        for f in ("HL", "HR"):
            feet[f].toe[1] += -0.32 * up
            feet[f].pastern += 26.0 * up
        ang = math.radians(52.0 * up)
        ca, sa = math.cos(ang), math.sin(ang)
        drop = -0.07 * crouch - 0.10 * up

        def carried(p):
            """A point of the body at rest, where the pitched-up body has it."""
            rel = p - hip
            return np.array([p[0], hip[1] + rel[1] * ca + rel[2] * sa, hip[2] - rel[1] * sa + rel[2] * ca + drop])
        # the forelegs leave the ground and fold at the knee, the hooves tucked up under the chest,
        # paddling a little: they are placed in the body's own frame and carried up with it
        for f, ph in (("FL", 0.0), ("FR", 0.35)):
            fp = feet[f]
            if up <= 0.02:
                continue
            fp.planted = False
            pad = math.sin(2 * math.pi * (u * 3.2 + ph))
            # the knees fold as soon as the hooves leave the ground, not as the body rises: a
            # half-risen horse with straight forelegs reads as a leg thrust out
            fold = smooth(up / 0.35) * (0.85 + 0.15 * pad)
            rest = solver.rest[f].toe
            knee = sk.bones[foot_bones(f)[3]].head          # the knee (FrontCannon's head)
            tucked = np.array([rest[0], knee[1] + 0.10 + 0.06 * pad, knee[2] + 0.02])
            fp.toe = carried(rest * (1.0 - fold) + tucked * fold)
            fp.hoof = solver.rest[f].hoof - (140.0 - 52.0) * fold
            fp.pastern = solver.rest[f].pastern - (100.0 - 52.0) * fold
            fp.cannon = ("fold", -115.0 * fold)
        qp.neck = -20.0 * up
        qp.head = -10.0 * up
        # the tail is carried up and out behind as the quarters go down, clear of the hocks
        qp.tail = 62.0 * up
        qp.ears = (25.0 * up, 25.0 * up)
        qp.jaw = 8.0 * up * max(0.0, math.sin(2 * math.pi * u * 2))
        return qp
    return QuadClip("Rear", length, False, sample, [(0.55, "rear_top"), (1.72, "hoof_fl"), (1.8, "hoof_fr")], {})


def mount_clip(solver: Solver, name: str = "Mount", length: float = 1.3, dismount: bool = False) -> QuadClip:
    """The horse's side of a rider getting up (or down) on the near side: it braces against the
    weight in the stirrup, looks round, and settles."""
    def sample(t: float) -> QuadPose:
        u = t / length
        feet = _stand(solver)
        load = bump(u, 0.35 if not dismount else 0.55)
        qp = QuadPose(feet=feet)
        qp.roll = 3.0 * load
        qp.side = 0.02 * load
        qp.lift = -0.02 * load
        qp.neck_turn = 14.0 * bump(u, 0.5)
        qp.head_turn = 10.0 * bump(u, 0.5)
        qp.ears = (20.0 * bump(u, 0.4), 0.0)
        qp.ear_turn = (35.0 * bump(u, 0.4), 0.0)
        for f in ("FL", "HL"):
            feet[f].pastern += 6.0 * load
        return qp
    return QuadClip(name, length, False, sample, [], {})


def build_clips(solver: Solver) -> Dict[str, QuadClip]:
    """Every clip of the mount set (CONTRACTS §3b), by name."""
    clips: Dict[str, QuadClip] = {}
    for g in horse_gaits():
        clips[g.name] = gait_clip(solver, g)
    clips["Idle"] = idle_clip(solver)
    clips["Graze"] = graze_clip(solver)
    clips["Stop"] = stop_clip(solver)
    clips["Rear"] = rear_clip(solver)
    clips["Mount"] = mount_clip(solver, "Mount", 1.3)
    clips["Dismount"] = mount_clip(solver, "Dismount", 1.1, dismount=True)
    return clips


def sheep_gaits() -> List[GaitSpec]:
    """A ewe's gaits: a walk that ambles, a jog-trot, and the bounding run a flock breaks into.
    Lifts and bobs are a ewe's size; speeds are what Livestock plays them at (it plays a clip at
    ground speed / `speed`, as a horse's)."""
    return [
        GaitSpec("Walk", speed=0.9, cycle=24 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.05, fold=0.4, bob=0.01, bobs=2, bob_at=0.05, nod=6.0, nods=2, nod_at=0.30,
                 roll=2.0, carriage=0.0, ears=0.0),
        GaitSpec("Trot", speed=1.9, cycle=15 / FPS, duty=0.4,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.07, fold=0.7, bob=0.02, bobs=2, bob_at=0.21, nod=3.0, nods=2, nod_at=0.25, carriage=-4.0),
        GaitSpec("Run", speed=4.0, cycle=12 / FPS, duty=0.3,
                 footfalls={"HR": 0.85, "HL": 0.0, "FR": 0.12, "FL": 0.28},
                 lift=0.09, fold=0.9, bob=0.03, bobs=1, bob_at=0.3, pitch=5.0, pitch_at=0.8,
                 nod=6.0, nods=1, nod_at=0.6, flex=6.0, flex_at=0.75, carriage=-6.0),
        GaitSpec("Turn_L90", speed=0.0, cycle=30 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.045, fold=0.4, bob=0.005, bobs=2, nod=3.0, turn=90.0),
        GaitSpec("Turn_R90", speed=0.0, cycle=30 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.045, fold=0.4, bob=0.005, bobs=2, nod=3.0, turn=-90.0),
    ]


def build_sheep_clips(solver: Solver) -> Dict[str, QuadClip]:
    """A ewe's clips: Idle, Graze, Walk, Trot, Run and the turns on the spot."""
    clips: Dict[str, QuadClip] = {}
    for g in sheep_gaits():
        clips[g.name] = gait_clip(solver, g)
    clips["Idle"] = idle_clip(solver)
    clips["Graze"] = graze_clip(solver)
    return clips


SHEEP_CLIPS = ["Idle", "Graze", "Walk", "Trot", "Run", "Turn_L90", "Turn_R90"]


def deer_gaits() -> List[GaitSpec]:
    """A red deer's gaits: a long unhurried walk, a springy trot, and the flight -- a bounding gallop
    where the hinds land together, then the fores, and all four are off the ground twice a stride,
    the scut up to show the rump patch. Speeds are what the game plays them at (ground speed /
    `speed`, as a horse's)."""
    return [
        GaitSpec("Walk", speed=1.3, cycle=26 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.08, fold=0.5, bob=0.012, bobs=2, bob_at=0.05, nod=5.0, nods=2, nod_at=0.30,
                 roll=1.5, carriage=-4.0, ears=-4.0),
        GaitSpec("Trot", speed=3.2, cycle=17 / FPS, duty=0.32,
                 footfalls={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5},
                 lift=0.16, fold=0.85, bob=0.035, bobs=2, bob_at=0.21, nod=2.0, nods=2, nod_at=0.25,
                 carriage=-8.0, tail=15.0, ears=-8.0),
        GaitSpec("Run", speed=10.0, cycle=14 / FPS, duty=0.14,
                 footfalls={"HL": 0.0, "HR": 0.06, "FL": 0.46, "FR": 0.53},
                 lift=0.26, fold=1.0, bob=0.10, bobs=1, bob_at=0.30, pitch=9.0, pitch_at=0.85,
                 nod=5.0, nods=1, nod_at=0.6, flex=12.0, flex_at=0.72, carriage=-6.0, tail=55.0, ears=10.0),
        GaitSpec("Turn_L90", speed=0.0, cycle=33 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.07, fold=0.45, bob=0.008, bobs=2, nod=3.0, turn=90.0, ears=-6.0),
        GaitSpec("Turn_R90", speed=0.0, cycle=33 / FPS, duty=0.62,
                 footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                 lift=0.07, fold=0.45, bob=0.008, bobs=2, nod=3.0, turn=-90.0, ears=-6.0),
    ]


def _with(base: QuadClip, name: str, fn, length: Optional[float] = None, loop: Optional[bool] = None) -> QuadClip:
    """`base` under another name with its poses changed by fn(qp, t) -> None."""
    def sample(t: float) -> QuadPose:
        qp = base.sample(t)
        fn(qp, t)
        return qp
    return QuadClip(name, length or base.length, base.loop if loop is None else loop, sample, list(base.events),
                    dict(base.extra))


def alert_clip(solver: Solver, length: float = 2.0) -> QuadClip:
    """Head up, ears forward, stock still but for the breath and a flick of the ears: what a deer
    does for a second or three when it has heard you. A loop the game holds as long as it likes."""
    def sample(t: float) -> QuadPose:
        qp = QuadPose(feet=_stand(solver))
        u = t / length
        qp.lift = 0.006 + 0.003 * math.sin(2 * math.pi * u)
        qp.neck = -22.0
        qp.head = -8.0
        qp.ears = (-22.0, -22.0 + 12.0 * (bump(((u - 0.55) % 1.0) / 0.12) if ((u - 0.55) % 1.0) < 0.12 else 0.0))
        qp.ear_turn = (-6.0, -6.0)
        qp.tail = 12.0
        return qp
    return QuadClip("Alert", length, True, sample, [], {})


def tail_flick(qp: QuadPose, t: float, every: float = 3.0, up: float = 45.0) -> None:
    """A deer's tail flicked up and down, once every `every` seconds."""
    w = (t % every) / every
    if w < 0.08:
        qp.tail = qp.tail + up * bump(w / 0.08)


def hit_clip(solver: Solver, length: float = 0.6) -> QuadClip:
    """A wild beast struck: a flinch away from the blow, the head flung up, the ears back, the scut
    up; back to standing by the end."""
    def sample(t: float) -> QuadPose:
        u = t / length
        k = bump(u, 0.22)
        qp = QuadPose(feet=_stand(solver))
        qp.lift = -0.035 * k
        qp.roll = -5.0 * k
        qp.side = -0.03 * k
        qp.loin = 5.0 * k
        qp.neck = -18.0 * k
        qp.head = -14.0 * k
        qp.neck_turn = 12.0 * k
        qp.ears = (45.0 * k, 45.0 * k)
        qp.tail = 40.0 * k
        for f in FEET:
            qp.feet[f].pastern += 8.0 * k
        return qp
    return QuadClip("Hit", length, False, sample, [], {})


def death_clip(solver: Solver, length: float = 2.2) -> QuadClip:
    """A beast going down: the forelegs buckle and it drops to its knees, the quarters follow, and
    it lies folded on its brisket with the head let down along the ground. The last frame is held
    (CONTRACTS §3)."""
    sk = solver.skel
    hip = sk.bones["Thigh.L"].head.copy()
    hip[0] = 0.0
    lengths = {}
    for f in FEET:
        b = foot_bones(f)
        lengths[f] = (sk.bones[b[-3]].length, sk.bones[b[-2]].length, sk.bones[b[-1]].length)
    brisket = sk.bones[foot_bones("FL")[-3]].head[2]      # the knee's height at rest

    def folded(f: str) -> FootPose:
        """The hoof folded under the lying body: a fore cannon laid back along the ground from the
        knee, a hind one laid forward from the hock."""
        fore = f[0] == "F"
        b = foot_bones(f)
        joint = sk.bones[b[-3]].head.copy()
        lc, lp, lh = lengths[f]
        K = np.array([joint[0], joint[1] + (0.06 if fore else -0.10), 0.05])
        cannon = -88.0 if fore else 88.0
        pastern = -120.0 if fore else 120.0
        hoof = -150.0 if fore else 150.0
        F = K + lc * sag(cannon)
        C = F + lp * sag(pastern)
        toe = C + lh * sag(hoof)
        return FootPose(toe=toe, hoof=hoof, pastern=pastern, cannon=cannon, planted=False)

    def sample(t: float) -> QuadPose:
        u = t / length
        fore_k = smooth(u / 0.35)                  # the knees go
        hind_k = smooth((u - 0.22) / 0.35)         # then the quarters
        head_k = smooth((u - 0.45) / 0.45)         # and the head is let down
        feet = _stand(solver)
        for f in FEET:
            k = fore_k if f[0] == "F" else hind_k
            if k <= 0.0:
                continue
            a, b = feet[f], folded(f)
            feet[f] = FootPose(toe=a.toe * (1.0 - k) + b.toe * k, hoof=a.hoof * (1.0 - k) + b.hoof * k,
                               pastern=a.pastern * (1.0 - k) + b.pastern * k,
                               cannon=solver._rest_cannon[f] * (1.0 - k) + b.cannon * k, planted=k < 0.5)
        qp = QuadPose(feet=feet)
        drop = brisket * 1.28
        qp.pivot = hip
        # the front goes down first, pitching the body forward; the quarters come down after it
        qp.pitch = -14.0 * fore_k * (1.0 - hind_k)
        qp.lift = -drop * (0.55 * fore_k + 0.45 * hind_k)
        qp.roll = 12.0 * hind_k
        qp.neck = -10.0 * fore_k * (1.0 - head_k) + 78.0 * head_k
        qp.head = 8.0 * fore_k - 50.0 * head_k
        qp.neck_turn = 18.0 * head_k
        qp.ears = (40.0 * fore_k, 45.0 * fore_k)
        qp.tail = 20.0 * fore_k * (1.0 - head_k)
        qp.jaw = 6.0 * head_k
        return qp
    return QuadClip("Death", length, False, sample, [(0.35 * length, "fall"), (0.6 * length, "land")], {"held": True})


def build_deer_clips(solver: Solver) -> Dict[str, QuadClip]:
    """A red deer's clips: Idle, Graze, Graze_Step, Alert, Walk, Trot, Run (the flight: a bound),
    Hit, Death and the turns."""
    clips: Dict[str, QuadClip] = {}
    for g in deer_gaits():
        clips[g.name] = gait_clip(solver, g)
    idle = idle_clip(solver)

    def idle_fn(qp: QuadPose, t: float) -> None:
        qp.neck -= 10.0             # a deer's head is carried higher than a horse's at ease
        tail_flick(qp, t, 2.0)
    clips["Idle"] = _with(idle, "Idle", idle_fn)
    graze = graze_clip(solver)

    def graze_fn(qp: QuadPose, t: float) -> None:
        # a deer's neck, carried high, has further to come down: the muzzle to about 0.15 m
        qp.neck += 30.0
        qp.head -= 10.0
        qp.pitch -= 4.0
        tail_flick(qp, t, 2.0, 35.0)
    clips["Graze"] = _with(graze, "Graze", graze_fn)
    # grazing on: a slow step with the head down, the muzzle through the grass
    step = GaitSpec("Graze_Step", speed=0.35, cycle=48 / FPS, duty=0.75,
                    footfalls={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75},
                    lift=0.05, fold=0.4, bob=0.006, bobs=2, nod=2.0, carriage=0.0, ears=0.0)
    base = gait_clip(solver, step)
    hip = solver.skel.bones["Thigh.L"].head.copy()
    hip[0] = 0.0

    def graze_step(qp: QuadPose, t: float) -> None:
        qp.pivot = hip
        qp.pitch -= 10.0
        qp.neck += 135.0
        qp.head -= 82.0
        tail_flick(qp, t, 1.6, 30.0)
    clips["Graze_Step"] = _with(base, "Graze_Step", graze_step)
    clips["Alert"] = alert_clip(solver)
    clips["Hit"] = hit_clip(solver)
    clips["Death"] = death_clip(solver)
    return clips


# CONTRACTS §3b: a wild beast's set -- the gaits (Run is its bound), Hit and Death -- and a deer's own
DEER_CLIPS = ["Idle", "Graze", "Graze_Step", "Alert", "Walk", "Trot", "Run", "Hit", "Death", "Turn_L90", "Turn_R90"]


def look_back_clip(solver: Solver, name: str = "Look_Back", side: float = 1.0, length: float = 4.0) -> QuadClip:
    """Standing square, the head turned right round over the shoulder (the left for side 1, the
    right for -1) and held there, looking back at whoever follows: the back bent a little toward
    it, the head carried high, the ears pricked at what it sees. A loop the game holds while it
    waits; the breath goes on, an ear turns away once and comes back, the scut flicks."""
    def sample(t: float) -> QuadPose:
        qp = QuadPose(feet=_stand(solver))
        u = t / length
        b = math.sin(2 * math.pi * u)
        qp.lift = 0.005 * math.sin(4 * math.pi * u)
        qp.bend = 14.0 * side
        qp.yaw = 6.0 * side
        qp.roll = -1.5 * side
        qp.neck = -14.0 + 2.0 * b
        qp.neck_turn = (82.0 + 3.0 * b) * side
        qp.head_turn = 46.0 * side
        qp.head = -6.0 + 2.5 * math.sin(2 * math.pi * (u + 0.3))
        e = bump(((u - 0.4) % 1.0) / 0.2) if ((u - 0.4) % 1.0) < 0.2 else 0.0
        near, far = -16.0, -16.0 + 34.0 * e
        qp.ears = (near, far) if side > 0 else (far, near)
        qp.ear_turn = (-8.0, -8.0 + 30.0 * e) if side > 0 else (-8.0 + 30.0 * e, -8.0)
        qp.tail = 6.0
        tail_flick(qp, t, length, 35.0)
        return qp
    return QuadClip(name, length, True, sample, [], {})


def build_hart_clips(solver: Solver) -> Dict[str, QuadClip]:
    """The grey hart's: the red deer's walk, trot, bound, stand and turns, and the looking back
    over either shoulder at who follows it."""
    clips = build_deer_clips(solver)
    clips["Look_Back"] = look_back_clip(solver, "Look_Back", 1.0)
    clips["Look_Back_R"] = look_back_clip(solver, "Look_Back_R", -1.0)
    return clips


# A lead's set (Leads): it walks and trots its way, stands, looks back, turns; Hit and Death stay
# for whatever shoots it.
HART_CLIPS = ["Idle", "Alert", "Look_Back", "Look_Back_R", "Walk", "Trot", "Run", "Hit", "Death",
              "Turn_L90", "Turn_R90"]


MOUNT_CLIPS = ["Idle", "Graze", "Walk", "Trot", "Canter", "Gallop", "Walk_Back", "Turn_L90", "Turn_R90",
               "Stop", "Rear", "Mount", "Dismount"]


def check_contract(clips: Dict[str, QuadClip]) -> List[str]:
    problems = []
    for n in MOUNT_CLIPS:
        if n not in clips:
            problems.append(f"missing clip {n}")
    for n, c in clips.items():
        frames = c.length * FPS
        if c.loop and abs(frames - round(frames)) > 1e-6:
            problems.append(f"{n}: a loop of {c.length:.4f} s is {frames:.2f} frames")
        for t, e in c.events:
            if t < 0 or t > c.length + 1e-6:
                problems.append(f"{n}: event {e} at {t} outside the clip")
    for n in ("Walk", "Trot", "Canter", "Gallop", "Walk_Back"):
        c = clips.get(n)
        if c is not None and "speed" not in c.extra:
            problems.append(f"{n}: no speed")
        if c is not None and len([e for _, e in c.events if e.startswith("hoof_")]) != 4:
            problems.append(f"{n}: not four hoof events")
    return problems
