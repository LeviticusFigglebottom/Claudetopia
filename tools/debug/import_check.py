#!/usr/bin/env python3
"""What every checkout's Godot import would otherwise make anew or rewrite, caught before commit.

    python3 tools/debug/import_check.py          # report; exits 1 when anything is wrong
    python3 tools/debug/import_check.py --fix    # complete the .import sidecars that lack lines

Two kinds of file are made by Godot's import when they are not there, and each one made that
way is a change in every checkout that imports, untracked or rewritten, with an identity of its
own:

* A script, shader or GDExtension under game/ has a `<file>.uid` beside it (Godot 4.4 on), and
  the repository tracks them. A tracked script without a tracked .uid gets one made by each
  checkout's import, each with a different random uid: three ErrorLog scripts went out that way.
  This names them. The .uid is made by opening the project or `./run.sh import`, then `git add`.

* An `.import` sidecar without its `path` and `dest_files` lines (or its uid) imports as it
  should, but Godot writes the lines in on the first import, so every checkout finds the sidecar
  changed. The forge wrote new assets' sidecars that way until it wrote the complete form
  (tools/forge/lib/godot_import.py); `--fix` completes such sidecars in place, byte for byte as
  Godot would, and leaves complete ones alone.

And one kind of staleness that is this checkout's own, not the repository's:

* An import in game/.godot/imported made from other bytes than its source now holds (the .md5
  Godot keeps beside each import records the source's md5). Godot redoes an import only when
  the source's modified time changes, so an import cache linked in from another checkout
  (`./run.sh seed-import`) keeps the other checkout's import of every asset that differs here,
  and a run then tests old assets. `--touch-stale` touches those sources, and `./run.sh import`
  does that before it imports.

Runs in `./run.sh test` and before `./run.sh flow`. Reads the file list from git: tracked files,
and for sidecars also new ones not yet added, so a new asset is caught before its commit.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "forge"))

from lib import godot_import as GI  # noqa: E402

GAME = "game/"
# what Godot 4.4 and later give a .uid file of its own: the text resources with no header to
# keep a uid in
UID_EXTENSIONS = (".gd", ".gdshader", ".gdshaderinc", ".gdextension")


def _git(*args: str) -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=True).stdout
    return [line for line in out.split("\n") if line]


def missing_uids(tracked: list[str]) -> list[tuple[str, str]]:
    """[(file, why)] for each tracked game/ script, shader or extension without a tracked .uid."""
    have = set(tracked)
    out = []
    for f in tracked:
        if not f.startswith(GAME) or not f.endswith(UID_EXTENSIONS) or "/.godot/" in f:
            continue
        if f + ".uid" in have:
            continue
        on_disk = (ROOT / (f + ".uid")).exists()
        out.append((f, "its .uid is on disk but not tracked: git add %s.uid" % f if on_disk
                    else "no .uid: open the project or ./run.sh import to make it, then git add %s.uid" % f))
    return out


def sidecar_problems(files: list[str], fix: bool) -> tuple[list[tuple[str, list[str]]], int]:
    """([(sidecar, problems)] left, how many --fix completed)."""
    formats = GI.vram_formats(ROOT / "game" / "project.godot")
    left, fixed = [], 0
    for f in files:
        if not f.startswith(GAME) or not f.endswith(".import") or "/.godot/" in f:
            continue
        p = ROOT / f
        if not p.exists():
            continue
        text = p.read_text(encoding="utf-8")
        probs = GI.problems(text, formats)
        if probs and fix:
            done = GI.complete(text, formats)
            if done != text and not GI.problems(done, formats):
                p.write_text(done, encoding="utf-8", newline="\n")
                fixed += 1
                continue
        if probs:
            left.append((f, probs))
    return left, fixed


def stale_imports(files: list[str]) -> list[str]:
    """The sources whose import in this checkout's game/.godot/imported was made from other bytes
    than they now hold: the .md5 Godot keeps beside each import names the source's md5, and it no
    longer matches. Godot rechecks a source only when its modified time changes, so an import cache
    copied or linked from another checkout, or a checkout that kept a file's time, stays stale
    until the source is touched. Sources never imported here are not stale, only new."""
    out = []
    for f in files:
        if not f.startswith(GAME) or not f.endswith(".import") or "/.godot/" in f:
            continue
        side = ROOT / f
        src = ROOT / f[: -len(".import")]
        if not side.exists() or not src.exists():
            continue
        text = side.read_text(encoding="utf-8")
        source = re.search(r'^source_file="([^"]+)"', text, re.M)
        if source is None:
            continue
        record = ROOT / "game" / (GI.import_base(source.group(1))[len("res://"):] + ".md5")
        if not record.exists():
            continue
        m = re.search(r'^source_md5="([0-9a-f]+)"', record.read_text(encoding="utf-8", errors="replace"), re.M)
        if m and m.group(1) != hashlib.md5(src.read_bytes()).hexdigest():
            out.append(str(src.relative_to(ROOT)))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fix", action="store_true", help="complete the sidecars that lack lines")
    ap.add_argument("--touch-stale", action="store_true",
                    help="touch each source whose import here is stale, so the next import redoes it")
    ap.add_argument("--quiet", action="store_true", help="only the verdict and what is wrong")
    args = ap.parse_args(argv)
    tracked = _git("ls-files", "--", "game")
    new = _git("ls-files", "--others", "--exclude-standard", "--", "game")
    stale = stale_imports(tracked + new)
    if args.touch_stale:
        now = time.time()
        for f in stale:
            os.utime(ROOT / f, (now, now))
        print("IMPORT CHECK | touched %d source(s) whose import here was stale, for the import to redo" % len(stale))
        return 0
    uids = missing_uids(tracked)
    sidecars, fixed = sidecar_problems(tracked + new, args.fix)
    for f, why in uids:
        print("UID      %s: %s" % (f, why))
    for f, probs in sidecars:
        print("IMPORT   %s: %s" % (f, "; ".join(probs)))
    for f in stale:
        print("STALE    %s: imported here from other bytes than it holds (./run.sh import redoes it)" % f)
    if fixed:
        print("completed %d sidecar(s); commit them" % fixed)
    n = len(uids) + len(sidecars) + len(stale)
    print("IMPORT CHECK | %s | %d script(s) without a tracked .uid, %d incomplete sidecar(s), %d stale import(s)%s" % (
        "PASS" if n == 0 else "FAIL", len(uids), len(sidecars), len(stale),
        "" if not sidecars or args.fix else " (--fix completes them)"))
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
