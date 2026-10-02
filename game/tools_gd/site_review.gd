extends Node3D
## Renders a large site so it can be judged as a place (docs/WORLD_LIFE_INTERIORS.md, "Testing"):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy res://tools_gd/site_review.tscn -- --site=<interior id>[,<id>] --out=<abs dir>
##   ... -- --poi=<poi id>[,<poi id>] --out=<abs dir>
##
## An inside (`--site`): the view through the way in, every room from beside its first doorway
## looking across it, and a plan from straight above (the rock is drawn from inside only, so the roof
## is not in the way). Lit only by what the site stands up and a faint ambient, as a player finds it.
## An outside (`--poi`): the POI's dressing raised on a flat pad of grass under a low sun (the world
## has no pad there until the next world build), seen from four sides, from the approach, from the
## yard, from its walkway and from above. Then tools/capture/contact_sheet.py tiles the PNGs.

var cam: Camera3D
var out_dir := "user://site_review"
## `--radius=<m>`: the outside's views stand as for a place this big (else the def's radius_m): a
## wayside find seen from 48 m is a speck.
var radius_override := 0.0
var shots: Array = []
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	var sites: Array = []
	var pois: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			sites = Array(a.substr(7).split(",", false))
		elif a.begins_with("--poi="):
			pois = Array(a.substr(6).split(",", false))
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--radius="):
			radius_override = float(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	we.environment = _env
	add_child(we)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 800.0
	cam.fov = 72.0
	add_child(cam)
	cam.current = true
	_sun = DirectionalLight3D.new()
	add_child(_sun)
	for s in sites:
		await _inside(str(s))
		await _take()
		for n in get_children():
			if n is SiteInterior:
				n.queue_free()
		await get_tree().process_frame
	for p in pois:
		await _outside(str(p))
	await _take()
	get_tree().quit(0)


func _inside(id: String) -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.01, 0.01, 0.012)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.4, 0.44, 0.52)
	_env.ambient_light_energy = 0.35
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_white = 2.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.45
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.1, 0.1, 0.12)
	_env.fog_density = 0.006
	_sun.visible = false
	var site := SiteInterior.new()
	site.set_meta("interior_id", id)
	site.paced_override = 0
	add_child(site)
	for i in 30:
		await get_tree().process_frame
	var slug := "b_inside_" + Ids.name_of(id)
	var plan := site.plan
	var ent := site.get_node("Entrance") as Node3D
	var fwd := -ent.transform.basis.z
	var eye := ent.position + Vector3.UP * 1.65
	shots.append({"label": "%s_00_way_in" % slug, "pos": eye + fwd * 0.3, "look": eye + fwd * 6.0 + Vector3.DOWN * 0.5})
	# where the eye stands at the way in: the floor under it and the roof over it (a way in whose
	# eye is in the rock renders black)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var probe := func(from: Vector3, to: Vector3) -> float:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(site.to_global(from), site.to_global(to)))
		return -1.0 if hit.is_empty() else site.to_global(from).distance_to(hit["position"])
	print("site review: way in eye %s: floor %.2f below, roof %.2f above, wall %.2f ahead, lights %d" % [eye,
			probe.call(eye, eye + Vector3.DOWN * 8.0), probe.call(eye, eye + Vector3.UP * 12.0),
			probe.call(eye, eye + fwd * 20.0), site.dress.lights.size() if site.dress != null else 0])
	var n := 1
	for r in plan.rooms:
		var c: Vector3 = r["centre"]
		var half: Vector3 = r["half"]
		var ms := plan.mouths_of(r)
		var stand := c + Vector3(half.x * 0.6, 0.0, 0.0)
		if not ms.is_empty():
			var m: Vector3 = ms[0]["at"]
			stand = m + (c - m).normalized() * 0.8
			stand.y = m.y
		var h := minf(half.y * 0.55, 2.2) if r["role"] != "boss" else 3.0
		var pos := stand + Vector3.UP * maxf(h, 1.6)
		# whether the eye is in the room or in its rock, and what of the room's light reaches it: a
		# black frame is one or the other (Cinderlea's were the eye in the rock at a drop's mouth)
		var lit := 0
		if site.dress != null:
			for l in site.dress.lights:
				var o := l as OmniLight3D
				if o != null and bool(o.get_meta("budget_on", true)) and o.position.distance_to(pos) < o.omni_range:
					lit += 1
		var seen: float = probe.call(c + Vector3.UP * 1.0, pos)
		var hidden := seen >= 0.0 and seen < (pos - (c + Vector3.UP)).length() - 0.05
		print("site review: room %s eye %s: floor %.2f below, roof %.2f above, %s from the room's middle, %d lights reach it" % [
				r["id"], pos, probe.call(pos, pos + Vector3.DOWN * 8.0), probe.call(pos, pos + Vector3.UP * 12.0),
				"hidden by rock %.1f m out" % seen if hidden else "seen", lit])
		# an eye behind the rock (round the doorway's bend, or in a lump of the wall) sees the rock: it
		# is brought in toward the room's middle until the middle sees it
		var look := c + Vector3.UP * 1.0 - (c - stand).normalized() * -2.0
		for step_in in 12:
			seen = probe.call(c + Vector3.UP * 1.0, pos)
			if seen < 0.0 or seen >= (pos - (c + Vector3.UP)).length() - 0.05:
				break
			pos = pos.lerp(c + Vector3.UP * maxf(h, 1.6), 0.15)
		shots.append({"label": "%s_%02d_%s_%s" % [slug, n, r["id"], r["set_piece"] if r["set_piece"] != "" else r["role"]],
				"pos": pos, "look": look})
		# and the way it was come in by, from the room's middle: what a player turning round sees
		if not ms.is_empty():
			var mid := c + Vector3.UP * maxf(minf(half.y * 0.5, 2.0), 1.6)
			shots.append({"label": "%s_%02d_%s_way_back" % [slug, n, r["id"]], "pos": mid,
					"look": (ms[0]["at"] as Vector3) + Vector3.UP * 1.2})
		n += 1
	var b := plan.bounds
	var mid := b.get_center()
	shots.append({"label": "%s_99_plan" % slug, "pos": Vector3(mid.x, b.end.y + 60.0, mid.z + 0.01), "look": Vector3(mid.x, b.position.y, mid.z),
			"ortho": maxf(b.size.x, b.size.z) * 1.05})


