class_name HouseKit
extends RefCounted
## One house of the fabric, built into the settlement's shared meshes.
##
## A settlement's houses were one white box each with a thatch lid: the same wash, a door and a
## row of windows on the street side, nothing on the others, and no way to tell a smithy from a
## cottage or a Vale village from a lake town. This is the rest of what a house is from the
## street, by region and by trade:
##
## * the wall it is built of: plaster over a timber frame, cob in a coloured wash, rubble stone,
##   tarred weatherboard, laid logs, drystone -- each region its own few, in its own colours;
## * the frame, where there is one: posts at the bays, rails at the floors, a king post and
##   braces in the gable, in dark oak against the plaster;
## * windows on every side, because a house is lived in all the way round;
## * a porch or a door hood, stilts in the fen, a jettied upper floor in the lake city;
## * a chimney at the hearth end, and where it smokes (`chimneys` in the result: the caller
##   hands them to ChimneySmoke);
## * for a trade, the iron bracket its sign hangs from over the street (`sign` in the result:
##   the caller hangs the trade's emblem on it).
##
## Everything goes into the fabric's shared keys ("wall", "wall_alt", "roof", "stone",
## "joinery"), so a street of forty houses is still one draw a surface.

const STOREY_M := 2.6
const EAVES_M := 0.5
const FRAME_W := 0.17
const FRAME_PROUD := 0.05

## What each culture builds its houses of, and how often. `wall` is the surface key the walls go
## in: "wall" is the culture's own (the interior's wall surface), "wall_alt" its stone.
## `tints` multiply the surface's colour: a limewash in a bucket of ochre, a Suffolk pink, a
## lake-town blue. `frame` puts a timber frame on it, `porch` says what shelters the door.
const STYLES := {
	"vale": [
		{"style": "framed", "weight": 4, "wall": "wall", "frame": true, "porch": "hood",
		 "tints": [[1.0, 1.0, 1.0], [1.0, 0.86, 0.62], [1.0, 0.8, 0.74], [0.96, 0.92, 0.82]]},
		{"style": "cob", "weight": 4, "wall": "wall", "frame": false, "porch": "hood",
		 "tints": [[1.0, 1.0, 1.0], [1.0, 0.82, 0.52], [1.0, 0.76, 0.7], [0.9, 0.94, 0.86]]},
		{"style": "flint", "weight": 2, "wall": "wall_alt", "frame": false, "porch": "",
		 "tints": [[1.0, 1.0, 1.0], [0.92, 0.9, 0.86]]},
	],
	"lakefolk": [
		{"style": "render", "weight": 5, "wall": "wall", "frame": false, "porch": "canopy",
		 "stone_ground": true, "tints": [[0.74, 0.84, 1.0], [1.0, 0.84, 0.56], [1.0, 0.76, 0.72],
				[0.82, 0.92, 0.8], [1.0, 1.0, 1.0]]},
		{"style": "framed", "weight": 2, "wall": "wall", "frame": true, "porch": "canopy",
		 "tints": [[1.0, 1.0, 1.0], [0.95, 0.95, 0.9]]},
		{"style": "ashlar", "weight": 2, "wall": "wall_alt", "frame": false, "porch": "canopy",
		 "tints": [[1.0, 1.0, 1.0], [0.94, 0.92, 0.88]]},
	],
	"reedfolk": [
		{"style": "boarded", "weight": 5, "wall": "wall", "frame": false, "porch": "steps",
		 "stilts": [0.7, 1.3], "tints": [[1.0, 1.0, 1.0], [0.62, 0.6, 0.58], [0.9, 0.84, 0.78]]},
	],
	"woodfolk": [
		{"style": "log", "weight": 5, "wall": "wall", "frame": false, "porch": "posts",
		 "tints": [[1.0, 1.0, 1.0], [0.86, 0.84, 0.8], [0.95, 0.88, 0.8]]},
		{"style": "boarded", "weight": 1, "wall": "wall_alt", "frame": false, "porch": "posts",
		 "tints": [[1.0, 1.0, 1.0]]},
	],
	"clans": [
		{"style": "drystone", "weight": 5, "wall": "wall", "frame": false, "porch": "",
		 "long": true, "tints": [[1.0, 1.0, 1.0], [0.9, 0.9, 0.88], [0.96, 0.94, 0.9]]},
	],
	"pilgrims": [
		{"style": "ashstone", "weight": 5, "wall": "wall", "frame": false, "porch": "",
		 "tints": [[1.0, 1.0, 1.0], [0.92, 0.9, 0.88]]},
	],
}

