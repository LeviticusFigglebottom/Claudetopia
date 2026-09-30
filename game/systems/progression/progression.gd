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
## It also owns the sayings the character knows (DESIGN §5.3 "Saying"), the same way Crafting
## owns known recipes: a saved, queryable list with learn_spell / knows_spell / spells().
##
## Signals it emits on EventBus: skill_level_up, level_up, attribute_raised, perk_taken,
## spell_learned.
## Derived pools (max HP/stamina/mana, load capacity) come from attributes and are passed
## through the modifier stack, so perks and worn gear change them.

signal skills_changed
signal level_changed(new_level: int)
signal points_changed(attribute_points: int, perk_points: int)
## A saying was added to `known_spells` (the sayings screen listens to this).
signal sayings_changed
## A timed modifier (a potion, a meal) came or went.
signal modifiers_changed

const GROUP := "progression"
const SAVE_SECTION := "progression"
const CALLING_TYPE := "calling"
const SPELL_TYPE := "spell"

@export var listen_to_event_bus: bool = true
## Global multiplier on awarded skill XP (difficulty, debug).
@export var learn_rate: float = 1.0

var skill_set := Skills.new()
var leveling := Leveling.new()
var perks := Perks.new()
var mods := Modifiers.new()
## effect id -> when the timed modifier it set runs out (seconds, engine clock).
var mods_source_expiry: Dictionary = {}
var calling_id: String = ""
## The fighting style the character was taught (core:style/*, DESIGN §5.1), or "" for one named
## before styles, or on the fallback start. Saved beside the Calling.
var style_id: String = ""
## The sayings this character has been taught, sorted; the only authority on what may be cast.
var known_spells: Array[String] = []


func _ready() -> void:
	add_to_group(GROUP)
	_refresh_perk_modifiers()
	SaveSystem.register(SAVE_SECTION, self)
	if listen_to_event_bus and not EventBus.skill_used.is_connected(_on_skill_used):
		EventBus.skill_used.connect(_on_skill_used)
	if listen_to_event_bus and not EventBus.book_opened.is_connected(_on_book_opened):
		EventBus.book_opened.connect(_on_book_opened)


func _exit_tree() -> void:
	if EventBus.skill_used.is_connected(_on_skill_used):
		EventBus.skill_used.disconnect(_on_skill_used)
	if EventBus.book_opened.is_connected(_on_book_opened):
		EventBus.book_opened.disconnect(_on_book_opened)
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
	skill_set.apply_bonuses(def.get("skill_bonuses", {}))
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
	# A calling raised near Saying starts with one or two already in the mouth; the rest have
	# to be taught (a tome, a Sayer, a quest). Which is which is data, not a rule in here.
	for spell in def.get("starting_spells", []):
		learn_spell(str(spell))
	skills_changed.emit()
	return true


## Applies a fighting style (core:style/*) on top of the Calling: its skill bonuses, its kit (into
## `inventory`, and the kit's `equip` rows into `equipment`'s hands) and its sayings. A style adds
## to the Calling and never replaces it. Returns false for an unknown style.
func apply_style(id: String, inventory: Inventory = null, equipment: Object = null) -> bool:
	var def := ContentDB.get_or_empty(id)
	if def.is_empty() or Ids.type_of(id) != StyleDef.TYPE:
		Log.error("Progression", "unknown style '%s'" % id)
		return false
	style_id = id
	skill_set.apply_bonuses(def.get("skill_bonuses", {}))
	var kit: Dictionary = def.get("kit", {})
	for row_v in kit.get("items", []):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var item := str(row.get("item", ""))
		if not ContentDB.has(item):
			continue
		if inventory != null:
			inventory.add(item, int(row.get("count", 1)))
		var hand := str(row.get("equip", ""))
		if hand != "" and equipment != null and equipment.has_method("equip"):
			equipment.call("equip", item, hand)
		var quick := str(row.get("quick", ""))
		if quick != "" and equipment != null and equipment.has_method("bind_quick"):
			# the belt holds things used; a kit's weapon "on a quick key" (the ranger's knife) is
			# kept in the weapon set, a press of the cycle key from the hand
			if equipment.has_method("add_to_weapon_set") and Equipment.set_takes(item):
				equipment.call("add_to_weapon_set", item)
			else:
				equipment.call("bind_quick", quick, item)
		elif quick == "" and hand == "" and equipment != null and equipment.has_method("bind_free_quick") \
				and HeldItems.is_torch(ContentDB.get_or_empty(item)):
			# a kit's torch is on the belt as well as in the bag: a press takes it up burning, as the
			# lantern key does (Player.use_torch)
			equipment.call("bind_free_quick", item)
	for spell in kit.get("spells", []):
		learn_spell(str(spell))
	skills_changed.emit()
	return true


