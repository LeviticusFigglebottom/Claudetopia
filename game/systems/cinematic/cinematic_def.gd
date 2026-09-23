class_name CinematicDef
extends RefCounted
## A cinematic is data, `core:cinematic/*`: shots whose cameras stand relative to named places
## and to the ground under them, with durations, time of day, weather, subtitle lines and a
## music cue. This is its validator, and the few readers the player, the capture runner and the
## tests share. DESIGN §5.1a says what the opening is for; `CinematicPlayer` plays one.
##
##   {id, name, music?, speaker?, letterbox?, dissolve?, hold_line?,
##    title_card?: {shot, at, for, title, line?},
##    handover?: {time?, weather?, facing?: {place} | {bearing}},
##    shots: [{id, duration, black?, handover?, time?, time_to?, weather?, region?, fov?, ease?,
##             dissolve?,
##             keys?: [{t, at: {place, bearing?, distance?, height} | "player_camera",
##                      look?: {place, bearing?, distance?, height?}, fov?}],
##             lines?: [{at, for, text, speaker?}]}]}
##
## `place` is a `place` or `poi` id, or "player" for wherever the player stands when control is
## handed back. `bearing` is compass degrees from that place (0 north, 90 east), `distance` is
## metres along it, and `height` is metres above whatever is under the point, ground or water.
## There is no way to write an altitude: the world builder reshapes the land, and a stored
## height is a camera inside a hill the next time it runs.

## A camera key may not be written closer to the ground than this; the test that samples every
## path asks for more, over the whole of it and not only at the keys.
const MIN_KEY_HEIGHT := 2.0
const MAX_SHOT_SECONDS := 40.0
const MAX_TOTAL_SECONDS := 180.0
## Characters a second a subtitle may ask of a reader. Seventeen is the usual ceiling for adults
## reading in their own language; there is no voice here to carry the line if the eye falls behind.
const MAX_READING_RATE := 17.0
const MIN_LINE_SECONDS := 1.0
## A line has to be off the screen this long before its shot ends. The dissolve into the next
## shot is made from a still of the last frame, and a subtitle caught in it would fade out twice.
const LINE_CLEAR_OF_CUT := 0.3
const EASES := ["in_out", "linear", "in", "out"]
const PLAYER_ANCHOR := "player"
const PLAYER_CAMERA := "player_camera"
const DEFAULT_FOV := 55.0
const DEFAULT_DISSOLVE := 1.4
const DEFAULT_LETTERBOX := 2.35


static func validate(def: Dictionary, source := "") -> Array[String]:
	var out: Array[String] = []
	var id := str(def.get("id", "?"))
	var where := "%s: %s" % [source, id] if not source.is_empty() else id
	var shots_v: Variant = def.get("shots", null)
	if not (shots_v is Array) or (shots_v as Array).is_empty():
		out.append("%s has no shots" % where)
		return out
	var shots: Array = shots_v
	_check_ref(def.get("music", null), ["music"], "%s music" % where, out)
	if def.has("letterbox") and not _num_in(def["letterbox"], 1.7, 2.8):
		out.append("%s letterbox %s is not an aspect between 1.7 and 2.8" % [where, str(def["letterbox"])])
	if def.has("dissolve") and not _num_in(def["dissolve"], 0.0, 4.0):
		out.append("%s dissolve %s is not between 0 and 4 seconds" % [where, str(def["dissolve"])])
	var ids := {}
	var total := 0.0
	var handovers := 0
	for i in shots.size():
		if not (shots[i] is Dictionary):
			out.append("%s shot %d is not an object" % [where, i])
			continue
		var shot: Dictionary = shots[i]
		var sid := str(shot.get("id", ""))
		var at := "%s shot '%s'" % [where, sid if not sid.is_empty() else str(i)]
		if sid.is_empty():
			out.append("%s has no id" % at)
		elif ids.has(sid):
			out.append("%s: two shots are called '%s'" % [where, sid])
		ids[sid] = shot
		var duration := float(shot.get("duration", 0.0)) if _is_num(shot.get("duration", null)) else -1.0
		if duration <= 0.0 or duration > MAX_SHOT_SECONDS:
			out.append("%s duration %s is not between 0 and %d seconds" % [at, str(shot.get("duration", "missing")), int(MAX_SHOT_SECONDS)])
			duration = maxf(duration, 0.0)
		total += duration
		if bool(shot.get("handover", false)):
			handovers += 1
			if i != shots.size() - 1:
				out.append("%s hands over control but is not the last shot" % at)
		for key in ["time", "time_to"]:
			if shot.has(key) and not _num_in(shot[key], 0.0, 24.0):
				out.append("%s %s %s is not an hour of the day" % [at, key, str(shot[key])])
		_check_ref(shot.get("weather", null), ["weather"], "%s weather" % at, out)
		_check_ref(shot.get("region", null), ["region"], "%s region" % at, out)
		if shot.has("fov") and not _num_in(shot["fov"], 20.0, 100.0):
			out.append("%s fov %s is outside 20..100" % [at, str(shot["fov"])])
		if shot.has("ease") and not (str(shot["ease"]) in EASES):
			out.append("%s ease '%s' is not one of %s" % [at, str(shot["ease"]), str(EASES)])
		if shot.has("dissolve") and not _num_in(shot["dissolve"], 0.0, 4.0):
			out.append("%s dissolve %s is not between 0 and 4 seconds" % [at, str(shot["dissolve"])])
		if not bool(shot.get("black", false)):
			_validate_keys(shot, at, bool(shot.get("handover", false)), out)
		elif shot.has("keys"):
			out.append("%s is black and has a camera" % at)
		_validate_lines(shot.get("lines", []), duration, at, out)
	if handovers != 1:
		out.append("%s must hand control back in exactly one shot, the last (found %d)" % [where, handovers])
	if total > MAX_TOTAL_SECONDS:
		out.append("%s runs %.0f s, longer than %d" % [where, total, int(MAX_TOTAL_SECONDS)])
	var card: Variant = def.get("title_card", null)
	if card != null:
		if not (card is Dictionary):
			out.append("%s title_card is not an object" % where)
		else:
			var c: Dictionary = card
			var shot_id := str(c.get("shot", ""))
			if not ids.has(shot_id):
				out.append("%s title_card is over shot '%s', which does not exist" % [where, shot_id])
			elif not _num_in(c.get("at", null), 0.0, 1000.0) or not _num_in(c.get("for", null), 1.0, 30.0) \
					or float(c["at"]) + float(c["for"]) > float(ids[shot_id].get("duration", 0.0)):
				out.append("%s title_card does not fit inside shot '%s'" % [where, shot_id])
			if str(c.get("title", "")).strip_edges().is_empty():
				out.append("%s title_card has no title" % where)
	var handover: Variant = def.get("handover", {})
	if handover is Dictionary:
		var h: Dictionary = handover
		if h.has("time") and not _num_in(h["time"], 0.0, 24.0):
			out.append("%s handover time %s is not an hour of the day" % [where, str(h["time"])])
		_check_ref(h.get("weather", null), ["weather"], "%s handover weather" % where, out)
		var facing: Variant = h.get("facing", null)
		if facing != null:
			if not (facing is Dictionary) or not ((facing as Dictionary).has("place") or (facing as Dictionary).has("bearing")):
				out.append("%s handover facing needs a place or a bearing" % where)
			elif (facing as Dictionary).has("place"):
				_check_place(str(facing["place"]), "%s handover facing" % where, out)
	else:
		out.append("%s handover is not an object" % where)
	return out


