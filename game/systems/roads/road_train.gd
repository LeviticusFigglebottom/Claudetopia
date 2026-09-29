class_name RoadTrain
extends Node3D
## A caravan's beast and its load, walking the road behind the trader: a packhorse with sacks and a
## crate at its pack socket, or a carthorse between the shafts of a forge cart with its bed loaded.
## Both are the forge's own things -- the cob (HorseModel, its walk clip played at the pace it goes)
## and the props (`hearthvale_cart_*`, `*_sack_a`, `*_crate_a`, `*_barrel_a`) -- so nothing on the
## road is a white box.
##
## It is moved, not driven: RoadEvent sets where it is and how fast it goes (`move`), along the
## road's own line and on the ground's height. A body (AnimatableBody3D, the world layer) keeps
## people and the player out of it. The load is a WorldContainer (`goods`): owned by the caravan's
## faction while its trader lives, so taking from it is theft; anybody's once the caravan is broken.
##
## The cart is the forge's: its shafts run to -X, and the horse stands between them (the cart
## turned a quarter so its -X is this node's -Z, gameplay forward).

const LAYER_WORLD := 1 << 0
## Where the cart stands behind the horse's middle, and the cart's own origin to its shafts' ends.
const CART_BEHIND_M := 2.7
const PROPS := "res://assets/models/props/"

var kind := "packhorse"
var region := "hearthvale"
var horse: HorseModel = null
var goods: WorldContainer = null
var _speed := 0.0
var _cart: Node3D = null


## Builds the beast and its load. `container_id` keeps the load's state across streaming.
func build(train_kind: String, region_key: String, container_id: String, loot_table: String, owner_faction: String) -> void:
	kind = train_kind
	region = region_key
	name = "RoadTrain"
	var pivot := Node3D.new()
	pivot.name = "Model"
	pivot.rotation.y = PI
	add_child(pivot)
	horse = HorseModel.new()
	horse.name = "Horse"
	horse.cloth_tint = Color(0.62, 0.52, 0.40)
	pivot.add_child(horse)
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.sync_to_physics = false
	add_child(body)
	_box(body, Vector3(0.8, 1.6, 2.3), Vector3(0.0, 0.9, 0.0))
	goods = WorldContainer.new()
	goods.container_id = container_id
	goods.loot_table = loot_table
	goods.owner_faction = owner_faction
	goods.respawn = true
	goods.respawn_hours = 48.0
	if kind == "wagon":
		goods.display_name = "The wagon's load"
		_cart = Node3D.new()
		_cart.name = "Cart"
		_cart.position = Vector3(0.0, 0.0, CART_BEHIND_M)
		add_child(_cart)
		var cart := _prop("cart", "a")
		if cart != null:
			cart.rotation.y = -PI / 2.0
			_cart.add_child(cart)
		# the bed's load: sacks, a barrel and a crate standing on the bed (the bed is 0.53 up)
		for spot in [[Vector3(-0.3, 0.56, 0.5), "sack"], [Vector3(0.28, 0.56, 0.8), "sack"],
				[Vector3(0.0, 0.56, 1.6), "barrel"], [Vector3(-0.25, 0.56, 2.2), "crate"]]:
			var p := _prop(str(spot[1]), "a")
			if p != null:
				p.position = spot[0]
				p.rotation.y = randf_range(-0.4, 0.4)
				_cart.add_child(p)
		_box(body, Vector3(1.5, 1.3, 2.6), Vector3(0.0, 0.8, CART_BEHIND_M + 1.2))
		goods.position = Vector3(0.0, 0.6, 2.3)
		_goods_shape(Vector3(1.4, 1.0, 1.0))
		_cart.add_child(goods)
		return
	else:
		goods.display_name = "The packhorse's load"
		# sacks slung either side of the pack socket, a crate on top
		var at := horse.socket("Socket.Pack") if horse.skeleton != null else null
		var hold: Node3D = at if at != null else pivot
		for side in [-1.0, 1.0]:
			var s := _prop("sack", "a")
			if s != null:
				s.position = Vector3(side * 0.36, -0.45, 0.0) if at != null else Vector3(side * 0.36, 1.05, 0.1)
				s.rotation.z = side * 0.25
				hold.add_child(s)
		var c := _prop("crate", "a")
		if c != null:
			c.scale = Vector3.ONE * 0.7
			c.position = Vector3(0.0, 0.05, 0.0) if at != null else Vector3(0.0, 1.5, 0.1)
			hold.add_child(c)
		goods.position = Vector3(0.0, 0.8, 0.9)
		_goods_shape(Vector3(1.0, 1.0, 0.9))
	add_child(goods)


func _goods_shape(size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	goods.add_child(shape)


func _box(body: CollisionObject3D, size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


## A forge prop of `kind` from this region, or Hearthvale's when the region has none.
func _prop(prop_kind: String, variant: String) -> Node3D:
	for r in [region, "hearthvale", "briarwold", "brightwater"]:
		var path := "%s%s_%s_%s/%s_%s_%s.glb" % [PROPS, r, prop_kind, variant, r, prop_kind, variant]
		if ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			if packed != null:
				var n := packed.instantiate() as Node3D
				_strip_bodies(n)
				return n
	return null


## A prop's own collision is for standing still; the train's body is the one that moves.
func _strip_bodies(n: Node) -> void:
	for c in n.find_children("*", "CollisionObject3D", true, false):
		c.get_parent().remove_child(c)
		c.free()


## Where it stands now: `at` on the ground, facing `dir` (world xz), going `speed` m/s.
func move(at: Vector3, dir: Vector2, speed: float) -> void:
	global_position = at
	if dir.length_squared() > 0.0001:
		rotation.y = atan2(-dir.x, -dir.y)
	_speed = speed
	if horse != null:
		horse.set_motion(speed, 0.0, "Walk" if speed > 0.1 else "")


## The cart is tilted by the rise of the ground from the horse to its wheels, so it neither buries
## its tail on a slope nor floats off a crest. `ground` answers a height for (x, z).
func settle(ground: Callable) -> void:
	if _cart == null:
		return
	var back := global_position + global_transform.basis.z * (CART_BEHIND_M + 1.0)
	var h: float = ground.call(back.x, back.z)
	_cart.rotation.x = -clampf(atan2(h - global_position.y, CART_BEHIND_M + 1.0), -0.3, 0.3)
