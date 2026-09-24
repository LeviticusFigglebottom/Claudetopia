#!/usr/bin/env python3
"""Counts the GDScript warnings in the project, and holds the count in the game's scripts down.

    python3 tools/debug/warning_census.py            # counts by kind and by file
    python3 tools/debug/warning_census.py --check    # fails if the game's count is over the baseline
    python3 tools/debug/warning_census.py --update   # writes the counts as the new baseline
    python3 tools/debug/warning_census.py --list     # and every warning, file:line and message

Godot shows a warning in the editor's debugger for every one the analyzer finds in a script the
running game loads, and prints none of them to a terminal. A user who opened the debugger found
239 there: seventy were the event bus's signals, which only other scripts use, and the rest were
real (a parameter named like a property it hides, an integer division, a static function called
through an instance, an unused local).

A census cannot be taken from inside a running game, because the analyzer reads each warning's
level once, at startup. So this asks Godot which warnings the project leaves at "warn", writes a
`game/override.cfg` that makes each of them an error, has Godot compile every script afresh under
a stand-in path (tools/debug/warning_census.gd), reads the errors that name a warning out of the
log, and removes the override whatever happens. The override is marked, and `run.sh` removes one
it finds left behind by a census that was killed.

The baseline (`tools/debug/warning_baseline.json`) is the count in the game's own scripts: not
its tests and not tools_gd, which the game never loads. `--check` fails when that count is over
the baseline and says which files grew. Clearing warnings brings the count down; `--update` then
brings the baseline down with it, so it cannot creep back up.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
OVERRIDE = GAME / "override.cfg"
MARK = "; written by tools/debug/warning_census.py for one census; delete it if you find it"
# run.sh's headless import writes one too (single-threaded import, run.sh import_project); one left
# by an import that was killed only slows the next import, and is the census's to remove
IMPORT_MARK = "; written by run.sh for one headless import"
# the census could not be taken (no Godot, the override is somebody's own, Godot did not finish):
# not a verdict on the warnings, and said apart from one (run.sh test reports it as such)
CANNOT_RUN = 2
CENSUS_GD = ROOT / "tools" / "debug" / "warning_census.gd"
BASELINE = ROOT / "tools" / "debug" / "warning_baseline.json"
STAND_IN = "res://__census__/"


def cannot_run(why: str) -> None:
    print("warning_census: %s" % why, file=sys.stderr)
    sys.exit(CANNOT_RUN)


def godot() -> str:
    found = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if not found:
        cannot_run("no Godot (set GODOT to name it)")
    return found


def run_godot(args: list[str], log: Path) -> int:
    cmd = [godot(), "--headless", "--path", str(GAME), "--audio-driver", "Dummy", "--script", str(CENSUS_GD)] + args
    with open(log, "w", encoding="utf-8") as out:
        return subprocess.call(cmd, stdout=out, stderr=subprocess.STDOUT, timeout=1200)


def warn_levels(work: Path) -> list[str]:
    """The warning settings the project leaves at 1 (warn)."""
    log = work / "levels.log"
    run_godot(["--", "--levels"], log)
    names = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"LEVEL (debug/gdscript/warnings/\S+) (\d+)$", line.strip())
        if m and m.group(2) == "1":
            names.append(m.group(1))
    if not names:
        cannot_run("Godot named no warning settings (see %s)" % log)
    return names


def remove_override() -> None:
    try:
        if OVERRIDE.exists() and OVERRIDE.read_text(encoding="utf-8").startswith(MARK):
            OVERRIDE.unlink()
    except OSError:
        pass


def census_log(work: Path) -> Path:
    """Runs the census with the override in place, and removes it after."""
    if OVERRIDE.exists():
        head = OVERRIDE.read_text(encoding="utf-8")
        if head.startswith(IMPORT_MARK):
            OVERRIDE.unlink()               # a killed import's; nothing else reads it
        elif not head.startswith(MARK):
            cannot_run("game/override.cfg exists and is neither the census's nor run.sh's import's; "
                       "it is somebody's own, so the census does not touch it: move it aside and run again")
    names = warn_levels(work)
    log = work / "census.log"
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: (remove_override(), sys.exit(130)))
    try:
        OVERRIDE.write_text(MARK + "\n[debug]\n\n" + "".join("%s=2\n" % n[len("debug/"):] for n in names),
                            encoding="utf-8")
        run_godot([], log)
    finally:
        remove_override()
    if "CENSUS done" not in log.read_text(encoding="utf-8", errors="replace"):
        cannot_run("the census did not finish (see %s)" % log)
    return log


def parse(text: str) -> list[tuple[str, int, str]]:
    """(path, line, message) for every warning a census log names, each once."""
    lines = text.splitlines()
    seen = set()
    out = []
    for i, line in enumerate(lines):
        if "(Warning treated as error.)" not in line:
            continue
        msg = re.sub(r"^.*?Parse Error: ", "", line.strip()).replace(" (Warning treated as error.)", "")
        for follow in lines[i + 1:i + 3]:
            m = re.search(r"at: GDScript::reload \((res://[^:]+):(\d+)\)", follow)
            if m:
                path = m.group(1).replace(STAND_IN, "res://")
                key = (path, int(m.group(2)), msg)
                if key not in seen:
                    seen.add(key)
                    out.append(key)
                break
    return sorted(out)


def area(path: str) -> str:
    if path.startswith("res://tests/"):
        return "tests"
    if path.startswith("res://tools_gd/"):
        return "tools_gd"
    return "game"


def kind_of(msg: str) -> str:
    return re.sub(r"\d+", "N", re.sub(r'"[^"]*"', '"X"', msg))


def counts(found: list[tuple[str, int, str]]) -> dict:
    by_area = collections.Counter(area(p) for p, _, _ in found)
    game_files = collections.Counter(p for p, _, _ in found if area(p) == "game")
    return {"game": by_area["game"], "tests": by_area["tests"], "tools_gd": by_area["tools_gd"],
            "game_by_file": dict(sorted(game_files.items()))}


def verdict(now: dict, base: dict) -> tuple[bool, list[tuple[str, int, int]]]:
    """Whether the game's count is within the baseline, and the files whose count grew."""
    grew = [(p, n, int(base.get("game_by_file", {}).get(p, 0))) for p, n in now["game_by_file"].items()
            if n > int(base.get("game_by_file", {}).get(p, 0))]
    return now["game"] <= int(base["game"]), grew


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="fail if the game's count is over the baseline")
    ap.add_argument("--update", action="store_true", help="write the counts as the new baseline")
    ap.add_argument("--list", action="store_true", help="print every warning")
    ap.add_argument("--log", type=Path, help="read this census log instead of running one")
    a = ap.parse_args()
    if a.log:
        text = a.log.read_text(encoding="utf-8", errors="replace")
    else:
        with tempfile.TemporaryDirectory(prefix="warning_census_") as work:
            text = census_log(Path(work)).read_text(encoding="utf-8", errors="replace")
    found = parse(text)
    now = counts(found)
    print("GDScript warnings: %d in the game's scripts, %d in its tests, %d in tools_gd"
          % (now["game"], now["tests"], now["tools_gd"]))
    for k, n in collections.Counter(kind_of(m) for p, _, m in found if area(p) == "game").most_common():
        print("  %4d  %s" % (n, k))
    print("by file (the game's scripts):")
    for path, n in sorted(now["game_by_file"].items(), key=lambda kv: (-kv[1], kv[0])):
        print("  %4d  %s" % (n, path))
    if a.list:
        for p, line, msg in found:
            print("%s:%d  %s" % (p, line, msg))
    if a.update:
        BASELINE.write_text(json.dumps(now, indent=1) + "\n", encoding="utf-8")
        print("baseline written: %d in the game's scripts" % now["game"])
    if a.check:
        base = json.loads(BASELINE.read_text(encoding="utf-8"))
        ok, grew = verdict(now, base)
        if not ok:
            print("FAIL: %d GDScript warnings in the game's scripts, the baseline is %d. Grown:" % (now["game"], base["game"]))
            for p, n, was in grew:
                print("  %s: %d (was %d)" % (p, n, was))
            return 1
        if now["game"] < int(base["game"]):
            print("PASS: %d, under the baseline of %d; bring it down with --update" % (now["game"], base["game"]))
        else:
            print("PASS: %d, at the baseline" % now["game"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
