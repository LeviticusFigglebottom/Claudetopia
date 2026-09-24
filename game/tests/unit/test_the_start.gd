extends TestCase
## Where a new game puts the player, and what it gives them (DESIGN §5.1a, "The start"). The
## user's first minutes were a body alone on a grey pad in the sea at the foot of a cliff, an
## objective that completed the moment it appeared and a Warden who was in Merrowby. These pin the
## start that replaced it: the Stair Head camp on the rim, dressed, with the Warden held at her
## fire, a first objective that waits to be done, and a way marked on walkable ground to a
## second one a couple of minutes off, clear of what lives on the heath.
##
## The ground and the spawns are read from the built world: the full-resolution maps where this
## machine built them (`./run.sh world`), else the runtime copy the tracked world carries; with no
## world at all those tests say so once and skip.

const GENERATED := "res://world/generated"
const OPENING := "core:opening/new_game"
const START := "core:poi/stair_head"
const WREN := "core:npc/wren_tallow"
const NAMING := "core:quest/the_naming"
const CHOIR := "core:place/sunken_choir"
const HUSHLINE := "core:poi/hushline_stair"
## What a person can walk up, measured over four metres of the built ground.
const WALKABLE_DEG := 30.0
## How close the marked way comes to anything the world builder stood on the heath to fight you.
const CLEAR_OF_ENEMIES_M := 50.0
## How near a `reach` objective's place counts as being there (QuestLog.REACH_RADIUS_M).
const REACH_M := 45.0
## Room for a body beside something solid the way goes round.
const BODY_M := 1.0

var provider: TerrainProvider = null
var pois: Array = []
var _heights: FileAccess = null
var _grid := 4096
var _spacing := 2.0
var _origin := Vector2(-4096.0, -4096.0)
var _scratch: Node3D = null
static var _warned := false


func before_each() -> void:
	if provider != null or not FileAccess.file_exists("%s/pois.json" % GENERATED):
		if provider == null and not _warned:
			_warned = true
			print("  (world data missing: run ./run.sh world; the start's ground tests skip)")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/world_manifest.json" % GENERATED))
	if manifest is Dictionary:
		_grid = int(manifest.get("grid", 4096))
		_spacing = float(manifest.get("spacing_m", 2.0))
		var o: Array = manifest.get("origin", [-4096, -4096])
		_origin = Vector2(float(o[0]), float(o[1]))
	if FileAccess.file_exists("%s/heights.r32" % GENERATED):
		_heights = FileAccess.open("%s/heights.r32" % GENERATED, FileAccess.READ)


func after_each() -> void:
	if _scratch != null and is_instance_valid(_scratch):
		_scratch.get_parent().remove_child(_scratch)
		_scratch.free()
	_scratch = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Full-resolution ground, bilinear over the builder's own grid; where only the tracked world's
## runtime copy is here (heights.r32 stays on the machine that built it), the ground the game
## itself reads from that copy. Without this fallback the ground tests passed on it having
## checked nothing.
func _ground(x: float, z: float) -> float:
	if _heights == null:
		return provider.get_height(x, z)
	var fx := clampf((x - _origin.x) / _spacing, 0.0, float(_grid) - 1.001)
	var fz := clampf((z - _origin.y) / _spacing, 0.0, float(_grid) - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	return lerpf(lerpf(_h(x0, z0), _h(x0 + 1, z0), tx), lerpf(_h(x0, z0 + 1), _h(x0 + 1, z0 + 1), tx), tz)


func _h(ix: int, iz: int) -> float:
	_heights.seek((clampi(iz, 0, _grid - 1) * _grid + clampi(ix, 0, _grid - 1)) * 4)
	return _heights.get_float()


func _xz(id: String) -> Vector2:
	return WorldProbe.xz_of(ContentDB.get_or_empty(id))


## The Stair Head as the world dresses it: on the pad the built world gave it, or, in a world
## built before it had one, on the ground where its data puts it.
func _raise_start() -> PoiDressing:
	var entries: Array = pois.duplicate()
	entries.append_array(WorldPois.unbuilt_entries(pois, provider))
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("place_id", "")) == START:
			var d := PoiDressing.raise(e, ContentDB.get_or_empty(START), false, provider, WorldPois.roads_from_disk())
			_scratch = Node3D.new()
			_scratch.name = "StartScratch"
			_tree().root.add_child(_scratch)
			_scratch.add_child(d)
			return d
	return null


## The way's points on today's map, as the waystones stand them: the built road from the Stair
## Head to the Choir where the world has one, else the path's shape between the two, so it goes
## where they go (PoiDressing.way_points, docs/COORDINATES.md).
func _via() -> Array[Vector2]:
	var out: Array[Vector2] = []
	# the way stops where reaching the Choir counts, as its stones do (PoiBuilders.way_of): the
	# atlas's road runs on to the Choir's own position, inside its first colossus
	for p in PoiDressing.way_points(START, ContentDB.get_or_empty(START)):
		out.append(p)
		if out.size() >= 2 and p.distance_to(_xz(CHOIR)) <= 40.0:
			break
	return out


