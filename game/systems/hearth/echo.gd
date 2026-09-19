extends Area3D
## The Echo: a faint standing figure where you last were known, holding your marks.

var marks := 0
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
	if body.is_in_group("player"):
		Hearth.recover_echo()
