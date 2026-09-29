class_name Leads
extends Node
## Something the story has you follow (docs/FIGHTING_STYLE_STARTS.md §3.2, §3.4): the grey hart
## walking south out of the Briar, the courier a field ahead with the other page. It keeps ahead of
## the player along its way, waits when they fall behind, and at the end of its way stands until the
## next stage moves it on: down the Hushline Stair, where it goes into the mist.
##
## A quest def may carry
##   "leads": [{"id", "when": [conditions], "body": "hart" | "humanoid", "tint"?, "npc"?,
##              "way": [PlaceRef specs] | "descent", "road"?: [PlaceRef specs], "ahead_m"?,
##              "wait_m"?, "walk"?}]
## `road` is a list of stops walked by road between them (RoadRoute), in place of `way`.
## For each lead id the first spec (across quests, in pack order) whose `when` holds is the one in
## force; none, and the lead is gone. `way` is walked point to point on the ground; "descent" is the
## Hushline Stair from its head to the step below the fortieth (StairDescent). `npc` dresses a
## humanoid lead as that person (their appearance), without their dialogue: a lead is seen, not met.
## Nothing is saved: a lead found again after a load stands ahead of the player on its way.

const GROUP := "leads"
const POLL_S := 0.25
const AHEAD_M := 45.0
const WAIT_M := 110.0
## m/s: the lead's own pace when the player is well back, and at most when they press it.
const WALK := 1.7
const FASTEST := 9.0
const ARRIVED_M := 2.0

var leads: Dictionary = {}          # lead id -> _Lead
var _look := PollTimer.new(POLL_S)


static func ensure() -> Leads:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is Leads:
		return found as Leads
	var made := Leads.new()
	made.name = "Leads"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _look.due(delta):
		refresh()


## The spec in force for each lead id: {id: spec}.
func wanted() -> Dictionary:
	var out: Dictionary = {}
	var ctx: SocialContext = Social.ctx if Social != null else null
	if ctx == null:
		return out
	for def in ContentDB.all("quest"):
		for l_v in def.get("leads", []):
			if typeof(l_v) != TYPE_DICTIONARY:
				continue
			var l: Dictionary = l_v
			var id := str(l.get("id", ""))
			if id.is_empty() or out.has(id):
				continue
			var when: Variant = l.get("when", [])
			if typeof(when) != TYPE_ARRAY or (when as Array).is_empty() or not Conditions.all_of(when, ctx):
				continue
			out[id] = l
	return out


func refresh() -> void:
	if not is_inside_tree():
		return
	var want := wanted()
	for id in leads.keys():
		if not want.has(id):
			(leads[id] as Node).queue_free()
			leads.erase(id)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for id in want:
		var spec: Dictionary = want[id]
		var lead: _Lead = leads.get(id)
		if lead != null and is_instance_valid(lead) and lead.spec == spec and not lead.way.is_empty():
			continue
		# worked out once a spec comes into force: a road's route is a search over every road
		var way := way_of(spec)
		if way.size() < 1:
			continue
		if lead == null or not is_instance_valid(lead):
			lead = _Lead.make(spec)
			add_child(lead)
			leads[id] = lead
			lead.spec = {}
		if lead.spec != spec or lead.way.is_empty():
			lead.spec = spec
			lead.set_way(way, player.global_position)


