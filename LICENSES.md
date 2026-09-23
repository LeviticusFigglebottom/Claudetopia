# Third-party content and its licences

Everything not listed here was created by this project (code, meshes, textures,
animations, audio, UI art, text). Only the items below come from elsewhere.

| Item | Where used | Source | Licence | Redistribution |
|---|---|---|---|---|
| **Terrain3D** 1.0.2 (GDExtension plugin) | `game/addons/terrain_3d/` | Tokisan Games, https://github.com/TokisanGames/Terrain3D | MIT (see `game/addons/terrain_3d/LICENSE.txt`) | Permitted with notice |
| **Spectral** (Regular, Italic, SemiBold) | `game/assets/fonts/` — body and book text | Production Type, via Google Fonts | SIL Open Font License 1.1 (`game/assets/fonts/OFL-Spectral.txt`) | Permitted |
| **Cinzel** (variable) | `game/assets/fonts/` — display type | Natanael Gama, via Google Fonts | SIL Open Font License 1.1 (`game/assets/fonts/OFL-Cinzel.txt`) | Permitted |
| **Godot Engine** 4.7.2 | engine | Godot Foundation | MIT | Not redistributed in-repo |

## Terrain3D binaries, and where they came from

Every binary under `game/addons/terrain_3d/bin/` is taken unmodified from the official
release archive `Terrain3D_v1.0.2-stable.zip`, fetched on 2026-09-22 from
https://github.com/TokisanGames/Terrain3D/releases/download/v1.0.2-stable/Terrain3D_v1.0.2-stable.zip
(the download the Godot Asset Library lists for Terrain3D 1.0.2, asset 3892).

Archive SHA-256: `a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2`

| File | SHA-256 |
|---|---|
| `libterrain.linux.debug.x86_64.so` | `178ae39467bb0743c1bbdf854a00f8e7d258a3691bcc1b63d4493beb6bde865e` |
| `libterrain.linux.release.x86_64.so` | `e79ebb2e48a63a5d6189a825f1d63ec847319dc8fa030936d95bf6fad8f294ef` |
| `libterrain.windows.debug.x86_64.dll` | `bf72686a7e1d8d8370ba9ba5eaa70c59375ee2cb5638d63b8942f1ad7d448cda` |
| `libterrain.windows.release.x86_64.dll` | `40900e649c3c6c7619c383d28732c3e2e8dc87c2938de43b29122a668aedcf86` |
| `libterrain.macos.debug.framework/libterrain.macos.debug` | `12b4822ef56fb4396da974f4efcb2db26fa2d9c93179d353bd30ba647cc28b01` |
| `libterrain.macos.release.framework/libterrain.macos.release` | `63449d6de24051669ea81464b1b6b2ae3dc0d72408845bec60b394867ed9b62a` |

The four Linux and Windows files were already vendored here; they are byte-identical to the
archive's, as are `terrain.gdextension` and `plugin.cfg`, which is how this is known to be the
same release. The two macOS files were added from the same archive. They are universal
(x86_64 and arm64; the arm64 slice carries the linker's ad-hoc signature, the x86_64 slice
none) and are built for **macOS 15.0 or later**: an older macOS will not load them.

What the release does not ship, and so this repository does not have: **Linux arm64 and
riscv64** (`terrain.gdextension` names both, but the archive holds no such files) and Windows
on arm64. On those machines, and on a Mac older than macOS 15, the `Terrain3D` class does not
exist at run time, and the game draws the ground itself from the runtime height map
(`game/world/fallback_terrain.gd`), saying so on the title screen.

## Tools used to make our own assets (not redistributed)

Blender 4.0 (GPL; outputs are ours), Python 3 with numpy/pillow/scipy/trimesh/
opensimplex (BSD/MIT/PSF-style; libraries only, not shipped).

## Explicitly not used

No models, textures, sounds or music from third-party packs (Kenney, KayKit,
Quaternius, Poly Haven, ambientCG, Mixamo or others) are included anywhere in
this repository, by decision (see `DECISIONS.md`).
