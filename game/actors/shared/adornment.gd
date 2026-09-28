class_name Adornment
extends RefCounted
## Tattoos and jewellery on a HumanoidModel (triage 48). The choices are CharacterAppearance's
## (`tattoos`, `jewellery`); this lays them on whatever body, head and hair the model is wearing.
##
## **Tattoos** are drawn, not modelled. On the face they are face_marks.gdshader's, in the head's face
## coordinates (its UV2, as the paint and scars are; the neck is the head's). On the body they are
## body_marks.gdshader's, the body's material_overlay: a body's UVs are laid out again by every build,
## so a tattoo is placed on the rig's bones instead -- a frame on the forearm's axis, the spine's, the
## back of the hand -- read off the body's own skin binds, and the body carries its bind-pose position
## as CUSTOM0 (tools/forge/body_coords.py). Round a limb the design wraps, on the back it lies flat.
## Only a body with a tattoo has the overlay; a sleeve over it covers it, as a sleeve would.
##
## **Jewellery** is forged (tools/forge/gen_jewellery.py: studs, hoops, drops, nose and lip rings,
## torcs, beads, pendants, brooches, finger rings, bracelets, circlets, hair pins, braid rings) and laid
## at a landmark found on the mesh it is worn on: an ear's lobe, the side of a nostril and the lower lip
## by the head's face coordinates, a finger and a wrist on the body's hand and forearm bones, the neck
## and the chest by the body's surface round the spine, the hair's back and a braid's end on the hair.
## Every piece takes the bone weights of the vertex it sits on, and that vertex's moves under the face's
## sliders and the hand's grip as morph targets of its own, so an earring goes with an ear made larger,
## and a ring with a closing hand. Everything a person wears is merged into one skinned mesh (one draw),
## lit by jewellery.gdshader from what each vertex is made of, and not drawn past SEEN_TO.

const SLOT := "jewellery"
const ROOT := "res://assets/models/characters/jewellery/"
const BODY_MARKS_SHADER := preload("res://assets/shaders/body_marks.gdshader")
const JEWELLERY_SHADER := preload("res://assets/shaders/jewellery.gdshader")
## Metres past which a person's jewellery is not drawn: a ring is a pixel at ten.
const SEEN_TO := 14.0
## What each stuff looks like: [colour, metallic, roughness].
const STUFF := {
	"iron": [Color("5d5e60"), 0.85, 0.55], "bronze": [Color("a8733f"), 1.0, 0.38],
	"silver": [Color("cfcfcc"), 1.0, 0.26], "gold": [Color("dcaa4e"), 1.0, 0.30],
	"bone": [Color("d6caa9"), 0.0, 0.55], "glass": [Color("3d7f95"), 0.0, 0.08],
}
const CORD := [Color("3b2a1d"), 0.0, 0.75]
## Glass comes in these, one to a person (by their seed).
const GLASS_SHADES := ["3d7f95", "2f5fa8", "4c8a4a", "b0702a", "8a2f3a", "d8d2b0"]
## What a piece of metal is set with: a glass bead, or on bone and glass pieces the same again.
const ACCENT_OF := {"iron": "glass", "bronze": "glass", "silver": "glass", "gold": "glass", "bone": "bone", "glass": "glass"}

## A face tattoo's box in face coordinates (centre x, centre y, half-width, half-height, metres; + is
## the head's left; a negative half-width mirrors the design for the other side).
const FACE_BOXES := {
	"cheek_l": Vector4(0.044, -0.037, 0.013, 0.016), "cheek_r": Vector4(-0.044, -0.037, -0.013, 0.016),
	"brow": Vector4(0.0, 0.048, 0.020, 0.012), "chin": Vector4(0.0, -0.113, 0.015, 0.011),
	"neck": Vector4(0.128, -0.178, 0.032, 0.030),
}

static var _carriers: Dictionary = {}
static var _pieces: Dictionary = {}
static var _material: ShaderMaterial = null


# -- tattoos --------------------------------------------------------------------------------------

## The face overlay's tattoo uniforms for this record (face_marks.gdshader `tattoo0`, `tattoo1`).
static func face_tattoo_params(a: CharacterAppearance) -> Dictionary:
	var out := {"tattoo0": 0, "tattoo1": 0}
	var i := 0
	for t in a.face_tattoos():
		if i >= CharacterAppearance.MOST_FACE_TATTOOS:
			break
		var ink := CharacterAppearance.ink_colour(str(t["ink"]))
		out["tattoo%d" % i] = CharacterAppearance.TATTOO_DESIGNS.find(str(t["design"]))
		out["tattoo%d_box" % i] = FACE_BOXES.get(str(t["on"]), Vector4(0, 0, 0.01, 0.01))
		out["tattoo%d_ink" % i] = Color(ink.r, ink.g, ink.b, float(t["fade"]))
		i += 1
	return out


## Puts this record's body tattoos on a body mesh as its overlay, or takes the overlay off.
static func dress_body(mi: MeshInstance3D, a: CharacterAppearance, skel: Skeleton3D) -> void:
	if mi == null:
		return
	var params := body_tattoo_params(a, mi, skel)
	if params.is_empty():
		if mi.material_overlay is ShaderMaterial and (mi.material_overlay as ShaderMaterial).shader == BODY_MARKS_SHADER:
			mi.material_overlay = null
		return
	var m := mi.material_overlay as ShaderMaterial
	if m == null or m.shader != BODY_MARKS_SHADER:
		m = ShaderMaterial.new()
		m.shader = BODY_MARKS_SHADER
		mi.material_overlay = m
	for key in params:
		m.set_shader_parameter(key, params[key])


