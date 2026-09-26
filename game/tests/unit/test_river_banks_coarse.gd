extends TestCase
## A river's water is lowered to the lower of its banks where something laid over the channel
## stands under its surface (WaterSurface._river_mesh). Read from the coarse map alone (no
## Terrain3D: a test, a tool, the fallback ground), the bank beside the channel was a texel that
## averages the channel in, and the Larkbourne sank a median 0.42 m into a trench of its own
## making. Held here against the 2 m ground a world build leaves (world/generated/heights.r32,
## untracked): where the fine ground lowers a river's water by nothing, the coarse map must not
## either. On the w4096d world: 2,026 such points; the old reading lowered 58% of them by more than
## 5 cm (median 7 cm, one in twenty by 34 cm), the reading a texel further out 5.8% (median 0, one in
## twenty by 6 cm). Without the 2 m heights on disk there is nothing to hold it to, and it says so.

const FINE := "res://world/generated/heights.r32"


## The 2 m ground as Terrain3D draws it, from the build's own heights.
class FineGround:
	extends TerrainProvider
	var fine := PackedFloat32Array()
	var n := 4096
	var sp := 2.0

	func has_terrain() -> bool:
		return true

	func get_height(x: float, z: float) -> float:
		var fx := clampf((x - origin.x) / sp, 0.0, float(n) - 1.001)
		var fz := clampf((z - origin.y) / sp, 0.0, float(n) - 1.001)
		var i := int(fz)
		var j := int(fx)
		var tx := fx - float(j)
		var tz := fz - float(i)
		return lerpf(lerpf(fine[i * n + j], fine[i * n + j + 1], tx), lerpf(fine[(i + 1) * n + j], fine[(i + 1) * n + j + 1], tx), tz)


func _ribbon_ys(ws: WaterSurface, entry: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var mesh := ws._river_mesh(entry)
	if mesh == null:
		return out
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in int(verts.size() / 2.0):
		out.append(verts[i * 2].y)
	return out


func test_the_coarse_map_sinks_no_river_the_fine_ground_does_not() -> void:
	if not FileAccess.file_exists(FINE):
		print("  (no 2 m heights on disk: the coarse banks are not checked against them)")
		return
	var coarse := TerrainProvider.new()
	var fine := FineGround.new()
	if not coarse.load_data() or not fine.load_data():
		coarse.free()
		fine.free()
		return
	fine.n = int(fine.manifest.get("grid", 4096))
	fine.sp = float(fine.manifest.get("spacing_m", 2.0))
	fine.fine = FileAccess.get_file_as_bytes(FINE).to_float32_array()
	if fine.fine.size() != fine.n * fine.n:
		coarse.free()
		fine.free()
		return
	assert_false(coarse.has_terrain(), "the coarse map alone")
	var rivers: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/rivers.json"))
	var wc := WaterSurface.new()
	wc.provider = coarse
	var wf := WaterSurface.new()
	wf.provider = fine
	var level := 0
	var sunk := 0
	var excess: Array[float] = []
	for entry in rivers:
		var surf: Array = entry.get("surface_m", [])
		if surf.size() != (entry.get("points", []) as Array).size() or surf.size() < 10:
			continue
		var yc := _ribbon_ys(wc, entry)
		var yf := _ribbon_ys(wf, entry)
		if yc.size() != surf.size() or yf.size() != surf.size():
			continue
		for i in surf.size():
			if float(surf[i]) - yf[i] > 0.01:
				continue
			level += 1
			var d := float(surf[i]) - yc[i]
			excess.append(d)
			if d > 0.05:
				sunk += 1
	assert_gt(level, 500, "points the fine ground lowers nothing (%d)" % level)
	excess.sort()
	var p95 := excess[int(excess.size() * 0.95)] if not excess.is_empty() else 0.0
	assert_true(float(sunk) / float(maxi(level, 1)) < 0.08,
			"the coarse map lowers %d of %d of them by more than 5 cm" % [sunk, level])
	assert_true(p95 < 0.1, "one in twenty by %.2f m" % p95)
	wc.free()
	wf.free()
	coarse.free()
	fine.free()
