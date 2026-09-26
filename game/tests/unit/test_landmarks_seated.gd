extends TestCase
## Every landmark the world stands up (a cell's `scenes`) stands on the ground: the lowest point of
## its model no more than half a metre over the ground under it (or the bed under the water there);
## sunk into it is allowed. The cartographer's
## batch 4 ground shots had the Drowned Nave's tower as a grey box in the sky from the marsh; it is
## seated (its foot at the ground's 4.08 m), and what hangs in that frame is the model's own mass,
## forty metres wide from 50 to 80 m up on a shaft twenty wide, with the shaft behind the trees.
## A carved landmark (the Choir's colossi, the Nave) runs on under its ground line and says how far
## (`buried_m`, set down by WorldStreamer.seated_depth); it is seated when the ground everywhere
## under its body, out to the rubble, stands over its buried foot -- no edge of it shows a gap or a
## plinth on a slope (the first colossi's blue drum stood out of the ash on its downhill side).
## These read the built world; when it is missing they skip.

const CELLS := "res://world/generated/cells"
const SEATED_M := 0.5


func test_every_landmark_stands_on_the_ground() -> void:
	if not DirAccess.dir_exists_absolute(CELLS):
		return
	var provider := TerrainProvider.new()
	provider.load_data()
	var checked := 0
	var off: Array[String] = []
	for file in DirAccess.get_files_at(CELLS):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CELLS, file]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for entry_v in (parsed as Dictionary).get("scenes", []):
			if typeof(entry_v) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_v
			var path := str(entry.get("scene", ""))
			if not path.contains("/models/landmarks/"):
				continue
			var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
			var at := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			var b: Dictionary = PoiKit.meta(path).get("bounds", {})
			var lo: Array = b.get("min", [0.0, 0.0, 0.0])
			var hi: Array = b.get("max", [0.0, 0.0, 0.0])
			var sunk := WorldStreamer.seated_depth(path)
			var foot := at.y + float(lo[1]) - sunk
			# the terrain's height is its bed where there is water over it, which is where a drowned
			# thing stands
			var ground := provider.get_height(at.x, at.z)
			# standing on it or sunk into it, never over it: a colossus half-buried in the ash is meant
			if foot - ground > SEATED_M:
				off.append("%s: foot at %.2f, the ground %.2f" % [path.get_file().get_basename(), foot, ground])
			if sunk > 0.0:
				# round the body: halfway and three-quarters out to its bounds, turned as it stands
				var basis := Basis(Vector3.UP, deg_to_rad(float(entry.get("yaw", 0.0))))
				for i in 16:
					var a := TAU * float(i) / 16.0
					for f in [0.5, 0.75]:
						var local := Vector3(lerpf(float(lo[0]), float(hi[0]), 0.5 + 0.5 * f * cos(a)), 0.0,
								lerpf(float(lo[2]), float(hi[2]), 0.5 + 0.5 * f * sin(a)))
						var p := at + basis * local
						var g := provider.get_height(p.x, p.z)
						if foot - g > SEATED_M:
							off.append("%s: its buried foot (%.2f) shows over the ground at %.0f, %.0f (%.2f)"
									% [path.get_file().get_basename(), foot, p.x, p.z, g])
			checked += 1
	provider.free()
	assert_gt(checked, 5, "the landmarks were found (%d)" % checked)
	assert_true(off.is_empty(), "landmarks off the ground: %s" % ", ".join(off))
