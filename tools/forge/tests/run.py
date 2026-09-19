#!/usr/bin/env python3
"""Run the forge test suite.

    python3 tools/forge/tests/run.py            # everything (end-to-end needs Blender)
    python3 tools/forge/tests/run.py --fast     # pure Python only, no Blender
    python3 tools/forge/tests/run.py palette    # only modules matching a substring
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

FORGE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(FORGE))

MODULES = ["tests.test_palette", "tests.test_paths", "tests.test_generation"]


def main(argv: list[str]) -> int:
    fast = "--fast" in argv
    filters = [a for a in argv if not a.startswith("-")]
    names = [m for m in MODULES if not (fast and m.endswith("test_generation"))]
    if filters:
        names = [m for m in names if any(f in m for f in filters)]
    if not names:
        print("no test modules match %s" % filters)
        return 1
    loader = unittest.TestLoader()
    suite = unittest.TestSuite(loader.loadTestsFromName(n) for n in names)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
