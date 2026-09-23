#!/usr/bin/env python3
"""Check an atlas against its schema and the content packs.

    python3 tools/world/atlas/check_atlas.py                 # tools/world/atlas/atlas.json
    python3 tools/world/atlas/check_atlas.py my_atlas.json   # any other
    python3 tools/world/atlas/check_atlas.py my_atlas.json --pack other/game/content/packs/core

Prints every error and warning and exits 1 when there is an error. An error is something the
world builder cannot make a world from, or would make a world the game's own tests refuse; a
warning is something that is probably not meant. SCHEMA.md beside this file says what each field
means.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from worldgen import atlas as ATLAS  # noqa: E402

PACK = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "game", "content", "packs", "core")


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    pack = PACK
    if "--pack" in argv:
        k = argv.index("--pack")
        pack = argv[k + 1]
        del argv[k:k + 2]
    path = argv[0] if argv else ATLAS.ATLAS_PATH
    try:
        doc = ATLAS.load(path)
    except (OSError, ValueError) as e:
        print("cannot read %s: %s" % (path, e))
        return 1
    errors, warnings = ATLAS.check(doc, pack)
    for w in warnings:
        print("warning: " + w)
    for e in errors:
        print("ERROR: " + e)
    n = {k: len(doc.get(k, [])) for k in ("provinces", "ranges", "peaks", "valleys", "rivers", "lakes",
                                         "forests", "roads")}
    print("%s: %s; %d error(s), %d warning(s)" % (
        os.path.relpath(path), ", ".join("%d %s" % (v, k) for k, v in n.items()), len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
