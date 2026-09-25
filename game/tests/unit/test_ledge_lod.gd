extends TestCase
## The crags and sea cliffs are built of the forge's cliff ledges, tens of thousands of them to a
## wall. They are affordable only because the scatter draws each one down its LOD ladder
## (world/scatter_lod.gd): whole near, LOD1 past its near line, LOD2 past its far one. Every ledge
## the world builder places, and every boulder that covers a run's end or seats a group, keeps
## that ladder.

const ROCKS := "res://assets/models/rocks"


func _ledges_and_boulders() -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_directories_at(ROCKS):
		if name.contains("_cliff_ledge_") or name.contains("_boulder_"):
			out.append("%s/%s/%s.glb" % [ROCKS, name, name])
	return out


func test_every_ledge_and_boulder_is_drawn_down_three_levels() -> void:
	var assets := _ledges_and_boulders()
	assert_gt(assets.size(), 20, "the regions' ledges and boulders")
	var ledges := 0
	for path in assets:
		var packed := load(path) as PackedScene
		assert_true(packed != null, "%s loads" % path)
		if packed == null:
			continue
		var lad := ScatterLod._build_ladder(path, packed)
		assert_true(lad != null, "%s has a ladder" % path.get_file())
		if lad == null:
			continue
		assert_eq(lad.levels.size(), 3, "%s: whole, LOD1 and LOD2" % path.get_file())
		var tris: Array[int] = []
		for level in lad.levels:
			tris.append(ScatterLod._tri_count(level["solid"]))
		assert_true(tris[0] > tris[1] and tris[1] > tris[2],
				"%s: each level lighter than the last (%s)" % [path.get_file(), str(tris)])
		if path.contains("_cliff_ledge_"):
			ledges += 1
			assert_gt(tris[0], tris[2] * 5, "%s: LOD2 under a fifth of the whole" % path.get_file())
	assert_gt(ledges, 10, "every region's ledges")
