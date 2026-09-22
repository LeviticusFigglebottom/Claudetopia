class_name HumanoidModel
extends Node3D
## Composes a humanoid from the forge's modular parts and drives its animation.
##
## Loads `humanoid_rig.glb` (rig + default body + every clip from CONTRACTS.md §3), attaches
## whatever parts an `appearance` Dictionary asks for to the one shared `Skeleton3D`, creates
## the `BoneAttachment3D` sockets from CONTRACTS.md §2, and exposes a small intent API over
## an `AnimationTree`:
##
##     model.set_locomotion(Vector2(0.0, 1.0), false)   # forward, not sneaking
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
var _locomotion := Vector2.ZERO
var _sneaking := false
var _part_cache: Dictionary = {}
## Which hair part is actually on the head, which is not always the record's: see COVERS_HEAD.
var hair_worn := ""
static var _meta_cache: Dictionary = {}
var _applying := false      ## guards the appearance_dict setter against re-entering

static var _clip_cache: Dictionary = {}


func _ready() -> void:
	if _rig_root == null:
		build()
	if not appearance_dict.is_empty():
		apply_appearance(appearance_dict)


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
	_clear_parts()
	hair_worn = _hair_to_wear()
	for slot in CharacterAppearance.SLOTS:
		var part_name := hair_worn if slot == "hair" else appearance.part(slot)
		if part_name.is_empty():
			continue
		if slot == "head" and part_name == "default":
			continue
		_add_part(slot, part_name)
	_apply_morality_parts()
	_apply_body_variant()
	var own_head: bool = appearance.part("head").is_empty() or appearance.part("head") == "default"
	_show_default(_default_meshes.get("head"), own_head)
	# a head part brings its own eyes; the rig's pair stayed on underneath, two irises deep
	for eye in _default_eyes:
		_show_default(eye, own_head)
	_apply_colours()
	_apply_fits()
	_apply_proportions()
	appearance_changed.emit()


## The hair the record chose, unless something is covering the crown.
func _hair_to_wear() -> String:
	var chosen := appearance.part("hair")
	if chosen.is_empty():
		return chosen
	for slot in COVERS_HEAD:
		if appearance.part(slot) in COVERS_HEAD[slot]:
			return UNDER_A_HOOD
	return chosen


func _clear_parts() -> void:
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
		copy.set_meta("material", str(_part_meta(slot, part_name).get("material", "")))
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
			elif pal.has(key):
				_dress(mi, pal[key] as Color, kind)
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
func _dress(mi: MeshInstance3D, c: Color, kind: String) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	for i in count:
		var base := mi.mesh.surface_get_material(i)
		var m := (base.duplicate() if base != null else StandardMaterial3D.new()) as BaseMaterial3D
		if m == null:
			continue
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
	return mi.name.to_lower().contains("eye")


## The eyeball keeps its baked texture; only the iris band is recoloured.
func _tint_iris(mi: MeshInstance3D) -> void:
	var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
	var tint := appearance.iris_tint()
	for i in count:
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
## 29 bones. Draping that mesh on adult bones would stretch a child back into an adult and
## look worse than the honest scale it gets now. A real child needs its own rig *and* its
## own bake of the clips (CONTRACTS §2 pins the clips to the default proportions), which is
## a second rig, not a wiring change -- so `body_variant()` still names it, and the model
## still falls back to scaling for it, deliberately and in one place.
const WEARABLE_BODIES := ["slight", "heavy"]


## The body this record wears, when it is not the default one.
##
## `CharacterAppearance.body_variant()` has always named the right one and nothing ever
## loaded it, because `bodies/child`, `heavy` and `slight` each held a 31-bone skeleton and
## no mesh at all: the forge built the geometry and the glTF exporter dropped it as invalid
## without failing the build.
func _apply_body_variant() -> void:
	var variant := appearance.body_variant()
	body_variant_worn = variant if WEARABLE_BODIES.has(variant) and _add_part("body", variant) else ""
	_show_default(_default_meshes.get("body"), body_variant_worn.is_empty())


