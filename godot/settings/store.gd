class_name NineweaveSettings
extends RefCounted
const Themes = preload("res://themes/registry.gd")
var path: String = "user://nineweave.cfg"
const DEFAULTS = {"sound":true,"music":false,"reduced_motion":false,"difficulty":"Hard","show_hints":true,"player_name":"You","sfx_volume":.85,"announcer_volume":.9,"music_volume":.45,"audio_version":3,"background_theme":"crystal","board_theme":"crystal","tutorial_completed":false}
var values: Dictionary = DEFAULTS.duplicate()
var saved_game = {}
func _init(file_path: String = "user://nineweave.cfg"):
	path = file_path
	var c = ConfigFile.new()
	# Round 3b: a binary-corrupt file (NULs from a torn write) is treated as missing
	# instead of handing it to the text parser, which logs engine errors.
	var corrupt = FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).has(0)
	if not corrupt and c.load(path) == OK:
		for key in values: values[key] = c.get_value("settings",key,values[key])
		saved_game = c.get_value("resume","game",{})
		# Only legacy bug-era saves are repaired. A Round 3 intentional mute persists.
		var version = c.get_value("settings","audio_version",0)
		if not (version is int or version is float) or int(version) < 3:
			values.sound = true; values.audio_version = 3; save()
	_sanitize()
	if not Themes.valid(str(values.background_theme),Themes.BACKGROUNDS): values.background_theme = Themes.DEFAULT_BACKGROUND
	if not Themes.valid(str(values.board_theme),Themes.BOARDS): values.board_theme = Themes.DEFAULT_BOARD
	for key in ["sfx_volume","announcer_volume","music_volume"]: values[key] = clampf(float(values[key]),0,1)
func save() -> void:
	var c = ConfigFile.new()
	for key in values: c.set_value("settings",key,values[key])
	c.set_value("resume","game",saved_game)
	c.save(path)
func set_value(key: String, value) -> void:
	if values.has(key): values[key] = value; save()
const DIFFICULTIES = ["Easy","Medium","Hard"]
## Round 3b: hand-edited or corrupt files can carry any Variant type. Every value is
## coerced to its default's type (bad values fall back to the default) so consumers
## such as bool(values.sound) or saved_game.state never crash on startup.
func _sanitize() -> void:
	var defaults = DEFAULTS
	for key in defaults:
		var d = defaults[key]; var v = values.get(key,d)
		match typeof(d):
			TYPE_BOOL:
				if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: v = v != 0
				elif typeof(v) != TYPE_BOOL: v = d
			TYPE_FLOAT:
				if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: v = float(v)
				else: v = d
				if is_nan(v) or is_inf(v): v = d
			TYPE_INT:
				v = int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else d
			TYPE_STRING:
				v = v if typeof(v) == TYPE_STRING else d
		values[key] = v
	if not values.difficulty in DIFFICULTIES: values.difficulty = DEFAULTS.difficulty
	values.player_name = str(values.player_name).strip_edges().left(24)
	if values.player_name.is_empty(): values.player_name = DEFAULTS.player_name
	if not saved_game is Dictionary or not saved_game.has_all(["state","human"]) or not (saved_game.human is int or saved_game.human is float) or not int(saved_game.human) in [1,2]:
		saved_game = {}
