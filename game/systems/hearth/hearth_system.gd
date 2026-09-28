extends Node
## Hearth: checkpoints, death and the Echo. See README.md.

signal echo_spawned(position: Vector3, marks: int)
signal echo_cleared

const ECHO_SCENE := preload("res://systems/hearth/echo.tscn")
const RESPAWN_DELAY := 3.0

var last_hearthstone_id := ""
var respawn_position := Vector3.ZERO
var respawn_yaw := 0.0
var lit: Array[String] = []
var echo: Dictionary = {}          # {position: Vector3, marks: int, region: String}
var deaths := 0
var _echo_node: Node3D
var _respawning := false
## The body a pending respawn is for: a death's timer that fires after that body is gone (a load,
## a new game, a test's next world) brings nobody back, rather than the next body to the old stone.
var _dying_body_id := 0


func _ready() -> void:
	SaveSystem.register("hearth", self)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_spawned.connect(_on_player_spawned)


func has_echo() -> bool:
	return not echo.is_empty()


# --- resting -------------------------------------------------------------------------------

## Called by a Hearthstone when the player rests. `autosave` is false during respawn.
func rest_at(hearthstone_id: String, position: Vector3, yaw: float, autosave := true) -> void:
	last_hearthstone_id = hearthstone_id
	respawn_position = position
	respawn_yaw = yaw
	if not hearthstone_id in lit:
		lit.append(hearthstone_id)
	var player := _player()
	if player and player.has_method("full_restore"):
		player.full_restore()
	EventBus.hearthstone_rested.emit(hearthstone_id)
	if autosave:
		call_deferred("_autosave")


func is_lit(hearthstone_id: String) -> bool:
	return hearthstone_id in lit


func _autosave() -> void:
	SaveSystem.save_to_slot(SaveSystem.AUTO_SLOT)


# --- death ---------------------------------------------------------------------------------

func _on_player_died(position: Vector3) -> void:
	if _respawning:
		return
	_respawning = true
	var dying := _player()
	_dying_body_id = dying.get_instance_id() if dying != null else 0
	deaths += 1
	GameState.inc("deaths")
	var inv := _inventory()
	var marks := 0
	if inv:
		marks = int(inv.get("marks"))
		if marks > 0 and inv.has_method("remove_marks"):
			inv.remove_marks(marks)
	if has_echo():
		EventBus.notify.emit("Your last Echo went quiet. %d marks are unsaid." % int(echo.get("marks", 0)), "warning")
	_clear_echo_node()
	echo = {"position": position, "marks": marks, "region": GameState.current_region_id}
	_spawn_echo_node()
	echo_spawned.emit(position, marks)
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	timer.timeout.connect(_respawn)


func _respawn() -> void:
	# One death, one coming back. The delay timer fires three seconds after the fall and nothing
	# can cancel it, so anything that brought the player back sooner -- a load, a scripted
	# respawn, the journey's -- was undone by it seconds into whatever they were doing next.
	if not _respawning:
		return
	_respawning = false
	var player := _player()
	if player == null:
		return
	if _dying_body_id != 0 and player.get_instance_id() != _dying_body_id:
		# the body that died is gone: this is somebody else's life, and it is not put anywhere.
		# The full suite found it: a death in one test, and three seconds later the next test's
		# player was taken off the Warden mid-conversation and put down at a stale stone.
		Log.info("Hearth", "a respawn for a body that is gone comes back for nobody")
		_dying_body_id = 0
		return
	_dying_body_id = 0
	if last_hearthstone_id.is_empty():
		respawn_position = player.global_position + Vector3.UP * 0.2
	if player.has_method("respawn"):
		player.respawn(respawn_position, respawn_yaw)
	elif player is Node3D:
		player.global_position = respawn_position
	# The Echo is something you come back to, so it only answers once you have: until here the
	# body was lying on the very spot it stands on.
	if is_instance_valid(_echo_node):
		_echo_node.set("armed", true)
	EventBus.player_respawned.emit(last_hearthstone_id)
	# Coming back is a rest: the world resets around you, but no autosave mid-recovery.
	EventBus.hearthstone_rested.emit(last_hearthstone_id)


# --- echo ----------------------------------------------------------------------------------

func recover_echo() -> void:
	if not has_echo():
		return
	# Not before you have come back for it. While a death is unresolved the player is still on
	# the ground where they fell, which is where the Echo is standing.
	if _respawning:
		return
	var marks := int(echo.get("marks", 0))
	var inv := _inventory()
	if inv and inv.has_method("add_marks"):
		inv.add_marks(marks)
	echo = {}
	_clear_echo_node()
	EventBus.echo_recovered.emit(marks)
	EventBus.notify.emit("You are known again. %d marks recovered." % marks, "info")
	echo_cleared.emit()


