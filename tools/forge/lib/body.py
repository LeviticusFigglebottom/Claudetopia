"""Procedural humanoid body, head, eyes, hair and beards for WM_Humanoid_v1.

Shapes are SDF scenes (see `sdf.py`) polygonised with surface nets: smooth blended
joints, no boolean creases, and the same field offset outward gives a clothing shell
that fits the body exactly (used by `cloth.py`).

Style: painted storybook realism — chunky-appealing proportions, slightly large hands
and head, soft forms, readable silhouette.  Not low-poly, not anatomical realism.

Blender is only needed by the functions below the "Blender pipeline" banner.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig, sdf
from .rig import Skeleton, FWD, UP, LEFT
from .sdf import Scene

BACK = -FWD


# --------------------------------------------------------------------------------------
# style parameters
# --------------------------------------------------------------------------------------

@dataclass
class BodyStyle:
    """Shape knobs beyond `Proportions`."""
    muscle: float = 0.35        # 0 soft .. 1 defined
    belly: float = 0.09
    chest: float = 0.5
    shoulders: float = 0.5
    # True size. At 1.12 the hand was the "slightly large hand that reads well" of a figure
    # seen from far off; in the Naming at portrait distance it read as a paddle.
    hands: float = 1.0
    feet: float = 0.97

    @staticmethod
    def from_dict(d: Optional[dict]) -> "BodyStyle":
        b = BodyStyle()
        for k, v in (d or {}).items():
            if hasattr(b, k):
                setattr(b, k, float(v))
        return b

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class HeadStyle:
    skull_width: float = 1.0
    skull_depth: float = 1.0
    jaw_width: float = 1.0
    chin: float = 1.0
    nose: float = 1.0
    nose_bridge: float = 1.0
    brow: float = 1.0
    cheeks: float = 1.0
    ears: float = 1.0
    eye_spacing: float = 1.0
    eye_size: float = 1.0
    mouth_width: float = 1.0
    lips: float = 1.0
    forehead: float = 1.0

    @staticmethod
    def from_dict(d: Optional[dict]) -> "HeadStyle":
        h = HeadStyle()
        for k, v in (d or {}).items():
            if hasattr(h, k):
                setattr(h, k, float(v))
        return h

    def to_dict(self) -> dict:
        return asdict(self)


# --------------------------------------------------------------------------------------
# body
# --------------------------------------------------------------------------------------

def body_scene(skel: Skeleton, style: Optional[BodyStyle] = None, ground_cut: bool = True,
               hands: bool = True) -> Scene:
    """The naked body as an SDF scene (Blender space, feet at z=0).

    Built from named anatomical masses rather than one smooth tube, because a capsule with
    limbs is exactly what a character looks like when it has no clavicle, no ribcage taper
    and no joints: a melted silhouette that reads the same from every angle.  What carries
    the read at gameplay distance is the shoulder shelf, the waist, and the joints."""
    st = style or BodyStyle()
    p = skel.props
    J = skel.J
    s = p.height / rig.DEFAULT_HEIGHT
    b = p.bulk
    fem = p.feminine
    heavy = p.build                       # 0 slight .. 1 heavy
    old = p.age
    mus = st.muscle
    sc = Scene()

    tw = b * (0.90 + 0.22 * heavy)        # torso width factor
    td = b * (0.88 + 0.34 * heavy)        # torso depth factor
    lb = b * (0.92 + 0.20 * heavy)        # limb factor
    hipj = J["UpperLeg.L"][2]
    waist_z = J["Spine"][2] + 0.022 * s
    chest_z = J["Chest"][2]
    neck_z = J["Neck"][2]
    crotch_z = hipj - 0.020 * s           # high and narrow: the legs make the crotch

    # A ribcage is wider than the waist and the waist narrower than the hips; that contrast
    # is the whole silhouette.  Half-widths in metres at 1.78 m.
    hipw = (0.122 + 0.022 * fem) * (0.9 + 0.2 * p.hip_width) * tw * s
    waistw = (0.104 - 0.014 * fem + 0.042 * heavy) * tw * s
    chw = (0.172 + 0.016 * st.chest) * (1 - 0.03 * fem) * tw * s
    shw = (0.182 + 0.020 * st.shoulders) * (0.86 + 0.28 * p.shoulder_width) * (1 - 0.06 * fem) * tw * s

    # -- torso: pelvis, waist, ribcage -----------------------------------------------------
    stations = [
        (np.array([0.0, 0.022 * s, crotch_z]), hipw * 0.56, 0.066 * td * s),
        (np.array([0.0, 0.016 * s, hipj + 0.028 * s]), hipw * 0.96, 0.094 * td * s),
        (np.array([0.0, 0.010 * s, hipj + 0.080 * s]), hipw * 0.84, 0.088 * td * s),
        (np.array([0.0, 0.0, waist_z]), waistw, (0.076 + 0.026 * heavy) * td * s),
        (np.array([0.0, -0.008 * s, chest_z - 0.030 * s]), chw * 0.88, 0.084 * td * s),
        (np.array([0.0, -0.012 * s, chest_z + 0.048 * s]), chw, (0.086 + 0.010 * st.chest) * td * s),
        (np.array([0.0, -0.004 * s, chest_z + 0.112 * s]), chw * 0.92, 0.086 * td * s),
        (np.array([0.0, 0.006 * s, neck_z - 0.010 * s]), 0.112 * tw * s, 0.080 * td * s),
        (np.array([0.0, 0.012 * s, neck_z + 0.020 * s]), 0.074 * b * s, 0.068 * b * s),
    ]
    torso_parts = [sdf.loft(stations, LEFT)]
    for sx in (1, -1):
        torso_parts.append(sdf.ellipsoid([sx * 0.060 * s, 0.062 * td * s, hipj + 0.014 * s],
                                         [0.062 * tw * s, (0.040 + 0.022 * heavy) * td * s, 0.062 * s], k=0.035 * s))
    belly_amt = st.belly * (0.4 + 1.1 * heavy) + 0.22 * old * heavy
    if belly_amt > 0.06:
        torso_parts.append(sdf.ellipsoid([0.0, -(0.052 + 0.040 * belly_amt) * td * s, waist_z - 0.060 * s],
                                         [(0.064 + 0.030 * belly_amt) * s, (0.028 + 0.052 * belly_amt) * s,
                                          (0.074 + 0.022 * belly_amt) * s], k=0.030 * s))
    if fem > 0.05:
        for sx in (1, -1):
            torso_parts.append(sdf.ellipsoid([sx * 0.062 * s, -(0.092 + 0.020 * fem) * td * s, chest_z + 0.038 * s],
                                             [(0.046 + 0.020 * fem) * s, (0.030 + 0.026 * fem) * s,
                                              (0.044 + 0.020 * fem) * s], k=0.04 * s))
    if mus > 0.25:
        for sx in (1, -1):
            torso_parts.append(sdf.ellipsoid([sx * 0.074 * s, -0.066 * td * s, chest_z + 0.044 * s],
                                             [0.074 * s, 0.017 * s, 0.036 * s], k=0.05 * s))
        # lats: width, not depth -- a broad flat sheet is what makes a back read as a back
        torso_parts.append(sdf.ellipsoid([0.0, 0.050 * td * s, chest_z + 0.020 * s],
                                         [0.158 * s, 0.026 * s, 0.084 * s], k=0.06 * s))
    sc.union(sdf.group(torso_parts), k=0.02 * s)

    # -- neck: a column with the trapezius flaring into the shoulders ----------------------
    nr = (0.050 + 0.009 * mus - 0.007 * fem - 0.004 * old) * b * s
    sc.union(sdf.round_cone(J["Neck"] + np.array([0.0, 0.010 * s, -0.036 * s]),
                            J["Head"] + np.array([0.0, 0.004 * s, 0.010 * s]), nr * 1.16, nr * 0.94), k=0.030 * s)

    # -- the shoulder shelf: clavicle in front, trapezius behind, deltoid cap on top -------
    for side, sx in (("L", 1), ("R", -1)):
        sh = J[f"UpperArm.{side}"]
        # clavicle: sternum notch out to the point of the shoulder, sitting proud
        sc.union(sdf.tube_path([[sx * 0.014 * s, -0.070 * td * s, neck_z - 0.018 * s],
                                [sx * 0.070 * s, -0.062 * td * s, neck_z - 0.010 * s],
                                [sx * 0.140 * s, -0.036 * td * s, neck_z - 0.014 * s],
                                [sh[0] * 0.96, -0.010 * s, sh[2] + 0.014 * s]],
                               [0.012 * b * s, 0.011 * b * s, 0.011 * b * s, 0.015 * b * s]), k=0.042 * s)
        # trapezius: falling gently from the neck to the point of the shoulder. It used to rise
        # towards the shoulder and end over the joint 5 cm thick, and the deltoid ball sat on
        # top of that: in the A-pose it was a shoulder; with the arms let down, the mound stayed
        # up and every figure wore an epaulette at each corner of a flat shelf.
        sc.union(sdf.tube_path([[sx * 0.020 * s, 0.014 * s, neck_z + 0.004 * s],
                                [sx * 0.072 * s, 0.020 * s, neck_z - 0.012 * s],
                                [sx * 0.130 * s, 0.016 * s, sh[2] - 0.004 * s],
                                [sh[0] - sx * 0.014 * s, 0.006 * s, sh[2] - 0.006 * s]],
                               [0.030 * b * s, 0.032 * b * s, 0.034 * b * s, 0.030 * b * s]), k=0.050 * s)
        # deltoid: a teardrop laid along the top and outside of the upper arm, from the point of
        # the shoulder to a third of the way down, rather than a ball over the joint -- so it
        # moves with the arm and, with the arm down, rounds the shoulder off instead of
        # standing up from it
        el0 = J[f"LowerArm.{side}"]
        da = sdf._unit(el0 - sh)
        fa, ua_up = _arm_frame(da, sx)
        dl_rot = np.stack([da, fa, ua_up], axis=1)
        sc.union(sdf.ellipsoid(sh + da * 0.034 * s + ua_up * 0.008 * s,
                               [(0.074 + 0.010 * mus) * lb * s, (0.050 + 0.008 * mus) * lb * s,
                                (0.047 + 0.008 * mus) * lb * s], rot=dl_rot),
                 k=0.030 * s)

    # -- arms -------------------------------------------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        sh = J[f"UpperArm.{side}"]
        el = J[f"LowerArm.{side}"]
        wr = J[f"Hand.{side}"]
        d = sdf._unit(el - sh)
        fwd, up = _arm_frame(d, sx)
        ua = (0.041 + 0.010 * mus + 0.009 * heavy - 0.004 * fem) * lb * s
        el_r = (0.032 + 0.004 * mus + 0.004 * heavy) * lb * s
        fa = (0.039 + 0.009 * mus + 0.007 * heavy - 0.003 * fem) * lb * s
        wrist = (0.026 + 0.004 * mus + 0.004 * heavy - 0.002 * fem) * lb * s
        ua_len = float(np.linalg.norm(el - sh))
        fa_len = float(np.linalg.norm(wr - el))
        parts = [
            sdf.chain([sh + d * 0.02 * s, sh + d * (0.40 * ua_len), el - d * 0.02 * s,
                       el + d * (0.10 * fa_len), el + d * (0.32 * fa_len), wr],
                      [ua * 1.02, ua * 0.92, el_r, fa, fa * 0.90, wrist], k=0.0),
            # elbow: a real mass, so the arm has a joint instead of a kink
            sdf.ellipsoid(el + up * 0.008 * s, [el_r * 1.30, el_r * 1.26, el_r * 1.30], k=0.026 * s),
            # forearm belly, thickest just below the elbow
            sdf.ellipsoid(el + d * (0.26 * fa_len) + fwd * 0.006 * s,
                          [fa * 1.10, fa * 1.08, fa * 1.14], k=0.034 * s),
            # wrist: narrow, which is what makes the hand read as a hand
            _wrist(wr, d, wrist, s),
        ]
        if mus > 0.2:
            parts.append(sdf.ellipsoid(sh + d * (0.38 * ua_len) + fwd * 0.014 * s,
                                       [0.036 * s, 0.034 * s, 0.034 * s], k=0.038 * s))
            parts.append(sdf.ellipsoid(sh + d * (0.42 * ua_len) - fwd * 0.014 * s,
                                       [0.032 * s, 0.030 * s, 0.038 * s], k=0.038 * s))
        parts.extend(_hand_parts(skel, st, wr, d, fwd, up, sx))
        arm = sdf.group(parts, internal_k=0.016 * s)
        if not hands:
            # The hands are meshed finer on their own (`hands_scene`) from this same arm, so the
            # arm is cut off just before the wrist: the two meshes are one surface either side of
            # the cut. Ended short and thin instead, the forearm's end stood out over the palm like
            # a glove's cuff, and ended shorter still, the two surfaces crossed in a ragged line.
            arm = _cut(arm, wr + d * HAND_CUT * s, d, k=0.002 * s)
        sc.union(arm, k=0.026 * s)

    # -- legs ---------------------------------------------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        hj = J[f"UpperLeg.{side}"]
        kn = J[f"LowerLeg.{side}"]
        an = J[f"Foot.{side}"]
        th = (0.067 + 0.011 * mus + 0.020 * heavy + 0.010 * fem) * lb * s
        kr = (0.048 + 0.005 * mus + 0.008 * heavy) * lb * s
        ar = (0.030 + 0.003 * mus + 0.005 * heavy) * lb * s
        leg_len = float(kn[2] - an[2])
        parts = [
            sdf.chain([hj + np.array([0.0, 0.004 * s, 0.056 * s]), hj - np.array([0.0, 0.0, 0.09 * s]),
                       kn + np.array([0.0, 0.004 * s, 0.070 * s]), kn, kn - np.array([0.0, -0.004 * s, 0.09 * s]),
                       an + np.array([0.0, 0.0, 0.060 * s]), an + np.array([0.0, 0.0, 0.016 * s])],
                      [th * 1.04, th * 0.98, kr * 1.20, kr, kr * 0.92, ar * 1.14, ar]),
            # knee: cap in front, hollow behind
            sdf.ellipsoid(kn + np.array([0.0, -0.016 * s, 0.006 * s]),
                          [kr * 1.06, kr * 0.86, kr * 1.16], k=0.030 * s),
            # calf, high and to the inside as it really sits
            sdf.ellipsoid([kn[0] - sx * 0.004 * s, 0.030 * s + 0.008 * mus * s, an[2] + leg_len * 0.66],
                          [(0.040 + 0.008 * mus) * lb * s, (0.034 + 0.012 * mus) * lb * s,
                           (0.078 + 0.012 * mus) * s], k=0.048 * s),
            # ankle: a narrow waist above the foot, with the bone showing
            sdf.ellipsoid(an + np.array([0.0, 0.004 * s, 0.026 * s]),
                          [ar * 1.14, ar * 1.10, ar * 1.20], k=0.020 * s),
        ]
        if mus > 0.2:
            parts.append(sdf.ellipsoid([hj[0] + sx * 0.010 * s, -0.028 * s, hj[2] - 0.12 * s],
                                       [0.046 * s, 0.034 * s, 0.078 * s], k=0.048 * s))
            parts.append(sdf.ellipsoid([hj[0] - sx * 0.004 * s, 0.026 * s, hj[2] - 0.16 * s],
                                       [0.040 * s, 0.032 * s, 0.070 * s], k=0.048 * s))
        parts.extend(_foot_parts(skel, st, side))
        sc.union(sdf.group(parts, internal_k=0.018 * s), k=0.028 * s)

    if ground_cut:
        sc.intersect(sdf.plane([0.0, 0.0, 0.0], [0.0, 0.0, -1.0]), k=0.008 * s)
    return sc


def _arm_frame(d: np.ndarray, sx: float = -1.0) -> Tuple[np.ndarray, np.ndarray]:
    """(front, up) perpendiculars of an arm direction: `up` is the upper side of the A-posed arm,
    the back of the hand, on either side (`sx` +1 left, -1 right).

    It used to be cross(d, front) whatever the side, which is up on the right arm and down on
    the left: the left hand was built palm up, and anything laid "above" the left arm (the
    elbow's mass) sat below it."""
    u = FWD - np.dot(FWD, d) * d
    u = sdf._unit(u)
    v = np.cross(d, u) * (-sx)
    return u, v


def _hand_parts(skel: Skeleton, st: BodyStyle, wr: np.ndarray, d: np.ndarray,
                fwd: np.ndarray, up: np.ndarray, sx: float = 1.0) -> List[sdf.Prim]:
    """A hand at true size: a thin palm, four fingers that are each a finger, and a thumb.

    The old hand was a paddle -- 1.12 scale, 4.8 cm thick, the fingers one grooved mass -- and at
    the Naming's whole figure it read as a mitten. Now the palm is 3 cm thick and 8 cm across the
    knuckles, and each finger is its own three-jointed tube, touching its neighbours at the root
    and parting towards the tip, curled as a hanging hand curls them. `fwd` is the thumb's side,
    `up` the back of the hand; the palm faces -up. The fingers carry their own small blend so
    the part's group does not melt them back together; mesh it at `hands_scene`'s spacing."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT
    hs = st.hands * p.hand_size * s
    L = 0.182 * hs                 # wrist to the tip of the middle finger, straight
    pw = 0.0405 * hs               # half the width across the knuckles
    pt = 0.0140 * hs               # half the thickness of the palm
    kn = 0.52 * L                  # wrist to the knuckle line
    frame = np.stack([d, fwd, up], axis=1)
    parts: List[sdf.Prim] = []
    # palm: thicker at the heel of the hand, thinning to the knuckles
    parts.append(sdf.loft([
        (wr - d * 0.030 * L, 0.027 * hs, 0.019 * hs),
        (wr + d * 0.14 * L + fwd * 0.004 * hs, pw * 0.88, pt * 1.20),
        (wr + d * 0.36 * L, pw * 0.98, pt * 1.02),
        (wr + d * (kn - 0.012 * hs), pw * 0.95, pt * 0.86),
    ], fwd))
    # the heel of the thumb and the pad under the little finger, on the palm side
    parts.append(sdf.ellipsoid(wr + d * 0.20 * L + fwd * pw * 0.42 - up * pt * 0.50,
                               [0.026 * hs, 0.019 * hs, 0.011 * hs], k=0.010 * s, rot=frame))
    parts.append(sdf.ellipsoid(wr + d * 0.24 * L - fwd * pw * 0.55 - up * pt * 0.45,
                               [0.028 * hs, 0.012 * hs, 0.009 * hs], k=0.010 * s, rot=frame))
    # fingers: (across the knuckles as a fraction of pw, length as a fraction of L, radius,
    # knuckle set back from the line, splay)
    fingers = [(0.70, 0.43, 0.0094, 0.020, 0.035),    # index
               (0.23, 0.47, 0.0096, 0.000, 0.008),    # middle
               (-0.24, 0.44, 0.0090, 0.010, -0.020),  # ring
               (-0.68, 0.35, 0.0079, 0.045, -0.050)]  # little
    curl = (9.0, 24.0, 18.0)       # degrees at each joint: a relaxed hand
    seg = (0.47, 0.29, 0.24)
    knuckles = []
    for off, ln, r, back, splay in fingers:
        base = wr + d * (kn - back * L) + fwd * (pw * off)
        knuckles.append(base + up * pt * 0.55)
        dirv = sdf._unit(d + fwd * splay)
        pts = [base - dirv * 0.014 * hs, base]
        cur, ang = base, 0.0
        for k in range(3):
            ang += curl[k]
            a = math.radians(ang)
            cur = cur + sdf._unit(dirv * math.cos(a) - up * math.sin(a)) * seg[k] * ln * L
            pts.append(cur)
        rr = r * hs
        parts.append(sdf.tube_path(pts, [rr * 1.04, rr, rr * 0.94, rr * 0.86, rr * 0.74], k=0.0025 * s))
    # the knuckles standing a little proud on the back of the hand
    parts.append(sdf.tube_path(knuckles, 0.0070 * hs, k=0.006 * s))
    # thumb: from the heel of the palm, forward and across, curling in towards the palm
    tb0 = wr + d * 0.12 * L + fwd * pw * 0.66 - up * pt * 0.20
    tb1 = tb0 + sdf._unit(fwd * 0.45 + d * 0.82 - up * 0.30) * 0.043 * hs
    tb2 = tb1 + sdf._unit(fwd * 0.16 + d * 0.88 - up * 0.42) * 0.030 * hs
    tb3 = tb2 + sdf._unit(fwd * 0.04 + d * 0.82 - up * 0.55) * 0.024 * hs
    parts.append(sdf.tube_path([tb0, tb1, tb2, tb3], [0.0168 * hs, 0.0126 * hs, 0.0113 * hs, 0.0097 * hs],
                               k=0.006 * s))
    return parts


# How far past the ball the toes reach, as a share of the skeleton's toe bone, and how far the heel
# stands behind the ankle (m at 1.78 m). The skeleton's ToeTip is 24.5 cm ahead of the ankle, and a
# foot modelled out to it, with its heel 8.7 cm behind, was 34 cm long before a shoe went on: in a
# lineup every shoe was a clown's. A foot is 26-27 cm; the bones are the clips' and stay as they are.
TOE_REACH = 0.50
HEEL_BACK = 0.034


def foot_tip(skel: Skeleton, side: str) -> np.ndarray:
    """Where the modelled toes end: short of the skeleton's ToeTip, a real foot's length."""
    ball = np.asarray(skel.J[f"Toe.{side}"], float)
    tip = np.asarray(skel.J[f"ToeTip.{side}"], float)
    return ball + (tip - ball) * TOE_REACH


def _foot_parts(skel: Skeleton, st: BodyStyle, side: str) -> List[sdf.Prim]:
    """A foot with an ankle, an arch and a toe break, rather than a slipper."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT
    fs = st.feet * p.foot_size * s
    J = skel.J
    an = J[f"Foot.{side}"]
    ball = J[f"Toe.{side}"]
    tip = foot_tip(skel, side)
    x = float(an[0])
    sx = 1.0 if side == "L" else -1.0
    heel = np.array([x, an[1] + HEEL_BACK * fs, 0.034 * fs])
    # the sole: narrow at the heel, waisted at the arch, widest at the ball
    sole = sdf.loft([
        (heel + np.array([0.0, 0.010 * fs, 0.0]), 0.031 * fs, 0.030 * fs),
        (np.array([x, an[1] + 0.012 * fs, 0.030 * fs]), 0.036 * fs, 0.030 * fs),
        (np.array([x - sx * 0.004 * fs, (an[1] + ball[1]) * 0.5, 0.026 * fs]), 0.036 * fs, 0.026 * fs),
        (np.array([ball[0], ball[1] + 0.010 * fs, 0.024 * fs]), 0.048 * fs, 0.024 * fs),
        (np.array([tip[0], tip[1] + 0.032 * fs, 0.023 * fs]), 0.037 * fs, 0.021 * fs),
    ], LEFT)
    parts = [
        # heel and Achilles
        sdf.round_cone(an + np.array([0.0, 0.006 * fs, 0.010 * fs]), heel, 0.031 * fs, 0.030 * fs, k=0.022 * s),
        sole,
        # instep, rising from the toes to the ankle
        sdf.loft([
            (np.array([x, ball[1] + 0.020 * fs, 0.030 * fs]), 0.040 * fs, 0.014 * fs),
            (np.array([x, an[1] - 0.040 * fs, 0.042 * fs]), 0.036 * fs, 0.026 * fs),
            (np.array([x, an[1] - 0.006 * fs, 0.056 * fs]), 0.032 * fs, 0.030 * fs),
        ], LEFT, k=0.026 * s),
        # ankle bones: the inner one sits higher than the outer, which reads even small
        sdf.ellipsoid([x + sx * 0.026 * fs, an[1], 0.080 * fs], [0.013 * fs, 0.016 * fs, 0.015 * fs], k=0.018 * s),
        sdf.ellipsoid([x - sx * 0.026 * fs, an[1], 0.070 * fs], [0.012 * fs, 0.015 * fs, 0.014 * fs], k=0.018 * s),
        # the arch: lift the inner edge of the sole off the ground
        sdf.ellipsoid([x + sx * 0.040 * fs, (an[1] + ball[1]) * 0.5, 0.004 * fs],
                      [0.024 * fs, 0.050 * fs, 0.020 * fs], k=0.020 * s, op="subtract"),
        # the toe break, and a big toe that is bigger than the rest
        sdf.tube_path([[x - sx * 0.042 * fs, ball[1] + 0.004 * fs, 0.022 * fs],
                       [x + sx * 0.040 * fs, ball[1] - 0.002 * fs, 0.024 * fs]],
                      0.0038 * fs, k=0.009 * s, op="subtract"),
        sdf.ellipsoid([x + sx * 0.024 * fs, tip[1] + 0.028 * fs, 0.023 * fs],
                      [0.014 * fs, 0.018 * fs, 0.015 * fs], k=0.011 * s),
    ]
    for i in range(3):
        tx = x - sx * (0.004 + 0.016 * i) * fs
        parts.append(sdf.tube_path([[tx, ball[1] + 0.002 * fs, 0.021 * fs],
                                    [tx, tip[1] + 0.030 * fs, 0.020 * fs]],
                                   [0.0022 * fs, 0.0042 * fs], k=0.0055 * s, op="subtract"))
    return parts


def body_mesh(skel: Skeleton, style: Optional[BodyStyle] = None, spacing: float = 0.0070,
              smooth: int = 4) -> Tuple[np.ndarray, np.ndarray]:
    sc = body_scene(skel, style)
    return sdf.mesh_from_scene(sc, spacing * (skel.props.height / rig.DEFAULT_HEIGHT), smooth_iters=smooth, project=1)


# Where the body stops and the separately meshed hand takes over, along the arm from the wrist
# joint (m, at 1.78 m): just short of it, before the palm's blend begins.
HAND_CUT = -0.008


def _cut(prim: sdf.Prim, point: np.ndarray, normal: np.ndarray, k: float = 0.0) -> sdf.Prim:
    """`prim` on the side of the plane through `point` that `normal` points away from, the edge
    rounded over `k`."""
    n = np.asarray(normal, float)

    def fn(P):
        return sdf.smax(prim.fn(P), (P - point) @ n, k)
    return sdf.Prim(fn, prim.lo, prim.hi, prim.op, prim.k)


def hands_scene(skel: Skeleton, style: Optional[BodyStyle] = None) -> Scene:
    """Both hands on their own, for meshing finer than the body: at the body's 8 mm the gap between
    two fingers is not there to be found, and the fingers came out as one mass whatever the field
    said. Each is the body's own arm from 3 cm above the cut (`HAND_CUT`) outwards, sunk 4 mm
    under the body's surface until 5 mm before the cut and exactly on it from there, so the body's
    forearm covers it up the arm and it covers the body's end, which is rounded off inside it."""
    st = style or BodyStyle()
    s = skel.props.height / rig.DEFAULT_HEIGHT
    arms = body_scene(skel, st, ground_cut=False)
    sc = Scene()
    J = skel.J
    for side in ("L", "R"):
        sh, el, wr, tip = J[f"UpperArm.{side}"], J[f"LowerArm.{side}"], J[f"Hand.{side}"], J[f"HandTip.{side}"]
        d = sdf._unit(el - sh)
        # the arm group of this side: the one whose bounds hold the wrist
        group = next(p for p in arms.prims if p.op == "union" and np.all(p.lo <= wr) and np.all(p.hi >= wr))
        cut = wr + d * HAND_CUT * s
        start = cut - d * 0.030 * s

        def fn(P, group=group, d=d, cut=cut, start=start):
            t = (P - cut) @ d
            # Well under the body's surface (4 mm, more than decimation moves either mesh) up the
            # forearm, and on it for the last 5 mm before the cut, where the body's end rounds off
            # inside it: the hand covers the join. Sunk 0.8 mm to the cut, the two surfaces crossed
            # in a ragged line; sunk 4 mm to the cut, the rounded end left a groove round the wrist.
            sunk = 0.004 * s * np.clip((-t - 0.005 * s) / (0.003 * s), 0.0, 1.0)
            return np.maximum(group.fn(P) + sunk, -((P - start) @ d))
        lo = np.minimum(start, tip) - 0.09 * s
        hi = np.maximum(start, tip) + 0.09 * s
        sc.union(sdf.Prim(fn, lo, hi, "union", 0.0))
    return sc


def _wrist(wr: np.ndarray, d: np.ndarray, wrist: float, s: float) -> sdf.Prim:
    return sdf.ellipsoid(wr - d * 0.012 * s, [wrist * 1.12, wrist * 0.92, wrist * 1.10], k=0.020 * s)


def body_mesh_parts(skel: Skeleton, style: Optional[BodyStyle] = None, spacing: float = 0.0080,
                    hand_spacing: float = 0.0026, smooth: int = 4):
    """The body without its hands at `spacing`, and the hands at `hand_spacing`: two meshes, joined
    by the caller, the hands' wrist stubs hidden inside the body's forearms."""
    k = skel.props.height / rig.DEFAULT_HEIGHT
    body = sdf.mesh_from_scene(body_scene(skel, style, hands=False), spacing * k, smooth_iters=smooth, project=1)
    hands = sdf.mesh_from_scene(hands_scene(skel, style), hand_spacing * k, smooth_iters=2, project=1)
    return body, hands


def _face_stations(s: float, V: float, chin_z: float, hs: "HeadStyle", fem: float,
                   heavy: float) -> List[Tuple[float, float, float, float]]:
    """The face in profile, chin to brow: (height as a fraction of V, half width, front y, back y).

    Everything a face is recognised by lines up in the side view -- brow over eye over cheek,
    nose tip ahead of the lips, the chin just behind them -- so the face is lofted from these
    stations and the vault is built separately above it. The back y stops at the ear line: the
    face is a mask on the front of the skull, and letting its stations reach the nape skews
    every section backwards and swallows the chin."""
    # A preset's numbers are its intent (`broad` is jaw_width 1.14); the gains here are what
    # make a 14% wider jaw read as a different person on a 400-pixel preview rather than as
    # the same face measured twice.
    jw = (1.0 + 1.5 * (hs.jaw_width - 1.0)) * (1 - 0.07 * fem) * (1 + 0.05 * heavy)
    cw = 1.0 + 1.0 * (hs.skull_width - 1.0) + 0.30 * (hs.cheeks - 1.0)
    ch = 1.0 + 1.5 * (hs.chin - 1.0)
    return [
        # the bottom station is small and set up by its own cap radius, so the cap of the sweep
        # IS the underside of the chin rather than hanging two centimetres below it
        (0.012 * s / V + 0.002, 0.016 * jw * s, -0.062 * s, -0.038 * s),  # under the chin
        (0.075, 0.034 * jw * s, (-0.083 - 0.008 * (ch - 1)) * s, -0.004 * s),   # the chin
        (0.135, 0.049 * jw * s, -0.081 * s, 0.014 * s),                  # mandible below the lip
        (0.205, 0.058 * jw * s, -0.086 * s, 0.028 * s),                  # the mouth
        (0.290, 0.062 * cw * s, -0.088 * s, 0.036 * s),                  # upper lip / nose base
        (0.390, 0.065 * cw * s, -0.084 * s, 0.040 * s),                  # cheekbones
        # the eye line and the brow are the same on every face: hair and its sideburns are
        # built once against them, so a preset changes the face below the eyes and not above
        (0.500, 0.066 * s, -0.080 * s, 0.036 * s),                       # the eye line
        (0.585, 0.063 * s, -0.086 * s, 0.020 * s),                       # the brow
    ]


def _station_front(st: Tuple[float, float, float, float], x: float) -> float:
    """Front-surface y of a face station at lateral offset `x` (the section is an ellipse)."""
    _, hw, front, back = st
    u = min(abs(x) / max(hw, 1e-6), 0.995)
    return 0.5 * (front + back) - 0.5 * (back - front) * math.sqrt(1.0 - u * u)


def head_landmarks(skel: Skeleton, hs: Optional[HeadStyle] = None) -> dict:
    """Key positions for the head builder, eyes, hair, beards and the face painter.

    Heights are fractions of the visible head V (chin to crown), on a head canon measured off a
    skull rather than guessed: eyes at V/2, the face in near-equal thirds from the chin to the
    nose base (0.30), to the brow (0.575) and to the hairline (0.80), the mouth a third of the
    way down from nose to chin. The Head bone starts just above the chin, so the jaw hangs a
    little below its origin.

    The vault -- `skull_c`/`skull_r` -- is the SAME for every head preset. A face preset moves
    the jaw, the cheeks, the nose and the brow; it does not move the cranium, because hair, hoods
    and helms are built once against the cranium and have to fit every face."""
    hs = hs or HeadStyle()
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT * p.head_size
    fem = p.feminine
    head = skel.J["Head"]
    top = float(skel.J["HeadTop"][2])
    hl = top - float(head[2])
    chin_z = float(head[2]) - 0.022 * s
    V = top - chin_z                                   # ~0.253 m at 1.78 m: a shade under 7 heads
    st = _face_stations(s, V, chin_z, hs, fem, p.build)
    eye_st = st[6]
    eye_z = chin_z + V * eye_st[0]
    face_y = eye_st[2]                                 # the front of the face at the eye line
    eye_x = 0.0322 * hs.eye_spacing * s
    eye_r = 0.0158 * hs.eye_size * s
    eye_surf = _station_front(eye_st, eye_x)
    skull_c = np.array([0.0, 0.012 * s, chin_z + V * 0.60])
    skull_r = np.array([0.079 * s, 0.103 * s, V * 0.40])
    return {
        "s": s, "head": head, "top": np.array([0.0, 0.0, top]), "hl": hl, "visible": V,
        "V": V, "half_w": float(st[5][1]), "half_d": float(skull_r[1]), "cy": float(skull_c[1]),
        "stations": st,
        "eye_z": eye_z, "skull_c": skull_c, "skull_r": skull_r,
        "face_y": face_y,
        "eye_x": eye_x, "eye_r": eye_r,
        # The eyeball sits behind the face surface where the face actually IS at that lateral
        # position; measured from the midline it lands proud of it and reads as goggles.
        "eye_c_y": eye_surf + 0.0118 * s,
        "brow_z": chin_z + V * 0.575,
        "nose_root_z": chin_z + V * 0.530,
        "nose_base_z": chin_z + V * 0.300,
        "nose_tip": np.array([0.0, face_y - (0.020 + 0.016 * (hs.nose - 1.0)) * s, chin_z + V * 0.335]),
        "mouth_z": chin_z + V * 0.195, "mouth_w": 0.0250 * hs.mouth_width * s,
        "chin_z": chin_z, "jaw_z": chin_z + V * 0.120,
        "cheek_z": chin_z + V * 0.400,
        "gonion": np.array([0.054 * (1.0 + 1.5 * (hs.jaw_width - 1.0)) * (1 - 0.07 * fem) * s, 0.010 * s,
                            chin_z + V * 0.150]),
        "ear_c": np.array([0.069 * s, 0.020 * s, chin_z + V * 0.445]),
        "ear_r": np.array([0.0055 * s, 0.0165 * hs.ears * s, V * 0.118 * hs.ears]),
        "hairline_z": chin_z + V * 0.800,
        "nape_z": chin_z + V * 0.300,
    }


def cranium_prims(skel: Skeleton) -> List[sdf.Prim]:
    """The vault, shared by every face: a long parietal mass, a narrower frontal mass that makes
    a forehead with a plane to it, the occipital shelf the neck tucks under, and the mastoids
    behind the ears. Width 0.15 m against a depth of 0.19 m at 1.78 m -- a head is longer
    than it is wide, which is the first thing an egg gets wrong."""
    L = head_landmarks(skel)
    s, V, z0 = L["s"], L["V"], L["chin_z"]
    Z = lambda f: z0 + V * f
    return [
        sdf.ellipsoid([0.0, 0.020 * s, Z(0.620)], [0.0755 * s, 0.087 * s, 0.380 * V]),
        sdf.ellipsoid([0.0, -0.020 * s, Z(0.665)], [0.0670 * s, 0.067 * s, 0.330 * V], k=0.022 * s),
        sdf.ellipsoid([0.0, 0.054 * s, Z(0.465)], [0.0560 * s, 0.052 * s, 0.150 * V], k=0.026 * s),
        sdf.ellipsoid([0.043 * s, 0.030 * s, Z(0.380)], [0.016 * s, 0.022 * s, 0.090 * V], k=0.018 * s),
        sdf.ellipsoid([-0.043 * s, 0.030 * s, Z(0.380)], [0.016 * s, 0.022 * s, 0.090 * V], k=0.018 * s),
    ]


def _ear(L: dict, sx: float, s: float, ears: float) -> Tuple[List[sdf.Prim], List[sdf.Prim]]:
    """An ear that reads at the distance a player stands: a rim, a bowl and a lobe, standing off
    the skull at the back. Returns (masses, carvings)."""
    ec = L["ear_c"] * np.array([sx, 1.0, 1.0])
    h = L["ear_r"][2]                          # half height, ~3 cm
    wdt = 0.0170 * ears * s                    # half width
    # the ear plane: the side of the head swung back 24 degrees (it flares away from the skull
    # behind) and tipped back 14 degrees from vertical, the way an ear actually sits
    R = rig.rot_axis(UP, math.radians(-24.0 * sx)) @ rig.rot_axis(LEFT, math.radians(-14.0))
    out = R @ np.array([sx, 0.0, 0.0])
    fwd = R @ np.array([0.0, -1.0, 0.0])
    up = R @ np.array([0.0, 0.0, 1.0])

    def P(f_fwd: float, f_up: float, f_out: float = 0.0) -> np.ndarray:
        return ec + fwd * (f_fwd * wdt) + up * (f_up * h) + out * (f_out * s)

    masses = [
        # the auricle: a thin plate, thickest at the root
        sdf.ellipsoid(ec + out * 0.002 * s, [0.0060 * s, wdt, h],
                      rot=np.stack([out, fwd, up], axis=1), k=0.004 * s),
        # the helix rim: the C that runs from above the tragus over the top and down the back
        sdf.tube_path([P(0.30, 0.55, 0.004), P(0.05, 0.95, 0.005), P(-0.55, 0.85, 0.006),
                       P(-0.95, 0.30, 0.007), P(-0.85, -0.30, 0.006), P(-0.40, -0.72, 0.005)],
                      [0.0024 * s, 0.0030 * s, 0.0032 * s, 0.0032 * s, 0.0030 * s, 0.0026 * s],
                      k=0.0020 * s),
        # the lobe
        sdf.ellipsoid(P(-0.15, -0.80, 0.003), [0.0045 * s, 0.0085 * s, 0.0090 * s],
                      rot=np.stack([out, fwd, up], axis=1), k=0.003 * s),
        # the tragus, the small flap in front of the canal
        sdf.ellipsoid(P(0.55, -0.12, 0.000), [0.0040 * s, 0.0045 * s, 0.0055 * s], k=0.003 * s),
    ]
    carve = [
        # the concha: the bowl behind the tragus, deepest low and forward
        sdf.ellipsoid(P(0.05, -0.18, 0.009), [0.0060 * s, 0.0085 * s, 0.0115 * s],
                      rot=np.stack([out, fwd, up], axis=1)),
        # the scapha: the groove just inside the rim at the back
        sdf.tube_path([P(-0.10, 0.70, 0.010), P(-0.60, 0.55, 0.010), P(-0.72, 0.05, 0.010),
                       P(-0.55, -0.40, 0.009)], 0.0022 * s),
    ]
    return masses, carve


def head_scene(skel: Skeleton, hs: Optional[HeadStyle] = None, with_neck: bool = True) -> Scene:
    """Head as an SDF scene: the shared vault, a face lofted from its profile below the brow,
    the parts a skull shows through a face (brow ridge, cheekbones, the jaw's edge and angle,
    the chin), then nose, lips and ears, then the carved detail."""
    hs = hs or HeadStyle()
    L = head_landmarks(skel, hs)
    p = skel.props
    s = L["s"]
    fem = p.feminine
    old = p.age
    heavy = p.build
    V, z0 = L["V"], L["chin_z"]
    Z = lambda f: z0 + V * f
    eye_z, face_y = L["eye_z"], L["face_y"]
    mouth_z = L["mouth_z"]
    st = L["stations"]
    sc = Scene()

    mass: List[sdf.Prim] = list(cranium_prims(skel))
    face = sdf.loft([(np.array([0.0, 0.5 * (f + b), Z(fz)]), hw, 0.5 * (b - f)) for fz, hw, f, b in st],
                    LEFT, axis=UP)
    mass.append(sdf.Prim(face.fn, face.lo, face.hi, "union", 0.020 * s))

    def front_at(fz: float, x: float) -> float:
        """Face surface y at height fraction fz and lateral x, interpolating the stations."""
        for a, b in zip(st, st[1:]):
            if a[0] <= fz <= b[0]:
                t = (fz - a[0]) / max(b[0] - a[0], 1e-6)
                return (1 - t) * _station_front(a, x) + t * _station_front(b, x)
        return _station_front(st[-1] if fz > st[-1][0] else st[0], x)

    # brow ridge: one bar across both eyes with the glabella between, the outer ends dropping
    # and running back to the temple -- the shelf that puts the eyes in shadow
    br = (0.0072 + 0.0100 * (hs.brow - 1.0) + 0.0026 * (1 - fem)) * s
    bz = L["brow_z"]
    brow_pts, brow_r = [], []
    for fx in (-1.00, -0.72, -0.38, 0.0, 0.38, 0.72, 1.00):
        x = fx * 0.056 * s
        droop = 0.006 * s * fx * fx
        y = front_at(0.575, x) + (0.004 - 0.006 * fx * fx - 0.008 * (hs.brow - 1.0)) * s
        brow_pts.append([x, y, bz + 0.002 * s - droop])
        brow_r.append(br * (1.0 - 0.34 * fx * fx))
    mass.append(sdf.tube_path(brow_pts, brow_r, k=0.010 * s))
    # cheekbones: the malar prominence under the outer eye and the arch running back to the ear
    for sx in (1, -1):
        mx = sx * 0.047 * s
        my = front_at(0.40, mx) + 0.004 * s
        ck = 1.0 + 1.6 * (hs.cheeks - 1.0)
        mass.append(sdf.ellipsoid([mx, my - 0.002 * s - 0.004 * (ck - 1.0) * s, L["cheek_z"] + 0.004 * s],
                                  [0.019 * ck * s, 0.013 * ck * s, 0.013 * ck * s], k=0.012 * s))
        mass.append(sdf.tube_path([[mx, my + 0.008 * s, L["cheek_z"] + 0.006 * s],
                                   [sx * 0.062 * s, -0.020 * s, L["cheek_z"] + 0.010 * s],
                                   [sx * 0.066 * s, 0.006 * s, L["cheek_z"] + 0.012 * s]],
                                  [0.0056 * s * hs.cheeks, 0.0046 * s, 0.0038 * s], k=0.014 * s))
    # the masseter and the soft tissue in front of the ear: without it the side of the face is
    # a channel between the cheekbone and the jaw, which is a skull, not a head
    for sx in (1, -1):
        mass.append(sdf.ellipsoid([sx * 0.053 * s, 0.010 * s, Z(0.330)],
                                  [0.0180 * s, 0.034 * s, 0.066 * s], k=0.026 * s))
    # the jaw: a definite line from the chin round to the angle, then the ramus up to the ear.
    # This edge is what a face is read by at thirty pixels; soft tissue alone rounds it away.
    gon = L["gonion"]
    jaw_pts, jaw_r = [], []
    for sx in (1, -1):
        g = gon * np.array([sx, 1, 1])
        ramus = [g + np.array([0.0, 0.004 * s, 0.050 * s]), g + np.array([0.0, 0.002 * s, 0.020 * s]), g]
        body = [np.array([sx * 0.036 * s, front_at(0.10, 0.036 * s) + 0.010 * s, Z(0.085)])]
        pts = ramus + body if sx == 1 else list(reversed(ramus + body))
        rr = [0.0070 * s, 0.0082 * s, 0.0086 * s, 0.0080 * s]
        jaw_pts.append(pts)
        jaw_r.append(rr if sx == 1 else list(reversed(rr)))
    chin_pt = np.array([0.0, front_at(0.055, 0.0) + 0.009 * s, Z(0.050)])
    mass.append(sdf.tube_path(jaw_pts[0] + [chin_pt] + jaw_pts[1],
                              jaw_r[0] + [0.0105 * s * hs.chin] + jaw_r[1], k=0.012 * s))
    # the chin's own mound, and a little fullness each side of the mouth
    mass.append(sdf.ellipsoid([0.0, front_at(0.06, 0.0) + 0.006 * s, Z(0.065)],
                              [0.017 * s, 0.009 * s * hs.chin, 0.015 * s * hs.chin], k=0.012 * s))
    # the cheek's soft tissue under the malar: fuller with weight and round faces, thinner
    # with age, and never a hollow -- a hollow cheek on a clay head is a skull
    cheek_amt = 0.16 + 0.26 * heavy - 0.22 * old + 0.9 * (hs.cheeks - 1.0)
    if cheek_amt > 0.05:
        for sx in (1, -1):
            x = sx * 0.042 * s
            mass.append(sdf.ellipsoid([x, front_at(0.27, x) + 0.012 * s, Z(0.27)],
                                      [0.018 * s, 0.013 * s, 0.022 * s * (0.8 + 0.5 * cheek_amt)], k=0.018 * s))
    # eye mounds (the lids sit on the eyeball)
    er = L["eye_r"]
    for sx in (1, -1):
        ec = np.array([sx * L["eye_x"], L["eye_c_y"], eye_z])
        mass.append(sdf.ellipsoid(ec, [er * 1.22, er * 1.00, er * 0.92], k=0.012 * s))
    # nose: bridge, tip and wings, projecting past the lips so the profile has a nose in it
    root = np.array([0.0, face_y + 0.004 * s, L["nose_root_z"]])
    tip = L["nose_tip"]
    bridge_r = (0.0074 + 0.0034 * hs.nose_bridge) * s
    # a bridge above 1 grows a hump, which is the whole of a hawkish profile
    mid = root + (tip - root) * 0.55 + np.array([0.0, (-0.002 - 0.014 * (hs.nose_bridge - 1.0)) * s, 0.0])
    mass.append(sdf.tube_path([root, mid, tip],
                              [bridge_r * 0.95, bridge_r * 1.02, (0.0088 + 0.0026 * hs.nose) * s], k=0.0060 * s))
    for sx in (1, -1):
        mass.append(sdf.ellipsoid(tip + np.array([sx * 0.0118 * hs.nose * s, 0.0100 * s, -0.0040 * s]),
                                  [0.0074 * hs.nose * s, 0.0080 * s, 0.0064 * s], k=0.0050 * s))
    # lips, following the dental arch so the corners sit back and a little low
    mw = L["mouth_w"]
    lip_y = front_at(0.195, 0.0)
    lip = 0.55 + 0.62 * hs.lips + 0.22 * fem

    def lip_arc(z_off: float, half_w: float, r: float, back: float, drop: float):
        pts, rr = [], []
        for f in (-1.0, -0.55, 0.0, 0.55, 1.0):
            pts.append([f * half_w, lip_y + back * (f * f) * s, mouth_z + z_off - drop * (f * f) * s])
            rr.append(r * (0.55 + 0.45 * (1.0 - f * f)))
        return sdf.tube_path(pts, rr, k=0.0070 * s)
    mass.append(lip_arc(0.0068 * s, mw * 0.84, 0.0068 * lip * s, 0.0085, 0.0030))
    mass.append(lip_arc(-0.0078 * s, mw * 0.74, 0.0066 * lip * s, 0.0080, 0.0018))
    # The upper lip's outline: the Cupid's bow, two peaks either side of the philtrum's dip, and
    # the edge of the red of the lip standing a little proud of the skin above it. A plain arc of
    # lip read as a rubber band; this line is most of what makes a mouth a shaped thing.
    bow, bow_r = [], []
    for f, lift in ((-1.0, -0.0030), (-0.62, 0.0006), (-0.26, 0.0030), (0.0, 0.0016),
                    (0.26, 0.0030), (0.62, 0.0006), (1.0, -0.0030)):
        bow.append([f * mw * 0.86, lip_y - 0.0020 * s + 0.0086 * (f * f) * s, mouth_z + (0.0118 + lift) * s])
        bow_r.append((0.0018 + 0.0008 * (1.0 - f * f)) * s * lip)
    mass.append(sdf.tube_path(bow, bow_r, k=0.0024 * s))
    # the philtrum's two ridges, from the base of the nose down to the peaks of the bow
    for sx in (1, -1):
        mass.append(sdf.tube_path([[sx * 0.0040 * s, lip_y - 0.0008 * s, L["nose_base_z"] - 0.004 * s],
                                   [sx * 0.0054 * s, lip_y - 0.0016 * s, mouth_z + 0.0135 * s]],
                                  [0.0009 * s, 0.0012 * s], k=0.0012 * s))
    # the floor of the mouth: fills under the jaw between the chin and the throat, so the
    # jawline is an edge over a plane and not a wire over a hollow
    mass.append(sdf.ellipsoid([0.0, -0.022 * s, Z(0.090)], [0.036 * s, 0.036 * s, 0.028 * s], k=0.020 * s))
    # ears
    ear_carve: List[sdf.Prim] = []
    for sx in (1, -1):
        m_, c_ = _ear(L, sx, s, hs.ears)
        mass.extend(m_)
        ear_carve.extend(c_)
    if with_neck:
        bs = p.height / rig.DEFAULT_HEIGHT
        nr = (0.0500 - 0.007 * fem - 0.004 * old) * p.bulk * bs
        mass.append(sdf.round_cone(L["head"] + np.array([0.0, 0.012 * bs, -0.090 * bs]),
                                   L["head"] + np.array([0.0, 0.020 * bs, 0.012 * bs]), nr * 1.12, nr * 0.92, k=0.022 * s))
    sc.union(sdf.group(mass, internal_k=0.014 * s))

    # -- carved detail --------------------------------------------------------------------
    for sx in (1, -1):
        ec = np.array([sx * L["eye_x"], L["eye_c_y"], eye_z])
        tilt = rig.rot_axis(FWD, math.radians(7.0 * sx))
        # a thin lens forward of the eyeball opens the lids and no more; deeper is a skull. It
        # was 1.2 eye radii tall, level with the eye's centre, and every face stared: white showed
        # above the iris. Lower and narrower, the upper lid covers the top of the iris, as a lid
        # at rest does.
        sc.subtract(sdf.ellipsoid(ec + np.array([0.0, -er * 0.66, -er * 0.07]),
                                  [er * 1.30, er * 0.62, er * 0.46], rot=tilt), k=0.0036 * s)
        # The socket: the hollow between the brow ridge and the upper lid, where the orbit's rim
        # stands over the eye. The eye mounds filled it level with the brow, so every eye sat on
        # the face like a button; set in under the ridge, it is shadowed as an eye is.
        sc.subtract(sdf.ellipsoid(ec + np.array([0.0, -er * 0.52, er * 1.00]),
                                  [er * 1.04, er * 0.42, er * 0.36], rot=tilt), k=0.006 * s)
        # upper lid crease under the brow
        sc.subtract(sdf.ellipsoid(ec + np.array([0.0, -er * 0.40, er * 0.98]),
                                  [er * 0.98, er * 0.26, er * 0.20], rot=tilt), k=0.006 * s)
        sc.subtract(sdf.sphere(ec + np.array([-sx * er * 1.06, -er * 0.60, -0.001 * s]), er * 0.20), k=0.004 * s)
        # under the lower lid: the fold where the lid meets the cheek, which comes with years
        if old > 0.35:
            sc.subtract(sdf.tube_path([ec + np.array([-sx * er * 0.70, -er * 0.84, -er * 1.00]),
                                       ec + np.array([0.0, -er * 0.90, -er * 1.16]),
                                       ec + np.array([sx * er * 0.80, -er * 0.82, -er * 0.98])],
                                      er * 0.10 * (old - 0.35) / 0.65), k=0.006 * s)
    # mouth line, philtrum, nostrils
    line_pts, line_r = [], []
    for f in (-1.0, -0.5, 0.0, 0.5, 1.0):
        line_pts.append([f * mw * 0.88, lip_y - 0.008 * s + 0.0078 * (f * f) * s, mouth_z - 0.0028 * (f * f) * s])
        line_r.append(0.0018 * s)
    sc.subtract(sdf.tube_path(line_pts, line_r), k=0.0034 * s)
    sc.subtract(sdf.capsule([0.0, lip_y - 0.003 * s, mouth_z + 0.012 * s],
                            [0.0, lip_y - 0.002 * s, mouth_z + 0.020 * s], 0.0022 * s), k=0.005 * s)
    for sx in (1, -1):
        sc.subtract(sdf.ellipsoid(tip + np.array([sx * 0.0074 * s, 0.0086 * s, -0.0082 * s]),
                                  [0.0036 * s, 0.0050 * s, 0.0026 * s]), k=0.0022 * s)
        # the crease round the nose wing, which is what attaches a nose to a face
        sc.subtract(sdf.tube_path([tip + np.array([sx * 0.0140 * s, 0.0060 * s, 0.0040 * s]),
                                   tip + np.array([sx * 0.0190 * s, 0.0120 * s, -0.0030 * s]),
                                   tip + np.array([sx * 0.0150 * s, 0.0150 * s, -0.0110 * s])],
                                  0.0016 * s), k=0.003 * s)
    for c in ear_carve:
        sc.subtract(c, k=0.0030 * s)
    # The lids, laid over the opening the lens cut: a roll of skin along each margin, lying on the
    # eyeball, thickest over the middle of the eye and thinning into the corners, the upper one
    # the heavier. Without them the opening was a hole cut in a mask; with them the eye has an
    # edge that catches the light above and holds a shadow on the white below it.
    for sx in (1, -1):
        ec = np.array([sx * L["eye_x"], L["eye_c_y"], eye_z])
        for upper in (True, False):
            pts, rr = [], []
            for t in np.linspace(-1.0, 1.0, 9):
                x = sx * t * er * 1.16
                tilt_z = t * er * 0.08                # the outer corner a little higher
                if upper:
                    z = er * (0.52 * (1.0 - t * t) - 0.05) + tilt_z
                    r = er * (0.10 + 0.08 * (1.0 - t * t))
                else:
                    z = -er * (0.50 * (1.0 - t * t) + 0.08) + tilt_z
                    r = er * (0.06 + 0.03 * (1.0 - t * t))
                R = er * 1.00 + r * 0.55
                y = -math.sqrt(max(R * R - x * x - z * z, (0.35 * er) ** 2))
                pts.append(ec + np.array([x, y, z]))
                rr.append(r)
            sc.union(sdf.tube_path(pts, rr, k=0.0022 * s))
    # the naso-labial fold, with age
    if old > 0.40:
        amt = (old - 0.40) / 0.60
        for sx in (1, -1):
            sc.subtract(sdf.round_cone([sx * (mw * 0.60), lip_y - 0.004 * s, mouth_z + 0.030 * s],
                                       [sx * (mw * 1.18), lip_y + 0.006 * s, mouth_z - 0.010 * s],
                                       0.0028 * amt * s, 0.0040 * amt * s), k=0.005 * s)
    return sc


def face_asymmetry(skel: Skeleton, hs: Optional[HeadStyle], V: np.ndarray) -> Dict[str, np.ndarray]:
    """Morph targets that take a face off true, one side at a time: a brow a little higher, a
    corner of the mouth a little higher (a half-smile at rest). The engine sets one of each pair
    by the person's seed (HumanoidModel.face_asymmetry_for), so two people on the same head are
    not one face twice. A painted asymmetry is the head's, the same on everyone who wears it."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    V = np.asarray(V, float)

    def bump(c, r):
        return np.exp(-0.5 * np.sum(((V - np.asarray(c, float)) / np.asarray(r, float)) ** 2, axis=1))
    out: Dict[str, np.ndarray] = {}
    for side, sx in (("L", 1.0), ("R", -1.0)):
        w = bump([sx * L["eye_x"] * 1.05, L["face_y"], L["brow_z"] + 0.004 * s], [0.022 * s, 0.030 * s, 0.012 * s])
        out["brow_up_%s" % side] = V + w[:, None] * np.array([0.0, 0.0, 0.0030 * s])
        w = bump([sx * L["mouth_w"] * 1.05, L["face_y"], L["mouth_z"]], [0.011 * s, 0.024 * s, 0.009 * s])
        out["mouth_up_%s" % side] = V + w[:, None] * np.array([sx * 0.0008 * s, 0.0, 0.0024 * s])
    return out


def head_mesh(skel: Skeleton, hs: Optional[HeadStyle] = None, spacing: float = 0.0032,
              smooth: int = 4) -> Tuple[np.ndarray, np.ndarray]:
    sc = head_scene(skel, hs)
    s = skel.props.height / rig.DEFAULT_HEIGHT * skel.props.head_size
    return sdf.mesh_from_scene(sc, spacing * s, smooth_iters=smooth, project=1)




# --------------------------------------------------------------------------------------
# eyes
# --------------------------------------------------------------------------------------

def eye_mesh(center: np.ndarray, r: float, nu: int = 22, nv: int = 16) -> Tuple[np.ndarray, List[List[int]], np.ndarray]:
    """Eyeball sphere whose pole faces forward (-Y).  UV: u = azimuth, v = polar angle / pi,
    so v=0 is the pupil centre — the iris texture is painted as rings in v."""
    verts, faces, uvs = [], [], []
    for i in range(nv + 1):
        th = math.pi * i / nv
        for j in range(nu + 1):
            ph = 2 * math.pi * j / nu
            p = np.array([r * math.sin(th) * math.cos(ph), -r * math.cos(th), r * math.sin(th) * math.sin(ph)])
            verts.append(center + p)
            uvs.append((j / nu, th / math.pi))
    # Wound so the faces look outward. They used to look inward: invisible to Blender's renders,
    # which draw both sides, and culled away entirely by the engine's iris shader.
    for i in range(nv):
        for j in range(nu):
            a = i * (nu + 1) + j
            faces.append([a, a + nu + 1, a + nu + 2, a + 1])
    return np.asarray(verts), faces, np.asarray(uvs)


# --------------------------------------------------------------------------------------
# hair and beards: shells grown from head regions
# --------------------------------------------------------------------------------------

# Hairline height, as a fraction of the visible head V, against the angle round the skull from
# straight ahead (0) to straight behind (180). Across the forehead at 0.80, up at the temple
# corner, down in front of the ear as a sideburn, over the top of the ear, down behind it and
# along the nape. A cap has one height all the way round, which is why every style used to
# read as a helmet sitting on the head rather than hair growing out of it.
HAIRLINE: List[Tuple[float, float]] = [
    (0, 0.800), (18, 0.806), (32, 0.828), (45, 0.792), (54, 0.690), (61, 0.560), (68, 0.478),
    (75, 0.490), (82, 0.560), (94, 0.612), (106, 0.590), (114, 0.480), (124, 0.395),
    (145, 0.325), (180, 0.292),
]


def head_angle(P: np.ndarray, L: dict) -> np.ndarray:
    """Degrees round the vertical axis of the vault: 0 at the face, 180 at the back of the head."""
    return np.degrees(np.arctan2(np.abs(P[:, 0]), -(P[:, 1] - L["skull_c"][1])))


def hairline_height(theta: np.ndarray, L: dict, front: float = 1.0, sides: float = 1.0,
                    back: float = 1.0) -> np.ndarray:
    """World height of the hairline at angle `theta` (degrees). `front` < 1 raises the front
    (a receding line), `sides` > 1 brings the sideburns lower, `back` > 1 takes it down the neck."""
    t, h = zip(*HAIRLINE)
    f = np.interp(np.clip(theta, 0.0, 180.0), t, h)
    w_front = 1.0 - np.clip((theta - 28.0) / 24.0, 0.0, 1.0)
    w_side = np.exp(-0.5 * ((theta - 70.0) / 9.0) ** 2)
    w_back = np.clip((theta - 110.0) / 40.0, 0.0, 1.0)
    f = f + (1.0 - front) * 0.06 * w_front - (sides - 1.0) * 0.07 * w_side - (back - 1.0) * 0.08 * w_back
    return L["chin_z"] + L["V"] * f


def ear_clearance(P: np.ndarray, L: dict, margin: float = 0.004) -> np.ndarray:
    """Signed metres outside the space an ear and the skin round it need (>0 = clear)."""
    s = L["s"]
    out = np.full(len(P), 1.0)
    for sx in (1.0, -1.0):
        ec = L["ear_c"] * np.array([sx, 1.0, 1.0])
        rad = np.array([0.030 * s, 0.024 * s + margin, L["ear_r"][2] + margin])
        k = np.linalg.norm((P - ec) / rad, axis=1)
        out = np.minimum(out, (k - 1.0) * float(rad.min()))
    return out


def scalp_field(verts: np.ndarray, skel: Skeleton, hs: Optional[HeadStyle] = None, front: float = 1.0,
                sides: float = 1.0, back: float = 1.0) -> np.ndarray:
    """Signed hair coverage over the head surface, in metres: >0 is scalp, the value is how far
    above the hairline (and clear of the ears) a point is."""
    L = head_landmarks(skel, hs)
    th = head_angle(verts, L)
    above = verts[:, 2] - hairline_height(th, L, front, sides, back)
    return np.minimum(above, ear_clearance(verts, L))


def beard_field(verts: np.ndarray, normals: Optional[np.ndarray], skel: Skeleton, hs: Optional[HeadStyle] = None,
                moustache: bool = True, cheeks: float = 1.0, length: float = 1.0,
                chin_only: bool = False) -> np.ndarray:
    """Signed beard coverage over the face, in metres (>0 = beard).

    The cheek line runs from the bottom of the sideburn down to the corner of the mouth; the
    moustache fills the upper lip up to the nose; under the jaw the beard stops where the
    throat begins; the lips are always bare."""
    L = head_landmarks(skel, hs)
    s, V, z0 = L["s"], L["V"], L["chin_z"]
    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    th = head_angle(verts, L)
    mw = L["mouth_w"]
    mz = L["mouth_z"]
    # upper edge: the moustache line at the front, rising along the cheek to the sideburn
    upper = np.interp(th, [0.0, 16.0, 30.0, 52.0, 70.0, 76.0],
                      [0.300, 0.290, 0.255, 0.330 * cheeks + 0.24 * (1 - cheeks), 0.470, 0.470])
    upper = z0 + V * upper
    cov = upper - z
    # the back edge: in front of the ear, and no further round than the sideburn
    cov = np.minimum(cov, (74.0 - th) * 0.0012 * s)
    # the lower edge: under the jaw the beard reaches back to the throat and no further
    under = (y - L["skull_c"][1]) + 0.020 * s
    cov = np.minimum(cov, np.where(z < z0 + 0.010 * s, -under, 1.0))
    cov = np.minimum(cov, z - (z0 - 0.034 * s * max(length, 0.6)))
    if chin_only:
        cov = np.minimum(cov, (0.040 * s - np.abs(x)))
    # bare lips
    lips = np.maximum(np.abs(x) - mw * 1.12, np.abs(z - mz) - 0.0085 * s)
    cov = np.minimum(cov, np.where(y < L["face_y"] + 0.030 * s, lips, 1.0))
    if not moustache:
        cov = np.minimum(cov, np.where((z > mz) & (th < 30.0), -1.0, 1.0))
    return cov


def moustache_field(verts: np.ndarray, skel: Skeleton, hs: Optional[HeadStyle] = None) -> np.ndarray:
    """Signed coverage of the upper lip alone, with the ends drooping past the mouth corners."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    x, z = verts[:, 0], verts[:, 2]
    mw, mz = L["mouth_w"], L["mouth_z"]
    top = L["nose_base_z"] - 0.002 * s
    bottom = mz + 0.0045 * s - np.clip(np.abs(x) - mw * 0.55, 0.0, None) * 0.9
    cov = np.minimum(top - z, z - bottom)
    cov = np.minimum(cov, mw * 1.30 - np.abs(x))
    return np.minimum(cov, (30.0 - head_angle(verts, L)) * 0.001 * s)


# ======================================================================================
# Blender pipeline (bpy imported lazily so the rest of the module works without Blender)
# ======================================================================================

def _bpy():
    import bpy
    return bpy


def select_only(ob) -> None:
    bpy = _bpy()
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def tri_count(ob) -> int:
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def to_object(name: str, verts: np.ndarray, faces, smooth: bool = True, uvs: Optional[np.ndarray] = None):
    """Create a Blender object from arrays.  `uvs` is per-vertex (n,2) if given."""
    bpy = _bpy()
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in verts], [], [list(map(int, f)) for f in faces])
    me.update()
    # Validate, the way `lib/scene.py` does for every mesh the prop forge builds from
    # arrays. `from_pydata` will accept topology Blender considers invalid -- the marching
    # cubes surface these come off produces faces that repeat a vertex where two corners
    # meet at a point -- and it does not complain. The glTF exporter does: it says
    # "Mesh Body is not valid, and may be exported wrongly" and then writes no mesh at all.
    # That is why `bodies/child`, `heavy` and `slight` each shipped as a 31-bone skeleton
    # with nothing on it, while the meta beside them recorded 7 798 triangles -- the
    # triangles were counted off a live object *after* the export that had silently
    # dropped them.
    me.validate(verbose=False)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if uvs is not None:
        uv = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for l in poly.loop_indices:
                uv.data[l].uv = tuple(map(float, uvs[me.loops[l].vertex_index]))
    return ob


