"""Pads and roads.

Pads: every named place gets a smoothly blended flat platform sized by its kind.
Roads: settlements are joined by least-cost routes that prefer gentle grades and dry ground
(water is expensive but not impossible, so roads cross rivers at their narrowest and use the
Long Stride causeway to reach Tollmere). Each route is graded (a smoothed, slope-limited
profile) and cut into the terrain 4-6 m wide with soft shoulders.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, smoothstep
from .noise import downsample
from . import paths

## How many buildings the settlement builder raises at a place of each kind. Kept in step with
## FABRIC in game/world/exteriors/settlement.gd: the flattened ground should be the size of the
## town that will stand on it, not a fixed disc per kind. A town of thirty-four houses on a
## ninety-metre pad is a cottage in a car park.
FABRIC_COUNT = {
    "city": 54, "town": 34, "village": 16, "hamlet": 8, "fort": 10, "lodge": 5,
    "ruin_village": 9, "camp": 0,
}
PAD_DEFAULT = 25.0
## A camp that is a point of interest builds no houses: it is a fire, tents on a ring 7.6 m out
## and their stores, and at the most a rail or a kiln 12 to 13 m from the fire (poi_builders.camp).
## Twenty-two metres keeps all of that on the level core (0.7 of the radius) with a couple of
## metres over. It was 30, the size a hamlet gets without the houses, and on the knoll the
## Clanless Camp stands on that pad threw a seventeen-metre embankment down the slope toward
## Brindlecrag -- whose rim was what the line from Brindlecrag grazed, 1.97 m over it against the
## 2 m allowed. A camp that is a *place* keeps its 30: Pilgrim's Ash is raised by the settlement
## builder, not the POI kit, and its chapter-house door stands 26 m from the middle.
CAMP_PAD_M = 22.0
## how far below an authored pad (the atlas's `pads`) the ground beyond its flat may lie before
## its skirt leaves it alone: that is a drop, a shelf's face, and not ground to be filled
PAD_DROP_M = 2.0
## A wayside find (a POI marked `"wayside": true`: a cairn, a shrine, a grave, a fold by the road)
## is a small thing on the dale side, and a PAD_DEFAULT pad on 25 to 45 degree ground is a quarry
## of cut and fill on the hillsides that are meant to read as wild. Its pad is this.
WAYSIDE_PAD_M = 14.0
CAMP_PLACE_PAD_M = 30.0
## A pad is level out to PAD_LEVEL of its radius (`pad_level_radius`), and its skirt blends it
## into the land over PAD_SKIRT radii past that. The radius is what the game is told as
## `radius_flat_m`, and much of the game is tuned to it (a point of interest's dressing, a
## place's arrival ring), so it stays what it was; the ground that is truly level is told as
## `radius_level_m`, which is where a settlement's houses may stand. A settlement is level to
## its whole radius, and a ring town to its own `flat_m` (RING_TOWNS); see `pad_level_radius`.
PAD_LEVEL = 0.7
PAD_SKIRT = 0.9
ROAD_KINDS = ("city", "town", "village", "hamlet", "fort", "camp", "lodge", "ruin_village")
ROAD_WIDTH = {"city": 6.0, "town": 6.0, "village": 5.0, "fort": 5.0, "hamlet": 4.5, "camp": 4.0,
              "lodge": 4.0, "ruin_village": 4.0}
## A town laid round something in its middle instead of along a street through it. Grandfather
## Hollow is a town round the foot of a dead tree ninety metres tall, whose trunk reaches 38.8 m
## from the centre: its street is a closed ring (`ring_m` to the centre line, `width_m` wide),
## every road that comes to the town ends on the ring's outer edge, and one short spur runs in
## from the ring to the door into the tree (`spur_bearing_deg`, measured from +z toward +x as
## the door plan measures it, in to `spur_to_m`, `spur_width_m` wide). Its pad is flat to
## `flat_m`, which leaves room for a ring of houses outside the street.
RING_TOWNS = {
    "core:place/grandfather_hollow": {"flat_m": 72.0, "ring_m": 48.0, "width_m": 6.0,
                                      "spur_bearing_deg": 304.0, "spur_to_m": 41.0,
                                      "spur_width_m": 4.0},
}


@dataclass
class Road:
    id: str
    points: np.ndarray
    width: float
    elevation: np.ndarray
    ## the land the profile was graded against, under each point (see `grade_profile`)
    ground: np.ndarray | None = None


def pad_radius(place: dict) -> float:
    """Enough flat ground for the houses that will stand here, and no more.

    Frontage rather than area is what a street plan needs: n houses at about eight metres of
    frontage, along two sides of one or two streets, is a street length of roughly 2n metres,
    so the radius grows with the square root of the count and not with the count itself.
    """
    if place.get("pad_radius_m"):
        return float(place["pad_radius_m"])          # the atlas's own (`pads`)
    if place.get("wayside"):
        return WAYSIDE_PAD_M
    kind = str(place.get("kind", ""))
    count = FABRIC_COUNT.get(kind)
    if count is None:
        return PAD_DEFAULT
    if count <= 0:
        return CAMP_PAD_M if ":poi/" in str(place.get("id", "")) else CAMP_PLACE_PAD_M
    return float(min(max(20.0 + 7.5 * math.sqrt(count), 26.0), 80.0))


def pad_level_radius(place: dict) -> float:
    """How far out a place's pad is truly level: `radius_level_m` in pois.json.

    A settlement (a place of a kind the fabric builds) is level to its whole radius: its houses
    go out to `radius - 8`, and level only to 0.7 of it they stood on the skirt, a house band
    level on 94% of it on average and 75% at Skarlow, Ghastfell and Fernhold. A point of
    interest keeps its level core of 0.7: nothing but its kit stands on it, and a wider level
    on a slope stood the Giants' Stair's terrace 2.4 m into the sightline up to it from Skarlow.
    """
    pid = str(place.get("id", ""))
    ring = RING_TOWNS.get(pid)
    if ring is not None:
        return float(ring["flat_m"])
    if ":place/" in pid and str(place.get("kind", "")) in FABRIC_COUNT:
        return pad_radius(place)
    return PAD_LEVEL * pad_radius(place)


## A point of interest's pad was a disc of dead-level ground out to 0.7 of its radius, which from
## the Stair Head's first view reads as a levelled test pad. It now keeps the land's lie: it tilts
## with the land round it (PAD_TILT_SHARE of the land's own slope, fitted over the ring just past its
## skirt, and never more than PAD_TILT_MAX, walkable everywhere) and rolls by up to PAD_ROLL_M over
## PAD_ROLL_WL_M (so a 4 m footprint anywhere on it is within a quarter metre of level), both nothing at its middle, which stays at the pad's level (the POI's height), and
## the roll coming in from PAD_CORE_M (at most a quarter of the radius) over PAD_ROLL_IN_M. The props
## a dressing stands on it are each set on the ground under them (PoiKit.on_ground). A settlement's
## pad, an authored one (the atlas's `pads`) and a step (a fall's, a cave's) stay as they were.
PAD_TILT_SHARE = 0.6
PAD_TILT_MAX = 0.06
PAD_ROLL_M = 0.45
PAD_ROLL_WL_M = (30.0, 60.0)
PAD_CORE_M = 5.0
PAD_ROLL_IN_M = 12.0
PAD_FIT_RING_M = 14.0


def pad_is_natural(place: dict) -> bool:
    """A pad that keeps the land's lie (`pad_relief`): a point of interest's or a wayside find's,
    not a settlement's (whose houses stand on its level ground)."""
    pid = str(place.get("id", ""))
    if pid in RING_TOWNS:
        return False
    return ":place/" not in pid or str(place.get("kind", "")) not in FABRIC_COUNT


def land_tilt(place: dict, H: np.ndarray, grid: Grid, r_reach: float, share: float, cap: float) -> tuple:
    """(grade east, grade south): `share` of the land's own tilt round a pad, a plane fitted over the
    ring just past its skirt (where no pad has been, so a pad laid again reads the same), and never
    steeper than `cap`."""
    px, pz = float(place["position"][0]), float(place["position"][1])
    a = np.linspace(0.0, 2.0 * math.pi, 24, endpoint=False)
    ring = r_reach + 0.5 * PAD_FIT_RING_M
    rx, rz = np.cos(a) * ring, np.sin(a) * ring
    from .grid import sample_bilinear
    hr = sample_bilinear(H, grid, px + rx, pz + rz).astype(np.float64)
    A = np.stack([rx, rz, np.ones_like(rx)], axis=1)
    (gx, gz, _c), *_ = np.linalg.lstsq(A, hr, rcond=None)
    tx, tz = share * float(gx), share * float(gz)
    t = math.hypot(tx, tz)
    if t > cap:
        tx, tz = tx * cap / t, tz * cap / t
    return tx, tz


