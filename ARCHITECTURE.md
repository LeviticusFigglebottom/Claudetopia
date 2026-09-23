# ARCHITECTURE.md — how Wickmere is built

Written so a fresh session can pick the project up cold. Read `DESIGN.md` for
what the game is, `WORLD_BIBLE.md` for the fiction, `PROGRESS.md` for where
things stand, `DECISIONS.md` for why.

## 1. Repository layout

```
run.sh, Makefile          single entry point: run | test | smoke | shots | world | assets | import
game/                     the Godot 4.7 project (open this folder in the editor)
  project.godot           autoloads, physics/render layers, defaults
  core/                   engine-level foundations (autoloads, see §3)
  systems/                gameplay systems, one folder each (see §5)
  actors/                 player, npc, enemy, boss scenes and controllers
  world/                  terrain provider, streamer, cells, POI scenes, interiors, sky/weather
  ui/                     theme, boot, HUD, menus, map, books, character creation
  content/packs/core/     ALL game content as JSON (items, enemies, npcs, quests, ...)
  assets/                 generated art: models/ textures/ audio/ materials/ shaders/ fonts/
  tests/                  unit tests (tests/unit), smoke runner, fixtures
  tools_gd/               in-engine tools run headlessly (terrain import, capture runner)
  addons/terrain_3d/      vendored Terrain3D 1.0.2 (MIT)
tools/                    Python/Blender tooling that runs outside the engine
  forge/                  asset generators (Blender scripts) + shared material library
  world/                  world builder: heightmaps, region masks, rivers, roads, placements
  audio/                  music/ambience/foley synthesis
  ui/                     UI texture generation
  capture/                capture plans and review helpers
captures/                 screenshot output (gitignored)
```

## 2. Principles

1. **Content is data, code is systems.** Anything a designer would tune lives in
   `game/content/packs/<pack>/**/*.json`. Code never hard-codes an ID from the
   core pack except in `content/packs/core` itself and in tests.
2. **Namespaced IDs**: `<pack>:<type>/<name>` (`core:item/iron_sword`). `Ids`
   validates and splits them. Types are fixed by `Schemas.REQUIRED`.
3. **One loading path for all packs.** `ContentDB` discovers `pack.json`
   manifests under `res://content/packs/` and `user://packs/`, orders by
   `depends`, deep-merges `extends` chains, validates required fields and
   dangling references, and logs overrides. The core pack has no privileges.
4. **Systems talk through `EventBus`** (global signals) and read shared state
   from `GameState`. No system holds a reference to another system's node except
   through the autoload singletons.
5. **Everything saveable registers with `SaveSystem`** under a section name and
   implements `to_save()`/`from_save()` with plain Dictionaries (copies, not
   references). Save files are JSON with `schema_version` (currently **3**);
   `Migrations` is a pure chain of `vN -> vN+1` functions with fixture tests.
6. **Data drives visuals.** Region identity (palette, light, weather, flora,
   ambience) is data; generators and shaders consume it.
7. **Nothing fake.** If a feature is not implemented, it is absent and listed in
   `PROGRESS.md`, not stubbed to look present.

## 3. Autoloads (game/core), in load order

| Name | File | Role |
|---|---|---|
| `Log` | `log.gd` | tagged logging, error/warning counters (smoke test fails on errors), `user://logs/wickmere.log` |
| `ContentDB` | `content_db.gd` | pack loader and registry: `get_def(id)`, `all(type)`, `where(type,key,value)`, `ids_of(type)`, `problems` |
| `EventBus` | `event_bus.gd` | global signals grouped by domain |
| `Settings` | `settings.gd` | `user://settings.cfg`, video/audio/controls/gameplay, input map from `core/default_bindings.json`, `rebind()` |
| `WorldClock` | `world_clock.gd` | game time (48 real min/day), `hour_changed`, `new_day`, `wait_until()`, sun elevation |
| `GameState` | `game_state.gd` | flags, counters, discovered places, read books, current region/interior |
| `SaveSystem` | `save_system.gd` | slots in `user://saves/`, `register(section, obj)`, `take_pending()` for late joiners |
| `Hearth` | `systems/hearth/hearth_system.gd` | Hearthstones, respawn point, the Echo (dropped marks), lit stones; section `hearth` |
| `Interiors` | `systems/interiors/interior_manager.gd` | interior cells in a far pocket, door transitions, return point; section `interiors` |
| `Social` | `systems/social/social.gd` | factions, standing, gossip, quests and dialogue under one name; sections `quests`, `factions`, `standing`, `gossip` |
| `Music` | `systems/audio/music_director.gd` | region stems, combat and deep layers, boss music, stingers |
| `Ambience` | `systems/audio/ambience_mixer.gd` | region beds and one-shot pools by time, weather and interior |
| `Foley` | `systems/audio/foley.gd` | `play(id, pos)`, `play_ui(id)`, `footstep(surface, pos)`, `surface_at(pos)` |
| `UI` | `ui/ui.gd` | the CanvasLayer stack, `open(menu)`, `close()`, theme variant, screen fade |
| `Debug` | `tools_gd/debug_console.tscn` | in-game console (backquote), `Debug.register(name, callable, help)`, `-- --cmd="..."` scripting |

