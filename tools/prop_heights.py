#!/usr/bin/env python3
"""Where a prop mesh disagrees with the size the interiors expect it to be.

`HouseInterior._placeholder_size` is the box drawn when a mesh is missing, and it is also,
in effect, the only written specification of how big these objects ought to be. A mesh that
is right about its shape and wrong about its height reads as a *character* defect every time,
because the character is the thing that moves: the smith hammers at his knees and it looks
like the animation is broken.

That is not hypothetical. The work clips were authored against an anvil 750 mm tall, which is
the placeholder; the mesh is 371 mm and stands on the floor, because a real anvil's height is
mostly the stump it sits on and the stump was never built.

A disagreement means one of the two is wrong and not necessarily the mesh. The placeholder for
a chair is 480 mm, which is a seat height, and the chair the forge builds is 1065 mm, which is
a chair with a back on it. That is the table being wrong. Read the pair and decide; the tool
only finds them.

What a kind resolves to is `PropLibrary.resolve()`'s business and not this tool's opinion:
the table asks for a `hearth` and gets `forge_hearth`, for a `settle` and gets `bench`. The
STAND_IN map is read out of the GDScript so the two cannot drift apart, and a kind is only
called unbuilt when the game would also draw a placeholder for it.

Usage: tools/prop_heights.py [--tolerance 0.25]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "game", "world", "interiors", "house_interior.gd")
LIBRARY = os.path.join(ROOT, "game", "world", "interiors", "prop_library.gd")
MODELS = os.path.join(ROOT, "game", "assets", "models")


def expected() -> dict:
    """kind -> (w, h, d), read out of the GDScript match statement itself."""
    text = open(SOURCE, encoding="utf-8").read()
    body = text[text.index("static func _placeholder_size"):]
    body = body[:body.index("\n\n")]
    out = {}
    for line in body.splitlines():
        m = re.search(r'^\s*((?:"[a-z_]+"(?:,\s*)?)+):\s*return Vector3\(([^)]+)\)', line)
        if not m:
            continue
        dims = tuple(float(v) for v in m.group(2).split(","))
        for kind in re.findall(r'"([a-z_]+)"', m.group(1)):
            out[kind] = dims
    return out


def stand_ins() -> dict:
    """kind -> substitute kind, read out of `PropLibrary.STAND_IN`."""
    text = open(LIBRARY, encoding="utf-8").read()
    body = text[text.index("const STAND_IN := {"):]
    body = body[:body.index("\n}")]
    return dict(re.findall(r'"([a-z_]+)"\s*:\s*"([a-z_]+)"', body))


def regions() -> list:
    text = open(LIBRARY, encoding="utf-8").read()
    line = re.search(r"const REGIONS := \[([^\]]+)\]", text).group(1)
    return re.findall(r'"([a-z_]+)"', line)


def kind_of(slug: str, region_list: list) -> str:
    """The same folder-name-to-kind rule `PropLibrary.scan()` uses, and no other."""
    kind = slug
    for r in region_list:
        if slug.startswith(r + "_"):
            kind = slug[len(r) + 1:]
            break
    parts = kind.split("_")
    if len(parts) > 1 and len(parts[-1]) == 1:
        kind = "_".join(parts[:-1])
    return kind


def built() -> dict:
    """kind -> [(slug, height)], from what the forge actually made."""
    region_list = regions()
    out: dict = {}
    for path in glob.glob(os.path.join(MODELS, "props", "*", "*.meta.json")):
        meta = json.load(open(path, encoding="utf-8"))
        slug = os.path.basename(path).replace(".meta.json", "")
        height = float(meta.get("bounds", {}).get("height", 0.0))
        out.setdefault(kind_of(slug, region_list), []).append((slug, height))
    return out


def match_for(kind: str, have: dict, substitutes: dict) -> list:
    """What `resolve()` would hand back, across every region: the kind itself, or its stand-in."""
    for candidate in (kind, substitutes.get(kind, "")):
        if candidate and candidate in have:
            return have[candidate]
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tolerance", type=float, default=0.25,
                    help="fractional difference from the expected height before it is reported")
    a = ap.parse_args()
    want = expected()
    have = built()
    subs = stand_ins()
    rows = []
    seen = set()
    for kind in sorted(want):
        target = want[kind][1]
        if target <= 0.0:
            continue
        for slug, height in sorted(match_for(kind, have, subs)):
            off = (height - target) / target
            if abs(off) >= a.tolerance and (kind, slug) not in seen:
                seen.add((kind, slug))
                rows.append((abs(off), kind, slug, height, target, off))
    rows.sort(reverse=True)
    print("%d prop kinds have a written size; %d meshes differ by %d%% or more\n"
          % (len(want), len(rows), int(a.tolerance * 100)))
    for _, kind, slug, height, target, off in rows:
        drawn = slug if kind_of(slug, regions()) == kind else "%s (as %s)" % (slug, kind)
        print("  %-42s %5.3f m   expected %5.3f m   %+d%%"
              % (drawn, height, target, round(off * 100)))

    unbuilt = sorted(k for k in want if not match_for(k, have, subs))
    if unbuilt:
        print("\nasked for and drawn as a placeholder: %s" % ", ".join(unbuilt))
    broken = sorted(k for k, v in subs.items() if v not in have)
    if broken:
        print("\nstand-ins pointing at a kind the forge never built: %s"
              % ", ".join("%s -> %s" % (k, subs[k]) for k in broken))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
