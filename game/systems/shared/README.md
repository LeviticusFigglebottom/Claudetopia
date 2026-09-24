# systems/shared — cross-stream helpers

Small static helpers the NPC-life, crime and economy systems share. Nothing here
holds state or owns a save section; nothing here references another stream's
class by name, so it compiles whether or not those systems exist yet.

| File | What it is |
|---|---|
| `peers.gd` | Duck-typed access to other streams' systems (standing, factions, inventory, quests, progression, the player) |
| `world_probe.gd` | Graceful access to the world stream's `World` accessor, plus cell/place/region/law geometry |
| `place_ref.gd` | Points said as a place and where from it (bearing, offset, a way's shape), and the pins a save keeps beside a place, so both follow a redrawn map (docs/COORDINATES.md) |
| `content_query.gd` | Tag and scalar content lookups that avoid a `ContentDB.where` bug |
| `service.gd` | Lazy installation of this stream's service nodes |

## Peers

Resolution order for each system: a test override, the scene group of that name
(`inventory`, `standing`, `factions`, `quests`, `progression`, `player`), then
the registered `SaveSystem` section. Everything returns a safe default when the
system is absent, so these systems run before the others land.

```gdscript
Peers.reaction_profile() -> {renown, renown_tier, morality, morality_tier, title}
Peers.skill_level(skill_id) / faction_rank(id) / faction_rep(id) / is_player_member(id)
Peers.law_faction_for_region(region_id) -> String or null (null = no Factions system)
Peers.knows_deed(place_id, deed) -> bool
Peers.inventory_of(actor) / item_count / give_item / take_item / items_of
Peers.overrides["standing"] = fake     # tests
```

## WorldProbe

```gdscript
WorldProbe.get_height(x, z, fallback) / region_id_at(pos) / has_world()
WorldProbe.cell_of(pos) / cell_of_place(place_id)      # CONTRACTS §6 cell maths
WorldProbe.place_position(place_id) / nearest_place(pos, max_m)
WorldProbe.law_of_region(region_id) -> {faction_id, law{style, ...}}
WorldProbe.culture_key(region_id) -> vale | lakefolk | reedfolk | clans | woodfolk | pilgrims
```

Without the world stream, heights fall back to the region def's `base_height`
and the region at a point is the nearest region centre in units of its radius.

## ContentQuery

`ContentDB.where(type, key, value)` raises *"Invalid operands 'Array' and
'String' in operator '=='"* in Godot 4.7 whenever any definition of that type
holds an Array in `key` that does not contain `value` (`content_db.gd:102` falls
through to `v == value`). Tag lookups therefore use `ContentQuery.with_tag`,
and scalar-field lookups use `where_scalar`. The one-line fix in the shared
file, if the owning stream wants it, is to guard that `elif` with
`typeof(v) != TYPE_ARRAY`.

## Service

`Service.ensure(script, node_name)` returns the existing node of that name under
the scene tree root or installs one. This is how `Bounty`, `Ownership`,
`Stealth`, `EconomyService`, `PropertyRegistry`, `NpcRegistry` and `Reactions`
come to exist without a new autoload. A world scene may add them explicitly
instead, and those instances win (each sets its own `instance` in `_enter_tree`).