## Pad shapes. A level pad (with a POI's tilt and roll, `pad_relief`) is right for almost everything,
## but not for a hole in a hillside. Brightwater found the Hush Hole reading as a mound with a door and
## Cadbrae's slate cut as a raised disc: a cave's mouth wants its own bank behind it and a quarry's
## benches the slope they were cut into, and the level pad takes both away. So a pad has a shape
## (`pad_shape`, from the POI def, else from its kind):
##   "level"   the pad above (every settlement, every pad the atlas fixes, and the default);
##   "slope"   keeps the land's own lie, its banks and benches, and only softens it (a gaussian of
##             SLOPE_SMOOTH_M: the bumps go, a bank stays): kinds SLOPE_KINDS, and a delve whose
##             mouth is the cave builder's (not a lava tube's). A plane fitted round the pad was
##             tried first: on the 1024 preview it read the Hush Hole's and Cadbrae's broad lie
##             (0.07 and 0.01) and levelled the local bank each is cut into, which is the point;
##   "trench"  the level pad with a trench sunk into it (`trench` in the def; `trench_depth`): the
##             Kilnway's lava tube, whose mouth is a trench cut into the heath, which the game cannot
##             dig at runtime.
## A cave's rise (worldgen.falls.caves) goes on over a sloped pad where the slope is not already
## higher than it. The game lays the same shapes for a POI it previews (TerrainProvider.lay_pad,
## PoiPreview) and is told the shape on each pois.json entry.
SLOPE_KINDS = ("cave", "quarry")
SLOPE_SMOOTH_M = 5.0
PAD_SHAPES = ("level", "slope", "trench")


def pad_shape(place: dict) -> str:
    """"level", "slope" or "trench" (see SLOPE_KINDS): the def's own `pad_shape`, else by kind."""
    asked = str(place.get("pad_shape", "") or "")
    if asked in PAD_SHAPES:
        if asked == "trench" and not isinstance(place.get("trench"), dict):
            return "level"
        return asked
    if not pad_is_natural(place):
        return "level"
    kind = str(place.get("kind", ""))
    if kind in SLOPE_KINDS or (kind == "delve" and str(place.get("mouth", "") or "") != "lava"):
        return "slope"
    return "level"


def trench_depth(trench: dict, dx, dz) -> np.ndarray:
    """Metres the land is sunk at offsets (dx, dz) from a pad's middle by its `trench`:
    {bearing_deg (the way it runs out to its open end, a yaw as `PoiKit.yaw_of` measures it),
     length_m (from the middle out to the top of its ramp), ramp_m, width_m (its floor), depth_m,
     behind_m (how far its floor runs back behind the middle), head_width_m and head_from_m (a wider
     floor behind `head_from_m` metres out, which may be negative: room for a throat that bends),
     side_m (over how far its sides come up to the land)}."""
    dx = np.asarray(dx, dtype=np.float64)
    dz = np.asarray(dz, dtype=np.float64)
    b = math.radians(float(trench.get("bearing_deg", 0.0)))
    fx, fz = math.sin(b), math.cos(b)
    depth = float(trench.get("depth_m", 2.0))
    side = float(trench.get("side_m", max(2.5, 1.3 * depth)))
    length = float(trench.get("length_m", 10.0))
    ramp = min(float(trench.get("ramp_m", 6.0)), length)
    behind = float(trench.get("behind_m", 0.0))
    half = 0.5 * float(trench.get("width_m", 5.0))
    head = 0.5 * float(trench.get("head_width_m", 2.0 * half))
    head_from = float(trench.get("head_from_m", 0.0))
    u = dx * fx + dz * fz
    v = np.abs(-dx * fz + dz * fx)
    h = half + (head - half) * (1.0 - smoothstep(head_from - side, head_from, u))
    across = 1.0 - smoothstep(h, h + side, v)
    along = (1.0 - smoothstep(length - ramp, length, u)) * smoothstep(-behind - side, -behind, u)
    return (depth * across * along).astype(np.float32)


def pad_relief(place: dict, dx: np.ndarray, dz: np.ndarray, H: np.ndarray, grid: Grid,
               r_reach: float) -> np.ndarray:
    """Metres over the pad's level at offsets (dx, dz) from its middle: the land's tilt and a
    gentle roll, both nothing at the middle (`pad_is_natural` pads; see PAD_TILT_SHARE)."""
    import zlib

    r = pad_radius(place)
    tx, tz = land_tilt(place, H, grid, r_reach, PAD_TILT_SHARE, PAD_TILT_MAX)
    # the roll: three long waves at their own bearings, seeded by the place
    rng = np.random.default_rng(zlib.crc32(("pad-roll:" + str(place.get("id", ""))).encode("utf-8")))
    roll = np.zeros(np.broadcast(dx, dz).shape, dtype=np.float64)
    for _ in range(3):
        b = rng.uniform(0.0, 2.0 * math.pi)
        wl = rng.uniform(*PAD_ROLL_WL_M)
        roll = roll + np.sin((dx * math.cos(b) + dz * math.sin(b)) * 2.0 * math.pi / wl + rng.uniform(0.0, 2.0 * math.pi))
    d = np.sqrt(dx * dx + dz * dz)
    core = min(PAD_CORE_M, 0.25 * r)
    roll = PAD_ROLL_M / 3.0 * roll * smoothstep(core, core + PAD_ROLL_IN_M, d)
    # (the roll's value at the middle is nothing: it only comes in past the core)
    return (tx * dx + tz * dz + roll).astype(np.float32)


def pad_reach(place: dict) -> float:
    """How far out a place's pad changes the land at all: the end of its skirt."""
    return pad_level_radius(place) + PAD_SKIRT * pad_radius(place)


def apply_pads(grid: Grid, H: np.ndarray, places: list, min_levels: dict | None = None,
               fixed_levels: dict | None = None, hold: np.ndarray | None = None,
               steps: dict | None = None) -> tuple:
    """Flatten a platform at every place. Returns (heights, pad_mask, pad heights by place id).

    `min_levels` lifts a pad that would otherwise sit under standing water: a stilt-town in
    the marsh stands on the highest peat island it can find, not in the pools.

    `hold` (0..1 at each texel, 1 where the pad is free) holds the land against a pad's skirt:
    the build passes the roads' clearance (`landforms.road_clear`) when it lays the pads again
    after the roads. A road is graded against the land it was routed over, and a skirt laid
    again over it moved that land from under it: 18 m down under the Chain Bridge road beside
    Kharrow Hold, 16 m up under the Fernhold road below Grandfather Hollow. The level core is
    never held: whatever crosses it stands at the pad's level.

    `steps` ({place id: worldgen.falls.Step}) lays a waterfall's pad as a step: level at its foot
    in front of the face and at its top behind it (`Step.rise`), the foot being the pad's level.
    """
    n = grid.n
    X, Z = grid.mesh()
    pad_mask = np.zeros((n, n), dtype=bool)
    levels: dict[str, float] = {}
    for p in places:
        px, pz = float(p["position"][0]), float(p["position"][1])
        r = pad_radius(p)
        r_level, r_reach = pad_level_radius(p), pad_reach(p)
        j, i = grid.to_tex(px, pz)
        j, i = grid.clamp_index(j, i)
        rad_t = max(int(r_reach / grid.spacing / 2.0) + 4, 3)
        i0, i1 = max(0, int(i) - 2 * rad_t), min(n, int(i) + 2 * rad_t + 1)
        j0, j1 = max(0, int(j) - 2 * rad_t), min(n, int(j) + 2 * rad_t + 1)
        sub = H[i0:i1, j0:j1]
        dx = X[:, j0:j1] - px
        dz = Z[i0:i1, :] - pz
        d = np.sqrt(dx * dx + dz * dz)
        shape = pad_shape(p) if not (fixed_levels is not None and p["id"] in fixed_levels) else "level"
        sunk = trench_depth(p["trench"], dx, dz) if shape == "trench" else None
        inner = d <= r * 0.75
        if sunk is not None and (inner & (sunk <= 0.0)).any():
            inner = inner & (sunk <= 0.0)            # the level from the land, not the trench in it
        level = float(np.median(sub[inner])) if inner.any() else float(H[int(i), int(j)])
        if min_levels is not None and p["id"] in min_levels:
            level = max(level, float(min_levels[p["id"]]))
        if fixed_levels is not None and p["id"] in fixed_levels:
            # the atlas says where this one stands (`pads`): a landing at the foot of a cliff,
            # a shelf over the water, which the ground under it cannot say
            level = float(fixed_levels[p["id"]])
        step = steps.get(p["id"]) if steps else None
        target = level
        slope = None
        if shape == "slope":
            # the land itself, softened (laid again, it softens a little more: a plane stays a plane)
            soft = ndimage.gaussian_filter(sub.astype(np.float64), SLOPE_SMOOTH_M / grid.spacing, mode="nearest")
            slope = (soft - (float(step.foot) if step is not None else level)).astype(np.float32)
        if step is not None:
            level = float(step.foot)
            rise = step.rise(X[:, j0:j1], Z[i0:i1, :])
            if slope is not None:
                # the land's slope, and the rise only where it stands higher than the slope does
                target = (level + slope + np.maximum(rise - np.maximum(slope, 0.0), 0.0)).astype(np.float32)
            else:
                target = (level + rise).astype(np.float32)
        elif slope is not None:
            target = (level + slope).astype(np.float32)
        elif pad_is_natural(p) and not (fixed_levels is not None and p["id"] in fixed_levels):
            target = (level + pad_relief(p, dx, dz, H, grid, r_reach)).astype(np.float32)
        levels[p["id"]] = level
        w = 1.0 - smoothstep(r_level, r_reach, d)
        if hold is not None:
            w = np.where(d <= r_level, w, w * hold[i0:i1, j0:j1])
        if sunk is not None:
            # the trench is the pad's own, laid whole wherever it reaches (it lies inside the level core)
            target = (target - sunk).astype(np.float32)
            w = np.where(sunk > 0.0, 1.0, w)
        if fixed_levels is not None and p["id"] in fixed_levels:
            # An authored pad is a landing on a shelf or at a cliff's foot. Its skirt takes the
            # ground down to it, but builds nothing out over a drop: blended over the edge of the
            # Hushline's shelf it filled the sea at the foot of the face up to a lip at sea level.
            w = np.where((d > r_level) & (sub < level - PAD_DROP_M), 0.0, w)
        H[i0:i1, j0:j1] = lerp(sub, target, w)
        pad_mask[i0:i1, j0:j1] |= d <= max(r, r_level)
    return H, pad_mask, levels


