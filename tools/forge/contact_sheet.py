#!/usr/bin/env python3
"""Tile the renders from game/tools_gd/asset_review into one contact sheet per category.

    python3 tools/forge/contact_sheet.py captures/assets/trees [--cols 3] [--width 1800]

A sheet is what makes a category reviewable at a glance: whether the silhouettes differ,
whether the palette holds, whether one asset is the wrong scale. Written next to the
renders as _sheet.png (plus _sheet_<angle>.png when several angles are present).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ANGLE_RE = re.compile(r"_(three_quarter|front|high|turn\d+)$")
BG = (38, 40, 45)
FG = (226, 222, 212)


def _font(size: int):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/TTF/DejaVuSans.ttf",
              "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def angle_of(stem: str) -> str:
    m = ANGLE_RE.search(stem)
    return m.group(1) if m else ""


def sheet(paths: list[Path], out: Path, cols: int, width: int, title: str) -> Path:
    if not paths:
        raise SystemExit("no images for %s" % title)
    cols = max(1, min(cols, len(paths)))
    rows = (len(paths) + cols - 1) // cols
    cell_w = width // cols
    with Image.open(paths[0]) as probe:
        aspect = probe.size[1] / probe.size[0]
    cell_h = int(cell_w * aspect)
    label_h = max(18, cell_w // 26)
    head_h = label_h + 12
    sheet_img = Image.new("RGB", (cell_w * cols, head_h + rows * (cell_h + label_h)), BG)
    draw = ImageDraw.Draw(sheet_img)
    draw.text((10, 6), title, fill=FG, font=_font(label_h))
    for i, p in enumerate(paths):
        r, c = divmod(i, cols)
        x = c * cell_w
        y = head_h + r * (cell_h + label_h)
        with Image.open(p) as im:
            sheet_img.paste(im.convert("RGB").resize((cell_w, cell_h), Image.LANCZOS), (x, y))
        draw.text((x + 6, y + cell_h + 2), p.stem, fill=FG, font=_font(max(11, label_h - 4)))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet_img.save(out, optimize=True)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Contact sheets for forge review renders")
    ap.add_argument("directory", help="directory of PNGs (captures/assets/<category>)")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--width", type=int, default=1800)
    ap.add_argument("--per-angle", action="store_true", help="also write one sheet per camera angle")
    ap.add_argument("--glob", default="*.png", help="which PNGs to include (default all)")
    args = ap.parse_args(argv)

    d = Path(args.directory)
    files = sorted(p for p in d.glob(args.glob) if not p.stem.startswith("_sheet"))
    if not files:
        print("no renders in %s" % d)
        return 1
    made = [sheet(files, d / "_sheet.png", args.cols, args.width, d.name)]
    if args.per_angle:
        angles: dict[str, list[Path]] = {}
        for f in files:
            angles.setdefault(angle_of(f.stem) or "other", []).append(f)
        for a, ps in sorted(angles.items()):
            made.append(sheet(ps, d / ("_sheet_%s.png" % a), args.cols, args.width, "%s / %s" % (d.name, a)))
    for m in made:
        print(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
