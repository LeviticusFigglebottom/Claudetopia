class_name HeldItems
extends RefCounted
## The weapons and shields a body is seen to hold. The forge makes them (tools/forge/gen_weapons.py,
## `assets/models/weapons/<name>/<name>.glb`), each built where the hand holds it: the grip's
## middle at the origin and the blade along +Y, which is the weapon socket's own frame (CONTRACTS
## §2), so a model goes into its socket with no transform of its own. A bow goes in the left hand
## (Socket.WeaponL) and a shield on the left forearm (Socket.ShieldL), its face outward.
##
## Before this, nothing was ever put in a hand: every body, the player's included, swung its
## attack clips' arcs with an empty, open hand.
##
## An item names its model with `model` ("weapons/sword_iron"); without one it is drawn as its
## weapon class in what it is made of, read from its id and material: bell bronze, the
## Ash-knights' blackened iron, bone, or iron.

const ROOT := "res://assets/models/"
## A held model is tagged so that dressing the hands again takes away only what it put there.
const TAG := "held_item"

## weapon class -> the forge's kind
const KIND_OF_CLASS := {
	"sword": "sword", "rapier": "rapier", "greatsword": "greatsword", "dagger": "dagger",
	"axe": "axe", "mace": "mace", "spear": "spear", "staff": "staff", "greathammer": "warhammer",
	"hammer": "warhammer", "bow": "bow", "shield": "shield",
}
## Kinds that are made in one finish only.
const ONLY_FINISH := {"rapier": "iron", "staff": "iron", "warhammer": "bronze", "bow": "wood", "knife": "iron"}
const FINISHES: Array[String] = ["iron", "bronze", "ashen", "bone"]
## The sockets a held item goes in, and the ones a sheathed weapon rides in.
const HANDS: Array[String] = ["WeaponR", "WeaponL", "ShieldL"]
const SHEATHS: Array[String] = ["Back", "HipL"]


## What an item is made of, as the forge's finishes go.
static func finish_of(item: Dictionary) -> String:
	var id := str(item.get("id", ""))
	var leaf := id.get_slice("/", id.get_slice_count("/") - 1)
	var material := str(item.get("material", ""))
	if leaf.begins_with("bell_bronze") or leaf.begins_with("bearers") or material.contains("bronze"):
		return "bronze"
	if leaf.begins_with("ashen") or leaf.begins_with("ash_"):
		return "ashen"
	if material.contains("bone") or leaf.begins_with("kingbone") or leaf.begins_with("clan_"):
		return "bone"
	if material.contains("oak") or material.contains("wood"):
		return "wood"
	return "iron"


## The forge asset an item is drawn with ("weapons/sword_iron"), or "" when there is none.
static func model_for(item: Dictionary) -> String:
	if item.has("model"):
		return str(item["model"])
	var weapon: Dictionary = item.get("weapon", {}) if item.get("weapon") is Dictionary else {}
	var cls := str(weapon.get("class", ""))
	var tags: Array = item.get("tags", [])
	if cls.is_empty() and tags.has("shield"):
		cls = "shield"
	var kind := str(KIND_OF_CLASS.get(cls, ""))
	if kind.is_empty():
		return ""
	var finish := finish_of(item)
	if kind == "shield":
		return "weapons/shield_%s" % ("bone" if finish == "bone" else ("wood" if finish == "wood" else "iron"))
	if kind == "bow":
		return "weapons/bow_%s" % ("bone" if finish == "bone" else "wood")
	if ONLY_FINISH.has(kind):
		finish = str(ONLY_FINISH[kind])
	elif not FINISHES.has(finish):
		finish = "iron"
	return "weapons/%s_%s" % [kind, finish]


## The glb a model name stands for.
static func path_of(model: String) -> String:
	return "%s%s/%s.glb" % [ROOT, model, model.get_file()]


