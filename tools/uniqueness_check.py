#!/usr/bin/env python3
"""Region drop test, automated proxy.

Given a directory of screenshots named <region>_<anything>.png (HUD off), compute a colour
signature per image (HSV histogram + luminance stats), then check that images cluster by
region: leave-one-out nearest-centroid accuracy must reach --min-accuracy (default 0.8).
Prints the confusion pairs so an art director knows which regions read alike.

Usage: tools/uniqueness_check.py captures/regions [--min-accuracy 0.8] [--json out.json]
"""
import argparse, json, os, sys
from collections import defaultdict
import numpy as np
from PIL import Image


def signature(path: str) -> np.ndarray:
    im = Image.open(path).convert("RGB").resize((160, 90))
    hsv = np.asarray(im.convert("HSV"), dtype=np.float32) / 255.0
    h, s, v = hsv[..., 0].ravel(), hsv[..., 1].ravel(), hsv[..., 2].ravel()
    # weight hue by saturation so grey regions do not get random hues
    hh, _ = np.histogram(h, bins=18, range=(0, 1), weights=s)
    sh, _ = np.histogram(s, bins=8, range=(0, 1))
    vh, _ = np.histogram(v, bins=8, range=(0, 1))
    hh = hh / max(hh.sum(), 1e-6); sh = sh / max(sh.sum(), 1e-6); vh = vh / max(vh.sum(), 1e-6)
    stats = np.array([s.mean(), v.mean(), v.std(), (hsv[..., 0] * hsv[..., 1]).mean()])
    return np.concatenate([hh * 2.0, sh, vh, stats])


def region_of(filename: str) -> str:
    return os.path.basename(filename).split("_")[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--min-accuracy", type=float, default=0.8)
    ap.add_argument("--json")
    a = ap.parse_args()
    files = sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".png"))
    if not files:
        print("no PNG files"); return 2
    sigs = {f: signature(os.path.join(a.dir, f)) for f in files}
    by_region = defaultdict(list)
    for f in files:
        by_region[region_of(f)].append(f)
    regions = sorted(by_region)
    if len(regions) < 2:
        print("need at least two regions"); return 2
    correct = 0
    confusions = defaultdict(int)
    for f in files:
        r = region_of(f)
        cents = {}
        for rr in regions:
            members = [sigs[g] for g in by_region[rr] if g != f]
            if members:
                cents[rr] = np.mean(members, axis=0)
        best = min(cents, key=lambda rr: np.linalg.norm(sigs[f] - cents[rr]))
        if best == r:
            correct += 1
        else:
            confusions[(r, best)] += 1
    acc = correct / len(files)
    # pairwise centroid distances
    cent = {r: np.mean([sigs[g] for g in by_region[r]], axis=0) for r in regions}
    pairs = sorted(((np.linalg.norm(cent[x] - cent[y]), x, y) for i, x in enumerate(regions) for y in regions[i + 1:]))
    print(f"images {len(files)}  regions {len(regions)}  leave-one-out accuracy {acc:.2f}")
    print("closest region pairs (small = easy to confuse):")
    for d, x, y in pairs[:5]:
        print(f"  {x:12s} {y:12s} {d:.3f}")
    if confusions:
        print("misclassified:")
        for (r, b), n in sorted(confusions.items(), key=lambda kv: -kv[1]):
            print(f"  {r} read as {b}: {n}")
    if a.json:
        json.dump({"accuracy": acc, "pairs": [[x, y, float(d)] for d, x, y in pairs], "confusions": {f"{r}->{b}": n for (r, b), n in confusions.items()}}, open(a.json, "w"), indent=2)
    ok = acc >= a.min_accuracy
    print("DROP TEST:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