## The stone a culture builds its stone houses of, in the painted surface's own terms.
const STONE_WALL := {
	# knapped flint in lime: small dark stones in a pale bed, not a wall of blocks
	"vale": {"pattern": 2, "base": "#8e8b86", "accent": "#555961", "grout": "#e2dac6", "unit": 0.1},
	"lakefolk": {"pattern": 2, "base": "#c9c0ae", "accent": "#a89f8e", "grout": "#6e685e", "unit": 0.42},
	"reedfolk": {"pattern": 1, "base": "#6f6353", "accent": "#4f463a", "grout": "#2e2921", "unit": 0.24},
	"woodfolk": {"pattern": 1, "base": "#6b5a42", "accent": "#4a3d2b", "grout": "#2a2117", "unit": 0.28},
	"clans": {"pattern": 2, "base": "#9d988d", "accent": "#7a766c", "grout": "#4f4c46", "unit": 0.34},
	"pilgrims": {"pattern": 2, "base": "#a5a099", "accent": "#857f78", "grout": "#57534d", "unit": 0.5},
}

## A Vale door is painted for the trade behind it (the region's own identity says so: "painted
## doors by trade (blue miller, red smith, green grower, yellow brewer)"): Mullard's Yellow Door
## is the brewer's, and the red door at the forge is the smith's.
const VALE_DOOR_PAINT := {
	"miller": Color(0.24, 0.36, 0.58), "smith": Color(0.58, 0.16, 0.12),
	"farmer": Color(0.2, 0.4, 0.22), "grower": Color(0.2, 0.4, 0.22), "brewer": Color(0.78, 0.62, 0.16),
}


## The joinery a door is made of: the culture's timber, with the panel painted where the Vale
## paints it for the trade.
static func door_timber(culture: String, trade: String) -> Dictionary:
	var timber := Building.timber_tints(culture)
	if culture == "vale" and VALE_DOOR_PAINT.has(trade):
		timber = timber.duplicate()
		timber["panel"] = VALE_DOOR_PAINT[trade]
	return timber


## The frame's timber: dark oak against plaster, weathered grey on the lake.
const FRAME_TINT := {
	"vale": Color(0.24, 0.17, 0.11), "lakefolk": Color(0.3, 0.26, 0.22),
	"woodfolk": Color(0.3, 0.22, 0.14), "reedfolk": Color(0.28, 0.23, 0.18),
	"clans": Color(0.3, 0.26, 0.22), "pilgrims": Color(0.3, 0.28, 0.25),
}


## One style for a house of `culture`, drawn by weight.
static func pick_style(culture: String, rng: RandomNumberGenerator) -> Dictionary:
	var styles: Array = STYLES.get(culture, STYLES["vale"])
	var total := 0
	for s in styles:
		total += int((s as Dictionary).get("weight", 1))
	var roll := rng.randi_range(1, maxi(total, 1))
	for s in styles:
		roll -= int((s as Dictionary).get("weight", 1))
		if roll <= 0:
			return s
	return styles[0]


static func pick_tint(style: Dictionary, rng: RandomNumberGenerator) -> Color:
	var tints: Array = style.get("tints", [[1.0, 1.0, 1.0]])
	var t: Array = tints[rng.randi_range(0, tints.size() - 1)]
	# a little of the bucket's own drift on top of the colour, so two ochre houses differ too
	var k := rng.randf_range(-0.035, 0.035)
	return Color(clampf(float(t[0]) + k, 0.0, 1.0), clampf(float(t[1]) + k, 0.0, 1.0),
			clampf(float(t[2]) + k * 0.8, 0.0, 1.0))


