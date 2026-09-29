shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// The flame in a Hearthstone's bowl: one quad turned about the vertical to face the eye, with a
// tongue of fire drawn on it that licks upward and sways. Two scrolling noises give it its ragged
// edge and its flicker; a white-gold core low down, orange going to nothing at the tips. Added,
// not blended, so it glows over whatever is behind it and needs no sorting. UV y is 0 at the top
// of the quad, so `up` below is 0 at the coals and 1 at the tips.

uniform vec4 core_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.42, 0.10, 1.0);
uniform float strength = 1.5;
// a stone's own phase, so two stones in one view do not flicker together
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// a Y billboard: the quad's right is the camera's right laid flat, its up stays up
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = normalize(cross(right, vec3(0.0, 1.0, 0.0)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	float t = TIME + seed * 13.0;
	float up = 1.0 - UV.y;
	float x = UV.x - 0.5;
	float n1 = noise(vec2(x * 4.0 + seed, up * 3.0 - t * 2.6));
	float n2 = noise(vec2(x * 9.0 + 3.0 + seed, up * 6.0 - t * 4.3));
	// the tongue leans with the draught more the higher it goes
	float sway = (n1 - 0.5) * 0.22 * up + 0.04 * sin(t * 1.7) * up;
	float width = 0.34 * pow(max(1.0 - up, 0.0), 0.75) * (0.7 + 0.6 * n2);
	float d = abs(x - sway) / max(width, 0.001);
	float body = 1.0 - smoothstep(0.35, 1.0, d);
	body *= smoothstep(0.0, 0.06, up);
	body *= 1.0 - smoothstep(0.45, 0.95, up + (n2 - 0.5) * 0.35);
	float core = (1.0 - smoothstep(0.0, 0.6, d)) * (1.0 - smoothstep(0.15, 0.55, up));
	float breathe = 0.85 + 0.15 * sin(t * 7.0) * sin(t * 2.3);
	vec3 col = mix(edge_color.rgb, core_color.rgb, core) * strength * breathe;
	ALBEDO = col * body;
	ALPHA = body;
}
