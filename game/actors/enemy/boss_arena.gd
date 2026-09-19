class_name BossArena
extends Area3D
## Fog-gate-ready boss arena trigger: when the player crosses the threshold the gate closes
## behind them, the boss wakes, and EventBus.boss_started fires (the boss itself emits it).
## On boss_defeated the gate opens and the trigger disarms. The fog plane is a child node
## named "FogGate" when present; otherwise this is purely logical and a UI/VFX stream can add one.
##
## It is also the floor of the fight. `radius` is the ground the player has, measured from
## `centre`; `shrink(m)` takes metres off it and keeps them (the Hart of Thorns' Briar closing
## across the Standing Moot), and anything standing outside the bound is in the thorns and
## bleeding. `light_by_renown()` puts out every light inside the bound except the few the
## player's renown keeps burning (the Last Cantor's third phase). Both are no-ops until a fight
## asks for them, so an ordinary arena behaves exactly as it did before.

signal arena_entered(boss_id: String)
signal arena_cleared(boss_id: String)
signal bound_changed(radius: float)
signal lights_dimmed(left_burning: int)

const LAYER_TRIGGER := 1 << 8
const MASK_PLAYER := 1 << 1
const GROUP := "boss_arena"
const DEFAULT_RADIUS := 18.0
const MIN_RADIUS := 5.0
## What the ground outside the bound does per second, and the bleed it leaves behind.
const EDGE_DAMAGE_PER_S := 14.0
const EDGE_BLEED := 4.0

@export var boss_id: String = ""
@export var boss_spawner_path: NodePath
@export var one_shot: bool = true
@export var close_gate: bool = true
## The ground the fight is held on. 0 means unbounded: nothing is outside it.
@export var radius: float = 0.0
@export var min_radius: float = MIN_RADIUS
## Where the bound is measured from; defaults to this node's own position.
@export var centre: Vector3 = Vector3.ZERO

var armed: bool = true
var active: bool = false
var boss: Enemy = null
var gate: Node3D = null
var dimmed: bool = false

var _edge_time: float = 0.0
var _restore: Array = []              # [{light, energy}] for every light this arena put out
var _kept: Array[Light3D] = []        # the ones it left burning


func _ready() -> void:
	collision_layer = LAYER_TRIGGER
	collision_mask = MASK_PLAYER
	# A bound improvised around a boss guards no threshold, so it watches for nobody crossing one.
	monitoring = armed
	monitorable = false
	gate = get_node_or_null("FogGate") as Node3D
	add_to_group(GROUP)
	if centre == Vector3.ZERO and is_inside_tree():
		centre = global_position
	body_entered.connect(_on_body_entered)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	_set_gate(false)


func _on_body_entered(body: Node3D) -> void:
	if not armed or active or not body.is_in_group("player"):
		return
	active = true
	armed = not one_shot
	boss = _find_boss()
	if boss != null:
		boss.start_boss()
		boss.perception.alert_to(body.global_position, body)
	if close_gate:
		_set_gate(true)
	arena_entered.emit(boss_id)


func _find_boss() -> Enemy:
	if not boss_spawner_path.is_empty():
		var sp := get_node_or_null(boss_spawner_path) as EnemySpawner
		if sp != null:
			var found := sp.find_by_id(boss_id)
			if found != null:
				return found
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Enemy and (n as Enemy).enemy_id == boss_id:
			return n as Enemy
	return null


func _on_boss_defeated(id: String) -> void:
	if id != boss_id:
		return
	# Whatever the fight did to the room, winning undoes: the thorns die back and the lights
	# come up. A player who has to walk out of a dark shrinking room has not really won.
	restore_lights()
	radius = 0.0
	if not active:
		return
	active = false
	_set_gate(false)
	arena_cleared.emit(boss_id)


## A closed gate blocks the player's exit; an open one lets them pass.
func _set_gate(closed: bool) -> void:
	if gate == null:
		return
	gate.visible = closed
	for c in gate.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not closed)
	if gate is CollisionObject3D:
		(gate as CollisionObject3D).set_deferred("collision_layer", (1 << 0) if closed else 0)


# --- the floor of the fight -------------------------------------------------------------------

## The arena a boss is fighting in: one already placed for it if a designer put one there,
## otherwise a bound improvised around where the boss was standing when it woke. Mirrors
## `EnemySpawner.for_node()`, so a fight works in a bespoke arena and in a generated chamber
## alike without the content having to know which it got.
static func for_boss(enemy: Node3D) -> BossArena:
	if enemy == null or not enemy.is_inside_tree():
		return null
	var wanted := str(enemy.get("enemy_id"))
	for n in enemy.get_tree().get_nodes_in_group(GROUP):
		if n is BossArena and (n as BossArena).boss_id == wanted:
			return n as BossArena
	var made := BossArena.new()
	made.name = "BossArena_" + Ids.name_of(wanted)
	made.boss_id = wanted
	# An improvised bound is not a fog gate: it guards no threshold and closes nothing.
	made.close_gate = false
	made.armed = false
	made.monitoring = false
	made.radius = 0.0
	made.centre = enemy.global_position
	var parent: Node = enemy.get_parent()
	if parent == null:
		return null
	parent.add_child(made)
	made.centre = enemy.global_position
	return made


