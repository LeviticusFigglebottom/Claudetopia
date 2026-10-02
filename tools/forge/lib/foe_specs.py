"""Who each forged foe is: its skeleton, its body, its size against its def (pure Python).

`spec(name)` gives a `FoeSpec`: the skeleton to build, the SDF scene, the style the painter reads,
the def `scale` the model is built for (the game scales it by the def's scale over this one, so an
matriarch built for 1.3 is drawn at the size the forge made her), and the budgets. creature_forge.py
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
    if name == "brake_dam":
        # the Brake-Dam: the thornhounds' dam, who whelps them in the Charter Delf's root -- a hound the
        # size of a pony (1.4 m at the withers in the game), heavy in the barrel and deep under it, her
        # bark grown thick and the briar she lies in grown into her, round her barrel and her neck and
        # her haunches; old, scarred, her frame showing through the bark
        sp = _canid(name, 1.72, 1.06, 0.94, 1.08,
                    bb.CanidStyle(kind="thorn", girth=1.36, depth=1.18, legs=1.5, ruff=0.0, fur=0.002, ears=0.75,
                                  muzzle=1.0, muzzle_w=1.2, brush=0.3, thorns=1.5, bark=1.35, age=0.6, scars=0.8,
                                  coils=1.0, seed=29), 2.4, "#3e3a24", depth=1.18, tris=9000)
        sp.extra["keep_barrel"] = True
        return sp
    if name == "leech_hound":
        # sleek, low, long in the body: an otter's build on a hound's head; 0.48 m at the withers
        return _canid(name, 0.76, 1.24, 0.7, 1.08,
                      bb.CanidStyle(kind="leech", girth=1.0, legs=0.9, ruff=0.0, fur=0.0, ears=0.55,
                                    muzzle=1.1, muzzle_w=0.92, brush=0.2, sleek=1.0, seed=11), 0.95, "#4d3f52")
    if name == "old_grey_bitch":
        # Mother: the first of Illa Nauve's leech-hounds, the pack's dam -- the same slick otter's
        # build grown big (0.83 m) and heavy, her frame showing through, the back let down, the muzzle
        # grey, the left ear bitten off and both flanks scarred by herons
        sp = _canid(name, 1.04, 1.18, 0.72, 1.12,
                    bb.CanidStyle(kind="leech", girth=1.18, depth=1.12, legs=1.05, ruff=0.0, fur=0.0, ears=0.6,
                                  muzzle=1.04, muzzle_w=1.04, brush=0.25, sleek=1.0, age=1.0, torn_ear=0.9,
                                  scars=1.0, seed=17), 1.3, "#5b5160", depth=1.12)
        sp.extra["keep_barrel"] = True
        return sp
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
    if name in ("sallowjaw", "gutter_drake"):
        from . import reptile as rp
        if name == "sallowjaw":
            joints, trunk, k = rp.CROC, rp.CROC_TRUNK, 1.0
            st = rp.ReptileStyle(kind="croc", seed=51)
            props = QuadProportions(withers=0.50, body_length=0.9, leg_length=0.3, neck_length=0.4, head_size=1.2,
                                    bulk=1.2, width=1.4, tail_length=2.0)
            return FoeSpec(name, "reptile", QuadSkeleton(props, joints=joints), st,
                           None, def_scale=1.25, tex=1024, tris=8000, lod1=2700, lod2=800, spacing=0.008,
                           extra={"tint": "#5c5f3a", "module": rp, "trunk": trunk, "splay": 1.2,
                                  "kind": {"tail_carriage": 0.0, "ears_back": 0.0, "lie_height": 0.3, "sternal": 0.16,
                                           "lie_roll": 180.0, "turn": 45.0,
                                           "speeds": {"Walk": 0.6, "Trot": 1.1, "Run": 2.6}}})
        k = 0.42
        joints = rp.scaled(rp.CROC, k, leg=1.7, head=0.5, tail=0.75, head_up=0.07)
        trunk = rp.scaled_trunk(rp.CROC_TRUNK, k, leg=1.6)
        st = rp.ReptileStyle(kind="drake", scutes=0.5, bands=1.0, horns=1.0, teeth=0.8, seed=61)
        props = QuadProportions(withers=0.50 * k, body_length=0.9, leg_length=0.5, neck_length=0.4, head_size=0.8,
                                bulk=1.0, width=1.2, tail_length=1.6)
        return FoeSpec(name, "reptile", QuadSkeleton(props, joints=joints), st, None, def_scale=0.55, tex=512,
                       tris=5000, lod1=1700, lod2=500, spacing=0.0035,
                       extra={"tint": "#3f4a3c", "module": rp, "trunk": trunk, "splay": 0.9,
                              "kind": {"tail_carriage": 0.0, "ears_back": 0.0, "lie_height": 0.3, "sternal": 0.2,
                                       "lie_roll": 180.0, "turn": 45.0,
                                       "speeds": {"Walk": 0.55, "Trot": 1.1, "Run": 3.4},
                                       "cycles": {"Walk": 16, "Trot": 10, "Run": 7}}})
    if name == "wisp":
        from . import wisp as wp
        st = wp.WispStyle()
        return FoeSpec(name, "wisp", wp.RIG, st, lambda: wp.shroud_scene(st), def_scale=0.35, tex=256,
                       tris=2400, lod1=900, lod2=300, spacing=0.008,
                       extra={"tint": "#9fd6c8", "module": wp, "parts": lambda: wp.scene_parts(st),
                              "part_share": {"Body": 0.85, "Core": 0.15}, "look": "wisp"})
    if name == "warden":
        from . import warden as wd
        st = wd.WardenStyle()
        return FoeSpec(name, "biped", wd.RIG, st, lambda: wd.scene(st), def_scale=2.4, tex=1024,
                       tris=11000, lod1=3600, lod2=1100, spacing=0.016,
                       extra={"tint": "#3c4a30", "module": wd})
    if name in ("stone_thrall", "stone_thrall_king"):
        from . import thrall as th
        st = th.ThrallStyle(king=name.endswith("king"))
        # the King is the thrall's frame grown to 6.2 m (his def's scale 3.2 over 1.6) and crowned
        return FoeSpec(name, "biped", th.RIG, st, lambda: th.scene_parts(st)["Body"], def_scale=1.6 if st.king else 2.2,
                       tex=1024, tris=14000 if st.king else 12000, lod1=4500 if st.king else 4000,
                       lod2=1400 if st.king else 1200, spacing=0.011,
                       extra={"tint": "#7e7768" if st.king else "#8c8578", "module": th.KING if st.king else th,
                              "parts": lambda: th.scene_parts(st), "limbs": th.KING_LIMBS if st.king else th.LIMBS,
                              "part_share": ({"Body": 0.66, "ArmL": 0.15, "ArmR": 0.15, "Jaw": 0.04} if st.king else
                                             {"Body": 0.6, "ArmR": 0.15, "ArmL": 0.15, "LegL": 0.1})})
    raise KeyError(name)


FOES = ["down_wolf", "crag_wolf", "thornhound", "brake_dam", "leech_hound", "old_grey_bitch", "bristleback", "gutter_drake",
        "sallowjaw", "weaver", "stone_thrall", "stone_thrall_king", "warden", "wisp"]
QUADS = ("canid", "boar", "reptile")


def _reptile_scene(sp: FoeSpec):
    return sp.extra["module"].reptile_scene(sp.skel, sp.style, sp.extra["trunk"])


_spec = spec


def spec(name: str) -> FoeSpec:  # noqa: F811
    sp = _spec(name)
    if sp.scene is None:
        sp.scene = lambda sp=sp: _reptile_scene(sp)
    return sp
