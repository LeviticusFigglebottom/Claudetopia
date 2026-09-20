class_name Reactions
extends Node
## What people do when the player comes near (DESIGN §5.11, §5.12). Given the player's
## standing profile, an NPC's personality and tags, and the bounty in this region, `choose()`
## names one behaviour; the node watches NPC actors for proximity and fires it once per
## approach, emitting `reaction(npc_id, kind)` for the animation and dialogue streams and a
## line through EventBus.notify.
##
## Behaviours: greet, cheer, crowd, bow, flinch, flee, hide, follow, growl, confront, ignore.
## Tags read from the npc def: "child", "dog", "guard", "merchant".

static var instance: Reactions

signal reaction(npc_id: String, kind: String)

const NEAR_M := 9.0
const FAR_M := 14.0
const CROWD_RENOWN_TIER := 3
const CHEER_RENOWN_TIER := 2
const FEAR_MORALITY_TIER := -2
const BARRED_MORALITY_TIER := -2
const CONFRONT_BOUNTY := 15
## Renown tiers at which a crowd may gather, keyed by how many are needed nearby.
const CROWD_MIN_NEARBY := 2

var enabled := true
var _recent: Dictionary = {}   # npc_id -> true while the player is still near


static func ensure() -> Reactions:
	if instance != null and is_instance_valid(instance):
		return instance
	return Service.ensure(load("res://systems/npc_life/reactions.gd"), "Reactions") as Reactions


func _enter_tree() -> void:
	instance = self
	add_to_group("reactions")


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- the rule ------------------------------------------------------------------------------

## Chooses one behaviour for an NPC.
##   profile: Peers.reaction_profile() — {renown_tier, morality_tier, title}
##   personality: a Personality (may be null)
##   tags: the npc def's tags
##   ctx: {bounty: int, wanted: bool, nearby: int, culture: String, hostile: bool,
##         is_merchant: bool, knows_deed: bool}
static func choose(profile: Dictionary, personality: Personality, tags: Array, ctx: Dictionary = {}) -> String:
	var renown := int(profile.get("renown_tier", 0))
	var morality := int(profile.get("morality_tier", 0))
	var bounty := int(ctx.get("bounty", 0))
	var wanted := bool(ctx.get("wanted", false))
	var nearby := int(ctx.get("nearby", 0))
	var timid: bool = personality != null and personality.has("timid")
	var brave: bool = personality != null and personality.has("brave")
	var fear: float = personality.fear() if personality != null else 0.0

	if bool(ctx.get("hostile", false)):
		return "confront"
	# Dogs answer to the Hollow and to strangers with blood on them, not to renown.
	if tags.has("dog"):
		if morality <= FEAR_MORALITY_TIER or wanted:
			return "growl"
		if morality >= 2 or renown >= CHEER_RENOWN_TIER:
			return "follow"
		return "ignore"
	# Guards go by the ledger first.
	if tags.has("guard"):
		if wanted:
			return "confront"
		if bounty >= CONFRONT_BOUNTY:
			return "confront"
		if morality <= FEAR_MORALITY_TIER:
			return "watch"
		return "greet"
	# Children follow the famous and hide from the Hollow.
	if tags.has("child"):
		if morality <= FEAR_MORALITY_TIER or wanted:
			return "hide"
		if renown >= CHEER_RENOWN_TIER:
			return "follow"
		return "greet"
	# Everybody else.
	if morality <= FEAR_MORALITY_TIER or wanted:
		if brave and not wanted:
			return "confront"
		if timid or fear > 0.0 or morality <= FEAR_MORALITY_TIER - 1:
			return "flee"
		return "flinch"
	if bounty >= CONFRONT_BOUNTY and not timid:
		return "flinch"
	if renown >= CROWD_RENOWN_TIER and nearby >= CROWD_MIN_NEARBY:
		return "crowd"
	if renown >= CHEER_RENOWN_TIER:
		return "cheer"
	if renown >= 1:
		return "bow" if (personality != null and personality.has("proud")) else "greet"
	if personality != null and personality.has("quiet"):
		return "ignore"
	return "greet"


## Is this door barred against the player? Hollow villages bar their doors (DESIGN §5.11);
## a house whose owner the player is wanted by bars too.
static func door_barred(profile: Dictionary, culture: String, wanted := false) -> bool:
	var morality := int(profile.get("morality_tier", 0))
	if morality <= BARRED_MORALITY_TIER:
		return culture in ["vale", "lakefolk", "reedfolk", "clans"]
	return wanted and culture in ["vale", "lakefolk"]