static func _validate_keys(shot: Dictionary, at: String, handover: bool, out: Array[String]) -> void:
	var keys_v: Variant = shot.get("keys", null)
	if not (keys_v is Array) or (keys_v as Array).size() < 2:
		out.append("%s needs at least two camera keys" % at)
		return
	var keys: Array = keys_v
	var last_t := -1.0
	for k in keys.size():
		if not (keys[k] is Dictionary):
			out.append("%s key %d is not an object" % [at, k])
			continue
		var key: Dictionary = keys[k]
		var ka := "%s key %d" % [at, k]
		if not _num_in(key.get("t", null), 0.0, 1.0):
			out.append("%s t %s is not between 0 and 1" % [ka, str(key.get("t", "missing"))])
			continue
		var t := float(key["t"])
		if k == 0 and t != 0.0:
			out.append("%s: the first key must be at t 0" % ka)
		if k == keys.size() - 1 and t != 1.0:
			out.append("%s: the last key must be at t 1" % ka)
		if t <= last_t:
			out.append("%s: keys must run forward in time" % ka)
		last_t = t
		if key.has("fov") and not _num_in(key["fov"], 20.0, 100.0):
			out.append("%s fov %s is outside 20..100" % [ka, str(key["fov"])])
		var cam: Variant = key.get("at", null)
		if cam is String and str(cam) == PLAYER_CAMERA:
			if not handover or k != keys.size() - 1:
				out.append("%s: only the last key of the hand-over shot may be the player's camera" % ka)
			continue
		if not (cam is Dictionary):
			out.append("%s has no camera position ('at')" % ka)
		else:
			_validate_point(cam, ka + " at", true, out)
		var look: Variant = key.get("look", null)
		if not (look is Dictionary):
			out.append("%s has nothing to look at" % ka)
		else:
			_validate_point(look, ka + " look", false, out)
	if handover:
		var last: Variant = keys[keys.size() - 1]
		if not (last is Dictionary) or str((last as Dictionary).get("at", "")) != PLAYER_CAMERA:
			out.append("%s hands over, so its last key must be the player's camera" % at)


