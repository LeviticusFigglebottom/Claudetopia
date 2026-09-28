shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Stubble (triage 40): a shell a millimetre and a half over the jaw. Drawn as a flat wash of the
// hair colour it read as a painted patch with a hard edge; this draws it grain by grain -- the
// hair's flow map's fine strands, shortened to dots -- thinning out towards the shell's edges
// and where it turns from the eye, so the skin shows between and it fades into the cheek.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_flow = false;
uniform vec3 tint : source_color = vec3(1.0);
// how much of the skin the grains cover at most
uniform float alpha : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint;
	ALBEDO = c * 0.8;
	ROUGHNESS = 0.8;
	float grain = use_flow ? texture(flow_tex, UV * 6.0).b : 0.5;
	float dots = smoothstep(0.35, 0.65, grain);
	float facing = smoothstep(0.1, 0.5, abs(dot(NORMAL, VIEW)));
	ALPHA = alpha * (0.55 + 0.6 * dots) * facing;
}
