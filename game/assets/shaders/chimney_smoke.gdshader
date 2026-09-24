shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// Smoke from a settlement's chimneys (world/exteriors/chimney_smoke.gd): every puff of every
// chimney in one MultiMesh, drawn once. Each instance sits on a chimney top; the vertex shader
// turns its quad to the camera and carries it up and away on the wind over its life, growing as
// it goes, and the fragment fades it in at the pot and out as it spreads. INSTANCE_CUSTOM holds
// the puff's own numbers: x where in its life it starts, y how long it lives, z how big it gets.

global uniform vec3 wm_wind_dir;
global uniform float wm_wind_strength;
global uniform float wm_night;

uniform float rise = 7.5;
uniform float life = 10.0;
uniform vec4 smoke_color : source_color = vec4(0.74, 0.73, 0.72, 1.0);
uniform float density = 0.4;

varying float v_age;
varying float v_seed;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = INSTANCE_CUSTOM.x;
	float age = fract(TIME / (life * (0.8 + 0.4 * INSTANCE_CUSTOM.y)) + seed);
	vec3 wind = vec3(wm_wind_dir.x, 0.0, wm_wind_dir.z);
	float wl = length(wind);
	wind = wl > 0.001 ? wind / wl : vec3(0.8, 0.0, 0.6);
	float blow = 0.5 + clamp(wm_wind_strength, 0.0, 1.0) * 3.5;
	vec3 wander = vec3(sin(seed * 40.0 + TIME * 0.31), 0.0, cos(seed * 31.0 + TIME * 0.27)) * age * 0.7;
	vec3 centre = origin + vec3(0.0, age * rise, 0.0) + wind * (age * age) * blow * 3.0 + wander;
	float size = mix(0.5, 2.6, sqrt(age)) * (0.8 + 0.4 * INSTANCE_CUSTOM.z);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_age = age;
	v_seed = seed;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float lumps = sin(q.x * 5.0 + v_seed * 17.0) * sin(q.y * 4.0 + v_seed * 11.0) * 0.14;
	float disc = smoothstep(1.0, 0.3, length(q) + lumps);
	float fade = smoothstep(0.0, 0.1, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));
	// darker against the night sky, and paler low down where it is thickest
	ALBEDO = smoke_color.rgb * mix(1.0, 0.3, clamp(wm_night, 0.0, 1.0)) * mix(0.92, 1.05, v_age);
	ALPHA = disc * fade * density;
}
