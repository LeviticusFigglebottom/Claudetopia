extends TestCase
## Every house you can go into still stands on a plot of its own in the world.
##
## Building.footprint_of builds a house's outside from its interior's ground floor, and the street
## plan (StreetPlan.place_real) finds each one a frontage where the box clears the roads, the
## place's edge and the houses already on the street; the rest of the village is filled round them
## afterwards. So when the house forge re-plans an interior, the question is whether every house
## still finds a plot, and whether what stands there keeps clear of its neighbours and the road
## with its door on the street. A house that finds no plot falls back to its door plan's bare
## bearing and ring, with nothing checked round it.

const WORLD_SCENE := "res://world/world.tscn"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_every_house_with_an_inside_has_a_clear_plot_with_its_door_on_the_street() -> void:
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	for i in 2:
		await _tree().physics_frame
	var doors := _tree().get_first_node_in_group("world_doors") as WorldDoors
	assert_true(doors != null, "the world puts its doors up")
	if doors == null:
		_tree().root.remove_child(w)
		w.queue_free()
		return
	var planned := 0
	var plotted := 0
	for plan in ContentDB.all("table"):
		if str(plan.get("role", "")) != WorldDoors.PLAN_ROLE:
			continue
		var place := str(plan.get("place", ""))
		var street: StreetPlan = doors.streets.get(place)
		for row in plan.get("rows", []):
			if str((row as Dictionary).get("kind", "")) != "house":
				continue
			var id := str(row["interior"])
			planned += 1
			if street == null:
				fail("%s: %s has no street to stand on" % [place, id])
				continue
			var plot: Dictionary = {}
			for h in street.houses:
				if str((h as Dictionary).get("real", "")) == id:
					plot = h
			if plot.is_empty():
				fail("%s: %s found no clear plot on its street" % [place, id])
				continue
			plotted += 1
			var box: Dictionary = plot["box"]
			var clashes: Array[String] = []
			for other in street.houses:
				if other == plot:
					continue
				if StreetPlan.overlaps(box, other["box"], 0.05):
					clashes.append("the house of %s" % str((other as Dictionary).get("real", "the village")))
				var g: Dictionary = other.get("garden", {})
				if not g.is_empty() and StreetPlan.overlaps(box, g, 0.05):
					clashes.append("the garden of %s" % str((other as Dictionary).get("real", "the village")))
			for r in street.reserved:
				if StreetPlan.overlaps(box, r):
					clashes.append("reserved ground")
			for li in street.lines.size():
				var pts: PackedVector2Array = street.lines[li]
				for j in range(pts.size() - 1):
					if StreetPlan.segment_hits(box, pts[j], pts[j + 1], StreetPlan.ROAD_HALF_M):
						clashes.append("road %d" % li)
						break
			# The door meets its path: it stands on the house's street face, a setback off the road.
			var door_at: Vector2 = plot["door"]
			var nearest := INF
			for li2 in street.lines.size():
				var pts2: PackedVector2Array = street.lines[li2]
				for j2 in range(pts2.size() - 1):
					nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(door_at, pts2[j2], pts2[j2 + 1]).distance_to(door_at))
			var reach := StreetPlan.ROAD_HALF_M + float(plot.get("setback", 0.0)) + 1.5
			assert_true(nearest <= reach, "%s: %s's door is %.1f m from the road (a setback is %.1f)" % [place, id, nearest, reach])
			assert_true(clashes.is_empty(), "%s: %s's house overlaps %s" % [place, id, ", ".join(clashes)])
			print("    PLOT | %s | %s | %.1f x %.1f m, door %.1f m off the road%s" % [place, id, float(box["hw"]) * 2.0, float(box["hd"]) * 2.0,
					nearest, "" if clashes.is_empty() else ", overlaps " + ", ".join(clashes)])
	print("    PLOTS | %d of %d houses with an inside stand on a plot of their own" % [plotted, planned])
	assert_eq(plotted, planned, "every house with an inside has a plot")
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
