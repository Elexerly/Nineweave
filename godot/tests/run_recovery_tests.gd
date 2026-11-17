extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var ui = Main.instantiate()
	var prefix = "user://recovery-test"
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg")
	var http; var account_http = Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	ui.account.api.request_factory = func(): return account_http
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(320,568))
	await process_frame
	ok(ui.controls.has("sign_in"),"first-run existing-player entry")
	# Exercise the actual input pipeline, not just the button signal.
	ui._onboarding_name = "night"; ui._rebuild()
	await process_frame; await process_frame
	var position = ui.controls.sign_in.get_global_rect().get_center()
	for pressed in [true,false]:
		var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = pressed; mouse.position = position
		root.push_input(mouse,true)
	await process_frame; await process_frame
	http = ui.recovery.api._request
	ok(ui.page == "recovery","real sign-in click opens recovery")
	var motion = InputEventMouseMotion.new(); motion.position = Vector2(40,40); root.push_input(motion,true)
	ok(ui.page == "recovery","pointer motion does not eject recovery")
	# Continue after a failing pre-fix assertion to collect the complete regression.
	if ui.page != "recovery": ui._online_action("sign_in",""); http = ui.recovery.api._request
	await process_frame; await process_frame
	position = ui.controls.recovery_email.get_global_rect().get_center()
	for pressed in [true,false]:
		var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = pressed; mouse.position = position
		root.push_input(mouse,true)
	ok(ui.page == "recovery","email field press and release preserve recovery")
	if ui.page != "recovery": ui._online_action("sign_in",""); http = ui.recovery.api._request
	ui.controls.recovery_email.grab_focus()
	var key = InputEventKey.new(); key.keycode = KEY_N; key.unicode = 110; key.pressed = true
	root.push_input(key); key = key.duplicate(); key.pressed = false; root.push_input(key)
	await process_frame
	ok(ui.page == "recovery" and ui.recovery.email == "n","real keyboard entry reaches recovery email")
	if ui.page != "recovery": ui._online_action("sign_in",""); http = ui.recovery.api._request
	ok(ui.page == "recovery" and ui.controls.has("recovery_email"),"recovery available without name")
	var escape = InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; root.push_input(escape)
	ok(ui.page == "onboarding" and ui._onboarding_name == "night" and ui.controls.has("begin_create"),"Escape returns to retained screen-name draft")
	ui._online_action("sign_in",""); http = ui.recovery.api._request
	ui.recovery.email = "bad"; ui.recovery.request_code()
	ok(http.requests.is_empty(),"invalid email stays local")
	ui.recovery.email = "unknown@example.com"; ui.recovery.request_code()
	ok(http.requests.back().url.ends_with("/auth/email/recover") and http.requests.back().headers.size() == 1,"unauthenticated recovery only")
	var challenge = {"challenge_id":"ec_example","resend_available_at":"2020-01-01T00:00:00Z"}
	http.respond(200,challenge)
	var generic = ui.recovery.message
	ok("If this email" in generic and ui.controls.has("recovery_code"),"unknown email generic code UI")
	ui.recovery.code = "123456"; ui.recovery.confirm(); http.respond(400,{"error":"Invalid code"})
	ok(ui.account.store.data.device_token.is_empty() and not ui.account.store.complete(),"wrong code never creates identity")
	var edited_http = http
	var field = ui.controls.recovery_email
	field.grab_focus(); field.text = "unknown2@example.com"; field.text_changed.emit(field.text)
	http = ui.recovery.api._request
	ok(ui.recovery.email == "unknown2@example.com" and field.editable,"email is directly editable after code request")
	ok(ui.controls.recovery_email == field and field.has_focus(),"typing does not rebuild form or discard keyboard focus")
	ok(ui.recovery.code.is_empty() and ui.recovery.challenge.is_empty() and not ui.controls.recovery_code.visible,"edit retires prior code step")
	ok(http.requests.is_empty() and account_http.requests.is_empty(),"editing neither sends email nor registers account")
	ok("Send a new sign-in code" in ui.recovery.message and ui.controls.cancel_recovery.caption == "Back","clear edit guidance and neutral Back")
	edited_http.respond(200,{"challenge_id":"stale"})
	ok(ui.recovery.challenge.is_empty(),"old response cannot revive edited challenge")
	# Changing an address while a request is pending must retire its callback too.
	ui.recovery.request_code(); var pending_http = http
	field = ui.controls.recovery_email; field.text = "pending@example.com"; field.text_changed.emit(field.text)
	http = ui.recovery.api._request
	pending_http.respond(200,{"challenge_id":"late_wrong_address"})
	ok(not ui.recovery.busy and ui.recovery.challenge.is_empty(),"in-flight response cannot restore challenge for previous address")
	ui.recovery.code = "123456"; ui.recovery.confirm()
	ok(http.requests.is_empty(),"new address cannot submit old code before requesting a new challenge")
	ui.recovery.challenge = {"challenge_id":"cooldown","resend_available_at":"2099-01-01T00:00:00Z"}
	ui.recovery.update_email("cooldown@example.com"); ui.recovery.request_code()
	ok(http.requests.is_empty() and ui.recovery.retry_until > Time.get_unix_time_from_system(),"editing does not bypass resend cooldown")
	ui.recovery.retry_until = 0; http = ui.recovery.api._request
	ui.recovery.email = "known@example.com"; ui.recovery.request_code(); http.respond(400,{"error":"Invalid request"})
	ok("request a sign-in code" in ui.recovery.message and not "expired" in ui.recovery.message,"request failure does not claim invalid code")
	ui.recovery.request_code(); http.respond(200,challenge)
	ok(ui.recovery.message == generic,"known and unknown copy identical")
	ui.recovery.code = "123456"; ui.recovery.confirm(); http.respond(401,{"error":"unauthorized"})
	ok(account_http.requests.is_empty(),"401 never triggers auto registration")
	ui.recovery.confirm(); http.respond(503,{"error":"offline"})
	ok(ui.recovery.email == "known@example.com" and not ui.recovery.busy,"failure permits retry preserving email")
	ui.recovery.confirm(); ui._recovery_action("cancel")
	ok(ui._onboarding_name == "night" and ui.controls.has("begin_create"),"cancel preserves typed screen name")
	var player = Store.consent_payload(); player.screen_name = "OriginalPlayer"; player.email = "known@example.com"; player.email_status = "verified"; player.capabilities = {"email":true}
	http.respond(200,{"token":"nwd_old_late","player":player})
	ok(ui.page == "onboarding" and ui.account.store.data.device_token.is_empty(),"late reply after cancel ignored")
	var retired_http = http
	ui._online_action("sign_in",""); http = ui.recovery.api._request; ui.recovery.email = "known@example.com"; ui.recovery.request_code()
	retired_http.respond(200,{"token":"nwd_late","player":player,"player_id":"old"})
	ok(ui.recovery.busy and ui.recovery.challenge.is_empty() and ui.account.store.data.device_token.is_empty(),"late canceled callback cannot consume new request")
	http.respond(200,challenge)
	ui.recovery.code = "123456"; ui.recovery.confirm(); http.respond(200,{"token":"nwd_same_account","player":player,"player_id":"original"})
	ok(ui.page == "title","successful recovery enters app")
	ok(ui.account.store.data.screen_name == "OriginalPlayer" and ui.account.store.data.device_token == "nwd_same_account","confirmed existing identity retained")
	ok(ui.account.store.online_ready() and ui.account.store.data.email_status == "verified","server consent and verified email retained")
	ok(account_http.requests.is_empty(),"entire recovery never calls registration")
	ok(Store.new(prefix+"-device.cfg").data.device_token == "nwd_same_account","credential persisted after success")
	# Sparse consent must not inherit another local profile's consent.
	ui.page = "recovery"
	var sparse = player.duplicate(); sparse.erase("tos_version"); sparse.erase("accepted_at")
	ui._account_recovered("nwd_sparse",sparse)
	ok(ui.page == "onboarding" and not ui.account.store.complete(),"sparse server consent requires renewal")
	ok(ui.account.store.data.device_token == "nwd_sparse" and account_http.requests.is_empty(),"consent renewal retains recovered identity without registration")
	ui.queue_free(); await process_frame; await process_frame
	print("NINEWEAVE_RECOVERY ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
