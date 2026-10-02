class_name EnemyDress
extends RefCounted
## What a humanoid foe wears, carries and grows.
##
## The rig on its own is the mannequin the forge bakes clothes onto, and every humanoid foe was
## that mannequin: the bandits at the ford, the raiders "in heavy plate", and the Hart of Thorns
## -- "antlered plate, a spear the length of a boat" -- in the middle of the Standing Moot. A foe
## is dressed from its def, and by its tags when the def says nothing:
##
##   "appearance": a person's look (CharacterAppearance, CONTRACTS §7): its parts and palette
##   "held":       {"prop": "hearthvale_spear", "scale": [x, y, z], "grip": 0.35}: a forge prop in
##                 the right hand, standing along the socket's +Y as CONTRACTS §2 has a blade
##                 stand, held `grip` of the way up it
##   "antlers":    {"span": m, "tines": n, "colour": "#hex", "thick": k}: grown from the head, on the helm
##   "carry":      [{"model": "props/x_a" | "weapons/x", "at": socket or bone, "pos": [x, y, z],
##                 "turn": [x, y, z], "scale": s or [x, y, z], "light": {...}, "flame": {...}}]: what a
##                 foe carries about it that is not in its hands -- a bell on its back, a register at
##                 its hip, a lamp on its hat (`carry_one`)
##   "aura":       {"rim": "#hex", "energy": e, "bands": n, "motes": {...}, "light": {...}}: the light
##                 an uncanny foe is seen by (`wear_aura`)
##   "breadth":    the body this much broader than its build makes it, for a foe that stands above
##                 its people in more than height
##
## A foe is drawn at its def's `scale`: the look's height (a person's own, 1.78 m when it says none)
## times the scale. Without it every humanoid foe stood at a person's height whatever its def said,
## and a bell-bearer built for 2.6 m of capsule stood 1.78 m inside it.
##
## The outfits by tag (`OUTFITS`) are the garments the character forge already builds: a hood
## and a jerkin for the road's outlaws, plate for a knight, rags for the dead, a robe for a caster.
## The forge's cuirass has no sleeves, and over bare arms it read as a vest on a labourer, so
## plate is worn as it is worn: over a padded gambeson (the plate in the `back` slot, which lays it
## over the torso's garment), with the pauldrons on the shoulders (the `belt` slot, tinted as
## leather).

## The first tag of a foe's that has an outfit decides it, in this order.
const OUTFITS := [
	["knight", {"torso": "gambeson", "back": "plate_torso", "belt": "pauldrons", "legs": "trousers", "feet": "boots",
			"hands": "gloves", "headgear": "helm"}, {"primary": "6f7378", "secondary": "3c3a36", "leather": "4a4c50", "metal": "8a8f94"}],
	["raider", {"torso": "gambeson", "back": "plate_torso", "belt": "belt", "legs": "kilt", "feet": "boots",
			"hands": "gloves", "headgear": "helm"}, {"primary": "5c5f63", "secondary": "5a4a3a", "leather": "3f3325", "metal": "6f7378"}],
	["caster", {"torso": "robe", "feet": "shoes", "back": "hooded_cloak", "belt": "belt"},
			{"primary": "4e4a56", "secondary": "3a3740", "leather": "3f3325", "metal": "77736d"}],
	["undead", {"torso": "shirt", "legs": "leg_wraps", "feet": "shoes", "back": "ragged_cloak", "hair": "long"},
			{"primary": "5d5a52", "secondary": "4a4740", "leather": "3a342c", "metal": "5f6259"}],
	["poacher", {"torso": "gambeson", "legs": "trousers", "feet": "boots", "back": "hooded_cloak", "belt": "belt", "hair": "short"},
			{"primary": "4f5a36", "secondary": "4a4030", "leather": "3f3325", "metal": "5f6259"}],
	["outlaw", {"torso": "brigandine", "legs": "trousers", "feet": "boots", "hands": "gloves", "belt": "belt", "hair": "cropped"},
			{"primary": "5a3f2c", "secondary": "4a4436", "leather": "3a2c1e", "metal": "6f7378"}],
	["bandit", {"torso": "tunic", "legs": "trousers", "feet": "boots", "back": "hood", "belt": "belt", "hair": "hood_friendly"},
			{"primary": "6b5a3e", "secondary": "4d4a3a", "leather": "4a3525", "metal": "6f7378"}],
	["oroth", {"torso": "robe", "feet": "boots", "back": "shoulder_cape", "hands": "gloves", "headgear": "helm"},
			{"primary": "3f3d45", "secondary": "2c2a30", "leather": "3a342c", "metal": "8a7a4a"}],
	["person", {"torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt", "hair": "tousled"},
			{"primary": "7a6a4e", "secondary": "5a5444", "leather": "4a3525", "metal": "6f7378"}],
	["humanoid", {"torso": "shirt", "legs": "trousers", "feet": "shoes", "belt": "belt", "hair": "short"},
			{"primary": "6a6458", "secondary": "4d4a42", "leather": "4a3525", "metal": "6f7378"}],
]
const PROPS_ROOT := "res://assets/models/props/"
const ANTLER_BONE := "#d9ccb0"


