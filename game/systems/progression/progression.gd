class_name Progression
extends Node
## The node that owns Skills, Leveling, Perks and the Modifiers aggregation, registers the
## "progression" save section and listens to EventBus.skill_used.
##
## Add one as a child of the player (or of the world for a headless test). It joins the
## "progression" group, so other systems find it without a node path:
##     var prog := get_tree().get_first_node_in_group("progression")
##     prog.skill_level("one_handed"); prog.mods.get_mult("stamina_cost_light")
##
## Signals it emits on EventBus: skill_level_up, level_up, attribute_raised, perk_taken.
## Derived pools (max HP/stamina/mana, load capacity) come from attributes and are passed
## through the modifier stack, so perks and worn gear change them.

signal skills_changed
signal level_changed(new_level: int)
signal points_changed(attribute_points: int, perk_points: int)

const GROUP := "progression"
const SAVE_SECTION := "progression"
const CALLING_TYPE := "calling"

@export var listen_to_event_bus: bool = true
## Global multiplier on awarded skill XP (difficulty, debug).
@export var learn_rate: float = 1.0

var skills := Skills.new()
var leveling := Leveling.new()
var perks := Perks.new()
var mods := Modifiers.new()
var calling_id: String = ""


func _ready() -> void:
	add_to_group(GROUP)
	_refresh_perk_modifiers()
	SaveSystem.register(SAVE_SECTION, self)
	if listen_to_event_bus and not EventBus.skill_used.is_connected(_on_skill_used):
		EventBus.skill_used.connect(_on_skill_used)


func _exit_tree() -> void:
	if EventBus.skill_used.is_connected(_on_skill_used):
		EventBus.skill_used.disconnect(_on_skill_used)
	if SaveSystem.participants.get(SAVE_SECTION) == self:
		SaveSystem.unregister(SAVE_SECTION)


# --- character creation ------------------------------------------------------------------

