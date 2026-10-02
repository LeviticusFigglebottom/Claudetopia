"""The reptiles: the sallowjaw (core:enemy/sallowjaw) and the gutter drake (core:enemy/gutter_drake),
on WM_Quadruped_v1 with sprawled legs (lib/foe_clips.FoeSolver.splay).

WORLD_BIBLE §8: the sallowjaw is the Sedgemire's crocodilian -- "waits as a log, lunges with a bite
that drags": 2.8 m from snout to tail, the long flat head a third of a metre wide at the jaws'
hinge, armoured with rows of scutes, the tail as long as the body and flattened to swim. The gutter
drake is Brightwater's sewer lizard, cat-sized: a short-snouted, long-legged drake whose back "has
taken the shape of the pipes" -- raised bands round it like a pipe's joints -- slick and dark.

The rig's names stay the horse's: the "cannon" is the metacarpus, the "pastern" the toes, the
"hoof" the claws; the ears are two nubs behind the eyes.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict, Tuple

import numpy as np

from . import sdf, paint
from .quadruped import QuadSkeleton, QuadProportions
from . import horse_body as hb
from . import beast_body as bb

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])

# The sallowjaw standing in its high walk, metres.
CROC = {
    "Hips": (0.0, 0.38, 0.38), "TailHead": (0.0, 0.58, 0.34), "Spine1": (0.0, 0.38, 0.38), "Spine2": (0.0, 0.0, 0.40),
    "Chest": (0.0, -0.30, 0.38), "Neck1": (0.0, -0.44, 0.36), "Neck2": (0.0, -0.54, 0.36), "Head": (0.0, -0.62, 0.37),
    "Muzzle": (0.0, -1.18, 0.24), "Jaw": (0.0, -0.58, 0.28), "Chin": (0.0, -1.13, 0.18),
    "Ear.L": (0.07, -0.66, 0.43), "EarTip.L": (0.075, -0.72, 0.45),
    "Tail1": (0.0, 0.58, 0.34), "Tail2": (0.0, 0.98, 0.24), "Tail3": (0.0, 1.38, 0.13), "TailTip": (0.0, 1.74, 0.05),
    "Scapula.L": (0.12, -0.24, 0.36), "Humerus.L": (0.19, -0.32, 0.28), "Forearm.L": (0.31, -0.25, 0.20),
    "FrontCannon.L": (0.33, -0.31, 0.055), "FrontPastern.L": (0.335, -0.35, 0.02), "FrontHoof.L": (0.34, -0.40, 0.01),
    "FrontToe.L": (0.35, -0.45, 0.0),
    "Thigh.L": (0.17, 0.36, 0.30), "Gaskin.L": (0.33, 0.25, 0.22), "HindCannon.L": (0.35, 0.38, 0.065),
    "HindPastern.L": (0.355, 0.30, 0.02), "HindHoof.L": (0.36, 0.24, 0.01), "HindToe.L": (0.37, 0.17, 0.0),
}
CROC_TRUNK = ((-0.56, 0.42, 0.29, 0.12), (-0.44, 0.46, 0.21, 0.20), (-0.26, 0.49, 0.15, 0.27), (0.0, 0.50, 0.13, 0.30),
              (0.24, 0.49, 0.15, 0.28), (0.42, 0.46, 0.19, 0.22), (0.58, 0.42, 0.25, 0.15))


def scaled(joints, k: float, leg: float = 1.0, head: float = 1.0, tail: float = 1.0, head_up: float = 0.0):
    """The sallowjaw's joints for another reptile: `k` the whole, `leg` the legs' length (the trunk
    rides on them), `head` the head's length about the poll."""
    legs = {"Scapula", "Humerus", "Forearm", "FrontCannon", "FrontPastern", "FrontHoof", "FrontToe",
            "Thigh", "Gaskin", "HindCannon", "HindPastern", "HindHoof", "HindToe"}
    head_parts = {"Muzzle", "Jaw", "Chin", "Ear", "EarTip"}
    top = 0.26
    out = {}
    for n, (x, y, z) in joints.items():
        b = n[:-2] if n[-2:] in (".L", ".R") else n
        if b in legs and z < top:
            zz = z * leg
        else:
            zz = top * leg + (z - top)
        out[n] = (x * k, y * k, zz * k)
    poll = np.array(joints["Head"])
    p2 = np.array(out["Head"])
    for n, (x, y, z) in joints.items():
        b = n[:-2] if n[-2:] in (".L", ".R") else n
        if b in head_parts:
            d = (np.array([x, y, z]) - poll) * np.array([1.0, head, 1.0])
            out[n] = tuple((p2 + d * k).tolist())
    t1 = np.array(out["Tail1"])
    for n in ("Tail2", "Tail3", "TailTip"):
        out[n] = tuple((t1 + (np.array(out[n]) - t1) * tail).tolist())
    for n in ("Neck2", "Head", "Muzzle", "Jaw", "Chin", "Ear.L", "EarTip.L"):
        f = 0.5 if n == "Neck2" else 1.0
        x, y, z = out[n]
        out[n] = (x, y, z + head_up * k * f)
    return out


