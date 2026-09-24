extends RefCounted
## One builder per kind of point of interest. Each takes the dressing (its kit, its masonry,
## its brief) and stands the place up out of the forge's assets and a little runtime masonry.
##
## A builder reads the POI's `unique_feature` as its brief: the thing the data names should be
## the thing you see. So a camp with "a stolen mill wheel as a table" gets a millstone laid on
## a barrel, and a shrine "built of lake pebbles" is a cairn rather than a standing stone.
## Everything else follows from the kind and the region's culture.
##
## **This script deliberately has no `class_name`.** Every builder below takes a
## `PoiDressing`, so a global name here is one half of a pair of scripts that name each other,
## and GDScript cannot always resolve that: after an import rebuilds the global class cache it
## parses one, fails on the half-built other, and reports `Could not resolve class
## "PoiBuilders", because of a parser error` — against whatever third file mentioned the name,
## which was `test_pois.gd`. `PoiDressing` loads this by path (`BUILDERS_PATH`) and the list
## of kinds a builder exists for lives on `PoiDressing.KINDS_BUILT`, so nothing outside this
## file needs the name at all.


## The kinds the drawn map asked for next, in a file of their own: caves, farmsteads, mills,
## waystones, market fields, quarries, shielings and vistas.
const LAND := preload("res://world/pois/poi_builders_land.gd")


static func build(d: PoiDressing) -> void:
	match d.kind:
		"camp":
			camp(d)
		"shrine":
			shrine(d)
		"hearth":
			hearth(d)
		"tower":
			tower(d)
		"bridge":
			bridge(d)
		"waterfall":
			waterfall(d)
		"ruins":
			ruins(d)
		"giant_bones":
			giant_bones(d)
		"strange_tree":
			strange_tree(d)
		"wreck":
			wreck(d)
		"hidden_valley":
			hidden_valley(d)
		"standing_stones":
			standing_stones(d)
		"strange":
			strange(d)
		"cave":
			LAND.cave(d)
		"farmstead":
			LAND.farmstead(d)
		"mill":
			LAND.mill(d)
		"waystone":
			LAND.waystone(d)
		"market_field":
			LAND.market_field(d)
		"quarry":
			LAND.quarry(d)
		"shieling":
			LAND.shieling(d)
		"vista":
			LAND.vista(d)
		_:
			Log.warn("PoiDressing", "%s: no builder for kind '%s'" % [d.poi_id, d.kind])
	if not d.kit.far and PoiKit.brief_says(d.brief, ["sheep grazing"]):
		_grazing(d)


# --- camps ----------------------------------------------------------------------------------------

## A fire ring with a light and smoke, tents facing the fire, bedrolls, stores, a cart, a lantern
## on a post; who camps here decides the rest. A fire that "went out" is cold: no light, ash,
## and the cups its sitters were passing set down around it.
static func camp(d: PoiDressing) -> void:
	if PoiKit.brief_says(d.brief, ["head of the hushline stair"]):
		_camp_stair_head(d)
		return
	var k := d.kit
	var m := d.masonry
	var cold := PoiKit.brief_says(d.brief, ["went out", "cold"])
	var fighters := PoiKit.brief_says(d.encounter + " " + d.brief, ["bandit", "raider", "brute", "skirmisher", "warrior", "thie"])
	var fire := k.jitter(1.2)
	var grain := k.grain()
	var timber := m.begin()

	# the fire, its ring of stones, its light and its smoke
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 1.15)
	# where the people this camp belongs to stand round it (an encounter's `at`)
	k.marker("the_fire", k.on_ground(fire.x, fire.y))
	var stones: Array = []
	for p in k.ring(9, 0.95, fire, 0.1):
		var pp: Vector2 = p
		stones.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU),
				k.rng.randf_range(0.09, 0.14)))
	k.scatter(k.rock("boulder"), stones)
	if cold:
		# ash: a dark disc where the fire was, and the cup still going round
		var ash := k.surface("earth", 0.9)
		ash.set_shader_parameter("base_color", Color(0.22, 0.21, 0.2))
		ash.set_shader_parameter("accent_color", Color(0.3, 0.29, 0.28))
		m.pool(fire, 1.6, k.on_ground(fire.x, fire.y).y + 0.03, ash, "Ash", 16)
		var passed := false
		for p in k.ring(6, 2.4, fire, 0.15):
			var pp: Vector2 = p
			k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp), 1.0)
			var cup := pp + (fire - pp).normalized() * 0.6
			k.place(k.prop("mug"), k.on_ground(cup.x, cup.y), k.rng.randf_range(0.0, TAU))
			if not passed:
				# the one being passed: whoever takes it up is in the circle, and the circle rises
				passed = true
				k.touchable("the_cup", k.on_ground(cup.x, cup.y), "Take up the cup")
	else:
		k.light(k.on_ground(fire.x, fire.y, 0.9), Color(1.0, 0.68, 0.35), 2.8, 13.0)
		k.puffs(k.on_ground(fire.x, fire.y, 0.7), Vector3(0.15, 0.1, 0.15), 0.6, 8,
				Color(0.55, 0.55, 0.55, 0.28), 1.1, 5.0)
		var sat := false
		for p in k.ring(3 + k.rng.randi_range(0, 2), 2.1, fire, 0.2):
			var pp: Vector2 = p
			k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp) + k.rng.randf_range(-0.3, 0.3))
			if not sat:
				# whoever keeps this fire at night keeps it from here, a pace behind the stool
				sat = true
				var behind := pp + (pp - fire).normalized() * 0.8
				k.marker("by_the_fire", k.on_ground(behind.x, behind.y), true)

	# tents on a ring, each turned to the fire, with a bedroll in its mouth
	var tents := 3 + (1 if k.rng.randf() > 0.55 else 0)
	var tent_ring := k.ring(tents, 7.6, fire, 0.14)
	var tent_spots: Array = []
	for p in tent_ring:
		var pp: Vector2 = p
		var yaw := PoiKit.yaw_of(fire - pp) + k.rng.randf_range(-0.25, 0.25)
		var scale := k.rng.randf_range(0.95, 1.12)
		k.place(k.prop("tent"), k.on_ground(pp.x, pp.y), yaw, scale, true, Vector3.ZERO, true)
		tent_spots.append(pp)
		var mouth := pp + (fire - pp).normalized() * (2.4 * scale)
		k.place(k.prop("bedroll"), k.on_ground(mouth.x, mouth.y), yaw + PI * 0.5 + k.rng.randf_range(-0.2, 0.2))

	# stores against the tents
	for i in range(tent_spots.size()):
		var t: Vector2 = tent_spots[i]
		var side := Vector2(-(fire - t).y, (fire - t).x).normalized()
		var at := t + side * k.rng.randf_range(2.6, 3.4) + (fire - t).normalized() * k.rng.randf_range(-0.5, 1.5)
		match i % 3:
			0:
				k.place(k.prop("crate"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
				var at2 := at + side * 0.85
				k.place(k.prop("crate"), k.on_ground(at2.x, at2.y), k.rng.randf_range(0.0, TAU), 0.9)
			1:
				k.place(k.prop("barrel"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
			_:
				k.place(k.prop("sack"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU))
				var at3 := at + side * 0.6
				k.place(k.prop("sack"), k.on_ground(at3.x, at3.y), k.rng.randf_range(0.0, TAU), 0.9)

	# a lantern on a post beside the fire, lit
	var lp := fire + Vector2(-grain.y, grain.x) * 3.2
	var top := m.post(timber, lp, 2.7, 0.16)
	var arm := Vector3(grain.x, 0.0, grain.y) * 0.45
	m.block(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(grain)), top + arm * 0.5 - Vector3(0.0, 0.06, 0.0)),
			Vector3(0.08, 0.08, 0.9))
	var lantern := k.prop("lantern_hanging")
	if lantern == "":
		lantern = k.prop("lantern_standing")
	k.place(lantern, top + arm - Vector3(0.0, 0.55, 0.0), PoiKit.yaw_of(grain), 1.0, false)
	if not cold:
		k.light(top + arm - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.8, 0.5), 1.6, 8.0)

	# a cart at the edge, on the road side, and a hitching rail
	var edge := fire - grain * 11.0 + Vector2(-grain.y, grain.x) * k.rng.randf_range(-3.0, 3.0)
	k.place(k.prop("cart"), k.on_ground(edge.x, edge.y), PoiKit.yaw_of(grain) + k.rng.randf_range(-0.3, 0.3))
	var rail := edge + Vector2(-grain.y, grain.x) * 5.5
	k.place(k.prop("fence_post_rail"), k.on_ground(rail.x, rail.y), PoiKit.yaw_of(grain) + PI * 0.5)

	# fighters keep their arms where they can reach them
	if fighters and not cold:
		for i in 3:
			var at := fire + Vector2(sin(0.9 * i + 1.1), cos(0.9 * i + 1.1)) * 3.6
			k.place(k.prop("spear"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false,
					Vector3(k.rng.randf_range(-0.12, 0.12), 0.0, k.rng.randf_range(-0.12, 0.12)))
		var shield_at: Vector2 = tent_spots[0] + Vector2(1.6, 0.4)
		k.place(k.prop("shield"), k.on_ground(shield_at.x, shield_at.y), k.rng.randf_range(0.0, TAU), 1.0, false,
				Vector3(-0.35, 0.0, 0.0))

	# the brief
	if PoiKit.brief_says(d.brief, ["mill wheel", "millstone"]):
		var at := fire + grain.rotated(0.8) * 4.2
		var barrel := k.place(k.prop("barrel"), k.on_ground(at.x, at.y), 0.0)
		var h := PoiKit.height_of(k.prop("barrel", 0)) if barrel != null else 0.9
		k.place(k.prop("millstone"), k.on_ground(at.x, at.y, h), k.rng.randf_range(0.0, TAU), 1.0, false)
		k.place(k.prop("mug"), k.on_ground(at.x + 0.3, at.y + 0.2, h + 0.42), 0.0, 1.0, false)
		k.place(k.prop("plate"), k.on_ground(at.x - 0.35, at.y - 0.1, h + 0.42), 0.0, 1.0, false)
		# the stolen wheel is the band's table, and whoever leads them sits at its head
		var head := at + (at - fire).normalized() * 1.3
		k.marker("the_wheel_table", k.on_ground(head.x, head.y), true)
	if PoiKit.brief_says(d.brief, ["kiln"]):
		var earth := k.surface("earth", 0.7)
		var first_kiln := Vector2.INF
		for p in k.ring(3, 9.5, fire, 0.1, 0.4):
			var pp: Vector2 = p
			if first_kiln == Vector2.INF:
				first_kiln = pp
			var base := k.on_ground(pp.x, pp.y)
			m.mound(base, 2.3, 1.9, earth, "Kiln", true, 1.1, 5, 14, true)
			k.puffs(base + Vector3(0.0, 1.9, 0.0), Vector3(0.5, 0.1, 0.5), 0.9, 14, Color(0.7, 0.68, 0.64, 0.4), 1.8, 7.0)
			var logs := pp + (pp - fire).normalized() * 3.2
			k.place(k.prop("chopping_block"), k.on_ground(logs.x, logs.y), k.rng.randf_range(0.0, TAU))
		# the burner tends the first clamp, and sells from beside it
		var tend := first_kiln + (fire - first_kiln).normalized() * 3.4
		k.marker("the_clamps", k.on_ground(tend.x, tend.y), true)
	if PoiKit.brief_says(d.encounter, ["jobs"]):
		# work posted for whoever passes: a notice post the job boards' generator fills, the
		# same as a village green's
		var post := fire + Vector2(-grain.y, grain.x) * 6.0 - grain * 2.0
		k.job_board(k.on_ground(post.x, post.y), PoiKit.yaw_of(fire - post))
	if PoiKit.brief_says(d.brief, ["chain", "wind chime"]):
		# loosened links hung to ring in the wind: small bells on a line between two posts
		var a := fire + grain.rotated(-1.2) * 5.5
		var b := a + Vector2(-grain.y, grain.x) * 4.0
		var ta := m.post(timber, a, 3.0, 0.14)
		var tb := m.post(timber, b, 3.0, 0.14)
		var line := m.begin()
		var mid := (ta + tb) * 0.5
		m.rod(line, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(b - a)) * Basis(Vector3.RIGHT, PI * 0.5), mid),
				0.012, ta.distance_to(tb))
		m.commit(line, PoiKit.plain(Color(0.35, 0.3, 0.26), 0.8), "Line")
		var bells: Array = []
		for i in 5:
			var t := (float(i) + 0.5) / 5.0
			bells.append(PoiKit.transform_at(ta.lerp(tb, t) - Vector3(0.0, 0.32 + k.rng.randf_range(0.0, 0.2), 0.0),
					k.rng.randf_range(0.0, TAU), 1.0))
		k.scatter(k.prop("bell_small"), bells)
		# under the chimes, where the bridge's own link hangs among the clanless men's
		var under := (a + b) * 0.5
		k.marker("the_chimes", k.on_ground(under.x, under.y, 0.05))
		# a drystone windbreak on the weather side
		var wall := m.begin()
		var w0 := fire - grain.rotated(0.6) * 6.5
		var w1 := fire - grain.rotated(-0.6) * 6.5
		m.wall(wall, w0, w1, 1.3, 0.35)
		m.commit(wall, k.surface("stone"), "Windbreak", true)
	m.commit(timber, k.surface("timber"), "Timber")


## The Stair Head: the Wardens' camp at the top of the Hushline Stair, where a new game hands
## over (DESIGN §5.1a). The POI's own position is where the Foundling stands, and everything is
## laid out from there towards the place its `path` leads, so the first view of the game is the
## camp in front, the Warden by its fire, the waystones going away down the heath and the Choir on
## the skyline. Behind: the two Oroth piers at the head of the stair and Wren's Hearthstone.
static func _camp_stair_head(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var timber := m.begin()
	var stone := m.begin()
	var to_id := str(d.path.get("to", ""))
	var to_xz := WorldProbe.xz_of(ContentDB.get_or_empty(to_id)) if to_id != "" else Vector2.ZERO
	var ahead := Vector2(to_xz.x - k.origin.x, to_xz.y - k.origin.z) if to_xz != Vector2.ZERO else Vector2(0.0, -1.0)
	ahead = ahead.normalized() if ahead.length() > 0.5 else Vector2(0.0, -1.0)
	var right := Vector2(-ahead.y, ahead.x)
	var at := func(forward: float, side: float) -> Vector2:
		return ahead * forward + right * side
	var yaw := PoiKit.yaw_of(ahead)

	# the fire the Warden keeps, a pace off the line of sight from where the Foundling stands
	var fire: Vector2 = at.call(8.6, -1.8)
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), k.rng.randf_range(0.0, TAU), 1.15)
	var ring: Array = []
	for p in k.ring(9, 0.95, fire, 0.1):
		var pp: Vector2 = p
		ring.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU),
				k.rng.randf_range(0.09, 0.14)))
	k.scatter(k.rock("boulder"), ring)
	k.light(k.on_ground(fire.x, fire.y, 0.9), Color(1.0, 0.68, 0.35), 3.0, 14.0)
	k.puffs(k.on_ground(fire.x, fire.y, 0.7), Vector3(0.15, 0.1, 0.15), 0.7, 10,
			Color(0.58, 0.58, 0.58, 0.3), 1.2, 6.0)
	for p in k.ring(3, 2.2, fire, 0.15, 0.3):
		var pp: Vector2 = p
		k.place(k.prop("stool"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(fire - pp))

	# where the Warden stands: by the fire, turned to the Foundling
	var wren: Vector2 = at.call(6.4, 2.1)
	if not k.far:
		# a worked spot the registry finds by name and place (PoiKit.marker's convention), which
		# also stands her there facing the Foundling the moment she is stood up
		var spot := NpcSpot.new()
		spot.name = "wren_stair_head"
		spot.place_id = d.poi_id
		spot.position = k.on_ground(wren.x, wren.y)
		spot.rotation.y = atan2(wren.x, wren.y)      # -Z (its forward) points back at the Foundling
		k.root.add_child(spot)

	# two tents turned to the fire, a bedroll in each mouth
	for spec in STAIR_HEAD_TENTS:
		var t: Vector2 = at.call(float(spec[0]), float(spec[1]))
		var tyaw := PoiKit.yaw_of(fire - t)
		k.place(k.prop("tent"), k.on_ground(t.x, t.y), tyaw, float(spec[2]), true, Vector3.ZERO, true)
		var mouth := t + (fire - t).normalized() * 2.5
		k.place(k.prop("bedroll"), k.on_ground(mouth.x, mouth.y), tyaw + PI * 0.5)

	# the cart they came up in, off to the side, with what it carried: wherever that side leaves the
	# camp's own way clear (the atlas turned the way west, and the cart stood across it)
	var cart: Vector2 = _clear_of_way(d, [at.call(2.5, -9.0), at.call(2.5, 9.5), at.call(-1.5, 11.5),
			at.call(-1.5, -11.5), at.call(11.0, 13.0), at.call(11.0, -13.0)], 5.5)
	var cyaw := yaw + 0.55
	k.place(k.prop("cart"), k.on_ground(cart.x, cart.y), cyaw, 1.0, true, Vector3.ZERO, true)
	var load_at: Vector2 = cart + right * 2.2
	k.place(k.prop("crate"), k.on_ground(load_at.x, load_at.y), k.rng.randf_range(0.0, TAU))
	k.place(k.prop("sack"), k.on_ground(load_at.x + 0.8, load_at.y + 0.5), k.rng.randf_range(0.0, TAU))
	k.place(k.prop("barrel"), k.on_ground(load_at.x - 0.7, load_at.y + 0.9), 0.0)
	var rail: Vector2 = cart - ahead * 4.0
	k.place(k.prop("fence_post_rail"), k.on_ground(rail.x, rail.y), yaw + PI * 0.5)

	# the Wardens' colours: two poles either side of the way out, a bell each. The way out is where
	# the marked way leaves the camp, which in the drawn atlas is not towards the Choir but west along
	# the knoll first: the poles stood at 333 degrees and the stones went west. The cloth is
	# weathered wool in their green with an ochre border and stripe, bleached at the pole,
	# stained and torn at the hem and moving in the wind (banner_cloth.gdshader); it was one
	# flat grey-green material on six rows, and read as a painted board.
	var out := _way_out(d, ahead)
	var out_right := Vector2(-out.y, out.x)
	var out_yaw := PoiKit.yaw_of(out)
	for s in [-1.0, 1.0]:
		var cloth := ShaderMaterial.new()
		cloth.shader = BANNER_SHADER
		cloth.set_shader_parameter("seed", 0.37 * (s + 2.0))
		var pole: Vector2 = out * 17.0 + out_right * (3.4 * float(s))
		var top := m.post(timber, pole, 4.4, 0.14)
		var bar := Transform3D(Basis(Vector3.UP, out_yaw + PI * 0.5), top - Vector3(0.0, 0.25, 0.0))
		m.block(timber, bar, Vector3(1.5, 0.08, 0.08))
		m.sheet(top - Vector3(0.0, 0.3, 0.0), out_yaw, 1.2, 2.3, cloth, "Banner", 0.12, true, 6, 14)
		k.place(k.prop("bell_small"), top - Vector3(0.0, 0.25, 0.0) + Vector3(out_right.x, 0.0, out_right.y) * 0.72,
				k.rng.randf_range(0.0, TAU), 1.0, false)

	# a signpost at the way out, and a lamp on a post by the fire and another at the first stone
	var sign_at: Vector2 = out * 18.5 + out_right * 5.0
	k.place(k.prop("signpost"), k.on_ground(sign_at.x, sign_at.y), out_yaw, 1.0, true, Vector3.ZERO, true)
	for lamp in [at.call(10.0, -4.4), out * 19.5 - out_right * 5.0]:
		_lamp_post(k, m, timber, lamp as Vector2, out_yaw)

	# behind: the head of the stair. Two Oroth piers, the top steps going over the edge, and the
	# Hearthstone that heard the name first
	for s in [-1.0, 1.0]:
		var p: Vector2 = at.call(-6.2, 3.4 * float(s))
		m.drum(stone, Transform3D(Basis.IDENTITY, k.on_ground(p.x, p.y)), 0.85, 4.4, 0.25, NAN, true, 0.55)
	var head: Vector2 = at.call(-6.8, 0.0)
	# the stair goes down the face towards the Stair's own place in the Hush, or straight back
	var pad := WorldProbe.xz_of(ContentDB.get_or_empty("core:poi/hushline_stair"))
	var down := -ahead
	if pad != Vector2.ZERO:
		var to_pad := Vector2(pad.x - k.origin.x, pad.y - k.origin.z) - head
		if to_pad.length() > 20.0 and to_pad.normalized().dot(-ahead) > 0.7:
			down = to_pad.normalized()
	# a world whose land draws the stair down the bank itself (a road with this id) has it; a second
	# one straight down the face beside it would be a stair nobody built
	var stair_road: Array = WorldProbe.road_points(HUSH_STAIR_ROAD)
	if stair_road.size() < 2:
		_hush_stair(d, stone, head, down)
	else:
		_stair_road(d, stone, stair_road)
	var hs: Vector2 = at.call(-3.4, -2.6)
	k.hearthstone(k.on_ground(hs.x, hs.y), yaw, d.poi_id, d.display_name)

	# the heath round it: grey grass, a dead ash for a silhouette against the sky
	var grass: Array = []
	for i in 46:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(5.0, 22.0)
		var p := Vector2(cos(a), sin(a)) * r
		if p.distance_to(fire) < 3.0 or p.distance_to(wren) < 1.5 or p.length() < 3.0:
			continue
		grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.25)))
	k.scatter(k.flora("grey_grass"), grass, false, false, false)
	var ash: Vector2 = at.call(12.0, 18.0)
	k.place(k.tree("dead_ash_tree"), k.on_ground(ash.x, ash.y), k.rng.randf_range(0.0, TAU), 0.9, true, Vector3.ZERO, true)

	_waymarks(d, timber)
	_camp_life(k, m, timber, ahead, right, fire, cart, yaw, out)
	_ash_field(k, fire)
	_tethered_ewe(d, timber, [at.call(3.0, -15.5), at.call(-1.0, 15.5), at.call(8.0, 17.0), at.call(8.0, -17.0)])
	_wardens_watch(d)
	m.commit(timber, k.surface("timber"), "Timber", true)
	m.commit(stone, k.surface("oroth", 0.5), "Stair", true)


const EMBER_SHADER := preload("res://assets/shaders/ember_crack.gdshader")
const ASH_DRIFT_SHADER := preload("res://assets/shaders/ash_drift.gdshader")


## The burned heath round the Stair Head, the first ground every player sees: it read as one dark
## sheet. The burn's mosaic of pale ash, cracks with the fire still glowing in them in smouldering
## patches, threads of smoke off the nearest and their warm light on the ash, green shoots and a
## little fireweed coming back through it, and charred stumps. All near: the far ring draws none
## of it.
static func _ash_field(k: PoiKit, fire: Vector2) -> void:
	if k.far:
		return
	# The field draws as many numbers as it likes from the dressing's generator and then puts it
	# back as it found it (one draw on), so tuning the field never moves what the camp raises
	# after it (the tethered ewe, the Wardens' Watch).
	var rng_state := k.rng.state
	_ash_field_body(k, fire)
	k.rng.state = rng_state
	k.rng.randi()


static func _ash_field_body(k: PoiKit, fire: Vector2) -> void:
	var clear := func(p: Vector2, near: float) -> bool:
		return p.distance_to(fire) > near and p.length() > 4.0 and not k.is_water(p.x, p.y)
	_ash_cover(k, fire)
	# the embers: glowing cracks in smouldering patches of three to five, and single ones between
	var patches: Array = []
	var embers: Array = []
	for c in 8:
		var a := k.rng.randf_range(0.0, TAU)
		var centre := Vector2(cos(a), sin(a)) * k.rng.randf_range(7.0, 38.0)
		if not clear.call(centre, 7.0):
			continue
		patches.append(centre)
		for j in k.rng.randi_range(3, 5):
			var q := centre + Vector2(k.rng.randf_range(-2.2, 2.2), k.rng.randf_range(-2.2, 2.2))
			embers.append(_crack(k, q, k.rng.randf_range(2.4, 3.8)))
	for i in 20:
		var a := k.rng.randf_range(0.0, TAU)
		var p := Vector2(cos(a), sin(a)) * k.rng.randf_range(9.0, 48.0)
		if clear.call(p, 7.0):
			embers.append(_crack(k, p, k.rng.randf_range(1.6, 3.2)))
	_ground_patches(k, embers, EMBER_SHADER, "Embers", 0.05)
	# the nearest patches smoke, a thread each that the wind leans, and throw a warm light on
	# the ash round them (NightLights' pool: a real light while among the nearest to the camera)
	patches.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.length() < y.length())
	for s in mini(patches.size(), 5):
		var at: Vector2 = patches[s]
		_smoke_thread(k, k.on_ground(at.x, at.y, 0.1))
		if s < 3:
			k.light(k.on_ground(at.x, at.y, 0.5), Color(1.0, 0.46, 0.16), 1.1, 5.0)
	# green shoots and fireweed through the ash, in small clusters; charred stumps
	var shoots := k.flora("grass_clump")
	var fireweed := k.flora("heather")
	for c in 9:
		var a := k.rng.randf_range(0.0, TAU)
		var centre := Vector2(cos(a), sin(a)) * k.rng.randf_range(8.0, 40.0)
		if not clear.call(centre, 4.0):
			continue
		for j in k.rng.randi_range(3, 7):
			var q := centre + Vector2(k.rng.randf_range(-1.6, 1.6), k.rng.randf_range(-1.6, 1.6))
			var path := fireweed if (c % 3 == 0 and j % 2 == 0) else shoots
			if path != "":
				k.place(path, k.on_ground(q.x, q.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.45, 0.8), false)
	for i in 5:
		var a := k.rng.randf_range(0.0, TAU)
		var p := Vector2(cos(a), sin(a)) * k.rng.randf_range(12.0, 40.0)
		if clear.call(p, 6.0):
			k.place(k.tree("char_stump"), k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.6, 0.9), true)


## The ash itself, as a burn leaves it: one sheet over the camp's ground, its vertices standing
## on the ground a metre and a half apart, on which ash_drift.gdshader draws the burn's mosaic
## from noise in the sheet's own metres -- pale ash in patches of every size with ragged edges,
## thick and thin, the ghosts of burned shrubs between. Separate patches, however they were
## placed, read from above as confetti and close to as pale sheets laid on the ground. The
## vertex colour says where ash may lie (red: none on the fire, the pad's middle or water, and an
## uneven edge between 36 and 62 metres out) and how much (green: more near the camp).
static func _ash_cover(k: PoiKit, fire: Vector2) -> void:
	const STEP := 1.5
	const CELLS := 88
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := CELLS + 1
	var live := PackedByteArray()
	live.resize(n * n)
	for j in n:
		for i in n:
			var q := Vector2((float(i) - CELLS * 0.5) * STEP, (float(j) - CELLS * 0.5) * STEP)
			var r := q.length()
			var th := atan2(q.y, q.x)
			var edge_r := 46.0 + 5.0 * sin(3.0 * th + 1.3) + 3.0 * sin(5.0 * th + 0.4) + 2.0 * sin(8.0 * th + 2.1)
			var mask := smoothstep(4.0, 7.0, q.distance_to(fire)) * smoothstep(3.0, 5.0, r) \
					* (1.0 - smoothstep(edge_r - 8.0, edge_r + 6.0, r))
			if mask > 0.0 and k.is_water(q.x, q.y):
				mask = 0.0
			live[j * n + i] = 1 if mask > 0.0 else 0
			st.set_color(Color(mask, 1.0 - smoothstep(10.0, 40.0, r), 0.0, 1.0))
			st.set_uv(q)
			st.add_vertex(k.on_ground(q.x, q.y, 0.05))
	for j in CELLS:
		for i in CELLS:
			var i0 := j * n + i
			var i1 := i0 + 1
			var i2 := i0 + n
			var i3 := i2 + 1
			if live[i0] + live[i1] + live[i2] + live[i3] == 0:
				continue
			for idx in [i0, i1, i3, i0, i3, i2]:
				st.add_index(idx)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = ASH_DRIFT_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Ash"
	mi.visibility_range_end = 220.0
	k.root.add_child(mi)


## One glowing crack in the ash at local `p`, as a patch for `_ground_patches` (its glow, 0-4, in
## the second number).
static func _crack(k: PoiKit, p: Vector2, glow: float) -> Array:
	var length := k.rng.randf_range(0.8, 2.8)
	return [p, Vector2(length, length * 0.5), k.rng.randf_range(0.0, TAU), k.rng.randf(), glow / 4.0]


## A thread of smoke off smouldering ground: it rises a few metres a second, spreads as it
## climbs and leans off with the wind, eight or ten metres tall, grey against the sky.
static func _smoke_thread(k: PoiKit, at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "SmokeThread"
	p.position = at
	p.amount = 18
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_range_end = 400.0
	p.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(12.0, 14.0, 12.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.15
	mat.direction = Vector3.UP
	mat.spread = 6.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.1
	# the lean: a light, steady push downwind, and a little drag so the thread slows as it rises
	var lean := Vector2(k.rng.randf_range(-1.0, 1.0), k.rng.randf_range(-1.0, 1.0)).normalized() * 0.14
	mat.gravity = Vector3(lean.x, 0.0, lean.y)
	mat.damping_min = 0.04
	mat.damping_max = 0.08
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	mat.scale_curve = grow_tex
	mat.scale_min = 0.8
	mat.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.46, 0.43, 0.41, 0.0))
	ramp.set_color(1, Color(0.58, 0.56, 0.54, 0.0))
	ramp.add_point(0.12, Color(0.46, 0.43, 0.41, 0.38))
	ramp.add_point(0.55, Color(0.52, 0.50, 0.48, 0.22))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.8)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = PoiKit._soft_disc()
	quad.material = qm
	p.draw_pass_1 = quad
	k.root.add_child(p)


## Patches lying on the ground, all in one mesh drawn with `shader`: each is [local centre,
## size, bearing, seed 0-1, strength 0-1], `size.x` along the bearing (UV x) and `size.y` across
## it, its vertices standing on the ground a metre apart: a flat quad of ten metres on the heath's
## bumps was half buried, and a drift showed only where the ground dipped under it (Compatibility
## has no decals). The seed and the strength go in each vertex's colour, red and green.
static func _ground_patches(k: PoiKit, patches: Array, shader: Shader, node_name: String, lift: float) -> void:
	if patches.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for patch in patches:
		var p: Vector2 = patch[0]
		var size: Vector2 = patch[1]
		var along := Vector2(cos(float(patch[2])), sin(float(patch[2])))
		var across := Vector2(-along.y, along.x)
		var tag := Color(float(patch[3]), float(patch[4]), 0.0, 1.0)
		var nu := clampi(int(ceil(size.x)), 2, 12)
		var nv := clampi(int(ceil(size.y)), 2, 12)
		for j in nv + 1:
			for i in nu + 1:
				var u := float(i) / float(nu)
				var v := float(j) / float(nv)
				var q := p + along * (u - 0.5) * size.x + across * (v - 0.5) * size.y
				st.set_color(tag)
				st.set_uv(Vector2(u, v))
				st.add_vertex(k.on_ground(q.x, q.y, lift))
		for j in nv:
			for i in nu:
				var i0 := base + j * (nu + 1) + i
				var i1 := i0 + 1
				var i2 := i0 + nu + 1
				var i3 := i2 + 1
				for idx in [i0, i1, i3, i0, i3, i2]:
					st.add_index(idx)
		base += (nu + 1) * (nv + 1)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# drawn after the ash sheet, which lies at the same height and would otherwise cover them
	# whenever the two sorted the other way
	mat.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = node_name
	mi.visibility_range_end = 160.0
	k.root.add_child(mi)