## The body overlay's uniforms for this record on this body: each tattoo's design, its frame (bind
## space -> the design's), its shape and its ink. {} when there is nothing to draw, or the body has no
## rest coordinates to draw it by.
static func body_tattoo_params(a: CharacterAppearance, mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	var list := a.body_tattoos()
	if list.is_empty() or mi == null or mi.mesh == null:
		return {}
	if (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) == 0:
		return {}
	var c := carrier(mi, skel)
	if c.is_empty():
		return {}
	var out := {}
	for i in CharacterAppearance.MOST_BODY_TATTOOS:
		out["design%d" % i] = 0
	var i := 0
	for t in list:
		if i >= CharacterAppearance.MOST_BODY_TATTOOS:
			break
		var place := tattoo_frame(c, str(t["on"]))
		if place.is_empty():
			continue
		var ink := CharacterAppearance.ink_colour(str(t["ink"]))
		out["design%d" % i] = CharacterAppearance.TATTOO_DESIGNS.find(str(t["design"]))
		out["frame%d" % i] = Projection((place["frame"] as Transform3D).affine_inverse())
		out["shape%d" % i] = place["shape"]
		out["ink%d" % i] = Color(ink.r, ink.g, ink.b, float(t["fade"]))
		i += 1
	return out if i > 0 else {}


## Where a body tattoo goes on this body: {"frame": the design's frame in the body's bind space (+Y up
## the design, +Z out of the skin through it), "shape": (radius round the axis or 0 for flat,
## half-width, half-height, stroke)}; {} when the body has not the bones for it.
static func tattoo_frame(c: Dictionary, place: String) -> Dictionary:
	var bones: Dictionary = c["frames"]
	var side := "L" if place.ends_with("_l") else "R"
	var sx := 1.0 if side == "L" else -1.0
	var up := Vector3.UP
	match place.trim_suffix("_l").trim_suffix("_r"):
		"forearm", "upper_arm", "hand":
			var from_bone: String = {"forearm": "LowerArm", "upper_arm": "UpperArm", "hand": "Hand"}[place.trim_suffix("_l").trim_suffix("_r")]
			var to_bone: String = {"forearm": "Hand", "upper_arm": "LowerArm", "hand": ""}[place.trim_suffix("_l").trim_suffix("_r")]
			var a_name := "%s.%s" % [from_bone, side]
			if not bones.has(a_name):
				return {}
			var a: Vector3 = (bones[a_name] as Transform3D).origin
			var down: Vector3
			var length: float
			if to_bone.is_empty():
				down = (bones[a_name] as Transform3D).basis.y.normalized()
				length = 0.13
			else:
				var b_name := "%s.%s" % [to_bone, side]
				if not bones.has(b_name):
					return {}
				var b: Vector3 = (bones[b_name] as Transform3D).origin
				down = (b - a).normalized()
				length = a.distance_to(b)
			# the design's up is back along the limb, towards the body; its face is the back of the
			# arm and hand (in the rest pose up and out, which a hanging arm turns outwards)
			var y := -down
			var z := (up - y * up.dot(y)).normalized()
			if place.begins_with("hand"):
				var centre := a + down * 0.068
				var d := _surface(c, _near(c, ["Hand." + side], centre, 0.08), centre, z, 0.012, 0.018)
				return {"frame": _frame(centre + z * d, y, z), "shape": Vector4(0.0, 0.021, 0.024, 0.08)}
			var t := 0.55 if place.begins_with("forearm") else 0.5
			var mid := a + down * length * t
			var bone_names: Array = [a_name]
			var r := _radius(c, _near(c, bone_names, mid, 0.12), mid, down, 0.012, 0.09, 0.036)
			var hw := 0.030 if place.begins_with("forearm") else 0.034
			var hh := 0.055 if place.begins_with("forearm") else 0.045
			return {"frame": _frame(mid, y, z), "shape": Vector4(r, hw, hh, 0.07)}
		"collarbone", "back":
			if not bones.has("Chest"):
				return {}
			var chest: Vector3 = (bones["Chest"] as Transform3D).origin
			var back := place == "back"
			var out := Vector3(0, 0, -1) if back else Vector3(sx * 0.55, 0.0, 0.84).normalized()
			var centre := chest + up * (0.115 if back else 0.15)
			var idx := _near(c, ["Chest", "Spine", "Neck", "Shoulder.L", "Shoulder.R"], centre, 0.2)
			var d := _surface(c, idx, centre, out, 0.02, 0.12)
			var shape := Vector4(0.0, 0.085, 0.09, 0.05) if back else Vector4(0.0, 0.045, 0.024, 0.08)
			return {"frame": _frame(centre + out * d, up, out), "shape": shape}
	return {}


## A frame at `origin` with +Y `y` and +Z `z` (made square to y), +X = y x z.
static func _frame(origin: Vector3, y: Vector3, z: Vector3) -> Transform3D:
	var yy := y.normalized()
	var zz := (z - yy * z.dot(yy)).normalized()
	return Transform3D(Basis(yy.cross(zz), yy, zz), origin)


# -- the meshes things are worn on ----------------------------------------------------------------

## What a skinned mesh is, read once: its vertices, normals, face coordinates, bone weights, morph
## targets (as moves), its binds as bone frames in its own space, and its vertices by bone.
static func carrier(mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	if mi == null or not (mi.mesh is ArrayMesh) or mi.skin == null:
		return {}
	var mesh := mi.mesh as ArrayMesh
	var key := "%d|%d" % [mesh.get_instance_id(), mi.skin.get_instance_id()]
	if _carriers.has(key):
		return _carriers[key]
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	if v.is_empty() or bones.is_empty():
		return {}
	var per := int(float(bones.size()) / float(v.size()))
	var skin := mi.skin
	var names := PackedStringArray()
	var frames := {}
	for i in skin.get_bind_count():
		var n := str(skin.get_bind_name(i))
		if n.is_empty() and skel != null and skin.get_bind_bone(i) >= 0:
			n = skel.get_bone_name(skin.get_bind_bone(i))
		names.append(n)
		frames[n] = skin.get_bind_pose(i).affine_inverse()
	var by_bone := {}
	var dom := PackedInt32Array()
	dom.resize(v.size())
	for i in v.size():
		var best := 0
		for k in range(1, per):
			if weights[i * per + k] > weights[i * per + best]:
				best = k
		var b := bones[i * per + best]
		dom[i] = b
		var n := names[b] if b < names.size() else ""
		if not by_bone.has(n):
			by_bone[n] = []
		(by_bone[n] as Array).append(i)
	# packed, once each list is whole (a packed array appended through a cast is a copy)
	for n in by_bone.keys():
		by_bone[n] = PackedInt32Array(by_bone[n])
	var shapes := {}
	var blend := mesh.surface_get_blend_shape_arrays(0)
	for s in mesh.get_blend_shape_count():
		var target: PackedVector3Array = (blend[s] as Array)[Mesh.ARRAY_VERTEX]
		var moves := PackedVector3Array()
		moves.resize(v.size())
		for i in v.size():
			moves[i] = target[i] - v[i]
		shapes[str(mesh.get_blend_shape_name(s))] = moves
	var uv2 := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV2] != null:
		uv2 = arrays[Mesh.ARRAY_TEX_UV2]
	var c := {"v": v, "n": arrays[Mesh.ARRAY_NORMAL], "uv2": uv2, "bones": bones, "weights": weights, "per": per,
		"skin": skin, "names": names, "frames": frames, "by_bone": by_bone, "shapes": shapes}
	_carriers[key] = c
	return c


## The vertices of `c` weighted most to any of `bone_names` (all of them for an empty list) and within
## `reach` of `at`.
static func _near(c: Dictionary, bone_names: Array, at: Vector3, reach: float) -> PackedInt32Array:
	var v: PackedVector3Array = c["v"]
	var out := PackedInt32Array()
	var r2 := reach * reach
	if bone_names.is_empty():
		for i in v.size():
			if v[i].distance_squared_to(at) < r2:
				out.append(i)
		return out
	for n in bone_names:
		var list: PackedInt32Array = (c["by_bone"] as Dictionary).get(n, PackedInt32Array())
		for i in list:
			if v[i].distance_squared_to(at) < r2:
				out.append(i)
	return out


## How far out along `out` from `centre` the surface is, within `width` of that line (`fallback` if
## nothing is there).
static func _surface(c: Dictionary, idx: PackedInt32Array, centre: Vector3, out: Vector3, width: float, fallback: float) -> float:
	var v: PackedVector3Array = c["v"]
	var best := -1.0
	for i in idx:
		var d := v[i] - centre
		var along := d.dot(out)
		if along <= 0.0:
			continue
		if (d - out * along).length() < width:
			best = maxf(best, along)
	return best if best > 0.0 else fallback


## The radius of the limb round `axis` at `at`: most of the way out of what lies within `slab` along
## it (and `most` from it); `fallback` if nothing does.
static func _radius(c: Dictionary, idx: PackedInt32Array, at: Vector3, axis: Vector3, slab: float, most: float, fallback: float) -> float:
	var v: PackedVector3Array = c["v"]
	var rs: Array[float] = []
	for i in idx:
		var d := v[i] - at
		var along := d.dot(axis)
		if absf(along) > slab:
			continue
		var r := (d - axis * along).length()
		if r < most:
			rs.append(r)
	if rs.size() < 3:
		return fallback
	rs.sort()
	return rs[int(rs.size() * 0.85)]


static func _nearest(c: Dictionary, idx: PackedInt32Array, p: Vector3) -> int:
	var v: PackedVector3Array = c["v"]
	var best := -1
	var bd := INF
	for i in idx:
		var d := v[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## The head's face coordinates of vertex i (metres across, + to the left, and up from the eye line).
static func _face_at(c: Dictionary, i: int) -> Vector2:
	var uv: Vector2 = (c["uv2"] as PackedVector2Array)[i]
	return Vector2((uv.x - 0.5) * 0.40, (0.5 - uv.y) * 0.40)


## The eye line's height on a head (every vertex's height less its face coordinate's).
static func _eye_y(c: Dictionary) -> float:
	var v: PackedVector3Array = c["v"]
	var i := int(v.size() * 0.5)
	return v[i].y - _face_at(c, i).y


# -- jewellery ------------------------------------------------------------------------------------

## A forged piece's mesh arrays [vertices, normals, colours, indices], read once.
static func piece(name: String) -> Array:
	if _pieces.has(name):
		return _pieces[name]
	var path := "%s%s/%s.glb" % [ROOT, name, name]
	var out: Array = []
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		var inst := scene.instantiate() if scene != null else null
		if inst != null:
			for n in inst.find_children("*", "MeshInstance3D", true, false):
				var m := (n as MeshInstance3D).mesh
				if m != null:
					var a := m.surface_get_arrays(0)
					out = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_COLOR], a[Mesh.ARRAY_INDEX]]
					break
			inst.free()
	_pieces[name] = out
	return out


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = JEWELLERY_SHADER
	return _material


