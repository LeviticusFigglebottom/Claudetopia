#!/usr/bin/env python3
"""Finds what nothing puts in the world.

`dead_data.py` asks which keys no code reads, and `unwired.py` which functions nothing calls.
This asks which *things* nothing places. A definition can be complete, valid and read by every
system that should read it, and still never be met by a player: no cell or encounter stands the
enemy up, no loot table, shop, line or quest hands the item over, no item reads the book, no door
leads into the interior, nobody speaks the dialogue.

For each kind of thing that lives in the world it gathers every way the built game has of putting
one there, and reports the definitions none of them reaches:

  enemy     a cell's spawns, a POI encounter, a deep place's encounters, a region's ecology (the
            job boards' hunts), a quest's kill target, a boss's own arena
  npc       a home, or a schedule that puts them somewhere
  item      a line or a quest that gives it, a drop, a calling's kit, a shop's stock, a loot table,
            a quest's pickup (QuestItems), a recipe's output, a deed's key, a furnishing on offer,
            a deed on a for-sale board
  book      an item that reads it and is itself placed, or a shelf in a house
  place     the world's POI data (the build put it on the map)
  interior  a door plan
  dialogue  an npc, a door, a point of interest, or another dialogue or quest that hands over to it

It follows the same sources `systems/quests/item_sources.gd` reads at runtime, and reads the built
world (`game/world/generated`) and the deep places' metas for where enemies stand. What it reports
is a list worth reading by hand; some of it is there on purpose (a test fixture, a key nothing yet
hands over), which is why nothing fails on it.

Usage: python3 tools/unplaced.py [--type TYPE] [--quiet]
"""
from __future__ import annotations

import collections
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
PACKS = GAME / "content" / "packs"
GENERATED = GAME / "world" / "generated"


def defs() -> dict:
    """id -> def, for every definition in every pack."""
    out = {}
    for path in sorted(PACKS.rglob("*.json")):
        if path.name in ("pack.json", "names_index.json"):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        items = data if isinstance(data, list) else data.get("entries", [data])
        for item in items:
            if isinstance(item, dict) and "id" in item:
                out[str(item["id"])] = item
    return out


def type_of(def_id: str) -> str:
    return def_id.split(":", 1)[1].split("/", 1)[0] if ":" in def_id and "/" in def_id else ""


def of_type(all_defs: dict, kind: str) -> dict:
    return {k: v for k, v in all_defs.items() if type_of(k) == kind}


def walk(value, path=()):
    """Every (path, string) in a nested value; path is the tuple of keys above it."""
    if isinstance(value, dict):
        for k, v in value.items():
            yield from walk(v, path + (str(k),))
    elif isinstance(value, list):
        for v in value:
            yield from walk(v, path)
    elif isinstance(value, str):
        yield path, value


def effect_items(value, verb: str):
    """Item ids an effect list gives (`give_item`), at any depth of a dialogue or quest."""
    if isinstance(value, dict):
        for k, v in value.items():
            if k == verb:
                if isinstance(v, list) and v and isinstance(v[0], str):
                    yield v[0]
                elif isinstance(v, str):
                    yield v
            else:
                yield from effect_items(v, verb)
    elif isinstance(value, list):
        for v in value:
            yield from effect_items(v, verb)


def items_in(value):
    for _path, s in walk(value):
        if s.startswith("core:item/"):
            yield s


# --- where things are put -------------------------------------------------------------------------

