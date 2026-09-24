"""Crags: rock set into the steep faces, and outcrops on the edges and crests.

A heightmap cannot hold a crag. A face steeper than about 35 degrees is a handful of texels
stretched over a long drop, and the ground texture on it smears down the slope; from the dale
floor the Skerrow's walls read as grey rubber, not as rock. So the steep faces are dressed with
the forge's own cliff pieces -- each region's cliff slabs (limestone in the Skerrow, granite in
the Briarwold, chalk on the Hearthvale's brow, lake stone round Brightwater) and Cinderlea's
basalt columns -- and the convex edges and crests with its boulders:

* A face piece stands on the face with its front along the face's normal, looking out downhill
  (`yaw`), leaned back into the hill by FACE_LEAN_SHARE of the way from upright to lying along
  the face (`lean`, `lean_toward`: CONTRACTS 6's scatter row), and pushed into the ground along
  the normal by FACE_EMBED of its depth, so its back and sides are buried and only its face
  stands proud.
* It is sized to the face: its height along the slope is about the face's own extent across the
  steep ground (FACE_FIT), between FACE_SCALE.
* An outcrop stands upright on a convex edge or a crest (the ground standing CREST_TPI_M or more
  over its surroundings), sunk CREST_EMBED of its height.
* Nothing is set within the road's carve and a margin, on a pad, or in or beside water; and in
  an authored sightline's corridor nothing stands within the game's clearance of the ray
  (`ceiling_under_lines`).

The pieces go into the cells' scatter buckets, so the streamer draws them in the same MultiMesh
per asset per cell as everything else: two face pieces and two outcrops a region at the most
(FACE_VARIANTS, CREST_VARIANTS), which is at most four more draws a cell.
"""
from __future__ import annotations

import math

import numpy as np
from scipy import ndimage

from .grid import Grid, sample_bilinear, sample_nearest, smoothstep

## the slope (rise over run) a face must have: 35 degrees
FACE_SLOPE = math.tan(math.radians(35.0))
## face pieces a hectare of face ground, and the share of candidates a low-frequency field lets
## through (so a face has crags and runs of bare scree between them, not an even stipple)
FACE_DENSITY_HA = 40.0
FACE_CLUSTER = 0.55
## how far from upright toward lying along the face a piece leans back, and how deep into the
## ground along the normal it sits, as a share of its depth
FACE_LEAN_SHARE = 0.7
FACE_EMBED = 0.45
## its height along the slope against the face's extent across the steep ground
FACE_FIT = 1.0
FACE_SCALE = (0.7, 3.0)
FACE_VARIANTS = 2
## outcrops a hectare of crest, what counts as a crest, and how far one sinks
CREST_DENSITY_HA = 10.0
CREST_TPI_M = 2.5
CREST_SLOPE = (0.18, 1.2)
CREST_EMBED = 0.3
CREST_SCALE = (1.0, 2.2)
CREST_VARIANTS = 2
## how far clear of a road's carriageway, water and a sightline's line the rock keeps
ROAD_CLEAR_M = 10.0
WATER_CLEAR_M = 8.0
SIGHTLINE_CORRIDOR_M = 30.0
SIGHTLINE_SPARE_M = 1.0

## which forge piece dresses each kind of province's faces, and its crests
FACE_PIECE = {
    "mountains": "rocks/cliff_slab",       # the Skerrow's limestone
    "forest_rise": "rocks/cliff_slab",     # the Briarwold's granite
    "ash_plateau": "rocks/basalt_columns", # Cinderlea's old lava
    "downs": "rocks/cliff_slab",           # the Hearthvale's chalk, on its brow
    "lake_basin": "rocks/cliff_slab",      # Brightwater's lake stone
}
CREST_PIECE = {k: "rocks/boulder" for k in FACE_PIECE}


def piece_size(asset: str, repo_root: str) -> tuple:
    """(height, depth to its front face) in metres, off the forge's meta for `asset` (a res://
    path), or a cliff slab's when it has none."""
    import json
    import os

    rel = asset.replace("res://", "game/", 1)
    meta = os.path.join(repo_root, os.path.splitext(rel)[0] + ".meta.json")
    try:
        with open(meta, "r", encoding="utf-8") as f:
            b = json.load(f)["bounds"]
        return float(b["max"][1] - b["min"][1]), float(b["max"][2])
    except (OSError, KeyError, ValueError):
        return 6.4, 1.8


