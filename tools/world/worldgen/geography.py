"""The land as the atlas draws it (tools/world/atlas/SCHEMA.md).

Everything here is a function of the atlas; the seed only breaks up the lines between what the
atlas says. In order, as `heights.compose_heights` calls it:

* `province_field` -- each province's weight everywhere, from its polygon (blended across its
  `blend_m`, the border wandering by a few tens of metres of noise), and the owner of each texel;
* `land` -- every province's level and hills in its character, then the ranges and peaks rising
  out of that and the valleys cut into it;
* `coast` -- the sea outside the coast polygon, falling to the seabed; beaches, and cliffs;
* `Waters` / `lakes` -- every lake carved to its bed at its level, its shores, its islands, and
  the causeways laid across it;
* `rivers` -- the authored rivers, each with a water surface that falls all the way to the
  water it runs into, and the valleys they run in;
* `forests` -- how much of each kind of wood stands at each texel.
"""
from __future__ import annotations

import math
import zlib
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .noise import NoiseBank, ridged, terrace, upsample
from .regions import RegionDef, RegionField

SEA_LEVEL = 0.0
## how high the land stands at the water's edge where the coast is a beach
SHORE_M = 0.8
## the grade a river's valley sides rise at from its banks, until they meet the land
RIVER_VALLEY_GRADE = 0.22
## a river's valley, when the atlas does not say: this many times its width at that point
RIVER_VALLEY_WIDTHS = 12.0
## how far either side of a cliffs path the coast stands as a cliff
CLIFF_REACH_M = 60.0
ROAD_WIDTH_BY_KIND = {"highway": 6.0, "road": 5.0, "lane": 4.0, "track": 3.5, "causeway": 6.0}
CAUSEWAY_HALF_M = 6.0
CAUSEWAY_DECK_M = 1.8


def _salt(*parts) -> int:
    """A salt for the noise bank that depends on what a thing is, never on where it is listed."""
    return 2000 + zlib.crc32(repr(parts).encode("utf-8")) % 100000


# --- rasterising -----------------------------------------------------------------------------

def polygon_mask(grid: Grid, poly) -> np.ndarray:
    """bool [n, n]: the texels whose centres the polygon covers.

    A corner on the edge of the world is taken to lie past it, so a coast or a province drawn
    along the world's edge covers the texels at the edge rather than stopping half a texel short
    of them (which put a one-texel trench of sea round every edge the land ran off)."""
    n = grid.n
    img = Image.new("L", (n, n), 0)
    lo, hi = grid.x0, grid.x0 + grid.size_m
    past = 3.0 * grid.spacing

    def out(v: float) -> float:
        return lo - past if v <= lo + 1e-6 else (hi + past if v >= hi - 1e-6 else v)

    # texel (i, j) is centred on (x0 + j*s, z0 + i*s); PIL's pixel j covers [j, j + 1)
    pts = [((out(float(x)) - grid.x0) / grid.spacing + 0.5, (out(float(z)) - grid.z0) / grid.spacing + 0.5)
           for x, z in poly]
    ImageDraw.Draw(img).polygon(pts, fill=1)
    return np.asarray(img, dtype=np.uint8).astype(bool)


def signed_distance(grid: Grid, inside: np.ndarray) -> np.ndarray:
    """Metres to the edge of `inside`: negative inside, positive out, crossing zero on the edge.
    The edge of the array is not an edge: a province that runs off the map has no border there."""
    if inside.all():
        return np.full(inside.shape, -1e6, dtype=np.float32)
    if not inside.any():
        return np.full(inside.shape, 1e6, dtype=np.float32)
    d_out = ndimage.distance_transform_edt(~inside)
    d_in = ndimage.distance_transform_edt(inside)
    return (np.where(inside, -(d_in - 0.5), d_out - 0.5) * grid.spacing).astype(np.float32)


def coarse_distance(grid: Grid, mask: np.ndarray, work_n: int = 1024) -> np.ndarray:
    """float32 [n, n]: metres from each texel to the nearest texel of `mask`, measured on a
    `work_n` lattice and interpolated back. Good to a lattice step (8 m at 1024), and a fraction
    of the memory of a full-resolution distance transform, for the rules that read hundreds of
    metres (the strand, the tide-flats)."""
    n = grid.n
    if not mask.any():
        return np.full((n, n), 1e6, dtype=np.float32)
    f = max(n // work_n, 1)
    small = mask[::f, ::f] if f > 1 else mask
    d = (ndimage.distance_transform_edt(~small) * grid.spacing * f).astype(np.float32)
    return upsample(d, n, order=1) if f > 1 else d


def resample_path(pts, step: float) -> np.ndarray:
    p = np.asarray(pts, dtype=np.float64)[:, :2]
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] <= 0:
        return p[:1].copy()
    t = np.linspace(0.0, s[-1], max(int(math.ceil(s[-1] / step)) + 1, 2))
    return np.stack([np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])], axis=1)


@dataclass
class LineField:
    """The nearest point of a polyline to each texel in a window: distance, arc position (0..1
    along the line), the tangent there, and which side the texel is on."""
    window: tuple          # (i0, i1, j0, j1) of the grid the arrays cover
    d: np.ndarray          # metres
    t: np.ndarray          # 0 at the first point, 1 at the last
    tx: np.ndarray         # unit tangent, x
    tz: np.ndarray         # unit tangent, z
    left: np.ndarray       # bool: on the left walking from the first point to the last


