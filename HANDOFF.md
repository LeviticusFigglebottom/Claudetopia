# Wickmere: handoff

**Read this first.** It is the state of the whole project, and how to carry on from it with
nothing but this repository. It was written by the coordinating Claude session that ran the work
from 2026-09-21 to 2026-09-23. It is refreshed at every hourly check-in while that session runs.
The **Last refreshed** line below says when. `PROGRESS.md` (the long, dated record),
`DECISIONS.md`, `DESIGN.md`, `WORLD_BIBLE.md`, `ARCHITECTURE.md` and `docs/CONTRACTS.md` stay the
detailed references. This file is the map.

**Last refreshed:** 2026-09-25, by the new coordinating session (see §0). Main is still
`claude/blissful-volta-dg80e6`, now at the same head as this session's branch
`claude/gifted-brahmagupta-29u39r`. Both are pushed together from here on.
**Batch 4 is in main (7ade0ba1, 2026-09-25):** both branches are at the same head again.

---

## 0. The new coordinating session (from 2026-09-24, late evening)

**2026-09-25 21:00 UTC.** The world is rebuilt as w4096d (3c1a7668): foes along the roads,
weapons in the country, the regrown trees, batch 5's terrain; the start's tests pass on it (22/22)
and the built-world tests pass (the one failure was the road test's own measuring, 856e0320).
Merged since: the rider's clips, the giant oak on the ground, the interiors' plots, wave 5's pads
(for the next build). **A Windows build** is made by `.github/workflows/windows-build.yml` every
four hours when main has moved (or by hand) and published as the `nightly` release: about six
minutes a run with the import cache warm, a 692 MB zip. Next world build waits on the world
builder's pads and ground review and settlements' arrival points.

**2026-09-25 ~18:30 UTC: build first, one check at the end (the user's).** The full checks are
suspended: agents run only targeted tests and look at their captures, and finished work merges
into main straight away, checked by an import (`docs/POLICY_NOW.md`). One full main check (suite,
journey, flow, the quest walker) runs after every workflow is complete. The last full suite, on
f769b592, passed 1974 of 1974; journey, flow and the walker (77/77) passed on the code before
settlements' weir fix and the opening's last three commits. Merged since without the full checks
(539dee4b): the cameras' frame check, player-feel (attack clips, swimming), characters (legs through
clothes, head UVs), interiors (colliding furniture, re-planned houses), the painted look (the Toll,
the start's light and ash), water's sea edge, settlements, the debug fixes, the world builder's and
cartographer's batch-5 sources (foes on the roads, weapons, erosion, the Stair Head's stray ledges)
and the title vista. The batch-5 sources reach the game at the next 4096 build, after tree forge's
regrown trees. New since the last refresh: the user's fighting-style intros (DECISIONS, task for
after the fixes), the quest tracker (wip/quest-tracker), and the starter-area clean-up from the
user's screenshot (wip/opening).

The session that wrote everything below ended. A new coordinator picked the project up from this
file and GitHub alone, as §2 says a new session must.

- **Branches.** Main stays `claude/blissful-volta-dg80e6`. This session's own branch,
  `claude/gifted-brahmagupta-29u39r`, is kept at the same head, and every landing is pushed to
  both. Each area works on `wip/<area>` as before, and the coordinator pushes every `wip/*` head
  hourly, so a container restart loses at most an hour.
- **Agents.** Eleven new agents, one per area, each in `.claude/worktrees/<area>` on
  `wip/<area>`, with main (dc2a749a) merged in cleanly before they started. The areas and their
  queues are the ones in §6. atlas-readiness is done and has no agent. The shared rules they work
  under (memory checks before any Godot run, `WORLD_BUILD.lock` and a new `BLENDER.lock`,
  commit locally and never push, stage by name, no world data) are in `docs/AGENT_RULES.md`,
  which restates §7 and §8 for an agent. Give it to every new agent.