# --- where it is --------------------------------------------------------------------------------

func test_a_new_game_opens_at_the_stair_head_facing_the_choir() -> void:
	var opening := ContentDB.get_def(OPENING)
	assert_eq(str(opening.get("place", "")), START, "the story opens at the Stair Head, not on the pad in the mist")
	assert_eq(str(opening.get("greeter", "")), WREN, "and the Warden is who speaks first")
	assert_ne(_xz(START), Vector2.ZERO, "the Stair Head says where it is")
	var cinematic := ContentDB.get_def(str(opening.get("cinematic", "")))
	var facing: Dictionary = (cinematic.get("handover", {}) as Dictionary).get("facing", {})
	assert_eq(str(facing.get("place", "")), CHOIR, "control comes back facing the Choir, the way the path goes")
	var stair := _xz("core:poi/hushline_stair")
	assert_true(_xz(START).distance_to(stair) > 100.0, "the start is up on the rim, not at the Stair itself")


func test_the_start_stands_on_the_rim_above_the_mist() -> void:
	if provider == null:
		return
	var at := _xz(START)
	var here := _ground(at.x, at.y)
	assert_gt(here, 40.0, "the start is up on the rim (%.1f m), not down in the Hush" % here)
	assert_false(provider.is_water(at.x, at.y), "and on dry ground")
	var lowest := here
	var highest := here
	for a in range(0, 360, 30):
		for r in [3.0, 6.0]:
			var g := _ground(at.x + cos(deg_to_rad(a)) * r, at.y + sin(deg_to_rad(a)) * r)
			lowest = minf(lowest, g)
			highest = maxf(highest, g)
	assert_true(highest - lowest < 3.5, "the ground where the Foundling stands is near level (%.1f m over 6 m)" % (highest - lowest))
	# the spawn's own test of a landing (PlayerSpawn.dry_ground_near), so the start is the landing
	# and that search is only ever a safety net under it
	assert_true(PlayerSpawn._dry_at(provider, at.x, at.y), "the spawn reads the start as dry, walkable ground")
	var landed := PlayerSpawn.dry_ground_near(provider, Vector3(at.x, 0.0, at.y))
	assert_true(Vector2(landed.x - at.x, landed.z - at.y).length() < 0.5, "and leaves the Foundling where the story put them")


# --- what is there ------------------------------------------------------------------------------

func test_the_stair_head_is_a_camp_with_the_warden_s_place_in_front() -> void:
	if provider == null:
		return
	var d := _raise_start()
	assert_true(d != null, "the Stair Head is dressed, on its pad or, before it had one, on the ground")
	if d == null:
		return
	# fires and lamps at a point of interest are drawn from the NightLights pool now, not each an
	# OmniLight3D of its own: count the ones it registered as well as any it still holds
	var lit := d.lights().size() + d.light_sources().size()
	assert_gt(lit, 2, "a fire and lamps: %d lights (%d held, %d pooled)" % [lit, d.lights().size(), d.light_sources().size()])
	var stones := d.hearthstones()
	assert_eq(stones.size(), 1, "one Hearthstone, the Warden's")
	if not stones.is_empty():
		assert_eq((stones[0] as Hearthstone).hearthstone_id, START)
	var spot := d.find_child("wren_stair_head", true, false) as NpcSpot
	assert_true(spot != null, "there is somewhere for the Warden to stand")
	if spot != null:
		var flat := Vector2(spot.position.x, spot.position.z)
		assert_true(flat.length() > 4.0 and flat.length() < 10.0, "she stands %.1f m in front of the Foundling" % flat.length())
		var to_choir := (_xz(CHOIR) - _xz(START)).normalized()
		var off := rad_to_deg(absf(flat.normalized().angle_to(to_choir)))
		assert_true(off < 35.0, "and in the way the first view looks (%.0f degrees off it)" % off)
		var facing := -spot.transform.basis.z
		assert_gt(Vector2(facing.x, facing.z).dot(-flat.normalized()), 0.9, "turned to face the Foundling")
	var marks := 0
	for mm_v in d.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mm_v as MultiMeshInstance3D
		if mm.multimesh != null and str(mm.name).contains("standing_stone"):
			marks += mm.multimesh.instance_count
	assert_gt(marks, 15, "waystones walk away to the Choir: %d of them" % marks)
	# they stop where reaching it counts, at the head of its avenue, and none stands in its colossus
	# (the way the builder lays them along; a headless multimesh keeps no instance positions)
	var way: Array = (load(PoiDressing.BUILDERS_PATH) as GDScript).call("way_of", d.path)
	var last: Array = way[way.size() - 1]
	var short := Vector2(float(last[0]), float(last[1])).distance_to(_xz(CHOIR))
	assert_true(short > 20.0 and short <= REACH_M, "the way's last point is %.0f m from the Choir's middle" % short)


