"""The closed hand: a morph that curls each finger and the thumb round a haft in the palm.

The rig has no finger bones, and the open hand hung splayed round every weapon hilt: nothing was
ever held. Finger bones would change the skeleton every clip and every part is bound to; a morph
target changes nothing but the meshes that carry a hand. `grip_positions` takes a hand's vertices
as they are modelled (`body._hand_parts`, in the rest pose) and moves the ones on each finger and
the thumb as rigid pieces of a curled chain: a finger's joints turn about its own knuckle hinge,
by the angles that lay it round the haft, as three bones would, blended across each joint.

The haft is the weapon socket's own axis (rig `_socket_defs`): the line through the palm centre
along the socket's +Y, which in the rest pose runs across the palm, forward. The fingers are laid
round a haft of `HAFT_R` so that a grip up to 3.2 cm across is held without a gap."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np

from . import rig, sdf
from .rig import Skeleton

HAFT_R = 0.016          # the haft the fist is shaped round (m, at the default height)
# how far each finger's centre line lies from the haft's axis: the haft and the finger's own radius
FINGER_CLEAR = 0.0015


@dataclass
class Chain:
    """A finger as the forge models it: a planar chain curling about `hinge`."""
    name: str
    base: np.ndarray            # the knuckle
    dirv: np.ndarray            # straight out from the knuckle
    hinge: np.ndarray           # the curl turns about this, from dirv towards the palm
    seg: Tuple[float, float, float]
    radius: float
    open: Tuple[float, float, float]    # the modelled curl at each joint, degrees


def hand_frame(skel: Skeleton, side: str) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """(wrist, along the arm, the thumb's side, the back of the hand), as `body.body_scene` builds
    the hand in the rest pose."""
    from . import body as bodylib
    J = skel.J
    sx = 1.0 if side == "L" else -1.0
    wr = np.asarray(J[f"Hand.{side}"], float)
    d = sdf._unit(np.asarray(J[f"LowerArm.{side}"], float) - np.asarray(J[f"UpperArm.{side}"], float))
    fwd, up = bodylib._arm_frame(d, sx)
    return wr, d, fwd, up


def chains(skel: Skeleton, hands: float, side: str) -> Tuple[List[Chain], Chain, float]:
    """The four fingers and the thumb of one hand, and the hand's scale: the numbers of
    `body._hand_parts`, which this has to agree with."""
    p = skel.props
    s = p.height / rig.DEFAULT_HEIGHT
    hs = hands * p.hand_size * s
    wr, d, fwd, up = hand_frame(skel, side)
    L = 0.182 * hs
    pw = 0.0405 * hs
    kn = 0.52 * L
    fingers = [("index", 0.70, 0.43, 0.0094, 0.020, 0.035),
               ("middle", 0.23, 0.47, 0.0096, 0.000, 0.008),
               ("ring", -0.24, 0.44, 0.0090, 0.010, -0.020),
               ("little", -0.68, 0.35, 0.0079, 0.045, -0.050)]
    seg = (0.47, 0.29, 0.24)
    out = []
    for name, off, ln, r, back, splay in fingers:
        base = wr + d * (kn - back * L) + fwd * (pw * off)
        dirv = sdf._unit(d + fwd * splay)
        hinge = sdf._unit(np.cross(dirv, -up))
        out.append(Chain(name, base, dirv, hinge, tuple(k * ln * L for k in seg), r * hs, (9.0, 24.0, 18.0)))
    # the thumb, from the heel of the palm: its three pieces as `_hand_parts` lays them
    tb0 = wr + d * 0.12 * L + fwd * pw * 0.66 - up * 0.0140 * hs * 0.20
    dirs = [sdf._unit(fwd * 0.45 + d * 0.82 - up * 0.30), sdf._unit(fwd * 0.16 + d * 0.88 - up * 0.42),
            sdf._unit(fwd * 0.04 + d * 0.82 - up * 0.55)]
    lens = (0.043 * hs, 0.030 * hs, 0.024 * hs)
    # its curl plane: the plane of its first two pieces, turning towards the palm
    hinge_t = sdf._unit(np.cross(dirs[0], dirs[2]))
    if np.dot(np.cross(hinge_t, dirs[0]), -up) < 0:
        hinge_t = -hinge_t
    open_t = (0.0, math.degrees(math.acos(float(np.clip(np.dot(dirs[0], dirs[1]), -1, 1)))),
              math.degrees(math.acos(float(np.clip(np.dot(dirs[1], dirs[2]), -1, 1)))))
    thumb = Chain("thumb", tb0, dirs[0], hinge_t, lens, 0.0126 * hs, open_t)
    return out, thumb, hs


def haft(skel: Skeleton, side: str) -> Tuple[np.ndarray, np.ndarray]:
    """A point on the axis of the haft the fist closes round, and its direction, in the rest pose:
    parallel to the weapon socket's +Y, against the palm below the base of the fingers, a haft's
    radius off it. The socket itself sits 1.8 cm shallower, in the palm's centre (`GRIP_OFFSET`):
    round a haft there, 1.2 cm into the palm and a finger's breadth from the knuckles, the fingers
    had no room to close and made a loose hook."""
    s = skel.props.height / rig.DEFAULT_HEIGHT
    a = math.radians(rig.A_POSE_DEG)
    sx = 1.0 if side == "L" else -1.0
    d = np.array([sx * math.cos(a), 0.0, -math.sin(a)])       # down the A-posed arm
    n = np.array([-sx * math.sin(a), 0.0, -math.cos(a)])      # out of the palm
    c = np.asarray(skel.J[f"Hand.{side}"], float) + d * 0.068 * s + n * 0.028 * s
    head, tail, _ = rig._socket_defs(skel.J, skel.props)[f"Socket.Weapon{side}"]
    return c, sdf._unit(np.asarray(tail, float) - np.asarray(head, float))


def socket_frame(skel: Skeleton, side: str) -> Tuple[np.ndarray, np.ndarray]:
    """The weapon socket's origin and its axes (columns x, y, z), as Blender makes the bone from
    `rig._socket_defs`: y from head to tail, z the align vector made square to it, x = y cross z."""
    head, tail, align = rig._socket_defs(skel.J, skel.props)[f"Socket.Weapon{side}"]
    y = sdf._unit(np.asarray(tail, float) - np.asarray(head, float))
    z = np.asarray(align, float) - np.dot(align, y) * y
    z = z / np.linalg.norm(z)
    x = np.cross(y, z)
    return np.asarray(head, float), np.stack([x, y, z], axis=1)


def grip_offset(skel: Skeleton, side: str) -> np.ndarray:
    """Where the fist's haft axis passes, from the weapon socket's origin, in the socket's own
    frame (metres): a held thing centred on this, along the socket's +Y, sits in the closed hand."""
    c, _ = haft(skel, side)
    o, axes = socket_frame(skel, side)
    return axes.T @ (c - o)


def _rot(axis: np.ndarray, deg: float) -> np.ndarray:
    a = math.radians(deg)
    x, y, z = axis
    c, s_, C = math.cos(a), math.sin(a), 1.0 - math.cos(a)
    return np.array([[c + x * x * C, x * y * C - z * s_, x * z * C + y * s_],
                     [y * x * C + z * s_, c + y * y * C, y * z * C - x * s_],
                     [z * x * C - y * s_, z * y * C + x * s_, c + z * z * C]])


def joints(ch: Chain, angles: Tuple[float, float, float]) -> List[np.ndarray]:
    """The chain's joints (knuckle, two middle joints, tip) curled by `angles` (degrees, each joint)."""
    pts = [ch.base]
    cur, tot = ch.base, 0.0
    for k in range(3):
        tot += angles[k]
        cur = cur + _rot(ch.hinge, tot) @ ch.dirv * ch.seg[k]
        pts.append(cur)
    return pts


def _dist_to_line(P: np.ndarray, c: np.ndarray, axis: np.ndarray) -> np.ndarray:
    v = P - c
    return np.linalg.norm(v - np.outer(v @ axis, axis), axis=1)


def fist_angles(ch: Chain, c: np.ndarray, axis: np.ndarray, r_haft: float, s: float) -> Tuple[float, float, float]:
    """The curl at each joint that lays the finger's centre line round the haft, a finger's radius
    out from it, as far round as the finger reaches: a grid search, coarse then fine."""
    target = r_haft + ch.radius + FINGER_CLEAR * s

    def cost(A):
        # A: (n, 3) angle triples; sample each chain at 12 points a piece
        n = len(A)
        tot = np.cumsum(A, axis=1)
        pts = np.repeat(ch.base[None], n, axis=0)
        samples = []
        for k in range(3):
            dirs = np.stack([_rot(ch.hinge, t) @ ch.dirv for t in tot[:, k]])
            for f in np.linspace(1.0 / 12, 1.0, 12):
                samples.append(pts + dirs * ch.seg[k] * f)
            pts = pts + dirs * ch.seg[k]
        S = np.stack(samples, axis=1)                      # (n, 36, 3)
        v = S - c
        along = v @ axis
        rho = np.linalg.norm(v - along[..., None] * axis, axis=2)
        miss = (rho - target) / target
        into = np.clip((target - rho) / target, 0.0, None)
        # lie on the circle, never inside it, and the tip right round: a fist, not a hook
        return (miss ** 2).mean(axis=1) + 8.0 * (into ** 2).mean(axis=1)

    best = None
    for step, span in ((10.0, None), (2.5, 10.0)):
        if span is None:
            g = np.arange(0.0, 125.0, step)
            A = np.stack(np.meshgrid(g, g, g, indexing="ij"), axis=-1).reshape(-1, 3)
        else:
            g = np.arange(-span, span + 1e-6, step)
            D = np.stack(np.meshgrid(g, g, g, indexing="ij"), axis=-1).reshape(-1, 3)
            A = np.clip(best[None] + D, 0.0, 130.0)
        cst = cost(A)
        best = A[int(np.argmin(cst))]
    return tuple(float(a) for a in best)


def _piece_frames(ch: Chain, angles) -> List[Tuple[np.ndarray, np.ndarray]]:
    """For each piece of the chain, (the rotation, the translation) taking its open pose to the
    curled one: p' = R p + t."""
    J0 = joints(ch, ch.open)
    J1 = joints(ch, angles)
    out = []
    for k in range(3):
        R = _rot(ch.hinge, sum(angles[:k + 1]) - sum(ch.open[:k + 1]))
        out.append((R, J1[k] - R @ J0[k]))
    return out


def grip_positions(skel: Skeleton, hands: float, V: np.ndarray, side: str,
                   r_haft: float = HAFT_R) -> np.ndarray:
    """`V` (rest pose, the forge frame) with the `side` hand closed round the socket's haft.

    Each vertex near a finger or the thumb is carried by the piece of that chain it lies on, and
    blended across a joint over a finger's radius; the palm and everything else stay put. The
    knuckle is blended from the palm's stillness into the first piece, so the back of the hand
    folds rather than tears."""
    s = skel.props.height / rig.DEFAULT_HEIGHT
    fingers, thumb, hs = chains(skel, hands, side)
    c, axis = haft(skel, side)
    wr, d, fwd, up = hand_frame(skel, side)
    V = np.asarray(V, float)
    out = V.copy()
    near_hand = (np.linalg.norm(V - (wr + d * 0.09 * hs), axis=1) < 0.16 * hs)
    idx = np.nonzero(near_hand)[0]
    P = V[idx]
    # every chain's claim on each vertex: distance to its open centre line, and the piece
    best_d = np.full(len(P), np.inf)
    moved = P.copy()
    for ch in fingers + [thumb]:
        ang = fist_angles(ch, c, axis, r_haft * s, s) if ch.name != "thumb" else _thumb_angles(ch, c, axis, r_haft * s, s)
        J0 = joints(ch, ch.open)
        frames = _piece_frames(ch, ang)
        # distance to each open piece, and where along it
        dists, ts = [], []
        for k in range(3):
            a, b = J0[k], J0[k + 1]
            ab = b - a
            t = np.clip(((P - a) @ ab) / float(ab @ ab), -0.6, 1.0)
            q = a + np.outer(np.clip(t, 0.0, 1.0), ab)
            dists.append(np.linalg.norm(P - q, axis=1))
            ts.append(t)
        dists = np.stack(dists, axis=1)
        k_near = np.argmin(dists, axis=1)
        dmin = dists[np.arange(len(P)), k_near]
        claim = (dmin < ch.radius * 1.9) & (dmin < best_d)
        if not claim.any():
            continue
        # the piece's own transform, blended with the one before it over a radius either side of
        # the joint; the first piece is blended from the palm (no transform) at the knuckle
        blend_len = ch.radius * 1.0
        res = np.empty((len(P), 3))
        for k in range(3):
            R, t = frames[k]
            res_k = P @ R.T + t
            a, b = J0[k], J0[k + 1]
            seg_len = float(np.linalg.norm(b - a))
            along = ts[k] * seg_len
            w = np.clip(0.5 + along / (2.0 * blend_len), 0.0, 1.0)   # 0 before the joint, 1 past it
            if k == 0:
                prev = P
            else:
                Rp, tp = frames[k - 1]
                prev = P @ Rp.T + tp
            mix = prev + (res_k - prev) * w[:, None]
            sel = k_near == k
            res[sel] = mix[sel]
        moved[claim] = res[claim]
        best_d[claim] = dmin[claim]
    out[idx] = moved
    return out


def _thumb_angles(ch: Chain, c: np.ndarray, axis: np.ndarray, r_haft: float, s: float) -> Tuple[float, float, float]:
    """The thumb closes over the haft beside the index finger: curled in its own plane until its
    last piece lies across the haft, a thumb's radius and the index finger's out from it."""
    target = r_haft + ch.radius * 0.9 + 0.006 * s
    best, best_c = ch.open, np.inf
    for a0 in np.arange(-10.0, 50.0, 5.0):
        for a1 in np.arange(0.0, 70.0, 5.0):
            for a2 in np.arange(0.0, 70.0, 5.0):
                pts = joints(ch, (ch.open[0] + a0, ch.open[1] + a1, ch.open[2] + a2))
                S = np.array([pts[1] + (pts[2] - pts[1]) * f for f in np.linspace(0, 1, 6)]
                             + [pts[2] + (pts[3] - pts[2]) * f for f in np.linspace(0, 1, 6)])
                rho = _dist_to_line(S, c, axis)
                cst = float(((rho - target) ** 2).mean() + 8.0 * (np.clip(target - rho, 0, None) ** 2).mean())
                if cst < best_c:
                    best, best_c = (ch.open[0] + a0, ch.open[1] + a1, ch.open[2] + a2), cst
    return best
