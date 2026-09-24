@tool
extends SceneTree
## Re-stamps every forge .import sidecar under res://assets/models from
## game/assets/import_defaults.cfg, without regenerating the assets themselves.
##
##   godot --headless --path game --script res://tools_gd/apply_import_settings.gd
##
## Use this when an import setting changes (a new LOD distance, a different compression
## mode) and the meshes are fine: rebuilding 200 GLBs to change one line would be absurd.
## The forge writes the same sidecars at generation time, so the two paths agree.

const MODELS_ROOT := "res://assets/models"
const DEFAULTS := "res://assets/import_defaults.cfg"
const SHADERS_ROOT := "res://assets/shaders"

var scene_params := ""
var texture_params := ""
var written := 0
var skipped := 0


func _init() -> void:
	if not _load_defaults():
		quit(2)
		return
	var files: Array[String] = []
	_scan(MODELS_ROOT, files)
	if files.is_empty():
		print("apply_import_settings: nothing under %s (generate assets first)" % MODELS_ROOT)
		quit(0)
		return
	for f in files:
		if f.ends_with(".glb"):
			_write(f, "scene", "PackedScene", scene_params)
		elif f.ends_with(".png"):
			_write(f, "texture", "CompressedTexture2D", _texture_block(f))
	print("apply_import_settings: wrote %d sidecars, %d unchanged" % [written, skipped])
	print("Now run: godot --headless --path game --import")
	quit(0)


func _load_defaults() -> bool:
	var text := _read(DEFAULTS)
	if text == "":
		push_error("apply_import_settings: cannot read %s" % DEFAULTS)
		return false
	var section := ""
	var blocks := {"scene": PackedStringArray(), "texture": PackedStringArray()}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if blocks.has(section):
			blocks[section].append(line)
	scene_params = "\n".join(blocks["scene"]) + "\n"
	texture_params = "\n".join(blocks["texture"]) + "\n"
	if scene_params.strip_edges().is_empty() or texture_params.strip_edges().is_empty():
		push_error("apply_import_settings: %s is missing a [scene] or [texture] block" % DEFAULTS)
		return false
	return true


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _scan(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan("%s/%s" % [dir_path, sub], into)
	for f in dir.get_files():
		if f.ends_with(".glb") or f.ends_with(".png"):
			into.append("%s/%s" % [dir_path, f])


func _texture_block(res_path: String) -> String:
	var is_normal := res_path.ends_with("_normal.png")
	# `_nrm.png`: an impostor's object-space normal atlas (tools/forge/gen_impostors.py) -- data, not a
	# tangent-space normal map
	var is_data := is_normal or res_path.ends_with("_orm.png") or res_path.ends_with("_nrm.png")
	return texture_params \
		.replace("{normal_map}", "1" if is_normal else "2") \
		.replace("{channel_pack}", "1" if is_data else "0")


func _write(res_path: String, importer: String, type_name: String, params: String) -> void:
	var import_path := res_path + ".import"
	var uid := _uid_for(res_path, import_path)
	var text := "[remap]\n\nimporter=\"%s\"\n" % importer
	if importer == "scene":
		text += "importer_version=1\n"
	text += "type=\"%s\"\nuid=\"%s\"\n\n[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n%s" % [
		type_name, uid, res_path, params]
	var existing := _read(import_path)
	if existing == text:
		skipped += 1
		return
	var f := FileAccess.open(import_path, FileAccess.WRITE)
	if f == null:
		push_error("apply_import_settings: cannot write %s" % import_path)
		return
	f.store_string(text)
	written += 1


func _uid_for(res_path: String, import_path: String) -> String:
	## Keep the uid an existing sidecar already has, so scenes referencing it do not break.
	var existing := _read(import_path)
	for line in existing.split("\n"):
		if line.begins_with("uid=\""):
			return line.substr(5, line.length() - 6)
	return _derive_uid(res_path)


func _derive_uid(res_path: String) -> String:
	## Same derivation as tools/forge/lib/export.py:godot_uid, so both paths agree.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(res_path.to_utf8_buffer())
	var digest := ctx.finish()
	var n := 0
	for i in 8:
		n = (n << 8) | int(digest[i])
	n &= 0x7FFFFFFFFFFFFFFF
	var chars := "abcdefghijklmnopqrstuvwxy012345678"
	var out := ""
	while n > 0:
		out = chars[n % 34] + out
		n /= 34
	return "uid://" + out
