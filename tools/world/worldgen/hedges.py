"""Hedgerows, field walls and orchard rows: the line-work of a farmed country.

`fields.py` divides the downs and the lake shoulder into parcels and hands back how far any
point is from a parcel boundary. Until now nothing stood on those boundaries. The texture
rules painted a strip of rough grass along them and the colour map darkened the line, so the
patchwork could be read from a hilltop -- but walk into it and the downs were open grass with
a few trees on it, which is not what WORLD_BIBLE 6.1 describes and not what the region is
for. DESIGN 4.1's first line is "rolling chalk downs, hedgerows, orchards".

This lays the hedge itself. It is deliberate placement, not scatter: a hedge is a line a
person planted along a boundary, and a density of so many bushes per hectare can only ever
produce a sprinkle near the line. Like `stones.py`, it returns the same bucket shape the
scatter does, so the streamer draws hedges in the same MultiMeshes as everything else and
nothing downstream needs to know they were placed by hand.

What it lays, per boundary:

* a run of `hedge_segment` end to end, each 2.2 m of hedge, turned to lie *along* the
  boundary rather than across it;
* hawthorn every twenty-seven metres and an oak standard every seventy, because a real
  hedge is a line of shrubs with trees grown out of it -- and because those two are the most
  expensive things in the frame, at five and a half thousand triangles each;
* gaps: a gateway every so often (a low-frequency field decides where), a gate post beside
  it, and always a gap where a road crosses, since a hedge laid across the lane is the one
  mistake that would be visible from the road itself;
* Skerrow's boundaries take drystone wall instead of hedge, because that is what the clans
  build and what its identity sheet says.

Orchards are the same idea in two dimensions: inside the parcels around Tamwick, apples in
rows on a lattice turned to the parcel, which is the only place in Wickmere apples grow.
"""
from __future__ import annotations

import math

import numpy as np

from .grid import Grid, sample_bilinear

## What each enclosed landform lines its boundaries with. `line` is the run laid end to end,
## `shrub` and `tree` are what grows out of it and how many metres apart.
KITS = {
    "downs": {
        "line": "props/hedge_segment", "spacing_m": 2.1,
        # A hawthorn is 5 610 triangles and an oak 6 500, so how far apart they stand along
        # the hedge is a budget decision as much as a look one. At one hawthorn every 13 m
        # the Merrowby street had 1 234 of them in the frame and the village went over the
        # primitive budget; at 27 m the hedge still reads as thorn with trees grown out of
        # it, because the run between them is hedge segments at 66 triangles apiece.
        "shrub": ("trees/hawthorn", 27.0),
        "tree": ("trees/oak", 70.0),
        "post": "props/gate_post",
    },
    "lake_basin": {
        "line": "props/hedge_segment", "spacing_m": 2.2,
        "shrub": ("trees/hawthorn", 30.0),
        "tree": ("trees/lime", 80.0),
        "post": "props/gate_post",
    },
    "mountains": {
        # the clans build in stone: drystone walls, no hedge, and no trees above the line
        "line": "props/drystone_wall", "spacing_m": 2.4,
        "shrub": ("flora/juniper", 34.0),
        "tree": None,
        "post": "props/drystone_wall_end",
        # the intakes stop at the fell wall: above it the moor is open, and a wall across the
        # tops would be a wall nobody built
        "max_height_m": 430.0,
    },
}

## How much of the boundary network actually carries a hedge. Not every field edge in a real
## landscape is hedged -- some are open, some are a ditch -- and hedging all of it makes a
## grid rather than a patchwork.
HEDGED_FRACTION = 0.78


def _assets(index: dict, rule_asset: str, region_short: str) -> list:
    """This region's variants of an asset, best match first (the scatter's rule, repeated)."""
    from .cells import assets_for
    return assets_for(index, rule_asset, region_short)


def _hash01(a: np.ndarray, salt: int) -> np.ndarray:
    """A stable 0..1 per integer, for decisions that must not move between builds."""
    h = (a.astype(np.int64) * np.int64(2654435761) + np.int64(salt) * np.int64(40503))
    h ^= h >> np.int64(13)
    h = (h * np.int64(1274126177)) & np.int64(0x7FFFFFFF)
    return (h % np.int64(100003)).astype(np.float32) / 100003.0


