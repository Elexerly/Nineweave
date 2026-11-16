extends Node
## Round 5a: capability probe plus device-token moderation (block, unblock, report).
## GET /capabilities is the only request an older server ever receives from here.
const API = preload("res://net/json_api.gd")
const Clock = preload("res://net/turn_clock.gd")
signal capabilities_changed(capabilities: Dictionary)
signal blocks_changed(names: Array)
## kind: block, unblock, report. ok=false carries the server's message.
signal finished(kind: String, ok: bool, message: String)
const CAPS_TTL = 60.0
var api = API.new()
var store # net/device_store.gd, for the device token only.
var capabilities: Dictionary = {}
var probed_at: float = -1000.0
var blocks: Array = []
var _probing: bool = false
func _ready():
	api.completed.connect(_completed); add_child(api)
func online2() -> bool: return capabilities.get("online2",false) == true or int(capabilities.get("protocol",1)) >= 2
func chat() -> bool: return capabilities.get("chat",false) == true
func presets() -> Dictionary:
	var value = capabilities.get("chat_presets")
	if value is Dictionary and not value.is_empty():
		var out = {}
		for key in value:
			if value[key] is String: out[str(key)] = str(value[key])
		if not out.is_empty(): return out
	return Clock.DEFAULT_PRESETS.duplicate()
func probe(force: bool = false):
	var t = Time.get_ticks_msec()/1000.0
	if _probing or (not force and t-probed_at < CAPS_TTL): return
	_probing = true
	api.submit("/capabilities",HTTPClient.METHOD_GET,{},"capabilities")
## Flags from /me, register or PATCH /me also count (they can only turn features on).
func merge_player(player: Dictionary):
	var flags = player.get("capabilities")
	if not flags is Dictionary: return
	var changed = false
	for key in ["online2","chat"]:
		if flags.get(key) == true and capabilities.get(key) != true: capabilities[key] = true; changed = true
	if changed: capabilities_changed.emit(capabilities)
func _token() -> String:
	return str(store.data.device_token) if store != null and store.has_device_token() else ""
func block(room_code: String, seat: int) -> bool:
	if not chat() or _token().is_empty(): return false
	api.submit("/players/block",HTTPClient.METHOD_POST,{"room_code":room_code,"seat":seat},"block",_token()); return true
func unblock(name: String) -> bool:
	if not chat() or _token().is_empty() or name.strip_edges().is_empty(): return false
	api.submit("/players/block",HTTPClient.METHOD_DELETE,{"name":name},"unblock",_token()); return true
func fetch_blocks() -> bool:
	if not chat() or _token().is_empty(): return false
	api.submit("/players/blocks",HTTPClient.METHOD_GET,{},"blocks",_token()); return true
func report(room_code: String, seat: int, reason: String, note: String = "") -> bool:
	if not chat() or _token().is_empty(): return false
	var valid = false
	for pair in Clock.REPORT_REASONS: valid = valid or pair[0] == reason
	if not valid: return false
	var body = {"room_code":room_code,"seat":seat,"reason":reason}
	var clean = note.strip_edges().left(Clock.NOTE_LIMIT)
	if not clean.is_empty(): body.note = clean
	api.submit("/reports",HTTPClient.METHOD_POST,body,"report",_token()); return true
func _completed(operation: String, response: int, data: Dictionary, problem: String):
	match operation:
		"capabilities":
			_probing = false; probed_at = Time.get_ticks_msec()/1000.0
			# 404 / failure / non-JSON = a round 1–4 server: everything new stays off.
			capabilities = data.duplicate(true) if problem.is_empty() else {}
			capabilities_changed.emit(capabilities)
		"blocks":
			if not problem.is_empty(): finished.emit("blocks",false,problem); return
			blocks = []
			if data.get("blocks") is Array:
				for item in data.blocks:
					if item is Dictionary and item.get("name") is String: blocks.append(str(item.name))
			blocks_changed.emit(blocks)
		"block","unblock","report":
			var text = problem
			if response == 429: text = "Too many requests. Try again in %d s." % maxi(1,int(data.get("retry_after_seconds",60)))
			finished.emit(operation,problem.is_empty(),text)
