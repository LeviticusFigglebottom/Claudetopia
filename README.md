# Wickmere

An original open-world action RPG built in Godot 4.7. Warm villages that remember you,
wild country between them, and old deep places where the world has gone quiet.

Everything in it is made by this project: the meshes, the textures, the caves, the
houses, the music, the writing. The only third-party files are two fonts and one terrain
plugin, listed in `LICENSES.md`.

## Run it

```
./run.sh
```

That is the whole thing. The built world is in the repository — the part of it the game reads,
about 310 MB, listed below — so a fresh clone needs no Python to play: the first run imports the
project into Godot (a minute or two) and starts the game, and after that it starts at once.
Opening `game/` in the Godot editor and pressing Play does the same.

Requirements: **Godot 4.7.2**. **Python 3.11+** with `pip install -r tools/requirements.txt` only
to rebuild the world, the interiors or the sound; **Blender 4.x** only to regenerate meshes.

`run.sh` is a bash script: on Windows run it from Git Bash. It looks for Godot as `godot` on the
`PATH`, then in the usual places — Downloads, the Desktop, `C:/Godot`, Program Files, Steam and
winget on Windows, `/Applications/Godot.app` on a Mac, an unpacked download on Linux — and takes a
4.7 before any other; `./run.sh godot` says which one it found. Anywhere else, name it with the
`GODOT` variable, with forward slashes on Windows:

```
GODOT="/c/Godot/Godot_v4.7.2-stable_win64_console.exe" ./run.sh
```

A command that needs Godot and cannot find it stops before it does anything and says so. Python is
found the same way (`PYTHON`, else `python3`, else `python`).

### What of the world is in the repository

| Path | What it is | Size |
|---|---|---|
| `game/world/generated/world_manifest.json`, `pois.json`, `roads.json`, `rivers.json` | the manifest, the places and the splines | 0.1 MB |
| `game/world/generated/runtime/` | 1024 x 1024 copies of the heights, regions, water and water level | 10 MB |
| `game/world/generated/cells/` | 1024 cells of 256 m: what stands in each, and what lives there | 154 MB |
| `game/terrain_data/` | Terrain3D's sixteen regions of ground | 145 MB |

The builder also writes 300 MB of full-resolution maps that only the terrain import reads. They
are not tracked (`.gitignore` says which files are), and `./run.sh world` writes everything again.

### If the title screen says the world has not been built

Then this copy has no world data — a checkout from before the world was tracked, say. Build it
from this folder with `./run.sh world`: it needs Python 3.11+ with `tools/requirements.txt`, about
8 GB of free memory and a few minutes. `./run.sh` then starts the game as usual. Until then the
title shuts New Game, Continue and Load, and says the same thing.

### Which machines draw the full terrain

The ground is drawn by Terrain3D 1.0.2, whose release carries binaries for Windows and Linux on
x86_64 and for macOS 15 or later (`LICENSES.md` has their source and hashes). Anywhere else —
Linux on arm64, Windows on arm64, a Mac on macOS 14 or older — on Mesa's software Vulkan driver
(llvmpipe under Forward+ or Mobile, which Terrain3D crashes, sooner or later), and in a copy
whose `game/terrain_data` is empty, the game draws the ground itself from the runtime height map at
8 m: the same country, with softer hills and plainer ground. It says so where it cannot be missed:
across the title screen with the reason and the way to the full terrain, on a card when you arrive,
and on a plate in the top left corner, "Coarse ground", for as long as you walk on it.

If the plate says **the full terrain is not built: ./run.sh terrain**, the world's maps were built
on this machine and never imported into Terrain3D (on Windows this happened whenever `godot` was
not on the `PATH`). Run `./run.sh terrain`, with `GODOT` set if need be; it takes a minute or two.

Two launch arguments choose the ground, from the command line after `--`, or in the editor under
Project Settings → Editor → Run → Main Run Args:

