class_name SiteDress
extends RefCounted
## Everything in a site's rock that makes it a place: what lights each room (torches, braziers, a
## camp's fire, glow fungus, the lava's own light, daylight down a shaft), what was left in it by
## whoever used it (a camp, stores, tombs, a mine's timbering and carts), its set-pieces dressed (the
## lake's water, the rift's bridge and what catches a fall, the forge, the ossuary's bones), its ways
## (the way out, the loose stones before the secret room, the bar across the shortcut), what can be
## looted, and who is here. Each room's things are chosen from the kind (SiteKinds) and the room's
## role, set at the plan's clear floor, never on a doorway or the lanes between them, and the whole
## is built a step at a time (SiteInterior.step).
##
## Things are the forge's props (PoiKit.prop, in the region's own look) wherever one exists; what no
## prop is (a torch's bracket, bones, fungus, a bridge's planks) is laid as masonry batches, one draw
## call per material per room.

var site: SiteInterior
var plan: SitePlan
var kit: PoiKit
var m: PoiMasonry
var root: Node3D
var lights_node: Node3D
## Faces a foe may walk that are not the rock's (a bridge's deck), for the navigation mesh.
var walk_faces: Array[PackedVector3Array] = []
var lights: Array[Light3D] = []
var waters: Array[ShaderMaterial] = []
var spawner: EnemySpawner = null
var _mats: Dictionary = {}
var _water_set := false
var _catches: Array = []


func _init(interior: SiteInterior, p: SitePlan) -> void:
	site = interior
	plan = p
	root = Node3D.new()
	root.name = "Dressing"
	interior.add_child(root)
	lights_node = Node3D.new()
	lights_node.name = "Lights"
	interior.add_child(lights_node)
	kit = PoiKit.new(root, Vector3.ZERO, 40.0, p.region, false, p.id)
	kit.provider = null
	kit.roads = []
	kit.rng.seed = p.site_seed * 7 + 3
	m = PoiMasonry.new(kit)


func step() -> void:
	await site.step()


func build() -> void:
	await _way_out()
	for r in plan.rooms:
		await _room(r)
	for l in plan.links:
		await _link(l)
	await _containers()
	await _features()
	_light_budget()
	await step()


## Compatibility draws at most `max_lights_per_object` (12) lights on one mesh and drops the rest
## without a word, and which it drops is not the farthest: a chunk of rock reached by the fills of
## four rooms went black by a lit lamp. So no chunk is reached by more than LIGHTS_PER_CHUNK: the
## widest-reaching of the lights on a chunk over it is drawn in, a fifth at a time, and one already
## small is put out.
const LIGHTS_PER_CHUNK := 11


func _light_budget() -> void:
	var boxes: Array[AABB] = []
	for ch in site.chunks:
		var vs: PackedVector3Array = ch["verts"]
		if vs.is_empty():
			continue
		var box := AABB(vs[0], Vector3.ZERO)
		for v in vs:
			box = box.expand(v)
		boxes.append(box)
	for guard in 400:
		var over := -1
		var on: Array = []
		for bi in boxes.size():
			var here: Array = []
			for l in lights:
				var o := l as OmniLight3D
				if o != null and o.visible and boxes[bi].grow(o.omni_range).has_point(o.position):
					here.append(o)
			if here.size() > LIGHTS_PER_CHUNK:
				over = bi
				on = here
				break
		if over < 0:
			for l in lights:
				l.set_meta("budget_on", l.visible)
			return
		on.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.omni_range > b.omni_range)
		var widest: OmniLight3D = on[0]
		if widest.omni_range > 6.0:
			widest.omni_range *= 0.8
		else:
			widest.visible = false


# --- materials ------------------------------------------------------------------------------------

func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var made: Material
	match key:
		"stone":
			made = kit.surface("stone", 0.7)
		"timber":
			made = kit.surface("timber", 0.7)
		"planks":
			made = kit.surface("planks", 0.7)
		"bone":
			made = PoiKit.plain(Color(0.78, 0.74, 0.62), 0.85)
		"flame":
			made = PoiKit.plain(Color(1.0, 0.6, 0.2), 0.5, 0.0, Color(1.0, 0.55, 0.18), 3.0)
		"iron":
			made = PoiKit.plain(Color(0.16, 0.15, 0.14), 0.55, 0.7)
		"rope":
			made = PoiKit.plain(Color(0.45, 0.37, 0.25), 0.95)
		"fungus":
			var c := Color(str(plan.spec.get("fungus_colour", "#6fe0c8")))
			made = PoiKit.plain(c.darkened(0.3), 0.6, 0.0, c, 2.2)
		"fungus_stalk":
			made = PoiKit.plain(Color(0.62, 0.6, 0.52), 0.8)
		"lava":
			made = PoiKit.plain(Color(0.9, 0.3, 0.05), 0.4, 0.0, Color(1.0, 0.36, 0.06), 4.5)
		"ember":
			made = PoiKit.plain(Color(0.3, 0.08, 0.02), 0.6, 0.0, Color(1.0, 0.32, 0.06), 1.3)
		"obsidian":
			made = PoiKit.plain(Color(0.05, 0.045, 0.06), 0.08, 0.3)
		"ore":
			made = PoiKit.plain(Color(0.55, 0.5, 0.35), 0.3, 0.6, Color(0.9, 0.75, 0.35), 0.6)
		"day_glow":
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.98, 0.92, 1.0))
			g.set_color(1, Color(0.85, 0.9, 1.0, 0.0))
			g.add_point(0.45, Color(0.95, 0.95, 0.95, 0.7))
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill = GradientTexture2D.FILL_RADIAL
			gt.fill_from = Vector2(0.5, 0.5)
			gt.fill_to = Vector2(0.5, 0.0)
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.albedo_texture = gt
			gm.albedo_color = Color(1.4, 1.4, 1.35)
			made = gm
		"daylight":
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.albedo_color = Color(0.92, 0.95, 1.0)
			made = sm
		"rock":
			made = site._material()
		_:
			made = PoiKit.plain(Color(0.5, 0.5, 0.5))
	_mats[key] = made
	return made


