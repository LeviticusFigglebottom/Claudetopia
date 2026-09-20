class_name HouseInterior
extends Node3D
## Builds a house or shop from a house-forge meta file: shell, surfaces by room, doors,
## windows with daylight, hearth and candle light, and every prop the dressing pass placed.
##
## Who lives here decided the plan and the contents; this makes them visible.

const SURFACE_SHADER := preload("res://assets/shaders/painted_surface.gdshader")
const DOOR := preload("res://systems/interiors/door.tscn")

## Wall and floor materials by culture, so a Vale cottage and a Reedfolk stilt-house are
## built of different stuff even when the plan is the same.
const CULTURE_SURFACES := {
	"vale": {"wall": {"pattern": 0, "base": "#e4dcc6", "accent": "#c9bda0", "grout": "#8d8266"},
			 "floor": {"pattern": 1, "base": "#8a6f4c", "accent": "#6b543a", "grout": "#40331f", "unit": 0.22},
			 "beam": {"pattern": 3, "base": "#5e452c", "accent": "#3c2c1c"}},
	"lakefolk": {"wall": {"pattern": 0, "base": "#f1eee6", "accent": "#d6d2c6", "grout": "#9a978c"},
				 "floor": {"pattern": 2, "base": "#9a968c", "accent": "#7e7a72", "grout": "#4e4b46", "unit": 0.45},
				 "beam": {"pattern": 3, "base": "#4a4038", "accent": "#2e2721"}},
	"reedfolk": {"wall": {"pattern": 3, "base": "#6b5540", "accent": "#493826", "grout": "#2b2118"},
				 "floor": {"pattern": 1, "base": "#7b6446", "accent": "#5a4730", "grout": "#33281a", "unit": 0.18},
				 "beam": {"pattern": 3, "base": "#4c3b28", "accent": "#2c2116"}},
	"clans": {"wall": {"pattern": 2, "base": "#a9a49a", "accent": "#8b857b", "grout": "#5c5850", "unit": 0.38},
			  "floor": {"pattern": 5, "base": "#6f6658", "accent": "#554d42", "grout": "#3a352d"},
			  "beam": {"pattern": 3, "base": "#514436", "accent": "#332a20"}},
	"woodfolk": {"wall": {"pattern": 3, "base": "#6a563c", "accent": "#463725", "grout": "#2a2116"},
				 "floor": {"pattern": 1, "base": "#7a6444", "accent": "#584630", "grout": "#33281a", "unit": 0.26},
				 "beam": {"pattern": 3, "base": "#473625", "accent": "#2a2016"}},
	"pilgrims": {"wall": {"pattern": 2, "base": "#a5a099", "accent": "#857f78", "grout": "#57534d", "unit": 0.5},
				 "floor": {"pattern": 5, "base": "#6b6660", "accent": "#514d48", "grout": "#38352f"},
				 "beam": {"pattern": 3, "base": "#4a453e", "accent": "#2c2925"}},
}

@export_file("*.json") var meta_path := ""
@export var build_on_ready := true

var meta: Dictionary = {}
var rooms: Dictionary = {}
var _missing: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _props := PropLibrary.new()
## Prop kinds that are a book somebody could pick up and read.
const BOOK_PROPS := ["book_single", "book_stack", "roll_book", "ledger"]

## Furniture you can open, and what it is worth opening. A house's chests were meshes until
## now: the container system could roll loot, lock itself and be emptied, and nothing in an
## interior ever attached one to the chest standing in the room. `wealth` shifts the table, so
## a cottager's chest is not the steward's.
const OPENABLE := {
	"chest": "common", "deed_chest": "rich", "strongbox": "rich", "coffer": "rich",
	"cupboard": "common", "crate": "poor", "root_crate": "poor", "barrel": "poor",
	"barrel_rack": "poor", "hop_sacks": "poor", "seed_sacks": "poor", "flour_sacks": "poor",
	"washstand": "poor",
}
## Which loot table a tier draws from. "poor" gets none: a sack of flour holds flour, and an
## empty crate that says "Empty." is more honest than a crate that mints a dagger.
const TIER_LOOT := {"common": "core:loot/common_chest", "rich": "core:loot/rich_chest"}
## The ones a resident would actually lock.
const LOCKED := ["strongbox", "coffer", "deed_chest"]
var _shelf_index := 0
var _variant := 0


