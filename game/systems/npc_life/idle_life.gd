class_name IdleLife
extends RefCounted
## What somebody does with themselves while their hour keeps them in one place. A person at their
## spot used to play one clip, the activity's, from arriving until the hour moved them on: the smith
## hammered, the gossip said Talk_1 to the empty air and the idle stood square, each for a whole game
## hour without a pause, a turn of the head or a step, and every one of them in step with the rest
## (playtest 2026-09-27, 18). This is the rhythm laid over that clip, in beats: the work in bouts
## with a breather between, talk in turns with listening and a laugh, standing broken by a look
## round, a look at whoever is near, a few steps and back, a reach across the counter. The timings
## are this person's own (a seeded RandomNumberGenerator), so no two keep time together.
##
## Pure: `next_beat` says what comes next and the Npc does it. A beat is
## {clip, hold (s), look: "" | "around" | "person" | "home", wander (m, 0 stays), tempo}.

## Looping clips played in bouts, broken by a breather.
const BOUT_CLIPS: Array[String] = ["Work_Hammer", "Work_Chop", "Work_Stir", "Work_Dig", "Read"]
const TALK_CLIPS: Array[String] = ["Talk_1", "Talk_2"]
## Lain or sat in: left to go round, only looked at again now and then.
const STILL_CLIPS: Array[String] = ["Sleep_Idle", "Sit_Idle"]
## One-shots a beat may be, with the length each is played for (the clips' own, a little over).
const ONE_SHOT_S := {"Eat": 2.2, "Drink": 2.1, "Laugh": 2.0, "Point": 1.6, "Interact": 1.0}
## How far from their spot somebody wanders in a beat.
const WANDER_M := 2.6

var rng := RandomNumberGenerator.new()
## This person's pace at their work, the clip's speed: 0.88 to 1.12.
var tempo := 1.0
var _at_it := false
var _talk := 0


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	tempo = rng.randf_range(0.88, 1.12)
	_talk = rng.randi() % 2
	_at_it = rng.randf() < 0.5


static func is_one_shot(clip: String) -> bool:
	return ONE_SHOT_S.has(clip)


## The beat after the last, for somebody whose activity plays `clip` (Schedules.intent_for).
func next_beat(activity: String, clip: String) -> Dictionary:
	if clip in STILL_CLIPS:
		return _beat(clip, rng.randf_range(15.0, 30.0))
	if clip in TALK_CLIPS or activity == "socialise":
		return _talk_beat()
	if clip in BOUT_CLIPS:
		return _bout_beat(clip)
	if is_one_shot(clip):
		return _hands_beat(clip)
	# standing about, keeping a stall, waiting at a post, or on the road and there early
	return _idle_beat(activity in ["shop", "work"])


func _beat(clip: String, hold: float, look := "", wander := 0.0) -> Dictionary:
	if is_one_shot(clip):
		hold = maxf(hold, float(ONE_SHOT_S[clip]))
	return {"clip": clip, "hold": hold, "look": look, "wander": wander, "tempo": tempo}


## Work in bouts: at it for six to fifteen seconds (reading, longer), then a breather of a few,
## which is a look round, a step away and back, or a drink.
func _bout_beat(clip: String) -> Dictionary:
	_at_it = not _at_it
	if _at_it:
		var hold := rng.randf_range(12.0, 24.0) if clip == "Read" else rng.randf_range(6.0, 15.0)
		return _beat(clip, hold, "home")
	var r := rng.randf()
	if r < 0.12:
		return _beat("Drink", 0.0, "around")
	if r < 0.32:
		return _beat("Idle", rng.randf_range(2.0, 4.0), "", rng.randf_range(0.8, 1.6))
	return _beat("Idle", rng.randf_range(2.0, 5.0), "around" if r < 0.8 else "person")


## Work done with the hands in short goes (a reach, a pick), with a moment between.
func _hands_beat(clip: String) -> Dictionary:
	_at_it = not _at_it
	if _at_it:
		return _beat(clip, float(ONE_SHOT_S[clip]) + rng.randf_range(0.0, 0.6), "home")
	if clip == "Eat" and rng.randf() < 0.3:
		return _beat("Drink", 0.0)
	return _beat("Idle", rng.randf_range(1.2, 4.0), "around" if rng.randf() < 0.3 else "")


## Talk in turns: a say (either talking clip, three to seven seconds) and a listen (standing, turned
## to them), and now and then a laugh or a point in place of the listening.
func _talk_beat() -> Dictionary:
	_at_it = not _at_it
	if _at_it:
		_talk = (_talk + 1 + (1 if rng.randf() < 0.3 else 0)) % TALK_CLIPS.size()
		return _beat(TALK_CLIPS[_talk], rng.randf_range(3.0, 7.0), "person")
	var r := rng.randf()
	if r < 0.15:
		return _beat("Laugh", 0.0, "person")
	if r < 0.2:
		return _beat("Point", 0.0, "around")
	return _beat("Idle", rng.randf_range(2.0, 5.0), "person")


## Standing about: three to nine seconds at a time, each ended by a look round, a look at somebody,
## a few steps and back, or (keeping a stall) a reach across it.
func _idle_beat(keeping: bool) -> Dictionary:
	var hold := rng.randf_range(3.0, 9.0)
	var r := rng.randf()
	if keeping and r < 0.2:
		return _beat("Interact", 0.0, "home")
	if r < 0.45:
		return _beat("Idle", hold, "around")
	if r < 0.65:
		return _beat("Idle", hold, "person")
	if r < 0.82 and not keeping:
		return _beat("Idle", hold, "", rng.randf_range(1.0, WANDER_M))
	return _beat("Idle", hold, "home" if r < 0.92 else "")
