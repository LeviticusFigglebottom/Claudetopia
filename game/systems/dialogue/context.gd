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
##   quests     stage_of(quest) stage_id_of(quest) stage_index(quest, stage) is_active(quest) is_completed(quest)
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
##   bounty     bounty_for(faction) -> int  report_crime(crime) -> Dictionary
##   recipes    learn_recipe(recipe) -> bool  knows_recipe(recipe) -> bool   (the crafting node)
##   sayings    learn_spell(spell) -> bool  knows_spell(spell) -> bool   (the progression node)
##   clock      hour() day (property or method)
##   content    get_or_empty(id) has(id) all(type)   (defaults to ContentDB)

## The flag that says the player owns a horse (give_mount; the Stable reads it).
const MOUNT_FLAG_PREFIX := "mount_owned/"

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
var work_offered: Array[String] = []    # places whose work the speaker has offered (offer_work)
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
	work_offered.clear()


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


## The index of a stage named as content names it (an id, or a number counted from one), or -1.
func quest_stage_index(quest: String, stage: Variant) -> int:
	return int(_call("quests", "stage_index", [quest, stage], -1))


## The open options of the decisions this NPC hosts that nobody wrote a button for:
## [{quest_id, id, text}] (QuestLog.unwritten_choices_for).
func quest_offers(npc: String) -> Array:
	var r: Variant = _call("quests", "unwritten_choices_for", [npc], [])
	return r if typeof(r) == TYPE_ARRAY else []


## Quests this person can start, as their giver: [{quest_id, text}] (QuestLog.giver_offers).
func quest_starts(npc: String) -> Array:
	var r: Variant = _call("quests", "giver_offers", [npc], [])
	return r if typeof(r) == TYPE_ARRAY else []


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


## The work going in a place, offered by somebody who lives there (the `offer_work` effect): the
## runner opens that place's board once the line is said. The speaker's own place when empty.
func offer_work(place: String = "") -> void:
	var where := place
	if where == "":
		where = str(npc.get("home_place", place_id))
	if where == "":
		problem("offer_work: nowhere to offer work for")
		return
	work_offered.append(where)


## A crime a decision makes of the player (the `bounty` effect), committed through the crime
## service's own rules: the severity its kind carries, the law of the place's region (and where
## there is no law, ill-feeling that wears off), and a report that lands after the witness's
## delay. It happens at `place`, the conversation's own when empty, and is seen by `witness`, the
## person being spoken to when empty; nobody else saw it. {} when there is no crime service.
func commit_crime(kind: String, place: String = "", witness: String = "", value: int = 0,
		reaction: String = "report") -> Dictionary:
	if not _has("bounty", "report_crime"):
		problem("crime '%s' lost: no crime service" % kind)
		return {}
	var where := place if place != "" else place_id
	var def := content_def(where)
	var xz: Variant = def.get("position", [])
	var at := Vector3.ZERO
	if typeof(xz) == TYPE_ARRAY and (xz as Array).size() >= 2:
		at = Vector3(float(xz[0]), 0.0, float(xz[1]))
	var who := witness if witness != "" else npc_id
	var seen: Array = []
	if who != "":
		seen.append({"npc_id": who, "detection": 1.0, "line_of_sight": true, "reaction": reaction, "place_id": where})
	var r: Variant = _call("bounty", "report_crime", [{"kind": kind, "position": at, "value": value,
			"region_id": str(def.get("region", "")), "place_id": where, "witnesses": seen}], {})
	return r if typeof(r) == TYPE_DICTIONARY else {}


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


func apply_deed(deed: String, witnesses: Variant = [], place: String = "") -> Dictionary:
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


## The piece of news this place is warmest about, as {rumour, heat, tone, text}, tilted by how
## the speaker feels about the player. {} when nobody here has anything to say.
func hottest_rumour(place: String = "", npc: String = "") -> Dictionary:
	if not _has("gossip", "hottest"):
		return {}
	var where := place if place != "" else place_id
	if where == "":
		return {}
	var warmth := clampf(float(disposition(npc if npc != "" else npc_id)) / 60.0, -1.0, 1.0)
	var subs := {"player": player_name(), "title": title(), "npc": npc_name()}
	var out: Variant = _call("gossip", "hottest", [where, subs, warmth], {})
	return out if typeof(out) == TYPE_DICTIONARY else {}


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


