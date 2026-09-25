#!/usr/bin/env python3
"""House and shop interiors for Wickmere, built from who lives there.

A house is not a box: it is a trade, a household and a set of habits that decide how many
rooms there are, what is in them, and where the wear shows. The recipe says who lives
here; this decides the plan, then dresses it the way a person would: the big things against
the walls facing into the room, grouped by what they are for, with a clear way from every
door to every other door, and to every bed, chest and fire.

    tools/interiors/house_forge.py recipes/houses/osric_smithy.json --out game/assets/models/interior

Output per recipe:
    <name>/<name>.glb        walls, floors, ceilings (one solid, openings cut exactly)
    <name>/<name>_timber.glb joists, plates, door and window frames, the stair, rails, the front door
    <name>/<name>_col.glb    collision: the shell, the stair's ramp, the rails, the front door leaf and
                             the window glazing; never decimated, so a doorway is as wide as it is drawn
    <name>/<name>.meta.json  rooms, doors (with their clear zones), windows, stairs, floors, lights,
                             prop placements (each with the asset it draws and the box it collides as)

The rules the dressing keeps, and `check()` measures (the Godot tests measure them again against
the built colliders):
  * the plan is one connected house: every room has a door to a room already reachable, and an
    upper storey is reached by a stair that runs along a wall and lands on a landing;
  * nothing stands within a door's clear zone: the opening plus a hand either side, a metre deep on
    both faces of the wall (it also covers the swing of a leaf);
  * nothing stands on the stair, in front of its foot, or where it arrives upstairs;
  * furniture stands on the floor with its back to a wall and its front into the room, or on a
    surface it belongs on; no two pieces of furniture overlap, and nothing crosses a wall;
  * a 0.9 m wide way stays open from every door to every other door, the stair, and the front of
    every container, bed and hearth.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import sys

import numpy as np
import trimesh
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROPS_DIR = os.path.join(ROOT, "game", "assets", "models", "props")
PROP_LIBRARY_GD = os.path.join(ROOT, "game", "world", "interiors", "prop_library.gd")
HOUSE_INTERIOR_GD = os.path.join(ROOT, "game", "world", "interiors", "house_interior.gd")

# What a trade needs, in the order it wants it from the door.
TRADE_PLANS = {
    "smith": {"rooms": ["workshop", "hearth_room", "store", "bed"], "workshop_area": 26, "noise": "loud",
              "fixtures": {"workshop": ["forge", "anvil", "quench_trough", "bellows", "tool_rack", "coal_heap"],
                           "store": ["iron_stock", "crate", "barrel"]},
              "wear": {"workshop": 0.9, "hearth_room": 0.4}},
    "baker": {"rooms": ["bakehouse", "shop_front", "hearth_room", "bed"], "workshop_area": 22, "noise": "quiet",
              "fixtures": {"bakehouse": ["bread_oven", "kneading_table", "flour_sacks", "peel_rack"],
                           "shop_front": ["counter", "bread_shelf"]},
              "wear": {"bakehouse": 0.8}},
    "miller": {"rooms": ["mill_floor", "meal_floor", "hearth_room", "bed"], "workshop_area": 30, "noise": "loud",
               "fixtures": {"mill_floor": ["millstone", "hopper", "sack_hoist", "gear_pit"],
                            "meal_floor": ["flour_sacks", "scales", "ledger_desk"]},
               "wear": {"mill_floor": 0.85}},
    "brewer": {"rooms": ["brewhouse", "cellar", "hearth_room", "bed"], "workshop_area": 24, "noise": "quiet",
               "fixtures": {"brewhouse": ["mash_tun", "copper", "cooling_trays", "hop_sacks"],
                            "cellar": ["barrel_rack", "barrel", "tap_bench"]},
               "wear": {"brewhouse": 0.7, "cellar": 0.5}},
    "alchemist": {"rooms": ["stillroom", "shop_front", "hearth_room", "bed"], "workshop_area": 18, "noise": "quiet",
                  "fixtures": {"stillroom": ["mortar_bench", "alembic", "drying_rack", "ingredient_shelf"],
                               "shop_front": ["counter", "bottle_shelf"]},
                  "wear": {"stillroom": 0.6}},
    "innkeeper": {"rooms": ["tap_room", "kitchen", "cellar", "guest_room", "bed"], "workshop_area": 40, "noise": "loud",
                  "fixtures": {"tap_room": ["hearth", "bar", "long_table", "bench", "bench", "board", "table", "stool", "stool", "barrel"],
                               "kitchen": ["cook_hearth", "prep_table", "pot_rack"],
                               "cellar": ["barrel_rack", "barrel"],
                               "guest_room": ["bed", "chest", "washstand"]},
                  "wear": {"tap_room": 0.95, "kitchen": 0.8}},
    "farmer": {"rooms": ["hearth_room", "byre", "store", "bed"], "workshop_area": 20, "noise": "quiet",
               "fixtures": {"byre": ["stall", "hay_pile", "yoke", "pitchfork"],
                            "store": ["grain_bin", "root_crate", "seed_sacks"]},
               "wear": {"byre": 0.8}},
    "steward": {"rooms": ["study", "hall", "hearth_room", "bed"], "workshop_area": 16, "noise": "quiet",
                "fixtures": {"study": ["writing_desk", "chair", "deed_chest", "shelf", "strongbox"],
                             "hall": ["long_table", "chair", "chair", "sideboard"]},
                "wear": {"study": 0.3}},
    "fisher": {"rooms": ["net_room", "hearth_room", "bed"], "workshop_area": 18, "noise": "quiet",
               "fixtures": {"net_room": ["net_rack", "drying_line", "crate", "oar_rack", "tar_pot"]},
               "wear": {"net_room": 0.7}},
    "warden": {"rooms": ["muster_room", "hearth_room", "store", "bed"], "workshop_area": 22, "noise": "quiet",
               "fixtures": {"muster_room": ["weapon_rack", "roll_desk", "stool", "map_board", "bench"],
                            "store": ["crate", "barrel", "chest"]},
               "wear": {"muster_room": 0.5}},
    "none": {"rooms": ["hearth_room", "bed"], "workshop_area": 0, "noise": "quiet", "fixtures": {}, "wear": {}},
}

# Wealth sets how much room, how good the materials, and how much is on the walls.
WEALTH = {
    0: {"room_scale": 0.78, "storeys": 1, "floor": "beaten_earth", "walls": "cob", "windows": 1, "clutter": 0.55, "comfort": 0.15},
    1: {"room_scale": 0.92, "storeys": 1, "floor": "board", "walls": "cob", "windows": 2, "clutter": 0.75, "comfort": 0.35},
    2: {"room_scale": 1.0, "storeys": 2, "floor": "board", "walls": "timber_frame", "windows": 3, "clutter": 0.9, "comfort": 0.55},
    3: {"room_scale": 1.15, "storeys": 2, "floor": "board", "walls": "stone", "windows": 4, "clutter": 0.8, "comfort": 0.8},
    4: {"room_scale": 1.3, "storeys": 2, "floor": "flag", "walls": "stone", "windows": 6, "clutter": 0.7, "comfort": 1.0},
}

# Base footprint for each room kind, in metres, before wealth and household scaling.
ROOM_SIZE = {
    "hearth_room": (5.0, 4.5), "bed": (3.6, 3.2), "store": (2.8, 2.6), "workshop": (5.5, 4.8),
    "bakehouse": (4.8, 4.2), "shop_front": (4.0, 3.2), "mill_floor": (6.0, 5.5), "meal_floor": (5.0, 4.5),
    "brewhouse": (5.0, 4.5), "cellar": (4.0, 3.6), "stillroom": (4.2, 3.6), "tap_room": (7.5, 6.0),
    "kitchen": (4.2, 3.8), "guest_room": (3.4, 3.0), "byre": (5.5, 4.0), "study": (3.8, 3.4),
    "hall": (6.0, 4.5), "net_room": (4.5, 3.8), "muster_room": (5.0, 4.5), "landing": (2.4, 2.4),
}
UPSTAIRS_KINDS = ("bed", "guest_room", "study")
MIN_SIZE = {"hearth_room": (4.4, 4.0), "kitchen": (4.0, 3.6), "tap_room": (6.5, 5.5)}
# Where the stair goes, in order of preference: a room people pass through, never a bedroom.
STAIR_ROOMS = ("hall", "hearth_room", "tap_room", "shop_front", "kitchen", "muster_room", "workshop",
               "bakehouse", "brewhouse", "net_room", "stillroom", "meal_floor", "byre")

WALL_T = 0.28
STOREY_H = 2.75          # floor to the underside of the ceiling
SLAB = 0.2               # a ceiling, which is the floor of the storey above
LEVEL = STOREY_H + SLAB  # storey to storey
DOOR_W, DOOR_H = 0.95, 2.05
WINDOW_W, WINDOW_H, WINDOW_SILL = 0.85, 1.05, 0.95
# A door's clear zone: the opening and this much either side of it, CLEAR deep on both faces.
DOOR_MARGIN = 0.15
CLEAR = 1.0
# A door stands at least this far from the end of the wall it is in.
DOOR_END = 0.3
# The way through a house is PATH wide: a body of radius PATH/2 fits it everywhere.
PATH = 0.9
# The stair: a straight flight along a wall, RISERS risers, each GOING deep.
RISERS = 16
GOING = 0.24
STAIR_W = 1.0
RUN = (RISERS - 1) * GOING + GOING      # from the ramp's toe to the landing's edge
RISE = LEVEL / RISERS
# Where the stairwell opens. A body on the flight stands about 0.09 m over the ramp (its capsule's
# foot sphere on the slope), and its head sphere must pass the well's edge with 0.15 m to spare:
# at 1.0 m (the plain 2 m headroom rule) the player's head met the edge and it stopped a third of
# the way up every stair.
WELL_FROM = 0.7
ARRIVE = 1.25            # floor beyond the top step
STRIP = 1.25             # landing floor beside the stairwell
FOOT = CLEAR             # clear floor before the first step
# The dressing's grid, and the gap a piece of furniture keeps from a wall and from its neighbour.
RES = 0.05
WALL_GAP = 0.03
GAP = 0.03
# A thing lower than this, or smaller than this across, is clutter: it is walked through, it has
# no collider, and it is never in anybody's way.
CLUTTER_H = 0.3
CLUTTER_W = 0.3

# ---------------------------------------------------------------------------------------
# The props: the same library the game resolves from, measured.
# ---------------------------------------------------------------------------------------

REGIONS = ["hearthvale", "brightwater", "sedgemire", "briarwold", "skerrow", "cinderlea"]
REGION_BY_CULTURE = {"vale": "hearthvale", "lakefolk": "brightwater", "reedfolk": "sedgemire",
                     "woodfolk": "briarwold", "clans": "skerrow", "pilgrims": "cinderlea"}


def _gd_pairs(path: str, start: str) -> dict:
    """`"a": "b"` pairs out of a GDScript dictionary constant, so the stand-ins have one home."""
    text = open(path).read()
    i = text.index(start)
    j = text.index("\n}", i)
    return dict(re.findall(r'"(\w+)"\s*:\s*"(\w+)"', text[i:j]))


def _placeholder_sizes(path: str) -> tuple[dict, tuple]:
    """HouseInterior._placeholder_size, read from the script: the box drawn for an unbuilt prop."""
    text = open(path).read()
    i = text.index("static func _placeholder_size")
    j = text.index("\n\n", i)
    sizes, default = {}, (0.35, 0.35, 0.35)
    for names, x, y, z in re.findall(r'^\s*((?:"\w+",?\s*)+):\s*return Vector3\(([\d.]+), ([\d.]+), ([\d.]+)\)',
                                     text[i:j], re.M):
        for n in re.findall(r'"(\w+)"', names):
            sizes[n] = (float(x), float(y), float(z))
    m = re.search(r'_:\s*return Vector3\(([\d.]+), ([\d.]+), ([\d.]+)\)', text[i:j])
    if m:
        default = tuple(float(v) for v in m.groups())
    return sizes, default


class Props:
    """PropLibrary.resolve, in Python, with every candidate's measured bounds. The forge writes the
    exact asset into each placement, so what is drawn is what was measured and laid out."""

    def __init__(self, root: str = PROPS_DIR):
        self.index: dict[str, dict[str, list[str]]] = {}
        self.bounds: dict[str, tuple] = {}
        self.stand_in = _gd_pairs(PROP_LIBRARY_GD, "const STAND_IN")
        self.placeholder, self.default_size = _placeholder_sizes(HOUSE_INTERIOR_GD)
        for folder in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            glb = os.path.join(root, folder, folder + ".glb")
            meta = os.path.join(root, folder, folder + ".meta.json")
            if not os.path.exists(glb) or not os.path.exists(meta):
                continue
            b = json.load(open(meta)).get("bounds", {})
            if "min" not in b:
                continue
            region, kind = "", folder
            for r in REGIONS:
                if folder.startswith(r + "_"):
                    region, kind = r, folder[len(r) + 1:]
                    break
            parts = kind.split("_")
            if len(parts) > 1 and len(parts[-1]) == 1:
                kind = "_".join(parts[:-1])
            path = "res://assets/models/props/%s/%s.glb" % (folder, folder)
            self.index.setdefault(kind, {}).setdefault(region, []).append(path)
            self.bounds[path] = (tuple(b["min"]), tuple(b["max"]))

    def resolve(self, kind: str, region: str, rng: np.random.Generator) -> tuple[str, tuple]:
        """(asset path, ((minx, miny, minz), (maxx, maxy, maxz))) for a kind in a region. A kind
        nothing answers for keeps its own name as the path, and the placeholder's size, which is
        exactly the labelled box the game draws for it."""
        for candidate in (kind, self.stand_in.get(kind, "")):
            by_region = self.index.get(candidate)
            if not candidate or not by_region:
                continue
            for key in (region, ""):
                if by_region.get(key):
                    path = by_region[key][int(rng.integers(0, len(by_region[key])))]
                    return path, self.bounds[path]
            key = sorted(by_region)[0]
            path = by_region[key][int(rng.integers(0, len(by_region[key])))]
            return path, self.bounds[path]
        sx, sy, sz = self.placeholder.get(kind, self.default_size)
        return (f"res://assets/models/props/{kind}/{kind}.glb",
                ((-sx * 0.5, 0.0, -sz * 0.5), (sx * 0.5, sy, sz * 0.5)))


# ---------------------------------------------------------------------------------------
# The plan: rooms packed wall to wall, each with a door to one already reachable.
# ---------------------------------------------------------------------------------------

def rect_of(r: dict) -> tuple:
    return (r["x"], r["z"], r["x"] + r["w"], r["z"] + r["d"])


def overlap(a, b, eps: float = 1e-6) -> bool:
    return a[0] < b[2] - eps and b[0] < a[2] - eps and a[1] < b[3] - eps and b[1] < a[3] - eps


def grow(a, m: float):
    return (a[0] - m, a[1] - m, a[2] + m, a[3] + m)


def wanted_rooms(recipe: dict, rng: np.random.Generator) -> list[dict]:
    trade = TRADE_PLANS.get(recipe.get("trade", "none"), TRADE_PLANS["none"])
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    household = int(recipe.get("household", 2))
    wanted = list(trade["rooms"]) + list(recipe.get("extra_rooms", []))
    if household > 3 and "bed" in wanted:
        wanted.insert(wanted.index("bed") + 1, "bed")
    rooms, seen = [], {}
    for kind in wanted:
        base = ROOM_SIZE.get(kind, (4.0, 3.6))
        w = base[0] * wealth["room_scale"] * rng.uniform(0.94, 1.08)
        d = base[1] * wealth["room_scale"] * rng.uniform(0.94, 1.08)
        if kind == "bed" and household > 4:
            w *= 1.15
        # A room with a fire in it has to hold the fire, a table and the way round them.
        if kind in MIN_SIZE:
            w, d = max(w, MIN_SIZE[kind][0]), max(d, MIN_SIZE[kind][1])
        seen[kind] = seen.get(kind, 0) + 1
        rid = kind if seen[kind] == 1 else f"{kind}_{seen[kind]}"
        rooms.append({"id": rid, "kind": kind, "w": round(w, 2), "d": round(d, 2), "storey": 0,
                      "wear": float(trade["wear"].get(kind, 0.25))})
    upstairs = [r for r in rooms if r["kind"] in UPSTAIRS_KINDS]
    if wealth["storeys"] > 1 and len(rooms) > 2 and upstairs and len(upstairs) < len(rooms):
        for r in upstairs:
            r["storey"] = 1
    return rooms


def attach(rooms: list[dict], placed: list[dict], new: dict, rng, ground_rect=None,
           sides_of=None, blocked: dict | None = None, frontage: float | None = None) -> dict | None:
    """Stand `new` against one of `placed`, sharing enough wall for a door, touching nothing else,
    and put the door in. Returns the door, or None when nowhere will take the room. `blocked` is
    floor, per room id, that no door's clear zone may cover (a stair and the floor before it)."""
    best, best_score = None, 1e18
    need = DOOR_W + 2.0 * DOOR_END
    for p in placed:
        for side in (sides_of(p) if sides_of else ("E", "S", "W", "N")):
            if side in ("E", "W"):
                x = p["x"] + p["w"] + WALL_T if side == "E" else p["x"] - WALL_T - new["w"]
                options = [(x, p["z"]), (x, p["z"] + p["d"] - new["d"]), (x, p["z"] + (p["d"] - new["d"]) * 0.5)]
            else:
                z = p["z"] + p["d"] + WALL_T if side == "S" else p["z"] - WALL_T - new["d"]
                options = [(p["x"], z), (p["x"] + p["w"] - new["w"], z), (p["x"] + (p["w"] - new["w"]) * 0.5, z)]
            for x, z in options:
                rect = (x, z, x + new["w"], z + new["d"])
                if new["storey"] == 0 and z < -1e-6:
                    continue        # nothing stands in front of the front wall
                if any(overlap(grow(rect, WALL_T * 0.98), rect_of(o)) for o in placed):
                    continue
                if side in ("E", "W"):
                    lo, hi = max(z, p["z"]), min(z + new["d"], p["z"] + p["d"])
                else:
                    lo, hi = max(x, p["x"]), min(x + new["w"], p["x"] + p["w"])
                if hi - lo < need:
                    continue
                trial = dict(new, x=x, z=z)
                door = door_between(p, trial, side, lo, hi, rng, blocked or {})
                if door is None:
                    continue
                xs = [o["x"] for o in placed] + [x]
                zs = [o["z"] for o in placed] + [z]
                xe = [o["x"] + o["w"] for o in placed] + [x + new["w"]]
                ze = [o["z"] + o["d"] for o in placed] + [z + new["d"]]
                bw, bd = max(xe) - min(xs), max(ze) - min(zs)
                score = bw * bd + 1.5 * abs(math.log(max(bw, bd) / max(min(bw, bd), 0.1)))
                # The street sees the ground floor (Building.footprint_of builds the outside from
                # it): keep the frontage the recipe allows, as the old row plan did, so a village's
                # houses keep the plots they were laid out on.
                if new["storey"] == 0 and frontage is not None:
                    score += 25.0 * max(0.0, bw - frontage) + 6.0 * max(0.0, bd - frontage * 1.25)
                # Rooms open off the house's hubs, not through one another's bedrooms.
                score += 9.0 * p.get("depth", 0)
                if ground_rect is not None:
                    gx0, gz0, gx1, gz1 = ground_rect
                    ox = max(0.0, gx0 - x) + max(0.0, x + new["w"] - gx1)
                    oz = max(0.0, gz0 - z) + max(0.0, z + new["d"] - gz1)
                    score += 6.0 * (ox * new["d"] + oz * new["w"])
                score += rng.uniform(0.0, 1.2)
                if score < best_score:
                    best_score = score
                    best = {"parent": p, "x": x, "z": z, "door": door}
    if best is None:
        return None
    new["x"], new["z"] = best["x"], best["z"]
    new["depth"] = best["parent"].get("depth", 0) + 1
    return best["door"]


