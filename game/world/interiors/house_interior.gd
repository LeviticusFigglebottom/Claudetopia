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
## The stone a culture builds its fireplaces of.
const CULTURE_STONE := {
	"vale": {"pattern": 2, "base": "#9c9282", "accent": "#7d7466", "grout": "#4d473f", "unit": 0.3},
	"lakefolk": {"pattern": 2, "base": "#a8a59c", "accent": "#88857c", "grout": "#55534d", "unit": 0.34},
	"reedfolk": {"pattern": 2, "base": "#7e7362", "accent": "#5f5648", "grout": "#383229", "unit": 0.26},
	"clans": {"pattern": 2, "base": "#8f8a80", "accent": "#716c63", "grout": "#46423c", "unit": 0.38},
	"woodfolk": {"pattern": 2, "base": "#857a68", "accent": "#665d4f", "grout": "#3c362e", "unit": 0.3},
	"pilgrims": {"pattern": 2, "base": "#99948b", "accent": "#79746c", "grout": "#4b4843", "unit": 0.4},
}

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
## Which fixture is a working station, and which screen it opens (DESIGN §5.8). The anvil and
## not the hearth, because the anvil is the thing a smith stands at and the hearth is the thing
## that is hot. Nothing in the game opened the working screen at all, so twenty-one recipes,
## the whole alembic and the whole of enchanting were behind a door with no handle.
const WORKABLE := {
	"anvil": "forge",
	"alembic": "alembic",
	"name_table": "name_table",
}

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
## A body coming in through the front door is stood at least this far inside the wall, over the
## floor by ENTRANCE_LIFT, and this far from anything standing on the floor and from the walls:
## the player's capsule (0.35) and a hand's breadth.
const ENTRANCE_IN := 0.75
const ENTRANCE_LIFT := 0.05
const BODY_CLEARANCE := 0.45
const BODY_RADIUS := 0.35
## Things this low (a rug, a coin) are stood on, not walked round.
const UNDERFOOT := 0.15
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
	_mark_entrance()
	dress_furnishings()
	_build_doors()
	# what a quest says lies in here (the steward's brass key on his desk), put down by the
	# quest-item placer, owned by whoever lives here
	var items := get_tree().get_first_node_in_group("quest_items") if is_inside_tree() else null
	var interior_id := str(get_meta("interior_id", ""))
	if items != null and interior_id != "":
		items.call("raise_in_interior", self, interior_id, meta)
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

	# The fireplaces, built into the walls: stone, with the embers glowing in them.
	if bool(meta.get("has_masonry", false)):
		var mglb := "%s/%s_masonry.glb" % [dir, slug]
		if ResourceLoader.exists(mglb):
			var minst := (load(mglb) as PackedScene).instantiate()
			minst.name = "Masonry"
			add_child(minst)
			var smat := _make_material(CULTURE_STONE.get(str(meta.get("culture", "vale")), CULTURE_STONE["vale"]), 0.45, 1.2)
			var ember := StandardMaterial3D.new()
			ember.albedo_color = Color(0.25, 0.08, 0.02)
			ember.emission_enabled = true
			ember.emission = Color(1.0, 0.42, 0.12)
			ember.emission_energy_multiplier = 2.2
			ember.roughness = 1.0
			for mi3 in minst.find_children("*", "MeshInstance3D", true, false):
				var m3 := mi3 as MeshInstance3D
				m3.material_override = ember if str(m3.name).contains("ember") else smat
				m3.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	# Floors as separate quads, so they read as boards or flags rather than plaster.
	var floors := Node3D.new()
	floors.name = "Floors"
	add_child(floors)
	var floor_mat := _make_material(surf["floor"], 0.75, 10000.0)
	for f in _floor_rects():
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(f.size.x, f.size.z)
		plane.mesh = pm
		plane.material_override = floor_mat
		plane.position = f.get_center() + Vector3.UP * 0.012
		floors.add_child(plane)


## The walkable floor of every room, as flat boxes at floor height (size.y is 0): the meta's own
## `floors` when the forge wrote them (a landing's floor stops at its stairwell), else each room.
func _floor_rects() -> Array[AABB]:
	var out: Array[AABB] = []
	var listed: Array = meta.get("floors", [])
	if not listed.is_empty():
		for f in listed:
			var at := _vec(f["at"])
			var size := Vector3(float(f["size"][0]), 0.0, float(f["size"][1]))
			out.append(AABB(at - size * 0.5, size))
		return out
	for id in rooms:
		var r: Dictionary = rooms[id]
		out.append(AABB(Vector3(float(r["x"]), float(r["floor_y"]), float(r["z"])), Vector3(float(r["w"]), 0.0, float(r["d"]))))
	return out


