extends SceneTree
## Round 5a: waiting room, leave/forfeit copy, 25 s turn clock + "Still there?", chat,
## moderation, polling. Every request goes to tests/fake_http.gd; no socket is opened.
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const Rules = preload("res://kernel/rules.gd")
const Clock = preload("res://net/turn_clock.gd")
const HTTP = preload("res://net/http_polling_transport.gd")
const ChatPanel = preload("res://ui/chat_panel.gd")
const NEW_CAPS = {"protocol":2,"online2":true,"chat":true,"tournaments":false,"email":true,"chat_presets":{"gg":"Good game!","nice":"Nice move","rematch":"Rematch?"}}
## Keeps a shared log: farewell/transport fakes are freed with their owners.
class LoggingFake extends "res://tests/fake_http.gd":
	var log: Array
	func request(url: String, headers: PackedStringArray, method: int, body: String) -> int:
		var result = super.request(url,headers,method,body)
		log.append(requests.back()); return result
var checks: int = 0
var failures: int = 0
var device_now: float = 0.0
var T0: float = 0.0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func iso(t: float) -> String:
	var whole = int(floor(t)); var ms = int(round((t-whole)*1000))
	return Time.get_datetime_string_from_unix_time(whole)+".%03dZ" % ms

## Protocol-2 envelope at server time `at` (seconds after T0). Turn clock starts at `start`.
func env(at: float = 3, start: float = 0, overrides: Dictionary = {}) -> Dictionary:
	var e = {"code":"N9ABC","seat":1,"token":"nws_fixture","seq":0,"state":Rules.new().serialize(),"status":"active","private":false,
		"opponent":"NightNight","opponent_left":false,"characters":{"1":"cryon","2":"aurelia"},"match":{"round":1,"seat":1,"local":false,"remote":false},
		"result":null,"end_reason":null,"protocol":2,"server_now":iso(T0+at),"turn_started_at":iso(T0+start),"still_there_at":iso(T0+start+25),
		"turn_expires_at":iso(T0+start+35),"still_here_used":false,"turn_seconds":25,"still_there_seconds":10,"grace_seconds":60,"both_moved":false,
		"opponent_joined_at":iso(T0-20),"opponent_last_seen_at":iso(T0+at-1),"opponent_connected":true,"you":{"name":"Weaver","hero":"cryon"},
		"players":{"1":{"name":"Weaver","hero":"cryon","connected":true},"2":{"name":"NightNight","hero":"aurelia","connected":true}},"poll_after_ms":60000}
	for key in overrides: e[key] = overrides[key]
	return e
func waiting_env(overrides: Dictionary = {}) -> Dictionary:
	var e = env(0,0,{"status":"waiting","opponent":"","characters":{"1":"cryon"},"players":{"1":{"name":"Weaver","hero":"cryon","connected":true}},
		"turn_started_at":null,"still_there_at":null,"turn_expires_at":null,"opponent_joined_at":null,"opponent_connected":false,"poll_after_ms":60000})
	for key in overrides: e[key] = overrides[key]
	return e
## Round 1–4 envelope: none of the protocol-2 fields.
func old_env(status: String = "active", overrides: Dictionary = {}) -> Dictionary:
	var e = {"code":"N9ABC","seat":1,"token":"nws_fixture","seq":0,"state":Rules.new().serialize(),"status":status,"private":false,
		"opponent":"" if status == "waiting" else "OldFriend","opponent_left":false,"characters":{"1":"cryon"} if status == "waiting" else {"1":"cryon","2":"aurelia"},
		"match":{"round":1,"seat":1,"local":false,"remote":false},"result":null,"end_reason":null,"turn_expires_at":null if status == "waiting" else iso(Time.get_unix_time_from_system()+170)}
	for key in overrides: e[key] = overrides[key]
	return e

func make_ui(id: String, view: Vector2 = Vector2(390,844)) -> Dictionary:
	var paths = {}
	for kind in ["device","settings","profile"]:
		paths[kind] = "user://r5a-"+id+"-"+kind+".cfg"
		if FileAccess.file_exists(paths[kind]): DirAccess.remove_absolute(paths[kind])
	var ui = Main.instantiate()
	ui.account.store = Store.new(paths.device)
	ui.settings = Settings.new(paths.settings); ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(paths.profile); ui.profile.data.character_id = "cryon"; ui.profile.data.onboarded = true
	ui.account.store.keep_device("nwd_fixture","Weaver")
	ui.account.store.accept_consent("Weaver",Store.consent_payload()); ui.account.store.skip_email()
	var bundle = {"ui":ui,"fakes":[],"log":[]}
	ui.http_request_factory = func():
		var fake = LoggingFake.new(); fake.log = bundle.log; bundle.fakes.append(fake); return fake
	var account = Fake.new(); ui.account.api.request_factory = func(): return account
	var lobby = Fake.new(); ui.online_api.request_factory = func(): return lobby
	bundle.account = account; bundle.lobby = lobby
	root.add_child(ui); ui.set_process(false); ui.set_view_size(view)
	return bundle
## The fake currently holding an unanswered request whose URL contains `fragment`.
func pending(bundle, fragment: String):
	for fake in bundle.fakes:
		if is_instance_valid(fake) and fake.active and not fake.requests.is_empty() and fragment in fake.requests.back().url: return fake
	return null
