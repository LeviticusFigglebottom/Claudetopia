"""Cliff pieces seated in their slope, not stood out of it (triage 42, 2026-09-28).

The forge's cliff face (gen_rocks.cliff_face) is a slab of bedded rock 10 to 24 m tall and 8 m
deep, massed with buttresses and an overhanging lip. `crags.cliff_faces` stood each one "as far
forward as its back is in the hill": it slid the piece out of the slope until the back of it only
just touched the ground, so its whole depth stood proud of the face. Measured on the installed
w4096e world, the middle of a piece's front stood a median 5.9 m out of the ground it dressed (a
tenth of pieces 12 m and more); a third of them stood over ground under 38 degrees (their fronts
out over the foot of the face, or on a bank that never needed rock); they leaned back only 0.85 of
the face's angle (at most 40 degrees); and each was scaled to the face's full height from wherever
the stack had got to, however narrow the steep ground across the slope. The user's "rock faces jut
a little too much and make the terrain round them look unnatural".

A piece is seated here, the same way in the build (`crags.cliff_faces`) and over an installed
world (`tools/world/seat_cliffs.py`):

* **Orientation.** A plane is fitted to the ground under the piece's front; the piece is turned to
  look down it (its yaw jitter kept, within CLIFF_YAW_JITTER_DEG) and leaned back to lie in it
  (SEAT_LEAN_MAX_DEG at most), so its face is parallel to the slope's, not stood up out of it.
* **Size.** Its height along the slope is held to the face's (the steep ground's foot to its top
  along the fall line, SEAT_RELIEF_FIT), and its width to the steep ground's across it
  (SEAT_WIDTH_FIT).
* **Embedding.** It is moved along the slope's normal until the lowest fifth of its front (read off
  the model's own mesh: its gullies and its lower edge) stands SEAT_SHOW_M out of the ground: its
  gullies at the ground, its buttresses and beds a metre or two out, so the face is the rock's and
  its edges meet the slope.
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
## how deep a piece goes in: its front's lowest SEAT_SHOW_PCT percent (its gullies and its lower
## edge) stand SEAT_SHOW_M out of the ground, along the ground's normal, and the rest of its face
## (its buttresses and beds) stands out further. Its median, 0.4 m out, left a Skerrow wall reading
## as earth with stripes of rock down it (the first after-sheet): the face is the rock's, not the
## terrain's with rock showing through
SEAT_SHOW_PCT = 20.0
SEAT_SHOW_M = 0.15
## how far its worst tenth may stand out: its own relief (its front's 90th percentile over its
## 20th, 1.1 to 3.9 m at scale one over the fifteen pieces), plus this where the ground under it is
## not a plane (a nose the face turns round, a hollow): more, and it is made smaller or goes
SEAT_CURVE_M = 1.5
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
## a piece already within this of lying in its plane, with its front where it should be, is left
## where it is (the plane under a piece moves a little as it is moved in, so a second pass would
## otherwise nudge every piece again)
SEATED_SLACK = 0.1
## ... and whose front is within this of the plane's normal (it was the lean alone, within 5
## degrees: a piece turned 10 degrees off the fall line stood rolled out of the plane by as much),
## and turned in it no more than this
SEATED_TILT_TOL_DEG = 3.0
SEATED_TWIST_MAX_DEG = 25.0

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
        # its own relief, gully to buttress
        self.spread = float(np.percentile(front[:, 2], 90) - np.percentile(front[:, 2], SEAT_SHOW_PCT))
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


def front_level(p: np.ndarray) -> float:
    """Where a piece's front stands against the ground, for embedding it: SEAT_SHOW_PCT of it lower."""
    return float(np.percentile(p, SEAT_SHOW_PCT))


def proud_max(prof: Profile, sc: float) -> float:
    return SEAT_SHOW_M + prof.spread * sc + SEAT_CURVE_M


def _wrap(a: float) -> float:
    return (a + 180.0) % 360.0 - 180.0


