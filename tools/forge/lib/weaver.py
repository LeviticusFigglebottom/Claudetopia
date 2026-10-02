"""The weaver: the Briarwold's canopy spider (core:enemy/weaver), its rig, body, paint and clips.

WORLD_BIBLE §8: "ambusher from above; arachnid: drops from canopy, webs slow". Built at the size
its def's scale (1.2) makes it: a cephalothorax the size of a dog's chest, a bulbous abdomen, eight
long banded legs spanning two metres, a cluster of eyes and two black fangs under them.

Rig (lib/creature_rig.Rig, `WM_Weaver_v1`): Hips (the cephalothorax), Abdomen and Spinner behind it,
Head with Fang.L/R and the palps (Palp1/2.L/R), and each leg Coxa/Femur/Tibia/Tarsus<n>.<side>, the
first pair in front. The legs walk an alternating tetrapod (L1 R2 L3 R4 against the others).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, List, Tuple

import numpy as np

from . import sdf, paint
from .anim import FPS
from .rig import rot_axis, UP, FWD, LEFT
from .creature_rig import Rig, Poser, RigClip, _u
from . import beast_body as bb

RIG_ID = "WM_Weaver_v1"
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

CEPH = np.array([0.0, 0.0, 0.40])          # the cephalothorax's middle
CEPH_R = np.array([0.15, 0.19, 0.095])
ABD = np.array([0.0, 0.44, 0.52])
ABD_R = np.array([0.27, 0.35, 0.25])
# each leg: (angle from straight ahead, degrees; femur, tibia, tarsus lengths; reach on the ground)
LEGS = {1: (32.0, 0.42, 0.46, 0.40, 0.98), 2: (68.0, 0.40, 0.42, 0.35, 0.92),
        3: (106.0, 0.34, 0.36, 0.30, 0.80), 4: (136.0, 0.40, 0.44, 0.38, 0.98)}
TETRAPOD_A = ["1.L", "2.R", "3.L", "4.R"]
FEET = ["%d.%s" % (i, s) for i in (1, 2, 3, 4) for s in ("L", "R")]


@dataclass
class WeaverStyle:
    seed: int = 21

    def to_dict(self) -> dict:
        return asdict(self)


def _dir(i: int, side: str) -> np.ndarray:
    """The leg's way out across the ground (unit, horizontal)."""
    a = math.radians(LEGS[i][0])
    sx = 1.0 if side == "L" else -1.0
    return np.array([sx * math.sin(a), -math.cos(a), 0.0])


def leg_root(i: int, side: str) -> np.ndarray:
    d = _dir(i, side)
    return CEPH + d * np.array([0.12, 0.15, 0.0]) + np.array([0.0, 0.0, -0.01])


def _rest_leg(i: int, side: str):
    """(coxa root, femur root, knee, ankle, tip) at rest."""
    _, lf, lt, lr, reach = LEGS[i]
    d = _dir(i, side)
    root = leg_root(i, side)
    hip = root + d * 0.055 + Z * 0.02
    tip = np.array([root[0], root[1], 0.0]) + d * reach
    tip[2] = 0.0
    ankle = tip + _u(-d * 0.28 + Z) * lr
    # the knee high over the leg's line: two bones from the hip to the ankle, bent upward
    to = ankle - hip
    dist = float(np.linalg.norm(to))
    dist = min(dist, lf + lt - 1e-3)
    dv = to / np.linalg.norm(to)
    cos_a = (lf * lf + dist * dist - lt * lt) / (2 * lf * dist)
    ang = math.acos(max(-1.0, min(1.0, cos_a)))
    pole = Z - dv * float(Z @ dv)
    pole = _u(pole)
    knee = hip + (math.cos(ang) * dv + math.sin(ang) * pole) * lf
    return root, hip, knee, ankle, tip


