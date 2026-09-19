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

var placed: Array[Door] = []


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
	doors_placed.emit(placed.size())
	return placed.size()


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
	return door


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
