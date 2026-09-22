class_name Npc
extends CharacterBody3D
## A villager. Follows its schedule between activity spots, reacts to the player, senses
## crimes as a witness, and hands off to the dialogue stream when spoken to.
##
## Movement uses a NavigationAgent3D when the scene has one and a NavigationRegion3D exists;
## otherwise it steers directly and snaps to the ground through World.get_height.
## Perception mirrors the enemy stream's `perception.gd`: a `detection` float 0..1 and
## `noise_heard(pos, loudness)`, so crime witnessing and stealth read the same interface on
## every actor in the game.

signal arrived(place_id: String)
signal activity_changed(activity: String)

const WALK_SPEED := 2.2
const TRAVEL_SPEED := 3.4
const FLEE_SPEED := 5.0
const ARRIVE_M := 1.2
const GRAVITY := 9.81
## Walking with somebody: how close to keep, and how far behind before hurrying.
const FOLLOW_GAP_M := 2.4
const FOLLOW_HURRY_M := 6.0
const CULTURE_COLOURS := {
	"vale": Color(0.78, 0.62, 0.36), "lakefolk": Color(0.72, 0.76, 0.82), "reedfolk": Color(0.28, 0.45, 0.48),
	"clans": Color(0.46, 0.44, 0.40), "woodfolk": Color(0.30, 0.38, 0.24), "pilgrims": Color(0.62, 0.60, 0.56),
}
const MODEL_SCENE := "res://actors/shared/humanoid_model.tscn"

@export var npc_id := ""
@export var sight_range := 18.0
@export var sight_fov := 110.0
@export var hearing_range := 14.0

var def: Dictionary = {}
var personality: Personality = null
var place_id := ""
var activity := "idle"
var spot := ""
var alive := true
var hostile := false
var detection := 0.0
var meter := DetectionMeter.new()
var target_position := Vector3.ZERO
var has_target := false
var fleeing := false
## Whoever this person is walking beside, when they are (Escorts sets it through `follow`).
var follow_target: Node3D = null

var _model: Node3D = null
var _agent: NavigationAgent3D = null
var _use_agent := false
var _intent := ""
var _entry_clip := ""
var _react_accum := 0.0
var _last_heard := Vector3.ZERO


func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")
	if not npc_id.is_empty():
		load_def()
	_model = get_node_or_null("Model")
	_agent = get_node_or_null("NavigationAgent3D")
	_build_placeholder()
	if place_id.is_empty():
		place_id = str(def.get("home_place", ""))
	target_position = global_position
	# The services these actors talk to install themselves on first use, so a village works
	# whether or not the world scene has added them.
	Stealth.ensure()
	Reactions.ensure()
	_build_merchant()


## A shopkeeper carries their trade with them: an npc def with a `merchant` block gets a
## Merchant child, which loads its own stock table and registers with the economy service.
func _build_merchant() -> void:
	if not def.has("merchant") or get_node_or_null("Merchant") != null:
		return
	var m := Merchant.new()
	m.name = "Merchant"
	m.npc_id = npc_id
	add_child(m)


func merchant() -> Merchant:
	return get_node_or_null("Merchant") as Merchant


func load_def() -> void:
	def = ContentDB.get_or_empty(npc_id)
	personality = Personality.from_def(def)
	if def.has("perception"):
		var p: Dictionary = def["perception"]
		sight_range = float(p.get("sight_range", sight_range))
		sight_fov = float(p.get("sight_fov", sight_fov))
		hearing_range = float(p.get("hearing", hearing_range))
	if def.has("tags") and def["tags"].has("guard"):
		add_to_group("guard")


func display_name() -> String:
	return str(def.get("name", Ids.name_of(npc_id)))


func culture() -> String:
	return WorldProbe.culture_of_place(str(def.get("home_place", "")))


## A capsule in the culture's colour until the humanoid model stream lands.
func _build_placeholder() -> void:
	if _model == null:
		_model = Node3D.new()
		_model.name = "Model"
		add_child(_model)
	if ResourceLoader.exists(MODEL_SCENE):
		if _model.get_child_count() == 0:
			var m: Node = load(MODEL_SCENE).instantiate()
			_model.add_child(m)
			# CONTRACTS §1: models face +Z after export; gameplay forward is -Z.
			_model.rotation.y = PI
			if m.has_method("apply_appearance"):
				m.call("apply_appearance", appearance_of())
		return


