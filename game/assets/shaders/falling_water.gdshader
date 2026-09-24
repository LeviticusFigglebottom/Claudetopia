shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// A sheet of water falling. Streaks scroll down the sheet's own V (the mesh puts v = 0 at
// the lip and v = 1 at the foot), froth gathers where it lands and where it leaves the rock,
// and `glass` = 1 freezes the whole thing into the black glass a fall leaves behind when it
// has been sung dry: the ropes of the water that fell still in it as ridges down the face, so
// the sky runs down it in streaks of light, dark and polished, with a violet sheen in its deeps.
// (A place's own fall of water is drawn by world/river_falls.gd's waterfall shader in its place;
// this one is what the glass keeps, and the plain sheet where nothing replaces it.)
uniform vec4 water_color : source_color = vec4(0.70, 0.80, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform vec4 glass_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 glass_sheen : source_color = vec4(0.22, 0.12, 0.34, 1.0);
uniform float speed = 2.6;
uniform float streaks = 7.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float glass : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
	           mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// the glass's frozen ropes: ridges down the face, a little wavering
float ropes(vec2 uv) {
	return vnoise2(vec2(uv.x * 16.0, uv.y * 1.6)) * 0.65 + vnoise2(vec2(uv.x * 37.0 + 3.0, uv.y * 3.1)) * 0.35;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed * (1.0 - glass);
	float n1 = vnoise2(vec2(uv.x * streaks, uv.y * 3.0 - t));
	float n2 = vnoise2(vec2(uv.x * streaks * 2.3 + 7.0, uv.y * 6.0 - t * 1.4));
	float streak = smoothstep(0.35, 0.8, n1 * 0.6 + n2 * 0.4);
	float foot = smoothstep(0.72, 1.0, uv.y);
	float lip = 1.0 - smoothstep(0.0, 0.12, uv.y);
	float froth = clamp(foot * 0.9 + lip * 0.5 + streak * 0.5, 0.0, 1.0);
	vec3 water = mix(water_color.rgb, foam_color.rgb, froth);

	// the glass: its ridges bend the normal across the face, so the sky's light runs down it in
	// streaks; the derivative is taken across the sheet's own u, turned into view space by the
	// face's own up and across
	float r0 = ropes(uv);
	float r1 = ropes(uv + vec2(0.004, 0.0));
	float ridge = (r1 - r0) / 0.004;
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 across_v = normalize(cross(up_v, NORMAL) + vec3(0.0001));
	vec3 glass_n = normalize(NORMAL + across_v * ridge * 0.035);
	NORMAL = normalize(mix(NORMAL, glass_n, glass));
	vec3 obsidian = glass_color.rgb + glass_sheen.rgb * smoothstep(0.55, 0.9, r0) * 0.35;

	vec3 col = mix(water, obsidian, glass);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.15, 0.4, froth), 0.04 + 0.08 * (1.0 - r0), glass);
	SPECULAR = mix(0.7, 0.95, glass);
	METALLIC = mix(0.0, 0.35, glass);
	ALPHA = mix(clamp(opacity * (0.55 + 0.45 * streak) + foot * 0.4, 0.0, 1.0), 1.0, glass);
	EMISSION = mix(foam_color.rgb * froth * 0.08, glass_sheen.rgb * r0 * r0 * 0.06, glass);
}
