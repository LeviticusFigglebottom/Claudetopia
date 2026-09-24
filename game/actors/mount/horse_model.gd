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
const CLIPS_JSON := "res://assets/models/creatures/horse_cob/horse_cob.clips.json"
const GAITS: Array[String] = ["Walk", "Trot", "Canter", "Gallop"]
const GAIT_BLEND_S := 0.28
const IDLE_BLEND_S := 0.35
## Under this ground speed (m/s) a horse is standing: it idles, or turns on the spot.
const STANDING := 0.25
## Level of detail by distance (m): the full body and tack, the joined LOD1, the joined LOD2.
const LOD1_FROM := 24.0
const LOD2_FROM := 70.0
const DRAW_TO := 320.0

static var _clip_cache: Dictionary = {}

var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var clip_data: Dictionary = {}
var speed := 0.0          # forward ground speed, m/s (negative backs)
var turn_rate := 0.0      # rad/s, + to the left
var gait := ""            # the gait asked for, one of GAITS ("" when standing)
var grazing := false

var _root: Node3D = null
var _playing := ""        # the loop now playing
var _action := ""         # a one-shot now playing
var _sockets: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	if _root != null:
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("HorseModel: cannot load %s" % MODEL_PATH)
		return
	_root = packed.instantiate() as Node3D
	add_child(_root)
	skeleton = _root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	clip_data = _load_clips()
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
	_set_up_lods()
	_play_loop("Idle", 0.0)


static func _load_clips() -> Dictionary:
	if _clip_cache.has(CLIPS_JSON):
		return _clip_cache[CLIPS_JSON]
	var out := {}
	if FileAccess.file_exists(CLIPS_JSON):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON))
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	_clip_cache[CLIPS_JSON] = out
	return out


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
	anim_player.speed_scale = clampf(rate, 0.05, 3.0)


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
