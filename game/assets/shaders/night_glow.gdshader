shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Every lamp, lantern, brazier, fire and lit window in the country as a soft point of light, all
// of them in one MultiMesh (world/night_lights.gd). Each instance is a quad turned to face the
// camera, never smaller than a few pixels, so a village on the next hill is a scatter of warm
// points and not nothing. Instance custom data is the colour and the strength.
//
// Additive, so it can only add light; drawn only at night (wm_night), and dimmed by distance by
// hand rather than by the fog, because fog on an additive surface adds the fog's colour instead
// of taking the lamp's away.

global uniform float wm_night;
uniform float min_angle = 0.0028;     // radians: the smallest a glow is drawn, however far off
uniform float haze_per_m = 0.00075;   // how quickly the air eats a distant lamp

varying vec4 v_custom;
varying float v_dist;

void vertex() {
	vec4 origin_view = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float size = length(MODEL_MATRIX[0].xyz);
	float dist = max(-origin_view.z, 0.05);
	float s = max(size, dist * min_angle * 2.0);
	vec3 corner = origin_view.xyz + vec3(VERTEX.xy * s, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(corner, 1.0);
	v_custom = INSTANCE_CUSTOM;
	v_dist = dist;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float core = clamp(1.0 - r, 0.0, 1.0);
	float glow = core * core * 0.55 + pow(core, 7.0) * 1.6;
	float atten = exp(-v_dist * haze_per_m);
	// near a lamp the glow is a halo round a real light; far off it is the whole of the lamp
	float far = smoothstep(25.0, 140.0, v_dist);
	ALBEDO = v_custom.rgb * v_custom.a * glow * atten * mix(0.45, 1.4, far) * wm_night;
	ALPHA = 1.0;
}
