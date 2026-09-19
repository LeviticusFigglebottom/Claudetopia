# systems/npc_life — schedules, personalities, reactions

Who the people of Wickmere are, where they are at any hour, and what they do when
the player walks up. DESIGN.md §5.11 (world reactions) and §5.12 (schedules and
personalities).

## Files

| File | Kind | What it is |
|---|---|---|
| `schedules.gd` | pure (`static`) | Timetable rules: which entry is current, travel lead, weather override |
| `personality.gd` | `RefCounted` | Six trait axes; gesture disposition, price bias, crime reaction |
| `npc_registry.gd` | Node, group `npc_registry` | Abstract state for every NPC; spawns and despawns actors with cells |
| `reactions.gd` | Node, group `reactions` | Chooses a behaviour from standing, personality, tags and bounty |

The actors themselves are `actors/npc/npc.gd` (villager) and `actors/npc/guard.gd`.

## Data it reads

* `npc` defs (CONTRACTS §7): `home_place`, `personality{traits[]}`,
  `schedule[{days, hour, place, activity, spot}]`, `merchant{...}`, `faction`,
  `tags[]`, and the optional `work_clip` and `perception{}` this system adds.
* `core:table/personality_traits` — trait behaviour rows (`role: personality_traits`).
  `Personality` falls back to built-in constants when no table is loaded.
* `place` positions (for cell lookup) and `region` culture/law, through `WorldProbe`.

### Schedule entries

`days` accepts `"all"`, `"workdays"`, `"restday"`, a day name (`"tollday"`), an
index `0..6` (0 = Kindleday), a range `"1-4"` (wrapping allowed), a list
`"0,2,4"`, or an array of any of those. `hour` is 0..24. `place` may be `"home"`.
`activity` is one of sleep, work, eat, idle, pray, socialise, patrol, shop.

Two rules beyond "latest entry wins":

* **Travel lead** — 20 game-minutes before an entry at a different place the NPC
  is already on the road: `activity` reads `travel` and `after_travel` names what
  they are going to do.
* **Weather** — rain, drizzle, storm or squall sends an *outdoor* `idle` entry
  home (`weather_override: true`). Work, sleep and indoor idling are unaffected.

## Public API

```gdscript
Schedules.entry_at(schedule, weekday, hour, weather, home_place) -> Dictionary
Schedules.entry_for_def(npc_def, day, hour, weather) -> Dictionary
Schedules.intent_for(activity, entry, def) -> String      # animation clip name
Schedules.problems(schedule, owner) -> Array[String]      # content validation

Personality.from_def(npc_def) -> Personality
p.has(trait) / p.disposition_delta(gesture) / p.price_bias()
p.crime_reaction()  # report | flee | confront | ignore
p.greeting_bias() / p.fear() / p.describe()

NpcRegistry.ensure() -> NpcRegistry
reg.state(npc_id) / place_of / activity_of / disposition_of / is_alive / is_hostile
reg.adjust_disposition(npc_id, delta) / note_player_deed(npc_id, deed) / kill(npc_id)
reg.npcs_at(place_id) / spawn(npc_id) / despawn(npc_id) / actor(npc_id)
reg.jail(npc_id, days) / simulate_all(weather)

Reactions.ensure() -> Reactions
Reactions.choose(profile, personality, tags, ctx) -> String   # pure
Reactions.door_barred(profile, culture, wanted) -> bool       # pure
Reactions.line_for(kind, npc_name, title) / Reactions.intent_for(kind)
r.react(npc_id, nearby) / r.on_player_near(npc_id, distance) / r.choose_for(npc_id)
```

Behaviour kinds: `greet`, `bow`, `cheer`, `crowd`, `flinch`, `flee`, `hide`,
`follow`, `growl`, `confront`, `watch`, `ignore`.

## Signals

Emitted: `EventBus.dialogue_started(npc_id)` (talking to an NPC),
`EventBus.gesture_performed`, `EventBus.detection_changed(observer, level)`,
`EventBus.entity_killed`, `EventBus.notify(line, "reaction")`.
Own signals: `Reactions.reaction(npc_id, kind)` for the animation and dialogue
streams; `NpcRegistry.npc_spawned/npc_despawned/state_changed`;
`Npc.arrived/activity_changed`; `Guard.confront(options)/confrontation_ended`.

Consumed: `EventBus.hour_changed`, `new_day`, `weather_changed`,
`cell_loaded`/`cell_unloaded`.

## Save section

`npcs` — `{states: {npc_id: {place, activity, spot, alive, disposition,
last_seen_player_deed, hostile, in_jail_until_day}}}`. Loaded actors are asked
for their state first (`collect_state`), so a save is accurate mid-stride.

## Notes for other streams

* NPC actors mirror the enemy stream's perception interface: a `detection` float
  0..1 and `noise_heard(pos, loudness)`. Crime witnessing reads exactly that, so
  anything with the same two members can witness a crime.
* The registry installs itself on first use (`ensure()`); a world scene may add
  `NpcRegistry`, `Reactions`, `Bounty`, `Ownership`, `Stealth` and
  `EconomyService` explicitly instead, and those instances win.
* Content named `core:npc/example_*` and marked `"example": true` is placeholder
  and meant to be deleted when the writer stream's Merrowby NPCs land.
