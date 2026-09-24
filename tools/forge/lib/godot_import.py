"""Godot .import sidecars in the complete form Godot itself writes. Pure Python, no Blender.

A sidecar written without its `path` and `dest_files` lines imports correctly, but Godot writes
them in on its first import, so every checkout that imports a new asset finds its sidecars
changed: basalt columns, driftwood and a wrack in batch 3, and every new asset before them.
Both lines are fixed by the source path alone, so the forge can write them itself:

    [remap]
    importer="texture"
    type="CompressedTexture2D"
    uid="uid://..."
    path.s3tc="res://.godot/imported/<file>-<md5 of its res:// path>.s3tc.ctex"
    metadata={
    "imported_formats": ["s3tc_bptc"],
    "vram_texture": true
    }

    [deps]

    source_file="res://.../<file>"
    dest_files=["res://.godot/imported/<file>-<md5>.s3tc.ctex"]

    [params]
    ...

(with a blank line after each section header, as Godot writes it). A VRAM-compressed texture
(`compress/mode=2`) is stored once per compressed format the project imports (the
`rendering/textures/vram_compression/import_*` settings), under `path.<format>`; every other
texture under a plain `path`, with `"vram_texture": false`. A scene is `.scn`, an Ogg stream
`.oggvorbisstr`, a font `.fontdata`.

`complete()` fills in what a sidecar lacks and leaves one that has it alone; `problems()` says
what one lacks. tools/debug/import_check.py runs both over the repository.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

IMPORTED = "res://.godot/imported/"
# the importer's save extension, as Godot names the imported file
SAVE_EXTENSION = {
    "scene": "scn",
    "texture": "ctex",
    "oggvorbisstr": "oggvorbisstr",
    "mp3": "mp3str",
    "wav": "sample",
    "font_data_dynamic": "fontdata",
}
# importers that write no imported file of their own
NO_OUTPUT = ("keep", "skip")
# the project settings that choose a VRAM texture's formats, and the variant each one writes
VRAM_FORMATS = (
    ("rendering/textures/vram_compression/import_s3tc_bptc", "s3tc_bptc", "s3tc", True),
    ("rendering/textures/vram_compression/import_etc2_astc", "etc2_astc", "etc2", False),
)
_UID_CHARS = 34


def godot_uid(res_path: str) -> str:
    """Stable ResourceUID text from the res:// path (Godot's base-34 a..y/0..8 encoding)."""
    n = int(hashlib.sha1(res_path.encode("utf-8")).hexdigest()[:16], 16) & 0x7FFFFFFFFFFFFFFF
    s = ""
    while n:
        c = n % _UID_CHARS
        s = (chr(ord("a") + c) if c < 25 else chr(ord("0") + c - 25)) + s
        n //= _UID_CHARS
    return "uid://" + s


def import_base(res_path: str) -> str:
    """Where Godot keeps a source file's import: the file's name and the md5 of its res:// path."""
    return "%s%s-%s" % (IMPORTED, res_path.rsplit("/", 1)[-1], hashlib.md5(res_path.encode("utf-8")).hexdigest())


def vram_formats(project_godot: Path | str | None = None) -> list[tuple[str, str]]:
    """[(imported format, path variant)] a VRAM-compressed texture is stored in, from the
    project's settings; the engine's defaults when there is no project file to read."""
    text = ""
    if project_godot is not None and Path(project_godot).exists():
        text = Path(project_godot).read_text(encoding="utf-8")
    out = []
    for setting, fmt, variant, default in VRAM_FORMATS:
        key = setting.split("/", 1)[1]           # project.godot keeps it under [rendering]
        m = re.search(r"^%s=(\w+)" % re.escape(key), text, re.M)
        on = default if m is None else m.group(1) == "true"
        if on:
            out.append((fmt, variant))
    # with neither asked for, the importer falls back to the desktop's formats
    return out or [("s3tc_bptc", "s3tc")]


def _field(text: str, key: str) -> str | None:
    m = re.search(r'^%s="([^"]*)"' % re.escape(key), text, re.M)
    return m.group(1) if m else None


def _compress_mode(text: str) -> int:
    m = re.search(r"^compress/mode=(\d+)", text, re.M)
    return int(m.group(1)) if m else 0


