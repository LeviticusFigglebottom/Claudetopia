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
##   "antlers":    {"span": m, "tines": n, "colour": "#hex"}: grown from the head, on the helm
##
## The outfits by tag (`OUTFITS`) are the garments the character forge already builds: a hood
## and a jerkin for the road's outlaws, plate for a knight, rags for the dead, a robe for a caster.

## The first tag of a foe's that has an outfit decides it, in this order.
const OUTFITS := [
	["knight", {"torso": "plate_torso", "legs": "trousers", "feet": "greaves", "hands": "gloves", "headgear": "helm",
			"back": "pauldrons"}, {"primary": "6f7378", "secondary": "3c3a36", "leather": "3f3325", "metal": "8a8f94"}],
	["raider", {"torso": "plate_torso", "legs": "kilt", "feet": "greaves", "hands": "gloves", "headgear": "helm",
			"belt": "belt"}, {"primary": "5c5f63", "secondary": "5a4a3a", "leather": "3f3325", "metal": "6f7378"}],
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
## not the rig.
static func dress(model: Node3D, def: Dictionary) -> void:
	if model == null or not model.has_method("apply_appearance"):
		return
	var look := look_for(def)
	if not look.is_empty():
		model.call("apply_appearance", look)
	var held: Variant = def.get("held", null)
	if typeof(held) == TYPE_DICTIONARY:
		hold(model, held)
	var antlers: Variant = def.get("antlers", null)
	if typeof(antlers) == TYPE_DICTIONARY:
		grow_antlers(model, antlers)


## The look a foe is given: its def's own `appearance`, or the outfit of its first tag that has
## one, on a body of its own seed. {} for a def with neither.
static func look_for(def: Dictionary) -> Dictionary:
	var own: Variant = def.get("appearance", null)
	if typeof(own) == TYPE_DICTIONARY and not (own as Dictionary).is_empty():
		return own
	var tags: Array = def.get("tags", [])
	for row in OUTFITS:
		if tags.has(row[0]):
			var seed := absi(str(def.get("id", "")).hash())
			return {"seed": seed, "culture": "vale", "parts": (row[1] as Dictionary).duplicate(),
					"palette": (row[2] as Dictionary).duplicate(), "skin": ["fair", "wheat", "olive", "amber"][seed % 4],
					"hair_colour": ["dark_brown", "black", "auburn", "grey"][(seed >> 3) % 4],
					"build": 0.6 + float((seed >> 5) % 4) * 0.1}
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
	# the model's frame (face +z, up +y) into the skeleton's, and the head's rest pose in it
	var to_skeleton := skeleton.global_transform.affine_inverse() * model.global_transform
	var pose := skeleton.get_bone_global_pose(bone)
	var head := (to_skeleton.affine_inverse() * pose).origin
	var fabric := FabricMesh.new()
	var span := float(spec.get("span", 0.9))
	var tines := int(spec.get("tines", 4))
	var bone_c := Color(str(spec.get("colour", ANTLER_BONE)))
	var tip_c := bone_c.lightened(0.25)
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var base := head + Vector3(side * 0.07, ANTLER_ROOT_M, -0.01)
		var points := antler_beam(base, side, span)
		for i in range(points.size() - 1):
			var r := lerpf(0.028, 0.012, float(i) / float(points.size() - 1))
			_limb(fabric, points[i], points[i + 1], r, bone_c.darkened(0.05 * float(i)), tip_c)
		# the tines, off the beam's upper side, shorter toward the tip
		for t in range(tines):
			var along := 0.3 + 0.62 * float(t) / float(maxi(tines - 1, 1))
			var from := _along(points, along)
			var reach := span * lerpf(0.26, 0.14, along)
			var up := Vector3(side * 0.18, 1.0, lerpf(0.35, -0.2, along)).normalized()
			_limb(fabric, from, from + up * reach, 0.014, bone_c, tip_c)
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
