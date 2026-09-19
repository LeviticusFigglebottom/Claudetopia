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
| `property_sign.gd/.tscn` | `StaticBody3D` | A "for sale" board outside a house |
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

## Data it reads

* `core:table/stock_*` (`role: merchant_stock`) — rows
  `{item, count: [min, max], restock_hours, chance?}`. Five ship in core:
  `stock_general`, `stock_smith`, `stock_alchemist`, `stock_innkeeper`,
  `stock_fishmonger`.
* `npc` defs' `merchant{stock, marks, buys[]}` block (CONTRACTS §7).
* Deed items `core:item/deed_*` with a `property{place, interior, name, price,
  rent, key, storage, bed}` block. Six ship in core (Merrowby ×2, Tollmere,
  Isseva, Kharrow Hold, Grandfather Hollow).
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
PropertyRegistry.all_deeds() / deeds_at(place_id) / rent_per_day(id)

Jobs.board_offers(place_id, count, day) -> Array[Dictionary]
Jobs.delivery_pay(distance_m) / station_pay(kind, skill, rng) / complete(job, worker)
JobBoard: interact(actor) -> jobs; take(index, actor); deliver(job, actor, at_place)
JobStation: interact(actor) -> bool; finish(actor) -> marks; is_ready()
```

## Signals

Emitted: `EventBus.transaction(merchant_id, item_id, count, price, bought)`,
`property_purchased(property_id)`, `job_completed(job_id, pay)`,
`skill_used(skill, xp)`, `marks_changed`, `dialogue_started` (trade and
stewards), `quest_started` (board jobs), `notify(...)`.
Own: `EconomyService.trade_requested(merchant)` — the UI stream's cue to open a
trade screen; `Merchant.traded/refused/stock_changed`;
`PropertyRegistry.purchased/rent_collected/let_changed`;
`JobBoard.jobs_listed/job_taken`; `JobStation.started/finished`.

Consumed: `EventBus.hour_changed` (restock, merchant purses), `new_day` (rent).

## Save sections

* `economy` — `{merchants: {merchant_id: {stock, marks, next_restock, disposition}}}`.
  A despawned shopkeeper keeps their shelves; they are restored on respawn.
* `property` — `{owned: {deed_id: {bought_day, let, rent_owed_day, furnishings}}}`.
  Loading re-marks the interior, door, chest and bed as the player's in the
  ownership registry.

## Notes for other streams

* Currency goes through `Purse`, which uses the inventory stream's
  `marks` / `add_marks` / `remove_marks` when an inventory is present and falls
  back to `GameState.counters["marks"]` when it is not, so trade works in tests
  and before the player exists.
* Job boards ask the quest system for `generate(region_id, count)` and normalise
  whatever comes back; with no quest system they generate their own deliveries
  between settlements of the region.