def make_rig() -> Rig:
    bones = [("Hips", None, CEPH + np.array([0.0, 0.08, 0.0]), CEPH + np.array([0.0, -0.10, 0.0]), UP),
             ("Abdomen", "Hips", np.array([0.0, 0.17, 0.44]), np.array([0.0, 0.74, 0.54]), UP),
             ("Spinner", "Abdomen", np.array([0.0, 0.74, 0.50]), np.array([0.0, 0.81, 0.44]), UP),
             ("Head", "Hips", np.array([0.0, -0.13, 0.43]), np.array([0.0, -0.22, 0.42]), UP)]
    for side, sx in (("L", 1.0), ("R", -1.0)):
        bones.append(("Fang.%s" % side, "Head", np.array([sx * 0.04, -0.215, 0.39]), np.array([sx * 0.032, -0.25, 0.27]), FWD))
        bones.append(("Palp1.%s" % side, "Head", np.array([sx * 0.06, -0.19, 0.39]), np.array([sx * 0.11, -0.30, 0.37]), UP))
        bones.append(("Palp2.%s" % side, "Palp1.%s" % side, np.array([sx * 0.11, -0.30, 0.37]), np.array([sx * 0.12, -0.36, 0.24]), FWD))
    for i in (1, 2, 3, 4):
        for side in ("L", "R"):
            root, hip, knee, ankle, tip = _rest_leg(i, side)
            n = "%d.%s" % (i, side)
            bones += [("Coxa" + n, "Hips", root, hip, UP), ("Femur" + n, "Coxa" + n, hip, knee, UP),
                      ("Tibia" + n, "Femur" + n, knee, ankle, UP), ("Tarsus" + n, "Tibia" + n, ankle, tip, UP)]
    return Rig(RIG_ID, bones, height=0.75)


# --------------------------------------------------------------------------------------
# body
# --------------------------------------------------------------------------------------

def weaver_scene(rig: Rig, st: WeaverStyle, bare: bool = False) -> sdf.Scene:
    sc = sdf.Scene()
    J = rig.bones
    # the cephalothorax: a flattened shield, the head end raised
    sc.union(sdf.ellipsoid(CEPH, CEPH_R))
    sc.union(sdf.ellipsoid(CEPH + np.array([0.0, -0.12, 0.035]), np.array([0.10, 0.09, 0.075])), k=0.04)
    # the abdomen on its waist, high and round, pointed a little at the spinnerets
    sc.union(sdf.capsule(np.array([0.0, 0.14, 0.42]), np.array([0.0, 0.2, 0.46]), 0.045), k=0.02)
    sc.union(sdf.ellipsoid(ABD, ABD_R), k=0.03)
    sc.union(sdf.round_cone(np.array([0.0, 0.70, 0.49]), np.array([0.0, 0.81, 0.45]), 0.05, 0.022), k=0.05)
    # the chelicerae: two heavy jaws hanging under the eyes, the fangs folded under them
    for sx in (1.0, -1.0):
        sc.union(sdf.round_cone(np.array([sx * 0.04, -0.18, 0.43]), np.array([sx * 0.04, -0.235, 0.36]), 0.035, 0.026), k=0.02)
        f0, f1 = J["Fang." + ("L" if sx > 0 else "R")].head, J["Fang." + ("L" if sx > 0 else "R")].tail
        sc.union(sdf.tube_path([f0, f0 + (f1 - f0) * 0.5 + Y * -0.01, f1], [0.014, 0.01, 0.002]), k=0.006)
        # the palps
        p0, p1, p2 = J["Palp1." + ("L" if sx > 0 else "R")].head, J["Palp2." + ("L" if sx > 0 else "R")].head, \
            J["Palp2." + ("L" if sx > 0 else "R")].tail
        sc.union(sdf.chain([p0, p1, p2], [0.018, 0.016, 0.013]), k=0.01)
    # the eyes: two big in front, two over them, and a row of four behind
    for (x, y, z, r) in eye_list():
        sc.union(sdf.sphere(np.array([x, y, z]), r), k=0.004)
    # the legs: tapering segments, knobbed at the joints, bristled
    rng = np.random.default_rng(st.seed)
    for i in (1, 2, 3, 4):
        for side in ("L", "R"):
            n = "%d.%s" % (i, side)
            root, hip, knee, ankle, tip = _rest_leg(i, side)
            th = 1.0 - 0.08 * (i - 1) if i < 4 else 0.95
            sc.union(sdf.round_cone(root, hip, 0.058 * th, 0.052 * th), k=0.025)
            sc.union(sdf.round_cone(hip, hip + (knee - hip) * 0.35, 0.052 * th, 0.05 * th), k=0.012)
            sc.union(sdf.round_cone(hip + (knee - hip) * 0.35, knee, 0.05 * th, 0.04 * th), k=0.02)
            sc.union(sdf.sphere(knee, 0.044 * th), k=0.012)
            sc.union(sdf.round_cone(knee, ankle, 0.04 * th, 0.026 * th), k=0.012)
            sc.union(sdf.sphere(ankle, 0.028 * th), k=0.006)
            sc.union(sdf.round_cone(ankle, tip + Z * 0.008, 0.022 * th, 0.008), k=0.006)
            # bristles: stiff short spines along the femur and tibia, raking toward the tip
            for a, b, rr, count in (() if bare else ((hip, knee, 0.046 * th, 8), (knee, ankle, 0.034 * th, 8))):
                axis = _u(b - a)
                for k in range(count):
                    f = (k + 0.5) / count
                    ang = rng.uniform(0, 2 * math.pi)
                    side_v = _u(np.cross(axis, np.array([math.cos(ang), math.sin(ang), 0.5])))
                    base = a + (b - a) * f + side_v * rr * 0.8
                    tipb = base + _u(side_v + axis * 1.4) * 0.05
                    sc.union(sdf.round_cone(base, tipb + _u(side_v) * 0.02, 0.008, 0.0015), k=0.004)
    # the abdomen's bristles and humps: a pair of shoulders at its front, as an orb-weaver's
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(ABD + np.array([sx * 0.13, -0.12, 0.17]), np.array([0.07, 0.07, 0.06])), k=0.06)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    if bare:
        return sc
    n1 = paint.Noise(st.seed + 3, 64)

    def disp(P):
        # a fine lumpy, hairy skin on the abdomen and the cephalothorax
        abd = 1.0 - bb.sm(0.0, 0.08, np.linalg.norm((P - ABD) / ABD_R, axis=1) - 1.0)
        return 0.008 * abd * (n1.fbm(P * np.array([1.0, 0.5, 1.0]), freq=40.0, octaves=2) - 0.45)
    return bb.Displaced(sc, disp, 0.012)


