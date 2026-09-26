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
## Fired when the wake has played and the Naming stands at its `wake` stage (begin_wake).
signal wake_begun

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
	# The quest log has waited for escort_arrived since it was written; this is what says it.
	["Escorts", "res://systems/npc_life/escorts.gd"],
	# Fourteen quests sent you for things nothing gave, sold or put anywhere.
	["QuestItems", "res://world/pois/quest_items.gd"],
	# And sent you to fight where nothing stood: the stage stands up what it asks for.
	["QuestFoes", "res://systems/quests/quest_foes.gd"],
	# and has its people wait where no dressing marks a place for them (a verge, a bridge's end)
	["QuestSpots", "res://world/tutorial/quest_spots.gd"],
	# and has a teacher step into a ring with you (the style starts' lessons)
	["Sparring", "res://world/tutorial/sparring.gd"],
	["EconomyService", "res://systems/economy/economy_service.gd"],
	["PropertyRegistry", "res://systems/economy/property.gd"],
	# The chart was filled by being told about places, never by going to one or looking out
	# from high ground; this is what walks the world and reads it.
	["PlaceDiscovery", "res://systems/exploration/place_discovery.gd"],
]

## The one thing a new game needs that no system owns: the opening quest, named in data so
## a content pack can open somewhere else entirely. This is the fallback's; a styled character's
## is its style's (Openings.for_new_game), and the wake's is `role: "wake"` (Openings.wake).
const OPENING := "core:opening/new_game"
## Why saves are held while a style's own film plays (SaveSystem.hold_saves).
const STYLE_FILM_HOLD := "style_film"
## How long the picture takes to go to grey at the fortieth step, before the wake's film.
const WAKE_GREY_SECONDS := 1.4

var services: Dictionary = {}
## Off only for a bench that wants one service and not the whole country standing up around it.
var installs_on_ready := true
## What the opening's greeter said when control was handed over, for a test or the flow probe.
var first_words := ""
var _new_game_begun := false
var _wake_begun := false


func _ready() -> void:
	if installs_on_ready:
		install()


func install() -> void:
	var there_before := _loose_nodes()
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
		if node != null and not there_before.has(node.get_instance_id()) and _outside_host(node):
			_made_outside.append(node)
	_install_loot_drops()
	Log.info("GameServices", "installed %d services: %s" % [services.size(), ", ".join(services.keys())])
	installed.emit()
	if Openings.begin_due():
		call_deferred("begin_new_game")


## A service belongs to the world that installed it, and goes when that world goes. Each system's
## `ensure()` puts a new one under the current scene, which in the game is the World itself, but
## under the test runner (or any host that adds a world beside the current scene) is the runner:
## every world a test stood up left its services behind, enabled, when it was freed. A left-over
## QuestFoes went on polling and stood the Naming's three ash-wights at the Choir itself, so the
## next test's own QuestFoes counted them as already standing, stood nothing, and had no group
## (test_kill_places in main's full suite, 2026-09-25).
##
## They are not moved into the world while it stands: a move is a leaving and an entering of the
## tree, and several services let go in `_exit_tree` of what their `_ready` took (the save
## registration, the kill listener), which no move gives back. The quest walker lost four
## quests to that. What this installer made outside its world is taken away as the world goes,
## and nothing it found already standing (a test's own service) is touched.
var _made_outside: Array[Node] = []


func _exit_tree() -> void:
	# freed, not taken out here: this runs while the world's parent is busy removing the world, and
	# a remove_child now is refused with an engine error (25 of them in a full suite). The free at
	# the end of the frame takes each out of the tree.
	for node in _made_outside:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	_made_outside.clear()


func _outside_host(node: Node) -> bool:
	var host := get_parent()
	return host != null and node.is_inside_tree() and not host.is_ancestor_of(node) and node != host


## The instance ids of what stands directly under the current scene and the root now.
func _loose_nodes() -> Dictionary:
	var out := {}
	for parent in [get_tree().current_scene, get_tree().root]:
		if parent != null:
			for c in parent.get_children():
				out[c.get_instance_id()] = true
	return out


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
## nothing. The context is `LootTable.world_context()`, which a chest reads as well.
func loot_context() -> Dictionary:
	return LootTable.world_context()


## The Naming hands over a named character and a flag, and until now nothing picked it up, so
## the first quest of the game never started and the main thread could not be entered at all.
## Starting it is all this does: everything else about a new game is a system's own business.
func begin_new_game() -> void:
	if _new_game_begun:
		return
	_new_game_begun = true
	var opening := Openings.for_new_game()
	if Openings.is_style_start(opening) and GameState.has_flag(Openings.STYLE_DUE):
		await _begin_style_start(opening)
		return
	opening = ContentDB.get_or_empty(OPENING)
	# The opening (DESIGN §5.1a) plays first, and the story starts when it hands control back, so
	# the quest's first objective is the first thing the HUD says rather than a toast under the
	# pictures. This is the cinematic's only way into the new-game flow; it returns at once when
	# there is nothing to play or the player has turned it off. The `new_game` flag stays up until
	# then: it is what holds the greeter at the start while the pictures play (her npc def's
	# `holds`), and the quest's own stage holds her from the hand-over on.
	# A slot is never written while the opening plays (SaveSystem.hold_saves), but one written
	# before that rule still carries the flag up: loaded, it gets the story and not the pictures.
	if _loaded_slot().is_empty():
		await CinematicPlayer.play_opening(opening)
	else:
		Log.info("GameServices", "'%s' was saved before the opening handed over: the story starts without it" % _loaded_slot())
	GameState.set_flag("new_game", false)
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
	# the fallback opens straight on the wake: the Naming's first stage is the style starts' descent,
	# and a character who never went down has nothing to follow
	var at: Variant = opening.get("stage", null)
	log_node.call("start", quest, at)
	new_game_started.emit(quest)
	Log.info("GameServices", "new game: started %s" % quest)
	_first_words(str(opening.get("greeter", "")))


