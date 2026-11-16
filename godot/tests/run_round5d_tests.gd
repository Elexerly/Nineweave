extends SceneTree
## Deterministic client regressions; every HTTP request uses Fake, never live data.
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://net/device_store.gd")
const Account = preload("res://net/device_account.gd")
const Fake = preload("res://tests/fake_http.gd")
const ADDRESS = "weaver@example.com"
var checks: int = 0
var failures: int = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames():
	await process_frame; await process_frame
func player(enabled: bool = true, address: String = "") -> Dictionary:
	return {"screen_name":"Weaver","email":address,"email_status":"unverified","capabilities":{"email":enabled}}
func challenge(id: String) -> Dictionary:
	var now = int(Time.get_unix_time_from_system())
	return {"challenge_id":id,"expires_at":Time.get_datetime_string_from_unix_time(now+600)+"Z","resend_available_at":Time.get_datetime_string_from_unix_time(now-1)+"Z"}
func make_ui(tag: String, token: String = "nwd_stale", pending: bool = false, first_run: bool = false):
	var prefix = "user://r5d-"+tag
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	var ui = Main.instantiate()
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.account.store = Store.new(prefix+"-device.cfg")
	if not first_run:
		ui.account.store.accept_consent("Weaver",Store.consent_payload("2026-11-15T10:00:00Z"))
		ui.account.store.data.pending_sync = pending
		if not token.is_empty(): ui.account.store.keep_device(token,"Weaver")
		ui.account.store.save()
	elif not token.is_empty(): ui.account.store.keep_device(token,"Old name")
	var http = Fake.new(); ui.account.api.request_factory = func(): return http
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false)
	ui.set_view_size(Vector2(390,844))
	return {"ui":ui,"http":http}
func save(b):
	b.ui.controls.email.text = ADDRESS; b.ui.controls.save_email.pressed.emit()
func request_is(b, path: String, method: int, credential: String, body: Dictionary):
	var request = b.http.requests.back()
	ok(request.url.ends_with(path) and request.method == method and request.body == body,"exact request: "+path)
	var expected = PackedStringArray(["Content-Type: application/json"])
	if not credential.is_empty(): expected.append("Authorization: Bearer "+credential)
	ok(request.headers == expected,"exact authentication: "+path)
func recovered(b, consent: Dictionary):
	request_is(b,"/auth/device",HTTPClient.METHOD_POST,"",{"screen_name":"Weaver"})
	ok(b.ui.account.store.data.device_token.is_empty() and Store.new(b.ui.account.store.path).data.device_token.is_empty(),"401 clears stale credential in memory and on disk")
	ok(not b.ui.account.store.online_ready() and not b.ui.account.email_online_enabled(),"invalid identity cannot authorize email")
	b.http.respond(201,{"token":"nwd_replacement","player":player()})
	var body = consent.duplicate(); body.screen_name = "Weaver"
	request_is(b,"/me",HTTPClient.METHOD_PATCH,"nwd_replacement",body)
	ok(b.ui.account.busy,"registration waits for consent before readiness")
	b.http.respond(200,player())
	ok(b.ui.account.store.online_ready() and Store.new(b.ui.account.store.path).online_ready(),"new identity and consent persist as online ready")
func finish_code(b, id: String, credential: String = "nwd_replacement"):
	request_is(b,"/me",HTTPClient.METHOD_PATCH,credential,{"email":ADDRESS})
	b.http.respond(200,player(true,ADDRESS))
	request_is(b,"/me/email/verification",HTTPClient.METHOD_POST,credential,{})
	b.http.respond(200,challenge(id))
	ok(b.ui.page == "email" and b.ui.controls.has("email_code"),"Save reaches code entry without visiting the menu")
	ok(b.ui.controls.continue_email.caption == "Continue without verifying","code entry keeps the optional continue action")
	ok(b.ui.account.email_challenge.challenge_id == id and not b.ui.account.email_busy,"new challenge is usable")
	ok(b.ui.controls.email_code.text.is_empty(),"replacement challenge never retains an old code draft")