def door_between(a: dict, b: dict, side: str, lo: float, hi: float, rng, blocked: dict) -> dict | None:
    """A door in the wall `b` shares with `a` (`side` is the side of `a` it is on), near a corner
    of both rooms when it can be, so the rest of each wall stays whole for furniture; never where
    its clear zone would cover floor `blocked` keeps for something else. None if nowhere will do."""
    first, last = lo + DOOR_END + DOOR_W * 0.5, hi - DOOR_END - DOOR_W * 0.5
    if side in ("E", "W"):
        ends = (a["z"], b["z"]), (a["z"] + a["d"], b["z"] + b["d"])
    else:
        ends = (a["x"], b["x"]), (a["x"] + a["w"], b["x"] + b["w"])
    cost_first = abs(lo - ends[0][0]) + abs(lo - ends[0][1])
    cost_last = abs(ends[1][0] - hi) + abs(ends[1][1] - hi)
    lean = rng.uniform(-0.05, 0.05)
    options = sorted(np.arange(first, last + 1e-6, 0.1).tolist() + [last],
                     key=lambda pos: (pos - first) * (1.0 if cost_first + lean < cost_last else -1.0))
    y0 = a["floor_y"]
    for pos in options:
        if side == "E":
            at, normal = (a["x"] + a["w"] + WALL_T * 0.5, y0, pos), "x"
        elif side == "W":
            at, normal = (a["x"] - WALL_T * 0.5, y0, pos), "x"
        elif side == "S":
            at, normal = (pos, y0, a["z"] + a["d"] + WALL_T * 0.5), "z"
        else:
            at, normal = (pos, y0, a["z"] - WALL_T * 0.5), "z"
        door = {"between": [a["id"], b["id"]], "at": [round(v, 3) for v in at], "axis": normal,
                "yaw": 90.0 if normal == "x" else 0.0, "kind": "internal", "width": DOOR_W}
        clash = False
        for room in (a, b):
            for zn in door_zones(room, [door]):
                if any(overlap(zn, bl) for bl in blocked.get(room["id"], [])):
                    clash = True
        if not clash:
            return door
    return None


def plan(recipe: dict, rng: np.random.Generator, variant: int = 0) -> tuple[list[dict], list[dict], dict | None]:
    """Rooms, doors and the stair. Tries seeded variations until the plan is whole: every room
    reachable, and a stair that fits against a wall clear of every door."""
    base = wanted_rooms(recipe, rng)
    for attempt in range(60):
        sub = np.random.default_rng(int(recipe.get("seed", 1)) * 1000 + variant * 7919 + attempt)
        rooms = [dict(r) for r in base]
        ground = [r for r in rooms if r["storey"] == 0]
        upper = [r for r in rooms if r["storey"] == 1]
        stair_room = None
        if upper:
            # The biggest room people pass through, and the hearth room only when nothing else
            # will do; a stair there gets the room made deeper for it.
            cands = [r for r in ground if r["kind"] in STAIR_ROOMS]
            cands.sort(key=lambda r: (r["kind"] == "hearth_room", -r["w"] * r["d"]))
            stair_room = cands[0] if cands and cands[0]["w"] * cands[0]["d"] >= 15.0 else \
                next((r for r in ground if r["kind"] == "hearth_room"), ground[0])
            if stair_room["kind"] in ("hearth_room", "kitchen") or stair_room["w"] * stair_room["d"] < 18.0:
                stair_room["d"] = round(stair_room["d"] + STAIR_W + 0.2, 2)
            # A flight and the floor before it want a wall this long.
            need = RUN + FOOT + 0.1
            if max(stair_room["w"], stair_room["d"]) < need:
                if stair_room["w"] >= stair_room["d"]:
                    stair_room["w"] = round(need + 0.1, 2)
                else:
                    stair_room["d"] = round(need + 0.1, 2)
        for r in ground:
            r["floor_y"] = 0.0
        for r in upper:
            r["floor_y"] = round(LEVEL, 3)
        frontage = float(recipe.get("width_limit", 11.0)) * WEALTH[int(recipe.get("wealth", 1))]["room_scale"]
        ground[0]["x"], ground[0]["z"], ground[0]["depth"] = 0.0, 0.0, 0
        doors = [front_door(ground[0], sub)]
        placed = [ground[0]]
        blocked: dict[str, list] = {}
        stair = None
        ok = True
        for r in [None] + ground[1:]:
            if r is not None:
                door = attach(rooms, placed, r, sub, blocked=blocked, frontage=frontage)
                if door is None:
                    ok = False
                    break
                doors.append(door)
                placed.append(r)
            # The stair goes in as soon as its room does, so every door after it keeps clear of it.
            if stair_room is not None and stair is None and stair_room in placed:
                stair = place_stair(stair_room, placed, doors, sub)
                if stair is None:
                    ok = False
                    break
                blocked[stair_room["id"]] = [stair_rect(stair, -FOOT, RUN + 0.05, 0.0, STAIR_W + 0.1)]
        if not ok:
            continue
        if upper:
            landing = landing_for(stair)
            gx0 = min(r["x"] for r in ground)
            gz0 = min(r["z"] for r in ground)
            gx1 = max(r["x"] + r["w"] for r in ground)
            gz1 = max(r["z"] + r["d"] for r in ground)
            uplaced = [landing]
            ublocked = {"landing": [stair_rect(stair, WELL_FROM - 0.3, RUN + 0.05, 0.0, STAIR_W + 0.15)]}
            for r in upper:
                door = attach(rooms, uplaced, r, sub, ground_rect=(gx0, gz0, gx1, gz1), blocked=ublocked,
                              sides_of=lambda p: stair["landing_sides"] if p is landing else ("E", "S", "W", "N"))
                if door is None:
                    ok = False
                    break
                doors.append(door)
                uplaced.append(r)
            if not ok:
                continue
            rooms.append(landing)
        # A later room may have closed off the side the stair was put against as an outside wall;
        # it was checked clear of that room's door when the door went in.
        for r in rooms:
            r["centre"] = [round(r["x"] + r["w"] * 0.5, 2), r["floor_y"], round(r["z"] + r["d"] * 0.5, 2)]
            r.pop("depth", None)
            r["x"], r["z"] = round(r["x"], 3), round(r["z"], 3)
        return rooms, doors, stair
    raise SystemExit("%s: no plan holds together in 60 tries" % recipe.get("id", "?"))


