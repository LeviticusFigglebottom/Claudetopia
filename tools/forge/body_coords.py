#!/usr/bin/env python3
"""Write each body's rest position into the body as extra UV sets, for tattoos drawn in the engine
(triage 48), without Blender.

    python3 tools/forge/body_coords.py              # the rig's body and every body variant
    python3 tools/forge/body_coords.py --check      # say which lack them, change nothing

A body's own UVs are a smart projection, laid out again on every build, so nothing can be placed by
them. A tattoo is placed in the rig's bone space instead: the engine's shader
(game/assets/shaders/body_marks.gdshader) takes a design's frame on a bone (a forearm's axis, the
spine's) and projects round it. To do that it needs where each vertex is in the pose the body was
bound in, which the skinned vertex in the shader no longer knows. So every body mesh carries its
bind-pose position (glTF metres, +Z forward) as TEXCOORD_2 (x, y) and TEXCOORD_3 (z, 0), which Godot
imports as CUSTOM0 (x, y, z, 0). The positions are the mesh's own, so the attribute follows any
rebuild of the body as long as this runs after it (`character_forge rig` and `parts` do).
"""
from __future__ import annotations

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import numpy as np

from forge.lib import glb

ROOT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "assets", "models", "characters")
BODY_MESH = "Body"
ATTRS = ("TEXCOORD_2", "TEXCOORD_3")


def body_files():
    rig = os.path.join(ROOT, "humanoid_rig", "humanoid_rig.glb")
    if os.path.exists(rig):
        yield rig
    bodies = os.path.join(ROOT, "bodies")
    if os.path.isdir(bodies):
        for name in sorted(os.listdir(bodies)):
            p = os.path.join(bodies, name, name + ".glb")
            if os.path.exists(p):
                yield p


def _body_meshes(gltf: dict) -> list:
    return [i for i, m in enumerate(gltf.get("meshes", []))
            if m.get("name", "").startswith(BODY_MESH) and len(m.get("primitives", [])) == 1]


def has_coords(path: str) -> bool:
    gltf, _ = glb.read_glb(path)
    meshes = _body_meshes(gltf)
    return bool(meshes) and all(all(a in gltf["meshes"][i]["primitives"][0]["attributes"] for a in ATTRS)
                                for i in meshes)


def rest_coords(V: np.ndarray) -> tuple:
    """(TEXCOORD_2, TEXCOORD_3) rows for bind-pose positions V (n, 3), glTF space."""
    V = np.asarray(V, float)
    return V[:, 0:2].copy(), np.stack([V[:, 2], np.zeros(len(V))], axis=1)


def write(path: str) -> int:
    """Writes the coordinates into every body mesh of the GLB; returns how many vertices."""
    gltf, bin_chunk = glb.read_glb(path)
    n = 0
    for mi in _body_meshes(gltf):
        p = gltf["meshes"][mi]["primitives"][0]
        V = glb.read_array(gltf, bin_chunk, p["attributes"]["POSITION"])
        a, b = rest_coords(V)
        bin_chunk = glb.set_attribute(gltf, bin_chunk, mi, ATTRS[0], a)
        bin_chunk = glb.set_attribute(gltf, bin_chunk, mi, ATTRS[1], b)
        n += len(V)
    if n:
        bin_chunk = glb.compact(gltf, bin_chunk)
        glb.write_glb(path, gltf, bin_chunk)
    return n


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="list the bodies without the coordinates; exit 1 if any")
    args = ap.parse_args(argv)
    if args.check:
        missing = [os.path.relpath(p, ROOT) for p in body_files() if not has_coords(p)]
        print("bodies without rest coordinates: %s" % (", ".join(missing) or "none"))
        return 1 if missing else 0
    for p in body_files():
        print("%-40s %6d vertices" % (os.path.relpath(p, ROOT), write(p)), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
