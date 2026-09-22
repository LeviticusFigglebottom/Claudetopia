shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Worked timber and the openings in it, for every house in the country (world/exteriors). The
// vertex colour is the colour, so a dark door panel and a paler frame share one draw -- except on
// a window pane, which is marked by its vertex alpha. Alpha 1 is timber. Anything under it is a
// pane (FabricMesh.pane), and how far under says how brightly the room behind it is lit after
// dark: 0 is a room nobody is in. A pane's red and green are not a colour but where the fragment
// lies across it (0..1, left to right, bottom to top), and that is what the lit window is painted
// from: glazing bars in a cross, the hearth's glow warmest low down, a darker rim at the frame.
// By day a pane is the shutter-dark gap it always was.
//
// Late at night the dimmer rooms go out: a pane lit at under 0.62 is a household that has gone
// to bed by midnight and is not up again before five.
//
// The glow is kept well under white. ACES takes a bright emission to white whatever its hue, so
// a pane written at three times the lamp colour came out as a lightbox, not a window.

global uniform float wm_night;
global uniform float wm_time_of_day;
uniform vec4 pane_dark : source_color = vec4(0.085, 0.08, 0.075, 1.0);
uniform vec4 glow_low : source_color = vec4(1.0, 0.52, 0.20, 1.0);
uniform vec4 glow_high : source_color = vec4(1.0, 0.74, 0.46, 1.0);
uniform float glow_energy = 1.25;

varying float v_lit;
varying vec3 v_pos;

void vertex() {
	v_lit = COLOR.a;
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float pane = 1.0 - step(0.995, v_lit);
	ALBEDO = mix(COLOR.rgb, pane_dark.rgb, pane);
	ROUGHNESS = mix(0.86, 0.35, pane);
	if (pane > 0.5 && wm_night > 0.001) {
		vec2 uv = COLOR.rg;
		float tod = wm_time_of_day;
		float asleep = smoothstep(22.5, 23.5, tod) + (1.0 - smoothstep(4.5, 5.5, tod)) * step(tod, 12.0);
		float lit = v_lit * (1.0 - clamp(asleep, 0.0, 1.0) * step(v_lit, 0.62));
		// glazing bars in a cross, and the frame's own shadow round the edge
		float bar_x = 1.0 - smoothstep(0.025, 0.055, abs(uv.x - 0.5));
		float bar_y = 1.0 - smoothstep(0.025, 0.055, abs(uv.y - 0.56));
		float bars = max(bar_x, bar_y);
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float rim = 1.0 - smoothstep(0.0, 0.12, edge);
		// the hearth is low in the room: warmest and brightest at the bottom of the glass
		float height = clamp(uv.y, 0.0, 1.0);
		vec3 warm = mix(glow_low.rgb, glow_high.rgb, height);
		float shape = mix(1.0, 0.55, height) * (1.0 - 0.85 * bars) * (1.0 - 0.6 * rim);
		// the fire behind the glass moves, and each pane on its own
		float flick = 0.86 + 0.14 * sin(TIME * 2.7 + v_pos.x * 1.9 + v_pos.z * 1.3) * sin(TIME * 4.1 + v_pos.y * 3.0);
		EMISSION = warm * glow_energy * shape * lit * flick * wm_night;
	}
}
