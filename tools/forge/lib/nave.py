"""The Drowned Nave (WORLD_BIBLE §6.3, Isse-Anthe): an Oroth church gone down into the fen, its
tower leaning fifteen degrees out of the marsh, the nave's walls broken and stepping down
toward the water, its floor flooded, and the fallen stone of its vault heaped round it.

The first Nave stood the whole hundred-and-twenty-metre spire on the ground and hung the tops of
its arcade and gable at the waterline it was drawn for, 58 m up: from the marsh that was a mass
forty metres wide at 50-80 m on a shaft twenty wide, and with the trees hiding the shaft, a box
in the sky. This one is built from the ground: the tower is broadest at its foot and
buttressed, the buttresses step down to the nave's walls, the walls step down to rubble and the
rubble to the fen, so there is no height from which the mass does not come down to the ground.

Numpy only (lib/carve.py, lib/sdf.py). Z up, metres, the ground line at z = 0 and everything
running on below it; the nave runs toward -Y from the tower, which leans toward +X.
"""
from __future__ import annotations

import math

import numpy as np

from . import carve as C
from . import sdf

LEAN_DEG = 15.0
TOWER_W = 17.0            # the tower's foot, square
TOWER_H = 84.0            # along its own axis, from the ground at its foot to the spire's tip
NAVE_W = 27.0             # outside the walls
NAVE_L = 62.0
WALL_T = 2.6
FLOOD_Z = 0.45            # the water standing on the nave's floor, over the ground line
BURY = 4.0


def _wall_top(y: float, rng_off: float) -> float:
    """How high the nave's walls stand along their length: tallest against the tower, broken
    down in steps toward the far end, as the vault pulled them in bay by bay."""
    t = np.clip(-y / NAVE_L, 0.0, 1.0)
    return 26.0 - 19.0 * t ** 0.8 + rng_off