func _build_collision(dir: String, slug: String) -> void:
	var glb := "%s/%s_col.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		glb = "%s/%s.glb" % [dir, slug]
	if not ResourceLoader.exists(glb):
		return
	var inst := (load(glb) as PackedScene).instantiate()
	var body := StaticBody3D.new()
	body.name = "Collision"
	# Footsteps read this (Foley.surface_at): a house is boards underfoot.
	body.set_meta("surface", "wood")
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
	for f in _floor_rects():
		var cs2 := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(f.size.x, 0.1, f.size.z)
		cs2.shape = bs
		cs2.position = f.get_center() + Vector3.DOWN * 0.05
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
		var node: Node3D
		if p.has("built"):
			# Built into the wall (a fireplace): drawn with the masonry, standing here as its place.
			node = Node3D.new()
			node.name = str(p.get("fixture", "built"))
			node.set_meta("built", p["built"])
		else:
			node = _instance(str(p.get("asset", "")), str(p.get("fixture", p.get("prop", "thing"))))
		if node == null:
			continue
		node.position = _vec(p["at"])
		node.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		if p.has("wear"):
			node.set_meta("wear", p["wear"])
		if p.has("habit"):
			node.set_meta("habit", p["habit"])
		node.set_meta("room", p.get("room", ""))
		node.set_meta("kind", str(p.get("fixture", p.get("prop", ""))))
		holder.add_child(node)
		_make_solid(node, p)
		var kind := str(p.get("fixture", p.get("prop", "")))
		_make_readable(node, kind, p)
		_make_openable(node, kind, p)
		_make_workable(node, kind)


## Furniture a body bumps into. The forge writes each placement's box, measured off the mesh it
## draws, in the prop's own frame (`collider`), or marks it clutter (a mug, a pair of boots: walked
## through, never in the way). A meta older than that gets the box of the meshes it drew, unless
## the thing is small or lies on a surface. One static body per prop, on the world layer, so the
## player and the people meet it where it stands.
const CLUTTER_H := 0.3
const CLUTTER_W := 0.3


func _make_solid(node: Node3D, p: Dictionary) -> void:
	if bool(p.get("clutter", false)):
		node.set_meta("clutter", true)
		return
	var box := AABB()
	if p.has("collider"):
		var c: Dictionary = p["collider"]
		var size := _vec(c["size"])
		box = AABB(_vec(c["centre"]) - size * 0.5, size)
	else:
		if p.has("on"):
			node.set_meta("clutter", true)
			return
		box = _local_bounds(node)
		if box.size.y < CLUTTER_H or maxf(box.size.x, box.size.z) < CLUTTER_W:
			node.set_meta("clutter", true)
			return
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone" if p.has("built") else "wood")
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = box.size
	shape.shape = form
	shape.position = box.get_center()
	body.add_child(shape)
	node.add_child(body)


## The box round every mesh under `node`, in `node`'s own frame (it need not be in the tree).
static func _local_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi_v in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != node:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## A bench you can work at. The station rides the prop it belongs to, so what you walk up to
## is the thing you were looking at rather than an invisible trigger beside it. The resident
## owns their own tools; using a smith's anvil is not theft, but the law can be told about it.
func _make_workable(node: Node3D, kind: String) -> void:
	if not WORKABLE.has(kind):
		return
	var bench := CraftingStation.new()
	bench.name = "Station"
	bench.station = str(WORKABLE[kind])
	bench.size = _placeholder_size(kind)
	bench.owner_npc = str(meta.get("resident", ""))
	node.add_child(bench)


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


# --- furnishings the player has bought (DESIGN §5.14) -------------------------------------------

## What you have put in your own house. The forge dressed this building for whoever lives in
## it; if that is you, your furnishings go in on top of the dressing, at a spot derived from
## the room rather than authored, because a house you buy has no recipe line for a rug.
##
## `PropertyRegistry.add_furnishing()` and `furnishings()` were written, saved and tested, and
## nothing in the game either sold a furnishing or drew one, so "Furnishings bought" was a
## save field. This is the drawing half.
##
## Public because `build()` is not the only way in: a review render or a test can load a meta
## and dress it without raising the shell.
func dress_furnishings() -> void:
	var reg := PropertyRegistry.instance
	if reg == null or not is_instance_valid(reg):
		return
	var property_id := reg.property_for_interior(str(meta.get("id", "")))
	if property_id.is_empty():
		return
	var bought: Array = reg.furnishings(property_id)
	if bought.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Furnishings"
	add_child(holder)
	var placed := 0
	for entry in bought:
		if _place_furnishing(holder, property_id, str(entry), placed):
			placed += 1
	Log.info("HouseInterior", "%s: %d of your own furnishings" % [property_id, placed])


