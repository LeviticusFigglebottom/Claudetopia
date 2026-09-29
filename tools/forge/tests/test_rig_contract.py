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


def _read(g: GLTF2, blob: bytes, ai: int) -> np.ndarray:
    """An accessor as an (n, width) array (dense, no sparse part)."""
    acc = g.accessors[ai]
    view = g.bufferViews[acc.bufferView]
    dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[acc.componentType]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc.type]
    start = (view.byteOffset or 0) + (acc.byteOffset or 0)
    item = np.dtype(dt).itemsize * width
    stride = view.byteStride or item
    raw = np.frombuffer(blob, np.uint8, count=stride * (acc.count - 1) + item, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(acc.count, item), strides=(stride, 1))
    out = np.frombuffer(rows.copy().tobytes(), dt).reshape(acc.count, width).astype(float)
    if acc.normalized and dt != np.float32:
        out /= float(np.iinfo(dt).max)
    return out


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

    def test_cloth_bones_are_there_and_no_clip_keys_them(self) -> None:
        """The skirt's bones stand in the rig, deforming, and are posed by SkirtDrive in the game:
        a channel on one would pose it back to rest under SkirtDrive every frame."""
        names = node_map(self.g)
        for bone in rig.CLOTH_NAMES:
            self.assertIn(bone, names, "missing cloth bone %s" % bone)
        keyed = set()
        for an in getattr(self.g, "animations", None) or []:
            for ch in an.channels:
                keyed.add(self.g.nodes[ch.target.node].name)
        self.assertEqual(sorted(keyed & set(rig.CLOTH_NAMES)), [], "a clip keys a cloth bone")

    def test_the_body_is_not_weighted_to_a_cloth_bone(self) -> None:
        """The body deforms as it did before the skirt's bones: none of its weight is theirs."""
        import struct
        joints = self.g.skins[0].joints
        cloth = {k for k, j in enumerate(joints) if self.g.nodes[j].name in rig.CLOTH_NAMES}
        blob = self.g.binary_blob()
        for m in self.g.meshes:
            for p in m.primitives:
                ja, wa = p.attributes.JOINTS_0, p.attributes.WEIGHTS_0
                if ja is None or wa is None:
                    continue
                J = _read(self.g, blob, ja)
                W = _read(self.g, blob, wa)
                on = np.isin(J, list(cloth)) & (W > 1e-6)
                self.assertFalse(on.any(), "%s: %d weights on a cloth bone" % (m.name, int(on.sum())))

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
        for name in ("Attack_1H_Heavy", "Attack_2H_Heavy", "Attack_Staff_Heavy"):
            events = {e: t for t, e in self.clips[name].events}
            self.assertGreater(events["hit_start"], 0.5,
                               "%s is a heavy attack and needs a long telegraph" % name)

    def _pose_at(self, name: str, t: float):
        W = self.skel.fk(self.clips[name].local_pose(t))
        return W

    def test_the_bow_draws_nocks_holds_and_looses(self) -> None:
        """Triage 55: an arrow from the quiver, nocked, the bow raised and drawn to the jaw; held;
        loosed with the string hand flying back. The events come in that order, the draw hand is at
        the quiver when it takes the arrow and at the jaw at full draw, the bow arm is out straight
        with the stave upright, and the arrow the string hand holds (along the hand's line,
        anim_clips.hand_line) points where the bow's does."""
        draw = self.clips["Bow_Draw"]
        ev = {e: t for t, e in draw.events}
        order = ["arrow_drawn", "nocked", "bow_raised", "bow_drawn"]
        for a, b in zip(order, order[1:]):
            self.assertLess(ev[a], ev[b], "Bow_Draw: %s comes after %s" % (a, b))
        self.assertLessEqual(ev["nocked"], 0.34, "a quick shot (Player.BOW_MIN_DRAW) would loose an arrow not yet nocked")
        rel = {e: t for t, e in self.clips["Bow_Release"].events}
        self.assertLess(rel["release"], 0.05, "Bow_Release looses at once")
        self.assertLess(rel["release"], rel["cancel_ok"])
        self.assertTrue(self.clips["Bow_Aim"].loop)
        s = self.skel
        W = self._pose_at("Bow_Draw", ev["arrow_drawn"])
        quiver = anim_clips.body_point(s, *anim_clips.BOW_QUIVER)
        self.assertLess(float(np.linalg.norm(W["Socket.WeaponR"][:3, 3] - quiver)), 0.06, "the hand is not at the quiver")
        W = self._pose_at("Bow_Draw", draw.length)
        anchor = anim_clips.body_point(s, *anim_clips.BOW_ANCHOR)
        self.assertLess(float(np.linalg.norm(W["Socket.WeaponR"][:3, 3] - anchor)), 0.03, "the string hand is not at the jaw")
        bow = W["Socket.WeaponL"]
        self.assertGreater(float(bow[:3, 1] @ rig.UP), 0.95, "the stave is not upright at full draw")
        way_bow = bow[:3, :3] @ anim_clips.hand_line(s, "L")
        way_arrow = W["Socket.WeaponR"][:3, :3] @ anim_clips.hand_line(s, "R")
        self.assertGreater(float(way_bow @ rig.FWD), 0.97, "the bow's arrow way is not ahead")
        self.assertGreater(float(way_arrow @ rig.FWD), 0.97, "the nocked arrow does not point ahead")
        drawn = float(np.linalg.norm(bow[:3, 3] - W["Socket.WeaponR"][:3, 3]))
        self.assertGreater(drawn, 0.55, "drawn only %.2f m" % drawn)
        shoulder, hand = W["UpperArm.L"][:3, 3], W["Hand.L"][:3, 3]
        reach = float(np.linalg.norm(hand - shoulder))
        arm = s.bones["UpperArm.L"].length + s.bones["LowerArm.L"].length
        self.assertGreater(reach, 0.93 * arm, "the bow arm is bent (%.2f of its length)" % (reach / arm))

    def test_the_staff_swings_clear_of_the_body(self) -> None:
        """Triage 56: the staff's own clips (a rising sweep, a thrust, an overhead), both hands on
        it, its head (0.97 m past the grip) and its butt (0.80 m behind it) out of the torso, a
        capsule of 0.13 m from the hips to the neck, as test_attack_motion holds in the game."""
        def gap(p0, p1, q0, q1):
            best = 1e9
            for a in np.linspace(0.0, 1.0, 25):
                p = p0 + (p1 - p0) * a
                d = q1 - q0
                u = float(np.clip((p - q0) @ d / max(float(d @ d), 1e-9), 0.0, 1.0))
                best = min(best, float(np.linalg.norm(p - (q0 + d * u))))
            return best
        for name in ("Attack_Staff_1", "Attack_Staff_2", "Attack_Staff_Heavy"):
            c = self.clips[name]
            for t in np.arange(0.0, c.length, 1.0 / 60.0):
                W = self.skel.fk(c.local_pose(float(t)))
                g, d = W["Socket.WeaponR"][:3, 3], W["Socket.WeaponR"][:3, 1]
                hips, neck = W["Hips"][:3, 3], W["Neck"][:3, 3]
                self.assertGreater(gap(g + d * 0.12, g + d * 0.97, hips, neck), 0.13, "%s: the head in the body at %.2f s" % (name, t))
                self.assertGreater(gap(g - d * 0.13, g - d * 0.80, hips, neck), 0.13, "%s: the butt in the body at %.2f s" % (name, t))
                self.assertLess(float(np.linalg.norm(W["Socket.WeaponL"][:3, 3] - (g - d * anim_clips.STAFF_SEP))), 0.07,
                                "%s: the left hand is off the staff at %.2f s" % (name, t))

    def _grip_path(self, name: str, dt: float = 1.0 / 120.0):
        from forge.lib import anim_preview
        c = self.clips[name]
        ts = np.arange(0.0, c.length, dt)
        pts = []
        for t in ts:
            W = self.skel.fk(anim_preview.local_pose_at(self.skel, c, t))
            pts.append(self.skel.joint_world(W, "Socket.WeaponR"))
        pts = np.array(pts)
        return ts, pts, np.linalg.norm(np.diff(pts, axis=0), axis=1) / dt

    def test_a_blow_carries_through_its_window(self) -> None:
        """The playtest's "attacking animations still need revising". Eased key by key, a swing
        left its cocked pose at full speed and stopped dead at the next key, in its hit window: the
        grip went from 2.7 to 109 m/s in a frame and stood still (0.00 of its peak) in every
        window, which on film was a one-frame pop and a blade hanging in front of the chest. The
        keys flow now (Track.flow): the blade gathers speed out of the wind-up and is still moving
        through the window. Measured at 120 Hz: at most 16.5 m/s of change in a 120th (was
        15-34), and the slowest moment of a cut's window 0.09-0.33 of its peak (was 0.00). The
        16.5 and 16.0 are one-sample twitches of the backhand and the two-handed sweep, where the
        grip is out of the arm's reach and the straight arm's roll is loose; every other cut is
        under 11."""
        for name in [c for c in anim_clips.ATTACK_CLIPS if c.startswith(("Attack_1H", "Attack_2H", "Attack_Dagger_2"))]:
            ev = {e: t for t, e in self.clips[name].events}
            ts, _, v = self._grip_path(name)
            jump = float(np.abs(np.diff(v)).max())
            self.assertLess(jump, 17.0, "%s: the grip's speed changes %.1f m/s in a 120th" % (name, jump))
            win = v[(ts[:-1] >= ev["hit_start"]) & (ts[:-1] <= ev["hit_end"])]
            self.assertGreater(float(win.min()), 0.05 * float(v.max()),
                               "%s: the blade stands still in its hit window" % name)

    def test_a_thrust_arrives_with_its_window(self) -> None:
        """A stab, a punch, the riposte and the backstab have windows set by hand, and their keys
        had the point out 30-80 ms before the window opened, then held there. Flowing, the point
        is 90% of the way out within 35 ms of hit_start."""
        for name in ("Attack_Dagger_1", "Riposte", "Backstab"):
            ev = {e: t for t, e in self.clips[name].events}
            ts, pts, _ = self._grip_path(name)
            fwd = pts @ rig.FWD
            i = int(np.argmax(fwd))
            lo = float(fwd[:i + 1].min())
            i90 = int(np.argmax(fwd >= lo + 0.9 * (float(fwd[i]) - lo)))
            self.assertLess(abs(float(ts[i90]) - ev["hit_start"]), 0.035,
                            "%s: the point is out at %.3f s, its window opens at %.3f s"
                            % (name, float(ts[i90]), ev["hit_start"]))

    def test_loops_are_marked_and_close(self) -> None:
        looped = [n for n, c in self.clips.items() if c.loop]
        for n in ["Idle", "Walk", "Run", "Idle_Combat", "Block_Idle", "Sneak_Walk"] + anim_clips.TURN_CLIPS:
            self.assertIn(n, looped, "%s should loop" % n)
        for n in ("Death_A", "Death_B", "Knockdown", "Get_Up"):
            self.assertFalse(self.clips[n].loop, "%s must not loop" % n)

    def test_locomotion_feet_do_not_slide(self) -> None:
        """A planted foot must travel backwards at exactly the clip's speed: the speed the sidecar
        carries, which is the speed the game plays it at (CONTRACTS §3)."""
        from forge.lib import anim_preview
        cases = {"Walk": (0.0, 1.0), "Trot": (0.0, 1.0), "Run": (0.0, 1.0), "Sprint": (0.0, 1.0),
                 "Walk_Back": (0.0, -1.0), "Sneak_Walk": (0.0, 1.0),
                 "Strafe_L": (1.0, 0.0), "Strafe_R": (-1.0, 0.0)}
        for name, direction in cases.items():
            speed = float(self.clips[name].extra["speed"])
            report = anim_preview.foot_slide_report(self.skel, self.clips[name], speed, direction, samples=30)
            for side, worst in report.items():
                self.assertLess(worst, 0.05,
                                "%s foot %s slides %.3f m" % (name, side, worst))

    # The gaits at the speeds DESIGN §5.2 moves the body at (Player.WALK_SPEED, JOG_SPEED,
    # SPRINT_SPEED, SNEAK_SPEED, and locked on LOCKED_BACK and LOCKED_SIDE; test_humanoid_model
    # checks the game reads the same numbers).
    GAIT_SPEEDS = {"Walk": 1.8, "Trot": 3.6, "Run": 5.0, "Sprint": 7.8, "Sneak_Walk": 1.5,
                   "Walk_Back": 1.8, "Strafe_L": 3.0, "Strafe_R": 3.0}

    def test_gait_clips_carry_the_games_speeds(self) -> None:
        for name, speed in self.GAIT_SPEEDS.items():
            self.assertAlmostEqual(float(self.clips[name].extra["speed"]), speed, places=3,
                                   msg="%s is authored at %s m/s, the game moves at %s"
                                       % (name, self.clips[name].extra["speed"], speed))

    def test_the_gaits_stand_up(self) -> None:
        """The report was a walk that read as a crouch. Measured on the first clips: Walk dipped
        the hips 13.5 cm below standing at each contact (11.4 cm peak to peak) and Run 25.2 cm
        (24.0). A walk moves the pelvis 4-5 cm and a run 6-8; these bounds sit just outside that.
        The side-steps dipped 21.3 cm (19.8 peak to peak) at every step until they were shortened."""
        hips0 = self.skel.joint_world(self.skel.fk({}), "Hips")[2]
        limits = {"Walk": (0.05, 0.07), "Trot": (0.06, 0.08), "Run": (0.06, 0.09), "Sprint": (0.06, 0.09),
                  "Walk_Back": (0.05, 0.08), "Strafe_L": (0.05, 0.08), "Strafe_R": (0.05, 0.08)}
        for name, (mean_max, p2p_max) in limits.items():
            c = self.clips[name]
            zs = []
            for i in range(60):
                W = self.skel.fk(c.local_pose(c.length * i / 60.0))
                zs.append(self.skel.joint_world(W, "Hips")[2])
            zs = np.array(zs)
            self.assertLess(hips0 - zs.mean(), mean_max, "%s holds the hips %.1f cm below standing"
                            % (name, (hips0 - zs.mean()) * 100))
            self.assertLess(zs.max() - zs.min(), p2p_max, "%s bobs the hips %.1f cm"
                            % (name, (zs.max() - zs.min()) * 100))

    def test_the_rolls_stay_on_the_ground(self) -> None:
        """A roll is felt through the floor. Built from keys alone, Dodge_F put the toes 19 cm into
        the ground on the way down, the head 24 cm into it at the turn and the back 26 cm clear of
        it coming over, and it ended standing on bent legs with its feet 30 cm in the air."""
        from forge.lib.anim import lowest_surface
        hips0 = self.skel.joint_world(self.skel.fk({}), "Hips")[2]
        for name in ("Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R"):
            c = self.clips[name]
            worst = 0.0
            for i in range(41):
                W = self.skel.fk(c.local_pose(c.length * i / 40.0))
                worst = max(worst, abs(lowest_surface(self.skel, W)))
            self.assertLess(worst, 0.01, "%s: the body is %.2f m off the ground" % (name, worst))
            W = self.skel.fk(c.local_pose(c.length))
            feet = min(self.skel.joint_world(W, b)[2] for b in ("Foot.L", "Foot.R", "Toe.L", "Toe.R"))
            self.assertLess(feet, 0.05, "%s ends with its feet %.2f m up" % (name, feet))
            self.assertAlmostEqual(self.skel.joint_world(W, "Hips")[2], hips0, delta=0.04,
                                   msg="%s does not end standing" % name)

    def test_gaits_share_a_phase(self) -> None:
        """The game blends gaits on a shared normalised timeline, which is only honest if every
        gait puts the same foot down at the same phase: left at 0, right at one half."""
        for name in anim_clips.GAIT_CLIPS:
            c = self.clips[name]
            left = c.feet.state("L", 0.001)
            right = c.feet.state("R", c.length * 0.501)
            self.assertTrue(left.planted, "%s: the left foot is not down at phase 0" % name)
            self.assertTrue(right.planted, "%s: the right foot is not down at phase 0.5" % name)
            self.assertFalse(c.feet.state("R", 0.001).planted and name not in ("Walk", "Sneak_Walk", "Walk_Back"),
                             "%s: a run has one foot down at a contact" % name)

    def test_the_turns_keep_a_planted_foot_still(self) -> None:
        """A turn on the spot is played at the rate the body turns, so a foot on the ground must go
        round the other way in the body's frame at exactly that rate: turned into the world by the
        body's own turn so far, the ball of a planted foot stays where it went down. It pivots on
        that ball, and no leg twists further than a leg turns (45 degrees past the idle's own
        toe-out). Each turn comes square at the end of its cycle, so it loops."""
        toe_out = math.radians(anim_clips.STANCES["idle"][3])
        for name in anim_clips.TURN_CLIPS:
            c = self.clips[name]
            self.assertIn("turn", c.extra, "%s carries no turn angle" % name)
            turn = math.radians(float(c.extra["turn"]))
            anchor = {"L": None, "R": None}
            for i in range(121):
                t = c.length * i / 120.0
                W = self.skel.fk(c.local_pose(t))
                R = rig.rot_axis(rig.UP, turn * i / 120.0)
                for side in ("L", "R"):
                    fs = c.feet.state(side, t)
                    twist = fs.yaw - (toe_out if side == "L" else -toe_out)
                    self.assertLess(abs(math.degrees(twist)), 45.0, "%s twists the %s leg %.0f degrees"
                                    % (name, side, math.degrees(twist)))
                    ball = R @ self.skel.joint_world(W, "Toe." + side)
                    if not fs.planted:
                        anchor[side] = None
                        continue
                    if anchor[side] is None:
                        anchor[side] = ball
                    drift = float(np.linalg.norm((ball - anchor[side])[:2]))
                    self.assertLess(drift, 0.01, "%s: the %s ball slides %.3f m while it is down" % (name, side, drift))
            a = c.local_pose(0.0)
            b = c.local_pose(c.length)
            for bone in a:
                if a[bone][0] is None or b[bone][0] is None:
                    continue
                self.assertLess(float(np.abs(a[bone][0] - b[bone][0]).max()), 0.01,
                                "%s does not come square at the end of its cycle (%s)" % (name, bone))

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
    ## The rider's clips are made with their root on the saddle (anim_clips.riding_clips): seated,
    ## the hips sit under the rest height by the legs' length; getting up and down, the body goes
    ## from the ground on the near side to the seat, 1.6 m up and 0.55 m across.
    SADDLE_CLIPS = {"Ride": 0.95, "Ride_Gallop": 0.95, "Mount_Horse": 1.7, "Dismount_Horse": 1.7}

    def test_clips_never_bake_root_motion(self) -> None:
        """CONTRACTS §2: locomotion is in place and movement is driven by code, so no clip
        may carry a Root track and only the Hips may translate."""
        for name, c in self.clips.items():
            baked = c.bake()
            self.assertNotIn("Root", baked.bones, "%s animates Root" % name)
            hips = baked.hips_pos
            limit = 1.05 if name in self.GROUND_CLIPS else (0.45 if name in self.CROUCH_CLIPS else 0.30)
            limit = self.SADDLE_CLIPS.get(name, limit)
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