func _lamp(at: Vector3, colour: Color, energy: float, reach: float, flicker_by := 0.0, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	l.light_specular = 0.25
	l.set_meta("flicker", flicker_by)
	l.set_meta("base_energy", energy)
	lights_node.add_child(l)
	lights.append(l)
	return l


func _place(kind: String, at: Vector3, yaw: float, scale := 1.0, collide := true) -> Node3D:
	var path := kit.prop(kind)
	if path == "":
		return null
	return kit.place(path, at, yaw, scale, collide)


func _face(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


# --- the way out ----------------------------------------------------------------------------------

func _way_out() -> void:
	var door := Door.new()
	door.name = "WayOut"
	door.is_exit = true
	door.display_name = "the way out"
	door.position = plan.exit_at
	door.rotation.y = plan.exit_yaw
	site.add_child(door)
	var back := Vector3(sin(plan.exit_yaw), 0.0, cos(plan.exit_yaw))   # into the room
	var yaw := plan.exit_yaw
	var basis := Basis(Vector3.UP, yaw)
	if plan._built():
		# a doorway of dressed stone, the door itself shut in it (you go out through it)
		var st := m.begin()
		var at := plan.exit_at - back * 0.2
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(basis, at + basis * Vector3(float(s) * 0.95, 1.3, 0.0)), Vector3(0.45, 2.6, 0.6))
		m.block(st, Transform3D(basis, at + basis * Vector3(0.0, 2.75, 0.0)), Vector3(2.4, 0.45, 0.65))
		m.commit(st, mat("stone"), "ExitFrame")
		var leaf := m.begin()
		for i in 5:
			m.block(leaf, Transform3D(basis, at - back * 0.05 + basis * Vector3(-0.58 + float(i) * 0.29, 1.25, 0.0)), Vector3(0.27, 2.5, 0.08))
		m.block(leaf, Transform3D(basis, at - back * 0.02 + basis * Vector3(0.0, 0.7, 0.0)), Vector3(1.4, 0.12, 0.1))
		m.block(leaf, Transform3D(basis, at - back * 0.02 + basis * Vector3(0.0, 1.9, 0.0)), Vector3(1.4, 0.12, 0.1))
		m.commit(leaf, mat("planks"), "ExitDoor")
		_lamp(at + back * 1.5 + Vector3.UP * 2.3, Color(1.0, 0.7, 0.42), 1.6, 8.0, 0.2)
	else:
		# the day at the top of the throat: a soft glow where the tunnel ends (faded at its edges, so
		# it is light coming round a bend and not a pane), and its light down the throat
		var glow := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(4.2, 4.2)
		glow.mesh = q
		glow.material_override = mat("day_glow")
		glow.position = plan.exit_glow
		glow.rotation.y = yaw
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.name = "Daylight"
		root.add_child(glow)
		_lamp(plan.exit_glow + back * 2.5, Color(0.86, 0.9, 0.98), 2.2, 9.0)
		# and the day's light where the throat opens into the room
		_lamp(plan.exit_at + back * 1.5 + Vector3.UP * 2.2, Color(0.8, 0.84, 0.92), 2.2, 11.0)
		# the day falling in down the throat and across the first room's floor, fading as it goes:
		# the first view in is the day behind you and the place's own light ahead
		var spill := SpotLight3D.new()
		spill.name = "DaySpill"
		spill.position = plan.exit_glow + back * 0.8 + Vector3.DOWN * 0.3
		var toward: Vector3 = (plan.rooms[0]["centre"] as Vector3) + back * 2.0
		spill.look_at_from_position(spill.position, toward, Vector3.UP)
		spill.light_color = Color(0.86, 0.9, 1.0)
		spill.light_energy = 3.2
		spill.spot_range = 20.0
		spill.spot_angle = 38.0
		spill.spot_attenuation = 1.1
		spill.spot_angle_attenuation = 0.9
		spill.light_specular = 0.2
		spill.set_meta("flicker", 0.0)
		spill.set_meta("base_energy", 3.2)
		lights_node.add_child(spill)
		lights.append(spill)
	await step()


# --- rooms ----------------------------------------------------------------------------------------

func _room(r: Dictionary) -> void:
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	var reach := Vector2(half.x, half.z).length()
	# a cold, weak fill so the room's shape reads beyond its lamps
	var tint := Color(0.6, 0.66, 0.8).lerp(Color(str(plan.spec.get("light_colour", "#ffb066"))), 0.3)
	if plan.spec.has("fill_colour"):
		# a kind lit by one hot colour (the lava tube) keeps its shadows cool, so the heat reads as heat
		tint = Color(str(plan.spec["fill_colour"]))
	var fill := _lamp(c + Vector3.UP * half.y * 0.7, tint, 1.0 + reach / 14.0, reach * 1.3)
	fill.light_specular = 0.0
	var ls: Array = plan.spec.get("lights", ["torch"])
	var role := str(r["role"])
	match role:
		"boss":
			await _ring_of(r, "brazier" if not ls.has("lava") else "lava_vent", 4)
		"camp":
			await _campfire(r)
			await _torches(r, 1)
		"secret":
			await _light_kind(r, "candles" if plan._built() else "fungus")
		"entrance":
			await _light_kind(r, str(ls[mini(1, ls.size() - 1)]))
		"passage":
			await _light_kind(r, str(ls[0]), 1)
		_:
			await _light_kind(r, str(ls[0]))
			if reach > 10.0 and ls.size() > 1:
				await _light_kind(r, str(ls[1]), 1)
	await _set_piece_dress(r)
	await _props(r)


func _light_kind(r: Dictionary, what: String, count := 2) -> void:
	match what:
		"torch":
			await _torches(r, count)
		"brazier":
			await _ring_of(r, "brazier", count)
		"lantern":
			await _lanterns(r, count)
		"candles":
			await _candles(r)
		"campfire":
			await _campfire(r)
		"fungus":
			await _fungus(r, 3 + count * 2)
		"lava", "ember":
			await _embers(r, 2 + count)
		"daylight":
			if not _has_zone(r, "shaft"):
				await _fungus(r, 3)
		_:
			await _torches(r, count)


func _has_zone(r: Dictionary, kind: String) -> bool:
	for z in r["zones"]:
		if z["kind"] == kind:
			return true
	return false


## Torches in iron brackets on the wall, flames and all, at the room's wall spots.
func _torches(r: Dictionary, count: int) -> void:
	var c: Vector3 = r["centre"]
	var iron := m.begin()
	var flame := m.begin()
	for i in count:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		# carry the torch to the wall itself: along from the middle until the rock
		var out := Vector3(at.x - c.x, 0.0, at.z - c.z).normalized()
		var wall := _wall_toward(at + Vector3.UP * 1.9, out)
		var p := wall - out * 0.28
		var basis := Basis(Vector3.UP, atan2(out.x, out.z))
		m.block(iron, Transform3D(basis, p + out * 0.14), Vector3(0.06, 0.06, 0.3))
		m.rod(iron, Transform3D(Basis(Vector3.RIGHT, -0.35), p + Vector3.UP * 0.05), 0.035, 0.5)
		m.ellipsoid(flame, p + Vector3.UP * 0.38, Vector3(0.09, 0.2, 0.09))
		_lamp(p + Vector3.UP * 0.45 - out * 0.25, Color(str(plan.spec.get("light_colour", "#ffb066"))), 2.4, 10.0, 0.35, i == 0 and r["role"] != "passage")
	await step()
	m.commit(iron, mat("iron"), "Brackets_%s" % r["id"])
	m.commit(flame, mat("flame"), "Flames_%s" % r["id"])


## Where the rock is along `dir` from `from` (the collision the shell just stood up), or a way
## short of the room's edge if nothing is found.
func _wall_toward(from: Vector3, dir: Vector3) -> Vector3:
	var hit := _ray(from, from + dir * 14.0)
	if hit != Vector3.INF:
		return hit
	return from + dir * 1.0


func _ray(a: Vector3, b: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for ch in site.chunks:
		var key: Vector2i = ch["key"]
		var lo := minf(a.x, b.x)
		var hi := maxf(a.x, b.x)
		if hi < key.x * SiteField.CHUNK_M - 1.0 or lo > (key.x + 1) * SiteField.CHUNK_M + 1.0:
			continue
		var lz := minf(a.z, b.z)
		var hz := maxf(a.z, b.z)
		if hz < key.y * SiteField.CHUNK_M - 1.0 or lz > (key.y + 1) * SiteField.CHUNK_M + 1.0:
			continue
		var tm: TriangleMesh = ch.get("tm", null)
		if tm == null:
			tm = TriangleMesh.new()
			tm.create_from_faces(ch["faces"])
			ch["tm"] = tm
		var hit := tm.intersect_segment(a, b)
		if hit.is_empty():
			continue
		var p: Vector3 = hit["position"]
		var d := p.distance_squared_to(a)
		if d < best_d:
			best_d = d
			best = p
	return best


## The floor under a point (the rock's, or a deck's), for things set down on it.
func floor_under(at: Vector3) -> Vector3:
	var hit := _ray(at + Vector3.UP * 1.0, at + Vector3.DOWN * 4.0)
	return hit if hit != Vector3.INF else at


func _ring_of(r: Dictionary, what: String, count: int) -> void:
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	var small := minf(half.x, half.z)
	var embers := m.begin()
	for i in count:
		var a := float(i) / float(count) * TAU + float(r["yaw"])
		var at := c + Vector3(sin(a), 0.0, cos(a)) * small * 0.72
		if count <= 2:
			var s := plan.take_spot(r, false)
			if s == Vector3.INF:
				continue
			at = s
		at = floor_under(at)
		if what == "lava_vent":
			# a vent: a star of cracks with the heat standing over it
			for k in 5:
				var h := a + TAU * float(k) / 5.0 + kit.rng.randf_range(-0.3, 0.3)
				var run := kit.rng.randf_range(0.6, 1.3)
				var dir := Vector3(sin(h), 0.0, cos(h))
				m.block(embers, Transform3D(Basis(Vector3.UP, h), at + dir * run * 0.5 + Vector3.UP * 0.005), Vector3(0.08, 0.02, run))
			_lamp(at + Vector3.UP * 1.0, Color(1.0, 0.45, 0.16), 3.4, 12.0, 0.2, i == 0)
		else:
			_place("brazier", at, a, 1.0)
			m.ellipsoid(embers, at + Vector3.UP * 0.95, Vector3(0.28, 0.12, 0.28))
			_lamp(at + Vector3.UP * 1.5, Color(1.0, 0.62, 0.3), 3.0, 13.0, 0.3, i == 0)
		await step()
	m.commit(embers, mat("ember"), "Embers_%s" % r["id"])


func _lanterns(r: Dictionary, count: int) -> void:
	for i in count:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		_place("lantern_standing", floor_under(at), randf_yaw(), 1.0)
		_lamp(at + Vector3.UP * 1.3, Color(1.0, 0.78, 0.48), 1.8, 9.0, 0.15)
		await step()


func randf_yaw() -> float:
	return kit.rng.randf() * TAU


func _candles(r: Dictionary) -> void:
	var at := plan.take_spot(r, true)
	if at == Vector3.INF:
		return
	for i in 5:
		var p := at + Vector3(kit.rng.randf_range(-0.5, 0.5), 0.0, kit.rng.randf_range(-0.5, 0.5))
		_place("candle_stub" if i % 2 == 0 else "candle", floor_under(p), randf_yaw(), 1.0, false)
	_lamp(at + Vector3.UP * 0.6, Color(1.0, 0.72, 0.4), 1.4, 7.0, 0.3)
	await step()


func _campfire(r: Dictionary) -> void:
	var at := plan.take_spot(r, false, r["centre"])
	if at == Vector3.INF:
		return
	at = floor_under(at)
	_place("campfire", at, randf_yaw(), 1.0, false)
	_lamp(at + Vector3.UP * 0.9, Color(1.0, 0.58, 0.26), 3.6, 14.0, 0.4, true)
	kit.puffs(at + Vector3.UP * 1.0, Vector3(0.3, 0.2, 0.3), 2.5, 10, Color(0.3, 0.28, 0.26, 0.35), 1.2, 5.0)
	r["fire"] = at
	await step()


## Glowing fungus in clumps by the walls: caps on stalks, each clump one small cold light's worth of
## glow (only the first few are real lights; the rest are the glow alone).
func _fungus(r: Dictionary, clumps: int) -> void:
	var caps := m.begin()
	var stalks := m.begin()
	var lit := 0
	for i in clumps:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		at = floor_under(at)
		for k in kit.rng.randi_range(4, 9):
			var p := at + Vector3(kit.rng.randf_range(-0.6, 0.6), 0.0, kit.rng.randf_range(-0.6, 0.6))
			var h := kit.rng.randf_range(0.08, 0.45)
			m.rod(stalks, Transform3D(Basis.IDENTITY, p + Vector3.UP * h * 0.5), 0.025, h)
			var cr := kit.rng.randf_range(0.06, 0.16)
			m.ellipsoid(caps, p + Vector3.UP * h, Vector3(cr, cr * 0.45, cr))
		if lit < 2:
			_lamp(at + Vector3.UP * 0.5, Color(str(plan.spec.get("fungus_colour", "#6fe0c8"))), 0.9, 6.5, 0.0)
			lit += 1
	await step()
	m.commit(caps, mat("fungus"), "Fungus_%s" % r["id"])
	m.commit(stalks, mat("fungus_stalk"), "FungusStalks_%s" % r["id"])


## Cracks in the floor with the heat showing through (the lava tube's own light).
func _embers(r: Dictionary, count: int) -> void:
	var st := m.begin()
	for i in count:
		var at := plan.take_spot(r, false)
		if at == Vector3.INF:
			break
		at = floor_under(at)
		var yaw := randf_yaw()
		# a jagged crack of a few short runs, each turned a little off the last
		var p := at
		var heading := yaw
		for k in kit.rng.randi_range(4, 6):
			var run := kit.rng.randf_range(0.25, 0.5)
			heading += kit.rng.randf_range(-0.7, 0.7)
			var dir := Vector3(sin(heading), 0.0, cos(heading))
			m.block(st, Transform3D(Basis(Vector3.UP, heading), p + dir * run * 0.5 + Vector3.UP * 0.005), Vector3(0.05, 0.02, run))
			p += dir * run
		if i < 2:
			_lamp(at + Vector3.UP * 0.7, Color(1.0, 0.42, 0.14), 2.2, 10.0, 0.15)
	await step()
	m.commit(st, mat("ember"), "Cracks_%s" % r["id"])


# --- set-pieces -------------------------------------------------------------------------------------

func _set_piece_dress(r: Dictionary) -> void:
	for z in r["zones"]:
		match str(z["kind"]):
			"lake":
				await _lake(r, z)
			"shaft":
				await _shaft(r, z)
			"rubble":
				await _rubble(z)
			"chasm":
				await _chasm(r, z)
			"niche":
				await _bones(z["at"], 0.35, 3, z.get("facing", Vector3.FORWARD))
			"pillar":
				if plan._built():
					var st := m.begin()
					var at: Vector3 = z["at"]
					m.block(st, Transform3D(Basis(Vector3.UP, 0.4), at + Vector3.UP * 0.25), Vector3(2.4, 0.5, 2.4))
					m.commit(st, mat("stone"), "Plinth")
			"ledge":
				await _ledge(r, z)
	match str(r["set_piece"]):
		"forge_hall":
			await _forge(r)
		"fungus_grotto":
			await _fungus(r, 8)
		"obsidian_grotto":
			await _obsidian(r)
		"ore_gallery":
			await _ore(r)
		"barracks":
			await _set_of(r, ["bed", "bed", "bedroll", "table_trestle", "stool", "stool", "chest", "shield", "spear"])
		"cellar_store":
			await _set_of(r, ["barrel", "barrel", "crate", "crate", "sack", "sack", "shelf"])
		"ossuary":
			await _set_of(r, ["coffin", "sarcophagus", "candlestick"])


func _lake(r: Dictionary, z: Dictionary) -> void:
	var at: Vector3 = z["at"]
	var rad := float(z["r"])
	var level := float(z["level"])
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(rad * 2.6, rad * 2.6)
	pm.subdivide_width = 6
	pm.subdivide_depth = 6
	plane.mesh = pm
	var wm := kit.still_water(level - 1.6, Color(0.8, 0.95, 1.0), 0.55)
	waters.append(wm)
	wm.set_meta("floor_local", level - 1.6)
	plane.material_override = wm
	plane.position = Vector3(at.x, level, at.z)
	plane.name = "Lake"
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plane)
	var area := Area3D.new()
	area.collision_layer = 1 << 11
	area.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rad * 2.0, 1.8, rad * 2.0)
	col.shape = box
	col.position.y = -0.9
	area.add_child(col)
	area.position = plane.position
	area.add_to_group("water_volume")
	root.add_child(area)
	_lamp(Vector3(at.x, level + 1.2, at.z), Color(0.45, 0.78, 0.85), 1.2, rad * 2.2)
	await _fungus(r, 2)


