#!/usr/bin/env python3
"""Where the roads are signed: a fingerpost at every junction out in the country, and a stone
naming the town or village at every road's way into it.

    python3 tools/world/atlas/signposts.py                  # the tracked world -> signposts.json
    python3 tools/world/atlas/signposts.py --world /tmp/w4096e --out /tmp/signposts.json
    python3 tools/world/atlas/signposts.py --check          # the file matches the tracked world

The user's complaint was that the world does not guide you. A road knows where it goes, since
every road is built between two places (world/road_network.gd). At a fork, though, nothing told a
walker which way was which, and the build stood a signpost only in a town's square, where three
road ends meet.

**A junction** is where two roads part, or where two ends meet out in the country. The built roads
run together for long stretches: the Grandfather Hollow road and the Hazelcombe road share a mile
of the Greatwood. So a junction is not where two lines come close. It is where the set of roads
running together along a road changes: a road joins it or leaves it, within CORUN_M. Those
changes are gathered within JUNCTION_M into one junction, at the point where the roads part.
Road ends meeting at a place that is not a settlement (a bridge, a ford, the Standing Moot) are a
junction too. A junction inside a settlement's pad (and SETTLEMENT_SPARE_M) is the town's own
business and is left out.

**A fingerpost** stands POST_OFF_M from the junction, in the widest angle between the ways out,
and at least POST_CLEAR_M from every road's edge. It stands on the verge, not the carriageway.
Its arms are the ways out, as world/road_network.gd reads them at runtime:
- along each road that passes, both ways, to the place at that road's end;
- two ways to one place keep the nearer;
- two ways leaving along one line keep the nearer place.
Each arm carries the distance along the road, in miles to the nearest quarter
(MILE_M, the Wardens' mile).

**A town stone** stands where a road comes into a settlement: on the traveller's right, as they
arrive, STONE_SIDE_M off the road's centre, at the settlement's pad radius plus STONE_OUT_M. It
faces the road the traveller comes along. Roads that come in together share one stone.

The file (tools/world/atlas/signposts.json) is atlas data for the build: tools/world/worldgen/
roadside.py stands a signpost row at each fingerpost, which world/wayside.gd builds as a
Fingerpost, and a `scenes` entry at each town stone, for the settlements' town_stone scene.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
from worldgen import atlas as ATLAS  # noqa: E402
from worldgen.roads import pad_radius  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GEN = os.path.join(REPO, "game", "world", "generated")
PACK = os.path.join(REPO, "game", "content", "packs", "core")
OUT = os.path.join(HERE, "signposts.json")

STEP_M = 4.0
## two roads closer than this are one way (the built lines of a shared stretch wander by a few m)
CORUN_M = 7.0
## a break in running together shorter than this is no parting
BREAK_M = 60.0
## changes nearer than this are one junction (two posts a stone's throw apart say the same thing)
JUNCTION_M = 75.0
## a junction within a settlement's flat pad and this far beyond it (its outskirts, as the gap
## map counts them) is the town's: its town stones say where you are
SETTLEMENT_SPARE_M = 40.0
## road ends this close together meet
END_MEET_M = 30.0
POST_OFF_M = (7.0, 9.0, 11.0, 13.0)
POST_CLEAR_M = 2.5
## world/road_network.gd's reach, HERE_M, END_M and AIM_M
REACH_M = 30.0
HERE_M = 45.0
END_M = 70.0
AIM_M = 40.0
MILE_M = 1609.344
STONE_OUT_M = 6.0
STONE_SIDE_M = 4.5
STONE_CLEAR_M = 1.5
## ways into one settlement nearer than this share a stone
STONE_SHARE_M = 25.0
## ...when the shared stone stands this near the other road's line too
STONE_PASSED_M = 10.0
## The town stone's model: the Vale's milestone until settlements' town_stone scene, which cuts
## the place's name on its face, replaces it here (one path; test_signposts checks it exists)
TOWN_STONE_SCENE = "res://assets/models/props/hearthvale_milestone_a/hearthvale_milestone_a.glb"


def is_street(rid: str) -> bool:
    return rid.endswith("_street") or rid.endswith("_street_cross")


def resample(pts, step: float = STEP_M) -> np.ndarray:
    pts = np.asarray(pts, dtype=float)
    seg = np.hypot(*(pts[1:] - pts[:-1]).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t = np.arange(0.0, s[-1] + 1e-6, step)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], axis=1)


def load(world: str = GEN, pack: str = PACK) -> dict:
    roads = []
    for r in json.load(open(os.path.join(world, "roads.json"), encoding="utf-8")):
        if is_street(r["id"]):
            continue
        roads.append({"id": r["id"], "pts": resample(r["points"]), "width": float(r.get("width_m", 3.5))})
    built = {e["place_id"]: e for e in json.load(open(os.path.join(world, "pois.json"), encoding="utf-8"))}
    places = []
    defs = json.load(open(os.path.join(pack, "places", "places.json"), encoding="utf-8"))
    # a point of interest is a place a road can end at too (world/road_network.gd)
    defs += json.load(open(os.path.join(pack, "pois", "pois.json"), encoding="utf-8"))
    for p in defs:
        pos = p.get("position")
        if not pos:
            continue
        kind = str(p.get("kind", ""))
        settle = kind in ATLAS.SETTLEMENT_KINDS and ":place/" in p["id"]
        pad = float(built.get(p["id"], {}).get("radius_flat_m", 0.0)) or (pad_radius(p) if settle else 0.0)
        places.append({"id": p["id"], "name": p.get("name", p["id"]), "kind": kind,
                       "at": (float(pos[0]), float(pos[1])), "settlement": settle, "pad": pad})
    return {"roads": roads, "places": places}


# --- junctions -----------------------------------------------------------------------------------

def junctions(m: dict, debug: list | None = None) -> list:
    roads = m["roads"]
    changes = []
    boxes = [(r["pts"][:, 0].min(), r["pts"][:, 0].max(), r["pts"][:, 1].min(), r["pts"][:, 1].max()) for r in roads]
    for i, a in enumerate(roads):
        A = a["pts"]
        near = np.zeros((len(A), len(roads)), dtype=bool)
        for j, b in enumerate(roads):
            if i == j:
                continue
            bx = boxes[j]
            if boxes[i][0] > bx[1] + CORUN_M or bx[0] > boxes[i][1] + CORUN_M or \
               boxes[i][2] > bx[3] + CORUN_M or bx[2] > boxes[i][3] + CORUN_M:
                continue
            B = b["pts"]
            d = np.hypot(A[:, None, 0] - B[None, :, 0], A[:, None, 1] - B[None, :, 1]).min(axis=1)
            near[:, j] = _steady(d < CORUN_M)
        for k in range(1, len(A)):
            diff = np.nonzero(near[k] != near[k - 1])[0]
            for j in diff:
                # where the roads part: the last point they still share
                at = A[k] if near[k, j] else A[k - 1]
                changes.append((float(at[0]), float(at[1]), a["id"], roads[j]["id"]))
    # road ends meeting at a place that is not a settlement
    ends = []
    for r in roads:
        for e in (r["pts"][0], r["pts"][-1]):
            ends.append((float(e[0]), float(e[1]), r["id"]))
    for x, z, rid in ends:
        others = [o for o in ends if o[2] != rid and math.hypot(o[0] - x, o[1] - z) < END_MEET_M]
        for o in others:
            changes.append((x, z, rid, o[2]))
    # gather
    J = []
    for x, z, a, b in changes:
        for j in J:
            if math.hypot(j["x"] - x, j["z"] - z) < JUNCTION_M:
                j["pts"].append((x, z))
                j["roads"].update([a, b])
                break
        else:
            J.append({"x": x, "z": z, "pts": [(x, z)], "roads": {a, b}})
    # and gather again until no two are within JUNCTION_M: a first pass seeds each junction at
    # the first change it meets, and two seeds can sit a few metres apart on one fork
    merged = True
    while merged:
        merged = False
        for a in range(len(J)):
            ca = np.mean(J[a]["pts"], axis=0)
            for b in range(a + 1, len(J)):
                cb = np.mean(J[b]["pts"], axis=0)
                if math.hypot(ca[0] - cb[0], ca[1] - cb[1]) < JUNCTION_M:
                    J[a]["pts"] += J[b]["pts"]
                    J[a]["roads"] |= J[b]["roads"]
                    del J[b]
                    merged = True
                    break
            if merged:
                break
    out = []
    for j in J:
        if debug is not None:
            debug.append(j)
        # the parting itself, not the mean of a cluster that may have drifted along a shared
        # stretch: the member nearest all the others
        pts = np.asarray(j["pts"])
        c = int(np.argmin(np.hypot(pts[:, None, 0] - pts[None, :, 0], pts[:, None, 1] - pts[None, :, 1]).sum(axis=1)))
        x, z = float(pts[c][0]), float(pts[c][1])
        # the town's only if every parting in it is (a fork on the outskirts' edge still gets a post)
        if all(in_settlement(m, px, pz) for px, pz in j["pts"]):
            continue
        out.append({"at": [round(x, 1), round(z, 1)], "roads": sorted(j["roads"])})
    out.sort(key=lambda j: (j["at"][0], j["at"][1]))
    return out


def _steady(mask: np.ndarray) -> np.ndarray:
    """Two roads running together wander apart and back by a few metres: a break in their
    running together shorter than BREAK_M is no parting."""
    out = mask.copy()
    n = int(BREAK_M / STEP_M)
    idx = np.nonzero(mask)[0]
    for a, b in zip(idx[:-1], idx[1:]):
        if 1 < b - a <= n:
            out[a:b] = True
    return out


def in_settlement(m: dict, x: float, z: float) -> bool:
    return any(p["settlement"] and math.hypot(p["at"][0] - x, p["at"][1] - z) < p["pad"] + SETTLEMENT_SPARE_M
               for p in m["places"])


# --- arms ----------------------------------------------------------------------------------------

def place_near(m: dict, p) -> dict | None:
    best, bd = None, END_M
    for pl in m["places"]:
        d = math.hypot(pl["at"][0] - p[0], pl["at"][1] - p[1])
        if d < bd:
            best, bd = pl, d
    return best


def run_m(pts: np.ndarray, k: int, sign: int) -> float:
    if sign > 0:
        return float(np.hypot(*(pts[k + 1:] - pts[k:-1]).T).sum()) if k < len(pts) - 1 else 0.0
    return float(np.hypot(*(pts[1:k + 1] - pts[:k]).T).sum()) if k > 0 else 0.0


def along(pts: np.ndarray, k: int, sign: int, metres: float) -> np.ndarray:
    steps = int(round(metres / STEP_M))
    return pts[max(0, min(len(pts) - 1, k + sign * steps))]


def destinations(m: dict, at, reach: float = REACH_M) -> list:
    """world/road_network.gd's `destinations`, in Python: the ways out from `at`, each
    {dir, place, name, metres, road}, nearest first."""
    found = []
    for r in m["roads"]:
        P = r["pts"]
        d = np.hypot(P[:, 0] - at[0], P[:, 1] - at[1])
        k = int(np.argmin(d))
        if d[k] > reach:
            continue
        for sign in (1, -1):
            end = P[-1] if sign > 0 else P[0]
            if math.hypot(end[0] - at[0], end[1] - at[1]) < HERE_M:
                continue
            pl = place_near(m, end)
            if pl is None:
                continue
            aim = along(P, k, sign, AIM_M)
            wx, wz = aim[0] - at[0], aim[1] - at[1]
            n = math.hypot(wx, wz)
            if n < 1.0:
                continue
            found.append({"dir": (wx / n, wz / n), "place": pl["id"], "name": pl["name"],
                          "metres": run_m(P, k, sign), "road": r["id"]})
    found.sort(key=lambda f: f["metres"])
    out = []
    for f in found:
        if any(o["place"] == f["place"] or (o["dir"][0] * f["dir"][0] + o["dir"][1] * f["dir"][1]) > 0.97 for o in out):
            continue
        out.append(f)
    return out


def miles(metres: float) -> str:
    """The Wardens' mile, to the nearest quarter: 1/4, 1/2, 3/4, 1, 1 1/4 ... as a fingerpost cuts it."""
    q = max(1, int(round(metres / MILE_M * 4.0)))
    whole, part = divmod(q, 4)
    frac = {0: "", 1: "¼", 2: "½", 3: "¾"}[part]
    return ("%d%s" % (whole, frac)) if whole else frac


