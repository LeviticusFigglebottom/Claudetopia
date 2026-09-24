extends TestCase
## The rivers' falls drawn from rivers.json: a river ribbon alone runs down a fall as a slide.

const RIVERS := [
	{"id": "a", "points": [], "falls": [
		{"top": [0.0, 100.0, 0.0], "foot": [0.0, 88.0, 3.0], "height_m": 12.0, "width_m": 4.0,
			"run_m": 3.0, "facing_deg": 0.0, "kind": "fall"},
		{"top": [200.0, 60.0, 0.0], "foot": [205.0, 56.0, 0.0], "height_m": 4.0, "width_m": 6.0,
			"run_m": 5.0, "facing_deg": 90.0, "kind": "cascade"}]},
	{"id": "b", "points": []},
	"not a river",
]


func test_every_fall_is_read_and_nothing_else() -> void:
	assert_eq(RiverFalls.read_falls(RIVERS).size(), 2)


func test_each_fall_draws_a_sheet_from_lip_to_foot() -> void:
	var falls := RiverFalls.new()
	assert_eq(falls.build(RIVERS), 2)
	for i in 2:
		var f: Dictionary = RIVERS[0]["falls"][i]
		var node: Node3D = falls.get_node("Fall%d" % i)
		var sheet: MeshInstance3D = node.get_node("Sheet")
		var aabb := sheet.mesh.get_aabb()
		var drop := float(f["top"][1]) - float(f["foot"][1])
		assert_near(aabb.position.y, -drop, 0.05, "fall %d's sheet reaches its foot" % i)
		assert_near(aabb.end.y, 0.0, 0.3, "fall %d's sheet starts at its lip" % i)
		assert_gt(aabb.size.x + aabb.size.z, float(f["width_m"]), "fall %d's sheet is as wide as the river" % i)
	# the tall one has mist as well as white water; the low cascade only the white water
	assert_eq(falls.get_node("Fall0").get_child_count(), 3)
	assert_eq(falls.get_node("Fall1").get_child_count(), 2)
	falls.free()


func test_a_place_can_ask_whether_a_fall_is_its_own() -> void:
	var falls := RiverFalls.new()
	falls.build(RIVERS)
	assert_true(RiverFalls.near(Vector3(2.0, 90.0, 4.0)), "beside the tall fall")
	assert_true(RiverFalls.near(Vector3(204.0, 0.0, 10.0)), "beside the cascade")
	assert_false(RiverFalls.near(Vector3(100.0, 0.0, 0.0)), "between them")
	falls.free()
	RiverFalls.all.clear()
