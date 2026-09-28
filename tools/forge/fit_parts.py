#!/usr/bin/env python3
"""Fit garments that are already built to another body, as a morph target, without Blender.

    python3 tools/forge/fit_parts.py                      # every grown garment, to the woman's body
    python3 tools/forge/fit_parts.py --only tunic,coat    # some of them
    python3 tools/forge/fit_parts.py --body woman --check # say which lack the fit, change nothing

`character_forge parts` fits a garment as it builds it (`ALWAYS_FITTED`, and `--fits` for the
heavy and the slight body). This does the same fit afterwards, on the GLB: every vertex keeps the
distance it had from the default body, measured from the other one and the drape cloth hangs
over it (`body.fit_positions` against `cloth.fit_field`, as the forge fits), and the move goes
into the file as a morph target named after the body, beside the grip morphs a glove already has.
Nothing else in the file changes, so the garment is the one that was reviewed, not a rebuild of
it under another Blender (README, "Which Blender").

A part rigid to one bone (a helm, a hood) is left alone, as the forge leaves it: it rides the
head, which is the same on every body. So are a child's cuts, which are on the child's skeleton.
HumanoidModel wears a body under a garment only when the garment's meta lists the body in `fits`.
"""
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

from forge.lib import rig, glb, body as bodylib, cloth as clothlib
from forge.lib.rig import Skeleton
import character_forge as CF

CLOTHING = os.path.join(CF.OUT_ROOT, "clothing")


def to_forge(v: np.ndarray) -> np.ndarray:
    """glTF (Y up, +Z forward) -> the forge's Blender space (Z up, -Y forward)."""
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)


def to_gltf(v: np.ndarray) -> np.ndarray:
    return np.stack([v[:, 0], v[:, 2], -v[:, 1]], axis=1)


def garments(only=None):
    """(name, glb path, meta path) for every grown, skinned garment."""
    for name in sorted(os.listdir(CLOTHING)):
        if name.endswith("_child") or (only and name not in only):
            continue
        path = os.path.join(CLOTHING, name, name + ".glb")
        meta_path = os.path.join(CLOTHING, name, name + ".meta.json")
        if not (os.path.exists(path) and os.path.exists(meta_path)):
            continue
        meta = json.load(open(meta_path))
        if (meta.get("params") or {}).get("bone"):
            continue
        yield name, path, meta_path


def body_fields(body: str):
    style = bodylib.BodyStyle()
    t0 = time.time()
    # measured from both bodies the same way (cloth.fit_field): the build's own body field is
    # read off its primitives' bounds, a few centimetres out
    base = clothlib.fit_field(Skeleton(rig.Proportions()), style)
    target = clothlib.fit_field(CF.variant_skeleton(rig.Proportions.from_dict(CF.BODY_VARIANTS[body])),
                               CF.variant_style(body))
    print("body fields in %.1fs" % (time.time() - t0))
    return base, target


def fit_file(path: str, body: str, base, target) -> dict:
    """Writes the target into the GLB; returns {mesh: (vertices, moved, largest move in mm)}."""
    gltf, bin_chunk = glb.read_glb(path)
    skinned = {n["mesh"] for n in gltf.get("nodes", []) if "mesh" in n and "skin" in n}
    report = {}
    for mi in sorted(skinned):
        rows = []
        for p in gltf["meshes"][mi]["primitives"]:
            rows.extend(glb.read_accessor(gltf, bin_chunk, p["attributes"]["POSITION"]))
        V = to_forge(np.asarray(rows, float))
        moved = bodylib.fit_positions(V, base, target) - V
        d = to_gltf(moved)
        bin_chunk = glb.set_morph_target(gltf, bin_chunk, mi, body, d.tolist())
        n = np.linalg.norm(moved, axis=1)
        report[gltf["meshes"][mi].get("name", str(mi))] = (len(V), int((n > 1e-4).sum()), float(n.max() * 1000))
    glb.write_glb(path, gltf, bin_chunk)
    return report


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--body", default="woman", choices=sorted(k for k in CF.BODY_VARIANTS if k not in ("default", "child")))
    ap.add_argument("--only", default="", help="comma-separated garment names")
    ap.add_argument("--check", action="store_true", help="list the garments without the fit and exit 1 if any")
    args = ap.parse_args(argv)
    only = set(filter(None, args.only.split(",")))
    todo = list(garments(only))
    if args.check:
        missing = [n for n, _, m in todo if args.body not in json.load(open(m)).get("fits", [])]
        print("without the %s fit: %s" % (args.body, ", ".join(missing) or "none"))
        return 1 if missing else 0
    base, target = body_fields(args.body)
    for name, path, meta_path in todo:
        report = fit_file(path, args.body, base, target)
        meta = json.load(open(meta_path))
        meta["fits"] = sorted(set(meta.get("fits", [])) | {args.body})
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=1, sort_keys=True)
        for mesh, (nv, nm, mx) in report.items():
            print("%-14s %-18s %5d vertices, %5d moved, at most %4.1f mm" % (name, mesh, nv, nm, mx))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
