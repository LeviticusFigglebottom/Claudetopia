#!/usr/bin/env python3
"""No two triangles of a head share texels.

    python3 tools/tests/test_head_uv.py     # or: python3 -m pytest tools/tests/test_head_uv.py

The heads were projected onto a cylinder round the skull, and a cylinder folds wherever the face
is not a height over it: under the tip of the nose, the brow ridge, the lids, the lips. The folds
shared texels with what lay over them (1 673 of 6 400 triangles on the hawk head), so each fold's
paint landed on the surface above it: the nostrils and the down-facing shadow on the front of a
long nose, which read in the engine as a dark, blotched tip. The forge unwraps them now
(character_forge.build_head).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "forge" / "preview"))

import lbspreview as LP  # noqa: E402
from forge.lib import glb  # noqa: E402

HEADS = ROOT / "game" / "assets" / "models" / "characters" / "heads"


def overlapping(uv: np.ndarray, tris: np.ndarray, size: int = 512, inset: float = 0.08) -> int:
    """How many triangles cover a texel another triangle already covers (their insides only,
    `inset` in from each edge, so neighbours that share an edge do not count)."""
    owner = -np.ones((size, size), int)
    clash = np.zeros(len(tris), bool)
    for t, (a, b, c) in enumerate(tris):
        P = uv[[a, b, c]] * size
        x0, x1 = int(P[:, 0].min()), int(P[:, 0].max()) + 1
        y0, y1 = int(P[:, 1].min()), int(P[:, 1].max()) + 1
        xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        d = (P[1, 1] - P[2, 1]) * (P[0, 0] - P[2, 0]) + (P[2, 0] - P[1, 0]) * (P[0, 1] - P[2, 1])
        if abs(d) < 1e-9:
            continue
        l0 = ((P[1, 1] - P[2, 1]) * (xs - P[2, 0]) + (P[2, 0] - P[1, 0]) * (ys - P[2, 1])) / d
        l1 = ((P[2, 1] - P[0, 1]) * (xs - P[2, 0]) + (P[0, 0] - P[2, 0]) * (ys - P[2, 1])) / d
        ins = (l0 > inset) & (l1 > inset) & (1 - l0 - l1 > inset)
        yy, xx = np.nonzero(ins)
        yy, xx = np.clip(yy + y0, 0, size - 1), np.clip(xx + x0, 0, size - 1)
        prev = owner[yy, xx]
        if (prev >= 0).any():
            clash[t] = True
            clash[np.unique(prev[prev >= 0])] = True
        owner[yy, xx] = t
    return int(clash.sum())


class HeadsAreUnwrapped(unittest.TestCase):
    def test_no_head_folds_over_itself(self):
        bad = []
        for path in sorted(HEADS.glob("*/*.glb")):
            g, b = glb.read_glb(path)
            for m in g["meshes"]:
                if not m["name"].lower().startswith("head"):
                    continue
                p = m["primitives"][0]
                uv = LP.acc(g, b, p["attributes"]["TEXCOORD_0"])
                tris = LP.acc(g, b, p["indices"]).astype(int).reshape(-1, 3)
                n = overlapping(uv, tris)
                if n > 0.005 * len(tris):
                    bad.append("%s: %d of %d triangles share texels" % (path.stem, n, len(tris)))
        self.assertEqual(bad, [], "\n".join(bad))


if __name__ == "__main__":
    unittest.main()
