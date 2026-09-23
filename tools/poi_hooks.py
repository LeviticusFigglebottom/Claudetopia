#!/usr/bin/env python3
"""Writes core:table/poi_hooks: what every point of interest's hook pays off in.

One row a point of interest (docs/ATLAS.md §16):

  * `quests`: the authored quests that send you there. That means an objective's target, where
    or place; a person by where they live; an interior by the place it is in; a stage's marker;
    or the giver's home. It is the reading `game/tests/unit/test_map_quests.gd` makes.
  * `finds`: what an encounter def's `lies` puts down there, to take or to read.
  * `encounters`: the encounter defs that stand somebody up there (`spawns`).
  * `hearthstone`: whether it keeps one.

Nothing in the game reads the table. It is the index, and test_map_quests holds each row true.
When a quest or an encounter changes what it names, run this and commit the table.

Usage:
    tools/poi_hooks.py            # rewrite game/content/packs/core/tables/poi_hooks.json
    tools/poi_hooks.py --check    # say which rows differ, and exit 1 if any do
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = ROOT / "game" / "content" / "packs"
TABLE = PACKS / "core" / "tables" / "poi_hooks.json"
TABLE_ID = "core:table/poi_hooks"


def defs() -> dict:
    out = {}
    for path in sorted(PACKS.rglob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        for item in data if isinstance(data, list) else data.get("entries", [data]):
            if isinstance(item, dict) and "id" in item:
                out[item["id"]] = item
    return out


def id_type(v) -> str:
    if not isinstance(v, str) or ":" not in v or "/" not in v:
        return ""
    return v.split(":", 1)[1].split("/", 1)[0]


def sends_you(q: dict, d: dict) -> set:
    """Where one quest sends you (test_map_quests' `_sends_you`)."""
    out = {d.get(q.get("giver", ""), {}).get("home_place", "")}
    for stage in q.get("stages", []):
        marker = stage.get("marker")
        if isinstance(marker, dict):
            out.add(marker.get("place_id", ""))
        for o in stage.get("objectives", []):
            for key in ("target", "where", "place"):
                v = o.get(key, "")
                t = id_type(v)
                if t in ("place", "poi"):
                    out.add(v)
                elif t == "npc":
                    out.add(d.get(v, {}).get("home_place", ""))
                elif t == "interior":
                    out.add(d.get(v, {}).get("place", ""))
    return out


def rows(d: dict) -> list:
    pays = {}
    for i, poi in sorted(d.items()):
        if id_type(i) == "poi":
            pays[i] = {"poi": i, "quests": [], "finds": [], "encounters": [],
                       "hearthstone": bool(poi.get("hearthstone", False))}
    for i, q in sorted(d.items()):
        if id_type(i) != "quest" or q.get("layer") == "radiant":
            continue
        for where in sorted(sends_you(q, d)):
            if where in pays:
                pays[where]["quests"].append(i)
    for i, e in sorted(d.items()):
        if id_type(i) != "encounter":
            continue
        at = e.get("place", "")
        if at not in pays:
            continue
        if e.get("spawns"):
            pays[at]["encounters"].append(i)
        for lying in e.get("lies", []):
            what = lying.get("item") or lying.get("book") if isinstance(lying, dict) else ""
            if what and what in d and what not in pays[at]["finds"]:
                pays[at]["finds"].append(what)
    return [pays[p] for p in sorted(pays)]


def main() -> int:
    d = defs()
    new = rows(d)
    bare = [r["poi"] for r in new if not (r["quests"] or r["finds"] or r["encounters"] or r["hearthstone"])]
    table = json.loads(TABLE.read_text(encoding="utf-8")) if TABLE.exists() else []
    old = next((t for t in table if t.get("id") == TABLE_ID), {})
    if "--check" in sys.argv:
        before = {r["poi"]: r for r in old.get("rows", [])}
        differ = [r["poi"] for r in new if before.get(r["poi"]) != r]
        differ += [p for p in before if p not in {r["poi"] for r in new}]
        for p in differ:
            print("differs: %s" % p)
        for p in bare:
            print("pays off in nothing: %s" % p)
        print("%d rows, %d differ, %d pay off in nothing" % (len(new), len(differ), len(bare)))
        return 1 if differ or bare else 0
    out = {"id": TABLE_ID, "name": "What every point of interest's hook pays off in",
           "description": "One row a point of interest: the quests whose stages send you there, the things lying "
                          "there to take or read, the encounters that stand something up there, and whether it keeps "
                          "a Hearthstone. Written from the pack by tools/poi_hooks.py; "
                          "tests/unit/test_map_quests.gd holds it true.",
           "rows": new}
    TABLE.write_text(json.dumps([out], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("%d rows written to %s; %d pay off in nothing" % (len(new), TABLE.relative_to(ROOT), len(bare)))
    for p in bare:
        print("  pays off in nothing: %s" % p)
    return 1 if bare else 0


if __name__ == "__main__":
    sys.exit(main())
