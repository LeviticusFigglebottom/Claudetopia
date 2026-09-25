shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// The ash of the burned heath round the Stair Head, drawn on one sheet laid over the camp's
// ground (PoiBuilders._ash_cover): the burn's mosaic from noise in the sheet's own metres (UV) --
// pale ash in patches of every size, their edges ragged, thick in places and thin where the char
// shows through, a dark rim of char just outside them, and the small ghosts of burned shrubs
// between. The vertex colour's red is where ash may lie at all, its green how much (more near
// the camp). Separate drift patches, however they were placed, read from above as confetti and
// close to as pale sheets laid on the ground; a mosaic reads as ground that burned.

uniform vec4 ash : source_color = vec4(0.40, 0.385, 0.37, 1.0);
// the wind the drifts lie across (the sheet's metres, x east z south) and how long a drift is for
// its width
uniform vec2 wind = vec2(1.0, 0.25);
uniform float drift_stretch = 2.6;
uniform vec4 char_rim : source_color = vec4(0.11, 0.10, 0.095, 1.0);
// the fbm level above which the ground is ash, far from the camp and near it
uniform float threshold_far = 0.6;
uniform float threshold_near = 0.555;
// the mosaic's grain and the shrub ghosts' spacing, metres
uniform float patch_m = 9.0;
uniform float ghost_m = 2.4;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// four octaves, normalised to 0-1
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

void fragment() {
	vec2 w = UV;
	// drift shapes: the mosaic stretched along the wind, so a patch is a tongue of ash lying
	// down the wind rather than a blot (round, hard-edged, pale, they read as mould or snow)
	vec2 wd = normalize(wind);
	vec2 wr = vec2(dot(w, wd) / drift_stretch, dot(w, vec2(-wd.y, wd.x)));
	vec2 p = wr / patch_m;
	vec2 warp = vec2(fbm(p * 0.7 + 3.1), fbm(p * 0.7 + 7.7)) - 0.5;
	float big = fbm(p + warp * 1.2);
	float t = mix(threshold_far, threshold_near, COLOR.g);
	float edge = (fbm(w * 1.3) - 0.5) * 0.08;
	// soft-edged: ash thins out over half a metre or so rather than stopping at a line, and a
	// dusting runs on past the patch (hard edges at eye level read as melting snow)
	float mosaic = smoothstep(t - 0.06 + edge, t + 0.16 + edge, big);
	float dust = smoothstep(t - 0.18 + edge, t + edge, big) * 0.25;
	float ghosts = smoothstep(0.72, 0.84, fbm(w / ghost_m + 11.0));
	float rim = smoothstep(t - 0.06 + edge, t + edge, big) * (1.0 - mosaic);
	// thick and thin within a patch: the char shows through where the ash is thin
	float thick = 0.3 + 0.45 * smoothstep(0.25, 0.75, fbm(wr * 0.9 + 5.0));
	float lying = clamp(max(max(mosaic * thick, dust), ghosts * 0.45), 0.0, 0.8);
	vec3 col = ash.rgb * (0.72 + 0.5 * fbm(w * 2.7 + 1.0));
	ALBEDO = mix(char_rim.rgb, col, step(0.001, lying));
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
	ALPHA = clamp(max(lying, rim * 0.35), 0.0, 1.0) * COLOR.r;
}