## Exact path ending (the create POST must not answer a pending /rooms/<CODE>/leave).
func respond_end(bundle, suffix: String, code: int, data) -> bool:
	for fake in bundle.fakes:
		if is_instance_valid(fake) and fake.active and not fake.requests.is_empty() and fake.requests.back().url.ends_with(suffix):
			fake.respond(code,data); return true
	return false
func respond(bundle, fragment: String, code: int, data) -> bool:
	var fake = pending(bundle,fragment)
	if fake == null: return false
	fake.respond(code,data); return true
func requests(bundle) -> Array:
	return bundle.log
func last_request(bundle, fragment: String):
	var found = null
	for request in requests(bundle):
		if fragment in request.url: found = request
	return found
func count_requests(bundle, fragment: String, method: int = -1) -> int:
	var n = 0
	for request in requests(bundle):
		if fragment in request.url and (method < 0 or request.method == method): n += 1
	return n
func quiet(bundle):
	var t = bundle.ui.transport
	if t is HTTP and is_instance_valid(t._timer): t._timer.stop()
func caps(bundle, data, code: int = 200):
	ok(respond(bundle,"/capabilities",code,data),"capabilities probe is GET /capabilities")
func labels_text(node: Node) -> String:
	var out: Array[String] = []
	for label in node.find_children("*","Label",true,false): out.append(label.text)
	return "\n".join(out)
## New-server match in progress: host seat 1 (X, to move), versus finished.
func start_match(bundle, overrides: Dictionary = {}):
	var ui = bundle.ui
	ui.open_online(); caps(bundle,NEW_CAPS)
	ui.create_online(); ui.transport.now_source = func(): return device_now
	respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
	ui.transport._poll(); respond(bundle,"/rooms/N9ABC?",200,env(3,0,overrides)); quiet(bundle)
	ui._joined_beat_done(); ui.cinematic.advance(3.01); ui.cinematic.skip()

