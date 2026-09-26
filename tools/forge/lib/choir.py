"""The Sunken Choir's colossi as carved figures (WORLD_BIBLE §6.6): twelve robed singers fifty
metres tall whose heads all went in one night, standing to their knees in the ash.

Three poses:
  a  both arms raised, hands open: the note being lifted (the figure you see first, at the
     head of the avenue, and the crown-of-stumps silhouette from the Mere)
  b  one hand raised and open, the other laid on the breast; the raised forearm has snapped
     and lies in the ash at its feet
  c  broken at the knees: the robe's lower half still stands, jagged, and the upper body lies
     on its back behind it, half sunk, its arms thrown wide

Numpy only (lib/carve.py, lib/sdf.py). `figure(variant)` returns the parts as signed-distance
scenes, each meshed on its own: the body, the rubble and fallen pieces, and the collision
volumes (the body only, as the few convex pieces a player walks round).
"""
from __future__ import annotations

import math

import numpy as np

from . import carve as C
from . import sdf

# The figure's measures, in metres, for a colossus fifty metres tall as carved (head and all).
SHOULDER_Z = 40.8
NECK_TOP_Z = 45.4
HEM_RX = 8.6
HEM_RY = 7.2
BURY_M = 2.6          # how far the robe runs on under the ground line


def _robe_stations(lower_only_z: float | None = None) -> list:
    """(z, rx, ry, cy): the robe from under the ground to the shoulders. The chest stands a
    little forward of the hem (cy < 0 is the front), the back falls straight."""
    st = [
        (-BURY_M, HEM_RX * 1.02, HEM_RY * 1.02, 0.25),
        (0.0, HEM_RX, HEM_RY, 0.2),
        (2.5, HEM_RX * 0.93, HEM_RY * 0.9, 0.15),
        (8.0, 7.2, 5.6, 0.0),
        (15.0, 6.2, 4.7, -0.15),
        (22.0, 5.6, 4.2, -0.2),
        (27.0, 5.25, 3.9, -0.2),
        (30.0, 5.0, 3.65, -0.15),     # the waist, under the cord
        (34.0, 5.35, 3.85, -0.35),
        (37.5, 5.9, 4.0, -0.4),       # the breast
        (40.0, 6.1, 3.7, -0.2),
        (41.8, 4.6, 3.1, 0.1),
    ]
    if lower_only_z is not None:
        st = [s for s in st if s[0] <= lower_only_z + 3.0]
    return st


FOLD_AMP = [(-BURY_M, 0.95), (4.0, 0.9), (14.0, 0.62), (24.0, 0.42), (29.0, 0.22),
            (31.5, 0.1), (36.0, 0.18), (41.0, 0.05)]


def _arm(shoulder, elbow, wrist, r_up=1.6, r_fore=1.25, sleeve=True, hang=(0.0, 0.3, -1.0)):
    """An arm as a limb in a wide sleeve. The sleeve is carried by the upper arm and falls from
    the elbow, bunched, the way cloth hangs off a raised arm; the forearm comes out of it."""
    S, E, W = (np.asarray(p, float) for p in (shoulder, elbow, wrist))
    prims = [sdf.round_cone(S, E, r_up, r_up * 0.86, k=1.2), sdf.round_cone(E, W, r_fore, r_fore * 0.72, k=0.8)]
    if sleeve:
        h = np.asarray(hang, float)
        h /= np.linalg.norm(h)
        cuff = E + (W - E) * 0.38
        # the sleeve's mouth, open round the forearm, and its fall below the elbow
        prims.append(sdf.round_cone(S + (E - S) * 0.25, cuff, r_up * 1.12, r_up * 1.45, k=1.0))
        prims.append(sdf.round_cone(E + (cuff - E) * 0.3, E + h * 5.0 + (cuff - E) * 0.15, r_up * 1.35, r_up * 1.05, k=1.6))
        # the fold down the sleeve's fall
        prims.append(sdf.round_cone(E + h * 1.0, E + h * 5.2, 0.55, 0.35, k=0.6, op="subtract"))
    return prims