def eye_list() -> List[Tuple[float, float, float, float]]:
    out = []
    for sx in (1.0, -1.0):
        out += [(sx * 0.03, -0.205, 0.465, 0.022), (sx * 0.045, -0.18, 0.505, 0.016), (sx * 0.075, -0.16, 0.49, 0.012),
                (sx * 0.06, -0.135, 0.515, 0.011)]
    return out


def regions(rig: Rig, P: np.ndarray) -> Dict[str, np.ndarray]:
    R: Dict[str, np.ndarray] = {}
    n = len(P)
    sm = bb.sm
    R["abdomen"] = 1.0 - sm(0.95, 1.12, np.linalg.norm((P - ABD) / (ABD_R * 1.15), axis=1))
    R["abdomen"] = np.maximum(R["abdomen"], (P[:, 1] > 0.55) * (P[:, 2] > 0.3) * 1.0)
    R["ceph"] = (1.0 - sm(1.0, 1.25, np.linalg.norm((P - CEPH) / CEPH_R, axis=1))) * (1.0 - R["abdomen"])
    R["top"] = sm(0.0, 0.5, P[:, 2] - 0.42)
    R["eye"] = np.zeros(n)
    for (x, y, z, r) in eye_list():
        R["eye"] = np.maximum(R["eye"], 1.0 - sm(r * 1.05, r * 1.35, np.linalg.norm(P - np.array([x, y, z]), axis=1)))
    R["fang"] = np.zeros(n)
    R["leg"] = np.zeros(n)
    R["band"] = np.zeros(n)
    for b in rig.order:
        bone = rig.bones[b]
        if b.startswith("Fang"):
            d, u = bb._seg(P, bone.head, bone.tail)
            R["fang"] = np.maximum(R["fang"], (1.0 - sm(0.016, 0.022, d)) * sm(0.25, 0.45, u))
        if b.startswith(("Femur", "Tibia", "Tarsus", "Palp")):
            d, u = bb._seg(P, bone.head, bone.tail)
            on = 1.0 - sm(0.05, 0.065, d)
            R["leg"] = np.maximum(R["leg"], on)
            # pale rings at each joint's end and in the middle of the long segments
            ring = np.maximum(1.0 - sm(0.06, 0.12, u), 1.0 - sm(0.04, 0.09, np.abs(u - 0.55)))
            R["band"] = np.maximum(R["band"], on * ring)
    R["leg"] *= (1.0 - R["abdomen"])
    R["band"] *= R["leg"]
    return R


