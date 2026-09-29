"""Reading the content pack's rows the way the game reads them: every file in a folder.

The game's ContentDB loads every *.json below a pack, so it never cared which file a def is in.
The tools used to open one named file (`pois/pois.json`); the POI registry is now one file a
region (`pois/<region>.json`, docs/WORLD_LIFE.md) and anything else in the folder (another
agent's `pois/_interiors_showcase.json`) is read with it, so every reader goes through here.

    rows(pack, "pois")             every row of every pois/*.json, by file name then file order
    poi_registry(pack)             the same rows in the world build's order (below)
    rows(pack, "encounters")       every encounter def, whichever file it is in

The build's order: the pads are laid and pois.json is written in registry order, so the order
is part of what a build makes. The 445 POIs the registry had when it was one file keep that
file's order (`poi_order.json`, frozen: never edit it); every POI added since follows, by file
name and then its place in the file. So the split changed no build, and a new POI changes
nothing but itself.
"""
from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LEGACY_ORDER = os.path.join(HERE, "poi_order.json")
REGIONS = ("hearthvale", "briarwold", "brightwater", "cinderlea", "sedgemire", "skerrow")


def files(pack_dir: str, sub: str) -> list:
    """Every *.json directly in pack_dir/sub, sorted by name (none when the folder is missing)."""
    folder = os.path.join(pack_dir, sub)
    if not os.path.isdir(folder):
        return []
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.endswith(".json")]


def rows(pack_dir: str, sub: str, with_file: bool = False) -> list:
    """Every row of every file in pack_dir/sub: a file holding one dict counts as one row.
    `with_file` gives (row, file name) pairs."""
    out = []
    for path in files(pack_dir, sub):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for row in data if isinstance(data, list) else [data]:
            out.append((row, os.path.basename(path)) if with_file else row)
    return out


def _legacy_order() -> dict:
    if not os.path.exists(LEGACY_ORDER):
        return {}
    with open(LEGACY_ORDER, "r", encoding="utf-8") as f:
        return {pid: i for i, pid in enumerate(json.load(f))}


def poi_registry(pack_dir: str) -> list:
    """Every POI def (core:poi/*) in pois/, in the build's order (the module's note)."""
    legacy = _legacy_order()
    found = [r for r in rows(pack_dir, "pois") if isinstance(r, dict)]
    # a stable sort: rows the legacy list does not name keep their file order after it
    return sorted(found, key=lambda r: legacy.get(str(r.get("id", "")), len(legacy)))


def region_of(row: dict) -> str:
    """'hearthvale' for a def whose region is core:region/hearthvale, '' otherwise."""
    return str(row.get("region", "")).split("/")[-1]
