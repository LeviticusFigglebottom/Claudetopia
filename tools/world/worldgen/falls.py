"""A step in the land at every waterfall the content places.

A waterfall POI (`kind` "waterfall") is dressed in the game as a face of the forge's ledges with
water over its lip. Its pad was a disc of level ground like any other, so the face stood up out
of the level with the sky behind it: the batch 3 shots had Whitecut, Foxfire and the Glass Falls as
towers of blocks on gentle ground, and the Three Sisters as a stepped pyramid in the river. And
where a river ran through the pad it ran level across it, with no drop for the water to fall.

Here the land falls with the water. Each waterfall's pad is stepped: level at its **foot** in front
of the face and at its **top** behind it, the ground between them as steep as the texels allow, so
the face the dressing stands there is the front of a hill. A POI on one of the atlas's rivers faces
downstream, and its top is no higher than the land the river comes from, so the river's own
surface (hydro.atlas_rivers, which follows the land) drops at the face and rivers.json has the fall
there; the gorge the river then runs in below it is the valley carve's. A POI off the rivers faces
the way its ground falls.

The dressings' forms (game/world/pois/poi_builders.gd, waterfall): a single face 11 m high 6 m
behind the centre; the glass fall 13 m, 7 m behind; three tiers of 4.6 m, 2, 8 and 14 m behind.
The step is those faces (FORMS), and pois.json says where it is (`fall` on the POI's entry) so the
dressing can stand its rock on the step rather than guessing at a facing of its own.
"""
from __future__ import annotations

import math
import zlib
from dataclasses import dataclass, field

import numpy as np

from .atlas import lake_at
from .grid import Grid, sample_bilinear, smoothstep

## The faces of each form: (metres behind the POI's centre, metres of drop), front to back.
FORMS = {
    "single": ((6.0, 11.0),),
    "glass": ((7.0, 13.0),),
    "terraced": ((2.0, 4.6), (8.0, 4.6), (14.0, 4.6)),
}
## how steep the ground between a face's foot and its top is laid: over this many metres
## (at least a texel and a half), the far side of it at the face's own line
STEP_RUN_M = 3.0
## a POI this near an atlas river is on it: its water is the river's (the dressing asks the same
## of the river's falls, within 30 m)
ON_RIVER_M = 30.0
## how far down the river the gorge below the fall may run before the fall is made lower instead
GORGE_M = 450.0
## how far either side of a river's drawn line above the fall the land is read for its lowest
UP_SPREAD_M = 10.0
## the least drop a step keeps; a waterfall with less than this is not worth the name
MIN_DROP_M = 4.0


@dataclass
class Step:
    id: str
    form: str
    x: float
    z: float
    fx: float                      # the facing: the way the water goes over, downstream
    fz: float
    foot: float                    # the ground's level in front of the first face
    faces: list = field(default_factory=list)    # [(metres behind the centre, drop)], front first
    river: str = ""
    ## a cave's rise is a knoll, not a scarp across the pad: full height out to `half_width` either
    ## side of the facing's line, down to the foot over `taper` more (0: across the whole pad)
    half_width: float = 0.0
    taper: float = 0.0

    @property
    def top(self) -> float:
        return self.foot + sum(d for _, d in self.faces)

    @property
    def facing_deg(self) -> float:
        """The facing as a yaw about +Y, measured as the dressing's `PoiKit.yaw_of` measures it."""
        return math.degrees(math.atan2(self.fx, self.fz)) % 360.0

    def rise(self, x: np.ndarray, z: np.ndarray) -> np.ndarray:
        """Metres over the foot the step stands at world (x, z)."""
        u = (x - self.x) * self.fx + (z - self.z) * self.fz
        out = np.zeros(np.broadcast(u).shape, dtype=np.float32)
        for behind, drop in self.faces:
            # 0 in front of the face's line, the drop past STEP_RUN_M behind it
            out += drop * (1.0 - smoothstep(-behind - STEP_RUN_M, -behind, u))
        if self.half_width > 0.0:
            v = np.abs(-(x - self.x) * self.fz + (z - self.z) * self.fx)
            out *= (1.0 - smoothstep(self.half_width, self.half_width + self.taper, v)).astype(np.float32)
        return out

    def pins(self) -> list:
        """[(x, z)]: where the river through it must have a point, each face's foot and lip on the
        line through the centre (hydro.atlas_rivers' `pins`)."""
        out = []
        for behind, _ in self.faces:
            for b in (behind, behind + STEP_RUN_M):
                out.append((self.x - self.fx * b, self.z - self.fz * b))
        return out

    def cave_entry(self) -> dict:
        """What pois.json says of a cave's rise (`cave` on the POI's entry; CONTRACTS section 6)."""
        behind = self.faces[0][0]
        return {"facing_deg": round(self.facing_deg, 1), "mouth_m": round(self.foot, 2),
                "face_top_m": round(self.top, 2), "mouth_behind_m": behind,
                "face_half_width_m": round(self.half_width, 2) if self.half_width > 0.0 else None}

    def entry(self) -> dict:
        """What pois.json says of it (`fall` on the POI's entry; docs/CONTRACTS.md section 6)."""
        return {"facing_deg": round(self.facing_deg, 1), "foot_m": round(self.foot, 2),
                "top_m": round(self.top, 2), "form": self.form, "river": self.river,
                "faces": [{"behind_m": b, "drop_m": round(d, 2)} for b, d in self.faces]}


