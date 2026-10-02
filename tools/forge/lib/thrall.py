"""The stone-thrall: Skerrow's giant bone and mountain rock (core:enemy/stone_thrall), and the King.

WORLD_BIBLE §8: "brute: giant bone and rock walking; limbs can be broken off". A giant's skeleton
-- the skull with its brow and its teeth, the spine standing out of the back, the ribs round a
cairn of packed stones, the long bones of the arms and the legs -- with the mountain built back on
to it: boulders on the shoulders, slabs on the thighs and shins, each fist a boulder gripped by the
finger bones. It stands 3.4 m hunched, its knuckles at its knees.

The arms and the lower left leg are their own meshes (Body, ArmR, ArmL, LegL): the def's limbs come
off in that order (right arm, left arm, left leg) and CreatureModel hides each and throws it down
as it goes. With the leg gone it has no arms either, and it comes on along the ground: Crawl,
Crawl_Idle, Crawl_Death and Attack_5, the crawling sweep.
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
from . import biped as bi
from . import beast_body as bb

RIG_ID = "WM_Thrall_v1"
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

JOINTS = {
    "Hips": (0.0, 0.10, 1.25), "Spine": (0.0, 0.13, 1.58), "Chest": (0.0, 0.06, 2.02), "Neck": (0.0, -0.22, 2.58),
    "Head": (0.0, -0.40, 2.70), "HeadTip": (0.0, -0.80, 2.78), "Jaw": (0.0, -0.50, 2.60), "JawTip": (0.0, -0.80, 2.46),
    "Shoulder.L": (0.16, -0.04, 2.42), "UpperArm.L": (0.64, -0.04, 2.44), "Forearm.L": (0.80, 0.04, 1.76),
    "Hand.L": (0.82, -0.16, 1.08), "HandTip.L": (0.82, -0.28, 0.64),
    "Thigh.L": (0.30, 0.12, 1.20), "Shin.L": (0.36, -0.02, 0.66), "Foot.L": (0.38, 0.12, 0.14), "Toe.L": (0.38, -0.34, 0.04),
}
PARTS = ["Body", "ArmR", "ArmL", "LegL"]
# the def's limbs, in the order they come off, and the mesh each is
LIMBS = [{"index": 0, "part": "ArmR"}, {"index": 1, "part": "ArmL"}, {"index": 2, "part": "LegL", "crawl": True}]


@dataclass
class ThrallStyle:
    king: bool = False
    seed: int = 31

    def to_dict(self) -> dict:
        return asdict(self)


def make_rig() -> Rig:
    return bi.make_rig(RIG_ID, JOINTS, height=3.0)


RIG = make_rig()


def _P(n: str) -> np.ndarray:
    return RIG.points[n]


# --------------------------------------------------------------------------------------
# body: bone and rock, in parts
# --------------------------------------------------------------------------------------

def _rock(c, r, rng, k=0.0, sharp=0.25) -> sdf.Prim:
    """A boulder: a rounded box turned at random, its corners knocked off."""
    c = np.asarray(c, float)
    r = np.asarray(r, float)
    a = rng.uniform(0, 2 * math.pi, 3)
    R = rot_axis(X, a[0]) @ rot_axis(Y, a[1]) @ rot_axis(Z, a[2])
    return sdf.box(c, r * (1.0 - sharp * 0.5), rot=R, round_r=float(r.min()) * sharp, k=k)


def _long_bone(a, b, r0, r1, knob=1.6) -> List[sdf.Prim]:
    """A long bone: the shaft, a knob at each end."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    return [sdf.round_cone(a, b, r0, r1), sdf.sphere(a, r0 * knob), sdf.sphere(b, r1 * knob)]


