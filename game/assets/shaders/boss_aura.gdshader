shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

// The light on an uncanny foe (EnemyDress `aura`): laid over every mesh it wears as a
// material_overlay, so it is the body's own silhouette that glows, not a sprite stood in front of it.
// A rim that is brightest where the surface turns away from the eye, breathing slowly, and -- when
// `bands` is set -- rings of it climbing the body, as a held note climbs a throat. Added on; no screen
// or depth reads, so it draws the same under Forward+ and Compatibility.

uniform vec4 rim : source_color = vec4(0.62, 0.86, 0.80, 1.0);
uniform float power = 2.4;
uniform float energy = 1.0;
// how much the light breathes, 0..1, and how fast (rad/s)
uniform float pulse = 0.35;
uniform float pulse_rate = 1.6;
// rings climbing the body: how many to the metre (0 is none), and how fast they climb (m/s)
uniform float bands = 0.0;
uniform float rise = 0.5;
// a share of the rim's light laid over the whole surface, facing or not
uniform float fill = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = pow(1.0 - facing, power) + fill;
	float breath = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(TIME * pulse_rate + world_pos.y * 0.9));
	float ring = 1.0;
	if (bands > 0.0) {
		float w = sin((world_pos.y - TIME * rise) * bands * 6.2831853);
		ring = 0.45 + 0.85 * smoothstep(0.55, 1.0, w);
	}
	ALBEDO = rim.rgb * edge * energy * breath * ring;
}
