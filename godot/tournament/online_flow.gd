extends Node
## Online3 client; all credentials stay in memory and only the server advances play.
const API = preload("res://net/json_api.gd")
const Clock = preload("res://net/turn_clock.gd")
const Screen = preload("res://tournament/online_screen.gd")
const Model = preload("res://tournament/online_model.gd")
const HTTP = preload("res://net/http_polling_transport.gd")
const COMING_SOON = "Online tournaments are coming soon"
var main
var api = API.new()
var timer: Timer
var state: String = "chooser"
var capabilities: Dictionary = {}
var unavailable: bool = false
var busy: bool = false
var status: String = ""
var listing: Array = []
var snapshot: Dictionary = {}
var code: String = ""
var desired_players: int = 8
var starts_in_minutes: int = 10
var private_tournament: bool = false
var password: String = ""
var join_code: String = ""
var join_password: String = ""
var screen
var offset: float = 0
var now_source: Callable
var match_active: bool = false
var entered_room: String = ""
var countdown: float = -1
var _pending_match: Dictionary = {}
var _inflight: String = ""
var _auto_return: float = -1
func setup(host):
	main = host
	if main.http_request_factory.is_valid(): api.request_factory = main.http_request_factory
	api.completed.connect(_response); add_child(api)
	timer = Timer.new(); timer.one_shot = true; add_child(timer); timer.timeout.connect(refresh)
func now() -> float: return float(now_source.call()) if now_source.is_valid() else Time.get_unix_time_from_system()
func token() -> String: return str(main.account.store.data.device_token)
func request():
	if main._require_screen_name(): return
	timer.stop(); main._leave_online(); main.cinematic.clear(); main.thinking = false
	state = "waiting" if not code.is_empty() else "chooser"
	main.page = "online_tournament"; main.overlay = ""; main._rebuild()
	if not code.is_empty(): refresh()
func open_online():
	state = "waiting" if not code.is_empty() else "lobby"; status = "Checking online tournaments…"
	main.page = "online_tournament"; main.overlay = ""; main._rebuild()
	if not code.is_empty(): refresh(); return
	if unavailable: status = COMING_SOON; _update(); return
	_send("/capabilities",HTTPClient.METHOD_GET,{},"capabilities",false)
func build(extent: Vector2):
	screen = Screen.new(); screen.size = extent; screen.flow = self
	screen.reduced_motion = bool(main.settings.values.reduced_motion)
	screen.action.connect(_action); screen.draft_changed.connect(_draft)
	main.add_child(screen); main.ui_nodes.append(screen); main.controls.merge(screen.controls)
func _send(path: String, method: int, body: Dictionary, operation: String, authenticated: bool = true):
	if not _inflight.is_empty():
		if _inflight in ["poll","list"] and operation not in ["poll","list"]: api.cancel_all(); _inflight = ""
		else: return
	_inflight = operation; busy = true
	api.submit(path,method,body,operation,token() if authenticated else "")
func _schedule(ms: int):
	timer.stop()
	if ms > 0 and main.page == "online_tournament" and state in ["waiting","lobby"]: timer.start(maxf(.25,ms/1000.0))
func refresh():
	if unavailable or main.page != "online_tournament" or match_active or not state in ["lobby","waiting"]: return
	if code.is_empty(): _send("/tournaments",HTTPClient.METHOD_GET,{},"list",false)
	else: _send("/tournaments/"+code,HTTPClient.METHOD_GET,{},"poll")
static func capacity(players: int) -> int: return 4 if players <= 4 else 8
func create():
	if unavailable or busy: return
	if not main.account.store.online_ready(): status = "Choose and sync a screen name in Play Online first."; _update(); return
	if private_tournament and (password.is_empty() or password.length() > 64): status = "Use a password with 1–64 characters."; _update(); return
	var body = {"size":capacity(desired_players),"starts_in_minutes":starts_in_minutes,"private":private_tournament,"character_id":str(main.profile.data.character_id)}
	if private_tournament: body.password = password
	_send("/tournaments",HTTPClient.METHOD_POST,body,"create"); _update()
