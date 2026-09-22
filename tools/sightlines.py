#!/usr/bin/env python3
"""Which authored sightlines the land actually honours.

DESIGN §4 says each POI names at least one other place it should be visible from, and the 48
POIs do: 90 lines of authored composition. `PlaceDiscovery` reads them, and surveying from a
vista reveals what is genuinely in view — so a claim the terrain contradicts silently reveals
nothing and nobody hears about it.

This says it out loud. It marches the same ray `PlaceDiscovery.can_see()` marches, over the
same heightmap the runtime samples, and reports every claim the ground refuses. A blocked
sightline is not automatically a bug: a shrine in a dry valley may be meant to be come upon
rather than seen. It is a question for whoever placed it — move the POI, raise the vantage,
or replace the line — and it should be answered rather than left to fail quietly. Every one
of them has been; `PROGRESS.md` under "Sightlines, answered" says what each answer was.

The lines into the three hidden valleys are counted apart, because a hidden valley is called
hidden: its sightline is the way in and not the place, and the land refusing it is the valley
doing its job. `tools/world/tests/test_sightlines.py` fails the build if any other line goes
dark or any POI outside those three loses its last vantage.

Usage: tools/sightlines.py [--verbose]
"""
from __future__ import annotations

import argparse
import array
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "game", "world", "generated")
SYSTEM = os.path.join(ROOT, "game", "systems", "exploration", "place_discovery.gd")


def constants() -> dict:
    """EYE_M, LANDMARK_M, RAY_STEPS, CLEARANCE_M, MAX_SIGHT_M, read out of the GDScript, so
    the two cannot drift apart and quietly disagree about what is visible."""
    text = open(SYSTEM, encoding="utf-8").read()
    out = {}
    for name in ("EYE_M", "LANDMARK_DEFAULT_M", "RAY_STEPS", "CLEARANCE_M", "MAX_SIGHT_M",
                 "FOREGROUND_M"):
        m = re.search(r"^const %s := ([0-9.]+)$" % name, text, re.M)
        if not m:
            raise SystemExit("%s is no longer a plain constant in place_discovery.gd" % name)
        out[name] = float(m.group(1))
    body = text[text.index("const LANDMARK_M := {"):]
    out["LANDMARK_M"] = {k: float(v) for k, v in
                         re.findall(r'"([a-z_]+)":\s*([0-9.]+)', body[:body.index("}")])}
    return out


class Heights:
    def __init__(self) -> None:
        man = json.load(open(os.path.join(GEN, "world_manifest.json"), encoding="utf-8"))
        self.grid = int(man["grid"])
        self.spacing = float(man["spacing_m"])
        self.ox, self.oz = (float(v) for v in man["origin"])
        self.h = array.array("f")
        with open(os.path.join(GEN, "heights.r32"), "rb") as f:
            self.h.frombytes(f.read(self.grid * self.grid * 4))

    def at(self, x: float, z: float) -> float:
        """Bilinear, the same way `TerrainProvider.sample_height` does it."""
        g = self.grid
        fx = min(max((x - self.ox) / self.spacing, 0.0), g - 1.001)
        fz = min(max((z - self.oz) / self.spacing, 0.0), g - 1.001)
        x0, z0 = int(fx), int(fz)
        tx, tz = fx - x0, fz - z0
        x1, z1 = min(x0 + 1, g - 1), min(z0 + 1, g - 1)
        h00 = self.h[z0 * g + x0]; h10 = self.h[z0 * g + x1]
        h01 = self.h[z1 * g + x0]; h11 = self.h[z1 * g + x1]
        return (h00 + (h10 - h00) * tx) * (1 - tz) + (h01 + (h11 - h01) * tx) * tz


def positions() -> dict:
    out = {}
    for e in json.load(open(os.path.join(GEN, "pois.json"), encoding="utf-8")):
        p = e["pos"]
        out[e["place_id"]] = (float(p[0]), float(p[1]), float(p[2]))
    return out


def kinds() -> dict:
    out = {}
    folder = os.path.join(ROOT, "game", "content", "packs", "core", "pois")
    for f in sorted(os.listdir(folder)):
        if f.endswith(".json"):
            for d in json.load(open(os.path.join(folder, f), encoding="utf-8")):
                out[d.get("id", "")] = d.get("kind", "")
    return out