## The playtest found the start "a little sparse". The Wardens' camp has their gear about it, and
## crows sat on it.
func test_the_camp_is_lived_in() -> void:
	if provider == null:
		return
	var d := _raise_start()
	if d == null:
		return
	var names: Array[String] = []
	for n in d.find_children("*", "Node3D", true, false):
		names.append(str(n.name))
	for kind: String in ["cooking_pot", "spear", "shield", "peat_stack", "bucket", "rope_coil"]:
		var marker := "_%s_" % kind
		var found := names.any(func(n: String) -> bool: return n.contains(marker))
		assert_true(found, "the camp has its %s" % kind)
	var crows := d.find_child("Crows", true, false) as Crows
	assert_true(crows != null, "and crows")
	if crows != null:
		assert_gt(crows.count(), 3, "%d of them" % crows.count())
		assert_gt(crows.sitting(), 1, "sat about the camp (%d)" % crows.sitting())


## Nothing the camp stands solid is on its own marked way. The atlas turned the way west out of the
## camp, and the Wardens' cart stood across it twelve metres from the fire, so the first walk began
## by stepping round it. Every body the dressing stands within forty metres of the camp is held off
## every leg of the way by the reach of its shapes and a body's width.
func test_nothing_the_camp_stands_solid_is_on_its_way() -> void:
	if provider == null:
		return
	var d := _raise_start()
	if d == null:
		return
	var origin := Vector2(d.global_position.x, d.global_position.z)
	var legs: Array = []
	var via := _via()
	for i in range(via.size() - 1):
		if via[i].distance_to(origin) < 45.0 or via[i + 1].distance_to(origin) < 45.0:
			legs.append([via[i], via[i + 1]])
	assert_false(legs.is_empty(), "the way leaves the camp")
	var across: Array[String] = []
	for b in d.find_children("*", "StaticBody3D", true, false):
		var body := b as StaticBody3D
		for s in body.find_children("*", "CollisionShape3D", false, false):
			var cs := s as CollisionShape3D
			if cs.shape == null:
				continue
			var box := cs.shape.get_debug_mesh().get_aabb()
			var centre := cs.global_transform * box.get_center()
			var flat_reach := Vector2(box.size.x, box.size.z).length() * 0.5 * cs.global_transform.basis.get_scale().x
			if box.size.y * cs.global_transform.basis.get_scale().y < 0.25:
				continue  # a slab underfoot is walked over, not round
			var at := Vector2(centre.x, centre.z)
			if at.distance_to(origin) > 40.0:
				continue
			for leg in legs:
				var closest := Geometry2D.get_closest_point_to_segment(at, leg[0], leg[1])
				if closest.distance_to(at) < flat_reach + BODY_M * 0.5:
					across.append("%s (%.1f m from the way, reaching %.1f m)" % [body.get_parent().name, closest.distance_to(at), flat_reach])
					break
	assert_true(across.is_empty(), "the camp stands on its own way: %s" % ", ".join(across))


## The stair down the bank, where the land draws it as a road: laid in stone steps from the camp
## to the Hush, with a wall on the side that falls away, and no wall anywhere a person walking
## down its middle would walk into (a switchback's next leg comes back through the last one's
## side, so the wall stops short of every bend).
func test_the_stair_road_is_laid_in_steps_with_a_wall_on_its_drop() -> void:
	if provider == null:
		return
	var consts := (load(PoiDressing.BUILDERS_PATH) as GDScript).get_script_constant_map()
	var road: Array[Vector2] = []
	for p in WorldProbe.road_points(str(consts["HUSH_STAIR_ROAD"])):
		road.append(Vector2(float(p[0]), float(p[1])))
	if road.size() < 2:
		return
	var d := _raise_start()
	if d == null:
		return
	var origin := Vector2(d.global_position.x, d.global_position.z)
	var stair := d.find_child("Stair", true, false) as MeshInstance3D
	assert_true(stair != null, "the Stair Head has its stone")
	if stair != null:
		var box := stair.global_transform * stair.get_aabb()
		var mid := road[road.size() / 2]
		assert_true(mid.x > box.position.x and mid.x < box.end.x and mid.y > box.position.z and mid.y < box.end.z,
				"the steps go down the road, past its middle at %s (the stone covers %s)" % [mid, box])
	# the walls: every box the dressing stands beside the road, away from the camp
	var walls: Array[CollisionShape3D] = []
	for s in d.find_children("*", "CollisionShape3D", true, false):
		var cs := s as CollisionShape3D
		if not (cs.shape is BoxShape3D):
			continue
		var at := Vector2(cs.global_position.x, cs.global_position.z)
		if at.distance_to(origin) < 45.0:
			continue
		for i in range(road.size() - 1):
			if Geometry2D.get_closest_point_to_segment(at, road[i], road[i + 1]).distance_to(at) < 4.0:
				walls.append(cs)
				break
	assert_gt(walls.size(), 0, "a wall stands on the stair's drop")
	# walk its middle, a body's width wide
	var struck: Array[String] = []
	for i in range(road.size() - 1):
		var length := road[i].distance_to(road[i + 1])
		var steps := int(ceil(length / 0.5))
		for j in steps:
			var p := road[i].lerp(road[i + 1], float(j) / float(steps))
			var body := Vector3(p.x, provider.get_height(p.x, p.y) + 0.9, p.y)
			for cs in walls:
				if Vector2(cs.global_position.x, cs.global_position.z).distance_to(p) > 12.0:
					continue
				var size := (cs.shape as BoxShape3D).size
				var local := cs.global_transform.affine_inverse() * body
				if absf(local.x) < size.x * 0.5 + BODY_M * 0.4 and absf(local.y) < size.y * 0.5 + 0.9 \
						and absf(local.z) < size.z * 0.5 + BODY_M * 0.4:
					struck.append("leg %d at %s" % [i, p.round()])
					break
	assert_true(struck.is_empty(), "walking down the stair's middle meets a wall %d times: %s" % [struck.size(),
			", ".join(struck.slice(0, 6))])
	print("  (the stair road: %d wall runs)" % walls.size())