def line_field(grid: Grid, pts, reach_m: float) -> LineField:
    """Distance from every texel within `reach_m` of the polyline `pts` ([[x, z], ...])."""
    p = np.asarray(pts, dtype=np.float64)[:, :2]
    dense = resample_path(p, grid.spacing * 0.5)
    seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t_all = s / max(s[-1], 1e-9)
    tan = np.gradient(dense, axis=0)
    tan /= np.maximum(np.linalg.norm(tan, axis=1, keepdims=True), 1e-9)
    n = grid.n
    pad = reach_m + 2.0 * grid.spacing
    j0 = max(int((dense[:, 0].min() - pad - grid.x0) / grid.spacing), 0)
    j1 = min(int((dense[:, 0].max() + pad - grid.x0) / grid.spacing) + 2, n)
    i0 = max(int((dense[:, 1].min() - pad - grid.z0) / grid.spacing), 0)
    i1 = min(int((dense[:, 1].max() + pad - grid.z0) / grid.spacing) + 2, n)
    m, k = i1 - i0, j1 - j0
    jj = np.clip(np.rint((dense[:, 0] - grid.x0) / grid.spacing).astype(np.int64) - j0, 0, k - 1)
    ii = np.clip(np.rint((dense[:, 1] - grid.z0) / grid.spacing).astype(np.int64) - i0, 0, m - 1)
    owner = np.full((m, k), -1, dtype=np.int64)
    owner[ii, jj] = np.arange(dense.shape[0])
    mask = owner >= 0
    _dist, (ni, nj) = ndimage.distance_transform_edt(~mask, return_indices=True)
    idx = owner[ni, nj]
    X = (grid.x0 + (np.arange(j0, j1) * grid.spacing))[None, :]
    Z = (grid.z0 + (np.arange(i0, i1) * grid.spacing))[:, None]
    qx, qz = dense[idx, 0], dense[idx, 1]
    vx, vz = X - qx, Z - qz
    d = np.sqrt(vx * vx + vz * vz).astype(np.float32)
    tx, tz = tan[idx, 0], tan[idx, 1]
    # with north up (-z), walking along (tx, tz), the left hand points along (tz, -tx)
    left = (vx * tz - vz * tx) > 0.0
    return LineField((i0, i1, j0, j1), d, t_all[idx].astype(np.float32), tx.astype(np.float32),
                     tz.astype(np.float32), left)


# --- provinces -------------------------------------------------------------------------------

## the old `map.shape` of each region is the biome its flora, rocks and art were made for
def provinces_from_atlas(atlas: dict, content_regions: list) -> list:
    """One RegionDef per province: the content region's identity (palette, light, danger,
    creatures), the biome's flora and art, and the province's own relief."""
    by_id = {r.id: r for r in content_regions}
    home = {r.shape: r for r in content_regions}
    out = []
    for k, p in enumerate(atlas["provinces"]):
        region = by_id[p["region"]]
        biome_home = home.get(p["biome"], region)
        poly = p["polygon"]
        cx = sum(q[0] for q in poly) / len(poly)
        cz = sum(q[1] for q in poly) / len(poly)
        area = 0.5 * abs(sum(poly[m][0] * poly[(m + 1) % len(poly)][1] - poly[(m + 1) % len(poly)][0] * poly[m][1]
                             for m in range(len(poly))))
        out.append(RegionDef(
            id=region.id, name=p.get("name", p["id"]), index=k, center=(cx, cz),
            radius=math.sqrt(max(area, 1.0) / math.pi),
            base_height=float(p["base_height_m"]), relief=float(p["relief_m"]),
            roughness=float(p.get("roughness", 0.3)), shape=str(p["biome"]),
            water_table=region.water_table, lake_radius=0.0,
            palette=list(region.palette), flora=list(biome_home.flora), light=dict(region.light),
            danger=region.danger, ecology=list(region.ecology),
            province=str(p["id"]), region_index=content_regions.index(region),
            character=str(p["character"]), landforms=list(p.get("landform", [])),
            grain_deg=(float(p["grain_deg"]) if "grain_deg" in p else None),
            blend_m=float(p.get("blend_m", 300.0)), art=biome_home.short))
    return out


def province_field(grid: Grid, bank: NoiseBank, atlas: dict, provinces: list) -> RegionField:
    """Each province's weight at every texel and the owner of each.

    A texel belongs to the province it is deepest inside; where provinces overlap that is the
    deeper one, and in a gap the nearest. Weights fall across a border over the province's
    `blend_m`: w ~ exp(-signed distance / (blend / 8)), so at the middle of a blend the two are
    even and at its edges one has fifty times the other. The border itself wanders by forty or
    fifty metres of noise, so a border drawn as a straight line does not read as one.
    """
    n = grid.n
    wx = (40.0 * bank.field_at(203, n, 1.8, 150, 450) + 18.0 * bank.field_at(205, n, 1.8, 50, 140)) / grid.spacing
    wz = (40.0 * bank.field_at(204, n, 1.8, 150, 450) + 18.0 * bank.field_at(206, n, 1.8, 50, 140)) / grid.spacing
    ii, jj = np.meshgrid(np.arange(n, dtype=np.float32), np.arange(n, dtype=np.float32), indexing="ij")
    coords = [ii + wz, jj + wx]
    del ii, jj, wx, wz
    P = len(provinces)
    scores = np.empty((P, n, n), dtype=np.float32)
    for k, (p, r) in enumerate(zip(atlas["provinces"], provinces)):
        sd = signed_distance(grid, polygon_mask(grid, p["polygon"]))
        sd = ndimage.map_coordinates(sd, coords, order=1, mode="nearest").astype(np.float32)
        scores[k] = sd / (r.blend_m / 8.0)
    del coords
    owner = np.argmin(scores, axis=0).astype(np.uint8)
    smin = scores.min(axis=0)
    weights = scores
    np.subtract(weights, smin[None], out=weights)
    np.negative(weights, out=weights)
    np.exp(weights, out=weights)
    weights /= weights.sum(axis=0)[None]
    return RegionField(grid=grid, weights=weights, owner=owner, scores=None)


