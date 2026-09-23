"""The atlas: the authored geography the land is made from (tools/world/atlas/SCHEMA.md).

This module reads and checks an atlas. It does two kinds of checking:

* the shape of the document, against tools/world/atlas/atlas.schema.json (a small validator for
  the part of JSON Schema that file uses, so the builder needs nothing it did not already);
* what the shape cannot say: that a province names a region the content packs have, that a
  polygon does not cross itself, that a river ends in water, that every place stands on land in
  a province of its own region, that a road runs between places that exist.

`check(atlas, pack_dir)` returns (errors, warnings). An error is something the builder cannot
make a world from, or would make a world the game's own tests refuse; a warning is something
the cartographer probably did not mean.
"""
from __future__ import annotations

import json
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ATLAS_DIR = os.path.join(os.path.dirname(HERE), "atlas")
ATLAS_PATH = os.path.join(ATLAS_DIR, "atlas.json")
SCHEMA_PATH = os.path.join(ATLAS_DIR, "atlas.schema.json")

## The kinds of place the road network is for (worldgen/roads.py ROAD_KINDS): a settlement the
## atlas gives no road to is walked to across country, which is worth a warning.
SETTLEMENT_KINDS = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
## The game's own test (test_world_data.gd) holds these out of the water.
DRY_KINDS = ("city", "town", "village", "hamlet", "fort", "camp")
## How close a river's mouth has to come to another river to be its tributary.
CONFLUENCE_M = 40.0


