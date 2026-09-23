class_name Guard
extends Npc
## A guard of a law faction. Patrols between its schedule spots, and when the player's bounty
## with its faction reaches the faction's `arrest_threshold` it confronts them: `confront`
## carries the options for the UI (no dialogue tree needed), and `resolve(option_id)` applies
## the outcome.
##
## Law styles (WORLD_BIBLE §4, faction law blocks):
##   fine_or_jail  pay the fine (bounty × fine_multiplier) | jail (time passes, bounty cleared)
##                 | resist (the guard turns hostile)
##   blood_price   pay twice over to the wronged clan | refuse, and the Moot remembers
##   exile         accept exile from the region's settlements | refuse
##   none          no confrontation at all (the Briarwold has arrows, not law)

signal confront(options: Array)
signal confrontation_ended(outcome: String)

const PATROL_RADIUS := 16.0
const CONFRONT_M := 6.0
const EXILE_FLAG := "exiled_from_"

@export var law_faction := ""

var confronting := false
var _patrol_index := 0
var _confront_cooldown := 0.0


func _ready() -> void:
	super()
	add_to_group("guard")
	if law_faction.is_empty():
		law_faction = str(def.get("faction", ""))
	if law_faction.is_empty():
		law_faction = WorldProbe.law_of_region(region_id())["faction_id"]


func region_id() -> String:
	var r := WorldProbe.region_of_place(place_id if not place_id.is_empty() else str(def.get("home_place", "")))
	return r if not r.is_empty() else GameState.current_region_id


func law() -> Dictionary:
	if law_faction.is_empty():
		return {"style": "none"}
	var f := ContentDB.get_or_empty(law_faction)
	var l: Dictionary = f.get("law", {}).duplicate()
	if l.is_empty():
		return {"style": "none"}
	if not l.has("style"):
		l["style"] = "fine_or_jail"
	return l


func bounty() -> int:
	var ledger := Bounty.ensure()
	return ledger.total(law_faction) if ledger != null else 0


func should_confront() -> bool:
	if confronting or hostile or not alive or _confront_cooldown > 0.0:
		return false
	var l := law()
	if not Crimes.style_is_lawful(str(l.get("style", "none"))):
		return false
	return bounty() >= int(l.get("arrest_threshold", 40))


func _physics_process(delta: float) -> void:
	super(delta)
	if _confront_cooldown > 0.0:
		_confront_cooldown = maxf(0.0, _confront_cooldown - delta)
	if confronting or not alive:
		return
	if activity == "patrol" and not has_target:
		_next_patrol_point()
	if should_confront():
		var player := Peers.player()
		if player is Node3D and global_position.distance_to((player as Node3D).global_position) <= CONFRONT_M and can_see(player as Node3D):
			begin_confrontation()


func _next_patrol_point() -> void:
	_patrol_index += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(npc_id) + _patrol_index
	var base := WorldProbe.place_position(place_id)
	var angle := rng.randf() * TAU
	var pos := base + Vector3(cos(angle), 0.0, sin(angle)) * (PATROL_RADIUS * (0.4 + rng.randf() * 0.6))
	pos.y = WorldProbe.get_height(pos.x, pos.z, base.y)
	set_move_target(pos)


# --- confrontation ---------------------------------------------------------------------------

## Halts the player: emits `confront(options)` for the UI. Options come from Crimes.
func begin_confrontation() -> Array:
	if confronting:
		return []
	confronting = true
	stop()
	play_intent("Point")
	var options := Crimes.confront_options(str(law().get("style", "none")), bounty(), law())
	EventBus.notify.emit("%s: \"Stop there. There is a matter of %d marks against your name.\"" % [display_name(), bounty()], "crime")
	confront.emit(options)
	return options


