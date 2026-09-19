shader_type sky;
render_mode use_half_res_pass;

// Painted sky for Wickmere: gradient + haze band, sun disc and glow, painterly fBm clouds,
// moon and stars. Every colour is driven by systems/atmosphere/atmosphere.gd per region and time.

uniform vec4 top_color : source_color = vec4(0.25, 0.45, 0.80, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.78, 0.72, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.62, 0.60, 0.55, 1.0);
uniform vec4 ground_color : source_color = vec4(0.20, 0.18, 0.16, 1.0);
uniform float horizon_sharpness : hint_range(0.5, 8.0) = 2.5;
uniform float haze : hint_range(0.0, 1.0) = 0.4;
uniform vec4 sun_disc_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float sun_disc_size : hint_range(0.0, 0.2) = 0.03;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;
uniform vec4 sun_glow_color : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.35;
uniform float cloud_scale = 1.0;
uniform float cloud_speed = 0.01;
uniform float cloud_height = 0.15;
uniform vec4 cloud_lit_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform vec4 cloud_shade_color : source_color = vec4(0.55, 0.58, 0.66, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform float moon_size : hint_range(0.0, 0.1) = 0.02;
uniform vec4 moon_color : source_color = vec4(0.85, 0.88, 0.95, 1.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_strength : hint_range(0.0, 1.0) = 0.0;
uniform float painterly : hint_range(0.0, 1.0) = 0.5;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = m * p;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float t = clamp(dir.y, -1.0, 1.0);
	float up = clamp(t, 0.0, 1.0);
	float sky_mix = 1.0 - pow(1.0 - up, horizon_sharpness);
	vec3 col;
	if (t >= 0.0) {
		col = mix(horizon_color.rgb, top_color.rgb, sky_mix);
	} else {
		col = mix(ground_horizon_color.rgb, ground_color.rgb, clamp(-t * 4.0, 0.0, 1.0));
	}
	col = mix(col, horizon_color.rgb, haze * exp(-abs(t) * 6.0) * 0.6);

	if (LIGHT0_ENABLED) {
		float sd = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(1.0 - sun_disc_size, 1.0 - sun_disc_size * 0.6, sd);
		float glow = pow(max(sd, 0.0), 8.0 / max(sun_glow, 0.01)) * sun_glow;
		col += sun_glow_color.rgb * glow * LIGHT0_ENERGY * 0.5;
		col = mix(col, sun_disc_color.rgb * max(LIGHT0_ENERGY, 0.3), disc * step(-0.02, t));
	}

	float md = dot(dir, normalize(moon_dir));
	float mdisc = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.5, md);
	float mglow = pow(max(md, 0.0), 40.0) * 0.25;
	col += moon_color.rgb * mglow * moon_strength;
	col = mix(col, moon_color.rgb, mdisc * moon_strength * step(0.0, t));

	if (stars > 0.001 && t > 0.0) {
		vec2 sp = dir.xz / (dir.y + 0.15) * 40.0;
		float s = hash21(floor(sp));
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + s * 50.0);
		float star = smoothstep(0.985, 1.0, s) * twinkle;
		col += vec3(star) * stars * smoothstep(0.0, 0.3, t);
	}

	if (t > 0.0 && cloud_opacity > 0.001) {
		vec2 cp = dir.xz / (dir.y + cloud_height) * cloud_scale;
		cp += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);
		float n = fbm(cp * 0.8);
		float shape = smoothstep(1.0 - cloud_coverage - cloud_softness, 1.0 - cloud_coverage + cloud_softness, n);
		shape = mix(shape, floor(shape * 4.0 + 0.5) / 4.0, painterly);
		float lit = 0.5;
		if (LIGHT0_ENABLED) {
			lit = clamp(dot(normalize(vec3(dir.x, 0.3, dir.z)), LIGHT0_DIRECTION) * 0.5 + 0.5, 0.0, 1.0);
		}
		float sun_e = LIGHT0_ENABLED ? LIGHT0_ENERGY : 0.0;
		vec3 cc = mix(cloud_shade_color.rgb, cloud_lit_color.rgb, lit) * max(sun_e * 0.8 + 0.2, 0.15);
		float fade = smoothstep(0.0, 0.25, t);
		col = mix(col, cc, shape * cloud_opacity * fade);
	}
	COLOR = col;
}
