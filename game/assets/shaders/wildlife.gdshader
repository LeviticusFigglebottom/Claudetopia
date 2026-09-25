shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
// The wild birds (world/wildlife/wildlife.gd), posed here rather than by a skeleton: one mesh a
// kind (WildlifeMeshes), a flock one MultiMesh, and each bird's pose in its instance data.
//
//   INSTANCE_CUSTOM.x  where it is in its wingbeat, in beats (the flock keeps them apart)
//   INSTANCE_CUSTOM.y  how hard it beats: 0 gliding on still wings .. 1 beating
//   INSTANCE_CUSTOM.z  how open the wings are: 0 folded on the back .. 1 spread
//   INSTANCE_CUSTOM.w  the neck drawn in (a heron in flight) or the head down (a crow feeding),
//                      and, with the wings open, the legs trailed out behind
//
// The mesh marks what each vertex is part of (UV2, see WildlifeMeshes): the wings, out along
// their span; the neck and head; the legs. A wingbeat is a stroke, not a sine: the downstroke
// takes longer than the upstroke and the tip lags the arm, so a flock does not read as
// flickering hinges.

uniform vec2 wing_root = vec2(0.05, 0.1);
uniform float fold_sweep = 0.3;
uniform vec3 neck_shift = vec3(0.0, -0.1, 0.05);
uniform vec3 hip = vec3(0.0, 0.1, 0.0);
uniform float trail = 1.2;
uniform float beat_hz = 3.0;
uniform float beat_amp = 0.75;
uniform float wetness = 0.0;

global uniform vec3 wm_sky_horizon;
global uniform vec3 wm_sky_zenith;

varying float v_wing;

vec3 rot_z(vec3 v, float a) {
	return vec3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z);
}

vec3 rot_x(vec3 v, float a) {
	return vec3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a));
}

void vertex() {
	vec4 pose = INSTANCE_CUSTOM;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float w = abs(UV2.x);
	float side = sign(UV2.x);
	v_wing = w;
	if (w > 0.0) {
		float open = clamp(pose.z, 0.0, 1.0);
		// folded: the span drawn in to the root, swept back along the body and laid on the back
		float out_x = abs(v.x) - wing_root.x;
		out_x *= mix(0.18, 1.0, open);
		// the chord drawn in as well, so a folded wing lies along the back and ends at the tail, not
		// as a spike behind the bird (every swan on the Mere trailed one)
		v.z = mix(v.z * 0.35 - w * fold_sweep, v.z, open);
		v.y += (1.0 - open) * w * 0.02;
		// the stroke: a longer downstroke than upstroke (a skewed wave), the hand behind the arm
		float ph = fract(pose.x) * 6.28318;
		float stroke = sin(ph + 0.45 * sin(ph));
		float lag = sin(ph - 0.7 + 0.45 * sin(ph - 0.7));
		float beat = pose.y * beat_amp * mix(stroke, lag, w * 0.6);
		// on still wings the tips lift a little (the dihedral a soaring bird holds)
		float a = beat * (1.0 + 0.35 * w) + (1.0 - pose.y) * 0.1 * open * w;
		a *= open;
		vec3 local = vec3(out_x, v.y - wing_root.y, v.z);
		local = rot_z(local, a);
		n = rot_z(n, a);
		v = vec3(side * (wing_root.x + local.x), wing_root.y + local.y, local.z);
		n.x *= side;
	} else if (UV2.y > 0.0) {
		v += neck_shift * pose.w * UV2.y;
	} else if (UV2.y < 0.0) {
		vec3 local = v - hip;
		// swung back about the hip, straight down to trailing out behind: only on the wing (a crow
		// pecking has its head down, not its legs out behind it)
		float legs = trail * pose.w * clamp(pose.z, 0.0, 1.0);
		local = rot_x(local, legs);
		n = rot_x(n, legs);
		v = hip + local;
	}
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	vec3 nrm = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = nrm;
	// a bird is lit a little from below by the ground and the water, or the underside of a wing is
	// a black hole against the sky
	vec3 fill = mix(wm_sky_horizon, wm_sky_zenith, 0.5) * 0.12;
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * fill;
	ROUGHNESS = mix(0.8, 0.45, wetness);
	SPECULAR = 0.3;
}
