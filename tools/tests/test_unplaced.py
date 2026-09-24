#!/usr/bin/env python3
"""What the audit of what nothing places counts as putting a thing in front of a player.

    python3 tools/tests/test_unplaced.py     # or: python3 -m unittest discover tools/tests

`tools/unplaced.py` lists the definitions no way of the built game's reaches. A way it does not
know of shows up as a false report: the chart in the Reed Wreck and the hermit's exercise book on
Willow Isle were reported as placed nowhere, though each place's encounter says it lies there and
QuestItems puts it down. These are checked on synthetic definitions, which needs nothing built.
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)

import unplaced  # noqa: E402


class WhatLiesAtAPlace(unittest.TestCase):
    def test_an_item_an_encounter_says_lies_at_its_place_is_placed(self):
        defs = {
            "core:item/test_chart": {"id": "core:item/test_chart"},
            "core:item/test_nowhere": {"id": "core:item/test_nowhere"},
            "core:encounter/test_wreck": {"id": "core:encounter/test_wreck", "place": "core:poi/test_wreck",
                                          "lies": [{"item": "core:item/test_chart", "at": "the_chart"}]},
        }
        src = unplaced.item_sources(defs)
        self.assertIn("lies at core:poi/test_wreck", src["core:item/test_chart"])
        self.assertFalse(src.get("core:item/test_nowhere"), "an item nothing names is still placed nowhere")

    def test_a_book_an_encounter_says_lies_at_its_place_is_read_there(self):
        defs = {
            "core:book/test_exercise": {"id": "core:book/test_exercise"},
            "core:encounter/test_isle": {"id": "core:encounter/test_isle", "place": "core:poi/test_isle",
                                         "lies": [{"book": "core:book/test_exercise", "at": "the_hermits_book"}]},
        }
        books = unplaced.read_books(defs, set())
        self.assertEqual(books["core:book/test_exercise"], ["lies at core:poi/test_isle"])

    def test_an_encounter_with_nothing_lying_places_nothing(self):
        defs = {
            "core:item/test_chart": {"id": "core:item/test_chart"},
            "core:encounter/test_camp": {"id": "core:encounter/test_camp", "place": "core:poi/test_camp",
                                         "spawns": [{"enemy": "core:enemy/test_raider", "count": 3}]},
        }
        self.assertFalse(unplaced.item_sources(defs).get("core:item/test_chart"))
        self.assertFalse(unplaced.read_books(defs, set()))


if __name__ == "__main__":
    unittest.main()