## The socket an item is held in: a bow in the left hand, a shield on the left forearm, the rest
## in the right hand.
static func socket_for(item: Dictionary) -> String:
	var model := model_for(item)
	if model.get_file().begins_with("bow"):
		return "WeaponL"
	if model.get_file().begins_with("shield"):
		return "ShieldL"
	return "WeaponR"


## Where a weapon rides out of a fight: "Back" for a two-handed weapon or a bow, "HipL" for a
## one-handed one, "" for one that is carried in the hand all the same (a spear or a staff, too long
## for a sheath, and a shield, which stays on the arm).
static func sheath_for(item: Dictionary) -> String:
	var file := model_for(item).get_file()
	if file.is_empty() or file.begins_with("shield") or file.begins_with("spear") or file.begins_with("staff"):
		return ""
	if file.begins_with("bow") or two_handed(item):
		return "Back"
	return "HipL"


## The sheathed model's place in its socket (`sheath` from sheath_for). It is worked out in the
## rest skeleton, then taken into the socket's frame, so the weapon moves with the hips or the
## chest it hangs from:
##   * at the left hip, the grip stands forward and up for the right hand to cross-draw, and the
##     blade hangs down and back along the thigh, its flat to the leg;
##   * across the back, a blade's grip rides over the right shoulder and the blade runs down to
##     the left hip, its flat to the back. A bow lies the other way, its middle between the shoulder
##     blades and its limbs from the left shoulder to the right hip.
## Returns the identity when `body` has no skeleton or no such socket.
static func sheath_transform(body: Node, sheath: String, item: Dictionary) -> Transform3D:
	var sk: Skeleton3D = body.get("skeleton") as Skeleton3D if body != null else null
	if sk == null:
		return Transform3D.IDENTITY
	var si := sk.find_bone("Socket.%s" % sheath)
	var bones := [sk.find_bone("Hips"), sk.find_bone("Head"), sk.find_bone("Hand.L"), sk.find_bone("Hand.R")]
	if si < 0 or bones.has(-1):
		return Transform3D.IDENTITY
	var rest := func(i: int) -> Vector3: return sk.get_bone_global_rest(i).origin
	var up: Vector3 = ((rest.call(bones[1]) as Vector3) - (rest.call(bones[0]) as Vector3)).normalized()
	var left: Vector3 = (rest.call(bones[2]) as Vector3) - (rest.call(bones[3]) as Vector3)
	left = (left - up * left.dot(up)).normalized()
	var fwd := left.cross(up).normalized()
	var socket := sk.get_bone_global_rest(si)
	var o := socket.origin
	var blade: Vector3
	var flat: Vector3               # the side of the blade that lies against the body
	var at: Vector3                 # where the grip's middle goes
	if sheath == "HipL":
		blade = (-up * 0.82 - fwd * 0.52 + left * 0.08).normalized()
		flat = left
		at = o + up * 0.10 + fwd * 0.09 + left * 0.05
	elif model_for(item).get_file().begins_with("bow"):
		# a bow's limbs are its model's Z; its thin side, X, lies against the back
		var limbs := (up * 0.87 - left * 0.5).normalized()
		var x := -fwd
		var y := limbs.cross(x).normalized()
		return socket.affine_inverse() * Transform3D(Basis(x, y, limbs), o - fwd * 0.03)
	else:
		blade = (-up * 0.87 + left * 0.5).normalized()
		flat = -fwd
		at = o + up * 0.24 - left * 0.14 - fwd * 0.03
	var bx := (flat - blade * flat.dot(blade)).normalized()
	var bz := bx.cross(blade).normalized()
	return socket.affine_inverse() * Transform3D(Basis(bx, blade, bz), at)


## Whether the other hand closes on the weapon too.
static func two_handed(item: Dictionary) -> bool:
	var tags: Array = item.get("tags", [])
	if tags.has("two_handed"):
		return true
	var weapon: Dictionary = item.get("weapon", {}) if item.get("weapon") is Dictionary else {}
	return str(weapon.get("clips_set", "")) == "2H"


