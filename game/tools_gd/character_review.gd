extends Node3D
## Headless review renders for the character forge.
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy res://tools_gd/character_review.tscn -- \
##       --out=captures/characters [--mode=lineup|strips|both] [--clips=Walk,Attack_1H_Heavy]
##
## `lineup` renders every preset in tools/forge/characters.json side by side; `strips`
## renders each named clip at eight times from three angles and stitches a contact sheet.
## Both write PNGs plus `contact_sheet.png` into the output folder. `children` stands two
## children between two grown people, standing and mid-stride, from the front and the side;
## `--no-child-rig` shows them as they were before the child had a skeleton of its own.
## `--looks=<file.json>` stands the appearances listed in that file in a row and photographs
## the row from the front, three-quarter, side and back (`--pose=Walk@0.5` holds a clip at a time);
## `--frame=head` closes in on the heads, `--frame=hands` on the hands (two looks to a row),
## `--frame=face` on each look's head and shoulders alone, one image a look (face_<i>_<view>.png),
## `--frame=close` on each look's face alone, filling the frame (close_<i>_<view>.png), and
## `--frame=twoshot` stands the first two looks a pace apart talking, photographed as a player sees
## a conversation, from three places (twoshot_<place>.png).

const MODEL_SCENE := preload("res://actors/shared/humanoid_model.tscn")
const PRESETS_PATH := "res://../tools/forge/characters.json"
const STRIP_TIMES := 8
## The model faces -Z once its holder is rotated (CONTRACTS.md §1), so "front" sits at -Z.
const STRIP_ANGLES := {"side": Vector3(3.6, 1.05, 0.0), "front": Vector3(0.0, 1.05, -3.6), "iso": Vector3(-2.5, 1.45, -2.5)}

var out_dir := "captures/characters"
var mode := "both"
var clip_list: PackedStringArray = PackedStringArray([
	"Idle", "Walk", "Run", "Attack_1H_Light_1", "Attack_1H_Heavy", "Attack_2H_Heavy",
	"Dodge_F", "Block_Hit", "Parry", "Hit_Heavy", "Stagger", "Death_A", "Bow_Draw", "Work_Chop",
])
var preset_filter: PackedStringArray = PackedStringArray()
var looks_path := ""
var looks_pose := "Idle"
var looks_time := -1.0          ## `--pose=Walk@0.5`: the time to hold the clip at
var looks_frame := "figure"
## `--grip=R,L`: the hands closed (HumanoidModel.set_grip); `--haft`: a stand-in haft in each one,
## 3 cm across and 60 cm long on the weapon socket's +Y, to see the fist round what it holds
var looks_grip: PackedStringArray = PackedStringArray()
var looks_haft := false

var _camera: Camera3D
var _jobs: Array[Dictionary] = []
var _job := 0
var _warmup := 0
var _written: Array[String] = []
var _models: Array[HumanoidModel] = []
var _preset_ids: Array[String] = []


func _ready() -> void:
	_parse_args()
	_build_environment()
	if mode == "lineup" or mode == "both":
		_queue_lineup()
	if mode == "strips" or mode == "both":
		_queue_strips()
	if mode == "children":
		_queue_children()
	if mode == "looks":
		_queue_looks()
	if _jobs.is_empty():
		print("REVIEW: nothing to do")
		get_tree().quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--clips="):
			clip_list = a.substr(8).split(",", false)
		elif a.begins_with("--presets="):
			preset_filter = a.substr(10).split(",", false)
		elif a == "--no-child-rig":
			HumanoidModel.child_rig = false
		elif a.begins_with("--looks="):
			looks_path = a.substr(8)
			mode = "looks"
		elif a.begins_with("--pose="):
			looks_pose = a.substr(7)
			if looks_pose.contains("@"):
				looks_time = float(looks_pose.get_slice("@", 1))
				looks_pose = looks_pose.get_slice("@", 0)
		elif a.begins_with("--frame="):
			looks_frame = a.substr(8)
		elif a.begins_with("--grip="):
			looks_grip = a.substr(7).split(",", false)
		elif a == "--haft":
			looks_haft = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../%s" % out_dir) if not out_dir.begins_with("/") else out_dir)