## The Wardens' banners at the Stair Head (weathered wool, torn at the hem, moving in the wind).
const BANNER_SHADER := preload("res://assets/shaders/banner_cloth.gdshader")
## The Stair Head's tents, as [forward, side, scale] from where the Foundling stands.
const STAIR_HEAD_TENTS := [[13.5, -8.2, 1.0], [15.0, 7.6, 1.08]]


## What makes the Wardens' camp lived in, drawn after the rest of it so that everything the camp
## drew before keeps its place. The playtest found the start "a little sparse", and nothing in it
## moved but the Warden and a wisp of smoke. Now:
## * a pot hangs on three poles over the fire and steams;
## * the smoke goes up high enough to be seen from the Stair;
## * the Wardens' spears stand by a tent with a shield at their foot;
## * there is a pack at each tent's mouth, peat to feed the fire, a pail, and rope by the cart;
## * crows sit on the colours' poles and the lamps and wheel over the heath ahead, and anybody who
##   walks near puts them up.
static func _camp_life(k: PoiKit, m: PoiMasonry, timber: SurfaceTool, ahead: Vector2, right: Vector2,
		fire: Vector2, cart: Vector2, yaw: float, out: Vector2) -> void:
	var out_right := Vector2(-out.y, out.x)
	var at := func(forward: float, side: float) -> Vector2:
		return ahead * forward + right * side
	# a pot on three poles over the fire, and its steam
	var apex := k.on_ground(fire.x, fire.y, 1.6)
	for j in 3:
		var a := TAU * float(j) / 3.0 + 0.5
		var foot: Vector2 = fire + Vector2(cos(a), sin(a)) * 1.0
		var foot3 := k.on_ground(foot.x, foot.y)
		# a little past the apex, as three poles lashed together cross
		m.limb(timber, foot3, apex + (apex - foot3).normalized() * 0.2, 0.035)
	var pot_at := apex - Vector3(0.0, 1.05, 0.0)
	m.limb(timber, apex, pot_at + Vector3(0.0, 0.45, 0.0), 0.012)
	k.place(k.prop("cooking_pot"), pot_at, k.rng.randf_range(0.0, TAU), 0.9, false)
	k.puffs(pot_at + Vector3(0.0, 0.45, 0.0), Vector3(0.1, 0.03, 0.1), 0.5, 6,
			Color(0.9, 0.9, 0.9, 0.24), 0.6, 2.4)
	# the fire's smoke, high: a column over the rim that is seen from the Stair and across the heath
	k.puffs(k.on_ground(fire.x, fire.y, 2.6), Vector3(0.3, 0.2, 0.3), 1.0, 14,
			Color(0.6, 0.6, 0.62, 0.18), 2.4, 9.0)
	# a pack at each tent's mouth beside the bedroll; the spears by the east tent, a shield at their foot
	for i in STAIR_HEAD_TENTS.size():
		var spec: Array = STAIR_HEAD_TENTS[i]
		var t: Vector2 = at.call(float(spec[0]), float(spec[1]))
		var to_fire := (fire - t).normalized()
		var beside := Vector2(-to_fire.y, to_fire.x)
		var pack := t + to_fire * 1.9 + beside * 1.15
		k.place(k.prop("sack"), k.on_ground(pack.x, pack.y), k.rng.randf_range(0.0, TAU), 0.8)
		if i == 1:
			var stand := t + to_fire * 1.7 - beside * 1.6
			for s in [-1.0, 1.0]:
				var spear: Vector2 = stand + beside * 0.18 * float(s)
				k.place(k.prop("spear"), k.on_ground(spear.x, spear.y), PoiKit.yaw_of(to_fire), 1.0, false,
						Vector3(0.07 * float(s), 0.0, 0.05))
			var shield := stand + to_fire * 0.35
			k.place(k.prop("shield"), k.on_ground(shield.x, shield.y), PoiKit.yaw_of(to_fire), 1.0, false,
					Vector3(-0.3, 0.0, 0.0))
	# the peat that feeds the fire, a pail by it, and the rope off the cart
	var peat: Vector2 = at.call(7.0, -4.6)
	k.place(k.prop("peat_stack"), k.on_ground(peat.x, peat.y), yaw + 0.3)
	var pail: Vector2 = at.call(11.6, -3.0)
	k.place(k.prop("bucket"), k.on_ground(pail.x, pail.y), k.rng.randf_range(0.0, TAU))
	var rope: Vector2 = at.call(1.6, -6.4)
	k.place(k.prop("rope_coil"), k.on_ground(rope.x, rope.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	# crows: on the colours' poles and the lamps, and two wheeling over the heath ahead
	if k.far:
		return
	var perches: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var pole: Vector2 = out * 17.0 + out_right * (3.4 * float(s))
		perches.append(k.on_ground(pole.x, pole.y, 4.4))
	for lamp in [out * 19.5 - out_right * 5.0, at.call(10.0, -4.4)]:
		var l: Vector2 = lamp
		perches.append(k.on_ground(l.x, l.y, 2.7))
	var wheel: Vector2 = at.call(30.0, -2.0)
	var crows := Crows.new()
	crows.name = "Crows"
	crows.radius = 14.0
	crows.height = 11.0
	k.root.add_child(crows)
	crows.setup(perches, k.on_ground(wheel.x, wheel.y), perches.size() + 2, k.rng.randi())


## The Wardens' Watch: a stone tower beside the camp's way where it tops the Choir's Crown, with
## a stair up its side to a walled platform WATCH_TOP_M above the ground. From the Stair Head the
## heath's own ridge hides the country; from here, ten metres up, the Grandfather, the Cracked
## Toll, the Choir's ring and Merrowby's roofs are all on the skyline (the sightline model counts
## 16 far things from the top, 9 from the way at its foot). It stands WATCH_ALONG_M along the
## way, WATCH_OFF_M off it on the side the Grandfather is, and is built from the Stair Head so
## that it is in the camp's near ring, and solid, while anybody stands on it.
const WATCH_ALONG_M := 360.0
const WATCH_OFF_M := 10.0
const WATCH_TOP_M := 10.0
const WATCH_HALF_M := 2.4
const WATCH_STAIR_W := 2.2
## Rise per metre of the Watch's stair: 27 degrees, walked as a slope.
const WATCH_STAIR_SLOPE := 0.5
const WATCH_RISER_M := 0.36
const WATCH_WALL_M := 1.0
## Past this from the camp the Watch would drop to the far ring (384 m) and lose its collider.
const WATCH_NEAR_M := 370.0
const GRANDFATHER := "core:place/grandfather"
## What looking out from the Watch's far wall names.
const WATCH_DIALOGUE := "core:dialogue/the_wardens_watch"


## Where the Watch stands on the camp's way (local xz) and which way the way runs there, or
## [] when the way is shorter than WATCH_ALONG_M.
static func _watch_spot(d: PoiDressing) -> Array:
	var k := d.kit
	var pts: Array[Vector2] = []
	for p in way_of(d.path):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]) - k.origin.x, float(p[1]) - k.origin.z))
	var s := 0.0
	for i in range(pts.size() - 1):
		var length := pts[i].distance_to(pts[i + 1])
		if length > 0.01 and s + length >= WATCH_ALONG_M:
			var along := (pts[i + 1] - pts[i]) / length
			return [pts[i] + along * (WATCH_ALONG_M - s), along]
		s += length
	return []


static func _wardens_watch(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var spot := _watch_spot(d)
	if spot.is_empty():
		return
	var on_way: Vector2 = spot[0]
	var along: Vector2 = spot[1]
	# the side of the way the Grandfather is on
	var side := Vector2(-along.y, along.x)
	var far_xz := WorldProbe.xz_of(ContentDB.get_or_empty(GRANDFATHER))
	if far_xz != Vector2.ZERO and side.dot(far_xz - Vector2(k.origin.x, k.origin.z) - on_way) < 0.0:
		side = -side
	var c := on_way + side * WATCH_OFF_M
	if c.length() > WATCH_NEAR_M:
		if not k.far:
			Log.warn("PoiBuilders", "%s: the Watch would stand %.0f m out, past the near ring; not built" % [d.poi_id, c.length()])
		return
	var yaw := atan2(along.x, along.y)
	var basis := Basis(Vector3.UP, yaw)
	var local := func(u: float, v: float) -> Vector2:
		return c + along * u + side * v
	var low := INF
	for u in [-WATCH_HALF_M, WATCH_HALF_M]:
		for v in [-WATCH_HALF_M, WATCH_HALF_M]:
			var q: Vector2 = local.call(u, v)
			low = minf(low, k.on_ground(q.x, q.y).y)
	var top := k.on_ground(c.x, c.y).y + WATCH_TOP_M
	var st := m.begin()
	# the tower, from below the ground at its lowest corner to the platform
	var body := Vector3(WATCH_HALF_M * 2.0, top - (low - 0.5), WATCH_HALF_M * 2.0)
	var body_xf := Transform3D(basis, Vector3(c.x, (top + low - 0.5) * 0.5, c.y))
	m.block(st, body_xf, body)
	k.collider(body, body_xf, "stone")
	# a string course under the platform's lip, so the tower has a top and is not a post
	m.block(st, Transform3D(basis, Vector3(c.x, top - 0.15, c.y)), Vector3(WATCH_HALF_M * 2.0 + 0.3, 0.3, WATCH_HALF_M * 2.0 + 0.3))
	# the wall round the platform: whole on three sides, and on the way's side only south of where
	# the stair lands
	var landing_u := WATCH_HALF_M - WATCH_STAIR_W
	var walls := [
		[0.0, WATCH_HALF_M, WATCH_HALF_M * 2.0, true],          # north (along +u)
		[0.0, -WATCH_HALF_M, WATCH_HALF_M * 2.0, true],         # south
		[WATCH_HALF_M, 0.0, WATCH_HALF_M * 2.0, false],         # the far side (+v)
		[-WATCH_HALF_M, (landing_u - WATCH_HALF_M) * 0.5, landing_u + WATCH_HALF_M, false],  # the way's side
	]
	for w in walls:
		var across_u: bool = w[3]
		var at: Vector2 = local.call(float(w[1]), float(w[0]))
		var size := Vector3(float(w[2]), WATCH_WALL_M, 0.35) if across_u else Vector3(0.35, WATCH_WALL_M, float(w[2]))
		var xf := Transform3D(basis, Vector3(at.x, top + WATCH_WALL_M * 0.5, at.y))
		m.block(st, xf, size)
		k.collider(size, xf, "stone")
	# the stair: up the tower's side on the way's side, from the south, filled down to the ground,
	# landing level with the platform where the wall stops
	var stair_v := -WATCH_HALF_M - WATCH_STAIR_W * 0.5
	var landing: Vector2 = local.call(landing_u + WATCH_STAIR_W * 0.5, stair_v)
	var landing_xf := Transform3D(basis, Vector3(landing.x, (top + low - 0.5) * 0.5, landing.y))
	var landing_size := Vector3(WATCH_STAIR_W, top - (low - 0.5), WATCH_STAIR_W)
	m.block(st, landing_xf, landing_size)
	k.collider(landing_size, landing_xf, "stone")
	var run := 0.0
	var foot_u := landing_u
	var step_top := top
	var tread := WATCH_RISER_M / WATCH_STAIR_SLOPE
	while step_top > low and run < 40.0:
		foot_u = landing_u - run - tread
		var q: Vector2 = local.call(foot_u + tread * 0.5, stair_v)
		var ground := k.on_ground(q.x, q.y).y
		step_top -= WATCH_RISER_M
		if step_top <= ground:
			break
		m.block(st, Transform3D(basis, Vector3(q.x, (step_top + ground - 0.4) * 0.5, q.y)),
				Vector3(WATCH_STAIR_W, step_top - (ground - 0.4), tread))
		run += tread
	var bottom: Vector2 = local.call(landing_u - run, stair_v)
	var bottom3 := Vector3(bottom.x, k.on_ground(bottom.x, bottom.y).y, bottom.y)
	# walked as one slope, half a riser under the treads' fronts so a foot is never held off them
	var sunk := WATCH_RISER_M * 0.5
	_flight_collider(k, Vector3(landing.x - along.x * WATCH_STAIR_W * 0.5, top - sunk, landing.y - along.y * WATCH_STAIR_W * 0.5),
			bottom3 - Vector3(0.0, sunk, 0.0), atan2(-along.x, -along.y), WATCH_STAIR_W)
	# a wall on the stair's open side: level along the landing, then down the flight to where the
	# stair is a metre off the ground
	var open_v := stair_v - WATCH_STAIR_W * 0.5 - 0.18
	var l_north: Vector2 = local.call(landing_u + WATCH_STAIR_W, open_v)
	var l_south: Vector2 = local.call(landing_u, open_v)
	_watch_rail(k, m, st, Vector3(l_north.x, top, l_north.y), Vector3(l_south.x, top, l_south.y))
	var wall_to := landing_u - run * maxf(0.0, 1.0 - 1.0 / maxf(top - bottom3.y, 1.0))
	var b2: Vector2 = local.call(wall_to, open_v)
	var b_y := top - (landing_u - wall_to) * WATCH_STAIR_SLOPE
	_watch_rail(k, m, st, Vector3(l_south.x, top, l_south.y), Vector3(b2.x, b_y, b2.y))
	m.commit(st, k.surface("stone", 0.6), "Watch", true)
	k.marker("the_view", Vector3(c.x, top, c.y), true, true, WATCH_HALF_M)
	# the look-out: the whole far wall is something to lean on and look from, and says what is there
	var lean: Vector2 = local.call(0.0, WATCH_HALF_M - 0.35)
	var touch := k.touchable("look_out", Vector3(lean.x, top, lean.y), "Look out", WATCH_DIALOGUE, "", false)
	if touch != null:
		touch.basis = basis
		var old_shape := touch.get_node_or_null("Shape")
		if old_shape != null:
			touch.remove_child(old_shape)
			old_shape.free()
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(0.7, 1.0, WATCH_HALF_M * 2.0 - 0.5)
		shape.shape = box
		shape.position.y = 1.0
		touch.add_child(shape)


## The stair's outer wall from `a` (its top) to `b`, sloped with it, WATCH_WALL_M above the treads.
static func _watch_rail(k: PoiKit, m: PoiMasonry, st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var along := b - a
	var flat := Vector2(along.x, along.z).length()
	if flat < 0.5:
		return
	var pitch := atan2(a.y - b.y, flat)
	var basis := Basis(Vector3.UP, atan2(along.x, along.z)) * Basis(Vector3.RIGHT, pitch)
	var size := Vector3(0.3, WATCH_WALL_M + 0.4, along.length())
	var xf := Transform3D(basis, (a + b) * 0.5 + Vector3(0.0, WATCH_WALL_M * 0.5 - 0.2, 0.0))
	m.block(st, xf, size)
	k.collider(size, xf, "stone")


## How long the Wardens' ewe's tether is, and how far any stake stands from the camp's way.
const TETHER_M := 1.8
const TETHER_CLEAR_M := 5.0


## The Wardens' ewe, on a tether at a stake at the first of `spots` (local xz) that is clear of the
## camp's way: the camp's milk, and the one beast in it besides the crows. The stake is timber;
## the ewe keeps within her tether of it.
static func _tethered_ewe(d: PoiDressing, timber: SurfaceTool, spots: Array) -> void:
	var k := d.kit
	var stake := _clear_of_way(d, spots, TETHER_CLEAR_M)
	d.masonry.post(timber, stake, 0.7, 0.05)
	if k.far:
		return
	var sheep := Livestock.paths_of("sheep")
	if sheep.is_empty():
		return
	var ewe := Livestock.new()
	ewe.name = "Tethered"
	ewe.seed_with(absi(("tethered:" + d.poi_id).hash()))
	ewe.keep("sheep", sheep, k.on_ground(stake.x, stake.y), TETHER_M, 1)
	d.add_child(ewe)


## How far out from a place its grazing flock is put, how far they wander, and how many.
const GRAZING_OUT_M := 24.0
const GRAZING_RADIUS_M := 6.0
const GRAZING_COUNT := 5


## Sheep grazing by a place whose sentence has them ("sheep grazing"), whatever its kind built:
## a flock on the flattest dry ground GRAZING_OUT_M out from it. The Wellspring's is the first
## flock a Foundling passes, where the living country begins below the ash.
static func _grazing(d: PoiDressing) -> void:
	var k := d.kit
	var sheep := Livestock.paths_of("sheep")
	if sheep.is_empty():
		return
	var best := Vector2.INF
	var best_fall := INF
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p := Vector2(sin(a), cos(a)) * GRAZING_OUT_M
		var here := k.on_ground(p.x, p.y).y
		var fall := 0.0
		for q: Vector2 in [Vector2.ZERO, Vector2(GRAZING_RADIUS_M, 0.0), Vector2(-GRAZING_RADIUS_M, 0.0),
				Vector2(0.0, GRAZING_RADIUS_M), Vector2(0.0, -GRAZING_RADIUS_M)]:
			if k.is_water(p.x + q.x, p.y + q.y):
				fall = INF
				break
			fall = maxf(fall, absf(k.on_ground(p.x + q.x, p.y + q.y).y - here))
		if fall < best_fall:
			best_fall = fall
			best = p
	if best == Vector2.INF:
		return
	var flock := Livestock.new()
	flock.name = "Grazing"
	flock.seed_with(absi(("grazing:" + d.poi_id).hash()))
	flock.keep("sheep", sheep, k.on_ground(best.x, best.y), GRAZING_RADIUS_M, GRAZING_COUNT)
	d.add_child(flock)


## Which way the POI's own marked way leaves it: towards its first point twelve metres or more out,
## or `otherwise` when it has none.
static func _way_out(d: PoiDressing, otherwise: Vector2) -> Vector2:
	var k := d.kit
	for p in way_of(d.path):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			var at := Vector2(float(p[0]) - k.origin.x, float(p[1]) - k.origin.z)
			if at.length() >= 12.0:
				return at.normalized()
	return otherwise


## The first of `spots` (local xz) that stands at least `reach` metres from every leg of the POI's
## own way, or the first of them when none does.
static func _clear_of_way(d: PoiDressing, spots: Array, reach: float) -> Vector2:
	var k := d.kit
	var pts: Array[Vector2] = []
	for p in way_of(d.path):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]) - k.origin.x, float(p[1]) - k.origin.z))
	for spot in spots:
		var at: Vector2 = spot
		var clear := true
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1]).distance_to(at) < reach:
				clear = false
				break
		if clear:
			return at
	return spots[0]


## The built road that is the stair down the bank from the camp, in a world whose land draws one.
const HUSH_STAIR_ROAD := "core:road/stair_head_hushline_stair"


## The Hushline Stair itself: from its head at the camp, straight down the cliff to the Hush and a
## few steps on into the water, where the mist takes it. Every step follows the ground (its top no
## more than 0.62 m below the last, and never less than 0.15 m above the face), and is filled down
## into the face, so the stair reads as built into the cliff and never stands off it. A parapet runs
## either side, and one sloped collider per flight of ten lets it be walked. It is built for the far
## ring too, because it is what the opening's last shot climbs to reach the camp.
static func _hush_stair(d: PoiDressing, stone: SurfaceTool, head: Vector2, down: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var tread := 0.46
	var width := 5.2
	var side := Vector2(-down.y, down.x)
	var yaw := atan2(down.x, down.y)
	var basis := Basis(Vector3.UP, yaw)
	var top := k.on_ground(head.x, head.y).y
	var flight_from := Vector3(head.x, top, head.y)
	var in_flight := 0
	var under := 0
	var last := head
	for i in 320:
		var p := head + down * tread * (float(i) + 0.5)
		last = p
		var g := k.ground(k.origin.x + p.x, k.origin.z + p.y) - k.origin.y
		var surface_y := k.water_y(p.x, p.y)
		if not is_nan(surface_y) and g < surface_y - 0.5:
			under += 1
			# a few steps on into the water, then the mist has it
			if under > 6:
				break
		var rise := clampf(top - (g + 0.15), 0.0, 0.62)
		top -= rise
		var bottom := minf(g, top) - 1.0
		var h := top - bottom
		m.block(stone, Transform3D(basis, Vector3(p.x, top - h * 0.5, p.y)), Vector3(width, h, tread * 1.04))
		for s in [-1.0, 1.0]:
			var w := p + side * float(s) * (width * 0.5 + 0.25)
			var wall_h := top + 0.9 - bottom
			m.block(stone, Transform3D(basis, Vector3(w.x, bottom + wall_h * 0.5, w.y)), Vector3(0.5, wall_h, tread * 1.04))
		in_flight += 1
		if in_flight >= 10:
			_flight_collider(k, flight_from, Vector3(p.x + down.x * tread * 0.5, top, p.y + down.y * tread * 0.5), yaw, width)
			flight_from = Vector3(p.x + down.x * tread * 0.5, top, p.y + down.y * tread * 0.5)
			in_flight = 0
	if in_flight > 0:
		var end := last + down * tread * 0.5
		_flight_collider(k, flight_from, Vector3(end.x, top, end.y), yaw, width)
	# the mist the stair goes down into, at its foot: lying on the water, not on the bed under it
	for i in 3:
		var at := last + down * float(i - 1) * 9.0
		var lie := k.on_ground(at.x, at.y).y
		var wet := k.water_y(at.x, at.y)
		if not is_nan(wet):
			lie = maxf(lie, wet)
		k.puffs(Vector3(at.x, lie + 0.9, at.y), Vector3(8.0, 1.2, 6.0), 0.08, 30, Color(0.58, 0.6, 0.64, 0.3), 10.0, 12.0)


## The Hushline Stair where the land draws it as a road (HUSH_STAIR_ROAD): stone treads where it
## climbs, and a parapet on its downhill side where the ground falls away, so the switchbacks down
## the face read as a stair built into the bank and not a track worn in it. The treads lie on the
## ground, which stays the walking surface; the parapet is solid, waist high, and keeps a walker
## off the drop. It stops short of a bend, where the next leg of the road comes back through it.
const STAIR_TREAD_M := 0.9
## Rise per metre of road above which it is laid in steps.
const STAIR_STEEP := 0.07
const STAIR_HALF_WIDTH := 1.7
## How much lower one side must be, a metre past the road's edge, for it to need a parapet.
const PARAPET_FALL_M := 0.6
## How far apart two parapet samples may be and still be one wall.
const PARAPET_RUN_M := 4.0
const PARAPET_HEIGHT := 0.75
const PARAPET_SIDE := 0.35
## A bend sharper than this has no parapet within PARAPET_CLEAR_M of it, on either leg.
const PARAPET_BEND_DEG := 30.0
const PARAPET_CLEAR_M := 5.0


static func _stair_road(d: PoiDressing, stone: SurfaceTool, points: Array) -> void:
	var k := d.kit
	var m := d.masonry
	var pts: Array[Vector2] = []
	for p in points:
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]) - k.origin.x, float(p[1]) - k.origin.z))
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var dir := (b - a) / length
		var side := Vector2(-dir.y, dir.x)
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.y))
		var bends_in := i > 0 and _bend_deg(pts[i - 1], a, b) > PARAPET_BEND_DEG
		var bends_out := i + 2 < pts.size() and _bend_deg(a, b, pts[i + 2]) > PARAPET_BEND_DEG
		var run_start := Vector3.INF
		var run_last := Vector3.INF
		var run_fall := 0.0
		var s := 0.0
		while s < length:
			var p := a + dir * s
			var here := k.on_ground(p.x, p.y).y
			var ahead := p + dir * minf(STAIR_TREAD_M, length - s)
			var next := k.on_ground(ahead.x, ahead.y).y
			var tread := p.distance_to(ahead)
			var wet := k.water_y(p.x, p.y)
			var dry := is_nan(wet) or here > wet
			if dry and tread > 0.2 and absf(next - here) / tread > STAIR_STEEP:
				# a tread: its top at the higher end, filled down into the slope
				var top := maxf(here, next) + 0.04
				var bottom := minf(here, next) - 0.3
				var mid := p + dir * (tread * 0.5)
				m.block(stone, Transform3D(basis, Vector3(mid.x, (top + bottom) * 0.5, mid.y)),
						Vector3(STAIR_HALF_WIDTH * 2.0, top - bottom, tread))
			# the parapet goes on whichever side falls away, clear of the bends
			var fall := 0.0
			var near_bend := (bends_in and s < PARAPET_CLEAR_M) \
					or (bends_out and s + STAIR_TREAD_M > length - PARAPET_CLEAR_M)
			if dry and not near_bend:
				var reach := STAIR_HALF_WIDTH + 1.0
				var left := k.on_ground(p.x + side.x * reach, p.y + side.y * reach).y
				var right := k.on_ground(p.x - side.x * reach, p.y - side.y * reach).y
				if absf(left - right) > PARAPET_FALL_M:
					fall = 1.0 if left < right else -1.0
			var wall := p + side * fall * (STAIR_HALF_WIDTH + PARAPET_SIDE * 0.5)
			var at := Vector3(wall.x, k.on_ground(wall.x, wall.y).y, wall.y)
			if fall != 0.0 and fall == run_fall and run_start != Vector3.INF \
					and Vector2(run_last.x, run_last.z).distance_to(wall) < PARAPET_RUN_M:
				run_last = at
			else:
				if run_start != Vector3.INF:
					_parapet(k, m, stone, run_start, run_last, dir)
				run_start = at if fall != 0.0 else Vector3.INF
				run_last = run_start
				run_fall = fall
			s += STAIR_TREAD_M
		if run_start != Vector3.INF:
			_parapet(k, m, stone, run_start, run_last, dir)


## How far the road turns at `b`, coming from `a` and going on to `c`, in degrees.
static func _bend_deg(a: Vector2, b: Vector2, c: Vector2) -> float:
	if a.distance_to(b) < 0.01 or b.distance_to(c) < 0.01:
		return 0.0
	return rad_to_deg(absf((b - a).angle_to(c - b)))


## One run of parapet along `dir` from `a` to `b` on the ground, carried on a tread's length past
## `b` so runs abut: a waist-high wall sloped with the road, set 0.3 m into the ground, with its
## collider.
static func _parapet(k: PoiKit, m: PoiMasonry, stone: SurfaceTool, a: Vector3, b: Vector3, dir: Vector2) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var slope := (b.y - a.y) / flat if flat > 0.01 else 0.0
	var run := flat + STAIR_TREAD_M
	var end := Vector3(a.x + dir.x * run, a.y + slope * run, a.z + dir.y * run)
	var pitch := atan2(a.y - end.y, run)
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis(Vector3.RIGHT, pitch)
	var tall := PARAPET_HEIGHT + 0.3
	var mid := (a + end) * 0.5 + Vector3(0.0, PARAPET_HEIGHT - tall * 0.5, 0.0)
	var xf := Transform3D(basis, mid)
	var size := Vector3(PARAPET_SIDE, tall, Vector2(run, end.y - a.y).length())
	m.block(stone, xf, size)
	k.collider(size, xf, "stone")


## One flight of a stair as a single sloped box from `a` to `b` (its top face on the steps' tops).
static func _flight_collider(k: PoiKit, a: Vector3, b: Vector3, yaw: float, width: float) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.2:
		return
	var flat := Vector2(along.x, along.z).length()
	var pitch := atan2(a.y - b.y, flat)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var mid := (a + b) * 0.5 - basis * Vector3(0.0, 0.25, 0.0)
	k.collider(Vector3(width, 0.5, length), Transform3D(basis, mid), "stone")


## A lantern hung from an arm on a post, lit.
static func _lamp_post(k: PoiKit, m: PoiMasonry, timber: SurfaceTool, at: Vector2, yaw: float) -> void:
	var top := m.post(timber, at, 2.7, 0.15)
	var arm := Vector3(sin(yaw), 0.0, cos(yaw)) * 0.45
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw), top + arm * 0.5 - Vector3(0.0, 0.06, 0.0)),
			Vector3(0.08, 0.08, 0.9))
	var lantern := k.prop("lantern_hanging")
	if lantern == "":
		lantern = k.prop("lantern_standing")
	k.place(lantern, top + arm - Vector3(0.0, 0.55, 0.0), yaw, 1.0, false, Vector3.ZERO, true)
	k.light(top + arm - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.8, 0.5), 1.6, 9.0)


## The way a POI's `path` names, marked on the ground: a waystone every twenty-odd metres along
## its points, alternating sides, and a lamp at every third. Built as silhouette pieces too, so
## the stones are still there when the POI's own cell has dropped to the far ring behind a
## player who has walked most of the way.
static func _waymarks(d: PoiDressing, timber: SurfaceTool) -> void:
	var k := d.kit
	var m := d.masonry
	var via: Array = way_of(d.path)
	if via.size() < 2:
		return
	var pts: Array[Vector2] = []
	for p in via:
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]) - k.origin.x, float(p[1]) - k.origin.z))
	# a way written for another build does not start here: no stones rather than stones across
	# somebody else's country
	if pts.is_empty() or pts[0].length() > 40.0:
		if not k.far:
			Log.warn("PoiBuilders", "%s: its way starts %.0f m off, not at it; no waystones" % [d.poi_id,
					pts[0].length() if not pts.is_empty() else INF])
		return
	var stones: Array = []
	var every := 22.0
	var carried := every * 0.8
	var n := 0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.01:
			continue
		var dir := seg / length
		var side := Vector2(-dir.y, dir.x)
		var s := every - carried
		while s <= length:
			var p := a + dir * s + side * (1.7 if n % 2 == 0 else -1.7)
			var g := k.on_ground(p.x, p.y, -0.15)
			var turn := k.rng.randf_range(0.0, TAU)
			var size := k.rng.randf_range(0.48, 0.55)
			stones.append([g, turn, size, Vector3(k.rng.randf_range(-0.05, 0.05), 0.0, k.rng.randf_range(-0.05, 0.05))])
			if n % 3 == 1:
				_lamp_post(k, m, timber, a + dir * s - side * (1.7 if n % 2 == 0 else -1.7), PoiKit.yaw_of(dir))
			n += 1
			s += every
		carried = length - (s - every)
	# A waystone stands about WAYSTONE_M whatever stone it is cut from: the sizes were set for
	# Hearthvale's 3.8 m chalk, and a region that borrows another's stone (PoiKit.lenders) gets a
	# different height -- Cinderlea's granite is 2.2 m.
	var stone_path := k.rock("standing_stone")
	var fit := WAYSTONE_M / (0.5 * maxf(PoiKit.height_of(stone_path), 0.5)) if stone_path != "" else 1.0
	var placed: Array = []
	for st in stones:
		placed.append(PoiKit.transform_at(st[0], float(st[1]), float(st[2]) * fit, st[3]))
	k.scatter(stone_path, placed, true, true)


## A waystone's height above the ground, at the middle of its sizes.
const WAYSTONE_M := 1.9


## The points a POI's `path` goes by: the built road it names (`built_road`) when the land drew
## one, the `via` points it was written with otherwise. The way stops where reaching the place it
## goes to counts (QuestLog.REACH_RADIUS_M): the atlas's road to the Choir ran on to the Choir's
## own position, which is inside its first colossus, and the stones followed it into the stone.
static func way_of(path: Dictionary) -> Array:
	var points: Array = WorldProbe.road_points(str(path.get("built_road", "")))
	if points.size() < 2:
		points = path.get("via", [])
	var to := WorldProbe.xz_of(ContentDB.get_or_empty(str(path.get("to", "")))) if str(path.get("to", "")) != "" else Vector2.ZERO
	if to == Vector2.ZERO or points.size() < 2:
		return points
	var out: Array = []
	for p in points:
		out.append(p)
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2 and out.size() >= 2 \
				and Vector2(float(p[0]), float(p[1])).distance_to(to) <= WAY_STOPS_SHORT_M:
			break
	return out


## How far short of the place it goes to a marked way stops: inside QuestLog.REACH_RADIUS_M (45 m),
## so the last stone stands where the objective has been reached.
const WAY_STOPS_SHORT_M := 40.0


# --- shrines ----------------------------------------------------------------------------------------

