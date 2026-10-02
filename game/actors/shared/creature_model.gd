class_name CreatureModel
extends Node3D
## A forged foe that is not a person (tools/forge/creature_forge.py): a wolf, a hound, a boar, a
## reptile, the weaver, a thrall, a warden, a wisp. It is the AnimationDriver's model, as the
## forged humanoid is (play_intent, clip_timing, set_locomotion, speed_scale, clip_event): the
## driver keeps the time and this is a picture of its timeline.
##
## * One-shots (attacks, Hit, Stagger, Knockdown, Get_Up, Death) are played as the driver asks,
##   at the speed it sets each frame; Death and Knockdown keep their last frame.
## * A loop asked for (Idle, Idle_Combat) is what the body stands in.
## * Moving, it plays the gait for its ground speed (Walk, Trot, Run, Walk_Back, Strafe_L/R) at the
##   rate that keeps its feet planted -- ground speed over the clip's sidecar `speed` -- and turning
##   on the spot it steps round (Turn_L90/R90), as HorseModel does.
## * The body, its LOD1 and its LOD2 are drawn each in its own band of distance.
##
## Which model a foe wears is its def's `body_variant` (MODELS, or its KIN's if the forge has not
## made its own); the def's `scale` over the scale the forge built it for (its meta's `def_scale`)
## sizes it.

signal clip_event(event_name: String)
signal clip_finished(clip: String)

const ROOT := "res://assets/models/creatures/"
## body_variant -> the forged model's folder and name under ROOT.
const MODELS := {
	"wolf": "down_wolf", "crag_wolf": "crag_wolf", "thornhound": "thornhound", "leech_hound": "leech_hound",
	"old_grey_bitch": "old_grey_bitch", "brake_dam": "brake_dam",
	"boar": "bristleback", "drake": "gutter_drake", "sallowjaw": "sallowjaw", "weaver": "weaver",
	"stone": "stone_thrall", "kingbone": "stone_thrall_king", "treant": "warden", "wisp": "wisp",
}
## A variant whose own model is not built wears its kin's.
const KIN := {"kingbone": "stone_thrall", "old_grey_bitch": "leech_hound", "brake_dam": "thornhound"}
## What a body with a crawling limb gone plays for what the game asks (a thrall with no arms and
## one leg comes on along the ground).
const CRAWLING := {"Idle": "Crawl_Idle", "Idle_Combat": "Crawl_Idle", "Walk": "Crawl", "Trot": "Crawl", "Run": "Crawl",
	"Walk_Back": "Crawl", "Strafe_L": "Crawl", "Strafe_R": "Crawl", "Turn_L90": "Crawl", "Turn_R90": "Crawl",
	"Death": "Crawl_Death", "Death_A": "Crawl_Death", "Death_B": "Crawl_Death", "Hit": "Crawl_Idle",
	"Hit_Light": "Crawl_Idle", "Stagger": "Crawl_Idle", "Knockdown": "Crawl_Idle", "Get_Up": "Crawl_Idle"}
## How long a limb that came off lies on the ground before it is gone.
const LIMB_LIES_S := 8.0
## The wisp's look (meta `look`: "wisp"): its shroud is mist, its core and a halo a light.
const VEIL_SHADER := preload("res://assets/shaders/wisp_veil.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/wisp_glow.gdshader")
const WISP_LIGHT_ENERGY := 1.0
const WISP_LIGHT_RANGE := 5.5
## How long a wisp takes to go out once it is dead.
const WISP_GOES_OUT_S := 1.6
## Clips the game asks for by another name, or that a beast plays as one of its own.
const STANDS_FOR := {
	"Death_A": "Death", "Death_B": "Death", "Hit_Light": "Hit", "Hit_Heavy": "Stagger", "Block_Hit": "Hit",
	"Parry": "Hit", "Riposte": "Attack_1", "Backstab": "Attack_1", "Block_Idle": "Idle_Combat",
	"Sprint": "Run", "Jump_Start": "Hit", "Jump_Land": "Hit", "Interact": "Idle", "Cast_Long": "Cast_Quick",
	"Cast_Quick": "Attack_1", "Cast_Loop": "Idle_Combat", "Idle_Combat": "Idle", "Trot": "Walk",
}
## Directional reactions (Hit_Light_L, Stagger_B): played as the front's when the beast has no own.
const WAYS: Array[String] = ["_B", "_L", "_R", "_F"]
const LOOPS: Array[String] = ["Idle", "Idle_Combat", "Walk", "Trot", "Run", "Walk_Back", "Strafe_L", "Strafe_R",
	"Turn_L90", "Turn_R90", "Swim", "Hover"]
