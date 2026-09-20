class_name Greetings
extends RefCounted
## Greetings: the personality x standing matrix (DESIGN §5.9). Picks the first line an NPC says
## when you walk up, from how well known you are, what the Hearth/Hollow axis has done to your
## face, your rank and bounty, what this one saw you do, what the village is currently saying,
## the hour, and what you are wearing.
##
## Data: core:table/greetings (game/content/packs/core/dialogues/greetings.json). A row is:
##   {id, lines[], weight?, traits[]?, renown_tier[min,max]?, morality_tier[min,max]?,
##    faction?, faction_rank_min?, rep_min?, rep_max?, bounty_min?, witnessed?, knows_deed?,
##    time[from,to]?, wearing_tag?, disposition_min?, disposition_max?, place?, region?, npc?,
##    flag?, conditions[]?}
## Every constraint a row states must hold. The most specific matching row wins; weight breaks
## ties, and a row's several lines keep a shopkeeper from greeting you the same way twice.
##
## `conditions` takes the full docs/CONTRACTS.md §7 vocabulary, so the writer stream can hang a
## greeting on anything dialogue can test.

const TABLE := "core:table/greetings"

static var _last_line: Dictionary = {}     # npc_id -> last line said
static var _dialogue_rows: Array = []
static var _dialogue_rows_built := false


## The line this NPC greets the player with. Returns "" only when the table is missing.
static func greet(npc_id: String, ctx: SocialContext) -> String:
	var row := select_row(npc_id, ctx)
	if row.is_empty():
		return ""
	return ctx.substitute(pick_line(row, npc_id, ctx))


## The chosen row, for tests and for tools that want to know why a line was said.
static func select_row(npc_id: String, ctx: SocialContext) -> Dictionary:
	var rows := table_rows()
	if rows.is_empty():
		Log.error("Greetings", "%s is missing or has no rows" % TABLE)
		return {}
	var best_score := -1.0
	var best: Array[Dictionary] = []
	for row in rows:
		var score := _score(row, npc_id, ctx)
		if score < 0.0:
			continue
		if score > best_score + 0.0001:
			best_score = score
			best = [row]
		elif absf(score - best_score) <= 0.0001:
			best.append(row)
	if best.is_empty():
		return {}
	if best.size() == 1:
		return best[0]
	return _weighted_pick(best, ctx)


static func table_rows() -> Array:
	var table := ContentDB.get_or_empty(TABLE)
	var rows: Variant = table.get("rows", [])
	var base: Array = rows if typeof(rows) == TYPE_ARRAY else []
	return base + dialogue_rows()


## Greetings written next to the conversation they belong to. Every dialogue in the pack
## carries a `greetings` array of `{conditions, text}` — a hundred and forty-seven lines of
## them — and nothing had ever read one: `Greetings` only looked at `core:table/greetings`, so
## the most specific writing in the pack, the lines that know this particular miller's water
## has come back, were dead data.
##
## They become ordinary rows here, with the `npc` of whoever the dialogue belongs to. That
## makes them the most specific match whenever their conditions hold, which is the right
## answer: a line written for this person and this moment should beat the personality matrix.
static func dialogue_rows() -> Array:
	if _dialogue_rows_built:
		return _dialogue_rows
	_dialogue_rows_built = true
	_dialogue_rows = []
	var speaker: Dictionary = {}
	for npc in ContentDB.all("npc"):
		var d := str((npc as Dictionary).get("dialogue", ""))
		if d != "":
			speaker[d] = str((npc as Dictionary).get("id", ""))
	for entry in ContentDB.all("dialogue"):
		var dialogue: Dictionary = entry
		var lines: Variant = dialogue.get("greetings", [])
		if typeof(lines) != TYPE_ARRAY:
			continue
		var who := str(speaker.get(str(dialogue.get("id", "")), ""))
		if who == "":
			continue      # a dialogue nobody owns has nobody to greet you with it
		for i in range((lines as Array).size()):
			var g: Dictionary = (lines as Array)[i]
			var text := str(g.get("text", ""))
			if text.is_empty():
				continue
			_dialogue_rows.append({
				"id": "%s#greeting%d" % [str(dialogue.get("id", "?")), i],
				"npc": who, "lines": [text],
				"conditions": g.get("conditions", []),
				"weight": float(g.get("weight", 1.0)),
			})
	return _dialogue_rows


## How much each kind of constraint counts towards a row being the most specific match. What a
## villager has personally seen beats what the village is saying, which beats your standing and
## the hour, which beat their personality: a timid neighbour who watched you rob a house does not
## greet you timidly, they greet you as a witness.
const W_NPC := 4
const W_SEEN := 3
const W_STANDING := 2
const W_TRAIT := 1


