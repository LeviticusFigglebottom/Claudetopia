class_name Personality
extends RefCounted
## Personality traits (DESIGN §5.12): six axes, each NPC carries one side of some of them.
## Trait behaviour (greeting bias, gesture responses, price bias, crime reaction) is data in
## a table def with role "personality_traits" (core: core:table/personality_traits); the
## constants below are the fallback when no table is loaded, so tests need no content.

const TRAITS: Array[String] = ["brave", "timid", "greedy", "generous", "pious", "cynical", "gossip", "quiet", "proud", "humble", "kind", "cruel"]
const OPPOSITES := {
	"brave": "timid", "timid": "brave", "greedy": "generous", "generous": "greedy", "pious": "cynical", "cynical": "pious",
	"gossip": "quiet", "quiet": "gossip", "proud": "humble", "humble": "proud", "kind": "cruel", "cruel": "kind",
}
const GESTURES: Array[String] = ["bow", "wave", "rude", "dance", "laugh", "flex"]
const BASE_GESTURE := {"bow": 2, "wave": 1, "rude": -4, "dance": 0, "laugh": 1, "flex": 0}
## Crime reactions, first matching trait wins in this order.
const CRIME_PRIORITY: Array[String] = ["timid", "brave", "gossip", "pious", "proud", "kind", "humble", "cynical", "quiet", "cruel", "greedy", "generous"]
const FALLBACK_ROWS := {
	"brave": {"greeting": "bold", "gestures": {"bow": 1, "wave": 1, "rude": -2, "flex": 2, "laugh": 1}, "price_bias": 0.0, "crime_reaction": "confront", "fear": -0.3},
	"timid": {"greeting": "wary", "gestures": {"bow": 2, "wave": 1, "rude": -6, "flex": -2, "laugh": 0}, "price_bias": 0.0, "crime_reaction": "flee", "fear": 0.4},
	"greedy": {"greeting": "sly", "gestures": {"bow": 1, "flex": 1, "rude": -3}, "price_bias": 0.1, "crime_reaction": "report", "fear": 0.0},
	"generous": {"greeting": "warm", "gestures": {"bow": 2, "wave": 2, "laugh": 2, "dance": 1}, "price_bias": -0.1, "crime_reaction": "report", "fear": 0.0},
	"pious": {"greeting": "pious", "gestures": {"bow": 3, "rude": -6, "dance": -1, "laugh": 0}, "price_bias": 0.0, "crime_reaction": "report", "fear": 0.0},
	"cynical": {"greeting": "curt", "gestures": {"bow": -1, "rude": -1, "laugh": 2, "flex": -1}, "price_bias": 0.05, "crime_reaction": "ignore", "fear": -0.1},
	"gossip": {"greeting": "nosy", "gestures": {"wave": 2, "laugh": 2, "dance": 2}, "price_bias": 0.0, "crime_reaction": "report", "fear": 0.0},
	"quiet": {"greeting": "curt", "gestures": {"wave": 0, "laugh": -1, "dance": -1, "rude": -2}, "price_bias": 0.0, "crime_reaction": "ignore", "fear": 0.1},
	"proud": {"greeting": "bold", "gestures": {"bow": 3, "rude": -8, "flex": -1, "laugh": -1}, "price_bias": 0.05, "crime_reaction": "confront", "fear": -0.2},
	"humble": {"greeting": "warm", "gestures": {"bow": 0, "wave": 2, "flex": -1, "rude": -3}, "price_bias": -0.05, "crime_reaction": "report", "fear": 0.1},
	"kind": {"greeting": "warm", "gestures": {"wave": 2, "laugh": 1, "dance": 1, "rude": -3}, "price_bias": -0.05, "crime_reaction": "report", "fear": 0.0},
	"cruel": {"greeting": "cold", "gestures": {"rude": 1, "laugh": 1, "bow": -1, "wave": -1}, "price_bias": 0.05, "crime_reaction": "ignore", "fear": -0.1},
}

static var _rows_cache: Dictionary = {}
static var _rows_loaded := false

var traits: Array[String] = []
## What this person does about a crime they see, when their def says it outright (`personality`'s
## `crime_reaction`: report | confront | flee | ignore) over what their traits would: Sauve Mor, who
## teaches the rogue the lock on the Tallymen's strongbox, does not report the lesson.
var reaction := ""