## Every calling, for the character-creation screen.
static func callings() -> Array:
	return ContentDB.all(CALLING_TYPE)


func reset_for_new_game() -> void:
	skill_set.reset()
	leveling.reset()
	perks.reset()
	calling_id = ""
	style_id = ""
	known_spells.clear()
	sayings_changed.emit()
	_refresh_perk_modifiers()
	skills_changed.emit()
	level_changed.emit(leveling.level)
	points_changed.emit(leveling.attribute_points, leveling.perk_points)


# --- skill use ---------------------------------------------------------------------------

func _on_skill_used(skill_id: String, xp: float) -> void:
	award(skill_id, xp)


## A book that teaches (`teaches_skill` on the book def) is worth one level of that skill, the
## first time it is read and never again. The flag it sets is also what dialogue and quests
## key on to know you have read a thing.
## A modifier with a clock on it: what a potion or a meal leaves behind. The source is the
## effect's own id, so drinking the same draught twice refreshes rather than stacks, and the
## timer is a scene-tree timer so it survives whatever else is going on.
func add_timed_modifier(source: String, added: Array, duration: float) -> void:
	mods_source_expiry[source] = Time.get_ticks_msec() * 0.001 + duration
	self.mods.set_source(source, added)
	modifiers_changed.emit()
	var timer := get_tree().create_timer(duration, false)
	# Bound to a method rather than a closure, for the reason `enemy.gd` gives about its parry
	# timer: a scene-tree timer outlives the node that asked for it, and freeing that node
	# takes a method connection with it but leaves a closure on the timer to fire into nothing.
	timer.timeout.connect(_expire_modifier.bind(source))


func _expire_modifier(source: String) -> void:
	# Another draught may have refreshed it while this timer was running.
	if float(mods_source_expiry.get(source, 0.0)) - Time.get_ticks_msec() * 0.001 > 0.05:
		return
	mods_source_expiry.erase(source)
	mods.clear_source(source)
	modifiers_changed.emit()


## Grants skill XP, levels the skill up and, through the gain total, the character.
## Returns the skill levels gained.
func award(skill: String, xp: float) -> int:
	var id := Skills.normalise(skill)
	if id == "":
		Log.warn("Progression", "unknown skill '%s'" % skill)
		return 0
	var gained := skill_set.add_xp(id, xp, learn_rate)
	if gained > 0:
		EventBus.skill_level_up.emit(id, skill_set.level(id))
	skills_changed.emit()
	if gained > 0:
		_check_level_up()
	return gained


func _check_level_up() -> void:
	var levels := leveling.update_from_gains(skill_set.total_gains)
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
	return skill_set.level(skill)


func skill_progress(skill: String) -> float:
	return skill_set.fraction(skill)


## [{id, name, level, progress, xp, xp_needed, uses, group, governs, description}] for the skills screen.
func skills() -> Array[Dictionary]:
	return skill_set.summaries()


func attribute(attr: String) -> int:
	return leveling.attribute(attr)


func level_progress() -> float:
	return Leveling.fraction_for(skill_set.total_gains)


