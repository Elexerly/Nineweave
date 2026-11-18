class_name HttpPollingTransport
extends "res://net/net_transport.gd"
## Live authoritative play. Device identity and the current room seat are separate.
const API = preload("res://net/json_api.gd")
const Clock = preload("res://net/turn_clock.gd")
const LIVE_ORIGIN = API.LIVE_ORIGIN
signal room_updated(envelope: Dictionary)
## Round 5a (protocol 2). Old servers never see a chat or still-here request.
signal chat_received(messages: Array)
signal chat_failed(message: String)
signal chat_sent
signal link_changed(reconnecting: bool)
signal clock_changed
const ROOM_KEYS = ["tournament","status","private","opponent","opponent_left","result","end_reason","turn_expires_at","protocol","turn_started_at","still_there_at","still_here_used","consecutive_late_turns","opponent_consecutive_late_turns","turn_late_limit","turn_seconds","still_there_seconds","grace_seconds","both_moved","opponent_joined_at","opponent_last_seen_at","opponent_connected","you","players","poll_after_ms"]
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
## Set from GET /capabilities (or a protocol-2 envelope); chat needs capabilities.chat.
var online2: bool = false
var chat_enabled: bool = false
var room: Dictionary = {} # Latest envelope fields (ROOM_KEYS + state + seat).
var clock_offset: float = 0.0
var chat_since: int = 0
var chat_log: Array = []
var chat_retry_until: float = 0.0
var background: bool = false
var reconnecting: bool = false
var poll_failures: int = 0
var now_source: Callable # Tests pin the device clock.
## Chat and still-here must not wait behind (or cancel) a move, so they use their own queue.
var aux_api = API.new()
var _chat_ids: Dictionary = {}
var _chat_busy: bool = false
var _chat_more: bool = false
var _still_here_turn: String = ""
var _last_stamp: float = 0.0
func _ready():
	api.base_url = base_url; api.completed.connect(_response); add_child(api); base_url = api.base_url
	aux_api.base_url = base_url; aux_api.completed.connect(_aux_response); add_child(aux_api)
	_timer = Timer.new(); _timer.one_shot = true; _timer.wait_time = 1.0; add_child(_timer); _timer.timeout.connect(_poll)
func now() -> float:
	return float(now_source.call()) if now_source.is_valid() else Time.get_unix_time_from_system()
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
		_send("/rooms/"+code+"?since="+str(sequence)+("&chat_since="+str(chat_since) if chat_enabled else ""),HTTPClient.METHOD_GET,{},"poll")
## Hidden web tab (document.visibilityState) or unfocused/backgrounded app.
func is_hidden() -> bool:
	if background: return true
	return OS.has_feature("web") and str(JavaScriptBridge.eval("document.visibilityState")) == "hidden"
func poll_delay_ms() -> int:
	var ms = Clock.poll_ms(room,seat,is_hidden())
	if ms > 0 and reconnecting: ms = maxi(Clock.backoff_ms(poll_failures),Clock.HIDDEN_POLL_MS if is_hidden() else 0)
	return ms
func _schedule():
	if not is_instance_valid(_timer) or code.is_empty() or token.is_empty(): return
	var ms = poll_delay_ms()
	if ms <= 0: _timer.stop(); return
	if _chat_more: _chat_more = false; ms = 50
	_timer.start(ms/1000.0)
func set_background(value: bool):
	if background == value: return
	background = value
	# Coming back: poll at the normal rate right away instead of waiting out the slow timer.
	if not value and is_instance_valid(_timer) and not _timer.is_stopped() and _timer.time_left*1000.0 > poll_delay_ms(): _schedule()
func _response(operation: String, response_code: int, data: Dictionary, problem: String):
	_inflight = ""
	if not problem.is_empty():
		if operation == "poll" and (response_code == 0 or response_code >= 500 or response_code in [408,429]):
			# Keep retrying quietly with backoff; the server grants a 60 s grace.
			poll_failures += 1
			if not reconnecting: reconnecting = true; link_changed.emit(true)
			_schedule(); return
		# Room conflicts also carry authoritative snapshots. Never discard those.
		if data.has("state"): _envelope(data)
		error.emit(problem)
		if not (operation == "poll" and response_code in [401,403,404]): _schedule()
		return
	if operation == "poll" and reconnecting:
		reconnecting = false; poll_failures = 0; link_changed.emit(false)
	if operation in ["create","join"]:
		if not data.has_all(["code","seat","token"]) or int(data.seat) not in [1,2] or str(data.token).is_empty():
			_unavailable(); return
		code = str(data.code); seat = int(data.seat); token = str(data.token); password = ""
		private_room = bool(data.get("private",private_room)); room.status = str(data.get("status",""))
		connected.emit()
		if operation == "create": room_created.emit(code)
		joined.emit(code,seat)
	_envelope(data)
	_schedule()
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
	_absorb_room(data)
	var opponent = Clock.opponent_name(data,seat)
	if not opponent.is_empty():
		remote_name = opponent
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
## Protocol-2 fields. A late reply built before a newer one cannot rewind the clock.
func _absorb_room(data: Dictionary):
	if (data.get("protocol") is int or data.get("protocol") is float) and int(data.protocol) >= 2: online2 = true
	var stamp = Clock.parse(data.get("server_now"))
	if stamp > 0:
		if stamp+0.001 < _last_stamp:
			_receive_chat(data); return
		_last_stamp = stamp; clock_offset = stamp-now()
	for key in ROOM_KEYS:
		if data.has(key): room[key] = data[key]
	if data.get("state") is Dictionary: room.state = data.state
	room.seat = seat
	_receive_chat(data)
	clock_changed.emit()
