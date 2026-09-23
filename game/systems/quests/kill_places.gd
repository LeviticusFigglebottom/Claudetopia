class_name KillPlaces
extends RefCounted
## Where a kill happened, for a kill objective that says where.
##
## A kill objective counted a kill of its kind anywhere in the world. The Undercroft's strongroom
## stage asks for the Guild's two bravos in the room behind the bell, and it closed on the two
## bravos who work the toll queue at the Long Stride; the crawl behind the bell asks for gutter
## drakes, and closed at the Gullhithe Wreck, a day's sail away. Every other stage that sends you
## somewhere to fight — twenty-two more — would have closed on the same kind of foe met on any road.
##
## An objective now says where the story puts the fight:
##
##   "where":  an interior (`core:interior/undercroft`: the kill is inside it), or a place or a
##             point of interest (in the open, within `radius` metres of it, 140 by default)
##   "region": a region, for a job board's hunt ("on the Hearthvale roads"): in the open there, or
##             in a deep place whose place is there
##
## and only a kill there counts. Where is read off the body that died: the interior whose tree it
## lies in, or the ground it lies on. A victim with no body to ask (a scripted kill, a test) is
## answered by the killer, and then by the player: where they stand and the interior they are in.

const RADIUS_M := 140.0
## Written out, for an objective that means it: a stage that sends you somewhere and does not mind
## where the fight is.
const ANYWHERE := "anywhere"


## The interior a node stands in, or "" in the open: the pocket an interior is loaded into carries
## its id (`Interiors._load`).
static func interior_of(node: Node) -> String:
	var n: Node = node
	while n != null:
		if n.has_meta("interior_id"):
			return str(n.get_meta("interior_id"))
		n = n.get_parent()
	return ""


## Whether this objective cares where: `where` or `region`, and not `anywhere`.
static func is_bound(objective: Dictionary) -> bool:
	var where := str(objective.get("where", ""))
	return (where != "" and where != ANYWHERE) or str(objective.get("region", "")) != ""


## The body to ask: the victim, else the killer; null when neither is a body in the world.
static func _witness(victim: Node, killer: Node) -> Node3D:
	for n in [victim, killer]:
		if is_instance_valid(n) and n is Node3D and (n as Node).is_inside_tree():
			return n as Node3D
	return null


## Whether a kill counts for `objective`. `player_at` (Vector3.INF when nobody can say) and
## `player_interior` answer for a kill with no body to ask.
static func counts(objective: Dictionary, victim: Node, killer: Node,
		player_at: Vector3 = Vector3.INF, player_interior: String = "") -> bool:
	if not is_bound(objective):
		return true
	var witness := _witness(victim, killer)
	var interior := interior_of(witness) if witness != null else player_interior
	var at: Vector3 = witness.global_position if witness != null else player_at
	var where := str(objective.get("where", ""))
	if where != "" and where != ANYWHERE and not _is_at(where, interior, at, float(objective.get("radius", RADIUS_M))):
		return false
	var region := str(objective.get("region", ""))
	if region != "" and not _is_in_region(region, interior, at):
		return false
	return true


static func _is_at(where: String, interior: String, at: Vector3, radius: float) -> bool:
	if Ids.type_of(where) == "interior":
		return interior == where
	# a place or a point of interest: in the open, near it
	if interior != "" or at == Vector3.INF:
		return false
	var p: Array = ContentDB.get_or_empty(where).get("position", [])
	if p.size() < 2:
		return false
	return Vector2(float(p[0]), float(p[1])).distance_to(Vector2(at.x, at.z)) <= radius


static func _is_in_region(region: String, interior: String, at: Vector3) -> bool:
	if interior != "":
		var place := str(ContentDB.get_or_empty(interior).get("place", ""))
		return place != "" and WorldProbe.region_of_place(place) == region
	if at == Vector3.INF:
		return false
	return WorldProbe.region_id_at(at) == region


## Where an objective's place is in the open, or Vector3.INF for an interior or no place at all.
static func place_position(objective: Dictionary) -> Vector3:
	var where := str(objective.get("where", ""))
	if where == "" or where == ANYWHERE or Ids.type_of(where) == "interior":
		return Vector3.INF
	var p: Array = ContentDB.get_or_empty(where).get("position", [])
	if p.size() < 2:
		return Vector3.INF
	return WorldProbe.place_position(where)
