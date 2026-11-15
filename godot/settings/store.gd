class_name NineweaveSettings
extends RefCounted
var path: String = "user://nineweave.cfg"
var values: Dictionary = {"sound":true,"music":false,"reduced_motion":false,"difficulty":"Hard","show_hints":true,"player_name":"You"}
var saved_game: Dictionary = {}
func _init(file_path: String = "user://nineweave.cfg"):
	path = file_path
	var c = ConfigFile.new()
	if c.load(path) == OK:
		for key in values: values[key] = c.get_value("settings",key,values[key])
		saved_game = c.get_value("resume","game",{})
func save() -> void:
	var c = ConfigFile.new()
	for key in values: c.set_value("settings",key,values[key])
	c.set_value("resume","game",saved_game)
	c.save(path)
func set_value(key: String, value) -> void:
	if values.has(key): values[key] = value; save()