def _candidates(rng, box, spacing):
    x0, x1, z0, z1 = box
    j0, j1 = int(np.floor(x0 / spacing)), int(np.ceil(x1 / spacing))
    i0, i1 = int(np.floor(z0 / spacing)), int(np.ceil(z1 / spacing))
    gx, gz = np.meshgrid((np.arange(j0, j1) + 0.5) * spacing, (np.arange(i0, i1) + 0.5) * spacing, indexing="xy")
    jit = 0.5 * spacing
    x = (gx + rng.uniform(-jit, jit, gx.shape)).ravel()
    z = (gz + rng.uniform(-jit, jit, gz.shape)).ravel()
    return x, z


def ceiling_under_lines(H: np.ndarray, g: Grid, x: np.ndarray, z: np.ndarray, claims: list, k: dict) -> np.ndarray:
    """The highest a rock may stand at each (x, z): under every authored sightline whose corridor
    it is in, the game's clearance under the ray (tools/sightlines.py's model: an eye EYE_M over
    the vantage, a point LANDMARK_M over the target, the first FOREGROUND_M not looked at), and
    anywhere else no limit. Barring the whole corridor left a 60 m strip of bare wall up the gorge
    below Kharrow Force, which the line from Kharrow Hold runs straight up."""
    out = np.full(x.shape, np.inf)
    for (ax, az), (bx, bz), kind, _ra, _rb in claims:
        dx, dz = bx - ax, bz - az
        ln = math.hypot(dx, dz)
        if ln < 1.0 or ln > k["MAX_SIGHT_M"]:
            continue
        t = np.clip(((x - ax) * dx + (z - az) * dz) / (ln * ln), 0.0, 1.0)
        d = np.hypot(x - (ax + t * dx), z - (az + t * dz))
        near = (d < SIGHTLINE_CORRIDOR_M) & (t * ln > k["FOREGROUND_M"])
        if not near.any():
            continue
        eye = float(sample_bilinear(H, g, np.array([ax]), np.array([az]))[0]) + k["EYE_M"]
        top = float(sample_bilinear(H, g, np.array([bx]), np.array([bz]))[0]) \
            + k["LANDMARK_M"].get(kind, k["LANDMARK_DEFAULT_M"])
        line = eye + (top - eye) * t - k["CLEARANCE_M"] - SIGHTLINE_SPARE_M
        out = np.where(near, np.minimum(out, line), out)
    return out