const HELD: Array[String] = ["Death", "Knockdown"]
const GAITS: Array[String] = ["Walk", "Trot", "Run", "Walk_Back", "Strafe_L", "Strafe_R"]
## Distance bands (m) for the full body, LOD1 and LOD2, at a body 1 m tall; a bigger body keeps its
## detail further out.
const LOD1_FROM := 18.0
const LOD2_FROM := 45.0
const DRAW_TO := 240.0
const STANDING := 0.2
const BLEND_GAIT := 0.25
const BLEND_ONE_SHOT := 0.12
const TURN_FROM := deg_to_rad(25.0)

static var _sidecars: Dictionary = {}
static var _metas: Dictionary = {}

var model_name := ""
## The foe's def scale (body_scale); the model is grown by it over its own `def_scale`.
var body_scale := 1.0
var tint := Color.WHITE
var speed_scale := 1.0:
	set(v):
		speed_scale = v
		if anim_player != null and not _intent.is_empty():
			anim_player.speed_scale = v
var anim_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var clip_data: Dictionary = {}
var meta: Dictionary = {}

var _root: Node3D = null
var _intent := ""            # what the driver asked for (its name)
var _intent_clip := ""       # the clip playing it
var _held := false
var _stand := "Idle"
var _loop := ""
var _loco := Vector2.ZERO
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _have_yaw := false
var _actor: Node = null
var _limbs_shown := 0
var _crawl := false
var _light: OmniLight3D = null
var _glows: Array[ShaderMaterial] = []
var _veils: Array[ShaderMaterial] = []
var _out := 0.0               # how far gone out a dead wisp is, 0..1
var _flare := 0.0             # the light brightened by a cast


## The model a body variant wears ("" when the forge has made none).
static func model_for(variant: String) -> String:
	for n in [str(MODELS.get(variant, "")), str(KIN.get(variant, ""))]:
		if not n.is_empty() and ResourceLoader.exists(ROOT + n + "/" + n + ".glb"):
			return n
	return ""


static func create(variant: String, scale_factor: float = 1.0) -> CreatureModel:
	var n := model_for(variant)
	if n.is_empty():
		return null
	var m := CreatureModel.new()
	m.name = "CreatureModel"
	m.model_name = n
	m.body_scale = scale_factor
	return m


static func sidecar(n: String) -> Dictionary:
	if not _sidecars.has(n):
		_sidecars[n] = _read_json(ROOT + n + "/" + n + ".clips.json")
	return _sidecars[n]


static func meta_of(n: String) -> Dictionary:
	if not _metas.has(n):
		_metas[n] = _read_json(ROOT + n + "/" + n + ".meta.json")
	return _metas[n]


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _ready() -> void:
	build()


func build() -> void:
	if _root != null or model_name.is_empty():
		return
	var packed := load(ROOT + model_name + "/" + model_name + ".glb") as PackedScene
	if packed == null:
		push_error("CreatureModel: cannot load %s" % model_name)
		return
	_root = packed.instantiate() as Node3D
	add_child(_root)
	clip_data = sidecar(model_name)
	meta = meta_of(model_name)
	scale = Vector3.ONE * (body_scale / maxf(float(meta.get("def_scale", 1.0)), 0.01))
	skeleton = _root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		for n in clip_data:
			var a := _anim(str(n))
			if a == null:
				continue
			var want := Animation.LOOP_LINEAR if bool((clip_data[n] as Dictionary).get("loop", false)) else Animation.LOOP_NONE
			if a.loop_mode != want:
				a.loop_mode = want
		anim_player.animation_finished.connect(_on_finished)
		anim_player.playback_default_blend_time = 0.0
	_set_up_lods()
	_tint()
	if str(meta.get("look", "")) == "wisp":
		_wisp_look()
	_play_loop("Idle", 0.0)


func _set_up_lods() -> void:
	var tall := maxf(float(meta.get("height", 1.0)) * scale.y, 0.5)
	var k := clampf(sqrt(tall), 0.6, 2.2)
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name).to_lower()
		if n.ends_with("lod1"):
			m.visibility_range_begin = LOD1_FROM * k
			m.visibility_range_end = LOD2_FROM * k
		elif n.ends_with("lod2"):
			m.visibility_range_begin = LOD2_FROM * k
			m.visibility_range_end = DRAW_TO * k
		else:
			m.visibility_range_begin = 0.0
			m.visibility_range_end = LOD1_FROM * k
		m.visibility_range_begin_margin = 0.0
		m.visibility_range_end_margin = 0.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## A def whose tint is not the one the forge painted (the meta's `tint`) -- a body worn by its kin
