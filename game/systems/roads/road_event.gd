class_name RoadEvent
extends EnemySpawner
## One thing happening on the road, stood up by RoadLife from a `roadevent` def: a caravan walking
## between two towns, bandits waiting at a bend, a patrol, pilgrims, somebody lost, a broken cart,
## beasts crossing, a pedlar, a runaway and the men after him (docs/WORLD_LIFE_ROADS.md).
##
## A def is a cast and a kind. The cast is people and beasts ({role, enemy | folk, count, does,
## talk}); the kind picks the few behaviours it is played with:
##   `walk`   along the road in a file, the first of the cast leading (a caravan, a patrol, pilgrims,
##            a pedlar); the file stops for a fight, a customer, or a leader left behind
##   `wait`   at the roadside, facing the road (somebody lost, the carter by his cart)
##   `hide`   out of sight either side of a site until sprung (the ambush)
##   `roam`   across the road and back on a line off it (beasts)
##   `flee`   along the road at a run, towards and past you (the runaway)
##   `follow` the file's pace some way behind the first of the cast who flees (the men after him)
## What a person says when spoken to is their `talk` ({prompt, say, do, hook}): `say` a line,
## `trade` (the Merchant, the shop screen), `escort` (they fall in behind you to the nearest
## settlement), `help`, `turn_in` (the runaway given up), or `spring` (the fake injured traveller).
## A `hook` is what it comes to: marks, an item, standing with a faction, a rumour, and a place put
## on the chart (`reveals`: a POI id, or `nearest:<kind>` for the nearest not yet found).
##
## The road's own people are foes' bodies (Enemy) when they carry a blade -- a caravan's trader and
## guards, a patrol, the hunters -- so they can be fought, robbed, and killed, and plain Npc bodies
## (RoadFolk) when they do not. The armed ones share the faction WAYFARERS, are in the group
## Perception.ROAD_GROUP (the road's foes hunt them, and they hunt the road's foes; they leave the
## player be until the player strikes one), and mind their own business until something does.
## A blow from the player on any of them sets the whole cast on the player and costs the def's
## `consequence` ({faction, reputation, notice}); a death by the player's hand costs it again.
##
## Everything is stood up a body at a time within WorldPace's budget (`build`), and nothing here is
## saved: RoadLife keeps a caravan's journey, and anything else is gone with the load.

signal finished(event: RoadEvent)

const KINDS: Array[String] = ["caravan", "ambush", "patrol", "pilgrims", "lost_traveller", "broken_cart", "beasts", "wanderer", "fugitive"]
const TALKS: Array[String] = ["say", "trade", "escort", "help", "turn_in", "spring"]
## What the road's own armed people are to Actor.is_hostile_to: not the player's, and at odds with
## everything that robs or eats travellers.
const WAYFARERS := "wayfarers"
const HOSTILE_TO: Array[String] = ["bandits", "beasts", "clanless", "unquiet", "smugglers", "quiet_hands", "hostile"]
## The most foes an ambush stands against a player of each tier (1..4): with AttackTokens' two at a
## time, four is the most a first-tier character can be asked to watch.
const FOE_CAP := [0, 2, 3, 4, 5]
## How long between the first two of an ambush coming out and each of the rest (s).
const SPRING_STAGGER_S := 1.4
## The file: metres between people, and how far off the road's middle each side walks.
const FILE_GAP_M := 3.2
const FILE_SIDE_M := 1.1
## A walker's goal is this far ahead of where the file has them, so they never arrive and stop.
const LEAD_M := 2.5
## A file waits for a member this far behind their place in it.
const STRAGGLE_M := 9.0
## Within this of the first of the cast, a player is somebody they stop for.
const CUSTOMER_M := 4.0
## An ambush springs on a body this near its site.
const SPRING_M := 14.0
## A hidden foe sits this far off the road's middle.
const HIDE_SIDE_M := Vector2(9.0, 15.0)
## An escort ends within this of the place.
const ARRIVE_M := 55.0
## How far a player may leave somebody they are escorting before they give up on them.
const ESCORT_LOST_M := 160.0

var uid := ""
var def: Dictionary = {}
var kind := ""
var region := ""
var tier := 1
var rng := RandomNumberGenerator.new()
var terrain_height := Callable()
## The line walked, and how far along it the head of the file is.
var path := PackedVector2Array()
var path_m := 0.0
var speed := 1.3
## The site of an ambush or the spot of a wait: {at: Vector2, dir: Vector2, kind}.
var site: Dictionary = {}
## Who an ambush is for: "player", or a caravan (RoadEvent) it waits for.
var prey: Node = null
## A caravan's journey (RoadLife's record), or {}.
var journey: Dictionary = {}
var state := "building"
var outcome := ""
var built := false
var tell := ""
## [{index, role, node, does, talk}] -- every body of the cast.
var members: Array = []
var train: RoadTrain = null
var props: Array[Node3D] = []
var escort_to := ""
var escorting: RoadFolk = null
var provoked := false
var helped := false
var _spring_left: Array = []
var _spring_t := 0.0
var _tick := 0.0
var _fight_seen := false
var _player_fought := false


