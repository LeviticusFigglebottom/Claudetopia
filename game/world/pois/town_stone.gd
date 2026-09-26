extends Node3D
## The stone at a road's entry to a town or village, with the place's name cut in its face: a
## slab of the region's own stone about 1.4 m tall, its top rounded by the weather, standing in a
## footing of rough stones half in the verge, lichen on its shoulders, the letters cut on both
## faces so it is read coming and going. The cartographer's signposts (tools/world/atlas/
## signposts.json) put one at every road's entry to a settlement; the build writes each into its
## cell as a `scenes` entry with `props: {place_id}`, and the streamer calls `configure` with them
## before this enters the tree. Its local -Z faces the road.
##
## No class_name: the streamer instances it by path.

const HEIGHT_M := 1.4
const WIDTH_M := 0.86
const THICK_M := 0.28
const LETTERS_RANGE_M := 45.0
const FONT_PATH := "res://assets/fonts/Cinzel-Variable.ttf"
const CUT := Color(0.09, 0.085, 0.08)
const LICHEN := Color(0.58, 0.6, 0.42)
## The region's stone, as the POI kit paints it (PoiKit.SURFACES).
const REGION_OF_PLACE_DEFAULT := "hearthvale"

var place_id := ""
var display_name := ""
var region := REGION_OF_PLACE_DEFAULT


func configure(props: Dictionary) -> void:
	place_id = str(props.get("place_id", ""))


func _ready() -> void:
	var def: Dictionary = ContentDB.get_or_empty(place_id) if place_id != "" else {}
	display_name = str(def.get("name", Ids.name_of(place_id).capitalize() if place_id != "" else ""))
	var r := str(def.get("region", ""))
	if r.contains("/"):
		region = Ids.name_of(r)
	_build()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(("town_stone:" + place_id + str(global_position.round()) if is_inside_tree() else place_id).hash())
	var stone := _stone_material(rng)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.03)) * Basis(Vector3.BACK, rng.randf_range(-0.04, 0.04))
	# the slab, sunk a hand into the ground, and its weathered top: a flattened round over it
	var body_h := HEIGHT_M - 0.18
	# the slab: a broad flat face for the name, a little narrower above than at the foot, where a
	# plinth course stands proud of it. (An eight-sided slab put the name across three faces, and the
	# angled ones hid its ends.)
	var slab := BoxMesh.new()
	slab.size = Vector3(WIDTH_M * 0.94, body_h * 0.72, THICK_M)
	st.append_from(slab, 0, Transform3D(lean, lean * Vector3(0.0, body_h * 0.62, 0.0)))
	var foot := BoxMesh.new()
	foot.size = Vector3(WIDTH_M, body_h * 0.34 + 0.25, THICK_M + 0.04)
	st.append_from(foot, 0, Transform3D(lean, lean * Vector3(0.0, (body_h * 0.34 + 0.25) * 0.5 - 0.25, 0.0)))
	var cap := SphereMesh.new()
	cap.radius = 0.5
	cap.height = 1.0
	cap.radial_segments = 18
	cap.rings = 8
	st.append_from(cap, 0, Transform3D(lean, lean * Vector3(0.0, body_h - 0.02, 0.0)).scaled_local(Vector3(WIDTH_M * 0.93, 0.36, THICK_M * 0.98)))
	# the footing: rough stones round its foot, half in the verge
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var rock := BoxMesh.new()
		rock.size = Vector3(rng.randf_range(0.22, 0.36), rng.randf_range(0.14, 0.22), rng.randf_range(0.18, 0.3))
		var at := Vector3(sin(a) * (WIDTH_M * 0.5 + 0.08), -0.02, cos(a) * (THICK_M * 0.5 + 0.14))
		st.append_from(rock, 0, Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), at))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Stone"
	mesh.mesh = st.commit()
	mesh.material_override = stone
	add_child(mesh)
	# lichen on its shoulders
	var lichen := MeshInstance3D.new()
	lichen.name = "Lichen"
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		var patch := SphereMesh.new()
		patch.radius = 0.5
		patch.height = 1.0
		patch.radial_segments = 8
		patch.rings = 3
		var side := -1.0 if i % 2 == 0 else 1.0
		# crusts of it on the shoulders and down the sides, flat on the stone
		var x := rng.randf_range(-WIDTH_M * 0.44, WIDTH_M * 0.44)
		var y := body_h + rng.randf_range(-0.6, 0.12) * (1.0 - absf(x) / WIDTH_M)
		var at := Vector3(x, y, side * (THICK_M * 0.5 + 0.004))
		var sz := rng.randf_range(0.025, 0.06)
		ls.append_from(patch, 0, Transform3D(lean, lean * at).scaled_local(Vector3(sz, sz * rng.randf_range(0.6, 1.0), 0.012)))
	ls.generate_normals()
	lichen.mesh = ls.commit()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = LICHEN
	lm.roughness = 1.0
	lichen.material_override = lm
	lichen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lichen)
	# the name, cut in both faces: dark in the grooves, read from the road and from the town
	if display_name != "":
		for side_v in [-1.0, 1.0]:
			var side := float(side_v)
			var label := Label3D.new()
			label.name = "Name" if side < 0.0 else "NameBack"
			label.text = display_name.to_upper()
			if ResourceLoader.exists(FONT_PATH):
				label.font = load(FONT_PATH) as Font
			label.font_size = 64
			# the name across the stone's face and no wider than it: Cinzel's capitals at 64 px are
			# about 50 px wide each
			label.pixel_size = clampf((WIDTH_M * 0.8) / (58.0 * maxf(float(display_name.length()), 4.0)), 0.0008, 0.0034)
			label.modulate = CUT
			label.outline_size = 0
			label.shaded = true
			label.double_sided = false
			label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.visibility_range_end = LETTERS_RANGE_M
			var face := Basis(Vector3.UP, PI) if side < 0.0 else Basis()
			label.transform = Transform3D(lean * face, lean * Vector3(0.0, body_h * 0.62, side * (THICK_M * 0.5 + 0.004)))
			add_child(label)
	# what a body walks into
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH_M, HEIGHT_M, THICK_M + 0.04)
	cs.shape = box
	cs.position = Vector3(0.0, HEIGHT_M * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)


## The region's stone, painted as the POI kit paints it, worn by the weather.
func _stone_material(rng: RandomNumberGenerator) -> Material:
	var by_region: Dictionary = PoiKit.SURFACES.get(region, PoiKit.SURFACES["hearthvale"])
	var spec: Dictionary = (by_region.get("stone", {}) as Dictionary).duplicate()
	# a single dressed stone, not a wall of blocks: the unit as large as the stone, so the pattern
	# draws its weathering and not courses
	spec["unit"] = 1.6
	# weathered darker than a new-cut block, as a stone that has stood by the road a lifetime
	for key in ["base", "accent"]:
		spec[key] = "#" + Color.html(str(spec.get(key, "#aaaaaa"))).darkened(0.34).to_html(false)
	return PoiKit.painted(2, spec, rng.randf_range(0.75, 0.95), 0.9)