func _place_furnishing(holder: Node3D, property_id: String, item_id: String, index: int) -> bool:
	var block: Dictionary = ContentDB.get_or_empty(item_id).get("furnishing", {})
	if block.is_empty():
		Log.warn("HouseInterior", "%s has no furnishing block" % item_id)
		return false
	var kind := str(block.get("prop", ""))
	var room := _room_for(str(block.get("room", "")))
	if room.is_empty() or kind.is_empty():
		return false
	var against_wall := str(block.get("spot", "floor")) == "wall"
	var anchor := _free_spot(room, against_wall, index)
	var node := _instance("", kind)
	if node == null:
		return false
	node.name = Ids.name_of(item_id)
	node.position = anchor["at"]
	node.rotation.y = float(anchor["yaw"])
	node.set_meta("furnishing", item_id)
	node.set_meta("room", str(room["id"]))
	holder.add_child(node)
	if bool(block.get("storage", false)):
		_make_player_storage(node, property_id, item_id, kind)
	return true


## The room a furnishing asks for, or the hearth room, which every house in Wickmere has.
## A book press wants a study and most houses have none; it goes by the fire instead of
## refusing to exist.
func _room_for(wanted: String) -> Dictionary:
	if wanted != "" and rooms.has(wanted):
		return rooms[wanted]
	for fallback in ["hearth_room", "hall"]:
		if rooms.has(fallback):
			return rooms[fallback]
	for id in rooms:
		return rooms[id]
	return {}


## Where a body coming through the front door stands, as the "Entrance" marker Interiors.enter
## looks for: a step inside the door, on the floor of the room it opens into, clear of whatever
## the forge stood there (an oven, a stool, the bellows) and of the walls, facing into the room.
## Without one every house stood the player in the corner of its first room, a metre up.
func _mark_entrance() -> void:
	var front := _front_door()
	if front.is_empty():
		return
	var door_at := _vec(front["at"])
	var room: Dictionary = rooms.get(_front_room_id(front), {})
	if room.is_empty():
		return
	var x0 := float(room["x"])
	var z0 := float(room["z"])
	var w := float(room["w"])
	var d := float(room["d"])
	var floor_y := float(room.get("floor_y", 0.0))
	# In through the wall the door is in: whichever of the room's four sides it stands nearest.
	var sides := [
		[absf(door_at.z - z0), Vector3.BACK, Vector3(door_at.x, floor_y, z0)],
		[absf(door_at.z - (z0 + d)), Vector3.FORWARD, Vector3(door_at.x, floor_y, z0 + d)],
		[absf(door_at.x - x0), Vector3.RIGHT, Vector3(x0, floor_y, door_at.z)],
		[absf(door_at.x - (x0 + w)), Vector3.LEFT, Vector3(x0 + w, floor_y, door_at.z)],
	]
	sides.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var inward: Vector3 = sides[0][1]
	var sill: Vector3 = sides[0][2]
	var across := Vector3(inward.z, 0.0, -inward.x)
	var things := _things_on_floor(floor_y)
	# Spots on a 0.1 m lattice inside the door, the nearest to a step straight in first; a hand's
	# breadth from everything if there is such a spot, else a capsule's width (a small room with a
	# hearth and a settle either side of the door, like Merrick's, has no more).
	var wanted := sill + inward * ENTRANCE_IN
	var lattice: Array[Vector3] = []
	for i in 21:
		for j in 33:
			lattice.append(sill + inward * (ENTRANCE_IN + 0.1 * float(i)) + across * (0.1 * float(j - 16)))
	lattice.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(wanted) < b.distance_squared_to(wanted))
	var spot := wanted
	var found := false
	for clearance in [BODY_CLEARANCE, BODY_RADIUS + 0.02]:
		for p in lattice:
			if _within_room(room, p, clearance) and _clear_of(things, p, clearance):
				spot = p
				found = true
				break
		if found:
			break
	if not found:
		Log.warn("HouseInterior", "%s: nowhere clear inside the front door; the body stands in the way of something" % meta.get("name", "?"))
	var marker := Marker3D.new()
	marker.name = "Entrance"
	marker.position = spot + Vector3.UP * ENTRANCE_LIFT
	marker.rotation.y = atan2(-inward.x, -inward.z)
	marker.set_meta("room", str(room["id"]))
	add_child(marker)


