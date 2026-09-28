#!/usr/bin/env python3
"""Write the face's sliders into the heads already built, and carry them onto what is worn over
the face, as morph targets, without Blender (triage 39; lib/face_morphs.py says how they are made).

    python3 tools/forge/face_morphs.py                    # every head, then the parts over the face
    python3 tools/forge/face_morphs.py --heads default,hawk_f
    python3 tools/forge/face_morphs.py --parts-only       # the hair, beards and hoods alone
    python3 tools/forge/face_morphs.py --check            # say which lack them, change nothing

`character_forge parts` runs the same on every head and every hair, beard and hood it builds, so a
rebuilt head keeps its sliders. Each head gets one target per slider (`face_<slider>`) and
`face_age`, its eyes the ones that move them (the size and the spacing), and a second UV set of
face coordinates for marks drawn in the engine (scars, moles, paint). The rest of the file is
left as it was: the textures and the asymmetry targets are the build's.

Parts over the face take the default head's moves, carried to each of their vertices from the
skin under it: every hair style, every beard, and the helm, the hood and the hooded cloaks."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import numpy as np

from forge.lib import rig, glb, body as bodylib, face_morphs as FM
import character_forge as CF

ROOT = CF.OUT_ROOT
HEADS = os.path.join(ROOT, "heads")
# what lies over the face and must go with it: (directory, names or None for all of them)
OVER_THE_FACE = [("hair", None), ("beards", None), ("clothing", ["helm", "hood", "hooded_cloak", "ragged_cloak"])]


def to_forge(v: np.ndarray) -> np.ndarray:
    """glTF (Y up, +Z forward) -> the forge's Blender space (Z up, -Y forward)."""
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)


def to_gltf(v: np.ndarray) -> np.ndarray:
    return np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1)


def head_style(name: str):
    base = name[:-len(CF.FEMININE_HEAD)] if name.endswith(CF.FEMININE_HEAD) else name
    fem = 1.0 if name.endswith(CF.FEMININE_HEAD) else 0.0
    return base, bodylib.HeadStyle.from_dict(CF.HEAD_PRESETS.get(base, {})), fem


def head_skeleton(fem: float):
    return CF.variant_skeleton(rig.Proportions(feminine=fem))


def _mesh_index(gltf: dict, pred) -> list:
    return [i for i, m in enumerate(gltf.get("meshes", [])) if pred(m.get("name", ""))]


def _positions(gltf, bin_chunk, mi):
    p = gltf["meshes"][mi]["primitives"][0]
    V = to_forge(glb.read_array(gltf, bin_chunk, p["attributes"]["POSITION"]))
    T = glb.read_array(gltf, bin_chunk, p["indices"]).astype(int).reshape(-1, 3) if "indices" in p else \
        np.arange(len(V)).reshape(-1, 3)
    return V, T


def has_sliders(path: str) -> bool:
    gltf, _ = glb.read_glb(path)
    for mi in _mesh_index(gltf, lambda n: n.startswith("Head")):
        return all(FM.target_name(t) in glb.morph_target_names(gltf, mi) for t in FM.TARGETS)
    return False


def head_moves(path: str, name: str):
    """(skeleton, style, V, T, {target: move}) for a built head: its mesh and its sliders' moves."""
    _, hs, fem = head_style(name)
    skel = head_skeleton(fem)
    gltf, bin_chunk = glb.read_glb(path)
    mi = _mesh_index(gltf, lambda n: n.startswith("Head"))[0]
    V, T = _positions(gltf, bin_chunk, mi)
    moves, _ = FM.head_targets(skel, hs, V, T)
    return skel, hs, V, T, moves


