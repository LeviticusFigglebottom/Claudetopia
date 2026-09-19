# systems/social — the autoload that wires the social half together

`Social` (autoload, `res://systems/social/social.gd`) owns one `SocialContext` and five nodes:

| Child | Script | Group | Save section |
|---|---|---|---|
| `Factions` | `systems/factions/factions.gd` | `factions` | `factions` |
| `Standing` | `systems/factions/standing.gd` | `standing` | `standing` |
| `Gossip` | `systems/factions/gossip.gd` | `gossip` | `gossip` |
| `QuestLog` | `systems/quests/quest_log.gd` | `quest_log` | `quests` (board cooldowns included) |
| `Dialogue` | `systems/dialogue/dialogue_runner.gd` | `dialogue_runner` | — |

`Social.radiant` is the `RadiantGenerator` the quest log saves alongside its own state.

## Why an autoload

Dialogue conditions read quests, factions, standing, gossip, the clock and the player's pack;
quest effects write to all of them. Wiring that through one autoload keeps every system reachable
without any of them holding another's node path (ARCHITECTURE §9), and gives the UI, crime and
economy streams one name to call. It is the only addition this stream makes to `project.godot`.

## Binding the systems other streams own

The context reads the player, the inventory, the crime system's bounties and the crafting
system's recipes through duck-typed providers. A system binds itself either way:

```gdscript
Social.bind("inventory", self)   # explicit
add_to_group("inventory")        # or just join the group; Social picks it up
```

| group | provider | what is called |
|---|---|---|
| `inventory` | `inventory` | `count(id)`, `add(id, n)`, `remove(id, n)`, `marks` (method or property), `add_marks(n)`, `remove_marks(n)`, optionally `has_equipped_tag(tag)` |
| `equipment` | `equipment` | `slots()` → `{slot: item_id}`, read for `wearing_tag` when the bag does not answer it |
| `player` | `player` | `display_name()`, and a position: a `position()` method **or** any Node3D. Binding it also feeds `reach` objectives. |
| `progression` | `skills` | `skill_level(id)` |
| `crime` | `bounty` | `bounty_for(faction_id)` |
| `crafting` | `recipes` | `teach(recipe_id)` |

Anything missing degrades safely: the read returns a default and a write is logged as a lost
effect rather than silently succeeding. `SocialContext.position_of(obj)` / `can_locate(obj)` are
the helpers that accept either shape of "where are you".

## World events that are deeds

Social applies three deeds itself, so renown moves without every stream knowing the table:
`boss_defeated` → `boss_kill` (once per boss, guarded by a `boss_deed/<id>` flag),
`place_discovered` → `place_discovered`, `player_died` → `died`. **Everything else**
(crimes, kindnesses, ordinary kills) is applied by the system that knows about it, through
`Social.apply_deed(deed_id, witnesses, place)`, so nothing is counted twice. Quest completion
applies its layer's deed from the quest log's reward step.

## Debug console

`systems/social/debug_commands.gd` registers `talk`, `next`, `say`, `greet`, `gesture`,
`standing`, `deed`, `rep`, `join`, `quests`, `quest`, `board` and `rumours` with the optional
`Debug` autoload, so a conversation or a reputation can be driven by hand:
`./run.sh run -- --cmd="region core:region/hearthvale; talk wardens_hesk; next; say 0"`.

## Public API

```gdscript
Social.talk(npc_id, dialogue_id := "", place := "") -> Node    # the runner, started
Social.greet(npc_id) -> String
Social.do_gesture(gesture_id, npc_id := "", witnesses := []) -> Dictionary
Social.apply_deed(deed_id, witnesses := [], place := "") -> Dictionary
Social.reaction_profile() -> Dictionary
Social.board_jobs(board_place_id, region_id := "", count := 3) -> Array[Dictionary]
Social.take_quest(quest_id) -> bool
Social.place_id() -> String ; Social.set_place(place_id)
Social.bind(provider_name, obj) ; Social.refresh_providers()
Social.reset_for_new_game()
```

`Social.place_id()` is where the player counts as being, for gossip and greetings: the nearest
settled place to the bound player, or whatever `set_place()` last said.

Details of each subsystem live in `systems/dialogue/README.md`, `systems/quests/README.md` and
`systems/factions/README.md`.