func _init() -> void:
	spawn_on_ready = false
	respawn_on_rest = false
	drop_to_ground = false


func _ready() -> void:
	super._ready()
	add_to_group("road_events")


## The cast's `count` as a number: a number, or a [min, max] range rolled.
func count_of(entry: Dictionary) -> int:
	var c: Variant = entry.get("count", 1)
	if c is Array and (c as Array).size() >= 2:
		return rng.randi_range(int(c[0]), int(c[1]))
	return maxi(int(c), 1)


func does_of(entry: Dictionary, index: int) -> String:
	if entry.has("does"):
		return str(entry["does"])
	match kind:
		"ambush":
			return "hide" if not entry.has("folk") else "wait"
		"beasts":
			return "roam"
		"lost_traveller", "broken_cart":
			return "wait"
		"fugitive":
			return "flee" if index == 0 else "follow"
	return "walk"


# --- standing it up -------------------------------------------------------------------------------

## Stands the cast up, a body at a time within the frame's budget, then the train and the tell.
func build() -> void:
	var slice := WorldPace.Slice.new()
	if kind == "ambush" and tell == "":
		var tells: Array = def.get("tell", ["crows"])
		tell = str(tells[rng.randi() % tells.size()]) if not tells.is_empty() else "crows"
	var cast: Array = def.get("cast", [])
	var hostiles := 0
	var slot := 0
	for i in cast.size():
		if not (cast[i] is Dictionary):
			continue
		var entry: Dictionary = cast[i]
		# a part of the cast that is one tell's (the fake wounded man) stands only for that tell
		if entry.has("only_tell") and str(entry["only_tell"]) != tell:
			continue
		var n := count_of(entry)
		var does := does_of(entry, i)
		if does == "hide" or (kind == "beasts" and entry.has("enemy")):
			var cap := int(FOE_CAP[clampi(tier, 1, FOE_CAP.size() - 1)])
			n = clampi(n, 1, maxi(cap - hostiles, 1))
			hostiles += n
		for k in n:
			if not is_inside_tree():
				return
			var at := _start_point(does, slot, k, n)
			var body: Node3D = null
			if entry.has("enemy"):
				body = _stand_foe(entry, at, does)
			else:
				body = _stand_folk(entry, at, i)
			if body != null:
				members.append({"index": i, "role": str(entry.get("role", "")), "node": body, "does": does,
						"talk": entry.get("talk", {}), "slot": slot})
				slot += 1
			await slice.pace("road_life")
	var t: Dictionary = def.get("train", {})
	if not t.is_empty() and is_inside_tree():
		_stand_train(t)
		await slice.pace("road_life")
	if kind == "broken_cart" and is_inside_tree():
		_stand_broken_cart()
		await slice.pace("road_life")
	if kind == "ambush" and is_inside_tree():
		_stand_tell()
		await slice.pace("road_life")
	built = true
	state = "live"


func _ground(x: float, z: float, fallback := 0.0) -> float:
	if terrain_height.is_valid():
		return float(terrain_height.call(x, z))
	if World.instance != null:
		return World.get_height(x, z)
	return fallback


func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, _ground(p.x, p.y, global_position.y), p.y)