## What this person looks like. The rig on its own is a naked body: `apply_appearance` is what
## puts clothes on it, and nothing outside the character-creation screen had ever called it —
## so every villager in Wickmere stood in the street with nothing on.
##
## The roll comes first and the def's own numbers are laid over it. A def's `appearance` block
## is written for a person reading it (`"build": "short_thick"`, `"hair": "red_grey_shaved
## _sides"`, a `notes` line about bone dust in the creases of both hands), so only the keys
## that are actually numbers are applied; the prose is for the writer, not for the mesh.
func appearance_of() -> CharacterAppearance:
	var raw: Variant = def.get("appearance", {})
	var block: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var from_seed := int(block.get("seed", abs(npc_id.hash())))
	var look := CharacterAppearance.random(from_seed, culture())
	for key in ["age", "height", "bulk", "feminine", "shoulder_width", "hip_width",
			"limb_length", "neck_length", "head_size", "hearth", "hollow"]:
		if not block.has(key):
			continue
		var v: Variant = block[key]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			look.set(key, float(v))
	return look
	if _model.get_node_or_null("Placeholder") != null:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "Placeholder"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = 1.78
	mesh.mesh = capsule
	mesh.position.y = 0.89
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CULTURE_COLOURS.get(culture(), Color(0.66, 0.60, 0.52))
	if def.get("tags", []).has("child"):
		mesh.scale = Vector3(0.7, 0.7, 0.7)
	if def.get("tags", []).has("guard"):
		mat.metallic = 0.4
		mat.roughness = 0.5
	mesh.material_override = mat
	_model.add_child(mesh)
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.78
		col.shape = shape
		col.position.y = 0.89
		add_child(col)


# --- registry hand-off -------------------------------------------------------------------------

## Applies the abstract state the registry kept while this NPC was off screen.
func apply_state(s: Dictionary) -> void:
	place_id = str(s.get("place", place_id))
	activity = str(s.get("activity", activity))
	spot = str(s.get("spot", spot))
	alive = bool(s.get("alive", true))
	hostile = bool(s.get("hostile", false))
	_apply_activity()


## The state to write back when this NPC is despawned or the game is saved.
func collect_state() -> Dictionary:
	return {"place": place_id, "activity": activity, "spot": spot, "alive": alive, "hostile": hostile}


## The registry calls this when the schedule moves on while the NPC is loaded.
func apply_schedule_state(entry: Dictionary) -> void:
	var was := activity
	place_id = str(entry.get("place", place_id))
	activity = str(entry.get("activity", activity))
	spot = str(entry.get("spot", spot))
	_entry_clip = str(entry.get("clip", ""))
	_go_to_spot()
	if activity != was:
		_apply_activity()


func _apply_activity() -> void:
	play_intent(Schedules.intent_for(activity, {"clip": _entry_clip}, def))
	activity_changed.emit(activity)


# --- movement ----------------------------------------------------------------------------------

## Walks to the current activity spot. Spot markers are looked up by name in the current
## scene (a place scene may name them, e.g. "market_stall"); otherwise the place position
## with the NPC's own deterministic offset is used.
func _go_to_spot() -> void:
	var pos := _spot_position()
	set_move_target(pos)


func _spot_position() -> Vector3:
	if not spot.is_empty() and is_inside_tree():
		var marker := _find_marker(spot)
		if marker != null:
			return marker.global_position
	if NpcRegistry.instance != null:
		return NpcRegistry.instance.spawn_position(npc_id)
	return WorldProbe.place_position(place_id)


func _find_marker(marker_name: String) -> Node3D:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	var found := scene.find_child(marker_name, true, false)
	return found as Node3D


## True only when a NavigationRegion3D has baked a map in this world; otherwise the NPC
## steers directly and snaps to the ground (the world stream may bake one later, so this is
## re-checked whenever a new target is set).
func _navigation_available() -> bool:
	if _agent == null or not is_inside_tree():
		return false
	var world := get_world_3d()
	if world == null:
		return false
	return NavigationServer3D.map_get_regions(world.navigation_map).size() > 0


func set_move_target(pos: Vector3) -> void:
	target_position = pos
	has_target = true
	_use_agent = _navigation_available()
	if _use_agent:
		_agent.target_position = pos


func stop() -> void:
	has_target = false
	velocity.x = 0.0
	velocity.z = 0.0


