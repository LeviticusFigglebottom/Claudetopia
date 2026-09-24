extends Node
## MusicDirector (autoload `Music`): decides what the score is doing and mixes the stems.
##
## A region's music is five stems started together and held in sync; what changes is how loud
## each one is. Exploration is pad + melody + texture. Fighting fades the combat stem in and
## the melody back. Deep places and interiors drop the melody for the deep stem, because that
## is where the ringing failed (WORLD_BIBLE 1.1). Night pulls the melody back and lets a little of
## the deep stem in. Menus, bosses and stingers take over on top.
##
## Nothing is ever switched: every change of state is a change of level, run over
## STEM_FADE_SECONDS, and a new track (a region, a boss, the menu theme) comes in on its own
## player while the old one goes out on another.
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

## Volume of each stem in each mode, in dB. -60 is silence.
const MIX_EXPLORE := {"pad": 0.0, "melody": 0.0, "texture": -1.0, "combat": SILENCE_DB, "deep": SILENCE_DB}
const MIX_COMBAT := {"pad": -2.0, "melody": -9.0, "texture": -4.0, "combat": 0.0, "deep": SILENCE_DB}
const MIX_DEEP := {"pad": -4.0, "melody": SILENCE_DB, "texture": -10.0, "combat": SILENCE_DB, "deep": 0.0}
const MIX_DEEP_COMBAT := {"pad": -5.0, "melody": SILENCE_DB, "texture": -9.0, "combat": -2.0, "deep": -4.0}
const MIX_NIGHT := {"pad": -3.0, "melody": -11.0, "texture": -5.0, "combat": SILENCE_DB, "deep": -14.0}

signal region_music_changed(music_id: String)
signal mode_changed(mode: String)

var combat_intensity := 0.0
var current_music_id := ""
var current_region_id := ""
var mode := "explore"                 ## explore | night | combat | deep | deep_combat
var enabled := true

## Two fixed banks of stem players, created once. A region change hands the current bank to
## _outgoing to fade away and fills the other; nothing is ever allocated or freed while the
## game runs. (Freeing a player also turned out to strand the stream playback the AudioServer
## was still holding, which showed up as a leak on every headless run.)
var _banks: Array[Dictionary] = [{}, {}]
var _bank := 0
var _players: Dictionary = {}         ## stem -> AudioStreamPlayer (current region)
var _outgoing: Array[AudioStreamPlayer] = []
var _targets: Dictionary = {}         ## stem -> target dB
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
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_index_content()
	for b in 2:
		for stem in STEMS:
			_banks[b][stem] = _make_player("Bank%d_%s" % [b, stem])
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
	for def in ContentDB.all("music"):
		if def.has("region"):
			_music_defs[str(def["region"])] = def
		if def.has("stingers"):
			_stingers = def["stingers"]
	Log.info("Music", "indexed %d region themes, %d stingers" % [_music_defs.size(), _stingers.size()])


func _make_player(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = name
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
	_refresh_mode(true)
	if instant:
		for stem: String in _players:
			(_players[stem] as AudioStreamPlayer).volume_db = _stem_db(stem)
	region_music_changed.emit(current_music_id)
	return true


func _load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		Log.warn("Music", "missing stream %s" % path)
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


## Finish with a player: stop it and drop its stream. The node itself stays, to be used again
## by the next region -- see the note on _banks.
func _discard(p: AudioStreamPlayer) -> void:
	if not is_instance_valid(p):
		return
	p.stop()
	p.stream = null


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
	if deep and fighting:
		new_mode = "deep_combat"
	elif deep:
		new_mode = "deep"
	elif fighting:
		new_mode = "combat"
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


## The dB a stem should currently sit at, before ducking.
func _stem_db(stem: String) -> float:
	var mix := _mix_for_mode()
	var db: float = float(mix.get(stem, SILENCE_DB))
	if stem == "combat" and db > SILENCE_DB:
		# the combat layer rides the intensity rather than snapping in
		db = lerpf(SILENCE_DB, db, clampf(combat_intensity, 0.0, 1.0))
	return db


func _target_db(stem: String) -> float:
	var db := float(_targets.get(stem, _stem_db(stem)))
	if db <= SILENCE_DB:
		return SILENCE_DB
	return db + _duck_db


func _process(delta: float) -> void:
	# The intensity decays towards the floor the fight sets, and the floor goes when the fight
	# does: the last enemy to die or give up lets the score back down to exploring.
	var floor_level := ENGAGED_LEVEL if engaged_count() > 0 else 0.0
	if combat_intensity > floor_level:
		combat_intensity = maxf(floor_level, combat_intensity - delta / COMBAT_DECAY_SECONDS)
	elif combat_intensity < floor_level:
		combat_intensity = floor_level
	if combat_intensity > 0.0 or not _targets.is_empty():
		_refresh_mode()
	var step := delta / maxf(STEM_FADE_SECONDS, 0.01) * 60.0
	for stem: String in _players:
		var p: AudioStreamPlayer = _players[stem]
		if not is_instance_valid(p):
			continue
		AudioGuard.ease_volume(p, _target_db(stem), step)
	# retire the previous region's stems
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


func _set_overlay(kind: String, music_id: String) -> void:
	if kind.is_empty():
		_overlay_kind = ""
		_overlay_id = ""
		_duck_db = 0.0
		return
	var def := ContentDB.get_or_empty(music_id)
	var stems: Dictionary = def.get("stems", {})
	var stream := _load_stream(str(stems.get("main", "")))
	if stream == null:
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


func _on_boss_phase_changed(_boss_id: String, phase: int) -> void:
	set_boss_intensity(2 if phase >= 1 else 1)


## Phase changes switch the boss track to its second intensity, crossfading.
func set_boss_intensity(level: int) -> void:
	level = clampi(level, 1, 2)
	if _overlay_kind != "boss" or level == _boss_intensity:
		return
	_boss_intensity = level
	_set_overlay("boss", "core:music/boss_%d" % level)


func _on_boss_defeated(_boss_id: String) -> void:
	_boss_id = ""
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
	current_region_id = ""
	current_music_id = ""
	combat_intensity = 0.0
	_engaged.clear()
	_targets.clear()