def place(grid: Grid, H: np.ndarray, owner: np.ndarray, water: np.ndarray, water_d: np.ndarray,
          road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray, regions: list, claims: list,
          sight_k: dict, index: dict, bank, seed: int, repo_root: str = ".") -> tuple:
    """Returns ({(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint, lean, lean_toward], ...]}},
    counts by kind)."""
    from . import cells as CELLS

    g = grid
    gz, gx = np.gradient(H.astype(np.float32), g.spacing)
    slope = np.hypot(gx, gz)
    steep = slope >= FACE_SLOPE
    # how far into the steep ground each texel lies, metres: half the face's extent across it
    inside = ndimage.distance_transform_edt(steep) * g.spacing
    tpi = CELLS.topographic_position(H, g.spacing, radius_m=40.0)
    boxes = CELLS._boxes(type("W", (), {"grid": g, "owner": owner})(), regions)
    out: dict = {}
    counts = {"face": 0, "crest": 0}

    def clear(x, z):
        ok = sample_nearest(water, g, x, z) == 0
        ok &= sample_bilinear(water_d, g, x, z) > WATER_CLEAR_M
        ok &= sample_nearest(road_d, g, x, z) > sample_nearest(road_w, g, x, z) * 0.5 + ROAD_CLEAR_M
        ok &= sample_nearest(pad_mask.astype(np.uint8), g, x, z) == 0
        return ok

    def put(asset, x, y, z, yaw, scale, lean, toward, tint):
        cx, cz = g.cell_of(np.array([x]), np.array([z]))
        key = (int(np.clip(cx[0], 0, g.cells - 1)), int(np.clip(cz[0], 0, g.cells - 1)))
        row = [round(float(x), 2), round(float(y), 2), round(float(z), 2), round(float(yaw), 1),
               round(float(scale), 3), tint, round(float(lean), 1), round(float(toward), 1)]
        out.setdefault(key, {}).setdefault(asset, []).append(row)

    for n, region in enumerate(regions):
        face_piece = FACE_PIECE.get(region.shape)
        if face_piece is None or region.index not in boxes:
            continue
        faces = CELLS.assets_for(index, face_piece, region.art_short)[:FACE_VARIANTS]
        crests = CELLS.assets_for(index, CREST_PIECE[region.shape], region.art_short)[:CREST_VARIANTS]
        rng = np.random.default_rng(np.random.SeedSequence([seed, 7700 + n]))
        cluster = bank.field_at(7800 + n, min(g.n, 1024), beta=1.8, wl_min=60.0, wl_max=400.0)
        g2 = g.with_n(cluster.shape[0])
        # --- the faces
        if faces:
            x, z = _candidates(rng, boxes[region.index], math.sqrt(10000.0 / FACE_DENSITY_HA))
            draw = rng.random(x.shape)
            sx = sample_bilinear(gx, g, x, z)
            sz = sample_bilinear(gz, g, x, z)
            s = np.hypot(sx, sz)
            gate = 0.5 + 0.5 * np.tanh(sample_bilinear(cluster, g2, x, z))
            keep = (sample_nearest(owner, g, x, z) == region.index) & (s >= FACE_SLOPE) \
                & (draw < smoothstep(1.0 - FACE_CLUSTER - 0.1, 1.0 - FACE_CLUSTER + 0.1, gate))
            idx = np.flatnonzero(keep)
            idx = idx[clear(x[idx], z[idx])]
            pick = rng.integers(0, len(faces), idx.size)
            jitter = rng.uniform(0.85, 1.15, idx.size)
            light = rng.normal(0.0, 0.05, idx.size)
            sizes = [piece_size(a, repo_root) for a in faces]
            ceiling = ceiling_under_lines(H, g, x[idx], z[idx], claims, sight_k)
            for t, k in enumerate(idx):
                xx, zz, ss = float(x[k]), float(z[k]), float(s[k])
                ux, uz = float(sx[k]) / ss, float(sz[k]) / ss          # uphill, unit
                theta = math.atan(ss)
                ph, pdepth = sizes[int(pick[t])]
                reach = 2.0 * float(sample_bilinear(inside, g, np.array([xx]), np.array([zz]))[0]) + g.spacing
                scale = float(np.clip(FACE_FIT * reach / ph * jitter[t], *FACE_SCALE))
                # up the normal: (-sx, 1, -sz) / |.|
                nl = math.sqrt(ss * ss + 1.0)
                nx, ny, nz = -float(sx[k]) / nl, 1.0 / nl, -float(sz[k]) / nl
                sink = FACE_EMBED * pdepth * scale
                y = float(sample_bilinear(H, g, np.array([xx]), np.array([zz]))[0])
                px, py, pz = xx - nx * sink, y - ny * sink, zz - nz * sink
                if y + ph * scale > ceiling[t]:
                    continue                                              # it would stand in a sightline
                yaw = math.degrees(math.atan2(-ux, -uz))                  # its front looks downhill
                lean = FACE_LEAN_SHARE * (90.0 - math.degrees(theta))
                toward = math.degrees(math.atan2(uz, ux))                 # its top leans uphill
                c = int(round(255 * min(1.0, max(0.7, 1.0 + light[t]))))
                put(faces[int(pick[t])], px, py, pz, yaw, scale, lean, toward, "#%02x%02x%02x" % (c, c, c))
                counts["face"] += 1
        # --- the crests and convex edges
        if crests:
            x, z = _candidates(rng, boxes[region.index], math.sqrt(10000.0 / CREST_DENSITY_HA))
            draw = rng.random(x.shape)
            s = np.hypot(sample_bilinear(gx, g, x, z), sample_bilinear(gz, g, x, z))
            t_ = sample_bilinear(tpi, g, x, z)
            keep = (sample_nearest(owner, g, x, z) == region.index) & (t_ >= CREST_TPI_M) \
                & (s >= CREST_SLOPE[0]) & (s <= CREST_SLOPE[1]) & (draw < 0.8)
            idx = np.flatnonzero(keep)
            idx = idx[clear(x[idx], z[idx])]
            pick = rng.integers(0, len(crests), idx.size)
            scale = rng.uniform(*CREST_SCALE, idx.size)
            yaw = rng.uniform(0.0, 360.0, idx.size)
            sizes = [piece_size(a, repo_root) for a in crests]
            ceiling = ceiling_under_lines(H, g, x[idx], z[idx], claims, sight_k)
            for t, k in enumerate(idx):
                ph = sizes[int(pick[t])][0]
                ground = float(sample_bilinear(H, g, np.array([x[k]]), np.array([z[k]]))[0])
                if ground + (1.0 - CREST_EMBED) * ph * scale[t] > ceiling[t]:
                    continue
                y = ground - CREST_EMBED * ph * scale[t]
                put(crests[int(pick[t])], x[k], y, z[k], yaw[t], scale[t], 0.0, 0.0, "#ffffff")
                counts["crest"] += 1
    return out, counts
