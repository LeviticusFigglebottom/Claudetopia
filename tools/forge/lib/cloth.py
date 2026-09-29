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


def womans_snug(skel: Skeleton, k: float = 0.60, floor: float = 0.007):
    """How much closer a woman wears her sleeves and the caps of her shoulders than the body they
    were built on (body.fit_positions' `snug`): the part of each vertex's distance past `floor`
    taken in by `k`, round the arms from the shoulder joint to the wrist. Fitted at the man's
    distances, a tunic's sleeve stood 14-19 mm off her slighter arm and the shoulder seam 19 mm
    off the cap, and under every tunic her shoulders and upper arms read broad (triage 29). The
    order of the layers is kept: a coat still stands off the shirt under it, by less."""
    s = _s(skel)
    segs = []
    for side in ("L", "R"):
        segs.append((skel.J["UpperArm.%s" % side], skel.J["LowerArm.%s" % side]))
        segs.append((skel.J["LowerArm.%s" % side], skel.J["Hand.%s" % side]))
    arms = near_segments(segs, 0.080 * s, 0.030 * s)
    # and over the front of her chest (item 46's review): cloth over a bust lies on it, a few
    # millimetres off, where over a man's flat chest it hangs a centimetre clear; fitted at the man's
    # distance on top of the drape, her tunic stood 3 cm before his and every woman read as two balls
    az = float(skel.J["Chest"][2]) + 0.014 * s

    def chest(V: np.ndarray) -> np.ndarray:
        wz = np.exp(-0.5 * ((V[:, 2] - (az - 0.015 * s)) / (0.055 * s)) ** 2)
        wx = 1.0 - _ss((np.abs(V[:, 0]) - 0.13 * s) / (0.05 * s))
        wy = _ss((-V[:, 1] - 0.04 * s) / (0.03 * s))
        return wz * wx * wy

    def fn(V: np.ndarray, d0: np.ndarray) -> np.ndarray:
        d = d0 - arms(V) * k * np.clip(d0 - floor * s, 0.0, None)
        return d - chest(V) * 0.70 * np.clip(d - 0.004 * s, 0.0, None)
    return fn


BODY_SNUG = {"woman": womans_snug}


def fit_field(skel: Skeleton, style: Optional[bodylib.BodyStyle] = None, spacing: float = 0.005) -> sdf.SampledField:
    """The field a garment built on another body is fitted to on this one (body.fit_positions):
    the body, with the drape cloth hangs over it (body.garment_drape) -- for a man's body, the
    body itself. A true distance out to where a fit fades (`reach` 9 cm, sdf.Scene.grid): the
    garment is measured from both bodies, and read off each primitive's bounds, a padded coat
    under the arm was pulled in 9 cm on a woman whose torso is a little narrower."""
    scene = bodylib.body_scene(skel, style)
    drape = bodylib.garment_drape(skel, style)
    if drape:
        scene.union(sdf.group(drape), k=0.03 * skel.props.height / rig.DEFAULT_HEIGHT)
    return sdf.SampledField(scene, spacing=spacing, margin=0.09, reach=0.09)


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
    # A skirt is a solid loft cut off by a plane at its hem, and a solid is meshed closed: the
    # cut was a flat floor across the bottom of every skirt, kilt, robe, dress, tunic and coat,
    # with the legs standing through it. At rest nobody saw it; in a stride it swung up with the
    # thighs and the legs cut through it -- the "running legs clip the clothes" of playtest 5.
    # With the hem's height here, the faces of that floor are dropped after meshing, and the
    # skirt is open at the bottom as a skirt is.
    open_below: Optional[float] = None
    # Other meshes exported with this one, each with its own material: the arming coat under
    # a cuirass is cloth, the cuirass is iron. Named `<name>_<layer name>`.
    layers: List["Garment"] = field(default_factory=list)
    # Per-vertex skin weights over rig.DEFORM_NAMES, for parts that are neither rigid to one
    # bone nor a copy of the body's weights (hair that hangs past the neck).
    weight_fn: Optional[Callable[[np.ndarray], np.ndarray]] = None
    # Or the body's weights, reworked: (vertex positions, their transferred weights) -> weights.
    # A skirt keeps the body's weights above the hips and below them gives the legs' share to
    # both thighs, blended across the centre line (see `_skirt_weights`).
    weight_adjust: Optional[Callable[[np.ndarray, np.ndarray], np.ndarray]] = None
    # The (z, a, b, yc) loft stations a skirt was cut through once they cover the body
    # (`_covered`), for what is laid on it afterwards: a wrap skirt's overlap.
    stations: list = field(default_factory=list)
    # Colour woven into the cloth: (positions, normals) -> rgb, multiplied into the painted value.
    # A part with a pattern is baked in its own colours and the game must not tint it again, which
    # its meta says with "tint": "none" (the clans' plaid is a tartan, not a primary colour).
    pattern: Optional[Callable[[np.ndarray, np.ndarray], np.ndarray]] = None
    # Modelled round the arms as they hang in the Idle rather than as they stand in the rest
    # pose: bound to the rest pose, it would be carried down again by every bit of its weight on
    # an arm. `rebind_from_idle` puts each vertex where the Idle's skinning brings it back.
    rebind: bool = False
    # Worn on the hands: it closes with them, as the body does, by the grip_L and grip_R morph
    # targets (grip.py), which HumanoidModel.set_grip turns on when a weapon is held.
    grip: bool = False
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
        if self.open_below is not None and len(quads):
            verts, quads = open_hem(verts, np.asarray(quads), self.open_below, 0.6 * self.spacing)
        return verts, quads


def open_hem(verts: np.ndarray, quads: np.ndarray, z: float, tol: float) -> Tuple[np.ndarray, np.ndarray]:
    """Drop the floor a plane cut leaves across the bottom of a solid at height `z`: the faces
    that face down and lie within `tol` of the plane (see Garment.open_below)."""
    q = np.asarray(quads)
    P = verts[q]
    n = np.cross(P[:, 2] - P[:, 0], P[:, 3] - P[:, 1]) if q.shape[1] == 4 else np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    floor = (P[..., 2] < z + tol).all(axis=1) & (n[:, 2] < -0.5)
    q = q[~floor]
    used = np.unique(q)
    remap = -np.ones(len(verts), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return verts[used], remap[q]


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
    # Behind, the collar sits up against the nape whatever the neckline does in front: a scooped
    # neck is scooped at the throat.
    back_cut = float(skel.J["Neck"][2]) + (max(collar, 0.0) + 0.012) * s
    neck_r = 0.085 * s

    def neckline(P):
        # Cut only a throat-sized hole, so shoulders and chest stay covered -- and cut it
        # crisply. Faded over 5 cm, a padded jack's neckline thinned out over a hand's breadth
        # and ended in a torn-paper edge, which is the first thing the Naming's face view saw.
        # Behind the neck the hole is wider (11 cm) and the cut is the
        # height alone. The nape stands 7.5-11 cm from the axis, and a garment's surface 11 mm off
        # it lay in the fade of an 8.5 cm hole for 7 cm of its height: the cut grazed it and left a
        # ragged notch of skin at the nape, stepped like the cells it was meshed in (every shirt,
        # tunic and gown from behind, triage 29). Inside the hole, a level cut is clean.
        rxy = np.hypot(P[:, 0], P[:, 1] - 0.01 * s)
        behind = np.clip((P[:, 1] - 0.01 * s) / np.maximum(rxy, 1e-6), 0.0, 1.0)
        r = neck_r * (1.0 + 0.30 * np.minimum(2.0 * behind, 1.0))
        near_axis = 1.0 - sdf_smoothstep(r * 0.92, r * 1.10, rxy)
        cut = neck_cut + (back_cut - neck_cut) * behind
        above = sdf_smoothstep(cut - 0.010 * s, cut + 0.008 * s, P[:, 2])
        return 1.0 - np.clip(near_axis * above + sdf_smoothstep(neck_cut + 0.06 * s, neck_cut + 0.10 * s, P[:, 2]), 0, 1)
    # The trunk's band does not take in the hands. In the A-pose they hang at chest height,
    # inside it, and every long-sleeved coat was an offset of them: a padded mitten over each hand
    # with the fingertips out of the end where the build box cut it -- the armoured figure's
    # "fists", twice a hand's size. The sleeves are the arms' region, which ends at its reach.
    hand_segs = [(skel.J["Hand.%s" % side], skel.J["HandTip.%s" % side]) for side in ("L", "R")]
    on_hands = near_segments(hand_segs, 0.055 * s, 0.010 * s)
    body_part = region_and(trunk, neckline, lambda P: 1.0 - on_hands(P))
    # The neckline cuts the sleeves' region too: it reaches 10 cm round the shoulder bones, which
    # start at the breastbone, and it put back the cloth the neckline had taken off either side of
    # the nape -- two ragged tabs up the back of the neck.
    return region_and(region_or(body_part, *arms), neckline) if arms else body_part


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
                          # wide enough for the sleeve: the A-posed wrist stands 0.65 m out, and
                          # at 0.55 every long sleeve (the gambeson's, the arming coat's) was cut
                          # off halfway down the forearm by the box it was evaluated in
                          bounds=zbox(skel, hem * skel.props.height - 0.03 * s, 0.92 * skel.props.height,
                                      xy=0.55 if sleeves < 0.6 else 0.74)))
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
    return Garment(name, sc, spacing=0.0075, target_tris=4200, material="cloth", open_below=z_hem)


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
    # From the top of the thigh up they lie closer, under whatever is worn over them: at full
    # thickness they stood 2 mm outside a tunic at the hips and showed through it in patches.
    hip = float(skel.J["UpperLeg.L"][2])
    snug = relief_band(hip - 0.12 * s, 0.70 * skel.props.height, -0.007 * s, 0.030 * s)
    sc.union(offset_shell(body, reg, thickness * s, gap=0.003 * s, relief=snug,
                          bounds=zbox(skel, 0.02, 0.60 * skel.props.height, xy=0.26)))
    return Garment("trousers", sc, spacing=0.0070, target_tris=3600, material="cloth")


def _cover(body, z: float, a: float, b: float, yc: float = 0.0, gap: float = 0.008,
           xmax: float = 0.30) -> Tuple[float, float]:
    """The semi-axes of an ellipse at height `z` round (0, yc), grown as little as they need to
    be for the body's section there, `gap` out from it, to lie inside.

    The skirts were lofted through fixed ellipses cut for an earlier, narrower body, and the
    final body's hips stood 1-2 cm out through the side of every dress, robe, kilt, wrap skirt
    and coat: in the family lineup a torn white patch of thigh showed at the hip of each dress."""
    xs = np.arange(-xmax, xmax + 1e-9, 0.003)
    ys = np.arange(-0.26, 0.26 + 1e-9, 0.003)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    P = np.stack([X.ravel(), Y.ravel(), np.full(X.size, z)], axis=1)
    inside = body.eval(P) < gap
    if not inside.any():
        return a, b
    k = float(np.sqrt((P[inside, 0] / a) ** 2 + ((P[inside, 1] - yc) / b) ** 2).max())
    return (a * k, b * k) if k > 1.0 else (a, b)


def _covered(body, stations: Sequence[Tuple[float, float, float, float]], gap: float,
             hang_from: int = 1, start: int = 1) -> List[Tuple[float, float, float, float]]:
    """(z, a, b, yc) loft stations, each from `start` on grown to cover the body (`_cover`); and
    from station `hang_from` down none narrower than the one above, because cloth that clears
    the hips hangs from them -- it does not tuck back in under them.

    The waistband (station 0) is left as cut: an ellipse grown round the waist's section stands
    off it at the flanks, and the belt worn over a kilt or a skirt disappeared under it."""
    out: List[Tuple[float, float, float, float]] = []
    for i, (z, a, b, yc) in enumerate(stations):
        if i >= start:
            a, b = _cover(body, z, a, b, yc, gap)
        if i > hang_from:
            a, b = max(a, out[-1][1]), max(b, out[-1][2])
        out.append((z, a, b, yc))
    return out


def _loft_of(stations: Sequence[Tuple[float, float, float, float]]) -> Prim:
    return sdf.loft([(np.array([0.0, yc, z]), a, b) for z, a, b, yc in stations], LEFT, axis=UP)


def _on_ellipse(ang: float, a: float, b: float, z: float, yc: float = 0.0, inset: float = 1.0) -> np.ndarray:
    return np.array([math.cos(ang) * a * inset, yc + math.sin(ang) * b * inset, z])


def _on_loft(stations: Sequence[Tuple[float, float, float, float]], x: float, y: float, z: float,
             out: float = 0.0) -> np.ndarray:
    """The point on a loft's surface at height `z` in the direction of (x, y) from its centre,
    `out` metres proud of it: for laying an edge on a skirt whatever size `_covered` made it."""
    zs = [st[0] for st in stations]
    order = np.argsort(zs)
    a = float(np.interp(z, np.take(zs, order), np.take([st[1] for st in stations], order)))
    b = float(np.interp(z, np.take(zs, order), np.take([st[2] for st in stations], order)))
    yc = float(np.interp(z, np.take(zs, order), np.take([st[3] for st in stations], order)))
    ang = math.atan2(y - yc, x)
    r = 1.0 / math.sqrt((math.cos(ang) / a) ** 2 + (math.sin(ang) / b) ** 2) + out
    return np.array([math.cos(ang) * r, yc + math.sin(ang) * r, z])