## A place a name is kept: the stone, its Hearthstone at the foot, candles, a small bell, the
## offerings people leave; and whatever the brief says this shrine actually is.
static func shrine(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var approach := PoiKit.yaw_of(grain) + PI       # things face the way you come in
	var centre := Vector2.ZERO
	var stone_at := centre - grain * 1.2
	var hearth_at := centre + grain * 1.6
	var brief := d.brief
	var timber := m.begin()
	var stonework := m.begin()
	var placed_hearth := false

	if PoiKit.brief_says(brief, ["hawthorn"]):
		# a stone chair with the tree grown up through its back; the stone sits in its lap
		var basis := Basis(Vector3.UP, approach)
		var g := k.on_ground(stone_at.x, stone_at.y)
		m.block(stonework, Transform3D(basis, g + Vector3(0.0, 0.28, 0.0)), Vector3(1.5, 0.56, 1.1))
		m.block(stonework, Transform3D(basis, g + basis * Vector3(0.0, 1.0, -0.55) + Vector3(0.0, 0.0, 0.0)), Vector3(1.5, 2.0, 0.42))
		for s in [-1.0, 1.0]:
			m.block(stonework, Transform3D(basis, g + basis * Vector3(float(s) * 0.66, 0.62, 0.0)), Vector3(0.22, 0.68, 1.1))
		k.collider(Vector3(1.5, 2.0, 1.2), Transform3D(basis, g + Vector3(0.0, 1.0, 0.0) + basis * Vector3(0.0, 0.0, -0.2)), "stone")
		var behind := stone_at - grain * 0.9
		k.place(k.tree("hawthorn"), k.on_ground(behind.x, behind.y), k.rng.randf_range(0.0, TAU), 1.9, true, Vector3.ZERO, true)
		var lap := stone_at + grain * 0.95
		_shrine_stone(d, k.on_ground(lap.x, lap.y), approach)
		placed_hearth = true
		var pie := stone_at + grain * 0.2 + Vector2(-grain.y, grain.x) * 0.45
		k.place(k.prop("plate"), Vector3(pie.x, g.y + 0.56, pie.y), 0.0, 1.0, false)
		k.place(k.prop("loaf"), Vector3(pie.x, g.y + 0.6, pie.y), 0.3, 1.0, false)
		# a pilgrim resting here sits in the chair's shade, off the path to the stone
		var rest := stone_at + grain * 3.2 + Vector2(-grain.y, grain.x) * 2.4
		k.marker("the_pilgrims_rest", k.on_ground(rest.x, rest.y), true)
	elif PoiKit.brief_says(brief, ["pebble", "shingle"]):
		# a cairn of lake pebbles, each a name; the stone stands out of its top
		var pebbles: Array = []
		var cairn_r := 2.5
		for i in 190:
			var u := k.rng.randf()
			var r := cairn_r * sqrt(u)
			var a := k.rng.randf_range(0.0, TAU)
			var h := 1.5 * maxf(1.0 - r / cairn_r, 0.0) * k.rng.randf_range(0.75, 1.0)
			pebbles.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, h),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.13, 0.22),
					Vector3(k.rng.randf_range(-0.5, 0.5), 0.0, k.rng.randf_range(-0.5, 0.5))))
		k.scatter(k.rock("boulder"), pebbles, false, true)
		var cyl := CylinderShape3D.new()
		cyl.radius = cairn_r * 0.9
		cyl.height = 1.2
		k.collider_shape(cyl, Transform3D(Basis.IDENTITY, k.on_ground(stone_at.x, stone_at.y, 0.6)), "stone")
		_shrine_stone(d, k.on_ground(stone_at.x, stone_at.y, 0.95), approach)
		placed_hearth = true
		# the newest pebbles, not yet on the heap
		var spill: Array = []
		for i in 14:
			var a := k.rng.randf_range(0.0, TAU)
			var r := cairn_r + k.rng.randf_range(0.2, 1.6)
			spill.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.1, 0.16)))
		k.scatter(k.rock("boulder", 1), spill)
	elif PoiKit.brief_says(brief, ["peat island", "under the water"]):
		# a hummock of peat with the stone on top, lantern poles about it, and the old bell
		# just breaking the surface of the pool beside
		var base := k.on_ground(stone_at.x, stone_at.y)
		m.mound(base, 6.5, 1.15, k.surface("earth", 0.6), "Island", true, 1.4, 6, 18, true)
		_shrine_stone(d, base + Vector3(0.0, 1.12, 0.0), approach)
		placed_hearth = true
		for p in k.ring(4, 5.2, stone_at, 0.08):
			var pp: Vector2 = p
			var top := m.post(timber, pp, 2.6, 0.14)
			k.place(k.prop("lantern_hanging"), top - Vector3(0.0, 0.5, 0.0), k.rng.randf_range(0.0, TAU), 1.0, false)
			k.light(top - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.78, 0.45), 1.5, 8.0)
		var pool_at := stone_at + Vector2(-grain.y, grain.x) * 9.5
		var pg := k.on_ground(pool_at.x, pool_at.y)
		m.pool(pool_at, 4.2, pg.y + 0.12, k.still_water(pg.y - 2.5, Color.WHITE, 0.6), "Pool")
		var bell := k.prop("bell_medium")
		k.place(bell, Vector3(pool_at.x, pg.y + 0.3 - PoiKit.height_of(bell) * 2.4, pool_at.y), 0.4, 2.4, false,
				Vector3(0.12, 0.0, -0.08))
		var reeds: Array = []
		for i in 40:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(4.2, 6.5)
			reeds.append(PoiKit.transform_at(k.on_ground(pool_at.x + sin(a) * r, pool_at.y + cos(a) * r),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
		k.scatter(k.flora("reeds"), reeds, false, false, false)
	elif PoiKit.brief_says(brief, ["oil"]):
		# oiled till it shines like a chestnut
		var stone := k.place(k.rock("standing_stone"), k.on_ground(stone_at.x, stone_at.y), approach, 1.2, true, Vector3.ZERO, true)
		if stone != null:
			var oiled := PoiKit.plain(Color(0.36, 0.2, 0.11), 0.18)
			for mi in stone.find_children("*", "MeshInstance3D", true, false):
				var mesh_inst := mi as MeshInstance3D
				var src := mesh_inst.mesh.surface_get_material(0) if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0 else null
				if src is StandardMaterial3D:
					oiled.albedo_texture = (src as StandardMaterial3D).albedo_texture
					oiled.normal_enabled = (src as StandardMaterial3D).normal_enabled
					oiled.normal_texture = (src as StandardMaterial3D).normal_texture
				mesh_inst.material_override = oiled
		for i in 3:
			var at := stone_at + Vector2(-grain.y, grain.x) * (1.1 + 0.35 * i) + grain * 0.6
			k.place(k.prop("jug"), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false)
		var rag := stone_at + Vector2(-grain.y, grain.x) * -1.2 + grain * 0.7
		k.place(k.prop("cloth"), k.on_ground(rag.x, rag.y), k.rng.randf_range(0.0, TAU), 1.0, false)
		var moss: Array = []
		for i in 26:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(1.6, 7.0)
			moss.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, 0.02),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
		k.scatter(k.flora("moss_patch"), moss, false, false, false)
	elif PoiKit.brief_says(brief, ["finger"]):
		# the sinkhole's rim: slabs leaning in; the giant's finger stands in the middle
		# the rim is open on the approach side, so the stone can be seen and walked to
		var slabs: Array = []
		for p in k.ring(13, 8.6, stone_at, 0.1):
			var pp: Vector2 = p
			var to_c := (stone_at - pp).normalized()
			if absf(angle_difference(PoiKit.yaw_of(pp - stone_at), PoiKit.yaw_of(grain))) < 0.55:
				continue
			slabs.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y, -0.6), PoiKit.yaw_of(to_c),
					k.rng.randf_range(0.5, 0.75), Vector3(k.rng.randf_range(0.35, 0.55), 0.0, k.rng.randf_range(-0.15, 0.15))))
		k.scatter(k.rock("cliff_slab"), slabs, true, true)
		# The finger stood on end. The forge builds it lying along +X with its butt at x = −0.38,
		# so turning it a quarter about Z puts that butt below the origin: it has to be lifted
		# by exactly that much or the bone hangs in the air above its own socket.
		var finger := k.rock("bone_finger")
		var meta: Dictionary = PoiKit.meta(finger).get("bounds", {})
		var lo: Array = meta.get("min", [-0.38, 0.0, 0.0])
		var hi: Array = meta.get("max", [5.78, 1.6, 0.0])
		var fs := 2.0
		var length := (float(hi[0]) - float(lo[0])) * fs
		k.place(finger, k.on_ground(stone_at.x, stone_at.y, -float(lo[0]) * fs), approach, fs,
				true, Vector3(0.0, 0.0, PI * 0.5), true)
		var cyl := CylinderShape3D.new()
		cyl.radius = float(hi[1]) * fs * 0.42
		cyl.height = length
		k.collider_shape(cyl, Transform3D(Basis.IDENTITY, k.on_ground(stone_at.x, stone_at.y, length * 0.5)), "stone")
		var foot := stone_at + grain * (float(hi[1]) * fs * 0.5 + 1.6)
		_shrine_stone(d, k.on_ground(foot.x, foot.y), approach)
		placed_hearth = true
		var crust: Array = []
		for i in 30:
			var a := k.rng.randf_range(0.0, TAU)
			var r := k.rng.randf_range(2.0, 7.5)
			crust.append(PoiKit.transform_at(k.on_ground(stone_at.x + sin(a) * r, stone_at.y + cos(a) * r, 0.02),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
		k.scatter(k.flora("lichen_crust"), crust, false, false, false)
	elif PoiKit.brief_says(brief, ["fallen bell", "inside a", "crack in its side"]):
		# a bell the size of a house on its side, its mouth to the approach; the stone inside
		var bell := k.prop("bell_medium")
		var bs := 6.0
		var br := PoiKit.half_width_of(bell) * bs
		var bh := PoiKit.height_of(bell) * bs
		# the bell lies along the grain with its mouth toward the approach: the standing bell's
		# up (mouth to crown) is turned onto local +Z, and local +Z faces away from the approach
		var mouth := centre + grain * (bh * 0.5)
		var g := k.on_ground(centre.x, centre.y)
		var axis := Basis(Vector3.UP, approach)
		var basis := axis * Basis(Vector3.RIGHT, PI * 0.5)
		var bell_node := k.place(bell, Vector3(mouth.x, g.y + br, mouth.y), 0.0, bs, false, Vector3.ZERO, true)
		if bell_node != null:
			bell_node.transform = Transform3D(basis.scaled(Vector3.ONE * bs), Vector3(mouth.x, g.y + br, mouth.y))
		# its shell as a ring of slabs around that axis, open at the bottom where it rests on
		# the ground, so you can walk in through the mouth and stand inside
		var segs := 12
		var middle := g + Vector3(0.0, br, 0.0)
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			if absf(angle_difference(a, PI)) < 0.5:
				continue
			var around := axis * Basis(Vector3.BACK, a)
			var at := middle + around * Vector3(0.0, br * 0.92, 0.0)
			k.collider(Vector3(br * TAU / float(segs) * 1.05, 0.5, bh * 0.9), Transform3D(around, at), "stone")
		var inside := centre - grain * (bh * 0.1)
		_shrine_stone(d, k.on_ground(inside.x, inside.y), approach)
		placed_hearth = true
		for s in [-1.0, 1.0]:
			var bz := mouth + grain * 0.8 + Vector2(-grain.y, grain.x) * float(s) * (br + 0.8)
			k.place(k.prop("brazier"), k.on_ground(bz.x, bz.y), 0.0)
			k.light(k.on_ground(bz.x, bz.y, 1.1), Color(1.0, 0.62, 0.3), 2.0, 9.0)
		var bench := mouth + grain * 3.4
		k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), approach + PI)
	else:
		k.place(k.rock("standing_stone"), k.on_ground(stone_at.x, stone_at.y), approach, 1.25, true,
				Vector3(0.0, 0.0, k.rng.randf_range(-0.05, 0.05)), true)

	# a shrine keeps a Hearthstone when its data says so: every wayside Hearthstone does, and the
	# Turning Cairn, a heap of pilgrims' tied bells on the Stair Path, does not (`_shrine_stone`)
	if not placed_hearth:
		_shrine_stone(d, k.on_ground(hearth_at.x, hearth_at.y), approach)

	# candles, a bell, offerings and flowers: what tending looks like
	var candles: Array = []
	for i in 10 + k.rng.randi_range(0, 8):
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(0.9, 2.2)
		var at := hearth_at + Vector2(sin(a), cos(a)) * r
		candles.append(PoiKit.transform_at(k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.6)))
	k.scatter(k.prop("candle"), candles, false, false, false)
	k.light(k.on_ground(hearth_at.x, hearth_at.y, 0.5), Color(1.0, 0.76, 0.5), 1.1, 6.0)
	if not PoiKit.brief_says(brief, ["bell"]):
		var frame_at := stone_at + Vector2(-grain.y, grain.x) * 2.6
		var hang := m.frame(timber, frame_at, approach, 0.9, 2.1, 0.12)
		k.place(k.prop("bell_small"), hang - Vector3(0.0, 0.3, 0.0), approach, 1.0, false)
	var gifts := ["mug", "jug", "plate", "book", "loaf", "candlestick"]
	for i in 5:
		var a := approach + k.rng.randf_range(-1.1, 1.1)
		var at := hearth_at + Vector2(sin(a), cos(a)) * k.rng.randf_range(0.9, 1.5)
		k.place(k.prop(gifts[i % gifts.size()]), k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var flower := k.flora("poppy")
	match k.region:
		"skerrow":
			flower = k.flora("heather")
		"sedgemire":
			flower = k.flora("marsh_marigold")
		"briarwold":
			flower = k.flora("foxglove")
		"cinderlea":
			flower = k.flora("grey_grass")
	var flowers: Array = []
	for i in 24:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(2.2, 5.5)
		var at := centre + Vector2(sin(a), cos(a)) * r
		flowers.append(PoiKit.transform_at(k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.3)))
	k.scatter(flower, flowers, false, false, false)
	if k.culture == "vale":
		for p in k.ring(3, 4.6, stone_at, 0.2, approach + 2.2):
			var pp: Vector2 = p
			k.place(k.prop("gravestone"), k.on_ground(pp.x, pp.y), PoiKit.yaw_of(stone_at - pp) + k.rng.randf_range(-0.3, 0.3),
					1.0, true, Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.1, 0.1)))
	m.commit(stonework, k.surface("stone", 0.6), "Stonework", true)
	m.commit(timber, k.surface("timber"), "Timber")


## A shrine's Hearthstone, where its data asks for one. A shrine kept one whatever its data said,
## and the Turning Cairn, a shrine of pilgrims' bells that keeps none, got one in its cairn.
static func _shrine_stone(d: PoiDressing, at: Vector3, yaw: float) -> void:
	if d.wants_hearthstone:
		d.kit.hearthstone(at, yaw, d.poi_id, d.display_name)


# --- the Hearthstone a settlement keeps ---------------------------------------------------------------

## A place tagged `shrine` keeps a Hearthstone: on its green, a little off the middle so nothing
## else that stands at the centre (a landmark, a spawning body) stands inside it, with the
## candles and the bench that say it is tended. Its id is the place's, which is what the main
## quest's `rest_at` objectives name.
static func hearth(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var approach := PoiKit.yaw_of(grain) + PI
	var off := maxf(7.0, _landmark_clearance(d) + 4.0)
	var at := grain.rotated(0.9) * off
	var stone := at - grain * 0.9
	k.place(k.rock("standing_stone"), k.on_ground(stone.x, stone.y), approach, 0.9, true, Vector3.ZERO, true)
	k.hearthstone(k.on_ground(at.x, at.y), approach, d.poi_id, d.display_name)
	var candles: Array = []
	for i in 8:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(0.8, 1.6)
		var c := at + Vector2(sin(a), cos(a)) * r
		candles.append(PoiKit.transform_at(k.on_ground(c.x, c.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.prop("candle"), candles, false, false, false)
	k.light(k.on_ground(at.x, at.y, 0.5), Color(1.0, 0.76, 0.5), 1.0, 5.0)
	var bench := at + grain * 2.6
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), approach + PI)
	var timber := m.begin()
	var hang := m.frame(timber, at + Vector2(-grain.y, grain.x) * 2.2, approach, 0.9, 2.1, 0.12)
	k.place(k.prop("bell_small"), hang - Vector3(0.0, 0.3, 0.0), approach, 1.0, false)
	m.commit(timber, k.surface("timber"), "Timber")


## How far a landmark standing on this place's centre reaches, from the forge's own meta,
## so the stone is set beyond the Grandfather's trunk rather than inside it.
static func _landmark_clearance(d: PoiDressing) -> float:
	var world := World.instance
	if world == null:
		return 0.0
	var reach := 0.0
	for entry_v in world.pois():
		var entry: Dictionary = entry_v
		if not entry.has("scene"):
			continue
		var p: Array = entry.get("pos", [0, 0, 0])
		var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if at.distance_to(d.world_position) > 6.0:
			continue
		reach = maxf(reach, PoiKit.radius_of(str(entry["scene"])))
	return reach


# --- towers ----------------------------------------------------------------------------------------

## A plain watch's or a beacon's drum, to the corbel its crown stands on (PlaceDiscovery's
## LANDMARK_M for a tower is this and its crown).
const WATCH_DRUM_M := 10.4


## Something to climb or to see from: a drum of stone courses standing, broken or lying down
## its valley; a lookout on stilts; a hide in a living oak; a toll-house under snow; a
## colossus's head with a window for an eye. Every tower is a silhouette piece, because a
## tower's whole job is to be seen from the next POI over.
static func tower(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var b := d.brief
	var grain := k.grain()
	var approach := PoiKit.yaw_of(grain) + PI
	if PoiKit.brief_says(b, ["lying on its side", "fell", "tumbled"]):
		_tower_tumbled(d, grain)
	elif PoiKit.brief_says(b, ["stilts"]):
		_tower_stilts(d, grain)
	elif PoiKit.brief_says(b, ["living trunk", "hide"]):
		_tower_hide(d, grain)
	elif PoiKit.brief_says(b, ["snow"]):
		_tower_toll_house(d, grain)
	# "head" alone is a headland, a head of a valley, a beacon ahead: the colossus is named
	elif PoiKit.brief_says(b, ["colossus", "fallen head"]):
		_tower_head(d, grain)
	else:
		# A beacon or a plain watch: a drum of courses with a door to the approach, and a crown
		# that reads against the sky from the next valley. It stood 7.6 m with a ragged top, which
		# the sightlines credited with ten and which read as a stub past a kilometre; it is 10.4 m
		# of drum now, a corbelled course over it, and on that the beacon's iron cage with the
		# fire-bowl in it, or the watch's merlons with gaps where they fell -- eleven to twelve
		# metres all told. All of it is silhouette, so the far ring carries the same crown.
		var stone := m.begin()
		var g := k.on_ground(0.0, 0.0)
		var r := 2.9
		var h := WATCH_DRUM_M
		var beacon := PoiKit.brief_says(b, ["bell", "fire-bowl", "beacon"])
		var broken := 0.05 if beacon else 0.08
		m.drum(stone, Transform3D(Basis.IDENTITY, g), r, h, broken, approach)
		# the corbelled course the crown stands on, stepped out over the wall below it; laid from
		# the lowest torn sector so it never floats over a gap
		var sill := g.y + h * (1.0 - broken) - 0.05
		var corbel := 0.45
		m.drum(stone, Transform3D(Basis.IDENTITY, Vector3(g.x, sill, g.z)), r + 0.3, corbel, 0.0, NAN, false)
		var crown_y := sill + corbel
		m.commit(stone, k.surface("stone", 0.6), "Drum", true)
		if not beacon:
			# The merlons, a few of them fallen: the watch's broken crenellation. A mesh of their
			# own: blocks are indexed and the drum's courses are not, and laid into one SurfaceTool
			# the index dropped the drum, which left the merlons floating ten metres up.
			var crown := m.begin()
			var merlons := 12
			var fallen := [k.rng.randi_range(0, merlons - 1), k.rng.randi_range(0, merlons - 1)]
			for i in merlons:
				if i in fallen:
					continue
				var a := TAU * (float(i) + 0.5) / float(merlons)
				var tall := 1.15 - (0.35 if (i + 1) % merlons in fallen or (i + merlons - 1) % merlons in fallen else 0.0)
				var at := Vector3(sin(a) * (r + 0.05), crown_y + tall * 0.5, cos(a) * (r + 0.05))
				m.block(crown, Transform3D(Basis(Vector3.UP, a), Vector3(g.x, 0.0, g.z) + at), Vector3(0.95, tall, 0.55))
			m.commit(crown, k.surface("stone", 0.6), "Crown", true)
		var rubble: Array = []
		for i in 14:
			var a := k.rng.randf_range(0.0, TAU)
			var rr := r + k.rng.randf_range(0.6, 4.5)
			rubble.append(PoiKit.transform_at(k.on_ground(sin(a) * rr, cos(a) * rr), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.25, 0.6)))
		k.scatter(k.rock("boulder"), rubble, true)
		if beacon:
			# The fire-bowl: an Oroth bell upturned in the crown, crown down and mouth up, sunk into
			# the corbel rather than balanced on top, and round it the iron cage a beacon is known
			# by: eight bars flaring out from the sill and bound with two hoops.
			var bell := k.prop("bell_medium")
			var bs := 2.6
			var bh := PoiKit.height_of(bell) * bs
			var rim := crown_y + bh * 0.3
			var top := Vector3(0.0, rim, 0.0)
			k.place(bell, top, 0.0, bs, false, Vector3(PI, 0.0, 0.0), true)
			var iron := m.begin()
			var bars := 8
			var cage_h := 2.0
			for i in bars:
				var a := TAU * float(i) / float(bars)
				var foot := Vector3(sin(a) * (r - 0.35), crown_y - 0.1, cos(a) * (r - 0.35))
				var head := Vector3(sin(a) * (r + 0.1), crown_y + cage_h, cos(a) * (r + 0.1))
				m.limb(iron, Vector3(g.x, 0.0, g.z) + foot, Vector3(g.x, 0.0, g.z) + head, 0.07)
			for hoop in [0.55, 1.0]:
				var rr := lerpf(r - 0.35, r + 0.1, float(hoop))
				var y := crown_y - 0.1 + cage_h * float(hoop)
				for i in 16:
					var a0 := TAU * float(i) / 16.0
					var a1 := TAU * float(i + 1) / 16.0
					m.limb(iron, Vector3(g.x + sin(a0) * rr, y, g.z + cos(a0) * rr), Vector3(g.x + sin(a1) * rr, y, g.z + cos(a1) * rr), 0.05)
			m.commit(iron, PoiKit.plain(Color(0.12, 0.11, 0.1), 0.55, 0.6), "Cage", true)
			k.light(top + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.6, 0.28), 4.5, 26.0)
			k.puffs(top + Vector3(0.0, 0.5, 0.0), Vector3(0.4, 0.1, 0.4), 1.4, 16, Color(0.4, 0.38, 0.36, 0.45), 2.2, 6.0)
		# whoever uses it now left their stores by the door
		var door := grain * (r + 1.6)
		k.place(k.prop("barrel"), k.on_ground(door.x + 1.2, door.y), k.rng.randf_range(0.0, TAU))
		k.place(k.prop("crate"), k.on_ground(door.x - 1.3, door.y + 0.3), k.rng.randf_range(0.0, TAU))
		k.place(k.prop("rope_coil"), k.on_ground(door.x - 1.3, door.y + 1.1), k.rng.randf_range(0.0, TAU), 1.0, false)


## The drum fell and lies down the valley, its stair a corridor: a hollow tube of courses on
## its side, open at both ends, the stump it broke from still standing.
static func _tower_tumbled(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.downhill()
	if down == Vector2.ZERO:
		down = grain
	var r := 2.6
	var length := 16.0
	var stone := m.begin()
	# the stump, at the pad's centre
	var base := k.on_ground(-down.x * 3.0, -down.y * 3.0)
	m.drum(stone, Transform3D(Basis.IDENTITY, base), r + 0.15, 3.2, 0.55, PoiKit.yaw_of(down) + PI)
	# the fallen drum, its axis along the fall; the frame's Y runs along the drum
	var start := down * 1.5
	var mid := start + down * (length * 0.5)
	var g_mid := k.on_ground(mid.x, mid.y)
	var yaw := PoiKit.yaw_of(down)
	var frame := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(start.x, g_mid.y + r * 0.9, start.y))
	# a lying drum's tear is at the open ends, not down its length, so barely any of it
	m.drum(stone, frame, r, length, 0.07, NAN)
	m.commit(stone, k.surface("stone", 0.7), "Drum", true)
	# the break: rubble between stump and drum, and along the fall
	var rubble: Array = []
	for i in 22:
		var t := k.rng.randf_range(-0.2, 1.1)
		var side := k.rng.randf_range(-1.0, 1.0) * (r + 1.8) * (1.0 if k.rng.randf() > 0.5 else -1.0)
		var p := start + down * (length * t) + Vector2(-down.y, down.x) * side
		rubble.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.25, 0.7)))
	k.scatter(k.rock("boulder"), rubble, true)
	var scree: Array = []
	for i in 12:
		var p := start + down * k.rng.randf_range(-3.0, 4.0) + Vector2(-down.y, down.x) * k.rng.randf_range(-4.0, 4.0)
		scree.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.2)))
	k.scatter(k.rock("scree"), scree)
	# the bell the Wardens want back, rolled out of the top
	var bell_at := start + down * (length + 2.5) + Vector2(-down.y, down.x) * 2.0
	k.place(k.prop("bell_medium"), k.on_ground(bell_at.x, bell_at.y), k.rng.randf_range(0.0, TAU), 1.7, true,
			Vector3(0.0, 0.0, 1.25))
	# somebody lives in the corridor now
	var inside := start + down * (length * 0.5)
	k.place(k.prop("bedroll"), k.on_ground(inside.x, inside.y), yaw)
	# the bandits' hall is the lying stair, and the one who says the Hush keeps the stump's top
	var hall := start + down * (length * 0.3)
	k.marker("stair_hall", k.on_ground(hall.x, hall.y))
	k.marker("the_parapet", base + Vector3(0.0, 3.25, 0.0), false, true, r)
	k.place(k.prop("crate"), k.on_ground(inside.x + down.x * 2.0, inside.y + down.y * 2.0), yaw)
	var fire := start + down * (length + 1.0)
	# the fallen stair's foot, where the Wardens' hand-bell is being used as a cup: by the fire at
	# the drum's lower mouth, on the side away from the big bell. It lay inside the drum, on the
	# ground under the stair's own lowest course, where nobody could stoop for it.
	var cup := fire - Vector2(-down.y, down.x) * 1.6
	k.marker("fallen_stair", k.on_ground(cup.x, cup.y, 0.05))
	k.place(k.prop("campfire"), k.on_ground(fire.x, fire.y), 0.0)
	k.light(k.on_ground(fire.x, fire.y, 0.8), Color(1.0, 0.66, 0.34), 2.4, 12.0)


## A reedfolk lookout on stilts: a plank platform seven metres up on four posts, a roof, a
## ladder, a bell the bittern nests in.
static func _tower_stilts(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var planks := m.begin()
	var posts := m.begin()
	var yaw := PoiKit.yaw_of(grain)
	var side := Vector2(-grain.y, grain.x)
	var deck_y := k.on_ground(0.0, 0.0).y + 6.8
	var half := 1.7
	m.plank_deck(planks, posts, -grain * half, grain * half, half * 2.0, deck_y, 3.4, true)
	# a pitched roof of planks over it, on two more posts
	var basis := Basis(Vector3.UP, yaw)
	for s in [-1.0, 1.0]:
		var xf := Transform3D(basis * Basis(Vector3.BACK, float(s) * 0.62),
				Vector3(side.x, 0.0, side.y) * float(s) * 0.85 + Vector3(0.0, deck_y + 2.6, 0.0))
		m.block(planks, xf, Vector3(2.2, 0.08, half * 2.0 + 0.8))
	for s in [-1.0, 1.0]:
		var p := side * float(s) * 1.55
		m.post(posts, p, 3.0 + (deck_y - k.on_ground(p.x, p.y).y), 0.14)
	# the ladder, leaning on the approach side
	var foot := grain * (half + 2.2)
	var g := k.on_ground(foot.x, foot.y)
	var top := Vector3(grain.x * half, deck_y, grain.y * half)
	var rail_len := g.distance_to(top)
	var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -atan2(2.2, deck_y - g.y))
	for s in [-1.0, 1.0]:
		var at := (g + top) * 0.5 + Vector3(side.x, 0.0, side.y) * float(s) * 0.28
		m.block(posts, Transform3D(lean, at), Vector3(0.07, rail_len, 0.07))
	for i in range(1, int(rail_len / 0.38)):
		var t := float(i) * 0.38 / rail_len
		m.block(posts, Transform3D(lean, g.lerp(top, t)), Vector3(0.6, 0.05, 0.05))
	k.collider(Vector3(0.7, rail_len, 0.2), Transform3D(lean, (g + top) * 0.5), "wood")
	m.commit(planks, k.surface("planks", 0.7), "Planks", true)
	m.commit(posts, k.surface("timber", 0.6), "Posts", true)
	# the bell under the roof, and what a lookout keeps up there
	k.place(k.prop("bell_small"), Vector3(0.0, deck_y + 2.0, 0.0), yaw, 1.3, false)
	k.place(k.prop("basket"), Vector3(-side.x * 0.9, deck_y, -side.y * 0.9), yaw, 1.0, false)
	k.place(k.prop("lantern_hanging"), Vector3(grain.x * half * 0.8, deck_y + 1.9, grain.y * half * 0.8), yaw, 1.0, false)
	k.light(Vector3(grain.x * half * 0.8, deck_y + 1.7, grain.y * half * 0.8), Color(1.0, 0.8, 0.5), 1.8, 10.0)
	var reeds: Array = []
	for i in 46:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(2.5, 9.0)
		reeds.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)
	k.place(k.prop("rowboat"), k.on_ground(-grain.x * 6.0 + side.x * 2.0, -grain.y * 6.0 + side.y * 2.0), yaw + 0.4)