## A pad's skirt that fills across a valley dams it. Fernhold's lodge pad (level 274 m) was laid
## over the head of a stream valley whose floor under its western skirt was near 190 m: the skirt
## blended from 190 to 274 over 33 m and closed the valley's way out, leaving a dry pit 52 m deep
## and 60 m across at the settlement's edge, walled on the pad side at seventy degrees (the owner's
## Briar crash, 2026-09-30: whatever went in did not come out). Every dry closed hollow that a
## pad's skirt closes is filled back to where it would spill, less DAM_DELL_M, so the valley is a
## dell under the pad and never a pit. A hollow no deeper than DAM_MIN_M is left as it is: the
## limestone's shakeholes and the ash's buried streets are hollows by design, and the marsh's
## pools are water. DAM_WINDOW_M is how far round a pad's skirt a hollow is looked for.
DAM_MIN_M = 6.0
DAM_DELL_M = 1.5
DAM_WINDOW_M = 260.0


def drain_pad_dams(grid: Grid, H: np.ndarray, places: list, outlet: np.ndarray | None = None,
                   hold: np.ndarray | None = None) -> tuple:
    """Fill every dry closed hollow a pad's skirt dams (see DAM_MIN_M). Returns (heights, report).

    `outlet` (bool, grid.n) is where water may leave the land: the sea, the lakes and the rivers'
    channels; a hollow that reaches one is not closed. `hold` (0..1, 1 where the land is free) is
    the roads' clearance: a road graded through a hollow keeps its ground. `report` is one
    (place id, deepest m, filled texels) per hollow filled. Each pad is looked at in a window of
    DAM_WINDOW_M past its reach, whose edge counts as open: a hollow bigger than that is a basin
    of the country's own, not a pad's.
    """
    from skimage.morphology import reconstruction

    n = grid.n
    X, Z = grid.mesh()
    report = []
    for p in places:
        px, pz = float(p["position"][0]), float(p["position"][1])
        r_level, r_reach = pad_level_radius(p), pad_reach(p)
        j, i = grid.to_tex(px, pz)
        j, i = grid.clamp_index(j, i)
        rad_t = int((r_reach + DAM_WINDOW_M) / grid.spacing) + 2
        i0, i1 = max(0, int(i) - rad_t), min(n, int(i) + rad_t + 1)
        j0, j1 = max(0, int(j) - rad_t), min(n, int(j) + rad_t + 1)
        sub = H[i0:i1, j0:j1].astype(np.float64)
        if sub.shape[0] < 3 or sub.shape[1] < 3:
            continue
        seed = np.full_like(sub, float(sub.max()))
        edge = np.zeros(sub.shape, dtype=bool)
        edge[0, :] = edge[-1, :] = edge[:, 0] = edge[:, -1] = True
        if outlet is not None:
            edge |= outlet[i0:i1, j0:j1]
        seed[edge] = sub[edge]
        filled = reconstruction(seed, sub, method="erosion")
        depth = filled - sub
        lab, count = ndimage.label(depth > 0.25)
        if count == 0:
            continue
        d = np.sqrt((X[:, j0:j1] - px) ** 2 + (Z[i0:i1, :] - pz) ** 2)
        # the skirt, and a few texels past it: where a pad's fill meets what it closed
        skirt = (d >= r_level - grid.spacing) & (d <= r_reach + 2.0 * grid.spacing)
        ids = np.arange(1, count + 1)
        deepest = ndimage.maximum(depth, lab, ids)
        touches = ndimage.maximum(skirt.astype(np.uint8), lab, ids)
        take = ids[(deepest > DAM_MIN_M) & (touches > 0)]
        if take.size == 0:
            continue
        m = np.isin(lab, take)
        raise_m = np.where(m, np.maximum(depth - DAM_DELL_M, 0.0), 0.0)
        if hold is not None:
            raise_m = raise_m * hold[i0:i1, j0:j1]
        H[i0:i1, j0:j1] = (sub + raise_m).astype(np.float32)
        for k in take:
            report.append((str(p.get("id", "")), float(deepest[k - 1]), int((lab == k).sum())))
    return H, report


## The design grade. A laden cart takes one in nine, and the router is what keeps a road under
## it -- by going round a slope, or up it in zigzags -- not the profile: the profile follows the
## ground, and it is never lifted off it or sunk into it to make a grade the route did not have.
MAX_GRADE = 0.11
## The steepest side slope the carve may leave between a road and the ground either side of
## it: one in two. `carve_roads` blends a road into the land across its shoulder with a
## smoothstep, whose steepest point is one and a half times its mean, so a road may stand
## `BATTER * shoulder / 1.5` metres off its own ground -- 2.4 m for a four-metre track, 3.6 m
## for a six-metre town road. That is a cutting or an embankment. It is never an arete: the
## old profile limited the grade by lifting the road, and on the spur out of Kharrow Hold it
## stood 150 m above the ground on both sides.
BATTER = 0.5
## A stair (the atlas's road kind "stair"): laid straight between its via points, as steep as
## thirty-five degrees -- steps cut into a bank the way a cliff path is -- and three metres wide.
STAIR_MAX_GRADE = 0.7
## How far below the land a road would rather run, by landform (`plan_roads`' `sink`). The
## Briarwold's lanes are holloways: a track in old ground on soft rock wears down between its
## own banks until the wood closes over it, and from inside one you see bank, roots and a strip
## of sky -- which is a different frame from a road across open downland. It is held inside the
## same band as any other road, so a holloway is a cutting and never a trench.
ROAD_SINK_M = {"forest_rise": 1.9}


def shoulder_m(width: float) -> float:
    """How far either side of the carriageway the carve blends back into the land."""
    return max(float(width) * 1.8, 7.0)


def cut_fill_m(width: float) -> float:
    """The most a road of this width may stand above, or lie below, the ground under it."""
    return BATTER * shoulder_m(width) / 1.5