def place(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
          road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray, field_labels: np.ndarray,
          field_d: np.ndarray, regions: list, index: dict, bank, seed: int,
          places: list | None = None) -> dict:
    """Returns {(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint], ...]}}."""
    out: dict = {}
    if field_labels is None:
        return out
    n = grid.n
    rng = np.random.default_rng(np.random.SeedSequence([seed, 5150]))

    # The boundary's own direction. `field_d` rises away from the boundary, so its gradient
    # points across the line and the tangent is at right angles to that. Without this every
    # segment would be laid at a random angle and a hedge would read as a row of loose bushes.
    gz, gx = np.gradient(field_d.astype(np.float32), grid.spacing)
    tangent_x, tangent_z = -gz, gx

    # where a gateway falls: a low-frequency field, so gaps are occasional and not periodic
    gate_field = bank.field_at(5151, min(n, 1024), beta=1.7, wl_min=60.0, wl_max=340.0)
    gate_g = grid.with_n(gate_field.shape[0])

    for region in regions:
        kit = KITS.get(region.shape)
        if kit is None:
            continue
        line_assets = _assets(index, kit["line"], region.short)
        if not line_assets:
            continue
        shrub_assets = _assets(index, kit["shrub"][0], region.short) if kit.get("shrub") else []
        tree_assets = _assets(index, kit["tree"][0], region.short) if kit.get("tree") else []
        post_assets = _assets(index, kit["post"], region.short) if kit.get("post") else []

        # A boundary texel: within half a texel of the line, on this region's enclosed ground.
        on_line = (field_d <= grid.spacing * 0.7) & (field_labels >= 0) & (owner == region.index)
        # Nothing is planted in water, on a settlement's platform, down a cliff, or across a
        # road: the lane through a gap in the hedge is a gate, not a hedge.
        clear = (water == 0) & (pad_mask == 0) & (slope < 0.45) \
            & (road_d > road_w * 0.5 + 3.5)
        if "max_height_m" in kit:
            clear &= H < float(kit["max_height_m"])
        idx = np.argwhere(on_line & clear)
        if idx.size == 0:
            continue
        ii, jj = idx[:, 0], idx[:, 1]
        x = (grid.x0 + jj * grid.spacing).astype(np.float32)
        z = (grid.z0 + ii * grid.spacing).astype(np.float32)

        # Which stretches of the network are hedged at all, decided per parcel boundary so a
        # field is hedged on a side or it is not, rather than in and out along one edge.
        keep = _hash01(field_labels[ii, jj], 611) < HEDGED_FRACTION
        # and the gateways
        gate = 0.5 + 0.5 * np.tanh(sample_bilinear(gate_field, gate_g, x, z))
        keep &= gate < 0.86
        if not keep.any():
            continue
        ii, jj, x, z = ii[keep], jj[keep], x[keep], z[keep]

        tx = tangent_x[ii, jj]
        tz = tangent_z[ii, jj]
        norm = np.hypot(tx, tz)
        good = norm > 1e-4
        ii, jj, x, z, tx, tz, norm = ii[good], jj[good], x[good], z[good], tx[good], tz[good], norm[good]
        if x.size == 0:
            continue
        tx, tz = tx / norm, tz / norm
        # The asset's run lies along its own +X. A rotation of `a` about +Y sends +X to
        # (cos a, 0, -sin a), so laying the run along (tx, tz) means a = atan2(-tz, tx).
        yaw = np.degrees(np.arctan2(-tz, tx)).astype(np.float32)

        # Thin the line to the segment's own length. Boundary texels sit two metres apart and
        # a segment is 2.1, so this is close to one for one, with a hash deciding which texel
        # of a diagonal staircase keeps its segment.
        step_keep = _hash01(ii.astype(np.int64) * 8191 + jj.astype(np.int64), 733)
        density = min(grid.spacing / float(kit["spacing_m"]), 1.0)
        take = step_keep < density
        # What grows out of the hedge, spaced along the run rather than chosen per texel: one
        # hawthorn every `shrub_every` metres of boundary, one standard tree every
        # `tree_every`, so a hedge is a line of shrubs with trees grown out of it.
        run_h = _hash01(ii.astype(np.int64) * 131071 + jj.astype(np.int64), 977)
        zeros = np.zeros(run_h.shape, dtype=bool)
        is_shrub = (run_h < grid.spacing / float(kit["shrub"][1])) if shrub_assets else zeros
        is_tree = (run_h > 1.0 - grid.spacing / float(kit["tree"][1])) if tree_assets else zeros
        is_shrub &= ~is_tree

        y_all = H[ii, jj].astype(np.float32)
        jitter = rng.uniform(-0.45, 0.45, x.size).astype(np.float32)
        px, pz = -tz, tx                      # across the line, to wander the run a little
        xs = x + px * jitter
        zs = z + pz * jitter

        for k in range(x.size):
            if is_tree[k]:
                asset = tree_assets[int(rng.integers(0, len(tree_assets)))]
                scale = float(rng.uniform(0.85, 1.25))
                yw = float(rng.uniform(0.0, 360.0))
            elif is_shrub[k]:
                asset = shrub_assets[int(rng.integers(0, len(shrub_assets)))]
                scale = float(rng.uniform(0.8, 1.15))
                yw = float(rng.uniform(0.0, 360.0))
            elif take[k]:
                asset = line_assets[int(rng.integers(0, len(line_assets)))]
                scale = float(rng.uniform(0.88, 1.18))
                # a couple of degrees off true, so the run is not a ruler
                yw = float(yaw[k] + rng.normal(0.0, 3.5))
            else:
                continue
            _put(out, grid, float(xs[k]), float(y_all[k]), float(zs[k]), yw, scale, asset)

        # Gate posts: one beside each gateway, on the boundary, where the run stops.
        if post_assets:
            gaps = np.argwhere(on_line & clear & (owner == region.index))
            if gaps.size:
                gi, gj = gaps[:, 0], gaps[:, 1]
                gx_ = (grid.x0 + gj * grid.spacing).astype(np.float32)
                gz_ = (grid.z0 + gi * grid.spacing).astype(np.float32)
                gval = 0.5 + 0.5 * np.tanh(sample_bilinear(gate_field, gate_g, gx_, gz_))
                # the shoulder of a gap, not the middle of it
                edge = (gval > 0.855) & (gval < 0.872)
                sel = np.argwhere(edge).ravel()
                for k in sel[:: max(1, int(sel.size / 220) if sel.size else 1)]:
                    _put(out, grid, float(gx_[k]), float(H[gi[k], gj[k]]), float(gz_[k]),
                         float(rng.uniform(0.0, 360.0)), float(rng.uniform(0.9, 1.1)),
                         post_assets[int(rng.integers(0, len(post_assets)))])
    return out


