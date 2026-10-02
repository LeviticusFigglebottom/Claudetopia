"""The forged foes (lib/foe_specs.py, lib/foe_clips.py, lib/beast_body.py): pure numpy, no Blender.

What the game reads from a foe's clips (CreatureModel, AnimationDriver): every clip its def needs,
each attack with `cocked` before `hit_start` before `hit_end`, gaits with a `speed` and planted
feet that stay put at it, Death and Knockdown ending on the ground and staying there; and a body
whose skeleton stands square on the ground.
"""
from __future__ import annotations

import unittest

import numpy as np

from lib import foe_specs as FS
from lib import foe_clips as FC
from lib import quad_clips as QC
from lib.quadruped import FEET, foot_bones

NEEDED = ["Idle", "Idle_Combat", "Walk", "Run", "Walk_Back", "Attack_1", "Attack_2", "Hit", "Stagger", "Knockdown",
          "Get_Up", "Death"]


class TestFoes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.specs = {n: FS.spec(n) for n in FS.FOES}
        cls.clips = {n: FC.build(sp) for n, sp in cls.specs.items() if sp.family in ("canid", "boar", "reptile")}

    def test_standing_square_on_the_ground(self):
        for n, sp in self.specs.items():
            if sp.family not in ("canid", "boar", "reptile"):
                continue
            W = sp.skel.fk({})
            for f in FEET:
                toe = sp.skel.tail_world(W, foot_bones(f)[-1])
                self.assertAlmostEqual(float(toe[2]), 0.0, places=3, msg="%s %s" % (n, f))

    def test_every_clip_the_game_asks_for(self):
        for n, clips in self.clips.items():
            for c in NEEDED:
                self.assertIn(c, clips, "%s has %s" % (n, c))

    def test_attacks_wind_up_before_they_strike(self):
        for n, clips in self.clips.items():
            for name, c in clips.items():
                if not name.startswith("Attack"):
                    continue
                ev = {e: t for t, e in c.events}
                self.assertLess(ev["cocked"], ev["hit_start"], "%s %s" % (n, name))
                self.assertLess(ev["hit_start"], ev["hit_end"], "%s %s" % (n, name))
                self.assertLess(ev["hit_end"], ev["cancel_ok"], "%s %s" % (n, name))
                self.assertLessEqual(ev["cancel_ok"], c.length)

    def test_gaits_have_a_speed_and_keep_their_feet(self):
        for n, clips in self.clips.items():
            solver = FC.make_solver(self.specs[n].skel)
            for g in ("Walk", "Trot"):
                c = clips[g]
                self.assertIn("speed", c.extra, "%s %s" % (n, g))
                slip = QC.toe_slip(solver, c, float(c.extra["speed"]))
                self.assertLess(slip, 0.06 * self.specs[n].skel.props.withers / 0.8 + 0.02, "%s %s slides %.3f m" % (n, g, slip))

    def test_the_dead_lie_on_the_ground(self):
        for n, clips in self.clips.items():
            sp = self.specs[n]
            for name in ("Death", "Knockdown"):
                c = clips[name]
                W = FC.pose_matrices(sp, c, c.length)
                hips = W["Hips"][:3, 3]
                self.assertLess(float(hips[2]), 0.45 * sp.skel.J["Hips"][2], "%s %s ends down" % (n, name))
                low = min(float(W[b][2, 3]) for b in W)
                self.assertGreater(low, -0.04, "%s %s: nothing far under the ground (%.3f)" % (n, name, low))

    def test_reach(self):
        for n, clips in self.clips.items():
            solver = FC.make_solver(self.specs[n].skel)
            for name in ("Walk", "Trot", "Idle", "Attack_1", "Idle_Combat"):
                c = clips[name]
                for i in range(0, int(c.length * 30) + 1):
                    solver.solve(c.sample(min(i / 30.0, c.length)))
            self.assertLess(solver.reach_error, 0.05, "%s: a leg falls short by %.3f m" % (n, solver.reach_error))


if __name__ == "__main__":
    unittest.main()
