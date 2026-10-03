class_name WorldDoors
extends Node3D
## Puts the interiors' doors in the world.
##
## Each `core:table/door_plan_*` (CONTRACTS §7) names a place and the ways in that stand at it:
## a house at a bearing and a distance from the place's centre, a deep place's mouth on the
## same ring. The world's POI data says where that centre actually is, so a door plan plus a
## POI is a door in the ground — which is how twenty-four hand-built interiors get attached to
## eight kilometres of terrain without anybody placing them by hand.
##
## A locked house gets a DoorLock whose owner is the resident, so breaking in is a crime the
## law already knows how to price.

signal doors_placed(count: int)

const PLAN_ROLE := "door_plan"
const DOOR_SCENE := "res://systems/interiors/door.tscn"
## How far above the ground a door frame sits, so it is not buried by a metre of chalk.
const SILL := 0.05
## Standing up over frames, the towns within this of where the world is first seen from are raised
## before it says it is ready; the rest after, nearest the eye first (`_process`).
const READY_M := 900.0
## After it is ready, a town is raised once the eye comes within this of it, nearest first: towns
## further off are not drawn from where anybody stands, and raising all thirty-nine behind the menu,
## the loading fade and the first minutes of play was minutes of main-thread time on a slow machine
## (TRIAGE item 36). A walker covers this in a couple of minutes, and a town is raised in a second.
const WANT_M := 2400.0
## While somebody is watching (play, a film's pictures, the title's menu), only the towns this near:
## the rest wait for a curtain (a film's black, the loading fade), where a frame of building is not
## seen.
const WANT_WATCHED_M := 1100.0
const LOOK_EVERY_S := 0.25
var _look_in := 0.0

@export var place_doors: bool = true
## Buildings are raised around house doors; a tool that only wants the doors turns this off.
@export var raise_buildings: bool = true
## The rest of the town around them: the roofs nobody lives under. Off for a tool that only
## wants the doors, and for a test that does not want fifty meshes it did not ask for.
@export var raise_fabric: bool = true

var placed: Array[Door] = []
var raised: Array[Building] = []
var fabric: Array[Settlement] = []
## Each settlement's streets, made before its doors so the houses with an inside front a street
## like everything else, and handed on to the fabric with those houses already on it.
var streets: Dictionary = {}          # place id -> StreetPlan
var _road_lines: Array = []
## Whether the world already had everything placed while it stood up (`place_all_over_frames`), so
## hearing it is ready places nothing twice.
var _placed := false
## Standing up over frames: the towns not yet raised (their place defs), what raising them needs
## (`_fabric_begin`), and the one being raised now.
var _queue: Array = []
var _fill: Dictionary = {}
var _raising: Settlement = null
## Whether the towns before the world is ready are up, and the rest are raised as the eye comes near.
var _in_background := false


func _ready() -> void:
	add_to_group("world_doors")
	if not place_doors:
		return
	# A child is ready before its parent: World.instance is still null here and the ground does
	# not exist yet, so doors placed now would hang at zero metres.
	var world := _world()
	if world != null and not world.is_world_ready:
		await world.world_ready
	if not _placed:
		place_all()


## The world this belongs to, found by looking up rather than through World.instance, which the
## parent has not set yet while its children are readying.
func _world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	return World.instance


## Reads every door plan and stands its doors up. Returns how many were placed; a plan for a
## place the world does not have is skipped with a warning rather than dropped in silence.
func place_all() -> int:
	_place_doors()
	if raise_fabric:
		_fill_settlements()
	doors_placed.emit(placed.size())
	_placed = true
	return placed.size()


## `place_all` over frames, for a world standing up in steps (World.stand_up_in_steps): the fabric
## of thirty-nine settlements raised at once was 8.9 s without a frame drawn, behind the title's
## chart and under the loading caption (PROGRESS "The title never freezes"), and a settlement a frame
## was a frame of up to 1.9 s each (TRIAGE item 36). Each town is now raised a piece at a time within
## the frame's budget (WorldPace, Settlement.stepwise); the towns within READY_M of `near` (where the
## world is first seen from) before this returns, so the world says it is ready with them standing,
## and the others after it, one at a time, once the eye comes near enough, nearest first (`_process`),
## so the country is not held for towns nobody is looking at. `doors_placed` is emitted when this
## returns, with the doors all placed.
func place_all_over_frames(near: Array = []) -> void:
	_place_doors()
	if not raise_fabric:
		doors_placed.emit(placed.size())
		_placed = true
		return
	_fill = _fabric_begin()
	_queue = (_fill.get("places", []) as Array).duplicate()
	_placed = true
	while true:
		var next := _nearest_queued(near, READY_M)
		if next.is_empty():
			break
		await _raise_paced(next)
		if not is_inside_tree():
			return
	doors_placed.emit(placed.size())
	_in_background = true
	set_process(not _queue.is_empty())
	if _queue.is_empty():
		_fabric_end(_fill)


