class_name Projectile
extends Node3D
## Kinematic projectile (arrows, spell bolts): gravity arc, swept ray each physics tick so it
## cannot tunnel, delivers HitData to the first Hurtbox it crosses, sticks into world geometry
## (arrows) or vanishes (bolts). Visuals are children; the root is what moves.

signal landed(position: Vector3, stuck: bool)
signal struck(victim: Node, hit: HitData, outcome: String)

const MASK_WORLD := 1 << 0
const MASK_TERRAIN := 1 << 10
const MASK_HURTBOX := 1 << 5

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 9.81
var hit: HitData = null
var sticks: bool = true
var lifetime: float = 20.0
var max_range: float = 90.0
var trail_color: Color = Color.TRANSPARENT

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
	if sticks:
		_stuck = true
		global_position = point + velocity.normalized() * 0.12
		_age = maxf(_age, lifetime - 15.0)
		landed.emit(point, true)
	else:
		landed.emit(point, false)
		queue_free()


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