## A hide built round a living trunk: a giant oak with a railed platform about it nine metres
## up, and the rope ladder pulled up after them.
static func _tower_hide(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var oak := k.tree("giant_oak")
	if oak == "":
		oak = k.tree("oak")
	k.place(oak, k.on_ground(0.0, 0.0), k.rng.randf_range(0.0, TAU), 1.0, true, Vector3.ZERO, true)
	var planks := m.begin()
	var posts := m.begin()
	var deck_y := k.on_ground(0.0, 0.0).y + 9.0
	var inner := 1.9
	var outer := 4.6
	var yaw := PoiKit.yaw_of(grain)
	var basis := Basis(Vector3.UP, yaw)
	for i in 4:
		var side_basis := basis * Basis(Vector3.UP, PI * 0.5 * float(i))
		var centre := side_basis * Vector3(0.0, 0.0, (inner + outer) * 0.5)
		var xf := Transform3D(side_basis, Vector3(centre.x, deck_y - 0.07, centre.z))
		m.block(planks, xf, Vector3(outer * 2.0, 0.15, outer - inner))
		k.collider(Vector3(outer * 2.0, 0.25, outer - inner), xf, "wood")
		# A hide is a screen you stand behind: a plank parapet round the outer edge, chest
		# high, with its cap rail on top. A bare rail photographed as scaffolding.
		var rail := side_basis * Vector3(0.0, 0.0, outer - 0.12)
		if i != 0:
			m.block(planks, Transform3D(side_basis, Vector3(rail.x, deck_y + 0.55, rail.z)),
					Vector3(outer * 2.0, 1.1, 0.12))
			k.collider(Vector3(outer * 2.0, 1.1, 0.12), Transform3D(side_basis, Vector3(rail.x, deck_y + 0.55, rail.z)), "wood")
		m.block(posts, Transform3D(side_basis, Vector3(rail.x, deck_y + 1.16, rail.z)), Vector3(outer * 2.0, 0.11, 0.2))
		for s in [-1.0, 1.0]:
			var p := side_basis * Vector3(float(s) * (outer - 0.12), 0.0, outer - 0.12)
			m.block(posts, Transform3D(side_basis, Vector3(p.x, deck_y + 0.6, p.z)), Vector3(0.14, 1.25, 0.14))
		# a strut from the platform's edge back to the trunk
		var strut_from := side_basis * Vector3(0.0, 0.0, outer - 0.3)
		var strut_to := side_basis * Vector3(0.0, 0.0, inner * 0.5)
		var mid := (strut_from + strut_to) * 0.5
		var pitch := atan2(2.2, outer - 0.3 - inner * 0.5)
		m.block(posts, Transform3D(side_basis * Basis(Vector3.RIGHT, -pitch), Vector3(mid.x, deck_y - 1.15, mid.z)),
				Vector3(0.16, 0.16, (strut_from - strut_to).length() * 1.05))
	m.commit(planks, k.surface("planks", 0.6), "Planks", true)
	m.commit(posts, k.surface("timber", 0.5), "Timber", true)
	# the rope ladder, pulled up: coiled on the edge with a stub hanging
	var edge := basis * Vector3(0.0, 0.0, outer - 0.6)
	k.place(k.prop("rope_coil"), Vector3(edge.x, deck_y, edge.z), yaw, 1.6, false)
	var rope := m.begin()
	m.rod(rope, Transform3D(Basis.IDENTITY, Vector3(edge.x, deck_y - 1.4, edge.z)), 0.03, 2.6)
	m.commit(rope, PoiKit.plain(Color(0.5, 0.42, 0.3), 0.9), "Rope")
	# what the poachers keep up there, and what they left below
	k.place(k.prop("crate"), Vector3(-edge.x, deck_y, -edge.z), yaw, 1.0, false)
	# where they stand to shoot: the deck, between the trunk and the parapet
	var deck_at := -edge * 0.8
	k.marker("the_platform", Vector3(deck_at.x, deck_y + 0.05, deck_at.z), false, true, outer)
	k.place(k.prop("spear"), Vector3(-edge.z * 0.9, deck_y, edge.x * 0.9), yaw, 1.0, false, Vector3(0.0, 0.0, 0.3))
	var below := -grain * 5.5
	k.place(k.prop("campfire"), k.on_ground(below.x, below.y), 0.0)
	k.place(k.prop("sack"), k.on_ground(below.x + 1.1, below.y - 0.4), 0.0)
	var ferns: Array = []
	for i in 30:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(3.0, 11.0)
		ferns.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("fern"), ferns, false, false, false)


## The clan toll-house at the pass: a square drystone tower half under old snow, its bell in
## a frame on the top, stopped mid-swing.
static func _tower_toll_house(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var yaw := PoiKit.yaw_of(grain)
	var basis := Basis(Vector3.UP, yaw)
	var half := 3.2
	var h := 6.2
	var stone := m.begin()
	var corners: Array = []
	for i in 4:
		var c := basis * Vector3(half * (1.0 if i in [0, 1] else -1.0), 0.0, half * (1.0 if i in [1, 2] else -1.0))
		corners.append(Vector2(c.x, c.z))
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		m.wall(stone, a, b, h, 0.12 if i == 2 else 0.0, true, 0.38)
	m.doorway(stone, grain * (half + 0.05), yaw, 1.3, 2.2)
	# a slab roof, half gone
	var roof := Transform3D(basis, Vector3(0.0, k.on_ground(0.0, 0.0).y + h + 0.15, 0.0))
	m.block(stone, roof.translated_local(Vector3(-half * 0.5, 0.0, 0.0)), Vector3(half + 0.6, 0.3, half * 2.0 + 0.6))
	m.commit(stone, k.surface("stone", 0.55), "Walls", true)
	var timber := m.begin()
	var hang := m.frame(timber, Vector2.ZERO, yaw, 2.4, h + 2.8, 0.3)
	m.commit(timber, k.surface("timber"), "Frame", true)
	# the bell, frozen mid-swing
	var bell := k.prop("bell_medium")
	var bs := 2.2
	k.place(bell, hang - Vector3(0.0, PoiKit.height_of(bell) * bs, 0.0) + basis * Vector3(0.0, 0.35, 0.4), yaw, bs, false,
			Vector3(0.62, 0.0, 0.0), true)
	# old snow, drifted against the walls and over the roof. Wind-piled snow lies long and low
	# against a wall rather than heaping up it, and it is never the white of paper.
	var snow := PoiKit.plain(Color(0.82, 0.85, 0.9), 0.7)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var mid := (a + b) * 0.5
		var out := mid.normalized()
		var at := mid + out * 2.2
		m.mound(k.on_ground(at.x, at.y, -0.35), 4.6, 1.5 + k.rng.randf_range(-0.3, 0.4), snow, "Drift", true,
				2.6, 6, 18, true, 0.16)
	for c in corners:
		var cc: Vector2 = c
		var at := cc * 1.3
		m.mound(k.on_ground(at.x, at.y, -0.3), 2.8, 0.95, snow, "Drift", true, 2.4, 5, 14, true, 0.2)
	m.mound(Vector3(0.0, k.on_ground(0.0, 0.0).y + h + 0.25, 0.0) + basis * Vector3(-half * 0.5, 0.0, 0.0), half * 1.05, 0.55,
			snow, "RoofSnow", false, 2.6, 4, 14, true, 0.18)
	# the gate-warden's things by the door
	var door := grain * (half + 2.0)
	k.place(k.prop("brazier"), k.on_ground(door.x + 1.2, door.y), 0.0)
	k.light(k.on_ground(door.x + 1.2, door.y, 1.1), Color(1.0, 0.62, 0.3), 2.0, 9.0)
	k.place(k.prop("signpost"), k.on_ground(door.x - 2.2, door.y + 1.0), yaw + PI)
	k.place(k.prop("drystone_wall"), k.on_ground(door.x - 4.0, door.y - 1.0), yaw + PI * 0.5)
	k.place(k.prop("drystone_wall"), k.on_ground(door.x + 4.4, door.y - 1.0), yaw + PI * 0.5)
	# The gate-warden's post: out on the road past the drift the door's wall has piled (4.6 m
	# round a point 5.4 m out, and it stands to the knee over the brazier), where the road comes
	# up to the snow, on whichever side the walls and the post by the door leave clear.
	var things := [[Vector2(door.x + 1.2, door.y), 1.4], [Vector2(door.x - 2.2, door.y + 1.0), 1.4],
			[Vector2(door.x - 4.0, door.y - 1.0), 3.0], [Vector2(door.x + 4.4, door.y - 1.0), 3.0]]
	var post := grain * 11.2
	for a in [0.0, 0.25, -0.25, 0.5, -0.5]:
		var c := grain.rotated(float(a)) * 11.2
		var clear := true
		for t in things:
			var thing: Array = t
			var where: Vector2 = thing[0]
			clear = clear and c.distance_to(where) >= float(thing[1])
		if clear:
			post = c
			break
	k.marker("the_gate_post", k.on_ground(post.x, post.y), true)


## A colossus's fallen head, hollowed for a watch: a great stone head sunk to the jaw in ash,
## its eye a lit window, a stair of slabs up to it.
static func _tower_head(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var yaw := PoiKit.yaw_of(grain)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.18) * Basis(Vector3.BACK, -0.12)
	var g := k.on_ground(0.0, 0.0)
	var rx := 5.6
	var ry := 7.0
	var rz := 6.2
	var centre := g + Vector3(0.0, ry - 3.4, 0.0)
	var st := m.begin()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 16
	# the cranium, flattened at the back the way a skull is, not a hen's egg
	st.append_from(sphere, 0, Transform3D(basis, centre + basis * Vector3(0.0, 0.0, 0.5))
			.scaled_local(Vector3(rx, ry, rz * 0.94)))
	# A head has to be a head from whichever side you come at it, because what the head faces
	# is decided by the ground and where you walk up from is not. So: a brow band right round
	# it, cheeks either side, a jaw and chin below, a nose, and a socket on *both* sides —
	# built as an ovoid with one face on it, this photographed as an egg.
	m.block(st, Transform3D(basis, centre + basis * Vector3(0.0, 1.9, 0.0)), Vector3(rx * 1.92, 1.3, rz * 1.86))
	for s in [-1.0, 1.0]:
		m.block(st, Transform3D(basis * Basis(Vector3.UP, float(s) * 0.5),
				centre + basis * Vector3(float(s) * rx * 0.82, -0.9, rz * 0.34)), Vector3(2.0, 3.2, 2.6))
	# the jaw: a mass under the cranium, and the chin standing out of it
	m.block(st, Transform3D(basis * Basis(Vector3.RIGHT, -0.12), centre + basis * Vector3(0.0, -ry * 0.62, rz * 0.22)),
			Vector3(rx * 1.5, 3.4, rz * 1.35))
	m.block(st, Transform3D(basis * Basis(Vector3.RIGHT, 0.25), centre + basis * Vector3(0.0, -ry * 0.72, rz * 0.82)),
			Vector3(rx * 0.9, 2.2, 1.9))
	# the nose, and the stump of the neck it broke off at
	m.block(st, Transform3D(basis * Basis(Vector3.RIGHT, 0.35), centre + basis * Vector3(0.0, -0.6, rz * 0.95)),
			Vector3(1.7, 4.4, 1.8))
	m.block(st, Transform3D(basis, centre + basis * Vector3(0.0, -ry * 0.78, -rz * 0.45)), Vector3(rx * 1.15, 3.2, rz * 0.9))
	# Carved stone, not masonry: at the Oroth unit of 1.1 m the whole head came out bricked.
	var carved := k.surface("oroth", 0.45)
	carved.set_shader_parameter("unit_size", 3.4)
	carved.set_shader_parameter("variation", 0.75)
	m.commit(st, carved, "Head", true)
	# a wall of the head's reach: a squashed sphere has no shape of its own
	k.collider(Vector3(rx * 1.9, ry * 1.9, rz * 1.9), Transform3D(basis, centre), "stone")
	# the eyes: dark sockets, the one facing the approach with the vigil's light in it
	var eye := m.begin()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.3
	disc.radial_segments = 20
	var lit_at := Vector3.ZERO
	for s in [-1.0, 1.0]:
		var at := centre + basis * Vector3(float(s) * rx * 0.44, 1.15, rz * 0.9)
		eye.append_from(disc, 0, Transform3D(basis * Basis(Vector3.UP, float(s) * 0.34) * Basis(Vector3.RIGHT, PI * 0.5), at)
				.scaled_local(Vector3(1.4, 1.0, 1.05)))
		if s > 0.0:
			lit_at = at
	m.commit(eye, PoiKit.plain(Color(0.03, 0.03, 0.035), 0.9, 0.0, Color(0.55, 0.75, 1.0), 0.6), "Eyes", true)
	k.light(lit_at + basis * Vector3(0.0, 0.0, 0.9), Color(0.6, 0.78, 1.0), 2.4, 14.0)
	# a stair of slabs up the ash toward the eye's ledge
	var stair_from := grain * 11.0 + Vector2(-grain.y, grain.x) * 3.5
	var stair := m.begin()
	var stair_y := k.on_ground(stair_from.x, stair_from.y).y
	m.steps(stair, stair_from, -grain, stair_y, 9, 0.34, 0.9, 1.6)
	m.commit(stair, k.surface("oroth", 0.6), "Stair", true)
	# the sixth step, where whatever is standing the watch when it has turned stands
	var sixth := stair_from - grain * (0.9 * 5.5)
	k.marker("the_stair", Vector3(sixth.x, stair_y + 0.34 * 6.0 + 0.02, sixth.y), false, true, 0.6)
	# the Order's vigil: braziers at the foot and a bench for the relief who never comes
	for s in [-1.0, 1.0]:
		var at := grain * 9.5 + Vector2(-grain.y, grain.x) * float(s) * 4.5
		k.place(k.prop("brazier"), k.on_ground(at.x, at.y), 0.0)
		k.light(k.on_ground(at.x, at.y, 1.1), Color(1.0, 0.62, 0.3), 1.8, 9.0)
	var bench := grain * 13.0
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), yaw)
	# the knight keeping it stands between the braziers, facing out the way the eye does
	var vigil := grain * 10.6
	k.marker("the_vigil", k.on_ground(vigil.x, vigil.y), true)
	var ash: Array = []
	for i in 24:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(rx + 1.0, 14.0)
		ash.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.4, 0.9)))
	k.scatter(k.rock("scree"), ash)


# --- bridges ----------------------------------------------------------------------------------------

## Something to cross on. A bridge lies along the road that crosses it; where water is within
## reach it spans that water from bank to bank, and where the pad is dry (the world builder
## set most of these some way from their river) it is still a bridge you walk over, with the
## thing under it that the brief names. Every deck carries collision so it can be crossed.
static func bridge(d: PoiDressing) -> void:
	var k := d.kit
	var b := d.brief
	var road := k.road_direction(90.0)
	var water := k.water_direction(70.0)
	var axis := road if road != Vector2.ZERO else (water if water != Vector2.ZERO else k.grain())
	if PoiKit.brief_says(b, ["causeway"]):
		_bridge_causeway(d, axis, water)
	elif PoiKit.brief_says(b, ["weir"]):
		_bridge_weir(d, water if water != Vector2.ZERO else axis)
	elif PoiKit.brief_says(b, ["boardwalk"]):
		_bridge_boardwalk(d, axis)
	elif PoiKit.brief_says(b, ["natural", "granite arch"]):
		_bridge_natural_arch(d, axis)
	elif PoiKit.brief_says(b, ["chain"]):
		_bridge_chains(d, axis)
	else:
		_bridge_arch(d, axis, water)


## Where the deck goes: across the water if any lies within reach along `water`, else a span
## centred on the pad along `axis`. Returns [a, b] in local xz.
static func _span(k: PoiKit, axis: Vector2, water: Vector2, length: float) -> Array:
	if water != Vector2.ZERO:
		var s := k.water_span(water, 60.0)
		if s.x >= 0.0 and s.y > s.x:
			var a := water * maxf(s.x - 3.0, -length * 0.5)
			var b := water * (s.y + 3.0)
			if a.distance_to(b) <= 64.0:
				return [a, b]
	return [-axis * length * 0.5, axis * length * 0.5]


## A stone arch with parapets, and under it what the brief says is there: the Toll's fallen
## clapper, half sunk and paved round; a dry riverbed of black glass.
static func _bridge_arch(d: PoiDressing, axis: Vector2, water: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var oroth := PoiKit.brief_says(d.brief, ["oroth", "fused"])
	# a packhorse bridge that carts cross is 4 m wide and humped enough to read from the road;
	# the first one was 3.4 m wide with a 1.5 m rise and at thirty paces it was a kerbstone
	var ends := _span(k, axis, water, 19.0)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var mid := (a + b) * 0.5
	var stone := m.begin()
	m.arch_bridge(stone, a, b, 4.2, 2.3)
	m.commit(stone, k.surface("oroth" if oroth else "stone", 0.55), "Bridge", true)
	if PoiKit.brief_says(d.brief, ["glass"]):
		# The riverbed the Ash Winter sang dry: a narrow band of broken black glass running
		# under the arch, laid *into* the ground rather than on it. The first version was
		# five-metre plates sitting proud at a roughness of 0.08, and they photographed as
		# spilled oil — a mirror the size of a room is not a riverbed.
		var bed := m.begin()
		for i in 38:
			var t := (float(i) - 18.5) * 2.2 + k.rng.randf_range(-0.5, 0.5)
			var off := dir * k.rng.randf_range(-1.9, 1.9)
			var p := mid + perp * t + off
			var gg := k.on_ground(p.x, p.y)
			m.block(bed, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(perp) + k.rng.randf_range(-0.3, 0.3))
					* Basis(Vector3.BACK, k.rng.randf_range(-0.09, 0.09)), gg - Vector3(0.0, 0.06, 0.0)),
					Vector3(k.rng.randf_range(1.4, 2.8), 0.16, k.rng.randf_range(1.6, 3.4)))
		m.commit(bed, PoiKit.plain(PoiKit.GLASS, 0.22), "GlassBed", true)
		var shards: Array = []
		for i in 26:
			var p := mid + perp * k.rng.randf_range(-24.0, 24.0) + dir * k.rng.randf_range(2.2, 5.0) * (1.0 if k.rng.randf() > 0.5 else -1.0)
			shards.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.7)))
		k.scatter(k.rock("scree"), shards)
		# the dead ash well off the crossing, down the bed, so nothing stands in the arch
		for s in [-1.0, 1.0]:
			var t := mid + perp * float(s) * 24.0 + dir * float(s) * 7.0
			k.place(k.tree("dead_ash_tree"), k.on_ground(t.x, t.y), k.rng.randf_range(0.0, TAU), 1.0, true, Vector3.ZERO, true)
	elif PoiKit.brief_says(d.brief, ["bell", "clapper"]):
		# the Toll's clapper under the arch, too big to move, so they paved round it
		var bell := k.prop("bell_medium")
		var g := k.on_ground(mid.x, mid.y)
		k.place(bell, g + Vector3(0.0, -0.9, 0.0), k.rng.randf_range(0.0, TAU), 2.2, true, Vector3(0.0, 0.0, 1.05), true)
		# they paved round it rather than move it: setts close about the clapper, not a white
		# apron twenty metres long, which is what a seven-block run of 3.3 × 4.6 came out as
		var paving := m.begin()
		for i in 22:
			# `ang`, not `a`: the near end of the span is already `a` at function scope, and
			# GDScript refuses the second declaration — which stops the whole script compiling,
			# so nothing that draws a point of interest loads at all
			var ang := k.rng.randf_range(0.0, TAU)
			var r := 1.2 + 3.4 * sqrt(k.rng.randf())
			var p := mid + Vector2(sin(ang), cos(ang)) * r
			var gg := k.on_ground(p.x, p.y)
			m.block(paving, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU))
					* Basis(Vector3.BACK, k.rng.randf_range(-0.05, 0.05)), gg - Vector3(0.0, 0.03, 0.0)),
					Vector3(k.rng.randf_range(0.7, 1.3), 0.14, k.rng.randf_range(0.7, 1.2)))
		var setts := k.surface("stone", 0.95)
		setts.set_shader_parameter("unit_size", 0.5)
		m.commit(paving, setts, "Paving")
	# a road's furniture at the near end
	var near := a - dir * 2.5
	k.place(k.prop("signpost"), k.on_ground(near.x + perp.x * 2.6, near.y + perp.y * 2.6), PoiKit.yaw_of(dir))
	if not oroth:
		var cart := a - dir * 6.0 + perp * 3.2
		k.place(k.prop("cart"), k.on_ground(cart.x, cart.y), PoiKit.yaw_of(dir) + k.rng.randf_range(-0.2, 0.2))
	# reeds or grass where the banks are
	var bank := k.flora("reeds") if water != Vector2.ZERO else ""
	if bank != "":
		var reeds: Array = []
		for i in 30:
			var t := k.rng.randf_range(0.1, 0.9)
			var p := a.lerp(b, t) + perp * k.rng.randf_range(2.6, 6.0) * (1.0 if k.rng.randf() > 0.5 else -1.0)
			reeds.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
		k.scatter(bank, reeds, false, false, false)


## The Long Stride: an Oroth causeway striding out over the water on piers, its hinge-less
## lamp posts one after another along it, each lit.
static func _bridge_causeway(d: PoiDressing, axis: Vector2, water: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var dir := water if water != Vector2.ZERO else axis
	var s := k.water_span(dir, 70.0) if water != Vector2.ZERO else Vector2(-1.0, -1.0)
	var start := -dir * 8.0
	var end := dir * (minf(s.y, 62.0) if s.y > 0.0 else 40.0)
	var wl := k.water_y(dir.x * 30.0, dir.y * 30.0)
	var deck_y := maxf(k.on_ground(start.x, start.y).y + 0.3, (wl if not is_nan(wl) else 0.0) + 1.3)
	var stone := m.begin()
	m.arch_bridge(stone, start, end, 4.2, 0.1, deck_y, true, false)
	# piers every eight metres down to the bed
	var yaw := PoiKit.yaw_of(dir)
	var length := start.distance_to(end)
	var n := int(length / 8.0)
	for i in range(1, n):
		var p := start + dir * (length * float(i) / float(n))
		var bed := k.on_ground(p.x, p.y).y
		var h := deck_y - bed + 0.3
		m.block(stone, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, deck_y - h * 0.5 - 0.2, p.y)), Vector3(4.6, h, 2.0))
	m.commit(stone, k.surface("oroth", 0.5), "Causeway", true)
	# the lamp posts, alternating sides, and their lights
	var lamp := k.prop("lantern_standing")
	var perp := Vector2(-dir.y, dir.x)
	var k_posts := int(length / 7.0)
	var posts: Array = []
	for i in range(k_posts + 1):
		var t := float(i) / float(maxi(k_posts, 1))
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := start.lerp(end, t) + perp * side * 1.75
		posts.append(PoiKit.transform_at(Vector3(p.x, deck_y + 0.21, p.y), yaw, 1.35))
		if i % 2 == 0 or k_posts < 6:
			k.light(Vector3(p.x, deck_y + 0.21 + PoiKit.height_of(lamp) * 1.35 - 0.2, p.y), Color(1.0, 0.82, 0.55), 1.6, 9.0)
	k.scatter(lamp, posts, true, true)
	# the toll: a table at the landward end, and the queue's litter
	var gate := start + dir * 3.0
	k.place(k.prop("table_trestle"), Vector3(gate.x + perp.x * 0.9, deck_y + 0.21, gate.y + perp.y * 0.9), yaw + PI * 0.5)
	# who keeps it stands beside it, the toll is paid at it, the line is the deck past it, and the
	# queue waits on the approach
	k.marker("the_toll_table", Vector3(gate.x - perp.x * 0.5, deck_y + 0.23, gate.y - perp.y * 0.5), false, true, 0.8)
	k.touchable("the_toll", Vector3(gate.x + perp.x * 0.9, deck_y + 0.21 + 0.8, gate.y + perp.y * 0.9), "Pay the toll")
	var line := gate + dir * 2.8
	k.marker("the_toll_line", Vector3(line.x, deck_y + 0.23, line.y), false, true, 2.0)
	var queue := start - dir * 3.5
	k.marker("the_toll_queue", k.on_ground(queue.x, queue.y))
	k.place(k.prop("chest"), Vector3(gate.x + perp.x * 0.9, deck_y + 0.21, gate.y + perp.y * 0.9) + Vector3(dir.x, 0.0, dir.y) * 1.2, yaw)
	k.place(k.prop("banner"), Vector3(gate.x - perp.x * 1.6, deck_y + 0.21, gate.y - perp.y * 1.6), yaw, 1.0, false)
	k.place(k.prop("crate"), k.on_ground(start.x - dir.x * 3.0 + perp.x * 3.0, start.y - dir.y * 3.0 + perp.y * 3.0), k.rng.randf_range(0.0, TAU))


## The Eelweir: dock posts across the outflow with wicker panels between them, a walkway of
## planks on top, and the eel traps hung from every post.
static func _bridge_weir(d: PoiDressing, dir: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var length := 26.0
	var a := -dir * (length * 0.5)
	var b := dir * (length * 0.5)
	var yaw := PoiKit.yaw_of(dir)
	var planks := m.begin()
	var posts := m.begin()
	var deck_y := maxf(k.on_ground(a.x, a.y).y, k.on_ground(b.x, b.y).y) + 1.1
	m.plank_deck(planks, posts, a, b, 1.6, deck_y, 2.6, true)
	m.commit(planks, k.surface("planks", 0.75), "Walkway", true)
	m.commit(posts, k.surface("timber", 0.7), "Posts", true)
	# wicker below the walkway, on the upstream side
	var perp := Vector2(-dir.y, dir.x)
	var panels: Array = []
	var wattle := k.prop("fence_wattle", 0)
	var pw := PoiKit.half_width_of(wattle) * 2.0
	var n := int(length / maxf(pw * 0.92, 1.0))
	for i in n:
		var p := a + dir * (pw * 0.92 * (float(i) + 0.5)) + perp * 0.95
		panels.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.3), yaw, 1.0))
		var p2 := p - dir * pw * 0.05
		panels.append(PoiKit.transform_at(k.on_ground(p2.x, p2.y, 0.6), yaw, 1.0))
	k.scatter(wattle, panels, true, true)
	# the traps
	var traps: Array = []
	var trap := k.prop("basket", 0)
	for i in range(int(length / 2.6) + 1):
		var p := a + dir * (2.6 * float(i)) - perp * 1.0
		traps.append(PoiKit.transform_at(Vector3(p.x, deck_y - 0.75 - k.rng.randf_range(0.0, 0.3), p.y), yaw + k.rng.randf_range(-0.4, 0.4), 1.1))
	k.scatter(trap, traps)
	for s in [-1.0, 1.0]:
		var e: Vector2 = (a if float(s) < 0.0 else b) + dir * float(s) * 2.4
		k.place(k.prop("dock_post"), k.on_ground(e.x, e.y), yaw, 1.15)
		k.place(k.prop("rope_coil"), k.on_ground(e.x + perp.x * 1.2, e.y + perp.y * 1.2), k.rng.randf_range(0.0, TAU), 1.0, false)
	k.place(k.prop("rowboat"), k.on_ground(a.x - perp.x * 4.0, a.y - perp.y * 4.0), yaw + 0.6)
	# reeds either side of the weir, off the walkway rather than through it
	var reeds: Array = []
	for i in 40:
		var t := k.rng.randf_range(-0.1, 1.1)
		var p := a.lerp(b, t) + perp * k.rng.randf_range(3.2, 9.0) * (1.0 if k.rng.randf() > 0.5 else -1.0)
		reeds.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)


## The Lantern Causeway: a boardwalk of planks on posts over the marsh, lantern poles along
## it, each lit at dusk by somebody who sings as she goes.
static func _bridge_boardwalk(d: PoiDressing, axis: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var length := 36.0
	var a := -axis * (length * 0.5)
	var b := axis * (length * 0.5)
	var yaw := PoiKit.yaw_of(axis)
	var perp := Vector2(-axis.y, axis.x)
	var planks := m.begin()
	var posts := m.begin()
	# a marsh boardwalk stands well clear of the water: at 0.9 m the reeds grew over it and
	# the whole causeway photographed as a reed bed with poles in it
	var deck_y := maxf(k.on_ground(a.x, a.y).y, maxf(k.on_ground(b.x, b.y).y, k.on_ground(0.0, 0.0).y)) + 1.45
	m.plank_deck(planks, posts, a, b, 2.4, deck_y, 3.0, false)
	# the poles, alternating sides, with a lantern hung from each and a rope between
	var n := int(length / 6.0)
	var lanterns: Array = []
	var last := Vector3.INF
	for i in range(n + 1):
		var t := float(i) / float(n)
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := a.lerp(b, t) + perp * side * 1.0
		var top := m.post(posts, p, deck_y - k.on_ground(p.x, p.y).y + 2.6, 0.13)
		var arm := Vector3(perp.x, 0.0, perp.y) * side * 0.5
		m.block(posts, Transform3D(Basis(Vector3.UP, yaw), top + arm * 0.5 - Vector3(0.0, 0.05, 0.0)), Vector3(0.9, 0.07, 0.07))
		lanterns.append(PoiKit.transform_at(top + arm - Vector3(0.0, 0.5, 0.0), yaw, 1.0))
		k.light(top + arm - Vector3(0.0, 0.3, 0.0), Color(1.0, 0.78, 0.45), 1.5, 8.0)
		if last != Vector3.INF:
			var rope := m.begin()
			var mid := (last + top) * 0.5 - Vector3(0.0, 0.25, 0.0)
			var seg := top - last
			var pitch := atan2(seg.y, Vector2(seg.x, seg.z).length())
			m.rod(rope, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(Vector2(seg.x, seg.z))) * Basis(Vector3.RIGHT, PI * 0.5 - pitch), mid),
					0.015, seg.length())
			m.commit(rope, PoiKit.plain(Color(0.42, 0.36, 0.28), 0.9), "Rope")
		last = top
	m.commit(planks, k.surface("planks", 0.7), "Boardwalk", true)
	m.commit(posts, k.surface("timber", 0.6), "Poles", true)
	k.scatter(k.prop("lantern_hanging"), lanterns)
	# the lamplighter's round: on the deck, not on the marsh under it
	var round_at := a.lerp(b, 0.35)
	k.marker("the_lamp_round", Vector3(round_at.x, deck_y + 0.1, round_at.y), true, true, length * 0.5)
	var reeds: Array = []
	for i in 70:
		var t := k.rng.randf_range(-0.1, 1.1)
		var p := a.lerp(b, t) + perp * k.rng.randf_range(3.6, 12.0) * (1.0 if k.rng.randf() > 0.5 else -1.0)
		reeds.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)
	var lilies: Array = []
	for i in 12:
		var t := k.rng.randf_range(0.0, 1.0)
		var p := a.lerp(b, t) + perp * k.rng.randf_range(3.0, 7.0) * (1.0 if k.rng.randf() > 0.5 else -1.0)
		var wy := k.water_y(p.x, p.y)
		if is_nan(wy):
			continue
		lilies.append(PoiKit.transform_at(Vector3(p.x, wy + 0.02, p.y), k.rng.randf_range(0.0, TAU), 1.0))
	k.scatter(k.flora("waterlily_pad"), lilies, false, false, false)


