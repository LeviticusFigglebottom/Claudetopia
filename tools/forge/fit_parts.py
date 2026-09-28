#!/usr/bin/env python3
"""Fit garments that are already built to another body, as a morph target, without Blender.

    python3 tools/forge/fit_parts.py                      # every grown garment, to the woman's body
    python3 tools/forge/fit_parts.py --only tunic,coat    # some of them
    python3 tools/forge/fit_parts.py --body woman --check # say which lack the fit, change nothing
    python3 tools/forge/fit_parts.py --bust               # the bust slider's targets (item 46)

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

`--bust` writes the woman's bust slider (item 46): the morph target `bust` on her body (her
bust at BUST_FULL of its built size, onto her skin's field over the chest) and `woman_bust` on
every garment fitted to her (the move of the skin under each vertex, as the cloth goes with it). The game sets both
at CharacterAppearance.bust_weight (-1 is the slight end, the same move the other way).
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


BUST_FULL = 1.2
BUST_TARGET = "bust"
GARMENT_BUST_TARGET = "woman_bust"


def _chest_box(skel: Skeleton):
    """The part of her the bust changes, and a margin a fit reaches out over (forge space)."""
    s = skel.props.height / rig.DEFAULT_HEIGHT
    chest = float(skel.J["Chest"][2])
    return (np.array([-0.27 * s, -0.30 * s, chest - 0.23 * s]), np.array([0.27 * s, 0.14 * s, chest + 0.27 * s]))


def _boxed(scene, box, spacing=0.004, reach=0.09):
    from forge.lib import sdf
    F, org, sp = scene.grid(spacing, box=box, reach=reach)
    return sdf.SampledField.from_grid(F, org, sp)


def _womans(size: float):
    skel = CF.variant_skeleton(rig.Proportions.from_dict(CF.BODY_VARIANTS["woman"]))
    style = CF.variant_style("woman")
    style.bust = size
    return skel, style


def bust_fields():
    """(box, her skin at 1, her skin at BUST_FULL), each over the chest box."""
    t0 = time.time()
    box = _chest_box(Skeleton(rig.Proportions()))
    skins = []
    for size in (1.0, BUST_FULL):
        skel, style = _womans(size)
        skins.append(_boxed(bodylib.body_scene(skel, style), box, spacing=0.003, reach=0.03))
    print("bust fields in %.1fs" % (time.time() - t0))
    return [box] + skins


def _inside(V: np.ndarray, box, margin: float = 0.03) -> np.ndarray:
    lo, hi = box
    return np.all((V > lo + margin) & (V < hi - margin), axis=1)


def _skinned_positions(gltf, bin_chunk):
    for mi in sorted({n["mesh"] for n in gltf.get("nodes", []) if "mesh" in n and "skin" in n}):
        rows = []
        for p in gltf["meshes"][mi]["primitives"]:
            rows.extend(glb.read_accessor(gltf, bin_chunk, p["attributes"]["POSITION"]))
        yield mi, np.asarray(rows, float)


def bust_body(path: str, fields) -> float:
    """The `bust` target on her body: each skin vertex over the chest onto her skin at BUST_FULL."""
    box, skin1, skin2 = fields
    gltf, bin_chunk = glb.read_glb(path)
    worst = 0.0
    for mi, rows in list(_skinned_positions(gltf, bin_chunk)):
        V = to_forge(rows)
        moved = np.zeros_like(V)
        ins = _inside(V, box)
        moved[ins] = bodylib.fit_positions(V[ins], skin1, skin2, reach=0.02, fade=0.01) - V[ins]
        bin_chunk = glb.set_morph_target(gltf, bin_chunk, mi, BUST_TARGET, to_gltf(moved).tolist())
        worst = max(worst, float(np.linalg.norm(moved, axis=1).max()))
    glb.write_glb(path, gltf, bin_chunk)
    return worst * 1000.0


def body_bust_move():
    """Her skin as built (forge space) and its `bust` move, off her built body."""
    path = os.path.join(CF.OUT_ROOT, "bodies", "woman", "woman.glb")
    gltf, bin_chunk = glb.read_glb(path)
    for mi, rows in _skinned_positions(gltf, bin_chunk):
        names = glb.morph_target_names(gltf, mi)
        if BUST_TARGET not in names:
            continue
        p = gltf["meshes"][mi]["primitives"][0]
        d = glb.read_array(gltf, bin_chunk, p["targets"][names.index(BUST_TARGET)]["POSITION"])
        return to_forge(rows), to_forge(np.asarray(d, float))
    raise SystemExit("her body has no bust target: build it (parts --only woman) or run --bust with the body")


def bust_file(path: str, skin, near: float = 0.060, far: float = 0.110, k: int = 8) -> dict:
    """`woman_bust` on a garment fitted to her: cloth goes with the skin under it. Each vertex, as
    fitted to her, takes the bust's move of the skin nearest it (a weighted mean of the nearest
    few, fading to nothing from `near` to `far` off her): a garment re-fitted to the fuller body
    moved most of its vertices a centimetre and a few of them five, stepped along a field inside
    the bust towards whichever side of it was nearest, and the cloth would have torn there."""
    from scipy.spatial import cKDTree
    BV, BD = skin
    tree = cKDTree(BV)
    gltf, bin_chunk = glb.read_glb(path)
    report = {}
    for mi, rows in list(_skinned_positions(gltf, bin_chunk)):
        V = to_forge(rows)
        names = glb.morph_target_names(gltf, mi)
        if "woman" in names:
            fit = [glb.read_array(gltf, bin_chunk, p["targets"][names.index("woman")]["POSITION"])
                   for p in gltf["meshes"][mi]["primitives"]]
            V = V + to_forge(np.concatenate([np.asarray(f, float).reshape(-1, 3) for f in fit]))
        d, i = tree.query(V, k=k)
        w = 1.0 / np.maximum(d, 0.002) ** 2
        moved = np.einsum("nk,nkc->nc", w, BD[i]) / w.sum(axis=1, keepdims=True)
        moved *= (1.0 - np.clip((d[:, 0] - near) / (far - near), 0.0, 1.0))[:, None]
        bin_chunk = glb.set_morph_target(gltf, bin_chunk, mi, GARMENT_BUST_TARGET, to_gltf(moved).tolist())
        n = np.linalg.norm(moved, axis=1)
        report[gltf["meshes"][mi].get("name", str(mi))] = (len(V), int((n > 1e-4).sum()), float(n.max() * 1000))
    glb.write_glb(path, gltf, bin_chunk)
    return report


def write_bust(only=None, body: bool = True, clothes: bool = True) -> None:
    if body:
        path = os.path.join(CF.OUT_ROOT, "bodies", "woman", "woman.glb")
        if os.path.exists(path):
            print("woman body: bust at most %.1f mm" % bust_body(path, bust_fields()))
    if not clothes:
        return
    skin = body_bust_move()
    for name, path, meta_path in garments(only):
        if "woman" not in json.load(open(meta_path)).get("fits", []):
            continue
        for mesh, (nv, nm, mx) in bust_file(path, skin).items():
            print("%-14s %-18s %5d vertices, %5d move with her bust, at most %4.1f mm" % (name, mesh, nv, nm, mx))


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
        moved = bodylib.fit_positions(V, base, target, snug=CF._snug(body, Skeleton(rig.Proportions()))) - V
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
    ap.add_argument("--bust", action="store_true", help="write the bust slider's targets (her body and her fits)")
    ap.add_argument("--no-body", action="store_true", help="with --bust: the garments only")
    args = ap.parse_args(argv)
    only = set(filter(None, args.only.split(",")))
    if args.bust:
        write_bust(only, body=not args.no_body)
        return 0
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