def bone_scene_parts(st: ThrallStyle) -> Dict[str, sdf.Scene]:
    """The skeleton alone, part by part (for the painter to know bone from rock, and the meshes)."""
    rng = np.random.default_rng(st.seed)
    out = {p: sdf.Scene() for p in PARTS}
    B = out["Body"]
    # the skull: a giant's, the brow heavy over deep sockets, a broad flat face
    h0, h1 = _P("Head"), _P("HeadTip")
    hd = _u(h1 - h0)
    sk = h0 + hd * 0.17 + Z * 0.06
    B.union(sdf.ellipsoid(sk, np.array([0.2, 0.24, 0.2])))
    # the neck: vertebrae from the top of the back up under the skull
    neck = [_P("Chest") + np.array([0.0, 0.2, 0.42]), _P("Neck") + np.array([0.0, 0.08, 0.02]), h0 + np.array([0.0, 0.06, -0.02])]
    for q in sdf._catmull_rom(np.array(neck), np.linspace(0, 2, 6)):
        B.union(sdf.ellipsoid(q, np.array([0.08, 0.07, 0.06])), k=0.03)
    B.union(sdf.tube_path(neck, [0.05, 0.05, 0.05]), k=0.03)
    B.union(sdf.capsule(h0 + hd * 0.30 + Z * 0.08 + X * 0.1, h0 + hd * 0.30 + Z * 0.08 - X * 0.1, 0.06), k=0.05)
    B.union(sdf.ellipsoid(h0 + hd * 0.33 - Z * 0.03, np.array([0.13, 0.1, 0.12])), k=0.06)
    for sx in (1.0, -1.0):
        B.subtract(sdf.sphere(h0 + hd * 0.38 + Z * 0.03 + X * sx * 0.065, 0.05), k=0.02)
    B.subtract(sdf.ellipsoid(h0 + hd * 0.42 - Z * 0.06, np.array([0.03, 0.04, 0.035])), k=0.01)  # the nose's hole
    # the jaw and the teeth
    j0, j1 = _P("Jaw"), _P("JawTip")
    for sx in (1.0, -1.0):
        B.union(sdf.capsule(j0 + X * sx * 0.12, j1 + X * sx * 0.07 + Z * 0.01, 0.035), k=0.03)
    B.union(sdf.capsule(j1 + X * 0.07, j1 - X * 0.07, 0.04), k=0.03)
    for i in range(7):
        f = (i - 3) / 3.0
        base = h0 + hd * 0.33 - Z * 0.11 + X * f * 0.09 + hd * (0.06 * (1 - abs(f)))
        B.union(sdf.round_cone(base, base - Z * 0.05, 0.016, 0.01), k=0.006)
        lb = j1 + Z * 0.04 + X * f * 0.07 - hd * 0.02 * abs(f)
        B.union(sdf.round_cone(lb, lb + Z * 0.04, 0.014, 0.009), k=0.006)
    # the spine standing out of the back, neck to tail
    spine = [_P("Neck") + np.array([0.0, 0.1, 0.0]), _P("Chest") + np.array([0.0, 0.22, 0.12]),
             _P("Spine") + np.array([0.0, 0.25, 0.0]), _P("Hips") + np.array([0.0, 0.22, -0.02])]
    tt = np.linspace(0, len(spine) - 1, 14)
    pts = sdf._catmull_rom(np.array(spine), tt)
    for i, q in enumerate(pts):
        B.union(sdf.ellipsoid(q, np.array([0.07, 0.05, 0.05])), k=0.02)
        B.union(sdf.round_cone(q, q + np.array([0.0, 0.10, 0.02]), 0.03, 0.012), k=0.01)
    # the ribs: hoops from the spine round the chest, open at the front
    ch = _P("Chest")
    for i, (z, w) in enumerate(((2.32, 0.42), (2.18, 0.46), (2.04, 0.46), (1.9, 0.42), (1.77, 0.36))):
        for sx in (1.0, -1.0):
            ribs = [np.array([sx * 0.06, ch[1] + 0.22, z + 0.05]), np.array([sx * w * 0.8, ch[1] + 0.18, z]),
                    np.array([sx * w, ch[1] - 0.05, z - 0.08]), np.array([sx * w * 0.75, ch[1] - 0.30, z - 0.14]),
                    np.array([sx * w * 0.3, ch[1] - 0.38, z - 0.16])]
            B.union(sdf.tube_path(ribs, [0.04, 0.045, 0.045, 0.04, 0.03]), k=0.015)
    # the pelvis: two wings of bone over the hips
    for sx in (1.0, -1.0):
        B.union(sdf.ellipsoid(_P("Hips") + np.array([sx * 0.22, 0.05, 0.12]), np.array([0.07, 0.2, 0.18]),
                              rot=rot_axis(Y, sx * 0.4)), k=0.04)
    # the collar bones
    for sx in (1.0, -1.0):
        B.union(sdf.capsule(_P("Neck") + np.array([sx * 0.08, 0.05, -0.12]), _P("UpperArm.L") * np.array([sx, 1, 1]), 0.05), k=0.03)
    # the arms' long bones
    for side, part in (("L", "ArmL"), ("R", "ArmR")):
        A = out[part]
        A.union(_long_bone(_P("UpperArm." + side), _P("Forearm." + side), 0.075, 0.065))
        for d in (0.05, -0.05):
            A.union(sdf.round_cone(_P("Forearm." + side) + X * d * 0.6, _P("Hand." + side) + X * d, 0.05, 0.045), k=0.02)
        # the fingers' bones round the fist's boulder
        hb_ = _P("Hand." + side)
        ht = _P("HandTip." + side)
        for i in range(4):
            f = (i - 1.5) / 1.5
            a0 = hb_ + X * f * 0.12 - Y * 0.10
            a1 = ht + X * f * 0.14 - Y * 0.20 + Z * 0.1
            a2 = ht + X * f * 0.12 + Y * 0.02 - Z * 0.02
            A.union(sdf.tube_path([a0, a1, a2], [0.04, 0.035, 0.03]), k=0.01)
    # the legs: the right whole in the body, the left thigh in the body and its shin and foot apart
    for side in ("L", "R"):
        B.union(_long_bone(_P("Thigh." + side), _P("Shin." + side), 0.09, 0.075))
        lower = B if side == "R" else out["LegL"]
        lower.union(_long_bone(_P("Shin." + side) - Z * 0.02, _P("Foot." + side), 0.075, 0.06))
        f0, f1 = _P("Foot." + side), _P("Toe." + side)
        for i in range(4):
            f = (i - 1.5) / 1.5
            lower.union(sdf.capsule(f0 + X * f * 0.07 - Z * 0.06, f1 + X * f * 0.12 + Z * 0.0, 0.032), k=0.01)
    return out