func _ready() -> void:
	if build_on_ready and not meta_path.is_empty():
		build(meta_path)


func build(path: String) -> bool:
	meta_path = path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("HouseInterior", "bad meta %s" % path)
		return false
	meta = parsed
	_rng.seed = int(meta.get("seed", 1))
	for r in meta.get("rooms", []):
		rooms[str(r["id"])] = r
	var dir := path.get_base_dir()
	var slug := path.get_file().trim_suffix(".meta.json")
	_build_shell(dir, slug)
	_build_collision(dir, slug)
	_build_windows()
	_build_lights()
	_build_props()
	_build_doors()
	Log.info("HouseInterior", "%s: %d rooms, %d props" % [meta.get("name", slug), rooms.size(), meta.get("placements", []).size()])
	return true


func _surfaces() -> Dictionary:
	var culture := str(meta.get("culture", "vale"))
	return CULTURE_SURFACES.get(culture, CULTURE_SURFACES["vale"])


func _make_material(spec: Dictionary, wear: float, soot_height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("pattern", int(spec.get("pattern", 0)))
	m.set_shader_parameter("base_color", Color.html(str(spec.get("base", "#cccccc"))))
	m.set_shader_parameter("accent_color", Color.html(str(spec.get("accent", "#999999"))))
	m.set_shader_parameter("grout_color", Color.html(str(spec.get("grout", "#666666"))))
	m.set_shader_parameter("unit_size", float(spec.get("unit", 1.0)))
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("soot_height", soot_height)
	m.set_shader_parameter("variation", 0.55)
	return m


func _build_shell(dir: String, slug: String) -> void:
	var glb := "%s/%s.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		Log.error("HouseInterior", "shell missing %s" % glb)
		return
	var inst := (load(glb) as PackedScene).instantiate()
	inst.name = "Shell"
	add_child(inst)
	var surf := _surfaces()
	# One material for the whole shell: walls dominate, and the floor pattern is picked
	# up by the floor props and rugs rather than by splitting the mesh.
	var wear := 0.35
	var soot := 1.9
	var mat := _make_material(surf["wall"], wear, soot)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Exposed joists and wall plates, in the culture's timber.
	if bool(meta.get("has_timber", false)):
		var tglb := "%s/%s_timber.glb" % [dir, slug]
		if ResourceLoader.exists(tglb):
			var tinst := (load(tglb) as PackedScene).instantiate()
			tinst.name = "Timber"
			add_child(tinst)
			var tmat := _make_material(surf["beam"], 0.25, soot - 0.4)
			for mi2 in tinst.find_children("*", "MeshInstance3D", true, false):
				(mi2 as MeshInstance3D).material_override = tmat
				(mi2 as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# Floors as separate quads, so they read as boards or flags rather than plaster.
	var floors := Node3D.new()
	floors.name = "Floors"
	add_child(floors)
	var floor_mat := _make_material(surf["floor"], 0.75, 10000.0)
	for id in rooms:
		var r: Dictionary = rooms[id]
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(r["w"]), float(r["d"]))
		plane.mesh = pm
		plane.material_override = floor_mat
		plane.position = Vector3(float(r["x"]) + float(r["w"]) * 0.5, float(r["floor_y"]) + 0.012, float(r["z"]) + float(r["d"]) * 0.5)
		floors.add_child(plane)


func _build_collision(dir: String, slug: String) -> void:
	var glb := "%s/%s_col.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		glb = "%s/%s.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		return
	var inst := (load(glb) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1 | (1 << 9)
	body.collision_mask = 0
	add_child(body)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		cs.transform = (mi as MeshInstance3D).transform
		body.add_child(cs)
	inst.queue_free()
	# Floors need collision too: the shell's slabs are solid, but a plane is cheaper
	# for the walkable surface and keeps the player off the slab's top face seam.
	for id in rooms:
		var r: Dictionary = rooms[id]
		var cs2 := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(r["w"]), 0.1, float(r["d"]))
		cs2.shape = bs
		cs2.position = Vector3(float(r["x"]) + float(r["w"]) * 0.5, float(r["floor_y"]) - 0.05, float(r["z"]) + float(r["d"]) * 0.5)
		body.add_child(cs2)


## Windows: a pane, a frame, and the daylight that comes through them, which is most of
## what makes a room feel like a room during the day.
func _build_windows() -> void:
	var holder := Node3D.new()
	holder.name = "Windows"
	add_child(holder)
	for w in meta.get("windows", []):
		var at := _vec(w["at"])
		var yaw := float(w.get("yaw", 0.0))
		var normal := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))

		var pane := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.85, 1.05)
		pane.mesh = qm
		var pmat := StandardMaterial3D.new()
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.albedo_color = Color(0.82, 0.88, 0.92, 0.28)
		pmat.roughness = 0.12
		pmat.metallic = 0.0
		pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pane.mesh.material = pmat
		pane.position = at
		pane.rotation.y = deg_to_rad(yaw)
		holder.add_child(pane)

		# Daylight through the opening, aimed inward and warm-cool by the hour.
		var light := SpotLight3D.new()
		light.position = at + normal * 0.6
		light.look_at_from_position(at + normal * 0.6, at - normal * 3.0, Vector3.UP)
		light.spot_range = 9.0
		light.spot_angle = 58.0
		light.spot_angle_attenuation = 0.8
		light.light_energy = 2.6
		light.light_color = Color(0.92, 0.95, 1.0)
		light.shadow_enabled = true
		light.set_meta("daylight", true)
		holder.add_child(light)


