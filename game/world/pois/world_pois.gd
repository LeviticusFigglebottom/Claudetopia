class_name WorldPois
extends Node3D
## Dresses the points of interest as the streamer reaches them.
##
## `pois.json` has eighty-two entries and nine of them have a scene; the rest were a flattened
## pad and a name. This indexes every entry the builders know how to dress by the cell it
## stands in, and when `WorldStreamer` builds a cell it asks here for that cell's dressings and
## parents them to the cell node — so a camp streams in with its ground, unloads with it, and
## in the far ring is only its silhouette. Raising everything at startup instead would stand
## seventy-odd fires, lanterns and Hearthstones in the tree at once wherever the player is;
## the ring system already decides what is near, and the dressing follows it.
##
## Positions come from the built `pois.json` (the ground the world actually has), never from
## a table here, so moving a POI in the data moves its dressing without touching code.

const GROUP := "world_pois"
const ROADS_PATH := "res://world/generated/roads.json"

@export var enabled: bool = true

var provider: TerrainProvider = null
var roads: Array = []
var indexed := false
var raised: Array[PoiDressing] = []

var _by_cell: Dictionary = {}          # Vector2i -> Array of {entry, def}
var _entries: Array = []               # every dressable {entry, def}
var _origin := Vector2(-4096.0, -4096.0)
var _cell_size := 256.0


func _ready() -> void:
	add_to_group(GROUP)
	if not enabled:
		return
	var world := _world()
	if world != null and not world.is_world_ready:
		await world.world_ready
	if world != null:
		index(world.pois(), world.provider, roads_from_disk())


func _world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	return World.instance


## Buckets every dressable entry by cell. Returns how many will be dressed.
func index(pois: Array, terrain: TerrainProvider, road_lines: Array) -> int:
	provider = terrain
	roads = road_lines
	_by_cell.clear()
	_entries.clear()
	if provider != null:
		_origin = provider.origin
		_cell_size = float(provider.manifest.get("cell_size_m", 256))
	for c in candidates(pois):
		var item: Dictionary = c
		var entry: Dictionary = item["entry"]
		var pos: Array = entry.get("pos", [0, 0, 0])
		var cell := cell_of(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
		_by_cell.get_or_add(cell, []).append(item)
		_entries.append(item)
	indexed = true
	Log.info("WorldPois", "indexed %d points of interest to dress" % _entries.size())
	return _entries.size()


## Every `pois.json` entry a builder can dress, paired with its content def: the POIs with a
## known kind, and the places whose `shrine` tag promises a Hearthstone.
static func candidates(pois: Array) -> Array:
	var out: Array = []
	for entry_v in pois:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var id := str(entry.get("place_id", ""))
		if id == "" or not ContentDB.has(id):
			continue
		var def := ContentDB.get_or_empty(id)
		if PoiDressing.dressable(id, def):
			out.append({"entry": entry, "def": def})
	return out


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - _origin.x) / _cell_size)), int(floor((pos.z - _origin.y) / _cell_size)))


func count() -> int:
	return _entries.size()


func entries() -> Array:
	return _entries


## The dressings of one cell, parented to `parent` (the cell node, so they unload with it).
## Called by the streamer as it builds the cell; `far` asks for silhouettes only.
func raise_in_cell(parent: Node3D, cell: Vector2i, far: bool) -> Array[PoiDressing]:
	var out: Array[PoiDressing] = []
	if not enabled or not indexed:
		return out
	for item_v in _by_cell.get(cell, []):
		var item: Dictionary = item_v
		var d := PoiDressing.raise(item["entry"], item["def"], far, provider, roads)
		d.position = d.world_position - parent.position
		parent.add_child(d)
		out.append(d)
		raised.append(d)
	_forget_the_freed()
	return out


## One POI by id, for a tool or a test; parented here unless told otherwise.
func raise_one(id: String, parent: Node3D = null, far := false) -> PoiDressing:
	for item_v in _entries:
		var item: Dictionary = item_v
		if str((item["entry"] as Dictionary).get("place_id", "")) != id:
			continue
		var host := parent if parent != null else self
		var d := PoiDressing.raise(item["entry"], item["def"], far, provider, roads)
		d.position = d.world_position - host.global_position if host.is_inside_tree() else d.world_position
		host.add_child(d)
		raised.append(d)
		return d
	return null


func _forget_the_freed() -> void:
	var keep: Array[PoiDressing] = []
	for d in raised:
		if is_instance_valid(d):
			keep.append(d)
	raised = keep


static func roads_from_disk() -> Array:
	if not FileAccess.file_exists(ROADS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in parsed:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).get("points", []))
	return out
