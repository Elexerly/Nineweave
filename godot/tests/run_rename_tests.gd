extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var ui = Main.instantiate()
	var prefix = "user://rename-test"
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.account.store.accept_consent("Weaver",Store.consent_payload())
	ui.account.store.keep_device("nwd_test_rename","Weaver")
	var http = Fake.new(); ui.account.api.request_factory = func(): return http
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false)
	await process_frame
	# Resolve startup refresh using a verified fixture, never a live service.
	http.respond(200,{"screen_name":"Weaver","email":"weaver@example.com","email_status":"verified","email_verified_at":"2026-11-16T10:00:00Z","capabilities":{"email":true}})
	var a = ui.account
	ui.overlay = "settings"; ui._rebuild()
	ui.controls.player_name.text = "  New   Weaver  "; ui.controls.save_name.pressed.emit()
	ok(a.rename_pending() and ui.controls.save_name.disabled and not ui.controls.player_name.editable,"pending disables edits and save")
	ok("Checking" in ui.controls.name_status.text,"explicit checking state")
	var count = http.requests.size()
	a.rename("Duplicate")
	ok(http.requests.size() == count,"duplicate ignored")
	ok(http.requests.back().body == {"screen_name":"New Weaver"} and http.requests.back().method == HTTPClient.METHOD_PATCH,"only name submitted")
	ui._close_overlay()
	http.respond(200,{"screen_name":"New Weaver"})
	ok(ui.overlay != "settings","completion does not navigate back")
	ok(a.store.data.screen_name == "New Weaver" and ui.settings.values.player_name == "New Weaver","confirmed name propagated")
	ok(a.store.data.email_status == "verified" and a.store.data.email == "weaver@example.com" and a.store.data.email_verified_at == "2026-11-16T10:00:00Z","sparse rename preserves verification")
	ok(http.requests.size() == count,"rename sent no verification request")
	ui.overlay = "settings"; ui._rebuild()
	ok("saved" in ui.controls.name_status.text and not ui.controls.save_name.disabled,"reopen shows success")
	a.rename("Taken"); http.respond(409,{"error":"conflict"})
	ok("taken" in a.rename_message and a.store.data.screen_name == "New Weaver" and not a.rename_pending(),"taken preserves name and releases busy")
	a.rename("Rejected"); count = http.requests.size(); http.respond(401,{"error":"invalid token"})
	ok(http.requests.size() == count and a.store.data.device_token == "nwd_test_rename" and a.store.data.email_status == "verified","401 never creates new identity or clears verified data")
	ok("Session" in a.rename_message and not a.rename_pending(),"401 feedback")
	a.rename("Malformed"); http.respond(200,{"ok":true})
	ok(not a.rename_pending() and a.store.data.screen_name == "New Weaver","malformed response cannot claim save or lock UI")
	a.rename("Unavailable"); http.respond(503,{"error":"offline"})
	ok(not a.rename_pending() and a.store.data.screen_name == "New Weaver","outage preserves name")
	a.store.data.pending_sync = true; count = http.requests.size(); a.rename("Offline")
	ok(http.requests.size() == count and a.store.data.screen_name == "New Weaver" and "not changed" in a.rename_message,"offline no local rename or claim")
	a.store.data.pending_sync = false; a.rename(" ")
	ok(http.requests.size() == count and "1–24" in a.rename_message,"validation")
	a.rename("New Weaver")
	ok(http.requests.size() == count and "already" in a.rename_message,"unchanged name no request")
	for view in [Vector2(390,844),Vector2(568,320),Vector2(844,390)]:
		ui.set_view_size(view); ui.overlay = "settings"; ui._rebuild()
		ok(ui.controls.player_name.size.x >= 40 and ui.controls.save_name.size.x >= 60,"rename controls usable at "+str(view))
	ui.queue_free(); await process_frame; await process_frame
	print("Rename tests: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