## (KIN) -- has the albedo multiplied toward it.
func _tint() -> void:
	if not meta.has("tint"):
		return
	var base := Color(str(meta["tint"]))
	if tint == Color.WHITE or base.is_equal_approx(tint):
		return
	var mul := Color(clampf(tint.r / maxf(base.r, 0.05), 0.5, 1.8), clampf(tint.g / maxf(base.g, 0.05), 0.5, 1.8),
		clampf(tint.b / maxf(base.b, 0.05), 0.5, 1.8))
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var own := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				own.albedo_color = own.albedo_color * mul
				m.set_surface_override_material(i, own)


func _anim(clip: String) -> Animation:
	if anim_player == null:
		return null
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(clip):
			return lib.get_animation(clip)
	return null


func _own(clip: String) -> bool:
	return clip_data.has(clip) and _anim(clip) != null


## The beast's own clip for a name the game uses, or "". A directional reaction is the beast's own
## only when it has one (`directional`: the driver plays the front's then).
func resolve(clip: String, directional := false) -> String:
	if _crawl and CRAWLING.has(clip) and _own(str(CRAWLING[clip])):
		return str(CRAWLING[clip])
	if _own(clip):
		return clip
	if directional:
		for w in WAYS:
			if clip.ends_with(w):
				return resolve(clip.substr(0, clip.length() - w.length()))
	var seen := {}
	var c := clip
	while STANDS_FOR.has(c) and not seen.has(c):
		seen[c] = true
		c = str(STANDS_FOR[c])
		if _own(c):
			return c
	return ""


func has_clip(clip: String) -> bool:
	return not resolve(clip).is_empty()


func clip_names() -> PackedStringArray:
	return PackedStringArray(clip_data.keys())


func clip_length(clip: String) -> float:
	var c := resolve(clip, true)
	return float((clip_data.get(c, {}) as Dictionary).get("length", 0.0)) if not c.is_empty() else 0.0


func clip_timing(clip: String) -> Dictionary:
	var c := resolve(clip, true)
	if c.is_empty():
		return {}
	var d: Dictionary = clip_data[c]
	return {"length": float(d.get("length", 0.0)), "events": (d.get("events", []) as Array).duplicate(true)}


func gait_speed(clip: String) -> float:
	return absf(float((clip_data.get(clip, {}) as Dictionary).get("speed", 0.0)))


func play_intent(clip: String, blend: float = BLEND_ONE_SHOT) -> bool:
	if anim_player == null:
		return false
	var c := resolve(clip, true)
	if c.is_empty():
		push_warning("CreatureModel %s: no clip for '%s'" % [model_name, clip])
		return false
	if LOOPS.has(c) or bool((clip_data[c] as Dictionary).get("loop", false)):
		# a loop is how the body stands, not an action
		_intent = ""
		_intent_clip = ""
		_held = false
		if not GAITS.has(c):
			_stand = c
		return true
	# roused from an ambush (Get_Up with nothing having put it down): a beast that waits has its own
	if c == "Get_Up" and _intent_clip != "Knockdown" and _own("Rise"):
		c = "Rise"
	_intent = clip
	_intent_clip = c
	_held = false
	anim_player.play(c, blend)
	anim_player.seek(0.0, true)
	anim_player.speed_scale = speed_scale
	_loop = ""
	return true


func stop_intent() -> void:
	if _intent.is_empty():
		return
	var finished := _intent
	_intent = ""
	_intent_clip = ""
	_held = false
	clip_finished.emit(finished)


func current_intent() -> String:
	return _intent


func current_clip() -> String:
	return _intent_clip if not _intent_clip.is_empty() else _loop


func set_locomotion(v: Vector2, _sneaking: bool = false) -> void:
	_loco = v


func set_swimming(_on: bool) -> void:
	pass


func _on_finished(clip: StringName) -> void:
	if String(clip) != _intent_clip:
		return
	if HELD.has(_intent_clip):
		_held = true
		return
	var finished := _intent
	_intent = ""
	_intent_clip = ""
	clip_finished.emit(finished)


