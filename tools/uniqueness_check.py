#!/usr/bin/env python3
"""Region drop test, automated proxy.

Given a directory of screenshots named <region>_<anything>.png (HUD off), ask the question a
player asks on being dropped somewhere with the HUD off: *do I know where I am?* Two things
answer it, and they answer it separately.

**Colour** is the palette: hue weighted by saturation, saturation and value histograms, and
the luminance statistics. It is the easy half, and a region can pass it by being tinted.

**Landform** is the shape of the place with the colour taken away: the skyline profile and
how rugged it is, where the detail sits in the frame, how much sky there is. It is computed
on per-image-normalised luminance, so a bright region and a dark one with the same horizon
score as the same shape — which is the point. A region that only passes on colour is a region
that would vanish if you turned the saturation down, and that is not identity, it is a filter.

Each axis is scored by leave-one-out nearest-centroid accuracy across regions, and the two
together as well. The combined score must reach --min-accuracy (default 0.8); landform alone
must reach --min-shape-accuracy (default 0.55), which is well above the 1/R chance line but
does not demand that every shot of a region share a silhouette.

Usage: tools/uniqueness_check.py captures/regions [--min-accuracy 0.8] [--json out.json]
"""
import argparse, json, os, sys
from collections import defaultdict
import numpy as np
from PIL import Image

W, H = 160, 90


def _load(path: str) -> Image.Image:
    return Image.open(path).convert("RGB").resize((W, H))


def colour_signature(im: Image.Image) -> np.ndarray:
    hsv = np.asarray(im.convert("HSV"), dtype=np.float32) / 255.0
    h, s, v = hsv[..., 0].ravel(), hsv[..., 1].ravel(), hsv[..., 2].ravel()
    # weight hue by saturation so grey regions do not get random hues
    hh, _ = np.histogram(h, bins=18, range=(0, 1), weights=s)
    sh, _ = np.histogram(s, bins=8, range=(0, 1))
    vh, _ = np.histogram(v, bins=8, range=(0, 1))
    hh = hh / max(hh.sum(), 1e-6); sh = sh / max(sh.sum(), 1e-6); vh = vh / max(vh.sum(), 1e-6)
    stats = np.array([s.mean(), v.mean(), v.std(), (hsv[..., 0] * hsv[..., 1]).mean()])
    return np.concatenate([hh * 2.0, sh, vh, stats])


def _skyline(lum: np.ndarray) -> np.ndarray:
    """Row of the strongest downward brightness step per column, as a fraction of the frame.

    The skyline is where a bright sky stops. Taking the largest vertical gradient per column
    finds it whether it is a ridge, a canopy or a roofline, and returns 0 for a column that is
    sky all the way down -- which is itself information about the place.
    """
    dy = lum[:-1, :] - lum[1:, :]          # positive where it darkens downward
    row = np.argmax(dy, axis=0).astype(np.float32)
    strength = np.max(dy, axis=0)
    # a column with no real step (open sky, or a wall filling the frame) reads as no horizon
    row = np.where(strength > 0.12, row, np.nan)
    return row / float(lum.shape[0])


def shape_signature(im: Image.Image) -> np.ndarray:
    """Landform with the colour removed: skyline, ruggedness, where the detail sits, sky area."""
    lum = np.asarray(im.convert("L"), dtype=np.float32) / 255.0
    n = (lum - lum.mean()) / max(lum.std(), 1e-4)   # colour- and exposure-invariant
    sky = _skyline(lum)
    filled = np.isfinite(sky)
    frac = float(filled.mean())
    prof = np.where(filled, sky, np.nanmean(sky) if filled.any() else 0.5)
    hist, _ = np.histogram(prof, bins=8, range=(0, 1))
    hist = hist / max(hist.sum(), 1e-6)
    d = np.abs(np.diff(prof))
    # how the skyline is built: one long slow mass, or a saw of trees and crags
    spec = np.abs(np.fft.rfft(prof - prof.mean()))
    bands = np.array([spec[1:4].sum(), spec[4:16].sum(), spec[16:].sum()], dtype=np.float32)
    bands = bands / max(bands.sum(), 1e-6)
    # where the detail lives, in six bands down the frame
    gy = np.abs(np.diff(n, axis=0)).mean(axis=1)
    gx = np.abs(np.diff(n, axis=1)).mean(axis=1)
    rows = np.array_split(gy[:len(gx)] + gx[:len(gy)], 6)
    detail = np.array([float(r.mean()) for r in rows], dtype=np.float32)
    detail = detail / max(detail.sum(), 1e-6)
    stats = np.array([prof.mean(), prof.std(), float(d.mean()), float(d.max()), frac],
                     dtype=np.float32)
    return np.concatenate([hist * 1.5, bands, detail * 1.5, stats * 1.5]).astype(np.float32)


