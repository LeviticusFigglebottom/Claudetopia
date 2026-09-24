class_name HorizonLayer
extends Node3D
## What stands on the skyline past the streamed ring (docs/HORIZON.md).
##
## The streamer builds the country out to `far_ring` cells, 384 to 640 m from the eye, and a
## landmark's model and a point of interest's dressing belong to their cell, so past that ring
## nothing was drawn but the ground: Merrowby at 2.4 km from the Stair Head, the Grandfather and
## the Tower of Vaelost at 3.2 km. This layer is always loaded and holds a stand-in for each thing
## the horizon should carry:
##
##   Tier A  every landmark model (a `scene` in pois.json, and the Choir's ring of colossi in the
##           cells round it), drawn with the model's own far levels, out to 4.2 km (6 at Epic);
##   Tier B  every point of interest of a tall kind (towers, falls, strange trees, giant bones),
##           the dressing's own far-silhouette build, out to 2.5 km (4.2 at Epic).
##
## Tier C, the settlements, needs no stand-in: their fabric is raised for the whole world when it
## loads and is drawn to the camera's far plane, which View distance sets (Graphics.camera_far).
##
## A stand-in is the very mesh the cell draws at that distance (a landmark's levels change where
## `LandmarkLod` says, in the cell and here alike, and a far-ring cell raises the same silhouette
## dressing), so handing over is a swap of identical pictures: the stand-in is hidden in the
## frame its cell is built, and shown again in the frame the cell goes, with no pop and nothing
## drawn twice.
##
## Nothing is held back by the sightline model: a stand-in behind a hill is hidden by the hill,
## drawn by Terrain3D to the edge of the world, and a stand-in the model calls hidden by a metre
## of ground at 64 samples is often in plain view on the screen. The model decides what the map
## says the player has seen; the screen shows what the land shows.
##
## View distance also sets the vertices in each of Terrain3D's clipmap rings (32, 48, 64): each
## ring is twice as coarse as the one inside it, so more vertices a ring is finer ground at every
## distance, and the far hills keep their shape rather than a blob's.
##
## Everything here takes the world's fog as the rest of the country does: the stand-ins are the
## country's own materials, so the haze paints them the way it paints a far hill.

const GROUP := "horizon_layer"
## The kinds whose dressings carry past the streamed ring (Tier B).
const TALL_KINDS: Array[String] = ["tower", "waterfall", "strange_tree", "giant_bones"]
## Points of interest the spec leaves off although their kind is tall.
const LEAVE_OFF: Array[String] = ["core:poi/bone_ford"]
## Landmark models the spec leaves off: a pool is not a skyline, and a hill figure has no height.
const LANDMARK_LEAVE_OFF: Array[String] = ["core:place/eelfathom", "core:place/chalk_hound"]
## Reach of each tier at each View distance: 0 Near, 1 Far, 2 Epic.
const TIER_A_M: Array[float] = [2500.0, 4200.0, 6000.0]
const TIER_B_M: Array[float] = [1500.0, 2500.0, 4200.0]
## Cells round a landmark place whose scene entries are its own (the Choir's colossi stand up to
## 160 m from its centre; two cells either way covers them wherever the centre falls).
const LANDMARK_CELLS := 2
const GENERATED := "res://world/generated"

## One stand-in: what it is, where, which cell hands it over, how tall it stands.
class Proxy extends RefCounted:
	var id := ""
	var tier := "A"
	var node: Node3D = null
	var cell := Vector2i.ZERO
	var base := Vector3.ZERO
	var top_m := 6.0
	var in_cell := false      # its cell is built, so the cell draws it
	## a landmark's levels: mesh instance -> its own [begin, end] (end 0: to the tier's reach)
	var bands: Dictionary = {}

var streamer: WorldStreamer = null
var provider: TerrainProvider = null
var proxies: Array[Proxy] = []
var setting := 1
var built := false


func _ready() -> void:
	add_to_group(GROUP)
	if Settings.has_signal("changed") and not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	if not EventBus.cell_loaded.is_connected(_on_cell_loaded):
		EventBus.cell_loaded.connect(_on_cell_loaded)
	if not EventBus.cell_unloaded.is_connected(_on_cell_unloaded):
		EventBus.cell_unloaded.connect(_on_cell_unloaded)
	setting = int(Settings.get_value("graphics", "view_distance", 1))


