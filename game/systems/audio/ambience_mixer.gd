extends Node
## AmbienceMixer (autoload `Ambience`): the layered bed under everything.
##
## A region's `identity.ambience` keys name the layers. Continuous ones (wind, water, reeds)
## are looping beds held at a level; sparse ones (a skylark, an owl, a bell) are pools of
## one-shots fired at random gaps. On top of those sit time-of-day layers, weather layers that
## follow Atmosphere.weather_params(), and a low-pass on the whole Ambience bus when the player
## steps indoors.
##
## Nothing is re-rendered at runtime: every layer is a file, and the mixer only moves levels.
## See README.md in this folder.

const AMBIENCE_DIR := "res://assets/audio/ambience"
const MANIFEST := AMBIENCE_DIR + "/manifest.json"

const FADE_SECONDS := 3.0
const SILENCE_DB := -60.0
const BED_DB := -6.0                  ## a bed's level when fully in
const ONESHOT_DB := -4.0
const INTERIOR_CUTOFF_HZ := 900.0     ## how much of the outside gets through a wall
const OPEN_CUTOFF_HZ := 20000.0
const CUTOFF_LERP := 4.0

## Thunder rolls are spaced this far apart, in seconds (the brief's 20-90 s).
const THUNDER_GAP := Vector2(20.0, 90.0)

## Layers that only belong to part of the day. Hours are [from, to), wrapping at midnight.
const TIME_LAYERS := {
	"night_insects": Vector2(20.0, 5.0),
	"night_insects_marsh": Vector2(19.5, 5.5),
	"dawn_chorus": Vector2(4.5, 8.0),
	"owl": Vector2(19.0, 6.0),
	"crows": Vector2(6.0, 19.0),
	"pipes_night": Vector2(20.0, 2.0),
	"bees": Vector2(7.0, 19.0),
	"skylark": Vector2(5.0, 19.0),
	"market_murmur": Vector2(7.0, 19.0),
	"woodpecker": Vector2(6.0, 18.0),
}

## Which night layer a region adds after dark, by region id.
const REGION_NIGHT_LAYER := {
	"core:region/hearthvale": "night_insects",
	"core:region/brightwater": "night_insects",
	"core:region/sedgemire": "night_insects_marsh",
	"core:region/briarwold": "night_insects",
	"core:region/skerrow": "",
	"core:region/cinderlea": "",
}

## Which rain surface a region's rain lands on.
const REGION_RAIN_LAYER := {
	"core:region/hearthvale": "rain_light",
	"core:region/brightwater": "rain_stone",
	"core:region/sedgemire": "rain_water",
	"core:region/briarwold": "rain_heavy",
	"core:region/skerrow": "rain_stone",
	"core:region/cinderlea": "rain_canvas",
}

signal layers_changed(active: Array)

var enabled := true
var region_id := ""
var interior := false

var _manifest: Dictionary = {}
var _beds: Dictionary = {}            ## key -> AudioStreamPlayer
var _bed_targets: Dictionary = {}     ## key -> target dB
var _pools: Dictionary = {}           ## key -> {"files": [...], "next": seconds}
var _pool_players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _atmosphere: Node
var _cutoff := OPEN_CUTOFF_HZ
var _lp_index := -1
var _thunder_timer := 0.0
var _weather_cache: Dictionary = {}

## Random gap between one-shots, per key, in seconds.
const POOL_GAPS := {
	"skylark": Vector2(4.0, 16.0),
	"gulls": Vector2(3.0, 12.0),
	"bittern": Vector2(25.0, 90.0),
	"owl": Vector2(20.0, 70.0),
	"woodpecker": Vector2(12.0, 45.0),
	"creak": Vector2(8.0, 30.0),
	"buoy_bell": Vector2(9.0, 26.0),
	"hammer_distant": Vector2(14.0, 50.0),
	"pipes_night": Vector2(45.0, 150.0),
	"bell_rare": Vector2(120.0, 300.0),
	"crows": Vector2(10.0, 40.0),
	"dawn_chorus": Vector2(2.5, 9.0),
	"thunder_near": THUNDER_GAP,
	"thunder_far": THUNDER_GAP,
}
const DEFAULT_GAP := Vector2(8.0, 30.0)


