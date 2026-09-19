shader_type canvas_item;
// Fog over the chart: everything is unread paper until you have stood somewhere and looked.
// Each reveal is a circle in the chart's own UV space; the noise gives its edge a torn look
// so the map fills in like damp spreading through paper rather than like a torch radius.

const int MAX_REVEALS = 96;

uniform int reveal_count = 0;
uniform vec3 reveals[MAX_REVEALS];              // xy = centre in UV, z = radius in UV
uniform vec4 fog_colour : source_color = vec4(0.90, 0.85, 0.74, 0.97);
uniform float edge_softness : hint_range(0.05, 0.9) = 0.34;
uniform float ragged : hint_range(0.0, 1.0) = 0.38;
uniform sampler2D noise_tex : repeat_enable, filter_linear;

void fragment() {
	float n = texture(noise_tex, UV * 7.0).r;
	float a = 1.0;
	for (int i = 0; i < reveal_count; i++) {
		vec2 d = UV - reveals[i].xy;
		float r = max(reveals[i].z, 0.0004) * (1.0 - ragged * 0.5 + ragged * n);
		float t = clamp(length(d) / r, 0.0, 1.0);
		a = min(a, smoothstep(1.0 - edge_softness, 1.0, t));
	}
	// the fog is not smoke: it is paper with nothing written on it yet
	vec3 tint = fog_colour.rgb * (0.94 + 0.10 * n);
	COLOR = vec4(tint, fog_colour.a * a);
}