## The Wardens keep a ewe on a tether at the camp, clear of its way.
func test_the_camp_keeps_a_ewe_on_a_tether() -> void:
	if provider == null:
		return
	var d := _raise_start()
	if d == null:
		return
	var ewe := d.find_child("Tethered", true, false) as Livestock
	assert_true(ewe != null, "the camp has its tethered ewe")
	if ewe == null:
		return
	assert_eq(ewe.beasts.size(), 1, "one ewe")
	var home: Vector3 = ewe.to_global((ewe.beasts[0] as Dictionary)["home"])
	var at := Vector2(home.x, home.z)
	assert_gt(25.0, at.distance_to(Vector2(d.global_position.x, d.global_position.z)), "by the camp")
	var via := _via()
	for i in range(via.size() - 1):
		var off := Geometry2D.get_closest_point_to_segment(at, via[i], via[i + 1]).distance_to(at)
		assert_gt(off, 4.0, "her stake is clear of the way (%.1f m from its leg %d)" % [off, i])
	# nothing solid in her circle: the ash field's charred stumps and the camp's things keep off it
	var tether: float = (load(PoiDressing.BUILDERS_PATH) as GDScript).get_script_constant_map()["TETHER_M"]
	var inside: Array[String] = []
	for s in d.find_children("*", "CollisionShape3D", true, false):
		var cs := s as CollisionShape3D
		if cs.shape == null or cs.get_parent() is PoiTouch:
			continue
		var box := cs.shape.get_debug_mesh().get_aabb()
		var centre := cs.global_transform * box.get_center()
		var reach := Vector2(box.size.x, box.size.z).length() * 0.5 * cs.global_transform.basis.get_scale().x
		var off := Vector2(centre.x, centre.z).distance_to(at)
		if off < tether + 0.6 + reach and off > 0.2:
			inside.append("%s %.1f m from her stake" % [cs.get_parent().name, off])
	assert_true(inside.is_empty(), "her tether's circle is clear: %s" % ", ".join(inside))


## Where the Naming's walk north comes out of the ash, the first flock: sheep grazing by the
## Wellspring, on dry ground.
func test_sheep_graze_by_the_wellspring() -> void:
	if provider == null:
		return
	var entries: Array = pois.duplicate()
	entries.append_array(WorldPois.unbuilt_entries(pois, provider))
	var d: PoiDressing = null
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("place_id", "")) == "core:poi/the_wellspring":
			d = PoiDressing.raise(e, ContentDB.get_or_empty("core:poi/the_wellspring"), false, provider, WorldPois.roads_from_disk())
	assert_true(d != null, "the Wellspring is dressed")
	if d == null:
		return
	_scratch = Node3D.new()
	_scratch.name = "WellspringScratch"
	_tree().root.add_child(_scratch)
	_scratch.add_child(d)
	var flock := d.find_child("Grazing", true, false) as Livestock
	assert_true(flock != null, "sheep graze by it")
	if flock == null:
		return
	assert_gt(flock.beasts.size(), 3, "a flock (%d)" % flock.beasts.size())
	for b in flock.beasts:
		var at := flock.to_global((b as Dictionary)["at"])
		assert_false(provider.is_water(at.x, at.z), "a ewe stands on dry ground at (%.0f, %.0f)" % [at.x, at.z])


