extends TestCase
## Footsteps where feet land in the built world, not on a test floor: a market street in Merrowby,
## the deck of a bridge, the bog at Isseva, the floor of a cave, the snow of the Skerrow heights and
## the western tide-flats. Each place is found in the world as it was built (the terrain's own paint
## underfoot, a bridge POI's own deck, a deep place's own floor), a body's footfalls walk it, and
## what was heard is compared with what the ground is. Every step goes through the same code a
## walking body uses (Footfalls -> Foley.surface_at -> Foley.footstep).
##
## Before this, the world's ground said nothing and every step on it was its region's nominal
## ground: cobbles, snow and the tide-flats all sounded like the Vale's grass or the region's mud,
## and a bridge sounded like whatever the river bank was.

const WORLD_SCENE := "res://world/world.tscn"
const FRAME := 1.0 / 60.0

var _heard: Array[String] = []
## Where the probe's feet are: only steps made there are counted (a villager or a weaver walking
## past makes footsteps of its own).
var _probe_at := Vector3.INF


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _on_played(id: String, at: Vector3) -> void:
	if id.begins_with("footstep_") and at.distance_to(_probe_at) < 0.01:
		_heard.append(id)


func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


## A point near `centre` (within `radius` m) whose painted texture is one of `textures`, dry and on
## the terrain, searched outward in rings; Vector3.INF when there is none.
static func _painted_near(centre: Vector3, textures: Array, radius: float, step := 6.0) -> Vector3:
	var terrain := World.terrain()
	if terrain == null:
		return Vector3.INF
	var r := 0.0
	while r <= radius:
		var around := maxi(1, int(TAU * r / step))
		for i in around:
			var a := TAU * float(i) / float(around)
			var x := centre.x + cos(a) * r
			var z := centre.z + sin(a) * r
			if terrain.is_water(x, z):
				continue
			if terrain.texture_at(x, z) in textures:
				return Vector3(x, terrain.get_height(x, z), z)
		r += step
	return Vector3.INF


## Walks a body's footfalls a few strides at `at` (a probe standing where the feet are, the player
## brought alongside so the steps are within hearing) and returns the footstep ids heard.
func _steps_at(player: Node3D, at: Vector3) -> Array[String]:
	player.global_position = at + Vector3(0.6, 0.3, 0.0)
	var probe := Node3D.new()
	_tree().root.add_child(probe)
	probe.global_position = at
	await _frames(2)
	var feet := Footfalls.new()
	_heard.clear()
	_probe_at = at
	# Three seconds at a walk: six strides.
	for i in 180:
		feet.advance(probe, FRAME, 4.2, true)
	probe.free()
	return _heard.duplicate()