## Sedgemire's line-work is the water's, not a farmer's. Its willows were scattered at so many
## a hectare with a pull toward the water, which gives a band of trees about every pool and a
## tree or two out on the peat; what a marsh actually shows from a boardwalk is a line: a
## willow every so often along the edge of every channel, a pace or two back from it, with
## alder among them where the ground is carr, and gaps where the bank is too soft to hold one.
WATERSIDE = {
    "delta": {"trees": ("trees/willow", "trees/alder"), "alder_share": 0.3,
              "every_m": 16.0, "back_m": (4.0, 6.5)},
}


def waterside(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
              water_d: np.ndarray, pad_mask: np.ndarray, road_d: np.ndarray, road_w: np.ndarray,
              regions: list, index: dict, bank, seed: int) -> dict:
    """Lines of trees along the water's edge. Returns the scatter's bucket shape."""
    out: dict = {}
    n = grid.n
    rng = np.random.default_rng(np.random.SeedSequence([seed, 5353]))
    gap_field = bank.field_at(5354, min(n, 1024), beta=1.7, wl_min=80.0, wl_max=400.0)
    gap_g = grid.with_n(gap_field.shape[0])
    for region in regions:
        kit = WATERSIDE.get(region.shape)
        if kit is None:
            continue
        first = _assets(index, kit["trees"][0], region.short)
        second = _assets(index, kit["trees"][1], region.short)
        if not first:
            continue
        lo, hi = kit["back_m"]
        hi = max(hi, lo + 1.5 * grid.spacing)          # a coarse test grid has no texel at 5 m
        on_line = (water_d >= lo) & (water_d < hi) & (owner == region.index) & (water == 0) \
            & (pad_mask == 0) & (slope < 0.35) & (road_d > road_w * 0.5 + 3.0)
        idx = np.argwhere(on_line)
        if idx.size == 0:
            continue
        ii, jj = idx[:, 0], idx[:, 1]
        # a band (hi - lo) m wide holds (hi - lo) / spacing texels across per spacing of line
        p = grid.spacing * grid.spacing / ((hi - lo) * float(kit["every_m"]))
        keep = _hash01(ii.astype(np.int64) * 65599 + jj.astype(np.int64), 919) < p
        x = (grid.x0 + jj * grid.spacing).astype(np.float32)
        z = (grid.z0 + ii * grid.spacing).astype(np.float32)
        gate = 0.5 + 0.5 * np.tanh(sample_bilinear(gap_field, gap_g, x, z))
        keep &= gate < 0.82
        for k in np.flatnonzero(keep):
            use_second = bool(second) and rng.random() < float(kit["alder_share"])
            pool = second if use_second else first
            _put(out, grid, float(x[k] + rng.uniform(-0.6, 0.6)), float(H[ii[k], jj[k]]),
                 float(z[k] + rng.uniform(-0.6, 0.6)), float(rng.uniform(0.0, 360.0)),
                 float(rng.uniform(0.85, 1.15)), pool[int(rng.integers(0, len(pool)))])
    return out


