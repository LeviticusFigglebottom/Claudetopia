class_name Pell
extends Actor
## A post to cut at in a drill yard (docs/FIGHTING_STYLE_STARTS.md §3.1). It is struck as anything
## is struck -- the blow is resolved, lands, throws splinters and is heard (Impact), and a lesson
## counts it (EventBus.act_done: hit_light, hit_heavy, stagger) -- and it never falls: whatever a
## blow takes, the post has again. A lock-on finds it, so the yard can teach that too. One of a
## yard's pells has a straw man lashed to it, which jerks and settles when it is hit.
##
## The post itself is drawn with the yard (Settlement._drill_yard); this is its body, and the straw.

const POST_RADIUS := 0.3
const POST_HEIGHT := 1.9
const STRAW := Color(0.78, 0.66, 0.38)
const TWINE := Color(0.42, 0.33, 0.22)

## Whether this pell carries the straw man.
var straw_man := false


func _init() -> void:
	faction = "training"
	body_kind = "none"
	display_name = "Pell"
	capsule_radius = POST_RADIUS
	capsule_height = POST_HEIGHT
	max_health = 100000.0
	poise_max = 30.0


func _ready() -> void:
	var pivot := Node3D.new()
	pivot.name = "Model"
	pivot.rotation.y = PI
	var figure := _Straw.new()
	figure.name = "Straw"
	figure.drawn = straw_man
	pivot.add_child(figure)
	add_child(pivot)
	super()
	collision_layer = LAYER_ENEMY
	collision_mask = 0
	body_material = "wood"
	add_to_group("lockable")
	add_to_group("pell")


func content_id() -> String:
	return ""


## Whatever the blow, the post is whole again after it.
func take_hit(hit: HitData) -> String:
	var outcome := super.take_hit(hit)
	health = max_health
	return outcome


func lock_point() -> Vector3:
	return global_position + Vector3.UP * 1.35


func is_hostile_to(other: Node) -> bool:
	# anybody may cut at a pell; it cuts at nobody
	return other != null and other != self and other is Actor and (other as Actor).faction == "player"


## The straw man, and what an AnimationDriver asks of a body: a blow jerks it back, and it settles.
class _Straw extends Node3D:
	signal clip_event(event_name: String)
	var drawn := false
	var _shake := 0.0
	var _figure: Node3D = null

	func _ready() -> void:
		if not drawn:
			return
		_figure = Node3D.new()
		add_child(_figure)
		var straw := StandardMaterial3D.new()
		straw.albedo_color = Pell.STRAW
		straw.roughness = 1.0
		var twine := StandardMaterial3D.new()
		twine.albedo_color = Pell.TWINE
		twine.roughness = 1.0
		# a sheaf for a body, a smaller one for a head, bound at the neck and the waist, and the
		# arms along the post's cross-piece
		_part(Vector3(0.46, 0.62, 0.28), Vector3(0.0, 1.2, 0.02), straw)
		_part(Vector3(0.26, 0.28, 0.24), Vector3(0.0, 1.68, 0.02), straw)
		_part(Vector3(0.48, 0.05, 0.3), Vector3(0.0, 1.0, 0.02), twine)
		_part(Vector3(0.3, 0.05, 0.26), Vector3(0.0, 1.52, 0.02), twine)
		_part(Vector3(0.95, 0.14, 0.16), Vector3(0.0, 1.45, 0.03), straw)

	func _part(size: Vector3, at: Vector3, mat: Material) -> void:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.material_override = mat
		mi.position = at
		_figure.add_child(mi)

	func play_intent(clip: String) -> void:
		if clip.begins_with("Hit") or clip.begins_with("Stagger") or clip == "Block_Hit":
			_shake = 1.0 if clip.begins_with("Hit_Heavy") or clip.begins_with("Stagger") else 0.6

	func set_locomotion(_v: Vector2, _sneaking: bool) -> void:
		pass

	func _process(delta: float) -> void:
		if _figure == null or _shake <= 0.0:
			return
		_shake = maxf(_shake - delta * 2.2, 0.0)
		var t := float(Time.get_ticks_msec()) * 0.001
		_figure.rotation = Vector3(sin(t * 31.0) * 0.12 * _shake - 0.1 * _shake, sin(t * 23.0) * 0.08 * _shake, 0.0)
