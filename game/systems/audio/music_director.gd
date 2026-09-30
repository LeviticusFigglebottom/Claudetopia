extends Node
## MusicDirector (autoload `Music`): decides what the score is doing and mixes it.
##
## A region has a theme -- five stems started together and held in sync, whose levels make the
## mode -- and a rotation of pieces around it (triage 2026-09-27 #19: one loop, however good,
## wore thin). By day the theme and two more day pieces take turns, by night two night pieces;
## none plays twice running, each plays for a couple of minutes and fades, and more often than
## not the country is left to its ambience for half a minute to a minute and a half before the
## next one. A fight crossfades to the region's fight piece and back to whatever was playing.
## Interiors keep the theme's stems in their deep mix, as before: they drop the melody for the
## deep stem, because that is where the ringing failed (WORLD_BIBLE 1.1). A dangerous region
## plays the theme in that deep mix too, when the theme is its piece. Night pulls the theme's
## melody back and lets a little of the deep stem in. Menus, bosses and stingers take over on top.
##
## Nothing is ever switched: every change of state is a change of level, run over
## STEM_FADE_SECONDS, and a new track (a region, a piece, a boss, the menu theme) comes in on its
## own player while the old one goes out on another.
##
## See README.md in this folder.

const STEMS: Array[String] = ["pad", "melody", "texture", "combat", "deep"]

const CROSSFADE_SECONDS := 4.0
const STEM_FADE_SECONDS := 1.6
const COMBAT_DECAY_SECONDS := 8.0     ## combat_intensity falls from 1 to 0 over this long
const COMBAT_HIT_GAIN := 0.5          ## how much one hit on the player raises the intensity
## The combat layer's floor while any enemy is fighting: a fight is a fight before the first blow
## lands and through every roll that keeps it from landing, not only in the seconds after a hit.
const ENGAGED_LEVEL := 0.6
## Hours [from, to) that count as night for the score, wrapping at midnight.
const NIGHT_HOURS := Vector2(21.0, 5.0)
const MENU_DUCK_DB := -10.0
const SILENCE_DB := -60.0
const DEEP_DANGER := 4                ## region danger at or above which the deep stem takes over

## The rotation. A piece loops until it has played at least PIECE_MIN_SECONDS, fading in over the
## first PIECE_FADE_IN_SECONDS (except the first piece of a region, which the region crossfade
## brings in) and out over the last PIECE_FADE_OUT_SECONDS. Then, GAP_CHANCE of the time, a
## silence of GAP_SECONDS; otherwise the next piece comes in under the fade: a crossfade.
const PIECE_MIN_SECONDS := 120.0
const PIECE_FADE_IN_SECONDS := 6.0
const PIECE_FADE_OUT_SECONDS := 10.0
const GAP_SECONDS := Vector2(30.0, 90.0)
const GAP_CHANCE := 0.7
## Players for the rotation's single-file pieces and the fight: the one playing, the one fading
## out under it, the fight, and the previous region's of each going out during a crossfade.
const PIECE_PLAYERS := 6

## Volume of each stem in each mode, in dB. -60 is silence.
const MIX_EXPLORE := {"pad": 0.0, "melody": 0.0, "texture": -1.0, "combat": SILENCE_DB, "deep": SILENCE_DB}
## A fight with no fight piece to go to (none rendered for the region) raises the theme's own
## combat stem instead, as every fight did before the rotation.
const MIX_COMBAT := {"pad": -2.0, "melody": -9.0, "texture": -4.0, "combat": 0.0, "deep": SILENCE_DB}
const MIX_DEEP := {"pad": -4.0, "melody": SILENCE_DB, "texture": -10.0, "combat": SILENCE_DB, "deep": 0.0}
const MIX_DEEP_COMBAT := {"pad": -5.0, "melody": SILENCE_DB, "texture": -9.0, "combat": -2.0, "deep": -4.0}
const MIX_NIGHT := {"pad": -3.0, "melody": -11.0, "texture": -5.0, "combat": SILENCE_DB, "deep": -14.0}

signal region_music_changed(music_id: String)
signal mode_changed(mode: String)
## A piece of the rotation came in ("" when a silence begins).
signal piece_changed(music_id: String)

var combat_intensity := 0.0
var current_music_id := ""            ## the region's theme
var current_region_id := ""
var mode := "explore"                 ## explore | night | combat | deep | deep_combat
var enabled := true
var gap_chance := GAP_CHANCE          ## how often a piece is followed by a silence (tests pin it)

