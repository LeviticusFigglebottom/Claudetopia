extends TestCase
## A batch of built pieces keeps every piece laid into it. The Stair Head's timber laid its poles,
## lamp posts and the ewe's stake as unindexed boxes and then the cooking tripod as capsules (an
## indexed mesh); a SurfaceTool given an indexed mesh draws only what its index names, and the
## committed "Timber" was the tripod alone. Every lantern along the waystones and every banner and
## bell at the camp hung in the air (the user's playtest, 2026-09-25).


func _span(st: SurfaceTool) -> AABB:
	st.generate_normals()
	return st.commit().get_aabb()


func test_a_block_and_a_limb_in_one_batch_are_both_drawn() -> void:
	var kit := PoiKit.new(Node3D.new(), Vector3.ZERO, 10.0, "core:region/cinderlea", false, "masonry test")
	var m := PoiMasonry.new(kit)
	var st := m.begin()
	m.block(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(0.2, 2.0, 0.2))
	m.limb(st, Vector3(10.0, 0.0, 0.0), Vector3(10.0, 1.0, 0.0), 0.05)
	var box := _span(st)
	assert_true(box.position.x < -0.05, "the post at the origin is in the mesh (it starts at x %.2f)" % box.position.x)
	assert_true(box.end.x > 9.9, "and so is the limb 10 m off (it ends at x %.2f)" % box.end.x)


func test_a_rod_an_ellipsoid_and_a_block_in_one_batch_are_all_drawn() -> void:
	var kit := PoiKit.new(Node3D.new(), Vector3.ZERO, 10.0, "core:region/cinderlea", false, "masonry test")
	var m := PoiMasonry.new(kit)
	var st := m.begin()
	m.rod(st, Transform3D(Basis.IDENTITY, Vector3(-10.0, 0.5, 0.0)), 0.05, 1.0)
	m.ellipsoid(st, Vector3(0.0, 0.0, 10.0), Vector3(0.5, 0.5, 0.5))
	m.block(st, Transform3D(Basis.IDENTITY, Vector3(10.0, 0.5, 0.0)), Vector3(0.2, 1.0, 0.2))
	var box := _span(st)
	assert_true(box.position.x < -9.9 and box.end.x > 9.9 and box.end.z > 10.3,
			"the rod, the ball and the block all stand in the mesh: %s" % str(box))
