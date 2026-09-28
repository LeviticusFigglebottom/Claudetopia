shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// A person's jewellery (triage 48): every piece they wear merged into one mesh (Adornment), so the
// lot is one draw. What each vertex is made of rides on the mesh: COLOR the stuff's colour, UV.x how
// metallic it is and UV.y how rough (iron, bronze, silver, gold, bone, glass, a leather cord).

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = UV.x;
	ROUGHNESS = UV.y;
	// glass is wet-bright and a little lit from within; metal needs a sky it has not got, so a floor
	// of lightness keeps a silver ring from going black away from the sun
	SPECULAR = mix(0.5, 0.8, step(UV.y, 0.12));
	EMISSION = COLOR.rgb * 0.06 * UV.x;
}