def front_door(room: dict, rng) -> dict:
    lo, hi = DOOR_END + DOOR_W * 0.5, room["w"] - DOOR_END - DOOR_W * 0.5
    # A third of the way along, or two thirds: a door dead centre leaves no wall either side of
    # the fire to put a settle on.
    t = float(rng.choice([0.33, 0.5, 0.67]))
    x = room["x"] + float(np.clip(room["w"] * t, lo, hi))
    return {"between": ["outside", room["id"]], "at": [round(x, 3), 0.0, round(-WALL_T * 0.5, 3)],
            "axis": "z", "yaw": 0.0, "kind": "front", "width": DOOR_W}


def door_zones(room: dict, doors: list[dict]) -> list[tuple]:
    """Each door's clear zone inside `room`, as a rect in the house's plan."""
    out = []
    half = DOOR_W * 0.5 + DOOR_MARGIN
    for d in doors:
        if room["id"] not in d["between"]:
            continue
        x, _, z = d["at"]
        if d["axis"] == "x":
            face_w, face_e = room["x"], room["x"] + room["w"]
            if abs(x - face_w) < abs(x - face_e):
                out.append((face_w, z - half, face_w + CLEAR, z + half))
            else:
                out.append((face_e - CLEAR, z - half, face_e, z + half))
        else:
            face_n, face_s = room["z"], room["z"] + room["d"]
            if abs(z - face_n) < abs(z - face_s):
                out.append((x - half, face_n, x + half, face_n + CLEAR))
            else:
                out.append((x - half, face_s - CLEAR, x + half, face_s))
    return out


def door_target(room: dict, d: dict, depth: float = 0.6) -> tuple[float, float]:
    """Where a body stands a pace inside `room` from door `d`."""
    x, _, z = d["at"]
    if d["axis"] == "x":
        return (room["x"] + depth, z) if abs(x - room["x"]) < abs(x - room["x"] - room["w"]) else (room["x"] + room["w"] - depth, z)
    return (x, room["z"] + depth) if abs(z - room["z"]) < abs(z - room["z"] - room["d"]) else (x, room["z"] + room["d"] - depth)


def place_stair(room: dict, ground: list[dict], doors: list[dict], rng) -> dict | None:
    """A straight flight against one of `room`'s walls, its top at a corner, its foot toward the
    middle of the wall with a metre of floor before it; clear of every door's zone. An outside
    wall is preferred (a stair against a shared wall would hide the neighbour's door)."""
    zones = door_zones(room, doors)
    options = []
    x0, z0, x1, z1 = rect_of(room)
    for side in ("S", "E", "W", "N"):
        for top_at_end in (True, False):
            if side in ("N", "S"):
                length = room["w"]
                wall = z1 if side == "S" else z0
                inward = (0.0, -1.0) if side == "S" else (0.0, 1.0)
                run_dir = (1.0, 0.0) if top_at_end else (-1.0, 0.0)
                toe_s = x1 - 0.05 - RUN if top_at_end else x0 + 0.05 + RUN
                origin = (toe_s, wall)
            else:
                length = room["d"]
                wall = x1 if side == "E" else x0
                inward = (-1.0, 0.0) if side == "E" else (1.0, 0.0)
                run_dir = (0.0, 1.0) if top_at_end else (0.0, -1.0)
                toe_s = z1 - 0.05 - RUN if top_at_end else z0 + 0.05 + RUN
                origin = (wall, toe_s)
            if length < RUN + FOOT + 0.1:
                continue
            st = {"origin": origin, "dir": run_dir, "in": inward, "room": room["id"], "side": side}
            foot = stair_rect(st, -FOOT, 0.0, 0.0, STAIR_W)
            body = stair_rect(st, 0.0, RUN, 0.0, STAIR_W)
            if any(overlap(foot, zn) or overlap(body, zn) for zn in zones):
                continue
            outside = not any(o is not room and shares_side(room, o, side) for o in ground)
            options.append(((0 if outside else 5) + rng.uniform(0, 1), st))
    if not options:
        return None
    options.sort(key=lambda o: o[0])
    st = options[0][1]
    # Which sides of the landing a door may open in: beyond the top, and along the strip beside
    # the well. Never over the well, and never the end the flight rises from.
    dx, dz = st["dir"]
    ix, iz = st["in"]
    side_of = {(1, 0): "E", (-1, 0): "W", (0, 1): "S", (0, -1): "N"}
    st["landing_sides"] = (side_of[(int(dx), int(dz))], side_of[(int(ix), int(iz))])
    return st


def shares_side(a: dict, b: dict, side: str) -> bool:
    if side == "S":
        return abs(b["z"] - (a["z"] + a["d"] + WALL_T)) < 0.05 and b["x"] < a["x"] + a["w"] and a["x"] < b["x"] + b["w"]
    if side == "N":
        return abs(a["z"] - (b["z"] + b["d"] + WALL_T)) < 0.05 and b["x"] < a["x"] + a["w"] and a["x"] < b["x"] + b["w"]
    if side == "E":
        return abs(b["x"] - (a["x"] + a["w"] + WALL_T)) < 0.05 and b["z"] < a["z"] + a["d"] and a["z"] < b["z"] + b["d"]
    return abs(a["x"] - (b["x"] + b["w"] + WALL_T)) < 0.05 and b["z"] < a["z"] + a["d"] and a["z"] < b["z"] + b["d"]


def stair_point(st: dict, s: float, t: float) -> tuple[float, float]:
    ox, oz = st["origin"]
    return ox + st["dir"][0] * s + st["in"][0] * t, oz + st["dir"][1] * s + st["in"][1] * t


def stair_rect(st: dict, s0: float, s1: float, t0: float, t1: float) -> tuple:
    a = stair_point(st, s0, t0)
    b = stair_point(st, s1, t1)
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))


def landing_for(st: dict) -> dict:
    x0, z0, x1, z1 = stair_rect(st, WELL_FROM, RUN + ARRIVE, 0.0, STAIR_W + STRIP)
    return {"id": "landing", "kind": "landing", "x": x0, "z": z0, "w": round(x1 - x0, 3), "d": round(z1 - z0, 3),
            "storey": 1, "floor_y": round(LEVEL, 3), "wear": 0.2, "depth": 0}


# ---------------------------------------------------------------------------------------
# The shell: boxes, unioned, with the openings cut out exactly.
# ---------------------------------------------------------------------------------------

def box(lo, hi) -> trimesh.Trimesh:
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    m = trimesh.creation.box(extents=hi - lo)
    m.apply_translation((lo + hi) * 0.5)
    return m


def outer_faces(rooms: list[dict]) -> list[tuple]:
    """Stretches of wall with nothing on the other side: (room, side, lo, hi)."""
    out = []
    for r in rooms:
        for side in ("N", "S", "E", "W"):
            if side in ("N", "S"):
                spans = [(r["x"], r["x"] + r["w"])]
            else:
                spans = [(r["z"], r["z"] + r["d"])]
            for o in rooms:
                if o is r or o["storey"] != r["storey"] or not shares_side(r, o, side):
                    continue
                cut = (o["x"] - WALL_T, o["x"] + o["w"] + WALL_T) if side in ("N", "S") else (o["z"] - WALL_T, o["z"] + o["d"] + WALL_T)
                nxt = []
                for a, b in spans:
                    if cut[1] <= a or cut[0] >= b:
                        nxt.append((a, b))
                        continue
                    if cut[0] > a:
                        nxt.append((a, cut[0]))
                    if cut[1] < b:
                        nxt.append((cut[1], b))
                spans = nxt
            for a, b in spans:
                if b - a > WINDOW_W + 1.0:
                    out.append((r, side, a, b))
    return out


def choose_windows(rooms: list[dict], doors: list[dict], stair: dict | None, recipe: dict, rng,
                   placements: list[dict] = ()) -> list[dict]:
    """Windows in outside walls, where the wall is free: never over a door's clear zone or the
    stair, and never behind anything that stands taller than the sill."""
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    # The landing is a neighbour like any room (a window never opens onto it), but takes no window.
    faces = [f for f in outer_faces(rooms) if f[0]["kind"] != "landing"]
    tall: dict[str, list] = {}
    for p in placements:
        if p.get("on") or p["bounds"][1][1] <= WINDOW_SILL - 0.05:
            continue
        fp = turned(p["bounds"], p["yaw"])
        tall.setdefault(p["room"], []).append((p["at"][0] + fp[0], p["at"][2] + fp[1], p["at"][0] + fp[2], p["at"][2] + fp[3]))
    cands = []
    for r, side, a, b in faces:
        zones = door_zones(r, doors) + tall.get(r["id"], [])
        for t in np.arange(a + 0.7, b - 0.7 + 1e-6, 0.1):
            if side in ("N", "S"):
                fz = r["z"] if side == "N" else r["z"] + r["d"]
                front = (t - WINDOW_W * 0.5 - 0.2, fz - 0.7, t + WINDOW_W * 0.5 + 0.2, fz + 0.7)
            else:
                fx = r["x"] if side == "W" else r["x"] + r["w"]
                front = (fx - 0.7, t - WINDOW_W * 0.5 - 0.2, fx + 0.7, t + WINDOW_W * 0.5 + 0.2)
            if any(overlap(front, zn) for zn in zones):
                continue
            if stair is not None and r["id"] == stair["room"] and overlap(front, grow(stair_rect(stair, -FOOT, RUN, 0.0, STAIR_W), 0.3)):
                continue
            mid = (a + b) * 0.5
            cands.append((r, side, float(t), abs(t - mid)))
    chosen, used = [], set()
    prio = {"hearth_room": 0, "tap_room": 0, "hall": 1, "workshop": 1, "bakehouse": 1, "stillroom": 1,
            "bed": 2, "study": 2, "guest_room": 2, "shop_front": 2}
    by_room: dict[str, list] = {}
    for c in cands:
        by_room.setdefault(c[0]["id"], []).append(c)
    room_order = sorted(by_room, key=lambda rid: (prio.get(next(r["kind"] for r in rooms if r["id"] == rid), 3), rid))
    want = wealth["windows"]
    passes = 0
    while len(chosen) < want and passes < 3:
        for rid in room_order:
            if len(chosen) >= want:
                break
            opts = [c for c in by_room[rid] if (rid, c[1]) not in used or passes > 0]
            opts = [c for c in opts if all(not (w[0]["id"] == rid and w[1] == c[1] and abs(w[2] - c[2]) < 1.6) for w in chosen)]
            if not opts:
                continue
            opts.sort(key=lambda c: c[3] + rng.uniform(0, 0.8))
            c = opts[0]
            chosen.append(c)
            used.add((rid, c[1]))
        passes += 1
    windows = []
    for r, side, t, _ in chosen:
        y = r["floor_y"] + WINDOW_SILL + WINDOW_H * 0.5
        if side in ("N", "S"):
            wz = r["z"] - WALL_T * 0.5 if side == "N" else r["z"] + r["d"] + WALL_T * 0.5
            at, axis, normal = (t, y, wz), "z", [0.0, 0.0, 1.0 if side == "N" else -1.0]
        else:
            wx = r["x"] - WALL_T * 0.5 if side == "W" else r["x"] + r["w"] + WALL_T * 0.5
            at, axis, normal = (wx, y, t), "x", [1.0 if side == "W" else -1.0, 0.0, 0.0]
        # The daylight stands outside the window and shines along -normal into the room
        # (house_interior.gd), so the yaw turns the normal outward.
        out_yaw = {"N": 180.0, "S": 0.0, "W": 270.0, "E": 90.0}[side]
        outward = [-v for v in normal]
        windows.append({"room": r["id"], "at": [round(v, 3) for v in at], "axis": axis, "side": side,
                        "yaw": out_yaw, "normal": outward})
    return windows


def opening_box(at, axis: str, width: float, y0: float, y1: float, thick: float) -> trimesh.Trimesh:
    x, _, z = at
    if axis == "x":
        return box((x - thick * 0.5, y0, z - width * 0.5), (x + thick * 0.5, y1, z + width * 0.5))
    return box((x - width * 0.5, y0, z - thick * 0.5), (x + width * 0.5, y1, z + thick * 0.5))


