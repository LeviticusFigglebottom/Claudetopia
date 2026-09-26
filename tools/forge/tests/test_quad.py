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


class TestFarHerd(unittest.TestCase):
    """The far herd's colours (lib/far_herd.py), in the water agent's layout."""

    def test_colours_name_the_parts(self):
        from lib import far_herd as FH
        sk = Q.QuadSkeleton()
        J = sk.J
        pts = {"fl": (J["FrontCannon.L"] + J["FrontPastern.L"]) / 2, "fr": (J["FrontCannon.R"] + J["FrontPastern.R"]) / 2,
               "hl": (J["HindCannon.L"] + J["HindPastern.L"]) / 2, "hr": (J["HindCannon.R"] + J["HindPastern.R"]) / 2,
               "withers": J["Chest"] + np.array([0.0, 0.0, 0.1]), "muzzle": J["Muzzle"], "barrel": J["Spine2"] - np.array([0, 0, 0.3]),
               "tail_root": J["TailHead"], "tail_tip": J["TailTip"]}
        names = list(pts)
        P = np.array([pts[n] for n in names])
        bones = Q.DEFORM_NAMES
        W = np.zeros((len(P), len(bones)))
        own = {"fl": "FrontCannon.L", "fr": "FrontCannon.R", "hl": "HindCannon.L", "hr": "HindCannon.R", "withers": "Chest",
               "muzzle": "Head", "barrel": "Spine2", "tail_root": "Tail1", "tail_tip": "Tail3"}
        for i, n in enumerate(names):
            W[i, bones.index(own[n])] = 1.0
        C = dict(zip(names, FH.herd_colours(P, W, bones, sk)))
        self.assertEqual([C[n][0] for n in ("fl", "fr", "hl", "hr")], [0.25, 0.5, 0.75, 1.0])
        self.assertEqual(C["barrel"][0], 0.0)
        self.assertLess(C["withers"][1], 0.05)
        self.assertGreater(C["muzzle"][1], 0.95)
        self.assertLess(C["tail_root"][2], 0.05)
        self.assertGreater(C["tail_tip"][2], 0.95)
        self.assertTrue(all(C[n][3] == 1.0 for n in names))


class TestDeer(unittest.TestCase):
    """The red deer (lib/deer_body.py) and its clips."""

    @classmethod
    def setUpClass(cls):
        from lib import deer_body as DB
        cls.DB = DB
        cls.sk = Q.QuadSkeleton(DB.RED)
        cls.solver = QC.make_solver(cls.sk)
        cls.clips = QC.build_deer_clips(cls.solver)

    def test_a_red_deer_is_its_size(self):
        J = self.sk.J
        # withers 1.15 m; nose to the tail's root about 1.9 m, measured along the ground
        self.assertAlmostEqual(self.sk.props.withers, 1.15)
        length = J["TailHead"][1] - J["Muzzle"][1]
        self.assertGreater(length, 1.6)
        self.assertLess(length, 2.1)
        # the neck carried higher than a horse's: the poll well above the withers
        self.assertGreater(J["Head"][2] - J["Chest"][2], 0.35)

    def test_every_deer_clip_is_there_and_loops_whole(self):
        for n in QC.DEER_CLIPS:
            self.assertIn(n, self.clips)
            c = self.clips[n]
            self.assertAlmostEqual(c.length * QC.FPS, round(c.length * QC.FPS), places=6, msg=n)

    def test_the_flight_leaves_the_ground(self):
        # a bound: somewhere in the stride all four hooves are up
        c = self.clips["Flee"]
        airborne = False
        for i in range(40):
            p = c.sample(c.length * i / 40)
            if all(not p.feet[f].planted for f in Q.FEET):
                airborne = True
        self.assertTrue(airborne, "the Flee never has all four feet off the ground")

    def test_graze_puts_the_muzzle_in_the_grass(self):
        for n in ("Graze", "Graze_Step"):
            c = self.clips[n]
            for i in range(4):
                R, th = self.solver.solve(c.sample(c.length * i / 4))
                W = self.sk.fk({k: (v, th if k == "Hips" else None) for k, v in R.items()})
                z = float(self.sk.tail_world(W, "Head")[2])
                self.assertLess(z, 0.25, "%s: the muzzle at %.2f m" % (n, z))
                self.assertGreater(z, 0.02, "%s: the muzzle in the ground at %.2f m" % (n, z))

    def test_the_antlers_stand_on_the_poll(self):
        sc = self.DB.antler_scene(self.sk)
        lo, hi = sc.bounds(0.0)
        poll = self.sk.J["Head"]
        self.assertLess(abs(lo[2] - poll[2]), 0.12)
        self.assertGreater(hi[2] - poll[2], 0.45)
        self.assertGreater(hi[0] - lo[0], 0.45)


if __name__ == "__main__":
    unittest.main()