func _spawn_echo_node() -> void:
	if not has_echo():
		return
	var parent := _dynamic_parent()
	if parent == null:
		return
	_echo_node = ECHO_SCENE.instantiate()
	parent.add_child(_echo_node)
	_echo_node.global_position = echo["position"]
	_echo_node.set("marks", int(echo["marks"]))
	# An Echo raised by a death appears around the body that just fell and must not notice it;
	# one raised by a load or a spawn is one the player left behind and is live at once.
	_echo_node.set("armed", not _respawning)


func _clear_echo_node() -> void:
	if is_instance_valid(_echo_node):
		_echo_node.queue_free()
	_echo_node = null


func _on_player_spawned(_body: Node) -> void:
	if has_echo() and not is_instance_valid(_echo_node):
		call_deferred("_spawn_echo_node")


func _dynamic_parent() -> Node:
	var n := get_tree().get_first_node_in_group("world_dynamic")
	if n:
		return n
	return get_tree().current_scene


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _inventory() -> Node:
	return get_tree().get_first_node_in_group("inventory")


# --- the road: between the stones, and to anywhere you have been -----------------------------

## Fast travel (playtest 09-27: there was none, and the warrior's tie-in already called the
## Wellspring a lesson in it). It is a choice of its own (triage 30: the list used to come up at
## every rest once two stones were lit): resting at a stone only rests, and then the stone offers
## "Travel from the Hearthstone" (Hearthstone.interact puts the road as a conversation with the
## stone). The chart (ui/map) goes further (triage 43): every place you have found (GameState's
## discovered places, the chart's own markers) that the world stands up is on its road, from
## wherever you stand out under the sky, as well as every lit stone. Either way it is `travel_to`,
## and the same refusals: indoors, a foe on you, or more in the bag than you can carry, and a
## place you have not been is not a way to go. The fade goes to black, the body is set down where
## anybody arriving at that place is (TravelPlaces.set_down: a dressing's own arrival, the same
## set-down the console's `tp` uses, or the edge of a town on its road in), facing into the place,
## the clock goes on by the walk's worth, the fade waits for the country to stand as a load does
## (UI.hold_for_the_country), the body is stepped clear if it stands in something the country
## brought, and a horse you were riding (or had beside you) comes too. Nothing is saved that was
## not already: which stones are lit and which places are found are in the save, and where they
## stand is the world's (pois.json). Stones inside a cave or a house are not on the road.

## How long the road takes, in hours a kilometre as the crow flies (a steady walk), and the most
## a journey can take.
const TRAVEL_HOURS_PER_KM := 0.25
const TRAVEL_MAX_HOURS := 10.0
## How near a foe that has the player for its target may be for the road to be refused.
const TRAVEL_DANGER_M := 40.0
const TRAVEL_LINE := "The road between the stones."
const TRAVEL_PLACE_LINE := "The road to %s."
const POIS_PATH := TravelPlaces.POIS_PATH
## A horse this near when the road is taken is beside you, and comes along.
const HORSE_WITH_YOU_M := 30.0

signal travelled(from_id: String, to_id: String)

var _travelling := false


## Where each place out in the country stands (its pois.json entry): the stones that are on the
## road, and every place the road can go.
static func stone_places() -> Dictionary:
	var out := {}
	for id in TravelPlaces.entries():
		out[id] = TravelPlaces.centre_of(str(id))
	return out


## Every lit stone out in the country but `from_id`, nearest first: [{id, name, km}]. Empty from a
## stone that is not on the road itself (a cave's).
func travel_targets(from_id: String) -> Array[Dictionary]:
	if not TravelPlaces.has(from_id):
		return []
	return travel_targets_from(TravelPlaces.centre_of(from_id), from_id)