def _skirt_weights(skel: Skeleton, keep_hip: float = 0.55,
                   keep_knee: float = 0.90, blend: float = 0.10, shin_back: float = 0.0,
                   shin_front: float = 0.0, panels: bool = False,
                   thigh: float = 0.0) -> Callable[[np.ndarray, np.ndarray], np.ndarray]:
    """A skirt goes with the thighs, and stretches between them.

    Weighted straight from the body, every vertex below the hips took the nearest leg's weights
    whole, so a stride tore the cloth open between the legs. Below the hips the legs' share goes
    to the two thighs now, by a smooth blend across the centre line -- half each on it -- with a
    part of it (less towards the hem) to the hips: the cloth over each thigh moves with that
    thigh, the cloth between them with both, and it stretches instead of tearing. `blend` is how
    wide (in metres, at the default height) the band across the centre line is.

    A short skirt does not bend at the knee, and by default nothing of it is left to the shins.
    One that falls past the knee (the robe, the wrap skirt, the coat) gives `shin_back` of each
    thigh's share below the knee to that shin behind and `shin_front` in front, so it hangs from
    a raised knee instead of standing out from it as a board, and the trailing heel carries its
    back up with it instead of kicking out through it.

    The first cut of this handed most of the legs' share to the hips, and a lineup that was
    meant to show a stride (and showed the idle: see character_review's `_hold_pose`) passed
    it. Held at the Walk's contact pose, the forward leg came out through the front of the robe,
    the wrap skirt and the kilt to the hip.

    With `panels` the legs' share goes to the skirt's own bones (rig.CLOTH_BONES) instead, which
    HumanoidModel's SkirtDrive swings from the thighs: the front with whichever thigh is ahead,
    the back with whichever is behind, each side with its own, and below the knee (a long
    skirt) the front and the back again. `thigh` of it stays with the thigh under it. The
    returned matrix is over rig.WEIGHT_NAMES then, and the forge skins the part over those
    (character_forge._part_object). Only on the grown rig: a child's cut is worn on the grown
    skeleton re-proportioned (ChildProportions), which does not move the skirt's bones."""
    if panels and _panels_fit(skel):
        return _panel_weights(skel, keep_hip, keep_knee, thigh)
    bones = list(rig.DEFORM_NAMES)
    B = {b: i for i, b in enumerate(bones)}
    s = _s(skel)
    hips_z = float(skel.J["UpperLeg.L"][2])
    knee_z = float(skel.J["LowerLeg.L"][2])
    legs = [B[b + side] for side in ("L", "R") for b in ("UpperLeg.", "LowerLeg.", "Foot.", "Toe.")]

    def fn(V, W):
        W = np.array(W, float, copy=True)
        z, x = V[:, 2], V[:, 0]
        below = _ss((hips_z - 0.02 * s - z) / (0.10 * s))
        down = np.clip((hips_z - z) / max(hips_z - knee_z, 1e-3), 0.0, 1.0)
        keep = keep_hip + (keep_knee - keep_hip) * down
        moved = W[:, legs].sum(axis=1) * below
        W[:, legs] *= (1.0 - below)[:, None]
        wl = _ss((x + 0.5 * blend * s) / (blend * s))
        # below the knee a long skirt goes partly with the shins: at the back with the heel as it
        # kicks up, in front with the shin as it hangs from a raised knee
        below_knee = _ss((knee_z - z) / (0.10 * s))
        back = _ss((V[:, 1] + 0.03 * s) / (0.06 * s))
        shin = below_knee * (shin_back * back + shin_front * (1.0 - back))
        for side, share in (("L", wl), ("R", 1.0 - wl)):
            W[:, B["UpperLeg." + side]] += moved * keep * share * (1.0 - shin)
            W[:, B["LowerLeg." + side]] += moved * keep * share * shin
        W[:, B["Hips"]] += moved * (1.0 - keep)
        return W
    return fn


def _panels_fit(skel: Skeleton) -> bool:
    """A skirt may hang from the skirt's bones on this skeleton: the grown one, not a child's."""
    return abs(skel.props.height - rig.DEFAULT_HEIGHT) < 0.05


def _panel_weights(skel: Skeleton, keep_hip: float, keep_knee: float,
                   thigh: float) -> Callable[[np.ndarray, np.ndarray], np.ndarray]:
    """_skirt_weights with `panels`: the legs' share to the skirt's bones, over rig.WEIGHT_NAMES.

    Round the hips it is parted by where the vertex lies from their centre -- front, back, left,
    right, by the square of the angle's cosine -- and below the knee the front's and the back's
    shares go to Skirt.F2 and Skirt.B2, which SkirtDrive hangs from the upper panels: the front
    falls back from a raised knee, the back lifts with a heel kicked up behind."""
    deform = list(rig.DEFORM_NAMES)
    names = list(rig.WEIGHT_NAMES)
    B = {b: i for i, b in enumerate(names)}
    s = _s(skel)
    hips_z = float(skel.J["UpperLeg.L"][2])
    knee_z = float(skel.J["LowerLeg.L"][2])
    cy = float(skel.J["Hips"][1])
    legs = [B[b + side] for side in ("L", "R") for b in ("UpperLeg.", "LowerLeg.", "Foot.", "Toe.")]

    def fn(V, W):
        W0 = np.asarray(W, float)
        W = np.zeros((len(V), len(names)))
        W[:, :len(deform)] = W0
        z, x, y = V[:, 2], V[:, 0], V[:, 1]
        below = _ss((hips_z - 0.02 * s - z) / (0.10 * s))
        down = np.clip((hips_z - z) / max(hips_z - knee_z, 1e-3), 0.0, 1.0)
        keep = keep_hip + (keep_knee - keep_hip) * down
        moved = W[:, legs].sum(axis=1) * below
        W[:, legs] *= (1.0 - below)[:, None]
        # round the hips: the forge's front is -Y, its left +X
        dx, dy = x, y - cy
        r2 = dx * dx + dy * dy + (0.01 * s) ** 2
        front = np.maximum(-dy, 0.0) ** 2 / r2
        back = np.maximum(dy, 0.0) ** 2 / r2
        left = np.maximum(dx, 0.0) ** 2 / r2
        right = np.maximum(-dx, 0.0) ** 2 / r2
        tot = front + back + left + right
        front, back, left, right = front / tot, back / tot, left / tot, right / tot
        below_knee = _ss((knee_z - z) / (0.10 * s))
        share = moved * keep
        cloth = share * (1.0 - thigh)
        W[:, B["Skirt.F"]] += cloth * front * (1.0 - below_knee)
        W[:, B["Skirt.F2"]] += cloth * front * below_knee
        W[:, B["Skirt.B"]] += cloth * back * (1.0 - below_knee)
        W[:, B["Skirt.B2"]] += cloth * back * below_knee
        W[:, B["Skirt.L"]] += cloth * left
        W[:, B["Skirt.R"]] += cloth * right
        wl = _ss((x + 0.025 * s) / (0.05 * s))
        W[:, B["UpperLeg.L"]] += share * thigh * wl
        W[:, B["UpperLeg.R"]] += share * thigh * (1.0 - wl)
        W[:, B["Hips"]] += moved * (1.0 - keep)
        return W
    return fn


def skirt(skel: Skeleton, body, *, hem: float = 0.30, flare: float = 1.0, name: str = "skirt",
          gap: float = 0.008, folds: int = 9) -> Garment:
    """A skirt from the waist, `flare` how far its hem stands out, clearing the body (and whatever
    is worn under it) by `gap`."""
    s = _s(skel)
    hip = float(skel.J["UpperLeg.L"][2])
    z_hem = hem * skel.props.height
    waist = float(skel.J["Spine"][2])
    sc = Scene()
    st = _covered(body, [
        (waist, 0.134 * s, 0.100 * s, 0.0),
        (hip + 0.02 * s, 0.158 * s, 0.118 * s, 0.0),
        ((hip + z_hem) * 0.5, (0.172 + 0.030 * flare) * s, (0.130 + 0.026 * flare) * s, 0.0),
        (z_hem + 0.02 * s, (0.186 + 0.058 * flare) * s, (0.142 + 0.048 * flare) * s, 0.0),
        (z_hem, (0.187 + 0.058 * flare) * s, (0.143 + 0.048 * flare) * s, 0.0),
    ], gap=gap * s)
    sc.union(_loft_of(st))
    # soft vertical folds, from the hips to the hem on the skirt's own surface
    n = folds
    hz, ha, hb, _ = st[1]
    ez, ea, eb, _ = st[-1]
    for i in range(n):
        a = 2 * math.pi * i / n
        sc.subtract(sdf.tube_path([_on_ellipse(a, ha, hb, hz, inset=0.985), _on_ellipse(a, ea, eb, ez)],
                                  0.010 * s), k=0.016 * s)
    sc.union(sdf.tube_path(_ring(ea, eb, z_hem + 0.010 * s), 0.0060 * s), k=0.006 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment(name, sc, spacing=0.0080, target_tris=3400, material="cloth", open_below=z_hem)
    # nearly all of the thigh's swing, from the top: at 45 % the forward thigh's front came through
    # a robe at mid-thigh, where it moves 6 cm and the cloth stands 1 cm off it. All of it now,
    # and parted between the thighs over 5 cm, not 10: with its floor gone, the rest measured by
    # clipcheck at the worst of the Run and the Sprint was 3 and 9 leg vertices drawn through at
    # 80 %, and 2 and 1 like this.
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05)
    g.stations = st
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
    # wide sleeve bells (a hand's width across at the cuff: at 20 cm, hanging by the hips in the
    # engine, they read as two balloons -- triage 46's review)
    for side in ("L", "R"):
        wr = skel.J[f"Hand.{side}"]
        el = skel.J[f"LowerArm.{side}"]
        d = rig._unit(wr - el)
        g.scene.union(sdf.loft([
            (el + d * 0.10 * s, 0.058 * s, 0.058 * s),
            (wr - d * 0.02 * s, 0.070 * s, 0.070 * s),
            (wr + d * 0.03 * s, 0.072 * s, 0.072 * s),
        ], FWD), k=0.02 * s)
    g.target_tris = 4800
    g.spacing = 0.0080
    # To the ankle, it goes with the shins below the knee as well: hung from the thighs alone it
    # swung up as a board over a raised knee, and the trailing heel kicked out through its back
    # (clipcheck, the worst of the Walk, Run and Sprint: 40, 75 and 70 leg vertices drawn through;
    # 3, 7 and 13 like this).
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05,
                                     shin_back=0.85, shin_front=0.5)
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


