shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// A waterfall's falling water, as RiverFalls (world/river_falls.gd) builds it: one mesh with two
// layers, the body of the fall and a looser veil of spray a little in front of it.
//
//   UV    x across the sheet, 0..1; y down it, 0 at the lip and 1 at the foot
//   UV2   x the metres fallen at this row; y the layer, 0 the body and 1 the veil
//
// Water leaving a lip accelerates, so the streaks are laid out in the time the water has been
// falling rather than in the distance: they are short and glassy at the lip, where the tongue of
// green water goes over, and stretch and break into white as they fall. The body whitens with
// the drop (a tall fall is white by half way down), its edges are ragged and see-through, and
// white water boils at the lip and where it lands. `cascade` = 1 is water down a stepped face:
// every step a short slide of dark water breaking into a band of white.

uniform vec4 water_colour : source_color = vec4(0.36, 0.50, 0.50, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.12, 0.22, 0.24, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.94, 0.96, 0.97, 1.0);
uniform float height_m = 10.0;
uniform float width_m = 5.0;
uniform float lip_speed = 1.6;        // m/s as it goes over
uniform float cascade : hint_range(0.0, 1.0) = 0.0;
uniform float steps = 4.0;            // a cascade's steps
uniform float opacity : hint_range(0.0, 1.0) = 0.92;
uniform float veil_opacity : hint_range(0.0, 1.0) = 0.32;
// the graphics setting's water quality: how many octaves of streak are drawn
uniform float detail : hint_range(0.0, 1.0) = 1.0;

global uniform vec3 wm_sun_dir;
global uniform vec3 wm_sun_color;
global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;

varying float v_fallen;
varying float v_layer;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// seconds the water has been falling after `d` metres, leaving the lip at `lip_speed`
float fall_time(float d) {
	return (sqrt(lip_speed * lip_speed + 19.6 * max(d, 0.0)) - lip_speed) / 9.8;
}

void vertex() {
	v_fallen = UV2.x;
	v_layer = UV2.y;
}

void fragment() {
	float u = UV.x;
	float v = clamp(UV.y, 0.0, 1.0);
	float veil = step(0.5, v_layer);
	float across_m = (u - 0.5) * width_m;
	// Streaks: ropes of water down the fall, fine across it and long down it, laid out in falling
	// time so they stretch as the water accelerates. Drawn near round they read as smoke.
	float tau = fall_time(v_fallen) * 2.2;
	float tt = TIME * (1.0 + veil * 0.35);
	float s1 = vnoise(vec2(across_m * 2.2 + veil * 17.0, (tau - tt) * 0.9));
	float s2 = vnoise(vec2(across_m * 5.0 + 5.3, (tau - tt * 1.2) * 1.8));
	float s3 = vnoise(vec2(across_m * 11.0 + 9.1, (tau - tt * 1.45) * 3.6));
	float streak = s1 * 0.5 + s2 * 0.32 + s3 * 0.18 * detail;
	float rope = smoothstep(0.32, 0.78, streak);
	// how broken into white the water is: a glassy tongue over the lip, white by a third of the
	// way down (sooner on a tall fall), whitest along the ropes
	float aer = clamp(v_fallen / clamp(height_m * 0.3, 1.2, 9.0), 0.0, 1.0);
	aer = clamp(0.2 + aer * 0.7 + (rope - 0.5) * 0.55, 0.0, 1.0);
	// A cascade: each step a slide of darker water, then the break. The steps are not a ladder:
	// their spacing wanders down the face, each break's line wavers across it and is broken
	// where a rope of white water runs straight over it; evenly spaced and straight across they
	// drew an 83 m cascade as a striped ribbon.
	float wander = vnoise(vec2(v * steps * 0.37, 1.7)) * 0.9 + vnoise(vec2(across_m * 0.35, v * steps * 0.5)) * 0.6;
	float step_t = fract(v * steps + wander);
	float slide = smoothstep(0.0, 0.15, step_t) * (1.0 - smoothstep(0.3, 0.55, step_t));
	slide *= smoothstep(0.25, 0.6, vnoise(vec2(across_m * 0.8 + floor(v * steps + wander) * 3.1, 0.5)));
	// A tall cascade down a steep face is white water nearly all the way: its slides are short and
	// broken. At a slide to every break, the 73 m one on the Skerrow Water read as a blue ribbon streaked
	// with white from the dale below.
	float tall = smoothstep(12.0, 45.0, height_m);
	float cascade_white = clamp(1.0 - slide * mix(0.55, 0.22, tall) + (rope - 0.5) * 0.5 + 0.12 * tall, 0.0, 1.0);
	aer = mix(aer, cascade_white, cascade);
	// white water boiling over the lip and where it lands
	float lip_foam = (1.0 - smoothstep(0.0, 0.06 + 0.5 / max(height_m, 1.0), v)) * smoothstep(0.3, 0.7, s2 + 0.25);
	float foot_foam = smoothstep(0.84, 1.0, v);
	float white = clamp(max(aer, max(lip_foam, foot_foam)), 0.0, 1.0);
	white = mix(white, 0.75 + streak * 0.25, veil);

	// the body's colour: the green tongue at the lip, then white water shaded cool in the troughs
	// between the ropes, so the fall reads as falling water even in front of pale rock
	vec3 glassy = mix(deep_colour.rgb, water_colour.rgb, rope);
	vec3 shade = mix(vec3(0.6, 0.7, 0.74), foam_colour.rgb, rope);
	vec3 col = mix(glassy, shade, white);

	// ragged, see-through edges, raggeder the further the water has fallen
	float edge_d = min(u, 1.0 - u);
	float rag = vnoise(vec2(across_m * 0.9, (tau - tt) * 2.0 + 3.0));
	float edge = smoothstep(0.0, 0.16 + 0.1 * v, edge_d + (rag - 0.5) * (0.08 + 0.18 * v));
	float body_a = mix(0.7 + 0.3 * rope, 1.0, white) * opacity;
	// the veil is spray: patchy, thin, thickest low down
	float veil_a = veil_opacity * rope * (0.4 + 0.6 * v);
	float a = mix(body_a, veil_a, veil) * edge;
	// the very top edge of the tongue is soft, not a cut line, and the foot thins into the white
	// water it lands in rather than ending on the pool in a straight line
	a *= smoothstep(0.0, 0.015, v) * (1.0 - 0.75 * smoothstep(0.9, 1.0, v));

	// lit by the sky as well as the sun, so the side away from the light is not black; the sky's
	// colour is taken at a third, or a clear sky turns the white water blue
	vec3 sky = mix(vec3(dot(wm_sky_horizon, vec3(0.333))), mix(wm_sky_horizon, wm_sky_zenith, 0.35), 0.35);
	ALBEDO = col;
	EMISSION = col * sky * (0.25 + 0.3 * white);
	ROUGHNESS = mix(0.18, 0.75, white);
	SPECULAR = mix(0.5, 0.15, white);
	METALLIC = 0.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
