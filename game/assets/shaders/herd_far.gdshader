shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// A herd or a flock far off (world/exteriors/livestock.gd): the forge's bind-pose LOD2 of a beast
// on WM_Quadruped_v1, posed here rather than by its skeleton. The mesh marks its parts in vertex
// colour (CONTRACTS, the forge's `_lod2_bind.glb`):
//   R  which leg: 0.25 fore left, 0.5 fore right, 0.75 hind left, 1.0 hind right (0 off the legs)
//   G  the neck and head, 0 at the withers to 1 at the muzzle
//   B  the tail, 0 at its root to 1 at its tip
// INSTANCE_CUSTOM: x its own phase (0..1), y walking (0 stood .. 1 walking), z grazing (0 head up ..
// 1 head down). A grazing beast's head goes down and comes up to look about; a walking one swings
// its legs in a walk's diagonal pairs and nods; every one flicks its tail now and then.

uniform vec4 leg_top = vec4(0.8);          // the height each leg hinges at, by leg
uniform vec3 neck_pivot = vec3(0.0, 1.5, 0.4);
uniform vec3 tail_pivot = vec3(0.0, 1.2, -0.8);
uniform float stride_hz = 1.1;
uniform vec4 body_colour : source_color = vec4(0.45, 0.30, 0.18, 1.0);
uniform vec4 head_colour : source_color = vec4(0.40, 0.26, 0.15, 1.0);
uniform vec4 leg_colour : source_color = vec4(0.18, 0.12, 0.08, 1.0);
uniform vec4 tail_colour : source_color = vec4(0.12, 0.08, 0.06, 1.0);

varying vec3 v_tint;

vec3 rot_x(vec3 v, float a) {
	return vec3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a));
}

vec3 rot_y(vec3 v, float a) {
	return vec3(v.x * cos(a) + v.z * sin(a), v.y, -v.x * sin(a) + v.z * cos(a));
}

void vertex() {
	vec4 pose = INSTANCE_CUSTOM;
	float t = TIME * stride_hz + pose.x * 7.0;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float leg = COLOR.r;
	float neck = COLOR.g;
	float tail = COLOR.b;
	v_tint = body_colour.rgb;
	if (leg > 0.1) {
		int id = int(round(leg * 4.0)) - 1;
		float top = leg_top[clamp(id, 0, 3)];
		// a walk: the diagonal pairs a half-cycle apart, the hind a quarter behind its fore
		float ph = (id == 0 || id == 3) ? 0.0 : 0.5;
		ph += id >= 2 ? 0.25 : 0.0;
		float swing = sin((t + ph) * 6.28318) * 0.42 * pose.y;
		vec3 local = v - vec3(0.0, top, 0.0);
		local = rot_x(local, swing);
		n = rot_x(n, swing);
		v = local + vec3(0.0, top, 0.0);
		v_tint = mix(body_colour.rgb, leg_colour.rgb, smoothstep(top, top * 0.55, VERTEX.y));
	} else if (neck > 0.01) {
		// down to the grass and up to look about, now and then; a nod as it walks
		float look_up = smoothstep(0.75, 0.95, sin(t * 0.21 + pose.x * 11.0) * 0.5 + 0.5);
		float down = pose.z * (1.0 - look_up) * 1.05 + sin(t * 6.28318 * 2.0) * 0.06 * pose.y;
		float bite = pose.z * (1.0 - look_up) * sin(TIME * 5.0 + pose.x * 20.0) * 0.05;
		vec3 local = v - neck_pivot;
		float a = (down + bite) * smoothstep(0.0, 0.35, neck);
		local = rot_x(local, a);
		n = rot_x(n, a);
		v = local + neck_pivot;
		v_tint = mix(body_colour.rgb, head_colour.rgb, smoothstep(0.35, 0.75, neck));
	} else if (tail > 0.01) {
		float flick = pow(max(sin(TIME * 0.9 + pose.x * 17.0), 0.0), 12.0);
		float a = sin(TIME * 9.0 + pose.x * 5.0) * 0.5 * flick * tail;
		vec3 local = v - tail_pivot;
		local = rot_y(local, a);
		v = local + tail_pivot;
		v_tint = tail_colour.rgb;
	}
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	ALBEDO = v_tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
