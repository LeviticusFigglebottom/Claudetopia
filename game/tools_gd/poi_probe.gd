extends Node
## The places of a region raised one at a time and measured: what each is, and whether it stands.
##
##   godot --headless --path game res://tools_gd/poi_probe.tscn -- --out=<abs file.json> \
##       [--region=hearthvale] [--only=<id or short name>,...] [--unbuilt] [--preview-pois=a,b]
##
## tools/world/region_audit.py runs it (`--probe`) and reads what it writes; so does
## tools/world/region_check.py for the places a region's author has written since the last world
## build (docs/WORLD_LIFE.md). It stands the world up headless, which lays a pad for every POI the
## build has not seen (PoiPreview), then raises each point of interest of the region on its own,
## as the streamer would, beside the world rather than in a cell: no scatter streams round it, so
## what is measured is the place itself. For each it writes:
##
## * `footprint`: the box of everything drawn (x and z extent, height, and how far out from the
##   middle it reaches), in metres;
## * `pieces`, `draws`, `primitives`: meshes, their surfaces (a draw call each, before shadows) and
##   triangles, a multimesh's by its instances;
## * `interactables` by kind (the "interactable" group: Hearthstone, WorldContainer, WorldItem,
##   Readable, Door, Npc ...), `lights` (NightLights sources), `bodies` (solid pieces);
## * `seat`: tools_gd/seat_audit.gd over its pieces (floating, buried, sunk, on_road, overlap,
##   lamp_unhung ...): each finding with where it is; headless, so a multimesh's rows are not
##   looked at (the seat audit says why);
## * `embankment_m`: how far the ground a pace past the pad's reach lies from the pad's level, the
##   cut or fill a pad makes on a slope; `raise_ms`.

const WORLD_SCENE := "res://world/world.tscn"
const SEAT_AUDIT := preload("res://tools_gd/seat_audit.gd")
## How long one place may take to finish raising, in real seconds.
const RAISE_LIMIT_S := 30.0
## Findings kept per place in the file (the counts are all kept).
const FINDINGS_KEPT := 12

var out_path := ""
var region := ""
var only: Array[String] = []
var unbuilt_only := false
var _w: World = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--region="):
			var r := a.substr(9).strip_edges()
			region = r if r.contains(":") else "core:region/%s" % r
		elif a.begins_with("--only="):
			for s in a.substr(7).split(",", false):
				only.append(s.strip_edges())
		elif a == "--unbuilt":
			unbuilt_only = true
	Settings.persist = false
	var code: int = await run()
	get_tree().quit(code)


func run() -> int:
	if out_path.is_empty():
		push_error("poi_probe: --out=<file.json> is needed")
		return 2
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	await get_tree().process_frame          # the root is still adding this scene in _ready
	# (`--preview-pois=a,b` stands those where their defs say, whatever the build has: PoiPreview)
	_w = (load(WORLD_SCENE) as PackedScene).instantiate() as World
	get_tree().root.add_child(_w)
	await _w.world_ready
	if _w.streamer != null:
		# nothing streams round the spawn: the places are raised here, on their own
		_w.streamer.process_mode = Node.PROCESS_MODE_DISABLED
	var dressings := _w.get_node_or_null("Pois")
	if dressings != null:
		dressings.process_mode = Node.PROCESS_MODE_DISABLED
	var roads := WorldPois.roads_from_disk()
	PoiKit.road_grid(roads)
	var audit = SEAT_AUDIT.new(_w)
	var host := Node3D.new()
	host.name = "PoiProbe"
	_w.add_child(host)
	var rows: Array = []
	var picked := _picked(_w.pois())
	print("POIPROBE: %d places to raise%s" % [picked.size(), " in %s" % region if region != "" else ""])
	for item: Dictionary in picked:
		rows.append(await _measure(item["entry"], item["def"], host, roads, audit))
		print("POIPROBE %d/%d %s" % [rows.size(), picked.size(), item["def"]["id"]])
	var out := {"region": region, "built_at": str(_w.provider.manifest.get("built_at", "")),
		"terrain": _w.terrain_mode, "pois": rows}
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("poi_probe: cannot write %s" % out_path)
		return 1
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	print("POIPROBE: wrote %s" % out_path)
	return 0


## The entries to raise, each with its def: the region's POIs (or those asked for by `--only`,
## or those the build has not seen with `--unbuilt`).
func _picked(pois: Array) -> Array:
	var out: Array = []
	for e_v in pois:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		var id := str(e.get("place_id", ""))
		if not id.begins_with("core:poi/") and Ids.type_of(id) != "poi":
			continue
		var def := ContentDB.get_or_empty(id)
		if def.is_empty() or not PoiDressing.dressable(id, def):
			continue
		if region != "" and str(def.get("region", "")) != region:
			continue
		if not only.is_empty() and not (only.has(id) or only.has(Ids.name_of(id))):
			continue
		if unbuilt_only and not bool(e.get("preview", false)):
			continue
		out.append({"entry": e, "def": def})
	return out


