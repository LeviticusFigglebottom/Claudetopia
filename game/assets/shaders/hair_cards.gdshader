shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Hair and beards as strand cards (triage 47; tools/forge/lib/hair_cards.py builds them).
//
// One mesh of three kinds of geometry, told apart by their UVs:
//   u in [0, 1)  cards: strips along the comb, each mapped over one clump of the strand atlas
//                (hair_strands.png: R the strand's value, G an id per strand, B how near the front
//                of the clump, A the strands cut out), root at v 0, tip at v 1;
//   u in [1, 2)  solid tubes (plaits, a bun's coil, a tail's body): the atlas with its gaps filled;
//   u >= 2       the scalp cap, in tiles of hair_grain.png: R the grain it is thinned by where the
//                hair thins out (the hairline, a shaved side), G streaks along the comb (roots).
// UV2 x is root (0) to tip (1), y the density (1 full; the cap falls off past the hairline, and a
// shaved side keeps a stubble's). COLOR r a random per card, g how free it is to sway, b its layer
// (0 inner .. 1 outer: the inner layers are in the mass's shade).
//
// It stays in the opaque pass: the strands are alpha-tested (with alpha to coverage where the
// viewport has MSAA), so cards need no sorting and write depth, which the depth prepass (Forward+)
// and the shadow pass use. The mips average strands with their gaps, so the coverage is lifted
// with the mip level (a card far off would otherwise dissolve).
//
// Lighting: NORMAL is the hair MASS's normal (the forge writes it into the vertices), set for
// both faces of a card: a card seen from behind, edge-on or from inside the hair is lit as the
// mass there is, not black and not as a flat plane. Kajiya-Kay shine runs along TANGENT, the strand
// direction the forge wrote root to tip: a white band shifted to the tips and a coloured one to
// the roots, as hair.gdshader does with its flow maps. Light through the hair from behind comes
// through warm. The shell (hair.gdshader) is the far level of detail (HumanoidModel.CARDS_RANGE).
//
// `tint` is the person's hair colour as a ratio against the bake's brown (hair_tint()), the same
// as the shell's, so the cards are the same colour as the shell they replace.

uniform sampler2D strand_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
// the bake's brown the tint is a ratio against (CharacterAppearance.BAKED_HAIR)
uniform vec3 base_colour : source_color = vec3(0.40, 0.278, 0.188);
uniform float value_gain = 1.40;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
// how much a mip level lifts the coverage (strands and gaps averaged together)
uniform float mip_coverage : hint_range(0.0, 1.0) = 0.30;
uniform float root_dark : hint_range(0.0, 1.0) = 0.72;
uniform float tip_lift : hint_range(0.0, 0.5) = 0.12;
// the inner layers are in the shade of the hair over them
uniform float inner_shade : hint_range(0.0, 1.0) = 0.72;
uniform float cap_value : hint_range(0.0, 1.0) = 0.70;
// how far up a card its strands take to fade in from the root
uniform float root_fade : hint_range(0.0, 0.5) = 0.14;
uniform float spec_primary : hint_range(0.0, 2.0) = 0.14;
uniform float spec_secondary : hint_range(0.0, 2.0) = 0.10;
uniform float exp_primary = 70.0;
uniform float exp_secondary = 20.0;
uniform float shift_primary = 0.10;
uniform float shift_secondary = -0.10;
uniform float wrap : hint_range(0.0, 1.0) = 0.40;
uniform float backlight : hint_range(0.0, 1.0) = 0.30;
uniform float diffuse_gain = 0.31831;
// a little sway where the hair hangs free (COLOR.g), like foliage in the wind
uniform float sway_amount = 0.008;
uniform float sway_speed = 1.4;

varying vec3 v_mass_n;
varying vec3 v_tan;
varying float v_sid;
varying float v_shine;

