"""The wisp: the Sedgemire's lantern that is not a lantern (core:enemy/wisp).

WORLD_BIBLE §8: "caster/lure: a lantern that is not a lantern; leads you into deep water; shoots
cold". The lore: "a lantern at the right height, the right amber, with the right patient sway".
So an amber light at a lantern's height -- a core the size of a fist -- held in a pale hood of
mist that hangs from it in a ragged shroud and a few long trailing tendrils, as if something
were carrying it and you could almost see the hand.

Two meshes: Wisp_Core (the light; CreatureModel draws it as a glow and hangs a light on it) and
Wisp_Body (the shroud; drawn by wisp_veil.gdshader, additive and fading at its edges). Rig
WM_Wisp_v1: Hips (the core, the bone that hovers), Hood over it, the shroud's Trail1-3 down and
behind, and four Tendril<n> chains of two.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict
from typing import Dict

import numpy as np

from . import sdf, paint
from .anim import FPS
from .rig import rot_axis, UP, FWD, LEFT
from .creature_rig import Rig, Poser, RigClip, _u
from . import beast_body as bb

RIG_ID = "WM_Wisp_v1"
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])
CORE = np.array([0.0, 0.0, 1.15])
CORE_R = 0.075
TENDRILS = [(-60.0, 0.10), (60.0, 0.10), (-150.0, 0.06), (150.0, 0.06)]   # (angle from ahead, lift)


@dataclass
class WispStyle:
    seed: int = 81

    def to_dict(self) -> dict:
        return asdict(self)


def _tendril_points(i: int):
    a, lift = TENDRILS[i]
    ar = math.radians(a)
    d = np.array([math.sin(ar), -math.cos(ar), 0.0])
    p0 = CORE + d * 0.10 + Z * lift
    p1 = p0 + d * 0.16 - Z * 0.22
    p2 = p1 + d * 0.06 - Z * 0.30
    return p0, p1, p2


def make_rig() -> Rig:
    bones = [("Hips", None, CORE, CORE + Z * 0.08, FWD),
             ("Hood", "Hips", CORE + Z * 0.04, CORE + Z * 0.26, FWD),
             ("Trail1", "Hips", CORE + np.array([0.0, 0.05, -0.05]), CORE + np.array([0.0, 0.14, -0.30]), FWD),
             ("Trail2", "Trail1", CORE + np.array([0.0, 0.14, -0.30]), CORE + np.array([0.0, 0.26, -0.58]), FWD),
             ("Trail3", "Trail2", CORE + np.array([0.0, 0.26, -0.58]), CORE + np.array([0.0, 0.40, -0.82]), FWD)]
    for i in range(len(TENDRILS)):
        p0, p1, p2 = _tendril_points(i)
        bones.append(("Tendril%dA" % i, "Hips", p0, p1, FWD))
        bones.append(("Tendril%dB" % i, "Tendril%dA" % i, p1, p2, FWD))
    return Rig(RIG_ID, bones, height=1.4)


RIG = make_rig()


def shroud_scene(st: WispStyle) -> sdf.Scene:
    """The hood over the light and the shroud falling from it: thin, open below, ragged."""
    sc = sdf.Scene()
    # the hood: a shell round the top of the core, open in front so the light shows
    outer = sdf.ellipsoid(CORE + Z * 0.08, np.array([0.17, 0.17, 0.2]))
    sc.union(outer)
    sc.subtract(sdf.ellipsoid(CORE + Z * 0.05, np.array([0.145, 0.145, 0.175])), k=0.01)
    sc.subtract(sdf.ellipsoid(CORE + np.array([0.0, -0.17, 0.0]), np.array([0.12, 0.12, 0.15])), k=0.02)
    # the shroud: tapering sheets falling behind and below
    pts = [CORE + np.array([0.0, 0.06, -0.02]), CORE + np.array([0.0, 0.14, -0.30]),
           CORE + np.array([0.0, 0.26, -0.58]), CORE + np.array([0.0, 0.40, -0.82])]
    sc.union(sdf.sweep([(p, r, r * 0.35) for p, r in zip(pts, (0.15, 0.13, 0.09, 0.02))], X), k=0.05)
    # the tendrils: long thin trailing hands
    for i in range(len(TENDRILS)):
        p0, p1, p2 = _tendril_points(i)
        sc.union(sdf.tube_path([p0, p1, p2], [0.03, 0.022, 0.005]), k=0.04)
    rng = np.random.default_rng(st.seed)
    # rag the hem: bites out of the shroud's lower edge
    for j in range(9):
        sx = 1.0 if j % 2 else -1.0
        c = CORE + np.array([sx * (0.06 + 0.04 * rng.random()), 0.16 + 0.2 * rng.random(), -0.35 - 0.3 * rng.random()])
        sc.subtract(sdf.sphere(c, 0.035 + 0.025 * rng.random()), k=0.02)
    return sc


def core_scene(st: WispStyle) -> sdf.Scene:
    sc = sdf.Scene()
    sc.union(sdf.sphere(CORE, CORE_R))
    return sc


def scene_parts(st: WispStyle):
    return {"Body": shroud_scene(st), "Core": core_scene(st)}


def painter(spec, field):
    """The shroud's map: what the veil shader reads as its streaks (pale where the mist is thick,
    dark where it thins), and the core's amber."""
    st = spec.style
    n1 = paint.Noise(st.seed, 64)

    def albedo(P, nrm):
        d_core = np.linalg.norm(P - CORE, axis=1)
        core = 1.0 - bb.sm(CORE_R * 1.05, CORE_R * 1.3, d_core)
        streak = n1.fbm(P * np.array([2.5, 2.5, 0.6]), freq=14.0, octaves=3)
        c = np.stack([0.62 + 0.3 * streak, 0.84 + 0.14 * streak, 0.80 + 0.16 * streak], axis=1)
        c = c * (0.55 + 0.6 * bb.sm(0.3, 0.7, streak))[:, None]
        c = paint.mix(c, np.array([1.0, 0.72, 0.30]), core)
        return np.clip(c, 0, 1)

    def orm(P, nrm):
        return np.stack([np.ones(len(P)), np.full(len(P), 0.9), np.zeros(len(P))], axis=1)

    return albedo, orm, None


