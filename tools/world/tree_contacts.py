#!/usr/bin/env python3
"""Write tools/world/tree_contacts.json: where each tree the forge grew meets the ground.

A tree is set down with its pivot (the middle of its trunk's foot) on the ground. On a slope, its
root flare's downhill side stands over air. Playtest 6 (1.webp) had a big tree standing on the
spikes of its roots with its trunk's foot clear of the soil. The world build sinks each tree until
every point of its foot is in the ground (worldgen.trees). The points are the ones this script
reads off the forge's own mesh: the vertices of the whole tree (LOD0, bark and roots) lower than
CONTACT_Y_M of the lowest in each of MAX_POINTS sectors round it (`contacts`), with their heights.

It also names the trees whose roots end in the air even on level ground: a root's outer end
standing ROOT_AIR_M or more over the pivot's plane. The world cannot seat those; they are the
forge's to regrow.

    python3 tools/world/tree_contacts.py            # rewrite the table
    python3 tools/world/tree_contacts.py --check    # exit 1 when the table is stale (a tree was regrown)
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys
import warnings

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TREES = os.path.join(REPO, "game", "assets", "models", "trees")
OUT = os.path.join(HERE, "tree_contacts.json")
## the foot: in each sector, what of the tree's lowest metre is within this of the sector's lowest
CONTACT_Y_M = 0.35
MAX_POINTS = 48
## a root whose outer end stands this far over the pivot's plane ends in the air
ROOT_AIR_M = 0.3
ROOT_ZONE_M = 1.0
## a flare that ends in the air is read over this much of the tree's height (the giant oaks' rims stand
## 0.35 to 1.4 m over the plane, 4.5 to 5.5 m out)
FLARE_ZONE_M = 1.6
## counted only this far out: nearer the trunk, a tree's lowest metre is also its low branches and
## its skirt of leaves (a hawthorn's, a yew's, an apple's), which are meant to stand clear of the ground
ROOT_REACH_M = 3.0


def _vertices(path: str) -> np.ndarray | None:
    import trimesh

    warnings.filterwarnings("ignore")
    sc = trimesh.load(path, force="scene")
    out = []
    for node in sc.graph.nodes_geometry:
        T, g = sc.graph[node]
        low = (node + g).lower()
        if "lod" in low or "card" in low or "leaves" in low or "impostor" in low:
            continue
        out.append(trimesh.transformations.transform_points(sc.geometry[g].vertices, T))
    return np.concatenate(out) if out else None


def _outermost(pts: np.ndarray, sectors: int) -> list:
    r = np.hypot(pts[:, 0], pts[:, 2])
    sec = np.floor((np.arctan2(pts[:, 2], pts[:, 0]) + math.pi) / (2 * math.pi) * sectors).astype(int) % sectors
    out = []
    for k in range(sectors):
        m = np.nonzero(sec == k)[0]
        if m.size:
            i = m[np.argmax(r[m])]
            out.append([round(float(pts[i, 0]), 3), round(float(pts[i, 1]), 3), round(float(pts[i, 2]), 3)])
    return out


def contacts(v: np.ndarray) -> list:
    """[[x, y, z], ...]: the foot, at most MAX_POINTS round it: in each sector, the outermost point of
    the tree lower than CONTACT_Y_M over its pivot's plane. A tree whose foot meets that plane in
    fewer than half of 16 sectors stands on a flare that ends in the air (the Briarwold's giant oaks:
    two root tips under 0.35 m, the rest of the flare 0.4 to 0.9 m over the plane). For those, the foot
    is each sector's lowest points instead, among the tree's lowest FLARE_ZONE_M, within CONTACT_Y_M of the
    sector's lowest."""
    band = v[v[:, 1] < CONTACT_Y_M]
    if band.shape[0]:
        sec = np.floor((np.arctan2(band[:, 2], band[:, 0]) + math.pi) / (2 * math.pi) * 16).astype(int) % 16
        if len(set(sec.tolist())) >= 8:
            return _outermost(band, MAX_POINTS)
    low = v[v[:, 1] < FLARE_ZONE_M]
    if low.shape[0] == 0:
        return []
    sec = np.floor((np.arctan2(low[:, 2], low[:, 0]) + math.pi) / (2 * math.pi) * 16).astype(int) % 16
    keep = np.zeros(low.shape[0], dtype=bool)
    for k in range(16):
        m = sec == k
        if m.any():
            keep |= m & (low[:, 1] < low[m, 1].min() + CONTACT_Y_M)
    return _outermost(low[keep], MAX_POINTS)


def roots_in_air(v: np.ndarray) -> list:
    """[(reach m, height m)]: each of 12 sectors' outermost root end, among the tree's lowest metre,
    that stands ROOT_AIR_M or more over the pivot's plane."""
    root = v[v[:, 1] < ROOT_ZONE_M]
    if root.shape[0] == 0:
        return []
    r = np.hypot(root[:, 0], root[:, 2])
    a = np.arctan2(root[:, 2], root[:, 0])
    sec = np.floor((a + math.pi) / (2 * math.pi) * 12).astype(int) % 12
    out = []
    for k in range(12):
        m = sec == k
        if not m.any():
            continue
        R = float(r[m].max())
        tip = float(root[m & (r > R - 0.3), 1].min())
        if tip >= ROOT_AIR_M and R > ROOT_REACH_M:
            out.append((round(R, 2), round(tip, 2)))
    return out


def table() -> dict:
    out = {}
    for meta_path in sorted(glob.glob(os.path.join(TREES, "*", "*.meta.json"))):
        name = os.path.basename(os.path.dirname(meta_path))
        glb = os.path.join(TREES, name, name + ".glb")
        if not os.path.exists(glb):
            continue
        meta = json.load(open(meta_path))
        v = _vertices(glb)
        if v is None:
            continue
        out[name] = {"hash": meta.get("hash", ""), "height_m": round(float(meta.get("bounds", {}).get("height", 5.0)), 3),
                     "contacts": contacts(v), "roots_in_air": roots_in_air(v)}
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        have = json.load(open(OUT)).get("trees", {}) if os.path.exists(OUT) else {}
        stale = []
        for meta_path in sorted(glob.glob(os.path.join(TREES, "*", "*.meta.json"))):
            name = os.path.basename(os.path.dirname(meta_path))
            if not os.path.exists(os.path.join(TREES, name, name + ".glb")):
                continue
            if have.get(name, {}).get("hash") != json.load(open(meta_path)).get("hash", ""):
                stale.append(name)
        if stale:
            print("tree_contacts.json is stale for: %s (python3 tools/world/tree_contacts.py)" % ", ".join(stale))
            return 1
        return 0
    t = table()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"_doc": "Written by tools/world/tree_contacts.py from the forge's tree meshes: each tree's "
                           "foot (tree_contacts.contacts) and its roots that end in the air.",
                   "trees": t}, f, separators=(",", ":"))
        f.write("\n")
    air = {k: v["roots_in_air"] for k, v in t.items() if v["roots_in_air"]}
    print("%d trees -> %s; roots ending in the air: %s" % (len(t), OUT, json.dumps(air) if air else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