void vertex() {
	float free_ = COLOR.g;
	if (free_ > 0.001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float ph = TIME * sway_speed + COLOR.r * 6.2831 + dot(wp.xz, vec2(1.3, 0.9));
		vec3 off = vec3(sin(ph), 0.0, 0.6 * sin(ph * 0.77 + 1.7)) * sway_amount * free_;
		vec3 sx = MODEL_MATRIX[0].xyz;
		float s2 = max(dot(sx, sx), 1e-4);
		VERTEX += (vec4(off, 0.0) * MODEL_MATRIX).xyz / s2;
	}
	v_mass_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_tan = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV;
	float tip = UV2.x;
	float density = UV2.y;
	float layer = COLOR.b;
	float value;
	float alpha;
	float sid = COLOR.r;
	float shade;
	if (uv.x >= 2.0) {
		// the cap: full inside the hairline; past it, and on a shaved side, thinned grain by grain
		vec4 g = texture(grain_tex, uv - vec2(2.0, 0.0));
		// the grain that thins it is read at full resolution: its mips average the hairs and the
		// skin between into one grey, and the fade became a hard line along the density
		float grain = textureLod(grain_tex, uv - vec2(2.0, 0.0), 0.0).r;
		alpha = density >= 0.985 ? 1.0 : clamp((grain + density - 1.0) * 8.0 + 0.5, 0.0, 1.0);
		// the roots: dark, streaked along the comb; a thinning grain is a darker stubble
		value = cap_value * (0.72 + 0.56 * g.g) * mix(0.80, 1.0, density);
		shade = 0.85;
		sid = g.b;
	} else {
		bool solid = uv.x >= 1.0;
		vec2 auv = vec2(solid ? uv.x - 1.0 : uv.x, uv.y);
		vec4 t = texture(strand_tex, auv);
		vec2 px = auv * vec2(textureSize(strand_tex, 0));
		vec2 dx = dFdx(px);
		vec2 dy = dFdy(px);
		float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
		alpha = solid ? 1.0 : clamp(t.a * (1.0 + mip * mip_coverage), 0.0, 1.0);
		// a card's root fades in strand by strand (each strand's own id staggers it), so where
		// cards start along the hairline or a parting they grow out of the scalp, not off a line
		alpha *= solid ? 1.0 : smoothstep(0.0, root_fade, tip + (t.g - 0.5) * root_fade);
		value = t.r * value_gain;
		// dark at the roots, the inner layers and the strands behind in the clump in shade
		value *= mix(root_dark, 1.0, smoothstep(0.0, 0.35, tip));
		shade = mix(inner_shade, 1.0, layer) * mix(0.82, 1.0, t.b);
		sid = fract(sid + t.g);
	}
	vec3 c = base_colour * tint * value * shade;
	// the ends a little lighter and drier
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, mix(vec3(lum), c, 0.85) * (1.0 + tip_lift * 2.0), tip * tip * 0.5);
	ALBEDO = clamp(c, 0.0, 1.0);
	// hair scatters what it reflects: little of the sky's mirror (the shine is light()'s bands)
	ROUGHNESS = 0.85;
	SPECULAR = 0.08;
	METALLIC = 0.0;
	// the mass's normal for both faces of a card (see the top)
	NORMAL = normalize(v_mass_n);
	v_sid = sid;
	v_shine = shade;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
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
	// light from behind the hair comes through it, warm
	float through = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 3.0) * backlight * (1.0 - v_shine * 0.5);
	DIFFUSE_LIGHT += (wrapped + through * vec3(1.0, 0.75, 0.55)) * ATTENUATION * LIGHT_COLOR * diffuse_gain;
	vec3 t = normalize(v_tan - NORMAL * dot(v_tan, NORMAL) + NORMAL * 1e-4);
	vec3 h = normalize(LIGHT + VIEW);
	float lit = smoothstep(-0.1, 0.4, ndl) * ATTENUATION;
	float jitter = (v_sid - 0.5) * 0.16;
	float s1 = strand_spec(t, NORMAL, h, shift_primary + jitter, exp_primary);
	float s2 = strand_spec(t, NORMAL, h, shift_secondary + jitter, exp_secondary);
	vec3 spec = vec3(s1 * spec_primary) + ALBEDO * s2 * spec_secondary * 2.0;
	SPECULAR_LIGHT += spec * lit * v_shine * LIGHT_COLOR * diffuse_gain;
}