## Where a body of the cast starts: in the file for walkers, at the roadside for waiters, off the
## road in cover for the hidden, on the crossing line for beasts.
func _start_point(does: String, slot: int, k: int, n: int) -> Vector3:
	match does:
		"hide":
			var d: Vector2 = site.get("dir", Vector2(0, 1))
			var side := Vector2(-d.y, d.x) * (1.0 if k % 2 == 0 else -1.0)
			var out := rng.randf_range(HIDE_SIDE_M.x, HIDE_SIDE_M.y)
			var at: Vector2 = site["at"] + side * out + d * rng.randf_range(-6.0, 6.0)
			return _v3(at)
		"wait":
			var d2: Vector2 = site.get("dir", Vector2(0, 1))
			var side2 := Vector2(-d2.y, d2.x)
			# the bait of an ambush lies in the road itself; anybody else waits at its edge
			var off := 1.0 if kind == "ambush" else 4.0
			return _v3(site["at"] + side2 * (off + 1.2 * k) + d2 * (1.5 * k))
		"roam":
			var a: Vector2 = _roam_line()[0]
			return _v3(a + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	var here := file_point(slot)
	return _v3(here["at"])


## The head of the file's place, and each member's `slot` behind it: {at, dir}.
func file_point(slot: int, ahead := 0.0) -> Dictionary:
	var s := path_m - float(slot) * FILE_GAP_M + ahead
	var p := RoadRoutes.point_along(path, s)
	var at: Vector2 = p["at"]
	var dir: Vector2 = p["dir"]
	if slot > 0:
		at += Vector2(-dir.y, dir.x) * (FILE_SIDE_M if slot % 2 == 0 else -FILE_SIDE_M)
	return {"at": at, "dir": dir}


func _roam_line() -> Array:
	var d: Vector2 = site.get("dir", Vector2(0, 1))
	var side := Vector2(-d.y, d.x)
	var c: Vector2 = site["at"]
	return [c + side * 45.0 + d * 10.0, c - side * 45.0 - d * 10.0]


func _stand_foe(entry: Dictionary, at: Vector3, does: String) -> Enemy:
	var facing := 0.0
	var enemy := spawn_one(str(entry["enemy"]), at, facing, {"group": uid})
	if enemy == null:
		return null
	enemy.set_meta("road_event", uid)
	enemy.hit_taken.connect(_on_member_hit.bind(enemy))
	enemy.died.connect(_on_member_died.bind(enemy))
	var hostile := does in ["hide", "roam"] or bool(entry.get("hostile", false))
	if not hostile:
		enemy.faction = WAYFARERS
		enemy.hostile_to.assign(HOSTILE_TO)
		enemy.add_to_group(Perception.ROAD_GROUP)
		enemy.sits = true
		enemy.minding = true
		enemy.inactive = true
		var talk: Dictionary = entry.get("talk", {})
		if not talk.is_empty():
			var t := RoadTalk.new()
			t.event = self
			t.actor = enemy
			t.prompt = str(talk.get("prompt", "Talk"))
			enemy.add_child(t)
		if not (def.get("merchant", {}) as Dictionary).is_empty() and str(entry.get("role", "")) == "trader":
			_give_shop(enemy)
	if does == "hide":
		_hide(enemy)
	elif does == "roam":
		var line := _roam_line()
		enemy.brain.patrol_points = PackedVector3Array([_v3(line[0]), _v3(line[1])])
		enemy.brain.params["patrol_speed"] = float(entry.get("speed", 1.6))
		enemy.brain.force(Brain.PATROL)
	elif does in ["walk", "follow"]:
		_march(enemy, at)
	return enemy


func _stand_folk(entry: Dictionary, at: Vector3, index: int) -> RoadFolk:
	var folk: Dictionary = entry.get("folk", {})
	var body := RoadFolk.make(folk, rng.randi(), str(journey.get("from", "")))
	body.event = self
	body.cast_index = index
	var talk: Dictionary = entry.get("talk", {})
	body.prompt = str(talk.get("prompt", ""))
	body.activity = "travel"
	if not (def.get("merchant", {}) as Dictionary).is_empty() and str(entry.get("role", "")) in ["trader", "wanderer"]:
		_give_shop(body)
	add_child(body)
	body.global_position = at
	if str(entry.get("pose", "")) != "":
		body.hold_pose(str(entry["pose"]))
	return body


## A merchant of the def's `merchant` block ({stock, marks, buys}) under `body`: the shop the talk
## opens. Its id is the event's own, so its shelves are its own across a load.
func _give_shop(body: Node) -> void:
	var m: Dictionary = def.get("merchant", {})
	var shop := Merchant.new()
	shop.name = "Merchant"
	shop.npc_id = "road:%s" % uid
	shop.stock_table = str(m.get("stock", ""))
	shop.marks = int(m.get("marks", Merchant.DEFAULT_MARKS))
	for b in m.get("buys", []):
		shop.buys.append(str(b))
	shop.place_id = str(journey.get("from", ""))
	shop.set_meta("title", str(def.get("name", "A trader")))
	body.add_child(shop)


func _hide(enemy: Enemy) -> void:
	enemy.visible = false
	enemy.inactive = true
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	if enemy.perception != null:
		enemy.perception.enabled = false
	_spring_left.append(enemy)


## Walks with the file: a patrol of two points on its place, moved as the file moves.
func _march(enemy: Enemy, at: Vector3) -> void:
	enemy.brain.patrol_points = PackedVector3Array([at, at + Vector3(0.01, 0, 0)])
	enemy.brain.params["patrol_speed"] = speed
	enemy.brain.params["patrol_dwell"] = 0.0
	enemy.brain.force(Brain.PATROL)


func _stand_train(t: Dictionary) -> void:
	train = RoadTrain.new()
	add_child(train)
	var region_key := Ids.name_of(region) if region != "" else "hearthvale"
	var owner := str(def.get("consequence", {}).get("faction", ""))
	train.build(str(t.get("kind", "packhorse")), region_key, "road:%s:goods" % uid, str(t.get("goods", "core:loot/common_chest")), owner)
	var here := file_point(0, -4.0)
	train.move(_v3(here["at"]), here["dir"], 0.0)


## The broken cart: a cart down on one side off the road's edge, and its load spilled.
func _stand_broken_cart() -> void:
	var d: Vector2 = site.get("dir", Vector2(0, 1))
	var side := Vector2(-d.y, d.x)
	var at: Vector2 = site["at"] + side * 3.5
	var holder := Node3D.new()
	holder.name = "BrokenCart"
	add_child(holder)
	holder.global_position = _v3(at)
	holder.rotation.y = atan2(-d.x, -d.y)
	var tmp := RoadTrain.new()
	var cart := tmp._prop("cart", "b")
	var sack := tmp._prop("sack", "a")
	var crate := tmp._prop("crate", "a")
	tmp.free()
	if cart != null:
		cart.rotation = Vector3(0.0, -PI / 2.0, 0.22)
		cart.position = Vector3(0.0, -0.15, 1.2)
		holder.add_child(cart)
	if sack != null:
		sack.position = Vector3(1.2, 0.0, 0.3)
		sack.rotation = Vector3(0.0, 0.5, 1.4)
		holder.add_child(sack)
	if crate != null:
		crate.position = Vector3(-1.1, 0.0, -0.4)
		crate.rotation.y = 0.7
		holder.add_child(crate)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.1, 3.2)
	shape.shape = box
	shape.position = Vector3(0.0, 0.55, 2.0)
	body.add_child(shape)
	holder.add_child(body)
	props.append(holder)