func run():
	T0 = Time.get_unix_time_from_datetime_string("2026-11-15T12:00:00")
	device_now = T0-300+3 # Device clock five minutes behind the server.
	clock_math()
	await old_server()
	await waiting_room()
	await leave_confirm()
	await turn_clock()
	await still_there()
	await end_messages()
	await chat()
	await moderation()
	await blocked_list()
	await polling()
	api_override()
	await layouts()
	print("NINEWEAVE_ROUND5A ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func clock_math():
	ok(absf(Clock.parse("2026-11-15T12:00:25.250Z")-(T0+25.25)) < .001,"ISO timestamps keep fractional seconds")
	ok(Clock.parse(null) == 0 and Clock.parse("soon") == 0,"missing or invalid timestamps parse as 0")
	var skew = Clock.offset(iso(T0+3),device_now)
	ok(absf(skew-300) < .001,"offset is server_now minus device clock at receipt")
	ok(absf(Clock.remaining(iso(T0+25),skew,device_now)-22) < .001,"remaining counts from server time, not device time")
	var room = env(3)
	var p = Clock.phase(room,1,skew,device_now)
	ok(p.phase == "turn" and p.mine and absf(p.remaining-22) < .01 and absf(p.fraction-.88) < .01 and p.tier == "calm","22 s left of 25: calm full ring")
	p = Clock.phase(room,1,skew,device_now+15)
	ok(p.phase == "turn" and p.tier == "amber" and absf(p.remaining-7) < .01,"last ~8 s turn amber")
	p = Clock.phase(room,1,skew,device_now+20)
	ok(p.tier == "red" and absf(p.remaining-2) < .01,"last seconds turn red")
	p = Clock.phase(room,1,skew,device_now+23)
	ok(p.phase == "still_there" and absf(p.remaining-9) < .01 and p.tier == "red","still_there_at starts the 10 s prompt")
	ok(Clock.phase(room,2,skew,device_now+23).phase == "still_there" and not Clock.phase(room,2,skew,device_now+23).mine,"opponent sees the same phase, not as theirs")
	ok(Clock.phase(room,1,skew,device_now+40).phase == "expired","past turn_expires_at is expired (server decides)")
	ok(Clock.phase(env(3,0,{"status":"finished"}),1,skew,device_now).phase == "none","no clock outside active")
	ok(Clock.phase(old_env(),1,0,Time.get_unix_time_from_system()).phase == "legacy","old server falls back to a plain countdown")
	ok(Clock.mmss(8.2) == "0:09" and Clock.mmss(8) == "0:08" and Clock.mmss(0) == "0:00" and Clock.mmss(65) == "1:05","countdown formatting")
	ok(Clock.clean_chat("  hi\n\tthere  ") == "hi there" and Clock.clean_chat("x".repeat(130)).length() == 120,"chat input is one line, trimmed, 120 max")
	ok(Clock.clean_chat("a"+char(0x200B)+"b"+char(0x202E)+"c") == "abc","zero-width and bidi controls removed")
	for reason in ["no_show","cancelled","forfeit","timeout","abandoned","expired"]:
		ok(not Clock.end_text(reason,-1,1,true,"NightNight").is_empty(),"end copy for "+reason)
	ok(Clock.end_text("no_show",-1,1,true,"NightNight") == "NightNight didn't show up — match cancelled, no loss","no-show copy")
	ok(Clock.end_text("forfeit",1,1,true,"NightNight") == "NightNight left — you win","forfeit win copy")
	ok(Clock.end_text("timeout",2,1,false,"NightNight") == "Time ran out — you lose","timeout loss copy")
	ok(Clock.end_text("abandoned",1,1,true,"NightNight") == "NightNight disconnected — you win","abandoned win copy")
	ok(Clock.leave_copy(true) == "Leave match? This counts as a loss." and Clock.leave_copy(false) == "Leave match? No one gets a loss yet.","leave copy")

func old_server():
	var bundle = make_ui("old"); var ui = bundle.ui
	ui.open_online(); caps(bundle,{"error":"Not found"},404)
	ok(not ui.social.chat() and not ui.social.online2(),"404 capabilities = old server")
	ui.create_online(); respond_end(bundle,"/rooms",201,old_env("waiting")); quiet(bundle)
	ok(not ui.transport.online2 and not ui.transport.chat_enabled,"old server: transport has no chat/online2")
	ok(ui.online_state == "waiting" and ui.controls.has_all(["cancel","copy"]) and not ui.controls.has("chat"),"old server: waiting screen with Leave, no chat button")
	ok(ui.controls.cancel.caption == "Leave","Leave button caption")
	ui.transport._poll()
	ok(not "chat_since" in last_request(bundle,"/rooms/N9ABC?").url,"old server poll has no chat_since")
	respond(bundle,"/rooms/N9ABC?",200,old_env()); quiet(bundle)
	ok(ui.page == "game" and ui.cinematic.kind == "versus","old server: joining goes straight into versus (round 4g)")
	ok(ui.opponent_name == "OldFriend" and ui.side_name(2) == "OldFriend","old opponent string still names the rival")
	ui.cinematic.advance(3.01); ui.cinematic.skip()
	ok(not ui.controls.has("chat") and not ui.chat_capable(),"old server: no chat button in game")
	ui.toggle_chat(); ok(not ui.chat_open and not is_instance_valid(ui.chat_view),"old server: chat cannot open")
	ok(ui.online_lines()[0].begins_with("Your turn · "),"old server: explicit local turn plus countdown from turn_expires_at")
	ok(ui.prompt_state() == "" and not ui.transport.still_here(),"old server: never a Still there? prompt")
	ok(ui.play_cell(4,4) and last_request(bundle,"/moves").body.board == 4,"old server: moves still post")
	ui.transport.send_chat("hello")
	ui.show_settings(); ok(not ui.controls.has("blocked_players"),"old server: no Blocked players entry")
	ui._close_overlay()
	ui.controls.home.pressed.emit()
	ok(ui.overlay == "leave_confirm" and ui.controls.modal_copy.text == "Leave match? This counts as a loss.","old server: active leave is treated as a loss")
	ui.controls.leave_match.pressed.emit(); await frames()
	ok(ui.page == "title" and count_requests(bundle,"/rooms/N9ABC/leave") == 1,"old server leave still posts /leave")
	for request in requests(bundle):
		for word in ["/chat","/still-here","/players/","/reports"]:
			ok(not word in request.url,"old server never receives "+word+" ("+request.url+")")
	ui.free(); await frames()
	# New server, for contrast.
	bundle = make_ui("new"); ui = bundle.ui
	ui.open_online(); caps(bundle,NEW_CAPS)
	ok(ui.social.chat() and ui.social.online2() and ui.social.presets().size() == 3,"capabilities enable chat/online2 and supply presets")
	ui.create_online(); respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
	ok(ui.transport.online2 and ui.transport.chat_enabled and ui.controls.has("chat"),"new server: chat button on the waiting screen")
	ui.transport._poll(); ok("chat_since=0" in last_request(bundle,"/rooms/N9ABC?").url,"new server poll carries chat_since")
	ui.free(); await frames()
	# A protocol-2 envelope alone also turns on the turn clock (chat still needs capabilities).
	bundle = make_ui("envelope"); ui = bundle.ui
	ui.open_online(); caps(bundle,{},404)
	ui.create_online(); respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
	ok(ui.transport.online2 and not ui.transport.chat_enabled,"protocol 2 envelope detected without chat")
	ui.free(); await frames()

func waiting_room():
	var bundle = make_ui("waiting"); var ui = bundle.ui
	ui.open_online(); caps(bundle,NEW_CAPS)
	ui.create_online(); respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
	var text = labels_text(ui.online_view)
	ok(ui.online_state == "waiting" and "Waiting for other player…" in text,"waiting title")
	ok(ui.online_view.get_node("RoomCode").text == "N9ABC","room code shown big")
	ok("PUBLIC GAME" in text and "Weaver" in text and "Cryon" in text,"public/private line, your screen name and hero")
	ok(ui.controls.has_all(["copy","cancel","chat"]),"copy, Leave and chat controls")
	ui.controls.copy.pressed.emit(); ok(ui.message == "Room code copied.","copy code")
	ui.controls.cancel.pressed.emit(); await frames()
	ok(ui.page == "online" and ui.online_state == "lobby" and ui.transport == null,"Leave returns to the online menu")
	ok(count_requests(bundle,"/rooms/N9ABC/leave",HTTPClient.METHOD_POST) == 1,"Leave posts /rooms/<CODE>/leave (no penalty while waiting)")
	# Host sees "<Name> joined" with their hero, then the versus intro.
	ui.create_online(); respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
	ui.transport._poll(); respond(bundle,"/rooms/N9ABC?",200,env(3)); quiet(bundle)
	ok(ui.online_state == "joined" and ui.page == "online","protocol 2 shows a joined beat first")
	ok(ui.online_view.get_node("WaitingTitle").text == "NightNight joined","<ScreenName> joined")
	ok(ui.online_view.get_node("OpponentName").text == "NightNight" and "Aurelia" in labels_text(ui.online_view),"joined rival's name and hero")
	ok(not ui.joined_timer.is_stopped(),"joined beat is timed")
	ui._joined_beat_done()
	ok(ui.page == "game" and ui.cinematic.kind == "versus","then the existing versus intro")
	ok(ui.cinematic.loser_name == "NightNight" and ui.cinematic.winner_name == "Weaver","versus labels use server screen names")
	ui.cinematic.advance(3.01); ui.cinematic.skip()
	ok(ui.side_name(1) == "Weaver" and ui.side_name(2) == "NightNight","in-game plates use screen names")
	ui.go_home(); ui.free(); await frames()
	# Joiner whose room still reports waiting sees the same screen.
	bundle = make_ui("joiner"); ui = bundle.ui
	ui.open_online(); caps(bundle,NEW_CAPS)
	ui.join_online("N9ABC"); var host_wait = waiting_env({"seat":2,"match":{"round":1,"seat":2,"local":false,"remote":false},"characters":{"2":"cryon"},"players":{"2":{"name":"Weaver","hero":"cryon","connected":true}}})
	respond(bundle,"/rooms/N9ABC/join",200,host_wait); quiet(bundle)
	ok(ui.online_state == "waiting" and ui.controls.has("cancel"),"joiner sees the waiting screen while the server reports waiting")
	ui.free(); await frames()

func leave_confirm():
	var bundle = make_ui("leave"); var ui = bundle.ui
	start_match(bundle)
	ok(ui.page == "game" and ui.overlay == "","in a live match")
	ui.controls.home.pressed.emit()
	ok(ui.overlay == "leave_confirm" and ui.controls.modal_copy.text == "Leave match? No one gets a loss yet.","both_moved false: no-loss copy")
	ok(ui.controls.has_all(["leave_match","stay"]),"Leave match / Stay")
	ui.controls.stay.pressed.emit(); ok(ui.overlay == "" and ui.page == "game","Stay keeps playing")
	ui.transport._poll(); respond(bundle,"/rooms/N9ABC?",200,env(5,0,{"both_moved":true})); quiet(bundle)
	ui.controls.home.pressed.emit()
	ok(ui.controls.modal_copy.text == "Leave match? This counts as a loss.","both_moved true: loss copy")
	ui.controls.leave_match.pressed.emit(); await frames()
	ok(ui.page == "title" and count_requests(bundle,"/rooms/N9ABC/leave") == 1,"Leave match posts /leave")
	ui.free(); await frames()

func turn_clock():
	var bundle = make_ui("clock"); var ui = bundle.ui
	device_now = T0-300+3
	start_match(bundle)
	var t = ui.transport
	ok(absf(t.clock_offset-300) < .01,"transport records server-minus-device offset")
	var info = ui.turn_info()
	ok(info.phase == "turn" and info.mine and absf(info.remaining-22) < .01,"own turn: 22 s left despite a 5-minute device skew")
	ok(ui.online_lines()[0] == "Your move · 0:22","own countdown line")
	ok(ui.online_lines()[1] == "First moves — no-shows cancel with no loss","first-moves label before both_moved")
	device_now += 16
	ok(ui.turn_info().tier == "amber","amber in the last ~8 s")
	device_now += 5
	ok(ui.turn_info().tier == "red","red in the last seconds")
	device_now = T0-300+3
	# Opponent's turn: X has moved; O (NightNight) is due.
	var state = Rules.new(); state.play(4,4)
	device_now = T0-300+10
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(10,8,{"seq":1,"state":state.serialize(),"moves":[{"board":4,"cell":4,"seq":1}]})); quiet(bundle)
	info = ui.turn_info()
	ok(not info.mine and info.turn == 2 and absf(info.remaining-23) < .01,"opponent turn timed from their turn_started_at")
	ok(ui.online_lines()[0] == "Waiting for NightNight… 0:23","Waiting for <name>… indicator")
	device_now = T0-300+35
	ok(ui.online_lines()[0] == "Waiting for NightNight… 0:08","opponent's Still there? phase keeps counting")
	ok(ui.prompt_state() == "","no prompt on the opponent's turn")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(35,8,{"seq":1,"state":state.serialize(),"opponent_connected":false,"both_moved":false})); quiet(bundle)
	ok(ui.online_lines()[0] == "NightNight reconnecting…","opponent_connected false shows reconnecting")
	ui.go_home(); ui.free(); await frames()
	device_now = T0-300+3