func _process(delta: float) -> void:
	if not _in_background or _raising != null or not is_inside_tree():
		return
	if _queue.is_empty():
		set_process(false)
		return
	_look_in -= delta
	if _look_in > 0.0:
		return
	_look_in = LOOK_EVERY_S
	_raise_next()


func _raise_next() -> void:
	if _raising != null or _queue.is_empty():
		return
	# while a film's pictures are watched nothing is raised: its opening's black is where the towns
	# its shots open on are raised, and its first picture waits for them (ShotSight.TOWNS_M)
	if not WorldPace.curtained() and get_tree().get_first_node_in_group(CinematicPlayer.GROUP) != null:
		return
	var next := _nearest_queued(_eyes(), WANT_M if WorldPace.curtained() else WANT_WATCHED_M)
	if next.is_empty():
		return
	await _raise_paced(next)
	if _queue.is_empty() and is_inside_tree():
		set_process(false)
		_fabric_end(_fill)


## Where the world is being looked at from: whatever the streamer follows, and the points it is
## asked to stand round besides (a film's next shot).
func _eyes() -> Array:
	var out: Array = []
	var world := _world()
	var streamer := world.streamer if world != null else null
	if streamer != null:
		if streamer.target != null and is_instance_valid(streamer.target):
			out.append(streamer.target.global_position)
		out.append_array(streamer.also_around)
	return out


## The queued town nearest any of `points` within `reach`, taken off the queue; {} for none. With no
## points and no limit to the reach, the first queued.
func _nearest_queued(points: Array, reach: float) -> Dictionary:
	var world := _world()
	if _queue.is_empty() or world == null:
		return {}
	var best := 0 if points.is_empty() and reach == INF else -1
	var best_d := INF
	for i in _queue.size():
		var at := world.place_position(str((_queue[i] as Dictionary).get("id", "")))
		for p in points:
			var d := Vector2((p as Vector3).x - at.x, (p as Vector3).z - at.z).length()
			if d < best_d and d <= reach:
				best_d = d
				best = i
	if best < 0:
		return {}
	var place: Dictionary = _queue[best]
	_queue.remove_at(best)
	return place


## Raises one town a piece at a time and returns when it stands.
func _raise_paced(place: Dictionary) -> void:
	if place.is_empty():
		return
	var s := _raise_settlement(place, _fill, true)
	if s == null or s.is_raised:
		return
	_raising = s
	await s.raised
	if _raising == s:
		_raising = null


## Whether every town within `reach` of `at` stands (none queued or half-raised there). What a film's
## shot or the loading fade waits for besides the cells (UI.near_ring_progress).
func towns_standing_near(at: Vector3, reach: float) -> Vector2i:
	var world := _world()
	var wanted := 0
	var standing := 0
	if world == null:
		return Vector2i.ZERO
	for place in _queue:
		var p := world.place_position(str((place as Dictionary).get("id", "")))
		if Vector2(p.x - at.x, p.z - at.z).length() <= reach:
			wanted += 1
	for s in fabric:
		if is_instance_valid(s) and Vector2(s.position.x - at.x, s.position.z - at.z).length() <= reach:
			wanted += 1
			standing += 1 if s.is_raised else 0
	return Vector2i(standing, wanted)


## Every world's doors' towns within `reach` of `at`: Vector2i(standing, wanted).
static func towns_near(tree: SceneTree, at: Vector3, reach: float) -> Vector2i:
	var out := Vector2i.ZERO
	if tree == null:
		return out
	for wd in tree.get_nodes_in_group("world_doors"):
		if wd is WorldDoors:
			out += (wd as WorldDoors).towns_standing_near(at, reach)
	return out


func _place_doors() -> void:
	for door in placed:
		if is_instance_valid(door):
			door.queue_free()
	placed.clear()
	for building in raised:
		if is_instance_valid(building):
			building.queue_free()
	raised.clear()
	streets.clear()
	_road_lines = _roads()
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != PLAN_ROLE:
			continue
		var place := str(plan.get("place", ""))
		var centre := _centre_of(place, plan)
		if centre == Vector3.INF:
			Log.warn("WorldDoors", "%s: no ground for %s" % [plan.get("id", "?"), place])
			continue
		var street := _street_for(place, centre)
		for row in plan.get("rows", []):
			var door := _place_one(row, centre, place, street)
			if door != null:
				placed.append(door)
	Log.info("WorldDoors", "placed %d doors" % placed.size())