## The warning an ambush gives: crows put up and wheeling over the site, a tree felled across the
## road, or somebody lying hurt in it (the cast entry that `wait`s, when the def has one).
func _stand_tell() -> void:
	var at: Vector2 = site["at"]
	var d: Vector2 = site.get("dir", Vector2(0, 1))
	match tell:
		"felled_tree":
			var region_key := Ids.name_of(region) if region != "" else "hearthvale"
			var log_node: Node3D = null
			for r in [region_key, "hearthvale", "briarwold"]:
				var path_s := "res://assets/models/rocks/%s_fallen_log_a/%s_fallen_log_a.glb" % [r, r]
				if ResourceLoader.exists(path_s):
					log_node = (load(path_s) as PackedScene).instantiate() as Node3D
					break
			var holder := Node3D.new()
			holder.name = "FelledTree"
			add_child(holder)
			holder.global_position = _v3(at)
			# across the road: the log's length is its X, laid along the road's side
			holder.rotation.y = atan2(-d.x, -d.y)
			if log_node != null:
				log_node.scale = Vector3(1.15, 1.0, 1.0)
				holder.add_child(log_node)
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(8.0, 0.9, 1.0)
			shape.shape = box
			shape.position.y = 0.45
			body.add_child(shape)
			holder.add_child(body)
			props.append(holder)
		"injured_traveller":
			pass    # the def's own `wait`ing folk entry with talk `spring` is the tell
		_:
			var crows := Crows.new()
			crows.name = "Crows"
			add_child(crows)
			crows.global_position = _v3(at)
			crows.setup([], Vector3(0.0, 0.0, 0.0), 5, rng.randi())
			props.append(crows)


# --- living ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not built:
		return
	_tick -= delta
	if not _spring_left.is_empty() and state == "sprung":
		_spring_t -= delta
		if _spring_t <= 0.0:
			_come_out(_spring_left.pop_front())
			_spring_t = SPRING_STAGGER_S
	if _tick > 0.0:
		return
	_tick = 0.25
	var player := Peers.player() as Node3D
	match kind:
		"ambush":
			_mind_ambush(player)
		"lost_traveller":
			_mind_escort(player)
	_move_file(0.25, player)
	_check_fight(player)


## Whether anybody of the cast is fighting.
func fighting() -> bool:
	for m in members:
		var n: Variant = m["node"]
		if is_instance_valid(n) and n is Enemy and not (n as Enemy).dead and (n as Enemy).brain != null and (n as Enemy).brain.is_fighting():
			return true
	return false