## The merged mesh of everything this model's record wears, skinned to its skeleton, or null for
## none (or nothing that could be laid on what the model is wearing).
static func build(model: HumanoidModel) -> MeshInstance3D:
	var a := model.appearance
	if a.jewellery.is_empty() or model.skeleton == null:
		return null
	var skel := model.skeleton
	var head := carrier(model.worn_mesh("head"), skel)
	var body := carrier(model.worn_mesh("body"), skel)
	var hair := carrier(model.worn_mesh("hair"), skel)
	var covered := model.head_covered()
	var gloved := not a.part("hands").is_empty()
	# what is worn over the neck and the chest, as it is cut for this body: a necklace lies on it
	var over: Array = []
	for slot in ["torso", "back"]:
		var g := carrier(model.worn_mesh(slot), skel)
		if not g.is_empty():
			over.append(_fitted(g, model.body_variant_worn))
	var b := _Merge.new()
	var shade := Color(str(GLASS_SHADES[absi(hash("%d|glass" % a.seed)) % GLASS_SHADES.size()]))
	for j in a.jewellery:
		var kind := str(j["kind"])
		var on := str(j["on"])
		var stuff := _stuff(str(j["metal"]), shade)
		var accent := _stuff(str(ACCENT_OF.get(str(j["metal"]), "glass")), shade)
		match kind:
			"stud", "hoop", "drop":
				if covered or head.is_empty():
					continue
				for s in _sides(on):
					var lobe := _lobe(head, s)
					if lobe >= 0:
						var p: Vector3 = (head["v"] as PackedVector3Array)[lobe] + Vector3(-s * 0.0006, 0.0035, 0.0)
						b.put(piece(kind), Transform3D(_basis(Vector3.UP, Vector3(s, 0, 0)), p), stuff, accent, head, lobe)
			"nose_stud", "nose_ring":
				var ala := _nostril(head)
				if ala >= 0:
					var out := Vector3(1.0, 0.0, 0.55).normalized()
					var p: Vector3 = (head["v"] as PackedVector3Array)[ala] - out * 0.0004
					b.put(piece(kind), Transform3D(_basis(Vector3.UP, out), p), stuff, accent, head, ala)
			"lip_ring":
				var lip := _lower_lip(head)
				if lip >= 0:
					var p: Vector3 = (head["v"] as PackedVector3Array)[lip] + Vector3(0, 0.0015, -0.0005)
					b.put(piece(kind), Transform3D(_basis(Vector3.UP, Vector3(0, 0, 1)), p), stuff, accent, head, lip)
			"circlet":
				if covered or head.is_empty():
					continue
				_circlet(b, head, stuff, accent, a)
			"hair_pin":
				if covered or hair.is_empty() or head.is_empty():
					continue
				_hair_pins(b, hair, head, stuff, accent)
			"braid_rings":
				if covered or hair.is_empty() or head.is_empty():
					continue
				_braid_rings(b, hair, head, stuff, accent)
			"ring":
				if gloved or body.is_empty():
					continue
				for s in _sides(on):
					_ring(b, body, s, stuff, accent)
			"bracelet":
				if body.is_empty():
					continue
				for s in _sides(on):
					_bracelet(b, body, s, stuff, accent)
			"torc":
				if not body.is_empty():
					_torc(b, body, head, stuff, accent, over)
			"beads", "pendant":
				if not body.is_empty():
					# a necklace lies on the tunic, and under the cloak
					_necklace(b, body, head, kind, stuff, accent, over.slice(0, 1) if not a.part("torso").is_empty() else [])
			"brooch":
				if not body.is_empty():
					_brooch(b, body, stuff, accent, over)
	return b.finish(skel)