def item_sources(all_defs: dict) -> dict:
    """item id -> [how it reaches a player]."""
    src = collections.defaultdict(list)
    for did, d in of_type(all_defs, "dialogue").items():
        for item in effect_items(d, "give_item"):
            src[item].append("dialogue " + did)
    for qid, q in of_type(all_defs, "quest").items():
        for item in effect_items(q.get("stages", []), "give_item"):
            src[item].append("quest " + qid)
        rewards = q.get("rewards", {}) or {}
        for entry in rewards.get("items", []) or []:
            item = entry[0] if isinstance(entry, list) else entry
            src[str(item)].append("reward " + qid)
        for item in effect_items(rewards.get("effects", []), "give_item"):
            src[item].append("reward " + qid)
        for stage in q.get("stages", []) or []:
            for o in stage.get("objectives", []) or []:
                if o.get("type") in ("collect", "use_item") and str(o.get("target", "")).startswith("core:item/"):
                    src[str(o["target"])].append("pickup " + qid)
                if o.get("item"):
                    src[str(o["item"])].append("pickup " + qid)
    for kind in ("enemy", "boss"):
        for eid, e in of_type(all_defs, kind).items():
            for entry in e.get("drops", []) or []:
                item = entry.get("item", "") if isinstance(entry, dict) else entry
                src[str(item)].append("drop " + eid)
    for cid, c in of_type(all_defs, "calling").items():
        for entry in c.get("starting_items", []) or []:
            item = entry.get("item", "") if isinstance(entry, dict) else entry
            src[str(item)].append("calling " + cid)
        if c.get("signature_item"):
            src[str(c["signature_item"])].append("calling " + cid)
    stocks = set()
    for nid, n in of_type(all_defs, "npc").items():
        m = n.get("merchant")
        if isinstance(m, dict) and m.get("stock"):
            stocks.add(str(m["stock"]))
    for table in stocks:
        for item in items_in(all_defs.get(table, {})):
            src[item].append("stock " + table)
    for lid, loot in of_type(all_defs, "loot").items():
        for item in items_in(loot):
            src[item].append("loot " + lid)
    for rid, r in of_type(all_defs, "recipe").items():
        out = r.get("output", {})
        item = out.get("item", "") if isinstance(out, dict) else out
        if item:
            src[str(item)].append("recipe " + rid)
    for iid, it in of_type(all_defs, "item").items():
        prop = it.get("property")
        if isinstance(prop, dict):
            src[iid].append("for-sale board")
            if prop.get("key"):
                src[str(prop["key"])].append("deed " + iid)
        if isinstance(it.get("furnishing"), dict):
            src[iid].append("furnishing")
    # what a place's own encounter def says lies there (QuestItems puts it down): the chart in
    # the Reed Wreck, a note at a shrine
    for eid, enc in of_type(all_defs, "encounter").items():
        for lying in enc.get("lies", []) or []:
            if isinstance(lying, dict) and lying.get("item"):
                src[str(lying["item"])].append("lies at " + str(enc.get("place", eid)))
    # what the game itself hands over by name: the job board's parcel for delivery
    for token, where in _code_literals("core:item/"):
        src[token].append("code " + where)
    # what a deep place or a house lays out in its rooms: a cist's leaf, a shelf's book
    for iid, interior in of_type(all_defs, "interior").items():
        for _path, s in walk(_meta(interior).get("features", [])):
            if s.startswith("core:item/"):
                src[s].append("interior " + iid)
        for p in _meta(interior).get("placements", []) or []:
            if isinstance(p, dict) and str(p.get("item", "")).startswith("core:item/"):
                src[str(p["item"])].append("interior " + iid)
    return src


def read_books(all_defs: dict, placed_items: set) -> dict:
    """book id -> [how it is read]: a placed item that reads it, or a house's shelf."""
    src = collections.defaultdict(list)
    for iid, it in of_type(all_defs, "item").items():
        book = str(it.get("reads", ""))
        if not book and it.get("category") == "book":
            guess = "core:book/" + iid.split("/", 1)[1]
            book = guess if guess in all_defs else ""
        if book and iid in placed_items:
            src[book].append("item " + iid)
    for iid, interior in of_type(all_defs, "interior").items():
        meta = _meta(interior)
        for p in meta.get("placements", []) or []:
            if isinstance(p, dict) and p.get("book"):
                src[str(p["book"])].append("shelf " + iid)
    # a book lying at a place is read where it lies (the hermit's exercise book on Willow Isle)
    for eid, enc in of_type(all_defs, "encounter").items():
        for lying in enc.get("lies", []) or []:
            if isinstance(lying, dict) and lying.get("book"):
                src[str(lying["book"])].append("lies at " + str(enc.get("place", eid)))
    return src


