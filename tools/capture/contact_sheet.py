#!/usr/bin/env python3
"""Tile capture PNGs into one labelled contact sheet.

    tools/capture/contact_sheet.py [captures] [--out captures/contact_sheet.jpg] [--cols 3]

Reads <dir>/*.png (in name order, which is shot order) and, if present, <dir>/perf.json, so
each tile is labelled with its shot and its draw-call / primitive cost. This is the sheet the
region drop test (DESIGN.md §10) is judged from.
"""
from __future__ import annotations

import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

LABEL_H = 26
PAD = 6
BG = (18, 18, 20)
FG = (238, 230, 214)
DIM = (150, 146, 138)


def _font(size: int):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def build(src: str, out: str, cols: int, width: int) -> str:
    names = sorted(f for f in os.listdir(src)
                   if f.lower().endswith(".png") and os.path.isfile(os.path.join(src, f)))
    if not names:
        raise SystemExit("no PNGs in %s" % src)
    perf = {}
    perf_path = os.path.join(src, "perf.json")
    if os.path.exists(perf_path):
        with open(perf_path, "r", encoding="utf-8") as f:
            doc = json.load(f)
        perf = {s["file"]: s for s in doc.get("shots", [])}
    first = Image.open(os.path.join(src, names[0]))
    tile_w = width // cols - PAD
    tile_h = int(tile_w * first.height / first.width)
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tile_w + PAD) + PAD, rows * (tile_h + LABEL_H + PAD) + PAD), BG)
    draw = ImageDraw.Draw(sheet)
    font = _font(14)
    small = _font(11)
    for i, name in enumerate(names):
        img = Image.open(os.path.join(src, name)).convert("RGB").resize((tile_w, tile_h), Image.LANCZOS)
        x = PAD + (i % cols) * (tile_w + PAD)
        y = PAD + (i // cols) * (tile_h + LABEL_H + PAD)
        sheet.paste(img, (x, y))
        label = os.path.splitext(name)[0]
        draw.text((x + 2, y + tile_h + 3), label, fill=FG, font=font)
        info = perf.get(name)
        if info:
            note = "%d draws · %.2f M prims · %s" % (
                info.get("draw_calls", 0), info.get("primitives", 0) / 1e6,
                str(info.get("region", "")).split("/")[-1])
            draw.text((x + 2, y + tile_h + 16), note, fill=DIM, font=small)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    sheet.save(out, quality=88)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?", default="captures")
    ap.add_argument("--out", default=None)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--width", type=int, default=1680)
    args = ap.parse_args()
    out = args.out or os.path.join(args.dir, "contact_sheet.jpg")
    path = build(args.dir, out, args.cols, args.width)
    print("[sheet] %s" % path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
