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
	ui.controls.sign_in.pressed.emit(); http = ui.recovery.api._request
	ok(ui.page == "recovery" and ui.controls.has("recovery_email"),"recovery available without name")
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
	ui._recovery_action("edit"); http = ui.recovery.api._request; ui.recovery.email = "known@example.com"; ui.recovery.request_code(); http.respond(200,challenge)
	ok(ui.recovery.message == generic,"known and unknown copy identical")
	ui.recovery.code = "123456"; ui.recovery.confirm(); http.respond(401,{"error":"unauthorized"})
	ok(account_http.requests.is_empty(),"401 never triggers auto registration")
	ui.recovery.confirm(); http.respond(503,{"error":"offline"})
	ok(ui.recovery.email == "known@example.com" and not ui.recovery.busy,"failure permits retry preserving email")
	ui.recovery.confirm(); ui._recovery_action("cancel")
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