## Daylight down a hole in the roof: the sun's shaft, the sky in the hole, dust turning in it.
func _shaft(r: Dictionary, z: Dictionary) -> void:
	var at: Vector3 = z["at"]
	var rad := float(z["r"])
	var half: Vector3 = r["half"]
	var top := plan.bounds.end.y - 0.5
	var floor_y := at.y
	var height := top - floor_y
	var light := SpotLight3D.new()
	light.position = Vector3(at.x, top + 10.0, at.z)
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.spot_range = height + 20.0
	light.spot_angle = clampf(rad_to_deg(atan(rad * 2.4 / (height + 10.0))), 6.0, 26.0)
	light.light_energy = 6.0
	light.light_color = Color(1.0, 0.95, 0.84)
	light.shadow_enabled = true
	lights_node.add_child(light)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad * 1.0
	cm.bottom_radius = rad * 2.2
	cm.height = height
	cm.radial_segments = 20
	cone.mesh = cm
	var gm := ShaderMaterial.new()
	gm.shader = CaveInterior.SHAFT_SHADER
	gm.set_shader_parameter("intensity", 0.028)
	gm.set_shader_parameter("edge_softness", 0.55)
	gm.set_shader_parameter("bottom_fade", 0.72)
	gm.set_shader_parameter("shaft_color", Color(1.0, 0.95, 0.8))
	cone.material_override = gm
	cone.position = Vector3(at.x, floor_y + height * 0.5, at.z)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.name = "Shaft"
	root.add_child(cone)
	var sky := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = rad * 1.3
	disc.bottom_radius = rad * 1.3
	disc.height = 0.05
	sky.mesh = disc
	sky.material_override = mat("daylight")
	sky.position = Vector3(at.x, top - 0.2, at.z)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sky)
	# the floor where the light falls: a little green where it has grown
	var moss := kit.flora("fern") if plan.region != "cinderlea" else ""
	if moss != "":
		var tufts: Array = []
		for i in 7:
			var p := at + Vector3(kit.rng.randf_range(-rad, rad), 0.0, kit.rng.randf_range(-rad, rad))
			tufts.append(PoiKit.transform_at(floor_under(p), randf_yaw(), kit.rng.randf_range(0.5, 0.9)))
		kit.scatter(moss, tufts, false)
	_lamp(Vector3(at.x, floor_y + 1.5, at.z), Color(0.95, 0.92, 0.84), 1.6, half.length() * 1.2)
	await step()


