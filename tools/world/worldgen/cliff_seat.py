"""Cliff pieces seated in their slope, not stood out of it (triage 42, 2026-09-28).

The forge's cliff face (gen_rocks.cliff_face) is a slab of bedded rock 10 to 24 m tall and 8 m
deep, massed with buttresses and an overhanging lip. `crags.cliff_faces` stood each one "as far
forward as its back is in the hill": it slid the piece out of the slope until the back of it only
just touched the ground, so its whole depth stood proud of the face. Measured on the installed
w4096e world, the middle of a piece's front stood a median 3.8 m out of the ground it dressed (the
worst tenth 7 m and more), leaned back only 0.85 of the face's angle (at most 40 degrees, so on a
45-degree slope the top stood out further than the foot), and scaled to the face's full height
from wherever the stack had got to, however narrow the steep ground was across the slope. The
user's "rock faces jut a little too much and make the terrain round them look unnatural".

A piece is seated here, the same way in the build (`crags.cliff_faces`) and over an installed
world (`tools/world/seat_cliffs.py`):

* **Orientation.** A plane is fitted to the ground under the piece's front; the piece is turned to
  look down it (its yaw jitter kept, within CLIFF_YAW_JITTER_DEG) and leaned back to lie in it
  (SEAT_LEAN_MAX_DEG at most), so its face is parallel to the slope's, not stood up out of it.
* **Size.** Its height along the slope is held to the face's (the steep ground's foot to its top
  along the fall line, SEAT_RELIEF_FIT), and its width to the steep ground's across it
  (SEAT_WIDTH_FIT).
* **Embedding.** It is moved along the slope's normal until the middle of its front (the median of
  the front surface, read off the model's own mesh) stands SEAT_PROUD_M out of the ground: its
  buttresses stand out of the terrain and its gullies go into it, so the face is the rock's.
* **Checks.** A piece whose front still stands more than `proud_max` out anywhere (its worst tenth:
  a flat piece on a face that curves away), or whose back shows out of the hill, is made smaller
  and tried again; one that cannot be seated at CLIFF_SCALE's least goes. So does one on ground
  gentler than SEAT_MIN_SLOPE_DEG (no rock stands out of a grass bank), and one with no other
  piece within SEAT_LONE_GAP_M of its edge (a single slab alone on a knoll reads as dropped there).

The scatter row format already carries a lean (`[x, y, z, yaw, scale, tint, lean, toward]`,
WorldStreamer.instance_transform), and the pieces' colliders are built from the same rows, so the
collision moves with the rock.
"""
from __future__ import annotations

import json
import math
import os
import struct

import numpy as np

from .grid import Grid, sample_bilinear

## a piece stands on ground at least this steep (the plane fitted under its front), or it goes;
## the terrain paints scree from 38-44 degrees and bare rock from 47-50 (surface.STEEP)
SEAT_MIN_SLOPE_DEG = 38.0
## the most a piece leans back off upright to lie in its slope
SEAT_LEAN_MAX_DEG = 52.0
## how far the middle of a piece's front stands out of the ground, along its normal (metres)
SEAT_PROUD_M = 0.4
## how far its worst tenth may stand out: this, plus a share of its depth at its scale (the
## model's own relief, buttress to gully, is about a fifth of its depth)
SEAT_PROUD_MAX_M = 1.2
SEAT_PROUD_MAX_SHARE = 0.25
## how much of its back may stand out of the hill (vertically, metres; crags.CLIFF_BACK_CLEAR_M)
SEAT_BACK_CLEAR_M = 0.2
## its length along the slope against the face's, and its width against the steep ground's across
## the slope (a piece may reach a little past both: its ends and crest are ragged)
SEAT_RELIEF_FIT = 1.15
SEAT_WIDTH_FIT = 1.35
## where a face ends, up, down or across: the ground eases under this slope (crags.CLIFF_EASE)
SEAT_EASE = 0.7
## a piece with no other within this of its edge goes
SEAT_LONE_GAP_M = 8.0
## how small a piece is made before it goes, and by how much at a time
SEAT_SCALE_MIN = 0.5
SEAT_SHRINK = 0.82
SEAT_TRIES = 5

FACE_PART = "_cliff_face_"

_PROFILES: dict = {}


