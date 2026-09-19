# systems/factions — standing with people, and with everybody

Reputation and rank with the eight factions; the Hearth/Hollow axis and Renown; and the gossip
that carries what you did from one village to the next. This is the mechanical half of the frame
in DESIGN §2: being known is what holds.

| File | What it is |
|---|---|
| `factions.gd` | Reputation −100..100, ranks from `rank_thresholds`, membership with rival penalties, law lookup by region. Group `factions`, save section `factions`. |
| `standing.gd` | Morality (Hearth/Hollow −100..100), Renown (0..1000), the deed table, per-NPC disposition and witness memory. Group `standing`, save section `standing`. |
| `gossip.gd` | Rumour pools per settled place, spreading along a talk graph over game hours, with decay. Group `gossip`, save section `gossip`. |

## Data

* `content/packs/core/factions/factions.json` — `faction` defs: `ranks[]`, `rank_thresholds[]`,
  `joinable`, `rival`, and the `law` block `{region, jail_place, arrest_threshold,
  fine_multiplier, jail_days_per_100, style}`.
* `content/packs/core/tables/deeds.json` — `core:table/deeds`, 40 rows:
  `{id, label, hearth, renown, witness_renown, witness_cap, rumour, heat}`.
* `content/packs/core/rumours/rumours.json` — 40 `rumour` defs: `{id, name, tone, text, variants[]}`,
  templates using `{player} {place} {title} {npc}`.

## How the numbers work

**Ranks** need membership: an outsider with high reputation still holds no rank. Rank is the
highest threshold your reputation has passed.

**Rivals**: joining expels you from the rival and costs `RIVAL_JOIN_PENALTY` (25) with them;
while you are a member, positive reputation bleeds `RIVAL_BLEED` (0.5) off the rival. Losing
standing with one is never a favour to the other. An expulsion is remembered until
`clear_expulsion()`.

**Deeds** move both axes: `hearth` always (you did it whether or not anyone saw), `renown` as a
base plus `witness_renown` per witness up to `witness_cap` — a deed nobody saw barely anchors.
Repeating a *kind* deed softens (6% per prior time, floor 25%); cruelty never gets cheaper.
Witnessed cold deeds are remembered by the NPCs who saw them (`npc_witnessed`) and seed the
nearest place's rumour pool.

**Tiers**: renown thresholds `[0, 25, 100, 300, 600]` → `"", the Heard-Of, the Known,
the Spoken-Of, the Named`. Morality tiers are signed −3..+3 at |15|, |40|, |75| →
`Kindly / Hearth-Warm / the Hearth-Kept` and `Cold-Handed / Quiet-eyed / the Hollow`.

**Gossip**: only settled places talk (`SETTLED_KINDS`). The talk graph links each settlement to
its four nearest neighbours within 3 km (symmetrised), with a travel time at 700 m per game hour.
Each hour pools cool and rumours above `SPREAD_THRESHOLD` walk onward, arriving at `TRANSFER`
(0.55) of their heat. How fast a rumour cools depends on how big it was: `decay_rate()`
interpolates 0.93/hour for small talk to 0.99/hour for a killing, so the Vale is still chewing
over blood three days later and has forgotten your manners by supper. Below `MIN_HEAT` it is
forgotten; at or above `KNOWN_HEAT` (0.25) an NPC there will bring it up.

## Signals

Emits `faction_reputation_changed`, `faction_rank_changed`, `morality_changed`, `renown_changed`,
`deed_applied`, `disposition_changed`, `rumour_spread`. Consumes `hour_changed` (gossip).

## Save sections

`factions` `{reputation, members, expelled}` · `standing` `{morality, renown, deed_counts,
disposition, witnessed}` · `gossip` `{pools}`.

## Public API

```gdscript
Social.factions.reputation(id) -> int ; add_reputation(id, delta, reason := "") -> int ; set_reputation(id, v)
Social.factions.rank(id) -> int ; rank_name(id) -> String ; next_rank_at(id) -> int
Social.factions.is_member(id) -> bool ; join(id) -> bool ; expel(id, reason) ; was_expelled(id)
Social.factions.law_faction_for_region(region_id) -> String
Social.factions.law_for_region(region_id) -> Dictionary ; is_lawless(region_id) -> bool
Social.factions.summary() -> {faction_id: {name, reputation, rank, rank_name, member}}

Social.standing.morality() / renown() -> int ; add_morality(d, reason) / add_renown(d, reason)
Social.standing.morality_tier() -> int (-3..3) ; renown_tier() -> int (0..4)
Social.standing.title() / renown_title() / morality_title() -> String
Social.standing.reaction_profile() -> {renown, renown_tier, renown_title, morality,
                                       morality_tier, morality_title, title, hollow}
Social.apply_deed(deed_id, witnesses := [], place := "") -> {deed, hearth, renown, witnesses, rumour, place}
Social.standing.disposition(npc_id) / add_disposition(npc_id, delta)
Social.standing.npc_witnessed(npc_id) -> String ; forget_witness(npc_id)

Social.gossip.add_rumour(rumour_id, place_id, heat := 0.6, deed_id := "")
Social.gossip.knows_deed(place_id, deed_id) -> bool ; knows_rumour(place_id, rumour_id) -> bool
Social.gossip.pool_of(place_id, subs := {}) -> [{rumour, heat, deed, text}] ; hottest(place_id, subs)
Social.gossip.rumour_text(rumour_id, place_id, subs) -> String
Social.gossip.nearest_place(pos: Vector3) -> String ; neighbours_of(place_id) -> [{place, dist, hours}]
Social.gossip.advance_hours(hours)   # the hour signal does this in play; tests skip time with it
```

`reaction_profile()` is the contract other streams read for morality visuals, prices, guard
tolerance and greetings.

## Tests

`tests/unit/test_factions.gd` (18), `tests/unit/test_standing.gd` (28).
