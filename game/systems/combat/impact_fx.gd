class_name ImpactFx
extends RefCounted
## What a landed blow knocks off what it hit (Impact.land): short particle bursts that clear
## themselves up, and on flesh a stain on the ground under the blow that fades.
##
##   metal (armour, a guard, a parry): sparks, bright and quick, flung off the struck face;
##   stone: a puff of dust and a scatter of chips;
##   wood: splinters and a little dust;
##   flesh: a restrained spray of dark blood along the blow, and a stain where it falls. With
##          gameplay.blood off, a small dull puff instead and no stain.
## accessibility.reduce_flashing halves the sparks and dims them. The counts scale with the blow.

## Stains on the ground at once, at most: the oldest goes first.
const MOST_STAINS := 24
## How long a stain lies before it has faded out (s).
const STAIN_S := 24.0
const GROUP := "impact_fx"

static var _stains: Array = []
static var _stain_tex: Texture2D = null
static var _mats: Dictionary = {}


## One burst at `point`, the blow travelling along `push`, of strength `force` (0..1).
static func burst(victim: Node3D, material: String, point: Vector3, push: Vector3, force: float, result: String) -> void:
	var root := _root(victim)
	if root == null:
		return
	var out := -push                      # off the struck face, back toward the blow
	match material:
		"metal":
			var n := int(lerpf(10.0, 26.0, force) * (1.3 if result == "parried" else 1.0))
			var dim := bool(Settings.get_value("accessibility", "reduce_flashing", false))
			if dim:
				n = n / 2
			_emit(root, "sparks", point, (out + push.cross(Vector3.UP) * 0.3).normalized(), n,
					Color(1.0, 0.58, 0.18) * (0.7 if dim else 1.25), 0.28, lerpf(3.5, 6.5, force), 55.0, 9.8, Vector2(0.011, 0.07))
		"stone":
			_emit(root, "dust", point, out, int(lerpf(5.0, 10.0, force)), Color(0.62, 0.6, 0.56, 0.55), 0.7, 0.9, 70.0, -0.3, Vector2(0.16, 0.16))
			_emit(root, "chips", point, out, int(lerpf(6.0, 14.0, force)), Color(0.42, 0.4, 0.37), 0.5, lerpf(2.0, 3.6, force), 60.0, 9.8, Vector2(0.025, 0.025))
		"wood":
			_emit(root, "splinters", point, out, int(lerpf(6.0, 14.0, force)), Color(0.55, 0.4, 0.24), 0.55, lerpf(2.2, 3.8, force), 55.0, 9.8, Vector2(0.012, 0.06))
			_emit(root, "dust", point, out, int(lerpf(3.0, 6.0, force)), Color(0.6, 0.52, 0.42, 0.45), 0.6, 0.7, 70.0, -0.2, Vector2(0.12, 0.12))
		_:
			var bleeds := not victim.has_method("bleeds") or bool(victim.call("bleeds"))
			if bleeds and bool(Settings.get_value("gameplay", "blood", true)):
				# along the blow and a little up, not back at the one who struck it
				var along := (push + Vector3.UP * 0.35).normalized()
				_emit(root, "blood", point, along, int(lerpf(10.0, 22.0, force)), Color(0.32, 0.03, 0.03), 0.45, lerpf(1.6, 3.0, force), 32.0, 9.8, Vector2(0.028, 0.028))
				_stain(victim, point + push * lerpf(0.15, 0.4, force), lerpf(0.22, 0.42, force))
			elif not bleeds:
				# the dead give up dust from their rags, not blood
				_emit(root, "dust", point, out, int(lerpf(5.0, 9.0, force)), Color(0.55, 0.5, 0.44, 0.5), 0.6, 0.8, 70.0, -0.2, Vector2(0.14, 0.14))
			else:
				_emit(root, "dust", point, out, 4, Color(0.55, 0.52, 0.5, 0.4), 0.4, 0.6, 60.0, -0.2, Vector2(0.08, 0.08))


static func _root(victim: Node3D) -> Node:
	if victim == null or not victim.is_inside_tree():
		return null
	var tree := victim.get_tree()
	return tree.current_scene if tree.current_scene != null else tree.root