func still_there():
	var bundle = make_ui("still"); var ui = bundle.ui
	device_now = T0-300+3
	start_match(bundle)
	var t = ui.transport
	ui.tick_online(); ok(ui.prompt_state() == "" and not ui.controls.has("still_here"),"no prompt before still_there_at")
	t.still_here(); ok(count_requests(bundle,"/still-here") == 0,"still-here is never sent before the prompt")
	device_now = T0-300+26
	ui.tick_online()
	ok(ui.prompt_state() == "ask" and ui.controls.has("still_here") and is_instance_valid(ui.prompt_layer),"Still there? appears at still_there_at on your turn")
	ok(absf(ui.turn_info().remaining-9) < .01,"10 s prompt countdown")
	ui.controls.still_here.pressed.emit()
	var request = last_request(bundle,"/still-here")
	ok(request != null and request.method == HTTPClient.METHOD_POST and request.url.ends_with("/rooms/N9ABC/still-here") and request.body.token == "nws_fixture","I'm here posts /still-here with the seat token")
	ok(not ui.controls.has("still_here") and ui.prompt_state() == "move","button hides once used")
	ok(not t.still_here() and count_requests(bundle,"/still-here") == 1,"only once per turn")
	ok(respond(bundle,"/still-here",200,env(26,26,{"still_here_used":true,"ok":true})),"still-here reply")
	ui.tick_online()
	ok(ui.prompt_state() == "" and ui.turn_info().phase == "turn" and absf(ui.turn_info().remaining-25) < .01,"fresh 25 s clock dismisses the prompt")
	device_now = T0-300+52
	ui.tick_online()
	ok(ui.prompt_state() == "move" and not ui.controls.has("still_here"),"after still_here_used: Move now! without the button")
	ok(not t.still_here() and count_requests(bundle,"/still-here") == 1,"no second still-here in the same turn")
	# Making a move dismisses the prompt immediately.
	ok(ui.play_cell(4,4),"move during the prompt is accepted")
	ok(ui.prompt_state() == "" and ui.prompt_layer == null,"move dismisses Still there?")
	ok(last_request(bundle,"/moves").body.seq == 1,"move posted")
	var state = Rules.new(); state.play(4,4)
	respond(bundle,"/moves",200,env(53,53,{"seq":1,"state":state.serialize(),"moves":[{"board":4,"cell":4,"seq":1}]})); quiet(bundle)
	# Next own turn: a 409 (already confirmed) envelope also hides the button.
	state.play(4,0)
	device_now = T0-300+60
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(60,60,{"seq":2,"state":state.serialize(),"moves":[{"board":4,"cell":0,"seq":2}],"both_moved":true})); quiet(bundle)
	device_now = T0-300+86; ui.tick_online()
	ok(ui.prompt_state() == "ask","new turn: prompt allowance resets")
	ui.controls.still_here.pressed.emit()
	respond(bundle,"/still-here",409,env(86,60,{"seq":2,"state":state.serialize(),"still_here_used":true,"both_moved":true,"error":"You already confirmed this turn"}))
	ui.tick_online(); ok(ui.prompt_state() == "move" and not ui.controls.has("still_here"),"409 still_here_used hides the button")
	ui.go_home(); ui.free(); await frames()
	device_now = T0-300+3

