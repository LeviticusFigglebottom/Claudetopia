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


def sdf_smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / max(e1 - e0, 1e-9), 0.0, 1.0)
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

    def mesh(self) -> Tuple[np.ndarray, np.ndarray]:
        return sdf.mesh_from_scene(self.scene, self.spacing, smooth_iters=self.smooth, project=1)


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
        # cut only a throat-sized hole, so shoulders and chest stay covered
        near_axis = 1.0 - sdf_smoothstep(neck_r * 0.75, neck_r * 1.35, np.hypot(P[:, 0], P[:, 1] - 0.01 * s))
        above = sdf_smoothstep(neck_cut - 0.025 * s, neck_cut + 0.015 * s, P[:, 2])
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


def trousers(skel: Skeleton, body, *, thickness: float = 0.010, length: float = 0.92) -> Garment:
    sc = Scene()
    s = _s(skel)
    reg = legs_region(skel, top=0.575, length=length)
    sc.union(offset_shell(body, reg, thickness * s, gap=0.003 * s,
                          bounds=zbox(skel, 0.02, 0.60 * skel.props.height, xy=0.26)))
    return Garment("trousers", sc, spacing=0.0070, target_tris=3600, material="cloth")


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
    return Garment(name, sc, spacing=0.0080, target_tris=3400, material="cloth")


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


