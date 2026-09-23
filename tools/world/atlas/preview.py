"""The cartographer's reading of the atlas: the country it describes, drawn coarse.

This is not the world builder and nothing in the game reads it. It is a quick model of what
`atlas.json` says, made from the atlas alone at 8 m, so the map can be drawn and the atlas
checked for the things a schema cannot see: that a river runs downhill, that a line of sight
the content packs claim is not through a range, and that the country is full enough to walk.
The world builder makes the real land (tools/world/atlas/SCHEMA.md); where the two differ, the
builder is right about the ground and this is right about what the atlas asked for.

    from preview import Atlas
    a = Atlas.load()                 # tools/world/atlas/atlas.json and the core content pack
    a.heights                        # metres, [z, x] at a.res
    a.survey()                       # walkable land, locations, the density figures

Everything here is a pure function of the atlas and the content packs; nothing is random.
"""
from __future__ import annotations

import json
import math
import os
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
PACK = os.path.join(REPO, "game", "content", "packs", "core")
ATLAS_PATH = os.path.join(HERE, "atlas.json")

SIZE_M = 8192.0
HALF_M = SIZE_M / 2.0

## The density rule (the brief the atlas was drawn to): no walkable point more than this far from
## a notable location, and nothing on a road more than ROAD_REACH_M from one.
REACH_M = 400.0
ROAD_REACH_M = 250.0
## Ground steeper than this (rise over run, about 35 degrees) is cliff, not country: nobody is
## asked to find a location on it.
WALKABLE_SLOPE = 0.70
## The ranges that close the world (SCHEMA.md: "close it: sea, or a range too steep to climb"),
## and the side of each that is off the map: the ground past their crests is the world's edge,
## not country. Above the snowline (the mountains biome's, SCHEMA.md) is snowfield and crag, not
## country either.
CLOSURES = {"skerrow_wall": "north", "thornmarch": "east"}
## A closing range's crest itself, and this much of the country's side of it, is the rampart, not
## country: a col in the Wall is still the Wall.
CREST_M = 120.0
SNOWLINE_M = 520.0
## The kinds of place that are the world's edge rather than a place in it.
EDGE_KINDS = ("edge",)

## place_discovery.gd, read by tools/sightlines.py: how far a thing of each kind stands above its
## ground for being seen, the eye, and how far the haze lets you see.
EYE_M = 1.65
LANDMARK_M = {
    "tower": 10.0, "waterfall": 13.0, "strange_tree": 14.0, "giant_bones": 13.0,
    "ruins": 6.0, "strange": 2.5, "wreck": 5.0, "standing_stones": 5.0,
    "bridge": 4.5, "shrine": 4.0, "camp": 2.5, "hidden_valley": 1.0,
}
LANDMARK_DEFAULT_M = 6.0
CLEARANCE_M = 2.0
FOREGROUND_M = 140.0
MAX_SIGHT_M = 4200.0


# --- reading ---------------------------------------------------------------------------------

def read_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_pack(pack: str = PACK) -> tuple:
    """(places, pois, regions) from the content pack."""
    def rows(*parts):
        p = os.path.join(pack, *parts)
        if not os.path.exists(p):
            return []
        d = read_json(p)
        return d if isinstance(d, list) else [d]
    return rows("places", "places.json"), rows("pois", "pois.json"), rows("regions", "regions.json")


# --- geometry on a grid ----------------------------------------------------------------------

