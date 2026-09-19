class_name Schemas
## Light-weight content schemas: required fields per type plus generic checks.
## Validation never crashes the game; it reports problems that tests turn into failures.

const REQUIRED := {
	"region": ["name", "identity", "map"],
	"place": ["name", "region", "kind", "unique_feature"],
	"faction": ["name", "kind"],
	"item": ["name", "category", "weight", "value", "description"],
	"enemy": ["name", "archetype", "stats"],
	"npc": ["name", "home_place", "personality"],
	"quest": ["name", "stages"],
	"dialogue": ["nodes"],
	"loot": ["entries"],
	"spell": ["name", "school", "cost", "cast_type", "effects", "description"],
	"recipe": ["station", "inputs", "output"],
	"book": ["title", "author", "body"],
	"skill": ["name", "governs"],
	"perk": ["name", "skill", "requires_level", "effects"],
	"calling": ["name", "skill_bonuses", "description"],
	"encounter": ["place", "spawns"],
	"interior": ["name", "scene", "resident", "story", "unique_object"],
	"house": ["name", "scene", "resident", "story", "unique_object"],
	"gesture": ["name", "animation"],
	"rumour": ["text"],
	"weather": ["name"],
	"music": ["name"],
	"boss": ["name", "phases", "arena"],
	"cell": ["placements"],
	"effect": ["name"],
	"table": ["rows"],
	"schedule": ["entries"],
	"world": ["seed", "size_m"],
	"poi": ["name", "kind", "region"],
	"appearance": ["parts"],
}

## Keys whose string values are free text and must not be treated as ID references.
const NON_REFERENCE_KEYS := ["description", "text", "body", "name", "title", "tagline", "story", "lore", "greeting", "line", "notes", "author", "unique_feature", "unique_object", "formed_by", "geology", "architecture", "soundscape", "culture"]


static func validate_def(def: Dictionary, source: String) -> Array[String]:
	var out: Array[String] = []
	var id: String = str(def.get("id", ""))
	if not Ids.is_valid(id):
		out.append("%s: invalid or missing id '%s'" % [source, id])
		return out
	var type := Ids.type_of(id)
	if not REQUIRED.has(type):
		out.append("%s: unknown content type '%s' in %s" % [source, type, id])
		return out
	for key in REQUIRED[type]:
		if not def.has(key):
			out.append("%s: %s is missing required field '%s'" % [source, id, key])
	return out


## Finds strings that look like content IDs but do not exist in the registry.
static func find_dangling(def: Dictionary, registry: Dictionary, source: String) -> Array[String]:
	var out: Array[String] = []
	_walk(def, registry, source, str(def.get("id", "?")), out, "")
	return out


static func _walk(value: Variant, registry: Dictionary, source: String, owner: String, out: Array[String], key: String) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for k in value.keys():
				_walk(value[k], registry, source, owner, out, str(k))
		TYPE_ARRAY:
			for v in value:
				_walk(v, registry, source, owner, out, key)
		TYPE_STRING:
			if key in NON_REFERENCE_KEYS or key == "id":
				return
			if Ids.looks_like_id(value) and not registry.has(value):
				out.append("%s: %s references missing '%s' (field '%s')" % [source, owner, value, key])
