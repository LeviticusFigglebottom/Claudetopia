extends Area3D
## The Echo: a faint standing figure where you last were known, holding your marks.

const RADIUS := 0.6
const HEIGHT := 2.0
## How far from the Echo's axis a body can stand and still be touching it: its own radius and a
## humanoid's, with room to spare.
const REACH := RADIUS + 0.6

var marks := 0
## An Echo is something you come back to. It appears at the spot you fell, which for the three
## seconds of the death delay is the spot your own body is lying on -- so it used to notice its
## own player and hand everything back before they had stood up, and death cost nothing. Hearth
## arms it when the player has come back (or at once, for one restored from a save).
var armed := false
var _figure: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # player layer
	monitoring = true
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	col.shape = shape
	col.position.y = HEIGHT * 0.5
	add_child(col)
	_figure = MeshInstance3D.new()
	# it hovers every frame in _process, so it is placed exactly, not interpolated
	_figure.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	if armed and body.is_in_group("player") and _is_here(body):
		Hearth.recover_echo()


## An Area3D finds an overlap during one physics step and reports it at the start of the next, so
## a body that lay here for a single tick and was then taken away -- a death one frame long, then
## the Hearthstone -- was announced as arriving after it had gone, and after the Echo had been
## armed. Only a body standing here when the arrival is announced counts.
func _is_here(body: Node) -> bool:
	var b := body as Node3D
	if b == null:
		return false
	var d := b.global_position - global_position
	return Vector2(d.x, d.z).length() <= REACH and absf(d.y) <= HEIGHT
