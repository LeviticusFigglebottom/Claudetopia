"""The shores: the land where it meets the sea and the lakes.

The atlas draws the coast as a line and says where it is cliff; everything between is a beach
brought down to the water over `beach_m` (geography.apply_coast). This module gives the coast
its kinds and shapes them at full resolution, after everything else is laid:

* **classes.** Every stretch of shore is one of SAND, SHINGLE, ROCK, CLIFF, MUD or REEDS. On the
  sea it is planned from the atlas (a cliff path, the landform behind the shore, and whether the
  shore is a bay, a straight or a headland); on the lakes and the rivers it is read from the land
  as built (how steep the bank, which way the lake's reed shore faces). `classify` writes it on a
  1024 lattice, with the signed distance to the water's edge, for the textures, the scatter and
  the water (`runtime/shore_1024.u8`, CONTRACTS 6).
* **the sea's shores** (`shape`). A sandy bay has a shallow foreshore and dunes behind it; a
  shingle beach a storm berm; a rocky shore a ledge and a platform of rock out into the water,
  with skerries off it; a cliff a wave-cut platform at its foot where the sea has one, sea stacks
  off it, and here and there a cove cut back into it with a beach at its head. An authored pad at
  a cliff's foot (the Tide Mouth) gets a shelf of rock at its level out into the water.
* **the marsh** (`marsh`). A delta province's low ground is cut by creeks and pitted with pools,
  which fill from its water table (hydro.marsh_table).

Everything here keeps off the pads, the roads, the rivers and the authored sightlines: it runs
last, and none of those may move under it.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage

from .grid import Grid, lerp, sample_bilinear, smoothstep
from .noise import ridged

NONE, SAND, SHINGLE, ROCK, CLIFF, MUD, REEDS = 0, 1, 2, 3, 4, 5, 6
CLASS_NAMES = {NONE: "none", SAND: "sand", SHINGLE: "shingle", ROCK: "rock", CLIFF: "cliff",
               MUD: "mud", REEDS: "reeds"}
CLASS_OF = {v: k for k, v in CLASS_NAMES.items()}

SEA_LEVEL = 0.0
## the lattice the shore is planned and classed on (8 m at 1024)
PLAN_N = 1024
## how far either side of the sea's coastline the shore is shaped
BAND_M = 260.0
## A cliff path counts where it stands within this of the coast (geography.CLIFF_REACH_M reach)
CLIFF_W_AT = 0.5

# --- the sea's shores --------------------------------------------------------------------------
## a bay, a straight and a headland, by how much of a 200 m disc round a point of the coast is land
BAY_LAND, HEAD_LAND = 0.56, 0.44
## how wide the wave-cut platform at a cliff's foot is, where it has one (m); under PLATFORM_NONE
## of its noise the cliff goes straight down into deep water
PLATFORM_M = (14.0, 62.0)
PLATFORM_NONE = -0.45
## the platform's rock: how high it stands over the sea at the cliff's foot, how much its ridges
## vary that, and how deep its pools are
PLATFORM_TOP_M = 0.45
PLATFORM_RIDGE_M = 0.6
PLATFORM_POOL_M = 0.9
## how far out the rock of a rocky shore runs, and its ledge on the land (m)
ROCK_PLATFORM_M = (10.0, 36.0)
ROCK_LEDGE_M = (0.8, 1.8)
## a sandy foreshore: how far out it runs (m) and how deep it is there
FORESHORE_M = 110.0
FORESHORE_DEEP_M = 2.8
## dunes behind a sandy bay: how deep the dune belt is (m), how high a dune (m), and the ground
## they rise on (none past DUNE_ON_M above the sea)
DUNE_BELT_M = (90.0, 190.0)
DUNE_M = (2.0, 6.5)
DUNE_ON_M = 16.0
## a shingle beach's storm berm: how far up the beach and how high (m)
BERM_AT_M, BERM_M = 10.0, 1.4
## tidal mud off a marsh: how far out it runs, and how deep it is there
MUDFLAT_M, MUDFLAT_DEEP_M = 180.0, 1.4
## how far one kind of shore blends into the next (m): measured to the nearest coastline alone, the
## seams between two kinds run straight out to sea and the shallows came in rectangles
SOFT_M = 45.0

# --- coves, stacks and skerries ----------------------------------------------------------------
## metres of cliff between one cove and the next, and a cove's radius
COVE_EVERY_M = (800.0, 1500.0)
COVE_R_M = (48.0, 95.0)
## no cove is cut where the land round it stands higher than this (m): into a mountain it is a
## slot, not a cove
COVE_MAX_LAND_M = 200.0
## how far a cove keeps off a pad, a road and the end of its cliff (m)
COVE_CLEAR_M = 90.0
COVE_ROAD_CLEAR_M = 60.0
## stacks: metres of cliff between one group and the next, how many in a group, radius, and height
## as a share of the cliff's
STACK_EVERY_M = (650.0, 1300.0)
STACK_COUNT = (1, 3)
STACK_R_M = (7.0, 16.0)
STACK_H = (0.35, 0.8)
## skerries: metres of rocky shore between one cluster and the next, how many in a cluster, their
## radius and how high they stand out of the water
SKERRY_EVERY_M = (220.0, 480.0)
SKERRY_COUNT = (3, 9)
SKERRY_R_M = (3.0, 10.0)
SKERRY_TOP_M = (0.3, 2.4)
SKERRY_OUT_M = (12.0, 140.0)
## what everything here keeps clear of: a pad's reach and a road's carve (m)
PAD_CLEAR_M = 6.0
ROAD_CLEAR_M = 6.0
## an authored pad this low, within this of a cliff, gets a shelf out into the water
SHELF_PAD_MAX_M = 8.0
SHELF_PAD_NEAR_M = 60.0

# --- the marsh ---------------------------------------------------------------------------------
## creeks: half-width (m) and how far under the water table their beds lie
CREEK_HALF_M = (1.2, 3.4)
CREEK_BED_M = 0.7
## pools: the share of the marsh's lowest ground pitted, and how far under the table
POOL_T = 1.25
POOL_BED_M = 0.6
## the marsh ground cut: under the water table plus this
MARSH_LOW_M = 1.2
## how far in from the sea the marsh's creeks and pools begin (m): the islets and the strand
## out there are the tide-flats'
MARSH_SEA_M = 60.0

## Full-resolution work is done a tile at a time, so a 4096 build holds a few megabytes of it
TILE = 512


@dataclass
class ShorePlan:
    """The sea's shores as planned from the atlas, on the PLAN_N lattice."""
    gp: Grid
    sd: np.ndarray               # metres to the coastline, negative on the land
    cls: np.ndarray              # u8 class of the nearest coastline, 0 past BAND_M
    cliff_h: np.ndarray          # the cliff's height where the coast is cliff, else 0
    plat: np.ndarray             # metres of wave-cut platform or rock out from the coast
    dune: np.ndarray             # metres of dune belt behind a sandy shore
    w: dict = field(default_factory=dict)          # {class: 0..1}, each class's share, softened
    coves: list = field(default_factory=list)      # dicts: x, z, r, cls, nx, nz, cliff
    stacks: list = field(default_factory=list)     # dicts: x, z, r, top
    skerries: list = field(default_factory=list)   # dicts: x, z, r, top
    shelves: list = field(default_factory=list)    # dicts: x, z, r, level, nx, nz
    counts: dict = field(default_factory=dict)


