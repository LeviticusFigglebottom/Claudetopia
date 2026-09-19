# systems/crime — ownership, crimes, bounty, stealth

Taking what is not yours, being seen doing it, and not being seen doing it.
DESIGN.md §5.13.

## Files

| File | Kind | What it is |
|---|---|---|
| `ownership.gd` | Node (static helpers) | Who owns an item, container, door, bed or animal |
| `crimes.gd` | pure (`static`) | Severity table, witness rule, fines, jail terms, law styles, gossip reach |
| `bounty.gd` | Node, group `crime` | Bounty per law faction, witness reports, decay, save section |
| `detection_meter.gd` | `RefCounted` | One observer's awareness 0..1 over time |
| `stealth.gd` | Node, group `stealth` | Light, noise, visibility, sneak attacks, pickpocket, lockpicking |
| `stealth_light.gd` | `Node3D` | A light source as far as stealth is concerned |
| `door_lock.gd` | Node | Lock component for a `Door` or chest; the lockpick minigame |

## The rules

**Severity**: trespass 5, pickpocket 25, theft `max(10, value/2)`, assault 40,
murder 100 (a Hollow deed), lockpicking 15.

**Witness**: an NPC witnesses a crime when its detection meter is at or above
**0.6** *and* it has line of sight. Sound alone never makes a witness — hearing
is capped just under the threshold. The witness then walks to the law: half a
game hour normally, a quarter for the confrontational, a full hour for those who
flee first, immediately for a guard, and never for `ignore` (the cynical and the
quiet). Killing or silencing the witness before they arrive cancels the report.

**Bounty keys**: a crime is recorded against the law faction of the region it
happened in, or against the *region id* itself where there is no law (the
Briarwold, Cinderlea). Lawless totals decay one point per game day and are never
enforced by guards — they are ill-feeling, and feed gossip and barred doors.
Faction bounties do not decay; they are paid, served or resisted.

**Law styles** (from each faction's `law` block): `fine_or_jail` (pay ×
`fine_multiplier` / jail `bounty/100 × jail_days_per_100` days / resist),
`blood_price` (pay double, or refuse — no cell in Skerrow), `exile` (leave the
Sedgemire boardwalks), `none` (no confrontation).

**Stealth**: visibility rises with light and noise and falls with crouching and
Sneak. Light is the sun (daylight × sky exposure × weather, with a moonlight
floor and a shadow raycast) screen-blended with registered `StealthLight`
sources. Noise comes from speed, armour weight class, crouch, surface and rain.
A detection meter per observer rises by `visibility × distance falloff × facing`,
holds two seconds after losing sight, then falls.

Sneak attacks multiply ×3, or ×6 with a dagger, and ×1 once the target is alert.

## Public API

```gdscript
Ownership.tag(node, faction, npc)                 # metadata on a scene node
Ownership.owner_of(node_or_id) -> {faction, npc}
Ownership.is_owned_by_other(node_or_id, actor_id, actor_factions) -> bool
Ownership.ensure().assign_owner(id, faction, npc) / claim_for_player(id) / owned_by(npc_id)

Crimes.severity(kind, value) / morality_delta(kind) / is_hollow_deed(kind)
Crimes.is_witness(detection, line_of_sight) / report_delay_hours(reaction, is_guard)
Crimes.fine(bounty, mult) / jail_days(bounty, per_100)
Crimes.confront_options(style, bounty, law) -> Array[{id, label, cost?, days?}]
Crimes.gossip_targets(place_id, places, known, range_m) -> Array[String]

Bounty.ensure() -> Bounty                          # group "crime"
b.bounty(faction_id) -> int                        # contracted name
b.report_crime(crime: Dictionary) -> Dictionary    # contracted name
b.pay_bounty(faction_id, payer) -> bool            # contracted name
b.commit(kind, position, opts) -> Dictionary       # the full form
b.total(key) / total_for_region(region_id) / is_wanted(key) / clear(key)
b.silence_witness(npc_id) / process_pending() / spread_gossip() / decay_lawless()

Stealth.ensure() -> Stealth                        # group "stealth"
st.player_visibility() / player_noise() / player_light() / light_level(pos)
st.sneak_multiplier(attacker, target) -> float
st.pickpocket(thief, victim, item_id, rng) -> {ok, chance, caught, item_id}
Stealth.pickpocket_chance(sneak, awareness, value) -> float
Stealth.lockpick_attempt(skill, lock_level, timing_accuracy) -> {success, broke, window, margin}
Stealth.noise_level(speed, weight_class, crouched, surface, raining) -> float
Stealth.visibility(light, noise, crouched, sneak_skill) -> float

DetectionMeter.new().update(delta, visibility, distance, range, facing_dot, fov, has_los, pos)
```

## Signals

Emitted: `EventBus.crime_committed(crime)`, `bounty_changed(faction_id, total)`,
`arrested(faction_id)` (from `Guard`), `detection_changed(observer, level)`,
`rumour_spread("bounty:<key>", place_id)`, `skill_used("sneak", xp)`,
`notify(...)`. Own: `Bounty.changed`, `Bounty.crime_reported`,
`DoorLock.unlocked/lockpick_started/attempt_made/pick_broken`.

Consumed: `EventBus.hour_changed` (reports, gossip), `new_day` (decay),
`entity_killed` (a dead witness reports nothing), `weather_changed`.

## Save section

`crime` — `{totals, pending, known, history, ownership: {registry}}`. The
ownership registry rides along here rather than owning a section of its own.

## Notes for other streams

* `DoorLock` is the child named exactly `DoorLock` on the interiors stream's
  `Door` scene, and exposes the contracted `is_locked()` and `try_open(actor)`.
  It adopts the Door's own `owner_faction`/`owner_npc` exports.
* A crime's `morality_delta` and `hollow_deed` fields are advisory: the morality
  system applies them from the `crime_committed` payload.
* `ContentDB.where(type, key, value)` errors on array-valued fields in Godot
  4.7; use `ContentQuery.with_tag` / `where_scalar` (see `systems/shared`).
