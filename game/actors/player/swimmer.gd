class_name Swimmer
extends RefCounted
## The water a body stands or swims in: how deep it is at the body, how much that slows a wade,
## when the body floats, and where it floats. The player owns one (Player._swimmer) and swims in
## State.SWIM; everything here is read from the body's own position each physics tick.
##
## Heights are for a body of the default 1.8 m and scale with `body_scale`. `submersion` is how far
## the surface stands above the soles; the bed is what the body stands on (a collider or the
## heightfield), so a pool on a bridge and a lake read alike.

## Wading: past the knee and the waist the water holds the legs back, and at the chest the body
## floats. Swimming stops (the feet find the bed) below SWIM_UNTIL, so a body at the edge does not
## flicker between the two.
const KNEE_M := 0.5
const WAIST_M := 1.0
const SWIM_FROM_M := 1.35
const SWIM_UNTIL_M := 1.2
## Pace kept against the water: 1 in the shallows, down to these at the knee, the waist and the chest.
const WADE_KNEE := 0.85
const WADE_WAIST := 0.6
const WADE_CHEST := 0.45
## A swimming body rides with its soles this far under the surface: the chin at it, treading, and
## the shoulders at it in the stroke (tools/forge/lib/anim_clips.py SWIM_FLOAT_M).
const FLOAT_M := 1.45
## Swimming pace, m/s: a stroke is slower than a walk, and a hard stroke (Sprint) costs stamina.
const SWIM_SPEED := 1.6
const STROKE_SPEED := 2.6
const STROKE_STAMINA_PER_S := 10.0
const SWIM_ACCEL := 3.0
const SWIM_DECEL := 2.2
const SWIM_TURN := deg_to_rad(240.0)
## How fast the body settles onto its float height, and the most it rises or sinks doing so.
const FLOAT_SPRING := 4.0
const FLOAT_MOST := 2.0
## A dive: down to this far under the float, never closer than BED_CLEAR to the bed, at DIVE_SPEED.
## Under water the breath runs down; with none left the body goes up until it has half again.
const DIVE_MOST_M := 3.0
const DIVE_SPEED := 1.2
const BED_CLEAR := 0.15
const BREATH_S := 20.0
const BREATH_BACK_PER_S := 4.0
## Reading the water: a surface further than this from the body is some other water (the map under
## an interior in its pocket high above it, a lake below a cliff path).
const NEAR_WATER_M := 6.0

var body_scale := 1.0
## Where the water stands at the body, and how deep: NAN / 0 on dry land.
var surface_y := NAN
var bed_y := NAN
var submersion := 0.0
var depth := 0.0
## How far under the float the body has dived (0 at the surface), and the breath it has left.
var dive := 0.0
var breath := BREATH_S
var out_of_breath := false


## The water's surface over (x, z), or NAN where there is none. The one place the game asks where
## the water is, for the swimmer and its camera: its source is TerrainProvider.water_level_at
## (lakes, rivers and the sea, from the built world's water maps).
static func water_surface_y(at: Vector3) -> float:
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("water_level_at"):
		return NAN
	var level := float(provider.call("water_level_at", at.x, at.z))
	if level <= -999.0:
		return NAN
	return level


## Reads the water at a body standing (or floating) at `feet`, with the bed at `bed` (NAN when
## nothing was found below it).
func read(feet: Vector3, bed: float) -> void:
	bed_y = bed
	var s := water_surface_y(feet)
	if is_nan(s) or absf(s - feet.y) > NEAR_WATER_M * body_scale:
		surface_y = NAN
		submersion = 0.0
		depth = 0.0
		return
	surface_y = s
	submersion = maxf(s - feet.y, 0.0)
	depth = maxf(s - bed, 0.0) if not is_nan(bed) else submersion


func in_water() -> bool:
	return not is_nan(surface_y) and submersion > 0.0


## Deep enough to float here: the water stands past the chest over the bed.
func deep_enough() -> bool:
	return not is_nan(surface_y) and depth >= SWIM_FROM_M * body_scale and submersion >= SWIM_FROM_M * body_scale * 0.85


## Shallow enough to stand: the bed is within the legs' reach.
func can_stand() -> bool:
	return is_nan(surface_y) or depth < SWIM_UNTIL_M * body_scale


## The share of its pace a wading body keeps (1 on dry land).
func wade_mult() -> float:
	if not in_water():
		return 1.0
	var d := submersion / body_scale
	if d <= KNEE_M * 0.6:
		return 1.0
	if d <= KNEE_M:
		return lerpf(1.0, WADE_KNEE, (d - KNEE_M * 0.6) / (KNEE_M * 0.4))
	if d <= WAIST_M:
		return lerpf(WADE_KNEE, WADE_WAIST, (d - KNEE_M) / (WAIST_M - KNEE_M))
	return lerpf(WADE_WAIST, WADE_CHEST, clampf((d - WAIST_M) / (SWIM_FROM_M - WAIST_M), 0.0, 1.0))


## Past the waist there is no sprinting, rolling or jumping; the water has the legs.
func waist_deep() -> bool:
	return in_water() and submersion >= WAIST_M * body_scale


## The height the soles ride at while swimming: the float, less the dive, kept off the bed.
func float_feet_y() -> float:
	var y := surface_y - FLOAT_M * body_scale - dive
	if not is_nan(bed_y):
		y = maxf(y, bed_y + BED_CLEAR)
	return y


## A tick of the dive and the breath: `down` asks to dive, and the body rises again when it lets go
## or has no breath left.
func tick_dive(down: bool, delta: float) -> void:
	if out_of_breath and breath >= BREATH_S * 0.5:
		out_of_breath = false
	var want_down := down and not out_of_breath
	dive = move_toward(dive, DIVE_MOST_M * body_scale if want_down else 0.0, DIVE_SPEED * delta)
	if not is_nan(bed_y) and not is_nan(surface_y):
		dive = minf(dive, maxf(surface_y - FLOAT_M * body_scale - bed_y - BED_CLEAR, 0.0))
	if under():
		breath = maxf(breath - delta, 0.0)
		if breath <= 0.0:
			out_of_breath = true
	else:
		breath = minf(breath + BREATH_BACK_PER_S * delta, BREATH_S)


## The head is under the surface.
func under() -> bool:
	return dive > 0.35 * body_scale


func reset() -> void:
	dive = 0.0
	breath = BREATH_S
	out_of_breath = false