func _abs_out() -> String:
	if out_dir.begins_with("/"):
		return out_dir
	return ProjectSettings.globalize_path("res://../%s" % out_dir)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.52, 0.76)
	mat.sky_horizon_color = Color(0.86, 0.84, 0.78)
	mat.ground_bottom_color = Color(0.22, 0.21, 0.18)
	mat.ground_horizon_color = Color(0.72, 0.68, 0.62)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# without a raised white point the mid-greys clip on this renderer (ARCHITECTURE.md §10)
	env.tonemap_white = 6.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 38, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.95, 0.87)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.78, 0.84, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.42, 0.33)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)


func _load_presets() -> Array:
	var path := ProjectSettings.globalize_path("res://../tools/forge/characters.json")
	if not FileAccess.file_exists(path):
		push_warning("character_review: no presets at %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for key in (parsed as Dictionary).get("presets", {}):
		if preset_filter.size() > 0 and not (key in preset_filter):
			continue
		out.append({"id": key, "appearance": (parsed["presets"] as Dictionary)[key]})
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out


func _spawn(appearance: Dictionary, pos: Vector3) -> HumanoidModel:
	# a look that names its people and not its colours is dressed in the people's colours, as
	# every villager is; without it the cloth renders in the bake's own white
	if appearance.has("culture") and not appearance.has("palette"):
		appearance = appearance.duplicate(true)
		var pal := {}
		var cp := CharacterAppearance.culture_palette(str(appearance["culture"]))
		for k in cp:
			pal[k] = (cp[k] as Color).to_html(false)
		appearance["palette"] = pal
	var holder := Node3D.new()
	holder.position = pos
	# CONTRACTS §1: actor scenes rotate the model 180 degrees so gameplay forward is -Z
	holder.rotation_degrees = Vector3(0, 180, 0)
	add_child(holder)
	var m := MODEL_SCENE.instantiate() as HumanoidModel
	holder.add_child(m)
	m.build()
	if not appearance.is_empty():
		m.apply_appearance(appearance)
	_models.append(m)
	return m


## `--grip` and `--haft`: the hands asked for closed, each round a stand-in haft if asked.
func _close_hands(m: HumanoidModel) -> void:
	for side in looks_grip:
		m.set_grip(side, 1.0, true)
		if not looks_haft:
			continue
		var haft := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.015
		cyl.bottom_radius = 0.015
		cyl.height = 0.6
		haft.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.22, 0.12)
		haft.material_override = mat
		# a CylinderMesh stands along its own +Y, which is the socket's grip axis, and the fist
		# closes round it where HumanoidModel.grip_offset says
		m.attach_to_socket("Weapon" + side, haft)
		haft.position = HumanoidModel.grip_offset(side)


## Holds a model on one frame of a clip, so a lineup is not a row of A-posed mannequins.
func _hold_pose(m: HumanoidModel, clip: String, t: float) -> void:
	if not m.has_clip(clip):
		return
	# The model steps its own tree every frame (HumanoidModel._process advances it by hand), and
	# the tree's locomotion idle overwrote the held clip: every "mid-stride" lineup stood still.
	m.set_process(false)
	if m.anim_tree != null:
		m.anim_tree.active = false
	m.anim_player.play(clip)
	m.anim_player.seek(t, true)
	m.anim_player.advance(0.0)
	m.anim_player.pause()
	# with its process off the model does not set the hold a cloak puts on a walker's arms
	# (ArmRoom.hold), so the lineup sets it: what a player sees walking, not the clip's bare swing
	if m.arm_room != null:
		m.arm_room.hold = m.arm_hold_in(clip)


