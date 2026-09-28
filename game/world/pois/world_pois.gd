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
## Stand up what each place's `encounter` def says is there (`PoiEncounters`). Off for a tool that
## wants the dressing without anybody in it.
@export var encounters: bool = true

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
	for c in candidates(pois + unbuilt_entries(pois, provider)):
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


## Entries for the POIs the content has and the built world does not yet: one written after the
## land was last built has no pad in `pois.json` until the next build flattens one. It is dressed
## where its def says, on the ground as it stands, so a place added for the story (the Stair Head,
## where a new game starts) is there the day it is written rather than the day the land is next
## rebuilt. `World.place_position` and `PlaceDiscovery` already fall back to the def the same way.
static func unbuilt_entries(pois: Array, terrain: TerrainProvider) -> Array:
	var built := {}
	for e in pois:
		if typeof(e) == TYPE_DICTIONARY:
			built[str((e as Dictionary).get("place_id", ""))] = true
	var out: Array = []
	for def in ContentDB.all("poi"):
		var id := str(def.get("id", ""))
		if id.is_empty() or built.has(id):
			continue
		var xz := WorldProbe.xz_of(def)
		if xz == Vector2.ZERO:
			continue
		var y := terrain.get_height(xz.x, xz.y) if terrain != null else 0.0
		out.append({"place_id": id, "pos": [xz.x, y, xz.y],
				"radius_flat_m": float(def.get("radius_m", 18.0)), "unbuilt": true})
	return out


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - _origin.x) / _cell_size)), int(floor((pos.z - _origin.y) / _cell_size)))


func count() -> int:
	return _entries.size()


func entries() -> Array:
	return _entries


## What raising the places has cost, by kind: kind -> [raised, total ms, longest ms] (the CPU probe,
## tools_gd/cpu_probe.gd).
static var raise_ms: Dictionary = {}


## The dressings of one cell, parented to `parent` (the cell node, so they unload with it); `far`
## asks for silhouettes only. The streamer raises them a place at a time instead (`items_in_cell`,
## `raise_item`, `finish_cell`), so a cell of several places is not one long frame.
func raise_in_cell(parent: Node3D, cell: Vector2i, far: bool) -> Array[PoiDressing]:
	var out: Array[PoiDressing] = []
	for item in items_in_cell(cell):
		out.append(raise_item(parent, item, far))
	finish_cell(parent, cell, far, out)
	return out


## The places a cell raises ({entry, def}), in order; none when the dressings are off.
func items_in_cell(cell: Vector2i) -> Array:
	if not enabled or not indexed:
		return []
	return _by_cell.get(cell, [])


## One place's dressing, raised under `parent`.
## Whether `raise_item` leaves a place's masonry to a worker thread (PoiDressing.defer_meshes); the
## streamer, which asks `meshes_ready` of each, turns it on. `raise_in_cell` never does.
var defer_meshes := false


func raise_item(parent: Node3D, item: Dictionary, far: bool) -> PoiDressing:
	var t0 := Time.get_ticks_usec()
	var d := PoiDressing.raise(item["entry"], item["def"], far, provider, roads)
	d.position = d.world_position - parent.position
	# where the world is drawn, its masonry is made on a worker thread (the streamer waits for it)
	d.defer_meshes = defer_meshes
	parent.add_child(d)
	raised.append(d)
	var k := "%s%s" % [str((item["def"] as Dictionary).get("kind", "?")), " (far)" if far else ""]
	var st: Array = raise_ms.get(k, [0, 0.0, 0.0])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	raise_ms[k] = [int(st[0]) + 1, snappedf(float(st[1]) + ms, 0.1), snappedf(maxf(float(st[2]), ms), 0.1)]
	return d


## `finish_cell` a piece at a time: step `k` (from 0) stands up who is at one place, and the last
## what the quests say lies there. True when that last step is done.
func finish_step(parent: Node3D, cell: Vector2i, far: bool, out: Array, k: int) -> bool:
	if k == 0:
		_forget_the_freed()
	if far or not enabled or not indexed:
		return true
	if k < out.size():
		if encounters and is_instance_valid(out[k]):
			PoiEncounters.stand_up(out[k])
		return false
	var items := get_tree().get_first_node_in_group("quest_items") if is_inside_tree() else null
	if items != null and items.has_method("raise_in_cell"):
		items.call("raise_in_cell", parent, cell)
	return true


## Once a cell's places are raised: who stands at them, and what the quests say lies there.
func finish_cell(parent: Node3D, cell: Vector2i, far: bool, out: Array) -> void:
	_forget_the_freed()
	if far or not enabled or not indexed:
		return
	# what each place's encounter sentence says stands there, on the dressing's own markers
	if encounters:
		for d in out:
			if is_instance_valid(d):
				PoiEncounters.stand_up(d)
	# what the quests say lies here (the tine at the Toll, the hand-bell in the fallen stair),
	# after the dressing so a thing can lie on the marker its dressing put down
	var items := get_tree().get_first_node_in_group("quest_items") if is_inside_tree() else null
	if items != null and items.has_method("raise_in_cell"):
		items.call("raise_in_cell", parent, cell)


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


## The built road between two places, as map points from `from_id` to `to_id`; empty when the
## world has none. The road is the one the path names (`built_road`), else the one named for its two
## ends (`core:road/<from>_<to>`, the atlas's own default), either way round; it has to start and
## end within ROAD_END_M of them, so a road of another build is not taken for this one's.
const ROAD_END_M := 60.0
static var _road_cache: Array = []
static var _road_cache_stamp := -1


static func road_between(from_id: String, to_id: String, named := "") -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a := PlaceRef.xz(from_id)
	var b := PlaceRef.xz(to_id)
	if a == Vector2.INF or b == Vector2.INF:
		return out
	var ids: Array[String] = ["core:road/%s_%s" % [Ids.name_of(from_id), Ids.name_of(to_id)],
		"core:road/%s_%s" % [Ids.name_of(to_id), Ids.name_of(from_id)]]
	if named != "":
		ids = [named]
	for r in _roads_with_ids():
		var id := str((r as Dictionary).get("id", ""))
		if not id in ids:
			continue
		for p in (r as Dictionary).get("points", []):
			if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
				out.append(Vector2(float(p[0]), float(p[1])))
		if out.size() >= 2 and out[0].distance_to(a) > out[out.size() - 1].distance_to(a):
			out.reverse()
		if out.size() < 2 or out[0].distance_to(a) > ROAD_END_M or out[out.size() - 1].distance_to(b) > ROAD_END_M:
			out.clear()
		return out
	return out


## roads.json as written, read once per build of it (the file's modified time says which).
static func _roads_with_ids() -> Array:
	if not FileAccess.file_exists(ROADS_PATH):
		return []
	var stamp := FileAccess.get_modified_time(ROADS_PATH)
	if stamp != _road_cache_stamp:
		_road_cache_stamp = stamp
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
		_road_cache = parsed if typeof(parsed) == TYPE_ARRAY else []
	return _road_cache


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
