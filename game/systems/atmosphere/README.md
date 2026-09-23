# systems/atmosphere

Purpose: the look of the sky and the light. One `Atmosphere` node (scene `atmosphere.tscn`)
owns the sun, the moon, the WorldEnvironment (painted sky shader, two layers of fog, tonemap,
glow, the region colour grade), the vignette and grain overlay, region look recipes and weather.
The lamps after dark belong to `world/night_lights.gd`, which reads `Atmosphere.night_factor`.

Reads: region defs (`identity.light`, every key below; `identity.weather` weights), weather defs
(`core:weather/*`), WorldClock time, the current camera's height (for the haze), Settings `video`.
Emits: `EventBus.weather_changed(region_id, weather_id)`.
Consumes: `EventBus.region_entered`, `Settings.changed`.
Global shader parameters set every frame (declared in project.godot `[shader_globals]`):
`wm_wind_strength`, `wm_wind_dir`, `wm_wetness`, `wm_time_of_day`, `wm_region_tint`, and for the
water, the windows and the lamps `wm_night` (0 day .. 1 night), `wm_sun_dir`, `wm_moon_dir`, and
`wm_sun_color`, `wm_moon_color`, `wm_sky_zenith`, `wm_sky_horizon` as **linear vec3s** (so no
shader has to guess whether a colour global was converted from sRGB for it).
Save section: `world` → `{"weather": {region_id: weather_id}, "weather_timer": seconds}`.

Public API (Atmosphere):
* `set_region(region_id: String, instant := false)`, `settle()` (finish any blend now: captures)
* `force_weather(weather_id: String, instant := true)`
* `current_weather_id() -> String`, `weather_params() -> Dictionary` (blended values)
* `look() -> Dictionary` (the blended region look), `state` (elevation, night, dusk, haze top)
* `sun_direction() -> Vector3` (toward the sun), `light_level_at(pos) -> float` (0..1, for stealth)
* static: `sky_sample(elevation_deg)`, `night_of(elevation_deg)`, `night_factor`,
  `grade_lut(look)`, `grade_colour(c, lift, gain, mid)`, `_look_from_region(def)`, `_day_sample(hour)`

Review: `game/tools_gd/atmosphere_review.tscn` renders every region at six times of day;
`tools/capture/plans/look.json` (from `make_default_plan.py --look`) is dusk, dawn, night, the
lamps, the Mere and four waterfalls in the built world; `game/tools_gd/render_probe.gd` measures
which Environment features the renderer in use actually draws.

## How the light is made

**The day follows the sun, not the clock.** `SUN_KEYS` is keyed by the sun's elevation: zenith
and horizon colour, sun colour and energy, ambient energy, stars, and `dusk` (how hard the horizon
under the sun burns). A region's `sun_elevation_scale` and `_bias` are its latitude, and the sky
follows wherever they put the sun. Keyed by the hour, as it was, Cinderlea's nine-degree sun at
half past four stood under a mid-afternoon sky.

**Two fogs.** The far fog is aerial perspective: exponential, the region's `fog_color` pulled
toward the horizon (hardest at dusk, when the whole distance goes the colour of the sky behind
it) and toward `night_tint` after dark. The low haze is Godot's height fog, which is a function
of a fragment's height alone and not of its distance, so a haze top fixed in the world veils the
grass at your feet as thickly as the valley a kilometre off. Its top is therefore held
`haze_below_eye` metres under the camera and never above `haze_ceiling`: the near ground stays
clear and the valleys you look down into fill. `haze_morning` thickens it after sunrise.

**Coloured shadows.** The fill is `ambient_tint` at `ambient_energy`, with `sky_contribution` of
the sky's own light mixed in. Painted light is warm light and cool shadow; the tint is the
shadow's colour, not a brightness.

**The grade.** Saturation, contrast and brightness, then a 3D LUT built from the region's
`shadow_lift` (the hue the blacks lean toward), `highlight_gain` and `midtone_tint`
(`Atmosphere.grade_lut`, rebuilt at most every 0.4 s while a look blends). ACES, with the
region's `exposure` and `tonemap_white`; at night the exposure rises to `night_exposure`, the way
the eye opens, so a moonlit country reads blue rather than black and the lamps bloom. Over the
frame, under the HUD: a vignette in the region's own dark, and grain where `grain` asks for it.

**The sky** (`assets/shaders/painted_sky.gdshader`): a gradient that burns round a low sun and
goes rose on the far side over the earth's blue shadow; a sun disc a degree and a half across
with a tight halo, a glow and a wide dusk wash; cumulus lit from the side the light is on (the
density a step toward the sun against the density here), falling into four flat painted steps
with a silver lining near the light and undersides lit by a low sun; cirrus streaked out along
the wind; a bank of stratus on the horizon where `cloud_band` asks for it; and at night stars in
two sizes, a band of milk and a moon with seas on its face. The moon is its own
DirectionalLight3D, left out of the sky shader, and takes the shadow cascades over once the sun
has set, so only one of the two ever pays for them -- and the moon on two cascades over 160 m,
not the sun's four over 260.

**Forward+ extras.** SSAO (`video/ssao`, on), volumetric fog (`video/volumetric_fog`, off) and
SDFGI (`video/sdfgi`, off) are enabled only when the renderer is Forward+ *and* the setting is on.
Nothing in the look depends on them: every image this project reviews is shot on Compatibility.