## Mossbridge: a natural granite arch across the way, moss on its back, a great tree rooted
## at each end.
static func _bridge_natural_arch(d: PoiDressing, axis: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var perp := Vector2(-axis.y, axis.x)
	var a := -perp * 10.0
	var b := perp * 10.0
	var stone := m.begin()
	m.arch_bridge(stone, a, b, 4.6, 4.4, NAN, false, true, 1.0)
	# Natural granite, not masonry: the painted stone at a two-metre unit reads as rock mass
	# rather than courses, and boulders sitting along the arch's own back finish the job. At
	# a 0.9 m unit this photographed as a neatly built bridge, which is the one thing the
	# brief says it is not.
	var granite := k.surface("stone", 0.85)
	granite.set_shader_parameter("unit_size", 2.1)
	granite.set_shader_parameter("variation", 0.8)
	m.commit(stone, granite, "Arch", true)
	# boulders at the feet where the arch grows out of the ground, and along its back
	var feet: Array = []
	for end in [a, b]:
		var e: Vector2 = end
		for i in 7:
			var p := e + k.jitter(3.0)
			feet.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.3), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.5)))
	k.scatter(k.rock("boulder"), feet, true, true)
	var back: Array = []
	for i in 9:
		var t := k.rng.randf_range(0.12, 0.88)
		var p := a.lerp(b, t) + axis * k.rng.randf_range(-2.1, 2.1)
		var y := PoiMasonry._hump(t, k.on_ground(a.x, a.y).y, k.on_ground(b.x, b.y).y, 4.4)
		back.append(PoiKit.transform_at(Vector3(p.x, y - 0.5, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.4, 0.8)))
	k.scatter(k.rock("boulder", 1), back, false, true)
	var moss: Array = []
	for i in 40:
		var t := k.rng.randf_range(0.05, 0.95)
		var p := a.lerp(b, t) + axis * k.rng.randf_range(-1.5, 1.5)
		var y := PoiMasonry._hump(t, k.on_ground(a.x, a.y).y, k.on_ground(b.x, b.y).y, 4.4) + 0.22
		moss.append(PoiKit.transform_at(Vector3(p.x, y, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
	k.scatter(k.flora("moss_patch"), moss, false, false, false)
	var hanging := k.flora("hanging_moss")
	if hanging != "":
		var beards: Array = []
		for i in 10:
			var t := k.rng.randf_range(0.25, 0.75)
			var p := a.lerp(b, t) + axis * k.rng.randf_range(-1.6, 1.6)
			var y := PoiMasonry._hump(t, k.on_ground(a.x, a.y).y, k.on_ground(b.x, b.y).y, 4.4) - 1.2
			beards.append(PoiKit.transform_at(Vector3(p.x, y, p.y), k.rng.randf_range(0.0, TAU), 1.0))
		k.scatter(hanging, beards, false, false, false)
	# the wardens' places: a great tree at each end
	var tree := k.tree("giant_oak")
	if tree == "":
		tree = k.tree("black_ash")
	# the wardens stand well off the ends, or they stand in front of the arch and hide it
	var ends := ["the_warden_west", "the_warden_east"]
	for i in 2:
		var e: Vector2 = [a, b][i]
		var t := e + e.normalized() * 6.5 + axis * 5.5
		k.place(tree, k.on_ground(t.x, t.y), k.rng.randf_range(0.0, TAU), 0.72, true, Vector3.ZERO, true)
		# and the Warden that keeps each end stands at the foot of its tree, on the path side
		var keep := t - axis * 3.2
		k.marker(ends[i], k.on_ground(keep.x, keep.y))
	var ferns: Array = []
	for i in 30:
		var p := k.jitter(13.0)
		ferns.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("fern"), ferns, false, false, false)


## The Chain Bridge: a plank deck slung between two pairs of stone pylons across the gorge,
## hung on four chains, one forged by each clan.
static func _bridge_chains(d: PoiDressing, axis: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var down := k.downhill()
	var dir := down if down != Vector2.ZERO else axis
	var a := dir * 4.0
	var yaw := PoiKit.yaw_of(dir)
	var perp := Vector2(-dir.y, dir.x)
	var deck_y := k.on_ground(a.x, a.y).y + 0.6
	# the far end is where the ground comes back up to the deck, if it does within reach, but
	# never so near that four pylons crowd each other: a treaty bridge is a long span
	var reach := 30.0
	for t in range(20, 44, 2):
		if k.on_ground(dir.x * float(t), dir.y * float(t)).y >= deck_y - 0.5:
			reach = float(t)
			break
	var b := dir * reach
	var planks := m.begin()
	m.arch_bridge(planks, a, b, 2.4, -0.7, deck_y, false, false, NAN, "wood")
	m.commit(planks, k.surface("planks", 0.8), "Deck", true)
	# pylons
	var stone := m.begin()
	var tops: Array = []
	for end in [a, b]:
		var e: Vector2 = end
		for s in [-1.0, 1.0]:
			var p := e + perp * float(s) * 1.9
			var g := k.on_ground(p.x, p.y)
			# the far wall of a gorge can stand above the near lip; a pylon is still a pylon
			var h := maxf(deck_y - g.y + 7.2, 3.0)
			m.drum(stone, Transform3D(Basis.IDENTITY, g), 1.05, h, 0.0, NAN, true, 0.36)
			tops.append(Vector3(p.x, g.y + h, p.y))
	m.commit(stone, k.surface("stone", 0.6), "Pylons", true)
	# the four chains: links along a catenary from pylon top to pylon top, touching the deck
	# A link the size of a tyre reads as a tyre: these are forged links of about 30 cm, laid
	# close enough to touch, alternating flat and on edge the way a chain lies.
	var link := TorusMesh.new()
	link.inner_radius = 0.055
	link.outer_radius = 0.15
	link.rings = 8
	link.ring_segments = 6
	var chains := m.begin()
	var hangers := m.begin()
	var sag := 4.4
	for s_v in [-1.0, 1.0]:
		var s := float(s_v)
		for lane_v in [0.0, 0.42]:
			var lane := float(lane_v)
			var p0: Vector3 = tops[0 if s < 0.0 else 1] + Vector3(perp.x, 0.0, perp.y) * s * -lane
			var p1: Vector3 = tops[2 if s < 0.0 else 3] + Vector3(perp.x, 0.0, perp.y) * s * -lane
			var span := p0.distance_to(p1)
			var steps := maxi(int(span / 0.24), 12)
			var along := (p1 - p0).normalized()
			for i in steps:
				var t := (float(i) + 0.5) / float(steps)
				var p := p0.lerp(p1, t)
				p.y -= sag * (1.0 - pow(2.0 * t - 1.0, 2.0)) * (0.95 + lane * 0.12)
				chains.append_from(link, 0, Transform3D(Basis.looking_at(along, Vector3.UP)
						* Basis(Vector3.BACK, PI * 0.5 * float(i % 2)), p))
			# the hangers: a rod from the chain down to the deck every two metres, which is
			# what makes the deck hang from the chains rather than the chains hang beside it
			if lane > 0.0:
				continue
			var drops := maxi(int(span / 2.0), 3)
			for i in range(1, drops):
				var t := float(i) / float(drops)
				var p := p0.lerp(p1, t)
				p.y -= sag * (1.0 - pow(2.0 * t - 1.0, 2.0)) * 0.95
				var deck := a.lerp(b, t)
				var deck_top := PoiMasonry._hump(t, deck_y, deck_y, -0.7) + 0.2
				var h := p.y - deck_top
				if h <= 0.2:
					continue
				m.block(hangers, Transform3D(Basis(Vector3.UP, yaw), Vector3(deck.x + (p.x - deck.x) * 0.5,
						deck_top + h * 0.5, deck.y + (p.z - deck.y) * 0.5)), Vector3(0.07, h, 0.07))
	m.commit(chains, PoiKit.plain(Color(0.28, 0.26, 0.25), 0.55, 0.85), "Chains", true)
	m.commit(hangers, PoiKit.plain(Color(0.3, 0.28, 0.26), 0.6, 0.7), "Hangers", true)
	# the toll-keeper's post at the near end
	var keeper := a - dir * 3.0 + perp * 3.0
	k.place(k.prop("brazier"), k.on_ground(keeper.x, keeper.y), 0.0)
	k.light(k.on_ground(keeper.x, keeper.y, 1.1), Color(1.0, 0.62, 0.3), 2.0, 9.0)
	k.place(k.prop("stool"), k.on_ground(keeper.x + perp.x, keeper.y + perp.y), yaw)
	k.place(k.prop("chest"), k.on_ground(keeper.x - dir.x * 1.4, keeper.y - dir.y * 1.4), yaw)
	k.place(k.prop("drystone_wall"), k.on_ground(keeper.x + perp.x * 2.6, keeper.y + perp.y * 2.6), yaw)
	k.place(k.prop("signpost"), k.on_ground(a.x - dir.x * 4.0 - perp.x * 2.6, a.y - dir.y * 4.0 - perp.y * 2.6), yaw)
	var stool := keeper + perp * 1.6
	k.marker("the_toll_post", k.on_ground(stool.x, stool.y), true)
	var beyond := b + dir * 7.0
	k.marker("the_far_approach", k.on_ground(beyond.x, beyond.y))


# --- waterfalls -------------------------------------------------------------------------------------

## Water coming down: a face of the region's cliff slabs with a sheet falling off its lip into
## a pool, spray at the foot, and what the brief adds — foxfire in the ravine walls, three
## terraces with a Hearthstone behind the middle one, or no water at all and a face of black
## glass with ledges to climb.
static func waterfall(d: PoiDressing) -> void:
	var k := d.kit
	var b := d.brief
	var grain := k.grain()
	if PoiKit.brief_says(b, ["three", "terrace"]):
		_falls_terraced(d, grain)
	elif PoiKit.brief_says(b, ["glass"]):
		_falls_glass(d, grain)
	else:
		_falls_single(d, grain, PoiKit.brief_says(b, ["foxfire", "glow"]))


## A face of rock across `width`, `height` tall, centred at `centre` (local xz) with its front
## toward `facing`, stepping back into the hill in ledges. Returns the lip: the point at the top
## front edge of the channel the water comes down, in local space.
##
## The face is the forge's cliff ledges (gen_rocks.cliff_ledge): modules of bedded rock whose ends
## tile, laid in columns round a shallow arc and stacked up each column, every one standing on the
## one below it and set a little back, so the face steps up in ledges and a row reads as one run of
## rock. The middle column is the channel: a module lower than its neighbours, set back, its top
## the lip. Where `mouth`, the channel's foot is cut back under an overhang for the cave behind the
## water, and the dark in it is its own shadow. (Before the ledges: slabs stood on end read as
## cardboard boxes, laid flat as cubes, and boulders pressed into beds as a heap of cloud.)
static func _rock_face(k: PoiKit, centre: Vector2, facing: Vector2, width: float, height: float,
		base := NAN, foot := true, mouth := false) -> Vector3:
	var kinds := _ledge_paths(k)
	var perp := Vector2(-facing.y, facing.x)
	var yaw := PoiKit.yaw_of(facing)
	var bow := width * 0.18
	var module := 5.0
	var cols := maxi(int(ceil(width / (module * 0.94))), 3)
	if cols % 2 == 0:
		cols += 1
	var mid_col := int(cols / 2.0)
	var columns: Array = []
	var ledges: Array = []
	var lip := Vector3.ZERO
	var set_back := 0.95
	# how far back the channel's slot is cut: under the neighbours' top ledges, so no ledge below
	# the lip stands out into the water (a stepped channel hid the sheet behind its own ledges)
	var slot := maxf(0.0, set_back * (ceilf((height + 1.6) / 3.0) - 1.0)) + 0.4
	for c in cols:
		var t := (float(c) - float(mid_col)) / float(cols)
		var along := (float(c) - float(mid_col)) * module * 0.94
		var p0 := centre + perp * along + facing * (bow * 4.0 * t * t)
		var channel := c == mid_col
		if channel:
			p0 -= facing * (1.3 + slot)
		var turn := yaw + atan(8.0 * bow * t / maxf(width, 1.0)) + k.rng.randf_range(-0.04, 0.04)
		var ground := k.on_ground(p0.x, p0.y).y
		var y := (ground if is_nan(base) else minf(base, ground)) - 0.5
		var want := (height if channel else height + 1.6 + k.rng.randf_range(-0.6, 0.8))
		var top := y
		var r := 0
		var stack: Array = []
		while top - y < want + 0.5 and r < 8:
			var path: String = kinds[k.rng.randi_range(0, kinds.size() - 1)]
			if channel and r == 0 and mouth:
				path = kinds[kinds.size() - 1]
			var dims := _ledge_dims(path)
			var back := 0.0 if channel else float(r) * set_back
			if channel and r == 0 and mouth:
				# the cave's overhang: its foot is cut back under the ledge above
				back += 2.6
			var p := p0 - facing * back
			var bottom := top - (0.18 if r > 0 else 0.0)
			stack.append({"path": path, "xform": Transform3D(Basis(Vector3.UP, turn), Vector3(p.x, bottom, p.y)),
					"bottom": bottom, "top": bottom + dims.y, "front": p + facing * dims.z})
			top = bottom + dims.y
			var shelf := p + facing * (dims.z - set_back * 0.6)
			ledges.append(Vector3(shelf.x, top - 0.05, shelf.y))
			r += 1
		columns.append(stack)
		if channel:
			var last: Dictionary = stack[-1]
			var f: Vector2 = last["front"]
			var proud := f + facing * 0.35
			lip = Vector3(proud.x, float(last["top"]) - 0.1, proud.y)
	# one MultiMesh per module, with the forge's own collision for each
	var by_path: Dictionary = {}
	for stack in columns:
		for piece in stack:
			var pth := str(piece["path"])
			if not by_path.has(pth):
				by_path[pth] = []
			(by_path[pth] as Array).append(piece["xform"])
	for pth in by_path:
		k.scatter(pth, by_path[pth], true, true)
	var kept: Array = k.root.get_meta("rock_columns", [])
	kept.append_array(columns)
	k.root.set_meta("rock_columns", kept)
	# weathered: moss along the ledges, fern in their backs, where the spray keeps them green
	var moss: Array = []
	var fern: Array = []
	for l in ledges:
		var q: Vector3 = l
		if k.rng.randf() < 0.35:
			var back_q := q - Vector3(facing.x, 0.0, facing.y) * 0.5
			moss.append(PoiKit.transform_at(back_q + Vector3(k.rng.randf_range(-1.2, 1.2), 0.0, 0.0),
					k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 0.85)))
		if k.rng.randf() < 0.5:
			fern.append(PoiKit.transform_at(q - Vector3(facing.x, 0.0, facing.y) * 0.3, k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(0.7, 1.1)))
	k.scatter(k.flora("moss_patch"), moss, false, false, false)
	k.scatter(k.flora("fern"), fern, false, false, false)
	var boulder_end := k.rock("boulder")
	if boulder_end != "":
		var bh := maxf(PoiKit.height_of(boulder_end), 1.0)
		var ends: Array = []
		for side_i in [0, cols - 1]:
			var stack: Array = columns[side_i]
			var out_dir := perp * (1.0 if side_i == cols - 1 else -1.0)
			for piece in stack:
				var pc: Dictionary = piece
				var f: Vector2 = pc["front"]
				var h := float(pc["top"]) - float(pc["bottom"])
				var sc := h / bh * k.rng.randf_range(0.9, 1.2)
				var q := f + out_dir * (2.4 + k.rng.randf_range(0.0, 0.6)) - facing * k.rng.randf_range(0.8, 1.8)
				var yb := float(pc["bottom"]) - h * 0.2
				ends.append(PoiKit.transform_at(Vector3(q.x, yb, q.y), k.rng.randf_range(0.0, TAU), sc,
						Vector3(k.rng.randf_range(-0.2, 0.2), 0.0, k.rng.randf_range(-0.2, 0.2))))
		k.scatter(boulder_end, ends, true, true)
	if not foot:
		return lip
	# boulders tumbled at the foot either side of where the water lands (in front of it they hid it)
	var boulder := k.rock("boulder")
	var feet: Array = []
	for i in 12:
		var side := 1.0 if i % 2 == 0 else -1.0
		var q := centre + perp * side * k.rng.randf_range(4.0, width * 0.55) + facing * k.rng.randf_range(3.0, 6.5)
		feet.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.4), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 1.2),
				Vector3(k.rng.randf_range(-0.2, 0.2), 0.0, k.rng.randf_range(-0.2, 0.2))))
	k.scatter(boulder, feet, true, true)
	var scree: Array = []
	for i in 16:
		var side := 1.0 if i % 2 == 0 else -1.0
		var q := centre + perp * side * k.rng.randf_range(3.0, width * 0.6) + facing * k.rng.randf_range(2.5, 8.0)
		scree.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 1.1)))
	k.scatter(k.rock("scree"), scree)
	return lip


## The region's cliff ledges, tallest first and the shortest last (the forge's variants a, b, c
## are 3.0, 4.2 and 2.1 m).
static func _ledge_paths(k: PoiKit) -> Array[String]:
	var out: Array[String] = []
	for v in 3:
		var pth := k.rock("cliff_ledge", v)
		if pth != "" and not out.has(pth):
			out.append(pth)
	out.sort_custom(func(x: String, y: String) -> bool: return _ledge_dims(x).y > _ledge_dims(y).y)
	return out


## A ledge's measure: x its width along the face, y its height, z how far its front (with the lip)
## stands in front of its origin.
static func _ledge_dims(pth: String) -> Vector3:
	var b: Dictionary = PoiKit.meta(pth).get("bounds", {})
	var lo: Array = b.get("min", [-2.5, 0.0, -1.7])
	var hi: Array = b.get("max", [2.5, 3.0, 2.4])
	return Vector3(float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1]), float(hi[2]))


static func _falls_single(d: PoiDressing, grain: Vector2, foxfire: bool) -> void:
	var k := d.kit
	var m := d.masonry
	var facing := grain
	var face_at := -facing * 6.0
	var lip := _rock_face(k, face_at, facing, 16.0, 11.0, NAN, true, not foxfire)
	var yaw := PoiKit.yaw_of(facing)
	var sheet_w := 5.5
	var g := k.on_ground(0.0, 0.0)
	var drop := lip.y - g.y
	_lip_marker(k, "lip", lip, sheet_w, drop)
	var pool_at := Vector2(lip.x, lip.z) + facing * 4.8
	if not river_draws_the_water(d):
		m.sheet(lip, yaw, sheet_w, drop + 0.4, PoiKit.falling_water(false, 2.4), "Fall", 0.9, true)
		m.pool(pool_at, 6.5, g.y + 0.12, k.still_water(g.y - 2.0, Color.WHITE, 0.62), "Pool")
		k.puffs(Vector3(pool_at.x, g.y + 0.3, pool_at.y) - Vector3(facing.x, 0.0, facing.y) * 3.0, Vector3(sheet_w * 0.6, 0.3, 1.2),
				0.8, 22, Color(0.95, 0.97, 1.0, 0.32), 2.6, 3.2)
	_lip_shelf(d, face_at, facing, lip, "above_the_falls")
	# the stream on toward wherever it goes: wet stones and reeds along the way out
	var out: Array = []
	for i in 16:
		var t := k.rng.randf_range(6.0, 20.0)
		var p := pool_at + facing * t + Vector2(-facing.y, facing.x) * k.rng.randf_range(-3.5, 3.5)
		out.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.35, 0.8)))
	k.scatter(k.rock("boulder", 1), out, true)
	var green := k.flora("fern") if foxfire else k.flora("reeds")
	var fringe: Array = []
	for i in 36:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(5.5, 9.5)
		var p := pool_at + Vector2(sin(a), cos(a)) * r
		fringe.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(green, fringe, false, false, false)
	if foxfire:
		# the ravine's walls glow: bracket fungus on the rock, and its light
		var fungus := k.flora("bracket_fungus")
		var glows: Array = []
		for i in 14:
			var side := 1.0 if i % 2 == 0 else -1.0
			var p := face_at + Vector2(-facing.y, facing.x) * side * k.rng.randf_range(3.0, 7.5) + facing * k.rng.randf_range(0.8, 1.6)
			var y := g.y + k.rng.randf_range(1.0, 7.0)
			glows.append(PoiKit.transform_at(Vector3(p.x, y, p.y), yaw + PI * 0.5 * side, k.rng.randf_range(1.2, 2.0)))
			if i % 4 == 0:
				k.light(Vector3(p.x, y + 0.2, p.y) + Vector3(facing.x, 0.0, facing.y) * 0.8, Color(0.45, 0.95, 0.6), 1.2, 7.0)
		k.scatter(fungus, glows, false, false, false)
		var moss: Array = []
		for i in 26:
			var p := k.jitter(10.0)
			moss.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.02), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
		k.scatter(k.flora("moss_patch"), moss, false, false, false)
	else:
		# the down-wolves' way in: a dark mouth in the rock behind the water is theirs, and a
		# cart track ends where somebody comes to look at the fall
		_cave_mouth(d, face_at, facing, "behind_the_falls")
		var look := pool_at + facing * 9.0
		k.place(k.prop("bench"), k.on_ground(look.x, look.y), yaw + PI)


## Whether the world draws this fall's water itself. The painted look draws a river's falls from
## rivers.json (`RiverFalls`, a child of the water surface): the sheet, the white water where it
## lands and the mist. Where it does, the dressing keeps the rock and the lip and leaves the water
## to it, so it is drawn once. Looked up by path, so this builds on a branch that has no RiverFalls.
static func river_draws_the_water(d: PoiDressing) -> bool:
	var path := "res://world/river_falls.gd"
	if not ResourceLoader.exists(path):
		return false
	var falls := load(path) as Script
	if falls == null:
		return false
	for method in falls.get_script_method_list():
		if str(method.get("name", "")) == "near":
			return bool(falls.call("near", d.world_position, 30.0))
	return false


## Where the water goes over: a marker at the lip's front edge, for whoever draws the water
## (the painted look draws a fall's sheet, foam and mist from it when it can), with the notch's
## width and the drop to the pool.
static func _lip_marker(k: PoiKit, marker_name: String, lip: Vector3, width: float, drop: float) -> void:
	var mk := k.marker(marker_name, lip)
	if mk != null:
		mk.set_meta("width_m", width)
		mk.set_meta("drop_m", drop)


## A ledge of the rock you can stand on: beds of the forge's cliff slab laid on their sides across
## `width` and back `depth` from `front` (local xz), their tops level at `top`.
static func _ledge_beds(k: PoiKit, front: Vector2, facing: Vector2, width: float, depth: float, top: float) -> void:
	var kinds := _ledge_paths(k)
	if kinds.is_empty():
		return
	var short: String = kinds[kinds.size() - 1]
	var dims := _ledge_dims(short)
	var perp := Vector2(-facing.y, facing.x)
	var yaw := PoiKit.yaw_of(facing)
	var xforms: Array = []
	var along := maxi(int(ceil(width / (dims.x * 0.94))), 1)
	var back := maxi(int(ceil(depth / 3.0)), 1)
	for r in back:
		for i in along:
			var x := (float(i) - float(along - 1) * 0.5) * dims.x * 0.94
			var q := front + perp * x + facing * (depth * 0.5 - dims.z - float(r) * 3.0)
			xforms.append(Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.03, 0.03)), Vector3(q.x, top - dims.y, q.y)))
	k.scatter(short, xforms, true, true)


## A shelf of stone on the lip of a fall, beside the water, that something can stand on and look
## down from, with a marker on it (`name`): the sentences put the weavers "above" and the
## bell-bearer "at the top", and a group with no marker stood on the pad's rim at the foot.
static func _lip_shelf(d: PoiDressing, face_at: Vector2, facing: Vector2, lip: Vector3, marker_name: String) -> void:
	var k := d.kit
	# the ledge beside the channel, a little higher than the lip: its top is the shelf. The face's
	# columns are kept on the dressing; the channel is the middle one, the shelf the next.
	var columns: Array = k.root.get_meta("rock_columns", [])
	var at := Vector3(lip.x, lip.y + 0.3, lip.z) + Vector3(-facing.y, 0.0, facing.x) * 4.6
	if columns.size() >= 3:
		var beside: Array = columns[int(columns.size() / 2.0) + 1]
		if not beside.is_empty():
			var top_piece: Dictionary = beside[-1]
			var f: Vector2 = top_piece["front"]
			var q := f - facing * 1.2
			at = Vector3(q.x, float(top_piece["top"]), q.y)
	k.marker(marker_name, at + Vector3(0.0, 0.02, 0.0), false, true, 1.8)


## The cave behind a fall: the channel's foot cut back under the ledge above it (`_rock_face`'s
## `mouth`), its dark its own shadow behind the water, and a marker (`name`) in it, on the ground.
## It was two squared jambs, a lintel and a black board, then boulders round a black board; the
## board was the dark block the coordinator saw behind the water.
static func _cave_mouth(d: PoiDressing, face_at: Vector2, facing: Vector2, marker_name: String) -> void:
	var k := d.kit
	var inside := face_at - facing * 0.6
	k.marker(marker_name, k.on_ground(inside.x, inside.y))


## Three falls one above the other up the slope, each with its pool, a stair up the side of
## each, and the Hearthstone the sisters carried up on the middle ledge behind the water.
static func _falls_terraced(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var up := -k.downhill()
	var facing := -up if up != Vector2.ZERO else grain
	var perp := Vector2(-facing.y, facing.x)
	var yaw := PoiKit.yaw_of(facing)
	var tier_h := 4.6
	var tier_d := 6.0
	var ledge_w := 9.0
	var base := k.on_ground(0.0, 0.0).y
	var pool_y := base
	for tier in 3:
		var face_at := -facing * (2.0 + float(tier) * tier_d)
		var ledge_y := maxf(k.on_ground(face_at.x - facing.x * 2.0, face_at.y - facing.y * 2.0).y, pool_y) + tier_h
		# The face: beds of the rock stepping back, the tier below's ledge its foot. It was four
		# slabs stood upright and a flat box laid on top, which stood in the river as a white
		# block of bricks. The ledge you stand on is beds of the same rock laid level with its top.
		var tier_lip := _rock_face(k, face_at, facing, ledge_w * 1.25, tier_h, pool_y - 0.6, tier == 0)
		ledge_y = maxf(ledge_y, tier_lip.y + 0.35)
		var ledge_c := face_at - facing * (tier_d * 0.5)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(ledge_c.x, ledge_y - 0.3, ledge_c.y))
		_ledge_beds(k, ledge_c, facing, ledge_w * 1.1, tier_d + 1.0, ledge_y)
		k.collider(Vector3(ledge_w, 0.6, tier_d + 1.0), xf, "stone")
		# the water off the lip of the tier's channel into the pool below
		var lip := tier_lip
		_lip_marker(k, "lip%d" % tier, lip, 3.8, lip.y - pool_y)
		var pool_at := Vector2(lip.x, lip.z) + facing * 2.8
		if not river_draws_the_water(d):
			m.sheet(lip, yaw, 3.8, lip.y - pool_y + 0.4, PoiKit.falling_water(false, 2.2), "Fall%d" % tier, 0.7, true)
			m.pool(pool_at, 3.6, pool_y + 0.12, k.still_water(pool_y - 1.5, Color.WHITE, 0.62), "Pool%d" % tier)
			k.puffs(Vector3(pool_at.x, pool_y + 0.3, pool_at.y), Vector3(2.0, 0.2, 0.8), 0.7, 12, Color(0.95, 0.97, 1.0, 0.3), 2.0, 3.0)
		# the stair up the side of this tier
		# beside the face, not in it: the ledges run three columns wide, about seven metres either side
		var stair_from := face_at + facing * 1.5 + perp * (ledge_w * 0.5 + 4.0)
		var stair := m.begin()
		var steps := int(ceil(tier_h / 0.36))
		m.steps(stair, stair_from, -facing, pool_y, steps, tier_h / float(steps), 0.42, 1.4)
		m.commit(stair, k.surface("stone", 0.7), "Stair%d" % tier, true)
		# a Hearthstone on the first ledge when the data asks for one: the Three Sisters keeps one,
		# and Blackgill's three falls, dressed the same way, do not
		if tier == 1 and d.wants_hearthstone:
			var stone_at := face_at - facing * 2.4
			k.hearthstone(Vector3(stone_at.x, ledge_y, stone_at.y), yaw, d.poi_id, d.display_name)
			var candles: Array = []
			for i in 9:
				var a := k.rng.randf_range(0.0, TAU)
				var c := stone_at + Vector2(sin(a), cos(a)) * k.rng.randf_range(0.7, 1.5)
				candles.append(PoiKit.transform_at(Vector3(c.x, ledge_y, c.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
			k.scatter(k.prop("candle"), candles, false, false, false)
			k.light(Vector3(stone_at.x, ledge_y + 0.6, stone_at.y), Color(1.0, 0.76, 0.5), 1.2, 6.0)
		if tier == 2:
			# the top ledge, over all three falls: where the scree-hags shriek at whoever climbs
			k.marker("the_cliffs", Vector3(ledge_c.x, ledge_y + 0.02, ledge_c.y), false, true, 3.0)
		pool_y = ledge_y
	var heather: Array = []
	for i in 30:
		var p := k.jitter(14.0)
		heather.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("heather"), heather, false, false, false)


## A dry fall of black glass, still and polished, with ledges up its face for the climb the
## Order forbids and uses.
static func _falls_glass(d: PoiDressing, grain: Vector2) -> void:
	var k := d.kit
	var m := d.masonry
	var facing := grain
	var face_at := -facing * 7.0
	var lip := _rock_face(k, face_at, facing, 18.0, 13.0)
	var yaw := PoiKit.yaw_of(facing)
	var g := k.on_ground(0.0, 0.0)
	m.sheet(lip, yaw, 7.0, lip.y - g.y + 0.6, PoiKit.falling_water(true), "Glass", 0.8, true)
	_lip_marker(k, "lip", lip, 7.0, lip.y - g.y)
	# the basin it fell into, glass too: a pool of it, set hard (five glass plates laid on the ground
	# read as five plates)
	var pool_at := Vector2(lip.x, lip.z) + facing * 4.8
	m.pool(pool_at, 6.0, g.y + 0.06, PoiKit.plain(PoiKit.GLASS, 0.08), "Basin")
	# Ledges up the face for the climb: narrow steps set *into* the glass, not shelves bolted
	# onto the front of it — at 2.2 × 1.3 standing a metre and a half clear they photographed
	# as brackets on a wall.
	var ledges := m.begin()
	var perp := Vector2(-facing.y, facing.x)
	var count := int((lip.y - g.y) / 1.15)
	for i in count:
		var t := float(i) / float(maxi(count, 1))
		var side := (1.0 if i % 2 == 0 else -1.0) * (1.6 + t * 1.2)
		# on the glass, which hangs from the lip in front of the channel the rock stands back from
		var p := Vector2(lip.x, lip.z) + facing * (0.3 - t * 0.2) + perp * side
		var y := g.y + 1.1 + float(i) * 1.15
		var xf := Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.2, 0.2)), Vector3(p.x, y, p.y))
		m.block(ledges, xf, Vector3(1.3, 0.28, 0.7))
		k.collider(Vector3(1.3, 0.28, 0.7), xf, "stone")
	m.commit(ledges, k.surface("oroth", 0.5), "Ledges", true)
	_lip_shelf(d, face_at, facing, lip, "the_top")
	var shards: Array = []
	for i in 20:
		var p := pool_at + k.jitter(9.0)
		shards.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.7)))
	k.scatter(k.rock("scree"), shards)
	var grass: Array = []
	for i in 30:
		var p := k.jitter(14.0)
		grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("grey_grass"), grass, false, false, false)
	k.place(k.tree("dead_ash_tree"), k.on_ground(face_at.x + perp.x * 11.0, face_at.y + perp.y * 11.0), k.rng.randf_range(0.0, TAU), 1.0, true, Vector3.ZERO, true)


# --- ruins -------------------------------------------------------------------------------------------

## What is left of a building: courses standing to the knee where the walls were, the plan
## still readable on the ground, fallen slabs where they fell, a doorway that still stands
## because a lintel is the last thing to go, and a hearth nobody has swept.
static func ruins(d: PoiDressing) -> void:
	var b := d.brief
	if PoiKit.brief_says(b, ["colonnade", "steps", "stair", "processional"]):
		_ruins_colonnade(d)
	elif PoiKit.brief_says(b, ["face down", "colossus", "walked away"]):
		_ruins_colossus(d)
	elif PoiKit.brief_says(b, ["wardstone", "thorn", "briar", "gap"]):
		_ruins_breach(d)
	else:
		_ruins_hall(d)


