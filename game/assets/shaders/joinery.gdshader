shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Worked timber and the openings in it, for every house in the country (world/exteriors). The
// vertex colour is the colour, so a dark door panel and a paler frame share one draw; and a window
// pane is marked by its vertex alpha. 1 is timber. Anything under it is glass, and how far under
// says how brightly the room behind it is lit after dark: 0 is a room nobody is in. By day a pane
// is the dark shutter-gap it always was; after dusk it is the hearth behind it.
//
// Late at night the dimmer rooms go out: a pane lit at under 0.62 is a household that has gone
// to bed by midnight and is not up again before five.

global uniform float wm_night;
global uniform float wm_time_of_day;
uniform vec4 glow_colour : source_color = vec4(1.0, 0.62, 0.30, 1.0);
uniform float glow_energy = 3.2;

varying float v_lit;
varying vec3 v_pos;

void vertex() {
	v_lit = COLOR.a;
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.86;
	float pane = 1.0 - step(0.995, v_lit);
	float tod = wm_time_of_day;
	float asleep = smoothstep(22.5, 23.5, tod) + (1.0 - smoothstep(4.5, 5.5, tod)) * step(tod, 12.0);
	float lit = v_lit * (1.0 - clamp(asleep, 0.0, 1.0) * step(v_lit, 0.62));
	// the fire behind the shutters moves, and each pane on its own
	float flick = 0.84 + 0.16 * sin(TIME * 2.7 + v_pos.x * 1.9 + v_pos.z * 1.3) * sin(TIME * 4.1 + v_pos.y * 3.0);
	EMISSION = glow_colour.rgb * glow_energy * pane * lit * flick * wm_night;
}