func _leader() -> Node3D:
	for m in members:
		if str(m["does"]) in ["walk", "flee"] and is_instance_valid(m["node"]) and _alive(m["node"]):
			return m["node"]
	return null


static func _alive(n: Variant) -> bool:
	if not is_instance_valid(n):
		return false
	if n is Enemy:
		return not (n as Enemy).dead
	if n is Npc:
		return (n as Npc).alive
	return true


## Moves the file along its line: at its pace, unless it is fighting, has a customer, or has left
## somebody behind; the flee-er at a run, and the followers a way behind.
func _move_file(dt: float, player: Node3D) -> void:
	if path.size() < 2 or state in ["building", "broken"]:
		return
	var leader := _leader()
	var halted := fighting() or state == "sprung"
	if leader != null and player != null and kind != "fugitive" and leader.global_position.distance_to(player.global_position) < CUSTOMER_M:
		halted = true
	if UI != null and UI.is_menu_open("trade") and player != null and leader != null and leader.global_position.distance_to(player.global_position) < 8.0:
		halted = true
	var lag := 0.0
	for m in members:
		if str(m["does"]) != "walk" or not _alive(m["node"]):
			continue
		var want: Vector2 = file_point(int(m["slot"]))["at"]
		var n: Node3D = m["node"]
		lag = maxf(lag, Vector2(n.global_position.x, n.global_position.z).distance_to(want))
	if lag > STRAGGLE_M:
		halted = true
	var pace := speed * (2.6 if kind == "fugitive" else 1.0)
	var moved := 0.0 if halted else pace * dt
	path_m = minf(path_m + moved, RoadRoutes.length_of(path))
	if not journey.is_empty():
		journey["metres"] = path_m
	for m in members:
		var n: Variant = m["node"]
		if not _alive(n):
			continue
		var does := str(m["does"])
		if does not in ["walk", "flee", "follow"]:
			continue
		var slot := int(m["slot"])
		var extra := -35.0 if does == "follow" else 0.0
		var goal: Dictionary = file_point(slot, extra + (LEAD_M if not halted else 0.0))
		var g := _v3(goal["at"])
		if n is Enemy:
			var e := n as Enemy
			if e.brain.is_fighting():
				continue
			e.brain.post = g
			e.brain.patrol_points = PackedVector3Array([g, g + Vector3(0.01, 0, 0)])
			var behind := Vector2(e.global_position.x, e.global_position.z).distance_to(goal["at"])
			e.brain.params["patrol_speed"] = clampf(pace * (1.0 + behind / 5.0), 0.0, e.speed)
			if halted and behind < 1.5:
				e.brain.params["patrol_speed"] = 0.0
		elif n is RoadFolk:
			var f := n as RoadFolk
			if f.is_following() or f.pose != "":
				continue
			f.fleeing = does == "flee" and not halted
			if halted and Vector2(f.global_position.x, f.global_position.z).distance_to(goal["at"]) < 1.5:
				if f.has_target:
					f.stop()
			elif not f.has_target or f.target_position.distance_to(g) > 1.5:
				f.set_move_target(g, false)
	if train != null and is_instance_valid(train):
		var tp := file_point(0, -4.0)
		train.move(_v3(tp["at"]), tp["dir"], 0.0 if halted else pace)
		train.settle(_ground)


## A caravan that has come to the end of its line.
func arrived() -> bool:
	return path.size() >= 2 and path_m >= RoadRoutes.length_of(path) - 1.0


# --- the ambush -------------------------------------------------------------------------------------

func _mind_ambush(player: Node3D) -> void:
	if state != "live":
		return
	var at: Vector2 = site["at"]
	var who: Node3D = null
	if prey is RoadEvent and is_instance_valid(prey):
		var lead := (prey as RoadEvent)._leader()
		if lead != null and Vector2(lead.global_position.x, lead.global_position.z).distance_to(at) < SPRING_M:
			who = lead
	if who == null and player != null:
		var d := Vector2(player.global_position.x, player.global_position.z).distance_to(at)
		var reach := SPRING_M if tell != "felled_tree" else SPRING_M + 4.0
		if d < reach:
			who = player
	if who != null:
		spring(who)