## The Wardens' Watch: a tower beside the camp's way where it tops the Choir's Crown, with a way
## up. Its platform is ten metres over the ground, it can be walked up to from the way, and
## nothing of it stands on the way.
func test_the_wardens_watch_can_be_climbed_from_the_way() -> void:
	if provider == null:
		return
	var d := _raise_start()
	if d == null:
		return
	var view: Marker3D = null
	for n in d.find_children("the_view", "Marker3D", true, false):
		view = n as Marker3D
	assert_true(view != null, "the Watch is built, with its view marked")
	if view == null:
		return
	var top := view.global_position
	var ground := provider.get_height(top.x, top.z)
	assert_near(top.y - ground, 10.0, 1.5, "its platform is ten metres up (%.1f)" % (top.y - ground))
	await _tree().physics_frame
	await _tree().physics_frame
	var space := d.get_world_3d().direct_space_state
	var down := func(x: float, z: float, from_y: float) -> Dictionary:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 40.0, z))
		return space.intersect_ray(q)
	var floor_hit: Dictionary = down.call(top.x, top.z, top.y + 3.0)
	assert_false(floor_hit.is_empty(), "the platform is solid")
	if not floor_hit.is_empty():
		assert_near(float((floor_hit["position"] as Vector3).y), top.y, 0.3, "and stood on at its top")
	# the stair: walk down its middle from the platform to the ground, toward the way it comes down
	# to, and every step of it is a slope a body goes up
	var builders := load(PoiDressing.BUILDERS_PATH) as GDScript
	var consts := builders.get_script_constant_map()
	var via := _via()
	var at := Vector2(top.x, top.z)
	var spot: Array = builders.call("_watch_spot", d)
	assert_false(spot.is_empty(), "the Watch has its place on the way")
	if spot.is_empty():
		return
	var on_way: Vector2 = Vector2(d.global_position.x, d.global_position.z) + (spot[0] as Vector2)
	var way_side := (on_way - at).normalized()
	var half: float = consts["WATCH_HALF_M"]
	var last_y := INF
	var climbed := 0.0
	var steep: Array[String] = []
	for j in 80:
		var p := at + way_side * (half + 0.3 + float(j) * 0.5)
		var hit: Dictionary = down.call(p.x, p.y, top.y + 3.0)
		if hit.is_empty():
			break
		var y := float((hit["position"] as Vector3).y)
		var n := hit["normal"] as Vector3
		if rad_to_deg(n.angle_to(Vector3.UP)) > 40.0:
			steep.append("%.1f m down the stair at %.0f degrees" % [float(j) * 0.5, rad_to_deg(n.angle_to(Vector3.UP))])
		if last_y != INF:
			climbed += last_y - y
		last_y = y
		if y <= provider.get_height(p.x, p.y) + 0.3:
			break
	assert_true(steep.is_empty(), "the stair is walked up: %s" % ", ".join(steep))
	assert_gt(climbed, 8.0, "and goes from the ground to the top (%.1f m)" % climbed)
	# nothing of it on the way
	var across: Array[String] = []
	for b in d.find_children("*", "CollisionShape3D", true, false):
		var cs := b as CollisionShape3D
		if not (cs.shape is BoxShape3D) or Vector2(cs.global_position.x, cs.global_position.z).distance_to(at) > 30.0:
			continue
		var size := (cs.shape as BoxShape3D).size
		for i in range(via.size() - 1):
			var length := via[i].distance_to(via[i + 1])
			for s in int(ceil(length / 0.5)):
				var p := via[i].lerp(via[i + 1], float(s) * 0.5 / length)
				var local := cs.global_transform.affine_inverse() * Vector3(p.x, provider.get_height(p.x, p.y) + 0.9, p.y)
				if absf(local.x) < size.x * 0.5 + 0.4 and absf(local.y) < size.y * 0.5 + 0.9 and absf(local.z) < size.z * 0.5 + 0.4:
					across.append("(%.0f, %.0f)" % [p.x, p.y])
					break
	assert_true(across.is_empty(), "the Watch stands off the way: it is across it at %s" % ", ".join(across))
	# and from its far wall you can look out, and are told what you are looking at
	var look := d.find_child("look_out", true, false) as PoiTouch
	assert_true(look != null, "the Watch's far wall is somewhere to look out from")
	if look != null:
		assert_eq(look.prompt_text(), "Look out", "and says so")
		assert_false(ContentDB.get_or_empty(look.dialogue_id).is_empty(), "with something to say (%s)" % look.dialogue_id)
		assert_near(look.global_position.y, top.y, 0.3, "on the platform")


func test_nothing_solid_stands_where_the_foundling_is_put() -> void:
	if provider == null:
		return
	var d := _raise_start()
	if d == null:
		return
	await _tree().physics_frame
	await _tree().physics_frame
	var space := d.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 1.8
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, d.global_position + Vector3(0.0, 1.0, 0.0))
	var hits := space.intersect_shape(q, 8)
	assert_eq(hits.size(), 0, "the spawn is clear: %s" % str(hits.map(func(h: Dictionary) -> String: return str((h["collider"] as Node).name))))


# --- the way to the first place ----------------------------------------------------------------------

func test_the_waystones_lead_from_the_camp_to_the_choir_a_couple_of_minutes_off() -> void:
	var via := _via()
	assert_gt(via.size(), 5, "the Stair Head marks a way")
	if via.size() < 2:
		return
	assert_eq(str((ContentDB.get_or_empty(START).get("path", {}) as Dictionary).get("to", "")), CHOIR)
	assert_true(via[0].distance_to(_xz(START)) < 30.0, "it starts at the camp")
	assert_true(via[via.size() - 1].distance_to(_xz(CHOIR)) < REACH_M, "and ends where reaching the Choir counts")
	var length := 0.0
	for i in range(via.size() - 1):
		length += via[i].distance_to(via[i + 1])
	# a minute or two at the pace the body walks the heath
	assert_true(length > 300.0 and length < 650.0, "the walk is %.0f m" % length)


