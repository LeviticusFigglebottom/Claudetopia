class_name HorseModel
extends Node3D
## The forge's horse (tools/forge/horse_forge.py) on WM_Quadruped_v1: its meshes, its LODs, its
## sockets, and its clips played by what its body is doing (CONTRACTS §2b, §3b).
##
## A gait is played at the rate that keeps its planted hooves still: (ground speed / the clip's
## `speed`) times the clip's own rate, so the stride keeps its length and the cadence changes. The
## gaits are discrete, as a horse's are: `Mount` picks one with its own thresholds and this blends
## from the old to the new over GAIT_BLEND_S, the new clip starting at the old one's phase (every
## gait lands its hind left hoof at phase 0, so a blend keeps the legs in step). Standing, it
## idles, and it turns on the spot with the turn clips played at (turn rate / the clip's `turn`).
## One-shot clips (Stop, Rear, Mount, Dismount) play over all of it and hand back when they end.

signal action_finished(clip: String)

const MODEL_PATH := "res://assets/models/creatures/horse_cob/horse_cob.glb"
const GAITS: Array[String] = ["Walk", "Trot", "Canter", "Gallop", "Run"]
const GAIT_BLEND_S := 0.28
const IDLE_BLEND_S := 0.35
## Under this ground speed (m/s) a horse is standing: it idles, or turns on the spot.
const STANDING := 0.25
## Level of detail by distance (m): the full body and tack, the joined LOD1, the joined LOD2.
const LOD1_FROM := 24.0
const LOD2_FROM := 70.0
const DRAW_TO := 320.0

static var _clip_cache: Dictionary = {}

## Any WM_Quadruped_v1 beast from the forge: the horse by default, a ewe's GLB for livestock. Its
## clips' sidecar is <model>.clips.json beside it.
var model_path := MODEL_PATH
var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var clip_data: Dictionary = {}
var speed := 0.0          # forward ground speed, m/s (negative backs)
var turn_rate := 0.0      # rad/s, + to the left
var gait := ""            # the gait asked for, one of GAITS ("" when standing)
var grazing := false
## What a start town's horse is painted over the cob's own coat and the Wardens' cloth: multiplied
## into the body's and the tack's albedo (white leaves them as the forge made them).
var coat_tint := Color.WHITE
var cloth_tint := Color.WHITE

## A jump (Mount's leap): 1 leaving the ground .. -1 landing, and how much of the leap's pose is on
## (HorseLeapPose). While it is, the gait's legs all but stop: the legs are the leap's.
var leap := 0.0
var leap_weight := 0.0

var _root: Node3D = null
var _leap_pose: HorseLeapPose = null
var _playing := ""        # the loop now playing
var _action := ""         # a one-shot now playing
var _sockets: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	if _root != null:
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("HorseModel: cannot load %s" % model_path)
		return
	_root = packed.instantiate() as Node3D
	add_child(_root)
	skeleton = _root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	clip_data = _load_clips(model_path.get_basename() + ".clips.json")
	if anim_player != null:
		for n in clip_data:
			var a := _anim(str(n))
			if a == null:
				continue
			var want := Animation.LOOP_LINEAR if bool(clip_data[n].get("loop", false)) else Animation.LOOP_NONE
			if a.loop_mode != want:
				a.loop_mode = want
		anim_player.animation_finished.connect(_on_finished)
		anim_player.playback_default_blend_time = 0.0
	if skeleton != null:
		_leap_pose = HorseLeapPose.new()
		_leap_pose.name = "LeapPose"
		skeleton.add_child(_leap_pose)
	_set_up_lods()
	_tint()
	_play_loop("Idle", 0.0)


static func _load_clips(path: String) -> Dictionary:
	if _clip_cache.has(path):
		return _clip_cache[path]
	var out := {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	_clip_cache[path] = out
	return out


func _tint() -> void:
	if coat_tint == Color.WHITE and cloth_tint == Color.WHITE:
		return
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var tack := String(m.name).to_lower().contains("tack")
		var tint := cloth_tint if tack else coat_tint
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var own := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				own.albedo_color = own.albedo_color * tint
				m.set_surface_override_material(i, own)


## Each mesh drawn only in its own band of distance: the body and tack near, a joined LOD1 in the
## middle distance, the joined LOD2 far. The far bands fade in over a few metres.
func _set_up_lods() -> void:
	if _root == null:
		return
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name).to_lower()
		if n.contains("lod1"):
			m.visibility_range_begin = LOD1_FROM
			m.visibility_range_end = LOD2_FROM
		elif n.contains("lod2"):
			m.visibility_range_begin = LOD2_FROM
			m.visibility_range_end = DRAW_TO
		else:
			m.visibility_range_end = LOD1_FROM
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _anim(clip: String) -> Animation:
	if anim_player == null:
		return null
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(clip):
			return lib.get_animation(clip)
	return null