def form_of(brief: str) -> str:
    """Which of the dressing's forms a waterfall's sentence asks for (poi_builders.waterfall)."""
    b = brief.lower()
    if "three" in b or "terrace" in b:
        return "terraced"
    if "glass" in b:
        return "glass"
    return "single"


def _nearest_on(path: np.ndarray, x: float, z: float) -> tuple:
    """(distance, segment index, its unit direction, metres along the path) of the nearest point."""
    a, b = path[:-1], path[1:]
    d = b - a
    ln2 = np.maximum((d ** 2).sum(axis=1), 1e-9)
    t = np.clip(((x - a[:, 0]) * d[:, 0] + (z - a[:, 1]) * d[:, 1]) / ln2, 0.0, 1.0)
    px, pz = a[:, 0] + t * d[:, 0], a[:, 1] + t * d[:, 1]
    dist = np.hypot(px - x, pz - z)
    k = int(np.argmin(dist))
    seg = np.sqrt(ln2)
    run = float(np.concatenate([[0.0], np.cumsum(seg)])[k] + t[k] * seg[k])
    u = d[k] / seg[k]
    return float(dist[k]), k, (float(u[0]), float(u[1])), run


def _along(path: np.ndarray, run0: float, run1: float, step: float = 10.0) -> np.ndarray:
    """Points along a polyline between two distances along it."""
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    lo, hi = max(min(run0, run1), 0.0), min(max(run0, run1), float(cum[-1]))
    if hi <= lo:
        return np.zeros((0, 2))
    s = np.arange(lo, hi + 1e-6, step)
    return np.stack([np.interp(s, cum, path[:, 0]), np.interp(s, cum, path[:, 1])], axis=1)


def _disc_median(H: np.ndarray, grid: Grid, x: float, z: float, r: float) -> float:
    a = np.linspace(0.0, 2.0 * math.pi, 12, endpoint=False)
    xs = np.concatenate([[x], x + r * np.cos(a), x + 0.5 * r * np.cos(a)])
    zs = np.concatenate([[z], z + r * np.sin(a), z + 0.5 * r * np.sin(a)])
    return float(np.median(sample_bilinear(H, grid, xs, zs)))


