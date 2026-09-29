shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The ground a lava tube breaks out of (site_exterior.gd, a `delve` whose mouth is "lava"): the
// heath's own soil where the tube's roof lies under it, going over into the tube's black crust where
// it shows, with the ropes and folds of lava that set as it flowed, glassy where it chilled fastest
// (the lip of the mouth), and warm in its cracks near the mouth where the fire still breathes.
//
// Per vertex, COLOR: r how much is rock (0 the soil, 1 the crust), g how glassy, b how warm.
// The soil is the terrain's own texture at the terrain's own scale (`soil`, `soil_scale`,
// `soil_value`, from the ground look PoiBuilders gives a bank), so the skirts meet the land
// with no seam.

uniform sampler2D soil : source_color, filter_linear_mipmap, repeat_enable;
uniform float soil_scale = 0.385;          // 1 / the texture's tile in metres
uniform float soil_value = 0.52;
uniform vec4 crust : source_color = vec4(0.085, 0.08, 0.08, 1.0);
uniform vec4 crust_high : source_color = vec4(0.22, 0.2, 0.19, 1.0);
uniform vec4 ash : source_color = vec4(0.46, 0.44, 0.42, 1.0);
uniform vec4 glass : source_color = vec4(0.03, 0.03, 0.04, 1.0);
uniform vec4 heat : source_color = vec4(1.0, 0.36, 0.08, 1.0);
uniform float heat_energy = 2.4;
// a mesh with no vertex colours of its own (the lip's lumps) says its mask here instead (a = 1)
uniform vec4 fixed_mask = vec4(0.0);

varying vec3 world_pos;
varying vec3 world_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
	               mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
	               mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	float t = 0.0;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		t += a;
		p *= 2.07;
		a *= 0.5;
	}
	return v / t;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 x = texture(soil, p.zy * soil_scale).rgb;
	vec3 y = texture(soil, p.xz * soil_scale).rgb;
	vec3 z = texture(soil, p.xy * soil_scale).rgb;
	return (x * w.x + y * w.y + z * w.z) * soil_value;
}

// the lava's ropes: folds across the way it flowed, bent by the flow's own eddies. Returns the fold
// (0 in a trough, 1 on a crest) and a crack mask in y.
vec2 ropes(vec3 p) {
	float warp = fbm3(p * 0.35, 3) * 7.0;
	float f = sin(p.x * 2.2 + p.z * 1.1 + warp) * 0.5 + 0.5;
	float fine = sin(p.x * 7.0 - p.z * 3.1 + warp * 2.0) * 0.5 + 0.5;
	float fold = mix(f, fine, 0.3);
	float c = fbm3(p * vec3(2.4, 1.0, 2.4), 3);
	float crack = smoothstep(0.018, 0.0, abs(c - 0.5)) * smoothstep(0.45, 0.75, fbm3(p * 0.6 + vec3(5.0), 2));
	return vec2(fold, crack);
}

void fragment() {
	vec3 p = world_pos;
	vec3 n = world_normal;
	vec3 mask = fixed_mask.a > 0.5 ? fixed_mask.rgb : COLOR.rgb;
	vec3 soil_col = triplanar(p, n);
	vec2 r = ropes(p);
	float fold = r.x;
	vec3 rock = mix(crust.rgb, crust_high.rgb, smoothstep(0.35, 0.95, fold));
	rock *= 0.85 + fbm3(p * 3.0, 2) * 0.3;
	// ash lying in the troughs and on the flats
	float flat_up = smoothstep(0.6, 0.95, n.y);
	rock = mix(rock, ash.rgb * (0.85 + 0.3 * fbm3(p * 1.7, 2)), (1.0 - fold) * flat_up * 0.45);
	// glassy where it chilled fast
	float g = mask.g;
	rock = mix(rock, glass.rgb + vec3(0.02, 0.02, 0.05) * fold, g * 0.85);
	// the soil gives way to the crust raggedly
	float edge = mask.r + (fbm3(p * 0.9, 3) - 0.5) * 0.55;
	float m = smoothstep(0.35, 0.6, edge);
	vec3 col = mix(soil_col, rock, m);
	// the crack network and its heat
	float warm = mask.b * m;
	float hot = r.y * warm;
	col = mix(col, col * 0.4, r.y * m * 0.8);
	ALBEDO = col;
	EMISSION = heat.rgb * heat_energy * hot * (0.7 + 0.3 * sin(TIME * 1.3 + p.x * 0.7 + p.z));
	// matte crust (a shiny one came out silver under the sky), glassy only where it chilled
	ROUGHNESS = mix(mix(0.95, 0.9, m), 0.38, g * m);
	SPECULAR = mix(0.3, 0.2, m) + 0.25 * g * m;
	// the folds' relief
	float e = 0.05;
	float fx = ropes(p + vec3(e, 0.0, 0.0)).x - fold;
	float fz = ropes(p + vec3(0.0, 0.0, e)).x - fold;
	vec3 grad = vec3(fx, 0.0, fz) / e;
	grad -= n * dot(grad, n);
	vec3 nrm = normalize(n - grad * 0.08 * m);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