func end_messages():
	for case in [
		["no_show",null,true,"NightNight didn't show up — match cancelled, no loss","online_end"],
		["cancelled",null,true,"NightNight left — match cancelled, no loss","online_end"],
		["abandoned",{"winner":1,"reason":"abandoned"},true,"NightNight disconnected — you win",""],
		["timeout",{"winner":2,"reason":"timeout"},false,"Time ran out — you lose",""],
		["forfeit",{"winner":1,"reason":"forfeit"},true,"NightNight left — you win",""]]:
		var bundle = make_ui("end-"+case[0]); var ui = bundle.ui
		start_match(bundle,{"both_moved":case[1] != null})
		ui.transport._poll()
		respond(bundle,"/rooms/N9ABC?",200,env(40,0,{"status":"closed","end_reason":case[0],"result":case[1],"opponent_left":case[2],"poll_after_ms":0,"turn_expires_at":null,"still_there_at":null}))
		ok(ui.end_message == case[3],"end message "+case[0]+": "+ui.end_message)
		ok(ui.transport._timer.is_stopped(),"polling stops on closed ("+case[0]+")")
		if case[4] == "online_end":
			ok(ui.overlay == "online_end" and ui.controls.modal_copy.text == case[3] and ui.controls.has_all(["end_lobby","end_menu"]),"cancelled card for "+case[0])
			ok(ui.game.status == 0,"no winner recorded for "+case[0])
		else:
			ok(ui.game.status == int(case[1].winner) and ui.message == case[3],"result flow carries the end line for "+case[0])
		ui.go_home(); ui.free(); await frames()

