class_name PropertySign
extends StaticBody3D
## A "for sale" board outside a house. Interacting offers the deed for its asking price; a
## steward NPC offers the same deed through dialogue by calling `PropertyRegistry.buy`.
## Signs are in the "interactable" group, so the player's interaction ray finds them.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

signal offer_made(property_id: String, price: int)

@export var property_id := ""
@export var steward_npc := ""
@export var seller_faction := ""
## With `confirm_required` the sign only quotes a price and emits `offer_made`; the UI calls
## `accept(player)` when the player agrees. Without it, interacting buys outright.
@export var confirm_required := true


func _ready() -> void:
	add_to_group("interactable")
	# The physics layer the player's interaction ray masks. It used to be set only in this
	# class's .tscn, so a node built with `.new()` kept Godot's default layer 1 and the ray
	# went straight through it — visible, in the group, with an `interact()` method, and
	# impossible to walk up to. `container.gd` and `world_item.gd` always set their own.
	collision_layer = INTERACT_LAYER
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
		var shown := PropertyRegistry.display_name(property_id)
		var due := reg.rent_due(property_id)
		if due > 0:
			return "Collect %d marks of rent from %s" % [due, shown]
		if reg.is_let(property_id):
			return "%s (let, %d marks a day)" % [shown, PropertyRegistry.rent_per_day(property_id)]
		return "Let %s (%d marks a day)" % [shown, PropertyRegistry.rent_per_day(property_id)]
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
		# the steward is asked in a conversation (Social.talk), which says dialogue_started itself once
		# it has begun: emitting that and stopping, as this did, started nothing
		Social.talk(steward_npc)
		return
	offer_made.emit(property_id, price())
	# The node signal had no listener outside a test, so a board with `confirm_required` set
	# quoted a price into the air and nothing was drawn. The deed screen listens on the bus.
	EventBus.property_offered.emit(property_id, price())
	if not confirm_required:
		accept(actor)


## The board outside a house you already own is the only place the game asks you to be a
## landlord. Letting and rent were built and had nowhere to be done from, so standing at your
## own sign used to tell you that you owned it and nothing else.
##
## It used to go through the registry directly and silently, and which of three things one
## interaction did depended on state the board never showed: the first press collected the
## rent, the next put the house to let, the next took it off the market. So it opens the same
## screen the for-sale board opens, in its owner mode — the rent waiting, whether the place is
## let, and the furnishings on offer for it, each on its own button. `prompt_text()` still
## says what is waiting, because that is what you read before you walk up to it.
##
## The price on the signal is the deed's own posting rather than today's asking price: the
## screen's owner mode never quotes it, and what a house you already own is worth is what is
## written on the deed, not what somebody would take for it this afternoon.
func _landlord(_reg: PropertyRegistry, _actor: Node) -> void:
	EventBus.property_offered.emit(property_id, PropertyRegistry.price_of(property_id))


func accept(actor: Node) -> Dictionary:
	var reg := registry()
	if reg == null:
		return {"ok": false, "reason": "no_registry", "price": 0}
	return reg.buy(actor, property_id, seller_faction)
