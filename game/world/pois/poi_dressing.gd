class_name PoiDressing
extends Node3D
## What stands at a point of interest.
##
## The world builder flattens a pad for every POI and writes its position to `pois.json`;
## nothing else is baked. What the player finds there — a camp's fire ring and tents, a
## shrine's stone and its Hearthstone, a tower, a bridge over the water, a ribcage to walk
## through — is raised here at runtime, the way `Settlement` raises a town: deterministically
## from the POI's id, from the forge's own assets, on the ground the world actually has, with
## the POI's `unique_feature` as the brief the builder answers.
##
## One builder per kind lives in `PoiBuilders`. The dressing is parented to its cell by
## `WorldPois` when the streamer loads that cell, so it streams and unloads with the ring
## system; in the far ring only the silhouette pieces are built.

const GROUP := "poi_dressing"
## The builders are reached by path at runtime, not by their class name.
##
## Every builder takes a `PoiDressing`, so naming `PoiBuilders` here makes the two scripts
## name each other, and GDScript cannot always resolve that: it parses whichever it reaches
## first, fails on the half-built other, and reports "Could not resolve class PoiBuilders,
## because of a parser error" — against `test_pois.gd`, which merely mentions both. It only
## bites once an import has rebuilt the global class cache, so the tests pass when run
## directly and the whole suite fails after `./run.sh test` imports. Loading by path leaves
## the dependency one-way and the cycle gone.
const BUILDERS_PATH := "res://world/pois/poi_builders.gd"

## Every kind a POI can be, and whether the thing built is something you can bump into. A kind
## missing here is a POI that stays a flattened pad, and `test_pois.gd` fails on it.
const KINDS := {
	"camp": true, "shrine": true, "tower": true, "bridge": true, "waterfall": true,
	"ruins": true, "strange_tree": true, "wreck": true, "strange": false, "giant_bones": true,
	"standing_stones": true, "hidden_valley": true,
	## the Hearthstone a settlement or landmark keeps, for a place tagged `shrine`
	"hearth": true,
	## the kinds the drawn map asked for next (docs/ATLAS.md, section 10): a mouth in a slope, the
	## worked land out between the villages, and the marks along a road
	"cave": true, "farmstead": true, "mill": true, "waystone": true, "market_field": true,
	"quarry": true, "shieling": true, "vista": true,
	## the wayside finds the gap map asks for, where a road runs a minute and more past nothing:
	## a cairn, a tally post, a grave, a gibbet, a fold, a well, a lantern post
	"cairn": true, "tally_post": true, "grave": true, "gibbet": true, "fold": true, "well": true,
	"lantern_post": true, "hut": true, "crossroads": true, "peat_cut": true, "beacon": true,
	## the large sites (world/sites, docs/WORLD_LIFE_INTERIORS.md): a way down into a site's inside,
	## and the fortified places you walk round and climb
	"delve": true, "fort": true, "stockade": true, "watchtower": true, "castle_ruin": true, "walled_camp": true,
}

## The kinds a builder exists for. `KINDS` above is the whole list the design names; the
## difference is what is still to be dressed, and `test_pois.gd` prints it rather than hiding
## it. It lives here rather than on the builders because that script has no global name (see
## `poi_builders.gd`), and this is the type everything else already speaks to.
const KINDS_BUILT := ["camp", "shrine", "hearth", "tower", "bridge", "waterfall", "ruins",
		"giant_bones", "strange_tree", "wreck", "hidden_valley", "standing_stones", "strange",
		"cave", "farmstead", "mill", "waystone", "market_field", "quarry", "shieling", "vista",
		"cairn", "tally_post", "grave", "gibbet", "fold", "well", "lantern_post", "hut", "crossroads", "peat_cut",
		"beacon", "delve", "fort", "stockade", "watchtower", "castle_ruin", "walled_camp"]