func _rubble(z: Dictionary) -> void:
	var at: Vector3 = z["at"]
	var rad := float(z["r"])
	var path := kit.rock("boulder")
	if path == "":
		return
	var list: Array = []
	for i in 6:
		var p := at + Vector3(kit.rng.randf_range(-rad, rad), 0.0, kit.rng.randf_range(-rad, rad))
		list.append(PoiKit.transform_at(floor_under(p) + Vector3.DOWN * 0.2, randf_yaw(), kit.rng.randf_range(0.35, 0.7)))
	kit.scatter(path, list, true)
	await step()


## The rift across a room: a bridge over it (planks on rope, or the rock's own span), light in
## the deep (the lava's glow, or nothing), and what catches a fall: back to the near end.
func _chasm(r: Dictionary, z: Dictionary) -> void:
	var c: Vector3 = z["at"]
	var along: Vector3 = z["along"]
	var width := float(z["width"])
	var depth := float(z["depth"])
	var yaw := atan2(along.x, along.z)
	var basis := Basis(Vector3.UP, yaw)
	var span := width + 2.4
	if str(z["bridge"]) == "timber":
		var planks := m.begin()
		var posts := m.begin()
		var rope := m.begin()
		var n := int(span / 0.34)
		for i in n:
			var t := (float(i) + 0.5) / float(n) - 0.5
			var sag := (0.25 - t * t) * 0.35
			m.block(planks, Transform3D(basis.rotated(Vector3.UP, kit.rng.randf_range(-0.03, 0.03)),
					c + along * (t * span) + Vector3.DOWN * (0.05 + sag)), Vector3(1.7, 0.07, 0.3))
		for end in [-1.0, 1.0]:
			for s in [-1.0, 1.0]:
				var p := c + along * (float(end) * span * 0.5) + basis * Vector3(float(s) * 0.95, 0.0, 0.0)
				m.block(posts, Transform3D(basis, p + Vector3.UP * 0.55), Vector3(0.18, 1.2, 0.18))
		for s in [-1.0, 1.0]:
			var a := c - along * span * 0.5 + basis * Vector3(float(s) * 0.95, 1.05, 0.0)
			var b := c + along * span * 0.5 + basis * Vector3(float(s) * 0.95, 1.05, 0.0)
			var mid := (a + b) * 0.5 + Vector3.DOWN * 0.35
			m.limb(rope, a, mid, 0.03)
			m.limb(rope, mid, b, 0.03)
		m.commit(planks, mat("planks"), "Bridge")
		m.commit(posts, mat("timber"), "BridgePosts")
		m.commit(rope, mat("rope"), "BridgeRope")
		kit.collider(Vector3(1.7, 0.2, span + 0.6), Transform3D(basis, c + Vector3.DOWN * 0.14), "wood")
		# the ropes are a rail you cannot fall through
		for s in [-1.0, 1.0]:
			kit.collider(Vector3(0.1, 1.0, span), Transform3D(basis, c + basis * Vector3(float(s) * 1.0, 0.5, 0.0)), "wood")
		walk_faces.append(_box_faces(Transform3D(basis, c + Vector3.DOWN * 0.04), Vector3(1.6, 0.02, span + 0.6)))
	if bool(z["lava"]):
		var lava := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(z["reach"]), width + 1.0)
		lava.mesh = pm
		lava.material_override = mat("lava")
		lava.position = c + Vector3.DOWN * (depth - 1.0)
		lava.rotation.y = yaw
		lava.name = "Lava"
		root.add_child(lava)
		var side := basis * Vector3.RIGHT
		for s in [-1.0, 1.0]:
			_lamp(c + side * float(s) * float(z["reach"]) * 0.25 + Vector3.DOWN * (depth - 2.0), Color(1.0, 0.42, 0.12), 4.0, 12.0, 0.12)
	else:
		_lamp(c + Vector3.DOWN * (depth * 0.6), Color(0.35, 0.42, 0.55), 0.6, depth + 4.0)
	# a fall is caught at the bottom and the body stood back at the near end of the bridge
	var catch := Area3D.new()
	catch.name = "FallCatch"
	catch.collision_layer = 0
	catch.collision_mask = 1 << 1 | 1 << 2 | 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(z["reach"]), 2.0, width + 2.0)
	col.shape = box
	catch.add_child(col)
	catch.position = c + Vector3.DOWN * (depth - 0.8)
	catch.rotation.y = yaw
	site.add_child(catch)
	var ends := [c - along * (span * 0.5 + 1.2), c + along * (span * 0.5 + 1.2)]
	catch.body_entered.connect(func(body: Node3D) -> void:
			if body.is_in_group("player"):
				var local := site.to_local(body.global_position)
				var back: Vector3 = ends[0] if local.distance_to(ends[0]) < local.distance_to(ends[1]) else ends[1]
				body.global_position = site.to_global(back + Vector3.UP * 0.2)
				if "velocity" in body:
					body.set("velocity", Vector3.ZERO)
				EventBus.notify.emit("You catch yourself on the rift's edge.", "warning"))
	_catches.append(catch)
	await step()


