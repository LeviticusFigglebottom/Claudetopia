#!/usr/bin/env python3
"""What a camera at eye height will actually have in its frame, checked before it is taken.

A ground shot passed the plan's test and came out as sky over fog, because its camera stood ten
metres inside the world's east edge and looked out of the world. Its neighbour passed too and came
out as bark and rock: a giant oak 10.8 m off and a cliff ledge 14.5 m off, both nearer than
anything the crown model's view check asked about. These are the checks that would have caught
both. Each one asks about the frame the camera will take, not about a model of the trees.

- **The edge.** The camera and the point it looks at both stand at least EDGE_M inside the world.
- **Near things.** Nothing the world planted stands in front of the lens within NEAR_M: no trunk,
  ledge, boulder or prop (anything NEAR_MIN_R_M round or more), and no crown the lens is level
  with. Each object counts by its real extent (a tree by its trunk's collision
  radius, or by its crown's reach where the lens is level with the crown; anything else by its
  bounds; each times the instance's scale).
- **Trunks.** Trunks within TRUNK_REACH_M fill under FRAME_TRUNK_MAX of the frame's width.
- **Places.** It stands PLACE_CLEAR_M outside a settlement's pad and outskirts, and POI_CLEAR_M
  from any point of interest, whose buildings and dressing the cells do not hold.
- **Depth.** Half the frame sees at least VIEW_DEPTH_MIN_M before the ground or a crown stops it:
  a camera on a slope over a wood looks level into its crowns, and that is a frame of leaves.
- **Ground.** The ground stays under the line of sight for at least SIGHT_MIN_M, or all the way
  to the point looked at if that is nearer.

    tools/capture/frame_check.py [plan.json] [--only label,label]   # print each shot's faults
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_default_plan as DP  # noqa: E402
import make_pois_plan as PP  # noqa: E402

REPO = DP.REPO

EDGE_M = 600.0
NEAR_M = 12.0
## ...counting things at least this far round: a reed or a pebble is not a prop in the frame
NEAR_MIN_R_M = 0.3
## a tree's crown hangs from this fraction of its height to its top; a lens level with it (a
## yew's at eye height, or a giant oak's seen from the slope above) is looking into leaves
CROWN_BASE = 0.3
## a camera stands this far outside a settlement's pad and outskirts, and from a POI's centre
PLACE_CLEAR_M = 12.0
POI_CLEAR_M = 30.0
TRUNK_REACH_M = 60.0
FRAME_TRUNK_MAX = 0.12
SIGHT_MIN_M = 200.0
## Half the frame has to see at least this far: of VIEW_RAYS rays across its width at the lens's
## pitch, the median one runs this far before the ground or a crown stops it. Crowns are counted
## at CROWN_SOLID of their reach, since a crown's edge is leaves and sky. On the frames looked at,
## the two walls of leaves in the Briarwold measured 38 and 70 m, and the good frames 78 m and up.
VIEW_DEPTH_MIN_M = 75.0
VIEW_RAYS = 9
VIEW_CAP_M = 300.0
CROWN_SOLID = 0.7
SIGHT_SPARE_M = 0.3
ASPECT = 16.0 / 9.0


def half_hfov(fov_deg: float) -> float:
    """Half the frame's horizontal angle (radians) for a vertical field of view."""
    return math.atan(math.tan(math.radians(fov_deg) * 0.5) * ASPECT)


