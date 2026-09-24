"""WM_Quadruped_v1 and its clips (lib/quadruped.py, lib/quad_clips.py): pure numpy, no Blender.

What the rig promises (CONTRACTS §2b, §3b): one set of bone names for every hoofed beast, scaled
by proportions; the rest pose standing square on the ground; gaits made from footfall timings,
the hind left landing at phase 0, whose planted hooves stand still on the ground at the clip's
`speed`; every loop a whole number of frames.
"""
from __future__ import annotations

import unittest

import numpy as np

from lib import quadruped as Q
from lib import quad_clips as QC

DEER = Q.QuadProportions(withers=1.2, body_length=0.9, leg_length=1.15, neck_length=1.1, head_size=0.8,
                         bulk=0.7, cannon=1.2, tail_length=0.35)


class TestSkeleton(unittest.TestCase):
    def test_bone_names_are_the_contracts(self):
        sk = Q.QuadSkeleton()
        for b in ["Root", "Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "Ear.L", "Ear.R",
                  "Tail1", "Tail2", "Tail3", "Socket.Saddle", "Socket.Bit", "Socket.Pack", "Socket.Head"]:
            self.assertIn(b, sk.bones)
        for side in ("L", "R"):
            for n in Q.LEG_FORE + Q.LEG_HIND:
                self.assertIn("%s.%s" % (n, side), sk.bones)
        self.assertEqual(len(Q.DEFORM_NAMES), 35)

    def test_standing_square_on_the_ground(self):
        for props in (None, DEER):
            sk = Q.QuadSkeleton(props)
            W = sk.fk({})
            for f in Q.FEET:
                toe = sk.tail_world(W, Q.foot_bones(f)[-1])
                self.assertAlmostEqual(float(toe[2]), 0.0, places=4)
            # the left legs on the left (+X), the fore legs ahead (-Y)
            self.assertGreater(sk.J["FrontToe.L"][0], 0.0)
            self.assertLess(sk.J["FrontToe.L"][1], sk.J["HindToe.L"][1])

    def test_a_deer_is_the_same_rig_in_other_proportions(self):
        horse, deer = Q.QuadSkeleton(), Q.QuadSkeleton(DEER)
        self.assertEqual(horse.order, deer.order)
        self.assertLess(deer.J["Chest"][2], horse.J["Chest"][2])
        leg = lambda sk: sk.J["Forearm.L"][2] / sk.J["Chest"][2]
        self.assertGreater(leg(deer), leg(horse))

    def test_leg_frames_keep_their_axis_across_the_body(self):
        # a hoof folded past pointing straight back keeps its X across the body
        for d in ([0.0, 1.0, 0.01], [0.0, 0.7, 0.7], [0.0, -1.0, 0.0]):
            F = Q.frame_lateral(np.array(d, float))
            self.assertGreater(-F[0, 0], 0.99)


class TestClips(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sk = Q.QuadSkeleton()
        cls.solver = QC.make_solver(cls.sk)
        cls.clips = QC.build_clips(cls.solver)

    def test_the_mount_set_is_complete_and_keeps_the_contract(self):
        self.assertEqual(QC.check_contract(self.clips), [])

    def test_rest_solves_to_rest(self):
        R, t = self.solver.solve(QC.QuadPose())
        self.assertLess(float(np.abs(t).max()), 1e-6)
        for b, r in R.items():
            ang = np.degrees(np.arccos(np.clip((np.trace(r) - 1) / 2, -1, 1)))
            self.assertLess(ang, 8.0, b)

    def test_every_gait_lands_the_hind_left_at_phase_0(self):
        for g in QC.horse_gaits():
            self.assertEqual(g.footfalls["HL"], 0.0, g.name)

    def test_planted_hooves_stand_still(self):
        for g in QC.horse_gaits():
            c = self.clips[g.name]
            speed = 0.0 if g.turn else g.speed
            drift = QC.toe_slip(self.solver, c, speed, samples=40)
            self.assertLess(drift, 0.06, "%s: a planted hoof strays %.3f m" % (g.name, drift))

    def test_sidecar_speeds_are_the_games(self):
        want = {"Walk": 1.8, "Trot": 3.8, "Canter": 7.0, "Gallop": 11.5}
        for n, v in want.items():
            self.assertAlmostEqual(self.clips[n].extra["speed"], v, places=3)
        self.assertEqual(self.clips["Turn_L90"].extra["turn"], 90.0)
        self.assertEqual(self.clips["Turn_R90"].extra["turn"], -90.0)

    def test_every_hoof_lands_in_every_gait(self):
        for g in QC.horse_gaits():
            names = sorted(e for _, e in self.clips[g.name].events)
            self.assertEqual(names, ["hoof_fl", "hoof_fr", "hoof_hl", "hoof_hr"], g.name)

    def test_baked_loops_close(self):
        c = self.clips["Trot"].bake(self.solver)
        self.assertEqual(c.frames, round(c.length * c.fps))
        # the frame after the last is the first again: the loop's seam is one step like any other
        nxt = self.clips["Trot"].sample(c.length)
        first = self.clips["Trot"].sample(0.0)
        for f in Q.FEET:
            self.assertLess(float(np.linalg.norm(nxt.feet[f].toe - first.feet[f].toe)), 1e-6)


if __name__ == "__main__":
    unittest.main()
