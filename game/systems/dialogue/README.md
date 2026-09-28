# systems/dialogue — talking, greeting, gesturing

Everything an NPC says and everything a conversation does to the world.

| File | What it is |
|---|---|
| `context.gd` | `SocialContext`: the one object conditions read and effects write through. Every access goes to a duck-typed provider, so tests use fakes and no system here holds another system's node path (ARCHITECTURE §9). |
| `conditions.gd` | `Conditions`: pure static evaluator for the CONTRACTS §7 condition vocabulary. |
| `effects.gd` | `Effects`: pure static applier for the CONTRACTS §7 effect vocabulary. |
| `dialogue_runner.gd` | The node that walks a dialogue graph and talks to the UI. Group `dialogue_runner`. |
| `greetings.gd` | `Greetings`: picks the opening line from a personality × standing matrix. |
| `gestures.gd` | `Gestures`: bow, wave, rude and the rest; disposition by personality, plus a reply. |

## Data

* `content/packs/core/dialogues/*.json` — `dialogue` defs: `{id, start, nodes{...}}` (CONTRACTS §7).
  A node is `{speaker, text, conditions[], effects[], choices[{text, next, conditions[], effects[], once, tag}], next, else, once}`.
  `speaker` is `npc`, `player`, or an NPC id. Text may use `{player} {title} {npc} {place} {region}` and `{greeting}`.
* `content/packs/core/dialogues/greetings.json` — `core:table/greetings`, 60 rows / 152 lines.
* `content/packs/core/gestures/gestures.json` — the ten `gesture` defs.

## Vocabulary