def _meta(def_: dict) -> dict:
    path = str(def_.get("meta", ""))
    if not path.startswith("res://"):
        return {}
    real = GAME / path[len("res://"):]
    try:
        return json.loads(real.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def enemy_sources(all_defs: dict) -> dict:
    src = collections.defaultdict(list)
    cells = GENERATED / "cells"
    if cells.is_dir():
        for path in cells.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            for s in data.get("spawns", []) or []:
                if isinstance(s, dict) and s.get("def"):
                    src[str(s["def"])].append("cell " + path.stem)
    for eid, enc in of_type(all_defs, "encounter").items():
        for _path, s in walk(enc):
            if s.startswith("core:enemy/") or s.startswith("core:boss/"):
                src[s].append("encounter " + eid)
    dungeon = GAME / "assets" / "models" / "dungeon"
    if dungeon.is_dir():
        for path in dungeon.glob("*/*.meta.json"):
            try:
                meta = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            for _p, s in walk(meta.get("encounters", [])):
                if s.startswith("core:enemy/") or s.startswith("core:boss/"):
                    src[s].append("deep place " + path.parent.name)
    for rid, region in of_type(all_defs, "region").items():
        for _p, s in walk(region.get("enemy_ecology", {})):
            if s.startswith("core:enemy/"):
                src[s].append("ecology " + rid)
    for qid, q in of_type(all_defs, "quest").items():
        for stage in q.get("stages", []) or []:
            for o in stage.get("objectives", []) or []:
                target = str(o.get("target", ""))
                if o.get("type") == "kill" and (target.startswith("core:enemy/") or target.startswith("core:boss/")):
                    src[target].append("quest " + qid)
    for bid, boss in of_type(all_defs, "boss").items():
        if boss.get("arena"):
            src[bid].append("arena " + str(boss["arena"]))
    # a saying that calls something up puts it in the world at the caster's side
    for sid, spell in of_type(all_defs, "spell").items():
        for _p, s in walk(spell):
            if s.startswith("core:enemy/"):
                src[s].append("spell " + sid)
    return src


def dialogue_sources(all_defs: dict) -> dict:
    src = collections.defaultdict(list)
    for did, d in all_defs.items():
        for _path, s in walk(d):
            if s.startswith("core:dialogue/") and s != did:
                src[s].append(did)
    # and what the game itself hands a conversation to: a POI's touchable (the One Poppy)
    for token, where in _code_literals("core:dialogue/"):
        src[token].append("code " + where)
    return src


def _code_literals(prefix: str):
    """(id, file) for every string literal in the game's own scripts (not its tests) that is an
    id starting `prefix`: what the code puts in the world by name."""
    for path in GAME.rglob("*.gd"):
        if "tests" in path.parts or ".godot" in path.parts or "tools_gd" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for token in text.split('"')[1::2]:
            if token.startswith(prefix):
                yield token, path.name


def placed_places() -> set:
    try:
        pois = json.loads((GENERATED / "pois.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    return {str(p.get("place_id", "")) for p in pois if isinstance(p, dict)}


def planned_interiors(all_defs: dict) -> set:
    out = set()
    for tid, t in of_type(all_defs, "table").items():
        if t.get("role") == "door_plan":
            for row in t.get("rows", []) or []:
                out.add(str(row.get("interior", "")))
    return out


# --- the report -------------------------------------------------------------------------------------

def unplaced(all_defs: dict) -> dict:
    """kind -> sorted [(id, why)] of what nothing places."""
    out = {}
    items = item_sources(all_defs)
    placed_items = {i for i, why in items.items() if why}
    out["item"] = sorted((i, "") for i in of_type(all_defs, "item") if i not in placed_items)
    books = read_books(all_defs, placed_items)
    out["book"] = sorted((b, "") for b in of_type(all_defs, "book") if b not in books)
    enemies = enemy_sources(all_defs)
    out["enemy"] = sorted((e, "") for e in list(of_type(all_defs, "enemy")) + list(of_type(all_defs, "boss"))
                          if e not in enemies)
    out["npc"] = sorted((n, "") for n, d in of_type(all_defs, "npc").items()
                        if not d.get("home_place") and not any(
                            isinstance(e, dict) and e.get("place") for e in d.get("schedule", []) or []))
    places = placed_places()
    out["place"] = sorted((p, str(d.get("kind", ""))) for p, d in of_type(all_defs, "place").items()
                          if places and p not in places)
    plans = planned_interiors(all_defs)
    out["interior"] = sorted((i, "") for i, d in of_type(all_defs, "interior").items()
                             if i not in plans and not d.get("test_only") and not d.get("no_door"))
    spoken = dialogue_sources(all_defs)
    out["dialogue"] = sorted((d, "") for d in of_type(all_defs, "dialogue") if d not in spoken)
    return out


def main() -> int:
    only = None
    if "--type" in sys.argv:
        only = sys.argv[sys.argv.index("--type") + 1]
    quiet = "--quiet" in sys.argv
    all_defs = defs()
    report = unplaced(all_defs)
    total = 0
    for kind in ("enemy", "npc", "item", "book", "place", "interior", "dialogue"):
        if only and kind != only:
            continue
        rows = report.get(kind, [])
        total += len(rows)
        have = len(of_type(all_defs, kind)) + (len(of_type(all_defs, "boss")) if kind == "enemy" else 0)
        print("%-9s %4d of %4d that nothing puts in the world" % (kind, len(rows), have))
        if not quiet:
            for def_id, why in rows:
                print("            " + def_id + (" (%s)" % why if why else ""))
    print("%d in all" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
