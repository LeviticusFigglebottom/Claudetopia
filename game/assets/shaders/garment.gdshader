shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
// Both faces: a pleat, a cloak's hem and a kilt's plaid apron are single sheets, and the glTF's own
// materials were double-sided. Culled, the Cragborn's plaid apron showed only its edge and the
// cloak's inside went missing in holes.

// What the people wear: cloth, leather and metal.
//
// The forge bakes each garment's albedo and ORM at 384 px over the whole of it. That is enough for
// the colour and the folds, and nowhere near enough for a thread, a pore or a hammer mark. Lit as a
// StandardMaterial3D with a rim, every garment read as a smooth tinted shell: painted plastic in the
// lineups. Here each kind gets a grain that tiles many times over its UVs (weave, leather crease,
// hammered dents: game/assets/textures/characters, tools/forge/gen_character_detail.py), dye and
// wear mottled over it, its folds darkened, and dirt taken up from the ground: the hem and the
// skirts are grimed, and everything grows cleaner towards the shoulders. Cloth is rough and has
// only a soft sheen; leather takes a dull, scuffed sheen with its edges worn paler; metal is dull,
// dark in the dents and dirtied, never chrome.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = true;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mottle_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
// 0 cloth, 1 leather, 2 metal, 3 woven in its own colours (cloth, untinted)
uniform int kind = 0;
// repeats of the detail maps over the UV square, and how hard they bend the light
uniform float detail_scale = 34.0;
uniform float detail_depth = 0.8;
uniform float mottle_scale = 3.0;
uniform float mottle_amount = 0.22;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec3 grime_colour : source_color = vec3(0.30, 0.26, 0.21);
// metres above the feet under which dirt collects, and how much at the ground
uniform float grime_height = 0.55;
uniform float grime_amount = 0.45;
uniform float sheen = 0.20;

varying float height_above_feet;

void vertex() {
	// the model's own frame: the rig stands on its origin, so height is height above the feet
	height_above_feet = VERTEX.y;
}

void fragment() {
	vec3 orm = use_orm ? texture(orm_tex, UV).rgb : vec3(1.0, 0.8, 0.0);
	vec3 m = texture(mottle_tex, UV * mottle_scale).rgb;           // soft patches
	vec3 fine = texture(mottle_tex, UV * detail_scale * 0.5).rgb;  // fibres and scuffs
	vec3 base = texture(albedo_tex, UV).rgb * (kind == 3 ? vec3(1.0) : tint);
	// dye that took unevenly, and a garment faded and darkened in patches
	// (a third as much on iron: patches of dye are cloth's, and on plate they were blotches)
	float patch = (m.r - 0.5) * 2.0 * mottle_amount * (kind == 2 ? 0.35 : 1.0);
	vec3 c = base * (1.0 + patch);
	// fibres: a fine tooth in the value, stronger on cloth
	float tooth = (fine.g - 0.5) * (kind == 2 ? 0.10 : (kind == 1 ? 0.14 : 0.12));
	c *= 1.0 + tooth;
	// the folds and the undersides, deeper than the bake's occlusion alone left them
	float ao = mix(1.0, orm.r, ao_strength);
	c *= mix(0.55, 1.0, ao);
	// dirt from the ground, patchy
	float low = 1.0 - smoothstep(0.0, grime_height, height_above_feet);
	float grime = clamp(low * grime_amount * (0.6 + m.r * 0.8), 0.0, 1.0);
	c = mix(c, c * grime_colour * 2.2, grime);
	float rough = orm.g;
	float metal = 0.0;
	float scuff = clamp((fine.b - 0.5) * 2.0, 0.0, 1.0);
	if (kind == 1) {
		// leather: scuffed paler and drier where it has rubbed, and a darker, waxy body
		c = mix(c * 0.92, c * 1.35 + vec3(0.03), scuff * 0.8);
		rough = clamp(mix(0.62, 0.9, scuff) + (m.g - 0.5) * 0.2, 0.5, 0.95);
	} else if (kind == 2) {
		// metal: dull, darkened, with scratches catching the light and dirt in the dents
		// (Near-mirror iron, rougher only in patches, took the sky and the ground as black and blue
		// blotches; forged iron is a grey that holds its own light, and its sheen is broad.)
		// Wear is fine and bright: scratches and rubbed edges, not patches. The scuff mask is
		// read at four times the grain for it; at the grain's own scale it was blotches again.
		metal = mix(0.6, 0.75, orm.b);
		float scratch = smoothstep(0.58, 0.80, texture(mottle_tex, UV * detail_scale * 4.0).b);
		float worn = clamp(scratch * 0.8 + smoothstep(0.55, 1.0, scuff) * 0.5, 0.0, 1.0);
		c = mix(c * vec3(0.82, 0.81, 0.80), c * 1.50 + vec3(0.03), worn);
		rough = clamp(0.64 + (m.r - 0.5) * 0.08 - worn * 0.26 + grime * 0.2, 0.36, 0.85);
	} else {
		// cloth: rough all over, rougher where it is dirty
		rough = clamp(max(rough, 0.86) + grime * 0.1, 0.0, 1.0);
	}
	ALBEDO = clamp(c, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = kind == 2 ? 0.5 : (kind == 1 ? 0.35 : 0.18);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = texture(detail_normal, UV * detail_scale).rgb;
	NORMAL_MAP_DEPTH = detail_depth;
	// cloth: a faint, broad sheen at grazing angles (the fuzz on wool), not a rim of plastic light
	if (kind == 0 || kind == 3) {
		float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		RIM = f * sheen;
		RIM_TINT = 0.8;
	}
}