## Springs the ambush on `who`: the hidden come out, two at once and the rest by turns.
func spring(who: Node3D) -> void:
	if state == "sprung" or state == "resolved":
		return
	state = "sprung"
	set_meta("sprung_on", who.get_path() if who.is_inside_tree() else NodePath())
	_springing_on = who
	for m in members:
		if m["node"] is RoadFolk and str(m["does"]) == "wait":
			var f := m["node"] as RoadFolk
			f.hold_pose("")
			f.play_intent("Laugh", true)
			f.prompt = ""
			f.fleeing = true
			f.set_move_target(f.global_position + (f.global_position - who.global_position).normalized() * 25.0, false)
	for i in 2:
		if not _spring_left.is_empty():
			_come_out(_spring_left.pop_front())
	_spring_t = SPRING_STAGGER_S
	var line := str(def.get("lines", {}).get("spring", ""))
	if line != "":
		say(str(def.get("lines", {}).get("speaker", "A voice")), line)


var _springing_on: Node3D = null


func _come_out(enemy: Variant) -> void:
	if not is_instance_valid(enemy):
		return
	var e := enemy as Enemy
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.visible = true
	e.inactive = false
	e.minding = false
	if e.perception != null:
		e.perception.enabled = true
		var t := _springing_on
		if t != null and is_instance_valid(t):
			e.perception.alert_to(t.global_position, t)
	e.brain.force(Brain.COMBAT)


# --- the fight, and what it costs ---------------------------------------------------------------------

func _on_member_hit(hit: HitData, _outcome: String, who: Enemy) -> void:
	var attacker := hit.attacker as Node3D if hit != null and hit.attacker is Node3D else null
	if attacker == null:
		return
	if attacker.is_in_group("player"):
		_player_fought = true
		if who.faction == WAYFARERS:
			_provoke(attacker)
	# the rest of the cast rises to whoever struck one of them
	for m in members:
		var n: Variant = m["node"]
		if n is Enemy and is_instance_valid(n) and not (n as Enemy).dead and n != who:
			var e := n as Enemy
			if e.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			if e.faction == WAYFARERS and attacker.is_in_group("player") and not provoked:
				continue
			e.minding = false
			e.inactive = false
			if e.perception != null and (e.faction != WAYFARERS or not attacker.is_in_group("player") or provoked):
				e.perception.alert_to(attacker.global_position, attacker)
			e.brain.force(Brain.COMBAT)
	if kind == "ambush" and state == "live":
		spring(attacker)


## The player struck one of the road's own: all of them turn on the player, and it costs.
func _provoke(player: Node3D) -> void:
	if provoked:
		return
	provoked = true
	for m in members:
		var n: Variant = m["node"]
		if n is Enemy and is_instance_valid(n):
			(n as Enemy).set_meta("provoked", true)
			(n as Enemy).minding = false
			(n as Enemy).inactive = false
	_cost("reputation", "notice")
	if RoadLife.instance != null:
		RoadLife.instance.note_outcome(self, "attacked")


func _on_member_died(killer: Node, who: Enemy) -> void:
	var by_player := killer != null and is_instance_valid(killer) and killer.is_in_group("player")
	if by_player:
		_player_fought = true
	if who.faction == WAYFARERS and by_player:
		_cost("killing", "killing_notice")
	# a trader down: the load is nobody's
	for m in members:
		if m["node"] == who and str(m["role"]) == "trader" and train != null and is_instance_valid(train) and train.goods != null:
			train.goods.owner_faction = ""
	_check_fight(Peers.player() as Node3D)


## The def's `consequence` ({faction, reputation, killing, notice, killing_notice}) of one kind.
func _cost(key: String, notice_key: String) -> void:
	var c: Dictionary = def.get("consequence", {})
	var faction := str(c.get("faction", ""))
	var delta := int(c.get(key, -5 if key == "reputation" else -10))
	if faction != "" and Social.factions != null and ContentDB.has(faction):
		Social.factions.add_reputation(faction, delta, "%s on the road" % ("an attack" if key == "reputation" else "a killing"))
	var notice := str(c.get(notice_key, ""))
	if notice != "":
		EventBus.notify.emit(notice, "warn")


## After a fight: an ambush put down resolves; a caravan whose attackers are down, with the player's
## hand in it, thanks the player (its `rescue` hook); one whose people are all down is broken.
func _check_fight(player: Node3D) -> void:
	if not built or state == "resolved":
		return
	if fighting():
		_fight_seen = true
	if kind == "ambush" and state == "sprung":
		var up := 0
		for m in members:
			if m["node"] is Enemy and _alive(m["node"]):
				up += 1
		if up == 0 and _spring_left.is_empty():
			finish("cleared")
			if prey is RoadEvent and is_instance_valid(prey):
				(prey as RoadEvent).rescued_by(player if _player_fought or _near(player, 40.0) else null)
		return
	if kind == "caravan" or kind == "patrol":
		var any := false
		for m in members:
			if _alive(m["node"]):
				any = true
		if not any and state != "broken":
			state = "broken"
			if train != null and is_instance_valid(train) and train.goods != null:
				train.goods.owner_faction = ""
			if RoadLife.instance != null:
				RoadLife.instance.note_outcome(self, "broken")


