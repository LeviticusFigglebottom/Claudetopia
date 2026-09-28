shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Hair and beards (triage 40). A shell of hair is a solid, and lit as one it read as a lumpy
// helmet: a round highlight where the sun was, chunky clumps, a hard outline. Real hair is a
// mass of fine cylinders, and three things make a shell read as that:
//
//   * The highlight runs across the strands, not round the head: Kajiya-Kay's model lights a
//     strand by the angle between the half vector and the strand, so the shine is a band. Two
//     bands, as in hair: a white one off the surface, shifted towards the tips, and a second,
//     broader and in the hair's own colour, shifted towards the roots (the light that went
//     through a strand and back). The strand direction is the flow map (face_textures.py
//     `hair_flow`, RG), in the normal map's tangent frame.
//   * Fine strands over the painted clumps: the flow map's B is noise drawn out along the
//     strands, and the painted grain is taken towards its own blur, so the clumps soften into
//     a mass of hair with a grain.
//   * A broken edge: where the shell turns away from the eye, the gaps between the fine strands
//     are cut out (alpha scissor), so the outline is strands and not a clean shell.
//
// Root to tip (flow A): the ends a little lighter and drier, as hair is.
// `tint` is the person's hair colour as a ratio against the bake's brown (hair_tint()).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flow_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = true;
uniform bool use_normal = true;
uniform bool use_flow = false;
uniform vec3 tint : source_color = vec3(1.0);
// how far the painted clumps are taken towards their blur, and how strong the fine strands are
uniform float soften_clumps : hint_range(0.0, 1.0) = 0.40;
uniform float fine_strands : hint_range(0.0, 1.0) = 0.30;
uniform float tip_lift : hint_range(0.0, 0.5) = 0.14;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.55;
// the two bands of shine
uniform float spec_primary : hint_range(0.0, 2.0) = 0.11;
uniform float spec_secondary : hint_range(0.0, 2.0) = 0.09;
uniform float exp_primary = 60.0;
uniform float exp_secondary = 18.0;
uniform float shift_primary = 0.10;
uniform float shift_secondary = -0.12;
// how far past the terminator the light wraps: hair lets light through
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
// the ragged outline: how grazing the view must be before the strand gaps open, and how much
uniform float edge_cut : hint_range(0.0, 1.0) = 0.40;
uniform float diffuse_gain = 0.31831;

varying vec3 strand_view;
varying float strand_fine;
varying float spec_mask;

void fragment() {
	vec4 fl = use_flow ? texture(flow_tex, UV) : vec4(0.5, 0.5, 0.5, 0.0);
	vec3 raw = texture(albedo_tex, UV).rgb;
	// the painted clumps softened towards their blur
	// (not too far down the mips: a coarse one mixes in the gutter between the islands)
	vec3 blur = textureLod(albedo_tex, UV, 2.0).rgb;
	vec3 c = mix(raw, blur, soften_clumps);
	float fine = use_flow ? fl.b : 0.5;
	// only where the grain says which way the hair runs: a curl read as a direction is a swirl
	float sure = use_flow ? clamp(length(fl.rg * 2.0 - 1.0) * 1.5, 0.0, 1.0) : 0.0;
	c *= 1.0 + fine_strands * sure * (fine - 0.5) * 2.0;
	// the ends lighter and a little less coloured
	float tip = fl.a;
	c = mix(c, mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 0.85) * (1.0 + tip_lift * 2.0), tip * 0.5);
	ALBEDO = clamp(c * tint, 0.0, 1.0);
	vec3 orm = use_orm ? texture(orm_tex, UV).rgb : vec3(1.0, 0.6, 0.0);
	ROUGHNESS = clamp(orm.g, 0.3, 1.0);
	METALLIC = 0.0;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	// the strand direction, from the doubled angle and its confidence
	vec2 d = fl.rg * 2.0 - 1.0;
	float conf = use_flow ? clamp(length(d) * 1.5, 0.0, 1.0) : 0.0;
	float th = 0.5 * atan(d.y, d.x);
	vec3 t = normalize(TANGENT * cos(th) + BINORMAL * sin(th));
	// with no grain to go by, the hair is taken to fall down the head
	vec3 down = normalize((VIEW_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
	vec3 fallback = normalize(down - NORMAL * dot(down, NORMAL) + NORMAL * 1e-4);
	// root to tip, as far as can be told: hair falls, so the strand is turned to point down
	// (the grain has no direction of its own, and the two bands shift towards root and tip)
	t *= dot(t, down) < 0.0 ? -1.0 : 1.0;
	strand_view = normalize(mix(fallback, t, conf));
	strand_fine = fine;
	spec_mask = orm.r;
	// the edge: the fine strands' gaps cut out where the shell turns away from the eye
	float facing = abs(dot(NORMAL, VIEW));
	float edge = (1.0 - smoothstep(0.04, 0.32, facing)) * edge_cut;
	float a = 1.0 - edge * (1.0 - smoothstep(0.22, 0.46, fine)) * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

float strand_spec(vec3 t, vec3 n, vec3 h, float shift, float e) {
	vec3 ts = normalize(t + n * shift);
	float th = dot(ts, h);
	float s = sqrt(max(1.0 - th * th, 0.0));
	return pow(s, e);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += wrapped * ATTENUATION * LIGHT_COLOR * diffuse_gain;
	vec3 h = normalize(LIGHT + VIEW);
	// a strand is lit from the side the light is on, softly round the terminator
	float lit = smoothstep(-0.1, 0.4, ndl) * ATTENUATION;
	float s1 = strand_spec(strand_view, NORMAL, h, shift_primary, exp_primary);
	float s2 = strand_spec(strand_view, NORMAL, h, shift_secondary, exp_secondary);
	// the second band sparkles along the fine strands; both are lost in the deep grooves
	s2 *= 0.4 + 1.2 * strand_fine;
	float occ = smoothstep(0.35, 0.9, spec_mask);
	vec3 spec = vec3(s1 * spec_primary) + ALBEDO * s2 * spec_secondary * 2.0;
	SPECULAR_LIGHT += spec * lit * occ * LIGHT_COLOR * diffuse_gain;
}
