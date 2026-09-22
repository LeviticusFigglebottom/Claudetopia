# systems/economy — prices, merchants, property, jobs

Marks changing hands. DESIGN.md §5.14, with the ±25% standing swing of §5.11.

## Files

| File | Kind | What it is |
|---|---|---|
| `pricing.gd` | pure (`static`) | The price formula and its four modifiers |
| `purse.gd` | pure (`static`) | Marks on any actor, duck-typed against the inventory stream |
| `merchant.gd` | Node | One shopkeeper: stock, marks pool, buy/sell, restock |
| `economy_service.gd` | Node, group `economy` | Merchant states across cell loads; `trade_requested`; save section |
| `property.gd` | Node, group `property` | Deeds, keys, storage, beds, letting and rent |
| `property_sign.gd/.tscn` | `StaticBody3D` | A board outside a house: for sale, or the landlord's side once it is yours |
| `jobs.gd` | pure (`static`) | Station work table and radiant delivery generation |
| `job_board.gd/.tscn` | `StaticBody3D` | A charter-board listing the day's work |
| `job_station.gd/.tscn` | `StaticBody3D` | Chop, smith, brew, fish, dig: a timed shift |

## The price

```
price = base · region_mod · supply_mod · disposition_mod · (1.3 − Speech/300)
```

* `region_mod` — the region def's `price_mod` (default 1.0, clamped 0.5–2.0).
* `supply_mod` — 1.4 when out of stock falling to 0.75 at eight or more.
* `disposition_mod` — `1 − disposition/400`, ±25% at the extremes, plus the
  shopkeeper's personality bias (greedy +10%, generous −10%) and a Hollow
  penalty. Disposition comes from renown tier, morality tier, faction rank and
  how much you have traded here before.
* Speech runs the mark-up from 1.3 down to 1.0 at skill 90.

Selling pays `base · 0.45 · region · supply / (disposition · speech)` — the last
two terms invert, so a merchant who likes you both charges less and pays more.
Bulk trades are priced a unit at a time, so scarcity moves as the shelf empties.

**Property** is quoted differently: a deed's `price` is a posted ceiling that
standing and Speech bargain *down*, never below three-quarters.

**Furnishings** are not quoted at all: a rug costs what the rug costs. They are
bought from the landlord's side of the deed screen — the board outside a house
you own, where the rent waiting, the letting and the furnishings on offer are
each their own button — and they do not go in the bag. They are recorded against
the deed, and `HouseInterior` puts them in the rooms when that house is built.

## Data it reads

* `core:table/stock_*` (`role: merchant_stock`) — rows
  `{item, count: [min, max], restock_hours, chance?}`. Five ship in core:
  `stock_general`, `stock_smith`, `stock_alchemist`, `stock_innkeeper`,
  `stock_fishmonger`.
* `npc` defs' `merchant{stock, marks, buys[]}` block (CONTRACTS §7).
* Deed items `core:item/deed_*` with a `property{place, interior, name, price,
  rent, key, storage, bed}` block. Six ship in core (Merrowby ×2, Tollmere,
  Isseva, Kharrow Hold, Grandfather Hollow).
* Furnishing items `core:item/furnishing_*`: `misc`, tagged `furnishing`, with a
  `furnishing{prop, room?, spot?, storage?}` block (CONTRACTS §7). Six ship in
  core — a hearth rug, bed hangings, a settle chair, a shelf of jars, a book
  press and a banded oak chest. `prop` is a prop *kind* `PropLibrary` resolves
  rather than an asset path, so your rug is woven out of whatever cloth the
  region's forge built. The item's `value` is the price: there is no haggling on
  a rug, and a furnishing never enters the bag — it rides in the `property` save
  section under the deed that bought it.
* Items referenced by the stock tables are all `core:item/econ_*`, defined by
  this stream, so nothing dangles while the inventory stream adds its own.

## Public API