## Runtime bone scaling would break clips authored on the default proportions
## (CONTRACTS.md §2), so overall size is a uniform scale.
##
## The widening is the fallback and only the fallback. With a real variant on, the shape is
## in the mesh -- baked at the proportions the forge was given -- and scaling the rig as
## well would count the same build twice and hand a heavy villager a second helping of
## width.
func _apply_proportions() -> void:
	var s: float = appearance.height / 1.78
	var wide := 1.0
	if body_variant_worn.is_empty():
		wide = lerpf(0.93, 1.09, clampf(appearance.build, 0.0, 1.0))
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
	sm.add_node(LOCOMOTION_STATE, _build_locomotion_blend(), Vector2(0, 0))
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
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	# the node has to be in the tree before a NodePath to the player can resolve
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	anim_tree = tree
	_state_machine = tree.get("parameters/playback")
	tree.set("parameters/%s/blend_position" % LOCOMOTION_STATE, Vector2.ZERO)


## One transition resource per edge: they are cheap, and `travel` refuses to cross-fade
## between two states that are not connected.
func _transition(xfade: float, mode: int) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = mode
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	t.reset = false
	return t


## Blend space: x is strafe (-1 left .. +1 right), y is forward speed (-1 back .. +1 run),
## with the sneak variants sitting on a second row so `set_locomotion` can cross-fade.
func _build_locomotion_blend() -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.min_space = Vector2(-1.2, -1.2)
	bs.max_space = Vector2(1.2, 2.2)
	bs.snap = Vector2(0.1, 0.1)
	var points := {
		"Idle": Vector2(0, 0),
		"Walk": Vector2(0, 1),
		"Run": Vector2(0, 2),
		"Walk_Back": Vector2(0, -1),
		"Strafe_L": Vector2(-1, 0),
		"Strafe_R": Vector2(1, 0),
		"Sneak_Idle": Vector2(0, -0.001),
		"Sneak_Walk": Vector2(0.001, 0.5),
	}
	for name in points:
		if not has_clip(name):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = name
		bs.add_blend_point(node, points[name], -1, name)
	return bs


func _is_locomotion_clip(name: String) -> bool:
	return name in ["Idle", "Walk", "Run", "Walk_Back", "Strafe_L", "Strafe_R", "Sneak_Idle", "Sneak_Walk"]


## Drive the locomotion blend space. `v.x` strafes (-1..1), `v.y` runs forward (-1..2).
func set_locomotion(v: Vector2, sneaking: bool = false) -> void:
	_locomotion = v
	_sneaking = sneaking
	if anim_tree == null:
		return
	var p := v
	if sneaking:
		p.y = clampf(p.y, 0.0, 0.5)
		p.x = maxf(p.x, 0.001)
	anim_tree.set("parameters/%s/blend_position" % LOCOMOTION_STATE, p)
	if _one_shot.is_empty() and _state_machine != null and _state_machine.get_current_node() != LOCOMOTION_STATE:
		_state_machine.travel(LOCOMOTION_STATE)


## Play a one-shot clip by name. Returns false if the rig has no such clip.
func play_intent(clip_name: String, blend: float = DEFAULT_BLEND) -> bool:
	if anim_tree == null or _state_machine == null:
		return false
	if not has_clip(clip_name):
		push_warning("HumanoidModel: no clip '%s'" % clip_name)
		return false
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
	_fired.clear()
	return true


func stop_intent() -> void:
	if _one_shot.is_empty():
		return
	var finished := _one_shot
	_one_shot = ""
	if _state_machine != null:
		_state_machine.travel(LOCOMOTION_STATE)
	clip_finished.emit(finished)


func current_intent() -> String:
	return _one_shot


func _process(delta: float) -> void:
	if _one_shot.is_empty():
		return
	var prev := _one_shot_time
	_one_shot_time += delta
	_fire_events(prev, _one_shot_time)
	if _one_shot_time >= _one_shot_length:
		var finished := _one_shot
		_one_shot = ""
		if _state_machine != null:
			_state_machine.travel(LOCOMOTION_STATE)
		clip_finished.emit(finished)


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