def build_shell(rooms, doors, windows, stair):
    """The shell (one solid), its timber, and its collision."""
    solids, holes, timber, extra_col = [], [], [], []
    top_storey = max(r["storey"] for r in rooms)
    for r in rooms:
        x0, z0, x1, z1 = rect_of(r)
        y0 = r["floor_y"]
        t = WALL_T
        # The floor this room stands on: the ground's slab, or the ceiling of the storey below.
        if r["storey"] == 0:
            solids.append(box((x0 - t, -0.35, z0 - t), (x1 + t, 0.0, z1 + t)))
        else:
            solids.append(box((x0 - t, y0 - SLAB, z0 - t), (x1 + t, y0, z1 + t)))
        # Its ceiling, which upstairs rooms stand on.
        solids.append(box((x0 - t, y0 + STOREY_H, z0 - t), (x1 + t, y0 + STOREY_H + SLAB, z1 + t)))
        # Four walls, each closing its corners.
        solids.append(box((x0 - t, y0, z0 - t), (x1 + t, y0 + STOREY_H, z0)))
        solids.append(box((x0 - t, y0, z1), (x1 + t, y0 + STOREY_H, z1 + t)))
        solids.append(box((x0 - t, y0, z0), (x0, y0 + STOREY_H, z1)))
        solids.append(box((x1, y0, z0), (x1 + t, y0 + STOREY_H, z1)))
        timber += joists(r, stair)

    for d in doors:
        y0 = d["at"][1]
        holes.append(opening_box(d["at"], d["axis"], DOOR_W, y0 + 0.0005, y0 + DOOR_H, WALL_T + 0.1))
        timber += door_frame(d)
    for w in windows:
        yc = w["at"][1]
        holes.append(opening_box(w["at"], w["axis"], WINDOW_W, yc - WINDOW_H * 0.5, yc + WINDOW_H * 0.5, WALL_T + 0.1))
        timber += window_frame(w)
        # Glazing the body cannot walk through (the pane itself is drawn at runtime).
        extra_col.append(opening_box(w["at"], w["axis"], WINDOW_W, yc - WINDOW_H * 0.5, yc + WINDOW_H * 0.5, 0.04))
    if stair is not None:
        x0, z0, x1, z1 = stair_rect(stair, WELL_FROM, RUN + 0.01, 0.0, STAIR_W + 0.02)
        holes.append(box((x0, STOREY_H - 0.01, z0), (x1, LEVEL + 0.01, z1)))
        parts, col = stair_parts(stair)
        timber += parts
        extra_col += col
    front = next(d for d in doors if d["kind"] == "front")
    leaf, leaf_col = front_leaf(front)
    timber += leaf
    extra_col.append(leaf_col)

    shell = trimesh.boolean.union(solids, engine="manifold")
    shell = trimesh.boolean.difference([shell, trimesh.boolean.union(holes, engine="manifold")], engine="manifold")
    shell.merge_vertices()
    tim = trimesh.util.concatenate(timber) if timber else None
    col = trimesh.util.concatenate([shell] + extra_col)
    return shell, tim, col


def joists(r: dict, stair: dict | None) -> list:
    """Joists across the shorter span under the ceiling, a plate round the walls, and around a
    stairwell a trimmer instead of joists through the hole."""
    out = []
    x0, z0, x1, z1 = rect_of(r)
    y_top = r["floor_y"] + STOREY_H
    well = None
    if stair is not None and (r["id"] == stair["room"] or r["kind"] == "landing"):
        well = stair_rect(stair, WELL_FROM - 0.05, RUN + 0.05, -0.1, STAIR_W + 0.05)
    along_z = r["w"] < r["d"]
    span = r["d"] if along_z else r["w"]
    n = max(int(span / 0.78), 2)
    if r["kind"] != "landing":
        for k in range(1, n):
            depth = 0.16 + 0.04 * ((k % 3) - 1) * 0.5
            if along_z:
                bz = z0 + r["d"] * k / n
                lo, hi = (x0 - WALL_T * 0.5, y_top - depth, bz - 0.065), (x1 + WALL_T * 0.5, y_top, bz + 0.065)
            else:
                bx = x0 + r["w"] * k / n
                lo, hi = (bx - 0.065, y_top - depth, z0 - WALL_T * 0.5), (bx + 0.065, y_top, z1 + WALL_T * 0.5)
            if well is not None and overlap((lo[0], lo[2], hi[0], hi[2]), well):
                continue
            out.append(box(lo, hi))
    plate = 0.14
    for lo, hi in (((x0, y_top - 0.18, z0), (x1, y_top, z0 + plate)),
                   ((x0, y_top - 0.18, z1 - plate), (x1, y_top, z1)),
                   ((x0, y_top - 0.18, z0), (x0 + plate, y_top, z1)),
                   ((x1 - plate, y_top - 0.18, z0), (x1, y_top, z1))):
        if well is not None and r["id"] == stair["room"] and overlap((lo[0], lo[2], hi[0], hi[2]), well):
            continue
        out.append(box(lo, hi))
    if well is not None and r["id"] == stair["room"]:
        a = stair_rect(stair, WELL_FROM - 0.05, RUN, STAIR_W + 0.02, STAIR_W + 0.16)
        out.append(box((a[0], y_top - 0.2, a[1]), (a[2], y_top, a[3])))
        b = stair_rect(stair, WELL_FROM - 0.19, WELL_FROM - 0.05, 0.0, STAIR_W + 0.16)
        out.append(box((b[0], y_top - 0.2, b[1]), (b[2], y_top, b[3])))
    return out


def door_frame(d: dict) -> list:
    """A timber casing round a doorway on both faces, outside the opening so it narrows nothing."""
    out = []
    x, y0, z = d["at"]
    jw, proud, head = 0.09, 0.035, 0.12
    half = DOOR_W * 0.5
    for face in (-1.0, 1.0):
        off = face * (WALL_T * 0.5 + proud * 0.5)
        if d["axis"] == "z":
            zc = z + off
            out.append(box((x - half - jw, y0, zc - proud * 0.5), (x - half, y0 + DOOR_H, zc + proud * 0.5)))
            out.append(box((x + half, y0, zc - proud * 0.5), (x + half + jw, y0 + DOOR_H, zc + proud * 0.5)))
            out.append(box((x - half - jw - 0.03, y0 + DOOR_H, zc - proud * 0.5), (x + half + jw + 0.03, y0 + DOOR_H + head, zc + proud * 0.5)))
        else:
            xc = x + off
            out.append(box((xc - proud * 0.5, y0, z - half - jw), (xc + proud * 0.5, y0 + DOOR_H, z - half)))
            out.append(box((xc - proud * 0.5, y0, z + half), (xc + proud * 0.5, y0 + DOOR_H, z + half + jw)))
            out.append(box((xc - proud * 0.5, y0 + DOOR_H, z - half - jw - 0.03), (xc + proud * 0.5, y0 + DOOR_H + head, z + half + jw + 0.03)))
    # A sill board across the threshold, flush with the floor, the width of the wall.
    if d["axis"] == "z":
        out.append(box((x - half, y0 - 0.02, z - WALL_T * 0.5), (x + half, y0 + 0.004, z + WALL_T * 0.5)))
    else:
        out.append(box((x - WALL_T * 0.5, y0 - 0.02, z - half), (x + WALL_T * 0.5, y0 + 0.004, z + half)))
    return out


def window_frame(w: dict) -> list:
    out = []
    x, yc, z = w["at"]
    half, hh, bar = WINDOW_W * 0.5, WINDOW_H * 0.5, 0.05
    inner = -1.0 if w["side"] in ("S", "E") else 1.0      # toward the room
    off = inner * (WALL_T * 0.5 + 0.02)
    sill_off = inner * (WALL_T * 0.5 + 0.06)
    if w["axis"] == "z":
        zc = z + off
        out.append(box((x - half - 0.07, yc - hh - 0.07, zc - 0.02), (x - half, yc + hh + 0.07, zc + 0.02)))
        out.append(box((x + half, yc - hh - 0.07, zc - 0.02), (x + half + 0.07, yc + hh + 0.07, zc + 0.02)))
        out.append(box((x - half, yc + hh, zc - 0.02), (x + half, yc + hh + 0.07, zc + 0.02)))
        out.append(box((x - half - 0.1, yc - hh - 0.05, min(z, z + sill_off) - 0.02), (x + half + 0.1, yc - hh, max(z, z + sill_off) + 0.02)))
        out.append(box((x - bar * 0.5, yc - hh, z - 0.02), (x + bar * 0.5, yc + hh, z + 0.02)))
        out.append(box((x - half, yc - bar * 0.5, z - 0.02), (x + half, yc + bar * 0.5, z + 0.02)))
    else:
        xc = x + off
        out.append(box((xc - 0.02, yc - hh - 0.07, z - half - 0.07), (xc + 0.02, yc + hh + 0.07, z - half)))
        out.append(box((xc - 0.02, yc - hh - 0.07, z + half), (xc + 0.02, yc + hh + 0.07, z + half + 0.07)))
        out.append(box((xc - 0.02, yc + hh, z - half), (xc + 0.02, yc + hh + 0.07, z + half)))
        out.append(box((min(x, x + sill_off) - 0.02, yc - hh - 0.05, z - half - 0.1), (max(x, x + sill_off) + 0.02, yc - hh, z + half + 0.1)))
        out.append(box((x - 0.02, yc - hh, z - bar * 0.5), (x + 0.02, yc + hh, z + bar * 0.5)))
        out.append(box((x - 0.02, yc - bar * 0.5, z - half), (x + 0.02, yc + bar * 0.5, z + half)))
    return out


def front_leaf(d: dict):
    """The front door, shut, in its opening: planks on two ledges. The way out is through it (the
    Door interaction stands in the same place), and nobody walks out into the dark round it."""
    x, y0, z = d["at"]
    out = []
    leaf_t = 0.06
    zc = z - WALL_T * 0.5 + 0.05          # set in from the outside face
    n = 5
    pw = DOOR_W / n
    for i in range(n):
        px = x - DOOR_W * 0.5 + pw * (i + 0.5)
        out.append(box((px - pw * 0.5 + 0.004, y0 + 0.01, zc - leaf_t * 0.5), (px + pw * 0.5 - 0.004, y0 + DOOR_H - 0.01, zc + leaf_t * 0.5)))
    for ly in (0.35, DOOR_H - 0.4):
        out.append(box((x - DOOR_W * 0.5 + 0.05, y0 + ly, zc + leaf_t * 0.5), (x + DOOR_W * 0.5 - 0.05, y0 + ly + 0.14, zc + leaf_t * 0.5 + 0.035)))
    col = box((x - DOOR_W * 0.5, y0, zc - leaf_t * 0.5), (x + DOOR_W * 0.5, y0 + DOOR_H, zc + leaf_t * 0.5))
    return out, col


def _oriented(st: dict, s0: float, s1: float, t0: float, t1: float, y0: float, y1: float) -> trimesh.Trimesh:
    x0, z0, x1, z1 = stair_rect(st, s0, s1, t0, t1)
    return box((x0, y0, z0), (x1, y1, z1))


def stair_parts(st: dict):
    """The flight (treads on a closed string, a handrail on its open side) and the rail round the
    well upstairs; and the collision: a ramp over the nosings, and the rail."""
    parts, col = [], []
    for k in range(1, RISERS):
        s0, s1 = GOING * k, min(GOING * (k + 1), RUN)
        top = RISE * k
        parts.append(_oriented(st, s0, s1, 0.0, STAIR_W, 0.0, top - 0.035))
        parts.append(_oriented(st, s0 - 0.025, s1, 0.0, STAIR_W + 0.02, top - 0.035, top))
    # A newel at the foot and a rail up the open side, on posts.
    parts.append(_oriented(st, GOING - 0.05, GOING + 0.05, STAIR_W - 0.1, STAIR_W, 0.0, RISE + 1.0))
    for k in (4, 8, 12):
        s = GOING * k + 0.1
        parts.append(_oriented(st, s - 0.025, s + 0.025, STAIR_W - 0.075, STAIR_W - 0.025, RISE * k, RISE * k + 0.9))
    slope = LEVEL / RUN
    length = math.hypot(RUN - GOING, (RUN - GOING) * slope)
    rail = trimesh.creation.box(extents=(length, 0.06, 0.07))
    ang = math.atan(slope)
    rail.apply_transform(trimesh.transformations.rotation_matrix(ang, (0, 0, 1)))
    # rail was built along +x rising to +y; turn it onto the flight
    heading = math.atan2(st["dir"][1], st["dir"][0])
    rail.apply_transform(trimesh.transformations.rotation_matrix(-heading, (0, 1, 0)))
    mid_s = (GOING + RUN) * 0.5
    cx, cz = stair_point(st, mid_s, STAIR_W - 0.05)
    rail.apply_translation((cx, RISE + 0.95 + (mid_s - GOING) * slope, cz))
    parts.append(rail)
    # Round the well upstairs: posts and a rail along its open side.
    for s in np.linspace(WELL_FROM + 0.05, RUN - 0.05, 5):
        parts.append(_oriented(st, s - 0.03, s + 0.03, STAIR_W + 0.02, STAIR_W + 0.08, LEVEL, LEVEL + 1.0))
    parts.append(_oriented(st, WELL_FROM, RUN, STAIR_W + 0.01, STAIR_W + 0.09, LEVEL + 0.92, LEVEL + 1.0))
    parts.append(_oriented(st, WELL_FROM, RUN, STAIR_W + 0.03, STAIR_W + 0.07, LEVEL + 0.4, LEVEL + 0.45))
    col.append(_oriented(st, WELL_FROM, RUN, STAIR_W + 0.02, STAIR_W + 0.08, LEVEL, LEVEL + 1.0))
    # The ramp: a wedge from the toe on the floor to the landing's edge, over the nosings.
    a = stair_point(st, 0.0, 0.0)
    b = stair_point(st, 0.0, STAIR_W)
    c = stair_point(st, RUN, 0.0)
    e = stair_point(st, RUN, STAIR_W)
    v = np.array([[a[0], 0.0, a[1]], [b[0], 0.0, b[1]], [c[0], 0.0, c[1]], [e[0], 0.0, e[1]],
                  [c[0], LEVEL, c[1]], [e[0], LEVEL, e[1]]])
    wedge = trimesh.Trimesh(v, [[0, 2, 1], [1, 2, 3], [0, 1, 4], [1, 5, 4], [0, 4, 2], [1, 3, 5], [2, 4, 3], [3, 4, 5]])
    trimesh.repair.fix_normals(wedge)
    col.append(wedge)
    return parts, col