def scaled_trunk(trunk, k: float, leg: float = 1.0):
    top = 0.26
    return tuple((y * k, (top * leg + (t - top)) * k, (top * leg + (b - top)) * k, w * k) for y, t, b, w in trunk)


@dataclass
class ReptileStyle:
    kind: str = "croc"        # croc | drake
    scutes: float = 1.0       # the rows of armour on the back
    bands: float = 0.0        # the drake's pipe-joint rings round the back
    horns: float = 0.0
    teeth: float = 1.0
    seed: int = 51

    def to_dict(self) -> dict:
        return asdict(self)


def head_axes(skel):
    J = skel.J
    poll, muz = J["Head"], J["Muzzle"]
    hl = float(np.linalg.norm(muz - poll))
    hu = (muz - poll) / hl
    dn = bb._u(np.cross(hu, X))
    if dn[2] > 0:
        dn = -dn
    return poll, hu, dn, hl


def k_of(skel) -> float:
    return skel.props.withers / 0.50


def H(skel, a, d, x=0.0):
    """A point of the head: `a` along it (0 the poll, 1 the snout's tip), `d` down from its top line
    and `x` across, both in the sallowjaw's metres scaled to this reptile."""
    poll, hu, dn, hl = head_axes(skel)
    k = k_of(skel)
    return poll + hu * a * hl + (dn * d + X * x) * k


def mouth_line(skel):
    return H(skel, 0.10, 0.075), H(skel, 0.97, 0.03)


