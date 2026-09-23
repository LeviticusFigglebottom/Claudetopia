extends TestCase
## Crossing a region border. The region under the player was read only when the streamer
## crossed into a new cell, with no margin, so a walk along a cell edge lying on a border flipped
## the region -- and with it the light's six-second blend, the music and the name on screen -- at
## every step over the edge. A region now counts as entered only a margin inside it.

const GENERATED := "res://world/generated"

var provider: TerrainProvider = null


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/world_manifest.json" % GENERATED):
		return
	provider = TerrainProvider.new()
	provider.load_data()


## A point on a border between two land regions, walking east along a row of the region map:
## [the last point of the first region, its id, the first point of the next, its id].
func _a_border() -> Array:
	for z in range(-3000, 3001, 250):
		var prev := ""
		var prev_x := 0.0
		for x in range(-3500, 3501, 8):
			var id := provider.region_id_at(float(x), float(z))
			if id.is_empty():
				prev = ""
				continue
			if not prev.is_empty() and id != prev:
				# a clean border: land of the first region behind, of the second ahead
				if provider.region_id_at(float(x) + 60.0, float(z)) == id \
						and provider.region_id_at(prev_x - 60.0, float(z)) == prev:
					return [Vector3(prev_x, 0.0, float(z)), prev, Vector3(float(x), 0.0, float(z)), id]
			prev = id
			prev_x = float(x)
	return []


func test_a_border_is_crossed_only_a_margin_inside_the_new_region() -> void:
	if provider == null:
		return
	var border := _a_border()
	assert_false(border.is_empty(), "the region map has a land border somewhere")
	if border.is_empty():
		return
	var streamer := WorldStreamer.new()
	streamer.setup(provider, null)
	streamer._current_region = str(border[1])
	var first_step: Vector3 = border[2]
	var into: String = border[3]
	assert_false(streamer.region_entered_at(first_step, into),
		"one step over the border is not yet %s" % into)
	var deep := first_step + Vector3(WorldStreamer.REGION_MARGIN_M + 30.0, 0.0, 0.0)
	if provider.region_id_at(deep.x + WorldStreamer.REGION_MARGIN_M, deep.z) == into \
			and provider.region_id_at(deep.x, deep.z + WorldStreamer.REGION_MARGIN_M) == into \
			and provider.region_id_at(deep.x, deep.z - WorldStreamer.REGION_MARGIN_M) == into:
		assert_true(streamer.region_entered_at(deep, into), "well inside, it is %s" % into)
	streamer._current_region = ""
	assert_true(streamer.region_entered_at(first_step, into), "the first region of all is taken at once")
	# walked there from the other side: not yet; put there from far away: at once
	var was := GameState.current_region_id
	var target := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(target)
	streamer.target = target
	streamer._current_region = str(border[1])
	target.global_position = border[0]
	streamer._region_checked_at = border[0]
	streamer._check_region()
	target.global_position = first_step
	streamer._check_region()
	assert_eq(streamer._current_region, str(border[1]), "a step over the border changes nothing")
	streamer._region_checked_at = first_step + Vector3(WorldStreamer.REGION_JUMP_M * 3.0, 0.0, 0.0)
	streamer._check_region()
	assert_eq(streamer._current_region, into, "a target set down over the border takes the region at once")
	target.queue_free()
	streamer.free()
	GameState.current_region_id = was
