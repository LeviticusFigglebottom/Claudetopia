#!/usr/bin/env python3
"""The bow drawn, as a morph target on the bows the forge has already made (triage 55).

    python3 tools/forge/bow_draw_morph.py            # every weapons/bow_* GLB
    python3 tools/forge/bow_draw_morph.py --check    # say which lack it, change nothing

A bow in the game bends as it is drawn. The GLB is the one gen_weapons.bow built (glTF axes): the
stave along Z through the grip at the origin, the arrow's way +Y, the string behind the grip at
y = -BRACE between the nocks, one straight tube. Two morph targets:
  * `drawn`: the limbs bend back and in along their length (the square of the distance out from
    the grip), the tips TIP_BACK further back and TIP_IN nearer the middle, the nocks with them;
    HeldItems.BowString sets it at the share of the draw the string hand has pulled;
  * `unstrung`: the forge's string drawn in onto its own line, where it has no width. A straight
    tube cannot bend into a V round the fingers, so while the bow is in a hand the game draws the
    string itself, from nock to nock through the string hand (BowString), and turns this on.
The grip does not move. Written into the file beside what is there, like fit_parts' morphs, on
each LOD, so the bow reviewed is the bow in the game. Pure Python, no Blender.
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from forge.lib import glb  # noqa: E402

WEAPONS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "assets", "models", "weapons")
NAME = "drawn"
UNSTRUNG = "unstrung"
BRACE = 0.1296            # gen_weapons.bow: the string at -brace * 0.9 behind the grip

TIP_BACK = 0.15
TIP_IN = 0.09
GRIP_HALF = 0.06          # the bound grip, which does not bend
STRING_R = 0.004          # a vertex this near the string's line is the string's


def bows() -> list:
    out = []
    for name in sorted(os.listdir(WEAPONS)):
        if name.startswith("bow_"):
            out.append(os.path.join(WEAPONS, name, name + ".glb"))
    return out


def string_verts(v: np.ndarray) -> np.ndarray:
    """Which vertices are the string's: on its line behind the grip, short of the nocks."""
    return (np.abs(v[:, 0]) < STRING_R) & (np.abs(v[:, 1] + BRACE) < STRING_R)


def draw_move(v: np.ndarray) -> np.ndarray:
    """The move of every vertex (glTF axes) at full draw: the limbs, the nocks and the string's ends
    bent back and in by the square of the way out from the grip."""
    v = np.asarray(v, float)
    half = float(np.abs(v[:, 2]).max())
    d = np.zeros_like(v)
    f = np.clip((np.abs(v[:, 2]) - GRIP_HALF) / max(half - GRIP_HALF, 1e-6), 0.0, 1.0) ** 2
    d[:, 1] = -TIP_BACK * f
    d[:, 2] = -np.sign(v[:, 2]) * TIP_IN * f
    return d


def unstrung_move(v: np.ndarray) -> np.ndarray:
    """The string's tube drawn in onto its own line, where it has no width and is not seen: the
    forge's string is one straight tube between the nocks, with nothing in its middle to bend, so
    the game draws the string itself while the bow is in hand (HeldItems.BowString)."""
    v = np.asarray(v, float)
    d = np.zeros_like(v)
    on = string_verts(v)
    d[on, 0] = -v[on, 0]
    d[on, 1] = -BRACE - v[on, 1]
    return d


def write(path: str, check: bool = False) -> str:
    gltf, bin_chunk = glb.read_glb(path)
    have = [NAME in glb.morph_target_names(gltf, i) and UNSTRUNG in glb.morph_target_names(gltf, i)
            for i in range(len(gltf["meshes"]))]
    if check:
        return "%s: %s" % (os.path.basename(path), "drawn" if all(have) else "no draw")
    for mi, mesh in enumerate(gltf["meshes"]):
        v = glb.read_array(gltf, bin_chunk, mesh["primitives"][0]["attributes"]["POSITION"])
        bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, mi, NAME, draw_move(v))
        bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, mi, UNSTRUNG, unstrung_move(v))
    bin_chunk = glb.compact(gltf, bin_chunk)
    glb.write_glb(path, gltf, bin_chunk)
    return "%s: drawn on %d meshes" % (os.path.basename(path), len(gltf["meshes"]))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    for p in bows():
        print(write(p, args.check))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
