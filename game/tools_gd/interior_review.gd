extends Node3D
## Renders built interiors from several viewpoints so each can be judged as a place.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --audio-driver Dummy \
##     res://tools_gd/interior_review.tscn -- --meta=<abs meta.json>[,<meta>...] --out=<abs dir>
##
## Per interior: the view from the Entrance marker (what a body coming through the door sees);
## each room or chamber from a corner looking across it and, for a house, from the opposite corner
## looking back; and for a house a plan per storey, seen straight down through a camera standing
## just under the ceiling (everything above it is behind the camera, so the walls read as a cut
## section and every piece of furniture shows where it stands).
##
## `--metas=all` takes every interior def with a meta. `--only=<slug>,...` narrows it.
##
## A house is lit as the game lights it: the game's own Atmosphere, indoors, in the region the
## house stands in, at `--hour=` (21 by default: the inn at night), with the door shot also taken
## at noon. A deep place keeps the reviewer's lantern, since a player carries light down there.
##
## Run on Forward+ (the default), NOT --rendering-driver opengl3: Compatibility caps omni
## lights per object and silently drops the rest, which makes a lit room look unlit.

var cave: Node3D          # CaveInterior or HouseInterior
var is_house := false
var cam: Camera3D
var shots: Array = []
var frames := 0
var out_dir := "user://interiors"
var label := "interior"
var queue: Array[String] = []
var _env: Environment
var _sun: DirectionalLight3D
var _lantern: OmniLight3D
var _shot := -1
var _atmos: Node = null
var hour := 21.0


func _ready() -> void:
	var metas := ""
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--meta="):
			metas = a.substr(7)
		elif a.begins_with("--metas="):
			metas = a.substr(8)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--label="):
			label = a.substr(8)
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(",", false))
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if metas == "all":
		for def in ContentDB.all("interior"):
			var p := str(def.get("meta", ""))
			if p.is_empty() or not FileAccess.file_exists(p):
				continue
			queue.append(p)
	else:
		for m in metas.split(",", false):
			queue.append(m)
	if not only.is_empty():
		queue = queue.filter(func(p: String) -> bool: return only.has(p.get_file().trim_suffix(".meta.json")))
	queue.sort()
	var we := WorldEnvironment.new()
	_env = Environment.new()
	we.environment = _env
	add_child(we)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	add_child(cam)
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color(1.0, 0.78, 0.5)
	_lantern.light_energy = 2.0
	_lantern.omni_range = 16.0
	_lantern.shadow_enabled = true
	cam.add_child(_lantern)
	_lantern.position = Vector3(0.3, 0.1, -0.2)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-38, 35, 0)
	_sun.light_energy = 0.35
	_sun.light_color = Color(0.95, 0.96, 1.0)
	_sun.shadow_enabled = false
	add_child(_sun)
	var packed := load("res://systems/atmosphere/atmosphere.tscn") as PackedScene
	if packed != null:
		_atmos = packed.instantiate()
		add_child(_atmos)
	cam.current = true
	if not _next_interior():
		get_tree().quit(2)


## Builds the next interior in the queue and plans its shots; false when there is none left.
func _next_interior() -> bool:
	if cave != null:
		cave.queue_free()
		cave = null
	while not queue.is_empty():
		var meta_path: String = queue.pop_front()
		var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(probe) != TYPE_DICTIONARY:
			printerr("interior review: cannot read %s" % meta_path)
			continue
		is_house = str((probe as Dictionary).get("generator", "")) == "house_forge"
		_environment()
		if is_house:
			cave = HouseInterior.new()
		else:
			cave = CaveInterior.new()
		cave.build_on_ready = false
		add_child(cave)
		if not cave.build(meta_path):
			printerr("interior review: %s did not build" % meta_path)
			continue
		label = meta_path.get_file().trim_suffix(".meta.json")
		shots = []
		_plan_shots()
		_shot = -1
		frames = 0
		print("interior review: %s, %d shots" % [label, shots.size()])
		return true
	return false


func _environment() -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.015, 0.014, 0.018)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.52, 0.56, 0.64) if is_house else Color(0.36, 0.44, 0.60)
	_env.ambient_light_energy = 0.75 if is_house else 0.85
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# A white point set for open daylight maps a lit interior wall to a sixth of its
	# value. Indoors the brightest thing in the room is a lamp, not the sun.
	_env.tonemap_white = 2.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = Color(0.14, 0.16, 0.22)
	_env.fog_density = 0.0 if is_house else 0.008
	_env.glow_enabled = true
	_env.glow_intensity = 0.5
	_env.glow_bloom = 0.12
	_env.glow_hdr_threshold = 1.25
	# A house is lit by its own fires and windows under the game's own sky; a deep place by the
	# lantern a player carries.
	_sun.visible = false
	_lantern.visible = not is_house
	if _atmos != null:
		var we := get_children().filter(func(n: Node) -> bool: return n is WorldEnvironment and n.get_parent() == self)
		for w in we:
			(w as WorldEnvironment).environment = null if is_house else _env
		_atmos.set_process(is_house)
		if is_house:
			_atmos.call("set_region", _region_of(), true)
			_atmos.call("set_interior", true)
			WorldClock.time_hours = hour
			_atmos.call("settle")


