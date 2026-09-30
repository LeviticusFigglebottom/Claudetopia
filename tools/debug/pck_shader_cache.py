#!/usr/bin/env python3
"""Counts the baked shaders in an exported Godot .pck, and fails if there are none.

The export's shader baker (game/export_presets.cfg, shader_baker/enabled) puts each shader it
compiled ahead of time in the pack as .godot/shader_cache/<ShaderRD class>/<hash>.<driver>.cache.
An export made headless bakes nothing (the baker needs a rendering device), and the pack is then
the same size as without it, so a player's first launch compiles every shader on the main thread.
The Windows build (.github/workflows/windows-build.yml) runs this on its pack; docs/FIRST_LAUNCH.md.

    python3 tools/debug/pck_shader_cache.py build/windows/Wickmere.pck [--min-scene=N] [--list]

Prints the entries per shader class and driver; exits 1 when the pack has no shader cache, or
fewer SceneForwardClusteredShaderRD entries (the materials') than --min-scene.
"""
import struct
import sys
from collections import Counter

MAGIC = 0x43504447  # "GDPC"
PACK_DIR_ENCRYPTED = 1


def pck_files(path):
    """(path, size) for every file in a .pck (pack format 2 and 3)."""
    with open(path, "rb") as f:
        magic, fmt, _maj, _min, _pat = struct.unpack("<IIIII", f.read(20))
        if magic != MAGIC:
            raise SystemExit(f"{path}: not a Godot pack (an .exe with the pack embedded is not read here)")
        flags, _base = struct.unpack("<IQ", f.read(12))
        if flags & PACK_DIR_ENCRYPTED:
            raise SystemExit(f"{path}: the pack's directory is encrypted")
        if fmt >= 3:
            (dir_off,) = struct.unpack("<Q", f.read(8))
            f.seek(dir_off)
        else:
            f.read(16 * 4)
        (count,) = struct.unpack("<I", f.read(4))
        out = []
        for _ in range(count):
            (n,) = struct.unpack("<I", f.read(4))
            name = f.read(n).rstrip(b"\0").decode("utf-8")
            _off, size = struct.unpack("<QQ", f.read(16))
            f.read(16)  # md5
            f.read(4)  # flags
            out.append((name, size))
        return out


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    min_scene = 0
    for a in argv:
        if a.startswith("--min-scene="):
            min_scene = int(a.split("=", 1)[1])
    files = pck_files(args[0])
    by = Counter()
    total = 0
    for name, size in files:
        p = name.removeprefix("res://")
        if not p.startswith(".godot/shader_cache/"):
            continue
        parts = p.split("/")
        driver = parts[-1].split(".")[-2] if parts[-1].count(".") >= 2 else "?"
        by[(parts[2] if len(parts) > 3 else "?", driver)] += 1
        total += size
        if "--list" in argv:
            print(size, p)
    for (cls, driver), n in sorted(by.items()):
        print(f"{n:5d}  {cls} ({driver})")
    scene = sum(n for (cls, _d), n in by.items() if cls == "SceneForwardClusteredShaderRD")
    print(f"shader cache: {sum(by.values())} entries, {total / 1e6:.1f} MB; "
          f"{scene} SceneForwardClusteredShaderRD (the materials'); {len(files)} files in the pack")
    if not by:
        print("FAIL: the pack holds no .godot/shader_cache/ entries: the shader baker did not run "
              "(an export made --headless bakes nothing; it needs a Vulkan device, e.g. under xvfb-run)")
        return 1
    if scene < min_scene:
        print(f"FAIL: {scene} baked material shaders, fewer than the {min_scene} expected")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
