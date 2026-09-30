#!/usr/bin/env python3
"""A part's skin names only bones the rig has, and leaving a joint out changes no vertex's skinning.

    python3 tools/tests/test_part_joints.py     # or: python3 -m pytest tools/tests/test_part_joints.py

A part is bound to the rig's skeleton by its skin's joint names, and a joint the rig lacks is an
error on every load. The skirt's bones (rig.CLOTH_NAMES) are in every armature the forge builds;
a part not weighted to them leaves them out of its skin (glb.drop_unweighted_joints), so heads,
hair and the rest bind on a rig built before those bones as well as after.
"""
from __future__ import annotations

import glob
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from forge.lib import glb  # noqa: E402

CHARS = ROOT / "game" / "assets" / "models" / "characters"


def skinning(path) -> tuple[list, dict]:
    """Per vertex of every skinned primitive: {joint name: weight}; and {joint name: its IBM}."""
    g, b = glb.read_glb(path)
    out, ibm = [], {}
    for si, skin in enumerate(g.get("skins", [])):
        names = [g["nodes"][j]["name"] for j in skin["joints"]]
        _, _, _, i0, ist = glb._elements(g, skin["inverseBindMatrices"])
        for k, n in enumerate(names):
            ibm[n] = b[i0 + k * ist:i0 + k * ist + 64]
        for node in g["nodes"]:
            if node.get("skin") != si or "mesh" not in node:
                continue
            for p in g["meshes"][node["mesh"]]["primitives"]:
                ja, wa = p["attributes"]["JOINTS_0"], p["attributes"]["WEIGHTS_0"]
                jc, _, jw, j0, jst = glb._elements(g, ja)
                wc, _, ww, w0, wst = glb._elements(g, wa)
                for i in range(g["accessors"][ja]["count"]):
                    jv = struct.unpack_from("<%d%s" % (jw, jc), b, j0 + i * jst)
                    wv = struct.unpack_from("<%d%s" % (ww, wc), b, w0 + i * wst)
                    d: dict = {}
                    for j, w in zip(jv, wv):
                        if w > 0:
                            d[names[j]] = d.get(names[j], 0) + w
                    out.append(d)
    return out, ibm


def rig_bones() -> set:
    g, _ = glb.read_glb(CHARS / "humanoid_rig" / "humanoid_rig.glb")
    return {g["nodes"][j]["name"] for s in g.get("skins", []) for j in s["joints"]}


class PartJoints(unittest.TestCase):
    def test_dropping_a_joint_nothing_is_weighted_to_changes_no_vertex(self):
        src = CHARS / "heads" / "default" / "default.glb"
        with tempfile.TemporaryDirectory() as d:
            dst = Path(d) / "head.glb"
            shutil.copy(src, dst)
            before, ibm0 = skinning(dst)
            # a head carries no weight on the toes
            dropped = glb.drop_unweighted_joints(dst, ["Toe.L", "Toe.R", "Head"])
            self.assertEqual(sorted(dropped), ["Toe.L", "Toe.R"], "the head is weighted to Head: it stays")
            after, ibm1 = skinning(dst)
            self.assertEqual(len(before), len(after))
            for a, b in zip(before, after):
                self.assertEqual(a, b)
            self.assertNotIn("Toe.L", ibm1)
            for n, m in ibm1.items():
                self.assertEqual(m, ibm0[n], "%s: its inverse bind matrix moved" % n)

    def test_every_heads_and_hairs_joints_are_on_the_rig(self):
        have = rig_bones()
        for f in sorted(glob.glob(str(CHARS / "heads" / "*" / "*.glb")) +
                        glob.glob(str(CHARS / "hair" / "*" / "*.glb"))):
            g, _ = glb.read_glb(f)
            names = {g["nodes"][j]["name"] for s in g.get("skins", []) for j in s["joints"]}
            self.assertFalse(names - have, "%s binds bones the rig lacks: %s" % (f, sorted(names - have)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
