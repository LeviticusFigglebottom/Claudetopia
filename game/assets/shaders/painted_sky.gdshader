shader_type sky;

// Painted sky for Wickmere: a gradient that burns round a low sun and goes rose on the far side,
// a sun disc with a halo, two layers of cloud that are lit from the side the light is on and
// fall into flat painted steps, a bank of stratus on the horizon, and at night stars, a band of
// milk and a moon. Every colour and the light's direction are driven per frame by
// systems/atmosphere/atmosphere.gd from the region's light recipe and the sun's height; nothing
// in here knows what time it is or which region it is in.
//
// No half-resolution pass: the previous version declared one and never read HALF_RES_COLOR, so
// every pixel was drawn twice. Everything here is drawn once, at full resolution, and the
// radiance pass (AT_CUBEMAP_PASS) skips the stars, the milk and the fine octaves, which light
// nothing and cost the most.

uniform vec4 top_color : source_color = vec4(0.25, 0.45, 0.80, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.78, 0.72, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.62, 0.60, 0.55, 1.0);
uniform vec4 ground_color : source_color = vec4(0.20, 0.18, 0.16, 1.0);
uniform float horizon_sharpness : hint_range(0.5, 8.0) = 2.5;
uniform float haze : hint_range(0.0, 1.0) = 0.4;

// The sun, even when it is under the horizon: dusk is lit by a sun nobody can see.
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_disc_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float sun_energy = 1.0;
// Angular radius in degrees. The real sun is a quarter of a degree and reads as nothing on a
// screen; the old default was a 1-cos of 0.03, which is eleven degrees and read as a white
// dinner plate. A degree and a half is a disc you can see with a halo round it.
uniform float sun_disc_deg : hint_range(0.2, 6.0) = 1.5;
uniform vec4 sun_glow_color : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float sun_glow : hint_range(0.0, 3.0) = 0.6;
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dusk_color : source_color = vec4(1.0, 0.55, 0.30, 1.0);
uniform vec4 antisolar_color : source_color = vec4(0.82, 0.58, 0.64, 1.0);

// The light the clouds are lit by: the sun by day, the moon by night.
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.35;
uniform float cloud_scale = 1.0;
uniform float cloud_speed = 0.01;
uniform float cloud_height = 0.15;
uniform float cloud_band : hint_range(0.0, 1.0) = 0.25;
uniform float cirrus : hint_range(0.0, 1.0) = 0.3;
uniform vec2 wind = vec2(0.8, 0.6);
uniform vec4 cloud_lit_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform vec4 cloud_shade_color : source_color = vec4(0.55, 0.58, 0.66, 1.0);
uniform vec4 cloud_under_color : source_color = vec4(1.0, 0.55, 0.35, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float painterly : hint_range(0.0, 1.0) = 0.45;

uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.88, 0.95, 1.0);
uniform float moon_disc_deg : hint_range(0.2, 6.0) = 1.9;
uniform float moon_strength : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float total = 0.0;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		total += a;
		p = m * p;
		a *= 0.5;
	}
	return v / total;
}

// The cloud field in the wind's own frame: x runs downwind, and a banded sky stretches along it.
// The stretch is gentle: pulled harder, the masses became streaks that met at the horizon like
// the lines of a zoom, which read as speed rather than as weather.
vec2 cloud_space(vec2 p, vec2 w) {
	vec2 q = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
	return vec2(q.x * (1.0 - 0.35 * cloud_band), q.y * (1.0 + 1.1 * cloud_band));
}

