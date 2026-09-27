"""Which of the laid lines stand at all: no rail or hedge left alone in a field, no gate post
without its boundary, and hedges only where a farm would keep them.

Playtest 09-27 (triage 16 and 17). "Random, unconnected fence segments are present in seemingly
random points of the map": a frontage's post-and-rail (roadside.place) runs from one boundary of a
field to the next and was meant to meet that field's own hedge or wall, but most boundaries are not
hedged (hedges.HEDGED_FRACTION, the gateways, the road and slope checks), so a rail ran 15 to 80 m
along a road and met nothing at either end. The gate posts (hedges.place, one at each gateway's
shoulder) were stood on every boundary, hedged or not: of the installed world's 1,994, most stood
alone in grass. And the dry, crag and off-ground sweeps after the lines were laid cut runs into
pieces of three or four.

"The 'hedge' floral walls ... are too abundant and pointless in many cases as they merely cut off
the open world, and clash with the environment in others, like the walk up to Brightwater": 60,219
hedge pieces, lining both sides of most roads, round every parcel of the downs far from any farm, and
beside the walls and rails as a second line. A hedge now stands only as a field's boundary near a
place people farm from (HEDGE_FARM_M past its pad); never along a road (HEDGE_ROAD_CLEAR_M) nor
within HEDGE_APPROACH_M of a road's last HEDGE_APPROACH_REACH_M into a place; never beside a wall
or a rail; and with a gateway every so often along every stretch.

`prune` runs last in the build, after every sweep that takes pieces out, and
tools/world/prune_lines.py runs it over an installed world's cells. Both take the same rules.
"""
from __future__ import annotations

import math
import os

import numpy as np

from .rows import Rows

## each line family's half-length at a stretch of one (a piece's run lies along its own +X), as
## lines.HALF_M; a post is a point
HALF_M = {"drystone_wall_end": 0.45, "drystone_wall": 1.2, "hedge_segment": 1.05, "fence_post_rail": 1.18,
          "gate_post": 0.0}
FAMILY = {"drystone_wall_end": "post", "drystone_wall": "wall", "hedge_segment": "hedge",
          "fence_post_rail": "rail", "gate_post": "post"}
## two pieces are one run where an end of one is this near the other (laid pieces overlap their
## neighbours by hedges.RUN_OVERLAP_M at each end, so their ends are 0.4 m apart)
JOIN_M = 1.0
## a run's open end joins something where another line (any family) or a settlement's pad is this
## near it: a rail stops FRONTAGE_INSET_M short of the boundary it meets, and a field's hedge stops
## 3.5 m past the road's edge
MEET_M = 6.0
SETTLED_MEET_M = 30.0
## the fewest pieces a run that joins nothing at either end may have. A rail is a field's frontage
## only where it meets the field's boundary: of the installed world's 211 rail runs, 103 met nothing
## at either end, from 8 to 60 pieces, and those were the "random" fences. One that meets nothing
## stands only where it is long enough (about 95 m) to read as the road's own fence.
MIN_PIECES = {"rail": 40, "hedge": 6, "wall": 5}
## a gate post (or a wall's end) with no hedge, wall or rail this near has no boundary to stand in
POST_REACH_M = 4.0
## hedges: how far past a place's pad they reach (a farm's fields; the open country past them is
## left open); how far off a road a hedge running along it keeps (one crossing it, a field's
## boundary coming down to the lane, still meets it); and how far off a road's last
## HEDGE_APPROACH_REACH_M into a place no hedge stands at all, so a place is walked up to across
## open ground
HEDGE_FARM_M = 460.0
HEDGE_ROAD_CLEAR_M = 24.0
HEDGE_ROAD_ALONG_DEG = 35.0
HEDGE_APPROACH_M = 75.0
HEDGE_APPROACH_REACH_M = 400.0
## a hedge piece this near a wall or a rail, and within DOUBLE_DEG of its line, doubles it
DOUBLE_M = 6.0
DOUBLE_DEG = 30.0
## a gateway along every straight stretch of hedge: GATE_LEN_M open in every GATE_EVERY_M
GATE_EVERY_M = 34.0
GATE_LEN_M = 8.0
## rounds of taking out the runs left too short, since taking one out can leave its neighbour alone
PASSES = 4
## how finely the roads are walked for the distance to them
ROAD_STEP_M = 4.0


def family_of(asset: str) -> str | None:
    name = os.path.basename(asset)
    for k in HALF_M:                        # (the wall's end before the wall: it is its prefix)
        if "_" + k + "_" in name:
            return FAMILY[k]
    return None


