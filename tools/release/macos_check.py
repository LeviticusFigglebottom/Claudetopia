#!/usr/bin/env python3
"""Checks an exported Mac build of Wickmere (the .zip Godot writes, holding Wickmere.app).

    python3 tools/release/macos_check.py build/macos/Wickmere.zip [--list]

It fails (exit 1) unless:
- the zip holds exactly one .app, with Contents/Info.plist naming its executable and bundle id;
- the executable is a universal Mach-O (x86_64 and arm64), executable, each slice signed;
- Contents/Frameworks has Terrain3D's release framework, universal and each slice signed;
- Contents/Resources has the game's .pck;
- Contents/_CodeSignature/CodeResources is there (the bundle's seal);
- nothing in the bundle is a debug build of Terrain3D.
It prints the bundle's files with their sizes (every file with --list; otherwise all but the
icons and the like). Python only, so the Linux runner that exports can run it; macOS itself
checks the signature with `codesign --verify --deep --strict Wickmere.app`.
"""
import plistlib
import struct
import sys
import zipfile

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
LC_CODE_SIGNATURE = 0x1D
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}


def slices(data: bytes):
    """[(arch, offset, size)] of a Mach-O file, fat or thin."""
    (magic,) = struct.unpack(">I", data[:4])
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        (n,) = struct.unpack(">I", data[4:8])
        out, p = [], 8
        for _ in range(n):
            if magic == FAT_MAGIC:
                cpu, _sub, off, size, _al = struct.unpack(">iiIII", data[p:p + 20])
                p += 20
            else:
                cpu, _sub, off, size, _al, _r = struct.unpack(">iiQQII", data[p:p + 32])
                p += 32
            out.append((CPU.get(cpu & 0xFFFFFFFF, hex(cpu)), off, size))
        return out
    (magic_le,) = struct.unpack("<I", data[:4])
    if magic_le == MH_MAGIC_64:
        (cpu,) = struct.unpack("<i", data[4:8])
        return [(CPU.get(cpu & 0xFFFFFFFF, hex(cpu)), 0, len(data))]
    return []


def slice_facts(data: bytes, off: int):
    """(signed, minos) of the thin Mach-O at off."""
    _m, _cpu, _sub, _ft, ncmds, _sz, _fl, _r = struct.unpack("<IiiIIIII", data[off:off + 32])
    p, signed, minos = off + 32, False, "?"
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[p:p + 8])
        if cmd == LC_CODE_SIGNATURE:
            signed = True
        elif cmd == 0x32:  # LC_BUILD_VERSION
            (v,) = struct.unpack("<I", data[p + 12:p + 16])
            minos = f"{v >> 16}.{(v >> 8) & 0xFF}"
        elif cmd == 0x24:  # LC_VERSION_MIN_MACOSX
            (v,) = struct.unpack("<I", data[p + 8:p + 12])
            minos = f"{v >> 16}.{(v >> 8) & 0xFF}"
        p += size
    return signed, minos


def main(argv) -> int:
    if not argv:
        print(__doc__)
        return 2
    path, show_all = argv[0], "--list" in argv
    bad = []
    z = zipfile.ZipFile(path)
    names = z.namelist()
    apps = sorted({n.split("/")[0] for n in names if n.split("/")[0].endswith(".app")})
    if len(apps) != 1:
        print(f"FAIL: expected one .app in {path}, found {apps}")
        return 1
    app = apps[0]
    c = f"{app}/Contents/"
    print(f"{path}: {app}")
    for i in z.infolist():
        if i.is_dir():
            continue
        if show_all or not i.filename.endswith((".icns", ".xcprivacy", "PkgInfo")):
            mode = (i.external_attr >> 16) & 0o777
            print(f"  {i.file_size:>12,}  {oct(mode) if mode else '     '}  {i.filename}")
    others = [n for n in names if not n.startswith(app + "/")]
    if others:
        print("  outside the app:", ", ".join(others))

    plist = plistlib.loads(z.read(c + "Info.plist"))
    exe = plist.get("CFBundleExecutable", "")
    print(f"Info.plist: {plist.get('CFBundleIdentifier')} '{plist.get('CFBundleName')}' "
          f"exe={exe} category={plist.get('LSApplicationCategoryType')} "
          f"min={plist.get('LSMinimumSystemVersionByArchitecture') or plist.get('LSMinimumSystemVersion')} "
          f"highres={plist.get('NSHighResolutionCapable')}")
    usage = sorted(k for k in plist if k.endswith("UsageDescription"))
    if usage:
        print("  asks for:", ", ".join(usage))

    def macho(member, label, want_exec):
        try:
            info = z.getinfo(member)
        except KeyError:
            bad.append(f"{label}: {member} missing")
            return
        data = z.read(info)
        sl = slices(data)
        archs = sorted(a for a, _o, _s in sl)
        facts = [(a,) + slice_facts(data, o) for a, o, _s in sl]
        print(f"{label}: {member.split('/')[-1]}: " + ", ".join(
            f"{a} ({'signed' if s else 'UNSIGNED'}, min macOS {m})" for a, s, m in facts))
        if archs != ["arm64", "x86_64"]:
            bad.append(f"{label}: architectures {archs}, not arm64 + x86_64")
        if not all(s for _a, s, _m in facts):
            bad.append(f"{label}: a slice has no code signature")
        mode = (info.external_attr >> 16) & 0o111
        if want_exec and not mode:
            bad.append(f"{label}: not marked executable in the zip")

    macho(c + "MacOS/" + exe, "executable", True)
    fw = c + "Frameworks/libterrain.macos.release.framework/"
    macho(fw + "libterrain.macos.release", "Terrain3D", False)
    if not any(n.startswith(fw) and n.endswith("CodeResources") for n in names):
        print("  (the Terrain3D framework has no _CodeSignature/CodeResources of its own; its binary is signed)")
    if any("libterrain.macos.debug" in n for n in names):
        bad.append("a debug build of Terrain3D is in the bundle")
    pcks = [n for n in names if n.startswith(c + "Resources/") and n.endswith(".pck")]
    if not pcks:
        bad.append("no .pck in Contents/Resources")
    else:
        print("pack:", ", ".join(f"{p} ({z.getinfo(p).file_size:,} bytes)" for p in pcks))
    if c + "_CodeSignature/CodeResources" not in names:
        bad.append("no Contents/_CodeSignature/CodeResources (the bundle is not sealed)")
    for b in bad:
        print("FAIL:", b)
    print("OK" if not bad else f"{len(bad)} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