# --- where things stand --------------------------------------------------------------------------

def road_edge_m(m: dict, x: float, z: float) -> float:
    best = 1e9
    for r in m["roads"]:
        P = r["pts"]
        d = float(np.hypot(P[:, 0] - x, P[:, 1] - z).min()) - r["width"] * 0.5
        best = min(best, d)
    return best


def post_spot(m: dict, j: dict, ways: list):
    """A spot POST_OFF_M from the junction in the widest angle between its ways out, clear of the
    road's edge."""
    x0, z0 = j["at"]
    angles = sorted(math.atan2(w["dir"][1], w["dir"][0]) for w in ways) or [0.0]
    gaps = []
    for i, a in enumerate(angles):
        b = angles[(i + 1) % len(angles)] + (2 * math.pi if i == len(angles) - 1 else 0.0)
        gaps.append((b - a, a + (b - a) / 2.0))
    gaps.sort(reverse=True)
    for _w, mid in gaps:
        for off in POST_OFF_M:
            for twist in (0.0, 0.25, -0.25, 0.5, -0.5):
                a = mid + twist
                x, z = x0 + math.cos(a) * off, z0 + math.sin(a) * off
                # clear of the carriageway, and still in reach of every way the junction has
                if road_edge_m(m, x, z) >= POST_CLEAR_M and len(destinations(m, (x, z))) >= len(ways):
                    return [round(x, 1), round(z, 1)]
    return None


