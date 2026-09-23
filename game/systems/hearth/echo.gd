extends Area3D
## The Echo: a faint standing figure where you last were known, holding your marks.

var marks := 0
## An Echo is something you come back to. It appears at the spot you fell, which for the three
## seconds of the death delay is the spot your own body is lying on -- so it used to notice its
## own player and hand everything back before they had stood up, and death cost nothing. Hearth
## arms it when the player has come back (or at once, for one restored from a save).
var armed := false
## How far from the Echo's foot a body can be and still be standing in it: the capsule's radius and
## height below, and the player's own, with room to spare.
const REACH := 2.5
var _figure: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # player layer
	monitoring = true
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.6
	shape.height = 2.0
	col.shape = shape
	col.position.y = 1.0
	add_child(col)
	_figure = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.7
	_figure.mesh = cm
	_figure.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_figure.material_override = mat
	add_child(_figure)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.8, 1.0)
	_light.omni_range = 7.0
	_light.light_energy = 1.4
	_light.position.y = 1.2
	add_child(_light)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	_figure.position.y = 0.9 + 0.06 * sin(_t * 1.3)
	_light.light_energy = 1.2 + 0.3 * sin(_t * 2.1)


func _on_body_entered(body: Node) -> void:
	# The physics server says who came in as the iteration after the step that found them begins,
	# so the word can arrive after the body has gone: one that lay here while the Echo was quiet and
	# was carried to the stone within that step was answered from wherever the stone is. An Echo
	# answers a body standing in it, not the word of one that was.
	if not armed or not body.is_in_group("player") or not (body is Node3D):
		return
	if (body as Node3D).global_position.distance_to(global_position) > REACH:
		return
	Hearth.recover_echo()
