class_name Npc
extends CharacterBody3D
## A villager. Follows its schedule between activity spots, reacts to the player, senses
## crimes as a witness, and hands off to the dialogue stream when spoken to.
##
## Movement follows a path round the town's houses and yards when the people's navigation mesh
## stands there (NpcNav), and otherwise a straight line with detours round what it meets; it steps
## round other people on the way (`_steer`), and snaps to the ground through World.get_height.
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
## How quickly what this person sees of you becomes their being sure of it: 1 for anybody, more for
## somebody whose trade is watching (the def's `perception.keen`: Moreva's night-watch).
@export var keen := 1.0

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
## The house this person was stood up in (NpcStreamer, when the player goes through its door), or
## null out of doors. Indoors the ground is the house's floor, not the country's far below the pocket,
## and their spot is a room of it.
var indoors: Node3D = null

var _model: Node3D = null
var _intent := ""
var _entry_clip := ""
var _react_accum := 0.0
## Whether this person is on your side of a lesson just now (the def's `with_you_when`), asked again
## every second.
var _with_you := false
var _with_you_left := 0.0
var _last_heard := Vector3.ZERO


func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")
	if not npc_id.is_empty():
		load_def()
	_model = get_node_or_null("Model")
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
	# their quest business over their head: "!" a quest to give, "?" one to go on with or hand in
	if not npc_id.is_empty() and get_node_or_null("QuestMark") == null:
		add_child(QuestMark.new())
	_start_life()
	if not EventBus.dialogue_ended.is_connected(_on_dialogue_ended):
		EventBus.dialogue_ended.connect(_on_dialogue_ended)
	_settle_on_marker.call_deferred()


## How long after spawning a person is still set straight down on their spot when its marker
## stands up, rather than walking to it.
const SETTLE_SECONDS := 2.5

