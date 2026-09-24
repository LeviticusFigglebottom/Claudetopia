#!/usr/bin/env python3
"""One contact sheet per motion-studio sequence: its frames cropped and tiled in shot order.

    tools/capture/motion_sheets.py <film dir> <sheet dir> [columns]

A film holds <label>_<nn>.png for each sequence of the plan (tools/capture/film_motion.sh). The
feet views are cropped to the body, the others to the middle of the frame, and each tile is
numbered with its shot.
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw

# (left, top, right, bottom) on a 1280x720 frame, by the sequence's label
CROPS = {
    "quarter_turn": (380, 60, 900, 520),
    "about_face": (330, 60, 950, 520),
    "jog_stop": (380, 60, 900, 520),
}
WIDE = (160, 0, 1120, 720)
SHEET_W = 1400


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 1
    src = pathlib.Path(argv[1])
    out = pathlib.Path(argv[2])
    cols = int(argv[3]) if len(argv) > 3 else 6
    out.mkdir(parents=True, exist_ok=True)
    seqs = sorted({p.stem.rsplit("_", 1)[0] for p in src.glob("*_[0-9][0-9].png")})
    for seq in seqs:
        frames = sorted(src.glob(f"{seq}_[0-9][0-9].png"))
        box = CROPS.get(seq, WIDE)
        w, h = box[2] - box[0], box[3] - box[1]
        scale = min(1.0, SHEET_W / (cols * w))
        tw, th = int(w * scale), int(h * scale)
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * th), "white")
        draw = ImageDraw.Draw(sheet)
        for i, f in enumerate(frames):
            im = Image.open(f).convert("RGB").crop(box).resize((tw, th), Image.LANCZOS)
            x, y = (i % cols) * tw, (i // cols) * th
            sheet.paste(im, (x, y))
            draw.text((x + 4, y + 4), f.stem.rsplit("_", 1)[1], fill="black")
        sheet.save(out / f"{seq}.png")
        print(seq, len(frames), sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
