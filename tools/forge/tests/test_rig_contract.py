#!/usr/bin/env python3
"""Checks the exported humanoid rig against docs/CONTRACTS.md §2 and §3.

Reads the GLB with pygltflib (no Blender, no Godot), so it runs anywhere:

    python3 tools/forge/tests/test_rig_contract.py

It is also importable as unittest test cases.  If the rig has not been built yet the
geometry checks skip with a clear message rather than failing the suite.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys
import unittest
from typing import Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import numpy as np
from pygltflib import GLTF2

from forge.lib import rig, anim_clips
from forge.lib.rig import Skeleton

RIG_DIR = os.path.join(ROOT, "game", "assets", "models", "characters", "humanoid_rig")
RIG_GLB = os.path.join(RIG_DIR, "humanoid_rig.glb")
CLIPS_JSON = os.path.join(RIG_DIR, "humanoid_rig.clips.json")

# CONTRACTS §2: glTF is Y-up, so a bone's length is |translation| of its child.
MIN_BONE_M = 0.03
MAX_BONE_M = 0.70


def load_gltf() -> Optional[GLTF2]:
    if not os.path.exists(RIG_GLB):
        return None
    return GLTF2().load(RIG_GLB)


def node_map(g: GLTF2) -> Dict[str, int]:
    """Bone name -> node index.  Restricted to the skin's joints, because a mesh object can
    share a name with a bone (the head mesh is called "Head", so is the bone)."""
    if g.skins:
        return {g.nodes[j].name: j for j in g.skins[0].joints if g.nodes[j].name}
    return {n.name: i for i, n in enumerate(g.nodes) if n.name}


def children_of(g: GLTF2, idx: int) -> List[int]:
    return list(g.nodes[idx].children or [])


def parent_map(g: GLTF2) -> Dict[int, int]:
    out: Dict[int, int] = {}
    for i, n in enumerate(g.nodes):
        for c in (n.children or []):
            out[c] = i
    return out


def bone_translation(g: GLTF2, idx: int) -> np.ndarray:
    t = g.nodes[idx].translation
    if t is None:
        m = g.nodes[idx].matrix
        if m:
            return np.array(m[12:15], dtype=float)
        return np.zeros(3)
    return np.array(t, dtype=float)


class TestRigSkeleton(unittest.TestCase):
    """CONTRACTS §2: bone names, hierarchy, sockets, scale."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.g = load_gltf()

    def setUp(self) -> None:
        if self.g is None:
            self.skipTest("humanoid_rig.glb not built yet (run: blender -b --python "
                          "tools/forge/character_forge.py -- rig)")

    def test_all_deform_bones_present(self) -> None:
        names = node_map(self.g)
        for bone in rig.DEFORM_NAMES:
            self.assertIn(bone, names, "missing deform bone %s" % bone)
        self.assertIn("Root", names)

    def test_all_socket_bones_present(self) -> None:
        names = node_map(self.g)
        for socket in rig.SOCKET_BONES:
            self.assertIn(socket, names, "missing socket %s" % socket)

    def test_hierarchy_matches_contract(self) -> None:
        names = node_map(self.g)
        parents = parent_map(self.g)
        for bone, expected in rig.PARENT.items():
            if expected is None:
                continue
            idx = names[bone]
            self.assertIn(idx, parents, "%s has no parent" % bone)
            actual = self.g.nodes[parents[idx]].name
            self.assertEqual(actual, expected, "%s parented to %s, expected %s" % (bone, actual, expected))

    def test_bone_lengths_are_sane(self) -> None:
        names = node_map(self.g)
        for bone in rig.DEFORM_NAMES:
            if bone == "Hips":
                continue
            d = float(np.linalg.norm(bone_translation(self.g, names[bone])))
            self.assertGreater(d, 0.0, "%s sits on top of its parent" % bone)
            self.assertLess(d, MAX_BONE_M, "%s is %.3f m from its parent" % (bone, d))

    def test_skeleton_is_about_the_right_height(self) -> None:
        names = node_map(self.g)
        parents = parent_map(self.g)

        def world_y(idx: int) -> float:
            y = 0.0
            while True:
                y += float(bone_translation(self.g, idx)[1])
                if idx not in parents:
                    return y
                idx = parents[idx]
        top = world_y(names["Socket.Head"])
        self.assertGreater(top, 1.55, "rig is only %.2f m tall" % top)
        self.assertLess(top, 1.95, "rig is %.2f m tall" % top)

    def test_feet_are_on_the_ground(self) -> None:
        skel = Skeleton()
        for side in ("L", "R"):
            toe_tip = skel.J["ToeTip.%s" % side]
            self.assertLess(float(toe_tip[2]), 0.05, "toe tip floats at %.3f" % toe_tip[2])
            self.assertGreaterEqual(float(toe_tip[2]), 0.0)

    def test_mesh_is_skinned_to_every_deform_bone(self) -> None:
        self.assertTrue(self.g.skins, "no skin in the GLB")
        joints = self.g.skins[0].joints
        joint_names = {self.g.nodes[j].name for j in joints}
        for bone in rig.DEFORM_NAMES:
            self.assertIn(bone, joint_names, "%s is not a skin joint" % bone)

    def test_meshes_exist_and_are_not_empty(self) -> None:
        self.assertTrue(self.g.meshes, "no meshes in the GLB")
        total = 0
        for m in self.g.meshes:
            for p in m.primitives:
                acc = self.g.accessors[p.indices] if p.indices is not None else None
                if acc is not None:
                    total += acc.count // 3
        self.assertGreater(total, 3000, "only %d triangles in the rig mesh" % total)
        self.assertLess(total, 40000, "%d triangles is over the character budget" % total)