## A person spawned in the same moment as their place is stood before its spot markers are: the
## registry then puts them on a ring round the place's middle, up to forty metres out, and they
## walked in from there. Sergeant Dole began a warrior's new game 28 m from the yard, out of view
## (flow, 2026-09-27). For the first moments of their life, if the marker turns up and they are
## well off it, they are set on it; a traveller or an escort keeps the road it was given.
func _settle_on_marker() -> void:
	var until := Time.get_ticks_msec() + int(SETTLE_SECONDS * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < until:
		if spot.is_empty() or activity == "travel" or NpcRegistry.instance == null:
			return
		if NpcRegistry.instance.escort_position(npc_id) != Vector3.INF or NpcRegistry.instance.road_position(npc_id) != Vector3.INF:
			return
		var marker := NpcRegistry.instance.spot_marker(npc_id)
		if marker != null:
			var at := _slot_of(marker)
			if _flat_distance(at) > 2.0:
				global_position = at
				target_position = at
				make_room()
			return
		await get_tree().process_frame


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
		keen = float(p.get("keen", keen))
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
## Set by whoever stands this person up while the world is drawn (NpcRegistry): the body is dressed
## within the frame's budget over a few frames rather than in the frame it appears (TRIAGE item 36).
var pace_slice: WorldPace.Slice = null


func _dress_paced(m: Node) -> void:
	_model.visible = false
	await m.apply_appearance(appearance_of(), pace_slice)
	if is_instance_valid(_model):
		_model.visible = true
	pace_slice = null


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
				if pace_slice != null:
					# stood up while the world is drawn: dressed a few parts a frame, and seen once dressed
					_dress_paced(m)
				else:
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
	# a def's `feminine` goes into the roll, so a named woman is dressed, grown and shaved as one
	var fem: Variant = block.get("feminine", null)
	var look := CharacterAppearance.random(from_seed, culture(),
			float(fem) if typeof(fem) in [TYPE_INT, TYPE_FLOAT] else -1.0)
	for key in ["age", "height", "bulk", "feminine", "shoulder_width", "hip_width",
			"limb_length", "neck_length", "head_size", "hearth", "hollow"]:
		if not block.has(key):
			continue
		var v: Variant = block[key]
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			look.set(key, float(v))
	# the face and the marks a writer pinned (a scar, a people's paint, a jaw), over the dice
	look.pin(block)
	if is_child():
		var years: Variant = block.get("age", null)
		look.height = child_height(float(years) if typeof(years) in [TYPE_INT, TYPE_FLOAT] else 9.0)
		look.build = minf(look.build, 0.45)
	# tattoos and jewellery (triage 48) for the person the def made, of the years it gave and the means
	# its tags speak of, on their own dice; and what the writer pinned of them over that
	look.roll_adornment(CharacterAppearance.adorn_rng(from_seed), CharacterAppearance.wealth_of(def.get("tags", [])))
	look.pin(block)
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
	make_room()
	_home = Vector3.INF
	_retry_goal = Vector3.INF
	_apply_activity()


## The state to write back when this NPC is despawned or the game is saved.
func collect_state() -> Dictionary:
	return {"place": place_id, "activity": activity, "spot": spot, "alive": alive, "hostile": hostile}


## The registry calls this when the schedule moves on while the NPC is loaded.
## `place`: set them straight down on the new spot rather than walk them to it (the story moved
## them while nobody was looking: NpcRegistry._on_story_moved).
func apply_schedule_state(entry: Dictionary, place := false) -> void:
	var was := activity
	place_id = str(entry.get("place", place_id))
	activity = str(entry.get("activity", activity))
	spot = str(entry.get("spot", spot))
	_entry_clip = str(entry.get("clip", ""))
	_home = Vector3.INF
	_retry_goal = Vector3.INF
	_retries = 0
	if place and activity != "travel":
		var at := _spot_position()
		if at.is_finite():
			global_position = at
			target_position = at
			make_room()
	_go_to_spot()
	if activity != was:
		_apply_activity()


func _apply_activity() -> void:
	play_intent(_activity_intent())
	# the next beat of the new hour comes at a moment of this person's own, not the village's
	if _life != null:
		_beat_left = _life.rng.randf_range(0.5, 2.5)
		_pending_beat = {}
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
	if is_instance_valid(indoors):
		# the room their hour is spent in; or, when their hour sends them out, the door
		if NpcRegistry.instance == null or NpcRegistry.instance.is_indoors(npc_id):
			return NpcStreamer.room_spot(indoors, activity, NpcStreamer.room_index(npc_id))
		var door := indoors.find_child("Entrance", true, false) as Node3D
		return door.global_position if door != null else indoors.global_position
	if not spot.is_empty() and is_inside_tree():
		# the registry's own marker first: it knows whose place a marker is in, and where in a
		# shared one this person stands
		if NpcRegistry.instance != null:
			var own := NpcRegistry.instance.spot_marker(npc_id)
			if own != null and str(own.name) == spot:
				return _slot_of(own)
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


## True when this person stands on the people's navigation mesh (NpcNav: a town near the player,
## the house they are in); otherwise the walk is a straight line with detours. Looked at again
## whenever a walk is set, since a town's mesh is baked a moment after the player comes near.
func _navigation_available() -> bool:
	return is_inside_tree() and NpcNav.on_mesh(global_position)


## The way to `to` round what is in the way, when there is a mesh here: its corners, walked one after
## another, and then straight on to `to` from where the mesh ends (a spot on a deck, a stall's
## counter). No corners, a straight line.
func _route(to: Vector3) -> void:
	_path = PackedVector3Array()
	_path_i = 0
	if not _navigation_available():
		return
	var way := NpcNav.path(global_position, to)
	if way.size() < 2:
		return
	_path = way
	_path_i = 1
	# a spot on the mesh that the way cannot reach (a yard with no gate): the nearest it comes is
	# where the walk ends, turned toward the spot, rather than leaning on the fence
	var end := way[way.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() > UNREACHABLE_M and NpcNav.on_mesh(to):
		_meant = to
		target_position = end


## `validate` moves a destination that is inside a wall, a stall or a tree to the nearest place
## beside it a body can stand (free_point_near): a stall's marker is the stall, and the grocer
## walked into her own counter for the rest of the morning.
func set_move_target(pos: Vector3, validate := true) -> void:
	_wandering = false
	if validate and (not has_target or pos.distance_to(target_position) > 0.5):
		pos = free_point_near(pos)
	if not has_target:
		_reslots = 0
		_stuck_t = 0.0
		_stuck_from = global_position
		_stuck_goal = pos
		_stuck_goal_d = _flat_distance(pos)
	var moved := not has_target or pos.distance_to(target_position) > 0.25
	target_position = pos
	has_target = true
	if moved:
		_waited = 0.0
		_meant = Vector3.INF
	if moved or _path.is_empty():
		_route(pos)


func stop() -> void:
	has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	_path = PackedVector3Array()
	_wait_left = 0.0
	_detour = Vector3.INF
	_detour_side = 0.0
	_stuck_tries = 0
	_wandering = false
	_pending_beat = {}


# --- getting round things -------------------------------------------------------------------------
#
# In a town near the player, and in the house the player is in, a walk follows the way NpcNav's mesh
# gives round the houses, the yards' fences and the stalls (`_route`). Elsewhere, or where the mesh
# stops short of the spot, it is a straight line, and ScatterSolids.unstick lets a body through trees
# and nothing else. Either way a walk is watched. Less than STUCK_PROGRESS_M in STUCK_WINDOW_S and
# the body looks for the way again, or steps aside along what is in the way (DETOUR_M, and that again
# further each try), and tries again; a person in the way is waited for a moment (`_wait_left`)
# rather than walked round like a wall. After STUCK_TRIES it gives the leg up. Out of the player's
# sight (UNSEEN_M) it is put where it was going, as the roster would put it; in sight it gets on with
# its hour where it is, turned from any wall, and tries the walk again a little later
# (`_retry_goal`): the first pass left it standing where it stopped until the next hour.

const STUCK_WINDOW_S := 1.6
const STUCK_PROGRESS_M := 0.6
const STUCK_TRIES := 5
const DETOUR_M := 3.5
## Windows in a row spent sliding along something without getting nearer that count as a try.
const SLIDING_WINDOWS := 3
const UNSEEN_M := 35.0
## The body a destination is checked with: a little narrower than the collider and lifted clear of
## the ground, so a slope or a kerb is not a wall.
const CLEAR_RADIUS := 0.3
const CLEAR_HEIGHT := 1.4
const CLEAR_LIFT := 1.05
## A corner of the way counts as reached this near it (m).
const CORNER_M := 0.6
## A spot the mesh holds but the way cannot reach (a yard with no gate, a roof) is given up for the
## nearest the way comes to it, when that is further off than this (m).
const UNREACHABLE_M := 2.5
## A person in the way is waited for this long (s) before being walked round, at most WAIT_MAX_S a leg.
const WAIT_S := Vector2(0.8, 1.8)
const WAIT_MAX_S := 6.0
## A leg given up in sight is tried again after this long (s), at most RETRIES times.
const RETRY_S := Vector2(15.0, 30.0)
const RETRIES := 3
## Nobody is set down, or stands at the end of a walk, nearer than this to somebody else (m, the two
## capsules and a hand between).
const ROOM_M := 0.75

static var _clear_shape: CapsuleShape3D = null

var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO
var _stuck_goal := Vector3.ZERO
var _stuck_goal_d := 0.0
var _sliding := 0
var _clear := 0
var _stuck_tries := 0
var _detour := Vector3.INF
var _detour_left := 0.0
var _detoured := false
var _detour_side := 0.0
## The way (NpcNav.path) and the corner walked to next; empty for a straight line.
var _path := PackedVector3Array()
var _path_i := 0
## Where the walk was meant for when the way stops short of it: turned to on arriving.
var _meant := Vector3.INF
## Waiting for somebody in the way, and how long this leg has waited in all.
var _wait_left := 0.0
var _waited := 0.0
var _bumped: Node3D = null
## A leg given up in sight, tried again once _retry_left runs out.
var _retry_goal := Vector3.INF
var _retry_left := 0.0
var _retries := 0
## Legs given up, for the probe and the tests.
var give_ups := 0
## A slot round a shared spot is arrived at this near (m; the slots are GATHER_GAP_M apart).
const SLOT_ARRIVE_M := 0.45
## Round their own shared spot, a walk held up in its crowd takes the nearest free slot, within this
## of its outer ring (m), at most RESLOTS times a walk.
const RESLOT_NEAR_M := 3.0
const RESLOTS := 3
var _reslots := 0
## The slot round a shared spot the walk is for, in the world (INF: none).
var _slot_target := Vector3.INF
## Until which physics tick a walk counts as queuing (`is_queuing`).
var _queued_until := 0


## Whether a body standing at `pos` would be inside something solid (walls, props, trees), or with
## `people`, within ROOM_M of somebody (another person, the player).
func blocked_at(pos: Vector3, people := false) -> bool:
	if not is_inside_tree():
		return false
	if people and someone_at(pos) != null:
		return true
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


## Whoever stands within ROOM_M of `pos` (flat, and on the same floor), other than this person.
func someone_at(pos: Vector3) -> Node3D:
	for e: Array in _crowd_now():
		if e[0] == self or not is_instance_valid(e[0]) or (e[0] as Node).is_queued_for_deletion():
			continue
		var who: Node3D = e[0]
		var at := who.global_position
		if absf(at.y - pos.y) < 1.5 and Vector2(at.x - pos.x, at.z - pos.z).length() < ROOM_M:
			return who
	return null


## `pos`, or when a body cannot stand there the nearest place round it that one can, on the
## smallest ring that has one and on the side nearest this person. `pos` itself when nowhere
## within five metres is clear. With `people`, clear of everybody else too.
func free_point_near(pos: Vector3, people := false) -> Vector3:
	if not blocked_at(pos, people):
		return pos
	var terrain := _on_terrain()
	var ground := WorldProbe.get_height(pos.x, pos.z, pos.y) if terrain else pos.y
	for r: float in [0.9, 1.7, 2.6, 3.6, 5.0]:
		var best := Vector3.INF
		for i in 12:
			var a := TAU * float(i) / 12.0
			var p := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if terrain:
				# follow the ground from the spot's own height, which may be a deck above it
				p.y = pos.y + (WorldProbe.get_height(p.x, p.z, ground) - ground)
			if blocked_at(p, people):
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


## Set down somewhere (stood up, put on a spot, carried by the story): out of any wall, and not in
## somebody else's body. Two people sent to the same gather spot were stood up one inside the other.
func make_room() -> void:
	if not is_inside_tree():
		return
	if blocked_at(global_position, true):
		global_position = free_point_near(global_position, true)
		if not has_target:
			target_position = global_position


## Called each physics frame of a walk, after the move.
func _watch_progress(delta: float) -> void:
	if _detour != Vector3.INF:
		_detoured = true
	if _wait_left > 0.0:
		# waiting for somebody is not getting stuck
		_stuck_t = 0.0
		_stuck_from = global_position
		return
	_stuck_t += delta
	if _stuck_t < STUCK_WINDOW_S:
		return
	var bumped := _bumped
	_bumped = null
	var went := _flat_distance(_stuck_from)
	var closed := _stuck_goal_d - _flat_distance(target_position)
	# a traveller's target moves on ahead of them; anybody else's stays put and is walked towards
	var moving_goal := _stuck_goal.distance_to(target_position) > 1.0
	# on the way the mesh gave, going is getting there, round a house as much as towards it
	var pathing := _path_i > 0 and _path_i < _path.size()
	_stuck_t = 0.0
	_stuck_from = global_position
	_stuck_goal = target_position
	_stuck_goal_d = _flat_distance(target_position)
	if _afloat or (went >= STUCK_PROGRESS_M and (moving_goal or pathing or closed >= went * 0.5)):
		# walked freely towards the target, twice running and not on a detour: whatever was in the
		# way is behind (once is not enough: straight off the end of a short detour, the body slid
		# back along the wall to where it began, and that counted)
		if not _detoured:
			_clear += 1
			_sliding = 0
			if _clear >= 2:
				_stuck_tries = 0
		_detoured = false
		return
	_clear = 0
	if went >= STUCK_PROGRESS_M:
		# going, but sliding along something rather than getting nearer: not stuck yet, unless it
		# goes on (a detour's own windows are sideways by design)
		if not _detoured:
			_sliding += 1
		_detoured = false
		if _sliding < SLIDING_WINDOWS:
			return
	_sliding = 0
	_detoured = false
	# held up in the crowd round their own shared spot (the well): the nearest free slot from here
	if _settle_in_crowd():
		return
	# somebody in the way: stand a moment and let them by, as a person does
	if is_instance_valid(bumped) and _waited < WAIT_MAX_S:
		_wait_for(bumped)
		return
	_stuck_tries += 1
	if _stuck_tries >= STUCK_TRIES:
		_give_up_leg()
		return
	# the first try looks for the way again from here; after that, a step aside and the way again
	if _stuck_tries == 1 and _navigation_available():
		_route(target_position)
		if not _path.is_empty():
			return
	if not _pick_detour():
		_give_up_leg()


## Stands still a moment for `who`, turned to them, and then goes on.
func _wait_for(who: Node3D) -> void:
	var hold := _life.rng.randf_range(WAIT_S.x, WAIT_S.y) if _life != null else WAIT_S.x
	_wait_left = hold
	_waited += hold
	_bumped = null
	_queued_until = Engine.get_physics_frames() + int((hold + 1.0) * Engine.physics_ticks_per_second)
	velocity.x = 0.0
	velocity.z = 0.0
	var d := who.global_position - global_position
	d.y = 0.0
	if _model != null and d.length_squared() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_of(d), 0.5)


## Their slot round the shared spot `marker` (NpcRegistry.gather_offset), where a body can stand, in
## the world; the marker itself for a spot that is one person's.
func _slot_of(marker: Node3D, near := Vector3.INF) -> Vector3:
	if not bool(marker.get_meta("gather", false)):
		return marker.global_position
	var people := near != Vector3.INF
	var at := marker.global_position + NpcRegistry.gather_offset(npc_id, marker, near,
			func(p: Vector3) -> bool: return not blocked_at(p, people))
	_slot_target = at
	return at


## A walk to their own shared spot held up in its crowd (somebody on their slot, or in the way within
## a few metres of it): the nearest free slot from where they are, and arrived when that is a step
## away. The well's crowd queued as stuck for 10-24 s, waiting on each other (triage 32).
func _settle_in_crowd() -> bool:
	if _wandering or is_following() or _reslots >= RESLOTS or NpcRegistry.instance == null or spot.is_empty() \
			or is_instance_valid(indoors) or activity == "travel":
		return false
	var marker := NpcRegistry.instance.spot_marker(npc_id)
	if marker == null or str(marker.name) != spot or not bool(marker.get_meta("gather", false)):
		return false
	var reach := float(marker.get_meta("gather_r", NpcRegistry.GATHER_R_M)) \
			+ NpcRegistry.GATHER_RING_STEP_M * float(NpcRegistry.GATHER_RINGS) + RESLOT_NEAR_M
	if _flat_distance(NpcRegistry.gather_centre(marker)) > reach:
		return false
	_reslots += 1
	_queued_until = Engine.get_physics_frames() + 2 * Engine.physics_ticks_per_second
	var at := _slot_of(marker, global_position)
	if _flat_distance(at) <= SLOT_ARRIVE_M * 2.0:
		_arrive()
	else:
		set_move_target(at, false)
	return true


## Whether this walk is standing its turn in a crowd (waiting on somebody, or just taken a free slot
## round a shared spot) rather than stuck: the people probe counts it apart.
func is_queuing() -> bool:
	return has_target and Engine.get_physics_frames() < _queued_until


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
	# each try further along: back on the line after a short one, the body slid back to where it began
	var reach := DETOUR_M * float(maxi(_stuck_tries, 1))
	for side: float in [_detour_side, -_detour_side]:
		for off: float in [0.3, 0.0, 0.8]:
			var dir := (along * side + normal * off).normalized()
			if not test_move(from, dir * reach):
				_detour_side = side
				_detour = global_position + dir * reach
				_detour_left = reach / WALK_SPEED + 0.6
				return true
	return false


## The walk cannot be finished. Unseen, they are put where they were going. In sight they stop here
## and live their hour where they stand (IdleLife), turned from any wall, and try again later.
func _give_up_leg() -> void:
	give_ups += 1
	var player := Peers.player()
	var watched := player is Node3D and _flat_distance((player as Node3D).global_position) < UNSEEN_M
	var goal := _meant if _meant != Vector3.INF else target_position
	if not watched and not is_following() and not blocked_at(target_position):
		global_position = target_position
		make_room()
	elif not is_following() and not _wandering and activity != "patrol" and _retries < RETRIES:
		# (a patrol goes on to its next point anyway)
		_retry_goal = goal
		_retries += 1
		_retry_left = _life.rng.randf_range(RETRY_S.x, RETRY_S.y) if _life != null else RETRY_S.x
	_arrive()


## The walk given up in sight comes round again: unseen now, they are put there; seen, they walk.
func _try_again() -> void:
	var goal := _retry_goal
	_retry_goal = Vector3.INF
	var player := Peers.player()
	var watched := player is Node3D and _flat_distance((player as Node3D).global_position) < UNSEEN_M
	if not watched and not blocked_at(goal):
		global_position = goal
		make_room()
		_arrive()
		return
	set_move_target(goal)


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
	if _wandering:
		return STROLL_SPEED
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
		if _can_live():
			_live(delta)
		_turn_to_look(delta)
	_apply_gravity_or_snap(delta)
	_in_the_water()
	var wanted := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	# walking and getting nowhere, pressed against a wall or caught between two trunks: through
	ScatterSolids.unstick(self, wanted, delta)
	if has_target:
		_note_bumps()
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
	if _wait_left > 0.0:
		# standing aside for somebody a moment
		_wait_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		play_intent("Idle")
		return
	var goal := target_position
	var last_leg := true
	if _path_i > 0 and _path_i < _path.size():
		goal = _path[_path_i]
		while _flat_distance(goal) < CORNER_M and _path_i < _path.size():
			_path_i += 1
			goal = _path[_path_i] if _path_i < _path.size() else target_position
		last_leg = _path_i >= _path.size() - 1
	if _detour != Vector3.INF:
		_detour_left -= delta
		if _detour_left <= 0.0 or _flat_distance(_detour) < 0.5:
			_detour = Vector3.INF
			# off the end of a step aside: the way from here
			_route(target_position)
		else:
			goal = _detour
	var arrive_m := WANDER_ARRIVE_M if _wandering else ARRIVE_M
	# a slot round a shared spot is walked right up to: at ARRIVE_M short, it is the next one's
	var to_slot := _slot_target != Vector3.INF and _slot_target.distance_to(target_position) < 0.3
	if to_slot and not _wandering:
		arrive_m = SLOT_ARRIVE_M
	if _detour == Vector3.INF and last_leg and _flat_distance(target_position) <= arrive_m:
		_arrive()
		return
	# somebody already stands where this walk ends (the well, a shared spot): round a shared spot,
	# the nearest free slot from here; anywhere else, near enough is there
	if _detour == Vector3.INF and last_leg and not _wandering and not is_following() \
			and _flat_distance(target_position) <= maxf(arrive_m, ARRIVE_M) * 2.0 and someone_at(target_position) != null:
		if _settle_in_crowd():
			return
		_arrive()
		return
	var to := goal - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		to = target_position - global_position
		to.y = 0.0
	var dir := to.normalized()
	var v := _steer(dir, current_speed())
	velocity.x = v.x
	velocity.z = v.z
	if _model != null and v.length_squared() > 0.01:
		# The model faces +Z (CONTRACTS §1); turned by the travel's own yaw, +Z goes along it.
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_of(v), minf(1.0, delta * 8.0))
	play_intent("Walk")


