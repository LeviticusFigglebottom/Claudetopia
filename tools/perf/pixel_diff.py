#!/usr/bin/env python3
"""Pixel-diffs two capture folders shot from one plan: for each PNG present in both, the share of
pixels that differ by more than a threshold (0-255 on any channel), the mean absolute difference,
and the largest. Writes an amplified difference image for any pair over --save-over.

    python3 tools/perf/pixel_diff.py <before dir> <after dir> [--threshold 8] [--out <dir>]
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('a')
    ap.add_argument('b')
    ap.add_argument('--threshold', type=int, default=8)
    ap.add_argument('--out', default='')
    ap.add_argument('--save-over', type=float, default=0.5, help='percent of pixels changed')
    args = ap.parse_args()
    rows = []
    for name in sorted(os.listdir(args.a)):
        if not name.endswith('.png') or not os.path.exists(os.path.join(args.b, name)):
            continue
        x = np.asarray(Image.open(os.path.join(args.a, name)).convert('RGB')).astype(np.int16)
        y = np.asarray(Image.open(os.path.join(args.b, name)).convert('RGB')).astype(np.int16)
        if x.shape != y.shape:
            rows.append({'shot': name, 'error': 'size'})
            continue
        d = np.abs(x - y).max(axis=2)
        changed = float((d > args.threshold).mean() * 100.0)
        row = {'shot': name, 'changed_pct': round(changed, 3), 'mean_abs': round(float(d.mean()), 3),
               'max': int(d.max())}
        rows.append(row)
        if args.out and changed > args.save_over:
            os.makedirs(args.out, exist_ok=True)
            Image.fromarray(np.clip(d * 4, 0, 255).astype(np.uint8)).save(os.path.join(args.out, 'diff_' + name))
    for r in rows:
        print(json.dumps(r))
    return 0


if __name__ == '__main__':
    sys.exit(main())