def _glb_positions(path: str) -> np.ndarray | None:
    """The first mesh's vertex positions in a .glb (the LOD0; glTF is Y up, +z front, as Godot)."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    n = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + n])
    off = 20 + n
    blen = struct.unpack("<I", data[off:off + 4])[0]
    blob = data[off + 8:off + 8 + blen]
    acc = j["accessors"][j["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    view = j["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 12)
    raw = np.frombuffer(blob, dtype=np.uint8, count=stride * (acc["count"] - 1) + 12, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(acc["count"], 12), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(np.float32).reshape(-1, 3).astype(np.float64)


class Profile:
    """A cliff piece's shape at scale one: its bounds, points on its front surface (the most
    forward vertex in each of a grid of columns across it and bins up it, from its mesh; the box's
    front where there is no mesh) and on its back."""

    def __init__(self, lo: np.ndarray, hi: np.ndarray, front: np.ndarray, back: np.ndarray):
        self.lo, self.hi, self.front, self.back = lo, hi, front, back
        # the front's grid at the box's back: where the piece meets the hill however it stands
        self.rear = front.copy()
        self.rear[:, 2] = lo[2]
        self.w = float(hi[0] - lo[0])
        self.h = float(hi[1] - lo[1])
        self.d = float(hi[2] - lo[2])


def profile(asset: str, repo_root: str, nx: int = 9, ny: int = 9) -> Profile:
    key = (asset, os.path.abspath(repo_root))
    if key in _PROFILES:
        return _PROFILES[key]
    rel = asset.replace("res://", "game/", 1)
    base = os.path.join(repo_root, os.path.splitext(rel)[0])
    lo = hi = None
    try:
        with open(base + ".meta.json", "r", encoding="utf-8") as f:
            b = json.load(f).get("bounds") or {}
        lo, hi = np.array(b["min"], dtype=np.float64), np.array(b["max"], dtype=np.float64)
    except (OSError, ValueError, KeyError):
        pass
    v = _glb_positions(base + ".glb")
    if v is not None and len(v):
        lo, hi = v.min(axis=0), v.max(axis=0)
    if lo is None:
        lo, hi = np.array([-10.0, 0.0, -4.0]), np.array([10.0, 16.0, 4.0])
    xs = (np.arange(nx) + 0.5) / nx * 0.84 + 0.08
    ys = (np.arange(ny) + 0.5) / ny * 0.9 + 0.05
    if v is not None and len(v):
        fx = (v[:, 0] - lo[0]) / max(hi[0] - lo[0], 1e-6)
        fy = (v[:, 1] - lo[1]) / max(hi[1] - lo[1], 1e-6)
        xi = np.floor((fx - 0.08) / 0.84 * nx).astype(int)
        yi = np.floor((fy - 0.05) / 0.9 * ny).astype(int)
        ok = (xi >= 0) & (xi < nx) & (yi >= 0) & (yi < ny)
        F = np.full((ny, nx), -np.inf)
        B = np.full((ny, nx), np.inf)
        np.maximum.at(F, (yi[ok], xi[ok]), v[ok, 2])
        np.minimum.at(B, (yi[ok], xi[ok]), v[ok, 2])
        front = [[lo[0] + x * (hi[0] - lo[0]), lo[1] + y * (hi[1] - lo[1]), F[a, b]]
                 for a, y in enumerate(ys) for b, x in enumerate(xs) if np.isfinite(F[a, b])]
        back = [[lo[0] + x * (hi[0] - lo[0]), lo[1] + y * (hi[1] - lo[1]), B[a, b]]
                for a, y in enumerate(ys) for b, x in enumerate(xs)
                if np.isfinite(B[a, b]) and y <= 0.85 and 0.2 <= x <= 0.8]
    else:
        front = [[lo[0] + x * (hi[0] - lo[0]), lo[1] + y * (hi[1] - lo[1]), hi[2]] for y in ys for x in xs]
        back = []
    if not back:
        back = [[lo[0] + x * (hi[0] - lo[0]), lo[1] + y * (hi[1] - lo[1]), lo[2]]
                for y in np.linspace(0.0, 0.8, 5) for x in np.linspace(0.2, 0.8, 5)]
    p = Profile(lo, hi, np.array(front, dtype=np.float64), np.array(back, dtype=np.float64))
    _PROFILES[key] = p
    return p


def transform(row: list, local: np.ndarray) -> np.ndarray:
    """World points of asset-local `local` under a row (crags.row_point, vectorised over the
    uniform scale and the lean)."""
    p = np.asarray(local, dtype=np.float64) * (np.asarray(row[8], dtype=np.float64) if len(row) > 8 else float(row[4]))
    a = math.radians(float(row[3]))
    c, s = math.cos(a), math.sin(a)
    p = np.stack([p[:, 0] * c + p[:, 2] * s, p[:, 1], -p[:, 0] * s + p[:, 2] * c], axis=1)
    if len(row) > 7 and float(row[6]) != 0.0:
        t = math.radians(float(row[7]))
        n = np.array([math.sin(t), 0.0, -math.cos(t)])     # UP x (cos t, 0, sin t), unit
        th = math.radians(float(row[6]))
        p = p * math.cos(th) + np.cross(n, p) * math.sin(th) + np.outer(p @ n, n) * (1.0 - math.cos(th))
    return p + np.array([float(row[0]), float(row[1]), float(row[2])])


def plane(H: np.ndarray, g: Grid, x: np.ndarray, z: np.ndarray) -> tuple:
    """The least-squares plane y = a + b (x - mx) + c (z - mz) through the ground at the points:
    (b, c), the ground's gradient over them."""
    y = sample_bilinear(H, g, x, z).astype(np.float64)
    A = np.stack([np.ones_like(x), x - x.mean(), z - z.mean()], axis=1)
    sol, *_ = np.linalg.lstsq(A, y, rcond=None)
    return float(sol[1]), float(sol[2])


