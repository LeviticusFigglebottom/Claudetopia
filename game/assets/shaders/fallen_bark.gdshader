shader_type spatial;
// A fallen oak's bark (briarwold.gd's _bark_bole and _bark_look: the Windthrow's bole, its stubs and
// its crown's limbs). The Greatwood oak's own bark pictures along the log's UVs, broken up in tone
// over the log so it does not read as one even, pale plank: darker and lighter reaches a few metres
// long, blotches over them, grey weathered patches, the wet dark underside. The moss on its top is
// the moss's own picture and colour in drifts, not the bark's darkened toward green (that went near
// black in the shade), and the snapped ends are the pale heartwood. Every face also takes a share of
// the sun's light whatever its shadow and its facing (the ground's and the sky's bounce under and
// round a lying log: the world's ambient is a small part of its sun), so a stub's shadow on the
// bole and the underside read dark brown, and the moss in the shade green, not black.
//
// The vertex colour is data, not a colour: r the bark's shade (1 dry, less where it lies wet), g the
// heartwood (0 bark, 1 a break's torn wood), b a per-vertex jitter (x 1.1), a the moss (0-1).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_orm : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 bark_tint : source_color = vec3(0.47, 0.42, 0.38);
uniform vec3 lichen_tint : source_color = vec3(0.62, 0.62, 0.56);
uniform vec3 heart_tint : source_color = vec3(0.72, 0.6, 0.44);
uniform vec3 moss_tint : source_color = vec3(0.72, 0.78, 0.55);
// the moss's picture laid from above, metres to a repeat (along the log's UVs it ran into stripes)
uniform float moss_tile_m = 1.8;
uniform float normal_depth = 1.4;
// the share of the sun every face takes whatever its shadow and facing (a lit face takes up to 1)
uniform float bounce = 0.14;

varying vec3 opos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 tex = texture(bark_albedo, UV).rgb;
	// the tone across the log: reaches a few metres long, and smaller blotches over them
	float n1 = vnoise(opos * vec3(0.18, 0.3, 0.18));
	float n2 = vnoise(opos * 0.85 + vec3(7.3, 1.1, 3.7));
	float n3 = vnoise(opos * 2.6 + vec3(3.1, 9.2, 5.5));
	float tone = mix(0.45, 1.25, smoothstep(0.15, 0.85, n1)) * mix(0.72, 1.15, n2) * mix(0.88, 1.08, n3);
	vec3 bark = tex * bark_tint * COLOR.r * (COLOR.b * 1.1) * tone;
	// weathered grey where the bark has dried out, in patches
	float lichen = smoothstep(0.6, 0.8, n2 * 0.65 + n3 * 0.35) * 0.55 * COLOR.r;
	float grey = dot(bark, vec3(0.3, 0.59, 0.11));
	bark = mix(bark, lichen_tint * grey * 1.7, lichen);
	// the heartwood of a break: the same grain, pale and warm
	vec3 heart = mix(vec3(dot(tex, vec3(0.3, 0.59, 0.11))), tex, 0.4) * heart_tint * 1.6;
	vec3 wood = mix(bark, heart, COLOR.g);
	// the moss: in drifts over the top, its edges broken by the noise rather than following the rings
	float moss = smoothstep(0.42, 0.68, COLOR.a * 0.95 + (n2 - 0.5) * 0.55 + (n1 - 0.5) * 0.35 + (n3 - 0.5) * 0.2);
	moss *= 1.0 - COLOR.g;
	vec2 muv = opos.xz / moss_tile_m;
	vec3 moss_col = texture(moss_albedo, muv).rgb * moss_tint * mix(0.7, 1.15, n3) * mix(0.85, 1.1, n1);
	ALBEDO = mix(wood, moss_col, moss);
	vec4 orm = texture(bark_orm, UV);
	AO = mix(orm.r, 1.0, moss * 0.8);
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = mix(orm.g, 1.0, moss);
	METALLIC = 0.0;
	NORMAL_MAP = mix(texture(bark_normal, UV).rgb, texture(moss_normal, muv).rgb, moss);
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.6, moss);
}

void light() {
	// Lambert, as the engine's own (the bark is too rough to shine), and the sun's bounce: a share of
	// the sun's light on every face, lit or in shadow
	float direct = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float fill = LIGHT_IS_DIRECTIONAL ? bounce : 0.0;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (direct + fill);
}
