"""Every tree is set into the ground at its whole foot, not at its pivot.

A tree was set down with its pivot (the middle of its trunk's foot) on the ground, at the ground's
height there. The roots and the flare reach out a metre or two past the trunk, five for the Briarwold's
giant oaks. On a slope, their downhill side stood over air, and the hedges, orchards and roadside
took the height of the nearest texel, not the ground under the pivot. Playtest 6 (1.webp) had a big
tree standing on the spikes of its roots with its trunk's foot clear of the soil.

`seat` goes over every tree in the buckets once they are all placed. It takes each tree's foot, the
points of it under 0.35 m that tools/world/tree_contacts.py read off the forge's mesh, turns them by
the row's yaw and scales them by its scale. It then sets the tree's pivot so that the highest of
them, measured over the ground where it stands, is SEAT_UNDER_M under that ground. The sink below
the ground at the pivot is capped at SEAT_CAP_M plus SEAT_CAP_PER_M of the tree's height, so no
tree on a crag is swallowed to its crown.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from .grid import Grid, sample_bilinear
from .rows import Rows

TABLE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tree_contacts.json")
SEAT_UNDER_M = 0.05
SEAT_CAP_M = 0.45
SEAT_CAP_PER_M = 0.05
## what is under a pivot on level ground: the forge grows each tree's foot a little into it
SEAT_MIN_SINK_M = 0.0


def load_table(path: str = TABLE) -> dict:
    """{asset name: (points [k, 3] at scale one, height m)}."""
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f).get("trees", {})
    return {k: (np.asarray(v["contacts"], dtype=np.float64).reshape(-1, 3), float(v.get("height_m", 5.0)))
            for k, v in raw.items() if v.get("contacts")}


def sink_for(H: np.ndarray, grid: Grid, x: np.ndarray, z: np.ndarray, yaw_deg: np.ndarray, scale: np.ndarray,
             pts: np.ndarray, height: float) -> tuple:
    """(pivot heights, sink under the ground at the pivot) for trees of one asset at (x, z)."""
    a = np.radians(yaw_deg.astype(np.float64))[:, None]
    c, s = np.cos(a), np.sin(a)
    px, py, pz = pts[None, :, 0], pts[None, :, 1], pts[None, :, 2]
    sc = scale.astype(np.float64)[:, None]
    # Godot's Basis(UP, a): x' = x cos a + z sin a, z' = -x sin a + z cos a
    wx = x[:, None] + sc * (px * c + pz * s)
    wz = z[:, None] + sc * (-px * s + pz * c)
    ground = sample_bilinear(H, grid, wx.ravel(), wz.ravel()).reshape(wx.shape)
    g0 = sample_bilinear(H, grid, x, z)
    # each foot point's height is pivot + scale * y: the pivot that puts the highest of them
    # SEAT_UNDER_M under its own ground
    want = np.min(ground - sc * py, axis=1) - SEAT_UNDER_M
    cap = SEAT_CAP_M + SEAT_CAP_PER_M * height * scale.astype(np.float64)
    y = np.maximum(np.minimum(want, g0 - SEAT_MIN_SINK_M), g0 - cap)
    return y.astype(np.float32), (g0 - y).astype(np.float32)


def seat(buckets: dict, grid: Grid, H: np.ndarray, table: dict | None = None) -> dict:
    """Set every tree in `buckets` into the ground at its whole foot (in place). Returns
    {"trees", "sunk_over_0_5_m", "capped"}."""
    table = load_table() if table is None else table
    counts = {"trees": 0, "sunk_over_0_5_m": 0, "capped": 0}
    for by_asset in buckets.values():
        for asset, rows in by_asset.items():
            if "/trees/" not in asset:
                continue
            name = os.path.splitext(os.path.basename(asset))[0]
            got = table.get(name)
            if got is None or not len(rows):
                continue
            pts, height = got
            if isinstance(rows, Rows):
                chunks = [c for c in rows._chunks]
            else:
                chunks = [rows]
            for c in chunks:
                if isinstance(c, list):
                    if not c:
                        continue
                    arr = np.array([(float(r[0]), float(r[2]), float(r[3]), float(r[4])) for r in c], dtype=np.float64)
                    y, sink = sink_for(H, grid, arr[:, 0], arr[:, 1], arr[:, 2], arr[:, 3], pts, height)
                    for r, v in zip(c, y.tolist()):
                        r[1] = round(v, 2)
                else:
                    y, sink = sink_for(H, grid, c["x"].astype(np.float64), c["z"].astype(np.float64), c["yaw"], c["scale"],
                                       pts, height)
                    c["y"] = y
                counts["trees"] += int(sink.size)
                counts["sunk_over_0_5_m"] += int((sink > 0.5).sum())
                cap = SEAT_CAP_M + SEAT_CAP_PER_M * height
                counts["capped"] += int((sink >= cap * 0.999).sum())
    return counts


def floating(H: np.ndarray, grid: Grid, rows: list, pts: np.ndarray) -> np.ndarray:
    """For rows [x, y, z, yaw, scale, ...] of one tree: how far the highest point of each one's foot
    stands over the ground under it (negative where the whole foot is in the ground)."""
    arr = np.array([(float(r[0]), float(r[1]), float(r[2]), float(r[3]), float(r[4])) for r in rows], dtype=np.float64)
    a = np.radians(arr[:, 3])[:, None]
    c, s = np.cos(a), np.sin(a)
    sc = arr[:, 4][:, None]
    wx = arr[:, 0][:, None] + sc * (pts[None, :, 0] * c + pts[None, :, 2] * s)
    wz = arr[:, 2][:, None] + sc * (-pts[None, :, 0] * s + pts[None, :, 2] * c)
    ground = sample_bilinear(H, grid, wx.ravel(), wz.ravel()).reshape(wx.shape)
    return np.max(arr[:, 1][:, None] + sc * pts[None, :, 1] - ground, axis=1)


# --- the authored sightlines ----------------------------------------------------------------------

## How far either side of an authored sightline's line a tree is judged: its trunk this near the
## line puts its crown (a downs oak's is 8-12 m across) into the view. Narrower than the rock's
## corridor (crags.SIGHTLINE_CORRIDOR_M, 30 m), which keeps whole outcrops out of a ray's way; a
## tree is a single crown, and a 24 m lane through a wood is already a ride, not a clearing.
SIGHT_TREE_CORRIDOR_M = 12.0
## and how far under the game's clearance (tools/sightlines.py CLEARANCE_M) under the ray its top
## must stay to be left standing
SIGHT_TREE_SPARE_M = 0.5
## the height of a tree the contact table does not know, at scale one
TREE_HEIGHT_DEFAULT_M = 10.0


class _Lines:
    """The authored sightlines, prepared once: each from its vantage's eye (EYE_M over the ground)
    to its landmark's top (LANDMARK_M of its kind over the ground), judged from the vantage's pad
    edge to the target's, which is where the trees between them stand (the pads themselves are
    clear already)."""

    def __init__(self, H: np.ndarray, grid: Grid, claims: list, k: dict):
        rows = []
        for (ax, az), (bx, bz), kind, ra, rb in claims:
            dx, dz = bx - ax, bz - az
            ln = math.hypot(dx, dz)
            if ln < 1.0 or ln > k["MAX_SIGHT_M"]:
                rows.append(None)
                continue
            eye = float(sample_bilinear(H, grid, np.array([ax]), np.array([az]))[0]) + k["EYE_M"]
            top = float(sample_bilinear(H, grid, np.array([bx]), np.array([bz]))[0]) \
                + k["LANDMARK_M"].get(kind, k["LANDMARK_DEFAULT_M"])
            rows.append((ax, az, dx, dz, ln, eye, top, float(ra) / ln, 1.0 - float(rb) / ln))
        self.rows = rows
        self.clear = float(k["CLEARANCE_M"])

    def blocking(self, x: np.ndarray, z: np.ndarray, ground: np.ndarray, top: np.ndarray, corridor_m: float):
        """(bool [n] of the trees that stand into some line, int [n_claims] of how many each line
        took): a tree blocks a line when its trunk is within `corridor_m` of it between the two
        pads, its top reaches within the clearance (and SIGHT_TREE_SPARE_M) of the ray over it,
        and the ground there is under the ray (where the land itself stands into the line the line
        is the land's to answer, and the tree is left)."""
        hit = np.zeros(x.shape, dtype=bool)
        per = np.zeros(len(self.rows), dtype=np.int64)
        for i, row in enumerate(self.rows):
            if row is None:
                continue
            ax, az, dx, dz, ln, eye, tt, t0, t1 = row
            # a cheap box test first: most lines are nowhere near most trees
            lo_x, hi_x = min(ax, ax + dx) - corridor_m, max(ax, ax + dx) + corridor_m
            lo_z, hi_z = min(az, az + dz) - corridor_m, max(az, az + dz) + corridor_m
            box = (x >= lo_x) & (x <= hi_x) & (z >= lo_z) & (z <= hi_z)
            if not box.any():
                continue
            idx = np.nonzero(box)[0]
            t = ((x[idx] - ax) * dx + (z[idx] - az) * dz) / (ln * ln)
            d = np.hypot(x[idx] - (ax + t * dx), z[idx] - (az + t * dz))
            line = eye + (tt - eye) * t - self.clear - SIGHT_TREE_SPARE_M
            into = (d < corridor_m) & (t > t0) & (t < t1) & (top[idx] > line) & (ground[idx] <= line)
            if into.any():
                fresh = into & ~hit[idx]
                per[i] += int(fresh.sum())
                hit[idx[into]] = True
        return hit, per


def clear_sightlines(buckets: dict, grid: Grid, H: np.ndarray, claims: list, k: dict, table: dict | None = None,
                     corridor_m: float = SIGHT_TREE_CORRIDOR_M) -> dict:
    """Take out of `buckets` (in place) every tree that would stand into an authored sightline:
    the build already cuts the land under a line (geography.honour_sightlines) and keeps rock out
    of its corridor (crags.ceiling_under_lines), and the trees were the last thing between the Hum
    Stone and the mill that is said to see it. `claims` are build_world.sightline_claims, `k` the
    game's sight constants (tools/sightlines.py `constants`). A tree's height is the contact table's
    (tree_contacts.json) times its scale. Returns {"trees": taken, "by_claim": [taken per claim, in
    `claims` order], "by_asset": {asset: taken}}."""
    table = load_table() if table is None else table
    lines = _Lines(H, grid, claims, k)
    out = {"trees": 0, "by_claim": [0] * len(claims), "by_asset": {}}
    if not claims:
        return out
    per_claim = np.zeros(len(claims), dtype=np.int64)
    for key in list(buckets):
        by_asset = buckets[key]
        for asset in list(by_asset):
            if "/trees/" not in asset:
                continue
            rows = by_asset[asset]
            if not len(rows):
                continue
            name = os.path.splitext(os.path.basename(asset))[0]
            height = table[name][1] if name in table else TREE_HEIGHT_DEFAULT_M
            if isinstance(rows, Rows):
                xz = rows.xz()
                scale = rows.column(4, "scale")
            else:
                xz = np.array([(float(r[0]), float(r[2])) for r in rows], dtype=np.float64).reshape(-1, 2)
                scale = np.array([float(r[4]) for r in rows], dtype=np.float64)
            ground = sample_bilinear(H, grid, xz[:, 0], xz[:, 1]).astype(np.float64)
            hit, per = lines.blocking(xz[:, 0], xz[:, 1], ground, ground + height * scale, corridor_m)
            if not hit.any():
                continue
            per_claim += per
            n = int(hit.sum())
            out["trees"] += n
            out["by_asset"][asset] = out["by_asset"].get(asset, 0) + n
            if isinstance(rows, Rows):
                rows.keep(~hit)
                if not len(rows):
                    del by_asset[asset]
                continue
            keep = [r for r, w in zip(rows, hit) if not w]
            if keep:
                by_asset[asset] = keep
            else:
                del by_asset[asset]
    out["by_claim"] = per_claim.tolist()
    return out


## A glade's way to its road, metres wide, where its def does not say (`glade_approach_m`).
GLADE_APPROACH_M = 18.0
## How far a tree's crown reaches out from its trunk, as a share of its height: a glade is open sky,
## so a tree goes if its crown reaches in, not only if its trunk stands in. (Taken by the trunk, the
## w4096j glades round the Windthrow and Tinehold had the giant oaks just outside them roofing
## the ground inside, and poi_sheet's views stood under their crowns.)
GLADE_CROWN_PER_H = 0.4


def glades(pois: list, roads: list) -> list:
    """[(centre_xz, radius_m, road_xz or None, approach_width_m)] for every POI def with `glade_m`: a
    place in the deep wood whose feature must be seen, the trees taken off a disc of that radius
    round it (beyond its pad, which clears only its own ground) and off a way from it to the nearest
    point of the nearest road, so it is seen from the track. `roads` are worldgen.roads.Road."""
    out = []
    for p in pois:
        r = p.get("glade_m")
        if not r:
            continue
        c = np.array([float(p["position"][0]), float(p["position"][1])], dtype=np.float64)
        best, best_d = None, 1e18
        for road in roads:
            pts = np.asarray(road.points, dtype=np.float64)[:, :2] if len(road.points) else None
            if pts is None or len(pts) < 2:
                continue
            a, b = pts[:-1], pts[1:]
            ab = b - a
            t = np.clip(((c - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0.0, 1.0)
            q = a + ab * t[:, None]
            d = np.hypot(*(q - c).T)
            i = int(np.argmin(d))
            if d[i] < best_d:
                best_d, best = float(d[i]), (float(q[i][0]), float(q[i][1]))
        out.append(((float(c[0]), float(c[1])), float(r), best, float(p.get("glade_approach_m", GLADE_APPROACH_M))))
    return out


def clear_glades(buckets: dict, glade_list: list, table: dict | None = None) -> dict:
    """Take out of `buckets` (in place) every tree whose crown reaches into a glade (`glades`): over
    its disc, or over the way from its middle to its road and two metres past the road's middle. A
    crown reaches GLADE_CROWN_PER_H of the tree's height (the contact table's, times its scale) from
    its trunk. Only trees: the ground's low cover, the logs and the rocks stay. Returns
    {"trees": taken, "by_glade": [taken per glade]}."""
    out = {"trees": 0, "by_glade": [0] * len(glade_list)}
    if not glade_list:
        return out
    table = load_table() if table is None else table
    for key in list(buckets):
        by_asset = buckets[key]
        for asset in list(by_asset):
            if "/trees/" not in asset:
                continue
            rows = by_asset[asset]
            if not len(rows):
                continue
            name = os.path.splitext(os.path.basename(asset))[0]
            height = table[name][1] if name in table else TREE_HEIGHT_DEFAULT_M
            if isinstance(rows, Rows):
                xz = rows.xz()
                scale = rows.column(4, "scale")
            else:
                xz = np.array([(float(r[0]), float(r[2])) for r in rows], dtype=np.float64).reshape(-1, 2)
                scale = np.array([float(r[4]) for r in rows], dtype=np.float64)
            crown = height * np.asarray(scale, dtype=np.float64) * GLADE_CROWN_PER_H
            hit = np.zeros(len(xz), dtype=bool)
            for gi, (c, radius, road, width) in enumerate(glade_list):
                c = np.asarray(c, dtype=np.float64)
                inside = np.hypot(xz[:, 0] - c[0], xz[:, 1] - c[1]) - crown < radius
                if road is not None:
                    e = np.asarray(road, dtype=np.float64)
                    seg = e - c
                    length = float(np.hypot(*seg))
                    if length > 1e-6:
                        u = seg / length
                        rel = xz - c
                        along = rel @ u
                        off = np.abs(rel[:, 0] * u[1] - rel[:, 1] * u[0])
                        inside |= (along >= -crown) & (along <= length + 2.0 + crown) & (off - crown < width * 0.5)
                n = int((inside & ~hit).sum())
                out["by_glade"][gi] += n
                hit |= inside
            if not hit.any():
                continue
            out["trees"] += int(hit.sum())
            if isinstance(rows, Rows):
                rows.keep(~hit)
                if not len(rows):
                    del by_asset[asset]
                continue
            keep = [r for r, w in zip(rows, hit) if not w]
            if keep:
                by_asset[asset] = keep
            else:
                del by_asset[asset]
    return out