def reptile_scene(skel: QuadSkeleton, st: ReptileStyle, trunk, bare: bool = False) -> sdf.Scene:
    J = skel.J
    k = k_of(skel)
    drake = st.kind == "drake"
    sc = sdf.Scene()
    sc.union(hb.section_loft(trunk))
    # the neck, thick, running straight into the head
    sc.union(sdf.sweep([(J["Chest"] + np.array([0.0, -0.1, 0.0]) * k, 0.2 * k, 0.13 * k),
                        (J["Neck2"], 0.16 * k, 0.1 * k), (J["Head"] + np.array([0.0, 0.0, -0.03]) * k, 0.15 * k, 0.09 * k)], X),
             k=0.06 * k)
    # the tail: tall and narrow, a long taper
    tail = [J["Tail1"] - np.array([0.0, 0.12, 0.0]) * k, J["Tail1"], J["Tail2"], J["Tail3"], J["TailTip"]]
    rs = [(0.15, 0.13), (0.13, 0.12), (0.085, 0.095), (0.045, 0.06), (0.012, 0.02)]
    sc.union(sdf.sweep([(p, r[0] * k, r[1] * k) for p, r in zip(tail, rs)], X, axis=None), k=0.08 * k)
    _head(sc, skel, st)
    # the legs: short and bowed, splayed out of the body's sides, on spread clawed feet
    for side, sx in (("L", 1.0), ("R", -1.0)):
        for fore in (True, False):
            names = (["Humerus", "Forearm", "FrontCannon", "FrontPastern", "FrontHoof", "FrontToe"] if fore else
                     ["Thigh", "Gaskin", "HindCannon", "HindPastern", "HindHoof", "HindToe"])
            p = [J["%s.%s" % (n, side)] for n in names]
            r0 = (0.075 if fore else 0.09) * k
            sc.union(sdf.round_cone(p[0] - X * sx * 0.03 * k, p[1], r0, r0 * 0.75), k=0.05 * k)
            sc.union(sdf.round_cone(p[1], p[2], r0 * 0.7, r0 * 0.5), k=0.03 * k)
            # the foot: a flat palm, toes spread forward and out, claws
            palm = 0.5 * (p[2] + p[3])
            palm[2] = 0.025 * k
            sc.union(sdf.round_cone(p[2], palm, r0 * 0.5, r0 * 0.45), k=0.015 * k)
            sc.union(sdf.ellipsoid(palm, np.array([0.05, 0.05, 0.025]) * k), k=0.02 * k)
            n_toes = 5 if fore else 4
            for i in range(n_toes):
                a = math.radians(-40.0 + 80.0 * i / (n_toes - 1)) * sx
                d = np.array([math.sin(a), -math.cos(a), 0.0])
                t0 = palm + d * 0.03 * k
                t1 = palm + d * (0.09 + 0.02 * (1 - abs(i - (n_toes - 1) / 2) / 2)) * k
                t1[2] = 0.006 * k
                sc.union(sdf.round_cone(t0, t1, 0.014 * k, 0.007 * k), k=0.008 * k)
                sc.union(sdf.round_cone(t1, t1 + d * 0.025 * k - Z * 0.004 * k, 0.006 * k, 0.0015 * k), k=0.003 * k)
    if not bare:
        if st.scutes > 0:
            _scutes(sc, skel, st, trunk)
        if st.horns > 0:
            for sx in (1.0, -1.0):
                b0 = H(skel, 0.05, -0.02, sx * 0.07)
                sc.union(sdf.tube_path([b0, b0 + np.array([sx * 0.03, 0.08, 0.04]) * k, b0 + np.array([sx * 0.035, 0.16, 0.02]) * k],
                                       [0.02 * k * st.horns, 0.012 * k * st.horns, 0.002 * k]), k=0.01 * k)
    sc.intersect(sdf.plane(np.zeros(3), np.array([0.0, 0.0, -1.0])))
    if bare:
        return sc
    n1 = paint.Noise(st.seed + 3, 64)

    def disp(P):
        R = regions(skel, P, st, trunk, fine=False)
        # a hide of small scales everywhere; the drake's pipe rings standing round its back
        sc_ = bb._cells(P, 45.0 / k, st.seed)
        out = 0.0025 * k * (1.0 - bb.sm(0.3, 0.7, sc_))
        if st.bands > 0:
            ring = np.abs(((P[:, 1] / k) * 13.0) % 1.0 - 0.5) * 2.0
            out = out + st.bands * 0.012 * k * bb.sm(0.7, 0.9, ring) * R["back"] * (1.0 - R["head"])
        return out + 0.002 * k * (n1.at(P, 60.0 / k) - 0.5)
    return bb.Displaced(sc, disp, 0.016 * k)


