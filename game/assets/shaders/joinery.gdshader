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
// Timber is painted as wood, not as a flat colour: a box of it carries UV x along its length and
// y across it, in metres (FabricMesh.box), and the grain is laid from those -- fine dark streaks
// along the board that wander a little, the odd knot, the board's own lighter and darker runs --
// and over it the weather: silvered grey in blotches, darker where the rain sits low on a post.
// A face with no UV (zero) is a plain colour, as everything was.
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

uniform float grain_strength = 0.34;
uniform vec4 weathered : source_color = vec4(0.56, 0.54, 0.5, 1.0);
uniform float weather_strength = 0.3;

varying float v_lit;
varying vec3 v_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// How dark the grain is at `uv` (metres along, metres across), 0 to 1.
float grain(vec2 uv) {
	// the rings, seen on a sawn face as streaks along the board, wandering a little along it
	float wander = vnoise(vec2(uv.x * 0.7, uv.y * 3.0)) * 1.6;
	float streak = abs(fract((uv.y + wander * 0.05) * 38.0) - 0.5) * 2.0;
	float lines = smoothstep(0.55, 1.0, streak) * (0.55 + 0.45 * vnoise(vec2(uv.x * 2.0, uv.y * 40.0)));
	// the board's own runs of lighter and darker wood
	float runs = vnoise(vec2(uv.x * 0.9, uv.y * 7.0));
	// now and then a knot
	vec2 cell = floor(vec2(uv.x * 1.6, uv.y * 5.0));
	vec2 local = fract(vec2(uv.x * 1.6, uv.y * 5.0)) - 0.5;
	float has_knot = step(0.9, hash21(cell));
	float knot = has_knot * (1.0 - smoothstep(0.05, 0.14, length(local * vec2(1.0, 1.6))));
	return clamp(lines * 0.6 + runs * 0.45 + knot * 0.9, 0.0, 1.0);
}

varying vec2 v_grain;

// A post or a hurdle standing by a pad's lip carries how far it stands up where the terrain draws its
// far rings, as painted_surface's walls do (FabricMesh.carry_ground_lift): Grandfather Hollow's
// fence posts went 0.6 m into the 4 m ring.
uniform bool ground_follow = false;
// x: the clipmap's vertices a side (0 is no Terrain3D), y: metres between its nearest vertices
global uniform vec2 wm_terrain_clipmap;

float clipmap_fold(float d, float scale) {
	float m = wm_terrain_clipmap.x;
	return smoothstep(0.55, 0.95, ((d + 2.0 * scale) / scale - m - 4.0) / (m - 2.0));
}

void vertex() {
	if (ground_follow && wm_terrain_clipmap.x > 2.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float d = length(w.xz - CAMERA_POSITION_WORLD.xz);
		float s = wm_terrain_clipmap.y;
		VERTEX.y += CUSTOM0.x * clipmap_fold(d, s) + (CUSTOM0.y - CUSTOM0.x) * clipmap_fold(d, s * 2.0)
				+ (CUSTOM0.z - CUSTOM0.y) * clipmap_fold(d, s * 4.0);
	}
	v_lit = COLOR.a;
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_grain = UV;
}

void fragment() {
	float pane = 1.0 - step(0.995, v_lit);
	vec3 wood = COLOR.rgb;
	if (pane < 0.5 && dot(v_grain, v_grain) > 1e-6) {
		float g = grain(v_grain);
		wood *= 1.0 - grain_strength * g;
		// the weather: silver-grey in blotches over the whole of it, and more of it low down
		float blotch = smoothstep(0.35, 0.8, vnoise(v_pos.xz * 0.9 + v_pos.y * 0.6) * 0.7 + vnoise(v_pos.xz * 3.1 - v_pos.y) * 0.3);
		wood = mix(wood, weathered.rgb * (0.8 + 0.2 * g), weather_strength * blotch);
	}
	ALBEDO = mix(wood, pane_dark.rgb, pane);
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
