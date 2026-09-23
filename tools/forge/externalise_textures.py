#!/usr/bin/env python3
"""Take the textures out of GLBs that carry them inside, without rebuilding anything.

    python3 tools/forge/externalise_textures.py                 # every character part
    python3 tools/forge/externalise_textures.py path/to/a.glb   # just these
    python3 tools/forge/externalise_textures.py --check         # report, change nothing

CONTRACTS §4 says a forge asset's textures are PNG files beside its GLB. The character forge
exported every part with its maps embedded, and Godot's scene import, told to extract them
(`gltf/embedded_image_handling=1`), wrote a second copy of every map as `<glb>_<image>.png`
-- uncompressed, because nothing had stamped import settings on the copies -- while the
forge's own PNGs beside it, VRAM-compressed and with the normal maps flagged, were loaded
by nothing at all.

The embedded images are byte-for-byte the forge's PNGs (all 122 were, when this was
written), so the repair is lossless: point each image at its file, drop the embedded copy,
and delete the extracted doubles, which are recognised by being byte-identical to a file
the GLB now references. A PNG that is referenced by nothing but is *not* a copy of anything
is reported and left alone; deciding it is garbage is a person's job.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lib import glb  # noqa: E402

ROOT = HERE.parents[1]
CHARACTERS = ROOT / "game" / "assets" / "models" / "characters"


def doubles_in(folder: Path, referenced: set[str]) -> tuple[list[Path], list[Path]]:
    """(extracted copies of a referenced PNG, PNGs nothing references and nothing copies)."""
    ref_bytes = {}
    for name in referenced:
        f = folder / name
        if f.exists():
            ref_bytes.setdefault(f.read_bytes(), name)
    copies, strays = [], []
    for png in sorted(folder.glob("*.png")):
        if png.name in referenced:
            continue
        if png.read_bytes() in ref_bytes:
            copies.append(png)
        else:
            strays.append(png)
    return copies, strays


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*", help="GLBs or folders (default: every character part)")
    ap.add_argument("--check", action="store_true", help="report only")
    args = ap.parse_args(argv)
    targets: list[Path] = []
    for p in (args.paths or [str(CHARACTERS)]):
        pp = Path(p)
        targets += sorted(pp.rglob("*.glb")) if pp.is_dir() else [pp]
    by_folder: dict[Path, set[str]] = {}
    moved = removed = saved = 0
    for g in targets:
        inside = glb.embedded_images(g)
        if inside and not args.check:
            before = g.stat().st_size
            res = glb.externalise_by_name(g)
            saved += before - g.stat().st_size
            moved += len(inside)
            if res["written"]:
                print("  wrote %s" % ", ".join(res["written"]))
        elif inside:
            print("embeds %d image(s): %s" % (len(inside), g.relative_to(ROOT)))
        # an image still inside the GLB (a --check run) will be referenced by its own name
        by_folder.setdefault(g.parent, set()).update(
            u for u in glb.summary(g)["images"] if u != "<embedded>")
        by_folder[g.parent].update("%s.png" % n for n in glb.embedded_images(g))
    for folder, referenced in sorted(by_folder.items()):
        copies, strays = doubles_in(folder, referenced)
        for c in copies:
            saved += c.stat().st_size
            if args.check:
                print("extracted copy: %s" % c.relative_to(ROOT))
                continue
            c.unlink()
            imp = c.with_name(c.name + ".import")
            if imp.exists():
                imp.unlink()
            removed += 1
        for s in strays:
            print("unreferenced (left alone): %s" % s.relative_to(ROOT))
    verb = "would free" if args.check else "freed"
    print("%d image(s) moved out of %d GLB(s), %d extracted copies removed, %s %.1f MB"
          % (moved, len(targets), removed, verb, saved / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
