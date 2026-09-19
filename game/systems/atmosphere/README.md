# systems/atmosphere

Purpose: the look of the sky and light. One `Atmosphere` node (scene `atmosphere.tscn`)
owns the sun, the moon, the WorldEnvironment (painted sky shader, fog, tonemap, glow,
adjustments), region look recipes and weather.

Reads: region defs (`identity.light`: sun_color, sun_elevation_bias, sun_elevation_scale,
fog_color, fog_density, ambient_tint, saturation, contrast, bloom, grain, god_rays;
`identity.weather` weights), weather defs (`core:weather/*`), WorldClock time.
Emits: `EventBus.weather_changed(region_id, weather_id)`.
Consumes: `EventBus.region_entered`, `EventBus.hour_changed`.
Global shader parameters set every frame: `wm_wind_strength`, `wm_wind_dir`, `wm_wetness`,
`wm_time_of_day`, `wm_region_tint` (declared in project.godot `[shader_globals]`).
Save section: `world` → `{"weather": {region_id: weather_id}, "weather_timer": seconds}`.

Public API (Atmosphere):
* `set_region(region_id: String, instant := false)`
* `force_weather(weather_id: String, instant := true)`
* `current_weather_id() -> String`, `weather_params() -> Dictionary` (blended values)
* `sun_direction() -> Vector3` (toward the sun), `light_level_at(pos) -> float` (0..1, for stealth)

Review: `game/tools_gd/atmosphere_review.tscn` renders every region at six times of day
into `captures/atmosphere/` (`./run.sh` is not needed: see the script header).