## Cinderlea's walls: the Builders' city shows through the ash as its street grid
## (`landforms.cinderlea`), and along the lip of the sunken streets what is left of the walls
## stands out of the drift -- runs of fused blocks lined up with the street, which is the one
## straight line in the country that nobody alive laid.
RUINS = {"ash_plateau": {"asset": "rocks/fused_block", "every_m": 34.0, "back_m": 9.0,
                         "min_depth_m": 1.2}}


def ruin_lines(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
               pad_mask: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, regions: list,
               index: dict, bank, seed: int) -> dict:
    """Wall stubs along the lips of the Builders' streets. Returns the scatter's bucket shape."""
    from .landforms import GRID_BEARING, GRID_M, STREET_M

    out: dict = {}
    rng = np.random.default_rng(np.random.SeedSequence([seed, 5454]))
    n = grid.n
    th = math.radians(GRID_BEARING)
    ct, st = math.cos(th), math.sin(th)
    run_field = bank.field_at(5455, min(n, 1024), beta=1.7, wl_min=60.0, wl_max=300.0)
    run_g = grid.with_n(run_field.shape[0])
    for region in regions:
        kit = RUINS.get(region.shape)
        if kit is None:
            continue
        assets = _assets(index, kit["asset"], region.short)
        if not assets:
            continue
        mine = np.argwhere(owner == region.index)
        if mine.size == 0:
            continue
        i0, j0 = mine.min(axis=0)
        i1, j1 = mine.max(axis=0) + 1
        X = (grid.x0 + np.arange(j0, j1) * grid.spacing)[None, :]
        Z = (grid.z0 + np.arange(i0, i1) * grid.spacing)[:, None]
        u = X * ct + Z * st
        v = -X * st + Z * ct
        sub = (slice(i0, i1), slice(j0, j1))
        base_ok = (owner[sub] == region.index) & (water[sub] == 0) & (pad_mask[sub] == 0) \
            & (slope[sub] < 0.6) & (road_d[sub] > road_w[sub] * 0.5 + 4.0)
        lip = 0.5 * STREET_M + float(kit["back_m"])
        # streets of constant u run along v, and the other way about
        for coord, period, off, along in ((u, GRID_M[0], 31.0, (-st, ct)), (v, GRID_M[1], 17.0, (ct, st))):
            rel = ((coord + off + 0.5 * period) % period) - 0.5 * period      # signed, from the street
            on_line = base_ok & (np.abs(np.abs(rel) - lip) < 0.8 * grid.spacing)
            idx = np.argwhere(on_line)
            if idx.size == 0:
                continue
            ii, jj = idx[:, 0] + i0, idx[:, 1] + j0
            p = grid.spacing / float(kit["every_m"]) * 0.6
            keep = _hash01(ii.astype(np.int64) * 131 + jj.astype(np.int64) * 7919, 1201) < p
            x = (grid.x0 + jj * grid.spacing).astype(np.float64)
            z = (grid.z0 + ii * grid.spacing).astype(np.float64)
            run = 0.5 + 0.5 * np.tanh(sample_bilinear(run_field, run_g, x, z))
            keep &= run > 0.45
            # only where the street is actually sunk into the land here: the city is not
            # everywhere, and the places stand on ground the grid was kept off
            r_sel = rel[idx[:, 0], idx[:, 1]]
            axis = (ct, st) if coord is u else (-st, ct)
            cx = x - axis[0] * r_sel
            cz = z - axis[1] * r_sel
            cj = np.clip(np.rint((cx - grid.x0) / grid.spacing).astype(np.int64), 0, n - 1)
            ci = np.clip(np.rint((cz - grid.z0) / grid.spacing).astype(np.int64), 0, n - 1)
            keep &= (H[ii, jj] - H[ci, cj]) > float(kit["min_depth_m"])
            yaw_along = math.degrees(math.atan2(-along[1], along[0]))
            for k in np.flatnonzero(keep):
                _put(out, grid, float(x[k]), float(H[ii[k], jj[k]]) - 0.3, float(z[k]),
                     yaw_along + float(rng.normal(0.0, 6.0)), float(rng.uniform(0.34, 0.6)),
                     assets[int(rng.integers(0, len(assets)))])
    return out