## -1 when the row does not apply; otherwise how specific it is (constraints met) plus its weight.
static func _score(row: Dictionary, npc_id: String, ctx: SocialContext) -> float:
	var specificity := 0

	if row.has("npc"):
		if str(row["npc"]) != npc_id:
			return -1.0
		specificity += W_NPC

	if row.has("traits"):
		var traits := _traits_for(npc_id, ctx)
		var hit := false
		for t in row["traits"]:
			if traits.has(str(t)):
				hit = true
				break
		if not hit:
			return -1.0
		specificity += W_TRAIT

	# A tier row only counts as specific when the tier it matched is a notable one. Rows that
	# describe an unremarkable stranger are fallbacks, not answers.
	if row.has("renown_tier"):
		var span: Array = row["renown_tier"]
		var tier := ctx.renown_tier()
		if tier < int(span[0]) or tier > int(span[span.size() - 1]):
			return -1.0
		if tier > 0:
			specificity += W_STANDING

	if row.has("morality_tier"):
		var span: Array = row["morality_tier"]
		var tier := ctx.morality_tier()
		if tier < int(span[0]) or tier > int(span[span.size() - 1]):
			return -1.0
		if tier != 0:
			specificity += W_STANDING

	var faction := str(row.get("faction", _faction_of(npc_id, ctx)))
	if row.has("faction_rank_min"):
		if faction == "" or not ctx.is_member(faction) or ctx.faction_rank(faction) < int(row["faction_rank_min"]):
			return -1.0
		specificity += W_STANDING
	if row.has("rep_min"):
		if faction == "" or ctx.reputation(faction) < int(row["rep_min"]):
			return -1.0
		specificity += 1
	if row.has("rep_max"):
		if faction == "" or ctx.reputation(faction) > int(row["rep_max"]):
			return -1.0
		specificity += 1

	if row.has("bounty_min"):
		var law := _law_faction(npc_id, ctx)
		if law == "" or ctx.bounty(law) < int(row["bounty_min"]):
			return -1.0
		specificity += W_SEEN

	if row.has("witnessed"):
		var saw := ctx.npc_witnessed(npc_id) != ""
		if saw != bool(row["witnessed"]):
			return -1.0
		specificity += W_NPC if saw else 0

	if row.has("knows_deed"):
		if not ctx.knows_deed(ctx.place_id, str(row["knows_deed"])):
			return -1.0
		specificity += W_SEEN

	if row.has("time"):
		var span: Array = row["time"]
		if not Conditions.in_hour_window(float(ctx.hour()), float(span[0]), float(span[1])):
			return -1.0
		specificity += W_STANDING

	if row.has("wearing_tag"):
		if not ctx.wearing_tag(str(row["wearing_tag"])):
			return -1.0
		specificity += W_SEEN

	if row.has("disposition_min"):
		if ctx.disposition(npc_id) < int(row["disposition_min"]):
			return -1.0
		specificity += 1
	if row.has("disposition_max"):
		if ctx.disposition(npc_id) > int(row["disposition_max"]):
			return -1.0
		specificity += 1

	if row.has("place"):
		if ctx.place_id != str(row["place"]):
			return -1.0
		specificity += W_STANDING
	if row.has("region"):
		if ctx.region_id() != str(row["region"]):
			return -1.0
		specificity += 1
	if row.has("flag"):
		if not ctx.has_flag(str(row["flag"])):
			return -1.0
		specificity += 1

	if row.has("conditions"):
		if not Conditions.all_of(row["conditions"], ctx):
			return -1.0
		specificity += W_STANDING

	return float(specificity) + float(row.get("weight", 1.0))


static func _weighted_pick(rows: Array[Dictionary], ctx: SocialContext) -> Dictionary:
	var total := 0.0
	for r in rows:
		total += maxf(0.01, float(r.get("weight", 1.0)))
	var roll := ctx.rng.randf() * total
	for r in rows:
		roll -= maxf(0.01, float(r.get("weight", 1.0)))
		if roll <= 0.0:
			return r
	return rows[rows.size() - 1]


## A line from the row, avoiding the one this NPC said last time.
static func pick_line(row: Dictionary, npc_id: String, ctx: SocialContext) -> String:
	var lines: Array = row.get("lines", [])
	if lines.is_empty():
		return ""
	var last := str(_last_line.get(npc_id, ""))
	var options: Array = []
	for l in lines:
		if str(l) != last:
			options.append(str(l))
	if options.is_empty():
		options = lines.duplicate()
	var chosen := str(options[ctx.rng.randi() % options.size()])
	_last_line[npc_id] = chosen
	return chosen


static func forget(npc_id: String = "") -> void:
	if npc_id == "":
		_last_line.clear()
		# The pack can be reloaded between tests, so the synthesised rows go with the memory.
		_dialogue_rows.clear()
		_dialogue_rows_built = false
	else:
		_last_line.erase(npc_id)


static func _traits_for(npc_id: String, ctx: SocialContext) -> Array:
	if ctx.npc_id == npc_id and not ctx.npc.is_empty():
		return ctx.npc_traits()
	var pers: Variant = ContentDB.get_or_empty(npc_id).get("personality", {})
	if typeof(pers) == TYPE_DICTIONARY:
		var t: Variant = (pers as Dictionary).get("traits", [])
		return t if typeof(t) == TYPE_ARRAY else []
	if typeof(pers) == TYPE_ARRAY:
		return pers
	return []


static func _faction_of(npc_id: String, ctx: SocialContext) -> String:
	if ctx.npc_id == npc_id and ctx.npc.has("faction"):
		return str(ctx.npc["faction"])
	return str(ContentDB.get_or_empty(npc_id).get("faction", ""))


## Who polices where this NPC lives (for bounty-flavoured greetings).
static func _law_faction(npc_id: String, ctx: SocialContext) -> String:
	var factions := ctx.provider("factions")
	var region := ctx.region_id()
	if region == "":
		var home := str(ContentDB.get_or_empty(npc_id).get("home_place", ctx.place_id))
		region = str(ContentDB.get_or_empty(home).get("region", ""))
	if factions != null and factions.has_method("law_faction_for_region"):
		return str(factions.call("law_faction_for_region", region))
	return str(ContentDB.get_or_empty(region).get("law_faction", ""))