func _queue_lineup() -> void:
	var presets := _load_presets()
	if presets.is_empty():
		presets = [{"id": "default", "appearance": {}}]
	var per_row := 6
	var spacing := 1.15
	var rows: int = int(ceil(float(presets.size()) / per_row))
	var labels: Array[String] = []
	for i in presets.size():
		var row := i / per_row
		var col := i % per_row
		var n_in_row: int = mini(per_row, presets.size() - row * per_row)
		var x := (col - (n_in_row - 1) * 0.5) * spacing
		var z := -float(row) * 1.6
		var mm := _spawn(presets[i]["appearance"], Vector3(x, 0, z))
		_hold_pose(mm, "Idle", 0.7 + 0.31 * float(i))
		labels.append(str(presets[i]["id"]))
	for row in rows:
		var n_in_row: int = mini(per_row, presets.size() - row * per_row)
		var width := n_in_row * spacing
		_jobs.append({
			"file": "lineup_row%d.png" % row,
			"cam": Vector3(0, 1.02, -row * 1.6 - width * 1.25 - 0.9),
			"look": Vector3(0, 0.92, -row * 1.6),
			"fov": 36.0,
			"hide_rows": row,
		})
	_jobs.append({
		"file": "lineup_all.png",
		"cam": Vector3(0, 2.4, -per_row * spacing * 1.6),
		"look": Vector3(0, 0.9, -rows * 0.8),
		"fov": 42.0,
		"hide_rows": -1,
	})
	_preset_ids = labels


## A man, a boy of eight, a girl of ten and a woman, in the plain clothes of the Vale.
const FAMILY := [
	{"height": 1.78, "build": 0.5, "skin": "wheat", "hair_colour": "dark_brown", "culture": "vale",
		"parts": {"head": "default", "hair": "short", "torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"}},
	{"height": 1.27, "build": 0.4, "skin": "wheat", "hair_colour": "dark_brown", "culture": "vale",
		"parts": {"head": "round", "hair": "tousled", "torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"}},
	{"height": 1.38, "build": 0.4, "skin": "fair", "hair_colour": "chestnut", "feminine": 1.0, "culture": "vale",
		"parts": {"head": "soft", "hair": "braid", "torso": "dress", "feet": "shoes"}},
	{"height": 1.66, "build": 0.45, "skin": "fair", "hair_colour": "chestnut", "feminine": 1.0, "culture": "vale",
		"parts": {"head": "soft", "hair": "bun", "torso": "dress", "feet": "shoes", "belt": "belt"}},
]


func _queue_children() -> void:
	var spacing := 0.95
	# four rows far enough apart that none is behind another: standing and mid-stride, each
	# once facing the camera and once in profile
	var rows := [["idle", "front"], ["idle", "side"], ["walk", "front"], ["walk", "side"]]
	for r in rows.size():
		var x0 := r * 40.0
		for i in FAMILY.size():
			var x := x0 + (i - (FAMILY.size() - 1) * 0.5) * spacing
			var m := _spawn(FAMILY[i], Vector3(x, 0, 0))
			if rows[r][1] == "side":
				(m.get_parent() as Node3D).rotation_degrees = Vector3(0, 90, 0)
			if rows[r][0] == "idle":
				_hold_pose(m, "Idle", 0.8)
			else:
				_hold_pose(m, "Walk", 0.25 + 0.1 * i)
		_jobs.append({"file": "lineup_children_%s_%s.png" % rows[r], "cam": Vector3(x0, 1.0, -4.6),
			"look": Vector3(x0, 0.85, 0), "fov": 36.0, "hide_rows": -1})