## The line the world says. `title` comes from the standing profile.
static func line_for(kind: String, npc_name: String, title := "") -> String:
	var named := title if not title.is_empty() else "stranger"
	match kind:
		"greet":
			return "%s nods to you." % npc_name
		"bow":
			return "%s bows: \"%s.\"" % [npc_name, named]
		"cheer":
			return "%s calls out your name." % npc_name
		"crowd":
			return "People put down what they are carrying to look at you."
		"flinch":
			return "%s will not meet your eye." % npc_name
		"flee":
			return "%s backs away and keeps backing away." % npc_name
		"hide":
			return "A child hides behind a door and watches through the crack."
		"follow":
			return "%s trails after you at a safe and admiring distance." % npc_name
		"growl":
			return "A dog growls low and does not stop."
		"confront":
			return "%s squares up to you." % npc_name
		"watch":
			return "%s watches you the whole length of the street." % npc_name
	return ""


## The animation intent for a behaviour (CONTRACTS §3 life clips).
static func intent_for(kind: String) -> String:
	match kind:
		"greet":
			return "Wave"
		"bow":
			return "Bow_Gesture"
		"cheer", "crowd":
			return "Cheer"
		"flinch", "hide":
			return "Cower"
		"flee":
			return "Run"
		"follow":
			return "Walk"
		"confront", "watch":
			return "Point"
	return "Idle"


# --- the service ------------------------------------------------------------------------------

func bounty_here(region_id := "") -> int:
	if Bounty.ensure() == null:
		return 0
	if region_id.is_empty():
		region_id = GameState.current_region_id
	if region_id.is_empty():
		return 0
	return Bounty.ensure().total_for_region(region_id)


func wanted_here(region_id := "") -> bool:
	if Bounty.ensure() == null:
		return false
	if region_id.is_empty():
		region_id = GameState.current_region_id
	if region_id.is_empty():
		return false
	return Bounty.ensure().is_wanted(Bounty.key_for_region(region_id))


## Builds the context for one NPC actor (or npc id) and chooses its behaviour.
func choose_for(npc_id: String, nearby := 0) -> String:
	var def := ContentDB.get_or_empty(npc_id)
	var region := WorldProbe.region_of_place(str(def.get("home_place", "")))
	if region.is_empty():
		region = GameState.current_region_id
	var ctx := {
		"bounty": bounty_here(region),
		"wanted": wanted_here(region),
		"nearby": nearby,
		"culture": WorldProbe.culture_key(region),
		"hostile": NpcRegistry.instance != null and NpcRegistry.instance.is_hostile(npc_id),
		"is_merchant": def.has("merchant"),
		"knows_deed": Peers.knows_deed(str(def.get("home_place", "")), "murder"),
	}
	return choose(Peers.reaction_profile(), Personality.from_def(def), def.get("tags", []), ctx)


## Fires the behaviour for an NPC: emits `reaction`, a notify line, and tells the actor.
func react(npc_id: String, nearby := 0) -> String:
	if not enabled:
		return ""
	var kind := choose_for(npc_id, nearby)
	if kind.is_empty() or kind == "ignore":
		return kind
	var def := ContentDB.get_or_empty(npc_id)
	var profile := Peers.reaction_profile()
	var line := line_for(kind, str(def.get("name", "Someone")), str(profile.get("title", "")))
	if not line.is_empty():
		EventBus.notify.emit(line, "reaction")
	reaction.emit(npc_id, kind)
	if NpcRegistry.instance != null:
		var actor := NpcRegistry.instance.actor(npc_id)
		if actor != null and actor.has_method("play_reaction"):
			actor.call("play_reaction", kind)
	return kind


## Called by NPC actors each time the player crosses their reaction radius. Fires once per
## approach: the NPC must lose the player (FAR_M) before reacting again.
func on_player_near(npc_id: String, distance: float) -> String:
	if distance > FAR_M:
		_recent.erase(npc_id)
		return ""
	if distance > NEAR_M or _recent.has(npc_id):
		return ""
	_recent[npc_id] = true
	return react(npc_id, count_nearby(npc_id))


func count_nearby(npc_id: String) -> int:
	if NpcRegistry.instance == null:
		return 0
	var place := NpcRegistry.instance.place_of(npc_id)
	if place.is_empty():
		return 0
	return maxi(0, NpcRegistry.instance.npcs_at(place).size() - 1)


func forget(npc_id: String) -> void:
	_recent.erase(npc_id)


func forget_all() -> void:
	_recent.clear()
