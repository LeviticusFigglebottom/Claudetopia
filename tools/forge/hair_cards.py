#!/usr/bin/env python3
"""Hair and beards as strand cards (triage 47), written into the parts already built, without
Blender. lib/hair_cards.py says what a style becomes.

    python3 tools/forge/hair_cards.py --atlas                  # the strand atlas and the cap's grain
    python3 tools/forge/hair_cards.py                          # every style and beard
    python3 tools/forge/hair_cards.py --only long_loose,goatee
    python3 tools/forge/hair_cards.py --dry --only curly        # build and report, write nothing

Each part's GLB keeps its shell (the far level of detail) and gains `<name>_cards`, skinned as the
shell is, with the face's sliders (face_morphs.write_part) and, for a beard, one target per face
(the jaws differ). Its meta gains `"cards"` and the cards' triangles. `character_forge parts` runs
the same after building a hair or a beard, so a rebuilt shell keeps its cards.

The default body's field (for hanging hair to fall over the shoulders) takes a minute and a half in
numpy, and is cached at $FORGE_BODY_CACHE (default: the system temp directory); delete the file when
the body changes."""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import numpy as np

from forge.lib import rig, cloth, sdf, glb, body as bodylib, hair_cards as HC

ROOT = os.path.dirname(os.path.dirname(HERE))
PARTS = os.path.join(ROOT, "game", "assets", "models", "characters")
TEX_DIR = os.path.join(ROOT, "game", "assets", "textures", "characters")
ATLAS = os.path.join(TEX_DIR, "hair_strands.png")
GRAIN = os.path.join(TEX_DIR, "hair_grain.png")
BODY_CACHE = os.environ.get("FORGE_BODY_CACHE", os.path.join(tempfile.gettempdir(), "forge_bodyfield_default.npz"))
# drawn as stubble is, on their shells (HumanoidModel STUBBLE, SHADOW_HAIR): no cards
NO_CARDS = ("shaven", "stubble")


def body_field(skel):
    if BODY_CACHE and os.path.exists(BODY_CACHE):
        z = np.load(BODY_CACHE)
        return sdf.SampledField.from_grid(z["F"], z["origin"], float(z["spacing"]))
    f = cloth.body_field(skel)
    if BODY_CACHE:
        np.savez(BODY_CACHE, F=f.F.astype(np.float32), origin=f.origin, spacing=f.spacing)
    return f


