class_name SocialContext
extends RefCounted
## SocialContext: the one object dialogue conditions read from and dialogue/quest effects write to.
##
## Every read and write goes through a small duck-typed provider object, so tests substitute fakes
## and other streams plug their systems in without this folder referencing them (ARCHITECTURE.md
## §2.4, §9). Missing providers yield safe defaults; a write that would be lost is logged as a
## problem instead of silently succeeding.
##
## Provider methods used (all optional):
##   flags      has_flag(key) get_flag(key, default) set_flag(key, value) clear_flag(key)
##              count(key) inc(key, by) is_discovered(place) discover(place) read_books (property)
##              mark_book_read(book) current_region_id (property) seed (property)
##   quests     stage_of(quest) stage_id_of(quest) is_active(quest) is_completed(quest)
##              outcome_of(quest) start(quest) set_stage(quest, stage) choose(quest, option)
##              fail(quest, reason) complete(quest, outcome) complete_objective(quest, key)
##   factions   reputation(id) rank(id) is_member(id) add_reputation(id, delta, reason) join(id) expel(id, reason)
##   standing   renown() morality() renown_tier() morality_tier() title() add_morality(delta, reason)
##              add_renown(delta, reason) apply_deed(deed, witnesses, place) npc_witnessed(npc) -> String
##              disposition(npc) add_disposition(npc, delta)
##   gossip     knows_deed(place, deed) add_rumour(rumour, place, heat, deed) nearest_place(x, z)
##   inventory  count(item) add(item, n) remove(item, n) -> int has_equipped_tag(tag)
##              marks() add_marks(n) remove_marks(n)
##   player     display_name() position() -> Vector3 skill_level(skill) -> int
##   bounty     bounty_for(faction) -> int
##   recipes    teach(recipe) -> bool
##   clock      hour() day (property or method)
##   content    get_or_empty(id) has(id) all(type)   (defaults to ContentDB)

var providers: Dictionary = {}          # name -> Object

## Conversation state (set by DialogueRunner / callers).
var npc_id: String = ""
var npc: Dictionary = {}                # the NPC def in play (personality.traits, faction, home_place, name)
var place_id: String = ""               # the place whose rumour pool and name apply
var rng := RandomNumberGenerator.new()

## Outputs of effects that the runner consumes.
var end_requested := false
var gesture_replies: Array[String] = []
var notifications: Array[String] = []
var problems: Array[String] = []        # content problems seen (also logged)

const LOG_TAG := "Social"


func set_provider(name: String, obj: Object) -> void:
	if obj == null:
		providers.erase(name)
	else:
		providers[name] = obj


func provider(name: String) -> Object:
	var p: Variant = providers.get(name)
	if p != null and is_instance_valid(p):
		return p
	return null


func problem(msg: String) -> void:
	problems.append(msg)
	Log.warn(LOG_TAG, msg)


func reset_conversation() -> void:
	end_requested = false
	gesture_replies.clear()
	notifications.clear()


# --- generic dispatch ---------------------------------------------------------------------

func _call(name: String, method: String, args: Array = [], default: Variant = null) -> Variant:
	var p := provider(name)
	if p != null and p.has_method(method):
		return p.callv(method, args)
	return default


func _has(name: String, method: String) -> bool:
	var p := provider(name)
	return p != null and p.has_method(method)


func _prop(name: String, prop: String, default: Variant = null) -> Variant:
	var p := provider(name)
	if p == null:
		return default
	if p.has_method(prop):
		return p.call(prop)
	if prop in p:
		return p.get(prop)
	return default


# --- flags / counters / discovery ------------------------------------------------------------

func has_flag(key: String) -> bool:
	return bool(_call("flags", "has_flag", [key], false))


func get_flag(key: String, default: Variant = null) -> Variant:
	return _call("flags", "get_flag", [key, default], default)


func set_flag(key: String, value: Variant = true) -> void:
	if not _has("flags", "set_flag"):
		problem("set_flag '%s' lost: no flags provider" % key)
		return
	_call("flags", "set_flag", [key, value])


func clear_flag(key: String) -> void:
	_call("flags", "clear_flag", [key])


func count(key: String) -> int:
	return int(_call("flags", "count", [key], 0))


func inc(key: String, by: int = 1) -> int:
	return int(_call("flags", "inc", [key, by], 0))


func is_discovered(place: String) -> bool:
	return bool(_call("flags", "is_discovered", [place], false))


func discover(place: String) -> void:
	_call("flags", "discover", [place])