var poi_id := ""
var kind := ""
var region := ""
var display_name := ""
var brief := ""
var encounter := ""
var pad_radius := 25.0
var far := false
## Where in the world this stands; `position` is relative to whatever cell node holds it.
var world_position := Vector3.ZERO
var wants_hearthstone := false
## Ground some foes will not cross, from the def's `ward` ({radius_m, keeps_off}): Wards.
var ward: Dictionary = {}
## A way marked on the ground from here to somewhere else: `{to: place id, via: [[x, z], ...]}`
## in world coordinates, the walk the POI's builder lays markers along (the Stair Head's cairns
## to the Choir). Empty for nearly everything.
var path: Dictionary = {}
## Where the land is stepped for a waterfall, from its `pois.json` entry (docs/CONTRACTS.md
## section 6): {facing_deg, foot_m, top_m, form, river, faces: [{behind_m, drop_m}]}. Empty where
## the world has no step there, and a fall then makes its own facing and its own hill.
var fall: Dictionary = {}
## Where the land rises behind a cave's mouth, from its `pois.json` entry (docs/CONTRACTS.md
## section 6): {facing_deg, mouth_m, face_top_m, mouth_behind_m, face_half_width_m}. Empty where the
## world raised none, and the cave then raises a bank of its own.
var cave: Dictionary = {}
## How far out the pad is level (`radius_level_m`): a stepped fall's face runs as wide as that.
var level_radius := 17.5
## Where a stepped fall's river falls are read from (rivers.json's `falls`); a test points it at
## its own file.
static var rivers_path := "res://world/generated/rivers.json"

var kit: PoiKit = null
var masonry: PoiMasonry = null
var built := false

var _provider: TerrainProvider = null
var _roads: Array = []


## A dressing for one `pois.json` entry and the content def behind it. Nothing is built until
## it enters the tree. `far` builds the silhouette only. `terrain` and `roads` let a headless
## test hand over real ground and roads; the world's own are used otherwise.
static func raise(entry: Dictionary, def: Dictionary, silhouette := false,
		terrain: TerrainProvider = null, roads: Array = []) -> PoiDressing:
	var d := PoiDressing.new()
	d.poi_id = str(entry.get("place_id", def.get("id", "")))
	d.kind = kind_of(d.poi_id, def)
	d.region = str(def.get("region", ""))
	d.display_name = str(def.get("name", Ids.name_of(d.poi_id).capitalize()))
	d.brief = str(def.get("unique_feature", ""))
	d.encounter = str(def.get("encounter", ""))
	d.pad_radius = float(entry.get("radius_flat_m", 25.0))
	d.level_radius = float(entry.get("radius_level_m", d.pad_radius * 0.7))
	var step: Variant = entry.get("fall", {})
	d.fall = (step as Dictionary).duplicate(true) if typeof(step) == TYPE_DICTIONARY else {}
	var rise: Variant = entry.get("cave", {})
	d.cave = (rise as Dictionary).duplicate(true) if typeof(rise) == TYPE_DICTIONARY else {}
	var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
	d.world_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	d.position = d.world_position
	d.far = silhouette
	d.wants_hearthstone = bool(def.get("hearthstone", false)) or d.kind == "hearth"
	d.ward = def.get("ward", {})
	var way: Variant = def.get("path", {})
	d.path = (way as Dictionary).duplicate(true) if typeof(way) == TYPE_DICTIONARY else {}
	if d.path.has("to"):
		var via: Array = []
		for p in way_points(d.poi_id, def):
			via.append([p.x, p.y])
		if not via.is_empty():
			d.path["via"] = via
	d.name = "Poi_" + Ids.name_of(d.poi_id)
	d._provider = terrain
	d._roads = roads
	return d


