"""Wickmere world builder library.

Pure numpy/scipy; every stage is deterministic from the world seed. Modules:

* grid     -- world/texel coordinate conventions shared by every stage
* noise    -- spectral (FFT) fractal noise bank, warping, helpers
* regions  -- weighted, domain-warped Voronoi membership and blend weights
* heights  -- per-shape height synthesis, blending, edges, the Mere
* hydro    -- rivers, water masks, flow
* roads    -- pads, roads, tracks
* surface  -- texture control maps and the colour map
* cells    -- scatter placement into 256 m cells
* output   -- binary/JSON writers that follow docs/CONTRACTS.md section 6
"""
