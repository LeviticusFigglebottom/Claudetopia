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
	dress_hands()
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
	return shown_name(def, Schedules.live_context(), Ids.name_of(npc_id))


## What somebody is called to the player now: the first of their def's `known_as` ({when:
## conditions, name}) that holds, else their name. The Warden at the Stair Head has not told a
## styled character her name before the wake, and her prompt and nameplate say so.
static func shown_name(npc_def: Dictionary, ctx: SocialContext, fallback := "") -> String:
	var known: Variant = npc_def.get("known_as", [])
	if ctx != null and known is Array:
		for v in known as Array:
			if v is Dictionary and Conditions.all_of((v as Dictionary).get("when", []), ctx):
				return str((v as Dictionary).get("name", ""))
	return str(npc_def.get("name", fallback))


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
	# no model scene at all: a capsule, so the person is at least somewhere
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
	if is_child():
		var years: Variant = block.get("age", null)
		look.height = child_height(float(years) if typeof(years) in [TYPE_INT, TYPE_FLOAT] else 9.0)
		look.build = minf(look.build, 0.45)
	return look


## A child is written three ways in the packs: tagged `child`, built `child_small`, or just given
## an age under fourteen. Every one of them was rolled as a grown person of the culture, so the
## miller's nine-year-old stood as tall as the miller.
func is_child() -> bool:
	if def.get("tags", []).has("child"):
		return true
	var raw: Variant = def.get("appearance", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	if str((raw as Dictionary).get("build", "")) == "child_small":
		return true
	var years: Variant = (raw as Dictionary).get("age", null)
	return typeof(years) in [TYPE_INT, TYPE_FLOAT] and float(years) > 0.0 and float(years) < 14.0


## A child's height for their years: 1.22 m at seven, 1.44 m at eleven. The body is still the
## adult one scaled down to it -- children have no skeleton of their own yet (PROGRESS.md).
static func child_height(years: float) -> float:
	return clampf(1.22 + (years - 7.0) * 0.055, 1.0, 1.50)


# --- registry hand-off -------------------------------------------------------------------------

## Applies the abstract state the registry kept while this NPC was off screen.
func apply_state(s: Dictionary) -> void:
	place_id = str(s.get("place", place_id))
	activity = str(s.get("activity", activity))
	spot = str(s.get("spot", spot))
	alive = bool(s.get("alive", true))
	hostile = bool(s.get("hostile", false))
	step_out_of_solids()
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
	play_intent(_activity_intent())
	dress_hands()
	activity_changed.emit(activity)


## What this person carries, on the body (HeldItems): the def's `carries`, {main_hand, off_hand},
## each an item id or "class:<weapon class>". A weapon rides in its sheath while they go about
## their day and is drawn while they are hostile. One with no sheath (a pole, a spear) is carried
## only on a patrol or in a fight, and nothing is taken to bed.
func dress_hands() -> void:
	var body := _body_model()
	if body == null:
		return
	var carries: Dictionary = def.get("carries", {}) if def.get("carries") is Dictionary else {}
	var main := _carried(str(carries.get("main_hand", "")))
	var off := _carried(str(carries.get("off_hand", "")))
	if not hostile and activity == "sleep":
		main = {}
		off = {}
	elif not hostile and not main.is_empty() and HeldItems.sheath_for(main).is_empty() and activity != "patrol":
		main = {}
	if main.is_empty() and off.is_empty() and HeldItems.held_by(body).is_empty() and HeldItems.sheathed_by(body).is_empty():
		return
	HeldItems.dress(body, main, off, hostile)


static func _carried(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if id.begins_with("class:"):
		return HeldItems.for_class(id.trim_prefix("class:"))
	return ContentDB.get_or_empty(id)


## The humanoid model standing in for this person, or null while it is a placeholder.
func _body_model() -> Node:
	if _model != null and _model.get_child_count() > 0:
		var m: Node = _model.get_child(0)
		if m.has_method("attach_to_socket"):
			return m
	return null


# --- movement ----------------------------------------------------------------------------------

## Walks to the current activity spot. Spot markers are looked up by name in the current
## scene (a place scene may name them, e.g. "market_stall"); otherwise the place position
## with the NPC's own deterministic offset is used.
func _go_to_spot() -> void:
	var pos := _spot_position()
	set_move_target(pos)


func _spot_position() -> Vector3:
	if not spot.is_empty() and is_inside_tree():
		# the registry's own marker first: it knows whose place a marker is in, and where in a
		# shared one this person stands
		if NpcRegistry.instance != null:
			var own := NpcRegistry.instance.spot_marker(npc_id)
			if own != null and str(own.name) == spot:
				return own.global_position + NpcRegistry.gather_offset(npc_id, own)
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


## `validate` moves a destination that is inside a wall, a stall or a tree to the nearest place
## beside it a body can stand (free_point_near): a stall's marker is the stall, and the grocer
## walked into her own counter for the rest of the morning.
func set_move_target(pos: Vector3, validate := true) -> void:
	if validate and (not has_target or pos.distance_to(target_position) > 0.5):
		pos = free_point_near(pos)
	if not has_target:
		_stuck_t = 0.0
		_stuck_from = global_position
	target_position = pos
	has_target = true
	_use_agent = _navigation_available()
	if _use_agent:
		_agent.target_position = pos


func stop() -> void:
	has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	_detour = Vector3.INF
	_detour_side = 0.0
	_stuck_tries = 0


# --- getting round things -------------------------------------------------------------------------
#
# Nothing steers a villager round a wall. The world has no navigation mesh, so a walk is a straight
# line, and ScatterSolids.unstick lets a body through trees and nothing else: somebody whose line
# ran into a house, a stall or a fence leant on it with their legs going for the rest of the hour.
# A walk is watched now. Less than STUCK_PROGRESS_M in STUCK_WINDOW_S and the body steps aside, to
# along what is in the way (a detour of DETOUR_M), and tries again; after STUCK_TRIES of those it
# gives the leg up. Out of the player's sight (UNSEEN_M) it is put where it was going, as the roster
# would put it; in sight it stays where it is and gets on with its hour there.

const STUCK_WINDOW_S := 1.6
const STUCK_PROGRESS_M := 0.6
const STUCK_TRIES := 5
const DETOUR_M := 3.5
const DETOUR_MOST_S := 2.2
const UNSEEN_M := 35.0
## The body a destination is checked with: a little narrower than the collider and lifted clear of
## the ground, so a slope or a kerb is not a wall.
const CLEAR_RADIUS := 0.3
const CLEAR_HEIGHT := 1.4
const CLEAR_LIFT := 1.05

static var _clear_shape: CapsuleShape3D = null

var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO
var _stuck_tries := 0
var _detour := Vector3.INF
var _detour_left := 0.0
var _detoured := false
var _detour_side := 0.0


## Whether a body standing at `pos` would be inside something solid (walls, props, trees).
func blocked_at(pos: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	if _clear_shape == null:
		_clear_shape = CapsuleShape3D.new()
		_clear_shape.radius = CLEAR_RADIUS
		_clear_shape.height = CLEAR_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _clear_shape
	q.transform = Transform3D(Basis(), pos + Vector3.UP * CLEAR_LIFT)
	q.collision_mask = collision_mask & (1 | ScatterSolids.LAYER)
	q.exclude = [get_rid()]
	return not space.intersect_shape(q, 1).is_empty()


## `pos`, or when a body cannot stand there the nearest place round it that one can, on the
## smallest ring that has one and on the side nearest this person. `pos` itself when nowhere
## within five metres is clear.
func free_point_near(pos: Vector3) -> Vector3:
	if not blocked_at(pos):
		return pos
	var ground := WorldProbe.get_height(pos.x, pos.z, pos.y) if WorldProbe.has_world() else pos.y
	for r: float in [0.9, 1.7, 2.6, 3.6, 5.0]:
		var best := Vector3.INF
		for i in 12:
			var a := TAU * float(i) / 12.0
			var p := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if WorldProbe.has_world():
				# follow the ground from the spot's own height, which may be a deck above it
				p.y = pos.y + (WorldProbe.get_height(p.x, p.z, ground) - ground)
			if blocked_at(p):
				continue
			if best == Vector3.INF or _flat_distance(p) < _flat_distance(best):
				best = p
		if best != Vector3.INF:
			return best
	return pos


## Stood up inside a house or a stall (the roster's ring round a place does not know where the
## houses are): out to the nearest clear ground.
func step_out_of_solids() -> void:
	if blocked_at(global_position):
		global_position = free_point_near(global_position)


## Called each physics frame of a walk, after the move.
func _watch_progress(delta: float) -> void:
	if _detour != Vector3.INF:
		_detoured = true
	_stuck_t += delta
	if _stuck_t < STUCK_WINDOW_S:
		return
	var went := _flat_distance(_stuck_from)
	_stuck_t = 0.0
	_stuck_from = global_position
	if went >= STUCK_PROGRESS_M or _afloat:
		# a straight stretch walked freely: whatever was in the way is behind
		if not _detoured:
			_stuck_tries = 0
		_detoured = false
		return
	_detoured = false
	_stuck_tries += 1
	if _stuck_tries >= STUCK_TRIES or not _pick_detour():
		_give_up_leg()


## A step along whatever is in the way, off the line to the target: along the face of the wall the
## body is pressed to (its collision normal), to the side the target is nearer, and on round the same
## side each try after, so a walk works its way along a house to its corner rather than turning back
## and forth in front of it. The other side when that one is shut; false when both are.
func _pick_detour() -> bool:
	var to := target_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return false
	var ahead := to.normalized()
	var normal := -ahead
	var hit := get_last_slide_collision()
	if hit != null:
		var n := hit.get_normal()
		n.y = 0.0
		if n.length_squared() > 0.01:
			normal = n.normalized()
	var along := normal.cross(Vector3.UP).normalized()
	if _detour_side == 0.0:
		var d := along.dot(ahead)
		_detour_side = signf(d) if absf(d) > 0.05 else (1.0 if abs(npc_id.hash()) % 2 == 0 else -1.0)
	var from := global_transform.translated(Vector3.UP * 0.35)
	for side: float in [_detour_side, -_detour_side]:
		for off: float in [0.3, 0.0, 0.8]:
			var dir := (along * side + normal * off).normalized()
			if not test_move(from, dir * DETOUR_M):
				_detour_side = side
				_detour = global_position + dir * DETOUR_M
				_detour_left = DETOUR_MOST_S
				return true
	return false


func _give_up_leg() -> void:
	var player := Peers.player()
	var watched := player is Node3D and _flat_distance((player as Node3D).global_position) < UNSEEN_M
	if not watched and not is_following() and not blocked_at(target_position):
		global_position = target_position
	_arrive()


## Turns to look along `dir` at once (flat), the way walking would leave them facing: for a
## person put somewhere rather than walked there (`NpcSpot`).
func face_direction(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or _model == null:
		return
	_model.rotation.y = _yaw_of(dir)


## The model's yaw that turns its face (+Z, CONTRACTS §1) along `dir`. It was this plus half a turn,
## and the facing read back through the same half turn, so the sums agreed with each other and the
## body did not: the rig's toes and face pointed the other way. Every person walked backwards,
## stood at a worked spot with their back to what it faced, and turned away from whoever spoke to
## them (the flow's picture of the first conversation, 09-24).
static func _yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


## Which way the person faces, flat: where the model's face is turned.
func facing_flat() -> Vector3:
	if _model == null:
		return -global_transform.basis.z
	return Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y)).normalized()


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
	_in_the_water()
	var wanted := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	# walking and getting nowhere, pressed against a wall or caught between two trunks: through
	ScatterSolids.unstick(self, wanted, delta)
	if has_target:
		_watch_progress(delta)
	_drive_gait()


## Tells the model how fast the body is walking (m/s, straight ahead: the model is turned to face
## the way it goes), so its legs keep pace with the ground. Nothing did: a walking villager's
## blend stayed at (0, 0) and the whole village glided about in its idle pose.
func _drive_gait() -> void:
	if _model == null or _model.get_child_count() == 0:
		return
	var m: Node = _model.get_child(0)
	if m.has_method("set_locomotion"):
		m.call("set_locomotion", Vector2(0.0, Vector2(velocity.x, velocity.z).length()), false)


func _step_towards(delta: float) -> void:
	var goal := target_position
	if _use_agent and _agent.is_inside_tree() and not _agent.is_navigation_finished():
		goal = _agent.get_next_path_position()
	if _detour != Vector3.INF:
		_detour_left -= delta
		if _detour_left <= 0.0 or _flat_distance(_detour) < 0.5:
			_detour = Vector3.INF
		else:
			goal = _detour
	var to := goal - global_position
	to.y = 0.0
	if _detour == Vector3.INF and to.length() <= ARRIVE_M:
		_arrive()
		return
	var dir := to.normalized()
	velocity.x = dir.x * current_speed()
	velocity.z = dir.z * current_speed()
	if _model != null:
		# The model faces +Z (CONTRACTS §1); turned by the travel's own yaw, +Z goes along it.
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_of(dir), minf(1.0, delta * 8.0))
	play_intent("Walk")


## The end of a walk: standing, and back to what the hour is for. A traveller the roads have let go
## near the end of their journey (the registry steers them only until the last stretch) walks on to
## the spot they are going to rather than standing on the road where the steering stopped. Whoever
## was running from something has got away: they walk again from here on (they ran everywhere after,
## for the rest of the day).
func _arrive() -> void:
	has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	_detour = Vector3.INF
	_detour_side = 0.0
	_stuck_tries = 0
	fleeing = false
	# a step behind somebody is not somewhere you have arrived
	if is_following():
		return
	arrived.emit(place_id)
	if activity == "travel" and NpcRegistry.instance != null:
		var marker := NpcRegistry.instance.spot_marker(npc_id)
		if marker != null and _flat_distance(marker.global_position) > ARRIVE_M * 2.0:
			set_move_target(marker.global_position + NpcRegistry.gather_offset(npc_id, marker))
			return
	play_intent(_activity_intent())


## The clip for the activity now, with the entry's own clip when it named one (arriving used to
## drop it and play the def's, so a brewer who walked to her vats hammered at them).
func _activity_intent() -> String:
	return Schedules.intent_for(activity, {"clip": _entry_clip}, def)


## Water a villager walks into: past the knee it wades slower, and in water deeper than its chest
## it floats with its head at the surface and its model in the swim (Swimmer, as the player's).
var _water: Swimmer = null
var _afloat := false


func _in_the_water() -> void:
	if _water == null:
		_water = Swimmer.new()
	var provider: Object = World.terrain()
	var bed := float(provider.call("get_height", global_position.x, global_position.z)) \
			if provider != null and provider.has_method("get_height") else NAN
	var feet := global_position
	if _afloat and not is_nan(bed):
		feet.y = bed          # read the depth from the bed, as a body standing there would
	_water.read(feet, bed)
	var was := _afloat
	_afloat = (not _water.can_stand()) if _afloat else _water.deep_enough()
	if _afloat:
		global_position.y = maxf(_water.float_feet_y(), global_position.y if is_nan(bed) else bed)
		velocity.y = 0.0
		var pace := Vector2(velocity.x, velocity.z).length()
		if pace > Swimmer.SWIM_SPEED:
			velocity.x *= Swimmer.SWIM_SPEED / pace
			velocity.z *= Swimmer.SWIM_SPEED / pace
	else:
		var m := _water.wade_mult()
		velocity.x *= m
		velocity.z *= m
	if _afloat != was and _model != null and _model.get_child_count() > 0:
		var model: Node = _model.get_child(0)
		if model.has_method("set_swimming"):
			model.call("set_swimming", _afloat)


func is_afloat() -> bool:
	return _afloat


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
	var facing := facing_flat()
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
	var facing := facing_flat()
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


## Talks: starts the conversation (Social.talk), which the dialogue UI shows and which says
## EventBus.dialogue_started itself once it has begun. This used to emit that signal and stop, as
## though somebody would hear it and start talking. Nobody did, so the interact key on anybody in
## Wickmere got a nod and nothing else, and the game's first objective, to speak to the Warden at
## her fire, could not be done. Every test and the journey had reached past it to Social.talk.
func interact(actor: Node) -> void:
	if not alive:
		return
	stop()
	# turned to whoever spoke to them: the conversation's camera looks at their face
	if actor is Node3D:
		face_direction((actor as Node3D).global_position - global_position)
	play_intent("Talk_1")
	var shop := merchant()
	if shop != null:
		shop.open_trade(actor)
		return
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		return
	Social.talk(npc_id, "", place_id)


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
