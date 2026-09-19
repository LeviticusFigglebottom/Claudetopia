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
ROAD_KINDS = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
ROAD_WIDTH = {"city": 6.0, "town": 6.0, "village": 5.0, "fort": 5.0, "hamlet": 4.5, "camp": 4.0,
              "lodge": 4.0, "ruin_village": 4.0}


@dataclass
class Road:
    id: str
    points: np.ndarray
    width: float
    elevation: np.ndarray


def pad_radius(place: dict) -> float:
    """Enough flat ground for the houses that will stand here, and no more.

    Frontage rather than area is what a street plan needs: n houses at about eight metres of
    frontage, along two sides of one or two streets, is a street length of roughly 2n metres,
    so the radius grows with the square root of the count and not with the count itself.
    """
    kind = str(place.get("kind", ""))
    count = FABRIC_COUNT.get(kind)
    if count is None:
        return PAD_DEFAULT
    if count <= 0:
        return 30.0
    return float(min(max(20.0 + 7.5 * math.sqrt(count), 26.0), 80.0))


def apply_pads(grid: Grid, H: np.ndarray, places: list, min_levels: dict | None = None) -> tuple:
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
        levels[p["id"]] = level
        w = 1.0 - smoothstep(r * 0.7, r * 1.6, d)
        H[i0:i1, j0:j1] = lerp(sub, level, w)
        pad_mask[i0:i1, j0:j1] |= d <= r
    return H, pad_mask, levels


def _grade(profile: np.ndarray, step_m: float, max_grade: float = 0.11, passes: int = 60) -> np.ndarray:
    """Smooth then slope-limit a road's elevation profile."""
    p = profile.astype(np.float64).copy()
    k = max(3, int(90.0 / step_m) | 1)
    kern = np.ones(k) / k
    p = np.convolve(np.pad(p, (k, k), mode="edge"), kern, mode="same")[k:-k]
    limit = max_grade * step_m
    for _ in range(passes):
        d = np.diff(p)
        over = np.abs(d) > limit
        if not over.any():
            break
        adj = np.sign(d) * np.minimum(np.abs(d), limit)
        p[1:] = p[:-1] + adj
        p = np.convolve(np.pad(p, (2, 2), mode="edge"), np.ones(5) / 5, mode="same")[2:-2]
    return p.astype(np.float32)


def plan_roads(grid: Grid, H: np.ndarray, places: list, water_mask: np.ndarray, levels: dict,
               n_c: int = 512) -> list:
    """Minimum spanning tree over settlements plus a couple of convenience links."""
    n_c = min(n_c, grid.n)
    gc = grid.with_n(n_c)
    hc = downsample(H, n_c)
    wc = downsample(water_mask.astype(np.float32), n_c)
    slope = np.hypot(*np.gradient(hc, gc.spacing)).astype(np.float32)
    area = (1.0 + 7.0 * wc + 2.5 * np.clip(slope - 0.18, 0.0, None))
    graph = paths.build_graph(hc, gc.spacing, climb_penalty=26.0, descent_bonus=0.0, area_cost=area)
    towns = [p for p in places if p.get("kind") in ROAD_KINDS]
    if len(towns) < 2:
        return []

    def ij(p):
        j, i = gc.to_tex(p["position"][0], p["position"][1])
        j, i = gc.clamp_index(j, i)
        return int(i), int(j)

    pos = np.array([[p["position"][0], p["position"][1]] for p in towns], dtype=np.float64)
    # Prim's algorithm over straight-line distance, then route each chosen edge properly
    k = len(towns)
    in_tree = [0]
    edges = []
    while len(in_tree) < k:
        best = None
        for a in in_tree:
            for b in range(k):
                if b in in_tree:
                    continue
                d = float(np.hypot(*(pos[a] - pos[b])))
                if best is None or d < best[0]:
                    best = (d, a, b)
        edges.append((best[1], best[2]))
        in_tree.append(best[2])
    # a few extra links so the network is not a pure tree (ring roads around the Mere)
    extra = [("merrowby", "gullhithe"), ("isseva", "pilgrims_ash"), ("kharrow_hold", "grandfather_hollow")]
    by_short = {p["id"].split("/")[-1]: i for i, p in enumerate(towns)}
    for a, b in extra:
        if a in by_short and b in by_short:
            edges.append((by_short[a], by_short[b]))
    roads: list[Road] = []
    seen = set()
    for a, b in edges:
        key = tuple(sorted((a, b)))
        if key in seen:
            continue
        seen.add(key)
        route = paths.path_between(graph, n_c, ij(towns[a]), ij(towns[b]))
        if len(route) < 3:
            continue
        pts = np.array([[gc.x0 + j * gc.spacing, gc.z0 + i * gc.spacing] for i, j in route], dtype=np.float64)
        pts[0] = pos[a]
        pts[-1] = pos[b]
        pts = paths.smooth_polyline(pts, passes=6)
        pts = paths.resample_polyline(pts, 12.0)
        jj, ii = grid.to_tex(pts[:, 0], pts[:, 1])
        jj, ii = grid.clamp_index(jj, ii)
        prof = H[ii, jj].astype(np.float64)
        prof[0] = levels.get(towns[a]["id"], prof[0])
        prof[-1] = levels.get(towns[b]["id"], prof[-1])
        elev = _grade(prof, 12.0)
        elev[0] = prof[0]
        elev[-1] = prof[-1]
        w = max(ROAD_WIDTH.get(towns[a]["kind"], 4.0), ROAD_WIDTH.get(towns[b]["kind"], 4.0))
        roads.append(Road(id="core:road/%s_%s" % (towns[a]["id"].split("/")[-1], towns[b]["id"].split("/")[-1]),
                          points=pts, width=w, elevation=elev))
    return roads


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
                    # the bearing the road arrives on, taken far enough back to ignore the
                    # last smoothing wiggle
                    step = min(6, len(r.points) - 1)
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
            if abs(float(np.dot(d, best[1]))) < 0.55 and abs(float(np.dot(d, best[2]))) < 0.55:
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
                            points=pts, width=width, elevation=elev))
    return roads + out


def carve_roads(grid: Grid, H: np.ndarray, roads: list) -> tuple:
    """Cut the graded corridors in. Returns (heights, distance to road centre line, width map)."""
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
    return Hn.astype(np.float32), d, near_w
