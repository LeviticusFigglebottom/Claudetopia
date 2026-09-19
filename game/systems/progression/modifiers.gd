class_name Modifiers
extends RefCounted
## Aggregates stat modifiers from any number of sources (perks, equipment, potions, enchantments)
## so other systems can ask one question: `get_mult("stamina_cost_light")` or `get_add("armour")`.
##
## A modifier is a small Dictionary: {"stat": key, "mult": x} and/or {"stat": key, "add": x}.
## Multipliers from different sources multiply together; additions sum. Sources are named, so a
## system can replace its whole contribution in one call (`set_source("equipment", [...])`)
## without knowing what else is registered.
##
## Stat keys used by the core pack's perks: damage_one_handed, damage_two_handed, damage_archery,
## poise_damage_one_handed, stamina_cost_light, stamina_cost_heavy, stamina_cost_dodge, poise_max,
## max_stamina, carry_capacity, dodge_iframes, armour, block_stability, parry_window, noise,
## pickpocket_chance, sneak_attack_mult, prices_buy, prices_sell, renown_gain, potion_potency,
## poison_potency, ingredient_yield, temper_bonus, smithing_material_cost, enchant_charge,
## enchant_magnitude, bow_draw_speed, arrow_recovery, weight_class_penalty, mote_yield,
## spell_cost_kindling, spell_cost_hush, spell_power_mending, spell_duration_binding,
## spell_duration_calling, luck.

signal changed

var _sources: Dictionary = {}   # source name -> Array[Dictionary]
var _mults: Dictionary = {}     # stat -> float (cache)
var _adds: Dictionary = {}      # stat -> float (cache)
var _dirty := true


## Replaces everything a source contributes. Pass [] to clear it.
func set_source(source: String, mods: Array) -> void:
	if mods.is_empty():
		_sources.erase(source)
	else:
		var clean: Array[Dictionary] = []
		for m in mods:
			if typeof(m) == TYPE_DICTIONARY and m.has("stat"):
				clean.append(m)
		_sources[source] = clean
	_dirty = true
	changed.emit()


func add_source(source: String, mods: Array) -> void:
	var existing: Array = _sources.get(source, [])
	set_source(source, existing + mods)


func clear_source(source: String) -> void:
	set_source(source, [])


func clear_all() -> void:
	_sources.clear()
	_dirty = true
	changed.emit()


func sources() -> Array[String]:
	var out: Array[String] = []
	for s in _sources:
		out.append(str(s))
	out.sort()
	return out


func _rebuild() -> void:
	_mults.clear()
	_adds.clear()
	for source in _sources:
		for m in _sources[source]:
			var stat := str(m.get("stat", ""))
			if stat == "":
				continue
			if m.has("mult"):
				_mults[stat] = float(_mults.get(stat, 1.0)) * float(m["mult"])
			if m.has("add"):
				_adds[stat] = float(_adds.get(stat, 0.0)) + float(m["add"])
	_dirty = false


func _ensure() -> void:
	if _dirty:
		_rebuild()


## Product of every multiplier on a stat (1.0 when none).
func get_mult(stat: String) -> float:
	_ensure()
	return float(_mults.get(stat, 1.0))


## Sum of every addition to a stat (0.0 when none).
func get_add(stat: String) -> float:
	_ensure()
	return float(_adds.get(stat, 0.0))


## The usual combination: (base + add) * mult.
func apply(stat: String, base: float) -> float:
	return (base + get_add(stat)) * get_mult(stat)


## mult only, for costs and rates whose base already includes everything additive.
func scale(stat: String, base: float) -> float:
	return base * get_mult(stat)


func has(stat: String) -> bool:
	_ensure()
	return _mults.has(stat) or _adds.has(stat)


## Every stat touched, with its aggregate: {stat: {mult, add}}.
func snapshot() -> Dictionary:
	_ensure()
	var out := {}
	for stat in _mults:
		out[stat] = {"mult": _mults[stat], "add": _adds.get(stat, 0.0)}
	for stat in _adds:
		if not out.has(stat):
			out[stat] = {"mult": 1.0, "add": _adds[stat]}
	return out


## Where a stat's modifiers come from: [{source, mult?, add?}], for a tooltip.
func explain(stat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for source in _sources:
		for m in _sources[source]:
			if str(m.get("stat", "")) == stat:
				var e := {"source": str(source)}
				if m.has("mult"):
					e["mult"] = float(m["mult"])
				if m.has("add"):
					e["add"] = float(m["add"])
				out.append(e)
	return out
