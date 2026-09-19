# PROGRESS.md — state of Wickmere

_Updated 2026-09-19 (session 1, early)._

## State

**603 unit tests green, 0 content problems. The smoke run builds all 24 shipping
interiors clean. The scripted journey passes all 12 of DESIGN's done-list promises.
16/16 combat-arena checks pass. 620+ content definitions across 23 types.**

Verify the whole thing with four commands:

```
./run.sh test       # 603 unit tests, and content validation fails the build
./run.sh smoke      # build every interior for real; fail on any error
./run.sh journey    # one scripted run through every promise in the done list
./run.sh perf       # draw calls and primitives against the budgets
```

Merged and working on the main branch:

* **Foundations** — autoloads (Log, ContentDB, EventBus, Settings, WorldClock, GameState,
  SaveSystem, Hearth, Interiors, Debug), namespaced IDs with schema and dangling-reference
  validation, versioned saves with a tested migration chain, data-driven input bindings
  with rebinding, a unit-test runner that treats content problems as failures.
* **Atmosphere** — painted sky shader, sun and moon over a 48-minute day, per-region light
  recipes that blend on region change, 16 weather states with precipitation and global
  wind/wetness shader parameters.
* **Hearth** — Hearthstones, death, and the Echo that holds your marks until a second death
  lets it go quiet.
* **Interiors** — a far-pocket loader and doors; the cave forge (nine deep places, each
  with its own formation grammar, beats, shortcut and boss) and the house forge (fifteen
  houses whose plan and contents follow from the resident's trade, wealth, household and
  habits). 3.4 M triangles of authored cave, chunked per chamber so it culls.
* **Integration** — `GameServices` installs law, ownership, stealth, NPC life, market and
  property in dependency order; the player carries and saves their own bag, paper doll,
  skills and recipes. Both existed only because the journey found them missing.
* **Inventory, progression, crafting** — stacks with per-instance state, 13 equipment
  slots, deterministic loot tables, 16 use-based skills with 34 perks, six callings,
  smithing with tempering, alchemy with effect discovery, enchanting with mote charge.
* **Bosses** — five, with phases that swap attack sets, breakable limbs on the
  Stone-Thrall King, channelled attacks that must be interrupted or silenced, and unique
  drops that carry the fight they came out of.
* **Combat and actors** — the full melee, ranged and magic loop with stamina, committed
  attacks, dodge i-frames, block, parry and riposte, poise and stagger, nine status
  effects; player with first and third person cameras, lock-on, mantling and interaction;
  enemy brains for every archetype, pack flanking, chargers, and phased bosses.
* **Narrative** — 25 NPCs with weekly schedules, 25 dialogue graphs, the seven main
  quests, three faction lines, six side quests, 20 books carrying the four contradictory
  accounts, 22 rumours.
* **Tooling** — `run.sh`, the debug console with scripted `--cmd` runs, the region
  drop-test checker, the naming generator with a banned-name check, review scenes for
  atmosphere, interiors and the combat arena.

## In flight (parallel worktree streams, session 1)

World builder + Terrain3D import + streaming + capture/smoke runners · Asset forge
library + trees/rocks/flora/props/landmarks · Character forge + humanoid clip
library · Player/cameras/combat core/enemy AI · Inventory/progression/crafting ·
Dialogue/quests/factions/standing · NPC life/crime/stealth/economy · Narrative
content (Merrowby roster, dialogue, quests, books) · UI (theme, HUD, menus, map,
Naming) · Audio (synth toolkit, music, ambience, SFX, directors).
Integrator (main branch) owns: atmosphere system (done, first pass), merging,
hearthstones/death/echo, docs.

## Next

1. Merge the remaining streams as they land: world/terrain, asset forge, character
   forge, dialogue/quests/factions, NPC life/crime/economy, UI, audio.
2. Place the interiors in the world: doors on the settlement buildings and at each
   deep place's mouth, wired to the `interior` defs.
3. Replace the placeholder props in the interiors with the forge's meshes.
4. Region fly-throughs, the drop test, and a pass of art direction on the overworld.
5. The smoke run over every region and every interior, and the performance budgets.

## Known issues

* Terrain3D + lavapipe (software Vulkan) crashes in JIT code; use OpenGL for
  headless captures (ARCHITECTURE.md §10).
* Compatibility renderer lacks SSAO/volumetric fog; the look must not depend on them.