## Builds one house. `at` is the house frame: origin on the ground at the middle of the
## footprint, x along the front, -z out of the front door. `spec` carries w, d, storeys,
## culture, style (a STYLES row), tint, stone (tint), roof (Building.ROOF_BY_CULTURE row),
## trade, home (somebody in after dark), standing (false: a ruin), jetty, stilts.
## Returns {door, lamp, chimneys, glows, sign, wall_key} in `at`'s parent space.
static func build(fabric: FabricMesh, at: Transform3D, spec: Dictionary, rng: RandomNumberGenerator,
		lights: RandomNumberGenerator) -> Dictionary:
	var w := float(spec.get("w", 7.0))
	var d := float(spec.get("d", 6.0))
	var storeys := int(spec.get("storeys", 1))
	var culture := str(spec.get("culture", "vale"))
	var style: Dictionary = spec.get("style", {})
	var wall_key := str(style.get("wall", "wall"))
	var tint: Color = spec.get("tint", Color.WHITE)
	var stone: Color = spec.get("stone", Color.WHITE)
	var roof: Dictionary = spec.get("roof", {})
	var standing := bool(spec.get("standing", true))
	var home := bool(spec.get("home", false))
	var timber := Building.timber_tints(culture)
	var out := {"door": Vector3.ZERO, "lamp": Vector3.INF, "chimneys": [], "glows": [],
			"sign": null, "wall_key": wall_key, "body": []}

	# what the house stands on: a course of stone, or posts over the wet ground
	var lift := 0.0
	var stilts: Array = style.get("stilts", [])
	if stilts.size() == 2:
		lift = rng.randf_range(float(stilts[0]), float(stilts[1]))
		_stilts(fabric, at, w, d, lift, timber, stone)
	else:
		var plinth_h := rng.randf_range(0.28, 0.5)
		fabric.box("stone", at * Transform3D(Basis(), Vector3(0.0, plinth_h * 0.5 - 0.14, 0.0)),
				Vector3(w + 0.3, plinth_h, d + 0.3), stone)
	var base := at * Transform3D(Basis(), Vector3(0.0, lift, 0.0))
	var h := STOREY_M * storeys
	out["body"] = [base * Vector3(0.0, h * 0.5, 0.0), Vector3(w, h + lift * 2.0, d)]

	# the walls: a stone ground floor under render in the lake towns, a jettied upper floor
	var jetty := 0.45 if bool(spec.get("jetty", false)) and storeys >= 2 else 0.0
	if bool(style.get("stone_ground", false)) and storeys >= 2:
		fabric.box("wall_alt", base * Transform3D(Basis(), Vector3(0.0, STOREY_M * 0.5, 0.0)),
				Vector3(w, STOREY_M, d), stone)
		var up := h - STOREY_M
		fabric.box(wall_key, base * Transform3D(Basis(), Vector3(0.0, STOREY_M + up * 0.5, -jetty * 0.5)),
				Vector3(w, up, d + jetty), tint)
	elif jetty > 0.0:
		fabric.box(wall_key, base * Transform3D(Basis(), Vector3(0.0, STOREY_M * 0.5, 0.0)),
				Vector3(w, STOREY_M, d), tint)
		var up2 := h - STOREY_M
		fabric.box(wall_key, base * Transform3D(Basis(), Vector3(0.0, STOREY_M + up2 * 0.5, -jetty * 0.5)),
				Vector3(w, up2, d + jetty), tint)
	else:
		fabric.box(wall_key, base * Transform3D(Basis(), Vector3(0.0, h * 0.5, 0.0)), Vector3(w, h, d), tint)
	if jetty > 0.0:
		# the joist ends under the overhang, which is what says "jetty" from the street
		var n := int(w / 0.55)
		for i in range(n):
			var x := -w * 0.5 + (float(i) + 0.5) * w / float(n)
			fabric.box("joinery", base * Transform3D(Basis(), Vector3(x, STOREY_M - 0.08, -d * 0.5 - jetty * 0.5)),
					Vector3(0.14, 0.16, jetty + 0.1), timber["lintel"])
	if not standing:
		return out

	# the roof over the whole length, the front eave carried out over the jetty
	var pitch := float(roof.get("pitch", 1.0))
	var thick := float(roof.get("thick", 0.2))
	var dd := d + jetty
	var shift := -jetty * 0.5
	var span := dd + EAVES_M * 2.0
	var length := w + EAVES_M * 2.0
	var rise := span * 0.5 * pitch
	var apex := h + dd * 0.5 * pitch
	for end_v in [1.0, -1.0]:
		var e := float(end_v)
		var a := base * Vector3(e * w * 0.5, h, shift - dd * 0.5)
		var b := base * Vector3(e * w * 0.5, h, shift + dd * 0.5)
		var c := base * Vector3(e * w * 0.5, apex, shift)
		if e > 0.0:
			fabric.tri(wall_key, a, b, c, tint)
		else:
			fabric.tri(wall_key, b, a, c, tint)
	var slope := sqrt(span * span * 0.25 + rise * rise)
	var angle := atan2(rise, span * 0.5)
	var eaves := base * Transform3D(Basis(), Vector3(0.0, h, shift))
	var roof_tint := Color(1.0, 1.0, 1.0).darkened(rng.randf_range(0.0, 0.12))
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		var normal := Vector3(0.0, span * 0.5, side * rise).normalized()
		var mid := Vector3(0.0, rise * 0.5, side * span * 0.25)
		var local := Transform3D(Basis(Vector3.RIGHT, side * angle), mid - normal * (thick * 0.5))
		fabric.box("roof", eaves * local, Vector3(length, thick, slope + thick * 0.6), roof_tint)
	if bool(roof.get("ridge", false)):
		fabric.box("roof", eaves * Transform3D(Basis(), Vector3(0.0, rise - thick * 0.25, 0.0)),
				Vector3(length * 0.98, thick * 0.9, thick * 2.2), Building.accent_tint(roof) * roof_tint)

	# the frame, where the house has one
	var slots := window_slots(w)
	if bool(style.get("frame", false)):
		_frame(fabric, base, w, d, storeys, jetty, pitch, slots, FRAME_TINT.get(culture, Color(0.25, 0.18, 0.12)))

	# the chimney at the hearth end, against the gable, and a second on a long house
	var hearth := 1.0 if rng.randf() < 0.5 else -1.0
	var top := h + rise + 0.8
	var stack := Vector3(hearth * (w * 0.5 + 0.16), top * 0.5, shift)
	fabric.box("stone", base * Transform3D(Basis(), stack), Vector3(0.72, top, 0.72), stone)
	fabric.box("stone", base * Transform3D(Basis(), Vector3(stack.x, top + 0.05, shift)), Vector3(0.86, 0.12, 0.86), stone.darkened(0.15))
	(out["chimneys"] as Array).append(base * Vector3(stack.x, top + 0.12, shift))
	if bool(style.get("long", false)) or w > 11.0:
		var inner := Vector3(-hearth * w * 0.22, h + rise * 0.55 + 0.9, shift)
		fabric.box("stone", base * Transform3D(Basis(), Vector3(inner.x, (inner.y + h) * 0.5 + 0.3, shift)),
				Vector3(0.62, inner.y - h + 0.6, 0.62), stone)
		(out["chimneys"] as Array).append(base * Vector3(inner.x, inner.y + 0.6, shift))

	# the door, in one of the bays, and what shelters it
	var door_slot := rng.randi_range(0, slots.size() - 1)
	var door_x: float = slots[door_slot]
	var front := at * Transform3D(Basis(Vector3.UP, PI), Vector3(door_x, lift, -d * 0.5))
	# a cottage with no trade of its own in the Vale is as often as not a grower's
	var paint_for := str(spec.get("trade", ""))
	if paint_for == "" and culture == "vale" and rng.randf() < 0.3:
		paint_for = "grower"
	Building.door_at(fabric, front, door_timber(culture, paint_for), stone)
	out["door"] = at * Vector3(door_x, lift, -d * 0.5)
	_porch(fabric, front, str(style.get("porch", "")), timber, roof_tint, lift)
	if home:
		out["lamp"] = at * Vector3(door_x, lift + 2.3, -d * 0.5 - 0.6)

	# windows on every side: every bay of the front and back, a window or two in each gable
	for s in range(storeys):
		var cy := lift + STOREY_M * float(s) + 1.45
		var front_z := -d * 0.5 - (jetty if s >= 1 else 0.0)
		for i in range(slots.size()):
			if s == 0 and i == door_slot:
				continue
			var face := at * Transform3D(Basis(Vector3.UP, PI), Vector3(slots[i], cy, front_z))
			_window(fabric, face, timber, stone, s == 0, _lit(lights, home, s == 0), out)
		for i in range(slots.size()):
			var back := at * Transform3D(Basis(), Vector3(slots[i], cy, d * 0.5))
			_window(fabric, back, timber, stone, false, _lit(lights, home, s == 0), out)
		for e_v in [1.0, -1.0]:
			var e := float(e_v)
			# beside the chimney at the hearth end (clear of its stack), in the middle of the other
			# gable: a gable a cottage turns to the street was a blank board of wall
			var z := maxf(d * 0.22, 0.92) if e == hearth else 0.0
			if d < (3.2 if e == hearth else 1.8):
				continue
			var gable := at * Transform3D(Basis(Vector3.UP, e * PI * 0.5), Vector3(e * w * 0.5, cy, z))
			_window(fabric, gable, timber, stone, false, _lit(lights, home, true), out)

	# a trade hangs its sign out over the street, on the side of the door away from the corner
	if str(spec.get("trade", "")) != "":
		var sx := door_x + (1.1 if door_x < 0.0 else -1.1)
		# under the eaves of a cottage, above the door's head on anything taller
		out["sign"] = at * Transform3D(Basis(), Vector3(sx, lift + minf(2.75, h - 0.25), -d * 0.5))
		sign_bracket(fabric, out["sign"], timber, false)
	return out


