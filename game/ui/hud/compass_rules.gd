class_name CompassRules
extends RefCounted
## Which places the compass strip shows, and how (DESIGN §5.16), in the manner of Skyrim's: a
## place is on the strip only within its kind's range, a big place from much further off than a
## small one, an undiscovered place faintly once you are near enough to notice it, and never more
## than CAP at once, the nearest and biggest first.
##
## The user's playtest 6: the strip "becomes too crowded with POI, should be more of a Skyrim
## distance-based mechanic", and "other POI aside from intro area don't seem to have distant icons
## (like towns)". Before, every discovered place showed at any range and no undiscovered one ever
## did, so the strip filled with the Stair Head's neighbours and a town over the hill never
## appeared. Quest areas are not decided here: they always show (the HUD's smudges).
##
## Pure and static, so tests can ask it about any spot without a scene (test_compass_rules.gd).

## Metres. `range`: a discovered place of this kind shows within it. `notice`: an undiscovered one
## shows faintly within it (0: not until it is found). `weight`: how much it counts when the strip
## is full (the bigger the place, the longer it holds its slot). `inside` (default TOO_NEAR_M):
## within this you are in the place, and it is not a marker. A kind not listed takes "poi".
const KINDS := {
	"city": {"range": 2200.0, "notice": 1300.0, "weight": 5.0, "inside": 260.0},
	"town": {"range": 1800.0, "notice": 1000.0, "weight": 4.0, "inside": 150.0},
	"village": {"range": 1200.0, "notice": 700.0, "weight": 3.0, "inside": 100.0},
	"landmark": {"range": 1500.0, "notice": 900.0, "weight": 3.0, "inside": 40.0},
	"hamlet": {"range": 800.0, "notice": 400.0, "weight": 2.0, "inside": 60.0},
	"fort": {"range": 900.0, "notice": 450.0, "weight": 2.0, "inside": 60.0},
	"lodge": {"range": 800.0, "notice": 400.0, "weight": 2.0, "inside": 40.0},
	"ruin_village": {"range": 700.0, "notice": 350.0, "weight": 2.0, "inside": 60.0},
	"edge": {"range": 700.0, "notice": 0.0, "weight": 1.5},
	"camp": {"range": 350.0, "notice": 175.0, "weight": 1.0},
	"tower": {"range": 500.0, "notice": 250.0, "weight": 1.2},
	"giant_bones": {"range": 500.0, "notice": 250.0, "weight": 1.2},
	"waterfall": {"range": 450.0, "notice": 220.0, "weight": 1.2},
	"poi": {"range": 380.0, "notice": 180.0, "weight": 1.0},
	# found, not noticed: what is underground or tucked away is not given away by the strip
	"deep_place": {"range": 400.0, "notice": 0.0, "weight": 1.0},
	"interior_dungeon": {"range": 400.0, "notice": 0.0, "weight": 1.0},
	"hidden_valley": {"range": 380.0, "notice": 0.0, "weight": 1.0},
	"cave": {"range": 350.0, "notice": 60.0, "weight": 1.0},
	# the wayside's small finds are for the eye, not the strip
	"wayside": {"range": 0.0, "notice": 0.0, "weight": 0.5},
}
## The most places on the strip at once.
const CAP := 7
## Nothing is shown this near: you are standing in it, and the marker would swing about.
const TOO_NEAR_M := 12.0


static func rule(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["poi"])


## The places to show from `origin` (x, z), best first, at most `cap`: each
## {"id", "xz", "kind", "distance", "found"}. `places` is [{"id", "xz", "kind"}], every place and
## POI that stands on the map; `discovered` answers whether an id has been found (a Callable, so
## the HUD passes GameState and a test its own set).
static func select(origin: Vector2, places: Array, discovered: Callable, cap := CAP) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	for p: Dictionary in places:
		var xz: Vector2 = p["xz"]
		var d := origin.distance_to(xz)
		var r := rule(str(p.get("kind", "poi")))
		if d < float(r.get("inside", TOO_NEAR_M)):
			continue
		var found := bool(discovered.call(str(p["id"])))
		var reach := float(r["range"]) if found else float(r["notice"])
		if d > reach:
			continue
		# how far into its own range it stands, shortened by its weight: a town at the edge of
		# its 1.8 km still outranks a cairn at the edge of its 380 m, and anything close
		# outranks anything far
		var score := (d / maxf(float(r["range"]), 1.0)) / float(r["weight"])
		picked.append({"id": str(p["id"]), "xz": xz, "kind": str(p.get("kind", "poi")), "distance": d,
				"found": found, "score": score})
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) < float(b["score"]))
	if picked.size() > cap:
		picked.resize(cap)
	return picked


## Every place and POI with a position, as `select` takes them.
static func places_from_content() -> Array:
	var out: Array = []
	for type in ["place", "poi"]:
		for def in ContentDB.all(type):
			var pos: Variant = def.get("position", null)
			if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 2:
				continue
			out.append({"id": str(def.get("id", "")), "xz": Vector2(float(pos[0]), float(pos[1])),
					"kind": str(def.get("kind", "poi"))})
	return out