## A horse of the player's own: owned by a flag (saved with the flags, and read by the Stable when
## the world comes up), and stood in the world now if a Stable is bound. Owning it twice is owning it.
func give_mount(mount: String) -> void:
	if not Ids.is_valid(mount) or Ids.type_of(mount) != "mount":
		problem("give_mount: '%s' is not a mount id" % mount)
		return
	set_flag(MOUNT_FLAG_PREFIX + mount, true)
	if _has("stable", "give"):
		_call("stable", "give", [mount])


## Removes up to n; returns how many were removed.
func take_item(item: String, n: int = 1) -> int:
	if not _has("inventory", "remove"):
		problem("take_item %s x%d lost: no inventory provider" % [item, n])
		return 0
	return int(_call("inventory", "remove", [item, n], 0))


## Is the player wearing or holding something with this tag? Asks the inventory if it answers
## that question itself, otherwise reads the equipment slots and the items' own tags.
func wearing_tag(tag: String) -> bool:
	if _has("inventory", "has_equipped_tag"):
		return bool(_call("inventory", "has_equipped_tag", [tag], false))
	var equipment := provider("equipment")
	if equipment == null or not equipment.has_method("slots"):
		return false
	var slots: Variant = equipment.call("slots")
	if typeof(slots) != TYPE_DICTIONARY:
		return false
	for slot in (slots as Dictionary):
		var item_id := str((slots as Dictionary)[slot])
		if item_id == "":
			continue
		var tags: Variant = content_def(item_id).get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has(tag):
			return true
	return false


## The inventory stream owns marks; it may expose them as a method or as a plain property.
func marks() -> int:
	return int(_prop("inventory", "marks", 0))


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
	return position_of(provider("player"))


## Where an object is, whether it answers with a position() method (a provider) or carries the
## Node3D properties (an actor scene). Zero when it is neither.
static func position_of(obj: Object) -> Vector3:
	if obj == null or not is_instance_valid(obj):
		return Vector3.ZERO
	if obj.has_method("position"):
		var p: Variant = obj.call("position")
		if typeof(p) == TYPE_VECTOR3:
			return p
	if obj is Node3D:
		# A body out of the tree has no global transform: asking for one is an engine error and
		# an identity matrix, which reads as the middle of the map rather than as "do not know".
		var n3 := obj as Node3D
		return n3.global_position if n3.is_inside_tree() else n3.position
	for prop in ["global_position", "position"]:
		if prop in obj:
			var v: Variant = obj.get(prop)
			if typeof(v) == TYPE_VECTOR3:
				return v
	return Vector3.ZERO


## True when this object can say where it is, either way.
static func can_locate(obj: Object) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	return obj.has_method("position") or obj is Node3D or ("global_position" in obj) or ("position" in obj)


## Skills live in the progression system; some player doubles answer for themselves.
func skill_level(skill: String) -> int:
	if _has("skills", "skill_level"):
		return int(_call("skills", "skill_level", [skill], 0))
	return int(_call("player", "skill_level", [skill], 0))


## Teaches a recipe (DESIGN §5.9). The provider method is `learn_recipe`, to match the sayings
## provider's `learn_spell` below — it used to ask for `teach`, which `Crafting` has never had,
## so every `teach_recipe` effect an author wrote would have been quietly lost.
func teach_recipe(recipe: String) -> bool:
	if not _has("recipes", "learn_recipe"):
		problem("teach_recipe '%s' lost: no recipes provider" % recipe)
		return false
	return bool(_call("recipes", "learn_recipe", [recipe], false))


## Teaches a saying (DESIGN §5.3). False when it was already known or nobody is listening.
func teach_spell(spell: String) -> bool:
	if not _has("sayings", "learn_spell"):
		problem("teach_spell '%s' lost: no sayings provider" % spell)
		return false
	return bool(_call("sayings", "learn_spell", [spell], false))


func knows_spell(spell: String) -> bool:
	return bool(_call("sayings", "knows_spell", [spell], false))


## Whether the character already has this recipe, so a smith does not offer to teach you a
## thing you can already make.
func knows_recipe(recipe: String) -> bool:
	return bool(_call("recipes", "knows_recipe", [recipe], false))


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
