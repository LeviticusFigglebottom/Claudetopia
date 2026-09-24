#!/usr/bin/env python3
"""The warning census reads its log right, and its ratchet holds.

    python3 tools/tests/test_warning_census.py     # or: python3 -m unittest discover tools/tests

`tools/debug/warning_census.py` has Godot compile every script with each warn-level warning made
an error and reads the warnings out of the log. The census itself needs Godot and a minute; this
checks, on a log written here, that each warning is counted once under the script it is in (not
the stand-in path the census compiles it under), that the game's scripts are counted apart from
their tests and tools, and that the check fails when the game's count goes over the baseline.
"""
from __future__ import annotations

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(TOOLS, "debug"))

import warning_census as census  # noqa: E402

LOG = """\
CENSUS compiling 3 scripts
SCRIPT ERROR: Parse Error: The local function parameter "name" is shadowing an already-declared property in the base class "Node". (Warning treated as error.)
          at: GDScript::reload (res://__census__/world/thing.gd:12)
SCRIPT ERROR: Parse Error: Integer division. Decimal part will be discarded. (Warning treated as error.)
          at: GDScript::reload (res://__census__/world/thing.gd:40)
SCRIPT ERROR: Parse Error: Integer division. Decimal part will be discarded. (Warning treated as error.)
          at: GDScript::reload (res://world/thing.gd:40)
SCRIPT ERROR: Parse Error: The variable "seed" has the same name as a built-in function. (Warning treated as error.)
          at: GDScript::reload (res://__census__/tests/unit/test_thing.gd:3)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: GDScript::reload (res://__census__/ui/other.gd:0)
SCRIPT ERROR: Parse Error: Integer division. Decimal part will be discarded. (Warning treated as error.)
          at: GDScript::reload (res://__census__/tools_gd/probe.gd:7)
CENSUS done
"""


class ReadingTheLog(unittest.TestCase):
    def test_each_warning_is_counted_once_under_its_own_script(self):
        found = census.parse(LOG)
        self.assertEqual(found, [
            ("res://tests/unit/test_thing.gd", 3, 'The variable "seed" has the same name as a built-in function.'),
            ("res://tools_gd/probe.gd", 7, "Integer division. Decimal part will be discarded."),
            ("res://world/thing.gd", 12, 'The local function parameter "name" is shadowing an already-declared property in the base class "Node".'),
            ("res://world/thing.gd", 40, "Integer division. Decimal part will be discarded."),
        ])

    def test_the_game_is_counted_apart_from_its_tests_and_tools(self):
        now = census.counts(census.parse(LOG))
        self.assertEqual((now["game"], now["tests"], now["tools_gd"]), (2, 1, 1))
        self.assertEqual(now["game_by_file"], {"res://world/thing.gd": 2})

    def test_a_kind_is_the_message_without_its_names(self):
        self.assertEqual(census.kind_of('The variable "seed" has the same name as a built-in function.'),
                         'The variable "X" has the same name as a built-in function.')


class TheRatchet(unittest.TestCase):
    def test_more_than_the_baseline_fails_and_says_where(self):
        base = {"game": 2, "game_by_file": {"res://a.gd": 1, "res://b.gd": 1}}
        now = {"game": 3, "game_by_file": {"res://a.gd": 1, "res://b.gd": 2}}
        ok, grew = census.verdict(now, base)
        self.assertFalse(ok)
        self.assertEqual(grew, [("res://b.gd", 2, 1)])

    def test_the_baseline_or_under_passes(self):
        base = {"game": 2, "game_by_file": {"res://a.gd": 2}}
        self.assertTrue(census.verdict({"game": 2, "game_by_file": {"res://a.gd": 2}}, base)[0])
        # a warning moved from one file to another is not a warning more
        self.assertTrue(census.verdict({"game": 2, "game_by_file": {"res://a.gd": 1, "res://c.gd": 1}}, base)[0])
        self.assertTrue(census.verdict({"game": 0, "game_by_file": {}}, base)[0])

    def test_the_committed_baseline_is_there_and_counts_the_game(self):
        import json
        base = json.loads(open(census.BASELINE, encoding="utf-8").read())
        self.assertEqual(base["game"], sum(base["game_by_file"].values()))
        self.assertTrue(all(p.startswith("res://") and not p.startswith(("res://tests/", "res://tools_gd/"))
                            for p in base["game_by_file"]))


if __name__ == "__main__":
    unittest.main()