func _box_faces(xf: Transform3D, size: Vector3) -> PackedVector3Array:
	var bm := BoxMesh.new()
	bm.size = size
	var faces := bm.get_faces()
	for i in faces.size():
		faces[i] = xf * faces[i]
	return faces


func _ledge(r: Dictionary, z: Dictionary) -> void:
	# a timber rail along the ledge's lip, so it reads as somewhere people stand
	var at: Vector3 = z["at"]
	var along: Vector3 = z["along"]
	var c: Vector3 = r["centre"]
	var inward := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var st := m.begin()
	var span := float(z.get("len", z.get("span", 6.0)))
	var lip := at + inward * 1.7
	for i in int(span / 2.0) + 1:
		var p := lip + along * (float(i) * 2.0 - span * 0.5)
		m.block(st, Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.5), Vector3(0.14, 1.0, 0.14))
	m.block(st, Transform3D(Basis(Vector3.UP, atan2(along.x, along.z)), lip + Vector3.UP * 0.95), Vector3(0.1, 0.1, span))
	m.commit(st, mat("timber"), "LedgeRail_%s" % r["id"])
	kit.collider(Vector3(0.12, 1.0, span), Transform3D(Basis(Vector3.UP, atan2(along.x, along.z)), lip + Vector3.UP * 0.5), "wood")
	_place("crate", at + along * (span * 0.4), randf_yaw(), 0.9)
	await step()


func _forge(r: Dictionary) -> void:
	var at := plan.take_spot(r, true)
	if at == Vector3.INF:
		return
	at = floor_under(at)
	var face := _face(at, r["centre"])
	_place("forge_hearth", at, face, 1.1)
	var front := at + Vector3(sin(face), 0.0, cos(face)) * 2.2
	_place("anvil", floor_under(front), face + 0.4, 1.0)
	_place("tongs", floor_under(front + Vector3(0.6, 0.0, 0.3)), randf_yaw(), 1.0, false)
	_place("hammer", floor_under(front + Vector3(-0.5, 0.0, 0.4)), randf_yaw(), 1.0, false)
	_place("whetstone", floor_under(front + Vector3(1.2, 0.0, -0.6)), randf_yaw(), 1.0)
	_lamp(at + Vector3.UP * 1.2, Color(1.0, 0.5, 0.18), 4.2, 15.0, 0.25, true)
	await step()


func _obsidian(r: Dictionary) -> void:
	var st := m.begin()
	for i in 7:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		at = floor_under(at)
		for k in kit.rng.randi_range(3, 6):
			var h := kit.rng.randf_range(0.4, 1.6)
			var tilt := Basis(Vector3.UP, randf_yaw()) * Basis(Vector3.RIGHT, kit.rng.randf_range(-0.4, 0.4))
			m.block(st, Transform3D(tilt, at + Vector3(kit.rng.randf_range(-0.6, 0.6), h * 0.4, kit.rng.randf_range(-0.6, 0.6))),
					Vector3(kit.rng.randf_range(0.15, 0.35), h, kit.rng.randf_range(0.1, 0.25)))
	await step()
	m.commit(st, mat("obsidian"), "Obsidian_%s" % r["id"])
	_lamp((r["centre"] as Vector3) + Vector3.UP * 1.0, Color(0.75, 0.5, 1.0), 1.0, 9.0)


func _ore(r: Dictionary) -> void:
	var st := m.begin()
	var c: Vector3 = r["centre"]
	for i in 6:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		var out := Vector3(at.x - c.x, 0.0, at.z - c.z).normalized()
		var wall := _wall_toward(at + Vector3.UP * kit.rng.randf_range(0.8, 2.4), out)
		m.block(st, Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)) * Basis(Vector3.FORWARD, kit.rng.randf_range(-0.8, 0.8)), wall),
				Vector3(1.4, 0.12, 0.25))
	m.commit(st, mat("ore"), "Ore_%s" % r["id"])
	# a room whose spots the ore took all of has no floor left for the cart: a cart at INF stood
	# every founders' gallery's cart nowhere, with a renderer error for each
	var cart_at := plan.take_spot(r, false)
	if cart_at != Vector3.INF:
		_place("cart", floor_under(cart_at), randf_yaw(), 1.0)
	await step()


func _set_of(r: Dictionary, kinds: Array) -> void:
	for kind in kinds:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		at = floor_under(at)
		_place(str(kind), at, _face(at, r["centre"]) + kit.rng.randf_range(-0.3, 0.3), 1.0)
		await step()


## A heap of bones: long bones crossed, a skull or two (masonry, in the bone's colour).
func _bones(at: Vector3, spread: float, skulls: int, facing: Vector3 = Vector3.FORWARD) -> void:
	var st := m.begin()
	for i in 6:
		var a := at + Vector3(kit.rng.randf_range(-spread, spread), 0.05, kit.rng.randf_range(-spread, spread) * 0.6)
		var dir := Vector3(kit.rng.randf_range(-1, 1), kit.rng.randf_range(-0.1, 0.1), kit.rng.randf_range(-1, 1)).normalized()
		m.limb(st, a - dir * 0.2, a + dir * 0.2, 0.025)
	for k in skulls:
		var s := at + Vector3(kit.rng.randf_range(-spread, spread) * 0.6, 0.1, kit.rng.randf_range(-spread, spread) * 0.4)
		m.ellipsoid(st, s, Vector3(0.085, 0.1, 0.11), Basis(Vector3.UP, atan2(facing.x, facing.z)))
	m.commit(st, mat("bone"), "Bones")
	await step()


# --- what was left lying ----------------------------------------------------------------------------