def orchards(grid: Grid, H: np.ndarray, owner: np.ndarray, slope: np.ndarray, water: np.ndarray,
             pad_mask: np.ndarray, field_labels: np.ndarray, field_d: np.ndarray, regions: list,
             places: list, index: dict, seed: int, around=("tamwick",),
             radius_m: float = 210.0, row_m: float = 9.0, tree_m: float = 7.0) -> dict:
    """Apple rows inside the enclosures around the cider villages.

    An orchard is the one planting in the world that is unmistakably deliberate: trees in
    rows, all of one kind, inside a wall. The rows follow each parcel's own turning so two
    neighbouring orchards do not line up, and they stop at the hedge.

    Tamwick only. WORLD_BIBLE 6.1 gives Hearthvale the only apple trees in Wickmere and
    Tamwick the only cider press, and planting Merrowby's enclosures too put 645 apple trees
    at 5 718 triangles each into the village street frame -- most of the primitive budget,
    spent on an orchard the bible does not place there.
    """
    out: dict = {}
    if field_labels is None or not places:
        return out
    rng = np.random.default_rng(np.random.SeedSequence([seed, 5252]))
    centres = [(float(p["position"][0]), float(p["position"][1]))
               for p in places if p["id"].split("/")[-1] in around]
    if not centres:
        return out
    downs = next((r for r in regions if r.shape == "downs"), None)
    if downs is None:
        return out
    apples = _assets(index, "trees/apple", downs.short)
    if not apples:
        return out
    n = grid.n
    for (cx, cz) in centres:
        j0, i0 = grid.to_tex(np.array([cx - radius_m]), np.array([cz - radius_m]))
        j1, i1 = grid.to_tex(np.array([cx + radius_m]), np.array([cz + radius_m]))
        i0 = int(max(0, i0[0])); j0 = int(max(0, j0[0]))
        i1 = int(min(n - 1, i1[0])); j1 = int(min(n - 1, j1[0]))
        labels = field_labels[i0:i1, j0:j1]
        parcels = [int(v) for v in np.unique(labels) if v >= 0]
        for pid in parcels[:6]:
            sel = np.argwhere(labels == pid)
            if sel.shape[0] < 400:
                continue
            ci = i0 + float(sel[:, 0].mean())
            cj = j0 + float(sel[:, 1].mean())
            ox = grid.x0 + cj * grid.spacing
            oz = grid.z0 + ci * grid.spacing
            if math.hypot(ox - cx, oz - cz) > radius_m:
                continue
            # every orchard turns its own way, off the parcel's index
            ang = float(_hash01(np.array([pid]), 313)[0]) * math.pi
            ux, uz = math.cos(ang), math.sin(ang)
            vx, vz = -uz, ux
            half = radius_m * 0.5
            rows = int(half / row_m)
            for a in range(-rows, rows + 1):
                cols = int(half / tree_m)
                for b in range(-cols, cols + 1):
                    px = ox + ux * (a * row_m) + vx * (b * tree_m)
                    pz = oz + uz * (a * row_m) + vz * (b * tree_m)
                    jj, iiy = grid.to_tex(np.array([px]), np.array([pz]))
                    jj, iiy = grid.clamp_index(jj, iiy)
                    jj, iiy = int(jj[0]), int(iiy[0])
                    if field_labels[iiy, jj] != pid:
                        continue                      # outside this parcel
                    if field_d[iiy, jj] < 4.0:
                        continue                      # leave the headland at the hedge
                    if water[iiy, jj] or pad_mask[iiy, jj] or slope[iiy, jj] > 0.32:
                        continue
                    _put(out, grid, px + float(rng.normal(0.0, 0.35)), float(H[iiy, jj]),
                         pz + float(rng.normal(0.0, 0.35)),
                         float(rng.uniform(0.0, 360.0)), float(rng.uniform(0.9, 1.12)),
                         apples[int(rng.integers(0, len(apples)))])
    return out


def _put(out: dict, grid: Grid, x: float, y: float, z: float, yaw: float, scale: float,
         asset: str, tint: str = "#ffffff") -> None:
    cx, cz = grid.cell_of(np.array([x], dtype=np.float32), np.array([z], dtype=np.float32))
    key = (int(np.clip(cx[0], 0, grid.cells - 1)), int(np.clip(cz[0], 0, grid.cells - 1)))
    out.setdefault(key, {}).setdefault(asset, []).append(
        [round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), round(scale, 3), tint])
