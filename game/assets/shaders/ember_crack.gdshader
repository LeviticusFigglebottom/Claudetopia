shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// A crack in the ash with the fire still in it: a thin, ragged line whose core glows orange-red
// and breathes, dark charred lips either side, fading out at its ends. Laid on the ground as a
// patch (UV x along the crack, y across it); all the cracks of a field are one mesh, each one's
// seed and glow in its vertex colour. These are what says the ground burned and is still warm.

uniform vec4 core : source_color = vec4(1.0, 0.42, 0.10, 1.0);
uniform vec4 lip : source_color = vec4(0.05, 0.035, 0.03, 1.0);

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

float vnoise(float x, float seed) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i + seed * 17.0), hash(i + 1.0 + seed * 17.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	// each crack's own seed and glow, from its vertex colour (the cracks are one mesh)
	float seed = COLOR.r * 10.0;
	float glow = COLOR.g * 4.0;
	float x = UV.x;
	// the crack wanders across the quad and changes width along its length
	float centre = 0.5 + 0.28 * (vnoise(x * 7.0, seed) - 0.5) + 0.12 * (vnoise(x * 23.0 + 5.0, seed) - 0.5);
	float width = 0.035 + 0.06 * vnoise(x * 11.0 + 3.0, seed);
	float d = abs(UV.y - centre) / width;
	float ends = smoothstep(0.0, 0.12, x) * smoothstep(1.0, 0.88, x);
	float hot = (1.0 - smoothstep(0.15, 0.55, d)) * ends * (0.35 + 0.65 * vnoise(x * 5.0 + 9.0, seed));
	float lips = (1.0 - smoothstep(0.5, 1.6, d)) * ends;
	float breathe = 0.75 + 0.25 * sin(TIME * (0.9 + seed * 0.7) + x * 6.0) * sin(TIME * 0.37 + seed * 3.0);
	// the warmth the crack throws on the ash round it, so a crack reads from the camp and not
	// only at the player's feet
	float halo = (1.0 - smoothstep(0.8, 6.0, d)) * ends * (0.5 + 0.5 * vnoise(x * 5.0 + 9.0, seed));
	vec3 col = mix(lip.rgb, core.rgb * glow * breathe, hot);
	col = mix(core.rgb * 0.55 * breathe, col, max(hot, lips * 0.85));
	ALBEDO = col;
	ALPHA = clamp(max(max(hot, lips * 0.85), halo * 0.42), 0.0, 1.0);
}