func test_the_marked_way_is_ground_a_person_can_walk() -> void:
	if provider == null:
		return
	var via := _via()
	var steep: Array[String] = []
	var wet: Array[String] = []
	for i in range(via.size() - 1):
		var a := via[i]
		var b := via[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
		for s in n:
			var p := a.lerp(b, float(s) / float(n))
			var q := a.lerp(b, float(s + 1) / float(n))
			var rise := absf(_ground(q.x, q.y) - _ground(p.x, p.y))
			var slope := rad_to_deg(atan2(rise, p.distance_to(q)))
			if slope > WALKABLE_DEG:
				steep.append("%.0f deg at (%.0f, %.0f)" % [slope, p.x, p.y])
			if provider.is_water(p.x, p.y):
				wet.append("(%.0f, %.0f)" % [p.x, p.y])
	assert_true(steep.is_empty(), "too steep to walk: %s" % ", ".join(steep))
	assert_true(wet.is_empty(), "under water: %s" % ", ".join(wet))


func test_the_marked_way_keeps_clear_of_what_lives_on_the_heath() -> void:
	if provider == null:
		return
	var via := _via()
	var near: Array[String] = []
	var dir := DirAccess.open("%s/cells" % GENERATED)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var cell: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/cells/%s" % [GENERATED, file]))
		if not (cell is Dictionary):
			continue
		for s in (cell as Dictionary).get("spawns", []):
			var spawn: Dictionary = s
			if str(spawn.get("kind", "")) != "enemy":
				continue
			var pos: Array = spawn.get("pos", [0, 0, 0])
			var at := Vector2(float(pos[0]), float(pos[2]))
			if at.distance_to(_xz(START)) > 800.0:
				continue
			for i in range(via.size() - 1):
				var closest := Geometry2D.get_closest_point_to_segment(at, via[i], via[i + 1])
				if closest.distance_to(at) < CLEAR_OF_ENEMIES_M:
					near.append("%s %.0f m from the way" % [str(spawn.get("def", "?")), closest.distance_to(at)])
					break
	assert_true(near.is_empty(), "the way walks past: %s" % ", ".join(near))


## The way goes round what the build stood solid in it, not through it. The Choir's colossi are
## twenty-seven metres across at the foot, and the way's last legs went through the robe of the
## one nearest the Choir, with two of its stones inside the stone. Each solid scene within reach of
## the way is held off every leg by its model's footprint (the widest its bounds reach from its
## origin, as its collision does at the ground) and a body's width.
func test_the_marked_way_goes_round_what_stands_solid_in_it() -> void:
	if provider == null:
		return
	var via := _via()
	var dir := DirAccess.open("%s/cells" % GENERATED)
	if dir == null:
		return
	var reaches := {}
	var through: Array[String] = []
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var cell: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/cells/%s" % [GENERATED, file]))
		if not (cell is Dictionary):
			continue
		for s in (cell as Dictionary).get("scenes", []):
			var scene: Dictionary = s
			if str(scene.get("collision", "")).is_empty():
				continue
			var pos: Array = scene.get("pos", [0, 0, 0])
			var at := Vector2(float(pos[0]), float(pos[2]))
			if at.distance_to(_xz(START)) > 800.0:
				continue
			var model := str(scene.get("scene", ""))
			if not reaches.has(model):
				reaches[model] = _footprint(model)
			var reach: float = reaches[model]
			if reach <= 0.0:
				continue
			for i in range(via.size() - 1):
				var closest := Geometry2D.get_closest_point_to_segment(at, via[i], via[i + 1])
				if closest.distance_to(at) < reach + BODY_M:
					through.append("%s at (%.0f, %.0f), %.1f m from the leg (%.0f, %.0f) to (%.0f, %.0f), %.1f m from its centre to its edge"
							% [model.get_file(), at.x, at.y, closest.distance_to(at), via[i].x, via[i].y, via[i + 1].x, via[i + 1].y, reach])
					break
	assert_true(through.is_empty(), "the way walks into: %s" % ", ".join(through))


## How far a model reaches from its origin across the ground: the widest of its bounds in x and z,
## from the meta the forge writes beside it. Nothing when it has none.
func _footprint(model: String) -> float:
	var meta := model.get_basename() + ".meta.json"
	if not FileAccess.file_exists(meta):
		return 0.0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta))
	if not (parsed is Dictionary):
		return 0.0
	var bounds: Dictionary = (parsed as Dictionary).get("bounds", {})
	var lo: Array = bounds.get("min", [0, 0, 0])
	var hi: Array = bounds.get("max", [0, 0, 0])
	return maxf(maxf(absf(float(lo[0])), absf(float(hi[0]))), maxf(absf(float(lo[2])), absf(float(hi[2]))))