class Grid:
    """A square raster over the world: cell (i, j) is row z, column x, centred."""

    def __init__(self, res: float = 8.0):
        self.res = float(res)
        self.n = int(round(SIZE_M / self.res))
        c = (np.arange(self.n, dtype=np.float32) + 0.5) * self.res - HALF_M
        self.xs = c[None, :]
        self.zs = c[:, None]

    def to_px(self, x: float, z: float) -> tuple:
        return ((x + HALF_M) / self.res, (z + HALF_M) / self.res)

    def index(self, x: float, z: float) -> tuple:
        j = int(min(max((x + HALF_M) / self.res, 0), self.n - 1))
        i = int(min(max((z + HALF_M) / self.res, 0), self.n - 1))
        return i, j

    def polygon_mask(self, poly) -> np.ndarray:
        img = Image.new("L", (self.n, self.n), 0)
        pts = [self.to_px(p[0], p[1]) for p in poly]
        ImageDraw.Draw(img).polygon([(u - 0.5, v - 0.5) for u, v in pts], fill=1, outline=1)
        return np.asarray(img, dtype=bool)

    def window(self, pts, pad: float):
        """Row and column slices covering the points plus pad metres."""
        xs = [p[0] for p in pts]
        zs = [p[1] for p in pts]
        j0 = max(int((min(xs) - pad + HALF_M) / self.res), 0)
        j1 = min(int((max(xs) + pad + HALF_M) / self.res) + 1, self.n)
        i0 = max(int((min(zs) - pad + HALF_M) / self.res), 0)
        i1 = min(int((max(zs) + pad + HALF_M) / self.res) + 1, self.n)
        return slice(i0, i1), slice(j0, j1)

    def path_distance(self, path, pad: float, values=None):
        """(slices, distance to the path, the value interpolated at the nearest point) inside the
        path's window. `values` is one number per path point (a crest height), or None."""
        sl = self.window(path, pad)
        X = self.xs[:, sl[1]]
        Z = self.zs[sl[0], :]
        best = np.full((sl[0].stop - sl[0].start, sl[1].stop - sl[1].start), np.inf, np.float32)
        val = np.zeros_like(best)
        for k in range(len(path) - 1):
            x0, z0 = path[k][0], path[k][1]
            x1, z1 = path[k + 1][0], path[k + 1][1]
            dx, dz = x1 - x0, z1 - z0
            L2 = dx * dx + dz * dz
            if L2 <= 0:
                t = np.zeros_like(best)
            else:
                t = np.clip(((X - x0) * dx + (Z - z0) * dz) / L2, 0.0, 1.0)
            d = np.hypot(X - (x0 + t * dx), Z - (z0 + t * dz))
            closer = d < best
            best = np.where(closer, d, best)
            if values is not None:
                v = values[k] + (values[k + 1] - values[k]) * t
                val = np.where(closer, v, val)
        return sl, best, val

    def side_of_path(self, path, sl) -> np.ndarray:
        """+1 on the right of the path walking it from its first point, -1 on the left (north up,
        x east, z south: walking north, right is east), taken from the nearest segment."""
        X = self.xs[:, sl[1]]
        Z = self.zs[sl[0], :]
        best = np.full((sl[0].stop - sl[0].start, sl[1].stop - sl[1].start), np.inf, np.float32)
        side = np.zeros_like(best)
        for k in range(len(path) - 1):
            x0, z0 = path[k][0], path[k][1]
            x1, z1 = path[k + 1][0], path[k + 1][1]
            dx, dz = x1 - x0, z1 - z0
            L2 = dx * dx + dz * dz or 1.0
            t = np.clip(((X - x0) * dx + (Z - z0) * dz) / L2, 0.0, 1.0)
            d = np.hypot(X - (x0 + t * dx), Z - (z0 + t * dz))
            cross = dx * (Z - z0) - dz * (X - x0)
            closer = d < best
            best = np.where(closer, d, best)
            # z grows south, so with north up a negative cross is on the left of travel
            side = np.where(closer, np.where(cross < 0, -1.0, 1.0), side)
        return side


def point_in_polygon(x: float, z: float, poly) -> bool:
    inside = False
    n = len(poly)
    for k in range(n):
        x0, z0 = poly[k][0], poly[k][1]
        x1, z1 = poly[(k + 1) % n][0], poly[(k + 1) % n][1]
        if (z0 > z) != (z1 > z):
            if x < x0 + (z - z0) / (z1 - z0) * (x1 - x0):
                inside = not inside
    return inside