func run():
	await stale_me()
	await stale_consent()
	await stale_email()
	await other_me_writes()
	await recovery_conflicts()
	await pending_registration()
	await pending_capabilities()
	await honest_fallbacks()
	await delivery_failures()
	await bounded_recovery()
	print("NINEWEAVE_ROUND5D ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func stale_me():
	var b = make_ui("stale-me"); var ui = b.ui
	var consent = Store.consent_payload(ui.account.store.data.accepted_at)
	var errors: Array = []; ui.account.error.connect(func(message): errors.append(message))
	# Queue a second request carrying the invalid token; recovery must discard it.
	ui.account.choose_hero("cryon")
	b.http.respond(401,{"error":"Unknown device token"})
	recovered(b,consent)
	ok(errors.is_empty() and ui.page == "email","successful 401 recovery is silent and preserves onboarding")
	ok(b.http.requests.size() == 3,"queued stale-token writes are not dispatched during recovery")
	ui.free(); await frames()
func stale_consent():
	for pending in [false,true]:
		var b = make_ui("stale-consent-"+str(pending),"nwd_stale",pending,not pending); var ui = b.ui
		if not pending:
			# Startup may refresh an old token even before a new name is chosen.
			b.http.respond(200,player())
			ui.controls.screen_name.text_changed.emit("Weaver"); ui.controls.create_name.pressed.emit()
		var consent = ui.account._consent.duplicate()
		b.http.respond(401,{"error":"Invalid token"})
		recovered(b,consent)
		ok(ui.page == "email" and not ui.account.busy,"stale consent recovers in first-run and pending sync")
		ui.free(); await frames()
func stale_email():
	for operation in ["store","request","confirm"]:
		var b = make_ui("stale-email-"+operation); var ui = b.ui
		b.http.respond(200,player()); var consent = Store.consent_payload(ui.account.store.data.accepted_at)
		save(b)
		if operation != "store": b.http.respond(200,player(true,ADDRESS))
		if operation == "confirm":
			b.http.respond(200,challenge("ec_old")); ui.controls.email_code.text = "123456"; ui.controls.confirm_email.pressed.emit()
		b.http.respond(401,{"error":"Unknown device token"})
		ok(ui.page == "email" and ui.email_view.status == "Setting up your account…","email 401 waits visibly: "+operation)
		ok(ui.account.email_challenge.is_empty(),"old account challenge is discarded: "+operation)
		recovered(b,consent); finish_code(b,"ec_replacement")
		for request in b.http.requests:
			if request.headers.has("Authorization: Bearer nwd_replacement"):
				ok(not request.url.ends_with("/confirm"),"old confirmation is never replayed under the new identity")
		ui.controls.continue_email.pressed.emit(); ok(ui.page == "title","optional continue still works after recovery")
		ui.free(); await frames()
func other_me_writes():
	for operation in ["rename","hero"]:
		var b = make_ui("write-"+operation); b.http.respond(200,player())
		var consent = Store.consent_payload(b.ui.account.store.data.accepted_at)
		if operation == "rename": b.ui.account.rename("Other name")
		else: b.ui.account.choose_hero("cryon")
		b.http.respond(401,{"error":"Unknown token"})
		if operation == "rename":
			ok(b.http.requests.size() == 2 and b.ui.account.store.data.device_token == "nwd_stale","rename rejection preserves identity and never registers a replacement")
			ok(b.ui.account.store.data.screen_name == "Weaver" and "session rejected" in b.ui.account.rename_message.to_lower(),"rename rejection leaves name unchanged with sign-in guidance")
		else: recovered(b,consent)
		b.ui.free(); await frames()
func recovery_conflicts():
	for pending in [false,true]:
		var b = make_ui("conflict-"+str(pending),"nwd_stale",pending); var ui = b.ui
		b.http.respond(401,{"error":"Unknown token"})
		b.http.respond(409,{"error":"Conflict"})
		ok(ui.page == "onboarding" and not ui.account.store.complete(),"re-registration 409 restores mandatory name screen")
		ok("screen name is taken" in ui.online_view.status and "choose another" in ui.online_view.status,"name conflict explains how to proceed")
		ok(not ui.controls.has("offline") and not ui.controls.has("home") and not ui.controls.create_name.disabled,"name form has retry and no skip")
		ui.go_home(); ok(ui.page == "onboarding","conflict cannot escape to main menu")
		ok(Store.new(ui.account.store.path).data.registration_rejected,"conflict persists across restart")
		ui.controls.screen_name.text_changed.emit("Available"); ui.controls.create_name.pressed.emit()
		request_is(b,"/auth/device",HTTPClient.METHOD_POST,"",{"screen_name":"Available"})
		var available = player(); available.screen_name = "Available"
		b.http.respond(201,{"token":"nwd_available","player":available}); b.http.respond(200,available)
		ok(ui.page == "email" and ui.account.store.online_ready(),"replacement name completes normally")
		ui.free(); await frames()
func pending_registration():
	var b = make_ui("pending-register","",true); var ui = b.ui
	var consent = Store.consent_payload(ui.account.store.data.accepted_at)
	save(b)
	ok(ui.page == "email" and ui.account.email_busy and ui.controls.save_email.disabled,"Save during registration remains on optional email with duplicate guard")
	ok(ui.email_view.status == "Setting up your account…" and b.http.requests.size() == 1,"pending registration shows setup message without an unauthenticated email write")
	ui.account._process(Account.EMAIL_SETUP_TIMEOUT-1)
	ok(ui.account.email_busy and ui.page == "email","pending Save does not fall back before timeout")
	# An advertised capability at registration still cannot bypass consent.
	b.http.respond(201,{"token":"nwd_replacement","player":player()})
	var body = consent.duplicate(); body.screen_name = "Weaver"
	request_is(b,"/me",HTTPClient.METHOD_PATCH,"nwd_replacement",body)
	ok(ui.account.email_busy and not ui.account.email_pending,"waits for consent even after email capability arrives")
	b.http.respond(200,player()); finish_code(b,"ec_pending")
	ui.free(); await frames()
func pending_capabilities():
	for stale in [false,true]:
		var b = make_ui("pending-caps-"+str(stale)); var ui = b.ui
		save(b)
		ok(ui.page == "email" and ui.email_view.status == "Setting up your account…" and b.http.requests.size() == 1,"unknown capability waits for startup GET instead of assuming false")
		if stale:
			var consent = Store.consent_payload(ui.account.store.data.accepted_at)
			b.http.respond(401,{"error":"Unknown device token"}); recovered(b,consent)
		else:
			b.http.respond(200,player())
		finish_code(b,"ec_capabilities","nwd_replacement" if stale else "nwd_stale")
		ui.free(); await frames()
func honest_fallbacks():
	for reason in ["disabled","outage","timeout","forbidden"]:
		var b = make_ui("fallback-"+reason); var ui = b.ui
		save(b)
		match reason:
			"disabled": b.http.respond(200,player(false))
			"outage": b.http.respond(0,{},HTTPRequest.RESULT_TIMEOUT)
			"timeout": ui.account._process(Account.EMAIL_SETUP_TIMEOUT)
			"forbidden": b.http.respond(403,{"error":"Account access denied"})
		ok(ui.page == "email" and not ui.account.email_busy and ui.account.store.data.email == ADDRESS,"fallback remains visible and preserves address: "+reason)
		if reason == "forbidden":
			ok(ui.email_view.status == "Account access denied" and not "saved on this device only" in ui.email_view.status,"reachable rejection is not a local-only success")
		else:
			ok("saved on this device only" in ui.email_view.status and "Not verified" in ui.email_view.status,"local fallback explains storage and verification: "+reason)
		ok(b.http.requests.size() == 1,"fallback never sends an email without readiness: "+reason)
		if reason == "timeout":
			b.http.respond(200,player())
			ok(b.http.requests.size() == 1 and not ui.account.email_pending,"late setup response does not restart a timed-out save")
		ui.controls.continue_email.pressed.emit(); ok(ui.page == "title","explicit continue can leave fallback: "+reason)
		ui.free(); await frames()
	var b = make_ui("cancel-wait","",true); save(b)
	b.ui.controls.continue_email.pressed.emit()
	b.http.respond(201,{"token":"nwd_late","player":player()}); b.http.respond(200,player())
	ok(b.ui.page == "title" and b.http.requests.size() == 2,"explicit skip while setting up cancels queued email intent")
	b.ui.free(); await frames()
func bounded_recovery():
	var b = make_ui("bounded"); b.http.respond(401,{"error":"Unknown device token"})
	b.http.respond(201,{"token":"nwd_rejected","player":player()}); b.http.respond(401,{"error":"Still invalid"})
	ok(b.http.requests.size() == 3 and not b.ui.account.busy and b.ui.account.store.data.device_token.is_empty(),"repeated rejection clears fresh token without infinite re-registration")
	ok(b.ui.page == "onboarding" and "Please create your screen name again" in b.ui.online_view.status,"repeated rejection gives an actionable mandatory retry")
	b.ui.free(); await frames()
	b = make_ui("bounded-email"); b.http.respond(200,player()); save(b)
	b.http.respond(401,{"error":"Unknown token"})
	b.http.respond(201,{"token":"nwd_rejected","player":player()}); b.http.respond(200,player())
	b.http.respond(401,{"error":"Email still rejects token"})
	ok(b.http.requests.size() == 5 and not b.ui.account.email_busy and b.ui.account.store.data.device_token.is_empty(),"repeated email 401 is bounded even when consent succeeds")
	ok(b.ui.page == "onboarding","repeated email rejection offers mandatory name retry")
	b.ui.free(); await frames()

func delivery_failures():
	for response in [502,503]:
		var b = make_ui("delivery-"+str(response)); var ui = b.ui
		b.http.respond(200,player()); save(b)
		b.http.respond(200,player(true,ADDRESS))
		var detail = "Could not send email. Try again shortly." if response == 502 else "Email verification is not available on this server yet"
		b.http.respond(response,{"error":detail})
		var message = ui.account.email_message
		ui.set_view_size(Vector2(320,568)); await frames()
		ok(ui.email_view.status_label.get_visible_line_count() == ui.email_view.status_label.get_line_count(),"delivery error fits narrow phone status box")
		ok("could not send your code" in message if response == 502 else "not configured" in message,"delivery error distinguishes provider rejection from missing configuration")
		ok(ui.account.email_challenge.is_empty() and not ui.controls.email_code.editable,"failed delivery never enables an unusable code field")
		ok(ui.controls.resend_email.caption == "Send code" and not ui.controls.resend_email.disabled,"first failed delivery offers Send code rather than implying a code was sent")
		ok(ui.account.store.data.email == ADDRESS and ui.account.email_pending,"delivery failure retains saved address and verification flow")
		ui.account.refresh(); b.http.respond(200,player(true,ADDRESS))
		ok(ui.email_view.status == message and ui.account.email_pending,"account refresh preserves delivery failure and verification stage")
		ui.controls.resend_email.pressed.emit()
		request_is(b,"/me/email/verification",HTTPClient.METHOD_POST,"nwd_stale",{})
		b.http.respond(200,challenge("retried"))
		ok(ui.controls.email_code.editable and ui.account.email_challenge.challenge_id == "retried","retry reaches usable code entry")
		ui.controls.change_email.pressed.emit()
		ok(ui.controls.email.text == ADDRESS and ui.controls.save_email.visible,"change email preserves address for editing")
		ui.free(); await frames()
