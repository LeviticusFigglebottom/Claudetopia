class_name HumanoidModel
extends Node3D
## Composes a humanoid from the forge's modular parts and drives its animation.
##
## Loads `humanoid_rig.glb` (rig + default body + every clip from CONTRACTS.md §3), attaches
## whatever parts an `appearance` Dictionary asks for to the one shared `Skeleton3D`, creates
## the `BoneAttachment3D` sockets from CONTRACTS.md §2, and exposes a small intent API over
## an `AnimationTree`:
##
##     model.set_locomotion(Vector2(0.0, 5.0), false)   # jogging ahead at 5 m/s, not sneaking
##     model.play_intent("Attack_1H_Light_1")
##     model.clip_event.connect(...)                    # hit_start / footstep_l / ...
##
## Clip events come from the `<model>.clips.json` sidecar rather than from method tracks in
## the GLB, so the forge can retime a clip without re-authoring anything in the engine.

signal clip_event(name: String)
signal clip_finished(name: String)
signal appearance_changed()

const RIG_PATH := "res://assets/models/characters/humanoid_rig/humanoid_rig.glb"
const CLIPS_JSON := "res://assets/models/characters/humanoid_rig/humanoid_rig.clips.json"
const PARTS_ROOT := "res://assets/models/characters/"
## Slot -> folder under PARTS_ROOT. One folder per part family (CONTRACTS.md §4).
const SLOT_DIRS := {
	"head": "heads", "hair": "hair", "beard": "beards", "torso": "clothing", "legs": "clothing",
	"feet": "clothing", "hands": "clothing", "belt": "clothing", "back": "clothing",
	"headgear": "clothing", "attachment": "attachments", "body": "bodies",
}
## CONTRACTS.md §2 socket bones, exposed as BoneAttachment3D children.
const SOCKETS := {
	"Socket.WeaponR": "WeaponR", "Socket.WeaponL": "WeaponL", "Socket.ShieldL": "ShieldL",
	"Socket.Back": "Back", "Socket.HipL": "HipL", "Socket.Head": "Head", "Socket.Lantern": "Lantern",
}
## Recolours the iris band of an eyeball and leaves the white alone (see the shader).
const IRIS_SHADER := preload("res://assets/shaders/eye_iris.gdshader")
## Skin: the Compatibility renderer has no subsurface scattering, so the shader wraps the light
## past the terminator and tints what it adds towards blood (see the shader).
const SKIN_SHADER := preload("res://assets/shaders/skin.gdshader")
## Headgear that covers the crown. Hair is combed for a bare head; under one of these the
## chosen style would stand through the helm or the hood, so the close style is worn instead.
const COVERS_HEAD := {"headgear": ["helm", "hood"], "back": ["hooded_cloak", "ragged_cloak"]}
const UNDER_A_HOOD := "hood_friendly"
const DEFAULT_BLEND := 0.12
## Cross-fades on the state machine edges: into a one-shot fast, back to locomotion softer.
const ONE_SHOT_BLEND_IN := 0.08
const ONE_SHOT_BLEND_OUT := 0.14
const LOCOMOTION_STATE := "Locomotion"
## One-shots that end in a pose the body keeps -- a corpse, a man knocked flat, a sleeper -- until
## something else is played. Everything else goes back to locomotion when it ends, and so, until
## this list, did the dead: a fallen bandit stood up again 2.3 s after dying.
const HOLD_LAST_POSE: Array[String] = ["Death_A", "Death_B", "Death", "Knockdown", "Sleep_Idle", "Sit_Idle"]
## The clips the moving branch of the Locomotion graph plays, all on one stride timeline.
const MOVE_CLIPS: Array[String] = ["Walk", "Run", "Sprint", "Walk_Back", "Strafe_L", "Strafe_R", "Sneak_Walk"]
## A walk carries on up to this much faster than it was authored, at a quicker cadence, before
## it starts turning into a run.
const BRISK_WALK := 1.33
## However slowly or fast the body moves, a clip plays between these shares of its own cadence:
## a crawl of a stride looks wrong sooner than a small slide does. The floor lets go as the body
## comes to a stand (below MOVING_FULL), so a stop freezes the stride where it is and settles it
## into the idle, rather than stepping on the spot at half pace while the feet skate.
const RATE_MIN := 0.5
const RATE_MAX := 1.6
const SNEAK_BLEND_S := 0.25
## The speed the graph is driven at eases toward the body's over this long, so a velocity that
## ticks at 60 Hz, or hitches on a step, does not shake the blend.
const SPEED_SMOOTH_S := 0.08
## Below MOVING_FROM m/s the body is standing (the idle plays); above MOVING_FULL it is all gait.
const MOVING_FROM := 0.08
const MOVING_FULL := 0.7
## Stances held over whatever the legs are doing: the upper body takes the clip, the hips and legs
## keep walking. Played as a whole-body state, a raised guard froze the legs in its stance and the
## body glided across the ground at 1.56 m/s with its feet still.
const STANCE_CLIPS: Array[String] = ["Block_Idle"]
## The bones a stance owns: everything above the hips, and what hangs off it.
const UPPER_BODY: Array[String] = ["Spine", "Chest", "Neck", "Head",
		"Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
		"Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
		"Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL", "Socket.Back", "Socket.Head", "Socket.Lantern"]
const STANCE_BLEND_S := 0.12
## The gait and the idle hand over across this long, from the moment the body's own speed says
## so. Read off the smoothed speed, a stop from a jog held the legs split mid-stride for a tenth
## of a second after the body stood (the smoothing still thought it was moving) and then snapped
## them together in the next tenth.
const MOVE_BLEND_S := 0.2

@export var appearance_dict: Dictionary = {}:
	set(value):
		appearance_dict = value
		if is_inside_tree() and not _applying:
			apply_appearance(value)

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var appearance: CharacterAppearance = CharacterAppearance.new()