func has_read(book: String) -> bool:
	var books: Variant = _prop("flags", "read_books", [])
	return typeof(books) == TYPE_ARRAY and books.has(book)


func region_id() -> String:
	return str(_prop("flags", "current_region_id", ""))


func world_seed() -> int:
	return int(_prop("flags", "seed", 0))


# --- quests --------------------------------------------------------------------------------

func quest_stage(quest: String) -> int:
	return int(_call("quests", "stage_of", [quest], -1))


func quest_stage_id(quest: String) -> String:
	return str(_call("quests", "stage_id_of", [quest], ""))


func quest_active(quest: String) -> bool:
	return bool(_call("quests", "is_active", [quest], false))


func quest_completed(quest: String) -> bool:
	return bool(_call("quests", "is_completed", [quest], false))


func quest_outcome(quest: String) -> String:
	return str(_call("quests", "outcome_of", [quest], ""))


func start_quest(quest: String) -> bool:
	if not _has("quests", "start"):
		problem("start_quest '%s' lost: no quests provider" % quest)
		return false
	return bool(_call("quests", "start", [quest], false))


func set_quest_stage(quest: String, stage: Variant) -> void:
	if not _has("quests", "set_stage"):
		problem("quest_stage for '%s' lost: no quests provider" % quest)
		return
	_call("quests", "set_stage", [quest, stage])


func quest_choose(quest: String, option: String) -> void:
	if not _has("quests", "choose"):
		problem("quest_choice for '%s' lost: no quests provider" % quest)
		return
	_call("quests", "choose", [quest, option])


func fail_quest(quest: String, reason: String) -> void:
	_call("quests", "fail", [quest, reason])


func complete_quest(quest: String, outcome: String) -> void:
	_call("quests", "complete", [quest, outcome])


func complete_objective(quest: String, key: Variant) -> void:
	_call("quests", "complete_objective", [quest, key])


# --- factions ------------------------------------------------------------------------------

func reputation(faction: String) -> int:
	return int(_call("factions", "reputation", [faction], 0))


func faction_rank(faction: String) -> int:
	return int(_call("factions", "rank", [faction], -1))


func is_member(faction: String) -> bool:
	return bool(_call("factions", "is_member", [faction], false))


func add_reputation(faction: String, delta: int, reason: String = "") -> void:
	if not _has("factions", "add_reputation"):
		problem("rep %+d for '%s' lost: no factions provider" % [delta, faction])
		return
	_call("factions", "add_reputation", [faction, delta, reason])


func join_faction(faction: String) -> bool:
	return bool(_call("factions", "join", [faction], false))


func expel_faction(faction: String, reason: String = "") -> void:
	_call("factions", "expel", [faction, reason])


func bounty(faction: String) -> int:
	return int(_call("bounty", "bounty_for", [faction], 0))


# --- standing & gossip ---------------------------------------------------------------------

func renown() -> int:
	return int(_call("standing", "renown", [], 0))


func morality() -> int:
	return int(_call("standing", "morality", [], 0))


func renown_tier() -> int:
	return int(_call("standing", "renown_tier", [], 0))


func morality_tier() -> int:
	return int(_call("standing", "morality_tier", [], 0))


func title() -> String:
	return str(_call("standing", "title", [], ""))


func add_morality(delta: int, reason: String = "") -> void:
	if not _has("standing", "add_morality"):
		problem("morality %+d lost: no standing provider" % delta)
		return
	_call("standing", "add_morality", [delta, reason])


func add_renown(delta: int, reason: String = "") -> void:
	if not _has("standing", "add_renown"):
		problem("renown %+d lost: no standing provider" % delta)
		return
	_call("standing", "add_renown", [delta, reason])


func apply_deed(deed: String, witnesses: Array = [], place: String = "") -> Dictionary:
	if not _has("standing", "apply_deed"):
		problem("deed '%s' lost: no standing provider" % deed)
		return {}
	var r: Variant = _call("standing", "apply_deed", [deed, witnesses, place if place != "" else place_id], {})
	return r if typeof(r) == TYPE_DICTIONARY else {}


func npc_witnessed(npc: String) -> String:
	return str(_call("standing", "npc_witnessed", [npc], ""))


func disposition(npc: String) -> int:
	return int(_call("standing", "disposition", [npc], 0))


func add_disposition(npc: String, delta: int) -> void:
	_call("standing", "add_disposition", [npc, delta])


func knows_deed(place: String, deed: String) -> bool:
	return bool(_call("gossip", "knows_deed", [place, deed], false))


