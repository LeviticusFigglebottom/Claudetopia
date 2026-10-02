shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// The wisp's shroud (core:enemy/wisp, drawn by CreatureModel): mist hanging from the light, thick
// along its folds and thin at its edges, the forge's streaks drifting up through it. Added onto
// what is behind it, so it never darkens the marsh, and drawn the same under Compatibility as
// under Forward+ (no screen reads, no depth reads).

uniform sampler2D streaks : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.62, 0.84, 0.80, 1.0);
uniform float strength = 0.55;
// 1 alive; it goes to 0 as the wisp goes out (CreatureModel, on Death)
uniform float fade = 1.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
	// the mist breathes along its length
	VERTEX += NORMAL * 0.012 * sin(TIME * 3.0 + VERTEX.y * 12.0 + VERTEX.x * 7.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// thin where it faces you, thick along the edges of its folds
	float rim = 1.0 - facing;
	vec3 s = texture(streaks, UV).rgb;
	float drift = 0.5 + 0.5 * sin(obj.y * 14.0 - TIME * 2.2 + s.r * 6.0);
	float a = (0.18 + 0.82 * rim * rim) * (0.45 + 0.55 * drift) * strength * fade;
	ALBEDO = tint.rgb * s * a * 1.7;
}
