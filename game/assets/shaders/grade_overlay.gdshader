shader_type canvas_item;
render_mode unshaded;

// The two parts of a region's grade that are drawn over the frame rather than into it: a
// vignette in the region's own dark (mode 0) and film grain (mode 1, Cinderlea's). Neither reads
// the screen, so each is one alpha-blended rect and works the same on every renderer.

uniform int mode = 0;
uniform float amount = 0.2;
uniform vec4 tint : source_color = vec4(0.08, 0.06, 0.05, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (mode == 0) {
		// wider than it is tall, as a frame is: the corners go, the sides barely
		vec2 c = (uv - 0.5) * vec2(1.25, 1.0);
		float v = smoothstep(0.32, 0.86, length(c) * 1.2);
		COLOR = vec4(tint.rgb, v * amount);
	} else {
		// grain: light and dark specks in equal measure, re-drawn a few times a second
		float frame = floor(TIME * 12.0);
		float n = hash(floor(FRAGCOORD.xy * 0.5) + frame * 17.0);
		float strength = abs(n - 0.5) * 2.0;
		COLOR = vec4(vec3(step(0.5, n)), strength * amount);
	}
}
