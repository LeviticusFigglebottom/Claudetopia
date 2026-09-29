class_name PoiPreview
extends RefCounted
## A point of interest stood up where its def says, before the world is built again.
##
## The world build flattens a pad for every POI and writes where it stands to
## world/generated/pois.json; the dressing is raised on that pad. A POI written after the last
## build has no pad and no entry, and one moved since has its pad where it used to be. Building
## the world again takes over an hour, so a region's author sees their places here instead:
##
## * every POI def the built world has no entry for (`auto`), and every POI asked for by id
##   (`ask`, `--preview-pois=a,b` on the command line, WICKMERE_PREVIEW_POIS=a,b in the
##   environment, a capture plan's "preview_pois"), is given an entry at its def's position;
## * a pad is laid for it on the ground as the game holds it (TerrainProvider.lay_pad: Terrain3D's
##   heights and the runtime map alike), the build's shape of pad: level to PAD_LEVEL of its
##   radius at the median of the ground under it, blended back into the land over PAD_SKIRT
##   radii past that (tools/world/worldgen/roads.py, apply_pads; without the tilt and roll a
##   built pad keeps of the land's lie);
## * the cells' scatter inside the pad is cleared as the build clears it, and what stands on its
##   skirt is let down or lifted with the ground (`clear_cell`).
##
## It is a preview, good enough to judge a place by. The build stays the source of truth: its
## pad also answers the roads, the sightlines and the water, which this does not, and the next
## build's entry replaces this one (an entry in pois.json is never previewed unless asked for).
## docs/WORLD_LIFE.md says how a region's author uses it.

## tools/world/worldgen/roads.py: PAD_DEFAULT, CAMP_PAD_M, WAYSIDE_PAD_M, PAD_LEVEL, PAD_SKIRT.
const PAD_DEFAULT := 25.0
const CAMP_PAD_M := 22.0
const WAYSIDE_PAD_M := 14.0
const PAD_LEVEL := 0.7
const PAD_SKIRT := 0.9
## The build clears its scatter to the pad's radius (worldgen/cells.py keep_discs).
const CLEAR_SHARE := 1.0
const ENV := "WICKMERE_PREVIEW_POIS"
const ARG := "--preview-pois="

## Stand up every POI the built world has no entry for. A test that wants the built world alone
## turns it off.
static var auto := true
## The pads laid this run: [{id, x, z, level, radius, level_radius, reach}]. Read by the cell
## loader's worker threads, so it is only ever replaced whole, never changed in place.
static var pads: Array = []
static var _asked: Array[String] = []


## Asks for these POIs (full ids or short names) to be previewed at their def's position even when
## the built world has them: a POI moved or resized since the build. Before the world stands.
static func ask(ids: Array) -> void:
	for i in ids:
		var s := str(i).strip_edges()
		if s != "" and not _asked.has(s):
			_asked.append(s)


## Everything asked for: by `ask`, on the command line and in the environment.
static func asked() -> Array[String]:
	var out: Array[String] = _asked.duplicate()
	var more: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with(ARG):
			more.append_array(a.substr(ARG.length()).split(",", false))
	more.append_array(OS.get_environment(ENV).split(",", false))
	for s in more:
		if not out.has(s.strip_edges()):
			out.append(s.strip_edges())
	return out


static func clear() -> void:
	_asked.clear()
	pads = []


## The pad a POI def gets from the build (roads.pad_radius): its own `pad_radius_m`, a wayside
## find's small one, a camp's, or the default.
static func pad_radius(def: Dictionary) -> float:
	if float(def.get("pad_radius_m", 0.0)) > 0.0:
		return float(def["pad_radius_m"])
	if bool(def.get("wayside", false)):
		return WAYSIDE_PAD_M
	if str(def.get("kind", "")) == "camp":
		return CAMP_PAD_M
	return PAD_DEFAULT


## The POI defs to preview against a built world's entries: those it lacks (when `auto`), and those
## asked for.
static func wanted(built: Array) -> Array[Dictionary]:
	var have := {}
	for e in built:
		if e is Dictionary:
			have[str((e as Dictionary).get("place_id", ""))] = true
	var want := asked()
	var out: Array[Dictionary] = []
	for def_v in ContentDB.all("poi"):
		var def: Dictionary = def_v
		var id := str(def.get("id", ""))
		if id == "" or WorldProbe.xz_of(def) == Vector2.ZERO:
			continue
		var forced := want.has(id) or want.has(Ids.name_of(id))
		if forced or (auto and not have.has(id)):
			out.append(def)
	return out


