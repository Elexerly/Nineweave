extends SceneTree
const Main = preload("res://main/main.tscn")
const HTTP = preload("res://net/http_polling_transport.gd")
const API = preload("res://net/json_api.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Account = preload("res://net/device_account.gd")
const Screen = preload("res://ui/online_screen.gd")
const Fake = preload("res://tests/fake_http.gd")
const Profile = preload("res://characters/profile.gd")
const Settings = preload("res://settings/store.gd")
const Roster = preload("res://characters/roster.gd")
const Rules = preload("res://kernel/rules.gd")
const F = preload("res://tests/fixtures.gd")
class RecordingTransport extends "res://net/http_polling_transport.gd":
	var departures: Array = []
	func _dispatch_leave(room: String, credential: String):
		departures.append({"path":"/rooms/"+room+"/leave","body":{"token":credential},"headers":API.authorization(credential)})
var checks: int = 0
var failures: int = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func clean_store(name: String):
	var path = "user://r4c-"+name+".cfg"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	return DeviceStore.new(path)
func make_account(name: String):
	var account = Account.new(); account.store = clean_store(name)
	var fake = Fake.new(); account.api.request_factory = func(): return fake
	return {"account":account,"fake":fake}
func envelope(seat: int = 2, round_number: int = 1, state: Dictionary = {}) -> Dictionary:
	return {"code":"N9ABC","seat":seat,"token":"nws_fixture","seq":state.get("history",[]).size(),"state":Rules.new().serialize() if state.is_empty() else state,"status":"waiting","private":false,"opponent":"","opponent_left":false,"characters":{str(seat):"erik_comet"},"match":{"round":round_number,"seat":seat,"local":false,"remote":false},"result":null}
func run():
	urls_and_storage()
	await json_boundary()
	await protocol()
	await player_actions_preempt_polls()
	await real_leave_dispatch()
	await account_flow()
	await outage_registration()
	await onboarding_ui()
	await controller_online()
	await leaderboard_and_layout()
	print("NINEWEAVE_ROUND4C ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func urls_and_storage():
	for origin in ["https://elexerly.github.io","http://localhost:8080","http://127.0.0.1:8060","null",""]:
		ok(HTTP.origin_base(origin) == "https://nineweave.grok.me","live origin for "+origin)
	ok(HTTP.origin_base("https://nineweave.grok.me") == "https://nineweave.grok.me","same origin uses absolute API path")
	ok(HTTP.LIVE_ORIGIN == API.LIVE_ORIGIN,"transport shares single live-origin constant")
	var store = clean_store("persist")
	ok(not store.complete(),"fresh consent missing")
	ok(store.keep_device("nwd_saved","Weaver"),"keep registered device")
	ok(not store.complete(),"token/name alone are not consent")
	var consent = DeviceStore.consent_payload("2026-11-15T12:00:00Z")
	ok(consent == {"tos_version":"2026-11-15","privacy_version":"2026-11-15","accepted_at":"2026-11-15T12:00:00Z","age_confirmed":true},"exact consent fields")
	store.accept_consent("Weaver",consent)
	var copy = DeviceStore.new(store.path)
	ok(copy.complete() and copy.data.device_token == "nwd_saved","device and consent persist")
	ok(not copy.keep_device("nws_seat","Bad") and copy.data.device_token == "nwd_saved","seat cannot replace persistent device")
	ok(not copy.keep_device("nwd_","Bad") and copy.data.device_token == "nwd_saved","empty device-token prefix cannot become an online credential")
	copy.data.tos_version = "old"; ok(not copy.complete(),"new legal version requires onboarding")
	var local = clean_store("local-consent")
	local.accept_consent("Weaver",consent); local.data.pending_sync = true; local.save()
	ok(local.complete() and not local.online_ready() and not local.has_device_token(),"local consent unlocks play without inventing a credential")
	ok(DeviceStore.new(local.path).data.pending_sync,"pending sync survives restart")
	for name in ["", "   ", "x".repeat(25)]:
		local.data.screen_name = name; ok(not local.complete(),"stored invalid name cannot complete onboarding")
	for name in ["X", "x".repeat(24)]:
		local.data.screen_name = name; ok(local.complete(),"stored 1–24 character name completes onboarding")
func json_boundary():
	var api = API.new(); var fake = Fake.new(); api.base_url = ""; api.request_factory = func(): return fake
	root.add_child(api); await frames(1)
	var results: Array = []; api.completed.connect(func(op,response,data,problem): results.append([op,response,data,problem]))
	api.submit("/me",HTTPClient.METHOD_GET,{},"first","nwd_fixture")
	api.submit("/me",HTTPClient.METHOD_PATCH,{"last_hero_id":"cryon"},"second","nwd_fixture")
	ok(fake.requests.size() == 1 and fake.requests[0].url == "https://nineweave.grok.me/api/nineweave/me","absolute same-origin URL and single flight")
	fake.respond(200,{"screen_name":"Patrick"})
	ok(fake.requests.size() == 2 and fake.requests[1].method == HTTPClient.METHOD_PATCH,"pending account writes run after GET")
	fake.respond(200,{})
	ok(results.size() == 2 and results[1][0] == "second","queued response routed to operation")
	api.submit("/rooms",HTTPClient.METHOD_GET,{},"cancelled"); api.cancel_all(); fake.respond(200,{"rooms":[]})
	ok(results.size() == 2,"cancelled lobby result cannot update later screen")
	fake.immediate_error = ERR_CANT_CONNECT; api.submit("/rooms",HTTPClient.METHOD_GET,{},"offline")
	ok("Online server not available" in results.back()[3],"immediate request failure surfaced without engine error")
	api.free(); await frames()
func protocol():
	var t = RecordingTransport.new(); var fake = Fake.new(); t.api.request_factory = func(): return fake
	root.add_child(t); t.device_token = "nwd_device"; t.player_name = "Patrick"; t.character_id = "erik_comet"
	var events = {"errors":[],"left":0,"moves":[],"states":[],"starts":[],"characters":[]}
	t.error.connect(func(value): events.errors.append(value))
	t.opponent_left.connect(func(): events.left += 1)
	t.move_received.connect(func(b,c,seq): events.moves.append([b,c,seq]))
	t.state_received.connect(func(state,seq): events.states.append([state,seq]))
	t.match_started.connect(func(seat,round_number): events.starts.append([seat,round_number,t.remote_character_id]))
	t.character_received.connect(func(seat,id): events.characters.append([seat,id]))
	t.private_room = true; t.password = "secret"; t.create_room()
	var request = fake.requests.back()
	ok(request.url == API.LIVE_ORIGIN+API.API_PATH+"/rooms" and request.method == HTTPClient.METHOD_POST,"native create URL/method")
	ok(request.headers.has("Authorization: Bearer nwd_device"),"create uses device bearer")
	ok(request.body == {"name":"Patrick","character_id":"erick_comet","private":true,"password":"secret"},"create public/private canonical payload")
	var initial = envelope(); initial.private = true; fake.respond(201,initial)
	ok(t.token == "nws_fixture" and t.device_token == "nwd_device" and t.seat == 2,"random host O does not overwrite device")
	ok(t.password.is_empty(),"password discarded after joining")
	t._poll(); request = fake.requests.back()
	ok(request.url.ends_with("/rooms/N9ABC?since=0") and request.headers.has("Authorization: Bearer nws_fixture"),"poll uses seat header, sequence query only")
	ok(not "nws_" in request.url and not "nwd_" in request.url,"secrets never in URLs")
	var active = envelope(); active.status = "active"; active.opponent = "Dana"; active.characters = {"1":"nova_sable","2":"erik_comet"}
	fake.respond(200,active)
	ok(t.remote_character_id == "aiden_vortex","incoming alias canonicalized")
	t.send_move(4,4,1); request = fake.requests.back()
	ok(request.body.size() == 4 and request.body.board == 4 and request.body.cell == 4 and request.body.seq == 1 and request.body.token == "nws_fixture","move body retains seat contract")
	var state = Rules.new(); state.play(4,4)
	var ack = active.duplicate(true); ack.seq = 1; ack.state = state.serialize(); ack.moves = [{"board":4,"cell":4,"seq":1}]
	fake.respond(200,ack); ok(events.moves == [[4,4,1]],"authoritative move applied once")
	t._poll(); fake.respond(200,ack); ok(events.moves.size() == 1,"duplicate acknowledgement ignored")
	state.play(4,0)
	var conflict = ack.duplicate(true); conflict.seq = 2; conflict.state = state.serialize(); conflict.error = "Resync this room"
	t.send_move(4,4,2); fake.respond(409,conflict)
	ok(t.sequence == 2 and events.states.back()[1] == 2 and events.errors.back() == "Resync this room","conflict applies authoritative snapshot before showing error")
	state.play(0,4); state.play(4,1)
	var ordered = active.duplicate(true); ordered.seq = 4; ordered.state = state.serialize(); ordered.moves = [{"board":4,"cell":1,"seq":4},{"board":0,"cell":4,"seq":3}]
	t._poll(); fake.respond(200,ordered)
	ok(events.moves.slice(1) == [[0,4,3],[4,1,4]] and t.sequence == 4,"out-of-order wire moves replay in sequence")
	var gap = ordered.duplicate(true); gap.seq = 6; gap.moves = [{"board":1,"cell":0,"seq":6}]
	t._poll(); fake.respond(200,gap)
	ok(events.moves.size() == 3 and t.sequence == 6 and events.states.back()[1] == 6,"move gap falls back to full snapshot/seq")
	t.request_rematch(); request = fake.requests.back()
	ok(request.body.size() == 2 and request.body.round == 1 and request.body.token == "nws_fixture" and request.headers.has("Authorization: Bearer nws_fixture"),"rematch round/body/header")
	var offered = ack.duplicate(true); offered.match.local = true; offered.match.remote = false; fake.respond(200,offered)
	ok(t.rematch_status() == "WAITING FOR OPPONENT…","one rematch agreement waits")
	t._poll(); var next = envelope(1,2); next.status = "active"; next.opponent = "Dana"; next.characters = {"1":"erick_comet","2":"aiden_vortex"}; fake.respond(200,next)
	ok(t.seat == 1 and t.match_round == 2 and t.sequence == 0 and not t.local_rematch,"round increment swaps seat and resets seq/agreements")
	ok(events.starts == [[1,2,"aiden_vortex"]],"characters delivered before rematch presentation")
	t._poll(); fake.respond(200,ack); ok(t.match_round == 2 and t.sequence == 0,"old-round response cannot roll state back")
	next.opponent_left = true
	for i in range(2): t._poll(); fake.respond(200,next)
	ok(events.left == 1,"sticky opponent_left emits once")
	t.leave()
	ok(t.departures.size() == 1 and t.departures[0].path == "/rooms/N9ABC/leave" and t.departures[0].body.token == "nws_fixture","leave attempts authenticated forfeit before clear")
	ok(t.token.is_empty() and t.code.is_empty() and t.device_token == "nwd_device" and t.seat == 0,"leave clears seat, keeps device")
	t.password = "secret"; t.character_id = "ak_shade"; t.join_room("n9abc")
	request = fake.requests.back()
	ok(request.url.ends_with("/rooms/N9ABC/join") and request.body == {"name":"Patrick","character_id":"simon_shade","password":"secret"},"private join password/canonical identity")
	ok(request.headers.has("Authorization: Bearer nwd_device"),"join uses device after leaving seat")
	fake.respond(403,{"error":"Wrong password"}); ok(events.errors.back() == "Wrong password","403 error string surfaced")
	for pair in [[404,"Room expired"],[409,"Room is full"],[429,"Please slow down"],[503,"Online server not configured"]]:
		t.join_room("N9ABC"); fake.respond(pair[0],{"error":pair[1]}); ok(events.errors.back() == pair[1],"server error "+str(pair[0]))
	t.join_room("N9ABC"); fake.respond(200,"<html>offline</html>"); ok("Online server not available" in events.errors.back(),"non-JSON graceful failure")
	t.join_room("N9ABC"); fake.respond(0,{},HTTPRequest.RESULT_TIMEOUT); ok("Online server not available" in events.errors.back(),"timeout graceful failure")
	for alias in Roster.ALIASES:
		t.character_id = alias; ok(t.lobby_payload().character_id == Roster.canonical_id(alias),"outgoing alias "+alias)
	t.character_id = "unknown"; ok(Roster.valid(t.lobby_payload().character_id),"unknown hero never sent")
	t.free(); await frames()
func player_actions_preempt_polls():
	var t = RecordingTransport.new(); var fake = Fake.new(); t.api.request_factory = func(): return fake
	root.add_child(t); t.device_token = "nwd_device"; t.player_name = "Patrick"; t.character_id = "erik_comet"
	var events = {"errors":[],"moves":[]}
	t.error.connect(func(value): events.errors.append(value))
	t.move_received.connect(func(b,c,seq): events.moves.append([b,c,seq]))
	t.create_room(); var active = envelope(1); active.status = "active"; active.opponent = "Dana"; fake.respond(201,active)
	t._poll(); ok(fake.requests.back().method == HTTPClient.METHOD_GET and fake.active,"poll in flight")
	var sent = fake.requests.size()
	t.send_move(4,4,1); var request = fake.requests.back()
	ok(fake.requests.size() == sent+1 and request.url.ends_with("/rooms/N9ABC/moves") and request.method == HTTPClient.METHOD_POST,"move tapped during poll is POSTed immediately")
	ok(request.body.size() == 4 and request.body.board == 4 and request.body.cell == 4 and request.body.seq == 1 and request.body.token == "nws_fixture" and request.headers.has("Authorization: Bearer nws_fixture"),"preempting move keeps seq/seat contract")
	ok(not "Syncing room. Try again in a moment." in events.errors and events.errors.is_empty(),"poll never blocks a legal tap")
	t._poll(); ok(fake.requests.size() == sent+1,"no poll while move in flight")
	t.send_move(4,0,2); ok(fake.requests.size() == sent+1 and events.errors.back() == "Syncing room. Try again in a moment.","second move refused only while a move is in flight")
	var state = Rules.new(); state.play(4,4)
	var ack = active.duplicate(true); ack.seq = 1; ack.state = state.serialize(); ack.moves = [{"board":4,"cell":4,"seq":1}]
	fake.respond(200,ack); ok(events.moves == [[4,4,1]] and t.sequence == 1,"preempting move acknowledged")
	t._poll(); ok(fake.requests.back().url.ends_with("/rooms/N9ABC?since=1"),"polling resumes after move")
	t.request_rematch(); request = fake.requests.back()
	ok(request.url.ends_with("/rooms/N9ABC/rematch") and request.body.round == 1 and request.body.token == "nws_fixture","rematch preempts in-flight poll")
	fake.respond(200,ack); t.leave(); t.free(); await frames()
func real_leave_dispatch():
	var transport = HTTP.new(); var fake = Fake.new(); transport.api.request_factory = func(): return fake
	var goodbye = API.new(); var leave_http = Fake.new(); goodbye.request_factory = func(): return leave_http
	transport.farewell_factory = func(): return goodbye
	root.add_child(transport); transport.device_token = "nwd_persistent"; transport.code = "N9ABC"; transport.token = "nws_leaving"
	transport.leave()
	ok(leave_http.requests.size() == 1 and leave_http.requests[0].url.ends_with("/rooms/N9ABC/leave") and leave_http.requests[0].method == HTTPClient.METHOD_POST,"real leave dispatch POSTs endpoint")
	ok(leave_http.requests[0].body.token == "nws_leaving" and leave_http.requests[0].headers.has("Authorization: Bearer nws_leaving"),"real leave dispatch authenticates before clearing seat")
	transport.free(); await frames()
	ok(is_instance_valid(goodbye) and goodbye.is_inside_tree(),"forfeit request survives transport teardown")
	leave_http.respond(0,{},HTTPRequest.RESULT_TIMEOUT); await frames()
	ok(not is_instance_valid(goodbye),"failed leave cleans up without blocking navigation")
func account_flow():
	var bundle = make_account("flow"); var a = bundle.account; var fake = bundle.fake; root.add_child(a)
	var errors: Array = []; var complete = {"count":0}; a.error.connect(func(text): errors.append(text)); a.onboarding_complete.connect(func(): complete.count += 1)
	a.create_screen_name(""); ok(fake.requests.is_empty() and not errors.is_empty(),"empty name validated locally")
	a.create_screen_name("x".repeat(25)); ok(fake.requests.is_empty(),"24-character limit validated locally")
	for pair in [[409,"That screen name is taken"],[400,"Please choose another name"]]:
		a.create_screen_name("Rejected"); var req = fake.requests.back()
		ok(req.url.ends_with("/auth/device") and not req.headers.has("Authorization: Bearer "),"registration is unauthenticated")
		ok(req.body.get("screen_name","") == "Rejected","registration sends the chosen name")
		for key in ["tos_version","privacy_version","accepted_at","age_confirmed"]: ok(not req.body.has(key),"registration omits consent "+key+" so current production still accepts it")
		fake.respond(pair[0],{"error":pair[1]})
		ok(errors.back() == pair[1] and not a.store.complete() and a.store.data.device_token.is_empty(),"rejection surfaces error without local consent")
	a.create_screen_name("Patrick"); fake.respond(201,{"token":"nwd_new","player":{"screen_name":"Patrick"}})
	ok(a.store.data.device_token == "nwd_new" and not a.store.complete(),"successful registration persists token before consent PATCH")
	var patch = fake.requests.back()
	ok(patch.method == HTTPClient.METHOD_PATCH and patch.url.ends_with("/me") and patch.headers.has("Authorization: Bearer nwd_new"),"consent PATCH uses device")
	ok(patch.body.age_confirmed == true and patch.body.tos_version == "2026-11-15" and patch.body.privacy_version == "2026-11-15" and str(patch.body.accepted_at).ends_with("Z"),"UTC consent payload on PATCH")
	fake.respond(503,{"error":"Online server not available"})
	ok(a.store.complete() and not a.store.online_ready() and a.store.data.pending_sync and a.store.data.device_token == "nwd_new" and complete.count == 1,"consent outage completes locally and retains real token for sync")
	var accepted_at = a.store.data.accepted_at
	a.sync_pending(); ok(fake.requests.back().url.ends_with("/me") and fake.requests.back().body.accepted_at == accepted_at,"sync PATCHes existing account with original consent")
	fake.respond(200,{"screen_name":"Patrick"}); ok(a.store.online_ready() and not a.store.data.pending_sync and complete.count == 1 and DeviceStore.new(a.store.path).online_ready(),"successful sync persists and never repeats onboarding completion")
	a.rename("Taken"); fake.respond(409,{"error":"Name taken"}); ok(a.store.data.screen_name == "Patrick" and "taken" in a.rename_message,"rename rejection keeps last accepted name")
	# Current production rejects consent columns; local consent must still complete.
	var legacy_bundle = make_account("legacy"); var legacy = legacy_bundle.account; var legacy_http = legacy_bundle.fake
	var legacy_done = {"count":0}; legacy.onboarding_complete.connect(func(): legacy_done.count += 1)
	root.add_child(legacy)
	legacy.create_screen_name("Legacy")
	ok(not legacy_http.requests[0].body.has("tos_version") and not legacy_http.requests[0].body.has("accepted_at"),"legacy register body is name-only")
	legacy_http.respond(201,{"token":"nwd_legacy","player":{"screen_name":"Legacy"}})
	legacy_http.respond(400,{"error":"Unknown field: tos_version"})
	ok(legacy.store.complete() and legacy_done.count == 1,"unknown consent fields still complete local consent")
	legacy.free()
	a.rename("Dana"); fake.respond(200,{"screen_name":"Dana"}); ok(a.store.data.screen_name == "Dana","later rename persists")
	a.choose_hero("derrick_torque"); ok(fake.requests.back().body == {"last_hero_id":"devin_torque"},"hero PATCH canonicalized"); fake.respond(200,{})
	var count = fake.requests.size(); a.choose_hero("unknown"); ok(fake.requests.size() == count,"unknown hero not patched")
	a.refresh(); ok(fake.requests.back().method == HTTPClient.METHOD_GET and fake.requests.back().headers.has("Authorization: Bearer nwd_new"),"launch /me authentication"); fake.respond(200,{"screen_name":"Dana"})
	a.free(); await frames()
func outage_registration():
	for outage in ["connect","timeout","immediate","server","unavailable","invalid-json"]:
		var bundle = make_account("outage-"+outage); var a = bundle.account; var fake = bundle.fake
		root.add_child(a)
		var done = {"count":0}; a.onboarding_complete.connect(func(): done.count += 1)
		if outage == "immediate": fake.immediate_error = ERR_CANT_CONNECT
		a.create_screen_name("Local Weaver")
		match outage:
			"connect": fake.respond(0,{},HTTPRequest.RESULT_CANT_CONNECT)
			"timeout": fake.respond(0,{},HTTPRequest.RESULT_TIMEOUT)
			"server": fake.respond(503,{"error":"Maintenance"})
			"unavailable": fake.respond(502,{"error":"Can't reach the server"})
			"invalid-json": fake.respond(503,"<html>Service unavailable</html>")
		ok(a.store.complete() and not a.store.online_ready() and not a.busy and done.count == 1,"outage completes locally: "+outage)
		var stored = DeviceStore.new(a.store.path)
		ok(stored.complete() and stored.data.pending_sync and stored.data.screen_name == "Local Weaver" and stored.data.device_token.is_empty(),"outage persists name, consent and pending registration without fake token: "+outage)
		var original_consent = stored.data.accepted_at
		var path = a.store.path; a.free(); await frames()
		a = Account.new(); a.store = DeviceStore.new(path); fake = Fake.new(); a.api.request_factory = func(): return fake
		root.add_child(a); a.refresh()
		ok(a.store.complete() and fake.requests.size() == 1 and fake.requests[0].url.ends_with("/auth/device"),"next launch retries without blocking local play: "+outage)
		ok(fake.requests[0].headers == API.authorization(""),"pending registration sends no bearer credential: "+outage)
		fake.respond(201,{"token":"nwd_synced","player":{"screen_name":"Local Weaver"}})
		ok(fake.requests.back().headers.has("Authorization: Bearer nwd_synced") and fake.requests.back().body.accepted_at == original_consent,"only real server token and original consent used for sync: "+outage)
		fake.respond(200,{"screen_name":"Local Weaver"})
		ok(DeviceStore.new(path).online_ready() and not a.busy,"successful background sync persists online readiness: "+outage)
		a.free(); await frames()
	# 4xx errors stay rejections even when fallback copy mentions availability.
	for response in [400,401,403,404,409,422,429]:
		var bundle = make_account("reject-"+str(response)); var a = bundle.account; var fake = bundle.fake
		root.add_child(a); a.create_screen_name("Rejected"); fake.respond(response,{"error":"Online server not available"})
		ok(not a.store.complete() and not a.store.data.pending_sync and not a.busy,"reachable rejection never accepts locally: "+str(response))
		a.free(); await frames()
	var bundle = make_account("consent-conflict"); var a = bundle.account; var fake = bundle.fake
	root.add_child(a); a.create_screen_name("Rejected")
	fake.respond(201,{"token":"nwd_registered","player":{"screen_name":"Rejected"}})
	fake.respond(409,{"error":"Name taken"})
	ok(not a.store.complete() and not a.store.data.pending_sync and not a.busy,"consent PATCH 409 never falls back to local acceptance")
	a.create_screen_name("Available"); fake.respond(200,{"screen_name":"Available"})
	ok(a.store.online_ready() and a.store.data.screen_name == "Available","consent conflict can retry against existing real token")
	a.free(); await frames()
func make_ui(name: String, bypass: bool = false):
	var ui = Main.instantiate(); ui.test_online_bypass = bypass
	ui.account.store = clean_store(name); ui.profile = Profile.new("user://r4c-"+name+"-profile.cfg"); ui.settings = Settings.new("user://r4c-"+name+"-settings.cfg")
	ui.settings.values.sound = false; ui.settings.saved_game = {}
	# These controller fixtures exercise established players; Round 4e covers first play.
	ui.settings.values.tutorial_completed = true
	var fake = Fake.new(); ui.account.api.request_factory = func(): return fake
	var lobby_fake = Fake.new(); ui.online_api.request_factory = func(): return lobby_fake
	return {"ui":ui,"fake":fake,"lobby":lobby_fake}
func has_checkbox(node: Node) -> bool:
	if node is CheckBox or node is CheckButton: return true
	for child in node.get_children():
		if has_checkbox(child): return true
	return false
func onboarding_ui():
	var bundle = make_ui("onboarding"); var ui = bundle.ui; var fake = bundle.fake
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	ok(ui.page == "onboarding" and not ui.account.store.complete(),"first launch begins at distinct online onboarding")
	ok(not has_checkbox(ui),"onboarding has no checkboxes")
	ok(ui.online_view.agreement.get_parsed_text() == Screen.AGREEMENT and ui.online_view.agreement.visible,"agreement sentence visible verbatim")
	ok(ui.online_view.agreement.get_theme_font_size("normal_font_size") == 18,"phone agreement comfortable body size")
	ok(Screen.TERMS_URL in ui.online_view.agreement.text and Screen.PRIVACY_URL in ui.online_view.agreement.text,"Terms and Privacy absolute URLs wired into tappable links")
	ok(ui.controls.create_name.caption == "Create Screen Name","exact create label")
	ok(not ui.controls.has("offline") and not ui.controls.has("back") and not ui.controls.has("home"),"no offline, back or home control on mandatory name screen")
	var agreement = "By creating a screen name, you agree to our Terms of Service and Privacy Policy and confirm you are 13 or older or have a parent or guardian's permission."
	ok(ui.online_view.agreement.get_parsed_text() == agreement,"round 4e consent text unchanged exactly")
	var saved_game = {"state":Rules.new().serialize(),"human":1,"seconds":12}
	ui.settings.saved_game = saved_game
	var paths = {
		"go_home":func(): ui.go_home(),
		"computer":func(): ui.request_game("computer"),
		"pass-and-play":func(): ui.request_game("local"),
		"request online":func(): ui.request_game("online"),
		"resume_game":func(): ui.resume_game(),
		"request_resume":func(): ui.request_resume(),
		"open_online":func(): ui.open_online(),
		"start_game":func(): ui.start_game("local"),
		"character select":func(): ui.open_character_select(),
		"demo create":func(): ui.create_online(true),
		"demo join":func(): ui.join_online("N9ABC",true),
		"live create":func(): ui.create_online(),
		"live join":func(): ui.join_online("N9ABC"),
		"leaderboard":func(): ui.open_leaderboard(),
		"stale home action":func(): ui._online_action("home",""),
		"settings":func(): ui.show_settings(),
		"tutorial":func(): ui.start_tutorial(true),
		"email":func(): ui.open_account_email(),
		"close overlay":func(): ui._close_overlay(),
		"QA position":func(): ui.debug_load_position(Rules.new().serialize()),
	}
	for path in paths:
		paths[path].call()
		ok(ui.page == "onboarding" and ui.overlay.is_empty() and not ui.board.visible and not ui.title_label.visible and not ui.cinematic.active,"first-run guard: "+path)
		ok(ui.controls.has("create_name") and not ui.controls.has("computer") and ui.transport == null,"guard leaves only name form: "+path)
	for key in [KEY_ESCAPE,KEY_BACK]:
		var event = InputEventKey.new(); event.keycode = key; event.pressed = true; ui._input(event)
		ok(ui.page == "onboarding" and ui.overlay.is_empty(),"Escape/back cannot dismiss onboarding: "+str(key))
	ui.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST); ui.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	ok(ui.page == "onboarding" and not auto_accept_quit and not quit_on_go_back,"Android back and window close cannot bypass or auto-dismiss first run")
	for event in [InputEventMouseButton.new(),InputEventScreenTouch.new()]:
		event.position = Vector2(1,1); event.pressed = true; ui._input(event)
		ok(ui.page == "onboarding" and ui.online_view.mouse_filter == Control.MOUSE_FILTER_STOP,"outside pointer cannot dismiss name panel")
	OS.set_environment("NW_SCENARIO","versus"); ui._clip_preview(); OS.unset_environment("NW_SCENARIO")
	ok(ui.page == "onboarding" and not ui.test_online_bypass and not ui.cinematic.active,"QA deep link cannot opt real first launch out")
	ui.page = "game"; ui.overlay = "setup"; ui._rebuild()
	ok(ui.page == "onboarding" and ui.overlay.is_empty() and not ui.play_cell(0,0),"rebuild repairs stale/deep-linked playable screen")
	ok(fake.requests.is_empty() and bundle.lobby.requests.is_empty(),"blocked routes perform no account or lobby requests")
	var opened: Array = []; ui.online_view.link_opener = func(url): opened.append(url)
	ui.online_view.agreement.meta_clicked.emit(Screen.TERMS_URL); ui.online_view.agreement.meta_clicked.emit(Screen.PRIVACY_URL)
	ui.online_view.open_legal("https://example.invalid")
	ok(opened == [Screen.TERMS_URL,Screen.PRIVACY_URL],"both legal links route to their exact URLs through stub opener")
	ok(ui.online_view.agreement.get_content_height() <= ui.online_view.agreement.size.y,"phone agreement fits at body size")
	ui.controls.screen_name.text = "Patrick"; ui.controls.screen_name.text_changed.emit("Patrick"); ui.controls.create_name.pressed.emit()
	ok(ui.controls.create_name.disabled,"submission guarded against duplicate registration")
	fake.respond(409,{"error":"Name taken"}); ok(ui.page == "onboarding" and ui.online_view.status == "Name taken" and not ui.account.store.complete(),"name rejection stays on visible retry screen")
	ui.go_home(); ok(ui.page == "onboarding" and not ui.controls.create_name.disabled,"409 cannot be bypassed and form remains retryable")
	ui.controls.create_name.pressed.emit(); fake.respond(0,{},HTTPRequest.RESULT_CANT_CONNECT)
	ok(ui.page == "email" and ui.account.store.complete() and ui.account.store.data.pending_sync,"outage creates local name and continues to optional email")
	ui.controls.continue_email.pressed.emit(); ui.go_home()
	ok(ui.page == "title" and ui.controls.has_all(["computer","local","online"]),"local name permits playable title after optional email")
	ui.request_game("computer"); ok(ui.page == "character_select","computer not blocked by server")
	ui.request_game("local"); ok(ui.page == "character_select","pass-and-play not blocked by server")
	ui.go_home(); ui.request_online(); ok(ui.page == "online" and fake.active and bundle.lobby.requests.is_empty(),"opening Online syncs local registration before fetching lobby")
	fake.respond(201,{"token":"nwd_onboard","player":{"screen_name":"Patrick"}}); fake.respond(200,{"screen_name":"Patrick"})
	ok(ui.page == "online" and ui.online_state == "lobby" and ui.account.store.online_ready(),"synced registration unlocks live lobby without repeating optional email")
	ok(bundle.lobby.requests.back().url.ends_with("/rooms") and not ui.lobby_timer.is_stopped(),"lobby fetch and 2.5-second refresh active")
	bundle.lobby.respond(200,{"rooms":[{"code":"N9ABC","host_name":"Dana","host_hero":"nova_sable"}]})
	ok(ui.public_rooms.size() == 1 and ui.online_view.list.get_child_count() == 1,"public rooms mapped into tappable list")
	ui.go_home(); ok(ui.lobby_timer.is_stopped(),"lobby refresh stops on leaving screen")
	ui.free(); await frames()
	bundle = make_ui("first-success"); ui = bundle.ui; fake = bundle.fake; root.add_child(ui); ui.set_process(false)
	ui.controls.screen_name.text_changed.emit("First"); ui.controls.create_name.pressed.emit(); fake.respond(201,{"token":"nwd_first","player":{"screen_name":"First"}}); fake.respond(200,{"screen_name":"First"})
	ui.controls.continue_email.pressed.emit()
	ok(ui.page == "title","first launch success continues to title")
	ui.free(); await frames()
func controller_online():
	var bundle = make_ui("controller"); var ui = bundle.ui; var fake = bundle.fake
	ui.account.store.keep_device("nwd_controller","Patrick"); ui.account.store.accept_consent("Patrick",DeviceStore.consent_payload())
	ui.profile.data.character_id = "cryon"
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	ok(fake.requests.back().url.ends_with("/me"),"existing device fetches /me on launch")
	fake.respond(200,{"screen_name":"Patrick","last_hero_id":"mateo_ricochet"})
	ok(ui.profile.data.character_id == "ethan_ricochet","launch last hero uses canonical alias")
	ui._confirm_hero("ak_shade","Patrick"); ok(fake.requests.back().body == {"last_hero_id":"simon_shade"},"confirmed selection PATCHes hero")
	fake.respond(200,{"last_hero_id":"simon_shade"})
	ui.account.refresh(); fake.respond(200,{"screen_name":"Patrick","last_hero_id":"cryon"})
	ok(ui.profile.data.character_id == "simon_shade","late /me cannot overwrite player selection")
	ui.go_home(); ui.open_online(); bundle.lobby.respond(0,{},HTTPRequest.RESULT_CANT_CONNECT)
	ok("Can't reach" in ui.online_view.status and ui.public_rooms.is_empty(),"lobby network failure leaves usable empty list")
	ui._refresh_lobby(); bundle.lobby.respond(200,{"rooms":[]})
	ui._online_action("private",""); ok(ui.online_state == "private" and ui.controls.has_all(["password","create_private","join_private"]),"private create/join form reachable")
	ui.controls.password.text_changed.emit("shared secret"); ui._rebuild()
	ok(ui.controls.password.text == "shared secret" and ui.controls.password.secret,"password survives relayout and is masked")
	var transport = RecordingTransport.new(); var room_http = Fake.new(); transport.api.request_factory = func(): return room_http
	ui._attach_transport(transport); transport.create_room(); room_http.respond(201,envelope(2))
	ok(ui.online_state == "waiting" and ui.human_mark == 2 and ui.controls.has("cancel"),"random O host sees waiting code and cancel")
	transport._poll(); var active = envelope(2); active.status = "active"; active.opponent = "Dana"; active.characters = {"1":"nova_sable","2":"ak_shade"}; room_http.respond(200,active)
	ok(ui.page == "game" and ui.human_mark == 2 and ui.game.turn == 1 and ui.cinematic.kind == "versus","live HTTP enters existing X-first versus flow")
	ok(ui.rival_character == "aiden_vortex" and not ui.controls.has("undo") and not ui.controls.has("hint"),"live heroes and online controls")
	ui.cinematic.advance(3.01); ui.cinematic.skip()
	var won = F.big_tactic(1); won.play(2,2)
	var finished = active.duplicate(true); finished.seq = won.history.size(); finished.state = won.serialize(); finished.status = "finished"; finished.result = {"winner":1,"reason":"win"}
	transport._poll(); room_http.respond(200,finished)
	ok(ui.game.status == 1 and not ui.board.win_fx.is_empty(),"finished snapshot recovers existing winner flow")
	ui._show_spotlight(); ui.cinematic.advance(5.1); ui.cinematic.skip(); ui.controls.again.pressed.emit()
	var waiting = finished.duplicate(true); waiting.match.local = true; room_http.respond(200,waiting)
	ok(ui.controls.again.disabled and transport.rematch_status() == "WAITING FOR OPPONENT…","HTTP rematch waits for second agreement")
	transport._poll(); var next = envelope(1,2); next.status = "active"; next.opponent = "Dana"; next.characters = {"1":"simon_shade","2":"aiden_vortex"}; room_http.respond(200,next)
	ok(ui.human_mark == 1 and ui.game.history.is_empty() and ui.game.turn == 1 and ui.cinematic.kind == "versus","HTTP rematch swaps X/O and starts clean versus")
	ui.cinematic.advance(3.01); ui.cinematic.skip()
	# Identical polls must leave animations untouched.
	ui.board.clock = 7.5; transport._poll(); room_http.respond(200,next)
	ok(ui.board.clock == 7.5 and not ui.cinematic.active,"identical snapshot does not reset animation")
	var closed = next.duplicate(true); closed.status = "closed"; closed.result = {"winner":1,"reason":"forfeit"}; closed.opponent_left = true
	transport._poll(); room_http.respond(200,closed)
	ok(ui.game.status == 1 and not ui.remote_ready and not ui.board.win_fx.is_empty(),"forfeit uses official full-match winner")
	ui.go_home(); ok(transport.departures.size() == 1,"main menu attempts leave before freeing transport")
	ui.free(); await frames()
func leaderboard_and_layout():
	var mapped = preload("res://main/main.gd").leaderboard_payload({})
	ok(mapped.players.is_empty() and mapped.me.is_empty(),"empty leaderboard maps safely")
	var bundle = make_ui("leaderboard",true); var ui = bundle.ui; root.add_child(ui); ui.set_process(false)
	var payload = {"players":[{"rank":1,"screen_name":"Dana","matches_won":12,"matches_played":20}],"me":{"screen_name":"Patrick","matches_won":2,"matches_played":10,"boards_won":99,"rank":80}}
	mapped = ui.leaderboard_payload(payload)
	ok(mapped.players == [{"rank":1,"screen_name":"Dana","matches_won":12}] and mapped.me.rank == 80 and mapped.me.matches_won == 2,"top players plus off-list own rank/wins")
	ok(not mapped.me.has("boards_won") and not mapped.players[0].has("boards_won"),"public presentation excludes small-board scores")
	ui.open_leaderboard(); ui._online_response("leaderboard",200,payload,"")
	ok(ui.leaderboard_players.size() == 1 and ui.leaderboard_me.rank == 80,"leaderboard response reaches screen")
	var float_payload = JSON.parse_string('{"players":[{"rank":1.0,"screen_name":"Dana","matches_won":0.0},{"rank":5.0,"screen_name":"Weaver","matches_won":0.0}],"me":{"screen_name":"Patrick","rank":5.0,"matches_won":0.0,"matches_played":1.0}}')
	ok(float_payload.players[0].rank is float and float_payload.me.matches_won is float,"live JSON fixture supplies floating-point numbers")
	mapped = ui.leaderboard_payload(float_payload)
	ok(mapped.players[0].rank is int and mapped.players[0].matches_won is int and mapped.me.rank is int and mapped.me.matches_won is int and mapped.me.matches_played is int,"JSON ranks and match counts normalize to integers")
	ui._online_response("leaderboard",200,float_payload,"")
	for raw_floats in [false,true]:
		if raw_floats:
			# The view must also format numbers when used without the controller mapper.
			ui.leaderboard_players = float_payload.players; ui.leaderboard_me = float_payload.me; ui._rebuild()
		var painted: Array[String] = []
		for node in ui.online_view.find_children("*","Label",true,false): painted.append(node.text)
		var painted_text = "\n".join(painted)
		ok("1" in painted and "5" in painted and "0" in painted,"leaderboard paints integer rank and wins, raw floats="+str(raw_floats))
		ok("0 matches won" in painted_text and "Rank #5" in painted_text,"own record paints integer wins and rank, raw floats="+str(raw_floats))
		ok(not "1.0" in painted_text and not "5.0" in painted_text and not "0.0" in painted_text,"painted leaderboard has no float suffixes, raw floats="+str(raw_floats))
	var unranked = ui.leaderboard_payload({"players":[{"rank":null,"matches_won":0.0}],"me":{"rank":null,"matches_won":0.0,"matches_played":0.0}})
	ok(unranked.players[0].rank == null and unranked.me.rank == null,"missing ranks remain unranked after integer normalization")
	ui._online_response("leaderboard",200,{"players":[],"me":{"screen_name":"Patrick","rank":1,"matches_won":0,"matches_played":0}},"")
	var text = ""
	for node in ui.online_view.get_children():
		if node is Label: text += node.text
	ok("Unranked" in text and "0 matches won" in text and "play a match to appear" in text,"zero-game player shown honestly even if API supplies hypothetical rank")
	float_payload.me.matches_played = 0.0
	ui._online_response("leaderboard",200,float_payload,"")
	text = ""
	for node in ui.online_view.get_children():
		if node is Label: text += node.text
	ok("Unranked" in text and "0 matches won" in text and "play a match to appear" in text and not "0.0" in text,"zero-game JSON player retains integer wins and unranked copy")
	for size in [Vector2(360,640),Vector2(390,844),Vector2(568,320),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(size)
		for screen in ["lobby","private","waiting","leaderboard","onboarding"]:
			ui.page = "online" if screen in ["lobby","private","waiting"] else screen
			ui.online_state = screen; ui._rebuild(); await frames(1)
			ok(not has_checkbox(ui.online_view),"no consent checkbox "+screen+str(size))
			for id in ui.controls:
				var control = ui.controls[id]
				ok(control.size.x >= 44 and control.size.y >= 44,"touch target %s %s %s" % [screen,size,id])
				if screen != "onboarding" or size.y >= 600:
					ok(Rect2(Vector2.ZERO,size).encloses(control.get_rect()),"screen bounds %s %s %s" % [screen,size,id])
	for scenario in ["onboarding","online_lobby","online_private","online_leaderboard","online_unranked"]:
		ui.debug_scenario(scenario); ok(ui.page in ["onboarding","online","leaderboard"],"producer capture fixture "+scenario)
	ui.go_home(); ui.free(); await frames()
