class_name CaveInterior
extends Node3D
## Builds a deep place from a cave-forge meta file: shell, collision, light shafts, water,
## lights, dressing and encounter markers.
##
## The generated shell is the base layer only. Everything that makes the place a place
## comes from the recipe's `features` list (hand-placed) and the per-chamber dressing
## rules below, which read the chamber's authored role.

const ROCK_SHADER := preload("res://assets/shaders/cave_rock.gdshader")
const WATER_SHADER := preload("res://assets/shaders/still_water.gdshader")
const SHAFT_SHADER := preload("res://assets/shaders/light_shaft.gdshader")
const HEARTHSTONE := preload("res://systems/hearth/hearthstone.tscn")
const DOOR := preload("res://systems/interiors/door.tscn")
const BOSS_ARENA := preload("res://actors/enemy/boss_arena.tscn")

## Surface parameters per formation: what cut the rock decides how the rock reads.
const ROCK_BY_FORMATION := {
	"water": {"bed_scale": 0.14, "bed_strength": 0.30, "block_scale": 0.34, "block_strength": 0.40,
			  "grain_scale": 6.0, "grain_strength": 0.22, "bump_strength": 0.75, "roughness_base": 0.82,
			  "occlusion": 0.70, "brightness": 1.10, "vein_amount": 0.14},
	"mining": {"bed_scale": 0.10, "bed_strength": 0.22, "block_scale": 0.55, "block_strength": 0.80,
			   "grain_scale": 9.0, "grain_strength": 0.30, "bump_strength": 0.85, "roughness_base": 0.93,
			   "occlusion": 0.72, "brightness": 1.05, "vein_amount": 0.26},
	"creature": {"bed_scale": 0.07, "bed_strength": 0.10, "block_scale": 0.28, "block_strength": 0.55,
				 "grain_scale": 5.0, "grain_strength": 0.34, "bump_strength": 1.05, "roughness_base": 0.88,
				 "occlusion": 0.78, "brightness": 1.00, "vein_amount": 0.08},
	"crypt": {"bed_scale": 0.22, "bed_strength": 0.45, "block_scale": 0.46, "block_strength": 0.70,
			  "grain_scale": 7.5, "grain_strength": 0.26, "bump_strength": 0.90, "roughness_base": 0.90,
			  "occlusion": 0.74, "brightness": 1.12, "vein_amount": 0.20},
	# Oroth: cut whole, no joints anywhere, courses you could lie down on.
	"builder": {"bed_scale": 0.045, "bed_strength": 0.55, "block_scale": 0.085, "block_strength": 1.05,
				"grain_scale": 3.0, "grain_strength": 0.10, "bump_strength": 1.25, "roughness_base": 0.62,
				"occlusion": 0.60, "brightness": 1.22, "vein_amount": 0.05},
	"ice": {"bed_scale": 0.09, "bed_strength": 0.38, "block_scale": 0.30, "block_strength": 0.30,
			"grain_scale": 4.5, "grain_strength": 0.14, "bump_strength": 0.60, "roughness_base": 0.22,
			"occlusion": 0.45, "brightness": 1.45, "vein_amount": 0.10},
}

@export_file("*.json") var meta_path := ""
@export var build_on_ready := true
@export var spawn_encounters := true

var meta: Dictionary = {}
var chambers: Dictionary = {}
var _missing_assets: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _props := PropLibrary.new()
var _variant := 0


func _ready() -> void:
	if build_on_ready and not meta_path.is_empty():
		build(meta_path)


