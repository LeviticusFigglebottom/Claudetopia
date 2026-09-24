// Level-of-detail dissolve, shared by every shader a scattered tree is drawn with
// (world/scatter_lod.gd). Across a band of distance two levels of the same tree are both drawn,
// and each keeps exactly the pixels the other throws away: the same noise, the same fade value,
// opposite tests. So a level change is a dissolve over the band rather than a pop at a line, and
// no pixel is ever drawn twice or not at all.
//
// The distance is the instance's from the *main* camera (MAIN_CAM_INV_VIEW_MATRIX), in the
// shadow pass as well as the colour pass: the sun's shadow camera is somewhere else entirely,
// and a fade measured from it would give the shadow of one level and the picture of another.
// A band of (0, 0) is off.

float lod_noise(vec2 p) {
	// interleaved gradient noise: cheap, and even at one sample a pixel
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// This level is fading in across `band` (start, end): whole from `end` outward.
bool lod_keep_in(vec2 band, float dist, vec2 frag) {
	if (band.y <= band.x) {
		return true;
	}
	return lod_noise(frag) < smoothstep(band.x, band.y, dist);
}

// This level is fading out across `band`: gone from `end` outward.
bool lod_keep_out(vec2 band, float dist, vec2 frag) {
	if (band.y <= band.x) {
		return true;
	}
	return lod_noise(frag) >= smoothstep(band.x, band.y, dist);
}