# --- sayings (DESIGN §5.3) ----------------------------------------------------------------
#
# Known sayings live here rather than on the player actor because they are something the
# character learned, not something they are carrying: they ride with `progression` in the
# save, survive a respawn, and are readable by the sayings screen and by dialogue through
# the "progression" group, exactly as known recipes ride with `crafting`.

## A book has been opened, anywhere: out of the bag, off a shelf, through a quest. A book
## whose def carries `teaches_spell` is a tome, and the saying in it is learned the first
## time it is read. Re-reading says so rather than doing nothing in silence.
func _on_book_opened(book_id: String) -> void:
	var def := ContentDB.get_or_empty(book_id)
	var flag := "read:" + book_id
	var first_reading := not GameState.has_flag(flag)
	GameState.set_flag(flag, true)

	# A tome: the saying in it is learned the first time, and said so on any later reading,
	# because a player who re-opens one wants to know they already have it.
	var spell := str(def.get("teaches_spell", ""))
	if spell != "":
		var saying := str(ContentDB.get_or_empty(spell).get("name", spell))
		if learn_spell(spell):
			EventBus.notify.emit("You have the saying: %s." % saying, "book")
		else:
			EventBus.notify.emit("You have %s by heart already." % saying, "book")

	# A book that teaches a skill is worth one level of it, once and never again.
	if not first_reading:
		return
	var skill := Skills.normalise(str(def.get("teaches_skill", "")))
	if skill == "":
		return
	var gained := award(skill, Skills.xp_for_level(skill_set.level(skill)))
	if gained > 0:
		var skill_name := str(Skills.def(skill).get("name", Ids.name_of(skill)))
		EventBus.notify.emit("%s taught you something. %s is %d." % [str(def.get("title", "The book")), skill_name, skill_set.level(skill)], "book")


## Learns a saying (a calling, a tome, a Sayer, a quest reward). False when already known
## or when the id is not a spell in any loaded pack.
func learn_spell(spell_id: String) -> bool:
	if known_spells.has(spell_id):
		return false
	if not ContentDB.has(spell_id) or Ids.type_of(spell_id) != SPELL_TYPE:
		Log.warn("Progression", "not a saying: '%s'" % spell_id)
		return false
	known_spells.append(spell_id)
	known_spells.sort()
	sayings_changed.emit()
	EventBus.spell_learned.emit(spell_id)
	return true


func knows_spell(spell_id: String) -> bool:
	return known_spells.has(spell_id)


## Takes a saying back (the console, a story that unsays one). False when it was not known.
func forget_spell(spell_id: String) -> bool:
	if not known_spells.has(spell_id):
		return false
	known_spells.erase(spell_id)
	sayings_changed.emit()
	return true


