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
    hands: float = 1.12         # slightly large hands read well
    feet: float = 1.06

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

def body_scene(skel: Skeleton, style: Optional[BodyStyle] = None, ground_cut: bool = True) -> Scene:
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
        # trapezius: a flatter slope than before, so the shoulder line is a shelf not a ramp
        sc.union(sdf.tube_path([[sx * 0.020 * s, 0.014 * s, neck_z + 0.006 * s],
                                [sx * 0.072 * s, 0.020 * s, neck_z - 0.006 * s],
                                [sx * 0.130 * s, 0.016 * s, sh[2] + 0.028 * s],
                                [sh[0] + sx * 0.020 * s, 0.006 * s, sh[2] + 0.020 * s]],
                               [0.030 * b * s, 0.034 * b * s, 0.042 * b * s, 0.048 * b * s]), k=0.050 * s)
        # deltoid: a cap that sits over the joint and carries the width
        sc.union(sdf.ellipsoid(sh + np.array([sx * 0.026 * s, 0.0, 0.014 * s]),
                               [(0.058 + 0.014 * mus) * lb * s, (0.054 + 0.010 * mus) * lb * s,
                                (0.062 + 0.012 * mus) * lb * s], rot=rig.rot_axis(FWD, math.radians(-22.0 * sx))),
                 k=0.030 * s)

    # -- arms -------------------------------------------------------------------------------
    for side, sx in (("L", 1), ("R", -1)):
        sh = J[f"UpperArm.{side}"]
        el = J[f"LowerArm.{side}"]
        wr = J[f"Hand.{side}"]
        d = sdf._unit(el - sh)
        fwd, up = _arm_frame(d)
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
            sdf.ellipsoid(wr - d * 0.012 * s, [wrist * 1.12, wrist * 0.92, wrist * 1.10], k=0.020 * s),
        ]
        if mus > 0.2:
            parts.append(sdf.ellipsoid(sh + d * (0.38 * ua_len) + fwd * 0.014 * s,
                                       [0.036 * s, 0.034 * s, 0.034 * s], k=0.038 * s))
            parts.append(sdf.ellipsoid(sh + d * (0.42 * ua_len) - fwd * 0.014 * s,
                                       [0.032 * s, 0.030 * s, 0.038 * s], k=0.038 * s))
        parts.extend(_hand_parts(skel, st, wr, d, fwd, up, sx))
        sc.union(sdf.group(parts, internal_k=0.016 * s), k=0.026 * s)

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