Static helper classes (not nodes): `Ids`, `Schemas`, `Migrations`.

## 4. Startup and modes

`ui/boot/boot.tscn` is the main scene. It waits for `ContentDB.loaded`, then reads
user args (after `--`):

* none → main menu (`ui/menus/main_menu.tscn`) or the world if no menu exists yet
* `--new-game`, `--load=<slot>` → straight into `world/world.tscn`
* `--smoke` → `tests/smoke/smoke_runner.tscn`
* `--capture=<plan.json>` → `tools_gd/capture_runner.tscn` (screenshots/fly-throughs)

Tests: `run.sh test` runs `tests/run_tests.tscn`, which discovers
`tests/unit/test_*.gd` (subclasses of `TestCase`) and exits non-zero on any
failure or any `ContentDB.problems` entry. Content validation is therefore part
of the test suite.

## 5. Systems (game/systems) — contracts

Each system folder holds its scripts, a `README.md` (one screen: purpose, data it
reads, signals it emits/consumes, save section) and tests under
`tests/unit/test_<system>_*.gd`. Pure logic (formulas, state machines, table
rolls) lives in `static func`s or `RefCounted` classes so tests need no scene.

| System | Folder | Key classes | Save section |
|---|---|---|---|
| Stats & damage | `systems/combat` | `DamageModel` (pure), `Hitbox`, `Hurtbox`, `StaminaComponent`, `PoiseComponent`, `StatusEffects`, `LockOn` | via actors |
| Progression | `systems/progression` | `Skills` (use-XP curves), `Leveling`, `Perks` | `progression` |
| Inventory & loot | `systems/inventory` | `Inventory`, `Equipment`, `ItemStack`, `LootTable` (pure), `WorldContainer`, `LootDrops` | `inventory`, `equipment`, `containers` |
| Crafting | `systems/crafting` | `Smithing`, `Alchemy` (effect discovery), `Enchanting` | `crafting` |
| Dialogue | `systems/dialogue` | `DialogueRunner`, `Conditions` (pure), `Effects` | none (flags in GameState) |
| Quests | `systems/quests` | `QuestLog`, `QuestStage`, `RadiantGenerator` | `quests` |
| Factions & standing | `systems/factions` | `Factions` (rep, ranks), `Morality` (Hearth/Hollow), `Renown`, `Gossip` | `factions`, `standing` |
| NPC life | `systems/npc_life` | `Schedules`, `Personality`, `Reactions` | `npcs` |
| Crime & stealth | `systems/crime` | `Ownership`, `Witnesses`, `Bounty`, `Stealth` (visibility/noise) | `crime` |
| Economy | `systems/economy` | `Merchant`, `Pricing` (pure), `Property`, `Jobs` | `economy`, `property` |
| Time & weather | `systems/atmosphere` | `Weather`, `SkyController`, `RegionLook` (applies identity light) | `world` |
| Audio | `systems/audio` | `MusicDirector`, `AmbienceMixer`, `Foley` | none |
| Death & shrines | `systems/hearth` | `Hearth` autoload, `Hearthstone`, `Echo` | `hearth` |
| Interiors | `systems/interiors` | `Interiors` autoload, `Door` (+ `DoorLock` child from crime) | `interiors` |
| Atmosphere | `systems/atmosphere` | `Atmosphere` node: sky shader, sun/moon, region look, weather | `world` |
| Exploration | `systems/exploration` | `PlaceDiscovery` (arriving, surveying, line of sight over the built terrain) | none (`GameState`) |
| Streaming | `world/streaming` | `WorldStreamer`, `Cell`, `TerrainProvider`, `Interiors` | `world_cells` |

Most of these are nodes rather than autoloads, each with a `static ensure()` that
finds or creates its own singleton. Nothing calls those by itself, which is how a
player ends up in a world with no law and no market, so
`world/bootstrap/game_services.gd` is the one place that does: its `ORDER` list
installs ownership, bounty, crime reports, stealth, the NPC registry, reactions,
the NPC streamer, the economy service, the property registry and place discovery,
in dependency order. Any host scene — the world, the arena, the smoke run, the
scripted journey — adds a single `GameServices`.

## 6. World data pipeline

