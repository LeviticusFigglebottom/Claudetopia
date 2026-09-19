#!/usr/bin/env python3
"""Dependency-free test runner for the audio toolkit (pytest is not installed in this container).

Discovers test_*.py next to this file, runs every module-level test_* function, prints a report
and exits non-zero on any failure.

    python3 tools/audio/tests/run_tests.py [--filter substring] [-v]
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))


def load_module(path: str):
    name = "audiotest_" + os.path.basename(path)[:-3]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--filter", default="")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    files = sorted(f for f in os.listdir(HERE) if f.startswith("test_") and f.endswith(".py"))
    total = failed = skipped = 0
    failures: list[tuple[str, str]] = []
    t0 = time.time()
    for f in files:
        if args.filter and args.filter not in f:
            pass  # a file may still hold matching test names
        try:
            mod = load_module(os.path.join(HERE, f))
        except Exception:
            failures.append((f, traceback.format_exc()))
            failed += 1
            print("  LOAD FAIL %s" % f)
            continue
        names = [n for n in dir(mod) if n.startswith("test_") and callable(getattr(mod, n))]
        for n in sorted(names):
            label = "%s::%s" % (f[:-3], n)
            if args.filter and args.filter not in label:
                skipped += 1
                continue
            total += 1
            t1 = time.time()
            try:
                getattr(mod, n)()
                if args.verbose:
                    print("  ok   %-56s %5.0f ms" % (label, (time.time() - t1) * 1000))
                else:
                    print("  ok   %s" % label)
            except Exception:
                failed += 1
                failures.append((label, traceback.format_exc()))
                print("  FAIL %s" % label)
    print("")
    for label, tb in failures:
        print("=" * 72)
        print("FAILURE: %s" % label)
        print(tb)
    print("%d tests, %d failed, %d skipped, %.1f s" % (total, failed, skipped, time.time() - t0))
    print("RESULT: %s" % ("PASS" if failed == 0 else "FAIL"))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
