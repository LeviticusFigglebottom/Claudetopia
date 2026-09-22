#!/usr/bin/env python3
"""The promises the region danger ratings make, checked against the content pack.

    python3 tools/tests/test_balance.py     # or: python3 -m unittest discover tools/tests

`tools/balance.py` prints the curves and says when one is out of shape. It is only read when
somebody runs it, so the two inversions it found in the first calibration sat in the pack for
weeks. This runs the same model and fails the build instead.

What is asserted here is what a `danger` rating promises a player, and nothing about
magnitudes: a region one step further into the world may not be *safer* than the one before
it, and the marsh may not pay less than the downs you started in. Both are orderings. The
numbers themselves are still uncalibrated guesses (ASSESSMENT.md) and this says nothing
about whether any of them is fun.
"""
from __future__ import annotations

import os
import statistics
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)

import balance  # noqa: E402

## The tool's own tolerance for "no safer than": half a hit of slack, so two regions written
## for the same point in the curve are not made to agree to one decimal place.
SLACK_HITS = 0.5
## Brightwater and Hearthvale are both rated danger 1, and Brightwater's roster is three city
## criminals who carry purses against the downs' three animals who do not, so Brightwater
## pays 2.5 times what Hearthvale does at the same rating. That makes the marsh after it look
## poor by comparison however the marsh is loaded, and the honest comparison for Sedgemire is
## the region the player actually came from. See DECISIONS.md, "Two orderings the data broke".
PAY_EXEMPT_PAIRS = {("brightwater", "sedgemire")}


def regions_in_world_order():
    items = balance.by_id(balance.load("items"))
    tables = balance.by_id(balance.load("loot"))
    spells = balance.by_id(balance.load("spells"))
    rows = balance.enemy_rows(balance.load("enemies"), tables, items, 10, spells)
    out = []
    for r in sorted(balance.load("regions"), key=lambda d: d.get("danger", 0)):
        here = [x for x in rows if x["region"] == r["id"]]
        if not here:
            continue
        out.append({
            "name": r["id"].split("/")[-1],
            "danger": r.get("danger", 0),
            "hits_to_kill_you": statistics.mean(x["hits_to_kill_you"] for x in here),
            "pay": statistics.mean(x["pay"] for x in here),
            "worst_hit_share": max(x["worst_hit_share"] for x in here),
        })
    return out


class TestDangerIsAPromise(unittest.TestCase):
    def setUp(self):
        self.regions = regions_in_world_order()

    def test_every_region_fields_something_to_fight(self):
        self.assertEqual(len(self.regions), 6,
                         "a region has no enemies in its ecology at all")

    def test_no_later_region_is_safer_than_the_one_before_it(self):
        """Hits to kill you must not go up as danger goes up.

        Brightwater read 13.1 against Hearthvale's 6.9 when this was written: its Bravo, the
        only elite in a region rated as dangerous as the starting downs, thrust for less than
        a Hearthvale bandit slashed, and its Gutter Drake's sewer bite carried nothing after
        it. A danger rating is a promise to the player.
        """
        for before, after in zip(self.regions, self.regions[1:]):
            self.assertLessEqual(
                after["hits_to_kill_you"], before["hits_to_kill_you"] + SLACK_HITS,
                "%s (danger %d) is SAFER than %s (danger %d): %.1f hits to kill you "
                "against %.1f, though the world puts it later"
                % (after["name"], after["danger"], before["name"], before["danger"],
                   after["hits_to_kill_you"], before["hits_to_kill_you"]))

    def test_the_hardest_hit_in_each_region_gets_harder(self):
        """The worst single blow rises from a third of your health to well over half."""
        first, last = self.regions[0], self.regions[-1]
        self.assertGreater(last["worst_hit_share"], first["worst_hit_share"] * 1.5,
                           "the last region's hardest hit is no worse than the first's")
        for r in self.regions:
            self.assertLess(r["worst_hit_share"], 1.0,
                            "%s has a single hit that kills a full-health player outright"
                            % r["name"])

    def test_pay_does_not_fall_as_the_world_gets_more_dangerous(self):
        """A more dangerous fight may not pay less than the one before it.

        Sedgemire read 19 marks a fight against Brightwater's 74: three marsh animals and a
        corpse, and the corpse — the brute of a region rated one step past the start —
        carried less than a Hearthvale roadside bandit.
        """
        for before, after in zip(self.regions, self.regions[1:]):
            if (before["name"], after["name"]) in PAY_EXEMPT_PAIRS:
                continue
            self.assertGreaterEqual(
                after["pay"], before["pay"] * 0.9,
                "%s pays LESS than %s (%.0f marks a fight against %.0f) for a more "
                "dangerous fight" % (after["name"], before["name"],
                                     after["pay"], before["pay"]))

    def test_the_marsh_pays_better_than_the_downs_you_started_in(self):
        """The pair the exemption above skips still has a floor: Sedgemire is danger 2 and
        must out-pay the danger-1 region the player came from, whatever Brightwater does."""
        by_name = {r["name"]: r for r in self.regions}
        self.assertGreater(by_name["sedgemire"]["pay"], by_name["hearthvale"]["pay"],
                           "the marsh pays less than the starting downs")