def mesh_arrays(ob) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(verts (n,3), vertex normals (n,3), triangles (m,3)) in object space."""
    me = ob.data
    me.calc_loop_triangles()
    n = len(me.vertices)
    verts = np.empty(n * 3)
    me.vertices.foreach_get("co", verts)
    normals = np.empty(n * 3)
    me.vertices.foreach_get("normal", normals)
    tris = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tris)
    return verts.reshape(-1, 3), normals.reshape(-1, 3), tris.reshape(-1, 3)


def set_verts(ob, verts: np.ndarray) -> None:
    ob.data.vertices.foreach_set("co", np.asarray(verts, float).ravel())
    ob.data.update()


def join_into(dst, others: Sequence) -> None:
    """Merge the mesh objects `others` into `dst` (one object, several shells)."""
    bpy = _bpy()
    bpy.ops.object.select_all(action='DESELECT')
    for o in others:
        o.select_set(True)
    dst.select_set(True)
    bpy.context.view_layer.objects.active = dst
    bpy.ops.object.join()


def decimate(ob, target_tris: int, symmetry: bool = True) -> None:
    bpy = _bpy()
    tris = tri_count(ob)
    if tris <= target_tris:
        return
    select_only(ob)
    dm = ob.modifiers.new("Decimate", 'DECIMATE')
    dm.decimate_type = 'COLLAPSE'
    dm.ratio = target_tris / tris
    dm.use_symmetry = symmetry
    dm.symmetry_axis = 'X'
    dm.use_collapse_triangulate = False
    bpy.ops.object.modifier_apply(modifier=dm.name)
    for p in ob.data.polygons:
        p.use_smooth = True


def shade_smooth_with_autosmooth(ob, angle_deg: float = 60.0) -> None:
    """Smooth shading with a crease angle, under either Blender.

    Blender 4.1 deleted `use_auto_smooth` and `auto_smooth_angle`; the same thing is said
    now by marking the edges over the angle sharp, which is what `shade_smooth_by_angle`
    does and what the glTF exporter reads. `lib/scene.py` carries the same guard for the
    prop forge.

    It used to swallow the `AttributeError` and carry on, which is worse than a crash: on
    4.2 the angle would quietly mean nothing and every mesh would come out fully smoothed
    with no threshold, and the only way to find out would be to notice it in a render. As
    it happens nothing in the character forge calls this -- the bodies and garments are
    smoothed by `to_object`, which sets every polygon smooth and asks for no angle -- so
    the swallowed error was never reached. That is luck, not design, and the next caller
    should get the behaviour the name promises."""
    bpy = _bpy()
    for p in ob.data.polygons:
        p.use_smooth = True
    if hasattr(bpy.types.Mesh, "use_auto_smooth"):        # Blender 4.0
        ob.data.use_auto_smooth = True
        ob.data.auto_smooth_angle = math.radians(angle_deg)
        return
    select_only(ob)                                       # Blender 4.1+
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg), keep_sharp_edges=True)


def smart_uv(ob, angle_deg: float = 66.0, margin: float = 0.02) -> None:
    bpy = _bpy()
    select_only(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle_deg), island_margin=margin, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')


def cylindrical_uv(ob, axis_center, z0: float, z1: float, u_scale: float = 1.0) -> None:
    """Cylindrical projection around a vertical axis (heads, torsos): u = angle with the seam
    at the back, v = height.  Written per loop so the seam does not smear."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0]
    verts = np.array([v.co[:] for v in me.vertices])
    rel = verts - np.asarray(axis_center, float)
    ang = np.arctan2(rel[:, 0], -rel[:, 1])
    u_all = 0.5 + ang / (2 * math.pi) * u_scale
    v_all = (verts[:, 2] - z0) / max(z1 - z0, 1e-6)
    for poly in me.polygons:
        us = [u_all[me.loops[l].vertex_index] for l in poly.loop_indices]
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for l, u in zip(poly.loop_indices, us):
            uv.data[l].uv = (u, v_all[me.loops[l].vertex_index])