## Dresses `model` (a HumanoidModel) for the foe `def` describes. Does nothing to a body that is
## not the rig. With a `slice` (WorldPace) the clothes go on a few parts a frame.
static func dress(model: Node3D, def: Dictionary, slice: WorldPace.Slice = null) -> void:
	if model == null or not model.has_method("apply_appearance"):
		return
	if "breadth" in model:
		model.set("breadth", float(def.get("breadth", 1.0)))
	var look := sized_look(def)
	if not look.is_empty():
		if slice != null and model is HumanoidModel:
			# stood up while the world is drawn: a few parts a frame, within the frame's budget
			await (model as HumanoidModel).apply_appearance(look, slice)
			if not is_instance_valid(model):
				return
		else:
			model.call("apply_appearance", look)
	var held: Variant = def.get("held", null)
	if typeof(held) == TYPE_DICTIONARY:
		hold(model, held)
	var antlers: Variant = def.get("antlers", null)
	if typeof(antlers) == TYPE_DICTIONARY:
		grow_antlers(model, antlers)
	var carry: Variant = def.get("carry", null)
	if typeof(carry) == TYPE_ARRAY:
		for spec: Variant in carry:
			if typeof(spec) == TYPE_DICTIONARY:
				carry_one(model, spec)
	var aura: Variant = def.get("aura", null)
	if typeof(aura) == TYPE_DICTIONARY:
		wear_aura(model, aura)


## The look a foe is drawn in, at its def's size: `look_for`, its height times the def's `scale`.
static func sized_look(def: Dictionary) -> Dictionary:
	var look := look_for(def)
	var s := float(def.get("scale", 1.0))
	if look.is_empty() or is_equal_approx(s, 1.0):
		return look
	look = look.duplicate(true)
	look["height"] = float(look.get("height", 1.78)) * s
	return look


## Where a dressed foe is armoured, for how a blow on it lands (Enemy.material_at): {"torso": plate
## over the chest, "head": a helm}. Its armour value says how much a blow is stopped; this says
## what the blow is seen to strike: sparks off plate and a helm, blood where there is none.
static func armour_of(def: Dictionary) -> Dictionary:
	var look := look_for(def)
	var parts: Dictionary = look.get("parts", {}) if look.get("parts") is Dictionary else {}
	var plate := false
	for slot in parts:
		if str(parts[slot]) in ["plate_torso"]:
			plate = true
	return {"torso": plate, "head": str(parts.get("headgear", "")) == "helm"}