## The points a POI's `path` passes on today's map. Where the built world has a road between the
## POI and the place its way leads to, the way is that road: the builder routes a road round a
## hill rather than over it, and a way drawn straight between the same points on the atlas world
## crossed ground of 37 to 61 degrees. Otherwise it is the way's `shape` between its two ends, so
## it follows them when the map is redrawn (`PlaceRef.along`, tools/place_paths.py); a `via` of
## bare coordinates is still read, and stays where it is. `follow_roads` false asks for the
## drawn way whatever is built.
static func way_points(for_poi: String, def: Dictionary, follow_roads := true) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var way: Variant = def.get("path", {})
	if typeof(way) != TYPE_DICTIONARY:
		return out
	var to := str((way as Dictionary).get("to", ""))
	if follow_roads and to != "":
		var road := WorldPois.road_between(for_poi, to, str((way as Dictionary).get("built_road", "")))
		if road.size() >= 2:
			return road
	var shape: Variant = (way as Dictionary).get("shape", null)
	if typeof(shape) == TYPE_ARRAY:
		return PlaceRef.along(for_poi, to, shape)
	for p in (way as Dictionary).get("via", []):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A POI's kind is its own; a place is dressed only for the Hearthstone its `shrine` tag
## promises (the main quest rests at three of them and nothing stood at any), or when its data
## names a `dressing` kind: the Standing Moot is a place, not a registry POI, and the main quest
## fights the Hart of Thorns among stones that nothing had stood there.
static func kind_of(id: String, def: Dictionary) -> String:
	if id.begins_with("core:poi/") or Ids.type_of(id) == "poi":
		return str(def.get("kind", ""))
	if str(def.get("dressing", "")) != "":
		return str(def["dressing"])
	var tags: Variant = def.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and (tags as Array).has("shrine"):
		return "hearth"
	return ""


## Whether anything would be raised for this entry at all.
static func dressable(id: String, def: Dictionary) -> bool:
	return KINDS.has(kind_of(id, def))


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)
	build()


static var _builders: GDScript = null
## Whether the masonry's meshes are made on a worker thread after the builder has run
## (PoiKit.deferred): a place raised while the world is drawn. Ask `meshes_ready` until it is true.
var defer_meshes := false
var _mesh_task := -1
var _mesh_out: Array = []
var _mesh_insts: Array = []

## Raised a step at a time within the frame's budget (PoiKit.stepwise): a place raised while the world
## is drawn (WorldPois.raise_item, for the streamer). Set before it enters the tree. `meshes_ready` is
## false until the last step is done.
var stepwise := false
## Stepwise, waits at every step (a test's way of raising it in the most pieces: PoiKit.every_step).
var step_every := false
## Everything the builder does is done (at once, unless stepwise).
var finished := false
signal built_all
## A stepwise build waiting for its next frame (PoiKit.step), and the word to go on.
var waiting := false
signal resumed
## What the build is counted as in `WorldPois.raise_ms` once it is done (stepwise only).
var raise_key := ""


