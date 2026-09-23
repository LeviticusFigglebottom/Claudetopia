"""Clothing, armour, hair and attachments for WM_Humanoid_v1.

Garments are grown from the body itself: the body's signed-distance field offset outward by
the cloth thickness is, by construction, a shell that fits the wearer exactly and can never
clip through them.  A garment is then that shell restricted to a *region* (torso, arms,
legs, ...) plus its own shapes — a skirt that falls away from the legs, a hood that stands
off the skull, a pauldron that sits proud of the shoulder.

The same trick makes hair: the scalp region of the head field, pushed out by a thickness
that varies with the style, plus tube_path locks for braids, buns and fringes.

Regions are smooth 0..1 weights over 3D space (see `Region`), so garment edges can be soft
(a sleeve that fades at the wrist) rather than a hard cut.
"""
from __future__ import annotations

import math
import zlib
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import numpy as np

from . import rig, sdf, body as bodylib
from .rig import Skeleton, FWD, UP, LEFT
from .sdf import Prim, Scene

BACK = -FWD


# --------------------------------------------------------------------------------------
# regions
# --------------------------------------------------------------------------------------

RegionFn = Callable[[np.ndarray], np.ndarray]


def band_z(z0: float, z1: float, soft: float = 0.02) -> RegionFn:
    """1 between two heights, fading over `soft`."""
    def fn(P):
        return (sdf_smoothstep(z0 - soft, z0 + soft, P[:, 2]) *
                (1.0 - sdf_smoothstep(z1 - soft, z1 + soft, P[:, 2])))
    return fn


