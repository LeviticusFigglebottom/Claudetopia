# PROGRESS.md — state of Wickmere

_Updated 2026-09-19 (session 1, early)._

## State

* Tooling verified in-container: Godot 4.7.2 headless run/import/render (Xvfb +
  Mesa; OpenGL for captures), Blender 4.0.2 headless with numpy, Cycles baking
  (1.7 s per 1024² map), Terrain3D 1.0.2 loads and imports heightmaps.
* Docs: DESIGN.md, WORLD_BIBLE.md, ARCHITECTURE.md, DECISIONS.md, LICENSES.md.
* Project skeleton: autoloads (Log, ContentDB, EventBus, Settings, WorldClock,
  GameState, SaveSystem), content pack `core` with 6 regions, 8 factions,
  34 places; test runner with 17 unit tests; `run.sh`.
* Asset forge prototypes: Sapling tree, displaced rock, Skin-modifier humanoid
  with code-authored Walk/Idle/Attack clips exported to GLB and playing in Godot.

## Next

1. Fix Settings parse error; make tests green; commit.
2. World builder (Python) + Terrain3D import tool + streamer.
3. Forge: material library, region trees, rocks, architecture kits, character
   forge v1 with the full clip set.
4. Player controller, cameras, combat core.

## Known issues

* Terrain3D + lavapipe (software Vulkan) crashes in JIT code; use OpenGL for
  headless captures (ARCHITECTURE.md §10).
* Compatibility renderer lacks SSAO/volumetric fog; the look must not depend on them.