var _rig_root: Node3D
var _state_machine: AnimationNodeStateMachinePlayback
var _clip_data: Dictionary = {}          ## clip name -> {loop, length, events[]}
var _default_meshes: Dictionary = {}     ## logical name -> MeshInstance3D from the rig GLB
var _default_eyes: Array[MeshInstance3D] = []   ## both of the rig's eyeballs
var _part_meshes: Dictionary = {}        ## slot -> Array[MeshInstance3D]
## Which `bodies/*` mesh is standing in for the rig's own body, or "" for the rig's own.
## Readable because the part node cannot answer it: every variant's mesh is called `Body`
## inside its own glTF, so they all arrive here named `body_Body`.
var body_variant_worn := ""
var _sockets: Dictionary = {}            ## socket bone name -> BoneAttachment3D
var _one_shot := ""
var _one_shot_time := 0.0
var _one_shot_length := 0.0
var _fired: Dictionary = {}              ## event index -> true, for the running one-shot
var _locomotion := Vector2.ZERO          ## ground velocity asked for, m/s, the body's frame
var _loco_now := Vector2.ZERO            ## ...eased (SPEED_SMOOTH_S)
var _sneaking := false
var _sneak_w := 0.0
var _move_w := 0.0                       ## gait against idle, eased over MOVE_BLEND_S
var _stance := ""                        ## a STANCE_CLIPS clip held over the legs, or ""
var _stance_w := 0.0                     ## ...eased over STANCE_BLEND_S
var _has_stance_layer := false
var _gait_points: Array = []             ## [[clip, ground speed m/s, point name], ...] ascending
var _clip_speed: Dictionary = {}         ## clip -> authored ground speed (sidecar `speed`)
var _clip_cycle: Dictionary = {}         ## clip -> seconds per stride cycle
var _part_cache: Dictionary = {}
## Which hair part is actually on the head, which is not always the record's: see COVERS_HEAD.
var hair_worn := ""
var _worn_signature := ""
var _colour_signature := ""
static var _meta_cache: Dictionary = {}
var _applying := false      ## guards the appearance_dict setter against re-entering
## How fast a one-shot plays. The AnimationDriver sets it so that the blow the body makes lands on
## the frame the game opens the hit window, whatever length the caller's timing gave the attack;
## 0 holds the pose, which is what a heavy being charged is. Locomotion always plays at 1.
var speed_scale: float = 1.0
var _holding := ""          ## a finished HOLD_LAST_POSE clip the body is lying in
## Holds the feet where they stand when the body stops and steps them into the stance, so a stop
## does not slide them along the ground (FootPlanter). Off, a stop cross-fades the gait into the
## idle as it did before (the review tool's before/after switch).
static var plant_feet := true
var _planter: FootPlanter = null

static var _clip_cache: Dictionary = {}


func _ready() -> void:
	if _rig_root == null:
		build()
	if not appearance_dict.is_empty():
		apply_appearance(appearance_dict)


## Takes the override materials off every mesh before the meshes go. Freed outright, a mesh's
## materials died with it while its render instance still named them, and the renderer said
## `Parameter "material" is null` once for every mesh on the body.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var meshes: Array = _default_eyes.duplicate()
	meshes.append_array(_default_meshes.values())
	for slot in _part_meshes:
		meshes.append_array(_part_meshes[slot])
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, null)


## Loads the rig and its clips. Safe to call once; `_ready` does it automatically.
func build() -> void:
	if _rig_root != null:
		return
	var packed: PackedScene = load(RIG_PATH)
	if packed == null:
		push_error("HumanoidModel: cannot load %s" % RIG_PATH)
		return
	_rig_root = packed.instantiate() as Node3D
	add_child(_rig_root)
	skeleton = _rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = _rig_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or anim_player == null:
		push_error("HumanoidModel: %s has no Skeleton3D/AnimationPlayer" % RIG_PATH)
		return
	for mi in _rig_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var logical := _logical_name(m.name)
		if logical == "eyes":
			# two eyeballs share one logical name; keyed by it, the left one was lost
			_default_eyes.append(m)
			# And an eye's shadow falls inside the head's. Casting it is two more meshes in
			# every cascade of the sun for nothing: on Merrowby's street, twenty villagers in
			# view were 590 of 1328 draw calls, and their eyes about a hundred and thirty.
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_default_meshes[logical] = m
	_clip_data = _load_clip_data()
	_restore_contract_clip_names()
	_apply_loop_flags()
	_build_sockets()
	_build_animation_tree()
	_planter = FootPlanter.make(skeleton)


## The rig GLB's meshes are named to avoid clashing with bone names (see the forge's
## `mesh_object_name`), so map them back to the slot they stand in for.
func _logical_name(n: String) -> String:
	var s := n.to_lower()
	if s.begins_with("body"):
		return "body"
	if s.begins_with("head"):
		return "head"
	if s.begins_with("eye"):
		return "eyes"
	return s


static func _load_clip_data() -> Dictionary:
	if _clip_cache.has(CLIPS_JSON):
		return _clip_cache[CLIPS_JSON]
	var out := {}
	if FileAccess.file_exists(CLIPS_JSON):
		var text := FileAccess.get_file_as_string(CLIPS_JSON)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
		else:
			push_warning("HumanoidModel: %s is not a JSON object" % CLIPS_JSON)
	else:
		push_warning("HumanoidModel: missing %s" % CLIPS_JSON)
	_clip_cache[CLIPS_JSON] = out
	return out


## Godot's glTF importer treats a "_Loop" (or "-loop", "_cycle", ...) suffix as a marker,
## strips it from the animation name and sets the loop mode — so `Jump_Loop` arrives as
## `Jump`. CONTRACTS.md §3 names are binding, so put them back; the sidecar says which
## names should exist.
func _restore_contract_clip_names() -> void:
	const SUFFIXES := ["_Loop", "-loop", "_loop", "_Cycle", "-cycle", "_cycle"]
	for wanted in _clip_data:
		var name := str(wanted)
		if _find_animation(name) != null:
			continue
		for suffix in SUFFIXES:
			if not name.ends_with(suffix):
				continue
			var stripped := name.substr(0, name.length() - suffix.length())
			for lib_name in anim_player.get_animation_library_list():
				var lib := anim_player.get_animation_library(lib_name)
				if lib.has_animation(stripped) and not lib.has_animation(name):
					lib.rename_animation(stripped, name)
					break
			break


## The sidecar is the source of truth for loop flags (CONTRACTS.md §3).
func _apply_loop_flags() -> void:
	for name in _clip_data:
		var anim := _find_animation(str(name))
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if bool(_clip_data[name].get("loop", false)) else Animation.LOOP_NONE


func _find_animation(name: String) -> Animation:
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(name):
			return lib.get_animation(name)
	return null


func has_clip(name: String) -> bool:
	return _find_animation(name) != null


func clip_names() -> PackedStringArray:
	return anim_player.get_animation_list()


func clip_length(name: String) -> float:
	var a := _find_animation(name)
	return a.length if a != null else 0.0


func clip_events(name: String) -> Array:
	var d: Variant = _clip_data.get(name, {})
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return (d as Dictionary).get("events", [])


## A clip's own timeline, `{length, events}`: what the AnimationDriver keeps time by when its
## caller did not say. Empty when the rig has no such clip.
func clip_timing(name: String) -> Dictionary:
	if not has_clip(name):
		return {}
	var t := sidecar_timing(name)
	if t.is_empty() or float(t.get("length", 0.0)) <= 0.0:
		t = {"length": clip_length(name), "events": clip_events(name).duplicate(true)}
	return t