func chat():
	var bundle = make_ui("chat"); var ui = bundle.ui
	start_match(bundle)
	var t = ui.transport
	ok(ui.controls.has("chat") and ui.controls.chat is ChatPanel.ChatButton,"chat button in game")
	ui.controls.chat.pressed.emit()
	ok(ui.chat_open and is_instance_valid(ui.chat_view) and ui.chat_view.can_send,"chat panel opens")
	var presets = ui.chat_view.controls.keys().filter(func(k): return k.begins_with("preset_"))
	ok(presets.size() == 3 and ui.chat_view.controls.preset_gg.caption == "Good game!","quick-chat chips come from server chat_presets")
	ok(ui.chat_view.controls.chat_input.max_length == 120,"input limited to 120 characters")
	ui.chat_view.controls.chat_input.text = "Nice one"; ui.chat_view.controls.chat_input.text_changed.emit("Nice one")
	ok(ui.chat_view.counter.text == "8/120","character counter")
	ui.chat_view.controls.chat_send.pressed.emit()
	var request = last_request(bundle,"/chat")
	ok(request.url.ends_with("/rooms/N9ABC/chat?chat_since=0") and request.method == HTTPClient.METHOD_POST and request.body == {"token":"nws_fixture","text":"Nice one"},"send posts {text} with the seat token")
	var mine = {"id":42,"seat":1,"mine":true,"name":"Weaver","text":"Nice one","preset":null,"at":iso(T0+4)}
	respond(bundle,"/chat",200,env(4,0,{"ok":true,"message":mine,"chat":[mine],"chat_seq":42}))
	ok(t.chat_log.size() == 1 and t.chat_since == 42 and ui.chat_view.controls.chat_input.text == "","sent message appears; input clears")
	ok(ui.chat_view.list.get_child(0).get_meta("mine") and "[right]" in ui.chat_view.list.get_child(0).text,"own messages are right-aligned")
	ui.chat_view.controls.preset_gg.pressed.emit()
	ok(last_request(bundle,"/chat").body == {"token":"nws_fixture","preset":"gg"},"preset chip posts {preset}")
	respond(bundle,"/chat",200,env(5,0,{"ok":true,"chat":[],"chat_seq":42}))
	# Receive via poll; duplicates by id are ignored.
	var theirs = {"id":43,"seat":2,"mine":false,"name":"NightNight","text":"gl [b]hf[/b]","preset":null,"at":iso(T0+5)}
	t._poll(); ok("chat_since=42" in last_request(bundle,"/rooms/N9ABC?").url,"poll asks for messages after the last id")
	respond(bundle,"/rooms/N9ABC?",200,env(6,0,{"chat":[mine,theirs],"chat_seq":43})); quiet(bundle)
	ok(t.chat_log.size() == 2 and ui.chat_view.list.get_child_count() == 2,"poll delivers new messages, dedupes by id")
	ok("NightNight" in ui.chat_view.list.get_child(1).text and "[lb]b]" in ui.chat_view.list.get_child(1).text,"labeled with sender name; markup escaped")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(7,0,{"chat":[theirs],"chat_seq":43})); quiet(bundle)
	ok(t.chat_log.size() == 2,"repeat delivery is ignored")
	# Unread badge while closed.
	ui.toggle_chat(); ok(not ui.chat_open and ui.chat_unread == 0,"closing chat")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(8,0,{"chat":[{"id":44,"seat":2,"mine":false,"name":"NightNight","text":"your move","at":iso(T0+8)}],"chat_seq":44})); quiet(bundle)
	ok(ui.chat_unread == 1 and ui.controls.chat.unread == 1,"unread badge counts opponent messages")
	ui.toggle_chat(); ok(ui.chat_unread == 0,"opening clears unread")
	# Limits and errors.
	t.send_chat("x".repeat(130)); ok(last_request(bundle,"/chat").body.text.length() == 120,"client trims to 120")
	respond(bundle,"/chat",400,{"error":"Message not allowed"})
	ok(ui.chat_view.status_label.text == "Message not allowed","400 Message not allowed is shown")
	var before = count_requests(bundle,"/chat")
	ui.chat_view.controls.chat_input.text = "hello"; ui.chat_view.controls.chat_send.pressed.emit()
	respond(bundle,"/chat",429,{"error":"Too many messages","retry_after_seconds":7})
	ok(ui.chat_view.status_label.text == "Slow down — try again in 7 s","429 shows retry_after_seconds")
	ui.chat_view.controls.chat_send.pressed.emit()
	ok(count_requests(bundle,"/chat") == before+1 and "try again" in ui.chat_view.status_label.text,"no resend before retry_after")
	device_now += 8
	ui.chat_view.controls.chat_send.pressed.emit(); ok(count_requests(bundle,"/chat") == before+2,"send works again after retry_after")
	respond(bundle,"/chat",200,env(9,0,{"ok":true,"chat":[],"chat_seq":44}))
	# Layout: on 390x844 the open panel stays on screen and off the board's cells.
	var panel = ui.chat_view.get_rect()
	ok(Rect2(0,0,390,844).encloses(panel) and not panel.intersects(ui.layout.board),"chat panel inside 390x844 and below the board")
	for id in ui.chat_view.controls:
		var c = ui.chat_view.controls[id]
		if not c.is_visible_in_tree() or c.get_parent() != ui.chat_view: continue
		ok(Rect2(Vector2.ZERO,panel.size).encloses(c.get_rect()) and c.size.y >= 44,"chat control inside panel and touch-sized: "+id)
	ok(not ui.controls.chat.get_rect().intersects(ui.layout.board),"chat button clear of the board")
	# Anonymous / no screen name.
	ui.account.store.data.device_token = ""
	ok(ui.chat_notice() == "Create a screen name to chat","no account: create a screen name to chat")
	ui._rebuild(); ok(not ui.chat_view.can_send and ui.chat_view.controls.chat_send.disabled,"send disabled without a screen name")
	ui.account.store.data.device_token = "nwd_fixture"
	t.send_chat("hello"); respond(bundle,"/chat",403,{"error":"Create a screen name to chat"})
	ok(ui.chat_status == "Create a screen name to chat","server 403 text shown")
	ui.go_home(); ui.free(); await frames()