def protrusion(row: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple) -> np.ndarray:
    """How far each point of the piece's front stands out of the ground: its height over the
    ground under it, along the ground's own normal there (negative: in the hill)."""
    pts = transform(row, prof.front)
    gy = sample_bilinear(H, g, pts[:, 0], pts[:, 2]).astype(np.float64)
    gx = sample_bilinear(Hs_grad[0], g, pts[:, 0], pts[:, 2]).astype(np.float64)
    gz = sample_bilinear(Hs_grad[1], g, pts[:, 0], pts[:, 2]).astype(np.float64)
    return (pts[:, 1] - gy) / np.sqrt(1.0 + gx * gx + gz * gz)


def back_show(row: list, prof: Profile, H: np.ndarray, g: Grid) -> float:
    """How far the most exposed point of the piece's back stands over the ground (vertically)."""
    pts = transform(row, prof.back)
    gy = sample_bilinear(H, g, pts[:, 0], pts[:, 2])
    return float(np.max(pts[:, 1] - gy))


def _steep_run(Hs_grad: tuple, g: Grid, x: float, z: float, dx: float, dz: float, reach: float) -> float:
    """How far from (x, z) along (dx, dz) the ground stays at least SEAT_EASE steep."""
    gx, gz = Hs_grad
    d = np.arange(1.0, reach + 1.0, 1.0)
    px, pz = x + dx * d, z + dz * d
    s = np.hypot(sample_bilinear(gx, g, px, pz), sample_bilinear(gz, g, px, pz))
    easy = np.nonzero(s < SEAT_EASE)[0]
    return float(d[easy[0]]) if easy.size else float(reach)


def proud_max(prof: Profile, sc: float) -> float:
    return SEAT_PROUD_MAX_M + SEAT_PROUD_MAX_SHARE * prof.d * sc


def _wrap(a: float) -> float:
    return (a + 180.0) % 360.0 - 180.0


def _orient(r: list, pts: np.ndarray, H: np.ndarray, g: Grid, yaw_jitter: float) -> tuple | None:
    """Turn and lean row `r` in place to lie in the plane of the ground under the world points
    `pts`. Returns that plane's gradient (b, c), or None where it is flat."""
    b, c = plane(H, g, pts[:, 0], pts[:, 2])
    m = math.hypot(b, c)
    if m < 1e-6:
        return None
    theta = math.degrees(math.atan(m))
    down = math.degrees(math.atan2(-b, -c))                   # the row yaw that faces downhill
    r[3] = round(down + max(-yaw_jitter, min(yaw_jitter, _wrap(float(r[3]) - down))), 1)
    r[6] = round(max(0.0, min(SEAT_LEAN_MAX_DEG, 90.0 - theta)), 1)
    r[7] = round(math.degrees(math.atan2(c, b)), 1)           # its top toward uphill
    return b, c


def _embed(r: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple, grad: tuple) -> None:
    """Move row `r` in place along the normal of the plane `grad` until the median of its front
    stands SEAT_PROUD_M out of the ground."""
    b, c = grad
    nrm = np.array([-b, 1.0, -c]) / math.sqrt(1.0 + b * b + c * c)
    for _k in range(4):
        move = float(np.median(protrusion(r, prof, H, g, Hs_grad))) - SEAT_PROUD_M
        if abs(move) < 0.05:
            break
        r[0] = round(float(r[0]) - move * nrm[0], 2)
        r[1] = round(float(r[1]) - move * nrm[1], 2)
        r[2] = round(float(r[2]) - move * nrm[2], 2)


