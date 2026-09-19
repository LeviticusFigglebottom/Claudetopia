# systems/inventory — items, equipment, loot

**Purpose.** Everything an actor carries, wears, wields, finds or drops: stacks and weight
(DESIGN §5.7), the paper-doll slots, deterministic loot tables, world pickups and containers.

## Files

| File | What it is |
|---|---|
| `item_stack.gd` | `ItemStack` (RefCounted): one stack = item id + count + per-instance `data` (temper, enchant, brewed effects). Reads the item def; applies temper to weapon/armour blocks. |
| `inventory.gd` | `Inventory` (Node): stacks, marks, weight/capacity, add/remove/query/sort, use, drop, transfer, save. |
| `equipment.gd` | `Equipment` (Node): the thirteen slots, equip rules, aggregated armour/stability/weight class/modifiers. |
| `loot_table.gd` | `LootTable` (static, pure): weighted rolls with conditions, ranges, nesting and guaranteed entries. |
| `world_item.gd/.tscn` | `WorldItem` (StaticBody3D): a pickup in the world; group `interactable`, `interact(actor)` / `prompt_text()`. |
| `container.gd/.tscn` | `WorldContainer` (StaticBody3D): a chest with an Inventory, an owner, a loot table rolled on first opening, optional respawn and locks. |
| `loot_drops.gd` | `LootDrops` (Node): listens to `entity_killed` and spawns a dead thing's loot and marks. Add one to the world or an arena; it is not an autoload. |

## Data read

* `core:item/*` — CONTRACTS §7 shape. Extra keys this system uses: `stack`, `tags`,
  `material` (what tempering consumes), `ranged.ammo`, `light`, `ember.charge`, `model`,
  `reads` (the `core:book/*` this item opens; `use()` routes it to `read()`, which emits
  `EventBus.book_opened` and leaves the book in the bag — a spell tome teaches from there).
* `core:loot/*` — `{rolls, entries[], guaranteed[]}`; see the header of `loot_table.gd`.
* `core:enemy/*` — `loot` (a loot id) and `marks` ([min, max]), read by `LootDrops`.
* `core:effect/*` — an item's `effects[]` and its enchantment turn into modifiers through each
  effect def's `modifier` block.

## Signals

Emitted on `EventBus` (only for the player's bag, `is_player`):
`item_acquired`, `item_removed`, `item_used(item_id, effects)`, `item_equipped(slot, item_id)`,
`marks_changed(total, delta)`, `container_opened(container, actor)`.

Local signals for screens: `Inventory.changed`, `stack_added`, `stack_removed`, `stack_changed`,
`marks_changed`, `item_used`; `Equipment.changed(slot)`; `WorldContainer.opened` / `looted`;
`WorldItem.picked_up`; `LootDrops.dropped`.

Consumed: `EventBus.entity_killed` (LootDrops), `EventBus.game_loaded` (containers).

## Save sections

The player's bag and paper-doll are serialised by whoever owns them (the player actor registers
`inventory` and `equipment` with `SaveSystem`, passing these nodes' `to_save()`/`from_save()`).
Containers keep their own shared section, **`containers`**, registered automatically the first
time a `WorldContainer` enters the tree; it is keyed by `container_id` so a chest emptied on one
side of the map is still empty after streaming or loading.

## Finding these nodes from another system

The player's bag is in group **`inventory`**, the paper-doll in group **`equipment`**. A bag whose
actor is in group `player` joins on its own; otherwise set `is_player = true`. Nothing else joins,
so `get_tree().get_first_node_in_group("inventory")` is always the player's.

## Public API (short)

```gdscript
# Inventory
add(item_id, count := 1, data := {}) -> ItemStack      remove(item_id, count := 1, data_filter := {}) -> int
read(item) -> bool                                     # opens the book an item `reads`; never consumes it
remove_stack(stack, count := -1) -> int                has(item_id, count := 1) -> bool
count(item_id) -> int                                  items() -> Array[Dictionary]
stacks() -> Array[ItemStack]                           find(uid) / find_first(item_id) -> ItemStack
query({category|tag|tags_any|tags_all|equippable|consumable|weapon_class|armour_slot|name_contains})
by_category(c) / by_tag(t)                             sort("category"|"name"|"weight"|"value")
weight() -> float   capacity() -> float   load_fraction() -> float   is_overloaded() -> bool
marks: int   add_marks(n)   remove_marks(n) -> int   take_all_marks() -> int   can_afford(n) -> bool
use(item) -> bool   drop(item, count := 1) -> Node     transfer_to(other, item, count := -1) -> int
transfer_all_to(other) -> int                          to_save() / from_save(d)
Inventory.for_actor(actor) -> Inventory                Inventory.player_bag(tree) -> Inventory

# Equipment  (slots: main_hand off_hand head body hands feet ring_1 ring_2 amulet quick_1..4)
equip(item, slot := "") -> bool   unequip(slot) -> ItemStack   can_equip(stack, slot) -> {ok, reason}
slots() -> Dictionary  (slot -> item id or "")         get_slot(slot) -> ItemStack
armour_total() -> float   stability() -> float   weight_class() -> "light|medium|heavy"
main_weapon() -> Dictionary   modifiers() -> Array[Dictionary]   summary() -> Dictionary
bind_quick(slot, item_id) / use_quick(slot) -> bool     to_save() / from_save(d)

# LootTable (static, pure)
LootTable.roll(table, rng, context := {}) -> Array[Dictionary]      # [{item, count} | {marks}]
LootTable.roll_merged(table, rng, context) -> Array[Dictionary]
LootTable.default_context() -> {region, level, luck, flags, quests}

# WorldItem / WorldContainer / LootDrops
world_item.setup(item_id, count, data, marks)   interact(actor) -> bool   prompt_text() -> String
container.interact(actor) -> bool   take_all(actor) -> int   unlock()   ensure_loot()
loot_drops.drops_for(enemy_def, ctx) -> Array   spawn_drops(results, pos, parent) -> Array[Node]
```

## Rules worth knowing

* Equipped items stay **in the bag**: weight counts once, and selling or dropping one clears the
  slot by itself. Slots hold a stack's `uid`, so a save restores exactly the piece you wore.
* Two-handed means clip set `2H`, `bow` or `staff`: equipping one clears the off hand, and
  equipping an off-hand item clears a two-handed main weapon.
* Stacks merge only when their `data` is identical, so a tempered sword, an enchanted sword and a
  plain one never blur together, and no two brews of different strength do either.
* A loot roll with the same rng seed, table and context always gives the same drops.
