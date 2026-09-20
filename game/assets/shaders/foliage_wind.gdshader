shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_prepass_alpha;

// Wickmere foliage: alpha-scissored leaf/grass cards with wind sway.
// Sway grows with height above the mesh origin and drifts with world position so
// neighbouring plants are out of phase. Works on Compatibility (no derivatives, no
// screen textures). The import step (tools_gd/glb_post_import.gd) assigns this shader to
// every material named *_foliage and copies the baked textures into the uniforms.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.52;
// Mipmaps average a leaf-cluster card's alpha down towards its coverage, and a cluster
// covers well under half of its atlas cell. Past a few tens of metres every card in the
// canopy therefore falls below a fixed cut-off and disappears, leaving a bare trunk: four
// hundred thousand of them, in the first world capture. Relaxing the cut-off with distance
// keeps a crisp leaf edge close up and a solid canopy far away, which is the only place it
// matters. `alpha_sharpen` rescales alpha about the threshold so the edge itself stays
// hard instead of turning to fringe as the threshold drops.
uniform float alpha_scissor_far : hint_range(0.0, 1.0) = 0.08;
uniform float scissor_fade_start = 18.0;
uniform float scissor_fade_end = 90.0;
uniform float alpha_sharpen : hint_range(1.0, 16.0) = 5.0;
uniform float roughness_mult : hint_range(0.0, 2.0) = 1.0;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.8;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.10;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.1;
uniform float wind_scale : hint_range(0.0, 2.0) = 0.25;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float sway_height = 2.0;
uniform float flutter : hint_range(0.0, 1.0) = 0.35;
uniform float backlight : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	float h = clamp((world_pos.y - root.y) / max(sway_height, 0.05), 0.0, 1.6);
	vec2 dir = normalize(wind_dir);
	float phase = dot(root.xz, dir) * wind_scale + TIME * wind_speed;
	float gust = sin(phase) * 0.55 + sin(phase * 2.17 + 1.3) * 0.25 + sin(phase * 0.31 + 0.7) * 0.45;
	vec3 offset = vec3(dir.x, 0.0, dir.y) * gust * wind_strength * h * h;
	// leaf flutter: per-card phase from UV so cards do not move as one sheet
	float fl = sin(phase * 3.7 + UV.x * 12.566 + UV.y * 6.283 + world_pos.x * 1.7) * flutter * wind_strength * h;
	offset += vec3(fl * 0.4, fl * 0.35, fl * 0.4);
	// world-space offset back into model space (handles rotation and uniform scale)
	vec3 sx = MODEL_MATRIX[0].xyz;
	float s2 = max(dot(sx, sx), 1e-4);
	VERTEX += (vec4(offset, 0.0) * MODEL_MATRIX).xyz / s2;
}

void fragment() {
	vec4 alb = texture(albedo_texture, UV) * tint;
	ALBEDO = alb.rgb;
	float fade = clamp((length(VERTEX) - scissor_fade_start)
			/ max(scissor_fade_end - scissor_fade_start, 0.01), 0.0, 1.0);
	float cut = mix(alpha_scissor, alpha_scissor_far, fade);
	ALPHA = clamp((alb.a - cut) * alpha_sharpen + 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 orm = texture(orm_texture, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(orm.g * roughness_mult, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = alb.rgb * backlight;
}