def _noise(bank, salt: int, wl_min: float, wl_max: float, beta: float = 1.8) -> np.ndarray:
    """A unit field on the PLAN_N lattice (kept at that size: sampled bilinearly where needed)."""
    return bank.field_at(salt, min(PLAN_N, bank.grid.n), beta=beta, wl_min=wl_min, wl_max=wl_max)


def _near(points: list, x: float, z: float, r: float) -> bool:
    return any((px - x) ** 2 + (pz - z) ** 2 < (pr + r) ** 2 for (px, pz, pr) in points)


def plan(grid: Grid, atlas: dict, bank, rf, regions: list, seed: int, keep_discs=(),
         road_d: np.ndarray | None = None, road_w: np.ndarray | None = None,
         sight: np.ndarray | None = None, H: np.ndarray | None = None) -> ShorePlan:
    """The sea's shores: each stretch's class, a cliff's platform, a sandy bay's dunes, and where
    the coves, the stacks and the skerries are. `keep_discs` [(x, z, r)] are the pads, `road_d` /
    `road_w` the roads (full grid), `sight` the authored sightlines' corridors (bool, full grid)."""
    from . import geography as GEO
    gp = grid.with_n(min(PLAN_N, grid.n))
    sp = gp.spacing
    land = GEO.land_mask(gp, atlas)
    sd = GEO.signed_distance(gp, land)
    n = gp.n
    rng = np.random.default_rng([int(seed), 7707])
    # the coastline: land texels with the sea beside them (not the world's edge)
    sea = ~land
    coast = land & ndimage.binary_dilation(sea, structure=np.ones((3, 3), dtype=bool))
    # the cliffs, as apply_coast stands them
    cliff_w = np.zeros((n, n), dtype=np.float32)
    cliff_h = np.zeros((n, n), dtype=np.float32)
    for cl in atlas["coast"].get("cliffs", []):
        lf = GEO.line_field(gp, cl["path"], GEO.CLIFF_REACH_M * 2.0)
        i0, i1, j0, j1 = lf.window
        w = 1.0 - smoothstep(GEO.CLIFF_REACH_M * 0.6, GEO.CLIFF_REACH_M * 1.6, lf.d)
        cliff_w[i0:i1, j0:j1] = np.maximum(cliff_w[i0:i1, j0:j1], w)
        cliff_h[i0:i1, j0:j1] = np.where(w > 0.3, np.maximum(cliff_h[i0:i1, j0:j1], float(cl["height_m"])),
                                         cliff_h[i0:i1, j0:j1])
    # an authored shelf (the Hushline's) is rock at its own height, and is left as it is drawn
    shelf = np.zeros((n, n), dtype=bool)
    for s in atlas["coast"].get("shelves", []):
        shelf |= GEO.polygon_mask(gp, s["polygon"])
    shelf = ndimage.binary_dilation(shelf, iterations=max(1, int(40.0 / sp)))
    # the landform behind the shore
    owner = rf.owner_at(n)
    shape_of = np.full(max([r.index for r in regions] + [0]) + 2, "none", dtype=object)
    for r in regions:
        shape_of[r.index] = r.shape
    shape = shape_of[np.clip(owner, 0, shape_of.size - 1)].astype(str)
    # a bay, a straight or a headland
    fill = ndimage.gaussian_filter(land.astype(np.float32), sigma=110.0 / sp)
    v = np.tanh(_noise(bank, 7711, 500.0, 1600.0))
    v2 = np.tanh(_noise(bank, 7712, 300.0, 1100.0))
    bay = fill > BAY_LAND + 0.08 * v
    head = fill < HEAD_LAND + 0.08 * v
    cls = np.zeros((n, n), dtype=np.uint8)
    lowland = np.isin(shape, ["downs", "lake_basin", "forest_rise", "ash_plateau"])
    cls[coast & lowland] = SHINGLE
    cls[coast & lowland & (bay | (v > 0.35))] = SAND
    cls[coast & lowland & head & (v < 0.5)] = ROCK
    cls[coast & (shape == "mountains")] = ROCK
    cls[coast & (shape == "mountains") & bay & (v > -0.2)] = SHINGLE
    cls[coast & (shape == "delta")] = MUD
    cls[coast & (shape == "delta") & (v > 0.55) & ~bay] = SAND
    cls[coast & (cliff_w > CLIFF_W_AT)] = CLIFF
    cls[coast & shelf] = ROCK
    # how wide the rock runs out: a cliff's platform where it has one, a rocky shore's reef
    t = 0.5 + 0.5 * v2
    plat = np.where(v2 < PLATFORM_NONE, 0.0, PLATFORM_M[0] + (PLATFORM_M[1] - PLATFORM_M[0]) * t)
    plat = np.where(cls == ROCK, ROCK_PLATFORM_M[0] + (ROCK_PLATFORM_M[1] - ROCK_PLATFORM_M[0]) * t, plat)
    plat = np.where((cls == CLIFF) | (cls == ROCK), plat, 0.0).astype(np.float32)
    dune = np.where(cls == SAND, DUNE_BELT_M[0] + (DUNE_BELT_M[1] - DUNE_BELT_M[0]) * (0.5 + 0.5 * v), 0.0)
    dune = dune.astype(np.float32)

    def pad_ok(x, z, r):
        return not _near([(float(d[0]), float(d[1]), float(d[2]) + COVE_CLEAR_M * 0.5) for d in keep_discs], x, z, r)

    def road_ok(x, z, r):
        if road_d is None:
            return True
        k = max(int(r / grid.spacing), 1)
        j, i = grid.to_tex(np.array([x]), np.array([z]))
        j, i = grid.clamp_index(j, i)
        i0, i1 = max(int(i[0]) - k, 0), min(int(i[0]) + k + 1, grid.n)
        j0, j1 = max(int(j[0]) - k, 0), min(int(j[0]) + k + 1, grid.n)
        clear = road_d[i0:i1, j0:j1] - (road_w[i0:i1, j0:j1] * 0.5 if road_w is not None else 0.0)
        return bool((clear > COVE_ROAD_CLEAR_M * 0.25).all())

    def sight_ok(x, z, r):
        if sight is None:
            return True
        k = max(int(r / grid.spacing), 1)
        j, i = grid.to_tex(np.array([x]), np.array([z]))
        j, i = grid.clamp_index(j, i)
        return not sight[max(int(i[0]) - k, 0):int(i[0]) + k + 1, max(int(j[0]) - k, 0):int(j[0]) + k + 1].any()

    gz, gx = np.gradient(ndimage.gaussian_filter(sd, 3.0))

    def land_top(x, z, r):
        """The highest land within r of (x, z), or 0 without heights."""
        if H is None:
            return 0.0
        k = max(int(r / grid.spacing), 1)
        j, i = grid.to_tex(np.array([x]), np.array([z]))
        j, i = grid.clamp_index(j, i)
        return float(H[max(int(i[0]) - k, 0):int(i[0]) + k + 1, max(int(j[0]) - k, 0):int(j[0]) + k + 1].max())

    def normal_at(x, z):
        j, i = gp.to_tex(np.array([x]), np.array([z]))
        j, i = gp.clamp_index(j, i)
        a, b = float(gx[int(i[0]), int(j[0])]), float(gz[int(i[0]), int(j[0])])
        m = max(math.hypot(a, b), 1e-6)
        return a / m, b / m                      # seaward

    # nothing is set within a few texels of the world's edge
    lim = grid.size_m * 0.5 - 16.0
    # coves and stacks along each cliff path
    coves, stacks, skerries = [], [], []
    for k, cl in enumerate(atlas["coast"].get("cliffs", [])):
        hgt = float(cl["height_m"])
        if hgt < 10.0:
            continue
        pts = GEO.resample_path(cl["path"], 10.0)
        seg = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
        length = float(seg[-1])
        s = float(rng.uniform(0.3, 1.0)) * COVE_EVERY_M[0]
        while s < length - COVE_CLEAR_M:
            if s > COVE_CLEAR_M:
                x, z = float(np.interp(s, seg, pts[:, 0])), float(np.interp(s, seg, pts[:, 1]))
                r = float(rng.uniform(*COVE_R_M))
                top = land_top(x, z, r + 30.0)
                if abs(x) < lim and abs(z) < lim and pad_ok(x, z, r) and road_ok(x, z, r + COVE_ROAD_CLEAR_M) \
                        and sight_ok(x, z, r + 20.0) and top < COVE_MAX_LAND_M:
                    nx, nz = normal_at(x, z)
                    coves.append({"x": x, "z": z, "r": r, "cls": SAND if rng.random() < 0.6 else SHINGLE,
                                  "nx": nx, "nz": nz, "cliff": max(hgt, top)})
            s += float(rng.uniform(*COVE_EVERY_M))
        s = float(rng.uniform(0.2, 1.0)) * STACK_EVERY_M[0]
        while s < length:
            x, z = float(np.interp(s, seg, pts[:, 0])), float(np.interp(s, seg, pts[:, 1]))
            nx, nz = normal_at(x, z)
            for _ in range(int(rng.integers(STACK_COUNT[0], STACK_COUNT[1] + 1))):
                out = float(rng.uniform(22.0, 90.0))
                along = float(rng.uniform(-60.0, 60.0))
                sx, sz = x + nx * out - nz * along, z + nz * out + nx * along
                r = float(rng.uniform(*STACK_R_M))
                if abs(sx) > lim or abs(sz) > lim:
                    continue
                if not pad_ok(sx, sz, r + 80.0) or not sight_ok(sx, sz, r + 10.0):
                    continue
                if _near([(c["x"], c["z"], c["r"]) for c in coves], sx, sz, r + 40.0):
                    continue
                stacks.append({"x": sx, "z": sz, "r": r, "top": hgt * float(rng.uniform(*STACK_H))})
                # and the stumps of the ones the sea has had, round its foot
                for _ in range(int(rng.integers(1, 4))):
                    a = float(rng.uniform(0.0, math.tau))
                    d = r + float(rng.uniform(4.0, 22.0))
                    skerries.append({"x": sx + math.cos(a) * d, "z": sz + math.sin(a) * d,
                                     "r": float(rng.uniform(*SKERRY_R_M)), "top": float(rng.uniform(*SKERRY_TOP_M))})
            s += float(rng.uniform(*STACK_EVERY_M))
    # a cove's shore is its beach
    if coves:
        X, Z = gp.mesh()
        for c in coves:
            near = (X - c["x"]) ** 2 + (Z - c["z"]) ** 2 < (c["r"] * 1.25) ** 2
            cls[near & coast] = c["cls"]
            plat[near & coast] = 0.0
            dune[near & coast] = 0.0
        del X, Z
    # skerries off the rocky shores, in clusters
    ci, cj = np.nonzero(coast & (cls == ROCK) & ~shelf)
    if ci.size:
        order = np.argsort(ci * n + cj)
        ci, cj = ci[order], cj[order]
        stride = max(1, int(np.mean(SKERRY_EVERY_M) / sp))
        for q in range(int(rng.integers(0, stride)), ci.size, stride):
            x, z = gp.to_world(cj[q], ci[q])
            x, z = float(x), float(z)
            nx, nz = normal_at(x, z)
            for _ in range(int(rng.integers(SKERRY_COUNT[0], SKERRY_COUNT[1] + 1))):
                out = float(rng.uniform(*SKERRY_OUT_M))
                along = float(rng.uniform(-50.0, 50.0))
                sx, sz = x + nx * out - nz * along, z + nz * out + nx * along
                r = float(rng.uniform(*SKERRY_R_M))
                if abs(sx) > lim or abs(sz) > lim or not pad_ok(sx, sz, r + 60.0) or not sight_ok(sx, sz, r):
                    continue
                skerries.append({"x": sx, "z": sz, "r": r, "top": float(rng.uniform(*SKERRY_TOP_M))})
    # an authored pad low at a cliff's foot: a shelf of rock at its level out into the water
    shelves = []
    for pad in atlas.get("pads", []):
        lvl = float(pad.get("level_m", 99.0))
        if lvl > SHELF_PAD_MAX_M:
            continue
        pos = next(((float(x), float(z), float(r)) for (x, z, r, pid) in _pad_ids(keep_discs) if pid == pad["place"]), None)
        if pos is None:
            continue
        x, z, r = pos
        j, i = gp.to_tex(np.array([x]), np.array([z]))
        j, i = gp.clamp_index(j, i)
        if shelf[int(i[0]), int(j[0])]:
            continue
        k = int(SHELF_PAD_NEAR_M / sp)
        near_cliff = cliff_w[max(int(i[0]) - k, 0):int(i[0]) + k + 1, max(int(j[0]) - k, 0):int(j[0]) + k + 1]
        if near_cliff.max() < CLIFF_W_AT:
            continue
        nx, nz = normal_at(x, z)
        shelves.append({"x": x, "z": z, "r": r, "level": lvl, "nx": nx, "nz": nz, "id": pad["place"]})
    # the class of the nearest coastline, out to BAND_M either side of it
    if coast.any():
        d, (ii, jj) = ndimage.distance_transform_edt(~coast, return_indices=True)
        band = d * sp <= BAND_M
        cls = np.where(band, cls[ii, jj], 0).astype(np.uint8)
        plat = np.where(band, plat[ii, jj], 0.0).astype(np.float32)
        dune = np.where(band, dune[ii, jj], 0.0).astype(np.float32)
        ch = np.where(band, cliff_h[ii, jj], 0.0).astype(np.float32)
        del d, ii, jj
    else:
        ch = cliff_h
    # each kind's share, softened across its seams with the next, and the widths with them
    sig = SOFT_M / sp
    inb = (cls > 0).astype(np.float32)
    norm = np.maximum(ndimage.gaussian_filter(inb, sig), 1e-3)
    shares = {c: (ndimage.gaussian_filter((cls == c).astype(np.float32), sig) / norm * inb).astype(np.float32)
              for c in (SAND, SHINGLE, ROCK, CLIFF, MUD)}
    plat = (ndimage.gaussian_filter(plat, sig) / norm * inb).astype(np.float32)
    dune = (ndimage.gaussian_filter(dune, sig) / norm * inb).astype(np.float32)
    counts = {CLASS_NAMES[c]: int(((cls == c) & coast).sum()) for c in (SAND, SHINGLE, ROCK, CLIFF, MUD)}
    counts.update(coves=len(coves), stacks=len(stacks), skerries=len(skerries), shelves=len(shelves))
    return ShorePlan(gp=gp, sd=sd.astype(np.float32), cls=cls, cliff_h=ch, plat=plat, dune=dune, w=shares,
                     coves=coves, stacks=stacks, skerries=skerries, shelves=shelves, counts=counts)