func build(path: String) -> bool:
	meta_path = path
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.error("CaveInterior", "cannot read %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("CaveInterior", "bad meta %s" % path)
		return false
	meta = parsed
	chambers = meta.get("chambers", {})
	_rng.seed = int(meta.get("seed", 1))
	var dir := path.get_base_dir()
	var slug := path.get_file().trim_suffix(".meta.json")

	_build_shell(dir, slug)
	_build_collision(dir, slug)
	_build_water()
	_build_light_shafts()
	_build_chamber_lighting()
	_build_features()
	if spawn_encounters:
		_build_encounters()
	_build_boss_arenas()
	Log.info("CaveInterior", "%s built: %d chambers, %d tris" % [meta.get("name", slug), chambers.size(), int(meta.get("tris", 0))])
	return true


func _build_shell(dir: String, slug: String) -> void:
	var glb := "%s/%s.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		Log.error("CaveInterior", "shell mesh missing: %s" % glb)
		return
	var scene: PackedScene = load(glb)
	var root := scene.instantiate()
	root.name = "Shell"
	add_child(root)
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	var palette: Array = meta.get("palette", [])
	# Each formation gets its own surface. Oroth work is vast regular ashlar; a mined
	# adit is blocky and dusty; a water cave is rounded; ice is smooth and bright.
	var tuned: Dictionary = ROCK_BY_FORMATION.get(str(meta.get("formed_by", "water")), ROCK_BY_FORMATION["water"])
	for key in tuned:
		mat.set_shader_parameter(key, tuned[key])
	var lowest := _lowest_floor()
	var wet := lowest
	for w in meta.get("water", []):
		wet = maxf(wet, float(w["level"]))
	mat.set_shader_parameter("wet_level", wet + 0.3)
	mat.set_shader_parameter("wet_fade", 2.2)
	if palette.size() > 3:
		mat.set_shader_parameter("damp_tint", Color.html(str(palette[3])))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = mat
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_collision(dir: String, slug: String) -> void:
	var glb := "%s/%s_col.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		glb = "%s/%s.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		return
	var inst := (load(glb) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1 | (1 << 9)   # world + camera blocker
	body.collision_mask = 0
	add_child(body)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		shape.transform = (mi as MeshInstance3D).transform
		body.add_child(shape)
	inst.queue_free()


func _build_water() -> void:
	var entries: Array = meta.get("water", [])
	if entries.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Water"
	add_child(holder)
	for w in entries:
		var centre: Array = w["centre"]
		var extent: Array = w["extent"]
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(extent[0]) * 2.0, float(extent[1]) * 2.0)
		pm.subdivide_width = 8
		pm.subdivide_depth = 8
		plane.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mat.set_shader_parameter("floor_y", float(centre[1]))
		mat.set_shader_parameter("depth_fade", maxf(float(w["level"]) - float(centre[1]), 0.4))
		mat.set_shader_parameter("wave_scale", 0.5)
		mat.set_shader_parameter("transparency", 0.6)
		plane.material_override = mat
		plane.position = Vector3(float(centre[0]), float(w["level"]), float(centre[2]))
		holder.add_child(plane)
		# Anything below the surface is a water volume: slows you, masks noise.
		var area := Area3D.new()
		area.collision_layer = 1 << 11
		area.collision_mask = 0
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var depth: float = maxf(float(w["level"]) - float(centre[1]), 0.5)
		box.size = Vector3(float(extent[0]) * 2.0, depth, float(extent[1]) * 2.0)
		col.shape = box
		col.position.y = -depth * 0.5
		area.add_child(col)
		area.position = plane.position
		area.add_to_group("water_volume")
		holder.add_child(area)


func _build_light_shafts() -> void:
	var shafts: Array = meta.get("light_shafts", [])
	if shafts.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "LightShafts"
	add_child(holder)
	for s in shafts:
		var pos: Array = s["pos"]
		var radius := float(s["radius"])
		var top := float(s["top"])
		var floor_y := float(pos[1])
		var ch: Dictionary = chambers.get(str(s["chamber"]), {})
		if ch.has("floor_y"):
			floor_y = float(ch["floor_y"])
		var at := Vector3(float(pos[0]), floor_y, float(pos[2]))

		# The light sits well above the opening so the shaft walls are not a metre from
		# the source: otherwise the rock beside the hole blows out to white.
		var height_above := 14.0
		var light := SpotLight3D.new()
		light.position = at + Vector3(0, minf(top - floor_y, 26.0) + height_above, 0)
		light.rotation_degrees = Vector3(-90, 0, 0)
		light.spot_range = maxf(top - floor_y, 8.0) + height_above + 20.0
		light.spot_angle = clampf(rad_to_deg(atan(radius * 2.4 / (maxf(top - floor_y, 4.0) + height_above))), 6.0, 30.0)
		light.spot_angle_attenuation = 0.8
		light.spot_attenuation = 0.6
		light.light_energy = 7.0
		light.light_color = Color(1.0, 0.95, 0.84)
		light.shadow_enabled = true
		light.light_specular = 0.25
		holder.add_child(light)

		# The visible shaft of light: an additive cone that dissolves before the floor.
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var height: float = maxf(top - floor_y, 6.0)
		cm.top_radius = radius * 1.05
		cm.bottom_radius = radius * 2.6
		cm.height = height
		cm.radial_segments = 24
		cone.mesh = cm
		var gm := ShaderMaterial.new()
		gm.shader = SHAFT_SHADER
		gm.set_shader_parameter("intensity", 0.028)
		gm.set_shader_parameter("edge_softness", 0.55)
		gm.set_shader_parameter("bottom_fade", 0.72)
		gm.set_shader_parameter("shaft_color", Color(1.0, 0.95, 0.80))
		cone.material_override = gm
		cone.position = at + Vector3(0, height * 0.5, 0)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.sorting_offset = -2.0
		holder.add_child(cone)

		# The sky seen through the hole: a bright disc so the opening reads as daylight.
		var sky := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius * 1.05
		disc.bottom_radius = radius * 1.05
		disc.height = 0.05
		disc.radial_segments = 24
		sky.mesh = disc
		var skm := StandardMaterial3D.new()
		skm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		skm.albedo_color = Color(0.78, 0.83, 0.92)
		skm.emission_enabled = true
		skm.emission = Color(1.0, 0.97, 0.88)
		skm.emission_energy_multiplier = 0.5
		skm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sky.material_override = skm
		sky.position = at + Vector3(0, height - 0.1, 0)
		sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(sky)

		# Dust turning in the light is what sells a shaft.
		var dust := CPUParticles3D.new()
		dust.amount = 90
		dust.lifetime = 9.0
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(radius * 1.6, height * 0.45, radius * 1.6)
		dust.direction = Vector3(0.2, -1, 0.1)
		dust.spread = 25.0
		dust.gravity = Vector3(0.05, -0.12, 0.03)
		dust.initial_velocity_min = 0.02
		dust.initial_velocity_max = 0.14
		var qm := QuadMesh.new()
		qm.size = Vector2(0.035, 0.035)
		dust.mesh = qm
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		dmat.albedo_color = Color(1.0, 0.94, 0.8, 0.5)
		dust.material_override = dmat
		dust.position = at + Vector3(0, height * 0.45, 0)
		holder.add_child(dust)


## Chambers that no daylight reaches still need to be readable. Roles decide what lights
## them: a camp has a fire, a crypt has a guttering brazier, a boss arena has a cold glow.
func _build_chamber_lighting() -> void:
	var lit := {}
	for s in meta.get("light_shafts", []):
		lit[str(s["chamber"])] = true
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)
	for id in chambers:
		var ch: Dictionary = chambers[id]
		var role := str(ch.get("role", "chamber"))
		if lit.has(id) and role != "boss":
			continue
		var centre := _vec(ch["centre"])
		var radii := _vec(ch["radii"])
		var recipe := _light_recipe(role)
		# A cathedral needs more than a cottage's lamp: light count, reach and strength all
		# follow the room, or the far wall of a big chamber is simply not there.
		var spread: float = maxf(radii.x, radii.z)
		var count: int = clampi(int(spread / 3.5) + 1, 2, 8)
		for i in count:
			var at := centre
			if count > 1:
				var ang := TAU * float(i) / float(count) + _rng.randf()
				at += Vector3(cos(ang), 0, sin(ang)) * radii.x * 0.55
				at = _nearest_floor(ch, at)
			var lamp := OmniLight3D.new()
			lamp.position = at + Vector3(0, minf(radii.y * 0.5, 2.4), 0)
			lamp.light_color = recipe["color"]
			lamp.light_energy = float(recipe["energy"]) * (1.0 + clampf(spread / 24.0, 0.0, 1.2))
			lamp.omni_range = maxf(float(recipe["range"]), radii.length() * 1.05)
			lamp.shadow_enabled = bool(recipe["shadow"]) and i == 0
			lamp.light_specular = 0.3
			lamp.set_meta("flicker", float(recipe["flicker"]))
			lamp.set_meta("base_energy", float(recipe["energy"]))
			holder.add_child(lamp)
			if i == 0:
				# A cold, weak fill: rock is never truly lightless in a place people
				# have lit for centuries, and the player must read the room's shape.
				var fill := OmniLight3D.new()
				fill.position = centre + Vector3(0, radii.y * 0.7, 0)
				fill.light_color = Color(0.58, 0.64, 0.78)
				fill.light_energy = 0.9 + clampf(spread / 16.0, 0.0, 1.4)
				fill.omni_range = radii.length() * 2.6
				fill.shadow_enabled = false
				fill.light_specular = 0.0
				holder.add_child(fill)
			if i == 0 and radii.y > 6.0:
				# A big chamber needs something up in the roof, or the vault above the
				# lamps is simply missing and the room reads as a lit floor in a void.
				var high := OmniLight3D.new()
				high.position = centre + Vector3(0, radii.y * 1.25, 0)
				high.light_color = (recipe["color"] as Color).lerp(Color(0.7, 0.78, 0.95), 0.55)
				high.light_energy = float(recipe["energy"]) * 0.7 * (1.0 + clampf(spread / 20.0, 0.0, 1.0))
				high.omni_range = radii.length() * 2.0
				high.shadow_enabled = false
				high.light_specular = 0.1
				holder.add_child(high)
			if bool(recipe["ember"]):
				var ember := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.1
				sm.height = 0.2
				ember.mesh = sm
				var em := StandardMaterial3D.new()
				em.albedo_color = recipe["color"]
				em.emission_enabled = true
				em.emission = recipe["color"]
				em.emission_energy_multiplier = 1.8
				ember.material_override = em
				ember.position = lamp.position - Vector3(0, 0.25, 0)
				holder.add_child(ember)


