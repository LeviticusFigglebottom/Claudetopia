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

Groups looked for: `inventory` → the `inventory` provider (`count`, `add`, `remove`,
`has_equipped_tag`, `marks`, `add_marks`, `remove_marks`), `player` → `player`
(`display_name`, `position`, `skill_level`; binding it also feeds `reach` objectives),
`crime` → `bounty` (`bounty_for`), `crafting` → `recipes` (`teach`).
Anything missing degrades safely: the read returns a default and a write is logged as a lost
effect rather than silently succeeding.

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
