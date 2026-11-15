extends SceneTree
## All HTTP is injected through Fake; this suite never opens a socket.
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const EmailScreen = preload("res://ui/email_screen.gd")
const NameScreen = preload("res://ui/online_screen.gd")
const Tutorial = preload("res://ui/tutorial.gd")
const CONSENT = "By creating a screen name, you agree to our Terms of Service and Privacy Policy and confirm you are 13 or older or have a parent or guardian's permission."
var checks: int = 0
var failures: int = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func path_for(id: String, kind: String) -> String: return "user://r4g-"+id+"-"+kind+".cfg"
func player(status: String = "none", email: String = "") -> Dictionary:
	return {"screen_name":"Weaver","email":null if email.is_empty() else email,"email_status":status,"email_verified_at":"2026-11-15T12:00:00Z" if status == "verified" else null,"capabilities":{"email":true}}
func challenge(id: String = "ec_fixture", resend: int = 83, expires: int = 601) -> Dictionary:
	var now = int(Time.get_unix_time_from_system())
	return {"challenge_id":id,"resend_available_at":Time.get_datetime_string_from_unix_time(now+resend)+".000Z","expires_at":Time.get_datetime_string_from_unix_time(now+expires)+".000Z","email":"weaver@example.com"}
func make_ui(id: String, registered: bool = true, fresh: bool = true):
	if fresh:
		for kind in ["device","settings","profile"]:
			var file = path_for(id,kind)
			if FileAccess.file_exists(file): DirAccess.remove_absolute(file)
	var ui = Main.instantiate()
	ui.account.store = Store.new(path_for(id,"device"))
	ui.settings = Settings.new(path_for(id,"settings")); ui.settings.values.sound = false
	ui.profile = Profile.new(path_for(id,"profile")); ui.profile.data.character_id = "cryon"
	ui.rival_character = "aurelia"
	if registered and fresh:
		ui.account.store.keep_device("nwd_fixture","Weaver")
		ui.account.store.accept_consent("Weaver",Store.consent_payload()); ui.account.store.skip_email()
	var http = Fake.new(); ui.account.api.request_factory = func(): return http
	var lobby = Fake.new(); ui.online_api.request_factory = func(): return lobby
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844))
	return {"ui":ui,"http":http,"lobby":lobby}
func save(bundle, address: String = "weaver@example.com"):
	bundle.ui.controls.email.text = address; bundle.ui.controls.save_email.pressed.emit()
func assert_request(bundle, path: String, method: int, body: Dictionary, message: String):
	var request = bundle.http.requests.back()
	ok(request.url.ends_with(path) and request.method == method and request.body == body,message)
	ok(request.headers.has("Authorization: Bearer "+bundle.ui.account.store.data.device_token),message+" uses real device token")
func store_and_send(bundle, address: String = "weaver@example.com"):
	save(bundle,address)
	assert_request(bundle,"/me",HTTPClient.METHOD_PATCH,{"email":address},"Save stores email before requesting code")
	ok(bundle.ui.account.store.data.email == address and bundle.ui.account.email_busy,"Save persists locally while waiting for PATCH")
	bundle.http.respond(200,player("unverified",address))
	assert_request(bundle,"/me/email/verification",HTTPClient.METHOD_POST,{},"only successful store starts code request")
	bundle.http.respond(200,challenge())
func finish_name(bundle, register_player: Dictionary, consent_player: Dictionary):
	bundle.ui.controls.screen_name.text_changed.emit("Weaver"); bundle.ui.controls.create_name.pressed.emit()
	ok(not bundle.http.requests.back().body.has("email"),"registration never includes email")
	bundle.http.respond(201,{"token":"nwd_registered","player":register_player})
	ok(not bundle.http.requests.back().body.has("email"),"consent PATCH never includes email")
	bundle.http.respond(200,consent_player)
