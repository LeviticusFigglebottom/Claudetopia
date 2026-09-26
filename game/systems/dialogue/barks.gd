class_name Barks
extends RefCounted
## A line somebody says out loud outside a conversation, as a subtitle with their name on it: the
## Warden's shout down the stair, a sergeant's word across the yard as a lesson is done. Pass one
## has no voices (DESIGN §12), so a line is its subtitle; the name is who the player knows them as
## (Npc.shown_name). A line may wait a moment first, on the wall clock.

const SECONDS := 5.0


static func say(npc_id: String, text: String, delay := 0.0, seconds := SECONDS) -> void:
	if text.strip_edges().is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if delay > 0.0:
		await tree.create_timer(delay, true, false, true).timeout
	var hud := UI.hud() if UI != null else null
	if hud == null or not hud.has_method("show_subtitle"):
		return
	var ctx: SocialContext = Social.ctx if Social != null else null
	var line := ctx.substitute(text) if ctx != null else text
	var who := Npc.shown_name(ContentDB.get_or_empty(npc_id), ctx, "")
	hud.call("show_subtitle", ("%s: %s" % [who, line]) if not who.is_empty() else line, seconds)


## Says every line an effect list left in the context (`say`), and forgets them.
static func flush(ctx: SocialContext) -> void:
	if ctx == null:
		return
	for row in ctx.lines:
		say(str(row.get("npc", "")), str(row.get("text", "")), float(row.get("delay", 0.0)), float(row.get("seconds", SECONDS)))
	ctx.lines.clear()
