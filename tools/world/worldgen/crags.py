"""Crags: rock set into the steep faces, outcrops on the edges and crests, and the sea cliffs.

A heightmap cannot hold a crag. A face steeper than about 35 degrees is a handful of texels
stretched over a long drop, and the ground texture on it smears down the slope; from the dale
floor the Skerrow's walls read as grey rubber, not as rock. A sea cliff is worse: it is one texel
from its top to the water, a hundred metres of stretched ground.

The forge's cliff ledge (gen_rocks.cliff_ledge) is what dresses them. It is a module of bedded
rock in each region's stone: two to four beds each standing out a little further than the one
below, the lowest undercut and the top one a lip, 5 m wide, its two ends cut to its beds' own
profile. Ledges laid side by side at their width meet as one face, so a row reads as one run of
rock; and stacked, each row standing on the one below, they step up a face in ledges:

* **The faces** (`place`). A crag is a run of ledges along the face's contour (RUN_LEN), one
  scale throughout so its ends meet, stacked RUN_ROWS rows high, each row set back up the slope
  far enough that its flat back is in the hill (LEDGE_BACK_SHOW_M at most shows). Where the
  region has no ledge, and in Cinderlea, whose faces are its basalt columns, the old face pieces
  stand instead: leaned back into the hill, sunk FACE_EMBED of their depth, sized to the face.
  A run's two cut ends each have a boulder at them.
* **The crests** (`place`). Where a convex edge is steep enough to seat one (CREST_LEDGE_SLOPE),
  an outcrop is a short run of the smallest ledge; on the gentler crests it is a boulder, sunk
  CREST_EMBED of its height.
* **The sea cliffs** (`coast_walls`). Each of the atlas's cliffs of WALL_MIN_M and over is dressed
  from the water to its top in rows of ledges, at a scale that grows with the cliff. Every column
  of one cliff takes the same ledge at the same height, so its beds run level along the whole
  cliff as a sea cliff's strata do, not a wall of blocks; its stacks take the same strata.
* Nothing is set within a road's carve and a margin, on a pad (a cave at a cliff's foot keeps
  its mouth: WALL_PAD_HEADROOM_M), or in or beside water inland; and in an authored sightline's
  corridor nothing stands within the game's clearance of the ray (`ceiling_under_lines`).

Everything goes into the cells' scatter buckets, so the streamer draws it in the same MultiMesh
per asset per cell as everything else: three ledges, two face pieces and two outcrops a region
at the most.
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

## which forge piece dresses each kind of province's faces where it has no ledge, and its crests
FACE_PIECE = {
    "mountains": "rocks/cliff_slab",       # the Skerrow's limestone
    "forest_rise": "rocks/cliff_slab",     # the Briarwold's granite
    "ash_plateau": "rocks/basalt_columns", # Cinderlea's old lava
    "downs": "rocks/cliff_slab",           # the Hearthvale's chalk, on its brow
    "lake_basin": "rocks/cliff_slab",      # Brightwater's lake stone
}
CREST_PIECE = {k: "rocks/boulder" for k in FACE_PIECE}

# --- the cliff ledge -----------------------------------------------------------------------------
## The forge's module of bedded rock. Its origin is at its foot in the middle of its width, and its
## front looks along +z: the lip of its top bed about 2.5 m out, the foot of its undercut lowest
## bed about 1.3 m (the generator's undercut is LEDGE_UNDERCUT of its depth), its flat back 1.7 m
## behind. Its ends are at +-2.5 m.
LEDGE_PIECE = "rocks/cliff_ledge"
LEDGE_UNDERCUT = 0.12
## a run's ledges stand this share of the module's width apart, so their ends overlap a little;
## their yaw keeps to the face's within LEDGE_YAW_JITTER_DEG (more opens the ends); a run is one
## scale throughout, or its ends would not meet
LEDGE_STEP = 0.94
LEDGE_YAW_JITTER_DEG = 2.5
## how deep a ledge's foot sits under the ground at its front, and how much of its flat back may
## stand clear of the hill behind it (metres at scale one)
LEDGE_FOOT_EMBED_M = 0.3
LEDGE_BACK_SHOW_M = 0.6
## Rows of one module repeated read as masonry: the in-engine look at 1024 had the sea cliffs as a
## wall of sandbags, every seam lined up from the water to the top. So each row (and each bed of a
## sea cliff) is slid along the face by its own share of a module, and each module stands a little
## in or out of its neighbours (metres at scale one, out positive).
LEDGE_STAGGER = (0.25, 0.75)
## and a crag's rows above the first step back irregularly (`course_span`: each a shorter span of
## the one below, now and then with a module missing), and its beds dip along the face by a few
## degrees (a whole crag one way, the row's lean pair about each module's foot)
LEDGE_GAP_P = 0.3
LEDGE_DIP_DEG = (1.5, 5.0)
LEDGE_IN_OUT_M = (-0.3, 0.2)
## where the next row up stands on the one below: its foot this far down into it, set back at
## least LEDGE_SET_BACK_M and at most as far as the lower ledge's top reaches
LEDGE_SEAT_M = 0.18
LEDGE_SET_BACK_M = 0.95
## the faces: crags a hectare of face (through the same cluster field as the face pieces), ledges a
## run, rows a crag, and a crag's scale
RUN_SEEDS_HA = 6.0
RUN_LEN = (2, 7)
RUN_ROWS = (1, 4)
RUN_SCALE = (1.0, 1.5)
## the landforms whose faces keep their own piece: Cinderlea's basalt columns are its signature
LEDGE_KEEP_OWN = ("ash_plateau",)
## An outcrop was a short run of ledges where the crest is at least this steep, a boulder below it.
## A row of ledges along a ridge's top read as a wall laid on the hill (the w4096b shots), so the
## crests are boulders again, seated, with CREST_KIN smaller stones fallen below a share of them.
CREST_LEDGES = False
CREST_KIN_P = 0.55
CREST_KIN = (1, 2)
CREST_LEDGE_SLOPE = 0.55
CREST_RUN = (1, 3)
CREST_LEDGE_SCALE = (0.9, 1.3)
## a boulder at each cut end of a run: its height against the ledge's, and how far it sinks. It is
## sized up, to END_BOULDER_MAX of the ledge's height at most, until its top reaches END_COVER of
## the ledge's: a ledge module is a box (its hull is nine tenths of its bounds), and its cut end is a
## flat face. The w4096c Skerrow shot had a one-ledge run on a 1 in 2 brow seen end-on, a pale cube
## on the skyline: its 0.85 boulder, sunk a third, stood to half the end's height.
END_BOULDER_FIT = 0.85
END_BOULDER_SINK = 0.35
END_COVER = 0.9
END_BOULDER_MAX = 1.8

# --- the sea cliffs ------------------------------------------------------------------------------
## the atlas's cliffs of this height and over are dressed; a cliff's ledges are at a scale that
## grows with it (so a hundred-metre face is not three hundred modules high)
WALL_MIN_M = 10.0
## the sea cliffs are dressed at all (False leaves them to the terrain, as before the ledges)
COAST_WALLS = True
## A sea cliff's beds are not all alike: a soft bed is weathered back into the cliff along its whole
## length (no ledge; the terrain's rock shows), a hard one runs on across the bays, and the rest
## stand only on the buttresses. The bays are where a noise along the cliff falls under
## WALL_BAY_T (about two fifths of it); the lowest bed is hard, a ledge of rock at the water; and no
## two soft beds lie together.
WALL_SOFT_SHARE = 0.25
WALL_HARD_SHARE = 0.3
WALL_BAY_T = -0.2
WALL_BAY_WL_M = (37.0, 61.0, 67.0)
WALL_SCALE_PER_M = 1.0 / 45.0
WALL_SCALE = (1.0, 2.2)
## the lowest row's foot (metres at scale one, under the sea): the platform's rock or the water
## closes over it, and every column starts there, so the beds run level along the cliff
WALL_FOOT_M = -1.2
## a column is set where the wall is at least this steep, and runs no further than this from the
## atlas's line of the cliff
WALL_SLOPE_MIN = 1.2
WALL_REACH_M = 150.0
## and a bed is laid only where the wall it would stand on is at least this steep (the smoothed
## ground, where the bed's middle height crosses it)
WALL_FACE_SLOPE = 0.7
## the seeds a column trace starts from, along the atlas's line
WALL_SEED_EVERY_M = 60.0
## where a column looks, in metres from its point on the wall's middle contour: for the cliff's top
## (inland), its foot (seaward), and each bed's crossing of the face (from inland, out); in metres,
## so a bank is dressed the same at any size of build
WALL_TOP_LOOK_M = (0.0, 4.0, 8.0, 12.0, 16.0, 24.0)
WALL_FOOT_LOOK_M = (0.0, 8.0, 16.0, 24.0, 32.0)
WALL_FACE_LOOK_M = (24.0, 40.0)
## how far behind the wall's face a ledge's origin sits (scale one): its foot stands about a metre
## proud of the face and its back is in the rock
WALL_SINK_M = 0.25
## the top row may stand this far over the cliff's top (metres), and no further; the strata are
## laid out to this height, over any cliff's top
WALL_OVERSHOOT_M = 1.0
WALL_STRATA_TOP_M = 600.0
## a pad at the cliff's foot keeps the wall off it: this far round it, up to this far over its level
WALL_PAD_CLEAR_M = 10.0
WALL_PAD_HEADROOM_M = 14.0
## A sea cliff's strata are not ranks of one module (the w4096b shots: "ranks of alike ledge tops, still
## masonry"). Each bed has its own thickness, a vertical stretch of the module (the row's ninth field,
## [sx, sy, sz]); its own set-back from the face, the hard beds proud and the rest weathered in, and
## wandering along the cliff; and its own dip, a few degrees one way along it. Along each bed a module
## is now and then missing or slumped a little down out of its bed; and at the cliff's foot lie the
## blocks that have come down: boulders and broken ledges, tipped, half in the shingle.
WALL_BED_STRETCH = (0.6, 1.5)
WALL_SET_BACK_M = {"hard": (0.0, 0.1), "mid": (0.15, 0.45)}
WALL_WANDER_M = 0.25
WALL_DIP_DEG = (0.8, 3.0)
WALL_GAP_P = 0.08
WALL_SLUMP_P = 0.07
WALL_SLUMP_M = (0.15, 0.5)
WALL_FALLEN_P = 0.4
WALL_FALLEN = (1, 3)
WALL_FALLEN_OUT_M = (1.0, 9.0)
## a stack is ringed with its cliff's strata, its modules closer (a ring's joints open at the front)
STACK_STEP = 0.8


def course_span(row: list, rng) -> list:
    """A row above a crag's first: a contiguous span of the row below it, shorter by up to half, and
    with a probability of LEDGE_GAP_P one module inside it missing (None), where it is long enough."""
    n = len(row)
    if n == 0:
        return []
    keep = max(1, n - int(rng.integers(0, max(n // 2, 1) + 1)))
    start = int(rng.integers(0, n - keep + 1))
    out = list(row[start:start + keep])
    if len(out) >= 4 and rng.random() < LEDGE_GAP_P:
        out[int(rng.integers(1, len(out) - 1))] = None
    return out


def _segments(row: list) -> list:
    """The runs of a row between its missing modules (None)."""
    segs, cur = [], []
    for p in row:
        if p is None:
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(p)
    if cur:
        segs.append(cur)
    return segs


def piece_size(asset: str, repo_root: str) -> tuple:
    """(height, depth to its front face) in metres, off the forge's meta for `asset` (a res://
    path), or a cliff slab's when it has none."""
    b = _meta(asset, repo_root).get("bounds")
    if b:
        return float(b["max"][1] - b["min"][1]), float(b["max"][2])
    return 6.4, 1.8