## Applies the player's choice: pay | jail | exile | resist. Returns {ok, outcome, cost, days}.
func resolve(option_id: String, player: Node = null) -> Dictionary:
	if player == null:
		player = Peers.player()
	var l := law()
	var style := str(l.get("style", "none"))
	var owed := bounty()
	var result := {"ok": false, "outcome": option_id, "cost": 0, "days": 0}
	match option_id:
		"pay":
			var due := Crimes.fine(owed, float(l.get("fine_multiplier", 1.0)))
			result["cost"] = due
			# Through the ledger, not past it. This block used to take the marks, clear the
			# bounty and count the fine itself -- a second implementation of `Bounty.pay_bounty`,
			# which had four passing tests and was called by nothing at all. Two answers to
			# "what does paying a fine do", and only one of them reachable.
			var ledger := Bounty.ensure()
			if ledger == null or not ledger.pay_bounty(law_faction, player):
				EventBus.notify.emit("You have not the marks.", "info")
				return result
			if style == "blood_price":
				EventBus.notify.emit("The price is paid. The Moot will remember that you paid it.", "crime")
			else:
				EventBus.notify.emit("Fine paid: %d marks." % due, "crime")
			result["ok"] = true
		"jail":
			var days := Crimes.jail_days(owed, float(l.get("jail_days_per_100", 1)))
			result["days"] = days
			_go_to_jail(player, days)
			result["ok"] = true
		"exile":
			_exile(player)
			result["ok"] = true
		"resist":
			become_hostile()
			result["ok"] = true
		_:
			return result
	confronting = false
	_confront_cooldown = 5.0
	confrontation_ended.emit(option_id)
	return result


func _clear_bounty() -> void:
	var ledger := Bounty.ensure()
	if ledger != null:
		ledger.clear(law_faction)


## Time passes, the bounty is cleared, and the player wakes in the jail place. Skill practice
## lost during the sentence is the progression stream's business: `arrested` tells it.
func _go_to_jail(player: Node, days: int) -> void:
	var jail_place := str(law().get("jail_place", ""))
	if jail_place.is_empty():
		jail_place = str(def.get("home_place", place_id))
	var pos := WorldProbe.place_position(jail_place)
	_put_player(player, pos)
	WorldClock.wait_until(7.0)
	if days > 1:
		WorldClock.advance_hours(24.0 * float(days - 1))
	_clear_bounty()
	GameState.inc("times_jailed")
	GameState.inc("days_jailed", days)
	EventBus.arrested.emit(law_faction)
	EventBus.notify.emit("You are let out after %d day%s. Your hands are your own again." % [days, "" if days == 1 else "s"], "crime")


## Exile: the bounty is cleared but the region's settlements are closed to the player.
func _exile(player: Node) -> void:
	var region := region_id()
	_clear_bounty()
	GameState.set_flag(EXILE_FLAG + Ids.name_of(region), true)
	GameState.inc("times_exiled")
	EventBus.arrested.emit(law_faction)
	EventBus.notify.emit("You are put off the boardwalks. Do not come back before the year turns.", "crime")
	var edge := WorldProbe.place_position(str(def.get("home_place", place_id)))
	_put_player(player, edge + Vector3(40.0, 0.0, 40.0))


## A cell or an exile is a teleport: through the body's own `teleport` (CONTRACTS §8), which
## brings the camera with it and drops the old position's interpolation.
func _put_player(player: Node, pos: Vector3) -> void:
	if player.has_method("teleport"):
		player.call("teleport", pos, (player as Node3D).rotation.y)
	elif player is Node3D:
		(player as Node3D).global_position = pos


static func is_exiled_from(region_id_: String) -> bool:
	return GameState.has_flag(EXILE_FLAG + Ids.name_of(region_id_))


## The player fights: other streams read `hostile` (and the "hostile_npc" group).
func become_hostile() -> void:
	hostile = true
	confronting = false
	add_to_group("hostile_npc")
	play_intent("Idle_Combat")
	if NpcRegistry.instance != null and not npc_id.is_empty():
		NpcRegistry.instance.set_hostile(npc_id, true)
	var ledger := Bounty.ensure()
	if ledger != null:
		ledger.add(law_faction, Crimes.SEVERITY["assault"], place_id)
	EventBus.notify.emit("\"Have it your way, then.\"", "crime")


func prompt_text() -> String:
	if confronting:
		return "%s bars your way" % display_name()
	return super()