def _near_segments(V: np.ndarray, a: np.ndarray, b: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Distance from each point to the segment a-b, and where along it (0..1) the nearest point is."""
    ab = b - a
    t = np.clip(((V - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(V - (a + t[:, None] * ab), axis=1), t


def _cloak_weights(skel: Skeleton, hooded: bool, hang: bool = False,
                   hand: float = 0.0) -> Callable[[np.ndarray], np.ndarray]:
    """What a cloak moves with. The hood with the head above the jaw, fading into the neck by
    the shoulders; the shoulder girdle at the points of the shoulders, and some of each upper
    arm where the cloth lies over it; then the chest, the spine and the hips down the back;
    and near the hem the front panels take a share of the thigh on their side, so a stride
    pushes the cloak open instead of through it. Weighted from the body instead, a cloak to
    the knee is torn down the middle by every step.

    `hang`: the cloak is modelled over the arms as they hang in the Idle (`drape_field`'s
    `hang_arms`), and the cloth that lies on an arm or hangs in front of or behind it, down to
    the wrist, takes nearly all of that arm's swing -- the upper arm's above the elbow, the
    forearm's below it. Without it the arms swung out through the sides of the cloak at every
    step. The game also holds a walker's arms in under a long cloak (HumanoidModel.ARM_HOLD):
    with the whole Walk swing, the hand came out through the front whatever the weights."""
    bones = list(rig.DEFORM_NAMES)
    B = {b: i for i, b in enumerate(bones)}
    s = _s(skel)
    L = bodylib.head_landmarks(skel)
    J = skel.J
    neck_z, chest_z = float(J["Neck"][2]), float(J["Chest"][2])
    spine_z, hips_z = float(J["Spine"][2]), float(J["Hips"][2])
    arms = {side: hanging_arm(skel, side) for side in ("L", "R")} if hang else {}

    def fn(V):
        W = np.zeros((len(V), len(bones)))
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        ax = np.abs(x)
        w_head = _ss((z - (L["chin_z"] - 0.010 * s)) / (0.050 * s)) if hooded else np.zeros(len(V))
        w_neck = (_ss((z - (neck_z - 0.010 * s)) / (0.035 * s)) * (1.0 - w_head)
                  * np.clip((0.13 * s - ax) / (0.05 * s), 0.0, 1.0))
        rest = 1.0 - w_head - w_neck
        w_sh = rest * 0.40 * np.clip((ax - 0.09 * s) / (0.12 * s), 0.0, 1.0) * _ss((z - (chest_z - 0.06 * s)) / (0.12 * s))
        if hang:
            left = x >= 0
            w_ua, w_la = np.zeros(len(V)), np.zeros(len(V))
            # Distance ahead of and behind an arm counts at 0.4 of itself: the cloth in front of
            # an arm and behind it is what its swing pushes. By plain distance only the cloth at
            # the arm's side went with it, the cloth hanging in front of the arm stayed where it
            # hung, and the Walk brought the forearm and the hand out through it.
            ahead = np.array([1.0, 0.4, 1.0])
            for side, m in (("L", left), ("R", ~left)):
                sh, el, wr = arms[side]
                # `hand`: the forearm's reach runs on past the wrist to the fingertips, this far
                wr = wr + rig._unit(wr - el) * hand * s
                sh, el, wr = (p * ahead for p in (sh, el, wr))
                Q = V[m] * ahead
                d_u, _ = _near_segments(Q, sh, el)
                d_l, _ = _near_segments(Q, el, wr)
                near = 1.0 - _ss((np.minimum(d_u, d_l) - 0.090 * s) / (0.06 * s))
                fore = _ss((d_u - d_l) / (0.03 * s))
                share = 0.95 * near * (rest[m] - w_sh[m])
                w_ua[m] = share * (1.0 - fore)
                w_la[m] = share * fore
            rest = rest - w_sh - w_ua - w_la
        else:
            w_ua = (rest * 0.30 * np.clip((ax - 0.21 * s) / (0.06 * s), 0.0, 1.0)
                    * _ss((z - (chest_z - 0.24 * s)) / (0.14 * s)) * (1.0 - _ss((z - (neck_z - 0.03 * s)) / (0.05 * s))))
            w_la = np.zeros(len(V))
            rest = rest - w_sh - w_ua
        w_ch = rest * _ss((z - spine_z) / (chest_z - spine_z))
        w_hip = rest * _ss((spine_z - z) / (spine_z - hips_z))
        w_sp = rest - w_ch - w_hip
        w_leg = w_hip * 0.45 * _ss((hips_z - 0.10 * s - z) / (0.25 * s)) * np.clip(-y / (0.10 * s), 0.0, 1.0)
        # With `hang` the back takes half of the thigh behind it too, from just under the hips
        # down, handed from one thigh to the other across the middle of the back so that the back
        # stays one sheet: without it the leg behind came out through the back at every stride.
        w_back = np.zeros(len(V))
        if hang:
            w_back = w_hip * 0.50 * _ss((hips_z - 0.05 * s - z) / (0.25 * s)) * np.clip(y / (0.10 * s), 0.0, 1.0)
        to_left = _ss((x / (0.08 * s) + 1.0) * 0.5)
        w_hip = w_hip - w_leg - w_back
        left = x >= 0
        for side, m in (("L", left), ("R", ~left)):
            W[m, B["Shoulder." + side]] = w_sh[m]
            W[m, B["UpperArm." + side]] = w_ua[m]
            W[m, B["LowerArm." + side]] = w_la[m]
            W[m, B["UpperLeg." + side]] = w_leg[m]
        W[:, B["UpperLeg.L"]] += w_back * to_left
        W[:, B["UpperLeg.R"]] += w_back * (1.0 - to_left)
        W[:, B["Head"]] = w_head
        W[:, B["Neck"]] = w_neck
        W[:, B["Chest"]] = w_ch
        W[:, B["Spine"]] = w_sp
        W[:, B["Hips"]] = w_hip
        return W
    return fn


GATHER = 0.040   # how far a cloak's cloth stands off behind the neck, where it is gathered (m at 1.78)


def cloak(skel: Skeleton, body, *, hooded: bool = False, hem: float = 0.30, ragged: int = 0,
          open_front: bool = True, hem_z: Optional[float] = None, name: Optional[str] = None,
          hood_down: bool = False) -> Garment:
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
    False closes it all round (a hood's own short cape). `hood_down` lays the hood back: a
    thick roll of cloth round the back of the neck, and the hood itself lying down the back
    from it. It is most of what rounds the cloak's top: over this body's square deltoids the
    cloth alone fell only 4 cm from the neck to the point of the shoulder and read as a shelf."""
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
    drape = drape_field(body, skel, flare=0.045, hang_arms=True)
    if hooded:
        # a smaller peak and less flare: at a full peak and 0.16 the spare cloth fell straight
        # from a corner behind the crown, and in profile the hood was a box on the head
        cowl = cowl_field(skel, flare=0.11, peak=0.6)
        fld = FieldFn(lambda P: np.minimum(drape.eval(P), cowl.eval(P)))
    else:
        fld = drape
    # the cloak's upper edge lies round the base of the neck. At 4.5 cm over the shoulder line,
    # with its collar ring on top, it stood up to the mouth in the Naming's whole figure
    top = sh + 0.020 * s
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
            # the top is cut round the base of the neck only: cut flat across the shoulders too,
            # it took the top off the cloth where it rounds over each shoulder and left a flat
            # rim from shoulder to shoulder, the top of a box
            near_neck = np.clip((0.140 * s - r) / (0.020 * s), 0.0, 1.0)
            # (behind, the cut stands as high as the cloth is gathered there: level with the
            # front, it cut ragged holes along the top of the gathered cloth)
            lift = GATHER * s * np.clip((P[:, 1] + 0.03 * s) / (0.06 * s), 0.0, 1.0)
            below_top = np.clip((top + lift - z) / (0.006 * s), 0.0, 1.0)
            w = w * (1.0 - near_neck * (1.0 - below_top)) * np.clip((r - 0.080 * s) / (0.006 * s), 0.0, 1.0)
        return w

    def relief(P):
        sa = _signed_around(P)
        depth = fall(P) ** 0.7
        folds = 0.75 * (0.5 + 0.5 * np.sin(n_folds * sa + 0.4)) + 0.25 * (0.5 + 0.5 * np.sin(31 * sa + 1.3))
        # a short cape has room for shallow folds only
        out = 0.024 * s * amp_k * depth * folds
        if not hooded:
            # The cloth stands off the body more towards the neck, where it is gathered: the top
            # then falls from the neck to the point of the shoulder. Laid at one distance over
            # this body's square deltoids it lay flat from neck to arm, a shelf with a corner.
            # Behind the neck and over the shoulders only: gathered in front as well, it stood
            # up to the wearer's mouth.
            ax = np.abs(P[:, 0])
            near = np.clip(1.0 - (ax - 0.08 * s) / (0.20 * s), 0.0, 1.0)
            high = np.clip((P[:, 2] - (sh - 0.07 * s)) / (0.06 * s), 0.0, 1.0)
            behind = np.clip((P[:, 1] + 0.03 * s) / (0.06 * s), 0.0, 1.0)
            out = out + GATHER * s * near ** 1.2 * high * behind
        if hooded:
            # the edge of the face opening rolled back on itself, standing a little proud
            e = np.sqrt((P[:, 0] / f_ax) ** 2 + ((P[:, 2] - f_zc) / f_az) ** 2)
            near = np.clip(1.0 - np.abs(e - 1.0) * f_az / (0.016 * s), 0.0, 1.0)
            out = out + 0.004 * s * near * (P[:, 1] < f_cut + 0.02 * s)
        return out

    z_top = float(L["top"][2]) + 0.10 * s if hooded else top + (0.03 + GATHER) * s
    shell, trim = draped_shell(fld, region, 0.012 * s, 0.016 * s,
                               zbox(skel, z_hem - 0.14 * s, z_top, xy=0.48, ymin=-0.36, ymax=0.44),
                               relief=relief)
    sc = Scene()
    sc.union(shell)
    off = 0.016 * s + 0.006 * s
    if not hooded and not hood_down:
        ring = np.array(_ring(0.086 * s, 0.082 * s, sh + 0.010 * s)) + np.array([0.0, 0.010 * s, 0.0])
        sc.union(sdf.tube_path(ring, 0.012 * s, closed=False), k=0.008 * s)
    if hood_down:
        # the roll: thin where it comes round to the clasp, thick behind the neck, and sitting a
        # little higher there, where the hood's opening is folded back on itself
        roll, radii = [], []
        for a in np.linspace(-0.62 * math.pi, 0.62 * math.pi, 21):
            t = abs(a) / math.pi                           # 0 at the front, 1 behind
            ang = a + math.pi / 2.0                        # _ring's angle: 0 at +x, pi/2 behind
            # on the gathered cloth round the neck (the relief below stands it 4.5 cm off there)
            rx, ry = (0.112 + 0.012 * t) * s, (0.106 + 0.026 * t) * s
            roll.append([rx * math.cos(ang), ry * math.sin(ang) + 0.010 * s, sh + (0.004 + 0.034 * t) * s])
            radii.append((0.013 + 0.022 * t ** 1.5) * s)
        sc.union(sdf.tube_path(roll, radii, closed=False), k=0.012 * s)
        # the hood lying down the back: broad under the roll, narrowing to its point between
        # the shoulder blades, and lying on the cloak
        stations = []
        for i, dz in enumerate((0.0, -0.06, -0.12, -0.18, -0.23)):
            z = sh + (0.010 + dz) * s
            ru = (0.070, 0.074, 0.060, 0.036, 0.012)[i] * s
            rv = (0.024, 0.020, 0.016, 0.012, 0.008)[i] * s
            gathered = GATHER * s * float(np.clip((z - (sh - 0.07 * s)) / (0.06 * s), 0.0, 1.0))
            back = _surface_point(fld, off + gathered + rv, math.pi, z, centre=(0.0, 0.02 * s))
            stations.append((back, ru, rv))
        sc.union(sdf.sweep(stations, np.array([1.0, 0.0, 0.0])), k=0.010 * s)
    # the clasp at the throat: a round brooch on the front of the cloth
    front = _surface_point(fld, off, 0.0, clasp + 0.004 * s)
    sc.union(sdf.ellipsoid(front + np.array([0.0, -0.004 * s, 0.0]), [0.014 * s, 0.006 * s, 0.014 * s]), k=0.003 * s)
    nm = name or ("hooded_cloak" if hooded else "cloak")
    g = Garment(nm, sc, spacing=0.0055 if not hooded else 0.0050, smooth=4, target_tris=5200 if hooded else 4400,
                material="cloth", trim=trim, trim_depth=0.0)
    g.weight_fn = _cloak_weights(skel, hooded, hang=True)
    g.double_sided = True
    g.rebind = True
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
        tip = bodylib.foot_tip(skel, side)
        sc.union(sdf.loft([
            # a real sole: 27-28 cm long and 9-10 cm across the ball; at 5.8 cm half-widths and
            # a heel 7.5 cm behind the ankle, the boots were a clown's
            (np.array([an[0], an[1] + 0.058 * s, 0.012 * s]), 0.040 * s, 0.014 * s),
            (np.array([an[0], an[1], 0.010 * s]), 0.044 * s, 0.012 * s),
            (np.array([an[0], tip[1] + 0.012 * s, 0.010 * s]), 0.047 * s, 0.011 * s),
        ], LEFT), k=0.012 * s)
        sc.union(sdf.box([an[0], an[1] + 0.050 * s, 0.014 * s], [0.036 * s, 0.030 * s, 0.016 * s], round_r=0.008 * s), k=0.012 * s)
    sc.intersect(sdf.plane([0.0, 0.0, 0.0], [0.0, 0.0, -1.0]), k=0.006 * s)
    return Garment("boots", sc, spacing=0.0055, target_tris=1600, material="leather")


def shoes(skel: Skeleton, body) -> Garment:
    g = boots(skel, body, high=0.07)
    g.name = "shoes"
    g.target_tris = 1100
    return g


def gloves(skel: Skeleton, body) -> Garment:
    """Leather gloves 3 mm over the hand, with a short cuff over the wrist: one mesh a hand.

    They were an offset of the body's field, 1 cm out: that field is sampled at 5 mm and has no
    gaps between fingers in it, so a glove was a padded mitten -- the paddle the bare hand used
    to be. The hands are sampled on their own at 2 mm here, and each glove is meshed round its
    own hand rather than over a box spanning both."""
    s = _s(skel)
    hands = sdf.SampledField(bodylib.hands_scene(skel), spacing=0.002, margin=0.02)
    fld = FieldFn(lambda P: np.minimum(hands.eval(P), body.eval(P)))
    pieces: List[Garment] = []
    for side in ("L", "R"):
        wr = skel.J[f"Hand.{side}"]
        tip = skel.J[f"HandTip.{side}"]
        reg = near_bones(skel, [f"Hand.{side}"], 0.115 * s, 0.045 * s)
        cuff = near_bones(skel, [f"LowerArm.{side}"], 0.075 * s, 0.03 * s)

        def near_wrist(P, wr=wr):
            return 1.0 - sdf_smoothstep(0.070 * s, 0.095 * s, np.linalg.norm(P - wr, axis=1))
        lo = np.minimum(wr, tip) - 0.12 * s
        hi = np.maximum(wr, tip) + 0.12 * s
        sc = Scene()
        sc.union(solid_shell(fld, region_or(reg, region_and(cuff, near_wrist)), 0.0020 * s, gap=0.0010 * s,
                             bounds=(lo, hi)))
        pieces.append(Garment("gloves" if side == "L" else "gloves_r", sc, spacing=0.0026, smooth=2,
                              target_tris=1500, material="leather", grip=True))
    pieces[0].layers = [pieces[1]]
    return pieces[0]


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
        # on the front of the left hip, outside the body: at (0.105, -0.030) it sat inside the
        # belly, and no belt in the game ever showed its pouch
        px, py = 0.118 * s, -0.112 * s
        sc.union(sdf.box([px, py, z - 0.052 * s], [0.040 * s, 0.022 * s, 0.044 * s], round_r=0.014 * s), k=0.010 * s)
        sc.union(sdf.box([px, py - 0.004 * s, z - 0.016 * s], [0.042 * s, 0.024 * s, 0.012 * s], round_r=0.006 * s), k=0.006 * s)
    return Garment("belt", sc, spacing=0.0040, target_tris=900, material="leather")


# -- what a belt carries: each people's own, so a lineup reads as different people -----------
# A crowd of the same belt with the same pouch was the same person six times over at a distance.
# Each of these is a belt part (the belt slot), chosen by culture in CharacterAppearance.

def _knife(sc_leather: Scene, sc_metal: Scene, s: float, x: float, y: float, z: float, lean: float = 0.12) -> None:
    """A knife in its sheath hanging from a belt at (x, y, z): the sheath down the thigh, the grip up."""
    down = np.array([lean * np.sign(x) * 1.5, 0.02, -1.0])
    down = down / np.linalg.norm(down)
    top = np.array([x, y, z - 0.010 * s])
    tipp = top + down * 0.200 * s
    # the sheath: flat, wider at the throat
    sc_leather.union(sdf.tube_path([top, top + down * 0.12 * s, tipp],
                                   [0.016 * s, 0.013 * s, 0.006 * s]), k=0.004 * s)
    # the frog that holds it to the belt
    sc_leather.union(sdf.box(top + np.array([0.0, 0.0, 0.020 * s]), [0.016 * s, 0.008 * s, 0.020 * s],
                             round_r=0.004 * s), k=0.004 * s)
    grip_top = top - down * 0.095 * s
    sc_leather.union(sdf.capsule(top - down * 0.012 * s, grip_top, 0.0105 * s), k=0.003 * s)
    # the guard and the pommel in iron
    sc_metal.union(sdf.box(top - down * 0.006 * s, [0.028 * s, 0.009 * s, 0.006 * s], round_r=0.003 * s))
    sc_metal.union(sdf.sphere(grip_top - down * 0.008 * s, 0.014 * s))


def _belt_band(skel: Skeleton, body, s: float, z: float, width: float, thick: float, gap: float) -> Prim:
    reg = band_z(z - width, z + width, 0.006 * s)
    return offset_shell(body, reg, thick, gap=gap, bounds=zbox(skel, z - width - 0.03 * s, z + width + 0.03 * s, xy=0.26))


def belt_knife(skel: Skeleton, body) -> Garment:
    """The clans' and the woodfolk's: a belt with a pouch on the left and a long knife on the right."""
    s = _s(skel)
    g = belt(skel, body)
    g.name = "belt_knife"
    z = float(skel.J["Spine"][2]) - 0.02 * s
    metal = Scene()
    _knife(g.scene, metal, s, -0.128 * s, -0.112 * s, z - 0.010 * s)
    g.layers = [Garment("belt_knife_iron", metal, spacing=0.0030, smooth=2, target_tris=300, material="iron")]
    g.target_tris = 1300
    return g


def sash(skel: Skeleton, body) -> Garment:
    """The Reedfolk's: a broad cloth sash wound twice round the waist and knotted on the left hip,
    its two ends hanging to the thigh."""
    s = _s(skel)
    sc = Scene()
    z = float(skel.J["Spine"][2]) - 0.01 * s
    sc.union(_belt_band(skel, body, s, z, 0.040 * s, 0.010 * s, 0.010 * s))
    # the second turn, a little lower and proud of the first
    sc.union(_belt_band(skel, body, s, z - 0.030 * s, 0.018 * s, 0.013 * s, 0.012 * s), k=0.006 * s)
    knot = np.array([0.130 * s, -0.080 * s, z - 0.010 * s])
    sc.union(sdf.ellipsoid(knot, [0.026 * s, 0.022 * s, 0.024 * s]), k=0.008 * s)
    for dx, ln in ((-0.012, 0.21), (0.018, 0.17)):
        a = knot + np.array([dx * s, -0.004 * s, -0.010 * s])
        b = a + np.array([0.020 * s, -0.012 * s, -ln * s])
        sc.union(sdf.tube_path([a, (a + b) * 0.5, b], [0.014 * s, 0.015 * s, 0.013 * s]), k=0.006 * s)
    return Garment("sash", sc, spacing=0.0040, target_tris=1400, material="cloth")


def cord_beads(skel: Skeleton, body) -> Garment:
    """The Ash-Pilgrims': a knotted cord over the robe, and a string of prayer beads from it."""
    s = _s(skel)
    sc = Scene()
    z = float(skel.J["Spine"][2]) - 0.01 * s
    # over a robe, which stands off the body: the cord rides at the robe's surface
    sc.union(_belt_band(skel, body, s, z, 0.008 * s, 0.009 * s, 0.022 * s))
    knot = np.array([-0.040 * s, -0.150 * s, z])
    sc.union(sdf.sphere(knot, 0.014 * s), k=0.004 * s)
    for dx, ln in ((-0.006, 0.30), (0.010, 0.26)):
        pts = [knot + np.array([dx * s, -0.006 * s * f, -ln * s * f]) for f in (0.0, 0.5, 1.0)]
        sc.union(sdf.tube_path(pts, 0.0048 * s), k=0.003 * s)
        sc.union(sdf.sphere(pts[-1] + np.array([0.0, 0.0, -0.008 * s]), 0.010 * s), k=0.003 * s)
    # the beads: a loop hanging from the cord at the right hip
    top = np.array([-0.130 * s, -0.070 * s, z - 0.010 * s])
    for i in range(14):
        a = 2 * math.pi * i / 14
        p = top + np.array([0.020 * s * math.sin(a), -0.012 * s, -0.070 * s * (1.0 - math.cos(a))])
        sc.union(sdf.sphere(p, 0.0070 * s), k=0.002 * s)
    return Garment("cord_beads", sc, spacing=0.0032, target_tris=1400, material="cloth")


def belt_satchel(skel: Skeleton, body) -> Garment:
    """The Lakefolk's: a satchel on a strap from the right shoulder to the left hip, over the coat."""
    s = _s(skel)
    sc = Scene()
    sh = np.asarray(skel.J["UpperArm.R"], float)
    hip = np.asarray(skel.J["UpperLeg.L"], float)
    a = np.array([sh[0] * 0.55, 0.0, sh[2] + 0.050 * s])
    b = np.array([hip[0] * 1.2, 0.0, hip[2] + 0.030 * s])
    d = sdf._unit(b - a)
    n = sdf._unit(np.cross(d, np.array([0.0, 1.0, 0.0])))

    def strap(P):
        return 1.0 - sdf_smoothstep(0.020 * s, 0.026 * s, np.abs((P - a) @ n))
    # over the coat, which stands 1.6 cm off the body
    sc.union(offset_shell(body, strap, 0.005 * s, gap=0.019 * s,
                          bounds=zbox(skel, float(hip[2]) - 0.06 * s, float(sh[2]) + 0.12 * s, xy=0.30)))
    bag = np.array([hip[0] * 1.55, -0.010 * s, hip[2] - 0.040 * s])
    sc.union(sdf.box(bag, [0.030 * s, 0.085 * s, 0.070 * s], round_r=0.020 * s), k=0.010 * s)
    sc.union(sdf.box(bag + np.array([0.012 * s, 0.0, 0.040 * s]), [0.022 * s, 0.088 * s, 0.036 * s],
                     round_r=0.012 * s), k=0.006 * s)
    return Garment("belt_satchel", sc, spacing=0.0045, target_tris=1400, material="leather")


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
                # A step is never more than 5 cm: where no primitive reached, a sampled field reads
                # 1e6, and one step on that threw a rivet 1 000 km out -- the brigandine's grid
                # then spanned it, and numpy refused to allocate it.
                dd = np.clip(body.eval(P) - off, -0.05 * s, 0.05 * s)
                P = P - body.gradient(P) * dd[:, None]
            miss = abs(float(body.eval(P)[0]) - off) > 0.003 * s or float(np.hypot(P[0, 0], P[0, 1])) > 0.35 * s
            if (not np.all(np.isfinite(P)) or miss or skip(P)[0] > 0.5
                    or abs(P[0, 2] - z) > 0.03 * s):
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
    # The brigandine's leather body, with its standing collar and lames, decimated to 5 200
    # triangles from 325 000, lay in chords across the chest and the shoulders that cut inside the
    # coat 1.4 cm under it: in the engine the orange coat showed through the leather in patches.
    main = Garment(name, sc, spacing=0.0034, smooth=3, target_tris=5200 if not brigandine else 9000,
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
    taper: float = 0.62         # how much of a lock's root thickness is gone at its tip
    # -- the styles added for the Naming's wider choice (triage 39) ----------------------------
    curl: float = 0.0           # a lock wound in a helix this far off its line (metres at 1.78 m)
    curl_period: float = 0.024  # ...one turn in this much of its length
    recede: float = 0.0         # the temples taken back (bodylib.hairline_height)
    strip: float = 0.0          # only a strip this wide each side of the middle keeps its length;
                                # the rest is shaved to a shadow (0: the whole scalp)
    tail_len: float = 0.0       # a tail tied at the back of the crown, hanging this long


def _crown(L: dict) -> np.ndarray:
    s = L["s"]
    return np.array([0.0, L["skull_c"][1] + 0.030 * s, L["chin_z"] + 0.965 * L["V"]])


def _sink(g: Groom, L: dict) -> Optional[np.ndarray]:
    s, V, z0, cy = L["s"], L["V"], L["chin_z"], L["skull_c"][1]
    if g.extra == "bun":
        return np.array([0.0, cy + 0.114 * s, z0 + 0.720 * V])
    if g.extra == "braid":
        return np.array([0.0, cy + 0.078 * s, z0 + 0.330 * V])
    if g.extra == "tail":
        # high on the back of the head, where a tail is tied
        return np.array([0.0, cy + 0.098 * s, z0 + 0.640 * V])
    if g.extra in ("chignon", "crown"):
        # low on the back of the head, over the nape: a knot, not a topknot
        return np.array([0.0, cy + 0.106 * s, z0 + 0.420 * V])
    if g.extra == "twin_braids":
        # the left one; the right is its mirror (`_sinks`)
        return np.array([0.050 * s, cy + 0.052 * s, z0 + 0.330 * V])
    return None


def _sinks(g: Groom, L: dict) -> List[np.ndarray]:
    """Every point a style's locks are combed into: one, or a pair for two braids."""
    sink = _sink(g, L)
    if sink is None:
        return []
    if g.extra == "twin_braids":
        return [sink, sink * np.array([-1.0, 1.0, 1.0])]
    return [sink]


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
        if g.extra == "twin_braids":
            # parted down the middle, each side to its own braid behind the ear
            def to_sinks(P):
                side = np.where(P[:, 0] >= 0.0, 1.0, -1.0)[:, None]
                return _unit_rows(sink[None] * np.concatenate([side, np.ones((len(P), 2))], axis=1) - P)
            return to_sinks

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
                # eased out to the clearance a little at a time: pushed out in one go, a beard
                # leaving the chin jumped 3 cm, the runaway guard below took that for a wild
                # projection, and every long beard stopped at the jaw
                c = clear if clear is not None else 0.008 * s + 0.5 * o
                db = float(body.eval(q[None])[0])
                if db < c:
                    q = q + body.gradient(q[None])[0] * min(c - db, 2.0 * step)
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


def _lock_prim(pts: np.ndarray, r0: float, s: float, taper: float = 0.62) -> Prim:
    u = np.linspace(0.0, 1.0, len(pts))
    radii = r0 * (1.0 - taper * u ** 1.5) + 0.0010 * s
    return sdf.tube_path(pts, radii, density=2, max_spheres=160)


def _plait(centre: np.ndarray, s: float, width: float = 1.0, taper_to: float = 0.55, closed: bool = False,
           out_hint: Optional[np.ndarray] = None) -> Tuple[List[Prim], List[np.ndarray]]:
    """Three strands plaited along `centre`: each crosses over the middle in turn, so the plait
    shows its chevrons from any side. `width` scales it (1 is a braid of the whole head of hair),
    `taper_to` is how thick it ends against how it starts. A `closed` plait (a crown) comes round
    to meet itself, a whole number of crossings round. `out_hint` is which way is away from the
    head at each point (for a plait lying on it); a hanging one takes its side from the view."""
    seg = np.diff(centre, axis=0)
    tang = _unit_rows(np.concatenate([seg, seg[-1:]], axis=0))
    if out_hint is not None:
        back = _unit_rows(out_hint - tang * np.sum(out_hint * tang, axis=1, keepdims=True))
        side = _unit_rows(np.cross(tang, back))
    else:
        side = _unit_rows(np.cross(tang, np.array([0.0, -1.0, 0.0])))
        back = _unit_rows(np.cross(side, tang))
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(seg, axis=1))])
    prims, lines = [], []
    amp = 0.0110 * s * width
    period = 0.056 * s * width
    if closed:
        period = arc[-1] / max(3, round(arc[-1] / period))
    taper = np.ones_like(arc) if closed else 1.0 - (1.0 - taper_to) * (arc / max(arc[-1], 1e-6))
    for k in range(3):
        ph = 2.0 * math.pi * k / 3.0
        w = 2.0 * math.pi * arc / period + ph
        off = side * (amp * taper * np.sin(w))[:, None] + back * (0.45 * amp * taper * np.sin(2.0 * w))[:, None]
        pts = centre + off
        prims.append(sdf.tube_path(pts, 0.0086 * s * width * taper, density=2, max_spheres=260, k=0.002 * s))
        lines.append(pts)
    return prims, lines