## A hall or a house: three rooms of courses, one gable still up, the hearth in the middle of
## what was the hall, and its roof slates in a heap where the roof came down.
static func _ruins_hall(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	var perp := Vector2(-grain.y, grain.x)
	var stone := m.begin()
	# the plan: a long range with a cross wing, laid out along the grain
	var w := 7.0
	var l := 13.0
	var c0 := -grain * (l * 0.5)
	var c1 := grain * (l * 0.5)
	var corners := [
		c0 - perp * (w * 0.5), c1 - perp * (w * 0.5),
		c1 + perp * (w * 0.5), c0 + perp * (w * 0.5),
	]
	# one gable stands nearly full height; the rest is knee to shoulder
	var heights := [0.9, 4.6, 1.3, 0.7]
	var breaks := [0.55, 0.15, 0.6, 0.75]
	for i in 4:
		var a: Vector2 = corners[i]
		var bb: Vector2 = corners[(i + 1) % 4]
		m.wall(stone, a, bb, float(heights[i]), float(breaks[i]))
	# the cross wall, and the doorway in the long wall that still has its lintel
	var mid := (c0 + c1) * 0.5 + grain * 1.5
	m.wall(stone, mid - perp * (w * 0.5), mid + perp * (w * 0.5), 1.1, 0.5)
	m.doorway(stone, c0 + grain * 0.1, yaw + PI, 1.3, 2.2)
	m.commit(stone, k.surface("stone", 0.75), "Courses", true)
	# the hearth: a ring of stones with the chimney breast behind it in the gable wall
	var hearth_at := (c0 + c1) * 0.5 - grain * 2.5
	var breast := m.begin()
	m.block(breast, Transform3D(Basis(Vector3.UP, yaw), k.on_ground(hearth_at.x - grain.x * 2.0, hearth_at.y - grain.y * 2.0, 0.9)),
			Vector3(2.4, 1.8, 0.7))
	m.commit(breast, k.surface("stone", 0.9), "Hearth", true)
	k.place(k.prop("campfire"), k.on_ground(hearth_at.x, hearth_at.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	var ring: Array = []
	for p in k.ring(8, 0.85, hearth_at, 0.1):
		var pp: Vector2 = p
		ring.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.1, 0.16)))
	k.scatter(k.rock("boulder"), ring)
	# the roof, where it fell: slabs flat inside the walls, and rubble along their feet
	var fallen: Array = []
	for i in 16:
		var p := (c0 + c1) * 0.5 + grain * k.rng.randf_range(-l * 0.45, l * 0.45) + perp * k.rng.randf_range(-w * 0.4, w * 0.4)
		fallen.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.15), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.55),
				Vector3(PI * 0.5 + k.rng.randf_range(-0.2, 0.2), 0.0, k.rng.randf_range(-0.25, 0.25))))
	k.scatter(k.rock("cliff_slab"), fallen, true)
	var rubble: Array = []
	for i in 26:
		var side := 1.0 if k.rng.randf() > 0.5 else -1.0
		var p := (c0 + c1) * 0.5 + grain * k.rng.randf_range(-l * 0.6, l * 0.6) + perp * (w * 0.5 + k.rng.randf_range(0.2, 2.2)) * side
		rubble.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.25, 0.6)))
	k.scatter(k.rock("boulder", 1), rubble, true)
	# what is left inside: a sarcophagus or a coffin if this was a barrow's business, else
	# the household's crocks, and grass growing through all of it
	if PoiKit.brief_says(d.brief, ["barrow", "tomb", "grave"]):
		k.place(k.prop("sarcophagus"), k.on_ground(mid.x + grain.x * 2.5, mid.y + grain.y * 2.5), yaw)
	else:
		for i in 4:
			var p := (c0 + c1) * 0.5 + grain * k.rng.randf_range(-3.5, 3.5) + perp * k.rng.randf_range(-2.0, 2.0)
			k.place(k.prop(["barrel", "crate", "jug", "bucket"][i]), k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), 1.0, i < 2)
	var grass: Array = []
	for i in 40:
		var p := (c0 + c1) * 0.5 + k.jitter(11.0)
		grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
	k.scatter(k.flora("grass_clump"), grass, false, false, false)


## The Stair of Isse: an Oroth colonnade rising step by step out of the water, its columns
## broken to different heights, the processional way still going somewhere.
static func _ruins_colonnade(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var water := k.water_direction(80.0)
	var up := -water if water != Vector2.ZERO else -k.downhill()
	if up == Vector2.ZERO:
		up = k.grain()
	var perp := Vector2(-up.y, up.x)
	var yaw := PoiKit.yaw_of(up)
	var stone := m.begin()
	# the steps, rising out of the water along `up`
	var start := -up * 16.0
	var g0 := k.on_ground(start.x, start.y).y
	m.steps(stone, start, up, g0 - 1.2, 13, 0.32, 1.5, 9.0, 0.7)
	# the columns, in two rows flanking the way, broken to different heights
	var cols := 7
	for i in cols:
		var t := float(i)
		for s in [-1.0, 1.0]:
			var p := start + up * (2.2 + t * 2.4) + perp * float(s) * 3.6
			var base := k.on_ground(p.x, p.y).y - 0.3 + 0.32 * minf(t * 1.6, 13.0)
			var h := float([6.4, 2.1, 5.2, 1.2, 4.0, 6.8, 0.8][i % 7]) * k.rng.randf_range(0.9, 1.1)
			var frame := Transform3D(Basis.IDENTITY, Vector3(p.x, base, p.y))
			m.drum(stone, frame, 0.62, h, 0.35, NAN, true, 0.5)
			# the top drum of a column that is nearly whole
			if h > 5.0:
				m.block(stone, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, base + h + 0.18, p.y)), Vector3(1.5, 0.36, 1.5))
	m.commit(stone, k.surface("oroth", 0.6), "Colonnade", true)
	# the drums that fell, lying where they rolled
	var drums: Array = []
	for i in 12:
		var p := start + up * k.rng.randf_range(2.0, 17.0) + perp * k.rng.randf_range(-7.0, 7.0)
		drums.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.6, 1.0),
				Vector3(PI * 0.5, 0.0, k.rng.randf_range(-0.3, 0.3))))
	k.scatter(k.rock("sunken_masonry"), drums, true, true)
	# a rope somebody tied to the last dry step and never untied
	var reeds: Array = []
	for i in 50:
		var p := start + up * k.rng.randf_range(-4.0, 18.0) + perp * k.rng.randf_range(-11.0, 11.0)
		if absf(perp.dot(p - start)) < 3.0:
			continue
		reeds.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)
	var rope_at := start + up * 2.0 + perp * 2.2
	k.place(k.prop("rope_coil"), k.on_ground(rope_at.x, rope_at.y, 0.3), k.rng.randf_range(0.0, TAU), 1.0, false)
	k.place(k.prop("dock_post"), k.on_ground(rope_at.x + perp.x * 1.2, rope_at.y + perp.y * 1.2), yaw, 1.1)


## The Thirteenth: a colossus lying face down a long way from the ring, as if it walked away,
## with its head — and it is not the head of the others — buried in the ash, and a Sayer camp
## digging at it.
##
## WORLD_BIBLE §6.6 makes the Choir twelve carved figures fifty metres tall; this is the thirteenth,
## fallen. The first dressing built it from boxes and a dome in the coursed Oroth surface and it
## photographed as a wall and an igloo: masonry, not a body. It is carved now, as the Headless
## Watch's head is: rounded masses for the back, the shoulder blades and the hips, limbs as long
## round forms, the soles of its feet turned up and the toes dug in, one arm flung out ahead of it
## with the fingers spread on the ground, the other at its side, and one knee drawn out to the side
## mid-stride. The ash has drifted against its flanks. Its head is down in the diggings, hooded,
## which none of the Choir's heads is: the Sayers' trench has found the rim of the hood and the
## seam that runs over the crown.
static func _ruins_colossus(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var lie := k.grain()
	var perp := Vector2(-lie.y, lie.x)
	var yaw := PoiKit.yaw_of(lie)
	var basis := Basis(Vector3.UP, yaw)
	# A point on the figure: `s` metres along it from the hips (toward the head), `l` across it,
	# `h` above the ground there. Everything stands on the ground it is over, not on the pad's
	# middle, because a figure this long runs off the flattened pad at both ends.
	var at := func(s: float, l: float, h: float) -> Vector3:
		var xz: Vector2 = lie * s + perp * l
		return Vector3(xz.x, k.on_ground(xz.x, xz.y).y + h, xz.y)
	var body := m.begin()
	# the back: shoulders, the blades standing out of them, the long back and the hips
	m.ellipsoid(body, at.call(10.5, 0.0, 1.2), Vector3(7.6, 2.9, 4.4), basis)
	for side in [-1.0, 1.0]:
		m.ellipsoid(body, at.call(9.4, 3.0 * float(side), 3.1), Vector3(2.6, 1.1, 3.0), basis)
	m.ellipsoid(body, at.call(4.0, 0.0, 1.3), Vector3(6.0, 2.8, 8.0), basis)
	for side in [-1.0, 1.0]:
		m.ellipsoid(body, at.call(-2.2, 2.4 * float(side), 1.6), Vector3(3.1, 2.5, 3.3), basis)
	# the left leg straight out behind, the right drawn up and out, as if it fell mid-stride
	var legs := [
		[at.call(-4.0, 2.3, 1.2), at.call(-13.0, 2.8, 1.0), at.call(-21.5, 3.1, 0.8)],
		[at.call(-4.0, -2.3, 1.2), at.call(-11.0, -8.0, 1.1), at.call(-18.5, -7.2, 0.8)],
	]
	for leg in legs:
		m.limb(body, leg[0], leg[1], 2.1)
		m.limb(body, leg[1], leg[2], 1.6)
		# the foot, sole to the sky and toes dug into the ash
		var toward: Vector3 = (leg[2] - leg[1]).normalized()
		var foot: Vector3 = leg[2] + toward * 1.8 + Vector3(0.0, 0.5, 0.0)
		m.ellipsoid(body, foot, Vector3(1.3, 0.9, 2.6), Basis(Vector3.UP, atan2(toward.x, toward.z)) * Basis(Vector3.RIGHT, 0.7))
	# the left arm flung out ahead of it, past the head, the hand flat and the fingers spread
	var shoulder_l: Vector3 = at.call(12.5, 6.4, 1.5)
	var elbow_l: Vector3 = at.call(19.5, 8.6, 1.0)
	var wrist_l: Vector3 = at.call(26.5, 9.6, 0.7)
	m.limb(body, shoulder_l, elbow_l, 1.6)
	m.limb(body, elbow_l, wrist_l, 1.3)
	m.ellipsoid(body, at.call(28.4, 9.9, 0.35), Vector3(1.3, 0.35, 1.7), basis)
	for f in 4:
		var across := -0.9 + float(f) * 0.6
		m.limb(body, at.call(29.6, 9.9 + across, 0.28), at.call(31.2 - absf(across) * 0.6, 10.1 + across * 1.3, 0.22), 0.27)
	m.limb(body, at.call(27.8, 8.7, 0.3), at.call(29.0, 7.9, 0.24), 0.3)
	# the right arm down at its side, the hand by the hip
	var shoulder_r: Vector3 = at.call(12.0, -6.6, 1.4)
	var elbow_r: Vector3 = at.call(5.0, -8.2, 1.0)
	var wrist_r: Vector3 = at.call(-1.5, -8.6, 0.7)
	m.limb(body, shoulder_r, elbow_r, 1.6)
	m.limb(body, elbow_r, wrist_r, 1.3)
	m.ellipsoid(body, at.call(-3.4, -8.4, 0.35), Vector3(1.2, 0.35, 1.6), basis)
	for f in 4:
		var across := -0.8 + float(f) * 0.55
		m.limb(body, at.call(-4.5, -8.4 + across, 0.28), at.call(-6.0 + absf(across) * 0.5, -8.4 + across * 1.2, 0.22), 0.25)
	# the neck going down into the diggings
	m.limb(body, at.call(14.5, 0.0, 1.0), at.call(16.8, 0.0, 0.1), 2.3)
	# The Choir are singers, robed: the robe's folds run down its back from the shoulders to the
	# hips, cut as ridges that follow the back's own curve. A smooth back read as a thing inflated.
	var back_h := func(s: float, l: float) -> float:
		var e1 := 1.3 + 2.8 * sqrt(maxf(0.0, 1.0 - pow(l / 6.0, 2.0) - pow((s - 4.0) / 8.0, 2.0)))
		var e2 := 1.2 + 2.9 * sqrt(maxf(0.0, 1.0 - pow(l / 7.6, 2.0) - pow((s - 10.5) / 4.4, 2.0)))
		return maxf(e1, e2)
	for fold in [-4.2, -2.1, 0.0, 2.1, 4.2]:
		var along := [12.0, 8.5, 5.0, 1.5, -1.8]
		var prev := Vector3.INF
		for s_v in along:
			var s := float(s_v)
			var l := float(fold) * (1.0 - maxf(0.0, (5.0 - s)) * 0.03)
			var p: Vector3 = at.call(s, l, back_h.call(s, l) - 0.18)
			if prev != Vector3.INF:
				m.limb(body, prev, p, 0.38)
			prev = p
	# Carved stone, not coursed. In the Oroth courses the first one came out a wall, and on round
	# forms the courses' joints drew seams, which made a body of capsules look inflated: a carved
	# thing has no joints. The Builders' dark stone with the hairline cracks of long weathering
	# (the painted surface's plaster pattern) is what one piece of cut stone looks like.
	var carved := PoiKit.painted(0, PoiKit.OROTH, 0.8, 0.9)
	carved.set_shader_parameter("unit_size", 1.6)
	m.commit(body, carved, "Colossus", true)
	# what has come off it: the last joints of the flung hand's fingers, and shards of the same
	# stone along its flanks, half in the ash (the region's boulders are fused glass, and read as
	# something else lying beside it)
	var shards := m.begin()
	for i in 12:
		var s := k.rng.randf_range(-12.0, 30.0)
		var side := (1.0 if k.rng.randf() > 0.5 else -1.0) * k.rng.randf_range(8.5, 12.5)
		var size := k.rng.randf_range(0.5, 1.1)
		var turn := Basis(Vector3.UP, k.rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, k.rng.randf_range(-0.3, 0.3))
		# none where the Sayers have pitched their camp, on the head's right: they would have
		# carted them off the dig (and a shard is solid, and a Sayer stands there)
		if side < 0.0 and s > 14.0:
			continue
		m.ellipsoid(shards, at.call(s, side, size * 0.25), Vector3(size, size * 0.6, size * 1.3), turn)
	for f in 3:
		m.limb(shards, at.call(32.6 + float(f) * 1.0, 9.2 + float(f) * 0.9, 0.2),
				at.call(33.3 + float(f) * 1.0, 9.6 + float(f) * 0.9, 0.15), 0.27)
	m.commit(shards, carved, "Shards", true)
	# collision: the back, and each limb as a box along it
	k.collider(Vector3(13.0, 4.6, 20.0), Transform3D(basis, at.call(5.0, 0.0, 1.8)), "stone")
	for pair in [[legs[0][0], legs[0][1], 2.1], [legs[0][1], legs[0][2], 1.6], [legs[1][0], legs[1][1], 2.1],
			[legs[1][1], legs[1][2], 1.6], [shoulder_l, elbow_l, 1.6], [elbow_l, wrist_l, 1.3],
			[shoulder_r, elbow_r, 1.6], [elbow_r, wrist_r, 1.3]]:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var r: float = pair[2]
		k.collider(Vector3(r * 1.8, r * 1.8, a.distance_to(b)),
				Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5), "stone")
	# The head, hooded, and down in the ash to above the brow: the back of the hood and its peak,
	# drawn back toward the neck, are what the trench has found. None of the Choir's heads is
	# hooded; the Headless Watch is one of theirs and is bare.
	var head_at: Vector3 = at.call(19.6, 0.0, -0.8)
	var head := m.begin()
	m.ellipsoid(head, head_at, Vector3(3.0, 3.3, 3.9), basis)
	# the cowl, standing off the skull all round and open toward the ground where the face is
	m.ellipsoid(head, head_at + basis * Vector3(0.0, 0.5, -0.6), Vector3(3.7, 3.5, 4.0), basis)
	# the hood's peak, laid back along the neck the way cloth falls when the head goes down
	m.limb(head, head_at + basis * Vector3(0.0, 2.6, -2.2), head_at + basis * Vector3(0.0, 3.3, -5.0), 1.05)
	m.limb(head, head_at + basis * Vector3(0.0, 3.3, -5.0), head_at + basis * Vector3(0.0, 2.8, -6.6), 0.6)
	# the hood's rim where it meets the ash on either side
	for side in [-1.0, 1.0]:
		m.limb(head, head_at + basis * Vector3(3.2 * float(side), 0.2, 2.2), head_at + basis * Vector3(3.5 * float(side), 1.2, -1.4), 0.55)
	var hood := PoiKit.painted(0, PoiKit.OROTH, 0.7, 0.9)
	hood.set_shader_parameter("unit_size", 1.3)
	m.commit(head, hood, "Head", true)
	k.collider(Vector3(7.0, 3.6, 7.6), Transform3D(basis, head_at + Vector3(0.0, 1.4, 0.0)), "stone")
	# the ash drifted against its flanks, which is how something this size is half sunk
	var ash := k.surface("earth", 0.9)
	ash.set_shader_parameter("base_color", Color(0.14, 0.135, 0.13))
	ash.set_shader_parameter("accent_color", Color(0.19, 0.18, 0.17))
	for drift in [[6.0, 7.9, 3.6], [-1.0, -6.8, 3.0], [13.0, -8.4, 3.2], [-9.0, 6.2, 3.4]]:
		var p: Vector3 = at.call(float(drift[0]), float(drift[1]), -0.2)
		m.mound(p, float(drift[2]), 1.3, ash, "Drift", false, 1.8, 6, 16, true, 0.12)
	# the Sayers' dig: the trench round the head, spoil heaps, a ladder down, a hoist over it,
	# tents, lanterns, a table of findings
	var head2d := Vector2(head_at.x, head_at.z)
	var dug := k.surface("earth", 0.95)
	dug.set_shader_parameter("base_color", Color(0.14, 0.13, 0.12))
	dug.set_shader_parameter("accent_color", Color(0.2, 0.19, 0.17))
	m.pool(head2d, 5.6, k.on_ground(head2d.x, head2d.y).y + 0.03, dug, "Diggings", 26)
	var spoil: Array = []
	for p in k.ring(16, 7.4, head2d, 0.1):
		var pp: Vector2 = p
		spoil.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.6, 1.1)))
	k.scatter(k.rock("scree"), spoil)
	var timber := m.begin()
	# the hoist: three poles leaning together over the crown, and a rope hanging from them
	var over := head_at + Vector3(0.0, 7.2, 0.0)
	for i in 3:
		var a := TAU * float(i) / 3.0 + yaw
		var foot2 := head2d + Vector2(sin(a), cos(a)) * 5.2
		var foot3 := k.on_ground(foot2.x, foot2.y)
		m.limb(timber, foot3, over, 0.12)
	m.rod(timber, Transform3D(Basis.IDENTITY, over - Vector3(0.0, 2.2, 0.0)), 0.03, 4.4)
	# The camp is on the head's right and ahead of it, the one quarter the figure leaves open:
	# behind the head are its own neck and shoulders, and its left arm is flung out past the head
	# on the other side. The first camp was measured from the head toward the hips and stood
	# inside the carving (the table, the lamp and the ladder in its shoulders, a tent in its arm).
	var right := -perp
	var toward_head := Vector3(perp.x, 0.0, perp.y)
	# a ladder down into the trench beside the head
	var ladder := head2d + right * 5.6
	var lg := k.on_ground(ladder.x, ladder.y)
	for s in [-1.0, 1.0]:
		m.limb(timber, lg + Vector3(lie.x, 0.0, lie.y) * 0.3 * float(s) - Vector3(0.0, 0.4, 0.0),
				lg + Vector3(lie.x, 0.0, lie.y) * 0.3 * float(s) + toward_head * 1.2 + Vector3(0.0, 2.6, 0.0), 0.05)
	m.commit(timber, k.surface("timber", 0.6), "Hoist", true)
	for t in [head2d + right * 10.5 - lie * 1.0, head2d + right * 7.0 + lie * 8.5]:
		var tp: Vector2 = t
		k.place(k.prop("tent"), k.on_ground(tp.x, tp.y), PoiKit.yaw_of(head2d - tp), 1.0, true, Vector3.ZERO, true)
		var crate := tp + (head2d - tp).normalized() * 2.8
		k.place(k.prop("crate"), k.on_ground(crate.x, crate.y), k.rng.randf_range(0.0, TAU))
	var table := head2d + right * 8.0 + lie * 4.0
	k.place(k.prop("table_trestle"), k.on_ground(table.x, table.y), yaw)
	k.place(k.prop("scroll"), k.on_ground(table.x, table.y, 0.75), yaw, 1.0, false)
	k.place(k.prop("book"), k.on_ground(table.x + 0.4, table.y + 0.2, 0.75), yaw + 0.5, 1.0, false)
	var lamp := head2d + right * 6.4 + lie * 2.0
	k.place(k.prop("lantern_standing"), k.on_ground(lamp.x, lamp.y), 0.0)
	k.light(k.on_ground(lamp.x, lamp.y, 1.9), Color(1.0, 0.82, 0.55), 1.8, 10.0)
	# where the two Sayers work: at the findings, on the trench's lip by the ladder, and down in
	# the trench by the hood (one marker each: a body stands exactly on its marker)
	var finds := table + right * 1.4
	k.marker("the_finds_table", k.on_ground(finds.x, finds.y), true)
	var lip := head2d + right * 6.4 - lie * 1.2
	k.marker("the_dig", k.on_ground(lip.x, lip.y), true)
	var trench := head2d + right * 4.2 + lie * 2.8
	k.marker("in_the_trench", k.on_ground(trench.x, trench.y), true)
	var grass: Array = []
	for i in 30:
		var p := k.jitter(18.0)
		grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(k.flora("grey_grass"), grass, false, false, false)


## The Breach: broken Oroth wardstones in a gap in the Briar, the thorns dead in a line where
## something walked through them.
static func _ruins_breach(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var through := k.grain()
	var perp := Vector2(-through.y, through.x)
	var yaw := PoiKit.yaw_of(through)
	var stone := m.begin()
	# the wardstones: four great slabs in a line across the gap, two of them snapped
	for i in 4:
		var t := float(i) - 1.5
		var p := perp * (t * 4.6)
		var h := float([5.4, 1.8, 2.6, 5.0][i])
		var frame := Transform3D(Basis(Vector3.UP, yaw + k.rng.randf_range(-0.1, 0.1))
				* Basis(Vector3.BACK, k.rng.randf_range(-0.12, 0.12)), k.on_ground(p.x, p.y, -0.3))
		m.drum(stone, frame, 1.05, h, 0.5, NAN, true, 0.62)
	m.commit(stone, k.surface("oroth", 0.7), "Wardstones", true)
	# the pieces that came off them, lying in the gap
	var shards: Array = []
	for i in 14:
		var p := perp * k.rng.randf_range(-9.0, 9.0) + through * k.rng.randf_range(-4.0, 4.0)
		shards.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 1.0),
				Vector3(k.rng.randf_range(0.6, PI * 0.5), 0.0, k.rng.randf_range(-0.4, 0.4))))
	k.scatter(k.rock("sunken_masonry"), shards, true, true)
	# the Briar either side, alive, and dead where the thing walked
	var briar := k.flora("briar_vine")
	var living: Array = []
	var dead: Array = []
	for i in 90:
		var across := k.rng.randf_range(-22.0, 22.0)
		var along := k.rng.randf_range(-7.0, 7.0)
		var p := perp * across + through * along
		var xf := PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(1.1, 2.0))
		if absf(across) < 9.0:
			if k.rng.randf() > 0.72:
				dead.append(xf)
		else:
			living.append(xf)
	k.scatter(briar, living, false, true, false)
	var withered := k.scatter(briar, dead, false, false, false)
	if withered != null:
		# the thorns died where it walked: the same vine, ash-grey
		var grey := PoiKit.plain(Color(0.42, 0.40, 0.36), 0.95)
		grey.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		var src := PoiKit.mesh(briar)
		if src != null and src.get_surface_count() > 0:
			var m0 := src.surface_get_material(0)
			if m0 is StandardMaterial3D:
				grey.albedo_texture = (m0 as StandardMaterial3D).albedo_texture
				grey.albedo_color = Color(0.55, 0.52, 0.48)
		withered.material_override = grey
	# ash-wights a long way from home leave the ash they walk in
	var ash: Array = []
	for i in 16:
		var p := perp * k.rng.randf_range(-6.0, 6.0) + through * k.rng.randf_range(-9.0, 9.0)
		ash.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.02), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.2)))
	k.scatter(k.flora("grey_grass"), ash, false, false, false)


# --- giant bones ---------------------------------------------------------------------------------------

## One animal, laid out as one animal. The forge built the parts — a rib seven metres tall, a
## vertebra, a finger, a piece of skull — and a heap of them is a quarry; a spine running away
## from you with its ribs arching over your head is a nave. So both of these are articulated:
## the spine is a line of vertebrae with the ribs in pairs along it, and you walk down the
## inside of it.
static func giant_bones(d: PoiDressing) -> void:
	if PoiKit.brief_says(d.brief, ["skull", "antler"]):
		_bones_skull(d)
	else:
		_bones_ribcage(d)


## The spine and ribs, walked through: `count` pairs of ribs along the line, arching in over
## the middle, with the vertebrae between them and the scapulae at the shoulder.
static func _bones_ribcage(d: PoiDressing) -> void:
	var k := d.kit
	var lie := k.grain()
	var perp := Vector2(-lie.y, lie.x)
	var yaw := PoiKit.yaw_of(lie)
	var rib := k.rock("bone_rib")
	var vert := k.rock("bone_vertebra")
	var rib_h := PoiKit.height_of(rib)
	var scale := 1.35
	var spacing := 3.4
	var pairs := 9
	var half := float(pairs - 1) * spacing * 0.5
	var ribs: Array = []
	var verts: Array = []
	# The forge's rib stands with its foot at the origin and curves over; a pair of them set
	# either side of the line and leaned inward closes over the aisle.
	for i in pairs:
		var along := -half + float(i) * spacing
		var taper := 1.0 - 0.30 * pow(absf(along) / maxf(half, 1.0), 1.6)
		var s := scale * taper
		var at := lie * along
		for side in [-1.0, 1.0]:
			var foot := at + perp * float(side) * (3.6 * taper)
			var lean := Vector3(0.0, 0.0, -0.34 * float(side))
			ribs.append(PoiKit.transform_at(k.on_ground(foot.x, foot.y, -0.35),
					yaw + (0.0 if side > 0.0 else PI), s, lean))
		# the vertebra at the top of the arch, on the spine itself
		var spine_y := k.on_ground(at.x, at.y).y + rib_h * s * 0.92
		verts.append(PoiKit.transform_at(Vector3(at.x, spine_y, at.y), yaw + PI * 0.5, s * 0.5,
				Vector3(0.0, 0.0, PI * 0.5)))
	k.scatter(rib, ribs, true, true)
	k.scatter(vert, verts, false, true)
	# the neck running on past the last rib, its vertebrae down into the ground
	var neck: Array = []
	for i in 6:
		var along := half + 2.6 + float(i) * 2.4
		var at := lie * along
		var drop := float(i) * 0.5
		neck.append(PoiKit.transform_at(k.on_ground(at.x, at.y, 1.4 - drop), yaw + PI * 0.5,
				scale * (0.62 - 0.04 * float(i)), Vector3(0.0, 0.0, PI * 0.5 + 0.1 * float(i))))
	k.scatter(vert, neck, true, true)
	# the skull at the end of the neck, its socket a door: the crag-wolves den in it
	var skull_at := lie * (half + 19.0)
	var skull := k.rock("bone_skull_fragment")
	k.place(skull, k.on_ground(skull_at.x, skull_at.y, -0.6), yaw + PI, 2.1, true, Vector3(0.12, 0.0, 0.06), true)
	# the scapulae, fallen flat at the shoulder
	for side in [-1.0, 1.0]:
		var sc := lie * (half * 0.5) + perp * float(side) * 7.5
		k.place(k.rock("bone_skull_fragment", 1), k.on_ground(sc.x, sc.y, -0.5), yaw + PI * 0.4 * float(side), 1.3,
				true, Vector3(PI * 0.42, 0.0, 0.0))
	# the clans hold their oaths here: a hearth on the aisle's floor, a stone to swear on
	var centre := Vector2.ZERO
	k.place(k.prop("campfire"), k.on_ground(centre.x, centre.y), k.rng.randf_range(0.0, TAU))
	k.light(k.on_ground(centre.x, centre.y, 0.9), Color(1.0, 0.66, 0.34), 2.6, 15.0)
	var stone_at := -lie * (half * 0.55)
	k.place(k.rock("standing_stone"), k.on_ground(stone_at.x, stone_at.y), yaw + PI, 0.8)
	for side in [-1.0, 1.0]:
		var bench := perp * float(side) * 2.2
		k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), yaw + PI * 0.5)
	# scree and heather under it all, and the smaller bones that came off
	var bits: Array = []
	for i in 22:
		var p := lie * k.rng.randf_range(-half - 4.0, half + 14.0) + perp * k.rng.randf_range(-9.0, 9.0)
		bits.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.8),
				Vector3(k.rng.randf_range(1.2, PI * 0.5), 0.0, k.rng.randf_range(-0.4, 0.4))))
	k.scatter(k.rock("bone_finger"), bits, true)
	var scree: Array = []
	for i in 26:
		var p := lie * k.rng.randf_range(-half - 6.0, half + 16.0) + perp * k.rng.randf_range(-12.0, 12.0)
		scree.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.5, 1.0)))
	k.scatter(k.rock("scree"), scree)
	var heather: Array = []
	for i in 40:
		var p := lie * k.rng.randf_range(-half - 8.0, half + 18.0) + perp * k.rng.randf_range(-14.0, 14.0)
		heather.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("heather"), heather, false, false, false)


## The Hart Bones: an antlered skull the size of a hall, jaw in the leaf litter, its antlers
## going up into the canopy — and a Hart-Knight's vigil kept at it.
static func _bones_skull(d: PoiDressing) -> void:
	var k := d.kit
	var face := k.grain()
	var perp := Vector2(-face.y, face.x)
	var yaw := PoiKit.yaw_of(face)
	var skull := k.rock("bone_skull_fragment")
	var g := k.on_ground(0.0, 0.0)
	# the skull: two pieces of the forge's cranium set nose to nose, at the size of a hall
	var s := 3.4
	k.place(skull, k.on_ground(0.0, 0.0, -0.9), yaw, s, true, Vector3(0.14, 0.0, 0.0), true)
	k.place(k.rock("bone_skull_fragment", 1), k.on_ground(face.x * 3.2, face.y * 3.2, -1.3), yaw + PI, s * 0.8,
			true, Vector3(-0.2, 0.0, 0.05), true)
	# the antlers: the forge's finger bones, branching up and out from the crown in two racks
	var antlers: Array = []
	var crown := Vector3(-face.x * 1.2, g.y + PoiKit.height_of(skull) * s * 0.78, -face.y * 1.2)
	for side in [-1.0, 1.0]:
		var base := crown + Vector3(perp.x, 0.0, perp.y) * float(side) * 2.2
		for i in 5:
			var t := float(i) / 4.0
			var out := 1.6 + t * 6.5
			var up := 1.2 + t * 4.2 - t * t * 1.4
			var tip := base + Vector3(perp.x, 0.0, perp.y) * float(side) * out + Vector3(0.0, up, 0.0) \
					+ Vector3(face.x, 0.0, face.y) * (t * 2.2 - 0.6)
			antlers.append(PoiKit.transform_at(tip, yaw + float(side) * (0.4 + t * 0.7), 1.5 - t * 0.5,
					Vector3(0.0, 0.0, float(side) * (1.15 - t * 0.5))))
			# a tine off each beam
			if i % 2 == 1:
				antlers.append(PoiKit.transform_at(tip + Vector3(0.0, 1.4, 0.0), yaw + float(side) * 1.2, 0.8,
						Vector3(0.5, 0.0, float(side) * 0.3)))
	k.scatter(k.rock("bone_finger"), antlers, false, true)
	# the vigil: a knight's fire, a spear set in the ground, a shield against the jaw
	var camp_at := face * 7.0 + perp * 2.5
	k.place(k.prop("campfire"), k.on_ground(camp_at.x, camp_at.y), 0.0)
	k.light(k.on_ground(camp_at.x, camp_at.y, 0.9), Color(1.0, 0.66, 0.34), 2.4, 12.0)
	k.place(k.prop("bedroll"), k.on_ground(camp_at.x + perp.x * 1.8, camp_at.y + perp.y * 1.8), yaw)
	var spear := camp_at - perp * 1.6
	k.place(k.prop("spear"), k.on_ground(spear.x, spear.y), yaw, 1.0, false, Vector3(0.06, 0.0, 0.06))
	k.place(k.prop("shield"), k.on_ground(face.x * 4.2 + perp.x * -2.0, face.y * 4.2 + perp.y * -2.0), yaw + 0.6,
			1.0, false, Vector3(-0.3, 0.0, 0.0))
	# the wood round it: ferns, bracken, and the antlers people have left in its memory
	var offerings: Array = []
	for p in k.ring(7, 6.5, Vector2.ZERO, 0.2):
		var pp: Vector2 = p
		offerings.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.4, 0.7),
				Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
	k.scatter(k.rock("bone_finger", 1), offerings, true)
	var ferns: Array = []
	for i in 46:
		var p := k.jitter(15.0)
		ferns.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("fern"), ferns, false, false, false)
	var moss: Array = []
	for i in 18:
		var p := k.jitter(9.0)
		moss.append(PoiKit.transform_at(k.on_ground(p.x, p.y, 0.02), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("moss_patch"), moss, false, false, false)


# --- strange trees ---------------------------------------------------------------------------------------

## A tree that is an event: one at a scale nothing else in the region reaches, or a species in
## the wrong place, and something hung in it or grown into it.
static func strange_tree(d: PoiDressing) -> void:
	if PoiKit.brief_says(d.brief, ["rooted again", "ring", "hall of trunks"]):
		_tree_sallow_king(d)
	elif PoiKit.brief_says(d.brief, ["islet", "island", "pollarded"]):
		_tree_willow_isle(d)
	else:
		_tree_singing_yew(d)


## A hollow yew with a bell grown into its heartwood, humming in any wind: one great yew at
## three times the scale of a hedge yew, its bell in the split of the trunk.
static func _tree_singing_yew(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	var yew := k.tree("yew")
	# 2.2, not 3.1: a tree's leaf cards scale with it, and past about twice its built size the
	# cards stop reading as foliage and start reading as spikes — the yew photographed as a
	# dark thorn-ball. Twice over is still half again the tallest hedge yew around it, which
	# is what makes it an event.
	var scale := 2.2
	k.place(yew, k.on_ground(0.0, 0.0), k.rng.randf_range(0.0, TAU), scale, true, Vector3.ZERO, true)
	# the split in the trunk, and the bell the tree ate, deep in it
	var bell := k.prop("bell_small")
	var bell_at := k.on_ground(0.0, 0.0, 2.6) + Vector3(grain.x, 0.0, grain.y) * 0.75
	k.place(bell, bell_at, yaw, 2.4, false, Vector3.ZERO, true)
	# the bark grown round it: two lips of timber either side of the bell
	var timber := m.begin()
	for s in [-1.0, 1.0]:
		var lip := bell_at + Vector3(-grain.y, 0.0, grain.x) * float(s) * 0.62
		m.block(timber, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, float(s) * 0.22), lip),
				Vector3(0.42, 1.9, 0.5))
	m.commit(timber, k.surface("timber", 0.8), "Bark", true)
	# the orchard-keepers count on it: a bench, and the bells they have hung in the branches
	var hung: Array = []
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.4
		var r := k.rng.randf_range(2.2, 4.4)
		var y := k.on_ground(0.0, 0.0).y + k.rng.randf_range(3.4, 6.2)
		hung.append(PoiKit.transform_at(Vector3(sin(a) * r, y, cos(a) * r), k.rng.randf_range(0.0, TAU), 1.3))
	k.scatter(bell, hung, false, true)
	var bench := grain * 5.5
	k.place(k.prop("bench"), k.on_ground(bench.x, bench.y), yaw + PI)
	# the wights will not pass it, and the barrow is that way: a line of gravestones stopping short
	for i in 3:
		var p := -grain * (7.0 + float(i) * 3.2) + Vector2(-grain.y, grain.x) * k.rng.randf_range(-1.6, 1.6)
		k.place(k.prop("gravestone"), k.on_ground(p.x, p.y), yaw + k.rng.randf_range(-0.4, 0.4), 1.0, true,
				Vector3(k.rng.randf_range(-0.12, 0.12), 0.0, k.rng.randf_range(-0.14, 0.14)))
	# and past the last stone, where the dead come up the hedge line after dark and stop
	var beyond := -grain * 17.5
	k.marker("the_gravestones", k.on_ground(beyond.x, beyond.y))
	var grass: Array = []
	for i in 34:
		var p := k.jitter(12.0)
		grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("grass_clump"), grass, false, false, false)


