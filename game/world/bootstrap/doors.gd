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


func _ready() -> void:
	add_to_group("world_doors")
	if not place_doors:
		return
	# A child is ready before its parent: World.instance is still null here and the ground does
	# not exist yet, so doors placed now would hang at zero metres.
	var world := _world()
	if world != null and not world.is_world_ready:
		await world.world_ready
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
	if raise_fabric:
		_fill_settlements()
	doors_placed.emit(placed.size())
	return placed.size()


## The town around the doors. Twenty-four interiors do not make eleven settlements; the fabric
## is what turns a paved circle with four doors on it into somewhere people live.
func _fill_settlements() -> void:
	for s in fabric:
		if is_instance_valid(s):
			s.queue_free()
	fabric.clear()
	var world := _world()
	if world == null:
		return
	var roads := _road_lines if not _road_lines.is_empty() else _roads()
	# A house with an inside is on its street's plan already; a deep place's mouth that opens in
	# a settlement keeps its own ground clear.
	var reserved: Array[Rect2] = []
	for door in placed:
		if is_instance_valid(door) and str(ContentDB.get_or_empty(door.interior_id).get("kind", "")) == "deep_place":
			var p := door.global_position
			reserved.append(Rect2(p.x - 11.0, p.z - 11.0, 22.0, 22.0))
	var built := 0
	for place in ContentDB.all("place"):
		var kind := str(place.get("kind", ""))
		if not Settlement.FABRIC.has(kind):
			continue
		var id := str(place.get("id", ""))
		var centre := world.place_position(id)
		if centre == Vector3.ZERO:
			continue
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
		add_child(s)
		fabric.append(s)
		built += 1
	Log.info("WorldDoors", "raised the fabric of %d settlements" % built)


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
			return maxf(float(poi.get("radius_flat_m", 40.0)), 24.0)
	return 40.0


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