def _laid_path(points: Sequence[np.ndarray], body, head, s: float, clear, step: float = 0.005) -> np.ndarray:
    """A line through `points`, rounded at its corners, every point of it kept `clear` off the body
    (metres, or a function of the points) and a centimetre off the head: a braid laid over a
    shoulder rather than combed down it."""
    P = np.asarray(points, float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    arc = np.concatenate([[0.0], np.cumsum(seg)])
    t = np.arange(0.0, arc[-1], step)
    C = np.stack([np.interp(t, arc, P[:, i]) for i in range(3)], axis=1)
    for _ in range(6):
        # round the corners: a few passes of neighbour averaging, the ends held
        C[1:-1] = 0.25 * C[:-2] + 0.5 * C[1:-1] + 0.25 * C[2:]
        for fld, c_ in ((body, clear), (head, 0.010 * s)):
            if fld is None:
                continue
            d = fld.eval(C)
            push = np.clip((c_(C) if callable(c_) else c_) - d, 0.0, 0.02)
            C = C + fld.gradient(C) * push[:, None]
    return C


def _braid_prims(start: np.ndarray, body, head, L: dict, s: float, length: float = 0.27,
                 fall=(0.0, 0.25, -1.0), width: float = 1.0,
                 through: Optional[Sequence[np.ndarray]] = None,
                 clear: float = HANG_CLEAR) -> Tuple[List[Prim], List[np.ndarray]]:
    """A three-strand braid hanging from `start` -- by default from the nape down the back -- and
    its tie and tuft. `fall` is the way it is let go; or `through` lays it along those points
    (two braids brought forward over the shoulders, which combing lets slide back off them)."""
    fall = np.asarray(fall, float)
    if through is not None:
        centre = _laid_path([start] + list(through), body, head, s,
                            (lambda C: clear(C) * s) if callable(clear) else clear * s)
    else:
        centre = comb(head, start, lambda P: np.tile(fall, (len(P), 1)),
                      length * s, lambda u: 0.012 * s, release_z=1e9, s=s, body=body, step=0.005,
                      clear=HANG_CLEAR * s)
    if len(centre) < 4:
        return [], []
    seg = np.diff(centre, axis=0)
    tang = _unit_rows(np.concatenate([seg, seg[-1:]], axis=0))
    side = _unit_rows(np.cross(tang, np.array([0.0, -1.0, 0.0])))
    back = _unit_rows(np.cross(side, tang))
    prims, lines = _plait(centre, s, width=width)
    end = centre[-1]
    prims.append(sdf.torus(end + tang[-1] * 0.002 * s, 0.0080 * s, 0.0034 * s, axis=tang[-1], k=0.002 * s))
    tuft = [end, end + tang[-1] * 0.024 * s * width + back[-1] * 0.004 * s, end + tang[-1] * 0.046 * s * width]
    prims.append(sdf.tube_path(tuft, [0.0075 * s * width, 0.0085 * s * width, 0.0024 * s], density=2, k=0.003 * s))
    lines.append(np.array(tuft))
    return prims, lines


def _crown_arc(head, L: dict, s: float, off: float) -> Tuple[np.ndarray, np.ndarray]:
    """The line a plaited crown lies along: from above one ear, over the top of the head a few
    fingers behind the hairline, to above the other, `off` out from the scalp -- a plait pinned
    across the head like a band. Returns the centreline and the way out from the head along it.

    It was a ring round the head at first, high over the brow and low behind, and from any side
    that is a knitted cap's rolled brim.

    Each point is found along a ray out from the middle of the skull, by halving: projected along
    the field's gradient, points settle in its creases; and the sampled head field ends a
    centimetre off the skull, so the scalp is found and the plait stood off it along its normal."""
    c = np.array([0.0, float(L["skull_c"][1]), float(L["skull_c"][2])])
    tilt = math.radians(24.0)                         # the band leans back from upright
    dirs = []
    for th in np.linspace(-math.radians(84.0), math.radians(84.0), 61):
        dirs.append([math.sin(th), math.cos(th) * math.sin(tilt), math.cos(th) * math.cos(tilt)])
    D = np.array(dirs)
    lo = np.zeros(len(D))
    hi = np.full(len(D), 0.20 * s)
    for _ in range(30):
        mid = 0.5 * (lo + hi)
        outside = head.eval(c + D * mid[:, None]) > 0.0
        hi = np.where(outside, mid, hi)
        lo = np.where(outside, lo, mid)
    P = c + D * (0.5 * (lo + hi))[:, None]
    out = head.gradient(P)
    return P + out * off, out


def _bun_prims(at: np.ndarray, s: float, size: float = 1.0) -> Tuple[List[Prim], List[np.ndarray]]:
    """A bun: a coil of hair wound round itself, with the turns showing. `size` 1 is a bun of the
    whole head of hair at the crown; a low knot at the nape is a little larger.

    The coil climbs the dome of the bun as it winds in. Wound the other way -- the outer turn
    standing furthest from the head -- it was a dish, and from behind it read as a button."""
    R = np.array([0.032, 0.027, 0.030]) * s * size
    prims = [sdf.ellipsoid(at, R, k=0.006 * s)]
    lines = []
    turns = 2.4
    pts = []
    for i in range(60):
        u = i / 59.0
        a = 2.0 * math.pi * turns * u
        r = (0.029 - 0.017 * u) * s * size
        y = 0.80 * R[1] * math.sqrt(max(0.0, 1.0 - (r / R[0]) ** 2))
        pts.append(at + np.array([r * math.cos(a), y, r * math.sin(a) * 0.95]))
    pts = np.array(pts)
    prims.append(sdf.tube_path(pts, 0.0090 * s * size, density=2, max_spheres=220, k=0.004 * s))
    lines.append(pts)
    return prims, lines


def _curled(pts: np.ndarray, head, amp: float, period: float, phase: float) -> np.ndarray:
    """A lock's centreline wound into a helix round itself: the curl comes in over the first
    centimetre from the root, so it grows out of the scalp rather than standing off it in a coil."""
    if len(pts) < 3:
        return pts
    seg = np.diff(pts, axis=0)
    tang = _unit_rows(np.concatenate([seg, seg[-1:]], axis=0))
    out = head.gradient(pts)
    n = _unit_rows(out - tang * np.sum(out * tang, axis=1, keepdims=True))
    b = np.cross(tang, n)
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(seg, axis=1))])
    a = amp * np.clip(arc / 0.010, 0.0, 1.0)
    th = phase + 2.0 * math.pi * arc / max(period, 1e-4)
    # outward more than in: a curl lying on the scalp is pushed off it, not into it
    return pts + n * (a * (0.35 + 0.65 * np.cos(th)))[:, None] + b * (a * np.sin(th))[:, None]