def _head(sc, skel, st):
    k = k_of(skel)
    poll, hu, dn, hl = head_axes(skel)
    rot = bb._frame(hu, X)
    drake = st.kind == "drake"
    # the skull's table behind the eyes, broad and flat, the jaw muscles bulging at its back
    sc.union(sdf.ellipsoid(H(skel, 0.12, 0.03), np.array([0.15, 0.13, 0.07]) * k, rot=rot), k=0.05 * k)
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(H(skel, 0.10, 0.07, sx * 0.1), np.array([0.06, 0.09, 0.06]) * k, rot=rot), k=0.04 * k)
    # the snout: long and flat (the drake's shorter and deeper), the upper jaw over the mouth's line
    w0, w1 = (0.15, 0.085) if not drake else (0.10, 0.05)
    h0, h1 = (0.05, 0.032) if not drake else (0.055, 0.035)
    sc.union(sdf.elliptic_cone(H(skel, 0.20, 0.035), H(skel, 0.95, 0.012), w0 * k, h0 * k, w1 * k, h1 * k, X,
                               squash_v_neg=0.4), k=0.04 * k)
    # the nostrils on a knob at the tip, the eyes standing proud on the skull's top
    sc.union(sdf.ellipsoid(H(skel, 0.95, -0.012), np.array([0.05, 0.035, 0.022]) * k, rot=rot), k=0.015 * k)
    for sx in (1.0, -1.0):
        sc.union(sdf.ellipsoid(H(skel, 0.20, -0.045, sx * 0.06), np.array([0.03, 0.035, 0.022]) * k, rot=rot), k=0.015 * k)
    # the lower jaw, its hinge behind the skull
    sc.union(sdf.elliptic_cone(H(skel, 0.05, 0.10), H(skel, 0.93, 0.05), (w0 + 0.01) * k, 0.04 * k, (w1 - 0.005) * k,
                               0.022 * k, X), k=0.04 * k)
    corner, tip = mouth_line(skel)
    along = tip - corner
    L = float(np.linalg.norm(along))
    sc.subtract(sdf.box(0.5 * (corner + tip) + bb._u(along) * 0.02 * k, np.array([0.2 * k, 0.005 * k, L * 0.5 + 0.03 * k]),
                        rot=bb._frame(along, X)), k=0.003 * k)
    # the teeth: a row down each side of both jaws, interlocking, the long ones near the front
    if st.teeth > 0:
        n = 12 if not drake else 8
        for i in range(n):
            f = 0.2 + 0.74 * i / (n - 1)
            for sx in (1.0, -1.0):
                w = (w0 + (w1 - w0) * (f - 0.2) / 0.75) * 0.92
                ln = (0.028 if i in (2, 3, n - 3) else 0.018) * k * st.teeth
                up_p = H(skel, f, 0.06 - 0.03 * f, sx * w)
                sc.union(sdf.round_cone(up_p, up_p + dn * ln, 0.007 * k, 0.0015 * k), k=0.003 * k)
                lo_p = H(skel, f + 0.035, 0.085 - 0.04 * f, sx * w * 0.95)
                sc.union(sdf.round_cone(lo_p, lo_p - dn * ln * 0.9, 0.006 * k, 0.0015 * k), k=0.003 * k)
    if drake:
        # a frill of short spines along the jaw's back edge
        for i, a in enumerate((0.0, 0.06, 0.12)):
            for sx in (1.0, -1.0):
                b0 = H(skel, a, 0.04 + 0.02 * i, sx * 0.12)
                sc.union(sdf.round_cone(b0, b0 + np.array([sx * 0.04, 0.05, 0.0]) * k, 0.012 * k, 0.002 * k), k=0.006 * k)


