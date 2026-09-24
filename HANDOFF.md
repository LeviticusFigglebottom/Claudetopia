# Wickmere: handoff

**Read this first.** It is the state of the whole project, and how to carry on from it with
nothing but this repository. It was written by the coordinating Claude session that ran the work
from 2026-09-21 to 2026-09-23. It is refreshed at every hourly check-in while that session runs.
The **Last refreshed** line below says when. `PROGRESS.md` (the long, dated record),
`DECISIONS.md`, `DESIGN.md`, `WORLD_BIBLE.md`, `ARCHITECTURE.md` and `docs/CONTRACTS.md` stay the
detailed references. This file is the map.

**Last refreshed:** 2026-09-24 02:11 UTC. Main is `claude/blissful-volta-dg80e6` at `9263fc11`. Every area's hand-off note is in §6.

---

## 1. What the user asked for (the quality bar)

The user owns the project. Their direction, in their words where it matters:

- **Look and feel.** The painted, mythical aesthetic of *Oblivion*, *Fable* and *Dark Souls 2*.
  Every environment, point of interest and quest should be distinct and compelling.
- **Graphics.** Fidelity customisable in settings. Optimised, but "not at the expense of visuals".
- **The map.** "The game ideally shouldn't have some rng/procedurally generated map… it should
  feel distinct and compelling, densely populated with POI/towns/quests but still sprawling
  massively with several unique biomes/provinces; the seed generation takes the mystique away."
  This is being delivered as the **hand-drawn atlas**; see §5.
- **Working style.** "Keep going, forget the stopping points, just send me periodic updates."
  Work continues without waiting for approval between steps. The user gets short progress reports.
- **The user's machine.** Windows, the Godot **4.7.1** editor (the project targets 4.7.2),
  **Forward+** on an **AMD RX 9070 XT**. That renderer can't be run on the build machine
  (see §8), so the user's playtests are the only real Forward+ check. Treat their screenshots as
  ground truth.

## 2. How the work was organised, and what carries over

- **One coordinator plus worktree agents.** The coordinating session spawned one agent per area.
  Each works in its own git worktree on a local branch, and the coordinator merges finished,
  verified work into the main branch.
- **Agents live in the environment, not the repo.** They are subprocesses of one Claude Code
  session in one cloud container. A new session **cannot** see them, message them or resume them.
  None of this carries over:
  - their transcripts;
  - uncommitted edits;
  - scratch builds and captures under the session's `/tmp` scratchpad;
  - the hourly check-in routine, which is bound to the old session.
- **What does carry over is on GitHub:**
  - `claude/blissful-volta-dg80e6`: **main**, everything merged and verified.
  - `wip/<area>`: each agent's branch, pushed with the user's permission and re-pushed hourly.
    Agents commit checkpoints often; unfinished work is committed with a subject starting `WIP:`.
- **To carry on in a new session:**
  1. Clone the repo and check out main.
  2. Read this file, then look at each `wip/*` branch.
  3. Continue each area, yourself or with new agents, from its section in §6.
  4. Merge a `wip/*` branch into main only after the checks in §7.

  **Never** push to main anything that hasn't passed them.

## 3. Branches

