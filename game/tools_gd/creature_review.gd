extends Node3D
## The creature review: a real foe (Enemy, its def, its forged body) on a plain lit floor, drawn
## from the side, the front and three-quarters, beside the PlaceholderBody box it replaces, and
## then frame by frame through its clips, for a contact sheet. It runs on either renderer.
##
##   xvfb-run -a -s '-screen 0 1280x720x24' godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 960x600 res://tools_gd/creature_review.tscn -- \
##       --foes=core:enemy/down_wolf,core:enemy/crag_wolf --out=<dir> [--clips=Attack_1,Death] [--frames=5] \
##       [--views=side,front,three_quarter,back,close] [--no-clips] [--lod=1]
##
## Writes <out>/<foe>_<view>.png, <out>/<foe>_box_side.png (the placeholder), and
## <out>/<foe>_<clip>_<n>.png for each clip at `frames` points from its start to its end, and one
## line per image to <out>/review.txt (the clip, the time, the body's height and the feet's lowest
## point, so a foot under the floor is a number as well as a picture).

const DEFAULT_CLIPS: Array[String] = ["Idle", "Idle_Combat", "Walk", "Trot", "Run", "Strafe_L", "Walk_Back",
	"Attack_1", "Attack_2", "Attack_3", "Attack_4", "Attack_5", "Cast_Quick", "Hit", "Stagger", "Knockdown",
	"Get_Up", "Death", "Crawl", "Crawl_Idle", "Crawl_Death"]

var out_dir := "captures/creatures"
var foes: Array[String] = []
var clips: Array[String] = []
var frames := 5
var views: Array[String] = ["side", "front", "three_quarter", "back"]
var with_clips := true
var lod := 0
var _cam: Camera3D
var _lines: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--foes="):
			for f in a.substr(7).split(",", false):
				foes.append(f)
		elif a.begins_with("--clips="):
			for c in a.substr(8).split(",", false):
				clips.append(c)
		elif a.begins_with("--frames="):
			frames = maxi(int(a.substr(9)), 1)
		elif a.begins_with("--views="):
			views.clear()
			for v in a.substr(8).split(",", false):
				views.append(v)
		elif a == "--no-clips":
			with_clips = false
		elif a.begins_with("--lod="):
			lod = int(a.substr(6))
	if clips.is_empty():
		clips = DEFAULT_CLIPS.duplicate()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_stage()
	await get_tree().process_frame
	for id in foes:
		await _review(id)
	var f := FileAccess.open(out_dir.path_join("review.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	print("CREATURES: %d images -> %s" % [_lines.size(), out_dir])
	get_tree().quit(0)


func _build_stage() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.36)
	mat.roughness = 0.95
	ground.material_override = mat
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 40.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.55, 0.72)
	sm.sky_horizon_color = Color(0.75, 0.78, 0.8)
	sm.ground_bottom_color = Color(0.3, 0.3, 0.28)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true


func _slug(id: String) -> String:
	return id.get_slice("/", id.get_slice_count("/") - 1)


func _review(id: String) -> void:
	var e := Enemy.new()
	e.configure(id)
	add_child(e)
	e.perception.enabled = false
	e.set_physics_process(false)
	e.brain.set_physics_process(false)
	e.brain.set_process(false)
	await get_tree().process_frame
	var model: CreatureModel = e.anim.model as CreatureModel if e.anim != null else null
	var slug := _slug(id)
	if model == null:
		_lines.append("%s: NO FORGED MODEL (placeholder %s)" % [slug, str(e.anim.placeholder != null)])
		e.queue_free()
		return
	if lod > 0:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var n := String(m.name).to_lower()
			m.visibility_range_begin = 0.0
			m.visibility_range_end = 0.0
			m.visible = n.ends_with("lod%d" % lod)
	var size := _extent(model)
	# the stills
	model.anim_player.play(model.resolve("Idle"))
	model.anim_player.seek(0.0, true)
	model.anim_player.pause()
	model.set_process(false)
	for v in views:
		_frame(e, v, size)
		await _shot("%s_%s" % [slug, v], "%s view %s" % [slug, v], model)
	# the box it replaces, standing beside
	var box := PlaceholderBody.build(e.body_kind, e.tint, e.body_scale, e.body_variant)
	box.position = Vector3(0.0, 0.0, maxf(size.z, 1.0) * 1.25)
	box.rotation.y = PI
	add_child(box)
	_frame(e, "pair", size)
	await _shot("%s_box_side" % slug, "%s beside its box" % slug, model)
	box.queue_free()
	if with_clips:
		for c in clips:
			var own := model.resolve(c)
			if own.is_empty() or own != c:
				continue
			var length := model.clip_length(c)
			for i in frames:
				var t := length * float(i) / float(maxi(frames - 1, 1))
				if bool((model.clip_data.get(c, {}) as Dictionary).get("loop", false)):
					t = length * float(i) / float(frames)
				model.anim_player.play(c)
				model.anim_player.seek(t, true)
				model.anim_player.pause()
				_frame(e, "clip", size)
				await _shot("%s_%s_%d" % [slug, c, i], "%s %s t=%.2f" % [slug, c, t], model)
	e.queue_free()
	await get_tree().process_frame


## The body's extent: x across, y up, z along (in the foe's own frame).
func _extent(model: Node3D) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).to_lower().contains("lod"):
			continue
		var bb := m.global_transform * m.get_aabb()
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
	if lo.x == INF:
		return Vector3(1, 1, 1)
	return hi - lo


func _frame(e: Node3D, view: String, size: Vector3) -> void:
	var reach := maxf(maxf(size.z, size.x), size.y)
	var at := e.global_position + Vector3(0.0, size.y * 0.45, 0.0)
	var fwd := -e.global_transform.basis.z
	var right := e.global_transform.basis.x
	var d := reach * (1.25 + 0.25 * clampf(size.y / maxf(size.z, 0.5) - 0.8, 0.0, 1.0)) + 0.4
	var eye: Vector3
	match view:
		"front":
			eye = at + fwd * d + Vector3.UP * size.y * 0.25
		"back":
			eye = at - fwd * d + Vector3.UP * size.y * 0.35
		"three_quarter":
			eye = at + (fwd * 0.75 + right * 0.75).normalized() * d + Vector3.UP * size.y * 0.5
		"close":
			at = e.global_position + fwd * size.z * 0.4 + Vector3(0.0, size.y * 0.7, 0.0)
			eye = at + (fwd * 0.5 + right).normalized() * reach * 0.8 + Vector3.UP * size.y * 0.1
		"pair":
			at = at - fwd * maxf(size.z, 1.0) * 0.62
			eye = at + right * d * 1.5 + Vector3.UP * size.y * 0.3
		"clip":
			eye = at + (right + fwd * 0.25).normalized() * d * 1.05 + Vector3.UP * size.y * 0.35
		_:
			eye = at + right * d + Vector3.UP * size.y * 0.2
	_cam.look_at_from_position(eye, at, Vector3.UP)


func _shot(name: String, label: String, model: CreatureModel) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	_lines.append("%s | %s | lowest %.3f" % [name, label, _lowest(model)])


## The lowest point of the drawn body (its skeleton's bones; a foot through the floor reads < 0).
func _lowest(model: CreatureModel) -> float:
	if model.skeleton == null:
		return 0.0
	var low := INF
	for i in model.skeleton.get_bone_count():
		var p := model.skeleton.global_transform * model.skeleton.get_bone_global_pose(i).origin
		low = minf(low, p.y)
	return low
