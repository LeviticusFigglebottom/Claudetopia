class_name Fingerpost
extends Node3D
## A signpost whose arms name the places they point to.
##
## The forge's signpost is a post with two or three arms turned at random and nothing written on
## them, and the world build stood one wherever three roads meet, turned at random too: five
## posts in the country, pointing nowhere and saying nothing. This one is built where it stands:
## an arm down each road that leaves (RoadNetwork.destinations), turned along the road, with the
## name of the place at the other end cut into both faces, and the post's own cap on top.
## One mesh for the timber and two labels an arm (each with its groove), near-only.

const POST_H := 2.7
const ARM_LEN := 1.25
const ARM_H := 0.2
const ARM_T := 0.045
## Arms are hung from the top down, this far apart.
const ARM_STEP := 0.27
const LABEL_RANGE_M := 40.0
## Old oak gone grey, the paint a deep weathered green and the letters cut into it and picked out
## in cream, as a parish paints its posts. The arms were a near-white board on a pale post, which
## in any warm light read as two blank white slats nailed to a stick.
const TIMBER := Color(0.36, 0.31, 0.25)
const PAINT := Color(0.2, 0.27, 0.22)
const RIM := Color(0.13, 0.15, 0.13)
const LETTERING := Color(0.86, 0.8, 0.63)
## The groove's shadow along the top of each cut letter.
const CUT := Color(0.04, 0.04, 0.03)
const FONT_PATH := "res://assets/fonts/Cinzel-Variable.ttf"

## What the arms say and which way they point, set before the post enters the tree (or found
## from the roads on `_ready` when nothing was set).
var ways: Array = []

static var _font: Font = null


func _ready() -> void:
	add_to_group("fingerpost")
	if ways.is_empty():
		ways = RoadNetwork.destinations(Vector2(global_position.x, global_position.z))
	_build()


func _build() -> void:
	var fabric := FabricMesh.new()
	# the post, chamfered (a square and the same square on its corner), with a sloped cap and a
	# knob, and a collar of wedging where it goes into the ground
	fabric.box("joinery", Transform3D(Basis(), Vector3(0.0, POST_H * 0.5 - 0.2, 0.0)), Vector3(0.15, POST_H + 0.4, 0.15), TIMBER)
	fabric.box("joinery", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, POST_H * 0.5 - 0.2, 0.0)),
			Vector3(0.13, POST_H + 0.36, 0.13), TIMBER.darkened(0.08))
	fabric.box("joinery", Transform3D(Basis(), Vector3(0.0, POST_H + 0.02, 0.0)), Vector3(0.24, 0.05, 0.24), TIMBER.darkened(0.3))
	fabric.box("joinery", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, POST_H + 0.08, 0.0)), Vector3(0.13, 0.08, 0.13), TIMBER.darkened(0.35))
	fabric.box("joinery", Transform3D(Basis(Vector3.RIGHT, PI * 0.25) * Basis(Vector3.BACK, PI * 0.25),
			Vector3(0.0, POST_H + 0.15, 0.0)), Vector3(0.08, 0.08, 0.08), TIMBER.darkened(0.4))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		fabric.box("joinery", Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.45),
				Vector3(sin(a) * 0.12, 0.12, cos(a) * 0.12)), Vector3(0.1, 0.16, 0.05), TIMBER.darkened(0.25))
	var y := POST_H - 0.22
	for w in ways:
		var way: Dictionary = w
		var dir: Vector2 = way["dir"]
		# the arm's own frame: +x out along the road, +z across it, y up; in this node's space,
		# which is never turned (the post takes its turn from the arms, not from the scatter row)
		var arm := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(0.0, y, 0.0))
		fabric.box("joinery", arm * Transform3D(Basis(), Vector3(ARM_LEN * 0.5 + 0.05, 0.0, 0.0)),
				Vector3(ARM_LEN - 0.1, ARM_H, ARM_T), PAINT)
		# a moulded rail along the top and bottom edges, proud of both faces
		for e in [1.0, -1.0]:
			fabric.box("joinery", arm * Transform3D(Basis(), Vector3(ARM_LEN * 0.5 + 0.02, float(e) * (ARM_H * 0.5 - 0.008), 0.0)),
					Vector3(ARM_LEN - 0.16, 0.022, ARM_T + 0.014), RIM)
		# the pointed end: a square turned on its corner, half of it past the arm's end
		fabric.box("joinery", arm * Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(ARM_LEN, 0.0, 0.0)),
				Vector3(ARM_H * 0.707, ARM_H * 0.707, ARM_T), PAINT)
		# the iron strap that holds it to the post
		fabric.box("joinery", arm * Transform3D(Basis(), Vector3(0.1, 0.0, 0.0)), Vector3(0.05, ARM_H + 0.02, ARM_T + 0.02), RIM.darkened(0.3))
		_label(arm, str(way.get("name", "")))
		y -= ARM_STEP
	var mesh := fabric.commit(self, "joinery", FabricMesh.joinery_material(), "Timber")
	if mesh != null:
		FabricMesh.near_only(mesh, FabricMesh.PROP_RANGE_M, true)


## The place's name on both faces of an arm, reading from the post outward on one side and from
## the tip inward on the other, so it reads left to right from either side. Cut in Roman capitals: the
## cream letter, and under it, a hair behind and above, the dark of the groove's upper wall.
func _label(arm: Transform3D, text: String) -> void:
	if text == "":
		return
	for side_v in [1.0, -1.0]:
		var side := float(side_v)
		var label := _letters(text, LETTERING)
		label.name = "Way"
		var face := Basis() if side > 0.0 else Basis(Vector3.UP, PI)
		label.transform = arm * Transform3D(face, Vector3(ARM_LEN * 0.55, -0.004, side * (ARM_T * 0.5 + 0.004)))
		add_child(label)
		var groove := _letters(text, CUT)
		groove.name = "Groove"
		groove.position = Vector3(0.0, 0.004, -0.002)
		label.add_child(groove)


func _letters(text: String, colour: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	if _font != null:
		label.font = _font
	label.font_size = 40
	label.pixel_size = 0.0016
	label.modulate = colour
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visibility_range_end = LABEL_RANGE_M
	return label


## What the arms say, top to bottom.
func names() -> Array[String]:
	var out: Array[String] = []
	for w in ways:
		out.append(str((w as Dictionary).get("name", "")))
	return out