## The pad for one def on the ground as it stands: level at the median of the ground within three
## quarters of its radius, as the build takes it.
static func pad_for(def: Dictionary, terrain: TerrainProvider) -> Dictionary:
	var xz := WorldProbe.xz_of(def)
	var r := pad_radius(def)
	var heights: Array[float] = []
	var step := 2.0
	var n := int(ceil(r * 0.75 / step))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var dx := i * step
			var dz := j * step
			if dx * dx + dz * dz <= (r * 0.75) * (r * 0.75):
				heights.append(terrain.get_height(xz.x + dx, xz.y + dz) if terrain != null else 0.0)
	heights.sort()
	var level := heights[int(heights.size() * 0.5)] if not heights.is_empty() else 0.0
	var level_r := PAD_LEVEL * r
	return {"id": str(def.get("id", "")), "x": xz.x, "z": xz.y, "level": level, "radius": r,
		"level_radius": level_r, "reach": level_r + PAD_SKIRT * r}


## The built world's entries with the previewed ones in: a pad laid for each and its entry put in
## (in place of the built one, for one asked for). Returns the new list; `built` is left as it was.
static func apply(built: Array, terrain: TerrainProvider) -> Array:
	var defs := wanted(built)
	if defs.is_empty():
		pads = []
		return built
	var laid: Array = []
	for def in defs:
		laid.append(pad_for(def, terrain))       # every level from the ground before any pad
	var ids := {}
	for p: Dictionary in laid:
		ids[p["id"]] = true
		if terrain != null:
			terrain.lay_pad(float(p["x"]), float(p["z"]), float(p["level"]), float(p["level_radius"]), float(p["reach"]))
	if terrain != null:
		terrain.commit_pads()
	pads = laid
	var out: Array = []
	for e in built:
		if not (e is Dictionary and ids.has(str((e as Dictionary).get("place_id", "")))):
			out.append(e)
	for p: Dictionary in laid:
		out.append(entry(p))
	var names := PackedStringArray()
	for k: String in ids:
		names.append(Ids.name_of(k))
	Log.info("PoiPreview", "%d point(s) of interest stood up ahead of the build, each on a pad laid now: %s"
			% [laid.size(), ", ".join(names)])
	return out


## A pois.json entry for a pad laid here, marked `preview`.
static func entry(p: Dictionary) -> Dictionary:
	return {"place_id": p["id"], "pos": [p["x"], p["level"], p["z"]], "yaw": 0.0,
		"radius_flat_m": p["radius"], "radius_level_m": p["level_radius"], "preview": true}


## The weight of a pad at `d` metres from its middle: 1 on its level core, 0 past its reach.
static func weight(p: Dictionary, d: float) -> float:
	return 1.0 - smoothstep(float(p["level_radius"]), float(p["reach"]), d)


## A cell's scatter as the pads leave it: nothing inside a pad's radius, and what stands on a
## skirt moved with the ground under it. On the cell loader's worker thread (WorldStreamer).
static func clear_cell(data: Dictionary) -> void:
	var laid := pads
	if laid.is_empty():
		return
	var inst: Variant = data.get("instances", null)
	if not (inst is Dictionary):
		return
	for path in (inst as Dictionary).keys():
		var rows: Array = inst[path]
		var kept: Array = []
		var changed := false
		for row_v in rows:
			var row: Array = row_v
			var x := float(row[0])
			var z := float(row[2])
			var drop := false
			for p: Dictionary in laid:
				var d := Vector2(x - float(p["x"]), z - float(p["z"])).length()
				if d >= float(p["reach"]):
					continue
				if d < float(p["radius"]) * CLEAR_SHARE:
					drop = true
					break
				row[1] = lerpf(float(row[1]), float(p["level"]), weight(p, d))
				changed = true
			if drop:
				changed = true
				continue
			kept.append(row)
		if changed:
			inst[path] = kept