## The Sallow King: a willow whose branches rooted again in a ring, making a hall of trunks
## you walk into, with the sallowjaws' water under its roots.
static func _tree_sallow_king(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var willow := k.tree("willow")
	# the king in the middle, and the ring its branches made when they came down and rooted
	k.place(willow, k.on_ground(0.0, 0.0), k.rng.randf_range(0.0, TAU), 1.5, true, Vector3.ZERO, true)
	var ring := k.ring(7, 11.0, Vector2.ZERO, 0.1)
	# all seven rooted limbs in one mesh: a commit inside the loop is a draw call per branch
	var timber := m.begin()
	for p in ring:
		var pp: Vector2 = p
		k.place(willow, k.on_ground(pp.x, pp.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.62, 0.85),
				true, Vector3.ZERO, true)
		# the branch that came down and rooted: a limb of timber from the king out to it
		var from := Vector3(0.0, k.on_ground(0.0, 0.0).y + 5.2, 0.0)
		var to := Vector3(pp.x, k.on_ground(pp.x, pp.y).y + 3.4, pp.y)
		var seg := to - from
		var pitch := atan2(seg.y, Vector2(seg.x, seg.z).length())
		m.rod(timber, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(Vector2(seg.x, seg.z)))
				* Basis(Vector3.RIGHT, PI * 0.5 - pitch), (from + to) * 0.5), 0.34, seg.length())
	m.commit(timber, k.surface("timber", 0.7), "Limbs", true)
	# the water inside the ring, where the sallowjaws nest under the roots
	var g := k.on_ground(0.0, 0.0)
	m.pool(Vector2(4.0, 2.0), 4.6, g.y - 0.15, k.still_water(g.y - 2.2, Color(0.8, 0.95, 0.85), 0.55))
	# where they lie, in the water under the roots, until somebody walks into the ring
	k.marker("the_pool", k.on_ground(4.0, 2.0))
	var reeds: Array = []
	for i in 60:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(2.0, 13.0)
		reeds.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)
	# the reedfolk feed them so they nest nowhere else: the offering post and its baskets
	var post_at := grain * 13.0
	k.place(k.prop("dock_post"), k.on_ground(post_at.x, post_at.y), 0.0, 1.2)
	for i in 3:
		var p := post_at + k.jitter(1.8)
		k.place(k.prop("basket"), k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU))
	k.place(k.prop("lantern_hanging"), k.on_ground(post_at.x, post_at.y, 1.9), 0.0, 1.0, false)
	k.light(k.on_ground(post_at.x, post_at.y, 1.8), Color(1.0, 0.8, 0.5), 1.4, 8.0)
	var marigold: Array = []
	for i in 22:
		var p := k.jitter(12.0)
		marigold.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.3)))
	k.scatter(k.flora("marsh_marigold"), marigold, false, false, false)


## Willow Isle: an islet raised out of the lake under one pollarded willow the size of a barn,
## with the hermit's boat moored in its roots.
static func _tree_willow_isle(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	var g := k.on_ground(0.0, 0.0)
	var wl := k.water_y(0.0, 0.0)
	# the island: a dome of earth standing out of the water. Where the map has drawn the isle
	# itself -- the atlas's Willow Isle is land, its pad dry above the Mere -- the ground is the
	# isle, and a second one heaped on it buried the hermit's stool in its own hill.
	var drawn := is_nan(wl)
	var lake := g.y if drawn else wl
	var isle_r := 13.0
	var top := 0.0 if drawn else lake + 2.1 - g.y
	var isle: MeshInstance3D = null
	if not drawn:
		isle = m.mound(Vector3(0.0, 0.0, 0.0), isle_r, top + 0.4, k.surface("earth", 0.6), "Isle", true, 1.7, 8, 22, true)
	var surface := _surface_of(isle)
	var stand := func(x: float, z: float) -> float:
		return _surface_y(surface, x, z, k.on_ground(x, z).y)
	# the willow on the crown of it, at the size of a barn
	var crown := Vector3(0.0, stand.call(0.0, 0.0), 0.0)
	# 2.1 for the same reason as the Singing Yew: a leaf card scaled much past twice its built
	# size reads as a shard rather than foliage. A pollarded willow at 2.1 is ten metres over
	# an islet you can walk round in twenty paces, which is barn-sized enough.
	k.place(k.tree("willow_pollard"), crown, k.rng.randf_range(0.0, TAU), 2.1, true, Vector3.ZERO, true)
	# the hermit's boat moored in the roots, on the water: off the isle's own edge when it was
	# raised out of the lake, at the nearest shore when the map drew it
	var moor := grain.rotated(0.8) * (isle_r - 2.0)
	var moored := not drawn
	if drawn:
		var toward := k.water_direction(60.0)
		var span := k.water_span(toward, 60.0)
		moored = toward != Vector2.ZERO and span.x >= 0.0
		if moored:
			moor = toward * (span.x + 2.0)
			var level := k.water_y(moor.x, moor.y)
			lake = level if not is_nan(level) else lake
	if moored:
		# tied off toward the isle: along the grain off a heaped isle's edge, as it always was, and
		# back toward the shore it lies off when the map drew the isle
		var tie := grain if not drawn else -moor.normalized()
		var bow := grain if not drawn else moor.normalized()
		k.place(k.prop("rowboat"), Vector3(moor.x, lake - 0.12, moor.y), PoiKit.yaw_of(-bow) + 0.5, 1.0, true, Vector3.ZERO, true)
		var post := moor + tie * 1.6
		var post_y := lake - 0.3 if not drawn else minf(stand.call(post.x, post.y), lake) - 0.3
		k.place(k.prop("dock_post"), Vector3(post.x, post_y, post.y), 0.0, 0.9)
		var coil := moor + tie * 1.4
		var coil_y := lake + 0.2 if not drawn else maxf(stand.call(coil.x, coil.y), lake) + 0.2
		k.place(k.prop("rope_coil"), Vector3(coil.x, coil_y, coil.y), 0.0, 1.0, false)
	# what a clerk who stopped counting keeps: a stool, a book, a lantern, the crate he sits on,
	# each on the ground it stands on
	var camp_at := -grain * 4.0
	var stool := Vector3(camp_at.x, stand.call(camp_at.x, camp_at.y), camp_at.y)
	k.place(k.prop("stool"), stool, yaw)
	var crate := Vector2(camp_at.x + 1.2, camp_at.y + 0.4)
	var crate_y: float = stand.call(crate.x, crate.y)
	k.place(k.prop("crate"), Vector3(crate.x, crate_y, crate.y), yaw + 0.6)
	k.place(k.prop("book"), Vector3(crate.x, crate_y + 0.66, crate.y), yaw + 0.2, 1.0, false)
	# the book is his, and it is a thing a place's `lies` can name (the island's is read where it is)
	k.marker("the_hermits_book", Vector3(crate.x, crate_y + 0.66, crate.y))
	var lamp := Vector2(camp_at.x - 1.4, camp_at.y - 0.6)
	var lamp_y: float = stand.call(lamp.x, lamp.y)
	k.place(k.prop("lantern_standing"), Vector3(lamp.x, lamp_y, lamp.y), 0.0)
	k.light(Vector3(lamp.x, lamp_y + 1.9, lamp.y), Color(1.0, 0.82, 0.55), 1.7, 10.0)
	var fire := Vector2(camp_at.x - 0.2, camp_at.y - 2.2)
	var fire_y: float = stand.call(fire.x, fire.y)
	k.place(k.prop("campfire"), Vector3(fire.x, fire_y, fire.y), 0.0)
	k.light(Vector3(fire.x, fire_y + 0.8, fire.y), Color(1.0, 0.68, 0.35), 2.0, 10.0)
	# the hermit's own place, by his stool, on the isle's surface: raised, because under a heaped
	# isle is the lake bed
	var seat := Vector2(camp_at.x + 0.8, camp_at.y - 1.0)
	k.marker("the_hermits_stool", Vector3(seat.x, stand.call(seat.x, seat.y), seat.y), true, true, 3.0)
	# lilies on the water round the isle, and reeds at its foot: only where there is water
	var lilies: Array = []
	for i in 22:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(isle_r + 1.5, isle_r + 12.0)
		var x := sin(a) * r
		var z := cos(a) * r
		var w := k.water_y(x, z) if drawn else lake
		if is_nan(w):
			continue
		lilies.append(PoiKit.transform_at(Vector3(x, w + 0.03, z), k.rng.randf_range(0.0, TAU), 1.0))
	k.scatter(k.flora("waterlily_pad"), lilies, false, false, false)
	var reeds: Array = []
	for i in 40:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(isle_r - 2.5, isle_r + 1.0)
		if drawn:
			r = k.rng.randf_range(isle_r - 2.5, isle_r + 16.0)
		var x := sin(a) * r
		var z := cos(a) * r
		var y: float = stand.call(x, z)
		if drawn:
			var w := k.water_y(x, z)
			if is_nan(w) and not k.is_water(x, z + 3.0) and not k.is_water(x + 3.0, z):
				continue
			y = minf(y, w + 0.1) if not is_nan(w) else y
		else:
			y = minf(y, lake - g.y + 0.1)
		reeds.append(PoiKit.transform_at(Vector3(x, y, z), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)


## A raised mound's own surface, to stand things on it where it is rather than where a formula
## for its dome says it is (the dome is lobed and jittered); null for no mound.
static func _surface_of(mound: MeshInstance3D) -> TriangleMesh:
	if mound == null or mound.mesh == null:
		return null
	var tm := TriangleMesh.new()
	if not tm.create_from_faces(mound.mesh.get_faces()):
		return null
	return tm


## The height of `surface` over local (x, z), or `fallback` where it is not under the point.
static func _surface_y(surface: TriangleMesh, x: float, z: float, fallback: float) -> float:
	if surface == null:
		return fallback
	var hit: Dictionary = surface.intersect_segment(Vector3(x, 400.0, z), Vector3(x, -400.0, z))
	if hit.is_empty():
		return fallback
	return maxf(float((hit["position"] as Vector3).y), fallback)


# --- wrecks -----------------------------------------------------------------------------------------------

## A boat where a boat should not be: a broken hull of ribs and planking, its cargo spilled,
## and whatever has moved into the hold.
static func wreck(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var big := PoiKit.brief_says(d.brief, ["trading ship", "salt isles"])
	var water := k.water_direction(70.0)
	var lie := water if water != Vector2.ZERO else k.grain()
	var perp := Vector2(-lie.y, lie.x)
	var yaw := PoiKit.yaw_of(lie)
	var g := k.on_ground(0.0, 0.0)
	var length := 22.0 if big else 13.0
	var beam := 6.4 if big else 4.2
	var heel := 0.38 if big else 0.5          # how far she is over on her side
	var timber := m.begin()
	# the keel, down the middle, and the ribs standing off it in pairs — an open broken hull
	var keel_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, heel)
	m.block(timber, Transform3D(keel_basis, Vector3(0.0, g.y - 0.2, 0.0)), Vector3(0.7, 0.8, length))
	var ribs := 9 if big else 7
	for i in ribs:
		var t := (float(i) + 0.5) / float(ribs)
		var along := (t - 0.5) * length * 0.94
		var taper := 1.0 - 0.55 * pow(absf(t - 0.42) * 2.0, 1.7)
		var at := lie * along
		var base := k.on_ground(at.x, at.y)
		for s in [-1.0, 1.0]:
			# a rib is a board leaning out of the keel; the lee side stands, the weather side
			# is broken back to stumps
			var broken := (float(s) * (1.0 if heel > 0.0 else -1.0)) > 0.0
			var h := (beam * 0.62 * taper) * (0.35 if broken and k.rng.randf() > 0.4 else 1.0)
			var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, heel + float(s) * 0.55)
			m.block(timber, Transform3D(lean, base + lean * Vector3(0.0, h * 0.5, 0.0)),
					Vector3(0.22, h, 0.9 * taper + 0.3))
	# the planking left on the lee side: three strakes along the ribs
	for i in 3:
		var side := -1.0 if heel > 0.0 else 1.0
		var up := 0.7 + float(i) * 1.15
		var out := side * (beam * 0.42 - float(i) * 0.25)
		var strake := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, heel + side * 0.5),
				Vector3(perp.x * out, g.y + up, perp.y * out))
		m.block(timber, strake, Vector3(0.14, 0.9, length * (0.92 - 0.08 * float(i))))
	# the stem, standing up out of the bow, which is what says "boat" from a distance
	var bow := lie * (length * 0.5)
	m.block(timber, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.5),
			Vector3(bow.x, g.y + 1.9, bow.y)), Vector3(0.55, 4.2, 0.8))
	# the mast, snapped off and fallen across her
	var mast_from := Vector3(0.0, g.y + 0.9, 0.0)
	var mast_dir := Vector3(perp.x, 0.28, perp.y).normalized() * (1.0 if heel > 0.0 else -1.0)
	m.block(timber, Transform3D(Basis.looking_at(mast_dir, Vector3.UP), mast_from + mast_dir * (length * 0.3)),
			Vector3(0.44, 0.44, length * 0.62))
	m.commit(timber, k.surface("planks", 0.9), "Hull", true)
	k.collider(Vector3(beam, 2.4, length), Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, g.y + 1.0, 0.0)), "wood")
	# the deck boards that came off her, and the masonry she broke on
	var boards: Array = []
	for i in 14:
		var p := lie * k.rng.randf_range(-length * 0.7, length * 0.7) + perp * k.rng.randf_range(-7.0, 7.0)
		boards.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(k.prop("boardwalk_plank"), boards, true)
	var masonry := k.rock("sunken_masonry")
	if masonry != "" and not big:
		var rocks: Array = []
		for i in 7:
			var p := lie * k.rng.randf_range(-length * 0.4, length * 0.4) + perp * k.rng.randf_range(-4.0, 4.0)
			rocks.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.3), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.2),
					Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.3, 0.3))))
		k.scatter(masonry, rocks, true, true)
	# her cargo, spilled: barrels and crates down the beach, and the rope still on her
	for i in 5:
		var p := lie * k.rng.randf_range(-length * 0.6, length * 0.6) + perp * k.rng.randf_range(2.0, 8.0) * (1.0 if i % 2 == 0 else -1.0)
		k.place(k.prop(["barrel", "crate", "barrel", "sack", "crate"][i]), k.on_ground(p.x, p.y),
				k.rng.randf_range(0.0, TAU), 1.0, true, Vector3(k.rng.randf_range(-0.3, 0.3), 0.0, k.rng.randf_range(-0.4, 0.4)))
	var rope := perp * (beam * 0.5 + 1.0)
	k.place(k.prop("rope_coil"), k.on_ground(rope.x, rope.y), k.rng.randf_range(0.0, TAU), 1.0, false)
	# a lantern still hanging off the stem, which is the last thing anybody did on her
	k.place(k.prop("lantern_hanging"), Vector3(bow.x, g.y + 3.4, bow.y), yaw, 1.2, false)
	k.light(Vector3(bow.x, g.y + 3.2, bow.y), Color(1.0, 0.76, 0.45), 1.4, 8.0)
	# her hold is somebody's now: a chest under the shelter of the standing side
	var lee := perp * (beam * 0.3) * (-1.0 if heel > 0.0 else 1.0)
	k.place(k.prop("chest"), k.on_ground(lee.x, lee.y), yaw + 0.4)
	# the smugglers' cache, by the chest under her keel: a quest's `spot` lies here
	k.marker("under_the_keel", k.on_ground(lee.x + lie.x * 1.1, lee.y + lie.y * 1.1, 0.05))
	# where she lies: nets and gulls on the shingle, or reeds three miles inland
	var fringe := k.flora("reeds") if big else k.flora("grass_clump")
	var growth: Array = []
	for i in 46:
		var p := lie * k.rng.randf_range(-length, length) + perp * k.rng.randf_range(-14.0, 14.0)
		growth.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(fringe, growth, false, false, false)
	if big:
		# the chart nobody has read, on a crate under the bow
		var crate_at := bow + perp * 2.4
		k.place(k.prop("crate"), k.on_ground(crate_at.x, crate_at.y), yaw)
		k.place(k.prop("scroll"), k.on_ground(crate_at.x, crate_at.y, 0.66), yaw + 0.3, 1.0, false)
		k.marker("the_chart", k.on_ground(crate_at.x - perp.x * 0.3, crate_at.y - perp.y * 0.3, 0.66))


# --- hidden valleys ------------------------------------------------------------------------------------------

## Hidden means come upon: from outside there is a wall of something, and inside there is more
## than you expected. So each of these is a screen — scree, briar, mist — with a dell behind it
## that is dense with growth, has water in it, and has somebody's business in it.
static func hidden_valley(d: PoiDressing) -> void:
	var b := d.brief
	if PoiKit.brief_says(b, ["tarn", "scree"]):
		_valley_tarn(d)
	elif PoiKit.brief_says(b, ["wisp", "drowned house", "chimney"]):
		_valley_wisps(d)
	elif PoiKit.brief_says(b, ["silk", "mist at noon", "ravine"]):
		_valley_gully(d)
	elif PoiKit.brief_says(b, ["stair", "mist", "colour drains"]):
		_valley_hushline(d)
	else:
		_valley_dell(d)


## Foxglove Dell: a dry valley entirely purple with foxgloves round a hedge-witch's turf hut,
## with the hedge closing it in.
static func _valley_dell(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	# the hut: a turf dome with a door and a chimney, and a garden fenced off the valley
	var hut_at := -grain * 6.0
	var g := k.on_ground(hut_at.x, hut_at.y)
	m.mound(g, 4.2, 3.0, k.surface("earth", 0.55), "Turf", true, 1.5, 6, 18, true)
	var stone := m.begin()
	m.doorway(stone, hut_at + grain * 3.6, yaw, 1.1, 2.0)
	m.block(stone, Transform3D(Basis(Vector3.UP, yaw), g + Vector3(-1.4, 3.2, 0.6)), Vector3(0.7, 1.6, 0.7))
	m.commit(stone, k.surface("stone", 0.7), "Hut", true)
	k.puffs(g + Vector3(-1.4, 4.1, 0.6), Vector3(0.12, 0.1, 0.12), 0.5, 7, Color(0.6, 0.58, 0.56, 0.3), 0.9, 5.0)
	# what a hedge-witch has outside her door
	var door := hut_at + grain * 5.4
	k.place(k.prop("table_trestle"), k.on_ground(door.x + 1.8, door.y), yaw + PI * 0.5)
	k.place(k.prop("jug"), k.on_ground(door.x + 1.8, door.y, 0.75), 0.0, 1.0, false)
	k.place(k.prop("basket"), k.on_ground(door.x + 1.8, door.y + 0.9, 0.75), 0.4, 1.0, false)
	k.place(k.prop("cooking_pot"), k.on_ground(door.x - 1.6, door.y + 0.4), 0.0)
	k.place(k.prop("campfire"), k.on_ground(door.x - 1.6, door.y + 0.4), 0.0, 1.0, false)
	k.light(k.on_ground(door.x - 1.6, door.y + 0.4, 0.8), Color(1.0, 0.68, 0.35), 2.0, 10.0)
	k.place(k.prop("stool"), k.on_ground(door.x + 0.3, door.y - 1.6), yaw)
	k.place(k.prop("rope_coil"), k.on_ground(door.x + 2.6, door.y - 1.2), 0.0, 1.0, false)
	# Where Tansy Cresswell stands to sell after dark: out in front of her door, on whichever side
	# of it the table, the fire, the stool and the rope (set out along the world's axes, not the
	# hut's) have left room for a person.
	var things: Array[Vector2] = [Vector2(door.x + 1.8, door.y), Vector2(door.x - 1.6, door.y + 0.4),
			Vector2(door.x + 0.3, door.y - 1.6), Vector2(door.x + 2.6, door.y - 1.2)]
	var stand := door + grain * 3.0
	for a in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var c := door + grain.rotated(float(a)) * 3.0
		var clear := true
		for t in things:
			clear = clear and c.distance_to(t) >= 1.3
		if clear:
			stand = c
			break
	k.marker("the_witchs_door", k.on_ground(stand.x, stand.y), true)
	# the yew somebody has been digging up at night, and the hole they left
	var yew_at := grain * 7.0 + Vector2(-grain.y, grain.x) * 4.0
	k.place(k.tree("yew"), k.on_ground(yew_at.x, yew_at.y), k.rng.randf_range(0.0, TAU), 1.3, true, Vector3.ZERO, true)
	var dug: Array = []
	for i in 9:
		var p := yew_at + k.jitter(3.0)
		dug.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.1), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.3, 0.6)))
	k.scatter(k.rock("scree"), dug)
	# the hedge round the valley, and the foxgloves that are the whole point of it
	var fence := k.prop("fence_wattle", 0)
	var panels: Array = []
	for p in k.ring(11, 15.0, Vector2.ZERO, 0.06):
		var pp: Vector2 = p
		if absf(angle_difference(PoiKit.yaw_of(pp), PoiKit.yaw_of(grain))) < 0.45:
			continue
		panels.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y), PoiKit.yaw_of(pp) + PI * 0.5, 1.0))
	k.scatter(fence, panels, true, true)
	var hedge: Array = []
	for i in 60:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(14.0, 18.0)
		hedge.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.1)))
	k.scatter(k.tree("hawthorn"), hedge, false, true)
	var foxglove := k.flora("foxglove")
	var flowers: Array = []
	for i in 260:
		var a := k.rng.randf_range(0.0, TAU)
		var r := 13.0 * sqrt(k.rng.randf())
		flowers.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.85, 1.35)))
	k.scatter(foxglove, flowers, false, false, false)
	# and where she works by day, among them, on the far side of the valley from the yew
	var beds := grain * 3.0 - Vector2(-grain.y, grain.x) * 6.0
	k.marker("the_foxglove_beds", k.on_ground(beds.x, beds.y), true)


## The Hidden Tarn: black water perfectly still behind a wall of scree, under the Cradle's mouth.
static func _valley_tarn(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var g := k.on_ground(0.0, 0.0)
	# the wall of scree on the way in: a bank of stones you come over
	var bank: Array = []
	for i in 46:
		var a := PoiKit.yaw_of(grain) + k.rng.randf_range(-1.1, 1.1)
		var r := k.rng.randf_range(13.0, 19.0)
		var p := Vector2(sin(a), cos(a)) * r
		bank.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.2), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.5)))
	k.scatter(k.rock("scree"), bank, true, true)
	var boulders: Array = []
	for i in 14:
		var a := PoiKit.yaw_of(grain) + k.rng.randf_range(-1.3, 1.3)
		var r := k.rng.randf_range(11.0, 17.0)
		var p := Vector2(sin(a), cos(a)) * r
		boulders.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.4), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.6)))
	k.scatter(k.rock("boulder"), boulders, true, true)
	# the tarn: black, still, no fringe of anything, which is the point — nothing lives in it
	m.pool(Vector2.ZERO, 10.5, g.y + 0.1, k.still_water(g.y - 6.0, Color(0.5, 0.55, 0.6), 0.9), "Tarn", 30)
	# the cliffs it sits under, on the far side
	var slabs: Array = []
	for i in 9:
		var a := PoiKit.yaw_of(-grain) + k.rng.randf_range(-0.9, 0.9)
		var r := k.rng.randf_range(13.0, 16.0)
		var p := Vector2(sin(a), cos(a)) * r
		slabs.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.6), PoiKit.yaw_of(-p), k.rng.randf_range(0.9, 1.5),
				Vector3(k.rng.randf_range(-0.12, 0.05), 0.0, k.rng.randf_range(-0.1, 0.1))))
	k.scatter(k.rock("cliff_slab"), slabs, true, true)
	# the scree-hags fish it with their hands, and leave what they catch
	var hag := grain.rotated(2.2) * 12.0
	k.place(k.prop("basket"), k.on_ground(hag.x, hag.y), k.rng.randf_range(0.0, TAU))
	k.place(k.rock("bone_finger"), k.on_ground(hag.x + 1.4, hag.y + 0.8, -0.1), k.rng.randf_range(0.0, TAU), 0.5,
			true, Vector3(1.3, 0.0, 0.2))
	var lichen: Array = []
	for i in 30:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(11.0, 18.0)
		lichen.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r, 0.02), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.4)))
	k.scatter(k.flora("lichen_crust"), lichen, false, false, false)
	var heather: Array = []
	for i in 26:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(12.0, 20.0)
		heather.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(k.flora("heather"), heather, false, false, false)


## Wisp Hollow: a dead-end channel with a drowned house in it whose chimney still stands, and
## the wisps that a water-burial becomes when nobody sings.
static func _valley_wisps(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var yaw := PoiKit.yaw_of(grain)
	var g := k.on_ground(0.0, 0.0)
	var wl := k.water_y(0.0, 0.0)
	var level := (wl if not is_nan(wl) else g.y + 0.3) - g.y
	# the channel: water filling the hollow, with the house standing in it
	m.pool(Vector2.ZERO, 15.0, level, k.still_water(g.y - 1.5, Color(0.75, 0.9, 0.85), 0.62), "Channel", 26)
	# the house: the tops of two walls and the chimney, above the water
	var stone := m.begin()
	var perp := Vector2(-grain.y, grain.x)
	var w := 4.4
	var l := 6.2
	var corners := [
		-grain * (l * 0.5) - perp * (w * 0.5), grain * (l * 0.5) - perp * (w * 0.5),
		grain * (l * 0.5) + perp * (w * 0.5), -grain * (l * 0.5) + perp * (w * 0.5),
	]
	for i in 4:
		var a: Vector2 = corners[i]
		var bb: Vector2 = corners[(i + 1) % 4]
		var mid := (a + bb) * 0.5
		var seg := bb - a
		var h := float([0.5, 1.1, 0.7, 0.4][i])
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(seg) + PI * 0.5),
				Vector3(mid.x, level + float(h) * 0.5 - 0.1, mid.y))
		m.block(stone, xf, Vector3(seg.length(), float(h), 0.45))
		k.collider(Vector3(seg.length(), float(h), 0.45), xf, "stone")
	# the chimney, which is the thing that still stands
	var stack := -grain * (l * 0.5 - 0.5)
	var xf2 := Transform3D(Basis(Vector3.UP, yaw), Vector3(stack.x, level + 2.3, stack.y))
	m.block(stone, xf2, Vector3(1.05, 5.0, 1.05))
	k.collider(Vector3(1.05, 5.0, 1.05), xf2, "stone")
	m.commit(stone, k.surface("stone", 0.85), "House", true)
	# the wisps: small cold lights over the water, and the pale motes about them. All five
	# bodies in one mesh; only the lights and the motes are per-wisp.
	var wisps := m.begin()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 10
	ball.rings = 6
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.7
		var r := k.rng.randf_range(3.5, 9.0)
		var at := Vector3(sin(a) * r, level + k.rng.randf_range(0.8, 2.2), cos(a) * r)
		wisps.append_from(ball, 0, Transform3D(Basis.IDENTITY, at).scaled_local(Vector3.ONE * 0.16))
		k.light(at, Color(0.5, 0.95, 0.75), 1.5, 7.0)
		k.puffs(at, Vector3(0.6, 0.3, 0.6), 0.25, 8, Color(0.65, 0.95, 0.85, 0.22), 0.7, 4.0)
	m.commit(wisps, PoiKit.plain(Color(0.7, 0.95, 0.85), 0.4, 0.0, Color(0.55, 0.95, 0.8), 3.5), "Wisps")
	# the strongbox in the chimney, which is what is actually here
	k.place(k.prop("chest"), Vector3(stack.x, level + 0.1, stack.y) + Vector3(grain.x, 0.0, grain.y) * 1.1, yaw)
	# and a burial lantern against the chimney, upright, out, and dry
	k.marker("the_chimney", Vector3(stack.x, level + 0.2, stack.y) - Vector3(grain.x, 0.0, grain.y) * 0.9)
	# the family's lanterns, never lit for them, on the bank
	for i in 3:
		var p := grain * (11.0 + float(i) * 1.6) + perp * k.rng.randf_range(-3.0, 3.0)
		k.place(k.prop("lantern_hanging"), k.on_ground(p.x, p.y, 0.1), k.rng.randf_range(0.0, TAU), 1.0, false)
	var reeds: Array = []
	for i in 70:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(11.0, 20.0)
		reeds.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("reeds"), reeds, false, false, false)
	var lilies: Array = []
	for i in 16:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(5.0, 13.0)
		lilies.append(PoiKit.transform_at(Vector3(sin(a) * r, level + 0.03, cos(a) * r), k.rng.randf_range(0.0, TAU), 1.0))
	k.scatter(k.flora("waterlily_pad"), lilies, false, false, false)


