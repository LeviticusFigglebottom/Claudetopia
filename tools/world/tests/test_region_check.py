"""Every region's POI content passes its definition-of-done content check (tools/world/region_check.py,
docs/WORLD_LIFE.md), and the audit's impact score reads as documented. Needs the installed world's
runtime maps (game/world/generated), and skips without them."""
from __future__ import annotations

import os
import sys
import unittest

TOOLS_WORLD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS_WORLD)

import region_audit as AUD  # noqa: E402

HAVE_WORLD = os.path.exists(os.path.join(AUD.GEN, "world_manifest.json"))


@unittest.skipUnless(HAVE_WORLD, "no installed world")
class RegionContent(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import region_check as RC
        from worldgen import atlas as ATLAS
        cls.RC = RC
        cls.world = AUD.World()
        cls.content = AUD.load_content()
        cls.atlas = ATLAS.load()

    def test_every_regions_content_passes(self):
        for region in AUD.REGIONS:
            part = self.RC.check_content(region, self.world, self.content, self.atlas)
            self.assertEqual(part.fails, [], region)


class Score(unittest.TestCase):
    def test_size_points(self):
        self.assertEqual([AUD.size_points(r) for r in (5, 10, 20, 30, 50)], [0, 1, 2, 3, 4])


if __name__ == "__main__":
    unittest.main()