def _hand(wrist, up, out, palm_normal, scale=1.0, curl=0.15, spread=1.0):
    """An open hand: a palm, four fingers and a thumb, big enough to read from the plain."""
    Wp = np.asarray(wrist, float)
    up = np.asarray(up, float) / np.linalg.norm(up)
    out = np.asarray(out, float) / np.linalg.norm(out)
    pn = np.asarray(palm_normal, float) / np.linalg.norm(palm_normal)
    s = scale
    palm_c = Wp + up * 1.4 * s
    prims = [sdf.round_cone(Wp, palm_c + up * 0.6 * s, 1.0 * s, 0.85 * s, k=0.6)]
    # flatten the palm into a hand's breadth
    prims.append(sdf.ellipsoid(palm_c, np.array([1.3, 0.55, 1.45]) * s, k=0.6,
                               rot=np.stack([out, pn, up], axis=1)))
    for i in range(4):
        t = (i - 1.5) / 1.5
        base = palm_c + up * 1.25 * s + out * t * 0.95 * s
        d1 = up + out * t * 0.18 * spread
        d1 /= np.linalg.norm(d1)
        ln = (2.0 - 0.35 * abs(t) - (0.25 if i == 3 else 0.0)) * s
        mid = base + d1 * ln * 0.55
        tip = mid + (d1 * (1.0 - curl) + pn * curl) * ln * 0.45
        prims.append(sdf.round_cone(base, mid, 0.36 * s, 0.31 * s, k=0.25))
        prims.append(sdf.round_cone(mid, tip, 0.31 * s, 0.24 * s, k=0.15))
    tb = Wp + up * 0.6 * s - out * 0.95 * s
    tt = tb + (up * 0.55 - out * 0.8 + pn * 0.2) * 1.9 * s
    prims.append(sdf.round_cone(tb, tt, 0.46 * s, 0.3 * s, k=0.4))
    return prims


def _upper_body(pose: str, seed: int) -> list:
    """Shoulders, the neck's stump, the cowl lying on the shoulders, and the arms of `pose`."""
    rng = np.random.default_rng(seed)
    P: list = []
    for sx in (-1.0, 1.0):
        P.append(sdf.ellipsoid((sx * 5.3, 0.1, SHOULDER_Z - 0.2), (2.7, 2.6, 2.3), k=1.8))
    # the cowl: the robe's hood thrown back, a thick roll round the neck and a fall down the back
    P.append(C.moved(sdf.torus((0, 0, 0), 2.7, 1.05), C.rot([1, 0, 0], -18), (0, 0.55, SHOULDER_Z + 1.1)))
    P.append(sdf.ellipsoid((0, 2.9, SHOULDER_Z - 1.2), (3.3, 1.35, 3.0), k=1.5))
    P.append(sdf.ellipsoid((0, 3.5, SHOULDER_Z - 4.2), (2.2, 0.9, 2.2), k=1.8))
    # the neck, snapped: the break is the point
    P.append(sdf.round_cone((0, 0.3, SHOULDER_Z), (0, 0.55, NECK_TOP_Z + 1.0), 2.25, 1.95, k=1.0))
    P.append(C.local_cut((0.2, 0.5, NECK_TOP_Z), (0.28, 0.12, 1.0), 3.4, 0.7, seed + 3, reach=4.0))
    if pose == "a":
        for sx in (-1.0, 1.0):
            S = (sx * 5.8, 0.2, SHOULDER_Z + 0.2)
            E = (sx * 9.6, -1.1, SHOULDER_Z + 3.8)
            W = (sx * 10.4, -2.6, SHOULDER_Z + 9.4)
            P += _arm(S, E, W, hang=(sx * 0.15, 0.25, -1.0))
            P += _hand(W, up=(sx * 0.25, -0.2, 1.0), out=(sx * 1.0, 0.0, -0.2), palm_normal=(0, -1.0, 0.25),
                       scale=1.55, curl=0.12, spread=1.6)
    elif pose == "b":
        # the left hand raised, open -- snapped mid-forearm; the right laid on the breast
        S = (-5.8, 0.2, SHOULDER_Z + 0.2)
        E = (-8.9, -1.0, SHOULDER_Z + 4.6)
        W = (-9.3, -2.2, SHOULDER_Z + 10.6)
        P += _arm(S, E, W, hang=(-0.15, 0.25, -1.0))
        S2 = (5.8, 0.0, SHOULDER_Z - 0.4)
        E2 = (7.5, -2.6, SHOULDER_Z - 6.4)
        W2 = (3.4, -4.9, SHOULDER_Z - 4.0)
        P += _arm(S2, E2, W2, sleeve=True, hang=(0.2, 0.2, -1.0))
        P += _hand(W2, up=(-1.0, -0.12, 0.35), out=(0.0, 0.1, 1.0), palm_normal=(0, 1.0, 0.0), scale=1.25,
                   curl=0.08, spread=0.6)
    return P