## The same, straight off the sidecar and without building a rig: a weapon measures its hit window
## against the clip it swings. Empty when the sidecar has no such clip.
static func sidecar_timing(name: String) -> Dictionary:
	var d: Variant = _load_clip_data().get(name, {})
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).is_empty():
		return {}
	var data := d as Dictionary
	return {"length": float(data.get("length", 0.0)), "events": (data.get("events", []) as Array).duplicate(true)}


# ---------------------------------------------------------------------------------------
# sockets
# ---------------------------------------------------------------------------------------

func _build_sockets() -> void:
	for bone_name in SOCKETS:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			push_warning("HumanoidModel: rig has no socket bone %s" % bone_name)
			continue
		var att := BoneAttachment3D.new()
		att.name = "Socket%s" % SOCKETS[bone_name]
		att.bone_name = bone_name
		att.bone_idx = idx
		# Moved by the animation every frame, not by physics: interpolated between ticks it would
		# trail the hand (measured: a child moved per frame read 3.61 where it had been put at 4).
		# Off, it sits exactly on the bone of a body that is itself interpolated.
		att.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		skeleton.add_child(att)
		_sockets[bone_name] = att


## The BoneAttachment3D for a socket, by its contract name ("Socket.WeaponR") or short name
## ("WeaponR"). Returns null when the rig has no such socket.
func socket(name: String) -> BoneAttachment3D:
	if _sockets.has(name):
		return _sockets[name]
	var full := "Socket.%s" % name
	return _sockets.get(full, null)


func socket_names() -> Array:
	return _sockets.keys()


## Parents a node to a socket, replacing whatever was there.
func attach_to_socket(name: String, node: Node3D, clear_existing: bool = true) -> bool:
	var s := socket(name)
	if s == null:
		return false
	if clear_existing:
		for c in s.get_children():
			c.queue_free()
	s.add_child(node)
	return true


# ---------------------------------------------------------------------------------------
# appearance
# ---------------------------------------------------------------------------------------

func apply_appearance(d: Variant) -> void:
	if _rig_root == null:
		build()
	if skeleton == null:
		return
	appearance = d as CharacterAppearance if d is CharacterAppearance else CharacterAppearance.new(d as Dictionary)
	_applying = true
	appearance_dict = appearance.to_dict()
	_applying = false
	hair_worn = _hair_to_wear()
	# Parts are only torn down and put back when the parts change. A slider dragged across the
	# Naming used to rebuild every mesh on the body at every step of the drag.
	var signature := _parts_signature()
	if signature != _worn_signature:
		_clear_parts()
		var child := _child_body_ready()
		for slot in CharacterAppearance.SLOTS:
			var part_name := hair_worn if slot == "hair" else appearance.part(slot)
			if slot == "head" and part_name.is_empty():
				part_name = "default"
			if child:
				part_name = _child_cut(slot, part_name)
			if part_name.is_empty():
				continue
			_add_part(slot, part_name)
		_apply_morality_parts()
		_apply_body_variant()
		# The head is always a part now, "default" included, and the rig's own head and eyes
		# stay hidden: the head parts carry the skull and the rig's copy is the old one. It
		# comes back only if the head part cannot be loaded at all.
		var own_head: bool = not _part_meshes.has("head")
		_show_default(_default_meshes.get("head"), own_head)
		for eye in _default_eyes:
			_show_default(eye, own_head)
		_worn_signature = signature
		_colour_signature = ""
	var colours := _colour_signature_now()
	if colours != _colour_signature:
		_apply_colours()
		_colour_signature = colours
	_apply_fits()
	_apply_proportions()
	appearance_changed.emit()


## Everything that decides which meshes are on the body.
func _parts_signature() -> String:
	var bits: Array[String] = [hair_worn, appearance.body_variant(),
		"hollow%d" % int(appearance.hollow >= 0.66) + str(int(appearance.hollow >= 0.33)),
		"hearth%d" % int(appearance.hearth >= 0.66)]
	for slot in CharacterAppearance.SLOTS:
		bits.append("%s=%s" % [slot, appearance.part(slot)])
	return "|".join(bits)


## Everything that decides what colour those meshes are.
func _colour_signature_now() -> String:
	return "%s|%s|%s|%s" % [appearance.skin, appearance.hair_colour, appearance.eye_colour,
		str(appearance.to_dict().get("palette", {}))]


## The hair the record chose, unless something is covering the crown.
func _hair_to_wear() -> String:
	var chosen := appearance.part("hair")
	if chosen.is_empty():
		return chosen
	for slot in COVERS_HEAD:
		if appearance.part(slot) in COVERS_HEAD[slot]:
			return UNDER_A_HOOD
	return chosen


## Freed at the end of the frame. A part put back in the same frame takes the same node names,
## and while the old meshes are still there the new ones are renamed `@MeshInstance3D@n` --
## which is why an eye is known by the `eye` meta `_add_part` gives it and not by its name: a
## head swapped for another used to lose the names its eyes were known by, and they were
## dressed in skin.
func _clear_parts() -> void:
	_worn_signature = ""
	for slot in _part_meshes:
		for mi in _part_meshes[slot]:
			if is_instance_valid(mi):
				mi.queue_free()
	_part_meshes.clear()


func _show_default(mi: MeshInstance3D, visible_now: bool) -> void:
	if mi != null:
		mi.visible = visible_now


## Morality visuals that are *parts* rather than colours (DESIGN.md §5.11).
func _apply_morality_parts() -> void:
	if appearance.hollow >= 0.66:
		_add_part("attachment", "horns_big")
	elif appearance.hollow >= 0.33:
		_add_part("attachment", "horns_small")
	if appearance.hearth >= 0.66:
		_add_part("attachment", "halo")


func _part_path(slot: String, part_name: String) -> String:
	var dir: String = SLOT_DIRS.get(slot, "clothing")
	return "%s%s/%s/%s.glb" % [PARTS_ROOT, dir, part_name, part_name]