def grade_profile(ground: np.ndarray, step_m: float, tol: float, max_grade: float = MAX_GRADE,
                  pins: dict | None = None, smooth_m: float = 60.0, sweeps: int = 60,
                  bias: np.ndarray | None = None, no_fill: np.ndarray | None = None,
                  near_lo: np.ndarray | None = None, near_hi: np.ndarray | None = None) -> np.ndarray:
    """A road's elevation along its length, sampled every `step_m` metres.

    As smooth as the ground allows, never more than `tol` above or below the ground under it,
    and no steeper than `max_grade` wherever the band leaves room for that. `pins` maps a sample
    index to a level it must take (a settlement's pad at each end, the grade of a road this one
    runs along); a pin outside the band is pulled into it. `bias` (metres, per sample) is where
    the road would rather lie relative to the ground -- a holloway wants to be below it -- and
    is still held inside the band. Where `no_fill` is set the band's top is the ground itself:
    the road may cut there but not stand proud. `near_lo` / `near_hi` narrow the band where
    another road passes close by; where that window and the ground's band do not overlap, the
    ground's band wins, because a road is never lifted off its land to meet another.

    Where the ground itself is steeper than the grade plus the room either side, the band wins:
    the road climbs with the ground for that pitch. That is the honest failure -- a steep
    stretch of road -- and the router is what keeps it rare.
    """
    g = np.asarray(ground, dtype=np.float64)
    n = g.size
    if n == 0:
        return g.astype(np.float32)
    lo = g - tol
    hi = g + tol
    if no_fill is not None:
        hi = np.where(np.asarray(no_fill, dtype=bool), g, hi)
    if near_lo is not None and near_hi is not None:
        lo2 = np.maximum(lo, np.asarray(near_lo, dtype=np.float64))
        hi2 = np.minimum(hi, np.asarray(near_hi, dtype=np.float64))
        agree = lo2 <= hi2
        lo = np.where(agree, lo2, lo)
        hi = np.where(agree, hi2, hi)
    for k, v in (pins or {}).items():
        k = int(k)
        if 0 <= k < n:
            v = float(min(max(v, lo[k]), hi[k]))
            lo[k] = hi[k] = v
    if n < 3:
        return np.clip(g, lo, hi).astype(np.float32)
    k = max(3, int(round(smooth_m / step_m)) | 1)
    e = np.convolve(np.pad(g, (k, k), mode="edge"), np.ones(k) / k, mode="same")[k:-k]
    if bias is not None:
        e = e + np.asarray(bias, dtype=np.float64)
    e = np.clip(e, lo, hi)
    step = max_grade * step_m
    for _ in range(sweeps):
        before = e.copy()
        for i in range(1, n):                      # forward: no steeper than the grade...
            e[i] = min(max(e[i], e[i - 1] - step), e[i - 1] + step)
            e[i] = min(max(e[i], lo[i]), hi[i])    # ...and never out of the band
        for i in range(n - 2, -1, -1):             # and back again
            e[i] = min(max(e[i], e[i + 1] - step), e[i + 1] + step)
            e[i] = min(max(e[i], lo[i]), hi[i])
        if float(np.abs(e - before).max()) < 1e-3:
            break
    # take the corners off the kinks the sweeps leave, and keep it in the band doing so
    for _ in range(2):
        e[1:-1] = 0.25 * e[:-2] + 0.5 * e[1:-1] + 0.25 * e[2:]
        e = np.clip(e, lo, hi)
    return e.astype(np.float32)


## Routing. A road is a least-cost path on a coarse lattice whose cost knows three things the
## old one did not. Grade costs the same both ways: a road is driven in both directions, and
## the old graph charged for climbing and nothing for descending, so a route planned from
## Kharrow Hold down to the Mere went straight over the edge of the mountain. Grade past the
## design grade costs quadratically, so a steep slope is worth going round or zigzagging up
## rather than climbing straight. And a change of heading costs something, because a lattice
## path that alternates two diagonals has a gentle grade on every edge and smooths out into a
## road straight up the fall line; with turns priced, a switchback's legs have to be long.
##
## Eight headings are enough to choose which side of a hill to go. They are not enough to climb
## one: on a uniform slope every edge that climbs at all climbs at 71% of the slope or more, so
## above 16% no lattice path has a gentle edge in it and the router cannot see what a
## switchback buys. The fine pass (`_refine`) adds the knight's moves, whose 27-degree heading
## across the fall line climbs at 45% of the slope, and that is what lets it zigzag.
_HEADINGS8 = ((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))
_HEADINGS16 = ((0, 1), (1, 2), (1, 1), (2, 1), (1, 0), (2, -1), (1, -1), (1, -2),
               (0, -1), (-1, -2), (-1, -1), (-2, -1), (-1, 0), (-2, 1), (-1, 1), (-1, 2))
_HEADINGS = _HEADINGS8
## metres of road that a change of heading is worth, by how far it turns: up to 30, 50, 95 and
## 140 degrees, and anything sharper (a hairpin)
_TURN_BY_ANGLE = ((1.0, 0.0), (30.0, 3.0), (50.0, 8.0), (95.0, 55.0), (140.0, 130.0), (181.0, 190.0))
_GRADE_LINEAR = 12.0
_GRADE_OVER = (0.10, 400.0)          # past this grade, cost grows with the square of the excess
_GRADE_STEEP = (0.22, 1500.0)        # and past this, much faster still


def _turn_table(headings: tuple) -> np.ndarray:
    """[from, to] cost of turning between two headings, by the angle between them."""
    ang = [math.atan2(di, dj) for di, dj in headings]
    nh = len(headings)
    out = np.zeros((nh, nh), dtype=np.float64)
    for a in range(nh):
        for b in range(nh):
            turn = abs(math.degrees(ang[b] - ang[a])) % 360.0
            turn = min(turn, 360.0 - turn)
            out[a, b] = next(c for limit, c in _TURN_BY_ANGLE if turn <= limit)
    return out


def _edge_costs(h: np.ndarray, area: np.ndarray, spacing: float, headings: tuple = _HEADINGS8) -> list:
    """Per heading, the cost of leaving each cell that way (inf where it would leave the box)."""
    m, k = h.shape
    out = []
    for di, dj in headings:
        length = spacing * math.hypot(di, dj)
        src_i = slice(max(0, -di), m - max(0, di))
        src_j = slice(max(0, -dj), k - max(0, dj))
        dst_i = slice(max(0, di), m - max(0, -di))
        dst_j = slice(max(0, dj), k - max(0, -dj))
        grade = np.abs(h[dst_i, dst_j] - h[src_i, src_j]) / length
        over = np.maximum(grade - _GRADE_OVER[0], 0.0)
        steep = np.maximum(grade - _GRADE_STEEP[0], 0.0)
        c = length * (0.5 * (area[src_i, src_j] + area[dst_i, dst_j]) + _GRADE_LINEAR * grade
                      + _GRADE_OVER[1] * over * over + _GRADE_STEEP[1] * steep * steep)
        full = np.full((m, k), np.inf, dtype=np.float64)
        full[src_i, src_j] = c
        out.append(full)
    return out


