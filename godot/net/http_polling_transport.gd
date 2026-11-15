class_name HttpPollingTransport
extends "res://net/net_transport.gd"
## Live authoritative play. Device identity and the current room seat are separate.
const API = preload("res://net/json_api.gd")
const LIVE_ORIGIN = API.LIVE_ORIGIN
signal room_updated(envelope: Dictionary)
var base_url: String = LIVE_ORIGIN
var device_token: String = ""
var token: String = "" # Seat only; never copied into the device store.
var private_room: bool = false
var password: String = ""
var sequence: int = 0
var api = API.new()
var _timer: Timer
var _inflight: String = "" # Operation awaiting a reply. Polls yield to player actions.
var _left_emitted: bool = false
var _opponent_connected: bool = false
var farewell_factory: Callable
func _ready():
	api.base_url = base_url; api.completed.connect(_response); add_child(api); base_url = api.base_url
	_timer = Timer.new(); _timer.wait_time = 1.0; add_child(_timer); _timer.timeout.connect(_poll)
static func origin_base(origin: String) -> String: return API.origin_base(origin)
func _send(path: String, method: int, body: Dictionary, operation: String) -> void:
	if _inflight == "poll" and operation != "poll": api.cancel_all(); _inflight = ""
	if not _inflight.is_empty(): return
	_inflight = operation
	api.submit(path,method,body,operation,device_token if operation in ["create","join"] else token)
func lobby_payload() -> Dictionary:
	var payload = super.lobby_payload()
	payload["private"] = private_room
	if not password.is_empty(): payload["password"] = password
	return payload
func create_room() -> void:
	leave()
	if private_room and (password.is_empty() or password.length() > 64): error.emit("Use a private-room password with 1–64 characters."); return
	_send("/rooms",HTTPClient.METHOD_POST,lobby_payload(),"create")
func join_room(room_code: String) -> void:
	leave(); code = room_code.strip_edges().to_upper()
	if code.length() != 5: code = ""; error.emit("Enter a five-character room code"); return
	for ch in code:
		if not ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789": code = ""; error.emit("Use letters and numbers in the room code"); return
	if password.length() > 64: code = ""; error.emit("Passwords can have at most 64 characters."); return
	var payload = super.lobby_payload()
	if not password.is_empty(): payload["password"] = password
	_send("/rooms/"+code+"/join",HTTPClient.METHOD_POST,payload,"join")
func send_move(board: int, cell: int, seq: int) -> void:
	if _inflight not in ["","poll"]: error.emit("Syncing room. Try again in a moment."); return
	_send("/rooms/"+code+"/moves",HTTPClient.METHOD_POST,{"board":board,"cell":cell,"seq":seq,"token":token},"move")
func _poll():
	if _inflight.is_empty() and not code.is_empty() and not token.is_empty():
		_send("/rooms/"+code+"?since="+str(sequence),HTTPClient.METHOD_GET,{},"poll")
func _response(operation: String, _response_code: int, data: Dictionary, problem: String):
	_inflight = ""
	if not problem.is_empty():
		# Room conflicts also carry authoritative snapshots. Never discard those.
		if data.has("state"): _envelope(data)
		error.emit(problem); return
	if operation in ["create","join"]:
		if not data.has_all(["code","seat","token"]) or int(data.seat) not in [1,2] or str(data.token).is_empty():
			_unavailable(); return
		code = str(data.code); seat = int(data.seat); token = str(data.token); password = ""
		private_room = bool(data.get("private",private_room)); connected.emit()
		if operation == "create": room_created.emit(code)
		joined.emit(code,seat); _timer.start()
	_envelope(data)
func _envelope(data: Dictionary):
	var previous_round = match_round
	var info = data.get("match",{})
	if info is Dictionary and int(info.get("round",match_round)) < match_round: return
	var next_seat = int(info.get("seat",seat)) if info is Dictionary else seat
	# Character map must be delivered before match_started runs the versus presentation.
	var old_seat = seat; seat = next_seat
	if data.has("characters"):
		if not data.characters is Dictionary or not receive_characters(data.characters): seat = old_seat; return
	if info is Dictionary: receive_match_info(info)
	if match_round > previous_round: sequence = 0
	if data.get("opponent") is String and not data.opponent.is_empty():
		remote_name = data.opponent
		if not _opponent_connected:
			_opponent_connected = true; opponent_joined.emit()
	if data.get("moves") is Array:
		var moves = data.moves.duplicate()
		moves.sort_custom(func(a,b): return int(a.get("seq",0)) < int(b.get("seq",0)) if a is Dictionary and b is Dictionary else false)
		for m in moves:
			if not m is Dictionary or not m.has_all(["board","cell","seq"]): continue
			if int(m.seq) == sequence+1:
				sequence = int(m.seq); move_received.emit(int(m.board),int(m.cell),sequence)
	if data.get("state") is Dictionary and data.has("seq"):
		sequence = int(data.seq); state_received.emit(data.state,sequence)
	room_updated.emit(data)
	if data.get("opponent_left",false) and not _left_emitted:
		_left_emitted = true; opponent_left.emit()
	if data.get("status","") == "closed": _timer.stop()
func _unavailable(): error.emit("Online server not available. Please try again.")
func _dispatch_leave(room_code: String, credential: String):
	# Lives under the tree root: freeing the room UI cannot cancel this forfeit.
	var farewell = farewell_factory.call() if farewell_factory.is_valid() else API.new()
	farewell.base_url = base_url
	get_tree().root.add_child(farewell)
	farewell.completed.connect(func(_op,_response,_data,_problem): farewell.queue_free())
	farewell.submit("/rooms/"+room_code+"/leave",HTTPClient.METHOD_POST,{"token":credential},"leave",credential)
func leave() -> void:
	if not code.is_empty() and not token.is_empty(): _dispatch_leave(code,token)
	if is_instance_valid(api) and api.is_inside_tree(): api.cancel_all()
	if is_instance_valid(_timer): _timer.stop()
	_inflight = ""; token = ""; code = ""; seat = 0; sequence = 0; remote_name = "Remote player"; remote_character_id = "auric_rex"
	match_round = 1; reset_agreement(); _left_emitted = false; _opponent_connected = false
func request_rematch() -> void:
	if _inflight not in ["","poll"] or local_rematch or token.is_empty(): return
	_send("/rooms/"+code+"/rematch",HTTPClient.METHOD_POST,{"round":match_round,"token":token},"rematch")