## A one-shot burst of `count` bits of `size` (w, h: a streak when h > w), flying along `dir` in a
## cone of `spread` degrees at `speed`, falling at `gravity`, living `life` seconds.
static func _emit(root: Node, kind: String, point: Vector3, dir: Vector3, count: int, colour: Color,
		life: float, speed: float, spread: float, gravity: float, size: Vector2) -> CPUParticles3D:
	if count <= 0:
		return null
	var p := CPUParticles3D.new()
	# a new CPUParticles3D is already emitting: held until it stands at the blow, or its first
	# burst leaves from the scene's origin (the first film showed sparks at the player's feet)
	p.emitting = false
	p.name = "Impact_%s" % kind
	p.add_to_group(GROUP)
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.direction = dir if dir.length_squared() > 0.0001 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.damping_min = 1.0 if gravity < 0.0 else 0.2
	p.damping_max = 2.0 if gravity < 0.0 else 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	if kind == "dust":
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.5))
		grow.add_point(Vector2(1.0, 1.4))
		p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(colour, colour.a))
	fade.set_color(1, Color(colour, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = _material(kind)
	p.mesh = quad
	if size.y > size.x * 1.5:
		p.particle_flag_align_y = true
	root.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func _material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	match kind:
		"sparks":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			# a streak along its flight, turned about it to face the eye
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m.billboard_keep_scale = true
		"splinters":
			m.roughness = 0.9
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m.billboard_keep_scale = true
		"dust":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = _soft_dot()
		"blood":
			m.roughness = 0.35
			m.albedo_texture = _soft_dot()
		_:
			m.roughness = 0.9
	_mats[kind] = m
	return m


static var _dot: Texture2D = null


## A round spot, soft at its edge, for dust and drops.
static func _soft_dot() -> Texture2D:
	if _dot != null:
		return _dot
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## A stain on the ground below `at`, `radius` across, that fades over STAIN_S.
static func _stain(victim: Node3D, at: Vector3, radius: float) -> void:
	var root := _root(victim)
	if root == null:
		return
	var space := victim.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0)
	q.exclude = [victim.get_rid()] if victim is CollisionObject3D else []
	var hit := space.intersect_ray(q)
	var ground := at
	var normal := Vector3.UP
	if not hit.is_empty():
		ground = hit["position"]
		normal = hit["normal"]
	else:
		if World.terrain() == null:
			return
		ground.y = World.get_height(at.x, at.z)
	var quad := MeshInstance3D.new()
	quad.name = "Impact_stain"
	quad.add_to_group(GROUP)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(radius, radius) * 2.0
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_texture = _stain_texture()
	m.albedo_color = Color(0.3, 0.02, 0.02, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.4
	quad.material_override = m
	root.add_child(quad)
	# flat on the ground, a hair above it, turned at random
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	# the quad faces its +Z: turn that up along the ground's normal
	var basis := Basis(y, randf() * TAU) * Basis(x, y.cross(x), y)
	quad.global_transform = Transform3D(basis, ground + y * 0.012)
	var tw := quad.create_tween()
	tw.tween_interval(STAIN_S * 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, STAIN_S * 0.4)
	tw.tween_callback(quad.queue_free)
	_stains.append(quad)
	while _stains.size() > MOST_STAINS:
		var old: Variant = _stains.pop_front()
		if old is Node and is_instance_valid(old):
			(old as Node).queue_free()


static func _stain_texture() -> Texture2D:
	if _stain_tex != null:
		return _stain_tex
	var rng := RandomNumberGenerator.new()
	rng.seed = 7707
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var blots: Array = [[Vector2(32, 32), 13.0]]
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 22.0)
		blots.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * r, rng.randf_range(2.0, 6.0)])
	for y in n:
		for x in n:
			var v := 0.0
			for b: Array in blots:
				var d := Vector2(x, y).distance_to(b[0]) / float(b[1])
				v = maxf(v, clampf(1.2 - d, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(v * 1.4, 0.0, 1.0)))
	_stain_tex = ImageTexture.create_from_image(img)
	return _stain_tex