## The look a foe is given: its def's own `appearance`, or the outfit of its first tag that has
## one, on a body of its own seed. {} for a def with neither.
static func look_for(def: Dictionary) -> Dictionary:
	var own: Variant = def.get("appearance", null)
	if typeof(own) == TYPE_DICTIONARY and not (own as Dictionary).is_empty():
		return own
	var tags: Array = def.get("tags", [])
	for row in OUTFITS:
		if tags.has(row[0]):
			var look_seed := absi(str(def.get("id", "")).hash())
			# a third of the outlaws, poachers and dead are women, as a third of any band would be
			var woman := (look_seed >> 7) % 3 == 0
			var parts := (row[1] as Dictionary).duplicate()
			if woman:
				# her hair is a woman's cut, as her people wear it (a hood's close crop stays), and a
				# plain tunic is her long belted one; armour is armour, fitted to her
				var hair := str(parts.get("hair", ""))
				if hair != "" and hair != "hood_friendly":
					parts["hair"] = str(CharacterAppearance.HAIR_ACROSS.get(hair, hair))
				var torso := str(parts.get("torso", ""))
				if CharacterAppearance.WOMANS_CUT_OF.has(torso) and CharacterAppearance.garment_built(str(CharacterAppearance.WOMANS_CUT_OF[torso])):
					parts["torso"] = str(CharacterAppearance.WOMANS_CUT_OF[torso])
			return {"seed": look_seed, "culture": "vale", "parts": parts,
					"palette": (row[2] as Dictionary).duplicate(), "skin": ["fair", "wheat", "olive", "amber"][look_seed % 4],
					"hair_colour": ["dark_brown", "black", "auburn", "grey"][(look_seed >> 3) % 4],
					"build": 0.6 + float((look_seed >> 5) % 4) * 0.1,
					"feminine": 1.0 if woman else 0.0, "height": 1.72 if woman else 1.78}
	return {}


## Puts the forge prop `spec.prop` in the right hand: along the socket's +Y (CONTRACTS §2: the
## grip is the origin and a blade stands up +Y), scaled by `spec.scale` and slid down it so the
## hand holds it `spec.grip` of the way from its foot. Returns the node, or null.
static func hold(model: Node3D, spec: Dictionary) -> Node3D:
	var slug := str(spec.get("prop", ""))
	var path := "%s%s_a/%s_a.glb" % [PROPS_ROOT, slug, slug]
	if slug == "" or not ResourceLoader.exists(path) or not model.has_method("socket"):
		return null
	var socket: Node3D = model.call("socket", "WeaponR")
	var packed := load(path) as PackedScene
	if socket == null or packed == null:
		return null
	var prop := packed.instantiate() as Node3D
	prop.name = "Held"
	var sv: Array = spec.get("scale", [1.0, 1.0, 1.0])
	var size := Vector3(float(sv[0]), float(sv[1]), float(sv[2]))
	var length := _height_of(prop) * size.y
	prop.transform = Transform3D(Basis.from_scale(size), Vector3(0.0, -length * float(spec.get("grip", 0.35)), 0.0))
	model.call("attach_to_socket", "WeaponR", prop)
	return prop


static func _height_of(node: Node3D) -> float:
	var top := 0.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null:
			top = maxf(top, m.get_aabb().end.y)
	return top if top > 0.0 else 1.0


## Antlers from the top of the head: two beams sweeping up, out and back, each with its tines
## turned up off it, `spec.span` across at the tips. They are built in the model's own frame at
## rest and hung on the head's socket, so they turn and nod with the head from then on.
static func grow_antlers(model: Node3D, spec: Dictionary) -> MeshInstance3D:
	var skeleton: Skeleton3D = model.get("skeleton")
	if skeleton == null or not model.has_method("socket"):
		return null
	var socket: Node3D = model.call("socket", "Head")
	var bone := skeleton.find_bone("Socket.Head")
	if socket == null or bone < 0:
		return null
	# the model's frame (face +z, up +y) into the skeleton's, in the rig's own metres, so they grow
	# with the body a big foe is drawn at; and the head's rest pose in it
	var to_skeleton := rest_frame(model, skeleton)
	var pose := skeleton.get_bone_global_pose(bone)
	var head := (to_skeleton.affine_inverse() * pose).origin
	var fabric := FabricMesh.new()
	var span := float(spec.get("span", 0.9))
	var tines := int(spec.get("tines", 4))
	# how heavy the beams and the tines are against a young hart's ("thick": Ardo's are old and heavy)
	var thick := float(spec.get("thick", 1.0))
	var bone_c := Color(str(spec.get("colour", ANTLER_BONE)))
	var tip_c := bone_c.lightened(0.25)
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var base := head + Vector3(side * 0.07, ANTLER_ROOT_M, -0.01)
		var points := antler_beam(base, side, span)
		for i in range(points.size() - 1):
			var r := lerpf(0.028, 0.012, float(i) / float(points.size() - 1)) * thick
			_limb(fabric, points[i], points[i + 1], r, bone_c.darkened(0.05 * float(i)), tip_c)
		# the tines, off the beam's upper side, shorter toward the tip
		for t in range(tines):
			var along := 0.3 + 0.62 * float(t) / float(maxi(tines - 1, 1))
			var from := _along(points, along)
			var reach := span * lerpf(0.26, 0.14, along)
			var up := Vector3(side * 0.18, 1.0, lerpf(0.35, -0.2, along)).normalized()
			_limb(fabric, from, from + up * reach, 0.014 * thick, bone_c, tip_c)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82
	var mesh := fabric.commit(socket, "antler", mat, "Antlers")
	if mesh != null:
		mesh.transform = pose.affine_inverse() * to_skeleton
	return mesh


