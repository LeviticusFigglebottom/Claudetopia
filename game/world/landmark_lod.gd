class_name LandmarkLod
extends RefCounted
## The distances a landmark model changes level at, by its own size, and changing outright.
##
## The GLB import gives every model the same level lines, 28 m and 75 m, with each level
## dissolving itself in and out across a margin (VISIBILITY_RANGE_FADE_SELF). For a crate that is
## right. For one of the Choir's colossi, 52 m tall, it put both lines inside a walk across its
## own shadow, and each dissolve drew the two levels as two half-dithered pictures of the same
## stone: the first playtest of the start saw the colossi turn semi-transparent as the player
## walked up to them, and whole again as they went past. An opaque landmark here is always
## wholly one level: its lines are its height times four and ten (as the trees' are), and a level
## switches outright, with a little hysteresis, where the next level is a close match anyway.

const NEAR_MIN := 28.0
const NEAR_PER_METRE := 4.0
const MID_MIN := 75.0
const MID_PER_METRE := 10.0
## Metres either side of a line a level holds on, so standing on it does not flicker.
const HYSTERESIS_SHARE := 0.03

## The level of a mesh by its name: `<model>`, `<model>_LOD1`, `<model>_LOD2`.
static func level_of(node_name: String) -> int:
	if node_name.ends_with("_LOD2"):
		return 2
	if node_name.ends_with("_LOD1"):
		return 1
	return 0


## The height the lines are sized by: the full mesh's top over the model's origin.
static func height_of(root: Node) -> float:
	var h := 0.0
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh != null and level_of(mi.name) == 0:
			h = maxf(h, mi.mesh.get_aabb().end.y * mi.scale.y)
	return h


## [begin, end] of each level for a model `height` tall (end 0: no end).
static func bands(height: float) -> Array:
	var near := maxf(NEAR_MIN, NEAR_PER_METRE * height)
	var mid := maxf(MID_MIN, MID_PER_METRE * height)
	return [[0.0, near], [near, mid], [mid, 0.0]]


## Sets every level of the landmark under `root` to its sized band, switching outright. Returns
## the height it sized them by.
static func apply(root: Node) -> float:
	var h := height_of(root)
	var b := bands(h)
	var levels := {}
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		levels[level_of(mi.name)] = true
	var last := 0
	for l in levels:
		last = maxi(last, int(l))
	for mi_v in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		var level := level_of(mi.name)
		var band: Array = b[level]
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.visibility_range_begin = float(band[0])
		mi.visibility_range_end = 0.0 if level == last else float(band[1])
		mi.visibility_range_begin_margin = float(band[0]) * HYSTERESIS_SHARE
		mi.visibility_range_end_margin = float(band[1]) * HYSTERESIS_SHARE
	return h