## The forge's meta for a part (what it is made of, its fits), read once per part.
func _part_meta(slot: String, part_name: String) -> Dictionary:
	var path := _part_path(slot, part_name).replace(".glb", ".meta.json")
	if _meta_cache.has(path):
		return _meta_cache[path]
	var out := {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	_meta_cache[path] = out
	return out


func _add_part(slot: String, part_name: String) -> bool:
	var path := _part_path(slot, part_name)
	if not ResourceLoader.exists(path):
		push_warning("HumanoidModel: missing part %s (%s)" % [part_name, path])
		return false
	var packed: PackedScene = _part_cache.get(path, null)
	if packed == null:
		packed = load(path)
		_part_cache[path] = packed
	if packed == null:
		return false
	var inst := packed.instantiate()
	var added: Array[MeshInstance3D] = []
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var src := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.name = "%s_%s" % [slot, src.name]
		copy.mesh = src.mesh
		copy.skin = src.skin
		copy.transform = Transform3D.IDENTITY
		skeleton.add_child(copy)
		# every part is skinned to this same rig, so the shared Skeleton3D drives it
		copy.skeleton = copy.get_path_to(skeleton)
		copy.set_meta("slot", slot)
		copy.set_meta("part", part_name)
		copy.set_meta("eye", str(src.name).to_lower().contains("eye"))
		# a harness is several meshes of several materials (a coat under steel); the meta says
		# which mesh is which, and a single-mesh part falls back to its one material
		var meta := _part_meta(slot, part_name)
		var per_mesh: Dictionary = meta.get("materials", {})
		copy.set_meta("material", str(per_mesh.get(str(src.name), meta.get("material", ""))))
		added.append(copy)
	inst.queue_free()
	if added.is_empty():
		return false
	if not _part_meshes.has(slot):
		_part_meshes[slot] = []
	_part_meshes[slot].append_array(added)
	return true


## Every rig, head, hair shell and garment is baked once, in one colour: the record's skin,
## eyes and hair are tints relative to those bakes, and cloth takes the palette's colour for
## its role. Skin used to be applied only when a palette spelled out `skin_tint`, so the tone
## the record named was never seen on a body, and a head part fell through to the cloth
## palette's primary.
func _apply_colours() -> void:
	var pal := appearance.palette
	var skin := appearance.skin_tint()
	for slot in _part_meshes:
		for mi in _part_meshes[slot]:
			# A body variant is skin, not cloth. Without this it falls through to
			# `_colour_key_for`, which has no key for it, and a heavy villager keeps the
			# bake's own default tone while his face takes the record's.
			if slot == "body":
				_skin(mi, skin)
				continue
			if slot == "head":
				if _is_eye(mi):
					_tint_iris(mi)
				else:
					_skin(mi, skin)
				continue
			var key := _colour_key_for(slot)
			var kind := str(mi.get_meta("material", ""))
			if slot == "hair" or slot == "beard":
				_dress(mi, appearance.hair_tint() if not pal.has("hair") else pal["hair"] as Color, "hair")
				if slot == "beard" and str(mi.get_meta("part", "")) == STUBBLE:
					_as_stubble(mi)
				continue
			# Steel is the people's metal and leather their leather, whichever slot it is worn
			# in: a Vale cuirass was tinted the Vale's wool brown because it sat in `torso`.
			var colour_key := key
			if kind == "iron" and pal.has("metal"):
				colour_key = "metal"
			elif kind == "leather" and pal.has("leather"):
				colour_key = "leather"
			if pal.has(colour_key):
				_dress(mi, pal[colour_key] as Color, kind)
	for logical in ["body", "head"]:
		if _default_meshes.has(logical):
			_skin(_default_meshes[logical], skin)
	for eye in _default_eyes:
		_tint_iris(eye)


## Skin wears the skin shader, carrying the bake's own maps across and the record's tone as a
## tint against the bake.
func _skin(mi: MeshInstance3D, tint: Color) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	for i in count:
		var worn := mi.get_surface_override_material(i) as ShaderMaterial
		if worn != null and worn.shader == SKIN_SHADER:
			worn.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
			continue
		var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = SKIN_SHADER
		if base != null:
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
			var orm: Texture2D = base.roughness_texture if base.roughness_texture != null else base.ao_texture
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("use_orm", orm != null)
			m.set_shader_parameter("normal_tex", base.normal_texture)
			m.set_shader_parameter("use_normal", base.normal_texture != null)
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		mi.set_surface_override_material(i, m)


## What a skin's tint is, from whichever material it is wearing (the tests and the probes ask).
static func skin_tint_of(mi: MeshInstance3D) -> Color:
	var m := mi.get_surface_override_material(0)
	if m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
		if v is Vector3:
			return Color(v.x, v.y, v.z)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(-1, -1, -1)


## Cloth, leather, metal and hair are baked as value and grain; here each is also lit as what it
## is. Wool and linen catch a soft light along their edges, which is what reads as cloth at a
## distance; leather takes a tighter sheen; hair a brighter edge where the light comes through
## it. Metal needs nothing but its own metallic map and something to reflect.
##
## A mesh keeps the one material it was dressed in and only its colour changes after that. A
## look made in one frame (a preset, the lots, a probe) used to build a fresh material for every
## mesh at every step and drop the last one, and the Compatibility renderer was left holding
## materials that no longer existed: eyes stopped drawing, and the log filled with
## `Parameter "material" is null`.
## Stubble is a shell a millimetre and a half over the jaw, drawn in the hair colour: opaque,
## it was a full short beard. Seen through, it is a shadow on the skin, which is what stubble is.
const STUBBLE := "stubble"
const STUBBLE_ALPHA := 0.42


func _as_stubble(mi: MeshInstance3D) -> void:
	for i in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
		var m := mi.get_surface_override_material(i) as BaseMaterial3D
		if m == null:
			continue
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = STUBBLE_ALPHA
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _dress(mi: MeshInstance3D, c: Color, kind: String) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	for i in count:
		var worn := mi.get_surface_override_material(i) as BaseMaterial3D
		if worn != null and worn.has_meta("dressed"):
			worn.albedo_color = c
			continue
		var base := mi.mesh.surface_get_material(i)
		var m := (base.duplicate() if base != null else StandardMaterial3D.new()) as BaseMaterial3D
		if m == null:
			continue
		m.set_meta("dressed", true)
		m.albedo_color = c
		match kind:
			"cloth":
				m.rim_enabled = true
				m.rim = 0.32
				m.rim_tint = 0.70
				m.metallic_specular = 0.25
			"leather":
				m.rim_enabled = true
				m.rim = 0.12
				m.rim_tint = 0.35
				m.metallic_specular = 0.55
			"hair":
				m.rim_enabled = true
				m.rim = 0.45
				m.rim_tint = 0.40
				m.metallic_specular = 0.40
			"iron":
				m.metallic_specular = 0.65
		mi.set_surface_override_material(i, m)


## Every garment is built on the default body and carries the heavy and slight bodies as
## morph targets, fitted by the forge, so a heavy villager's tunic is cut for him instead of
## the body standing through it. Beards carry one target per face, because a beard lies on a
## jaw and the faces' jaws are not one jaw.
func _apply_fits() -> void:
	var head := appearance.part("head")
	for slot in _part_meshes:
		for mi in _part_meshes[slot]:
			var m := mi as MeshInstance3D
			if m == null or m.mesh == null or not (m.mesh is ArrayMesh):
				continue
			var shapes := (m.mesh as ArrayMesh).get_blend_shape_count()
			for b in shapes:
				var shape := str((m.mesh as ArrayMesh).get_blend_shape_name(b))
				var on := false
				if shape == "heavy" or shape == "slight":
					on = shape == body_variant_worn
				elif slot == "beard" or slot == "hair":
					on = shape == head
				m.set_blend_shape_value(b, 1.0 if on else 0.0)


func _is_eye(mi: MeshInstance3D) -> bool:
	if mi.has_meta("eye"):
		return bool(mi.get_meta("eye"))
	return mi.name.to_lower().contains("eye")


## The eyeball keeps its baked texture; only the iris band is recoloured.
func _tint_iris(mi: MeshInstance3D) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	var tint := appearance.iris_tint()
	for i in count:
		var worn := mi.get_surface_override_material(i) as ShaderMaterial
		if worn != null and worn.shader == IRIS_SHADER:
			worn.set_shader_parameter("iris_tint", Vector3(tint.r, tint.g, tint.b))
			continue
		var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = IRIS_SHADER
		if base != null and base.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
		m.set_shader_parameter("iris_tint", Vector3(tint.r, tint.g, tint.b))
		mi.set_surface_override_material(i, m)


func _colour_key_for(slot: String) -> String:
	match slot:
		"torso", "back":
			return "primary"
		"legs":
			return "secondary"
		"feet", "belt", "hands":
			return "leather"
		"headgear":
			return "metal"
		"hair", "beard":
			return "hair"
	return "primary"


## Body variants that may be worn on *this* rig, and the one that may not.
##
## `_add_part` re-skins a part's mesh onto the shared `Skeleton3D`, which is only honest
## when the part was built around the same bones. Measured against the default skeleton,
## the worst joint in `slight` moves 3.3 mm and in `heavy` 1.9 mm -- they are shape, not
## skeleton, and they wear straight onto this rig.
##
## `child` is a different skeleton: its hips sit at 0.646 m against 0.980, its upper arm is
## 192 mm against 292, and its worst joint is 476 mm from the adult's, 9.2 m summed over
## 29 bones. Draping that mesh on adult bones would stretch a child back into an adult, so it
## is not worn like these two: `_apply_child` re-proportions the rig itself (see
## ChildProportions) and the child body goes on that.
const WEARABLE_BODIES := ["slight", "heavy"]
const CHILD_BODY := "child"
## What a child wears in a slot whose garment has no child's cut: the plain garment of that
## slot. A slot missing here (hands, back) is left bare rather than draped in a grown cut.
const CHILD_STAND_INS := {"torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"}
## Slots whose parts are skinned to the body and so are cut per skeleton. Everything else
## (head, hair, beard, headgear, attachments) is rigid to the head and fits any skeleton.
const CUT_PER_SKELETON := ["torso", "legs", "feet", "hands", "belt", "back"]

var _child_mod: ChildProportions = null
var _child_height := 1.30
## Off, a child is the grown rig scaled down to a child's height, as before it had a skeleton
## of its own (the review tool's before/after switch).
static var child_rig := true


## The body this record wears, when it is not the default one.
##
## `CharacterAppearance.body_variant()` has always named the right one and nothing ever
## loaded it, because `bodies/child`, `heavy` and `slight` each held a 31-bone skeleton and
## no mesh at all: the forge built the geometry and the glTF exporter dropped it as invalid
## without failing the build.
##
## And only under clothes cut for it. The heavy body is wider than every garment built on the
## default one, so wearing it under them showed skin through the gambeson, the coat and the
## tunic at the heavy end of the Naming's build slider. A garment the forge has fitted carries
## the variant as a morph target and says so in its meta (`fits`); until every garment on the
## body does, the default body is worn and the rig's girth does the widening.
func _apply_body_variant() -> void:
	var variant := appearance.body_variant()
	if variant == CHILD_BODY and _child_body_ready() and _add_part("body", CHILD_BODY):
		body_variant_worn = CHILD_BODY
		_apply_child(true)
	else:
		_apply_child(false)
		var wearable: bool = WEARABLE_BODIES.has(variant) and _garments_fit(variant)
		body_variant_worn = variant if wearable and _add_part("body", variant) else ""
	_show_default(_default_meshes.get("body"), body_variant_worn.is_empty())


## True when this record is a child's and the forge has built the child's body and the
## clothes cut for it. Without the clothes the child body would stand in the street bare, and
## the grown rig scaled down is the better of the two.
func _child_body_ready() -> bool:
	return child_rig and appearance.body_variant() == CHILD_BODY \
			and ResourceLoader.exists(_part_path("body", CHILD_BODY)) \
			and ResourceLoader.exists(_part_path("torso", "%s_child" % CHILD_STAND_INS["torso"]))


## The part a child wears in `slot` for `part_name`: rigid parts as they are, a garment's
## child cut when the forge made one, otherwise the plain garment of the slot, otherwise none.
func _child_cut(slot: String, part_name: String) -> String:
	if part_name.is_empty() or not CUT_PER_SKELETON.has(slot):
		return part_name
	for candidate in [part_name, str(CHILD_STAND_INS.get(slot, ""))]:
		if candidate.is_empty():
			continue
		var cut := "%s_child" % candidate
		if ResourceLoader.exists(_part_path(slot, cut)):
			return cut
	return ""


## Puts the rig at the child's proportions (or back). The child's rest pose is read off the
## forge's child body, and its head scale off the proportions that body was built at: the
## heads are the grown ones and a child's is 0.86 of a grown head at 1.30 m.
func _apply_child(on: bool) -> void:
	if not on:
		if _child_mod != null:
			_child_mod.queue_free()
			_child_mod = null
		return
	if _child_mod != null:
		return
	var packed: PackedScene = _part_cache.get(_part_path("body", CHILD_BODY), null)
	if packed == null:
		packed = load(_part_path("body", CHILD_BODY))
	if packed == null:
		return
	var inst := packed.instantiate()
	var child_skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if child_skel == null:
		inst.free()
		return
	var props: Dictionary = _part_meta("body", CHILD_BODY).get("params", {}).get("proportions", {})
	_child_height = float(props.get("height", 1.30))
	var head_scale := float(props.get("head_size", 1.0)) * _child_height / 1.78
	_child_mod = ChildProportions.new()
	_child_mod.name = "ChildProportions"
	_child_mod.setup(skeleton, child_skel, head_scale)
	inst.free()
	skeleton.add_child(_child_mod)


## Slots whose garments take their weights from the body and so have to be cut for it.
const FITTED_SLOTS := ["torso", "legs", "feet", "hands", "belt", "back"]


func _garments_fit(variant: String) -> bool:
	if variant == CHILD_BODY:
		return true
	for slot in FITTED_SLOTS:
		var part_name := appearance.part(slot)
		if part_name.is_empty():
			continue
		var fits: Array = _part_meta(slot, part_name).get("fits", [])
		if not fits.has(variant):
			return false
	return true


## Runtime bone scaling would break clips authored on the default proportions
## (CONTRACTS.md §2), so overall size is a uniform scale.
##
## The widening is the fallback and only the fallback. With a real variant on, the shape is
## in the mesh -- baked at the proportions the forge was given -- and scaling the rig as
## well would count the same build twice and hand a heavy villager a second helping of
## width.
##
## The build slider used to do nothing at all across its middle third: the body variant only
## changes at 0.30 and 0.68, and with a variant on the rig was not widened. Now the girth the
## slider asks for is one continuous line from slight to broad, and the rig makes up the
## difference between it and the girth of whichever body is worn -- so each variant's own
## shape (narrow shoulders, a heavy middle) comes in at its end without the width jumping,
## and nothing is counted twice.
const VARIANT_GIRTH := {"": 1.0, "slight": 0.90, "heavy": 1.12}


static func girth_for(build: float) -> float:
	return lerpf(0.88, 1.14, clampf(build, 0.0, 1.0))


func _apply_proportions() -> void:
	var s: float = appearance.height / (_child_height if _child_mod != null else 1.78)
	var wide: float = girth_for(appearance.build) / float(VARIANT_GIRTH.get(body_variant_worn, 1.0))
	if _rig_root != null:
		_rig_root.scale = Vector3(s * wide, s, s * wide)


# ---------------------------------------------------------------------------------------
# animation
# ---------------------------------------------------------------------------------------

func _build_animation_tree() -> void:
	var sm := AnimationNodeStateMachine.new()
	# ROOT, not GROUPED: a grouped machine may only be driven through its parent's playback,
	# and this one is the tree root, so every travel() on it pushed an error.  A walking
	# actor did that once a frame.
	sm.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT
	sm.add_node(LOCOMOTION_STATE, _build_locomotion_tree(), Vector2(0, 0))
	var boot := _transition(0.0, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE)
	boot.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", LOCOMOTION_STATE, boot)
	var x := 260.0
	var y := -420.0
	for name in anim_player.get_animation_list():
		if _is_locomotion_clip(name):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = name
		sm.add_node(name, node, Vector2(x, y))
		# travel() needs a path of real transitions or it teleports without a cross-fade
		sm.add_transition(LOCOMOTION_STATE, name,
				_transition(ONE_SHOT_BLEND_IN, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
		sm.add_transition(name, LOCOMOTION_STATE,
				_transition(ONE_SHOT_BLEND_OUT, AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE))
		y += 46.0
		if y > 420.0:
			y = -420.0
			x += 200.0
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = sm
	# Stepped by _process rather than by itself, so a one-shot can be played faster, slower or not
	# at all (speed_scale) -- an AnimationTree has no speed of its own to set.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# the node has to be in the tree before a NodePath to the player can resolve
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	anim_tree = tree
	_state_machine = tree.get("parameters/playback")
	_update_locomotion(0.0)


## One transition resource per edge: they are cheap, and `travel` refuses to cross-fade
## between two states that are not connected.
func _transition(xfade: float, mode: int) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = mode
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	t.reset = false
	return t


## The locomotion graph (the Locomotion state):
##
##     Walk, Walk (fast), Run, Sprint -> gait (1D, by ground speed) -+
##                                             Sneak_Walk -> fwd ----+-> fb <- Walk_Back
##     Strafe_L, Strafe_R -> lr ------------------------------------> dir -> cycle -> move -> out
##     Idle, Sneak_Idle -> idle ------------------------------------------------------^
##
## Every moving clip is laid on the same one-second timeline, one stride cycle stretched to fit
## it, and every blend in the moving branch keeps its silent inputs running, so the gaits are
## always at the same phase: the forge puts the left foot down at 0 and the right at 0.5 in each
## (CONTRACTS §3). `cycle` then sets how many strides a second that shared timeline runs at:
## ground speed over the stride of whatever is being blended, which is what keeps a planted foot
## planted. The first graph was one 2D blend space fed velocity/6.5 with Sneak_Walk half way up
## its forward axis: the default gait was posed three-quarters of the way into a crouch, the
## sprint played Walk, and the feet slid at 76-79% of the ground speed.
func _build_locomotion_tree() -> AnimationNodeBlendTree:
	_read_gait_speeds()
	var bt := AnimationNodeBlendTree.new()
	var gait := AnimationNodeBlendSpace1D.new()
	gait.blend_mode = AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED
	gait.min_space = 0.0
	gait.max_space = 20.0
	gait.sync = true
	for point in _gait_points:
		gait.add_blend_point(_cycle_node(str(point[0])), float(point[1]), -1, str(point[2]))
	bt.add_node("gait", gait, Vector2(0, 0))
	bt.add_node("sneak_walk", _cycle_node(_or_idle("Sneak_Walk")), Vector2(0, 160))
	bt.add_node("back", _cycle_node(_or_idle("Walk_Back")), Vector2(200, 260))
	bt.add_node("strafe_l", _cycle_node(_or_idle("Strafe_L")), Vector2(0, 360))
	bt.add_node("strafe_r", _cycle_node(_or_idle("Strafe_R")), Vector2(0, 460))
	for blend_name in ["fwd", "fb", "lr", "dir"]:
		var b := AnimationNodeBlend2.new()
		b.sync = true
		bt.add_node(blend_name, b, Vector2(400, 0))
	bt.connect_node("fwd", 0, "gait")
	bt.connect_node("fwd", 1, "sneak_walk")
	bt.connect_node("fb", 0, "fwd")
	bt.connect_node("fb", 1, "back")
	bt.connect_node("lr", 0, "strafe_l")
	bt.connect_node("lr", 1, "strafe_r")
	bt.connect_node("dir", 0, "fb")
	bt.connect_node("dir", 1, "lr")
	bt.add_node("cycle", AnimationNodeTimeScale.new(), Vector2(600, 0))
	bt.connect_node("cycle", 0, "dir")
	var idle := AnimationNodeAnimation.new()
	idle.animation = _or_idle("Idle")
	var sneak_idle := AnimationNodeAnimation.new()
	sneak_idle.animation = _or_idle("Sneak_Idle")
	bt.add_node("idle_stand", idle, Vector2(400, -200))
	bt.add_node("idle_sneak", sneak_idle, Vector2(400, -100))
	bt.add_node("idle", AnimationNodeBlend2.new(), Vector2(600, -150))
	bt.connect_node("idle", 0, "idle_stand")
	bt.connect_node("idle", 1, "idle_sneak")
	bt.add_node("move", AnimationNodeBlend2.new(), Vector2(800, 0))
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "cycle")
	bt.connect_node("output", 0, _add_stance_layer(bt, "move"))
	return bt


## The upper body of a held stance (a raised guard) over `below`, filtered to UPPER_BODY so the
## hips and legs go on walking under it. Returns the node to take the output from.
func _add_stance_layer(bt: AnimationNodeBlendTree, below: String) -> String:
	_has_stance_layer = false
	if anim_player == null or not anim_player.has_animation(STANCE_CLIPS[0]):
		return below
	var pose := AnimationNodeAnimation.new()
	pose.animation = STANCE_CLIPS[0]
	bt.add_node("stance_pose", pose, Vector2(800, 200))
	var layer := AnimationNodeBlend2.new()
	layer.filter_enabled = true
	var clip := anim_player.get_animation(STANCE_CLIPS[0])
	for i in clip.get_track_count():
		var path := clip.track_get_path(i)
		if UPPER_BODY.has(str(path.get_concatenated_subnames())):
			layer.set_filter_path(path, true)
	bt.add_node("stance", layer, Vector2(1000, 0))
	bt.connect_node("stance", 0, below)
	bt.connect_node("stance", 1, "stance_pose")
	_has_stance_layer = true
	return "stance"


## One stride cycle of a clip, stretched onto the shared one-second timeline.
func _cycle_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	n.use_custom_timeline = true
	n.timeline_length = 1.0
	n.stretch_time_scale = true
	n.loop_mode = Animation.LOOP_LINEAR
	return n


func _or_idle(clip: String) -> String:
	return clip if has_clip(clip) else "Idle"


## The ground speed each clip was authored at (the sidecar's `speed`, CONTRACTS §3) and the
## points of the gait blend: the walk twice (as authored, and a third faster before it breaks
## into a run, the way a person walks briskly before they jog), the run, and the sprint.
func _read_gait_speeds() -> void:
	_gait_points.clear()
	_clip_speed.clear()
	_clip_cycle.clear()
	for clip in MOVE_CLIPS:
		if has_clip(clip):
			_clip_speed[clip] = maxf(float((_clip_data.get(clip, {}) as Dictionary).get("speed", 1.0)), 0.1)
			_clip_cycle[clip] = maxf(clip_length(clip), 0.05)
	for clip in ["Walk", "Run", "Sprint"]:
		if not _clip_speed.has(clip):
			continue
		_gait_points.append([clip, float(_clip_speed[clip]), clip.to_lower()])
		if clip == "Walk":
			_gait_points.append([clip, float(_clip_speed[clip]) * BRISK_WALK, "walk_brisk"])
	_gait_points.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))