## The town around the doors. Twenty-four interiors do not make eleven settlements; the fabric
## is what turns a paved circle with four doors on it into somewhere people live.
func _fill_settlements() -> void:
	var fill := _fabric_begin()
	for place in fill.get("places", []):
		_raise_settlement(place, fill)
	_fabric_end(fill)


## What raising the fabric needs, worked out once: the roads, the ground kept clear, the places.
## {} with no world.
func _fabric_begin() -> Dictionary:
	for s in fabric:
		if is_instance_valid(s):
			s.queue_free()
	fabric.clear()
	var world := _world()
	if world == null:
		return {}
	var roads := _road_lines if not _road_lines.is_empty() else _roads()
	# A house with an inside is on its street's plan already; a deep place's mouth that opens in
	# a settlement keeps its own ground clear.
	var reserved: Array[Rect2] = []
	for door in placed:
		if is_instance_valid(door) and str(ContentDB.get_or_empty(door.interior_id).get("kind", "")) == "deep_place":
			var p := door.global_position
			reserved.append(Rect2(p.x - 11.0, p.z - 11.0, 22.0, 22.0))
	# A landmark keeps its own footprint clear. Grandfather Hollow's centre is the Grandfather's
	# trunk, and its ring of houses round a green was being laid inside the tree.
	for entry_v in world.pois():
		var entry: Dictionary = entry_v
		if entry.has("scene"):
			var lp: Array = entry.get("pos", [0, 0, 0])
			reserved.append_array(footprint(Vector2(float(lp[0]), float(lp[2])), PoiKit.radius_of(str(entry["scene"]))))
	var places: Array = []
	for place in ContentDB.all("place"):
		if Settlement.FABRIC.has(str(place.get("kind", ""))):
			places.append(place)
	return {"world": world, "roads": roads, "reserved": reserved, "places": places, "built": 0}


func _raise_settlement(place: Dictionary, fill: Dictionary, stepwise := false) -> Settlement:
	var world: World = fill.get("world", null)
	if world == null or not is_instance_valid(world):
		return null
	var roads: Array = fill["roads"]
	var reserved: Array[Rect2] = fill["reserved"]
	var kind := str(place.get("kind", ""))
	var id := str(place.get("id", ""))
	var centre := world.place_position(id)
	if centre == Vector3.ZERO:
		return null
	var radius := _pad_radius(world, id)
	var near: Array = []
	for line in roads:
		if _touches(line, centre, radius):
			near.append(line)
	var street: StreetPlan = streets.get(id, null)
	if street == null:
		street = StreetPlan.make(id, kind, Vector2(centre.x, centre.z), radius, near)
		streets[id] = street
	var s := Settlement.raise_at(id, kind, str(place.get("region", "")), centre, radius,
			near, reserved, street)
	s.stepwise = stepwise
	fabric.append(s)
	fill["built"] = int(fill["built"]) + 1
	add_child(s)
	return s


func _fabric_end(fill: Dictionary) -> void:
	if fill.is_empty():
		return
	Log.info("WorldDoors", "raised the fabric of %d settlements" % int(fill["built"]))


## A round footprint as the fabric's reserved rectangles: a cross of two, which between them hold
## the whole disc and leave the corners of its bounding square free for plots.
static func footprint(centre: Vector2, radius: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if radius <= 0.5:
		return out
	var k := radius * 0.72
	out.append(Rect2(centre.x - radius, centre.y - k, radius * 2.0, k * 2.0))
	out.append(Rect2(centre.x - k, centre.y - radius, k * 2.0, radius * 2.0))
	return out


func _roads() -> Array:
	var path := "res://world/generated/roads.json"
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in parsed:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).get("points", []))
	return out


static func _touches(line_v: Variant, centre: Vector3, radius: float) -> bool:
	if typeof(line_v) != TYPE_ARRAY:
		return false
	for p_v in line_v:
		var p: Array = p_v
		if Vector2(float(p[0]) - centre.x, float(p[1]) - centre.z).length() < radius:
			return true
	return false


## How much ground the world flattened for this place, which is how much town there is room for.
func _pad_radius(world: World, place_id: String) -> float:
	for entry in world.pois():
		var poi: Dictionary = entry
		if str(poi.get("place_id", "")) == place_id:
			return pad_radius_of(poi)
	return 40.0


## A built pad's room for houses. `radius_level_m` is how far the ground is truly level (the
## builder writes it beside `radius_flat_m`, which the dressings, arrival and tests keep reading);
## a house past it would stand on the pad's skirt. A build without it gives `radius_flat_m`.
static func pad_radius_of(poi: Dictionary) -> float:
	var r := float(poi.get("radius_level_m", poi.get("radius_flat_m", 40.0)))
	return maxf(r, 24.0)


