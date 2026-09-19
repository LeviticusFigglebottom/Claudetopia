class_name PlaceholderBody
extends Node3D
## Stand-in body until the forge delivers rigs: a capsule torso with limb blocks (humanoid) or a
## box body with four legs (quadruped), posed procedurally per clip so attacks, dodges, blocks,
## staggers, knockdowns and deaths read on screen. Built in Model space (+Z is forward).

var kind: String = "humanoid"
var variant: String = ""
var tint: Color = Color(0.85, 0.8, 0.7)
var body_scale: float = 1.0
var parts: Dictionary = {}          # name -> Node3D pivot
var pose: Dictionary = {}           # name -> target Vector3 rotation (radians)
var pose_pos: Dictionary = {}       # name -> target position offset
var base_pos: Dictionary = {}       # name -> rest position
var clip: String = ""
var events: Dictionary = {}
var clip_length: float = 1.0
var _phase: float = 0.0
var _time: float = 0.0


static func build(body_kind: String, body_tint: Color, scale_factor: float = 1.0, body_variant: String = "") -> PlaceholderBody:
	var b := PlaceholderBody.new()
	b.name = "PlaceholderBody"
	b.kind = body_kind
	b.variant = body_variant
	b.tint = body_tint
	b.body_scale = scale_factor
	return b


func _ready() -> void:
	if kind == "quadruped":
		_build_quadruped()
	else:
		_build_humanoid()
	scale = Vector3.ONE * body_scale


