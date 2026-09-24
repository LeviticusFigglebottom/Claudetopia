class_name Impact
extends RefCounted
## How a blow lands, for the eye and the ear: none of it changes a number or a timing.
##
## Actor.take_hit calls `land` for every blow that lands, is blocked or is parried, and this:
##   * holds both bodies' pictures still for a few frames (HumanoidModel.hit_stop), longer for a
##     heavier weapon and a heavy attack. The AnimationDriver keeps every §5.3 timing on the
##     physics clock; the picture falls a few frames behind and catches up (DECISIONS);
##   * kicks the camera when the player struck or was struck (CameraRig.shake);
##   * throws what the blow knocks off what it hit (ImpactFx): sparks off metal and a guard, dust
##     and chips off stone, splinters off wood, a little blood off flesh and a stain under it;
##   * lays the weapon's sound over the material's: the shear of an edge biting, and the low
##     weight of a heavy blow arriving.
## `trail` puts a streak behind a heavy swing's blade while its blow is live.
##
## The player's settings: accessibility.hit_pause (the hold), accessibility.camera_shake (the
## kick's strength, 0 none), accessibility.reduce_flashing (fewer, dimmer sparks) and
## gameplay.blood.

## The hold at the lightest and the heaviest blow (s): two frames and seven at 60 Hz.
const STOP_LIGHT_S := 0.035
const STOP_HEAVY_S := 0.115
## A guard that takes the blow holds for this share of it; a parry holds this long.
const STOP_BLOCKED_SHARE := 0.6
const STOP_PARRY_S := 0.1
## The camera's kick when the player lands a blow, as a share of when the player takes one.
const KICK_LANDED_SHARE := 0.7
## At this force and above a blow's own weight is heard under the material (impact_weight).
const WEIGHT_HEARD_FROM := 0.55
## What a weapon class weighs (kg) when no item says: the enemies swing classes, not items.
const CLASS_WEIGHT := {
	"dagger": 1.0, "knife": 0.8, "rapier": 1.5, "sword": 3.0, "axe": 3.5, "mace": 4.0, "club": 3.5,
	"spear": 4.0, "staff": 2.0, "scythe": 5.0, "hammer": 7.0, "greathammer": 9.0, "greatsword": 7.0,
	"greataxe": 7.5, "maul": 8.0, "unarmed": 0.6, "claw": 2.0, "bite": 2.5, "tusk": 6.0,
}
## Kinds of damage an edge does: they bite before they thud.
const EDGED := ["slash", "pierce"]

## The longest a blow's picture waits for the blade to reach the body (s).
const MOST_WAIT_S := 0.2

## The last blow shown, for tests and the debug console: {force, stop, point, material, result}.
static var last: Dictionary = {}


## How hard a blow lands, 0..1: the weapon's weight, more for a heavy attack or a crit.
static func force_of(hit: HitData) -> float:
	var w := hit.weight if hit.weight > 0.0 else weight_of_class(hit.weapon_class)
	var f := 0.2 + 0.8 * clampf((w - 0.8) / 8.2, 0.0, 1.0)
	if hit.heavy:
		f = f * 1.3 + 0.1
	if hit.is_crit():
		f += 0.2
	return clampf(f, 0.0, 1.0)


static func weight_of_class(weapon_class: String) -> float:
	return float(CLASS_WEIGHT.get(weapon_class, 2.0))


## Seconds a blow holds the picture: longer the harder it lands; a guard's share when blocked.
static func stop_seconds(force: float, result: String) -> float:
	if result == "parried":
		return STOP_PARRY_S
	var s := lerpf(STOP_LIGHT_S, STOP_HEAVY_S, clampf(force, 0.0, 1.0))
	return s * STOP_BLOCKED_SHARE if result == "blocked" else s


## Metres a blow drives the body it lands on back: only a heavy attack, and more the heavier the
## weapon; a dagger or a fist drives nothing.
static func knockback_for(weight: float, heavy: bool, clips_set: String) -> float:
	if not heavy or clips_set in ["dagger", "unarmed", "bow", "staff"]:
		return 0.0
	if clips_set == "2H":
		return clampf(0.3 + weight * 0.055, 0.3, 0.85)
	return clampf(0.16 + weight * 0.05, 0.16, 0.45)


## Where on `victim` the blow met it: on its body's surface, where the attacker's blade (when it
## holds one) passes nearest its middle, else at chest height on the side the blow came from.
static func contact_point(victim: Node3D, hit: HitData) -> Vector3:
	var h := float(victim.get("capsule_height")) if victim.get("capsule_height") != null else 1.8
	var r := float(victim.get("capsule_radius")) if victim.get("capsule_radius") != null else 0.35
	var base := victim.global_position
	var foot := base + Vector3.UP * r
	var crown := base + Vector3.UP * maxf(h - r * 0.5, r)
	var toward := hit.origin - base
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.0001 else -victim.global_transform.basis.z
	var blade := blade_of(hit.attacker)
	if not blade.is_empty():
		var pts := Geometry3D.get_closest_points_between_segments(blade[0], blade[1], foot, crown)
		var on_axis: Vector3 = pts[1]
		var out: Vector3 = (pts[0] as Vector3) - on_axis
		out.y = 0.0
		out = out.normalized() if out.length_squared() > 0.0001 else toward
		return on_axis + out * r * 0.85
	return base + Vector3.UP * h * 0.6 + toward * r * 0.85


