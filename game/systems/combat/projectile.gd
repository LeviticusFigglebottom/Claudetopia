class_name Projectile
extends Node3D
## Kinematic projectile (arrows, spell bolts): gravity arc, swept ray each physics tick so it
## cannot tunnel, delivers HitData to the first Hurtbox it crosses, sticks into world geometry
## (arrows) or vanishes (bolts). Visuals are children; the root is what moves.

signal landed(position: Vector3, stuck: bool)
signal struck(victim: Node, hit: HitData, outcome: String)
## An arrow that survived its landing in the world, as the pickup left in its place.
signal recovered(pickup: Node)

const MASK_WORLD := 1 << 0
const MASK_TERRAIN := 1 << 10
const MASK_HURTBOX := 1 << 5
const WORLD_ITEM_SCENE := "res://systems/inventory/world_item.tscn"

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 9.81
var hit: HitData = null
var sticks: bool = true
var lifetime: float = 20.0
var max_range: float = 90.0
var trail_color: Color = Color.TRANSPARENT
## The Foley id it makes where it lands, on a body or on the world ("" for none): arrow_hit for an
## arrow, spell_impact_<school> for a saying's bolt.
var impact_sound: String = ""
## The ammunition this is (an arrow's item id), and the chance it survives where it lands: stuck in
## the world it is left there to be picked up, stuck in a body it is lodged there until the body
## falls (Actor.lodge). Empty for a saying's bolt, which nothing recovers.
var recover_item: String = ""
var recover_chance: float = 0.0
## Rolls recovery; seeded by a test that needs a known outcome.
var rng: RandomNumberGenerator = null

var _stuck: bool = false
var _travelled: float = 0.0
var _exclude: Array[RID] = []
var _age: float = 0.0
var _armed: bool = false


func launch(from: Vector3, direction: Vector3, speed: float, hit_data: HitData, gravity_accel: float = 9.81) -> void:
	global_position = from
	velocity = direction.normalized() * speed
	gravity = gravity_accel
	hit = hit_data
	_exclude.clear()
	if hit != null and hit.attacker != null and is_instance_valid(hit.attacker):
		if hit.attacker is CollisionObject3D:
			_exclude.append((hit.attacker as CollisionObject3D).get_rid())
		var hb: Node = hit.attacker.get("hurtbox")
		if hb is CollisionObject3D:
			_exclude.append((hb as CollisionObject3D).get_rid())
	_orient()
	_armed = true


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck or not _armed:
		if _age > lifetime:
			queue_free()
		return
	var from := global_position
	var next := from + velocity * delta
	velocity.y -= gravity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, next, MASK_WORLD | MASK_TERRAIN | MASK_HURTBOX, _exclude)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := space.intersect_ray(query)
	if result.is_empty():
		global_position = next
		_travelled += (next - from).length()
		_orient()
		if _travelled > max_range or global_position.y < -200.0:
			queue_free()
		return
	var collider: Object = result.get("collider")
	var point: Vector3 = result.get("position", next)
	if collider is Hurtbox:
		var hb := collider as Hurtbox
		if hit != null and hb.actor != null and hb.actor != hit.attacker:
			var h := hit.copy()
			h.origin = from
			h.source = self
			var outcome := hb.receive_hit(h)
			_sound(point)
			if outcome == "hit" and hb.actor.has_method("lodge") and _recovers():
				hb.actor.lodge(recover_item)
			struck.emit(hb.actor, h, outcome)
			landed.emit(point, false)
			queue_free()
			return
		# our own or a friendly hurtbox: keep flying past it
		_exclude.append(hb.get_rid())
		global_position = point + velocity.normalized() * 0.05
		return
	# world geometry
	global_position = point
	_sound(point)
	if sticks:
		_stuck = true
		global_position = point + velocity.normalized() * 0.12
		_age = maxf(_age, lifetime - 15.0)
		landed.emit(point, true)
		if _recovers():
			_leave_to_be_found(point)
	else:
		landed.emit(point, false)
		queue_free()


## Whether this one survives where it landed (never for a bolt of light, or when no chance is set).
func _recovers() -> bool:
	if recover_item.is_empty() or recover_chance <= 0.0 or not ContentDB.has(recover_item):
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng.randf() < recover_chance


## An arrow that stood its landing becomes the thing it is again: a pickup where it struck, in
## place of the shaft that flew there.
func _leave_to_be_found(point: Vector3) -> void:
	var scene := load(WORLD_ITEM_SCENE) as PackedScene
	var parent := get_parent()
	if scene == null or parent == null:
		return
	var wi := scene.instantiate()
	wi.set("item_id", recover_item)
	wi.set("count", 1)
	wi.set("bob", false)
	parent.add_child(wi)
	if wi is Node3D and (wi as Node3D).is_inside_tree():
		(wi as Node3D).global_position = point
	recovered.emit(wi)
	queue_free()


func _sound(at: Vector3) -> void:
	if not impact_sound.is_empty():
		Foley.play(impact_sound, at)


func _orient() -> void:
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD)


## Builds a simple glowing bolt visual (used by spells when no scene is given).
static func make_bolt(color: Color, radius: float = 0.12) -> Projectile:
	var p := Projectile.new()
	p.name = "Bolt"
	p.sticks = false
	p.lifetime = 6.0
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	p.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 3.0
	light.light_energy = 1.2
	p.add_child(light)
	return p
