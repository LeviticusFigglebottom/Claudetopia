"""Palette parsing and role derivation (pure Python, no Blender)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import palette as P  # noqa: E402


class TestColourMath(unittest.TestCase):
    def test_hex_round_trip(self):
        for h in ("#c9a24a", "#000000", "#ffffff", "#1e1c1b"):
            self.assertEqual(P.srgb_to_hex(P.hex_to_srgb(h)), h)

    def test_short_hex(self):
        self.assertEqual(P.hex_to_srgb("#fff"), P.hex_to_srgb("#ffffff"))

    def test_bad_hex_raises(self):
        for bad in ("#12345", "nope", ""):
            with self.assertRaises(ValueError):
                P.hex_to_srgb(bad)

    def test_linear_round_trip(self):
        for h in ("#c9a24a", "#3f7fb5", "#efe7d2"):
            c = P.hex_to_srgb(h)
            back = P.linear_to_srgb(P.srgb_to_linear(c))
            for a, b in zip(c, back):
                self.assertAlmostEqual(a, b, places=6)

    def test_linear_is_darker_than_srgb(self):
        # sRGB 0.5 is about 0.21 in linear light; getting this backwards washes everything out.
        self.assertLess(P.srgb_channel_to_linear(0.5), 0.25)
        self.assertGreater(P.srgb_channel_to_linear(0.5), 0.18)

    def test_luminance_ordering(self):
        white = P.lin("#ffffff")
        grey = P.lin("#808080")
        black = P.lin("#000000")
        self.assertGreater(P.luminance(white), P.luminance(grey))
        self.assertGreater(P.luminance(grey), P.luminance(black))


class TestPalette(unittest.TestCase):
    def test_every_region_loads(self):
        ids = P.region_ids()
        self.assertGreaterEqual(len(ids), 6)
        for rid in ids:
            pal = P.get_palette(rid)
            self.assertEqual(len(pal.hexes), 6, "%s should have 6 colours" % rid)
            self.assertTrue(pal.flora, "%s should list flora" % rid)

    def test_lookup_forms(self):
        a = P.get_palette("hearthvale")
        b = P.get_palette("core:region/hearthvale")
        c = P.get_palette("region/hearthvale")
        self.assertEqual(a.hexes, b.hexes)
        self.assertEqual(a.hexes, c.hexes)

    def test_unknown_region_raises(self):
        with self.assertRaises(KeyError):
            P.get_palette("nowhere")

    def test_neutral_palette(self):
        for name in (None, "neutral", "none"):
            pal = P.get_palette(name)
            self.assertEqual(pal.short, "neutral")

    def test_all_roles_resolve_for_all_regions(self):
        for pal in P.all_palettes():
            for role in P.ROLES:
                c = pal.role(role)
                self.assertEqual(len(c), 3)
                for v in c:
                    self.assertGreaterEqual(v, 0.0)
                    self.assertLessEqual(v, 1.0)
                self.assertIn(pal.role_hex(role), pal.hexes)

    def test_unknown_role_raises(self):
        with self.assertRaises(KeyError):
            P.get_palette("hearthvale").role("sparkly")

    def test_light_is_lighter_than_dark(self):
        for pal in P.all_palettes():
            self.assertGreater(P.luminance(pal.role("light")), P.luminance(pal.role("dark")),
                               "%s light/dark inverted" % pal.short)

    def test_regions_are_visually_distinct(self):
        """DESIGN §10.1: region palettes must be separable. No two regions may share a
        palette, and their mean colours must differ."""
        seen = {}
        means = {}
        for pal in P.all_palettes():
            key = tuple(pal.hexes)
            self.assertNotIn(key, seen, "%s and %s share a palette" % (pal.short, seen.get(key)))
            seen[key] = pal.short
            means[pal.short] = tuple(sum(c[i] for c in pal.srgb) / len(pal.srgb) for i in range(3))
        names = sorted(means)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                d = sum(abs(means[a][k] - means[b][k]) for k in range(3))
                self.assertGreater(d, 0.05, "%s and %s read the same overall" % (a, b))

    def test_expected_region_character(self):
        """The palettes must actually say what WORLD_BIBLE §6 says they say."""
        hv = P.get_palette("hearthvale")
        self.assertGreater(hv.role("warm")[0], hv.role("warm")[2], "Hearthvale's warm is not warm")
        bw = P.get_palette("brightwater")
        self.assertGreater(bw.role("cool")[2], bw.role("cool")[0], "Brightwater's cool is not blue")
        cl = P.get_palette("cinderlea")
        # Cinderlea is desaturated ash: its mean saturation is the lowest of the six.
        def sat(pal):
            total = 0.0
            for c in pal.srgb:
                mx, mn = max(c), min(c)
                total += 0.0 if mx == 0 else (mx - mn) / mx
            return total / len(pal.srgb)
        self.assertEqual(min(P.all_palettes(), key=sat).short, cl.short)

    def test_tint_moves_toward_role(self):
        pal = P.get_palette("sedgemire")
        base = P.lin("#808080")
        tinted = pal.tint(base, "cool", 1.0)
        for a, b in zip(tinted, pal.role("cool")):
            self.assertAlmostEqual(a, b, places=6)
        self.assertEqual(pal.tint(base, "cool", 0.0), base)

    def test_to_meta_is_json_safe(self):
        import json
        meta = P.get_palette("skerrow").to_meta()
        json.loads(json.dumps(meta))
        self.assertEqual(len(meta["colors"]), 6)
        self.assertEqual(set(meta["roles"]), set(P.ROLES))


if __name__ == "__main__":
    unittest.main()