def _tail_prims(g: "Groom", sink: np.ndarray, head, body, s: float, rng) -> Tuple[List[Prim], List[np.ndarray]]:
    """A tail tied high at the back of the head: a tie round the gathered hair, and the locks
    hanging from it down the back, spreading a little as they fall and curling if the style does."""
    prims: List[Prim] = []
    lines: List[np.ndarray] = []
    out = head.gradient(sink[None])[0]
    tie = sink + out * 0.012 * s
    prims.append(sdf.torus(tie, 0.0105 * s, 0.0036 * s, axis=out, k=0.002 * s))
    prims.append(sdf.ellipsoid(tie - out * 0.004 * s, [0.016 * s, 0.013 * s, 0.017 * s], k=0.006 * s))
    # the body of the tail: a full mass from the tie, swelling below it and tapering to the ends
    centre = comb(head, tie + out * 0.010 * s, lambda P: np.tile(np.array([0.0, 0.30, -1.0]), (len(P), 1)),
                  g.tail_len * s, lambda u: 0.020 * s, release_z=1e9, s=s, body=body, step=0.005,
                  clear=HANG_CLEAR * s + 0.010 * s)
    if len(centre) >= 4:
        u = np.linspace(0.0, 1.0, len(centre))
        radii = (0.012 + 0.010 * np.sin(np.pi * np.clip(u * 1.6, 0.0, 1.0)) * (1.0 - 0.3 * u) - 0.006 * u ** 2) * s
        prims.append(sdf.tube_path(centre, radii, density=2, max_spheres=160, k=0.006 * s))
        lines.append(centre)
        # and the locks lying over it, so it reads as hair and not a sleeve
        seg = np.diff(centre, axis=0)
        tang = _unit_rows(np.concatenate([seg, seg[-1:]], axis=0))
        side = _unit_rows(np.cross(tang, np.array([0.0, 0.0, 1.0])) + 1e-9)
        back = _unit_rows(np.cross(side, tang))
        for i in range(16):
            ang = 2.0 * math.pi * i / 16.0 + rng.uniform(-0.2, 0.2)
            spread = rng.uniform(0.7, 1.0)
            off = (np.cos(ang) * side + np.sin(ang) * back) * (radii[:, None] * spread)
            end = int(len(centre) * rng.uniform(0.75, 1.0))
            pts = (centre + off)[:max(end, 3)]
            if g.curl > 0.0:
                pts = _curled(pts, head, g.curl * s, g.curl_period * s, rng.uniform(0.0, 2.0 * math.pi))
            lines.append(pts)
            prims.append(_lock_prim(pts, g.radius * s * rng.uniform(0.8, 1.1), s, g.taper))
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

    def cov_all(P):
        return bodylib.scalp_field(P, skel, hs, g.front, g.sides, g.back, g.recede)

    if g.strip > 0.0:
        # shaved at the sides and the back: a shadow of hair over the whole scalp, and the length
        # kept on a strip over the top
        def cov(P):
            return np.minimum(cov_all(P), g.strip * s - np.abs(P[:, 0]))
    else:
        cov = cov_all
    sc = Scene()
    sc.union(scalp_shell(head, cov, g.base * s, s))
    if g.strip > 0.0:
        sc.union(scalp_shell(head, cov_all, 0.0016 * s, s, t_min=0.0008 * s))
    flow = flow_field(g, L)
    sink = _sink(g, L)
    sinks = _sinks(g, L)
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

        def stop(q, u):
            if any(np.linalg.norm(q - k_) < 0.018 * s for k_ in sinks):
                return True
            if q[2] < release_z:
                return False
            return float(cov(q[None])[0]) < -g.spill * s
        pts = comb(head, _onto(head, p0[None], off0)[0], flow, length, off_fn, release_z, s,
                   body=body, twist=twist, stop_fn=stop, clear=HANG_CLEAR * s)
        if len(pts) < 3:
            continue
        if g.curl > 0.0:
            pts = _curled(pts, head, g.curl * s * rng.uniform(0.8, 1.2), g.curl_period * s * rng.uniform(0.85, 1.15),
                          rng.uniform(0.0, 2.0 * math.pi))
        locks.append(pts)
        sc.union(_lock_prim(pts, r0, s, g.taper), k=g.blend * s)
    hang = L["nape_z"]
    if g.extra == "tail" and sink is not None:
        prims, lines = _tail_prims(g, sink, head, body, s, rng)
        for pr in prims:
            sc.union(pr, k=g.blend * s)
        locks += lines
    if g.extra == "braid" and sink is not None:
        prims, lines = _braid_prims(sink, body, head, L, s)
        for pr in prims:
            sc.union(pr, k=0.004 * s)
        locks += lines
    if g.extra == "twin_braids":
        # two braids from behind the ears, let fall forward over the shoulders
        neck = float(skel.J["Neck"][2])
        for sx, k_ in zip((1.0, -1.0), sinks):
            # down the side of the neck close in, then forward over the top of the shoulder and
            # down in front of it, standing off a woman's bust as well as a man's chest (the hair
            # is not fitted to either). Held 3 cm off the body like loose hair, and led out to the
            # shoulder first, each braid looped wide of the jaw below the ear (triage 29): it lies
            # against the neck, 1.2 cm off it, and comes forward only over the shoulder.
            over = [k_ + np.array([-0.002 * sx, -0.010, -0.045]) * s,
                    np.array([0.050 * sx * s, -0.026 * s, neck + 0.004 * s]),
                    np.array([0.066 * sx * s, -0.066 * s, neck - 0.070 * s]),
                    np.array([0.070 * sx * s, -0.110 * s, neck - 0.150 * s])]
            # (over the clothes below the collar: a bodice's laced leather stands 2 cm off)
            def clear(C, neck=neck):
                return 0.012 + (HANG_CLEAR - 0.012) * np.clip((neck + 0.010 * s - C[:, 2]) / (0.040 * s), 0.0, 1.0)
            prims, lines = _braid_prims(k_, body, head, L, s, width=0.86, through=over, clear=clear)
            for pr in prims:
                sc.union(pr, k=0.004 * s)
            locks += lines
    if g.extra in ("bun", "chignon") and sink is not None:
        prims, lines = _bun_prims(sink, s, size=1.0 if g.extra == "bun" else 1.18)
        for pr in prims:
            sc.union(pr, k=0.005 * s)
        locks += lines
    if g.extra == "crown":
        # the band of plait over the top, and the rest drawn back into a small low knot
        arc, out = _crown_arc(head, L, s, g.base * s + 0.0070 * s)
        prims, lines = _plait(arc, s, width=0.74, taper_to=0.80, out_hint=out)
        for pr in prims:
            sc.union(pr, k=0.004 * s)
        locks += lines
        if sink is not None:
            prims, lines = _bun_prims(sink, s, size=0.95)
            for pr in prims:
                sc.union(pr, k=0.005 * s)
            locks += lines
    hangs = g.release > 0 or g.extra in ("braid", "twin_braids", "tail")
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
    blend: float = 0.0035       # how far the locks melt into each other and the shell
    mass: float = 0.0           # the body of a full beard under the chin (radius, metres at 1.78 m)
    clumps: int = 0             # short clumps shingled over the beard and its mass, never hanging
    clump_len: Tuple[float, float] = (0.014, 0.024)
    clump_r: float = 0.0045


