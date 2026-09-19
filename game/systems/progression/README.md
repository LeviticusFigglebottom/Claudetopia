# systems/progression — skills, levels, perks

**Purpose.** Improve by doing (DESIGN §5.6): use grants skill XP, skill levels buy character
levels, each level grants one attribute point and one perk point, and every perk, potion and worn
item ends up as a number other systems can query.

It also owns **what sayings the character knows** (DESIGN §5.3), for the same reason it owns
skills: a saying is something the character learned, not something they are carrying. The list
rides with the `progression` save section, survives death and respawn, and is the only authority
on what may be cast — see DECISIONS.md.

## Files

| File | What it is |
|---|---|
| `skills.gd` | `Skills` (RefCounted, pure): the sixteen skill levels, the `40 · 1.12^level` curve, diminishing returns, shared XP (Calling ↔ Mending), `total_gains`. |
| `leveling.gd` | `Leveling` (RefCounted, pure): character level from `10L + 5L²` gains, attributes (Vigour/Endurance/Will) and the derived pools. |
| `perks.gd` | `Perks` (RefCounted, pure): taken perks, availability rules, perk → modifier lists. |
| `modifiers.gd` | `Modifiers` (RefCounted): named sources of `{stat, mult|add}`, aggregated into `get_mult(key)` / `get_add(key)`. |
| `progression.gd` | `Progression` (Node): owns the four above, registers the save section, listens to `EventBus.skill_used`, applies Callings. |

## Data read

* `core:skill/*` — `{name, group, governs, description, shares_xp_with?}`.
* `core:perk/*` — `{name, skill, requires_level, requires_perk?, effects: [{stat, mult|add}], description}`.
* `core:calling/*` — `{name, skill_bonuses, signature_item, starting_items, starting_reputation, starting_marks, starting_spells?, description}`.
* `core:spell/*` — read for the sayings listing (school, cost, cast time, effects, description).
* `core:book/*` — `teaches_spell?`: a book with a working in it teaches that saying the first
  time it is opened, wherever it is opened.

## Formulas (normative, DESIGN §5.6 and §5.3)

```
XP from skill level L to L+1 = 40 · 1.12^L        (Skills.xp_for_level)
awarded XP                   = xp · learn_rate · gain_multiplier(level)
gain_multiplier              = 1.0 at level 5 → 0.35 at level 100 (linear)
character level L needs        sum_skill_gains ≥ 10(L−1) + 5(L−1)²
max HP  = 100 + 10·Vigour      max stamina = 100 + 8·Endurance
max mana = 60 + 6·Will         load        = 60 + 4·Endurance
```
Skills start at 5 and cap at 100; a Calling adds +10 to three of them without granting levels.
Every derived pool is passed through `Modifiers`, so perks (`max_stamina`, `carry_capacity`) and
worn gear change them.

## Signals

Emitted on `EventBus`: `skill_level_up(skill_id, level)`, `level_up(level)`,
`attribute_raised(attribute, value)`, `perk_taken(perk_id)`, `spell_learned(spell_id)`.
Local: `skills_changed`, `level_changed(level)`, `points_changed(attribute_points, perk_points)`,
`sayings_changed`.
Consumed: `EventBus.skill_used(skill_id, xp)` — combat, crafting, stealth and speech all just emit
this, and nothing needs a reference to this node; `EventBus.book_opened(book_id)` — a book whose
def carries `teaches_spell` teaches it, and re-reading says so rather than doing nothing.

## Save section

**`progression`** — `{calling, skills{levels, progress, uses, total_gains}, leveling{...},
perks{taken}, known_spells[]}`. Registered by `Progression._ready()`. A save from before
`known_spells` existed loads with nothing known; `Migrations._v2_to_v3` carries over whatever
saying that character had readied, which is the only evidence such a save holds.

## Finding this node

Group **`progression`**: `get_tree().get_first_node_in_group("progression")`, or
`Progression.of(get_tree())`.

## Public API (short)

```gdscript
# Progression (the node)
award(skill, xp) -> int                      # skill levels gained; usually reached via EventBus
skill_level(skill) -> int                    skill_progress(skill) -> float   # 0..1
skills() -> Array[Dictionary]                # {id, name, level, progress, xp, xp_needed, uses, ...}
perks_for(skill := "") -> Array[Dictionary]  # {id, name, description, requires_level, taken, available, blocker}
take_perk(perk_id) -> bool                   grant_perk(perk_id) -> bool      has_perk(id) -> bool
spend_attribute("vigour"|"endurance"|"will") -> bool
level: int   attribute_points: int   perk_points: int   attribute(name) -> int
level_progress() -> float                    summary() -> Dictionary
max_health() / max_stamina() / max_mana() / load_capacity() -> float
effective_skill(skill) -> float              # trained level + fortify effects
apply_calling(id, inventory := null) -> bool Progression.callings() -> Array

# sayings (DESIGN §5.3) — mirrors Crafting's known_recipes
learn_spell(spell_id) -> bool                # false when already known or not a spell
knows_spell(spell_id) -> bool                forget_spell(spell_id) -> bool
known_spells: Array[String]                  # sorted; what the caster is allowed to say
spells() -> Array[Dictionary]                # {id, name, school, school_name, cast_type, cost,
                                             #  base_cost, cast_time, range, radius, duration,
                                             #  skill_level, description, effects} for the screen
mods: Modifiers                              # get_mult(key) / get_add(key) / apply(key, base)

# Modifiers (used by every other system)
set_source(name, [{stat, mult|add}])   clear_source(name)   get_mult(stat) -> float
get_add(stat) -> float                 apply(stat, base) -> float    scale(stat, base) -> float
explain(stat) -> Array[Dictionary]     snapshot() -> Dictionary
```

## Modifier stat keys the core perks use

`damage_one_handed`, `damage_two_handed`, `damage_archery`, `poise_damage_one_handed`,
`stamina_cost_light`, `stamina_cost_heavy`, `stamina_cost_dodge`, `poise_max`, `max_stamina`,
`carry_capacity`, `dodge_iframes`, `armour`, `block_stability`, `parry_window`, `noise`,
`pickpocket_chance`, `sneak_attack_mult`, `prices_buy`, `prices_sell`, `renown_gain`,
`potion_potency`, `poison_potency`, `ingredient_yield`, `temper_bonus`, `smithing_material_cost`,
`enchant_charge`, `enchant_magnitude`, `bow_draw_speed`, `arrow_recovery`, `weight_class_penalty`,
`mote_yield`, `spell_cost_kindling`, `spell_cost_hush`, `spell_power_mending`,
`spell_duration_binding`, `spell_duration_calling`. Fortify effects add `skill_<name>` and the
attribute keys `vigour`, `endurance`, `will`.

A system that wants a perk to matter reads it: `mods.scale("stamina_cost_light", 18.0)`.