def cloak(skel: Skeleton, body, *, hooded: bool = False, hem: float = 0.30) -> Garment:
    s = _s(skel)
    sc = Scene()
    chest = float(skel.J["Chest"][2])
    neck = float(skel.J["Neck"][2])
    z_hem = hem * skel.props.height
    shoulder_x = float(skel.J["UpperArm.L"][0])
    # a cape hanging off the shoulders: wide at the back, open at the front
    outer = sdf.loft([
        (np.array([0.0, 0.016 * s, neck + 0.030 * s]), 0.118 * s, 0.104 * s),
        (np.array([0.0, 0.018 * s, neck - 0.020 * s]), (shoulder_x + 0.016) * s, 0.122 * s),
        (np.array([0.0, 0.020 * s, chest - 0.05 * s]), (shoulder_x + 0.040) * s, 0.132 * s),
        (np.array([0.0, 0.024 * s, (chest + z_hem) * 0.5]), (shoulder_x + 0.032) * s, 0.134 * s),
        (np.array([0.0, 0.028 * s, z_hem + 0.03 * s]), (shoulder_x + 0.044) * s, 0.142 * s),
        (np.array([0.0, 0.028 * s, z_hem]), (shoulder_x + 0.045) * s, 0.143 * s),
    ], LEFT, axis=UP)
    sc.union(outer)
    # Open down the front, and WIDE: the old opening was narrower than the body, so the cape
    # closed over the chest and read as a barrel with a slot in it rather than as a cape.
    sc.subtract(sdf.box([0.0, -0.32 * s, (neck + z_hem) * 0.5],
                        [0.150 * s, 0.262 * s, (neck - z_hem) * 0.6],
                        round_r=0.02 * s), k=0.02 * s)
    for i in range(7):
        a = math.pi * (0.25 + 0.5 * i / 6)
        d = np.array([math.cos(a), math.sin(a), 0.0])
        sc.subtract(sdf.tube_path([d * 0.16 * s + np.array([0, 0, chest]),
                                   d * (shoulder_x + 0.072) * s + np.array([0, 0.02 * s, z_hem])],
                                  0.014 * s), k=0.022 * s)
    sc.union(sdf.tube_path(_ring((shoulder_x + 0.045) * s, 0.143 * s, z_hem + 0.010 * s),
                           0.0060 * s), k=0.006 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment("hooded_cloak" if hooded else "cloak", sc, spacing=0.0080, target_tris=3600, material="cloth")
    if hooded:
        g.scene.union(hood_prim(skel, body, up=True), k=0.02 * s)
        g.target_tris = 3000
    return g


def hood_prim(skel: Skeleton, body, up: bool = True) -> Prim:
    """A hood standing off the skull (worn up), open at the face."""
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    c = L["skull_c"]
    r = L["skull_r"]
    parts = []
    outer = sdf.ellipsoid(c + np.array([0.0, 0.020 * s, 0.012 * s]),
                          [r[0] * 1.24, r[1] * 1.26, r[2] * 1.22])
    cone = sdf.loft([
        (np.array([0.0, c[1] + 0.03 * s, c[2] - r[2] * 1.1]), r[0] * 1.30, r[1] * 1.34),
        (np.array([0.0, c[1] + 0.05 * s, float(skel.J["Neck"][2]) - 0.02 * s]), r[0] * 1.55, r[1] * 1.50),
    ], LEFT, axis=UP)
    grp = sdf.group([outer, sdf.Prim(cone.fn, cone.lo, cone.hi, "union", 0.04 * s)], internal_k=0.03 * s)
    sc = Scene()
    sc.union(grp)
    sc.subtract(sdf.ellipsoid(c + np.array([0.0, 0.016 * s, 0.006 * s]),
                              [r[0] * 1.12, r[1] * 1.14, r[2] * 1.10]), k=0.006 * s)
    # the face opening
    sc.subtract(sdf.ellipsoid([0.0, L["face_y"] - 0.02 * s, L["eye_z"] - 0.012 * s],
                              [r[0] * 0.92, 0.090 * s, r[2] * 0.85]), k=0.012 * s)
    prim = sdf.Prim(sc.eval, *sc.bounds(0.02), "union", 0.0)
    return prim


def hood(skel: Skeleton, body) -> Garment:
    sc = Scene()
    sc.union(hood_prim(skel, body, up=True))
    return Garment("hood", sc, spacing=0.0055, target_tris=1400, material="cloth", bone="Head")


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
    g = tunic(skel, body, hem=0.42, sleeves=0.75, thickness=0.026, name="gambeson")
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


def plate_torso(skel: Skeleton, body, *, brigandine: bool = False) -> Garment:
    s = _s(skel)
    sc = Scene()
    chest = float(skel.J["Chest"][2])
    waist = float(skel.J["Spine"][2])
    hip = float(skel.J["UpperLeg.L"][2])
    # The arm used to be excluded from the REGION, by an 85 mm capsule around the whole
    # upper-arm bone.  That carved the shoulder and the outer chest off the breastplate --
    # an armoured man bare from the collarbone out, which reads as unfinished rather than as
    # a style -- and any region boundary on a limb ends in a flat flange anyway, because
    # `offset_shell` cuts perpendicular to nothing.  The plate now covers the shoulder and a
    # rounded armhole is CARVED out of it below, which is how a cuirass is actually shaped.
    reg = band_z(hip + 0.02 * s, float(skel.J["Neck"][2]) - 0.01 * s, 0.018 * s)
    sc.union(offset_shell(body, reg, 0.016 * s, gap=0.014 * s,
                          bounds=zbox(skel, hip - 0.16 * s, float(skel.J["Neck"][2]) + 0.04 * s, xy=0.30)))
    for side, sx in (("L", 1), ("R", -1)):
        sh = skel.J["UpperArm.%s" % side]
        el = skel.J["LowerArm.%s" % side]
        d = (el - sh) / max(float(np.linalg.norm(el - sh)), 1e-6)
        sc.subtract(sdf.capsule(sh + d * 0.052 * s + np.array([sx * 0.030 * s, 0.0, 0.0]),
                                sh + d * 0.46 * float(np.linalg.norm(el - sh)) + np.array([sx * 0.070 * s, 0.0, 0.0]),
                                0.082 * s), k=0.018 * s)
    # a breastplate keel and a raised neck edge
    sc.union(sdf.loft([
        (np.array([0.0, -0.128 * s, chest + 0.085 * s]), 0.070 * s, 0.020 * s),
        (np.array([0.0, -0.140 * s, chest - 0.01 * s]), 0.058 * s, 0.024 * s),
        (np.array([0.0, -0.126 * s, waist + 0.02 * s]), 0.040 * s, 0.020 * s),
    ], LEFT, axis=UP), k=0.026 * s)
    if brigandine:
        rng = np.random.default_rng(7)
        for i in range(34):
            a = rng.uniform(0, 2 * math.pi)
            z = rng.uniform(hip + 0.05 * s, chest + 0.14 * s)
            d = np.array([math.cos(a), math.sin(a) * 0.78, 0.0])
            sc.union(sdf.sphere(d * 0.175 * s + np.array([0, 0, z]), 0.0075 * s), k=0.004 * s)
    else:
        z_top = waist - 0.005 * s
        z_bot = z_top - 0.135 * s
        sc.union(sdf.loft([
            (np.array([0.0, 0.0, z_top]), 0.172 * s, 0.130 * s),
            (np.array([0.0, 0.0, (z_top + z_bot) * 0.5]), 0.186 * s, 0.140 * s),
            (np.array([0.0, 0.0, z_bot]), 0.196 * s, 0.148 * s),
        ], LEFT, axis=UP), k=0.014 * s)
        # two scored lines, which is all a lamellar fauld needs to read as layered
        for i in range(2):
            zr = z_top - (0.045 + 0.045 * i) * s
            sc.subtract(sdf.tube_path(_ring((0.180 + 0.008 * i) * s, (0.136 + 0.006 * i) * s, zr),
                                      0.0055 * s), k=0.006 * s)
        sc.intersect(sdf.plane([0.0, 0.0, z_bot], [0.0, 0.0, -1.0]), k=0.004 * s)
    return Garment("brigandine" if brigandine else "plate_torso", sc, spacing=0.0075,
                   target_tris=4000, material="iron")


def pauldrons(skel: Skeleton, body) -> Garment:
    s = _s(skel)
    sc = Scene()
    for side, sx in (("L", 1), ("R", -1)):
        sh = skel.J[f"UpperArm.{side}"]
        for i in range(3):
            r = (0.095 + 0.012 * i) * s
            c = sh + np.array([sx * (0.004 + 0.012 * i) * s, 0.0, (0.012 - 0.030 * i) * s])
            lam = sdf.ellipsoid(c, [r, r * 1.02, r * 0.86])
            inner = sdf.ellipsoid(c + np.array([-sx * 0.012 * s, 0, 0.004 * s]), [r * 0.88, r * 0.88, r * 0.78])
            sub = Scene()
            sub.union(lam)
            sub.subtract(inner, k=0.004 * s)
            sub.intersect(sdf.plane(c + np.array([0, 0, (-0.022 - 0.002 * i) * s]), [0, 0, -1.0]), k=0.004 * s)
            sc.union(sdf.Prim(sub.eval, *sub.bounds(0.02), "union", 0.0), k=0.006 * s)
    return Garment("pauldrons", sc, spacing=0.0045, target_tris=1600, material="iron")


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
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    c, r = L["skull_c"], L["skull_r"]
    sc = Scene()
    sc.union(sdf.ellipsoid(c + np.array([0.0, 0.004 * s, 0.004 * s]), [r[0] * 1.12, r[1] * 1.10, r[2] * 1.12]))
    sc.subtract(sdf.ellipsoid(c + np.array([0.0, 0.004 * s, 0.002 * s]), [r[0] * 1.03, r[1] * 1.01, r[2] * 1.03]), k=0.003 * s)
    # cut the whole lower half off, then a face opening
    sc.intersect(sdf.plane([0.0, 0.0, L["eye_z"] - 0.012 * s], [0.0, 0.0, -1.0]), k=0.006 * s)
    if open_face:
        sc.subtract(sdf.box([0.0, L["face_y"] - 0.04 * s, L["eye_z"] + 0.030 * s],
                            [r[0] * 0.62, 0.075 * s, 0.030 * s], round_r=0.012 * s), k=0.008 * s)
    # nasal bar and a brow ridge
    sc.union(sdf.tube_path([[0.0, L["face_y"] + 0.004 * s, L["brow_z"] + 0.016 * s],
                            [0.0, L["face_y"] - 0.008 * s, L["eye_z"] - 0.006 * s],
                            [0.0, L["face_y"] - 0.010 * s, L["nose_base_z"]]], 0.009 * s), k=0.006 * s)
    sc.union(sdf.tube_path([[-r[0] * 1.02, c[1] + 0.03 * s, L["eye_z"] + 0.030 * s],
                            [0.0, L["face_y"] + 0.004 * s, L["eye_z"] + 0.036 * s],
                            [r[0] * 1.02, c[1] + 0.03 * s, L["eye_z"] + 0.030 * s]], 0.010 * s), k=0.008 * s)
    return Garment("helm", sc, spacing=0.0042, target_tris=1500, material="iron", bone="Head")


# --------------------------------------------------------------------------------------
# hair and beards
# --------------------------------------------------------------------------------------

def _head_field(skel: Skeleton, hs: Optional[bodylib.HeadStyle] = None) -> sdf.SampledField:
    return head_field(skel, hs)


def hair(skel: Skeleton, name: str, *, front: float = 1.0, sides: float = 1.0, back: float = 1.0,
         thickness: float = 0.016, locks: Sequence[Sequence[Sequence[float]]] = (),
         lock_radius: float = 0.018, hs: Optional[bodylib.HeadStyle] = None) -> Garment:
    """A hair shell over the scalp, plus optional locks (a braid, a bun, a fringe)."""
    s = _s(skel)
    head = _head_field(skel, hs)
    L = bodylib.head_landmarks(skel, hs)

    def region(P):
        return np.clip(bodylib.scalp_field(P, skel, hs or bodylib.HeadStyle(), front, sides, back) * 0.55 + 0.42, 0.0, 1.0)
    sc = Scene()
    lo, hi = head.bounds(0.02)
    sc.union(offset_shell(head, region, thickness * s, gap=0.001 * s, bounds=(lo, hi)))
    for pts in locks:
        sc.union(sdf.tube_path([np.asarray(p, float) * s for p in pts], lock_radius * s), k=0.012 * s)
    return Garment(name, sc, spacing=0.0034, target_tris=2200, material="hair", bone="Head")


def beard(skel: Skeleton, name: str, *, moustache: bool = True, cheeks: float = 1.0, length: float = 1.0,
          thickness: float = 0.013, hs: Optional[bodylib.HeadStyle] = None) -> Garment:
    s = _s(skel)
    head = _head_field(skel, hs)
    hsx = hs or bodylib.HeadStyle()
    L = bodylib.head_landmarks(skel, hsx)

    def region(P):
        eps = 1e-3
        d0 = head.eval(P)
        g = np.stack([(head.eval(P + np.eye(3)[i] * eps) - d0) / eps for i in range(3)], axis=1)
        g = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)
        f = bodylib.beard_field(P, g, skel, hsx, moustache, cheeks, length)
        return np.clip(f * 0.8 + 0.4, 0.0, 1.0)
    sc = Scene()
    lo, hi = head.bounds(0.02)
    sc.union(offset_shell(head, region, thickness * s, gap=0.001 * s, bounds=(lo, hi)))
    if length > 1.2:
        chin = np.array([0.0, L["face_y"] + 0.02 * s, L["chin_z"]])
        sc.union(sdf.tube_path([chin, chin + np.array([0.0, 0.006 * s, -0.05 * s * length]),
                                chin + np.array([0.0, 0.016 * s, -0.10 * s * length])],
                               [0.028 * s, 0.024 * s, 0.014 * s]), k=0.015 * s)
    return Garment(name, sc, spacing=0.0036, target_tris=900, material="hair", bone="Head")


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