func _build_lights() -> void:
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)
	for l in meta.get("lights", []):
		var lamp := OmniLight3D.new()
		lamp.position = _vec(l["at"])
		lamp.light_color = Color.html(str(l.get("color", "#ffd9a0")))
		lamp.light_energy = float(l.get("energy", 1.0))
		lamp.omni_range = float(l.get("range", 6.0))
		lamp.shadow_enabled = bool(l.get("shadow", false))
		lamp.light_specular = 0.35
		lamp.set_meta("flicker", float(l.get("flicker", 0.0)))
		lamp.set_meta("base_energy", lamp.light_energy)
		holder.add_child(lamp)


func _build_props() -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	add_child(holder)
	for p in meta.get("placements", []):
		var node := _instance(str(p.get("asset", "")), str(p.get("fixture", p.get("prop", "thing"))))
		if node == null:
			continue
		node.position = _vec(p["at"])
		node.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		if p.has("wear"):
			node.set_meta("wear", p["wear"])
		if p.has("habit"):
			node.set_meta("habit", p["habit"])
		node.set_meta("room", p.get("room", ""))
		holder.add_child(node)
		var kind := str(p.get("fixture", p.get("prop", "")))
		_make_readable(node, kind, p)
		_make_openable(node, kind, p)


## A chest that opens. The id is built from the house and the thing's own place in it, so the
## same chest holds the same contents every time you come back to it and across a save; the
## owner is the resident, which is what makes taking from it a theft rather than a pickup.
func _make_openable(node: Node3D, kind: String, placement: Dictionary) -> void:
	if not OPENABLE.has(kind):
		return
	var tier := str(OPENABLE[kind])
	var box := WorldContainer.new()
	box.name = "Container"
	var at: Vector3 = node.position
	box.container_id = "%s/%s@%d_%d" % [str(meta.get("id", "interior")), kind,
			roundi(at.x * 10.0), roundi(at.z * 10.0)]
	var owner_npc := str(meta.get("resident", ""))
	if owner_npc != "":
		box.owner_npc = owner_npc
	var table := str(TIER_LOOT.get(tier, ""))
	# A wealthy house's ordinary chests are worth more than a poor one's best.
	if tier == "common" and int(meta.get("wealth", 2)) >= 3:
		table = str(TIER_LOOT["rich"])
	box.loot_table = table
	if LOCKED.has(kind):
		box.locked = true
		box.key_item = str(placement.get("key_item", ""))
	# The prop is a mesh; the body that the interaction ray hits has to be the container's own,
	# and it needs a shape or the ray goes straight through the chest.
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = _placeholder_size(kind)
	shape.shape = form
	shape.position.y = form.size.y * 0.5
	box.add_child(shape)
	node.add_child(box)