def rock_scene_parts(st: ThrallStyle) -> Dict[str, sdf.Scene]:
    rng = np.random.default_rng(st.seed + 1)
    out = {p: sdf.Scene() for p in PARTS}
    B = out["Body"]
    ch = _P("Chest")
    # the cairn in the ribs: a heap of stones filling the chest and the belly
    for c, r in (((0.0, ch[1] - 0.02, 2.08), (0.36, 0.30, 0.34)), ((0.0, ch[1] + 0.02, 1.72), (0.30, 0.26, 0.24)),
                 ((0.18, ch[1] - 0.15, 1.95), (0.16, 0.14, 0.18)), ((-0.2, ch[1] - 0.12, 2.15), (0.15, 0.16, 0.14)),
                 ((0.0, 0.10, 1.42), (0.26, 0.22, 0.2))):
        B.union(_rock(c, r, rng, k=0.04))
    # the shoulders: a boulder on each, the arm hung under it
    for sx in (1.0, -1.0):
        sh = _P("UpperArm.L") * np.array([sx, 1, 1])
        B.union(_rock(sh + np.array([sx * 0.02, 0.02, 0.16]), np.array([0.26, 0.24, 0.2]), rng, k=0.05, sharp=0.35))
        B.union(_rock(sh + np.array([-sx * 0.22, 0.12, 0.10]), np.array([0.16, 0.15, 0.14]), rng, k=0.05))
    # the hump: a boulder bedded between the shoulders, over the top of the spine
    B.union(_rock(np.array([0.0, 0.32, 2.30]), np.array([0.34, 0.26, 0.28]), rng, k=0.06, sharp=0.35))
    B.union(_rock(np.array([0.12, 0.36, 1.98]), np.array([0.2, 0.18, 0.2]), rng, k=0.05))
    # stones packed under the jaw, down the throat
    B.union(_rock(_P("Neck") + np.array([0.0, -0.08, -0.1]), np.array([0.14, 0.12, 0.14]), rng, k=0.04))
    # a slab on the brow and the back of the skull, as if the mountain had set it there
    h0, h1 = _P("Head"), _P("HeadTip")
    B.union(_rock(h0 + _u(h1 - h0) * 0.05 + Z * 0.17, np.array([0.16, 0.14, 0.07]), rng, k=0.03))
    # the hips and the thighs
    for sx in (1.0, -1.0):
        th, sn = _P("Thigh.L") * np.array([sx, 1, 1]), _P("Shin.L") * np.array([sx, 1, 1])
        B.union(_rock(0.55 * th + 0.45 * sn + np.array([sx * 0.04, 0.0, 0.0]), np.array([0.17, 0.2, 0.25]), rng, k=0.05))
        B.union(_rock(th + np.array([sx * 0.08, 0.06, 0.08]), np.array([0.16, 0.18, 0.12]), rng, k=0.05))
    # the shins and the feet: slabs bound to the bone, a flat stone under each foot
    for side, sx in (("L", 1.0), ("R", -1.0)):
        lower = B if side == "R" else out["LegL"]
        sn, ft, to = _P("Shin." + side), _P("Foot." + side), _P("Toe." + side)
        lower.union(_rock(0.5 * sn + 0.5 * ft + np.array([0.0, -0.06, 0.02]), np.array([0.13, 0.11, 0.2]), rng, k=0.04))
        lower.union(_rock(0.5 * (ft + to) + np.array([0.0, 0.04, -0.03]), np.array([0.17, 0.26, 0.07]), rng, k=0.03, sharp=0.4))
    # the arms: stones bound round the upper arm and the forearm, and the fist a boulder
    for side, part in (("L", "ArmL"), ("R", "ArmR")):
        A = out[part]
        ua, fa, hd, ht = _P("UpperArm." + side), _P("Forearm." + side), _P("Hand." + side), _P("HandTip." + side)
        A.union(_rock(0.5 * ua + 0.5 * fa, np.array([0.15, 0.15, 0.22]), rng, k=0.04))
        A.union(_rock(0.45 * fa + 0.55 * hd, np.array([0.12, 0.13, 0.18]), rng, k=0.04))
        A.union(_rock(0.4 * hd + 0.6 * ht + np.array([0.0, -0.04, 0.0]), np.array([0.2, 0.22, 0.22]), rng, k=0.04, sharp=0.4))
    if st.king:
        # the King: a crown of kingbone, long bony spines rising from the skull and the shoulders
        for i in range(7):
            a = (i - 3) / 3.0
            base = h0 + _u(h1 - h0) * 0.12 + Z * 0.15 + X * a * 0.14
            tip = base + _u(np.array([a * 0.5, 0.25, 1.0])) * (0.42 - 0.12 * abs(a))
            B.union(sdf.round_cone(base, tip, 0.045, 0.01), k=0.03)
    return out