func has_clip(clip: String) -> bool:
	return _anim(clip) != null


## The clip's `speed` from the sidecar (m/s at which its planted hooves stand still).
func gait_speed(clip: String) -> float:
	return absf(float((clip_data.get(clip, {}) as Dictionary).get("speed", 0.0)))


func clip_length(clip: String) -> float:
	var a := _anim(clip)
	return a.length if a != null else float((clip_data.get(clip, {}) as Dictionary).get("length", 1.0))


## What the body is doing, set each physics frame by its Mount.
func set_motion(ground_speed: float, turning: float, wanted_gait: String) -> void:
	speed = ground_speed
	turn_rate = turning
	gait = wanted_gait


## A one-shot over the loops: Stop, Rear, Mount, Dismount. False when there is no such clip.
func play_action(clip: String) -> bool:
	if not has_clip(clip):
		return false
	_action = clip
	anim_player.play(clip, 0.15)
	anim_player.speed_scale = 1.0
	return true


func is_acting() -> bool:
	return not _action.is_empty()


func current_clip() -> String:
	return _action if not _action.is_empty() else _playing


func _on_finished(clip: StringName) -> void:
	if String(clip) == _action:
		_action = ""
		_playing = ""
		action_finished.emit(String(clip))


func _process(_delta: float) -> void:
	if _leap_pose != null:
		_leap_pose.leap = leap
		_leap_pose.weight = leap_weight
	if anim_player == null or not _action.is_empty():
		return
	var want := "Idle"
	var rate := 1.0
	if absf(speed) >= STANDING:
		if speed < 0.0 and has_clip("Walk_Back"):
			want = "Walk_Back"
		else:
			want = gait if gait in GAITS else "Walk"
		var s := gait_speed(want)
		rate = absf(speed) / s if s > 0.0 else 1.0
	elif absf(turn_rate) > deg_to_rad(20.0):
		want = "Turn_L90" if turn_rate > 0.0 else "Turn_R90"
		var t := absf(float((clip_data.get(want, {}) as Dictionary).get("turn", 90.0)))
		var per_cycle := deg_to_rad(t) / maxf(clip_length(want), 0.01)
		rate = absf(turn_rate) / maxf(per_cycle, 0.01)
	elif grazing and has_clip("Graze"):
		want = "Graze"
	if want != _playing:
		var blend := GAIT_BLEND_S if (want in GAITS and _playing in GAITS) else IDLE_BLEND_S
		_play_loop(want, blend)
	anim_player.speed_scale = lerpf(clampf(rate, 0.05, 3.0), 0.15, clampf(leap_weight, 0.0, 1.0))


func _play_loop(clip: String, blend: float) -> void:
	if not has_clip(clip):
		return
	var phase := 0.0
	if _playing in GAITS and clip in GAITS and anim_player.is_playing():
		var old_len := maxf(clip_length(_playing), 0.001)
		phase = fposmod(anim_player.current_animation_position / old_len, 1.0)
	anim_player.play(clip, blend)
	if phase > 0.0:
		anim_player.seek(phase * clip_length(clip), true)
	_playing = clip


## A socket bone (Socket.Saddle, Socket.Bit, Socket.Pack, Socket.Head) as a BoneAttachment3D,
## made on first asking.
func socket(socket_name: String) -> Node3D:
	if _sockets.has(socket_name):
		return _sockets[socket_name]
	if skeleton == null:
		return null
	var b := skeleton.find_bone(socket_name)
	if b < 0:
		return null
	var att := BoneAttachment3D.new()
	att.name = socket_name.replace(".", "_")
	att.bone_name = socket_name
	skeleton.add_child(att)
	_sockets[socket_name] = att
	return att


func meshes() -> Array:
	return _root.find_children("*", "MeshInstance3D", true, false) if _root != null else []
