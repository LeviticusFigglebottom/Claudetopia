shader_type spatial;
// shadows_disabled: the picture does not receive shadows. It casts them -- turned to face the
// sun in the shadow pass -- and that caster crosses the camera-facing picture at the trunk, so a
// picture that received shadows lay half in its own: a hard dark wedge through every far tree
// whenever the sun and the camera were not in line. The crown's shading on itself is done in
// light() instead. What is lost is a far tree darkened by some other thing's shadow, a house's
// or a hill's; at the distances pictures are drawn, that is the rarer fault by far.
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

// A tree far away: eight pictures of it (tools/forge/gen_impostors.py) on one upright quad that
// turns about the trunk to face whoever is looking. In the colour pass that is the camera; in
// the shadow pass it is the sun, so a tree's shadow is its silhouette as the sun sees it and not
// the edge of a card. The picture is the one taken from the side you are standing on, and it is
// lit through the normals baked beside it, so it has a light side and a shade side like the mesh
// it stands in for instead of shading as a flat plane.
//
// The quad is authored in the GLB as the frame the views were rendered in: upright, facing +Z,
// its x across the frame and its y up it. Only its width and height are read from the vertices;
// the direction it faces is decided here. `frame_axis` is the trunk axis the views were taken
// around (x, z in object space). MODEL_MATRIX carries the MultiMesh instance's transform.
//
// Works on both renderers: no screen textures, no derivatives beyond the texture gradients.

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec2 frame_axis = vec2(0.0);
uniform int views = 8;
uniform int grid = 3;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.45;
// Below one, the atlas is read a little finer than the picture's size on screen asks for.
uniform float mip_sharpen : hint_range(0.25, 1.0) = 0.75;
// How much of the sun a crown's surface gets, on average, once its own leaves have shadowed
// it: the mesh levels get this from the shadow map, a picture has to be told. Measured against
// LOD1 by tools_gd/lod_review.tscn (LODSTATS), not chosen by eye.
uniform float sun_share : hint_range(0.0, 1.0) = 0.75;
// light through the leaves from behind, as the foliage shader's BACKLIGHT gives the cards
uniform float translucency : hint_range(0.0, 1.0) = 0.25;
// How far the baked sky visibility also shades the sun: the middle of a crown, which sees
// little sky, is the part the mesh's own leaves shadow. Without it a picture has none of the
// dark gaps between leaf clusters that give the mesh its depth, and reads pale and flat.
uniform float sun_occlusion : hint_range(0.0, 1.0) = 0.85;
// ...and how far it shades the sky's own light. Little: the mesh's leaves take the sky's light
// on every card whatever faces them, with nothing to occlude it on Compatibility, and a picture
// that let its baked visibility darken the sky's light came out warmer and darker than the
// mesh beside it on every tree measured.
uniform float sky_occlusion : hint_range(0.0, 1.0) = 0.3;
// Low: a crown's highlights are broken up leaf by leaf, but the picture's normals are smoothed
// into an envelope, so any more than this draws one broad cream sheen over the top of the crown.
uniform float specular_value : hint_range(0.0, 1.0) = 0.1;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.72;
uniform vec4 tint : source_color = vec4(1.0);
// fading in across (start, end) metres from the main camera; (0, 0) is always whole
uniform vec2 lod_fade_in = vec2(0.0);

#include "res://assets/shaders/lod_fade.gdshaderinc"

varying flat float v_view;
varying flat vec3 v_bx;
varying flat vec3 v_bz;
varying float v_lod_dist;
varying float v_sky;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	mat3 basis = mat3(MODEL_MATRIX);
	float s2 = max(dot(basis[0], basis[0]), 1e-8);
	vec3 axis_obj = vec3(frame_axis.x, 0.0, frame_axis.y);
	vec3 axis_world = (MODEL_MATRIX * vec4(axis_obj, 1.0)).xyz;
	// who is looking: the camera, or in a shadow pass (orthographic) the sun's direction
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 to_eye_world = ortho ? INV_VIEW_MATRIX[2].xyz : INV_VIEW_MATRIX[3].xyz - axis_world;
	// into object space (basis is a rotation times a uniform scale), and level
	vec3 to_eye = (transpose(basis) * to_eye_world) / s2;
	to_eye.y = 0.0;
	if (dot(to_eye, to_eye) < 1e-10) {
		to_eye = vec3(0.0, 0.0, 1.0);
	}
	to_eye = normalize(to_eye);
	vec3 right = vec3(to_eye.z, 0.0, -to_eye.x);
	float across = VERTEX.x - frame_axis.x;
	VERTEX = axis_obj + right * across + vec3(0.0, VERTEX.y, 0.0);
	NORMAL = to_eye;
	TANGENT = right;
	BINORMAL = vec3(0.0, 1.0, 0.0);
	// the view taken from this side: view k looked from azimuth k * TAU / views about +Y
	float az = atan(to_eye.x, to_eye.z);
	v_view = mod(az / 6.28318530718 * float(views) + float(views), float(views));
	v_bx = normalize(basis[0]);
	v_bz = normalize(basis[2]);
	v_lod_dist = length(origin - MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
}

vec2 cell_uv(float index, vec2 uv) {
	float i = mod(index, float(views));
	float col = mod(i, float(grid));
	float row = floor(i / float(grid) + 0.001);
	return (vec2(col, row) + clamp(uv, vec2(0.002), vec2(0.998))) / float(grid);
}

void fragment() {
	if (!lod_keep_in(lod_fade_in, v_lod_dist, FRAGCOORD.xy)) {
		discard;
	}
	// Between two views, a dissolve rather than a blend: two silhouettes blended are a double
	// exposure of the tree; dissolved, every pixel is one tree or the other.
	float i0 = floor(v_view);
	float t = v_view - i0;
	float pick = step(lod_noise(FRAGCOORD.xy + vec2(37.0, 11.0)), smoothstep(0.3, 0.7, t));
	float index = mix(i0, mod(i0 + 1.0, float(views)), pick);
	vec2 uv = cell_uv(index, UV);
	// gradients from the quad's own UV, so the mip level does not jump where the dissolve
	// switches cells between neighbouring pixels; shortened by `mip_sharpen`, a picture read at
	// the mip its size asks for is a smudge beside the mesh, whose leaves are drawn at full
	// resolution however small they are
	vec2 gx = dFdx(UV) / float(grid) * mip_sharpen;
	vec2 gy = dFdy(UV) / float(grid) * mip_sharpen;
	vec4 c = textureGrad(albedo_atlas, uv, gx, gy);
	vec4 n = textureGrad(normal_atlas, uv, gx, gy);
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	vec3 n_obj = n.rgb * 2.0 - 1.0;
	vec3 by = vec3(0.0, 1.0, 0.0);
	vec3 n_world = normalize(v_bx * n_obj.x + by * n_obj.y + v_bz * n_obj.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// the baked sky visibility: the middle of a crown sees less of the sky than its rim
	AO = mix(1.0, n.a, sky_occlusion);
	AO_LIGHT_AFFECT = 0.0;
	v_sky = n.a;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shade = mix(1.0, v_sky, sun_occlusion);
	float diffuse = (max(ndl, 0.0) * sun_share + max(-ndl, 0.0) * translucency) * shade;
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, h), 0.0), mix(64.0, 4.0, roughness_value));
	SPECULAR_LIGHT += spec * specular_value * sun_share * ATTENUATION * LIGHT_COLOR / PI;
}
