shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Skin for the Compatibility renderer, which has no subsurface scattering.
//
// Light reaching a real face does not stop at the terminator: it enters the skin, scatters,
// and comes back out a little way round the curve, reddened by the blood it passed through.
// That warm, soft edge between lit and unlit is most of what makes a face read as flesh
// rather than as painted plaster. Here the light is wrapped past the terminator (`wrap`) and
// what the wrap adds is tinted towards `scatter_colour`, so the shadow side of a nose or a
// jaw falls off through a warm band instead of going straight to grey.
//
// The baked textures keep their jobs: the albedo carries the painted form (occlusion, blush,
// the lit planes), the ORM its occlusion and roughness, the normal map the pores. `tint` is
// the record's skin tone as a ratio against the bake (CharacterAppearance.skin_tint()).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = true;
uniform bool use_normal = true;
uniform vec3 tint : source_color = vec3(1.0);
// Softer than it was (0.86/0.30/0.20 at 0.60): on a hand or a neck most of what is seen is the
// band past the terminator, and there the old values pushed a mid-brown skin to 68 % saturated.
// and less saturated again: in the lineups every tone read as orange plastic
uniform vec3 scatter_colour : source_color = vec3(0.76, 0.46, 0.38);
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float scatter : hint_range(0.0, 2.0) = 0.42;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.70;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.09;
// The face bakes are painted with their lit planes already lifted (paint.skin_paint), so under
// the engine's own light a fair face went to porcelain. This takes the paint back down to the
// value skin is, rather than the value it is painted in a light.
uniform float albedo_scale : hint_range(0.5, 1.2) = 0.84;
// LIGHT_COLOR arrives scaled for the engine's own BRDF; this matches a lit StandardMaterial3D
// of the same albedo at normal incidence (measured, see tools_gd/character_review.gd).
uniform float diffuse_gain = 0.31831;

void fragment() {
	vec3 orm = use_orm ? texture(orm_tex, UV).rgb : vec3(1.0, 0.6, 0.0);
	vec3 c = texture(albedo_tex, UV).rgb * tint * albedo_scale;
	// a little more colour in the mid-tones, which the scale above takes out with the value;
	// at 1.12 every tone darker than the bake went orange under the warm key
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = clamp(mix(vec3(l), c, 0.94), 0.0, 1.0);
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	AO = mix(1.0, orm.r, ao_strength);
	AO_LIGHT_AFFECT = 0.25;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float direct = clamp(ndl, 0.0, 1.0);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// what the wrap adds beyond plain Lambert is the light that went through the skin
	float band = max(wrapped - direct, 0.0);
	vec3 diffuse = vec3(direct) + scatter_colour * band * scatter;
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR * diffuse_gain;
	// a soft, broad sheen: skin is oily enough to catch the key light on the brow and the nose
	vec3 h = normalize(VIEW + LIGHT);
	float shininess = exp2(9.0 * (1.0 - ROUGHNESS) + 1.0);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), shininess) * (shininess + 8.0) / 25.1327;
	SPECULAR_LIGHT += spec * direct * specular_amount * 0.08 * ATTENUATION * LIGHT_COLOR;
}
