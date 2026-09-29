class_name Pell
extends Actor
## A post to cut at in a drill yard (docs/FIGHTING_STYLE_STARTS.md §3.1). It is struck as anything
## is struck -- the blow is resolved, lands, throws splinters and is heard (Impact), and a lesson
## counts it (EventBus.act_done: hit_light, hit_heavy, stagger) -- and it never falls: whatever a
## blow takes, the post has again. A lock-on finds it, so the yard can teach that too. One of a
## yard's pells has a straw man lashed to it, which jerks and settles when it is hit.
##
## The post itself is drawn with the yard (Settlement._drill_yard); this is its body, and the straw.
##
## The same body is the other things a start's lessons are made on (`kind`, laid by QuestSpots from a
## quest's `props`): a `butt`, a straw boss on a trestle with painted rings, for the bow; a
## `brazier`, an iron bowl on a tripod that a fire saying lights (it says `kindle`, and burns); a
## `sack` of eels hung from a stilt, for the rogue's dagger: it never sees you coming, so a crouched
## blow at it is a sneak attack (Player._sneak_crit). Its
## content id is `prop:<kind>` (a yard's post is `prop:pell`), which a lesson's `against` names, so
## the objective marker can point at the thing itself (triage 49, 51).

const POST_RADIUS := 0.3
const POST_HEIGHT := 1.9
const STRAW := Color(0.66, 0.55, 0.3)
const TWINE := Color(0.42, 0.33, 0.22)

## Whether this pell carries the straw man.
var straw_man := false
## pell | butt | brazier | sack
var kind := "pell"
## A brazier that has been kindled.
var lit := false
var _flame: Node3D = null


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
	match kind:
		"butt":
			capsule_radius = 0.6
			capsule_height = 1.7
			_draw_butt(pivot)
		"brazier":
			capsule_radius = 0.45
			capsule_height = 1.3
			body_material = "metal"
			_draw_brazier(pivot)
		"sack":
			capsule_radius = 0.4
			capsule_height = 1.1
			_draw_sack(pivot)
	super()
	collision_layer = LAYER_ENEMY
	collision_mask = 0
	body_material = "metal" if kind == "brazier" else "flesh" if kind == "sack" else "wood"
	add_to_group("lockable")
	add_to_group("pell")


func content_id() -> String:
	return "prop:" + kind


## Whatever the blow, the post is whole again after it. A fire saying lights a brazier.
func take_hit(hit: HitData) -> String:
	var outcome := super.take_hit(hit)
	health = max_health
	if kind == "brazier" and not lit and (hit.kind == "fire" or hit.skill_id.ends_with("kindling")):
		kindle(hit.attacker)
	return outcome


## The brazier catches: a flame, its light, and a lesson told (`kindle`).
func kindle(by: Node = null) -> void:
	if lit:
		return
	lit = true
	_flame = Node3D.new()
	_flame.name = "Flame"
	add_child(_flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.position = Vector3(0.0, 1.45, 0.0)
	_flame.add_child(light)
	var fire := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.26
	cone.height = 0.55
	fire.mesh = cone
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.18)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.5, 0.15)
	glow.emission_energy_multiplier = 2.5
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.material_override = glow
	fire.position = Vector3(0.0, 1.38, 0.0)
	_flame.add_child(fire)
	EventBus.act_done.emit("kindle", by, self, "")


func _mat(c: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9 if metal <= 0.0 else 0.55
	m.metallic = metal
	return m


func _add(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A straw boss bound in twine, lashed upright to a trestle, a painted face of rings towards the
## shooter (the model's +Z).
func _draw_butt(pivot: Node3D) -> void:
	var wood := _mat(Color(0.4, 0.3, 0.2))
	for sx in [-0.55, 0.55]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.09, 1.5, 0.09)
		_add(pivot, leg, Vector3(float(sx), 0.72, -0.28), wood, Vector3(-0.28, 0.0, 0.0))
	var bar := BoxMesh.new()
	bar.size = Vector3(1.3, 0.08, 0.08)
	_add(pivot, bar, Vector3(0.0, 0.5, -0.18), wood)
	var boss := CylinderMesh.new()
	boss.top_radius = 0.62
	boss.bottom_radius = 0.62
	boss.height = 0.34
	boss.radial_segments = 20
	_add(pivot, boss, Vector3(0.0, 1.12, 0.0), _mat(Pell.STRAW), Vector3(PI * 0.5, 0.0, 0.0))
	var rings := [[0.56, Color(0.86, 0.82, 0.7)], [0.42, Color(0.25, 0.3, 0.42)], [0.28, Color(0.72, 0.2, 0.14)], [0.12, Color(0.9, 0.72, 0.2)]]
	for i in rings.size():
		var ring := CylinderMesh.new()
		ring.top_radius = float(rings[i][0])
		ring.bottom_radius = float(rings[i][0])
		ring.height = 0.02
		ring.radial_segments = 20
		_add(pivot, ring, Vector3(0.0, 1.12, 0.175 + 0.004 * float(i)), _mat(rings[i][1]), Vector3(PI * 0.5, 0.0, 0.0))


## A sack of eels on a hook from a crossbar on two stakes, bulging and wet, at a man's height.
func _draw_sack(pivot: Node3D) -> void:
	var wood := _mat(Color(0.36, 0.28, 0.2))
	for sx in [-0.5, 0.5]:
		var stake := BoxMesh.new()
		stake.size = Vector3(0.08, 1.9, 0.08)
		_add(pivot, stake, Vector3(float(sx), 0.95, -0.1), wood)
	var bar := BoxMesh.new()
	bar.size = Vector3(1.1, 0.07, 0.07)
	_add(pivot, bar, Vector3(0.0, 1.85, -0.1), wood)
	var sack := CapsuleMesh.new()
	sack.radius = 0.3
	sack.height = 0.95
	_add(pivot, sack, Vector3(0.0, 1.12, -0.1), _mat(Color(0.47, 0.42, 0.3)))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.05
	neck.bottom_radius = 0.09
	neck.height = 0.2
	_add(pivot, neck, Vector3(0.0, 1.68, -0.1), _mat(Pell.TWINE))


## An iron fire-basket on three legs, cold until a saying lights it.
func _draw_brazier(pivot: Node3D) -> void:
	var iron := _mat(Color(0.2, 0.19, 0.18), 0.6)
	for k in 3:
		var a := TAU * float(k) / 3.0
		var leg := BoxMesh.new()
		leg.size = Vector3(0.05, 1.2, 0.05)
		_add(pivot, leg, Vector3(cos(a) * 0.22, 0.58, sin(a) * 0.22), iron, Vector3(sin(a) * 0.18, 0.0, -cos(a) * 0.18))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.36
	bowl.bottom_radius = 0.2
	bowl.height = 0.26
	bowl.radial_segments = 14
	_add(pivot, bowl, Vector3(0.0, 1.2, 0.0), iron)
	var coal := CylinderMesh.new()
	coal.top_radius = 0.33
	coal.bottom_radius = 0.33
	coal.height = 0.04
	_add(pivot, coal, Vector3(0.0, 1.31, 0.0), _mat(Color(0.12, 0.1, 0.09)))


func lock_point() -> Vector3:
	return global_position + Vector3.UP * (1.12 if kind in ["butt", "sack"] else 1.25 if kind == "brazier" else 1.35)


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
