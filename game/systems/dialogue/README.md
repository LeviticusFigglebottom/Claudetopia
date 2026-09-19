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
* `content/packs/core/dialogues/greetings.json` — `core:table/greetings`, 57 rows / 142 lines.
* `content/packs/core/gestures/gestures.json` — the ten `gesture` defs.

## Vocabulary

Conditions (all of CONTRACTS §7 plus this stream's): `flag`, `quest_at`, `rep_min`, `renown_min`,
`morality_min`, `skill_min`, `has_item`, `time_between`, `not`, `any`, `all`, `personality`,
`faction_rank_min`, `bounty_min`, `counter_min`, `discovered`, `wearing_tag`, `random`, and the
mirrors `flag_not`, `flag_equals`, `quest_active`, `quest_done`, `quest_not_done`,
`quest_min_stage`, `quest_outcome`, `rep_max`, `renown_max`, `morality_max`, `member_of`,
`not_member_of`, `has_no_item`, `marks_min`, `is_night`, `knows_deed`, `book_read`, `in_region`,
`at_place`, `npc_is`, `witnessed_crime`, `disposition_min`, `true`, `false`.

Effects: `set_flag`, `give_item`, `quest_stage`, `rep`, `morality`, `renown`, `marks`,
`start_quest`, `teach_recipe`, `gesture_reply`, `rumour`, `unlock_topic`, `end`, plus
`clear_flag`, `inc_counter`, `take_item`, `deed`, `disposition`, `complete_quest`, `fail_quest`,
`quest_choice`, `complete_objective`, `join_faction`, `leave_faction`, `discover`, `notify`, `none`.

An unknown condition or effect is a **content problem**: it is logged through the context and the
condition reads false / the effect is skipped. Nothing crashes on bad content.

## Signals

Emits `line_shown(speaker, text, choices)`, `choice_needed(choices)`, `ended` on the runner, and
`EventBus.dialogue_started/dialogue_ended`, `gesture_performed`, `npc_gesture`, `notify`.
Choices are `[{index, text, tag?, skill?}]`; `index` is the index to pass back to `choose()`.

Consumes nothing directly; everything else arrives through the context's providers.

## Save section

None. Dialogue state is flags and counters in `GameState` (`unlock_topic` writes `topic/<id>`).

## Public API

```gdscript
Social.talk(npc_id, dialogue_id := "", place := "") -> Node   # the runner, already started
runner.advance()                    # past a line with no choices
runner.choose(index)                # take the choice the UI showed at that index
runner.start_def(def, npc_id)       # run a graph that is not in the packs (generated, tests)
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

## Tests

`tests/unit/test_dialogue_conditions.gd` (24), `tests/unit/test_dialogue_runner.gd` (21),
fakes in `tests/fixtures/fakes.gd`.