func _light_recipe(role: String) -> Dictionary:
	match role:
		"entrance":
			return {"color": Color(0.85, 0.92, 1.0), "energy": 1.8, "range": 20.0, "flicker": 0.0, "shadow": false, "ember": false}
		"camp":
			return {"color": Color(1.0, 0.62, 0.28), "energy": 4.0, "range": 18.0, "flicker": 0.35, "shadow": true, "ember": true}
		"boss":
			return {"color": Color(0.55, 0.72, 1.0), "energy": 3.2, "range": 26.0, "flicker": 0.08, "shadow": true, "ember": true}
		"treasure":
			return {"color": Color(1.0, 0.82, 0.45), "energy": 1.9, "range": 14.0, "flicker": 0.15, "shadow": false, "ember": true}
		"shrine":
			return {"color": Color(1.0, 0.72, 0.4), "energy": 1.5, "range": 15.0, "flicker": 0.2, "shadow": true, "ember": true}
		"flooded", "pool":
			return {"color": Color(0.5, 0.8, 0.82), "energy": 1.5, "range": 15.0, "flicker": 0.05, "shadow": false, "ember": false}
		"passage":
			return {"color": Color(1.0, 0.7, 0.4), "energy": 1.8, "range": 12.0, "flicker": 0.25, "shadow": false, "ember": true}
		"deep", "chamber":
			return {"color": Color(1.0, 0.68, 0.36), "energy": 3.2, "range": 18.0, "flicker": 0.28, "shadow": false, "ember": true}
		_:
			return {"color": Color(1.0, 0.68, 0.36), "energy": 3.2, "range": 18.0, "flicker": 0.28, "shadow": false, "ember": true}