def fireplace(p: dict):
    """A fireplace built into the wall at placement `p`: a chimney breast with a stack above the
    mantel, a fire opening with a lintel stone, a hearthstone before it; logs on the embers and a
    mantel shelf in timber. (masonry parts, ember parts, timber parts), in the house's space."""
    hw, hd = FP_W * 0.5, FP_D * 0.5
    lower = box((-hw, 0.0, -hd), (hw, 1.45, hd))
    stack = box((-0.62, 1.4, -hd), (0.62, STOREY_H - 0.005, hd - 0.15))
    opening = box((-0.55, 0.05, -hd + 0.18), (0.55, 1.05, hd + 0.05))
    breast = trimesh.boolean.difference([trimesh.boolean.union([lower, stack], engine="manifold"), opening], engine="manifold")
    masonry = [breast,
               box((-hw + 0.05, 0.0, hd), (hw - 0.05, 0.05, hd + FP_STONE)),        # hearthstone
               box((-0.55, 0.0, -hd + 0.18), (0.55, 0.05, hd)),                      # firebox floor
               box((-0.68, 1.05, hd - 0.02), (0.68, 1.24, hd + 0.05))]               # lintel stone
    timber = [box((-hw - 0.08, 1.45, -hd), (hw + 0.08, 1.56, hd + 0.08))]            # mantel shelf
    for x0, x1, z, y in ((-0.34, 0.3, -0.05, 0.1), (-0.28, 0.36, 0.08, 0.1), (-0.2, 0.25, 0.01, 0.21)):
        log = trimesh.creation.cylinder(radius=0.055, height=x1 - x0, sections=10)
        log.apply_transform(trimesh.transformations.rotation_matrix(math.pi * 0.5, (0, 1, 0)))
        log.apply_transform(trimesh.transformations.rotation_matrix(0.25 * (1 if z > 0 else -1), (0, 1, 0)))
        log.apply_translation(((x0 + x1) * 0.5, y, z))
        timber.append(log)
    embers = [box((-0.36, 0.05, -0.1), (0.36, 0.085, 0.2))]
    a = math.radians(p["yaw"])
    m = trimesh.transformations.rotation_matrix(a, (0, 1, 0))
    m[:3, 3] = p["at"]
    for part in masonry + timber + embers:
        part.apply_transform(m)
    return masonry, embers, timber


def floors_for(rooms: list[dict], stair: dict | None) -> list[dict]:
    """Walkable floor rects per room (the landing's minus its stairwell), for the runtime's floor
    planes and floor boxes."""
    out = []
    for r in rooms:
        rects = [rect_of(r)]
        if stair is not None and r["kind"] == "landing":
            well = stair_rect(stair, WELL_FROM, RUN, 0.0, STAIR_W + 0.02)
            rects = subtract(rects[0], well)
        for x0, z0, x1, z1 in rects:
            if x1 - x0 < 0.05 or z1 - z0 < 0.05:
                continue
            out.append({"room": r["id"], "at": [round((x0 + x1) * 0.5, 3), r["floor_y"], round((z0 + z1) * 0.5, 3)],
                        "size": [round(x1 - x0, 3), round(z1 - z0, 3)]})
    return out


def subtract(a, b) -> list:
    if not overlap(a, b):
        return [a]
    out = []
    x0, z0, x1, z1 = a
    bx0, bz0, bx1, bz1 = max(b[0], x0), max(b[1], z0), min(b[2], x1), min(b[3], z1)
    if bz0 > z0:
        out.append((x0, z0, x1, bz0))
    if bz1 < z1:
        out.append((x0, bz1, x1, z1))
    if bx0 > x0:
        out.append((x0, bz0, bx0, bz1))
    if bx1 < x1:
        out.append((bx1, bz0, x1, bz1))
    return out


# ---------------------------------------------------------------------------------------
# Dressing: what is in the room, and why it is where it is.
# ---------------------------------------------------------------------------------------

# How each fixture wants to stand: against a wall (`wall`), in a corner (`corner`), free in the
# room (`centre`, `open`), drawn up to a table (`seat`), or on a surface (`surface`). `near` is what
# it belongs beside, so a room falls into its corners: the fire and what feeds it, the table and
# its seats, the bed and its chest.
FIXTURE = {
    "forge": ("wall", None), "anvil": ("open", "forge"), "quench_trough": ("wall", "forge"),
    "bellows": ("wall", "forge"), "tool_rack": ("wall", "anvil"), "coal_heap": ("corner", "forge"),
    "iron_stock": ("wall", None), "crate": ("wall", None), "barrel": ("corner", None),
    "bread_oven": ("wall", None), "kneading_table": ("open", "bread_oven"), "flour_sacks": ("corner", "kneading_table"),
    "peel_rack": ("wall", "bread_oven"), "counter": ("wall", None), "bread_shelf": ("wall", "counter"),
    "millstone": ("centre", None), "hopper": ("wall", "millstone"), "sack_hoist": ("corner", "millstone"),
    "gear_pit": ("corner", "millstone"), "scales": ("surface", "counter"), "ledger_desk": ("wall", None),
    "mash_tun": ("corner", None), "copper": ("wall", "mash_tun"), "cooling_trays": ("wall", "copper"),
    "hop_sacks": ("corner", "mash_tun"), "barrel_rack": ("wall", None), "tap_bench": ("wall", "barrel_rack"),
    "alembic": ("surface", "mortar_bench"), "drying_rack": ("wall", "mortar_bench"),
    "ingredient_shelf": ("wall", "mortar_bench"), "mortar_bench": ("wall", None), "bottle_shelf": ("wall", "counter"),
    "bar": ("wall", None), "long_table": ("centre", "hearth"), "bench": ("seat", "long_table"),
    "hearth": ("wall", None), "board": ("wall", "bar"), "cook_hearth": ("wall", None),
    "prep_table": ("open", "cook_hearth"), "pot_rack": ("wall", "cook_hearth"), "bed": ("bed", None),
    "chest": ("wall", "bed"), "washstand": ("wall", "bed"), "stall": ("wall", None), "hay_pile": ("corner", "stall"),
    "yoke": ("wall", "stall"), "pitchfork": ("wall", "hay_pile"), "grain_bin": ("wall", None),
    "root_crate": ("corner", "grain_bin"), "seed_sacks": ("corner", "grain_bin"), "writing_desk": ("wall", None),
    "deed_chest": ("wall", "writing_desk"), "shelf": ("wall", None), "strongbox": ("corner", "writing_desk"),
    "chair": ("seat", "writing_desk"), "sideboard": ("wall", "long_table"), "net_rack": ("wall", None),
    "drying_line": ("wall", "net_rack"), "oar_rack": ("corner", "net_rack"), "tar_pot": ("corner", "net_rack"),
    # A Name-table (DESIGN §5.8): the bench a Toll-Knight writes a note into iron at. Against a
    # wall, because the Bell Chapter-House's muster room is a cell.
    "name_table": ("wall", None),
    "weapon_rack": ("wall", None), "roll_desk": ("wall", None), "map_board": ("wall", "roll_desk"),
    "stool": ("seat", "table"), "cupboard": ("wall", "table"), "table": ("centre", "hearth"),
    "settle": ("wall", "hearth"), "cradle": ("wall", "bed"), "loom": ("wall", None),
    "spinning_wheel": ("open", "hearth"), "basket": ("wall", "hearth"), "bucket": ("wall", "hearth"),
}
# Built into the house rather than stood in it: a fireplace is masonry, part of the wall it is
# against. Its footprint takes in the hearthstone before it (nothing stands there); it collides as
# the chimney breast.
BUILT = {"hearth": "fireplace", "cook_hearth": "fireplace"}
FP_W, FP_D, FP_STONE = 1.8, 0.6, 0.42
BUILT_FOOTPRINT = {"fireplace": ((-FP_W * 0.5, 0.0, -FP_D * 0.5), (FP_W * 0.5, STOREY_H - 0.01, FP_D * 0.5 + FP_STONE))}
BUILT_COLLIDER = {"fireplace": ((-FP_W * 0.5, 0.0, -FP_D * 0.5), (FP_W * 0.5, STOREY_H - 0.01, FP_D * 0.5))}
# What a seat is drawn up to, in order of preference.
SEAT_FOR = {"stool": ("table", "roll_desk", "kneading_table", "prep_table", "long_table", "writing_desk"),
            "chair": ("writing_desk", "long_table", "table", "roll_desk"),
            "bench": ("long_table", "table")}
# What stands against the fire's own wall, never across its mouth.
HEARTHS = ("hearth", "cook_hearth", "forge", "bread_oven")
# Things a body has to be able to walk up to the front of.
CONTAINERS = ("chest", "deed_chest", "strongbox", "coffer", "cupboard", "crate", "root_crate", "barrel",
              "barrel_rack", "hop_sacks", "seed_sacks", "flour_sacks", "washstand")
WORKABLE = ("anvil", "alembic", "name_table")

# Every hearth room gets these, and the purse adds to them: this is what "lived in" means.
HOME_FIXTURES = ["hearth", "table", "stool", "stool", "cupboard", "settle", "basket"]

# What sits on a surface, grouped the way a person would group it.
SURFACE_GROUPS = {
    "kneading_table": [["dough_ball", "flour_scoop", "cloth"], ["loaf_tin", "loaf_tin"]],
    "prep_table": [["knife", "board", "onion", "onion"], ["bowl", "cloth"]],
    "table": [["bowl", "spoon", "mug"], ["candlestick", "candle_stub"], ["bread_heel", "cheese_end"]],
    "long_table": [["mug", "mug", "mug", "jug"], ["candlestick"], ["dice_cup", "coin_few"]],
    "counter": [["scales", "coin_few"], ["wrapped_loaf", "wrapped_loaf"]],
    "bar": [["mug", "mug", "jug"], ["tally_stick", "rag"]],
    "writing_desk": [["quill", "inkpot", "paper_stack"], ["candlestick", "seal"]],
    "roll_desk": [["roll_book", "quill", "inkpot"], ["lantern"]],
    "ledger_desk": [["ledger", "quill", "inkpot"]],
    "mortar_bench": [["mortar", "pestle", "herb_bundle"], ["phial", "phial", "phial"]],
    "tap_bench": [["mug", "funnel", "bung_mallet"]],
    "washstand": [["basin", "ewer", "cloth"]],
    "sideboard": [["plate_stack", "jug"], ["candlestick"]],
    "shelf": [["book_stack", "book_single"], ["phial", "phial"]],
    "ingredient_shelf": [["jar", "jar", "jar"], ["herb_bundle", "herb_bundle"]],
    "bottle_shelf": [["phial", "phial", "phial", "phial"]],
    "bread_shelf": [["loaf", "loaf", "loaf"]],
    "tool_rack": [["hammer", "tongs", "file"], ["punch", "chisel"]],
    "weapon_rack": [["spear", "spear", "shield"]],
    "pot_rack": [["pot", "pan", "ladle"]],
    "cupboard": [["jug", "bowl"]],
    "chest": [["candle_stub"]],
}

# A habit is a sentence about the resident that becomes an object in the house. `where` says what
# it belongs with: a fixture kind it stands beside (floor) or lies on (surface), the front door, a
# window sill, or a surface of any kind in the hearth room.
HABIT_PROPS = {
    "leaves_boots_by_the_door": [("boots", "door")],
    "keeps_the_fire_in": [("kindling_basket", "hearth"), ("cooking_pot", "hearth")],
    "drinks_alone": [("mug", "on:settle|table"), ("jug", "on:settle|table")],
    "mends_at_night": [("mending_basket", "settle"), ("candle_stub", "on:table")],
    "reads_late": [("book_single", "on:bed"), ("candle_stub", "on:chest|washstand|bed")],
    "never_finishes_a_job": [("half_made_thing", "table")],
    "feeds_the_birds": [("crumb_bowl", "window")],
    "counts_everything": [("tally_sticks", "on:shelf|cupboard|table|writing_desk|roll_desk")],
    "keeps_a_shrine": [("small_bell", "on:cupboard|shelf|chest|table"), ("candle_stub", "on:cupboard|shelf|chest|table")],
    "sleeps_badly": [("blanket_heap", "on:bed"), ("cold_tea", "on:chest|washstand|bed")],
    "hoards_string": [("string_ball", "corner"), ("string_ball", "corner")],
    "works_at_the_table": [("work_in_progress", "on:table|long_table|writing_desk")],
    "has_a_dog": [("dog_bowl", "hearth"), ("chewed_stick", "hearth")],
    "has_children": [("wooden_toy", "hearth"), ("small_boots", "door")],
    "sharpens_obsessively": [("whetstone", "on:bench|settle|table|anvil|long_table"), ("oil_rag", "on:bench|settle|table|anvil|long_table")],
}


def asset_for(name: str) -> str:
    return f"res://assets/models/props/{name}/{name}.glb"


def is_clutter(bounds) -> bool:
    (x0, y0, z0), (x1, y1, z1) = bounds
    return (y1 - y0) < CLUTTER_H or max(x1 - x0, z1 - z0) < CLUTTER_W