func build() -> void:
	if built:
		return
	built = true
	kit = PoiKit.new(self, world_position, pad_radius, region, far, poi_id, _provider, _roads)
	kit.deferred = defer_meshes
	kit.stepwise = stepwise
	kit.every_step = step_every
	masonry = PoiMasonry.new(kit)
	var builders: GDScript = _builders
	if builders == null:
		# read on a loader's thread when a world began to stand up (World._ready), or here
		if ResourceLoader.load_threaded_get_status(BUILDERS_PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			builders = ResourceLoader.load_threaded_get(BUILDERS_PATH) as GDScript
		if builders == null:
			builders = load(BUILDERS_PATH)
		_builders = builders
	if builders == null:
		Log.error("PoiDressing", "%s: the builders did not load from %s" % [poi_id, BUILDERS_PATH])
		finished = true
		return
	if stepwise:
		set_process(true)
	# stepwise, the frame it is raised in holds none of the builder: it goes on in a later one
	await kit.step()
	await builders.build(self)
	if kind == "waterfall" and not far:
		# a fall no river draws: its water drawn as the rivers' falls are, over the dressing's rock
		RiverFalls.dress_place(self)
	if not far and not ward.is_empty():
		Wards.add(self, world_position, float(ward.get("radius_m", 8.0)), ward.get("keeps_off", []))
	if wants_hearthstone and not far and hearthstones().is_empty():
		# a builder that did not find a better place for the stone gets the plain one: at the
		# pad's centre, off the exact middle so nothing spawning there stands inside it
		var g := kit.grain()
		kit.hearthstone(kit.on_ground(g.x * 3.0, g.y * 3.0), PoiKit.yaw_of(g) + PI, poi_id, display_name)
	kit.end_steps()
	_start_meshes()
	finished = true
	set_process(false)
	if stepwise and raise_key != "":
		var st: Array = WorldPois.raise_ms.get(raise_key, [0, 0.0, 0.0])
		var ms := kit.build_us / 1000.0
		WorldPois.raise_ms[raise_key] = [int(st[0]), snappedf(float(st[1]) + ms, 0.1), snappedf(maxf(float(st[2]), ms), 0.1)]
	built_all.emit()


## A stepwise build goes on when this frame's budget has room, or when no place has gone on this
## frame (PoiKit.stepped_frame), so the builds waiting share the budget and one always moves.
func _process(_delta: float) -> void:
	if not waiting:
		return
	var f := Engine.get_process_frames()
	if WorldPace.left_usec() <= 0 and PoiKit.stepped_frame == f:
		return
	waiting = false
	PoiKit.stepped_frame = f
	resumed.emit()


## The masonry the builder left to be made (PoiKit.pending), made on a worker thread: the surface
## tools are this place's own and nothing else touches them until `meshes_ready` takes them.
func _start_meshes() -> void:
	if kit == null or kit.pending.is_empty():
		return
	var tools: Array = []
	var tangents: Array[bool] = []
	for pair in kit.pending:
		_mesh_insts.append(pair[0])
		tools.append(pair[1])
		# the obsidian's glass is drawn along its tangents (ObsidianGlass.commit)
		tangents.append((pair as Array).size() > 2 and bool(pair[2]))
	kit.pending = []
	_mesh_out.resize(tools.size())
	var out := _mesh_out
	_mesh_task = WorkerThreadPool.add_task(func() -> void:
		for i in tools.size():
			var st: SurfaceTool = tools[i]
			st.generate_normals()
			if tangents[i]:
				st.generate_tangents()
			out[i] = st.commit_to_arrays(), true, "wm_poi_masonry")


## Whether the meshes are all on (at once for a place that made them itself); gives the finished
## ones to their MeshInstance3Ds on the main thread when the worker is done.
func meshes_ready() -> bool:
	if not finished:
		return false
	if _mesh_task < 0:
		return true
	if not WorkerThreadPool.is_task_completed(_mesh_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_mesh_task)
	_mesh_task = -1
	for i in _mesh_insts.size():
		var mi: MeshInstance3D = _mesh_insts[i]
		var arrays: Variant = _mesh_out[i]
		if not is_instance_valid(mi):
			continue
		var verts: Variant = (arrays as Array)[Mesh.ARRAY_VERTEX] if arrays is Array and not (arrays as Array).is_empty() else null
		if verts == null or (verts as PackedVector3Array).is_empty():
			# nothing was laid in it: made at once, no mesh and no node would have stood
			mi.queue_free()
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = mesh
	_mesh_insts.clear()
	_mesh_out = []
	return true


func _exit_tree() -> void:
	# a place unloaded while its meshes are made: the worker is waited for, not left holding it
	if _mesh_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_mesh_task)
		_mesh_task = -1


# --- what got built, for the tests and the tools ------------------------------------------------

func mesh_count() -> int:
	var n := 0
	for node in find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			n += 1
	for node in find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.instance_count > 0:
			n += 1
	return n


func body_count() -> int:
	var n := 0
	for node in find_children("*", "StaticBody3D", true, false):
		if node is Hearthstone:
			continue
		if not (node as Node).find_children("*", "CollisionShape3D", true, false).is_empty():
			n += 1
	return n


func hearthstones() -> Array:
	return find_children("*", "Hearthstone", true, false)


## Real lights standing in this dressing. None, now: its fires and lamps are sources for
## NightLights, which lights the nearest of them from one pool (`light_sources()` lists them).
func lights() -> Array:
	return find_children("*", "OmniLight3D", true, false)


