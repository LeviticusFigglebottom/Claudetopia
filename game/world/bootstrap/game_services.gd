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
## registry before reactions (reactions read NPC state), the economy before property
## (a deed is bought with marks at a price).

signal installed

const ORDER := [
	["Ownership", "res://systems/crime/ownership.gd"],
	["Bounty", "res://systems/crime/bounty.gd"],
	["Stealth", "res://systems/crime/stealth.gd"],
	["NpcRegistry", "res://systems/npc_life/npc_registry.gd"],
	["Reactions", "res://systems/npc_life/reactions.gd"],
	["EconomyService", "res://systems/economy/economy_service.gd"],
	["PropertyRegistry", "res://systems/economy/property.gd"],
]

var services: Dictionary = {}


func _ready() -> void:
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


## Loot is a listener rather than a queried service, so it has no ensure() of its own.
func _install_loot_drops() -> void:
	if get_tree().get_nodes_in_group("loot_drops").size() > 0:
		return
	var path := "res://systems/inventory/loot_drops.gd"
	if not ResourceLoader.exists(path):
		return
	var drops: Node = (load(path) as GDScript).new()
	drops.name = "LootDrops"
	drops.add_to_group("loot_drops")
	add_child(drops)
	services["LootDrops"] = drops


func service(display_name: String) -> Node:
	return services.get(display_name)
