class_name TerrainOccluder
extends OccluderInstance3D
## The land as an occluder (Godot's occlusion culling): a coarse sheet a little under the ground, so
## what stands behind a hill -- a town over the ridge, a wood in the next dale, the far ring's
## trees -- is not drawn. Nothing else in the world is an occluder: the towns' houses are merged a
## mesh per surface for the whole place (Settlement), so a house hides nothing that could be left
## out on its own.
##
## The sheet is the runtime height map (8 m) taken every STEP texels (64 m), each vertex the lowest
## ground within half a step of it and MARGIN_M under that, so it stays under the ground it stands
## for: a vertex is never above any ground near it, and the triangles between them dip into the
## dales rather than bridge them. It is built once, on a worker thread, when the world stands up;
## the culling itself is the engine's (Embree, on the CPU), run only while the setting is on
## ("Hide what hills hide", Graphics: `occlusion`).

const STEP := 8
const MARGIN_M := 2.0

var _task := -1
var _arrays: Array = []
var _provider: TerrainProvider = null


## The sheet over a height map: [vertices, indices] for an ArrayOccluder3D. Pure, for the tests.
## `heights` is `grid` x `grid`, row by row (z), texel (0, 0) at `origin`, `spacing` metres apart.
static func build_arrays(heights: PackedFloat32Array, grid: int, spacing: float, origin: Vector2,
		step := STEP, margin := MARGIN_M) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	if grid < 2 or heights.size() < grid * grid or step < 1:
		return [verts, idx]
	var n := int(floor(float(grid - 1) / float(step))) + 1
	var reach := int(ceil(step * 0.5))
	for vi in n:
		var gz := mini(vi * step, grid - 1)
		for vj in n:
			var gx := mini(vj * step, grid - 1)
			var low := INF
			for z in range(maxi(gz - reach, 0), mini(gz + reach, grid - 1) + 1):
				var row := z * grid
				for x in range(maxi(gx - reach, 0), mini(gx + reach, grid - 1) + 1):
					low = minf(low, heights[row + x])
			verts.append(Vector3(origin.x + gx * spacing, low - margin, origin.y + gz * spacing))
	for vi in n - 1:
		for vj in n - 1:
			var a := vi * n + vj
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	return [verts, idx]


## Builds the sheet when the setting is on, now or when it is turned on: nothing is built, and
## the engine keeps no occluder, for a player who leaves it off.
func watch(provider: TerrainProvider) -> void:
	_provider = provider
	if bool(Settings.get_value("graphics", "occlusion", false)):
		build_from(provider)
	Settings.changed.connect(_on_setting_changed)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "graphics" and key == "occlusion" and bool(value) and occluder == null and _task < 0 \
			and _provider != null and is_instance_valid(_provider):
		build_from(_provider)


## Builds the sheet from the provider's height map on a worker thread; it is set when done.
func build_from(provider: TerrainProvider) -> void:
	if provider == null or provider._heights.is_empty():
		return
	name = "TerrainOccluder"
	var heights := provider._heights
	var grid := provider._grid
	var spacing := provider._spacing
	var origin := provider._height_origin
	# the task fills an array of its own, not this node: a world torn down mid-build frees the node
	var out: Array = []
	_arrays = out
	_task = WorkerThreadPool.add_task(func() -> void:
		out.append_array(TerrainOccluder.build_arrays(heights, grid, spacing, origin)), false, "terrain occluder")
	set_process(true)


func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	set_process(false)
	if _arrays.size() == 2 and not (_arrays[0] as PackedVector3Array).is_empty():
		var occ := ArrayOccluder3D.new()
		occ.set_arrays(_arrays[0], _arrays[1])
		occluder = occ
		Log.info("TerrainOccluder", "the land's occluder: %d vertices, %d triangles" % [
				(_arrays[0] as PackedVector3Array).size(), int((_arrays[1] as PackedInt32Array).size() / 3.0)])
	_arrays = []


func _exit_tree() -> void:
	# a world torn down while it builds: the task is left to finish and collected (never waited for)
	if _task >= 0:
		ThreadedLoads.after_task(_task, false, _arrays)
		_task = -1