func test_footsteps_fall_on_what_the_built_world_is_made_of() -> void:
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	var spawn: Node = w.get_node_or_null("PlayerSpawn")
	var player: Node3D = spawn.get("player") if spawn != null else null
	assert_true(player != null, "somebody stands in the world")
	if player == null:
		_tree().root.remove_child(w)
		w.queue_free()
		return
	Foley.played.connect(_on_played)
	var found := {}
	# The street: the cobbles laid in Merrowby's market.
	var street := _painted_near(w.place_position("core:place/merrowby"), ["cobbles"], 220.0)
	found["a market street in Merrowby (cobbles)"] = [street, "footstep_stone"]
	# The bog: peat and mud about Isseva, the jetty town in the marsh.
	var bog := _painted_near(w.place_position("core:place/isseva"), ["mud", "peat"], 400.0)
	found["the bog at Isseva (mud, peat)"] = [bog, "footstep_mud"]
	# The heights: snow above the snow line in Skerrow.
	var snow := _painted_near(w.place_position("core:place/fallen_hand"), ["snow"], 900.0, 10.0)
	found["the Skerrow heights (snow)"] = [snow, "footstep_snow"]
	# The tide-flats past the marsh's western edge.
	var sand := _painted_near(Vector3(-3450.0, 0.0, -450.0), ["sand_flats"], 700.0, 10.0)
	found["the western tide-flats (sand)"] = [sand, "footstep_sand"]
	for what in found:
		var at: Vector3 = found[what][0]
		assert_true(at != Vector3.INF, "%s is somewhere in the world" % what)
		if at == Vector3.INF:
			continue
		var heard := await _steps_at(player, at)
		print("FOOTSTEPS | %s | %s | heard %s" % [what, str(Vector2(at.x, at.z).round()), str(_counts(heard))])
		assert_gt(heard.size(), 3, "%s: steps were heard" % what)
		assert_true(heard.all(func(id: String) -> bool: return id == str(found[what][1])),
				"%s sounds %s: %s" % [what, found[what][1], str(_counts(heard))])
	# The bridge: a bridge POI raised as the streamer raises it, stepped on its own deck.
	var pois := _tree().get_first_node_in_group(WorldPois.GROUP) as WorldPois
	assert_true(pois != null, "the world indexes its points of interest")
	var decks := {}
	var raised: Array[Node] = []
	if pois != null:
		for id in ["core:poi/larkbourne_ford", "core:poi/long_stride", "core:poi/eelweir", "core:poi/lantern_causeway", "core:poi/mossbridge"]:
			var d := pois.raise_one(id)
			if d == null:
				continue
			raised.append(d)
			await _frames(2)
			for deck in _decks_of(d):
				var surface := str(deck["surface"])
				if not decks.has(surface):
					decks[surface] = {"at": deck["at"], "poi": id}
	assert_true(decks.has("stone"), "a stone bridge's deck says it is stone: %s" % str(decks.keys()))
	for surface in decks:
		var at: Vector3 = decks[surface]["at"]
		assert_eq(Foley.surface_at(at), str(surface), "%s's deck is %s underfoot" % [decks[surface]["poi"], surface])
		var heard := await _steps_at(player, at)
		print("FOOTSTEPS | the deck of %s | %s | heard %s" % [decks[surface]["poi"], str(Vector2(at.x, at.z).round()), str(_counts(heard))])
		assert_gt(heard.size(), 3, "steps on %s's deck were heard" % decks[surface]["poi"])
		assert_true(heard.all(func(id: String) -> bool: return id == "footstep_" + str(surface)),
				"%s's deck sounds %s: %s" % [decks[surface]["poi"], surface, str(_counts(heard))])
	for d in raised:
		d.queue_free()
	# The cave: a deep place's own floor, where going in through its door stands the player.
	assert_true(Interiors.enter("core:interior/weaverdeep"), "Weaverdeep can be entered")
	await _frames(30)
	var floor_at: Vector3 = player.global_position
	var heard := await _steps_at(player, floor_at)
	print("FOOTSTEPS | the floor of Weaverdeep | %s | heard %s" % [str(Vector2(floor_at.x, floor_at.z).round()), str(_counts(heard))])
	assert_gt(heard.size(), 3, "steps in the cave were heard")
	assert_true(heard.all(func(id: String) -> bool: return id == "footstep_stone"), "a cave floor is stone: %s" % str(_counts(heard)))
	Interiors.exit()
	Interiors.unload_all()
	Foley.played.disconnect(_on_played)
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame


## Every ground the world builder paints (the manifest's texture slots) is a ground a foot knows:
## each has a footstep surface, and that surface has a sound. A slot added to the builder without
## one would fall back to the region's nominal ground, which is what every step sounded like
## before the paint was read.
func test_every_painted_ground_has_a_footstep() -> void:
	var path := "res://world/generated/world_manifest.json"
	if not FileAccess.file_exists(path):
		print("  (world data missing: run ./run.sh world; painted-ground check skipped)")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(manifest is Dictionary, "the manifest reads")
	if not (manifest is Dictionary):
		return
	var slots: Array = (manifest as Dictionary).get("texture_slots", [])
	assert_gt(slots.size(), 10, "the manifest names the textures it painted")
	var unheard: Array[String] = []
	for slot in slots:
		var surface := str(Foley.TEXTURE_SURFACE.get(str(slot), ""))
		if surface.is_empty() or not Foley.rows.has("footstep_" + surface):
			unheard.append(str(slot))
	assert_empty(unheard, "painted grounds with no footstep: %s" % str(unheard))


## The walkable tops of a dressing's built colliders that declare a surface: {surface, at}, the
## widest flat ones first (a deck is wider than a parapet is tall).
static func _decks_of(dressing: Node) -> Array:
	var out: Array = []
	for cs_v in dressing.find_children("*", "CollisionShape3D", true, false):
		var cs := cs_v as CollisionShape3D
		if not cs.has_meta(PoiKit.SURFACE_META) or not (cs.shape is BoxShape3D):
			continue
		var size := (cs.shape as BoxShape3D).size
		if size.x < 1.2 or size.z < 1.2 or size.y > 0.8:
			continue
		var top := cs.global_transform.origin + cs.global_transform.basis.y.normalized() * (size.y * 0.5)
		out.append({"surface": str(cs.get_meta(PoiKit.SURFACE_META)), "at": top, "area": size.x * size.z})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) > float(b["area"]))
	return out


static func _counts(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = int(out.get(id, 0)) + 1
	return out