func _outside(id: String) -> void:
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.42, 0.55, 0.72)
	ps.sky_horizon_color = Color(0.78, 0.8, 0.8)
	ps.ground_horizon_color = Color(0.5, 0.52, 0.46)
	sky.sky_material = ps
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.8
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.fog_enabled = false
	_sun.visible = true
	_sun.rotation_degrees = Vector3(-32, 140, 0)
	_sun.light_energy = 1.4
	_sun.shadow_enabled = true
	# the places' lamps and fires (PoiKit.light) are NightLights' sources: without its pool nothing
	# a builder lit was lit here
	if get_node_or_null("NightLights") == null:
		var nl := NightLights.new()
		nl.name = "NightLights"
		add_child(nl)
	var def := ContentDB.get_def(id)
	# the pad: flat grass, standing in for the ground the next world build flattens there
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	pad.mesh = pm
	# in the terrain's own texture for the region, at its own scale (PoiBuilders.GROUND_SLOTS), so
	# what a builder lays in the ground's look meets it as it would the land
	var region := Ids.name_of(str(def.get("region", "core:region/hearthvale")))
	var builders: GDScript = load(PoiDressing.BUILDERS_PATH)
	var slot := str((builders.get("REGION_GROUND") as Dictionary).get(region, "vale_grass"))
	var spec: Array = (builders.get("GROUND_SLOTS") as Dictionary).get(slot, [2.6, 0.42])
	var gm := StandardMaterial3D.new()
	var tex_path := "res://assets/textures/terrain/%s_albedo_height.png" % slot
	if ResourceLoader.exists(tex_path):
		gm.albedo_texture = load(tex_path)
	gm.albedo_color = Color(float(spec[1]), float(spec[1]), float(spec[1]))
	gm.uv1_triplanar = true
	gm.uv1_world_triplanar = true
	gm.uv1_scale = Vector3.ONE / float(spec[0])
	gm.roughness = 0.95
	pad.material_override = gm
	add_child(pad)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240, 1, 240)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	var entry := {"place_id": id, "pos": [0.0, 0.0, 0.0], "radius_flat_m": float(def.get("radius_m", 24.0)), "radius_level_m": float(def.get("radius_m", 24.0))}
	var d := PoiDressing.raise(entry, def)
	add_child(d)
	for i in 30:
		await get_tree().process_frame
	var slug := "a_outside_" + Ids.name_of(id)
	var r := float(def.get("radius_m", 24.0)) if radius_override <= 0.0 else radius_override
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		shots.append({"label": "%s_0%d_side" % [slug, i], "pos": Vector3(sin(a), 0.0, cos(a)) * (r * 2.0) + Vector3.UP * (r * 0.45),
				"look": Vector3.UP * 3.0, "ground": [pad, body]})
	# the approach, through the gate or the mouth, at eye height
	var door := d.find_children("*", "Door", true, false)
	var gate := Vector3.ZERO
	for n in d.find_children("*", "", true, false):
		if n.name == "GateLeaves" or n.name == "Hook":
			gate = (n as Node3D).position
	shots.append({"label": "%s_10_approach" % slug, "pos": Vector3(gate.x, 0.0, gate.z) * 2.0 + Vector3.UP * 1.7, "look": Vector3.UP * 2.0})
	# close, from three-quarters and a little up: the look of the thing
	var hero_a := atan2(gate.x, gate.z) + 0.7 if gate != Vector3.ZERO else 0.9
	shots.append({"label": "%s_05_near" % slug, "pos": Vector3(sin(hero_a), 0.0, cos(hero_a)) * (r * 1.25) + Vector3.UP * (r * 0.28),
			"look": Vector3.UP * 3.5, "ground": [pad, body]})
	# a delve's mouth, from its approach at eye height
	var den := d.find_child("the_mouth", true, false) as Node3D
	if den != null and d.find_child("Garrison", true, false) == null:
		var into := Vector3(den.position.x, 0.0, den.position.z).normalized()
		shots.append({"label": "%s_12_the_mouth" % slug, "pos": den.position - into * 12.0 + Vector3.UP * 2.2,
				"look": den.position - into * 3.0 + Vector3.UP * 1.7})
		# from the head of the way down into it, standing on the ground it is cut into
		var side := Vector3(into.z, 0.0, -into.x)
		shots.append({"label": "%s_13_the_way_down" % slug, "pos": den.position - into * 21.0 + side * 3.0 + Vector3.UP * 4.3,
				"look": den.position - into * 4.0 + Vector3.UP * 1.0})
	if not door.is_empty():
		var dp := (door[0] as Node3D).position
		var face := (door[0] as Node3D).transform.basis.z
		# a door round a bend says where it is seen from
		var from: Vector3 = (door[0] as Node3D).get_meta("view_from", dp + face * 6.0)
		shots.append({"label": "%s_11_the_door" % slug, "pos": from + Vector3.UP * 1.7, "look": dp + Vector3.UP * 1.4})
	# up on the walls, if it has any: where a walker of the walls stands
	var sp := d.find_child("Garrison", true, false) as EnemySpawner
	if sp != null:
		for e in sp.living:
			if e.patrol_points.size() > 1:
				var p: Vector3 = e.patrol_points[0]
				shots.append({"label": "%s_12_walkway" % slug, "pos": p + Vector3.UP * 1.7 + (p - Vector3(0, p.y, 0)).normalized() * -0.4,
						"look": Vector3(-p.x, p.y, -p.z) * 0.3 + Vector3.UP * 0.5})
				break
		shots.append({"label": "%s_13_yard" % slug, "pos": Vector3(gate.x, 0.0, gate.z) * 0.55 + Vector3.UP * 1.7, "look": Vector3(-gate.x, 3.0, -gate.z)})
	shots.append({"label": "%s_20_above" % slug, "pos": Vector3(0.0, r * 3.0, r * 0.8), "look": Vector3.ZERO})
	await _take()
	d.queue_free()
	pad.queue_free()
	body.queue_free()
	await get_tree().process_frame


func _take() -> void:
	# the first frames after a build draw before every light is in: let them pass
	for i in 30:
		await get_tree().process_frame
	for s in shots:
		if s.has("ortho"):
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(s["ortho"])
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP if absf(((s["look"] as Vector3) - (s["pos"] as Vector3)).normalized().y) < 0.99 else Vector3.FORWARD)
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, s["label"]])
		print("site review: %s" % s["label"])
	shots.clear()