class _Pieces:
    """Every line piece and post in the buckets, as arrays: where it is written (bucket key, asset,
    row), its family, its middle, its run's direction and its half-length."""

    def __init__(self, buckets: dict):
        at, fam, x, z, ux, uz, h = [], [], [], [], [], [], []
        for key, by_asset in buckets.items():
            for asset, rows in by_asset.items():
                f = family_of(asset)
                if f is None or isinstance(rows, Rows) or not rows:
                    continue
                name = os.path.basename(asset)
                half = next(v for k, v in HALF_M.items() if "_" + k + "_" in name)
                for i, r in enumerate(rows):
                    a = math.radians(float(r[3]))
                    at.append((key, asset, i))
                    fam.append(f)
                    x.append(float(r[0]))
                    z.append(float(r[2]))
                    ux.append(math.cos(a))
                    uz.append(-math.sin(a))
                    # its length is its run's stretch where it was laid to its line, else its scale
                    h.append(half * (float(r[8][0]) if len(r) > 8 else float(r[4])))
        self.at = at
        self.fam = np.array(fam, dtype=object)
        self.x, self.z = np.array(x, np.float64), np.array(z, np.float64)
        self.ux, self.uz = np.array(ux, np.float64), np.array(uz, np.float64)
        self.h = np.array(h, np.float64)
        self.alive = np.ones(len(at), dtype=bool)

    def samples(self, sel: np.ndarray, k: int = 5) -> tuple:
        """`k` points along each selected piece: (points [m*k, 2], piece index of each)."""
        idx = np.flatnonzero(sel)
        t = np.linspace(-1.0, 1.0, k)
        px = self.x[idx, None] + self.ux[idx, None] * self.h[idx, None] * t[None, :]
        pz = self.z[idx, None] + self.uz[idx, None] * self.h[idx, None] * t[None, :]
        return np.stack([px.ravel(), pz.ravel()], axis=1), np.repeat(idx, k)

    def ends(self, idx: np.ndarray) -> np.ndarray:
        """The two ends of each piece in `idx`: [2m, 2], every + end then every - end."""
        return np.concatenate([
            np.stack([self.x[idx] + self.ux[idx] * self.h[idx], self.z[idx] + self.uz[idx] * self.h[idx]], 1),
            np.stack([self.x[idx] - self.ux[idx] * self.h[idx], self.z[idx] - self.uz[idx] * self.h[idx]], 1)])


def _road_points(roads: list) -> tuple:
    """Every road walked every ROAD_STEP_M: (points [m, 2], unit tangents [m, 2])."""
    pts, tans = [], []
    for r in roads:
        p = np.asarray(r, dtype=np.float64)[:, :2]
        if p.shape[0] < 2:
            continue
        seg = np.hypot(np.diff(p[:, 0]), np.diff(p[:, 1]))
        cum = np.concatenate([[0.0], np.cumsum(seg)])
        s = np.arange(0.0, float(cum[-1]) + 1e-6, ROAD_STEP_M)
        q = np.stack([np.interp(s, cum, p[:, 0]), np.interp(s, cum, p[:, 1])], axis=1)
        if q.shape[0] < 2:
            continue
        t = np.gradient(q, axis=0)
        pts.append(q)
        tans.append(t / np.maximum(np.hypot(t[:, 0], t[:, 1]), 1e-9)[:, None])
    if not pts:
        return np.zeros((0, 2)), np.zeros((0, 2))
    return np.concatenate(pts), np.concatenate(tans)


def _hash01(a: np.ndarray, salt: int) -> np.ndarray:
    """A stable 0..1 per integer (hedges._hash01's)."""
    h = (a.astype(np.int64) * np.int64(2654435761) + np.int64(salt) * np.int64(40503))
    h ^= h >> np.int64(13)
    h = (h * np.int64(1274126177)) & np.int64(0x7FFFFFFF)
    return (h % np.int64(100003)).astype(np.float64) / 100003.0