func current_speed() -> float:
	if fleeing:
		return FLEE_SPEED
	if is_following():
		# keep up: a walk at your elbow, a trot when you have got ahead, a run when well ahead
		var gap := _flat_distance(follow_target.global_position)
		if gap > FOLLOW_HURRY_M * 2.0:
			return FLEE_SPEED
		return TRAVEL_SPEED if gap > FOLLOW_HURRY_M else WALK_SPEED
	return TRAVEL_SPEED if activity == "travel" else WALK_SPEED


# --- walking with somebody (Escorts) ------------------------------------------------------------

## Falls in a step behind `leader` and keeps there until told otherwise. Escorts decides when an
## escort starts, pauses and ends; this is only the walking.
func follow(leader: Node3D) -> void:
	follow_target = leader
	fleeing = false


func stop_following() -> void:
	follow_target = null
	stop()


func is_following() -> bool:
	return follow_target != null and is_instance_valid(follow_target) and follow_target.is_inside_tree()


## Aims a gap short of the leader along the line between, and stands still inside the gap.
func update_follow() -> void:
	if not is_following():
		follow_target = null
		return
	var to := follow_target.global_position - global_position
	to.y = 0.0
	if to.length() <= FOLLOW_GAP_M:
		if has_target:
			stop()
		return
	var aim := follow_target.global_position - to.normalized() * (FOLLOW_GAP_M * 0.8)
	if not has_target or target_position.distance_to(aim) > 1.0:
		set_move_target(aim)


func _flat_distance(to: Vector3) -> float:
	return Vector2(to.x - global_position.x, to.z - global_position.z).length()


# --- standing on something that is not the ground -------------------------------------------------

var _floor_marker: Node3D = null
var _floor_spot := "~"

## The height of the deck or mound this person's spot stands on when that is not the ground: the
## hermit's fire on the crown of an island, which the terrain under it puts at the bottom of the
## lake. A dressing marks such a spot `raised`, with the `radius` it holds for. -INF for a spot on
## the ground, which is nearly everybody's, or once they have walked off it.
func _raised_floor() -> float:
	var stale := _floor_marker != null and not is_instance_valid(_floor_marker)
	if _floor_spot != spot or stale or (_floor_marker == null and Engine.get_physics_frames() % 60 == 0):
		_floor_spot = spot
		_floor_marker = _spot_marker_node(spot)
	if _floor_marker == null or not bool(_floor_marker.get_meta("raised", false)):
		return -INF
	if _flat_distance(_floor_marker.global_position) > float(_floor_marker.get_meta("radius", 3.0)):
		return -INF
	return _floor_marker.global_position.y


func _spot_marker_node(marker_name: String) -> Node3D:
	if marker_name.is_empty() or not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(NpcRegistry.SPOT_GROUP):
		if node is Node3D and str(node.name) == marker_name:
			return node as Node3D
	return null


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_sense(delta)
	if is_following():
		update_follow()
	if has_target:
		_step_towards(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_apply_gravity_or_snap(delta)
	move_and_slide()


func _step_towards(delta: float) -> void:
	var goal := target_position
	if _use_agent and _agent.is_inside_tree() and not _agent.is_navigation_finished():
		goal = _agent.get_next_path_position()
	var to := goal - global_position
	to.y = 0.0
	if to.length() <= ARRIVE_M:
		has_target = false
		velocity.x = 0.0
		velocity.z = 0.0
		# a step behind somebody is not somewhere you have arrived
		if not is_following():
			arrived.emit(place_id)
		play_intent(Schedules.intent_for(activity, {}, def))
		return
	var dir := to.normalized()
	velocity.x = dir.x * current_speed()
	velocity.z = dir.z * current_speed()
	if _model != null:
		var yaw := atan2(dir.x, dir.z)
		# The model faces +Z (CONTRACTS §1), so it is turned to face along -Z travel.
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw + PI, minf(1.0, delta * 8.0))
	play_intent("Walk")


func _apply_gravity_or_snap(delta: float) -> void:
	if WorldProbe.has_world():
		var h := WorldProbe.get_height(global_position.x, global_position.z, global_position.y)
		global_position.y = maxf(h, _raised_floor())
		velocity.y = 0.0
		return
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta


# --- animation -------------------------------------------------------------------------------------