def _meta(asset: str, repo_root: str) -> dict:
    import json
    import os

    rel = asset.replace("res://", "game/", 1)
    path = os.path.join(repo_root, os.path.splitext(rel)[0] + ".meta.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


class Ledge:
    """One ledge asset's size at scale one: `h` its height, `back` how far its flat back stands
    behind its origin, `foot` how far out the foot of its lowest bed stands, `w` its width."""

    def __init__(self, asset: str, meta: dict):
        b = meta["bounds"]
        self.asset = asset
        self.h = float(b["max"][1] - b["min"][1])
        self.back = -float(b["min"][2])
        self.foot = self.back * (1.0 - 2.0 * LEDGE_UNDERCUT)
        self.w = float(meta.get("module_width_m", b["max"][0] - b["min"][0]))


def ledge_kit(index: dict, art_short: str, repo_root: str) -> list:
    """This region's own ledges, shortest first; [] where it has none (another region's stone is
    not its rock, and the face pieces stand instead)."""
    from . import cells as CELLS

    out = []
    for a in CELLS.assets_for(index, LEDGE_PIECE, art_short):
        if ("/%s_cliff_ledge_" % art_short) not in a:
            continue
        m = _meta(a, repo_root)
        if m.get("bounds"):
            out.append(Ledge(a, m))
    return sorted(out, key=lambda k: k.h)


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
    x = np.atleast_1d(np.asarray(x, dtype=np.float64))
    z = np.atleast_1d(np.asarray(z, dtype=np.float64))
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


class _Ground:
    """The ground at single world points, bilinear: `h` as built, and a copy smoothed over a texel
    or so for the contours and their normals (a face one texel across has no direction of its
    own)."""

    def __init__(self, g: Grid, H: np.ndarray, smooth_texels: float = 1.0):
        self.g = g
        self.H = H
        Hs = ndimage.gaussian_filter(H.astype(np.float32), smooth_texels) if smooth_texels > 0 \
            else H.astype(np.float32)
        self.Hs = Hs
        gz, gx = np.gradient(Hs, g.spacing)
        self.gx, self.gz = gx.astype(np.float32), gz.astype(np.float32)

    def _at(self, A, x: float, z: float) -> float:
        g = self.g
        fj = min(max((x - g.x0) / g.spacing, 0.0), g.n - 1.001)
        fi = min(max((z - g.z0) / g.spacing, 0.0), g.n - 1.001)
        j0, i0 = int(fj), int(fi)
        tj, ti = fj - j0, fi - i0
        a = float(A[i0, j0]) * (1.0 - tj) + float(A[i0, j0 + 1]) * tj
        b = float(A[i0 + 1, j0]) * (1.0 - tj) + float(A[i0 + 1, j0 + 1]) * tj
        return a * (1.0 - ti) + b * ti

    def h(self, x: float, z: float) -> float:
        return self._at(self.H, x, z)

    def hs(self, x: float, z: float) -> float:
        return self._at(self.Hs, x, z)

    def grad(self, x: float, z: float) -> tuple:
        return self._at(self.gx, x, z), self._at(self.gz, x, z)

    def down(self, x: float, z: float):
        """The unit direction straight down the smoothed ground, or None where it is flat."""
        gx, gz = self.grad(x, z)
        m = math.hypot(gx, gz)
        return (-gx / m, -gz / m) if m > 1e-4 else None


class _Taken:
    """Discs already standing (x, z, r), hashed on a coarse lattice, so a crag or a wall does not
    stand in another."""

    def __init__(self, cell: float = 8.0):
        self.cell = cell
        self.bins: dict = {}

    def hit(self, x: float, z: float, r: float) -> bool:
        c = self.cell
        k = int(math.ceil((r + 8.0) / c))
        ci, cj = int(math.floor(z / c)), int(math.floor(x / c))
        for di in range(-k, k + 1):
            for dj in range(-k, k + 1):
                for (px, pz, pr) in self.bins.get((ci + di, cj + dj), ()):
                    if (px - x) ** 2 + (pz - z) ** 2 < (pr + r) ** 2:
                        return True
        return False

    def add(self, x: float, z: float, r: float) -> None:
        self.bins.setdefault((int(math.floor(z / self.cell)), int(math.floor(x / self.cell))), []).append((x, z, r))


def trace_contour(G: _Ground, x0: float, z0: float, level: float, step: float, n: int, ok) -> list:
    """Up to `n` points `step` apart along the contour of G's smoothed ground at `level`, through
    the point of it nearest (x0, z0) and out on both sides, while `ok(x, z)` holds: [(x, z)] in
    order along the contour. A closed contour stops where it comes round to its start."""
    def settle(x, z):
        for _ in range(4):
            gx, gz = G.grad(x, z)
            gg = gx * gx + gz * gz
            if gg < 1e-6:
                return None
            d = (G.hs(x, z) - level) / gg
            x, z = x - d * gx, z - d * gz
        return (x, z) if abs(G.hs(x, z) - level) < 0.25 else None

    def tangent(x, z):
        gx, gz = G.grad(x, z)
        m = math.hypot(gx, gz)
        return (-gz / m, gx / m) if m > 1e-6 else None

    start = settle(x0, z0)
    if start is None or not ok(*start):
        return []
    sides = []
    for sign in (1.0, -1.0):
        pts: list = []
        x, z = start
        t = tangent(x, z)
        if t is None or n <= 1:
            sides.append(pts)
            continue
        tx, tz = t[0] * sign, t[1] * sign
        room = n - 1 - (len(sides[0]) if sides else 0)
        while len(pts) < room:
            p = settle(x + tx * step, z + tz * step)
            if p is None or not ok(*p):
                break
            # the contour turned back on itself, or the settle jumped to another one
            if abs(math.hypot(p[0] - x, p[1] - z) - step) > 0.3 * step:
                break
            # round a closed contour and back to its start
            if len(pts) > 2 and math.hypot(p[0] - start[0], p[1] - start[1]) < 0.7 * step:
                break
            t = tangent(*p)
            if t is None:
                break
            if t[0] * tx + t[1] * tz < 0.0:
                t = (-t[0], -t[1])
            tx, tz = t
            x, z = p
            pts.append(p)
        sides.append(pts)
    return list(reversed(sides[1])) + [start] + sides[0]


def _yaw(dx: float, dz: float) -> float:
    """The scatter row's yaw that turns an asset's front (+z) to look along (dx, dz)."""
    return math.degrees(math.atan2(dx, dz))


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
    kits = {r.index: ([] if r.shape in LEDGE_KEEP_OWN else ledge_kit(index, r.art_short, repo_root))
            for r in regions}
    # the smoothed ground the runs are traced on: only where there is a ledge to lay (three more
    # arrays the size of the world)
    G = _Ground(g, H) if any(kits.values()) else None
    taken = _Taken()
    out: dict = {}
    counts = {"face": 0, "crest": 0, "ledge": 0, "crest_ledge": 0}

    def clear(x, z):
        ok = sample_nearest(water, g, x, z) == 0
        ok &= sample_bilinear(water_d, g, x, z) > WATER_CLEAR_M
        ok &= sample_nearest(road_d, g, x, z) > sample_nearest(road_w, g, x, z) * 0.5 + ROAD_CLEAR_M
        ok &= sample_nearest(pad_mask.astype(np.uint8), g, x, z) == 0
        return ok

    def clear1(x: float, z: float) -> bool:
        return bool(clear(np.array([x]), np.array([z]))[0])

    def put(asset, x, y, z, yaw, scale, lean, toward, tint):
        key = g.written_cell(x, z)
        row = [round(float(x), 2), round(float(y), 2), round(float(z), 2), round(float(yaw), 1),
               round(float(scale), 3), tint, round(float(lean), 1), round(float(toward), 1)]
        out.setdefault(key, {}).setdefault(asset, []).append(row)

    def grey(light: float) -> str:
        c = int(round(255 * min(1.0, max(0.7, 1.0 + light))))
        return "#%02x%02x%02x" % (c, c, c)

    for n, region in enumerate(regions):
        face_piece = FACE_PIECE.get(region.shape)
        if face_piece is None or region.index not in boxes:
            continue
        kit = kits[region.index]
        faces = CELLS.assets_for(index, face_piece, region.art_short)[:FACE_VARIANTS]
        crests = CELLS.assets_for(index, CREST_PIECE[region.shape], region.art_short)[:CREST_VARIANTS]
        rng = np.random.default_rng(np.random.SeedSequence([seed, 7700 + n]))
        cluster = bank.field_at(7800 + n, min(g.n, 1024), beta=1.8, wl_min=60.0, wl_max=400.0)
        g2 = g.with_n(cluster.shape[0])
        boulder_h = [piece_size(a, repo_root)[0] for a in crests]

        def end_boulders(row, s, tint_rng):
            """A boulder at each cut end of a row of ledges: [(asset, x, y, z, yaw, scale)]."""
            if not crests or len(row) == 0:
                return []
            res = []
            if len(row) == 1:
                ends = [(row[0], 1.0), (row[0], -1.0)]
            else:
                ends = [(row[0], None), (row[-1], None)]
            for q, (end, sign) in enumerate(ends):
                lg, x, y, z, dx, dz = end
                # along the row, outward from its end (away from its neighbour)
                ax, az = (dz, -dx)
                if sign is None:
                    other = row[1] if q == 0 else row[-2]
                    if (other[1] - x) * ax + (other[3] - z) * az > 0.0:
                        ax, az = -ax, -az
                else:
                    ax, az = ax * sign, az * sign
                bx = x + ax * 0.5 * lg.w * s + dx * lg.foot * s * 0.4
                bz = z + az * 0.5 * lg.w * s + dz * lg.foot * s * 0.4
                k = int(tint_rng.integers(0, len(crests)))
                bh = max(boulder_h[k], 0.3)
                ground = G.h(bx, bz)
                # tall enough, standing on its own ground, to cover the end's face to END_COVER
                need = (y + END_COVER * lg.h * s - ground) / ((1.0 - END_BOULDER_SINK) * bh)
                sc = float(np.clip(need, END_BOULDER_FIT * lg.h * s / bh, END_BOULDER_MAX * lg.h * s / bh))
                by = ground - END_BOULDER_SINK * bh * sc
                res.append((crests[k], bx, by, bz, float(tint_rng.uniform(0.0, 360.0)), sc))
            return res

        def lay_run(pts, s, ledge, rows_wanted, crest_run, draw_rng):
            """A crag of ledges on the run `pts` (along a contour), `rows_wanted` rows high: the
            rows [(ledge, x, y, z, dx, dz)], or [] where it will not seat."""
            downs = [G.down(x, z) for (x, z) in pts]
            if any(d is None for d in downs):
                return []
            # each ledge's front looks down the face, as its neighbours' do (so the ends meet)
            dirs = []
            for i in range(len(pts)):
                ax = sum(downs[j][0] for j in range(max(i - 1, 0), min(i + 2, len(pts))))
                az = sum(downs[j][1] for j in range(max(i - 1, 0), min(i + 2, len(pts))))
                m = math.hypot(ax, az)
                dirs.append((ax / m, az / m))
            crag = []
            step = LEDGE_STEP * ledge.w * s

            def in_out(cells):
                """Each module a little in or out of its neighbours, along its own front."""
                j = draw_rng.uniform(LEDGE_IN_OUT_M[0], LEDGE_IN_OUT_M[1], len(cells)) * s
                return [(x + dx * u, z + dz * u, dx, dz) for (x, z, dx, dz), u in zip(cells, j)]

            row = in_out([(p[0], p[1], d[0], d[1]) for p, d in zip(pts, dirs)])
            y = None
            prev = None
            for r in range(rows_wanted):
                if r == 0:
                    # the first row stands on the ground: its foot under the ground at the front of
                    # every ledge in it, and its back in the hill
                    lg = ledge
                    y = min(G.h(x + dx * lg.foot * s, z + dz * lg.foot * s) for (x, z, dx, dz) in row) \
                        - LEDGE_FOOT_EMBED_M * s
                    backs = [G.h(x - dx * lg.back * s, z - dz * lg.back * s) for (x, z, dx, dz) in row]
                    if y + lg.h * s - min(backs) > (LEDGE_BACK_SHOW_M + (0.6 if crest_run else 0.0)) * s:
                        return []
                    placed = row
                else:
                    # the next row up stands on this one, set back up the slope until its back is in
                    # the hill -- and no further than this one's top reaches, or it floats
                    lg = ledge if crest_run else draw_rng.choice(kit_list)
                    y2 = y + prev.h * s - LEDGE_SEAT_M * s
                    placed = None
                    # slid along the face by its own share of a module, so its seams do not stand
                    # over the row below's (the other way, or not at all, where that will not seat)
                    slide = float(draw_rng.uniform(*LEDGE_STAGGER)) * step
                    shifted = in_out(row)
                    for along in (slide, -slide, 0.0):
                        sb = LEDGE_SET_BACK_M * s
                        while sb <= (prev.back + prev.foot) * s + 1e-6:
                            cand = [(x - dx * sb + dz * along, z - dz * sb - dx * along, dx, dz)
                                    for (x, z, dx, dz) in shifted]
                            if all(G.h(x - dx * lg.back * s, z - dz * lg.back * s) >= y2 + (lg.h - LEDGE_BACK_SHOW_M) * s
                                   for (x, z, dx, dz) in cand):
                                placed = cand
                                break
                            sb += 0.25 * s
                        if placed is not None:
                            break
                    if placed is None or not all(clear1(x, z) for (x, z, _dx, _dz) in placed):
                        break
                    y = y2
                if r > 0 and not crest_run:
                    # A crag steps back irregularly: each row above the first is a shorter span of the
                    # one it stands on, and now and then broken by a missing module. Full rows stacked
                    # on full rows read up close as courses of loaves (the b4 Skerrow crag).
                    placed = course_span(placed, draw_rng)
                    if not placed:
                        break
                ceiling = ceiling_under_lines(H, g, np.array([p[0] for p in placed if p is not None]),
                                              np.array([p[1] for p in placed if p is not None]), claims, sight_k)
                if (y + lg.h * s > ceiling).any():
                    break
                for seg in _segments(placed):
                    crag.append([(lg, x, y, z, dx, dz) for (x, z, dx, dz) in seg])
                row = [p for p in placed if p is not None]
                prev = lg
            return crag

        def emit(crag, s, draw_rng, kind):
            # the whole crag's beds dip a few degrees one way along the face, as strata do: level
            # courses of one module are what read as masonry
            dip = float(draw_rng.uniform(*LEDGE_DIP_DEG)) if "ledge" in kind else 0.0
            sign = 1.0 if draw_rng.random() < 0.5 else -1.0
            for r, row in enumerate(crag):
                light = float(draw_rng.normal(0.0, 0.04))
                for (lg, x, y, z, dx, dz) in row:
                    yaw = _yaw(dx, dz) + float(draw_rng.uniform(-LEDGE_YAW_JITTER_DEG, LEDGE_YAW_JITTER_DEG))
                    # tipped about the foot toward one end of the run (along the face, (dz, -dx))
                    toward = math.degrees(math.atan2(-dx * sign, dz * sign))
                    put(lg.asset, x, y, z, yaw, s, dip, toward if dip > 0.0 else 0.0, grey(light))
                    taken.add(x, z, 0.5 * lg.w * s)
                    counts[kind] += 1
            for row in crag:
                for (a, bx, by, bz, yaw, sc) in end_boulders(row, s, draw_rng):
                    put(a, bx, by, bz, yaw, sc, 0.0, 0.0, "#ffffff")

        kit_list = list(kit)
        # --- the faces
        if kit:
            lr = np.random.default_rng(np.random.SeedSequence([seed, 7750 + n]))
            x, z = _candidates(lr, boxes[region.index], math.sqrt(10000.0 / RUN_SEEDS_HA))
            draw = lr.random(x.shape)
            s_ = np.hypot(sample_bilinear(gx, g, x, z), sample_bilinear(gz, g, x, z))
            gate = 0.5 + 0.5 * np.tanh(sample_bilinear(cluster, g2, x, z))
            keep = (sample_nearest(owner, g, x, z) == region.index) & (s_ >= FACE_SLOPE) \
                & (draw < smoothstep(1.0 - FACE_CLUSTER - 0.1, 1.0 - FACE_CLUSTER + 0.1, gate))
            idx = np.flatnonzero(keep)
            idx = idx[clear(x[idx], z[idx])]
            for k in idx[lr.permutation(idx.size)]:
                s = float(lr.uniform(*RUN_SCALE))
                want = int(lr.integers(RUN_LEN[0], RUN_LEN[1] + 1))
                rows = int(lr.integers(RUN_ROWS[0], RUN_ROWS[1] + 1))
                w = kit[0].w
                rad = 0.5 * w * s * 0.9

                def ok(px, pz, rad=rad):
                    if G.down(px, pz) is None:
                        return False
                    gxx, gzz = G.grad(px, pz)
                    return (math.hypot(gxx, gzz) >= 0.8 * FACE_SLOPE and clear1(px, pz)
                            and int(sample_nearest(owner, g, np.array([px]), np.array([pz]))[0]) == region.index
                            and not taken.hit(px, pz, rad))

                level = G.hs(float(x[k]), float(z[k]))
                pts = trace_contour(G, float(x[k]), float(z[k]), level, LEDGE_STEP * w * s, want, ok)
                if len(pts) < 2:
                    continue
                # the tallest ledge that seats on the gentlest of the run's ground
                sl = min(math.hypot(*G.grad(px, pz)) for (px, pz) in pts)
                fits = [lg for lg in kit if lg.h <= (lg.back + lg.foot) * sl + LEDGE_FOOT_EMBED_M + LEDGE_BACK_SHOW_M]
                ledge = fits[int(lr.integers(0, len(fits)))] if fits else kit[0]
                crag = lay_run(pts, s, ledge, rows, False, lr)
                emit(crag, s, lr, "ledge")
        elif faces:
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
                put(faces[int(pick[t])], px, py, pz, yaw, scale, lean, toward, grey(float(light[t])))
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
            cr = np.random.default_rng(np.random.SeedSequence([seed, 7760 + n]))
            seat_rng = np.random.default_rng(np.random.SeedSequence([seed, 7790 + n]))
            for t, k in enumerate(idx):
                if CREST_LEDGES and kit and s[k] >= CREST_LEDGE_SLOPE:
                    # steep enough to seat a ledge: a short run of the smallest, on the contour
                    sc = float(cr.uniform(*CREST_LEDGE_SCALE))
                    lg = kit[0]

                    def ok(px, pz, rad=0.45 * lg.w * sc):
                        return (clear1(px, pz) and not taken.hit(px, pz, rad)
                                and int(sample_nearest(owner, g, np.array([px]), np.array([pz]))[0]) == region.index)

                    pts = trace_contour(G, float(x[k]), float(z[k]), G.hs(float(x[k]), float(z[k])),
                                        LEDGE_STEP * lg.w * sc, int(cr.integers(CREST_RUN[0], CREST_RUN[1] + 1)), ok)
                    crag = lay_run(pts, sc, lg, 1, True, cr) if pts else []
                    if crag:
                        emit(crag, sc, cr, "crest_ledge")
                        continue
                ph = sizes[int(pick[t])][0]
                ground = float(sample_bilinear(H, g, np.array([x[k]]), np.array([z[k]]))[0])
                if ground + (1.0 - CREST_EMBED) * ph * scale[t] > ceiling[t]:
                    continue
                if taken.hit(float(x[k]), float(z[k]), 1.0):
                    continue
                # seated as the scatter's rock is (cells.seat_on_ground): leaned back with the crest's
                # slope and its downhill edge in the ground, and CREST_EMBED of it under at least.
                # Stood upright and sunk by its height alone, a 2 m boulder on a 1 in 2 crest stood
                # over a metre of air on its downhill side: "rocks jut from slopes".
                half = CELLS.asset_bounds(crests[int(pick[t])], repo_root)[0] * scale[t]
                ys, ln, tw = CELLS.seat_on_ground(H, g, np.array([x[k]], dtype=np.float64), np.array([z[k]], dtype=np.float64),
                                                  np.array([ground], dtype=np.float32), np.array([half]),
                                                  np.array([ph * scale[t]]), CELLS.SEAT_TILT,
                                                  (CREST_EMBED, CREST_EMBED), seat_rng)
                put(crests[int(pick[t])], x[k], float(ys[0]), z[k], yaw[t], scale[t], float(ln[0]), float(tw[0]), "#ffffff")
                if seat_rng.random() < CREST_KIN_P and float(ln[0]) > 0.0:
                    # smaller stones come down off it, below it on the slope
                    down = math.radians(float(tw[0]))
                    for _ in range(int(seat_rng.integers(CREST_KIN[0], CREST_KIN[1] + 1))):
                        a = down + float(seat_rng.normal(0.0, 0.5))
                        dist = half * float(seat_rng.uniform(1.4, 3.5))
                        kx, kz = float(x[k]) + math.cos(a) * dist, float(z[k]) + math.sin(a) * dist
                        if not clear(np.array([kx]), np.array([kz]))[0] or taken.hit(kx, kz, 0.5):
                            continue
                        ks = scale[t] * float(seat_rng.uniform(0.25, 0.5))
                        kk = int(seat_rng.integers(0, len(crests)))
                        kh = CELLS.asset_bounds(crests[kk], repo_root)
                        kg = float(sample_bilinear(H, g, np.array([kx]), np.array([kz]))[0])
                        ky, kln, ktw = CELLS.seat_on_ground(H, g, np.array([kx]), np.array([kz]), np.array([kg], dtype=np.float32),
                                                           np.array([kh[0] * ks]), np.array([kh[1] * ks]), CELLS.SEAT_TILT,
                                                           CELLS.SEAT_EMBED, seat_rng)
                        put(crests[kk], kx, float(ky[0]), kz, float(seat_rng.uniform(0.0, 360.0)), ks,
                            float(kln[0]), float(ktw[0]), "#ffffff")
                counts["crest"] += 1
    return out, counts


# --- the sea cliffs ------------------------------------------------------------------------------

def _dist_to_path(x: float, z: float, P: np.ndarray) -> float:
    a = P[:-1]
    b = P[1:]
    ab = b - a
    t = np.clip(((x - a[:, 0]) * ab[:, 0] + (z - a[:, 1]) * ab[:, 1]) / np.maximum((ab ** 2).sum(axis=1), 1e-9), 0.0, 1.0)
    d = np.hypot(x - (a[:, 0] + t * ab[:, 0]), z - (a[:, 1] + t * ab[:, 1]))
    return float(d.min())


def coast_walls(grid: Grid, H: np.ndarray, atlas: dict, owner: np.ndarray, regions: list, road_d: np.ndarray,
                road_w: np.ndarray, pads: list, claims: list, sight_k: dict, index: dict, seed: int,
                repo_root: str = ".", stacks: list = ()) -> tuple:
    """The sea cliffs dressed in ledges from the water to their tops. `pads` is [(x, z, radius,
    level)], `stacks` the shores' sea stacks ({x, z, r, top}). Returns ({(cx, cz): {asset_path:
    [rows]}}, counts)."""
    from . import cells as CELLS_
    from . import geography as GEO

    g = grid
    G = None
    kit_small: list = []
    boulders: list = []
    if not COAST_WALLS:
        return {}, {"walls": 0, "columns": 0, "wall_ledges": 0, "stack_ledges": 0}
    taken = _Taken()
    out: dict = {}
    counts = {"walls": 0, "columns": 0, "wall_ledges": 0, "stack_ledges": 0}
    by_index = {r.index: r for r in regions}

    def put(asset, x, y, z, yaw, scale, tint, lean=0.0, toward=0.0, stretch=None):
        row = [round(float(x), 2), round(float(y), 2), round(float(z), 2), round(float(yaw), 1),
               round(float(scale), 3), tint, round(float(lean), 1), round(float(toward), 1)]
        if stretch is not None:
            # the row's ninth field: the scale in the asset's own axes (the streamer's `row[8]`)
            row.append([round(float(scale * stretch[0]), 3), round(float(scale * stretch[1]), 3),
                        round(float(scale * stretch[2]), 3)])
        out.setdefault(g.written_cell(x, z), {}).setdefault(asset, []).append(row)

    def road_clear(x, z):
        j, i = g.clamp_index(*g.to_tex(np.array([x]), np.array([z])))
        return float(road_d[i[0], j[0]]) > float(road_w[i[0], j[0]]) * 0.5 + ROAD_CLEAR_M * 0.6

    def under_pad(x, z, y):
        for (px, pz, pr, lvl) in pads:
            if (px - x) ** 2 + (pz - z) ** 2 < (pr + WALL_PAD_CLEAR_M) ** 2 and y < lvl + WALL_PAD_HEADROOM_M:
                return True
        return False

    def strata(rng, kit, s, height):
        """The cliff's beds from its foot up: [(ledge, base y, tint, slide, kind)], `slide` the share
        of a module the bed is slid along the cliff and `kind` "soft", "hard" or "mid". They go on
        far past the atlas's height for the cliff: the land behind a cliff may stand higher than the
        cliff was drawn (the Tide Mouth's is 120 m on a 78 m line), and each column stops at its own
        top."""
        beds = []
        y = WALL_FOOT_M * s
        while y < max(height, WALL_STRATA_TOP_M):
            lg = kit[int(rng.integers(0, len(kit)))]
            c = int(round(255 * float(np.clip(1.0 + rng.normal(0.0, 0.05), 0.82, 1.0))))
            u = float(rng.random())
            # (never two soft beds together: four in a row left a band of the cliff 18 m deep bare)
            soft_ok = bool(beds) and beds[-1][4] != "soft"
            kind = "hard" if not beds else ("soft" if u < WALL_SOFT_SHARE and soft_ok else
                                            ("hard" if u < WALL_SOFT_SHARE + WALL_HARD_SHARE else "mid"))
            sy = float(rng.uniform(*WALL_BED_STRETCH))
            back = float(rng.uniform(*WALL_SET_BACK_M.get(kind, (0.0, 0.0))))
            dip = float(rng.uniform(*WALL_DIP_DEG)) * (1.0 if rng.random() < 0.7 else -1.0)
            beds.append((lg, y, "#%02x%02x%02x" % (c, c, c), float(rng.random()), kind, sy, back, dip))
            y += (lg.h * sy - LEDGE_SEAT_M) * s
        return beds

    def bay_at(x, z, phases):
        """True where the cliff is a bay (its mid beds weathered back), from a noise along it; never
        on a stack (`phases` None)."""
        if phases is None:
            return False
        a, b, c = phases
        w1, w2, w3 = WALL_BAY_WL_M
        v = (math.sin(x / w2 + a) + math.sin(z / w3 + b) + math.sin((x - z) / w1 + c)) / 3.0
        return v < WALL_BAY_T

    def column(x, z, dx, dz, s, beds, top_hint, phases, jr):
        """One column of the wall at (x, z) on its face, looking out along (dx, dz): its beds each slid
        along the cliff by their own share of a module, and each module a little in or out; the soft
        beds left out, and in a bay all but the hard ones."""
        # the wall's top just behind the face, and its foot just out from it
        top = max(G.h(x - dx * d, z - dz * d) for d in WALL_TOP_LOOK_M)
        foot = min(G.h(x + dx * d, z + dz * d) for d in WALL_FOOT_LOOK_M)
        if top - max(foot, 0.0) < 0.6 * WALL_MIN_M:
            return 0
        made = 0
        ceilings = None
        bay = bay_at(x, z, phases)
        step = LEDGE_STEP * beds[0][0].w * s
        for (lg, y, tint, slide, kind, sy, back, dip) in beds:
            hh_ = lg.h * sy * s
            if y + hh_ > top + WALL_OVERSHOOT_M:
                break
            u = float(jr.uniform(*LEDGE_IN_OUT_M)) * s
            if y + hh_ < -0.3 or kind == "soft" or (bay and kind != "hard"):
                continue
            broken = phases is not None
            if broken and jr.random() < WALL_GAP_P:
                continue
            # weathered in by the bed's own set-back, wandering along the cliff
            u -= back * s
            if phases is not None:
                u += WALL_WANDER_M * s * math.sin(x / 23.0 + z / 31.0 + y * 0.37 + phases[0])
            yy = y
            if broken and jr.random() < WALL_SLUMP_P:
                yy = y - float(jr.uniform(*WALL_SLUMP_M)) * s
            mid = y + 0.5 * hh_
            # where the wall's face stands at this bed's height: from behind the face out
            q = None
            prev_h = G.h(x - dx * WALL_FACE_LOOK_M[0], z - dz * WALL_FACE_LOOK_M[0])
            prev_d = -WALL_FACE_LOOK_M[0]
            d = prev_d + 0.5
            while d <= WALL_FACE_LOOK_M[1]:
                hh = G.h(x + dx * d, z + dz * d)
                if hh <= mid < prev_h:
                    f = (prev_h - mid) / max(prev_h - hh, 1e-6)
                    q = prev_d + f * (d - prev_d)
                    break
                prev_h, prev_d = hh, d
                d += 0.5
            if q is None:
                continue
            # on the wall, not out on the beach at its foot: a cove's low beds crossed the ground
            # twenty metres out on the sand
            if math.hypot(*G.grad(x + dx * q, z + dz * q)) < WALL_FACE_SLOPE:
                continue
            along = slide * step
            ox = x + dx * (q - WALL_SINK_M * s + u) + dz * along
            oz = z + dz * (q - WALL_SINK_M * s + u) - dx * along
            if under_pad(ox, oz, y) or not road_clear(ox, oz):
                continue
            if ceilings is None:
                ceilings = float(ceiling_under_lines(H, g, np.array([ox]), np.array([oz]), claims, sight_k)[0])
            if y + hh_ > ceilings:
                continue
            # the bed's dip, along the cliff ((dz, -dx) one way, the other for a negative dip)
            sgn = 1.0 if dip >= 0.0 else -1.0
            toward = math.degrees(math.atan2(-dx * sgn, dz * sgn))
            put(lg.asset, ox, yy, oz, _yaw(dx, dz), s, tint, abs(dip), toward, (1.0, sy, 1.0))
            made += 1
        if phases is not None and jr.random() < WALL_FALLEN_P:
            made += fallen(x, z, dx, dz, s, max(foot, 0.0) + 0.25 * (top - max(foot, 0.0)), jr)
        return made

    def fallen(x, z, dx, dz, s, high, jr):
        """The blocks come down from the cliff at (x, z), lying at its foot: boulders and broken
        ledges, tipped and half sunk, out on the ground 1 to 9 m from the face and never in deep water."""
        n = 0
        for _ in range(int(jr.integers(WALL_FALLEN[0], WALL_FALLEN[1] + 1))):
            d = float(jr.uniform(*WALL_FALLEN_OUT_M)) * s
            a = float(jr.normal(0.0, 0.5))
            ex, ez = dx * math.cos(a) - dz * math.sin(a), dz * math.cos(a) + dx * math.sin(a)
            # from the face's foot out: find where the ground stops falling
            fx, fz = x + ex * d, z + ez * d
            gy = G.h(fx, fz)
            # (on the beach or the platform or in the shallows, not in deep water nor up the face)
            if gy < -1.0 or gy > high or math.hypot(*G.grad(fx, fz)) > WALL_FACE_SLOPE \
                    or not road_clear(fx, fz) or under_pad(fx, fz, gy):
                continue
            if boulders and jr.random() < 0.6:
                a_ = boulders[int(jr.integers(0, len(boulders)))]
                sc = s * float(jr.uniform(0.7, 1.8))
                put(a_, fx, gy - 0.3 * sc, fz, float(jr.uniform(0.0, 360.0)), sc, "#ffffff",
                    float(jr.uniform(5.0, 30.0)), float(jr.uniform(-180.0, 180.0)))
            else:
                lg = kit_small[0]
                sc = s * float(jr.uniform(0.45, 0.8))
                put(lg.asset, fx, gy - 0.35 * lg.h * sc, fz, float(jr.uniform(0.0, 360.0)), sc, "#e8e8e8",
                    float(jr.uniform(18.0, 55.0)), float(jr.uniform(-180.0, 180.0)))
            n += 1
        counts["fallen"] = counts.get("fallen", 0) + n
        return 0

    walls = []
    for k, cl in enumerate(atlas.get("coast", {}).get("cliffs", [])):
        height = float(cl["height_m"])
        if height < WALL_MIN_M:
            continue
        P = GEO.resample_path(cl["path"], 10.0)
        mid = P[len(P) // 2]
        j, i = g.clamp_index(*g.to_tex(np.array([mid[0]]), np.array([mid[1]])))
        region = by_index.get(int(owner[i[0], j[0]]))
        kit = ledge_kit(index, region.art_short, repo_root) if region is not None else []
        if not kit:
            continue
        if G is None:
            G = _Ground(g, H)
        rng = np.random.default_rng(np.random.SeedSequence([seed, 7910 + k]))
        s = float(np.clip(height * WALL_SCALE_PER_M, *WALL_SCALE))
        beds = strata(rng, kit, s, height)
        kit_small = kit
        boulders = CELLS_.assets_for(index, "rocks/boulder", region.art_short)
        phases = tuple(float(v) for v in rng.uniform(0.0, 2.0 * math.pi, 3))
        jr = np.random.default_rng(np.random.SeedSequence([seed, 7930 + k]))
        walls.append((P, s, beds, height, phases))
        level = 0.5 * height
        step = LEDGE_STEP * kit[0].w * s
        counts["walls"] += 1

        def ok(px, pz, P=P, s=s):
            gxx, gzz = G.grad(px, pz)
            return (math.hypot(gxx, gzz) >= WALL_SLOPE_MIN and _dist_to_path(px, pz, P) <= WALL_REACH_M
                    and not taken.hit(px, pz, 0.45 * step))

        seg = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        for s0 in np.arange(0.5 * WALL_SEED_EVERY_M, seg[-1], WALL_SEED_EVERY_M):
            sx = float(np.interp(s0, seg, P[:, 0]))
            sz = float(np.interp(s0, seg, P[:, 1]))
            # the wall's face near this point of the atlas's line: along the line's normal, the
            # nearest crossing of the smoothed ground through the cliff's middle height
            tx = float(np.interp(s0 + 5.0, seg, P[:, 0])) - float(np.interp(s0 - 5.0, seg, P[:, 0]))
            tz = float(np.interp(s0 + 5.0, seg, P[:, 1])) - float(np.interp(s0 - 5.0, seg, P[:, 1]))
            m = math.hypot(tx, tz)
            if m < 1e-6:
                continue
            nx, nz = -tz / m, tx / m
            best = None
            for d in np.arange(-WALL_REACH_M, WALL_REACH_M, 2.0):
                a = G.hs(sx + nx * d, sz + nz * d) - level
                b = G.hs(sx + nx * (d + 2.0), sz + nz * (d + 2.0)) - level
                if a * b <= 0.0 and (best is None or abs(d) < abs(best)):
                    best = d
            if best is None:
                continue
            cx, cz = sx + nx * (best + 1.0), sz + nz * (best + 1.0)
            if taken.hit(cx, cz, 0.45 * step):
                continue
            pts = trace_contour(G, cx, cz, level, step, 100000, ok)
            for (px, pz) in pts:
                dn = G.down(px, pz)
                if dn is None or taken.hit(px, pz, 0.45 * step):
                    continue
                taken.add(px, pz, 0.45 * step)
                made = column(px, pz, dn[0], dn[1], s, beds, height, phases, jr)
                if made:
                    counts["columns"] += 1
                    counts["wall_ledges"] += made
    # the stacks: ringed with the strata of the cliff they stood out from
    sr = np.random.default_rng(np.random.SeedSequence([seed, 7990]))
    for st in stacks:
        if not walls:
            break
        P, s_wall, beds, height, _phases = min(walls, key=lambda w: _dist_to_path(st["x"], st["z"], w[0]))
        if _dist_to_path(st["x"], st["z"], P) > 2.0 * WALL_REACH_M:
            continue
        # (at the cliff's own scale, so its beds are the cliff's at the same heights)
        r = 0.85 * float(st["r"])
        count = max(3, int(math.ceil(2.0 * math.pi * r / (STACK_STEP * beds[0][0].w * s_wall))))
        for c in range(count):
            a = 2.0 * math.pi * c / count
            dx, dz = math.cos(a), math.sin(a)
            made = column(float(st["x"]) + dx * r, float(st["z"]) + dz * r, dx, dz, s_wall, beds, float(st["top"]),
                          None, sr)
            counts["stack_ledges"] += made
    return out, counts


# --- the waterfalls' steps -----------------------------------------------------------------------

## A waterfall's step (worldgen.falls) runs across the whole of its pad and out into its skirt. The
## dressing's face of ledges (poi_builders) owns it out to the pad's flat radius (`radius_flat_m` in
## pois.json, the pad's own radius); past that, the step was bare ground: an 11 m drop over one or
## two texels, its material rock but its texture stretched down it (the w4096b Kharrow shot). These
## are the step's face from the flat radius, less STEP_FACE_OVERLAP_M so no gap is left between,
## out to where the drop is under STEP_FACE_MIN_M: columns of the region's ledges from the foot to
## the top, their fronts at the face's foot, a module apart, their beds staggered.
STEP_FACE_OVERLAP_M = 0.5
STEP_FACE_MIN_M = 1.5
STEP_FACE_REACH_M = 40.0
STEP_FACE_SCALE = 1.0


def fall_faces(grid: Grid, H: np.ndarray, steps: dict, flat_radius: dict, owner: np.ndarray, regions: list,
               index: dict, seed: int, repo_root: str = ".") -> tuple:
    """The rock of each waterfall step's face past the dressing's own. `steps` is worldgen.falls'
    {POI id: Step}, `flat_radius` {POI id: the pad's flat radius, pois.json's `radius_flat_m`}.
    Returns ({(cx, cz): {asset: [rows]}}, ledges laid)."""
    g = grid
    G = _Ground(g, H)
    by_index = {r.index: r for r in regions}
    out: dict = {}
    laid = 0
    for k, (pid, st) in enumerate(sorted(steps.items())):
        if st.form == "cave":
            continue                                    # (a cave's face is its dressing's crag)
        j, i = g.clamp_index(*g.to_tex(np.array([st.x]), np.array([st.z])))
        region = by_index.get(int(owner[i[0], j[0]]))
        kit = ledge_kit(index, region.art_short, repo_root) if region is not None else []
        if not kit:
            continue
        rng = np.random.default_rng(np.random.SeedSequence([seed, 8100 + k]))
        s = STEP_FACE_SCALE
        fx, fz = float(st.fx), float(st.fz)
        px, pz = -fz, fx
        yaw = _yaw(fx, fz)
        step_m = LEDGE_STEP * kit[0].w * s
        start = float(flat_radius[pid]) - STEP_FACE_OVERLAP_M
        for behind, _drop in st.faces:
            for side in (1.0, -1.0):
                v = start + 0.5 * step_m                   # (the first column's inner end at `start`)
                while v <= STEP_FACE_REACH_M:
                    cx, cz = st.x + px * v * side, st.z + pz * v * side
                    fx0, fz0 = cx - fx * (behind - 1.0), cz - fz * (behind - 1.0)
                    tx0, tz0 = cx - fx * (behind + 3.0 + 1.5), cz - fz * (behind + 3.0 + 1.5)
                    foot, top = G.h(fx0, fz0), G.h(tx0, tz0)
                    if top - foot < STEP_FACE_MIN_M:
                        break
                    # the module's lip at the face's foot, its back in the hill behind the face
                    y = foot - LEDGE_FOOT_EMBED_M * s
                    r = 0
                    while y < top - 0.4 and r < 8:
                        lg = kit[int(rng.integers(0, len(kit)))] if r else kit[-1]
                        if y + lg.h * s > top + 0.6:
                            lg = kit[0]
                            if y + lg.h * s > top + 0.9:
                                y = top + 0.3 - lg.h * s          # the last course sunk to the top
                        back = 0.35 * r * s + float(rng.uniform(-0.15, 0.15)) * s
                        u = -behind + 1.0 - lg.foot * s - back
                        along = float(rng.uniform(-0.2, 0.2)) * step_m if r else 0.0
                        ox = cx + fx * u + px * along
                        oz = cz + fz * u + pz * along
                        c = int(round(255 * float(np.clip(1.0 + rng.normal(0.0, 0.05), 0.82, 1.0))))
                        row = [round(ox, 2), round(y, 2), round(oz, 2),
                               round(yaw + float(rng.uniform(-LEDGE_YAW_JITTER_DEG, LEDGE_YAW_JITTER_DEG)), 1),
                               round(s, 3), "#%02x%02x%02x" % (c, c, c), 0.0, 0.0]
                        out.setdefault(g.written_cell(ox, oz), {}).setdefault(lg.asset, []).append(row)
                        laid += 1
                        y += (lg.h - LEDGE_SEAT_M) * s
                        r += 1
                    v += step_m
    return out, laid