def _scutes(sc, skel, st, trunk):
    """The armour on the back: paired rows of keeled plates from the neck down the tail, the two
    middle rows the highest; on the tail they close into one row, the double crest of a swimmer."""
    J = skel.J
    k = k_of(skel)
    rng = np.random.default_rng(st.seed + 9)
    ys = [t[0] for t in trunk]
    tops = [t[1] for t in trunk]
    y0, y1 = J["Neck1"][1], J["Tail1"][1]
    n = 16
    for i in range(n):
        y = y0 + (y1 - y0) * i / (n - 1)
        top = float(np.interp(y, ys, tops)) if ys[0] <= y <= ys[-1] else J["Neck1"][2] + 0.09 * k
        for j, xo in enumerate((0.035, 0.085, 0.14)):
            if j == 2 and (i < 3 or i > n - 3):
                continue
            for sx in (1.0, -1.0):
                c = np.array([sx * xo * k, y, top - 0.012 * k * j])
                sz = (0.032 - 0.006 * j) * k * st.scutes * (0.85 + 0.3 * rng.random())
                sc.union(sdf.ellipsoid(c, np.array([sz * 0.9, sz * 1.2, sz * 0.55])), k=0.008 * k)
                sc.union(sdf.round_cone(c, c + Z * sz * 0.9 + Y * sz * 0.3, sz * 0.35, 0.002 * k), k=0.006 * k)
    # down the tail
    pts = sdf._catmull_rom(np.array([J["Tail1"], J["Tail2"], J["Tail3"], J["TailTip"]]), np.linspace(0, 2.6, 18))
    for i, p in enumerate(pts):
        f = i / len(pts)
        hgt = (0.12 - 0.08 * f) * k
        for sx in ((1.0, -1.0) if f < 0.45 else (0.0,)):
            c = p + Z * hgt * 0.8 + X * sx * 0.03 * k * (1.0 - f)
            sz = (0.03 - 0.015 * f) * k * st.scutes
            sc.union(sdf.round_cone(c - Z * sz, c + Z * sz * 1.2 + Y * sz * 0.4, sz * 0.6, 0.002 * k), k=0.006 * k)


def regions(skel, P, st, trunk, fine=True) -> Dict[str, np.ndarray]:
    J = skel.J
    k = k_of(skel)
    sm = bb.sm
    R = {}
    ys = [t[0] for t in trunk]
    mids = [0.5 * (t[1] + t[2]) for t in trunk]
    y = P[:, 1]
    mid = np.interp(y, ys + [J["Tail1"][1], J["Tail2"][1], J["Tail3"][1], J["TailTip"][1]],
                    mids + [J["Tail1"][2], J["Tail2"][2], J["Tail3"][2], J["TailTip"][2]])
    R["back"] = sm(mid - 0.01 * k, mid + 0.06 * k, P[:, 2])
    hw = np.interp(y, ys, [t[3] for t in trunk], left=0.0, right=0.0)
    R["belly"] = (1.0 - sm(mid - 0.12 * k, mid - 0.05 * k, P[:, 2])) * (1.0 - sm(hw * 0.6, hw * 0.95 + 1e-4, np.abs(P[:, 0])))
    poll, hu, dn, hl = head_axes(skel)
    rel = P - poll
    al = rel @ hu / hl
    R["head"] = sm(-0.05, 0.05, al) * (1.0 - sm(0.16 * k, 0.2 * k, np.linalg.norm(rel - np.outer(rel @ hu, hu), axis=1)))
    R["tail"] = sm(J["Tail1"][1], J["Tail1"][1] + 0.1 * k, y)
    R["feet"] = 1.0 - sm(0.03 * k, 0.06 * k, P[:, 2])
    R["eye"] = np.zeros(len(P))
    for sx in (1.0, -1.0):
        R["eye"] = np.maximum(R["eye"], 1.0 - sm(0.022 * k, 0.03 * k, np.linalg.norm(P - H(skel, 0.20, -0.06, sx * 0.065), axis=1)))
    corner, tip = mouth_line(skel)
    d_m, _ = bb._seg(P, corner, tip)
    R["mouth"] = (1.0 - sm(0.005 * k, 0.012 * k, d_m)) * R["head"]
    R["teeth"] = (1.0 - sm(0.006 * k, 0.016 * k, d_m)) * R["head"] * (1.0 - R["mouth"])
    R["claw"] = 1.0 - sm(0.004 * k, 0.012 * k, P[:, 2])
    R["claw"] *= sm(0.3 * k, 0.32 * k, np.abs(P[:, 0]))
    return R