def _hedges_out(P: _Pieces, settlements: list, roads: list) -> dict:
    """Marks dead the hedge pieces that stand where no hedge should; returns how many by rule."""
    from scipy.spatial import cKDTree

    got = {"far_from_farms": 0, "along_roads": 0, "on_approaches": 0, "doubling": 0, "gateways": 0}
    hedge = P.alive & (P.fam == "hedge")
    S = np.asarray(settlements, dtype=np.float64).reshape(-1, 3)
    # far from any place people farm from: open country
    d = np.full(P.x.size, np.inf)
    for sx, sz, sr in S:
        d = np.minimum(d, np.hypot(P.x - sx, P.z - sz) - sr)
    out = hedge & (d > HEDGE_FARM_M)
    got["far_from_farms"] = int(out.sum())
    P.alive &= ~out
    hedge = P.alive & (P.fam == "hedge")
    road_pts, road_tan = _road_points(roads)
    idx = np.flatnonzero(hedge)
    if road_pts.shape[0] and idx.size:
        xz = np.stack([P.x[idx], P.z[idx]], axis=1)
        rd, ri = cKDTree(road_pts).query(xz)
        # along the road: near it, and lying with it
        lying = np.abs(P.ux[idx] * road_tan[ri, 0] + P.uz[idx] * road_tan[ri, 1]) \
            >= math.cos(math.radians(HEDGE_ROAD_ALONG_DEG))
        along = (rd < HEDGE_ROAD_CLEAR_M) & lying
        # the road's last stretch into a place: its points within the reach of a pad
        near_place = np.zeros(road_pts.shape[0], dtype=bool)
        for sx, sz, sr in S:
            near_place |= np.hypot(road_pts[:, 0] - sx, road_pts[:, 1] - sz) < sr + HEDGE_APPROACH_REACH_M
        approach = np.zeros(idx.size, dtype=bool)
        if near_place.any():
            ad, _ = cKDTree(road_pts[near_place]).query(xz, distance_upper_bound=HEDGE_APPROACH_M)
            approach = np.isfinite(ad) & ~along
        got["along_roads"] = int(along.sum())
        got["on_approaches"] = int(approach.sum())
        P.alive[idx[along | approach]] = False
        hedge = P.alive & (P.fam == "hedge")
    # beside a wall or a rail, and lying with it
    other = P.alive & ((P.fam == "wall") | (P.fam == "rail"))
    idx = np.flatnonzero(hedge)
    if other.any() and idx.size:
        pts, owner = P.samples(other)
        near = cKDTree(pts).query_ball_point(np.stack([P.x[idx], P.z[idx]], axis=1), DOUBLE_M)
        cos_min = math.cos(math.radians(DOUBLE_DEG))
        dbl = np.array([any(abs(P.ux[i] * P.ux[owner[q]] + P.uz[i] * P.uz[owner[q]]) >= cos_min for q in nb)
                        for i, nb in zip(idx, near)], dtype=bool)
        got["doubling"] = int(dbl.sum())
        P.alive[idx[dbl]] = False
        hedge = P.alive & (P.fam == "hedge")
    # a gateway every GATE_EVERY_M along every straight stretch. A stretch's pieces share its
    # direction and its line, so where each falls along that line, and a phase of the line's own,
    # opens the same gap across all of them.
    idx = np.flatnonzero(hedge)
    if idx.size:
        # the line's direction taken the same way whichever way a piece was laid along it
        yaw = np.degrees(np.arctan2(-P.uz[idx], P.ux[idx])) % 180.0
        ux, uz = np.cos(np.radians(yaw)), -np.sin(np.radians(yaw))
        along = P.x[idx] * ux + P.z[idx] * uz
        across = -P.x[idx] * uz + P.z[idx] * ux
        line = np.floor(yaw / 3.0).astype(np.int64) * 100003 + np.floor(across / 4.0).astype(np.int64)
        f = (along / GATE_EVERY_M + _hash01(line, 1709)) % 1.0
        gap = f < GATE_LEN_M / GATE_EVERY_M
        got["gateways"] = int(gap.sum())
        P.alive[idx[gap]] = False
    return got


def _runs(P: _Pieces, family: str) -> tuple:
    """The alive pieces of `family` joined into runs: (their indices, a run label for each, and a
    boolean per piece end [2m], + ends then - ends, true where the end is open: no other piece of
    the run within JOIN_M of it)."""
    from scipy.spatial import cKDTree

    sel = P.alive & (P.fam == family)
    idx = np.flatnonzero(sel)
    if idx.size == 0:
        return idx, np.zeros(0, np.int64), np.zeros(0, bool)
    pts, owner = P.samples(sel)
    tree = cKDTree(pts)
    ends = P.ends(idx)
    parent = np.arange(P.x.size)

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    near = tree.query_ball_point(ends, JOIN_M)
    me = np.concatenate([idx, idx])
    open_end = np.ones(ends.shape[0], dtype=bool)
    for e, nb in enumerate(near):
        i = int(me[e])
        for q in nb:
            j = int(owner[q])
            if j == i:
                continue
            open_end[e] = False
            ri, rj = find(i), find(j)
            if ri != rj:
                parent[ri] = rj
    label = np.array([find(int(i)) for i in idx], dtype=np.int64)
    return idx, label, open_end


