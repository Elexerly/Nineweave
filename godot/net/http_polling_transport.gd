class_name HttpPollingTransport
extends "res://net/net_transport.gd"
## Future same-origin authoritative JSON backend. Nothing is hosted by this client.
## No HTTP is attempted until create/join. Polling is sequential and single-flight.
var base_url: String = ""
var token: String = ""
var sequence: int = 0
var _request: HTTPRequest
var _timer: Timer
var _operation: String = ""
var _busy: bool = false
var _generation: int = 0
var _request_generation: int = 0
func _ready():
	_request = HTTPRequest.new(); _request.timeout = 8.0; add_child(_request)
	_request.request_completed.connect(_complete)
	_timer = Timer.new(); _timer.wait_time = 1.0; add_child(_timer)
	_timer.timeout.connect(_poll)
	if OS.has_feature("web"):
		base_url = str(JavaScriptBridge.eval("window.location.origin"))
func _send(path: String, method: int, body: Dictionary, operation: String) -> void:
	if _busy: return
	if base_url.is_empty(): _unavailable(); return
	_operation = operation; _busy = true; _request_generation = _generation
	var headers = PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty(): headers.append("Authorization: Bearer "+token)
	var err = _request.request(base_url+"/api/nineweave"+path,headers,method,JSON.stringify(body) if method != HTTPClient.METHOD_GET else "")
	if err != OK: _busy = false; _unavailable()
func create_room() -> void:
	leave(); _send("/rooms",HTTPClient.METHOD_POST,lobby_payload(),"create")
func join_room(room_code: String) -> void:
	leave(); code = room_code.strip_edges().to_upper()
	if code.length() != 5: error.emit("Enter a five-character room code"); return
	for ch in code:
		if not ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789": error.emit("Use letters and numbers in the room code"); return
	_send("/rooms/"+code+"/join",HTTPClient.METHOD_POST,lobby_payload(),"join")
func send_move(board: int, cell: int, seq: int) -> void:
	if _busy: error.emit("Syncing room. Try again in a moment."); return
	_send("/rooms/"+code+"/moves",HTTPClient.METHOD_POST,{"board":board,"cell":cell,"seq":seq,"token":token},"move")
func _poll():
	if not _busy and not code.is_empty():
		_send("/rooms/"+code+"?since="+str(sequence),HTTPClient.METHOD_GET,{},"poll")
func _complete(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray):
	if _request_generation != _generation: return
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response in [404,405,502,503] or response == 0: _unavailable(); return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary: _unavailable(); return
	if response < 200 or response >= 300:
		error.emit(str(data.get("error","The server rejected that request")))
		return
	if _operation in ["create","join"]:
		if not data.has_all(["code","seat","token"]): _unavailable(); return
		code = str(data.code); seat = int(data.seat); token = str(data.token)
		connected.emit()
		if _operation == "create": room_created.emit(code)
		joined.emit(code,seat); _timer.start()
	if data.has("match") and data.match is Dictionary:
		var previous_round = match_round
		receive_match_info(data.match)
		if match_round > previous_round: sequence = 0
	if data.has("characters"):
		if not data.characters is Dictionary or not receive_characters(data.characters): return
	if data.has("opponent") and not str(data.opponent).is_empty():
		var first = remote_name == "Remote player"
		remote_name = str(data.opponent)
		if first: opponent_joined.emit()
	if data.get("opponent_left",false): opponent_left.emit()
	if data.has("moves"):
		for m in data.moves:
			if not m is Dictionary or not m.has_all(["board","cell","seq"]): continue
			if int(m.seq) == sequence+1:
				sequence = int(m.seq); move_received.emit(int(m.board),int(m.cell),sequence)
	if data.has("state") and data.has("seq"):
		sequence = int(data.seq); state_received.emit(data.state,sequence)
func _unavailable():
	if is_instance_valid(_timer): _timer.stop()
	error.emit("Online server not available yet. Try the local online demo.")
func leave() -> void:
	_generation += 1
	if is_instance_valid(_request): _request.cancel_request()
	if is_instance_valid(_timer): _timer.stop()
	_busy = false; token = ""; code = ""; seat = 0; sequence = 0; remote_character_id = "auric_rex"

func request_rematch() -> void:
	if _busy or local_rematch: return
	_send("/rooms/"+code+"/rematch",HTTPClient.METHOD_POST,{"round":match_round,"token":token},"rematch")