# -- skinning ---------------------------------------------------------------------------

def auto_weights(ob, arm) -> bool:
    """Blender bone-heat automatic weights; True when every vertex got a weight."""
    bpy = _bpy()
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    except Exception as e:  # pragma: no cover
        print("  auto weights failed:", e)
        return False
    missing = sum(1 for v in ob.data.vertices if not v.groups)
    if missing:
        print("  auto weights left %d/%d verts unweighted" % (missing, len(ob.data.vertices)))
    return missing == 0


def weight_matrix(ob, bones: Sequence[str]) -> np.ndarray:
    gi = {g.name: g.index for g in ob.vertex_groups}
    n = len(ob.data.vertices)
    W = np.zeros((n, len(bones)))
    col = {gi[b]: j for j, b in enumerate(bones) if b in gi}
    for v in ob.data.vertices:
        for g in v.groups:
            if g.group in col:
                W[v.index, col[g.group]] = g.weight
    return W


def apply_weight_matrix(ob, bones: Sequence[str], W: np.ndarray, threshold: float = 0.004) -> None:
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    for j, b in enumerate(bones):
        idx = np.nonzero(W[:, j] > threshold)[0]
        if len(idx) == 0:
            continue
        vg = ob.vertex_groups.new(name=b)
        for vi in idx:
            vg.add([int(vi)], float(W[vi, j]), 'REPLACE')


