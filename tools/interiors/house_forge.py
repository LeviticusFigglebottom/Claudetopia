#!/usr/bin/env python3
"""House and shop interiors for Wickmere, built from who lives there.

A house is not a box: it is a trade, a household and a set of habits that decide how many
rooms there are, what is in them, and where the wear shows. The recipe says who lives
here; this decides the plan, then dresses it densely and logically — objects on surfaces,
grouped by use, with evidence of the day.

    tools/interiors/house_forge.py recipes/houses/osric_smithy.json --out game/assets/models/interior

Output per recipe:
    <name>/<name>.glb        walls, floor, ceiling, stairs, fixed joinery
    <name>/<name>_col.glb    collision
    <name>/<name>.meta.json  rooms, doors, windows, light sources, prop placements, story
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
import trimesh

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
                  "fixtures": {"stillroom": ["alembic", "drying_rack", "ingredient_shelf", "mortar_bench"],
                               "shop_front": ["counter", "bottle_shelf"]},
                  "wear": {"stillroom": 0.6}},
    "innkeeper": {"rooms": ["tap_room", "kitchen", "cellar", "guest_room", "bed"], "workshop_area": 40, "noise": "loud",
                  "fixtures": {"tap_room": ["bar", "long_table", "bench", "hearth", "board"],
                               "kitchen": ["cook_hearth", "prep_table", "pot_rack"],
                               "cellar": ["barrel_rack", "barrel"],
                               "guest_room": ["bed", "chest", "washstand"]},
                  "wear": {"tap_room": 0.95, "kitchen": 0.8}},
    "farmer": {"rooms": ["hearth_room", "byre", "store", "bed"], "workshop_area": 20, "noise": "quiet",
               "fixtures": {"byre": ["stall", "hay_pile", "yoke", "pitchfork"],
                            "store": ["grain_bin", "root_crate", "seed_sacks"]},
               "wear": {"byre": 0.8}},
    "steward": {"rooms": ["study", "hall", "hearth_room", "bed"], "workshop_area": 16, "noise": "quiet",
                "fixtures": {"study": ["writing_desk", "deed_chest", "shelf", "strongbox"],
                             "hall": ["long_table", "chair", "sideboard"]},
                "wear": {"study": 0.3}},
    "fisher": {"rooms": ["net_room", "hearth_room", "bed"], "workshop_area": 18, "noise": "quiet",
               "fixtures": {"net_room": ["net_rack", "drying_line", "crate", "oar_rack", "tar_pot"]},
               "wear": {"net_room": 0.7}},
    "warden": {"rooms": ["muster_room", "hearth_room", "store", "bed"], "workshop_area": 22, "noise": "quiet",
               "fixtures": {"muster_room": ["weapon_rack", "roll_desk", "map_board", "bench"],
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

WALL_T = 0.28
STOREY_H = 2.75
DOOR_W, DOOR_H = 0.95, 2.05
WINDOW_W, WINDOW_H, WINDOW_SILL = 0.85, 1.05, 0.95


def plan(recipe: dict, rng: np.random.Generator) -> list[dict]:
    """Lay rooms out as a packed plan: a spine corridor of rooms off the front door.

    Rooms are placed left to right in a row, then wrapped into a second row behind, which
    gives the L and double-pile plans real village houses have.
    """
    trade = TRADE_PLANS.get(recipe.get("trade", "none"), TRADE_PLANS["none"])
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    household = int(recipe.get("household", 2))
    wanted = list(trade["rooms"])
    for extra in recipe.get("extra_rooms", []):
        wanted.append(extra)
    if household > 3 and "bed" in wanted:
        wanted.insert(wanted.index("bed") + 1, "bed")

    rooms = []
    row_x = 0.0
    row = 0
    row_depth = 0.0
    row_width_limit = float(recipe.get("width_limit", 11.0)) * wealth["room_scale"]
    for i, kind in enumerate(wanted):
        base = ROOM_SIZE.get(kind, (4.0, 3.6))
        w = base[0] * wealth["room_scale"] * rng.uniform(0.94, 1.08)
        d = base[1] * wealth["room_scale"] * rng.uniform(0.94, 1.08)
        if kind == "bed" and household > 4:
            w *= 1.15
        if row_x + w > row_width_limit and row_x > 0:
            row += 1
            row_x = 0.0
        rooms.append({
            "id": f"{kind}_{sum(1 for r in rooms if r['kind'] == kind) + 1}" if any(r["kind"] == kind for r in rooms) else kind,
            "kind": kind, "x": row_x, "z": 0.0, "w": w, "d": d, "row": row,
            "storey": 0, "wear": float(trade["wear"].get(kind, 0.25)),
        })
        row_x += w
        row_depth = max(row_depth, d)

    # Second row sits behind the first; give every room its true z by row depth.
    depths = {}
    for r in rooms:
        depths[r["row"]] = max(depths.get(r["row"], 0.0), r["d"])
    z = 0.0
    for row_idx in sorted(depths):
        for r in rooms:
            if r["row"] == row_idx:
                r["z"] = z
        z += depths[row_idx] + WALL_T

    # Upstairs, if the purse runs to it: beds go up, work stays down.
    if wealth["storeys"] > 1 and len(rooms) > 2:
        upstairs = [r for r in rooms if r["kind"] in ("bed", "guest_room", "study")]
        if upstairs:
            for r in upstairs:
                r["storey"] = 1
            rooms.append({"id": "landing", "kind": "landing", "x": 0.0, "z": 0.0,
                          "w": ROOM_SIZE["landing"][0], "d": ROOM_SIZE["landing"][1],
                          "row": 0, "storey": 1, "wear": 0.2})
            # Re-pack the upper storey on its own grid.
            ux = 0.0
            for r in [x for x in rooms if x["storey"] == 1]:
                r["x"] = ux
                r["z"] = 0.0
                ux += r["w"]
    return rooms


def box(centre, size) -> trimesh.Trimesh:
    m = trimesh.creation.box(extents=size)
    m.apply_translation(centre)
    return m


def build_shell(rooms: list[dict], recipe: dict, rng: np.random.Generator):
    """Walls, floors and ceilings as solid geometry, with doors and windows cut out."""
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    solids = []
    beams = []
    holes = []
    doors = []
    windows = []

    by_storey: dict[int, list[dict]] = {}
    for r in rooms:
        by_storey.setdefault(r["storey"], []).append(r)

    for storey, group in sorted(by_storey.items()):
        y0 = storey * STOREY_H
        for r in group:
            cx = r["x"] + r["w"] * 0.5
            cz = r["z"] + r["d"] * 0.5
            # Floor slab (ground floor gets a thicker base).
            t = 0.35 if storey == 0 else 0.22
            solids.append(box((cx, y0 - t * 0.5, cz), (r["w"] + WALL_T * 2, t, r["d"] + WALL_T * 2)))
            # Four walls as a hollow box: outer solid minus inner void.
            outer = box((cx, y0 + STOREY_H * 0.5, cz), (r["w"] + WALL_T * 2, STOREY_H, r["d"] + WALL_T * 2))
            inner = box((cx, y0 + STOREY_H * 0.5, cz), (r["w"], STOREY_H + 0.1, r["d"]))
            solids.append(("wall", outer, inner))
            r["centre"] = [round(cx, 2), round(y0, 2), round(cz, 2)]
            r["floor_y"] = round(y0, 2)

        # Ceiling of the top storey, and the beams under every ceiling. Exposed joists
        # are most of what tells you a room is a room and not a white box.
        for r in group:
            cx = r["x"] + r["w"] * 0.5
            cz = r["z"] + r["d"] * 0.5
            if storey == max(by_storey):
                solids.append(box((cx, y0 + STOREY_H + 0.11, cz), (r["w"] + WALL_T * 2, 0.22, r["d"] + WALL_T * 2)))
            # Joists run across the shorter span, as they would be framed.
            span_x = r["w"] < r["d"]
            spacing = 0.78
            n = max(int((r["d"] if span_x else r["w"]) / spacing), 2)
            for k in range(1, n):
                t = k / n
                depth = 0.16 + 0.04 * ((k % 3) - 1) * 0.5
                if span_x:
                    bz = r["z"] + r["d"] * t
                    beams.append(box((cx, y0 + STOREY_H - depth * 0.5, bz), (r["w"] + WALL_T, depth, 0.13)))
                else:
                    bx = r["x"] + r["w"] * t
                    beams.append(box((bx, y0 + STOREY_H - depth * 0.5, cz), (0.13, depth, r["d"] + WALL_T)))
            # A wall plate the joists sit on, all the way round.
            plate = 0.14
            for bx, bz, sx, sz in (
                (cx, r["z"] - plate * 0.3, r["w"] + WALL_T, plate),
                (cx, r["z"] + r["d"] + plate * 0.3, r["w"] + WALL_T, plate),
                (r["x"] - plate * 0.3, cz, plate, r["d"] + WALL_T),
                (r["x"] + r["w"] + plate * 0.3, cz, plate, r["d"] + WALL_T),
            ):
                beams.append(box((bx, y0 + STOREY_H - 0.09, bz), (sx, 0.18, sz)))

    # Doorways between rooms that share a wall, and one front door.
    for storey, group in sorted(by_storey.items()):
        y0 = storey * STOREY_H
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                shared = shared_wall(a, b)
                if shared is None:
                    continue
                axis, pos, lo, hi = shared
                mid = (lo + hi) * 0.5
                if axis == "x":
                    centre = (pos, y0 + DOOR_H * 0.5, mid)
                    size = (WALL_T * 3.0, DOOR_H, DOOR_W)
                else:
                    centre = (mid, y0 + DOOR_H * 0.5, pos)
                    size = (DOOR_W, DOOR_H, WALL_T * 3.0)
                holes.append(box(centre, size))
                doors.append({"between": [a["id"], b["id"]], "at": [round(c, 2) for c in centre],
                              "yaw": 90.0 if axis == "x" else 0.0, "kind": "internal"})

    # Front door on the outer face of the first ground-floor room.
    front = by_storey[0][0]
    fx = front["x"] + front["w"] * 0.5
    fz = front["z"] - WALL_T
    holes.append(box((fx, DOOR_H * 0.5, fz), (DOOR_W, DOOR_H, WALL_T * 3.0)))
    doors.append({"between": ["outside", front["id"]], "at": [round(fx, 2), 0.0, round(fz, 2)], "yaw": 0.0, "kind": "front"})

    # Windows on outer walls, as many as the purse allows.
    outer_faces = find_outer_faces(rooms)
    rng.shuffle(outer_faces)
    for face in outer_faces[: wealth["windows"]]:
        axis, pos, lo, hi, storey, room_id = face
        mid = (lo + hi) * 0.5
        y = storey * STOREY_H + WINDOW_SILL + WINDOW_H * 0.5
        if axis == "x":
            centre = (pos, y, mid)
            size = (WALL_T * 3.0, WINDOW_H, WINDOW_W)
        else:
            centre = (mid, y, pos)
            size = (WINDOW_W, WINDOW_H, WALL_T * 3.0)
        holes.append(box(centre, size))
        windows.append({"room": room_id, "at": [round(c, 2) for c in centre], "yaw": 90.0 if axis == "x" else 0.0,
                        "normal": [1.0 if axis == "x" else 0.0, 0.0, 0.0 if axis == "x" else 1.0]})

    # Boolean the lot: walls first (outer minus inner), then subtract openings.
    parts = []
    for item in solids:
        if isinstance(item, tuple):
            _, outer, inner = item
            parts.append(outer.difference(inner))
        else:
            parts.append(item)
    shell = trimesh.util.concatenate(parts)
    if holes:
        shell = shell.difference(trimesh.util.concatenate(holes))
    timber = trimesh.util.concatenate(beams) if beams else None
    return shell, timber, doors, windows


def shared_wall(a: dict, b: dict):
    """If two rooms touch, return (axis, position, overlap_lo, overlap_hi)."""
    ax0, ax1 = a["x"], a["x"] + a["w"]
    az0, az1 = a["z"], a["z"] + a["d"]
    bx0, bx1 = b["x"], b["x"] + b["w"]
    bz0, bz1 = b["z"], b["z"] + b["d"]
    tol = WALL_T * 1.6
    if abs(ax1 - bx0) < tol or abs(bx1 - ax0) < tol:
        lo, hi = max(az0, bz0), min(az1, bz1)
        if hi - lo > DOOR_W * 1.3:
            return ("x", (ax1 + bx0) * 0.5 if abs(ax1 - bx0) < tol else (bx1 + ax0) * 0.5, lo, hi)
    if abs(az1 - bz0) < tol or abs(bz1 - az0) < tol:
        lo, hi = max(ax0, bx0), min(ax1, bx1)
        if hi - lo > DOOR_W * 1.3:
            return ("z", (az1 + bz0) * 0.5 if abs(az1 - bz0) < tol else (bz1 + az0) * 0.5, lo, hi)
    return None


def find_outer_faces(rooms: list[dict]) -> list:
    """Wall faces with nothing on the other side: where windows can go."""
    faces = []
    for r in rooms:
        for axis, pos, lo, hi in (
            ("x", r["x"], r["z"], r["z"] + r["d"]),
            ("x", r["x"] + r["w"], r["z"], r["z"] + r["d"]),
            ("z", r["z"], r["x"], r["x"] + r["w"]),
            ("z", r["z"] + r["d"], r["x"], r["x"] + r["w"]),
        ):
            blocked = False
            for other in rooms:
                if other is r or other["storey"] != r["storey"]:
                    continue
                s = shared_wall(r, other)
                if s and s[0] == axis and abs(s[1] - pos) < WALL_T * 2:
                    blocked = True
                    break
            if not blocked and hi - lo > WINDOW_W * 1.4:
                faces.append((axis, pos, lo + 0.6, hi - 0.6, r["storey"], r["id"]))
    return faces


# ---------------------------------------------------------------------------------------
# Dressing: what is in the room, and why it is where it is.
# ---------------------------------------------------------------------------------------

# Fixtures know their own footprint and where they want to be.
FIXTURE = {
    # name: (size x, size z, placement, height off floor)
    "forge": (1.8, 1.2, "wall", 0.0), "anvil": (0.9, 0.5, "floor_open", 0.0),
    "quench_trough": (1.4, 0.7, "wall", 0.0), "bellows": (1.2, 0.8, "wall", 0.0),
    "tool_rack": (1.6, 0.35, "wall", 0.9), "coal_heap": (1.2, 1.2, "corner", 0.0),
    "iron_stock": (1.8, 0.5, "wall", 0.0), "crate": (0.8, 0.8, "wall", 0.0),
    "barrel": (0.7, 0.7, "wall", 0.0), "bread_oven": (2.0, 1.6, "wall", 0.0),
    "kneading_table": (1.9, 0.9, "floor_open", 0.0), "flour_sacks": (1.2, 1.0, "corner", 0.0),
    "peel_rack": (1.0, 0.3, "wall", 1.2), "counter": (2.4, 0.7, "wall", 0.0),
    "bread_shelf": (1.8, 0.4, "wall", 1.0), "millstone": (2.2, 2.2, "centre", 0.0),
    "hopper": (1.2, 1.2, "centre", 1.6), "sack_hoist": (0.8, 0.8, "corner", 2.2),
    "gear_pit": (1.6, 1.6, "corner", 0.0), "scales": (0.7, 0.5, "wall", 0.8),
    "ledger_desk": (1.2, 0.6, "wall", 0.0), "mash_tun": (1.5, 1.5, "corner", 0.0),
    "copper": (1.3, 1.3, "wall", 0.0), "cooling_trays": (2.0, 1.0, "wall", 0.8),
    "hop_sacks": (1.0, 0.9, "corner", 0.0), "barrel_rack": (2.4, 0.9, "wall", 0.0),
    "tap_bench": (1.6, 0.6, "wall", 0.0), "alembic": (0.9, 0.9, "wall", 0.9),
    "drying_rack": (1.4, 0.4, "wall", 1.5), "ingredient_shelf": (1.8, 0.4, "wall", 1.1),
    "mortar_bench": (1.4, 0.7, "floor_open", 0.0), "bottle_shelf": (1.6, 0.35, "wall", 1.2),
    "bar": (3.2, 0.8, "wall", 0.0), "long_table": (2.6, 1.0, "centre", 0.0),
    "bench": (2.2, 0.45, "beside_table", 0.0), "hearth": (1.6, 0.9, "wall", 0.0),
    "board": (1.0, 0.1, "wall", 1.4), "cook_hearth": (1.6, 1.0, "wall", 0.0),
    "prep_table": (1.6, 0.8, "floor_open", 0.0), "pot_rack": (1.2, 0.4, "wall", 1.8),
    "bed": (2.0, 1.1, "wall", 0.0), "chest": (1.0, 0.5, "wall", 0.0),
    "washstand": (0.7, 0.5, "wall", 0.0), "stall": (2.0, 1.6, "wall", 0.0),
    "hay_pile": (1.6, 1.4, "corner", 0.0), "yoke": (1.2, 0.3, "wall", 1.3),
    "pitchfork": (0.3, 0.3, "wall", 0.0), "grain_bin": (1.2, 1.0, "wall", 0.0),
    "root_crate": (0.9, 0.7, "corner", 0.0), "seed_sacks": (1.0, 0.8, "corner", 0.0),
    "writing_desk": (1.3, 0.7, "wall", 0.0), "deed_chest": (0.9, 0.5, "wall", 0.0),
    "shelf": (1.6, 0.35, "wall", 1.1), "strongbox": (0.6, 0.45, "corner", 0.0),
    "chair": (0.5, 0.5, "beside_table", 0.0), "sideboard": (1.6, 0.6, "wall", 0.0),
    "net_rack": (2.0, 0.5, "wall", 0.0), "drying_line": (2.4, 0.1, "wall", 1.9),
    "oar_rack": (0.4, 0.4, "corner", 0.0), "tar_pot": (0.6, 0.6, "corner", 0.0),
    # A Name-table (DESIGN §5.8): the bench a Toll-Knight writes a note into iron at. It
    # had no entry at all and fell through to the 0.8 x 0.6 default, which reserved half
    # the floor it needs -- the mesh is 1.4 x 0.78, and the room has to leave room to stand
    # at it. Against a wall, because the Bell Chapter-House's muster room is a cell.
    "name_table": (1.5, 0.9, "wall", 0.0),
    "weapon_rack": (1.8, 0.4, "wall", 0.0), "roll_desk": (1.4, 0.8, "wall", 0.0),
    "map_board": (1.4, 0.1, "wall", 1.3), "stool": (0.4, 0.4, "beside_table", 0.0),
    "cupboard": (1.2, 0.5, "wall", 0.0), "table": (1.6, 0.9, "centre", 0.0),
    "settle": (1.8, 0.6, "wall", 0.0), "cradle": (0.9, 0.5, "wall", 0.0),
    "loom": (1.5, 1.0, "wall", 0.0), "spinning_wheel": (0.7, 0.7, "floor_open", 0.0),
}

# Every hearth room gets these, scaled by wealth: this is what "lived in" means.
HOME_FIXTURES = ["hearth", "table", "stool", "stool", "cupboard", "settle"]

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
}

# A habit is a sentence about the resident that becomes an object on the floor.
HABIT_PROPS = {
    "leaves_boots_by_the_door": [("boots", "door", 0.0)],
    "keeps_the_fire_in": [("banked_embers", "hearth", 0.0), ("kindling_basket", "hearth", 0.0)],
    "drinks_alone": [("mug", "settle", 0.45), ("jug", "settle", 0.45)],
    "mends_at_night": [("mending_basket", "settle", 0.0), ("candle_stub", "table", 0.75)],
    "reads_late": [("book_single", "bed", 0.55), ("candle_stub", "bed", 0.55)],
    "never_finishes_a_job": [("half_made_thing", "floor_open", 0.0)],
    "feeds_the_birds": [("crumb_bowl", "window", 0.95)],
    "counts_everything": [("tally_sticks", "wall", 1.2)],
    "keeps_a_shrine": [("small_bell", "wall", 1.5), ("candle_stub", "wall", 1.5)],
    "sleeps_badly": [("blanket_heap", "bed", 0.5), ("cold_tea", "bed", 0.5)],
    "hoards_string": [("string_ball", "corner", 0.0), ("string_ball", "corner", 0.0)],
    "works_at_the_table": [("work_in_progress", "table", 0.75)],
    "has_a_dog": [("dog_bowl", "hearth", 0.0), ("chewed_stick", "floor_open", 0.0)],
    "has_children": [("wooden_toy", "floor_open", 0.0), ("small_boots", "door", 0.0)],
    "sharpens_obsessively": [("whetstone", "bench", 0.0), ("oil_rag", "bench", 0.0)],
}


def asset_for(name: str) -> str:
    return f"res://assets/models/props/{name}/{name}.glb"


def dress(rooms: list[dict], recipe: dict, doors: list, windows: list, rng: np.random.Generator) -> list[dict]:
    """Place fixtures against the walls, then put things on them, then add the habits."""
    trade = TRADE_PLANS.get(recipe.get("trade", "none"), TRADE_PLANS["none"])
    wealth = WEALTH[int(recipe.get("wealth", 1))]
    clutter = float(recipe.get("clutter", wealth["clutter"]))
    placements: list[dict] = []
    surfaces: dict[str, list[dict]] = {}

    for room in rooms:
        kind = room["kind"]
        wanted = list(trade["fixtures"].get(kind, []))
        if kind == "hearth_room":
            wanted = HOME_FIXTURES + (["loom", "spinning_wheel"] if rng.random() < 0.4 else [])
        elif kind in ("bed", "guest_room"):
            wanted = ["bed", "chest"] + (["washstand"] if wealth["comfort"] > 0.4 else [])
            if int(recipe.get("children", 0)) > 0 and kind == "bed":
                wanted.append("cradle")
        elif kind == "store" and not wanted:
            wanted = ["crate", "barrel", "chest"]
        wanted += recipe.get("extra_fixtures", {}).get(kind, [])

        taken = []  # (x0, z0, x1, z1) in room-local metres
        for name in wanted:
            size = FIXTURE.get(name, (0.8, 0.6, "wall", 0.0))
            spot = place(room, size, taken, rng)
            if spot is None:
                continue
            x, z, yaw = spot
            p = {
                "asset": asset_for(name), "fixture": name, "room": room["id"],
                "at": [round(room["x"] + x, 2), round(room["floor_y"] + size[3], 2), round(room["z"] + z, 2)],
                "yaw": round(yaw, 1),
                "wear": round(min(1.0, room["wear"] + rng.uniform(-0.1, 0.1)), 2),
            }
            placements.append(p)
            if name in SURFACE_GROUPS:
                surfaces.setdefault(room["id"], []).append({"name": name, "at": p["at"], "yaw": yaw, "size": size})

        # Things on surfaces, kept in their groups, not scattered evenly.
        for surf in surfaces.get(room["id"], []):
            groups = SURFACE_GROUPS[surf["name"]]
            top = surf["at"][1] + (0.78 if surf["size"][3] == 0.0 else 0.06)
            for gi, group in enumerate(groups):
                if rng.random() > clutter:
                    continue
                # Each group huddles at one end of the surface, as a person leaves it.
                anchor_u = rng.uniform(-0.35, 0.35) + (gi - (len(groups) - 1) * 0.5) * 0.32
                for k, item in enumerate(group):
                    ang = math.radians(surf["yaw"])
                    u = (anchor_u + k * 0.13 + rng.uniform(-0.03, 0.03)) * surf["size"][0]
                    v = rng.uniform(-0.22, 0.22) * surf["size"][1]
                    placements.append({
                        "asset": asset_for(item), "prop": item, "room": room["id"], "on": surf["name"],
                        "at": [round(surf["at"][0] + math.cos(ang) * u - math.sin(ang) * v, 2),
                               round(top, 2),
                               round(surf["at"][2] + math.sin(ang) * u + math.cos(ang) * v, 2)],
                        "yaw": round(rng.uniform(0, 360), 1),
                        "group": f"{surf['name']}_{gi}",
                    })

    # Habits: the specific evidence that one person lives here and not another.
    for habit in recipe.get("habits", []):
        for item, where, height in HABIT_PROPS.get(habit, []):
            room = pick_room_for(where, rooms, rng)
            if room is None:
                continue
            x = rng.uniform(0.6, room["w"] - 0.6)
            z = rng.uniform(0.6, room["d"] - 0.6)
            if where == "door" and doors:
                d = doors[0]["at"]
                x, z = d[0] - room["x"] + rng.uniform(-0.5, 0.5), d[2] - room["z"] + rng.uniform(0.4, 0.9)
            placements.append({
                "asset": asset_for(item), "prop": item, "room": room["id"], "habit": habit,
                "at": [round(room["x"] + x, 2), round(room["floor_y"] + height, 2), round(room["z"] + z, 2)],
                "yaw": round(rng.uniform(0, 360), 1),
            })
    return placements


def place(room: dict, size, taken: list, rng: np.random.Generator):
    """Find a spot for a fixture that respects how it wants to sit in the room."""
    w, d, mode, _h = size
    for _ in range(40):
        if mode == "wall":
            side = rng.integers(0, 4)
            if side == 0:
                x, z, yaw = rng.uniform(w * 0.5 + 0.2, room["w"] - w * 0.5 - 0.2), d * 0.5 + 0.1, 0.0
            elif side == 1:
                x, z, yaw = rng.uniform(w * 0.5 + 0.2, room["w"] - w * 0.5 - 0.2), room["d"] - d * 0.5 - 0.1, 180.0
            elif side == 2:
                x, z, yaw = d * 0.5 + 0.1, rng.uniform(w * 0.5 + 0.2, room["d"] - w * 0.5 - 0.2), 90.0
            else:
                x, z, yaw = room["w"] - d * 0.5 - 0.1, rng.uniform(w * 0.5 + 0.2, room["d"] - w * 0.5 - 0.2), 270.0
        elif mode == "corner":
            cx = rng.choice([w * 0.5 + 0.15, room["w"] - w * 0.5 - 0.15])
            cz = rng.choice([d * 0.5 + 0.15, room["d"] - d * 0.5 - 0.15])
            x, z, yaw = float(cx), float(cz), float(rng.choice([0, 90, 180, 270]))
        elif mode == "centre":
            x, z = room["w"] * 0.5 + rng.uniform(-0.4, 0.4), room["d"] * 0.5 + rng.uniform(-0.4, 0.4)
            yaw = float(rng.choice([0, 90]))
        elif mode == "beside_table":
            centre_items = [t for t in taken if abs((t[0] + t[2]) * 0.5 - room["w"] * 0.5) < 1.2]
            if centre_items:
                t = centre_items[0]
                side = rng.integers(0, 2)
                x = (t[0] + t[2]) * 0.5 + (rng.uniform(-0.6, 0.6))
                z = (t[1] - d * 0.6) if side == 0 else (t[3] + d * 0.6)
                yaw = 0.0 if side == 0 else 180.0
            else:
                x, z, yaw = room["w"] * 0.5, room["d"] * 0.5 + 1.0, 180.0
        else:  # floor_open
            x, z = rng.uniform(w, room["w"] - w), rng.uniform(d, room["d"] - d)
            yaw = float(rng.uniform(0, 360))
        x = float(np.clip(x, w * 0.5 + 0.1, max(room["w"] - w * 0.5 - 0.1, w * 0.5 + 0.1)))
        z = float(np.clip(z, d * 0.5 + 0.1, max(room["d"] - d * 0.5 - 0.1, d * 0.5 + 0.1)))
        rect = (x - w * 0.5, z - d * 0.5, x + w * 0.5, z + d * 0.5)
        if not any(overlaps(rect, t) for t in taken):
            taken.append(rect)
            return x, z, yaw
    return None


def overlaps(a, b) -> bool:
    return not (a[2] < b[0] or b[2] < a[0] or a[3] < b[1] or b[3] < a[1])


def pick_room_for(where: str, rooms: list[dict], rng: np.random.Generator):
    if where in ("hearth", "settle", "table", "floor_open", "wall", "corner", "window", "door", "bench"):
        hearths = [r for r in rooms if r["kind"] == "hearth_room"]
        if hearths:
            return hearths[0]
    if where == "bed":
        beds = [r for r in rooms if r["kind"] in ("bed", "guest_room")]
        if beds:
            return beds[0]
    return rooms[0] if rooms else None


def lights_for(rooms: list[dict], placements: list[dict], recipe: dict) -> list[dict]:
    """Hearths, candles and lanterns, warm and low, one strong source per lived-in room."""
    out = []
    for room in rooms:
        hearth = next((p for p in placements if p.get("fixture") in ("hearth", "cook_hearth", "forge", "bread_oven") and p["room"] == room["id"]), None)
        if hearth:
            out.append({"room": room["id"], "at": [hearth["at"][0], hearth["at"][1] + 0.6, hearth["at"][2]],
                        "color": "#ff9a42" if hearth["fixture"] != "forge" else "#ff7b2a",
                        "energy": 4.2 if hearth["fixture"] == "forge" else 3.0, "range": 9.0, "flicker": 0.4, "shadow": True})
        candles = [p for p in placements if p.get("prop") in ("candlestick", "candle_stub", "lantern") and p["room"] == room["id"]]
        for c in candles[:2]:
            out.append({"room": room["id"], "at": [c["at"][0], c["at"][1] + 0.25, c["at"][2]],
                        "color": "#ffca7a", "energy": 1.1, "range": 4.5, "flicker": 0.35, "shadow": False})
        if not hearth and not candles:
            out.append({"room": room["id"], "at": [room["centre"][0], room["floor_y"] + 2.2, room["centre"][2]],
                        "color": "#ffd9a0", "energy": 0.8, "range": 6.0, "flicker": 0.0, "shadow": False})
    return out


BOOK_PROPS = ("book_single", "book_stack", "roll_book", "ledger")


def shelve(recipe: dict, placements: list[dict]) -> None:
    """A recipe's `books` names what lies on a room's book props: {"hall": {"book": id, "fixed":
    true}}. The first book prop in that room carries it (house_interior.gd makes it readable);
    otherwise the house's shelf gets what the culture pool picks. A room with no book prop is an
    error, since the recipe has promised something that would not be there."""
    for room_id, spec in (recipe.get("books") or {}).items():
        target = next((p for p in placements if p.get("room") == room_id and p.get("prop") in BOOK_PROPS), None)
        if target is None:
            raise SystemExit("%s: the recipe puts a book in '%s' and nothing there holds one" % (recipe.get("id", "?"), room_id))
        target.update({k: v for k, v in spec.items() if k in ("book", "item", "fixed")})


def build(recipe: dict, out_root: str, quiet: bool = False) -> dict:
    name = recipe["name_slug"]
    rng = np.random.default_rng(int(recipe.get("seed", 1)))
    rooms = plan(recipe, rng)
    shell, timber, doors, windows = build_shell(rooms, recipe, rng)
    placements = dress(rooms, recipe, doors, windows, rng)
    shelve(recipe, placements)
    lights = lights_for(rooms, placements, recipe)

    folder = os.path.join(out_root, name)
    os.makedirs(folder, exist_ok=True)
    shell.export(os.path.join(folder, f"{name}.glb"))
    if timber is not None:
        timber.export(os.path.join(folder, f"{name}_timber.glb"))
    col = shell.simplify_quadric_decimation(face_count=max(int(len(shell.faces) * 0.5), 500)) if len(shell.faces) > 4000 else shell
    col.export(os.path.join(folder, f"{name}_col.glb"))

    meta = {
        "id": recipe["id"], "name": recipe.get("name", name), "generator": "house_forge", "version": 1,
        "seed": int(recipe.get("seed", 1)), "resident": recipe.get("resident", ""), "trade": recipe.get("trade", "none"),
        "wealth": int(recipe.get("wealth", 1)), "household": int(recipe.get("household", 2)),
        "story": recipe.get("story", ""), "who_was_here": recipe.get("who_was_here", ""),
        "unique_object": recipe.get("unique_object", ""), "habits": recipe.get("habits", []),
        "culture": recipe.get("culture", ""), "place": recipe.get("place", ""),
        "tris": int(len(shell.faces)) + (int(len(timber.faces)) if timber is not None else 0),
        "has_timber": timber is not None,
        "rooms": [{k: v for k, v in r.items() if k != "row"} for r in rooms],
        "doors": doors, "windows": windows, "placements": placements, "lights": lights,
        "features": recipe.get("features", []),
        "entrance": doors[0]["at"] if doors else [0, 0, 0],
    }
    with open(os.path.join(folder, f"{name}.meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    if not quiet:
        print(f"{name}: {len(rooms)} rooms, {len(shell.faces) + (len(timber.faces) if timber is not None else 0):,} tris, {len(placements)} props, "
              f"{len(doors)} doors, {len(windows)} windows, {len(lights)} lights")
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("recipes", nargs="+")
    ap.add_argument("--out", default="game/assets/models/interior")
    args = ap.parse_args()
    for path in args.recipes:
        recipe = json.load(open(path))
        recipe.setdefault("name_slug", os.path.splitext(os.path.basename(path))[0])
        build(recipe, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
