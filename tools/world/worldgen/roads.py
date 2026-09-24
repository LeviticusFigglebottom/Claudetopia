"""Pads and roads.

Pads: every named place gets a smoothly blended flat platform sized by its kind.
Roads: settlements are joined by least-cost routes that prefer gentle grades and dry ground
(water is expensive but not impossible, so roads cross rivers at their narrowest and use the
Long Stride causeway to reach Tollmere). Each route is graded (a smoothed, slope-limited
profile) and cut into the terrain 4-6 m wide with soft shoulders.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .noise import downsample
from . import paths

## How many buildings the settlement builder raises at a place of each kind. Kept in step with
## FABRIC in game/world/exteriors/settlement.gd: the flattened ground should be the size of the
## town that will stand on it, not a fixed disc per kind. A town of thirty-four houses on a
## ninety-metre pad is a cottage in a car park.
FABRIC_COUNT = {
    "city": 54, "town": 34, "village": 16, "hamlet": 8, "fort": 10, "lodge": 5,
    "ruin_village": 9, "camp": 0,
}
PAD_DEFAULT = 25.0
## A camp that is a point of interest builds no houses: it is a fire, tents on a ring 7.6 m out
## and their stores, and at the most a rail or a kiln 12 to 13 m from the fire (poi_builders.camp).
## Twenty-two metres keeps all of that on the flat core (0.7 of the radius) with a couple of
## metres over. It was 30, the size a hamlet gets without the houses, and on the knoll the
## Clanless Camp stands on that pad threw a seventeen-metre embankment down the slope toward
## Brindlecrag -- whose rim was what the line from Brindlecrag grazed, 1.97 m over it against the
## 2 m allowed. A camp that is a *place* keeps its 30: Pilgrim's Ash is raised by the settlement
## builder, not the POI kit, and its chapter-house door stands 26 m from the middle.
CAMP_PAD_M = 22.0
## how far below an authored pad (the atlas's `pads`) the ground beyond its flat may lie before
## its skirt leaves it alone: that is a drop, a shelf's face, and not ground to be filled
PAD_DROP_M = 2.0
CAMP_PLACE_PAD_M = 30.0
ROAD_KINDS = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
ROAD_WIDTH = {"city": 6.0, "town": 6.0, "village": 5.0, "fort": 5.0, "hamlet": 4.5, "camp": 4.0,
              "lodge": 4.0, "ruin_village": 4.0}


@dataclass
class Road:
    id: str
    points: np.ndarray
    width: float
    elevation: np.ndarray
    ## the land the profile was graded against, under each point (see `grade_profile`)
    ground: np.ndarray | None = None


def pad_radius(place: dict) -> float:
    """Enough flat ground for the houses that will stand here, and no more.

    Frontage rather than area is what a street plan needs: n houses at about eight metres of
    frontage, along two sides of one or two streets, is a street length of roughly 2n metres,
    so the radius grows with the square root of the count and not with the count itself.
    """
    if place.get("pad_radius_m"):
        return float(place["pad_radius_m"])          # the atlas's own (`pads`)
    kind = str(place.get("kind", ""))
    count = FABRIC_COUNT.get(kind)
    if count is None:
        return PAD_DEFAULT
    if count <= 0:
        return CAMP_PAD_M if ":poi/" in str(place.get("id", "")) else CAMP_PLACE_PAD_M
    return float(min(max(20.0 + 7.5 * math.sqrt(count), 26.0), 80.0))


def apply_pads(grid: Grid, H: np.ndarray, places: list, min_levels: dict | None = None,
               fixed_levels: dict | None = None) -> tuple:
    """Flatten a platform at every place. Returns (heights, pad_mask, pad heights by place id).

    `min_levels` lifts a pad that would otherwise sit under standing water: a stilt-town in
    the marsh stands on the highest peat island it can find, not in the pools.
    """
    n = grid.n
    X, Z = grid.mesh()
    pad_mask = np.zeros((n, n), dtype=bool)
    levels: dict[str, float] = {}
    for p in places:
        px, pz = float(p["position"][0]), float(p["position"][1])
        r = pad_radius(p)
        j, i = grid.to_tex(px, pz)
        j, i = grid.clamp_index(j, i)
        rad_t = max(int(r / grid.spacing) + 4, 3)
        i0, i1 = max(0, int(i) - 2 * rad_t), min(n, int(i) + 2 * rad_t + 1)
        j0, j1 = max(0, int(j) - 2 * rad_t), min(n, int(j) + 2 * rad_t + 1)
        sub = H[i0:i1, j0:j1]
        dx = X[:, j0:j1] - px
        dz = Z[i0:i1, :] - pz
        d = np.sqrt(dx * dx + dz * dz)
        inner = d <= r * 0.75
        level = float(np.median(sub[inner])) if inner.any() else float(H[int(i), int(j)])
        if min_levels is not None and p["id"] in min_levels:
            level = max(level, float(min_levels[p["id"]]))
        if fixed_levels is not None and p["id"] in fixed_levels:
            # the atlas says where this one stands (`pads`): a landing at the foot of a cliff,
            # a shelf over the water, which the ground under it cannot say
            level = float(fixed_levels[p["id"]])
        levels[p["id"]] = level
        w = 1.0 - smoothstep(r * 0.7, r * 1.6, d)
        if fixed_levels is not None and p["id"] in fixed_levels:
            # An authored pad is a landing on a shelf or at a cliff's foot. Its skirt takes the
            # ground down to it, but builds nothing out over a drop: blended over the edge of the
            # Hushline's shelf it filled the sea at the foot of the face up to a lip at sea level.
            w = np.where((d > r * 0.7) & (sub < level - PAD_DROP_M), 0.0, w)
        H[i0:i1, j0:j1] = lerp(sub, level, w)
        pad_mask[i0:i1, j0:j1] |= d <= r
    return H, pad_mask, levels


## The design grade. A laden cart takes one in nine, and the router is what keeps a road under
## it -- by going round a slope, or up it in zigzags -- not the profile: the profile follows the
## ground, and it is never lifted off it or sunk into it to make a grade the route did not have.
MAX_GRADE = 0.11
## The steepest side slope the carve may leave between a road and the ground either side of
## it: one in two. `carve_roads` blends a road into the land across its shoulder with a
## smoothstep, whose steepest point is one and a half times its mean, so a road may stand
## `BATTER * shoulder / 1.5` metres off its own ground -- 2.4 m for a four-metre track, 3.6 m
## for a six-metre town road. That is a cutting or an embankment. It is never an arete: the
## old profile limited the grade by lifting the road, and on the spur out of Kharrow Hold it
## stood 150 m above the ground on both sides.
BATTER = 0.5
## A stair (the atlas's road kind "stair"): laid straight between its via points, as steep as
## thirty-five degrees -- steps cut into a bank the way a cliff path is -- and three metres wide.
STAIR_MAX_GRADE = 0.7
## How far below the land a road would rather run, by landform (`plan_roads`' `sink`). The
## Briarwold's lanes are holloways: a track in old ground on soft rock wears down between its
## own banks until the wood closes over it, and from inside one you see bank, roots and a strip
## of sky -- which is a different frame from a road across open downland. It is held inside the
## same band as any other road, so a holloway is a cutting and never a trench.
ROAD_SINK_M = {"forest_rise": 1.9}


def shoulder_m(width: float) -> float:
    """How far either side of the carriageway the carve blends back into the land."""
    return max(float(width) * 1.8, 7.0)


def cut_fill_m(width: float) -> float:
    """The most a road of this width may stand above, or lie below, the ground under it."""
    return BATTER * shoulder_m(width) / 1.5


def grade_profile(ground: np.ndarray, step_m: float, tol: float, max_grade: float = MAX_GRADE,
                  pins: dict | None = None, smooth_m: float = 60.0, sweeps: int = 60,
                  bias: np.ndarray | None = None, no_fill: np.ndarray | None = None,
                  near_lo: np.ndarray | None = None, near_hi: np.ndarray | None = None) -> np.ndarray:
    """A road's elevation along its length, sampled every `step_m` metres.

    As smooth as the ground allows, never more than `tol` above or below the ground under it,
    and no steeper than `max_grade` wherever the band leaves room for that. `pins` maps a sample
    index to a level it must take (a settlement's pad at each end, the grade of a road this one
    runs along); a pin outside the band is pulled into it. `bias` (metres, per sample) is where
    the road would rather lie relative to the ground -- a holloway wants to be below it -- and
    is still held inside the band. Where `no_fill` is set the band's top is the ground itself:
    the road may cut there but not stand proud. `near_lo` / `near_hi` narrow the band where
    another road passes close by; where that window and the ground's band do not overlap, the
    ground's band wins, because a road is never lifted off its land to meet another.

    Where the ground itself is steeper than the grade plus the room either side, the band wins:
    the road climbs with the ground for that pitch. That is the honest failure -- a steep
    stretch of road -- and the router is what keeps it rare.
    """
    g = np.asarray(ground, dtype=np.float64)
    n = g.size
    if n == 0:
        return g.astype(np.float32)
    lo = g - tol
    hi = g + tol
    if no_fill is not None:
        hi = np.where(np.asarray(no_fill, dtype=bool), g, hi)
    if near_lo is not None and near_hi is not None:
        lo2 = np.maximum(lo, np.asarray(near_lo, dtype=np.float64))
        hi2 = np.minimum(hi, np.asarray(near_hi, dtype=np.float64))
        agree = lo2 <= hi2
        lo = np.where(agree, lo2, lo)
        hi = np.where(agree, hi2, hi)
    for k, v in (pins or {}).items():
        k = int(k)
        if 0 <= k < n:
            v = float(min(max(v, lo[k]), hi[k]))
            lo[k] = hi[k] = v
    if n < 3:
        return np.clip(g, lo, hi).astype(np.float32)
    k = max(3, int(round(smooth_m / step_m)) | 1)
    e = np.convolve(np.pad(g, (k, k), mode="edge"), np.ones(k) / k, mode="same")[k:-k]
    if bias is not None:
        e = e + np.asarray(bias, dtype=np.float64)
    e = np.clip(e, lo, hi)
    step = max_grade * step_m
    for _ in range(sweeps):
        before = e.copy()
        for i in range(1, n):                      # forward: no steeper than the grade...
            e[i] = min(max(e[i], e[i - 1] - step), e[i - 1] + step)
            e[i] = min(max(e[i], lo[i]), hi[i])    # ...and never out of the band
        for i in range(n - 2, -1, -1):             # and back again
            e[i] = min(max(e[i], e[i + 1] - step), e[i + 1] + step)
            e[i] = min(max(e[i], lo[i]), hi[i])
        if float(np.abs(e - before).max()) < 1e-3:
            break
    # take the corners off the kinks the sweeps leave, and keep it in the band doing so
    for _ in range(2):
        e[1:-1] = 0.25 * e[:-2] + 0.5 * e[1:-1] + 0.25 * e[2:]
        e = np.clip(e, lo, hi)
    return e.astype(np.float32)


## Routing. A road is a least-cost path on a coarse lattice whose cost knows three things the
## old one did not. Grade costs the same both ways: a road is driven in both directions, and
## the old graph charged for climbing and nothing for descending, so a route planned from
## Kharrow Hold down to the Mere went straight over the edge of the mountain. Grade past the
## design grade costs quadratically, so a steep slope is worth going round or zigzagging up
## rather than climbing straight. And a change of heading costs something, because a lattice
## path that alternates two diagonals has a gentle grade on every edge and smooths out into a
## road straight up the fall line; with turns priced, a switchback's legs have to be long.
##
## Eight headings are enough to choose which side of a hill to go. They are not enough to climb
## one: on a uniform slope every edge that climbs at all climbs at 71% of the slope or more, so
## above 16% no lattice path has a gentle edge in it and the router cannot see what a
## switchback buys. The fine pass (`_refine`) adds the knight's moves, whose 27-degree heading
## across the fall line climbs at 45% of the slope, and that is what lets it zigzag.
_HEADINGS8 = ((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))
_HEADINGS16 = ((0, 1), (1, 2), (1, 1), (2, 1), (1, 0), (2, -1), (1, -1), (1, -2),
               (0, -1), (-1, -2), (-1, -1), (-2, -1), (-1, 0), (-2, 1), (-1, 1), (-1, 2))
_HEADINGS = _HEADINGS8
## metres of road that a change of heading is worth, by how far it turns: up to 30, 50, 95 and
## 140 degrees, and anything sharper (a hairpin)
_TURN_BY_ANGLE = ((1.0, 0.0), (30.0, 3.0), (50.0, 8.0), (95.0, 55.0), (140.0, 130.0), (181.0, 190.0))
_GRADE_LINEAR = 12.0
_GRADE_OVER = (0.10, 400.0)          # past this grade, cost grows with the square of the excess
_GRADE_STEEP = (0.22, 1500.0)        # and past this, much faster still


def _turn_table(headings: tuple) -> np.ndarray:
    """[from, to] cost of turning between two headings, by the angle between them."""
    ang = [math.atan2(di, dj) for di, dj in headings]
    nh = len(headings)
    out = np.zeros((nh, nh), dtype=np.float64)
    for a in range(nh):
        for b in range(nh):
            turn = abs(math.degrees(ang[b] - ang[a])) % 360.0
            turn = min(turn, 360.0 - turn)
            out[a, b] = next(c for limit, c in _TURN_BY_ANGLE if turn <= limit)
    return out


def _edge_costs(h: np.ndarray, area: np.ndarray, spacing: float, headings: tuple = _HEADINGS8) -> list:
    """Per heading, the cost of leaving each cell that way (inf where it would leave the box)."""
    m, k = h.shape
    out = []
    for di, dj in headings:
        length = spacing * math.hypot(di, dj)
        src_i = slice(max(0, -di), m - max(0, di))
        src_j = slice(max(0, -dj), k - max(0, dj))
        dst_i = slice(max(0, di), m - max(0, -di))
        dst_j = slice(max(0, dj), k - max(0, -dj))
        grade = np.abs(h[dst_i, dst_j] - h[src_i, src_j]) / length
        over = np.maximum(grade - _GRADE_OVER[0], 0.0)
        steep = np.maximum(grade - _GRADE_STEEP[0], 0.0)
        c = length * (0.5 * (area[src_i, src_j] + area[dst_i, dst_j]) + _GRADE_LINEAR * grade
                      + _GRADE_OVER[1] * over * over + _GRADE_STEEP[1] * steep * steep)
        full = np.full((m, k), np.inf, dtype=np.float64)
        full[src_i, src_j] = c
        out.append(full)
    return out


def _route(h: np.ndarray, area: np.ndarray, spacing: float, start: tuple, goal: tuple,
           margin: int, allowed: np.ndarray | None = None, headings: tuple = _HEADINGS8) -> list:
    """Least-cost lattice route with priced turns. Returns [(i, j), ...], or [] if there is none.

    The search is over (cell, heading) states inside a box around the two ends, `margin` cells
    wider than they are on every side: room to go round a hill, and a graph of a few hundred
    thousand states rather than two million. `allowed`, the lattice's shape, narrows the search
    further to a corridor; only its cells get states at all.
    """
    from scipy.sparse import coo_matrix, csgraph

    n0, n1 = h.shape
    i0 = max(0, min(start[0], goal[0]) - margin)
    i1 = min(n0, max(start[0], goal[0]) + margin + 1)
    j0 = max(0, min(start[1], goal[1]) - margin)
    j1 = min(n1, max(start[1], goal[1]) + margin + 1)
    hs = h[i0:i1, j0:j1].astype(np.float64)
    ar = area[i0:i1, j0:j1].astype(np.float64)
    m, k = hs.shape
    ok_cell = np.ones((m, k), dtype=bool) if allowed is None else allowed[i0:i1, j0:j1].copy()
    ok_cell[start[0] - i0, start[1] - j0] = True
    ok_cell[goal[0] - i0, goal[1] - j0] = True
    cells = int(ok_cell.sum())
    compact = np.full((m, k), -1, dtype=np.int64)
    compact[ok_cell] = np.arange(cells, dtype=np.int64)
    nh = len(headings)
    costs = _edge_costs(hs, ar, spacing, headings)
    turns = _turn_table(headings)
    rows, cols, data = [], [], []
    for d_out, (di, dj) in enumerate(headings):
        c = costs[d_out]
        si, sj = np.nonzero(np.isfinite(c) & ok_cell)
        ti, tj = si + di, sj + dj
        keep = compact[ti, tj] >= 0
        src = compact[si[keep], sj[keep]]
        dst = compact[ti[keep], tj[keep]]
        base = c[si[keep], sj[keep]]
        for d_in in range(nh):
            rows.append(src * nh + d_in)
            cols.append(dst * nh + d_out)
            data.append(base + turns[d_in, d_out])
    graph = coo_matrix((np.concatenate(data), (np.concatenate(rows), np.concatenate(cols))),
                       shape=(cells * nh, cells * nh)).tocsr()
    s_cell = int(compact[start[0] - i0, start[1] - j0])
    g_cell = int(compact[goal[0] - i0, goal[1] - j0])
    sources = {s_cell * nh + d for d in range(nh)}
    dist, pred, _ = csgraph.dijkstra(graph, directed=True, indices=sorted(sources), min_only=True,
                                     return_predecessors=True)
    goals = np.array([g_cell * nh + d for d in range(nh)])
    best = int(goals[int(np.argmin(dist[goals]))])
    if not np.isfinite(dist[best]):
        return []
    where = np.argwhere(ok_cell)                      # compact id -> (i, j) in the box
    path = []
    cur = best
    guard = 0
    while cur >= 0 and guard < cells * nh:
        ci, cj = where[cur // nh]
        cell = (int(ci) + i0, int(cj) + j0)
        if not path or path[-1] != cell:
            path.append(cell)
        if cur in sources:
            break
        cur = int(pred[cur])
        guard += 1
    path.reverse()
    return path


## What a metre of road across open water costs, in metres of road on dry ground.
WATER_COST = 30.0


def _water_cells(water_mask: np.ndarray, n: int) -> np.ndarray:
    """How much of each coarse cell is water that a road cannot stand on, 0..1.

    A cell counts as water only where all of it is: the Long Stride is twelve metres wide, and
    a sixteen-metre cell with the causeway down its middle is half water by area -- which
    priced the causeway nearly as high as the open Mere, and the road to Tollmere swam.
    """
    m = water_mask.shape[0]
    if m == n:
        return water_mask.astype(np.float32)
    if n > m or m % n:
        return downsample(water_mask.astype(np.float32), n)
    f = m // n
    return water_mask.reshape(n, f, n, f).min(axis=(1, 3)).astype(np.float32)


## A road that follows the crest of a knife-edge spur, or the floor of a V-shaped gully, stands
## above (or below) the ground either side of it by the ground's own relief, and from beside it
## that reads exactly as the arete did. Measured on the first build with the new profile, the
## road down the spur from Kharrow Hold stood 12.5 m above both sides on natural ground. So the
## fine router prices how far a cell stands above or below its own twenty metres (`CREST_COST`
## per metre past `CREST_FREE_M`), and a road crosses a spur or a gully rather than riding it.
CREST_FREE_M = 1.5
CREST_COST = 1.4
CLIFF_COST = 30.0
## A road already laid is cheaper to follow than new ground is to cross: two roads out of one
## town share their trunk and fork, rather than running side by side a few metres apart at two
## different levels, which is where their carves cut steps into each other.
TRUNK_DISCOUNT = 0.55


def _refine(grid: Grid, H: np.ndarray, water_mask: np.ndarray, coarse_pts: np.ndarray,
            spacing: float = 4.0, corridor_m: float = 64.0,
            laid: list | None = None) -> np.ndarray | None:
    """Route again on a fine lattice, inside a corridor around the coarse route.

    The coarse lattice is sixteen metres a cell, which is fine for choosing which side of a hill
    to go but too coarse to lay a road on: smoothing its staircase into a curve cuts the corners
    of every switchback and steepens it. Re-routed at four metres within sixty of the coarse
    line, the road finds the gentle line across each slope at the scale it is actually built,
    and the curve it smooths into is already most of the way to smooth. `laid` is the centre
    lines of the roads already planned (world points), which this one would rather share.
    Returns world points, or None when the grid is too coarse for a second pass to add anything.
    """
    spacing = max(spacing, grid.spacing)
    n_f = int(round(grid.size_m / spacing))
    if spacing >= 12.0 or grid.n % n_f != 0:
        return None
    gf = grid.with_n(n_f)
    # a box around the coarse line, so the fine arrays are only as large as the road needs
    pad = corridor_m + 8.0 * spacing
    x0, x1 = float(coarse_pts[:, 0].min() - pad), float(coarse_pts[:, 0].max() + pad)
    z0, z1 = float(coarse_pts[:, 1].min() - pad), float(coarse_pts[:, 1].max() + pad)
    j0, i0 = gf.to_tex(x0, z0)
    j1, i1 = gf.to_tex(x1, z1)
    i0, j0 = max(0, int(i0)), max(0, int(j0))
    i1, j1 = min(n_f, int(i1) + 2), min(n_f, int(j1) + 2)
    f = grid.n // n_f
    sub_h = H[i0 * f:i1 * f, j0 * f:j1 * f]
    sub_w = water_mask[i0 * f:i1 * f, j0 * f:j1 * f].astype(np.float32)
    m, k = i1 - i0, j1 - j0
    if f > 1:
        sub_h = sub_h[:m * f, :k * f].reshape(m, f, k, f).mean(axis=(1, 3))
        sub_w = sub_w[:m * f, :k * f].reshape(m, f, k, f).min(axis=(1, 3))
    # The route should see the lie of the land, not every tussock: routed over the raw detail
    # band, the road wove round bumps a metre high and drew a drunkard's line across the moor.
    # Bumps that small are what the profile's own tolerance absorbs. What smoothing must not
    # hide is a cleft: a ravine twelve metres across and eighteen deep smooths into a dimple,
    # and a road that crosses it has to go down into it. So the raw ground's steepest pitch
    # nearby is priced separately, whichever way the road crosses it.
    raw = sub_h.astype(np.float64)
    raw_slope = ndimage.maximum_filter(np.hypot(*np.gradient(raw, spacing)), size=3)
    # how far each cell stands proud of (or sunk into) the ground within about twenty metres
    crest = np.abs(raw - ndimage.gaussian_filter(raw, sigma=10.0 / spacing, mode="nearest"))
    sub_h = ndimage.gaussian_filter(raw, sigma=6.0 / spacing, mode="nearest")
    # the corridor: within `corridor_m` of the coarse line
    line = np.zeros((m, k), dtype=bool)
    dense = paths.resample_polyline(coarse_pts, spacing * 0.5)
    lj = np.clip(np.rint((dense[:, 0] - gf.x0) / spacing).astype(np.int64) - j0, 0, k - 1)
    li = np.clip(np.rint((dense[:, 1] - gf.z0) / spacing).astype(np.int64) - i0, 0, m - 1)
    line[li, lj] = True
    allowed = ndimage.distance_transform_edt(~line) * spacing <= corridor_m
    # A cliff is priced hard enough that a road will go three hundred metres round a gorge
    # rather than down one wall and up the other: a profile that follows the ground has no
    # other way to cross a slot twelve metres wide than to go into it.
    area = 1.0 + WATER_COST * sub_w + 6.0 * np.clip(raw_slope - 0.45, 0.0, None) \
        + CLIFF_COST * np.clip(raw_slope - 0.9, 0.0, None) \
        + CREST_COST * np.clip(crest - CREST_FREE_M, 0.0, None)
    if laid:
        on = np.zeros((m, k), dtype=bool)
        for pts in laid:
            q = paths.resample_polyline(np.asarray(pts, dtype=np.float64), spacing * 0.5)
            qj = np.rint((q[:, 0] - gf.x0) / spacing).astype(np.int64) - j0
            qi = np.rint((q[:, 1] - gf.z0) / spacing).astype(np.int64) - i0
            ok = (qi >= 0) & (qi < m) & (qj >= 0) & (qj < k)
            on[qi[ok], qj[ok]] = True
        area = np.where(on, area * TRUNK_DISCOUNT, area)
    start = (int(li[0]), int(lj[0]))
    goal = (int(li[-1]), int(lj[-1]))
    route = _route(sub_h, area, spacing, start, goal, margin=max(m, k), allowed=allowed,
                   headings=_HEADINGS16)
    if len(route) < 3:
        return None
    return np.array([[gf.x0 + (j + j0) * spacing, gf.z0 + (i + i0) * spacing] for i, j in route],
                    dtype=np.float64)


def _ground_along(grid: Grid, H: np.ndarray, pts: np.ndarray, width: float,
                  floor: np.ndarray | None = None) -> np.ndarray:
    """The land under a road: the mean across its carriageway, at each point.

    `floor` lifts it where the road crosses water, so a profile laid across a river is laid
    across its surface and not along its bed.
    """
    from .grid import sample_bilinear

    d = np.gradient(pts, axis=0)
    nrm = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)
    nx, nz = -d[:, 1] / nrm, d[:, 0] / nrm
    acc = np.zeros(pts.shape[0], dtype=np.float64)
    for off in (-0.5 * width, 0.0, 0.5 * width):
        x = pts[:, 0] + nx * off
        z = pts[:, 1] + nz * off
        h = sample_bilinear(H, grid, x, z).astype(np.float64)
        if floor is not None:
            h = np.maximum(h, sample_bilinear(floor, grid, x, z).astype(np.float64))
        acc += h
    return acc / 3.0


def stop_short(pts: np.ndarray, centre, radius: float, at_end: bool = True) -> np.ndarray:
    """A road that runs into something solid stops at its foot: `pts` cut where, walking toward
    `centre` from the road's other end, it first comes within `radius` of it, and ending on that
    circle. `at_end` says which end of `pts` the centre is at. A road that starts inside the circle
    is left alone."""
    seq = pts if at_end else pts[::-1]
    d = np.hypot(seq[:, 0] - float(centre[0]), seq[:, 1] - float(centre[1]))
    inside = np.flatnonzero(d < radius)
    if inside.size == 0 or int(inside[0]) == 0:
        return pts
    k = int(inside[0])
    p, q = seq[k - 1], seq[k]
    t = (d[k - 1] - radius) / max(d[k - 1] - d[k], 1e-9)
    out = np.vstack([seq[:k], (p + (q - p) * t)[None, :]])
    return out if at_end else out[::-1].copy()


def plan_roads(grid: Grid, H: np.ndarray, specs: list, things: dict, water_mask: np.ndarray, levels: dict,
               n_c: int = 512, floor: np.ndarray | None = None, sink: np.ndarray | None = None,
               no_fill: np.ndarray | None = None, lake=None, solid: dict | None = None) -> list:
    """The atlas's roads, each laid on the ground from its start through its via points to its end.

    `specs` is the atlas's `roads` (tools/world/atlas/SCHEMA.md) and `things` every place and POI
    by id. Each leg between two waypoints is routed with priced grades and turns (`_route`) on a
    16 m lattice and again on a 4 m one inside a corridor round the first (`_refine`); a
    causeway's legs over a lake (`lake`, geography.Waters) are laid straight along its deck.
    The whole is smoothed and given a profile that follows the ground within the carve's own
    tolerance (`grade_profile`). Where a road runs along one laid before it, it takes that road's
    levels, so two roads sharing the way out of a town are carved as one road and not as two at
    different heights. `floor` is the water surface a road may not be graded under (see
    `_ground_along`). `sink` is how far below the land a road would rather run, in metres, where
    that is a landform's character: the Briarwold's lanes are holloways, worn down between their
    banks by centuries of feet. `no_fill` marks ground a road may cut into but not build up: the
    corridors of the authored sightlines, where an embankment legal anywhere else rose into the
    line from Greyfold to the Cold Fire. `solid` is {place id: metres}: what stands solid on a
    place's own position, and how far it reaches across the ground from there, plus room for a
    body. A road to or from such a place stops at its foot (`stop_short`). The Sunken Choir's head
    colossus stands on the Choir's position, and the Stair Path ran on into it.
    """
    from scipy.spatial import cKDTree

    from .geography import ROAD_WIDTH_BY_KIND

    n_c = min(n_c, grid.n)
    gc = grid.with_n(n_c)
    hc = downsample(H, n_c)
    wc = _water_cells(water_mask, n_c)
    slope = np.hypot(*np.gradient(hc, gc.spacing)).astype(np.float32)
    # Open water is all but impassable; a river is crossed at a ford, and a causeway is dry
    # ground. The grade a road takes is priced per edge in `_route`; this is only the ground
    # nobody would bench a road into whichever way it crossed it.
    area = (1.0 + WATER_COST * wc + 3.0 * np.clip(slope - 0.55, 0.0, None))
    # and the spurs and gullies at this scale, so the fine pass is not handed a corridor that
    # runs along a knife-edge with nowhere else to go (`CREST_COST`, at a sixteen-metre cell)
    crest_c = np.abs(hc - ndimage.gaussian_filter(hc.astype(np.float64), sigma=1.5, mode="nearest"))
    area = area + 0.5 * CREST_COST * np.clip(crest_c - 2.0 * CREST_FREE_M, 0.0, None)
    # and the cliffs inside a cell, which its mean height hides: the steepest texel in it
    f = grid.n // n_c
    if f > 1 and grid.n % n_c == 0:
        steep = np.hypot(*np.gradient(H.astype(np.float32), grid.spacing))
        steep = steep.reshape(n_c, f, n_c, f).max(axis=(1, 3))
        area = area + 0.3 * CLIFF_COST * np.clip(steep - 0.9, 0.0, 3.0)
        del steep

    def ij(x, z):
        j, i = gc.to_tex(x, z)
        j, i = gc.clamp_index(j, i)
        return int(i), int(j)

    def over_lake(p, q) -> bool:
        if lake is None:
            return False
        from .grid import sample_nearest
        t = np.linspace(0.0, 1.0, 64)
        x = p[0] + (q[0] - p[0]) * t
        z = p[1] + (q[1] - p[1]) * t
        wet = sample_nearest((lake.sd < 0.0).astype(np.uint8), grid, x, z) > 0
        return bool(wet.mean() > 0.2)

    roads: list[Road] = []
    ids: set = set()
    laid_pts: list = []        # the centre lines of the roads already planned, every 2 m
    laid_elev: list = []       # and their levels there
    laid_ground: list = []     # and the land they were graded against
    laid_width: list = []      # and their widths
    # A profile every 4 m: at 12 m, a cleft twelve metres across was one sample on one road and
    # none on the next, and two roads sharing a trunk were graded 13 m apart at the same place.
    step_m = 4.0
    for spec in specs:
        a, b = things.get(spec["from"]), things.get(spec["to"])
        if a is None or b is None:
            continue
        kind = str(spec.get("kind", "road"))
        w = float(ROAD_WIDTH_BY_KIND.get(kind, 5.0))
        ends = [np.array(a["position"][:2], dtype=np.float64), np.array(b["position"][:2], dtype=np.float64)]
        wps = [ends[0]] + [np.array(v, dtype=np.float64) for v in spec.get("via", [])] + [ends[1]]
        # the roads already laid are cheaper to follow than new ground (TRUNK_DISCOUNT)
        area_now = area
        if laid_pts:
            on = np.zeros((n_c, n_c), dtype=bool)
            q = np.concatenate(laid_pts)
            qj, qi = gc.clamp_index(*gc.to_tex(q[:, 0], q[:, 1]))
            on[qi, qj] = True
            area_now = np.where(on, area * TRUNK_DISCOUNT, area)
        legs = []
        for p, q in zip(wps[:-1], wps[1:]):
            if kind == "stair" or (kind == "causeway" and over_lake(p, q)):
                legs.append(paths.resample_polyline(np.stack([p, q]), step_m))
                continue
            sa, sb = ij(p[0], p[1]), ij(q[0], q[1])
            span = int(max(abs(sa[0] - sb[0]), abs(sa[1] - sb[1])))
            route = _route(hc, area_now, gc.spacing, sa, sb, margin=max(30, int(0.45 * span)))
            # A box round the two ends is room to go round a hill, not round a lake. A route that
            # crosses open water gets the whole lattice to find a dry one; if there is none, the
            # water is the answer after all.
            if not route or sum(1 for i, j in route if wc[i, j] > 0.99) > 2:
                wide = _route(hc, area_now, gc.spacing, sa, sb, margin=n_c)
                if wide:
                    route = wide
            if len(route) < 3:
                legs.append(paths.resample_polyline(np.stack([p, q]), step_m))
                continue
            pts = np.array([[gc.x0 + j * gc.spacing, gc.z0 + i * gc.spacing] for i, j in route], dtype=np.float64)
            pts[0] = p
            pts[-1] = q
            fine = _refine(grid, H, water_mask, pts, laid=laid_pts)
            if fine is not None:
                fine[0] = p
                fine[-1] = q
                pts = paths.smooth_polyline(fine, passes=6)
            else:
                pts = paths.smooth_polyline(pts, passes=4)
            legs.append(pts)
        pts = np.concatenate([leg if k == 0 else leg[1:] for k, leg in enumerate(legs)])
        if kind != "stair":
            pts = paths.resample_polyline(pts, step_m)
        # (a stair keeps its corners: resampled across a switchback, a corner is cut short by a
        # step that runs straight down the fall line, the one line a stair must not take)
        pts[0] = ends[0]
        pts[-1] = ends[1]
        stopped = set()
        for at_end, tid in ((False, spec["from"]), (True, spec["to"])):
            reach = float((solid or {}).get(tid, 0.0))
            if reach > 0.0:
                n_before = pts.shape[0]
                pts = stop_short(pts, ends[1] if at_end else ends[0], reach, at_end)
                if pts.shape[0] != n_before or not np.allclose(pts[-1 if at_end else 0], ends[1 if at_end else 0]):
                    stopped.add(tid)
        last = pts.shape[0] - 1
        # Where this road's carriageway overlaps one already laid, it IS that road: its points
        # are moved onto the other's centre line and take its level and the land it recorded.
        # Laid a few metres beside it instead, the two were graded against different ground --
        # on either side of a scar's riser, ten metres apart in height across four -- and their
        # carves cut steps into each other.
        snapped: dict = {}
        tree = None
        max_w = max(ROAD_WIDTH_BY_KIND.values())
        if laid_pts:
            laid_all = np.concatenate(laid_pts)
            tree = cKDTree(laid_all)
            elev_all = np.concatenate(laid_elev)
            ground_all = np.concatenate(laid_ground)
            width_all = np.concatenate(laid_width)
            dist, near = tree.query(pts, distance_upper_bound=0.5 * (w + max_w) + 1.5)
            for kk in np.flatnonzero(np.isfinite(dist)):
                if not 0 < kk < last:
                    continue
                if float(dist[kk]) <= 0.5 * (w + float(width_all[near[kk]])) + 1.5:
                    pts[kk] = laid_all[near[kk]]
                    snapped[int(kk)] = int(near[kk])
        ground = _ground_along(grid, H, pts, w, floor)
        for kk, idx in snapped.items():
            ground[kk] = float(ground_all[idx])
        # (a road stopped at a landmark's foot ends on the ground there, which may be off its pad)
        pins = {0: float(ground[0]) if a["id"] in stopped else levels.get(a["id"], float(ground[0])),
                last: float(ground[-1]) if b["id"] in stopped else levels.get(b["id"], float(ground[-1]))}
        for kk, idx in snapped.items():
            pins[kk] = float(elev_all[idx])
        # and where it passes near one, it may differ from it by no more than a one-in-two
        # batter between the two carriageways allows, so the two carves meet on a bank
        near_lo = near_hi = None
        if tree is not None:
            reach = w * 0.5 + shoulder_m(max_w) + 0.5 * max_w
            dist, near = tree.query(pts, distance_upper_bound=reach)
            near_lo = np.full(pts.shape[0], -np.inf)
            near_hi = np.full(pts.shape[0], np.inf)
            for kk in np.flatnonzero(np.isfinite(dist)):
                if not 0 < kk < last or int(kk) in snapped:
                    continue
                e_other = float(elev_all[near[kk]])
                gap = float(dist[kk]) - 0.5 * w - 0.5 * float(width_all[near[kk]])
                if gap < shoulder_m(w) + shoulder_m(float(width_all[near[kk]])):
                    room = BATTER * max(gap, 0.0)
                    near_lo[kk] = e_other - room
                    near_hi[kk] = e_other + room
        bias = None
        if sink is not None:
            from .grid import sample_bilinear
            bias = -sample_bilinear(sink, grid, pts[:, 0], pts[:, 1]).astype(np.float64)
        cap = None
        if no_fill is not None:
            from .grid import sample_nearest
            cap = sample_nearest(no_fill.astype(np.uint8), grid, pts[:, 0], pts[:, 1]) > 0
        elev = grade_profile(ground, step_m, cut_fill_m(w),
                             max_grade=STAIR_MAX_GRADE if kind == "stair" else MAX_GRADE,
                             pins=pins, bias=bias, no_fill=cap, near_lo=near_lo, near_hi=near_hi,
                             **({"smooth_m": 12.0} if kind == "stair" else {}))
        rid = str(spec.get("id") or "core:road/%s_%s" % (a["id"].split("/")[-1], b["id"].split("/")[-1]))
        base_id, k = rid, 2
        while rid in ids:
            rid = "%s_%d" % (base_id, k)
            k += 1
        ids.add(rid)
        roads.append(Road(id=rid, points=pts, width=w, elevation=elev, ground=ground.astype(np.float32)))
        dense = paths.resample_polyline(pts, 2.0)
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        sd = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
        laid_pts.append(dense)
        laid_elev.append(np.interp(sd, s, elev.astype(np.float64)))
        laid_ground.append(np.interp(sd, s, ground.astype(np.float64)))
        laid_width.append(np.full(dense.shape[0], w))
    return roads


## How far off both legs of the through street a third road has to arrive to earn a cross
## street: more than about 49 degrees (|cos| under 0.66). It was 0.55, 57 degrees, and when the
## roads were laid on the ground instead of over it Pilgrim's Ash's side road came in 64 degrees
## off one leg and 50 off the other and the town lost its crossing. No other town changes: the
## only others with three roads (Grandfather Hollow, Kharrow Hold) send two of them out on one
## trunk, and Merrowby's and Gullhithe's side roads are 68 and 66 degrees off.
CROSS_STREET_DOT = 0.66


def add_streets(roads: list, places: list, levels: dict) -> list:
    """Carry every road through its settlement instead of stopping it at the middle.

    A road planned between two towns ends exactly on the second town's centre, so a place with
    three roads has three spokes meeting at a point. That is not a street plan: a settlement is
    somewhere a road passes *through*, and a town where two routes meet has a crossing.

    For each settlement this lays a street along the dominant pair of approach bearings, from
    one side of the pad to the other, and a cross street where a third road arrives at enough
    of an angle to justify one. The result is a polyline that enters the pad, crosses it and
    leaves, which is what the settlement builder needs to lay plots along a frontage, and which
    the surface rules pave.
    """
    by_place: dict = {}
    for r in roads:
        for end, other in ((0, -1), (-1, 0)):
            p = r.points[end]
            for pl in places:
                if pl.get("kind") not in ROAD_KINDS:
                    continue
                cx, cz = float(pl["position"][0]), float(pl["position"][1])
                if abs(p[0] - cx) < 1.0 and abs(p[1] - cz) < 1.0:
                    # the bearing the road arrives on, taken far enough back (about 72 m, which
                    # was six points when roads were sampled every 12 m) to ignore the last
                    # smoothing wiggle
                    seg = float(np.mean(np.linalg.norm(np.diff(r.points, axis=0), axis=1)))
                    step = min(max(1, int(round(72.0 / max(seg, 1e-3)))), len(r.points) - 1)
                    away = r.points[end - step] if end == -1 else r.points[step]
                    v = np.array([away[0] - cx, away[1] - cz], dtype=np.float64)
                    nrm = float(np.hypot(v[0], v[1]))
                    if nrm > 1e-3:
                        by_place.setdefault(pl["id"], (pl, []))[1].append(v / nrm)
    out: list[Road] = []
    for pid, (place, dirs) in by_place.items():
        short = pid.split("/")[-1]
        r_pad = pad_radius(place) * 0.94
        cx, cz = float(place["position"][0]), float(place["position"][1])
        level = float(levels.get(pid, 0.0))
        width = ROAD_WIDTH.get(str(place.get("kind", "")), 4.5)
        # the most opposed pair of approaches is the through route
        best = (2.0, dirs[0], -dirs[0])
        for i in range(len(dirs)):
            for j in range(i + 1, len(dirs)):
                dot = float(np.dot(dirs[i], dirs[j]))
                if dot < best[0]:
                    best = (dot, dirs[i], dirs[j])
        streets = [(best[1], best[2])]
        # a third road arriving across the grain earns a cross street
        for d in dirs:
            if abs(float(np.dot(d, best[1]))) < CROSS_STREET_DOT and abs(float(np.dot(d, best[2]))) < CROSS_STREET_DOT:
                streets.append((d, -d))
                break
        for n, (a, b) in enumerate(streets):
            pts = []
            for t in np.linspace(-1.0, 1.0, 13):
                d = a if t < 0 else b
                pts.append([cx + d[0] * r_pad * abs(t), cz + d[1] * r_pad * abs(t)])
            pts = np.array(pts, dtype=np.float64)
            # a street is level: it is laid on the flattened ground of the place itself
            elev = np.full(pts.shape[0], level, dtype=np.float64)
            out.append(Road(id="core:road/%s_street%s" % (short, "" if n == 0 else "_cross"),
                            points=pts, width=width, elevation=elev, ground=elev.copy()))
    return roads + out


def carve_roads(grid: Grid, H: np.ndarray, roads: list, no_fill: np.ndarray | None = None) -> tuple:
    """Cut the graded corridors in. Returns (heights, distance to road centre line, width map).

    Where `no_fill` is set (an authored sightline's corridor) the carve only ever lowers the
    land: a road benched across a slope there is cut in on its uphill side and left on the
    ground on its downhill side, rather than built up into the line.
    """
    n = grid.n
    mask = np.zeros((n, n), dtype=bool)
    elev = np.zeros((n, n), dtype=np.float32)
    wide = np.zeros((n, n), dtype=np.float32)
    for r in roads:
        paths.rasterise_polyline(r.points, grid, value=r.elevation, out_mask=mask, out_value=elev)
        paths.rasterise_polyline(r.points, grid, value=np.full(r.points.shape[0], r.width, dtype=np.float32),
                                 out_mask=mask, out_value=wide)
    if not mask.any():
        return H, np.full((n, n), 1e6, dtype=np.float32), wide
    dist_t, (ii, jj) = ndimage.distance_transform_edt(~mask, return_indices=True)
    d = (dist_t * grid.spacing).astype(np.float32)
    near_e = elev[ii, jj]
    near_w = wide[ii, jj]
    del ii, jj, dist_t
    half = near_w * 0.5
    shoulder = np.maximum(near_w * 1.8, 7.0)
    crown = near_e + 0.12 * (1.0 - np.clip(d / np.maximum(half, 0.5), 0.0, 1.0) ** 2)
    w = 1.0 - smoothstep(half, half + shoulder, d)
    Hn = lerp(H, crown, w)
    if no_fill is not None:
        Hn = np.where(no_fill, np.minimum(H, Hn), Hn)
    return Hn.astype(np.float32), d, near_w