## [{id, name, school, school_name, cast_type, cost, cast_time, range, radius, duration,
##   description, effects}] for the sayings screen, cheapest first inside each school.
## Costs and cast times are the ones this character would pay, skill included.
func spells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in known_spells:
		var def := ContentDB.get_or_empty(id)
		if def.is_empty():
			continue
		var school := SpellRuntime.school_of(def)
		var skill := effective_skill(school)
		out.append({
			"id": id, "name": str(def.get("name", Ids.name_of(id))), "school": school,
			"school_name": str(ContentDB.get_or_empty("core:skill/" + school).get("name", school.capitalize())),
			"cast_type": str(def.get("cast_type", "")), "skill_level": skill_level(school),
			"cost": SpellRuntime.cost_of(def, skill, mods.get_mult("spell_cost_" + school)), "base_cost": float(def.get("cost", 0.0)),
			"cast_time": SpellRuntime.cast_time_of(def, skill),
			"range": SpellRuntime.range_of(def) if def.has("range") else 0.0,
			"radius": SpellRuntime.radius_of(def) if def.has("radius") else 0.0,
			"duration": SpellRuntime.duration_of(def) * mods.get_mult("spell_duration_" + school),
			"description": str(def.get("description", "")), "effects": SpellRuntime.effects_of(def),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := SpellRuntime.SCHOOLS.find(str(a["school"]))
		var sb := SpellRuntime.SCHOOLS.find(str(b["school"]))
		if sa != sb:
			return sa < sb
		return float(a["base_cost"]) < float(b["base_cost"]))
	return out


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


func _attr_with_mods(attr: String) -> int:
	return int(round(mods.apply(attr, float(leveling.attribute(attr)))))


## An attribute as the body feels it: the trained value with any fortify effect on it. The
## player's pools and load are built from these.
func attribute_with_mods(attr: String) -> int:
	return _attr_with_mods(attr)


## Effective skill level for damage and cost formulas: the trained level plus fortify effects.
func effective_skill(skill: String) -> float:
	var id := Skills.normalise(skill)
	if id == "":
		return 0.0
	return mods.apply("skill_" + Ids.name_of(id), float(skill_set.level(id)))


## Everything a HUD or character screen needs in one call.
func summary() -> Dictionary:
	var d := leveling.summary(skill_set.total_gains)
	d["calling"] = calling_id
	d["calling_name"] = str(ContentDB.get_or_empty(calling_id).get("name", ""))
	d["style"] = style_id
	d["style_name"] = str(ContentDB.get_or_empty(style_id).get("name", ""))
	d["total_gains"] = skill_set.total_gains
	d["max_health"] = max_health()
	d["max_stamina"] = max_stamina()
	d["max_mana"] = max_mana()
	d["load_capacity"] = load_capacity()
	return d


# --- spending ----------------------------------------------------------------------------

## Spends one attribute point on "vigour", "endurance" or "will".
func spend_attribute(attr: String) -> bool:
	if not leveling.spend_attribute(attr):
		return false
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
	EventBus.attribute_raised.emit(attr, leveling.attribute(attr))
	return true


## Takes a perk, spending one perk point. False when unavailable or unaffordable.
func take_perk(perk_id: String) -> bool:
	if leveling.perk_points <= 0:
		return false
	if not perks.can_take(perk_id, skill_set):
		return false
	if not leveling.spend_perk_point():
		return false
	perks.take(perk_id, skill_set)
	_refresh_perk_modifiers()
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
	EventBus.perk_taken.emit(perk_id)
	return true


## Gives a perk without spending a point (quest reward, console).
func grant_perk(perk_id: String) -> bool:
	if not perks.can_take(perk_id, skill_set):
		return false
	perks.take(perk_id, skill_set)
	_refresh_perk_modifiers()
	EventBus.perk_taken.emit(perk_id)
	return true


## Perk trees for the perks screen. Empty skill = every perk.
func perks_for(skill: String = "") -> Array[Dictionary]:
	var id := Skills.normalise(skill) if skill != "" else ""
	return perks.summaries(id, skill_set)


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
		"calling": calling_id, "style": style_id, "skills": skill_set.to_save(), "leveling": leveling.to_save(),
		"perks": perks.to_save(), "known_spells": known_spells.duplicate(),
	}


func from_save(d: Dictionary) -> void:
	calling_id = str(d.get("calling", ""))
	# a save from before styles has none, and loads as the fallback start (docs/FIGHTING_STYLE_STARTS §5.5)
	style_id = str(d.get("style", ""))
	skill_set.from_save(d.get("skills", {}))
	leveling.from_save(d.get("leveling", {}))
	perks.from_save(d.get("perks", {}))
	# A save from before sayings existed simply has no key, and a saying whose pack is no
	# longer loaded is dropped rather than left to fail at the moment of casting.
	known_spells.clear()
	for id in d.get("known_spells", []):
		var s := str(id)
		if ContentDB.has(s) and not known_spells.has(s):
			known_spells.append(s)
	known_spells.sort()
	_refresh_perk_modifiers()
	sayings_changed.emit()
	skills_changed.emit()
	level_changed.emit(leveling.level)
	points_changed.emit(leveling.attribute_points, leveling.perk_points)