static func _stuff(name: String, shade: Color) -> Array:
	var s: Array = (STUFF.get(name, STUFF["bronze"]) as Array).duplicate()
	if name == "glass":
		s[0] = shade
	return s


## +1 for the left, -1 for the right, both for the plural ("ears", "hands", "wrists").
static func _sides(on: String) -> Array:
	if on.ends_with("_l"):
		return [1.0]
	if on.ends_with("_r"):
		return [-1.0]
	return [1.0, -1.0]


## A frame whose +Y is `up` and +Z `out` (square to it).
static func _basis(up: Vector3, out: Vector3) -> Basis:
	var z := out.normalized()
	var y := (up - z * up.dot(z)).normalized()
	return Basis(y.cross(z), y, z)


## The vertex of `head` on side s (+1 left, -1 right, 0 either) that `shape` moves furthest, among
## those `keep` passes; -1 when the head has not the shape. The face's sliders say what is what on any
## head: the ear is what the ear slider moves, the nostril's wing what the nose's width moves.
static func _moved_most(head: Dictionary, shape: String, s: float, keep: Callable) -> int:
	var moves: PackedVector3Array = (head["shapes"] as Dictionary).get(shape, PackedVector3Array())
	if moves.is_empty():
		return -1
	var v: PackedVector3Array = head["v"]
	var best := -1
	var most := 0.0002
	for i in v.size():
		if s != 0.0 and s * v[i].x <= 0.0:
			continue
		var d := moves[i].length()
		if d > most and keep.call(i):
			most = d
			best = i
	return best


## The ear's lobe on side s: the lowest point of what the ear slider moves (the ear itself), or else
## the lowest of the ear's outermost vertices below the eye line.
static func _lobe(head: Dictionary, s: float) -> int:
	if head.is_empty() or (head["uv2"] as PackedVector2Array).is_empty():
		return -1
	var v: PackedVector3Array = head["v"]
	var ear: PackedVector3Array = (head["shapes"] as Dictionary).get("face_ear_size", PackedVector3Array())
	if not ear.is_empty():
		var lowest := -1
		for i in v.size():
			if s * v[i].x < 0.05 or ear[i].length() < 0.0008:
				continue
			if lowest < 0 or v[i].y < v[lowest].y:
				lowest = i
		if lowest >= 0:
			return lowest
	var cand: Array[int] = []
	var widest := 0.0
	for i in v.size():
		if s * v[i].x < 0.056:
			continue
		var f := _face_at(head, i)
		if f.y < -0.065 or f.y > -0.018:
			continue
		cand.append(i)
		widest = maxf(widest, s * v[i].x)
	var best := -1
	var low := INF
	for i in cand:
		if s * v[i].x >= widest - 0.011 and _face_at(head, i).y < low:
			low = _face_at(head, i).y
			best = i
	return best


