extends TestCase
## The stone at a road's entry to a town (the cartographer's signposts, a cell `scenes` entry):
## about 1.4 m of the region's stone, the place's name cut in both faces, something to walk into,
## and standing on the ground at its own origin.

const SCENE := "res://world/pois/town_stone.tscn"


func test_a_town_stone_carries_its_place_s_name_in_its_region_s_stone() -> void:
	var packed := load(SCENE) as PackedScene
	assert_true(packed != null, "the scene the build writes into the cells")
	if packed == null:
		return
	var s := packed.instantiate() as Node3D
	s.call("configure", {"place_id": "core:place/merrowby"})
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	var names := s.find_children("Name*", "Label3D", true, false)
	assert_eq(names.size(), 2, "the name cut in both faces")
	for n in names:
		assert_eq((n as Label3D).text, "MERROWBY", "the place's own name")
	var stone := s.find_child("Stone", true, false) as MeshInstance3D
	assert_true(stone != null, "a stone")
	if stone != null:
		var box := stone.mesh.get_aabb()
		assert_true(box.end.y > 1.25 and box.end.y < 1.6, "about 1.4 m tall (%.2f)" % box.end.y)
		assert_true(box.position.y < 0.0, "its foot in the ground")
		assert_true(stone.material_override is ShaderMaterial, "painted in the region's stone")
	assert_true(s.find_child("Collision", true, false) is StaticBody3D, "something to walk into")
	(Engine.get_main_loop() as SceneTree).root.remove_child(s)
	s.free()