func run():
	await capability_off()
	await onboarding_flow()
	await settings_and_restart()
	await optional_continue()
	await error_flows()
	await layouts()
	await tutorial_auto_advance()
	print("NINEWEAVE_ROUND4G ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func capability_off():
	for capabilities in [null,{}, {"email":false}, "invalid"]:
		var bundle = make_ui("off-"+str(checks)); var ui = bundle.ui
		var profile = {"screen_name":"Weaver"}
		if capabilities != null: profile.capabilities = capabilities
		bundle.http.respond(200,profile)
		ui.open_account_email(); var count = bundle.http.requests.size(); save(bundle)
		ok(ui.overlay == "settings" and ui.account.store.data.email == "weaver@example.com","absent/false capability keeps Settings save local")
		ok(not ui.account.email_capable and bundle.http.requests.size() == count,"absent/false capability sends no email request")
		ui.account.request_email_verification(); ui.account.confirm_email("123456")
		for request in bundle.http.requests:
			ok(not request.body.has("email") and not "/email/" in request.url,"older API is never probed with address or verification")
		ui.free(); await frames()
	# Same fallback in first-run optional step, including an explicit false.
	for capability in [false,true]:
		var bundle = make_ui("off-onboarding-"+str(capability),false); var ui = bundle.ui
		var profile = {"screen_name":"Weaver"}
		if capability: profile.capabilities = {"email":false}
		finish_name(bundle,profile,profile); var count = bundle.http.requests.size(); save(bundle)
		ok(ui.page == "title" and bundle.http.requests.size() == count,"onboarding email save stays local against old API")
		for request in bundle.http.requests: ok(not request.body.has("email"),"old registration and PATCH contain no email")
		ui.free(); await frames()
	# Even an advertised capability cannot invent a token for a pending local name.
	var local = make_ui("pending",false); var ui = local.ui
	ui.controls.screen_name.text_changed.emit("Weaver"); ui.controls.create_name.pressed.emit()
	local.http.respond(503,{"error":"Unavailable"}); ui.account.email_capable = true
	var count = local.http.requests.size(); save(local)
	ok(ui.page == "title" and ui.account.store.data.pending_sync and ui.account.store.data.device_token.is_empty(),"local-only name continues without a synthetic bearer")
	ok(local.http.requests.size() == count,"capability plus pending name still sends no address")
	ui.free(); await frames()
func onboarding_flow():
	var bundle = make_ui("onboarding",false); var ui = bundle.ui
	finish_name(bundle,player(),player())
	ok(ui.page == "email" and ui.account.email_online_enabled(),"register/consent player advertises capability for optional step")
	store_and_send(bundle)
	ok(ui.page == "email" and ui.controls.has_all(["email_code","resend_email","confirm_email","email_expiry"]),"onboarding Save shows code-entry stage")
	ok(ui.account.email_challenge.challenge_id == "ec_fixture" and ui.controls.verification_status.text == "Not verified","challenge stored without claiming verification")
	ok(ui.controls.resend_email.disabled and "Resend in 8" in ui.controls.resend_email.caption,"resend countdown uses supplied 83-second timestamp")
	ok("Code expires in" in ui.controls.email_expiry.text and "UTC" in ui.controls.email_expiry.text,"expiry is displayed from expires_at")
	ok(absf(Store.email_timestamp("2026-11-15T12:01:00.123Z")-Store.email_timestamp("2026-11-15T12:00:00Z"))-60 < .01,"ISO UTC timestamps handle fractional seconds")
	var count = bundle.http.requests.size(); ui.controls.resend_email.pressed.emit()
	ok(bundle.http.requests.size() == count,"cooldown blocks resend even if action is emitted directly")
	ui.controls.email_code.text_submitted.emit("12345")
	ok(bundle.http.requests.size() == count and "6-digit" in ui.email_view.status,"malformed code is rejected locally")
	ui.controls.email_code.text_changed.emit("12 34 56"); ui.set_view_size(Vector2(867,553))
	ok(ui.controls.email_code.text == "12 34 56","code draft survives resize")
	ui.controls.email_code.text_submitted.emit("12 34 56")
	assert_request(bundle,"/me/email/verification/confirm",HTTPClient.METHOD_POST,{"challenge_id":"ec_fixture","code":"123456"},"confirmation removes spaces and posts six digits")
	ok(ui.controls.verification_status.text == "Not verified","sending confirm cannot establish Verified")
	bundle.http.respond(200,player("unverified","weaver@example.com"))
	ok(ui.controls.verification_status.text == "Not verified","200 alone cannot establish Verified without server status")
	store_and_send(bundle)
	ui.controls.email_code.text = "123456"; ui.controls.confirm_email.pressed.emit()
	bundle.http.respond(200,{"player":player("verified","weaver@example.com")})
	ok(ui.controls.verification_status.text == "Verified" and ui.account.store.data.email_verified_at == "2026-11-15T12:00:00Z","only returned player establishes Verified and verified_at")
	ok(ui.page == "email" and ui.controls.continue_email.caption == "Continue","verified optional step still offers Continue")
	ui.controls.continue_email.pressed.emit(); ok(ui.page == "title","verified player reaches menu")
	ui.free(); await frames()
func settings_and_restart():
	var bundle = make_ui("settings"); var ui = bundle.ui
	bundle.http.respond(200,player()); ui.show_settings(); ui.controls.account_email.pressed.emit()
	store_and_send(bundle)
	ok(ui.overlay == "account" and not ui.email_view.onboarding,"Settings add uses the same optional code-entry flow")
	# Resend after the advertised timestamp, without another PATCH or an address body.
	ui.account.email_challenge.resend_available_at = challenge("unused",-1).resend_available_at
	ui._rebuild(); ui.controls.resend_email.pressed.emit()
	assert_request(bundle,"/me/email/verification",HTTPClient.METHOD_POST,{},"resend uses stored address")
	bundle.http.respond(200,challenge("ec_second"))
	ui.controls.email_code.text = "654321"; ui.controls.confirm_email.pressed.emit()
	ok(bundle.http.requests.back().body.challenge_id == "ec_second","resend replaces saved challenge id")
	bundle.http.respond(200,player("verified","weaver@example.com"))
	ok(ui.controls.verification_status.text == "Verified","Settings verifies from server payload")
	ui.controls.continue_email.pressed.emit(); ui.controls.account_email.pressed.emit(); save(bundle,"changed@example.org")
	ok(ui.controls.verification_status.text == "Not verified" and ui.account.store.data.email_verified_at.is_empty(),"changing verified address immediately clears local status")
	bundle.http.respond(200,player("unverified","changed@example.org")); bundle.http.respond(200,challenge("ec_changed"))
	ui.controls.email_code.text = "123456"; ui.controls.confirm_email.pressed.emit(); bundle.http.respond(200,player("verified","changed@example.org"))
	ok(ui.account.store.data.email == "changed@example.org" and ui.controls.verification_status.text == "Verified","Settings can change and verify an address")
	ui.free(); await frames()
	bundle = make_ui("settings",true,false); ui = bundle.ui; ui.open_account_email()
	ok(ui.controls.verification_status.text == "Not verified" and not ui.account.email_capable,"restart distrusts cached verified status and capability until GET")
	ok(bundle.http.requests.size() == 1 and bundle.http.requests[0].method == HTTPClient.METHOD_GET,"restart refreshes with GET without sending local address")
	bundle.http.respond(200,player("verified","changed@example.org"))
	ok(ui.controls.verification_status.text == "Verified" and ui.account.email_capable,"GET restores server verified status")
	ui.account.refresh(); bundle.http.respond(200,player("verified","different@example.org"))
	ok(ui.controls.verification_status.text == "Not verified","server status cannot verify a different local address")
	for status in ["none","unverified"]:
		ui.email_view.set_verification_status(status); ok(ui.controls.verification_status.text == "Not verified","server "+status+" maps to Not verified")
	# PATCH player objects can also enable the gate after an older/missing GET.
	ui.account.refresh(); bundle.http.respond(200,{"screen_name":"Weaver"})
	ui.account.rename("Weaver"); bundle.http.respond(200,player("unverified","changed@example.org"))
	ok(ui.account.email_capable,"successful PATCH player may advertise capability")
	ui.free(); await frames()
func optional_continue():
	for enabled in [false,true]:
		var bundle = make_ui("skip-"+str(enabled),false); var ui = bundle.ui
		var profile = player() if enabled else {"screen_name":"Weaver"}
		finish_name(bundle,profile,profile); var count = bundle.http.requests.size()
		ui.controls.continue_email.pressed.emit()
		ok(ui.page == "title" and ui.account.store.data.email_prompt_done and ui.account.store.data.email.is_empty(),"Continue without email skips with capability "+str(enabled))
		ok(bundle.http.requests.size() == count,"skip never sends email or code requests")
		ui.free(); await frames()
	var bundle = make_ui("skip-verifying",false); var ui = bundle.ui
	finish_name(bundle,player(),player()); store_and_send(bundle)
	var count = bundle.http.requests.size(); ui.controls.continue_email.pressed.emit()
	ok(ui.page == "title" and ui.account.store.data.email == "weaver@example.com" and bundle.http.requests.size() == count,"saved address can continue without verifying")
	ui.show_settings(); ui.controls.account_email.pressed.emit()
	ok(ui.controls.has("email_code"),"Settings can resume an optional verification left during this session")
	ui.free(); await frames()
func error_flows():
	# Run every requested error through both entry points, including PATCH failures.
	for onboarding in [false,true]:
		for response in [400,409,429,502,503]:
			for failed_operation in ["store","request","confirm"]:
				var bundle = make_ui("error-"+str(checks),not onboarding); var ui = bundle.ui
				if onboarding: finish_name(bundle,player(),player())
				else: bundle.http.respond(200,player()); ui.open_account_email()
				save(bundle)
				if failed_operation != "store": bundle.http.respond(200,player("unverified","weaver@example.com"))
				if failed_operation == "confirm":
					bundle.http.respond(200,challenge()); ui.controls.email_code.text = "123456"; ui.controls.confirm_email.pressed.emit()
				var error_text = "That email is already used by another account." if response == 409 else "Fixture server validation message."
				var count = bundle.http.requests.size()
				bundle.http.respond(response,{"error":error_text,"retry_after_seconds":137})
				ok(ui.page == "email" if onboarding else ui.overlay == "account","email error stays in its entry point")
				ok(ui.account.store.data.email == "weaver@example.com" and ui.controls.verification_status.text == "Not verified","errors retain local address without marking verified")
				if response in [400,409]: ok(ui.email_view.status == error_text,"400/409 display exact server error in "+failed_operation)
				elif response in [502,503]: ok(ui.email_view.status == "Email isn't available right now","provider/unavailable error uses consistent sentence")
				else:
					var wait = ui.account.email_retry_until-Time.get_unix_time_from_system()
					ok(wait > 135 and wait <= 137 and "137" in ui.email_view.status,"429 reads body retry_after_seconds")
					ok(ui.controls.resend_email.disabled and "Resend in 13" in ui.controls.resend_email.caption,"429 controls resend countdown")
					ui.controls.resend_email.pressed.emit(); ok(bundle.http.requests.size() == count,"429 guard blocks early retry")
				ok(not ui.account.email_busy and bundle.http.requests.size() == count,"error releases busy state and does not automatically retry")
				ui.free(); await frames()
		# Unknown challenge offers a new request, and never a room-specific message.
		var bundle = make_ui("not-found-"+str(onboarding),not onboarding); var ui = bundle.ui
		if onboarding: finish_name(bundle,player(),player())
		else: bundle.http.respond(200,player()); ui.open_account_email()
		store_and_send(bundle); ui.controls.email_code.text = "123456"; ui.controls.confirm_email.pressed.emit()
		bundle.http.respond(404,{"error":"Challenge not found"})
		ok("request a new code" in ui.email_view.status and not "Room" in ui.email_view.status and ui.account.email_challenge.is_empty(),"404 confirm asks for a new code")
		ui.controls.resend_email.pressed.emit(); assert_request(bundle,"/me/email/verification",HTTPClient.METHOD_POST,{},"404 retry requests a new code")
		bundle.http.respond(200,challenge("ec_replacement",0,-1))
		ok("expired" in ui.controls.email_expiry.text and ui.controls.confirm_email.disabled,"expired code is displayed and cannot be confirmed in form")
		ui.controls.change_email.pressed.emit(); ok(ui.controls.email.visible and not ui.controls.has("email_code"),"Change email returns to address editor")
		ui.free(); await frames()
	# A PATCH rate limit must retry PATCH, never send a code to an older address.
	var bundle = make_ui("store-retry"); var ui = bundle.ui
	bundle.http.respond(200,player()); ui.open_account_email(); save(bundle,"new@example.org")
	bundle.http.respond(429,{"error":"Wait","retry_after_seconds":137})
	ui.account.email_retry_until = 0; ui._rebuild(); ui.controls.resend_email.pressed.emit()
	assert_request(bundle,"/me",HTTPClient.METHOD_PATCH,{"email":"new@example.org"},"failed store is retried before any verification request")
	bundle.http.respond(200,player("unverified","new@example.org"))
	assert_request(bundle,"/me/email/verification",HTTPClient.METHOD_POST,{},"successful retried store proceeds to verification")
	ui.free(); await frames()
func layouts():
	var bundle = make_ui("layout",false); var ui = bundle.ui
	for dimensions in [Vector2(390,844),Vector2(1366,1024)]:
		ui.set_view_size(dimensions); await frames()
		var screen = ui.online_view
		ok(screen.agreement.get_parsed_text() == CONSENT and NameScreen.AGREEMENT == CONSENT,"consent remains verbatim at "+str(dimensions))
		ok(not ui.controls.has("offline") and not ui.controls.has("back") and not ui.controls.has("home"),"no Play Offline/Main Menu skip")
		var gap = screen.status_label.position.y-ui.controls.create_name.get_rect().end.y
		ok(gap >= 8 and gap <= 16 and screen._panel.size.y < 500,"status sits near Create and name panel is compact")
		ok(screen._panel.encloses(screen.status_label.get_rect()),"status remains inside compact card")
	finish_name(bundle,player(),player())
	for dimensions in [Vector2(360,640),Vector2(390,844),Vector2(1366,1024)]:
		ui.set_view_size(dimensions); await frames()
		var form = ui.email_view; var helper = form.helper_label
		ok(helper.text == EmailScreen.HELPER and "recover your account on a new device" in helper.text,"current recovery copy fully present")
		ok(helper.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and not helper.clip_text,"helper wraps without clipping")
		ok(helper.get_line_count() > 1 and helper.get_line_count()*helper.get_line_height() <= helper.size.y,"every line of helper fits at "+str(dimensions))
		ok(form.card.get_global_rect().encloses(helper.get_global_rect()),"full helper stays inside email card")
		ok(not helper.get_rect().intersects(ui.controls.email.get_rect()),"wrapped helper does not overlap email field")
		ok(Rect2(Vector2.ZERO,ui.layout.size).encloses(helper.get_global_rect()),"helper is visible in viewport")
	ui.set_view_size(Vector2(390,844)); store_and_send(bundle); await frames()
	var viewport = Rect2(Vector2.ZERO,ui.layout.size)
	for id in ["email_code","email_expiry","confirm_email","resend_email","change_email","continue_email"]:
		ok(viewport.encloses(ui.controls[id].get_global_rect()),"verification stage fits phone: "+id)
	for id in ["email_code","confirm_email","resend_email","change_email","continue_email"]:
		ok(ui.controls[id].size.y >= 44,"verification touch target: "+id)
	ui.free(); await frames()
func tutorial_auto_advance():
	var bundle = make_ui("tutorial-auto"); var ui = bundle.ui
	ui.settings.values.tutorial_completed = false
	ui.start_game("computer",2,true,true)
	ui.cinematic.advance(.81); ui.cinematic.skip()
	ok(ui.tutorial.active and ui.overlay == "tutorial" and ui.tutorial.step == 0,"first match still auto-opens the tutorial")
	ok(not ui.tutorial.controls.has("next"),"Next button is removed so a stuck web Next cannot block first play")
	ok(ui.tutorial.controls.skip.visible and ui.tutorial.controls.skip.size.y >= 44,"Skip remains on the first step")
	ok(Tutorial.STEP_SECONDS >= 3.0 and ui.tutorial.arrow_progress() < 1,"auto-advance waits until after the arrow would finish")
	# Main process is off in this suite; drive the tutorial clock explicitly.
	ui.tutorial.set_process(false)
	ui.tutorial.age = 0; ui.tutorial._ignore_next_delta = false
	ui.tutorial._process(2.9)
	ok(ui.tutorial.active and ui.tutorial.step == 0 and ui.tutorial.arrow_progress() >= 1.0,"2.9s finishes the arrow without leaving step 1")
	ui.tutorial._process(0.2)
	ok(ui.tutorial.active and ui.tutorial.step == 1,"step auto-advances once the 3s hold elapses")
	# A large first-frame delta after a step must not skip ahead.
	ui.tutorial._process(8)
	ok(ui.tutorial.active and ui.tutorial.step == 1,"the frame that opened a step cannot skip it")
	ui.tutorial._process(Tutorial.STEP_SECONDS)
	ok(ui.tutorial.step == 2,"the following tick advances after the full hold")
	while ui.tutorial.active and ui.tutorial.step < 5:
		ui.tutorial._ignore_next_delta = false; ui.tutorial.age = Tutorial.STEP_SECONDS; ui.tutorial._process(0)
	ok(ui.tutorial.active and ui.tutorial.step == 5,"arrives on the last step without finishing early")
	ui.tutorial._ignore_next_delta = false; ui.tutorial._process(Tutorial.STEP_SECONDS)
	ok(not ui.tutorial.active and ui.board.game == ui.game and not ui.board.frozen,"auto-advance through step 6 starts the match")
	ok(ui.settings.values.tutorial_completed and ui.thinking,"completion persists and opponent-first AI may resume")
	ui.thinking = false; ui.start_game("local")
	ok(not ui.tutorial.active,"second match does not auto-run the tutorial")
	# How to Play still replays, also auto-advances, and a tap can jump ahead.
	ui.go_home(); ui.controls.how.pressed.emit()
	ok(ui.tutorial.active and ui.tutorial.replay and ui.tutorial.step == 0,"How to play from the menu replays")
	ui.tutorial.set_process(false)
	var tap = InputEventMouseButton.new(); tap.button_index = MOUSE_BUTTON_LEFT; tap.pressed = false
	ui.tutorial._gui_input(tap)
	ok(ui.tutorial.step == 1,"optional tap still jumps ahead of the timer")
	var touch = InputEventScreenTouch.new(); touch.pressed = true
	ui.tutorial._gui_input(touch)
	touch.pressed = false; ui.tutorial._gui_input(touch)
	var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = false; mouse.device = -1
	ui.tutorial._gui_input(mouse)
	ok(ui.tutorial.step == 2,"touch plus emulated mouse still advances exactly once")
	ui.tutorial.skip()
	ok(not ui.tutorial.active and ui.settings.values.tutorial_completed,"Skip still ends a replay")
	ui.free(); await frames()