def write_textures() -> None:
    from PIL import Image
    from forge.lib import godot_import as GI
    os.makedirs(TEX_DIR, exist_ok=True)
    a = HC.strand_atlas()
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(ATLAS, optimize=True)
    g = HC.grain_tile()
    Image.fromarray((g * 255 + 0.5).astype(np.uint8), "RGBA").save(GRAIN, optimize=True)
    for path in (ATLAS, GRAIN):
        _sidecar(path, GI)
        print("wrote %s (%d KB)" % (os.path.relpath(path, ROOT), os.path.getsize(path) // 1024))


def _sidecar(path: str, GI) -> None:
    """Lossless, mipmapped, never VRAM-compressed: block compression smears one-pixel strands."""
    res = "res://" + os.path.relpath(path, os.path.join(ROOT, "game")).replace(os.sep, "/")
    text = ('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\nuid="%s"\n\n[deps]\n\nsource_file="%s"\n\n'
            "[params]\n\ncompress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n"
            "compress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n"
            "compress/normal_map=2\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n"
            'roughness/mode=0\nroughness/src_normal=""\nprocess/channel_remap/red=0\n'
            "process/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
            "process/fix_alpha_border=false\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\n"
            "process/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\n"
            "detect_3d/compress_to=0\n") % (GI.godot_uid(res), res)
    with open(path + ".import", "w") as f:
        f.write(GI.complete(text, GI.vram_formats()))


def _shell_reach(path: str, name: str, head) -> float:
    """How far the shell stands off the scalp (its 95th percentile), for a close cut's cards."""
    gltf, b = glb.read_glb(path)
    for m in gltf["meshes"]:
        if m.get("name") == name:
            V = glb.read_array(gltf, b, m["primitives"][0]["attributes"]["POSITION"])
            V = np.stack([V[:, 0], -V[:, 2], V[:, 1]], axis=1)
            d = head.eval(V)
            return float(np.percentile(d[d > 0], 95))
    return 1e9


def build(names, dry: bool = False, verbose: bool = True) -> dict:
    import character_forge as CF
    import face_morphs as FMT
    skel = CF.variant_skeleton(rig.Proportions())
    s = cloth._s(skel)
    report = {}
    need_body = any(n in cloth.HAIR_STYLES and (cloth.HAIR_STYLES[n].release > 0 or cloth.HAIR_STYLES[n].extra)
                    for n in names)
    field = body_field(skel) if need_body or any(n in cloth.BEARD_STYLES for n in names) else None
    face_fits = None
    hv = moves = None
    for name in names:
        t0 = time.time()
        if name in NO_CARDS:
            continue
        if name in cloth.HAIR_STYLES:
            kind, sub = "hair", "hair"
        elif name in cloth.BEARD_STYLES:
            kind, sub = "beard", "beards"
        else:
            print("no hair style or beard called %s" % name)
            continue
        path = os.path.join(PARTS, sub, name, name + ".glb")
        if not os.path.exists(path):
            print("%s: no part at %s (build the shell first: character_forge parts --only %s)" % (name, path, name))
            continue
        targets = {}
        if kind == "hair":
            g = cloth.HAIR_STYLES[name]
            max_off = None
            if name in HC.CLOSE:
                max_off = _shell_reach(path, name, cloth._head_field(skel))
            arrays, rep = HC.build_hair_cards(skel, name, g, body=field, seed=cloth.stable_seed(name), max_off=max_off)
            wfn = None
            if rep["hangs"]:
                wfn = cloth._hair_weights(bodylib.head_landmarks(skel), bodylib.head_landmarks(skel)["nape_z"])
            W = HC.skin_weights(arrays["P"], wfn)
            rep["max_off"] = max_off
        else:
            st = cloth.BEARD_STYLES[name]
            arrays, rep = HC.build_beard_cards(skel, name, st, seed=cloth.stable_seed(name), body=field)
            W = HC.skin_weights(arrays["P"])
            if face_fits is None:
                base_face = cloth.head_field(skel)
                face_fits = {h: (base_face, cloth.head_field(skel, bodylib.HeadStyle.from_dict(p)))
                             for h, p in CF.HEAD_PRESETS.items() if h != "default"}
            for h, (a_, b_) in face_fits.items():
                targets[h] = bodylib.fit_positions(arrays["P"], a_, b_) - arrays["P"]
        rep["seconds"] = round(time.time() - t0, 1)
        report[name] = rep
        if verbose:
            print("%-14s %-5s %5d tris (%d cards, cap %d)  %s  %.0fs" % (
                name, kind, rep["tris"], rep["cards"], rep["cap_tris"],
                " ".join("%s %d" % kv for kv in rep["layers"].items()), rep["seconds"]), flush=True)
        if dry:
            report[name]["arrays"] = arrays
            continue
        tris = HC.attach_cards(path, name, arrays, W, targets)
        if hv is None:
            hv, moves = FMT.default_moves()
        FMT.write_part(path, hv, moves)
        meta_path = path.replace(".glb", ".meta.json")
        meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
        meta.setdefault("materials", {})[name + "_cards"] = "hair_cards"
        meta["cards"] = name + "_cards"
        meta["card_tris"] = tris
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=1, sort_keys=True)
            f.write("\n")
    return report


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma-separated styles and beards (default: all)")
    ap.add_argument("--atlas", action="store_true", help="write the strand atlas and the grain tile")
    ap.add_argument("--dry", action="store_true", help="build and report only")
    args = ap.parse_args(argv)
    if args.atlas:
        write_textures()
        if not args.only:
            return 0
    names = [n for n in args.only.split(",") if n] or (list(cloth.HAIR_STYLES) + list(cloth.BEARD_STYLES))
    build(names, dry=args.dry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
