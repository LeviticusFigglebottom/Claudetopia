"""Who each forged foe is: its skeleton, its body, its size against its def (pure Python).

`spec(name)` gives a `FoeSpec`: the skeleton to build, the SDF scene, the style the painter reads,
the def `scale` the model is built for (the game scales it by the def's scale over this one, so an
old matriarch at 1.3 is the leech-hound's own model grown), and the budgets. creature_forge.py
builds from it; the previews read it without Blender.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Dict, Optional

from .quadruped import QuadSkeleton, QuadProportions
from . import beast_body as bb


@dataclass
class FoeSpec:
    name: str
    family: str                       # canid | boar | reptile | spider | biped | wisp
    skel: object
    style: object
    scene: Callable[[], object]
    def_scale: float = 1.0
    tex: int = 1024
    tris: int = 6000
    lod1: int = 2000
    lod2: int = 600
    spacing: float = 0.006
    extra: dict = field(default_factory=dict)


def _canid(name: str, k: float, length: float, leg: float, head: float, style: bb.CanidStyle,
           def_scale: float, tint: str, depth: float = 1.0, tex: int = 1024, tris: int = 6500) -> FoeSpec:
    joints = bb.scaled_joints(bb.WOLF_JOINTS, k=k, length=length, leg=leg, head=head)
    props = QuadProportions(withers=0.80 * k, body_length=0.62 * length, leg_length=leg, neck_length=0.6,
                            head_size=0.55 * head, bulk=0.5, width=0.6, tail_length=0.6)
    skel = QuadSkeleton(props, joints=joints)
    skel.muzzle = style.muzzle
    trunk = bb.scaled_trunk(bb.WOLF_TRUNK, k=k, length=length, leg=leg, depth=depth, girth=style.girth)
    return FoeSpec(name, "canid", skel, style, lambda: bb.canid_scene(skel, style, trunk), def_scale=def_scale,
                   tex=tex, tris=tris, lod1=tris // 3, lod2=tris // 10, spacing=0.0055 * k,
                   extra={"trunk": trunk, "tint": tint})


def _lod1(sp: FoeSpec, n: int) -> FoeSpec:
    sp.lod1 = n
    return sp


def spec(name: str) -> FoeSpec:
    if name == "down_wolf":
        # lean, grey-gold, patient: the Vale's wolf, 0.80 m at the withers
        return _canid(name, 1.0, 1.0, 1.0, 1.0, bb.CanidStyle(kind="wolf", ruff=0.35, fur=0.006, ears=1.1, muzzle=1.06,
                                                                  legs=0.95, brush=0.85, seed=3), 1.0, "#8a8073")
    if name == "crag_wolf":
        # bigger than a Vale wolf, white the year round, heavy in the shoulder: 0.96 m
        return _canid(name, 1.2, 0.98, 1.0, 1.02,
                      bb.CanidStyle(kind="crag", girth=1.2, depth=1.1, legs=1.28, ruff=1.9, fur=0.016,
                                    muzzle=0.88, muzzle_w=1.15, ears=0.8, brush=1.45, seed=5), 1.25, "#d6d9dd",
                      depth=1.1)
    if name == "thornhound":
        # a hound crossed with the wall: bark-skinned, thorn-jawed, a whip of a tail; 0.71 m
        return _lod1(_canid(name, 0.9, 0.98, 0.86, 1.04,
                      bb.CanidStyle(kind="thorn", girth=1.0, legs=1.2, ruff=0.0, fur=0.002, ears=0.8,
                                    muzzle=1.05, brush=0.25, thorns=1.15, bark=1.0, seed=7), 1.05, "#4a3b2c"), 3200)
    if name == "leech_hound":
        # sleek, low, long in the body: an otter's build on a hound's head; 0.48 m at the withers
        return _canid(name, 0.76, 1.24, 0.7, 1.08,
                      bb.CanidStyle(kind="leech", girth=1.0, legs=0.9, ruff=0.0, fur=0.0, ears=0.55,
                                    muzzle=1.1, muzzle_w=0.92, brush=0.2, sleek=1.0, seed=11), 0.95, "#4d3f52")
    if name == "weaver":
        from . import weaver as wv
        st = wv.WeaverStyle()
        return FoeSpec(name, "spider", wv.RIG, st, lambda: wv.weaver_scene(wv.RIG, st), def_scale=1.2, tex=1024,
                       tris=9000, lod1=3000, lod2=900, spacing=0.0045,
                       extra={"tint": "#59504a", "module": wv})
    if name == "bristleback":
        from . import boar as bo
        skel = bo.make_skel()
        st = bo.BoarStyle()
        return FoeSpec(name, "boar", skel, st, lambda: bo.boar_scene(skel, st), def_scale=1.1, tex=1024,
                       tris=7500, lod1=3900, lod2=750, spacing=0.0065,
                       extra={"tint": "#5a4436", "module": bo, "trunk": bo.TRUNK,
                              "kind": {"tail_carriage": 25.0, "ears_back": 20.0, "lie_height": 0.24, "sternal": 0.36,
                                       "speeds": {"Walk": 0.95, "Trot": 2.0, "Run": 4.2}}})
    if name in ("stone_thrall", "stone_thrall_king"):
        from . import thrall as th
        st = th.ThrallStyle(king=name.endswith("king"))
        return FoeSpec(name, "biped", th.RIG, st, lambda: th.scene_parts(st)["Body"], def_scale=3.2 if st.king else 2.2,
                       tex=1024, tris=12000, lod1=4000, lod2=1200, spacing=0.011,
                       extra={"tint": "#7e7768" if st.king else "#8c8578", "module": th,
                              "parts": lambda: th.scene_parts(st), "limbs": th.LIMBS,
                              "part_share": {"Body": 0.6, "ArmR": 0.15, "ArmL": 0.15, "LegL": 0.1}})
    raise KeyError(name)


FOES = ["down_wolf", "crag_wolf", "thornhound", "leech_hound", "bristleback", "weaver", "stone_thrall"]
QUADS = ("canid", "boar", "reptile")
