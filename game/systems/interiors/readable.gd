class_name Readable
extends StaticBody3D
## A book lying where somebody left it. Interacting opens the reader on `book_id`; taking it
## is the inventory's business, so a Readable that names an `item_id` hands that over instead
## and goes away, leaving the shelf one book lighter.
##
## Interiors dress themselves with book props; this is what makes one of them worth walking to.

const TAKE_PROMPT := "Take"
const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"

@export var book_id := ""
@export var item_id := ""
@export var display_name := "a book"
## A book chained to its lectern or shelf is read where it lies and never leaves.
@export var fixed := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("readable")
	# The layer the player's interaction ray masks. A body made with `.new()` keeps Godot's
	# default layer 1, which the ray does not see: every shelf book in every house was a prompt
	# nobody could raise, readable only by a test calling `interact()` directly.
	collision_layer = INTERACT_LAYER
	if display_name == "a book" and not book_id.is_empty():
		display_name = str(ContentDB.get_or_empty(book_id).get("title", display_name))
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(0.28, 0.14, 0.24)
		col.shape = box
		col.position.y = 0.07
		add_child(col)


func prompt_text() -> String:
	if fixed or item_id.is_empty():
		return "Read %s" % display_name
	return "%s %s" % [TAKE_PROMPT, display_name]


## Reads it where it lies, or hands it over. Returns what happened, for the tests and for any
## system that wants to know a book has left the room.
func interact(actor: Node) -> Dictionary:
	if fixed or item_id.is_empty():
		if book_id.is_empty():
			return {"ok": false, "reason": "no_book"}
		EventBus.book_opened.emit(book_id)
		return {"ok": true, "read": book_id}
	var bag := _bag_of(actor)
	if bag == null:
		return {"ok": false, "reason": "no_bag"}
	var added: Variant = bag.call("add", item_id, 1)
	if added == null:
		EventBus.notify.emit("You cannot carry that.", "warning")
		return {"ok": false, "reason": "full"}
	EventBus.notify.emit("Taken: %s." % display_name, "item")
	queue_free()
	return {"ok": true, "taken": item_id}


static func _bag_of(actor: Node) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	var bag := actor.get_node_or_null("Inventory")
	if bag == null and actor.has_method("bag"):
		bag = actor.call("bag")
	return bag if bag != null and bag.has_method("add") else null