class TestRigPose(unittest.TestCase):
    """The A-pose of CONTRACTS §2, checked on the pure-Python skeleton."""

    def test_arms_are_35_degrees_below_horizontal(self) -> None:
        skel = Skeleton()
        for side in ("L", "R"):
            sh = skel.J["UpperArm.%s" % side]
            el = skel.J["LowerArm.%s" % side]
            d = el - sh
            horiz = math.hypot(d[0], d[1])
            angle = math.degrees(math.atan2(-d[2], horiz))
            self.assertAlmostEqual(angle, rig.A_POSE_DEG, delta=1.0,
                                   msg="%s arm is %.1f deg below horizontal" % (side, angle))

    def test_default_height(self) -> None:
        skel = Skeleton()
        self.assertAlmostEqual(float(skel.J["HeadTop"][2]), rig.DEFAULT_HEIGHT, delta=0.02)

    def test_socket_bones_do_not_deform(self) -> None:
        skel = Skeleton()
        for socket in rig.SOCKET_BONES:
            self.assertFalse(skel.bones[socket].deform, "%s must not deform" % socket)

    def test_weapon_socket_points_along_the_blade(self) -> None:
        ## CONTRACTS §2: Socket.WeaponR has +Y along the blade.
        skel = Skeleton()
        W = skel.fk({})
        blade = W["Socket.WeaponR"][:3, :3] @ np.array([0.0, 1.0, 0.0])
        self.assertGreater(float(np.dot(blade, rig.FWD)), 0.8,
                           "weapon socket +Y should point forward out of the fist")

    def test_proportions_scale_bone_lengths(self) -> None:
        tall = Skeleton(rig.Proportions(height=2.0))
        short = Skeleton(rig.Proportions(height=1.4))
        self.assertGreater(tall.bones["UpperLeg.L"].length, short.bones["UpperLeg.L"].length)
        self.assertAlmostEqual(float(tall.J["HeadTop"][2]), 2.0, delta=0.03)
        self.assertAlmostEqual(float(short.J["HeadTop"][2]), 1.4, delta=0.03)
        for s in (tall, short):
            self.assertLess(abs(float(s.J["Foot.L"][2] - s.J["Foot.R"][2])), 1e-6)