def sdf_smoothstep(e0, e1, x: np.ndarray) -> np.ndarray:
    """Hermite step from e0 to e1; the edges may be per-point arrays (a hem that varies round
    the body), which the built-in `max` in here used to refuse."""
    t = np.clip((x - e0) / np.maximum(e1 - e0, 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def near_bones(skel: Skeleton, bones: Sequence[str], radius: float, soft: float = 0.06) -> RegionFn:
    """1 near the given bone segments.  The natural way to say 'the sleeves' or 'the legs'."""
    segs = [(skel.bones[b].head, skel.bones[b].tail) for b in bones]

    def fn(P):
        d = np.full(len(P), 1e6)
        for a, t in segs:
            ab = t - a
            l2 = max(float(np.dot(ab, ab)), 1e-9)
            u = np.clip(((P - a) @ ab) / l2, 0.0, 1.0)
            np.minimum(d, np.linalg.norm(P - (a + u[:, None] * ab), axis=1), out=d)
        return 1.0 - sdf_smoothstep(radius - soft, radius + soft, d)
    return fn


def near_segments(segs: Sequence[Tuple[np.ndarray, np.ndarray]], radius: float,
                  soft: float = 0.03) -> RegionFn:
    """1 near any of the given segments.  Like `near_bones`, but on arbitrary points, for
    when a region has to start part of the way down a bone rather than at its head."""
    pairs = [(np.asarray(a, float), np.asarray(b, float)) for a, b in segs]

    def fn(P):
        d = np.full(len(P), 1e6)
        for a, t in pairs:
            ab = t - a
            l2 = max(float(np.dot(ab, ab)), 1e-9)
            u = np.clip(((P - a) @ ab) / l2, 0.0, 1.0)
            np.minimum(d, np.linalg.norm(P - (a + u[:, None] * ab), axis=1), out=d)
        return 1.0 - sdf_smoothstep(radius - soft, radius + soft, d)
    return fn


def region_or(*fns: RegionFn) -> RegionFn:
    def fn(P):
        out = np.zeros(len(P))
        for f in fns:
            out = np.maximum(out, f(P))
        return out
    return fn


def region_and(*fns: RegionFn) -> RegionFn:
    def fn(P):
        out = np.ones(len(P))
        for f in fns:
            out = np.minimum(out, f(P))
        return out
    return fn


def region_not(f: RegionFn) -> RegionFn:
    return lambda P: 1.0 - f(P)


def region_scale(f: RegionFn, k: float) -> RegionFn:
    return lambda P: np.clip(f(P) * k, 0.0, 1.0)


# --------------------------------------------------------------------------------------
# garment shells
# --------------------------------------------------------------------------------------

Field = "sdf.SampledField"


def body_field(skel: Skeleton, style: Optional[bodylib.BodyStyle] = None, spacing: float = 0.005) -> sdf.SampledField:
    """The body's distance field, cached once so every garment can offset it cheaply."""
    return sdf.SampledField(bodylib.body_scene(skel, style), spacing=spacing, margin=0.09)


def head_field(skel: Skeleton, hs: Optional[bodylib.HeadStyle] = None, spacing: float = 0.0032) -> sdf.SampledField:
    return sdf.SampledField(bodylib.head_scene(skel, hs, with_neck=False), spacing=spacing, margin=0.06)


def relief_band(z0: float, z1: float, amount: float, soft: float) -> RegionFn:
    """Extra (or, negative, less) offset between two heights, faded over `soft`.

    This is how a garment gets edges.  A hem, a collar and a cuff are all the same thing --
    the cloth doubled back on itself, so it stands a few millimetres further out than the
    body of the garment and catches light along a line.  A waist is the same trick with the
    sign flipped: the cloth pulled IN where the belt or the wearer's shape holds it."""
    def fn(P):
        z = P[:, 2]
        w = sdf_smoothstep(z0 - soft, z0 + soft, z) * (1.0 - sdf_smoothstep(z1 - soft, z1 + soft, z))
        return amount * w
    return fn


def relief_around(points: Sequence[np.ndarray], radius: float, amount: float, soft: float) -> RegionFn:
    """Extra offset within `radius` of any of `points` -- cuffs at the wrists, a collar
    round the throat."""
    pts = [np.asarray(p, float) for p in points]

    def fn(P):
        best = None
        for c in pts:
            d = np.linalg.norm(P - c, axis=1)
            best = d if best is None else np.minimum(best, d)
        return amount * (1.0 - sdf_smoothstep(radius - soft, radius + soft, best))
    return fn


def relief_sum(*fns: RegionFn) -> RegionFn:
    def fn(P):
        out = fns[0](P)
        for f in fns[1:]:
            out = out + f(P)
        return out
    return fn


def offset_shell(body, region: RegionFn, thickness: float, gap: float = 0.004,
                 k: float = 0.0, bounds: Optional[Tuple[np.ndarray, np.ndarray]] = None,
                 hollow: bool = False, relief: Optional[RegionFn] = None) -> Prim:
    """The body's field pushed out by `gap + thickness`, restricted to `region`.

    Solid by default.  A garment modelled as a true two-sided shell a centimetre thick
    tangles the moment it is decimated to a game triangle budget — opposite faces collapse
    into each other — and nothing in this game ever sees the inside of a tunic, so the
    piece simply encloses the body instead.  Outside the region the field is pushed
    outward, which ends the garment in a soft hem rather than a torn edge.

    `bounds` limits where the garment is evaluated at all; without it a belt would be
    meshed over the whole body's bounding box."""
    outer = gap + thickness
    mid = 0.5 * (gap + outer)
    half = 0.5 * (outer - gap)

    def fn(P):
        d = body.eval(P)
        w = np.clip(region(P), 0.0, 1.0)
        o = outer if relief is None else outer + relief(P)
        surf = (np.abs(d - mid) - half) if hollow else (d - o)
        return surf + (1.0 - w) * 0.25
    lo, hi = bounds if bounds is not None else body.bounds(outer + 0.05)
    return Prim(fn, np.asarray(lo, float), np.asarray(hi, float), "union", k)


def solid_shell(body, region: RegionFn, thickness: float, gap: float = 0.004,
                bounds: Optional[Tuple[np.ndarray, np.ndarray]] = None) -> Prim:
    """Like `offset_shell` but solid (the body's volume is included), for pieces that are
    easier to mesh closed — boots, helms, gloves."""
    outer = gap + thickness

    def fn(P):
        d = body.eval(P) - outer
        w = np.clip(region(P), 0.0, 1.0)
        return d + (1.0 - w) * 0.25
    lo, hi = bounds if bounds is not None else body.bounds(outer + 0.05)
    return Prim(fn, np.asarray(lo, float), np.asarray(hi, float), "union", 0.0)


def zbox(skel: Skeleton, z0: float, z1: float, xy: float = 0.42, ymin: float = -0.34,
         ymax: float = 0.30) -> Tuple[np.ndarray, np.ndarray]:
    """Bounds helper in metres: a slab between two heights around the body axis."""
    s = _s(skel)
    return (np.array([-xy * s, ymin * s, z0]), np.array([xy * s, ymax * s, z1]))


@dataclass
class Garment:
    name: str
    scene: Scene
    spacing: float = 0.006
    smooth: int = 5
    target_tris: int = 2200
    material: str = "cloth"
    colour_key: str = "primary"
    bone: Optional[str] = None           # rigid parts (helms, horns) bind to one bone
    double_sided: bool = False
    # A field whose inside is hidden anyway (the scalp under hair): faces whose centre lies
    # more than `trim_depth` inside it are dropped after meshing, so a shell that dives under
    # the skin at its edge does not spend half its triangles on a surface nobody can see.
    trim: Optional[object] = None
    trim_depth: float = 0.0012
    # Other meshes exported with this one, each with its own material: the arming coat under
    # a cuirass is cloth, the cuirass is iron. Named `<name>_<layer name>`.
    layers: List["Garment"] = field(default_factory=list)
    # Per-vertex skin weights over rig.DEFORM_NAMES, for parts that are neither rigid to one
    # bone nor a copy of the body's weights (hair that hangs past the neck).
    weight_fn: Optional[Callable[[np.ndarray], np.ndarray]] = None
    # Or the body's weights, reworked: (vertex positions, their transferred weights) -> weights.
    # A skirt keeps the body's weights above the hips and gives most of the legs' share below
    # them to the hips (see `_skirt_weights`).
    weight_adjust: Optional[Callable[[np.ndarray, np.ndarray], np.ndarray]] = None
    # What the painter needs to lay strands along: a flow direction anywhere on the part and
    # the centrelines of the locks it was combed into.
    flow_fn: Optional[Callable[[np.ndarray], np.ndarray]] = None
    locks: List[np.ndarray] = field(default_factory=list)
    _grid: list = field(default_factory=list, repr=False)

    def field(self) -> "sdf.SampledField":
        """The part's own distance field, from the grid meshing sampled (or sampled now)."""
        if self._grid:
            return sdf.SampledField.from_grid(*self._grid)
        return sdf.SampledField(self.scene, spacing=self.spacing, margin=0.02)

    def mesh(self) -> Tuple[np.ndarray, np.ndarray]:
        self._grid = []
        verts, quads = sdf.mesh_from_scene(self.scene, self.spacing, smooth_iters=self.smooth, project=1,
                                           grid_out=self._grid)
        if self.trim is not None and len(quads):
            q = np.asarray(quads)
            centres = verts[q].mean(axis=1)
            keep = self.trim.eval(centres) > -self.trim_depth
            quads = q[keep]
            used = np.unique(quads)
            remap = -np.ones(len(verts), dtype=np.int64)
            remap[used] = np.arange(len(used))
            verts, quads = verts[used], remap[quads]
        return verts, quads


# --------------------------------------------------------------------------------------
# the garment library
# --------------------------------------------------------------------------------------

def _s(skel: Skeleton) -> float:
    return skel.props.height / rig.DEFAULT_HEIGHT


def torso_region(skel: Skeleton, *, top: float = 1.0, hem: float = 0.0, sleeves: float = 0.0,
                 collar: float = 0.0, soft: float = 0.025) -> RegionFn:
    """The trunk between `hem` and `top` (fractions of the body height), optionally with
    sleeves running `sleeves` of the way down the arms.

    `collar` raises (+) or lowers (-) the neckline in metres from the base of the neck; the
    garment always covers the shoulders, so a negative collar opens the throat rather than
    stripping the chest.

    The radius here only says *where the garment exists*; it cannot make a sleeve fat.
    `offset_shell` puts the surface where the body's own field reads `gap + thickness`, and
    outside the region it pushes the field solid so the garment ends. A larger radius
    lengthens the sleeve's reach round the limb; it does not lift it off.

    That is worth writing down, because ASSESSMENT lists "tunic sleeves are wider than the
    forearm under them" as a known weakness and the measurement does not support it. Taking
    every sleeve vertex's distance to the nearest point on the body and reading the median,
    in millimetres:

        tunic     shoulder 19   upper arm 14   forearm 13
        shirt     shoulder 19   upper arm 14   forearm 13
        coat      shoulder 26   upper arm 19   forearm 19
        gambeson  shoulder 38   upper arm 32   forearm 31
        robe      shoulder 27   upper arm 21   forearm 40

    The tunic is the closest-fitting sleeved garment in the set and sits 2 mm over its own
    design of 11 mm (3 gap + 8 thickness). What reads as a leg-of-mutton sleeve in a
    character lineup is the *gambeson*, which is a padded jack standing 31-38 mm off the
    arm because that is what padding is, and which half the presets in that render wear.
    Before widening or narrowing anything here, render one figure in a tunic alone."""
    s = _s(skel)
    z0 = hem * skel.props.height
    z1 = top * skel.props.height
    trunk = band_z(z0, z1, soft * s)
    arms: List[RegionFn] = []
    if sleeves > 0.01:
        bones = ["Shoulder.L", "Shoulder.R", "UpperArm.L", "UpperArm.R"]
        if sleeves > 0.55:
            bones += ["LowerArm.L", "LowerArm.R"]
        arm_len = skel.bones["UpperArm.L"].length + skel.bones["LowerArm.L"].length
        reach = arm_len * sleeves
        sh = skel.J["UpperArm.L"]

        def sleeve_fn(P, sh=sh, reach=reach):
            dl = np.linalg.norm(P - sh, axis=1)
            dr = np.linalg.norm(P - (sh * np.array([-1, 1, 1])), axis=1)
            d = np.minimum(dl, dr)
            return 1.0 - sdf_smoothstep(reach - 0.015 * s, reach + 0.010 * s, d)
        arms.append(region_and(near_bones(skel, bones, 0.100 * s, 0.030 * s), sleeve_fn))
    neck_cut = float(skel.J["Neck"][2]) + collar * s
    neck_r = 0.085 * s

    def neckline(P):
        # Cut only a throat-sized hole, so shoulders and chest stay covered -- and cut it
        # crisply. Faded over 5 cm, a padded jack's neckline thinned out over a hand's breadth
        # and ended in a torn-paper edge, which is the first thing the Naming's face view saw.
        near_axis = 1.0 - sdf_smoothstep(neck_r * 0.92, neck_r * 1.10, np.hypot(P[:, 0], P[:, 1] - 0.01 * s))
        above = sdf_smoothstep(neck_cut - 0.010 * s, neck_cut + 0.008 * s, P[:, 2])
        return 1.0 - np.clip(near_axis * above + sdf_smoothstep(neck_cut + 0.06 * s, neck_cut + 0.10 * s, P[:, 2]), 0, 1)
    body_part = region_and(trunk, neckline)
    return region_or(body_part, *arms) if arms else body_part


def legs_region(skel: Skeleton, *, top: float = 0.60, length: float = 1.0, soft: float = 0.02) -> RegionFn:
    s = _s(skel)
    hip = float(skel.J["UpperLeg.L"][2])
    z_top = top * skel.props.height
    ankle = float(skel.J["Foot.L"][2])
    z_bot = ankle + (hip - ankle) * (1.0 - length)
    return region_and(band_z(z_bot, z_top, soft * s),
                      near_bones(skel, ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "Hips"], 0.17 * s, 0.05 * s))


def ragged_floor(z: float, amp: float, teeth: int, phase: float = 0.0) -> Prim:
    """A hem cut that wobbles with the angle round the body, so a garment ends in torn
    points instead of a machined line.

    Biting notches out with spheres, which is the obvious thing to try, punches holes
    straight through a solid garment where the sphere happens to be thicker than the cloth.
    Varying the height of the cut cannot."""
    def fn(P):
        a = np.arctan2(P[:, 1], P[:, 0])
        thr = z + amp * (0.62 * np.cos(teeth * a + phase) + 0.38 * np.cos(2 * teeth * a - phase))
        return thr - P[:, 2]
    lo = np.array([-1e3, -1e3, z - abs(amp) * 1.2])
    hi = np.array([1e3, 1e3, 1e3])
    return Prim(fn, lo, hi, "intersect", 0.0)


def _ring(rx: float, ry: float, z: float, n: int = 28) -> List[List[float]]:
    """A closed elliptical path at height z, for hem and belt rings."""
    pts = []
    for i in range(n + 1):
        a = 2.0 * math.pi * i / n
        pts.append([rx * math.cos(a), ry * math.sin(a), z])
    return pts


def garment_edges(skel: Skeleton, *, hem_z: Optional[float] = None, collar_z: Optional[float] = None,
                  sleeve_end: Optional[float] = None, waist: float = 0.0,
                  edge: float = 0.0045) -> RegionFn:
    """The relief that turns a shrink-wrapped offset into a garment: a doubled hem, a
    standing collar, thick cuffs, and cloth drawn in at the waist.

    Without these a tunic is a coloured layer of skin.  What says `cloth` at any distance is
    the line of light along an edge and the one place the shape is held in."""
    s = _s(skel)
    parts: List[RegionFn] = []
    if hem_z is not None:
        parts.append(relief_band(hem_z - 0.004 * s, hem_z + 0.026 * s, edge * s, 0.008 * s))
    if collar_z is not None:
        parts.append(relief_band(collar_z - 0.012 * s, collar_z + 0.050 * s, edge * 1.25 * s, 0.010 * s))
    if sleeve_end is not None:
        cuffs = []
        for side in ("L", "R"):
            sh = skel.J[f"UpperArm.{side}"]
            wr = skel.J[f"Hand.{side}"]
            cuffs.append(sh + (wr - sh) * sleeve_end)
        parts.append(relief_around(cuffs, 0.030 * s, edge * 0.85 * s, 0.020 * s))
    if abs(waist) > 1e-6:
        wz = float(skel.J["Spine"][2])
        parts.append(relief_band(wz - 0.070 * s, wz + 0.055 * s, -waist * s, 0.032 * s))
    if not parts:
        return lambda P: np.zeros(len(P))
    return relief_sum(*parts)


def tunic(skel: Skeleton, body, *, hem: float = 0.44, sleeves: float = 0.55,
          thickness: float = 0.008, name: str = "tunic") -> Garment:
    s = _s(skel)
    sc = Scene()
    reg = torso_region(skel, top=0.90, hem=hem, sleeves=sleeves, collar=0.012)
    sc.union(offset_shell(body, reg, thickness * s, gap=0.003 * s,
                          relief=garment_edges(skel, collar_z=float(skel.J["Neck"][2]),
                                               sleeve_end=min(sleeves, 1.0), waist=0.010),
                          bounds=zbox(skel, hem * skel.props.height - 0.03 * s, 0.92 * skel.props.height, xy=0.55)))
    # the skirt of the tunic hangs away from the legs instead of shrink-wrapping them
    hip = float(skel.J["UpperLeg.L"][2])
    z_hem = hem * skel.props.height
    sc.union(sdf.loft([
        (np.array([0.0, 0.010 * s, hip + 0.10 * s]), 0.148 * s, 0.108 * s),
        (np.array([0.0, 0.008 * s, hip - 0.02 * s]), 0.158 * s, 0.116 * s),
        (np.array([0.0, 0.004 * s, z_hem + 0.045 * s]), 0.168 * s, 0.124 * s),
        (np.array([0.0, 0.002 * s, z_hem + 0.020 * s]), 0.176 * s, 0.131 * s),
        (np.array([0.0, 0.0, z_hem]), 0.174 * s, 0.129 * s),
    ], LEFT, axis=UP), k=0.014 * s)
    # the hem edge: the skirt doubled back, so it ends on a line of light not a fade
    sc.union(sdf.tube_path(_ring(0.176 * s, 0.131 * s, z_hem + 0.008 * s), 0.0055 * s), k=0.006 * s)
    # a sphere sweep caps its end station with a hemisphere; left alone that hangs between
    # the legs as a dome.  A skirt is open at the bottom.
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    return Garment(name, sc, spacing=0.0075, target_tris=4200, material="cloth")


def shirt(skel: Skeleton, body, *, thickness: float = 0.008) -> Garment:
    sc = Scene()
    s = _s(skel)
    reg = torso_region(skel, top=0.90, hem=0.52, sleeves=0.62, collar=0.004)
    sc.union(offset_shell(body, reg, thickness * s, gap=0.003 * s,
                          relief=garment_edges(skel, hem_z=0.52 * skel.props.height,
                                               collar_z=float(skel.J["Neck"][2]), sleeve_end=0.62,
                                               waist=0.006, edge=0.0035),
                          bounds=zbox(skel, 0.50 * skel.props.height, 0.92 * skel.props.height, xy=0.62)))
    return Garment("shirt", sc, spacing=0.0070, target_tris=3600, material="cloth")


def trousers(skel: Skeleton, body, *, thickness: float = 0.010, length: float = 0.975) -> Garment:
    """Hip to ankle. They end inside the shoe: cut at 0.92 of the leg, the hem stood 3.5 cm
    above the top of a shoe and every villager in shoes had bare ankles between the two."""
    sc = Scene()
    s = _s(skel)
    reg = legs_region(skel, top=0.575, length=length)
    sc.union(offset_shell(body, reg, thickness * s, gap=0.003 * s,
                          bounds=zbox(skel, 0.02, 0.60 * skel.props.height, xy=0.26)))
    return Garment("trousers", sc, spacing=0.0070, target_tris=3600, material="cloth")


def _skirt_weights(skel: Skeleton) -> Callable[[np.ndarray, np.ndarray], np.ndarray]:
    """A skirt hangs from the hips and is pushed by the legs; it is not carried by them.

    Weighted straight from the body, every vertex below the hips took the nearest leg's weights
    whole, so a stride tore the cloth between the legs open and showed the thigh through the
    gap -- the dress, the robe, the kilt and the wrap skirt all did it. Below the hip joint the
    legs' share is handed to the hips, all of it on the centre line between the legs and less
    of it towards the sides and the hem, where the thigh really does push the cloth; and what
    the legs keep is the thigh's, because a skirt does not bend at the knee."""
    bones = list(rig.DEFORM_NAMES)
    B = {b: i for i, b in enumerate(bones)}
    s = _s(skel)
    hips_z = float(skel.J["UpperLeg.L"][2])
    knee_z = float(skel.J["LowerLeg.L"][2])

    def fn(V, W):
        W = np.array(W, float, copy=True)
        z, ax = V[:, 2], np.abs(V[:, 0])
        below = _ss((hips_z - 0.02 * s - z) / (0.10 * s))
        down = np.clip((hips_z - z) / max(hips_z - knee_z, 1e-3), 0.0, 1.0)
        keep = (0.20 + 0.40 * down) * np.clip((ax - 0.02 * s) / (0.09 * s), 0.0, 1.0)
        keep = 1.0 - below * (1.0 - keep)
        for side in ("L", "R"):
            thigh = B["UpperLeg." + side]
            for b in ("LowerLeg.", "Foot.", "Toe."):
                j = B[b + side]
                W[:, thigh] += W[:, j] * below
                W[:, j] *= (1.0 - below)
            moved = W[:, thigh] * (1.0 - keep)
            W[:, thigh] -= moved
            W[:, B["Hips"]] += moved
        return W
    return fn


def skirt(skel: Skeleton, body, *, hem: float = 0.30, flare: float = 1.0, name: str = "skirt") -> Garment:
    s = _s(skel)
    hip = float(skel.J["UpperLeg.L"][2])
    z_hem = hem * skel.props.height
    waist = float(skel.J["Spine"][2])
    sc = Scene()
    outer = sdf.loft([
        (np.array([0.0, 0.0, waist]), 0.134 * s, 0.100 * s),
        (np.array([0.0, 0.0, hip + 0.02 * s]), 0.158 * s, 0.118 * s),
        (np.array([0.0, 0.0, (hip + z_hem) * 0.5]), (0.172 + 0.030 * flare) * s, (0.130 + 0.026 * flare) * s),
        (np.array([0.0, 0.0, z_hem + 0.02 * s]), (0.186 + 0.058 * flare) * s, (0.142 + 0.048 * flare) * s),
        (np.array([0.0, 0.0, z_hem]), (0.187 + 0.058 * flare) * s, (0.143 + 0.048 * flare) * s),
    ], LEFT, axis=UP)
    sc.union(outer)
    # soft vertical folds
    n = 9
    for i in range(n):
        a = 2 * math.pi * i / n
        d = np.array([math.cos(a), math.sin(a), 0.0])
        sc.subtract(sdf.tube_path([d * 0.155 * s + np.array([0, 0, hip + 0.02 * s]),
                                   d * (0.186 + 0.058 * flare) * s + np.array([0, 0, z_hem])],
                                  0.010 * s), k=0.016 * s)
    sc.union(sdf.tube_path(_ring((0.187 + 0.058 * flare) * s, (0.143 + 0.048 * flare) * s,
                                 z_hem + 0.010 * s), 0.0060 * s), k=0.006 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment(name, sc, spacing=0.0080, target_tris=3400, material="cloth")
    g.weight_adjust = _skirt_weights(skel)
    return g


def dress(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    g = skirt(skel, body, hem=0.22, flare=0.8, name="dress")
    reg = torso_region(skel, top=0.90, hem=0.55, sleeves=0.45, collar=0.0)
    g.scene.union(offset_shell(body, reg, 0.010 * s, gap=0.004 * s,
                               bounds=zbox(skel, 0.53 * skel.props.height, 0.92 * skel.props.height, xy=0.50)), k=0.01 * s)
    g.target_tris = 4400
    return g


def robe(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    g = skirt(skel, body, hem=0.08, flare=0.55, name="robe")
    reg = torso_region(skel, top=0.92, hem=0.50, sleeves=1.0, collar=0.020)
    g.scene.union(offset_shell(body, reg, 0.013 * s, gap=0.006 * s,
                               bounds=zbox(skel, 0.48 * skel.props.height, 0.94 * skel.props.height, xy=0.80)), k=0.012 * s)
    # wide sleeve bells
    for side in ("L", "R"):
        wr = skel.J[f"Hand.{side}"]
        el = skel.J[f"LowerArm.{side}"]
        d = rig._unit(wr - el)
        g.scene.union(sdf.loft([
            (el + d * 0.10 * s, 0.075 * s, 0.075 * s),
            (wr - d * 0.02 * s, 0.098 * s, 0.098 * s),
            (wr + d * 0.03 * s, 0.100 * s, 0.100 * s),
        ], FWD), k=0.02 * s)
    g.target_tris = 4800
    g.spacing = 0.0080
    return g


def _ss(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def _chunked(fn: Callable[[np.ndarray], np.ndarray], n: int = 400_000) -> Callable[[np.ndarray], np.ndarray]:
    """`fn` over at most `n` points at a time. A sampled field reads eight gathered copies of
    its input back, which over a cloak's whole box is gigabytes at once."""
    def run(P):
        if len(P) <= n:
            return fn(P)
        return np.concatenate([fn(P[i:i + n]) for i in range(0, len(P), n)])
    return run


def cowl_field(skel: Skeleton, hs: Optional[bodylib.HeadStyle] = None, flare: float = 0.16,
               peak: float = 1.0, spacing: float = 0.005) -> sdf.SampledField:
    """The head as a hood falls from it.

    `drape_field` over the head: every section of the head, and of the spare cloth a hood is
    cut with behind the crown, pushed out by `flare` for every metre of fall. A hood drawn up
    rests on the crown and the back of the skull and falls from the widest part of the head
    straight past the ears to the shoulders. It does not follow the jaw and the neck back in,
    which is what the old hood -- a bigger head with a hole in it -- did."""
    s = _s(skel)
    L = bodylib.head_landmarks(skel, hs)
    head = _head_field(skel, hs)
    lo = np.array([-0.27 * s, -0.25 * s, float(skel.J["Chest"][2])])
    hi = np.array([0.27 * s, 0.32 * s, float(L["top"][2]) + 0.08 * s])
    n = np.ceil((hi - lo) / spacing).astype(int) + 1
    axes = [lo[i] + np.arange(n[i]) * spacing for i in range(3)]
    gx, gy, gz = np.meshgrid(*axes, indexing="ij")
    P = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
    F = _chunked(head.eval)(P)
    if peak > 0:
        pk = sdf.ellipsoid(L["skull_c"] + np.array([0.0, 0.070 * s, 0.050 * s]),
                           np.array([0.030, 0.050, 0.040]) * s * peak)
        F = np.minimum(F, _chunked(pk.fn)(P))
    F = F.reshape(tuple(n))
    out = np.empty_like(F)
    run = np.full(F.shape[:2], 1e3)
    for k in range(F.shape[2] - 1, -1, -1):
        run = np.minimum(run - flare * spacing, F[:, :, k])
        out[:, :, k] = run
    return sdf.SampledField.from_grid(out, lo, spacing)


def _surface_point(fld, off: float, a: np.ndarray, z: float, r_max: float = 0.5,
                   centre=(0.0, 0.0)) -> np.ndarray:
    """Where a horizontal ray at height `z`, `a` radians round from straight ahead, leaves the
    level set `fld = off`: for laying a rim or a clasp on a surface made from a field."""
    d = np.array([math.sin(a), -math.cos(a), 0.0])
    o = np.array([centre[0], centre[1], z])
    lo_r, hi_r = 0.0, r_max
    for _ in range(40):
        m = 0.5 * (lo_r + hi_r)
        if float(fld.eval((o + d * m)[None])[0]) < off:
            lo_r = m
        else:
            hi_r = m
    return o + d * hi_r


def _signed_around(P: np.ndarray) -> np.ndarray:
    """Radians round the body from straight ahead, positive to the left: -pi..pi."""
    return np.arctan2(P[:, 0], -P[:, 1])


def _cloak_weights(skel: Skeleton, hooded: bool) -> Callable[[np.ndarray], np.ndarray]:
    """What a cloak moves with. The hood with the head above the jaw, fading into the neck by
    the shoulders; the shoulder girdle at the points of the shoulders, and some of each upper
    arm where the cloth lies over it; then the chest, the spine and the hips down the back;
    and near the hem the front panels take a share of the thigh on their side, so a stride
    pushes the cloak open instead of through it. Weighted from the body instead, a cloak to
    the knee is torn down the middle by every step."""
    bones = list(rig.DEFORM_NAMES)
    B = {b: i for i, b in enumerate(bones)}
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    J = skel.J
    neck_z, chest_z = float(J["Neck"][2]), float(J["Chest"][2])
    spine_z, hips_z = float(J["Spine"][2]), float(J["Hips"][2])

    def fn(V):
        W = np.zeros((len(V), len(bones)))
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        ax = np.abs(x)
        w_head = _ss((z - (L["chin_z"] - 0.010 * s)) / (0.050 * s)) if hooded else np.zeros(len(V))
        w_neck = (_ss((z - (neck_z - 0.010 * s)) / (0.035 * s)) * (1.0 - w_head)
                  * np.clip((0.13 * s - ax) / (0.05 * s), 0.0, 1.0))
        rest = 1.0 - w_head - w_neck
        w_sh = rest * 0.40 * np.clip((ax - 0.09 * s) / (0.12 * s), 0.0, 1.0) * _ss((z - (chest_z - 0.06 * s)) / (0.12 * s))
        w_ua = (rest * 0.30 * np.clip((ax - 0.21 * s) / (0.06 * s), 0.0, 1.0)
                * _ss((z - (chest_z - 0.24 * s)) / (0.14 * s)) * (1.0 - _ss((z - (neck_z - 0.03 * s)) / (0.05 * s))))
        rest = rest - w_sh - w_ua
        w_ch = rest * _ss((z - spine_z) / (chest_z - spine_z))
        w_hip = rest * _ss((spine_z - z) / (spine_z - hips_z))
        w_sp = rest - w_ch - w_hip
        w_leg = w_hip * 0.45 * _ss((hips_z - 0.10 * s - z) / (0.25 * s)) * np.clip(-y / (0.10 * s), 0.0, 1.0)
        w_hip = w_hip - w_leg
        left = x >= 0
        for side, m in (("L", left), ("R", ~left)):
            W[m, B["Shoulder." + side]] = w_sh[m]
            W[m, B["UpperArm." + side]] = w_ua[m]
            W[m, B["UpperLeg." + side]] = w_leg[m]
        W[:, B["Head"]] = w_head
        W[:, B["Neck"]] = w_neck
        W[:, B["Chest"]] = w_ch
        W[:, B["Spine"]] = w_sp
        W[:, B["Hips"]] = w_hip
        return W
    return fn


def cloak(skel: Skeleton, body, *, hooded: bool = False, hem: float = 0.30, ragged: int = 0,
          open_front: bool = True, hem_z: Optional[float] = None, name: Optional[str] = None) -> Garment:
    """A cloak: cloth laid over the shoulders and let fall to the knee.

    The old one was a rigid tube from the shoulders to the calves -- the lampshade the shoulder
    cape was -- and the ragged one cut from it exported nothing at all. This is the cape's
    construction carried down: one sheet over the drape of the body, resting on the points of
    the shoulders and falling past the arms, folds that start below the shoulder blades and
    deepen towards the hem, the hem a hand lower behind than in front, open down the front from
    a clasp at the throat and opening wider as it falls.

    Hooded, the same sheet is carried up over the head by `cowl_field`, with the face cut out
    of it and a peak of spare cloth behind the crown, and it moves with the head above the jaw.
    `ragged` tears the hem into that many leaf-shaped points (the Woodfolk's); `open_front`
    False closes it all round (a hood's own short cape)."""
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    neck = float(skel.J["Neck"][2])
    z_hem = hem_z if hem_z is not None else hem * skel.props.height
    sh = shoulder_line(body, skel)
    # the clasp closes the cloak at the base of the throat; hooded, below the face opening
    clasp = sh - 0.015 * s if not hooded else min(sh - 0.015 * s, float(L["chin_z"]) - 0.036 * s)
    # The flare is the cloak's own cut, not what hangs it off the body: the drape already takes
    # in every section below the shoulders. At the cape's 0.10 per metre a cloak to the knee
    # came out 0.92 m across the hem, a bell rather than cloth falling from two shoulders.
    drape = drape_field(body, skel, flare=0.045, arm_far=1.0)
    if hooded:
        # a smaller peak and less flare: at a full peak and 0.16 the spare cloth fell straight
        # from a corner behind the crown, and in profile the hood was a box on the head
        cowl = cowl_field(skel, flare=0.11, peak=0.6)
        fld = FieldFn(lambda P: np.minimum(drape.eval(P), cowl.eval(P)))
    else:
        fld = drape
    top = sh + 0.045 * s
    n_folds = 14
    start = clasp - 0.050 * s                   # the folds start under the shoulder blades

    amp_k = float(np.clip((start - z_hem) / (0.30 * s), 0.35, 1.0))

    def fall(P):
        return np.clip((start - P[:, 2]) / max(start - z_hem, 1e-3), 0.0, 1.0)

    def hem_at(P):
        a = _around(P)
        sa = _signed_around(P)
        z = z_hem - 0.075 * s * (1.0 - np.cos(a)) * 0.5 + 0.008 * s * np.sin(n_folds * sa + 0.4)
        if ragged:
            # leaf-shaped points: long tips, short rounded notches between them
            t = np.abs(np.sin(0.5 * ragged * sa + 0.7))
            z = z - 0.060 * s * (1.0 - t ** 0.55) + 0.012 * s
        return z

    if hooded:
        f_top = L["brow_z"] + 0.030 * s
        f_bot = L["chin_z"] - 0.022 * s
        f_zc, f_az, f_ax = 0.5 * (f_top + f_bot), 0.5 * (f_top - f_bot), 0.074 * s
        f_cut = float(L["skull_c"][1]) - 0.020 * s

    def face_hole(P):
        e = np.sqrt((P[:, 0] / f_ax) ** 2 + ((P[:, 2] - f_zc) / f_az) ** 2)
        return (np.clip((1.0 - e) * f_az / (0.005 * s), 0.0, 1.0)
                * np.clip((f_cut - P[:, 1]) / (0.006 * s), 0.0, 1.0))

    def region(P):
        z = P[:, 2]
        w = np.clip((z - hem_at(P)) / (0.006 * s), 0.0, 1.0)
        if open_front:
            a_open = np.radians(7.0 + 29.0 * fall(P) ** 0.8)
            r = np.hypot(P[:, 0], P[:, 1])
            o = np.clip((_around(P) - a_open) * r / (0.006 * s), 0.0, 1.0)
            w = w * np.where(z < clasp, o, 1.0)
        if hooded:
            w = w * (1.0 - face_hole(P))
        else:
            r = np.hypot(P[:, 0], P[:, 1] - 0.012 * s)
            w = w * np.clip((top - z) / (0.006 * s), 0.0, 1.0) * np.clip((r - 0.080 * s) / (0.006 * s), 0.0, 1.0)
        return w

    def relief(P):
        sa = _signed_around(P)
        depth = fall(P) ** 0.7
        folds = 0.75 * (0.5 + 0.5 * np.sin(n_folds * sa + 0.4)) + 0.25 * (0.5 + 0.5 * np.sin(31 * sa + 1.3))
        # a short cape has room for shallow folds only
        out = 0.024 * s * amp_k * depth * folds
        if hooded:
            # the edge of the face opening rolled back on itself, standing a little proud
            e = np.sqrt((P[:, 0] / f_ax) ** 2 + ((P[:, 2] - f_zc) / f_az) ** 2)
            near = np.clip(1.0 - np.abs(e - 1.0) * f_az / (0.016 * s), 0.0, 1.0)
            out = out + 0.004 * s * near * (P[:, 1] < f_cut + 0.02 * s)
        return out

    z_top = float(L["top"][2]) + 0.10 * s if hooded else top + 0.03 * s
    shell, trim = draped_shell(fld, region, 0.012 * s, 0.016 * s,
                               zbox(skel, z_hem - 0.14 * s, z_top, xy=0.48, ymin=-0.36, ymax=0.44),
                               relief=relief)
    sc = Scene()
    sc.union(shell)
    off = 0.016 * s + 0.006 * s
    if not hooded:
        ring = np.array(_ring(0.086 * s, 0.082 * s, sh + 0.032 * s)) + np.array([0.0, 0.010 * s, 0.0])
        sc.union(sdf.tube_path(ring, 0.012 * s, closed=False), k=0.008 * s)
    # the clasp at the throat: a round brooch on the front of the cloth
    front = _surface_point(fld, off, 0.0, clasp + 0.004 * s)
    sc.union(sdf.ellipsoid(front + np.array([0.0, -0.004 * s, 0.0]), [0.014 * s, 0.006 * s, 0.014 * s]), k=0.003 * s)
    nm = name or ("hooded_cloak" if hooded else "cloak")
    g = Garment(nm, sc, spacing=0.0055 if not hooded else 0.0050, smooth=4, target_tris=5200 if hooded else 4400,
                material="cloth", trim=trim, trim_depth=0.0)
    g.weight_fn = _cloak_weights(skel, hooded)
    g.double_sided = True
    return g


def hood(skel: Skeleton, body) -> Garment:
    """A hood on its own: the cloak's hood with a short cape of its own over the shoulders, closed
    all round below the face, so the join at the neck is cloth and not the rim of a skull cap."""
    s = _s(skel)
    neck = float(skel.J["Neck"][2])
    g = cloak(skel, body, hooded=True, open_front=False, hem_z=neck - 0.115 * s, name="hood")
    g.target_tris = 2600
    return g


def boots(skel: Skeleton, body, *, high: float = 0.30) -> Garment:
    s = _s(skel)
    sc = Scene()
    ankle = float(skel.J["Foot.L"][2])
    knee = float(skel.J["LowerLeg.L"][2])
    top = ankle + (knee - ankle) * high
    reg = region_and(band_z(-0.05, top, 0.018 * s),
                     near_bones(skel, ["Foot.L", "Foot.R", "Toe.L", "Toe.R", "LowerLeg.L", "LowerLeg.R"], 0.13 * s, 0.05 * s))
    sc.union(solid_shell(body, reg, 0.013 * s, gap=0.003 * s,
                         bounds=zbox(skel, -0.01, top + 0.03 * s, xy=0.24, ymin=-0.32, ymax=0.16)))
    # a sole and a small heel
    for side in ("L", "R"):
        an = skel.J[f"Foot.{side}"]
        tip = skel.J[f"ToeTip.{side}"]
        sc.union(sdf.loft([
            (np.array([an[0], an[1] + 0.075 * s, 0.012 * s]), 0.048 * s, 0.014 * s),
            (np.array([an[0], an[1], 0.010 * s]), 0.054 * s, 0.012 * s),
            (np.array([an[0], tip[1] + 0.012 * s, 0.010 * s]), 0.058 * s, 0.011 * s),
        ], LEFT), k=0.012 * s)
        sc.union(sdf.box([an[0], an[1] + 0.065 * s, 0.014 * s], [0.042 * s, 0.038 * s, 0.016 * s], round_r=0.008 * s), k=0.012 * s)
    sc.intersect(sdf.plane([0.0, 0.0, 0.0], [0.0, 0.0, -1.0]), k=0.006 * s)
    return Garment("boots", sc, spacing=0.0055, target_tris=1600, material="leather")


def shoes(skel: Skeleton, body) -> Garment:
    g = boots(skel, body, high=0.07)
    g.name = "shoes"
    g.target_tris = 1100
    return g


def gloves(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    sc = Scene()
    reg = near_bones(skel, ["Hand.L", "Hand.R"], 0.115 * s, 0.045 * s)
    cuff = near_bones(skel, ["LowerArm.L", "LowerArm.R"], 0.075 * s, 0.03 * s)
    wrist_l = skel.J["Hand.L"]
    wrist_r = skel.J["Hand.R"]

    def near_wrist(P):
        d = np.minimum(np.linalg.norm(P - wrist_l, axis=1), np.linalg.norm(P - wrist_r, axis=1))
        return 1.0 - sdf_smoothstep(0.085 * s, 0.115 * s, d)
    lo = np.minimum(wrist_l, wrist_r) - 0.20 * s
    hi = np.maximum(wrist_l, wrist_r) + 0.22 * s
    sc.union(solid_shell(body, region_or(reg, region_and(cuff, near_wrist)), 0.008 * s, gap=0.002 * s,
                         bounds=(lo, hi)))
    return Garment("gloves", sc, spacing=0.0040, target_tris=1200, material="leather")


def belt(skel: Skeleton, body, *, pouch: bool = True) -> Garment:
    s = _s(skel)
    sc = Scene()
    z = float(skel.J["Spine"][2]) - 0.02 * s
    reg = band_z(z - 0.026 * s, z + 0.026 * s, 0.006 * s)
    sc.union(offset_shell(body, reg, 0.009 * s, gap=0.013 * s,
                          bounds=zbox(skel, z - 0.05 * s, z + 0.05 * s, xy=0.24)))
    # buckle
    sc.union(sdf.box([0.0, -0.135 * s, z], [0.026 * s, 0.014 * s, 0.024 * s], round_r=0.005 * s), k=0.006 * s)
    if pouch:
        sc.union(sdf.box([0.105 * s, -0.030 * s, z - 0.055 * s], [0.042 * s, 0.030 * s, 0.046 * s], round_r=0.014 * s), k=0.012 * s)
        sc.union(sdf.box([0.105 * s, -0.030 * s, z - 0.012 * s], [0.044 * s, 0.032 * s, 0.010 * s], round_r=0.006 * s), k=0.008 * s)
    return Garment("belt", sc, spacing=0.0040, target_tris=900, material="leather")


def apron(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    sc = Scene()
    chest = float(skel.J["Chest"][2])
    hem = 0.36 * skel.props.height

    def front(P):
        return (1.0 - sdf_smoothstep(-0.02 * s, 0.03 * s, P[:, 1])) * \
            (1.0 - sdf_smoothstep(0.115 * s, 0.155 * s, np.abs(P[:, 0])))
    reg = region_and(band_z(hem, chest + 0.06 * s, 0.02 * s), front)
    sc.union(offset_shell(body, reg, 0.010 * s, gap=0.014 * s,
                          bounds=zbox(skel, hem - 0.03 * s, chest + 0.10 * s, xy=0.22, ymin=-0.26, ymax=0.10)))
    # neck strap and waist ties
    sc.union(sdf.tube_path([[0.05 * s, -0.04 * s, chest + 0.06 * s], [0.055 * s, 0.02 * s, float(skel.J["Neck"][2])],
                            [0.0, 0.075 * s, float(skel.J["Neck"][2]) + 0.005 * s],
                            [-0.055 * s, 0.02 * s, float(skel.J["Neck"][2])], [-0.05 * s, -0.04 * s, chest + 0.06 * s]],
                           0.008 * s), k=0.01 * s)
    return Garment("apron", sc, spacing=0.0060, target_tris=1200, material="cloth")


def gambeson(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    # sleeves to the wrist, as the arming coat's: ending at three quarters of the arm they left
    # a strip of bare forearm above every pair of padded gloves
    g = tunic(skel, body, hem=0.42, sleeves=0.97, thickness=0.026, name="gambeson")
    # quilted channels
    hip = float(skel.J["UpperLeg.L"][2])
    chest = float(skel.J["Chest"][2])
    for i in range(8):
        a = 2 * math.pi * i / 8
        d = np.array([math.cos(a), math.sin(a), 0.0])
        g.scene.subtract(sdf.tube_path([d * 0.175 * s + np.array([0, 0, chest + 0.10 * s]),
                                        d * 0.185 * s + np.array([0, 0, hip + 0.03 * s]),
                                        d * 0.200 * s + np.array([0, 0, 0.44 * skel.props.height])],
                                       0.010 * s), k=0.016 * s)
    g.material = "cloth"
    g.target_tris = 4400
    g.spacing = 0.0080
    return g


# -- armour ------------------------------------------------------------------------------
#
# A cuirass on its own reads as a corset: bare shoulders over it, bare arms out of it, and a
# hard edge at the waist with nothing below. Armour is a harness -- a padded coat under it
# whose sleeves and skirt show, a gorget closing the neck, spaulders over the shoulder caps,
# a fauld over the hips and tassets over the thighs -- and the harness is what reads.

COAT_GAP, COAT_T = 0.003, 0.018       # the arming coat: 3 mm off the body, 18 mm of padding
PLATE_T = 0.0055                      # 5.5 mm of steel, a shade thick for the eye


def arming_coat(skel: Skeleton, body, name: str) -> Garment:
    """The padded coat worn under plate or a brigandine: sleeves to the wrist, a skirt to
    mid-thigh, quilted in vertical channels. It is what shows at the arms and below the fauld."""
    s = _s(skel)
    g = tunic(skel, body, hem=0.40, sleeves=0.97, thickness=COAT_T, name=name)
    chest = float(skel.J["Chest"][2])
    hip = float(skel.J["UpperLeg.L"][2])
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        d = np.array([math.cos(a), math.sin(a) * 0.80, 0.0])
        g.scene.subtract(sdf.tube_path([d * 0.172 * s + np.array([0, 0, chest + 0.12 * s]),
                                        d * 0.190 * s + np.array([0, 0, hip + 0.03 * s]),
                                        d * 0.205 * s + np.array([0, 0, 0.42 * skel.props.height])],
                                       0.006 * s), k=0.010 * s)
    g.material = "cloth"
    g.target_tris = 4600
    return g


def _arm_exclusion(skel: Skeleton, radius: float, start: float = 0.055) -> RegionFn:
    """1 on the arms beyond the point of the shoulder: where a cuirass must not go."""
    s = _s(skel)
    segs = []
    for side in ("L", "R"):
        sh = skel.J["UpperArm.%s" % side]
        hand = skel.J["HandTip.%s" % side]
        d = sdf._unit(hand - sh)
        segs.append((sh + d * start * s, hand))
    return near_segments(segs, radius * s, 0.018 * s)


def _neck_hole(skel: Skeleton, r: float, z_from: float) -> RegionFn:
    """0 inside a vertical shaft round the neck above `z_from`, 1 elsewhere."""
    s = _s(skel)

    def fn(P):
        near = 1.0 - sdf_smoothstep(r - 0.008 * s, r + 0.008 * s, np.hypot(P[:, 0], P[:, 1] - 0.010 * s))
        above = sdf_smoothstep(z_from - 0.010 * s, z_from + 0.010 * s, P[:, 2])
        return 1.0 - near * above
    return fn


def _lame_ring(z_top: float, z_bot: float, rx: float, ry: float, cy: float, flare: float,
               thickness: float, sector=None) -> Prim:
    """One lame of a fauld or a tasset: a band of steel `thickness` thick round an ellipse,
    flaring `flare` outward towards its lower edge. `sector` (half-spaces) limits it to part of
    the ring -- a tasset is a lame over one thigh."""
    zm = 0.5 * (z_top + z_bot)
    outer = sdf.loft([(np.array([0.0, cy, z_top]), rx, ry),
                      (np.array([0.0, cy, zm]), rx + 0.5 * flare, ry + 0.5 * flare),
                      (np.array([0.0, cy, z_bot]), rx + flare, ry + flare)], LEFT, axis=UP)
    sub = Scene()
    sub.union(outer)
    sub.subtract(sdf.loft([(np.array([0.0, cy, z_top]), rx - thickness, ry - thickness),
                           (np.array([0.0, cy, zm]), rx + 0.5 * flare - thickness, ry + 0.5 * flare - thickness),
                           (np.array([0.0, cy, z_bot]), rx + flare - thickness, ry + flare - thickness)],
                          LEFT, axis=UP))
    sub.intersect(sdf.plane([0.0, 0.0, z_top], [0.0, 0.0, 1.0]))
    sub.intersect(sdf.plane([0.0, 0.0, z_bot], [0.0, 0.0, -1.0]))
    if sector is not None:
        for pr in sector:
            sub.intersect(pr)
    lo = np.array([-(rx + flare) - 0.01, cy - (ry + flare) - 0.01, z_bot - 0.01])
    hi = np.array([rx + flare + 0.01, cy + ry + flare + 0.01, z_top + 0.01])
    return Prim(sub.eval, lo, hi, "union", 0.0)


def fauld_and_tassets(skel: Skeleton, *, gap: float, thickness: float = PLATE_T, lames: int = 3,
                      tassets: bool = True) -> List[Prim]:
    """Hoops of steel over the hips below the cuirass, each overlapping the one below, and two
    tassets hanging from the last over the front of the thighs."""
    s = _s(skel)
    waist = float(skel.J["Spine"][2])
    # the pelvis at the hips measures +-0.18 m by -0.09..+0.12 m, before the coat
    rx0, ry0, cy = (0.180 + gap) * s, (0.108 + gap) * s, 0.014 * s
    top = waist - 0.010 * s
    step = 0.040 * s
    out: List[Prim] = []
    for i in range(lames):
        zt = top - i * step
        zb = zt - step - 0.010 * s
        out.append(_lame_ring(zt, zb, rx0 + 0.004 * i * s, ry0 + 0.004 * i * s, cy, 0.006 * s, thickness * s))
    if tassets:
        z0 = top - lames * step - 0.004 * s
        for side in (1.0, -1.0):
            for i in range(3):
                zt = z0 - i * 0.046 * s
                zb = zt - 0.056 * s
                sector = [sdf.plane([side * 0.016 * s, 0.0, 0.0], [-side, 0.0, 0.0]),
                          sdf.plane([0.0, cy + 0.030 * s, 0.0], [0.0, 1.0, 0.0]),
                          sdf.plane([side * 0.205 * s, 0.0, 0.0], [side, 0.0, 0.0])]
                out.append(_lame_ring(zt, zb, rx0 + (0.012 + 0.004 * i) * s, ry0 + (0.016 + 0.004 * i) * s,
                                      cy, 0.006 * s, thickness * s, sector=sector))
    return out


def gorget(skel: Skeleton, body, *, gap: float, thickness: float = PLATE_T) -> Prim:
    """A collar of steel from over the collarbones up the neck, lower in front than behind so
    the chin clears it, in three lames that step in towards the throat."""
    s = _s(skel)
    neck = float(skel.J["Neck"][2])

    def region(P):
        a = _around(P)
        top = neck + (0.030 + 0.060 * (1.0 - np.cos(a)) * 0.5) * s
        r = np.hypot(P[:, 0], P[:, 1] - 0.010 * s)
        w = (1.0 - sdf_smoothstep(top - 0.004 * s, top + 0.004 * s, P[:, 2])) * \
            sdf_smoothstep(neck - 0.060 * s, neck - 0.050 * s, P[:, 2])
        # a ring round the neck: out to 0.14 m it was a plate across the shoulder blades
        return w * (1.0 - sdf_smoothstep(0.100 * s, 0.112 * s, r))

    def relief(P):
        z = P[:, 2]
        # three lames, each standing a little proud of the one above it
        lame = np.floor(np.clip((neck + 0.070 * s - z) / (0.034 * s), 0.0, 2.99))
        taper = np.clip((z - (neck - 0.050 * s)) / (0.12 * s), 0.0, 1.0)
        return 0.004 * s * lame - 0.012 * s * taper
    return offset_shell(body, region, thickness * s, gap=gap * s, relief=relief,
                        bounds=zbox(skel, neck - 0.08 * s, neck + 0.12 * s, xy=0.20, ymin=-0.18, ymax=0.18))


def spaulders(skel: Skeleton, body, *, gap: float, thickness: float = PLATE_T, lames: int = 3) -> List[Prim]:
    """Steel over each shoulder cap: three lames stepping down the top of the arm, each
    overlapping the next, following the body's own shoulder rather than a sphere near it."""
    s = _s(skel)
    out: List[Prim] = []
    for side, sx in (("L", 1.0), ("R", -1.0)):
        sh = skel.J["UpperArm.%s" % side]
        el = skel.J["LowerArm.%s" % side]
        d = sdf._unit(el - sh)
        # "up" across the arm: perpendicular to it, in the plane of the arm and the vertical
        up = sdf._unit(np.array([0.0, 0.0, 1.0]) - d * d[2])
        for i in range(lames):
            a0 = (-0.030 + 0.050 * i) * s
            a1 = a0 + 0.062 * s

            def region(P, sh=sh, d=d, up=up, a0=a0, a1=a1):
                t = (P - sh) @ d
                h = (P - sh) @ up
                along = sdf_smoothstep(a0 - 0.004 * s, a0 + 0.004 * s, t) * \
                    (1.0 - sdf_smoothstep(a1 - 0.004 * s, a1 + 0.004 * s, t))
                over = sdf_smoothstep(-0.030 * s, -0.016 * s, h)
                return along * over
            out.append(offset_shell(body, region, thickness * s, gap=(gap + 0.005 * (lames - 1 - i)) * s,
                                    bounds=(np.minimum(sh, el) - 0.13 * s, np.maximum(sh, el) + 0.13 * s)))
    return out


def _rivet_rows(body, skel: Skeleton, off: float, z0: float, z1: float, pitch: float,
                skip: RegionFn) -> List[Prim]:
    """Rivet heads in rows round the torso, on the surface `off` metres out from the body."""
    s = _s(skel)
    out: List[Prim] = []
    z = z0
    row = 0
    while z <= z1:
        n = 26
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * (row % 2)) / n
            dirv = np.array([math.sin(a), -math.cos(a), 0.0])
            P = np.array([[0.0, 0.010 * s, z]]) + dirv[None] * 0.30 * s
            for _ in range(8):
                dd = body.eval(P) - off
                P = P - body.gradient(P) * dd[:, None]
            if not np.all(np.isfinite(P)) or skip(P)[0] > 0.5 or abs(P[0, 2] - z) > 0.03 * s:
                continue
            out.append(sdf.sphere(P[0], 0.0042 * s, k=0.002 * s))
        z += pitch
        row += 1
    return out


def plate_torso(skel: Skeleton, body, *, brigandine: bool = False) -> Garment:
    """A harness: an arming coat, a cuirass to the base of the neck, a gorget, spaulders, a
    fauld and tassets -- or, for the brigandine, a riveted leather body over the same coat,
    with a standing collar and leather lames."""
    s = _s(skel)
    name = "brigandine" if brigandine else "plate_torso"
    neck = float(skel.J["Neck"][2])
    waist = float(skel.J["Spine"][2])
    coat = arming_coat(skel, body, name + "_coat")
    cuirass_gap = COAT_GAP + COAT_T + 0.006
    arms = _arm_exclusion(skel, 0.070)
    # Over the tops of the shoulders and round the base of the neck. Cut off at a height just
    # above the Neck joint, the plate ended in a flat shelf from shoulder to shoulder -- the
    # body's shoulders stand higher than that joint -- and read as a box with a head in it.
    sh = shoulder_line(body, skel)
    region = region_and(band_z(waist - 0.030 * s, sh + 0.070 * s, 0.010 * s), region_not(arms),
                        _neck_hole(skel, 0.098 * s, neck - 0.010 * s))
    t_body = 0.008 if brigandine else PLATE_T
    sc = Scene()
    sc.union(offset_shell(body, region, t_body * s, gap=cuirass_gap * s,
                          bounds=zbox(skel, waist - 0.06 * s, neck + 0.10 * s, xy=0.34)))
    if not brigandine:
        # the breastplate's keel, which is what makes steel read as shaped rather than poured
        chest = float(skel.J["Chest"][2])
        sc.union(sdf.loft([(np.array([0.0, -0.140 * s, chest + 0.090 * s]), 0.050 * s, 0.012 * s),
                           (np.array([0.0, -0.152 * s, chest - 0.010 * s]), 0.046 * s, 0.016 * s),
                           (np.array([0.0, -0.136 * s, waist + 0.020 * s]), 0.034 * s, 0.012 * s)],
                          LEFT, axis=UP), k=0.030 * s)
    # the lames below the waist overlap the cuirass's hem
    for pr in fauld_and_tassets(skel, gap=cuirass_gap + 0.012, thickness=0.007 if brigandine else PLATE_T,
                                tassets=not brigandine):
        sc.union(pr)
    main = Garment(name, sc, spacing=0.0034, smooth=3, target_tris=5200,
                   material="leather" if brigandine else "iron")
    steel = Scene()
    if brigandine:
        # a standing collar of the same leather, and rivets in rows over the whole body
        def collar_region(P):
            return 1.0 - sdf_smoothstep(0.100 * s, 0.115 * s, np.hypot(P[:, 0], P[:, 1]))
        main.scene.union(offset_shell(body, region_and(band_z(neck - 0.010 * s, neck + 0.070 * s, 0.006 * s),
                                                       collar_region),
                                      0.010 * s, gap=(cuirass_gap - 0.006) * s,
                                      bounds=zbox(skel, neck - 0.04 * s, neck + 0.10 * s, xy=0.16,
                                                  ymin=-0.14, ymax=0.14)), k=0.008 * s)
        for pr in _rivet_rows(body, skel, (cuirass_gap + t_body) * s, waist + 0.010 * s, neck - 0.030 * s,
                              0.034 * s, arms):
            steel.union(pr)
    else:
        steel.union(gorget(skel, body, gap=cuirass_gap + PLATE_T + 0.002))
        for pr in spaulders(skel, body, gap=cuirass_gap + PLATE_T + 0.004):
            steel.union(pr)
    layers = [coat]
    if steel.prims:
        layers.append(Garment(name + "_steel", steel, spacing=0.0030, smooth=3,
                              target_tris=2600 if not brigandine else 3000, material="iron"))
    main.layers = layers
    return main


def pauldrons(skel: Skeleton, body) -> Garment:
    """Spaulders on their own, for a brigandine or a coat: the shoulder caps in steel."""
    sc = Scene()
    for pr in spaulders(skel, body, gap=0.032):
        sc.union(pr)
    return Garment("pauldrons", sc, spacing=0.0032, smooth=3, target_tris=2200, material="iron")


def greaves(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    sc = Scene()
    knee = float(skel.J["LowerLeg.L"][2])
    ankle = float(skel.J["Foot.L"][2])

    def shin_front(P):
        return 1.0 - sdf_smoothstep(-0.02 * s, 0.04 * s, P[:, 1])
    reg = region_and(band_z(ankle + 0.035 * s, knee + 0.015 * s, 0.015 * s),
                     near_bones(skel, ["LowerLeg.L", "LowerLeg.R"], 0.085 * s, 0.03 * s), shin_front)
    sc.union(offset_shell(body, reg, 0.010 * s, gap=0.010 * s,
                          bounds=zbox(skel, ankle, knee + 0.08 * s, xy=0.24, ymin=-0.20, ymax=0.14)))
    for side, sx in (("L", 1), ("R", -1)):
        kn = skel.J[f"LowerLeg.{side}"]
        sc.union(sdf.ellipsoid(kn + np.array([0.0, -0.052 * s, 0.012 * s]), [0.052 * s, 0.028 * s, 0.052 * s], k=0.012 * s))
    return Garment("greaves", sc, spacing=0.0045, target_tris=1300, material="iron")


def helm(skel: Skeleton, body, *, open_face: bool = True) -> Garment:
    """A nasal helm: a steel cap stood off the skull by the hair under it, down to the brow in
    front, over the tops of the ears at the sides and lower behind; a rolled rim with rivets,
    a comb ridge from brow to nape, and a nasal down the nose.

    It is an offset of the head it sits on. The old one was an ellipsoid 3 % bigger than the
    vault, which the new skull's brow, occiput and ears -- and any hair at all -- came through."""
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    head = _head_field(skel)
    gap, t = 0.013 * s, 0.0045 * s
    front_z = float(L["brow_z"]) + 0.012 * s
    side_z = float(L["ear_c"][2] + L["ear_r"][2]) + 0.004 * s
    back_z = float(L["nape_z"]) + 0.030 * s

    def rim_z(a):
        a = np.asarray(a, float)
        u = _ss(a / (0.5 * math.pi))
        v = _ss((a - 0.5 * math.pi) / (0.5 * math.pi))
        return np.where(a < 0.5 * math.pi, front_z + (side_z - front_z) * u, side_z + (back_z - side_z) * v)

    def cap(P):
        d = head.eval(P)
        shell = np.maximum(d - (gap + t), gap - d)
        return np.maximum(shell, rim_z(_around(P)) - P[:, 2])
    lo, hi = head.bounds(0.0)
    sc = Scene()
    sc.union(Prim(_chunked(cap), lo, hi, "union", 0.0))
    mid = FieldFn(lambda P: head.eval(P))
    cy = float(L["skull_c"][1])
    # the rolled rim, laid on the outside of the cap just above its edge
    rim = []
    for i in range(49):
        a = 2.0 * math.pi * i / 48.0
        aa = abs(math.atan2(math.sin(a), math.cos(a)))
        z = float(rim_z(aa)) + 0.006 * s
        rim.append(_surface_point(mid, gap + t, a, z, r_max=0.2, centre=(0.0, cy)))
    sc.union(sdf.tube_path(rim, 0.0042 * s, closed=False, density=3), k=0.002 * s)
    for i in range(16):
        a = 2.0 * math.pi * (i + 0.5) / 16.0
        aa = abs(math.atan2(math.sin(a), math.cos(a)))
        q = _surface_point(mid, gap + t + 0.003 * s, a, float(rim_z(aa)) + 0.014 * s, r_max=0.2, centre=(0.0, cy))
        sc.union(sdf.sphere(q, 0.0028 * s), k=0.0012 * s)
    # the comb: over the top of the cap from brow to nape
    comb_pts = []
    for i in range(25):
        th = math.radians(-70.0 + 150.0 * i / 24.0)          # from the brow over to the nape
        d = np.array([0.0, math.sin(th), math.cos(th)])
        o = np.array([0.0, cy, float(L["skull_c"][2])])
        lo_r, hi_r = 0.0, 0.25
        for _ in range(40):
            m = 0.5 * (lo_r + hi_r)
            if float(head.eval((o + d * m)[None])[0]) < gap + t:
                lo_r = m
            else:
                hi_r = m
        q = o + d * hi_r
        if q[2] > float(rim_z(abs(math.atan2(q[0], -q[1])))) + 0.012 * s:
            comb_pts.append(q)
    if len(comb_pts) > 2:
        comb_pts = np.array(comb_pts)
        u = np.linspace(0.0, 1.0, len(comb_pts))
        sc.union(sdf.tube_path(comb_pts, 0.0032 * s + 0.0026 * s * np.sin(math.pi * u), density=3), k=0.004 * s)
    # the nasal: from the rim down the bridge of the nose, a hand's breadth off it
    nasal = []
    for i in range(7):
        z = front_z + 0.004 * s - (front_z - (float(L["nose_tip"][2]) + 0.014 * s)) * i / 6.0
        nasal.append(_surface_point(mid, gap * 0.55 + t, 0.0, z, r_max=0.2, centre=(0.0, cy)))
    sc.union(sdf.tube_path(nasal, [0.0068 * s] * 5 + [0.0074 * s, 0.0060 * s], density=3), k=0.004 * s)
    return Garment("helm", sc, spacing=0.0022, smooth=3, target_tris=2200, material="iron", bone="Head")


# --------------------------------------------------------------------------------------
# hair and beards
# --------------------------------------------------------------------------------------

def _head_field(skel: Skeleton, hs: Optional[bodylib.HeadStyle] = None) -> sdf.SampledField:
    return head_field(skel, hs)


DOWN = np.array([0.0, 0.0, -1.0])


def _unit_rows(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def _onto(field, P: np.ndarray, off, iters: int = 3) -> np.ndarray:
    """Move points onto the level set field == off (off a scalar or one per point)."""
    P = np.array(P, float)
    for _ in range(iters):
        d = field.eval(P) - off
        P = P - field.gradient(P) * d[:, None]
    return P


@dataclass
class Groom:
    """How a style lies on the head.

    A style is a scalp shell -- `base` thick where the hair is full, thinning to a millimetre at
    a hairline that follows the skull -- and `seeds` locks combed over it along `flow`, each
    `length` long and `radius` thick at the root, standing `lift` off at the tip. Below
    `release` (a fraction of the visible head) a lock stops following the skull and hangs,
    pushed out of the shoulders and back by the body. `extra` adds a braid or a bun, which
    the locks are combed towards."""
    base: float
    flow: str = "radial"
    front: float = 1.0
    sides: float = 1.0
    back: float = 1.0
    seeds: int = 0
    length: Tuple[float, float] = (0.04, 0.06)
    radius: float = 0.006
    lift: float = 0.004
    jitter: float = 0.0
    part_x: float = 0.0
    release: float = -1.0
    spill: float = 0.0          # how far past the hairline a lock may fall (a fringe)
    blend: float = 0.0045       # how far neighbouring locks melt into each other
    extra: str = ""
    target_tris: int = 3200


def _crown(L: dict) -> np.ndarray:
    s = L["s"]
    return np.array([0.0, L["skull_c"][1] + 0.030 * s, L["chin_z"] + 0.965 * L["V"]])


def _sink(g: Groom, L: dict) -> Optional[np.ndarray]:
    s, V, z0, cy = L["s"], L["V"], L["chin_z"], L["skull_c"][1]
    if g.extra == "bun":
        return np.array([0.0, cy + 0.114 * s, z0 + 0.720 * V])
    if g.extra == "braid":
        return np.array([0.0, cy + 0.078 * s, z0 + 0.330 * V])
    return None


def flow_field(g: Groom, L: dict) -> Callable[[np.ndarray], np.ndarray]:
    """The direction the hair is combed at any point (not yet projected onto the scalp)."""
    s = L["s"]
    crown = _crown(L)
    sink = _sink(g, L)

    def radial(P):
        d = P - crown
        d[:, 2] -= 0.015 * s
        return _unit_rows(d)

    if g.flow == "radial":
        return radial
    if g.flow in ("side_part", "centre_part"):
        px = g.part_x * s
        back = 0.35 if g.flow == "side_part" else 0.10

        def parted(P):
            side = np.where(P[:, 0] >= px, 1.0, -1.0)
            v = _unit_rows(np.stack([side, np.full(len(P), back), np.full(len(P), -0.30)], axis=1))
            # behind the crown the hair falls away from the whorl instead
            wb = np.clip((P[:, 1] - crown[1] + 0.005 * s) / (0.045 * s), 0.0, 1.0)[:, None]
            return _unit_rows(v * (1.0 - wb) + radial(P) * wb)
        return parted
    if g.flow == "back":
        def combed_back(P):
            v = np.tile(np.array([0.0, 1.0, -0.22]), (len(P), 1))
            wb = np.clip((P[:, 1] - crown[1]) / (0.050 * s), 0.0, 1.0)[:, None]
            return _unit_rows(v * (1.0 - wb) + np.array([0.0, 0.30, -1.0]) * wb)
        return combed_back
    if g.flow == "sink" and sink is not None:
        def to_sink(P):
            return _unit_rows(sink - P)
        return to_sink
    return radial


def seed_scalp(head, L: dict, cov_fn, n: int, min_cov: float, rng) -> np.ndarray:
    """About `n` points spread evenly over the scalp, at least `min_cov` inside the hairline."""
    if n <= 0:
        return np.zeros((0, 3))
    m = n * 5
    k = np.arange(m) + 0.5
    phi = np.arccos(1.0 - 2.0 * k / m)
    th = math.pi * (1.0 + 5 ** 0.5) * k
    dirs = np.stack([np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)], axis=1)
    P = L["skull_c"] + dirs * (L["skull_r"] * 1.06)
    P = _onto(head, P, 0.0, iters=8)
    P = P[cov_fn(P) > min_cov]
    if len(P) > n:
        P = P[np.sort(rng.choice(len(P), n, replace=False))]
    return P + rng.normal(0.0, 0.002 * L["s"], P.shape)


def comb(head, start: np.ndarray, flow, length: float, off_fn, release_z: float, s: float,
         body=None, twist: Optional[np.ndarray] = None, stop_fn=None, step: float = 0.004,
         clear: Optional[float] = None) -> np.ndarray:
    """One lock's centreline, walked from `start` along the flow.

    Above `release_z` the lock hugs the skull at its own offset, so it lies on the head the way
    combed hair does. Below it, it hangs: gravity with a little of the flow, and never inside
    the head or the body -- long hair falls onto the shoulders rather than through them."""
    n_steps = max(2, int(length / step))
    p = np.array(start, float)
    pts = [p.copy()]
    hanging = p[2] < release_z
    for i in range(n_steps):
        u = (i + 1) / n_steps
        f = flow(p[None])[0]
        if twist is not None:
            f = twist @ f
        if not hanging:
            nrm = head.gradient(p[None])[0]
            t = f - nrm * float(np.dot(f, nrm))
            if np.linalg.norm(t) < 1e-6:
                t = DOWN - nrm * float(np.dot(DOWN, nrm))
            q = p + sdf._unit(t) * step
            q = _onto(head, q[None], off_fn(u), iters=2)[0]
            if q[2] < release_z:
                hanging = True
        else:
            q = p + sdf._unit(0.22 * f + DOWN) * step
            o = off_fn(u)
            dh = float(head.eval(q[None])[0])
            if dh < o:
                q = q + head.gradient(q[None])[0] * (o - dh)
            if body is not None:
                c = clear if clear is not None else 0.008 * s + 0.5 * o
                db = float(body.eval(q[None])[0])
                if db < c:
                    q = q + body.gradient(q[None])[0] * (c - db)
        # a projection off a degenerate gradient can throw a point anywhere, and one wild
        # point is a scene bound the size of a house: a lock that jumps stops where it was
        if not np.all(np.isfinite(q)) or np.linalg.norm(q - p) > 4.0 * step:
            break
        if stop_fn is not None and stop_fn(q, u):
            break
        pts.append(q)
        p = q
    return np.array(pts)


def scalp_shell(head, cov_fn, base: float, s: float, t_min: float = 0.0012, depth: float = 0.004) -> Prim:
    """The hair's first layer: `base` thick over the scalp, thinning to `t_min` at the hairline
    over the last 14 mm, cut there, and diving under the skin below it -- so the hairline is a
    line hair grows out of, not the rim of a cap. Everything under the skin is trimmed off
    after meshing."""
    feather = 0.014 * s

    def fn(P):
        d = head.eval(P)
        c = cov_fn(P)
        r = np.clip(c / feather, 0.0, 1.0)
        t = t_min + (base - t_min) * (r * r * (3.0 - 2.0 * r))
        shell = np.maximum(d - t, -(d + depth))
        return np.maximum(shell, -c)
    lo, hi = head.bounds(0.01)
    return Prim(fn, lo, hi, "union", 0.0)


# How far hanging hair and a long beard stay off the body: over the clothes, not the skin.
# At 1 cm the long beard fell inside every shirt (1.1 cm off the body) and was seen only as a
# tuft on the chest below the collar; 3 cm clears a padded jack.
HANG_CLEAR = 0.030


def _lock_prim(pts: np.ndarray, r0: float, s: float) -> Prim:
    u = np.linspace(0.0, 1.0, len(pts))
    radii = r0 * (1.0 - 0.62 * u ** 1.5) + 0.0010 * s
    return sdf.tube_path(pts, radii, density=2, max_spheres=160)


def _braid_prims(start: np.ndarray, body, head, L: dict, s: float, length: float = 0.27) -> Tuple[List[Prim], List[np.ndarray]]:
    """A three-strand braid hanging from the nape down the back, and its tie and tuft."""
    centre = comb(head, start, lambda P: np.tile(np.array([0.0, 0.25, -1.0]), (len(P), 1)),
                  length * s, lambda u: 0.012 * s, release_z=1e9, s=s, body=body, step=0.005,
                  clear=HANG_CLEAR * s)
    if len(centre) < 4:
        return [], []
    seg = np.diff(centre, axis=0)
    tang = _unit_rows(np.concatenate([seg, seg[-1:]], axis=0))
    side = _unit_rows(np.cross(tang, np.array([0.0, -1.0, 0.0])))
    back = _unit_rows(np.cross(side, tang))
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(seg, axis=1))])
    prims, lines = [], []
    amp = 0.0110 * s
    period = 0.056 * s
    taper = 1.0 - 0.45 * (arc / max(arc[-1], 1e-6))
    for k in range(3):
        ph = 2.0 * math.pi * k / 3.0
        w = 2.0 * math.pi * arc / period + ph
        off = side * (amp * taper * np.sin(w))[:, None] + back * (0.45 * amp * taper * np.sin(2.0 * w))[:, None]
        pts = centre + off
        prims.append(sdf.tube_path(pts, 0.0086 * s * taper, density=2, max_spheres=200, k=0.002 * s))
        lines.append(pts)
    end = centre[-1]
    prims.append(sdf.torus(end + tang[-1] * 0.002 * s, 0.0080 * s, 0.0034 * s, axis=tang[-1], k=0.002 * s))
    tuft = [end, end + tang[-1] * 0.024 * s + back[-1] * 0.004 * s, end + tang[-1] * 0.046 * s]
    prims.append(sdf.tube_path(tuft, [0.0075 * s, 0.0085 * s, 0.0024 * s], density=2, k=0.003 * s))
    lines.append(np.array(tuft))
    return prims, lines


def _bun_prims(at: np.ndarray, s: float) -> Tuple[List[Prim], List[np.ndarray]]:
    """A bun: a coil of hair wound round itself, with the turns showing.

    The coil climbs the dome of the bun as it winds in. Wound the other way -- the outer turn
    standing furthest from the head -- it was a dish, and from behind it read as a button."""
    R = np.array([0.032, 0.027, 0.030]) * s
    prims = [sdf.ellipsoid(at, R, k=0.006 * s)]
    lines = []
    turns = 2.4
    pts = []
    for i in range(60):
        u = i / 59.0
        a = 2.0 * math.pi * turns * u
        r = (0.029 - 0.017 * u) * s
        y = 0.80 * R[1] * math.sqrt(max(0.0, 1.0 - (r / R[0]) ** 2))
        pts.append(at + np.array([r * math.cos(a), y, r * math.sin(a) * 0.95]))
    pts = np.array(pts)
    prims.append(sdf.tube_path(pts, 0.0090 * s, density=2, max_spheres=220, k=0.004 * s))
    lines.append(pts)
    return prims, lines


def _hair_weights(L: dict, hang_below: float) -> Callable[[np.ndarray], np.ndarray]:
    """Head above the nape; below it the hanging hair goes over to the neck and the chest, so a
    braid or a length of loose hair lies on the back instead of swinging through it."""
    bones = list(rig.DEFORM_NAMES)
    hi = bones.index("Head")
    ni = bones.index("Neck")
    ci = bones.index("Chest")
    s = L["s"]

    def fn(V):
        W = np.zeros((len(V), len(bones)))
        z = V[:, 2]
        wh = np.clip((z - (hang_below - 0.070 * s)) / (0.070 * s), 0.0, 1.0)
        wh = wh * wh * (3.0 - 2.0 * wh)
        W[:, hi] = wh
        W[:, ni] = (1.0 - wh) * 0.30
        W[:, ci] = (1.0 - wh) * 0.70
        return W
    return fn


def hair(skel: Skeleton, name: str, g: Groom, body=None, hs: Optional[bodylib.HeadStyle] = None,
         seed: int = 0) -> Garment:
    """A hair style: the scalp shell with its hairline, and locks combed over it."""
    s = _s(skel)
    head = _head_field(skel, hs)
    L = bodylib.head_landmarks(skel, hs)
    rng = np.random.default_rng(seed + 811)

    def cov(P):
        return bodylib.scalp_field(P, skel, hs, g.front, g.sides, g.back)
    sc = Scene()
    sc.union(scalp_shell(head, cov, g.base * s, s))
    flow = flow_field(g, L)
    sink = _sink(g, L)
    release_z = L["chin_z"] + L["V"] * g.release if g.release > 0 else -1e9
    locks: List[np.ndarray] = []
    starts = seed_scalp(head, L, cov, g.seeds, 0.006 * s, rng)
    for p0 in starts:
        length = rng.uniform(*g.length) * s
        lift = g.lift * s * rng.uniform(0.6, 1.3)
        r0 = g.radius * s * rng.uniform(0.85, 1.15)
        off0 = g.base * s * 0.45

        def off_fn(u, off0=off0, lift=lift):
            return off0 + lift * u ** 1.6
        twist = None
        if g.jitter > 0:
            nrm = head.gradient(p0[None])[0]
            twist = rig.rot_axis(nrm, math.radians(rng.uniform(-g.jitter, g.jitter)))

        def stop(q, u, sink=sink):
            if sink is not None and np.linalg.norm(q - sink) < 0.018 * s:
                return True
            if q[2] < release_z:
                return False
            return float(cov(q[None])[0]) < -g.spill * s
        pts = comb(head, _onto(head, p0[None], off0)[0], flow, length, off_fn, release_z, s,
                   body=body, twist=twist, stop_fn=stop, clear=HANG_CLEAR * s)
        if len(pts) < 3:
            continue
        locks.append(pts)
        sc.union(_lock_prim(pts, r0, s), k=g.blend * s)
    hang = L["nape_z"]
    if g.extra == "braid" and sink is not None:
        prims, lines = _braid_prims(sink, body, head, L, s)
        for pr in prims:
            sc.union(pr, k=0.004 * s)
        locks += lines
    if g.extra == "bun" and sink is not None:
        prims, lines = _bun_prims(sink, s)
        for pr in prims:
            sc.union(pr, k=0.005 * s)
        locks += lines
    hangs = g.release > 0 or g.extra == "braid"
    gm = Garment(name, sc, spacing=0.0032, smooth=4, target_tris=g.target_tris, material="hair",
                 bone=None if hangs else "Head", trim=head)
    if hangs:
        gm.weight_fn = _hair_weights(L, hang)
    gm.flow_fn = flow
    gm.locks = locks
    return gm


@dataclass
class BeardStyle:
    base: float
    region: str = "full"        # full | moustache | chin
    seeds: int = 0
    length: Tuple[float, float] = (0.02, 0.03)
    radius: float = 0.004
    hang: float = 0.0           # how far below the chin the locks fall (metres at 1.78 m)
    target_tris: int = 1400


def beard(skel: Skeleton, name: str, st: BeardStyle, hs: Optional[bodylib.HeadStyle] = None,
          seed: int = 0, body=None) -> Garment:
    """A beard grown on the beard line: a shell over the jaw, cheeks and lip, and locks combed
    down it -- off the chin and onto the chest when the style is long."""
    s = _s(skel)
    head = _head_field(skel, hs)
    L = bodylib.head_landmarks(skel, hs)
    rng = np.random.default_rng(seed + 907)
    if st.region == "moustache":
        def cov(P):
            return bodylib.moustache_field(P, skel, hs)
    else:
        chin_only = st.region == "chin"

        def cov(P):
            return bodylib.beard_field(P, None, skel, hs, moustache=True, chin_only=chin_only)
    sc = Scene()
    sc.union(scalp_shell(head, cov, st.base * s, s, t_min=0.0008 * s, depth=0.003 * s))
    chin = np.array([0.0, L["face_y"] + 0.010 * s, L["chin_z"] + 0.02 * s])

    if st.region == "moustache":
        mid = np.array([0.0, L["face_y"], L["mouth_z"] + 0.02 * s])

        def flow(P):
            v = P - mid
            v[:, 2] = -0.9 * np.abs(v[:, 0]) / 0.03 - 0.4
            return _unit_rows(v)
    else:
        def flow(P):
            # down the jaw towards the chin, and straight down off it
            v = np.stack([-0.35 * P[:, 0] / 0.05, np.full(len(P), -0.25), np.full(len(P), -1.0)], axis=1)
            return _unit_rows(v)
    locks: List[np.ndarray] = []
    release_z = L["chin_z"] + 0.004 * s if st.hang > 0 else -1e9
    starts = np.zeros((0, 3))
    if st.seeds > 0:
        # seeds over the beard itself, which the skull-sphere seeding does not reach well
        cand = _face_points(head, L, rng, st.seeds * 12)
        cand = cand[cov(cand) > 0.003 * s]
        if len(cand) > st.seeds:
            cand = cand[rng.choice(len(cand), st.seeds, replace=False)]
        starts = cand
    for p0 in starts:
        length = rng.uniform(*st.length) * s + (st.hang * s if st.hang > 0 else 0.0)
        r0 = st.radius * s * rng.uniform(0.8, 1.2)
        off0 = st.base * s * 0.45

        def off_fn(u, off0=off0):
            return off0 + 0.002 * s * u

        def stop(q, u):
            if q[2] < release_z:
                return False
            return float(cov(q[None])[0]) < -0.004 * s
        pts = comb(head, _onto(head, p0[None], off0)[0], flow, length, off_fn, release_z, s,
                   body=body, stop_fn=stop, step=0.003, clear=HANG_CLEAR * s)
        if len(pts) < 3:
            continue
        locks.append(pts)
        sc.union(_lock_prim(pts, r0, s), k=0.0035 * s)
    gm = Garment(name, sc, spacing=0.0028, smooth=4, target_tris=st.target_tris, material="hair",
                 bone="Head", trim=head)
    gm.flow_fn = flow
    gm.locks = locks
    return gm


def _face_points(head, L: dict, rng, n: int) -> np.ndarray:
    """Random points on the lower face and jaw, for seeding a beard."""
    s = L["s"]
    c = np.array([0.0, L["face_y"] + 0.045 * s, L["chin_z"] + 0.30 * L["V"]])
    d = _unit_rows(rng.normal(0.0, 1.0, (n, 3)) * np.array([1.0, 0.6, 1.0]) + np.array([0.0, -0.55, -0.35]))
    P = c + d * 0.08 * s
    return _onto(head, P, 0.0, iters=8)


# --------------------------------------------------------------------------------------
# morality attachments (DESIGN.md §5.11)
# --------------------------------------------------------------------------------------

def horns(skel: Skeleton, *, big: bool = False) -> Garment:
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    c, r = L["skull_c"], L["skull_r"]
    k = 1.7 if big else 1.0
    sc = Scene()
    for sx in (1, -1):
        base = np.array([sx * r[0] * 0.62, c[1] - 0.010 * s, c[2] + r[2] * 0.66])
        pts = [base,
               base + np.array([sx * 0.012 * s, -0.004 * s, 0.030 * s * k]),
               base + np.array([sx * 0.030 * s, 0.006 * s, 0.055 * s * k]),
               base + np.array([sx * 0.044 * s, 0.026 * s, 0.070 * s * k])]
        radii = [0.016 * s * k, 0.013 * s * k, 0.009 * s * k, 0.004 * s * k]
        sc.union(sdf.tube_path(pts, radii), k=0.006 * s)
    return Garment("horns_big" if big else "horns_small", sc, spacing=0.0028,
                   target_tris=700, material="horn", bone="Head")


def halo(skel: Skeleton) -> Garment:
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    sc = Scene()
    z = float(L["top"][2]) + 0.075 * s
    sc.union(sdf.torus([0.0, L["skull_c"][1], z], 0.105 * s, 0.0075 * s, axis=UP))
    return Garment("halo", sc, spacing=0.0030, target_tris=600, material="glow", bone="Head")


# --------------------------------------------------------------------------------------
# the catalogue
# --------------------------------------------------------------------------------------

def stable_seed(name: str) -> int:
    """A seed from a name that is the same in every process. `hash()` on a str is salted per
    interpreter, so every part seeded with it painted a different texture on every build."""
    return zlib.crc32(name.encode("utf-8")) % 99991


# The styles the Naming offers, by the name it offers them under ("Short", "Cropped", "Loose",
# "Braided", "Tied back", "Under a hood", "Wild"). Every one covers the scalp to the hairline;
# they differ in how the hair is combed and how much of it there is.
HAIR_STYLES: Dict[str, Groom] = {
    # combed over from a side parting, short at the sides and back
    "short": Groom(base=0.0068, flow="side_part", part_x=0.030, seeds=80, length=(0.035, 0.065),
                   radius=0.0060, lift=0.0035, jitter=8.0, target_tris=3400),
    # a close crop: the shell and the painted grain, with no lock standing proud of it
    "cropped": Groom(base=0.0040, flow="radial", seeds=0, front=1.02, target_tris=2000),
    # loose to the shoulders from a centre parting
    "long": Groom(base=0.0066, flow="centre_part", seeds=74, length=(0.20, 0.34), radius=0.0092,
                  lift=0.002, jitter=5.0, release=0.46, sides=1.05, blend=0.0080, target_tris=4600),
    # combed back tight to the nape into one braid down the back
    "braid": Groom(base=0.0058, flow="sink", seeds=70, length=(0.08, 0.18), radius=0.0050,
                   lift=0.0, extra="braid", target_tris=4200),
    # combed back and up into a coiled bun
    "bun": Groom(base=0.0058, flow="sink", seeds=70, length=(0.08, 0.16), radius=0.0050,
                 lift=0.0, extra="bun", target_tris=3800),
    # short and flat, combed back, so a hood or a helm sits over it
    "hood_friendly": Groom(base=0.0050, flow="back", seeds=55, length=(0.025, 0.045), radius=0.0040,
                           lift=0.0, target_tris=2800),
    # thick and every which way, a fringe falling over the brow
    "tousled": Groom(base=0.0080, flow="radial", seeds=90, length=(0.040, 0.075), radius=0.0068,
                     lift=0.010, jitter=30.0, spill=0.013, blend=0.0058, target_tris=4400),
}
BEARD_STYLES: Dict[str, BeardStyle] = {
    "stubble": BeardStyle(base=0.0016, target_tris=1000),
    "short_beard": BeardStyle(base=0.0072, seeds=45, length=(0.018, 0.032), radius=0.0038, target_tris=1900),
    "long_beard": BeardStyle(base=0.0085, seeds=42, length=(0.030, 0.050), radius=0.0055, hang=0.10,
                             target_tris=2800),
    "moustache": BeardStyle(base=0.0034, region="moustache", seeds=14, length=(0.022, 0.034),
                            radius=0.0030, target_tris=900),
}


def build_hair(skel: Skeleton, style: str, body=None, hs: Optional[bodylib.HeadStyle] = None) -> Garment:
    return hair(skel, style, HAIR_STYLES[style], body=body, hs=hs, seed=stable_seed(style))


def build_beard(skel: Skeleton, style: str, hs: Optional[bodylib.HeadStyle] = None, body=None) -> Garment:
    return beard(skel, style, BEARD_STYLES[style], hs=hs, seed=stable_seed(style), body=body)


# --------------------------------------------------------------------------------------
# culture silhouettes
#
# Five peoples have to be tellable apart at the distance the player actually sees them,
# which is far too far for a colour to help.  What carries that far is the OUTLINE: where
# the hem falls, whether the shoulders are square or sloped, whether the thing is symmetric,
# and whether the head is covered.  Each of these pieces exists to give one culture a shape
# you could name from across a field.
# --------------------------------------------------------------------------------------

def coat(skel: Skeleton, body, *, hem: float = 0.215) -> Garment:
    """Lakefolk: a long straight coat with a standing collar.  It falls to the shin without
    narrowing, which is the opposite of everyone else's belted taper."""
    s = _s(skel)
    sc = Scene()
    z_hem = hem * skel.props.height
    hip = float(skel.J["UpperLeg.L"][2])
    neck = float(skel.J["Neck"][2])
    reg = torso_region(skel, top=0.92, hem=0.52, sleeves=0.96, collar=0.030)
    sc.union(offset_shell(body, reg, 0.011 * s, gap=0.005 * s,
                          # no waist at all: the whole point of this coat is that it is a
                          # column, where every other culture's garment is held in
                          relief=garment_edges(skel, collar_z=neck + 0.012 * s, sleeve_end=0.98,
                                               waist=-0.004),
                          bounds=zbox(skel, 0.50 * skel.props.height, 0.96 * skel.props.height, xy=0.64)))
    # the skirt of the coat: straight sides, no flare, so it reads as a column
    sc.union(sdf.loft([
        (np.array([0.0, 0.006 * s, hip + 0.16 * s]), 0.150 * s, 0.114 * s),
        (np.array([0.0, 0.004 * s, hip - 0.04 * s]), 0.162 * s, 0.122 * s),
        (np.array([0.0, 0.002 * s, z_hem + 0.10 * s]), 0.166 * s, 0.126 * s),
        (np.array([0.0, 0.0, z_hem]), 0.164 * s, 0.124 * s),
    ], LEFT, axis=UP), k=0.012 * s)
    sc.union(sdf.tube_path(_ring(0.166 * s, 0.126 * s, z_hem + 0.014 * s), 0.0064 * s), k=0.006 * s)
    # standing collar: a band that rises past the jaw
    sc.union(sdf.tube_path(_ring(0.074 * s, 0.066 * s, neck + 0.056 * s), 0.014 * s), k=0.010 * s)
    # the front split, so the coat has a centre line down the middle of the silhouette
    sc.subtract(sdf.box([0.0, -0.140 * s, (hip + z_hem) * 0.5],
                        [0.007 * s, 0.045 * s, (hip - z_hem) * 0.62]), k=0.005 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    return Garment("coat", sc, spacing=0.0075, target_tris=4800, material="cloth")


class FieldFn:
    """Anything with `eval(P)`, from a plain function: a trim field, an offset of a field."""

    def __init__(self, fn: Callable[[np.ndarray], np.ndarray]):
        self.fn = fn

    def eval(self, P: np.ndarray) -> np.ndarray:
        return self.fn(P)


def drape_field(body, skel: Skeleton, flare: float = 0.10, arm_cut_x: float = 0.25,
                arm_far: float = 0.05) -> sdf.SampledField:
    """The body as cloth falls from it.

    Every horizontal section of the result is the union of the body's sections above it,
    pushed out by `flare` metres for every metre of fall -- which is the space a cloth takes
    when it is laid over the shoulders and let go. The arms below the top of the deltoid are
    left out, or the cloth would hang from an A-posed arm like a bat's wing: a cape rests on the
    point of the shoulder and falls past the arm, not from it.

    Left out means read as `arm_far` away. A short cape is let lie over the top of the arm at
    5 cm; a cloak to the knee must not be, because the flare closes any fixed distance in the
    end: at 5 cm the cloak's hem had spread out to the A-posed hands, half a metre each side."""
    s = _s(skel)
    F = np.array(body.F, copy=True)
    o, sp = body.origin, body.spacing
    xs = o[0] + np.arange(F.shape[0]) * sp
    zs = o[2] + np.arange(F.shape[2]) * sp
    zc = float(skel.J["UpperArm.L"][2]) + 0.030 * s
    arm = (np.abs(xs)[:, None] > arm_cut_x * s) & (zs[None, :] < zc)
    F = np.where(arm[:, None, :], np.maximum(F, arm_far), F)
    out = np.empty_like(F)
    run = np.full(F.shape[:2], 1e3)
    for k in range(F.shape[2] - 1, -1, -1):
        run = np.minimum(run - flare * sp, F[:, :, k])
        out[:, :, k] = run
    return sdf.SampledField.from_grid(out, o, sp)


def shoulder_line(body, skel: Skeleton, x: float = 0.14) -> float:
    """The height of the top of the shoulders `x` metres out from the spine, read off the body:
    where a cape or a cloak rests. The body's trapezius stands 6 cm above the Neck joint, and
    the cape cut off at the joint's height left the top of each shoulder bare above its edge."""
    s = _s(skel)
    zs = np.arange(float(skel.J["Chest"][2]), float(skel.J["Head"][2]) + 0.10 * s, 0.002)
    P = np.stack([np.full_like(zs, x * s), np.full_like(zs, 0.02 * s), zs], axis=1)
    inside = zs[body.eval(P) < 0.0]
    return float(inside.max()) if len(inside) else float(skel.J["Neck"][2]) + 0.06 * s


def _around(P: np.ndarray) -> np.ndarray:
    """Radians round the body's vertical axis: 0 straight ahead, pi straight behind."""
    return np.arctan2(np.abs(P[:, 0]), -P[:, 1])


def draped_shell(drape, region: RegionFn, thickness: float, gap: float, bounds,
                 relief: Optional[RegionFn] = None) -> Tuple[Prim, "FieldFn"]:
    """A cloth sheet `thickness` thick lying `gap` off a drape field, restricted to `region`,
    and the trim field that removes its inner face after meshing. The result is one sheet of
    cloth, drawn from both sides, not a solid block with a floor under it -- which is what made
    the old cape a lampshade."""
    mid = gap + 0.5 * thickness
    half = 0.5 * thickness

    def off(P):
        return mid if relief is None else mid + relief(P)

    def fn(P):
        d = drape.eval(P)
        w = np.clip(region(P), 0.0, 1.0)
        return np.abs(d - off(P)) - half + (1.0 - w) * 0.25
    lo, hi = bounds
    trim = FieldFn(lambda P: drape.eval(P) - off(P))
    return Prim(_chunked(fn), np.asarray(lo, float), np.asarray(hi, float), "union", 0.0), trim


def _cape_weights(skel: Skeleton) -> Callable[[np.ndarray], np.ndarray]:
    """A cape moves with the chest and the shoulder girdle, and only a little with the top of
    the arm under it: weighted from the body it would follow the arms and tear at the armpit."""
    bones = list(rig.DEFORM_NAMES)
    s = _s(skel)
    ci, ni = bones.index("Chest"), bones.index("Neck")
    neck_z = float(skel.J["Neck"][2])

    def fn(V):
        W = np.zeros((len(V), len(bones)))
        ax = np.abs(V[:, 0])
        w_sh = 0.45 * np.clip((ax - 0.09 * s) / (0.12 * s), 0.0, 1.0)
        w_ua = 0.18 * np.clip((ax - 0.21 * s) / (0.06 * s), 0.0, 1.0) * np.clip((V[:, 2] - (neck_z - 0.09 * s)) / (0.08 * s), 0.0, 1.0)
        w_nk = np.clip((V[:, 2] - (neck_z + 0.015 * s)) / (0.030 * s), 0.0, 1.0) * np.clip((0.11 * s - ax) / (0.04 * s), 0.0, 1.0)
        left = V[:, 0] >= 0
        for side, mask in (("L", left), ("R", ~left)):
            W[mask, bones.index("Shoulder." + side)] = w_sh[mask]
            W[mask, bones.index("UpperArm." + side)] = w_ua[mask]
        W[:, ni] = w_nk
        W[:, ci] = np.clip(1.0 - w_sh - w_ua - w_nk, 0.0, 1.0)
        return W
    return fn


def shoulder_cape(skel: Skeleton, body) -> Garment:
    """Lakefolk: a short cape that rests on the shoulders and falls to the top of the arm.

    It lies over the drape of the shoulders, so it follows the slope from the neck and breaks
    over the point of each shoulder before it falls; eleven folds deepen towards a hem that
    runs lower behind and over the arms than in front; a standing collar closes at the throat
    with a clasp, and the front is split below it. Squaring the shoulders is still its job,
    which it does by resting on them rather than by standing off them."""
    s = _s(skel)
    sc = Scene()
    neck = float(skel.J["Neck"][2])
    drape = drape_field(body, skel, flare=0.10)
    sh = shoulder_line(body, skel)
    top = sh + 0.045 * s
    clasp_z = sh - 0.012 * s
    n_folds = 11

    def hem(P):
        a = _around(P)
        z = neck - 0.130 * s - 0.070 * s * (1.0 - np.cos(a)) * 0.5 - 0.022 * s * np.sin(a) ** 2
        return z + 0.006 * s * np.sin(n_folds * a + 0.6)

    def region(P):
        r = np.hypot(P[:, 0], P[:, 1] - 0.012 * s)
        above = np.clip((P[:, 2] - hem(P)) / (0.006 * s), 0.0, 1.0)
        below_top = np.clip((top - P[:, 2]) / (0.006 * s), 0.0, 1.0)
        neck_hole = np.clip((r - 0.080 * s) / (0.006 * s), 0.0, 1.0)
        # the front split, from the clasp down
        split = np.clip((np.abs(P[:, 0]) - 0.010 * s) / (0.004 * s), 0.0, 1.0)
        split = np.where((P[:, 1] < -0.04 * s) & (P[:, 2] < clasp_z - 0.020 * s), split, 1.0)
        return above * below_top * neck_hole * split

    def folds(P):
        a = _around(P)
        depth = np.clip((neck - 0.010 * s - P[:, 2]) / (0.13 * s), 0.0, 1.0)
        return 0.013 * s * depth * (0.5 + 0.5 * np.sin(n_folds * a + 0.6))
    shell, trim = draped_shell(drape, region, 0.010 * s, 0.006 * s,
                               zbox(skel, neck - 0.26 * s, top + 0.02 * s, xy=0.42, ymin=-0.30, ymax=0.30),
                               relief=folds)
    sc.union(shell)
    # the standing collar round the neck, over the cut edge of the cloth, and the clasp at the
    # throat below it, laid on the front of the cloth
    ring = np.array(_ring(0.084 * s, 0.080 * s, sh + 0.030 * s)) + np.array([0.0, 0.010 * s, 0.0])
    sc.union(sdf.tube_path(ring, 0.011 * s, closed=False), k=0.008 * s)
    front = _surface_point(drape, 0.011 * s, 0.0, clasp_z)
    sc.union(sdf.ellipsoid(front + np.array([0.0, -0.004 * s, 0.0]), [0.012 * s, 0.006 * s, 0.012 * s]), k=0.003 * s)
    g = Garment("shoulder_cape", sc, spacing=0.0045, smooth=4, target_tris=2600, material="cloth",
                trim=trim, trim_depth=0.0)
    g.weight_fn = _cape_weights(skel)
    g.double_sided = True
    return g


def wrap_torso(skel: Skeleton, body) -> Garment:
    """Reedfolk: cloth wound over one shoulder and under the other arm, with a sash across
    the chest.  Nobody else in the world is asymmetric, so this reads instantly."""
    s = _s(skel)
    sc = Scene()
    neck = float(skel.J["Neck"][2])
    waist = float(skel.J["Spine"][2])
    hip = float(skel.J["UpperLeg.L"][2])

    def diagonal(P):
        # covered below a plane running from the left shoulder down to the right hip
        t = (P[:, 2] - (waist - 0.02 * s)) / (0.30 * s) + P[:, 0] / (0.26 * s)
        return 1.0 - sdf_smoothstep(0.55, 1.15, t)
    reg = region_and(band_z(hip - 0.02 * s, neck + 0.030 * s, 0.020 * s), diagonal)
    sc.union(offset_shell(body, reg, 0.010 * s, gap=0.004 * s,
                          relief=garment_edges(skel, waist=0.008),
                          bounds=zbox(skel, hip - 0.06 * s, neck + 0.08 * s, xy=0.44)))
    # the sash: a band of cloth over one shoulder, thick enough to carry its own line
    sh = skel.J["UpperArm.L"]
    shz = float(sh[2])
    sc.union(sdf.tube_path([[float(sh[0]) * 0.55, 0.086 * s, shz - 0.02 * s],
                            [float(sh[0]) * 0.92, 0.030 * s, shz + 0.030 * s],
                            [float(sh[0]) * 0.70, -0.090 * s, shz - 0.05 * s],
                            [0.010 * s, -0.116 * s, waist + 0.06 * s],
                            [-0.090 * s, -0.070 * s, waist - 0.05 * s],
                            [-0.112 * s, 0.050 * s, waist - 0.06 * s]],
                           [0.026 * s, 0.030 * s, 0.030 * s, 0.028 * s, 0.026 * s, 0.022 * s]),
             k=0.012 * s)
    return Garment("wrap_torso", sc, spacing=0.0065, target_tris=3200, material="cloth")


def wrap_skirt(skel: Skeleton, body, *, hem: float = 0.18) -> Garment:
    """Reedfolk: a long narrow wrapped skirt to mid-calf, with the overlap showing."""
    s = _s(skel)
    g = skirt(skel, body, hem=hem, flare=0.22, name="wrap_skirt")
    z_hem = hem * skel.props.height
    hip = float(skel.J["UpperLeg.L"][2])
    g.scene.union(sdf.tube_path([[0.130 * s, -0.100 * s, hip + 0.04 * s],
                                 [0.114 * s, -0.118 * s, (hip + z_hem) * 0.5],
                                 [0.098 * s, -0.126 * s, z_hem + 0.03 * s]],
                                [0.011 * s, 0.012 * s, 0.012 * s]), k=0.008 * s)
    g.scene.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g.target_tris = 3600
    return g


def kilt(skel: Skeleton, body) -> Garment:
    """Clans: a short pleated kilt ending above the knee.  Bare knees are unmistakable next
    to five peoples who all cover their legs."""
    s = _s(skel)
    knee = float(skel.J["LowerLeg.L"][2])
    z_hem = knee + 0.060 * s
    hip = float(skel.J["UpperLeg.L"][2])
    waist = float(skel.J["Spine"][2])
    sc = Scene()
    sc.union(sdf.loft([
        (np.array([0.0, 0.0, waist - 0.01 * s]), 0.132 * s, 0.100 * s),
        (np.array([0.0, 0.0, hip + 0.02 * s]), 0.156 * s, 0.118 * s),
        (np.array([0.0, 0.0, z_hem + 0.05 * s]), 0.180 * s, 0.138 * s),
        (np.array([0.0, 0.0, z_hem]), 0.184 * s, 0.141 * s),
    ], LEFT, axis=UP))
    # pleats, deeper at the back than the front, the way a kilt is actually made
    n = 14
    for i in range(n):
        a = 2 * math.pi * i / n
        dvec = np.array([math.cos(a), math.sin(a), 0.0])
        depth = 0.009 * s * (0.55 + 0.45 * math.sin(a))
        sc.subtract(sdf.tube_path([dvec * 0.156 * s + np.array([0, 0, hip + 0.02 * s]),
                                   dvec * 0.186 * s + np.array([0, 0, z_hem])], depth), k=0.013 * s)
    sc.union(sdf.tube_path(_ring(0.185 * s, 0.142 * s, z_hem + 0.012 * s), 0.0062 * s), k=0.006 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment("kilt", sc, spacing=0.0070, target_tris=3200, material="cloth")
    g.weight_adjust = _skirt_weights(skel)
    return g


def plaid(skel: Skeleton, body) -> Garment:
    """Clans: a great blanket over the left shoulder, pinned, falling behind the knee.  It
    gives one high shoulder and a long diagonal -- a shape no one else in the world has."""
    s = _s(skel)
    sc = Scene()
    sh = skel.J["UpperArm.L"]
    shx, shz = float(sh[0]), float(sh[2])
    neck = float(skel.J["Neck"][2])
    knee = float(skel.J["LowerLeg.L"][2])
    chest = float(skel.J["Chest"][2])
    waist = float(skel.J["Spine"][2])
    # the blanket itself, hanging down the back
    sc.union(sdf.loft([
        (np.array([shx * 0.62, 0.030 * s, shz + 0.026 * s]), 0.090 * s, 0.070 * s),
        (np.array([shx * 0.34, 0.058 * s, neck - 0.08 * s]), 0.140 * s, 0.092 * s),
        (np.array([-0.010 * s, 0.080 * s, neck - 0.30 * s]), 0.154 * s, 0.068 * s),
        (np.array([-0.020 * s, 0.088 * s, knee + 0.22 * s]), 0.152 * s, 0.060 * s),
        (np.array([-0.026 * s, 0.092 * s, knee + 0.05 * s]), 0.140 * s, 0.054 * s),
    ], LEFT, axis=UP), k=0.010 * s)
    sc.intersect(sdf.plane([0.0, 0.0, knee + 0.05 * s], [0.0, 0.0, -1.0]))
    # The length that comes OVER the shoulder and across the chest.  Without it the plaid is
    # a panel hanging behind the man and does not exist at all from the front, which is the
    # only angle the player usually has.
    sc.union(sdf.tube_path([[shx * 0.38, 0.072 * s, waist - 0.02 * s],
                            [shx * 0.72, 0.048 * s, chest - 0.02 * s],
                            [shx * 0.92, -0.004 * s, shz + 0.030 * s],
                            [shx * 0.66, -0.088 * s, chest - 0.01 * s],
                            [shx * 0.10, -0.122 * s, waist + 0.02 * s],
                            [-shx * 0.42, -0.086 * s, waist - 0.08 * s]],
                           [0.030 * s, 0.036 * s, 0.038 * s, 0.036 * s, 0.032 * s, 0.026 * s]),
             k=0.014 * s)
    # the pin at the shoulder, which is where the eye goes
    sc.union(sdf.torus([shx * 0.86, -0.052 * s, shz + 0.020 * s], 0.022 * s, 0.0070 * s,
                       axis=np.array([0.0, 1.0, 0.0])), k=0.004 * s)
    return Garment("plaid", sc, spacing=0.0065, target_tris=2600, material="cloth")


def leg_wraps(skel: Skeleton, body) -> Garment:
    """Woodfolk: a trouser with strips wound over it from the ankle to below the knee, so
    the leg reads as banded rather than as one smooth tube.

    It carries the trouser itself because it occupies the `legs` slot: wraps alone would
    leave the thigh bare, which reads as a man who has lost his trousers rather than as a
    forester."""
    s = _s(skel)
    sc = Scene()
    reg = legs_region(skel, top=0.575, length=0.92)
    sc.union(offset_shell(body, reg, 0.010 * s, gap=0.003 * s,
                          bounds=zbox(skel, 0.02, 0.60 * skel.props.height, xy=0.26)))
    for side in ("L", "R"):
        an = skel.J["Foot.%s" % side]
        kn = skel.J["LowerLeg.%s" % side]
        n = 7
        for i in range(n):
            t = (i + 0.5) / n
            c = an * (1 - t) + kn * t + np.array([0.0, 0.0, 0.014 * s])
            r = (0.050 - 0.006 * t) * s
            sc.union(sdf.torus(c, r, 0.0130 * s,
                               axis=np.array([0.10 * (1 if i % 2 else -1), 0.05, 1.0])), k=0.007 * s)
    return Garment("leg_wraps", sc, spacing=0.0060, target_tris=3800, material="cloth")


def ragged_hem(skel: Skeleton, g: Garment, z_hem: float, teeth: int = 9,
               depth: float = 0.05) -> Garment:
    """Woodfolk: a hem torn into leaf-shaped points rather than cut straight."""
    s = _s(skel)
    g.scene.intersect(ragged_floor(z_hem + depth * 0.45 * s, depth * 0.55 * s, teeth, phase=0.7))
    g.name = "ragged_cloak"
    return g


CLOTHING_BUILDERS: Dict[str, Callable[[Skeleton, Scene], Garment]] = {
    "tunic": lambda s, b: tunic(s, b),
    "shirt": shirt,
    "trousers": trousers,
    "skirt": lambda s, b: skirt(s, b),
    "dress": dress,
    "robe": robe,
    "cloak": lambda s, b: cloak(s, b),
    "hooded_cloak": lambda s, b: cloak(s, b, hooded=True),
    "hood": hood,
    "boots": lambda s, b: boots(s, b),
    "shoes": shoes,
    "gloves": gloves,
    "belt": lambda s, b: belt(s, b),
    "apron": apron,
    "gambeson": gambeson,
    "plate_torso": lambda s, b: plate_torso(s, b),
    "brigandine": lambda s, b: plate_torso(s, b, brigandine=True),
    "pauldrons": pauldrons,
    "greaves": greaves,
    "helm": lambda s, b: helm(s, b),
    "coat": lambda s, b: coat(s, b),
    "shoulder_cape": shoulder_cape,
    "wrap_torso": wrap_torso,
    "wrap_skirt": lambda s, b: wrap_skirt(s, b),
    "kilt": kilt,
    "plaid": plaid,
    "leg_wraps": leg_wraps,
    "ragged_cloak": lambda s, b: cloak(s, b, hooded=True, hem=0.38, ragged=13, name="ragged_cloak"),
    # the same with the hood down, which is how the player wears it
    "torn_cloak": lambda s, b: cloak(s, b, hooded=False, hem=0.38, ragged=13, name="torn_cloak"),
}
ATTACHMENT_BUILDERS: Dict[str, Callable[[Skeleton], Garment]] = {
    "horns_small": lambda s: horns(s, big=False),
    "horns_big": lambda s: horns(s, big=True),
    "halo": halo,
}


# --------------------------------------------------------------------------------------
# culture palettes (WORLD_BIBLE.md §3, DESIGN.md §7.0)
# --------------------------------------------------------------------------------------

CULTURE_PALETTES: Dict[str, Dict[str, str]] = {
    # primary / secondary garment colours, the leather and the metal each culture uses
    "vale": {"primary": "#a8763f", "secondary": "#7d8a4a", "accent": "#b23a2e",
             "leather": "#6b4a2c", "metal": "#8a8f94", "trim": "#c9a24a",
             "note": "warm wool; the accent is the family's painted-door colour"},
    "lakefolk": {"primary": "#efe9dc", "secondary": "#5d6470", "accent": "#b08a3e",
                 "leather": "#4a4239", "metal": "#b08a3e", "trim": "#3f7fb5",
                 "note": "lime-white and slate, brass fittings"},
    "reedfolk": {"primary": "#3b3a6e", "secondary": "#2f7f78", "accent": "#e8a93f",
                 "leather": "#54452f", "metal": "#7d7a70", "trim": "#c9b26a",
                 "note": "marsh indigo on everything"},
    "clans": {"primary": "#c8bda6", "secondary": "#6e5a44", "accent": "#8a4a2e",
              "leather": "#59432c", "metal": "#6f7378", "trim": "#e8e4d8",
              "note": "undyed wool, bone tokens, chain"},
    "woodfolk": {"primary": "#4a4030", "secondary": "#5c6b3c", "accent": "#8ab34a",
                 "leather": "#3f3325", "metal": "#5f6259", "trim": "#2b211c",
                 "note": "bark browns and moss"},
    "ash_pilgrims": {"primary": "#8b8a86", "secondary": "#5a5652", "accent": "#d8cfbf",
                     "leather": "#4a4744", "metal": "#77736d", "trim": "#a08a4a",
                     "note": "grey, always grey"},
}
MATERIAL_DEFAULTS: Dict[str, dict] = {
    "cloth": {"roughness": 0.88, "metallic": 0.0, "colour": "primary"},
    "leather": {"roughness": 0.62, "metallic": 0.0, "colour": "leather"},
    "iron": {"roughness": 0.38, "metallic": 1.0, "colour": "metal"},
    # Hair at 0.52 roughness reads as a moulded swim cap under a sky light; real hair
    # scatters far more than it reflects.
    "hair": {"roughness": 0.78, "metallic": 0.0, "colour": "hair"},
    "horn": {"roughness": 0.55, "metallic": 0.0, "colour": "#c9bda6"},
    "glow": {"roughness": 0.30, "metallic": 0.0, "colour": "#ffe7a8"},
}
