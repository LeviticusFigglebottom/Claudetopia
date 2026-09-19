# systems/quests — the journal and the job boards

| File | What it is |
|---|---|
| `quest_log.gd` | Every quest started: stage, objective progress, journal, markers, rewards. Group `quest_log`, save section `quests`. |
| `radiant.gd` | `RadiantGenerator`: turns the six radiant templates into real quests with region-appropriate targets and written text. |
| `quest_conditions.gd` | `QuestConditions`: the glue between quest data and the dialogue condition vocabulary (`requires`, `hidden_until`, `fails_if`, `repeatable`). |

## Data

`content/packs/core/quests/*.json` — `quest` defs (CONTRACTS §7):

```json
{"id", "name", "layer": "main|faction|side|radiant", "giver?", "requires?": [conds],
 "repeatable?": false,
 "stages": [{"id", "journal", "auto?": false, "manual_advance?": false, "marker?": {"place_id", "radius"},
             "objectives": [{"type", "target", "count?", "text?", "optional?", "hidden?",
                             "place?", "item?", "radius?", "options?", "effects_by_option?", "on_complete?"}],
             "on_enter?": [effects], "on_complete?": [effects]}],
 "rewards": {"marks?", "renown?", "morality?", "items?": [[id, n]], "rep?": [[faction, n]], "deed?", "effects?"}}
```

Objective types and what closes them:

| type | target | closed by |
|---|---|---|
| `talk` | npc id | `EventBus.dialogue_ended` |
| `reach` | place or poi id | the position provider (`radius`, default 45 m) or `place_discovered` |
| `kill` | enemy id, `""`/`any`, or `tag:<tag>` | `entity_killed` |
| `collect` | item id | `item_acquired`, and what is already in the pack when the stage opens |
| `deliver` | npc id (+`item`) | a dialogue effect (`complete_objective`) or `deliver()` |
| `escort` | npc id (+`place`) | `escort_arrived` |
| `choice` | option id (+`options`, `effects_by_option`) | `choose()` |
| `use_item` | item id | `item_used` |
| `rest_at` | hearthstone/place id | `hearthstone_rested` |
| `read_book` | book id | `book_opened` |

A stage closes when every non-optional objective is done (unless `manual_advance`), runs its
`on_complete`, and the next stage's `on_enter` fires. A stage with no objectives waits for a
dialogue to move it on unless it is marked `auto`. Finishing the last stage completes the quest
and grants `rewards`, including a deed by layer (`quest_complete_main/faction/side/radiant`).

**Markers are areas, never pins**: `{place_id | region_id, radius, quest_id, text}`, radius 140 m
for a place and 600 m for a region (DESIGN §5.10).

### Radiant templates

`content/packs/core/quests/radiant_templates.json` holds the six: bounty, hunt, deliver, clear,
escort, fetch. A template is a quest def carrying a `template` block (pools, count range, reward
formula and text variants); its `stages` are the shape, and every `{token}` is filled — ID fields
with the chosen definition's id, text fields with its name — so generated journals never show a
placeholder. Target pools: `enemy` (region ecology, or an enemy def naming the region, narrowed
by archetype/tag), `place`, `poi`, `npc`, `item` (by tag, falling back to category). A pool with
no content yet makes the generator skip that template and log it; it never invents an id.

Rewards scale with the region's `danger`, the count, and the distance from the board.
Generation is deterministic for a seed; boards derive theirs from region, board and day, so the
same board offers the same work all day (`DEFAULT_COOLDOWN_HOURS` 48).

## Signals

Emits `EventBus.quest_started(id)`, `quest_stage_changed(id, stage)`, `quest_completed(id, outcome)`.
Consumes `entity_killed`, `item_acquired`, `item_used`, `place_discovered`, `dialogue_ended`,
`hearthstone_rested`, `book_opened`, `escort_arrived`.

## Save section

`quests`: `{quests: {id: {stage, stage_id, counts, journal, state, outcome, choices, runtime}},
radiant: {boards: {...}}}`. Generated quests keep their whole definition under `runtime`, so a
loaded game still knows what the board asked for. Board cooldowns ride in the same section.

## Public API

```gdscript
Social.quests.start(quest_id) -> bool          # honours the def's `requires`
Social.quests.set_stage(quest_id, stage)       # index or stage id
Social.quests.advance(quest_id)
Social.quests.complete(quest_id, outcome := "") / fail(quest_id, reason) / abandon(quest_id)
Social.quests.choose(quest_id, option) / complete_objective(quest_id, key) / deliver(quest_id, npc_id)
Social.quests.is_active/is_completed/is_failed/is_known(quest_id) -> bool
Social.quests.stage_of/stage_id_of/outcome_of(quest_id)
Social.quests.active_quests() / completed_quests() / failed_quests() -> Array[Dictionary]
Social.quests.entry(quest_id) -> {id, name, layer, state, stage, stage_id, journal, objectives, outcome, giver}
Social.quests.objectives_of(quest_id) -> [{text, type, target, count, needed, done, optional}]
Social.quests.active_markers() -> [{place_id|region_id, radius, quest_id, text}]
Social.quests.register_runtime(def) -> bool    # a generated or scripted quest
Social.quests.check_reach(at := null)          # or set position_provider (needs position() -> Vector3)

Social.board_jobs(board_place_id, region_id := "", count := 3) -> Array[Dictionary]
Social.take_quest(quest_id) -> bool
Social.radiant.generate(region_id, count, board_place := "", seed := 0) -> Array[Dictionary]
Social.radiant.generate_for_board(board_id, region_id, count, cooldown_hours := 48.0)
Social.radiant.board_cooldown_remaining(board_id) -> float
QuestConditions.can_start(def, ctx, log) / is_offerable(...) / offers_of(npc_id, ctx, log)
```

## Tests

`tests/unit/test_quests.gd` (30): trackers per objective type, markers, the authored Wardens
quest end to end (both endings), radiant determinism, every template generating once the enemy
and item pools are stood in, rewards by danger, and both save paths.