def seat(row: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple, yaw_jitter: float = 10.0,
         scale_min: float = SEAT_SCALE_MIN) -> tuple:
    """(the row seated in its slope, "") or (None, why it goes). `Hs_grad` is the smoothed ground's
    (gx, gz)."""
    if seated(row, prof, H, g, Hs_grad):
        return list(row), ""
    r = list(row[:8]) + [0.0] * max(0, 8 - len(row))
    sc = float(r[4])
    why = "proud"
    for _try in range(SEAT_TRIES):
        r[4] = round(sc, 3)
        # first to the ground under its back (a piece stood out of the face has its front over
        # the ground below the face), into it, then again to the ground under its front
        grad = _orient(r, transform(r, prof.rear), H, g, yaw_jitter)
        if grad is None:
            return None, "gentle"
        _embed(r, prof, H, g, Hs_grad, grad)
        for _k in range(2):
            grad = _orient(r, transform(r, prof.front), H, g, yaw_jitter)
            if grad is None:
                return None, "gentle"
            _embed(r, prof, H, g, Hs_grad, grad)
        b, c = grad
        m = math.hypot(b, c)
        if math.degrees(math.atan(m)) < SEAT_MIN_SLOPE_DEG:
            # a smaller piece, nearer its foot, may stand on the steep part of it
            why = "gentle"
            sc *= SEAT_SHRINK
            if sc < scale_min:
                return None, why
            continue
        # its size against the face's: along the fall line through its middle, and across it
        fit = size_fit(r, prof, g, Hs_grad, grad)
        if fit < 1.0 - 1e-3:
            if sc * fit < scale_min:
                return None, "small"
            sc = sc * fit
            continue
        p = protrusion(r, prof, H, g, Hs_grad)
        if float(np.percentile(p, 90)) <= proud_max(prof, sc) and back_show(r, prof, H, g) <= SEAT_BACK_CLEAR_M:
            return r + list(row[8:]), ""
        why = "proud"
        sc *= SEAT_SHRINK
        if sc < scale_min:
            return None, why
    return None, why


def seated(row: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple) -> bool:
    """Whether a row already meets every rule, so seating it again leaves it as it is (the sweep
    over installed cells is idempotent)."""
    if len(row) < 8:
        return False
    pts = transform(row, prof.front)
    b, c = plane(H, g, pts[:, 0], pts[:, 2])
    m = math.hypot(b, c)
    if m < 1e-6 or math.degrees(math.atan(m)) < SEAT_MIN_SLOPE_DEG:
        return False
    if abs(float(row[6]) - min(SEAT_LEAN_MAX_DEG, 90.0 - math.degrees(math.atan(m)))) > 1.5:
        return False
    p = protrusion(row, prof, H, g, Hs_grad)
    return abs(float(np.median(p)) - SEAT_PROUD_M) < 0.1 and float(np.percentile(p, 90)) <= proud_max(prof, float(row[4])) \
        and size_fit(row, prof, g, Hs_grad, (b, c)) >= 1.0 - 1e-3 and back_show(row, prof, H, g) <= SEAT_BACK_CLEAR_M


def size_fit(r: list, prof: Profile, g: Grid, Hs_grad: tuple, grad: tuple) -> float:
    """The most the piece may be scaled by where it stands: its length up the slope against the
    face's (SEAT_RELIEF_FIT), its width against the steep ground's across the slope (SEAT_WIDTH_FIT).
    Under 1, it is too big for its face."""
    b, c = grad
    m = math.hypot(b, c)
    dx, dz = -b / m, -c / m                                   # downhill, unit
    mid = transform(r, prof.front).mean(axis=0)
    up_m = _steep_run(Hs_grad, g, mid[0], mid[2], -dx, -dz, 150.0)
    down_m = _steep_run(Hs_grad, g, mid[0], mid[2], dx, dz, 150.0)
    across = _steep_run(Hs_grad, g, mid[0], mid[2], -dz, dx, 60.0) + _steep_run(Hs_grad, g, mid[0], mid[2], dz, -dx, 60.0)
    slope_len = (up_m + down_m) * math.sqrt(1.0 + m * m)     # along the slope, not across the map
    sc = float(r[4])
    return min(SEAT_RELIEF_FIT * slope_len / (prof.h * sc), SEAT_WIDTH_FIT * across / (prof.w * sc))