## The blade `actor` holds in its right hand (or left, for a bow): [grip, tip] in the world, or [].
static func blade_of(actor: Node) -> Array:
	var node := held_weapon(actor)
	if node == null:
		return []
	var length := WeaponTrail.blade_length(node)
	if length <= 0.05:
		return []
	var xf := node.global_transform
	return [xf.origin, xf.origin + xf.basis.y.normalized() * length]


## The weapon model in `actor`'s hand (HeldItems), or null.
static func held_weapon(actor: Node) -> Node3D:
	var body := body_of(actor)
	if body == null or not body.has_method("socket"):
		return null
	for socket in ["WeaponR", "WeaponL"]:
		var s: Node = body.call("socket", socket)
		if s == null:
			continue
		for c in s.get_children():
			# a HeldItems weapon, or the forge prop a foe's def puts in its hand (EnemyDress.hold, "Held")
			if (c.has_meta(HeldItems.TAG) or str(c.name) == "Held") and c is Node3D and not c.is_queued_for_deletion():
				return c as Node3D
	return null


static func body_of(actor: Node) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	var driver: Variant = actor.get("anim")
	if driver is AnimationDriver and (driver as AnimationDriver).model != null:
		return (driver as AnimationDriver).model
	if actor.has_method("_body_model"):
		return actor.call("_body_model")
	return null


## Which way a blow from `to_origin` (the attacker less the body, world space) comes at a body
## facing `forward`: "" from in front (within 45 degrees), "B" from behind, "L" or "R" from a side.
static func way_of(forward: Vector3, to_origin: Vector3) -> String:
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var o := Vector3(to_origin.x, 0.0, to_origin.z)
	if o.length_squared() < 0.0001 or f.length_squared() < 0.0001:
		return ""
	o = o.normalized()
	var ahead := f.dot(o)
	if ahead >= cos(deg_to_rad(45.0)):
		return ""
	if ahead <= -cos(deg_to_rad(45.0)):
		return "B"
	# the body's left is up x forward
	return "L" if Vector3.UP.cross(f).dot(o) > 0.0 else "R"


## A blow `victim` took: "hit", "blocked" or "parried". The blow is scored on the hitbox's frame
## (the §5.3 hit window, a swing volume), which can open while the blade in the picture is still
## over the attacker's head. So what is seen and heard waits for the picture: while the attacker's
## blade is still on its way (Contact), and at most MOST_WAIT_S, then all of it at once where the
## blade meets the body. A blow with no blade to watch (a fist, a claw, a spell, a test's bare
## HitData) shows at once.
static func land(victim: Node3D, hit: HitData, result: String) -> void:
	if victim == null or hit == null or not victim.is_inside_tree():
		return
	var push := victim.global_position - hit.origin
	push.y = 0.0
	push = push.normalized() if push.length_squared() > 0.0001 else victim.global_transform.basis.z
	var blow := {"victim": victim, "attacker": hit.attacker, "force": force_of(hit), "result": result,
			"push": push, "kind": hit.kind, "sound": result == "hit"}
	var material := str(victim.get("body_material")) if victim.get("body_material") != null else "flesh"
	blow["material"] = material if result == "hit" else _guard_material(victim)
	if not blade_of(hit.attacker).is_empty():
		var c := Contact.new()
		c.blow = blow
		c.name = "ImpactContact"
		victim.add_child(c)
		# the struck body's picture waits for the blade too, so its flinch (begun now, on the
		# timeline) is seen to start where the blade meets it; with the hold turned off, the flinch
		# starts at once
		var struck := body_of(victim)
		if struck != null and struck.has_method("hit_stop") and bool(Settings.get_value("accessibility", "hit_pause", true)):
			struck.call("hit_stop", MOST_WAIT_S)
		return
	show(blow, contact_point(victim, hit))


