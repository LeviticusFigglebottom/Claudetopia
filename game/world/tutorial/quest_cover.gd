class_name QuestCover
extends StaticBody3D
## Something to be low behind (docs/FIGHTING_STYLE_STARTS.md §3.4, "hiding"): a quest prop of kind
## `cover`, laid by QuestSpots from a quest's `props` with a `look`:
##   crates - two crates and two more on them, 1.3 m;
##   traps  - wicker eel-traps stacked on their sides to dry, 1.3 m;
##   boat   - a boat turned over on two crates for tarring, 1.35 m.
## It is solid on the world layer, so a person's eye (Npc.can_see_point) and a foe's
## (Perception.has_line_of_sight) stop on it: a body crouched behind it (Stealth.sight_point, the
## small of the back) is out of sight. Its long side runs across the prop's `facing`.

const LOOKS := {"crates": Vector3(1.6, 1.33, 0.8), "traps": Vector3(1.6, 1.3, 1.2), "boat": Vector3(3.8, 1.35, 2.0)}
const WICKER := Color(0.5, 0.4, 0.25)

var look := "crates"


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("quest_cover")
	var box := BoxShape3D.new()
	box.size = size()
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)
	match look:
		"traps":
			_traps()
		"boat":
			_boat()
		_:
			_crates()


func size() -> Vector3:
	return LOOKS.get(look, LOOKS["crates"])


## One of the forge's props, as a mesh only (the cover's own box is what is solid), or a plain box
## where the forge has built none.
func _prop(kind: String, variant: int, at: Vector3, yaw := 0.0, fallback := Vector3(0.75, 0.66, 0.75), flip := false) -> void:
	var path := PoiKit.library().resolve(kind, "sedgemire", variant)
	var m := PoiKit.mesh(path) if path != "" else null
	var mi := MeshInstance3D.new()
	if m != null:
		mi.mesh = m
	else:
		var bm := BoxMesh.new()
		bm.size = fallback
		mi.mesh = bm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.36, 0.27, 0.18)
		mi.material_override = wood
		at.y += fallback.y * (-0.5 if flip else 0.5)
	mi.position = at
	mi.rotation.y = yaw
	if flip:
		mi.rotation.z = PI
	add_child(mi)


func _crates() -> void:
	_prop("crate", 0, Vector3(-0.4, 0.0, 0.0), 0.05)
	_prop("crate", 1, Vector3(0.4, 0.0, 0.02), -0.04)
	_prop("crate", 2, Vector3(-0.38, 0.66, 0.02), 0.12)
	_prop("crate", 3, Vector3(0.36, 0.66, -0.03), -0.1)


func _traps() -> void:
	# long wicker cones on their sides, three, then two, then one, their mouths all one way
	var wicker := StandardMaterial3D.new()
	wicker.albedo_color = WICKER
	wicker.roughness = 0.95
	var rows := [[-0.5, 0.0, 0.5], [-0.25, 0.25], [0.0]]
	for r in rows.size():
		for x in rows[r]:
			var trap := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.18
			c.bottom_radius = 0.26
			c.height = 1.2
			c.radial_segments = 10
			trap.mesh = c
			trap.material_override = wicker
			trap.rotation.x = PI * 0.5
			trap.position = Vector3(float(x), 0.26 + float(r) * 0.42, 0.0)
			add_child(trap)


func _boat() -> void:
	_prop("crate", 4, Vector3(-1.2, 0.0, 0.0), 0.0)
	_prop("crate", 5, Vector3(1.2, 0.0, 0.0), 0.0)
	# turned over, gunwales on the crates, keel up
	_prop("rowboat", 0, Vector3(0.0, 1.33, 0.0), 0.0, Vector3(3.8, 0.66, 1.4), true)
