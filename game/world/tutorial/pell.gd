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
const STRAW := Color(0.66, 0.55, 0.3)
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
	## what an AnimationDriver looks for in a body; a straw man has no clip events to say
	@warning_ignore("unused_signal")
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
		# a sheaf for a body, bound at the waist and the chest, splaying at its foot; a smaller
		# sheaf for a head, bound at the neck; and the arms, a bundle along the cross-piece
		_sheaf(0.2, 0.26, 0.66, Vector3(0.0, 1.18, 0.02), straw)
		_sheaf(0.26, 0.16, 0.14, Vector3(0.0, 0.8, 0.02), straw)
		_sheaf(0.17, 0.18, 0.28, Vector3(0.0, 1.7, 0.0), straw)
		_sheaf(0.215, 0.215, 0.05, Vector3(0.0, 1.0, 0.02), twine)
		_sheaf(0.2, 0.2, 0.05, Vector3(0.0, 1.36, 0.02), twine)
		_sheaf(0.175, 0.175, 0.05, Vector3(0.0, 1.57, 0.0), twine)
		var arms := _sheaf(0.07, 0.07, 0.95, Vector3(0.0, 1.45, 0.05), straw)
		arms.rotation.z = PI * 0.5

	func _sheaf(top_r: float, bottom_r: float, height: float, at: Vector3, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = top_r
		c.bottom_radius = bottom_r
		c.height = height
		c.radial_segments = 10
		c.rings = 2
		mi.mesh = c
		mi.material_override = mat
		mi.position = at
		_figure.add_child(mi)
		return mi

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