- **Lost with the old container.** The cartographer's gap map ("81 of 120 km of road thin") and
  its first wave of wayside finds were never committed. The gap map is rebuilt as a committed tool,
  `tools/world/atlas/gap_map.py` with `tools/world/tests/test_gap_map.py` (wip/atlas-quests
  da9b5513). It counts every place and POI, including farmsteads, mills, caves and finds marked
  `"wayside": true`. Passing a thing means coming within 60 m of it, and a gap over 300 m (a minute
  at a jog) is thin. On the batch-3 world: **65.4 of 120.5 km of built road is thin**, 100 gaps,
  the longest 1680 m (Merrowhithe to the Skarl Bridge), and 2.3 of 43.1 km² of walkable ground is
  more than 300 m from anything. The 120.5 km is the 83 atlas roads as built (116.2 km,
  meandered from 80 km as drawn) plus 52 streets. The old 81 comes back under a stricter reading
  (50 m / 200 m). The worst runs are the Skerrow dales, then the Wold and the Greatwood.
- **The wayside finds, waves 1–4** (wip/atlas-quests c3777208; last content a8149f4d): **120 finds**,
  all of kinds already built, each a pace off a road with a reason tied to its place, 108 notes in
  the region's own voice and 12 objects, 16 of them standing foes up. Measured by the gap map (the
  one-minute rule, on the tracked world):

  | | thin road of 120.5 km | gaps > 300 m | longest | empty ground |
  |---|---|---|---|---|
  | before | 65.4 km | 100 | 1680 m | 2.3 km² |
  | wave 1 (Skerrow, North Shore) | 46.3 | 89 | 1360 | 2.0 |
  | wave 2 (the Briarwold) | 32.9 | 71 | 1248 | 1.9 |
  | wave 3 (Hearthvale, the Mere, Sedgemire) | 20.5 | 45 | 1248 | 1.7 |
  | wave 4 (Cinderlea, a light touch) | 18.0 | 44 | 925 | 1.7 |

  By region, Skerrow 19.6 → 7.9 km, the Briarwold 15.3 → 1.7, Brightwater 10.1 → 0.3, Cinderlea
  9.8 → 7.4, Hearthvale 7.1 → 0.3, Sedgemire 3.4 → 0.3. The atlas now has 440 locations, 9.3 per
  walkable km², the nearest a mean 159 m away (was 320, 6.8, 180 m). What stays red is the dale
  switchbacks, where no ground takes a 14 m pad, and the Ash Heath and the Ashgrid, left quiet on
  purpose. The next wave is off the road, in the fold, cairn and tally_post kinds settlements is
  building. `PoiDressing` places on the land as it is and does not level, so **the finds land in
  main with the batch-4 world build** and its 14 m wayside pads, not before.
- **The quest walker passes with the wayside finds in** (wip/atlas-quests 6f8ab0e9, waves 1–4 on
  main): 77 of 77 quests, 228 of 228 walks, 0 world notes, 0 logged errors (31 min, tracked world).
  **Wave 5 is planned off the road** (e9ceb508; `gap_map.py --switchbacks` and `--offroad`,
  64fff3f5): 29 sites, each visible from a road 30–320 m away (eye 1.65 m, target 2.2 m, the line
  marched over the built heights). They are 14 cairns, 7 folds, 4 tally_posts, 3 wells, 2 graves and
  2 lantern_posts. One cairn is visible from the Stair Head road. Estimated effect: road 18.0 →
  14.1 km thin, and empty country 1.7 → 1.04 km². It is emitted as settlements' kinds land.
- **The atlas debts in §6.1–6.3 are mostly already paid**, measured by the cartographer on the
  tracked batch-3 world: the Stair Head → Choir road is 542 m (inside 300–650); the Heron Watch is
  29 m off the water with a dry pad; the Blackgill ends in the Blackgill Pot; the Thornmarch crest
  wanders between x 3925 and 4030; Wat's and Jory's schedules walk round the water (9d15f9c9). Of
  the sightlines, on the tracked 1024 runtime heights only 4 of 199 are refused, all marginal
  (3.9–5.7 m), and all 21 of the old refusals over 25 m are gone; the batch-4 4096 build's
  `test_sightlines` decides the four. §6.1–6.3 below are older than this.