# --- other people in the way -------------------------------------------------------------------------
#
# Bodies pass round each other. Every person and the player are one list a tick (`_crowd_now`); a
# walker looks along where it is going for anybody it would come within their two bodies and a gap
# of in the next AVOID_AHEAD_S, and bends its way off to the side that clears them (both to their
# own right when they meet head on, so they pass as people pass), more the nearer that is. Somebody
# standing is not steered and is not pushed: people collide with people and the player now (their
# scene's mask), so a walker slides round them rather than through, and one that is held up by them
# waits a moment (`_wait_for`) before stepping round.

## How far ahead in time, and in metres, a walker looks for people in its way.
const AVOID_AHEAD_S := 1.8
const AVOID_RANGE_M := 5.0
## The capsule's radius, and the gap left between two people passing.
const BODY_R := 0.32
const PASS_GAP_M := 0.35
## How hard the way bends for somebody in it, at the closest.
const AVOID_BEND := 1.6

static var _crowd_tick := -1
static var _crowd: Array = []


## Somebody stood up or taken away: the tick's crowd is read again. It was kept for the whole
## physics tick, so a person stood up again on their spot in the tick they were taken away (the
## roster moving them on) was made room from their own ghost, 0.9 m off the marker, and two stood
## up at one gather spot in one tick did not see each other (triage 38).
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_crowd_tick = -1