class TestTheModelReadsWhatTheGameUses(unittest.TestCase):
    """The reading gaps that hid both inversions. Each is a number the game acts on and the
    tool used to score as zero."""

    def setUp(self):
        self.spells = balance.by_id(balance.load("spells"))
        self.items = balance.by_id(balance.load("items"))
        self.tables = balance.by_id(balance.load("loot"))

    def test_a_casters_spell_damage_is_counted(self):
        """A spell attack has no `damage` of its own: enemy.gd sends it through the caster."""
        cast = {"name": "hush_frost", "kind": "spell", "spell": "core:spell/hush_frost",
                "damage": 0.0}
        self.assertGreater(balance.attack_damage(cast, self.spells), 0.0,
                           "a caster's spell reads as doing nothing")

    def test_a_bleed_is_counted_and_a_chill_is_not(self):
        bleed = {"damage": 10.0,
                 "statuses": [{"id": "bleeding", "duration": 6.0, "magnitude": 2.0}]}
        chill = {"damage": 10.0, "statuses": [{"id": "chilled", "duration": 6.0}]}
        self.assertEqual(balance.attack_damage(bleed, self.spells), 22.0)
        self.assertEqual(balance.attack_damage(chill, self.spells), 10.0)

    def test_the_hardest_single_hit_leaves_the_aftermath_out(self):
        """Whether a blow kills you outright is decided by the blow, not by the bleed."""
        bleed = {"damage": 10.0,
                 "statuses": [{"id": "bleeding", "duration": 6.0, "magnitude": 2.0}]}
        self.assertEqual(balance.attack_impact(bleed, self.spells), 10.0)

    def test_guaranteed_loot_is_counted(self):
        """A sallowjaw's hide is the whole reason Isseva hunts one, and it read as worth
        nothing because it is `guaranteed` rather than one of the weighted picks."""
        value = balance.loot_value("core:loot/sallowjaw", self.tables, self.items)
        hide = float(self.items["core:item/sallow_hide"]["value"])
        self.assertGreater(value, hide * 0.5,
                           "the hide a sallowjaw always leaves is not in its value")

    def test_a_nested_table_is_rolled_in_full(self):
        nested = {"id": "_t", "rolls": 1,
                  "entries": [{"table": "core:loot/sallowjaw", "weight": 1}]}
        tables = dict(self.tables)
        tables["_t"] = nested
        self.assertAlmostEqual(balance.loot_value("_t", tables, self.items),
                               balance.loot_value("core:loot/sallowjaw", tables, self.items),
                               places=6)


if __name__ == "__main__":
    unittest.main(verbosity=2)