def weaver_paint(rig: Rig, st: WeaverStyle, field: sdf.SampledField):
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 9, 64)
    base = np.array([0.30, 0.27, 0.25])          # the def's #59504a, painted darker for the light to lift
    dark = np.array([0.11, 0.10, 0.10])
    pale = np.array([0.66, 0.60, 0.50])
    fang = np.array([0.10, 0.03, 0.03])

    def albedo(P, nrm):
        R = regions(rig, P)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.05, samples=5, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=4.0, octaves=3)
        hair = n2.fbm(P * np.array([1.0, 1.0, 3.0]), freq=120.0, octaves=2)
        c = np.broadcast_to(base, (len(P), 3)).copy() * (0.85 + 0.3 * big)[:, None]
        # the abdomen: a pale folium down its back, edged dark, chevrons across it, mottled sides
        q = (P - ABD) / ABD_R
        fol_w = 0.32 + 0.12 * np.cos(q[:, 1] * 3.2)
        folium = (1.0 - bb.sm(fol_w - 0.06, fol_w, np.abs(q[:, 0]))) * bb.sm(0.1, 0.4, q[:, 2]) * R["abdomen"]
        chev = 0.5 + 0.5 * np.sin((q[:, 1] + 1.6 * np.abs(q[:, 0])) * 9.0)
        c = paint.mix(c, dark, 0.7 * R["abdomen"] * bb.sm(-0.1, 0.4, q[:, 2]) * (1.0 - folium))
        c = paint.mix(c, pale * (0.75 + 0.3 * big)[:, None], 0.85 * folium * bb.sm(0.35, 0.6, chev))
        c = paint.mix(c, dark, 0.6 * folium * (1.0 - bb.sm(0.15, 0.35, chev)))
        mott = paint.dots(P, 0.04, 0.5, 0.008, 0.02, st.seed)
        c = paint.mix(c, pale * 0.8, 0.5 * mott * R["abdomen"] * (1.0 - folium))
        # the shield: dark, with grooves fanning from its middle
        ang = np.arctan2(P[:, 0] - CEPH[0], P[:, 1] - CEPH[1])
        groove = 0.5 + 0.5 * np.cos(ang * 8.0)
        c = paint.mix(c, dark, R["ceph"] * (0.35 + 0.35 * bb.sm(0.7, 0.95, groove)))
        # the legs: dark, banded pale at the joints, the hair catching the light
        c = paint.mix(c, dark * 1.4, 0.6 * R["leg"])
        c = paint.mix(c, pale, 0.75 * R["band"])
        c = c * (0.85 + 0.3 * hair)[:, None]
        # the underside paler
        c = paint.mix(c, pale * 0.6, 0.35 * (1.0 - bb.sm(-0.7, -0.2, up)) * (1.0 - R["leg"]))
        c = paint.mix(c, fang, R["fang"])
        c = paint.mix(c, np.array([0.02, 0.02, 0.025]), R["eye"])
        v = (0.5 + 0.5 * occ)
        v = np.maximum(v, R["eye"])
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = regions(rig, P)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.05, samples=5, strength=1.2)
        rough = 0.78 - 0.7 * R["eye"] - 0.4 * R["fang"] - 0.15 * R["ceph"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.05, 0.95), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        R = regions(rig, P)
        hair = n2.fbm(P * np.array([1.0, 1.0, 3.0]), freq=120.0, octaves=2)
        return 0.5 * hair * (1.0 - R["eye"]) + 0.3 * R["band"]

    return albedo, orm, height


# --------------------------------------------------------------------------------------
# clips
# --------------------------------------------------------------------------------------

@dataclass
class Body:
    lift: float = 0.0
    ahead: float = 0.0
    side: float = 0.0
    pitch: float = 0.0       # the front up, degrees
    roll: float = 0.0        # the left side down, degrees
    yaw: float = 0.0
    abdomen: float = 0.0     # the abdomen raised, degrees
    abd_swing: float = 0.0
    fangs: float = 0.0       # opened, degrees
    palps: float = 0.0       # raised, degrees
    head: float = 0.0        # nodded down, degrees


def body_turn(b: Body) -> np.ndarray:
    return rot_axis(UP, math.radians(b.yaw)) @ rot_axis(LEFT, math.radians(-b.pitch)) @ rot_axis(FWD, math.radians(-b.roll))


def rest_tips() -> Dict[str, np.ndarray]:
    return {f: _rest_leg(int(f[0]), f[2])[4].copy() for f in FEET}


def body_xf(rig: Rig, b: Body):
    R = body_turn(b)
    pv = CEPH
    off = np.array([b.side, -b.ahead, b.lift])
    return R, (lambda p: pv + R @ (np.asarray(p, float) - pv) + off)