def _route(h: np.ndarray, area: np.ndarray, spacing: float, start: tuple, goal: tuple,
           margin: int, allowed: np.ndarray | None = None, headings: tuple = _HEADINGS8) -> list:
    """Least-cost lattice route with priced turns. Returns [(i, j), ...], or [] if there is none.

    The search is over (cell, heading) states inside a box around the two ends, `margin` cells
    wider than they are on every side: room to go round a hill, and a graph of a few hundred
    thousand states rather than two million. `allowed`, the lattice's shape, narrows the search
    further to a corridor; only its cells get states at all.
    """
    from scipy.sparse import coo_matrix, csgraph

    n0, n1 = h.shape
    i0 = max(0, min(start[0], goal[0]) - margin)
    i1 = min(n0, max(start[0], goal[0]) + margin + 1)
    j0 = max(0, min(start[1], goal[1]) - margin)
    j1 = min(n1, max(start[1], goal[1]) + margin + 1)
    hs = h[i0:i1, j0:j1].astype(np.float64)
    ar = area[i0:i1, j0:j1].astype(np.float64)
    m, k = hs.shape
    ok_cell = np.ones((m, k), dtype=bool) if allowed is None else allowed[i0:i1, j0:j1].copy()
    ok_cell[start[0] - i0, start[1] - j0] = True
    ok_cell[goal[0] - i0, goal[1] - j0] = True
    cells = int(ok_cell.sum())
    compact = np.full((m, k), -1, dtype=np.int64)
    compact[ok_cell] = np.arange(cells, dtype=np.int64)
    nh = len(headings)
    costs = _edge_costs(hs, ar, spacing, headings)
    turns = _turn_table(headings)
    rows, cols, data = [], [], []
    for d_out, (di, dj) in enumerate(headings):
        c = costs[d_out]
        si, sj = np.nonzero(np.isfinite(c) & ok_cell)
        ti, tj = si + di, sj + dj
        keep = compact[ti, tj] >= 0
        src = compact[si[keep], sj[keep]]
        dst = compact[ti[keep], tj[keep]]
        base = c[si[keep], sj[keep]]
        for d_in in range(nh):
            rows.append(src * nh + d_in)
            cols.append(dst * nh + d_out)
            data.append(base + turns[d_in, d_out])
    graph = coo_matrix((np.concatenate(data), (np.concatenate(rows), np.concatenate(cols))),
                       shape=(cells * nh, cells * nh)).tocsr()
    s_cell = int(compact[start[0] - i0, start[1] - j0])
    g_cell = int(compact[goal[0] - i0, goal[1] - j0])
    sources = {s_cell * nh + d for d in range(nh)}
    dist, pred, _ = csgraph.dijkstra(graph, directed=True, indices=sorted(sources), min_only=True,
                                     return_predecessors=True)
    goals = np.array([g_cell * nh + d for d in range(nh)])
    best = int(goals[int(np.argmin(dist[goals]))])
    if not np.isfinite(dist[best]):
        return []
    where = np.argwhere(ok_cell)                      # compact id -> (i, j) in the box
    path = []
    cur = best
    guard = 0
    while cur >= 0 and guard < cells * nh:
        ci, cj = where[cur // nh]
        cell = (int(ci) + i0, int(cj) + j0)
        if not path or path[-1] != cell:
            path.append(cell)
        if cur in sources:
            break
        cur = int(pred[cur])
        guard += 1
    path.reverse()
    return path


## What a metre of road across open water costs, in metres of road on dry ground.
WATER_COST = 30.0


def _water_cells(water_mask: np.ndarray, n: int) -> np.ndarray:
    """How much of each coarse cell is water that a road cannot stand on, 0..1.

    A cell counts as water only where all of it is: the Long Stride is twelve metres wide, and
    a sixteen-metre cell with the causeway down its middle is half water by area -- which
    priced the causeway nearly as high as the open Mere, and the road to Tollmere swam.
    """
    m = water_mask.shape[0]
    if m == n:
        return water_mask.astype(np.float32)
    if n > m or m % n:
        return downsample(water_mask.astype(np.float32), n)
    f = m // n
    return water_mask.reshape(n, f, n, f).min(axis=(1, 3)).astype(np.float32)


## A road that follows the crest of a knife-edge spur, or the floor of a V-shaped gully, stands
## above (or below) the ground either side of it by the ground's own relief, and from beside it
## that reads exactly as the arete did. Measured on the first build with the new profile, the
## road down the spur from Kharrow Hold stood 12.5 m above both sides on natural ground. So the
## fine router prices how far a cell stands above or below its own twenty metres (`CREST_COST`
## per metre past `CREST_FREE_M`), and a road crosses a spur or a gully rather than riding it.
CREST_FREE_M = 1.5
CREST_COST = 1.4
CLIFF_COST = 30.0
## A road already laid is cheaper to follow than new ground is to cross: two roads out of one
## town share their trunk and fork, rather than running side by side a few metres apart at two
## different levels, which is where their carves cut steps into each other.
TRUNK_DISCOUNT = 0.55


def _refine(grid: Grid, H: np.ndarray, water_mask: np.ndarray, coarse_pts: np.ndarray,
            spacing: float = 4.0, corridor_m: float = 64.0,
            laid: list | None = None) -> np.ndarray | None:
    """Route again on a fine lattice, inside a corridor around the coarse route.

    The coarse lattice is sixteen metres a cell, which is fine for choosing which side of a hill
    to go but too coarse to lay a road on: smoothing its staircase into a curve cuts the corners
    of every switchback and steepens it. Re-routed at four metres within sixty of the coarse
    line, the road finds the gentle line across each slope at the scale it is actually built,
    and the curve it smooths into is already most of the way to smooth. `laid` is the centre
    lines of the roads already planned (world points), which this one would rather share.
    Returns world points, or None when the grid is too coarse for a second pass to add anything.
    """
    spacing = max(spacing, grid.spacing)
    n_f = int(round(grid.size_m / spacing))
    if spacing >= 12.0 or grid.n % n_f != 0:
        return None
    gf = grid.with_n(n_f)
    # a box around the coarse line, so the fine arrays are only as large as the road needs
    pad = corridor_m + 8.0 * spacing
    x0, x1 = float(coarse_pts[:, 0].min() - pad), float(coarse_pts[:, 0].max() + pad)
    z0, z1 = float(coarse_pts[:, 1].min() - pad), float(coarse_pts[:, 1].max() + pad)
    j0, i0 = gf.to_tex(x0, z0)
    j1, i1 = gf.to_tex(x1, z1)
    i0, j0 = max(0, int(i0)), max(0, int(j0))
    i1, j1 = min(n_f, int(i1) + 2), min(n_f, int(j1) + 2)
    f = grid.n // n_f
    sub_h = H[i0 * f:i1 * f, j0 * f:j1 * f]
    sub_w = water_mask[i0 * f:i1 * f, j0 * f:j1 * f].astype(np.float32)
    m, k = i1 - i0, j1 - j0
    if f > 1:
        sub_h = sub_h[:m * f, :k * f].reshape(m, f, k, f).mean(axis=(1, 3))
        sub_w = sub_w[:m * f, :k * f].reshape(m, f, k, f).min(axis=(1, 3))
    # The route should see the lie of the land, not every tussock: routed over the raw detail
    # band, the road wove round bumps a metre high and drew a drunkard's line across the moor.
    # Bumps that small are what the profile's own tolerance absorbs. What smoothing must not
    # hide is a cleft: a ravine twelve metres across and eighteen deep smooths into a dimple,
    # and a road that crosses it has to go down into it. So the raw ground's steepest pitch
    # nearby is priced separately, whichever way the road crosses it.
    raw = sub_h.astype(np.float64)
    raw_slope = ndimage.maximum_filter(np.hypot(*np.gradient(raw, spacing)), size=3)
    # how far each cell stands proud of (or sunk into) the ground within about twenty metres
    crest = np.abs(raw - ndimage.gaussian_filter(raw, sigma=10.0 / spacing, mode="nearest"))
    sub_h = ndimage.gaussian_filter(raw, sigma=6.0 / spacing, mode="nearest")
    # the corridor: within `corridor_m` of the coarse line
    line = np.zeros((m, k), dtype=bool)
    dense = paths.resample_polyline(coarse_pts, spacing * 0.5)
    lj = np.clip(np.rint((dense[:, 0] - gf.x0) / spacing).astype(np.int64) - j0, 0, k - 1)
    li = np.clip(np.rint((dense[:, 1] - gf.z0) / spacing).astype(np.int64) - i0, 0, m - 1)
    line[li, lj] = True
    allowed = ndimage.distance_transform_edt(~line) * spacing <= corridor_m
    # A cliff is priced hard enough that a road will go three hundred metres round a gorge
    # rather than down one wall and up the other: a profile that follows the ground has no
    # other way to cross a slot twelve metres wide than to go into it.
    area = 1.0 + WATER_COST * sub_w + 6.0 * np.clip(raw_slope - 0.45, 0.0, None) \
        + CLIFF_COST * np.clip(raw_slope - 0.9, 0.0, None) \
        + CREST_COST * np.clip(crest - CREST_FREE_M, 0.0, None)
    if laid:
        on = np.zeros((m, k), dtype=bool)
        for pts in laid:
            q = paths.resample_polyline(np.asarray(pts, dtype=np.float64), spacing * 0.5)
            qj = np.rint((q[:, 0] - gf.x0) / spacing).astype(np.int64) - j0
            qi = np.rint((q[:, 1] - gf.z0) / spacing).astype(np.int64) - i0
            ok = (qi >= 0) & (qi < m) & (qj >= 0) & (qj < k)
            on[qi[ok], qj[ok]] = True
        area = np.where(on, area * TRUNK_DISCOUNT, area)
    start = (int(li[0]), int(lj[0]))
    goal = (int(li[-1]), int(lj[-1]))
    route = _route(sub_h, area, spacing, start, goal, margin=max(m, k), allowed=allowed,
                   headings=_HEADINGS16)
    if len(route) < 3:
        return None
    return np.array([[gf.x0 + (j + j0) * spacing, gf.z0 + (i + i0) * spacing] for i, j in route],
                    dtype=np.float64)


def _ground_along(grid: Grid, H: np.ndarray, pts: np.ndarray, width: float,
                  floor: np.ndarray | None = None) -> np.ndarray:
    """The land under a road: the mean across its carriageway, at each point.

    `floor` lifts it where the road crosses water, so a profile laid across a river is laid
    across its surface and not along its bed.
    """
    from .grid import sample_bilinear

    d = np.gradient(pts, axis=0)
    nrm = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)
    nx, nz = -d[:, 1] / nrm, d[:, 0] / nrm
    acc = np.zeros(pts.shape[0], dtype=np.float64)
    for off in (-0.5 * width, 0.0, 0.5 * width):
        x = pts[:, 0] + nx * off
        z = pts[:, 1] + nz * off
        h = sample_bilinear(H, grid, x, z).astype(np.float64)
        if floor is not None:
            h = np.maximum(h, sample_bilinear(floor, grid, x, z).astype(np.float64))
        acc += h
    return acc / 3.0