## Everything a blow is seen and heard to do, at `point`: the hold, the kick, the bits, the sound.
static func show(blow: Dictionary, point: Vector3) -> void:
	var victim: Node3D = blow["victim"]
	if victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return
	var attacker: Node = blow["attacker"] if is_instance_valid(blow["attacker"]) else null
	var force := float(blow["force"])
	var result := str(blow["result"])
	var push: Vector3 = blow["push"]
	var material := str(blow["material"])
	# a dressed foe is struck where the blade meets it: plate on the chest, flesh at the legs
	if result == "hit" and victim.has_method("material_at"):
		material = str(victim.call("material_at", point))
	var stop := 0.0
	if bool(Settings.get_value("accessibility", "hit_pause", true)):
		stop = stop_seconds(force, result)
	for who: Node in [victim, attacker]:
		var body := body_of(who)
		if body != null and body.has_method("hit_stop"):
			# the struck body's wait for the blade ends here, and the blow's own hold begins
			body.call("hit_stop", stop, who == victim)
	var player := Peers.player()
	if player != null and player.get("camera_rig") != null:
		var rig: Node = player.get("camera_rig")
		if victim == player:
			rig.call("shake", force, push)
		elif attacker == player:
			rig.call("shake", force * KICK_LANDED_SHARE, push)
	if bool(blow.get("sound", false)):
		# the blow on whatever the body is made of: flesh, mail, stone or wood, and over it the
		# weapon's own layers
		Foley.play("impact_" + material, point)
		if EDGED.has(str(blow["kind"])) and material == "flesh":
			Foley.play("impact_edge", point)
		if force >= WEIGHT_HEARD_FROM:
			Foley.play("impact_weight", point, lerpf(-8.0, 0.0, (force - WEIGHT_HEARD_FROM) / (1.0 - WEIGHT_HEARD_FROM)))
	ImpactFx.burst(victim, material, point, push, force, result)
	# how far the blade in the picture was from the body's middle when the blow was shown
	var gap := -1.0
	var blade := blade_of(attacker)
	if not blade.is_empty():
		var h := float(victim.get("capsule_height")) if victim.get("capsule_height") != null else 1.8
		var pts := Geometry3D.get_closest_points_between_segments(blade[0], blade[1],
				victim.global_position + Vector3.UP * 0.3, victim.global_position + Vector3.UP * h * 0.9)
		gap = (pts[0] as Vector3).distance_to(pts[1])
	last = {"force": force, "stop": stop, "point": point, "material": material, "result": result,
			"victim": victim.name, "push": push, "shown_at": Engine.get_process_frames(), "blade_gap": gap}


## Waits for the attacker's blade in the picture to reach the struck body, then shows the blow
## there: when the blade comes within the body's radius of its middle, or has passed its nearest
## and is going away, or MOST_WAIT_S has gone by.
class Contact extends Node:
	var blow: Dictionary = {}
	var _t := 0.0
	var _best := INF
	var _best_point := Vector3.ZERO
	var _rising := 0
	var _last := INF

	func _process(delta: float) -> void:
		_t += delta
		var victim := get_parent() as Node3D
		var attacker: Node = blow.get("attacker")
		if victim == null or attacker == null or not is_instance_valid(attacker):
			queue_free()
			return
		var blade := Impact.blade_of(attacker)
		var r := float(victim.get("capsule_radius")) if victim.get("capsule_radius") != null else 0.35
		var h := float(victim.get("capsule_height")) if victim.get("capsule_height") != null else 1.8
		var foot := victim.global_position + Vector3.UP * r
		var crown := victim.global_position + Vector3.UP * maxf(h - r * 0.5, r)
		var met := false
		if not blade.is_empty():
			var pts := Geometry3D.get_closest_points_between_segments(blade[0], blade[1], foot, crown)
			var d := (pts[0] as Vector3).distance_to(pts[1])
			var out: Vector3 = (pts[0] as Vector3) - (pts[1] as Vector3)
			out.y = 0.0
			out = out.normalized() if out.length_squared() > 0.0001 else -(blow["push"] as Vector3)
			var at: Vector3 = (pts[1] as Vector3) + out * r * 0.85
			if d < _best - 0.002:
				_best = d
				_best_point = at
				_rising = 0
			else:
				_rising += 1
			# a heavy blade covers a third of a metre a frame: shown when the next frame would
			# put it into the body, so the hold is on the blade at the body, not buried in it
			var closing := maxf(_last - d, 0.0) if _last < INF else 0.0
			_last = d
			met = d - closing <= r * 1.1 or (_rising >= 2 and _best < r * 3.0)
		if met or _t >= Impact.MOST_WAIT_S or blade.is_empty():
			Impact.show(blow, _best_point if _best < INF else victim.global_position + Vector3.UP * h * 0.6)
			queue_free()


## What a guard is made of where a blow meets it: a wooden shield's boards, else steel.
static func _guard_material(victim: Node) -> String:
	var body := body_of(victim)
	if body != null:
		var shield := str(HeldItems.held_by(body).get("ShieldL", ""))
		if not shield.is_empty():
			var model := HeldItems.model_for(ContentDB.get_or_empty(shield))
			if model.ends_with("_wood"):
				return "wood"
	return "metal"


## Starts (or lets fade) the streak behind the blade `actor` holds.
static func trail(actor: Node, on: bool) -> void:
	var node := held_weapon(actor)
	if node == null:
		return
	var t := node.get_node_or_null("Trail") as WeaponTrail
	if t == null:
		if not on:
			return
		t = WeaponTrail.new()
		t.name = "Trail"
		node.add_child(t)
	t.active = on