## Ground speed (m/s) a gait clip plants its feet at, or 0 when the rig has no such clip.
func gait_speed(clip: String) -> float:
	return float(_clip_speed.get(clip, 0.0))


## Metres the body covers in one stride cycle of a clip played as authored.
func _stride(clip: String) -> float:
	return float(_clip_speed.get(clip, 1.0)) * float(_clip_cycle.get(clip, 1.0))


func _is_locomotion_clip(name: String) -> bool:
	return name in ["Idle", "Sneak_Idle"] or name in MOVE_CLIPS


## Drive locomotion with the body's ground velocity in its own frame, in metres per second: x to
## its right, y ahead (behind is negative). The model picks the gait, the blend and the rate that
## keep a planted foot planted; `sneaking` crouches, cross-faded over a quarter of a second.
func set_locomotion(v: Vector2, sneaking: bool = false) -> void:
	_locomotion = v
	_sneaking = sneaking
	if anim_tree == null:
		return
	if _one_shot.is_empty() and _holding.is_empty() and _state_machine != null and _state_machine.get_current_node() != LOCOMOTION_STATE:
		_state_machine.travel(LOCOMOTION_STATE)


## What the Locomotion graph is set to for a ground velocity `v` (m/s, the body's frame) and a
## crouch weight 0..1, keyed by parameter path under the state. Pure, so tests can read it.
## `ground_speed` is the speed the stride has to match, when it is not `v`'s: the blend is
## driven by a smoothed velocity so that it does not shake, but a foot on the ground has to keep
## pace with the ground as it is this tick, not as it was a smoothing constant ago.
func locomotion_params(v: Vector2, sneak_w: float, ground_speed := -1.0) -> Dictionary:
	var speed := v.length()
	var sideways := absf(v.x)
	var ahead := absf(v.y)
	var back := 1.0 if v.y < 0.0 else 0.0
	var right := 1.0 if v.x > 0.0 else 0.0
	var gait_value := speed
	if not _gait_points.is_empty():
		gait_value = clampf(speed, float(_gait_points[0][1]), float(_gait_points[-1][1]))
	# stride per cycle of each branch, and the blend of them as a vector in the body's frame
	var gait := _gait_blend(gait_value)
	var fwd_stride := lerpf(float(gait[0]), _stride("Sneak_Walk"), sneak_w)
	var fwd_rate := lerpf(float(gait[1]), 1.0 / float(_clip_cycle.get("Sneak_Walk", 1.0)), sneak_w)
	var along := lerpf(fwd_stride, -_stride("Walk_Back"), back)
	var along_rate := lerpf(fwd_rate, 1.0 / float(_clip_cycle.get("Walk_Back", 1.0)), back)
	var strafe := _stride("Strafe_R") if right > 0.5 else _stride("Strafe_L")
	var strafe_rate := 1.0 / float(_clip_cycle.get("Strafe_R" if right > 0.5 else "Strafe_L", 1.0))
	# the sideways share is weighted by the strides, not only by the velocity, so the blended
	# stride points exactly where the body goes: with the plain |x| / (|x| + |y|) a diagonal was
	# 4 degrees off and its planted foot slid sideways
	var lateral := 0.0
	if speed > 0.001:
		lateral = sideways * absf(along) / maxf(sideways * absf(along) + ahead * strafe, 0.0001)
	var stride := Vector2(strafe * (1.0 if right > 0.5 else -1.0) * lateral, along * (1.0 - lateral))
	var natural := lerpf(along_rate, strafe_rate, lateral)
	var pace := speed if ground_speed < 0.0 else ground_speed
	var rate := pace / maxf(stride.length(), 0.01)
	rate = clampf(rate, natural * RATE_MIN * smoothstep(MOVING_FROM, MOVING_FULL, pace), natural * RATE_MAX)
	return {
		"gait/blend_position": gait_value,
		"fwd/blend_amount": sneak_w,
		"fb/blend_amount": back,
		"lr/blend_amount": right,
		"dir/blend_amount": lateral,
		"cycle/scale": rate,
		"idle/blend_amount": sneak_w,
		"move/blend_amount": smoothstep(MOVING_FROM, MOVING_FULL, speed),
	}