## A road that comes back within SPUR_NEAR_M of where it was SPUR_ALONG_M or more before, over
## ground within SPUR_LEVEL_M of the same height, has gone out and back: the spur is cut.
SPUR_NEAR_M = 12.0
SPUR_ALONG_M = 60.0
SPUR_LEVEL_M = 3.0


def cut_spurs(pts: np.ndarray, ground: np.ndarray, keep: np.ndarray | None = None) -> np.ndarray:
    """`pts` with every out-and-back spur taken out; `ground` is the land under each point.

    A `via` point drawn on a knoll above the way the road can take makes the road climb to it and
    come back down the same line: on the final build of the drawn atlas 25 roads did, over 60 m
    to 1.8 km (Pilgrim's Ash to Ashwell went up to the Wellspring's plateau and back for 1.6 km).
    The carve can hold only one level where the two legs lie side by side, so the land under one
    of them stood metres off its grade. Where the road comes back beside a point it passed, over
    land at the same height, the road goes straight on from that point. `keep` marks points that
    may not be cut out (the ends)."""
    n = pts.shape[0]
    if n < 4:
        return pts
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    out = [0]
    i = 0
    while i < n - 1:
        d = np.hypot(pts[i + 1:, 0] - pts[i, 0], pts[i + 1:, 1] - pts[i, 1])
        ok = (d < SPUR_NEAR_M) & (cum[i + 1:] - cum[i] > SPUR_ALONG_M) & (np.abs(ground[i + 1:] - ground[i]) < SPUR_LEVEL_M)
        cand = np.flatnonzero(ok)
        j = i + 1
        if cand.size:
            far = i + 1 + int(cand[-1])
            if keep is None or not keep[i + 1:far].any():
                j = far
        out.append(j)
        i = j
    return pts[np.asarray(out)]


def stop_short(pts: np.ndarray, centre, radius: float, at_end: bool = True) -> np.ndarray:
    """A road that runs into something solid stops at its foot: `pts` cut where, walking toward
    `centre` from the road's other end, it first comes within `radius` of it, and ending on that
    circle. `at_end` says which end of `pts` the centre is at. A road that starts inside the circle
    is left alone."""
    seq = pts if at_end else pts[::-1]
    d = np.hypot(seq[:, 0] - float(centre[0]), seq[:, 1] - float(centre[1]))
    inside = np.flatnonzero(d < radius)
    if inside.size == 0 or int(inside[0]) == 0:
        return pts
    k = int(inside[0])
    p, q = seq[k - 1], seq[k]
    t = (d[k - 1] - radius) / max(d[k - 1] - d[k], 1e-9)
    out = np.vstack([seq[:k], (p + (q - p) * t)[None, :]])
    return out if at_end else out[::-1].copy()