def _stubs_out(P: _Pieces, settlements: list) -> dict:
    """Marks dead every run shorter than its family's MIN_PIECES that joins nothing at any open
    end (another line of any family within MEET_M, or a settlement's pad within SETTLED_MEET_M);
    returns how many pieces by family."""
    from scipy.spatial import cKDTree

    got = {"rail": 0, "hedge": 0, "wall": 0}
    S = np.asarray(settlements, dtype=np.float64).reshape(-1, 3)
    for family, least in MIN_PIECES.items():
        lines = P.alive & (P.fam != "post")
        if not lines.any():
            break
        all_pts, all_owner = P.samples(lines)
        tree = cKDTree(all_pts)
        idx, label, open_end = _runs(P, family)
        if idx.size == 0:
            continue
        ends = P.ends(idx)
        run_of_end = np.concatenate([label, label])
        runs, counts = np.unique(label, return_counts=True)
        short = set(int(r) for r, c in zip(runs, counts) if c < least)
        if not short:
            continue
        joined: set = set()
        for e in np.flatnonzero(open_end):
            r = int(run_of_end[e])
            if r not in short or r in joined:
                continue
            ex, ez = ends[e]
            if S.size and bool((np.hypot(S[:, 0] - ex, S[:, 1] - ez) < S[:, 2] + SETTLED_MEET_M).any()):
                joined.add(r)
                continue
            for q in tree.query_ball_point(ends[e], MEET_M):
                j = int(all_owner[q])
                if P.fam[j] != family or not _same_run(label, idx, j, r):
                    joined.add(r)
                    break
        # a run with no open end closes on itself: a pen, a field walled all round
        closed = {int(r) for r in runs} - {int(run_of_end[e]) for e in np.flatnonzero(open_end)}
        dead = np.array([int(l) in short and int(l) not in joined and int(l) not in closed for l in label])
        got[family] += int(dead.sum())
        P.alive[idx[dead]] = False
    return got


def _same_run(label: np.ndarray, idx: np.ndarray, j: int, run: int) -> bool:
    k = int(np.searchsorted(idx, j))
    return k < idx.size and idx[k] == j and int(label[k]) == run


def _posts_out(P: _Pieces) -> int:
    """Marks dead every gate post (and wall's end) with no hedge, wall or rail within POST_REACH_M."""
    from scipy.spatial import cKDTree

    posts = np.flatnonzero(P.alive & (P.fam == "post"))
    lines = P.alive & (P.fam != "post")
    if posts.size == 0:
        return 0
    if not lines.any():
        P.alive[posts] = False
        return int(posts.size)
    pts, _ = P.samples(lines)
    d, _ = cKDTree(pts).query(np.stack([P.x[posts], P.z[posts]], axis=1))
    lone = d > POST_REACH_M
    P.alive[posts[lone]] = False
    return int(lone.sum())


def prune(buckets: dict, settlements: list, roads: list) -> dict:
    """In place: the hedges thinned to a farm's field boundaries (`_hedges_out`), then every run too
    short that joins nothing and every gate post with no boundary taken out of `buckets`
    ({key: {asset: rows}}).
    `settlements` are [(x, z, pad radius)] of the places people live in, `roads` the road polylines
    [[x, z], ...]. Returns what went, by rule, and the pieces of each family before and after."""
    P = _Pieces(buckets)
    before = {f: int((P.fam == f).sum()) for f in ("hedge", "wall", "rail", "post")}
    got = {"before": before}
    got["hedges"] = _hedges_out(P, list(settlements), roads)
    stubs = {"rail": 0, "hedge": 0, "wall": 0}
    for _ in range(PASSES):
        more = _stubs_out(P, list(settlements))
        for k, v in more.items():
            stubs[k] += v
        if not any(more.values()):
            break
    got["stubs"] = stubs
    got["lone_posts"] = _posts_out(P)
    # and out of the buckets
    dead: dict = {}
    for i in np.flatnonzero(~P.alive):
        key, asset, r = P.at[i]
        dead.setdefault((key, asset), set()).add(r)
    for (key, asset), gone in dead.items():
        rows = buckets[key][asset]
        kept = [row for r, row in enumerate(rows) if r not in gone]
        if kept:
            buckets[key][asset] = kept
        else:
            del buckets[key][asset]
    got["after"] = {f: int(((P.fam == f) & P.alive).sum()) for f in ("hedge", "wall", "rail", "post")}
    got["cells_changed"] = len({k for k, _ in dead})
    return got
