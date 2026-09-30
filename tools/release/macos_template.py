#!/usr/bin/env python3
"""Let Godot export Wickmere's Mac build as one universal app without ETC2/ASTC textures.

Godot's macOS export refuses the "universal" and "arm64" architectures unless the project imports
ETC2/ASTC textures (rendering/textures/vram_compression/import_etc2_astc). Wickmere imports only
S3TC/BPTC: turning ETC2/ASTC on would re-import its ~1600 VRAM-compressed textures (rewriting every
.import file, and roughly an hour of ASTC encoding on a CI runner) to add a second copy that Macs do
not need. Every Apple Silicon Mac's GPU reads BC (S3TC/BPTC) textures: Godot's Metal driver asks
Metal (supportsBCTextureCompression) and uses them; Intel Macs and Rosetta use them through MoltenVK.

So the "macOS" preset asks for "x86_64", which only needs S3TC/BPTC, and this script adds
godot_macos_{release,debug}.x86_64 to the official macos.zip template as copies of its universal
(x86_64 + arm64) binaries. The export then writes, and signs ad hoc, a universal executable. The
Terrain3D framework is universal already. docs/MAC.md explains it.

    python3 tools/release/macos_template.py [path/to/macos.zip]

The default path is Godot's export template folder for the version in GODOT_VERSION (4.7.2).
Running it again changes nothing.
"""
import os
import shutil
import sys
import tempfile
import zipfile

VERSION = os.environ.get("GODOT_VERSION", "4.7.2")
DEFAULT = os.path.expanduser(f"~/.local/share/godot/export_templates/{VERSION}.stable/macos.zip")
BIN = "macos_template.app/Contents/MacOS/godot_macos_%s.%s"


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.isfile(path):
        print(f"macos_template: no template at {path}", file=sys.stderr)
        return 1
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
    todo = [t for t in ("release", "debug") if BIN % (t, "x86_64") not in names]
    missing = [BIN % (t, "universal") for t in todo if BIN % (t, "universal") not in names]
    if missing:
        print(f"macos_template: {path} has no {', '.join(missing)}", file=sys.stderr)
        return 1
    if not todo:
        print(f"macos_template: {path} already has the x86_64 names; nothing to do")
        return 0
    fd, tmp = tempfile.mkstemp(suffix=".zip", dir=os.path.dirname(path))
    os.close(fd)
    try:
        shutil.copyfile(path, tmp)
        with zipfile.ZipFile(path) as src, zipfile.ZipFile(tmp, "a", zipfile.ZIP_DEFLATED) as dst:
            for t in todo:
                info = src.getinfo(BIN % (t, "universal"))
                out = zipfile.ZipInfo(BIN % (t, "x86_64"), date_time=info.date_time)
                out.external_attr = info.external_attr or (0o100755 << 16)
                out.compress_type = zipfile.ZIP_DEFLATED
                with src.open(info) as fin, dst.open(out, "w", force_zip64=True) as fout:
                    shutil.copyfileobj(fin, fout, 1 << 20)
                print(f"macos_template: added {out.filename} (the universal binary, {info.file_size} bytes)")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