def names() -> dict:
    out = {}
    packs = os.path.join(ROOT, "game", "content", "packs", "core")
    for sub in ("pois", "places"):
        folder = os.path.join(packs, sub)
        if not os.path.isdir(folder):
            continue
        for f in os.listdir(folder):
            if not f.endswith(".json"):
                continue
            data = json.load(open(os.path.join(folder, f), encoding="utf-8"))
            for d in data if isinstance(data, list) else []:
                out[d.get("id", "")] = d.get("name", d.get("id", ""))
    return out


def claims() -> list:
    out = []
    folder = os.path.join(ROOT, "game", "content", "packs", "core", "pois")
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json"):
            continue
        data = json.load(open(os.path.join(folder, f), encoding="utf-8"))
        for d in data if isinstance(data, list) else []:
            for v in d.get("visible_from", []):
                out.append((v, d["id"]))
    return out


def blocked_at(hs: Heights, a: tuple, b: tuple, k: dict, kind: str = ""):
    """(blocked, worst_intrusion_m, distance_m) for one ray."""
    flat = ((b[0] - a[0]) ** 2 + (b[2] - a[2]) ** 2) ** 0.5
    if flat <= 1.0:
        return False, 0.0, flat
    if flat > k["MAX_SIGHT_M"]:
        return True, float("inf"), flat
    eye = a[1] + k["EYE_M"]
    top = b[1] + k["LANDMARK_M"].get(kind, k["LANDMARK_DEFAULT_M"])
    worst = 0.0
    steps = int(k["RAY_STEPS"])
    skip = min(k["FOREGROUND_M"] / flat, 0.4)
    for i in range(1, steps):
        t = i / steps
        if t < skip:
            continue
        ground = hs.at(a[0] + (b[0] - a[0]) * t, a[2] + (b[2] - a[2]) * t)
        line = eye + (top - eye) * t
        worst = max(worst, ground - line)
    return worst > k["CLEARANCE_M"], worst, flat


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true", help="list the clear ones too")
    a = ap.parse_args()
    k = constants()
    hs, pos, nm, kd = Heights(), positions(), names(), kinds()
    clear, bad, veiled, missing = [], [], [], []
    for vantage, target in claims():
        if vantage not in pos or target not in pos:
            missing.append((vantage, target))
            continue
        is_blocked, worst, dist = blocked_at(hs, pos[vantage], pos[target], k, kd.get(target, ""))
        row = (worst, dist, vantage, target)
        if not is_blocked:
            clear.append(row)
        elif kd.get(target) == "hidden_valley":
            # A line into a hidden valley is the way in, not the place. The land refusing it
            # is the valley doing its job, so it is counted apart rather than as a fault.
            veiled.append(row)
        else:
            bad.append(row)

    total = len(clear) + len(bad) + len(veiled) + len(missing)
    print("%d authored sightlines: %d the land honours, %d it refuses, %d into hidden valleys, "
          "%d with no placed pad\n" % (total, len(clear), len(bad), len(veiled), len(missing)))
    for worst, dist, v, t in sorted(bad, reverse=True):
        reason = "out of sight range" if worst == float("inf") else "ground %.0f m over the line" % worst
        print("  %-30s -> %-30s %-16s %5.0f m   %s"
              % (nm.get(v, v), nm.get(t, t), kd.get(t, ""), dist, reason))
    for worst, dist, v, t in sorted(veiled, reverse=True):
        print("  %-30s -> %-30s %-16s %5.0f m   veiled: %.0f m over the line"
              % (nm.get(v, v), nm.get(t, t), kd.get(t, ""), dist, worst))
    for v, t in missing:
        print("  %-34s -> %-34s  no pad in the built world" % (nm.get(v, v), nm.get(t, t)))
    if a.verbose:
        print("\nclear:")
        for worst, dist, v, t in sorted(clear, key=lambda r: -r[1]):
            print("  %-34s -> %-34s  %5.0f m" % (nm.get(v, v), nm.get(t, t), dist))
    # Every POI is supposed to be reachable by eye from somewhere.
    reachable = {t for _, _, _, t in clear}
    orphans = sorted({t for _, t in claims()} - reachable)
    # A hidden valley is called hidden. It is found by walking into it, and a sightline to one
    # means the way in rather than the place, so it is not counted against the placement.
    hidden = [o for o in orphans if kd.get(o) == "hidden_valley"]
    orphans = [o for o in orphans if kd.get(o) != "hidden_valley"]
    if orphans:
        print("\n%d POIs that no vantage can actually see:" % len(orphans))
        for o in orphans:
            print("  %-30s %s" % (nm.get(o, o), kd.get(o, "")))
    if hidden:
        print("\n%d hidden valleys, which is what they are for: %s"
              % (len(hidden), ", ".join(nm.get(o, o) for o in hidden)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
