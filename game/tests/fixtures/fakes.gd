class_name SocialFakes
extends RefCounted
## Fakes for the social systems' providers, so conditions, effects, the dialogue runner and the
## quest log can be tested without a world, a player or an inventory.
##
## SocialFakes.context() returns a SocialContext with every provider bound to a fake and its rng
## seeded, which makes "random" and line variation deterministic in tests.


class Flags extends RefCounted:
	var flags: Dictionary = {}
	var counters: Dictionary = {}
	var discovered: Array[String] = []
	var read_books: Array[String] = []
	var current_region_id: String = "core:region/hearthvale"
	var seed: int = 7

	func has_flag(key: String) -> bool:
		var v: Variant = flags.get(key)
		match typeof(v):
			TYPE_NIL:
				return false
			TYPE_BOOL:
				return v
			TYPE_INT, TYPE_FLOAT:
				return v != 0
			TYPE_STRING:
				return v != ""
			_:
				return true

	func get_flag(key: String, default: Variant = null) -> Variant:
		return flags.get(key, default)

	func set_flag(key: String, value: Variant = true) -> void:
		flags[key] = value

	func clear_flag(key: String) -> void:
		flags.erase(key)

	func count(key: String) -> int:
		return int(counters.get(key, 0))

	func inc(key: String, by: int = 1) -> int:
		counters[key] = count(key) + by
		return counters[key]

	func is_discovered(place_id: String) -> bool:
		return place_id in discovered

	func discover(place_id: String) -> void:
		if not place_id in discovered:
			discovered.append(place_id)

	func mark_book_read(book_id: String) -> void:
		if not book_id in read_books:
			read_books.append(book_id)


class Quests extends RefCounted:
	var stages: Dictionary = {}        # quest_id -> int
	var stage_ids: Dictionary = {}     # quest_id -> String
	var active: Dictionary = {}
	var completed: Dictionary = {}
	var outcomes: Dictionary = {}
	var started: Array[String] = []
	var objectives_done: Array = []
	var choices: Dictionary = {}

	func stage_of(quest_id: String) -> int:
		return int(stages.get(quest_id, -1))

	func stage_id_of(quest_id: String) -> String:
		return str(stage_ids.get(quest_id, ""))

	func is_active(quest_id: String) -> bool:
		return bool(active.get(quest_id, false))

	func is_completed(quest_id: String) -> bool:
		return bool(completed.get(quest_id, false))

	func outcome_of(quest_id: String) -> String:
		return str(outcomes.get(quest_id, ""))

	func start(quest_id: String) -> bool:
		started.append(quest_id)
		active[quest_id] = true
		stages[quest_id] = 0
		return true

	func set_stage(quest_id: String, stage: Variant) -> void:
		active[quest_id] = true
		if typeof(stage) == TYPE_STRING:
			stage_ids[quest_id] = str(stage)
		else:
			stages[quest_id] = int(stage)

	func choose(quest_id: String, option: String) -> void:
		choices[quest_id] = option

	func complete(quest_id: String, outcome: String) -> void:
		active[quest_id] = false
		completed[quest_id] = true
		outcomes[quest_id] = outcome

	func fail(quest_id: String, reason: String) -> void:
		active[quest_id] = false
		outcomes[quest_id] = reason

	func complete_objective(quest_id: String, key: Variant) -> void:
		objectives_done.append([quest_id, key])


class Factions extends RefCounted:
	var rep: Dictionary = {}
	var ranks: Dictionary = {}
	var members: Dictionary = {}
	var joined: Array[String] = []
	var expelled: Array[String] = []

	func reputation(faction_id: String) -> int:
		return int(rep.get(faction_id, 0))

	func rank(faction_id: String) -> int:
		return int(ranks.get(faction_id, -1))

	func is_member(faction_id: String) -> bool:
		return bool(members.get(faction_id, false))

	func add_reputation(faction_id: String, delta: int, _reason: String = "") -> void:
		rep[faction_id] = reputation(faction_id) + delta

	func join(faction_id: String) -> bool:
		members[faction_id] = true
		joined.append(faction_id)
		return true

	func expel(faction_id: String, _reason: String = "") -> void:
		members[faction_id] = false
		expelled.append(faction_id)

	func law_faction_for_region(region_id: String) -> String:
		return str(ContentDB.get_or_empty(region_id).get("law_faction", ""))


