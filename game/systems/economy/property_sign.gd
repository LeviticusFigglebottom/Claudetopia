class_name PropertySign
extends StaticBody3D
## A "for sale" board outside a house. Interacting offers the deed for its asking price; a
## steward NPC offers the same deed through dialogue by calling `PropertyRegistry.buy`.
## Signs are in the "interactable" group, so the player's interaction ray finds them.

signal offer_made(property_id: String, price: int)

@export var property_id := ""
@export var steward_npc := ""
@export var seller_faction := ""
## With `confirm_required` the sign only quotes a price and emits `offer_made`; the UI calls
## `accept(player)` when the player agrees. Without it, interacting buys outright.
@export var confirm_required := true


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("property_sign")
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 1.6, 0.12)
		col.shape = box
		col.position.y = 1.0
		add_child(col)
	# Placeholder geometry until the forge makes a painted board; replaced by a prop scene.
	if get_node_or_null("Board") == null and not Engine.is_editor_hint():
		var board := MeshInstance3D.new()
		board.name = "Board"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8, 0.5, 0.06)
		board.mesh = mesh
		board.position.y = 1.5
		add_child(board)
		var post := MeshInstance3D.new()
		post.name = "Post"
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.09, 1.5, 0.09)
		post.mesh = post_mesh
		post.position.y = 0.75
		add_child(post)


func registry() -> PropertyRegistry:
	return PropertyRegistry.ensure()


func price() -> int:
	return registry().asking_price(property_id, seller_faction) if registry() != null else PropertyRegistry.price_of(property_id)


func prompt_text() -> String:
	if property_id.is_empty():
		return "A weathered board"
	var reg := registry()
	if reg != null and reg.is_owned(property_id):
		var name := PropertyRegistry.display_name(property_id)
		var due := reg.rent_due(property_id)
		if due > 0:
			return "Collect %d marks of rent from %s" % [due, name]
		if reg.is_let(property_id):
			return "%s (let, %d marks a day)" % [name, PropertyRegistry.rent_per_day(property_id)]
		return "Let %s (%d marks a day)" % [name, PropertyRegistry.rent_per_day(property_id)]
	if not steward_npc.is_empty():
		return "%s — ask the steward (%d marks)" % [PropertyRegistry.display_name(property_id), price()]
	return "Buy %s (%d marks)" % [PropertyRegistry.display_name(property_id), price()]


func interact(actor: Node) -> void:
	var reg := registry()
	if reg == null or property_id.is_empty():
		return
	if reg.is_owned(property_id):
		_landlord(reg, actor)
		return
	if not steward_npc.is_empty():
		EventBus.dialogue_started.emit(steward_npc)
		return
	offer_made.emit(property_id, price())
	if not confirm_required:
		accept(actor)


## The board outside a house you already own is the only place the game asks you to be a
## landlord. Letting and rent were built and had nowhere to be done from, so standing at your
## own sign used to tell you that you owned it and nothing else. Rent first, because money
## waiting is what you came for; otherwise the board is where you put the word out.
func _landlord(reg: PropertyRegistry, actor: Node) -> void:
	var name := PropertyRegistry.display_name(property_id)
	var due := reg.rent_due(property_id)
	if due > 0:
		reg.collect_rent(actor, property_id)
		return
	if reg.is_let(property_id):
		reg.set_let(property_id, false)
		EventBus.notify.emit("You take %s off the market. Your own key again." % name, "property")
		return
	reg.set_let(property_id, true)
	EventBus.notify.emit("%s is to let, at %d marks a day."
			% [name, PropertyRegistry.rent_per_day(property_id)], "property")


func accept(actor: Node) -> Dictionary:
	var reg := registry()
	if reg == null:
		return {"ok": false, "reason": "no_registry", "price": 0}
	return reg.buy(actor, property_id, seller_faction)
