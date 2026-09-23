# systems/atmosphere

Purpose: the look of the sky and the light. One `Atmosphere` node (scene `atmosphere.tscn`)
owns the sun, the moon, the WorldEnvironment (painted sky shader, two layers of fog, tonemap,
glow, the region colour grade), the vignette and grain overlay, region look recipes and weather.
The lamps after dark belong to `world/night_lights.gd`, which reads `Atmosphere.night_factor`
and lights every fire and lamp in the open country, the points of interest's included, from
one pool (at most eight, so Compatibility's twelve lights on one object are never passed).

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
frame, under the HUD: a faint vignette in the region's own dark, and grain where `grain` asks
for it and the player has turned it on. The blacks take a fifth of `shadow_lift` (`GRADE_LIFT`),
not the 0.45 they first took, which greyed every shadow. The table grades the sky as well as the
land, so `highlight_gain` and `midtone_tint` stay within a few percent of white: Hearthvale's
first warm midtone (`#fff2d6`) took a sixth of the blue out of a mid-blue sky and turned it
olive-grey, which on Forward+ was the whole top half of every frame. Warmth is the sun's colour's
job, and the fill's; the table leans, it does not tint. The table is made once and rewritten in
place as a blend moves; it is never replaced: the first cut handed the Environment a new texture
for every refresh of a blend, fifteen in six seconds, swapping a resource the renderer was
drawing with.

**The sky** (`assets/shaders/painted_sky.gdshader`): a gradient whose blue comes down to within
a few degrees of the horizon (`horizon_sharpness` 4.5) over a horizon that takes only a little of
the fog's colour (0.15) -- a level view sees the sky only up to twenty degrees or so, and at 3.2
and 0.3 all of that was a band of each region's fog-grey -- that burns round a low sun and
goes rose on the far side over the earth's blue shadow; a sun disc a degree and a half across
with a tight halo, a glow and a wide dusk wash; cumulus as masses -- a slowly warped low-frequency
field with the fine octaves only on its edges -- lit from the side the light is on, measured on
the smooth field so the light falls in broad strokes, in three soft painted steps, a little
greyer at the heart, with a silver lining near the light, undersides lit by a low sun, and the
far ones going the colour of the air. A thin cloud is lit through, and deep inside an overcast
the modelling eases off, so a grey sky is grey and not a field of dark eyes. Cirrus streaked out
along the wind; a bank of stratus on the horizon where `cloud_band` asks for it; and at night
stars in two sizes, a band of milk and a moon with seas on its face. The first version took its
shape and its light from one five-octave field stepped hard into four, and over the Briarwold it
drew camouflage: flat olive blotches with dark eyes; the second cut its masses from the raw
field, whose values hardly leave the middle, so a half-covered sky fell inside the soft edge and
came out as one grey wash (the field is now spread before it is cut; sampled off the shader's
own noise, the clear sky's 0.25 covers about a fifth of the sky and overcast's 0.85 nine
tenths). Two `pow()` calls of a possibly negative base drew a dotted black line up the sky at the
sun's bearing (and would have speckled the milk); both are guarded. The moon is its own
DirectionalLight3D, left out of the sky shader, and takes the shadow cascades over once the sun
has set, so only one of the two ever pays for them -- and the moon on two cascades over 160 m,
not the sun's four over 260.

**The water** (`assets/shaders/painted_water.gdshader`). None of it was drawn on a lake or the sea
until the water mask was read right: the builder writes it as 0 and 1, a shader samples a byte as
byte/255, and the shader's 0.5 test discarded every fragment of the sheet, so what showed on the
Mere was the lake bed's terrain texture (`WaterSurface.mask_bytes`, docs/CONTRACTS.md 6). Now: the
frame's own pixels mirrored where the
reflected ray lands -- followed over the water mask to the shore it meets, since that is where
what a lake mirrors stands, and projected to infinity where it meets none -- the sky's own
colours where the ray leaves the frame, a Fresnel term, glints under the sun and the moon.
Projected to infinity everywhere, as it first was, the far shore's reflection came out a
camera-height too high: from sixty metres over the Mere, three degrees, in the sky above the
hills, and the lake gave back nothing but pale sky. What the mirror shows is bent by a third of
the waves (`mirror_ripple`), and each region sets how rough its open water is: the Mere is Lake
Glass, calm enough to hold its island and its far shore upside down, where the first cut ran
every lake and sea at one wave height that scrambled any reflection into streaks of sky and
shore. Each region's `reflect`,
`cap`, `glint`, `waves` and `foam` are in `world/water_surface.gd`; the marsh raises almost no
foam, being shallower than the foam band everywhere, and the sea the most. `video/water_reflections` off puts
the water on the same shader built without the lookup (`WaterSurface.shader_for`): a material
that so much as names the screen texture has the frame copied for it, whatever its uniforms say.
The water asks the engine for no specular (`SPECULAR` 0): at 0.12 the renderer laid the sky's own
radiance over the mirror as well, its Fresnel rising to nearly the mirror's own share at a grazing
angle, and every lake came out as bright as the sky above it. Its depth is read per fragment,
not at the sheet's vertices ninety metres apart, and seen from under its surface it is its own
colour and mirrors nothing.

**Forward+ extras.** SSAO (`video/ssao`, on), volumetric fog (`video/volumetric_fog`, off) and
SDFGI (`video/sdfgi`, off) are enabled only when the renderer is Forward+ *and* the setting is on.
Nothing in the look depends on them. Forward+ is the renderer players have, and it can be shot
here on Mesa's software Vulkan (`--rendering-driver vulkan --rendering-method forward_plus`),
slowly: about four seconds a frame, and Terrain3D's clipmap at the game's nine LODs crashes that
driver on its first frame (seven draw, but a camera that moves can still bring it down), so a
Forward+ review is a few still shots or a still camera's run of frames.

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
| `dusk_fog_color`, `dusk_aerial` | the colour the distance goes at dusk (unset: the burning horizon's own), and how much more of the sky it takes |
| `cloud_scale`, `cloud_height`, `cloud_band`, `cirrus`, `cloud_bias`, `painterly` | the region's clouds: size, flatness, stratus banding, high streaks, extra cover, how stepped the light on them is |
| `night_tint`, `night_exposure`, `moon_energy` | moonlight and night fill; the eye's opening; the moon's strength |
| `god_rays` | on Forward+ with volumetric fog on, denser forward-scattering volumetric fog: shafts. Nothing on Compatibility |

## Six lights

Each region is written as a light first and a palette second: what the light is doing, and why
this region's and no other's. The values are in `content/packs/core/regions/regions.json`.

**Hearthvale — Harvest Gold.** A warm gold sun, 30° at nine and 40-odd at noon, casting long
soft shadows that lean lavender-blue (`#aab2d8`, half of it the sky's), so the gold has something
to stand against. At dusk the distance goes lavender-rose (`dusk_fog_color` `#b8a4c4`) and takes
more of the sky, over golden fields: every other dusk in the country is the burning horizon's own
orange, and Cinderlea's is ash-red, so the two warmest regions do not end the day alike. A pale gold haze lies in the vales and dry valleys under a ceiling of 45 m,
thickest in the first hours after sunrise (`haze_morning` 1.5: "fog pale gold in the mornings"),
and never on the downs themselves. Saturated (1.16), with soft bloom. The shadows lift toward
violet, the highlights warm; fair-weather cumulus. The storybook's opening page.

**Brightwater — Lake Glass.** High, clean, white light and hard noon shadows, blue from a clear
sky (`sky_contribution` 0.75). The far distance goes sky-blue (`aerial_perspective` 0.6) and a
thin blue-grey haze lies on the water under 24 m. The brightest exposure of the six (1.06), crisp
contrast, cool shadow lift, and high streaked cirrus. The water glitters: the sun path on the Mere
is the one thing a screenshot of Brightwater should always have.

**Sedgemire — Drowned Lantern.** A weak, pale sun (0.7) behind low flat stratus and diffuse
teal light that comes from everywhere at once (ambient 1.2). The fog is the region: the densest
far fog, and a mist that lies over every channel and pool under eight metres, so the marsh
breathes at your feet and the distance dissolves -- but not to white: at the first density the
Drowned Nave stood in a whiteout from its own landmark camera, so the far fog is 0.0009 and the
mist 0.022, the fog a darker teal, the contrast full and the bloom low. Desaturated, shadows
lifted toward bruise-purple and indigo, a heavy vignette. At night, teal
moonlight and the lanterns far off across the water.

**Briarwold — Green Cathedral.** An amber sun (1.2) that makes the clearings blaze against deep
green shade (`#4a6a48`, little sky in it: under a canopy the sky is not what lights you). The green
is in the fill and the foliage and nowhere else: the grade's midtones are neutral, the sky is a
clear warm blue, the far air a grey-teal that takes the sky's colour (`aerial_perspective` 0.35)
and leaves the sky alone (`fog_sky_affect` 0). The first cut put green in the grade, the sky
tint, the fog and the vignette at once, and the whole frame sat under a green-grey cast. High
contrast, saturated, the strongest bloom, amber highlights, teal-green blacks. The shafts are
the region's (`god_rays`): on Forward+ with volumetric fog turned on, its volumetric fog is denser
and scatters toward the sun. On Compatibility there are none, and the region does not lean on them.

**Skerrow Heights — Bone and Slate.** Cold, clear, hard light from the highest sky and the lowest
sun (scale 0.38: 32° at two in the afternoon, so every crag throws a long shadow), shadows a deep
cold blue straight from the sky (`sky_contribution` 0.8). The thinnest air of the six (fog
0.00014) and a far horizon that goes to sky-blue rather than to grey; almost no haze, and only
eighty metres below you in the gorges. The haze is 0.0005: Godot's height fog is measured by how
far a thing stands under the haze's top, not by how far it is from you, and at 0.0015 the whole
island seen from a 700 m vista stood half-white under a top eighty metres below the eye. High
contrast, cool, desaturated, wind-streaked cirrus, alpenglow at dawn (`sun_color_low` `#ffb8a8`),
and snow under a bright blue moon.

**Cinderlea — Ember Ash.** A sun that never climbs (nine degrees at half past four) and burns
gold (`#ffd49a`, 1.25) through the ash, with a haze that glows round it (`fog_sun_scatter`
0.35). The ground is char and ash, so the fill is violet (`#8c84b4` at 1.25) and holds the char in
shade as violet-grey rather than black, the highlights gold, the sky a clear pale blue
(`#9fb8dc`) over a warm horizon, few stratus bands (0.2), and the colour held back (0.92, the
least of the six) rather than taken away. This is where a new game opens, at the Hushline Stair,
and the first cut made it the greyest frame in the game: saturation 0.55, the blacks lifted to
an eighth grey, a far fog at 0.0008 that was a third of the way to beige at five hundred metres,
a cream-grey sky banded like a zoom, film grain and the heaviest vignette -- the player's first
sight of the country read as washed out and filtered, on Forward+ and on Compatibility alike.
The distance still goes to warm ash (fog `#b09a82`, 0.0003, aerial perspective 0.45); the
foreground is clear. Its weather was
grey seven times in ten -- ashfall and still grey, which took a further three tenths and a fifth
of what colour was left and thickened the fog by 1.7 and 1.4 -- so the dry wind and the thin sun
are the likelier now (35 and 30 in a hundred), and the two grey weathers, which no other region
has, take less (0.85 and 0.9 of the colour, fog 1.4 and 1.25).

**The frame overlays** are the player's: the vignette is faint (0.08 to 0.12) and
`video/vignette` turns it off; film grain (`grain`, Cinderlea's only) is drawn only when
`video/film_grain` is on, and it is off by default. Glow is for what is brighter than white: by
day nothing else is fed into it (`glow_bloom` is 0 until night), where the whole frame used to
be, which laid a soft light over everything on Forward+.