## Where the place stands in the world: the built POI data first, since that is the ground the
## world actually has, then the place's own definition (a headless test has no world). A plan
## says only which place; it used to copy the place's position as well, and a copy stays behind
## when the map is redrawn (docs/COORDINATES.md).
func _centre_of(place_id: String, _plan: Dictionary) -> Vector3:
	var world := _world()
	if world != null:
		var at := world.place_position(place_id)
		if at != Vector3.ZERO:
			return at
	var xz := PlaceRef.xz(place_id)
	if xz == Vector2.INF:
		return Vector3.INF
	return Vector3(xz.x, 0.0, xz.y)


## A settlement's streets, for placing its houses. Null for a place the fabric does not build
## (a deep place, a landmark): its doors stand where the plan's ring puts them.
func _street_for(place_id: String, centre: Vector3) -> StreetPlan:
	if streets.has(place_id):
		return streets[place_id]
	var kind := str(ContentDB.get_or_empty(place_id).get("kind", ""))
	if not Settlement.FABRIC.has(kind):
		return null
	var world := _world()
	var radius := _pad_radius(world, place_id) if world != null else 40.0
	var near: Array = []
	for line in _road_lines:
		if _touches(line, centre, radius):
			near.append(line)
	var street := StreetPlan.make(place_id, kind, Vector2(centre.x, centre.z), radius, near)
	streets[place_id] = street
	return street


func _place_one(row_v: Variant, centre: Vector3, place_id: String, street: StreetPlan = null) -> Door:
	if typeof(row_v) != TYPE_DICTIONARY:
		return null
	var row: Dictionary = row_v
	var interior := str(row.get("interior", ""))
	if interior == "" or not ContentDB.has(interior):
		Log.warn("WorldDoors", "%s names an interior that does not exist: '%s'" % [place_id, interior])
		return null
	var packed := load(DOOR_SCENE) as PackedScene
	var door: Door = packed.instantiate() as Door if packed != null else Door.new()
	door.interior_id = interior
	door.display_name = str(row.get("name", ContentDB.get_or_empty(interior).get("name", "a door")))
	door.name = "Door_" + Ids.name_of(interior)
	add_child(door)
	var bearing := deg_to_rad(float(row.get("bearing_deg", 0.0)))
	var ring := float(row.get("ring_radius", 20.0))
	var at := centre + Vector3(sin(bearing), 0.0, cos(bearing)) * ring
	# A door faces out of the building. Where the place has streets, a house fronts one: the
	# plan's bearing and ring say where in the place it wanted to be, and the frontage nearest
	# that is where it stands, its door on the street. Otherwise it faces away from the middle.
	var facing := bearing
	if str(row.get("kind", "")) == "house" and street != null:
		var foot := Building.footprint_of(interior)
		if foot.size != Vector2.ZERO:
			var plot := street.place_real(interior, foot, Vector2(at.x, at.z))
			if not plot.is_empty():
				var d2: Vector2 = plot["door"]
				var face: Vector2 = plot["facing"]
				at = Vector3(d2.x, 0.0, d2.y)
				facing = atan2(face.x, face.y)
	door.global_position = _on_ground(at)
	door.rotation.y = facing
	if bool(row.get("locked", false)):
		_lock(door, interior)
	if str(row.get("kind", "")) == "house" and raise_buildings:
		_raise_building(interior, door.global_position, facing)
	return door


## The house around the door. A deep place's mouth is a hole in a hill and needs nothing; a
## house needs to be a house from across the green, and the one we raise is the one you enter,
## because it is built from that interior's own rooms.
func _raise_building(interior_id: String, at: Vector3, bearing: float) -> void:
	# The interior extends away from its front wall, so the building turns to put its back to
	# the door's facing.
	var building := Building.raise_for(interior_id, at, bearing + PI)
	add_child(building)
	raised.append(building)


func _on_ground(point: Vector3) -> Vector3:
	var provider := _terrain()
	if provider == null:
		return point
	return Vector3(point.x, provider.get_height(point.x, point.z) + SILL, point.z)


## The resident owns their own front door, so forcing it is theft from somebody in particular.
func _lock(door: Door, interior_id: String) -> void:
	var def := ContentDB.get_or_empty(interior_id)
	var lock := DoorLock.new()
	lock.name = "DoorLock"
	lock.locked = true
	lock.lock_level = int(def.get("lock_level", 2))
	var resident := str(def.get("resident_npc", def.get("owner_npc", "")))
	if resident != "" and ContentDB.has(resident):
		lock.owner_npc = resident
		door.owner_npc = resident
	var faction := str(def.get("owner_faction", ""))
	if faction != "":
		lock.owner_faction = faction
		door.owner_faction = faction
	door.add_child(lock)


## The ground, through this world rather than the singleton.
func _terrain() -> TerrainProvider:
	var world := _world()
	return world.provider if world != null else null
