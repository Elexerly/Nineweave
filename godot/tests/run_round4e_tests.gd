extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const Rules = preload("res://kernel/rules.gd")
const Layout = preload("res://ui/layout.gd")
const Tutorial = preload("res://ui/tutorial.gd")
const Roster = preload("res://characters/roster.gd")
var checks: int = 0
var failures: int = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func path_for(id: String, kind: String) -> String: return "user://r4e-"+id+"-"+kind+".cfg"
func make_ui(id: String, registered: bool = true, fresh: bool = true, startup_reply: bool = true):
	if fresh:
		for kind in ["device","settings","profile"]:
			var path = path_for(id,kind)
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var ui = Main.instantiate()
	ui.account.store = DeviceStore.new(path_for(id,"device"))
	ui.settings = Settings.new(path_for(id,"settings")); ui.settings.values.sound = false
	ui.profile = Profile.new(path_for(id,"profile")); ui.profile.data.character_id = "cryon"
	ui.rival_character = "aurelia"
	if registered and fresh:
		ui.account.store.keep_device("nwd_fixture","Weaver")
		ui.account.store.accept_consent("Weaver",DeviceStore.consent_payload())
		ui.account.store.skip_email()
	var fake = Fake.new(); ui.account.api.request_factory = func(): return fake
	var lobby = Fake.new(); ui.online_api.request_factory = func(): return lobby
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844))
	if fake.active and startup_reply: fake.respond(200,{"screen_name":"Weaver"})
	return {"ui":ui,"http":fake,"lobby":lobby}
