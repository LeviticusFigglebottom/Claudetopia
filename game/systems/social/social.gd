extends Node
## Social: the autoload that owns the social half of Wickmere and wires it together — factions,
## standing (Hearth/Hollow and Renown), gossip, the quest log with its job boards, and the
## dialogue runner. It builds the one SocialContext they all read and write through, and binds
## the providers other streams own (inventory, player, crime) by duck typing, so no system here
## holds a path to another system's nodes (ARCHITECTURE §9).
##
## Children (each in its own group, for other streams to find):
##   Factions   group "factions"         save section "factions"
##   Standing   group "standing"         save section "standing"
##   Gossip     group "gossip"           save section "gossip"
##   QuestLog   group "quest_log"        save section "quests" (board cooldowns ride along)
##   Dialogue   group "dialogue_runner"  no save section (its state is flags in GameState)
##
## Other streams bind themselves with Social.bind("inventory", node) or simply by joining the
## group this looks for: "inventory", "player", "crime" (bounty), "crafting" (recipes).

const PROVIDER_GROUPS := {
	"inventory": "inventory",
	"player": "player",
	"bounty": "crime",
	"recipes": "crafting",
}

var ctx: SocialContext
var factions: Node
var standing: Node
var gossip: Node
var quests: Node
var dialogue: Node
var radiant: RadiantGenerator


func _ready() -> void:
	ctx = SocialContext.new()
	ctx.rng.randomize()

	factions = preload("res://systems/factions/factions.gd").new()
	factions.name = "Factions"
	add_child(factions)

	standing = preload("res://systems/factions/standing.gd").new()
	standing.name = "Standing"
	add_child(standing)

	gossip = preload("res://systems/factions/gossip.gd").new()
	gossip.name = "Gossip"
	add_child(gossip)

	quests = preload("res://systems/quests/quest_log.gd").new()
	quests.name = "QuestLog"
	add_child(quests)

	dialogue = preload("res://systems/dialogue/dialogue_runner.gd").new()
	dialogue.name = "Dialogue"
	dialogue.ctx = ctx
	add_child(dialogue)

	radiant = RadiantGenerator.new(quests, factions)
	quests.radiant = radiant
	quests.ctx = ctx
	standing.gossip = gossip
	standing.place_provider = self

	ctx.set_provider("flags", GameState)
	ctx.set_provider("clock", WorldClock)
	ctx.set_provider("content", ContentDB)
	ctx.set_provider("quests", quests)
	ctx.set_provider("factions", factions)
	ctx.set_provider("standing", standing)
	ctx.set_provider("gossip", gossip)

	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.region_entered.connect(_on_region_entered)
	call_deferred("refresh_providers")
	call_deferred("_register_debug_commands")


## The debug console is optional and loads after this autoload, so commands are registered on the
## first frame and only if it is there.
func _register_debug_commands() -> void:
	var console := get_node_or_null("/root/Debug")
	if console != null and console.has_method("register"):
		SocialDebugCommands.register_all(self, console)


# --- provider binding -------------------------------------------------------------------------

## Binds (or replaces) one of the providers the context reads: "inventory", "player", "bounty",
## "recipes", or any other name a future system wants to serve.
func bind(provider_name: String, obj: Object) -> void:
	ctx.set_provider(provider_name, obj)
	if provider_name == "player":
		quests.position_provider = obj if SocialContext.can_locate(obj) else null


## Looks for the systems other streams own and binds the first node in each group.
func refresh_providers() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for provider_name in PROVIDER_GROUPS:
		if ctx.provider(provider_name) != null:
			continue
		var nodes := tree.get_nodes_in_group(PROVIDER_GROUPS[provider_name])
		if not nodes.is_empty():
			bind(provider_name, nodes[0])


func _on_player_spawned(player: Node) -> void:
	bind("player", player)
	refresh_providers()


func _on_region_entered(_region_id: String, _previous: String) -> void:
	refresh_providers()


# --- where the player is ---------------------------------------------------------------------

## The settled place the player counts as being at, for gossip and greetings. Uses the player's
## position when one is bound, otherwise the current region's main settlement.
func place_id() -> String:
	var player := ctx.provider("player")
	if player != null and player.has_method("position") and gossip.has_method("nearest_place"):
		var near := str(gossip.nearest_place(player.call("position")))
		if near != "":
			return near
	if ctx.place_id != "":
		return ctx.place_id
	return ""


func set_place(new_place_id: String) -> void:
	ctx.place_id = new_place_id


# --- the convenience API other streams call ------------------------------------------------------

## Starts a conversation. Returns the runner so the UI can connect to its signals.
func talk(npc_id: String, dialogue_id: String = "", place: String = "") -> Node:
	ctx.place_id = place if place != "" else place_id()
	dialogue.start(dialogue_id, npc_id, ctx.place_id)
	return dialogue


## The line this NPC would greet the player with right now.
func greet(npc_id: String) -> String:
	ctx.place_id = place_id()
	return dialogue.greeting_for(npc_id)


## A gesture aimed at an NPC, with whoever else can see it.
func do_gesture(gesture_id: String, npc_id: String = "", witnesses: Array = []) -> Dictionary:
	if dialogue.is_running():
		return dialogue.gesture(gesture_id, witnesses)
	ctx.place_id = place_id()
	return Gestures.perform(gesture_id, npc_id, ctx, witnesses)


## Records a deed (the crime, combat and quest systems call this).
func apply_deed(deed_id: String, witnesses: Array = [], place: String = "") -> Dictionary:
	return standing.apply_deed(deed_id, witnesses, place if place != "" else place_id())


## {renown, renown_tier, morality, morality_tier, title, ...} for prices, visuals and guards.
func reaction_profile() -> Dictionary:
	return standing.reaction_profile()


## Fresh work for a job board: generate(region, count) with the board's own cooldown.
func board_jobs(board_place_id: String, region_id: String = "", count: int = 3) -> Array[Dictionary]:
	var region := region_id
	if region == "":
		region = str(ContentDB.get_or_empty(board_place_id).get("region", GameState.current_region_id))
	return radiant.generate_for_board(board_place_id, region, count)


## Accepts a generated (or authored) quest.
func take_quest(quest_id: String) -> bool:
	return quests.start(quest_id)


func reset_for_new_game() -> void:
	factions.reset_for_new_game()
	standing.reset_for_new_game()
	gossip.reset_for_new_game()
	quests.reset_for_new_game()
	Gestures.clear_memory()
	Greetings.forget()