def outputs(text: str, formats: list[tuple[str, str]]) -> tuple[list[str], list[str], str] | None:
    """(the [remap] path lines, the dest files, the metadata block or "") Godot writes for this
    sidecar, or None for an importer this does not know."""
    importer = _field(text, "importer")
    source = _field(text, "source_file")
    if importer is None or source is None or importer not in SAVE_EXTENSION:
        return None
    base = import_base(source)
    ext = SAVE_EXTENSION[importer]
    if importer == "texture" and _compress_mode(text) == 2:
        lines, dest = [], []
        for _fmt, variant in formats:
            p = "%s.%s.%s" % (base, variant, ext)
            lines.append('path.%s="%s"' % (variant, p))
            dest.append(p)
        meta = 'metadata={\n"imported_formats": [%s],\n"vram_texture": true\n}' % ", ".join(
            '"%s"' % f for f, _v in formats)
        return lines, dest, meta
    p = "%s.%s" % (base, ext)
    meta = ""
    if importer == "texture":
        # an editor icon that follows the editor's scale or theme is imported a second time for it
        editor_variant = re.search(r"^editor/(scale_with_editor_scale|convert_colors_with_editor_theme)=true",
                                   text, re.M) is not None
        meta = 'metadata={\n%s"vram_texture": false\n}' % ('"has_editor_variant": true,\n' if editor_variant else "")
    return ['path="%s"' % p], [p], meta


def _has_path(text: str) -> bool:
    return re.search(r"^path(\.[a-z0-9_]+)?=", text, re.M) is not None


def _has_dest(text: str) -> bool:
    return re.search(r"^dest_files=", text, re.M) is not None


def problems(text: str, formats: list[tuple[str, str]] | None = None) -> list[str]:
    """What this sidecar lacks against the form Godot writes ([] when nothing)."""
    importer = _field(text, "importer")
    if importer in NO_OUTPUT:
        return []
    out = []
    if _field(text, "uid") is None:
        out.append("no uid (the import gives it a random one)")
    if not _has_path(text):
        out.append("no path")
    if not _has_dest(text):
        out.append("no dest_files")
    source = _field(text, "source_file")
    if source is None:
        out.append("no source_file")
    elif _has_dest(text):
        base = import_base(source)
        for p in re.findall(r'"(res://\.godot/imported/[^"]+)"', text):
            if not p.startswith(base + "."):
                out.append("%s is not where Godot imports %s" % (p, source))
                break
    if formats is not None and _has_path(text) and _has_dest(text) and source is not None:
        want = outputs(text, formats)
        if want is not None:
            have = sorted(re.findall(r"^(path(?:\.[a-z0-9_]+)?=.*)$", text, re.M))
            if have != sorted(want[0]):
                out.append("paths %s, where this project imports %s" % (have, sorted(want[0])))
    return out


def complete(text: str, formats: list[tuple[str, str]]) -> str:
    """The sidecar with what Godot would write in added: its uid (the forge's, from the path),
    its path lines and metadata, and dest_files. One already complete comes back unchanged, and
    one this cannot complete (an importer it does not know) comes back as it was."""
    if _field(text, "importer") in NO_OUTPUT or (_has_path(text) and _has_dest(text)
                                                  and _field(text, "uid") is not None):
        return text
    want = outputs(text, formats)
    if want is None:
        return text
    path_lines, dest, meta = want
    lines = text.split("\n")
    out: list[str] = []
    section = ""
    remap_done = False
    for i, line in enumerate(lines):
        if line.startswith("[") and line.rstrip().endswith("]"):
            section = line.strip()
        out.append(line)
        if section == "[remap]" and not remap_done:
            # the remap block ends at the blank line before [deps]
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if line.strip() and not line.startswith("[") and nxt.strip() == "":
                block = []
                if _field(text, "uid") is None:
                    block.append('uid="%s"' % godot_uid(_field(text, "source_file") or ""))
                if not _has_path(text):
                    block += path_lines
                    if meta and not re.search(r"^metadata=", text, re.M):
                        block.append(meta)
                out += block
                remap_done = True
        if section == "[deps]" and line.startswith("source_file=") and not _has_dest(text):
            out.append("dest_files=[%s]" % ", ".join('"%s"' % d for d in dest))
    return "\n".join(out)