def turned(bounds, yaw: float) -> tuple:
    """A prop's footprint (x0, z0, x1, z1) about its origin, turned by yaw (a multiple of 90)."""
    (x0, _, z0), (x1, _, z1) = bounds
    corners = [(x0, z0), (x0, z1), (x1, z0), (x1, z1)]
    a = math.radians(yaw)
    c, s = round(math.cos(a)), round(math.sin(a))
    # Godot's turn about +Y: x' = x cos + z sin, z' = -x sin + z cos
    pts = [(x * c + z * s, -x * s + z * c) for x, z in corners]
    return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))


def facing(yaw: float) -> tuple[float, float]:
    """The prop's front (+Z) in the plan after the turn."""
    a = math.radians(yaw)
    return (round(math.sin(a)), round(math.cos(a)))


# The yaw that puts a prop's back to a wall: local -Z (or -X for a bed's head) toward it.
WALL_YAW = {"N": 0.0, "S": 180.0, "W": 90.0, "E": 270.0}
HEAD_YAW = {"N": 270.0, "S": 90.0, "W": 0.0, "E": 180.0}


class Room:
    """One room's floor as a grid of RES cells: what stands where, what must stay clear."""

    def __init__(self, r: dict, doors: list[dict], windows: list[dict], stair: dict | None):
        self.r = r
        self.x0, self.z0 = r["x"], r["z"]
        self.nu = int(math.floor(r["w"] / RES + 1e-6))
        self.nv = int(math.floor(r["d"] / RES + 1e-6))
        self.solid = np.zeros((self.nu, self.nv), bool)     # furniture that collides
        self.keep = np.zeros((self.nu, self.nv), bool)      # nothing at all
        self.low = np.zeros((self.nu, self.nv), bool)       # nothing taller than a sill
        self.clutter = np.zeros((self.nu, self.nv), bool)   # things on the floor that do not collide
        self.zones = door_zones(r, doors)
        for zn in self.zones:
            self.mark(self.keep, zn)
        self.targets = [door_target(r, d) for d in doors if r["id"] in d["between"]]
        self.stair_zones = []
        if stair is not None and r["id"] == stair["room"]:
            self.stair_zones.append(stair_rect(stair, -FOOT, RUN + 0.05, 0.0, STAIR_W + 0.1))
            self.targets.append(stair_point(stair, -0.6, STAIR_W * 0.5))
        if stair is not None and r["kind"] == "landing":
            self.stair_zones.append(stair_rect(stair, WELL_FROM - 0.3, RUN + ARRIVE, 0.0, STAIR_W + 0.15))
            self.targets.append(stair_point(stair, RUN + 0.6, STAIR_W * 0.5))
        for zn in self.stair_zones:
            self.mark(self.keep, zn)
        self.solid_walls = np.zeros((self.nu, self.nv), bool)
        if stair is not None and r["id"] == stair["room"]:
            self.mark(self.solid_walls, stair_rect(stair, 0.0, RUN, 0.0, STAIR_W))
        if stair is not None and r["kind"] == "landing":
            self.mark(self.solid_walls, stair_rect(stair, WELL_FROM, RUN, 0.0, STAIR_W + 0.08))
        self.windows = [w for w in windows if w["room"] == r["id"]]
        for w in self.windows:
            x, _, z = w["at"]
            if w["axis"] == "z":
                fz = r["z"] if w["side"] == "N" else r["z"] + r["d"]
                self.mark(self.low, (x - WINDOW_W * 0.5 - 0.15, fz - 0.7, x + WINDOW_W * 0.5 + 0.15, fz + 0.7))
            else:
                fx = r["x"] if w["side"] == "W" else r["x"] + r["w"]
                self.mark(self.low, (fx - 0.7, z - WINDOW_W * 0.5 - 0.15, fx + 0.7, z + WINDOW_W * 0.5 + 0.15))
        self.fronts: list[tuple] = []      # (name, band rect) that must be reachable

    def cells(self, rect):
        u0 = int(math.floor((rect[0] - self.x0) / RES + 1e-6))
        v0 = int(math.floor((rect[1] - self.z0) / RES + 1e-6))
        u1 = int(math.ceil((rect[2] - self.x0) / RES - 1e-6))
        v1 = int(math.ceil((rect[3] - self.z0) / RES - 1e-6))
        return slice(max(u0, 0), min(u1, self.nu)), slice(max(v0, 0), min(v1, self.nv))

    def mark(self, grid, rect, value=True):
        su, sv = self.cells(rect)
        grid[su, sv] = value

    def inside(self, rect, margin=0.0) -> bool:
        r = self.r
        return (rect[0] >= r["x"] + margin - 1e-6 and rect[1] >= r["z"] + margin - 1e-6 and
                rect[2] <= r["x"] + r["w"] - margin + 1e-6 and rect[3] <= r["z"] + r["d"] - margin + 1e-6)

    def free(self, rect, tall: bool, grid=None) -> bool:
        su, sv = self.cells(grow(rect, GAP * 0.5))
        if self.keep[su, sv].any() or self.solid[su, sv].any() or self.solid_walls[su, sv].any():
            return False
        if tall and self.low[su, sv].any():
            return False
        if grid is not None and grid[su, sv].any():
            return False
        return True

    def walkable(self, solid=None):
        s = (self.solid if solid is None else solid) | self.solid_walls
        padded = np.pad(~s, 1, constant_values=False)
        dist = ndimage.distance_transform_edt(padded)[1:-1, 1:-1] * RES
        return dist >= PATH * 0.5 - 1e-6

    def cell_of(self, p):
        return (int(np.clip((p[0] - self.x0) / RES, 0, self.nu - 1)), int(np.clip((p[1] - self.z0) / RES, 0, self.nv - 1)))

    def connected(self, solid=None, fronts=None) -> bool:
        """Every door and stair target in one walkable piece, and every front reachable from it."""
        walk = self.walkable(solid)
        labels, _ = ndimage.label(walk, structure=np.ones((3, 3)))
        want = None
        for t in self.targets:
            c = self.cell_of(t)
            lab = self.near_label(labels, c)
            if lab == 0:
                return False
            if want is None:
                want = lab
            elif lab != want:
                return False
        if want is None:
            # A room with no door of its own (never, but be safe): the biggest piece is the room.
            counts = np.bincount(labels.ravel())
            counts[0] = 0
            want = int(counts.argmax()) if counts.size > 1 else 0
            if want == 0:
                return False
        for _, band in (self.fronts if fronts is None else fronts):
            su, sv = self.cells(band)
            if not (labels[su, sv] == want).any():
                return False
        return True

    @staticmethod
    def near_label(labels, c, reach: int = 3) -> int:
        u, v = c
        best = labels[u, v]
        if best:
            return int(best)
        for du in range(-reach, reach + 1):
            for dv in range(-reach, reach + 1):
                uu, vv = u + du, v + dv
                if 0 <= uu < labels.shape[0] and 0 <= vv < labels.shape[1] and labels[uu, vv]:
                    return int(labels[uu, vv])
        return 0

    def front_band(self, rect, yaw: float, depth: float = 0.9) -> tuple:
        fx, fz = facing(yaw)
        x0, z0, x1, z1 = rect
        if fz > 0:
            return (x0, z1, x1, z1 + depth)
        if fz < 0:
            return (x0, z0 - depth, x1, z0)
        if fx > 0:
            return (x1, z0, x1 + depth, z1)
        return (x0 - depth, z0, x0, z1)


def dress(rooms, doors, stair, recipe, props: Props, rng) -> tuple[list[dict], dict, list[dict]]:
    """Place fixtures against the walls, then put things on them, then open the windows where the
    walls are still free, then add the habits."""
    windows: list[dict] = []
    trade = TRADE_PLANS.get(recipe.get("trade", "none"), TRADE_PLANS["none"])
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    clutter_rate = float(recipe.get("clutter", wealth["clutter"]))
    region = REGION_BY_CULTURE.get(recipe.get("culture", ""), recipe.get("region", ""))
    placements: list[dict] = []
    grids: dict[str, Room] = {}
    report = {"dropped": []}

    for room in rooms:
        g = Room(room, doors, windows, stair)
        grids[room["id"]] = g
        kind = room["kind"]
        wanted = list(trade["fixtures"].get(kind, []))
        if kind == "hearth_room":
            wanted = HOME_FIXTURES + (["loom"] if wealth["comfort"] > 0.3 and rng.random() < 0.3 else []) \
                + (["spinning_wheel"] if rng.random() < 0.4 else []) + (["bucket"] if rng.random() < 0.6 else [])
        elif kind in ("bed", "guest_room"):
            wanted = ["bed", "chest"] + (["washstand"] if wealth["comfort"] > 0.4 else []) + (["stool"] if rng.random() < 0.5 else [])
            if int(recipe.get("children", 0)) > 0 and kind == "bed":
                wanted.append("cradle")
        elif kind == "store" and not wanted:
            wanted = ["crate", "barrel", "chest"]
        elif kind == "landing":
            wanted = ["chest"] if rng.random() < 0.5 else []
        wanted += recipe.get("extra_fixtures", {}).get(kind, [])
        placed_here: list[dict] = []
        for name in order_fixtures(wanted):
            p = place_fixture(g, name, placed_here, props, region, rng)
            if p is None:
                report["dropped"].append(f"{room['id']}:{name}")
                continue
            p["wear"] = round(min(1.0, room["wear"] + rng.uniform(-0.1, 0.1)), 2)
            placed_here.append(p)
            placements.append(p)
        # Things on surfaces, kept in their groups, not scattered evenly.
        for surf in list(placed_here):
            groups = SURFACE_GROUPS.get(surf["fixture"], [])
            for gi, group in enumerate(groups):
                if rng.random() > clutter_rate:
                    continue
                placements += on_surface(surf, group, gi, len(groups), props, region, rng, room, placements)

    windows += choose_windows(rooms, doors, stair, recipe, rng, placements)
    # Habits: the specific evidence that one person lives here and not another.
    for habit in recipe.get("habits", []):
        for item, where in HABIT_PROPS.get(habit, []):
            got = place_habit(item, where, habit, rooms, grids, doors, windows, placements, props, region, rng)
            if got is None:
                report["dropped"].append(f"habit:{habit}:{item}")
                continue
            placements.append(got)

    # Where a quest leaves a thing in a room: open floor a body can reach, nearest the middle.
    for room in rooms:
        g = grids[room["id"]]
        room["item_spot"] = item_spot(g)
    report["grids"] = grids
    return placements, report, windows


def order_fixtures(wanted: list[str]) -> list[str]:
    """Anchors first (what others stand beside), then the biggest, then seats and surfaces last."""
    anchors = {FIXTURE.get(w, ("wall", None))[1] for w in wanted}

    def key(name):
        mode, near = FIXTURE.get(name, ("wall", None))
        rank = 0 if name in HEARTHS else 1 if name == "bed" else 2 if name in anchors else 3
        if mode == "seat":
            rank = 5
        elif mode == "surface":
            rank = 6
        return rank
    return sorted(wanted, key=key)


def _prop_entry(name, room, at, yaw, asset, bounds, fixture=True, **extra) -> dict:
    p = {"asset": asset, ("fixture" if fixture else "prop"): name, "room": room["id"],
         "at": [round(at[0], 3), round(at[1], 3), round(at[2], 3)], "yaw": round(yaw, 1)}
    if name in BUILT:
        p["built"] = BUILT[name]
        (x0, y0, z0), (x1, y1, z1) = BUILT_COLLIDER[BUILT[name]]
    else:
        (x0, y0, z0), (x1, y1, z1) = bounds
    if is_clutter(bounds) or extra.get("on"):
        p["clutter"] = True
    else:
        p["collider"] = {"centre": [round((x0 + x1) * 0.5, 3), round((y0 + y1) * 0.5, 3), round((z0 + z1) * 0.5, 3)],
                         "size": [round(x1 - x0, 3), round(y1 - y0, 3), round(z1 - z0, 3)]}
    p["bounds"] = [[round(v, 3) for v in bounds[0]], [round(v, 3) for v in bounds[1]]]
    p.update(extra)
    return p