func _queue_looks() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(looks_path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("character_review: %s is not a list of appearances" % looks_path)
		return
	var looks: Array = parsed
	if looks_frame == "twoshot":
		_queue_twoshot(looks)
		return
	var close := looks_frame == "close"
	var heads := looks_frame == "head"
	var hands := looks_frame == "hands"
	var faces := looks_frame == "face"
	# a face alone in its frame: its neighbours stand out of the shot
	var spacing := 1.4 if (faces or close) else (0.62 if heads else (0.55 if hands else 1.05))
	var views := {"front": 0.0, "three_quarter": -40.0, "side": -90.0, "back": 180.0}
	var r := 0
	for view in views:
		var x0 := r * 40.0
		for i in looks.size():
			var x := x0 + (i - (looks.size() - 1) * 0.5) * spacing
			var m := _spawn(looks[i], Vector3(x, 0, 0))
			(m.get_parent() as Node3D).rotation_degrees = Vector3(0, 180.0 + float(views[view]), 0)
			var t := looks_time if looks_time >= 0.0 else (0.8 if looks_pose == "Idle" else 0.3)
			_hold_pose(m, looks_pose, t)
			_close_hands(m)
		var width := looks.size() * spacing
		if close:
			for i in looks.size():
				var cx := x0 + (i - (looks.size() - 1) * 0.5) * spacing
				# the eyes stand at 0.928 of the height
				var eye := 0.928 * float((looks[i] as Dictionary).get("height", 1.78))
				_jobs.append({"file": "close_%d_%s.png" % [i, view],
					"cam": Vector3(cx, eye + 0.01, -0.48), "look": Vector3(cx, eye - 0.035, 0), "fov": 26.0, "hide_rows": -1})
		elif faces:
			for i in looks.size():
				var fx := x0 + (i - (looks.size() - 1) * 0.5) * spacing
				_jobs.append({"file": "face_%d_%s.png" % [i, view],
					"cam": Vector3(fx, 1.60, -1.05), "look": Vector3(fx, 1.56, 0), "fov": 30.0, "hide_rows": -1})
		elif heads:
			_jobs.append({"file": "lineup_looks_%s.png" % view,
				# wide enough for the row at 16:9 and a 30 degree field of view
				"cam": Vector3(x0, 1.62, -maxf(1.2, (width * 0.5 + 0.3) / 0.476)),
				"look": Vector3(x0, 1.58, 0), "fov": 30.0, "hide_rows": -1})
		elif hands:
			# from the elbow to the knee: the hands hanging at the sides, and how they meet the arm
			_jobs.append({"file": "lineup_looks_%s.png" % view,
				"cam": Vector3(x0, 0.98, -maxf(0.9, (width * 0.5 + 0.1) / 0.476)),
				"look": Vector3(x0, 0.92, 0), "fov": 30.0, "hide_rows": -1})
		else:
			_jobs.append({"file": "lineup_looks_%s.png" % view,
				"cam": Vector3(x0, 1.0, -maxf(3.4, width * 0.9 + 1.0)),
				"look": Vector3(x0, 0.9, 0), "fov": 36.0, "hide_rows": -1})
		r += 1


## Two people a pace apart, turned to each other, in the Idle: the distance a player stands at in a
## conversation, from beside the player's shoulder, from the side, and a little wider.
func _queue_twoshot(looks: Array) -> void:
	if looks.size() < 2:
		push_error("character_review: --frame=twoshot wants two looks")
		return
	var gap := 1.1
	for k in 2:
		var m := _spawn(looks[k], Vector3((k - 0.5) * gap, 0, 0))
		# the model faces -Z once its holder is turned 180; +-90 more turns them to each other
		(m.get_parent() as Node3D).rotation_degrees = Vector3(0, 180.0 + (90.0 if k == 0 else -90.0), 0)
		_hold_pose(m, "Idle", 0.8)
		_close_hands(m)
	var eye := 1.62
	_jobs.append({"file": "twoshot_over_shoulder.png", "cam": Vector3(-1.05, eye + 0.12, -1.25),
		"look": Vector3(0.45, eye - 0.08, 0.0), "fov": 40.0, "hide_rows": -1})
	_jobs.append({"file": "twoshot_side.png", "cam": Vector3(0.0, eye, -2.3),
		"look": Vector3(0.0, eye - 0.12, 0.0), "fov": 38.0, "hide_rows": -1})
	_jobs.append({"file": "twoshot_wide.png", "cam": Vector3(0.9, eye + 0.25, -3.6),
		"look": Vector3(0.0, 1.2, 0.0), "fov": 38.0, "hide_rows": -1})


func _queue_strips() -> void:
	var m := _spawn({}, Vector3(0, 0, 6.0))
	for clip in clip_list:
		if not m.has_clip(clip):
			push_warning("character_review: no clip %s" % clip)
			continue
		var length := m.clip_length(clip)
		for i in STRIP_TIMES:
			var t := length * float(i) / float(STRIP_TIMES if m._clip_data.get(clip, {}).get("loop", false) else STRIP_TIMES - 1)
			for angle_name in STRIP_ANGLES:
				var off: Vector3 = STRIP_ANGLES[angle_name]
				_jobs.append({
					"file": "clip_%s_%s_%02d.png" % [clip, angle_name, i],
					"cam": Vector3(0, 0, 6.0) + off,
					"look": Vector3(0, 0.95, 6.0),
					"fov": 34.0,
					"clip": clip, "time": t, "model": m,
				})


## Shows only the lineup row being photographed (or all of them when row < 0).
func _only_row(row: int) -> void:
	var per_row := 6
	for i in _models.size():
		var holder := _models[i].get_parent() as Node3D
		if holder == null:
			continue
		holder.visible = row < 0 or (i / per_row) == row


func _process(_delta: float) -> void:
	if _job >= _jobs.size():
		return
	var job: Dictionary = _jobs[_job]
	if _warmup == 0:
		_camera.position = job["cam"]
		_camera.look_at(job["look"])
		_camera.fov = float(job.get("fov", 38.0))
		if job.has("hide_rows"):
			_only_row(int(job["hide_rows"]))
		if job.has("clip"):
			var m: HumanoidModel = job["model"]
			_pose_at(m, str(job["clip"]), float(job["time"]))
	_warmup += 1
	if _warmup < 3:
		return
	_warmup = 0
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [_abs_out(), str(job["file"])]
	img.save_png(path)
	_written.append(str(job["file"]))
	_job += 1
	if _job >= _jobs.size():
		_finish()


## Poses the model at one instant of a clip without running the AnimationTree.
func _pose_at(m: HumanoidModel, clip: String, t: float) -> void:
	if m.anim_tree != null:
		m.anim_tree.active = false
	m.anim_player.play(clip)
	m.anim_player.seek(t, true)
	m.anim_player.advance(0.0)
	m.anim_player.pause()


func _finish() -> void:
	_contact_sheet()
	print("REVIEW: wrote %d images to %s" % [_written.size(), _abs_out()])
	get_tree().quit(0)


## Stitches every clip strip into one sheet per clip, then an index sheet of the lineups.
func _contact_sheet() -> void:
	var by_clip := {}
	for f in _written:
		if not f.begins_with("clip_"):
			continue
		var rest := f.substr(5).trim_suffix(".png")
		var parts := rest.rsplit("_", true, 2)
		if parts.size() < 3:
			continue
		var clip: String = parts[0]
		if not by_clip.has(clip):
			by_clip[clip] = []
		by_clip[clip].append(f)
	for clip in by_clip:
		var files: Array = by_clip[clip]
		files.sort()
		var angles := STRIP_ANGLES.keys()
		var cols := STRIP_TIMES
		var rows := angles.size()
		var cell := 260
		var sheet := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.95, 0.94, 0.91))
		for f in files:
			var img := Image.load_from_file("%s/%s" % [_abs_out(), f])
			if img == null:
				continue
			img.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
			# blit_rect needs matching formats, and the viewport gives RGBA8
			img.convert(Image.FORMAT_RGB8)
			var rest: String = (f as String).substr(5).trim_suffix(".png")
			var idx := int(rest.rsplit("_", true, 1)[1])
			var angle := rest.trim_prefix(clip + "_").rsplit("_", true, 1)[0]
			var row := angles.find(angle)
			if row < 0:
				continue
			sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(idx * cell, row * cell))
		sheet.save_png("%s/sheet_%s.png" % [_abs_out(), clip])
	var lineups: Array[String] = []
	for f in _written:
		if f.begins_with("lineup_"):
			lineups.append(f)
	if lineups.is_empty():
		return
	lineups.sort()
	var imgs: Array[Image] = []
	for f in lineups:
		var im := Image.load_from_file("%s/%s" % [_abs_out(), f])
		if im != null:
			imgs.append(im)
	if imgs.is_empty():
		return
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var sheet2 := Image.create(w, h * imgs.size(), false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		im.convert(Image.FORMAT_RGB8)
		sheet2.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(0, i * h))
	sheet2.save_png("%s/contact_sheet.png" % _abs_out())
