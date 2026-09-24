"""Filling the texels of a baked atlas that no island covers.

A bake writes each UV island's texels and a margin of a few more round it; everything else in
the atlas stays black. That is harmless for an asset baked into a few large islands, and it is
the whole look of one baked into hundreds of small ones -- a well of seventy stones, a drystone
wall of several hundred, a peat stack of cut turves -- because a mip level a few steps down
averages each stone with the black between the islands. From a street's length away the well's
stones came out as a black-and-white chequer and Skerrow's walls as dark rubble.

`fill_uncovered` pushes the islands' own colours outward into every uncovered texel (a
push-pull: averaged down a pyramid over the covered texels only, then pulled back up into the
holes), so every mip level averages stone with stone. The covered texels are left exactly as
baked. Pure numpy, so the forge's bake and the command line share it.
"""
from __future__ import annotations

import numpy as np


def fill_uncovered(rgb: np.ndarray, covered: np.ndarray) -> np.ndarray:
    """`rgb`: H x W x C floats; `covered`: H x W bools. Returns a copy with every uncovered
    texel set to the average of the covered texels nearest it, coarsely."""
    src = np.asarray(rgb, dtype=np.float64)
    mask = np.asarray(covered, dtype=bool)
    if mask.all() or not mask.any():
        return src.copy()
    weight = mask.astype(np.float64)
    colour = src * weight[..., None]
    levels = []
    c, w = colour, weight
    while min(c.shape[0], c.shape[1]) > 1:
        levels.append((c, w))
        h2, w2 = c.shape[0] // 2, c.shape[1] // 2
        c = c[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, -1).sum(axis=(1, 3))
        w = w[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2).sum(axis=(1, 3))
    avg = c / np.maximum(w, 1e-9)[..., None]
    for c, w in reversed(levels):
        up = np.repeat(np.repeat(avg, 2, axis=0), 2, axis=1)
        pad_h = c.shape[0] - up.shape[0]
        pad_w = c.shape[1] - up.shape[1]
        if pad_h > 0 or pad_w > 0:
            up = np.pad(up, ((0, max(pad_h, 0)), (0, max(pad_w, 0)), (0, 0)), mode="edge")
        up = up[:c.shape[0], :c.shape[1]]
        mine = c / np.maximum(w, 1e-9)[..., None]
        avg = np.where((w > 1e-9)[..., None], mine, up)
    return np.where(mask[..., None], src, avg)


def covered_of(rgb8: np.ndarray) -> np.ndarray:
    """For an atlas already on disk: the texels a bake wrote are the ones that are not pure
    black. (A stone's darkest texel is never exactly 0, 0, 0; an unbaked texel always is.)"""
    return np.asarray(rgb8)[..., :3].astype(np.int32).sum(axis=2) > 0


def shrink_mask(mask: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """A coverage mask at another size: a texel is covered where any of what it spans is."""
    h, w = mask.shape
    th, tw = size
    ys = (np.arange(th) * h) // th
    xs = (np.arange(tw) * w) // tw
    out = np.zeros((th, tw), dtype=bool)
    step_y = max(1, h // th)
    step_x = max(1, w // tw)
    for dy in range(step_y):
        for dx in range(step_x):
            out |= mask[np.minimum(ys + dy, h - 1)][:, np.minimum(xs + dx, w - 1)]
    return out