## The points a spec walks, on the ground.
func way_of(spec: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var way: Variant = spec.get("way", [])
	if typeof(way) == TYPE_STRING and str(way) == "descent":
		var d := get_tree().get_first_node_in_group(StairDescent.GROUP) as StairDescent
		if d == null or d.step_at.is_empty():
			return out
		var end := d.step_at[mini(StairDescent.LEAD_STEP, d.step_at.size()) - 1]
		var m := 0.0
		while m < end:
			out.append(d.point_along(m))
			m += 2.0
		out.append(d.point_along(end))
		return out
	var road: Variant = spec.get("road", null)
	if road is Array:
		# the stops, joined by road (RoadRoute): the way the fingerposts name
		var stops: Array[Vector2] = []
		for p in road:
			if PlaceRef.is_spec(p):
				var xz := PlaceRef.point_xz(p)
				if xz != Vector2.INF:
					stops.append(xz)
		for i in range(stops.size() - 1):
			var leg := RoadRoute.between(stops[i], stops[i + 1])
			if leg.is_empty():
				leg = PackedVector2Array([stops[i], stops[i + 1]])
			for k in leg.size():
				if k == 0 and i > 0:
					continue
				out.append(Vector3(leg[k].x, WorldProbe.get_height(leg[k].x, leg[k].y), leg[k].y))
		return out
	if typeof(way) != TYPE_ARRAY:
		return out
	for p in way:
		if PlaceRef.is_spec(p):
			var at := PlaceRef.point(p)
			if at != Vector3.INF:
				out.append(at)
	return out


## The one thing followed: a body walking its way, keeping ahead of the player.
class _Lead extends Node3D:
	var spec: Dictionary = {}
	var way := PackedVector3Array()
	var index := 0
	var body: Node3D = null
	var placeholder: PlaceholderBody = null
	var humanoid: Node = null
	var _speed := 0.0
	var _last_player := Vector3.INF

	static func make(from: Dictionary) -> _Lead:
		var l := _Lead.new()
		l.spec = from
		l.name = "Lead_" + str(from.get("id", "?"))
		return l

	func _ready() -> void:
		var pivot := Node3D.new()
		pivot.name = "Model"
		pivot.rotation.y = PI
		add_child(pivot)
		body = pivot
		var kind := str(spec.get("body", "hart"))
		var tint := Color(str(spec.get("tint", "#9a9894")))
		if kind == "humanoid" and ResourceLoader.exists("res://actors/shared/humanoid_model.tscn"):
			humanoid = (load("res://actors/shared/humanoid_model.tscn") as PackedScene).instantiate()
			pivot.add_child(humanoid)
			var npc_id := str(spec.get("npc", ""))
			var npc := ContentDB.get_or_empty(npc_id)
			if not npc.is_empty() and humanoid.has_method("apply_appearance"):
				# dressed as the person, from their def, as an Npc dresses itself
				var block: Dictionary = npc.get("appearance", {}) if npc.get("appearance", {}) is Dictionary else {}
				var culture := WorldProbe.culture_of_place(str(npc.get("home_place", "")))
				var look := CharacterAppearance.random(int(block.get("seed", abs(npc_id.hash()))), culture)
				humanoid.call("apply_appearance", look.to_dict())
			if humanoid.has_method("play_intent"):
				humanoid.call("play_intent", "Idle")
		else:
			placeholder = PlaceholderBody.build("quadruped", tint, float(spec.get("scale", 1.0)), "hart")
			pivot.add_child(placeholder)
		add_to_group("lead")

	## Walks `new_way` from where it is nearest the player's way ahead: the point after the one
	## nearest the player, a stretch ahead of them.
	func set_way(new_way: PackedVector3Array, player_at: Vector3) -> void:
		var fresh := way.is_empty()
		way = new_way
		if fresh:
			var best := 0
			var best_d := INF
			for i in way.size():
				var d := Vector2(way[i].x - player_at.x, way[i].z - player_at.z).length()
				if d < best_d:
					best_d = d
					best = i
			index = mini(best + (1 if best_d < float(spec.get("ahead_m", Leads.AHEAD_M)) else 0), way.size() - 1)
			var from := player_at
			var to := way[index]
			var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
			var ahead := float(spec.get("ahead_m", Leads.AHEAD_M))
			var start := to if dir.length() < ahead else from + dir.normalized() * ahead
			global_position = _grounded(start)
		else:
			index = 0
			# a new way starts from where it stands: the nearest of its points
			var best_d := INF
			for i in way.size():
				var d := global_position.distance_to(way[i])
				if d < best_d:
					best_d = d
					index = i

	func _grounded(p: Vector3) -> Vector3:
		var q := p
		q.y = WorldProbe.get_height(p.x, p.z, p.y)
		return q

	func _process(delta: float) -> void:
		if way.is_empty():
			return
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
		var ahead := float(spec.get("ahead_m", Leads.AHEAD_M))
		var wait := float(spec.get("wait_m", Leads.WAIT_M))
		var gap := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
		var player_speed := 0.0
		if _last_player != Vector3.INF and delta > 0.0:
			player_speed = Vector2(player.global_position.x - _last_player.x, player.global_position.z - _last_player.z).length() / delta
		_last_player = player.global_position
		var want := 0.0
		var at_end := index >= way.size() - 1 and global_position.distance_to(way[way.size() - 1]) <= Leads.ARRIVED_M
		if not at_end:
			if gap < ahead:
				# pressed: keep the stretch, at the pace the player comes on at
				want = clampf(maxf(float(spec.get("walk", Leads.WALK)) * 1.6, player_speed * 1.05), 0.0, Leads.FASTEST)
			elif gap < wait:
				want = float(spec.get("walk", Leads.WALK))
		_speed = lerpf(_speed, want, 1.0 - exp(-delta * 3.0))
		var target := way[index]
		var to := target - global_position
		var flat := Vector2(to.x, to.z)
		if flat.length() <= Leads.ARRIVED_M and index < way.size() - 1:
			index += 1
			return
		var face := flat.normalized() if flat.length() > 0.05 else Vector2.ZERO
		if at_end or _speed < 0.05:
			# standing: it turns to look back at who follows
			var back := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
			if back.length() > 0.5:
				face = back.normalized()
		if face != Vector2.ZERO:
			rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.y), 1.0 - exp(-delta * 4.0))
		if _speed > 0.01 and flat.length() > 0.05:
			var step := minf(_speed * delta, flat.length())
			var next := global_position + Vector3(flat.x, 0.0, flat.y).normalized() * step
			next.y = lerpf(global_position.y, target.y, step / maxf(flat.length(), 0.01)) if str(spec.get("way", "")) == "descent" \
					else WorldProbe.get_height(next.x, next.z, global_position.y)
			global_position = next
		var gait := clampf(_speed / 4.0, 0.0, 1.0)
		if placeholder != null:
			placeholder.update(delta, "Walk" if _speed > 0.05 else "Idle", 0.0, Vector2(0.0, gait), false)
		elif humanoid != null and humanoid.has_method("set_locomotion"):
			humanoid.call("set_locomotion", Vector2(0.0, _speed), false)