def _forearm_break(seed: int) -> sdf.Prim:
    """Where pose b's raised forearm snapped: all of it above the break goes."""
    return C.local_cut((-9.1, -1.6, SHOULDER_Z + 7.0), (-0.05, -0.2, 1.0), 3.2, 0.45, seed + 11, reach=6.0)


def _ash_bank(r_foot: float, r_out: float, h: float, seed: int, squash: float = 0.84, cy: float = 0.0,
              along: float = 1.0) -> sdf.Prim:
    """The ash drifted against a foot: a bank `h` metres high where it meets the stone at
    `r_foot`, deeper on the weather side (west, -X), thinning out to the ground by `r_out`, and
    going under the ground again past it (a closed body, whose rim stays buried on a slope)."""
    def fn(P):
        x, y, z = P[:, 0], (P[:, 1] - cy) / (squash * along), P[:, 2]
        rr = np.sqrt(x * x + y * y)
        t = np.clip((r_out - rr) / (r_out - r_foot), 0.0, 1.0)
        lean = 1.0 - 0.35 * np.tanh(x / r_out * 2.0)
        top = -2.5 + (h * lean + 2.5) * t ** 1.3 + C.fbm(P, 0.22, 2, seed) * 0.7 * t
        return np.maximum(np.maximum((z - top) * 0.7, (-BURY_M - 1.5) - z), (rr - r_out) * 0.7)
    ry = r_out * squash * along
    return C.custom(fn, (-r_out - 1, cy - ry - 1, -BURY_M - 2.0), (r_out + 1, cy + ry + 1, h * 1.4 + 1.5))


def _cord(z: float, rx: float, ry: float, cy: float, r: float) -> sdf.Prim:
    """A cord round the waist, following the robe's own section."""
    def fn(P):
        x, y = P[:, 0], P[:, 1] - cy
        u, v = x / rx, y / ry
        rn = np.sqrt(u * u + v * v) + 1e-9
        grad = np.sqrt((u / rx) ** 2 + (v / ry) ** 2) + 1e-9
        de = (rn * rn - 1.0) / (2.0 * rn * grad)
        return np.sqrt(de * de + (P[:, 2] - z) ** 2) - r
    return C.custom(fn, (-rx - r - 1, -ry + cy - r - 1, z - r - 1), (rx + r + 1, ry + cy + r + 1, z + r + 1), k=0.4)


def _wear(p, seed, amp=0.34, cracks=0.5):
    return C.worn(p, amp=amp, freq=0.22, seed=seed, octaves=4, cracks=cracks, crack_freq=0.06, crack_w=0.05)