## The fires and lamps this dressing registered with NightLights: [position, kind, colour,
## energy, range] each.
func light_sources() -> Array:
	return NightLights.sources_of(self)


## A flat description of everything standing here, for comparing two raisings of one POI.
## A node Godot had to name itself (`@Node3D@1034`) carries a counter that is never the same
## twice, so those are described by class alone; what is compared is what stands where.
func signature() -> Array:
	var out: Array = []
	for node in find_children("*", "", true, false):
		if node is Node3D:
			var n3 := node as Node3D
			var label := n3.get_class() if n3.name.begins_with("@") else str(n3.name)
			out.append("%s@%s" % [label, str(n3.position.snapped(Vector3.ONE * 0.001))])
	# its fires and lamps stand here too, though they are sources for NightLights and no longer
	# nodes of their own
	for s in light_sources():
		out.append("light@%s" % str(to_local(s[0]).snapped(Vector3.ONE * 0.001)))
	return out


# --- where somebody is set down -------------------------------------------------------------------

## The names of the dressing's own water, which is no ground to set anybody down on.
const WATER_NODES := ["Pool", "TidePool", "Basin", "Stream", "Spring", "TroughWater", "CutWater", "Fall", "Glass",
		"Sheet"]
## A body set down is a capsule this wide and tall.
const ARRIVAL_RADIUS_M := 0.35
const ARRIVAL_HEIGHT_M := 1.8

var _arrival := Vector3.INF


## Where somebody arriving here is set down (fast travel, a Hearthstone's return, a quest's set-down,
## the console's `tp`), in this node's space: on open, dry ground clear of everything the dressing
## stood up, as near the middle as that allows, on the road's side where there is one. A place's
## middle is often inside what stands there (Rudd Mill's masonry, the Glass Bridge's) or in its
## water (the Three Sisters' plunge pool, under Ruddale Bridge's deck). The same every time, since
## the dressing is.
func arrival() -> Vector3:
	if _arrival != Vector3.INF:
		return _arrival
	if kit == null:
		return Vector3.ZERO
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var solids: Array[AABB] = []
	var floors: Array = []   # [PackedVector3Array faces] of what can be stood on (the brow, a bank)
	for cs_v in find_children("*", "CollisionShape3D", true, false):
		var cs := cs_v as CollisionShape3D
		if cs.shape == null or cs.disabled:
			continue
		var xf := (inv * cs.global_transform) if is_inside_tree() else _local_of(cs)
		# ground the dressing laid to be walked on (a brow, a bank, a clearing: the masonry's own
		# trimesh with earth underfoot) is a floor; any other trimesh is a thing (a tent, a rib)
		var floor_like := cs.shape is ConcavePolygonShape3D and str(cs.get_meta(PoiKit.SURFACE_META, "")) == "dirt"
		if floor_like:
			var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
			var out := PackedVector3Array()
			out.resize(faces.size())
			for i in faces.size():
				out[i] = xf * faces[i]
			floors.append(out)
			continue
		var mesh := cs.shape.get_debug_mesh()
		if mesh != null:
			solids.append(xf * mesh.get_aabb())
	var wet: Array[AABB] = []
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for w in WATER_NODES:
			if str(mi.name).begins_with(str(w)) and mi.mesh != null:
				wet.append((inv * mi.global_transform if is_inside_tree() else mi.transform) * mi.mesh.get_aabb())
				break
	# toward the road, else away from the hill, else the grain
	var first := PoiKit.yaw_of(kit.grain())
	var road := kit.road_direction(80.0)
	var toward := Vector2.ZERO
	if road != Vector2.ZERO:
		var here := Vector2(kit.origin.x, kit.origin.z)
		var best := INF
		for line_v in kit.roads:
			if typeof(line_v) != TYPE_ARRAY:
				continue
			for p_v in (line_v as Array):
				var p := Vector2(float(p_v[0]), float(p_v[1]))
				var dist := p.distance_to(here)
				if dist < best and dist > 0.5:
					best = dist
					toward = (p - here).normalized()
	elif kit.downhill() != Vector2.ZERO:
		toward = kit.downhill()
	if toward != Vector2.ZERO:
		first = PoiKit.yaw_of(toward)
	var r := 0.0
	while r <= pad_radius + 40.0:
		var steps := 1 if r == 0.0 else 24
		for i in steps:
			# from the first bearing, alternately either side of it
			var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)
			var a := first + TAU * float(k) / float(steps)
			var p := Vector2(sin(a), cos(a)) * r
			var at := _stand_at(p, floors)
			if _open(at, solids, wet):
				_arrival = at
				return _arrival
		r += 1.5
	# out on the water (the Bell Field's buoys): the nearest dry shore, however far
	r = pad_radius + 40.0
	while r <= 400.0:
		for i in 48:
			var a := TAU * float(i) / 48.0
			var at := kit.on_ground(sin(a) * r, cos(a) * r)
			if not kit.in_water(at + Vector3(0.0, 0.3, 0.0)):
				_arrival = at
				return _arrival
		r += 4.0
	_arrival = kit.on_ground(0.0, 0.0)
	return _arrival