def tower(seed: int) -> list:
    """The tower in its own upright frame (foot at the origin), as primitives: a battered,
    fluted shaft with stepped corner buttresses, a belfry of tall openings, and an octagonal
    spire drawn to a point. Lean it afterwards."""
    rng = np.random.default_rng(seed)
    h = TOWER_H
    P = []
    hw = TOWER_W * 0.5
    # the shaft: square-ish with rounded corners, battered (wider at the foot), in three stages
    stages = [(-BURY - 8.0, 0.0, 1.12), (0.0, 22.0, 1.06), (22.0, 40.0, 1.0), (40.0, 52.0, 0.93)]
    for z0, z1, k in stages:
        P.append(C.slab((0, 0, (z0 + z1) * 0.5), (hw * k, hw * k, (z1 - z0) * 0.5 + 0.4), round_r=1.2, k=0.8))
        # a string course at the top of each stage
        P.append(C.slab((0, 0, z1), (hw * k + 0.5, hw * k + 0.5, 0.45), round_r=0.3, k=0.3))
    # stepped buttresses at the four corners, each in three offsets down to the ground
    for sx in (-1, 1):
        for sy in (-1, 1):
            for i, (top, reach, w) in enumerate(((44.0, 1.2, 2.4), (30.0, 3.4, 2.7), (15.0, 5.8, 3.0))):
                cx = sx * (hw + reach * 0.5)
                cy = sy * (hw + reach * 0.5)
                zb = -BURY - 2.0
                P.append(C.slab((cx, sy * (hw - 1.0), (top + zb) * 0.5), (reach * 0.5 + 1.0, w * 0.5, (top - zb) * 0.5),
                                round_r=0.5, k=0.5))
                P.append(C.slab((sx * (hw - 1.0), cy, (top + zb) * 0.5), (w * 0.5, reach * 0.5 + 1.0, (top - zb) * 0.5),
                                round_r=0.5, k=0.5))
                # the sloped weathering on each offset
                P.append(C.moved(C.slab((0, 0, 0), (reach * 0.5 + 1.2, w * 0.55, 0.9), round_r=0.3),
                                 C.rot([0, 1, 0], -sx * 35.0), (cx, sy * (hw - 1.0), top)))
    # the belfry and the spire: an octagon on the square, drawn to a needle
    oct_r = hw * 0.86
    for i in range(4):
        ang = 45.0 * i
        P.append(C.moved(C.slab((0, 0, 0), (oct_r, oct_r * 0.42, 7.5), round_r=0.6), C.rot([0, 0, 1], ang), (0, 0, 59.5)))
    P.append(sdf.round_cone((0, 0, 66.0), (0, 0, h), oct_r * 0.95, 0.35, k=0.8))
    # ribs up the spire's eight arrises, and two bands round it
    for i in range(8):
        a = math.radians(22.5 + 45 * i)
        P.append(sdf.round_cone((math.cos(a) * oct_r * 0.98, math.sin(a) * oct_r * 0.98, 66.5),
                                (math.cos(a) * 0.5, math.sin(a) * 0.5, h - 1.5), 0.55, 0.2, k=0.3))
    for zb in (72.0, 78.0):
        rb = oct_r * 0.95 * (h - zb) / (h - 66.0) + 0.35
        P.append(sdf.torus((0, 0, zb), rb, 0.45))
    # pinnacles at the octagon's shoulders
    for i in range(4):
        a = math.radians(45 + 90 * i)
        P.append(sdf.round_cone((math.cos(a) * hw * 0.95, math.sin(a) * hw * 0.95, 51.0),
                                (math.cos(a) * hw * 0.9, math.sin(a) * hw * 0.9, 62.0), 1.3, 0.25, k=0.4))
    body = sdf.group(P, k=0.0)
    cuts = []
    # the openings: tall lancets in each face of the belfry and slits down the shaft
    for i in range(4):
        a = math.radians(90 * i)
        d = np.array([math.cos(a), math.sin(a), 0.0])
        side = np.array([-d[1], d[0], 0.0])
        for s in (-1, 1):
            c = d * (oct_r - 0.5) + side * s * 2.6
            cuts.append(sdf.round_cone(c + [0, 0, 55.0], c + [0, 0, 63.0], 1.15, 1.15, op="subtract"))
        for z in (30.0, 45.0):
            c = d * (hw - 0.3)
            cuts.append(sdf.round_cone(c + [0, 0, z - 4.0], c + [0, 0, z + 3.0], 0.9, 0.9, op="subtract"))
    return [C.worn(body, amp=0.3, freq=0.12, seed=seed + 1, octaves=3, cracks=0.45, crack_freq=0.04)] + cuts


def nave_walls(seed: int) -> list:
    """The nave's two long walls and the apse at its far end, broken down in steps, pierced by
    tall windows, with stepped buttresses standing off them between the bays."""
    rng = np.random.default_rng(seed)
    P = []
    hw = NAVE_W * 0.5
    bays = 7
    bay = NAVE_L / bays
    for sx in (-1, 1):
        x = sx * (hw - WALL_T * 0.5)
        # each bay its own height of broken wall: a few metres of step between neighbours
        for b in range(bays):
            y1 = -b * bay
            y0 = y1 - bay
            top = _wall_top((y0 + y1) * 0.5, rng.uniform(-3.5, 2.0))
            if rng.random() < 0.18 and b > 1:
                top *= 0.35                                    # a bay fallen almost to the water
            P.append(C.slab((x, (y0 + y1) * 0.5, (top - BURY) * 0.5), (WALL_T * 0.5, bay * 0.5 + 0.3, (top + BURY) * 0.5),
                            round_r=0.4))
            # a buttress between this bay and the next, stepped twice down to the ground
            if b < bays:
                yb = y0
                btop = min(top + 3.0, _wall_top(yb, 0.0) + 2.0)
                for i, (frac, reach) in enumerate(((1.0, 2.4), (0.5, 5.0))):
                    t = btop * frac
                    P.append(C.slab((sx * (hw + reach * 0.5), yb, (t - BURY) * 0.5),
                                    (reach * 0.5 + 0.3, 1.4, (t + BURY) * 0.5), round_r=0.4, k=0.4))
                    # its sloped weathering, shedding the rain off the offset
                    P.append(C.moved(C.slab((0, 0, 0), (reach * 0.5 + 0.9, 1.55, 0.7), round_r=0.25),
                                     C.rot([0, 1, 0], sx * 30.0), (sx * (hw + reach * 0.5), yb, t)))
    # the apse: a half-round end, lowest of all
    ay = -NAVE_L

    def apse(Pp):
        x, y, z = Pp[:, 0], Pp[:, 1] - ay, Pp[:, 2]
        r = np.sqrt(x * x + y * y)
        ring = np.abs(r - (hw - WALL_T * 0.5)) - WALL_T * 0.5
        half = y                                       # only the -Y half
        top = 7.0 + 3.0 * np.sin(np.arctan2(y, x) * 3.0 + 1.0)
        return np.maximum(np.maximum(ring, half), np.maximum(z - top, -BURY - z))
    P.append(C.custom(apse, (-hw - 1, ay - hw - 1, -BURY - 1), (hw + 1, ay + 1, 12)))
    walls = sdf.group(P, k=0.0)
    cuts = []
    # tall windows, one to each bay, on both sides; where the wall has come down below its sill
    # the window is simply a notch
    for sx in (-1, 1):
        for b in range(bays):
            yc = -(b + 0.5) * bay
            cuts.append(sdf.round_cone((sx * (hw - WALL_T * 0.5), yc, 7.0), (sx * (hw - WALL_T * 0.5), yc, 17.0),
                                       1.6, 1.6, op="subtract"))
    # the interior is open to the sky and flooded: hollow out between the walls
    cuts.append(C.slab((0, -NAVE_L * 0.5, 20.0), (hw - WALL_T, NAVE_L * 0.5 + 0.2, 20.0 + FLOOD_Z - 1.0), round_r=0.2,
                       op="subtract"))
    return [C.worn(walls, amp=0.28, freq=0.14, seed=seed + 3, octaves=3, cracks=0.4, crack_freq=0.05)] + cuts


