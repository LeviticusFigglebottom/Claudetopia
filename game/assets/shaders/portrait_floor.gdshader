shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// The flagstones the Naming's figure stands on: a pool of light round the feet that falls away
// to shadow, and past it the floor becomes the dusk itself (it is emitted in the backdrop's
// horizon colour) so there is no edge where the stones stop and the painted sky starts.
// Depth fog would do the second job, and on the Compatibility renderer inside a SubViewport it
// did nothing.

uniform sampler2D stones : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_metres = 1.6;
uniform vec3 tint : source_color = vec3(0.50, 0.46, 0.42);
uniform vec3 far_colour : source_color = vec3(0.70, 0.55, 0.40);
uniform float pool = 1.8;
uniform float fade_from = 2.8;
uniform float fade_to = 8.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(world_pos.xz);
	vec3 st = texture(stones, world_pos.xz / tile_metres).rgb;
	// soften the stones' own contrast: they are a floor to stand on, not a subject
	st = mix(vec3(dot(st, vec3(0.333))), st, 0.55);
	float lit = mix(0.38, 1.0, 1.0 - smoothstep(0.35, pool, r));
	float fade = smoothstep(fade_from, fade_to, r);
	ALBEDO = st * tint * lit * (1.0 - fade);
	EMISSION = far_colour * fade;
	ROUGHNESS = 0.95;
}