## The meta's front door, or {} for a house with none.
func _front_door() -> Dictionary:
	for d in meta.get("doors", []):
		if str((d as Dictionary).get("kind", "")) == "front":
			return d
	return {}


## The room a front door opens into: the one it stands between with the outside, else the ground
## floor's first.
func _front_room_id(front: Dictionary) -> String:
	for id in front.get("between", []):
		if str(id) != "outside" and rooms.has(str(id)):
			return str(id)
	for r in meta.get("rooms", []):
		if absf(float((r as Dictionary).get("floor_y", 0.0))) < 0.01:
			return str(r["id"])
	return ""


static func _within_room(room: Dictionary, p: Vector3, margin: float) -> bool:
	return p.x >= float(room["x"]) + margin and p.x <= float(room["x"]) + float(room["w"]) - margin \
			and p.z >= float(room["z"]) + margin and p.z <= float(room["z"]) + float(room["d"]) - margin


## What stands on the floor at `floor_y` that a body cannot stand in, as boxes in this house's
## space: every mesh the props put up (the real meshes, which are not the sizes their kinds'
## stand-ins are drawn at: Merrick's forge hearth and crate are larger), from a rug's height to a
## head's. Before the house is in a tree, the stand-in sizes from the meta.
func _things_on_floor(floor_y: float) -> Array[AABB]:
	var out: Array[AABB] = []
	var holder := get_node_or_null("Props")
	if holder != null and is_inside_tree():
		var into_house := global_transform.affine_inverse()
		for mi_v in holder.find_children("*", "MeshInstance3D", true, false):
			var mi := mi_v as MeshInstance3D
			if mi.mesh == null:
				continue
			var box: AABB = (into_house * mi.global_transform) * mi.get_aabb()
			if box.end.y < floor_y + UNDERFOOT or box.position.y > floor_y + 1.8:
				continue
			out.append(box)
		return out
	for pl in meta.get("placements", []):
		var at := _vec((pl as Dictionary)["at"])
		if absf(at.y - floor_y) > 0.3:
			continue
		var size := _placeholder_size(str(pl.get("fixture", pl.get("prop", ""))))
		if size.y < UNDERFOOT:
			continue
		var turned := Basis(Vector3.UP, deg_to_rad(float(pl.get("yaw", 0.0))))
		out.append(Transform3D(turned, at) * AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size))
	return out


## Whether a body standing at `p` keeps `clearance` from every one of `things`, across the floor.
static func _clear_of(things: Array[AABB], p: Vector3, clearance: float) -> bool:
	for box in things:
		var dx := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
		var dz := maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)
		if Vector2(dx, dz).length() < clearance:
			return false
	return true


## Somewhere in this room that nothing already stands. The dressing pass put the resident's
## things down first, so this scores a lattice of candidate spots by how far they are from the
## nearest of them and takes the best — a derived anchor, deterministic for a given house and
## room, so your rug is in the same place every time you come home. `index` shifts the lattice
## so two furnishings in one room do not both win the same spot.
func _free_spot(room: Dictionary, against_wall: bool, index: int) -> Dictionary:
	const INSET := 0.55
	const STEPS := 5
	var x0 := float(room["x"]) + INSET
	var z0 := float(room["z"]) + INSET
	var w := maxf(float(room["w"]) - INSET * 2.0, 0.1)
	var d := maxf(float(room["d"]) - INSET * 2.0, 0.1)
	var y := float(room["floor_y"])
	var taken := _props_in(str(room["id"]))
	var best := Vector3(x0 + w * 0.5, y, z0 + d * 0.5)
	var best_yaw := 0.0
	var best_score := -1.0
	for i in STEPS:
		for j in STEPS:
			var u := (float((i + index) % STEPS) + 0.5) / float(STEPS)
			var v := (float(j) + 0.5) / float(STEPS)
			var at := Vector3(x0 + w * u, y, z0 + d * v)
			var yaw := 0.0
			if against_wall:
				# Nearest wall, and face into the room off it.
				var to_left := at.x - x0
				var to_right := x0 + w - at.x
				var to_near := at.z - z0
				var to_far := z0 + d - at.z
				var least := minf(minf(to_left, to_right), minf(to_near, to_far))
				if least > INSET * 1.2:
					continue        # not against anything; a wall-hung thing wants a wall
				if least == to_left:
					yaw = 90.0
				elif least == to_right:
					yaw = 270.0
				elif least == to_near:
					yaw = 0.0
				else:
					yaw = 180.0
			var score := 99.0
			for other in taken:
				score = minf(score, at.distance_to(other))
			if score > best_score:
				best_score = score
				best = at
				best_yaw = yaw
	return {"at": best, "yaw": deg_to_rad(best_yaw), "clearance": best_score}