class _MinField:
    """The nearer of two fields, with a gradient: the face and a beard's mass, for combing clumps
    over both."""

    def __init__(self, a, b, eps: float = 0.0010):
        self.a, self.b, self.eps = a, b, eps

    def eval(self, P: np.ndarray) -> np.ndarray:
        P = np.asarray(P, float)
        return np.minimum(self.a.eval(P), self.b.eval(P))

    def gradient(self, P: np.ndarray) -> np.ndarray:
        P = np.asarray(P, float)
        g = np.empty_like(P)
        for i in range(3):
            o = np.zeros(3)
            o[i] = self.eps
            g[:, i] = (self.eval(P + o) - self.eval(P - o)) / (2.0 * self.eps)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


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
    elif st.region == "chops":
        # down the cheeks from the sideburns to the jaw's angle and along it, the chin and the lip bare
        def cov(P):
            c = bodylib.beard_field(P, None, skel, hs, moustache=False)
            return np.minimum(c, np.abs(P[:, 0]) - 0.030 * s)
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
    mass_sc = None
    if st.mass > 0:
        # A full beard is a mass before it is hair: without one the locks hung from the jaw as
        # separate strands, like icicles. The mass fills out under the chin, follows the jaw back
        # towards the ears, and rounds off a hand below the chin; the hair lies on it in clumps.
        m = st.mass * s
        top = np.array([0.0, L["face_y"] + 0.016 * s, L["chin_z"] + 0.006 * s])
        low = np.array([0.0, L["face_y"] + 0.022 * s, L["chin_z"] - max(st.hang * 0.80, 0.02) * s])
        gon = L["gonion"]

        def mass_prims():
            out = [sdf.ellipsoid(top, [m * 1.60, m * 0.80, m * 0.80], k=0.010 * s)]
            for sx in (1, -1):
                # two lobes side by side, so the beard is broad across and shallow front to back
                dx = np.array([sx * m * 0.45, 0.0, 0.0])
                out.append(sdf.round_cone(top + dx, low + dx * 0.25, m * 0.80, m * 0.30, k=0.012 * s))
                # and along the jaw to its angle, so the beard is one piece with the cheeks
                g = gon * np.array([sx, 1.0, 1.0]) + np.array([0.0, -0.004 * s, -0.004 * s])
                out.append(sdf.round_cone(top + dx * 1.2, g, m * 0.62, m * 0.34, k=0.012 * s))
            return out
        for pr in mass_prims():
            sc.union(pr, k=pr.k)
        mass_sc = Scene()
        for pr in mass_prims():
            mass_sc.union(pr, k=pr.k)
    if st.clumps > 0:
        # The hair of a full beard: short clumps laid over the face's beard and the mass, each
        # following the jaw down and in to the chin and tucking in at its tip, so they overlap
        # like shingles and nothing hangs free. Long locks off the chin read as tails.
        surf = _MinField(head, mass_sc) if mass_sc is not None else head
        n_face = st.clumps if mass_sc is None else int(st.clumps * 0.55)
        cand = _face_points(head, L, rng, n_face * 14)
        cand = cand[cov(cand) > 0.002 * s]
        # none from the moustache or beside the mouth: combed down, they hung over the lips
        mouth = (np.abs(cand[:, 0]) < L["mouth_w"] * 1.35) & (cand[:, 2] > L["mouth_z"] - 0.014 * s)
        cand = cand[~mouth]
        if len(cand) > n_face:
            cand = cand[rng.choice(len(cand), n_face, replace=False)]
        seeds_all = [cand]
        if mass_sc is not None:
            n_mass = st.clumps - n_face
            # round the mass from the front and the sides, below the mouth
            c0 = np.array([0.0, L["face_y"] + 0.018 * s, L["chin_z"] - 0.010 * s])
            d = _unit_rows(rng.normal(0.0, 1.0, (n_mass * 8, 3)) * np.array([1.0, 0.5, 0.9])
                           + np.array([0.0, -0.9, -0.2]))
            mc = _onto(surf, c0 + d * 0.06 * s, 0.0, iters=6)
            ok = (mc[:, 2] < L["mouth_z"] - 0.010 * s) & (mc[:, 1] < c0[1] + 0.010 * s)
            mc = mc[ok & np.all(np.isfinite(mc), axis=1)]
            if len(mc) > n_mass:
                mc = mc[rng.choice(len(mc), n_mass, replace=False)]
            seeds_all.append(mc)
        for p0 in np.concatenate(seeds_all, axis=0):
            length = rng.uniform(*st.clump_len) * s
            r0 = st.clump_r * s * rng.uniform(0.8, 1.2)
            off0 = r0 * 0.9

            def off_fn(u, off0=off0):
                return off0 * (1.0 - 0.55 * u)        # the tip tucks in under the next clump
            pts = comb(surf, _onto(surf, p0[None], off0)[0], flow, length, off_fn, -1e9, s,
                       body=None, step=0.0025)
            if len(pts) < 3:
                continue
            # tapering to a point: with a lock's round end every clump at the bottom of the beard
            # ended in a blunt tip, a row of fingers
            u = np.linspace(0.0, 1.0, len(pts))
            sc.union(sdf.tube_path(pts, r0 * (1.0 - 0.88 * u ** 1.2) + 0.0005 * s, density=2, max_spheres=120),
                     k=st.blend * s)
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
        if st.mass > 0 and (p0[2] > L["mouth_z"] or abs(p0[0]) > st.mass * s * 1.3):
            # on the cheeks and the sides of the jaw a full beard lies close: a long lock from
            # there stood off the jaw like a leg
            length, r0 = rng.uniform(*st.length) * s * 0.6, r0 * 0.7
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
        sc.union(_lock_prim(pts, r0, s), k=st.blend * s)
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
    # -- the long styles most women wear (triage 22); offered to everyone ---------------------
    # long and full from a side parting, well past the shoulders and down the back
    "long_loose": Groom(base=0.0076, flow="side_part", part_x=0.022, seeds=124, length=(0.30, 0.44),
                        radius=0.0118, lift=0.0030, jitter=5.0, release=0.47, front=1.04, sides=1.10,
                        blend=0.0105, taper=0.34, target_tris=6000),
    # a full cut to the shoulder, fuller at the ends
    "shoulder": Groom(base=0.0074, flow="side_part", part_x=0.026, seeds=110, length=(0.13, 0.18),
                      radius=0.0108, lift=0.0050, jitter=8.0, release=0.50, front=1.04, sides=1.10,
                      blend=0.0095, taper=0.38, target_tris=5000),
    # parted in the middle, a braid from behind each ear let fall forward over the shoulders
    "twin_braids": Groom(base=0.0060, flow="sink", seeds=74, length=(0.08, 0.16), radius=0.0050,
                         lift=0.0, extra="twin_braids", front=1.04, sides=1.08, target_tris=5200),
    # a plait pinned over the top of the head from ear to ear, the rest combed back into a low knot
    "crown_braid": Groom(base=0.0058, flow="sink", seeds=72, length=(0.08, 0.16), radius=0.0050,
                         lift=0.0, extra="crown", front=1.04, sides=1.08, target_tris=5200),
    # combed back smooth into a low knot at the nape
    "chignon": Groom(base=0.0060, flow="sink", seeds=72, length=(0.08, 0.16), radius=0.0050,
                     lift=0.0, extra="chignon", front=1.04, sides=1.08, target_tris=4200),
    # -- more for everyone (triage 39) ---------------------------------------------------------
    # curls to the jaw, full and round: short locks wound tight, standing off the head
    "curly": Groom(base=0.0090, flow="radial", seeds=150, length=(0.06, 0.10), radius=0.0070,
                   lift=0.012, jitter=35.0, spill=0.010, blend=0.0055, curl=0.0055, curl_period=0.020,
                   release=0.52, taper=0.45, front=1.03, sides=1.06, target_tris=6000),
    # cropped curls: a close cap of tight curls, no length to them
    "cropped_curls": Groom(base=0.0070, flow="radial", seeds=130, length=(0.018, 0.028), radius=0.0050,
                           lift=0.004, jitter=40.0, blend=0.0040, curl=0.0030, curl_period=0.012,
                           target_tris=4600),
    # shaved at the sides and the back, a strip of length on top combed back
    "shaved_sides": Groom(base=0.0072, flow="back", seeds=70, length=(0.050, 0.090), radius=0.0064,
                          lift=0.0025, jitter=6.0, strip=0.038, target_tris=3600),
    # the head shaved: a shadow where the hair grows, which sits under any hood or helm
    "shaven": Groom(base=0.0014, flow="radial", seeds=0, target_tris=1600),
    # thin at the temples and cropped close, the hairline gone back
    "receding": Groom(base=0.0038, flow="radial", seeds=0, recede=1.0, target_tris=2000),
    # drawn back and tied high at the back of the head, the tail hanging to the shoulder blades
    "ponytail": Groom(base=0.0060, flow="sink", seeds=76, length=(0.08, 0.16), radius=0.0070,
                      lift=0.0, extra="tail", tail_len=0.26, blend=0.0070, taper=0.40, front=1.04,
                      sides=1.06, target_tris=5200),
}
BEARD_STYLES: Dict[str, BeardStyle] = {
    "stubble": BeardStyle(base=0.0016, target_tris=1000),
    # clumps shingled over the jaw and the chin, never hanging free: long locks read as tails
    "short_beard": BeardStyle(base=0.0088, blend=0.0030, clumps=44, clump_len=(0.014, 0.022),
                              clump_r=0.0038, target_tris=2400),
    "long_beard": BeardStyle(base=0.0100, hang=0.07, blend=0.0030, mass=0.028, clumps=84,
                             clump_len=(0.024, 0.036), clump_r=0.0044, target_tris=3600),
    "moustache": BeardStyle(base=0.0034, region="moustache", seeds=14, length=(0.022, 0.034),
                            radius=0.0030, target_tris=900),
    # -- more (triage 39) --------------------------------------------------------------------
    # between the short and the long: a full beard with some body under the chin
    "full_beard": BeardStyle(base=0.0095, hang=0.035, blend=0.0030, mass=0.022, clumps=66,
                             clump_len=(0.018, 0.028), clump_r=0.0042, target_tris=3200),
    # the chin and the lip, the cheeks bare
    "goatee": BeardStyle(base=0.0080, region="chin", blend=0.0030, clumps=26, clump_len=(0.012, 0.020),
                         clump_r=0.0036, target_tris=1600),
    # side-whiskers down to the jaw, the chin and the lip shaved
    "mutton_chops": BeardStyle(base=0.0082, region="chops", blend=0.0030, clumps=30,
                               clump_len=(0.012, 0.020), clump_r=0.0036, target_tris=1800),
    # a heavy moustache drooping over the lip and past the corners of the mouth
    "walrus": BeardStyle(base=0.0050, region="moustache", seeds=26, length=(0.030, 0.044),
                         radius=0.0040, blend=0.0040, target_tris=1300),
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
                          bounds=zbox(skel, 0.50 * skel.props.height, 0.96 * skel.props.height, xy=0.72)))
    # the skirt of the coat: straight sides, no flare, so it reads as a column -- one that
    # clears the hips (`_covered`), which the fixed column did not by 1.5 cm a side. It clears
    # the body by 1.6 cm, measured down the thigh as well as at the hip and the hem: cleared by
    # 1 cm at those alone, the trousers under it came through its sides in blue spots at the
    # thigh's widest, between the stations, and in a strip down the free leg in the Idle
    st = _covered(body, [
        (hip + 0.16 * s, 0.150 * s, 0.114 * s, 0.006 * s),
        (hip - 0.04 * s, 0.162 * s, 0.122 * s, 0.004 * s),
        (hip - 0.14 * s, 0.164 * s, 0.124 * s, 0.003 * s),
        (hip - 0.25 * s, 0.165 * s, 0.125 * s, 0.003 * s),
        (z_hem + 0.10 * s, 0.166 * s, 0.126 * s, 0.002 * s),
        (z_hem, 0.164 * s, 0.124 * s, 0.0),
    ], gap=0.016 * s, hang_from=1)
    sc.union(_loft_of(st), k=0.012 * s)
    sc.union(sdf.tube_path(_ring(st[-1][1] + 0.002 * s, st[-1][2] + 0.002 * s, z_hem + 0.014 * s), 0.0064 * s),
             k=0.006 * s)
    # standing collar: a band that rises past the jaw
    sc.union(sdf.tube_path(_ring(0.074 * s, 0.066 * s, neck + 0.056 * s), 0.014 * s), k=0.010 * s)
    # the front split, so the coat has a centre line down the middle of the silhouette
    sc.subtract(sdf.box([0.0, -0.140 * s, (hip + z_hem) * 0.5],
                        [0.007 * s, 0.045 * s, (hip - z_hem) * 0.62]), k=0.005 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment("coat", sc, spacing=0.0075, target_tris=4800, material="cloth", open_below=z_hem)
    # its skirt is a skirt: weighted from the nearest leg, a stride opened it at the side and the
    # trousers showed through in patches; and it goes with the thigh nearly whole, since at 0.70
    # of it at the hip the forward thigh came through the front of the coat at the Walk's contact.
    # Wholly now, and to the shin it goes with the shins below the knee, as the robe: over the
    # trousers at the worst of the Walk, Run and Sprint, clipcheck drew 5, 28 and 30 leg vertices
    # through it at 85 % (with its floor gone), and 2, 5 and 11 like this.
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05,
                                     shin_back=0.85, shin_front=0.5)
    return g


class FieldFn:
    """Anything with `eval(P)`, from a plain function: a trim field, an offset of a field."""

    def __init__(self, fn: Callable[[np.ndarray], np.ndarray]):
        self.fn = fn

    def eval(self, P: np.ndarray) -> np.ndarray:
        return self.fn(P)


ARM_BONES = ("UpperArm.L", "LowerArm.L", "Hand.L", "UpperArm.R", "LowerArm.R", "Hand.R")


def _idle_matrices(skel: Skeleton) -> Dict[str, np.ndarray]:
    """Each bone's skinning matrix in the relaxed Idle: posed global times inverse rest."""
    from . import anim, anim_clips
    cb = anim.ClipBuilder(skel, "hang", 1.0, loop=True, grounded=False)
    cb.key(0.0, anim_clips.RELAXED)
    W = skel.fk(cb.local_pose(0.0))
    return {b: W[b] @ np.linalg.inv(skel.bones[b].rest) for b in skel.bones if b in W}


def rebind_from_idle(skel: Skeleton, V: np.ndarray, W: np.ndarray,
                     bones: Sequence[str] = rig.DEFORM_NAMES) -> np.ndarray:
    """Rest-pose positions for a part modelled round the Idle's hanging arms.

    Where a vertex should stand in the Idle is where the rest of its weights (the chest, the
    spine, the hips) carry the place it was modelled at; its rest position is that, taken back
    through the blend of all its weights' Idle matrices, arms included. Skinned in the Idle it
    lands where it was modelled; skinned in a stride it follows its share of the arm's swing."""
    M = _idle_matrices(skel)
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    blend = np.zeros((len(V), 4, 4))
    body = np.zeros((len(V), 4, 4))
    body_w = np.zeros(len(V))
    for i, b in enumerate(bones):
        if b not in M:
            continue
        w = W[:, i]
        if not np.any(w > 0):
            continue
        blend += w[:, None, None] * M[b][None]
        if b not in ARM_BONES:
            body += w[:, None, None] * M[b][None]
            body_w += w
    free = body_w < 1e-6
    body[free] = M["Chest"]
    body[~free] /= body_w[~free, None, None]
    target = np.einsum("nij,nj->ni", body, Vh)
    # a blend of two turns far apart shrinks towards singular; where it does, keep the vertex
    ok = np.abs(np.linalg.det(blend[:, :3, :3])) > 0.25
    out = np.array(Vh, copy=True)
    out[ok] = np.linalg.solve(blend[ok], target[ok][:, :, None])[:, :, 0]
    return out[:, :3]


def hanging_arm(skel: Skeleton, side: str) -> List[np.ndarray]:
    """Where the arm hangs in the relaxed Idle -- the shoulder, the elbow and the wrist -- in the
    rest frame, measured from the rest shoulder: the forge's own FK of `anim_clips.RELAXED`."""
    from . import anim, anim_clips
    cb = anim.ClipBuilder(skel, "hang", 1.0, loop=True, grounded=False)
    cb.key(0.0, anim_clips.RELAXED)
    W = skel.fk(cb.local_pose(0.0))
    sh = skel.joint_world(W, "UpperArm." + side)
    rest = np.asarray(skel.J["UpperArm." + side], float)
    return [rest + (skel.joint_world(W, n + side) - sh) for n in ("UpperArm.", "LowerArm.", "Hand.")]


def drape_field(body, skel: Skeleton, flare: float = 0.10, arm_cut_x: float = 0.25,
                arm_far: float = 0.05, hang_arms: bool = False) -> sdf.SampledField:
    """The body as cloth falls from it.

    Every horizontal section of the result is the union of the body's sections above it,
    pushed out by `flare` metres for every metre of fall -- which is the space a cloth takes
    when it is laid over the shoulders and let go. The arms below the top of the deltoid are
    left out, or the cloth would hang from an A-posed arm like a bat's wing: a cape rests on the
    point of the shoulder and falls past the arm, not from it.

    Left out means read as `arm_far` away. A short cape is let lie over the top of the arm at
    5 cm; a cloak to the knee must not be, because the flare closes any fixed distance in the
    end: at 5 cm the cloak's hem had spread out to the A-posed hands, half a metre each side.

    `hang_arms` puts the arms back as they hang in the Idle, instead of cutting the A-posed arm
    off at `arm_cut_x`: the stub of it that was left, out to the cut, ended every cloak's shoulder
    in a square corner, a coat hanger under the cloth. Laid over an arm that hangs, the cloth
    rounds over the point of the shoulder and falls down the outside of the arm."""
    s = _s(skel)
    F = np.array(body.F, copy=True)
    o, sp = body.origin, body.spacing
    xs = o[0] + np.arange(F.shape[0]) * sp
    ys = o[1] + np.arange(F.shape[1]) * sp
    zs = o[2] + np.arange(F.shape[2]) * sp
    zc = float(skel.J["UpperArm.L"][2]) + 0.030 * s
    cut = arm_cut_x if not hang_arms else float(skel.J["UpperArm.L"][0]) / s - 0.005
    arm = (np.abs(xs)[:, None] > cut * s) & (zs[None, :] < zc)
    F = np.where(arm[:, None, :], np.maximum(F, arm_far if not hang_arms else 1.0), F)
    if hang_arms:
        # the arm and a sleeve on it, and room at the hand for a robe's bell sleeve: at the arm's
        # own size the sleeves of whatever was worn under the cloak came through its sides
        radii = [0.050 * s, 0.066 * s, 0.090 * s]
        axes = (xs, ys, zs)
        for side in ("L", "R"):
            limb = sdf.chain(hanging_arm(skel, side), radii)
            # only the part of the grid near the arm: the whole of it is 20 million points
            idx = [np.nonzero((a >= limb.lo[i] - 0.10) & (a <= limb.hi[i] + 0.10))[0] for i, a in enumerate(axes)]
            if any(len(i) == 0 for i in idx):
                continue
            sl = tuple(slice(int(i[0]), int(i[-1]) + 1) for i in idx)
            X, Y, Z = np.meshgrid(xs[sl[0]], ys[sl[1]], zs[sl[2]], indexing="ij")
            d = limb.fn(np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)).reshape(X.shape)
            F[sl] = np.minimum(F[sl], d)
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
    drape = drape_field(body, skel, flare=0.10, hang_arms=True)
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
    g.rebind = True
    return g


