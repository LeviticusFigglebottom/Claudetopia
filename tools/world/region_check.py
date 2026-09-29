#!/usr/bin/env python3
"""A region's definition of done for the world-life work (docs/WORLD_LIFE.md).

    python3 tools/world/region_check.py hearthvale                       # content + placement + density
    GODOT=... ~/bin/heavy python3 tools/world/region_check.py hearthvale --godot
                                    # and raise the region's new (unbuilt) POIs in Godot and seat them
    ... --edited foxglove_dell,gosling_pit   # POIs moved or resized since the build: previewed too
    python3 tools/world/region_check.py all                              # every region (no Godot)

Three parts, each PASS or FAIL, and the run exits 1 when any fails:

1. **Content**: the region's POI file holds only its own POIs, with ids `core:poi/<snake_case>` found
   nowhere else in the pack; every def has name, region, a kind a builder builds
   (PoiDressing.KINDS_BUILT), a position on the region's own dry land (the installed world's
   region map; a bridge, wreck, waterfall may stand in water), a unique_feature and a story; the
   region's encounter files name places that exist and foes, items and books that exist; the atlas
   check (worldgen/atlas.py) says nothing against the region's POIs; the hook table
   (tables/poi_hooks.json) is up to date for them (`python3 tools/poi_hooks.py` rewrites it).
2. **Placement** of the region's POIs the world was not built with (and `--edited` ones): no pad on
   top of another's (closer than the larger radius) and none overlapping a settlement's; no road
   through the level core of a place that is not road furniture; with `--godot`, the probe raises
   each on a pad laid at runtime (tools_gd/poi_probe.gd) and the seat audit finds nothing floating,
   buried, sunk or standing in a road among its pieces, no piece past its pad by more than
   PAST_PAD_M; its own draw calls and primitives are within the per-place budget. Without Godot: the
   ground under a new pad slopes no more than region_audit.SITE_STEEP_DEG on average.
3. **Density**: the region's numbers against tools/world/region_targets.json: the share of its land
   further than 200 m from any place, POI or roadside mark, its largest empty stretch, how many of
   its POIs are weak and how many strong (region_audit.py's impact score), how many it has.
   New POIs count where their defs stand. A POI with no probe measurement (built since the
   committed probe, run without --godot) scores without its size.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import region_audit as AUD  # noqa: E402
from worldgen import atlas as ATLAS  # noqa: E402
from worldgen import content as CONTENT  # noqa: E402

PACK = AUD.PACK
TARGETS = os.path.join(HERE, "region_targets.json")
DRESSING = os.path.join(REPO, "game", "world", "pois", "poi_dressing.gd")
ID_RE = re.compile(r"^core:poi/[a-z0-9]+(_[a-z0-9]+)*$")
## Placement limits for a new place (the probe's measurements).
SEAT_FAILS = ("floating", "buried", "sunk", "on_road")
PAST_PAD_M = 4.0
## One place's own cost, as the probe counts it (surfaces before shadows, triangles).
PLACE_DRAWS = 300
PLACE_PRIMS = 600_000


def kinds_built() -> set:
    text = open(DRESSING, encoding="utf-8").read()
    body = text[text.index("const KINDS_BUILT"):]
    return set(re.findall(r'"([a-z_]+)"', body[:body.index("]")]))


class Part:
    def __init__(self, name: str) -> None:
        self.name = name
        self.fails: list = []
        self.notes: list = []

    def fail(self, msg: str) -> None:
        self.fails.append(msg)

    def show(self) -> bool:
        print("%s %s" % ("PASS" if not self.fails else "FAIL", self.name))
        for m in self.fails[:60]:
            print("   x %s" % m)
        if len(self.fails) > 60:
            print("   ... and %d more" % (len(self.fails) - 60))
        for m in self.notes:
            print("   - %s" % m)
        return not self.fails


def check_content(region: str, world, content: dict, atlas: dict) -> Part:
    part = Part("content (%s)" % region)
    built = kinds_built()
    all_ids = {}
    for sub in ("places", "pois"):
        for row, name in CONTENT.rows(PACK, sub, with_file=True):
            if isinstance(row, dict) and row.get("id"):
                if row["id"] in all_ids:
                    part.fail("%s is defined in %s and %s" % (row["id"], all_ids[row["id"]], name))
                all_ids[row["id"]] = "%s/%s" % (sub, name)
    idx = world.region_index[region]
    mine = []
    for row, name in CONTENT.rows(PACK, "pois", with_file=True):
        if name == "%s.json" % region:
            mine.append(row)
            if CONTENT.region_of(row) != region:
                part.fail("%s is in pois/%s but says region %s" % (row.get("id"), name, row.get("region")))
        elif CONTENT.region_of(row) == region and not name.startswith("_"):
            part.fail("%s (%s) is in pois/%s, not pois/%s.json" % (row.get("id"), region, name, region))
    for d in mine:
        pid = str(d.get("id", ""))
        if not ID_RE.match(pid):
            part.fail("%s: an id is core:poi/<snake_case>" % pid)
        for key in ("name", "kind", "position", "unique_feature", "story"):
            if not d.get(key):
                part.fail("%s has no %s" % (pid, key))
        if "hearthstone" in d and not isinstance(d["hearthstone"], bool):
            part.fail("%s: hearthstone is true or false" % pid)
        if d.get("kind") and d["kind"] not in built:
            part.fail("%s: no builder builds the kind %r (PoiDressing.KINDS_BUILT)" % (pid, d["kind"]))
        pos = d.get("position") or []
        if len(pos) >= 2:
            x, z = float(pos[0]), float(pos[1])
            i, j = world.ij(x, z)
            # a new place is held to it; one the world was built with is told (it may be meant: a jetty)
            say = part.fail if pid not in world.built else part.notes.append
            wet_ok = d.get("kind") in AUD.WET_KINDS
            if int(world.R[i, j]) != idx and not (wet_ok and world.W[i, j]):
                say("%s at (%.0f, %.0f) is not on %s's ground (the region map says %s)"
                    % (pid, x, z, region, world.man["regions"][world.R[i, j]].split("/")[-1]
                       if world.R[i, j] < len(world.man["regions"]) else "none"))
            if world.W[i, j] and not wet_ok:
                say("%s at (%.0f, %.0f) stands in water" % (pid, x, z))
        for v in d.get("visible_from", []):
            if v not in all_ids:
                part.fail("%s: visible_from names %s, which is nowhere" % (pid, v))
        if d.get("pad_radius_m") and not (8.0 <= float(d["pad_radius_m"]) <= 60.0):
            part.fail("%s: pad_radius_m %.0f is outside 8-60 m" % (pid, float(d["pad_radius_m"])))
    # the region's encounters, finds and notes
    defs = {}
    for sub in ("enemies", "bosses", "items", "books", "npcs"):
        for row in CONTENT.rows(PACK, sub):
            if isinstance(row, dict) and row.get("id"):
                defs[row["id"]] = row
    for sub, prefixes in (("encounters", ("pois_", "wayside_")), ("items", ("wayside_",)), ("books", ("wayside_",))):
        for row, name in CONTENT.rows(PACK, sub, with_file=True):
            if not any(name == "%s%s.json" % (p, region) for p in prefixes):
                continue
            rid = row.get("id", "?")
            if sub == "encounters":
                if row.get("place") not in all_ids:
                    part.fail("%s (%s): no place %s" % (rid, name, row.get("place")))
                for s in row.get("spawns", []):
                    if s.get("enemy") and s["enemy"] not in defs:
                        part.fail("%s: no enemy %s" % (rid, s["enemy"]))
                for lying in row.get("lies", []):
                    what = lying.get("item") or lying.get("book")
                    if what and what not in defs:
                        part.fail("%s: lies %s, which is nowhere" % (rid, what))
            if sub == "items" and row.get("reads") and row["reads"] not in defs:
                part.fail("%s reads %s, which is nowhere" % (rid, row["reads"]))
    # the atlas's word on them
    errors, warnings = ATLAS.check(atlas, PACK)
    ids = {d.get("id") for d in mine}
    for e in errors:
        if any(i and i in e for i in ids):
            part.fail("atlas: " + e)
    for w in warnings:
        if any(i and i in w for i in ids):
            part.notes.append("atlas warns: " + w)
    # the hook table
    import poi_hooks as HOOKS
    table = json.load(open(HOOKS.TABLE, encoding="utf-8"))
    table = table[0] if isinstance(table, list) else table
    have = {r["poi"]: r for r in table.get("rows", [])}
    for r in HOOKS.rows(HOOKS.defs()):
        if r["poi"] in ids and have.get(r["poi"]) != r:
            part.fail("tables/poi_hooks.json is stale for %s: run python3 tools/poi_hooks.py" % r["poi"])
    part.notes.append("%d POIs in pois/%s.json" % (len(mine), region))
    return part


def check_placement(region: str, world, content: dict, marks: list, probe: dict, edited: list) -> Part:
    part = Part("placement of new and edited POIs (%s)" % region)
    fresh = [t for t in marks if t["cls"] == "poi" and t["region"] == region
             and (not t["built"] or t["id"] in edited)]
    if not fresh:
        part.notes.append("no POI here the world was not built with, and none named --edited")
    rows = {r["id"]: r for r in AUD.poi_rows(world, region, content, probe)}
    for t in fresh:
        r = rows.get(t["id"], {})
        for u in marks:
            if u["cls"] == "roadside" or u["id"] == t["id"]:
                continue
            d = ((t["x"] - u["x"]) ** 2 + (t["z"] - u["z"]) ** 2) ** 0.5
            if d < max(t["r"], u["r"]):
                part.fail("%s stands on %s's pad (%.0f m apart)" % (t["id"], u["id"], d))
            elif u["cls"] == "place" and d < t["r"] + u["r"]:
                part.fail("%s's pad overlaps the settlement %s's (%.0f m apart)" % (t["id"], u["id"], d))
        if not t["built"]:
            sd = AUD.site_deg(world, t["x"], t["z"], t["r"])
            if sd > AUD.SITE_STEEP_DEG:
                part.fail("%s: the ground under its pad slopes %.0f deg on average (over %.0f): the build will "
                          "cut and fill it hard; find gentler ground" % (t["id"], sd, AUD.SITE_STEEP_DEG))
        rd = min((((t["x"] - x) ** 2 + (t["z"] - z) ** 2) ** 0.5 for rr in world.roads for x, z in rr["points"]),
                 default=1e9)
        if rd < 0.7 * t["r"] - 3.0 and t["kind"] not in AUD.ROAD_KINDS and not t["def"].get("wayside"):
            part.fail("%s: a road passes %.0f m from its middle, inside its level core" % (t["id"], rd))
        p = probe.get(t["id"])
        if p is None:
            part.notes.append("%s was not raised (run with --godot to seat it)" % t["id"])
            continue
        for check in SEAT_FAILS:
            n = int(p.get("seat", {}).get(check, 0))
            if n:
                ex = next((f for f in p.get("findings", []) if f.get("check") == check), {})
                part.fail("%s: %d %s (e.g. %s %s)" % (t["id"], n, check, ex.get("family", ""), ex.get("detail", "")))
        reach = float(p.get("footprint", {}).get("reach", 0.0))
        if reach > float(p.get("radius_flat_m", t["r"])) + PAST_PAD_M:
            part.fail("%s: pieces reach %.0f m out, past its %.0f m pad (give the def a pad_radius_m)"
                      % (t["id"], reach, float(p.get("radius_flat_m", t["r"]))))
        if int(p.get("draws", 0)) > PLACE_DRAWS or int(p.get("primitives", 0)) > PLACE_PRIMS:
            part.fail("%s costs %d draws / %.0f k triangles, over %d / %d k for one place"
                      % (t["id"], int(p["draws"]), int(p["primitives"]) / 1000.0, PLACE_DRAWS, PLACE_PRIMS // 1000))
        part.notes.append("%s: score %s, reach %.0f m, %d draws, %.0f k tris, seat %s"
                          % (t["id"], r.get("score", "?"), reach, int(p.get("draws", 0)),
                             int(p.get("primitives", 0)) / 1000.0, p.get("seat", {}) or "clean"))
    return part


def check_density(region: str, a: dict) -> Part:
    part = Part("density (%s)" % region)
    targets = json.load(open(TARGETS, encoding="utf-8")).get(region, {})
    s = a["stats"]
    non_wayside = [r for r in a["rows"] if not r["wayside"]]
    weak_share = s["weak"] / max(len(non_wayside), 1)
    now = {"far_share_200": s["share_by_m"]["200"], "largest_gap_km2": s["largest_gap_km2"],
           "weak_share": round(weak_share, 3), "strong": s["strong"], "pois": s["pois"]}
    rules = [("far_share_200", "max", "share of land > 200 m from anything"),
             ("largest_gap_km2", "max", "largest empty stretch (km2)"),
             ("weak_share", "max", "weak share of the non-wayside POIs"),
             ("strong", "min", "POIs scoring 8 or more"),
             ("pois", "min", "POIs")]
    for key, how, what in rules:
        if key not in targets:
            continue
        want = targets[key]
        ok = now[key] <= want if how == "max" else now[key] >= want
        line = "%s: %s (target %s %s)" % (what, now[key], "at most" if how == "max" else "at least", want)
        (part.notes.append if ok else part.fail)(line)
    if s["probed"] < s["pois"]:
        part.notes.append("%d of %d POIs have no probe measurement and score without their size"
                          % (s["pois"] - s["probed"], s["pois"]))
    return part


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("region")
    ap.add_argument("--godot", action="store_true", help="raise the new POIs in Godot (./run.sh poi-probe)")
    ap.add_argument("--edited", default="", help="POIs moved or resized since the build, to preview too")
    args = ap.parse_args(argv)
    regions = list(AUD.REGIONS) if args.region == "all" else [args.region]
    world = AUD.World()
    content = AUD.load_content()
    atlas = ATLAS.load()
    marks = AUD.things(world, content)
    ok = True
    for region in regions:
        edited = ["core:poi/%s" % e if not e.startswith("core:") else e for e in args.edited.split(",") if e]
        probe = AUD.load_probe(os.path.join(AUD.OUT, "probe_%s.json" % region))
        fresh = [t["id"] for t in marks if t["cls"] == "poi" and t["region"] == region and not t["built"]]
        for e in edited:
            probe.pop(e, None)                   # measured where it stood before; measured again below
            for t in marks:
                if t["id"] == e:                 # and it counts where its def now stands
                    t["x"], t["z"] = float(t["def"]["position"][0]), float(t["def"]["position"][1])
                    t["r"] = AUD.RD.pad_radius(dict(t["def"]))
        if args.godot and (fresh or edited):
            with tempfile.TemporaryDirectory() as tmp:
                out = os.path.join(tmp, "probe.json")
                extra = ["--only=%s" % ",".join(fresh + edited)]
                if edited:
                    extra.append("--preview-pois=%s" % ",".join(edited))
                AUD.run_probe(region, out, extra)
                probe.update(AUD.load_probe(out))
        parts = [check_content(region, world, content, atlas),
                 check_placement(region, world, content, marks, probe, edited)]
        a = AUD.audit(region, world, content, atlas, probe, AUD.GAP_M, marks)
        parts.append(check_density(region, a))
        print("== %s" % region)
        for p in parts:
            ok = p.show() and ok
    print("RESULT: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