def scene_parts(st: ThrallStyle) -> Dict[str, sdf.Scene]:
    bones = bone_scene_parts(st)
    rocks = rock_scene_parts(st)
    n1 = paint.Noise(st.seed + 5, 64)
    rock_fields = {p: rocks[p] for p in PARTS}
    out = {}
    for p in PARTS:
        sc = sdf.Scene()
        sc.prims = list(bones[p].prims) + [q for q in rocks[p].prims]
        sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
        rk = rock_fields[p]

        def disp(P, rk=rk):
            # the rock's face: chipped and fractured; the bone's: pitted
            d_rock = rk.eval(P) if rk.prims else np.full(len(P), 1.0)
            on_rock = 1.0 - bb.sm(0.0, 0.03, d_rock)
            F = bb._cells(P, 7.0, st.seed)
            facet = 0.02 * (bb.sm(0.2, 0.7, F) - 0.5)
            pit = 0.004 * (n1.fbm(P, freq=30.0, octaves=2) - 0.5)
            return on_rock * (facet + 0.008 * (n1.fbm(P, freq=12.0, octaves=3) - 0.5)) + (1.0 - on_rock) * pit
        out[p] = bb.Displaced(sc, disp, 0.02)
    return out


def regions(P: np.ndarray, st: ThrallStyle, bone_fields: Dict[str, sdf.Scene]) -> Dict[str, np.ndarray]:
    d_bone = np.full(len(P), 9.0)
    for p in PARTS:
        if bone_fields[p].prims:
            d_bone = np.minimum(d_bone, bone_fields[p].near(0.05).eval(P))
    R = {"bone": 1.0 - bb.sm(0.004, 0.03, d_bone)}
    h0, h1 = _P("Head"), _P("HeadTip")
    hd = _u(h1 - h0)
    R["socket"] = np.zeros(len(P))
    for sx in (1.0, -1.0):
        c = h0 + hd * 0.38 + Z * 0.03 + X * sx * 0.065
        R["socket"] = np.maximum(R["socket"], 1.0 - bb.sm(0.04, 0.065, np.linalg.norm(P - c, axis=1)))
    R["low"] = 1.0 - bb.sm(0.0, 0.45, P[:, 2])
    return R


def thrall_paint(spec, field: sdf.SampledField):
    st = spec.style
    bones = bone_scene_parts(st)
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 4, 64)
    rock = np.array([0.50, 0.48, 0.44])            # the def's #8c8578, a shade down for the light
    rock_dark = np.array([0.26, 0.25, 0.24])
    lichen = np.array([0.62, 0.62, 0.44])
    lichen2 = np.array([0.72, 0.52, 0.24])
    bone = np.array([0.78, 0.73, 0.62]) if not st.king else np.array([0.84, 0.80, 0.68])
    bone_dark = np.array([0.42, 0.38, 0.30])
    if st.king:
        rock = np.array([0.44, 0.42, 0.38])

    def albedo(P, nrm):
        R = regions(P, st, bones)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.12, samples=5, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=1.6, octaves=3)
        grain = n2.fbm(P, freq=14.0, octaves=3)
        c = np.broadcast_to(rock, (len(P), 3)).copy() * (0.8 + 0.35 * big)[:, None]
        # the stone: strata, cracks dark, the faces that see the sky paler and lichened
        strata = 0.5 + 0.5 * np.sin(P[:, 2] * 22.0 + 3.0 * n1.at(P, 3.0))
        c = c * (0.88 + 0.16 * strata)[:, None]
        F = bb._cells(P, 7.0, st.seed)
        c = paint.mix(c, rock_dark, 0.7 * bb.sm(0.55, 0.75, F))
        lich = bb.sm(0.55, 0.7, n2.fbm(P, freq=5.0, octaves=3)) * bb.sm(0.1, 0.7, up)
        c = paint.mix(c, lichen, 0.6 * lich)
        c = paint.mix(c, lichen2, 0.5 * lich * bb.sm(0.6, 0.8, n1.at(P, 22.0)))
        # the bone: old ivory, darker in its grooves and where the ground has had it
        bc = bone * (0.85 + 0.25 * grain)[:, None]
        bc = paint.mix(bc, bone_dark, 0.5 * (1.0 - occ) + 0.3 * R["low"])
        c = paint.mix(c, bc, R["bone"])
        c = paint.mix(c, np.array([0.05, 0.045, 0.04]), R["socket"])
        c = paint.mix(c, np.array([0.30, 0.26, 0.20]), 0.4 * R["low"] * (1.0 - R["bone"]))
        v = 0.45 + 0.55 * occ
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = regions(P, st, bones)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.12, samples=5, strength=1.2)
        rough = 0.9 - 0.25 * R["bone"]
        return np.stack([0.4 + 0.6 * occ, rough, np.zeros(len(P))], axis=1)

    def height(P, nrm):
        R = regions(P, st, bones)
        F = bb._cells(P, 7.0, st.seed)
        return (1.0 - R["bone"]) * (0.6 * (1.0 - bb.sm(0.5, 0.8, F)) + 0.3 * n2.fbm(P, freq=20.0, octaves=3)) \
            + R["bone"] * 0.3 * n1.fbm(P * np.array([1.0, 1.0, 0.3]), freq=40.0, octaves=2)

    return albedo, orm, height