func _build_features() -> void:
	var holder := Node3D.new()
	holder.name = "Features"
	add_child(holder)
	for f in meta.get("features", []):
		var kind := str(f.get("kind", "prop"))
		var at := _feature_position(f)
		match kind:
			"hearthstone":
				var hs := HEARTHSTONE.instantiate()
				hs.hearthstone_id = str(f.get("id", "%s_hearth" % meta.get("id", "")))
				hs.display_name = str(f.get("name", "Hearthstone"))
				hs.place_id = str(f.get("place", ""))
				hs.position = at
				hs.rotation.y = deg_to_rad(float(f.get("yaw", 0.0)))
				holder.add_child(hs)
			"exit":
				var d := DOOR.instantiate()
				d.is_exit = true
				d.display_name = str(f.get("name", "the way out"))
				d.position = at
				d.rotation.y = deg_to_rad(float(f.get("yaw", 0.0)))
				holder.add_child(d)
			"door":
				var d2 := DOOR.instantiate()
				d2.interior_id = str(f.get("interior", ""))
				d2.display_name = str(f.get("name", "Door"))
				d2.position = at
				d2.rotation.y = deg_to_rad(float(f.get("yaw", 0.0)))
				holder.add_child(d2)
			"marker":
				var m := Marker3D.new()
				m.name = str(f.get("name", "Marker"))
				m.position = at
				holder.add_child(m)
			_:
				var node := _instance_asset(str(f.get("asset", "")), at, float(f.get("yaw", 0.0)), float(f.get("scale", 1.0)))
				if node:
					if f.has("note"):
						node.set_meta("note", f["note"])
					if f.has("item"):
						node.set_meta("item", f["item"])
					holder.add_child(node)