## The Naming's first fight is among the Choir's feet, where the waystones end: every point
## QuestFoes can stand its three ash-wights on (a ring of RING_MIN_M to RING_MAX_M round the Choir)
## is dry ground at least a metre above any water, and from the way's last stone to each of them
## is ground a person can walk. From the Stair Head to the fight is walkable end to end.
func test_the_naming_s_first_fight_is_on_dry_ground_at_the_end_of_the_way() -> void:
	if provider == null:
		return
	var stage := {}
	for st in ContentDB.get_def(NAMING).get("stages", []):
		if str((st as Dictionary).get("id", "")) == "ash_wights":
			stage = st
	var objectives: Array = stage.get("objectives", [])
	assert_false(objectives.is_empty(), "the Naming asks for its ash-wights")
	if objectives.is_empty():
		return
	assert_eq(str((objectives[0] as Dictionary).get("where", "")), CHOIR, "among the Choir's feet, where the way goes")
	var via := _via()
	if via.is_empty():
		return
	var from := via[via.size() - 1]
	var centre := _xz(CHOIR)
	var wet: Array[String] = []
	var steep: Array[String] = []
	for ring in [QuestFoes.RING_MIN_M, (QuestFoes.RING_MIN_M + QuestFoes.RING_MAX_M) * 0.5, QuestFoes.RING_MAX_M]:
		for step in 24:
			var a := TAU * float(step) / 24.0
			var p: Vector2 = centre + Vector2(cos(a), sin(a)) * float(ring)
			var above := provider.get_height(p.x, p.y) - provider.nearest_water_level(p.x, p.y)
			if provider.is_water(p.x, p.y) or above < 1.0:
				wet.append("(%.0f, %.0f) %.1f m above the water" % [p.x, p.y, above])
			var n := maxi(1, int(ceil(from.distance_to(p) / 4.0)))
			for s in n:
				var u := from.lerp(p, float(s) / float(n))
				var v := from.lerp(p, float(s + 1) / float(n))
				var slope := rad_to_deg(atan2(absf(_ground(v.x, v.y) - _ground(u.x, u.y)), u.distance_to(v)))
				if slope > WALKABLE_DEG:
					steep.append("%.0f deg on the way to (%.0f, %.0f)" % [slope, p.x, p.y])
					break
	assert_true(wet.is_empty(), "the fight's ground is dry: %s" % ", ".join(wet))
	assert_true(steep.is_empty(), "and it can be walked to from the last waystone: %s" % ", ".join(steep))


## The Hushline Stair's own pad was flattened at 0.2 m with the Hush twenty metres deep round it:
## a raft awash, its stair going down into clear sea, its ash-wights at the waterline. Its landing
## stands on a shelf clear of the water now, its wights on the landing, and the mist lies on the
## water where the stair goes under.
func test_the_hushline_landing_stands_clear_of_the_water_with_its_wights_on_it() -> void:
	if provider == null:
		return
	var d: PoiDressing = null
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == HUSHLINE:
			d = PoiDressing.raise(e, ContentDB.get_or_empty(HUSHLINE), false, provider, WorldPois.roads_from_disk())
			_scratch = Node3D.new()
			_scratch.name = "HushlineScratch"
			_tree().root.add_child(_scratch)
			_scratch.add_child(d)
	assert_true(d != null, "the Hushline Stair is in the built world")
	if d == null:
		return
	var at := _xz(HUSHLINE)
	var water := provider.nearest_water_level(at.x, at.y)
	var landing := d.find_child("the_landing", true, false) as Node3D
	assert_true(landing != null, "the landing is marked")
	if landing == null:
		return
	var floor_y := landing.global_position.y
	assert_true(floor_y >= water + 1.0, "the landing stands %.1f m above the water" % (floor_y - water))
	assert_true(bool(landing.get_meta("raised", false)) or not provider.is_water(at.x, at.y),
			"and it is the floor there, not the sea bed")
	# the wights stand where PoiEncounters puts them, spread round the marker, each with the landing
	# under its feet
	for _i in 3:
		await _tree().physics_frame
	var space := d.get_world_3d().direct_space_state
	var groups := PoiEncounters.of(HUSHLINE)
	assert_false(groups.is_empty(), "the Stair keeps its ash-wights")
	for index in groups.size():
		var e: Dictionary = groups[index]
		assert_eq(str(e.get("at", "")), "the_landing", "they wait on the landing")
		var count := maxi(1, int(e.get("count", 1)))
		for k in count:
			var a := TAU * float(k) / float(count) + float(index)
			var p := landing.global_position + Vector3(cos(a), 0.0, sin(a)) * float(e.get("spread", 2.5))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0))
			var under := NAN
			if not hit.is_empty():
				under = (hit["position"] as Vector3).y
			elif not bool(landing.get_meta("raised", false)):
				# a pad the land already lifts clear of the water is its own landing (the atlas world
				# draws one under the cliff): the ground is under them, which this scratch has no
				# collider for, so it is read from the terrain
				under = provider.get_height(p.x, p.z)
			assert_false(is_nan(under), "a wight at (%.1f, %.1f) has the landing under it" % [p.x, p.z])
			if not is_nan(under):
				assert_true(absf(under - p.y) < 0.35 and under >= water + 1.0,
						"standing %.2f m above the water, on the landing" % (under - water))
	var mist := 0
	for n in d.find_children("*", "GPUParticles3D", true, false):
		var y := (n as Node3D).global_position.y
		if y > water and y < water + 3.5:
			mist += 1
	assert_true(mist >= 4, "the mist lies on the water where the stair goes under (%d banks)" % mist)