def hurt():
    return [("sphere", CORE + Z * 0.02, 0.26)]


def origin():
    return CORE


# --------------------------------------------------------------------------------------
# clips: it hovers; the clips are the drift of its shroud and the lean of the light
# --------------------------------------------------------------------------------------

def _pose(t: float, bob: float, lean: float, sway: float, stream: float, reach: float = 0.0, flare: float = 0.0,
          sink: float = 0.0, droop: float = 0.0, turn: float = 0.0) -> Poser:
    p = Poser(RIG)
    R = rot_axis(UP, math.radians(turn)) @ rot_axis(LEFT, math.radians(lean)) @ rot_axis(FWD, math.radians(sway))
    p.move_hips(R, np.array([0.0, 0.0, bob - sink]))
    p.turn("Hood", rot_axis(LEFT, math.radians(-lean * 0.5 + 6.0 * math.sin(t * 2.1))))
    # the shroud streams back with the speed, and ripples
    for i, n in enumerate(("Trail1", "Trail2", "Trail3")):
        r = math.sin(t * 3.0 - i * 0.9)
        p.turn(n, rot_axis(LEFT, math.radians(-stream * (0.6 + 0.3 * i) + 8.0 * r - droop * 20.0))
               @ rot_axis(FWD, math.radians(6.0 * math.sin(t * 1.7 - i))))
    for i, (a, _) in enumerate(TENDRILS):
        side = 1.0 if a > 0 else -1.0
        front = abs(a) < 90.0
        r = math.sin(t * 2.4 + i * 1.3)
        lift = -stream * 0.5 + 10.0 * r - droop * 30.0
        if front:
            lift += 70.0 * reach
        p.turn("Tendril%dA" % i, rot_axis(LEFT, math.radians(-lift)) @ rot_axis(FWD, math.radians(side * (12.0 * r + 55.0 * flare))))
        p.turn("Tendril%dB" % i, rot_axis(LEFT, math.radians(-0.6 * lift)) @ rot_axis(FWD, math.radians(side * 30.0 * flare)))
    return p


def hover_clip(name: str, L: float, speed: float = 0.0, lean: float = 0.0, stream: float = 0.0, side: float = 0.0,
               turn: float = 0.0) -> RigClip:
    def sample(t: float) -> Poser:
        u = t / L
        return _pose(t, 0.05 * math.sin(2 * math.pi * u * 2), lean, 6.0 * math.sin(2 * math.pi * u) + side * 10.0,
                     stream, turn=turn * math.sin(2 * math.pi * u) * 0.0)
    extra = {}
    if speed:
        extra["speed"] = speed
    if turn:
        extra["turn"] = turn
    return RigClip(name, L, True, sample, [], extra)


def cast_clip(name: str = "Cast_Quick") -> RigClip:
    """Cast_Quick, the cold light: drawn back, the front tendrils raised, then thrown forward at
    the blow; the game brightens the light with it."""
    L = 0.9
    cocked, hs, he, ok = 0.4, 0.55, 0.65, 0.75

    def sample(t: float) -> Poser:
        back = bi_s(t / cocked) * (1.0 - bi_s((t - cocked) / (hs - cocked)))
        go = bi_s((t - cocked) / (hs - cocked)) * (1.0 - bi_s((t - he) / (L - he)))
        return _pose(t, 0.08 * back, -12.0 * back + 18.0 * go, 0.0, 10.0 * back, reach=0.6 * back + 1.0 * go)
    return RigClip(name, L, False, sample, [(cocked, "cocked"), (hs, "cast_release"), (hs, "hit_start"),
                                                     (he, "hit_end"), (ok, "cancel_ok")])


