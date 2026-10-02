shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

// The wisp's light (core:enemy/wisp, CreatureModel): the core itself, and a halo round it on a
// quad turned to the eye (`billboard`). Amber, flickering as a candle in a lantern does, so it reads
// as a lantern across water before it reads as anything else. Added on; no screen or depth reads.

uniform vec4 glow : source_color = vec4(1.0, 0.68, 0.26, 1.0);
uniform float energy = 1.0;
uniform float fade = 1.0;
uniform bool billboard = false;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	float flicker = 0.88 + 0.08 * sin(TIME * 13.0) + 0.06 * sin(TIME * 7.3 + 1.3) + 0.04 * sin(TIME * 23.0);
	float e = energy * flicker * fade;
	if (billboard) {
		float d = length(UV - vec2(0.5)) * 2.0;
		float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
		ALBEDO = glow.rgb * halo * 0.9 * e;
	} else {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		ALBEDO = mix(glow.rgb, vec3(1.0, 0.94, 0.8), facing * facing) * (1.1 + 0.4 * facing) * e;
	}
}
