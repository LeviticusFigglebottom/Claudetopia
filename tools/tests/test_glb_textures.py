#!/usr/bin/env python3
"""Every model the game ships keeps its textures as files beside it (CONTRACTS §4).

    python3 tools/tests/test_glb_textures.py     # or: python3 -m unittest discover tools/tests

The forge's own output check (`tools/forge/tests/test_output.py`) only ever looked at the five
categories the prop forge writes, so the character forge exported all 54 of its GLBs with
their maps embedded and nothing said so. Godot then extracted a second, uncompressed copy of
every map beside each part, and the forge's PNGs -- the ones with import settings stamped on
them -- were loaded by nothing. This walks every GLB under game/assets instead, whoever made it.

It also holds the other thing that was invisible from the file layout: five character parts
(three beards, the pauldrons and the ragged cloak) were a skeleton with no mesh in it, because
the glTF exporter drops a mesh it judges invalid without failing, and their meta files recorded
the triangles of a mesh that never reached the file.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "forge"))

from lib import glb  # noqa: E402

ASSETS = ROOT / "game" / "assets"
CHARACTERS = ASSETS / "models" / "characters"
REPAIR = "python3 tools/forge/externalise_textures.py"


def shipped_glbs() -> list[Path]:
    return sorted(ASSETS.rglob("*.glb")) if ASSETS.is_dir() else []


def character_glbs() -> list[Path]:
    return sorted(CHARACTERS.rglob("*.glb")) if CHARACTERS.is_dir() else []


@unittest.skipUnless(shipped_glbs(), "no models under game/assets yet")
class TestTexturesAreFiles(unittest.TestCase):
    def test_no_shipped_glb_embeds_an_image(self):
        bad = []
        for p in shipped_glbs():
            inside = glb.embedded_images(p)
            if inside:
                bad.append("%s embeds %s" % (p.relative_to(ROOT), ", ".join(inside)))
        self.assertEqual(bad, [], "GLBs carrying their textures inside (CONTRACTS §4 wants files "
                                  "beside them; `%s` moves them out losslessly):\n  %s"
                         % (REPAIR, "\n  ".join(bad)))

    def test_every_referenced_texture_is_there_and_written(self):
        bad = []
        for p in shipped_glbs():
            for uri in glb.summary(p)["images"]:
                if uri == "<embedded>":
                    continue
                f = p.parent / uri
                if not f.exists():
                    bad.append("%s -> missing %s" % (p.relative_to(ROOT), uri))
                elif f.stat().st_size == 0:
                    bad.append("%s -> %s is empty" % (p.relative_to(ROOT), uri))
        self.assertEqual(bad, [], "GLB texture references that lead nowhere:\n  " + "\n  ".join(bad))


@unittest.skipUnless(character_glbs(), "the character forge has not been run")
class TestCharacterParts(unittest.TestCase):
    def test_every_character_glb_holds_a_mesh(self):
        """A part is built to be seen. A GLB with a skeleton and no triangles is a failed build
        that the exporter did not report, and a chooser offering it shows nothing at all."""
        empty = [str(p.relative_to(CHARACTERS)) for p in character_glbs() if glb.mesh_triangles(p) == 0]
        self.assertEqual(empty, [], "character GLBs with no mesh in them:\n  " + "\n  ".join(empty))

    def test_the_meta_counts_the_triangles_the_file_holds(self):
        """The meta beside an empty body variant once said 7 798 triangles, because it was
        counted off the live Blender object after the export had dropped it."""
        wrong = []
        for p in character_glbs():
            meta = p.with_suffix(".meta.json")
            if not meta.exists():
                continue
            # a list per level of detail, or (the characters' rebuild) one count
            m = json.loads(meta.read_text(encoding="utf-8"))
            tris = m["tris"]
            said = int(tris[0] if isinstance(tris, list) else tris)
            # a hair's or a beard's cards are a mesh of their own in the same file, counted apart
            said += int(m.get("card_tris", 0))
            held = glb.mesh_triangles(p)
            if said != held:
                wrong.append("%s: meta says %d, file holds %d" % (p.relative_to(CHARACTERS), said, held))
        self.assertEqual(wrong, [], "meta triangle counts that are not the file's:\n  " + "\n  ".join(wrong))

    def test_no_texture_in_a_character_folder_is_referenced_by_nothing(self):
        """Godot's extracted copies (`<glb>_<image>.png`) and textures orphaned by a rebuild
        both look like assets and are neither: a folder holds the maps its GLBs name."""
        folders: dict[Path, set[str]] = {}
        for p in character_glbs():
            used = folders.setdefault(p.parent, set())
            used.update(glb.summary(p)["images"])
            # The face marks no GLB names (age, ruddiness, freckles, weathering; they replaced the
            # age maps): game/actors/shared/humanoid_model.gd loads them by path (`_face_marks`),
            # a head part's as `<part>.glb` -> `<part>_marks.png` and the rig's default head as
            # `humanoid_rig_head_marks.png`. Used, so not strays.
            used.add(p.stem + "_marks.png")
            # and beside them the zones (`_marks.png` -> `_zones.png`), and a hair's or a beard's
            # flow map beside its normal map (`_normal.png` -> `_flow.png`), loaded the same way
            used.add(p.stem + "_zones.png")
            for img in list(used):
                if img.endswith("_normal.png"):
                    used.add(img[: -len("_normal.png")] + "_flow.png")
            if p.stem == "humanoid_rig":
                used.add("humanoid_rig_head_marks.png")
                used.add("humanoid_rig_head_zones.png")
        strays = []
        for folder, used in sorted(folders.items()):
            for png in sorted(folder.glob("*.png")):
                if png.name not in used:
                    strays.append(str(png.relative_to(CHARACTERS)))
        self.assertEqual(strays, [], "character textures nothing references (`%s` removes extracted "
                                     "copies):\n  %s" % (REPAIR, "\n  ".join(strays)))


if __name__ == "__main__":
    unittest.main()