func _measure(entry: Dictionary, def: Dictionary, host: Node3D, roads: Array, audit) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var d := PoiDressing.raise(entry, def, false, _w.provider, roads)
	host.add_child(d)
	var until := Time.get_ticks_msec() + int(RAISE_LIMIT_S * 1000.0)
	while not d.meshes_ready() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	await get_tree().process_frame
	var raise_ms := Time.get_ticks_msec() - t0
	var centre := d.world_position
	var box := AABB()
	var have_box := false
	var reach := 0.0
	var pieces := 0
	var draws := 0
	var prims := 0
	for n in d.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or _skipped(g):
			continue
		var mesh: Mesh = null
		var count := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
			count = (g as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null or count <= 0:
			continue
		pieces += 1
		draws += mesh.get_surface_count()
		prims += _triangles(mesh) * count
		var b: AABB = g.global_transform * g.get_aabb()
		if g is MultiMeshInstance3D:
			b = g.global_transform * (g as MultiMeshInstance3D).multimesh.get_aabb()
		box = b if not have_box else box.merge(b)
		have_box = true
		for cx in [b.position.x, b.end.x]:
			for cz in [b.position.z, b.end.z]:
				reach = maxf(reach, Vector2(float(cx) - centre.x, float(cz) - centre.z).length())
	var kinds := {}
	for n in get_tree().get_nodes_in_group("interactable"):
		if d.is_ancestor_of(n):
			var k := _kind_of(n)
			kinds[k] = int(kinds.get(k, 0)) + 1
	var r := float(entry.get("radius_flat_m", 25.0))
	var found: Array = audit.audit_node(d, Rect2(centre.x - r * 3.0, centre.z - r * 3.0, r * 6.0, r * 6.0))
	var seat := {}
	for f: Dictionary in found:
		seat[str(f["check"])] = int(seat.get(str(f["check"]), 0)) + 1
	var row := {
		"id": str(def.get("id", "")), "kind": d.kind, "preview": bool(entry.get("preview", false)),
		"pos": [snappedf(centre.x, 0.1), snappedf(centre.y, 0.01), snappedf(centre.z, 0.1)],
		"radius_flat_m": r,
		"footprint": {"x": snappedf(box.size.x, 0.1), "z": snappedf(box.size.z, 0.1), "height": snappedf(box.size.y, 0.1),
			"reach": snappedf(reach, 0.1), "top": snappedf(box.end.y - centre.y, 0.1) if have_box else 0.0},
		"pieces": pieces, "draws": draws, "primitives": prims,
		"interactables": kinds, "lights": d.light_sources().size(), "bodies": d.body_count(),
		"hearthstones": d.hearthstones().size(),
		"seat": seat, "findings": found.slice(0, FINDINGS_KEPT),
		"embankment_m": snappedf(_embankment(entry, centre), 0.1),
		"raise_ms": raise_ms, "finished": d.finished,
	}
	host.remove_child(d)
	d.queue_free()
	await get_tree().process_frame
	return row


## The furthest the ground just past a pad's reach lies from the pad's level: the cut or the fill
## its skirt makes on a slope.
func _embankment(entry: Dictionary, centre: Vector3) -> float:
	var r := float(entry.get("radius_flat_m", 25.0))
	var reach := float(entry.get("radius_level_m", r * 0.7)) + PoiPreview.PAD_SKIRT * r
	var worst := 0.0
	for i in 16:
		var a := TAU * float(i) / 16.0
		var h := _w.provider.get_height(centre.x + cos(a) * (reach + 4.0), centre.z + sin(a) * (reach + 4.0))
		worst = maxf(worst, absf(h - centre.y))
	return worst


func _skipped(n: Node) -> bool:
	var p := n
	while p != null:
		var nm := str(p.name)
		if nm == "Encounters" or nm == "Livestock" or nm.begins_with("Npc") or p is CharacterBody3D:
			return true
		if p is PoiDressing:
			return false
		p = p.get_parent()
	return false


static func _triangles(mesh: Mesh) -> int:
	var n := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			var idx := am.surface_get_array_index_len(s)
			n += int((idx if idx > 0 else am.surface_get_array_len(s)) / 3.0)
		return n
	return int(mesh.get_faces().size() / 3.0)


static func _kind_of(n: Node) -> String:
	var s: Script = n.get_script()
	while s != null:
		var g := s.get_global_name()
		if g != &"":
			return str(g)
		s = s.get_base_script()
	return n.get_class()