def fingerposts(m: dict) -> list:
    out = []
    for j in junctions(m):
        ways = destinations(m, j["at"])
        if len(ways) < 2:
            continue
        spot = post_spot(m, j, ways)
        if spot is None:
            continue
        arms = destinations(m, spot)
        out.append({"at": spot, "junction": j["at"], "roads": j["roads"],
                    "arms": [{"place": a["place"], "name": a["name"], "metres": round(a["metres"]),
                              "miles": miles(a["metres"]), "road": a["road"]} for a in arms]})
    return out


def town_stones(m: dict) -> list:
    out = []
    for p in m["places"]:
        if not p["settlement"]:
            continue
        cx, cz = p["at"]
        ring = p["pad"] + STONE_OUT_M
        mine = []
        for r in m["roads"]:
            P = r["pts"]
            d = np.hypot(P[:, 0] - cx, P[:, 1] - cz)
            inside = d < ring
            if not inside.any() or inside.all():
                continue
            # each place the road crosses the ring coming in: outside -> inside
            for k in range(1, len(P)):
                if inside[k] != inside[k - 1]:
                    o, i = (k - 1, k) if not inside[k - 1] else (k, k - 1)
                    ox, oz = P[o]
                    ix, iz = P[i]
                    tx, tz = ix - ox, iz - oz
                    n = math.hypot(tx, tz) or 1.0
                    tx, tz = tx / n, tz / n
                    # on the right of someone walking in (+x east, +z south: right of (tx, tz) is (-tz, tx))
                    rx, rz = -tz, tx
                    # off the carriageway, however wide the road coming in
                    for side in (STONE_SIDE_M, STONE_SIDE_M + 1.5, STONE_SIDE_M + 3.0):
                        sx, sz = ox + rx * side, oz + rz * side
                        if road_edge_m(m, sx, sz) >= STONE_CLEAR_M:
                            break
                    else:
                        continue
                    mine.append({"at": [round(sx, 1), round(sz, 1)], "entry": [round(float(ox), 1), round(float(oz), 1)],
                                 "yaw": round(math.degrees(math.atan2(-tx, -tz)), 1), "road": r["id"]})
        # roads that come in together share a stone: one a traveller on this road walks past
        lines = {r["id"]: r["pts"] for r in m["roads"]}
        kept = []
        for s in mine:
            P = lines[s["road"]]
            if any(math.hypot(s["entry"][0] - k["entry"][0], s["entry"][1] - k["entry"][1]) < STONE_SHARE_M
                   and float(np.hypot(P[:, 0] - k["at"][0], P[:, 1] - k["at"][1]).min()) < STONE_PASSED_M for k in kept):
                continue
            kept.append(s)
        for s in kept:
            s.update({"place": p["id"], "name": p["name"]})
            out.append(s)
    return out