def pose(rig: Rig, b: Body, tips: Dict[str, np.ndarray], knees_up: Dict[str, float] = None) -> Poser:
    """The body placed, then each leg's tip put where `tips` says (armature space)."""
    p = Poser(rig)
    R, xf = body_xf(rig, b)
    p.move_hips(R, np.array([b.side, -b.ahead, b.lift]), pivot=CEPH)
    p.turn("Abdomen", rot_axis(LEFT, math.radians(b.abdomen)) @ rot_axis(UP, math.radians(b.abd_swing)))
    p.turn("Spinner", rot_axis(LEFT, math.radians(b.abdomen * 0.3)))
    p.turn("Head", rot_axis(LEFT, math.radians(b.head)))
    for side, sx in (("L", 1.0), ("R", -1.0)):
        p.turn("Fang." + side, rot_axis(UP, math.radians(sx * b.fangs * 0.6)) @ rot_axis(LEFT, math.radians(-b.fangs)))
        p.turn("Palp1." + side, rot_axis(LEFT, math.radians(-b.palps)))
        p.turn("Palp2." + side, rot_axis(LEFT, math.radians(-b.palps * 0.6)))
    for f in FEET:
        n = f
        i = int(f[0])
        W = p.W()
        hip = W["Femur" + n][:3, 3]
        tip = np.asarray(tips[f], float)
        lr = rig.bones["Tarsus" + n].length
        out = tip - hip
        out[2] = 0.0
        d = _u(out) if np.linalg.norm(out) > 1e-4 else R @ _dir(i, f[2])
        up_b = R @ Z
        ankle = tip + _u(-d * 0.28 + up_b) * lr
        ku = (knees_up or {}).get(f, 1.0)
        p.two_bone("Femur" + n, "Tibia" + n, ankle, up_b * ku + d * 0.2)
        p.aim("Tarsus" + n, tip - p.tail("Tibia" + n))
    return p


def gait(name: str, speed: float, cycle: float, duty: float, lift: float, way=(0.0, 1.0), turn: float = 0.0,
         bob: float = 0.01) -> RigClip:
    """The alternating tetrapod: L1 R2 L3 R4 down while the others swing, and the other way.
    `way` is the planted feet's travel in the body's frame (+Y: the body going forward)."""
    stride = speed * cycle
    stance = stride * duty
    rest = rest_tips()
    wv = np.array([way[0], way[1], 0.0])

    def sample(t: float) -> Poser:
        ph = (t / cycle) % 1.0
        tips = {}
        for f in FEET:
            off = 0.0 if f in TETRAPOD_A else 0.5
            u = (ph - off) % 1.0
            r = rest[f]
            if turn:
                ang_from, ang_to = math.radians(turn * duty * 0.5), -math.radians(turn * duty * 0.5)
            if u < duty:
                w = u / duty
                if turn:
                    a = ang_from + (ang_to - ang_from) * w
                    tips[f] = CEPH * np.array([1, 1, 0]) + rot_axis(UP, a) @ (r - CEPH * np.array([1, 1, 0]))
                else:
                    tips[f] = r + wv * stance * (w - 0.5)
                tips[f][2] = 0.0
            else:
                w = (u - duty) / (1.0 - duty)
                s = 0.5 - 0.5 * math.cos(math.pi * w)
                if turn:
                    a = ang_to + (ang_from - ang_to) * s
                    tips[f] = CEPH * np.array([1, 1, 0]) + rot_axis(UP, a) @ (r - CEPH * np.array([1, 1, 0]))
                else:
                    tips[f] = r + wv * stance * (0.5 - s)
                tips[f][2] = lift * math.sin(math.pi * w)
        b = Body(lift=bob * math.cos(4 * math.pi * ph), roll=1.5 * math.sin(2 * math.pi * ph),
                 abd_swing=4.0 * math.sin(2 * math.pi * ph), palps=10.0 + 8.0 * math.sin(4 * math.pi * ph))
        return pose(RIG, b, tips)
    extra = {"speed": round(speed, 4)} if not turn else {"turn": turn}
    if way[0] and not way[1]:
        extra["side"] = way[0]
    return RigClip(name, cycle, True, sample, [], extra)


def _smooth(x: float) -> float:
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def _bump(x: float, peak: float = 0.5) -> float:
    x = min(1.0, max(0.0, x))
    if x < peak:
        return math.sin(0.5 * math.pi * x / peak) ** 2
    return math.sin(0.5 * math.pi * (1.0 - x) / (1.0 - peak)) ** 2