func _build_encounters() -> void:
	var holder := Node3D.new()
	holder.name = "Encounters"
	add_child(holder)
	for e in meta.get("encounters", []):
		var ch_id := str(e.get("chamber", ""))
		if not chambers.has(ch_id):
			continue
		var ch: Dictionary = chambers[ch_id]
		var spots: Array = e.get("spots", [])
		var count := int(e.get("count", spots.size() if spots.size() > 0 else 1))
		for i in count:
			var at: Vector3
			if i < spots.size():
				at = _vec(spots[i])
			else:
				at = _random_floor(ch)
			var marker := Marker3D.new()
			marker.name = "Spawn_%s_%d" % [Ids.name_of(str(e.get("enemy", "core:enemy/unknown"))), i]
			marker.position = at
			marker.rotation.y = deg_to_rad(float(e.get("yaw", 0.0)) if i == 0 else _rng.randf() * 360.0)
			marker.set_meta("enemy", str(e.get("enemy", "")))
			marker.set_meta("group", str(e.get("group", ch_id)))
			marker.set_meta("role", str(e.get("role", "")))
			marker.set_meta("ambush", bool(e.get("ambush", false)))
			marker.add_to_group("enemy_spawn")
			holder.add_child(marker)


## DESIGN 5.4 promises a boss "a fog gate, a name card, a bespoke arena scene, a unique drop".
## `boss_arena.tscn` has been in the project from the beginning and nothing anywhere instantiated
## it, so every fight improvised an unbounded bound around wherever the boss happened to wake --
## no threshold, no gate, nothing to tell a player the fight had begun and nothing to stop them
## strolling back up the tunnel mid-swing. The forge already knows everything the arena needs:
## the chamber it gave the role "boss" is the floor, and `beats` (the order the place is walked)
## and `links` (what joins what) between them say which tunnel is the way in.
##
## Only a chamber with a *boss* in it gets one. Three of the nine deep places have a boss-role
## chamber holding elites or a swarm instead, and a fog gate across a room full of hedge-wights
## would be a promise the fight does not keep.
func _build_boss_arenas() -> void:
	var order := {}
	var beats: Array = meta.get("beats", [])
	for i in beats.size():
		order[str((beats[i] as Dictionary).get("id", ""))] = i
	for raw in meta.get("encounters", []):
		var e: Dictionary = raw
		if str(e.get("role", "")) != "boss":
			continue
		var ch_id := str(e.get("chamber", ""))
		var boss_id := str(e.get("enemy", ""))
		if not chambers.has(ch_id) or boss_id.is_empty():
			continue
		var approach := _approach_chamber(ch_id, order)
		if approach.is_empty():
			Log.warn("CaveInterior", "%s has no way into it, so no fog gate" % ch_id)
			continue
		var ch: Dictionary = chambers[ch_id]
		var centre := _vec(ch["centre"])
		var radii := _vec(ch["radii"])
		var toward := _vec((chambers[approach] as Dictionary)["centre"]) - centre
		toward.y = 0.0
		if toward.length() < 0.01:
			continue
		toward = toward.normalized()
		var arena := BOSS_ARENA.instantiate() as BossArena
		arena.name = "BossArena_" + ch_id
		arena.boss_id = boss_id
		arena.centre = centre
		# The chamber is an ellipsoid; the larger of its two ground radii is the circle that
		# holds all of it, so nothing standing in the room is standing outside the fight.
		arena.radius = maxf(radii.x, radii.z)
		arena.min_radius = minf(BossArena.MIN_RADIUS, arena.radius)
		arena.position = Vector3(0.0, float(ch.get("floor_y", centre.y)), 0.0) \
				+ Vector3(centre.x, 0.0, centre.z) + toward * _edge_along(radii, toward)
		# The gate is a plane across the tunnel: its thin axis lies along the way in.
		arena.rotation.y = atan2(toward.x, toward.z)
		add_child(arena)


