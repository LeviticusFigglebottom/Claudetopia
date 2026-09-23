#!/usr/bin/env python3
"""Find world coordinates written down where a place could have been named (docs/COORDINATES.md).

The map is drawn by hand and gets drawn again; a coordinate stays behind when it is. This lists,
by file:

* content JSON: every pair or triple of numbers that looks like metres on the 8 km map (one of
  them at least 60 from zero), except the places' and POIs' own `position` and a region's `map`
  block, which is where the map is written down (test_place_ref.gd holds the content to this);
* capture plans: shots, gaits and sequences still at `pos` / `look_at` coordinates (the generated
  plans, default/pois/look/horizon, are expected here: their generators are rerun after a redraw);
* scripts (GDScript and Python): Vector2/Vector3 literals and number lists with a component of
  250 m or more, which is where a test or a tool most often hides a place's old position.

    tools/coordinate_scan.py            # everything
    tools/coordinate_scan.py --code     # only the scripts

Most of what the scripts part prints is legitimate (the map frame, arena floors, points off the
map, synthetic ground); it is a list to read, not a gate.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ID = re.compile(r"^([a-z0-9_]+):([a-z_]+)/(.+)$")
NUM = r"(-?\d+(?:\.\d+)?)"
V3 = re.compile(r"Vector3i?\(\s*" + NUM + r"\s*,\s*" + NUM + r"\s*,\s*" + NUM + r"\s*\)")
V2 = re.compile(r"Vector2i?\(\s*" + NUM + r"\s*,\s*" + NUM + r"\s*\)")
LIST = re.compile(r"\[\s*" + NUM + r"\s*,\s*" + NUM + r"(?:\s*,\s*" + NUM + r")?\s*\]")
SKIP_LINE = re.compile(r"size|minimum|resolution|screen|pixel|_SIZE|Rect2|viewport|texture|image|font|margin|offset_|Color\(", re.I)


def _is_point(v) -> bool:
    return (isinstance(v, list) and 2 <= len(v) <= 3 and all(isinstance(e, (int, float)) and not isinstance(e, bool) for e in v)
            and max(abs(e) for e in v) >= 60)


def scan_content() -> int:
    found = 0
    for f in sorted(glob.glob(os.path.join(REPO, "game", "content", "**", "*.json"), recursive=True)):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        rel = os.path.relpath(f, REPO)
        for d in data if isinstance(data, list) else ([data] if isinstance(data, dict) else []):
            if not isinstance(d, dict):
                continue
            m = ID.match(str(d.get("id", "")))
            typ = m.group(2) if m else ""
            for key, v in d.items():
                if (key == "position" and typ in ("place", "poi")) or (key == "map" and typ == "region"):
                    continue
                for path, point in _points(v, key):
                    if path.split(".")[-1].split("[")[0] in ("marks", "count", "tris", "rolls"):
                        continue
                    print("%s: %s %s %s" % (rel, d.get("id", "?"), path, point))
                    found += 1
    return found


def _points(v, path):
    if _is_point(v):
        yield path, v
    elif isinstance(v, list):
        for i, e in enumerate(v):
            yield from _points(e, "%s[%d]" % (path, i))
    elif isinstance(v, dict):
        for k, e in v.items():
            yield from _points(e, "%s.%s" % (path, k))


def scan_plans() -> int:
    found = 0
    for f in sorted(glob.glob(os.path.join(REPO, "tools", "capture", "plans", "*.json"))):
        plan = json.load(open(f, encoding="utf-8"))
        n = 0
        for item in plan.get("shots", []) + plan.get("sequences", []) + ([plan["gait"]] if isinstance(plan.get("gait"), dict) else []):
            if isinstance(item, dict) and any(_is_point(item.get(k)) for k in ("pos", "look_at", "to")):
                n += 1
        if n:
            print("%s: %d cameras at coordinates" % (os.path.relpath(f, REPO), n))
            found += n
    return found


def scan_code() -> int:
    found = 0
    files = glob.glob(os.path.join(REPO, "game", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(REPO, "tools", "**", "*.py"), recursive=True)
    for f in sorted(files):
        if "/addons/" in f or "/.godot/" in f:
            continue
        rel = os.path.relpath(f, REPO)
        for i, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
            if SKIP_LINE.search(line):
                continue
            hits = []
            for m in V3.finditer(line):
                x, _, z = (float(g) for g in m.groups())
                if 250 <= max(abs(x), abs(z)) <= 4200:
                    hits.append(m.group(0))
            for m in V2.finditer(line):
                x, z = (float(g) for g in m.groups())
                if min(abs(x), abs(z)) >= 250 and max(abs(x), abs(z)) <= 4200:
                    hits.append(m.group(0))
            if f.endswith(".py"):
                for m in LIST.finditer(line):
                    nums = [float(g) for g in m.groups() if g is not None]
                    if min(abs(nums[0]), abs(nums[-1])) >= 250 and max(abs(v) for v in nums) <= 4200:
                        hits.append(m.group(0))
            if hits:
                print("%s:%d: %s   | %s" % (rel, i, " ".join(hits), line.strip()[:100]))
                found += 1
    return found


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--code", action="store_true", help="only the scripts")
    args = ap.parse_args(argv)
    if not args.code:
        print("== content (outside places', POIs' and regions' own map data)")
        c = scan_content()
        print("   %d\n== capture plans" % c)
        p = scan_plans()
        print("   %d" % p)
    print("== scripts")
    s = scan_code()
    print("   %d lines" % s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
