"""Wickmere asset forge: shared library for the Blender generators.

Pure-Python modules (importable without Blender): palette, cli, glb, naming.
Blender modules (need bpy): scene, materials, bake, export.

Blender runs its own interpreter, and it cannot see the project's Python packages. Pillow
is a declared dependency of this project's tools (`tools/requirements.txt`: `pillow>=10`)
and half of `lib` needs it -- `bake` writes every baked map through it, `textures` draws
the leaf and grass atlases with it, `impostor` blurs a billboard with it. Blender 4.0
happened to ship it and Blender 4.2 does not, so on this container the whole forge died at
the moment it had something to save: `Image.fromarray` on a `None`, after the bake, in
`finish_asset`. It is repaired here, once, before any submodule imports PIL, by putting
the interpreter's *own* version of the project's site-packages on the path: same CPython
minor version, so the compiled wheel loads. Nothing is installed and nothing is vendored.
"""
from __future__ import annotations

import sys
from pathlib import Path


def _repair_pil_path() -> str | None:
    """Make the project's Pillow importable from inside Blender. Returns the path used."""
    try:
        import PIL  # noqa: F401
        return None
    except ImportError:
        pass
    import os
    v = "python%d.%d" % sys.version_info[:2]
    candidates = [os.environ.get("FORGE_SITE_PACKAGES", ""),
                  "/usr/local/lib/%s/dist-packages" % v, "/usr/lib/%s/dist-packages" % v,
                  "/usr/local/lib/%s/site-packages" % v, "/usr/lib/%s/site-packages" % v,
                  "/usr/lib/python3/dist-packages"]
    for c in candidates:
        if c and (Path(c) / "PIL" / "__init__.py").exists():
            sys.path.append(c)
            try:
                import PIL  # noqa: F401
                return c
            except ImportError:
                sys.path.remove(c)
    return None


PIL_PATH = _repair_pil_path()
