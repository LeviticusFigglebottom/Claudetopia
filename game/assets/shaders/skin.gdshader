shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Skin, on both renderers.
//
// Light reaching a real face does not stop at the terminator: it enters the skin, scatters,
// and comes back out a little way round the curve, reddened by the blood it passed through.
// That warm, soft edge between lit and unlit is most of what makes a face read as flesh
// rather than as painted plaster. Here the light is wrapped past the terminator (`wrap`) and
// what the wrap adds is tinted towards `scatter_colour`, so the shadow side of a nose or a
// jaw falls off through a warm band instead of going straight to grey. Where the skin is thin
// (the ears, the wings of the nose, the lids: zones A) it wraps further, and light from behind
// comes through them red. Forward+ adds its own screen-space scattering over that (a little:
// the wrap already does most of it); Compatibility has none and the wrap carries it alone.
//
// Triage 40 ("skin reads as smooth plastic"): what the bake cannot hold at its resolution is
// laid on here, all of it cheap:
//   * a tiling detail normal of pores and fine creases (skin_detail_normal.png), deeper over
//     the nose and the T-zone, which breaks the sheen into a skin's;
//   * the face's zones (the forge's paint.face_zones, <head>_zones.png): warmer over the
//     cheeks, nose and ears, cooler and a shade olive-grey where a beard grows under the skin
//     and in the sockets of the eyes, oilier over the T-zone;
//   * a real, if faint, specular: two lobes with a Fresnel rise, the tighter one on the oily
//     zones, and a soft sheen at grazing angles (the down on a face).
//
// The baked textures keep their jobs: the albedo carries the painted form (occlusion, the
// features), the ORM its occlusion and roughness, the normal map the face's folds. `tint` is
// the record's skin tone as a ratio against the bake (CharacterAppearance.skin_tint()).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = true;
uniform bool use_normal = true;
uniform vec3 tint : source_color = vec3(1.0);
// What a life puts on a face, as four masks (the forge's paint.face_marks): R the lines of age,
// G ruddiness, B freckles, A weathering. Every head is baked young and even; the person decides
// how much of each shows (HumanoidModel.face_marks_for), so one head is many people.
uniform sampler2D marks_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float age_amount : hint_range(0.0, 1.0) = 0.0;
uniform float ruddy_amount : hint_range(0.0, 1.0) = 0.0;
uniform float freckle_amount : hint_range(0.0, 1.0) = 0.0;
uniform float weather_amount : hint_range(0.0, 1.0) = 0.0;
// Where the skin differs (paint.face_zones): R warm, G cool, B oily, A thin. Black (none) on a
// body or a head built before the zones were.
uniform sampler2D zones_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float warm_amount : hint_range(0.0, 1.0) = 0.55;
uniform float cool_amount : hint_range(0.0, 1.0) = 0.60;
// Pores and fine creases, tiled over the UVs: `detail_scale` repeats over the UV square.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_detail = false;
uniform float detail_scale = 40.0;
uniform float detail_depth : hint_range(0.0, 2.0) = 0.25;
// Softer than it was (0.86/0.30/0.20 at 0.60): on a hand or a neck most of what is seen is the
// band past the terminator, and there the old values pushed a mid-brown skin to 68 % saturated.
// and less saturated again: in the lineups every tone read as orange plastic
uniform vec3 scatter_colour : source_color = vec3(0.76, 0.46, 0.38);
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float scatter : hint_range(0.0, 2.0) = 0.50;
// light from behind through the thin parts (the ears above all)
uniform float transmission : hint_range(0.0, 2.0) = 0.45;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.70;
// Skin's reflectance at normal incidence (about 0.028) and how much of it is shown; the old
// sheen was 0.09 x 0.08 of a normalised lobe, a fifth of what skin reflects, and the face had
// no highlight to break up at all.
uniform float specular_f0 : hint_range(0.0, 0.1) = 0.028;
uniform float specular_amount : hint_range(0.0, 2.0) = 0.6;
uniform float oily : hint_range(0.0, 0.5) = 0.18;
uniform float sheen : hint_range(0.0, 0.5) = 0.10;
// Forward+ only: the screen-space subsurface scattering, over the wrap
uniform float sss_strength : hint_range(0.0, 1.0) = 0.18;
// The face bakes are painted with their lit planes already lifted (paint.skin_paint), so under
// the engine's own light a fair face went to porcelain. This takes the paint back down to the
// value skin is, rather than the value it is painted in a light.
uniform float albedo_scale : hint_range(0.5, 1.2) = 0.84;
// LIGHT_COLOR arrives scaled for the engine's own BRDF; this matches a lit StandardMaterial3D
// of the same albedo at normal incidence (measured, see tools_gd/character_review.gd).
uniform float diffuse_gain = 0.31831;