def place_fixture(g: Room, name: str, placed_here: list[dict], props: Props, region: str, rng) -> dict | None:
    mode, near = FIXTURE.get(name, ("wall", None))
    room = g.r
    if mode == "surface":
        surf = next((s for s in placed_here if s["fixture"] == near), None) or \
            next((s for s in placed_here if s["fixture"] in SURFACE_GROUPS and s.get("collider")), None)
        if surf is None:
            mode = "wall"
        else:
            asset, bounds = props.resolve(name, region, rng)
            got = on_surface(surf, [name], 0, 1, props, region, rng, room, [], fixture=True, fixed=(asset, bounds))
            return got[0] if got else None
    if name in BUILT:
        asset, bounds = "", BUILT_FOOTPRINT[BUILT[name]]
    else:
        asset, bounds = props.resolve(name, region, rng)
    tall = bounds[1][1] > WINDOW_SILL - 0.05
    anchor = next((p for p in placed_here if p["fixture"] == near), None) if near else None
    if mode == "seat":
        wanted = SEAT_FOR.get(name, ("table",))
        tables = [p for t in wanted for p in placed_here if p["fixture"] == t]
        if tables:
            # the table with the fewest seats drawn up to it yet
            tables.sort(key=lambda t: sum(1 for p in placed_here if p.get("_seat_of") == id(t)))
            anchor = tables[0]
        else:
            mode = "wall"       # nothing to draw up to: it stands against a wall
    cands = []
    x0, z0, x1, z1 = rect_of(room)
    step = 0.1
    if mode in ("wall", "corner", "bed"):
        for side in ("N", "S", "E", "W"):
            yaw = HEAD_YAW[side] if mode == "bed" else WALL_YAW[side]
            fp = turned(bounds, yaw)
            if side in ("N", "S"):
                pz = (z0 + WALL_GAP - fp[1]) if side == "N" else (z1 - WALL_GAP - fp[3])
                lo, hi = x0 + WALL_GAP - fp[0], x1 - WALL_GAP - fp[2]
                along = [lo, hi] if mode == "corner" else list(np.arange(lo, hi + 1e-6, step)) + [hi]
                pts = [(a, pz) for a in along]
            else:
                px = (x0 + WALL_GAP - fp[0]) if side == "W" else (x1 - WALL_GAP - fp[2])
                lo, hi = z0 + WALL_GAP - fp[1], z1 - WALL_GAP - fp[3]
                along = [lo, hi] if mode == "corner" else list(np.arange(lo, hi + 1e-6, step)) + [hi]
                pts = [(px, a) for a in along]
            if hi < lo - 1e-6:
                continue
            for px, pz in pts:
                cands.append((px, pz, yaw, side))
    elif mode == "seat" and anchor is not None:
        ax, az = anchor["at"][0], anchor["at"][2]
        afp = turned(anchor["bounds"], anchor["yaw"])
        ar = (ax + afp[0], az + afp[1], ax + afp[2], az + afp[3])
        # Drawn up to one of the table's sides, its front to the table, a hand's gap off its edge.
        for side, yaw in (("N", 0.0), ("S", 180.0), ("W", 90.0), ("E", 270.0)):
            fp = turned(bounds, yaw)
            if side == "N":
                pz = ar[1] - GAP - fp[3]
                pts = [(a, pz) for a in np.arange(ar[0] - fp[0], ar[2] - fp[2] + 1e-6, 0.1)]
            elif side == "S":
                pz = ar[3] + GAP - fp[1]
                pts = [(a, pz) for a in np.arange(ar[0] - fp[0], ar[2] - fp[2] + 1e-6, 0.1)]
            elif side == "W":
                px = ar[0] - GAP - fp[2]
                pts = [(px, a) for a in np.arange(ar[1] - fp[1], ar[3] - fp[3] + 1e-6, 0.1)]
            else:
                px = ar[2] + GAP - fp[0]
                pts = [(px, a) for a in np.arange(ar[1] - fp[1], ar[3] - fp[3] + 1e-6, 0.1)]
            for px, pz in pts:
                cands.append((float(px), float(pz), yaw, side))
    else:
        # Free in the room: a table in the middle, a working thing near what it works with.
        for yaw in (0.0, 90.0, 180.0, 270.0) if mode == "open" else (0.0, 90.0):
            fp = turned(bounds, yaw)
            for px in np.arange(x0 + 0.5 - fp[0], x1 - 0.5 - fp[2] + 1e-6, step):
                for pz in np.arange(z0 + 0.5 - fp[1], z1 - 0.5 - fp[3] + 1e-6, step):
                    cands.append((float(px), float(pz), yaw, None))
    if not cands:
        return None
    scored = []
    cx, cz = x0 + room["w"] * 0.5, z0 + room["d"] * 0.5
    door_pts = g.targets
    for px, pz, yaw, side in cands:
        fp = turned(bounds, yaw)
        rect = (px + fp[0], pz + fp[1], px + fp[2], pz + fp[3])
        if not g.inside(rect, WALL_GAP - 0.005):
            continue
        if not g.free(rect, tall):
            continue
        score = rng.uniform(0.0, 0.6)
        if anchor is not None:
            ax, az = anchor["at"][0], anchor["at"][2]
            score += 1.2 * math.hypot(px - ax, pz - az)
        if name in HEARTHS:
            # The fire in the middle of a long wall, as far from the door as the room allows.
            if side in ("N", "S"):
                score += 2.0 * abs(px - cx) - 0.4 * room["w"]
            else:
                score += 2.0 * abs(pz - cz) - 0.4 * room["d"]
            score -= 0.8 * min((math.hypot(px - t[0], pz - t[1]) for t in door_pts), default=0.0)
        elif mode == "bed":
            score -= 1.5 * min((math.hypot(px - t[0], pz - t[1]) for t in door_pts), default=0.0)
            score += 1.0 * min(abs(rect[0] - x0), abs(x1 - rect[2]), abs(rect[1] - z0), abs(z1 - rect[3]))
        elif mode in ("centre", "open") and anchor is None:
            score += 1.5 * math.hypot(px - cx, pz - cz)
        elif mode == "open":
            score += 0.3 * math.hypot(px - cx, pz - cz)
        scored.append((score, px, pz, yaw, rect))
    scored.sort(key=lambda s: s[0])
    y = room["floor_y"]
    clutter = is_clutter(bounds)
    tried = 0
    for score, px, pz, yaw, rect in scored:
        if tried > 500:
            break
        if not clutter and any(overlap(rect, band) for _, band in g.fronts):
            continue        # never in front of a chest, a bed or the fire
        tried += 1
        if clutter:
            g.mark(g.clutter, rect)
            return _prop_entry(name, room, (px, y, pz), yaw, asset, bounds)
        trial = g.solid.copy()
        su, sv = g.cells(rect)
        trial[su, sv] = True
        fronts = list(g.fronts)
        band = None
        if name in CONTAINERS or name in HEARTHS or name in WORKABLE or mode == "bed":
            # A bed is got into from whichever long side is open; everything else from its front.
            band = bed_band(rect, g) if mode == "bed" else g.front_band(rect, yaw)
            fronts.append((name, band))
        if not g.connected(trial, fronts):
            continue
        g.solid = trial
        if band is not None:
            g.fronts.append((name, band))
        got = _prop_entry(name, room, (px, y, pz), yaw, asset, bounds)
        if mode == "seat" and anchor is not None:
            got["_seat_of"] = id(anchor)
        return got
    return None


def bed_band(rect, g: Room) -> tuple:
    """The open long side of a bed: whichever long edge is further from a wall."""
    x0, z0, x1, z1 = rect
    r = g.r
    if (x1 - x0) >= (z1 - z0):
        a = (x0, z0 - 0.9, x1, z0)
        b = (x0, z1, x1, z1 + 0.9)
        return a if (z0 - r["z"]) > (r["z"] + r["d"] - z1) else b
    a = (x0 - 0.9, z0, x0, z1)
    b = (x1, z0, x1 + 0.9, z1)
    return a if (x0 - r["x"]) > (r["x"] + r["w"] - x1) else b


def on_surface(surf: dict, group: list[str], gi: int, ngroups: int, props: Props, region: str, rng, room: dict,
               placements: list[dict], fixture: bool = False, fixed=None) -> list[dict]:
    """Things set down on a surface, in a huddle at one end of it, as a person leaves them: inside
    its top, touching nothing else on it."""
    sfp = turned(surf["bounds"], surf["yaw"])
    sx, sy, sz = surf["at"]
    top = sy + surf["bounds"][1][1]
    inset = 0.04
    rect = (sx + sfp[0] + inset, sz + sfp[1] + inset, sx + sfp[2] - inset, sz + sfp[3] - inset)
    if rect[2] <= rect[0] or rect[3] <= rect[1]:
        return []
    others = []
    for p in placements:
        if p.get("on_index") == surf.get("index") and p.get("on") == surf.get("fixture") and p.get("surface_at") == surf["at"]:
            ofp = turned(p["bounds"], p["yaw"])
            others.append((p["at"][0] + ofp[0], p["at"][2] + ofp[1], p["at"][0] + ofp[2], p["at"][2] + ofp[3]))
    long_x = (rect[2] - rect[0]) >= (rect[3] - rect[1])
    length = (rect[2] - rect[0]) if long_x else (rect[3] - rect[1])
    # Each group huddles in its own share of the surface.
    share = length / max(ngroups, 1)
    start = share * gi + rng.uniform(0.0, max(share * 0.3, 0.0))
    out = []
    cursor = start
    for item in group:
        if fixed is not None:
            asset, bounds = fixed
        else:
            asset, bounds = props.resolve(item, region, rng)
        yaw = float(rng.choice([0.0, 90.0, 180.0, 270.0]))
        fp = turned(bounds, yaw)
        w_along = (fp[2] - fp[0]) if long_x else (fp[3] - fp[1])
        w_across = (fp[3] - fp[1]) if long_x else (fp[2] - fp[0])
        across_room = ((rect[3] - rect[1]) if long_x else (rect[2] - rect[0])) - w_across
        if across_room < 0 or w_along > length:
            continue
        done = False
        for tries in range(12):
            a = cursor + (0.0 if tries == 0 else rng.uniform(-0.2, share))
            b = rng.uniform(0.0, across_room)
            if long_x:
                px, pz = rect[0] + a - fp[0], rect[1] + b - fp[1]
            else:
                px, pz = rect[0] + b - fp[0], rect[1] + a - fp[1]
            r2 = (px + fp[0], pz + fp[1], px + fp[2], pz + fp[3])
            if r2[0] < rect[0] - 1e-6 or r2[1] < rect[1] - 1e-6 or r2[2] > rect[2] + 1e-6 or r2[3] > rect[3] + 1e-6:
                continue
            if any(overlap(grow(r2, 0.01), o) for o in others):
                continue
            others.append(r2)
            cursor = a + w_along + 0.03
            p = _prop_entry(item, room, (px, top, pz), yaw, asset, bounds, fixture=fixture,
                            on=surf["fixture"], surface_at=surf["at"], group=f"{surf['fixture']}_{gi}")
            if fixture:
                p.pop("clutter", None)
                p["clutter"] = True
            out.append(p)
            done = True
            break
        if not done:
            continue
    return out


def place_habit(item, where, habit, rooms, grids, doors, windows, placements, props, region, rng):
    hearth_room = next((r for r in rooms if r["kind"] == "hearth_room"), rooms[0])
    asset, bounds = props.resolve(item, region, rng)
    if where.startswith("on:"):
        kinds = where[3:].split("|")
        for k in kinds:
            surfs = [p for p in placements if p.get("fixture") == k and not p.get("on")]
            surfs.sort(key=lambda p: (p["room"] != hearth_room["id"], p["room"]))
            for s in surfs:
                room = next(r for r in rooms if r["id"] == s["room"])
                got = on_surface(s, [item], 0, 1, props, region, rng, room, placements, fixed=(asset, bounds))
                if got:
                    got[0]["habit"] = habit
                    return got[0]
        return None
    if where == "window":
        ws = sorted(windows, key=lambda w: w["room"] != hearth_room["id"])
        for w in ws:
            room = next(r for r in rooms if r["id"] == w["room"])
            x, yc, z = w["at"]
            if any(p.get("habit") == habit and p["at"][0] == round(x, 3) for p in placements):
                continue
            return _prop_entry(item, room, (x, yc - WINDOW_H * 0.5, z), float(rng.uniform(0, 360)), asset, bounds,
                               fixture=False, habit=habit, on="window")
        return None
    if where == "door":
        front = next(d for d in doors if d["kind"] == "front")
        room = next(r for r in rooms if r["id"] == front["between"][1])
        g = grids[room["id"]]
        x = front["at"][0]
        half = DOOR_W * 0.5 + DOOR_MARGIN
        fp = turned(bounds, 0.0)
        for off in (half + 0.05 - fp[0], -(half + 0.05) - fp[2], half + 0.35 - fp[0], -(half + 0.35) - fp[2]):
            px, pz = x + off, room["z"] + WALL_GAP - fp[1]
            rect = (px + fp[0], pz + fp[1], px + fp[2], pz + fp[3])
            if g.inside(rect) and g.free(rect, False, g.clutter):
                g.mark(g.clutter, rect)
                return _prop_entry(item, room, (px, room["floor_y"], pz), float(rng.uniform(-15, 15)), asset, bounds,
                                   fixture=False, habit=habit)
        return None
    # Beside a fixture on the floor (the hearth, the settle), or in a corner of the hearth room.
    anchors = [p for p in placements if p.get("fixture") in (HEARTHS if where == "hearth" else (where,)) and not p.get("on")]
    anchors.sort(key=lambda p: p["room"] != hearth_room["id"])
    room = next((r for r in rooms if anchors and r["id"] == anchors[0]["room"]), hearth_room)
    g = grids[room["id"]]
    cands = []
    x0, z0, x1, z1 = rect_of(room)
    yaw = float(rng.choice([0.0, 90.0, 180.0, 270.0]))
    fp = turned(bounds, yaw)
    for px in np.arange(x0 + WALL_GAP - fp[0], x1 - WALL_GAP - fp[2] + 1e-6, 0.1):
        for pz in np.arange(z0 + WALL_GAP - fp[1], z1 - WALL_GAP - fp[3] + 1e-6, 0.1):
            rect = (px + fp[0], pz + fp[1], px + fp[2], pz + fp[3])
            wall = min(rect[0] - x0, x1 - rect[2], rect[1] - z0, z1 - rect[3])
            if where == "corner":
                wall2 = sorted([rect[0] - x0, x1 - rect[2], rect[1] - z0, z1 - rect[3]])[1]
                score = wall + wall2
            elif anchors:
                a = anchors[0]
                afp = turned(a["bounds"], a["yaw"])
                ar = (a["at"][0] + afp[0], a["at"][2] + afp[1], a["at"][0] + afp[2], a["at"][2] + afp[3])
                dx = max(ar[0] - rect[2], rect[0] - ar[2], 0.0)
                dz = max(ar[1] - rect[3], rect[1] - ar[3], 0.0)
                score = math.hypot(dx, dz) + 0.5 * wall
            else:
                score = wall
            cands.append((score + rng.uniform(0, 0.15), float(px), float(pz), rect))
    cands.sort(key=lambda c: c[0])
    clutter = is_clutter(bounds)
    for score, px, pz, rect in cands[:400]:
        if not g.free(rect, bounds[1][1] > WINDOW_SILL - 0.05, g.clutter):
            continue
        if not clutter:
            # Nobody's things go in front of a chest or across the fire, and the way stays open.
            if any(overlap(rect, band) for _, band in g.fronts):
                continue
            trial = g.solid.copy()
            su, sv = g.cells(rect)
            trial[su, sv] = True
            if not g.connected(trial):
                continue
            g.solid = trial
        else:
            g.mark(g.clutter, rect)
        return _prop_entry(item, room, (px, room["floor_y"], pz), yaw, asset, bounds, fixture=False, habit=habit)
    return None