## Two fixed banks of stem players, created once. A region change hands the current bank to
## _outgoing to fade away and fills the other; nothing is ever allocated or freed while the
## game runs. (Freeing a player also turned out to strand the stream playback the AudioServer
## was still holding, which showed up as a leak on every headless run.)
var _banks: Array[Dictionary] = [{}, {}]
var _bank := 0
var _players: Dictionary = {}         ## stem -> AudioStreamPlayer (current region)
var _outgoing: Array[AudioStreamPlayer] = []
var _targets: Dictionary = {}         ## stem -> target dB
## The rotation's players, made once like the banks.
var _piece_players: Array[AudioStreamPlayer] = []
## The piece playing now and the one fading out under it: {id, player (null for the theme's
## stems), elapsed, length}. Empty when nothing is. Both are still while the rotation is held.
var _now: Dictionary = {}
var _prev: Dictionary = {}
var _gap_left := 0.0                  ## seconds of silence left before the next piece
var _next_decided := false            ## whether the piece now playing knows what follows it
var _last_piece := ""                 ## never played twice running
var _fight_player: AudioStreamPlayer
var _fight_id := ""
var _pools: Dictionary = {}           ## region_id -> {"day": [ids], "night": [ids], "combat": id}
var _piece_defs: Dictionary = {}      ## music id -> def, for the rotation's pieces
var _rng := RandomNumberGenerator.new()
## Menu theme / boss track: replaces the region bed. Two players, so that one track can go out
## while the next comes in (boss_1 to boss_2 used to stop one and start the other on one player).
var _overlays: Array[AudioStreamPlayer] = []
var _overlay_now := 0                 ## which of _overlays carries the current overlay
var _overlay_kind := ""               ## "" | "menu" | "boss" | "cue"
var _overlay_id := ""                 ## the music id the current overlay carries
var _engaged: Dictionary = {}         ## instance id -> WeakRef, every enemy fighting now
var _stinger: AudioStreamPlayer
var _boss_id := ""
var _boss_intensity := 1
var _open_menus: Array[String] = []
var _music_defs: Dictionary = {}      ## region_id -> music def
var _stingers: Dictionary = {}
var _duck_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_index_content()
	for b in 2:
		for stem in STEMS:
			_banks[b][stem] = _make_player("Bank%d_%s" % [b, stem])
	for i in PIECE_PLAYERS:
		_piece_players.append(_make_player("Piece_%d" % i))
	_overlays = [_make_player("Overlay_A"), _make_player("Overlay_B")]
	_stinger = _make_player("Stinger")
	EventBus.region_entered.connect(_on_region_entered)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.enemy_engaged.connect(_on_enemy_engaged)
	EventBus.hour_changed.connect(_on_hour_changed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.level_up.connect(_on_level_up)
	EventBus.quest_stage_changed.connect(_on_quest_stage_changed)
	EventBus.hearthstone_rested.connect(_on_rested)
	EventBus.echo_recovered.connect(_on_echo_recovered)
	EventBus.menu_opened.connect(_on_menu_opened)
	EventBus.menu_closed.connect(_on_menu_closed)
	EventBus.interior_entered.connect(_on_interior_changed.unbind(1))
	EventBus.interior_exited.connect(_on_interior_changed.unbind(1))
	if not GameState.current_region_id.is_empty():
		play_region(GameState.current_region_id, true)


func _index_content() -> void:
	var variations: Array = []
	for def in ContentDB.all("music"):
		if def.has("region"):
			_music_defs[str(def["region"])] = def
		elif def.has("for_region"):
			variations.append(def)
		if def.has("stingers"):
			_stingers = def["stingers"]
	# Each region's rotation: its theme first among the day pieces, then its variations by role.
	for region_id: String in _music_defs:
		var theme_id := str(_music_defs[region_id].get("id", ""))
		_pools[region_id] = {"day": [theme_id], "night": [], "combat": ""}
	for def: Dictionary in variations:
		var pool: Dictionary = _pools.get(str(def["for_region"]), {})
		if pool.is_empty():
			continue
		var id := str(def.get("id", ""))
		_piece_defs[id] = def
		match str(def.get("role", "")):
			"day": (pool["day"] as Array).append(id)
			"night": (pool["night"] as Array).append(id)
			"combat": pool["combat"] = id
	for region_id: String in _pools:
		var pool: Dictionary = _pools[region_id]
		(pool["day"] as Array).sort()
		(pool["night"] as Array).sort()
		# a region with no night pieces keeps its theme, in the night mix, after dark
		if (pool["night"] as Array).is_empty():
			pool["night"] = [str(_music_defs[region_id].get("id", ""))]
	Log.info("Music", "indexed %d region themes, %d rotation pieces, %d stingers" % [
		_music_defs.size(), _piece_defs.size(), _stingers.size()])


func _make_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = "Music"
	p.volume_db = SILENCE_DB
	add_child(p)
	return p


# --- regions ---------------------------------------------------------------------------------

## Start (or crossfade to) a region's music. `instant` skips the crossfade.
func play_region(region_id: String, instant := false) -> bool:
	if not enabled or region_id == current_region_id:
		return false
	var def: Dictionary = _music_defs.get(region_id, {})
	if def.is_empty():
		Log.warn("Music", "no music for region %s" % region_id)
		return false
	current_region_id = region_id
	current_music_id = str(def.get("id", ""))
	_retire_current(instant)
	_bank = 1 - _bank
	var stems: Dictionary = def.get("stems", {})
	for stem in STEMS:
		if not stems.has(stem):
			continue
		var stream := _load_stream(str(stems[stem]))
		if stream == null:
			continue
		var p: AudioStreamPlayer = _banks[_bank][stem]
		p.stop()
		p.stream = stream
		p.volume_db = SILENCE_DB
		p.play()
		_players[stem] = p
	# By day a region opens on its theme, which is what the place sounds like; by night on one
	# of its night pieces. Either way it comes in with the region crossfade, not a fade of its own.
	_last_piece = ""
	var first := current_music_id if not is_night() else _pick_piece()
	_start_piece(first, false)
	_refresh_mode(true)
	if instant:
		for stem: String in _players:
			(_players[stem] as AudioStreamPlayer).volume_db = _stem_db(stem)
		if _now.get("player") != null:
			(_now["player"] as AudioStreamPlayer).volume_db = _entry_db(_now)
	region_music_changed.emit(current_music_id)
	return true


func _load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		# once for each path: a missing file is one fault, not one a minute
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			Log.warn("Music", "missing stream %s" % (path if not path.is_empty() else "(no path given)"))
		return null
	var s := load(path)
	return s as AudioStream


func _retire_current(instant: bool) -> void:
	for stem: String in _players:
		var p: AudioStreamPlayer = _players[stem]
		if instant:
			_discard(p)
		else:
			_outgoing.append(p)
	_players.clear()
	for entry in [_now, _prev]:
		var p: AudioStreamPlayer = entry.get("player")
		if p != null:
			if instant:
				_discard(p)
			elif not _outgoing.has(p):
				_outgoing.append(p)
	if _fight_player != null:
		if instant:
			_discard(_fight_player)
		elif not _outgoing.has(_fight_player):
			_outgoing.append(_fight_player)
	_now = {}
	_prev = {}
	_fight_player = null
	_fight_id = ""
	_gap_left = 0.0
	_next_decided = false


## Finish with a player: stop it and drop its stream. The node itself stays, to be used again
## by the next region -- see the note on _banks.
func _discard(p: AudioStreamPlayer) -> void:
	if not is_instance_valid(p):
		return
	p.stop()
	p.stream = null


# --- the rotation ------------------------------------------------------------------------------

## The pieces a region rotates through at a time of day ("day" | "night"), or its fight ("combat").
func pieces_for(region_id: String, role: String) -> Array:
	var pool: Dictionary = _pools.get(region_id, {})
	if role == "combat":
		var id := str(pool.get("combat", ""))
		return [] if id.is_empty() else [id]
	return (pool.get(role, []) as Array).duplicate()


## "day", "night" or "combat" for a rotation piece; a region's theme is a day piece.
func piece_role(music_id: String) -> String:
	if _piece_defs.has(music_id):
		return str(_piece_defs[music_id].get("role", ""))
	for region_id: String in _music_defs:
		if str(_music_defs[region_id].get("id", "")) == music_id:
			return "day"
	return ""


## The rotation piece playing now, "" in a silence between pieces.
func current_piece() -> String:
	return str(_now.get("id", ""))


func in_gap() -> bool:
	return _now.is_empty() and not current_region_id.is_empty()


## Seconds of silence left before the next piece.
func gap_left() -> float:
	return _gap_left if in_gap() else 0.0


## What comes next: a piece for the time of day, never the one just played if there is another.
func _pick_piece() -> String:
	var pool := pieces_for(current_region_id, "night" if is_night() else "day")
	var choices := pool.filter(func(id): return id != _last_piece)
	if choices.is_empty():
		choices = pool
	if choices.is_empty():
		return current_music_id
	return str(choices[_rng.randi_range(0, choices.size() - 1)])


## Bring a piece in. The theme restarts its stems from the top (they are silent whenever it is
## not the piece, so nothing is heard to jump); anything else takes a free piece player.
func _start_piece(music_id: String, fade_in: bool) -> void:
	var entry := {"id": music_id, "player": null, "elapsed": 0.0 if fade_in else PIECE_FADE_IN_SECONDS}
	var loop_seconds := 0.0
	if music_id == current_music_id:
		loop_seconds = float(_music_defs[current_region_id].get("loop_seconds", 0.0))
		if fade_in and _players.values().all(func(p): return p.volume_db <= SILENCE_DB + 0.01):
			for stem: String in _players:
				var p: AudioStreamPlayer = _players[stem]
				p.stop()
				p.volume_db = SILENCE_DB
				p.play()
	else:
		var def: Dictionary = _piece_defs.get(music_id, {})
		var stream := _load_stream(str((def.get("stems", {}) as Dictionary).get("main", "")))
		if stream == null:
			# a piece that cannot be loaded gives its turn back to the theme
			if music_id != current_music_id:
				_start_piece(current_music_id, fade_in)
			return
		var p := _free_piece_player()
		p.stop()
		p.stream = stream
		p.volume_db = SILENCE_DB
		p.play()
		entry["player"] = p
		loop_seconds = float(def.get("loop_seconds", 0.0))
	if loop_seconds <= 0.0:
		loop_seconds = PIECE_MIN_SECONDS
	entry["length"] = ceilf(PIECE_MIN_SECONDS / loop_seconds) * loop_seconds
	_now = entry
	_last_piece = music_id
	_next_decided = false
	_gap_left = 0.0
	piece_changed.emit(music_id)


func _free_piece_player() -> AudioStreamPlayer:
	var busy: Array = [_now.get("player"), _prev.get("player"), _fight_player]
	for p in _piece_players:
		if not p.playing and not busy.has(p) and not _outgoing.has(p):
			return p
	# All six busy can only mean several regions crossed in a few seconds: take the quietest
	# of those going out.
	var best: AudioStreamPlayer = null
	for p in _outgoing:
		if _piece_players.has(p) and (best == null or p.volume_db < best.volume_db):
			best = p
	if best != null:
		_outgoing.erase(best)
		_discard(best)
		return best
	return _piece_players[0]


## The rotation moves only while it is what the player hears: outdoors, out of a fight, with no
## boss, cutscene or menu theme over it.
func _rotating() -> bool:
	return not current_region_id.is_empty() and GameState.current_interior_id.is_empty() \
		and combat_intensity <= 0.01 and _overlay_kind.is_empty()


func _advance_rotation(delta: float) -> void:
	if not _rotating():
		return
	if not _prev.is_empty():
		_prev["elapsed"] = float(_prev["elapsed"]) + delta
		if float(_prev["elapsed"]) >= float(_prev["length"]):
			_release_entry(_prev)
			_prev = {}
	if _now.is_empty():
		_gap_left -= delta
		if _gap_left <= 0.0:
			_start_piece(_pick_piece(), true)
		return
	_now["elapsed"] = float(_now["elapsed"]) + delta
	var left := float(_now["length"]) - float(_now["elapsed"])
	if left <= PIECE_FADE_OUT_SECONDS and not _next_decided:
		_next_decided = true
		var gap := _rng.randf_range(GAP_SECONDS.x, GAP_SECONDS.y) if _rng.randf() < gap_chance else 0.0
		if gap <= 0.0 and _prev.is_empty():
			# no silence this time: the next piece comes in under this one's fade
			_prev = _now
			_start_piece(_pick_piece(), true)
			return
		_gap_left = maxf(gap, 0.0)
	if left <= 0.0:
		_release_entry(_now)
		_now = {}
		piece_changed.emit("")


## A piece has faded to nothing: its player is freed (the theme's stems keep running, silent,
## for the deep mix and the next time the theme comes round).
func _release_entry(entry: Dictionary) -> void:
	var p: AudioStreamPlayer = entry.get("player")
	if p != null and p.volume_db <= SILENCE_DB + 0.01:
		_discard(p)
	elif p != null and not _outgoing.has(p):
		_outgoing.append(p)


## End the piece playing now and move on. `gap_seconds` < 0 lets the rotation decide as it
## would; 0 brings the next piece straight in; more is that long a silence first. Returns the
## piece now playing ("" during a silence). For the tests and the debug console.
func next_piece(gap_seconds := -1.0) -> String:
	if current_region_id.is_empty():
		return ""
	if not _now.is_empty():
		_release_entry(_now)
		_now = {}
	if not _prev.is_empty():
		_release_entry(_prev)
		_prev = {}
	var gap := gap_seconds
	if gap < 0.0:
		gap = _rng.randf_range(GAP_SECONDS.x, GAP_SECONDS.y) if _rng.randf() < gap_chance else 0.0
	_gap_left = gap
	if gap <= 0.0:
		_start_piece(_pick_piece(), true)
	else:
		piece_changed.emit("")
	_refresh_mode()
	return current_piece()


## The envelope a piece is under: rising over its first seconds and falling over its last.
func _envelope_db(entry: Dictionary) -> float:
	if entry.is_empty():
		return SILENCE_DB
	var elapsed := float(entry["elapsed"])
	var gain := minf(clampf(elapsed / PIECE_FADE_IN_SECONDS, 0.0, 1.0),
		clampf((float(entry["length"]) - elapsed) / PIECE_FADE_OUT_SECONDS, 0.0, 1.0))
	return maxf(linear_to_db(gain), SILENCE_DB) if gain > 0.0 else SILENCE_DB


## How far the fight has taken over, 0..1: an engaged enemy is all the way.
func _fight_share() -> float:
	return clampf(combat_intensity / ENGAGED_LEVEL, 0.0, 1.0)


## The rotation's level under a fight: an equal-power crossfade to the fight piece.
func _explore_gain_db() -> float:
	if not _has_fight():
		return 0.0
	var g := cos(_fight_share() * PI * 0.5)
	return maxf(linear_to_db(g), SILENCE_DB) if g > 0.001 else SILENCE_DB


func _has_fight() -> bool:
	return not str((_pools.get(current_region_id, {}) as Dictionary).get("combat", "")).is_empty()


## The level a rotation piece's own player should be at, before ducking.
func _entry_db(entry: Dictionary) -> float:
	if entry.is_empty() or not GameState.current_interior_id.is_empty():
		return SILENCE_DB
	var db := _envelope_db(entry) + _explore_gain_db()
	return db if db > SILENCE_DB else SILENCE_DB


## The level the fight piece should be at, before ducking. Indoors a fight is the theme's
## combat stem, as it always was.
func fight_db() -> float:
	if not _has_fight() or not GameState.current_interior_id.is_empty():
		return SILENCE_DB
	var g := sin(_fight_share() * PI * 0.5)
	return maxf(linear_to_db(g), SILENCE_DB) if g > 0.001 else SILENCE_DB


## The player carrying the fight piece, started from the top as a fight begins; null when none is.
func _update_fight() -> void:
	var want := fight_db()
	if want > SILENCE_DB and _fight_player == null:
		_fight_id = pieces_for(current_region_id, "combat")[0]
		var def: Dictionary = _piece_defs.get(_fight_id, {})
		var stream := _load_stream(str((def.get("stems", {}) as Dictionary).get("main", "")))
		if stream == null:
			return
		_fight_player = _free_piece_player()
		_fight_player.stop()
		_fight_player.stream = stream
		_fight_player.volume_db = SILENCE_DB
		_fight_player.play()
	elif want <= SILENCE_DB and _fight_player != null and _fight_player.volume_db <= SILENCE_DB + 0.01:
		_discard(_fight_player)
		_fight_player = null
		_fight_id = ""


## The player carrying the rotation piece now, or null (the theme, or a silence).
func piece_player() -> AudioStreamPlayer:
	return _now.get("player")


func fight_player() -> AudioStreamPlayer:
	return _fight_player

# --- mode ------------------------------------------------------------------------------------

## Whether it is night for the score (NIGHT_HOURS on the world clock).
func is_night() -> bool:
	var h := WorldClock.time_hours
	return h >= NIGHT_HOURS.x or h < NIGHT_HOURS.y


## Whether the deep variant applies: inside any interior, or in a dangerous region.
func is_deep() -> bool:
	if not GameState.current_interior_id.is_empty():
		return true
	var def := ContentDB.get_or_empty(current_region_id)
	return int(def.get("danger", 0)) >= DEEP_DANGER


func _refresh_mode(force := false) -> void:
	var deep := is_deep()
	var fighting := combat_intensity > 0.01
	var new_mode := "explore"
	if deep and fighting and _stems_carry_all():
		new_mode = "deep_combat"
	elif fighting:
		new_mode = "combat"
	elif deep:
		new_mode = "deep"
	elif is_night():
		new_mode = "night"
	if new_mode != mode or force:
		mode = new_mode
		mode_changed.emit(mode)
	_targets.clear()
	for stem in STEMS:
		_targets[stem] = _stem_db(stem)


func _mix_for_mode() -> Dictionary:
	match mode:
		"combat": return MIX_COMBAT
		"deep": return MIX_DEEP
		"deep_combat": return MIX_DEEP_COMBAT
		"night": return MIX_NIGHT
		_: return MIX_EXPLORE


## Indoors, and in a fight a region has no fight piece for, the theme's stems carry everything
## as they did before the rotation: the mode's mix, the combat stem riding the intensity.
func _stems_carry_all() -> bool:
	return not GameState.current_interior_id.is_empty() or (combat_intensity > 0.01 and not _has_fight())


## The theme's envelope when it is the rotation's piece (or the one fading out), else silence.
func _theme_envelope_db() -> float:
	if str(_now.get("id", "")) == current_music_id:
		return _envelope_db(_now)
	if str(_prev.get("id", "")) == current_music_id:
		return _envelope_db(_prev)
	return SILENCE_DB


## The dB a stem should currently sit at, before ducking.
func _stem_db(stem: String) -> float:
	if _stems_carry_all():
		var mix := _mix_for_mode()
		var db: float = float(mix.get(stem, SILENCE_DB))
		if stem == "combat" and db > SILENCE_DB:
			# the combat layer rides the intensity rather than snapping in
			db = lerpf(SILENCE_DB, db, clampf(combat_intensity, 0.0, 1.0))
		return db
	# Outdoors the stems are the theme, one piece of the rotation: heard in the deep mix in a
	# dangerous region, the night mix after dark, and under the fight's crossfade in a fight.
	var base := MIX_DEEP if is_deep() else (MIX_NIGHT if is_night() else MIX_EXPLORE)
	var level := float(base.get(stem, SILENCE_DB))
	var env := _theme_envelope_db()
	if level <= SILENCE_DB or env <= SILENCE_DB:
		return SILENCE_DB
	level += env + _explore_gain_db()
	return level if level > SILENCE_DB else SILENCE_DB


func _target_db(stem: String) -> float:
	return _ducked(float(_targets.get(stem, _stem_db(stem))))


func _ducked(db: float) -> float:
	return SILENCE_DB if db <= SILENCE_DB else db + _duck_db


func _process(delta: float) -> void:
	# The intensity decays towards the floor the fight sets, and the floor goes when the fight
	# does: the last enemy to die or give up lets the score back down to exploring.
	var floor_level := ENGAGED_LEVEL if engaged_count() > 0 else 0.0
	if combat_intensity > floor_level:
		combat_intensity = maxf(floor_level, combat_intensity - delta / COMBAT_DECAY_SECONDS)
	elif combat_intensity < floor_level:
		combat_intensity = floor_level
	_advance_rotation(delta)
	if not current_region_id.is_empty():
		_refresh_mode()
		_update_fight()
	var step := delta / maxf(STEM_FADE_SECONDS, 0.01) * 60.0
	for stem: String in _players:
		var p: AudioStreamPlayer = _players[stem]
		if not is_instance_valid(p):
			continue
		AudioGuard.ease_volume(p, _target_db(stem), step)
	for entry: Dictionary in [_now, _prev]:
		var p: AudioStreamPlayer = entry.get("player")
		if p != null and is_instance_valid(p):
			AudioGuard.ease_volume(p, _ducked(_entry_db(entry)), step)
	if _fight_player != null and is_instance_valid(_fight_player):
		AudioGuard.ease_volume(_fight_player, _ducked(fight_db()), step)
	# retire the previous region's stems and pieces
	var still: Array[AudioStreamPlayer] = []
	var out_step := delta / maxf(CROSSFADE_SECONDS, 0.01) * 60.0
	for p in _outgoing:
		if not is_instance_valid(p):
			continue
		AudioGuard.ease_volume(p, SILENCE_DB, out_step)
		if p.volume_db <= SILENCE_DB:
			_discard(p)
		else:
			still.append(p)
	_outgoing = still
	_update_overlay(delta)


# --- combat ----------------------------------------------------------------------------------

## Raise the combat layer. 1.0 is a full fight; it decays to nothing over COMBAT_DECAY_SECONDS.
func raise_combat(amount := COMBAT_HIT_GAIN) -> void:
	combat_intensity = clampf(combat_intensity + amount, 0.0, 1.0)
	_refresh_mode()


func clear_combat() -> void:
	combat_intensity = 0.0
	_engaged.clear()
	_refresh_mode()


func _on_enemy_engaged(enemy: Node, engaged: bool) -> void:
	if enemy == null:
		return
	if engaged:
		_engaged[enemy.get_instance_id()] = weakref(enemy)
		combat_intensity = maxf(combat_intensity, ENGAGED_LEVEL)
		_refresh_mode()
	else:
		_engaged.erase(enemy.get_instance_id())


## How many enemies are fighting now. One that has died or been freed without saying so (a cell
## unloading under it) stops counting here.
func engaged_count() -> int:
	var n := 0
	for id: int in _engaged.keys():
		var e: Object = (_engaged[id] as WeakRef).get_ref()
		if e == null or not is_instance_valid(e) or (e.has_method("is_dead") and bool(e.call("is_dead"))):
			_engaged.erase(id)
			continue
		n += 1
	return n


func _on_damage_dealt(attacker: Node, victim: Node, _amount: float, _kind: String) -> void:
	# only the player's own fight drives the music
	if _is_player(victim) or _is_player(attacker):
		raise_combat()


static func _is_player(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player")


# --- overlays: boss music and the menu theme ---------------------------------------------------

func _overlay_target_db() -> float:
	return 0.0 if _overlay_kind != "" else SILENCE_DB


func _update_overlay(delta: float) -> void:
	var step := delta / maxf(STEM_FADE_SECONDS, 0.01) * 60.0
	for i in _overlays.size():
		var p := _overlays[i]
		if not is_instance_valid(p):
			continue
		var want := _overlay_target_db() if i == _overlay_now else SILENCE_DB
		AudioGuard.ease_volume(p, want, step)
		if p.volume_db <= SILENCE_DB and p.playing and want <= SILENCE_DB:
			_discard(p)


var _missing_warned := {}


## The one file a piece played over everything else (a film's cue, a boss's track) is: its `main`
## stem. A region's bed has none -- it is five stems played together -- and the class-start films
## name their region's (`start_ranger`: core:music/briarwold), which asked for a main stem of ""
## and said "[Music] missing stream" at every start (the owner's Briar crash log, 2026-09-30). A
## bed stands for its region's first day piece (`<bed>_day_2`), which is the same theme through-
## composed, or failing that its melody stem. "" when there is nothing to play.
static func overlay_path(music_id: String) -> String:
	var def := ContentDB.get_or_empty(music_id)
	var stems: Dictionary = def.get("stems", {})
	if stems.has("main"):
		return str(stems["main"])
	if stems.is_empty():
		return ""
	var day := ContentDB.get_or_empty(music_id + "_day_2")
	var day_main := str((day.get("stems", {}) as Dictionary).get("main", ""))
	if not day_main.is_empty():
		return day_main
	return str(stems.get("melody", ""))


func _set_overlay(kind: String, music_id: String) -> void:
	if kind.is_empty():
		_overlay_kind = ""
		_overlay_id = ""
		_duck_db = 0.0
		return
	var path := overlay_path(music_id)
	var stream: AudioStream = null
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		# said once for each piece, with its name: a film or a fight goes on without its music
		if not _missing_warned.has(music_id):
			_missing_warned[music_id] = true
			Log.warn("Music", "no stream for the %s cue %s (%s); it plays without" % [
					kind, music_id, path if not path.is_empty() else "no main stem"])
		_overlay_kind = ""
		_overlay_id = ""
		return
	_overlay_id = music_id
	var current := _overlays[_overlay_now]
	if current.playing and current.stream == stream:
		_overlay_kind = kind
		_duck_db = SILENCE_DB
		return
	# The new track comes in on the other player while this one goes out: a crossfade. Stop
	# before restarting: assigning a new stream to a player that is still playing leaves the
	# old stream playback alive with nothing to stop it. Every play() in this file is preceded
	# by a stop() for that reason.
	_overlay_now = 1 - _overlay_now
	var p := _overlays[_overlay_now]
	p.stop()
	p.stream = stream
	p.volume_db = SILENCE_DB
	p.play()
	_overlay_kind = kind
	# the region bed goes away under an overlay rather than fighting it
	_duck_db = SILENCE_DB


func _on_boss_started(boss_id: String) -> void:
	_boss_id = boss_id
	_boss_intensity = 1
	_set_overlay("boss", "core:music/boss_1")


func _on_boss_phase_changed(_phase_boss_id: String, phase: int) -> void:
	set_boss_intensity(2 if phase >= 1 else 1)


## Phase changes switch the boss track to its second intensity, crossfading.
func set_boss_intensity(level: int) -> void:
	level = clampi(level, 1, 2)
	if _overlay_kind != "boss" or level == _boss_intensity:
		return
	_boss_intensity = level
	_set_overlay("boss", "core:music/boss_%d" % level)


func _on_boss_defeated(_defeated_id: String) -> void:
	_boss_id = ""     # the member, not the parameter this used to clear
	_set_overlay("", "")
	play_stinger("victory")


## A cutscene's music (`CinematicPlayer`): one through-composed piece in place of everything
## else, with the region bed held silent under it until `end_cue` lets it back. Returns whether
## the piece could be loaded; a cinematic plays on in silence rather than failing without one.
func play_cue(music_id: String) -> bool:
	if not enabled or music_id.is_empty():
		return false
	_set_overlay("cue", music_id)
	var p := _cue_player()
	if p == null:
		return false
	p.stream_paused = false
	# a cue has a first note, and fading up into it would lose it
	p.volume_db = 0.0
	return true


## Holds the cue where it is: the pictures have stopped to wait for the country to load, and the
## music has to wait with them or the two come apart.
func pause_cue(paused: bool) -> void:
	var p := _cue_player()
	if p != null:
		p.stream_paused = paused


## Lets the region bed back and fades the cue out under it.
func end_cue() -> void:
	if _overlay_kind != "cue":
		return
	var p := _cue_player()
	if p != null:
		p.stream_paused = false
	_set_overlay("", "")


func cue_playing() -> bool:
	var p := _cue_player()
	return p != null and p.playing and not p.stream_paused


## The overlay player carrying the cue, or null when no cue is up.
func _cue_player() -> AudioStreamPlayer:
	if _overlay_kind != "cue" or _overlay_now >= _overlays.size():
		return null
	var p := _overlays[_overlay_now]
	return p if is_instance_valid(p) else null


func _on_quest_stage_changed(_quest_id: String, _stage: int) -> void:
	# (A quest stage mid-boss used to stand in for a phase change; the boss says so itself now,
	# through EventBus.boss_phase_changed.)
	play_stinger("quest_update")


# --- menus -------------------------------------------------------------------------------------

## Menus that take the whole screen get the menu theme; small popups do not.
const FULLSCREEN_MENUS := ["main_menu", "inventory", "journal", "map", "skills", "settings",
		"save", "load", "character_creation", "pause"]


func _on_menu_opened(menu_id: String) -> void:
	if not _open_menus.has(menu_id):
		_open_menus.append(menu_id)
	if menu_id in FULLSCREEN_MENUS and _overlay_kind != "boss":
		if menu_id == "main_menu" or menu_id == "character_creation":
			_set_overlay("menu", "core:music/main_theme" if menu_id == "main_menu" else "core:music/naming")
		else:
			_duck_db = MENU_DUCK_DB


func _on_menu_closed(menu_id: String) -> void:
	_open_menus.erase(menu_id)
	if _open_menus.filter(func(m): return m in FULLSCREEN_MENUS).is_empty():
		if _overlay_kind == "menu":
			_set_overlay("", "")
		_duck_db = 0.0


func menus_open() -> bool:
	return not _open_menus.filter(func(m): return m in FULLSCREEN_MENUS).is_empty()


# --- stingers ------------------------------------------------------------------------------------

## Play a one-off cue over whatever is playing. Known kinds come from core:music/stingers.
func play_stinger(kind: String) -> bool:
	if not enabled or not _stingers.has(kind):
		return false
	var stream := _load_stream(str(_stingers[kind]))
	if stream == null:
		return false
	_stinger.stop()
	_stinger.stream = stream
	_stinger.volume_db = 0.0
	_stinger.play()
	return true


func _on_player_died(_position: Vector3) -> void:
	clear_combat()
	_set_overlay("", "")
	play_stinger("death")


func _on_level_up(_new_level: int) -> void:
	play_stinger("level_up")


func _on_rested(_hearthstone_id: String) -> void:
	clear_combat()
	play_stinger("rest")


func _on_echo_recovered(_marks: int) -> void:
	play_stinger("echo")


# --- events --------------------------------------------------------------------------------------

func _on_region_entered(region_id: String, previous_region_id: String) -> void:
	play_region(region_id, previous_region_id.is_empty())


func _on_interior_changed() -> void:
	_refresh_mode()


func _on_hour_changed(_hour: int) -> void:
	_refresh_mode()


# --- introspection (used by the tests and the debug console) ---------------------------------------

func stem_volume_db(stem: String) -> float:
	var p: AudioStreamPlayer = _players.get(stem)
	return p.volume_db if is_instance_valid(p) else SILENCE_DB


func playing_stems() -> Array[String]:
	var out: Array[String] = []
	for stem: String in _players:
		if float(_targets.get(stem, SILENCE_DB)) > SILENCE_DB:
			out.append(stem)
	out.sort()
	return out


func overlay_kind() -> String:
	return _overlay_kind


## The piece the overlay is playing now (a screen's theme, a boss track, a cue), or "" when there is
## none or its player has stopped.
func overlay_playing() -> String:
	if _overlay_kind.is_empty() or _overlay_now >= _overlays.size():
		return ""
	var p := _overlays[_overlay_now]
	return _overlay_id if is_instance_valid(p) and p.playing else ""


## Every music player's level now, for tests that watch a change happen: {name: dB}.
func player_levels() -> Dictionary:
	var out := {}
	for child in get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			out[str(child.name)] = (child as AudioStreamPlayer).volume_db
	return out


## A playing stream keeps its decoder alive, so everything is stopped and detached on the way
## out; otherwise Godot reports leaked Ogg playbacks at exit and the smoke run fails on them.
func release() -> void:
	# Nothing may start again after this: a frame running between the release and the
	# engine shutting down would put streams back and they would be reported as leaks.
	enabled = false
	set_process(false)
	stop_all()
	_release_players()
	_music_defs.clear()

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


func stop_all() -> void:
	_retire_current(true)
	# The stems of the region being crossfaded away are held in _outgoing, not _players, and
	# would otherwise keep playing (and keep their decoders open) after everything else stopped.
	for p in _outgoing:
		_discard(p)
	_outgoing.clear()
	_set_overlay("", "")
	for p in _overlays:
		_discard(p)
	if is_instance_valid(_stinger):
		_stinger.stop()
	for p in _piece_players:
		_discard(p)
	_last_piece = ""
	current_region_id = ""
	current_music_id = ""
	combat_intensity = 0.0
	_engaged.clear()
	_targets.clear()