varying float thin_skin;
varying float oil;

void fragment() {
	vec3 orm = use_orm ? texture(orm_tex, UV).rgb : vec3(1.0, 0.6, 0.0);
	vec3 c = texture(albedo_tex, UV).rgb * tint * albedo_scale;
	vec4 mk = texture(marks_tex, UV);
	vec4 zn = texture(zones_tex, UV);
	c *= mix(vec3(1.0), vec3(0.74, 0.62, 0.58), mk.r * age_amount);
	// ruddiness: a flush the skin turns through, not paint (triage 40: was 1.04/0.84/0.80)
	c = mix(c, c * vec3(1.03, 0.90, 0.87), mk.g * ruddy_amount);
	c = mix(c, c * vec3(0.80, 0.66, 0.56), mk.b * freckle_amount);
	// sun and wind: a little darker and warmer, and drier
	c = mix(c, c * vec3(0.88, 0.78, 0.70), mk.a * weather_amount);
	// the zones: warmth where the blood is near, a cool olive-grey under the beard and in the
	// sockets. Ratios, so they hold for every tone.
	c *= mix(vec3(1.0), vec3(1.035, 0.955, 0.935), zn.r * warm_amount);
	c *= mix(vec3(1.0), vec3(0.935, 0.955, 0.975), zn.g * cool_amount);
	ALBEDO = clamp(c, 0.0, 1.0);
	thin_skin = zn.a;
	oil = zn.b;
	ROUGHNESS = clamp(orm.g + 0.10 * mk.a * weather_amount - oily * zn.b, 0.2, 1.0);
	METALLIC = 0.0;
	AO = mix(1.0, orm.r, ao_strength);
	AO_LIGHT_AFFECT = 0.25;
	vec3 nm = use_normal ? texture(normal_tex, UV).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
	if (use_detail) {
		// pores deeper over the nose and the T-zone, shallower on the lids and the ears
		vec3 dn = texture(detail_normal, UV * detail_scale).rgb * 2.0 - 1.0;
		float depth = detail_depth * (0.8 + 0.7 * zn.b - 0.5 * zn.a);
		nm = normalize(vec3(nm.xy + dn.xy * depth, nm.z));
	}
	if (use_normal || use_detail) {
		NORMAL_MAP = nm * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 1.0;
	}
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	SSS_STRENGTH = sss_strength;
#endif
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float direct = clamp(ndl, 0.0, 1.0);
	float w = wrap + 0.25 * thin_skin;
	float wrapped = clamp((ndl + w) / (1.0 + w), 0.0, 1.0);
	// what the wrap adds beyond plain Lambert is the light that went through the skin
	float band = max(wrapped - direct, 0.0);
	vec3 diffuse = vec3(direct) + scatter_colour * band * scatter;
	// through an ear from behind: strongest looking into the light
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * clamp(0.3 - ndl, 0.0, 1.0);
	diffuse += scatter_colour * scatter_colour * back * thin_skin * transmission;
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR * diffuse_gain;
	// two lobes, as skin has: an oily, tighter one and the skin's own broad one, each rising
	// towards the grazing angles (Schlick)
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float vdh = clamp(dot(VIEW, h), 0.0, 1.0);
	float fres = specular_f0 + (1.0 - specular_f0) * pow(1.0 - vdh, 5.0);
	float r1 = clamp(ROUGHNESS - 0.12 * oil, 0.15, 1.0);
	float n1 = exp2(10.0 * (1.0 - r1) + 1.0);
	float n2 = exp2(7.0 * (1.0 - clamp(ROUGHNESS + 0.15, 0.0, 1.0)) + 1.0);
	float d1 = pow(ndh, n1) * (n1 + 8.0) / 25.1327;
	float d2 = pow(ndh, n2) * (n2 + 8.0) / 25.1327;
	float spec = mix(d2, d1, 0.4 + 0.4 * oil) * fres;
	// a soft sheen at the rim: the down on a cheek, catching the light
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.0) * sheen;
	SPECULAR_LIGHT += (spec * specular_amount + rim * 0.1) * direct * ATTENUATION * LIGHT_COLOR;
}