## The bays along a frontage: evenly spaced, two metres or more apart, so a door with its frame
## and a shuttered window can stand side by side without touching.
static func window_slots(w: float) -> Array[float]:
	var out: Array[float] = []
	var n := clampi(int((w - 1.8) / 2.0), 1, 4)
	for i in range(n):
		out.append(-w * 0.5 + 0.9 + (w - 1.8) * (float(i) + 0.5) / float(n))
	return out


static func _lit(lights: RandomNumberGenerator, home: bool, ground_floor: bool) -> float:
	if home and lights.randf() < (0.8 if ground_floor else 0.5):
		return lights.randf_range(0.5, 0.95)
	return 0.0


## A window, and its pane in the list of glows when somebody is in the room behind it.
static func _window(fabric: FabricMesh, face: Transform3D, timber: Dictionary, stone: Color,
		shutters: bool, lit: float, out: Dictionary) -> void:
	var pane := Building.window_at(fabric, face, timber, stone, shutters, lit)
	if lit > 0.0:
		(out["glows"] as Array).append(pane)


## A timber frame on the plaster: a post at every bay and at the corners, a sill over the plinth,
## a rail at each floor and a plate under the eaves, and in each gable a king post with its two
## braces. The members stand a few centimetres proud of the wall, so they throw a line of shadow.
static func _frame(fabric: FabricMesh, base: Transform3D, w: float, d: float, storeys: int,
		jetty: float, pitch: float, slots: Array[float], tint: Color) -> void:
	var h := STOREY_M * storeys
	var bays := slots.size()
	for face_v in [-1.0, 1.0]:
		var face := float(face_v)
		for s in range(storeys):
			var z := face * (d * 0.5 + FRAME_PROUD * 0.5)
			if face < 0.0 and s >= 1:
				z -= jetty
			var y0 := STOREY_M * float(s)
			# a post at each corner and one midway between each pair of bays, clear of the
			# windows' shutters and the door's frame
			var posts: Array[float] = [-w * 0.5 + FRAME_W * 0.5, w * 0.5 - FRAME_W * 0.5]
			for k in range(1, bays):
				posts.append((slots[k - 1] + slots[k]) * 0.5)
			for x in posts:
				fabric.box("joinery", base * Transform3D(Basis(), Vector3(x, y0 + STOREY_M * 0.5, z)),
						Vector3(FRAME_W, STOREY_M, FRAME_PROUD), tint)
			# the rail at the foot of the storey and the one at its head
			fabric.box("joinery", base * Transform3D(Basis(), Vector3(0.0, y0 + 0.08, z)),
					Vector3(w, FRAME_W, FRAME_PROUD), tint)
			fabric.box("joinery", base * Transform3D(Basis(), Vector3(0.0, y0 + STOREY_M - 0.08, z)),
					Vector3(w, FRAME_W, FRAME_PROUD), tint)
	# the gables: corner posts, the rails, and the king post with a brace to each side
	for e_v in [-1.0, 1.0]:
		var e := float(e_v)
		var x := e * (w * 0.5 + FRAME_PROUD * 0.5)
		for s in range(storeys):
			var y0 := STOREY_M * float(s)
			fabric.box("joinery", base * Transform3D(Basis(), Vector3(x, y0 + 0.08, 0.0)),
					Vector3(FRAME_PROUD, FRAME_W, d), tint)
			fabric.box("joinery", base * Transform3D(Basis(), Vector3(x, y0 + STOREY_M - 0.08, 0.0)),
					Vector3(FRAME_PROUD, FRAME_W, d), tint)
		var rise := d * 0.5 * pitch
		fabric.box("joinery", base * Transform3D(Basis(), Vector3(x, h + rise * 0.45, 0.0)),
				Vector3(FRAME_PROUD, rise * 0.9, FRAME_W), tint)
		for side_v in [-1.0, 1.0]:
			var side := float(side_v)
			# from the tie beam a third of the way out up to the king post
			var foot := Vector3(x, h + 0.1, side * d * 0.3)
			var head := Vector3(x, h + rise * 0.55, 0.0)
			var mid := (foot + head) * 0.5
			var run := head - foot
			var reach := run.length()
			var tilt := atan2(run.z, run.y)
			fabric.box("joinery", base * Transform3D(Basis(Vector3.RIGHT, tilt), mid),
					Vector3(FRAME_PROUD, reach, FRAME_W * 0.8), tint)


