extends SceneTree
## Round 5a captures: waiting room, joined beat, turn ring, Still there?, chat, report,
## leave confirm, no-show card and the old-server game. All HTTP goes to the test fake.
const Main = preload("res://main/main.tscn")
const Fake = preload("res://tests/fake_http.gd")
const Rules = preload("res://kernel/rules.gd")
const NEW_CAPS = {"protocol":2,"online2":true,"chat":true,"tournaments":false,"email":true,"chat_presets":{"gg":"Good game!","nice":"Nice move","rematch":"Rematch?","gl":"Good luck!","hi":"Hi!","thanks":"Thanks!","wow":"Wow!","oops":"Oops!"}}
var fakes: Array = []
var T0: float = 0.0
var device_now: float = 0.0
func _initialize(): run.call_deferred()
func iso(t: float) -> String:
	var whole = int(floor(t)); return Time.get_datetime_string_from_unix_time(whole)+".%03dZ" % int(round((t-whole)*1000))
func env(at: float, start: float, overrides: Dictionary = {}) -> Dictionary:
	var e = {"code":"N7QKD","seat":1,"token":"nws_capture","seq":0,"state":Rules.new().serialize(),"status":"active","private":false,"opponent":"NightNight","opponent_left":false,
		"characters":{"1":"vesper_vale","2":"auric_rex"},"match":{"round":1,"seat":1,"local":false,"remote":false},"result":null,"end_reason":null,"protocol":2,
		"server_now":iso(T0+at),"turn_started_at":iso(T0+start),"still_there_at":iso(T0+start+25),"turn_expires_at":iso(T0+start+35),"still_here_used":false,
		"turn_seconds":25,"still_there_seconds":10,"grace_seconds":60,"both_moved":false,"opponent_joined_at":iso(T0-5),"opponent_last_seen_at":iso(T0+at-1),"opponent_connected":true,
		"you":{"name":"Weaver","hero":"vesper_vale"},"players":{"1":{"name":"Weaver","hero":"vesper_vale","connected":true},"2":{"name":"NightNight","hero":"auric_rex","connected":true}},"poll_after_ms":600000}
	for key in overrides: e[key] = overrides[key]
	return e
func waiting_env() -> Dictionary:
	return env(0,0,{"status":"waiting","opponent":"","characters":{"1":"vesper_vale"},"players":{"1":{"name":"Weaver","hero":"vesper_vale","connected":true}},"turn_started_at":null,"still_there_at":null,"turn_expires_at":null,"opponent_joined_at":null,"opponent_connected":false})
func respond(fragment: String, code: int, data):
	for fake in fakes:
		if is_instance_valid(fake) and fake.active and not fake.requests.is_empty() and fake.requests.back().url.contains(fragment):
			fake.respond(code,data); return
	print("CAPTURE WARN: no pending request for ",fragment)
func respond_end(suffix: String, code: int, data):
	for fake in fakes:
		if is_instance_valid(fake) and fake.active and not fake.requests.is_empty() and fake.requests.back().url.ends_with(suffix):
			fake.respond(code,data); return
	print("CAPTURE WARN: no pending request for ",suffix)
func stop(main):
	if is_instance_valid(main.transport) and main.transport.get("_timer") != null: main.transport._timer.stop()
func staged(moves: Array) -> Rules:
	var r = Rules.new()
	for m in moves: r.play(m[0],m[1])
	return r