## Where the resident's own things already stand in this room, furnishings included, so the
## second thing you buy does not land on the first; and where a body coming in through the front
## door stands, so a bought bed is not put in the doorway.
func _props_in(room_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var entrance := get_node_or_null("Entrance") as Node3D
	if entrance != null and str(entrance.get_meta("room", "")) == room_id:
		out.append(entrance.position)
	for p in meta.get("placements", []):
		if str((p as Dictionary).get("room", "")) == room_id:
			out.append(_vec((p as Dictionary)["at"]))
	var holder := get_node_or_null("Furnishings")
	if holder != null:
		for child in holder.get_children():
			if child is Node3D and str(child.get_meta("room", "")) == room_id:
				out.append((child as Node3D).position)
	return out


## A chest you bought is storage, and it is yours: no loot rolled into it, no resident on it,
## and claimed in your name so taking your own things back out is not theft. Its id is built
## from the property's storage id, so the same chest holds the same things across a save.
func _make_player_storage(node: Node3D, property_id: String, item_id: String, kind: String) -> void:
	var box := WorldContainer.new()
	box.name = "Storage"
	box.container_id = "%s#%s" % [PropertyRegistry.storage_id_of(property_id), Ids.name_of(item_id)]
	box.display_name = str(ContentDB.get_or_empty(item_id).get("name", "chest"))
	box.loot_table = ""
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = _placeholder_size(kind)
	shape.shape = form
	shape.position.y = form.size.y * 0.5
	box.add_child(shape)
	node.add_child(box)
	var reg := Ownership.ensure()
	if reg != null:
		reg.claim_for_player(box.container_id)


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
##
## An empty `path` means "no recipe named a file for this, ask the library for the kind" —
## which is how a bought furnishing arrives, since a deed carries a prop kind and not an
## asset path. A placement whose recipe named neither is the caller's mistake and is refused.
func _instance(path: String, kind: String) -> Node3D:
	if path.is_empty() and kind.is_empty():
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


## The box drawn when the forge has not built a prop yet — and, because it is the only written
## record of how big these things are, the specification the mesh is checked against by
## `tools/prop_heights.py`. So it has to describe *the object that will replace the box*, not
## the idea of the object: a chair with a back on it is a metre tall even though its seat is at
## 480 mm, and a hearth is the whole chimney breast even though the fire-opening is 1.4.
## Where a kind resolves through `PropLibrary.STAND_IN`, the size is the one the stand-in will
## actually draw, so a disagreement means a stand-in that lies about scale rather than a bad
## number here.
static func _placeholder_size(kind: String) -> Vector3:
	match kind:
		"forge", "bread_oven", "cook_hearth", "hearth": return Vector3(1.6, 2.1, 1.0)
		"anvil": return Vector3(0.8, 0.75, 0.4)
		"bed": return Vector3(2.0, 0.55, 1.1)
		"table", "long_table", "kneading_table", "prep_table": return Vector3(1.7, 0.78, 0.9)
		"name_table": return Vector3(1.4, 0.82, 0.8)
		"bar", "counter": return Vector3(2.4, 1.05, 0.7)
		"barrel", "mash_tun", "copper": return Vector3(0.7, 0.95, 0.7)
		"chest", "deed_chest", "strongbox": return Vector3(0.95, 0.55, 0.5)
		"stool": return Vector3(0.42, 0.48, 0.42)
		"chair": return Vector3(0.46, 1.06, 0.48)
		"bench", "settle": return Vector3(1.9, 0.5, 0.45)
		"shelf", "bread_shelf", "bottle_shelf", "ingredient_shelf", "tool_rack", "weapon_rack": return Vector3(1.6, 1.02, 0.32)
		"millstone": return Vector3(2.0, 0.4, 2.0)
		"cupboard", "sideboard": return Vector3(1.2, 1.4, 0.5)
		"mug", "phial", "candle_stub", "jar": return Vector3(0.09, 0.13, 0.09)
		"coin_few": return Vector3(0.08, 0.02, 0.08)
		"jug", "inkpot": return Vector3(0.16, 0.28, 0.16)
		"lantern", "mortar": return Vector3(0.14, 0.22, 0.14)
		"candlestick": return Vector3(0.12, 0.34, 0.12)
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
