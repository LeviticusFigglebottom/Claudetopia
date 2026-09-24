class_name NpcSpot
extends Marker3D
## Where somebody stands at a point of interest: the `spot` a schedule entry or a story hold
## names, raised by the POI's dressing and named for it (the Warden by the fire at the Stair Head
## is `wren_stair_head`). `Npc` already walks to a node of its spot's name; this puts whoever the
## registry stands up with this spot here at once, facing the way the marker faces, instead of on
## the ring round the place's middle with a walk still to do. At the Stair Head that walk would
## still be going on when the opening hands control over, and the first thing the player saw
## would be the Warden's back.

const GROUP := "npc_spot"

## The place this spot belongs to, so a spot name two places share cannot pull a person from one
## to the other. Empty accepts anyone with the spot.
var place_id := ""


func _ready() -> void:
	add_to_group(GROUP)
	# the registry's own reading of whose marker this is (NpcRegistry.spot_marker)
	if not place_id.is_empty():
		set_meta("place", place_id)
	var reg := NpcRegistry.instance
	if reg == null:
		return
	if not reg.npc_spawned.is_connected(_on_npc_spawned):
		reg.npc_spawned.connect(_on_npc_spawned)
	# the cell's people can stand up before its dressing does; but a dressing raised again round
	# somebody the player is with (NpcRegistry.is_kept) does not pick them up and put them down
	for id: String in reg.states:
		if reg.is_spawned(id) and not reg.is_kept(id):
			_on_npc_spawned(id, reg.actor(id))


## Whether `npc_id`, by the registry's account, should be standing at this spot now. Somebody on
## the road is not, although the spot they are walking to is theirs.
func is_for(npc_id: String) -> bool:
	var reg := NpcRegistry.instance
	if reg == null or reg.is_travelling(npc_id):
		return false
	var s := reg.state(npc_id)
	if str(s.get("spot", "")) != str(name):
		return false
	return place_id.is_empty() or str(s.get("place", "")) == place_id


func _on_npc_spawned(npc_id: String, node: Node) -> void:
	if not is_inside_tree() or not (node is Node3D) or not is_for(npc_id):
		return
	var body := node as Node3D
	if not body.is_inside_tree():
		return
	body.global_position = global_position
	if "velocity" in body:
		body.set("velocity", Vector3.ZERO)
	if body.has_method("stop"):
		body.call("stop")
	# the marker's forward (-Z) is the way they face; an Npc turns its model, anything else itself
	var facing := -global_transform.basis.z
	if body.has_method("face_direction"):
		body.call("face_direction", facing)
	else:
		body.global_rotation = Vector3(0.0, atan2(-facing.x, -facing.z), 0.0)
	body.reset_physics_interpolation()