static func from_def(def: Dictionary) -> Personality:
	var p := Personality.new()
	var block: Variant = def.get("personality", {})
	var list: Variant = block.get("traits", []) if typeof(block) == TYPE_DICTIONARY else block
	if typeof(list) == TYPE_ARRAY or typeof(list) == TYPE_PACKED_STRING_ARRAY:
		for t in list:
			p.add(str(t))
	if typeof(block) == TYPE_DICTIONARY:
		p.reaction = str((block as Dictionary).get("crime_reaction", ""))
	return p


static func of(list: Array) -> Personality:
	var p := Personality.new()
	for t in list:
		p.add(str(t))
	return p


## Trait rows keyed by trait, from the content table with role "personality_traits" if one is
## loaded, else the fallback constants. Tests may pass rows to `set_rows`.
static func rows() -> Dictionary:
	if _rows_loaded:
		return _rows_cache
	_rows_loaded = true
	_rows_cache = {}
	if ContentDB.is_loaded:
		for t in ContentQuery.where_scalar("table", "role", "personality_traits"):
			for r in t.get("rows", []):
				if typeof(r) == TYPE_DICTIONARY and r.has("trait"):
					_rows_cache[str(r["trait"])] = r
	if _rows_cache.is_empty():
		_rows_cache = FALLBACK_ROWS.duplicate(true)
	return _rows_cache


static func set_rows(new_rows: Dictionary) -> void:
	_rows_cache = new_rows.duplicate(true)
	_rows_loaded = true


static func reset_rows() -> void:
	_rows_loaded = false
	_rows_cache = {}


static func row(trait_name: String) -> Dictionary:
	return rows().get(trait_name, FALLBACK_ROWS.get(trait_name, {}))


func add(trait_name: String) -> void:
	var t := trait_name.strip_edges().to_lower()
	if t.is_empty() or t in traits:
		return
	var opp := opposite_of(t)
	if not opp.is_empty() and opp in traits:
		traits.erase(opp)
	traits.append(t)


func has(trait_name: String) -> bool:
	return trait_name in traits


func is_opposed(trait_name: String) -> bool:
	var opp := opposite_of(trait_name)
	return not opp.is_empty() and opp in traits


## The other side of a trait's axis, as the trait table says (`opposite` on its row), so a pack
## that adds an axis gets it kept one side at a time; the built-in pairs when no table says.
## The table's own column was never read: the pairs were written twice, and only the copy in
## this file counted.
static func opposite_of(trait_name: String) -> String:
	var r := row(trait_name)
	if r.has("opposite"):
		return str(r["opposite"])
	return str(OPPOSITES.get(trait_name, ""))


## Disposition change for a gesture (DESIGN §5.9): base response plus every trait's bias.
func disposition_delta(gesture: String) -> int:
	var total := int(BASE_GESTURE.get(gesture, 0))
	for t in traits:
		var g: Dictionary = row(t).get("gestures", {})
		total += int(g.get(gesture, 0))
	return total


## Multiplicative price bias: +0.10 greedy, -0.10 generous, small nudges from other traits.
func price_bias() -> float:
	var bias := 0.0
	for t in traits:
		bias += float(row(t).get("price_bias", 0.0))
	return clampf(bias, -0.25, 0.25)


## What this NPC does on witnessing a crime: report | flee | confront | ignore.
func crime_reaction() -> String:
	if not reaction.is_empty():
		return reaction
	for t in CRIME_PRIORITY:
		if t in traits:
			return str(row(t).get("crime_reaction", "report"))
	return "report"


## Greeting pool key for the dialogue stream: warm | bold | wary | curt | sly | pious | nosy | cold.
func greeting_bias() -> String:
	for t in traits:
		var g := str(row(t).get("greeting", ""))
		if not g.is_empty():
			return g
	return "plain"


## -1..1: how easily this NPC is frightened (timid high, brave low).
func fear() -> float:
	var f := 0.0
	for t in traits:
		f += float(row(t).get("fear", 0.0))
	return clampf(f, -1.0, 1.0)


func describe() -> String:
	return ", ".join(traits) if not traits.is_empty() else "plain"