## True when this arena is holding the player to a piece of ground.
func is_bounded() -> bool:
	return radius > 0.0


## Takes `metres` of floor away and keeps them. The first call on an unbounded arena sets the
## bound at the default and then shrinks it, which is what "the circle loses three metres" means
## when nobody has measured the circle.
func shrink(metres: float) -> float:
	if metres <= 0.0:
		return radius
	if radius <= 0.0:
		radius = DEFAULT_RADIUS
	radius = maxf(radius - metres, min_radius)
	bound_changed.emit(radius)
	return radius


func set_bound(new_radius: float) -> void:
	radius = maxf(new_radius, 0.0)
	bound_changed.emit(radius)


func is_outside(point: Vector3) -> bool:
	if not is_bounded():
		return false
	var flat := Vector3(point.x - centre.x, 0.0, point.z - centre.z)
	return flat.length() > radius


func _physics_process(delta: float) -> void:
	if not is_bounded():
		return
	_edge_time += delta
	if _edge_time < 0.5:
		return
	var elapsed := _edge_time
	_edge_time = 0.0
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node3D) or not n.has_method("take_hit"):
			continue
		if not is_outside((n as Node3D).global_position):
			continue
		var hit := HitData.new()
		hit.amount = EDGE_DAMAGE_PER_S * elapsed
		hit.kind = "slash"
		hit.poise_damage = 0.0
		hit.blockable = false
		hit.parryable = false
		hit.dodgeable = false
		hit.label = "arena:thorns"
		hit.origin = centre
		hit.statuses = [{"id": "bleeding", "duration": 4.0, "magnitude": EDGE_BLEED}]
		n.call("take_hit", hit)


# --- what stays lit ------------------------------------------------------------------------------

## The Last Cantor's third phase: the colour goes out of the room and only what the player is
## known for stays lit. Every light inside the bound is put out except the brightest few, and
## how many that is comes straight off their renown tier.
func light_by_renown(on: bool) -> void:
	if not on:
		restore_lights()
		return
	var tier := int(Peers.reaction_profile().get("renown_tier", 0))
	dim_to(EnemyAbilities.lights_for_renown(tier))


## Puts out every light in the arena except the `keep` strongest. Idempotent: calling it again
## measures against what was originally burning, not against what is left.
func dim_to(keep: int) -> void:
	restore_lights()
	var lights := lights_in_arena()
	lights.sort_custom(func(a: Light3D, b: Light3D) -> bool: return a.light_energy > b.light_energy)
	var kept := maxi(keep, 0)
	for i in lights.size():
		if i < kept:
			_kept.append(lights[i])
			continue
		var light := lights[i]
		_restore.append({"light": light, "energy": light.light_energy})
		light.light_energy = 0.0
	dimmed = not _restore.is_empty()
	lights_dimmed.emit(_kept.size())


func restore_lights() -> void:
	for entry in _restore:
		var light: Variant = (entry as Dictionary).get("light")
		if light is Light3D and is_instance_valid(light):
			(light as Light3D).light_energy = float((entry as Dictionary).get("energy", 1.0))
	_restore.clear()
	_kept.clear()
	dimmed = false


## The lights this arena left burning, in the order it chose them.
func kept_lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	for light in _kept:
		if is_instance_valid(light):
			out.append(light)
	return out


## Every light standing on this fight's floor. An unbounded arena takes the lights of the whole
## loaded scene, because a fight with no measured bound is still a fight in a room. The sky is
## never one of them: a Cantor can put out a chapter-house, not the sun.
func lights_in_arena() -> Array[Light3D]:
	var out: Array[Light3D] = []
	_collect_lights(get_tree().root, out)
	return out


func _collect_lights(node: Node, out: Array[Light3D]) -> void:
	if node is Light3D and not (node is DirectionalLight3D):
		var light := node as Light3D
		if light.light_energy > 0.0 and (not is_bounded() or not is_outside(light.global_position)):
			out.append(light)
	for c in node.get_children():
		_collect_lights(c, out)


func lights_out() -> int:
	return _restore.size()


## Is this point standing in one of the lights that is still burning? Once the Cantor has put
## the room out, the few lamps left are the deeds the player is known for, and standing in one
## is the difference the fiction promises: `spares_lit` on his note reads this.
func lit_at(point: Vector3) -> bool:
	if not dimmed:
		return true
	for light in kept_lights():
		if light.light_energy <= 0.0:
			continue
		var reach := 0.0
		if light is OmniLight3D:
			reach = (light as OmniLight3D).omni_range
		elif light is SpotLight3D:
			reach = (light as SpotLight3D).spot_range
		if reach > 0.0 and light.global_position.distance_to(point) <= reach:
			return true
	return false
