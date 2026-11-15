class_name NineweaveSettings
extends RefCounted
const Themes = preload("res://themes/registry.gd")
var path: String = "user://nineweave.cfg"
var values: Dictionary = {"sound":true,"music":false,"reduced_motion":false,"difficulty":"Hard","show_hints":true,"player_name":"You","sfx_volume":.85,"announcer_volume":.9,"music_volume":.45,"audio_version":3,"background_theme":"crystal","board_theme":"crystal"}
var saved_game: Dictionary = {}
func _init(file_path: String = "user://nineweave.cfg"):
	path = file_path
	var c = ConfigFile.new()
	if c.load(path) == OK:
		for key in values: values[key] = c.get_value("settings",key,values[key])
		saved_game = c.get_value("resume","game",{})
		# Only legacy bug-era saves are repaired. A Round 3 intentional mute persists.
		if int(c.get_value("settings","audio_version",0)) < 3:
			values.sound = true; values.audio_version = 3; save()
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
