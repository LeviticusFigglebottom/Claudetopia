class_name GrassInstancer
extends RefCounted
## A prototype, off by default: one region's grass and small ground cover drawn by Terrain3D's own
## instancer instead of the streamer's MultiMeshes (graphics setting `grass_instancer`).
##
## The streamer draws a cell's herbs as one MultiMesh an asset, built when the cell streams in
## within its near ring and culled whole by the cell's 256 m box. Terrain3D 1.0.2's instancer keeps
## every instance of the region at once, in 32 m cells with a MultiMesh a mesh, level and cell, and
## culls them by its own visibility ranges. Which is cheaper -- draw calls, primitives, the main and
## render threads, memory, the time a world takes to load -- is what this is for measuring
## (PROGRESS, "Ground cover through Terrain3D's instancer"); the whole world is not moved to it.
##
## The rows are the built world's own (game/world/generated/cells/*.json), read as the streamer
## reads them, so the world builder's pads, sightline clearings, roads and seat audits hold as they
## do for the streamer: nothing is placed that the cells do not place. The ground cover setting
## thins them the way the streamer does, and setting 2 doubles every row (a second tuft turned on the
## same spot), the denser cover the instancer is meant to make affordable.
##
## `-- --grass-instancer=0|1|2` sets it for one run (the benchmark, captures).

## The region it is tried on: the most ground cover in the world (1.6 M rows in 195 cells).
const REGION := "core:region/hearthvale"
const ARG := "--grass-instancer="
const CELLS := "res://world/generated/cells"
## Terrain3D's instancer cell, for the record (it is the extension's, not set here).
const INSTANCER_CELL_M := 32.0

## True while a world's instancer holds the region's ground cover: the streamer leaves those rows
## to it. Set when the world decides to use it, before the first cell streams in.
static var active := false
## What the last population cost and held, for the measurement (`stats()`).
static var last := {}


## 0 off, 1 on, 2 on with twice the cover: the run's argument, else the setting.
static func mode() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(ARG):
			return clampi(int(arg.trim_prefix(ARG)), 0, 2)
	return clampi(int(Settings.get_value("graphics", "grass_instancer", 0)), 0, 2)


## Whether the streamer should leave this cell's asset to the instancer.
static func takes(region: String, asset_path: String) -> bool:
	return active and region == REGION and WorldStreamer.asset_kind(asset_path) == "herb"


## The region's herb rows by asset, read from the cell files: {asset path: [rows]}. Run on a worker
## thread; it touches no node.
static func read_rows(cells_dir: String = CELLS) -> Dictionary:
	var out: Dictionary = {}
	for f in DirAccess.get_files_at(cells_dir):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [cells_dir, file])
		if text.is_empty() or not text.contains(REGION):
			continue
		var data: Variant = JSON.parse_string(text)
		if not data is Dictionary or str((data as Dictionary).get("region", "")) != REGION:
			continue
		var instances: Dictionary = (data as Dictionary).get("instances", {})
		for path_v in instances:
			var path := str(path_v)
			if WorldStreamer.asset_kind(path) != "herb":
				continue
			if not out.has(path):
				out[path] = []
			(out[path] as Array).append_array(instances[path_v])
	return out


## Hands the rows to `terrain`'s instancer: one Terrain3DMeshAsset an asset, drawn to the streamer's
## herb range times `view_range`, no shadows (the streamer casts none from grass either). `density`
## is the ground cover setting; `doubled` adds a second tuft a row. Returns the mesh assets made.
static func populate(terrain: Node, rows_by_asset: Dictionary, view_range: float, density: float,
		doubled: bool) -> int:
	var t0 := Time.get_ticks_usec()
	var assets: Object = terrain.get("assets")
	var instancer: Object = terrain.get("instancer")
	if assets == null or instancer == null:
		return 0
	var reach := float(WorldStreamer.VIEW_RANGE["herb"]) * view_range
	var next_id := int(assets.call("get_mesh_count"))
	var made := 0
	var placed := 0
	var paths := rows_by_asset.keys()
	paths.sort()
	for path_v in paths:
		var path := str(path_v)
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var ma: Resource = ClassDB.instantiate("Terrain3DMeshAsset")
		ma.set("name", path.get_file().get_basename())
		ma.set("scene_file", packed)
		ma.set("cast_shadows", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		# one level: the streamer draws a herb at one level too, to its range
		ma.set("last_lod", 0)
		ma.set("lod0_range", reach)
		ma.set("fade_margin", reach * 0.15)
		assets.call("set_mesh_asset", next_id, ma)
		var rows: Array = rows_by_asset[path_v]
		var keep := int(ceil(float(rows.size()) * clampf(density, 0.0, 1.0)))
		var step := float(rows.size()) / float(maxi(keep, 1))
		var xforms: Array[Transform3D] = []
		var colours := PackedColorArray()
		for i in keep:
			var row: Array = rows[int(floor(float(i) * step))]
			var t := WorldStreamer.instance_transform(row, Vector3.ZERO)
			var c := WorldStreamer.instance_tint(row)
			xforms.append(t)
			colours.append(c)
			if doubled:
				# the second tuft on the same spot, turned a third of the way round
				xforms.append(Transform3D(t.basis.rotated(Vector3.UP, 2.09), t.origin))
				colours.append(c)
		instancer.call("add_transforms", next_id, xforms, colours, false)
		placed += xforms.size()
		next_id += 1
		made += 1
	var t1 := Time.get_ticks_usec()
	instancer.call("update_mmis", true)
	last = {"meshes": made, "instances": placed, "add_ms": (t1 - t0) / 1000.0,
			"update_mmis_ms": (Time.get_ticks_usec() - t1) / 1000.0, "reach_m": reach}
	return made


## The MultiMeshes the instancer made, and the instances in them (what it costs in nodes and memory).
static func census(terrain: Node) -> Dictionary:
	var mmis := 0
	var instances := 0
	var stack: Array[Node] = [terrain]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(true):
			stack.append(c)
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			mmis += 1
			instances += (n as MultiMeshInstance3D).multimesh.instance_count
	return {"mmi_nodes": mmis, "mmi_instances": instances}