## What shelters a front door, in the door's own frame (+z out of the wall, y up from its foot).
static func _porch(fabric: FabricMesh, door: Transform3D, kind: String, timber: Dictionary,
		roof_tint: Color, lift: float) -> void:
	match kind:
		"hood":
			# a little gabled hood on two brackets, thatched or tiled like the roof
			for side_v in [-1.0, 1.0]:
				var side := float(side_v)
				fabric.box("joinery", door * Transform3D(Basis(), Vector3(side * 0.78, 2.45, 0.35)),
						Vector3(0.1, 0.12, 0.7), timber["frame"])
				fabric.box("roof", door * Transform3D(Basis(Vector3.FORWARD, side * 0.62),
						Vector3(side * 0.42, 2.78, 0.42)), Vector3(1.0, 0.1, 0.95), roof_tint)
		"canopy":
			# a flat hood on shaped brackets, the lake town's door
			for side_v in [-1.0, 1.0]:
				var side := float(side_v)
				fabric.box("joinery", door * Transform3D(Basis(), Vector3(side * 0.74, 2.42, 0.28)),
						Vector3(0.1, 0.34, 0.5), timber["frame"])
			fabric.box("joinery", door * Transform3D(Basis(), Vector3(0.0, 2.64, 0.36)),
					Vector3(1.9, 0.1, 0.76), timber["lintel"])
		"posts":
			# an open porch: two posts and a lean-to roof out over the step
			for side_v in [-1.0, 1.0]:
				var side := float(side_v)
				fabric.box("joinery", door * Transform3D(Basis(), Vector3(side * 1.05, 1.25, 1.35)),
						Vector3(0.16, 2.5, 0.16), timber["frame"])
			fabric.box("joinery", door * Transform3D(Basis(), Vector3(0.0, 2.52, 1.35)),
					Vector3(2.4, 0.14, 0.16), timber["lintel"])
			fabric.box("roof", door * Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0.0, 2.75, 0.8)),
					Vector3(2.7, 0.1, 1.75), roof_tint)
		"steps":
			# up from the wet ground to a door on stilts
			var n := maxi(int(ceil(lift / 0.22)), 1)
			for i in range(n):
				fabric.box("joinery", door * Transform3D(Basis(), Vector3(0.0, -lift + (float(i) + 0.5) * lift / float(n),
						0.45 + float(n - i) * 0.28)), Vector3(1.1, 0.08, 0.3), timber["frame"])
		_:
			pass