def painter(spec, field):
    return thrall_paint(spec, field)


def hurt():
    return [("capsule", np.array([0.0, 0.02, 1.2]), np.array([0.0, -0.1, 2.45]), 0.55),
            ("sphere", _P("Head") + np.array([0.0, -0.15, 0.05]), 0.28)]


# --------------------------------------------------------------------------------------
# clips
# --------------------------------------------------------------------------------------

S, B = bi.smooth, bi.bump


def stand(**kw) -> bi.BPose:
    bp = bi.BPose(lean=6.0, bend=6.0, neck=8.0, head=6.0)
    for k, v in kw.items():
        setattr(bp, k, v)
    return bp


def _hips_xf(bp: bi.BPose):
    R = rot_axis(UP, math.radians(bp.yaw)) @ rot_axis(LEFT, math.radians(bp.lean)) @ rot_axis(FWD, math.radians(-bp.roll))
    hb = RIG.bones["Hips"]
    pv = hb.head if bp.pivot is None else np.asarray(bp.pivot, float)
    off = np.array([bp.side, -bp.ahead, bp.lift])
    return lambda p: pv + R @ (np.asarray(p, float) - pv) + off


def idle_clip() -> RigClip:
    L = 4.0

    def sample(t: float) -> Poser:
        u = t / L
        b = math.sin(2 * math.pi * u * 2)
        bp = stand(lift=-0.01 + 0.01 * b, bend=6.0 + 2.0 * b, head_turn=12.0 * math.sin(2 * math.pi * u),
                   jaw=3.0 + 3.0 * max(0.0, b))
        for s, sg in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([0.0, 0.02 * b, 0.02 * b])
        return bi.pose(RIG, bp)
    return RigClip("Idle", L, True, sample)


def combat_idle_clip() -> RigClip:
    L = 2.4

    def sample(t: float) -> Poser:
        u = t / L
        b = math.sin(2 * math.pi * u)
        bp = stand(lift=-0.12, lean=12.0, bend=10.0, side=0.05 * b, roll=2.0 * b, neck=-14.0, jaw=8.0)
        bp.feet = {"L": _P("Foot.L") + np.array([0.08, -0.12, 0.0]), "R": _P("Foot.R") + np.array([-0.08, 0.14, 0.0])}
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([sx * 0.15, -0.25, 0.25 + 0.03 * b])
            bp.fist[s] = 10.0
        return bi.pose(RIG, bp)
    return RigClip("Idle_Combat", L, True, sample)