1. `tools/world/build_world.py` reads `world.json` (seed, size) and the region
   defs from the core pack; writes `game/world/generated/`:
   heights (`.r32` float32), control/colour maps, region mask, water mask,
   rivers/roads splines, cell placement JSON (`cells/<x>_<z>.json`) and
   `world_manifest.json`.
2. `game/tools_gd/import_terrain.tscn` (headless) imports those maps into
   Terrain3D region files under `game/terrain_data/`.
3. At runtime `TerrainProvider` wraps the `Terrain3D` node (height queries,
   region streaming). `WorldStreamer` loads cell placements in rings around the
   player: authored POI scenes, scatter MultiMeshes, NPC spawns, interior doors.
4. Interiors are separate scenes listed in `interior` content defs; doors carry
   `interior_id` and a spawn marker name.

Generated data is a build artifact, but the part of it the game reads (the manifest, the
places and splines, `runtime/`, `cells/` and `game/terrain_data/`, about 310 MB) is tracked so
a clone plays without Python; `.gitignore` names exactly that set, and `run.sh` builds the
world only when it is missing. `WorldStatus` (`game/world/world_status.gd`) decides at every
way in whether there is a world at all, and when Terrain3D cannot draw it `FallbackTerrain`
draws the ground from the runtime height map (game/world/README.md).

## 6a. Interiors pipeline (tools/interiors)

Interiors are generated from recipes, which are authored intent, not random seeds.

* **Deep places** (`tools/interiors/cave_forge.py`): a recipe lists **beats** (entrance,
  passage, chamber, camp, flooded, shrine, treasure, boss) with a size word and a drop,
  plus links between them and a `shortcut` that loops back. The forge lays the beats out
  in 3D, builds a signed-distance field from ellipsoid chambers and capsule or box
  tunnels, applies the grammar of whatever `formed_by` the place (water, mining,
  creature, crypt, builder, ice), adds stalactites, columns and rubble, roughens the
  walls in three noise bands, flattens floors, cuts light shafts, meshes it with marching
  cubes, splits the shell per chamber so it can be culled, and writes `<name>.glb`,
  `<name>_col.glb` and `<name>.meta.json` (chambers with floor points, light shafts,
  water levels, encounters, features, the beats and the story).
* **Houses and shops** (`tools/interiors/house_forge.py`): a recipe names the resident,
  their **trade**, their **wealth** (0–4), their household and their **habits**. The
  trade decides which rooms exist and what fixtures they hold; wealth decides room size,
  storeys, materials and window count; the dressing pass puts objects on surfaces in
  groups the way a person leaves them, and each habit becomes specific evidence on the
  floor. Outputs the shell, the ceiling timber, collision and a meta file.
* Godot side: `game/world/interiors/cave_interior.gd` and `house_interior.gd` build the
  scene from a meta file; `deep_place.tscn` and `house.tscn` are the scenes the
  `interior` content defs point at. `Interiors` (autoload) loads them into a far pocket.
* Review: `game/tools_gd/interior_review.tscn` renders every chamber or room of either
  kind. `game/tests/unit/test_interiors_uniqueness.gd` enforces DESIGN section 10.

## 6b. Exteriors: the outside of a settlement (game/world/exteriors)

Nothing in the world build places a building. What stands in a settlement is raised at
runtime by `WorldDoors`, from two sources:

* **`building.gd` — the house you enter.** For each door plan row of kind `house`,
  `Building.raise_for()` reads that interior's own meta and raises its outside from its
  inside: ground-floor rooms become wall masses, each mass takes a pitched roof at its
  culture's pitch and depth, the hearth room takes a chimney at the gable, and the front
  door and windows are where the interior put them. So a one-room cottage is small
  outside and the steward's eight-room house is not, and the building you see is the
  building you enter. Surfaces come from `HouseInterior.CULTURE_SURFACES` and
  `Building.ROOF_BY_CULTURE` through `painted_surface.gdshader`, with a per-building
  tone shift so a street is not one house printed nine times. However many rooms and
  windows it has, a building is **four meshes**: walls (masses and gables), roof (slabs
  and ridge), stone (plinths, chimney, sills, step) and joinery (door, frames, shutters),
  plus one collision body per room.