## The height a body stands at, local xz `p`: the ground, or what the dressing laid over it to be
## stood on (a brow, a bank) where that is higher.
func _stand_at(p: Vector2, floors: Array) -> Vector3:
	var at := kit.on_ground(p.x, p.y)
	var from := Vector3(p.x, at.y + 60.0, p.y)
	for faces_v in floors:
		var faces: PackedVector3Array = faces_v
		var i := 0
		while i + 2 < faces.size():
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
			if hit != null and (hit as Vector3).y > at.y:
				at.y = (hit as Vector3).y
			i += 3
	return at


func _open(at: Vector3, solids: Array[AABB], wet: Array[AABB]) -> bool:
	if kit.provider != null and kit.in_water(at + Vector3(0.0, 0.3, 0.0)):
		return false
	var body := AABB(at + Vector3(-ARRIVAL_RADIUS_M, 0.08, -ARRIVAL_RADIUS_M),
			Vector3(ARRIVAL_RADIUS_M * 2.0, ARRIVAL_HEIGHT_M, ARRIVAL_RADIUS_M * 2.0))
	for box in solids:
		if box.intersects(body):
			return false
	for w in wet:
		if absf(at.x - w.get_center().x) <= w.size.x * 0.5 + ARRIVAL_RADIUS_M \
				and absf(at.z - w.get_center().z) <= w.size.z * 0.5 + ARRIVAL_RADIUS_M:
			return false
	return true


func _local_of(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != self:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Where somebody is set down at the POI `id`, in the world: the arrival of its dressing where it
## stands, or of one raised for the asking and taken down again. INF where there is no such POI.
## `terrain` and `roads` are the ground and roads a dressing raised for the asking is laid on
## (the running world's by default: raised on no ground, it knew no water and no slope).
static func arrival_for(id: String, terrain: TerrainProvider = null, roads: Array = []) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector3.INF
	for n in tree.get_nodes_in_group(GROUP):
		var standing := n as PoiDressing
		if standing != null and standing.poi_id == id and not standing.far and standing.finished:
			return standing.to_global(standing.arrival())
	var entry: Dictionary = TravelPlaces.entries().get(id, {})
	var def := ContentDB.get_or_empty(id)
	if entry.is_empty() or not dressable(id, def):
		return Vector3.INF
	if terrain == null:
		terrain = World.terrain()
	if roads.is_empty():
		roads = WorldPois.roads_from_disk()
	var d := PoiDressing.raise(entry, def, false, terrain, roads)
	d.position = d.world_position
	var host := Node3D.new()
	host.name = "ArrivalScratch"
	tree.root.add_child(host)
	host.add_child(d)
	var at := d.to_global(d.arrival())
	tree.root.remove_child(host)
	host.free()
	return at