func _props(r: Dictionary) -> void:
	var half: Vector3 = r["half"]
	var area := half.x * half.z * 4.0
	var budget := clampi(int(area / 30.0), 2, 9)
	if r["role"] in ["passage", "secret"]:
		budget = 2
	var kinds: Array = plan.spec.get("props", ["rocks"])
	var role := str(r["role"])
	for k in kinds:
		match str(k):
			"rocks":
				await _boulders(r, maxi(2, (budget >> 1)))
			"bones_light":
				if kit.rng.randf() < 0.4:
					var at := plan.take_spot(r, true)
					if at != Vector3.INF:
						await _bones(floor_under(at), 0.5, 1)
			"bones":
				for i in maxi(1, floori(budget / 3.0)):
					var at := plan.take_spot(r, true)
					if at != Vector3.INF:
						await _bones(floor_under(at), 0.6, 2)
			"tombs":
				await _set_of(r, ["sarcophagus", "coffin"].slice(0, 1 + kit.rng.randi() % 2))
			"stores":
				await _clusters(r, ["barrel", "crate", "sack"], maxi(1, floori(budget / 3.0)))
			"barracks":
				if role in ["hall", "chamber"]:
					await _set_of(r, ["bedroll", "table_trestle", "stool", "shield"].slice(0, 2 + kit.rng.randi() % 3))
			"camp":
				if role in ["camp", "hall", "chamber"]:
					await _camp(r)
			"timbering":
				await _frames_in(r)
			"mine_gear":
				await _set_of(r, ["wheelbarrow", "bucket", "rope_coil", "cart", "pitchfork"].slice(0, 1 + kit.rng.randi() % 3))
			"shore":
				await _set_of(r, ["rope_coil", "crab", "basket"].slice(0, 1 + kit.rng.randi() % 2))
				if role == "hall" or r["set_piece"] == "underground_lake":
					await _set_of(r, ["rowboat"])
			"basalt":
				await _rocks_of(r, "basalt_columns", 2)
				await _boulders(r, 2)
			"ash":
				await _rocks_of(r, "scree", 2)
			"rubble":
				await _boulders(r, (budget >> 1) + 1)
			"roots":
				await _roots(r)


func _boulders(r: Dictionary, count: int) -> void:
	var path := kit.rock("boulder")
	if path == "":
		return
	var list: Array = []
	for i in count:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		var sc := kit.rng.randf_range(0.45, 0.9)
		list.append(PoiKit.transform_at(floor_under(at) + Vector3.DOWN * 0.12 * sc, randf_yaw(), sc))
	if not list.is_empty():
		kit.scatter(path, list, true)
	await step()


func _rocks_of(r: Dictionary, kind: String, count: int) -> void:
	var path := kit.rock(kind)
	if path == "":
		return
	var list: Array = []
	for i in count:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		list.append(PoiKit.transform_at(floor_under(at) + Vector3.DOWN * 0.3, randf_yaw(), kit.rng.randf_range(0.4, 0.8)))
	if not list.is_empty():
		kit.scatter(path, list, kind != "scree")
	await step()


func _clusters(r: Dictionary, kinds: Array, count: int) -> void:
	for i in count:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		at = floor_under(at)
		var face := _face(at, r["centre"])
		for k in kit.rng.randi_range(2, 3):
			var p := at + Basis(Vector3.UP, face) * Vector3(float(k) * 0.75 - 0.75, 0.0, kit.rng.randf_range(-0.2, 0.2))
			_place(str(kinds[kit.rng.randi() % kinds.size()]), floor_under(p), face + kit.rng.randf_range(-0.5, 0.5), 1.0)
		await step()


## A bandit's camp: bedrolls round the fire, a tent if there is room, stores, a table.
func _camp(r: Dictionary) -> void:
	var fire: Vector3 = r.get("fire", Vector3.INF)
	if fire == Vector3.INF:
		fire = r["centre"]
	for i in 3:
		var at := plan.take_spot(r, false, fire)
		if at == Vector3.INF:
			break
		_place("bedroll", floor_under(at), _face(at, fire), 1.0, false)
	var half: Vector3 = r["half"]
	if minf(half.x, half.z) > 6.0:
		var t := plan.take_spot(r, true)
		if t != Vector3.INF:
			_place("tent", floor_under(t), _face(t, r["centre"]), 0.9)
	await _set_of(r, ["crate", "barrel", "table_trestle", "cooking_pot"].slice(0, 2 + kit.rng.randi() % 3))


## A mine's timbering: frames of posts and a cap against the walls.
func _frames_in(r: Dictionary) -> void:
	var st := m.begin()
	var c: Vector3 = r["centre"]
	for i in 2:
		var at := plan.take_spot(r, true)
		if at == Vector3.INF:
			break
		var out := Vector3(at.x - c.x, 0.0, at.z - c.z).normalized()
		var along := Vector3(out.z, 0.0, -out.x)
		var base := floor_under(at)
		var h := 2.6
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(Basis.IDENTITY, base + along * float(s) * 1.1 + Vector3.UP * h * 0.5), Vector3(0.22, h, 0.22))
		m.block(st, Transform3D(Basis(Vector3.UP, atan2(along.x, along.z)), base + Vector3.UP * (h + 0.1)), Vector3(0.24, 0.24, 2.6))
	m.commit(st, mat("timber"), "Timbering_%s" % r["id"])
	await step()


func _roots(r: Dictionary) -> void:
	var st := m.begin()
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	for i in 4:
		var a := randf_yaw()
		var top := c + Vector3(sin(a) * half.x * 0.5, half.y * 0.95, cos(a) * half.z * 0.5)
		var foot := floor_under(c + Vector3(sin(a) * half.x * 0.75, 0.0, cos(a) * half.z * 0.75))
		var bend := (top + foot) * 0.5 + Vector3(kit.rng.randf_range(-1, 1), 0.0, kit.rng.randf_range(-1, 1))
		m.limb(st, top, bend, 0.14)
		m.limb(st, bend, foot, 0.1)
	m.commit(st, mat("timber"), "Roots_%s" % r["id"])
	await step()


# --- passages ---------------------------------------------------------------------------------------

func _link(l: Dictionary) -> void:
	var pts: Array = l["points"]
	var kind := str(l["kind"])
	var square := plan._built() or bool(plan.spec.get("square_tunnels", false))
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		var slope := (b.y - a.y) / maxf(run, 0.01)
		if plan._built() and absf(slope) > 0.1:
			await _stairs(a, b, float(l["width"]))
		if square and not plan._built():
			await _timber_run(a, b, float(l["width"]))
		if run > 10.0 and kind != "secret":
			var mid := (a + b) * 0.5
			var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			if plan.spec.get("lights", []).has("fungus") or plan.spec.get("lights", []).has("lava"):
				var st := m.begin()
				var side := Vector3(dir.z, 0.0, -dir.x) * (float(l["width"]) * 0.4)
				var p := floor_under(mid + side)
				for k in 5:
					var q := p + Vector3(kit.rng.randf_range(-0.4, 0.4), 0.0, kit.rng.randf_range(-0.4, 0.4))
					m.ellipsoid(st, q + Vector3.UP * 0.1, Vector3(0.12, 0.05, 0.12))
				m.commit(st, mat("fungus" if plan.spec.get("lights", []).has("fungus") else "ember"), "Glow")
			elif plan.spec.get("lights", []).has("torch") or plan.spec.get("lights", []).has("lantern"):
				var at := mid + Vector3.UP * 0.0
				_lamp(floor_under(at) + Vector3.UP * 2.2, Color(str(plan.spec.get("light_colour", "#ffb066"))), 1.2, 8.0, 0.3)
	match kind:
		"secret":
			await _seal(l, true)
		"shortcut":
			await _seal(l, false)