| Argument | What it does |
|---|---|
| `--terrain=fallback` | Draws the coarse ground even where Terrain3D can: to see, test or capture what a machine without it sees, or to get in on a graphics driver that fails inside Terrain3D. |
| `--terrain=terrain3d` | Tries Terrain3D even on a driver it is known to crash. |
| `--terrain-lods=N` | Terrain3D's clipmap rings, 1 to 10 (the `WICKMERE_TERRAIN_LODS` environment variable does the same; the argument wins). Nine, the default, reach the edge of the world from anywhere in it; seven reach about 6 km. Asking also tries Terrain3D on software Vulkan: at seven it drew the real terrain there for about forty seconds of play before the driver crashed, so take short captures. |

```
godot --path game -- --terrain=fallback
```

## Check it

| Command | What it proves |
|---|---|
| `./run.sh test` | 1204 unit tests. Content validation runs here too, so a dangling id fails the build, and the run fails if any test logs an error. |
| `./run.sh journey` | One scripted run through every promise in the design's done list, in the built world: create a character in the Naming and wake at the Hushline Stair as the person you made and walk out of the region, find a village by walking into it and read the country off a vista, meet somebody who lives here, fight, level up, die and recover your marks, join a faction, commit a crime and pay for it, buy a house, clear a dungeon, fight a boss, learn a saying and cast it, save and load. |
| `./run.sh flow` | The way in, pressed the way a player presses it: boots `boot.tscn` with no arguments, clicks New Game by the words on the button, types a name, changes a swatch, a chooser, a slider and a Calling, clicks Be named, and then watches the world for forty seconds — failing if the screen is still black, the fade is still down, the HUD is not up, nothing draws the ground, there is no ground under the body or nothing standing within 200 m of it, Terrain3D is following some other camera than the body's, the coarse ground is drawn without its plate in the corner and its card, the fade lifted before the cells round the body were in, or the body standing there is not the one that was made. With no world on disk it fails at the title, with the title's words in its report. Then the same for `--load=<slot>` and the title menu's Continue. Every step is a PNG in `captures/flow/`; look at them. Needs a display (Xvfb will do). |
| `./run.sh smoke` | Builds all 24 shipping interiors for real and fails if one has no geometry, no collision, no light or no way out. |
| `./run.sh perf` | Measures draw calls and primitives against the budgets in `DESIGN.md` §11. |
| `./run.sh shots` | Headless capture plan into `captures/`. |

## Rebuild it

| Command | What it rebuilds |
|---|---|
| `./run.sh world` | Terrain, region masks, rivers, roads and cell placements from the region recipes, then the terrain import. It looks for Godot before it builds anything, because the import at the end needs it. |
| `./run.sh terrain` | Terrain3D's regions alone, from the full-resolution maps a world build left on this machine. Says so in a banner if it fails. |
| `./run.sh interiors` | Every cave and house from `tools/interiors/recipes/`. |
| `./run.sh assets` | Generated meshes and textures (needs Blender). |
| `./run.sh import` | Re-import the Godot project headlessly. |

`make run`, `make test` and so on work too.

## Read it

| File | What it holds |
|---|---|
| `DESIGN.md` | The game bible: pillars, systems, formulas, art direction, budgets, scope. |
| `WORLD_BIBLE.md` | The world bible: cosmology told four contradictory ways, history, cultures, factions, region identity sheets, bestiary, bosses, naming languages. |
| `ARCHITECTURE.md` | How the code is organised, and how to pick it up cold. |
| `docs/CONTRACTS.md` | The binding interfaces between systems: units, the rig, clip names, asset layout, world data, content shapes, system discovery. |
| `PROGRESS.md` | Where things stand, what is next, what is known to be missing. |
| `ASSESSMENT.md` | A candid assessment: what is good, what is weak, what I got wrong, what to do next. Read this one first if you are deciding whether to continue it. |
| `DECISIONS.md` | Every significant choice, why it was made, and what it cost. |
| `LICENSES.md` | The three third-party things and their licences. |

## Where things live

```
game/            the Godot project (open this folder in the editor)
  core/          autoloads: content, events, settings, clock, state, saves
  systems/       one folder per system, each with a README
  actors/        player, NPCs, enemies, bosses
  world/         terrain, streaming, interiors, atmosphere
  ui/            theme, HUD, menus, map, books
  content/       all game content as JSON, in the core pack
  assets/        generated art and audio
  tests/         unit tests, the smoke run, the journey
tools/           the generators: world, interiors, forge, audio, UI
```