func _near(player: Node3D, metres: float) -> bool:
	var lead := _leader()
	return player != null and lead != null and lead.global_position.distance_to(player.global_position) < metres


## Bandits set on this caravan are down: if the player had a hand in it, the def's `rescue` hook.
func rescued_by(player: Node3D) -> void:
	if player == null or provoked or state == "broken":
		return
	var hook: Dictionary = def.get("rescue", {})
	if hook.is_empty() or helped:
		return
	helped = true
	var lead := _leader()
	say(_name_of(lead), str(hook.get("say", "")))
	give_hook(hook)


# --- talking ----------------------------------------------------------------------------------------

## The interact key on one of the cast: what their `talk` says to do.
func talk(who: Node3D, player: Node) -> void:
	var entry := _member_of(who)
	if entry.is_empty():
		return
	var t: Dictionary = entry.get("talk", {})
	var line := str(t.get("say", ""))
	match str(t.get("do", "say")):
		"trade":
			var shop := who.get_node_or_null("Merchant") as Merchant
			if line != "":
				say(_name_of(who), line)
			if shop != null:
				shop.open_trade(player)
		"escort":
			_start_escort(who as RoadFolk, player as Node3D, line)
		"help":
			if helped:
				say(_name_of(who), str(t.get("after", "Thank you again.")))
				return
			helped = true
			say(_name_of(who), line)
			give_hook(t.get("hook", {}))
			if who is RoadFolk:
				(who as RoadFolk).prompt = ""
				(who as RoadFolk).hold_pose("")
			finish("helped")
		"turn_in":
			if helped:
				return
			helped = true
			say(_name_of(who), line)
			give_hook(t.get("hook", {}))
			_turn_in()
		"spring":
			spring(player as Node3D)
		_:
			say(_name_of(who), line)
			var h: Dictionary = t.get("hook", {})
			if not h.is_empty() and not bool(get_meta("hooked_%d" % int(entry.get("index", 0)), false)):
				set_meta("hooked_%d" % int(entry.get("index", 0)), true)
				give_hook(h)


func _member_of(n: Node) -> Dictionary:
	for m in members:
		if m["node"] == n:
			return m
	return {}


func _name_of(n: Node) -> String:
	if n is Npc:
		return (n as Npc).display_name()
	if n is Enemy:
		return str((n as Enemy).def.get("name", "Traveller"))
	return str(def.get("name", ""))


## The runaway given up: the hunters take him with them, and he is gone with the event.
func _turn_in() -> void:
	for m in members:
		if str(m["does"]) == "flee" and m["node"] is RoadFolk and _alive(m["node"]):
			var f := m["node"] as RoadFolk
			f.fleeing = false
			f.prompt = ""
			f.hold_pose("Cower")
	finish("turned_in")


# --- escorting --------------------------------------------------------------------------------------

func _start_escort(f: RoadFolk, player: Node3D, line: String) -> void:
	if f == null or player == null or escorting != null:
		return
	escort_to = nearest_settlement(Vector2(f.global_position.x, f.global_position.z))
	var place := str(ContentDB.get_or_empty(escort_to).get("name", "the nearest town"))
	say(_name_of(f), line.replace("{place}", place))
	escorting = f
	f.prompt = ""
	f.hold_pose("")
	f.follow(player)
	state = "escort"


func _mind_escort(player: Node3D) -> void:
	if escorting == null or not is_instance_valid(escorting) or state != "escort" or player == null:
		return
	var at := WorldProbe.place_position(escort_to)
	var here := escorting.global_position
	if Vector2(here.x - at.x, here.z - at.z).length() < ARRIVE_M:
		var talk_def: Dictionary = {}
		for c in def.get("cast", []):
			if (c as Dictionary).get("talk", {}).get("do", "") == "escort":
				talk_def = (c as Dictionary)["talk"]
		say(_name_of(escorting), str(talk_def.get("thanks", "This is it. Thank you.")))
		give_hook(talk_def.get("hook", {}))
		escorting.stop_following()
		helped = true
		finish("escorted")
	elif here.distance_to(player.global_position) > ESCORT_LOST_M:
		escorting.stop_following()
		EventBus.notify.emit("%s gave up waiting for you." % _name_of(escorting), "info")
		finish("abandoned")


