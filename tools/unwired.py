#!/usr/bin/env python3
"""What the game can do and never does: public functions only the tests call.

A system can be complete, correct, covered and inert. Nothing in a green suite says that
`NpcRegistry.spawn()` has one caller and it is a test, or that `Bounty.commit()` is never
reached by the two crimes a player is most likely to commit. Both of those shipped in this
project and both were found by this question:

    does anything outside `game/tests/` ever call this?

It is a text scan, not a compiler, so read the output rather than trusting it. Three kinds of
false positive are expected and harmless:

  * accessors and predicates a test asserts on and nothing else needs (`armour_total`);
  * functions called from the same file without a `.` prefix, which this deliberately does not
    count, because a self-call is not evidence that the world reaches the system;
  * anything reached through `call("name")` or `has_method("name")`, which this *does* count,
    by looking for the quoted name as well.

Usage:
    tools/unwired.py [--verbs] [--dir game]

`--verbs` narrows to names that sound like actions, which is where the real findings are: a
query nobody calls is dead weight, but a *verb* nobody calls is a feature that does not happen.
"""
from __future__ import annotations

import argparse
import collections
import os
import re

TEST_DIRS = {"tests", "tools_gd"}
VERBS = (
    "spawn|start|begin|install|collect|enter|open|close|trigger|award|place|drop|advance|"
    "perform|apply|run|refresh|rebuild|simulate|pay|sell|buy|steal|rest|travel|sleep|wander|"
    "patrol|work|use|read|equip|craft|brew|temper|enchant|learn|teach|join|leave|arrest|jail|"
    "fine|report|notice|react|greet|talk|gossip|commit|kill|die|take|give|move|set|add|remove"
)


def gather(root: str) -> tuple[dict, collections.Counter, collections.Counter]:
    defined: dict[str, list] = {}
    for base, _dirs, files in os.walk(root):
        if set(base.split(os.sep)) & TEST_DIRS:
            continue
        for f in files:
            if not f.endswith(".gd"):
                continue
            path = os.path.join(base, f)
            with open(path, encoding="utf-8") as fh:
                for i, line in enumerate(fh, 1):
                    m = re.match(r"^(static )?func ([a-z][a-z0-9_]*)\(", line)
                    if m and not m.group(2).startswith("_"):
                        defined.setdefault(m.group(2), []).append((path, i))

    from_game: collections.Counter = collections.Counter()
    from_tests: collections.Counter = collections.Counter()
    names = list(defined)
    for base, _dirs, files in os.walk(root):
        is_test = bool(set(base.split(os.sep)) & TEST_DIRS)
        for f in files:
            if not f.endswith(".gd"):
                continue
            text = open(os.path.join(base, f), encoding="utf-8").read()
            for name in names:
                n = len(re.findall(r"[.\"']%s\(" % re.escape(name), text))
                n += len(re.findall(r'"%s"' % re.escape(name), text))
                if n:
                    (from_tests if is_test else from_game)[name] += n
    return defined, from_game, from_tests


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="game")
    ap.add_argument("--verbs", action="store_true",
                    help="only names that sound like actions, which is where the findings are")
    a = ap.parse_args()
    defined, from_game, from_tests = gather(a.dir)
    rows = []
    for name, sites in sorted(defined.items()):
        if from_game[name] or not from_tests[name]:
            continue
        if a.verbs and not re.match(r"^(%s)(_|$)" % VERBS, name):
            continue
        rows.append((name, sites, from_tests[name]))
    print("%d public functions in %s; %d are reached only by the tests%s\n"
          % (len(defined), a.dir, len(rows), " (verbs only)" if a.verbs else ""))
    for name, sites, n in rows:
        where = ", ".join("%s:%d" % s for s in sites[:2])
        print("  %-32s %-56s tests:%d" % (name, where, n))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