def plan(grid: Grid, H: np.ndarray, atlas: dict, pois: list) -> dict:
    """{POI id: Step} for every waterfall POI in the registry, read off the land as composed
    (before any pad is laid) and the atlas's drawn rivers."""
    rivers = [(rv["id"], np.asarray(rv["path"], dtype=np.float64)) for rv in atlas.get("rivers", [])
              if len(rv.get("path", [])) >= 2]
    out: dict = {}
    for p in pois:
        if str(p.get("kind", "")) != "waterfall" or "position" not in p:
            continue
        pid = str(p["id"])
        x, z = float(p["position"][0]), float(p["position"][1])
        form = form_of(str(p.get("unique_feature", "")) + " " + str(p.get("description", "")))
        faces = FORMS[form]
        drop = sum(d for _, d in faces)
        back = faces[-1][0]
        best = None
        for rid, path in rivers:
            got = _nearest_on(path, x, z)
            if got[0] <= ON_RIVER_M and (best is None or got[0] < best[1][0]):
                best = (rid, got, path)
        if best is not None:
            rid, (dist, k, (fx, fz), run), path = best
            # the top: the land behind the last face, and no higher than any of the land the river
            # comes down over from its source to get there. Its surface is the lowest land above
            # it (hydro._monotone_profile); a top over that stood the river's surface under the
            # step's lip, and keep_channels cut the step back down to the river's carve.
            behind = _disc_median(H, grid, x - fx * (back + 8.0), z - fz * (back + 8.0), 6.0)
            up = _along(path, 0.0, run - back - 4.0)
            top = behind
            if up.shape[0]:
                # (and a little either side of the drawn line, where the river's meander may run)
                d = np.diff(up, axis=0, prepend=up[:1] - (up[1:2] - up[:1] if up.shape[0] > 1 else 1.0))
                d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
                for side in (-UP_SPREAD_M, 0.0, UP_SPREAD_M):
                    xs, zs = up[:, 0] - d[:, 1] * side, up[:, 1] + d[:, 0] * side
                    top = min(top, float(np.min(sample_bilinear(H, grid, xs, zs))))
            src = lake_at(atlas, float(path[0, 0]), float(path[0, 1]))
            if src is not None:
                top = min(top, float(src["level_m"]))
            # the gorge below: lower the fall rather than cut a gorge longer than GORGE_M
            down = _along(path, run + 4.0, run + GORGE_M)
            if down.shape[0]:
                lowest = float(np.min(sample_bilinear(H, grid, down[:, 0], down[:, 1])))
                drop_ok = max(min(drop, top - lowest), MIN_DROP_M)
            else:
                drop_ok = drop
            foot = top - drop_ok
        else:
            rid = ""
            # the way the ground falls, over the pad and its skirt
            r = 30.0
            gx = (_disc_median(H, grid, x + r, z, 8.0) - _disc_median(H, grid, x - r, z, 8.0)) / (2.0 * r)
            gz = (_disc_median(H, grid, x, z + r, 8.0) - _disc_median(H, grid, x, z - r, 8.0)) / (2.0 * r)
            s = math.hypot(gx, gz)
            if s > 0.02:
                fx, fz = -gx / s, -gz / s
            else:
                a = math.radians(zlib.crc32(pid.encode("utf-8")) % 360)
                fx, fz = math.sin(a), math.cos(a)
            behind = _disc_median(H, grid, x - fx * (back + 8.0), z - fz * (back + 8.0), 6.0)
            front = _disc_median(H, grid, x + fx * 6.0, z + fz * 6.0, 6.0)
            # half cut and half fill where the ground gives less than the fall, none where it gives it
            if behind - front >= drop:
                foot = behind - drop
            else:
                foot = 0.5 * (behind + front) - 0.5 * drop
            drop_ok = drop
        scale = drop_ok / drop
        out[pid] = Step(id=pid, form=form, x=x, z=z, fx=float(fx), fz=float(fz), foot=float(foot),
                        faces=[(b, d * scale) for b, d in faces], river=rid)
    return out


def from_entries(pois_json: list) -> dict:
    """The steps a build wrote to pois.json (`fall` on each entry), for a staged build that reuses
    its heights and lays its pads again."""
    out: dict = {}
    for e in pois_json:
        c = e.get("cave")
        if c:
            a = math.radians(float(c["facing_deg"]))
            hw = c.get("face_half_width_m")
            out[str(e["place_id"])] = Step(id=str(e["place_id"]), form="cave", x=float(e["pos"][0]), z=float(e["pos"][2]),
                                           fx=math.sin(a), fz=math.cos(a), foot=float(c["mouth_m"]),
                                           faces=[(float(c["mouth_behind_m"]), float(c["face_top_m"]) - float(c["mouth_m"]))],
                                           half_width=float(hw) if hw else 0.0,
                                           taper=CAVE_KNOLL_TAPER_M if hw else 0.0)
            continue
        f = e.get("fall")
        if not f:
            continue
        a = math.radians(float(f["facing_deg"]))
        out[str(e["place_id"])] = Step(id=str(e["place_id"]), form=str(f.get("form", "single")),
                                       x=float(e["pos"][0]), z=float(e["pos"][2]), fx=math.sin(a), fz=math.cos(a),
                                       foot=float(f["foot_m"]),
                                       faces=[(float(c["behind_m"]), float(c["drop_m"])) for c in f["faces"]],
                                       river=str(f.get("river", "")))
    return out