| Branch | Area | Head at last push | State |
|---|---|---|---|
| `claude/blissful-volta-dg80e6` | **main** | `9263fc11` | Verified (§4) and pushed. Player feel round four (slopes, jump) merged 2026-09-24. |
| `wip/world-builder` | World builder: terrain, rivers, roads and cover from the atlas | `304d5df9` | Final 4096 build done. Build helpers are in the repo. Fixing river gorges cut as slots, then hands back. Carries the cartographer's atlas. |
| `wip/atlas-quests` | The drawn atlas (297 locations) plus 40 new side quests and quest plumbing | `ebb5f18b` | Atlas final. Quest plumbing Phase A done. The Hushline has moved onto the landing. Next: the atlas items that gate the merge, then the **quest walker** (`./run.sh quests`). |
| `wip/atlas-readiness` | The game follows places, not coordinates, on the atlas world | `4e479668` | PlaceRef and the coordinate inventory are done. The game runs on the atlas world (journey 16/16, fights 0 failed, 1 atlas-side test fail). Next: merge main, rerun, hand back. |
| `wip/opening` | The intro cinematic, the start, and its loose ends | `62cd87b3` | **NPC talk and tents fixed** (tests pass). The flow now talks to Wren through the key. Camp life added. Final suite, journey and flow, then merge. |
| `wip/player-feel` | Movement, gaits, animation feel | `63b462b9` | **Slopes and jump fixed** (5–40° climbed at full pace; jump rises about 1.1 m) with `test_walking_uphill`. Full suite, journey and flow running, then merge. Then the attack-clip audit. |
| `wip/painted-look` | The painted art direction: light, fog, sky, water, grade | `cbf7a236` | **URGENT: black ground, diagnosed** (the ash soil albedo, §4); fix next. |
| `wip/graphics-settings` | The Graphics tab, presets, tree LODs, budgets | `a5a930e9` | Suite passes (1616 tests, 0 failed). The flow failure was main's old opening stall. Next: merge main, then flow, then hand back. |
| `wip/characters` | Bodies, faces, hair, clothing, the Naming screen | `7b9537b9` | Most refinements done. The empty Naming preview is fixed (class cache). WIP: the wrist rebuild, cloaks mid-stride, the brigandine review (§6.8). |
| `wip/settlements` | Settlements as streets, POI people and dressing, quest plumbing | `320c1739` | **Brief done and verified** (test 1664 passed, 0 failed; journey 16/16; smoke PASS; flow 98/99, the miss is the opening's). Queued for the next batch merge. Next: the atlas POI kinds. |

The heads move. `git log origin/wip/<area>` is the truth, and each branch's newest `PROGRESS.md`
section says what it did.

## 4. The state of main (what a player gets today)

Verified on `6985d356` (the opening's merge; the tree is identical to what its agent tested):

- `./run.sh test`: 1594 tests, 0 failed, 0 content problems, 0 script errors, 0 dead lambda
  captures. There are 4 logged errors; tests provoke them on purpose.
- `./run.sh journey`: 16/16 steps.
- `./run.sh flow`: PASS for New Game (99 checks), Load (32) and Continue (35).
- `./run.sh fights` (at 6838f23b): 66 fights, 0 failed checks.

**What's in it**, in merge order (`git log --first-parent`):
- the built world, tracked;
- **no void**: the world appears for a fresh clone on any desktop, with a fallback ground and
  Godot discovery on Windows and Mac;
- **the painted look**: named lights, sky, water drawn, the grade fixed, the flicker gone;
- **player feel**: camera-relative WASD, gaits at game speed, Sprint, roll, controls taught on
  screen;
- **combat and sound**: DESIGN §5.3 timing, the audio-mixer crash guarded (`AudioGuard`),
  24 doors landed both ways, interiors on the rock;
- **characters round two**;
- **quests round two**;
- **the opening**: a 95 s skippable cinematic after the Naming on New Game only, running on the
  wall clock with bounded waits. The Warden is at her fire on the first frame, the first
  objective is on the compass, and the Naming's fight is out of the Choir colossus.

**It still has the old, seeded world.** The drawn atlas (§5) isn't in main yet.

### Open bugs from the user's latest playtest (at 6985d356)

| Report | Owner branch | Status |
|---|---|---|
| "Talking to Wren doesn't do anything": the first objective is blocked | `wip/opening` | **Diagnosed, game-wide.** `Npc.interact` emitted `EventBus.dialogue_started` and stopped; only `Social.talk` starts the DialogueRunner. So pressing `E` on **any** NPC did nothing, and every test called `Social.talk` directly. Also, 60 of 72 dialogues sent "bye" back to "hub", so a talk could never end. Fix in WIP `cede10cd`, not yet run: `Npc.interact` and the property steward call `Social.talk`, the runner stops after "bye", and `runner.just_ended()` stops the closing key press re-opening the talk. The new `test_talk_to_the_warden` presses the real key at 4, 2.5 and 1.5 m. **Merge as soon as it passes.** |
| "Walking up any incline seems impossible" | `wip/player-feel` | **Fixed in main (9263fc11).** `snap_to_terrain` stands down on a floor collider and never pulls a rising body down. Walking, jogging and sprinting climb 5–40° at full pace, and 50° is a wall (`test_walking_uphill`). |
| "Jump doesn't work" | `wip/player-feel` | **Fixed in main (9263fc11).** The body leaves the ground 0.12 s after the press and rises about 1.1 m. Jump_Start → Jump_Loop → Jump_Land. |
| "The ground is black" | `wip/painted-look` | **Diagnosed, and not Forward+-only.** The `ash_soil` slot draws at linear albedo about 0.008: texture mean 0.017 × `albedo_color` 0.45, charcoal colours in `tools/world/gen_terrain_textures.py:432`. `fused_stone` is 0.020. Grass is 0.05–0.1. The Stair Head's ground is 48% ash. Fix in progress: raise both to about 0.035–0.045 (the `value` column in `tools_gd/import_terrain.gd` SLOTS, and `albedo_color` in `world/terrain_assets.tres`), with a unit test against any slot under 0.02. Measure with `python3 tools/world/ground_albedo.py --at -1922,3708 --regions --floor 0.02`. |
| "Inverted tent edges" at the camp | `wip/opening` | To fix: backfaces or normals on a camp tent prop. |
| "Attacking animations still need revising" | `wip/player-feel` | After slopes and jump: an audit of the attack clips, keeping DESIGN §5.3 timing. |
| "A little sparse" | `wip/atlas-*`, `wip/opening` | The atlas more than doubles the locations and adds 40 quests. Camp life is on the opening's list. |
| The debugger lists 239 entries | unassigned | Mostly GDScript warnings: `event_bus.gd` signals "declared but never used". Silence them properly so real errors stand out. |

## 5. The critical path: the hand-drawn atlas replaces the seeded world

**Status:** the atlas is authored and verified. The builder makes it at full size. The game is
being made to follow places. Three hand-backs gate the merge:
1. `wip/world-builder`: the river-gorge fix, then its hand-back.
2. `wip/atlas-readiness`: the world-coupled tests pass on the atlas world.
3. `wip/atlas-quests`: the quest walker finishes all 75 quests and every decision branch on the
   atlas world.

**What the atlas is:**
- `tools/world/atlas/atlas.json` is the source. `docs/ATLAS.md` explains every province and
  valley, and has tables of the moved and new locations. `docs/atlas/wickmere_atlas.png` is
  the map the user reviewed.
- **Size:** 8192 m square, 61.4 km² of land, 47.2 km² walkable.
- **Provinces:** 22, in 6 regions: Skerrow, Brightwater, Sedgemire, Hearthvale, Cinderlea and
  the Briarwold.
- **Locations:** 297 (57 places and 240 POIs). Nearest location: mean 180 m, 95% within
  312 m. 83 roads, 80 km.
- **Moved and new:** 83 existing ids moved, none renamed; 217 new ids.
- **Quests:** 40 new side quests (75 authored in all). Every settlement offers work. All
  240 POIs pay off in placed content.

**The merge, when all three have handed back.** Only the main checkout commits world data:
1. In main, `git merge --no-ff` each branch in turn: `wip/world-builder`, then
   `wip/atlas-quests`, then `wip/atlas-readiness`. PROGRESS.md and DECISIONS.md conflicts are
   append-only, so keep both sides.
2. Rebuild the world from the atlas with `./run.sh world`. It builds with Python and imports
   Terrain3D at the end. On the build machine it took about **16 min** at about **6.2 GB peak**
   RSS, so have about 10 GB free. The land agent's note gives the exact flags; see §6.1.
3. Check `git status`. Only the runtime world set should change:
   - `game/world/generated/{world_manifest.json,pois.json,roads.json,rivers.json}`;
   - `game/world/generated/runtime/`;
   - `game/world/generated/cells/`;
   - `game/terrain_data/terrain3d*.res`.

   These are the paths `.gitignore`'s negations let through.
4. Stage those **by name**, then commit. The world is about 150 MB of history per rebuild, so
   rebuild only for a real change.
5. Verify on a **fresh clone** of the pushed-to-be tree:
   - `./run.sh test`, `flow`, `journey` and `fights`;
   - the quest walker (`./run.sh quests` or whatever `wip/atlas-quests` names it).

   Then push.
6. Tell every area to merge main. After that:
   - the opening re-frames its ten shots on the drawn geography (its Phase B);
   - the painted look re-shoots;
   - graphics re-measures the streets.

## 6. Every area: state, next steps, traps

Each subsection is refreshed from its agent's hand-off note. Commands assume the repo root.

### 6.1 World builder (`wip/world-builder`)
- **Done:**
  - the atlas builder, including coast shelves, `stair` roads, pinned POI pads, lake shores and
    ranges;
  - bounded memory; the combing fixed (`line_field` distance);
  - rivers carry `surface_m` per point, so `water_surface.gd` draws them on their own water;
  - the landing's broken seaward edge, with its notch where the Oroth stair leaves.
- **Final 4096 build:** 972 s wall, 6.19 GB peak, 3.93 M scatter instances, heights −24.2
  to 784.2 m, 17% water.
- **In progress:** river gorges are cut as slots. `hydro.carve_river_valleys` fades to untouched
  land over 11 m, so where the land is 50 m or more higher the fade is a wall (the Brindle, Rudd
  and Rib Becks). The fix carries the valley side out at a 1.2 grade until it meets the land.
- **The atlas still owes** (for the cartographer or builder):
  - 28 refused sightlines (the worst is Oskelcrag→Skerry Watch, 144 m over);
  - the Heron Watch stands 8 m from the North Channel;
  - the Blackgill's water stands 23–26 m over its hollow;
  - the Thornmarch is a straight 7.5 km scarp;
  - the walk from the Stair Head to the Choir is 980 m.
- **Build, install and verify** (from its note; head `05937961` carries these helpers):
  ```
  tools/world/build_when_free.sh /tmp/w4096 /tmp/w4096.log    # no recipe; seed 8471 from the pack; waits for 10 GB free
      # share a lock with WORLD_BUILD_LOCK=<path> WORLD_BUILD_OWNER=<id>; ~16-17 min, peak 6.2 GB
      # preview: MEM_GB=4 ... --size 1024 (~90 s, 0.6 GB)
  tools/world/install_world.sh /tmp/w4096      # copies into game/world/generated, godot --import, Terrain3D import
  python3 -m pytest -q tools/world/tests tools/tests
  godot --headless --path game --audio-driver Dummy res://tests/run_tests.tscn -- --filter=water
  python3 tools/world/atlas/render_build.py --world /tmp/w4096 --out /tmp/map.png --size 2048   # look at it
  python3 tools/capture/make_default_plan.py && python3 tools/capture/make_default_plan.py --horizon \
    && python3 tools/capture/make_pois_plan.py && python3 tools/capture/make_default_plan.py --look   # after any rebuild
  ```
  In an agent's worktree, `git checkout -- game/world/generated game/terrain_data` before
  committing. In main, §5 says what to commit.
- **Its recommendations for what the atlas still owes:**
  - Of the 28 refused sightlines (`test_sightlines` fails on them), move the POI or the vantage
    for the 21 that are over 25 m. The builder won't cut deeper.
  - Four stand 1–2 m outside an end pad. Move each target about 15 m.
  - Three are unexplained: Hazelwick→Barkbridge, Charcoal Camp→Foxfire Falls and Kharrow
    Hold→Chain Bridge.
  - Move the Heron Watch (−2460, −640) about 30 m off the channel.
  - End the Blackgill in a pool under the falls at (2600, −1700), or join it to the Skarl Water.
  - Redraw the Thornmarch's x = 3965 line as a wandering border.
  - For the 980 m from the Stair Head to the Choir, bring the Choir nearer, or lower the knoll
    or the plateau.
- **Traps:**
  - Under about 7 GB free, a 4096 build dies to the OOM killer.
  - The build log's "N cut / M left" is measured before rivers and roads; `test_sightlines` is
    the truth.
  - The same atlas and seed give the same world, apart from the manifest's build time.
  - `game/world/terrain_assets.tres` is tracked, and builds don't change it.

### 6.2 Atlas and quests (`wip/atlas-quests`)
- **Done:**
  - the atlas (§5);
  - 40 side quests in `game/content/packs/core/quests/the_map.json`, each ending in a
    three-way decision the giver remembers;
  - the hook table `core:table/poi_hooks`, rewritten by `tools/poi_hooks.py` (`--check` finds
    stale rows);
  - quest plumbing:
    - `talk` objectives by `topic`;
    - `read_book` with `in_place`;
    - a `bounty` effect through the crime service (the missing `bounty_for` also fixed);
    - `test_quest_reach` reads `offer`;
    - residents `offer_work` through `JobBoard.for_place`.
- **Head:** `a90cfdde`, from its note.
- **The Hushline** moved from (0, 3990) onto the landing at (10, 3870), with an atlas pad
  (level 4, r 20). ATLAS §3, §11 and §12 are updated. The escort step floor went from 40 to 30.
- **Results:**
  - `check_atlas`: 0 errors;
  - the atlas pytest: 31 passed;
  - `poi_hooks --check`: 0 differ;
  - `test_map` 13/0, `test_quest` 82/0, `test_poi` 38/0, `test_escorts` 7/0,
    `test_faction_lines` 38/0;
  - on w_final4: `test_settlement_people` 12/0 and `test_npc_streamer` 11/0.
- **Still failing on w_final4:**
  - world-side, sent to the builder: `test_world_data` river widths (the Weaver Gill 3.8 m, the
    outfall 19.9 m, the North Channel 14.7 m);
  - `test_the_start`: the 980 m walk, the Stair Head pad, the way round the solid, and the
    landing's wights. Some of these pass on `wip/atlas-readiness`, whose place-relative
    conversions this branch doesn't have.
- **Next, in order:**
  1. The atlas items that gate the merge:
     - The Choir walk, 980 m against 300–650 m. The road drops 38 m off the knoll into the heath
       dip at (−45, 3560), then zigzags up a 56 m scarp. A fix must cut that vertical: a saddle
       from the Stair Knoll to the Choir's Crown, or the Choir and the plateau edge nearer.
     - The Heron Watch 30 m off the North Channel.
     - Wat Thatcher's and Jory Wick's schedules.
     - The 28 sightlines.
     - The Blackgill's end.
     - The Thornmarch border.

     Then tell the land agent to rebuild at 4096.
  2. The quest walker, `game/tests/quests/quest_walker.tscn/.gd`, built like `tests/journey`,
     and run by `./run.sh quests [--only=<quest id>]`.
     - Per quest, it starts through the giver's offer, then drives each objective through the
       services:
       - teleport or walk to the `where`;
       - `DialogueRunner` to the topic node;
       - kills through `take_hit`;
       - `WorldItem` pickups;
       - books read.
     - Before each choice it saves with `SaveSystem.serialize()`, then deserializes once per
       option.
     - It asserts the effects and the remembered greeting.
- **Traps:**
  - The quests, dialogues, places, POIs, encounters and books JSON is canonical; edit it directly.
    The scratch DSL that first wrote it is gone. Don't recreate it.
  - `atlas.json` is canonical and hand-edited. Move a pack position and its atlas feature
    together, and update ATLAS §12.
  - Escort arrival and quest reach use the content position. Map markers use the generated
    `pois.json`, which is stale until the next build.
  - Restore installed test worlds with
    `git checkout -- game/world/generated game/terrain_data; git clean -fd game/world/generated`.
- **Checks:**
  - `python3 tools/world/atlas/check_atlas.py` (0 errors);
  - `pytest tools/world/tests/test_atlas.py tools/world/tests/test_atlas_map.py`;
  - `python3 tools/poi_hooks.py --check`;
  - `./run.sh test`.

  Twelve world-coupled Godot tests fail until the tracked world is rebuilt from the atlas. That's
  expected; §5 says when.

### 6.3 Atlas readiness (`wip/atlas-readiness`), from its note
- **Head:** `a0dd10dd`, with the land branch merged at `3aced4f4`.
- **Done:**
  - The inventory is in `docs/COORDINATES.md`: each coordinate classed as derived, converted or
    legitimately absolute, plus the procedure after a redraw.
  - `PlaceRef` (`systems/shared/place_ref.gd`) resolves `{place, bearing, distance, height}`,
    offsets and way shapes. Door plans name their place only. The Stair Head's way is a shape.
    Hand capture plans are place specs. Saves pin the player, the Hearth, interiors and escorts.
    Tests use `TestCase.at_place`.
  - `test_place_ref.gd` (15 tests) moves places, and fails on coordinates in content.
  - Game-side fixes the atlas found:
    - stone stair colliders;
    - the terraced falls' Hearthstone flag;
    - Willow Isle on its own surface;
    - the Hand shot raised 3 m;
    - chart labels.
- **Results:**
  - On main's world: test 1599 (1 fail, fixed), journey 16/16, fights 66 with 0 failed checks.
  - On the atlas world (w_final3/4): test 1599, with 1 fail that is atlas-side (the waystone walk
    is 980 m against the 300–650 m the start test expects), journey 16/16, fights 66 with 0
    failed checks, and all 24 doors land both ways. The body starts at (10, 108, 3670).
  - Flow's 10 failures were the old opening stall, which is fixed in main.
- **Next:**
  1. Merge main.
  2. `tools/world/use_build.sh --restore` puts the committed world back.
  3. `./run.sh test && ./run.sh journey && ./run.sh flow`.
  4. Hand back.
- **To try a build:** `tools/world/use_build.sh <build dir> [<terrain dir>]`, then
  `python3 tools/world/place_checks.py`, then `./run.sh test`.
- **After main's world is rebuilt from the atlas:**
  - `python3 tools/capture/make_default_plan.py` (and `--look`, `--horizon`);
  - `python3 tools/capture/make_pois_plan.py`;
  - `python3 tools/ui/gen_map.py --world <full build dir>`. The tracked world has no
    `heights.r32`.
- **Atlas-side, sent to the cartographer:**
  - the Heron Watch stands in the North Channel;
  - Wat Thatcher's schedule leg crosses the Lark Pool;
  - Jory Wick commutes across the Mere;
  - 28 of 201 sightlines are refused;
  - the 980 m way.
- **Traps:**
  - Never stage `game/world/generated` or `game/terrain_data` after `use_build.sh`.
  - A test file edited mid-suite fails once, so rerun it alone.
  - The generated capture plans fail `tools/tests/test_capture_plan.py` until regenerated on
    the final build.

### 6.4 The opening (`wip/opening`)
- **In main:** the whole opening.
  - The stall was slow motion: Godot caps physics at 8 steps a frame, so under load game time
    crawled. It now runs on the wall clock.
  - The Hushline landing sits on a dry shelf, and the Naming's fight is at the Choir.
  - `QuestFoes._blocked` rejects spots with something solid overhead. Landmark collision is a
    hollow trimesh.
- **Head:** `cede10cd`, from its note. The full suite passes on `fcf08d50` (1600 tests, 0 failed,
  0 script errors), and journey is 16/16.
- **Phase A, done:**
  - title and Naming music now play (`16042fc7`);
  - `QuestLog.start` sets stage 0 before `quest_started`, and a wall-clock `PollTimer` drives the
    NPC streamer (`79e7b212`);
  - `QuestFoes.clear_ground` rings outward and never takes a landmark's middle (`0ed758c9`);
  - subtitles fade on the wall clock (`fcf08d50`).

  The dusk stars and the dotted sky line belong to the painted look, and are fixed on its branch.
- **Urgent, in progress:** talking to NPCs; the diagnosis and fix are in §4.
  1. Run `OUT=/tmp/t tools/debug/tests_one_at_a_time.sh test_talk_to_the_warden test_dialogue_runner test_npc_actor test_property`,
     fix what fails, then commit without "WIP:".
  2. Add a flow check after the first moment of control: go to Wren at 2 m, press interact
     through `Input.parse_input_event` and `push_input`, and assert that the dialogue is on screen
     and the Naming leaves "wake".
- **The tents:** `k.prop("tent")` in `world/pois/poi_builders.gd` (about l.279, plus l.117 and
  l.2158) resolves to `assets/models/props/cinderlea_tent_{a,b}.glb`, forged by `tools/forge`.
  Fix the flipped faces or normals in the recipe and rebuild with `./run.sh assets`, or make the
  cloth `CULL_DISABLED`. Add a test and look at a shot.
- **Then:**
  - camp life (animals by the cart, smoke, the Wardens' gear in `_camp_stair_head`);
  - the full suite, journey and flow;
  - one PROGRESS section.
- **Phase B, after the atlas lands:**
  - merge main;
  - re-frame the ten shots (Tollmere's harbour bight, the Spire on its rock, the Stride Ness
    causeway);
  - steps and parapets on the stair road;
  - read the start from the manifest;
  - flow green.

  `python3 tools/debug/route_check.py game` checks the waystones.
- **Traps:**
  - Never edit `game/` during a run: hot reload fakes SCRIPT ERRORs.
  - The player polls Input in `_physics_process`, so headless presses need `parse_input_event`,
    `push_input` and `flush_buffered_events`, held for 3 or more physics frames.
  - Never pipe `run.sh test` or `flow` to `head`: they `tee` to stderr, so redirect to a file.
  - `first_fight.json` and the flow's spots are current-world positions (Choir −1900, 3300;
    start −1922, 3708). The atlas moves them.

### 6.5 Player feel (`wip/player-feel`), from its note
- **Done** (verified: test 1595 tests, 0 failed; journey 16/16; flow not yet passed on this
  branch, blocked by load):
  - planted stops (FootPlanter), the braking hold, heel-down after turns;
  - four turn clips, four-way legs with hip turn, Trot;
  - Walk_Back and strafes remade;
  - the pad layout, with a `RETIRED_DEFAULTS` migration.

  The numbers are in PROGRESS "Feet on the ground".
- **In progress:** slopes and jump. WIP `ca2d4920` adds `game/tests/unit/test_walking_uphill.gd`:
  a synthetic Terrain3D of ramps from 0 to 50°, collision on and off, driven by real keys. It
  fails, as it should.
- **Diagnosis:** `Actor.snap_to_terrain` (`actors/shared/actor.gd`) snaps whenever the body is
  within 0.12 m above the provider height.
  - On a slope collider the capsule (r 0.35) rests r(1/cos θ − 1) above that height, so the
    snap sinks it and the collider pushes it downhill. A jog makes 48% of its pace at 35°; a walk
    sticks at 40°.
  - A jump's first tick rises 7.7 cm, inside the skin, so it is pulled back every tick.
- **Next steps:**
  1. In `snap_to_terrain`, do nothing when `is_on_floor()`, never pull down a rising body, and
     fix the stale comment.
  2. In `player.gd`, jump, Jump_Land, mantle and block use `_on_ground()`.
  3. Consider `floor_constant_speed = true` and `floor_max_angle` from `WALKABLE_SLOPE_DEG`.
  4. `godot --headless --path game --import`, then `./run.sh test --filter=test_walking_uphill`,
     plus `test_player_locomotion`, `test_roll_from_the_keys`, `test_combat_design` and
     `test_locomotion_blend`.
  5. The full suite, journey and flow.
  6. Then the attack-clip audit.
- **Traps:**
  - `Engine.time_scale` scales the physics delta; it doesn't add ticks.
  - The test runner doesn't await `after_each`.
  - Terrain3D wants `set_camera` before its first physics frame.
  - `user://` is shared by every worktree on one machine.
- **Films:**
  - `tools/capture/film_motion.sh tools/capture/plans/turns_and_ways.json captures/turns`;
  - `tools/capture/film_motion.sh tools/capture/plans/stop_planted.json captures/stops`;
  - clips come from `blender -b --python tools/forge/bake_clips.py -- --out <dir>`, then
    `tools/forge/transplant_clips.py` (see `docs/CONTRACTS.md` §3).

### 6.6 The painted look (`wip/painted-look`), from its note
- **Head:** `cbf7a236`, with main merged.
- **Done and verified:**
  - The grey flicker is fixed: the grade LUT is made once and updated in place. On Forward+
    (lavapipe), 250 frames read luma 0.38–0.49 with none dark.
  - Water draws, because its mask bytes are stretched (`test_water_look`, CONTRACTS §6).
  - Per-region palettes. Stars wait for the dark. Cirrus in wisps. Overlays faint, with grain
    off by default.
  - The drop test went from 0.64 to 0.79.
- **Tests:**
  - The suite passes, apart from one flaky failure under load (`test_control_hints`, which
    passes alone).
  - Flow: new game 90/90 and load 32/32. Continue was OOM-killed by the kernel partway through.
- **Urgent:** the black ground, diagnosed in §4. The fix is next, plus a minimum-albedo test and
  before/after shots:
  - `./run.sh shots tools/capture/plans/start.json`
  - `python3 tools/capture/forward_plus.py tools/capture/plans/start.json captures/fplus_start --lods 7`
- **What to ask the user if it's still dark after the fix:**
  1. the Output lines with `[World]` or Terrain3D ("terrain textures ready: 21 slots" versus
     "texture array was not built");
  2. whether a corner plate says the ground is coarse;
  3. whether ticking Remote → World/Terrain3D → Material → *Show Checkered* shows a clear
     checker, which would mean the light is fine and the albedo is at fault.
- **Then:** the per-region fog layers and lamps in code, and the full re-shoot on the atlas world.
- **Traps:**
  - Forward+ on lavapipe segfaults with Terrain3D at 9 rings, so use `--terrain-lods=7`.
  - It also crashes on moving cameras and every few teleports.
  - It takes about 4 s a frame, and needs 6 GB or more free.

### 6.7 Graphics settings (`wip/graphics-settings`)
- **Done:**
  - a Graphics tab: four presets and 24 controls, applied live and saved in a `graphics`
    settings section;
  - main's atmosphere keys moved there, with a one-time migration;
  - rows that Compatibility can't do are greyed out with a reason.
- **Tree LODs:** full mesh, the forge's mid mesh, then an eight-view impostor, with fades. Bark
  sheets in 19 mid meshes removed.
- **Budget:** at High, Merrowby's street went from 1470 draws / 1.55 M primitives to
  1384 / 0.94 M.
- **Streets on the merged tree** (`./run.sh shots tools/capture/plans/streets.json --preset=<p>`),
  worst frame:
  - High: 1526 draws / 1.05 M primitives;
  - Painted: 1805 / 1.39 M;
  - High `--no-lod`: 1619 / 1.71 M.

  All are under the 2000-draw budget; High `--no-lod` is over the 1.5 M primitive budget.
- **A real bug fixed** in `efb55a3c`, with a test: the coarse ground read LOD-group MultiMesh
  buffers back as NaN. That caused 72–454 script errors and garbage trees on the fallback ground
  (Macs before 15, arm64 Linux, `--terrain=fallback`).
- **Head:** `6fe6cefa`. The suite passes (1616 tests, 0 failed) on `efb55a3c`.
- **The flow that exited 1** was main's opening stall at the time, now fixed. The Load start then
  replayed the opening from a slot saved mid-opening, which is also fixed in main.
- **Next:**
  1. Merge main, then run test and flow. Expect all three starts to pass.
  2. Forward+ Painted on the coarse ground (more than 7 GB free), and High `--no-lod` to
     attribute 14 RD "Buffer argument is not a valid buffer" errors.
  3. Low and Medium street shots.
  4. Rebuild the 4 poor LOD1s (PROGRESS "Next" item 4).
  5. Instance scale into the level lines.
- **Trap:** Godot 4.7 records a failed import as done. After fixing an import script, delete the
  matching `.godot/imported/*.md5`, touch the sources, then `./run.sh import`.

### 6.8 Characters (`wip/characters`), from its note
- **Head:** `e7351633`, with main merged at `6985d356`.
- **Brief:** a second pass on the characters (skull, hair, cape, harness, external textures, a
  child body, eyes and skin), the Naming screen first, then the four rough things (plaid, paddle
  hands, the A-pose idle, the flat face).
- **Done and verified in the engine:**
  - a relaxed, weighted Idle;
  - hands with fingers;
  - face paint: brows, lashes, nose and lips;
  - the tartan plaid;
  - skirts, robe and kilt across both thighs;
  - gloves;
  - long hair, braid and beard;
  - the harness and helm;
  - pauldrons;
  - child clothes;
  - `ArmRoom`, which turns the arms out for padding.
- **The empty Naming stage** was a stale `.godot` class cache.
  - `run.sh` now imports whenever a `class_name` is missing from the cache (`184a7991`).
  - The probe now fails unless the body script loads and draws a mesh (`663af1af`).
  - A tour from a clean cache passed 235 checks, 0 failed, with a figure in all 34 frames.
- **Suite:** 1596 tests, 0 failed, 0 script errors.
- **WIP commits** (each body says what fails):
  - `0bff37b6`: the Naming's suggestion buttons clip, and no tour has run since.
  - `8e7b29af`: the wrist-join code is final, but the committed rig and bodies are one step
    older and have a groove at each wrist. The rebuild is running.
  - `2592df60`: cloaks draped over the Idle. The forward arm pokes through at Walk@0.51.
  - `e7351633`: the brigandine, not yet seen in the engine.
- **Next:**
  1. Rebuild the rig and bodies from the final wrist code:
     - `tools/forge/rigbuild.sh` (about 30 min; expect "identical (<1e-5): 71");
     - `blender -b --python tools/forge/character_forge.py -- parts --only bodies` (about 15 min);
     - check with `tools/forge/preview/looks.sh <out> tools/forge/preview/looks/hands.json --frame=hands`.
  2. Cloaks mid-stride.
     - Try weight rules with `python3 tools/forge/preview/cloakreweight.py o.png cloak aniso2 Idle@0,Walk@0.25,Walk@0.51 --views=0,60,90,270`.
     - Damp the arm swing under long cloaks during locomotion only.
     - Port the result to `cloth._cloak_weights`, then build
       `parts --only cloak hooded_cloak ragged_cloak torn_cloak hood shoulder_cape` (about
       28 min).
  3. Review the coat walking (`looks/outfits.json`) and the brigandine (`looks/armour.json`) in
     the engine.
  4. `./run.sh import`, then test, flow and journey, and
     `python3 -m pytest tools/tests/test_glb_textures.py`.
  5. The Naming tour at 1280, 1920 and 2560:
     `xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 -- --flow=<out> --naming-tour`.
     Look at every frame.
  6. The PROGRESS section, at the end of the file only.
- **Clips, only when one changes:**
  - `blender -b --python tools/forge/bake_clips.py -- --out <dir>`;
  - then `python3 tools/forge/transplant_clips.py <rig.glb> <dir>/humanoid_rig_clips.glb <rig.glb>`,
    plus the sidecar.
- **Traps:**
  - A raw `godot` command doesn't refresh the class cache; use `./run.sh import`.
  - `character_review` must hold clips with the model's `_process` off.
  - Never run `character_forge rig` without `--clips Idle`; use `rigbuild.sh`.
  - Parts with `rebind=True` are modelled in the Idle hang.
  - One Blender at a time; a cloak build needs about 4 GB.
- **Tools:** everything is in the repo under `tools/forge/preview/`: lbspreview, garmenttest,
  cloakreweight, facepreview, clipdiff, `looks.sh` and `looks/*.json`.

### 6.9 Settlements and POIs (`wip/settlements`), from its note
- **Head:** `3352cb7c`, with main `6985d356` merged at `52040d16`. The tree is clean.
- **Done:**
  - settlements read as places: streets from the roads, plots, gardens, backlands, houses by
    region and trade, beasts, smoke, fingerposts named at runtime, gates in gate posts, Skerrow's
    walls;
  - the five dead content keys;
  - `tools/unplaced.py`;
  - the POI encounter sentences;
  - the Hart of Thorns' body.

  Loose ends #18 are closed.
- **Verified on `52040d16`:**
  - test: 1664 tests, 0 failed, 0 script errors;
  - journey: 16/16;
  - smoke: PASS;
  - flow: 98/99. The one fail, "a key during the opening shows the skip prompt", was at load
    11–15 and is in the opening's code, not this branch.
- **Audits against main:**
  - `unwired.py`: 39 names, the same as main;
  - `dead_data.py`: 0 (main has 5);
  - `unplaced.py`: 40 of 239 items and 17 of 41 books.
- **Budget:** Merrowby (`budget_merrowby.json --attribute`) is at 1713 draws and **1.82 M
  primitives, over the 1.5 M budget.** Settlements are 216 draws and 0.27 M. The excess is scatter
  (0.88 M), NPCs (0.32 M) and terrain (0.29 M), so graphics or scatter needs to cut it.
- **Next:**
  1. Merge main, then run test, journey, smoke and flow.
  2. Run `tools/capture/run_plan.sh tools/capture/plans/settlements.json captures/settlements forward`
     and look at every frame. The Forward+ run was OOM-killed twice.
  3. Build the POI kinds the atlas wants (ATLAS §10). Add each to `PoiDressing.KINDS_BUILT` and to
     `poi_builders.build`, one test and one capture shot per kind. What to reuse:
     - cave: `_cave_mouth`, from Whitecut;
     - farmstead: `HouseKit` with `Settlement._wall`/`_fence`;
     - mill: the camp's millstone;
     - waystone: the standing stones;
     - market field: the Settlement stalls;
     - quarry: cliff slabs, scree and masonry, with a crane;
     - shieling: `HouseKit` with a fold;
     - vista: a bench or cairn facing downhill.
  4. Silence the `event_bus.gd` unused-signal warnings.
- **Found and not fixed:**
  - the `streets.json` cameras look at back gardens;
  - interiors have no shutters;
  - cutpurses fight rather than pick pockets;
  - terrain faults at Gosling's rear path, Fern Gully's bridges and Whitecut's wet stone;
  - the sallowjaw body;
  - an empty `pauldrons` glb (3 failing forge tests);
  - Clan Plate shows over bare arms.
- **Traps:**
  - `test_settlements`' EYE_RATCHET 74 and SHADOW_RATCHET 50 count Merrowby's meshes, and a new
    surface goes in SURFACES.
  - A headless MultiMesh has no AABB.
  - With physics interpolation on, a node moved from `_process` needs
    `PHYSICS_INTERPOLATION_MODE_OFF`.
  - `unwired.py` counts public functions that only tests call, so prefix helpers with `_`.
  - A new foe shifts `tools/tests/test_balance.py`'s region means.

## 7. How to verify, and the house rules

**Checks before any merge into main.** Run them on the merged tree, one Godot at a time:
- `./run.sh import` if any `class_name` was added;
- `./run.sh test`, which must be 0 failed, 0 script errors and 0 dead lambda captures;
- `./run.sh journey`, which must be 16/16;
- `./run.sh flow`, which must PASS all three starts, if the change touches gameplay, UI, the
  world or boot;
- `./run.sh fights`, if it touches combat;
- after the atlas lands, the quest walker.

**Look at captures**, don't just count them: `captures/flow/*.png`, and `./run.sh shots <plan>`.

**Git:**
- Merge with `git merge --no-ff <branch>` and a message that says what the merge brings.
- Stage **by name**. Never `git add -A` or `git add .`. Never commit symlinks.
- World data (`game/world/generated`, `game/terrain_data`) is committed only from the main
  checkout, after a rebuild, and only the runtime set in §5.
- Don't commit Godot's `.import` churn: re-imports rewrite hundreds of `.import` files that no
  change needs.
- End every commit message with the attribution trailer your session's instructions give: a
  `Co-Authored-By:` line and a `Claude-Session:` link to *your* session. Name no model anywhere
  else: not in code, docs, commit subjects or PR text.
- Pushes: main is `claude/blissful-volta-dg80e6`. The `wip/*` branches may be pushed and
  refreshed; the user approved that on 2026-09-23. Push nothing else without asking. Open no
  pull request unless the user asks.

**House style:**
- The project's voice is candid and measured. PROGRESS and DECISIONS entries say what was
  measured, not what was hoped.
- Commit subjects are sentences about what is now true.

## 8. The build machine, and what bites

- **Godot:**
  - Godot 4.7.2, headless, plus `xvfb-run` for anything drawn.
  - Flow and captures use **Compatibility** (`--rendering-driver opengl3`), llvmpipe here.
  - **Forward+** is Vulkan on lavapipe, and Terrain3D crashes it. `WM_TERRAIN_LODS=6` or `7`
    sometimes gets a frame out. `--terrain=fallback` draws the 8 m coarse ground instead.
- **Memory:** 15 GB is tight with several agents running.
  - A 4096 world build wants about 10 GB free.
  - With agents running, take the lock at `<scratchpad>/WORLD_BUILD.lock`. Its content is
    `<id> <epoch> <what>`. It means start no new Godot or Blender run while it exists and is
    under 45 min old.
  - Check `free -g` before every Godot run.
- **Slow frames:** under load, frames take seconds, and Godot caps physics at 8 steps a frame,
  so *game* time crawls. Anything a player times (cinematics, subtitles, prompts) must use the
  wall clock. Tests should count ticks or wall time deliberately.
- **Hung `rm`:** in background agents, `rm` of several paths, especially world symlinks, has
  twice hung for an hour on a permission prompt nobody could answer. Use `unlink <path>`, one
  path at a time.
- **Shared state across worktrees:**
  - `git stash` is shared by all worktrees. Don't use it; make a WIP commit.
  - `user://` is also shared across worktrees, so save slots and settings collide between
    parallel runs.
- **Class cache:** a new `class_name` needs `godot --headless --path game --import`, or its users
  fail to parse.
- **World symlinks:** agents once symlinked `game/world/generated` and `game/terrain_data` to a
  snapshot. Since the world is tracked, those links must not exist. Remove them with `unlink`
  before merging main.
- **Disk allowance:** the session's writable disk is a fixed allowance of about 38 GB, and `df` shows it as "Avail". On 2026-09-24 it reached 96%. Ten worktrees with their `.godot` caches take about 1.3–1.9 GB each, and each 4096 world build about 0.5 GB plus 0.15 GB for its terrain. Delete superseded builds and captures as you go. Remove a merged agent's worktree with `git worktree remove` (the user must approve it here).
- **Setup:**
  - Python 3.11+ with `pip install -r tools/requirements.txt` for the world, the interiors and
    sound;
  - Blender 4.x only for `./run.sh assets` and the clip bakes;
  - `./run.sh godot` says which Godot the scripts will use.

## 9. Not yet assigned (after the urgent list)

- A Godot audio-mixer race: bus details are freed while mixing. It's guarded in-game
  (`systems/audio/audio_guard.gd`), and the repro is `tools/debug/stall_mixer.py` with
  `tools/debug/audio_race_check.sh`. Report it upstream only if the user wants it reported.
- Interiors, the Merrowby perf budget and the POI dressing need a re-check once the atlas world
  moves places.
- The music has never been listened to by a person, and motion has never been seen in real time
  on a real GPU. Both need the user.