## Posts under a house on the fen, and the platform it stands on.
static func _stilts(fabric: FabricMesh, at: Transform3D, w: float, d: float, lift: float,
		timber: Dictionary, stone: Color) -> void:
	var nx := maxi(int(w / 2.2), 2)
	var nz := maxi(int(d / 2.2), 2)
	for i in range(nx + 1):
		for j in range(nz + 1):
			var x := -w * 0.5 + w * float(i) / float(nx)
			var z := -d * 0.5 + d * float(j) / float(nz)
			fabric.box("joinery", at * Transform3D(Basis(), Vector3(x, lift * 0.5 - 0.2, z)),
					Vector3(0.2, lift + 0.4, 0.2), timber["lintel"])
	fabric.box("joinery", at * Transform3D(Basis(), Vector3(0.0, lift - 0.08, 0.0)),
			Vector3(w + 0.4, 0.16, d + 0.4), timber["frame"])


## An iron-dark bracket out from the wall, and what hangs from it: a painted board on two chains,
## or (`board` false) one chain for the trade's emblem to hang from. `at`: origin on the wall's
## face, -z out of the front toward the street, as the house frame has it.
static func sign_bracket(fabric: FabricMesh, at: Transform3D, timber: Dictionary, board := true) -> void:
	var iron := Color(0.12, 0.11, 0.1)
	var out := at * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	fabric.box("joinery", out * Transform3D(Basis(), Vector3(0.0, 0.0, 0.5)), Vector3(0.06, 0.06, 1.0), iron)
	fabric.box("joinery", out * Transform3D(Basis(Vector3.RIGHT, -0.62), Vector3(0.0, -0.22, 0.28)),
			Vector3(0.05, 0.05, 0.62), iron)
	if not board:
		fabric.box("joinery", out * Transform3D(Basis(), Vector3(0.0, -0.1, 0.62)), Vector3(0.03, 0.2, 0.03), iron)
		return
	for z_v in [0.28, 0.82]:
		fabric.box("joinery", out * Transform3D(Basis(), Vector3(0.0, -0.1, float(z_v))), Vector3(0.03, 0.2, 0.03), iron)
	fabric.box("joinery", out * Transform3D(Basis(), Vector3(0.0, -0.46, 0.55)), Vector3(0.06, 0.52, 0.72), timber["panel"])