def item_spot(g: Room) -> list[float]:
    walk = g.walkable() & ~g.keep & ~g.clutter
    labels, _ = ndimage.label(walk, structure=np.ones((3, 3)))
    cx, cz = g.r["x"] + g.r["w"] * 0.5, g.r["z"] + g.r["d"] * 0.5
    best, best_d = None, 1e9
    us, vs = np.nonzero(walk)
    for u, v in zip(us, vs):
        x, z = g.x0 + (u + 0.5) * RES, g.z0 + (v + 0.5) * RES
        dd = math.hypot(x - cx, z - cz)
        if dd < best_d:
            best, best_d = (x, z), dd
    if best is None:
        best = (cx, cz)
    return [round(best[0], 3), g.r["floor_y"], round(best[1], 3)]


def lights_for(rooms: list[dict], placements: list[dict], recipe: dict) -> list[dict]:
    """Hearths, candles and lanterns, warm and low, one strong source per lived-in room."""
    out = []
    for room in rooms:
        hearth = next((p for p in placements if p.get("fixture") in HEARTHS and p["room"] == room["id"]), None)
        if hearth:
            fx, fz = facing(hearth["yaw"])
            if hearth.get("built"):
                # in the mouth of the fireplace, low, where the fire is
                out_by, up = FP_D * 0.5 + 0.3, 0.45
            else:
                out_by, up = hearth["bounds"][1][2] + 0.5, 0.7
            at = [hearth["at"][0] + fx * out_by, hearth["at"][1] + up, hearth["at"][2] + fz * out_by]
            out.append({"room": room["id"], "at": [round(v, 3) for v in at],
                        "color": "#ff9a42" if hearth["fixture"] != "forge" else "#ff7b2a",
                        "energy": 4.2 if hearth["fixture"] == "forge" else 3.0, "range": 9.0, "flicker": 0.4, "shadow": True})
        candles = [p for p in placements if p.get("prop") in ("candlestick", "candle_stub", "lantern") and p["room"] == room["id"]]
        for c in candles[:2]:
            out.append({"room": room["id"], "at": [c["at"][0], round(c["at"][1] + 0.25, 3), c["at"][2]],
                        "color": "#ffca7a", "energy": 1.1, "range": 4.5, "flicker": 0.35, "shadow": False})
        if not hearth and not candles:
            out.append({"room": room["id"], "at": [room["centre"][0], round(room["floor_y"] + 2.2, 3), room["centre"][2]],
                        "color": "#ffd9a0", "energy": 0.8, "range": 6.0, "flicker": 0.0, "shadow": False})
    return out


BOOK_PROPS = ("book_single", "book_stack", "roll_book", "ledger")


def shelve(recipe: dict, placements: list[dict], props: Props, rooms: list[dict], rng) -> None:
    """A recipe's `books` names what lies on a room's book props: {"hall": {"book": id, "fixed":
    true}}. The first book prop in that room carries it (house_interior.gd makes it readable); a
    room whose dressing put no book down gets one on its first surface that will take it.
    Otherwise the house's shelf gets what the culture pool picks. A room with nowhere to put a
    book is an error, since the recipe has promised something that would not be there."""
    region = REGION_BY_CULTURE.get(recipe.get("culture", ""), "")
    for room_id, spec in (recipe.get("books") or {}).items():
        target = next((p for p in placements if p.get("room") == room_id and p.get("prop") in BOOK_PROPS), None)
        if target is None:
            room = next((r for r in rooms if r["id"] == room_id), None)
            for surf in [p for p in placements if p.get("room") == room_id and p.get("fixture") in SURFACE_GROUPS and not p.get("on")]:
                got = on_surface(surf, ["book_single"], 0, 1, props, region, rng, room, placements) if room else []
                if got:
                    placements.append(got[0])
                    target = got[0]
                    break
        if target is None:
            raise ShelveError("%s: the recipe puts a book in '%s' and nothing there holds one" % (recipe.get("id", "?"), room_id))
        target.update({k: v for k, v in spec.items() if k in ("book", "item", "fixed")})


def check(rooms, doors, placements, grids) -> list[str]:
    """What breaks the rules, said plainly: an empty list is a house that keeps them."""
    faults = []
    by_room: dict[str, list] = {}
    for i, p in enumerate(placements):
        fp = turned(p["bounds"], p["yaw"])
        rect = (p["at"][0] + fp[0], p["at"][2] + fp[1], p["at"][0] + fp[2], p["at"][2] + fp[3])
        by_room.setdefault(p["room"], []).append((i, p, rect))
    for room in rooms:
        g = grids[room["id"]]
        items = by_room.get(room["id"], [])
        for i, p, rect in items:
            name = p.get("fixture", p.get("prop"))
            if p.get("on"):
                continue
            if not g.inside(rect, 0.0):
                faults.append(f"{room['id']}: {name} crosses a wall")
            for zn in g.zones + g.stair_zones:
                if overlap(rect, zn, 0.01):
                    faults.append(f"{room['id']}: {name} stands in a door's or the stair's clear zone")
        solids = [(i, p, r) for i, p, r in items if p.get("collider")]
        for a in range(len(solids)):
            for b in range(a + 1, len(solids)):
                if overlap(solids[a][2], solids[b][2], 0.01):
                    faults.append(f"{room['id']}: {solids[a][1].get('fixture', solids[a][1].get('prop'))} and "
                                  f"{solids[b][1].get('fixture', solids[b][1].get('prop'))} overlap")
        if not g.connected():
            faults.append(f"{room['id']}: no {PATH} m way between its doors and everything that needs one")
    return faults


class ShelveError(Exception):
    pass


# What a house is not itself without: dropping one of these costs a whole attempt.
MUST = {"forge", "anvil", "hearth", "cook_hearth", "bread_oven", "bed", "table", "long_table", "writing_desk",
        "roll_desk", "name_table", "alembic", "mortar_bench", "counter", "bar", "millstone", "mash_tun", "copper",
        "barrel_rack", "deed_chest", "kneading_table", "net_rack", "stall", "weapon_rack", "chest"}
ATTEMPTS = 12


def cost_of(report: dict, faults: list[str]) -> float:
    cost = 1000.0 * len(faults)
    for d in report["dropped"]:
        kind = d.split(":")[-1]
        cost += 60.0 if kind in MUST else 1.0 if kind in ("stool", "chair", "bench", "loom", "washstand") else 4.0
    return cost


def build(recipe: dict, out_root: str, quiet: bool = False, props: Props | None = None) -> dict:
    """Plans and dresses the house several ways, and keeps the one that breaks no rule and leaves
    out least: the seed makes every attempt the same every time, so the choice is too."""
    name = recipe["name_slug"]
    props = props or Props()
    best = None
    for variant in range(ATTEMPTS):
        rng = np.random.default_rng(int(recipe.get("seed", 1)) + variant * 104729)
        rooms, doors, stair = plan(recipe, rng, variant)
        placements, report, windows = dress(rooms, doors, stair, recipe, props, rng)
        try:
            shelve(recipe, placements, props, rooms, rng)
            shelved = True
        except ShelveError:
            shelved = False
        faults = check(rooms, doors, placements, report["grids"])
        cost = cost_of(report, faults) + (0.0 if shelved else 500.0)
        if best is None or cost < best[0]:
            best = (cost, variant, rng, rooms, doors, stair, placements, report, windows, shelved)
        if cost < 4.0:
            break
    cost, variant, rng, rooms, doors, stair, placements, report, windows, shelved = best
    if not shelved:
        shelve(recipe, placements, props, rooms, rng)      # raises, saying which room
    shell, timber, col = build_shell(rooms, doors, windows, stair)
    masonry, embers = [], []
    for p in placements:
        if p.get("built") == "fireplace":
            m, e, t = fireplace(p)
            masonry += m
            embers += e
            timber = trimesh.util.concatenate([timber] + t) if timber is not None else trimesh.util.concatenate(t)
    faults = check(rooms, doors, placements, report["grids"])
    lights = lights_for(rooms, placements, recipe)
    report["variant"] = variant

    folder = os.path.join(out_root, name)
    os.makedirs(folder, exist_ok=True)
    shell.export(os.path.join(folder, f"{name}.glb"))
    if timber is not None:
        timber.export(os.path.join(folder, f"{name}_timber.glb"))
    col.export(os.path.join(folder, f"{name}_col.glb"))
    if masonry:
        scene = trimesh.Scene()
        scene.add_geometry(trimesh.util.concatenate(masonry), node_name="masonry", geom_name="masonry")
        scene.add_geometry(trimesh.util.concatenate(embers), node_name="embers", geom_name="embers")
        scene.export(os.path.join(folder, f"{name}_masonry.glb"))

    stairs = []
    if stair is not None:
        stairs.append({"room": stair["room"], "landing": "landing",
                       "toe": [round(v, 3) for v in stair_point(stair, 0.0, STAIR_W * 0.5)],
                       "top": [round(v, 3) for v in stair_point(stair, RUN, STAIR_W * 0.5)],
                       "dir": list(stair["dir"]), "in": list(stair["in"]), "width": STAIR_W, "run": RUN, "rise": LEVEL,
                       "well": [round(v, 3) for v in stair_rect(stair, WELL_FROM, RUN, 0.0, STAIR_W)]})
    zones = []
    for d in doors:
        for rid in d["between"]:
            room = next((r for r in rooms if r["id"] == rid), None)
            if room is None:
                continue
            for zn in door_zones(room, [d]):
                zones.append({"room": rid, "floor_y": room["floor_y"], "rect": [round(v, 3) for v in zn]})
    meta = {
        "id": recipe["id"], "name": recipe.get("name", name), "generator": "house_forge", "version": 2,
        "seed": int(recipe.get("seed", 1)), "resident": recipe.get("resident", ""), "trade": recipe.get("trade", "none"),
        "wealth": int(recipe.get("wealth", 1)), "household": int(recipe.get("household", 2)),
        "story": recipe.get("story", ""), "who_was_here": recipe.get("who_was_here", ""),
        "unique_object": recipe.get("unique_object", ""), "habits": recipe.get("habits", []),
        "culture": recipe.get("culture", ""), "place": recipe.get("place", ""),
        "tris": int(len(shell.faces)) + (int(len(timber.faces)) if timber is not None else 0),
        "has_timber": timber is not None, "has_masonry": bool(masonry),
        "rooms": [{k: v for k, v in r.items() if k not in ("depth",)} for r in rooms],
        "doors": doors, "door_zones": zones, "windows": windows, "stairs": stairs,
        "floors": floors_for(rooms, stair), "placements": placements, "lights": lights,
        "features": recipe.get("features", []),
        "entrance": doors[0]["at"] if doors else [0, 0, 0],
        "rules": {"path": PATH, "door_clear": CLEAR, "door_margin": DOOR_MARGIN, "clutter_h": CLUTTER_H, "clutter_w": CLUTTER_W},
    }
    for p in placements:
        for k in [k for k in p if k.startswith("_")]:
            del p[k]
    with open(os.path.join(folder, f"{name}.meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    if not quiet:
        solid = sum(1 for p in placements if p.get("collider"))
        print(f"{name}: {len(rooms)} rooms, {meta['tris']:,} tris, {len(placements)} props ({solid} solid), "
              f"{len(doors)} doors, {len(windows)} windows, {len(lights)} lights"
              + (f"; dropped {', '.join(report['dropped'])}" if report["dropped"] else ""))
        for fault in faults:
            print(f"  FAULT {name}: {fault}")
    meta["_faults"] = faults
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("recipes", nargs="+")
    ap.add_argument("--out", default="game/assets/models/interior")
    args = ap.parse_args()
    props = Props()
    bad = 0
    for path in args.recipes:
        recipe = json.load(open(path))
        recipe.setdefault("name_slug", os.path.splitext(os.path.basename(path))[0])
        meta = build(recipe, args.out, props=props)
        bad += len(meta["_faults"])
    if bad:
        print(f"{bad} rule(s) broken")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
