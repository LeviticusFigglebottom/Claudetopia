shader_type spatial;
// Both sides: the forge wound every eyeball inside out (its quads face inward), and with the
// back faces culled the engine drew no eyeball at all -- the lids opened on the socket behind
// them. Blender renders both sides, so the forge's own renders never showed it. Godot turns a
// back face's normal round to the viewer, so an inside-out eye lights the right way too.
render_mode cull_disabled;

// The forge paints an eyeball as bands in v measured from the pupil (tools/forge/lib/paint.py
// `iris_texture`): pupil to 0.072, iris to 0.205, limbal ring to 0.224, then sclera. glTF export
// flips v, so in the engine the iris is the band where UV.y is above 1 - 0.224. Every rig and
// head is baked with brown irises; `iris_tint` is the per-channel ratio that turns that brown
// into the eye colour asked for, so the fibres and the pupil survive the recolour and the
// whites are left alone.
//
// Triage 40 ("the eyes lack depth, the faces look wide-eyed"). The eyeball is a UV sphere
// whose pole looks forward (bodylib.eye_mesh): u is the angle round the pole, 0.25 straight up,
// and v the angle from it. So without any 3D data the shader knows, for every texel, how high
// on the ball it is, and does four things with it:
//   * the lid's shadow: the top of the ball, under the upper lid and its lashes, darkened
//     softly down over the top of the iris, and a little under the lower lid and in the
//     corners. An eye with its upper iris in shadow reads as a lid resting on it, not a stare.
//   * the iris sits under the cornea: it is looked up a little way back along the view (a
//     parallax, from the screen-space derivatives of the UVs), so it shifts behind the clear
//     front as the eye turns; and the light entering the cornea falls on the far side of the
//     iris, so that side is lit and the near side shadowed.
//   * a wet highlight: a sharp specular off the cornea, and the sky's reflection off it.
//   * the white is not white (the bake's, and `sclera_tint`).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 iris_tint : source_color = vec3(1.0);
uniform float iris_edge = 0.776;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform vec3 sclera_tint : source_color = vec3(0.97, 0.95, 0.92);
// how far up the ball (as the sine of the height) the upper lid's shadow starts and is full
uniform float lid_from = 0.12;
uniform float lid_full = 0.62;
uniform float lid_shadow : hint_range(0.0, 1.0) = 0.62;
uniform float lower_shadow : hint_range(0.0, 1.0) = 0.30;
uniform float corner_shadow : hint_range(0.0, 1.0) = 0.35;
uniform float iris_depth = 0.0012;
uniform float caustic : hint_range(0.0, 1.0) = 0.45;
uniform float wet : hint_range(0.0, 4.0) = 1.2;
uniform float diffuse_gain = 0.31831;

varying float lid_occ;
varying float in_iris_v;
varying vec3 to_pupil;

void fragment() {
	float theta = PI * (1.0 - UV.y);
	float phi = TAU * UV.x;
	float up = sin(theta) * sin(phi);
	float side = abs(sin(theta) * cos(phi));
	float occ = smoothstep(lid_from, lid_full, up) * lid_shadow;
	occ = max(occ, smoothstep(-0.45, -0.80, up) * lower_shadow);
	occ = max(occ, smoothstep(0.45, 0.85, side) * corner_shadow);
	lid_occ = occ;

	// the cotangent frame: the view-space gradients of u and v (Schüler, "Normal mapping
	// without precomputed tangents"), with u's wrap at the seam taken out
	vec3 n = normalize(NORMAL);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 duv1 = dFdx(UV);
	vec2 duv2 = dFdy(UV);
	duv1.x -= round(duv1.x);
	duv2.x -= round(duv2.x);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	float det = dot(dp1, dp2perp);
	vec3 gu = (dp2perp * duv1.x + dp1perp * duv2.x) / (abs(det) > 1e-12 ? det : 1e-12);
	vec3 gv = (dp2perp * duv1.y + dp1perp * duv2.y) / (abs(det) > 1e-12 ? det : 1e-12);
	// towards the pupil along the ball (v, as UV.y, grows towards it)
	to_pupil = length(gv) > 1e-6 ? normalize(gv) : n;
	float iris_w = smoothstep(iris_edge - 0.01, iris_edge + 0.02, UV.y);
	in_iris_v = iris_w;
	vec2 uv = UV;
	// looked up back along the view: the iris lies under the cornea
	vec3 vt = VIEW - n * dot(n, VIEW);
	vec3 back = -vt / max(dot(n, VIEW), 0.3) * iris_depth;
	vec2 duv = vec2(dot(gu, back), dot(gv, back));
	duv = clamp(duv, vec2(-0.08), vec2(0.08));
	uv += duv * iris_w;
	vec4 tex = texture(albedo_tex, uv);
	float in_iris = step(iris_edge, uv.y);
	vec3 c = mix(tex.rgb * sclera_tint, tex.rgb * iris_tint, in_iris);
	c *= 1.0 - occ;
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	// the sky over the eye is the engine's own reflection, off a wet (smooth) cornea; under the
	// lid there is none
	SPECULAR = 0.5 * (1.0 - occ);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lambert = clamp(ndl, 0.0, 1.0);
	// the far side of the iris takes the light that came in through the cornea
	float c = 1.0 + caustic * in_iris_v * dot(to_pupil, LIGHT);
	DIFFUSE_LIGHT += lambert * max(c, 0.0) * ATTENUATION * LIGHT_COLOR * diffuse_gain;
	// the cornea: wet, a small sharp highlight, dimmed under the lid
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float vdh = clamp(dot(VIEW, h), 0.0, 1.0);
	float f = 0.025 + 0.975 * pow(1.0 - vdh, 5.0);
	// sharp, but not so sharp it is lost between the pixels of an eye across a room
	float e = 360.0;
	float spec = pow(ndh, e) * (e + 8.0) / 25.1327 * f;
	SPECULAR_LIGHT += spec * wet * lambert * (1.0 - lid_occ) * ATTENUATION * LIGHT_COLOR;
}
