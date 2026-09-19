class_name BossArena
extends Area3D
## Fog-gate-ready boss arena trigger: when the player crosses the threshold the gate closes
## behind them, the boss wakes, and EventBus.boss_started fires (the boss itself emits it).
## On boss_defeated the gate opens and the trigger disarms. The fog plane is a child node
## named "FogGate" when present; otherwise this is purely logical and a UI/VFX stream can add one.

signal arena_entered(boss_id: String)
signal arena_cleared(boss_id: String)

const LAYER_TRIGGER := 1 << 8
const MASK_PLAYER := 1 << 1

@export var boss_id: String = ""
@export var boss_spawner_path: NodePath
@export var one_shot: bool = true
@export var close_gate: bool = true

var armed: bool = true
var active: bool = false
var boss: Enemy = null
var gate: Node3D = null


func _ready() -> void:
	collision_layer = LAYER_TRIGGER
	collision_mask = MASK_PLAYER
	monitoring = true
	monitorable = false
	gate = get_node_or_null("FogGate") as Node3D
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
	if id != boss_id or not active:
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