class Standing extends RefCounted:
	var morality_value := 0
	var renown_value := 0
	var deeds: Array = []
	var dispositions: Dictionary = {}
	var witnessed: Dictionary = {}

	func morality() -> int:
		return morality_value

	func renown() -> int:
		return renown_value

	func morality_tier() -> int:
		var mag := absi(morality_value)
		var step := 0
		for t in [15, 40, 75]:
			if mag >= t:
				step += 1
		return step if morality_value >= 0 else -step

	func renown_tier() -> int:
		var out := 0
		for i in [0, 25, 100, 300, 600].size():
			if renown_value >= [0, 25, 100, 300, 600][i]:
				out = i
		return out

	func title() -> String:
		return ["", "the Heard-Of", "the Known", "the Spoken-Of", "the Named"][renown_tier()]

	func add_morality(delta: int, _reason: String = "") -> void:
		morality_value = clampi(morality_value + delta, -100, 100)

	func add_renown(delta: int, _reason: String = "") -> void:
		renown_value = clampi(renown_value + delta, 0, 1000)

	func apply_deed(deed_id: String, witnesses: Variant = [], place_id: String = "") -> Dictionary:
		deeds.append({"deed": deed_id, "witnesses": witnesses, "place": place_id})
		return {"deed": deed_id}

	func disposition(npc_id: String) -> int:
		return int(dispositions.get(npc_id, 0))

	func add_disposition(npc_id: String, delta: int) -> void:
		dispositions[npc_id] = disposition(npc_id) + delta

	func npc_witnessed(npc_id: String) -> String:
		return str(witnessed.get(npc_id, ""))

	func forget_witness(npc_id: String) -> void:
		witnessed.erase(npc_id)


class Gossip extends RefCounted:
	var known: Dictionary = {}         # "place|deed" -> true
	var added: Array = []

	func knows_deed(place_id: String, deed_id: String) -> bool:
		return known.has("%s|%s" % [place_id, deed_id])

	func add_rumour(rumour_id: String, place_id: String, heat: float = 0.6, deed_id: String = "") -> void:
		added.append({"rumour": rumour_id, "place": place_id, "heat": heat, "deed": deed_id})
		if deed_id != "":
			known["%s|%s" % [place_id, deed_id]] = true

	func nearest_place(_pos: Vector3, _settled_only := true) -> String:
		return "core:place/merrowby"


class Inventory extends RefCounted:
	var items: Dictionary = {}
	var marks_value := 0
	var equipped_tags: Array[String] = []

	func count(item_id: String) -> int:
		return int(items.get(item_id, 0))

	func add(item_id: String, n: int = 1) -> void:
		items[item_id] = count(item_id) + n
		EventBus.item_acquired.emit(item_id, n)

	func remove(item_id: String, n: int = 1) -> int:
		var taken: int = mini(n, count(item_id))
		items[item_id] = count(item_id) - taken
		if taken > 0:
			EventBus.item_removed.emit(item_id, taken)
		return taken

	func has_equipped_tag(tag: String) -> bool:
		return tag in equipped_tags

	func marks() -> int:
		return marks_value

	func add_marks(n: int) -> void:
		marks_value += n

	func remove_marks(n: int) -> void:
		marks_value -= n


class Player extends RefCounted:
	var name_value := "Wren"
	var pos := Vector3.ZERO
	var skills: Dictionary = {}

	func display_name() -> String:
		return name_value

	func position() -> Vector3:
		return pos

	func skill_level(skill_id: String) -> int:
		return int(skills.get(skill_id, 0))


class Bounty extends RefCounted:
	var bounties: Dictionary = {}

	func bounty_for(faction_id: String) -> int:
		return int(bounties.get(faction_id, 0))


class Recipes extends RefCounted:
	var taught: Array[String] = []

	func teach(recipe_id: String) -> bool:
		taught.append(recipe_id)
		return true


class Clock extends RefCounted:
	var hour_value := 12
	var day := 1

	func hour() -> int:
		return hour_value


## A context with every provider faked and a fixed rng seed.
static func context(rng_seed: int = 12345) -> SocialContext:
	var ctx := SocialContext.new()
	ctx.set_provider("flags", Flags.new())
	ctx.set_provider("quests", Quests.new())
	ctx.set_provider("factions", Factions.new())
	ctx.set_provider("standing", Standing.new())
	ctx.set_provider("gossip", Gossip.new())
	ctx.set_provider("inventory", Inventory.new())
	ctx.set_provider("player", Player.new())
	ctx.set_provider("bounty", Bounty.new())
	ctx.set_provider("recipes", Recipes.new())
	ctx.set_provider("clock", Clock.new())
	ctx.set_provider("content", ContentDB)
	ctx.rng.seed = rng_seed
	ctx.place_id = "core:place/merrowby"
	return ctx