void sky() {
	vec3 dir = EYEDIR;
	float t = clamp(dir.y, -1.0, 1.0);
	float up = max(t, 0.0);
	int oct = AT_CUBEMAP_PASS ? 3 : 5;

	// --- the gradient ---------------------------------------------------------------------
	float sky_mix = 1.0 - pow(1.0 - up, horizon_sharpness);
	vec3 col;
	if (t >= 0.0) {
		col = mix(horizon_color.rgb, top_color.rgb, sky_mix);
	} else {
		// Below the horizon the sky stands in for ground the view has not reached. It has to
		// leave the horizon at exactly the horizon colour, or the land's far edge reads as a
		// ruled line; the darkening is kept for steep downward views.
		float down = clamp(-t, 0.0, 1.0);
		col = mix(horizon_color.rgb, ground_horizon_color.rgb, smoothstep(0.0, 0.10, down));
		col = mix(col, ground_color.rgb, smoothstep(0.06, 0.45, down));
	}
	// Dusk: the half of the horizon under the sun burns, the far half goes rose over a band of
	// blue (the earth's own shadow), which is the whole of what makes an evening worth stopping for.
	vec2 hdir = normalize(dir.xz + vec2(1e-5, 0.0));
	vec2 sdir = normalize(sun_dir.xz + vec2(1e-5, 0.0));
	// Clamped: two unit vectors can dot to a hair over one, and pow() of the hair under zero that
	// leaves is NaN, which drew a dotted black line up the sky at the sun's own bearing.
	float toward = clamp(dot(hdir, sdir) * 0.5 + 0.5, 0.0, 1.0);
	float low_band = exp(-up * 6.0) * step(-0.02, t);
	col = mix(col, dusk_color.rgb, dusk * low_band * (0.25 + 0.75 * pow(toward, 1.8)));
	float belt = smoothstep(0.015, 0.06, up) * (1.0 - smoothstep(0.09, 0.26, up));
	col = mix(col, antisolar_color.rgb, dusk * belt * pow(1.0 - toward, 1.4) * 0.65);
	float shadow_band = (1.0 - smoothstep(0.0, 0.05, up)) * step(0.0, t);
	col = mix(col, top_color.rgb * 0.8, dusk * shadow_band * pow(1.0 - toward, 2.0) * 0.4);
	col = mix(col, horizon_color.rgb, haze * exp(-abs(t) * 6.0) * 0.6);

	// --- the sun --------------------------------------------------------------------------
	float sd = dot(dir, normalize(sun_dir));
	float sun_up = smoothstep(-0.06, 0.02, sun_dir.y);
	float disc_r = radians(sun_disc_deg);
	float disc = smoothstep(cos(disc_r), cos(disc_r * 0.82), sd) * step(-0.01, t) * sun_up;
	// three lobes: a tight halo, a softer glow, and a wide wash that a low sun spreads further
	float halo = pow(max(sd, 0.0), 260.0);
	float glow = pow(max(sd, 0.0), mix(18.0, 7.0, dusk));
	float wash = pow(max(sd, 0.0), 2.5) * (0.25 + dusk);
	col += sun_disc_color.rgb * halo * 1.4 * sun_energy * sun_up;
	col += sun_glow_color.rgb * glow * sun_glow * 0.55 * sun_energy * sun_up;
	col += dusk_color.rgb * wash * sun_glow * 0.18 * sun_up;
	// The disc adds to the sky; it does not replace it. Mixed over the sky, it came out darker
	// than the halo, glow and dusk wash round its own edge, and a low sun over Cinderlea was a
	// dark lozenge (tools_gd/sun_probe measured the centre at 0.58 against 0.83 five degrees off).
	col += sun_disc_color.rgb * max(sun_energy, 0.25) * disc * 1.5;

	// --- night: the milk, the stars and the moon -------------------------------------------
	float md = dot(dir, normalize(moon_dir));
	float night_sky = stars * smoothstep(-0.02, 0.2, t);
	if (!AT_CUBEMAP_PASS && night_sky > 0.001) {
		// the milk: a faint band along one great circle, lumpy with dust
		// squared by hand: pow() of the negative half of the sky is undefined
		float across = dot(dir, normalize(vec3(0.35, 0.28, 0.89))) * 3.2;
		float band = exp(-across * across);
		float milk = band * (0.35 + 0.65 * fbm(dir.xz / (dir.y + 1.0) * 9.0, 4));
		col += vec3(0.62, 0.66, 0.82) * milk * 0.08 * night_sky;
		// stars in two sizes, on a stereographic grid so they do not bunch at the zenith
		vec2 sp = dir.xz / (dir.y + 1.0) * 150.0;
		vec2 cell = floor(sp);
		float h = hash21(cell);
		vec2 jitter = vec2(hash21(cell + 17.0), hash21(cell + 43.0)) - 0.5;
		float dist = length(fract(sp) - 0.5 - jitter * 0.6);
		float bright = step(0.982, h) * (1.0 - smoothstep(0.0, 0.16, dist)) * 1.6;
		float faint = step(0.90, h) * (1.0 - smoothstep(0.0, 0.08, dist)) * 0.55;
		float twinkle = 0.65 + 0.35 * sin(TIME * (1.3 + h * 3.0) + h * 40.0);
		vec3 tint = mix(vec3(0.85, 0.9, 1.0), vec3(1.0, 0.9, 0.78), hash21(cell + 91.0));
		col += tint * (bright + faint) * twinkle * night_sky * (1.0 - smoothstep(0.9993, 0.9999, md));
	}
	if (moon_strength > 0.001) {
		float mr = radians(moon_disc_deg);
		float mdisc = smoothstep(cos(mr), cos(mr * 0.86), md) * step(0.0, t);
		// seas on the face: a few dark lumps, fixed to the disc
		vec3 mside = normalize(cross(normalize(moon_dir), vec3(0.0, 1.0, 0.0)) + vec3(1e-4));
		vec3 mupv = cross(mside, normalize(moon_dir));
		vec2 face = vec2(dot(dir, mside), dot(dir, mupv)) / max(sin(mr), 1e-4);
		float seas = smoothstep(0.45, 0.75, vnoise(face * 2.2 + 3.0)) * 0.28;
		col = mix(col, moon_color.rgb * 1.6 * (1.0 - seas), mdisc * moon_strength);
		col += moon_color.rgb * (pow(max(md, 0.0), 900.0) * 0.5 + pow(max(md, 0.0), 60.0) * 0.1) * moon_strength;
	}

	// --- cirrus: high, streaked out along the wind ----------------------------------------
	vec2 w = normalize(wind + vec2(1e-4, 0.0));
	float cumulus = 0.0;
	if (t > 0.0 && cloud_opacity > 0.001) {
		// Cumulus fades out in the last degree or so over the horizon, where perspective squashes a
		// lone cloud into a flat lozenge (dark, it read as a flying saucer over Cinderlea; lit
		// through, as it is now, it is a far cloud). Faded out over the lowest seventeen degrees, as
		// it first was, a level camera saw no cloud at all: that band is most of the sky in a frame.
		float fade = smoothstep(0.012, 0.14, t);
		if (!AT_CUBEMAP_PASS && cirrus > 0.001) {
			vec2 pc = dir.xz / (dir.y + 0.35) * 0.9;
			vec2 qc = vec2(dot(pc, w), dot(pc, vec2(-w.y, w.x)));
			float streak = fbm(vec2(qc.x * 0.3, qc.y * 4.5) + vec2(TIME * cloud_speed * 1.7, 0.0), 4);
			float ci = smoothstep(0.58, 0.86, streak) * cirrus * smoothstep(0.05, 0.35, t);
			vec3 cic = mix(cloud_shade_color.rgb, cloud_lit_color.rgb, 0.75);
			col = mix(col, cic, ci * 0.55);
		}

		// --- the cumulus, lit from the side the light is on --------------------------------
			// Masses first: a low-frequency field, slowly warped so the masses are lumps and not a
		// contour map of noise, with the fine octaves only on their edges. The first version took
		// its shape and its light from one five-octave field and stepped the light hard into four,
		// so every octave's wobble became a flat blotch with a dark eye in it: camouflage, not cloud.
		// The masses are sized so a frame holds several: at a third of this frequency one mass
		// filled a ninety-degree view, and a sky of one soft edge read as haze.
		vec2 p = dir.xz / (dir.y + cloud_height) * cloud_scale;
		vec2 q = cloud_space(p, w) * 0.8 + vec2(TIME * cloud_speed, 0.0);
		vec2 warp = vec2(fbm(q * 0.35 + vec2(7.1, 2.3), 3), fbm(q * 0.35 + vec2(3.7, 9.4), 3)) - 0.5;
		vec2 qw = q + warp * 0.7;
		float base = fbm(qw * 1.8, 3);
		float detail = fbm(qw * 6.0 + vec2(11.0, 5.0), oct);
		// Value-noise fbm keeps most of its values within 0.2 of the middle, so the masses are
		// spread before they are cut: at their raw spread a half-covered sky fell entirely inside
		// the soft edge and came out as one grey wash with no cloud in it.
		float dens = 0.5 + (base - 0.5) * 1.9 + (detail - 0.5) * 0.35;
		float thr = 1.0 - cloud_coverage;
		float shape = smoothstep(thr - cloud_softness * 0.18, thr + cloud_softness * 0.18, dens);
		// The light, measured on the smooth field alone, so it falls in broad strokes: the side of
		// a mass that thins toward the light is its lit side. Deep inside an overcast the modelling
		// eases off (a grey sky is not a field of dark eyes), and a thin cloud is lit through: a
		// wisp at the edge of the threshold came out as a dark lozenge on a pale sky over Skerrow.
		float thick = smoothstep(thr, thr + 0.3, dens);
		float deep = smoothstep(thr + 0.2, thr + 0.6, dens);
		// A low sun lights a mass from its side; a high one lights its top, which on the dome is the
		// side toward the zenith, so the bases seen from below go grey. The two are mixed, not
		// normalised: where they cancel (a cloud in the sun's own direction) the light is even.
		vec2 toward_light = cloud_space(normalize(light_dir.xz + vec2(1e-4, 0.0)), w);
		vec2 toward_top = -cloud_space(normalize(p + vec2(1e-4, 0.0)), w);
		float high = clamp(light_dir.y, 0.0, 1.0);
		toward_light = toward_light * (1.0 - high) + toward_top * high;
		float base_l = fbm((qw + toward_light * 0.25) * 1.8, 3);
		float light = clamp(0.6 + (base - base_l) * 3.2 * (1.0 - 0.6 * deep) + light_dir.y * 0.2, 0.0, 1.0);
		light = mix(max(light, 0.78), light, thick);
		// a mass is a little greyer at its heart than at its edge, and no more: not a doughnut
		light *= mix(1.0, 0.86, thick);
		// painted: three soft steps rather than four hard ones
		float steps = light * 3.0;
		float stepped = (floor(steps) + smoothstep(0.25, 0.75, fract(steps))) / 3.0;
		light = mix(light, stepped, painterly);
		vec3 cc = mix(cloud_shade_color.rgb, cloud_lit_color.rgb, light);
		// a low sun lights the clouds from underneath, most on the side it is on
		cc = mix(cc, cloud_under_color.rgb, dusk * (1.0 - light) * (0.3 + 0.5 * toward) * 0.85);
		// silver lining: thin edges near the light glow
		float edge = shape * (1.0 - shape) * 4.0;
		float near_light = pow(max(dot(dir, normalize(light_dir)), 0.0), 10.0);
		cc += cloud_lit_color.rgb * edge * near_light * 0.9;
		// the far ones go the colour of the air they are seen through
		cc = mix(cc, horizon_color.rgb, (1.0 - smoothstep(0.02, 0.4, t)) * 0.5);
		cumulus = shape * cloud_opacity * fade;
		col = mix(col, cc, cumulus);

		// --- a bank of stratus along the horizon --------------------------------------------
		if (cloud_band > 0.001) {
			vec2 around = hdir * 3.0;
			float bank = fbm(around * 1.7 + vec2(up * 36.0, TIME * cloud_speed * 0.5), oct);
			float bank_mask = smoothstep(0.004, 0.02, up) * (1.0 - smoothstep(0.035, 0.11, up));
			float b = smoothstep(0.48, 0.66, bank) * bank_mask * cloud_band;
			vec3 bank_col = mix(horizon_color.rgb * 0.82, cloud_lit_color.rgb, 0.3 + 0.4 * toward * dusk);
			col = mix(col, bank_col, b * 0.75);
		}
	}
	COLOR = col;
}