def _pad_ids(keep_discs):
    """keep_discs may carry the place id as a fourth member ((x, z, r, id)); those without are
    passed over for the shelves."""
    for d in keep_discs:
        if len(d) >= 4:
            yield d[0], d[1], d[2], d[3]


def _tiles(n: int, boxes: list):
    """Full-resolution tiles (i0, i1, j0, j1) of TILE texels that any of `boxes` touches."""
    seen = set()
    for (bi0, bi1, bj0, bj1) in boxes:
        for ti in range(max(bi0, 0) // TILE, (min(bi1, n) - 1) // TILE + 1):
            for tj in range(max(bj0, 0) // TILE, (min(bj1, n) - 1) // TILE + 1):
                seen.add((ti, tj))
    for ti, tj in sorted(seen):
        yield ti * TILE, min((ti + 1) * TILE, n), tj * TILE, min((tj + 1) * TILE, n)


def shape(grid: Grid, H: np.ndarray, p: ShorePlan, bank, keep_discs=(), keep: np.ndarray | None = None,
          no_raise: np.ndarray | None = None) -> np.ndarray:
    """The sea's shores laid on the land at full resolution: foreshores, dunes, berms, ledges and
    platforms by class, then the coves, the stacks, the skerries and the pad shelves. Kept off
    `keep` (bool, full grid: roads, rivers) and the pads in `keep_discs`; nothing is raised in
    `no_raise` (the sightlines)."""
    n = grid.n
    sp = grid.spacing
    gp = p.gp
    f = n // gp.n
    # every tile the band touches (the band is two long strips; a box round it is the world)
    boxes = []
    active = ndimage.binary_dilation(p.cls > 0, iterations=2)
    per = max(TILE // f, 1)
    for ti in range((gp.n + per - 1) // per):
        for tj in range((gp.n + per - 1) // per):
            if active[ti * per:(ti + 1) * per, tj * per:(tj + 1) * per].any():
                boxes.append((ti * TILE, (ti + 1) * TILE, tj * TILE, (tj + 1) * TILE))
    things = [(c["x"], c["z"], c["r"] * 1.6 + 40.0) for c in p.coves] \
        + [(s["x"], s["z"], s["r"] + 10.0) for s in p.stacks] \
        + [(s["x"], s["z"], s["r"] + 4.0) for s in p.skerries] \
        + [(s["x"], s["z"], s["r"] + 60.0) for s in p.shelves]
    for (x, z, r) in things:
        j, i = grid.to_tex(x, z)
        k = int(r / sp) + 2
        boxes.append((int(i) - k, int(i) + k + 1, int(j) - k, int(j) + k + 1))
    rough_f = _noise(bank, 7721, 18.0, 70.0)
    pool_f = _noise(bank, 7725, 45.0, 160.0)
    dune_f = _noise(bank, 7722, 26.0, 85.0, beta=1.6)
    dune_a = _noise(bank, 7723, 200.0, 700.0)
    ledge_f = _noise(bank, 7724, 40.0, 160.0)
    g1 = grid.with_n(rough_f.shape[0])
    for (i0, i1, j0, j1) in _tiles(n, boxes):
        xs = grid.x0 + np.arange(j0, j1, dtype=np.float32) * sp
        zs = grid.z0 + np.arange(i0, i1, dtype=np.float32) * sp
        X = np.broadcast_to(xs[None, :], (i1 - i0, j1 - j0))
        Z = np.broadcast_to(zs[:, None], (i1 - i0, j1 - j0))
        sub = H[i0:i1, j0:j1].astype(np.float32)
        orig = sub.copy()
        sd = sample_bilinear(p.sd, gp, X, Z)
        plat = sample_bilinear(p.plat, gp, X, Z)
        dune_w = sample_bilinear(p.dune, gp, X, Z)
        w_sand, w_shingle, w_mud = (sample_bilinear(p.w[c], gp, X, Z) for c in (SAND, SHINGLE, MUD))
        w_rock = sample_bilinear(p.w[ROCK], gp, X, Z)
        w_hard = w_rock + sample_bilinear(p.w[CLIFF], gp, X, Z)
        rough = 0.5 + 0.5 * np.tanh(sample_bilinear(rough_f, g1, X, Z))
        ridge = ridged(sample_bilinear(rough_f, g1, X, Z), 1.4)
        # what may not move: the roads and the rivers, and every pad and a little round it
        held = np.zeros(sub.shape, dtype=bool) if keep is None else keep[i0:i1, j0:j1].copy()
        for d in keep_discs:
            px, pz, pr = float(d[0]), float(d[1]), float(d[2]) + PAD_CLEAR_M
            if px + pr < xs[0] or px - pr > xs[-1] or pz + pr < zs[0] or pz - pr > zs[-1]:
                continue
            held |= (X - px) ** 2 + (Z - pz) ** 2 <= pr * pr
        road_free = (np.ones(sub.shape, dtype=np.float32) if keep is None
                     else (~keep[i0:i1, j0:j1]).astype(np.float32))
        free = (~held).astype(np.float32)
        up_ok = free * (1.0 if no_raise is None else (~no_raise[i0:i1, j0:j1]).astype(np.float32))
        wet = sd > 0.0
        in_d = np.maximum(-sd, 0.0)
        out_d = np.maximum(sd, 0.0)
        # --- the sea's side ---
        # a sandy foreshore: shallow a long way out
        fore = -0.2 - FORESHORE_DEEP_M * np.clip(out_d / FORESHORE_M, 0.0, 1.0) ** 1.3
        t = 1.0 - smoothstep(FORESHORE_M * 0.8, FORESHORE_M * 1.4, out_d)
        sub = np.where(wet, lerp(sub, np.maximum(sub, fore), t * up_ok * w_sand), sub)
        # tidal mud off the marsh
        flat = -0.15 - MUDFLAT_DEEP_M * np.clip(out_d / MUDFLAT_M, 0.0, 1.0)
        t = 1.0 - smoothstep(MUDFLAT_M * 0.8, MUDFLAT_M * 1.3, out_d)
        sub = np.where(wet, lerp(sub, np.maximum(sub, flat), t * up_ok * w_mud), sub)
        # the rock at a cliff's foot and off a rocky shore: a platform just out of the water,
        # ridged, with pools lying in it in whole sheets (not a speckle of wet and dry texels),
        # wetter toward its outer edge, and its lip dropping to the sea floor
        pool = smoothstep(0.35, 0.8, sample_bilinear(pool_f, g1, X, Z))
        rock_top = PLATFORM_TOP_M + PLATFORM_RIDGE_M * (ridge - 0.5) * 0.5 \
            - PLATFORM_POOL_M * pool - 0.5 * np.clip(out_d / np.maximum(plat, 1.0), 0.0, 1.0)
        w = wet & (plat > 0.5)
        lip = smoothstep(plat, plat + 22.0, out_d)
        target = lerp(np.maximum(rock_top, sub), np.maximum(sub, -1.6 - 0.2 * out_d), lip)
        target = np.where(out_d > plat + 22.0, sub, target)
        sub = np.where(w, lerp(sub, np.maximum(sub, target), up_ok * smoothstep(0.2, 0.7, w_hard)), sub)
        # --- the land's side ---
        low = 1.0 - smoothstep(DUNE_ON_M * 0.5, DUNE_ON_M, orig)
        # dunes behind a sandy bay: ridges across the wind, highest a little back from the beach
        amp = DUNE_M[0] + (DUNE_M[1] - DUNE_M[0]) * (0.5 + 0.5 * np.tanh(sample_bilinear(dune_a, g1, X, Z)))
        belt = smoothstep(18.0, 48.0, in_d) * (1.0 - smoothstep(dune_w * 0.55, np.maximum(dune_w, 1.0), in_d))
        dunes = amp * belt * (0.65 * ridged(sample_bilinear(dune_f, g1, X, Z), 1.6) + 0.35 * rough)
        sub = np.where(~wet, sub + dunes * low * up_ok * w_sand, sub)
        # a shingle beach's storm berm
        berm = BERM_M * np.exp(-((in_d - BERM_AT_M) / 4.5) ** 2) * (1.0 - smoothstep(3.0, 7.0, orig))
        sub = np.where(~wet, sub + berm * up_ok * w_shingle, sub)
        # a rocky shore's ledge: the ground at the water flattened to rock a metre or two up
        ledge = ROCK_LEDGE_M[0] + (ROCK_LEDGE_M[1] - ROCK_LEDGE_M[0]) * (0.5 + 0.5 * np.tanh(
            sample_bilinear(ledge_f, g1, X, Z))) + 0.35 * ridge
        t = (1.0 - smoothstep(16.0, 34.0, in_d)) * (1.0 - smoothstep(ledge + 2.0, ledge + 7.0, orig))
        sub = np.where(~wet, lerp(sub, ledge, t * w_rock * np.where(ledge > sub, up_ok, free)), sub)
        # --- coves, cut back into the cliff ---
        for c in p.coves:
            r = np.hypot(X - c["x"], Z - c["z"])
            wall = 10.0 + 0.15 * c["cliff"]
            if float(r.min()) > c["r"] + wall:
                continue
            # how far into the cove from its mouth: 0 at the coast, 1 at the back
            inward = -((X - c["x"]) * c["nx"] + (Z - c["z"]) * c["nz"])
            u = np.clip(r / c["r"], 0.0, 1.5)
            sand = c["cls"] == SAND
            beach_top = 2.6 if sand else 3.4
            head = np.where(u < 0.3, -1.6 + 1.6 * u / 0.3,
                            np.where(u < 0.85, beach_top * (u - 0.3) / 0.55,
                                     beach_top + (7.0 - beach_top) * np.clip((u - 0.85) / 0.15, 0.0, 1.0)))
            if not sand:
                head = head + 1.2 * np.exp(-((u - 0.62) / 0.08) ** 2)
            head = head + 0.25 * (rough - 0.5)
            # the sea's half of the disc is its floor: shallow sand or shingle
            floor = -1.2 - 3.2 * np.clip(u, 0.0, 1.0)
            cut = np.where(inward >= 0.0, head, np.maximum(floor, np.minimum(head, floor)))
            wgt = (1.0 - smoothstep(c["r"], c["r"] + wall, r)) * free
            sub = np.where(wgt > 0.0, lerp(sub, np.where(inward >= 0.0, np.minimum(sub, cut),
                                                          np.maximum(np.minimum(sub, 0.0), cut)), wgt), sub)
        # --- stacks, skerries and the shelves under low pads ---
        for s in p.stacks:
            r = np.hypot(X - s["x"], Z - s["z"])
            if float(r.min()) > s["r"] + 8.0:
                continue
            a = np.arctan2(Z - s["z"], X - s["x"])
            rn = r * (1.0 + 0.22 * np.sin(3.0 * a + s["x"] * 0.01) + 0.12 * np.sin(5.0 * a + s["z"] * 0.013))
            core = 1.0 - smoothstep(s["r"] * 0.78, s["r"], rn)
            foot = 1.0 - smoothstep(s["r"], s["r"] + 7.0, rn)
            top = s["top"] * (0.92 + 0.08 * rough) - 2.5 * smoothstep(0.2, 1.0, rn / s["r"]) ** 3
            sub = np.where(foot > 0.0, np.maximum(sub, lerp(sub, 0.4 + 0.5 * rough, foot * up_ok)), sub)
            sub = np.where(core > 0.0, np.maximum(sub, lerp(sub, top, core * up_ok)), sub)
        for s in p.skerries:
            d2 = ((X - s["x"]) ** 2 + (Z - s["z"]) ** 2) / (s["r"] * s["r"])
            if float(d2.min()) > 1.0:
                continue
            lump = np.clip(1.0 - d2, 0.0, 1.0) ** 0.6 * (0.8 + 0.4 * rough)
            sub = np.where(d2 < 1.0, np.maximum(sub, sub + (s["top"] - sub) * np.minimum(lump, 1.0) * up_ok), sub)
        for s in p.shelves:
            # a lobe of rock at the pad's level, out from it into the water, its edge broken
            cx, cz = s["x"] + s["nx"] * 10.0, s["z"] + s["nz"] * 10.0
            r = np.hypot(X - cx, Z - cz)
            a = np.arctan2(Z - cz, X - cx)
            reach = s["r"] + 18.0
            rn = r * (1.0 + 0.16 * np.sin(4.0 * a + 1.3) + 0.1 * np.sin(7.0 * a))
            lobe = 1.0 - smoothstep(reach - 10.0, reach, rn)
            step = (1.0 - smoothstep(reach, reach + 16.0, rn)) * (1.0 - lobe)
            shelf_top = s["level"] - 0.35 + 0.3 * (rough - 0.5)
            # (never lowered, so the pad's own level core stands as it is)
            not_pad = 1.0
            sub = np.where(lobe > 0.0, np.maximum(sub, lerp(sub, shelf_top, lobe * not_pad * road_free)), sub)
            sub = np.where(step > 0.0, np.maximum(sub, lerp(sub, 0.3 + 0.6 * rough, step * not_pad * road_free)), sub)
        H[i0:i1, j0:j1] = sub.astype(np.float32)
    return H


# --- the marsh -------------------------------------------------------------------------------------

def marsh(grid: Grid, H: np.ndarray, rf, regions: list, table: np.ndarray, bank,
          keep: np.ndarray | None = None, carve: bool = True, p: ShorePlan | None = None) -> tuple:
    """Creeks and pools in a delta province's low ground. Returns (heights, water): `water` (bool,
    full grid) is where they hold water at the table, which the water maps add to the marsh's own
    pools (hydro.water_maps `extra`) -- a creek three metres wide is narrower than the opening
    that keeps the pools from speckling, and would be lost to it. With `carve` False the heights
    are left as they are and only the water is read from them (a staged build's reload). With the
    shore's plan `p`, the ground within MARSH_SEA_M of the sea is left to the tide-flats."""
    n = grid.n
    sp = grid.spacing
    water = np.zeros((n, n), dtype=bool)
    marsh_ids = [r.index for r in regions if r.shape == "delta"]
    if not marsh_ids:
        return H, water
    gp = grid.with_n(min(PLAN_N, n))
    wd = sum(rf.weight_at(k, gp.n) for k in marsh_ids).astype(np.float32)
    on = wd > 0.3
    if not on.any():
        return H, water
    f = n // gp.n
    ii = np.flatnonzero(on.any(axis=1))
    jj = np.flatnonzero(on.any(axis=0))
    box = (int(ii[0]) * f, (int(ii[-1]) + 1) * f, int(jj[0]) * f, (int(jj[-1]) + 1) * f)
    c1 = _noise(bank, 7731, 140.0, 520.0, beta=1.6)
    c2 = _noise(bank, 7732, 60.0, 220.0, beta=1.6)
    cw = _noise(bank, 7733, 150.0, 600.0)
    gate = _noise(bank, 7734, 300.0, 1200.0)
    pools = _noise(bank, 7735, 24.0, 80.0, beta=1.4)
    g1 = grid.with_n(c1.shape[0])
    half_min = 0.6 * sp
    for (i0, i1, j0, j1) in _tiles(n, [box]):
        xs = grid.x0 + np.arange(j0, j1, dtype=np.float32) * sp
        zs = grid.z0 + np.arange(i0, i1, dtype=np.float32) * sp
        X = np.broadcast_to(xs[None, :], (i1 - i0, j1 - j0))
        Z = np.broadcast_to(zs[:, None], (i1 - i0, j1 - j0))
        dw = sample_bilinear(wd, gp, X, Z)
        if float(dw.max()) < 0.5:
            continue
        sub = H[i0:i1, j0:j1].astype(np.float32)
        tbl = table[i0:i1, j0:j1]
        held = np.zeros(sub.shape, dtype=bool) if keep is None else keep[i0:i1, j0:j1]
        low = (dw > 0.5) & (sub < tbl + MARSH_LOW_M) & ~held
        if p is not None:
            low &= sample_bilinear(p.sd, p.gp, X, Z) < -MARSH_SEA_M
        cut = np.zeros(sub.shape, dtype=np.float32)
        bed = np.zeros(sub.shape, dtype=np.float32)
        for fld, share, salt_scale in ((c1, 1.0, 1.0), (c2, 0.6, 0.7)):
            v = sample_bilinear(fld, g1, X, Z)
            gz_, gx_ = np.gradient(v, sp)
            dist = np.abs(v) / np.maximum(np.hypot(gx_, gz_), 1e-4)
            half = np.maximum(half_min, (CREEK_HALF_M[0] + (CREEK_HALF_M[1] - CREEK_HALF_M[0])
                                         * (0.5 + 0.5 * np.tanh(sample_bilinear(cw, g1, X, Z)))) * salt_scale)
            prof = 1.0 - smoothstep(0.55 * half, half + 1.2, dist)
            prof = prof * (sample_bilinear(gate, g1, X, Z) > 0.5 * (1.0 - share))
            cut = np.maximum(cut, prof)
            bed = np.where(prof >= cut, tbl - CREEK_BED_M * (0.6 + 0.4 * half / CREEK_HALF_M[1]), bed)
        pv = sample_bilinear(pools, g1, X, Z)
        pprof = smoothstep(POOL_T, POOL_T + 0.35, pv) * (sub < tbl + 0.8)
        bed = np.where(pprof > cut, tbl - POOL_BED_M, bed)
        cut = np.maximum(cut, pprof)
        cut = cut * low
        if carve:
            sub = np.where(cut > 0.0, np.minimum(sub, lerp(sub, bed, cut)), sub)
            H[i0:i1, j0:j1] = sub.astype(np.float32)
        water[i0:i1, j0:j1] = (cut > 0.3) & (sub < tbl - 0.12)
    return H, water


# --- the classes as built --------------------------------------------------------------------------

def classify(grid: Grid, H: np.ndarray, water_mask: np.ndarray, water_level: np.ndarray, p: ShorePlan,
             lake, rf, regions: list, bank) -> tuple:
    """(class u8, signed metres to the water's edge f32), both on the PLAN_N lattice: the sea's
    shores as planned and shaped, and every lake's and river's read from its bank. A texel within
    SHORE_REACH_M of the edge, either side, carries the class of the land it is nearest; the
    distance is negative on the water."""
    gp = p.gp
    f = grid.n // gp.n
    sp = gp.spacing
    h = H[::f, ::f]
    wet = water_mask[::f, ::f] > 0
    lvl = water_level[::f, ::f]
    gz_, gx_ = np.gradient(h.astype(np.float32), sp)
    sl = np.hypot(gx_, gz_)
    del gz_, gx_
    reach = SHORE_REACH_M
    if not wet.any() or wet.all():
        return np.zeros(h.shape, dtype=np.uint8), np.full(h.shape, 1e6, dtype=np.float32)
    d_w, (wi, wj) = ndimage.distance_transform_edt(~wet, return_indices=True)
    d_l, (li, lj) = ndimage.distance_transform_edt(wet, return_indices=True)
    shore_d = np.where(wet, -d_l, d_w).astype(np.float32) * sp
    near_land = (~wet) & (d_w * sp <= reach)
    # the water each bank faces, and how high the bank stands over it
    faces = lvl[wi, wj]
    over = h - faces
    sea_face = (np.abs(faces - SEA_LEVEL) < 0.05) & (np.abs(p.sd) < BAND_M + reach)
    cls = np.zeros(h.shape, dtype=np.uint8)
    # the sea's: as planned, a cliff's platform and ledges being rock
    planned = p.cls
    cls = np.where(near_land & sea_face, planned, cls)
    cls = np.where(near_land & sea_face & (planned == CLIFF) & (over < 6.0), ROCK, cls)
    cls = np.where(near_land & sea_face & (planned == 0), np.where(sl > 0.6, ROCK, SAND), cls)
    # and a sandy bay's dunes, which run back further than any bank
    dune_land = (~wet) & (planned == SAND) & (np.abs(p.sd) < BAND_M) & (d_w * sp <= DUNE_BELT_M[1] + 20.0)
    cls = np.where(dune_land & ~near_land, SAND, cls)
    # the lakes' and the rivers': by the bank
    inland = near_land & ~sea_face
    reedy = np.zeros(h.shape, dtype=np.float32)
    if lake is not None and getattr(lake, "reediness", None) is not None:
        reedy = lake.reediness[::f, ::f][wi, wj]
    marshy = np.zeros(h.shape, dtype=bool)
    ids = [r.index for r in regions if r.shape in ("delta", "lake_basin")]
    if ids:
        marshy = sum(rf.weight_at(k, gp.n) for k in ids) > 0.5
    v = np.tanh(_noise(bank, 7741, 60.0, 300.0))
    gentle = sl < 0.12
    steep = sl > 0.7
    lake_cls = np.where(steep, np.where(over > 6.0, CLIFF, ROCK),
                        np.where(gentle & ((reedy > 0.35) | (marshy & (v > -0.1))), REEDS,
                                 np.where(gentle & (v > -0.4), MUD, SHINGLE)))
    cls = np.where(inland, lake_cls, cls).astype(np.uint8)
    # the water near a shore carries the class of the bank it laps
    near_water = wet & (d_l * sp <= reach)
    cls = np.where(near_water, cls[li, lj], cls).astype(np.uint8)
    far = (np.abs(shore_d) > reach) & ~dune_land
    cls[far] = 0
    return cls, shore_d


## how far either side of the water's edge a shore's class is written (m)
SHORE_REACH_M = 60.0
## how far up from the water a beach is bare of everything but the shore's own plants and wrack,
## and a rocky shore (cells.scatter)
BEACH_BARE_M = 24.0
ROCK_BARE_M = 10.0
