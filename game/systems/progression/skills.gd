class_name Skills
extends RefCounted
## The fifteen (plus Calling) use-XP skills of DESIGN §5.6.
##
## XP to go from level L to L+1 is `40 * 1.12^L` (XP_BASE * XP_GROWTH^level). Skills start at
## level 5 (BASE_LEVEL), a Calling adds +10 to three of them, and they cap at MAX_LEVEL 100.
## Awarded XP has diminishing returns with skill level: a use worth `xp` grants
## `xp * gain_multiplier(level)`, falling from 1.0 at level 5 to DIMINISH_FLOOR at 100, so late
## levels take the curve's cost *and* earn less per use.
##
## Every level gained also adds to the character's level progress; `total_gains` is the sum of
## skill levels earned since character creation, which Leveling turns into character levels.
## Pure logic: no nodes, no signals. Progression owns an instance and does the broadcasting.

const XP_BASE := 40.0
const XP_GROWTH := 1.12
const BASE_LEVEL := 5
const MAX_LEVEL := 100
const DIMINISH_FLOOR := 0.35
const SKILL_TYPE := "skill"

var levels: Dictionary = {}        # skill id -> int
var progress: Dictionary = {}      # skill id -> float XP toward the next level
var uses: Dictionary = {}          # skill id -> int (how often it was used; for the skills screen)
var total_gains: int = 0           # skill levels earned since creation (feeds Leveling)


func _init() -> void:
	reset()


func reset() -> void:
	levels.clear()
	progress.clear()
	uses.clear()
	total_gains = 0
	for id in ids():
		levels[id] = BASE_LEVEL
		progress[id] = 0.0
		uses[id] = 0


# --- definitions -------------------------------------------------------------------------

## Every skill id in the content packs, sorted.
static func ids() -> Array[String]:
	return ContentDB.ids_of(SKILL_TYPE)


static func def(skill_id: String) -> Dictionary:
	return ContentDB.get_or_empty(skill_id)


## Accepts "one_handed" or "core:skill/one_handed" and returns the full id ("" if unknown).
static func normalise(skill: String) -> String:
	if ContentDB.has(skill):
		return skill
	if not skill.contains(":"):
		for id in ids():
			if Ids.name_of(id) == skill:
				return id
	return ""


## Skills that share their XP with this one (DESIGN §5.6: Calling and Mending).
static func shared_with(skill_id: String) -> Array[String]:
	var out: Array[String] = []
	var d := def(skill_id)
	var partner := str(d.get("shares_xp_with", ""))
	if partner != "" and ContentDB.has(partner):
		out.append(partner)
	for other in ContentDB.where(SKILL_TYPE, "shares_xp_with", skill_id):
		var id: String = other["id"]
		if id != skill_id and not out.has(id):
			out.append(id)
	return out


# --- the curve ---------------------------------------------------------------------------

## XP needed to go from `level` to `level + 1`.
static func xp_for_level(at_level: int) -> float:
	return XP_BASE * pow(XP_GROWTH, float(at_level))


## Total XP to go from BASE_LEVEL to `level`.
static func xp_to_reach(at_level: int) -> float:
	var total := 0.0
	for l in range(BASE_LEVEL, at_level):
		total += xp_for_level(l)
	return total


## Diminishing returns on awarded XP, 1.0 at BASE_LEVEL down to DIMINISH_FLOOR at MAX_LEVEL.
static func gain_multiplier(at_level: int) -> float:
	var span := float(MAX_LEVEL - BASE_LEVEL)
	var t := clampf(float(at_level - BASE_LEVEL) / span, 0.0, 1.0)
	return lerpf(1.0, DIMINISH_FLOOR, t)


# --- state -------------------------------------------------------------------------------

func has(skill_id: String) -> bool:
	return levels.has(skill_id)


func level(skill: String) -> int:
	var id := normalise(skill)
	return int(levels.get(id, 0))


func xp(skill: String) -> float:
	return float(progress.get(normalise(skill), 0.0))


## 0..1 toward the next level (1.0 at the cap).
func fraction(skill: String) -> float:
	var id := normalise(skill)
	if id == "":
		return 0.0
	var l := int(levels.get(id, BASE_LEVEL))
	if l >= MAX_LEVEL:
		return 1.0
	return clampf(float(progress.get(id, 0.0)) / xp_for_level(l), 0.0, 1.0)


func use_count(skill: String) -> int:
	return int(uses.get(normalise(skill), 0))


## Sets a skill's level outright (character creation, Calling bonuses, console). Does not
## count toward `total_gains`, so a Calling does not hand out character levels.
func set_level(skill: String, new_level: int) -> void:
	var id := normalise(skill)
	if id == "":
		return
	levels[id] = clampi(new_level, 1, MAX_LEVEL)
	progress[id] = 0.0


## Applies a Calling's `skill_bonuses` ({"speech": 10, ...}) on top of the base levels.
func apply_bonuses(bonuses: Dictionary) -> void:
	for key in bonuses:
		var id := normalise(str(key))
		if id == "":
			Log.warn("Skills", "unknown skill '%s' in bonuses" % key)
			continue
		levels[id] = clampi(int(levels.get(id, BASE_LEVEL)) + int(bonuses[key]), 1, MAX_LEVEL)


## Grants XP for a use (multiplied by the learning rate and by diminishing returns) and
## returns the levels gained. Shared skills (Calling/Mending) get half the XP, without
## recursing further.
func add_xp(skill: String, amount: float, learn_rate: float = 1.0, share: bool = true) -> int:
	var id := normalise(skill)
	if id == "" or amount <= 0.0:
		return 0
	uses[id] = int(uses.get(id, 0)) + 1
	var l := int(levels.get(id, BASE_LEVEL))
	if l >= MAX_LEVEL:
		return 0
	progress[id] = float(progress.get(id, 0.0)) + amount * learn_rate * gain_multiplier(l)
	var gained := 0
	while l < MAX_LEVEL and float(progress[id]) >= xp_for_level(l):
		progress[id] = float(progress[id]) - xp_for_level(l)
		l += 1
		gained += 1
	levels[id] = l
	if l >= MAX_LEVEL:
		progress[id] = 0.0
	total_gains += gained
	if share:
		for partner in shared_with(id):
			add_xp(partner, amount * 0.5, learn_rate, false)
	return gained


## [{id, name, level, progress, xp, xp_needed, uses, group, governs, description}] for the skills screen.
func summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var d := def(id)
		var l := int(levels.get(id, BASE_LEVEL))
		out.append({
			"id": id, "name": str(d.get("name", id)), "level": l, "progress": fraction(id),
			"xp": float(progress.get(id, 0.0)), "xp_needed": xp_for_level(l), "uses": int(uses.get(id, 0)),
			"group": str(d.get("group", "")), "governs": str(d.get("governs", "")), "description": str(d.get("description", "")),
		})
	return out


func to_save() -> Dictionary:
	return {"levels": levels.duplicate(), "progress": progress.duplicate(), "uses": uses.duplicate(), "total_gains": total_gains}


func from_save(d: Dictionary) -> void:
	reset()
	var saved_levels: Dictionary = d.get("levels", {})
	for id in saved_levels:
		if levels.has(id):
			levels[id] = clampi(int(saved_levels[id]), 1, MAX_LEVEL)
	var saved_progress: Dictionary = d.get("progress", {})
	for id in saved_progress:
		if progress.has(id):
			progress[id] = float(saved_progress[id])
	var saved_uses: Dictionary = d.get("uses", {})
	for id in saved_uses:
		if uses.has(id):
			uses[id] = int(saved_uses[id])
	total_gains = int(d.get("total_gains", 0))