Conditions (all of CONTRACTS §7 plus this stream's): `flag`, `quest_at`, `rep_min`, `renown_min`,
`morality_min`, `skill_min`, `has_item`, `time_between`, `not`, `any`, `all`, `personality`,
`faction_rank_min`, `bounty_min`, `counter_min`, `discovered`, `wearing_tag`, `random`,
`knows_spell`, and the
mirrors `flag_not`, `flag_equals`, `quest_active`, `quest_done`, `quest_not_done`,
`quest_min_stage`, `quest_outcome`, `rep_max`, `renown_max`, `morality_max`, `member_of`,
`not_member_of`, `has_no_item`, `marks_min`, `is_night`, `knows_deed`, `book_read`, `in_region`,
`at_place`, `npc_is`, `witnessed_crime`, `disposition_min`, `true`, `false`.

Effects: `set_flag`, `give_item`, `quest_stage`, `rep`, `morality`, `renown`, `marks`,
`start_quest`, `teach_recipe`, `teach_spell`, `gesture_reply`, `rumour`, `unlock_topic`, `end`, plus
`clear_flag`, `inc_counter`, `take_item`, `deed`, `disposition`, `complete_quest`, `fail_quest`,
`quest_choice`, `complete_objective`, `join_faction`, `leave_faction`, `discover`, `notify`, `none`,
`bounty`, `offer_work`, `travel` (to a lit Hearthstone: `Hearth.travel_to`).

`bounty` is a decision that is a crime: `{"bounty": "theft"}`, or `{"bounty": {"crime", "value",
"at", "seen_by", "reaction"}}`. It is committed through the crime service (`Bounty.report_crime`) at
`at` (the conversation's place when left out), seen by `seen_by` (the person spoken to when left
out), so the severity, the law of the place's region, the witness's report delay and the lawless
regions' ill-feeling are the crime system's own. Nobody seeing it means nobody reports it.
`offer_work` opens the work going in a place (the speaker's own when `true`): the notice post that
stands there, or, where there is none, what its people carry (`JobBoard.for_place`).

An unknown condition or effect is a **content problem**: it is logged through the context and the
condition reads false / the effect is skipped. Nothing crashes on bad content.

## Signals

Emits `line_shown(speaker, text, choices)`, `choice_needed(choices)`, `ended` on the runner, and
`EventBus.dialogue_started/dialogue_ended`, `dialogue_node_entered` (a `talk` with a `topic` closes
on it), `gesture_performed`, `npc_gesture`, `notify`, and `job_board_opened` for `offer_work`.
Choices are `[{index, text, tag?, skill?}]`; `index` is the index to pass back to `choose()`.

A choice that does something to a quest also carries `quest: {kind, quest_id, name, tier, tag,
tier_word}` (`runner.quest_cue(choice)`, `QuestCues.for_choice`, triage 50), read from its effects
and the lines it leads to up to the next answers, never from anything written on it: `start`
(`start_quest`, or `quest_stage` on a quest not taken), `advance` (`quest_stage`,
`complete_objective`, `quest_choice`, the `topic` line an open `talk` with this person waits for, a
`take_item` a `deliver` to them waits for), `turn_in` (`complete_quest`, or any of those when it is
the last thing the quest asks), `about` (no effect, but offered only while a quest is at a stage).
`tier` is `main`, `side`, `faction`, or `intro` (a style's `tutorial`/`tie_in`). The page writes
`[New quest]`, `[Quest]` or `[Turn in]` before the answer, with the quest icon in the tier's colour,
and the quest's name and tier under the answers while it has the focus (and on hover); the
nameplate says the person's quest business (`runner.speaker_quest_state()`), and a `QuestMark`
over their head in the world says the same ("!" to give, "?" to go on with or hand in).

Consumes `damage_dealt`, `enemy_engaged`, `player_died` and `game_loaded`: each ends a running
conversation (triage 41). Everything else arrives through the context's providers.

### Every ending goes through `stop()`

The runner owns the conversation, and `EventBus.dialogue_ended` is the one signal the camera's
two-shot, the dialogue page, the held body and the NPC's day key on, so it is always sent: the
graph's own ends, the player struck, a foe within 25 m turning on them, death, a load, and the
person spoken to (`speaker_actor`, handed over by `Npc.interact` via `set_next_speaker`, or the
roster's body) gone, dead or `WALK_AWAY_M` further off than at the start. A node whose every answer
its conditions close off, with no `next`, is given "Leave."; a node with no line and nothing to ask
says "...". `CameraRig` keeps a conversation's shot only while the runner runs. A shop with no words
is a screen (`EventBus.trade_requested`), never a `dialogue_started`.

## Save section

None. Dialogue state is flags and counters in `GameState` (`unlock_topic` writes `topic/<id>`).

## Public API

```gdscript
Social.talk(npc_id, dialogue_id := "", place := "") -> Node   # the runner, already started
runner.advance()                    # past a line with no choices
runner.choose(index)                # take the choice the UI showed at that index
runner.start_def(def, npc_id)       # run a graph that is not in the packs (generated, tests)
runner.set_next_speaker(body)       # the body the next conversation is held to (before start)
runner.stop()                       # ends it, from anywhere; Escape on the page calls this
runner.check_speaker() -> bool      # the watch's look, at once
runner.greeting_for(npc_id) -> String
runner.gesture(gesture_id, witnesses := []) -> Dictionary
Social.greet(npc_id) -> String
Social.do_gesture(gesture_id, npc_id := "", witnesses := []) -> Dictionary
Conditions.all_of(conds, ctx) -> bool ; Conditions.check(cond, ctx) -> bool
Effects.apply_all(effects, ctx, reason := "dialogue")
Greetings.greet(npc_id, ctx) -> String ; Greetings.select_row(npc_id, ctx) -> Dictionary
Gestures.perform(gesture_id, npc_id, ctx, witnesses := []) -> Dictionary
```

### Greeting selection

Every constraint a row states must hold; the most specific match wins and `weight` breaks ties.
Specificity is weighted so that what this villager *saw* (4) beats what the village is *saying*
(3), which beats your standing, rank, bounty and the hour (2), which beat their personality (1).
A row that matches only because you are unremarkable (renown tier 0, morality tier 0) scores no
specificity, so it is a fallback rather than an answer.

Traits the matrix has rows for: `kind`, `gossip`, `quiet`, `timid`, `brave`, `proud`, `humble`,
`greedy`, `generous`, `pious`, `cynical`. An NPC with a trait no row names still gets rows for
their other traits and for your standing, so nothing goes silent; adding a trait is adding rows.

`wearing_tag` asks the inventory if it answers that question itself, otherwise it reads the
equipment slots and the items' own `tags`. `skill_min` reads the progression system.

## Tests

`tests/unit/test_dialogue_conditions.gd` (24), `tests/unit/test_dialogue_runner.gd` (21),
`tests/unit/test_social_integration.gd` (9, against the real bag, doll and skills),
`tests/unit/test_dialogue_endings.gd` (11, every ending lets the camera go),
`tests/unit/test_dialogue_page.gd` (8, the page is never up empty), fakes in
`tests/fixtures/fakes.gd`.