## The left nostril's wing: what the nose's width moves furthest, or else its widest point a little
## above the base of the nose.
static func _nostril(head: Dictionary) -> int:
	if head.is_empty() or (head["uv2"] as PackedVector2Array).is_empty():
		return -1
	var v: PackedVector3Array = head["v"]
	var wing := _moved_most(head, "face_nose_width", 1.0, func(i: int) -> bool:
			var f := _face_at(head, i)
			return f.y < -0.030 and f.y > -0.060 and f.x < 0.03)
	if wing >= 0:
		return wing
	var front := -INF
	for i in v.size():
		front = maxf(front, v[i].z)
	var best := -1
	var wide := -INF
	for i in v.size():
		var f := _face_at(head, i)
		if f.y < -0.054 or f.y > -0.040 or f.x < 0.004 or f.x > 0.03 or v[i].z < front - 0.030:
			continue
		if v[i].x > wide:
			wide = v[i].x
			best = i
	return best


## The lower lip, a little to the left of the middle: its most forward point.
static func _lower_lip(head: Dictionary) -> int:
	if head.is_empty() or (head["uv2"] as PackedVector2Array).is_empty():
		return -1
	var v: PackedVector3Array = head["v"]
	var best := -1
	var fwd := -INF
	for i in v.size():
		var f := _face_at(head, i)
		if f.y < -0.096 or f.y > -0.078 or absf(f.x - 0.009) > 0.005:
			continue
		if v[i].z > fwd:
			fwd = v[i].z
			best = i
	return best


static func _circlet(b: _Merge, head: Dictionary, stuff: Array, accent: Array, a: CharacterAppearance) -> void:
	var v: PackedVector3Array = head["v"]
	var sum := Vector3.ZERO
	var n := 0
	var ring: Array[int] = []
	for i in v.size():
		var f := _face_at(head, i)
		if f.y > 0.046 and f.y < 0.060:
			ring.append(i)
			sum += v[i]
			n += 1
	if n < 8:
		return
	var centre := sum / n
	var rx := 0.0
	var rz := 0.0
	var front := -1
	for i in ring:
		rx = maxf(rx, absf(v[i].x - centre.x))
		rz = maxf(rz, absf(v[i].z - centre.z))
		if front < 0 or v[i].z > v[front].z:
			front = i
	var hair := a.part("hair")
	var room := 0.003 if hair.is_empty() or hair in CharacterAppearance.CLOSE_HAIR else 0.011
	var sc := Vector3(rx + room, (rx + rz) * 0.5, rz + room)
	b.put(piece("circlet"), Transform3D(Basis.from_scale(sc), centre), stuff, accent, head, front)


static func _hair_pins(b: _Merge, hair: Dictionary, head: Dictionary, stuff: Array, accent: Array) -> void:
	var v: PackedVector3Array = hair["v"]
	var eye := _eye_y(head)
	var best := -1
	for i in v.size():
		if v[i].y < eye - 0.05 or v[i].y > eye + 0.10:
			continue
		if best < 0 or v[i].z < v[best].z:
			best = i
	if best < 0:
		return
	var centre := Vector3(0.0, eye + 0.01, -0.01)
	var out := (v[best] - centre).normalized()
	for s in [-1.0, 1.0]:
		var o := out.rotated(Vector3.UP, s * 0.35).rotated(Vector3.RIGHT, -0.25)
		var p := v[best] + Vector3(s * 0.012, 0.004, 0.0) - out * 0.004
		b.put(piece("hair_pin"), Transform3D(_basis(Vector3.UP, o), p), stuff, accent, hair, best)


static func _braid_rings(b: _Merge, hair: Dictionary, head: Dictionary, stuff: Array, accent: Array) -> void:
	var v: PackedVector3Array = hair["v"]
	var eye := _eye_y(head)
	var lowest := INF
	for i in v.size():
		lowest = minf(lowest, v[i].y)
	# a braid hangs well below the jaw; a knot or a crop has none to ring
	if lowest > eye - 0.17:
		return
	var ends := {}
	for i in v.size():
		if v[i].y < lowest + 0.09:
			var s := signi(int(roundf(v[i].x * 100.0)))
			var k := 0 if absf(v[i].x) < 0.03 else s
			if not ends.has(k):
				ends[k] = []
			(ends[k] as Array).append(i)
	for k in ends:
		var list: Array = ends[k]
		var low := INF
		for i in list:
			low = minf(low, v[i].y)
		for at in [0.045, 0.075]:
			var y: float = low + at
			var sum := Vector3.ZERO
			var n := 0
			for i in list:
				if absf(v[i].y - y) < 0.01:
					sum += v[i]
					n += 1
			if n < 3:
				continue
			var centre := sum / n
			var r := 0.0
			for i in list:
				if absf(v[i].y - y) < 0.01:
					r = maxf(r, Vector2(v[i].x - centre.x, v[i].z - centre.z).length())
			r = clampf(r + 0.0008, 0.004, 0.025)
			var anchor := _nearest(hair, PackedInt32Array(list), centre)
			b.put(piece("braid_ring"), Transform3D(Basis.from_scale(Vector3(r, 0.012, r)), centre), stuff, accent, hair, anchor)


## A ring on the ring finger of side s: the fingers are cut across just past the knuckles and the
## second from the little finger's side taken.
static func _ring(b: _Merge, body: Dictionary, s: float, stuff: Array, accent: Array) -> void:
	var side := "L" if s > 0.0 else "R"
	var frames: Dictionary = body["frames"]
	if not frames.has("Hand." + side):
		return
	var hand: Transform3D = frames["Hand." + side]
	var to_hand := hand.affine_inverse()
	var v: PackedVector3Array = body["v"]
	var list: PackedInt32Array = (body["by_bone"] as Dictionary).get("Hand." + side, PackedInt32Array())
	var cut: Array = []
	for i in list:
		var l := to_hand * v[i]
		if l.y > 0.112 and l.y < 0.128:
			cut.append([l.z, i, l])
	if cut.size() < 6:
		return
	cut.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var fingers: Array = [[cut[0]]]
	for k in range(1, cut.size()):
		if float(cut[k][0]) - float(cut[k - 1][0]) > 0.0022:
			fingers.append([])
		(fingers[-1] as Array).append(cut[k])
	var finger: Array = fingers[1] if fingers.size() >= 3 else fingers[0]
	var sum := Vector3.ZERO
	for e in finger:
		sum += e[2]
	var centre := sum / finger.size()
	var r := 0.0
	for e in finger:
		var d: Vector3 = e[2] - centre
		r = maxf(r, Vector2(d.x, d.z).length())
	r = clampf(r + 0.0006, 0.006, 0.013)
	var anchor := int(finger[int(finger.size() * 0.5)][1])
	var xf := hand * Transform3D(Basis.from_scale(Vector3(r, r * 0.9, r)), Vector3(centre.x, centre.y, centre.z))
	b.put(piece("ring"), xf, stuff, accent, body, anchor)


