shader_type canvas_item;
// Under the water (world/underwater_view.gd): the frame seen through the water, drawn over the
// whole screen while the camera is below the surface. The picture wavers a little, is washed
// toward the water's own deep colour (more the deeper the eye is and the farther off a thing
// stands, which the frame's brightness stands in for here), and darkens toward the edges; a
// band of light plays across the top of the frame where the surface is near.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform vec4 water_colour : source_color = vec4(0.06, 0.20, 0.24, 1.0);
uniform float depth_m = 0.5;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	vec2 wob = vec2(sin(uv.y * 38.0 + t * 1.7), cos(uv.x * 31.0 + t * 1.3)) * 0.0025 * amount;
	vec3 seen = texture(screen_tex, uv + wob).rgb;
	float murk = clamp(0.45 + depth_m * 0.06, 0.45, 0.85);
	vec3 col = mix(seen * vec3(0.75, 0.95, 1.0), water_colour.rgb, murk);
	// light from the surface: brighter toward the top, rippling
	float top = smoothstep(0.35, 1.0, 1.0 - uv.y) * exp(-depth_m * 0.25);
	float caustic = 0.5 + 0.5 * sin(uv.x * 55.0 + sin(uv.y * 23.0 + t * 1.1) * 2.0 + t * 0.9);
	col += water_colour.rgb * (0.6 + 0.4 * caustic) * top * 0.9;
	// darker at the edges of the frame
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 0.9;
	COLOR = vec4(col, amount);
}
