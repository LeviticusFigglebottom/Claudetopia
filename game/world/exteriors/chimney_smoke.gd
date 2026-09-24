class_name ChimneySmoke
extends RefCounted
## The smoke from a settlement's chimneys, as one MultiMesh of puffs.
##
## A village with cold chimneys at noon is a village nobody lives in, and a thread of smoke over
## the roofs is what says a place is home from the next hill. A particle system per chimney would
## be a draw each and a simulation each; this is every puff of every chimney in one MultiMesh of
## camera-facing quads, moved by `chimney_smoke.gdshader` on the GPU, so the smoke of a whole
## town is one draw and costs the CPU nothing after it is built.

const SHADER := preload("res://assets/shaders/chimney_smoke.gdshader")
## Puffs in the air above one chimney at a time.
const PUFFS := 6
## Smoke is seen from further off than a shutter: it is how a village is found.
const RANGE_M := 700.0


## The smoke over `tops` (chimney tops, in the space of the node the result is added to).
static func make(tops: Array, puff_seed: int) -> MultiMeshInstance3D:
	if tops.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = puff_seed
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = tops.size() * PUFFS
	var i := 0
	for top_v in tops:
		var top: Vector3 = top_v
		var start := rng.randf()
		for k in range(PUFFS):
			mm.set_instance_transform(i, Transform3D(Basis(), top))
			# the puffs of one chimney are spread evenly through its life, so it draws steadily
			mm.set_instance_custom_data(i, Color(fposmod(start + float(k) / float(PUFFS), 1.0),
					rng.randf(), rng.randf(), 0.0))
			i += 1
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var inst := MultiMeshInstance3D.new()
	inst.name = "ChimneySmoke"
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the puffs are moved in the shader, up to a dozen metres from where the instances stand
	inst.extra_cull_margin = 14.0
	inst.visibility_range_end = RANGE_M
	inst.visibility_range_end_margin = RANGE_M * 0.1
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return inst