## Steps down a built passage's ramp: dressed treads over the rock's own slope, which is what is
## walked (so a foot never catches a nosing and the navigation mesh has a ramp).
func _stairs(a: Vector3, b: Vector3, width: float) -> void:
	var st := m.begin()
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var run := dir.length()
	dir = dir / run
	var yaw := atan2(dir.x, dir.z)
	var rise := b.y - a.y
	var n := maxi(int(absf(rise) / 0.22), 2)
	var tread := run / float(n)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t)
		var top := a.y + rise * (float(i) + (1.0 if rise > 0.0 else 0.0)) / float(n)
		m.block(st, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top - 0.2, p.z)), Vector3(width - 0.3, 0.4, tread * 1.02))
	m.commit(st, mat("stone"), "Stairs")
	await step()


func _timber_run(a: Vector3, b: Vector3, width: float) -> void:
	var st := m.begin()
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var run := dir.length()
	dir = dir / run
	var side := Vector3(dir.z, 0.0, -dir.x)
	var yaw := atan2(dir.x, dir.z)
	var h := width * 1.25 - 0.35
	var n := int(run / 4.0)
	var lanterns := 0
	for i in range(1, n):
		var p := a.lerp(b, float(i) / float(n))
		for s in [-1.0, 1.0]:
			m.block(st, Transform3D(Basis.IDENTITY, p + side * float(s) * (width * 0.5 - 0.25) + Vector3.UP * h * 0.5), Vector3(0.2, h, 0.2))
		m.block(st, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + Vector3.UP * (h + 0.1)), Vector3(0.22, 0.22, width))
		if i % 3 == 0 and lanterns < 2:
			_lamp(p + Vector3.UP * (h - 0.3), Color(1.0, 0.78, 0.46), 1.3, 7.0, 0.12)
			lanterns += 1
	m.commit(st, mat("timber"), "Timbering")
	await step()


## The loose stones before the secret room (at the host room's mouth), or the bar across the way
## back out (at the entrance's end, lifted from the boss's side).
func _seal(l: Dictionary, secret: bool) -> void:
	var pts: Array = l["points"]
	var at: Vector3
	var toward: Vector3
	if secret:
		at = pts[0]
		toward = ((pts[1] as Vector3) - at)
	else:
		at = pts[-1]
		toward = ((pts[-2] as Vector3) - at)
	toward.y = 0.0
	toward = toward.normalized()
	at += toward * 1.6
	var seal := SiteSeal.new()
	seal.name = "Seal_%s" % l["kind"]
	seal.flag = "site_open/%s/%s" % [plan.id, l["kind"]]
	seal.position = at
	seal.rotation.y = atan2(toward.x, toward.z)
	var w := float(l["width"]) + 0.8
	var h := 3.4 if secret else float(l["width"]) * 1.4
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, 0.9)
	cs.shape = box
	cs.position.y = h * 0.5
	seal.add_child(cs)
	var st := m.begin()
	if secret:
		seal.display_name = "Loose stones"
		seal.open_prompt = "Pull the loose stones away"
		# the region's own stones heaped across the passage from its floor to above a body's height,
		# packed so they touch (rows of three a metre apart floated as three separate bands), fewer
		# and smaller toward the top, the small stuff spilled at the foot
		var boulder := kit.rock("boulder")
		var packed := PoiKit.scene(boulder) if boulder != "" else null
		var bh := maxf(PoiKit.height_of(boulder), 0.3) if boulder != "" else 1.0
		var per_row := [4, 4, 3, 2]
		var y := -0.15
		for row in per_row.size():
			if packed == null:
				break
			var count: int = per_row[row]
			var size := lerpf(1.05, 0.8, float(row) / 3.0)
			for i in count:
				var stone := packed.instantiate() as Node3D
				var x := (float(i) + 0.5 - float(count) * 0.5) * (w / 4.0) * 1.05 + kit.rng.randf_range(-0.12, 0.12)
				stone.position = Vector3(x, y, kit.rng.randf_range(-0.2, 0.2))
				stone.rotation = Vector3(kit.rng.randf_range(-0.5, 0.5), randf_yaw(), kit.rng.randf_range(-0.5, 0.5))
				stone.scale = Vector3.ONE * size / bh * kit.rng.randf_range(0.9, 1.15)
				seal.add_child(stone)
			y += size * 0.72
		if packed != null:
			for i in 5:
				var stone := packed.instantiate() as Node3D
				stone.position = Vector3(kit.rng.randf_range(-w * 0.45, w * 0.45), -0.1, kit.rng.randf_range(-1.1, -0.5))
				stone.rotation = Vector3(kit.rng.randf_range(-0.6, 0.6), randf_yaw(), kit.rng.randf_range(-0.6, 0.6))
				stone.scale = Vector3.ONE * kit.rng.randf_range(0.3, 0.5) / bh
				seal.add_child(stone)
	else:
		seal.display_name = "A barred gate"
		seal.open_prompt = "Lift the bar"
		seal.shut_prompt = "Barred from the other side"
		seal.from_side = toward   # set in world space below
		for i in 7:
			var x := -w * 0.45 + float(i) * w * 0.9 / 6.0
			m.block(st, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5, 0.0)), Vector3(0.12, h, 0.12))
		for y in [0.5, h * 0.55, h - 0.3]:
			m.block(st, Transform3D(Basis.IDENTITY, Vector3(0.0, float(y), -0.1)), Vector3(w, 0.16, 0.1))
	var inst := MeshInstance3D.new()
	st.generate_normals()
	inst.mesh = st.commit()
	inst.material_override = mat("stone") if secret else mat("iron")
	inst.name = "Look"
	seal.add_child(inst)
	site.add_child(seal)
	if not secret:
		seal.from_side = site.global_transform.basis * toward
	await step()


# --- loot and features --------------------------------------------------------------------------

func _containers() -> void:
	for cdef in plan.containers:
		var at := floor_under(cdef["at"])
		var yaw := float(cdef["yaw"])
		var kind := str(cdef["prop"])
		if str(cdef["tier"]) in ["rich", "boss"]:
			kind = "chest"
		var look := _place(kind, at, yaw, 1.0, false)
		var box := WorldContainer.new()
		box.name = "Container"
		box.container_id = str(cdef["id"])
		box.loot_table = str(cdef["table"])
		box.display_name = {"chest": "Chest", "crate": "Crate", "sarcophagus": "Sarcophagus"}.get(kind, "Chest")
		var cs := CollisionShape3D.new()
		var form := BoxShape3D.new()
		form.size = Vector3(1.0, 0.7, 0.6) if kind != "sarcophagus" else Vector3(2.2, 0.9, 1.0)
		cs.shape = form
		cs.position.y = form.size.y * 0.5
		box.add_child(cs)
		box.position = at
		box.rotation.y = yaw
		root.add_child(box)
		if look != null:
			look.set_meta("container", box.container_id)
		await step()