## Fern Gully: a ravine deep enough to hold mist at noon, crossed by the weavers' silk bridges.
static func _valley_gully(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var across := k.grain()
	var along := Vector2(-across.y, across.x)
	var g := k.on_ground(0.0, 0.0)
	# the walls of the ravine: two ranks of cliff slabs either side of the line
	for s in [-1.0, 1.0]:
		var slabs: Array = []
		for i in 9:
			var t := (float(i) - 4.0) * 4.2
			var p := along * t + across * float(s) * k.rng.randf_range(8.0, 10.0)
			slabs.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.5), PoiKit.yaw_of(-across * float(s)),
					k.rng.randf_range(1.5, 2.2), Vector3(k.rng.randf_range(-0.12, 0.04), 0.0, k.rng.randf_range(-0.08, 0.08))))
		k.scatter(k.rock("cliff_slab"), slabs, true, true)
	# the mist that does not lift
	for i in 3:
		var t := (float(i) - 1.0) * 9.0
		k.puffs(k.on_ground(along.x * t, along.y * t, 1.2), Vector3(7.0, 0.6, 3.0), 0.12, 26,
				Color(0.85, 0.88, 0.86, 0.2), 6.5, 9.0)
	# the silk bridges: pale strands across the ravine at two heights, and their anchors
	var silk := PoiKit.plain(Color(0.92, 0.94, 0.9), 0.35, 0.0, Color(0.8, 0.85, 0.82), 0.25)
	silk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silk.albedo_color = Color(0.92, 0.94, 0.9, 0.75)
	for i in 3:
		var t := (float(i) - 1.0) * 7.5
		var h := g.y + 5.0 + float(i % 2) * 2.4
		var strands := m.begin()
		for j in 4:
			var off := (float(j) - 1.5) * 0.28
			var a := along * t + across * -9.5 + along * off
			var b := along * t + across * 9.5 + along * off
			var from := Vector3(a.x, h, a.y)
			var to := Vector3(b.x, h - 0.4, b.y)
			var steps := 7
			for step in steps:
				var f0 := float(step) / float(steps)
				var f1 := float(step + 1) / float(steps)
				var p0 := from.lerp(to, f0)
				var p1 := from.lerp(to, f1)
				p0.y -= 1.9 * (1.0 - pow(2.0 * f0 - 1.0, 2.0))
				p1.y -= 1.9 * (1.0 - pow(2.0 * f1 - 1.0, 2.0))
				var seg := p1 - p0
				var pitch := atan2(seg.y, Vector2(seg.x, seg.z).length())
				m.rod(strands, Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(Vector2(seg.x, seg.z)))
						* Basis(Vector3.RIGHT, PI * 0.5 - pitch), (p0 + p1) * 0.5), 0.035, seg.length() * 1.05)
		m.commit(strands, silk, "Silk%d" % i, true)
	# what the woodfolk left: a lost hunting party's gear at the lip
	var lip := along * -12.0 + across * 7.0
	k.place(k.prop("sack"), k.on_ground(lip.x, lip.y), k.rng.randf_range(0.0, TAU))
	k.place(k.prop("spear"), k.on_ground(lip.x + 1.2, lip.y + 0.6), k.rng.randf_range(0.0, TAU), 1.0, false, Vector3(1.3, 0.0, 0.2))
	k.place(k.prop("shield"), k.on_ground(lip.x - 1.0, lip.y + 0.9), k.rng.randf_range(0.0, TAU), 1.0, false, Vector3(-0.4, 0.0, 0.2))
	k.place(k.prop("bedroll"), k.on_ground(lip.x + 0.2, lip.y - 1.8), k.rng.randf_range(0.0, TAU))
	# the gully's own growth: ferns everywhere, bracken, hanging moss off the slabs
	var ferns: Array = []
	for i in 150:
		var p := along * k.rng.randf_range(-19.0, 19.0) + across * k.rng.randf_range(-9.0, 9.0)
		ferns.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.7)))
	k.scatter(k.flora("fern"), ferns, false, false, false)
	var bracken: Array = []
	for i in 60:
		var p := along * k.rng.randf_range(-20.0, 20.0) + across * k.rng.randf_range(-11.0, 11.0)
		bracken.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.5)))
	k.scatter(k.flora("bracken"), bracken, false, false, false)
	var hanging := k.flora("hanging_moss")
	if hanging != "":
		var beards: Array = []
		for i in 18:
			var s := 1.0 if i % 2 == 0 else -1.0
			var p := along * k.rng.randf_range(-16.0, 16.0) + across * s * k.rng.randf_range(7.0, 9.0)
			beards.append(PoiKit.transform_at(k.on_ground(p.x, p.y, k.rng.randf_range(3.5, 6.5)), k.rng.randf_range(0.0, TAU),
					k.rng.randf_range(1.0, 1.6)))
		k.scatter(hanging, beards, false, false, false)
	var fungus := k.flora("bracket_fungus")
	if fungus != "":
		var brackets: Array = []
		for i in 14:
			var s := 1.0 if i % 2 == 0 else -1.0
			var p := along * k.rng.randf_range(-15.0, 15.0) + across * s * 8.2
			brackets.append(PoiKit.transform_at(k.on_ground(p.x, p.y, k.rng.randf_range(1.0, 4.0)),
					PoiKit.yaw_of(-across * s), k.rng.randf_range(1.0, 1.8)))
		k.scatter(fungus, brackets, false, false, false)
	# a giant oak leaning over the ravine, because the Briarwold is the Briarwold
	var tree_at := along * 14.0 + across * -8.5
	k.place(k.tree("giant_oak"), k.on_ground(tree_at.x, tree_at.y), k.rng.randf_range(0.0, TAU), 0.8, true,
			Vector3(0.0, 0.0, 0.12), true)


## How far above the water the Hushline Stair's landing stands where the land does not lift it clear.
const HUSH_LANDING_ABOVE_M := 1.6


## The Hushline Stair: Oroth steps going down into the mist where the colour goes out of
## things, with Wren Tallow's Hearthstone at the top step — the first name you are given.
##
## The built world flattened its pad at 0.2 m, with the Hush twenty metres deep on every side and
## the cliff a hundred metres off: the pad read as a raft awash, the stair went down into clear sea,
## and the ash-wights stood at the waterline. Where the ground is that low the stair's head stands
## on a shelf of its own, a rough stone mound out of the water with an Oroth landing laid on it
## HUSH_LANDING_ABOVE_M clear of the surface: the Hearthstone, the brazier, the piers and the wights
## (`the_landing`, a raised marker) are on it. The stair goes out from it away from the cliff, and
## where it goes under, the mist lies on the water and takes it. A pad the land already lifts clear
## of the water keeps its own ground. Built from the pad's def and the water, not the terrain, so a
## new build's pad is seated the same way.
static func _valley_hushline(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	# away from the cliff: out from under the Stair Head's camp, over the Hush
	var into := Vector2.ZERO
	var head_def := ContentDB.get_or_empty("core:poi/stair_head")
	if not head_def.is_empty():
		var from := WorldProbe.xz_of(head_def)
		var here := Vector2(k.origin.x, k.origin.z)
		if here.distance_to(from) > 1.0:
			into = (here - from).normalized()
	if into == Vector2.ZERO:
		var down := k.downhill()
		into = down if down != Vector2.ZERO else k.grain()
	var perp := Vector2(-into.y, into.x)
	var yaw := PoiKit.yaw_of(into)
	var basis := Basis(Vector3.UP, yaw)
	var g := k.on_ground(0.0, 0.0)
	# the water the pad stands in or beside: the pad itself reads dry, the sea round it does not
	var water := NAN
	if k.provider != null and k.water_direction(k.radius + 20.0) != Vector2.ZERO:
		water = k.provider.nearest_water_level(k.origin.x, k.origin.z) - k.origin.y
	var shelf := not is_nan(water) and g.y < water + HUSH_LANDING_ABOVE_M and g.y > water - 3.0
	var floor_y := water + HUSH_LANDING_ABOVE_M if shelf else g.y
	var stone := m.begin()
	# the stair: forty steps going down, wide, with a wall along each side. On a level pad that
	# ends at a drop it starts at the drop, not buried in the pad.
	var steps := 40
	var rise := -0.34
	var tread := 0.95
	var top := -into * 3.0
	if not shelf:
		var edge := _edge_along(k, into, g.y, k.radius + 12.0)
		if edge > 4.0:
			top = into * (edge - 1.0)
	var landing := top - into * 6.0
	if shelf:
		# the rock the landing is seated on, its rim under the water, and the landing on it: level
		# Oroth paving from the stair's head back twelve metres, its sides down into the water
		var rock := -into * 8.0
		var base := water - 3.0
		m.mound(Vector3(rock.x, base, rock.y), 16.0, floor_y - 0.3 - base, k.surface("stone", 0.8), "Shelf",
				true, 4.0, 8, 24, true, 0.14)
		var deep := floor_y - (water - 1.0)
		var slab := Transform3D(basis, Vector3(landing.x, floor_y - deep * 0.5, landing.y))
		m.block(stone, slab, Vector3(14.0, deep, 12.0))
		k.collider(Vector3(14.0, deep, 12.0), slab, "stone")
	m.steps(stone, top, into, floor_y, steps, rise, tread, 7.0, 1.1)
	for s in [-1.0, 1.0]:
		var a := top + perp * float(s) * 3.8
		var b := top + into * (tread * float(steps)) + perp * float(s) * 3.8
		var mid := (a + b) * 0.5
		var seg := b - a
		var xf := Transform3D(Basis(Vector3.UP, PoiKit.yaw_of(seg) + PI * 0.5),
				Vector3(mid.x, floor_y + rise * float(steps) * 0.5 + 0.7, mid.y))
		m.block(stone, xf, Vector3(seg.length(), 1.4, 0.6))
		k.collider(Vector3(seg.length(), 1.4, 0.6), xf, "stone")
	# the head of the stair: two Oroth piers marking where it begins
	for s in [-1.0, 1.0]:
		var p := top - into * 1.6 + perp * float(s) * 4.2
		var frame := Transform3D(Basis.IDENTITY, _on_landing(k, p, shelf, floor_y))
		m.drum(stone, frame, 0.85, 4.4, 0.25, NAN, true, 0.55)
	m.commit(stone, k.surface("oroth", 0.5), "Stair", true)
	# where the tutorial's wights wait, on the landing and never in the water
	k.marker("the_landing", _on_landing(k, landing, shelf, floor_y), false, shelf, 6.0)
	# the mist, which is what turns you back: lying on the water from where the stair goes under
	# to past its last step, so it goes down into grey and not into clear sea
	var under_from := 0.0
	if not is_nan(water):
		under_from = clampf((floor_y - water) / -rise, 0.0, float(steps)) * tread
	var t := under_from
	var i := 0
	while t <= tread * float(steps) + 8.0:
		var at := top + into * t
		var lie := floor_y + rise * clampf(t / tread, 0.0, float(steps))
		if not is_nan(water):
			lie = maxf(lie, water)
		# grey, not white: unshaded, a pale colour lit by the low sun read as a glare on the sea
		k.puffs(Vector3(at.x, lie + 0.6 + float(i % 3) * 0.3, at.y), Vector3(9.0, 0.8, 4.5), 0.06, 40,
				Color(0.56, 0.58, 0.62, 0.34), 10.0, 12.0)
		t += 6.0
		i += 1
	# Wren's Hearthstone at the top step, and the brazier she keeps
	var stone_at := top - into * 3.4 + perp * 2.2
	k.hearthstone(_on_landing(k, stone_at, shelf, floor_y), yaw + PI, d.poi_id, d.display_name)
	var brazier := top - into * 3.0 - perp * 2.4
	k.place(k.prop("brazier"), _on_landing(k, brazier, shelf, floor_y), 0.0)
	k.light(_on_landing(k, brazier, shelf, floor_y, 1.1), Color(1.0, 0.62, 0.3), 2.2, 10.0)
	var bench := top - into * 5.4
	k.place(k.prop("bench"), _on_landing(k, bench, shelf, floor_y), yaw)
	k.place(k.prop("crate"), _on_landing(k, bench + perp * 2.0, shelf, floor_y), yaw + 0.4)
	k.place(k.prop("signpost"), _on_landing(k, bench - perp * 3.0, shelf, floor_y), yaw + PI)
	# the grey grass gives out as the stair goes down: the last of it at the top, and on a landing
	# only on the landing
	var grass: Array = []
	for n in 40:
		var along := k.rng.randf_range(-12.0, 8.0)
		var across := k.rng.randf_range(-13.0, 13.0)
		var p := top + into * along + perp * across
		if shelf and (absf(along + 6.0) > 5.6 or absf(across) > 6.6):
			continue
		grass.append(PoiKit.transform_at(_on_landing(k, p, shelf, floor_y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(k.flora("grey_grass"), grass, false, false, false)
	for n in 2:
		var p := top - into * 8.0 + perp * (6.0 * (1.0 if n == 0 else -1.0))
		k.place(k.tree("dead_ash_tree"), _on_landing(k, p, shelf, floor_y), k.rng.randf_range(0.0, TAU), 0.9, true, Vector3.ZERO, true)


## How far along `dir` from the pad's middle the ground first falls a metre below `level`, or the
## water begins; 0 when neither happens within `reach`.
static func _edge_along(k: PoiKit, dir: Vector2, level: float, reach: float) -> float:
	var t := 1.0
	while t <= reach:
		var p := dir * t
		if k.is_water(p.x, p.y) or k.on_ground(p.x, p.y).y < level - 1.0:
			return t
		t += 1.0
	return 0.0


## A point on the Hushline's landing: the landing's own floor where it stands on its shelf, the
## ground where the land holds it.
static func _on_landing(k: PoiKit, p: Vector2, shelf: bool, floor_y: float, lift := 0.0) -> Vector3:
	return Vector3(p.x, floor_y + lift, p.y) if shelf else k.on_ground(p.x, p.y, lift)


# --- standing stones -----------------------------------------------------------------------------------------

## `worldgen/stones.py` already sets standing stones across the country by hand — a ring at the
## Moot, pairs flanking a road, singles on skylines — but the three POIs that *are* a setting of
## stones were not among them, because that pass works from places and roads rather than from
## the POI registry. So these three get their own setting, and what is particular about each.
static func standing_stones(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var b := d.brief
	var grain := k.grain()
	var stone := k.rock("standing_stone")
	var count := 3
	var radius := 4.6
	if PoiKit.brief_says(b, ["seven"]):
		count = 7
		radius = 7.4
	elif PoiKit.brief_says(b, ["stone circle"]):
		# a circle somebody stands in the middle of, and something charges across: wide enough
		# to fight in, and stones enough to break a charge on
		count = 9
		radius = 12.5
		# its keeper stands in the middle, where the question is asked
		k.marker("the_circle", k.on_ground(0.0, 0.0))
	elif PoiKit.brief_says(b, ["three"]):
		count = 3
	var shoreline := PoiKit.brief_says(b, ["shoreline", "sea's edge", "tide"])
	# the setting: a ring where there are many, a line along the old shore where there are three
	# on the sea's edge, and a leaning group where pieces of something fell
	var spots: Array = []
	if shoreline:
		var along := Vector2(-grain.y, grain.x)
		for i in count:
			spots.append(along * ((float(i) - float(count - 1) * 0.5) * 6.5))
	else:
		spots = k.ring(count, radius, Vector2.ZERO, 0.12)
	var leaning := PoiKit.brief_says(b, ["leaning"])
	for i in range(spots.size()):
		var p: Vector2 = spots[i]
		var yaw := PoiKit.yaw_of(-p) if not shoreline else PoiKit.yaw_of(grain)
		var tilt := Vector3.ZERO
		if leaning:
			tilt = Vector3(k.rng.randf_range(-0.22, 0.22), 0.0, k.rng.randf_range(0.1, 0.26) * (1.0 if i % 2 == 0 else -1.0))
		k.place(stone, k.on_ground(p.x, p.y), yaw + k.rng.randf_range(-0.2, 0.2),
				k.rng.randf_range(1.15, 1.55), true, tilt, true)
		# each stone's own packing stones at its foot, which is how a stone is actually set
		var packing: Array = []
		for j in 5:
			var q := p + Vector2(sin(TAU * float(j) / 5.0), cos(TAU * float(j) / 5.0)) * k.rng.randf_range(0.7, 1.1)
			packing.append(PoiKit.transform_at(k.on_ground(q.x, q.y, -0.08), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.2)))
		k.scatter(k.rock("boulder"), packing)
	# what is particular about each setting
	if PoiKit.brief_says(b, ["bronze", "toll's crown"]):
		# the bronze that landed with them: pieces of the Toll's crown in the grass
		var bronze := PoiKit.plain(PoiKit.BRONZE, 0.42, 0.75)
		for i in 3:
			var p := grain.rotated(float(i) * 2.1) * k.rng.randf_range(3.0, 8.0)
			var shard := m.begin()
			m.block(shard, Transform3D(Basis(Vector3.UP, k.rng.randf_range(0.0, TAU))
					* Basis(Vector3.BACK, k.rng.randf_range(-0.5, 0.5)), k.on_ground(p.x, p.y, 0.25)),
					Vector3(k.rng.randf_range(1.2, 2.2), 0.35, k.rng.randf_range(0.8, 1.4)))
			m.commit(shard, bronze, "Bronze%d" % i, true)
		k.place(k.prop("bell_small"), k.on_ground(grain.x * 2.2, grain.y * 2.2), k.rng.randf_range(0.0, TAU), 1.6, true,
				Vector3(0.0, 0.0, 1.1))
		# the sheep sleep against them because they are warm
		var grass: Array = []
		for i in 40:
			var p := k.jitter(10.0)
			grass.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.9, 1.4)))
		k.scatter(k.flora("grass_clump"), grass, false, false, false)
	elif PoiKit.brief_says(b, ["lichen"]):
		# seven stones for seven clans, each grown over with a different colour of lichen, and
		# the one whose lichen has gone
		var crust := k.flora("lichen_crust")
		for i in range(spots.size()):
			var p: Vector2 = spots[i]
			if i == spots.size() - 1:
				continue                     # the clan that died: its stone is bare
			var patches: Array = []
			for j in 7:
				var a := k.rng.randf_range(0.0, TAU)
				var q := p + Vector2(sin(a), cos(a)) * k.rng.randf_range(0.3, 0.6)
				patches.append(PoiKit.transform_at(k.on_ground(q.x, q.y, k.rng.randf_range(0.4, 3.2)),
						PoiKit.yaw_of(q - p), k.rng.randf_range(0.8, 1.5)))
			var mm := k.scatter(crust, patches, false, false, false)
			if mm != null:
				# a different colour on every stone, which is the whole point of the seven
				var tints := [Color(0.85, 0.9, 0.6), Color(0.95, 0.8, 0.45), Color(0.7, 0.85, 0.8),
						Color(0.6, 0.7, 0.45), Color(0.9, 0.85, 0.75), Color(0.75, 0.6, 0.5)]
				var tinted := PoiKit.plain(tints[i % tints.size()], 0.9)
				tinted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				var src := PoiKit.mesh(crust)
				if src != null and src.get_surface_count() > 0 and src.surface_get_material(0) is StandardMaterial3D:
					tinted.albedo_texture = (src.surface_get_material(0) as StandardMaterial3D).albedo_texture
				mm.material_override = tinted
		var heather: Array = []
		for i in 40:
			var p := k.jitter(14.0)
			heather.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
		k.scatter(k.flora("heather"), heather, false, false, false)
	elif shoreline:
		# a shoreline that no longer exists: the old strand of shingle in a line at their feet
		var shingle: Array = []
		var along := Vector2(-grain.y, grain.x)
		for i in 60:
			var p := along * k.rng.randf_range(-16.0, 16.0) + grain * k.rng.randf_range(-2.5, 2.5)
			shingle.append(PoiKit.transform_at(k.on_ground(p.x, p.y, -0.05), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.2, 0.5)))
		k.scatter(k.rock("scree"), shingle)
		var reeds: Array = []
		for i in 30:
			var p := along * k.rng.randf_range(-18.0, 18.0) + grain * k.rng.randf_range(3.0, 12.0)
			reeds.append(PoiKit.transform_at(k.on_ground(p.x, p.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
		k.scatter(k.flora("reeds"), reeds, false, false, false)
		k.place(k.prop("rowboat"), k.on_ground(along.x * 9.0 + grain.x * 5.0, along.y * 9.0 + grain.y * 5.0),
				PoiKit.yaw_of(along) + 0.4, 1.0, true, Vector3(0.0, 0.0, 0.25))
		# "none; crabs": nothing to fight, and the crabs on the old strand, going about sideways
		# among the shingle at the stones' feet
		if not k.far:
			var crabs := Livestock.paths_of("crab", "sedgemire")
			if not crabs.is_empty():
				var shore := Livestock.new()
				shore.name = "Crabs"
				shore.seed_with(absi(("crabs:" + d.poi_id).hash()))
				for i in 3:
					var at := along * (float(i) - 1.0) * 8.0 + grain * k.rng.randf_range(-1.0, 1.0)
					shore.keep("crab", crabs, k.on_ground(at.x, at.y), 3.2, 3 + k.rng.randi_range(0, 2))
				d.add_child(shore)


# --- the strange -----------------------------------------------------------------------------------------------

## Two POIs whose kind is only "strange", so each is built from its own sentence: a line of
## twelve buoys whose bells ring in any wind, and one red poppy in a square kilometre of grey.
static func strange(d: PoiDressing) -> void:
	if PoiKit.brief_says(d.brief, ["buoy", "bells ring"]):
		_strange_bell_buoys(d)
	elif PoiKit.brief_says(d.brief, ["poppy"]):
		_strange_one_poppy(d)
	else:
		Log.warn("PoiDressing", "%s: nothing in its feature text to build: '%s'" % [d.poi_id, d.brief])


## The poppy itself, from shapes rather than a leaf card: a stem to the knee, four petals a hand
## across tilted to the sky, a black heart. The red holds a little light of its own so that in a
## grey dusk it is still the one colour on the heath. A silhouette piece, so it is there from far.
static func _poppy_flower(d: PoiDressing, at: Vector3) -> MeshInstance3D:
	var m := d.masonry
	var k := d.kit
	var st := m.begin()
	var head := at + Vector3(0.0, 0.86, 0.0)
	var petal := SphereMesh.new()
	petal.radius = 1.0
	petal.height = 2.0
	petal.radial_segments = 10
	petal.rings = 5
	var turn := k.rng.randf_range(0.0, TAU)
	for i in 4:
		var a := turn + TAU * float(i) / 4.0
		var out := Vector3(sin(a), 0.0, cos(a))
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.45)
		st.append_from(petal, 0, Transform3D(basis, head + out * 0.15 + Vector3(0.0, 0.06, 0.0))
				.scaled_local(Vector3(0.17, 0.03, 0.2)))
	var red := PoiKit.plain(Color(0.85, 0.07, 0.05), 0.5, 0.0, Color(0.75, 0.05, 0.03), 0.9)
	var bloom := m.commit(st, red, "Bloom", true)
	var dark := m.begin()
	dark.append_from(petal, 0, Transform3D(Basis.IDENTITY, head + Vector3(0.0, 0.08, 0.0)).scaled_local(Vector3.ONE * 0.06))
	m.rod(dark, Transform3D(Basis.from_euler(Vector3(0.08, 0.0, 0.05)), at + Vector3(0.0, 0.43, 0.0)), 0.014, 0.86)
	var stem := m.commit(dark, PoiKit.plain(Color(0.12, 0.14, 0.1), 0.8), "Stem", true)
	# one thing, so that picking it takes all of it
	if bloom != null and stem != null:
		stem.reparent(bloom)
	return bloom


## The Bell Buoys: twelve buoys in a line on the water, each a float with a post and a bell in
## a cage on top, each tuned to a note of the Toll.
static func _strange_bell_buoys(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var g := k.on_ground(0.0, 0.0)
	var wl := k.water_y(0.0, 0.0)
	var level := (wl if not is_nan(wl) else g.y) - g.y
	var along := k.grain()
	var timber := m.begin()
	var bells: Array = []
	var floats: Array = []
	for i in 12:
		var t := (float(i) - 5.5) * 7.0
		var p := along * t + Vector2(-along.y, along.x) * k.rng.randf_range(-1.6, 1.6)
		var lean := Vector3(k.rng.randf_range(-0.08, 0.08), 0.0, k.rng.randf_range(-0.08, 0.08))
		var basis := Basis.from_euler(lean)
		var foot := Vector3(p.x, level - 0.3, p.y)
		# the float: a barrel on its side lashed under the post
		floats.append(Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PoiKit.yaw_of(along)),
				foot + Vector3(0.0, 0.35, 0.0)))
		# the post, out of the water
		var h := 2.6 - float(i % 3) * 0.25
		m.block(timber, Transform3D(basis, foot + basis * Vector3(0.0, h * 0.5 + 0.4, 0.0)), Vector3(0.18, h, 0.18))
		# the cage: four uprights and a cap over the bell
		var head := foot + basis * Vector3(0.0, h + 0.4, 0.0)
		for j in 4:
			var a := TAU * float(j) / 4.0 + PI * 0.25
			m.block(timber, Transform3D(basis * Basis(Vector3.UP, a), head + basis * (Vector3(sin(a), 0.0, cos(a)) * 0.34)),
					Vector3(0.07, 1.0, 0.07))
		m.block(timber, Transform3D(basis, head + basis * Vector3(0.0, 0.54, 0.0)), Vector3(0.9, 0.09, 0.9))
		# each bell a little different, because each is a different note
		bells.append(Transform3D(basis.scaled(Vector3.ONE * (1.5 - float(i) * 0.055)),
				head + basis * Vector3(0.0, 0.42 - PoiKit.height_of(k.prop("bell_small", 0)) * (1.5 - float(i) * 0.055), 0.0)))
	m.commit(timber, k.surface("timber", 0.9), "Buoys", true)
	k.scatter(k.prop("barrel"), floats, false, true)
	k.scatter(k.prop("bell_small"), bells, false, true)
	# the boat you row out in, and the lilies the shallows keep
	var boat := along * -46.0
	k.place(k.prop("rowboat"), Vector3(boat.x, level - 0.1, boat.y), PoiKit.yaw_of(along) + 0.3, 1.0, true, Vector3.ZERO, true)
	var lilies: Array = []
	for i in 18:
		var p := along * k.rng.randf_range(-44.0, 44.0) + Vector2(-along.y, along.x) * k.rng.randf_range(-14.0, 14.0)
		lilies.append(PoiKit.transform_at(Vector3(p.x, level + 0.03, p.y), k.rng.randf_range(0.0, TAU), 1.0))
	k.scatter(k.flora("waterlily_pad"), lilies, false, false, false)


## The One Poppy: one red poppy in a square kilometre of grey grass, and nothing else — except
## that somebody has put a ring of stones round it and a cup of water beside it.
##
## Honest to the fiction, the first dressing photographed from thirty metres as a speck and some
## pebbles: nothing in it told the eye there was anything there to walk to. What does now is what
## people who come out to it would leave. The grey grass is worn off inside the ring and down a
## path from the way they come, so the grass stops round it; the ring is stones you would carry,
## not pebbles; and every pilgrim who waters it leaves a stone on a cairn by the path, with a
## peeled white stake in it that stands up out of a flat heath the way nothing else on it does. The
## poppy is a flower, built big enough to see and no bigger than a big poppy: a stem above the knee
## and a bloom two hands across, holding a little light of its own, and the only colour here.
## (A trodden path laid as thin boards read from thirty metres as a white rail across the heath;
## where the grass stops is the path.)
##
## It is also the sentence's deed: touching it puts the choice (water it, the Hearth; pick it, the
## Hollow), and a poppy picked is not there the next time the heath is built.
static func _strange_one_poppy(d: PoiDressing) -> void:
	var k := d.kit
	var m := d.masonry
	var grain := k.grain()
	var picked := GameState.has_flag("poppy_picked")
	# the ring of stones somebody set round it: stones you would carry, set touching
	var ring: Array = []
	for p in k.ring(13, 2.9, Vector2.ZERO, 0.04):
		var pp: Vector2 = p
		ring.append(PoiKit.transform_at(k.on_ground(pp.x, pp.y, -0.04), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.28, 0.4)))
	k.scatter(k.rock("boulder"), ring, true)
	# the cairn by the path, a stone for every watering, and the peeled stake in it
	var cairn := grain * 4.4 + Vector2(-grain.y, grain.x) * 1.6
	var stones: Array = []
	for i in 46:
		var u := k.rng.randf()
		var r := 0.95 * sqrt(u)
		var a := k.rng.randf_range(0.0, TAU)
		var h := 1.0 * maxf(1.0 - r / 0.95, 0.0) * k.rng.randf_range(0.8, 1.0)
		stones.append(PoiKit.transform_at(k.on_ground(cairn.x + sin(a) * r, cairn.y + cos(a) * r, h),
				k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.12, 0.2),
				Vector3(k.rng.randf_range(-0.4, 0.4), 0.0, k.rng.randf_range(-0.4, 0.4))))
	k.scatter(k.rock("boulder", 1), stones, false, true)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.85
	cyl.height = 0.9
	k.collider_shape(cyl, Transform3D(Basis.IDENTITY, k.on_ground(cairn.x, cairn.y, 0.45)), "stone")
	var stake := m.begin()
	m.rod(stake, Transform3D(Basis.from_euler(Vector3(0.06, 0.0, -0.04)), k.on_ground(cairn.x, cairn.y, 1.3)), 0.05, 2.6)
	m.commit(stake, PoiKit.plain(Color(0.86, 0.83, 0.76), 0.9), "Stake", true)
	# the cup of water, which is the Hearth deed: somebody comes out here and waters it
	k.place(k.prop("mug"), k.on_ground(grain.x * 2.2, grain.y * 2.2), k.rng.randf_range(0.0, TAU), 1.0, false)
	k.place(k.prop("jug"), k.on_ground(grain.x * 2.8 + grain.y * 0.4, grain.y * 2.8 - grain.x * 0.4), k.rng.randf_range(0.0, TAU), 1.0, false)
	# the one thing, unless somebody has picked it
	if not picked:
		var touch := k.touchable("the_poppy", k.on_ground(0.0, 0.0), "Kneel by the poppy",
				"core:dialogue/the_one_poppy", "poppy_picked", false)
		var flower := _poppy_flower(d, k.on_ground(0.0, 0.0))
		if touch != null and flower != null:
			flower.reparent(touch)
		var poppy := k.flora("red_poppy_single")
		if poppy == "":
			poppy = k.flora("poppy")
		var leaves := k.place(poppy, k.on_ground(0.25, -0.15), k.rng.randf_range(0.0, TAU), 1.6, false, Vector3.ZERO, true)
		if touch != null and leaves != null:
			leaves.reparent(touch)
	# and a square kilometre of grey grass, kept off the trodden ground, so the red is the only colour
	var grass: Array = []
	for i in 220:
		var a := k.rng.randf_range(0.0, TAU)
		var r := 3.4 + 22.6 * sqrt(k.rng.randf())
		var at := Vector2(sin(a) * r, cos(a) * r)
		# not on the path
		if at.dot(grain) > 3.0 and absf(at.dot(Vector2(-grain.y, grain.x))) < 1.3:
			continue
		grass.append(PoiKit.transform_at(k.on_ground(at.x, at.y), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.8, 1.3)))
	k.scatter(k.flora("grey_grass"), grass, false, false, false)
	var stumps: Array = []
	for i in 6:
		var a := k.rng.randf_range(0.0, TAU)
		var r := k.rng.randf_range(12.0, 24.0)
		stumps.append(PoiKit.transform_at(k.on_ground(sin(a) * r, cos(a) * r), k.rng.randf_range(0.0, TAU), k.rng.randf_range(0.7, 1.1)))
	k.scatter(k.tree("char_stump"), stumps, true, true)