## Asks the model for an animation intent (the animation stream's AnimationDriver API).
func play_intent(intent: String) -> void:
	if intent.is_empty() or intent == _intent:
		return
	_intent = intent
	if _model != null and _model.get_child_count() > 0:
		var m: Node = _model.get_child(0)
		if m.has_method("play_intent"):
			m.call("play_intent", intent)


func current_intent() -> String:
	return _intent


func play_reaction(kind: String) -> void:
	play_intent(Reactions.intent_for(kind))
	if kind == "flee":
		flee_from(Peers.player())


func flee_from(from: Node) -> void:
	fleeing = true
	var away := global_position - (from as Node3D).global_position if from is Node3D else Vector3.FORWARD
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	set_move_target(global_position + away.normalized() * 15.0)


# --- perception (mirrors actors/enemy/perception.gd) -------------------------------------------------

func eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.65


## True when this NPC has an unobstructed view of a point inside its sight cone.
func can_see_point(point: Vector3) -> bool:
	var to := point - eye_position()
	var distance := to.length()
	if distance > sight_range:
		return false
	var facing := -global_transform.basis.z
	if _model != null:
		facing = Vector3(sin(_model.rotation.y + PI), 0.0, cos(_model.rotation.y + PI)).normalized()
	if DetectionMeter.facing_factor(facing.dot(to.normalized()), sight_fov) <= 0.0:
		return false
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(eye_position(), point)
	query.collision_mask = 1 | (1 << 10)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func can_see(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and can_see_point(node.global_position + Vector3.UP)


## The enemy stream's hearing interface: a noise of `loudness` at `pos`.
func noise_heard(pos: Vector3, loudness: float) -> void:
	if not alive:
		return
	_last_heard = pos
	detection = meter.hear(loudness, global_position.distance_to(pos), hearing_range, pos)
	EventBus.detection_changed.emit(self, detection)


func _sense(delta: float) -> void:
	var player := Peers.player()
	if player == null or not (player is Node3D):
		return
	var p := player as Node3D
	var to := p.global_position - eye_position()
	var distance := to.length()
	var facing := -global_transform.basis.z
	if _model != null:
		facing = Vector3(sin(_model.rotation.y + PI), 0.0, cos(_model.rotation.y + PI)).normalized()
	var los := distance <= sight_range and can_see(p)
	var visibility := 1.0
	if Stealth.instance != null:
		visibility = Stealth.instance.player_visibility()
	var before := detection
	detection = meter.update(delta, visibility, distance, sight_range, facing.dot(to.normalized()) if distance > 0.01 else 1.0, sight_fov, los, p.global_position)
	if absf(detection - before) > 0.05:
		EventBus.detection_changed.emit(self, detection)
	_react_accum += delta
	if _react_accum >= 0.5:
		_react_accum = 0.0
		if Reactions.instance != null and not npc_id.is_empty() and los:
			Reactions.instance.on_player_near(npc_id, distance)
		elif Reactions.instance != null and distance > Reactions.FAR_M:
			Reactions.instance.forget(npc_id)


# --- interaction ---------------------------------------------------------------------------------------

func prompt_text() -> String:
	if not alive:
		return "%s (dead)" % display_name()
	if def.has("merchant"):
		return "Trade with %s" % display_name()
	return "Talk to %s" % display_name()


## The dialogue stream picks this up through EventBus.dialogue_started.
func interact(actor: Node) -> void:
	if not alive:
		return
	stop()
	play_intent("Talk_1")
	var shop := merchant()
	if shop != null:
		shop.open_trade(actor)
		return
	EventBus.dialogue_started.emit(npc_id)


## A gesture from the player, answered by personality (DESIGN §5.9).
func receive_gesture(gesture: String) -> int:
	var delta := personality.disposition_delta(gesture) if personality != null else 0
	if NpcRegistry.instance != null and not npc_id.is_empty():
		NpcRegistry.instance.adjust_disposition(npc_id, delta)
	play_intent("Bow_Gesture" if delta > 0 else "Rude")
	EventBus.gesture_performed.emit(gesture, npc_id)
	return delta


## The body stays where it fell: the registry marks the NPC dead but leaves the actor for
## the loot and quest streams, and it is freed with its cell.
func die() -> void:
	if not alive:
		return
	alive = false
	hostile = false
	stop()
	remove_from_group("interactable")
	play_intent("Death_A")
	if NpcRegistry.instance != null and not npc_id.is_empty():
		NpcRegistry.instance.kill(npc_id)
	EventBus.entity_killed.emit(self, Peers.player(), npc_id)