## The region a house stands in, by its place; Hearthvale when the place says nothing.
func _region_of() -> String:
	var place := str(cave.meta.get("place", ""))
	if ContentDB.has(place):
		var r := str(ContentDB.get_def(place).get("region", ""))
		if r != "":
			return r
	return "core:region/hearthvale"


func _plan_shots() -> void:
	# Through the door: where Interiors.enter stands a body, at eye height, the way it faces.
	var entrance := cave.get_node_or_null("Entrance") as Node3D
	if entrance != null:
		var fwd := -entrance.transform.basis.z
		var eye := entrance.position + Vector3(0, 1.62, 0)
		shots.append({"label": "%s_00_door" % label, "pos": eye - fwd * 0.6, "look": eye + fwd * 4.0 + Vector3(0, -0.45, 0), "fov": 78})
		if is_house:
			shots.append({"label": "%s_00_door_noon" % label, "pos": eye - fwd * 0.6, "look": eye + fwd * 4.0 + Vector3(0, -0.45, 0),
					"fov": 78, "hour": 13.0})
	var spaces: Dictionary = cave.rooms if is_house else cave.chambers
	var ids: Array = spaces.keys()
	ids.sort()
	for id in ids:
		var ch: Dictionary = spaces[id]
		var centre: Vector3
		var radii: Vector3
		if is_house:
			centre = Vector3(float(ch["x"]) + float(ch["w"]) * 0.5, float(ch["floor_y"]), float(ch["z"]) + float(ch["d"]) * 0.5)
			radii = Vector3(float(ch["w"]) * 0.5, 1.4, float(ch["d"]) * 0.5)
		else:
			centre = CaveInterior._vec(ch["centre"])
			radii = CaveInterior._vec(ch["radii"])
		# Stand in a corner and look across the space, the way someone walking in sees it.
		var stand := centre
		if is_house:
			stand = centre + Vector3(-radii.x * 0.72, 0, -radii.z * 0.72)
			var back := centre + Vector3(radii.x * 0.72, 0, radii.z * 0.72)
			shots.append({"label": "%s_%s_b" % [label, id], "pos": back + Vector3(0, 1.62, 0),
					"look": Vector3(centre.x, back.y + 1.0, centre.z), "fov": 78})
		else:
			var pts: Array = ch.get("floor_points", [])
			var best := -1.0
			for p in pts:
				var v: Vector3 = CaveInterior._vec(p)
				var dd := Vector2(v.x - centre.x, v.z - centre.z).length()
				if dd > best and dd < maxf(radii.x, radii.z) * 0.55:
					best = dd
					stand = v
			if best < 0.5:
				stand = centre + Vector3(radii.x * 0.6, 0, 0)
		shots.append({
			"label": "%s_%s" % [label, id],
			"pos": stand + Vector3(0, 1.62, 0),
			"look": Vector3(centre.x, stand.y + 1.15, centre.z),
			"fov": 78 if is_house else 75,
		})
	if not is_house:
		return
	# A plan of each storey, cut just under its ceiling.
	var storeys: Dictionary = {}
	for id2 in cave.rooms:
		var r: Dictionary = cave.rooms[id2]
		var y := float(r["floor_y"])
		var key := snappedf(y, 0.1)
		if not storeys.has(key):
			storeys[key] = [Vector3(1e9, y, 1e9), Vector3(-1e9, y, -1e9)]
		var lo: Vector3 = storeys[key][0]
		var hi: Vector3 = storeys[key][1]
		lo.x = minf(lo.x, float(r["x"]))
		lo.z = minf(lo.z, float(r["z"]))
		hi.x = maxf(hi.x, float(r["x"]) + float(r["w"]))
		hi.z = maxf(hi.z, float(r["z"]) + float(r["d"]))
		storeys[key] = [lo, hi]
	var keys := storeys.keys()
	keys.sort()
	for i in keys.size():
		var lo2: Vector3 = storeys[keys[i]][0]
		var hi2: Vector3 = storeys[keys[i]][1]
		var mid := (lo2 + hi2) * 0.5
		shots.append({"label": "%s_zz_plan%d" % [label, i], "pos": Vector3(mid.x, lo2.y + 2.3, mid.z),
				"look": Vector3(mid.x, lo2.y - 5.0, mid.z + 0.001), "ortho": maxf(hi2.x - lo2.x, (hi2.z - lo2.z) * 16.0 / 9.0) + 1.2,
				"hour": 13.0})


func _process(_d: float) -> void:
	frames += 1
	if cave == null:
		return
	# Ten frames per shot: pose the camera on the first, save on the tenth.
	if frames % 10 == 1:
		_shot += 1
		if _shot >= shots.size():
			if not _next_interior():
				print("errors=%d warnings=%d" % [Log.error_count, Log.warning_count])
				get_tree().quit(0)
			return
		var s: Dictionary = shots[_shot]
		if is_house and _atmos != null:
			WorldClock.time_hours = float(s.get("hour", hour))
			_atmos.call("settle")
		if s.has("ortho"):
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(s["ortho"]) * 9.0 / 16.0
			cam.near = 0.05
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = float(s.get("fov", 70))
		cam.position = s["pos"]
		cam.look_at(s["look"], Vector3.FORWARD if s.has("ortho") else Vector3.UP)
	elif frames % 10 == 0 and _shot >= 0 and _shot < shots.size():
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%s.png" % shots[_shot]["label"]))
		print("SAVED %s" % shots[_shot]["label"])
