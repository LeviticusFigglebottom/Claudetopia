#!/usr/bin/env python3
"""Manifest-driven asset build. `./run.sh assets` calls this.

    tools/forge/build_assets.py [--only trees] [--jobs 2] [--force] [--quick] [--list]

Reads tools/forge/manifest.json: a list of entries
    {"generator": "gen_trees", "category": "trees", "kind": "oak", "name": "...",
     "palette": "hearthvale", "seed": 3, "variant": "a", "params": {...}}
and runs each through `blender -b --python tools/forge/<generator>.py -- ...`.

Incremental: an entry is skipped when its output meta.json records the same hash (the
generator name + version + params + seed + palette). Touching a generator does not
invalidate assets on its own; bump FORGE_VERSION in lib/cli.py (or pass --force) when
the geometry changes and everything should be rebuilt.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import cli  # noqa: E402  (pure Python: this script runs outside Blender)

FORGE_DIR = Path(__file__).resolve().parent
MANIFEST = FORGE_DIR / "manifest.json"
BLENDER = os.environ.get("BLENDER", "blender")


def load_manifest(path: Path = MANIFEST) -> list[dict]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data["assets"] if isinstance(data, dict) else data
    out = []
    for i, e in enumerate(entries):
        e = dict(e)
        e.setdefault("variant", "a")
        e.setdefault("seed", 1)
        e.setdefault("params", {})
        e.setdefault("palette", None)
        if "generator" not in e or "kind" not in e:
            raise ValueError("manifest entry %d needs generator and kind" % i)
        e.setdefault("category", default_category(e["generator"]))
        e.setdefault("name", cli.default_name(short_palette(e["palette"]), e["kind"], str(e["variant"])))
        out.append(e)
    return out


def default_category(generator: str) -> str:
    # gen_ground_kit's hedges, gate posts and milestones file under props deliberately: the
    # streamer reads the category to decide a scatter asset's view range and whether it casts
    # a shadow, and a hedgerow is line-work that has to read at two hundred metres, not a
    # herb that stops at a hundred and ten.
    return {"gen_trees": "trees", "gen_rocks": "rocks", "gen_flora": "flora",
            "gen_props": "props", "gen_landmarks": "landmarks",
            "gen_ground_kit": "props", "gen_weapons": "weapons"}.get(generator, "props")


def short_palette(palette) -> str:
    return (palette or "neutral").split("/")[-1].split(":")[-1]


def entry_hash(e: dict, version: int) -> str:
    return cli.asset_hash(e["generator"], version, e["name"], e["kind"], e["params"], int(e["seed"]),
                          e["palette"])


def _written(path: Path) -> bool:
    """A file that is there and has bytes in it.

    Existence alone is not enough. A build killed part-way through leaves the meta.json --
    which is what carries the hash -- already written and a texture truncated to nothing,
    and the truncated texture is the one file in the set whose emptiness takes a whole
    scene down: Godot will not load a .glb whose material points at a 0-byte PNG, and the
    interior that asked for the prop fails rather than falling back. Before this, a
    zero-length albedo read as "current" for ever, because nothing ever looked."""
    try:
        return path.stat().st_size > 0
    except OSError:
        return False


def is_current(e: dict, out_root: Path, version: int) -> bool:
    paths = cli.output_paths(out_root, e["category"], e["name"])
    if not _written(paths["meta"]) or not _written(paths["glb"]):
        return False
    try:
        meta = json.loads(paths["meta"].read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    if meta.get("hash") != entry_hash(e, version):
        return False
    for t in meta.get("textures", []):
        if not _written(paths["dir"] / t):
            return False
    return True


def build_command(e: dict, out_root: Path, quick: bool, res: int) -> list[str]:
    script = FORGE_DIR / ("%s.py" % e["generator"])
    if not script.exists():
        raise FileNotFoundError("no generator %s" % script)
    cmd = [BLENDER, "-b", "--python", str(script), "--",
           "--out", str(out_root), "--category", e["category"], "--name", e["name"],
           "--kind", e["kind"], "--seed", str(e["seed"]), "--variant", str(e["variant"]),
           "--params", json.dumps(e["params"])]
    if e.get("palette"):
        cmd += ["--palette", e["palette"]]
    if quick:
        cmd.append("--quick")
    if res:
        cmd += ["--res", str(res)]
    return cmd


def run_one(e: dict, out_root: Path, quick: bool, res: int, verbose: bool) -> dict:
    t0 = time.time()
    cmd = build_command(e, out_root, quick, res)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    ok = proc.returncode == 0 and "FORGE_OK" in proc.stdout
    tail = [ln for ln in proc.stdout.splitlines() if ln.startswith("FORGE_")]
    result = {"name": e["name"], "category": e["category"], "ok": ok, "seconds": time.time() - t0,
              "line": tail[-1] if tail else ""}
    if not ok or verbose:
        err = "\n".join(proc.stdout.splitlines()[-40:] + proc.stderr.splitlines()[-25:])
        result["log"] = err
    return result


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Build Wickmere's generated assets")
    ap.add_argument("--only", action="append", default=[],
                    help="limit to a category, generator, palette or name substring (repeatable)")
    ap.add_argument("--jobs", type=int, default=2, help="parallel Blender processes (default 2)")
    ap.add_argument("--out", default=str(cli.DEFAULT_OUT))
    ap.add_argument("--manifest", default=str(MANIFEST))
    ap.add_argument("--force", action="store_true", help="rebuild even when the hash matches")
    ap.add_argument("--quick", action="store_true", help="fast, low-quality pass (no AO, no LODs)")
    ap.add_argument("--res", type=int, default=0, help="force texture resolution")
    ap.add_argument("--list", action="store_true", help="list what would be built and exit")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)

    out_root = Path(args.out)
    version = cli.FORGE_VERSION
    entries = load_manifest(Path(args.manifest))
    if args.only:
        def matches(e):
            hay = " ".join([e["category"], e["generator"], e["name"], e["kind"], str(e["palette"])])
            return any(o in hay for o in args.only)
        entries = [e for e in entries if matches(e)]
    if not entries:
        print("[assets] nothing matches %s" % args.only)
        return 0

    todo = entries if args.force else [e for e in entries if not is_current(e, out_root, version)]
    skipped = len(entries) - len(todo)
    if args.list:
        for e in entries:
            state = "build" if e in todo else "ok   "
            print("%s %s/%s (%s seed=%s)" % (state, e["category"], e["name"], e["generator"], e["seed"]))
        print("%d entries, %d to build, %d current" % (len(entries), len(todo), skipped))
        return 0

    print("[assets] %d entries, %d up to date, building %d with %d job(s)"
          % (len(entries), skipped, len(todo), args.jobs))
    if not todo:
        return 0
    t0 = time.time()
    results = []
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        futures = {ex.submit(run_one, e, out_root, args.quick, args.res, args.verbose): e for e in todo}
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            done += 1
            mark = "ok " if r["ok"] else "FAIL"
            print("[%d/%d] %s %s/%s %.1fs" % (done, len(todo), mark, r["category"], r["name"], r["seconds"]))
            if not r["ok"]:
                print("       %s" % r.get("log", "").replace("\n", "\n       ")[-2500:])

    failed = [r for r in results if not r["ok"]]
    by_cat: dict[str, int] = {}
    for r in results:
        if r["ok"]:
            by_cat[r["category"]] = by_cat.get(r["category"], 0) + 1
    print("\n[assets] built %d in %.0fs (%s)%s"
          % (len(results) - len(failed), time.time() - t0,
             ", ".join("%s: %d" % kv for kv in sorted(by_cat.items())) or "-",
             ", %d FAILED" % len(failed) if failed else ""))
    for r in failed:
        print("  failed: %s/%s" % (r["category"], r["name"]))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