static func _validate_point(p: Dictionary, at: String, camera: bool, out: Array[String]) -> void:
	var place := str(p.get("place", ""))
	if place.is_empty():
		out.append("%s is not placed relative to anywhere" % at)
	elif place != PLAYER_ANCHOR:
		_check_place(place, at, out)
	if p.has("bearing") and not _num_in(p["bearing"], -360.0, 720.0):
		out.append("%s bearing %s is not a compass bearing" % [at, str(p["bearing"])])
	if p.has("distance") and not _num_in(p["distance"], 0.0, 8000.0):
		out.append("%s distance %s is not between 0 and 8000 m" % [at, str(p["distance"])])
	if camera:
		if not _is_num(p.get("height", null)):
			out.append("%s has no height above the ground" % at)
		elif float(p["height"]) < MIN_KEY_HEIGHT:
			out.append("%s height %s is closer to the ground than %.0f m" % [at, str(p["height"]), MIN_KEY_HEIGHT])
	elif p.has("height") and not _num_in(p["height"], -50.0, 500.0):
		out.append("%s height %s is not between -50 and 500 m" % [at, str(p["height"])])


static func _validate_lines(lines_v: Variant, duration: float, at: String, out: Array[String]) -> void:
	if lines_v == null:
		return
	if not (lines_v is Array):
		out.append("%s lines is not a list" % at)
		return
	var lines: Array = lines_v
	var end := -1.0
	for l in lines.size():
		if not (lines[l] is Dictionary):
			out.append("%s line %d is not an object" % [at, l])
			continue
		var line: Dictionary = lines[l]
		var la := "%s line %d" % [at, l]
		var text := str(line.get("text", "")).strip_edges()
		if text.is_empty():
			out.append("%s has no words" % la)
		if not _is_num(line.get("at", null)) or not _is_num(line.get("for", null)):
			out.append("%s needs 'at' and 'for' in seconds" % la)
			continue
		var start := float(line["at"])
		var seconds := float(line["for"])
		if start < 0.0 or seconds < MIN_LINE_SECONDS:
			out.append("%s is on for %.1f s from %.1f s; a line needs at least %.1f s" % [la, seconds, start, MIN_LINE_SECONDS])
		if start + seconds > duration - LINE_CLEAR_OF_CUT + 0.0001:
			out.append("%s runs to %.2f s, into the cut at %.2f s (lines end %.1f s before it)" % [la, start + seconds, duration, LINE_CLEAR_OF_CUT])
		if start < end - 0.0001:
			out.append("%s starts before the line before it has gone" % la)
		end = start + seconds
		# {name} is the player's; a long name can only make the line longer, so it is read at
		# its longest believable length
		var readable := text.replace("{name}", "Maud Brambling")
		if seconds > 0.0 and float(readable.length()) / seconds > MAX_READING_RATE:
			out.append("%s asks for %.0f characters a second (at most %.0f): '%s'" % [la, float(readable.length()) / seconds, MAX_READING_RATE, text.left(40)])


static func _check_place(id: String, at: String, out: Array[String]) -> void:
	if not Ids.is_valid(id) or not (Ids.type_of(id) in ["place", "poi"]):
		out.append("%s: '%s' is not a place or a point of interest" % [at, id])


static func _check_ref(value: Variant, types: Array, at: String, out: Array[String]) -> void:
	if value == null:
		return
	var id := str(value)
	if not Ids.is_valid(id) or not (Ids.type_of(id) in types):
		out.append("%s: '%s' is not a %s id" % [at, id, "/".join(types)])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _num_in(v: Variant, low: float, high: float) -> bool:
	return _is_num(v) and float(v) >= low and float(v) <= high


# --- readers ---------------------------------------------------------------------------------

static func shots_of(def: Dictionary) -> Array:
	var v: Variant = def.get("shots", [])
	return v if v is Array else []


static func total_seconds(def: Dictionary) -> float:
	var total := 0.0
	for shot in shots_of(def):
		total += float((shot as Dictionary).get("duration", 0.0))
	return total


## Seconds from the start of the cinematic to the start of shot `index`.
static func shot_start(def: Dictionary, index: int) -> float:
	var shots := shots_of(def)
	var at := 0.0
	for i in mini(index, shots.size()):
		at += float((shots[i] as Dictionary).get("duration", 0.0))
	return at


static func handover_index(def: Dictionary) -> int:
	var shots := shots_of(def)
	for i in shots.size():
		if bool((shots[i] as Dictionary).get("handover", false)):
			return i
	return shots.size() - 1


## The dissolve into shot `index`: its own, the cinematic's, and never out of or into black.
static func dissolve_into(def: Dictionary, index: int) -> float:
	var shots := shots_of(def)
	if index <= 0 or index >= shots.size():
		return 0.0
	var shot: Dictionary = shots[index]
	var before: Dictionary = shots[index - 1]
	if bool(shot.get("black", false)) or bool(before.get("black", false)):
		return 0.0
	return float(shot.get("dissolve", def.get("dissolve", DEFAULT_DISSOLVE)))


## A line's words as the player reads them.
static func words(line: Dictionary, player_name: String) -> String:
	var name := player_name.strip_edges()
	if name.is_empty():
		name = "Foundling"
	return str(line.get("text", "")).replace("{name}", name)


## The line on screen at `seconds` into a shot, or an empty dictionary.
static func line_at(shot: Dictionary, seconds: float) -> Dictionary:
	for line in shot.get("lines", []):
		var l: Dictionary = line
		var start := float(l.get("at", 0.0))
		if seconds >= start and seconds < start + float(l.get("for", 0.0)):
			return l
	return {}