func join(value: String = ""):
	if unavailable or busy: return
	if not main.account.store.online_ready(): status = "Choose and sync a screen name in Play Online first."; _update(); return
	var target = (join_code if value.is_empty() else value).strip_edges().to_upper()
	if target.length() != 6 or not target.begins_with("T"): status = "Enter a six-character tournament code beginning with T."; _update(); return
	for ch in target:
		if not ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789": status = "Use letters and numbers in the tournament code."; _update(); return
	var body = {"character_id":str(main.profile.data.character_id)}
	if value.is_empty() and not join_password.is_empty(): body.password = join_password
	_send("/tournaments/"+target+"/join",HTTPClient.METHOD_POST,body,"join"); _update()
func leave():
	if code.is_empty(): close(); return
	_send("/tournaments/"+code+"/leave",HTTPClient.METHOD_POST,{},"leave")
func close():
	timer.stop(); api.cancel_all(); _inflight = ""; busy = false
	countdown = -1; _pending_match = {}; _auto_return = -1
	main.go_home()
func _response(operation: String, response: int, data: Dictionary, problem: String):
	_inflight = ""; busy = false
	if response == 404 and (operation in ["capabilities","list","create"] or str(data.get("error","")).to_lower() in ["not found","unknown path","unknown endpoint"]):
		unavailable = true; status = COMING_SOON; timer.stop(); _update(); return
	if not problem.is_empty():
		status = "Tournament not found. Check the code." if response == 404 else problem
		if response == 429: status = "Too many requests. Please wait a moment."
		_update()
		if response == 0 or response >= 500 or response in [408,429]: _schedule(5000)
		return
	if operation == "capabilities":
		capabilities = data
		if data.get("tournaments") != true:
			unavailable = true; status = COMING_SOON; _update(); return
		status = "Join a public tournament or create one for your rivals."
		refresh(); _update(); return
	if operation == "list":
		listing = data.get("tournaments",[]) if data.get("tournaments") is Array else []
		offset = Clock.parse(data.get("server_now"))-now()
		status = "No public tournaments yet. Create one to gather your rivals." if listing.is_empty() else "Public tournaments refresh automatically."
		_update(); _schedule(int(data.get("poll_after_ms",5000))); return
	if operation == "leave":
		code = ""; snapshot = {}; entered_room = ""; match_active = false; countdown = -1; _pending_match = {}
		password = ""; join_password = ""; state = "lobby"; status = "You left the tournament."; _update(); refresh(); return
	if not data.has_all(["code","status","players","rounds"]):
		status = "Tournament server returned an incomplete update. Retrying…"; _update(); _schedule(5000); return
	code = str(data.code); snapshot = data.duplicate(true); state = "waiting"; password = ""; join_password = ""
	var stamp = Clock.parse(data.get("server_now"))
	if stamp > 0: offset = stamp-now()
	status = str(data.get("cancel_reason","")) if data.get("status") == "cancelled" else ""
	_update(); _schedule(int(data.get("poll_after_ms",4000)))
	var next = data.get("your_match")
	if next is Dictionary and str(next.get("room_code","")) != entered_room and not match_active:
		# Online3 polls every second before room entry. Repeated envelopes must
		# not restart the three-second countdown and postpone entry forever.
		var same_match = str(_pending_match.get("room_code","")) == str(next.get("room_code",""))
		_pending_match = next.duplicate(true)
		if not same_match:
			countdown = 3
			main.hero_video.prefetch_pair(str(main.profile.data.character_id),str(next.get("opponent",{}).get("hero","")))
		_update()
	elif not match_active:
		_pending_match = {}; countdown = -1
func seconds_to_start() -> int:
	var at = Clock.parse(snapshot.get("starts_at")); var full = Clock.parse(snapshot.get("starting_at"))
	if full > 0: at = minf(at,full)
	return maxi(0,ceili(at-now()-offset))
