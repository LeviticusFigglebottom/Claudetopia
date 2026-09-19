"""Trees keyed by region flora (WORLD_BIBLE §6, regions.json identity.flora).

    blender -b --python tools/forge/gen_trees.py -- --kind oak --palette hearthvale --seed 1 --variant a

Species: hearthvale oak / apple / hawthorn / yew; briarwold giant_oak / black_ash;
skerrow hardy_pine / rowan / juniper; sedgemire willow / alder; cinderlea dead_ash_tree;
brightwater willow_pollard / lime.

Each tree is a Sapling-grown trunk with our bark material and displacement, plus leaf
cards mapped into a drawn leaf-cluster atlas (2-3 cluster shapes per species). LOD1 drops
branch resolution and half the cards; LOD2 is a crossed-card impostor with a rendered
texture of the tree itself.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import cli  # noqa: E402
from lib import export as E  # noqa: E402
from lib import impostor as IMP  # noqa: E402
from lib import materials as M  # noqa: E402
from lib import palette as P  # noqa: E402
from lib import scene as S  # noqa: E402
from lib import textures as T  # noqa: E402
from lib import tree as TR  # noqa: E402
from lib.runner import run_generator  # noqa: E402


# --- species table -----------------------------------------------------------------------
# sapling: Sapling parameters. leaf: atlas description. bark: material builder name.
SPECIES = {
    # ---- Hearthvale -------------------------------------------------------------------
    "oak": dict(
        height=(8.5, 12.0), bark="oak_bark", leaf_hex="#4d7a2e", leaf_shapes=("lobed", "oval", "lobed"),
        card=0.95, leaf_scale=0.40, leaves=105, autumn_hex="#a8762e", autumn=0.10,
        sapling=dict(levels=3, shape="2", shapeS="4", branches=(0, 38, 22, 12), length=(0.82, 0.55, 0.62, 0.42),
                     lengthV=(0, 0.14, 0.15, 0.1), baseSize=0.28, baseSize_s=0.2, ratio=0.021, ratioPower=1.35,
                     curveRes=(9, 8, 5, 3), curve=(0, 38, -28, 0), curveV=(65, 105, 120, 0), curveBack=(0, -18, 0, 0),
                     attractUp=(0, -0.3, -0.6, -0.4), downAngle=(0, 62, 48, 42), downAngleV=(0, 26, 18, 12),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(18, 22, 30, 0), segSplits=(0.24, 0.32, 0.18, 0),
                     splitAngle=(14, 22, 18, 0), splitAngleV=(6, 10, 10, 0), baseSplits=2, splitBias=0.3,
                     taperCrown=0.25, leafScale=0.42, leafScaleX=0.9, leafDownAngle=48),
        trunk_scale=1.0, relief=0.035,
    ),
    "apple": dict(
        height=(4.2, 5.6), bark="oak_bark", bark_kw=dict(tint=0.1), leaf_hex="#5d8a38",
        leaf_shapes=("oval", "oval", "round"), card=0.72, leaf_scale=0.34, leaves=95,
        fruit_hex="#b23a2e", fruit_r=0.030, fruit_count=6,
        sapling=dict(levels=3, shape="1", shapeS="4", branches=(0, 26, 18, 10), length=(0.62, 0.62, 0.55, 0.4),
                     lengthV=(0, 0.18, 0.15, 0.1), baseSize=0.22, baseSize_s=0.22, ratio=0.026, ratioPower=1.2,
                     curveRes=(7, 7, 5, 3), curve=(0, 50, -40, 0), curveV=(90, 130, 130, 0),
                     attractUp=(0, -0.7, -1.1, -0.5), downAngle=(0, 68, 58, 45), downAngleV=(0, 30, 22, 14),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(25, 30, 35, 0), segSplits=(0.4, 0.35, 0.2, 0),
                     splitAngle=(22, 28, 20, 0), splitAngleV=(8, 12, 10, 0), baseSplits=3, splitBias=-0.2,
                     leafScale=0.36, leafScaleX=0.95, leafDownAngle=55),
        trunk_scale=1.0, relief=0.03,
    ),
    "hawthorn": dict(
        height=(3.6, 5.2), bark="oak_bark", bark_kw=dict(tint=0.2, age=0.7), leaf_hex="#3f6b2a",
        leaf_shapes=("toothed", "lobed"), card=0.55, leaf_scale=0.28, leaves=120,
        fruit_hex="#96241f", fruit_r=0.018, fruit_count=9,
        sapling=dict(levels=3, shape="5", shapeS="4", branches=(0, 42, 26, 12), length=(0.58, 0.48, 0.45, 0.35),
                     lengthV=(0, 0.25, 0.2, 0.1), baseSize=0.12, baseSize_s=0.18, ratio=0.03, ratioPower=1.15,
                     curveRes=(8, 7, 4, 3), curve=(0, 20, -20, 0), curveV=(140, 170, 160, 0),
                     attractUp=(0, -0.2, -0.4, 0), downAngle=(0, 55, 50, 45), downAngleV=(0, 40, 30, 20),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(40, 45, 45, 0), segSplits=(0.5, 0.45, 0.25, 0),
                     splitAngle=(28, 34, 26, 0), splitAngleV=(12, 14, 12, 0), baseSplits=3,
                     leafScale=0.3, leafScaleX=1.0, leafDownAngle=60),
        trunk_scale=1.0, relief=0.03,
    ),
    "yew": dict(
        height=(5.0, 7.5), bark="oak_bark", bark_kw=dict(tint=0.25, age=0.9), leaf_hex="#20401f",
        leaf_shapes=("needle", "lance"), card=0.85, leaf_scale=0.22, leaves=150, leaf_cells=2,
        fruit_hex="#a8301f", fruit_r=0.013, fruit_count=6,
        sapling=dict(levels=3, shape="2", shapeS="3", branches=(0, 45, 30, 14), length=(0.55, 0.52, 0.5, 0.4),
                     lengthV=(0, 0.2, 0.2, 0.1), baseSize=0.1, baseSize_s=0.2, ratio=0.045, ratioPower=1.1,
                     curveRes=(8, 7, 5, 3), curve=(0, 25, -30, 0), curveV=(120, 140, 130, 0),
                     attractUp=(0, -0.4, -0.8, -0.4), downAngle=(0, 70, 60, 50), downAngleV=(0, 35, 25, 15),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(30, 35, 40, 0), segSplits=(0.45, 0.4, 0.25, 0),
                     splitAngle=(24, 30, 24, 0), splitAngleV=(10, 12, 12, 0), baseSplits=4, splitBias=-0.4,
                     leafScale=0.26, leafScaleX=0.7, leafDownAngle=70),
        trunk_scale=1.0, relief=0.045,
    ),
    # ---- Briarwold --------------------------------------------------------------------
    "giant_oak": dict(
        height=(26.0, 34.0), bark="oak_bark", bark_kw=dict(tint=0.25, age=0.9), leaf_hex="#2c5322",
        leaf_shapes=("lobed", "oval", "lobed"), card=2.6, leaf_scale=0.42, leaves=130,
        buttress=dict(count=7, height=5.2, reach=3.4, thickness=1.15), moss=90, tier="hero",
        sapling=dict(levels=3, shape="2", shapeS="4", branches=(0, 34, 20, 10), length=(0.85, 0.5, 0.58, 0.4),
                     lengthV=(0, 0.15, 0.15, 0.1), baseSize=0.34, baseSize_s=0.22, ratio=0.026, ratioPower=1.4,
                     curveRes=(11, 9, 6, 3), curve=(0, 42, -32, 0), curveV=(70, 110, 120, 0), curveBack=(0, -22, 0, 0),
                     attractUp=(0, -0.35, -0.7, -0.4), downAngle=(0, 58, 46, 40), downAngleV=(0, 24, 18, 12),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(16, 20, 28, 0), segSplits=(0.22, 0.3, 0.18, 0),
                     splitAngle=(12, 20, 16, 0), splitAngleV=(6, 10, 10, 0), baseSplits=2, splitBias=0.4,
                     taperCrown=0.35, leafScale=0.5, leafScaleX=0.9, leafDownAngle=45),
        trunk_scale=1.0, relief=0.09,
    ),
    "black_ash": dict(
        height=(14.0, 19.0), bark="black_ash_bark", leaf_hex="#3a5f28", leaf_shapes=("lance", "toothed"),
        card=1.15, leaf_scale=0.32, leaves=110, moss=28,
        sapling=dict(levels=3, shape="4", shapeS="4", branches=(0, 30, 20, 10), length=(0.9, 0.42, 0.5, 0.4),
                     lengthV=(0, 0.12, 0.15, 0.1), baseSize=0.4, baseSize_s=0.2, ratio=0.017, ratioPower=1.45,
                     curveRes=(10, 8, 5, 3), curve=(0, 28, -30, 0), curveV=(45, 90, 110, 0),
                     attractUp=(0, 0.2, -0.3, -0.2), downAngle=(0, 48, 42, 38), downAngleV=(0, 20, 16, 10),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(14, 18, 25, 0), segSplits=(0.18, 0.25, 0.15, 0),
                     splitAngle=(10, 18, 14, 0), splitAngleV=(5, 8, 8, 0), baseSplits=1, splitBias=0.5,
                     taperCrown=0.2, leafScale=0.4, leafScaleX=0.85, leafDownAngle=42),
        trunk_scale=1.0, relief=0.05,
    ),
    # ---- Skerrow ----------------------------------------------------------------------
    "hardy_pine": dict(
        height=(9.0, 13.5), bark="pine_bark", leaf_hex="#2c4a30", leaf_shapes=("needle", "needle", "lance"),
        card=1.05, leaf_scale=0.26, leaves=120,
        sapling=dict(levels=3, shape="0", shapeS="4", branches=(0, 32, 22, 10), length=(0.92, 0.38, 0.42, 0.35),
                     lengthV=(0, 0.12, 0.12, 0.08), baseSize=0.42, baseSize_s=0.18, ratio=0.016, ratioPower=1.5,
                     curveRes=(9, 6, 4, 3), curve=(0, 12, -14, 0), curveV=(25, 55, 70, 0),
                     attractUp=(0, 0.5, 0.1, 0), downAngle=(0, 72, 60, 50), downAngleV=(0, 18, 14, 10),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(10, 14, 20, 0), segSplits=(0.08, 0.12, 0.08, 0),
                     splitAngle=(8, 14, 12, 0), splitAngleV=(4, 6, 6, 0), baseSplits=0, splitBias=0.6,
                     taperCrown=0.1, leafScale=0.34, leafScaleX=0.6, leafDownAngle=62),
        trunk_scale=1.0, relief=0.035,
    ),
    "rowan": dict(
        height=(5.5, 7.8), bark="birch_bark", bark_kw=dict(tint=0.25), leaf_hex="#4a7034",
        leaf_shapes=("toothed", "lance"), card=0.72, leaf_scale=0.28, leaves=110,
        fruit_hex="#c03418", fruit_r=0.016, fruit_count=12,
        sapling=dict(levels=3, shape="1", shapeS="4", branches=(0, 28, 20, 10), length=(0.68, 0.55, 0.5, 0.4),
                     lengthV=(0, 0.2, 0.18, 0.1), baseSize=0.3, baseSize_s=0.2, ratio=0.022, ratioPower=1.25,
                     curveRes=(8, 7, 5, 3), curve=(0, 32, -28, 0), curveV=(80, 110, 120, 0),
                     attractUp=(0, -0.3, -0.6, -0.3), downAngle=(0, 58, 50, 42), downAngleV=(0, 28, 20, 14),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(22, 26, 32, 0), segSplits=(0.3, 0.3, 0.2, 0),
                     splitAngle=(18, 24, 20, 0), splitAngleV=(8, 10, 10, 0), baseSplits=2,
                     leafScale=0.34, leafScaleX=0.9, leafDownAngle=52),
        trunk_scale=1.0, relief=0.025,
    ),
    "juniper": dict(
        height=(1.6, 2.6), bark="pine_bark", bark_kw=dict(age=0.8), leaf_hex="#33503a",
        leaf_shapes=("needle", "needle"), card=0.55, leaf_scale=0.22, leaves=130,
        fruit_hex="#3f4a6a", fruit_r=0.012, fruit_count=8,
        sapling=dict(levels=3, shape="6", shapeS="3", branches=(0, 40, 28, 12), length=(0.35, 0.72, 0.6, 0.45),
                     lengthV=(0, 0.3, 0.25, 0.12), baseSize=0.06, baseSize_s=0.16, ratio=0.05, ratioPower=1.0,
                     curveRes=(6, 7, 5, 3), curve=(0, 15, -20, 0), curveV=(150, 180, 170, 0),
                     attractUp=(0, 0.1, -0.2, 0), downAngle=(0, 62, 55, 48), downAngleV=(0, 45, 35, 20),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(45, 50, 50, 0), segSplits=(0.55, 0.45, 0.3, 0),
                     splitAngle=(32, 36, 28, 0), splitAngleV=(14, 16, 14, 0), baseSplits=4, splitBias=-0.6,
                     leafScale=0.24, leafScaleX=0.65, leafDownAngle=68),
        trunk_scale=1.0, relief=0.02,
    ),
    # ---- Sedgemire --------------------------------------------------------------------
    "willow": dict(
        height=(7.5, 11.0), bark="willow_bark", leaf_hex="#5c7a3a", leaf_shapes=("lance", "lance", "needle"),
        card=1.0, leaf_scale=0.24, leaves=95, droop=55.0, weep=dict(count=110, length=(1.6, 4.4), width=(0.5, 1.0)),
        sapling=dict(levels=3, shape="3", shapeS="4", branches=(0, 30, 22, 10), length=(0.72, 0.6, 0.65, 0.45),
                     lengthV=(0, 0.2, 0.2, 0.1), baseSize=0.26, baseSize_s=0.2, ratio=0.024, ratioPower=1.25,
                     curveRes=(9, 9, 6, 3), curve=(0, 45, -55, 0), curveV=(90, 140, 150, 0),
                     attractUp=(0, -1.2, -2.6, -1.5), downAngle=(0, 52, 62, 55), downAngleV=(0, 28, 24, 16),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(24, 28, 34, 0), segSplits=(0.3, 0.3, 0.2, 0),
                     splitAngle=(16, 22, 18, 0), splitAngleV=(8, 10, 10, 0), baseSplits=2,
                     leafScale=0.34, leafScaleX=0.55, leafDownAngle=78),
        trunk_scale=1.0, relief=0.04,
    ),
    "alder": dict(
        height=(6.5, 9.5), bark="willow_bark", bark_kw=dict(tint=0.3, age=0.7), leaf_hex="#3d6636",
        leaf_shapes=("round", "oval"), card=0.85, leaf_scale=0.32, leaves=100,
        fruit_hex="#4a3a28", fruit_r=0.014, fruit_count=7,
        sapling=dict(levels=3, shape="4", shapeS="4", branches=(0, 32, 22, 10), length=(0.8, 0.48, 0.5, 0.4),
                     lengthV=(0, 0.18, 0.15, 0.1), baseSize=0.24, baseSize_s=0.2, ratio=0.021, ratioPower=1.3,
                     curveRes=(8, 7, 5, 3), curve=(0, 30, -26, 0), curveV=(75, 105, 115, 0),
                     attractUp=(0, -0.1, -0.4, -0.2), downAngle=(0, 55, 48, 42), downAngleV=(0, 26, 20, 12),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(20, 24, 30, 0), segSplits=(0.3, 0.3, 0.2, 0),
                     splitAngle=(16, 22, 18, 0), splitAngleV=(8, 10, 10, 0), baseSplits=2,
                     leafScale=0.38, leafScaleX=0.95, leafDownAngle=50),
        trunk_scale=1.0, relief=0.035,
    ),
    # ---- Cinderlea --------------------------------------------------------------------
    "dead_ash_tree": dict(
        height=(7.0, 11.5), bark="dead_bark", leaf_hex=None, leaves=0,
        sapling=dict(levels=3, shape="7", shapeS="4", branches=(0, 34, 26, 14), length=(0.88, 0.5, 0.48, 0.4),
                     lengthV=(0, 0.2, 0.2, 0.12), baseSize=0.3, baseSize_s=0.18, ratio=0.018, ratioPower=1.4,
                     curveRes=(10, 8, 6, 4), curve=(0, 35, -40, 0), curveV=(85, 130, 150, 0),
                     attractUp=(0, 0.3, 0.5, 0.2), downAngle=(0, 50, 45, 40), downAngleV=(0, 30, 26, 18),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(26, 30, 36, 0), segSplits=(0.35, 0.35, 0.25, 0),
                     splitAngle=(20, 26, 22, 0), splitAngleV=(10, 12, 12, 0), baseSplits=2, showLeaves=False),
        trunk_scale=1.0, relief=0.04,
    ),
    "char_stump": dict(
        height=(1.5, 2.6), bark="dead_bark", bark_kw=dict(tint=0.4, age=1.0), leaf_hex=None, leaves=0,
        sapling=dict(levels=2, shape="4", shapeS="4", branches=(0, 12, 6, 0), length=(0.42, 0.3, 0.2, 0.1),
                     lengthV=(0, 0.3, 0.2, 0), baseSize=0.5, baseSize_s=0.3, ratio=0.055, ratioPower=1.6,
                     curveRes=(6, 4, 2, 1), curve=(0, 40, 0, 0), curveV=(60, 160, 0, 0),
                     attractUp=(0, 0.4, 0, 0), downAngle=(0, 55, 45, 40), downAngleV=(0, 40, 0, 0),
                     rotate=(99.5, 137.5, 137.5, 137.5), segSplits=(0.3, 0.2, 0, 0), baseSplits=2, showLeaves=False),
        trunk_scale=1.0, relief=0.06,
    ),
    # ---- Brightwater ------------------------------------------------------------------
    "willow_pollard": dict(
        height=(3.8, 5.2), bark="willow_bark", bark_kw=dict(age=0.8), leaf_hex="#6a8a3e",
        leaf_shapes=("lance", "needle"), card=0.6, leaf_scale=0.22, leaves=130, pollard=True,
        sapling=dict(levels=2, shape="6", shapeS="4", branches=(0, 34, 0, 0), length=(0.5, 0.95, 0.3, 0.2),
                     lengthV=(0, 0.25, 0, 0), baseSize=0.62, baseSize_s=0.3, ratio=0.04, ratioPower=1.1,
                     curveRes=(6, 8, 3, 1), curve=(0, -12, 0, 0), curveV=(25, 70, 0, 0),
                     attractUp=(0, 1.6, 0, 0), downAngle=(0, 22, 40, 40), downAngleV=(0, 16, 0, 0),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(20, 24, 0, 0), segSplits=(0.1, 0.15, 0, 0),
                     splitAngle=(10, 14, 0, 0), baseSplits=1, leafScale=0.3, leafScaleX=0.6, leafDownAngle=40),
        trunk_scale=1.0, relief=0.055,
    ),
    "lime": dict(
        height=(9.0, 13.0), bark="oak_bark", bark_kw=dict(tint=0.2), leaf_hex="#5a8a3a",
        leaf_shapes=("heart", "heart", "round"), card=1.0, leaf_scale=0.34, leaves=110,
        sapling=dict(levels=3, shape="7", shapeS="4", branches=(0, 34, 22, 12), length=(0.85, 0.5, 0.55, 0.42),
                     lengthV=(0, 0.15, 0.15, 0.1), baseSize=0.3, baseSize_s=0.2, ratio=0.019, ratioPower=1.35,
                     curveRes=(9, 8, 5, 3), curve=(0, 30, -26, 0), curveV=(55, 95, 110, 0),
                     attractUp=(0, 0.1, -0.4, -0.3), downAngle=(0, 52, 46, 40), downAngleV=(0, 22, 18, 12),
                     rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(16, 20, 28, 0), segSplits=(0.2, 0.28, 0.18, 0),
                     splitAngle=(12, 20, 16, 0), splitAngleV=(6, 10, 10, 0), baseSplits=1, splitBias=0.4,
                     taperCrown=0.3, leafScale=0.4, leafScaleX=0.95, leafDownAngle=48),
        trunk_scale=1.0, relief=0.03,
    ),
}

# Which region each species belongs to (used by the manifest and for sanity checks).
REGION_OF = {
    "oak": "hearthvale", "apple": "hearthvale", "hawthorn": "hearthvale", "yew": "hearthvale",
    "giant_oak": "briarwold", "black_ash": "briarwold",
    "hardy_pine": "skerrow", "rowan": "skerrow", "juniper": "skerrow",
    "willow": "sedgemire", "alder": "sedgemire",
    "dead_ash_tree": "cinderlea", "char_stump": "cinderlea",
    "willow_pollard": "brightwater", "lime": "brightwater",
}


def build_tree(kind: str, pal, rng, params: dict, variant: int, out_dir, name: str, quick: bool):
    spec = dict(SPECIES[kind])
    spec.update({k: v for k, v in params.items() if k in spec or k in ("height", "leaves", "card")})
    h0, h1 = spec["height"]
    height = params.get("height_m") or rng.uniform(h0, h1)
    sap = dict(spec["sapling"])
    sap["scale"] = height
    sap["scaleV"] = height * 0.06
    budget_tier = spec.get("budget", "hero" if spec.get("tier") == "hero" else
                           ("small" if height < 4.0 else "normal"))
    sap = TR.cap_resolution(sap, budget_tier, quick)
    # Sapling's leaf count is per parent branch; ask for plenty and thin to `cards_target`.
    cards_target = int(spec.get("cards_target", 190 if height > 6 else 130) * (0.45 if quick else 1.0))
    if spec.get("leaf_hex"):
        sap["leaves"] = 6
    trunk, leaves = TR.grow(sap, rng.randrange(99999))
    trunk_budget = int(spec.get("trunk_budget", 16000 if spec.get("tier") == "hero" else 7500))
    if quick:
        trunk_budget //= 3
    TR.trim_to_budget(trunk, trunk_budget)

    # bark
    bark_kw = dict(spec.get("bark_kw", {}))
    bark_kw.setdefault("age", 0.4 + 0.4 * rng.random())
    bark = M.by_name(spec["bark"], pal, **bark_kw)
    trunk.data.materials.clear()
    trunk.data.materials.append(bark)
    S.shade_smooth(trunk, 45.0)
    if spec.get("relief") and not quick:
        TR.bark_relief(trunk, strength=spec["relief"] * height / 10.0, scale=0.3 + 0.4 * rng.random(),
                       seed=rng.randrange(999))
    opaque = [trunk]
    if spec.get("buttress") and not quick:
        b = dict(spec["buttress"])
        b["height"] *= height / 30.0
        b["reach"] *= height / 30.0
        b["thickness"] *= height / 30.0
        opaque += TR.buttress(trunk, rng, mat=bark, **b)

    cards = []
    card_tex = {}
    if leaves is not None and spec.get("leaf_hex"):
        cells = spec.get("leaf_cells", 2)
        size = 256 if quick else 512
        atlas_prefix = "%s_leaf" % name
        names = T.leaf_cluster_atlas(
            out_dir, atlas_prefix, P.lin(spec["leaf_hex"]), shapes=spec.get("leaf_shapes", ("oval",)),
            seed=rng.randrange(99999), size=size, cells=cells,
            leaves_per_cell=int(70 * (0.6 if quick else 1.0)), leaf_scale=spec.get("leaf_scale", 0.15),
            autumn=P.lin(spec["autumn_hex"]) if spec.get("autumn_hex") else None,
            autumn_amount=spec.get("autumn", 0.0),
            fruit=P.lin(spec["fruit_hex"]) if spec.get("fruit_hex") else None,
            fruit_r=spec.get("fruit_r", 0.0), fruit_count=spec.get("fruit_count", 0),
            droop=0.25 if spec.get("droop") else 0.0)
        # tint the leaves toward the region's green so each region's canopy differs
        leaf_mat = M.foliage_material("%s_leaf" % name, out_dir / names["albedo"],
                                      out_dir / names["normal"], out_dir / names["orm"])
        leaf_mat["forge_textures"] = dict(names)
        card_tex = dict(names)
        TR.cards_from_leaves(leaves, "%s_leaves" % name, leaf_mat, rng, cells=cells,
                             scale=spec.get("card", 1.0), droop_deg=spec.get("droop", 0.0),
                             target=cards_target)
        cards.append(leaves)
        # weeping curtains (willow) and hanging moss (Briarwold giants)
        if spec.get("weep") and not quick:
            w = dict(spec["weep"])
            pos = TR.card_positions(leaves, int(w.pop("count") * 0.5), rng)
            curtain = TR.hanging_cards(pos, "%s_weep" % name, leaf_mat, rng, cells=cells, **w)
            if curtain:
                cards.append(curtain)
        if spec.get("moss") and not quick:
            mnames = T.moss_strand_atlas(out_dir, "%s_moss" % name, pal.tint(P.lin("#7d8a5a"), "green", 0.35),
                                         seed=rng.randrange(9999), size=256)
            mmat = M.foliage_material("%s_moss" % name, out_dir / mnames["albedo"],
                                      out_dir / mnames["normal"], out_dir / mnames["orm"])
            mmat["forge_textures"] = dict(mnames)
            pos = TR.card_positions(leaves, int(spec["moss"]), rng)
            beard = TR.hanging_cards(pos, "%s_mossbeard" % name, mmat, rng, cells=2,
                                     length=(0.8, 2.6), width=(0.4, 1.0), sway=0.1)
            if beard:
                cards.append(beard)
    elif leaves is not None:
        S.delete([leaves])
    return opaque, cards, card_tex, height, spec


def make_kind(kind: str):
    def builder(pal, rng, params, variant):
        raise RuntimeError("trees use a custom main()")
    return builder


def main():
    args = cli.parse("Wickmere tree generator")
    if args.list:
        for k in sorted(SPECIES):
            print("%s (%s)" % (k, REGION_OF.get(k, "-")))
        return
    kind = args.kind or "oak"
    if kind not in SPECIES:
        raise SystemExit("unknown species %r; --list shows them" % kind)
    pal = P.get_palette(args.palette or REGION_OF.get(kind))
    seed = cli.derive_seed(args.seed, args.variant_index, kind)
    name = args.name or cli.default_name(pal.short, kind, args.variant)
    cli.validate_name(name)
    S.reset()
    import random
    rng = random.Random(seed)
    out_dir = cli.asset_dir(args.out, args.category or "trees", name)
    opaque, cards, card_tex, height, spec = build_tree(kind, pal, rng, dict(args.params), args.variant_index,
                                                       out_dir, name, args.quick)

    # Every card mesh carries its own foliage material; the export joins them and reads
    # each material's `forge_textures` to point the GLB at the drawn atlases.
    card_objs = list(cards)
    baked_objs = []

    # LOD2 impostor: render the assembled tree before it is baked.
    lod2 = None
    impostor_tex = None
    if not args.quick and params_true(args.params, "impostor", True):
        all_parts = list(opaque) + card_objs
        size = 512 if height > 12 else 256
        lod2, impostor_tex = IMP.crossed_cards(all_parts, out_dir, "%s_impostor" % name, name,
                                               size=size, samples=20 if height < 15 else 28)

    meta = E.finish_asset(
        out_root=args.out, category=args.category or "trees", name=name, generator="gen_trees",
        seed=args.seed, kind=kind, params=dict(args.params), pal=pal, opaque_objs=opaque,
        card_objs=card_objs or None, baked_objs=baked_objs or None, collision="capsule",
        collision_params=trunk_capsule(opaque[0], height), quick=args.quick, res=args.res,
        tier=spec.get("tier"), rng=rng, smooth_angle=45.0,
        lod_ratios=(0.45, 0.2), card_keep=(0.55, 0.0), impostor=lod2, impostor_textures=impostor_tex,
        materials_used=[spec["bark"], "foliage_leaf_card"],
        extra_meta={"species": kind, "region": REGION_OF.get(kind, ""), "height_m": round(height, 2)})
    return meta


def params_true(params, key, default):
    v = params.get(key, default)
    return bool(v)


def trunk_capsule(trunk, height):
    lo, hi = S.bounds([trunk])
    # capsule around the trunk only, not the canopy
    r = 0.0
    for v in trunk.data.vertices:
        if v.co.z < height * 0.25:
            r = max(r, math.hypot(v.co.x, v.co.y))
    return {"radius": round(max(0.12, r * 1.05), 3), "height": round(hi.z - lo.z, 2)}


if __name__ == "__main__":
    main()