## Book props are the only ones worth walking across a room for, so they carry the book they
## are. The recipe may name one (`book`/`item`); otherwise the house's own shelf gets what a
## household like this would own, picked from the culture pool and settled by the house seed so
## the same shelf holds the same book every time you come back.
func _make_readable(node: Node3D, kind: String, placement: Dictionary) -> void:
	if not BOOK_PROPS.has(kind):
		return
	var book := str(placement.get("book", ""))
	var item := str(placement.get("item", ""))
	if book.is_empty() and item.is_empty():
		var pick := _shelf_book()
		book = str(pick.get("book", ""))
		item = str(pick.get("item", ""))
	if book.is_empty() and item.is_empty():
		return
	var readable := Readable.new()
	readable.name = "Readable"
	readable.book_id = book
	readable.item_id = "" if bool(placement.get("fixed", false)) else item
	readable.fixed = bool(placement.get("fixed", false))
	if not book.is_empty():
		readable.display_name = str(ContentDB.get_or_empty(book).get("title", "a book"))
	elif not item.is_empty():
		readable.display_name = str(ContentDB.get_or_empty(item).get("name", "a book"))
	node.add_child(readable)


## What this household keeps on the shelf. Books tagged with the house's culture come first,
## then anything common; a house with nothing suitable simply has no readable book.
func _shelf_book() -> Dictionary:
	var culture := str(meta.get("culture", ""))
	var wanted: Array = []
	var common: Array = []
	for def in ContentDB.all("item"):
		if str(def.get("category", "")) != "book":
			continue
		var tags: Array = def.get("tags", [])
		if tags.has("no_sale") or tags.has("quest"):
			continue
		if tags.has(culture):
			wanted.append(def)
		elif tags.has("common") or tags.has("vale"):
			common.append(def)
	var pool: Array = wanted if not wanted.is_empty() else common
	if pool.is_empty():
		return {}
	_shelf_index += 1
	var pick: Dictionary = pool[(int(meta.get("seed", 0)) + _shelf_index * 7) % pool.size()]
	return {"item": str(pick.get("id", "")), "book": str(pick.get("reads", ""))}


func _build_doors() -> void:
	var holder := Node3D.new()
	holder.name = "Doors"
	add_child(holder)
	for d in meta.get("doors", []):
		if str(d.get("kind", "")) != "front":
			continue
		var door := DOOR.instantiate()
		door.is_exit = true
		door.display_name = "the door"
		door.position = _vec(d["at"])
		door.rotation.y = deg_to_rad(float(d.get("yaw", 0.0)))
		holder.add_child(door)


## A path that exists is not a path that loads. A `.glb` whose import has not finished, or
## has produced something that is not a scene, used to come back null and be instantiated
## anyway — three script errors and a failed smoke run for what this function was written to
## survive. A prop that will not load takes the same road as a prop that was never built: a
## labelled box, and the name of the thing that would not load, said once.
func _scene_at(path: String) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		if not _missing.has(path):
			_missing[path] = true
			Log.warn("Interiors", "%s is not a scene, drawing a stand-in" % path)
		return null
	return packed.instantiate() as Node3D


