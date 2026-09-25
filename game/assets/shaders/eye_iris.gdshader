shader_type spatial;
// Both sides: the forge wound every eyeball inside out (its quads face inward), and with the
// back faces culled the engine drew no eyeball at all -- the lids opened on the socket behind
// them. Blender renders both sides, so the forge's own renders never showed it. Godot turns a
// back face's normal round to the viewer, so an inside-out eye lights the right way too.
render_mode cull_disabled;

// The forge paints an eyeball as bands in v measured from the pupil (tools/forge/lib/paint.py
// `iris_texture`): pupil to 0.084, iris to 0.238, limbal ring to 0.258, then sclera. glTF export
// flips v, so in the engine the iris is the band where UV.y is above 1 - 0.258. Every rig and
// head is baked with brown irises; `iris_tint` is the per-channel ratio that turns that brown
// into the eye colour asked for, so the fibres and the pupil survive the recolour and the
// whites are left alone.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 iris_tint : source_color = vec3(1.0);
uniform float iris_edge = 0.742;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float in_iris = step(iris_edge, UV.y);
	ALBEDO = mix(tex.rgb, tex.rgb * iris_tint, in_iris);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
