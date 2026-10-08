class_name QuestNoticeQueue
extends RefCounted
## The order and the timing of the quest notices (QuestNotice draws them), kept apart from the
## drawing so the tests can drive it second by second.
##
## The owner: "almost every starter quest progresses from point-to-point with no clear reason why,
## or the bit that pops up is small and disappears". So a notice is held long enough to be read
## (scaled to its words, 6-10 s at full ink, Settings gameplay/quest_notice_time on top), several
## wait their turn instead of writing over each other, and none is spent while a conversation, a
## film, a full-screen menu or the loading screen has the screen (`blocked`): it waits, and one
## taken down by them comes back in full after.
##
## A notice is {quest, kind ("started" | "updated" | "complete"), name, objective, why, tier}.
## A newer notice of the same quest takes the place of its older ones still waiting, and of the
## one up now if that has been up less than SUPERSEDE_S: a stage that lasted a moment (a quest
## taken and moved on by the same answer) is not worth reading, and its objective is already
## stale. A start so taken over keeps saying "Quest started"; a completion is always one.

## Ink in and out (s).
const FADE_IN_S := 0.45
const FADE_OUT_S := 1.1
## Full ink, before the setting's scale: 2.5 s and a little for every letter, inside these.
const MIN_HOLD_S := 6.0
const MAX_HOLD_S := 10.0
const BASE_S := 2.5
const PER_CHAR_S := 0.045
## A notice up for less than this gives way to its own quest's next one.
const SUPERSEDE_S := 1.5
## After whatever blocked the screen lets go, before the next notice comes up; and between two.
const SETTLE_S := 0.6
const GAP_S := 0.35
## Waiting notices kept at most; past it the oldest go (they are in the journal).
const MAX_PENDING := 6

## Settings gameplay/quest_notice_time: 0.75 shorter, 1.0, 1.5 longer.
var hold_scale := 1.0

var _pending: Array[Dictionary] = []
var _current: Dictionary = {}
var _age := 0.0
var _hold := 0.0
## How long the screen must be clear before the next notice comes up, and how long it has been.
var _wait := 0.0
var _clear := 0.0


## Seconds at full ink for a notice with these words, at `scale`.
static func hold_seconds(objective: String, why: String, scale := 1.0) -> float:
	var letters := objective.length() + why.length()
	return clampf(BASE_S + PER_CHAR_S * letters, MIN_HOLD_S, MAX_HOLD_S) * maxf(scale, 0.1)


## Puts a notice in line. Returns true when it took the place of the one up now (to be redrawn).
func push(n: Dictionary) -> bool:
	var note := n.duplicate()
	var quest := str(note.get("quest", ""))
	var was_start := false
	for i in range(_pending.size() - 1, -1, -1):
		if str(_pending[i].get("quest", "")) == quest and quest != "":
			was_start = was_start or str(_pending[i].get("kind", "")) == "started"
			_pending.remove_at(i)
	var replaces_current := not _current.is_empty() and quest != "" \
			and str(_current.get("quest", "")) == quest and _age < SUPERSEDE_S
	if replaces_current:
		was_start = was_start or str(_current.get("kind", "")) == "started"
	if was_start and str(note.get("kind", "")) == "updated":
		note["kind"] = "started"
	if replaces_current:
		_current = note
		_hold = hold_seconds(str(note.get("objective", "")), str(note.get("why", "")), hold_scale)
		# it keeps inking in from where it was, and gets its whole time at full ink
		_age = minf(_age, FADE_IN_S)
		return true
	_pending.append(note)
	while _pending.size() > MAX_PENDING:
		_pending.pop_front()
	return false


## Moves the clock on `dt` seconds. `blocked`: a conversation, a film, a full menu or the loading
## screen has the screen. Returns true when a notice came up (or went back) this step.
## `clear_dt`: the frame's own time for the wait before a notice comes up (the read itself is timed
## on `dt`, which the caller caps so one long frame does not eat it): on a slow machine the capped
## step made the 0.6 s settle after a film take a dozen seconds. Below zero, `dt` serves for both.
func step(dt: float, blocked: bool, clear_dt := -1.0) -> bool:
	if blocked:
		_clear = 0.0
		_wait = SETTLE_S
		if not _current.is_empty():
			# taken down unread (or half read): shown again in full once the screen is clear
			_pending.push_front(_current)
			_current = {}
			_age = 0.0
			return true
		return false
	_clear += clear_dt if clear_dt >= 0.0 else dt
	if _current.is_empty():
		if _pending.is_empty() or _clear < _wait:
			return false
		_current = _pending.pop_front()
		_age = 0.0
		_hold = hold_seconds(str(_current.get("objective", "")), str(_current.get("why", "")), hold_scale)
		return true
	_age += dt
	if _age >= total_seconds():
		_current = {}
		_age = 0.0
		_clear = 0.0
		_wait = GAP_S
		return true
	return false


## The notice up now, {} when none.
func current() -> Dictionary:
	return _current


## Those waiting their turn, in order.
func pending() -> Array[Dictionary]:
	return _pending


func is_empty() -> bool:
	return _current.is_empty() and _pending.is_empty()


## How long the one up now is on the screen in all: in, held, out.
func total_seconds() -> float:
	return FADE_IN_S + _hold + FADE_OUT_S


## Seconds at full ink of the one up now.
func held_seconds() -> float:
	return _hold


## How much ink the one up now has, 0-1.
func alpha() -> float:
	if _current.is_empty():
		return 0.0
	if _age < FADE_IN_S:
		return clampf(_age / FADE_IN_S, 0.0, 1.0)
	var out_at := FADE_IN_S + _hold
	if _age <= out_at:
		return 1.0
	return clampf(1.0 - (_age - out_at) / FADE_OUT_S, 0.0, 1.0)


## Seconds the one up now has been up.
func age() -> float:
	return _age


## Drops everything (a new game, a load).
func clear() -> void:
	_pending.clear()
	_current = {}
	_age = 0.0