def front_raised(tips, k: float, high: float = 0.55, fwd: float = 0.15, pairs=(1,)):
    """The front legs lifted up and forward in threat."""
    out = dict(tips)
    for i in pairs:
        for side in ("L", "R"):
            f = "%d.%s" % (i, side)
            r = tips[f]
            out[f] = r + np.array([0.0, -fwd * k, high * k]) + _dir(i, side) * (-0.25 * k)
    return out


def curled(rig: Rig, b: Body, amount: float, wiggle: float = 0.0, t: float = 0.0) -> Dict[str, np.ndarray]:
    """Tips drawn in under the body (in the body's own frame, carried with it): a dead spider's legs."""
    R, xf = body_xf(rig, b)
    out = {}
    for f in FEET:
        i = int(f[0])
        r = rest_tips()[f]
        root = leg_root(i, f[2])
        tuck = root + _dir(i, f[2]) * 0.30 + np.array([0.0, 0.0, -0.18])
        wg = wiggle * math.sin(2 * math.pi * (t * 3.0 + i * 0.27 + (0.5 if f[2] == "R" else 0.0)))
        tuck = tuck + np.array([0.0, 0.0, 0.08 * wg])
        out[f] = xf(r + (tuck - r) * amount)
    return out


def idle_clip() -> RigClip:
    L = 4.0
    rest = rest_tips()

    def sample(t: float) -> Poser:
        u = t / L
        b = Body(lift=0.008 * math.sin(2 * math.pi * u * 2), abdomen=3.0 * math.sin(2 * math.pi * u * 2),
                 palps=12.0 + 10.0 * max(0.0, math.sin(2 * math.pi * u * 3)), fangs=4.0 * max(0.0, math.sin(2 * math.pi * u)))
        tips = dict(rest)
        # a foreleg tested on the ground, now and then
        w = (u - 0.3) % 1.0
        if w < 0.15:
            tips["1.L"] = rest["1.L"] + np.array([0.0, -0.05, 0.10 * _bump(w / 0.15)])
        return pose(RIG, b, tips)
    return RigClip("Idle", L, True, sample)


def combat_idle_clip() -> RigClip:
    L = 2.0
    rest = rest_tips()

    def sample(t: float) -> Poser:
        u = t / L
        b = Body(lift=-0.05 + 0.01 * math.sin(2 * math.pi * u * 2), pitch=8.0, abdomen=10.0, palps=30.0,
                 fangs=10.0 + 8.0 * max(0.0, math.sin(2 * math.pi * u * 2)), side=0.02 * math.sin(2 * math.pi * u))
        tips = front_raised(rest, 0.55 + 0.1 * math.sin(2 * math.pi * u * 2))
        return pose(RIG, b, tips)
    return RigClip("Idle_Combat", L, True, sample)


def fang_clip() -> RigClip:
    """Attack_1, the fang: reared on the back legs with the forelegs up and the fangs spread, then
    down and forward on to you, the fangs driving in at `hit_start`."""
    L = 0.9
    cocked, strike, hs, he, ok = 0.26, 0.31, 0.36, 0.50, 0.66
    rest = rest_tips()

    def sample(t: float) -> Poser:
        rear = _smooth(t / cocked) * (1.0 - _smooth((t - cocked) / (hs - cocked)))
        go = _smooth((t - cocked) / (hs - cocked)) * (1.0 - _smooth((t - he) / (L - he)))
        b = Body(lift=0.10 * rear - 0.08 * go, pitch=22.0 * rear - 12.0 * go, ahead=-0.06 * rear + 0.20 * go,
                 abdomen=-8.0 * rear + 12.0 * go, palps=40.0 * rear, fangs=45.0 * rear * (1.0 - go) + 50.0 * _smooth((t - 0.15) / 0.1) * (1.0 - _smooth((t - hs) / 0.05)))
        tips = front_raised(rest, 1.0 * rear + 0.3 * go, high=0.5, fwd=0.1 + 0.35 * go)
        if go > 0:
            for side in ("L", "R"):
                tips["1." + side] = tips["1." + side] + np.array([0.0, -0.2 * go, -0.35 * go])
        return pose(RIG, b, tips)
    return RigClip("Attack_1", L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def drop_clip() -> RigClip:
    """Attack_2, the drop: gathered low on all eight, then up and out at you, legs flung wide and
    the fangs open; it comes down on you at `hit_start` and settles."""
    L = 1.2
    cocked, strike, hs, he, ok, land = 0.40, 0.46, 0.60, 0.80, 0.98, 0.78
    rest = rest_tips()

    def sample(t: float) -> Poser:
        crouch = _smooth(t / cocked) * (1.0 - _smooth((t - cocked) / 0.08))
        air = _smooth((t - cocked) / (hs - cocked)) * (1.0 - _smooth((t - hs) / (land - hs)))
        b = Body(lift=-0.15 * crouch + 0.35 * air, pitch=-6.0 * crouch + 14.0 * air, ahead=0.25 * air,
                 abdomen=8.0 * crouch - 15.0 * air, fangs=55.0 * air, palps=35.0 * air)
        tips = dict(rest)
        R, xf = body_xf(RIG, b)
        for f in FEET:
            i = int(f[0])
            gather = rest[f] - _dir(i, f[2]) * 0.12 * crouch
            spread = xf(rest[f] + _dir(i, f[2]) * 0.12 + np.array([0.0, -0.1 if i <= 2 else 0.05, 0.08 if i <= 2 else -0.05]))
            tips[f] = gather * (1.0 - air) + spread * air
            if air < 0.01:
                tips[f][2] = 0.0
        return pose(RIG, b, tips)
    return RigClip("Attack_2", L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (land, "land"), (ok, "cancel_ok")])


