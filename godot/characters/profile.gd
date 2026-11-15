extends RefCounted
const Roster = preload("res://characters/roster.gd")
var path: String
## Identity is a replaceable envelope: future verified server identity can replace
## {kind:local,id:...} without changing character selection or UI consumers.
var data: Dictionary = {"version":1,"identity":{},"display_name":"You","character_id":"vesper_vale","onboarded":false}
func _init(file_path: String = "user://nineweave-profile.cfg"):
	path = file_path
	data = data.duplicate(true)
	var cfg = ConfigFile.new()
	var corrupt = FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).has(0)
	if not corrupt and cfg.load(path) == OK:
		for key in data: data[key] = cfg.get_value("profile",key,data[key])
	# Round 3b: wrong-typed values from a corrupt file fall back to safe defaults.
	if not data.onboarded is bool: data.onboarded = false
	if not data.character_id is String: data.character_id = "vesper_vale"
	if not data.display_name is String: data.display_name = "You"
	if not data.identity is Dictionary or data.identity.is_empty(): data.identity = {"kind":"local","id":"local-"+str(Time.get_unix_time_from_system()).sha256_text().left(16)}
	if not Roster.valid(str(data.character_id)): data.character_id = "vesper_vale"
	data.character_id = Roster.canonical_id(data.character_id)
	data.display_name = str(data.display_name).strip_edges().left(24)
	if data.display_name.is_empty(): data.display_name = "You"
func choose(id: String, display_name: String):
	if not Roster.valid(id): return false
	data.character_id = Roster.canonical_id(id); data.display_name = display_name.strip_edges().left(24)
	if data.display_name.is_empty(): data.display_name = "You"
	data.onboarded = true; save(); return true
func save():
	var cfg = ConfigFile.new()
	for key in data: cfg.set_value("profile",key,data[key])
	cfg.save(path)