```gdscript
Pricing.buy_price(base, region_id, stock, disposition, speech, personality_bias, hollow)
Pricing.sell_price(...)  Pricing.bulk(..., direction) -> {total, unit_prices}
Pricing.disposition_for(profile, faction_rank, stored) -> int

Purse.balance(actor) / can_pay(actor, n) / pay(actor, n) -> bool / give(actor, n)

Merchant: m.buy(player, item_id, count) / m.sell(player, item_id, count)
          -> {ok, reason, price, count}
          m.count(item_id) / m.items() / m.buy_price_of(id) / m.sell_price_of(id)
          m.will_buy(id) / m.refuses_trade() / m.restock_all(force)
          m.open_trade(player)            # -> EconomyService.trade_requested

EconomyService.ensure() -> EconomyService  # group "economy"
PropertyRegistry.ensure() -> PropertyRegistry
reg.buy(player, deed_id, seller_faction) -> {ok, reason, price}
reg.is_owned(id) / owns_bed(bed_id) / storage_ids() / asking_price(id)
reg.set_let(id, bool) / rent_due(id) / collect_rent(player) / add_furnishing(id, item)
reg.buy_furnishing(player, deed_id, item_id) -> {ok, reason, price}
reg.furnishings(deed_id) -> Array / property_for_interior(interior_key) -> deed id
PropertyRegistry.all_furnishings() / furnishing_block(item) / furnishing_price(item)
PropertyRegistry.all_deeds() / deeds_at(place_id) / rent_per_day(id)

Jobs.board_offers(place_id, count, day) -> Array[Dictionary]
Jobs.normalise_offer(quest_def) -> Dictionary     # a quest def as a board row
Jobs.delivery_pay(distance_m) / station_pay(kind, skill, rng) / complete(job, worker)
JobBoard: interact(actor) -> jobs; take(index, actor); deliver(job, actor, at_place)
          has_taken(job_id); taken (parcels in hand); accepted (board quests taken)
JobStation: interact(actor) -> bool; finish(actor) -> marks; is_ready()
```

## Signals

Emitted: `EventBus.transaction(merchant_id, item_id, count, price, bought)`,
`property_purchased(property_id)`, `job_completed(job_id, pay)`,
`skill_used(skill, xp)`, `marks_changed`, `dialogue_started` (trade and
stewards), `quest_started` (board jobs), `notify(...)`.
Own: `EconomyService.trade_requested(merchant)` — the UI stream's cue to open a
trade screen; `Merchant.traded/refused/stock_changed`;
`PropertyRegistry.purchased/rent_collected/let_changed/furnished`;
`JobBoard.jobs_listed/job_taken`; `JobStation.started/finished`.

Consumed: `EventBus.hour_changed` (restock, merchant purses), `new_day` (rent).

## Save sections

* `economy` — `{merchants: {merchant_id: {stock, marks, next_restock, disposition}}}`.
  A despawned shopkeeper keeps their shelves; they are restored on respawn.
* `property` — `{owned: {deed_id: {bought_day, let, rent_owed_day, furnishings}}}`.
  Loading re-marks the interior, door, chest and bed as the player's in the
  ownership registry. `furnishings` is a list of item ids, which is all a
  furnishing is once bought: `HouseInterior.dress_furnishings()` reads it when it
  builds a house `property_for_interior()` says is yours, and derives the spot
  from the room rather than storing one, so the same rug is in the same corner
  every time you come home without a position in the save file.

## Notes for other streams

* Currency goes through `Purse`, which uses the inventory stream's
  `marks` / `add_marks` / `remove_marks` when an inventory is present and falls
  back to `GameState.counters["marks"]` when it is not, so trade works in tests
  and before the player exists.
* Job boards ask the social façade for the day's radiant work
  (`Social.board_jobs(place, region, count)`) and normalise whatever comes back
  to the delivery row shape, so the board and its screen do not care which they
  got; with no quest system at all they generate their own parcel deliveries
  between settlements of the region. A board quest is accepted through
  `Social.take_quest()`, which answers whether it took — a notice that cannot be
  started says so and is not announced. `board_offers` used to ask the quest-log
  participant for a `generate()` method that `QuestLog` does not have, so every
  board in the game fell through to deliveries and the radiant layer never
  reached a notice post; the duck-typed hook is still tried first, for tests.