## Every person and the player this physics tick: [body, flat position, flat velocity, radius].
func _crowd_now() -> Array:
	var tick := Engine.get_physics_frames()
	if tick == _crowd_tick and not _crowd.is_empty():
		return _crowd
	_crowd_tick = tick
	_crowd = []
	if not is_inside_tree():
		return _crowd
	for n in get_tree().get_nodes_in_group("npc"):
		# (a body taken away this frame stays in the tree until the frame ends)
		if n is CharacterBody3D and (n as Node3D).is_inside_tree() and not n.is_queued_for_deletion():
			var b := n as CharacterBody3D
			_crowd.append([b, Vector2(b.global_position.x, b.global_position.z), Vector2(b.velocity.x, b.velocity.z), BODY_R])
	var player := Peers.player()
	if player is Node3D and (player as Node3D).is_inside_tree():
		var p := player as Node3D
		var pv: Vector3 = p.get("velocity") if "velocity" in p else Vector3.ZERO
		_crowd.append([p, Vector2(p.global_position.x, p.global_position.z), Vector2(pv.x, pv.z), 0.4])
	return _crowd


## The velocity to walk at along `dir`, bent round whoever is in the way.
func _steer(dir: Vector3, speed: float) -> Vector3:
	var me := Vector2(global_position.x, global_position.z)
	var want := Vector2(dir.x, dir.z) * speed
	var right := Vector2(-dir.z, dir.x)
	var bend := Vector2.ZERO
	var slow := 1.0
	for e: Array in _crowd_now():
		if e[0] == self or not is_instance_valid(e[0]):
			continue
		var p: Vector2 = (e[1] as Vector2) - me
		var d2 := p.length_squared()
		if d2 > AVOID_RANGE_M * AVOID_RANGE_M or absf((e[0] as Node3D).global_position.y - global_position.y) > 1.5:
			continue
		var reach: float = BODY_R + float(e[3]) + PASS_GAP_M
		# my way relative to theirs, and where they are from me when we are closest
		var rel: Vector2 = want - (e[2] as Vector2)
		var rr := rel.length_squared()
		var ahead := p.dot(rel)
		if ahead <= 0.0 or rr < 0.0001:
			continue
		var t := minf(ahead / rr, AVOID_AHEAD_S)
		var miss := p - rel * t
		var m := miss.length()
		if m >= reach:
			continue
		# to the side away from where they will be; square on, to the right
		var lateral := -miss.dot(right)
		var side := right * (signf(lateral) if absf(lateral) > 0.05 else 1.0)
		var urgency := (reach - m) / reach * (1.0 - t / AVOID_AHEAD_S * 0.7)
		bend += side * urgency
		# close and square in front: slow while going round
		if d2 < (reach + 0.4) * (reach + 0.4) and p.normalized().dot(want.normalized()) > 0.7:
			slow = minf(slow, 0.55)
	if bend == Vector2.ZERO:
		return Vector3(want.x, 0.0, want.y)
	var way := (Vector2(dir.x, dir.z) + bend * AVOID_BEND).normalized() * speed * slow
	return Vector3(way.x, 0.0, way.y)