## [stride m/cycle, cycles/s as authored] of the gait blend at a blend position, interpolated
## between the two points either side of it exactly as the 1D blend space weights them.
func _gait_blend(value: float) -> Array:
	if _gait_points.is_empty():
		return [1.0, 1.0]
	var lo: Array = _gait_points[0]
	var hi: Array = _gait_points[0]
	for p in _gait_points:
		if float(p[1]) <= value:
			lo = p
		if float(p[1]) >= value:
			hi = p
			break
	var w := 0.0
	if float(hi[1]) > float(lo[1]):
		w = (value - float(lo[1])) / (float(hi[1]) - float(lo[1]))
	var s_lo := _stride(str(lo[0]))
	var s_hi := _stride(str(hi[0]))
	var r_lo := 1.0 / float(_clip_cycle.get(str(lo[0]), 1.0))
	var r_hi := 1.0 / float(_clip_cycle.get(str(hi[0]), 1.0))
	return [lerpf(s_lo, s_hi, w), lerpf(r_lo, r_hi, w)]


func _update_locomotion(delta: float) -> void:
	if anim_tree == null:
		return
	_loco_now = _loco_now.lerp(_locomotion, 1.0 - exp(-delta / SPEED_SMOOTH_S))
	_sneak_w = move_toward(_sneak_w, 1.0 if _sneaking else 0.0, delta / SNEAK_BLEND_S)
	var p := locomotion_params(_loco_now, _sneak_w, _locomotion.length())
	var moving := smoothstep(MOVING_FROM, MOVING_FULL, _locomotion.length())
	if _plants_feet():
		# The gait keeps its pose until the body stands and its feet are held; only then does the
		# body settle into the idle over them while the feet step into it (_plant_feet). A
		# one-shot the body stands through goes back to the idle, not to a frozen stride.
		if _locomotion.length() >= FootPlanter.STANDS_BELOW:
			moving = 1.0
		elif _planter.is_planted() or not _one_shot.is_empty() or not _holding.is_empty():
			moving = 0.0
		else:
			moving = _move_w
	_move_w = move_toward(_move_w, moving, delta / MOVE_BLEND_S)
	p["move/blend_amount"] = _move_w
	if _has_stance_layer:
		_stance_w = move_toward(_stance_w, 1.0 if _stance != "" else 0.0, delta / STANCE_BLEND_S)
		p["stance/blend_amount"] = _stance_w
	for key in p:
		anim_tree.set("parameters/%s/%s" % [LOCOMOTION_STATE, key], p[key])