## Applies a Calling (core:calling/*): skill bonuses and starting reputations; the signature and
## starting items are handed to `inventory` when one is given, and marks with them.
## Returns false for an unknown calling.
func apply_calling(id: String, inventory: Inventory = null) -> bool:
	var def := ContentDB.get_or_empty(id)
	if def.is_empty():
		Log.error("Progression", "unknown calling '%s'" % id)
		return false
	calling_id = id
	skills.apply_bonuses(def.get("skill_bonuses", {}))
	for faction in def.get("starting_reputation", {}):
		EventBus.faction_reputation_changed.emit(str(faction), int(def["starting_reputation"][faction]), int(def["starting_reputation"][faction]))
	if inventory != null:
		var signature := str(def.get("signature_item", ""))
		if signature != "" and ContentDB.has(signature):
			inventory.add(signature, 1)
		for entry in def.get("starting_items", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var item := str(entry.get("item", ""))
			if ContentDB.has(item):
				inventory.add(item, int(entry.get("count", 1)))
		inventory.add_marks(int(def.get("starting_marks", 0)))
	skills_changed.emit()
	return true


## Every calling, for the character-creation screen.
static func callings() -> Array:
	return ContentDB.all(CALLING_TYPE)


func reset_for_new_game() -> void:
	skills.reset()
	leveling.reset()
	perks.reset()
	calling_id = ""
	_refresh_perk_modifiers()
	skills_changed.emit()
	level_changed.emit(leveling.level)
	points_changed.emit(leveling.attribute_points, leveling.perk_points)


# --- skill use ---------------------------------------------------------------------------

func _on_skill_used(skill_id: String, xp: float) -> void:
	award(skill_id, xp)


## Grants skill XP, levels the skill up and, through the gain total, the character.
## Returns the skill levels gained.
func award(skill: String, xp: float) -> int:
	var id := Skills.normalise(skill)
	if id == "":
		Log.warn("Progression", "unknown skill '%s'" % skill)
		return 0
	var gained := skills.add_xp(id, xp, learn_rate)
	if gained > 0:
		EventBus.skill_level_up.emit(id, skills.level(id))
	skills_changed.emit()
	if gained > 0:
		_check_level_up()
	return gained


func _check_level_up() -> void:
	var levels := leveling.update_from_gains(skills.total_gains)
	if levels <= 0:
		return
	level_changed.emit(leveling.level)
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
	EventBus.level_up.emit(leveling.level)


# --- reading -----------------------------------------------------------------------------

var level: int:
	get:
		return leveling.level

var attribute_points: int:
	get:
		return leveling.attribute_points

var perk_points: int:
	get:
		return leveling.perk_points


func skill_level(skill: String) -> int:
	return skills.level(skill)


func skill_progress(skill: String) -> float:
	return skills.fraction(skill)


## [{id, name, level, progress, ...}] for the skills screen.
func skills_list() -> Array[Dictionary]:
	return skills.summaries()


func attribute(name: String) -> int:
	return leveling.attribute(name)


func level_progress() -> float:
	return Leveling.fraction_for(skills.total_gains)


# --- derived pools (attributes through the modifier stack) -------------------------------

func max_health() -> float:
	return mods.apply("max_health", Leveling.max_health_for(_attr_with_mods("vigour")))


func max_stamina() -> float:
	return mods.apply("max_stamina", Leveling.max_stamina_for(_attr_with_mods("endurance")))


func max_mana() -> float:
	return mods.apply("max_mana", Leveling.max_mana_for(_attr_with_mods("will")))


## Carry capacity, read by Inventory.capacity().
func load_capacity() -> float:
	return mods.apply("carry_capacity", Leveling.load_capacity_for(_attr_with_mods("endurance")))


func _attr_with_mods(name: String) -> int:
	return int(round(mods.apply(name, float(leveling.attribute(name)))))


## Effective skill level for damage and cost formulas: the trained level plus fortify effects.
func effective_skill(skill: String) -> float:
	var id := Skills.normalise(skill)
	if id == "":
		return 0.0
	return mods.apply("skill_" + Ids.name_of(id), float(skills.level(id)))


## Everything a HUD or character screen needs in one call.
func summary() -> Dictionary:
	var d := leveling.summary(skills.total_gains)
	d["calling"] = calling_id
	d["calling_name"] = str(ContentDB.get_or_empty(calling_id).get("name", ""))
	d["total_gains"] = skills.total_gains
	d["max_health"] = max_health()
	d["max_stamina"] = max_stamina()
	d["max_mana"] = max_mana()
	d["load_capacity"] = load_capacity()
	return d


# --- spending ----------------------------------------------------------------------------

## Spends one attribute point on "vigour", "endurance" or "will".
func spend_attribute(name: String) -> bool:
	if not leveling.spend_attribute(name):
		return false
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
	EventBus.attribute_raised.emit(name, leveling.attribute(name))
	return true


## Takes a perk, spending one perk point. False when unavailable or unaffordable.
func take_perk(perk_id: String) -> bool:
	if leveling.perk_points <= 0:
		return false
	if not perks.can_take(perk_id, skills):
		return false
	if not leveling.spend_perk_point():
		return false
	perks.take(perk_id, skills)
	_refresh_perk_modifiers()
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
	EventBus.perk_taken.emit(perk_id)
	return true


## Gives a perk without spending a point (quest reward, console).
func grant_perk(perk_id: String) -> bool:
	if not perks.can_take(perk_id, skills):
		return false
	perks.take(perk_id, skills)
	_refresh_perk_modifiers()
	EventBus.perk_taken.emit(perk_id)
	return true


## Perk trees for the perks screen. Empty skill = every perk.
func perks_for(skill: String = "") -> Array[Dictionary]:
	var id := Skills.normalise(skill) if skill != "" else ""
	return perks.summaries(id, skills)


func has_perk(perk_id: String) -> bool:
	return perks.has(perk_id)


func _refresh_perk_modifiers() -> void:
	mods.set_source("perks", perks.modifiers())


## Convenience for other systems: Progression.of(tree).mods.get_mult("...").
static func of(tree: SceneTree) -> Progression:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as Progression


# --- save --------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"calling": calling_id, "skills": skills.to_save(), "leveling": leveling.to_save(),
		"perks": perks.to_save(),
	}


func from_save(d: Dictionary) -> void:
	calling_id = str(d.get("calling", ""))
	skills.from_save(d.get("skills", {}))
	leveling.from_save(d.get("leveling", {}))
	perks.from_save(d.get("perks", {}))
	_refresh_perk_modifiers()
	skills_changed.emit()
	level_changed.emit(leveling.level)
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