# --- the hills in each province ---------------------------------------------------------------

def _sc(v, k: float = 2.0):
    return (k * np.tanh(v / k)).astype(np.float32)


def _normalised(v: np.ndarray) -> np.ndarray:
    """Rescaled so its 2nd and 98th percentiles are 0 and 1: `base_height_m` is then the low
    ground and `relief_m` how far the hills rise over it."""
    lo, hi = np.percentile(v[::4, ::4], [2.0, 98.0])
    return ((v - lo) / max(hi - lo, 1e-6)).astype(np.float32)


def character_field(ctx, character: str, grain_deg, roughness: float) -> np.ndarray:
    """A province character as a field of about 0..1 over its low ground (see SCHEMA.md,
    characters): 0 is the province's `base_height_m`, 1 that plus its `relief_m`."""
    salt = _salt("character", character, grain_deg, round(roughness, 2))
    aniso = None if grain_deg is None else (float(grain_deg) - 90.0, 2.5)

    def f(k, beta, lo, hi, an=None):
        return ctx.f(salt + k, beta, lo, hi, an)

    rough = float(roughness)
    if character == "flat":
        v = 0.7 * f(1, 2.0, None, 1600, aniso) + 0.3 * f(2, 2.0, 150, 500)
        return 0.1 * _normalised(v)
    if character == "marsh":
        mix = 0.5 * f(1, 2.0, None, 600) + 0.5 * f(2, 2.1, None, 1800)
        c1 = ctx.warped(salt + 3, 240, 700, 120.0, beta=1.7, aniso=(0.0 if grain_deg is None else grain_deg - 90.0, 1.6))
        c2 = ctx.warped(salt + 4, 400, 1100, 160.0, beta=1.7, aniso=(0.0 if grain_deg is None else grain_deg - 90.0, 1.2))
        chan = np.exp(-(c1 / 0.22) ** 2) + 0.8 * np.exp(-(c2 / 0.16) ** 2)
        islands = np.clip(f(5, 1.9, None, 260) - 0.6, 0.0, 1.2) ** 1.2
        return _normalised(0.8 * np.tanh(0.8 * mix) + 2.2 * islands - 2.2 * chan)
    if character == "rolling":
        v = ctx.warped(salt + 1, None, 2200, 90.0, beta=2.1, aniso=aniso)
        dome = (0.5 + 0.5 * np.tanh(v / 1.1)) ** 0.8
        return _normalised(dome + 0.18 * _sc(f(2, 2.0, None, 800), 1.5) + 0.12 * rough * _sc(f(3, 2.0, 120, 420), 1.5))
    if character == "hills":
        mix = 0.62 * f(1, 2.2, None, 2400, aniso) + 0.26 * f(2, 2.0, None, 800, aniso) \
            + 0.12 * (0.5 + rough) * f(3, 2.0, 120, 460)
        v = _sc(mix / 0.71)
        return _normalised(np.where(v > 0, 0.6 * v, 0.25 * v))
    if character == "ridged":
        crest = ridged(f(1, 2.1, None, 1600, aniso if aniso else None), 1.6)
        return _normalised(crest + 0.25 * f(2, 2.0, None, 900) + 0.15 * rough * f(3, 2.0, 80, 300))
    if character == "plateau":
        mix = 0.7 * f(1, 2.2, None, 1900, aniso) + 0.3 * f(2, 2.0, None, 700)
        v = np.tanh(1.3 * mix) + 0.2 * _sc(f(3, 2.0, 140, 520), 1.5) + 0.1 * rough * _sc(f(4, 1.8, 40, 220))
        v = _normalised(v)
        # a level top, stepped where it breaks
        return (0.55 * terrace(v, 0.18, 0.3) + 0.45 * v).astype(np.float32)
    if character == "mountains":
        bulk = 0.5 + 0.5 * np.tanh(f(1, 2.3, None, 3200) / 1.1)
        crest = ridged(f(2, 2.2, None, 1800, aniso if aniso else (15.0, 1.6)), 1.8)
        crags = ridged(f(3, 2.0, 60, 400), 1.1)
        l2 = _sc(f(4, 2.1, None, 1800))
        v = 0.75 * bulk + 0.28 * crest * (0.25 + 0.75 * bulk) + (0.02 + 0.03 * rough) * crags * (0.3 + 0.7 * crest) + 0.05 * l2
        return _normalised(v)
    raise ValueError("no such character: %s" % character)


# --- ranges, peaks and valleys ------------------------------------------------------------------

def _range_profile(profile: str, t: np.ndarray) -> np.ndarray:
    """0..1 of the way up from the foot to the crest, at `t` = distance / half width."""
    t = np.clip(t, 0.0, 1.0)
    if profile == "rounded":
        return (1.0 - t * t) ** 1.3
    if profile == "massif":
        return 1.0 - smoothstep(0.5, 1.0, t)
    # a ridge: sharp at the crest, spreading at the foot
    return (1.0 - t) ** 1.6 * (1.0 + 0.6 * t)


