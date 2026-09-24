#!/usr/bin/env python3
"""Counts the errors and warnings a Godot run printed, deduplicated, with where each came from.

What the editor's debugger lists for a play session is what the engine prints to the terminal:
`ERROR:` (the engine's own, and every `push_error`, which the game's `Log.error` calls),
`SCRIPT ERROR:` (a GDScript fault at run time), and `WARNING:` (the engine's, and `push_warning`
through `Log.warn`). Each is followed by an `at:` line and, for script-side ones, a GDScript
backtrace. This reads a log, groups the reports by kind, message (numbers and ids folded) and
the first frame of game code they came from, and prints the counts.

    tools/debug/error_census.py run.log                 # totals and the distinct reports
    tools/debug/error_census.py run.log --json out.json
    tools/debug/error_census.py run.log --max-errors 0  # exit 1 when there are errors (a gate)

Lines the engine prints once at start-up on a machine with no GPU or no audio device (the
V-Sync note under xvfb, a dummy audio driver) are counted apart as `environment` and do not
fail the gate: they describe the machine, not the game.
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys

KINDS = (("SCRIPT ERROR:", "script_error"), ("USER SCRIPT ERROR:", "script_error"),
         ("USER ERROR:", "error"), ("ERROR:", "error"), ("USER WARNING:", "warning"), ("WARNING:", "warning"))
# the machine running the test, not the game (xvfb has no V-Sync control, Dummy audio, llvmpipe)
ENVIRONMENT = (
    re.compile(r"Could not set V-Sync mode"),
    re.compile(r"resources still in use at exit"),
    re.compile(r"RID allocations of type .* were leaked at exit"),
    re.compile(r"ObjectDB instances leaked at exit"),
)
FRAME = re.compile(r"^\s*(?:at:|\[\d+\])\s*(.*)$")
# 4.5 and later print the script's stack under this line after the engine's `at:`
BACKTRACE_HEAD = re.compile(r"^\s*GDScript backtrace")
GAME_FRAME = re.compile(r"(res://[^\s:)]+|\b(?:actors|core|systems|ui|world|tools_gd|tests)/[^\s:)]+\.gd):?(\d+)?")
FOLD = re.compile(r"(?<![A-Za-z_])-?\d+(?:\.\d+)?(?![A-Za-z_])")


def _fold(msg: str) -> str:
    msg = re.sub(r"#\d+|<[A-Za-z0-9_]+#-?\d+>|0x[0-9a-f]+", "#", msg)
    return FOLD.sub("N", msg).strip()


def census(lines: list[str]) -> dict:
    reports = collections.OrderedDict()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        kind = None
        for prefix, k in KINDS:
            if line.startswith(prefix):
                kind, msg = k, line[len(prefix):].strip()
                break
        if kind is None:
            i += 1
            continue
        frames = []
        j = i + 1
        while j < len(lines) and len(frames) < 12:
            if BACKTRACE_HEAD.match(lines[j]):
                j += 1
                continue
            m = FRAME.match(lines[j])
            if not m:
                break
            frames.append(m.group(1).strip())
            j += 1
        source = ""
        for f in frames:
            m = GAME_FRAME.search(f)
            if m and "core/log.gd" not in f:
                source = "%s:%s" % (m.group(1).replace("res://", ""), m.group(2) or "?")
                break
        if not source and frames:
            source = frames[0]
        if any(p.search(msg) for p in ENVIRONMENT):
            kind = "environment"
        key = (kind, _fold(msg), source)
        entry = reports.setdefault(key, {"kind": kind, "message": msg, "source": source, "count": 0})
        entry["count"] += 1
        i = j
    totals = collections.Counter()
    for r in reports.values():
        totals[r["kind"]] += r["count"]
    return {"totals": dict(totals), "distinct": {k: sum(1 for r in reports.values() if r["kind"] == k) for k in totals},
            "reports": sorted(reports.values(), key=lambda r: (r["kind"], -r["count"]))}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--json", default="")
    ap.add_argument("--max-errors", type=int, default=-1, help="fail when errors + script errors exceed this")
    ap.add_argument("--max-warnings", type=int, default=-1, help="fail when warnings exceed this")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)
    lines = []
    for path in args.logs:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines.extend(f.readlines())
    c = census(lines)
    t = c["totals"]
    errors = t.get("error", 0) + t.get("script_error", 0)
    print("CENSUS | errors %d (%d distinct) | script errors %d (%d distinct) | warnings %d (%d distinct) | environment %d" % (
        t.get("error", 0), c["distinct"].get("error", 0), t.get("script_error", 0), c["distinct"].get("script_error", 0),
        t.get("warning", 0), c["distinct"].get("warning", 0), t.get("environment", 0)))
    if not args.quiet:
        for r in c["reports"]:
            if r["kind"] != "environment":
                print("%-12s x%-4d %s  <- %s" % (r["kind"], r["count"], r["message"][:150], r["source"][:90]))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(c, f, indent=1)
    failed = False
    if args.max_errors >= 0 and errors > args.max_errors:
        print("CENSUS | FAIL: %d errors, allowed %d" % (errors, args.max_errors))
        failed = True
    if args.max_warnings >= 0 and t.get("warning", 0) > args.max_warnings:
        print("CENSUS | FAIL: %d warnings, allowed %d" % (t.get("warning", 0), args.max_warnings))
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
