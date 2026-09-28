shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// A person's tattoos on the body (triage 48), drawn over the skin as the body's material_overlay.
// A body's UVs are a smart projection that moves with every build, so a tattoo is placed in the rig's
// bone space instead: every body carries its bind-pose position as CUSTOM0 (tools/forge/body_coords.py),
// and each tattoo a frame on a bone (HumanoidModel/Adornment.tattoo_frame): its origin on the bone's
// axis at the design's middle, +Y along the bone, +Z out through the design. Round a limb the design
// is wrapped (the arc round the axis is across it), on the flat of the back, the chest or the hand it
// is laid straight. Only a body with a tattoo has the overlay; under a sleeve the sleeve covers it.

#include "res://assets/shaders/tattoo_designs.gdshaderinc"

// up to four; a slot with design 0 is empty
uniform int design0 = 0;
uniform int design1 = 0;
uniform int design2 = 0;
uniform int design3 = 0;
uniform mat4 frame0;
uniform mat4 frame1;
uniform mat4 frame2;
uniform mat4 frame3;
// (radius round the axis in metres, 0 for flat; half-width; half-height; stroke half-width in the box)
uniform vec4 shape0 = vec4(0.04, 0.03, 0.05, 0.07);
uniform vec4 shape1 = vec4(0.04, 0.03, 0.05, 0.07);
uniform vec4 shape2 = vec4(0.04, 0.03, 0.05, 0.07);
uniform vec4 shape3 = vec4(0.04, 0.03, 0.05, 0.07);
// ink rgb, and a = fade (0 fresh .. 1 old)
uniform vec4 ink0 : source_color = vec4(0.1, 0.11, 0.13, 0.0);
uniform vec4 ink1 : source_color = vec4(0.1, 0.11, 0.13, 0.0);
uniform vec4 ink2 : source_color = vec4(0.1, 0.11, 0.13, 0.0);
uniform vec4 ink3 : source_color = vec4(0.1, 0.11, 0.13, 0.0);

varying vec3 rest;

void vertex() {
	// a hair's breadth off the skin, so the overlay never loses the depth test to it
	VERTEX += NORMAL * 0.00015;
	rest = CUSTOM0.xyz;
}

// how much of design `id` covers this point of the body, in its frame
float placed(int id, mat4 frame, vec4 shape, float fade) {
	vec3 q = (frame * vec4(rest, 1.0)).xyz;
	vec2 p;
	if (shape.x > 0.0) {
		// round a limb or the neck: the arc round the axis, on the near side only
		float a = atan(q.x, q.z);
		float r = length(q.xz);
		if (abs(a) > 1.9 || r < shape.x * 0.35 || r > shape.x * 2.4) return 0.0;
		p = vec2(a * shape.x / shape.y, q.y / shape.z);
	} else {
		// the flat of the back, the chest or the hand: straight on, near the skin the frame sits on
		if (q.z < -0.045 || q.z > 0.03) return 0.0;
		p = vec2(q.x / shape.y, q.y / shape.z);
	}
	float soft = 0.02 + 0.08 * fade;
	float w = shape.w * (1.0 + 0.35 * fade);
	return tattoo(id, p, w, soft) * (1.0 - 0.3 * fade);
}

void fragment() {
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (design0 > 0) {
		float c = placed(design0, frame0, shape0, ink0.a);
		col = mix(col, tattoo_ink(ink0.rgb, ink0.a), c);
		a = max(a, c);
	}
	if (design1 > 0) {
		float c = placed(design1, frame1, shape1, ink1.a);
		col = mix(col, tattoo_ink(ink1.rgb, ink1.a), c);
		a = max(a, c);
	}
	if (design2 > 0) {
		float c = placed(design2, frame2, shape2, ink2.a);
		col = mix(col, tattoo_ink(ink2.rgb, ink2.a), c);
		a = max(a, c);
	}
	if (design3 > 0) {
		float c = placed(design3, frame3, shape3, ink3.a);
		col = mix(col, tattoo_ink(ink3.rgb, ink3.a), c);
		a = max(a, c);
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(a * 0.88, 0.0, 1.0);
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
}