## Play a one-shot clip by name. Returns false if the rig has no such clip.
func play_intent(clip_name: String, blend: float = DEFAULT_BLEND) -> bool:
	if anim_tree == null or _state_machine == null:
		return false
	if not has_clip(clip_name):
		push_warning("HumanoidModel: no clip '%s'" % clip_name)
		return false
	_holding = ""
	if _has_stance_layer and STANCE_CLIPS.has(clip_name):
		# held over the legs in the Locomotion graph, not played as a state of its own
		_stance = clip_name
		_one_shot = ""
		if _state_machine.get_current_node() != LOCOMOTION_STATE:
			_state_machine.travel(LOCOMOTION_STATE)
		return true
	_stance = ""
	if _is_locomotion_clip(clip_name):
		_one_shot = ""
		_state_machine.travel(LOCOMOTION_STATE)
		return true
	# travel() cross-fades along the edge built for it; from another one-shot there is no
	# direct edge, and routing through Locomotion would flash a walk, so that case restarts.
	if _state_machine.get_current_node() == LOCOMOTION_STATE:
		_state_machine.travel(clip_name)
	else:
		_state_machine.start(clip_name, true)
	_one_shot = clip_name
	_one_shot_time = 0.0
	_one_shot_length = clip_length(clip_name)
	speed_scale = 1.0
	_fired.clear()
	return true