def gutter_clip() -> RigClip:
    """Attack_2, the guttering: the light sinks and gathers, the tendrils drawn in; then it flares,
    the shroud thrown wide in a ring of cold (`hit_start`)."""
    L = 1.3
    cocked, hs, he, ok = 0.62, 0.8, 0.96, 1.1

    def sample(t: float) -> Poser:
        gather = bi_s(t / cocked) * (1.0 - bi_s((t - cocked) / (hs - cocked)))
        burst = bi_s((t - cocked) / (hs - cocked)) * (1.0 - bi_s((t - he) / (L - he)))
        return _pose(t, -0.08 * gather + 0.06 * burst, 0.0, 0.0, -20.0 * burst, flare=-0.4 * gather + 1.0 * burst,
                     droop=0.5 * gather)
    return RigClip("Attack_2", L, False, sample, [(cocked, "cocked"), (hs, "hit_start"), (he, "hit_end"), (ok, "cancel_ok")])


def hit_clip() -> RigClip:
    L = 0.45

    def sample(t: float) -> Poser:
        k = bi_b(t / L, 0.25)
        return _pose(t, 0.05 * k, -20.0 * k, 8.0 * k, 25.0 * k, flare=0.4 * k)
    return RigClip("Hit", L, False, sample, [(0.01, "hit_react"), (0.3, "cancel_ok")])


def stagger_clip() -> RigClip:
    L = 0.8

    def sample(t: float) -> Poser:
        u = t / L
        k = bi_b(u, 0.25)
        return _pose(t, -0.1 * k, -25.0 * k, 20.0 * math.sin(2 * math.pi * u * 1.5) * (1.0 - u), 30.0 * k, flare=0.5 * k)
    return RigClip("Stagger", L, False, sample, [(0.01, "hit_react"), (0.65, "cancel_ok")])


def knockdown_clip() -> RigClip:
    L = 1.6

    def sample(t: float) -> Poser:
        k = bi_s(t / 0.4)
        return _pose(t, 0.0, -30.0 * k, 25.0 * k, 25.0, sink=0.55 * k, droop=0.8 * k)
    return RigClip("Knockdown", L, False, sample, [(0.02, "hit_react"), (0.4, "body_land")], {"held": True})


def get_up_clip() -> RigClip:
    L = 0.8

    def sample(t: float) -> Poser:
        k = 1.0 - bi_s(t / L)
        return _pose(t, 0.0, -30.0 * k, 25.0 * k, 25.0 * k, sink=0.55 * k, droop=0.8 * k)
    return RigClip("Get_Up", L, False, sample, [(0.6 * L, "cancel_ok")])


def death_clip() -> RigClip:
    """Going out: the light sinks toward the water, the shroud collapsing round it; the game puts
    the light out with it. The last frame is held."""
    L = 2.0

    def sample(t: float) -> Poser:
        u = t / L
        k = bi_s(u / 0.8)
        return _pose(t, 0.03 * math.sin(t * 9.0) * (1.0 - k), 10.0 * k, 0.0, -10.0 * k, sink=1.0 * k, droop=1.0 * k)
    return RigClip("Death", L, False, sample, [(0.02, "death_start"), (0.8 * L, "body_land")], {"held": True})


def bi_s(x: float) -> float:
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def bi_b(x: float, peak: float = 0.5) -> float:
    x = min(1.0, max(0.0, x))
    if x < peak:
        return math.sin(0.5 * math.pi * x / peak) ** 2
    return math.sin(0.5 * math.pi * (1.0 - x) / (1.0 - peak)) ** 2


def build_clips() -> Dict[str, RigClip]:
    return {
        "Idle": hover_clip("Idle", 4.0), "Idle_Combat": hover_clip("Idle_Combat", 2.0, lean=6.0),
        "Walk": hover_clip("Walk", 2.0, speed=1.2, lean=10.0, stream=20.0),
        "Run": hover_clip("Run", 1.2, speed=3.2, lean=18.0, stream=45.0),
        "Walk_Back": hover_clip("Walk_Back", 2.0, speed=-1.0, lean=-8.0, stream=-10.0),
        "Strafe_L": hover_clip("Strafe_L", 2.0, speed=1.0, stream=15.0, side=-1.0),
        "Strafe_R": hover_clip("Strafe_R", 2.0, speed=1.0, stream=15.0, side=1.0),
        "Attack_1": cast_clip("Attack_1"), "Cast_Quick": cast_clip(), "Attack_2": gutter_clip(),
        "Hit": hit_clip(), "Stagger": stagger_clip(), "Knockdown": knockdown_clip(), "Get_Up": get_up_clip(),
        "Death": death_clip(),
    }