static func _bracelet(b: _Merge, body: Dictionary, s: float, stuff: Array, accent: Array) -> void:
	var side := "L" if s > 0.0 else "R"
	var frames: Dictionary = body["frames"]
	if not frames.has("LowerArm." + side) or not frames.has("Hand." + side):
		return
	var a: Vector3 = (frames["LowerArm." + side] as Transform3D).origin
	var h: Vector3 = (frames["Hand." + side] as Transform3D).origin
	var axis := (h - a).normalized()
	var at := a.lerp(h, 0.86)
	var idx := _near(body, ["LowerArm." + side, "Hand." + side], at, 0.08)
	var r := _radius(body, idx, at, axis, 0.006, 0.07, 0.03) + 0.0025
	var anchor := _nearest(body, idx, at)
	# the ring is made round Y, so Y goes along the arm
	b.put(piece("bracelet"), Transform3D(_along(axis) * Basis.from_scale(Vector3(r, r, r)), at), stuff, accent, body, anchor)


## A basis whose +Y is `axis`.
static func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


## The neck's middle and its half-widths (x, z) at height y: off the head's skin, which is the neck's
## down to the shoulders, or the body's where there is no head part; most of the way out of what is
## there, so a stray vertex of a jaw or a collar does not widen it.
static func _neck_at(body: Dictionary, head: Dictionary, y: float) -> Array:
	var pts: Array[Vector3] = []
	for c in [head, body]:
		if c.is_empty() or pts.size() >= 12:
			continue
		var v: PackedVector3Array = c["v"]
		for i in v.size():
			if absf(v[i].y - y) < 0.008 and Vector2(v[i].x, v[i].z).length() < 0.085:
				pts.append(v[i])
	if pts.size() < 6:
		return [Vector3(0, y, 0), 0.058, 0.060]
	var xs: Array[float] = []
	var zs: Array[float] = []
	for p in pts:
		xs.append(p.x)
		zs.append(p.z)
	xs.sort()
	zs.sort()
	var lo := int(pts.size() * 0.05)
	var hi := int(pts.size() * 0.95)
	var mid := Vector3((xs[lo] + xs[hi]) * 0.5, y, (zs[lo] + zs[hi]) * 0.5)
	return [mid, (xs[hi] - xs[lo]) * 0.5, (zs[hi] - zs[lo]) * 0.5]


static func _torc(b: _Merge, body: Dictionary, head: Dictionary, stuff: Array, accent: Array, over: Array) -> void:
	var frames: Dictionary = body["frames"]
	if not frames.has("Neck"):
		return
	var neck: Vector3 = (frames["Neck"] as Transform3D).origin
	var n := _neck_at(body, head, neck.y + 0.006)
	var mid: Vector3 = n[0]
	var room := 0.007
	# over a collar that stands up round the neck
	for pts in over:
		for q in (pts as PackedVector3Array):
			if absf(q.y - (neck.y + 0.006)) < 0.01 and Vector2(q.x - mid.x, q.z - mid.z).length() < 0.085:
				# how far out of the neck's own ellipse this point of the collar stands, in metres
				var e := Vector2((q.x - mid.x) / maxf(float(n[1]), 0.03), (q.z - mid.z) / maxf(float(n[2]), 0.03)).length()
				room = clampf((e - 1.0) * (float(n[1]) + float(n[2])) * 0.5 + 0.004, room, 0.03)
	var sc := Vector3(float(n[1]) + room, 0.07, float(n[2]) + room)
	# low on the neck, its front lower than its back, as a torc lies towards the collar
	var at := Vector3(mid.x, neck.y + 0.006, mid.z)
	var tilt := Basis(Vector3.RIGHT, 0.26)
	var anchor := _nearest(body, _near(body, ["Neck", "Chest"], at, 0.2), at + Vector3(0, 0, sc.z))
	b.put(piece("torc"), Transform3D(tilt * Basis.from_scale(sc), at), stuff, accent, body, anchor)