def piers(seed: int) -> list:
    """The nave's arcade: two rows of piers inside the walls, standing to what the vault left
    them, with an arch or two still spanning, and the rest lying in the water."""
    rng = np.random.default_rng(seed)
    P = []
    hw = NAVE_W * 0.5 - WALL_T - 3.2
    bays = 7
    bay = NAVE_L / bays
    standing = []
    for sx in (-1, 1):
        for b in range(1, bays):
            y = -b * bay
            top = _wall_top(y, 0.0) * rng.uniform(0.45, 0.95)
            if rng.random() < 0.3:
                top = rng.uniform(2.5, 5.0)               # a stump in the water
            P.append(sdf.round_cone((sx * hw, y, -BURY), (sx * hw, y, top), 1.5, 1.3, k=0.3))
            standing.append((sx, y, top))
    # an arch still standing between two tall neighbours
    for (sx, y, top) in standing:
        nxt = [s for s in standing if s[0] == sx and abs(s[1] - (y - bay)) < 0.1]
        if nxt and min(top, nxt[0][2]) > 13.0:
            yc = y - bay * 0.5
            zc = min(top, nxt[0][2]) - 3.0

            def arch(Pp, sx=sx, yc=yc, zc=zc):
                x, yy, z = Pp[:, 0] - sx * hw, Pp[:, 1] - yc, Pp[:, 2] - zc
                r = np.sqrt(yy * yy + z * z)
                ring = np.abs(r - bay * 0.5) - 1.1
                return np.maximum(np.maximum(ring, np.abs(x) - 1.2), -z)
            P.append(C.custom(arch, (sx * hw - 2, yc - bay, zc - 1), (sx * hw + 2, yc + bay, zc + bay)))
    return [C.worn(sdf.group(P, k=0.0), amp=0.2, freq=0.2, seed=seed + 5, cracks=0.3, crack_freq=0.07)]


