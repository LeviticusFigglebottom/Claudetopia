# systems/quests — the journal and the job boards

| File | What it is |
|---|---|
| `quest_log.gd` | Every quest started: stage, objective progress, journal, markers, rewards. Group `quest_log`, save section `quests`. |
| `radiant.gd` | `RadiantGenerator`: turns the six radiant templates into real quests with region-appropriate targets and written text. |
| `quest_conditions.gd` | `QuestConditions`: the glue between quest data and the dialogue condition vocabulary (`requires`, `hidden_until`, `fails_if`, `repeatable`). |
| `quest_routes.gd` | `QuestRoutes`: which deliveries and decisions the pack's dialogue closes by hand, and who hosts the ones nobody wrote a line for. |
| `item_sources.gd` | `ItemSources`: where a player can get an item — the story hands it over, a shopkeeper sells it, a loot table may roll it, a house keeps the book on a shelf. |
| `choice_point.gd` | `ChoicePoint`: a decision with nobody left to put it to you (the note at the Cantor's Seat); a cold light that puts the open options when walked up to. |
| `quest_walk.gd` | `QuestWalk`: every objective of every quest, and what in the built game closes it — the person and where they live, the enemy and where it stands, the item and how it is got — or why nothing can; the same for what starts each quest and for every target a job board could name. |
| `kill_places.gd` | `KillPlaces`: where a kill happened (the interior its body lay in, or the ground it fell on), for kill objectives that say `where` or `region`. |
| `quest_foes.gd` | `QuestFoes`: stands up the foes a stage sends you to fight in the open, once you are near: the shortfall, or its own group; a world service installed by `GameServices`. |

## Data

`content/packs/core/quests/*.json` — `quest` defs (CONTRACTS §7):

```json
{"id", "name", "layer": "main|faction|side|radiant", "giver?", "offer?", "requires?": [conds],
 "repeatable?": false,
 "stages": [{"id", "journal", "auto?": false, "manual_advance?": false, "marker?": {"place_id", "radius"},
             "objectives": [{"type", "target", "count?", "text?", "optional?", "hidden?",
                             "place?", "item?", "radius?", "options?", "effects_by_option?", "on_complete?",
                             "where?", "spot?", "owner?", "with?", "marker?", "hidden_why?"}],
             "on_enter?": [effects], "on_complete?": [effects]}],
 "rewards": {"marks?", "renown?", "morality?", "items?": [[id, n]], "rep?": [[faction, n]], "deed?", "effects?"}}
```

Objective types and what closes them:

| type | target | closed by |
|---|---|---|
| `talk` | npc id (+`topic?`) | `EventBus.dialogue_ended`; with a `topic` (a node of the person's dialogue), only a conversation that reaches that line (`dialogue_node_entered`) |
| `reach` | place or poi id | the position provider (`radius`, default 45 m) or `place_discovered` |
| `kill` | enemy id, `""`/`any`, or `tag:<tag>` (+`where`, `radius?`, `region?`, `when?`, `stand?`) | `entity_killed` where the objective says (`KillPlaces`) |
| `collect` | item id | `item_acquired`, and what is already in the pack when the stage opens |
| `deliver` | npc id (+`item`) | a dialogue effect (`complete_objective`); where no author wrote one, finishing a conversation with the person while carrying the item hands it over (`QuestRoutes`) |
| `escort` | npc id (+`place`, `radius?`, `requires?`) | `escort_arrived`, said by `Escorts` (systems/npc_life) when the person walking with you gets there |
| `choice` | option id (+`options`, `effects_by_option`, `with?`) | `choose()`: an authored `quest_choice` button, or, where nobody wrote one, the open options offered at the host's hub |
| `use_item` | item id | `item_used`; a `tool` is used without being used up |
| `rest_at` | hearthstone/place id | `hearthstone_rested` |
| `read_book` | book id (+`in_place?`) | `book_opened`: read from the bag, off a shelf, or where it lies; with `in_place`, the book itself is laid, fixed, at the objective's `where` and read there |

**Where the things lie.** A `collect` or `use_item` objective's item, or the item that reads a
`read_book` objective's book, is put in the world by `QuestItems` (world/pois/quest_items.gd) unless
the story already hands it over or a shopkeeper sells it: at the objective's `where` (a place, a
point of interest or an interior), else the item's own `where`, else the place the same stage
sends you to (`reach`). A `read_book` that says `in_place` gets the book itself instead of its copy:
a board hung inside a tower door, a slate at a cairn, read where it lies and never taken. `spot` names a marker in the dressing, a chamber of a deep place, or a room
of a house; `owner` makes taking it theft (in a house the resident owns it). A `choice` whose
`with` names a place rather than a person gets a `ChoicePoint` there. What has been taken is the
`quest_items` save section. `tests/unit/test_quest_items.gd` pins where each one lies.

**Who starts a quest.** The opening, or a `start_quest` effect in a line, a stage or a reward;
and where none of those does, its `giver`, who offers it at their hub once its `requires` hold
(`QuestLog.giver_offers`; the line is the quest's `offer`, else its name). A giver used to start
nothing, and a quest written with a giver and no line of its own could never begin
(`tests/unit/test_quest_givers.gd`).

**Where a fight is.** A kill counts only where its objective says (`KillPlaces`): `where` is an
interior (the body lay in its pocket) or a place or point of interest (in the open, within
`radius`, 140 m unless it says); a job board's hunt says its `region`. The body that died is asked,
then the killer, then the player. Every authored kill objective says where
(`tests/unit/test_kill_places.gd`), because counting a kill anywhere let the Undercroft's
strongroom close on the Long Stride's bravos. Where a stage sends you to fight in the open,
`QuestFoes` stands up what it asks for once you are near: the shortfall after what already stands
there, or with `stand: "own"` the objective's own group whatever else is there (the Cold Fire's
newer six); `when` keeps them to an hour window (`night`, `dawn`, ... as `PoiEncounters`). A boss
is never stood up; a boss already put down when its stage opens closes the objective at once. A
deep place stands what its meta's encounters say, and the walk checks it holds enough.

**Naming a stage.** Content names a stage by its id or by its *number*, and numbers count from
one: `{"quest_at": ["core:quest/the_naming", 1]}` is the waking, the first stage.
`QuestLog.stage_index()` is the one translation from what content wrote to an index; `stage_of()`
answers that index (from nought) and is never what content writes. The code used to read the
numbers as indices, so the pack's forty-eight numbered references all landed a stage late;
`tests/unit/test_quest_stage_references.gd` pins every one of them to the stage id its writer
meant, and fails on a new number until somebody says what it means.

A stage's `on_complete` may send the quest to another stage (a branch rejoining the line), and
when it does that is where the quest goes: `advance()` no longer walks on into the next stage
in the list over the top of it.

An option is written either as a plain id, with its consequences in the objective's
`effects_by_option`, or as an object `{id, text, conditions?, effects?}` carrying its own. Both
are answered by `choose()`, which refuses an option whose `conditions` are unmet; a branching
quest names the stage it jumps to in the option's own effects, by stage id.
`open_options(quest_id)` lists the options a dialogue should actually offer.

A stage closes when every non-optional objective is done (unless `manual_advance`), runs its
`on_complete`, and the next stage's `on_enter` fires. A stage with no objectives waits for a
dialogue to move it on unless it is marked `auto`. Finishing the last stage completes the quest
and grants `rewards`, including a deed by layer (`quest_complete_main/faction/side/radiant`).

**Markers** (`active_markers`) are areas: `{place_id | region_id, radius, quest_id, text}`, radius
140 m for a place and 600 m for a region; the chart washes them over places already found.

**Waymarks** (`waymarks.gd`, DESIGN §5.16): the *tracked* quest (`tracked_quest()`, `track(id)`,
`tracked_changed`, saved as `tracked`) has its current objectives pointed at on the compass, the
chart and the HUD's tracker. `Waymarks.anchor(quest, stage, objective)` says from the content what
each is about (a place, a person, foes where the story puts them, a thing where it lies, an
interior), the objective's `marker` overriding; `Waymarks.locate(anchor, from, inside)` says where
that is in the live world now, and the door between when it is in another space.
`tracked_objectives()` hands the HUD both. An objective written `"hidden": true` with a
`"hidden_why"` is still listed in the journal and is not pointed at; `tests/unit/test_waymarks.gd`
fails on any other objective that points nowhere.

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

**How a board reaches this.** The economy stream's `JobBoard` asks `Jobs.board_offers()`, which
asks `Social.board_jobs()` — the façade, because `QuestLog` has no `generate()`; it *holds* the
generator. `JobBoard.take()` then accepts through `Social.take_quest()`. Both halves used to be
unreachable: `board_offers` looked for a `generate()` method on the quest-log participant, found
none, and fell through to the economy's own parcel deliveries every time, so no board in the
game ever listed a bounty. A generated quest has no content-pack definition, so anything the
generator hands out is registered with the log on the way — including notices handed back out of
a board's cache and notices restored from a save, which were not, so every job still hanging on
a board in a loaded game answered "cannot start unknown quest" when taken.

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
Social.quests.set_stage(quest_id, stage)       # stage id, or its number counted from 1
Social.quests.stage_index(quest_id, stage) -> int  # what content wrote, as an index (-1: no such stage)
Social.quests.advance(quest_id)
Social.quests.complete(quest_id, outcome := "") / fail(quest_id, reason) / abandon(quest_id)
Social.quests.choose(quest_id, option) / complete_objective(quest_id, key) / deliver(quest_id, npc_id)
Social.quests.open_options(quest_id) -> [{id, text}]   # the choices open right now
Social.quests.is_active/is_completed/is_failed/is_known(quest_id) -> bool
Social.quests.stage_of/stage_id_of/outcome_of(quest_id)
Social.quests.active_quests() / completed_quests() / failed_quests() -> Array[Dictionary]
Social.quests.entry(quest_id) -> {id, name, layer, state, stage, stage_id, journal, objectives, outcome, giver}
Social.quests.objectives_of(quest_id) -> [{text, type, target, count, needed, done, optional}]
Social.quests.active_markers() -> [{place_id|region_id, radius, quest_id, text}]
Social.quests.tracked_quest() -> String / track(quest_id) -> bool / tracked_objectives()
Waymarks.anchor(quest, stage, objective) / Waymarks.locate(anchor, from, inside) / Waymarks.audit()
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
`tests/unit/test_quest_items.gd`: the things the quests send you to pick up lie where their quests
say, the same place every time, stay taken across streaming and saves, and the note is decided at the Seat.
`tests/unit/test_quest_walk.gd`: every objective of every authored quest can be closed by something
in the built game, every quest has something that starts it, and every target a job board could
name can be done; a new objective that cannot fails it unless it is listed with its reason.
Its `test_print_report` prints the whole walk, objective by objective, with how each one closes.

`./run.sh quests` (`tests/quests/quest_walker.gd`) closes them. It plays every authored quest in
the built world through the game's own services: the quest is begun the way the game begins it,
people are found where their day has them, and their dialogue is steered line by line
(`tests/quests/dialogue_steer.gd`, pinned by `tests/unit/test_dialogue_steer.gd`). Foes are put
down with hits and things are picked up where they lie. Every decision is walked every way from
an in-memory save. After each stage it checks that the stage's effects took, and at each ending
that whoever remembers the quest greets you with it. What the land does to a place the content
names is a `QW WORLD` line with coordinates.