func _mat(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.metallic = metallic
	return m


func _pivot(pivot_name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pivot_name
	p.position = pos
	parent.add_child(p)
	parts[pivot_name] = p
	base_pos[pivot_name] = pos
	pose[pivot_name] = Vector3.ZERO
	pose_pos[pivot_name] = Vector3.ZERO
	return p


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, metallic)
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _build_humanoid() -> void:
	var skin := tint
	var cloth := tint.darkened(0.35)
	var hips := _pivot("hips", self, Vector3(0.0, 0.95, 0.0))
	var torso := _pivot("torso", hips, Vector3.ZERO)
	_capsule(torso, 0.2, 0.62, Vector3(0.0, 0.36, 0.0), cloth)
	_sphere(torso, 0.13, Vector3(0.0, 0.72, 0.0), skin)
	var sl := _pivot("shoulder_l", torso, Vector3(-0.28, 0.6, 0.0))
	_box(sl, Vector3(0.11, 0.58, 0.11), Vector3(0.0, -0.29, 0.0), skin)
	var sr := _pivot("shoulder_r", torso, Vector3(0.28, 0.6, 0.0))
	_box(sr, Vector3(0.11, 0.58, 0.11), Vector3(0.0, -0.29, 0.0), skin)
	_box(sr, Vector3(0.04, 0.04, 0.85), Vector3(0.04, -0.6, 0.38), Color(0.55, 0.56, 0.6), 0.7).name = "WeaponStick"
	var hl := _pivot("hip_l", hips, Vector3(-0.12, 0.0, 0.0))
	_box(hl, Vector3(0.15, 0.92, 0.15), Vector3(0.0, -0.46, 0.0), cloth)
	var hr := _pivot("hip_r", hips, Vector3(0.12, 0.0, 0.0))
	_box(hr, Vector3(0.15, 0.92, 0.15), Vector3(0.0, -0.46, 0.0), cloth)


func _build_quadruped() -> void:
	var fur := tint
	var dark := tint.darkened(0.3)
	var boar := variant == "boar"
	var hips := _pivot("hips", self, Vector3(0.0, 0.55, 0.0))
	var body := _pivot("torso", hips, Vector3.ZERO)
	_box(body, Vector3(0.5 if boar else 0.4, 0.44 if boar else 0.4, 1.0), Vector3(0.0, 0.05, 0.0), fur)
	var head := _pivot("head", body, Vector3(0.0, 0.2, 0.55))
	_box(head, Vector3(0.28, 0.26, 0.36), Vector3(0.0, 0.0, 0.12), fur)
	if boar:
		_box(head, Vector3(0.16, 0.14, 0.22), Vector3(0.0, -0.08, 0.38), dark)
		_box(head, Vector3(0.03, 0.03, 0.16), Vector3(0.1, -0.12, 0.42), Color(0.95, 0.92, 0.8))
		_box(head, Vector3(0.03, 0.03, 0.16), Vector3(-0.1, -0.12, 0.42), Color(0.95, 0.92, 0.8))
	else:
		_box(head, Vector3(0.12, 0.12, 0.24), Vector3(0.0, -0.06, 0.36), dark)
		_box(head, Vector3(0.06, 0.12, 0.03), Vector3(0.09, 0.18, 0.02), dark)
		_box(head, Vector3(0.06, 0.12, 0.03), Vector3(-0.09, 0.18, 0.02), dark)
	var tail := _pivot("tail", body, Vector3(0.0, 0.12, -0.5))
	_box(tail, Vector3(0.06, 0.06, 0.4 if not boar else 0.18), Vector3(0.0, 0.05, -0.2 if not boar else -0.09), dark)
	for leg in [["leg_fl", Vector3(-0.15, -0.1, 0.33)], ["leg_fr", Vector3(0.15, -0.1, 0.33)], ["leg_bl", Vector3(-0.15, -0.1, -0.33)], ["leg_br", Vector3(0.15, -0.1, -0.33)]]:
		var p := _pivot(leg[0], hips, leg[1])
		_box(p, Vector3(0.1, 0.48, 0.1), Vector3(0.0, -0.24, 0.0), dark)


func begin(new_clip: String, clip_events: Dictionary, length: float) -> void:
	clip = new_clip
	events = clip_events
	clip_length = maxf(length, 0.05)
	_time = 0.0


func _frac(event_name: String, fallback: float) -> float:
	if events.has(event_name) and clip_length > 0.0:
		return clampf(float(events[event_name]) / clip_length, 0.0, 1.0)
	return fallback


func update(delta: float, current_clip: String, p: float, locomotion: Vector2, sneaking: bool) -> void:
	_time += delta
	# play_intent() always calls begin() with the clip's timing; this only resyncs the name.
	clip = current_clip
	for k in pose.keys():
		pose[k] = Vector3.ZERO
		pose_pos[k] = Vector3.ZERO
	var mag := clampf(locomotion.length(), 0.0, 1.0)
	_phase += delta * (4.0 + 9.0 * mag) * (1.0 if mag > 0.05 else 0.0)
	if kind == "quadruped":
		_pose_quadruped(current_clip, p, mag)
	else:
		_pose_humanoid(current_clip, p, mag, sneaking)
	var k := 1.0 - exp(-18.0 * delta)
	for part_name in parts.keys():
		var n: Node3D = parts[part_name]
		n.rotation = n.rotation.lerp(pose[part_name], k)
		n.position = n.position.lerp(base_pos[part_name] + pose_pos[part_name], k)


func _pose_humanoid(c: String, p: float, mag: float, sneaking: bool) -> void:
	var s := sin(_phase)
	var leg_amp := 0.35 + 0.55 * mag
	var arm_amp := 0.25 + 0.4 * mag
	var moving := mag > 0.05
	# locomotion base layer
	if moving:
		pose["hip_l"].x = s * leg_amp
		pose["hip_r"].x = -s * leg_amp
		pose["shoulder_l"].x = -s * arm_amp
		pose["shoulder_r"].x = s * arm_amp
		pose_pos["hips"].y = absf(s) * 0.04 * mag
	else:
		pose["shoulder_l"].x = -0.12 + 0.02 * sin(_time * 2.0)
		pose["shoulder_r"].x = -0.12 + 0.02 * sin(_time * 2.0)
	if sneaking:
		pose_pos["hips"].y -= 0.25
		pose["hip_l"].x -= 0.5
		pose["hip_r"].x -= 0.5
		pose["torso"].x += 0.35
	var hs := _frac("hit_start", 0.4)
	var he := _frac("hit_end", 0.6)
	var sp := sin(PI * p)
	match c:
		"Attack_1H_Light_1", "Attack_1H_Light_3", "Attack_Dagger_1", "Attack_Unarmed_1", "Attack_1H_Light_2", "Attack_Dagger_2", "Attack_Unarmed_2":
			var a := _swing(p, hs, he, -2.5, 0.6)
			pose["shoulder_r"].x = a
			pose["torso"].y = -0.35 if p < hs else 0.4 * (1.0 - (p - hs) / maxf(1.0 - hs, 0.01))
			if c.ends_with("_2"):
				pose["shoulder_r"].z = -0.6
			if c.begins_with("Attack_Unarmed"):
				pose["shoulder_r"].x = _swing(p, hs, he, -0.4, -1.6)
		"Attack_1H_Heavy", "Attack_2H_Light_1", "Attack_2H_Light_2", "Attack_2H_Heavy", "Riposte", "Backstab":
			var a := _swing(p, hs, he, -2.9, 0.7)
			pose["shoulder_r"].x = a
			pose["shoulder_l"].x = a
			pose["shoulder_l"].z = 0.5
			pose["shoulder_r"].z = -0.5
			pose["torso"].x = -0.2 if p < hs else 0.35
			if c == "Riposte" or c == "Backstab":
				pose_pos["hips"].z = 0.3 * sp
		"Block_Idle", "Block_Hit":
			pose["shoulder_l"].x = -1.35
			pose["shoulder_l"].z = 0.55
			pose["shoulder_r"].x = -0.7
			if c == "Block_Hit":
				pose["torso"].x = -0.25 * sp
				pose_pos["hips"].z = -0.08 * sp
		"Parry":
			pose["shoulder_l"].x = -1.3 - 0.9 * sp
			pose["shoulder_l"].z = 0.55 - 0.8 * sp
			pose["shoulder_r"].x = -0.5
		"Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R":
			var roll := TAU * p
			match c:
				"Dodge_F": pose["hips"].x = roll
				"Dodge_B": pose["hips"].x = -roll
				"Dodge_L": pose["hips"].z = roll
				"Dodge_R": pose["hips"].z = -roll
			pose_pos["hips"].y = -0.35 * sp
			pose["hip_l"].x = -1.3
			pose["hip_r"].x = -1.3
			pose["shoulder_l"].x = -1.2
			pose["shoulder_r"].x = -1.2
		"Hit_Light", "Hit":
			pose["torso"].x = -0.3 * sp
			pose_pos["hips"].z = -0.08 * sp
		"Hit_Heavy":
			pose["torso"].x = -0.55 * sp
			pose_pos["hips"].z = -0.25 * sp
			pose["shoulder_l"].x = -0.8 * sp
			pose["shoulder_r"].x = -0.8 * sp
		"Stagger":
			pose["torso"].y = 0.5 * sin(TAU * p) * (1.0 - p)
			pose["torso"].x = -0.35 * sp
			pose["hip_l"].z = 0.25
			pose["hip_r"].z = -0.25
			pose_pos["hips"].z = -0.15 * sp
		"Knockdown":
			var q := smoothstep(0.0, 0.35, p)
			pose["hips"].x = -1.45 * q
			pose_pos["hips"].y = -0.6 * q
			pose["shoulder_l"].x = -1.5 * q
			pose["shoulder_r"].x = -1.5 * q
		"Get_Up":
			var q := 1.0 - smoothstep(0.0, 0.7, p)
			pose["hips"].x = -1.45 * q
			pose_pos["hips"].y = -0.6 * q
			pose["hip_l"].x = -0.8 * q
			pose["hip_r"].x = -0.8 * q
		"Death_A", "Death":
			var q := smoothstep(0.0, 0.55, p)
			pose["hips"].x = 1.5 * q
			pose_pos["hips"].y = -0.65 * q
			pose["shoulder_l"].x = -1.2 * q
			pose["shoulder_r"].x = -1.2 * q
		"Death_B":
			var q := smoothstep(0.0, 0.55, p)
			pose["hips"].z = 1.5 * q
			pose_pos["hips"].y = -0.65 * q
		"Cast_Quick", "Cast_Long", "Cast_Loop":
			var q := 1.0 if c == "Cast_Loop" else minf(p * 3.0, 1.0)
			pose["shoulder_l"].x = -1.5 * q
			pose["shoulder_r"].x = -1.5 * q
			pose["shoulder_l"].z = 0.4 * q
			pose["shoulder_r"].z = -0.4 * q
		"Bow_Draw", "Bow_Aim":
			pose["shoulder_l"].x = -1.55
			pose["shoulder_r"].x = -1.3
			pose_pos["shoulder_r"].z = -0.12 * (1.0 if c == "Bow_Aim" else p)
			pose["torso"].y = -0.5
		"Bow_Release":
			pose["shoulder_l"].x = -1.55
			pose["shoulder_r"].x = -1.0 + 0.5 * p
			pose["torso"].y = -0.5 * (1.0 - p)
		"Interact", "Pick_Up", "Work_Dig":
			pose["torso"].x = 0.7 * sp
			pose["shoulder_r"].x = -1.0 * sp
		"Jump_Start", "Jump_Loop", "Fall_Loop":
			pose["hip_l"].x = -0.6
			pose["hip_r"].x = -0.3
			pose["shoulder_l"].x = -0.5
			pose["shoulder_r"].x = -0.5
		"Jump_Land":
			pose_pos["hips"].y = -0.15 * sp
			pose["hip_l"].x = -0.4 * sp
			pose["hip_r"].x = -0.4 * sp
		"Wave", "Cheer", "Point":
			pose["shoulder_r"].x = -2.8 + 0.2 * sin(_time * 10.0)
		"Sit_Down", "Sit_Idle":
			pose["hip_l"].x = -1.5
			pose["hip_r"].x = -1.5
			pose_pos["hips"].y = -0.45
		"Sleep_Idle":
			pose["hips"].z = 1.5
			pose_pos["hips"].y = -0.65
		_:
			pass

func _pose_quadruped(c: String, p: float, mag: float) -> void:
	var s := sin(_phase)
	var amp := 0.3 + 0.6 * mag
	if mag > 0.05:
		pose["leg_fl"].x = s * amp
		pose["leg_br"].x = s * amp
		pose["leg_fr"].x = -s * amp
		pose["leg_bl"].x = -s * amp
		pose_pos["hips"].y = absf(s) * 0.04 * mag
		pose["torso"].x = -0.05 * s * mag
	else:
		pose["head"].x = 0.05 * sin(_time * 1.5)
	pose["tail"].x = -0.4 + 0.15 * sin(_time * 3.0)
	var hs := _frac("hit_start", 0.5)
	var he := _frac("hit_end", 0.7)
	var sp := sin(PI * p)
	match c:
		"Attack_1":
			if p < hs:
				pose["head"].x = 0.55 * (p / maxf(hs, 0.01))
				pose_pos["hips"].y = -0.12 * (p / maxf(hs, 0.01))
			elif p < he:
				pose["head"].x = -0.35
				pose_pos["hips"].z = 0.35
			else:
				pose["head"].x = 0.0
		"Attack_2":
			if p < hs:
				pose["torso"].x = 0.3 * (p / maxf(hs, 0.01))
				pose["head"].x = 0.5 * (p / maxf(hs, 0.01))
				pose["leg_fl"].x = 0.6 * sin(_time * 14.0)
			else:
				pose["torso"].x = -0.15
				pose["head"].x = -0.2
				pose_pos["hips"].z = 0.25
		"Hit", "Hit_Light":
			pose_pos["hips"].z = -0.15 * sp
			pose["torso"].x = -0.2 * sp
		"Hit_Heavy":
			pose_pos["hips"].z = -0.3 * sp
			pose["torso"].x = -0.4 * sp
		"Stagger":
			pose["torso"].z = 0.4 * sin(TAU * p) * (1.0 - p)
			pose_pos["hips"].z = -0.2 * sp
		"Knockdown":
			var q := smoothstep(0.0, 0.35, p)
			pose["hips"].z = 1.4 * q
			pose_pos["hips"].y = -0.3 * q
		"Get_Up":
			var q := 1.0 - smoothstep(0.0, 0.7, p)
			pose["hips"].z = 1.4 * q
			pose_pos["hips"].y = -0.3 * q
		"Death", "Death_A", "Death_B":
			var q := smoothstep(0.0, 0.55, p)
			pose["hips"].z = 1.5 * q
			pose_pos["hips"].y = -0.3 * q
			for leg in ["leg_fl", "leg_fr", "leg_bl", "leg_br"]:
				pose[leg].x = 0.8 * q
		"Sneak_Idle", "Sneak_Walk":
			pose_pos["hips"].y -= 0.15
		_:
			pass


## Arm swing profile: wind up to `back` before hit_start, sweep to `front` by hit_end, recover.
static func _swing(p: float, hs: float, he: float, back: float, front: float) -> float:
	if p < hs:
		return lerpf(-0.12, back, smoothstep(0.0, 1.0, p / maxf(hs, 0.01)))
	if p < he:
		return lerpf(back, front, (p - hs) / maxf(he - hs, 0.01))
	return lerpf(front, -0.12, smoothstep(0.0, 1.0, (p - he) / maxf(1.0 - he, 0.01)))
