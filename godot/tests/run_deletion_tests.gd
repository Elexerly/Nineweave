extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Account = preload("res://net/device_account.gd")
const Store = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(): await process_frame; await process_frame
func click(control):
	await frames()
	var position = control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.position = position
		root.push_input(event,true)
	await frames()
func run():
	root.size = Vector2i(640,1100)
	var ui = Main.instantiate(); var prefix = "user://delete-test"
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	ui.account.store = Store.new(prefix+"-device.cfg"); ui.account.store.accept_consent("Original",Store.consent_payload())
	ui.account.store.keep_device("nwd_original","Original"); ui.account.store.keep_email("original@example.com"); ui.account.store.save()
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("cryon","Original")
	var requests = []; var account_http
	ui.account.api.request_factory = func(): var fake = Fake.new(); requests.append(fake); return fake
	ui.deletion.api.request_factory = func(): return Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(640,1100)); await frames()
	account_http = requests[0]
	account_http.respond(200,{"screen_name":"Original","email":"original@example.com","email_status":"verified","capabilities":{"email":true}})
	ui.show_settings(); ok(ui.controls.account_email.caption == "Account email","old backend has no deletion entry")
	ui.deletion.begin(); ui.deletion.proceed(); ui.deletion.phrase = "DELETE MY ACCOUNT"; ui.deletion.submit("nwd_original",false)
	var http = ui.deletion.api._request
	ok(http.requests.is_empty(),"capability gate enforced before HTTP")
	ui.deletion.cancel()
	# Synchronous web-storage seam: storage denial prevents any DELETE.
	ui.account.store.deletion_marker_io = func(_operation): return "error"
	ui.deletion.begin(); ui.deletion.proceed(); ui.deletion.phrase = "DELETE MY ACCOUNT"
	ui.deletion.submit("nwd_original",true)
	ok(http.requests.is_empty() and not ui.deletion.busy,"browser storage denial blocks destructive request")
	ui.account.store.deletion_marker_io = Callable(); ui.deletion.cancel()
	var seam = Store.new(prefix+"-marker.cfg")
	seam.data.device_token = "nwd_stale"; seam.data.screen_name = "Original"
	seam.deletion_marker_io = func(_operation): return "pending"
	seam.merge_deletion_marker(); ok(seam.data.deletion_uncertain,"browser pending marker overrides stale cfg false")
	seam.deletion_marker_io = func(_operation): return "deleted:nonce"
	seam.merge_deletion_marker(); ok(seam.deletion_reset_required and seam.data.device_token.is_empty() and seam.data.screen_name.is_empty(),"terminal deletion overrides stale credentials")
	seam.data.device_token = "nwd_old"; seam.data.deletion_resolution = "oldnonce"
	seam.deletion_marker_io = func(_operation): return "recovered:newnonce"
	seam.merge_deletion_marker(); ok(seam.data.deletion_uncertain,"stale cfg after recovery cannot auto-register")
	seam.data.deletion_resolution = "newnonce"; seam.merge_deletion_marker()
	ok(not seam.data.deletion_uncertain,"matching persisted resolution nonce permits legitimate recovered account")
	var failed_store = Store.new("/nonexistent-nineweave-directory/cannot-write.cfg")
	failed_store.deletion_reset_required = true
	failed_store.deletion_marker_io = func(_op): return "ok"
	ok(not failed_store.mark_deletion_resolved(true) and failed_store.deletion_reset_required and failed_store.data.deletion_uncertain,"failed terminal filesystem save keeps resolution blocked")
	# Failed save must not leave a matching in-memory nonce that unlocks writes.
	var failed_marker = [""]
	failed_store.deletion_marker_io = func(op):
		if op == "read": return failed_marker[0]
		failed_marker[0] = op.trim_prefix("write:"); return "ok"
	failed_store.data.deletion_resolution = "prior-persisted-nonce"
	ok(not failed_store.mark_deletion_resolved(false),"forced recovery-resolution save fails")
	failed_store.merge_deletion_marker()
	ok(failed_store.data.deletion_resolution == "prior-persisted-nonce" and failed_store.data.deletion_uncertain,"merge after failed save cannot match unsaved nonce")
	var failed_account = Account.new(); failed_account.store = failed_store
	var failed_http = Fake.new(); failed_account.api.request_factory = func(): return failed_http
	root.add_child(failed_account)
	failed_account.create_screen_name("MustNotRegister"); failed_account._submit_registration()
	ok(failed_http.requests.is_empty() and failed_account._deletion_blocked(),"full account stays blocked after failed save and marker merge")
	failed_account.queue_free(); await frames()
	var recorded = []
	seam.deletion_marker_io = func(operation): recorded.append(operation); return "ok"
	seam.mark_deletion_resolved(true)
	ok(recorded.back().begins_with("write:deleted:") and not seam.data.deletion_resolution.is_empty() and not seam.deletion_reset_required,"confirmed success retains terminal marker and releases runtime reset lock")
	ui.account._accept_email_player({"email":"original@example.com","email_status":"verified","capabilities":{"email":true,"account_deletion":true}})
	ui.show_settings(); await click(ui.controls.account_email); ok(ui.overlay == "account_options","Options account menu")
	await click(ui.controls.delete_account); ok(ui.deletion.stage == 1 and http.requests.is_empty(),"entry opens first warning only")
	await click(ui.controls.delete_cancel); ok(ui.overlay == "settings" and ui.account.store.data.device_token == "nwd_original","first cancel safe")
	ui.overlay = "delete_account"; ui.deletion.begin(); await click(ui.controls.delete_review)
	ok(ui.deletion.stage == 2 and http.requests.is_empty() and ui.controls.delete_final.disabled,"first confirmation sends nothing")
	await click(ui.controls.delete_cancel); ok(http.requests.is_empty() and ui.account.store.online_ready(),"second cancel safe")
	var error_count = 0
	for status in [409,401,409,503,0,200]:
		ui.overlay = "delete_account"; ui.deletion.begin(); ui.deletion.proceed(); ui.deletion.phrase = "DELETE MY ACCOUNT"; ui._deletion_action("submit")
		var request = http.requests.back()
		ok(request.url.ends_with("/api/nineweave/me") and request.method == HTTPClient.METHOD_DELETE and request.body == {"confirm":"DELETE MY ACCOUNT"},"own-account deletion contract")
		ok(request.headers == PackedStringArray(["Content-Type: application/json","Authorization: Bearer nwd_original"]),"uses existing own token only")
		http.respond(status,{} if status == 200 else {"error":"test"})
		ok(ui.account.store.data.deletion_uncertain == (error_count > 0),"only first definite rejection clears uncertainty")
		error_count += 1
		ok(ui.account.store.data.device_token == "nwd_original" and Store.new(prefix+"-device.cfg").data.device_token == "nwd_original","failure preserves persisted identity "+str(status))
		ok(not ui.deletion.busy and ui.deletion.phrase.is_empty() and not ui.deletion.message.is_empty(),"retry requires reconfirmation "+str(status))
		ok(requests.size() == 1 and account_http.requests.size() == 1,"errors never auto-register")
	# Simulate lost-success response followed by a real reconstructed startup refresh.
	ok(Store.new(prefix+"-device.cfg").data.deletion_uncertain,"uncertain deletion persists before restart")
	var restarted = Account.new(); restarted.store = Store.new(prefix+"-device.cfg")
	var restarted_http = Fake.new(); restarted.api.request_factory = func(): return restarted_http
	root.add_child(restarted); restarted.refresh()
	ok(restarted_http.requests.size() == 1 and restarted_http.requests[0].method == HTTPClient.METHOD_GET,"restart checks existing account without registration")
	restarted_http.respond(401,{"error":"deleted token"})
	restarted.sync_pending(); restarted.create_screen_name("Original"); restarted._submit_registration()
	ok(restarted_http.requests.size() == 1 and restarted.store.data.device_token == "nwd_original","lost deletion success then GET401 never recreates old account")
	ok(restarted.store.data.deletion_uncertain and not restarted.store.online_ready(),"unresolved account cannot authorize normal online actions")
	# A second tab loaded before deletion must re-read the synchronous marker.
	restarted.store.data.deletion_uncertain = false
	restarted.store.deletion_marker_io = func(_op): return "pending"
	restarted.refresh(); restarted_http.respond(401,{"error":"deleted in other tab"})
	ok(restarted_http.requests.size() == 2 and restarted.store.data.deletion_uncertain,"already-open tab re-reads deletion marker before 401 recovery")
	restarted.store.deletion_marker_io = func(_op): return "deleted:other-tab"
	restarted.create_screen_name("Original")
	ok(restarted_http.requests.size() == 2 and restarted.store.deletion_reset_required,"terminal marker in another tab blocks stale registration")
	restarted.queue_free(); await frames()
	var restarted_ui = Main.instantiate(); restarted_ui.account.store = Store.new(prefix+"-device.cfg")
	restarted_ui.settings = Settings.new(prefix+"-settings.cfg"); restarted_ui.profile = Profile.new(prefix+"-profile.cfg")
	var startup_http = Fake.new(); restarted_ui.account.api.request_factory = func(): return startup_http
	restarted_ui.online_api.request_factory = func(): return Fake.new()
	restarted_ui.http_request_factory = func(): return Fake.new()
	root.add_child(restarted_ui); restarted_ui.set_process(false); await frames()
	startup_http.respond(401,{"error":"deleted token"})
	ok(restarted_ui.overlay == "account_options" and restarted_ui.controls.has("resolve_deletion"),"full app restart shows unresolved deletion and recovery path")
	ok(startup_http.requests.size() == 1 and restarted_ui.account.store.data.deletion_uncertain,"full startup rejected token cannot auto-register")
	restarted_ui.queue_free(); await frames()
	ui.show_settings(); await click(ui.controls.account_email)
	ok(ui.controls.has("resolve_deletion"),"uncertain state offers explicit email recovery")
	await click(ui.controls.resolve_deletion)
	var recovery_http = ui.recovery.api._request
	ui.recovery.email = "original@example.com"; ui.recovery.request_code()
	recovery_http.respond(200,{"challenge_id":"ec_resolve"})
	ui.recovery.code = "123456"; ui.recovery.confirm()
	var restored = Store.consent_payload(); restored.screen_name = "Original"; restored.email = "original@example.com"; restored.email_status = "verified"; restored.capabilities = {"email":true,"account_deletion":true}
	recovery_http.respond(200,{"token":"nwd_original","player_id":"existing","player":restored})
	ok(not Store.new(prefix+"-device.cfg").data.deletion_uncertain and ui.account.store.online_ready(),"only explicit successful email recovery resolves uncertain existing identity")
	ui.overlay = "delete_account"; ui.deletion.begin(); ui.deletion.proceed()
	# Real input for final typed confirmation. Enter itself does not submit.
	ui.deletion.phrase = ""; ui._rebuild(); await frames()
	await click(ui.controls.delete_phrase)
	for ch in "DELETE MY ACCOUNT":
		var key = InputEventKey.new(); key.unicode = ch.unicode_at(0); key.keycode = ch.unicode_at(0); key.pressed = true; root.push_input(key)
		key = key.duplicate(); key.pressed = false; root.push_input(key)
	await frames()
	ok(ui.deletion.phrase == "DELETE MY ACCOUNT" and not ui.controls.delete_final.disabled,"real keyboard phrase enables final action")
	var before = http.requests.size()
	await click(ui.controls.delete_final)
	ok(http.requests.size() == before+1 and ui.deletion.busy,"final real click sends exactly one request")
	ok(Store.new(prefix+"-device.cfg").data.deletion_uncertain,"durable marker exists while delete request is in flight")
	ui._deletion_action("cancel"); ok(ui.deletion.busy and ui.overlay == "delete_account","submitted request cannot be falsely canceled")
	ui.settings.saved_game = {"name":"Original"}; ui.settings.save(); ui.tournament.session.wins = {"cryon":3}; ui.tournament.session.save()
	var old_account = ui.account; var old_social_http = ui.social.api._request
	http.respond(200,{"deleted":true,"retained_gameplay_label":"####"})
	ok(ui.page == "onboarding" and ui.account.store.data.device_token.is_empty() and ui.account.store.data.email.is_empty() and not ui.account.store.data.deletion_uncertain,"confirmed success clears identity and opens create name")
	ok(Store.new(prefix+"-device.cfg").data.screen_name.is_empty() and Settings.new(prefix+"-settings.cfg").saved_game.is_empty(),"persisted own name and saved game removed")
	ok(Profile.new(prefix+"-profile.cfg").data.display_name == "You" and ui.tournament.session.wins.is_empty(),"profile and local scores cleared")
	ok(ui.social.store == ui.account.store and ui.social._token().is_empty(),"new social client holds no old credential")
	account_http.respond(200,{"screen_name":"Ghost","capabilities":{"account_deletion":true}})
	old_social_http.respond(200,{"names":["Original"]})
	ok(ui.account.store.data.screen_name.is_empty() and ui.social.blocks.is_empty(),"late retired clients cannot restore deleted data")
	ok(old_account.is_blocking_signals() and requests.size() == 2 and requests[1].requests.is_empty(),"old account retired and no replacement registration")
	ui.account.create_screen_name("FreshChoice")
	ok(requests[1].requests.size() == 1 and requests[1].requests[0].url.ends_with("/auth/device"),"deliberate new-account action works after confirmed cleanup")
	requests[1].respond(201,{"token":"nwd_fresh","player":{"screen_name":"FreshChoice"}})
	requests[1].respond(200,{"screen_name":"FreshChoice"})
	ok(ui.account.store.data.screen_name == "FreshChoice" and not ui.account.store.deletion_reset_required,"intentional new identity is not blocked by stale runtime flag")
	# Narrow screens remain scrollable; confirmation controls fit within viewport width.
	for extent in [Vector2(320,568),Vector2(390,844)]:
		ui.set_view_size(extent); ui.account.store.accept_consent("Test",Store.consent_payload()); ui.account.store.keep_device("nwd_test","Test")
		ui.overlay = "delete_account"; ui.deletion.begin(); await frames()
		for stage in [1,2]:
			if stage == 2: ui.deletion.proceed(); await frames()
			var action_control = ui.controls.delete_review if stage == 1 else ui.controls.delete_final
			var box = action_control.get_parent()
			var scroll = box.get_parent()
			var scope_present = false; var limits_present = false
			for child in box.get_children():
				if not child is Label or child.text.is_empty(): continue
				scope_present = scope_present or "from the active game database" in child.text
				limits_present = limits_present or "does not erase hosting/email-provider records, backups or copies held by others" in child.text
				scroll.ensure_control_visible(child); await frames()
				var visible_rect = scroll.get_global_rect().grow(1)
				ok(visible_rect.encloses(child.get_global_rect()),"explanatory label readable by scrolling stage %d width %d" % [stage,extent.x])
				ok(child.size.y >= child.get_minimum_size().y,"explanation not vertically clipped")
			ok(scope_present and limits_present,"both confirmations include database scope and provider/backups limits")
			scroll.ensure_control_visible(action_control); await frames()
			ok(scroll.get_global_rect().grow(1).encloses(action_control.get_global_rect()),"confirmation reachable after explanation")
		ok(ui.controls.delete_phrase.size.x <= extent.x-32 and ui.controls.delete_final.size.x <= extent.x-32,"confirmation fits width "+str(extent.x))
	ui.queue_free(); await frames()
	var terminal_ui = Main.instantiate(); terminal_ui.account.store = Store.new(prefix+"-device.cfg")
	var terminal_marker = ["deleted:unflushed-terminal"]
	terminal_ui.account.store.deletion_marker_io = func(op):
		if op == "read": return terminal_marker[0]
		terminal_marker[0] = op.trim_prefix("write:"); return "ok"
	terminal_ui.settings = Settings.new(prefix+"-settings.cfg"); terminal_ui.settings.values.sound = false
	terminal_ui.profile = Profile.new(prefix+"-profile.cfg")
	var terminal_requests = []
	terminal_ui.account.api.request_factory = func(): var f = Fake.new(); terminal_requests.append(f); return f
	terminal_ui.deletion.api.request_factory = func(): return Fake.new()
	terminal_ui.online_api.request_factory = func(): return Fake.new()
	terminal_ui.http_request_factory = func(): return Fake.new()
	root.add_child(terminal_ui); terminal_ui.set_process(false); await frames()
	ok(terminal_ui.page == "onboarding" and terminal_ui.account.store.data.device_token.is_empty(),"stale terminal marker on full startup clears old identity")
	ok(not terminal_ui.account.store.deletion_reset_required,"startup cleanup releases runtime reset flag")
	terminal_ui.account.create_screen_name("AfterReload")
	ok(terminal_requests.back().requests.size() == 1 and terminal_requests.back().requests[0].body == {"screen_name":"AfterReload"},"explicit registration allowed after stale-terminal startup cleanup")
	var t_http = terminal_requests.back()
	t_http.respond(201,{"token":"nwd_afterreload","player":{"screen_name":"AfterReload"}})
	t_http.respond(200,{"screen_name":"AfterReload","capabilities":{"account_deletion":true}})
	terminal_ui.account.store.set_deletion_uncertain(true)
	terminal_ui.show_settings(); await click(terminal_ui.controls.account_email)
	ok(terminal_ui.controls.has("start_fresh") and terminal_ui.controls.has("resolve_deletion"),"unresolved account offers both sign-in and deliberate start fresh")
	var reset_http = terminal_ui.deletion.api._request; var old_request_count = t_http.requests.size()
	await click(terminal_ui.controls.start_fresh); await click(terminal_ui.controls.delete_cancel)
	ok(terminal_ui.account.store.data.device_token == "nwd_afterreload" and terminal_ui.account.store.data.deletion_uncertain,"cancel local reset preserves credential and uncertainty")
	await click(terminal_ui.controls.start_fresh); await click(terminal_ui.controls.delete_review)
	ok(terminal_ui.controls.delete_final.disabled and reset_http.requests.is_empty(),"local reset second step waits for typed confirmation")
	await click(terminal_ui.controls.delete_phrase)
	for ch in "CLEAR THIS DEVICE":
		var key = InputEventKey.new(); key.unicode = ch.unicode_at(0); key.keycode = ch.unicode_at(0); key.pressed = true; root.push_input(key)
		key = key.duplicate(); key.pressed = false; root.push_input(key)
	await frames(); await click(terminal_ui.controls.delete_final)
	ok(terminal_ui.page == "onboarding" and terminal_ui.account.store.data.device_token.is_empty(),"explicit local reset opens blank onboarding")
	ok("remains unconfirmed" in terminal_ui.message and not "was deleted" in terminal_ui.message,"local reset never claims server deletion")
	ok(terminal_marker[0].begins_with("cleared:") and Store.new(prefix+"-device.cfg").data.device_token.is_empty(),"local reset writes distinct durable terminal marker and clears saved token")
	ok(terminal_requests.back().requests.is_empty(),"start fresh itself never registers an account")
	terminal_ui.queue_free(); await frames()
	print("NINEWEAVE_DELETION ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