## Props the forge has not built yet get a labelled stand-in sized like the real thing,
## so the room still reads and the gap is obvious in a review render.
func _instance(path: String, kind: String) -> Node3D:
	if path.is_empty():
		return null
	var direct := _scene_at(path)
	if direct != null:
		return direct
	# The recipe asked for a plain kind; the forge builds them per region. Ask the library
	# for this region's version before giving up and drawing a labelled stand-in.
	_variant += 1
	var found := _props.resolve(kind, str(meta.get("culture", "")), _variant)
	if found.is_empty():
		found = _props.resolve(kind, _region_of_place(), _variant)
	var real := _scene_at(found)
	if real != null:
		return real
	if not _missing.has(path):
		_missing[path] = true
	var size := _placeholder_size(kind)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	var m := StandardMaterial3D.new()
	var h := float(hash(kind) % 360) / 360.0
	m.albedo_color = Color.from_hsv(h, 0.32, 0.52)
	m.roughness = 0.9
	mi.material_override = m
	var root := Node3D.new()
	root.name = kind
	root.add_child(mi)
	return root


static func _placeholder_size(kind: String) -> Vector3:
	match kind:
		"forge", "bread_oven", "cook_hearth", "hearth": return Vector3(1.6, 1.4, 1.0)
		"anvil": return Vector3(0.8, 0.75, 0.4)
		"bed": return Vector3(2.0, 0.55, 1.1)
		"table", "long_table", "kneading_table", "prep_table": return Vector3(1.7, 0.78, 0.9)
		"bar", "counter": return Vector3(2.4, 1.05, 0.7)
		"barrel", "mash_tun", "copper": return Vector3(0.7, 0.95, 0.7)
		"chest", "deed_chest", "strongbox": return Vector3(0.95, 0.55, 0.5)
		"stool", "chair": return Vector3(0.42, 0.48, 0.42)
		"bench", "settle": return Vector3(1.9, 0.5, 0.45)
		"shelf", "bread_shelf", "bottle_shelf", "ingredient_shelf", "tool_rack", "weapon_rack": return Vector3(1.6, 0.35, 0.32)
		"millstone": return Vector3(2.0, 0.4, 2.0)
		"cupboard", "sideboard": return Vector3(1.2, 1.4, 0.5)
		"mug", "phial", "candle_stub", "jar", "coin_few": return Vector3(0.09, 0.13, 0.09)
		"jug", "candlestick", "lantern", "inkpot", "mortar": return Vector3(0.14, 0.22, 0.14)
		"bowl", "plate_stack", "loaf", "wrapped_loaf": return Vector3(0.2, 0.09, 0.2)
		"book_single", "ledger", "roll_book", "paper_stack": return Vector3(0.22, 0.06, 0.16)
		"boots", "small_boots": return Vector3(0.25, 0.18, 0.32)
		_: return Vector3(0.35, 0.35, 0.35)


static func _vec(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## The region a house stands in, for choosing the local timber and stone.
func _region_of_place() -> String:
	var place := str(meta.get("place", ""))
	if place.is_empty() or not ContentDB.has(place):
		return ""
	return str(ContentDB.get_def(place).get("region", ""))


func missing_assets() -> Array:
	return _missing.keys()


func _process(_delta: float) -> void:
	var lights := get_node_or_null("Lights")
	if lights == null:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	for c in lights.get_children():
		if c is OmniLight3D and float(c.get_meta("flicker", 0.0)) > 0.0:
			var amt: float = c.get_meta("flicker")
			var base: float = c.get_meta("base_energy")
			var o := float(c.get_index()) * 2.3
			var f := sin(t * 6.1 + o) * 0.5 + sin(t * 11.7 + o * 1.7) * 0.3 + sin(t * 2.7 + o) * 0.2
			(c as OmniLight3D).light_energy = base * (1.0 + f * amt * 0.45)