func _process(delta: float) -> void:
	if anim_player == null:
		return
	if _light != null or not _glows.is_empty():
		_wisp_light(delta)
	_track_turn(delta)
	if _actor != null and is_instance_valid(_actor) and _actor.has_method("limbs_broken"):
		var n := int(_actor.call("limbs_broken"))
		if n != _limbs_shown:
			_apply_limbs(n)
	if not _intent.is_empty():
		return
	var speed := _loco.length()
	var want := _stand
	var rate := 1.0
	if speed >= STANDING:
		want = _gait_for(_loco)
		var s := gait_speed(want)
		rate = speed / s if s > 0.0 else 1.0
	elif absf(_yaw_rate) > TURN_FROM and has_clip("Turn_L90"):
		want = "Turn_L90" if _yaw_rate > 0.0 else "Turn_R90"
		var t := absf(float((clip_data.get(want, {}) as Dictionary).get("turn", 90.0)))
		var per := deg_to_rad(t) / maxf(clip_length(want), 0.01)
		rate = absf(_yaw_rate) / maxf(per, 0.01)
	want = resolve(want)
	if want.is_empty():
		want = resolve("Idle")
	if want != _loop:
		_play_loop(want, BLEND_GAIT)
	anim_player.speed_scale = clampf(rate, 0.3, 2.6)


## Forward: the gait whose speed is nearest without being well under; back: Walk_Back; sideways
## more than ahead: a sidle.
func _gait_for(v: Vector2) -> String:
	if absf(v.x) > absf(v.y) * 1.3 and has_clip("Strafe_L"):
		return "Strafe_R" if v.x > 0.0 else "Strafe_L"
	if v.y < -0.1 and has_clip("Walk_Back"):
		return "Walk_Back"
	var speed := v.length()
	var best := "Walk"
	for g in ["Walk", "Trot", "Run"]:
		if not _own(g):
			continue
		# a gait is taken once the pace is past the middle of it and the one below
		if speed >= gait_speed(g) * 0.72 or g == "Walk":
			best = g
	return best


func _track_turn(delta: float) -> void:
	var yaw := global_rotation.y
	if not _have_yaw:
		_have_yaw = true
		_last_yaw = yaw
		return
	var d := wrapf(yaw - _last_yaw, -PI, PI)
	_last_yaw = yaw
	if delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, d / delta, clampf(delta * 8.0, 0.0, 1.0))


func _play_loop(clip: String, blend: float) -> void:
	if not _own(clip):
		return
	var phase := 0.0
	if GAITS.has(_loop) and GAITS.has(clip) and anim_player.is_playing():
		phase = fposmod(anim_player.current_animation_position / maxf(clip_length(_loop), 0.001), 1.0)
	anim_player.play(clip, blend)
	if phase > 0.0:
		anim_player.seek(phase * clip_length(clip), true)
	_loop = clip


## The actor's hurtbox laid on the body: the meta's volumes (a capsule along a beast's trunk, a
## sphere at its head; a tall body's column) in place of the upright capsule every actor starts
## with, which on a wolf stood over its middle and left its head and its quarters out.
func fit_hurtbox(hurtbox: Area3D, actor: Node3D) -> void:
	var vols: Array = meta.get("hurt", [])
	if hurtbox == null or vols.is_empty() or actor == null:
		return
	for c in hurtbox.get_children():
		if c is CollisionShape3D:
			hurtbox.remove_child(c)
			c.queue_free()
	_actor = actor
	var to_actor := actor.global_transform.affine_inverse() * global_transform
	# what it casts from: the wisp's light, not its feet
	var origin: Variant = meta.get("origin", null)
	if origin is Array and actor.get("attack_origin") is Node3D:
		(actor.get("attack_origin") as Node3D).position = to_actor * _v3(origin)
	var s := scale.x
	var i := 0
	for v in vols:
		var vol: Dictionary = v
		var shape := CollisionShape3D.new()
		shape.name = "Shape%d" % i
		i += 1
		var r := float(vol.get("r", 0.3)) * s
		if str(vol.get("kind", "")) == "sphere":
			var sp := SphereShape3D.new()
			sp.radius = r + 0.04
			shape.shape = sp
			shape.position = to_actor * _v3(vol.get("c", [0, 0, 0]))
		else:
			var a := to_actor * _v3(vol.get("a", [0, 0, 0]))
			var b := to_actor * _v3(vol.get("b", [0, 1, 0]))
			var cap := CapsuleShape3D.new()
			cap.radius = r + 0.04
			cap.height = a.distance_to(b) + 2.0 * cap.radius
			shape.shape = cap
			var axis := (b - a).normalized() if a.distance_to(b) > 0.001 else Vector3.UP
			var side := axis.cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3.RIGHT
			side = side.normalized()
			shape.transform = Transform3D(Basis(side, axis, side.cross(axis)), (a + b) * 0.5)
		hurtbox.add_child(shape)


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


# --- limbs that come off -------------------------------------------------------------------------