class Props:
    """Everything the world planted that a lens can stand against, as discs (x, z, radius, is_tree)."""

    def __init__(self, world: str = "") -> None:
        self.world = world or DP.GEN
        self.cell_m = 256.0
        with open(os.path.join(self.world, "world_manifest.json"), "r", encoding="utf-8") as f:
            self.half = float(json.load(f).get("size_m", 8192.0)) / 2.0
        self._r: dict = {}
        self.cells: dict = {}
        self._things = None

    def things(self) -> list:
        """The places and POIs, as the gap map counts them (a settlement out to its pad and
        outskirts)."""
        if self._things is None:
            sys.path.insert(0, os.path.join(REPO, "tools", "world", "atlas"))
            import gap_map  # noqa: E402
            self._things = gap_map.things(DP.PACK, self.world)
        return self._things

    def _meta(self, asset: str) -> tuple:
        """(trunk radius, horizontal reach, height) of an asset at scale 1, from its meta file."""
        if asset not in self._r:
            trunk, reach, height = 0.5, 0.5, 0.0
            meta = os.path.join(REPO, "game", asset.replace("res://", "", 1))
            meta = os.path.splitext(meta)[0] + ".meta.json"
            try:
                with open(meta, "r", encoding="utf-8") as f:
                    m = json.load(f)
                b = m.get("bounds", {})
                lo, hi = b.get("min", [0, 0, 0]), b.get("max", [0, 0, 0])
                reach = max(abs(float(lo[0])), abs(float(hi[0])), abs(float(lo[2])), abs(float(hi[2])), 0.2)
                height = float(hi[1])
                trunk = float(m.get("collision_params", {}).get("radius", reach))
            except (OSError, ValueError, TypeError, KeyError, IndexError):
                pass
            self._r[asset] = (trunk, reach, height)
        return self._r[asset]

    def disc(self, asset: str, x: float, ground: float, z: float, scale: float = 1.0) -> tuple:
        """(x, z, radius, is_tree, trunk radius, crown radius, crown bottom, crown top): a tree is
        its trunk below and above its crown and as wide as its crown within it; anything else is
        as wide as its bounds."""
        trunk, reach, height = self._meta(asset)
        if "/trees/" in asset:
            top = ground + height * scale
            return (x, z, trunk * scale, True, trunk * scale, reach * scale,
                    ground + height * scale * CROWN_BASE, top)
        return (x, z, reach * scale, False, 0.0, 0.0, 0.0, 0.0)

    def _cell(self, cx: int, cz: int) -> list:
        key = (cx, cz)
        if key not in self.cells:
            out = []
            path = os.path.join(self.world, "cells", "%d_%d.json" % (cx, cz))
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                for asset, rows in data.get("instances", {}).items():
                    # grass and flowers are not things a frame is filled by
                    if "/flora/" in asset and "reed" not in asset:
                        continue
                    for r in rows:
                        scale = float(r[4]) if len(r) > 4 and not isinstance(r[4], str) else 1.0
                        out.append(self.disc(asset, float(r[0]), float(r[1]), float(r[2]), scale))
                # the landmarks and other whole scenes a cell stands up (the Drowned Nave)
                for sc in data.get("scenes", []):
                    pos = sc.get("pos")
                    if pos:
                        out.append(self.disc(sc.get("scene", ""), float(pos[0]), float(pos[1]), float(pos[2])))
            self.cells[key] = out
        return self.cells[key]

    def around(self, x: float, z: float, rings: int = 1):
        cx, cz = int((x + self.half) // self.cell_m), int((z + self.half) // self.cell_m)
        for dx in range(-rings, rings + 1):
            for dz in range(-rings, rings + 1):
                yield from self._cell(cx + dx, cz + dz)


def extent_at(t: tuple, y: float) -> float:
    """How far round a disc is at the height `y`: a tree's crown if `y` is within it."""
    if len(t) > 7 and t[3] and t[6] - 1.0 <= y <= t[7] + 1.0:
        return t[5]
    return t[2]


def _off(x, z, px, pz, ahead):
    return (math.atan2(pz - z, px - x) - ahead + math.pi) % (2.0 * math.pi) - math.pi


def near_in_front(props: Props, cam, look, fov_deg: float, near_m: float = NEAR_M) -> list:
    """(distance to its near side, radius) of each thing within `near_m` in front of the lens."""
    x, z = cam[0], cam[2]
    ahead = math.atan2(look[2] - z, look[0] - x)
    half = half_hfov(fov_deg)
    out = []
    for t in props.around(x, z):
        px, pz = t[:2]
        r = extent_at(t, cam[1])
        d = math.hypot(px - x, pz - z)
        if r < NEAR_MIN_R_M or d - r > near_m:
            continue
        # a lens inside the thing's footprint has it all round (under the Drowned Nave's roof)
        if d <= r or abs(_off(x, z, px, pz, ahead)) - math.asin(r / d) < half:
            out.append((max(d - r, 0.0), r))
    return out


def trunk_fill(props: Props, cam, look, fov_deg: float) -> float:
    """How much of the frame's width the trunks within TRUNK_REACH_M fill (overlaps once)."""
    x, z = cam[0], cam[2]
    ahead = math.atan2(look[2] - z, look[0] - x)
    half = half_hfov(fov_deg)
    spans = []
    for t in props.around(x, z):
        px, pz, _r, tree = t[:4]
        if not tree:
            continue
        # a crown overhead is not a frame of bark; the trunk under it is what stands in the view
        r = t[4] if len(t) > 4 else t[2]
        d = math.hypot(px - x, pz - z)
        if d > TRUNK_REACH_M or d < 0.01:
            continue
        w = math.asin(min(1.0, r / d))
        o = _off(x, z, px, pz, ahead)
        lo, hi = max(o - w, -half), min(o + w, half)
        if hi > lo:
            spans.append((lo, hi))
    spans.sort()
    covered, end = 0.0, -half
    for lo, hi in spans:
        if hi > end:
            covered += hi - max(lo, end)
            end = hi
    return covered / (2.0 * half)


def sight_clear_m(ground, cam, look) -> float:
    """How far along the line of sight the ground stays under it."""
    d = math.hypot(look[0] - cam[0], look[2] - cam[2])
    n = max(int(d / 2.0), 4)
    for k in range(1, n + 1):
        t = k / n
        x, z = cam[0] + (look[0] - cam[0]) * t, cam[2] + (look[2] - cam[2]) * t
        if ground.height(x, z) > cam[1] + (look[1] - cam[1]) * t - SIGHT_SPARE_M:
            return t * d
    return d


def view_depth(ground, props: Props, cam, look, fov_deg: float) -> float:
    """The median distance the rays across the frame's width run before the ground or a crown
    stops them (capped at VIEW_CAP_M)."""
    x, z = cam[0], cam[2]
    ahead = math.atan2(look[2] - z, look[0] - x)
    half = half_hfov(fov_deg)
    far = max(math.hypot(look[0] - x, look[2] - z), 1.0)
    pitch = (look[1] - cam[1]) / far
    trees = [t for t in props.around(x, z, 2) if len(t) > 7 and t[3]]
    runs = []
    for k in range(VIEW_RAYS):
        a = ahead - half + (k + 0.5) * 2.0 * half / VIEW_RAYS
        ux, uz = math.cos(a), math.sin(a)
        # only the crowns this ray passes near
        near = []
        for t in trees:
            along = (t[0] - x) * ux + (t[1] - z) * uz
            if -t[5] < along < VIEW_CAP_M + t[5] and abs((t[0] - x) * uz - (t[1] - z) * ux) < t[5] * CROWN_SOLID:
                near.append(t)
        hit, d = VIEW_CAP_M, 2.0
        while d < VIEW_CAP_M:
            px, pz, py = x + ux * d, z + uz * d, cam[1] + pitch * d
            if ground.height(px, pz) > py or any(
                    t[6] <= py <= t[7] and math.hypot(t[0] - px, t[1] - pz) < t[5] * CROWN_SOLID for t in near):
                hit = d
                break
            d += 2.0
        runs.append(hit)
    runs.sort()
    return runs[len(runs) // 2]


def faults(shot: dict, ground, props: Props, spare: float = 0.0) -> list:
    """What is wrong with a ground shot's frame; [] when nothing is. `spare` tightens every
    limit by that fraction, for a generator that must pass on coarser heights than its own."""
    cam, look, fov = shot["pos"], shot["look_at"], float(shot.get("fov", 60.0))
    out = []
    lim = props.half - EDGE_M * (1.0 + spare)
    for name, p in (("camera", cam), ("look-at", look)):
        if abs(p[0]) > lim or abs(p[2]) > lim:
            out.append("its %s is within %.0f m of the world's edge" % (name, EDGE_M))
    for t in props.things():
        d = math.hypot(t["x"] - cam[0], t["z"] - cam[2])
        if t["r"] > 0.0 and d < t["r"] + PLACE_CLEAR_M * (1.0 + spare):
            out.append("it stands in %s's outskirts" % t["name"])
        elif t["r"] <= 0.0 and d < POI_CLEAR_M * (1.0 + spare):
            out.append("it stands %.0f m from %s" % (d, t["name"]))
    near = near_in_front(props, cam, look, fov, NEAR_M * (1.0 + spare))
    if near:
        d, r = min(near)
        out.append("%d things stand within %.0f m in front of the lens (nearest %.1f m off, %.1f m round)"
                   % (len(near), NEAR_M, d, r))
    fill = trunk_fill(props, cam, look, fov)
    if fill >= FRAME_TRUNK_MAX * (1.0 - spare):
        out.append("trunks fill %.0f%% of the frame" % (fill * 100.0))
    far = math.hypot(look[0] - cam[0], look[2] - cam[2])
    clear = sight_clear_m(ground, cam, look)
    if clear < min(SIGHT_MIN_M * (1.0 + spare), far) - 0.5:
        out.append("the ground cuts the line of sight %.0f m out" % clear)
    if not out:
        depth = view_depth(ground, props, cam, look, fov)
        if depth < VIEW_DEPTH_MIN_M * (1.0 + spare):
            out.append("half the frame is stopped within %.0f m (by the ground or crowns)" % depth)
    return out


def find_ground_camera(x0: float, z0: float, bearing_deg: float, ground, props: Props, height_at,
                       keep, eye: float = 2.2, look_m: float = 520.0, fov: float = 60.0,
                       radius: float = 1000.0, spare: float = 0.25):
    """The nearest spot to (x0, z0), looking as near `bearing_deg` as can be, whose frame has no
    faults: rings out from the spot 20 m at a time, and at each spot the bearing and then turns
    of 30 degrees either way. `keep(x, z)` says whether a spot may be used at all (its region, dry
    land). Returns (cam, look) or None."""
    for r in range(0, int(radius) + 1, 20):
        found = None
        for a in range(0, 360, 15 if r else 360):
            x = x0 + math.cos(math.radians(a)) * r
            z = z0 + math.sin(math.radians(a)) * r
            if not keep(x, z):
                continue
            for turn in (0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180):
                b = math.radians(bearing_deg + turn)
                tx, tz = x + math.cos(b) * look_m, z + math.sin(b) * look_m
                shot = {"pos": [x, height_at(x, z) + eye, z], "look_at": [tx, height_at(tx, tz) + 2.0, tz],
                        "fov": fov}
                if faults(shot, ground, props, spare):
                    continue
                cost = abs(turn)
                if found is None or cost < found[0]:
                    found = (cost, shot)
                break
        if found is not None:
            return found[1]["pos"], found[1]["look_at"]
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("plan", nargs="?", default=os.path.join(REPO, "tools", "capture", "plans", "default.json"))
    ap.add_argument("--only", default="")
    ap.add_argument("--world", default="")
    args = ap.parse_args()
    world = args.world or DP.GEN
    ground, props = PP.Ground(world), Props(world)
    only = [s for s in args.only.split(",") if s]
    with open(args.plan, "r", encoding="utf-8") as f:
        shots = json.load(f)["shots"]
    bad = 0
    for s in shots:
        if only and not any(o in s["label"] for o in only):
            continue
        if not only and "_ground" not in s["label"]:
            continue
        f = faults(s, ground, props)
        bad += bool(f)
        print("%-22s %s" % (s["label"], "; ".join(f) if f else "clear"))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