## The point an emblem hangs from, at the foot of the bracket's chain: y up, x along the street.
static func emblem_frame(board: Transform3D) -> Transform3D:
	var out := board * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	return out * Transform3D(Basis(), Vector3(0.0, -0.2, 0.62))


## The house's name painted on both faces of the board `sign_bracket` hangs at `at`, so it is read
## from either way along the street. Two labels on `parent`, near-only; nothing when `text` is empty.
static func name_board(parent: Node3D, at: Transform3D, text: String) -> void:
	if text.strip_edges() == "":
		return
	var out := at * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for side_v in [1.0, -1.0]:
		var side := float(side_v)
		var label := Label3D.new()
		label.name = "SignName" if side > 0.0 else "SignNameBack"
		label.text = text
		label.font_size = 30
		label.pixel_size = 0.0024
		label.width = 0.66 / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color(0.93, 0.85, 0.62)
		label.outline_size = 6
		label.outline_modulate = Color(0.16, 0.11, 0.07)
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.visibility_range_end = 45.0
		label.transform = out * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(side * 0.034, -0.46, 0.55))
		parent.add_child(label)


## A notice post: two posts, a board under a little roof of its own, and the notices pinned to
## it. What `JobBoard` wears in a square: it used to wear a signpost, whose arms named nowhere.
## One mesh on `parent`, in the joinery's colours; the board faces the parent's +z.
static func notice_board(parent: Node3D, board_seed: int) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed
	var fabric := FabricMesh.new()
	var wood := Color(0.42, 0.32, 0.22)
	for side_v in [-1.0, 1.0]:
		fabric.box("joinery", Transform3D(Basis(), Vector3(float(side_v) * 0.72, 1.15, 0.0)), Vector3(0.12, 2.3, 0.12), wood.darkened(0.15))
	fabric.box("joinery", Transform3D(Basis(), Vector3(0.0, 1.62, 0.02)), Vector3(1.36, 0.92, 0.06), wood)
	for side_v in [-1.0, 1.0]:
		var side := float(side_v)
		fabric.box("joinery", Transform3D(Basis(Vector3.RIGHT, side * 0.55), Vector3(0.0, 2.28, side * 0.2)),
				Vector3(1.7, 0.05, 0.5), wood.darkened(0.35))
	var papers := [Color(0.92, 0.89, 0.8), Color(0.88, 0.84, 0.72), Color(0.95, 0.93, 0.88)]
	for i in range(rng.randi_range(4, 6)):
		var at := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(1.35, 1.9), 0.057)
		fabric.box("joinery", Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.12, 0.12)), at),
				Vector3(rng.randf_range(0.18, 0.26), rng.randf_range(0.22, 0.32), 0.008),
				papers[rng.randi_range(0, papers.size() - 1)])
	var mesh := fabric.commit(parent, "joinery", FabricMesh.joinery_material(), "NoticeBoard")
	if mesh != null:
		FabricMesh.near_only(mesh, FabricMesh.PROP_RANGE_M, true)
	return mesh