func run():
	await tutorial_first_play()
	await tutorial_skip_and_replay()
	await tutorial_online_updates()
	await tutorial_input()
	await email_creation_paths()
	await offline_first_play()
	await email_editing_and_restart()
	email_validation()
	await responsive_forms()
	ok(Roster.get_hero("madame_solstice").name == "Beth Solstice","Beth Solstice display name preserved")
	print("NINEWEAVE_ROUND4E ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func tutorial_first_play():
	var bundle = make_ui("first"); var ui = bundle.ui
	ok(not ui.settings.values.tutorial_completed and not ui.tutorial.active,"fresh startup waits for a match")
	ui.start_game("computer",2,true,true)
	ok(ui.cinematic.active and not ui.tutorial.active,"hero intro is intact and runs before tutorial")
	ui.cinematic.advance(.81); ui.cinematic.skip()
	ok(ui.tutorial.active and ui.overlay == "tutorial" and ui.board.frozen,"first match automatically opens locked guided demo")
	ok(ui.board.game == ui.tutorial.demo and ui.board.game != ui.game,"same board renderer uses isolated demo rules")
	ok(not ui.thinking and ui.game.history.is_empty(),"opponent-first AI waits for tutorial")
	var original = ui.game.serialize(); var geometry = ui.board.get_rect(); var seconds = ui.match_seconds
	ok(not ui.play_cell(0,0),"tutorial blocks actual moves")
	ui._process(1)
	ok(ui.match_seconds == seconds and ui.game.serialize() == original,"tutorial pauses real match clock and AI")
	ui.tutorial.set_process(false); ui.tutorial.age = 0
	ok(ui.tutorial.arrow_progress() == 0,"arrow starts undrawn")
	ui.tutorial.age = .4; ok(ui.tutorial.arrow_progress() > 0 and ui.tutorial.arrow_progress() < 1,"arrow sweeps toward destination")
	ui.tutorial.reduced_motion = true
	ok(ui.tutorial.arrow_progress() == 1,"reduced motion shows a static completed arrow")
	ui.tutorial.reduced_motion = false
	for index in range(6):
		ok(ui.tutorial.step == index and ui.tutorial.caption.text == Tutorial.STEPS[index],"short sentence for step "+str(index))
		ok(ui.tutorial.controls.skip.visible and ui.tutorial.controls.skip.size.y >= 44,"Skip always visible and touch sized")
		ok(ui.board.get_rect() == geometry,"tutorial keeps locked board geometry")
		match index:
			0: ok(ui.tutorial.demo.cells[5] == 1 and ui.tutorial.demo.active_board == -1,"first ghost points to open square")
			1: ok(ui.tutorial.demo.active_board == 5,"cell five opens matching board five")
			2: ok(ui.tutorial.demo.cells[5*9+7] == 2 and ui.tutorial.demo.active_board == 7,"opponent ghost routes to board seven")
			3: ok(ui.tutorial.demo.owners[0] == 1 and ui.tutorial.demo.small_lines[0] == [[0,1,2]],"real kernel claims three cells")
			4: ok(ui.tutorial.demo.status == 1 and ui.tutorial.demo.big_lines == [[0,1,2]],"real kernel wins three big boards")
			5: ok(ui.tutorial.demo.active_board == -1 and ui.tutorial.demo.owners[0] == 1 and ui.tutorial.demo.legal_moves().size() > 9,"sent to won board grants open-board choice")
		ui.tutorial.controls.next.pressed.emit()
	ok(not ui.tutorial.active and ui.board.game == ui.game and not ui.board.frozen,"completion restores real board")
	ok(ui.game.serialize() == original and ui.thinking,"untouched opponent-first match resumes AI")
	ok(Settings.new(ui.settings.path).values.tutorial_completed,"completion persists to user config")
	ui.thinking = false; ui.start_game("local")
	ok(not ui.tutorial.active,"second match never auto-replays completed demo")
	ui.free(); await frames()
	bundle = make_ui("first",true,false); ui = bundle.ui; ui.start_game("local")
	ok(not ui.tutorial.active,"completed flag survives a new controller/session")
	ui.free(); await frames()
func tutorial_skip_and_replay():
	var bundle = make_ui("skip"); var ui = bundle.ui
	ui.start_game("local"); ui.tutorial.controls.skip.pressed.emit()
	ok(Settings.new(ui.settings.path).values.tutorial_completed,"skip persists immediately")
	ui.free(); await frames()
	bundle = make_ui("skip",true,false); ui = bundle.ui; ui.start_game("local")
	ok(not ui.tutorial.active and ui.play_cell(0,4),"skipped flag survives restart and match is playable")
	ui.play_cell(4,0); var state = ui.game.serialize(); ui.match_seconds = 23
	ui.show_settings(); ui.controls.replay_tutorial.pressed.emit()
	ok(ui.tutorial.active and ui.tutorial.replay and ui.tutorial.step == 0,"Settings How to play replays after skip")
	ui.set_view_size(Vector2(1366,1024))
	ok(ui.tutorial.active and ui.tutorial.step == 0 and ui.board.get_rect().is_equal_approx(ui.layout.board),"rotation preserves tutorial on exact board rect: %s vs %s, step %s" % [ui.board.get_rect(),ui.layout.board,ui.tutorial.step])
	ui.tutorial.skip()
	ok(ui.overlay == "settings" and ui.game.serialize() == state and ui.match_seconds == 23,"replay returns to settings preserving live match")
	ui._close_overlay(); ui.go_home(); ui.controls.how.pressed.emit()
	ok(ui.tutorial.active and ui.board.visible and not ui.title_label.visible,"main menu replay shows real board")
	for i in range(6): ui.tutorial.next_step()
	ok(ui.page == "title" and ui.overlay.is_empty() and not ui.board.visible,"menu replay completes back to menu")
	ui.free(); await frames()
func tutorial_online_updates():
	var bundle = make_ui("online"); var ui = bundle.ui
	ui._reset_online_match(); ui.cinematic.advance(.81); ui.cinematic.skip()
	ok(ui.tutorial.active,"first online match offers tutorial")
	var demo_cells = ui.tutorial.demo.cells.duplicate()
	ui._receive_move(0,4,1)
	ok(ui.game.cells[4] == 1 and ui.online_sequence == 1 and ui.tutorial.demo.cells == demo_cells,"incoming online move updates real state without touching demo")
	var remote = Rules.new(); remote.play(0,4); remote.play(4,0)
	ui._receive_state(remote.serialize(),2)
	ok(ui.game.cells == remote.cells and ui.tutorial.active and ui.board.frozen,"online resync stays behind locked tutorial")
	ui.tutorial.skip()
	ok(ui.board.game == ui.game and ui.game.cells == remote.cells,"latest authoritative match restored after tutorial")
	ui.start_tutorial(true)
	ui._online_room_update({"status":"closed","result":{"winner":2}})
	ok(ui.game.status == 2 and ui.tutorial.active and ui.board.win_fx.is_empty(),"official online forfeit remains authoritative during replay")
	ui.tutorial.skip()
	ok(ui.board.win_fx.player == 2,"online result presentation resumes after tutorial")
	ui.free(); await frames()
func tutorial_input():
	var bundle = make_ui("input"); var ui = bundle.ui; ui.start_game("local")
	var touch = InputEventScreenTouch.new(); touch.pressed = true
	ui.tutorial._gui_input(touch); ok(ui.tutorial.step == 0,"touch press alone cannot double advance")
	touch.pressed = false; ui.tutorial._gui_input(touch)
	var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = false; mouse.device = -1
	ui.tutorial._gui_input(mouse)
	ok(ui.tutorial.step == 1,"touch plus emulated mouse advances exactly once")
	var escape = InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	ui.tutorial._unhandled_key_input(escape)
	ok(not ui.tutorial.active and ui.settings.values.tutorial_completed,"Escape is a persistent skip")
	ui.free(); await frames()
func create_name(bundle, name: String):
	var ui = bundle.ui
	ui.controls.screen_name.text_changed.emit(name); ui.controls.create_name.pressed.emit()
	bundle.http.respond(201,{"token":"nwd_new","player":{"screen_name":name}})
	bundle.http.respond(200,{"screen_name":name})
func email_creation_paths():
	for add_email in [false,true]:
		var id = "email-save" if add_email else "email-skip"
		var bundle = make_ui(id,false); var ui = bundle.ui
		ok(ui.page == "onboarding" and ui.online_view.agreement.get_parsed_text().contains("13 or older"),"original screen-name consent remains first")
		create_name(bundle,"Weaver")
		ok(ui.page == "email" and ui.account.store.complete() and ui.controls.has_all(["email","save_email","continue_email"]),"name creation leads to optional email")
		ok(ui.controls.verification_status.text == "Not verified","honest unverified status")
		var requests = bundle.http.requests.size()
		if add_email:
			ui.controls.email.text = "not-an-email"; ui.controls.save_email.pressed.emit()
			ok(ui.page == "email" and "valid email" in ui.email_view.status and ui.account.store.data.email.is_empty(),"invalid email stays on form with readable error")
			ui.controls.email.text = " Weaver+backup@example.com "
			ui.controls.save_email.pressed.emit()
		else: ui.controls.continue_email.pressed.emit()
		ok(ui.page == "title" and ui.controls.has_all(["computer","local"]),"both optional paths reach playable menu")
		var saved = DeviceStore.new(ui.account.store.path)
		ok(saved.data.email == ("Weaver+backup@example.com" if add_email else "") and saved.data.email_prompt_done,"optional decision persists locally")
		ok(saved.data.email_status == "not_verified","local email never claims verified ownership")
		ok(bundle.http.requests.size() == requests and bundle.lobby.requests.is_empty(),"saving or skipping email sends no server requests")
		for request in bundle.http.requests: ok(not request.body.has("email"),"legacy account request never contains email")
		ui.free(); await frames()
		bundle = make_ui(id,true,false); ui = bundle.ui
		ok(ui.page == "title","email choice is not prompted again after restart")
		ui.free(); await frames()
	var bundle = make_ui("email-online",false); var ui = bundle.ui
	ok(not ui.controls.has("offline"),"first run has no offline/main-menu skip")
	ui.request_online(); ok(ui.page == "onboarding","online request remains behind mandatory name")
	create_name(bundle,"Weaver")
	ok(ui.page == "email" and bundle.lobby.requests.is_empty(),"online destination waits for optional step")
	ui.controls.continue_email.pressed.emit()
	ok(ui.page == "online" and bundle.lobby.requests.size() == 1,"continue without email preserves online destination")
	ui.free(); await frames()
func offline_first_play():
	var bundle = make_ui("offline-first",false); var ui = bundle.ui
	ui.controls.screen_name.text_changed.emit("Offline Weaver"); ui.controls.create_name.pressed.emit()
	bundle.http.respond(0,{},HTTPRequest.RESULT_TIMEOUT)
	var consent_time = ui.account.store.data.accepted_at
	ok(ui.page == "email" and ui.account.store.complete() and ui.account.store.data.pending_sync,"timeout creates local name and shows optional email")
	ok(ui.account.store.data.device_token.is_empty() and ui.account.store.data.age_confirmed,"offline completion saves consent without a token")
	ui.free(); await frames()
	# A restart during optional email attempts sync but never blocks that step.
	bundle = make_ui("offline-first",false,false,false); ui = bundle.ui
	ok(ui.page == "email" and bundle.http.active and bundle.http.requests[0].url.ends_with("/auth/device"),"next launch syncs in background and resumes optional email")
	bundle.http.respond(503,{"error":"Service unavailable"})
	ok(ui.page == "email" and ui.account.store.complete() and not ui.account.busy,"repeated outage leaves optional email usable")
	ui.controls.email.text = "offline@example.com"; ui.controls.save_email.pressed.emit()
	ok(ui.page == "title" and ui.account.store.data.email == "offline@example.com","optional email still saves locally during outage")
	ui.start_game("computer",1,false,true)
	ok(ui.cinematic.active and not ui.tutorial.active,"offline local account keeps hero intro")
	ui.cinematic.advance(.81); ui.cinematic.skip()
	ok(ui.tutorial.active and ui.overlay == "tutorial","offline local account keeps first-play tutorial")
	ui.tutorial.skip(); ui.go_home(); ui.open_online()
	ok(ui.page == "online" and bundle.lobby.requests.is_empty() and bundle.http.active,"Online retries pending registration without unauthenticated lobby requests")
	ui.create_online(); ui.join_online("N9ABC")
	ok(ui.transport == null and bundle.lobby.requests.is_empty(),"pending registration cannot create or join live matches")
	bundle.http.respond(0,{},HTTPRequest.RESULT_CANT_CONNECT)
	ok(ui.page == "online" and "saved on this device" in ui.online_view.status and ui.account.store.data.pending_sync,"failed sync keeps local name with honest online status")
	ui.go_home(); ui.resume_game()
	ok(ui.page == "game" and not ui.tutorial.active,"local match remains resumable after failed online sync")
	ui.go_home(); ui.free(); await frames()
	bundle = make_ui("offline-first",false,false,false); ui = bundle.ui
	ok(ui.page == "title" and ui.account.store.data.email_prompt_done and ui.settings.values.tutorial_completed,"restart preserves offline name, email decision and tutorial completion")
	bundle.http.respond(201,{"token":"nwd_offline_synced","player":{"screen_name":"Offline Weaver"}})
	ok(bundle.http.requests.back().body.accepted_at == consent_time,"later sync preserves original consent timestamp")
	bundle.http.respond(200,{"screen_name":"Offline Weaver"})
	ok(ui.page == "title" and ui.account.store.online_ready() and not DeviceStore.new(ui.account.store.path).data.pending_sync,"successful launch sync preserves menu and clears persisted pending flag")
	ui.open_online()
	ok(bundle.lobby.requests.size() == 1 and bundle.lobby.requests[0].headers.has("Authorization: Bearer nwd_offline_synced"),"live lobby uses actual server-issued token after sync")
	ui.free(); await frames()
	# If a locally chosen name is taken when service returns, resolve it on the
	# mandatory form; retries and restarts must never silently accept a 409.
	bundle = make_ui("offline-conflict",false); ui = bundle.ui
	ui.controls.screen_name.text_changed.emit("Taken"); ui.controls.create_name.pressed.emit()
	bundle.http.respond(503,{"error":"Unavailable"}); ui.controls.continue_email.pressed.emit(); ui.open_online()
	bundle.http.respond(409,{"error":"Name taken"})
	ok(ui.page == "onboarding" and "Name taken" in ui.online_view.status and not ui.account.store.complete(),"sync 409 returns to name form for retry")
	ui.go_home(); ui.request_game("local"); ui.resume_game()
	ok(ui.page == "onboarding","sync conflict cannot escape via navigation")
	ui.free(); await frames()
	bundle = make_ui("offline-conflict",false,false,false); ui = bundle.ui
	ok(ui.page == "onboarding" and bundle.http.requests.is_empty(),"unresolved conflict remains on name screen after restart")
	create_name(bundle,"Available")
	ok(ui.page == "email" and ui.account.store.online_ready(),"replacement name can complete normally after conflict")
	ui.free(); await frames()
func email_editing_and_restart():
	var bundle = make_ui("edit"); var ui = bundle.ui
	ui.show_settings(); ui.controls.account_email.pressed.emit()
	ok(ui.overlay == "account" and not ui.email_view.onboarding,"Settings exposes later account email editor")
	var requests = bundle.http.requests.size()
	ui.controls.email.text = "first@example.com"; ui.controls.save_email.pressed.emit()
	ok(ui.overlay == "settings" and ui.account.store.data.email == "first@example.com","later add saves and returns to settings")
	ui.controls.account_email.pressed.emit(); ok(ui.controls.email.text == "first@example.com","later edit prefills saved email")
	ui.controls.email.text_changed.emit("second@example.org"); ui.set_view_size(Vector2(867,553))
	ok(ui.controls.email.text == "second@example.org","unsaved draft survives rotation")
	ui.controls.email.text_submitted.emit("second@example.org")
	ok(ui.account.store.data.email == "second@example.org" and ui.overlay == "settings","Enter saves changed email")
	ui.controls.account_email.pressed.emit(); ui.controls.email.text = "bad"; ui.controls.save_email.pressed.emit()
	ok(ui.account.store.data.email == "second@example.org" and "valid email" in ui.email_view.status,"invalid replacement preserves prior saved email")
	ui.controls.continue_email.pressed.emit()
	ok(ui.overlay == "settings" and bundle.http.requests.size() == requests,"return discards draft without network")
	ui.free(); await frames()
	bundle = make_ui("edit",true,false); ui = bundle.ui; ui.open_account_email()
	ok(ui.controls.email.text == "second@example.org" and ui.controls.verification_status.text == "Not verified","email and status survive controller restart")
	ui.free(); await frames()
	# A quit between name creation and the optional decision resumes at that step.
	bundle = make_ui("interrupted",false); ui = bundle.ui; create_name(bundle,"Weaver"); ui.free(); await frames()
	bundle = make_ui("interrupted",true,false); ui = bundle.ui
	ok(ui.page == "email","unfinished optional step resumes after restart")
	ui.free(); await frames()
func email_validation():
	for value in ["a@b.co","name+backup@example.com"," first.last@sub.example.org ","o'neil@example.com"]:
		ok(DeviceStore.valid_email(value),"accept basic email "+value)
	for value in ["","a","@example.com","a@","a@localhost","a@@b.co","a b@example.com","a@example..com","a@-example.com","a@example-.com","a@example.com\ncc:other@example.com",".a@example.com","a..b@example.com","a.@example.com","a".repeat(65)+"@example.com","a@"+"b".repeat(250)+".com"]:
		ok(not DeviceStore.valid_email(value),"reject invalid email "+value.left(30))
	var legacy_path = path_for("legacy","device"); var cfg = ConfigFile.new()
	cfg.set_value("device","screen_name","Legacy"); cfg.save(legacy_path)
	var legacy = DeviceStore.new(legacy_path)
	ok(legacy.data.email.is_empty() and not legacy.data.email_prompt_done,"legacy account defaults migrate without inventing email")
	cfg.set_value("device","email",42); cfg.set_value("device","email_status","verified"); cfg.set_value("device","email_prompt_done","yes"); cfg.save(legacy_path)
	legacy = DeviceStore.new(legacy_path)
	ok(legacy.data.email.is_empty() and legacy.data.email_status == "not_verified" and not legacy.data.email_prompt_done,"bad types and local verified claims cannot authenticate email")
func responsive_forms():
	var bundle = make_ui("layout"); var ui = bundle.ui
	for view_size in [Vector2(360,640),Vector2(390,620),Vector2(390,844),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(view_size); ui.go_home(); ui.start_tutorial(true); await frames()
		var viewport = Rect2(Vector2.ZERO,ui.layout.size)
		for control in [ui.tutorial.controls.skip,ui.tutorial.controls.next,ui.tutorial.caption,ui.tutorial.counter]:
			ok(viewport.encloses(control.get_rect()),"tutorial content fits "+str(view_size))
			ok(not control.get_rect().intersects(ui.layout.board),"tutorial copy/buttons never cover board "+str(view_size))
		ok(ui.tutorial.caption.get_line_count()*ui.tutorial.caption.get_line_height() <= ui.tutorial.caption.size.y,"tutorial first sentence fits at readable size")
		for i in range(6):
			await frames(1)
			ok(ui.tutorial.caption.get_line_count()*ui.tutorial.caption.get_line_height() <= ui.tutorial.caption.size.y,"each guided sentence fits "+str(view_size)+" "+str(i))
			ui.tutorial.next_step()
		ui.show_settings(); await frames()
		for id in ["account_email","replay_tutorial","done","cosmetics","player_name","save_name"]:
			var rect = ui.controls[id].get_global_rect()
			ok(viewport.encloses(rect) and rect.size.x >= 44 and rect.size.y >= 44,"Settings touch bounds "+id+str(view_size))
		for id in ["account_email","replay_tutorial"]:
			for other in ["player_name","save_name","done","cosmetics","toggle_show_hints","difficulty"]:
				ok(not ui.controls[id].get_global_rect().intersects(ui.controls[other].get_global_rect()),"Settings links do not overlap "+id+" "+other+str(view_size))
		ui.controls.account_email.pressed.emit(); await frames()
		for id in ["email","save_email","continue_email"]:
			ok(ui.controls[id].size.x >= 44 and ui.controls[id].size.y >= 44,"email touch size "+id+str(view_size))
		# Short landscape scrolls; portrait/desktop exposes the complete form at once.
		if view_size.y >= 620:
			for id in ["email","save_email","continue_email","verification_status"]:
				ok(viewport.encloses(ui.controls[id].get_global_rect()),"email visible bounds "+id+str(view_size))
		ui.controls.continue_email.pressed.emit(); ui._close_overlay()
	ui.free(); await frames()