def wrap_torso(skel: Skeleton, body) -> Garment:
    """Reedfolk: cloth wound over one shoulder and under the other arm, with a sash across
    the chest.  Nobody else in the world is asymmetric, so this reads instantly."""
    s = _s(skel)
    sc = Scene()
    neck = float(skel.J["Neck"][2])
    waist = float(skel.J["Spine"][2])
    hip = float(skel.J["UpperLeg.L"][2])

    shz_line = float(skel.J["UpperArm.L"][2])

    def diagonal(P):
        # Covered to a line that runs from the right shoulder down across the breastbone to under
        # the left arm, the left shoulder bare but for the sash. The first cut ran from the left
        # shoulder down to the right hip, and in the engine the whole left breast and the middle
        # of the chest were bare skin between the sash and the cloth: a strap, not a top.
        # (the chest joint sits below the breasts: from it the left breast was still bare, so the
        # line starts under the left armpit, a hand below the shoulder joint)
        edge = shz_line - 0.070 * s + np.clip(-P[:, 0], 0.0, 0.20 * s) * 0.60
        return 1.0 - sdf_smoothstep(edge - 0.012 * s, edge + 0.012 * s, P[:, 2])
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
    # the overlap's edge, laid on the skirt as `_covered` cut it, standing half its width proud
    g.scene.union(sdf.tube_path([_on_loft(g.stations, 0.130 * s, -0.100 * s, hip + 0.04 * s),
                                 _on_loft(g.stations, 0.114 * s, -0.118 * s, (hip + z_hem) * 0.5),
                                 _on_loft(g.stations, 0.098 * s, -0.126 * s, z_hem + 0.03 * s)],
                                [0.011 * s, 0.012 * s, 0.012 * s]), k=0.008 * s)
    g.scene.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g.target_tris = 3600
    # to mid-calf and narrow: with the shins below the knee, as the robe (clipcheck, the worst of
    # the Walk, Run and Sprint: 20, 35 and 46 leg vertices drawn through; 4, 9 and 15 like this)
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05,
                                     shin_back=0.85, shin_front=0.5)
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
    # a little more room than the long skirts: the kilt ends above the knee, so its sides are
    # the thigh's own, and in the Idle the free leg's thigh came out through the side of it
    st = _covered(body, [
        (waist - 0.01 * s, 0.132 * s, 0.100 * s, 0.0),
        (hip + 0.02 * s, 0.156 * s, 0.118 * s, 0.0),
        (z_hem + 0.05 * s, 0.180 * s, 0.138 * s, 0.0),
        (z_hem, 0.184 * s, 0.141 * s, 0.0),
    ], gap=0.014 * s)
    sc.union(_loft_of(st))
    # pleats, deeper at the back than the front, the way a kilt is actually made; laid on the
    # kilt's own surface all the way round (on a circle they only ever reached it at the sides)
    n = 14
    hz, ha, hb, _ = st[1]
    ez, ea, eb, _ = st[-1]
    for i in range(n):
        a = 2 * math.pi * i / n
        depth = 0.009 * s * (0.55 + 0.45 * math.sin(a))
        sc.subtract(sdf.tube_path([_on_ellipse(a, ha, hb, hz), _on_ellipse(a, ea, eb, ez)], depth), k=0.013 * s)
    sc.union(sdf.tube_path(_ring(ea + 0.001 * s, eb + 0.001 * s, z_hem + 0.012 * s), 0.0062 * s), k=0.006 * s)
    sc.intersect(sdf.plane([0.0, 0.0, z_hem], [0.0, 0.0, -1.0]))
    g = Garment("kilt", sc, spacing=0.0070, target_tris=3200, material="cloth", open_below=z_hem)
    # with the thighs whole: at the old 55 % at the hip and 90 % at the hem, a running thigh came
    # out through the front of the kilt and the trailing one through its back (clipcheck: 54 leg
    # vertices drawn through it at the worst of the Sprint, with its floor gone; 2 now)
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0)
    g.stations = st
    # Woven in the clan's tartan all round, the same sett as the plaid over the shoulder: the
    # kilt was the palette's plain brown with the check only on the plaid's apron beside it.
    # Across is round the waist (arc length on the hip station), along is down the leg.
    weave = tartan()
    r_hip = 0.5 * (ha + hb)

    def pattern(P, nrm):
        return weave(np.arctan2(P[:, 0], -P[:, 1]) * r_hip, P[:, 2])
    g.pattern = pattern
    return g


# The clans' tartan, half a sett from pivot to pivot (it mirrors at both ends): a rust ground,
# brown bands with a cream line through them, a dark line either side of the ground. Madder,
# walnut and undyed wool -- the palette's accent, secondary and trim, darkened as a dyed wool is.
CLAN_SETT: List[Tuple[str, float]] = [("#7e3f25", 30.0), ("#2a1d15", 4.0), ("#7e3f25", 7.0),
                                      ("#4f3d2b", 24.0), ("#d9cfb8", 3.0), ("#4f3d2b", 24.0)]


def tartan(sett: Sequence[Tuple[str, float]] = CLAN_SETT, mm: float = 0.00062,
           twill: float = 0.0034) -> Callable[[np.ndarray, np.ndarray], np.ndarray]:
    """A woven check as a function of two cloth coordinates (u across, v along, in metres): the
    warp's stripe and the weft's stripe at a point, crossed in a 2/2 twill, so where a colour
    crosses itself it is solid and where it crosses another the two mix along a fine diagonal."""
    cols = np.array([[int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)] for h, _ in sett])
    edges = np.cumsum([w * mm for _, w in sett])
    half = float(edges[-1])

    def stripe(t):
        t = np.mod(t, 2.0 * half)
        t = np.where(t > half, 2.0 * half - t, t)
        return cols[np.clip(np.searchsorted(edges, t, side="right"), 0, len(cols) - 1)]

    def fn(u, v):
        warp, weft = stripe(u), stripe(v)
        w = 0.5 + 0.30 * np.sin(2.0 * math.pi * (u + v) / twill)
        return warp * w[:, None] + weft * (1.0 - w[:, None])
    return fn


def plaid(skel: Skeleton, body) -> Garment:
    """Clans: a length of tartan over the left shoulder, pinned there, across the chest and round
    the right side under the belt in front, and down the back to behind the knee. It gives one
    high shoulder and a long diagonal -- a shape no one else in the world has.

    It was a solid loft 15 cm thick down the back and a 7 cm tube across the chest, in undyed
    wool the palette left pale and plain: a thick white blanket, and over a shirt a padded
    costume. Now it is one sheet of cloth a centimetre thick, woven in the clan's tartan
    (`tartan`, baked into the texture and not tinted by the game) and held at the shoulder by a
    ring brooch. The sash lies on the body, as a band pulled from the shoulder to the belted hip
    does, and slips in under the belt; the back hangs from the shoulder blades on the drape of
    the body, as the cloaks do, in folds that deepen towards a hem behind the knee."""
    s = _s(skel)
    J = skel.J
    knee = float(J["LowerLeg.L"][2])
    waist = float(J["Spine"][2])
    top = shoulder_line(body, skel)
    drape = drape_field(body, skel, flare=0.035, arm_far=1.0)

    def lies(P):
        # 1 on the front, where the sash lies on the body; 0 behind, where the cloth hangs
        return _ss((0.020 * s - P[:, 1]) / (0.040 * s))

    fld = FieldFn(lambda P: lies(P) * body.eval(P) + (1.0 - lies(P)) * drape.eval(P))
    z_hem = knee + 0.05 * s
    gap, thick = 0.014 * s, 0.009 * s
    # the sash's centre line in the front view, from the top of the left shoulder across the chest
    # and on round the right side, where it meets the top of the back
    sa = np.array([0.125 * s, top + 0.015 * s])
    sb = np.array([-0.26 * s, waist - 0.035 * s])
    sab = sb - sa
    sl2 = float(sab @ sab)
    s_dir = sab / math.sqrt(sl2)
    s_perp = np.array([-s_dir[1], s_dir[0]])
    # the back panel's top edge falls from the left shoulder to the right side at the waist
    ex0, ez0 = 0.15 * s, top + 0.020 * s
    ex1, ez1 = -0.20 * s, waist + 0.030 * s
    fold_k = 2.0 * math.pi / (0.075 * s)

    def sash_t(P):
        return np.clip(((P[:, 0] - sa[0]) * sab[0] + (P[:, 2] - sa[1]) * sab[1]) / sl2, 0.0, 1.0)

    def sash_dist(P):
        t = sash_t(P)
        return np.hypot(P[:, 0] - (sa[0] + t * sab[0]), P[:, 2] - (sa[1] + t * sab[1]))

    def hem_at(P):
        return z_hem + 0.009 * s * np.sin(P[:, 0] * fold_k + 0.6 + math.pi)

    def region(P):
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        # a band 14 cm wide, narrowing where it gathers at the side
        half_w = (0.072 - 0.016 * sash_t(P)) * s
        front = (1.0 - _ss((sash_dist(P) - half_w) / (0.006 * s))) * _ss((0.030 * s - y) / (0.012 * s))
        edge = ez1 + (x - ex1) * (ez0 - ez1) / (ex0 - ex1)
        back = (_ss((edge - z) / (0.006 * s)) * _ss((z - hem_at(P)) / (0.006 * s))
                * _ss((y + 0.030 * s) / (0.012 * s)) * _ss((0.215 * s - np.abs(x - 0.010 * s)) / (0.008 * s)))
        return np.maximum(front, back)

    def relief(P):
        # the back falls in folds that deepen towards the hem
        fall = np.clip((top - P[:, 2]) / max(top - z_hem, 1e-3), 0.0, 1.0) ** 0.7
        folds = (0.70 * (0.5 + 0.5 * np.sin(P[:, 0] * fold_k + 0.6))
                 + 0.30 * (0.5 + 0.5 * np.sin(P[:, 0] * fold_k * 2.3 + 1.9)))
        behind = 1.0 - lies(P)
        # the sash: pleats along its length where it is gathered, and its lower end let in under
        # the belt (which stands 13-22 mm off the body) so the belt passes over it
        across = (P[:, 0] - sa[0]) * s_perp[0] + (P[:, 2] - sa[1]) * s_perp[1]
        pleats = 0.5 + 0.5 * np.sin(across * 2.0 * math.pi / (0.032 * s))
        t = sash_t(P)
        tuck = _ss((t - 0.55) / 0.30)
        return (0.018 * s * fall * folds * behind
                + (0.004 * s * pleats * (0.4 + 0.6 * t) - 0.006 * s * tuck) * (1.0 - behind))

    shell, trim = draped_shell(fld, region, thick, gap,
                               zbox(skel, z_hem - 0.05 * s, top + 0.08 * s, xy=0.36, ymin=-0.30, ymax=0.36),
                               relief=relief)
    sc = Scene()
    sc.union(shell)
    g = Garment("plaid", sc, spacing=0.0055, smooth=4, target_tris=3200, material="cloth",
                trim=trim, trim_depth=0.0)
    g.weight_fn = _cloak_weights(skel, False)
    g.double_sided = True
    weave = tartan()

    def pattern(P, nrm):
        # the cloth's own directions: along and across the sash in front, down and across the back
        front = (P[:, 1] < -0.010 * s) & (P[:, 2] < top - 0.020 * s)
        u = np.where(front, P[:, 0] * s_perp[0] + P[:, 2] * s_perp[1], P[:, 0])
        v = np.where(front, P[:, 0] * s_dir[0] + P[:, 2] * s_dir[1], P[:, 2])
        return weave(u, v)
    g.pattern = pattern
    # the brooch: a ring with its pin across, on the front of the sash below the shoulder
    bz = top - 0.045 * s
    bx = 0.110 * s
    ys = np.linspace(0.05 * s, -0.25 * s, 301)
    Pz = np.stack([np.full_like(ys, bx), ys, np.full_like(ys, bz)], axis=1)
    outer = gap + thick
    i = int(np.argmax(fld.eval(Pz) > outer))
    by = float(ys[max(i, 0)])
    pin = Scene()
    c = np.array([bx, by - 0.004 * s, bz])
    pin.union(sdf.torus(c, 0.019 * s, 0.0042 * s, axis=np.array([0.0, 1.0, 0.0])))
    pin.union(sdf.tube_path([c + np.array([-0.026 * s, -0.003 * s, 0.010 * s]),
                             c + np.array([0.026 * s, -0.003 * s, -0.010 * s])], 0.0026 * s), k=0.002 * s)
    pin.union(sdf.ellipsoid(c + np.array([0.0, 0.002 * s, 0.0]), [0.011 * s, 0.004 * s, 0.011 * s]), k=0.003 * s)
    brooch = Garment("plaid_brooch", pin, spacing=0.0022, smooth=2, target_tris=500, material="iron")
    brooch.weight_fn = _cloak_weights(skel, False)
    g.layers.append(brooch)
    return g


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


# --------------------------------------------------------------------------------------
# women's cuts (triage 22)
#
# A woman in a man's tunic fitted to her by a morph is still a man's outline. What says a woman
# at the distance the player stands is the line: a bodice that follows the body to a drawn-in
# waist and a skirt that falls from it, full, to the ankle. Each people keeps its own shape in
# them -- the Vale belted, the Clans' plaid over a bodice and a long skirt, the Lakefolk's coat
# over a skirt instead of trousers, the Woodfolk's long belted tunic over banded legs. They are
# built on the default body like everything else and fitted to hers (ALWAYS_FITTED), and a man
# may wear them too.
# --------------------------------------------------------------------------------------

def _long_skirt_weights(skel: Skeleton):
    """To the ankle it goes with the shins below the knee, as the robe does."""
    return _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05, shin_back=0.85, shin_front=0.5)


def _bodice_shell(skel: Skeleton, body, *, hem: float, sleeves: float, collar: float, waist: float,
                  thickness: float, gap: float, top: float = 0.90) -> Prim:
    """The top of a gown: close over the body to a waist drawn in by `waist` metres, with a
    neckline `collar` from the base of the neck (negative, lower: a scooped neck)."""
    s = _s(skel)
    reg = torso_region(skel, top=top, hem=hem, sleeves=sleeves, collar=collar)
    return offset_shell(body, reg, thickness * s, gap=gap * s,
                        relief=garment_edges(skel, collar_z=float(skel.J["Neck"][2]) + collar * s,
                                             sleeve_end=min(sleeves, 0.98) if sleeves > 0.01 else None,
                                             waist=waist, edge=0.0040),
                        bounds=zbox(skel, (hem - 0.02) * skel.props.height, 0.93 * skel.props.height,
                                    xy=0.74 if sleeves > 0.6 else 0.55))


def kirtle(skel: Skeleton, body) -> Garment:
    """The Vale's gown: a fitted bodice with a scooped neck, long close sleeves, the waist drawn in
    and a full skirt falling from it to the ankle. A belt or a girdle goes over it at the waist."""
    s = _s(skel)
    g = skirt(skel, body, hem=0.065, flare=1.35, name="kirtle", gap=0.010, folds=13)
    g.scene.union(_bodice_shell(skel, body, hem=0.56, sleeves=0.96, collar=-0.030, waist=0.014,
                                thickness=0.007, gap=0.003), k=0.012 * s)
    g.target_tris = 5600
    g.weight_adjust = _long_skirt_weights(skel)
    return g