## Every lit stone out in the country but `except`, nearest to `here` first: [{id, name, km}].
func travel_targets_from(here: Vector3, except := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in lit:
		if id == except or not TravelPlaces.has(id):
			continue
		out.append({"id": id, "name": _stone_name(id), "km": _km(here, TravelPlaces.centre_of(id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["km"]) < float(b["km"]))
	return out


## Every place the road can go from `here`: each lit stone and each place found that the world
## stands up. [{id, name, km, region, region_name, kind, stone}], nearest first; `stone` says a
## lit Hearthstone keeps your name there.
func destinations_from(here: Vector3) -> Array[Dictionary]:
	var ids: Array[String] = []
	for id in lit:
		if TravelPlaces.has(id) and not ids.has(id):
			ids.append(id)
	for id in GameState.discovered_places:
		if TravelPlaces.has(id) and not ids.has(id):
			ids.append(id)
	var out: Array[Dictionary] = []
	for id in ids:
		var def := ContentDB.get_or_empty(id)
		var region := str(def.get("region", ""))
		out.append({"id": id, "name": _stone_name(id), "km": _km(here, TravelPlaces.centre_of(id)),
				"region": region, "region_name": str(ContentDB.get_or_empty(region).get("name", "Elsewhere")),
				"kind": str(def.get("kind", "poi")), "stone": id in lit})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["km"]) < float(b["km"]))
	return out


## Whether the road goes to `id`: a lit stone, or a place found, that the world stands up.
func can_travel_to(id: String) -> bool:
	return TravelPlaces.has(id) and (id in lit or GameState.is_discovered(id))


static func _km(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length() / 1000.0


## What the stone offers when rested at, as a conversation with nobody in it: each lit stone on
## the road, and staying. Empty when there is nowhere to go.
func travel_conversation(from_id: String, stone_name: String) -> Dictionary:
	var targets := travel_targets(from_id)
	if targets.is_empty():
		return {}
	var choices: Array = []
	for t in targets:
		choices.append({"text": "Go on to %s (%.1f km)" % [str(t["name"]), float(t["km"])], "next": "end",
				"effects": [{"travel": str(t["id"])}]})
	choices.append({"text": "Stay by the fire.", "next": "end"})
	return {"id": "", "speaker_name": stone_name, "start": "road",
			"nodes": {"road": {"speaker": "npc", "no_talk": true, "choices": choices,
					"text": "Your name is kept here, and at every stone that is lit. The flame leans toward them."}}}


## Why the road is shut now, or "" when it is open.
func why_no_travel() -> String:
	if _travelling:
		return "already on the road"
	var player := _player()
	if player == null:
		return "nobody to travel"
	if Interiors != null and not str(Interiors.current_id).is_empty():
		return "You must be out under the sky to take the road."
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or bool(e.get("dead")):
			continue
		if e.get("target") == player and e.global_position.distance_to(player.global_position) <= TRAVEL_DANGER_M:
			return "Not with a foe at your back."
	# the bag's own rule: more in it than you can carry and you cannot run (Inventory.is_overloaded)
	var bag := player.get_node_or_null(NodePath("Inventory"))
	if bag != null and bag.has_method("is_overloaded") and bool(bag.call("is_overloaded")):
		return "You carry too much to take the road. Put something down first."
	return ""


## Takes the player to the lit stone or found place `to_id`. Returns false (and says why) when it
## cannot; the journey itself runs on after the return, under the fade.
func travel_to(to_id: String) -> bool:
	var why := why_no_travel()
	if why.is_empty() and not can_travel_to(to_id):
		why = "You have not been there." if TravelPlaces.has(to_id) else "The road does not go there."
	if not why.is_empty():
		EventBus.notify.emit(why, "warning")
		return false
	_travel(to_id)
	return true


func _travel(to_id: String) -> void:
	_travelling = true
	var player := _player()
	var from_id := last_hearthstone_id
	var from := player.global_position
	var horse := _horse_with(player)
	var was_riding := _riding(player)
	UI.fade_to_black(0.45, TRAVEL_LINE if to_id in lit else TRAVEL_PLACE_LINE % _stone_name(to_id))
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(player):
		_travelling = false
		UI.fade_from_black(0.3)
		return
	# worked out under the fade: a place with no dressing standing raises one for the asking
	var down := TravelPlaces.set_down(to_id)
	var at: Vector3 = down["at"]
	var face: Vector3 = down["face"]
	var to_face := Vector3(face.x - at.x, 0.0, face.z - at.z)
	var yaw := atan2(-to_face.x, -to_face.z) if to_face.length() > 0.1 else player.rotation.y
	if player.has_method("teleport"):
		player.call("teleport", at + Vector3(0.0, 0.1, 0.0), yaw, "fast travel")
	else:
		player.global_position = at + Vector3(0.0, 0.1, 0.0)
		player.rotation.y = yaw
	var km := _km(from, at)
	WorldClock.advance_hours(minf(km * TRAVEL_HOURS_PER_KM, TRAVEL_MAX_HOURS))
	GameState.discover(to_id)
	await UI.hold_for_the_country(player)
	if is_instance_valid(player):
		_step_clear(player, yaw)
		if horse != null and is_instance_valid(horse):
			_bring_horse(horse, player, was_riding)
	travelled.emit(from_id, to_id)
	UI.fade_from_black(0.8)
	EventBus.notify.emit("You come to %s." % _stone_name(to_id), "info")
	_travelling = false


func is_travelling() -> bool:
	return _travelling


## The body's own shape as a query, standing at `at`, for what the country brought (a tree, a rock,
## a wall a streamed cell stood up) that no data said was there.
func _blocked(player: Node3D, at: Vector3) -> bool:
	if not player.is_inside_tree():
		return false
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = PoiDressing.ARRIVAL_RADIUS_M
	capsule.height = PoiDressing.ARRIVAL_HEIGHT_M - 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis(), at + Vector3(0.0, 0.3 + capsule.height * 0.5, 0.0))
	q.collision_mask = Actor.LAYER_WORLD
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return not space.intersect_shape(q, 1).is_empty()


## Once the country stands: a body put inside something steps to the nearest open ground.
func _step_clear(player: Node3D, yaw: float) -> void:
	var here := player.global_position
	if not _blocked(player, here):
		return
	var terrain := World.terrain()
	var r := 1.5
	while r <= 14.0:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var p := here + Vector3(sin(a), 0.0, cos(a)) * r
			if terrain != null:
				p.y = terrain.get_height(p.x, p.z)
				if TravelPlaces.is_wet(p, terrain):
					continue
			if not _blocked(player, p):
				if player.has_method("teleport"):
					player.call("teleport", p + Vector3(0.0, 0.1, 0.0), yaw, "fast travel")
				else:
					player.global_position = p + Vector3(0.0, 0.1, 0.0)
				return
		r += 1.5


# --- the horse comes too ------------------------------------------------------------------------

func _rider_of(player: Node3D) -> Rider:
	return player.get("rider") as Rider if player != null and "rider" in player else null


func _riding(player: Node3D) -> bool:
	var rider := _rider_of(player)
	return rider != null and rider.riding()


## The horse on the road with you: the one ridden, or one of yours standing beside you.
func _horse_with(player: Node3D) -> Mount:
	var rider := _rider_of(player)
	if rider != null and rider.riding() and rider.horse != null:
		return rider.horse
	var stable := Stable.find()
	if stable == null:
		return null
	var best: Mount = null
	var best_d := HORSE_WITH_YOU_M
	for m_v in stable.horses.values():
		var m := m_v as Mount
		if m == null or not is_instance_valid(m) or m.sleeping:
			continue
		var d := m.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## Stands the horse beside the body where it has room, and puts you back in the saddle if you rode.
func _bring_horse(horse: Mount, player: Node3D, was_riding: bool) -> void:
	var stable := Stable.find()
	var right := Vector3(cos(player.rotation.y), 0.0, -sin(player.rotation.y))
	var back := Vector3(sin(player.rotation.y), 0.0, cos(player.rotation.y))
	var yaw := player.rotation.y
	var spot := player.global_position + right * 2.2
	for off in [right * 2.2, -right * 2.2, back * 3.0, right * 3.5 + back * 2.0, -right * 3.5 + back * 2.0, back * 6.0]:
		var p: Vector3 = player.global_position + off
		p.y = World.get_height(p.x, p.z)
		if stable == null or stable._clear(p, yaw):
			spot = p
			break
	spot.y = World.get_height(spot.x, spot.z)
	horse.wake()
	horse.place(spot, yaw)
	if was_riding:
		var rider := _rider_of(player)
		if rider != null:
			rider.seat_now(horse)


func _stone_name(id: String) -> String:
	var n := str(ContentDB.get_or_empty(id).get("name", ""))
	return n if not n.is_empty() else id.get_slice("/", 1).capitalize()


# --- save ----------------------------------------------------------------------------------

## Both positions are saved with the place they stood beside (`near`), so a load into a redrawn
## map puts the stone's landing and the Echo back beside the same places (PlaceRef).
func to_save() -> Dictionary:
	var e := {}
	if has_echo():
		var p: Vector3 = echo["position"]
		e = {"position": [p.x, p.y, p.z], "marks": int(echo["marks"]), "region": echo.get("region", ""),
			"near": PlaceRef.pin(p)}
	return {
		"last_hearthstone_id": last_hearthstone_id,
		"respawn_position": [respawn_position.x, respawn_position.y, respawn_position.z],
		"respawn_near": PlaceRef.pin(respawn_position) if last_hearthstone_id != "" else {},
		"respawn_yaw": respawn_yaw, "lit": lit.duplicate(), "echo": e, "deaths": deaths,
	}


func from_save(d: Dictionary) -> void:
	last_hearthstone_id = str(d.get("last_hearthstone_id", ""))
	var rp: Array = d.get("respawn_position", [0, 0, 0])
	respawn_position = PlaceRef.follow(Vector3(float(rp[0]), float(rp[1]), float(rp[2])), d.get("respawn_near", null))
	respawn_yaw = float(d.get("respawn_yaw", 0.0))
	lit.assign(d.get("lit", []))
	deaths = int(d.get("deaths", 0))
	_clear_echo_node()
	var e: Dictionary = d.get("echo", {})
	if e.is_empty():
		echo = {}
	else:
		var ep: Array = e.get("position", [0, 0, 0])
		var at := PlaceRef.follow(Vector3(float(ep[0]), float(ep[1]), float(ep[2])), e.get("near", null))
		echo = {"position": at, "marks": int(e.get("marks", 0)), "region": str(e.get("region", ""))}
		if is_inside_tree():
			call_deferred("_spawn_echo_node")