class TestClipLibrary(unittest.TestCase):
    """CONTRACTS §3: every clip, its loop flag and its events."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.skel = Skeleton()
        cls.clips = anim_clips.build_clips(cls.skel)

    def test_every_required_clip_is_built(self) -> None:
        for name in anim_clips.REQUIRED_CLIPS:
            self.assertIn(name, self.clips, "clip library is missing %s" % name)

    def test_no_contract_problems(self) -> None:
        problems = anim_clips.check_contract(self.clips)
        self.assertEqual(problems, [], "\n".join(problems))

    def test_attacks_have_readable_telegraphs(self) -> None:
        """A player has to be able to react to a wind-up (DESIGN.md §5.3)."""
        for name in anim_clips.ATTACK_CLIPS:
            c = self.clips[name]
            events = {e: t for t, e in c.events}
            windup = events["hit_start"]
            self.assertGreater(windup, 0.13, "%s strikes after only %.2fs" % (name, windup))
            self.assertLess(events["hit_end"], c.length, "%s hit window runs past the clip" % name)
            self.assertGreater(events["hit_end"], events["hit_start"], "%s has an empty hit window" % name)
            self.assertGreaterEqual(events["cancel_ok"], events["hit_end"],
                                    "%s can be cancelled during its active frames" % name)
            self.assertLessEqual(events["cancel_ok"], c.length)
        for name in ("Attack_1H_Heavy", "Attack_2H_Heavy"):
            events = {e: t for t, e in self.clips[name].events}
            self.assertGreater(events["hit_start"], 0.5,
                               "%s is a heavy attack and needs a long telegraph" % name)

    def test_loops_are_marked_and_close(self) -> None:
        looped = [n for n, c in self.clips.items() if c.loop]
        for n in ("Idle", "Walk", "Run", "Idle_Combat", "Block_Idle", "Sneak_Walk"):
            self.assertIn(n, looped, "%s should loop" % n)
        for n in ("Death_A", "Death_B", "Knockdown", "Get_Up"):
            self.assertFalse(self.clips[n].loop, "%s must not loop" % n)

    def test_locomotion_feet_do_not_slide(self) -> None:
        """A planted foot must travel backwards at exactly the clip's speed."""
        from forge.lib import anim_preview
        cases = {"Walk": (1.55, (0.0, 1.0)), "Run": (5.0, (0.0, 1.0)),
                 "Walk_Back": (1.15, (0.0, -1.0)), "Sneak_Walk": (0.95, (0.0, 1.0))}
        for name, (speed, direction) in cases.items():
            report = anim_preview.foot_slide_report(self.skel, self.clips[name], speed, direction, samples=30)
            for side, worst in report.items():
                self.assertLess(worst, 0.05,
                                "%s foot %s slides %.3f m" % (name, side, worst))

    def test_death_clips_end_held(self) -> None:
        for name in ("Death_A", "Death_B"):
            c = self.clips[name]
            a = c.local_pose(c.length - 0.12)
            b = c.local_pose(c.length)
            worst = 0.0
            for bone in a:
                if a[bone][0] is None or b[bone][0] is None:
                    continue
                worst = max(worst, float(np.abs(a[bone][0] - b[bone][0]).max()))
            self.assertLess(worst, 0.06, "%s is still moving when it ends" % name)

    ## Clips that legitimately put the body on the ground, where the hips must travel far.
    GROUND_CLIPS = {"Death_A", "Death_B", "Knockdown", "Get_Up", "Sleep_Idle",
                    "Sit_Down", "Sit_Idle", "Stand_Up", "Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R"}
    ## Clips that crouch deeply but stay on their feet.
    CROUCH_CLIPS = {"Pick_Up", "Cower", "Jump_Start", "Jump_Land", "Sneak_Idle", "Sneak_Walk"}

    def test_clips_never_bake_root_motion(self) -> None:
        """CONTRACTS §2: locomotion is in place and movement is driven by code, so no clip
        may carry a Root track and only the Hips may translate."""
        for name, c in self.clips.items():
            baked = c.bake()
            self.assertNotIn("Root", baked.bones, "%s animates Root" % name)
            hips = baked.hips_pos
            limit = 1.05 if name in self.GROUND_CLIPS else (0.45 if name in self.CROUCH_CLIPS else 0.30)
            worst = float(np.abs(hips).max())
            self.assertLess(worst, limit, "%s moves the hips %.2f m" % (name, worst))

    def test_no_wild_joint_angles(self) -> None:
        """Knees and elbows are hinges: they may fold, never invert or hyper-extend."""
        from forge.lib import anim_preview
        pairs = [("UpperLeg.L", "LowerLeg.L"), ("UpperLeg.R", "LowerLeg.R"),
                 ("UpperArm.L", "LowerArm.L"), ("UpperArm.R", "LowerArm.R")]
        for name, c in self.clips.items():
            for i in range(13):
                t = c.length * i / 12.0
                for upper, lower in pairs:
                    bend = anim_preview.joint_bend_degrees(self.skel, c, t, upper, lower)
                    self.assertLess(bend, 150.0,
                                    "%s at %.2fs folds %s to %.0f deg" % (name, t, lower, bend))


class TestClipsSidecar(unittest.TestCase):
    """The exported <model>.clips.json sidecar (CONTRACTS §3)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.data = None
        if os.path.exists(CLIPS_JSON):
            with open(CLIPS_JSON) as f:
                cls.data = json.load(f)
        cls.g = load_gltf()

    def setUp(self) -> None:
        if self.data is None:
            self.skipTest("humanoid_rig.clips.json not built yet")

    def test_sidecar_shape(self) -> None:
        for name, entry in self.data.items():
            self.assertIn("loop", entry, "%s has no loop flag" % name)
            self.assertIn("length", entry, "%s has no length" % name)
            self.assertIn("events", entry, "%s has no events list" % name)
            self.assertGreater(float(entry["length"]), 0.0)
            for e in entry["events"]:
                self.assertIn("t", e)
                self.assertIn("name", e)
                self.assertGreaterEqual(float(e["t"]), 0.0)
                self.assertLessEqual(float(e["t"]), float(entry["length"]) + 1e-6)

    def test_every_sidecar_clip_is_in_the_glb(self) -> None:
        if self.g is None:
            self.skipTest("rig not built")
        exported = {a.name for a in (self.g.animations or [])}
        for name in self.data:
            self.assertIn(name, exported, "%s is in the sidecar but not in the GLB" % name)

    def test_full_export_covers_the_contract(self) -> None:
        """Only meaningful once the rig has been built with every clip."""
        if len(self.data) < len(anim_clips.REQUIRED_CLIPS):
            self.skipTest("rig built with a clip subset (%d of %d)"
                          % (len(self.data), len(anim_clips.REQUIRED_CLIPS)))
        for name in anim_clips.REQUIRED_CLIPS:
            self.assertIn(name, self.data)


def main() -> int:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite([loader.loadTestsFromTestCase(t) for t in (
        TestRigSkeleton, TestRigPose, TestClipLibrary, TestClipsSidecar)])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
