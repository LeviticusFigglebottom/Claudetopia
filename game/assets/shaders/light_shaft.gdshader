shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, shadows_disabled;

// A visible shaft of daylight falling into a dark place. Additive cone with soft edges,
// fading out toward the floor, brightest when looked at across the beam.

uniform vec4 shaft_color : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.10;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.6;
uniform float bottom_fade : hint_range(0.0, 1.0) = 0.7;
uniform float dust_speed = 0.06;

varying vec3 local_pos;
varying vec3 world_normal;
varying float height_t;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	height_t = UV.y;
}

void fragment() {
	// Soft radial edge: fade where the cone's surface turns away from the viewer.
	float facing = 1.0 - abs(dot(normalize(world_normal), normalize(VIEW)));
	float edge = pow(clamp(facing, 0.0, 1.0), mix(0.6, 2.4, edge_softness));

	// Top bright, bottom dissolved: light spreads and loses itself before the floor.
	float vertical = mix(1.0, pow(1.0 - height_t, 1.6), bottom_fade);

	// Slow drift so the beam is alive without being a moving texture.
	float drift = hash12(floor(local_pos.xz * 3.0 + vec2(TIME * dust_speed)));
	float mote = 0.9 + drift * 0.2;

	ALBEDO = shaft_color.rgb;
	ALPHA = clamp(intensity * edge * vertical * mote, 0.0, 1.0);
}