## How far above the head's socket the antlers root, in the rig's own metres. The socket sits at
## the crown (1.76 m on the default body, measured); a helm stands a few centimetres proud of it.
const ANTLER_ROOT_M := 0.05


## The points of one beam from `base`: out to the side, up, and swept back, its tip `span` / 2
## off the middle.
static func antler_beam(base: Vector3, side: float, span: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := 5
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(base + Vector3(side * (span * 0.5 - 0.07) * sin(t * PI * 0.5),
				span * 0.62 * t - span * 0.12 * t * t, -span * 0.3 * t * t))
	return out


static func _along(points: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var i := mini(int(f), points.size() - 2)
	return points[i].lerp(points[i + 1], f - float(i))


## A limb of antler from `a` to `b`, `r` thick: a six-sided prism with its ends in `ends`.
static func _limb(fabric: FabricMesh, a: Vector3, b: Vector3, r: float, tint: Color, ends: Color) -> void:
	var d := b - a
	if d.length() < 0.005:
		return
	var x := d.normalized()
	var side := x.cross(Vector3.UP)
	if side.length() < 0.01:
		side = x.cross(Vector3.RIGHT)
	var z := side.normalized()
	var y := z.cross(x)
	fabric.prism("antler", Transform3D(Basis(x, y, z), (a + b) * 0.5), r, d.length() + r, tint, ends, 6)


# --- what a foe carries about it ----------------------------------------------------------------

const MODELS_ROOT := "res://assets/models/"
const AURA_SHADER := preload("res://assets/shaders/boss_aura.gdshader")
## Carried things are tagged, so dressing a body again takes away only what this put there.
const CARRY_TAG := "carried"


## Hangs the forge model `spec.model` ("props/cinderlea_bell_medium_a", "weapons/clapper_bronze") on
## the body, riding the socket or bone `spec.at` ("Back", "HipL", "Lantern", "Head", or a bone:
## "Chest", "Hips", "Spine", "Hand.L"). It is placed as the body stands at rest, in the body's own
## frame and metres -- +X its left, +Y up, +Z ahead, from the ground between its feet, on the rig as
## the forge built it (1.78 m) -- so it grows with the body's scale and goes where the bone goes:
##   "pos":   where the model's origin is, [x, y, z] m
##   "turn":  its turn, degrees about X, Y, Z (applied Y, X, Z), from facing ahead as it was built
##   "scale": a number, or [x, y, z]
##   "light": {"colour": "#hex", "energy": e, "range": m, "pos": [x, y, z] in the model's own frame}
##   "flame": {"colour": "#hex", "size": m, "pos": [x, y, z]}: a small bright bead (a wick, a lamp's
##            glass) drawn unlit
## Returns the node, or null when the model or the place is not there.
static func carry_one(model: Node3D, spec: Dictionary) -> Node3D:
	var skeleton: Skeleton3D = model.get("skeleton")
	if skeleton == null:
		return null
	var path := model_path(str(spec.get("model", "")))
	var node: Node3D = null
	if not path.is_empty():
		var packed := load(path) as PackedScene
		if packed == null:
			return null
		node = packed.instantiate() as Node3D
	else:
		# nothing but a light or a flame, hung in its place
		node = Node3D.new()
	if node == null:
		return null
	var at := str(spec.get("at", "Chest"))
	var holder := _carry_holder(model, skeleton, at)
	if holder == null:
		node.free()
		return null
	node.name = "Carried_%s" % str(spec.get("model", "light")).get_file()
	node.set_meta(CARRY_TAG, true)
	node.add_to_group(CARRY_TAG)
	var bone := skeleton.find_bone(holder.bone_name)
	var rest := skeleton.get_bone_global_rest(bone)
	node.transform = rest.affine_inverse() * rest_frame(model, skeleton) * carry_transform(spec)
	holder.add_child(node)
	light_up(node, spec)
	return node


## Lights what a foe carries or holds, by its spec's `light` (an OmniLight3D: "colour", "energy",
## "range", "pos" in the node's own frame) and `flame` (a small bright bead drawn unlit: "colour",
## "size", "pos"): a lamp's glass, a candle's wick.
static func light_up(node: Node3D, spec: Dictionary) -> void:
	var light: Variant = spec.get("light", null)
	if typeof(light) == TYPE_DICTIONARY:
		var lamp := OmniLight3D.new()
		lamp.name = "CarriedLight"
		lamp.light_color = Color(str(light.get("colour", "#ffb35c")))
		lamp.light_energy = float(light.get("energy", 1.0))
		lamp.omni_range = float(light.get("range", 5.0))
		lamp.shadow_enabled = false
		lamp.position = _vec(light.get("pos", [0.0, 0.0, 0.0]), Vector3.ZERO)
		node.add_child(lamp)
	var flame: Variant = spec.get("flame", null)
	if typeof(flame) == TYPE_DICTIONARY:
		node.add_child(_flame(flame))


## The forge model a carried thing names, as a path ("" when it names none or it is not built).
static func model_path(model_name: String) -> String:
	if model_name.is_empty():
		return ""
	var path := "%s%s/%s.glb" % [MODELS_ROOT, model_name, model_name.get_file()]
	return path if ResourceLoader.exists(path) else ""


## The body's rest frame in the skeleton's: the body's own axes (+X its left, +Y up, +Z ahead) and
## the rig's metres, whatever scale the rig is drawn at.
static func rest_frame(model: Node3D, skeleton: Skeleton3D) -> Transform3D:
	var to_skeleton := skeleton.global_transform.affine_inverse() * model.global_transform
	return Transform3D(to_skeleton.basis.orthonormalized(), Vector3.ZERO)


## A carry spec's place and turn and scale, in the body's rest frame.
static func carry_transform(spec: Dictionary) -> Transform3D:
	var turn := _vec(spec.get("turn", [0.0, 0.0, 0.0]), Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z)))
	var sc: Variant = spec.get("scale", 1.0)
	var size := _vec(sc, Vector3.ONE) if typeof(sc) == TYPE_ARRAY else Vector3.ONE * float(sc)
	return Transform3D(basis.scaled_local(size), _vec(spec.get("pos", [0.0, 1.0, 0.0]), Vector3(0.0, 1.0, 0.0)))