HAIR_STYLES: Dict[str, dict] = {
    "short": dict(front=1.0, sides=1.0, back=1.0, thickness=0.010),
    "cropped": dict(front=1.15, sides=1.35, back=1.25, thickness=0.005),
    "long": dict(front=0.9, sides=0.55, back=0.2, thickness=0.015),
    "braid": dict(front=0.95, sides=0.85, back=0.7, thickness=0.011),
    "bun": dict(front=0.95, sides=0.95, back=0.9, thickness=0.010),
    "hood_friendly": dict(front=1.05, sides=1.1, back=1.05, thickness=0.007),
    "tousled": dict(front=0.85, sides=1.0, back=0.95, thickness=0.014),
}
BEARD_STYLES: Dict[str, dict] = {
    "stubble": dict(moustache=True, cheeks=1.0, length=0.55, thickness=0.006),
    "short_beard": dict(moustache=True, cheeks=1.0, length=1.0, thickness=0.013),
    "long_beard": dict(moustache=True, cheeks=1.0, length=1.6, thickness=0.017),
    "moustache": dict(moustache=True, cheeks=0.0, length=0.35, thickness=0.011),
}


def hair_locks(skel: Skeleton, style: str) -> List[List[List[float]]]:
    """Extra strands for the styles that need them, in units of the body scale."""
    s = 1.0
    L = bodylib.head_landmarks(skel)
    c, r = L["skull_c"] / _s(skel), L["skull_r"] / _s(skel)
    nape = [0.0, float(c[1]) + float(r[1]) * 0.72, float(c[2]) - float(r[2]) * 0.55]
    if style == "long":
        out = []
        for sx in (1, -1, 0):
            x = sx * 0.055
            out.append([[x * 0.7, c[1] + r[1] * 0.55, c[2] + r[2] * 0.30],
                        [x, c[1] + r[1] * 0.80, c[2] - r[2] * 0.30],
                        [x, c[1] + r[1] * 0.86, c[2] - r[2] * 1.30],
                        [x * 0.9, c[1] + r[1] * 0.80, c[2] - r[2] * 2.30]])
        return out
    if style == "braid":
        return [[nape,
                 [0.0, nape[1] + 0.012, nape[2] - 0.075],
                 [0.012, nape[1] + 0.020, nape[2] - 0.150],
                 [-0.010, nape[1] + 0.022, nape[2] - 0.225],
                 [0.0, nape[1] + 0.020, nape[2] - 0.285]]]
    if style == "bun":
        b = [0.0, nape[1] + 0.030, float(c[2]) + float(r[2]) * 0.30]
        return [[[b[0] - 0.045, b[1], b[2]], [b[0], b[1] + 0.022, b[2] + 0.020],
                 [b[0] + 0.045, b[1], b[2]], [b[0], b[1] - 0.010, b[2] - 0.020],
                 [b[0] - 0.045, b[1], b[2]]]]
    if style == "tousled":
        rng = np.random.default_rng(3)
        out = []
        for i in range(5):
            a = rng.uniform(-1.0, 1.0)
            out.append([[a * 0.05, c[1] - r[1] * 0.35, c[2] + r[2] * 0.70],
                        [a * 0.055, c[1] - r[1] * 0.70, c[2] + r[2] * 0.62],
                        [a * 0.06, c[1] - r[1] * 0.92, c[2] + r[2] * 0.50]])
        return out
    return []


