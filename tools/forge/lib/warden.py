"""The warden: the Briarwold's sentinel treant at the Standing Moot (core:enemy/warden).

WORLD_BIBLE §8: "sentinel; treant: does not chase; enormous poise; punishes greed near shrines".
The lore: "a dead tree with a face you are imagining". So a dead oak 4.2 m high that is a body when
it moves: the trunk its body, a split at its foot its two legs on root-feet that spread over the
ground, two great limbs its arms ending in twigs for fingers, a crown of bare branches over a face
-- two hollows and a split -- you could take for knots in the bark. Moss on what faces the sky.

On lib/biped.py (WM_Warden_v1): Hips, Spine, Chest, Neck, Head (the crown), the arms and the legs.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, List

import numpy as np

from . import sdf, paint
from .anim import FPS
from .rig import rot_axis, UP, FWD, LEFT
from .creature_rig import Rig, Poser, RigClip, _u
from . import biped as bi
from . import beast_body as bb

RIG_ID = "WM_Warden_v1"
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

JOINTS = {
    "Hips": (0.0, 0.0, 1.35), "Spine": (0.0, 0.0, 1.78), "Chest": (0.0, -0.04, 2.45), "Neck": (0.0, -0.06, 3.05),
    "Head": (0.0, -0.06, 3.28), "HeadTip": (0.0, -0.04, 3.95),
    "Shoulder.L": (0.20, -0.05, 2.86), "UpperArm.L": (0.66, -0.05, 2.96), "Forearm.L": (1.12, -0.12, 2.30),
    "Hand.L": (1.22, -0.26, 1.58), "HandTip.L": (1.18, -0.44, 1.00),
    "Thigh.L": (0.30, 0.0, 1.28), "Shin.L": (0.42, -0.10, 0.74), "Foot.L": (0.46, 0.04, 0.20), "Toe.L": (0.48, -0.48, 0.05),
}


@dataclass
class WardenStyle:
    seed: int = 71

    def to_dict(self) -> dict:
        return asdict(self)


RIG = bi.make_rig(RIG_ID, JOINTS, height=4.0)


def _P(n):
    return RIG.points[n]


def _branch(sc, rng, start, direction, length, r0, depth, k=0.04):
    """A crooked branch and its forks: a tube that kinks as it goes, a fork or two off it."""
    d = _u(direction)
    pts = [start]
    p = start.copy()
    for i in range(3):
        jitter = rng.normal(0, 0.28, 3)
        d = _u(d + jitter * 0.6 + Z * 0.15)
        p = p + d * length / 3.0
        pts.append(p.copy())
    rs = [r0, r0 * 0.75, r0 * 0.5, max(r0 * 0.22, 0.008)]
    sc.union(sdf.tube_path(pts, rs), k=k * r0 / 0.1)
    if depth > 0:
        for j in range(2):
            at = pts[1 + j]
            side = _u(np.cross(d, rng.normal(0, 1, 3)))
            _branch(sc, rng, at, _u(d + side * 0.9), length * 0.5, rs[1 + j] * 0.7, depth - 1, k)


def scene(st: WardenStyle, bare: bool = False) -> sdf.Scene:
    rng = np.random.default_rng(st.seed)
    sc = sdf.Scene()
    # the trunk: from the split at its foot up through the body to where the crown breaks out
    stations = [(_P("Hips") + Z * -0.1, 0.46, 0.40), (_P("Spine"), 0.44, 0.38), (_P("Chest"), 0.48, 0.42),
                (_P("Neck"), 0.42, 0.38), (_P("Head") + Z * 0.15, 0.36, 0.33), (_P("HeadTip") - Z * 0.35, 0.24, 0.22)]
    sc.union(sdf.sweep(stations, X), k=0.1)
    # the legs: the trunk split in two, on spreading roots
    for side, sx in (("L", 1.0), ("R", -1.0)):
        th, sh, ft = _P("Thigh." + side), _P("Shin." + side), _P("Foot." + side)
        sc.union(sdf.tube_path([th + Z * 0.15 - X * sx * 0.12, th, sh, ft + Z * 0.05], [0.34, 0.3, 0.24, 0.22]), k=0.12)
        for i in range(5):
            a = math.radians(-70 + 140 * i / 4) * sx
            d = np.array([math.sin(a), -math.cos(a), 0.0])
            r0 = ft + Z * 0.02
            r1 = np.array([ft[0], ft[1], 0.06]) + d * (0.32 + 0.1 * rng.random())
            r2 = np.array([ft[0], ft[1], 0.02]) + d * (0.62 + 0.15 * rng.random()) + X * sx * 0.05
            sc.union(sdf.tube_path([r0, r1, r2], [0.12, 0.08, 0.03]), k=0.06)
    # the arms: great limbs out of the shoulders, forking at the end into twig fingers
    for side, sx in (("L", 1.0), ("R", -1.0)):
        sh, ua, fa, hd, ht = _P("Shoulder." + side), _P("UpperArm." + side), _P("Forearm." + side), _P("Hand." + side), \
            _P("HandTip." + side)
        sc.union(sdf.tube_path([sh, ua, fa, hd], [0.3, 0.24, 0.18, 0.14]), k=0.1)
        for i in range(5):
            f = (i - 2) / 2.0
            base = hd + X * f * 0.06 * sx
            tip = ht + X * f * 0.28 * sx + Y * f * 0.1 + (rng.normal(0, 0.05, 3))
            mid = 0.5 * (base + tip) + X * sx * 0.08 - Y * 0.08
            sc.union(sdf.tube_path([base, mid, tip], [0.075, 0.05, 0.012]), k=0.04)
        if not bare:
            # a few dead twigs off the forearm
            for j in range(3):
                at = ua + (fa - ua) * (0.35 + 0.25 * j)
                _branch(sc, rng, at, np.array([sx * 0.6, 0.2 * rng.normal(), 0.8]), 0.45, 0.05, 0, k=0.02)
    if not bare:
        # the crown: bare branches breaking out of the top, up and out
        top = _P("HeadTip") - Z * 0.4
        for i in range(7):
            a = 2 * math.pi * i / 7 + rng.normal(0, 0.2)
            d = np.array([math.cos(a) * 0.8, math.sin(a) * 0.6, 1.0])
            _branch(sc, rng, top + d * 0.05, d, 0.9 + 0.4 * rng.random(), 0.12, 1)
    # the face: a brow, two hollows and the split of a mouth in the bark
    fc = _P("Neck") + np.array([0.0, -0.36, 0.05])
    sc.union(sdf.capsule(fc + np.array([-0.2, 0.0, 0.14]), fc + np.array([0.2, 0.0, 0.14]), 0.08), k=0.08)
    sc.union(sdf.ellipsoid(fc + np.array([0.0, -0.06, -0.05]), np.array([0.06, 0.08, 0.12])), k=0.06)
    for sx in (1.0, -1.0):
        sc.subtract(sdf.ellipsoid(fc + np.array([sx * 0.12, 0.02, 0.05]), np.array([0.07, 0.08, 0.055])), k=0.03)
    sc.subtract(sdf.ellipsoid(fc + np.array([0.0, 0.02, -0.32]), np.array([0.16, 0.08, 0.035])), k=0.03)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    if bare:
        return sc
    n1 = paint.Noise(st.seed + 3, 64)

    def disp(P):
        # bark: deep furrows running up the trunk and along the limbs, broken into plates
        furrow = n1.fbm(P * np.array([2.2, 2.2, 0.35]), freq=6.0, octaves=3)
        return 0.035 * (bb.sm(0.35, 0.65, furrow) - 0.5) + 0.01 * (n1.at(P, 18.0) - 0.5)
    return bb.Displaced(sc, disp, 0.04)


def face_centre():
    return _P("Neck") + np.array([0.0, -0.36, 0.05])


def regions(P: np.ndarray, st: WardenStyle) -> Dict[str, np.ndarray]:
    n1 = paint.Noise(st.seed + 3, 64)
    R = {}
    furrow = n1.fbm(P * np.array([2.2, 2.2, 0.35]), freq=6.0, octaves=3)
    R["furrow"] = 1.0 - bb.sm(0.3, 0.5, furrow)
    fc = face_centre()
    R["hollow"] = np.zeros(len(P))
    for c, r in ((fc + np.array([0.12, 0.02, 0.05]), 0.08), (fc + np.array([-0.12, 0.02, 0.05]), 0.08),
                 (fc + np.array([0.0, 0.02, -0.32]), 0.12)):
        R["hollow"] = np.maximum(R["hollow"], 1.0 - bb.sm(r * 0.6, r * 1.2, np.linalg.norm(P - c, axis=1)))
    R["roots"] = 1.0 - bb.sm(0.15, 0.4, P[:, 2])
    return R


def painter(spec, field):
    st = spec.style
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 5, 64)
    bark = np.array([0.30, 0.27, 0.22])
    dark = np.array([0.09, 0.08, 0.06])
    moss = np.array([0.30, 0.38, 0.15])
    lichen = np.array([0.62, 0.66, 0.52])
    ember = np.array([0.35, 0.12, 0.03])

    def albedo(P, nrm):
        R = regions(P, st)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.15, samples=5, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=1.2, octaves=3)
        c = np.broadcast_to(bark, (len(P), 3)).copy() * (0.8 + 0.4 * big)[:, None]
        c = paint.mix(c, dark, 0.75 * R["furrow"])
        # moss: thick on what faces the sky and on the north side, in the furrows' shelter
        mossy = bb.sm(0.1, 0.6, up + 0.4 * (-nrm[:, 1])) * bb.sm(0.45, 0.6, n2.fbm(P, freq=2.5, octaves=3))
        c = paint.mix(c, moss * (0.8 + 0.4 * n1.at(P, 20.0))[:, None], 0.8 * mossy)
        c = paint.mix(c, lichen, 0.7 * paint.dots(P, 0.12, 0.25, 0.02, 0.05, st.seed) * (1.0 - mossy) * (1.0 - R["furrow"]))
        c = paint.mix(c, np.array([0.22, 0.18, 0.13]), 0.5 * R["roots"])
        c = paint.mix(c, dark * 0.4, R["hollow"])
        deep = 1.0 - bb.sm(0.0, 0.06, np.min(np.stack([np.linalg.norm(P - (face_centre() + np.array([s * 0.12, 0.06, 0.05])), axis=1)
                                                       for s in (1.0, -1.0)]), axis=0))
        c = paint.mix(c, ember, 0.8 * deep)
        v = 0.45 + 0.55 * occ
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = regions(P, st)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.15, samples=5, strength=1.2)
        return np.stack([0.4 + 0.6 * occ, np.full(len(P), 0.93), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        R = regions(P, st)
        return 1.0 - R["furrow"] + 0.3 * n2.fbm(P * np.array([3.0, 3.0, 0.5]), freq=12.0, octaves=2)

    return albedo, orm, height


def bare_scene(spec):
    return scene(spec.style, bare=True)


def hurt():
    return [("capsule", np.array([0.0, 0.0, 0.7]), np.array([0.0, -0.05, 3.2]), 0.55),
            ("sphere", face_centre(), 0.45)]


# --------------------------------------------------------------------------------------
# clips
# --------------------------------------------------------------------------------------

S, B = bi.smooth, bi.bump


def stand(**kw) -> bi.BPose:
    bp = bi.BPose(lean=2.0, bend=3.0)
    for s in bi.SIDES:
        bp.hands[s] = np.zeros(3)
    for k_, v in kw.items():
        setattr(bp, k_, v)
    return bp


def idle_clip() -> RigClip:
    """A dead tree in a wind: the crown swaying, a creak in the limbs, nothing else."""
    L = 6.0

    def sample(t: float) -> Poser:
        u = t / L
        w = math.sin(2 * math.pi * u) + 0.4 * math.sin(2 * math.pi * 3 * u)
        bp = stand(side_bend=1.5 * w, bend=3.0 + 1.0 * math.sin(2 * math.pi * 2 * u), neck=2.0 * w, head_turn=3.0 * w)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([0.03 * sx * w, 0.02 * w, 0.0])
        return bi.pose(RIG, bp)
    return RigClip("Idle", L, True, sample)


def combat_idle_clip() -> RigClip:
    L = 3.0

    def sample(t: float) -> Poser:
        u = t / L
        w = math.sin(2 * math.pi * u)
        bp = stand(bend=10.0, lean=4.0, lift=-0.08, side_bend=2.0 * w, neck=8.0)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([sx * 0.2, -0.4, 0.45 + 0.04 * w])
            bp.elbow[s] = np.array([sx * 1.0, 0.5, 0.2])
        bp.feet = {"L": _P("Foot.L") + np.array([0.05, -0.15, 0.0]), "R": _P("Foot.R") + np.array([-0.05, 0.15, 0.0])}
        return bi.pose(RIG, bp)
    return RigClip("Idle_Combat", L, True, sample)


def root_sweep_clip() -> RigClip:
    """Attack_1: the right limb drawn far back and low, held, and swept round across the ground in
    front of it like a fallen bough swung by its end."""
    L = 2.0
    cocked, strike, hs, he, ok = 0.75, 0.9, 1.0, 1.24, 1.55

    def sample(t: float) -> Poser:
        wind = S(t / cocked) * (1.0 - S((t - cocked) / (he - cocked)))
        go = S((t - cocked) / (he - cocked)) * (1.0 - S((t - he) / (L - he)))
        bp = stand(bend=8.0 + 18.0 * go, lean=4.0 + 8.0 * go, twist=35.0 * wind - 40.0 * go, yaw=10.0 * wind - 12.0 * go,
                   lift=-0.15 * (wind + go), side_bend=6.0 * go)
        start = np.array([0.6, 0.8, -0.2])
        mid = np.array([0.4, -1.4, -0.95])
        end = np.array([-1.4, -0.6, -0.8])
        if go < 0.5:
            a_ = 2.0 * go
            pos = start * wind * (1.0 - a_) + mid * a_
        else:
            k_ = (go - 0.5) * 2.0
            pos = mid * (1.0 - k_) + end * k_
        bp.hands["R"] = pos
        bp.elbow["R"] = np.array([-1.0, 0.6, 0.2])
        bp.hands["L"] = np.array([0.1, -0.2 * go, 0.2])
        bp.feet = {"R": _P("Foot.R") + np.array([0.0, 0.2 * wind - 0.15 * go, 0.0]), "L": _P("Foot.L")}
        return bi.pose(RIG, bp)
    return RigClip("Attack_1", L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def reckoning_clip() -> RigClip:
    """Attack_2, the reckoning: both limbs lifted high and wide over the crown, the whole tree
    leaning back on its roots; then down, both limbs driven into the ground before it, and the
    ground answers in a ring (`hit_start`)."""
    L = 2.6
    cocked, strike, hs, he, ok = 1.2, 1.42, 1.55, 1.77, 2.1

    def sample(t: float) -> Poser:
        up = S(t / cocked) * (1.0 - S((t - cocked - 0.1) / (hs - cocked - 0.1)))
        down = S((t - cocked - 0.1) / (hs - cocked - 0.1)) * (1.0 - S((t - he - 0.2) / (L - he - 0.2)))
        bp = stand(lean=-8.0 * up + 22.0 * down, bend=-6.0 * up + 22.0 * down, lift=0.05 * up - 0.4 * down,
                   neck=-15.0 * up + 10.0 * down)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            hi = np.array([sx * 0.3, 0.2, 2.1])
            lo = np.array([-sx * 0.45, -1.4, -0.6])
            bp.hands[s] = hi * up + lo * down
            bp.elbow[s] = np.array([sx * 1.0, 0.5, 0.4 * up])
        bp.feet = {"L": _P("Foot.L") + np.array([0.0, -0.1 * down, 0.0]), "R": _P("Foot.R") + np.array([0.0, 0.1 * down, 0.0])}
        return bi.pose(RIG, bp)
    return RigClip("Attack_2", L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def hit_clip() -> RigClip:
    L = 0.6

    def sample(t: float) -> Poser:
        k_ = B(t / L, 0.25)
        bp = stand(lean=2.0 - 6.0 * k_, bend=3.0 - 4.0 * k_, side_bend=4.0 * k_, neck=-8.0 * k_)
        return bi.pose(RIG, bp)
    return RigClip("Hit", L, False, sample, [(0.01, "hit_react"), (0.4, "cancel_ok")])


def stagger_clip() -> RigClip:
    L = 1.1

    def sample(t: float) -> Poser:
        u = t / L
        k_ = B(u, 0.3)
        wob = math.sin(2 * math.pi * u * 1.5) * (1.0 - S(u))
        bp = stand(lean=2.0 - 10.0 * k_, side_bend=-8.0 * k_ + 4.0 * wob, roll=-4.0 * k_, ahead=-0.12 * k_, lift=-0.06 * k_,
                   neck=-15.0 * k_)
        bp.feet = {"L": _P("Foot.L") + np.array([0.0, 0.25 * S((u - 0.15) / 0.3) * (1.0 - S((u - 0.7) / 0.3)),
                                                 0.15 * B((u - 0.15) / 0.3) if 0.15 < u < 0.45 else 0.0]), "R": _P("Foot.R")}
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([sx * 0.5 * k_, 0.2 * k_, 0.5 * k_])
        return bi.pose(RIG, bp)
    return RigClip("Stagger", L, False, sample, [(0.01, "hit_react"), (0.85, "cancel_ok")])


def _fallen(amount: float, forward: bool) -> bi.BPose:
    """The tree come down on its back (or its face): stiff, toppled from its roots."""
    sgn = 1.0 if forward else -1.0
    bp = stand(lean=sgn * 84.0 * amount, lift=0.34 * amount, ahead=sgn * 0.3 * amount)
    bp.pivot = np.array([0.0, 0.0, 0.3])
    for s, sx in (("L", 1.0), ("R", -1.0)):
        bp.hands[s] = np.array([sx * 0.3 * amount, sgn * 0.0, 0.2 * amount])
        bp.feet[s] = _P("Foot." + s) + np.array([0.0, -sgn * 0.5 * amount, 0.15 * amount])
        bp.knee[s] = np.array([0.0, -sgn, 0.4])
    return bp


def knockdown_clip() -> RigClip:
    """Thrown over backwards: it goes down slowly, as a tree does, and lies with its limbs up."""
    L = 1.6
    fall = 0.9

    def sample(t: float) -> Poser:
        w = S(t / fall) ** 1.6
        return bi.pose(RIG, _fallen(w, forward=False))
    return RigClip("Knockdown", L, False, sample, [(0.02, "hit_react"), (fall, "body_land")], {"held": True})


def get_up_clip() -> RigClip:
    L = 0.9

    def sample(t: float) -> Poser:
        w = 1.0 - S(t / L)
        return bi.pose(RIG, _fallen(w, forward=False))
    return RigClip("Get_Up", L, False, sample, [(0.7 * L, "cancel_ok")])


def death_clip() -> RigClip:
    """Felled: it stiffens, creaks, and goes over on its face all in one piece, slow and then fast,
    and lies where it fell. The last frame is held."""
    L = 2.6

    def sample(t: float) -> Poser:
        u = t / L
        lean = S((u - 0.2) / 0.6) ** 2.2
        bp = _fallen(lean, forward=True)
        bp.side_bend += 3.0 * math.sin(2 * math.pi * u * 2) * (1.0 - lean) * S(u / 0.2)
        return bi.pose(RIG, bp)
    return RigClip("Death", L, False, sample, [(0.02, "death_start"), (0.8 * L, "body_land")], {"held": True})


def build_clips() -> Dict[str, RigClip]:
    def heavy(bp, ph):
        bp.bend += 4.0
    return {
        "Idle": idle_clip(), "Idle_Combat": combat_idle_clip(),
        "Walk": bi.walk(RIG, "Walk", 0.9, 40 / FPS, lift=0.15, bob=0.05, sway=0.1, arm_swing=0.15, lean=4.0, extra_fn=heavy),
        "Run": bi.walk(RIG, "Run", 1.6, 30 / FPS, duty=0.55, lift=0.2, bob=0.08, sway=0.12, arm_swing=0.25, lean=8.0,
                       extra_fn=heavy),
        "Walk_Back": bi.walk(RIG, "Walk_Back", 0.6, 44 / FPS, lift=0.12, way=(0.0, -1.0)),
        "Strafe_L": bi.walk(RIG, "Strafe_L", 0.5, 44 / FPS, lift=0.12, way=(-1.0, 0.0), stance_w=1.1),
        "Strafe_R": bi.walk(RIG, "Strafe_R", 0.5, 44 / FPS, lift=0.12, way=(1.0, 0.0), stance_w=1.1),
        "Turn_L90": bi.walk(RIG, "Turn_L90", 0.0, 44 / FPS, lift=0.12, turn=60.0),
        "Turn_R90": bi.walk(RIG, "Turn_R90", 0.0, 44 / FPS, lift=0.12, turn=-60.0),
        "Attack_1": root_sweep_clip(), "Attack_2": reckoning_clip(),
        "Hit": hit_clip(), "Stagger": stagger_clip(), "Knockdown": knockdown_clip(), "Get_Up": get_up_clip(),
        "Death": death_clip(),
    }