func moderation():
	var bundle = make_ui("mod"); var ui = bundle.ui
	start_match(bundle)
	var t = ui.transport
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(4,0,{"chat":[{"id":1,"seat":1,"mine":true,"name":"Weaver","text":"hi","at":iso(T0+1)},{"id":2,"seat":2,"mine":false,"name":"NightNight","text":"rude","at":iso(T0+2)}],"chat_seq":2})); quiet(bundle)
	ui.toggle_chat()
	ok(ui.chat_view.list.get_child_count() == 2,"both messages shown")
	ui.chat_view.controls.opponent_menu.pressed.emit()
	ok(ui.chat_view.view == "menu" and ui.chat_view.controls.has_all(["mute","block","report"]),"moderation menu on the opponent's name")
	var before = requests(bundle).size()
	ui.chat_view.controls.mute.pressed.emit()
	ok(ui.chat_muted and ui.chat_view.list.get_child_count() == 1 and requests(bundle).size() == before,"mute hides their messages locally, no request")
	ui.chat_view.controls.opponent_menu.pressed.emit(); ui.chat_view.controls.mute.pressed.emit()
	ok(not ui.chat_muted and ui.chat_view.list.get_child_count() == 2,"unmute")
	# Block: confirm dialog first.
	ui.chat_view.controls.opponent_menu.pressed.emit(); ui.chat_view.controls.block.pressed.emit()
	ok(ui.chat_view.view == "block" and "Block NightNight?" in ui.chat_view.get_node("BlockCopy").text,"block asks to confirm")
	ok(count_requests(bundle,"/players/block") == 0,"nothing sent before confirming")
	ui.chat_view.controls.block_confirm.pressed.emit()
	var request = last_request(bundle,"/players/block")
	ok(request.method == HTTPClient.METHOD_POST and request.body.size() == 2 and request.body.room_code == "N9ABC" and int(request.body.seat) == 2 and request.headers.has("Authorization: Bearer nwd_fixture"),"block posts {room_code, seat} with the device token")
	respond(bundle,"/players/block",200,{"ok":true,"blocked":true})
	ok(ui.chat_blocked and ui.chat_view.list.get_child_count() == 1 and ui.chat_view.status_label.text == "NightNight blocked","blocked player's messages disappear")
	# Report: reason picker + optional note.
	ui.chat_view.controls.opponent_menu.pressed.emit(); ui.chat_view.controls.report.pressed.emit()
	ok(ui.chat_view.view == "report","report dialog")
	for pair in Clock.REPORT_REASONS: ok(ui.chat_view.controls.has("reason_"+pair[0]),"reason "+pair[0])
	ok(ui.chat_view.controls.report_note.max_length == 500,"note limited to 500")
	ui.chat_view.controls.report_send.pressed.emit()
	ok(count_requests(bundle,"/reports") == 0 and "reason" in ui.chat_view.status_label.text,"a reason is required")
	ui.chat_view.controls.reason_harassment.pressed.emit()
	ui.chat_view.controls.report_note.text_changed.emit("  kept insulting  ")
	ui.chat_view.controls.report_send.pressed.emit()
	request = last_request(bundle,"/reports")
	ok(request.method == HTTPClient.METHOD_POST and request.body.size() == 4 and request.body.room_code == "N9ABC" and int(request.body.seat) == 2 and request.body.reason == "harassment" and request.body.note == "kept insulting" and request.headers.has("Authorization: Bearer nwd_fixture"),"report posts {room_code, seat, reason, note}")
	respond(bundle,"/reports",201,{"ok":true})
	ok(ui.chat_view.view == "chat" and ui.chat_view.status_label.text == "Thanks — we'll review it","report confirmation toast")
	ui.go_home(); ui.free(); await frames()

func blocked_list():
	var bundle = make_ui("blocks"); var ui = bundle.ui
	ui.open_online(); caps(bundle,NEW_CAPS); ui.go_home()
	ui.show_settings()
	ok(ui.controls.has("blocked_players"),"Settings has Blocked players when chat is advertised")
	ui.controls.blocked_players.pressed.emit()
	var request = last_request(bundle,"/players/blocks")
	ok(ui.overlay == "blocked" and request.method == HTTPClient.METHOD_GET and request.headers.has("Authorization: Bearer nwd_fixture"),"GET /players/blocks with device token")
	respond(bundle,"/players/blocks",200,{"blocks":[{"name":"NightNight","blocked_at":iso(T0)}]})
	ok(ui.controls.has("unblock_NightNight"),"blocked name listed with Unblock")
	ui.controls.unblock_NightNight.pressed.emit()
	request = last_request(bundle,"/players/block")
	ok(request.method == HTTPClient.METHOD_DELETE and request.body == {"name":"NightNight"},"Unblock sends DELETE {name}")
	respond(bundle,"/players/block",200,{"ok":true,"blocked":false})
	ok(respond(bundle,"/players/blocks",200,{"blocks":[]}),"list refreshes after unblock")
	ok(not ui.controls.has("unblock_NightNight") and ui.controls.blocked_status.text == "No blocked players.","empty list copy")
	ui.controls.done.pressed.emit(); ok(ui.overlay == "settings","back to Settings")
	ui.free(); await frames()