# --- the caves -------------------------------------------------------------------------------------

## A cave POI (`kind` "cave") was a pad of level ground like any other, and its dressing stood a black
## box on it with rubble heaped over (the w4096c Kharrow Hole: "a cave with no hillside to be a cave
## in"). Its pad now has a rise to go into, as a fall's has its step: level at the mouth's floor in
## front, and CAVE_FACE_M or more higher behind the mouth's line, which is CAVE_MOUTH_M behind the
## centre (poi_builders_land.cave stands the mouth three metres into the hill from the middle).
## Where the ground already rises that much behind the mouth, the pad is cut into it as a shelf and
## the face keeps the whole of the natural rise; where it does not, a knoll is raised behind the
## mouth, CAVE_KNOLL_HALF_M either side of it at full height and down to the pad over CAVE_KNOLL_TAPER_M.
## It faces away from the rising ground (over CAVE_LOOK_M), or where there is none, a bearing its id
## gives it. A pad whose level the atlas fixes (the Hushline's sea-cave at 4 m) keeps it.
CAVE_MOUTH_M = 3.0
CAVE_FACE_M = 6.0
CAVE_KNOLL_HALF_M = 8.0
CAVE_KNOLL_TAPER_M = 10.0
CAVE_LOOK_M = (16.0, 28.0, 44.0)
CAVE_RISING_M = 2.0


def caves(grid: Grid, H: np.ndarray, pois: list, fixed_levels: dict | None = None) -> dict:
    """{POI id: Step (form "cave")} for every cave POI, read off the land as composed."""
    fixed = fixed_levels or {}
    out: dict = {}
    for p in pois:
        if str(p.get("kind", "")) != "cave" or "position" not in p:
            continue
        pid = str(p["id"])
        x, z = float(p["position"][0]), float(p["position"][1])
        h0 = _disc_median(H, grid, x, z, 4.0)
        # the way into the rising ground: each bearing by how far the land rises along it
        best, into = 0.0, None
        for k in range(24):
            a = 2.0 * math.pi * k / 24.0
            ux, uz = math.sin(a), math.cos(a)
            rise = max(float(sample_bilinear(H, grid, np.array([x + ux * d]), np.array([z + uz * d]))[0]) - h0
                       for d in CAVE_LOOK_M)
            if rise > best:
                best, into = rise, (ux, uz)
        if into is None or best < CAVE_RISING_M:
            a = math.radians(zlib.crc32(pid.encode("utf-8")) % 360)
            into = (math.sin(a), math.cos(a))
        fx, fz = -into[0], -into[1]
        behind = _disc_median(H, grid, x - fx * (CAVE_MOUTH_M + 8.0), z - fz * (CAVE_MOUTH_M + 8.0), 4.0)
        front = _disc_median(H, grid, x + fx * 4.0, z + fz * 4.0, 4.0)
        if pid in fixed:
            foot = float(fixed[pid])
        elif behind - front >= CAVE_FACE_M:
            foot = front
        else:
            foot = min(front, h0)
        drop = max(CAVE_FACE_M, behind - foot)
        # a shelf cut into ground that already rises the whole face: across the pad; else a knoll
        shelf = behind - foot >= CAVE_FACE_M
        out[pid] = Step(id=pid, form="cave", x=x, z=z, fx=float(fx), fz=float(fz), foot=float(foot),
                        faces=[(CAVE_MOUTH_M, float(drop))], river="",
                        half_width=0.0 if shelf else CAVE_KNOLL_HALF_M,
                        taper=0.0 if shelf else CAVE_KNOLL_TAPER_M)
    return out
