class_name Fingerpost
extends Node3D
## A signpost whose arms name the places they point to.
##
## The forge's signpost is a post with two or three arms turned at random and nothing written on
## them, and the world build stood one wherever three roads meet, turned at random too: five
## posts in the country, pointing nowhere and saying nothing. This one is built where it stands:
## an arm down each road that leaves (RoadNetwork.destinations), turned along the road, with the
## name of the place at the other end painted on both faces, and the post's own cap on top.
## One mesh for the timber and two labels an arm, near-only.

const POST_H := 2.7
const ARM_LEN := 1.25
const ARM_H := 0.2
const ARM_T := 0.045
## Arms are hung from the top down, this far apart.
const ARM_STEP := 0.27
const LABEL_RANGE_M := 40.0
const TIMBER := Color(0.5, 0.42, 0.32)
const PAINT := Color(0.88, 0.85, 0.76)
const LETTERING := Color(0.13, 0.1, 0.08)

## What the arms say and which way they point, set before the post enters the tree (or found
## from the roads on `_ready` when nothing was set).
var ways: Array = []


func _ready() -> void:
	add_to_group("fingerpost")
	if ways.is_empty():
		ways = RoadNetwork.destinations(Vector2(global_position.x, global_position.z))
	_build()


func _build() -> void:
	var fabric := FabricMesh.new()
	fabric.box("joinery", Transform3D(Basis(), Vector3(0.0, POST_H * 0.5, 0.0)), Vector3(0.14, POST_H, 0.14), TIMBER.darkened(0.2))
	fabric.box("joinery", Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, POST_H + 0.06, 0.0)), Vector3(0.2, 0.12, 0.2), TIMBER.darkened(0.35))
	var y := POST_H - 0.22
	for w in ways:
		var way: Dictionary = w
		var dir: Vector2 = way["dir"]
		# the arm's own frame: +x out along the road, +z across it, y up; in this node's space,
		# which is never turned (the post takes its turn from the arms, not from the scatter row)
		var arm := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(0.0, y, 0.0))
		fabric.box("joinery", arm * Transform3D(Basis(), Vector3(ARM_LEN * 0.5 + 0.05, 0.0, 0.0)),
				Vector3(ARM_LEN - 0.1, ARM_H, ARM_T), PAINT)
		# the pointed end: a square turned on its corner, half of it past the arm's end
		fabric.box("joinery", arm * Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(ARM_LEN, 0.0, 0.0)),
				Vector3(ARM_H * 0.707, ARM_H * 0.707, ARM_T), PAINT)
		_label(arm, str(way.get("name", "")))
		y -= ARM_STEP
	var mesh := fabric.commit(self, "joinery", FabricMesh.joinery_material(), "Timber")
	if mesh != null:
		FabricMesh.near_only(mesh, FabricMesh.PROP_RANGE_M, true)


## The place's name on both faces of an arm, reading from the post outward on one side and from
## the tip inward on the other, so it reads left to right from either side.
func _label(arm: Transform3D, text: String) -> void:
	if text == "":
		return
	for side_v in [1.0, -1.0]:
		var side := float(side_v)
		var label := Label3D.new()
		label.name = "Way"
		label.text = text
		label.font_size = 26
		label.pixel_size = 0.0028
		label.modulate = LETTERING
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visibility_range_end = LABEL_RANGE_M
		var face := Basis() if side > 0.0 else Basis(Vector3.UP, PI)
		label.transform = arm * Transform3D(face, Vector3(ARM_LEN * 0.52, 0.0, side * (ARM_T * 0.5 + 0.004)))
		add_child(label)


## What the arms say, top to bottom.
func names() -> Array[String]:
	var out: Array[String] = []
	for w in ways:
		out.append(str((w as Dictionary).get("name", "")))
	return out