def load(path: str = ATLAS_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_schema(path: str = SCHEMA_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# --- the document's shape ------------------------------------------------------------------

_TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool,
    "number": (int, float), "integer": int,
}


def _is_type(value, name: str) -> bool:
    if name in ("number", "integer") and isinstance(value, bool):
        return False
    return isinstance(value, _TYPES[name])


def schema_errors(value, schema: dict, root: dict | None = None, where: str = "atlas") -> list:
    """Every way `value` departs from `schema`, as readable lines. The subset used by
    atlas.schema.json: $ref (local), type, const, enum, required, properties,
    additionalProperties (false), items, minItems, maxItems, minimum, maximum, pattern."""
    root = root if root is not None else schema
    if "$ref" in schema:
        ref = schema["$ref"]
        node = root
        for step in ref.lstrip("#/").split("/"):
            node = node[step]
        return schema_errors(value, node, root, where)
    out: list = []
    if "type" in schema and not _is_type(value, schema["type"]):
        return ["%s: should be %s, is %s" % (where, schema["type"], type(value).__name__)]
    if "const" in schema and value != schema["const"]:
        out.append("%s: must be %r" % (where, schema["const"]))
    if "enum" in schema and value not in schema["enum"]:
        out.append("%s: %r is not one of %s" % (where, value, ", ".join(map(str, schema["enum"]))))
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            out.append("%s: %s is under %s" % (where, value, schema["minimum"]))
        if "maximum" in schema and value > schema["maximum"]:
            out.append("%s: %s is over %s" % (where, value, schema["maximum"]))
    if isinstance(value, str) and "pattern" in schema and not re.search(schema["pattern"], value):
        out.append("%s: %r does not look like %s" % (where, value, schema["pattern"]))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            out.append("%s: needs at least %d items, has %d" % (where, schema["minItems"], len(value)))
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            out.append("%s: takes at most %d items, has %d" % (where, schema["maxItems"], len(value)))
        if "items" in schema:
            for k, item in enumerate(value):
                out.extend(schema_errors(item, schema["items"], root, "%s[%d]" % (where, k)))
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                out.append("%s: missing %r" % (where, key))
        props = schema.get("properties", {})
        for key, item in value.items():
            if key in props:
                out.extend(schema_errors(item, props[key], root, "%s.%s" % (where, key)))
            elif schema.get("additionalProperties", True) is False:
                out.append("%s: unknown field %r" % (where, key))
    return out


# --- geometry -------------------------------------------------------------------------------

def point_in_polygon(x: float, z: float, poly) -> bool:
    """Even-odd rule; a point on an edge may land either side."""
    inside = False
    n = len(poly)
    for k in range(n):
        x0, z0 = poly[k][0], poly[k][1]
        x1, z1 = poly[(k + 1) % n][0], poly[(k + 1) % n][1]
        if (z0 > z) != (z1 > z):
            t = (z - z0) / (z1 - z0)
            if x < x0 + t * (x1 - x0):
                inside = not inside
    return inside


def polygon_area(poly) -> float:
    """Unsigned area in square metres (shoelace)."""
    s = 0.0
    n = len(poly)
    for k in range(n):
        x0, z0 = poly[k][0], poly[k][1]
        x1, z1 = poly[(k + 1) % n][0], poly[(k + 1) % n][1]
        s += x0 * z1 - x1 * z0
    return abs(s) * 0.5


def _segments_cross(a, b, c, d) -> bool:
    """Whether segment ab properly crosses segment cd (touching ends do not count)."""
    def orient(p, q, r):
        v = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return 0 if abs(v) < 1e-9 else (1 if v > 0 else -1)
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return o1 * o2 < 0 and o3 * o4 < 0


def self_crossings(poly, closed: bool = True) -> list:
    """[(k, m)] pairs of edges that cross each other."""
    n = len(poly)
    edges = n if closed else n - 1
    out = []
    for k in range(edges):
        a, b = poly[k], poly[(k + 1) % n]
        for m in range(k + 2, edges):
            if closed and k == 0 and m == edges - 1:
                continue                        # neighbours through the closing edge
            c, d = poly[m], poly[(m + 1) % n]
            if _segments_cross(a, b, c, d):
                out.append((k, m))
    return out


def distance_to_path(x: float, z: float, path) -> float:
    best = math.inf
    for k in range(len(path) - 1):
        x0, z0 = path[k][0], path[k][1]
        x1, z1 = path[k + 1][0], path[k + 1][1]
        dx, dz = x1 - x0, z1 - z0
        L2 = dx * dx + dz * dz
        t = 0.0 if L2 <= 0 else max(0.0, min(1.0, ((x - x0) * dx + (z - z0) * dz) / L2))
        best = min(best, math.hypot(x - (x0 + t * dx), z - (z0 + t * dz)))
    return best


def on_land(atlas: dict, x: float, z: float) -> bool:
    coast = atlas.get("coast", {})
    if point_in_polygon(x, z, coast.get("polygon", [])):
        return True
    if any(point_in_polygon(x, z, isl) for isl in coast.get("islands", [])):
        return True
    return any(point_in_polygon(x, z, s["polygon"]) for s in coast.get("shelves", []))


def lake_at(atlas: dict, x: float, z: float):
    """The lake whose water covers (x, z), or None (its islands are not water)."""
    for lake in atlas.get("lakes", []):
        if point_in_polygon(x, z, lake["polygon"]):
            if any(point_in_polygon(x, z, isl["polygon"]) for isl in lake.get("islands", [])):
                return None
            return lake
    return None


def province_at(atlas: dict, x: float, z: float):
    """The province (x, z) is inside, the one it is deepest inside where two overlap, and the
    nearest where it is in none: the rule the builder's province weights follow."""
    best, best_d = None, -math.inf
    for p in atlas.get("provinces", []):
        poly = p["polygon"]
        d = distance_to_path(x, z, list(poly) + [poly[0]])
        signed = d if point_in_polygon(x, z, poly) else -d
        if signed > best_d:
            best, best_d = p, signed
    return best, best_d


# --- what the shape cannot say ----------------------------------------------------------------

def _content(pack_dir: str) -> tuple:
    def read(*parts):
        path = os.path.join(pack_dir, *parts)
        if not os.path.exists(path):
            return []
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else [data]
    regions = read("regions", "regions.json")
    places = read("places", "places.json")
    pois = read("pois", "pois.json")
    return regions, places, pois


def check(atlas: dict, pack_dir: str, schema: dict | None = None) -> tuple:
    """(errors, warnings) for an atlas against its schema and the content packs."""
    schema = schema if schema is not None else load_schema()
    errors = schema_errors(atlas, schema)
    warnings: list = []
    if errors:
        return errors, warnings            # the rest reads fields the shape check vouches for
    regions, places, pois = _content(pack_dir)
    region_ids = {r["id"] for r in regions}
    things = {p["id"]: p for p in places}
    things.update({p["id"]: p for p in pois})

    def polygon_ok(poly, where):
        if polygon_area(poly) < 1.0:
            errors.append("%s: the polygon has no area" % where)
        crossings = self_crossings(poly)
        if crossings:
            k, m = crossings[0]
            errors.append("%s: the polygon crosses itself (edge %d, from %s, and edge %d, from %s%s)"
                          % (where, k, poly[k], m, poly[m],
                             "" if len(crossings) == 1 else ", and %d more" % (len(crossings) - 1)))

    # provinces
    seen: dict = {}
    for k, p in enumerate(atlas["provinces"]):
        where = "provinces[%d] (%s)" % (k, p["id"])
        if p["id"] in seen:
            errors.append("%s: the id is used twice" % where)
        seen[p["id"]] = p
        if p["region"] not in region_ids:
            errors.append("%s: no region %s in the content packs (there are: %s)"
                          % (where, p["region"], ", ".join(sorted(region_ids))))
        polygon_ok(p["polygon"], where)
    covered = {p["region"] for p in atlas["provinces"]}
    for rid in sorted(region_ids - covered):
        warnings.append("region %s has no province: it will have no ground, and nothing of it "
                        "can be entered" % rid)

    coast = atlas["coast"]
    polygon_ok(coast["polygon"], "coast.polygon")
    for k, isl in enumerate(coast.get("islands", [])):
        polygon_ok(isl, "coast.islands[%d]" % k)
    for k, shelf in enumerate(coast.get("shelves", [])):
        polygon_ok(shelf["polygon"], "coast.shelves[%d]" % k)
        if not any(point_in_polygon(x, z, coast["polygon"]) for x, z in shelf["polygon"]):
            warnings.append("coast.shelves[%d]: no corner of it is on the mainland, so the sea runs "
                            "between it and the land behind it: draw it back under the coast" % k)

    for k, r in enumerate(atlas.get("ranges", [])):
        where = "ranges[%d] (%s)" % (k, r["id"])
        if r.get("profile") == "scarp" and "face" not in r:
            errors.append("%s: a scarp needs a face (left or right, walking the ridge from its "
                          "first point to its last)" % where)
        if any(pt[2] <= 0 for pt in r["ridge"]):
            errors.append("%s: every crest height must be above sea level" % where)

    for k, v in enumerate(atlas.get("valleys", [])):
        if len(v["path"]) < 2:
            errors.append("valleys[%d]: a path needs two points" % k)

    lakes = atlas.get("lakes", [])
    for k, lake in enumerate(lakes):
        where = "lakes[%d] (%s)" % (k, lake["id"])
        polygon_ok(lake["polygon"], where)
        outside = [pt for pt in lake["polygon"] if not on_land(atlas, pt[0], pt[1])]
        if outside:
            errors.append("%s: %d of its shore points are in the sea, e.g. %s" % (where, len(outside), outside[0]))
        for m, isl in enumerate(lake.get("islands", [])):
            polygon_ok(isl["polygon"], "%s.islands[%d]" % (where, m))
            if not all(point_in_polygon(pt[0], pt[1], lake["polygon"]) for pt in isl["polygon"]):
                errors.append("%s.islands[%d]: the island is not inside its lake" % (where, m))
            if isl["height_m"] <= lake["level_m"]:
                errors.append("%s.islands[%d]: an island %.1f m high is under the lake's surface "
                              "(%.1f m)" % (where, m, isl["height_m"], lake["level_m"]))

    rivers = atlas.get("rivers", [])
    for k, rv in enumerate(rivers):
        where = "rivers[%d] (%s)" % (k, rv["id"])
        sx, sz = rv["path"][0]
        mx, mz = rv["path"][-1]
        if not on_land(atlas, sx, sz):
            errors.append("%s: it rises in the sea at %s" % (where, rv["path"][0]))
        into_sea = not on_land(atlas, mx, mz)
        into_lake = lake_at(atlas, mx, mz) is not None
        into_river = any(distance_to_path(mx, mz, other["path"]) <= CONFLUENCE_M
                         for m, other in enumerate(rivers) if m != k)
        if not (into_sea or into_lake or into_river):
            errors.append("%s: its mouth %s is not in the sea, a lake or another river (within %d m); "
                          "the path runs from source to mouth" % (where, rv["path"][-1], CONFLUENCE_M))
        w0, w1 = rv["width_m"]
        if w1 < w0:
            warnings.append("%s: it narrows toward its mouth (%.0f m to %.0f m)" % (where, w0, w1))

    for k, f in enumerate(atlas.get("forests", [])):
        polygon_ok(f["polygon"], "forests[%d]" % k)

    # places and points of interest stand where the content packs put them
    for thing in list(places) + list(pois):
        pos = thing.get("position")
        if not pos or len(pos) < 2:
            continue
        x, z = float(pos[0]), float(pos[1])
        name = thing["id"]
        is_place = ":place/" in name
        kind = str(thing.get("kind", ""))
        # an edge of the world is where the world stops, and a deep place is under it
        if kind in ("edge", "deep_place", "interior_dungeon"):
            continue
        if not on_land(atlas, x, z):
            (errors if kind in DRY_KINDS else warnings).append(
                "%s stands in the sea at (%.0f, %.0f)" % (name, x, z))
            continue
        lake = lake_at(atlas, x, z)
        if lake is not None and kind != "bridge":
            (errors if kind in DRY_KINDS else warnings).append(
                "%s stands in %s at (%.0f, %.0f)" % (name, lake["id"], x, z))
        prov, depth = province_at(atlas, x, z)
        if prov is None:
            continue
        region = thing.get("region", "")
        if region and prov["region"] != region:
            msg = ("%s (%s) stands in province %s, which is %s" % (name, region, prov["id"], prov["region"]))
            (errors if is_place else warnings).append(msg)
        elif region and depth < float(prov.get("blend_m", 300.0)) * 0.5 and is_place:
            warnings.append("%s is %.0f m inside its province %s, within the border's blend: its "
                            "ground may take on the neighbour's" % (name, max(depth, 0.0), prov["id"]))

    # roads
    pairs: dict = {}
    for k, road in enumerate(atlas.get("roads", [])):
        where = "roads[%d] (%s - %s)" % (k, road["from"], road["to"])
        for end in ("from", "to"):
            if road[end] not in things:
                errors.append("%s: no place or POI %s in the content packs" % (where, road[end]))
        if road["from"] == road["to"]:
            errors.append("%s: a road from a place to itself" % where)
        key = tuple(sorted((road["from"], road["to"])))
        if key in pairs and road.get("via") == pairs[key].get("via"):
            warnings.append("%s: the same road twice" % where)
        pairs[key] = road
    roaded = {end for road in atlas.get("roads", []) for end in (road["from"], road["to"])}
    for p in places:
        if str(p.get("kind", "")) in SETTLEMENT_KINDS and p["id"] not in roaded:
            warnings.append("%s (%s) has no road" % (p["id"], p.get("kind")))

    seen_pads: set = set()
    for k, pad in enumerate(atlas.get("pads", [])):
        where = "pads[%d] (%s)" % (k, pad["place"])
        if pad["place"] not in things:
            errors.append("%s: no place or POI %s in the content packs" % (where, pad["place"]))
            continue
        if pad["place"] in seen_pads:
            errors.append("%s: the place's pad is given twice" % where)
        seen_pads.add(pad["place"])
        pos = things[pad["place"]].get("position") or [0, 0]
        x, z = float(pos[0]), float(pos[1])
        lake = lake_at(atlas, x, z)
        water = float(lake["level_m"]) if lake is not None else 0.0
        if pad["level_m"] < water + 1.0:
            errors.append("%s: a pad at %.1f m is within a metre of the water there (%.1f m): "
                          "whatever stands on it is awash" % (where, pad["level_m"], water))

    start = atlas.get("start")
    if start:
        x, z = start["at"]
        if not on_land(atlas, x, z):
            errors.append("start: (%.0f, %.0f) is in the sea" % (x, z))
        elif lake_at(atlas, x, z) is not None:
            errors.append("start: (%.0f, %.0f) is in a lake" % (x, z))
        for rv in rivers:
            if distance_to_path(x, z, rv["path"]) < max(rv["width_m"]) + 6.0:
                errors.append("start: (%.0f, %.0f) is in %s" % (x, z, rv["id"]))
        if start.get("place") and start["place"] not in things:
            errors.append("start: no place or POI %s in the content packs" % start["place"])
    else:
        warnings.append("no start: a new game begins where the opening's place is")
    return errors, warnings