def figure(variant: str = "a", seed: int = 1) -> dict:
    """{"body": Scene, "debris": Scene, "collision": [Scene, ...], "height": metres}."""
    rng = np.random.default_rng(seed)
    body = sdf.Scene()
    debris = sdf.Scene()
    cols = []
    pose = {"a": "a", "b": "b", "c": "a"}.get(variant, "a")

    lower = variant == "c"
    break_z = 17.5
    robe = C.robe(_robe_stations(break_z if lower else None), folds=15, fold_amp=FOLD_AMP, seed=seed, k=0.0)
    parts = [robe]
    # a knee pressing forward under the cloth, and the cord at the waist
    parts.append(sdf.ellipsoid((1.9, -4.2, 16.5), (2.4, 1.6, 3.4), k=2.6))
    parts.append(_cord(30.3, 5.05, 3.7, -0.15, 0.42))
    # its knot and the two ends hanging down the front
    parts.append(sdf.ellipsoid((1.2, -3.9, 30.1), (0.9, 0.6, 0.8), k=0.4))
    for dx, ln in ((0.9, 7.5), (1.7, 5.8)):
        parts.append(sdf.round_cone((1.2, -4.0, 29.6), (dx, -4.35 - 0.02 * ln, 29.6 - ln), 0.34, 0.42, k=0.5))
    # the toes of the right foot out from under the hem, sunk to the joints
    parts.append(sdf.ellipsoid((2.6, -7.4, 0.2), (1.7, 2.0, 1.1), k=0.8))
    parts.append(sdf.ellipsoid((-2.4, -7.0, -0.2), (1.6, 1.8, 0.9), k=0.8))
    upper = _upper_body(pose, seed + 1)
    if not lower:
        parts += upper
    stone = sdf.group(parts, k=1.2)
    body.add(_wear(stone, seed + 5))
    if variant == "b":
        body.add(_forearm_break(seed))
    if lower:
        body.add(C.jagged_cut((0.0, 0.0, break_z + 1.5), (0.55, -0.4, 1.0), 6.5, 2.2, seed + 21, bumps=9))
    body.add(_ash_bank(HEM_RX * 0.95, HEM_RX + 6.0, 2.2, seed + 7, cy=0.2))

    # --- what has fallen --------------------------------------------------------------
    avoid_front = None
    if variant == "c":
        # the upper body fell backward (+Y) and lies on its back, half sunk, arms wide
        top = sdf.group([C.robe([(22.0, 5.6, 4.2, -0.2), (27.0, 5.25, 3.9, -0.2), (30.0, 5.0, 3.65, -0.15),
                                 (34.0, 5.35, 3.85, -0.35), (37.5, 5.9, 4.0, -0.4), (40.0, 6.1, 3.7, -0.2),
                                 (41.8, 4.6, 3.1, 0.1)], folds=15, fold_amp=FOLD_AMP, seed=seed)]
                        + _upper_body("a", seed + 1), k=1.2)
        top = sdf.group([top] + C.jagged_cut((0.0, 0.0, 22.6), (0.2, -0.3, -1.0), 6.0, 1.8, seed + 23, bumps=6), k=0.0)
        # laid on its back along +Y: the break (z 22) comes to rest 9.5 m behind the stump's
        # foot, and it is sunk three metres into the ash
        R = C.rot([0, 0, 1], 8.0) @ C.rot([1, 0, 0], -86.0)
        lying = C.moved(top, R, (0.8, 0.0, 0.0))
        lo = lying.lo
        lying = C.moved(lying, np.eye(3), (0.0, 9.5 - lo[1], -3.2 - lo[2]))
        debris.add(_wear(lying, seed + 31))
        debris.add(_ash_bank(5.0, 11.0, 1.8, seed + 33, squash=1.0, along=1.7, cy=(lying.lo[1] + lying.hi[1]) * 0.5))
        cols.append(("hull", lying))
        # drums of the robe between: the part of it that burst when it fell
        for i in range(3):
            c = (rng.uniform(-3, 3), 6.0 + i * 2.5 + rng.uniform(-1, 1), rng.uniform(0.5, 1.5))
            d = C.worn(C.moved(sdf.round_cone((0, 0, -1.8), (0, 0, 1.8), 3.2, 3.0),
                                C.rot([rng.normal(), rng.normal(), 0.3], rng.uniform(40, 90)), c),
                       amp=0.3, freq=0.25, seed=seed + 40 + i, cracks=0.4, crack_freq=0.08)
            debris.add(d)

        def avoid_front(x, y):
            return y > 4.0 and abs(x) < 9.0
    if variant == "b":
        # the snapped forearm and its hand, lying in the ash at the figure's left
        arm = sdf.group([sdf.round_cone((0, 0, 0), (0, 0, 4.8), 1.15, 0.95)]
                        + _hand((0, 0, 4.8), up=(0, 0, 1), out=(1, 0, 0), palm_normal=(0, -1, 0), curl=0.2), k=0.6)
        arm = C.moved(arm, C.rot([0.3, 1.0, 0.1], 97.0) @ C.rot([0, 0, 1], 20), (-12.5, -5.5, 0.4))
        debris.add(C.worn(arm, amp=0.18, freq=0.3, seed=seed + 51, cracks=0.2, crack_freq=0.1))
    # a hand of stone fingers and shards broken off, strewn round the foot
    for p in C.rubble(rng, 16 if variant != "c" else 11, HEM_RX + 1.5, HEM_RX + 5.0, (0.6, 1.5),
                      sink=0.5, avoid=avoid_front, seed=seed + 60):
        debris.add(p)
    for p in C.rubble(rng, 7, HEM_RX + 0.2, HEM_RX + 1.6, (1.1, 1.9), sink=0.55, avoid=avoid_front, seed=seed + 90):
        debris.add(p)

    # --- what a player walks round ------------------------------------------------------
    cols.insert(0, ("hull", sdf.round_cone((0, 0, -BURY_M), (0, 0, break_z if lower else SHOULDER_Z + 1.0),
                                           HEM_RX * 0.94, 4.6)))
    height = NECK_TOP_Z + 1.0 if pose == "b" and not lower else SHOULDER_Z + 15.0
    return {"body": body, "debris": debris, "collision": cols, "height": height,
            "bury_m": BURY_M}