func _ready() -> void:
	_rng.seed = 90210
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_load_manifest()
	_lp_index = _find_lowpass()
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.name = "Shot%d" % i
		p.bus = "Ambience"
		add_child(p)
		_pool_players.append(p)
	EventBus.region_entered.connect(_on_region_entered)
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.interior_entered.connect(_on_interior_entered)
	EventBus.interior_exited.connect(_on_interior_exited)
	if not GameState.current_region_id.is_empty():
		set_region(GameState.current_region_id)


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		Log.warn("Ambience", "no manifest at %s; ambience will be silent" % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("Ambience", "manifest is not an object")
		return
	_manifest = parsed
	Log.info("Ambience", "manifest: %d entries" % _manifest.size())


func _find_lowpass() -> int:
	var bus := AudioServer.get_bus_index("Ambience")
	if bus < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			return i
	return -1


# --- regions -------------------------------------------------------------------------------------

func set_region(id: String) -> void:
	region_id = id
	_refresh()


func _on_region_entered(new_region: String, _prev: String) -> void:
	set_region(new_region)


func _on_hour_changed(_hour: int) -> void:
	_refresh()


func _on_weather_changed(_region: String, _weather: String) -> void:
	_refresh()


func _on_interior_entered(_interior_id: String) -> void:
	interior = true
	_refresh()


func _on_interior_exited(_interior_id: String) -> void:
	interior = Interiors.in_interior() if Interiors else false
	_refresh()


## Every layer that should be sounding now, as key -> dB.
func desired_layers() -> Dictionary:
	var out: Dictionary = {}
	if not enabled:
		return out
	var def := ContentDB.get_or_empty(region_id)
	var ident: Dictionary = def.get("identity", {})
	for key: String in ident.get("ambience", []):
		if not _in_time_window(key):
			continue
		out[key] = BED_DB
	# the night layer this region gets, if any
	var night: String = str(REGION_NIGHT_LAYER.get(region_id, ""))
	if not night.is_empty() and _in_time_window(night):
		out[night] = BED_DB - 3.0
	if _in_time_window("dawn_chorus") and _has("dawn_chorus") and not _is_bare_region():
		out["dawn_chorus"] = BED_DB - 4.0
	# weather
	out.merge(_weather_layers(), true)
	# interiors swap the outside for a room
	if interior:
		for key in out.keys():
			out[key] = float(out[key]) - 9.0
		out["room_tone"] = BED_DB - 2.0
	return out


func _is_bare_region() -> bool:
	return region_id == "core:region/cinderlea" or region_id == "core:region/skerrow"


func _weather_layers() -> Dictionary:
	var out: Dictionary = {}
	var w := weather_params()
	if w.is_empty():
		return out
	var precip := str(w.get("precipitation", "none"))
	var intensity := float(w.get("precip_intensity", 0.0))
	var wind := float(w.get("wind", 0.0))
	if precip == "rain" and intensity > 0.02:
		var key: String = str(REGION_RAIN_LAYER.get(region_id, "rain_light"))
		# light rain and heavy rain are separate recordings; the level follows the intensity
		if intensity < 0.45:
			out["rain_light"] = lerpf(SILENCE_DB, BED_DB + 1.0, clampf(intensity / 0.45, 0.0, 1.0))
		else:
			out[key] = lerpf(BED_DB - 5.0, BED_DB + 3.0, clampf((intensity - 0.45) / 0.55, 0.0, 1.0))
	elif precip == "snow" and intensity > 0.02:
		out["snow_hush"] = lerpf(SILENCE_DB, BED_DB, clampf(intensity, 0.0, 1.0))
	elif precip == "ash" and intensity > 0.02:
		out["ash_hiss"] = lerpf(SILENCE_DB, BED_DB, clampf(intensity, 0.0, 1.0))
	if wind > 0.15:
		var key := "wind_gust_strong" if wind > 0.6 else "wind_gust_light"
		out[key] = lerpf(BED_DB - 10.0, BED_DB + 1.0, clampf((wind - 0.15) / 0.85, 0.0, 1.0))
	if bool(w.get("thunder", false)):
		out["thunder_far"] = BED_DB
		if intensity > 0.6:
			out["thunder_near"] = BED_DB
	return out


## Atmosphere's blended weather values, or {} when there is no Atmosphere in the scene.
func weather_params() -> Dictionary:
	if not is_instance_valid(_atmosphere):
		_atmosphere = get_tree().get_first_node_in_group("atmosphere") if get_tree() else null
	if is_instance_valid(_atmosphere) and _atmosphere.has_method("weather_params"):
		_weather_cache = _atmosphere.weather_params()
	return _weather_cache


## Test seam: lets a test drive the mixer without an Atmosphere node.
func set_weather_override(params: Dictionary) -> void:
	_weather_cache = params
	_atmosphere = null
	_refresh()


static func _hour_in(hour: float, window: Vector2) -> bool:
	var from := window.x
	var to := window.y
	if from <= to:
		return hour >= from and hour < to
	return hour >= from or hour < to


func _in_time_window(key: String) -> bool:
	if not TIME_LAYERS.has(key):
		return true
	return _hour_in(WorldClock.time_hours, TIME_LAYERS[key])


func _has(key: String) -> bool:
	return _manifest.has(key)


func _refresh() -> void:
	var want := desired_layers()
	for key: String in want.keys():
		if not _has(key):
			continue
		var entry: Dictionary = _manifest[key]
		if str(entry.get("kind", "bed")) == "bed":
			_ensure_bed(key)
			_bed_targets[key] = float(want[key])
		else:
			if not _pools.has(key):
				_pools[key] = {"files": entry.get("files", []), "next": _next_gap(key), "db": 0.0}
			_pools[key]["db"] = float(want[key])
	# anything no longer wanted fades out
	for key: String in _bed_targets.keys():
		if not want.has(key):
			_bed_targets[key] = SILENCE_DB
	for key: String in _pools.keys():
		if not want.has(key):
			_pools.erase(key)
	layers_changed.emit(active_layers())


func _ensure_bed(key: String) -> void:
	if _beds.has(key) and is_instance_valid(_beds[key]):
		return
	var entry: Dictionary = _manifest.get(key, {})
	var files: Array = entry.get("files", [])
	if files.is_empty():
		return
	var stream := _load(str(files[0]))
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.name = "Bed_" + key
	p.bus = "Ambience"
	p.stream = stream
	p.volume_db = SILENCE_DB
	add_child(p)
	p.play()
	_beds[key] = p


func _load(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		Log.warn("Ambience", "missing %s" % path)
		return null
	return load(path) as AudioStream


func _next_gap(key: String) -> float:
	var g: Vector2 = POOL_GAPS.get(key, DEFAULT_GAP)
	return _rng.randf_range(g.x, g.y)


# --- per frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var step := delta / maxf(FADE_SECONDS, 0.01) * 60.0
	for key: String in _beds.keys():
		var p: AudioStreamPlayer = _beds[key]
		if not is_instance_valid(p):
			continue
		var target := float(_bed_targets.get(key, SILENCE_DB))
		p.volume_db = move_toward(p.volume_db, target, step)
		if p.volume_db <= SILENCE_DB and target <= SILENCE_DB and p.playing:
			p.stop()
		elif p.volume_db > SILENCE_DB and not p.playing:
			p.play()
	for key: String in _pools.keys():
		var pool: Dictionary = _pools[key]
		pool["next"] = float(pool["next"]) - delta
		if float(pool["next"]) <= 0.0:
			pool["next"] = _next_gap(key)
			_fire_oneshot(key, float(pool.get("db", ONESHOT_DB)))
	# interior muffling
	var want_cutoff := INTERIOR_CUTOFF_HZ if interior else OPEN_CUTOFF_HZ
	_cutoff = lerpf(_cutoff, want_cutoff, clampf(delta * CUTOFF_LERP, 0.0, 1.0))
	_apply_cutoff()


func _apply_cutoff() -> void:
	if _lp_index < 0:
		return
	var bus := AudioServer.get_bus_index("Ambience")
	if bus < 0:
		return
	var fx := AudioServer.get_bus_effect(bus, _lp_index) as AudioEffectLowPassFilter
	if fx:
		fx.cutoff_hz = _cutoff


func _fire_oneshot(key: String, db: float) -> bool:
	var pool: Dictionary = _pools.get(key, {})
	var files: Array = pool.get("files", [])
	if files.is_empty():
		return false
	var stream := _load(str(files[_rng.randi_range(0, files.size() - 1)]))
	if stream == null:
		return false
	var p := _free_player()
	if p == null:
		return false
	p.stream = stream
	p.volume_db = db + (ONESHOT_DB - BED_DB) + (-9.0 if interior else 0.0)
	p.pitch_scale = _rng.randf_range(0.94, 1.07)
	p.play()
	return true


func _free_player() -> AudioStreamPlayer:
	for p in _pool_players:
		if is_instance_valid(p) and not p.playing:
			return p
	return null


# --- introspection ------------------------------------------------------------------------------------

func active_layers() -> Array:
	var out: Array = []
	for key: String in _bed_targets.keys():
		if float(_bed_targets[key]) > SILENCE_DB:
			out.append(key)
	out.append_array(_pools.keys())
	out.sort()
	return out


func bed_volume_db(key: String) -> float:
	var p: AudioStreamPlayer = _beds.get(key)
	return p.volume_db if is_instance_valid(p) else SILENCE_DB


func target_db(key: String) -> float:
	return float(_bed_targets.get(key, SILENCE_DB))


func cutoff_hz() -> float:
	return _cutoff


## Stop and detach every stream on the way out; a playing Ogg keeps its decoder alive and
## Godot reports it as a leak at exit.
func release() -> void:
	stop_all()
	_release_players()
	_manifest.clear()

## Stop and detach every player under this node, whichever code path made it.
## A stream that is still playing keeps its decoder alive, and a node queue_freed during
## shutdown never reaches its deferred free, so both show up as leaks when the engine exits.
func _release_players() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D or child is AudioStreamPlayer2D:
			child.stop()
			child.stream = null


func _exit_tree() -> void:
	release()


## Finish with a bed player for good. Freed now rather than deferred: a queue_free() issued
## during shutdown never reaches its deferred call, and the stream playback the player still
## holds is then reported as a leak at exit.
func _discard(p: AudioStreamPlayer) -> void:
	if not is_instance_valid(p):
		return
	p.stop()
	p.stream = null
	if p.get_parent() == self:
		remove_child(p)
	p.free()


func stop_all() -> void:
	for key: String in _beds.keys():
		_discard(_beds[key])
	_beds.clear()
	_bed_targets.clear()
	_pools.clear()
	region_id = ""