func _receive_chat(data: Dictionary):
	if not data.get("chat") is Array: return
	var fresh: Array = []
	for item in data.chat:
		if not item is Dictionary or not (item.get("id") is int or item.get("id") is float): continue
		var id = int(item.id)
		if _chat_ids.has(id): continue
		_chat_ids[id] = true
		var message = {"id":id,"seat":int(item.get("seat",0)),"mine":bool(item.get("mine",false)),"name":str(item.get("name","")),"text":Clock.clean_chat(str(item.get("text",""))),"preset":item.get("preset")}
		chat_log.append(message); fresh.append(message); chat_since = maxi(chat_since,id)
	chat_log.sort_custom(func(a,b): return a.id < b.id)
	if not fresh.is_empty(): chat_received.emit(fresh)
	# A full page means more are waiting: fetch the rest on the next tick.
	var seq = data.get("chat_seq")
	if (seq is int or seq is float) and int(seq) > chat_since and data.chat.size() >= 50: _chat_more = true
func my_turn() -> bool:
	var state = room.get("state",{})
	return str(room.get("status","")) == "active" and state is Dictionary and int(state.get("turn",0)) == seat
## Unknown both_moved (round 1–4 server): an active match counts as a loss to leave.
func leave_costs_loss() -> bool:
	if str(room.get("status","")) != "active": return false
	if room.has("both_moved"): return bool(room.both_moved)
	return true
func turn_phase() -> Dictionary:
	return Clock.phase(room,seat,clock_offset,now())
func can_still_here() -> bool:
	return online2 and my_turn() and not bool(room.get("still_here_used",false)) and _still_here_turn != str(room.get("turn_started_at",""))
## POST /still-here once per turn, only during the prompt and only on protocol 2.
func still_here() -> bool:
	if token.is_empty() or code.is_empty() or not can_still_here(): return false
	if turn_phase().phase != "still_there": return false
	_still_here_turn = str(room.get("turn_started_at",""))
	aux_api.submit("/rooms/"+code+"/still-here",HTTPClient.METHOD_POST,{"token":token},"still_here",token)
	return true
func send_chat(text: String = "", preset: String = "") -> bool:
	if not chat_enabled or code.is_empty() or token.is_empty() or _chat_busy: return false
	if now() < chat_retry_until:
		chat_failed.emit("Slow down — try again in %d s" % ceili(chat_retry_until-now())); return false
	var body = {"token":token}
	if not preset.is_empty(): body.preset = preset
	else:
		var clean = Clock.clean_chat(text)
		if clean.is_empty(): return false
		body.text = clean
	_chat_busy = true
	aux_api.submit("/rooms/"+code+"/chat?chat_since="+str(chat_since),HTTPClient.METHOD_POST,body,"chat",token)
	return true
func _aux_response(operation: String, response_code: int, data: Dictionary, problem: String):
	if code.is_empty(): return
	if operation == "chat":
		_chat_busy = false
		if not problem.is_empty():
			var text = str(data.get("error",problem))
			if response_code == 429:
				var wait = maxi(1,int(data.get("retry_after_seconds",10)))
				chat_retry_until = now()+wait; text = "Slow down — try again in %d s" % wait
			elif response_code == 400 and text.is_empty(): text = "Message not allowed"
			chat_failed.emit(text); return
		_receive_chat(data); chat_sent.emit(); return
	if operation == "still_here":
		# Success and 409 both carry the envelope; only take its clock for this round/seq.
		if data.get("state") is Dictionary and int(data.get("seq",-1)) == sequence:
			var info = data.get("match",{})
			if not info is Dictionary or int(info.get("round",match_round)) == match_round:
				_absorb_room(data)
		clock_changed.emit()
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
	if is_instance_valid(aux_api) and aux_api.is_inside_tree(): aux_api.cancel_all()
	_inflight = ""; token = ""; code = ""; seat = 0; sequence = 0; remote_name = "Remote player"; remote_character_id = "auric_rex"
	match_round = 1; reset_agreement(); _left_emitted = false; _opponent_connected = false
	room = {}; chat_since = 0; chat_log = []; _chat_ids = {}; _chat_busy = false; _still_here_turn = ""; _last_stamp = 0.0
	reconnecting = false; poll_failures = 0; chat_retry_until = 0.0
func request_rematch() -> void:
	if room.get("tournament") is Dictionary: return
	if _inflight not in ["","poll"] or local_rematch or token.is_empty(): return
	_send("/rooms/"+code+"/rematch",HTTPClient.METHOD_POST,{"round":match_round,"token":token},"rematch")

func enter_tournament_match(match_info: Dictionary):
	# Already seated by online3: never POST /join or use the device token as a seat.
	code = str(match_info.get("room_code","")); token = str(match_info.get("token","")); seat = int(match_info.get("seat",0))
	if code.is_empty() or token.is_empty() or not seat in [1,2]:
		code = ""; token = ""; error.emit("Your tournament match is not ready. Return to the bracket."); return
	private_room = true; room = {"status":"waiting","tournament":{"rematch":false}}
	connected.emit(); joined.emit(code,seat); _poll()