## The socket `at` names, or a BoneAttachment3D of its own on the bone it names.
static func _carry_holder(model: Node3D, skeleton: Skeleton3D, at: String) -> BoneAttachment3D:
	if model.has_method("socket"):
		var s: BoneAttachment3D = model.call("socket", at)
		if s != null:
			return s
	var bone := skeleton.find_bone(at)
	if bone < 0:
		return null
	var holder_name := "Carry_%s" % at.replace(".", "_")
	var holder := skeleton.get_node_or_null(holder_name) as BoneAttachment3D
	if holder == null:
		holder = BoneAttachment3D.new()
		holder.name = holder_name
		holder.bone_name = at
		skeleton.add_child(holder)
	return holder


static func _flame(spec: Dictionary) -> MeshInstance3D:
	var bead := MeshInstance3D.new()
	bead.name = "CarriedFlame"
	var sphere := SphereMesh.new()
	var r := float(spec.get("size", 0.025))
	sphere.radius = r
	sphere.height = r * 2.6
	sphere.radial_segments = 8
	sphere.rings = 4
	bead.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(str(spec.get("colour", "#ffd08a")))
	bead.material_override = mat
	bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bead.position = _vec(spec.get("pos", [0.0, 0.0, 0.0]), Vector3.ZERO)
	return bead


static var _dot: GradientTexture2D = null


## A round spot, white in the middle and gone at its edge, shared by every mote.
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.45, Color(1.0, 1.0, 1.0, 0.55))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot


static func _vec(v: Variant, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


# --- the light an uncanny foe is seen by ------------------------------------------------------

## An uncanny foe's light (`aura`): its silhouette lit from the edges in its own colour, breathing
## (boss_aura.gdshader, laid over every mesh it wears as the overlay, or after the one it has), and
## if the spec says so, motes about it and a light it casts.
##   "rim": "#hex", "energy": e, "power": p, "pulse": 0..1, "bands": rings a metre, "rise": m/s, "fill": share
##   "motes": {"colour": "#hex", "count": n, "size": m, "rise": m/s, "spread": m, "height": m, "mix": true}
##            ("mix": drawn over, not added on: dark motes, smoke, ash)
##   "light": {"colour": "#hex", "energy": e, "range": m, "height": m}
static func wear_aura(model: Node3D, spec: Dictionary) -> void:
	var mat := aura_material(spec)
	if mat != null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.has_meta(CARRY_TAG) or m.name == "CarriedFlame":
				continue
			_overlay(m, mat)
	var motes: Variant = spec.get("motes", null)
	if typeof(motes) == TYPE_DICTIONARY:
		model.add_child(aura_motes(motes))
	var light: Variant = spec.get("light", null)
	if typeof(light) == TYPE_DICTIONARY:
		var lamp := OmniLight3D.new()
		lamp.name = "AuraLight"
		lamp.light_color = Color(str(light.get("colour", spec.get("rim", "#9fd8c8"))))
		lamp.light_energy = float(light.get("energy", 0.6))
		lamp.omni_range = float(light.get("range", 5.0))
		lamp.shadow_enabled = false
		lamp.position = Vector3(0.0, float(light.get("height", 1.4)), 0.3)
		model.add_child(lamp)


## The overlay an aura spec draws with, or null when it has no rim.
static func aura_material(spec: Dictionary) -> ShaderMaterial:
	if not spec.has("rim"):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = AURA_SHADER
	var c := Color(str(spec["rim"]))
	mat.set_shader_parameter("rim", c)
	mat.set_shader_parameter("energy", float(spec.get("energy", 1.0)))
	mat.set_shader_parameter("power", float(spec.get("power", 2.4)))
	mat.set_shader_parameter("pulse", float(spec.get("pulse", 0.35)))
	mat.set_shader_parameter("bands", float(spec.get("bands", 0.0)))
	mat.set_shader_parameter("rise", float(spec.get("rise", 0.5)))
	mat.set_shader_parameter("fill", float(spec.get("fill", 0.0)))
	return mat


## Lays `mat` over a mesh: as its overlay, or after the overlay it already has (a tattoo's).
static func _overlay(mi: MeshInstance3D, mat: Material) -> void:
	var over := mi.material_overlay
	if over == null:
		mi.material_overlay = mat
		return
	while over.next_pass != null and over.next_pass != mat:
		over = over.next_pass
	if over != mat and over.next_pass == null:
		# its own copy: the overlay may be shared with other bodies
		var mine := mi.material_overlay.duplicate() as Material
		mi.material_overlay = mine
		var tail := mine
		while tail.next_pass != null:
			tail = tail.next_pass
		tail.next_pass = mat


## Motes drifting up round the body: CPU particles (they draw the same on every renderer), each a
## small soft square turned to the eye.
static func aura_motes(spec: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "AuraMotes"
	p.amount = int(spec.get("count", 24))
	p.lifetime = float(spec.get("life", 2.6))
	p.preprocess = p.lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var spread := float(spec.get("spread", 0.45))
	var tall := float(spec.get("height", 1.8))
	p.emission_box_extents = Vector3(spread, tall * 0.5, spread)
	p.position = Vector3(0.0, tall * 0.5, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 25.0
	p.gravity = Vector3(0.0, float(spec.get("rise", 0.25)), 0.0)
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.12
	var size := float(spec.get("size", 0.04))
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	var ramp := Gradient.new()
	var c := Color(str(spec.get("colour", "#bfe8dc")))
	ramp.set_color(0, Color(c, 0.0))
	ramp.set_color(1, Color(c, 0.0))
	ramp.add_point(0.25, Color(c, 1.0))
	ramp.add_point(0.7, Color(c, 0.8))
	p.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	# a soft round mote, not a square of colour
	mat.albedo_texture = _soft_dot()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not bool(spec.get("mix", false)):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	return p