func _features() -> void:
	# what a quest says lies in here, and the def's own items, through the quest-item placer
	var items := QuestItems.ensure() if site.is_inside_tree() else null
	var meta := compat_meta()
	for f in plan.features:
		var kind := str(f.get("kind", "prop"))
		var at := floor_under(f["at"])
		var yaw := deg_to_rad(float(f.get("yaw", 0.0)))
		match kind:
			"hearthstone":
				kit.hearthstone(at, yaw, str(f.get("id", Ids.name_of(plan.id) + "_hearth")), str(f.get("name", "Hearthstone")))
			"readable", "note":
				var rd := Readable.new()
				rd.book_id = str(f.get("book", ""))
				rd.display_name = str(f.get("name", "a note"))
				rd.fixed = bool(f.get("fixed", false))
				rd.item_id = str(f.get("item", ""))
				rd.position = at + Vector3.UP * 0.02
				rd.rotation.y = yaw
				root.add_child(rd)
				_place("paper_stack" if kind == "note" else "book", at, yaw, 1.0, false)
			"prop":
				_place(str(f.get("prop", "crate")), at, yaw, float(f.get("scale", 1.0)))
			"item":
				pass
		await step()
	if items != null:
		var placed: Array = items.call("raise_in_interior", root, plan.id, meta, Callable(self, "_feature_at"))
		for node in placed:
			if node is Node3D:
				(node as Node3D).position = floor_under((node as Node3D).position) + Vector3.UP * 0.02
	await step()


## The plan as the deep places' meta reads, for the quest-item placer: chambers with their roles,
## middles and clear floor, and the def's item features in their rooms.
func compat_meta() -> Dictionary:
	var chambers := {}
	for r in plan.rooms:
		var pts: Array = []
		for p in (r["spots"] as Array).slice(0, 6):
			pts.append([(p as Vector3).x, (p as Vector3).y, (p as Vector3).z])
		var c: Vector3 = r["centre"]
		chambers[r["id"]] = {"role": "treasure" if r["role"] in ["secret", "treasure"] else r["role"],
				"centre": [c.x, c.y, c.z], "floor_points": pts}
	var feats: Array = []
	for f in plan.features:
		if str(f.get("kind", "")) == "item":
			var a: Vector3 = f["at"]
			var fd: Dictionary = f.duplicate()
			fd["chamber"] = f.get("room", "")
			fd["at"] = [a.x, a.y, a.z]
			feats.append(fd)
	return {"id": plan.id, "chambers": chambers, "features": feats}


func _feature_at(f: Dictionary) -> Vector3:
	var a: Variant = f.get("at", null)
	if a is Array:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	var r := plan.room(str(f.get("chamber", "")))
	return r["centre"] if not r.is_empty() else Vector3.ZERO


# --- who is here --------------------------------------------------------------------------------

func people() -> void:
	spawner = EnemySpawner.new()
	spawner.name = "Foes"
	spawner.spawn_on_ready = false
	site.add_child(spawner)
	for ei in plan.encounters.size():
		var e: Dictionary = plan.encounters[ei]
		var enemy_id := str(e["enemy"])
		if not ContentDB.has(enemy_id):
			Log.warn("SiteDress", "%s: no foe '%s'" % [plan.id, enemy_id])
			continue
		var role := str(e["role"])
		if role == "boss" and GameState.has_flag("boss_deed/" + enemy_id):
			continue
		var i := 0
		for p in e["spots"]:
			# whoever was killed here stays dead when the place is entered again, until a rest
			var key := "%s/%s/%d/%d" % [plan.id, e["room"], ei, i]
			if role != "boss" and SiteFallen.is_fallen(key):
				i += 1
				continue
			var at := site.to_global(floor_under(p) + Vector3.UP * 0.05)
			var opts := {"group": "%s/%s" % [plan.id, e["room"]]}
			if e.has("patrol"):
				var route: Array = []
				for q in e["patrol"]:
					route.append(site.to_global(floor_under(q)))
				opts["patrol"] = route
			await step()
			var foe := spawner.spawn_one(enemy_id, at, float(e.get("yaw", 0.0)) + float(i) * 0.9, opts)
			site.note_foe()
			i += 1
			if foe == null:
				continue
			if role != "boss":
				SiteFallen.watch(foe, key)
			match role:
				"sleeper":
					# lying by the fire: roused by noise, a blow, or being walked into
					foe.inactive = true
					if foe.perception != null and "sight_range" in foe.perception:
						foe.perception.set("sight_range", float(foe.perception.get("sight_range")) * 0.35)
				"ambush":
					foe.inactive = true
				"archer":
					foe.brain.post = foe.global_position
					foe.set_meta("holds_post", true)
			await step()
		if role == "boss":
			_arena(e)
	await step()


func _arena(e: Dictionary) -> void:
	var r := plan.room(str(e["room"]))
	if r.is_empty():
		return
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	# the gate across the way in along the walk
	var way_in := Vector3.ZERO
	for li in r["links"]:
		var l: Dictionary = plan.links[li]
		if str(l["kind"]) == "passage":
			var pts: Array = l["points"]
			way_in = pts[-1] if l["b"] == r["id"] else pts[0]
			break
	var toward := way_in - c
	toward.y = 0.0
	if toward.length() < 0.1:
		return
	toward = toward.normalized()
	var arena := CaveInterior.BOSS_ARENA.instantiate() as BossArena
	arena.name = "BossArena"
	arena.boss_id = str(e["enemy"])
	arena.radius = maxf(half.x, half.z)
	arena.min_radius = minf(BossArena.MIN_RADIUS, arena.radius)
	arena.position = Vector3(way_in.x, c.y, way_in.z)
	arena.rotation.y = atan2(toward.x, toward.z)
	site.add_child(arena)
	arena.centre = site.to_global(c)


# --- every frame ----------------------------------------------------------------------------------

## Compatibility draws at most `max_renderable_lights` (32) lights in view and drops the rest in no
## order it says: from the Kilnway's way in, looking down the tube, more than that were in the
## frustum and the mouth room's own went, so the first view in was black (the same room lit from its
## other doorway). So only the NEAR_LIGHTS lights nearest the eye (by how far their reach falls short
## of it) are on at once, chosen again as the eye moves.
const NEAR_LIGHTS := 24
var _near_from := Vector3.INF


func _nearest_lights() -> void:
	var vp := site.get_viewport() if site.is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var eye := site.to_local(cam.global_position)
	if _near_from != Vector3.INF and eye.distance_squared_to(_near_from) < 1.0:
		return
	_near_from = eye
	var order: Array = []
	for l in lights:
		if not bool(l.get_meta("budget_on", true)):
			continue
		var reach := (l as OmniLight3D).omni_range if l is OmniLight3D else ((l as SpotLight3D).spot_range if l is SpotLight3D else 0.0)
		order.append([l.position.distance_to(eye) - reach, l])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in order.size():
		(order[i][1] as Light3D).visible = i < NEAR_LIGHTS


func flicker() -> void:
	if site.is_built:
		_nearest_lights()
	if not _water_set and site.is_inside_tree():
		# the water's depth is read in world space, and the interior is moved to its pocket after it
		# is built
		for w in waters:
			w.set_shader_parameter("floor_y", site.global_position.y + float(w.get_meta("floor_local", 0.0)))
		_water_set = true
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in lights.size():
		var l := lights[i]
		var amount := float(l.get_meta("flicker", 0.0))
		if amount <= 0.0:
			continue
		var base := float(l.get_meta("base_energy", 1.0))
		var k := float(i) * 1.7
		var f := sin(t * 7.3 + k) * 0.5 + sin(t * 13.1 + k * 2.1) * 0.3 + sin(t * 3.1 + k) * 0.2
		l.light_energy = base * (1.0 + f * amount * 0.5)