func waiting_text() -> String:
	if snapshot.is_empty(): return status
	match str(snapshot.get("status","")):
		"cancelled": return "CANCELLED · "+str(snapshot.get("cancel_reason","Not enough players joined"))
		"finished":
			var champ = snapshot.get("champion")
			return str(champ.get("name","Winner"))+" is the champion!" if champ is Dictionary else "Tournament complete"
		"registering","starting": return "%d / %d joined · Starts in %d:%02d · Minimum 3" % [int(snapshot.get("joined",0)),int(snapshot.get("size",8)),seconds_to_start()/60,seconds_to_start()%60]
	if countdown >= 0: return "Next match in %d…" % maxi(1,ceili(countdown))
	var you = snapshot.get("you")
	var phase = str(you.get("state","waiting")) if you is Dictionary else "spectator"
	return {"bye":"BYE · Advanced automatically. Waiting for your opponent.","waiting":"You advanced! Waiting for the next opponent.","playing":"Your match is ready.","eliminated":"Eliminated · Follow the bracket to the crown.","champion":"You are the champion!","spectator":"Live bracket · Small boards won"}.get(phase,"Waiting for the next round…")
func _process(delta):
	if main == null: return
	if main.page != "online_tournament": timer.stop()
	if countdown >= 0 and main.page == "online_tournament" and not match_active:
		countdown -= delta
		if countdown <= 0: enter_match()
	if _auto_return >= 0:
		_auto_return -= delta
		if _auto_return <= 0: _auto_return = -1; return_to_bracket()
	if is_instance_valid(screen) and main.page == "online_tournament": screen.tick()
func enter_match():
	if _pending_match.is_empty() or match_active: return
	var next = _pending_match; _pending_match = {}; countdown = -1; match_active = true
	entered_room = str(next.get("room_code","")); timer.stop(); api.cancel_all(); _inflight = ""; busy = false
	main.cinematic.clear(); main.page = "online"; main.online_state = "waiting"; main.overlay = ""
	var transport = HTTP.new(); main._attach_transport(transport)
	main.room_code = entered_room; main.human_mark = int(next.get("seat",1))
	var opponent = next.get("opponent",{})
	main.opponent_name = str(opponent.get("name","Rival")); main.rival_character = str(opponent.get("hero","auric_rex"))
	transport.enter_tournament_match(next)
	main.message = "Opening your tournament match…"; main._rebuild()
func match_ended(data: Dictionary):
	if not match_active or not data.get("status") in ["finished","closed"]: return
	if not data.get("result") is Dictionary: return
	# Give the combined result card a short readable beat, then pull the bracket.
	if _auto_return < 0: _auto_return = 5.0
func return_to_bracket():
	_auto_return = -1; match_active = false
	main._leave_online(); main.cinematic.clear(); main.board.clear_effects(); main.thinking = false
	state = "waiting"; main.page = "online_tournament"; main.overlay = ""; main._rebuild(); refresh()
func _update():
	if main.page != "online_tournament": return
	if is_instance_valid(screen) and screen.screen == state:
		screen.update_state()
	else: main._rebuild()
func _action(kind: String, value: String):
	main.sound.cue("ui")
	match kind:
		"computer": close(); main.tournament.request()
		"online": open_online()
		"menu": close()
		"back":
			if state == "chooser": close()
			else: state = "chooser"; timer.stop(); _update()
		"create": create()
		"join": join(value)
		"refresh": refresh()
		"privacy": private_tournament = not private_tournament; main._rebuild()
		"players": desired_players = int(value); main._rebuild()
		"start": starts_in_minutes = int(value)
		"leave": leave()
		"ready": enter_match()
		"copy": DisplayServer.clipboard_set(code); status = "Tournament code copied."; _update()
		"account": close(); main.open_online()
func _draft(kind: String, value: String):
	if kind == "password": password = value
	elif kind == "room_code": join_code = value.to_upper()
	elif kind == "join_password": join_password = value