def plan_roads(grid: Grid, H: np.ndarray, specs: list, things: dict, water_mask: np.ndarray, levels: dict,
               n_c: int = 512, floor: np.ndarray | None = None, sink: np.ndarray | None = None,
               no_fill: np.ndarray | None = None, lake=None, solid: dict | None = None) -> list:
    """The atlas's roads, each laid on the ground from its start through its via points to its end.

    `specs` is the atlas's `roads` (tools/world/atlas/SCHEMA.md) and `things` every place and POI
    by id. Each leg between two waypoints is routed with priced grades and turns (`_route`) on a
    16 m lattice and again on a 4 m one inside a corridor round the first (`_refine`); a
    causeway's legs over a lake (`lake`, geography.Waters) are laid straight along its deck.
    The whole is smoothed and given a profile that follows the ground within the carve's own
    tolerance (`grade_profile`). Where a road runs along one laid before it, it takes that road's
    levels, so two roads sharing the way out of a town are carved as one road and not as two at
    different heights. `floor` is the water surface a road may not be graded under (see
    `_ground_along`). `sink` is how far below the land a road would rather run, in metres, where
    that is a landform's character: the Briarwold's lanes are holloways, worn down between their
    banks by centuries of feet. `no_fill` marks ground a road may cut into but not build up: the
    corridors of the authored sightlines, where an embankment legal anywhere else rose into the
    line from Greyfold to the Cold Fire. `solid` is {place id: metres}: what stands solid on a
    place's own position, and how far it reaches across the ground from there, plus room for a
    body. A road to or from such a place stops at its foot (`stop_short`). The Sunken Choir's head
    colossus stands on the Choir's position, and the Stair Path ran on into it.
    """
    from scipy.spatial import cKDTree

    from .geography import ROAD_WIDTH_BY_KIND

    n_c = min(n_c, grid.n)
    gc = grid.with_n(n_c)
    hc = downsample(H, n_c)
    wc = _water_cells(water_mask, n_c)
    slope = np.hypot(*np.gradient(hc, gc.spacing)).astype(np.float32)
    # Open water is all but impassable; a river is crossed at a ford, and a causeway is dry
    # ground. The grade a road takes is priced per edge in `_route`; this is only the ground
    # nobody would bench a road into whichever way it crossed it.
    area = (1.0 + WATER_COST * wc + 3.0 * np.clip(slope - 0.55, 0.0, None))
    # and the spurs and gullies at this scale, so the fine pass is not handed a corridor that
    # runs along a knife-edge with nowhere else to go (`CREST_COST`, at a sixteen-metre cell)
    crest_c = np.abs(hc - ndimage.gaussian_filter(hc.astype(np.float64), sigma=1.5, mode="nearest"))
    area = area + 0.5 * CREST_COST * np.clip(crest_c - 2.0 * CREST_FREE_M, 0.0, None)
    # and the cliffs inside a cell, which its mean height hides: the steepest texel in it
    f = grid.n // n_c
    if f > 1 and grid.n % n_c == 0:
        steep = np.hypot(*np.gradient(H.astype(np.float32), grid.spacing))
        steep = steep.reshape(n_c, f, n_c, f).max(axis=(1, 3))
        area = area + 0.3 * CLIFF_COST * np.clip(steep - 0.9, 0.0, 3.0)
        del steep

    def ij(x, z):
        j, i = gc.to_tex(x, z)
        j, i = gc.clamp_index(j, i)
        return int(i), int(j)

    def over_lake(p, q) -> bool:
        if lake is None:
            return False
        from .grid import sample_nearest
        t = np.linspace(0.0, 1.0, 64)
        x = p[0] + (q[0] - p[0]) * t
        z = p[1] + (q[1] - p[1]) * t
        wet = sample_nearest((lake.sd < 0.0).astype(np.uint8), grid, x, z) > 0
        return bool(wet.mean() > 0.2)

    roads: list[Road] = []
    ids: set = set()
    laid_pts: list = []        # the centre lines of the roads already planned, every 2 m
    laid_elev: list = []       # and their levels there
    laid_ground: list = []     # and the land they were graded against
    laid_width: list = []      # and their widths
    # A profile every 4 m: at 12 m, a cleft twelve metres across was one sample on one road and
    # none on the next, and two roads sharing a trunk were graded 13 m apart at the same place.
    step_m = 4.0
    for spec in specs:
        a, b = things.get(spec["from"]), things.get(spec["to"])
        if a is None or b is None:
            continue
        kind = str(spec.get("kind", "road"))
        w = float(ROAD_WIDTH_BY_KIND.get(kind, 5.0))
        ends = [np.array(a["position"][:2], dtype=np.float64), np.array(b["position"][:2], dtype=np.float64)]
        wps = [ends[0]] + [np.array(v, dtype=np.float64) for v in spec.get("via", [])] + [ends[1]]
        # the roads already laid are cheaper to follow than new ground (TRUNK_DISCOUNT)
        area_now = area
        if laid_pts:
            on = np.zeros((n_c, n_c), dtype=bool)
            q = np.concatenate(laid_pts)
            qj, qi = gc.clamp_index(*gc.to_tex(q[:, 0], q[:, 1]))
            on[qi, qj] = True
            area_now = np.where(on, area * TRUNK_DISCOUNT, area)
        legs = []
        for p, q in zip(wps[:-1], wps[1:]):
            if kind == "stair" or (kind == "causeway" and over_lake(p, q)):
                legs.append(paths.resample_polyline(np.stack([p, q]), step_m))
                continue
            sa, sb = ij(p[0], p[1]), ij(q[0], q[1])
            span = int(max(abs(sa[0] - sb[0]), abs(sa[1] - sb[1])))
            route = _route(hc, area_now, gc.spacing, sa, sb, margin=max(30, int(0.45 * span)))
            # A box round the two ends is room to go round a hill, not round a lake. A route that
            # crosses open water gets the whole lattice to find a dry one; if there is none, the
            # water is the answer after all.
            if not route or sum(1 for i, j in route if wc[i, j] > 0.99) > 2:
                wide = _route(hc, area_now, gc.spacing, sa, sb, margin=n_c)
                if wide:
                    route = wide
            if len(route) < 3:
                legs.append(paths.resample_polyline(np.stack([p, q]), step_m))
                continue
            pts = np.array([[gc.x0 + j * gc.spacing, gc.z0 + i * gc.spacing] for i, j in route], dtype=np.float64)
            pts[0] = p
            pts[-1] = q
            fine = _refine(grid, H, water_mask, pts, laid=laid_pts)
            if fine is not None:
                fine[0] = p
                fine[-1] = q
                pts = paths.smooth_polyline(fine, passes=6)
            else:
                pts = paths.smooth_polyline(pts, passes=4)
            legs.append(pts)
        pts = np.concatenate([leg if k == 0 else leg[1:] for k, leg in enumerate(legs)])
        if kind != "stair":
            pts = paths.resample_polyline(pts, step_m)
            # no out-and-back spur to a via point drawn up a knoll (`cut_spurs`)
            from .grid import sample_bilinear
            before = pts.shape[0]
            pts = cut_spurs(pts, sample_bilinear(H, grid, pts[:, 0], pts[:, 1]))
            if pts.shape[0] < before:
                pts = paths.resample_polyline(paths.smooth_polyline(pts, passes=3), step_m)
        # (a stair keeps its corners: resampled across a switchback, a corner is cut short by a
        # step that runs straight down the fall line, the one line a stair must not take)
        pts[0] = ends[0]
        pts[-1] = ends[1]
        stopped = set()
        for at_end, tid in ((False, spec["from"]), (True, spec["to"])):
            reach = float((solid or {}).get(tid, 0.0))
            if reach > 0.0:
                n_before = pts.shape[0]
                pts = stop_short(pts, ends[1] if at_end else ends[0], reach, at_end)
                if pts.shape[0] != n_before or not np.allclose(pts[-1 if at_end else 0], ends[1 if at_end else 0]):
                    stopped.add(tid)
        last = pts.shape[0] - 1
        # Where this road's carriageway overlaps one already laid, it IS that road: its points
        # are moved onto the other's centre line and take its level and the land it recorded.
        # Laid a few metres beside it instead, the two were graded against different ground --
        # on either side of a scar's riser, ten metres apart in height across four -- and their
        # carves cut steps into each other.
        snapped: dict = {}
        tree = None
        max_w = max(ROAD_WIDTH_BY_KIND.values())
        if laid_pts:
            laid_all = np.concatenate(laid_pts)
            tree = cKDTree(laid_all)
            elev_all = np.concatenate(laid_elev)
            ground_all = np.concatenate(laid_ground)
            width_all = np.concatenate(laid_width)
            dist, near = tree.query(pts, distance_upper_bound=0.5 * (w + max_w) + 1.5)
            for kk in np.flatnonzero(np.isfinite(dist)):
                if not 0 < kk < last:
                    continue
                if float(dist[kk]) <= 0.5 * (w + float(width_all[near[kk]])) + 1.5:
                    pts[kk] = laid_all[near[kk]]
                    snapped[int(kk)] = int(near[kk])
        ground = _ground_along(grid, H, pts, w, floor)
        for kk, idx in snapped.items():
            ground[kk] = float(ground_all[idx])
        # (a road stopped at a landmark's foot ends on the ground there, which may be off its pad)
        pins = {0: float(ground[0]) if a["id"] in stopped else levels.get(a["id"], float(ground[0])),
                last: float(ground[-1]) if b["id"] in stopped else levels.get(b["id"], float(ground[-1]))}
        for kk, idx in snapped.items():
            pins[kk] = float(elev_all[idx])
        # and where it passes near one, it may differ from it by no more than a one-in-two
        # batter between the two carriageways allows, so the two carves meet on a bank
        near_lo = near_hi = None
        if tree is not None:
            reach = w * 0.5 + shoulder_m(max_w) + 0.5 * max_w
            dist, near = tree.query(pts, distance_upper_bound=reach)
            near_lo = np.full(pts.shape[0], -np.inf)
            near_hi = np.full(pts.shape[0], np.inf)
            for kk in np.flatnonzero(np.isfinite(dist)):
                if not 0 < kk < last or int(kk) in snapped:
                    continue
                e_other = float(elev_all[near[kk]])
                gap = float(dist[kk]) - 0.5 * w - 0.5 * float(width_all[near[kk]])
                if gap < shoulder_m(w) + shoulder_m(float(width_all[near[kk]])):
                    room = BATTER * max(gap, 0.0)
                    near_lo[kk] = e_other - room
                    near_hi[kk] = e_other + room
        bias = None
        if sink is not None:
            from .grid import sample_bilinear
            bias = -sample_bilinear(sink, grid, pts[:, 0], pts[:, 1]).astype(np.float64)
        cap = None
        if no_fill is not None:
            from .grid import sample_nearest
            cap = sample_nearest(no_fill.astype(np.uint8), grid, pts[:, 0], pts[:, 1]) > 0
        elev = grade_profile(ground, step_m, cut_fill_m(w),
                             max_grade=STAIR_MAX_GRADE if kind == "stair" else MAX_GRADE,
                             pins=pins, bias=bias, no_fill=cap, near_lo=near_lo, near_hi=near_hi,
                             **({"smooth_m": 12.0} if kind == "stair" else {}))
        rid = str(spec.get("id") or "core:road/%s_%s" % (a["id"].split("/")[-1], b["id"].split("/")[-1]))
        base_id, k = rid, 2
        while rid in ids:
            rid = "%s_%d" % (base_id, k)
            k += 1
        ids.add(rid)
        roads.append(Road(id=rid, points=pts, width=w, elevation=elev, ground=ground.astype(np.float32)))
        dense = paths.resample_polyline(pts, 2.0)
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        sd = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
        laid_pts.append(dense)
        laid_elev.append(np.interp(sd, s, elev.astype(np.float64)))
        laid_ground.append(np.interp(sd, s, ground.astype(np.float64)))
        laid_width.append(np.full(dense.shape[0], w))
    return roads


## How far off both legs of the through street a third road has to arrive to earn a cross
## street: more than about 49 degrees (|cos| under 0.66). It was 0.55, 57 degrees, and when the
## roads were laid on the ground instead of over it Pilgrim's Ash's side road came in 64 degrees
## off one leg and 50 off the other and the town lost its crossing. No other town changes: the
## only others with three roads (Grandfather Hollow, Kharrow Hold) send two of them out on one
## trunk, and Merrowby's and Gullhithe's side roads are 68 and 66 degrees off.
CROSS_STREET_DOT = 0.66