## The chamber a player comes *from* to reach this one: of everything joined to it, the one
## the authored walk-through reaches first. A boss chamber has two tunnels -- the approach and
## the way out to the shortcut -- and the gate belongs on the approach.
func _approach_chamber(ch_id: String, order: Dictionary) -> String:
	var mine := int(order.get(ch_id, 1 << 20))
	var best := ""
	var best_order := 1 << 20
	for raw in meta.get("links", []):
		var link: Array = raw
		if link.size() < 2:
			continue
		var other := ""
		if str(link[0]) == ch_id:
			other = str(link[1])
		elif str(link[1]) == ch_id:
			other = str(link[0])
		if other.is_empty() or not chambers.has(other):
			continue
		var theirs := int(order.get(other, 1 << 20))
		if theirs < mine and theirs < best_order:
			best = other
			best_order = theirs
	return best


## How far the chamber's wall is from its centre in this direction, for an ellipse with these
## ground radii. A gate placed at a flat `radius` would hang in the rock on the long axis.
static func _edge_along(radii: Vector3, direction: Vector3) -> float:
	var rx := maxf(radii.x, 0.5)
	var rz := maxf(radii.z, 0.5)
	var k := pow(direction.x / rx, 2.0) + pow(direction.z / rz, 2.0)
	return 1.0 / sqrt(k) if k > 0.0 else rx


func _instance_asset(path: String, at: Vector3, yaw: float, scale: float) -> Node3D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		# Ask the forge's library for this region's version of the kind first.
		_variant += 1
		var kind := path.get_base_dir().get_file()
		var found := _props.resolve(kind, _region_id(), _variant)
		if not found.is_empty():
			var real := (load(found) as PackedScene).instantiate() as Node3D
			real.position = at
			real.rotation.y = deg_to_rad(yaw)
			real.scale = Vector3.ONE * scale
			return real
		if not _missing_assets.has(path):
			_missing_assets[path] = true
			Log.warn("CaveInterior", "asset not built yet, using a placeholder: %s" % path)
		var ph := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 0.6) * scale
		ph.mesh = bm
		ph.position = at + Vector3(0, 0.3 * scale, 0)
		ph.rotation.y = deg_to_rad(yaw)
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.8, 0.2, 0.6)
		ph.material_override = pm
		return ph
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = deg_to_rad(yaw)
	node.scale = Vector3.ONE * scale
	return node


func _feature_position(f: Dictionary) -> Vector3:
	if f.has("at"):
		return _vec(f["at"])
	var ch_id := str(f.get("chamber", ""))
	if chambers.has(ch_id):
		var ch: Dictionary = chambers[ch_id]
		if f.has("anchor"):
			var pts: Array = ch.get("floor_points", [])
			if pts.size() > 0:
				return _vec(pts[int(f["anchor"]) % pts.size()])
		return _vec(ch["centre"])
	return Vector3.ZERO


func _random_floor(ch: Dictionary) -> Vector3:
	var pts: Array = ch.get("floor_points", [])
	if pts.is_empty():
		return _vec(ch["centre"])
	return _vec(pts[_rng.randi() % pts.size()])


func _nearest_floor(ch: Dictionary, near: Vector3) -> Vector3:
	var pts: Array = ch.get("floor_points", [])
	var best := _vec(ch["centre"])
	var best_d := INF
	for p in pts:
		var v := _vec(p)
		var d := v.distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = v
	return best


func _lowest_floor() -> float:
	var lowest := INF
	for id in chambers:
		lowest = minf(lowest, float(chambers[id].get("floor_y", INF)))
	return 0.0 if is_inf(lowest) else lowest


func _region_id() -> String:
	var place := str(meta.get("place", ""))
	if not place.is_empty() and ContentDB.has(place):
		return str(ContentDB.get_def(place).get("region", ""))
	return ""


static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _process(delta: float) -> void:
	var lights := get_node_or_null("Lights")
	if lights == null:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	for child in lights.get_children():
		if child is OmniLight3D and child.has_meta("flicker"):
			var amount: float = child.get_meta("flicker")
			if amount <= 0.0:
				continue
			var base: float = child.get_meta("base_energy")
			var seed_offset := float(child.get_index()) * 1.7
			var f := sin(t * 7.3 + seed_offset) * 0.5 + sin(t * 13.1 + seed_offset * 2.1) * 0.3 + sin(t * 3.1 + seed_offset) * 0.2
			(child as OmniLight3D).light_energy = base * (1.0 + f * amount * 0.5)