func add_rumour(rumour: String, place: String, heat: float = 0.6, deed: String = "") -> void:
	if not _has("gossip", "add_rumour"):
		problem("rumour '%s' lost: no gossip provider" % rumour)
		return
	_call("gossip", "add_rumour", [rumour, place, heat, deed])


# --- inventory, marks, player ---------------------------------------------------------------

func item_count(item: String) -> int:
	return int(_call("inventory", "count", [item], 0))


func has_inventory() -> bool:
	return _has("inventory", "count")


func give_item(item: String, n: int = 1) -> void:
	if not _has("inventory", "add"):
		problem("give_item %s x%d lost: no inventory provider" % [item, n])
		return
	_call("inventory", "add", [item, n])


## Removes up to n; returns how many were removed.
func take_item(item: String, n: int = 1) -> int:
	if not _has("inventory", "remove"):
		problem("take_item %s x%d lost: no inventory provider" % [item, n])
		return 0
	return int(_call("inventory", "remove", [item, n], 0))


func wearing_tag(tag: String) -> bool:
	return bool(_call("inventory", "has_equipped_tag", [tag], false))


func marks() -> int:
	return int(_call("inventory", "marks", [], 0))


func add_marks(delta: int) -> void:
	if delta == 0:
		return
	var method := "add_marks" if delta > 0 else "remove_marks"
	if not _has("inventory", method):
		problem("marks %+d lost: no inventory provider" % delta)
		return
	_call("inventory", method, [absi(delta)])


func player_name() -> String:
	var n: Variant = _call("player", "display_name", [], null)
	if n != null and str(n) != "":
		return str(n)
	var f: Variant = get_flag("player_name", "")
	return str(f) if str(f) != "" else "the Foundling"


func player_position() -> Vector3:
	var p: Variant = _call("player", "position", [], null)
	return p if typeof(p) == TYPE_VECTOR3 else Vector3.ZERO


func skill_level(skill: String) -> int:
	return int(_call("player", "skill_level", [skill], 0))


func teach_recipe(recipe: String) -> bool:
	if not _has("recipes", "teach"):
		problem("teach_recipe '%s' lost: no recipes provider" % recipe)
		return false
	return bool(_call("recipes", "teach", [recipe], false))


# --- time ----------------------------------------------------------------------------------

func hour() -> int:
	return int(_call("clock", "hour", [], 12))


func day() -> int:
	return int(_prop("clock", "day", 1))


func is_night() -> bool:
	var h := hour()
	return h < 6 or h >= 21


# --- content lookups -------------------------------------------------------------------------

func content_def(id: String) -> Dictionary:
	var p := provider("content")
	if p != null and p.has_method("get_or_empty"):
		return p.get_or_empty(id)
	if Engine.has_singleton("ContentDB"):
		return Engine.get_singleton("ContentDB").get_or_empty(id)
	var tree_db: Object = _autoload("ContentDB")
	if tree_db != null:
		return tree_db.get_or_empty(id)
	return {}


func content_all(type: String) -> Array:
	var p := provider("content")
	if p != null and p.has_method("all"):
		return p.all(type)
	var tree_db: Object = _autoload("ContentDB")
	if tree_db != null:
		return tree_db.all(type)
	return []


static func _autoload(name: String) -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null(name)
	return null


func npc_traits() -> Array:
	var pers: Variant = npc.get("personality", {})
	if typeof(pers) == TYPE_DICTIONARY:
		var t: Variant = pers.get("traits", [])
		return t if typeof(t) == TYPE_ARRAY else []
	if typeof(pers) == TYPE_ARRAY:
		return pers
	return []


func npc_name() -> String:
	return str(npc.get("name", npc_id))


func place_name(id: String = "") -> String:
	var pid := id if id != "" else place_id
	if pid == "":
		return "here"
	var def := content_def(pid)
	return str(def.get("name", pid.get_slice("/", 1).replace("_", " ")))


## Replaces {player}, {title}, {npc}, {place}, {region} in authored text.
func substitute(text: String) -> String:
	if text.find("{") < 0:
		return text
	var out := text
	if out.find("{player}") >= 0:
		out = out.replace("{player}", player_name())
	if out.find("{title}") >= 0:
		out = out.replace("{title}", title())
	if out.find("{npc}") >= 0:
		out = out.replace("{npc}", npc_name())
	if out.find("{place}") >= 0:
		out = out.replace("{place}", place_name())
	if out.find("{region}") >= 0:
		var r := content_def(region_id())
		out = out.replace("{region}", str(r.get("name", "these parts")))
	return out