* **`settlement.gd` — the town around it.** Twenty-four interiors cannot furnish eleven
  settlements. `Settlement.raise_at()` lays plots along any road polyline that crosses
  the place's pad (plots front the road; the road is the grain of the street) and falls
  back to a ring around a green where none does. Counts and sizes come from the place's
  `kind` via `Settlement.FABRIC`. The whole fabric is the same **four meshes** for the
  whole settlement — fifty houses cost four draws, each house carrying its own wash as a
  vertex colour (the painted shader multiplies by `COLOR`) — and every filler house has
  a varied plinth, gables, overhanging eaves, a chimney at its hearth end, a framed door
  under a lintel and framed, shuttered windows, all inside those meshes. It then strews
  the culture's props (`PROPS_BY_CULTURE`) as one `MultiMesh` per forge asset; a prop
  whose mesh reaches below y = 0 is lifted by its own box, though the forge now exports
  standing props with their feet at zero (CONTRACTS §4). Joinery and props carry a
  visibility range and the joinery casts no shadow; walls and roofs are drawn to the
  horizon, because a village is read by its roofs from the next hill. Only the collision
  bodies and the interactables (`JobBoard`, `JobStation`, `PropertySign`) are nodes.
* **`fabric_mesh.gd`** is the builder both use: one `SurfaceTool` per surface key, boxes
  emitted from `BoxMesh`'s own winding with a vertex colour per piece, committed as one
  `MeshInstance3D` each.

Both are deterministic from the place id, so a town is the same town every time you walk
back into it; `game/tests/unit/test_settlements.gd` pins that, along with plots not
overlapping, reserved ground being left alone, roads actually lining houses up, and the
mesh count of a village of Merrowby's kind (a ratchet, `MESH_RATCHET`). To see what a
frame's draw calls belong to, shoot a plan with `-- --attribute` (see §10) or type
`draws measure` in the debug console.

## 7. Asset pipeline (tools/forge)

Every asset is generated by our own scripts (see DESIGN.md §7.0). Blender runs
headless (`blender -b --python tools/forge/<gen>.py -- args`). Generators share
`tools/forge/lib/` (materials, bake, export, LOD, collision, naming). Outputs
land in `game/assets/models/<category>/<name>.glb` with baked textures next to
them, plus a `manifest.json` per category recording generator, seed and params
so any asset can be regenerated. `tools/forge/build_assets.py` runs everything
that is missing or stale. Generated outputs are committed so the game runs
without Blender.

Godot import settings for GLBs are set by `game/assets/import_defaults.cfg`
applied through `tools_gd/apply_import_settings.gd` (LODs on, lightmap UV off,
skeleton compression off).

## 8. Actors

`actors/shared/actor.gd` (`CharacterBody3D`): health, stamina, poise, status
effects, equipment attachment points, `AnimationDriver` (maps intents like
`attack_light`, `dodge`, `hit`, `die` to clips on our rig), `Faction` tag.
`actors/player/`: input, camera rig (first/third person), lock-on, interaction.
`actors/enemy/`: `Brain` (state machine driven by archetype data), perception.
`actors/npc/`: schedule follower, dialogue hook, personality reactions.

## 9. Conventions

* GDScript, typed, tabs. `snake_case` files, `PascalCase` classes. One class
  per file. `class_name` only for reusable types.
* Scenes reference scripts by path; content references scenes by `res://` path.
* No `get_node("../..")` reaching across systems; use signals or autoloads.
* Every new system: README, tests, save section, content schema entry.
* Every new region/place/interior: identity data with `unique_feature`, and it
  must pass `tests/unit/test_content_db.gd` and the smoke run.
* Commit small and often; update `PROGRESS.md` at the end of every work block.

## 10. Rendering notes for this container

No GPU. Forward+ runs on lavapipe (software Vulkan) and is the shipped default.

* **Terrain3D crashes lavapipe's shader JIT**, so anything that loads the terrain must be
  captured with `--rendering-driver opengl3` (Compatibility). That is a limitation of the
  software rasteriser, not a Godot or Terrain3D bug.
* **Everything else, including interiors, is reviewed on Forward+**, because Compatibility
  caps omni lights per object (`rendering/limits/opengl/max_lights_per_object`, raised to
  12 here). Past that cap it silently drops lights, which reads as a correctly lit floor
  under an unlit vault, and no amount of extra light fixes it. If an interior looks black
  under `opengl3` but fine under Forward+, that cap is why.
* Keep materials and effects working under Compatibility as well: it is the low-end
  target, and its lighting limits are a design constraint on how many lamps a room gets.
* Interiors set a tonemap white point of 2.0 against the outdoor 6.0. A white point tuned
  for daylight maps a lamp-lit wall to a sixth of its value.
* A draw-call total names nobody. `tools_gd/draw_attribution.gd` says who a frame belongs
  to: a census of what the camera sees by owning script (colour pass), and the measured
  cost of hiding each owner, which includes the sun's shadow cascades — on a clear day well
  over half of a village's draws are shadow passes. The capture runner runs it after every
  shot with `-- --attribute` and writes `<out>/attribution.json`; the console command is
  `draws [measure]`. `tools/capture/plans/streets.json` is the six street shots, the worst
  frames in the game, on their own.