def apply_ranges(ctx, h: np.ndarray, atlas: dict) -> tuple:
    """Every range at its crest heights, blended into the land over its width. Returns (heights,
    rock mask): the rock mask is how much of each texel is a range's own flank, for the texture
    rules.

    Each range is laid against the provinces' ground, not against the ranges before it. Where it
    stands over that ground it raises it, and where two ranges meet the higher wins; where its
    crest is drawn under the ground (a pass through high country) it lowers it, but only near
    its own crest and never ground another range has raised, so a pass is a notch in its own
    range and not a trench across another's."""
    g = ctx.grid
    rock = np.zeros_like(h, dtype=np.float32)
    ground = h.copy()
    raised = h.copy()
    lowered = np.full_like(h, np.inf)
    for rg in atlas.get("ranges", []):
        width = float(rg["width_m"])
        half = 0.5 * width
        profile = rg.get("profile", "ridge")
        lf = line_field(g, [[p[0], p[1]] for p in rg["ridge"]], half * 1.15)
        i0, i1, j0, j1 = lf.window
        sub = ground[i0:i1, j0:j1]
        crest_pts = np.array([p[2] for p in rg["ridge"]], dtype=np.float64)
        # the crest height at each texel's nearest ridge point, by the fraction along the ridge
        arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(np.asarray(rg["ridge"], dtype=np.float64)[:, :2], axis=0), axis=1))])
        crest = np.interp(lf.t * arc[-1], arc, crest_pts).astype(np.float32)
        salt = _salt("range", rg["id"])
        # the crest is broken, and the flanks put out spurs and draw back into gullies
        rough = {"massif": 0.12, "rounded": 0.04}.get(profile, 0.07)
        nz = ctx.f(salt, 2.0, 250, 1200)[i0:i1, j0:j1]
        spur = ctx.f(salt + 1, 1.9, 120, 500)[i0:i1, j0:j1]
        base = sub
        crest_n = crest + rough * np.maximum(np.abs(crest - base), 0.1 * crest) * _sc(nz, 1.5)
        d = lf.d * (1.0 + 0.22 * _sc(spur, 1.5))
        if profile == "scarp":
            face_left = rg.get("face", "left") == "left"
            on_face = lf.left if face_left else ~lf.left
            t = np.where(on_face, d / (width / 6.0), d / (width * 5.0 / 6.0))
            up = np.where(on_face, 1.0 - smoothstep(0.0, 1.0, np.clip(t, 0.0, 1.0)),
                          np.clip(1.0 - t, 0.0, 1.0) ** 0.9)
        else:
            up = _range_profile(profile, d / half)
        # past either end of the ridge the range rounds off rather than stopping at a wall
        up = up * np.where((lf.t > 0.0) & (lf.t < 1.0), 1.0, np.clip(1.0 - lf.d / half, 0.0, 1.0))
        # at its crest a range is the height drawn for it, whatever the provinces put there: it
        # rises out of low ground, and a pass drawn low in it is low
        target = base + (crest_n - base) * up
        raised[i0:i1, j0:j1] = np.maximum(raised[i0:i1, j0:j1], target)
        near_crest = up * (1.0 - smoothstep(0.35, 0.7, 1.0 - up))
        low = np.where(crest_n < base, base + (target - base) * near_crest, np.inf)
        lowered[i0:i1, j0:j1] = np.minimum(lowered[i0:i1, j0:j1], low)
        rock[i0:i1, j0:j1] = np.maximum(rock[i0:i1, j0:j1], smoothstep(0.15, 0.5, up))
    # a pass lowers only ground no other range has raised
    out = np.where(raised > ground + 0.5, raised, np.minimum(raised, lowered))
    return out.astype(np.float32), rock