func polling():
	ok(Clock.poll_ms({"poll_after_ms":1500},1,false) == 1500 and Clock.poll_ms({"poll_after_ms":1500},1,true) == 5000,"poll_after_ms honored; hidden slows to 5 s")
	ok(Clock.poll_ms({"poll_after_ms":8000},1,true) == 8000 and Clock.poll_ms({"poll_after_ms":0},1,false) == 0,"max(hint, 5000) when hidden; 0 stops")
	var state = Rules.new().serialize()
	ok(Clock.poll_ms({"status":"waiting"},1,false) == 3000 and Clock.poll_ms({"status":"active","state":state},2,false) == 1500 and Clock.poll_ms({"status":"active","state":state},1,false) == 3000 and Clock.poll_ms({"status":"finished"},1,false) == 4000 and Clock.poll_ms({"status":"closed"},1,false) == 0,"fallback rates for old servers")
	ok(Clock.backoff_ms(1) == 1000 and Clock.backoff_ms(2) == 2000 and Clock.backoff_ms(3) == 4000 and Clock.backoff_ms(9) == 5000,"reconnect backoff")
	var bundle = make_ui("poll"); var ui = bundle.ui
	start_match(bundle)
	var t = ui.transport
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(4,0,{"poll_after_ms":1500}))
	ok(not t._timer.is_stopped() and absf(t._timer.wait_time-1.5) < .01,"next poll scheduled at poll_after_ms")
	t.set_background(true); ok(t.poll_delay_ms() == 5000,"backgrounded app polls every 5 s")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(5,0,{"poll_after_ms":1500}))
	ok(absf(t._timer.wait_time-5.0) < .01 and not t._timer.is_stopped(),"hidden keeps polling, slower")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	ok(not t.background and absf(t._timer.wait_time-1.5) < .01,"focus returns to the normal rate at once")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT); ok(t.background,"focus loss marks the app backgrounded")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	quiet(bundle)
	# Own polls failing: quiet "Reconnecting…" and backoff; no error message spam.
	ui.message = ""
	t._poll(); pending(bundle,"/rooms/N9ABC?").respond(0,{},HTTPRequest.RESULT_CANT_CONNECT)
	ok(t.reconnecting and ui.online_lines()[0] == "Reconnecting…" and ui.message == "","failed poll shows Reconnecting…")
	ok(absf(t._timer.wait_time-1.0) < .01,"first retry after 1 s")
	t._poll(); pending(bundle,"/rooms/N9ABC?").respond(503,{"error":"busy"})
	ok(absf(t._timer.wait_time-2.0) < .01 and ui.message == "","second retry backs off")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(9,0,{"poll_after_ms":1500}))
	ok(not t.reconnecting and t.poll_failures == 0 and absf(t._timer.wait_time-1.5) < .01,"recovers on the next good poll")
	t._poll(); respond(bundle,"/rooms/N9ABC?",200,env(10,0,{"status":"finished","poll_after_ms":0}))
	ok(t._timer.is_stopped(),"poll_after_ms 0 stops polling")
	ui.go_home(); ui.free(); await frames()

func api_override():
	ok(Clock.api_override("localhost","http://127.0.0.1:8787") == "http://127.0.0.1:8787","?api honored on localhost")
	ok(Clock.api_override("127.0.0.1","http://localhost:3000/") == "http://localhost:3000","?api honored on 127.0.0.1")
	ok(Clock.api_override("elexerly.github.io","http://127.0.0.1:8787") == "","?api ignored on GitHub Pages")
	ok(Clock.api_override("nineweave.grok.me","http://localhost:3000") == "","?api ignored on the live site")
	ok(Clock.api_override("localhost","https://evil.example") == "" and Clock.api_override("localhost","javascript:alert(1)") == "","?api only points at a local server")

func layouts():
	for view in [Vector2(390,844),Vector2(1366,768),Vector2(390,664)]:
		var bundle = make_ui("layout-"+str(view.x)+"x"+str(view.y),view); var ui = bundle.ui
		device_now = T0-300+3
		start_match(bundle)
		var screen = Rect2(Vector2.ZERO,view)
		var board: Rect2 = ui.layout.board
		for mark in [1,2]:
			var ring = ui.timer_ring_rect(mark)
			ok(screen.encloses(ring) and not ring.intersects(board),"timer ring %d inside %s and off the board" % [mark,view])
		ok(not ui.controls.chat.get_rect().intersects(board) and screen.encloses(ui.controls.chat.get_rect()),"chat button placement "+str(view))
		ok(not ui.controls.chat.get_rect().intersects(ui.controls.settings.get_rect()) and not ui.controls.chat.get_rect().intersects(ui.controls.home.get_rect()),"chat button clear of header buttons "+str(view))
		ui.toggle_chat()
		var panel = ui.chat_view.get_rect()
		ok(screen.encloses(panel),"chat panel on screen "+str(view))
		if view != Vector2(390,664): ok(not panel.intersects(board),"chat panel off the board "+str(view))
		ui.toggle_chat()
		device_now = T0-300+27; ui.tick_online()
		var prompt = ui.prompt_layer.get_rect()
		ok(screen.encloses(prompt) and ui.controls.has("still_here") and prompt.encloses(ui.controls.still_here.get_rect()),"Still there? on screen with its button "+str(view))
		if view == Vector2(390,844): ok(not prompt.intersects(board),"Still there? leaves the board cells tappable")
		ui.go_home()
		# Waiting screen with chat at every size: touch targets and bounds.
		for size in [view,Vector2(568,320),Vector2(844,390)]:
			ui.set_view_size(size); ui.open_online(); ui.create_online(); respond_end(bundle,"/rooms",201,waiting_env()); quiet(bundle)
			for id in ui.controls:
				var c = ui.controls[id]
				ok(c.size.x >= 44 and c.size.y >= 44 and Rect2(Vector2.ZERO,size).encloses(c.get_rect()),"waiting control %s at %s" % [id,size])
			ok(ui.controls.has("chat"),"waiting chat button at "+str(size))
		ui.free(); await frames()
	device_now = T0-300+3