func stop_intent() -> void:
	_holding = ""
	_stance = ""
	if _one_shot.is_empty():
		return
	var finished := _one_shot
	_one_shot = ""
	if _state_machine != null:
		_state_machine.travel(LOCOMOTION_STATE)
	clip_finished.emit(finished)


func current_intent() -> String:
	return _one_shot


## The stance held over the legs (a raised guard), or "".
func current_stance() -> String:
	return _stance


func _process(delta: float) -> void:
	_update_locomotion(delta)
	var step := delta * (maxf(speed_scale, 0.0) if not _one_shot.is_empty() else 1.0)
	if anim_tree != null:
		anim_tree.advance(step)
	if not _one_shot.is_empty():
		_advance_one_shot(step)
	_plant_feet(delta)


## The feet held where they stand when the body stops, and stepped into the stance, on the pose
## the clips have just set (FootPlanter). Not on a child's rig: its legs are re-proportioned after
## this, by ChildProportions, and a solve on the grown legs would miss its feet.
func _plant_feet(delta: float) -> void:
	if _plants_feet():
		_planter.update(delta, _locomotion.length(), not _one_shot.is_empty() or not _holding.is_empty())
	elif _planter != null and _planter.is_planted():
		_planter.release()


func _plants_feet() -> bool:
	return plant_feet and _planter != null and _child_mod == null and anim_tree != null


## The feet the planter holds, for tests and the motion studio (null on a rig without legs).
func foot_planter() -> FootPlanter:
	return _planter


func _advance_one_shot(step: float) -> void:
	var prev := _one_shot_time
	_one_shot_time += step
	_fire_events(prev, _one_shot_time)
	if _one_shot_time >= _one_shot_length:
		var finished := _one_shot
		_one_shot = ""
		if HOLD_LAST_POSE.has(finished):
			_holding = finished
		elif _state_machine != null:
			_state_machine.travel(LOCOMOTION_STATE)
		clip_finished.emit(finished)


## The pose a finished one-shot left the body lying in, or "" when it went back to its feet.
func holding_pose() -> String:
	return _holding


## Events come from the clips.json sidecar: everything in [prev, now) fires once.
func _fire_events(prev: float, now: float) -> void:
	var events := clip_events(_one_shot)
	for i in events.size():
		if _fired.has(i):
			continue
		var e: Dictionary = events[i]
		var t := float(e.get("t", 0.0))
		if t >= prev and t < now:
			_fired[i] = true
			clip_event.emit(str(e.get("name", "")))
