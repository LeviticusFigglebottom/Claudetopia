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

That is the whole thing. It forges any missing interiors and builds the world — six regions
over eight kilometres square, with its rivers, roads and settlements — then starts the game.
The first run takes a few minutes for the caves and the terrain; after that it is immediate.

Requirements: **Godot 4.7.2** (on `PATH`, or set `GODOT`), **Python 3.11+** with
`pip install -r tools/requirements.txt`. **Blender 4.x** is only needed to regenerate
meshes, not to play.

## Check it

| Command | What it proves |
|---|---|
| `./run.sh test` | 928 unit tests. Content validation runs here too, so a dangling id fails the build. |
| `./run.sh journey` | One scripted run through every promise in the design's done list, in the built world: create a character, wake at the Hushline Stair and walk out of the region, fight, level up, die and recover your marks, join a faction, commit a crime and pay for it, buy a house, clear a dungeon, fight a boss, learn a saying and cast it, save and load. |
| `./run.sh smoke` | Builds all 24 shipping interiors for real and fails if one has no geometry, no collision, no light or no way out. |
| `./run.sh perf` | Measures draw calls and primitives against the budgets in `DESIGN.md` §11. |
| `./run.sh shots` | Headless capture plan into `captures/`. |

## Rebuild it

| Command | What it rebuilds |
|---|---|
| `./run.sh world` | Terrain, region masks, rivers, roads and cell placements from the region recipes. |
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