## Builds every stand-in. `pois` is pois.json; `dressings` the WorldPois entries ({entry, def}),
## and `roads` what the dressings lay their paths along.
func build(pois: Array, dressings: Array, roads: Array = []) -> int:
	for p in proxies:
		if is_instance_valid(p.node):
			p.node.queue_free()
	proxies.clear()
	var seen := {}
	for e_v in pois:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var scene := str(e.get("scene", ""))
		var id := str(e.get("place_id", ""))
		if scene.is_empty() or id in LANDMARK_LEAVE_OFF:
			continue
		var at := _vec(e.get("pos", [0, 0, 0]))
		# a place is one model at its pad, or a ring of them (the Choir's twelve colossi), which
		# only the cells round it know where the builder stood
		var entries: Array = [{"scene": scene, "pos": e.get("pos"), "yaw": e.get("yaw", 0.0)}]
		if _ring_count(scene) > 1:
			entries.clear()
			for c_v in _cell_scenes_round(at):
				var c: Dictionary = c_v
				if str((c.get("props", {}) as Dictionary).get("place_id", "")) == id:
					entries.append(c)
		for s_v in entries:
			var s: Dictionary = s_v
			var key := "%s@%s" % [str(s.get("scene", "")), str(_vec(s.get("pos", [0, 0, 0])).round())]
			if seen.has(key):
				continue
			seen[key] = true
			var p := _landmark(id, s)
			if p != null:
				proxies.append(p)
	for item_v in dressings:
		var item: Dictionary = item_v
		var entry: Dictionary = item.get("entry", {})
		var def: Dictionary = item.get("def", {})
		var id := str(entry.get("place_id", ""))
		if id in LEAVE_OFF or not (PoiDressing.kind_of(id, def) in TALL_KINDS):
			continue
		var p := _dressing(entry, def, roads)
		if p != null:
			proxies.append(p)
	built = true
	for p in proxies:
		p.in_cell = streamer != null and streamer.has_cell(p.cell)
	apply_setting()
	return proxies.size()


## Builds from the world: its pois.json, the dressings WorldPois would raise, the roads.
func build_from(world: World) -> int:
	streamer = world.streamer
	provider = world.provider
	var pois := world.pois()
	var dressings := WorldPois.candidates(pois + WorldPois.unbuilt_entries(pois, provider))
	var t0 := Time.get_ticks_msec()
	var n := build(pois, dressings, WorldPois.roads_from_disk())
	Log.info("Horizon", "%d on the skyline (%d landmark models, %d tall places) in %d ms"
			% [n, count("A"), count("B"), Time.get_ticks_msec() - t0])
	return n


## How many of a landmark model its builder stands round the place (the meta's `ring_count`).
static func _ring_count(scene: String) -> int:
	var meta_path := scene.get_basename() + ".meta.json"
	if not FileAccess.file_exists(meta_path):
		return 1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	return int((parsed as Dictionary).get("ring_count", 1)) if parsed is Dictionary else 1


func count(tier := "") -> int:
	var n := 0
	for p in proxies:
		if tier.is_empty() or p.tier == tier:
			n += 1
	return n


## How many stand-ins are on screen now.
func shown() -> int:
	var n := 0
	for p in proxies:
		if is_instance_valid(p.node) and p.node.visible:
			n += 1
	return n


## What the skyline is doing, in words, for a capture's log.
func summary() -> String:
	var in_cell := 0
	var names: Array[String] = []
	for p in proxies:
		if p.in_cell:
			in_cell += 1
		elif is_instance_valid(p.node) and p.node.visible:
			names.append(Ids.name_of(p.id))
	return "%d standing, %d handed to their cells (view distance %d): %s" % [
			names.size(), in_cell, setting, ", ".join(names)]


func proxy(id: String) -> Proxy:
	for p in proxies:
		if p.id == id:
			return p
	return null


## The reach of a tier at the current setting.
func reach(tier: String) -> float:
	var s := clampi(setting, 0, 2)
	return TIER_A_M[s] if tier == "A" else TIER_B_M[s]


func apply_setting() -> void:
	for p in proxies:
		if not is_instance_valid(p.node):
			continue
		var r := reach(p.tier)
		for g in _geometry(p.node):
			var band: Array = p.bands.get(g, [0.0, 0.0])
			g.visibility_range_begin = float(band[0])
			g.visibility_range_begin_margin = float(band[0]) * LandmarkLod.HYSTERESIS_SHARE
			g.visibility_range_end = minf(float(band[1]), r) if float(band[1]) > 0.0 else r
			g.visibility_range_end_margin = g.visibility_range_end * 0.1
			# a stand-in's last level fades out at the reach, into haze that has all but taken it;
			# its levels change outright, as the cell's do
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF \
					if float(band[1]) <= 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		_show(p)
	_apply_terrain()


## View distance's vertices per clipmap ring, on the world's Terrain3D if there is one.
func _apply_terrain() -> void:
	var world := World.instance
	if world == null or not is_instance_valid(world.terrain_node):
		return
	var size := Graphics.terrain_mesh_size({"view_distance": setting})
	if int(world.terrain_node.get("mesh_size")) != size:
		world.terrain_node.set("mesh_size", size)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "graphics" and key == "view_distance":
		setting = int(value)
		apply_setting()