# --- the story's first two asks ------------------------------------------------------------------------

func test_standing_at_the_start_completes_nothing_and_the_warden_sends_you_north() -> void:
	var quests: Node = Social.quests
	quests.call("reset_for_new_game")
	assert_true(bool(quests.call("start", NAMING)), "the Naming starts")
	var start := Vector3(_xz(START).x, 0.0, _xz(START).y)
	quests.call("check_reach", start)
	EventBus.place_discovered.emit(START)
	assert_eq(str(quests.call("stage_id_of", NAMING)), "wake", "arriving where you are completes nothing")
	var marked := false
	for m in quests.call("active_markers"):
		if str((m as Dictionary).get("place_id", "")) == START:
			marked = true
	assert_true(marked, "and the compass is told where the Warden is, not where she lives")
	var line := str(quests.call("objectives_of", NAMING)[0].get("text", ""))
	assert_eq(line, "Speak to the Warden at her fire")
	EventBus.dialogue_ended.emit(WREN)
	assert_eq(str(quests.call("stage_id_of", NAMING)), "the_choir", "speaking to her sends you north")
	quests.call("check_reach", start)
	assert_eq(str(quests.call("stage_id_of", NAMING)), "the_choir", "the Choir is a walk away, not where you stand")
	var choir := Vector3(_xz(CHOIR).x, 0.0, _xz(CHOIR).y)
	quests.call("check_reach", choir)
	assert_eq(str(quests.call("stage_id_of", NAMING)), "ash_wights", "and reaching it moves the story on")
	quests.call("reset_for_new_game")
	_forget_the_story()


## The flags the Naming's first stages set, taken back so the next test starts from nothing.
func _forget_the_story() -> void:
	for flag in ["woke_at_hushline", "met_wren", "named", "walked_to_the_choir"]:
		GameState.clear_flag(flag)


func test_the_warden_is_held_at_her_fire_until_you_walk_north() -> void:
	var quests: Node = Social.quests
	var wren := ContentDB.get_def(WREN)
	assert_true(Schedules.hold_problems(wren).is_empty(), "her hold is well formed: %s" % str(Schedules.hold_problems(wren)))
	quests.call("reset_for_new_game")
	var had_flag := GameState.has_flag("new_game")
	GameState.set_flag("new_game", true)
	var named := Schedules.entry_for_def(wren, 3, 15.0, "rain")
	assert_eq(str(named.get("place", "")), START, "from the moment a new game is named she is at the Stair Head")
	assert_eq(str(named.get("spot", "")), "wren_stair_head", "at her fire, rain or no")
	GameState.set_flag("new_game", false)
	assert_ne(str(Schedules.entry_for_def(wren, 3, 15.0).get("place", "")), START, "and nobody else's game keeps her there")
	quests.call("start", NAMING)
	assert_eq(str(Schedules.entry_for_def(wren, 3, 15.0).get("place", "")), START, "the first stage holds her")
	quests.call("set_stage", NAMING, "the_choir")
	assert_eq(str(Schedules.entry_for_def(wren, 3, 15.0).get("place", "")), START, "so does the walk north")
	quests.call("set_stage", NAMING, "ash_wights")
	assert_eq(str(Schedules.entry_for_def(wren, 3, 15.0).get("place", "")), "core:place/merrowby",
			"and then she goes back to her own days")
	quests.call("reset_for_new_game")
	GameState.set_flag("new_game", had_flag)
	_forget_the_story()


func test_the_warden_speaks_first_and_the_hud_says_what_to_do() -> void:
	var quests: Node = Social.quests
	quests.call("reset_for_new_game")
	quests.call("start", NAMING)
	# by day: after dark she has a line about counting bells that is just as much hers
	var hour := WorldClock.time_hours
	WorldClock.set_time(10.0)
	var greeting := str(Social.dialogue.call("greeting_for", WREN))
	WorldClock.set_time(hour)
	assert_true(greeting.begins_with("There you are."), "her first words are her own for this moment: %s" % greeting)
	var hud: Node = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	_tree().root.add_child(hud)
	assert_eq(str(hud.call("objective_line", NAMING)), "The Naming: Speak to the Warden at her fire")
	quests.call("set_stage", NAMING, "the_choir")
	await _tree().create_timer(0.35).timeout
	assert_eq(str(hud.call("objective_shown")), "The Naming: Walk the waystones north to the Sunken Choir",
			"a new objective is written under the compass as it happens")
	_tree().root.remove_child(hud)
	hud.free()
	quests.call("reset_for_new_game")
	_forget_the_story()