def write_head(path: str, name: str, only=None) -> dict:
    """Writes the head's targets, its eyes' and its face coordinates into the GLB."""
    _, hs, fem = head_style(name)
    skel = head_skeleton(fem)
    gltf, bin_chunk = glb.read_glb(path)
    mi = _mesh_index(gltf, lambda n: n.startswith("Head"))[0]
    V, T = _positions(gltf, bin_chunk, mi)
    eyes = {}
    for side, sx in (("L", 1.0), ("R", -1.0)):
        e = _mesh_index(gltf, lambda n, side=side: n == "Eye_%s" % side)
        if e:
            eyes[sx] = (e[0], _positions(gltf, bin_chunk, e[0])[0])
    moves, eye_moves = FM.head_targets(skel, hs, V, T, {sx: E for sx, (_, E) in eyes.items()}, only=only)
    report = {}
    for t, M in moves.items():
        N = FM.normal_moves(V, T, M)
        bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, mi, FM.target_name(t), to_gltf(M), to_gltf(N))
        report[t] = float(np.linalg.norm(M, axis=1).max() * 1000.0)
    for sx, (e, E) in eyes.items():
        for t, M in eye_moves.get(sx, {}).items():
            bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, e, FM.target_name(t), to_gltf(M))
    bin_chunk = glb.set_attribute(gltf, bin_chunk, mi, "TEXCOORD_1", FM.face_coords(skel, hs, V))
    bin_chunk = glb.compact(gltf, bin_chunk)
    glb.write_glb(path, gltf, bin_chunk)
    return report


def write_part(path: str, head_V: np.ndarray, moves: dict) -> dict:
    """The face's targets carried onto every mesh of a part worn over it."""
    gltf, bin_chunk = glb.read_glb(path)
    report = {}
    for mi, m in enumerate(gltf.get("meshes", [])):
        if len(m.get("primitives", [])) != 1:
            continue
        V, _ = _positions(gltf, bin_chunk, mi)
        carried = FM.transfer(head_V, moves, V)
        moved = 0
        for t, M in carried.items():
            bin_chunk = glb.add_sparse_morph_target(gltf, bin_chunk, mi, FM.target_name(t), to_gltf(M))
            moved = max(moved, int((np.linalg.norm(M, axis=1) > 2e-5).sum()))
        report[m.get("name", str(mi))] = (len(V), moved)
    bin_chunk = glb.compact(gltf, bin_chunk)
    glb.write_glb(path, gltf, bin_chunk)
    return report


def heads(only=None):
    for name in sorted(os.listdir(HEADS)):
        path = os.path.join(HEADS, name, name + ".glb")
        if os.path.exists(path) and (not only or name in only):
            yield name, path


def parts(only=None):
    for kind, names in OVER_THE_FACE:
        d = os.path.join(ROOT, kind)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if names is not None and name not in names:
                continue
            if only and name not in only:
                continue
            path = os.path.join(d, name, name + ".glb")
            if os.path.exists(path):
                yield kind, name, path


def default_moves():
    """The default (man's) head's moves, which the parts over the face take."""
    path = os.path.join(HEADS, "default", "default.glb")
    _, _, V, _, moves = head_moves(path, "default")
    return V, moves


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--heads", default="", help="comma-separated head names (default: all)")
    ap.add_argument("--parts", default="", help="comma-separated part names (default: all over the face)")
    ap.add_argument("--parts-only", action="store_true")
    ap.add_argument("--heads-only", action="store_true")
    ap.add_argument("--check", action="store_true", help="list the heads without the sliders and exit 1 if any")
    args = ap.parse_args(argv)
    only_heads = set(filter(None, args.heads.split(",")))
    only_parts = set(filter(None, args.parts.split(",")))
    if args.check:
        missing = [n for n, p in heads(only_heads) if not has_sliders(p)]
        print("heads without the sliders: %s" % (", ".join(missing) or "none"))
        return 1 if missing else 0
    if not args.parts_only:
        for name, path in heads(only_heads):
            t0 = time.time()
            rep = write_head(path, name)
            print("%-14s %s  (%.0fs)" % (name, " ".join("%s %.1f" % (k, v) for k, v in rep.items()), time.time() - t0),
                  flush=True)
    if not args.heads_only:
        V, moves = default_moves()
        for kind, name, path in parts(only_parts):
            rep = write_part(path, V, moves)
            for mesh, (nv, nm) in rep.items():
                print("%-9s %-14s %-18s %5d vertices, %5d go with the face" % (kind, name, mesh, nv, nm), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