## The nearest settlement (a place of a settled kind) to `p`, or "".
static func nearest_settlement(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for d in ContentDB.all("place"):
		if str(d.get("kind", "")) not in Crimes.SETTLEMENT_KINDS:
			continue
		var xz := WorldProbe.xz_of(d)
		if xz == Vector2.ZERO:
			continue
		var dist := xz.distance_to(p)
		if dist < best_d:
			best_d = dist
			best = str(d["id"])
	return best


# --- what it comes to ----------------------------------------------------------------------------

## A hook: {marks, item, count, reputation: {faction, delta}, rumour, reveals, once}.
func give_hook(hook: Variant) -> void:
	if not (hook is Dictionary) or (hook as Dictionary).is_empty():
		return
	var h: Dictionary = hook
	var player := Peers.player()
	var once_flag := "road_life/hook/%s" % str(def.get("id", ""))
	if bool(h.get("once", false)) and GameState.has_flag(once_flag):
		return
	if bool(h.get("once", false)):
		GameState.set_flag(once_flag, true)
	var marks := int(h.get("marks", 0))
	if marks > 0 and player != null:
		Purse.give(player, marks)
		EventBus.notify.emit("%d marks." % marks, "info")
	var item := str(h.get("item", ""))
	if item != "" and ContentDB.has(item):
		var bag := Peers.inventory()
		if bag != null and bag.has_method("add"):
			bag.call("add", item, int(h.get("count", 1)))
			EventBus.notify.emit("%s." % str(ContentDB.get_or_empty(item).get("name", item)), "info")
	var rep: Dictionary = h.get("reputation", {})
	if not rep.is_empty() and Social.factions != null and ContentDB.has(str(rep.get("faction", ""))):
		Social.factions.add_reputation(str(rep["faction"]), int(rep.get("delta", 2)), "help on the road")
	var rumour := str(h.get("rumour", ""))
	var reveals := resolve_reveal(str(h.get("reveals", "")))
	if reveals != "":
		var name_of := str(ContentDB.get_or_empty(reveals).get("name", ""))
		rumour = rumour.replace("{place}", name_of)
		GameState.discover(reveals)
		GameState.set_flag("road_life/heard_of/" + reveals, true)
		EventBus.notify.emit("%s is marked on your chart." % name_of, "place")
	if rumour != "":
		EventBus.notify.emit(rumour, "info")
	GameState.set_flag("road_life/done/" + str(def.get("id", "")), true)


## A place a hook points at: a POI or place id as it is, or `nearest:<kind>` for the nearest POI of
## that kind the player has not found, from where the event is.
func resolve_reveal(what: String) -> String:
	if what == "":
		return ""
	if not what.begins_with("nearest:"):
		return what if ContentDB.has(what) else ""
	var want := what.substr(8)
	var here := Vector2(global_position.x, global_position.z)
	var lead := _leader()
	if lead != null:
		here = Vector2(lead.global_position.x, lead.global_position.z)
	var best := ""
	var best_d := INF
	for d in ContentDB.all("poi"):
		if (want != "" and want != "any" and str(d.get("kind", "")) != want) or GameState.is_discovered(str(d["id"])):
			continue
		var p := WorldProbe.place_position(str(d["id"]))
		var dist := Vector2(p.x, p.z).distance_to(here)
		if p != Vector3.ZERO and dist < best_d:
			best_d = dist
			best = str(d["id"])
	return best


## A line out loud, as the HUD's subtitle with who says it.
static func say(who: String, text: String) -> void:
	if text.strip_edges() == "" or UI == null:
		return
	var hud := UI.hud()
	if hud != null and hud.has_method("show_subtitle"):
		hud.call("show_subtitle", ("%s: %s" % [who, text]) if who != "" else text, 5.0)


# --- the end --------------------------------------------------------------------------------------

## Done: what it came to. The bodies stay until RoadLife takes the event down out of sight.
func finish(how: String) -> void:
	if state == "resolved":
		return
	outcome = how
	state = "resolved"
	if RoadLife.instance != null:
		RoadLife.instance.note_outcome(self, how)
	finished.emit(self)


## Where the event is now, for streaming and sight: the leader, else its site.
func focus() -> Vector3:
	var lead := _leader()
	if lead != null:
		return lead.global_position
	if not site.is_empty():
		return _v3(site["at"])
	if path.size() >= 2:
		return _v3(file_point(0)["at"])
	return global_position


## Every point of it worth asking about for sight: its bodies and its props.
func points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m in members:
		if is_instance_valid(m["node"]) and (m["node"] as Node3D).visible:
			out.append((m["node"] as Node3D).global_position + Vector3.UP)
	if train != null and is_instance_valid(train):
		out.append(train.global_position + Vector3.UP)
	for p in props:
		if is_instance_valid(p):
			out.append(p.global_position + Vector3.UP)
	return out
