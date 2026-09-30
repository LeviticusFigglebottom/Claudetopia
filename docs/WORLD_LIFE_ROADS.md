# Life on the roads: how a region adds its own

The playtest found the land between places empty. `game/systems/roads/` gives the roads a life:
caravans that walk between towns, ambushes at the road's bends and bridges, patrols, pilgrims,
somebody lost, a broken cart, beasts crossing, a wandering pedlar, and a runaway with hunters behind
him. The systems are generic. What happens, where, and how often is content, and each region keeps
its own file.

## The files

| File | What it is |
|---|---|
| `game/systems/roads/road_life.gd` | `RoadLife`, the director (a GameServices service). It rolls events as the player travels, keeps the caravans' journeys and stands them up nearby, takes things down, and saves. |
| `game/systems/roads/road_event.gd` | `RoadEvent`: one event standing: its cast, its behaviours, its talk, its hooks. |
| `game/systems/roads/road_tables.gd` | `RoadTables`: reads the `roadtable` defs and picks a row. `problems()` is the content check. |
| `game/systems/roads/road_sites.gd` | `RoadSites`: the built roads (not streets) as polylines, with the features along them: `bend`, `bridge`, `pass`, `woods`. |
| `game/systems/roads/road_folk.gd` | `RoadFolk`: an unarmed person met on the road (an Npc body with no npc id). |
| `game/systems/roads/road_talk.gd` | `RoadTalk`: the interact prompt on an armed road person (a trader, a guard). |
| `game/systems/roads/road_train.gd` | `RoadTrain`: a packhorse or a horse and cart, from the forge's cob and props, with the load as a `WorldContainer`. |
| `game/content/packs/core/roadlife/common.json` | Events any region can use: the two caravans, the Wardens' patrol, pilgrims, lost traveller, broken cart, wandering pedlar, runaway. |
| `game/content/packs/core/roadlife/<region>.json` | **One per region, owned by that region's agent**: its `roadtable` and its own events. |
| `game/content/packs/core/enemies/road_folk.json` | The road's armed people: `caravan_guard`, `road_trader`, `road_warden`, `bounty_hunter`. They use faction `wayfarers`. |
| `game/tests/unit/test_road_life.gd` | The tests. |
| `game/tools_gd/road_life_ride.gd` | Measures a ride: `./run.sh roads --only=<roads> --roadlife=on` (or `off`, to compare). |

To add to a region, edit only `roadlife/<region>.json`. Files are merged by region: two
`roadtable` defs for one region add their rows, caravans and sites together. A pack can add a region
file of its own without touching the core one.

## A region's table (`roadtable`)

```json
{
  "id": "core:roadtable/hearthvale",
  "region": "core:region/hearthvale",
  "budget": {"max_active": 3, "gap_s": 55, "every_m": [260, 520]},
  "rows": [
    {"event": "core:roadevent/hearthvale_larkbourne_ambush", "weight": 3,
     "sites": ["bend", "woods", "bridge", "pass"], "tier": [1, 99], "cooldown_h": 8},
    {"event": "core:roadevent/hearthvale_down_wolves", "weight": 2, "when": "night", "cooldown_h": 6},
    {"event": "core:roadevent/pilgrims", "weight": 2, "when": "day", "biome": ["fields", "open"]}
  ],
  "caravans": [
    {"event": "core:roadevent/carters_wagon", "route": ["core:place/merrowby", "core:place/tamwick"],
     "speed": 1.3, "start": 0.35}
  ],
  "sites": [{"at": {"place": "core:poi/larkbourne_ford", "offset": [12, -30]}, "kind": "bend", "tell": "felled_tree"}]
}
```

- **`budget`** (optional) overrides the director's defaults while the player is in this region:
  - `max_active`: events standing at once (default 3). Caravans are not counted.
  - `gap_s`: the least time between two events starting (default 55 s).
  - `every_m`: `[min, max]` metres of travel between rolls (default 260-520).
