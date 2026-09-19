#!/usr/bin/env python3
"""Finds content keys no code reads.

A field in a JSON pack that nothing in game/ ever looks up is a promise the game does not
keep: the writing says a book teaches Binding, or a boss summons its dead, and the player
never sees it. This walks every definition in every pack, collects the keys, and reports the
ones that appear in no .gd source.

Keys are matched loosely on purpose: a read can be `def["x"]`, `get("x", ...)`, `has("x")`,
`.x`, or the key held in a constant, so this errs towards saying a key IS read. What it
reports is therefore a short list worth looking at by hand, not a verdict.

Usage: python3 tools/dead_data.py [--all] [--type TYPE]
"""
import json
import pathlib
import re
import sys
import collections

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = ROOT / "game" / "content" / "packs"
CODE_DIRS = [ROOT / "game", ROOT / "tools"]
CODE_SUFFIXES = {".gd", ".py", ".gdshader"}

# Keys every definition carries, or that are documentation for the reader rather than data.
STRUCTURAL = {"id", "name", "description", "notes", "_doc", "entries", "extends", "title"}
# Dictionaries whose keys are content the author chose (dialogue node ids, table row names),
# not field names the code looks up. Their children's names are skipped; their grandchildren
# are still fields and are still checked.
MAP_VALUED = {"nodes", "rows", "greetings", "lines", "pools", "by_region", "by_culture"}


def defs():
	for path in sorted(PACKS.rglob("*.json")):
		if path.name in ("pack.json", "names_index.json"):
			continue
		try:
			data = json.loads(path.read_text(encoding="utf-8"))
		except json.JSONDecodeError as exc:
			print(f"  ! {path.relative_to(ROOT)}: {exc}")
			continue
		items = data if isinstance(data, list) else data.get("entries", [data])
		for item in items:
			if isinstance(item, dict) and "id" in item:
				yield path, item


def keys_of(value, prefix="", named_map=False):
	"""Every field name in a definition, including nested ones, as (key, path) pairs."""
	if isinstance(value, dict):
		for k, v in value.items():
			if not named_map:
				yield k, (prefix + "." + k if prefix else k)
			yield from keys_of(v, prefix + "." + k if prefix else k, named_map=k in MAP_VALUED)
	elif isinstance(value, list):
		for v in value:
			yield from keys_of(v, prefix)


def source_text():
	out = []
	for base in CODE_DIRS:
		for path in base.rglob("*"):
			if path.suffix in CODE_SUFFIXES and ".godot" not in path.parts:
				out.append(path.read_text(encoding="utf-8", errors="replace"))
	return "\n".join(out)


def main() -> int:
	want_all = "--all" in sys.argv
	only = None
	if "--type" in sys.argv:
		only = sys.argv[sys.argv.index("--type") + 1]
	code = source_text()
	read = set(re.findall(r'"([a-z_][a-z0-9_]*)"', code))
	read |= set(re.findall(r'&"([a-z_][a-z0-9_]*)"', code))
	read |= set(re.findall(r"\.([a-z_][a-z0-9_]*)\b", code))

	where = collections.defaultdict(set)   # key -> {type}
	count = collections.Counter()
	for path, item in defs():
		kind = item["id"].split(":")[-1].split("/")[0]
		if only and kind != only:
			continue
		for key, _full in keys_of(item):
			if key in STRUCTURAL:
				continue
			where[key].add(kind)
			count[key] += 1

	dead = sorted(k for k in where if k not in read)
	print(f"{len(where)} distinct content keys; {len(dead)} that no source file mentions\n")
	for key in dead:
		print(f"  {key:28} {count[key]:5} uses   in: {', '.join(sorted(where[key]))}")
	if want_all:
		print("\nall keys:")
		for key in sorted(where):
			mark = " " if key in read else "!"
			print(f" {mark} {key:28} {count[key]:5}   {', '.join(sorted(where[key]))}")
	return 1 if dead else 0


if __name__ == "__main__":
	raise SystemExit(main())