## The def's limbs (meta `limbs`: index, the part's mesh, whether losing it leaves the body
## crawling): the first `n` are gone. Each newly gone is hidden and thrown down beside the body.
func _apply_limbs(n: int) -> void:
	var limbs: Array = meta.get("limbs", [])
	var crawl := false
	for l in limbs:
		var limb: Dictionary = l
		var gone := int(limb.get("index", 0)) < n
		var part := model_name.to_pascal_case() + "_" + str(limb.get("part", ""))
		var meshes := _part_meshes(part)
		if gone and int(limb.get("index", 0)) >= _limbs_shown and not meshes.is_empty():
			_throw(meshes[0])
		for m in meshes:
			(m as MeshInstance3D).visible = not gone
		if gone and bool(limb.get("crawl", false)):
			crawl = true
	_limbs_shown = n
	if crawl != _crawl:
		_crawl = crawl
		_loop = ""


## The part's meshes, its body and its LODs.
func _part_meshes(part: String) -> Array:
	var out := []
	if _root == null:
		return out
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm == part or nm.begins_with(part + "_LOD"):
			out.append(mi)
	out.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).length() < String(b.name).length())
	return out


## The limb as a stone that falls and rolls: its mesh as it was made (the rest pose), a body that
## tumbles away from the trunk, gone after LIMB_LIES_S.
func _throw(mi: MeshInstance3D) -> void:
	var host := get_tree().current_scene if get_tree() != null else null
	if host == null or mi.mesh == null:
		return
	var box := mi.mesh.get_aabb()
	var rb := RigidBody3D.new()
	rb.name = "FallenLimb"
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 40.0
	var piece := MeshInstance3D.new()
	piece.mesh = mi.mesh
	piece.material_override = mi.get_active_material(0)
	piece.position = -(box.position + box.size * 0.5)
	rb.add_child(piece)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(box.size.x, box.size.z) * 0.35 * scale.x
	shape.shape = sphere
	rb.add_child(shape)
	host.add_child(rb)
	var at := global_transform * (box.position + box.size * 0.5)
	rb.global_transform = Transform3D(global_transform.basis, at)
	var away := (at - global_position)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else global_transform.basis.x
	rb.apply_central_impulse((away * 3.0 + Vector3.UP * 2.0) * rb.mass)
	rb.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * rb.mass * 2.0)
	get_tree().create_timer(LIMB_LIES_S).timeout.connect(rb.queue_free)


# --- the wisp's light ----------------------------------------------------------------------------

func _wisp_look() -> void:
	var body_tex: Texture2D = null
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var base := m.get_active_material(0)
		if base is BaseMaterial3D and body_tex == null:
			body_tex = (base as BaseMaterial3D).albedo_texture
		var core := String(m.name).contains("Core")
		var mat := ShaderMaterial.new()
		if core:
			mat.shader = GLOW_SHADER
			_glows.append(mat)
		else:
			mat.shader = VEIL_SHADER
			if body_tex != null:
				mat.set_shader_parameter("streaks", body_tex)
			mat.set_shader_parameter("tint", tint if tint != Color.WHITE else Color(0.62, 0.84, 0.8))
			_veils.append(mat)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if skeleton == null:
		return
	var att := BoneAttachment3D.new()
	att.name = "Lantern"
	att.bone_name = "Hips"
	skeleton.add_child(att)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	halo.mesh = quad
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hm := ShaderMaterial.new()
	hm.shader = GLOW_SHADER
	hm.set_shader_parameter("billboard", true)
	halo.material_override = hm
	_glows.append(hm)
	att.add_child(halo)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.light_energy = WISP_LIGHT_ENERGY
	_light.omni_range = WISP_LIGHT_RANGE
	_light.shadow_enabled = false
	att.add_child(_light)


## The light breathes; a cast flares it; dead, it goes out.
func _wisp_light(delta: float) -> void:
	var casting := _intent_clip in ["Cast_Quick", "Attack_1", "Attack_2"]
	_flare = move_toward(_flare, 1.0 if casting else 0.0, delta * (3.0 if casting else 1.5))
	if _intent_clip == "Death":
		_out = minf(_out + delta / WISP_GOES_OUT_S, 1.0)
	else:
		_out = 0.0
	var fade := 1.0 - _out
	var t := Time.get_ticks_msec() * 0.001
	var flicker := 0.9 + 0.06 * sin(t * 13.0) + 0.04 * sin(t * 7.3 + 1.3)
	if _light != null:
		_light.light_energy = WISP_LIGHT_ENERGY * flicker * fade * (1.0 + 1.2 * _flare)
		_light.visible = fade > 0.01
	for g in _glows:
		g.set_shader_parameter("energy", 1.0 + 1.5 * _flare)
		g.set_shader_parameter("fade", fade)
	for v in _veils:
		v.set_shader_parameter("fade", fade)
