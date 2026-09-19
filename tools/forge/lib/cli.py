"""Command line handling and output paths shared by every generator (pure Python).

Generators are run as:  blender -b --python tools/forge/gen_x.py -- [args]
Everything after the first "--" belongs to us. The same parser also works when a
generator module is imported by the tests (pass argv explicitly).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "models"
CATEGORIES = ("trees", "flora", "rocks", "props", "architecture", "dungeon", "landmarks",
              "characters", "creatures", "weapons", "armour", "vfx_meshes")

# Bump when generated geometry changes in a way that should rebuild every asset; it is
# part of each asset's hash, so build_assets sees the whole manifest as stale. It lives
# here rather than in export.py so the build orchestrator can read it without Blender.
FORGE_VERSION = 1
VARIANT_LETTERS = "abcdefghijklmnopqrstuvwxyz"


def forge_argv(argv: list[str] | None = None) -> list[str]:
    """The arguments meant for us: everything after '--' (Blender eats the rest)."""
    argv = list(sys.argv if argv is None else argv)
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    # Not launched through Blender's '--' convention (tests): drop the program name.
    return argv[1:] if argv and argv[0].endswith(".py") else argv


def build_parser(description: str) -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="forge", description=description)
    p.add_argument("--out", default=str(DEFAULT_OUT), help="output root (default game/assets/models)")
    p.add_argument("--category", default=None, help="output category folder; generators have a default")
    p.add_argument("--name", default=None, help="asset name (snake_case); default <palette>_<kind>_<variant>")
    p.add_argument("--kind", default=None, help="generator-specific asset kind (e.g. oak, barrel, boulder)")
    p.add_argument("--palette", default=None, help="region id or short name (hearthvale, core:region/hearthvale)")
    p.add_argument("--seed", type=int, default=1, help="stable seed")
    p.add_argument("--variant", default="a", help="variant letter or index; folded into the seed and name")
    p.add_argument("--params", default="{}", help="JSON object of generator parameters")
    p.add_argument("--res", type=int, default=0, help="force texture size (0 = choose by asset size)")
    p.add_argument("--quick", action="store_true", help="fast mode: no AO bake, half texture size, no LODs")
    p.add_argument("--list", action="store_true", help="list the kinds this generator knows and exit")
    p.add_argument("--no-import-files", action="store_true", help="do not write Godot .import sidecars")
    return p


def parse(description: str, argv: list[str] | None = None) -> argparse.Namespace:
    args = build_parser(description).parse_args(forge_argv(argv))
    try:
        args.params = json.loads(args.params) if isinstance(args.params, str) else dict(args.params)
    except json.JSONDecodeError as e:
        raise SystemExit("--params must be a JSON object: %s" % e)
    if not isinstance(args.params, dict):
        raise SystemExit("--params must be a JSON object")
    args.variant_index = variant_index(args.variant)
    args.variant = variant_letter(args.variant_index)
    args.palette_short = (args.palette or "neutral").split("/")[-1].split(":")[-1]
    return args


def variant_index(v) -> int:
    if isinstance(v, int):
        return max(0, v)
    v = str(v).strip().lower()
    if v.isdigit():
        return int(v)
    if len(v) == 1 and v in VARIANT_LETTERS:
        return VARIANT_LETTERS.index(v)
    raise SystemExit("bad --variant %r (letter a-z or index)" % v)


def variant_letter(i: int) -> str:
    return VARIANT_LETTERS[i % len(VARIANT_LETTERS)]


def derive_seed(seed: int, variant_idx: int, kind: str = "") -> int:
    """One stable seed per (seed, variant, kind) so variants differ but are reproducible."""
    h = hashlib.sha1(("%d|%d|%s" % (seed, variant_idx, kind)).encode("utf-8")).hexdigest()
    return int(h[:8], 16)


def default_name(palette_short: str, kind: str, variant: str) -> str:
    kind = kind.replace("-", "_")
    if palette_short in ("neutral", ""):
        return "%s_%s" % (kind, variant)
    return "%s_%s_%s" % (palette_short, kind, variant)


def asset_dir(out_root: str | Path, category: str, name: str, create: bool = True) -> Path:
    """game/assets/models/<category>/<name>/ (CONTRACTS.md §4). Category may contain one
    slash for architecture/<culture> and dungeon/<kit>."""
    validate_name(name)
    d = Path(out_root) / category / name
    if create:
        d.mkdir(parents=True, exist_ok=True)
    return d


def output_paths(out_root: str | Path, category: str, name: str) -> dict[str, Path]:
    d = asset_dir(out_root, category, name, create=False)
    return {
        "dir": d,
        "glb": d / ("%s.glb" % name),
        "meta": d / ("%s.meta.json" % name),
        "albedo": d / ("%s_albedo.png" % name),
        "normal": d / ("%s_normal.png" % name),
        "orm": d / ("%s_orm.png" % name),
        "col": d / ("%s_col.glb" % name),
    }


def validate_name(name: str) -> None:
    if not name or name != name.lower() or not all(c.isalnum() or c == "_" for c in name) or name[0].isdigit():
        raise ValueError("asset names are snake_case: %r" % name)


def asset_hash(generator: str, version: int, name: str, kind: str, params: dict, seed: int, palette: str | None) -> str:
    payload = json.dumps({"generator": generator, "version": version, "name": name, "kind": kind,
                          "params": params, "seed": seed, "palette": palette or "neutral"}, sort_keys=True)
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:16]


def res_path(out_root: str | Path, path: str | Path) -> str:
    """Absolute path under game/ -> res:// path."""
    p = Path(path).resolve()
    game = (REPO_ROOT / "game").resolve()
    try:
        return "res://" + p.relative_to(game).as_posix()
    except ValueError:
        return p.as_posix()