def long_skirt(skel: Skeleton, body) -> Garment:
    """A full skirt to the ankle, worn over a shirt or under a coat: the Clans' under the plaid,
    the Lakefolk's under the long coat. It clears the body by the thickness of a shirt's hem."""
    g = skirt(skel, body, hem=0.065, flare=1.25, name="long_skirt", gap=0.016, folds=12)
    g.target_tris = 3800
    g.weight_adjust = _long_skirt_weights(skel)
    return g


def fitted_tunic(skel: Skeleton, body) -> Garment:
    """A long tunic cut to the body: close to a drawn waist, then a flared skirt to the knee, long
    sleeves. Over banded legs or trousers; the Woodfolk's and the Vale's working woman's."""
    s = _s(skel)
    knee = float(skel.J["LowerLeg.L"][2])
    hem = (knee - 0.03 * s) / skel.props.height
    g = skirt(skel, body, hem=hem, flare=0.95, name="fitted_tunic", gap=0.010, folds=11)
    g.scene.union(_bodice_shell(skel, body, hem=0.56, sleeves=0.90, collar=-0.012, waist=0.016,
                                thickness=0.008, gap=0.003), k=0.012 * s)
    g.target_tris = 5000
    # to just below the knee, like the kilt it clears the thighs whole
    g.weight_adjust = _skirt_weights(skel, keep_hip=1.0, keep_knee=1.0, blend=0.05)
    return g


def bodice(skel: Skeleton, body) -> Garment:
    """The Clans' woman's top: a linen shirt with long sleeves under a laced leather bodice that
    holds her from the hips to under the arms, with straps over the shoulders and a lacing down
    the front. The shirt is the part (tinted as cloth); the bodice is its leather layer."""
    s = _s(skel)
    neck = float(skel.J["Neck"][2])
    chest = float(skel.J["Chest"][2])
    waist = float(skel.J["Spine"][2])
    hip = float(skel.J["UpperLeg.L"][2])
    # the shirt: the ordinary shirt's cut with a wider neck and longer sleeves
    shirt_sc = Scene()
    shirt_sc.union(offset_shell(body, torso_region(skel, top=0.90, hem=0.52, sleeves=0.90, collar=-0.012),
                                0.007 * s, gap=0.003 * s,
                                relief=garment_edges(skel, hem_z=0.52 * skel.props.height,
                                                     collar_z=neck - 0.012 * s, sleeve_end=0.90,
                                                     waist=0.006, edge=0.0035),
                                bounds=zbox(skel, 0.50 * skel.props.height, 0.92 * skel.props.height, xy=0.70)))
    main = Garment("bodice", shirt_sc, spacing=0.0070, target_tris=3600, material="cloth")
    # the bodice: from the top of the hips to the top of the chest in front, higher under the
    # arms, never on them; two straps over the shoulders
    arms = _arm_exclusion(skel, 0.075, start=0.020)
    top_front = chest + 0.085 * s

    def body_band(P):
        # the top edge dips in a shallow scoop in front and rises under the arms and behind
        side = np.clip(np.abs(P[:, 0]) / (0.12 * s), 0.0, 1.0)
        behind = np.clip(P[:, 1] / (0.08 * s), 0.0, 1.0)
        top = top_front - 0.018 * s * (1.0 - side) ** 2 + 0.020 * s * np.maximum(side, behind)
        return (sdf_smoothstep(hip - 0.010 * s, hip + 0.004 * s, P[:, 2]) *
                (1.0 - sdf_smoothstep(top - 0.004 * s, top + 0.004 * s, P[:, 2])))

    def straps(P):
        ax = np.abs(P[:, 0])
        across = sdf_smoothstep(0.052 * s, 0.058 * s, ax) * (1.0 - sdf_smoothstep(0.090 * s, 0.096 * s, ax))
        return across * sdf_smoothstep(top_front - 0.02 * s, top_front, P[:, 2]) * \
            (1.0 - sdf_smoothstep(neck + 0.050 * s, neck + 0.060 * s, P[:, 2]))
    reg = region_and(region_or(body_band, straps), lambda P: 1.0 - arms(P))
    lace = Scene()
    lace.union(offset_shell(body, reg, 0.006 * s, gap=0.013 * s,
                            relief=garment_edges(skel, waist=0.006, edge=0.0),
                            bounds=zbox(skel, hip - 0.03 * s, neck + 0.08 * s, xy=0.30)))
    # the lacing: a cord zig-zagging between two rows of eyelets down the front
    front = [_surface_point(body, 0.020 * s, 0.0, z) for z in np.linspace(top_front - 0.02 * s, waist - 0.02 * s, 7)]
    pts = []
    for i, p in enumerate(front):
        pts.append(p + np.array([(0.012 if i % 2 == 0 else -0.012) * s, -0.002 * s, 0.0]))
    lace.union(sdf.tube_path(pts, 0.0022 * s), k=0.002 * s)
    main.layers = [Garment("bodice_laced", lace, spacing=0.0045, smooth=3, target_tris=2400, material="leather")]
    return main


def _shawl_weights(skel: Skeleton) -> Callable[[np.ndarray], np.ndarray]:
    """A cape's weights, and the long ends below the breast going with the spine as the gown
    under them does: on the chest alone they stood still while the waist turned under them."""
    cape = _cape_weights(skel)
    bones = list(rig.DEFORM_NAMES)
    s = _s(skel)
    ci, si = bones.index("Chest"), bones.index("Spine")
    chest = float(skel.J["Chest"][2])

    def fn(V):
        W = cape(V)
        low = 0.6 * np.clip((chest - V[:, 2]) / (0.14 * s), 0.0, 1.0)
        take = W[:, ci] * low
        W[:, ci] -= take
        W[:, si] += take
        return W
    return fn


def shawl(skel: Skeleton, body) -> Garment:
    """A shawl: a big square of wool folded to a triangle and laid over the shoulders, its point
    low behind to the small of the back, falling over the arms to above the elbow, and its two
    ends brought round in front, crossed and knotted on the breast, and let hang to the hip.

    The first cut ended its fronts in a V under the breast and its sides at the top of the arm,
    and in the engine it read as a short cape (triage 29): what says a shawl is the knot and the
    ends hanging from it, and the length of the point behind."""
    s = _s(skel)
    sc = Scene()
    neck = float(skel.J["Neck"][2])
    drape = drape_field(body, skel, flare=0.05, hang_arms=True)   # it lies closer than a cape
    sh = shoulder_line(body, skel)
    top = sh + 0.040 * s
    n_folds = 9
    knot_z = neck - 0.215 * s                 # on the breastbone, between the breasts
    end_z = neck - 0.470 * s                  # the ends hang to the top of the hip

    def hem(P):
        a = _around(P)                       # 0 in front, pi behind
        back = np.clip((a - 0.9) / (math.pi - 0.9), 0.0, 1.0)
        # over the arms to above the elbow, and a point behind to the small of the back
        z = neck - 0.215 * s - 0.300 * s * back ** 1.1 - 0.040 * s * np.sin(np.clip(a, 0.0, math.pi)) ** 2
        return z + 0.005 * s * np.sin(n_folds * a)

    def ends(P):
        """The two ends in front: each comes down from its shoulder across to the knot and hangs
        on the other side of it, a little splayed, narrowing to a rounded tip."""
        x, z = P[:, 0], P[:, 2]
        out = np.zeros(len(P))
        above = z >= knot_z
        for sx in (1.0, -1.0):
            # from the shoulder (x 10 cm out, at the top) across to just past the middle at the knot
            u = np.clip((top - z) / max(top - knot_z, 1e-6), 0.0, 1.0)
            xc_hi = sx * (0.105 * s * (1.0 - u) - 0.010 * s * u)
            w_hi = (0.150 - 0.075 * u) * s
            # below the knot, hanging: from 1 cm across to 4.5 cm across at the tip
            v = np.clip((knot_z - z) / max(knot_z - end_z, 1e-6), 0.0, 1.0)
            xc_lo = -sx * (0.022 + 0.030 * v) * s
            w_lo = (0.070 - 0.016 * v) * s
            xc = np.where(above, xc_hi, xc_lo)
            w = np.where(above, w_hi, w_lo)
            band = 1.0 - np.clip((np.abs(x - xc) - 0.5 * w) / (0.004 * s), 0.0, 1.0)
            # a rounded tip: the band narrows over its last 3 cm
            tip = np.clip((z - end_z) / (0.030 * s), 0.0, 1.0)
            band = band * (1.0 - np.clip((np.abs(x - xc) - 0.5 * w * np.sqrt(tip)) / (0.004 * s), 0.0, 1.0) * (tip < 1.0))
            out = np.maximum(out, band * (z > end_z))
        return out

    def region(P):
        a = _around(P)
        r = np.hypot(P[:, 0], P[:, 1] - 0.012 * s)
        below_top = np.clip((top - P[:, 2]) / (0.006 * s), 0.0, 1.0)
        neck_hole = np.clip((r - 0.084 * s) / (0.006 * s), 0.0, 1.0)
        # Behind, it lies up against the nape and ends at a level edge: cut round at 8.4 cm there,
        # the cut grazed the cloth over the back of the neck and left it ragged (as every tunic's
        # neckline was, torso_region).
        behind = np.clip((P[:, 1] - 0.012 * s) / np.maximum(r, 1e-6), 0.0, 1.0)
        nape = 1.0 - np.clip((P[:, 2] - (neck + 0.012 * s)) / (0.006 * s), 0.0, 1.0) * (r < 0.115 * s)
        neck_hole = neck_hole * (1.0 - behind) + nape * behind
        # behind and over the arms the shawl down to its hem; in front only its two ends
        front = np.clip((1.25 - a) / 0.35, 0.0, 1.0) * (P[:, 1] < -0.02 * s)
        back = np.clip((P[:, 2] - hem(P)) / (0.006 * s), 0.0, 1.0)
        return below_top * neck_hole * ((1.0 - front) * back + front * ends(P))

    def folds(P):
        a = _around(P)
        depth = np.clip((neck - 0.010 * s - P[:, 2]) / (0.22 * s), 0.0, 1.0)
        # the ends lie over each other at the knot and a little off the breast below it
        lift = 0.010 * s * np.exp(-0.5 * ((P[:, 2] - knot_z) / (0.03 * s)) ** 2) * (np.abs(P[:, 0]) < 0.05 * s)
        # and it stands a little off the point of each shoulder, which the arm's hang lifts under
        # it (the gown's shoulder came through there in the Idle)
        for side in ("L", "R"):
            lift = lift + 0.009 * s * np.exp(-0.5 * np.sum(((P - skel.J["UpperArm.%s" % side]) / (0.060 * s)) ** 2, axis=1))
        return 0.012 * s * depth * (0.5 + 0.5 * np.sin(n_folds * a + 0.3)) + lift
    shell, trim = draped_shell(drape, region, 0.009 * s, 0.006 * s,
                               zbox(skel, end_z - 0.03 * s, top + 0.02 * s, xy=0.42, ymin=-0.30, ymax=0.30),
                               relief=folds)
    sc.union(shell)
    # the knot: the two ends tied on the breastbone, a fist of wool laid on the cloth
    k = _surface_point(drape, 0.020 * s, 0.0, knot_z)
    sc.union(sdf.ellipsoid(k + np.array([0.0, -0.008 * s, 0.002 * s]), [0.024 * s, 0.014 * s, 0.020 * s]), k=0.006 * s)
    sc.union(sdf.ellipsoid(k + np.array([0.010 * s, -0.012 * s, -0.004 * s]), [0.012 * s, 0.010 * s, 0.014 * s]), k=0.004 * s)
    g = Garment("shawl", sc, spacing=0.0045, smooth=4, target_tris=3400, material="cloth",
                trim=trim, trim_depth=0.0)
    g.weight_fn = _shawl_weights(skel)
    g.double_sided = True
    g.rebind = True
    return g


CLOTHING_BUILDERS: Dict[str, Callable[[Skeleton, Scene], Garment]] = {
    "tunic": lambda s, b: tunic(s, b),
    "shirt": shirt,
    "trousers": trousers,
    "skirt": lambda s, b: skirt(s, b),
    "dress": dress,
    "robe": robe,
    "cloak": lambda s, b: cloak(s, b, hood_down=True),
    "hooded_cloak": lambda s, b: cloak(s, b, hooded=True),
    "hood": hood,
    "boots": lambda s, b: boots(s, b),
    "shoes": shoes,
    "gloves": gloves,
    "belt": lambda s, b: belt(s, b),
    "belt_knife": belt_knife,
    "sash": sash,
    "cord_beads": cord_beads,
    "belt_satchel": belt_satchel,
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
    "torn_cloak": lambda s, b: cloak(s, b, hooded=False, hem=0.38, ragged=13, name="torn_cloak", hood_down=True),
    # women's cuts (triage 22)
    "kirtle": kirtle,
    "long_skirt": long_skirt,
    "fitted_tunic": fitted_tunic,
    "bodice": bodice,
    "shawl": shawl,
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
    # primary / secondary garment colours, the leather and the metal each culture uses. Period
    # dyes, low in saturation and varied in value, so the clothes sit in the painted world:
    # madder, woad, weld, undyed wool, oak-gall browns and lichen greens.
    "vale": {"primary": "#8f7a5a", "secondary": "#6a6b52", "accent": "#8c4a3e",
           "leather": "#5e4632", "metal": "#7c7e7e", "trim": "#a8925c",
           "note": "weld-yellow and oak-brown wool, lichen hose; the accent is the family's madder door"},
    "lakefolk": {"primary": "#c6bca8", "secondary": "#5b6570", "accent": "#8f7446",
               "leather": "#4a4239", "metal": "#8f7446", "trim": "#5d7080",
               "note": "undyed wool and woad slate, dull brass fittings"},
    "reedfolk": {"primary": "#4f5a69", "secondary": "#7a5a4c", "accent": "#a8804a",
               "leather": "#54452f", "metal": "#7d7a70", "trim": "#b0a070",
               "note": "woad blue-grey and madder brown, the marsh's own dyes"},
    "clans": {"primary": "#c2b8a0", "secondary": "#5e4c3a", "accent": "#7c4034",
            "leather": "#59432c", "metal": "#6f7274", "trim": "#d6cfbd",
            "note": "undyed wool, oak-gall brown, bone tokens, chain"},
    "woodfolk": {"primary": "#665a45", "secondary": "#5a5f47", "accent": "#6e7650",
               "leather": "#3f3325", "metal": "#5f6259", "trim": "#2b211c",
               "note": "bark browns and lichen"},
    "ash_pilgrims": {"primary": "#8b8a86", "secondary": "#5a5652", "accent": "#cfc7b6",
                   "leather": "#4a4744", "metal": "#77736d", "trim": "#8f7f58",
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