## A string of beads or a pendant's chain round the neck, lying on the body (and on what is over it):
## at the back at the foot of the neck, in front on the breastbone.
static func _necklace(b: _Merge, body: Dictionary, head: Dictionary, kind: String, stuff: Array, accent: Array,
		over: Array) -> void:
	var frames: Dictionary = body["frames"]
	if not frames.has("Neck"):
		return
	var neck: Vector3 = (frames["Neck"] as Transform3D).origin
	var at_neck := _neck_at(body, head, neck.y - 0.012)
	var mid: Vector3 = _neck_at(body, head, neck.y + 0.02)[0]
	var back_y := neck.y - 0.012
	var front_y := neck.y - (0.10 if kind == "beads" else 0.13)
	var room := 0.0035
	var idx := _near(body, ["Neck", "Chest", "Spine", "Shoulder.L", "Shoulder.R", "Head"], Vector3(mid.x, neck.y - 0.06, mid.z), 0.24)
	var v: PackedVector3Array = body["v"]
	var loop: Array[Vector3] = []
	var anchors: Array[int] = []
	var count := 36
	for k in count:
		var th := TAU * float(k) / count
		var dir := Vector3(sin(th), 0.0, cos(th))
		var y := lerpf(back_y, front_y, (1.0 + cos(th)) * 0.5)
		# the first skin out from the neck's middle that way at that height: the neck at the back, the
		# slope of the shoulders at the sides, the breastbone in front (a shell's nearest crossing, not
		# its furthest, which at the sides is the outside of the shoulder)
		var r := INF
		var best := -1
		for i in idx:
			var d := v[i] - Vector3(mid.x, y, mid.z)
			if absf(d.y) > 0.012:
				continue
			var flat := Vector3(d.x, 0.0, d.z)
			var along := flat.dot(dir)
			if along <= 0.03 or (flat - dir * along).length() > 0.014:
				continue
			if along < r:
				r = along
				best = i
		# and never inside the neck's own skin (the head's, which the body's lies under)
		var ex := maxf(float(at_neck[1]), 0.03)
		var ez := maxf(float(at_neck[2]), 0.03)
		var neck_r := 1.0 / sqrt(pow(dir.x / ex, 2.0) + pow(dir.z / ez, 2.0))
		r = maxf(r if r < INF else neck_r, neck_r)
		# and on what is worn over it there, not through it
		# (in front: at the sides a shirt's shoulder is the outside of the arm)
		if cos(th) > 0.2:
			var body_r := r
			for pts in over:
				r = maxf(r, minf(_crossing(pts, Vector3(mid.x, y, mid.z), dir, 0.0), body_r + 0.03))
		loop.append(Vector3(mid.x, y, mid.z) + dir * (r + room))
		anchors.append(best if best >= 0 else _nearest(body, idx, Vector3(mid.x, y, mid.z) + dir * r))
	if kind == "beads":
		b.tube(loop, anchors, 0.0006, CORD, body)
		var bead := piece("bead")
		# glass and metal beads round, bone ones a longer token
		var size := Vector3(0.0034, 0.0034, 0.0034) if stuff != STUFF["bone"] else Vector3(0.0036, 0.0026, 0.0026)
		for k in count:
			var th := TAU * float(k) / count
			# strung over the front two-thirds; the cord goes bare round the back
			if cos(th) < -0.35:
				continue
			var tangent := (loop[(k + 1) % count] - loop[(k + count - 1) % count]).normalized()
			var basis := Basis(tangent, (Vector3.UP - tangent * Vector3.UP.dot(tangent)).normalized(), Vector3.ZERO)
			basis.z = basis.x.cross(basis.y)
			var sz := size * (1.25 if k == 0 else 1.0)
			b.put(bead, Transform3D(basis * Basis.from_scale(sz), loop[k]), stuff, accent, body, anchors[k])
	else:
		b.tube(loop, anchors, 0.00055, stuff, body)
		var out := Vector3(0, 0.12, 1).normalized()
		b.put(piece("pendant"), Transform3D(_basis(Vector3.UP, out), loop[0] + Vector3(0, -0.001, 0.002)), stuff, accent, body, anchors[0])


static func _brooch(b: _Merge, body: Dictionary, stuff: Array, accent: Array, over: Array) -> void:
	var frames: Dictionary = body["frames"]
	if not frames.has("Neck"):
		return
	var neck: Vector3 = (frames["Neck"] as Transform3D).origin
	var th := 0.55
	var dir := Vector3(sin(th), 0.0, cos(th))
	var at := Vector3(0.0, neck.y - 0.085, 0.0)
	var idx := _near(body, ["Chest", "Shoulder.L", "Neck"], at + dir * 0.1, 0.12)
	var r := _surface(body, idx, at, dir, 0.02, 0.11)
	# on the outermost of what is worn there: a brooch pins the cloak or the plaid
	for pts in over:
		var o: Vector3 = at
		var far := 0.0
		for q in (pts as PackedVector3Array):
			var d := q - o
			var along := d.dot(dir)
			if along > far and (d - dir * along).length() < 0.02:
				far = along
		r = maxf(r, minf(far, r + 0.06))
	var p := at + dir * (r + 0.003)
	b.put(piece("brooch"), Transform3D(_basis(Vector3.UP, dir), p), stuff, accent, body, _nearest(body, idx, p))


## A mesh's vertices as they are cut for `variant` (a garment carries each body it is fitted to as a
## morph target of that body's name); its own where it has none.
static func _fitted(c: Dictionary, variant: String) -> PackedVector3Array:
	var key := "fit|" + variant
	if c.has(key):
		return c[key]
	var v: PackedVector3Array = c["v"]
	var moves: PackedVector3Array = (c["shapes"] as Dictionary).get(variant, PackedVector3Array())
	var out := v
	if not variant.is_empty() and moves.size() == v.size():
		out = PackedVector3Array()
		out.resize(v.size())
		for i in v.size():
			out[i] = v[i] + moves[i]
	c[key] = out
	return out


## The nearest crossing outwards from `from` along the horizontal `dir` of the points `pts` (within a
## band 12 mm high and 14 mm across), or `fallback`.
static func _crossing(pts: PackedVector3Array, from: Vector3, dir: Vector3, fallback: float) -> float:
	var r := INF
	for q in pts:
		var d := q - from
		if absf(d.y) > 0.012:
			continue
		var flat := Vector3(d.x, 0.0, d.z)
		var along := flat.dot(dir)
		if along <= 0.03 or (flat - dir * along).length() > 0.014:
			continue
		r = minf(r, along)
	return r if r < INF else fallback


