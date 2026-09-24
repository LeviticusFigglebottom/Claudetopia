#!/usr/bin/env python3
"""The forge's post-and-rail module has its rails on its posts.

    python3 tools/tests/test_fence_model.py     # or: python3 -m unittest discover tools/tests

Playtest 4: "fences have their poles and lengthwise planks entirely misaligned". The module's
posts had been moved to their place twice (4.8 m apart for a 2.4 m rail) and its rails turned
about the origin after being put at their height, which swung them half a metre and more behind
the posts. This reads each built module's mesh, splits it into its parts, and checks that every
rail's two ends sit on a post: within 5 cm of a post's side along the run, inside the post's
depth across it, and between its foot and its top.
"""
from __future__ import annotations

import glob
import json
import os
import struct
import unittest
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "game", "assets", "models", "props")


def parts(path: str) -> list:
    """The LOD0 mesh's connected parts, as vertex arrays (glTF axes: y up)."""
    b = open(path, "rb").read()
    length = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + length])
    blob = b[20 + length + 8:]
    out = []
    for m in j["meshes"]:
        if "LOD" in m.get("name", ""):
            continue
        for p in m["primitives"]:
            a = j["accessors"][p["attributes"]["POSITION"]]
            bv = j["bufferViews"][a["bufferView"]]
            off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            v = np.frombuffer(blob[off:off + a["count"] * 12], dtype="<f4").reshape(-1, 3)
            ia = j["accessors"][p["indices"]]
            ibv = j["bufferViews"][ia["bufferView"]]
            ioff = ibv.get("byteOffset", 0) + ia.get("byteOffset", 0)
            dt = {5123: "<u2", 5125: "<u4"}[ia["componentType"]]
            idx = np.frombuffer(blob[ioff:ioff + ia["count"] * np.dtype(dt).itemsize], dtype=dt)
            parent = list(range(len(v)))

            def find(x):
                while parent[x] != x:
                    parent[x] = parent[parent[x]]
                    x = parent[x]
                return x
            for t in idx.reshape(-1, 3):
                r = [find(int(x)) for x in t]
                parent[r[1]] = r[0]
                parent[find(r[2])] = find(r[0])
            same = defaultdict(list)
            for i, q in enumerate(np.round(v, 4)):
                same[tuple(q)].append(i)
            for ids in same.values():
                for i in ids[1:]:
                    parent[find(i)] = find(ids[0])
            comp = defaultdict(list)
            for i in range(len(v)):
                comp[find(i)].append(i)
            out += [v[ids] for ids in comp.values()]
    return out


class FenceModelTest(unittest.TestCase):
    def test_every_rail_ends_on_a_post(self):
        found = sorted(glob.glob(os.path.join(MODELS, "*fence_post_rail_*", "*fence_post_rail_?.glb")))
        self.assertTrue(found, "no post-and-rail module built")
        for path in found:
            name = os.path.basename(path)
            ps = parts(path)
            # a post is tall and thin; a rail is long along x
            posts = [p for p in ps if np.ptp(p[:, 1]) > 0.8 and np.ptp(p[:, 0]) < 0.3]
            rails = [p for p in ps if np.ptp(p[:, 0]) > 1.5]
            self.assertEqual(len(posts), 2, "%s: two posts" % name)
            self.assertEqual(len(rails), 2, "%s: two rails" % name)
            for r in rails:
                ry = (r[:, 1].min() + r[:, 1].max()) * 0.5
                rz = (r[:, 2].min() + r[:, 2].max()) * 0.5
                for end_x in (r[:, 0].min(), r[:, 0].max()):
                    post = min(posts, key=lambda p: abs(p[:, 0].mean() - end_x))
                    gap = max(post[:, 0].min() - end_x, end_x - post[:, 0].max(), 0.0)
                    self.assertLess(gap, 0.05, "%s: a rail's end %.2f m off its post along the run" % (name, gap))
                    self.assertTrue(post[:, 2].min() - 0.05 <= rz <= post[:, 2].max() + 0.05,
                                    "%s: a rail %.2f m in front of or behind its post" % (name, rz))
                    self.assertTrue(post[:, 1].min() < ry < post[:, 1].max(),
                                    "%s: a rail at %.2f m, off its post's height" % (name, ry))


if __name__ == "__main__":
    unittest.main()