def _peak_profile(shape: str, t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    if shape == "dome":
        return (1.0 - t * t) ** 1.4
    if shape == "mesa":
        return 1.0 - smoothstep(0.55, 0.8, t)
    return (1.0 - t) ** 1.4 * (1.0 + 0.4 * t)


def apply_peaks(ctx, h: np.ndarray, atlas: dict) -> np.ndarray:
    g = ctx.grid
    for pk in atlas.get("peaks", []):
        x, z = float(pk["at"][0]), float(pk["at"][1])
        radius = float(pk["radius_m"])
        top = float(pk["height_m"])
        shape = pk.get("shape", "cone")
        k = int(radius * 1.2 / g.spacing) + 2
        j = int(round((x - g.x0) / g.spacing))
        i = int(round((z - g.z0) / g.spacing))
        i0, i1 = max(0, i - k), min(g.n, i + k + 1)
        j0, j1 = max(0, j - k), min(g.n, j + k + 1)
        if i0 >= i1 or j0 >= j1:
            continue
        salt = _salt("peak", pk.get("id", ""), x, z)
        spur = ctx.f(salt, 1.9, 60, 400)[i0:i1, j0:j1]
        dx = ctx.X[:, j0:j1] - x
        dz = ctx.Z[i0:i1, :] - z
        d = np.sqrt(dx * dx + dz * dz) * (1.0 + 0.2 * _sc(spur, 1.5))
        up = _peak_profile(shape, d / radius)
        base = h[i0:i1, j0:j1]
        crown = top
        if shape == "crag":
            crown = top - 0.08 * (top - base) * (1.0 - ridged(ctx.f(salt + 1, 1.8, 30, 160)[i0:i1, j0:j1], 1.2))
        h[i0:i1, j0:j1] = base + np.maximum(crown - base, 0.0) * up
    return h


def _valley_profile(profile: str, t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    if profile == "v":
        return 1.0 - t
    if profile == "gorge":
        return 1.0 - smoothstep(0.6, 0.85, t)
    return 1.0 - smoothstep(0.3, 1.0, t)


def apply_valleys(ctx, h: np.ndarray, atlas: dict) -> np.ndarray:
    g = ctx.grid
    for v in atlas.get("valleys", []):
        half = 0.5 * float(v["width_m"])
        lf = line_field(g, v["path"], half * 1.1)
        i0, i1, j0, j1 = lf.window
        cut = float(v["depth_m"]) * _valley_profile(v.get("profile", "u"), lf.d / half)
        # the valley heads and mouths fade rather than ending at a wall
        cut *= np.where((lf.t > 0.0) & (lf.t < 1.0), 1.0, np.clip(1.0 - lf.d / half, 0.0, 1.0))
        h[i0:i1, j0:j1] -= cut.astype(np.float32)
    return h


def land(ctx, atlas: dict) -> tuple:
    """Every province's ground and hills, blended; then the ranges, peaks and valleys.
    Returns (heights, range rock mask)."""
    rf = ctx.rf
    h = np.zeros((ctx.grid.n, ctx.grid.n), dtype=np.float32)
    fields: dict = {}
    for r in ctx.regions:
        key = (r.character, r.grain_deg, round(r.roughness, 2))
        if key not in fields:
            fields[key] = character_field(ctx, r.character, r.grain_deg, r.roughness)
        h += rf.weights[r.index] * (r.base_height + r.relief * fields[key])
    del fields
    h, rock = apply_ranges(ctx, h, atlas)
    h = apply_peaks(ctx, h, atlas)
    h = apply_valleys(ctx, h, atlas)
    return h, rock


# --- the coast ---------------------------------------------------------------------------------

def land_mask(grid: Grid, atlas: dict) -> np.ndarray:
    coast = atlas["coast"]
    m = polygon_mask(grid, coast["polygon"])
    for isl in coast.get("islands", []):
        m |= polygon_mask(grid, isl)
    return m


def apply_coast(ctx, h: np.ndarray, atlas: dict) -> tuple:
    """The sea outside the coast, falling to the seabed; the land brought down to the shore over
    `beach_m`, or held at a cliff's height along a `cliffs` path. Returns (heights, sea mask)."""
    g = ctx.grid
    coast = atlas["coast"]
    on_land = land_mask(g, atlas)
    if on_land.all():
        return h, np.zeros_like(on_land)
    sd = signed_distance(g, on_land)                 # negative on land
    seabed = float(coast.get("seabed_m", -26.0))
    shelf = float(coast.get("shelf_m", 300.0))
    beach = float(coast.get("beach_m", 60.0))
    out_d = np.maximum(sd, 0.0)
    in_d = np.maximum(-sd, 0.0)
    ripple = 1.2 * ridged(ctx.f(_salt("seabed"), 2.0, None, 700), 1.3)
    sea_h = SEA_LEVEL - 0.6 - (SEA_LEVEL - 0.6 - seabed) * smoothstep(0.0, shelf, out_d) ** 0.7 + ripple * smoothstep(0.0, shelf, out_d)
    beach_h = lerp(np.float32(SHORE_M), h, smoothstep(0.0, max(beach, 1.0), in_d)) if beach > 0 else h
    land_h = beach_h
    cliff_w = np.zeros_like(h, dtype=np.float32)
    cliff_h = np.zeros_like(h, dtype=np.float32)
    for cl in coast.get("cliffs", []):
        lf = line_field(g, cl["path"], CLIFF_REACH_M * 2.0)
        i0, i1, j0, j1 = lf.window
        w = 1.0 - smoothstep(CLIFF_REACH_M * 0.6, CLIFF_REACH_M * 1.6, lf.d)
        cliff_w[i0:i1, j0:j1] = np.maximum(cliff_w[i0:i1, j0:j1], w)
        cliff_h[i0:i1, j0:j1] = np.maximum(cliff_h[i0:i1, j0:j1], float(cl["height_m"]) * w)
    if cliff_w.any():
        # a cliff stands to the water, so no beach comes down to it, and the land at its top is
        # at least the cliff's height; below it the sea is deep at once
        top = np.maximum(h, cliff_h + 2.0 * _sc(ctx.f(_salt("cliff"), 1.8, 20, 120), 1.5))
        land_h = lerp(beach_h, top, cliff_w)
        foot = np.maximum(SEA_LEVEL - 4.0 - 0.5 * np.minimum(out_d, 40.0), seabed)
        sea_h = lerp(sea_h, np.minimum(sea_h, foot), cliff_w)
    out = np.where(on_land, land_h, sea_h).astype(np.float32)
    return out, ~on_land


# --- lakes ---------------------------------------------------------------------------------

@dataclass
class Waters:
    """The standing water the atlas draws: the sea and every lake, at the composition grid or at
    full resolution. `sd` is metres to the nearest lake shore (negative on the water, positive on
    land and on islands); `level` the surface of the nearest lake; `lake_id` which lake (-1 none);
    `island_sd` metres to the nearest lake island (negative on it); `cliffness`/`reediness` how
    much a shore is the lake's cliff shore or its reed shelf; `causeway` the decks across it."""
    sd: np.ndarray
    level: np.ndarray
    lake_id: np.ndarray
    island_sd: np.ndarray
    cliffness: np.ndarray
    reediness: np.ndarray
    causeway: np.ndarray
    sea: np.ndarray
    lakes: list = field(default_factory=list)

    # the names the texture rules and the landforms were written against
    @property
    def northness(self) -> np.ndarray:
        return self.cliffness

    @property
    def westness(self) -> np.ndarray:
        return self.reediness

    def in_lake(self, H: np.ndarray) -> np.ndarray:
        """Lake water: inside a lake's shore and under its surface, not on an island."""
        return (self.sd < 0.0) & (H < self.level) & (self.island_sd > 0.0)


def _bearing_weight(dx: np.ndarray, dz: np.ndarray, bearing_deg, width_deg: float = 55.0) -> np.ndarray:
    """1 on the stretch of shore facing `bearing_deg` from the middle of the lake, 0 away from it."""
    if bearing_deg is None:
        return np.zeros(dx.shape, dtype=np.float32)
    b = math.radians(float(bearing_deg))
    ux, uz = math.sin(b), -math.cos(b)
    d = np.maximum(np.sqrt(dx * dx + dz * dz), 1.0)
    c = (dx * ux + dz * uz) / d
    return smoothstep(math.cos(math.radians(width_deg * 1.6)), math.cos(math.radians(width_deg * 0.6)), c).astype(np.float32)


def waters(grid: Grid, atlas: dict, things: dict, sea: np.ndarray | None = None) -> Waters:
    """The lakes' geometry on `grid` (the heights come later: `apply_lakes`). `things` is every
    place and POI by id, for the ends of the causeways."""
    n = grid.n
    X, Z = grid.mesh()
    sd = np.full((n, n), 1e6, dtype=np.float32)
    level = np.full((n, n), SEA_LEVEL, dtype=np.float32)
    lake_id = np.full((n, n), -1, dtype=np.int16)
    island_sd = np.full((n, n), 1e6, dtype=np.float32)
    cliff = np.zeros((n, n), dtype=np.float32)
    reed = np.zeros((n, n), dtype=np.float32)
    for k, lake in enumerate(atlas.get("lakes", [])):
        water = polygon_mask(grid, lake["polygon"])
        isl = np.zeros_like(water)
        for s in lake.get("islands", []):
            isl |= polygon_mask(grid, s["polygon"])
        sd_k = signed_distance(grid, water)
        if isl.any():
            island_sd = np.minimum(island_sd, signed_distance(grid, isl))
        # the nearest lake owns each texel: its level, its shore styles
        mine = sd_k < sd
        sd = np.where(mine, sd_k, sd)
        level = np.where(mine, np.float32(lake["level_m"]), level)
        lake_id = np.where(mine, np.int16(k), lake_id)
        poly = lake["polygon"]
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        cliff = np.where(mine, _bearing_weight(X - cx, Z - cz, lake.get("cliff_shore_deg")), cliff)
        reed = np.where(mine, _bearing_weight(X - cx, Z - cz, lake.get("reed_shore_deg")), reed)
    # an island is land: shift the lake's distance so it is positive on the island
    sd = np.where(island_sd < 0.0, np.maximum(sd, -island_sd), sd).astype(np.float32)
    causeway = causeway_mask(grid, atlas, things, sd)
    return Waters(sd=sd, level=level, lake_id=lake_id, island_sd=island_sd, cliffness=cliff,
                  reediness=reed, causeway=causeway,
                  sea=(sea if sea is not None else np.zeros((n, n), dtype=bool)),
                  lakes=list(atlas.get("lakes", [])))


def causeway_legs(atlas: dict, things: dict) -> list:
    """[(road, p, q)] every leg of a causeway road (between consecutive waypoints)."""
    out = []
    for road in atlas.get("roads", []):
        if road.get("kind") != "causeway":
            continue
        a, b = things.get(road["from"]), things.get(road["to"])
        if a is None or b is None:
            continue
        pts = [list(a["position"][:2])] + [list(v) for v in road.get("via", [])] + [list(b["position"][:2])]
        for p, q in zip(pts[:-1], pts[1:]):
            out.append((road, p, q))
    return out


def causeway_mask(grid: Grid, atlas: dict, things: dict, lake_sd: np.ndarray) -> np.ndarray:
    """0..1: the decks of the causeway legs that cross a lake (soft edges)."""
    out = np.zeros((grid.n, grid.n), dtype=np.float32)
    for _road, p, q in causeway_legs(atlas, things):
        lf = line_field(grid, [p, q], CAUSEWAY_HALF_M + 20.0)
        i0, i1, j0, j1 = lf.window
        deck = 1.0 - smoothstep(CAUSEWAY_HALF_M, CAUSEWAY_HALF_M + 9.0, lf.d)
        wet = lake_sd[i0:i1, j0:j1] < 40.0
        out[i0:i1, j0:j1] = np.maximum(out[i0:i1, j0:j1], deck * wet)
    return out


def apply_lakes(ctx, h: np.ndarray, wt: Waters) -> np.ndarray:
    """Carve each lake to its bed, shape its shores, raise its islands and lay its causeways."""
    if not wt.lakes:
        return h
    sd, level = wt.sd, wt.level
    inside = 1.0 - smoothstep(-40.0, 0.0, sd)
    r_eff = np.ones_like(sd)
    for k, lake in enumerate(wt.lakes):
        poly = lake["polygon"]
        area = 0.5 * abs(sum(poly[m][0] * poly[(m + 1) % len(poly)][1] - poly[(m + 1) % len(poly)][0] * poly[m][1]
                             for m in range(len(poly))))
        r_eff = np.where(wt.lake_id == k, math.sqrt(area / math.pi), r_eff)
    depth = np.zeros_like(sd)
    for k, lake in enumerate(wt.lakes):
        depth = np.where(wt.lake_id == k, float(lake.get("depth_m", 10.0)), depth)
    depth_t = np.clip(-sd / (r_eff * 0.75), 0.0, 1.0)
    bed = level - depth * smoothstep(0.0, 1.0, depth_t) ** 0.8 - 0.6 * ctx.f(171, 1.9, None, 260)
    # the water is water: out from the shore the bed stays under it (islands are drawn)
    bed = np.minimum(bed, level - 0.3 - 0.9 * smoothstep(40.0, 200.0, -sd))
    # a reed shore runs out in a shallow shelf
    shelf = level - 1.3
    bed = lerp(bed, np.maximum(bed, shelf), wt.reediness * (1.0 - smoothstep(60.0, 220.0, -sd)))
    # on land: shingle rising four metres over sixty, then the land; kept a metre and a half over
    # the water for a few hundred metres, so no dry hollow sits below the lake beside it
    shore = level + 4.0 * smoothstep(0.0, 60.0, sd)
    ground = lerp(shore, h, smoothstep(50.0, 320.0, sd))
    near = 1.0 - smoothstep(250.0, 700.0, sd)
    ground = lerp(ground, np.maximum(ground, level + 1.5), near)
    # a cliff shore stands seven to ten metres at the water
    cliff = (7.0 + 3.0 * ctx.f(172, 1.9, None, 260)) * smoothstep(0.0, 10.0, sd)
    ground = ground + cliff * wt.cliffness * (1.0 - smoothstep(40.0, 260.0, sd))
    influence = 1.0 - smoothstep(700.0, 900.0, sd)
    h2 = lerp(h, lerp(ground, np.minimum(bed, ground), inside), influence)
    # islands: stone stacks stepping up to a broken crown
    for k, lake in enumerate(wt.lakes):
        for s in lake.get("islands", []):
            isl_sd = signed_distance(ctx.grid, polygon_mask(ctx.grid, s["polygon"]))
            poly = s["polygon"]
            area = 0.5 * abs(sum(poly[m][0] * poly[(m + 1) % len(poly)][1] - poly[(m + 1) % len(poly)][0] * poly[m][1]
                                 for m in range(len(poly))))
            r_isl = math.sqrt(max(area, 1.0) / math.pi)
            lv = float(lake["level_m"])
            rise = float(s["height_m"]) - lv
            on = 1.0 - smoothstep(-30.0, 25.0, isl_sd)
            ih = lv + 0.55 * rise * smoothstep(0.0, 0.4, np.clip(-isl_sd / r_isl, 0.0, 1.0)) ** 0.7
            inner = smoothstep(-6.0, -55.0, isl_sd)
            ledges = terrace(np.clip(0.45 * rise * np.clip(0.5 + 0.5 * ctx.f(174, 1.7, 40.0, 200.0), 0.0, 1.0), 0.0, None), 2.2, 0.45)
            fracture = 1.2 * np.abs(ctx.f(175, 1.5, 9.0, 48.0))
            ih = ih + (ledges + fracture) * inner
            h2 = np.maximum(h2, lerp(h2, ih, on))
    return h2.astype(np.float32)


def apply_causeways(ctx, h: np.ndarray, wt: Waters, atlas: dict, things: dict) -> np.ndarray:
    """Raise every causeway leg that crosses a lake on a bank: a straight deck a metre and eighty
    over the water, with sides falling one in 1.4 into it."""
    g = ctx.grid
    for _road, p, q in causeway_legs(atlas, things):
        lf = line_field(g, [p, q], CAUSEWAY_HALF_M + 40.0)
        i0, i1, j0, j1 = lf.window
        lv = wt.level[i0:i1, j0:j1]
        on_span = (wt.sd[i0:i1, j0:j1] < 20.0) & (lf.t > 0.0) & (lf.t < 1.0)
        deck = lv + CAUSEWAY_DECK_M
        sides = deck - 1.4 * np.clip(lf.d - CAUSEWAY_HALF_M, 0.0, None)
        sub = h[i0:i1, j0:j1]
        h[i0:i1, j0:j1] = np.where(on_span, np.maximum(sub, sides), sub)
    return h


# --- sightlines ----------------------------------------------------------------------------------

## How far the builder will cut the land to honour an authored sightline, at the deepest point of
## the cut. A line with a shoulder of hill in the way is given a saddle; a line with a mountain
## in the way is left refused, because a two-hundred-metre trench is not a view, and that line
## is the atlas's or the content's to answer (move the place, draw a pass, or change the claim).
NOTCH_MAX_M = 25.0
## what the cut leaves under the line on top of the game's own clearance, for the carving,
## pads and detail that come after it and for the runtime's coarser copy of the heights
NOTCH_SPARE_M = 1.0
## the floor of the cut either side of the line, and the grade its sides climb back to the land
NOTCH_FLOOR_M = 6.0
NOTCH_SIDE_GRADE = 0.6


def honour_sightlines(grid: Grid, H: np.ndarray, lines: list, k: dict) -> list:
    """Cut a saddle wherever the land stands into an authored sightline, up to NOTCH_MAX_M.

    `lines` is [(vantage_xz, target_xz, target_kind, pad_radius_vantage, pad_radius_target)]
    and `k` the game's own sight constants (tools/sightlines.py `constants`, read out of
    place_discovery.gd). The ray is the one `PlaceDiscovery.can_see` marches: from an eye EYE_M
    over the vantage to a point LANDMARK_M over the target, the first FOREGROUND_M ignored, and
    the land must stay CLEARANCE_M under it. Lines into a hidden valley are the way in, not the
    place, and are left alone. Returns [(vantage_xz, target_xz, worst_m, cut)] for every line
    the land stood into: `cut` False where it stood in by more than NOTCH_MAX_M and was left.
    """
    from .grid import sample_bilinear

    out = []
    for a, b, kind, ra, rb in lines:
        if kind == "hidden_valley":
            continue
        flat = math.hypot(b[0] - a[0], b[1] - a[1])
        if flat <= 1.0 or flat > k["MAX_SIGHT_M"]:
            continue
        ya = float(sample_bilinear(H, grid, np.array([a[0]]), np.array([a[1]]))[0])
        yb = float(sample_bilinear(H, grid, np.array([b[0]]), np.array([b[1]]))[0])
        eye = ya + k["EYE_M"]
        top = yb + k["LANDMARK_M"].get(kind, k["LANDMARK_DEFAULT_M"])
        skip = min(k["FOREGROUND_M"] / flat, 0.4)
        # what the land must stay under, along the line (the pads at either end are their own)
        t0 = max(skip, (ra * 1.2) / flat)
        t1 = 1.0 - (rb * 1.2) / flat
        if t1 <= t0:
            continue
        ts = np.linspace(t0, t1, max(int((t1 - t0) * flat / grid.spacing), 2))
        xs = a[0] + (b[0] - a[0]) * ts
        zs = a[1] + (b[1] - a[1]) * ts
        ground = sample_bilinear(H, grid, xs, zs)
        ceiling = eye + (top - eye) * ts - k["CLEARANCE_M"] - NOTCH_SPARE_M
        worst = float((ground - ceiling).max())
        if worst <= 0.0:
            continue
        if worst > NOTCH_MAX_M:
            out.append((a, b, worst, False))
            continue
        reach = NOTCH_FLOOR_M + worst / NOTCH_SIDE_GRADE + 4.0 * grid.spacing
        lf = line_field(grid, [a, b], reach)
        i0, i1, j0, j1 = lf.window
        t = lf.t
        under = eye + (top - eye) * t - k["CLEARANCE_M"] - NOTCH_SPARE_M
        cut = under + NOTCH_SIDE_GRADE * np.maximum(lf.d - NOTCH_FLOOR_M, 0.0)
        # only between the pads, fading in and out over a few texels
        span = grid.spacing * 4.0 / flat
        along = smoothstep(t0 - span, t0, t) * (1.0 - smoothstep(t1, t1 + span, t))
        sub = H[i0:i1, j0:j1]
        H[i0:i1, j0:j1] = np.where(along > 0.0, lerp(sub, np.minimum(sub, cut), along), sub)
        out.append((a, b, worst, True))
    return out


# --- forests -----------------------------------------------------------------------------------

## how far in from a wood's edge its trees reach their full density
FOREST_EDGE_M = 40.0


def forests(grid: Grid, atlas: dict) -> dict:
    """{kind: float32 [n, n] 0..1}: how much of each kind of wood stands at each texel."""
    out: dict = {}
    for f in atlas.get("forests", []):
        m = polygon_mask(grid, f["polygon"])
        if not m.any():
            continue
        d_in = ndimage.distance_transform_edt(m) * grid.spacing
        w = (smoothstep(0.0, FOREST_EDGE_M, d_in) * float(f["density"])).astype(np.float32)
        k = f["kind"]
        out[k] = np.maximum(out[k], w) if k in out else w
    return out


# --- rivers --------------------------------------------------------------------------------------

def river_order(atlas: dict) -> list:
    """The rivers, each after the one it runs into, so a tributary knows its confluence level."""
    rivers = list(atlas.get("rivers", []))
    from .atlas import distance_to_path, lake_at, on_land, CONFLUENCE_M
    into: dict = {}
    for rv in rivers:
        mx, mz = rv["path"][-1]
        if not on_land(atlas, mx, mz) or lake_at(atlas, mx, mz) is not None:
            into[rv["id"]] = None
            continue
        best = None
        for other in rivers:
            if other["id"] == rv["id"]:
                continue
            d = distance_to_path(mx, mz, other["path"])
            if d <= CONFLUENCE_M and (best is None or d < best[0]):
                best = (d, other["id"])
        into[rv["id"]] = best[1] if best else None
    ordered: list = []
    placed: set = set()
    for _ in range(len(rivers) + 1):
        for rv in rivers:
            if rv["id"] in placed:
                continue
            target = into[rv["id"]]
            if target is None or target in placed:
                ordered.append(rv)
                placed.add(rv["id"])
    for rv in rivers:                      # a loop of tributaries: take them as written
        if rv["id"] not in placed:
            ordered.append(rv)
    return [(rv, into.get(rv["id"])) for rv in ordered]