- **Landed in main (a998cd3e): 1024 previews draw the whole world in the engine.** Before it,
  Terrain3D imported and drew every build at 2 m spacing and on a 1024-sample region grid from the
  origin, so a 1024 build (8 m texels) went in as one region and the places stood over fog; every
  in-engine judgement of a preview was on the wrong ground. The terrain import and the game now
  take the manifest's `spacing_m`, and the import pads the maps onto Terrain3D's region grid and
  fails if the centre reads NaN. A no-op for the 4096 world (the world and terrain test filters
  pass, 85 and 16, 0 failed). An agent's worktree needs main merged before `use_build.sh` draws
  a preview right.
- **Landed in main (df2a602a): settlements' six commits (0d422f15..a29440f9).** Cliff ledges are
  crag, with their LOD ladders (`tools/tests/test_ledge_lod.py`); caves sit backed into cliffs; farm
  keepers stand clear of their doors; stone circles stand whole; a fall's face is dressed as the
  front of a hill (the runtime stopgap until the world builder's carved step lands with batch 4).
  Verified on settlements' merged tree, which differs from main's only in two docs files: the suite
  1894 with 1 failure (`test_talk_to_the_warden`, a frame-counted wait that fails under load and
  passes alone; the opening area is making it wall-clock), journey 16/16, smoke PASS, and flow
  PASS on all three starts.
- **The gate's heavy-run cap is now 4** (was 5). At 5 to 6 heavy runs the load average still sat
  at 16 on 4 cores. Fewer runs at once finish sooner each, and throughput stays about the same.
- **Batch 4 landed (7ade0ba1):** the world rebuilt from main as w4096c. It has:
  - falls that step and are falls on their rivers (the terraced tiers too);
  - rock seated and in groups;
  - trees set into the ground at their whole foot;
  - roads planted field by field, with rails, hedges and walls anchored and on the ground;
  - crags that step back and dip;
  - the 120 wayside finds on 14 m pads, and nothing in the water;
  - graphics' solid scatter (trees, rocks, walls, hedges, fences, wayside rails, posts and gates);
  - settlements' fall faces reading `fall`;
  - the Hearth respawn fix, a user:// per checkout, and the world-services fix.
  Verified on main: suite 1920/0, journey 16/16, flow on all three starts, fights 66/66, quest walker
  77/77 quests and 228/228 walks, and the falls and tree-seating BuiltWorld checks. The one failure on
  the way (the Choir's colossus test, only in the full suite) was eight services outliving their world
  under the test runner (667c4c80); in the game the World is the scene, so play was never affected.
- **Known dependency warning:** Terrain3D 1.0.2's GDExtension calls the deprecated
  instance_reset_physics_interpolation(), reported at world.gd:200 (add_child). It is harmless, once a
  session; the fix is a Terrain3D build against 4.7's API.
- **Landing policy (the user, 2026-09-25):** verified work lands as soon as it is verified, one
  hand-back at a time, unless it truly depends on something else landing first (world data waits
  for its rebuild; a rig change waits for the rig it builds on). No holding finished work for a batch.
  Order right now: the colossus-test fix with batch 4's world, then the opening's work and the
  painted look's opening-area pass, then everything else in the order it is verified. New: the title
  screen gets a slow panning cinematic across several regions (graphics).
- **Playtest 6 (the user, on main's batch-3 world, 2026-09-25), and who has each item:**
  - No collision on rocks, trees or fences: graphics (the scatter physics ring, not yet landed; now
    also `wayside.gd`'s signposts, gates, drystone and rail runs, which build no bodies at all).
  - Floating trees, their root flares above the ground: world builder (seat trees as rock is seated).
  - Road fences randomly placed, missing or clipping: world builder (roadside and wayside runs).
  - The beginning neither compelling nor guided: opening. The compass shows every discovered place
    at any range (`hud.gd::_rebuild_markers`) and never a town from afar. The user asks for a
    Skyrim-like rule, which overrides DESIGN §5.16: per-kind ranges, undiscovered places faint once
    near, and a cap. Opening again.
  - Dialogue: the player walks during a conversation, and W/S don't choose. Opening.
  - Water not meeting its shores (a slab edge): water. No swimming (there is no swim state; the
    player walks the lake bed): player-feel, after the attack clips.
  - Cliff rocks flat, white and out of place: painted look (colour and grounding) and world builder
    (a15faadd's broken, dipping courses).
  - Sheep "disemboweled": the static prop's legs stop 3 cm short of a body with no underside. The
    tree forge rebuilds sheep on the shared quadruped rig, after the horse.
  - Interiors needing a full placement redesign (clipping, blocked doorways, no furniture
    collision): **a new interiors area** (`wip/interiors`).
  - No foes or weapons beyond the start. The data has 534 cell foes and 233 POI foes in all six
    regions, more away from the start, but spawns are cleared 14 m from roads, 120–420 m round
    settlements and along the start's roads. No weapon lies anywhere in the open world. Debug
    measures the runtime spawns; the cartographer adds road encounters and weapon finds.
- **Batch 4 in flight:** a first 4096 (w4096) showed the two terraced falls, the Three Sisters and
  the Blackgill, missing from rivers.json. Every single-face fall passed. The fix (916235a4 → main
  d401b682) is in a second 4096 (w4096b). The 4096 peaks at 6.28 GB in the textures stage: the rows
  saving comes after the peak, so it isn't the 3.2–3.6 estimated.
- **Commit identity (trap).** This container's git config carried the machine owner's identity,
  and worktrees share it, so commits came out under that email and GitHub shows them as
  unverified. The repo's config is now `Claude <noreply@anthropic.com>` for every worktree. About
  thirty earlier agent commits on the `wip/*` branches still carry the old identity; they are
  re-authored when their branch lands, never rewritten under a working agent.
- **Also recovered.** `claude/admiring-faraday-74m7pe` holds one commit that never reached main:
  125a8c4c, "a capture that photographs an empty county now says so and fails". The capture runner
  on main still reports an unstreamed frame as healthy. The debug area is porting the guard onto
  today's runner, and that branch can be retired once it lands.
- **Branches to retire.** `wip/atlas-merge`, `wip/atlas-readiness`, `wip/batch2`, `wip/batch3`,
  `wip/debug-errors` and `wip/water` are all in main (the last two as patch-equivalent commits;
  `wip/water` was replaced by `wip/water-2`). This environment's git proxy refuses branch
  deletion with HTTP 403, so they are still on GitHub. They can be deleted from the GitHub UI
  at no loss.
- **Stale files, found and removed.** A checkout that has held an older world keeps that world's
  `heights.r32`, `control.u32`, `color.rgba8` and the rest in `game/world/generated/`. They are
  ignored by git and ignored by the game, which reads only the manifest's `runtime` set. An
  offline tool that reads `heights.r32` from there, though, measures the wrong world without
  saying so. After any world change, `git status --ignored game/world/generated` should list
  nothing.
- **Decisions made so far.**
  - The starter horse is the Wardens' spare cob, given by Wren at Merrowby when the_toll_hums
    reaches "arrive". It is not given at the Stair Head, which keeps the_cart and the ash on foot.
  - Every hoofed animal uses one rig, `WM_Quadruped_v1`, with gaits from one footfall generator.
    Wildlife builds deer on it after the horse, and birds and fish need no rig.
  - Riding lives in its own nodes and uses named hook points in `player.gd`, `camera_rig.gd` and
    Actor. Player-feel makes the rider's seat clip.
  - Painted rocks and the builder's rock seating keep CONTRACTS §6 row order. The builder
    doesn't write the tint alpha, which the painted look uses to find the ground line, and pivots
    stay at the foot.


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
| `claude/blissful-volta-dg80e6` | **main** | `f0af2989` | **Batch 3 is in main**: the world rebuilt from atlas a2775553 (3cd8d984; 5.55 M scatter instances), the water's falls, rivers, lakes and sea, every leafy tree regrown whole with birch and hazel, the farmsteads, mills and caves with their people, the countryside and finished shores, LandmarkLod and View distance, the painted look's clouds, dead trees, ash field and skies, the Wardens' Watch, the ewe and flock, weapons' butt end and blended hand-over, a killed foe that stays down (c88ebb22). Verified on the rebuilt world: import check, journey 16/16, flow PASS with 0 errors, the quest walker 198+ walks with 0 failures; the suite's loop-flags crash (7a115835) and the new farms' test_poi_people failures (6c6ddf63, 9fa10881) fixed; a confirming full suite follows. **Landing is continuous.** Since batch 3: the Warden stays through a cell reload (5896cc79); no freed stain or foe is touched (00ceb432). Playtest 5 (the user, on batch 3): trees and fences have no collision (graphics: a streamed physics ring); running legs clip the clothes (characters); rocks jut from slopes (world-builder: seating, tilt, clusters; painted look: a painted rock pass); the world still feels empty between places (cartographer: gap map done, 81 of 120 km of road thin, wave 1 of ~200 wayside finds; world-builder: roadside planting; water agent: wildlife); a starter horse is wanted (tree-forge: horses, starter horse first; flying later). From the batch-3 shots: falls stand as towers (world-builder: carve a real step at each fall; settlements: a runtime brow stopgap a29440f9); a cart stands in a Briarwold river (no props in water). Import cache: seeding from main's .godot/imported needs a touch of the branch's changed files first (Godot rechecks only on mtime). |
| `wip/world-builder` | World builder: terrain, rivers, roads and cover from the atlas | `ee6badc6` | Crags and sea cliffs built of the forge's cliff ledges (26,893 at 1024, builds in 458 s at 3.1 GB). Joins batch 3's rebuild if its shots hold by 18:45, otherwise batch 4. |
| `wip/atlas-quests` | The drawn atlas (297 locations) plus 40 new side quests and quest plumbing | `e0d8eccc` | The roster fix is in batch 3. Now: the walker counts the thank-yous; after batch 3's rebuild, the roads walked again. |
| `wip/atlas-readiness` | The game follows places, not coordinates, on the atlas world | `2a3be507` | **Done and in main.** |
| `wip/opening` | The intro cinematic, the start, and its loose ends | `4d443c34` | In batch 3. Now: the re-framed cinematic shots (the Spire, the Nave, the Hand, the_choir). |
| `wip/player-feel` | Movement, gaits, animation feel, combat clips | `6acc5748` | In batch 3. Now: the film of the foes' cold sweeps, the spear chain and the backstab. It owns the rig's clips; characters owns the meshes and the Idle. |
| `wip/painted-look` | The painted art direction: light, fog, sky, water, grade | `3f583764` | Its batch 3 work is in. The start view (3f583764) and the ash field rework lead batch 4. |
| `wip/graphics-settings` | The Graphics tab, presets, tree LODs, budgets, the horizon | `966bde5c` | In batch 3 through 5554cbd5. Now: the Hushline curtain over the Stair Head's crest, night lights checked from open views, the Thornmarch reshoot. |
| `wip/characters` | Bodies, faces, hair, clothing, the Naming screen | `9a486188` | Third pass in batch 3. Now: faces, gloves, the cloak and the preset seed fix (2f36e384), for batch 4. |
| `wip/settlements` | Settlements as streets, POI people and dressing, quest plumbing | `a29440f9` | Crag ledges, caves in cliffs and the fall-face dressing are in main (df2a602a). Now: the atlas POI kinds (cairn, tally_post, grave, gibbet, fold, well, lantern_post, the cart wreck; then hut, crossroads, peat_cut, beacon). fold, cairn and tally_post come first, because the cartographer's off-road wave needs them. |
| `wip/water-2` | Water: falls, rivers, lakes, the sea | `d7516ded` | In batch 3 (its history was rewritten to add trailers, hence the new wip name). |
| `wip/tree-forge` | Every tree species regrown as whole wood | `abec8455` | 54 grown trees, LOD1s and impostors, birch and hazel; merging batch 3. New variants need a rebuild's scatter to be placed. |
| `wip/debug-errors-2` | ErrorLog, import_check, warnings, the walking flow | `fcaf50d8` | ErrorLog and import_check are in batch 3. Now: the wander that covers ground and a teleport tour (batch 4). |

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
| "Talking to Wren doesn't do anything": the first objective is blocked | `wip/opening` | **Fixed in main (36d83f56).** Pressing interact on any NPC now starts the conversation through `Social.talk`, and a goodbye ends it. The flow walks to Wren on W, sees "[E] Talk to Wren Tallow", talks her down to her goodbye, and the Naming moves from wake to the_choir. Still to do: the prompt stays up under the conversation (fix coming), and there is no conversation camera (design item). |
| "Walking up any incline seems impossible" | `wip/player-feel` | **Fixed in main (9263fc11).** `snap_to_terrain` stands down on a floor collider and never pulls a rising body down. Walking, jogging and sprinting climb 5–40° at full pace, and 50° is a wall (`test_walking_uphill`). |
| "Jump doesn't work" | `wip/player-feel` | **Fixed in main (9263fc11).** The body leaves the ground 0.12 s after the press and rises about 1.1 m. Jump_Start → Jump_Loop → Jump_Land. |
| "The ground is black" | `wip/painted-look` | **Fixed in main (d5c51ea2)** with a low-sun fill for Cinderlea, a softer grade, and the ash and fused stone relit. `test_ground_albedo` guards it. Console checks: `terrain grey`, `look`, `look low_sun_fill 6`, `look reset`. The original diagnosis follows: The `ash_soil` slot draws at linear albedo about 0.008: texture mean 0.017 × `albedo_color` 0.45, charcoal colours in `tools/world/gen_terrain_textures.py:432`. `fused_stone` is 0.020. Grass is 0.05–0.1. The Stair Head's ground is 48% ash. Fix in progress: raise both to about 0.035–0.045 (the `value` column in `tools_gd/import_terrain.gd` SLOTS, and `albedo_color` in `world/terrain_assets.tres`), with a unit test against any slot under 0.02. Measure with `python3 tools/world/ground_albedo.py --at -1922,3708 --regions --floor 0.02`. |
| "Inverted tent edges" at the camp | `wip/opening` | **Fixed in main (36d83f56).** The forge's tent sides were tilted 90° off, and every camp's tents stood side-on to its fire. Both tent models are rebuilt as A-frames with their mouths in front (`test_camp_tents`). The camp also gets a pot, smoke, the Wardens' gear and crows. |
| "Attacking animations still need revising" | `wip/player-feel` | After slopes and jump: an audit of the attack clips, keeping DESIGN §5.3 timing. |
| "A little sparse" | `wip/atlas-*`, `wip/opening` | The atlas more than doubles the locations and adds 40 quests. Camp life is on the opening's list. |
| The debugger lists 239 entries | unassigned | Mostly GDScript warnings: `event_bus.gd` signals "declared but never used". Silence them properly so real errors stand out. |

### Playtest 4 (2026-09-24, on wip/batch2): being fixed in batch 3
- The clouds race when the wind changes: TIME×speed in painted_sky; fixed by an accumulated cloud_drift (painted look 783727b3).
- Fence posts and rails were misaligned (settlements 7f6a3f39, plus roadside.py at the next build).
- The start spires fade near: LOD lines too short for landmarks (graphics LandmarkLod).
- A dull black start (painted look ash field 946a888a).
- Distant POIs and terrain (graphics View distance).
- Sparse land between POIs (world-builder countryside; cartographer farmsteads, mills, caves).
- Broken trees: trim_to_budget fragments wood; regrowing every species (tree-forge).
- 228 debugger errors: not reproduced headless or windowed on llvmpipe; waiting on the user's error lines (agent a2d712).

- **User logs (playtest 4):** 471 of 511 events were stale import-cache "invalid UID" warnings, plus missing renamed textures (shirt, trousers, moustache, the Skerrow pine impostors). Fix for the user: delete game/.godot and reopen. The root fix (the forge changes the GLB .import when textures change), an OptionButton index bug, physics-interpolation warnings and the ErrorLog exporter are with agent a2d712. Logs are at scratchpad/userlogs.
- **New agents:** water (all water, from rivers.json falls) and tree-forge (every species regrown whole, in the reused worktree agent-a4733a4…, branch tree-forge).

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
- **Done (d5c51ea2):** the black ground, diagnosed in §4. The fix landed, plus a minimum-albedo test and
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