## The recipe (`identity.light`)

Every key is optional; `Atmosphere.DEFAULT_LOOK` is what a silent region gets.

| key | what it is |
|---|---|
| `name` | the palette's name |
| `sun_color`, `sun_color_low` | the sun above ~20°, and near the horizon |
| `sun_elevation_scale`, `sun_elevation_bias` | the region's latitude: how high its sun climbs |
| `sun_energy` | the sun's strength against the day's own curve |
| `ambient_tint`, `ambient_energy`, `sky_contribution` | the shadows' colour and strength, and how much of the sky's own light is in them |
| `fog_color`, `fog_density`, `aerial_perspective`, `fog_sun_scatter`, `fog_sky_affect` | the far fog |
| `haze_density`, `haze_ceiling`, `haze_below_eye`, `haze_morning` | the low haze (per metre; world metres; metres under the eye; extra after sunrise) |
| `saturation`, `contrast`, `brightness`, `exposure`, `tonemap_white` | the grade's basics |
| `shadow_lift`, `highlight_gain`, `midtone_tint` | the LUT: the hue the blacks lean toward, the lights' warmth, the middle's tint |
| `bloom`, `grain`, `vignette`, `vignette_tint` | glow; film grain; the frame's edge |
| `sky_tint`, `horizon_tint`, `dusk_tint` | the sky's colour, its horizon band, the burning horizon at dusk |
| `cloud_scale`, `cloud_height`, `cloud_band`, `cirrus`, `cloud_bias`, `painterly` | the region's clouds: size, flatness, stratus banding, high streaks, extra cover, how stepped the light on them is |
| `night_tint`, `night_exposure`, `moon_energy` | moonlight and night fill; the eye's opening; the moon's strength |
| `god_rays` | on Forward+ with volumetric fog on, denser forward-scattering volumetric fog: shafts. Nothing on Compatibility |

## Six lights

Each region is written as a light first and a palette second: what the light is doing, and why
this region's and no other's. The values are in `content/packs/core/regions/regions.json`.

**Hearthvale — Harvest Gold.** A warm gold sun, 30° at nine and 40-odd at noon, casting long
soft shadows that lean lavender-blue (`#aab2d8`, half of it the sky's), so the gold has something
to stand against. A pale gold haze lies in the vales and dry valleys under a ceiling of 45 m,
thickest in the first hours after sunrise (`haze_morning` 1.5: "fog pale gold in the mornings"),
and never on the downs themselves. Saturated (1.16), with soft bloom. The shadows lift toward
violet, the highlights warm; fair-weather cumulus. The storybook's opening page.

**Brightwater — Lake Glass.** High, clean, white light and hard noon shadows, blue from a clear
sky (`sky_contribution` 0.75). The far distance goes sky-blue (`aerial_perspective` 0.6) and a
thin blue-grey haze lies on the water under 24 m. The brightest exposure of the six (1.06), crisp
contrast, cool shadow lift, and high streaked cirrus. The water glitters: the sun path on the Mere
is the one thing a screenshot of Brightwater should always have.

**Sedgemire — Drowned Lantern.** A weak, pale sun (0.7) behind low flat stratus (`cloud_band`
0.75) and diffuse teal light that comes from everywhere at once (ambient 1.2). The fog is the
region: the densest far fog, and a haze two and a half metres under the eye that lies over every
channel and pool, so the marsh breathes mist at your feet and the distance dissolves. Low contrast,
desaturated, shadows lifted toward bruise-purple and indigo, a heavy vignette. At night, teal
moonlight and the lanterns far off across the water.

**Briarwold — Green Cathedral.** An amber sun (1.2) that makes the clearings blaze against deep
green shade (`#3f5c3a`, barely any sky in it: under a canopy the sky is not what lights you). Green
haze in the ravines and the lower wood, held thirty metres under you so the forest you look down
on goes soft and gold-green toward the sun (`fog_sun_scatter` 0.35). High contrast, saturated,
the strongest bloom, amber highlights over teal-green shadows, the darkest vignette. The shafts are
the region's (`god_rays`): on Forward+ with volumetric fog turned on, its volumetric fog is denser
and scatters toward the sun. On Compatibility there are none, and the region does not lean on them.

**Skerrow Heights — Bone and Slate.** Cold, clear, hard light from the highest sky and the lowest
sun (scale 0.38: 32° at two in the afternoon, so every crag throws a long shadow), shadows a deep
cold blue straight from the sky (`sky_contribution` 0.8). The thinnest air of the six (fog
0.00014) and a far horizon that goes to sky-blue rather than to grey; almost no haze, and only
eighty metres below you in the gorges. High contrast, cool, desaturated, wind-streaked cirrus,
alpenglow at dawn (`sun_color_low` `#ffb8a8`), and snow under a bright blue moon.

**Cinderlea — Ember Ash.** A sun that never climbs (nine degrees at half past four) and burns
faded gold through the ash haze, which glows round it (`fog_sun_scatter` 0.55, the highest). The
ground is char and ash, so the fill is lifted and grey-violet (ambient 1.35) to keep the black
soil reading as soil rather than as nothing. Even so the char in shade came out black, so the
grade lifts the blacks furthest of the six, grey-violet (`#474a62`), and eases the contrast
under one: ash should read as ash. Desaturated (0.55), flat ash bands in the sky, the highlights
faded gold, film grain, and the heaviest vignette. The only region whose screenshot should look
old.