## A styled character's start (DESIGN §5.1a): the style's own short film over its region and town,
## in the teacher's voice, then its tutorial quest, and the teacher's first words. `new_game` is never
## raised: a style's start is play like any other, saved and loaded, for as long as it takes. Only
## the film holds saving while it plays.
func _begin_style_start(opening: Dictionary) -> void:
	GameState.clear_flag(Openings.STYLE_DUE)
	GameState.set_flag(Openings.STYLE_START, true)
	if _loaded_slot().is_empty():
		SaveSystem.hold_saves(STYLE_FILM_HOLD)
		await CinematicPlayer.play_opening(opening)
		SaveSystem.release_saves(STYLE_FILM_HOLD)
	var quest := str(opening.get("quest", ""))
	var log_node := get_tree().get_first_node_in_group("quest_log")
	if quest.is_empty() or not ContentDB.has(quest) or log_node == null or not log_node.has_method("start"):
		Log.warn("GameServices", "no tutorial quest to start for %s" % str(opening.get("id", "?")))
		return
	if not bool(log_node.call("is_active", quest)) and not bool(log_node.call("is_completed", quest)):
		log_node.call("start", quest)
	new_game_started.emit(quest)
	Log.info("GameServices", "new game (%s): started %s" % [str(opening.get("style", "")), quest])
	_first_words(str(opening.get("greeter", "")))


## The wake (DESIGN §5.1a): fired by the descent's trigger at the fortieth step of the Hushline
## Stair (StairDescent), or by a test. The picture goes to grey, the body is stood at the top of the
## stair where the Warden will find it, `new_game` goes up for as long as the opening's film plays
## (it holds saving, and the Warden at her fire), and when the film hands back the Naming moves to
## its `wake` stage and the Warden speaks first. The same whether the film plays, is skipped, or is
## turned off in the settings. Returns once control is back.
func begin_wake() -> void:
	if _wake_begun:
		return
	_wake_begun = true
	var wake := Openings.wake()
	var quest := str(wake.get("quest", "core:quest/the_naming"))
	var log_node := get_tree().get_first_node_in_group("quest_log")
	# the descent has already drained the colour and the sound out of it: what is left goes to the
	# black the film opens on ("Black. One bell.")
	UI.fade_to_black(WAKE_GREY_SECONDS)
	await get_tree().create_timer(WAKE_GREY_SECONDS, true, false, true).timeout
	GameState.set_flag(Openings.NEW_GAME, true)
	GameState.clear_flag(Openings.STYLE_START)
	var spawn := get_tree().get_first_node_in_group("player_spawn")
	if spawn != null and spawn.has_method("stand_at_opening"):
		spawn.call("stand_at_opening", wake)
	StairDescent.restore()
	# the film lays its own black curtain the moment it begins, under this; with the film turned off
	# the fade lifts on the Stair Head
	UI.fade_from_black(0.8)
	await CinematicPlayer.play_opening(wake)
	GameState.set_flag(Openings.NEW_GAME, false)
	if log_node != null and log_node.has_method("set_stage") and not quest.is_empty():
		if not bool(log_node.call("is_active", quest)) and not bool(log_node.call("is_completed", quest)):
			log_node.call("start", quest, str(wake.get("stage", "wake")))
		else:
			log_node.call("set_stage", quest, str(wake.get("stage", "wake")))
	Log.info("GameServices", "the wake: %s at %s" % [quest, str(wake.get("stage", "wake"))])
	wake_begun.emit()
	_first_words(str(wake.get("greeter", "")))


func _loaded_slot() -> String:
	var spawn := get_tree().get_first_node_in_group("player_spawn")
	return str(spawn.get("loaded_slot")) if spawn != null and spawn.get("loaded_slot") != null else ""


## Somebody speaks first: the opening's greeter says the greeting their own dialogue has for this
## moment (the Warden's for the Naming's first stage), as a line on the screen with their name on
## it, the moment control is handed over. Nothing is said if the greeter has no line for now.
func _first_words(greeter: String) -> void:
	if greeter.is_empty() or not ContentDB.has(greeter):
		return
	var runner: Node = Social.dialogue if Social != null else null
	if runner == null or not runner.has_method("greeting_for"):
		return
	var line := str(runner.call("greeting_for", greeter))
	var hud := UI.hud()
	if line.is_empty() or hud == null or not hud.has_method("show_subtitle"):
		return
	var ctx: SocialContext = Social.ctx if Social != null else null
	hud.call("show_subtitle", "%s: %s" % [Npc.shown_name(ContentDB.get_or_empty(greeter), ctx), line], 6.0)
	first_words = line


func service(display_name: String) -> Node:
	return services.get(display_name)
