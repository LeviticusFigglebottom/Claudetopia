class_name GameServices
extends Node
## Installs every world service exactly once, in the order they depend on each other.
##
## Each system ships a `static ensure()` that finds or creates its own singleton node, so
## the systems never reach for one another by path. Nothing calls those, though, which is
## how a player ends up standing in a world with no law and no market. This node is the
## one place that does, and any host scene (the world, the arena, the smoke run, the
## scripted journey) adds a single instance of it.
##
## Order matters: ownership before crime (crime asks who owns the thing), the NPC
## registry before reactions (reactions read NPC state), the streamer after both (it
## stands bodies up and they are reacted to), the economy before property (a deed is
## bought with marks at a price).

signal installed
## Fired once, on the first frame of a new game, after the opening has been set up.
signal new_game_started(quest_id: String)

const ORDER := [
	["Ownership", "res://systems/crime/ownership.gd"],
	["Bounty", "res://systems/crime/bounty.gd"],
	# Nothing in the world told the law about a theft or a killing; this is what does.
	["CrimeReports", "res://systems/crime/crime_reports.gd"],
	["Stealth", "res://systems/crime/stealth.gd"],
	["NpcRegistry", "res://systems/npc_life/npc_registry.gd"],
	["Reactions", "res://systems/npc_life/reactions.gd"],
	# The registry can stand people up and never did outside a test; this is what calls it.
	["NpcStreamer", "res://systems/npc_life/npc_streamer.gd"],
	["EconomyService", "res://systems/economy/economy_service.gd"],
	["PropertyRegistry", "res://systems/economy/property.gd"],
	# The chart was filled by being told about places, never by going to one or looking out
	# from high ground; this is what walks the world and reads it.
	["PlaceDiscovery", "res://systems/exploration/place_discovery.gd"],
]

## The one thing a new game needs that no system owns: the opening quest, named in data so
## a content pack can open somewhere else entirely.
const OPENING := "core:opening/new_game"

var services: Dictionary = {}
## Off only for a bench that wants one service and not the whole country standing up around it.
var installs_on_ready := true


func _ready() -> void:
	if installs_on_ready:
		install()


func install() -> void:
	for pair in ORDER:
		var display: String = pair[0]
		var path: String = pair[1]
		if not ResourceLoader.exists(path):
			Log.warn("GameServices", "%s is not in this build (%s)" % [display, path])
			continue
		var script: GDScript = load(path)
		var node: Node = null
		if script.has_method("ensure"):
			node = script.ensure()
		if node == null:
			node = script.new()
			node.name = display
			get_tree().current_scene.add_child(node)
		services[display] = node
	_install_loot_drops()
	Log.info("GameServices", "installed %d services: %s" % [services.size(), ", ".join(services.keys())])
	installed.emit()
	if GameState.has_flag("new_game"):
		call_deferred("begin_new_game")


## Loot is a listener rather than a queried service, so it has no ensure() of its own.
func _install_loot_drops() -> void:
	var present := get_tree().get_nodes_in_group("loot_drops")
	if present.size() > 0:
		for drops in present:
			var provider: Variant = drops.get("context_provider")
			if provider is Callable and not (provider as Callable).is_valid():
				drops.set("context_provider", loot_context)
		return
	var path := "res://systems/inventory/loot_drops.gd"
	if not ResourceLoader.exists(path):
		return
	var drops: Node = (load(path) as GDScript).new()
	drops.name = "LootDrops"
	drops.add_to_group("loot_drops")
	drops.set("context_provider", loot_context)
	add_child(drops)
	services["LootDrops"] = drops


## What a kill's loot is rolled against (LootTable's context): where it happened, the character's
## level and luck, the flags, and how far each quest has come. LootDrops has always asked for this
## through `context_provider` and nothing ever assigned one, so every kill in the game rolled as a
## level-1 character with no luck and no quests: every loot entry gated on `min_level` --
## twenty-one of them, from level 2 to level 20 -- could never drop, and `weight_per_luck` weighed
## nothing. Stages are QuestLog's own `stage_of`, the same index the dialogue context hands out.
func loot_context() -> Dictionary:
	var ctx := LootTable.default_context()
	if not is_inside_tree():
		return ctx
	var prog := get_tree().get_first_node_in_group("progression")
	if prog != null:
		ctx["level"] = int(prog.get("level"))
		var mods: Variant = prog.get("mods")
		if mods is Modifiers:
			ctx["luck"] = (mods as Modifiers).apply("luck", 0.0)
	var quest_log := get_tree().get_first_node_in_group("quest_log")
	if quest_log != null and quest_log.has_method("stage_of"):
		var quests := {}
		var known: Variant = quest_log.get("quests")
		if known is Dictionary:
			for quest_id in known:
				quests[str(quest_id)] = int(quest_log.call("stage_of", str(quest_id)))
		ctx["quests"] = quests
	return ctx


## The Naming hands over a named character and a flag, and until now nothing picked it up, so
## the first quest of the game never started and the main thread could not be entered at all.
## Starting it is all this does: everything else about a new game is a system's own business.
func begin_new_game() -> void:
	GameState.set_flag("new_game", false)
	var opening := ContentDB.get_or_empty(OPENING)
	var quest := str(opening.get("quest", ""))
	if quest.is_empty() or not ContentDB.has(quest):
		Log.warn("GameServices", "no opening quest in %s" % OPENING)
		return
	var log_node := get_tree().get_first_node_in_group("quest_log")
	if log_node == null or not log_node.has_method("start"):
		Log.warn("GameServices", "no quest log to start '%s' in" % quest)
		return
	if bool(log_node.call("is_active", quest)) or bool(log_node.call("is_completed", quest)):
		return
	log_node.call("start", quest)
	new_game_started.emit(quest)
	Log.info("GameServices", "new game: started %s" % quest)


func service(display_name: String) -> Node:
	return services.get(display_name)
