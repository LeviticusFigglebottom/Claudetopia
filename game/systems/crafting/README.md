# systems/crafting — smithing, alchemy, enchanting

**Purpose.** DESIGN §5.8: forge and temper gear, discover what ingredients do and brew them, learn
notes by disenchanting and write them into gear with Ember Motes.

## Files

| File | What it is |
|---|---|
| `smithing.gd` | `Smithing` (static, pure): recipes, material cost, skill gates, tempering (+10% per tier). |
| `alchemy.gd` | `Alchemy` (RefCounted): the four effects per ingredient, discovery by eating and by combining, brewing 2–3 ingredients into a potion instance. |
| `enchanting.gd` | `Enchanting` (static, pure): disenchant to learn, enchant with motes, charge, `consume_charge()`, recharge. |
| `crafting.gd` | `Crafting` (Node): owns the above for one actor, holds what is known, registers the save section, awards XP. |

## Data read

* `core:recipe/*` — `{name, station, skill, requires_level, xp, known_by_default, inputs[{item, count}], output{item, count}}`.
* `core:item/*` — `alchemy.effects` (four effect ids) on ingredients; `material` (what tempering
  consumes); `core:item/ember_mote` carries `ember.charge` (25 per mote).
* `core:effect/*` — `{name, kind, magnitude_base, duration_base, potion}` for alchemy, and
  `{enchant: true, enchant_slots[], charge_cost, mote_cost}` for the notes.

## How the three crafts work

**Smithing.** A recipe consumes its inputs at a station (`forge`) and adds its output; unknown
recipes must be learned first (`learn_recipe`, or `EventBus.recipe_learned` from a quest).
Tempering raises one item's `temper` tier: +10% to damage and armour per tier (more with the Red
Door perk), costing one unit of the item's material per tier reached, capped by
`1 + smithing/15` tiers. A tempered piece splits off its stack and shows as *(Fine)*, *(Honed)*,
*(Tempered)*, *(Rung)*, *(Named)*.

**Alchemy.** Only an ingredient's first effect is known; eating reveals the next one, and a
successful combine teaches every contributing ingredient the effect it shared. Combining 2–3
ingredients keeps every effect at least two of them share; a mixture with nothing in common is
wasted. The potion is an instance of the first shared effect's content-defined template
(`core:effect/x`.`potion` → `core:item/potion_x`) carrying its own `effects`, `name` and
`quality` in the stack's `data`, so two brews never merge unless they came out identical.
Magnitude = `magnitude_base · (1 + alchemy/100) · potency modifier`.

**Enchanting.** Disenchanting destroys an enchanted item and teaches its effect id. Enchanting
writes `{effect, magnitude, duration, charge, charge_max, charge_cost}` into a stack at a
`name_table`, spending Ember Motes: motes buy magnitude (`mote_cost` per step, five steps max)
and charge (25 each). A weapon note spends `charge_cost` per blow through
`consume_charge()`; at zero it is silent until recharged with more motes. A worn note
(`charge_cost` 0) never spends anything and shows up in `Equipment.modifiers()`.

## Signals

Emitted on `EventBus`: `recipe_learned`, `enchantment_learned`, `item_crafted(recipe, item, count)`,
`item_enchanted(item_id, effect_id)`, `ingredient_effect_discovered(item_id, effect_index)`,
`item_used(item_id, effects)` (eating an ingredient), plus `skill_used` for every craft, which is
how Smithing, Alchemy and Enchanting train.
Local: `known_changed`, `crafted`, `brewed`, `enchanted`.

## Save section

**`crafting`** — `{known_recipes[], known_enchantments[], alchemy{discovered{item: [indices]}}}`.
Registered by `Crafting._ready()`. Recipes or notes that no longer exist are dropped on load.

## Finding this node

Group **`crafting`**: `get_tree().get_first_node_in_group("crafting")`, or `Crafting.of(get_tree())`.
It uses the sibling `Inventory` (or the player's bag) and, when one exists, the `progression` node
for skill levels and modifiers; everything works headless without one.

## Public API (short)

```gdscript
# Crafting (the node)
recipes_for(station) -> Array[Dictionary]   # {id, name, inputs, output, can_craft, missing, blocker}
craft(recipe_id) -> bool                    can_craft(recipe_id) -> bool
learn_recipe(id) -> bool                    knows_recipe(id) -> bool
temper(item) -> {ok, reason, tier}          temper_preview(item) -> {cost, material, max_tier, ...}
ingredients() -> Array[Dictionary]          known_effects(item_id) -> Array[String]
eat_ingredient(item_id) -> Dictionary       combine(ingredient_ids) -> {ok, item_id, effects, discovered}
enchantments() -> Array[Dictionary]         enchant_preview(effect_id, motes) -> Dictionary
enchant(item, effect_id, motes := 2) -> bool  disenchant(item) -> bool
recharge(item, motes := -1) -> bool         consume_charge(item, amount := -1.0) -> bool
learn_enchantment(effect_id) -> bool        knows_enchantment(id) -> bool

# Statics for systems that hold their own state (merchants, tests, the world)
Smithing.craft(recipe_id, inventory, skill_level, station, known, mods) -> {ok, item, count, xp}
Smithing.temper(stack, inventory, skill_level, mods) -> {ok, stack, tier, xp}
Alchemy.shared_effects(item_ids) -> Array[String]
Alchemy.brewed_magnitude(effect_id, skill_level, mods) -> {magnitude, duration}
Enchanting.consume_charge(stack, amount := -1.0, inventory := null) -> bool
Enchanting.has_charge(stack) -> bool        Enchanting.charge_fraction(stack) -> float
```

`item` above is an item id, a stack uid or an `ItemStack` — `Inventory.resolve()` sorts it out.
Every "why not" is a short reason string (`missing_materials`, `skill_too_low`, `not_known`,
`wrong_item`, `already_enchanted`, `no_shared_effect`, …) so a screen can say what is wrong.