def polygon_area(poly) -> float:
    s = 0.0
    n = len(poly)
    for k in range(n):
        s += poly[k][0] * poly[(k + 1) % n][1] - poly[(k + 1) % n][0] * poly[k][1]
    return abs(s) * 0.5


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


def path_length(path) -> float:
    return sum(math.hypot(path[k + 1][0] - path[k][0], path[k + 1][1] - path[k][1])
               for k in range(len(path) - 1))


def resample(path, step: float) -> list:
    """Points every `step` metres along a path, both ends included."""
    out = [tuple(path[0][:2])]
    for k in range(len(path) - 1):
        x0, z0 = path[k][0], path[k][1]
        x1, z1 = path[k + 1][0], path[k + 1][1]
        L = math.hypot(x1 - x0, z1 - z0)
        n = max(1, int(math.ceil(L / step)))
        for s in range(1, n + 1):
            out.append((x0 + (x1 - x0) * s / n, z0 + (z1 - z0) * s / n))
    return out


# --- the character of a province's hills --------------------------------------------------------

def _waves(grid: Grid, seed: int, wavelengths, grain_deg=None, sharp: float = 1.0) -> np.ndarray:
    """A sum of long plane waves in [0, 1], fixed by `seed` (a checksum of the province's id, so
    the same atlas always draws the same hills). With a grain the waves run along it."""
    acc = np.zeros((grid.n, grid.n), np.float32)
    total = 0.0
    for k, wl in enumerate(wavelengths):
        h = zlib.crc32(("%d:%d" % (seed, k)).encode())
        if grain_deg is None:
            ang = (h % 3600) / 10.0
        else:
            # hills that run along the grain vary across it: the wave travels at right angles
            ang = grain_deg + 90.0 + ((h >> 12) % 40 - 20)
        a = math.radians(ang)
        ph = ((h >> 20) % 1000) / 1000.0 * 2 * math.pi
        kx, kz = math.sin(a), -math.cos(a)
        w = 1.0 / (1.0 + k * 0.6)
        acc += w * np.cos(2 * math.pi * (grid.xs * kx + grid.zs * kz) / wl + ph)
        total += w
    v = acc / total * 0.5 + 0.5
    if sharp != 1.0:
        v = 1.0 - np.abs(v * 2 - 1) ** sharp if sharp < 1.0 else v ** sharp
    return v.astype(np.float32)


CHARACTER = {
    # wavelengths (m), how much of relief_m, sharpening
    "flat": ((1600, 1100, 700), 0.12, 1.0),
    "marsh": ((500, 330, 220), 0.25, 1.0),
    "rolling": ((1500, 950, 620), 1.0, 1.0),
    "hills": ((780, 520, 340), 1.0, 1.0),
    "ridged": ((620, 410, 260), 1.0, 0.6),
    "plateau": ((1200, 800), 0.25, 1.0),
    "mountains": ((900, 560, 330, 210), 1.0, 0.7),
}


# --- the model ----------------------------------------------------------------------------------

