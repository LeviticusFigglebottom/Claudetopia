shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Painterly rock for cave shells.
//
// Vertex colour carries the stone's own colour in RGB and baked cavity occlusion in
// ALPHA (see tools/interiors/cave_forge.py). This shader adds the surface itself:
// bedding planes at a large scale, broken blocky relief at a middle scale, and only a
// whisper of grain, so the rock reads as rock rather than as noise.

uniform float bed_scale = 0.11;          // bedding planes (metres between layers ~ 1/scale)
uniform float bed_strength : hint_range(0.0, 1.0) = 0.35;
uniform float block_scale = 0.42;        // broken block relief
uniform float block_strength : hint_range(0.0, 1.5) = 0.45;
uniform float grain_scale = 7.0;
uniform float grain_strength : hint_range(0.0, 1.5) = 0.20;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.9;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.86;
uniform float occlusion : hint_range(0.0, 1.0) = 0.7;
uniform float wet_level = -10000.0;
uniform float wet_fade = 2.5;
uniform vec4 damp_tint : source_color = vec4(0.42, 0.46, 0.5, 1.0);
uniform vec4 vein_color : source_color = vec4(0.72, 0.68, 0.58, 1.0);
uniform float vein_amount : hint_range(0.0, 1.0) = 0.18;
uniform float brightness : hint_range(0.2, 3.0) = 1.25;
uniform float grain_fade_start = 9.0;   // fine grain fades out beyond this, so distant rock does not fizz
uniform float grain_fade_end = 30.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 vcol;

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

float fbm3(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		total += a;
		p *= 2.07;
		a *= 0.5;
	}
	return v / total;
}

// Ridged noise: sharp crests and creases. Smooth noise gives clay; this gives rock.
float ridged(vec3 p, int octaves, float gain) {
	float v = 0.0;
	float a = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		n *= n;
		v += a * n;
		total += a;
		p = p * 2.13 + vec3(1.7, 0.3, 2.9);
		a *= gain;
	}
	return v / total;
}

// Height of the rock surface at a point: what the relief is derived from.
float rock_height(vec3 p, float grain_fade) {
	// Bedding: near-horizontal layers, warped so they are not ruled lines. Subtle.
	float warp = fbm3(p * bed_scale * 1.7, 2) - 0.5;
	float bedding = sin((p.y + warp * 7.0) * bed_scale * 6.2831);
	bedding = sign(bedding) * pow(abs(bedding), 0.75);

	// Joints and creases: the big cracks that break a rock face into faces.
	float joints = ridged(p * block_scale, 3, 0.55);
	joints = pow(joints, 1.6);

	// Grain: chipped, granular surface at the scale a hand would feel.
	float grain = ridged(p * grain_scale, 2, 0.5);

	return bedding * bed_strength
	     + (joints - 0.45) * block_strength
	     + (grain - 0.45) * grain_strength * grain_fade;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 p = world_pos;
	float view_dist = length(VERTEX);
	float grain_fade = 1.0 - smoothstep(grain_fade_start, grain_fade_end, view_dist);
	// Floors are walked on: they wear smooth, and a floor full of shader dimples reads
	// as sand. Keep the fine relief for walls and ceilings.
	grain_fade *= mix(1.0, 0.25, clamp(abs(world_normal.y), 0.0, 1.0));
	float h = rock_height(p, grain_fade);

	float e = 0.14;
	vec3 grad = vec3(
		rock_height(p + vec3(e, 0.0, 0.0), grain_fade) - h,
		rock_height(p + vec3(0.0, e, 0.0), grain_fade) - h,
		rock_height(p + vec3(0.0, 0.0, e), grain_fade) - h) / e;
	// Keep the perturbation tangential so silhouettes stay honest.
	grad -= world_normal * dot(grad, world_normal);
	vec3 nrm = normalize(world_normal - grad * bump_strength * 0.5);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	vec3 base = vcol.rgb * brightness;
	base *= 1.0 + h * 0.22;

	// Mineral veins follow the bedding, catching the light along a layer.
	float vein = smoothstep(0.55, 0.78, fbm3(p * vec3(0.7, 3.1, 0.7), 3));
	base = mix(base, vein_color.rgb, vein * vein_amount);

	float damp = clamp((wet_level + wet_fade - world_pos.y) / max(wet_fade, 0.01), 0.0, 1.0);
	base = mix(base, base * damp_tint.rgb * 1.25, damp * 0.55);

	float ao = mix(1.0, vcol.a, occlusion);
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness_base - h * 0.2 - damp * 0.5, 0.1, 1.0);
	SPECULAR = mix(0.3, 0.6, damp);
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
}