def spit_clip() -> RigClip:
    """Attack_3, the web: rocked back with the abdomen curled up over its back and the forelegs
    raised, then a jerk forward that throws the web at `hit_start`."""
    L = 1.0
    cocked, hs, he, ok = 0.36, 0.45, 0.55, 0.72
    rest = rest_tips()

    def sample(t: float) -> Poser:
        back = _smooth(t / cocked) * (1.0 - _smooth((t - cocked) / (hs - cocked)))
        jerk = _bump((t - cocked) / (he + 0.1 - cocked), 0.4) if cocked < t < he + 0.1 else 0.0
        rec = 1.0 - _smooth((t - he) / (L - he))
        b = Body(lift=0.03 * back, pitch=14.0 * back - 6.0 * jerk, ahead=-0.08 * back + 0.08 * jerk,
                 abdomen=(35.0 * back + 20.0 * jerk) * rec, palps=30.0 * back + 50.0 * jerk, fangs=20.0 * jerk)
        tips = front_raised(rest, 0.7 * back + 0.4 * jerk)
        return pose(RIG, b, tips)
    return RigClip("Attack_3", L, False, sample,
                   [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def hit_clip() -> RigClip:
    L = 0.45
    rest = rest_tips()

    def sample(t: float) -> Poser:
        k = _bump(t / L, 0.22)
        b = Body(lift=-0.04 * k, pitch=10.0 * k, ahead=-0.06 * k, roll=6.0 * k, abdomen=12.0 * k, palps=40.0 * k)
        return pose(RIG, b, front_raised(rest, 0.4 * k))
    return RigClip("Hit", L, False, sample, [(0.01, "hit_react"), (0.3, "cancel_ok")])


def stagger_clip() -> RigClip:
    L = 0.9
    rest = rest_tips()

    def sample(t: float) -> Poser:
        u = t / L
        k = _bump(u, 0.2)
        wob = math.sin(2 * math.pi * u * 2) * (1.0 - _smooth(u))
        b = Body(lift=-0.06 * k, roll=-12.0 * k + 6.0 * wob, yaw=10.0 * k, side=-0.06 * k, ahead=-0.08 * k,
                 abdomen=15.0 * k, abd_swing=20.0 * wob, palps=30.0 * k)
        tips = dict(rest)
        for f, w0 in (("2.R", 0.1), ("3.R", 0.2), ("1.L", 0.3)):
            w = (u - w0) / 0.2
            if 0 < w < 1:
                tips[f] = rest[f] + np.array([-0.05, 0.05, 0.12 * _bump(w)])
        return pose(RIG, b, tips)
    return RigClip("Stagger", L, False, sample, [(0.01, "hit_react"), (0.7, "cancel_ok")])


def _flipped(amount: float) -> Body:
    return Body(lift=-0.07 * amount + 0.25 * _bump(amount), roll=180.0 * amount, abdomen=-10.0 * amount)


def knockdown_clip() -> RigClip:
    """Thrown on its back, the legs curling and kicking in the air; held to the end."""
    L = 1.6
    fall = 0.45

    def sample(t: float) -> Poser:
        a = _smooth(t / fall)
        b = _flipped(a)
        b.side = -0.2 * a
        tips = curled(RIG, b, 0.6 * a, wiggle=a * (1.0 - _smooth((t - 1.0) / 0.5)), t=t)
        return pose(RIG, b, tips, knees_up={f: -1.0 for f in FEET} if a > 0.5 else None)
    return RigClip("Knockdown", L, False, sample, [(0.02, "hit_react"), (fall, "body_land")], {"held": True})


def get_up_clip() -> RigClip:
    """Rolled back on to its feet, the legs reaching for the ground. Also the ambush's rousing."""
    L = 0.8
    rest = rest_tips()

    def sample(t: float) -> Poser:
        a = 1.0 - _smooth(t / (0.6 * L))
        b = _flipped(a)
        b.side = -0.2 * a
        tips = curled(RIG, b, 0.6 * a)
        if a < 0.5:
            w = _smooth((0.5 - a) / 0.5)
            tips = {f: tips[f] * (1.0 - w) + rest[f] * w for f in FEET}
        return pose(RIG, b, tips, knees_up={f: -1.0 for f in FEET} if a > 0.5 else None)
    return RigClip("Get_Up", L, False, sample, [(0.6 * L, "cancel_ok")])


def death_clip() -> RigClip:
    """Killed: the legs draw in under it as it settles on its belly, the abdomen sinking last."""
    L = 1.8
    rest = rest_tips()

    def sample(t: float) -> Poser:
        u = t / L
        sink = _smooth(u / 0.5)
        curl = _smooth((u - 0.15) / 0.6)
        twitch = 0.4 * _bump((u - 0.55) / 0.35) if 0.55 < u < 0.9 else 0.0
        b = Body(lift=-(CEPH[2] - CEPH_R[2] - 0.02) * sink, pitch=-6.0 * sink, roll=5.0 * sink, abdomen=-12.0 * sink,
                 palps=-30.0 * curl, fangs=-10.0 * curl)
        tips = curled(RIG, b, 0.8 * curl, wiggle=twitch, t=t)
        for f in FEET:
            tips[f] = rest[f] * (1.0 - curl) + tips[f] * curl
            tips[f][2] = max(tips[f][2], 0.0)
        return pose(RIG, b, tips)
    return RigClip("Death", L, False, sample, [(0.02, "death_start"), (0.5 * L, "body_land")], {"held": True})


RIG = make_rig()


def build_clips() -> Dict[str, RigClip]:
    c = {
        "Idle": idle_clip(), "Idle_Combat": combat_idle_clip(),
        "Walk": gait("Walk", 1.1, 18 / FPS, 0.6, 0.12),
        "Run": gait("Run", 4.2, 9 / FPS, 0.5, 0.16, bob=0.02),
        "Walk_Back": gait("Walk_Back", 0.9, 18 / FPS, 0.6, 0.10, way=(0.0, -1.0)),
        "Strafe_L": gait("Strafe_L", 1.0, 18 / FPS, 0.6, 0.11, way=(-1.0, 0.0)),
        "Strafe_R": gait("Strafe_R", 1.0, 18 / FPS, 0.6, 0.11, way=(1.0, 0.0)),
        "Turn_L90": gait("Turn_L90", 0.0, 24 / FPS, 0.6, 0.10, turn=90.0),
        "Turn_R90": gait("Turn_R90", 0.0, 24 / FPS, 0.6, 0.10, turn=-90.0),
        "Attack_1": fang_clip(), "Attack_2": drop_clip(), "Attack_3": spit_clip(),
        "Hit": hit_clip(), "Stagger": stagger_clip(), "Knockdown": knockdown_clip(), "Get_Up": get_up_clip(),
        "Death": death_clip(),
    }
    # a strafe's speed is its sideways pace
    c["Strafe_L"].extra["speed"] = 1.0
    c["Strafe_R"].extra["speed"] = 1.0
    c["Walk_Back"].extra["speed"] = -0.9
    return c


def painter(spec, field):
    return weaver_paint(spec.skel, spec.style, field)


def hurt():
    """Where a blow lands, Blender space: the body from the fangs to the spinnerets, and the
    abdomen's bulk."""
    return [("capsule", np.array([0.0, -0.20, 0.42]), np.array([0.0, 0.20, 0.42]), 0.16),
            ("sphere", ABD, 0.27)]


def bare_scene(spec):
    return weaver_scene(spec.skel, spec.style, bare=True)