## Who the last move ran into, when it was a person or the player: the walk waits for them.
func _note_bumps() -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i).get_collider()
		if hit is Npc or (hit is Node3D and (hit as Node).is_in_group("player")):
			_bumped = hit as Node3D
			return


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
	_path = PackedVector3Array()
	_path_i = 0
	_wait_left = 0.0
	var meant := _meant
	_meant = Vector3.INF
	fleeing = false
	# a step behind somebody is not somewhere you have arrived
	if is_following():
		return
	if _wandering:
		# a few steps about their own spot: not somewhere new, and the day's rhythm goes on
		_wandering = false
		if not _pending_beat.is_empty():
			var beat := _pending_beat
			_pending_beat = {}
			_do_beat(beat)
		elif _life != null:
			_beat_left = minf(_beat_left, _life.rng.randf_range(0.4, 1.5))
		return
	_home = global_position
	_home_yaw = _model.rotation.y if _model != null else 0.0
	arrived.emit(place_id)
	if activity == "travel" and NpcRegistry.instance != null:
		var marker := NpcRegistry.instance.spot_marker(npc_id)
		if marker != null and _flat_distance(marker.global_position) > ARRIVE_M * 2.0:
			set_move_target(_slot_of(marker))
			return
	_face_on_arrival(meant)
	play_intent(_activity_intent())