def drop_lone(pieces: list) -> list:
    """Of [(key, asset, row, half_width)], a keep flag each: False where no other piece's edge is
    within SEAT_LONE_GAP_M of its own."""
    if not pieces:
        return []
    from scipy.spatial import cKDTree

    xz = np.array([(float(p[2][0]), float(p[2][2])) for p in pieces])
    rad = np.array([float(p[3]) for p in pieces])
    tree = cKDTree(xz)
    reach = 2.0 * float(rad.max()) + SEAT_LONE_GAP_M
    keep = []
    for k in range(len(pieces)):
        near = tree.query_ball_point(xz[k], reach)
        keep.append(any(q != k and math.hypot(*(xz[q] - xz[k])) < rad[q] + rad[k] + SEAT_LONE_GAP_M for q in near))
    return keep


def keep_not_lone(pieces: list) -> list:
    """drop_lone until none is left alone (one going can leave its only neighbour alone)."""
    keep = [True] * len(pieces)
    while True:
        idx = [k for k in range(len(pieces)) if keep[k]]
        now = drop_lone([pieces[k] for k in idx])
        if all(now):
            return keep
        for k, n in zip(idx, now):
            keep[k] = n


def smoothed_grad(H: np.ndarray, g: Grid) -> tuple:
    from scipy import ndimage

    Hs = ndimage.gaussian_filter(H.astype(np.float32), 1.0)
    gz, gx = np.gradient(Hs, g.spacing)
    return gx.astype(np.float32), gz.astype(np.float32)


def settle(buckets: dict, H: np.ndarray, g: Grid, repo_root: str = ".", yaw_jitter: float = 10.0) -> dict:
    """In place: every cliff face piece in `buckets` ({key: {asset: [rows]}}) seated, and those that
    cannot be, or stand alone, taken out; a piece that moves into another cell is filed there.
    Returns counts and the kept pieces' footprints [(x, z, half width)]."""
    Hs_grad = smoothed_grad(H, g)
    counts = {"pieces": 0, "seated": 0, "gentle": 0, "small": 0, "proud": 0, "lone": 0}
    placed = []
    for key in list(buckets):
        by = buckets[key]
        for asset in list(by):
            if FACE_PART not in asset:
                continue
            prof = profile(asset, repo_root)
            for row in by[asset]:
                counts["pieces"] += 1
                new, why = seat(list(row), prof, H, g, Hs_grad, yaw_jitter)
                if new is None:
                    counts[why] += 1
                    continue
                placed.append((key, asset, new, 0.5 * prof.w * float(new[4])))
            del by[asset]
    keep = keep_not_lone(placed)
    feet = []
    for (key, asset, row, half), k in zip(placed, keep):
        if not k:
            counts["lone"] += 1
            continue
        counts["seated"] += 1
        buckets.setdefault(g.written_cell(row[0], row[2]), {}).setdefault(asset, []).append(row)
        feet.append((float(row[0]), float(row[2]), half))
    counts["feet"] = feet
    return counts


def measure(buckets: dict, H: np.ndarray, g: Grid, repo_root: str = ".") -> dict:
    """What the cliff face pieces are like where they stand, one row each: how far the middle of
    its front stands out of the ground (the median over its front surface, along the ground's
    normal), its worst tenth, its scale against what its face allows (size_fit: over 1 it is too
    big), the slope under its front, how much of its back shows, its scale and its lean."""
    Hs_grad = smoothed_grad(H, g)
    rows = []
    for by in buckets.values():
        for asset, rs in by.items():
            if FACE_PART not in asset:
                continue
            prof = profile(asset, repo_root)
            for r in rs:
                pts = transform(r, prof.front)
                b, c = plane(H, g, pts[:, 0], pts[:, 2])
                m = math.hypot(b, c)
                p = protrusion(r, prof, H, g, Hs_grad)
                over = 1.0 / max(size_fit(r, prof, g, Hs_grad, (b, c)), 1e-3) if m > 1e-6 else float("inf")
                rows.append((float(np.median(p)), float(np.percentile(p, 90)), over,
                             math.degrees(math.atan(m)), back_show(r, prof, H, g), float(r[4]),
                             float(r[6]) if len(r) > 6 else 0.0))
    return {"rows": np.array(rows, dtype=np.float64).reshape(-1, 7)}