def hammerfall_clip() -> RigClip:
    """Attack_1: both fists raised high over the skull, held, and brought down on the ground in
    front of it in one blow; the ground takes it at `hit_start`."""
    L = 1.7
    cocked, strike, hs, he, ok = 0.62, 0.76, 0.86, 1.02, 1.32

    def sample(t: float) -> Poser:
        up = S(t / cocked) * (1.0 - S((t - cocked - 0.04) / (hs - cocked - 0.04)))
        down = S((t - cocked) / (hs - cocked)) * (1.0 - S((t - he - 0.1) / (L - he - 0.1)))
        bp = stand(lift=0.04 * up - 0.28 * down, lean=-8.0 * up + 30.0 * down, bend=-12.0 * up + 22.0 * down,
                   neck=-20.0 * up + 6.0 * down, jaw=20.0 * up + 10.0 * down)
        bp.feet = {"L": _P("Foot.L") + np.array([0.0, -0.18 * (up + down) * 0.7, 0.0]), "R": _P("Foot.R")}
        for s, sx in (("L", 1.0), ("R", -1.0)):
            hi = np.array([-sx * 0.55, -0.15, 1.75])
            lo = np.array([-sx * 0.6, -0.95, -0.25])
            bp.hands[s] = hi * up + lo * down
            bp.elbow[s] = np.array([sx * 1.0, 0.6, 0.4 * up])
            bp.fist[s] = 30.0 * down
        return bi.pose(RIG, bp)
    return RigClip("Attack_1", L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def swing_clip(name: str, side: str, low: bool = False) -> RigClip:
    """A one-armed blow across the body: the backhand (the right arm drawn across to the left and
    flung back out to the right), or the stone sweep (the left arm low, round from the right)."""
    L = 1.3
    cocked, strike, hs, he, ok = 0.40, 0.5, 0.58, 0.74, 0.98
    sx = 1.0 if side == "L" else -1.0

    def sample(t: float) -> Poser:
        wind = S(t / cocked) * (1.0 - S((t - cocked) / (he - cocked)))
        through = S((t - cocked) / (he - cocked)) * (1.0 - S((t - he) / (L - he)))
        bp = stand(lift=-0.08 * (wind + through) - (0.18 * through if low else 0.0), twist=-sx * 35.0 * wind + sx * 40.0 * through,
                   yaw=-sx * 10.0 * wind + sx * 12.0 * through, lean=8.0 + (18.0 * through if low else 0.0),
                   bend=8.0 + (14.0 * through if low else 0.0), jaw=12.0 * through)
        z_low = -0.65 if low else 0.25
        start = np.array([-sx * 0.95, -0.35, 0.55 if not low else 0.2])
        end = np.array([sx * 0.55, -0.95, z_low])
        mid = np.array([-sx * 0.15, -1.15, z_low + 0.1])
        if through < 0.5:
            pos = start * wind + mid * (2.0 * through) + np.zeros(3) * (1.0 - wind - 2.0 * through)
        else:
            k = (through - 0.5) * 2.0
            pos = mid * (1.0 - k) + end * k
        bp.hands[side] = pos
        bp.elbow[side] = np.array([sx * 0.8, 0.9, 0.2])
        other = "R" if side == "L" else "L"
        bp.hands[other] = np.array([sx * 0.1, 0.2 * wind, 0.1])
        bp.feet = {side: _P("Foot." + side) + np.array([0.0, -0.20 * through, 0.0]), other: _P("Foot." + other)}
        return bi.pose(RIG, bp)
    return RigClip(name, L, False, sample,
                   [(cocked, "cocked"), (strike, "strike"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def headbutt_clip() -> RigClip:
    """Attack_4, armless: rocked back on its heels with the skull lifted, then thrown forward and
    down, the skull leading."""
    L = 1.1
    cocked, hs, he, ok = 0.36, 0.52, 0.64, 0.86

    def sample(t: float) -> Poser:
        back = S(t / cocked) * (1.0 - S((t - cocked) / (hs - cocked)))
        go = S((t - cocked) / (hs - cocked)) * (1.0 - S((t - he) / (L - he)))
        bp = stand(lean=-12.0 * back + 32.0 * go, bend=-8.0 * back + 18.0 * go, ahead=-0.1 * back + 0.35 * go,
                   lift=-0.15 * go, neck=-25.0 * back + 20.0 * go, head=-10.0 * back + 15.0 * go, jaw=25.0 * back)
        bp.feet = {"L": _P("Foot.L") + np.array([0.0, -0.35 * go, 0.0]), "R": _P("Foot.R")}
        return bi.pose(RIG, bp)
    return RigClip("Attack_4", L, False, sample, [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def prone_pose(push: float = 0.0, swing: float = 0.0, lift_head: float = 0.0) -> bi.BPose:
    """Down on its chest with no arms and one leg, the head up: what is left of it, crawling."""
    bp = bi.BPose(lean=78.0, bend=6.0, lift=-0.62 + 0.04 * push, ahead=0.35 + 0.15 * push, yaw=swing,
                  neck=-55.0 - 15.0 * lift_head, head=-10.0, jaw=10.0 + 10.0 * lift_head, twist=swing * 0.6)
    xf = _hips_xf(bp)
    # the leg left to it shoves; the stump drags
    bp.feet = {"R": xf(_P("Foot.R") + np.array([0.0, 0.45 - 0.45 * push, 0.35 + 0.2 * push])),
               "L": xf(_P("Foot.L") + np.array([0.0, 0.2, 0.5]))}
    bp.foot_dir = {"R": np.array([0.0, 0.3, -1.0]), "L": np.array([0.0, 0.3, -1.0])}
    bp.knee = {"R": np.array([0.0, 0.0, -1.0]), "L": np.array([0.0, 0.0, -1.0])}
    return bp


def crawl_clip() -> RigClip:
    L = 1.6

    def sample(t: float) -> Poser:
        ph = t / L
        push = 0.5 + 0.5 * math.sin(2 * math.pi * ph)
        return bi.pose(RIG, prone_pose(push=push, swing=6.0 * math.sin(2 * math.pi * ph), lift_head=0.3))
    return RigClip("Crawl", L, True, sample, [], {"speed": 0.9})


def crawl_idle_clip() -> RigClip:
    L = 2.0

    def sample(t: float) -> Poser:
        u = t / L
        return bi.pose(RIG, prone_pose(push=0.3 + 0.1 * math.sin(2 * math.pi * u), lift_head=0.5 + 0.3 * math.sin(2 * math.pi * u)))
    return RigClip("Crawl_Idle", L, True, sample)


def crawl_sweep_clip() -> RigClip:
    """Attack_5: what is left of it heaves its whole weight round along the ground."""
    L = 1.3
    cocked, hs, he, ok = 0.42, 0.58, 0.8, 1.0

    def sample(t: float) -> Poser:
        wind = S(t / cocked) * (1.0 - S((t - cocked) / (hs - cocked)))
        go = S((t - cocked) / (he - cocked)) * (1.0 - S((t - he) / (L - he)))
        return bi.pose(RIG, prone_pose(push=0.8 * wind, swing=-35.0 * wind + 45.0 * go, lift_head=wind))
    return RigClip("Attack_5", L, False, sample, [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def crawl_death_clip() -> RigClip:
    L = 1.6

    def sample(t: float) -> Poser:
        u = S(t / L)
        bp = prone_pose(push=0.2, lift_head=1.0 - 1.4 * u)
        bp.lift -= 0.12 * u
        bp.lean += 8.0 * u
        bp.jaw = 25.0 * u
        return bi.pose(RIG, bp)
    return RigClip("Crawl_Death", L, False, sample, [(0.02, "death_start"), (0.7 * L, "body_land")], {"held": True})


def hit_clip() -> RigClip:
    L = 0.5

    def sample(t: float) -> Poser:
        k = B(t / L, 0.25)
        bp = stand(lean=6.0 - 10.0 * k, bend=6.0 - 8.0 * k, ahead=-0.06 * k, neck=-6.0 - 12.0 * k, jaw=20.0 * k,
                   twist=8.0 * k)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([sx * 0.1 * k, 0.1 * k, 0.15 * k])
        return bi.pose(RIG, bp)
    return RigClip("Hit", L, False, sample, [(0.01, "hit_react"), (0.35, "cancel_ok")])


def stagger_clip() -> RigClip:
    L = 1.0

    def sample(t: float) -> Poser:
        u = t / L
        k = B(u, 0.25)
        wob = math.sin(2 * math.pi * u * 1.5) * (1.0 - S(u))
        bp = stand(lean=6.0 - 14.0 * k, roll=-8.0 * k + 5.0 * wob, side=-0.12 * k, ahead=-0.15 * k, lift=-0.06 * k,
                   neck=-20.0 * k, jaw=25.0 * k, twist=12.0 * wob)
        bp.feet = {"L": _P("Foot.L") + np.array([0.0, 0.25 * S((u - 0.15) / 0.25) * (1.0 - S((u - 0.7) / 0.3)), 0.12 * B((u - 0.15) / 0.25) if 0.15 < u < 0.4 else 0.0]),
                   "R": _P("Foot.R") + np.array([-0.1 * S((u - 0.35) / 0.25) * (1.0 - S((u - 0.75) / 0.25)), 0.0,
                                                 0.1 * B((u - 0.35) / 0.25) if 0.35 < u < 0.6 else 0.0])}
        for s, sx in (("L", 1.0), ("R", -1.0)):
            bp.hands[s] = np.array([sx * 0.35 * k, 0.1 * k, 0.35 * k])
        return bi.pose(RIG, bp)
    return RigClip("Stagger", L, False, sample, [(0.01, "hit_react"), (0.8, "cancel_ok")])


def supine_pose(kick: float = 0.0) -> bi.BPose:
    """Flat on its back, the knees up, the arms out."""
    bp = bi.BPose(lean=-82.0, lift=-0.95, ahead=-0.9, neck=20.0, head=10.0, jaw=12.0)
    xf = _hips_xf(bp)
    for s, sx in (("L", 1.0), ("R", -1.0)):
        bp.feet[s] = np.array([sx * 0.45, 0.25 + 0.08 * kick * sx, 0.14])
        bp.knee[s] = np.array([sx * 0.3, 0.0, 1.0])
        bp.hands[s] = np.array([sx * 0.6, 0.3, 0.5])
    del xf
    return bp


def _blend(a: bi.BPose, b: bi.BPose, t: float) -> bi.BPose:
    out = bi.BPose()
    for n in ("lift", "ahead", "side", "lean", "roll", "yaw", "bend", "twist", "side_bend", "neck", "head", "head_turn", "jaw"):
        setattr(out, n, getattr(a, n) + (getattr(b, n) - getattr(a, n)) * t)
    for s in bi.SIDES:
        fa = a.feet.get(s, _P("Foot." + s))
        fb = b.feet.get(s, _P("Foot." + s))
        out.feet[s] = fa + (fb - fa) * t
        ha = a.hands.get(s, np.zeros(3))
        hb_ = b.hands.get(s, np.zeros(3))
        out.hands[s] = ha + (hb_ - ha) * t
        ka = a.knee.get(s)
        kb = b.knee.get(s)
        if ka is not None or kb is not None:
            ka = ka if ka is not None else np.array([0.0, -1.0, 0.15])
            kb = kb if kb is not None else np.array([0.0, -1.0, 0.15])
            out.knee[s] = ka + (kb - ka) * t
    return out


def knockdown_clip() -> RigClip:
    L = 1.6
    fall = 0.55

    def sample(t: float) -> Poser:
        w = S(t / fall)
        bp = _blend(stand(), supine_pose(kick=math.sin(t * 6.0) * (1.0 - S((t - 0.8) / 0.6))), w)
        bp.lift += 0.1 * B(t / fall, 0.3)
        return bi.pose(RIG, bp)
    return RigClip("Knockdown", L, False, sample, [(0.02, "hit_react"), (fall, "body_land")], {"held": True})


def get_up_clip() -> RigClip:
    L = 0.9

    def sample(t: float) -> Poser:
        w = S(t / L)
        mid = stand(lean=40.0, bend=20.0, lift=-0.7)
        mid.feet = {"L": _P("Foot.L") + np.array([0.0, -0.1, 0.0]), "R": _P("Foot.R") + np.array([0.0, 0.25, 0.0])}
        for s, sx in (("L", 1.0), ("R", -1.0)):
            mid.hands[s] = np.array([sx * 0.2, -0.6, -0.9])
        bp = _blend(supine_pose(), mid, S(w / 0.55)) if w < 0.55 else _blend(mid, stand(), S((w - 0.55) / 0.45))
        return bi.pose(RIG, bp)
    return RigClip("Get_Up", L, False, sample, [(0.7 * L, "cancel_ok")])


def death_clip() -> RigClip:
    """The Breath goes out of it: down on its knees, and over on its face."""
    L = 2.4

    def sample(t: float) -> Poser:
        u = t / L
        kneel = S(u / 0.35)
        over = S((u - 0.35) / 0.4)
        bp = stand(lift=-0.62 * kneel - 0.5 * over, lean=6.0 + 10.0 * kneel + 62.0 * over, bend=6.0 + 15.0 * kneel,
                   ahead=0.25 * kneel + 0.45 * over, neck=-6.0 + 10.0 * kneel - 30.0 * over, jaw=25.0 * kneel)
        xf = _hips_xf(bp)
        for s, sx in (("L", 1.0), ("R", -1.0)):
            # the knees on the ground, the shins back along it
            kn = np.array([sx * 0.38, -0.35 * kneel, 0.12])
            ft = np.array([sx * 0.4, 0.45, 0.1])
            bp.feet[s] = _P("Foot." + s) * (1.0 - kneel) + ft * kneel
            bp.knee[s] = np.array([0.0, -1.0, -0.3 * kneel])
            bp.foot_dir[s] = np.array([0.0, -1.0, -0.2]) * (1.0 - kneel) + np.array([0.0, 0.4, -1.0]) * kneel
            bp.hands[s] = np.array([sx * 0.15 * kneel, -0.2 * over, -0.3 * kneel + 0.5 * over])
            del kn
        del xf
        return bi.pose(RIG, bp)
    return RigClip("Death", L, False, sample, [(0.02, "death_start"), (0.35 * L, "knees_land"), (0.75 * L, "body_land")],
                   {"held": True})


def build_clips() -> Dict[str, RigClip]:
    def lumber(bp, ph):
        bp.bend += 6.0
        bp.neck -= 4.0
    return {
        "Idle": idle_clip(), "Idle_Combat": combat_idle_clip(),
        "Walk": bi.walk(RIG, "Walk", 1.1, 36 / FPS, lift=0.16, bob=0.06, sway=0.08, extra_fn=lumber),
        "Run": bi.walk(RIG, "Run", 2.2, 26 / FPS, duty=0.5, lift=0.24, bob=0.1, sway=0.1, arm_swing=0.4, lean=14.0,
                       extra_fn=lumber),
        "Walk_Back": bi.walk(RIG, "Walk_Back", 0.8, 40 / FPS, lift=0.12, way=(0.0, -1.0)),
        "Strafe_L": bi.walk(RIG, "Strafe_L", 0.6, 40 / FPS, lift=0.12, way=(-1.0, 0.0), stance_w=1.1),
        "Strafe_R": bi.walk(RIG, "Strafe_R", 0.6, 40 / FPS, lift=0.12, way=(1.0, 0.0), stance_w=1.1),
        "Turn_L90": bi.walk(RIG, "Turn_L90", 0.0, 40 / FPS, lift=0.12, turn=90.0),
        "Turn_R90": bi.walk(RIG, "Turn_R90", 0.0, 40 / FPS, lift=0.12, turn=-90.0),
        "Attack_1": hammerfall_clip(), "Attack_2": swing_clip("Attack_2", "R"), "Attack_3": swing_clip("Attack_3", "L", low=True),
        "Attack_4": headbutt_clip(), "Attack_5": crawl_sweep_clip(),
        "Crawl": crawl_clip(), "Crawl_Idle": crawl_idle_clip(), "Crawl_Death": crawl_death_clip(),
        "Hit": hit_clip(), "Stagger": stagger_clip(), "Knockdown": knockdown_clip(), "Get_Up": get_up_clip(),
        "Death": death_clip(),
    }