## Which way somebody turns at the end of a walk: the way their spot's marker faces (the square from
## behind a stall, the fire they tend), round at the middle of a spot they share (the well), toward a
## spot the way could not reach; and with no marker to say, never into a wall. They walked up to a
## wall and stood facing it for the hour.
func _face_on_arrival(meant: Vector3) -> void:
	if _model == null:
		return
	var yaw := _model.rotation.y
	var marker := NpcRegistry.instance.spot_marker(npc_id) if NpcRegistry.instance != null and not spot.is_empty() else null
	if marker != null and _flat_distance(marker.global_position) < 3.5:
		var to := NpcRegistry.gather_centre(marker) - global_position
		to.y = 0.0
		if bool(marker.get_meta("gather", false)) and to.length() > 0.3:
			yaw = _yaw_of(to)
		else:
			yaw = _yaw_of(-marker.global_transform.basis.z)
	else:
		if meant != Vector3.INF and _flat_distance(meant) > 0.5:
			yaw = _yaw_of(meant - global_position)
		yaw = open_yaw(yaw)
	_home_yaw = yaw
	_look_yaw = yaw


## A look across a wall or a house front this close is a face to the wall (m).
const WALL_NEAR_M := 0.8

## `yaw`, or when a wall stands close in front of it the nearest way round from it that is open.
func open_yaw(yaw: float) -> float:
	if not is_inside_tree() or not _wall_ahead(yaw, WALL_NEAR_M):
		return yaw
	for k in range(1, 7):
		for sgn: float in [1.0, -1.0]:
			var y := yaw + sgn * float(k) * PI / 6.0
			if not _wall_ahead(y, WALL_NEAR_M * 2.0):
				return y
	return yaw


func _wall_ahead(yaw: float, reach: float) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * 1.25
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(sin(yaw), 0.0, cos(yaw)) * reach,
			collision_mask & (1 | ScatterSolids.LAYER))
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


## The clip for the activity now, with the entry's own clip when it named one (arriving used to
## drop it and play the def's, so a brewer who walked to her vats hammered at them).
func _activity_intent() -> String:
	return Schedules.intent_for(activity, {"clip": _entry_clip, "spot": spot}, def)


## Water a villager walks into: past the knee it wades slower, and in water deeper than its chest
## it floats with its head at the surface and its model in the swim (Swimmer, as the player's).
var _water: Swimmer = null
var _afloat := false


func _in_the_water() -> void:
	if not _on_terrain():
		return
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


## Whether this person stands on the country's ground (World.get_height) rather than a house's floor.
func _on_terrain() -> bool:
	return WorldProbe.has_world() and not is_instance_valid(indoors)


func _apply_gravity_or_snap(delta: float) -> void:
	if _on_terrain():
		var h := WorldProbe.get_height(global_position.x, global_position.z, global_position.y)
		global_position.y = maxf(h, _raised_floor())
		velocity.y = 0.0
		return
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta


# --- animation -------------------------------------------------------------------------------------

## Asks the model for an animation intent (the animation stream's AnimationDriver API). The same
## intent twice is asked once, unless `again`: a one-shot that has finished is played again only so.
func play_intent(intent: String, again := false) -> void:
	if intent.is_empty() or (intent == _intent and not again):
		return
	_intent = intent
	if _model != null and _model.get_child_count() > 0:
		var m: Node = _model.get_child(0)
		if m.has_method("play_intent"):
			m.call("play_intent", intent)