func run():
	if DisplayServer.get_name() == "headless":
		print("CAPTURE FAIL: need a real display (xvfb)"); quit(2); return
	var scenario = "waiting"; var out = "user://r5a.png"
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		if args[i] in ["--scenario","--out"] and i+1 < args.size():
			if args[i] == "--scenario": scenario = args[i+1]
			else: out = args[i+1]
			i += 1
		i += 1
	T0 = Time.get_unix_time_from_datetime_string("2026-11-15T12:00:00"); device_now = T0-42+3
	var main = Main.instantiate(); main.test_online_bypass = true
	main.http_request_factory = func():
		var fake = Fake.new(); fakes.append(fake); return fake
	root.add_child(main)
	main.set_view_size(Vector2(root.size)); main.settings.values.sound = false; main.sound.enabled = false
	main.settings.saved_game = {}; main.settings.values.reduced_motion = false; main.settings.values.tutorial_completed = true
	main.profile.data.character_id = "vesper_vale"; main.profile.data.display_name = "Weaver"; main.profile.data.onboarded = true
	main.settings.values.player_name = "Weaver"; main.settings.values.background_theme = "crystal"; main.settings.values.board_theme = "crystal"; main._apply_preferences()
	main.set_process(false)
	main.social.capabilities = {} if scenario == "old_server_chat_hidden" else NEW_CAPS.duplicate(true)
	main.open_online(); main.create_online()
	main.transport.now_source = func(): return device_now
	var ok_scenario = true
	if scenario == "old_server_chat_hidden":
		var old = {"code":"N7QKD","seat":1,"token":"nws_capture","seq":0,"state":Rules.new().serialize(),"status":"waiting","private":false,"opponent":"","opponent_left":false,"characters":{"1":"vesper_vale"},"match":{"round":1,"seat":1,"local":false,"remote":false},"result":null,"end_reason":null,"turn_expires_at":null}
		respond_end("/rooms",201,old); stop(main)
		var game = staged([[4,4],[4,0]])
		var active = old.duplicate(true); active.status = "active"; active.opponent = "OldFriend"; active.characters = {"1":"vesper_vale","2":"auric_rex"}
		active.seq = 2; active.state = game.serialize(); active.turn_expires_at = iso(device_now+170)
		main.transport._poll(); respond("/rooms/N7QKD?",200,active); stop(main)
		main.cinematic.advance(3.01)
	else:
		respond_end("/rooms",201,waiting_env()); stop(main)
		if scenario != "waiting":
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(3,0)); stop(main)
			if scenario != "opponent_joined":
				main._joined_beat_done(); main.cinematic.advance(3.01)
	match scenario:
		"waiting", "opponent_joined", "old_server_chat_hidden": pass
		"timer_ring":
			# X has moved; NightNight (O) is due with ~6 s left of the 25 s turn.
			var game = staged([[4,4],[4,0],[0,4]])
			device_now = T0-42+40
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(40,21,{"seq":3,"state":game.serialize(),"both_moved":true})); stop(main)
			device_now += 0.4
		"still_there":
			var game = staged([[4,4],[4,0]])
			device_now = T0-42+30
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(30,4,{"seq":2,"state":game.serialize(),"both_moved":true})); stop(main)
			device_now += 1.2; main.tick_online()
		"chat_open", "report_dialog":
			var game = staged([[4,4],[4,0],[0,4],[4,8]])
			var chat = [{"id":11,"seat":2,"mine":false,"name":"NightNight","text":"Good luck!","preset":"gl","at":iso(T0+1)},
				{"id":12,"seat":1,"mine":true,"name":"Weaver","text":"You too — may the threads be kind","preset":null,"at":iso(T0+4)},
				{"id":13,"seat":2,"mine":false,"name":"NightNight","text":"Nice move","preset":"nice","at":iso(T0+9)}]
			device_now = T0-42+12
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(12,10,{"seq":4,"state":game.serialize(),"both_moved":true,"chat":chat,"chat_seq":13})); stop(main)
			main.toggle_chat()
			if scenario == "report_dialog":
				main.chat_view.controls.opponent_menu.pressed.emit(); main.chat_view.controls.report.pressed.emit()
				main.chat_view.controls.reason_spam.pressed.emit()
			else:
				main._chat_draft = "gg, rematch?"; main._rebuild()
		"leave_confirm":
			var game = staged([[4,4],[4,0]])
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(8,6,{"seq":2,"state":game.serialize(),"both_moved":true})); stop(main)
			main.controls.home.pressed.emit()
		"end_no_show":
			main.transport._poll(); respond("/rooms/N7QKD?",200,env(40,0,{"status":"closed","end_reason":"no_show","opponent_left":true,"poll_after_ms":0,"turn_expires_at":null,"still_there_at":null,"turn_started_at":null})); stop(main)
		_:
			ok_scenario = false
	if not ok_scenario:
		print("CAPTURE FAIL: unknown scenario ",scenario); quit(2); return
	main.callout.callout = "" # The post-versus READY flourish is transient.
	main.backdrop.set_process(false); main.board.set_process(false)
	main.clock = 4; main.backdrop.clock = 4; main.board.clock = 4
	main.debug_refresh()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE FAIL: empty viewport"); quit(1); return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var saved = image.save_png(out) == OK
	print("CAPTURE ","PASS" if saved else "FAIL"," scenario=",scenario," size=",root.size," out=",out)
	quit(0 if saved else 1)