def build(world: str = GEN, pack: str = PACK) -> dict:
    m = load(world, pack)
    posts = fingerposts(m)
    stones = town_stones(m)
    return {"_doc": "Where the roads are signed, from tools/world/atlas/signposts.py over the built roads: "
                    "a fingerpost at every junction out in the country (its arms as world/road_network.gd "
                    "reads them, with the distance in Wardens' miles) and a town stone at every road's way "
                    "into a settlement. tools/world/worldgen/roadside.py stands them.",
            "town_stone_scene": TOWN_STONE_SCENE,
            "fingerposts": posts, "town_stones": stones}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", default=GEN)
    ap.add_argument("--pack", default=PACK)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--check", action="store_true", help="say whether the file matches the world, and write nothing")
    args = ap.parse_args()
    data = build(args.world, args.pack)
    if args.check:
        old = json.load(open(args.out, encoding="utf-8")) if os.path.exists(args.out) else {}
        same = old.get("fingerposts") == data["fingerposts"] and old.get("town_stones") == data["town_stones"]
        print("%s: %d fingerposts, %d town stones; %s" % (args.out, len(data["fingerposts"]), len(data["town_stones"]),
                                                        "matches the world" if same else "DIFFERS from the world"))
        return 0 if same else 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    arms = sum(len(p["arms"]) for p in data["fingerposts"])
    print("wrote %s: %d fingerposts (%d arms), %d town stones" % (args.out, len(data["fingerposts"]), arms, len(data["town_stones"])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