func current_intent() -> String:
	return _intent


## A reaction is played and then the day takes over again. It did not: the reaction's clip was the
## last thing asked for, so a smith waved at stood idle for the rest of his hour, and one who
## cowered (a looping clip) cowered until the clock moved him on.
func play_reaction(kind: String) -> void:
	var clip := Reactions.intent_for(kind)
	play_intent(clip, true)
	if kind == "flee":
		flee_from(Peers.player())
		return
	var player := Peers.player()
	if player is Node3D and kind != "hide" and not has_target:
		_look_at((player as Node3D).global_position)
	if _life != null:
		_beat_left = _clip_seconds(clip, REACTION_HOLD_S) + _life.rng.randf_range(0.3, 1.2)
		_pending_beat = {}


# --- a life at the spot (IdleLife) ------------------------------------------------------------------
#
# Somebody whose hour keeps them in one place lives through it in beats (IdleLife): the work in
# bouts with a breather, talk in turns, a look round, a look at whoever is near, a few steps and
# back. Each person keeps their own time, and turns to look at the pace of a head and shoulders.

## How fast somebody standing turns to look at something, rad/s at most.
const LOOK_TURN_RATE := 2.2
## Whoever is nearer than this is company: somebody to look at or talk to.
const COMPANY_M := 6.0
## A reaction whose clip goes round (a cower) is held this long before the day takes over again.
const REACTION_HOLD_S := 4.5
## A few steps about their spot are at a stroll, and end close.
const STROLL_SPEED := 1.1
const WANDER_ARRIVE_M := 0.35
## Nobody wanders to within this of somebody else.
const ELBOW_ROOM_M := 0.9

var _life: IdleLife = null
var _beat_left := 0.0
## Where this person's activity is done and which way they faced there; INF until they stand there.
var _home := Vector3.INF
var _home_yaw := 0.0
## Somebody keeping a watch (NightWatch sets it while a stage's `unseen` names them): the day's idle
## beats keep their look where their post faces and their feet on it. Moreva's night-watch looked
## "around" up to 109 degrees either way and wandered off her boards, so where she was looking when
## the rogue came down depended on the dice (test_rogue_plays found her turned to 218, not 150).
var keep_look := false
## The yaw they are turning to look along while standing, or NAN.
var _look_yaw := NAN
var _wandering := false
## A beat waiting for them to walk back to their spot (a bout of work is done there).
var _pending_beat: Dictionary = {}


func _start_life() -> void:
	_life = IdleLife.new(hash(npc_id) ^ int(get_instance_id()))
	_beat_left = _life.rng.randf_range(0.3, 3.5)
	# every body's idle at its own point: a street stood up together breathed together
	var m := _body_model()
	var tree: Variant = m.get("anim_tree") if m != null else null
	if tree is AnimationTree and (tree as AnimationTree).is_inside_tree():
		(tree as AnimationTree).advance(_life.rng.randf_range(0.0, 4.0))


func _can_live() -> bool:
	if not alive or hostile or fleeing or has_target or _afloat or is_following() or _life == null:
		return false
	if get("confronting") == true:
		return false
	return not NpcRegistry.is_talking(npc_id)


func _live(delta: float) -> void:
	if _retry_goal != Vector3.INF:
		_retry_left -= delta
		if _retry_left <= 0.0:
			_try_again()
			return
	_beat_left -= delta
	if _beat_left <= 0.0:
		_next_beat()


func _next_beat() -> void:
	if _home == Vector3.INF:
		_home = global_position
		_home_yaw = _model.rotation.y if _model != null else 0.0
	var base := _activity_intent()
	if base == "Walk":
		base = "Idle"  # on the road and there early, or between the legs of a patrol
	var beat := _life.next_beat(activity, base)
	# the work itself is done at their spot: walk back to it first from a few steps off
	if str(beat["look"]) == "home" and _flat_distance(_home) > 0.6 and not blocked_at(_home):
		set_move_target(_home, false)
		_wandering = true
		_pending_beat = beat
		return
	_do_beat(beat)


func _do_beat(beat: Dictionary) -> void:
	var clip := str(beat["clip"])
	_beat_left = float(beat["hold"])
	var m := _body_model()
	var playing := str(m.call("current_intent")) if m != null and m.has_method("current_intent") else ""
	var lying := str(m.call("holding_pose")) if m != null and m.has_method("holding_pose") else ""
	# a loop already going round is left to go on (asked again, it would start over with a jump)
	if IdleLife.is_one_shot(clip) or (clip != playing and clip != lying):
		play_intent(clip, true)
	if m != null and not IdleLife.is_one_shot(clip) and clip != "Idle":
		m.set("speed_scale", float(beat.get("tempo", 1.0)))
	if keep_look:
		_look_yaw = _home_yaw
		return
	match str(beat["look"]):
		"around":
			_look_yaw = _home_yaw + _life.rng.randf_range(-1.9, 1.9)
		"person":
			var who := _company()
			if who != null:
				_look_at(who.global_position)
			else:
				_look_yaw = _home_yaw + _life.rng.randf_range(-1.2, 1.2)
		"home":
			_look_yaw = _home_yaw
	var wander := float(beat.get("wander", 0.0))
	if wander > 0.0:
		var a := _life.rng.randf() * TAU
		var to := _home + Vector3(cos(a) * wander, 0.0, sin(a) * wander)
		if _on_terrain():
			to.y = WorldProbe.get_height(to.x, to.z, _home.y)
		if _flat_distance(to) > WANDER_ARRIVE_M * 2.0 and not blocked_at(to) and not _crowded(to):
			set_move_target(to, false)
			_wandering = true