def _arm_frame(d: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """(front, up) perpendiculars of an arm direction."""
    u = FWD - np.dot(FWD, d) * d
    u = sdf._unit(u)
    v = np.cross(d, u)
    return u, v


def _hand_parts(skel: Skeleton, st: BodyStyle, wr: np.ndarray, d: np.ndarray,
                fwd: np.ndarray, up: np.ndarray, sx: float = 1.0) -> List[sdf.Prim]:
    """A hand, not a paddle: a palm, four fingers as one softly grooved mass with a knuckle
    ridge, and a thumb that is its own mass set against the palm.  The fingers rest in a
    relaxed curl, which is what a hand does when an arm hangs."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT
    hs = st.hands * p.hand_size * s
    L = 0.170 * hs                 # wrist to fingertip, straight
    pw = 0.046 * hs                # half width across the palm
    pt = 0.024 * hs                # half thickness
    # `fwd` points to the character's front; the palm faces `-up` (inwards, towards the leg)
    parts: List[sdf.Prim] = []
    # palm: a wedge, thicker at the thumb side, thinning towards the little finger
    palm = sdf.loft([
        (wr - d * 0.020 * L, 0.030 * hs, 0.022 * hs),
        (wr + d * 0.16 * L, pw * 0.92, pt * 1.04),
        (wr + d * 0.42 * L, pw, pt),
    ], fwd)
    parts.append(palm)
    # the knuckle ridge across the top of the palm
    parts.append(sdf.tube_path([wr + d * 0.46 * L + fwd * pw * 0.88,
                                wr + d * 0.50 * L + fwd * pw * 0.10,
                                wr + d * 0.47 * L - fwd * pw * 0.80],
                               [0.013 * hs, 0.015 * hs, 0.012 * hs], k=0.012 * s))
    # the finger mass, curling slightly: a relaxed hand is never flat
    curl = -up * 0.030 * hs
    fing = sdf.loft([
        (wr + d * 0.50 * L, pw * 0.94, pt * 0.92),
        (wr + d * 0.72 * L + curl * 0.35, pw * 0.94, pt * 0.86),
        (wr + d * 0.90 * L + curl * 0.80, pw * 0.84, pt * 0.76),
        (wr + d * 1.00 * L + curl * 1.25, pw * 0.62, pt * 0.62),
    ], fwd)
    parts.append(sdf.Prim(fing.fn, fing.lo, fing.hi, "union", 0.010 * s))
    # three grooves between the fingers, deepest at the tips
    for i, f in enumerate((0.48, 0.02, -0.46)):
        a = wr + d * 0.55 * L + fwd * (pw * f)
        c = wr + d * 1.01 * L + fwd * (pw * f * 0.72) + curl * 1.25
        parts.append(sdf.tube_path([a, (a + c) * 0.5 + curl * 0.35, c],
                                   [0.0042 * hs, 0.0062 * hs, 0.0078 * hs], k=0.0055 * s, op="subtract"))
    # thumb: its own mass, set low and across the palm, with a visible web
    tb0 = wr + d * 0.20 * L + fwd * pw * 0.80
    tb1 = tb0 + sdf._unit(fwd * 0.52 + d * 0.78 - up * 0.22) * 0.070 * hs
    tb2 = tb1 + sdf._unit(fwd * 0.16 + d * 0.86 - up * 0.46) * 0.056 * hs
    parts.append(sdf.tube_path([tb0, tb1, tb2], [0.021 * hs, 0.018 * hs, 0.014 * hs], k=0.016 * s))
    parts.append(sdf.ellipsoid(tb0 - fwd * 0.004 * hs, [0.020 * hs, 0.020 * hs, 0.018 * hs], k=0.018 * s))
    return parts


def _foot_parts(skel: Skeleton, st: BodyStyle, side: str) -> List[sdf.Prim]:
    """A foot with an ankle, an arch and a toe break, rather than a slipper."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT
    fs = st.feet * p.foot_size * s
    J = skel.J
    an = J[f"Foot.{side}"]
    ball = J[f"Toe.{side}"]
    tip = J[f"ToeTip.{side}"]
    x = float(an[0])
    sx = 1.0 if side == "L" else -1.0
    heel = np.array([x, an[1] + 0.056 * fs, 0.034 * fs])
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


def head_landmarks(skel: Skeleton, hs: Optional[HeadStyle] = None) -> dict:
    """Key positions for the head builder, eyes, hair, beards and the face painter.

    Everything is expressed as a fraction of the *visible* head height V (chin to crown),
    using the classic head canon: eyes at V/2, nose base at 0.33 V, mouth at 0.21 V,
    brow at 0.60 V, ears spanning brow to nose base.  The Head bone starts at the skull
    pivot (about ear level), so the jaw hangs below its origin."""
    hs = hs or HeadStyle()
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT * p.head_size
    fem = p.feminine
    head = skel.J["Head"]
    top = float(skel.J["HeadTop"][2])
    hl = top - float(head[2])
    chin_z = float(head[2]) - 0.022 * s
    V = top - chin_z                                   # ~0.265 m at 1.78 m -> 6.7 heads
    w = 0.0895 * hs.skull_width * (1 - 0.03 * fem) * s   # half width at the temples
    d = 0.0930 * hs.skull_depth * s                      # half depth at the temples
    cy = 0.009 * s                                       # skull axis offset (back of head is deeper)
    eye_z = chin_z + V * 0.500
    face_y = cy - d * 0.985                              # face surface y at the eye line
    # Stylised eyes: a shade larger than life, which reads as expressive rather than beady
    # at gameplay distance and survives the mesh resolution around the lids.
    eye_x = 0.0325 * hs.eye_spacing * s
    eye_r = 0.0165 * hs.eye_size * s
    _u = min(eye_x / (w * 0.985), 0.99)                  # lateral fraction of the eye station
    _yc = 0.5 * (face_y + cy + d * 0.94)
    _hd = 0.5 * (cy + d * 0.94 - face_y)
    eye_surf = _yc - _hd * math.sqrt(1.0 - _u * _u)      # skull surface at the eye, not the midline
    return {
        "s": s, "head": head, "top": np.array([0.0, 0.0, top]), "hl": hl, "visible": V,
        "V": V, "half_w": w, "half_d": d, "cy": cy,
        "eye_z": eye_z, "skull_c": np.array([0.0, cy, chin_z + V * 0.66]),
        "skull_r": np.array([w, d, V * 0.34]),
        "face_y": face_y,
        "eye_x": eye_x, "eye_r": eye_r,
        # The eye sits on the skull where the skull actually IS at that lateral position.
        # Measured from the midline it lands 10 mm proud of the local surface, which is
        # what turns a pair of eyes into a pair of goggles.
        "eye_c_y": eye_surf + 0.0128 * s,
        "brow_z": chin_z + V * 0.600,
        "nose_root_z": chin_z + V * 0.512,
        "nose_base_z": chin_z + V * 0.360,
        "nose_tip": np.array([0.0, face_y - (0.013 + 0.005 * hs.nose) * s, chin_z + V * 0.392]),
        "mouth_z": chin_z + V * 0.240, "mouth_w": 0.0265 * hs.mouth_width * s,
        "chin_z": chin_z, "jaw_z": chin_z + V * 0.135,
        "cheek_z": chin_z + V * 0.385,
        "ear_c": np.array([w * 0.925, cy + 0.012 * s, chin_z + V * 0.425]),
        "ear_r": np.array([0.0055 * s, 0.0165 * hs.ears * s, V * 0.116 * hs.ears]),
        "hairline_z": chin_z + V * 0.715,
        "nape_z": chin_z + V * 0.300,
    }


def head_scene(skel: Skeleton, hs: Optional[HeadStyle] = None, with_neck: bool = True) -> Scene:
    """Head as an SDF scene.

    The skull and face are ONE loft from chin to crown, so the cranium can never overhang
    the face; features (brow, nose, lips, ears, eye mounds) are blended onto it and the
    detail (eye openings, mouth line, philtrum, nostrils) is carved out afterwards."""
    hs = hs or HeadStyle()
    L = head_landmarks(skel, hs)
    p = skel.props
    s = L["s"]
    fem = p.feminine
    old = p.age
    heavy = p.build
    V, w, d, cy = L["V"], L["half_w"], L["half_d"], L["cy"]
    z0 = L["chin_z"]
    eye_z, face_y = L["eye_z"], L["face_y"]
    mouth_z, jaw_z = L["mouth_z"], L["jaw_z"]
    jw = hs.jaw_width * (1 - 0.06 * fem) * (1 + 0.05 * heavy)
    fh = 0.96 + 0.08 * hs.forehead
    sc = Scene()

    # The head is built from its PROFILE: each station gives the half width and where the
    # front and back surfaces sit, in absolute y.  Working from the outline is the only way
    # to control a face -- the brow, nose, lips and chin have to line up in the side view or
    # nothing done to them afterwards will read.  (-y is forward.)
    F = face_y                                        # the front of the face at the eye line
    def prof(fz: float, fw: float, front: float, back: float) -> Tuple[np.ndarray, float, float]:
        return (np.array([0.0, 0.5 * (front + back), z0 + V * fz]), w * fw, 0.5 * (back - front))

    chin_y = F + (0.012 + 0.008 * (1.0 - hs.chin)) * s      # chin front, just behind the brow
    top_w, top_d = 0.800 * fh, 0.790
    fz_top = 1.0 - math.sqrt((w * top_w) * (d * top_d)) / V
    # widths as fractions of the bizygomatic half width, from the front-view outline of a
    # head: a definite corner at the jaw angle and a chin that is a plate, not a point.
    bot_fw, bot_front, bot_back = 0.400 * jw, chin_y, chin_y + 0.046 * s
    fz_bot = math.sqrt((w * bot_fw) * (0.5 * (bot_back - bot_front))) / V
    # The lower stations stop at the back of the jaw, NOT at the back of the skull: letting
    # them reach the nape skews the ellipse centre backwards so fast that the chin is
    # swallowed by the station above it.  The neck cone fills the space behind the jaw.
    skull = sdf.loft([
        prof(fz_bot,  bot_fw,       bot_front,      bot_back),            # chin; its cap is the plate
        prof(0.195, 0.620 * jw, chin_y - 0.003 * s, chin_y + 0.070 * s),  # mandible body
        prof(0.285, 0.855 * jw, F + 0.004 * s,      cy + d * 0.50),       # mouth and the jaw angle
        prof(0.375, 0.925,      F + 0.006 * s,      cy + d * 0.76),       # nose base / cheekbone
        prof(0.500, 0.985,      F,                  cy + d * 0.94),       # eye line
        prof(0.610, 1.000,      F + 0.005 * s,      cy + d * 0.985),      # temples: widest
        prof(0.775, 0.930,      F + 0.020 * s,      cy + d * 0.950),      # forehead
        prof(fz_top, top_w,     F + 0.052 * s,      cy + d * 0.82),       # its cap forms the crown
    ], LEFT, axis=UP)
    def surf_y(fx: float, fw: float, front: float, back: float) -> float:
        """Front-surface y of the profile station (fw, front, back) at lateral fraction `fx`
        of the half width.  Features placed off the midline have to follow the skull round,
        or they stand proud of it as wedges -- which is what a cheekbone must never do."""
        u = min(abs(fx) / max(fw, 1e-6), 0.995)
        return 0.5 * (front + back) - 0.5 * (back - front) * math.sqrt(1.0 - u * u)

    mass: List[sdf.Prim] = [skull]
    # back of the skull: fuller behind, and a flatter forehead plane
    mass.append(sdf.ellipsoid([0.0, cy + 0.002 * s, z0 + V * 0.635], [w * 0.94, d * 0.64, V * 0.245], k=0.026 * s))
    # cheekbones
    for sx in (1, -1):
        # soft tissue over the maxilla: fills the hollow the cheekbone would otherwise leave
        fill_y = surf_y(0.430, 0.880, F + 0.006 * s, cy + d * 0.87) + 0.011 * s
        mass.append(sdf.ellipsoid([sx * w * 0.480, fill_y, L["cheek_z"] - 0.020 * s],
                                  [0.026 * s, 0.013 * s, 0.030 * s], k=0.030 * s))
        cb_y = surf_y(0.560, 0.920, F + 0.005 * s, cy + d * 0.90) + 0.010 * s
        mass.append(sdf.ellipsoid([sx * w * 0.560, cb_y, L["cheek_z"] + 0.010 * s],
                                  [0.030 * hs.cheeks * s, 0.019 * s, 0.012 * s],
                                  rot=rig.rot_axis(FWD, math.radians(-14.0 * sx)), k=0.024 * s))
    cheek_amt = 0.04 + 0.40 * heavy - 0.24 * old
    if cheek_amt > 0.08:
        for sx in (1, -1):
            jw_y = surf_y(0.450, 0.800, F + 0.005 * s, cy + d * 0.80) + 0.012 * s
            mass.append(sdf.ellipsoid([sx * w * 0.450, jw_y, mouth_z + 0.026 * s],
                                      [0.016 * s, 0.014 * s, 0.020 * s * (0.8 + 0.5 * cheek_amt)], k=0.020 * s))
    # Gonial angle: the corner where the jaw turns up to the ear.  It is the only part of a
    # mandible an ellipse cross-section cannot give, so it stays as its own small mass.
    gon_z = z0 + V * 0.255
    chin_front = chin_y
    for sx in (1, -1):
        mass.append(sdf.ellipsoid([sx * w * 0.790 * jw, cy + 0.006 * s, gon_z + V * 0.038],
                                  [0.011 * s, 0.024 * s, 0.026 * s], k=0.014 * s))
    # chin pad
    mass.append(sdf.ellipsoid([0.0, chin_front + 0.006 * s, z0 + V * 0.115],
                              [0.019 * jw * s, 0.009 * hs.chin * s, 0.020 * hs.chin * s], k=0.016 * s))
    # soft tissue under the chin / throat, so the jaw is not a floating wire
    mass.append(sdf.ellipsoid([0.0, cy + 0.006 * s, z0 + V * 0.150],
                              [w * 0.30 * jw, d * 0.30, V * 0.075], k=0.024 * s))
    # brow ridge
    brow_r = (0.0074 + 0.0040 * hs.brow - 0.0028 * fem) * s
    for sx in (1, -1):
        brow_out_y = surf_y(0.600, 1.000, F + 0.005 * s, cy + d * 0.985) + 0.009 * s
        mass.append(sdf.round_cone([sx * 0.004 * s, face_y + 0.002 * s, L["brow_z"] - 0.003 * s],
                                   [sx * w * 0.60, brow_out_y, L["brow_z"] + 0.004 * s],
                                   brow_r * 1.10, brow_r * 0.62, k=0.012 * s))
    # eye mounds (the lids sit on the eyeball)
    er = L["eye_r"]
    for sx in (1, -1):
        ec = np.array([sx * L["eye_x"], L["eye_c_y"], eye_z])
        mass.append(sdf.ellipsoid(ec, [er * 1.22, er * 1.02, er * 0.94], k=0.016 * s))
    # nose
    root = np.array([0.0, face_y + 0.005 * s, L["nose_root_z"]])
    tip = L["nose_tip"]
    bridge_r = (0.0086 + 0.0038 * hs.nose_bridge) * s
    mass.append(sdf.tube_path([root, (root + tip) * 0.5 + np.array([0.0, 0.004 * s, 0.0]), tip],
                              [bridge_r * 1.00, bridge_r * 0.92, (0.0086 + 0.0030 * hs.nose) * s], k=0.0070 * s))
    for sx in (1, -1):
        mass.append(sdf.ellipsoid(tip + np.array([sx * 0.0122 * hs.nose * s, 0.0094 * s, -0.0022 * s]),
                                  [0.0082 * hs.nose * s, 0.0082 * s, 0.0066 * s], k=0.0055 * s))
    # lips
    mw = L["mouth_w"]
    lip_y = face_y + 0.004 * s
    lip = 0.7 + 0.5 * hs.lips + 0.25 * fem
    # Lips follow the curve of the jaw: the corners sit further back and a little lower than
    # the centre, so the mouth reads as a mouth rather than a band across the face.
    def lip_arc(z_off: float, half_w: float, r: float, back: float, drop: float):
        pts, rr = [], []
        for f in (-1.0, -0.55, 0.0, 0.55, 1.0):
            pts.append([f * half_w, lip_y + back * (f * f) * s, mouth_z + z_off - drop * (f * f) * s])
            rr.append(r * (0.55 + 0.45 * (1.0 - f * f)))
        return sdf.tube_path(pts, rr, k=0.0075 * s)
    mass.append(lip_arc(0.0070 * s, mw * 0.82, 0.0072 * lip * s, 0.0060, 0.0035))
    mass.append(lip_arc(-0.0082 * s, mw * 0.72, 0.0082 * lip * s, 0.0055, 0.0020))
    # ears
    for sx in (1, -1):
        e = L["ear_c"] * np.array([sx, 1, 1])
        rot = rig.rot_axis(UP, math.radians(-22.0 * sx)) @ rig.rot_axis(FWD, math.radians(7.0 * sx))
        mass.append(sdf.ellipsoid(e, L["ear_r"], rot=rot, k=0.006 * s))
        mass.append(sdf.ellipsoid(e + np.array([sx * 0.001 * s, 0.002 * s, -L["ear_r"][2] * 0.82]),
                                  [L["ear_r"][0] * 1.05, L["ear_r"][1] * 0.72, L["ear_r"][2] * 0.28], rot=rot, k=0.004 * s))
    if with_neck:
        bs = p.height / rig.DEFAULT_HEIGHT
        nr = (0.0500 - 0.007 * fem - 0.004 * old) * p.bulk * bs
        mass.append(sdf.round_cone(L["head"] + np.array([0.0, 0.012 * bs, -0.090 * bs]),
                                   L["head"] + np.array([0.0, 0.016 * bs, 0.006 * bs]), nr * 1.12, nr * 0.94, k=0.020 * s))
    sc.union(sdf.group(mass, internal_k=0.018 * s))

    # -- carved detail --------------------------------------------------------------------
    # eye opening: an almond pocket in the mound; its rim reads as the lids and the separate
    # eyeball mesh sits inside it
    for sx in (1, -1):
        ec = np.array([sx * L["eye_x"], L["eye_c_y"], eye_z])
        tilt = rig.rot_axis(FWD, math.radians(8.0 * sx))
        # the opening: a shallow almond window cut forward of the eyeball centre, so the lid
        # rim stays thick enough to survive decimation.  Lashes and the lid line are painted.
        # A THIN lens cut forward of the eyeball: it opens the lids and no more.  Cutting
        # deeper carves an orbit, and an orbit on a bald head is a skull.
        sc.subtract(sdf.ellipsoid(ec + np.array([0.0, -er * 0.66, 0.0]),
                                  [er * 1.30, er * 0.62, er * 0.62], rot=tilt), k=0.0040 * s)
        # upper lid crease: a shallow score above the opening, not a second socket
        sc.subtract(sdf.ellipsoid(ec + np.array([0.0, -er * 0.44, er * 1.02]),
                                  [er * 0.98, er * 0.22, er * 0.20], rot=tilt), k=0.008 * s)
        # inner corner, just enough to break the lid line
        sc.subtract(sdf.sphere(ec + np.array([-sx * er * 1.08, -er * 0.62, -0.001 * s]), er * 0.22), k=0.004 * s)
    # mouth line
    line_pts, line_r = [], []
    for f in (-1.0, -0.5, 0.0, 0.5, 1.0):
        line_pts.append([f * mw * 0.88, lip_y - 0.010 * s + 0.0070 * (f * f) * s, mouth_z - 0.0030 * (f * f) * s])
        line_r.append(0.0019 * s)
    sc.subtract(sdf.tube_path(line_pts, line_r), k=0.0035 * s)
    # philtrum
    sc.subtract(sdf.capsule([0.0, face_y - 0.004 * s, mouth_z + 0.011 * s],
                            [0.0, face_y - 0.004 * s, mouth_z + 0.018 * s], 0.0024 * s), k=0.005 * s)
    # nostrils
    for sx in (1, -1):
        sc.subtract(sdf.sphere(tip + np.array([sx * 0.0076 * s, 0.0082 * s, -0.0070 * s]), 0.0030 * s), k=0.0026 * s)
    # ear bowl
    for sx in (1, -1):
        e = L["ear_c"] * np.array([sx, 1, 1])
        rot = rig.rot_axis(UP, math.radians(-22.0 * sx)) @ rig.rot_axis(FWD, math.radians(7.0 * sx))
        sc.subtract(sdf.ellipsoid(e + rot @ np.array([sx * 0.0050 * s, -0.0035 * s, -0.002 * s]),
                                  [0.0042 * s, 0.0062 * hs.ears * s, L["ear_r"][2] * 0.44], rot=rot), k=0.0055 * s)
    # naso-labial crease with age
    if old > 0.45:
        amt = (old - 0.45) / 0.55
        for sx in (1, -1):
            sc.subtract(sdf.round_cone([sx * (mw * 0.55), face_y + 0.018 * s, mouth_z + 0.028 * s],
                                       [sx * (mw * 1.20), face_y + 0.026 * s, mouth_z - 0.012 * s],
                                       0.0030 * amt * s, 0.0042 * amt * s), k=0.005 * s)
    return sc


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
    for i in range(nv):
        for j in range(nu):
            a = i * (nu + 1) + j
            faces.append([a, a + 1, a + nu + 2, a + nu + 1])
    return np.asarray(verts), faces, np.asarray(uvs)


# --------------------------------------------------------------------------------------
# hair and beards: shells grown from head regions
# --------------------------------------------------------------------------------------

def scalp_field(verts: np.ndarray, skel: Skeleton, hs: HeadStyle, front: float = 1.0, sides: float = 1.0,
                back: float = 1.0) -> np.ndarray:
    """Signed 'hairiness' (>0 = covered) over the head surface.  `front` lowers/raises the
    hairline, `sides` covers the temples/over the ears, `back` reaches down the nape."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    eye_z = L["eye_z"]
    fy = L["face_y"]
    # -1 at the back, +1 at the face
    fwdness = np.clip((L["skull_c"][1] - y) / max(abs(L["skull_c"][1] - fy), 1e-6), -1.2, 1.2)
    ff = np.clip(fwdness, 0, 1)
    bb = np.clip(-fwdness, 0, 1)
    z_front = eye_z + (0.075 - 0.022 * front) * s
    z_side = eye_z + (0.055 - 0.040 * sides) * s
    z_back = eye_z + (0.020 - 0.085 * back) * s
    zl = z_side * np.clip(1 - ff - bb, 0, 1) + z_front * ff + z_back * bb
    # widow's-peak dip / temple recession
    temple = np.exp(-0.5 * (((np.abs(x) - 0.055 * s) / (0.020 * s)) ** 2)) * ff
    peak = np.exp(-0.5 * ((x / (0.016 * s)) ** 2)) * ff
    zl = zl + temple * 0.016 * s - peak * 0.010 * s
    f = (z - zl) / (0.02 * s)
    # never on the face below the brow
    f = np.minimum(f, np.where((ff > 0.55) & (z < eye_z + 0.055 * s), -1.0, 10.0))
    return f


def beard_field(verts: np.ndarray, normals: np.ndarray, skel: Skeleton, hs: HeadStyle,
                moustache: bool = True, cheeks: float = 1.0, length: float = 1.0) -> np.ndarray:
    """Signed beard coverage over the head surface."""
    L = head_landmarks(skel, hs)
    s = L["s"]
    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    eye_z, mouth_z, chin_z = L["eye_z"], L["mouth_z"], L["chin_z"]
    top = (eye_z - 0.030 * s) * cheeks + (L["mouth_z"] + 0.008 * s) * (1 - cheeks)
    f = np.minimum(top - z, z - (chin_z - 0.09 * s * length)) / (0.012 * s)
    f = np.minimum(f, (0.045 * s - y) / (0.01 * s))            # front half only
    f = np.minimum(f, (0.72 - normals[:, 2]) / 0.2)            # not the top of the head
    # keep the lips bare
    lips = ((np.abs(x) < L["mouth_w"] * 1.15) & (np.abs(z - mouth_z) < 0.009 * s) & (y < 0.02 * s))
    f = np.where(lips, -1.0, f)
    if not moustache:
        f = np.where((z > mouth_z) & (np.abs(x) < L["mouth_w"] * 1.5) & (y < 0.02 * s), -1.0, f)
    else:
        must = (z > mouth_z + 0.004 * s) & (z < mouth_z + 0.026 * s) & (np.abs(x) < L["mouth_w"] * 1.5) & (y < 0.02 * s)
        f = np.where(must, np.maximum(f, 1.0), f)
    return f


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
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        ob.data.use_auto_smooth = True
        ob.data.auto_smooth_angle = math.radians(angle_deg)
    except AttributeError:      # Blender >= 4.1
        pass


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