def add_streets(roads: list, places: list, levels: dict) -> list:
    """Carry every road through its settlement instead of stopping it at the middle.

    A road planned between two towns ends exactly on the second town's centre, so a place with
    three roads has three spokes meeting at a point. That is not a street plan: a settlement is
    somewhere a road passes *through*, and a town where two routes meet has a crossing.

    For each settlement this lays a street along the dominant pair of approach bearings, from
    one side of the pad to the other, and a cross street where a third road arrives at enough
    of an angle to justify one. The result is a polyline that enters the pad, crosses it and
    leaves, which is what the settlement builder needs to lay plots along a frontage, and which
    the surface rules pave.
    """
    by_place: dict = {}
    for r in roads:
        for end, other in ((0, -1), (-1, 0)):
            p = r.points[end]
            for pl in places:
                if pl.get("kind") not in ROAD_KINDS:
                    continue
                cx, cz = float(pl["position"][0]), float(pl["position"][1])
                if abs(p[0] - cx) < 1.0 and abs(p[1] - cz) < 1.0:
                    # the bearing the road arrives on, taken far enough back (about 72 m, which
                    # was six points when roads were sampled every 12 m) to ignore the last
                    # smoothing wiggle
                    seg = float(np.mean(np.linalg.norm(np.diff(r.points, axis=0), axis=1)))
                    step = min(max(1, int(round(72.0 / max(seg, 1e-3)))), len(r.points) - 1)
                    away = r.points[end - step] if end == -1 else r.points[step]
                    v = np.array([away[0] - cx, away[1] - cz], dtype=np.float64)
                    nrm = float(np.hypot(v[0], v[1]))
                    if nrm > 1e-3:
                        by_place.setdefault(pl["id"], (pl, []))[1].append(v / nrm)
    out: list[Road] = []
    rings = [pl for pl in places if str(pl.get("id", "")) in RING_TOWNS]
    if rings:
        roads = [ring_end(r, rings) for r in roads]
    for place in rings:
        out.extend(ring_streets(place, float(levels.get(place["id"], 0.0))))
    for pid, (place, dirs) in by_place.items():
        if pid in RING_TOWNS:
            continue
        short = pid.split("/")[-1]
        r_pad = pad_radius(place) * 0.94
        cx, cz = float(place["position"][0]), float(place["position"][1])
        level = float(levels.get(pid, 0.0))
        width = ROAD_WIDTH.get(str(place.get("kind", "")), 4.5)
        # the most opposed pair of approaches is the through route
        best = (2.0, dirs[0], -dirs[0])
        for i in range(len(dirs)):
            for j in range(i + 1, len(dirs)):
                dot = float(np.dot(dirs[i], dirs[j]))
                if dot < best[0]:
                    best = (dot, dirs[i], dirs[j])
        streets = [(best[1], best[2])]
        # a third road arriving across the grain earns a cross street
        for d in dirs:
            if abs(float(np.dot(d, best[1]))) < CROSS_STREET_DOT and abs(float(np.dot(d, best[2]))) < CROSS_STREET_DOT:
                streets.append((d, -d))
                break
        for n, (a, b) in enumerate(streets):
            pts = []
            for t in np.linspace(-1.0, 1.0, 13):
                d = a if t < 0 else b
                pts.append([cx + d[0] * r_pad * abs(t), cz + d[1] * r_pad * abs(t)])
            pts = np.array(pts, dtype=np.float64)
            # a street is level: it is laid on the flattened ground of the place itself
            elev = np.full(pts.shape[0], level, dtype=np.float64)
            out.append(Road(id="core:road/%s_street%s" % (short, "" if n == 0 else "_cross"),
                            points=pts, width=width, elevation=elev, ground=elev.copy()))
    return roads + out


def ring_streets(place: dict, level: float) -> list:
    """A ring town's streets: the closed ring, then the spur in to the door (`RING_TOWNS`)."""
    spec = RING_TOWNS[place["id"]]
    cx, cz = float(place["position"][0]), float(place["position"][1])
    short = place["id"].split("/")[-1]
    ring_m = float(spec["ring_m"])
    k = max(int(math.ceil(2.0 * math.pi * ring_m / 6.0)), 12)
    a = np.linspace(0.0, 2.0 * math.pi, k + 1)
    a[-1] = 0.0                                      # closed: the last point is the first
    ring = np.stack([cx + ring_m * np.sin(a), cz + ring_m * np.cos(a)], axis=1)
    b = math.radians(float(spec["spur_bearing_deg"]))
    # a point a metre, and at least as many as roads.json keeps of any road (the game reads a
    # road of four points or fewer as a stub, test_world_data)
    t = np.linspace(ring_m, float(spec["spur_to_m"]), max(int(math.ceil(ring_m - float(spec["spur_to_m"]))) + 1, 8))
    spur = np.stack([cx + t * math.sin(b), cz + t * math.cos(b)], axis=1)
    out = []
    for rid, pts, width in (("core:road/%s_street" % short, ring, float(spec["width_m"])),
                            ("core:road/%s_door" % short, spur, float(spec["spur_width_m"]))):
        # level, like every street: laid on the flattened ground of the place itself
        elev = np.full(pts.shape[0], level, dtype=np.float64)
        out.append(Road(id=rid, points=pts, width=width, elevation=elev, ground=elev.copy()))
    return out


def ring_end(road: Road, rings: list) -> Road:
    """A road that comes to a ring town, stopped where it first reaches the town's level ground
    and run from there straight in to the ring's outer edge. Stopped where it first reached the
    ring, the Fernhold road, routed to the centre, came onto Grandfather Hollow's level ground on
    the far side and curled a quarter of the way round the ring 60 m out, through the houses."""
    for pl in rings:
        cx, cz = float(pl["position"][0]), float(pl["position"][1])
        spec = RING_TOWNS[pl["id"]]
        ring_edge = float(spec["ring_m"]) + 0.5 * float(spec["width_m"])
        edge = max(float(spec["flat_m"]), ring_edge)
        for end in (0, -1):
            p = road.points[end]
            if abs(p[0] - cx) >= 1.0 or abs(p[1] - cz) >= 1.0:
                continue
            flip = end == 0                          # walk it with the town at the far end
            pts = road.points[::-1] if flip else road.points
            elev = np.asarray(road.elevation, dtype=np.float64)
            elev = elev[::-1] if flip else elev
            ground = None if road.ground is None else np.asarray(road.ground, dtype=np.float64)
            if ground is not None and flip:
                ground = ground[::-1]
            d = np.hypot(pts[:, 0] - cx, pts[:, 1] - cz)
            inside = np.nonzero(d < edge)[0]
            if inside.size == 0 or inside[0] == 0:
                continue
            k = int(inside[0])                       # the first point inside the edge
            f = (d[k - 1] - edge) / max(d[k - 1] - d[k], 1e-9)

            def cut(v):
                return np.concatenate([v[:k], [v[k - 1] + f * (v[k] - v[k - 1])]])

            pts, elev = cut(pts), cut(elev)
            ground = None if ground is None else cut(ground)
            if edge > ring_edge + 1e-6:
                # on the level ground, straight in to the ring, at the level it came onto it at
                u = (pts[-1] - [cx, cz]) / edge
                steps = np.linspace(edge, ring_edge, max(int(math.ceil((edge - ring_edge) / 6.0)), 1) + 1)[1:]
                pts = np.concatenate([pts, [[cx, cz]] + steps[:, None] * u[None, :]])
                elev = np.concatenate([elev, np.full(steps.size, elev[-1])])
                ground = None if ground is None else np.concatenate([ground, np.full(steps.size, ground[-1])])
            if flip:
                pts, elev = pts[::-1], elev[::-1]
                ground = None if ground is None else ground[::-1]
            road = Road(id=road.id, points=np.ascontiguousarray(pts), width=road.width,
                        elevation=np.ascontiguousarray(elev).astype(np.asarray(road.elevation).dtype),
                        ground=None if ground is None else np.ascontiguousarray(ground))
    return road


def carve_roads(grid: Grid, H: np.ndarray, roads: list, no_fill: np.ndarray | None = None) -> tuple:
    """Cut the graded corridors in. Returns (heights, distance to road centre line, width map).

    Where `no_fill` is set (an authored sightline's corridor) the carve only ever lowers the
    land: a road benched across a slope there is cut in on its uphill side and left on the
    ground on its downhill side, rather than built up into the line.
    """
    n = grid.n
    mask = np.zeros((n, n), dtype=bool)
    elev = np.zeros((n, n), dtype=np.float32)
    wide = np.zeros((n, n), dtype=np.float32)
    # A texel the line crosses takes the level where the line passes nearest its centre, not where
    # it leaves it: up a steep pitch the exit's level stood a texel's run of grade off the road.
    # And the first road laid through a texel keeps it. The roads are laid in order, and a later
    # one that runs along an earlier one takes the earlier one's levels where it is snapped to it
    # (`plan_roads`); where it only runs close beside, it keeps its own. Stamped over the earlier
    # road, the later one's levels won the texels its line happened to cross: on w4096f, where the
    # Chain Bridge-Windgate and Ruddow-Fallen Hand tracks share a zigzag up a 1-in-3 at (668,
    # -3046), the earlier road's carriageway was read 2.5 m off its grade, with a second carve a
    # metre and a half higher beside it.
    for r in roads:
        i, j, v = paths.polyline_texels(r.points, grid, np.asarray(r.elevation, dtype=np.float64), at_centre=True)
        free = ~mask[i, j]
        elev[i[free], j[free]] = v[free]
        wide[i[free], j[free]] = r.width
        mask[i, j] = True
    if not mask.any():
        return H, np.full((n, n), 1e6, dtype=np.float32), wide
    dist_t, (ii, jj) = ndimage.distance_transform_edt(~mask, return_indices=True)
    d = (dist_t * grid.spacing).astype(np.float32)
    near_e = elev[ii, jj]
    near_w = wide[ii, jj]
    del ii, jj, dist_t
    half = near_w * 0.5
    shoulder = np.maximum(near_w * 1.8, 7.0)
    crown = near_e + 0.12 * (1.0 - np.clip(d / np.maximum(half, 0.5), 0.0, 1.0) ** 2)
    w = 1.0 - smoothstep(half, half + shoulder, d)
    Hn = lerp(H, crown, w)
    if no_fill is not None:
        Hn = np.where(no_fill, np.minimum(H, Hn), Hn)
    return Hn.astype(np.float32), d, near_w