def fallen(seed: int) -> list:
    """What has come down: column drums rolled in the water, blocks of the vault heaped against
    the walls inside and out, and a spill of stone off the tower's downhill side."""
    rng = np.random.default_rng(seed)
    P = []
    hw = NAVE_W * 0.5
    for i in range(9):
        y = rng.uniform(-NAVE_L + 4, -4)
        x = rng.uniform(-hw + 5, hw - 5)
        R = C.rot([rng.normal(), rng.normal(), 0.2], 90.0 + rng.uniform(-15, 15))
        P.append(C.worn(C.moved(sdf.round_cone((0, 0, -1.2), (0, 0, 1.2), 1.4, 1.35), R, (x, y, rng.uniform(-0.2, 0.5))),
                        amp=0.12, freq=0.4, seed=seed + i))
    # heaps against the walls, inside and out, and round the tower's foot
    def heap_at(cx, cy, n, spread, size):
        for j in range(n):
            a = rng.uniform(0, math.tau)
            r = spread * math.sqrt(rng.random())
            s = rng.uniform(*size)
            half = np.array([s * rng.uniform(0.8, 1.6), s * rng.uniform(0.6, 1.1), s * rng.uniform(0.4, 0.8)])
            R = C.rot([rng.normal(), rng.normal(), rng.normal()], rng.uniform(0, 50)) @ C.rot([0, 0, 1], rng.uniform(0, 360))
            z = s * 0.3 + rng.uniform(-0.6, 0.5) + max(0.0, (spread - r) / spread) * size[1] * 0.8
            P.append(C.worn(C.slab((cx + math.cos(a) * r, cy + math.sin(a) * r, z), half, R, round_r=min(half) * 0.35),
                            amp=s * 0.1, freq=0.8 / s, seed=seed + 100 + len(P)))
    for sx in (-1, 1):
        for k in range(4):
            y = -rng.uniform(8, NAVE_L - 6)
            heap_at(sx * (hw + 4.5), y, 6, 5.5, (0.9, 2.2))
            heap_at(sx * (hw - 5.0), y, 4, 3.5, (0.8, 1.8))
    heap_at(TOWER_W * 0.9, 6.0, 12, 9.0, (1.2, 2.8))         # off the downhill side of the leaning tower
    heap_at(-TOWER_W * 0.3, TOWER_W * 0.9, 7, 7.0, (1.0, 2.2))
    heap_at(0.0, -NAVE_L - 8.0, 8, 8.0, (0.8, 2.0))
    return P


def flood(seed: int) -> sdf.Prim:
    """The water standing on the floor, from wall to wall: a thin slab just over the ground."""
    hw = NAVE_W * 0.5 - WALL_T + 0.4
    return C.slab((0, -NAVE_L * 0.5 - 2.0, FLOOD_Z - 0.6), (hw, NAVE_L * 0.5 + hw * 0.5, 0.6), round_r=0.05)


def ruin(seed: int = 3) -> dict:
    """{"tower": Scene, "nave": Scene, "fallen": Scene, "water": Scene, "collision": [(kind, Prim)]}."""
    lean = C.rot([0, 1, 0], LEAN_DEG)          # the tip goes toward +X
    t = tower(seed)
    # pivot about the downhill edge of the foot, and let the uphill side's foot sink, as a tower
    # going over into soft ground does: then carry it so its foot's middle is at the ground line
    tw = C.moved(sdf.group(t, k=0.0), lean, (0.0, TOWER_W * 0.35, -1.0))
    tower_sc = sdf.Scene().add(tw)
    nave_sc = sdf.Scene().add(nave_walls(seed + 10)).add(piers(seed + 20))
    fallen_sc = sdf.Scene().add(fallen(seed + 30))
    water_sc = sdf.Scene().add(flood(seed))
    hw = NAVE_W * 0.5
    cols = [
        ("hull", C.moved(C.slab((0, 0, 30.0), (TOWER_W * 0.5 + 2.0, TOWER_W * 0.5 + 2.0, 34.0)), lean, (0.0, TOWER_W * 0.35, -1.0))),
        ("hull", C.slab((-(hw - WALL_T * 0.5), -NAVE_L * 0.5, 8.0), (WALL_T * 0.5 + 0.4, NAVE_L * 0.5, 12.0))),
        ("hull", C.slab(((hw - WALL_T * 0.5), -NAVE_L * 0.5, 8.0), (WALL_T * 0.5 + 0.4, NAVE_L * 0.5, 12.0))),
    ]
    return {"tower": tower_sc, "nave": nave_sc, "fallen": fallen_sc, "water": water_sc, "collision": cols,
            "flood_z": FLOOD_Z, "lean_deg": LEAN_DEG}
