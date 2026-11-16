extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(): await process_frame; await process_frame
func run():
	var prefix = "user://signout-test"
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	var ui = Main.instantiate()
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.account.store.accept_consent("Original",Store.consent_payload()); ui.account.store.keep_device("nwd_original","Original")
	ui.account.store.data.email_prompt_done = true
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("cryon","Original")
	var requests = []; var marker = [""]
	ui.account.store.deletion_marker_io = func(op):
		if op == "read": return marker[0]
		marker[0] = op.trim_prefix("write:"); return "ok"
	ui.account.api.request_factory = func(): var f = Fake.new(); requests.append(f); return f
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	ui.deletion.api.request_factory = func(): return Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); await frames()
	requests[0].respond(200,{"screen_name":"Original","email":"original@example.com","email_status":"verified","capabilities":{"email":true}})
	ui.show_settings(); ok(ui.controls.save_name.caption == "Change","rename caption is Change")
	ui.controls.account_email.pressed.emit(); ok(ui.controls.has("sign_out"),"signout available without deletion capability")
	ui.account.store.set_deletion_uncertain(true); ui._rebuild()
	ok(not ui.controls.has("sign_out"),"signout hidden while deletion unresolved")
	ui._confirm_signout(); ok(ui.account.store.data.device_token == "nwd_original","signout guard preserves uncertain identity")
	ui.account.store.set_deletion_uncertain(false); ui._rebuild()
	ui.controls.sign_out.pressed.emit(); ok("NOT deleted" in ui._signout_copy(),"signout distinguished from deletion")
	ui.controls.cancel_signout.pressed.emit(); ok(ui.account.store.data.device_token == "nwd_original","cancel preserves identity")
	ui.account.store.data.email_status = "not_verified"; ok("permanently lose access" in ui._signout_copy(),"unverified recovery warning")
	ui.account.store.data.pending_sync = true; ok("Local-only" in ui._account_status_copy(),"pending registration distinguished")
	ui.account.store.data.pending_sync = false
	for extent in [Vector2(320,568),Vector2(844,390)]:
		root.size = Vector2i(extent); ui.set_view_size(extent); ui.overlay = "account_options"; ui._rebuild(); await frames()
		ok(ui._modal_rect.encloses(ui.controls.sign_out.get_global_rect()),"account signout fits modal")
		ok(ui._modal_rect.encloses(ui.controls.account_options_back.get_global_rect()),"account Back fits modal")
		ui.overlay = "signout_confirm"; ui._rebuild(); await frames()
		ok(Rect2(Vector2.ZERO,extent).encloses(ui.controls.confirm_signout.get_global_rect()),"signout confirmation in viewport")
		ok(ui.controls.signout_copy.get_parent() is ScrollContainer,"warning scrolls without clipping")
	marker[0] = "pending"
	ui._confirm_signout(); await frames()
	ok(marker[0] == "pending" and ui.account.store.data.device_token == "nwd_original" and ui.account.store.data.deletion_uncertain,"late cross-tab deletion blocks signout without overwriting marker")
	ui.account.store.mark_deletion_resolved(false)
	ui._confirm_signout(); await frames()
	ok(ui.page == "account_choice" and ui.controls.has("sign_in") and ui.controls.has("new_account"),"explicit account choice after signout")
	ok(ui.account.store.data.signed_out and ui.account.store.data.device_token.is_empty(),"credential cleared")
	ok(marker[0].begins_with("signedout:"),"durable distinct signout marker")
	ok(ui.settings.saved_game.is_empty() and ui.profile.data.display_name == "You" and ui.social.blocks.is_empty(),"local user-specific data cleared")
	ui.account.refresh(); ui.account.sync_pending(); ui.account.create_screen_name("Accidental")
	ok(requests.back().requests.is_empty(),"signedout never auto-registers or refreshes")
	var saved = Store.new(prefix+"-device.cfg"); ok(saved.data.signed_out and saved.data.device_token.is_empty(),"reload remains signed out")
	var stale = Store.new(prefix+"-device.cfg"); stale.data.device_token = "nwd_old"; stale.data.deletion_resolution = "old"
	stale.deletion_marker_io = func(_op): return marker[0]
	stale.merge_deletion_marker(); ok(stale.data.signed_out and stale.data.device_token.is_empty(),"stale tab credentials invalidated")
	ui.controls.sign_in.pressed.emit(); ok(ui.page == "recovery","sign in opens recovery without registration")
	ui._recovery_action("cancel"); ok(ui.page == "account_choice","cancel returns to account choice")
	ui.controls.sign_in.pressed.emit()
	var recovered_player = Store.consent_payload(); recovered_player.screen_name = "Different"; recovered_player.email = "different@example.com"; recovered_player.email_status = "verified"
	ui._account_recovered("nwd_different",recovered_player); await frames()
	ok(not ui.account.store.data.signed_out and ui.account.store.data.device_token == "nwd_different" and ui.account.store.data.screen_name == "Different","successful recovery switches identity rather than restoring previous account")
	ok(marker[0].begins_with("recovered:"),"recovery replaces signout terminal marker")
	ui.account.api.cancel_all(); ui.account.busy = false; ui.account._refreshing = false
	ui._confirm_signout(); await frames()
	ui.account._completed("register",201,{"token":"nwd_old","player":{"screen_name":"Original"}},"")
	ok(ui.account.store.data.device_token.is_empty(),"late account callback cannot revive signedout identity")
	ui.controls.new_account.pressed.emit(); ok(ui.page == "onboarding" and not ui.account.store.data.signed_out,"explicit new account starts onboarding")
	ok(requests.back().requests.is_empty(),"choosing new account alone sends no registration")
	ui.queue_free(); await frames()
	print("NINEWEAVE_SIGNOUT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