func _on_cell_loaded(cell: Vector2i) -> void:
	for p in proxies:
		if p.cell == cell:
			p.in_cell = true
			_show(p)


func _on_cell_unloaded(cell: Vector2i) -> void:
	for p in proxies:
		if p.cell == cell:
			p.in_cell = false
			_show(p)


func _show(p: Proxy) -> void:
	if is_instance_valid(p.node):
		p.node.visible = not p.in_cell


# --- the stand-ins -------------------------------------------------------------------------------

## A landmark model's stand-in: its lowest LOD, where its cell would stand it.
func _landmark(id: String, s: Dictionary) -> Proxy:
	var path := str(s.get("scene", ""))
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	# the levels the cell draws past its streamed ring: all but the full mesh, whose band ends
	# where no cell is ever unloaded
	var height := LandmarkLod.apply(inst)
	var at := _vec(s.get("pos", [0, 0, 0]))
	var holder := Node3D.new()
	holder.name = "A_" + Ids.name_of(id)
	holder.position = at
	holder.rotation.y = deg_to_rad(float(s.get("yaw", 0.0)))
	var p := Proxy.new()
	for src_v in inst.find_children("*", "MeshInstance3D", true, false):
		var src := src_v as MeshInstance3D
		if src.mesh == null or LandmarkLod.level_of(src.name) == 0:
			continue
		var local := Transform3D.IDENTITY
		var n: Node = src
		while n != null and n != inst:
			local = (n as Node3D).transform * local
			n = n.get_parent()
		var mi := MeshInstance3D.new()
		mi.name = src.name
		mi.mesh = src.mesh
		mi.transform = local
		for i in src.get_surface_override_material_count():
			mi.set_surface_override_material(i, src.get_surface_override_material(i))
		mi.material_override = src.material_override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		p.bands[mi] = [src.visibility_range_begin, src.visibility_range_end]
	inst.free()
	if holder.get_child_count() == 0:
		holder.free()
		return null
	add_child(holder)
	p.id = id
	p.tier = "A"
	p.node = holder
	p.base = at
	p.top_m = maxf(height, PlaceDiscovery.landmark_height(id))
	p.cell = _cell_of(at)
	return p


## A tall point of interest's stand-in: its dressing's own far silhouette.
func _dressing(entry: Dictionary, def: Dictionary, roads: Array) -> Proxy:
	var d := PoiDressing.raise(entry, def, true, provider, roads)
	add_child(d)          # builds in _ready
	d.remove_from_group(PoiDressing.GROUP)
	d.name = "B_" + Ids.name_of(d.poi_id)
	# a stand-in is a picture: nothing in it may be walked into, found, or counted as the place
	for body in d.find_children("*", "CollisionObject3D", true, false):
		(body as Node).queue_free()
	for light in d.find_children("*", "Light3D", true, false):
		(light as Node).queue_free()
	for g in _geometry(d):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p := Proxy.new()
	p.id = d.poi_id
	p.tier = "B"
	p.node = d
	p.base = d.world_position
	p.top_m = PlaceDiscovery.landmark_height(d.poi_id)
	p.cell = _cell_of(d.world_position)
	return p


func _geometry(root: Node) -> Array:
	var out: Array = []
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		out.append(g)
	return out


## The scene entries the cells round `at` stand (the streamer builds them there).
func _cell_scenes_round(at: Vector3) -> Array:
	var out: Array = []
	var c := _cell_of(at)
	for dz in range(-LANDMARK_CELLS, LANDMARK_CELLS + 1):
		for dx in range(-LANDMARK_CELLS, LANDMARK_CELLS + 1):
			out.append_array(cell_scenes(Vector2i(c.x + dx, c.y + dz)))
	return out


## The `scenes` array of one built cell, read without parsing the cell's scatter (a cell file is
## most of a megabyte of instance rows; its scenes are a line).
static func cell_scenes(cell: Vector2i) -> Array:
	var path := "%s/cells/%d_%d.json" % [GENERATED, cell.x, cell.y]
	if not FileAccess.file_exists(path):
		return []
	var text := FileAccess.get_file_as_string(path)
	var at := text.find("\"scenes\"")
	if at < 0:
		return []
	var open := text.find("[", at)
	if open < 0:
		return []
	var depth := 0
	var close := -1
	for i in range(open, text.length()):
		var ch := text[i]
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth -= 1
			if depth == 0:
				close = i
				break
	if close < 0:
		return []
	var parsed: Variant = JSON.parse_string(text.substr(open, close - open + 1))
	return parsed if parsed is Array else []


func _cell_of(pos: Vector3) -> Vector2i:
	if streamer != null:
		return streamer.cell_of(pos)
	var origin := provider.origin if provider != null else Vector2(-4096.0, -4096.0)
	return Vector2i(int(floor((pos.x - origin.x) / 256.0)), int(floor((pos.z - origin.y) / 256.0)))


static func _vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