def segment_weights(verts: np.ndarray, skel: Skeleton, bones: Sequence[str], sharpness: float = 2.4) -> np.ndarray:
    """Distance-to-bone-segment weights with a smooth falloff (seed / fallback field)."""
    n = len(verts)
    W = np.zeros((n, len(bones)))
    for bi, b in enumerate(bones):
        bb = skel.bones[b]
        a, t = bb.head, bb.tail
        ab = t - a
        l2 = max(float(np.dot(ab, ab)), 1e-9)
        u = np.clip(((verts - a) @ ab) / l2, 0.0, 1.0)
        d = np.linalg.norm(verts - (a + u[:, None] * ab), axis=1)
        r = 0.035 + 0.42 * bb.length
        W[:, bi] = np.exp(-((d / r) ** sharpness))
    return W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)


def smooth_weights(W: np.ndarray, tris: np.ndarray, iters: int = 4, factor: float = 0.45) -> np.ndarray:
    """Laplacian smoothing of the weight field across mesh edges (kills joint creasing)."""
    n = W.shape[0]
    edges = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]], axis=0)
    for _ in range(iters):
        acc = np.zeros_like(W)
        cnt = np.zeros(n)
        np.add.at(acc, edges[:, 0], W[edges[:, 1]])
        np.add.at(acc, edges[:, 1], W[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        W = (1.0 - factor) * W + factor * acc / np.maximum(cnt, 1)[:, None]
        W = np.maximum(W, 0.0)
        W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return W


def limit_influences(W: np.ndarray, max_influences: int = 4) -> np.ndarray:
    n = W.shape[0]
    idx = np.argsort(-W, axis=1)
    keep = np.zeros_like(W)
    for k in range(min(max_influences, W.shape[1])):
        keep[np.arange(n), idx[:, k]] = W[np.arange(n), idx[:, k]]
    return keep / np.maximum(keep.sum(axis=1, keepdims=True), 1e-9)


def skin_to_armature(ob, arm, skel: Skeleton, smooth_iters: int = 3, max_influences: int = 4) -> str:
    """Skin `ob` to `arm`: bone-heat automatic weights where they work (they respect the
    surface, so nothing bleeds across a gap), a segment-distance field where they do not;
    then edge smoothing and a 4-influence limit for glTF."""
    method = "auto"
    if not auto_weights(ob, arm):
        method = "segment"
        verts, normals, tris = mesh_arrays(ob)
        W = segment_weights(verts, skel, rig.DEFORM_NAMES)
        apply_weight_matrix(ob, rig.DEFORM_NAMES, W)
        if not any(m.type == 'ARMATURE' for m in ob.modifiers):
            mod = ob.modifiers.new("Armature", 'ARMATURE')
            mod.object = arm
        ob.parent = arm
    verts, normals, tris = mesh_arrays(ob)
    W = weight_matrix(ob, rig.DEFORM_NAMES)
    empty = W.sum(axis=1) < 1e-6
    if empty.any():
        seed = segment_weights(verts, skel, rig.DEFORM_NAMES)
        W[empty] = seed[empty]
    W = smooth_weights(W, tris, iters=smooth_iters)
    W = limit_influences(W, max_influences)
    apply_weight_matrix(ob, rig.DEFORM_NAMES, W)
    return method


def nearest_weights(dst_verts: np.ndarray, src_verts: np.ndarray, src_W: np.ndarray, k: int = 4) -> np.ndarray:
    """Inverse-distance weight transfer from a source point cloud (chunked)."""
    out = np.zeros((len(dst_verts), src_W.shape[1]))
    chunk = max(1, 3_000_000 // max(len(src_verts), 1))
    for i in range(0, len(dst_verts), chunk):
        part = dst_verts[i:i + chunk]
        dd = ((part[:, None, :] - src_verts[None, :, :]) ** 2).sum(axis=2)
        kk = min(k, dd.shape[1])
        idx = np.argpartition(dd, kk - 1, axis=1)[:, :kk]
        d2 = np.take_along_axis(dd, idx, axis=1)
        w = 1.0 / np.maximum(d2, 1e-8)
        w /= w.sum(axis=1, keepdims=True)
        out[i:i + chunk] = np.einsum("nk,nkb->nb", w, src_W[idx])
    return out


def transfer_weights(dst_ob, src_verts: np.ndarray, src_W: np.ndarray, arm, bones: Sequence[str] = rig.DEFORM_NAMES,
                     k: int = 4, smooth: int = 2) -> None:
    """Skin a part (garment, hair, armour) by copying weights from the nearest body vertices,
    so every part deforms exactly like the body under it."""
    verts, normals, tris = mesh_arrays(dst_ob)
    W = nearest_weights(verts, src_verts, src_W, k)
    if smooth and len(tris):
        W = smooth_weights(W, tris, iters=smooth, factor=0.4)
    W = limit_influences(W)
    apply_weight_matrix(dst_ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in dst_ob.modifiers):
        mod = dst_ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    dst_ob.parent = arm


def custom_weights(ob, W: np.ndarray, arm, bones: Sequence[str] = rig.DEFORM_NAMES) -> None:
    """Bind a part with weights computed for it (hair that hangs past the neck)."""
    W = limit_influences(np.asarray(W, float))
    apply_weight_matrix(ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    ob.parent = arm


def fit_positions(verts: np.ndarray, base_field, target_field, reach: float = 0.060,
                  fade: float = 0.030, iters: int = 3, max_step: float = 0.03) -> np.ndarray:
    """Where each vertex of a part built on one surface goes to sit on another.

    Each vertex keeps the distance it had from the surface it was built on, measured now from
    the new one, found by stepping along the new field's gradient. A tunic built on the
    default body lands on the heavy body the same 11 mm off it; a beard built on the default
    jaw lands on a broad one. Past `reach` from the body the move fades out over `fade`,
    because the sampled fields end there and a cloak's hem does not follow the ribs."""
    V = np.asarray(verts, float)
    d0 = base_field.eval(V)
    P = V.copy()
    # A sampled field reads 1e6 in any cell no primitive's bounds reached, and a Newton step on
    # that flung a dress's hem and a plaid's corner a thousand kilometres: never step on a
    # reading that is not a distance, and never more than a few centimetres at once.
    sane = np.abs(d0) < 0.5
    for _ in range(iters):
        d = target_field.eval(P)
        ok = sane & (np.abs(d) < 0.5)
        step = np.clip(d - d0, -max_step, max_step) * ok
        P = P - target_field.gradient(P) * step[:, None]
    w = (1.0 - np.clip((d0 - reach) / max(fade, 1e-6), 0.0, 1.0)) * sane
    return V + (P - V) * w[:, None]


def add_shape_keys(ob, targets: Dict[str, np.ndarray]) -> List[str]:
    """Morph targets on a part, exported to glTF and set by the game (HumanoidModel._apply_fits)."""
    if not targets:
        return []
    if ob.data.shape_keys is None:
        ob.shape_key_add(name="Basis", from_mix=False)
    names = []
    for name, pos in targets.items():
        kb = ob.shape_key_add(name=name, from_mix=False)
        kb.data.foreach_set("co", np.asarray(pos, float).ravel())
        names.append(name)
    ob.data.update()
    return names


def rigid_weights(ob, bone: str, arm, bones: Sequence[str] = rig.DEFORM_NAMES) -> None:
    """Bind a whole part to one bone (helms, horns, halos attached to Head)."""
    W = np.zeros((len(ob.data.vertices), len(bones)))
    W[:, list(bones).index(bone)] = 1.0
    apply_weight_matrix(ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    ob.parent = arm


# -- morph targets ----------------------------------------------------------------------

def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def gauss3(p: np.ndarray, c, s) -> np.ndarray:
    d = (p - np.asarray(c, float)) / np.asarray(s, float)
    return np.exp(-0.5 * np.sum(d * d, axis=1))