class Atlas:
    """The atlas, the content pack's places, and the land the one describes under the other."""

    def __init__(self, doc: dict, places: list, pois: list, regions: list, res: float = 8.0):
        self.doc = doc
        self.places = places
        self.pois = pois
        self.regions = regions
        self.grid = Grid(res)
        self.res = self.grid.res
        self._build()

    @classmethod
    def load(cls, path: str = ATLAS_PATH, pack: str = PACK, res: float = 8.0) -> "Atlas":
        places, pois, regions = read_pack(pack)
        return cls(read_json(path), places, pois, regions, res)

    # -- the land --

    def _build(self) -> None:
        g = self.grid
        doc = self.doc
        n = g.n
        provs = doc["provinces"]
        wsum = np.zeros((n, n), np.float32)
        base = np.zeros((n, n), np.float32)
        relief = np.zeros((n, n), np.float32)
        best = np.full((n, n), -1, np.int16)
        bestw = np.zeros((n, n), np.float32)
        self.province_masks = []
        for k, p in enumerate(provs):
            m = g.polygon_mask(p["polygon"])
            self.province_masks.append(m)
            sigma = max(float(p.get("blend_m", 300.0)) * 0.35 / g.res, 1.0)
            w = ndimage.gaussian_filter(m.astype(np.float32), sigma) + m * 1e-3
            ch = p["character"]
            wl, share, sharp = CHARACTER.get(ch, CHARACTER["rolling"])
            seed = zlib.crc32(p["id"].encode())
            pat = _waves(g, seed, wl, p.get("grain_deg") if ch == "ridged" or "grain_deg" in p else None, sharp)
            wsum += w
            base += w * float(p["base_height_m"])
            relief += w * float(p["relief_m"]) * share * (pat - 0.5)
            closer = w > bestw
            best = np.where(closer, k, best)
            bestw = np.where(closer, w, bestw)
        wsum = np.maximum(wsum, 1e-6)
        self.base = base / wsum
        h = self.base + relief / wsum
        self.province_index = best

        for r in doc.get("ranges", []):
            ridge = r["ridge"]
            half = float(r["width_m"]) / 2.0
            sl, d, crest = g.path_distance(ridge, half, [p[2] for p in ridge])
            t = d / half
            prof = r.get("profile", "ridge")
            if prof == "scarp":
                side = g.side_of_path(ridge, sl)
                steep = 1.0 if r.get("face") == "right" else -1.0
                on_face = side == steep
                tt = np.where(on_face, t * 3.2, t)
                f = np.clip(1.0 - tt, 0.0, 1.0) ** np.where(on_face, 1.0, 1.6)
            elif prof == "rounded":
                f = np.where(t < 1.0, 0.5 * (1.0 + np.cos(np.pi * np.clip(t, 0, 1))), 0.0)
            elif prof == "massif":
                f = np.clip(1.0 - t * t, 0.0, 1.0) ** 0.6
            else:
                f = np.clip(1.0 - t, 0.0, 1.0) ** 1.35
            b = self.base[sl]
            rise = b + (crest - b) * f
            h[sl] = np.maximum(h[sl], np.where(f > 0, rise, -1e9))

        for pk in doc.get("peaks", []):
            x, z = pk["at"]
            R = float(pk["radius_m"])
            sl = g.window([(x, z)], R)
            d = np.hypot(g.xs[:, sl[1]] - x, g.zs[sl[0], :] - z)
            s = d / R
            shape = pk.get("shape", "cone")
            if shape == "mesa":
                f = np.clip((1.0 - s) / 0.22, 0.0, 1.0)
            elif shape == "dome":
                f = np.where(s < 1.0, 0.5 * (1.0 + np.cos(np.pi * np.clip(s, 0, 1))), 0.0)
            elif shape == "crag":
                f = np.clip(1.0 - s, 0.0, 1.0) ** 0.85
            else:
                f = np.clip(1.0 - s, 0.0, 1.0) ** 1.25
            b = self.base[sl]
            H = float(pk["height_m"])
            h[sl] = np.maximum(h[sl], np.where(f > 0, b + (H - b) * f, -1e9))

        for v in doc.get("valleys", []):
            half = float(v["width_m"]) / 2.0
            sl, d, _ = g.path_distance(v["path"], half)
            t = np.clip(d / half, 0.0, 1.0)
            prof = v.get("profile", "u")
            if prof == "v":
                cut = 1.0 - t
            elif prof == "gorge":
                cut = np.clip((1.0 - t) / 0.35, 0.0, 1.0)
            else:
                cut = np.clip(1.0 - t ** 3, 0.0, 1.0)
            h[sl] -= float(v["depth_m"]) * cut

        coast = doc["coast"]
        land = g.polygon_mask(coast["polygon"])
        for isl in coast.get("islands", []):
            land |= g.polygon_mask(isl)
        self.land = land
        seabed = float(coast.get("seabed_m", -26.0))
        shelf = float(coast.get("shelf_m", 350.0))
        beach = float(coast.get("beach_m", 60.0))
        out_d = ndimage.distance_transform_edt(~land) * g.res
        in_d = ndimage.distance_transform_edt(land) * g.res
        cliff = np.zeros((n, n), bool)
        for c in coast.get("cliffs", []):
            sl, d, _ = g.path_distance(c["path"], 90.0)
            cliff[sl] |= d < 70.0
        self.cliff_coast = cliff
        sea = seabed * np.clip(out_d / shelf, 0.0, 1.0) ** 0.7 - 1.0
        shore = np.clip(in_d / max(beach, 1.0), 0.0, 1.0)
        h = np.where(land, np.where(cliff, h, 1.0 + (h - 1.0) * shore), np.minimum(h, sea))

        water = ~land
        lake_id = np.full((n, n), -1, np.int16)
        self.lake_level = np.full((n, n), np.nan, np.float32)
        for k, lk in enumerate(doc.get("lakes", [])):
            m = g.polygon_mask(lk["polygon"])
            isl = np.zeros_like(m)
            for i in lk.get("islands", []):
                im = g.polygon_mask(i["polygon"])
                isl |= im
                h = np.where(im, np.maximum(float(i["height_m"]) - 3.0 * (1 - np.clip(
                    ndimage.distance_transform_edt(im) * g.res / 60.0, 0, 1)), float(lk["level_m"]) + 0.5), h)
            wet = m & ~isl
            lvl = float(lk["level_m"])
            dep = float(lk.get("depth_m", 10.0))
            dd = ndimage.distance_transform_edt(wet) * g.res
            dmax = max(float(dd.max()), 1.0)
            h = np.where(wet, lvl - 0.5 - dep * np.clip(dd / max(dmax * 0.6, 60.0), 0, 1) ** 0.6, h)
            # the shore held a little above the water
            near = (~m) & (ndimage.distance_transform_edt(~m) * g.res < 200.0)
            h = np.where(near, np.maximum(h, lvl + 1.0), h)
            water |= wet
            lake_id = np.where(wet, k, lake_id)
            self.lake_level = np.where(wet, lvl, self.lake_level)
        self.lake_id = lake_id

        river = np.zeros((n, n), bool)
        for rv in doc.get("rivers", []):
            w0, w1 = rv["width_m"]
            sl, d, frac = g.path_distance(rv["path"], max(w0, w1) + 16.0,
                                          np.linspace(0.0, 1.0, len(rv["path"])).tolist())
            half = (w0 + (w1 - w0) * frac) * 0.5
            river[sl] |= d <= np.maximum(half, g.res * 0.5)
        self.river = river
        water = water | river
        self.water = water
        self.heights = h.astype(np.float32)
        gz, gx = np.gradient(self.heights, g.res)
        self.slope = np.hypot(gx, gz)
        self.edge = self._edge_mask()
        self.walkable = self.land & ~water & (self.slope < WALKABLE_SLOPE) & ~self.edge

    def _edge_mask(self) -> np.ndarray:
        """The world's closures: past the crest of each closing range, and above the snowline."""
        g = self.grid
        edge = self.heights > SNOWLINE_M
        for r in self.doc.get("ranges", []):
            side = CLOSURES.get(r["id"])
            if side is None:
                continue
            crest = np.array([[p[0], p[1]] for p in r["ridge"]], np.float32)
            if side == "north":
                # beyond a crest running west to east: every column north of the crest's z there
                # (past its ends, the end's z: a closing range closes to the map's edge)
                order = np.argsort(crest[:, 0])
                zc = np.interp(g.xs[0], crest[order, 0], crest[order, 1])
                edge |= g.zs < zc[None, :] + CREST_M
            else:
                order = np.argsort(crest[:, 1])
                xc = np.interp(g.zs[:, 0], crest[order, 1], crest[order, 0])
                edge |= g.xs > xc[:, None] - CREST_M
        return edge

    # -- sampling --

    def height_at(self, x: float, z: float) -> float:
        """Bilinear over the model."""
        g = self.grid
        fx = min(max((x + HALF_M) / g.res - 0.5, 0.0), g.n - 1.001)
        fz = min(max((z + HALF_M) / g.res - 0.5, 0.0), g.n - 1.001)
        j, i = int(fx), int(fz)
        tx, tz = fx - j, fz - i
        H = self.heights
        return float((H[i, j] * (1 - tx) + H[i, j + 1] * tx) * (1 - tz)
                     + (H[i + 1, j] * (1 - tx) + H[i + 1, j + 1] * tx) * tz)

    def province_of(self, x: float, z: float):
        """The province the point is deepest inside, the atlas's own rule."""
        best, best_d = None, -math.inf
        for p in self.doc["provinces"]:
            poly = p["polygon"]
            d = distance_to_path(x, z, list(poly) + [poly[0]])
            signed = d if point_in_polygon(x, z, poly) else -d
            if signed > best_d:
                best, best_d = p, signed
        return best, best_d

    def on_land(self, x: float, z: float) -> bool:
        coast = self.doc["coast"]
        if point_in_polygon(x, z, coast["polygon"]):
            return True
        return any(point_in_polygon(x, z, i) for i in coast.get("islands", []))

    def in_lake(self, x: float, z: float):
        for lk in self.doc.get("lakes", []):
            if point_in_polygon(x, z, lk["polygon"]):
                if any(point_in_polygon(x, z, i["polygon"]) for i in lk.get("islands", [])):
                    return None
                return lk
        return None

    # -- what stands on it --

    def locations(self) -> list:
        """Every place and POI with a position: (id, name, kind, region, x, z, def)."""
        out = []
        for d in list(self.places) + list(self.pois):
            pos = d.get("position")
            if not pos or len(pos) < 2:
                continue
            out.append((d["id"], d.get("name", d["id"]), str(d.get("kind", "")), d.get("region", ""),
                        float(pos[0]), float(pos[1]), d))
        return out

    def road_paths(self) -> list:
        """Each road as the polyline its ends and waypoints make: (road, [(x, z), ...])."""
        where = {loc[0]: (loc[4], loc[5]) for loc in self.locations()}
        out = []
        for r in self.doc.get("roads", []):
            a = where.get(r["from"])
            b = where.get(r["to"])
            if a is None or b is None:
                continue
            pts = [a] + [tuple(v) for v in r.get("via", [])] + [b]
            out.append((r, pts))
        return out

    def survey(self) -> dict:
        """The density figures: how much of the country can be walked, how many notable
        locations stand in it, how far the furthest walkable ground is from one, and the same
        along the roads."""
        g = self.grid
        locs = [l for l in self.locations() if l[2] not in EDGE_KINDS]
        seeds = np.ones((g.n, g.n), bool)
        for l in locs:
            i, j = g.index(l[4], l[5])
            seeds[i, j] = False
        dist, (ii, jj) = ndimage.distance_transform_edt(seeds, return_indices=True)
        dist = dist * g.res
        walk = self.walkable
        cell_km2 = (g.res / 1000.0) ** 2
        walk_km2 = float(walk.sum()) * cell_km2
        land_km2 = float(self.land.sum()) * cell_km2
        far = walk & (dist > REACH_M)
        labels, nlab = ndimage.label(far)
        gaps = []
        if nlab:
            sizes = ndimage.sum(far, labels, range(1, nlab + 1))
            for k in np.argsort(-sizes):
                if sizes[k] * cell_km2 < 0.004:
                    break
                ys, xs = np.nonzero(labels == k + 1)
                worst = np.argmax(dist[ys, xs])
                gaps.append({"area_km2": float(sizes[k] * cell_km2),
                             "worst_m": float(dist[ys[worst], xs[worst]]),
                             "at": [float(g.xs[0, xs[worst]]), float(g.zs[ys[worst], 0])]})
        road_worst = []
        road_len = 0.0
        for r, pts in self.road_paths():
            road_len += path_length(pts)
            bad = []
            for x, z in resample(pts, 10.0):
                i, j = g.index(x, z)
                if dist[i, j] > ROAD_REACH_M:
                    bad.append((float(dist[i, j]), x, z))
            if bad:
                bad.sort(reverse=True)
                road_worst.append({"road": "%s - %s" % (r["from"], r["to"]), "worst_m": bad[0][0],
                                   "at": [bad[0][1], bad[0][2]], "points_over": len(bad)})
        road_worst.sort(key=lambda d: -d["worst_m"])
        d_walk = dist[walk]
        return {
            "land_km2": land_km2,
            "walkable_km2": walk_km2,
            "locations": len(locs),
            "places": sum(1 for l in locs if ":place/" in l[0]),
            "pois": sum(1 for l in locs if ":poi/" in l[0]),
            "per_km2_walkable": len(locs) / max(walk_km2, 1e-6),
            "max_gap_m": float(d_walk.max()) if d_walk.size else 0.0,
            "mean_gap_m": float(d_walk.mean()) if d_walk.size else 0.0,
            "p95_gap_m": float(np.percentile(d_walk, 95)) if d_walk.size else 0.0,
            "share_over_reach": float((d_walk > REACH_M).mean()) if d_walk.size else 0.0,
            "gaps": gaps,
            "road_km": road_len / 1000.0,
            "roads_over_reach": road_worst,
            "distance": dist,
        }

    # -- rivers and sightlines --

    def river_profiles(self) -> list:
        """For each river: the ground of the atlas's land (before the channel) along its path, and
        the worst rise above the lowest ground upstream of it. A river may cut through a little;
        it may not climb a range."""
        out = []
        for rv in self.doc.get("rivers", []):
            pts = resample(rv["path"], 20.0)
            hs = [self.height_at(x, z) for x, z in pts]
            low = hs[0]
            worst = (0.0, pts[0])
            for (x, z), h in zip(pts, hs):
                if h - low > worst[0]:
                    worst = (h - low, (x, z))
                low = min(low, h)
            out.append({"id": rv["id"], "source_m": hs[0], "mouth_m": hs[-1], "worst_rise_m": worst[0],
                        "worst_at": [worst[1][0], worst[1][1]], "length_m": path_length(rv["path"])})
        return out

    def sightline(self, a, b, target_kind: str) -> float:
        """How far the ground stands above the line from a to b at its worst (the same ray as
        PlaceDiscovery.can_see), in metres; negative is clear by that much."""
        ax, az = a
        bx, bz = b
        flat = math.hypot(bx - ax, bz - az)
        eye = self.height_at(ax, az) + EYE_M
        top = self.height_at(bx, bz) + LANDMARK_M.get(target_kind, LANDMARK_DEFAULT_M)
        worst = -math.inf
        steps = 64
        for s in range(1, steps):
            t = s / steps
            if t * flat < FOREGROUND_M or (1 - t) * flat < 30.0:
                continue
            x, z = ax + (bx - ax) * t, az + (bz - az) * t
            line = eye + (top - eye) * t
            worst = max(worst, self.height_at(x, z) - line)
        return worst if worst > -math.inf else -99.0

    def sightlines(self) -> list:
        where = {l[0]: (l[4], l[5]) for l in self.locations()}
        kinds = {l[0]: l[2] for l in self.locations()}
        out = []
        for d in self.pois:
            if d["id"] not in where:
                continue
            for v in d.get("visible_from", []):
                if v not in where:
                    out.append({"from": v, "to": d["id"], "over_m": math.nan, "length_m": math.nan, "missing": True})
                    continue
                a, b = where[v], where[d["id"]]
                L = math.hypot(b[0] - a[0], b[1] - a[1])
                over = self.sightline(a, b, kinds[d["id"]]) if L <= MAX_SIGHT_M else math.inf
                out.append({"from": v, "to": d["id"], "over_m": over, "length_m": L, "missing": False,
                            "hidden": kinds[d["id"]] == "hidden_valley"})
        return out
