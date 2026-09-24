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
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != PLAN_ROLE:
			continue
		var place := str(plan.get("place", ""))
		var centre := _centre_of(place, plan)
		if centre == Vector3.INF:
			Log.warn("WorldDoors", "%s: no ground for %s" % [plan.get("id", "?"), place])
			continue
		for row in plan.get("rows", []):
			var door := _place_one(row, centre, place)
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
	var roads := _roads()
	# Every door already placed keeps its own ground clear, house or hillside mouth alike.
	var reserved: Array[Rect2] = []
	for door in placed:
		if is_instance_valid(door):
			var p := door.global_position
			reserved.append(Rect2(p.x - 11.0, p.z - 11.0, 22.0, 22.0))
	# A landmark keeps its own footprint clear. Grandfather Hollow's centre is the Grandfather's
	# trunk, and its ring of houses round a green was being laid inside the tree.
	for entry_v in world.pois():
		var entry: Dictionary = entry_v
		if entry.has("scene"):
			var lp: Array = entry.get("pos", [0, 0, 0])
			reserved.append_array(footprint(Vector2(float(lp[0]), float(lp[2])), PoiKit.radius_of(str(entry["scene"]))))
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
		var s := Settlement.raise_at(id, kind, str(place.get("region", "")), centre, radius,
				near, reserved)
		add_child(s)
		fabric.append(s)
		built += 1
	Log.info("WorldDoors", "raised the fabric of %d settlements" % built)


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
## world actually has, and the plan's own recorded position as a fallback for a headless test.
func _centre_of(place_id: String, plan: Dictionary) -> Vector3:
	var world := _world()
	if world != null:
		var at := world.place_position(place_id)
		if at != Vector3.ZERO:
			return at
	var pos: Variant = plan.get("position", null)
	if pos is Array and (pos as Array).size() == 2:
		return Vector3(float(pos[0]), 0.0, float(pos[1]))
	return Vector3.INF


func _place_one(row_v: Variant, centre: Vector3, place_id: String) -> Door:
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
	door.global_position = _on_ground(at)
	# A door faces out of the building, which is away from the middle of the settlement.
	door.rotation.y = bearing
	if bool(row.get("locked", false)):
		_lock(door, interior)
	if str(row.get("kind", "")) == "house" and raise_buildings:
		_raise_building(interior, door.global_position, bearing)
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