def yaw_matrix(yaw_deg: float) -> np.ndarray:
    """Basis(UP, yaw): a row's turn (local +z to (sin a, 0, cos a))."""
    a = math.radians(yaw_deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def lean_matrix(lean_deg: float, toward_deg: float) -> np.ndarray:
    """A row's lean: `lean` degrees about UP x (cos t, 0, sin t), its top toward t
    (WorldStreamer.instance_transform)."""
    if lean_deg == 0.0:
        return np.eye(3)
    t = math.radians(toward_deg)
    n = np.array([math.sin(t), 0.0, -math.cos(t)])
    th = math.radians(lean_deg)
    K = np.array([[0.0, -n[2], n[1]], [n[2], 0.0, -n[0]], [-n[1], n[0], 0.0]])
    return np.eye(3) * math.cos(th) + K * math.sin(th) + np.outer(n, n) * (1.0 - math.cos(th))


def row_basis(row: list) -> np.ndarray:
    """A row's rotation (no scale): its columns are where the piece's x (width), y (up) and z
    (front) point."""
    lean = float(row[6]) if len(row) > 7 else 0.0
    toward = float(row[7]) if len(row) > 7 else 0.0
    return lean_matrix(lean, toward) @ yaw_matrix(float(row[3]))


def row_angles(R: np.ndarray) -> tuple:
    """(yaw, lean, toward) of a row whose rotation is R. The format's lean tilts the piece's up
    anywhere (lean off vertical, toward a bearing) and its yaw turns it about its own up, so it
    holds any rotation: a piece can roll with ground that tilts across it as well as lean back."""
    up = R[:, 1]
    lean = math.degrees(math.acos(max(-1.0, min(1.0, float(up[1])))))
    toward = math.degrees(math.atan2(float(up[2]), float(up[0]))) if lean > 1e-6 else 0.0
    Y = lean_matrix(lean, toward).T @ R
    yaw = math.degrees(math.atan2(float(Y[0, 2]), float(Y[2, 2])))
    return yaw, lean, toward


def plane_frame(b: float, c: float) -> tuple:
    """(N, u, x0) for the plane with gradient (b, c): the normal a piece's front takes (no more
    than SEAT_LEAN_MAX_DEG off vertical: on gentler ground its face stands steeper than the
    ground), up that face (up the fall line) and across it, left to right as the piece looks out."""
    m = math.hypot(b, c)
    th = max(math.atan(m), math.radians(90.0 - SEAT_LEAN_MAX_DEG))
    dh = np.array([-b / m, 0.0, -c / m])                      # downhill, level
    N = dh * math.sin(th) + np.array([0.0, 1.0, 0.0]) * math.cos(th)
    u = -dh * math.cos(th) + np.array([0.0, 1.0, 0.0]) * math.sin(th)
    return N, u, np.cross(u, N)


def twist(row: list, b: float, c: float) -> float:
    """How far a row is turned in the plane (b, c) off facing straight down it, degrees: its width's
    angle off the level line across the slope."""
    N, u, x0 = plane_frame(b, c)
    X = row_basis(row)[:, 0]
    X = X - (X @ N) * N
    return math.degrees(math.atan2(float(X @ u), float(X @ x0)))


def _orient(r: list, pts: np.ndarray, H: np.ndarray, g: Grid, yaw_jitter: float) -> tuple | None:
    """Turn and lean row `r` in place to lie in the plane of the ground under the world points
    `pts`: its front along the plane's normal, turned in the plane by its own twist (within
    `yaw_jitter`). Returns that plane's gradient (b, c), or None where it is flat.

    (It was yawed about the vertical, then leaned back about the level line across the fall: with
    its yaw jitter the piece rolled out of the plane by the jitter, one edge standing out and the
    other in; and it could not roll with ground tilting across it. The row's lean and toward tilt
    its up anywhere, so the whole rotation is expressed: triage 42's leftovers.)"""
    b, c = plane(H, g, pts[:, 0], pts[:, 2])
    m = math.hypot(b, c)
    if m < 1e-6:
        return None
    psi = math.radians(max(-yaw_jitter, min(yaw_jitter, twist(r, b, c))))
    N, u, x0 = plane_frame(b, c)
    X = x0 * math.cos(psi) + u * math.sin(psi)
    Y = u * math.cos(psi) - x0 * math.sin(psi)
    yaw, lean, toward = row_angles(np.stack([X, Y, N], axis=1))
    r[3], r[6], r[7] = round(yaw, 1), round(lean, 1), round(toward, 1)
    return b, c


def _embed(r: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple, grad: tuple) -> None:
    """Move row `r` in place along the normal of the plane `grad` until its front's `front_level`
    stands SEAT_SHOW_M out of the ground."""
    b, c = grad
    nrm = np.array([-b, 1.0, -c]) / math.sqrt(1.0 + b * b + c * c)
    for _k in range(6):
        move = front_level(protrusion(r, prof, H, g, Hs_grad)) - SEAT_SHOW_M
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
        # first, where it stands out, to the ground under its back (a piece stood out of the face
        # has its front over the ground below the face) and into it; then to the ground under its
        # front (the back of a piece already in the face is under the ground above it)
        if front_level(protrusion(r, prof, H, g, Hs_grad)) > 1.0:
            grad = _orient(r, transform(r, prof.rear), H, g, yaw_jitter)
            if grad is None:
                return None, "gentle"
            _embed(r, prof, H, g, Hs_grad, grad)
        # (until the plane under it no longer moves as it goes in, so a piece seated once is
        # `seated` and a second pass leaves it be)
        for _k in range(6):
            lean0, yaw0 = float(r[6]), float(r[3])
            grad = _orient(r, transform(r, prof.front), H, g, yaw_jitter)
            if grad is None:
                return None, "gentle"
            _embed(r, prof, H, g, Hs_grad, grad)
            if _k and abs(float(r[6]) - lean0) < 0.5 and abs(_wrap(float(r[3]) - yaw0)) < 1.0:
                break
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
        if abs(front_level(p) - SEAT_SHOW_M) < 0.1 and float(np.percentile(p, 90)) <= proud_max(prof, sc) \
                and back_show(r, prof, H, g) <= SEAT_BACK_CLEAR_M and seated(r, prof, H, g, Hs_grad):
            return r + list(row[8:]), ""
        why = "proud"
        sc *= SEAT_SHRINK
        if sc < scale_min:
            return None, why
    return None, why


def seated(row: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple) -> bool:
    """Whether a row already meets every rule, within SEATED_SLACK, so seating it again leaves it
    as it is: the rules for keeping a piece are a little looser than for placing one, or a piece
    seated at the edge of one (a plane of 38.1 degrees) could fail it on a second pass, and the
    sweep over installed cells would not be idempotent."""
    if len(row) < 8:
        return False
    pts = transform(row, prof.front)
    b, c = plane(H, g, pts[:, 0], pts[:, 2])
    m = math.hypot(b, c)
    if m < 1e-6 or math.degrees(math.atan(m)) < SEAT_MIN_SLOPE_DEG - 2.0:
        return False
    N, _u, _x0 = plane_frame(b, c)
    if math.degrees(math.acos(min(1.0, float(row_basis(row)[:, 2] @ N)))) > SEATED_TILT_TOL_DEG \
            or abs(twist(row, b, c)) > SEATED_TWIST_MAX_DEG:
        return False
    p = protrusion(row, prof, H, g, Hs_grad)
    return abs(front_level(p) - SEAT_SHOW_M) < 0.25 \
        and float(np.percentile(p, 90)) <= proud_max(prof, float(row[4])) * (1.0 + SEATED_SLACK) \
        and size_fit(row, prof, g, Hs_grad, (b, c)) >= 1.0 - SEATED_SLACK \
        and back_show(row, prof, H, g) <= SEAT_BACK_CLEAR_M + 0.1


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
    big), the slope under its front, how much of its back shows, its scale, its lean, and the share of
    its front out of the ground."""
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
                             float(r[6]) if len(r) > 6 else 0.0, float((p > 0.0).mean())))
    return {"rows": np.array(rows, dtype=np.float64).reshape(-1, 8)}


# --- the rock a face is covered by, and the gaps in it (triage 42's leftovers) ----------------

## what counts as rock on a face: the cliff pieces, the ledges and beds, the forge's slabs and
## columns, and the boulders (not the scree: a stone a metre across covers nothing)
ROCK_PARTS = ("_cliff_face_", "_cliff_ledge_", "_cliff_slab_", "_basalt_columns_", "_boulder_")
LEDGE_PART = "_cliff_ledge_"
## the steep ground a face is: this steep (the player's walkable limit, Actor.WALKABLE_SLOPE_DEG),
## with this much relief within FACE_RELIEF_WIN_M (crags.CLIFF_MIN_H, CLIFF_RELIEF_M)
FACE_SLOPE_DEG = 45.0
FACE_RELIEF_M = 8.0
FACE_RELIEF_WIN_M = 20.0


def footprint(row: list, prof: Profile, face: bool) -> np.ndarray:
    """The ground a piece covers, as a polygon of (x, z) corners: a cliff face's front (it lies in
    the slope, so its depth goes into the hill, not over the ground), anything else its box."""
    lo, hi = prof.lo, prof.hi
    if face:
        zf = float(np.median(prof.front[:, 2]))
        pts = np.array([[lo[0], lo[1], zf], [hi[0], lo[1], zf], [hi[0], hi[1], zf], [lo[0], hi[1], zf]])
        return _hull(transform(row, pts)[:, [0, 2]])
    pts = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    return _hull(transform(row, pts)[:, [0, 2]])


def _hull(p: np.ndarray) -> np.ndarray:
    """The convex hull of 2-D points, anticlockwise (monotone chain)."""
    p = p[np.lexsort((p[:, 1], p[:, 0]))]

    def half(pts):
        out = []
        for q in pts:
            while len(out) >= 2 and ((out[-1][0] - out[-2][0]) * (q[1] - out[-2][1])
                                     - (out[-1][1] - out[-2][1]) * (q[0] - out[-2][0])) <= 0.0:
                out.pop()
            out.append(q)
        return out
    lower, upper = half(p), half(p[::-1])
    return np.array(lower[:-1] + upper[:-1])


def raster(poly: np.ndarray, g: Grid) -> tuple:
    """(i, j) of the texels whose centres are inside the convex polygon `poly` (anticlockwise in
    x, z, as _hull gives it)."""
    fj, fi = g.to_tex(poly[:, 0], poly[:, 1])
    if len(fj) < 3:
        return np.zeros(0, np.int64), np.zeros(0, np.int64)
    j0, j1 = max(int(np.floor(fj.min())), 0), min(int(np.ceil(fj.max())), g.n - 1)
    i0, i1 = max(int(np.floor(fi.min())), 0), min(int(np.ceil(fi.max())), g.n - 1)
    if j1 < j0 or i1 < i0:
        return np.zeros(0, np.int64), np.zeros(0, np.int64)
    jj, ii = np.meshgrid(np.arange(j0, j1 + 1), np.arange(i0, i1 + 1))
    jj, ii = jj.ravel(), ii.ravel()
    inside = np.ones(jj.size, dtype=bool)
    k = len(fj)
    for a in range(k):
        b = (a + 1) % k
        inside &= (fj[b] - fj[a]) * (ii - fi[a]) - (fi[b] - fi[a]) * (jj - fj[a]) >= 0.0
    return ii[inside], jj[inside]


def rock_rows(buckets: dict, parts=ROCK_PARTS):
    """(asset, row) for every rock piece in `buckets`."""
    for by in buckets.values():
        for asset, rows in by.items():
            if any(p in asset for p in parts):
                for r in rows:
                    yield asset, r


def cover_map(buckets: dict, g: Grid, repo_root: str = ".", out: np.ndarray | None = None) -> np.ndarray:
    """[z, x] uint8: 1 on the ground some rock piece covers (its footprint), else 0."""
    C = np.zeros((g.n, g.n), dtype=np.uint8) if out is None else out
    for asset, r in rock_rows(buckets):
        ii, jj = raster(footprint(r, profile(asset, repo_root), FACE_PART in asset), g)
        C[ii, jj] = 1
    return C


def face_mask(H: np.ndarray, g: Grid, Hs_grad: tuple | None = None) -> np.ndarray:
    """[z, x] bool: the steep faces (FACE_SLOPE_DEG, with FACE_RELIEF_M round them)."""
    from scipy import ndimage

    gx, gz = Hs_grad if Hs_grad is not None else smoothed_grad(H, g)
    k = max(3, int(FACE_RELIEF_WIN_M / g.spacing))
    Hf = H.astype(np.float32)
    relief = ndimage.maximum_filter(Hf, size=k) - ndimage.minimum_filter(Hf, size=k)
    return (np.hypot(gx, gz) >= math.tan(math.radians(FACE_SLOPE_DEG))) & (relief >= FACE_RELIEF_M)


def gap_stats(C: np.ndarray, steep: np.ndarray, g: Grid, near_m: float = 3.0) -> dict:
    """How well the steep faces are covered in rock: the share of them under a piece, the share
    within `near_m` of one, how far the bare steep ground is from the nearest rock, and the bare
    patches (steep ground over `near_m` from rock) by size."""
    from scipy import ndimage

    n = int(steep.sum())
    if not n:
        return {"steep_ha": 0.0}
    d = ndimage.distance_transform_edt(C == 0).astype(np.float32) * g.spacing
    bare = steep & (d > near_m)
    lab, k = ndimage.label(bare)
    sizes = (np.bincount(lab.ravel())[1:] * g.spacing * g.spacing) if k else np.zeros(1)
    ds = d[steep & (C == 0)]
    q = lambda a, p: round(float(np.percentile(a, p)), 1) if a.size else 0.0  # noqa: E731
    return {
        "steep_ha": round(n * g.spacing ** 2 / 1e4, 1),
        "under_rock": round(float(C[steep].mean()), 3),
        "within_%gm" % near_m: round(1.0 - float(bare.sum()) / n, 3),
        "bare_to_rock_m_p50": q(ds, 50), "bare_to_rock_m_p90": q(ds, 90), "bare_to_rock_m_p99": q(ds, 99),
        "gaps": int(k), "gap_m2_p50": q(sizes, 50), "gap_m2_p90": q(sizes, 90),
        "gap_m2_max": round(float(sizes.max()), 0),
        "bare_in_gaps_over_400m2": round(float(sizes[sizes > 400.0].sum()) / max(float(sizes.sum()), 1.0), 3),
    }


# --- the gaps filled -----------------------------------------------------------------------
#
# Seated and held to their faces, the pieces left bare strips between them: the build laid them in
# columns up the fall line, one column a seed apart, and seating made each smaller or took it out
# without laying any other. On the Skerrow wall that read as parallel columns of rock with the dark
# hill between (the coordinator's review of the triage 42 sheet). Where a face is still bare more
# than FILL_GAP_M from any rock, smaller pieces go in, seated by the same rules: the region's own
# kit (the pieces nearest), a mix of sizes, turned in the slope each its own way, each laid where a
# gap is (in no order along or across the slope, and jittered off it), overlapping the rock round
# it a little. A face reads as one broken wall of rock, not as stripes.

## steep ground further than this from rock is a gap
FILL_GAP_M = 3.0
## the sizes pieces go in at: most small, some middling (a first pass at the larger, then one at
## the smaller for what is left), and the least one is seated at
FILL_SCALES = ((0.5, 1.0), (0.3, 0.55))
FILL_SCALE_MIN = 0.26
## how far a piece is turned in its slope off facing straight down it (the build's are 10)
FILL_TWIST_DEG = 22.0
## how far off the gap's texel it is laid, along and across the slope
FILL_JITTER_M = 3.0
## the gaps are filled middles first, with this much noise on how far a texel is from rock
FILL_ORDER_NOISE_M = 8.0
## a piece goes in where at most this share of its footprint is already rock, and at least
## FILL_NEW_MIN of it was bare steep ground
FILL_OVERLAP_MAX = 0.5
FILL_NEW_MIN = 0.3
## its kit: the variants among the FILL_KIT_K nearest cliff pieces, within FILL_KIT_REACH_M
FILL_KIT_K = 10
FILL_KIT_REACH_M = 400.0
## a variant is picked in proportion to (its width over its height) to this power
FILL_BROAD = 1.5
## the pieces' tints, as the build's (crags.cliff_faces)
FILL_TINT = (0.85, 1.0)


def _family(asset: str) -> str:
    """A kit's family: the asset's name without its variant letter (skerrow_cliff_face)."""
    return os.path.splitext(os.path.basename(asset))[0].rsplit("_", 1)[0]


def _kit_tree(buckets: dict):
    from scipy.spatial import cKDTree

    xz, names = [], []
    for asset, r in rock_rows(buckets, (FACE_PART,)):
        xz.append((float(r[0]), float(r[2])))
        names.append(asset)
    if not xz:
        return None, []
    return cKDTree(np.array(xz)), names


def _laid(asset: str, prof: Profile, x: float, z: float, sc: float, psi_deg: float,
          H: np.ndarray, g: Grid, Hs_grad: tuple) -> list | None:
    """A row for `asset` lying in the ground's plane at (x, z), turned `psi_deg` in it, with the
    middle of its front on the ground there (for seat() to finish)."""
    gx = float(sample_bilinear(Hs_grad[0], g, np.array([x]), np.array([z]))[0])
    gz = float(sample_bilinear(Hs_grad[1], g, np.array([x]), np.array([z]))[0])
    if math.hypot(gx, gz) < 1e-3:
        return None
    N, u, x0 = plane_frame(gx, gz)
    psi = math.radians(psi_deg)
    R = np.stack([x0 * math.cos(psi) + u * math.sin(psi), u * math.cos(psi) - x0 * math.sin(psi), N], axis=1)
    yaw, lean, toward = row_angles(R)
    mid = R @ (prof.front.mean(axis=0) * sc)
    y = float(sample_bilinear(H, g, np.array([x]), np.array([z]))[0])
    return [round(float(x - mid[0]), 2), round(float(y - mid[1]), 2), round(float(z - mid[2]), 2), round(yaw, 1), round(sc, 3),
            "#ffffff", round(lean, 1), round(toward, 1)]


def fill_gaps(buckets: dict, H: np.ndarray, g: Grid, repo_root: str = ".", seed: int = 0,
              clear=None, steep: np.ndarray | None = None, cover: np.ndarray | None = None) -> dict:
    """In place: cliff face pieces added to `buckets` on the steep faces (face_mask) that are still
    more than FILL_GAP_M from rock, each seated by seat(). `clear(x, z)`, if given, says where a
    piece may stand (off the roads, the pads and the water). Returns counts and `cover` (the rock
    footprints, with the new pieces')."""
    from scipy import ndimage

    Hs_grad = smoothed_grad(H, g)
    if steep is None:
        steep = face_mask(H, g, Hs_grad)
    C = cover_map(buckets, g, repo_root) if cover is None else cover
    tree, kit_of = _kit_tree(buckets)
    families: dict = {}
    for a in sorted(set(kit_of)):
        families.setdefault(_family(a), []).append(a)
    counts = {"added": 0, "tried": 0, "no_kit": 0, "unseated": 0, "overlap": 0, "not_clear": 0}
    if tree is None:
        counts["cover"] = C
        return counts
    rng = np.random.default_rng(np.random.SeedSequence([seed, 4242]))
    gap_px = int(math.floor(FILL_GAP_M / g.spacing))
    di, dj = np.nonzero(np.hypot(*np.mgrid[-gap_px:gap_px + 1, -gap_px:gap_px + 1]) * g.spacing <= FILL_GAP_M)
    di, dj = di - gap_px, dj - gap_px
    for p_i, (s_lo, s_hi) in enumerate(FILL_SCALES):
        dist = ndimage.distance_transform_edt(C == 0) * g.spacing
        ii, jj = np.nonzero(steep & (dist > FILL_GAP_M))
        # the middles of the gaps first, so a piece covers bare ground rather than rock, but in no
        # order along a gap (FILL_ORDER_NOISE_M of noise on the distance): the middle of a strip
        # between two columns, in order, is a third column
        order = np.argsort(-(dist[ii, jj] + rng.uniform(0.0, FILL_ORDER_NOISE_M, ii.size)), kind="stable")
        del dist
        for o in order:
            i, j = int(ii[o]), int(jj[o])
            # still a gap? (pieces laid this pass cover it)
            if C[np.clip(i + di, 0, g.n - 1), np.clip(j + dj, 0, g.n - 1)].any():
                continue
            counts["tried"] += 1
            x = g.x0 + j * g.spacing + float(rng.uniform(-FILL_JITTER_M, FILL_JITTER_M))
            z = g.z0 + i * g.spacing + float(rng.uniform(-FILL_JITTER_M, FILL_JITTER_M))
            dist, idx = tree.query((x, z), k=FILL_KIT_K, distance_upper_bound=FILL_KIT_REACH_M)
            idx = [int(k) for k, d in zip(np.atleast_1d(idx), np.atleast_1d(dist)) if np.isfinite(d)]
            if not idx:
                counts["no_kit"] += 1
                continue
            # the region's kit (the family of a piece near), in its broader variants more often:
            # the build picks the variant whose height fits a face best, which on a tall wall is
            # the tallest and narrowest (the Skerrow's `b`, 14 m by 23), and a wall of those,
            # stacked up the fall line, is columns; the gaps take `a` and `c` (20 by 17, 23 by 10)
            fam = families[_family(kit_of[idx[int(rng.integers(0, len(idx)))]])]
            wts = np.array([profile(a, repo_root).w / max(profile(a, repo_root).h, 1e-3) for a in fam]) ** FILL_BROAD
            asset = fam[int(rng.choice(len(fam), p=wts / wts.sum()))]
            prof = profile(asset, repo_root)
            # sizes spread evenly in log between the pass's bounds: many small, a few larger
            sc = math.exp(float(rng.uniform(math.log(s_lo), math.log(s_hi))))
            psi = float(rng.uniform(-FILL_TWIST_DEG, FILL_TWIST_DEG))
            row = _laid(asset, prof, x, z, sc, psi, H, g, Hs_grad)
            if row is None:
                counts["unseated"] += 1
                continue
            new, _why = seat(row, prof, H, g, Hs_grad, FILL_TWIST_DEG, FILL_SCALE_MIN)
            if new is None:
                counts["unseated"] += 1
                continue
            fi, fj = raster(footprint(new, prof, True), g)
            if fi.size == 0:
                counts["unseated"] += 1
                continue
            if float(C[fi, fj].mean()) > FILL_OVERLAP_MAX or float((steep[fi, fj] & (C[fi, fj] == 0)).mean()) < FILL_NEW_MIN:
                counts["overlap"] += 1
                continue
            if clear is not None:
                pts = transform(new, prof.front[:: max(1, len(prof.front) // 12)])
                if not all(clear(float(p[0]), float(p[2])) for p in pts):
                    counts["not_clear"] += 1
                    continue
            c = int(round(255 * float(rng.uniform(*FILL_TINT))))
            new[5] = "#%02x%02x%02x" % (c, c, c)
            buckets.setdefault(g.written_cell(new[0], new[2]), {}).setdefault(asset, []).append(new)
            C[fi, fj] = 1
            counts["added"] += 1
            counts["added_pass_%d" % p_i] = counts.get("added_pass_%d" % p_i, 0) + 1
    counts["cover"] = C
    return counts


# --- the ledges and beds seated where they stand proud ---------------------------------------
#
# The crag ledges and the sea-cliff beds (`cliff_ledge`) are courses of level beds: they are not
# leaned into the slope as the faces are (their bedding is level along the crag), but where the
# ground falls away under one (a nose the course turns round, a face steeper than the course was
# laid for) its front stood out of the slope, a third of them by more than a metre and a sixth by
# more than two on the installed world. Such a bed goes back into the hill, level, until the lowest
# fifth of its front stands LEDGE_SHOW_M out, by no more than LEDGE_BACK_MAX of its own depth.

## a bed whose front's lowest fifth stands out more than this is proud
LEDGE_PROUD_M = 1.0
## ... and is moved back until it stands this far out
LEDGE_SHOW_M = 0.3
## at most this share of its own depth, in steps of LEDGE_STEP_M
LEDGE_BACK_MAX = 0.9
LEDGE_STEP_M = 0.25
## and not so far that less than this share of its front is out of the ground
LEDGE_SHOWN_MIN = 0.35


def seat_ledge(row: list, prof: Profile, H: np.ndarray, g: Grid, Hs_grad: tuple) -> list | None:
    """The bed moved back into its hill, level, where it stands proud; None where it does not (or
    cannot go back without burying it)."""
    p0 = front_level(protrusion(row, prof, H, g, Hs_grad))
    if p0 <= LEDGE_PROUD_M:
        return None
    f = row_basis(row)[:, 2]
    f = np.array([f[0], 0.0, f[2]])
    if np.linalg.norm(f) < 1e-3:
        return None
    f /= np.linalg.norm(f)
    sc = float(row[4]) if not (len(row) > 8 and isinstance(row[8], list)) else float(row[8][2])
    most = LEDGE_BACK_MAX * prof.d * sc
    best, best_p = None, p0
    s = LEDGE_STEP_M
    while s <= most + 1e-6:
        r = list(row)
        r[0], r[2] = round(float(row[0]) - f[0] * s, 2), round(float(row[2]) - f[2] * s, 2)
        p = protrusion(r, prof, H, g, Hs_grad)
        lvl = front_level(p)
        if float((p > 0.0).mean()) < LEDGE_SHOWN_MIN:
            break
        if lvl < best_p - 0.05:
            best, best_p = r, lvl
        if lvl <= LEDGE_SHOW_M:
            break
        s += LEDGE_STEP_M
    # (only a move that takes it out of the proud: one that went part way would go further again
    # on a second pass, and the sweep over installed cells would not be idempotent)
    return best if best is not None and best_p <= LEDGE_PROUD_M else None


def settle_ledges(buckets: dict, H: np.ndarray, g: Grid, repo_root: str = ".") -> dict:
    """In place: every proud `cliff_ledge` row in `buckets` moved back into its hill (seat_ledge);
    one that moves into another cell is filed there. Returns counts."""
    Hs_grad = smoothed_grad(H, g)
    counts = {"ledges": 0, "proud": 0, "moved": 0}
    moved = []
    for key in list(buckets):
        by = buckets[key]
        for asset in list(by):
            if LEDGE_PART not in asset:
                continue
            prof = profile(asset, repo_root)
            keep = []
            for r in by[asset]:
                counts["ledges"] += 1
                new = seat_ledge(r, prof, H, g, Hs_grad)
                if front_level(protrusion(r, prof, H, g, Hs_grad)) > LEDGE_PROUD_M:
                    counts["proud"] += 1
                if new is None:
                    keep.append(r)
                    continue
                counts["moved"] += 1
                if g.written_cell(new[0], new[2]) == key:
                    keep.append(new)
                else:
                    moved.append((asset, new))
            by[asset] = keep
    for asset, r in moved:
        buckets.setdefault(g.written_cell(r[0], r[2]), {}).setdefault(asset, []).append(r)
    return counts