def build_hair(skel: Skeleton, style: str) -> Garment:
    kw = dict(HAIR_STYLES[style])
    locks = hair_locks(skel, style)
    return hair(skel, style, locks=locks, lock_radius=0.021 if style != "braid" else 0.016, **kw)


def build_beard(skel: Skeleton, style: str) -> Garment:
    return beard(skel, style, **BEARD_STYLES[style])


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


def shoulder_cape(skel: Skeleton, body) -> Garment:
    """Lakefolk: a short cape ending above the elbow.  It squares the shoulders off, and a
    square shoulder is the one cue that still reads at thirty pixels tall."""
    s = _s(skel)
    sc = Scene()
    neck = float(skel.J["Neck"][2])
    chest = float(skel.J["Chest"][2])
    z_bot = chest - 0.10 * s
    sx = float(skel.J["UpperArm.L"][0])
    sc.union(sdf.loft([
        (np.array([0.0, 0.010 * s, neck + 0.014 * s]), 0.086 * s, 0.076 * s),
        (np.array([0.0, 0.008 * s, neck - 0.022 * s]), (sx + 0.055) * s, 0.128 * s),
        (np.array([0.0, 0.004 * s, chest + 0.030 * s]), (sx + 0.086) * s, 0.146 * s),
        (np.array([0.0, 0.0, z_bot + 0.020 * s]), (sx + 0.094) * s, 0.152 * s),
        (np.array([0.0, 0.0, z_bot]), (sx + 0.090) * s, 0.149 * s),
    ], LEFT, axis=UP))
    sc.union(sdf.tube_path(_ring((sx + 0.094) * s, 0.152 * s, z_bot + 0.010 * s), 0.0060 * s), k=0.006 * s)
    # The neck hole has to be a shaft, not a dimple -- and the sweep's top cap has to come
    # off, because a hemisphere of its own radius rises past the chin and the cape ends up
    # wearing the wearer's face.
    sc.subtract(sdf.capsule([0.0, 0.012 * s, neck - 0.030 * s],
                            [0.0, 0.012 * s, neck + 0.40 * s], 0.082 * s), k=0.010 * s)
    sc.intersect(sdf.plane([0.0, 0.0, neck + 0.006 * s], [0.0, 0.0, 1.0]))
    sc.intersect(sdf.plane([0.0, 0.0, z_bot], [0.0, 0.0, -1.0]))
    return Garment("shoulder_cape", sc, spacing=0.0060, target_tris=2000, material="cloth")


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
    return Garment("kilt", sc, spacing=0.0070, target_tris=3200, material="cloth")


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
    "ragged_cloak": lambda s, b: ragged_hem(s, cloak(s, b, hooded=True, hem=0.38),
                                            0.38 * s.props.height, teeth=13, depth=0.055),
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