## The nearest person within COMPANY_M, the player first when they are near.
func _company() -> Node3D:
	var player := Peers.player()
	if player is Node3D and _flat_distance((player as Node3D).global_position) < COMPANY_M:
		return player as Node3D
	var best: Node3D = null
	var best_d := COMPANY_M
	for n in get_tree().get_nodes_in_group("npc"):
		if n == self or not (n is Node3D):
			continue
		var d := _flat_distance((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func _crowded(at: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("npc"):
		if n != self and n is Node3D and Vector2(at.x - (n as Node3D).global_position.x,
				at.z - (n as Node3D).global_position.z).length() < ELBOW_ROOM_M:
			return true
	return false


func _look_at(point: Vector3) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_look_yaw = _yaw_of(dir)


## Standing, turned toward _look_yaw a little slower as they come round to it.
func _turn_to_look(delta: float) -> void:
	if is_nan(_look_yaw) or _model == null:
		return
	var d := wrapf(_look_yaw - _model.rotation.y, -PI, PI)
	if absf(d) < 0.02:
		_look_yaw = NAN
		return
	var rate := clampf(absf(d) * 3.0, 0.6, LOOK_TURN_RATE)
	_model.rotation.y += clampf(d, -rate * delta, rate * delta)


func _clip_seconds(clip: String, fallback: float) -> float:
	if IdleLife.ONE_SHOT_S.has(clip):
		return float(IdleLife.ONE_SHOT_S[clip])
	var m := _body_model()
	if m != null and m.has_method("clip_length") and not bool(_loops(m, clip)):
		var s := float(m.call("clip_length", clip))
		if s > 0.0:
			return s
	return fallback


static func _loops(m: Node, clip: String) -> bool:
	var data: Variant = m.get("_clip_data")
	return data is Dictionary and bool(((data as Dictionary).get(clip, {}) as Dictionary).get("loop", false))


## The conversation is over: back to the day in a moment (a shopkeeper's trade has no end the actor
## hears of, so interact's own hold covers that).
func _on_dialogue_ended(id: String) -> void:
	if id == npc_id and _life != null:
		_beat_left = _life.rng.randf_range(0.4, 1.2)
		_pending_beat = {}


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
	if distance > seeing_range():
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
	return node != null and is_instance_valid(node) and can_see_point(Stealth.sight_point(node))


## How far this person sees in the weather now: fog and mist take most of it.
func seeing_range() -> float:
	return sight_range * Stealth.weather_sight()


## True while the def's `with_you_when` holds: the teacher at your shoulder is not somebody you are
## hiding from, and the sneak read on the HUD (the most watchful near) must not read him. Before
## this, Sauve Mor, a few paces off and turned to you, read "Found" from the first second of the
## Rogue's start, and the eye taught nothing about the watch.
func is_with_you() -> bool:
	return _with_you


func _refresh_with_you(delta: float) -> void:
	_with_you_left -= delta
	if _with_you_left > 0.0:
		return
	_with_you_left = 1.0
	var when: Variant = def.get("with_you_when", [])
	var ctx := Schedules.live_context()
	_with_you = ctx != null and when is Array and not (when as Array).is_empty() and Conditions.all_of(when, ctx)


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
	_refresh_with_you(delta)
	if _with_you:
		if detection > 0.0:
			detection = 0.0
			meter.reset()
		return
	var to := p.global_position - eye_position()
	var distance := to.length()
	var facing := facing_flat()
	var seeing := seeing_range()
	# a sleeper sees nothing (hearing still wakes them: noise_heard)
	var los := distance <= seeing and not Pickpocketing.is_asleep(self) and can_see(p)
	var visibility := 1.0
	if Stealth.instance != null:
		visibility = Stealth.instance.player_visibility()
	var before := detection
	detection = meter.update(delta, visibility * keen, distance, seeing, facing.dot(to.normalized()) if distance > 0.01 else 1.0, sight_fov, los, p.global_position)
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
	if Pickpocketing.can_offer(self, Peers.player()):
		return Pickpocketing.prompt_for(self)
	if def.has("merchant") and not _has_words():
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
	# crouched at somebody who has not noticed you, the hand goes to their pocket (Pickpocketing)
	if Pickpocketing.can_offer(self, actor):
		Pickpocketing.request(self, actor)
		return
	stop()
	# turned to whoever spoke to them: the conversation's camera looks at their face
	if actor is Node3D:
		face_direction((actor as Node3D).global_position - global_position)
	_look_yaw = NAN
	play_intent("Talk_1")
	# attending to them for a while: a trade has no end the actor hears of
	_beat_left = 12.0
	if Social.dialogue != null and bool(Social.dialogue.call("is_running")):
		return
	# a shopkeeper with nothing written to say opens the shop; one with words talks, and their hub
	# offers the shop (DialogueRunner's trade choice), so what they have to say is not lost behind it
	var shop := merchant()
	if shop != null and not _has_words():
		shop.open_trade(actor)
		return
	if actor is Node3D and Social.dialogue.has_method("set_next_speaker"):
		Social.dialogue.call("set_next_speaker", self)
	Social.talk(npc_id, "", place_id)


## Whether this person has a conversation of their own written (their def's `dialogue`).
func _has_words() -> bool:
	return not str(def.get("dialogue", "")).is_empty()


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