- **`rows`**: what may happen. A row fits when all of these hold:
  - `when`: `always`/`any`, `day`, `night`, `dawn`, `dusk` or `midnight` (PoiEncounters' words);
  - `biome`: the ground beside the road is one of `woods`, `marsh`, `upland`, `ash`, `shore`,
    `fields` or `open` (read from the terrain's paint; empty means any);
  - `tier`: `[lo, hi]` of the player's tier. Tier 1 is levels 1-3, tier 2 is 4-7, tier 3 is 8-12,
    tier 4 is 13 and up;
  - `sites`: the road ahead (110-280 m) has one of these features. Needed by an ambush; optional
    for anything else, which then stands at that feature;
  - `cooldown_h`: game hours after this event starts before it may come again;
  - the event's own `if` / `unless` conditions and `once`.

  One row is picked by `weight` among those that fit.
- **`caravans`**: standing traffic. Each is a journey kept for the whole game:
  - `route` is two places, walked on the built roads (RoadRoutes);
  - `speed` is in m/s;
  - `start` is how far along the route it is at a new game (0-1).

  It rests 3 game hours at each end and turns round. If it is broken, it sets out again 72 hours
  later.
- **`sites`**: your own ambush sites, added to the road features the land has. Each is `at`, said
  beside a place (`{"place": id, "offset": [dx, dz]}`, PlaceRef, so it moves with the map), snapped
  to the nearest road, with a `kind` and optionally a `tell`. Use them for a place the
  story wants, such as the Larkbourne ford.

## An event (`roadevent`)

```json
{
  "id": "core:roadevent/hearthvale_larkbourne_ambush",
  "name": "The Larkbourne Boys' toll",
  "kind": "ambush",
  "tell": ["crows", "felled_tree", "injured_traveller"],
  "cast": [
    {"role": "bandit", "enemy": "core:enemy/roadside_bandit", "count": [2, 4]},
    {"role": "bait", "folk": {"name": "A wounded man"}, "pose": "Cower", "only_tell": "injured_traveller",
     "talk": {"prompt": "Help the wounded man", "do": "spring"}}
  ],
  "lines": {"speaker": "A Larkbourne Boy", "spring": "Tell them it was the Larkbourne Boys!"}
}
```

**`kind`** is one of the following. It picks each cast member's default behaviour (`does`):

| kind | default `does` | notes |
|---|---|---|
| `caravan` | `walk` | Only used from a table's `caravans`. Needs a `trader`-role cast entry; takes `train`, `merchant`, `consequence` and `rescue`. |
| `ambush` | `hide` (enemies), `wait` (folk) | Needs a road site ahead. `tell` is chosen at random from the list. `"prey": "caravan"` lays it ahead of a caravan standing near the player instead. |
| `patrol`, `pilgrims`, `wanderer` | `walk` | They come towards the player from ahead, or catch up from behind. |
| `lost_traveller`, `broken_cart` | `wait` | At the road's edge. |
| `beasts` | `roam` | Across the road and back, 45 m either side. Hostile. May happen off the road. |
| `fugitive` | `flee` (the first cast entry), `follow` (the rest) | The runaway runs past; the hunters walk 35 m behind. |

**`cast`** entries:
- `role`: a free name. `trader` gets the shop.
- `enemy` (an enemy id: an armed body that can be fought) **or** `folk` (`{name, tags, appearance, home}`:
  an unarmed person).
- `count`: a number, or `[min, max]`.
- `does` overrides the kind's default behaviour. `pose` holds a clip while waiting (`Sit_Idle`,
  `Cower`, `Work_Dig`).
- `only_tell` stands this entry only for that tell.
- `hostile: true` makes an enemy in a walking cast hostile as usual instead of a road person.
- `talk`: what the interact key does, given as `{prompt, say, do, hook}`. `do` is one of:
  - `say`: speaks the line, and gives the `hook` once;
  - `trade`: opens the shop screen on the event's `merchant`;
  - `escort`: the person follows you to the nearest settlement (`{place}` in `say` names it), then
    says `thanks` and gives the `hook`;
  - `help`: gives the `hook` and ends the event;
  - `turn_in`: hands the runaway over (the hunters' `hook`);
  - `spring`: springs the ambush.

The rest of the event:
- **`hook`** (also `rescue`): what the event comes to:
  - `marks`;
  - `item` and `count`;
  - `reputation: {faction, delta}`;
  - `rumour`: a line; `{place}` names what it reveals;
  - `reveals`: a POI id, or `nearest:<poi kind>` for the nearest such POI not yet found. It is found
    (GameState.discover), so the compass and the chart show it;
  - `once`: true to give it once a game.
- **`train`**: `{kind: "wagon" | "packhorse", goods: loot table}`. The load is a container that
  belongs to the consequence's faction while the trader lives, so taking from it is theft; once the
  trader is dead, it belongs to nobody.
- **`merchant`**: `{stock: a stock table, marks, buys: [categories]}`.
- **`consequence`**: `{faction, reputation, killing, notice, killing_notice}`:
  - the first blow the player strikes on any of the cast costs `reputation` and says `notice`, and
    the whole cast turns on the player;
  - each road person the player kills costs `killing` and says `killing_notice`.
- **`rescue`**: a hook with a `say` line. The caravan gives it when an ambush set on it is put down
  and the player had a hand in the fight or was within 40 m.
- **`lines`**: `{speaker, spring}`, said as the ambush springs.
- **`speed`** (m/s), **`cooldown_h`**, **`if`**, **`unless`**, **`once`**.

**Tells** for an ambush:
- `crows` wheel over the site;
- `felled_tree` lays the region's fallen log across the road. The ambush springs 4 m further out;
- `injured_traveller` is the cast entry with `only_tell` lying in the road. Speaking to them springs
  it.

Only `felled_tree` and `crows` need no cast entry.

**Fairness.** An ambush's hidden foes are capped by the player's tier: 2, 3, 4 or 5. The first two
come out at once and the rest 1.4 s apart. AttackTokens then lets no more than two swing at one
body at a time. For a first tier, keep counts at `[2, 3]` or lower. Beasts count against the same
cap.

## Rules the director keeps (and you don't need to)

**When nothing happens.** Nothing is rolled while the player is:
- indoors;
- in a film;
- under the loading curtain;
- in a conversation;
- in a fight;
- travelling by Hearthstone;
- escorting a quest's person;
- in a style's tutorial quest.

A quest can hush the roads with the flag `road_life/hush`, and code with `RoadLife.instance.hush(reason)`.

**Where nothing stands.** Nothing is stood up:
- within a settlement's pad plus 90 m, or a place's pad plus 15 m;
- within 60 m of a Hearthstone;
- nearer the player than 70 m;
- in a cell not standing;
- where the camera sees it: in the view widened by a quarter, within 320 m, and not behind the
  ground.

Ahead on the road is tried first, then behind. A place that is refused is counted in
`stats.skipped`.

**Building.** One event builds at a time, a body per slice of WorldPace's budget.

**Taking things down.** Events are taken down out of sight:
- once the player is 300 m away, or 90 m once the event is over;
- or when their cell unloads.

**Caravans.**
- A caravan stands up within 230 m of the player and is taken down past 330 m.
- It walks the game's clock while unseen: 144 real seconds to the game hour.
- Journeys are saved (`road_life` section). A load stands up the same caravans where they were,
  never twice.

**Road people.** The road's armed people are in `Perception.ROAD_GROUP`:
- the road's foes (bandits, beasts, the unquiet) hunt them, and they hunt those foes;
- they leave the player alone until struck;
- the player's summoned allies leave them alone.

## Checking your region

- `./run.sh test --filter=test_road_life`: the content check (`RoadTables.problems()`: every id,
  kind, talk and route) and the systems.
- `./run.sh roads --only=<road ids> --roadlife=on`: a headless ride on your roads. It prints a
  `ROADLIFE` line: events per km, what started, what was skipped and why, and the worst and 99th
  percentile frame. Use `--roadlife=off` for the same ride without road life, to compare.
  `captures/roads/roadlife_on.json` has the detail.

## Known limits

- **Unarmed people cannot be hurt.** `RoadFolk` (pilgrims, the lost, the runaway, the carter by
  his cart) are Npc bodies, which have no hurtbox. Anybody who should be attackable is written as an
  `enemy`.
- **Features need the land.** `pass` and `woods` are read from heights and paint, so they only exist
  with a world. Unit tests have only `bend` and `bridge`.
- **Carts are moved, not driven.** A cart follows the road's line and tilts to the ground; its
  wheels do not turn.
- **Transient events are not saved.** A load begins with none; only the caravans' journeys persist.
