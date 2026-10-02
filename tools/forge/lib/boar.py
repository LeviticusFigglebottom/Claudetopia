"""The bristleback: the Vale's boar (core:enemy/bristleback), on WM_Quadruped_v1.

WORLD_BIBLE §8: "a boar armoured in its own stiff hair; charges, tusks up". A wild boar 0.95 m at
the shoulder and 1.6 m long: the weight all in the forehand -- a deep, narrow, wedge of a chest
under a high shoulder -- falling away to small quarters; short stout legs on small cloven hooves;
the long wedge of the head running down to a disc of a snout, the tusks curling up out of the
lower jaw; small pricked ears; and the crest, a hedge of long bristles from the poll down the
spine that the lore says stands up before it charges.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict

import numpy as np

from . import sdf, paint
from .quadruped import QuadSkeleton, QuadProportions
from . import horse_body as hb
from . import beast_body as bb

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

JOINTS = {
    "Hips": (0.0, 0.42, 0.84), "TailHead": (0.0, 0.66, 0.79), "Spine1": (0.0, 0.42, 0.84),
    "Spine2": (0.0, 0.05, 0.90), "Chest": (0.0, -0.28, 0.93), "Neck1": (0.0, -0.46, 0.84),
    "Neck2": (0.0, -0.60, 0.77), "Head": (0.0, -0.70, 0.73), "Muzzle": (0.0, -1.05, 0.41),
    "Jaw": (0.0, -0.78, 0.58), "Chin": (0.0, -0.98, 0.39),
    "Ear.L": (0.075, -0.70, 0.80), "EarTip.L": (0.15, -0.67, 0.91),
    "Tail1": (0.0, 0.66, 0.79), "Tail2": (0.0, 0.71, 0.70), "Tail3": (0.0, 0.73, 0.61), "TailTip": (0.0, 0.74, 0.52),
    "Scapula.L": (0.10, -0.20, 0.88), "Humerus.L": (0.16, -0.42, 0.58), "Forearm.L": (0.155, -0.30, 0.42),
    "FrontCannon.L": (0.15, -0.33, 0.20), "FrontPastern.L": (0.15, -0.35, 0.085), "FrontHoof.L": (0.15, -0.38, 0.035),
    "FrontToe.L": (0.15, -0.43, 0.0),
    "Thigh.L": (0.14, 0.48, 0.74), "Gaskin.L": (0.17, 0.30, 0.48), "HindCannon.L": (0.145, 0.50, 0.27),
    "HindPastern.L": (0.145, 0.46, 0.085), "HindHoof.L": (0.145, 0.42, 0.035), "HindToe.L": (0.145, 0.37, 0.0),
}
PROPS = QuadProportions(withers=0.95, body_length=0.75, leg_length=0.6, neck_length=0.5, head_size=0.8,
                        bulk=1.1, width=0.95, tail_length=0.3)
TRUNK = ((-0.52, 0.80, 0.52, 0.09), (-0.44, 0.93, 0.44, 0.18), (-0.30, 0.99, 0.40, 0.235),
         (-0.12, 0.98, 0.40, 0.245), (0.08, 0.93, 0.42, 0.235), (0.28, 0.885, 0.45, 0.21),
         (0.46, 0.86, 0.50, 0.19), (0.60, 0.81, 0.55, 0.15), (0.69, 0.73, 0.60, 0.07))


@dataclass
class BoarStyle:
    kind: str = "boar"
    crest: float = 1.0
    seed: int = 41

    def to_dict(self) -> dict:
        return asdict(self)


def make_skel() -> QuadSkeleton:
    return QuadSkeleton(PROPS, joints=JOINTS)


def head_axes(skel):
    J = skel.J
    poll, muz = J["Head"], J["Muzzle"]
    hl = float(np.linalg.norm(muz - poll))
    hu = (muz - poll) / hl
    dn = bb._u(np.cross(hu, X))
    if dn[2] > 0:
        dn = -dn
    return poll, hu, dn, hl


def H(skel, a, d, x=0.0):
    poll, hu, dn, hl = head_axes(skel)
    return poll + hu * a * hl + dn * d + X * x


def mouth_line(skel):
    return H(skel, 0.30, 0.10), H(skel, 0.93, 0.045)


def boar_scene(skel: QuadSkeleton, st: BoarStyle, bare: bool = False) -> sdf.Scene:
    J = skel.J
    sc = sdf.Scene()
    sc.union(hb.section_loft(TRUNK))
    # the shield: the massive shoulders and the high crest of the withers
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(np.array([sx * 0.13, -0.30, 0.74]), np.array([0.13, 0.22, 0.22])), k=0.08)
    sc.union(sdf.ellipsoid(np.array([0.0, -0.36, 0.86]), np.array([0.16, 0.2, 0.14])), k=0.08)
    # the neck: short and as thick as the head, running straight into the shoulders
    n1, n2, hd = J["Neck1"], J["Neck2"], J["Head"]
    sc.union(sdf.sweep([(n1 + np.array([0.0, 0.08, -0.04]), 0.19, 0.24), (n2, 0.16, 0.19), (hd + np.array([0.0, 0.03, -0.06]), 0.13, 0.15)],
                       X), k=0.08)
    # the head: a long wedge, deep and broad at the jowls, down to the snout's disc
    poll, hu, dn, hl = head_axes(skel)
    rot = bb._frame(hu, X)
    sc.union(sdf.ellipsoid(H(skel, 0.12, 0.05), np.array([0.12, 0.13, 0.15]), rot=rot), k=0.06)
    sc.union(sdf.elliptic_cone(H(skel, 0.22, 0.05), H(skel, 0.92, 0.025), 0.115, 0.125, 0.056, 0.058, X, squash_v_neg=0.2), k=0.06)
    # the snout's disc, flat on its end
    tip = H(skel, 0.96, 0.03)
    sc.union(sdf.capsule(tip - hu * 0.02, tip + hu * 0.015, 0.058), k=0.02)
    for sx in (1.0, -1.0):
        sc.subtract(sdf.sphere(tip + hu * 0.06 + X * sx * 0.022, 0.016), k=0.004)
    # the jowls and the lower jaw
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(H(skel, 0.26, 0.13, sx * 0.07), np.array([0.06, 0.09, 0.08]), rot=rot), k=0.05)
    sc.union(sdf.elliptic_cone(H(skel, 0.22, 0.15), H(skel, 0.86, 0.085), 0.08, 0.05, 0.035, 0.025, X), k=0.04)
    corner, mtip = mouth_line(skel)
    along = mtip - corner
    L = float(np.linalg.norm(along))
    sc.subtract(sdf.box(0.5 * (corner + mtip) + bb._u(along) * 0.02, np.array([0.09, 0.0035, L * 0.5 + 0.02]),
                        rot=bb._frame(along, X)), k=0.002)
    # the tusks: out of the lower jaw ahead of the mouth's corner, curling up and back
    for sx in (1.0, -1.0):
        b0 = H(skel, 0.66, 0.07, sx * 0.05)
        pts = [b0, b0 + X * sx * 0.035 - dn * 0.05 + hu * 0.01, b0 + X * sx * 0.06 - dn * 0.10 - hu * 0.04,
               b0 + X * sx * 0.06 - dn * 0.13 - hu * 0.10]
        sc.union(sdf.tube_path(pts, [0.018, 0.015, 0.011, 0.004]), k=0.006)
        # the upper tusk, short, whetting the lower
        u0 = H(skel, 0.70, 0.03, sx * 0.06)
        sc.union(sdf.tube_path([u0, u0 + X * sx * 0.03 - dn * 0.03 - hu * 0.03], [0.012, 0.004]), k=0.005)
    # the eyes, small and deep under the brow
    for sx in (1.0, -1.0):
        sc.union(sdf.sphere(H(skel, 0.28, -0.015, sx * 0.085), 0.016), k=0.006)
    # the ears: small, pointed, pricked
    for side, sx in (("L", 1.0), ("R", -1.0)):
        e0, e1 = J["Ear." + side], J["EarTip." + side]
        sc.union(sdf.elliptic_cone(e0 - (e1 - e0) * 0.2, e1, 0.05, 0.016, 0.006, 0.004, bb._u(np.cross(e1 - e0, -hu))), k=0.015)
    # the legs: short, stout, on small cloven hooves
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for fore in (True, False):
            if fore:
                top, a, b_, fet, cor, toe = (J["Humerus." + side], J["Forearm." + side], J["FrontCannon." + side],
                                             J["FrontPastern." + side], J["FrontHoof." + side], J["FrontToe." + side])
                sc.union(sdf.elliptic_cone(top, a + np.array([0, 0.02, 0.02]), 0.1, 0.13, 0.085, 0.1, X), k=0.06)
                sc.union(sdf.elliptic_cone(a, b_, 0.075, 0.085, 0.05, 0.055, X), k=0.04)
            else:
                top, a, b_, fet, cor, toe = (J["Thigh." + side], J["Gaskin." + side], J["HindCannon." + side],
                                             J["HindPastern." + side], J["HindHoof." + side], J["HindToe." + side])
                sc.union(sdf.elliptic_cone(top + np.array([0, 0.03, 0.05]), a + np.array([0, 0.05, 0.0]), 0.1, 0.16, 0.07, 0.09, X), k=0.08)
                sc.union(sdf.elliptic_cone(a + np.array([0, 0.03, 0]), b_, 0.075, 0.095, 0.045, 0.055, X), k=0.04)
            sc.union(sdf.round_cone(b_, fet, 0.047, 0.04), k=0.02)
            sc.union(sdf.round_cone(fet, cor, 0.04, 0.036), k=0.015)
            sc.union(hb.hoof_cone(skel, cor, 0.55), k=0.01)
            sc.subtract(sdf.box(np.array([cor[0], toe[1] + 0.015, 0.025]), np.array([0.004, 0.03, 0.04])), k=0.003)
            # the dew claws behind
            for dx in (0.022, -0.022):
                sc.union(sdf.round_cone(fet + np.array([dx, 0.03, -0.02]), fet + np.array([dx, 0.045, -0.06]), 0.012, 0.007), k=0.005)
    # the tail: thin, with a tassel
    sc.union(sdf.tube_path([J["Tail1"], J["Tail2"], J["Tail3"], J["TailTip"]], [0.025, 0.018, 0.016, 0.028]), k=0.02)
    if not bare and st.crest > 0:
        _crest(sc, skel, st)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    if bare:
        return sc
    n1 = paint.Noise(st.seed + 3, 64)

    def disp(P):
        # coarse, stiff hair everywhere, longer and shaggier over the shoulders and the neck
        R = regions(skel, P, st, fine=False)
        Q = P * np.array([1.0, 0.45, 0.7])
        clump = n1.fbm(Q, freq=40.0, octaves=2)
        long_ = 0.6 + 0.8 * R["shield"]
        return 0.012 * (clump - 0.45) * long_ * (1.0 - R["snout"]) * (1.0 - R["hoof"]) * (1.0 - R["tusk"])
    return bb.Displaced(sc, disp, 0.02)


def _crest(sc, skel, st):
    """The hedge along the spine: long stiff bristles from the poll to the loin, leaning back."""
    J = skel.J
    rng = np.random.default_rng(st.seed + 7)
    line = [J["Head"] + np.array([0.0, 0.0, 0.10]), J["Neck2"] + np.array([0.0, 0.0, 0.17]),
            J["Neck1"] + np.array([0.0, 0.05, 0.20]), J["Chest"] + np.array([0.0, 0.0, 0.07]),
            J["Spine2"] + np.array([0.0, 0.0, 0.05]), J["Spine1"] + np.array([0.0, -0.1, 0.04])]
    pts = sdf._catmull_rom(np.array(line), np.linspace(0, len(line) - 1, 26))
    for i, p in enumerate(pts):
        f = i / len(pts)
        size = (0.10 + 0.08 * math.sin(math.pi * min(1.0, f * 1.4))) * st.crest * (0.8 + 0.4 * rng.random())
        for sx in ((0.0, 0.03) if i % 2 else (0.0, -0.03)):
            base = p + X * sx - Z * 0.02
            tip = base + bb._u(np.array([sx * 4.0 + rng.normal(0, 0.15), 0.55 + rng.normal(0, 0.1), 1.0])) * size
            sc.union(sdf.round_cone(base, tip, 0.016, 0.003), k=0.012)


def regions(skel, P, st, fine=True) -> Dict[str, np.ndarray]:
    J = skel.J
    sm = bb.sm
    R = {}
    poll, hu, dn, hl = head_axes(skel)
    rel = P - poll
    along = rel @ hu / hl
    R["snout"] = sm(0.9, 0.95, along) * (1.0 - sm(0.07, 0.1, np.linalg.norm(rel - np.outer(rel @ hu, hu), axis=1)))
    R["face"] = sm(0.0, 0.1, along) * (1.0 - sm(0.12, 0.2, np.linalg.norm(rel - np.outer(rel @ hu, hu), axis=1)))
    R["hoof"] = 1.0 - sm(0.06, 0.09, P[:, 2])
    R["legs"] = 1.0 - sm(0.35, 0.5, P[:, 2])
    R["tusk"] = np.zeros(len(P))
    for sx in (1.0, -1.0):
        b0 = H(skel, 0.66, 0.07, sx * 0.05)
        tipt = b0 + X * sx * 0.06 - dn * 0.13 - hu * 0.10
        d, u = bb._seg(P, b0 - dn * 0.02, tipt)
        R["tusk"] = np.maximum(R["tusk"], (1.0 - sm(0.018, 0.026, d)) * sm(0.1, 0.25, u))
        ut = H(skel, 0.70, 0.03, sx * 0.06)
        d2, _ = bb._seg(P, ut, ut + X * sx * 0.03 - dn * 0.03 - hu * 0.03)
        R["tusk"] = np.maximum(R["tusk"], (1.0 - sm(0.012, 0.018, d2)))
    d_c, _ = bb._seg(P, J["Head"], J["Spine1"])
    R["crest"] = sm(0.0, 0.05, P[:, 2] - np.interp(P[:, 1], [J["Head"][1], J["Chest"][1], J["Spine1"][1]],
                                                     [J["Head"][2] + 0.08, J["Chest"][2] + 0.04, J["Spine1"][2] + 0.03]))
    R["shield"] = (1.0 - sm(0.25, 0.4, np.abs(P[:, 1] - (-0.40)))) * sm(0.55, 0.75, P[:, 2])
    R["belly"] = 1.0 - sm(0.42, 0.55, P[:, 2])
    R["belly"] *= (P[:, 1] > -0.45) & (P[:, 1] < 0.6)
    R["eye"] = np.zeros(len(P))
    for sx in (1.0, -1.0):
        R["eye"] = np.maximum(R["eye"], 1.0 - sm(0.014, 0.02, np.linalg.norm(P - H(skel, 0.28, -0.015, sx * 0.085), axis=1)))
    corner, mtip = mouth_line(skel)
    d_m, _ = bb._seg(P, corner, mtip)
    R["mouth"] = 1.0 - sm(0.004, 0.01, d_m)
    R["ear"] = np.zeros(len(P))
    for side in ("L", "R"):
        d_e, _ = bb._seg(P, J["Ear." + side], J["EarTip." + side])
        R["ear"] = np.maximum(R["ear"], 1.0 - sm(0.04, 0.06, d_e))
    return R


def painter(spec, field):
    skel, st = spec.skel, spec.style
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 5, 64)
    body = np.array([0.30, 0.22, 0.16])      # the def's #5a4436, dark, the hair grizzled
    dark = np.array([0.12, 0.09, 0.07])
    grizzle = np.array([0.58, 0.50, 0.40])
    belly = np.array([0.40, 0.32, 0.25])
    snout = np.array([0.36, 0.25, 0.23])
    tusk = np.array([0.88, 0.84, 0.70])
    hoof = np.array([0.10, 0.08, 0.07])

    def albedo(P, nrm):
        R = regions(skel, P, st)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.08, samples=5, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=3.0, octaves=3)
        hair = n2.fbm(P * np.array([1.0, 0.4, 1.0]), freq=90.0, octaves=2)
        c = np.broadcast_to(body, (len(P), 3)).copy() * (0.85 + 0.3 * big)[:, None]
        # the grizzle: pale tips to the bristles on the back and the shield
        c = paint.mix(c, grizzle, 0.35 * bb.sm(0.55, 0.8, hair) * bb.sm(0.0, 0.7, up))
        c = paint.mix(c, dark, 0.7 * R["crest"])
        c = paint.mix(c, dark, 0.5 * R["legs"])
        c = paint.mix(c, belly, 0.4 * R["belly"])
        c = paint.mix(c, dark, 0.45 * R["face"] * bb.sm(0.0, 0.6, up))
        c = paint.mix(c, snout, R["snout"])
        c = paint.mix(c, np.array([0.08, 0.05, 0.05]), R["mouth"])
        c = paint.mix(c, dark, 0.6 * R["ear"])
        c = paint.mix(c, hoof, R["hoof"])
        c = paint.mix(c, tusk * (0.85 + 0.2 * big)[:, None], R["tusk"])
        c = paint.mix(c, np.array([0.03, 0.02, 0.02]), R["eye"])
        # mud: the wallow's, caked to the knees and the belly
        mud = bb.sm(0.62, 0.38, P[:, 2] / 0.95 + 0.25 * (n1.fbm(P, freq=8.0, octaves=2) - 0.5)) * (1.0 - R["tusk"])
        c = paint.mix(c, np.array([0.30, 0.25, 0.18]), 0.45 * mud * (1.0 - R["hoof"]))
        v = (0.5 + 0.5 * occ) * (0.85 + 0.25 * hair)
        v = np.maximum(v, R["eye"])
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = regions(skel, P, st)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.08, samples=5, strength=1.2)
        rough = 0.9 - 0.4 * R["tusk"] - 0.3 * R["snout"] - 0.8 * R["eye"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.06, 0.97), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        return n2.fbm(P * np.array([1.0, 0.4, 1.0]), freq=90.0, octaves=2)

    return albedo, orm, height


def bare_scene(spec):
    return boar_scene(spec.skel, spec.style, bare=True)
