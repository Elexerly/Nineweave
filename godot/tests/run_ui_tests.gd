extends SceneTree
const Main = preload("res://main/main.tscn")
const F = preload("res://tests/fixtures.gd")
const Rules = preload("res://kernel/rules.gd")
const Loopback = preload("res://net/loopback_transport.gd")
const Http = preload("res://net/http_polling_transport.gd")
const Store = preload("res://settings/store.gd")
var checks = 0
var failures = 0
var received_a: Array = []
var received_b: Array = []
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func frames(count: int = 3):
	for i in range(count): await process_frame
func run():
	var ui = Main.instantiate(); ui.settings = Store.new("user://ui-test.cfg"); ui.settings.values.sound = false; ui.settings.values.reduced_motion = false
	ui.profile.data.onboarded = true
	root.add_child(ui); await frames()
	ui.set_view_size(Vector2(390,844)); await frames()
	ok(ui.page == "title" and ui.controls.has_all(["computer","online","local","settings","how"]),"title choices")
	ui.controls.computer.pressed.emit(); await frames()
	ok(ui.overlay == "setup" and ui.controls.has("choose_o"),"difficulty and seat chooser")
	ui.controls.choose_x.pressed.emit(); ui.thinking = false; await frames()
	ok(ui.mode == "computer" and ui.human_mark == 1 and ui.turn_label == "Turn: X","X first")
	ui.start_game("local")
	# Simulated pointer input travels through the board's real hit-test API.
	var tap = InputEventMouseButton.new(); tap.button_index = MOUSE_BUTTON_LEFT; tap.pressed = true; tap.position = ui.board.cell_center(0,4)
	ui.board._gui_input(tap)
	ok(ui.game.cells[4] == 1 and ui.turn_label == "Turn: O" and ui.active_label == "Active Board: Center","pointer move updates labels")
	ok(not ui.play_cell(0,0) and ui.board.invalid_board == 0,"invalid board feedback")
	ok(ui.play_cell(4,0),"reply legal")
	ok(ui.undo_move() and ui.game.history.size() == 1 and ui.active_label == "Active Board: Center","undo updates labels")
	ui.request_hint()
	for i in range(200):
		ui.hint_ai.step(5000)
		if ui.hint_ai.done: break
	ui._process(.01)
	ok(ui.game.is_legal(ui.board.hint_move.x,ui.board.hint_move.y),"hint legal and displayed")
	ui.debug_load_position(F.position(["XX.OO....",".........",".........",".........",".........",".........",".........",".........","........."],1,0).serialize())
	ui._debug_capture = false
	ok(ui.play_cell(0,2) and ui.board.claims.size() == 1,"claim animation starts")
	ui.board.advance(2)
	ok(ui.board.claims.is_empty() and ui.game.owners[0] == 1,"claim animation finishes with persistent ownership")
	ui.debug_load_position(F.big_tactic(1).serialize()); ui._debug_capture = false
	ok(ui.play_cell(2,2) and not ui.board.win_fx.is_empty(),"win animation starts")
	ok(ui.display_player() == 1,"winning player keeps the crown through victory")
	ui.board.advance(4); ui._process(.01); ui.cinematic.age = .25; ui.cinematic.skip(); await frames()
	ok(ui.game.winner() == 1 and ui.overlay == "result" and ui.controls.has("again"),"win finishes in victory panel")
	ok(ui._result_t >= .99 and ui.controls.again.visible and ui.controls.again.modulate.a > .95,"win panel fully visible at end of win animation")
	ok(ui.info_lines()[0] == "Victory! X wins the game" and ui.active_label == "Victory! X wins the game","info pill shows the result after game over")
	ok(not "Active Board" in ui.info_lines()[0] and not "Play your" in ui.info_lines()[1],"info pill no longer prompts a move after game over")
	var states = ui.minimap_states()
	var tint_ok = not states.has("active")
	for b in range(9):
		var want = {1:"x",2:"o",3:"sealed"}.get(ui.game.owners[b],"open")
		tint_ok = tint_ok and states[b] == want
	ok(tint_ok,"mini-map only tints owned boards after a win, no active board "+str(states))
	ok(ui.mode == "computer" and ui._rival_name() == "Rival AI" and ui.side_name(2) == "Rival AI" and ui.is_rival_ai_shown(),"vs-computer shows Rival AI")
	var digest = ui.game.compact()
	ui.debug_preview_claim(4,2,.4); ui.debug_preview_win([0,4,8],1,.5)
	ok(ui.game.compact() == digest,"preview effects cannot alter rules")
	# Posed scenarios use real positions: drawn lines match genuine marks/owners.
	ui.debug_scenario("claim",.45)
	var claimed = ui.board.claims[0].board if not ui.board.claims.is_empty() else -1
	ok(claimed >= 0 and ui.game.owners[claimed] == 1 and not ui.game.small_lines[claimed].is_empty(),"claim scenario poses a genuine claimed board")
	var line_ok = claimed >= 0
	if line_ok:
		for c in ui.game.small_lines[claimed][0]: line_ok = line_ok and ui.game.cells[claimed*9+c] == 1
	ok(line_ok,"claim beam passes through three real X marks")
	ok(ui.mode == "computer" and ui._rival_name() == "Rival AI","capture scenarios use vs-computer with Rival AI")
	var live = 0
	if claimed >= 0:
		for i in range(ui.board.CLAIM_PARTICLES):
			if ui.board._particle(ui.board.claims[0],i,ui.board.tile_rect(claimed),.45).alpha > 0: live += 1
	ok(live >= 60,"posed claim at 0.45 shows %d deterministic particles" % live)
	ok(ui.board.scale.x > 1.0 or ui.board.reduced_motion,"posed claim applies the camera punch-in")
	ok(ui.board.screen_flash().a > .02,"posed claim at 0.45 still shows the screen tint flash")
	ui.debug_scenario("win",.45)
	var big: Array = ui.board.win_fx.line
	ok(big.size() == 3 and ui.game.status == 1 and ui.game.owners[big[0]] == 1 and ui.game.owners[big[1]] == 1 and ui.game.owners[big[2]] == 1,"win beam passes through three boards owned by the winner")
	ok(ui.overlay == "","win panel hidden early in the win animation")
	ok(ui.board.screen_flash().a > .01,"posed win at 0.45 keeps a colour wash")
	ui.debug_scenario("win",.95)
	ok(ui.overlay == "result" and ui.controls.has("again") and ui.controls.again.modulate.a > .95,"debug_preview_win at 0.95 shows the victory panel")
	ui.debug_preview_win(big,1,.95)
	ok(ui.overlay == "result" and ui._result_t >= .99,"debug_preview_win(line,player,0.95) keeps the panel visible")
	ui.debug_scenario("win_end")
	ok(ui.overlay == "result" and ui._victory_title() == "VICTORY","win_end scenario shows VICTORY panel")
	ui.debug_scenario("claim_end")
	ok(ui.board.claims.size() == 1 and is_equal_approx(ui.board.claim_phase(ui.board.claims[0]),1.0),"claim_end poses the settled emblem")
	ui.debug_scenario("thinking")
	ok(ui.thinking and ui.game.turn == 2 and ui._rival_name() == "Rival AI","thinking scenario shows the Rival AI thinking")
	ui.thinking = false; ui._debug_capture = false; ui.overlay = ""
	ui.show_settings(); await frames()
	ui.controls.toggle_reduced_motion.pressed.emit()
	ok(ui.settings.values.reduced_motion and ui.board.reduced_motion,"reduced motion setting applies")
	var loaded = Store.new("user://ui-test.cfg")
	ok(loaded.values.reduced_motion,"settings ConfigFile persistence")
	ui.settings.values.reduced_motion = false; ui._apply_preferences(); ui._close_overlay()
	ui.start_game("computer",2)
	ok(ui.thinking and ui.game.turn == 1,"AI opens when human chooses O")
	for i in range(220):
		ui._process(.02)
		if not ui.thinking: break
	ok(ui.game.history.size() == 1 and ui.game.turn == 2,"frame-sliced AI opening")
	ui._save_match(); var state = ui.game.compact(); ui.go_home(); ui.resume_game()
	ok(ui.game.compact() == state and ui.human_mark == 2,"save/resume computer game")
	ui.start_game("local")
	# Headless geometry and draw traversal at every target; no rendering claims.
	for s in [Vector2(390,844),Vector2(360,640),Vector2(844,390),Vector2(568,320),Vector2(867,553),Vector2(669,787),Vector2(1366,1024),Vector2(1280,720),Vector2(2601,1659)]:
		ui.set_view_size(s); await frames(2)
		var viewport = Rect2(Vector2.ZERO,ui.layout.size).grow(.5)
		ok(viewport.encloses(ui.board.get_rect()),"mounted board fits "+str(s))
		for id in ui.controls:
			var control = ui.controls[id]
			ok(viewport.encloses(control.get_rect()),"mounted control fits "+id+" "+str(s))
		ui.debug_scenario("midgame"); await frames(2)
		ok(ui.game.turn == 1 and ui.game.active_board == 4,"midgame scenario reference routing")
	# Every menu/modal has real 44px controls inside even the shortest phone.
	for s in [Vector2(360,640),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(669,787)]:
		ui.set_view_size(s); ui.go_home(); await frames(2)
		check_controls(ui,"title "+str(s))
		for panel in ["settings","how","setup","cosmetics"]:
			ui.overlay = panel; ui._rebuild(); await frames(2)
			check_controls(ui,panel+" "+str(s))
			ok(Rect2(Vector2.ZERO,ui.layout.size).encloses(ui._modal_rect),"modal fits "+panel+" "+str(s))
		ui.open_online(); await frames(2); check_controls(ui,"online lobby "+str(s))
		ui.create_online(true); await frames(2); check_controls(ui,"online waiting "+str(s))
		ui.go_home()
	ui.set_view_size(Vector2(867,553)); ui.debug_simulate_hinge(); await frames()
	ok(not ui.board.get_rect().intersects(ui.layout.hinge),"mounted hinge safe")
	ui.show_settings(); await frames(2)
	ok(not ui._modal_rect.intersects(ui.layout.hinge),"hinge safe settings panel")
	ui._close_overlay()
	ui.set_view_size(Vector2(669,787)); ui.debug_simulate_hinge(); await frames(2)
	ok(not ui.board.get_rect().intersects(ui.layout.hinge),"portrait hinge split")
	ui.show_settings(); await frames(2)
	ok(not ui._modal_rect.intersects(ui.layout.hinge),"portrait hinge safe settings")
	ui._close_overlay()
	ui.set_hinge_rect(Rect2())
	# Real authoritative two-client service, all moves flow through send/ack.
	Loopback.reset_service()
	var a = Loopback.new(); var b = Loopback.new(); root.add_child(a); root.add_child(b)
	var ga = Rules.new(); var gb = Rules.new()
	var events = {"created":"","joined":false,"opponent":false,"errors":0,"left":false}
	a.room_created.connect(func(code): events.created = code)
	b.joined.connect(func(_code,seat): events.joined = seat == 2)
	a.opponent_joined.connect(func(): events.opponent = true)
	a.error.connect(func(_msg): events.errors += 1)
	a.opponent_left.connect(func(): events.left = true)
	a.move_received.connect(func(board,cell,seq): received_a.append(seq); ga.play(board,cell))
	b.move_received.connect(func(board,cell,seq): received_b.append(seq); gb.play(board,cell))
	a.create_room(); b.join_room(a.code)
	ok(events.created.length() == 5 and events.joined and events.opponent,"loopback create/join")
	a.send_move(0,4,7)
	ok(events.errors == 1 and ga.history.is_empty(),"authority rejects stale sequence")
	var random = RandomNumberGenerator.new(); random.seed = 848
	while ga.status == 0:
		var moves = ga.legal_moves(); var m = moves[random.randi_range(0,moves.size()-1)]
		(a if ga.turn == 1 else b).send_move(m.x,m.y,ga.history.size()+1)
		ok(ga.compact() == gb.compact(),"two-way state sync")
	ok(ga.status != 0 and received_a == received_b,"online reaches terminal result")
	b.leave(); ok(events.left,"opponent left signal")
	a.queue_free(); b.queue_free(); await frames()
	# UI demo flow is explicitly local, with an AI standing in for a remote seat.
	ui.open_online()
	ui.controls.room_code.text = "NAB12"; ui.controls.room_code.text_changed.emit("NAB12"); ui._rebuild()
	ok(ui.controls.room_code.text == "NAB12","room code survives layout rebuild")
	var code_field = ui.controls.room_code; code_field.grab_focus(); await frames(1)
	ui._resize_pending = true; ui._process(.01)
	ok(is_instance_valid(code_field) and code_field.has_focus(),"virtual keyboard resize retains LineEdit focus")
	code_field.release_focus(); ui._resize_pending = false
	ui.create_online(true); await frames()
	ok(ui.online_state == "waiting" and ui.room_code.length() == 5,"room code screen")
	ui.invite_demo_rival(); await frames()
	ok(ui.page == "game" and ui.mode == "online" and ui.remote_ready,"demo enters same game screen")
	ui._debug_capture = false; ui.play_cell(0,4)
	for i in range(220):
		ui._process(.02)
		if ui.game.history.size() >= 2: break
	ok(ui.game.history.size() == 2 and ui.online_sequence == 2,"demo simulated remote reply")
	ok(not ui.undo_move(),"online undo disabled")
	ui.go_home(); await frames()
	var http = Http.new(); root.add_child(http); var errors: Array = []
	http.error.connect(func(msg): errors.append(msg)); http.create_room()
	ok(errors.size() == 1 and "Online server not available yet" in errors[0],"offline HTTP graceful failure without network")
	http.queue_free(); ui.queue_free(); await frames(4)
	Loopback.reset_service()
	print("NINEWEAVE_UI ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func check_controls(ui, context: String):
	var viewport = Rect2(Vector2.ZERO,ui.layout.size).grow(.1)
	for id in ui.controls:
		var item = ui.controls[id]
		ok(viewport.encloses(item.get_rect()),context+" fits "+id+" "+str(item.get_rect()))
		ok(item.size.x >= 43.95 and item.size.y >= 43.95,context+" touch "+id)