## The model, instanced; null when the item has none or the forge has not made it.
static func instance(item: Dictionary) -> Node3D:
	var model := model_for(item)
	if model.is_empty():
		return null
	var path := path_of(model)
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = "Held_%s" % model.get_file()
	node.set_meta(TAG, str(item.get("id", model)))
	node.add_to_group(TAG)
	# drawn where the hand is this frame, not interpolated behind it
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return node


## Puts the weapon in the main hand and the off-hand item (a shield) on the left arm, each in its
## socket of `body` (a HumanoidModel), taking away whatever this put there before, and closes the
## hands round what they hold. Items are content defs ({} for an empty hand). Not `drawn`, the
## main weapon goes in its sheath instead (sheath_for), when it has one, and that hand stays open.
static func dress(body: Node, main: Dictionary, off: Dictionary = {}, drawn := true) -> Array[Node3D]:
	var held: Array[Node3D] = []
	if body == null or not body.has_method("attach_to_socket"):
		return held
	undress(body)
	var right := false
	var left := false
	for item: Dictionary in [main, off]:
		if item.is_empty():
			continue
		var node := instance(item)
		if node == null:
			continue
		var socket := socket_for(item)
		var sheath := sheath_for(item) if item == main and not drawn else ""
		if not sheath.is_empty():
			if bool(body.call("attach_to_socket", sheath, node, false)):
				node.transform = sheath_transform(body, sheath, item)
				held.append(node)
			else:
				node.queue_free()
			continue
		if not bool(body.call("attach_to_socket", socket, node, false)):
			node.queue_free()
			continue
		# the closed fist holds a haft a little off the socket's own line (the rig's grip
		# morph, HumanoidModel.grip_offset); a shield hangs on the forearm and is not held so
		if socket != "ShieldL" and body.has_method("grip_offset"):
			node.position = body.call("grip_offset", "R" if socket == "WeaponR" else "L")
		held.append(node)
		match socket:
			"WeaponR":
				right = true
				left = left or two_handed(item)
			"WeaponL", "ShieldL":
				left = true
	if body.has_method("set_grip"):
		body.call("set_grip", "R", 1.0 if right else 0.0)
		body.call("set_grip", "L", 1.0 if left else 0.0)
	return held


## Takes away what `dress` put in `body`'s sockets.
static func undress(body: Node) -> void:
	if body == null or not body.has_method("socket"):
		return
	for socket in HANDS + SHEATHS:
		var s: Node = body.call("socket", socket)
		if s == null:
			continue
		for c in s.get_children():
			if c.has_meta(TAG):
				s.remove_child(c)
				c.queue_free()


## What `body` holds now: {socket: item id}.
static func held_by(body: Node) -> Dictionary:
	return _in_sockets(body, HANDS)


## What `body` carries sheathed: {"Back" or "HipL": item id}.
static func sheathed_by(body: Node) -> Dictionary:
	return _in_sockets(body, SHEATHS)


static func _in_sockets(body: Node, sockets: Array) -> Dictionary:
	var out := {}
	if body == null or not body.has_method("socket"):
		return out
	for socket: String in sockets:
		var s: Node = body.call("socket", socket)
		if s == null:
			continue
		for c in s.get_children():
			if c.has_meta(TAG) and not c.is_queued_for_deletion():
				out[socket] = str(c.get_meta(TAG))
	return out


## A stand-in item def for a body that fights with a weapon class and carries no item (an
## enemy's attacks name a `weapon_class`): {} when the forge makes nothing of that class.
static func for_class(weapon_class: String) -> Dictionary:
	if not KIND_OF_CLASS.has(weapon_class):
		return {}
	var item := {"id": "class:%s" % weapon_class, "weapon": {"class": weapon_class}}
	if weapon_class in ["greatsword", "spear", "greathammer", "hammer"]:
		item["tags"] = ["two_handed"]
	return item