## The merged mesh being built: vertices in the bind space of the mesh each piece sits on, each with
## that mesh's weights (its binds folded into one skin) and its moves under the morph targets.
class _Merge:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var moves := {}            # target name -> PackedVector3Array, one row per vertex so far
	var binds: Array = []      # [bone name, bind pose]
	var bind_of := {}          # "<carrier key>|<bind>" -> index in binds

	## A piece `p` put at `xf` in the bind space of carrier `c`, moving as its vertex `anchor` does.
	func put(p: Array, xf: Transform3D, stuff: Array, accent: Array, c: Dictionary, anchor: int) -> void:
		if p.is_empty() or c.is_empty() or anchor < 0 or anchor >= (c["v"] as PackedVector3Array).size():
			return
		var pv: PackedVector3Array = p[0]
		var pn: PackedVector3Array = p[1]
		var pc: PackedColorArray = p[2]
		var pi: PackedInt32Array = p[3]
		var base := pos.size()
		var nb := xf.basis.inverse().transposed()
		var w := _weights_of(c, anchor)
		for k in pv.size():
			pos.append(xf * pv[k])
			nrm.append((nb * pn[k]).normalized())
			var role := pc[k].r if k < pc.size() else 1.0
			var s: Array = stuff if role > 0.75 else (accent if role > 0.25 else Adornment.CORD)
			col.append(s[0])
			uv.append(Vector2(float(s[1]), float(s[2])))
			bones.append_array(w[0])
			weights.append_array(w[1])
		_move_with(c, anchor, pv.size())
		for k in pi:
			idx.append(base + k)

	## A round tube through `loop` (closed), each ring of it moving with its own vertex of `c`.
	func tube(loop: Array[Vector3], anchors: Array[int], r: float, stuff: Array, c: Dictionary) -> void:
		var sides := 5
		var n := loop.size()
		var base := pos.size()
		for k in n:
			var t := (loop[(k + 1) % n] - loop[(k + n - 1) % n]).normalized()
			var a := t.cross(Vector3.UP).normalized()
			if a.length() < 0.5:
				a = Vector3.RIGHT
			var bb := t.cross(a).normalized()
			var w := _weights_of(c, maxi(anchors[k], 0))
			for j in sides:
				var ang := TAU * float(j) / sides
				var d := a * cos(ang) + bb * sin(ang)
				pos.append(loop[k] + d * r)
				nrm.append(d)
				col.append(stuff[0])
				uv.append(Vector2(float(stuff[1]), float(stuff[2])))
				bones.append_array(w[0])
				weights.append_array(w[1])
			_move_with(c, maxi(anchors[k], 0), sides)
		for k in n:
			var k2 := (k + 1) % n
			for j in sides:
				var j2 := (j + 1) % sides
				var a0 := base + k * sides + j
				var a1 := base + k * sides + j2
				var b0 := base + k2 * sides + j
				var b1 := base + k2 * sides + j2
				idx.append_array([a0, b0, b1, a0, b1, a1])

	## The four heaviest bones of vertex i of carrier c, as indices into the merged skin.
	func _weights_of(c: Dictionary, i: int) -> Array:
		var per := int(c["per"])
		var cb: PackedInt32Array = c["bones"]
		var cw: PackedFloat32Array = c["weights"]
		var pairs: Array = []
		for k in per:
			pairs.append([cw[i * per + k], cb[i * per + k]])
		pairs.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		var out_b := PackedInt32Array()
		var out_w := PackedFloat32Array()
		var total := 0.0
		for k in 4:
			if k < pairs.size():
				total += float(pairs[k][0])
		for k in 4:
			if k < pairs.size() and float(pairs[k][0]) > 0.0:
				out_b.append(_bind(c, int(pairs[k][1])))
				out_w.append(float(pairs[k][0]) / maxf(total, 1e-6))
			else:
				out_b.append(0)
				out_w.append(0.0)
		return [out_b, out_w]

	func _bind(c: Dictionary, b: int) -> int:
		var key := "%d|%d" % [(c["skin"] as Skin).get_instance_id(), b]
		if bind_of.has(key):
			return bind_of[key]
		var names: PackedStringArray = c["names"]
		binds.append([names[b] if b < names.size() else "", (c["skin"] as Skin).get_bind_pose(b)])
		bind_of[key] = binds.size() - 1
		return binds.size() - 1

	## `count` new vertices that move as vertex i of c does under each of c's targets.
	func _move_with(c: Dictionary, i: int, count: int) -> void:
		var shapes: Dictionary = c["shapes"]
		var before := pos.size() - count
		for name in shapes:
			if not moves.has(name):
				var fresh := PackedVector3Array()
				fresh.resize(before)
				moves[name] = fresh
		for name in moves:
			var m: PackedVector3Array = moves[name]
			var d: Vector3 = (shapes[name] as PackedVector3Array)[i] if shapes.has(name) else Vector3.ZERO
			for k in count:
				m.append(d)
			moves[name] = m

	func finish(skel: Skeleton3D) -> MeshInstance3D:
		if pos.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		# the targets are whole positions, as the imported parts' are (a relative target is a move,
		# and whole positions read as moves put an earring a third of a metre over the head)
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		var shapes: Array = []
		for name in moves:
			var m: PackedVector3Array = moves[name]
			var moved := false
			for d in m:
				if d.length_squared() > 1e-12:
					moved = true
					break
			if not moved:
				continue
			mesh.add_blend_shape(StringName(name))
			var at := PackedVector3Array()
			at.resize(pos.size())
			for k in pos.size():
				at[k] = pos[k] + m[k]
			var s := []
			s.resize(Mesh.ARRAY_MAX)
			s[Mesh.ARRAY_VERTEX] = at
			s[Mesh.ARRAY_NORMAL] = nrm
			shapes.append(s)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
		# the surface's own material, not an override: a model being freed takes the overrides off
		# every surface it has, and a surface left with none at all is an engine error
		mesh.surface_set_material(0, Adornment.material())
		var skin := Skin.new()
		for bind in binds:
			skin.add_named_bind(StringName(str(bind[0])), bind[1])
		var mi := MeshInstance3D.new()
		mi.name = "jewellery"
		mi.mesh = mesh
		mi.skin = skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = Adornment.SEEN_TO
		mi.visibility_range_end_margin = 1.0
		mi.set_meta("slot", Adornment.SLOT)
		skel.add_child(mi)
		mi.skeleton = mi.get_path_to(skel)
		return mi