def painter(spec, field):
    skel, st, trunk = spec.skel, spec.style, spec.extra["trunk"]
    k = k_of(skel)
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 5, 64)
    drake = st.kind == "drake"
    if drake:
        back, side, belly = np.array([0.15, 0.19, 0.16]), np.array([0.22, 0.27, 0.22]), np.array([0.55, 0.52, 0.36])
        band, band2 = np.array([0.42, 0.25, 0.12]), np.array([0.28, 0.42, 0.36])
        eye = np.array([0.9, 0.7, 0.1])
    else:
        back, side, belly = np.array([0.20, 0.22, 0.12]), np.array([0.33, 0.34, 0.19]), np.array([0.70, 0.65, 0.42])
        band, band2 = np.array([0.10, 0.11, 0.07]), np.array([0.40, 0.42, 0.22])
        eye = np.array([0.72, 0.65, 0.18])
    teeth = np.array([0.86, 0.82, 0.66])
    mouth = np.array([0.55, 0.38, 0.30])

    def albedo(P, nrm):
        R = regions(skel, P, st, trunk)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.08 * k, samples=5, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=3.0 / k, octaves=3)
        c = paint.mix(np.broadcast_to(side, (len(P), 3)), back, bb.sm(-0.1, 0.5, up))
        c = c * (0.85 + 0.3 * big)[:, None]
        # cross-bands down the back and the tail, the croc's young markings worn faint
        bands = 0.5 + 0.5 * np.sin((P[:, 1] / k) * (9.0 if not drake else 13.0) * 2 * math.pi / 2.0 + 2.0 * n1.at(P, 4.0 / k))
        c = paint.mix(c, band, (0.5 if not drake else 0.65) * bb.sm(0.6, 0.85, bands) * (R["back"] + 0.6 * R["tail"]).clip(0, 1))
        if drake:
            # the pipe-rings rust and verdigris where they stand proud
            ring = np.abs(((P[:, 1] / k) * 13.0) % 1.0 - 0.5) * 2.0
            c = paint.mix(c, band2, 0.6 * bb.sm(0.75, 0.92, ring) * R["back"] * bb.sm(0.5, 0.6, n2.at(P, 10.0 / k)))
        else:
            # duckweed and mud in patches over the back and down the flanks
            weed = bb.sm(0.58, 0.68, n2.fbm(P, freq=6.0 / k, octaves=3)) * bb.sm(0.0, 0.6, up)
            c = paint.mix(c, band2, 0.55 * weed)
        c = paint.mix(c, belly, R["belly"] * (0.9 - 0.3 * R["tail"]))
        # the scales' net: dark between, the scales' crowns lighter
        cells = bb._cells(P, 45.0 / k, st.seed)
        c = c * (0.8 + 0.3 * (1.0 - bb.sm(0.45, 0.8, cells)))[:, None]
        c = paint.mix(c, mouth, R["mouth"])
        c = paint.mix(c, teeth, R["teeth"] * 0.9)
        c = paint.mix(c, eye, R["eye"])
        slit = (1.0 - bb.sm(0.004 * k, 0.008 * k, np.abs((P - H(skel, 0.20, -0.06, 0.0)) @ Y))) * R["eye"]
        c = paint.mix(c, np.array([0.02, 0.02, 0.01]), slit)
        c = paint.mix(c, np.array([0.12, 0.10, 0.08]), R["claw"] * 0.8)
        v = 0.5 + 0.5 * occ
        v = np.maximum(v, R["eye"])
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = regions(skel, P, st, trunk)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.08 * k, samples=5, strength=1.2)
        rough = (0.42 if drake else 0.72) + 0.1 * n1.fbm(P, freq=10.0 / k, octaves=2) - 0.6 * R["eye"] - 0.3 * R["teeth"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.06, 0.97), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        cells = bb._cells(P, 45.0 / k, st.seed)
        return 1.0 - bb.sm(0.3, 0.75, cells)

    return albedo, orm, height


def bare_scene(spec):
    return reptile_scene(spec.skel, spec.style, spec.extra["trunk"], bare=True)
