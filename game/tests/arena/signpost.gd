extends StaticBody3D
## A minimal interactable for the test arena: proves the Interactor's prompt and interact path
## without depending on the world or dialogue streams. Real interactables (doors, containers,
## Hearthstones) implement the same two methods.

signal interacted(who: Node)

const LAYER_INTERACTABLE := 1 << 4

@export var label: String = "Read the signpost"
@export var text: String = "MERROWBY 2 · TAMWICK 5 · and the Toll, which you can see for yourself."

var times_used: int = 0


func _ready() -> void:
	collision_layer = LAYER_INTERACTABLE
	collision_mask = 0
	if get_child_count() == 0:
		_build()


func _build() -> void:
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.8, 0.12)
	post.mesh = post_mesh
	post.position = Vector3(0.0, 0.9, 0.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.33, 0.22)
	post.material_override = wood
	add_child(post)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.9, 0.35, 0.06)
	board.mesh = board_mesh
	board.position = Vector3(0.0, 1.55, 0.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.8, 0.64)
	board.material_override = paint
	add_child(board)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.9, 0.3)
	shape.shape = box
	shape.position = Vector3(0.0, 0.95, 0.0)
	add_child(shape)


func prompt_text() -> String:
	return label


func interact(who: Node) -> void:
	times_used += 1
	EventBus.notify.emit(text, "read")
	interacted.emit(who)