def region_of(filename: str) -> str:
    return os.path.basename(filename).split("_")[0]


def _accuracy(sigs: dict, by_region: dict, regions: list, files: list) -> tuple:
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
    return correct / len(files), confusions


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--min-accuracy", type=float, default=0.8)
    ap.add_argument("--min-shape-accuracy", type=float, default=0.55)
    ap.add_argument("--json")
    a = ap.parse_args()
    files = sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".png"))
    if not files:
        print("no PNG files"); return 2
    images = {f: _load(os.path.join(a.dir, f)) for f in files}
    colour = {f: colour_signature(im) for f, im in images.items()}
    shape = {f: shape_signature(im) for f, im in images.items()}
    both = {f: np.concatenate([colour[f], shape[f]]) for f in files}
    by_region = defaultdict(list)
    for f in files:
        by_region[region_of(f)].append(f)
    regions = sorted(by_region)
    if len(regions) < 2:
        print("need at least two regions"); return 2

    acc_c, _ = _accuracy(colour, by_region, regions, files)
    acc_s, conf_s = _accuracy(shape, by_region, regions, files)
    acc, confusions = _accuracy(both, by_region, regions, files)
    chance = 1.0 / len(regions)

    cent = {r: np.mean([both[g] for g in by_region[r]], axis=0) for r in regions}
    pairs = sorted(((np.linalg.norm(cent[x] - cent[y]), x, y)
                    for i, x in enumerate(regions) for y in regions[i + 1:]))
    print(f"images {len(files)}  regions {len(regions)}  chance {chance:.2f}")
    print(f"  colour    {acc_c:.2f}   palette alone")
    print(f"  landform  {acc_s:.2f}   silhouette and structure, colour removed")
    print(f"  together  {acc:.2f}")
    print("closest region pairs (small = easy to confuse):")
    for d, x, y in pairs[:5]:
        print(f"  {x:12s} {y:12s} {d:.3f}")
    if conf_s:
        print("read as the wrong place by landform alone:")
        for (r, b), n in sorted(conf_s.items(), key=lambda kv: -kv[1]):
            print(f"  {r} read as {b}: {n}")
    if confusions:
        print("misclassified:")
        for (r, b), n in sorted(confusions.items(), key=lambda kv: -kv[1]):
            print(f"  {r} read as {b}: {n}")
    if a.json:
        json.dump({"accuracy": acc, "colour_accuracy": acc_c, "shape_accuracy": acc_s,
                   "chance": chance,
                   "pairs": [[x, y, float(d)] for d, x, y in pairs],
                   "confusions": {f"{r}->{b}": n for (r, b), n in confusions.items()},
                   "shape_confusions": {f"{r}->{b}": n for (r, b), n in conf_s.items()}},
                  open(a.json, "w"), indent=2)
    ok = acc >= a.min_accuracy and acc_s >= a.min_shape_accuracy
    if acc >= a.min_accuracy and acc_s < a.min_shape_accuracy:
        print(f"landform {acc_s:.2f} is under {a.min_shape_accuracy:.2f}: these regions are "
              "telling themselves apart by tint, not by the shape of the country.")
    print("DROP TEST:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
