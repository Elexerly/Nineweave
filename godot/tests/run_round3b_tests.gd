extends SceneTree
## Round 3b regression suite: one block per bug fixed in the Claude bug-hunt pass, plus
## rules/AI edge cases, persistence, corner layout against live HUD nodes and leak checks.
const Rules = preload("res://kernel/rules.gd")
const AI = preload("res://ai/strategist.gd")
const F = preload("res://tests/fixtures.gd")
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Sound = preload("res://fx/sound.gd")
const Layout = preload("res://ui/layout.gd")
const Cinema = preload("res://characters/cinematic.gd")
const Loopback = preload("res://net/loopback_transport.gd")
const SIZES = [[390,844],[360,640],[430,932],[375,667],[844,390],[932,430],[667,375],[568,320],[768,1024],[1024,768],[1366,1024],[1280,720],[1920,1080],[1024,720],[960,720],[800,600],[800,700],[720,700],[1180,820],[867,553],[867,500],[867,600],[669,787],[669,720],[2601,1659]]
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func blank() -> Array:
	var p: Array = []
	for i in range(9): p.append(".........")
	return p

func run():
	rules_edges()
	ai_legal_everywhere()
	persistence()
	audio()
	var ui = Main.instantiate(); ui.settings = Store.new("user://r3b-ui.cfg"); ui.profile = Profile.new("user://r3b-profile.cfg")
	ui.settings.values.sound = false; ui.settings.values.reduced_motion = false; ui.profile.data.onboarded = true
	root.add_child(ui); await frames()
	ui.set_view_size(Vector2(390,844)); await frames()
	await spotlight_input(ui)
	await hint_and_highlight(ui)
	await pops(ui)
	await corner_layout(ui)
	await leak_loop(ui)
	ui.queue_free(); await frames(3)
	print("NINEWEAVE_ROUND3B ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------ 1. rules
func rules_edges():
	# Sent to a claimed board: free move.
	var p = blank(); p[0] = "XXXOO...."
	var g = F.position(p,1,4); ok(g.play(4,0) and g.active_board == -1,"sent to claimed board is a free move")
	ok(g.legal_moves().size() == 8*9-1,"free move offers every open board, none in the claimed one")
	# Sent to a full (drawn) board: free move.
	p = blank(); p[3] = "XOXXOOOXX"
	g = F.position(p,1,4); ok(g.owners[3] == Rules.DRAW,"full small board without a line is sealed")
	ok(g.play(4,3) and g.active_board == -1,"sent to full board is a free move")
	# Small-board draw produced by the last cell.
	p = blank(); p[1] = "XOXXOOOX."
	g = F.position(p,1,1); ok(g.play(1,8) and g.owners[1] == Rules.DRAW and g.status == 0,"filling a board with no line draws it")
	ok(g.active_board == 8,"sealing move still routes to its open target")
	ok(g.play(8,1) and g.active_board == -1,"sent to the just-sealed board is a free move")
	# Line on the ninth cell counts as a claim, not a draw.
	p = blank(); p[2] = "XX.OOXOXO"
	g = F.position(p,1,2); ok(g.play(2,2) and g.owners[2] == 1,"line on the last cell claims, not seals")
	# Overall draw on the very last move.
	p = ["XXXOO....","OOOXX....","XXXOO....","XXXOO....","OOOXX....","OOOXX....","OOOXX....","XXXOO....","XOXXOOOX."]
	g = F.position(p,1,8); ok(g.status == 0,"8 boards closed, game open")
	ok(g.play(8,8) and g.status == Rules.DRAW and g.legal_moves().is_empty(),"overall draw when the last board seals with no line")
	ok(g.undo() and g.status == 0 and g.owners[8] == 0 and g.active_board == 8,"undo restores a drawn game")
	# Win detection on the last move of the game (board fills and makes the big line).
	p = ["XXXOO....","OOOXX....","OOOXX....","OOOXX....","XXXOO....","XXXOO....","XXXOO....","OOOXX....","XX.OOXOXO"]
	g = F.position(p,1,8)
	ok(g.play(8,2) and g.status == 1 and g.big_lines == [[0,4,8]],"last-move win beats overall draw")
	ok(g.undo() and g.status == 0 and g.big_lines.is_empty() and g.owners[8] == 0 and g.small_lines[8].is_empty(),"undo after win reopens the game")
	ok(g.play(8,2) and g.status == 1,"replay after undo wins again")
	# Undo after an ordinary claim.
	p = blank(); p[0] = "XX.OO...."
	g = F.position(p,1,0); g.play(0,2)
	ok(g.owners[0] == 1 and g.active_board == 2,"claim recorded, routed to open board 2")
	ok(g.undo() and g.owners[0] == 0 and g.active_board == 0 and g.turn == 1,"undo after claim restores board and target")
	# Rejection after game over.
	g = F.big_tactic(1); g.play(2,2); ok(not g.play(5,5) and g.legal_moves().is_empty(),"no moves after win")

# ------------------------------------------------------------------ AI
func ai_legal_everywhere():
	var rng = RandomNumberGenerator.new(); rng.seed = 3301
	var free_positions = 0; var bad = 0; var tested = 0
	for game_index in range(14):
		var g = Rules.new()
		while g.status == 0:
			if g.history.size()%3 == 0 or g.active_board == -1:
				if g.active_board == -1: free_positions += 1
				for level in ["Easy","Medium","Hard"]:
					var ai = AI.new(game_index*31+g.history.size()); ai.node_limit = 90
					var m = ai.choose_move(g,level); tested += 1
					if not g.is_legal(m.x,m.y): bad += 1
			var moves = g.legal_moves(); var pick = moves[rng.randi_range(0,moves.size()-1)]
			g.play(pick.x,pick.y)
	ok(bad == 0 and tested > 300,"AI legal at every difficulty (%d probes, %d free-move positions)" % [tested,free_positions])
	ok(free_positions > 10,"free-move positions exercised")
	# Hint (Hard) on a free move.
	var p = blank(); p[0] = "XXXOO...."
	var g = F.position(p,2,-1)
	var hint = AI.new(444).choose_move(g,"Hard"); ok(g.is_legal(hint.x,hint.y),"hint legal on free move")

# ------------------------------------------------------------------ 6. persistence
func persistence():
	var path = "user://r3b-store.cfg"; DirAccess.remove_absolute(path)
	var s = Store.new(path)
	s.set_value("sound",false); s.set_value("sfx_volume",.3); s.set_value("announcer_volume",.2); s.set_value("difficulty","Easy")
	s.set_value("background_theme","dusk"); s.set_value("board_theme","sandstone"); s.set_value("reduced_motion",true)
	var r = Store.new(path)
	ok(not r.values.sound and is_equal_approx(r.values.sfx_volume,.3) and is_equal_approx(r.values.announcer_volume,.2),"mute and volumes persist across restart")
	ok(r.values.difficulty == "Easy" and r.values.reduced_motion and r.values.board_theme == "sandstone","difficulty/motion/board theme persist")
	ok(r.values.background_theme in ["dusk","crystal"],"background theme validated")
	# Missing file.
	DirAccess.remove_absolute("user://r3b-missing.cfg")
	var m = Store.new("user://r3b-missing.cfg"); ok(m.values == Store.DEFAULTS and m.saved_game.is_empty(),"missing file uses defaults")
	# Garbage file.
	var f = FileAccess.open("user://r3b-garbage.cfg",FileAccess.WRITE); f.store_buffer(PackedByteArray([0,255,91,91,0,61,61,10,0,7])); f.close()
	var garbage = Store.new("user://r3b-garbage.cfg"); ok(garbage.values.sound == true and garbage.values.difficulty == "Hard","garbage file falls back to defaults")
	# Wrong types (the Round 3 store crashed on bool("yes") / saved_game.state).
	var c = ConfigFile.new()
	c.set_value("settings","sound","yes"); c.set_value("settings","sfx_volume","loud"); c.set_value("settings","announcer_volume",[1])
	c.set_value("settings","difficulty","Impossible"); c.set_value("settings","player_name",42); c.set_value("settings","reduced_motion",1)
	c.set_value("settings","audio_version",[3]); c.set_value("settings","background_theme",7)
	c.set_value("resume","game","corrupt"); c.save("user://r3b-typed.cfg")
	var t = Store.new("user://r3b-typed.cfg")
	ok(t.values.sound is bool and t.values.sound,"non-bool mute → default")
	ok(is_equal_approx(t.values.sfx_volume,.85) and is_equal_approx(t.values.announcer_volume,.9),"non-numeric volumes → defaults")
	ok(t.values.difficulty == "Hard" and t.values.player_name == "You" and t.values.reduced_motion == true,"bad difficulty/name repaired, numeric bool accepted")
	ok(t.values.background_theme == "crystal" and t.saved_game is Dictionary and t.saved_game.is_empty(),"bad theme/saved game dropped")
	c = ConfigFile.new(); c.set_value("settings","audio_version",3); c.set_value("resume","game",{"state":{},"human":7}); c.save("user://r3b-typed2.cfg")
	ok(Store.new("user://r3b-typed2.cfg").saved_game.is_empty(),"saved game with bad seat dropped")
	# Profile: selected character persists; corrupt types fall back.
	var pp = "user://r3b-prof.cfg"; DirAccess.remove_absolute(pp)
	var pr = Profile.new(pp); pr.choose("nyx_thread","Ada")
	ok(Profile.new(pp).data.character_id == "nyx_thread","selected character persists")
	c = ConfigFile.new(); c.set_value("profile","character_id",5); c.set_value("profile","onboarded","sure"); c.set_value("profile","display_name",[1]); c.save(pp)
	var bad = Profile.new(pp)
	ok(bad.data.character_id == "vesper_vale" and bad.data.onboarded == false and bad.data.display_name == "You","corrupt profile → safe defaults")

# ------------------------------------------------------------------ 5. audio
func audio():
	var sound = Sound.new(); root.add_child(sound)
	sound.configure({"sound":true,"sfx_volume":.5,"announcer_volume":.25,"music_volume":.4})
	# Locked queue must not hold the mix ducked.
	sound.announce("ready"); sound.advance_mix(.5)
	ok(not sound.unlocked and absf(sound.duck_db) < .01,"lines waiting for first gesture do not duck")
	var press = InputEventScreenTouch.new(); press.pressed = true; sound._input(press)
	var release = InputEventScreenTouch.new(); release.pressed = false; sound._input(release)
	ok(sound.unlocked and sound.unlock_plays == 2,"silent unlock in first touchstart AND touchend (iOS)")
	sound._input(press); sound._input(release); ok(sound.unlock_plays == 2,"unlock only once per gesture kind")
	# Ducking restores exact configured volumes.
	sound.clear_announcer(); sound.announce("victory","victory"); sound.advance_mix(.2)
	var sfx_bus = AudioServer.get_bus_index("SFX"); var music_bus = AudioServer.get_bus_index("Music")
	ok(AudioServer.get_bus_volume_db(sfx_bus) < linear_to_db(.5)-3,"announcer ducks SFX")
	for i in range(80): sound.advance_mix(.1)
	ok(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus),linear_to_db(.5)) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus),linear_to_db(.4)),"duck release restores exact SFX/music volume")
	ok(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Announcer")),linear_to_db(.25)),"announcer volume respected")
	# Queue: no overlap, stale ladder lines capped, result lines never dropped.
	sound.clear_announcer()
	for id in ["first_claim","double_lock","triple_weave","match_point","turnaround","nineweave"]: sound.announce(id)
	sound.announce("defeat","defeat")
	var queued: Array = []
	for e in sound.voice_queue: queued.append(e.id)
	ok(sound.voice_queue.size() <= 3 and "nineweave" in queued and "defeat" in queued,"stale lines capped, result lines kept "+str(queued))
	var heard: Array = [sound.voice_id]; var overlap = false
	for i in range(200):
		var before = sound.voice_id; sound.advance_mix(.05)
		if sound.voice_id != before and not before.is_empty() and sound._announcer_left > 0 and sound._gap_left > 0: overlap = true
		if not sound.voice_id.is_empty() and sound.voice_id != heard.back(): heard.append(sound.voice_id)
	ok(not overlap and heard.back() == "defeat","voice lines play one at a time, ending on the result "+str(heard))
	# Every owner .ogg is reachable from a cue; cues without a file synthesize.
	var cue_paths = {}
	for id in Sound.VOICES: cue_paths[Sound.real_path("ann_"+id)] = true
	for id in Sound.REAL_SFX: cue_paths[Sound.real_path(id)] = true
	for dir in ["res://assets/audio/announcer","res://assets/audio/sfx"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".ogg"): ok(cue_paths.has(dir+"/"+file),"owner audio wired to a cue "+file)
	for path in cue_paths: ok(Sound.load_real(path) is AudioStreamOggVorbis,"cue resolves to real ogg "+path)
	for id in ["place_x","place_o","draw","unlock"]: ok(Sound.real_path(id).is_empty() and sound.stream_for(id) is AudioStreamWAV,"no owner file: synth fallback "+id)
	# Mute respected.
	sound.enabled = false; sound.announce("victory"); var before_streams = []
	for p in sound._players: before_streams.append(p.stream)
	sound.cue("claim_x")
	var same = true
	for i in range(sound._players.size()): same = same and sound._players[i].stream == before_streams[i]
	ok(sound.voice_queue.is_empty() and sound.voice_id.is_empty() and same,"mute blocks voices and SFX")
	sound.queue_free()

# ------------------------------------------------------------------ 4. spotlight
func spotlight_input(ui):
	ui.debug_load_position(F.big_tactic(1).serialize(),"computer"); ui._debug_capture = false; ui.thinking = false
	ok(ui._apply_move(2,2) and ui.game.status == 1,"winning move")
	ui.board.advance(4); ui._process(.01)
	ok(ui.cinematic.active and ui.cinematic.kind == "spotlight","spotlight shown")
	var history = ui.game.history.size()
	# Board input blocked while it shows (even before the 200 ms skip window).
	ok(not ui.play_cell(5,5) and ui.game.history.size() == history,"board play rejected during spotlight")
	var key = InputEventKey.new(); key.pressed = true; key.keycode = KEY_SPACE
	root.push_input(key)
	ok(ui.cinematic.active,"early key does not skip inside the 200 ms guard")
	ui._process(.01); ok(ui.cinematic.active and ui.cinematic.kind == "spotlight","no double trigger while active")
	ui.cinematic.advance(.85)
	root.push_input(key)
	ok(not ui.cinematic.active and ui.overlay == "result" and not ui.board.frozen,"key skips spotlight, board unfreezes")
	ui._process(.01); ok(not ui.cinematic.active,"spotlight not re-triggered after skip")
	# Touch skip: touch press then emulated mouse press/release on Play Again must not press it.
	ui.undo_move(); ui.thinking = false; ui._debug_capture = false
	ok(ui.game.status == 0 and ui.overlay.is_empty(),"undo after win reopens game")
	ui._apply_move(2,2); ui.board.advance(4); ui._process(.01); ui.cinematic.advance(.85)
	var started = [0]
	var touch = InputEventScreenTouch.new(); touch.pressed = true; touch.position = Vector2(195,600)
	ui._input(touch)
	ok(ui.overlay == "result" and ui.controls.has("again"),"touch skips to result")
	ui.controls.again.pressed.connect(func(): started[0] += 1)
	ui._result_t = 1.0; ui._apply_result_anim()
	var at = ui.controls.again.get_global_rect().get_center()
	for pressed in [true,false]:
		var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = pressed; mouse.position = at; mouse.global_position = at
		root.push_input(mouse,true)
	ok(started[0] == 0 and ui.overlay == "result","skip gesture's emulated click does not press Play Again")
	ui._skip_guard_until = 0
	for pressed in [true,false]:
		var mouse = InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = pressed; mouse.position = at; mouse.global_position = at
		root.push_input(mouse,true)
	ok(started[0] == 1 and ui.page == "game" and ui.game.history.is_empty(),"a later deliberate tap on Play Again rematches")
	ok(ui.board.last_move.x < 0 and ui.board.win_fx.is_empty(),"rematch clears highlight and win FX")
	ui.thinking = false
	# Menu works after skip.
	ui.debug_load_position(F.big_tactic(1).serialize(),"local"); ui._debug_capture = false
	ui._apply_move(2,2); ui.board.advance(4); ui._process(.01); ui.cinematic.advance(.85); ui.cinematic.skip()
	ui.controls.menu.pressed.emit(); ok(ui.page == "title" and not ui.cinematic.active,"menu works after skip")
	await frames()

# ------------------------------------------------------------------ 1/2. hint + highlight
func hint_and_highlight(ui):
	# Round 3e: hints exist only vs the computer.
	ui.start_game("computer"); ui._debug_capture = true
	# Stale hint: computed for an old position, must not appear after a move.
	ui.request_hint(); ok(ui.hint_busy,"hint started")
	ui._apply_move(4,4)
	for i in range(200):
		ui.hint_ai.step(5000)
		if ui.hint_ai.done: break
	ui._process(.01); ok(ui.board.hint_move == Vector2i(-1,-1),"hint for an old position is discarded")
	# Hint on a free move through the real controller.
	var p = blank(); p[0] = "XXXOO...."
	ui.debug_load_position(F.position(p,2,-1).serialize(),"computer")
	ui.request_hint()
	for i in range(300):
		ui.hint_ai.step(5000)
		if ui.hint_ai.done: break
	ui._process(.01); ok(ui.game.is_legal(ui.board.hint_move.x,ui.board.hint_move.y) and ui.game.active_board == -1,"hint legal on free move in UI")
	# Online loopback: opponent's move is highlighted, own move clears, rematch clears.
	Loopback.reset_service()
	Loopback.assignment_rng.seed = 1
	while true:
		var saved_state = Loopback.assignment_rng.state
		if Loopback.assignment_rng.randi_range(1,2) == 1:
			Loopback.assignment_rng.state = saved_state; break
	ui.create_online(true); ui.invite_demo_rival(); ui.cinematic.advance(3.01)
	ok(not ui._debug_capture,"online match leaves debug capture off")
	ok(ui.mode == "online" and ui.page == "game" and ui.remote_ready,"loopback match started")
	ok(ui.play_cell(4,4),"online local move sent")
	ok(ui.board.last_move.x < 0,"own online move not highlighted")
	for i in range(400):
		ui._process(.02)
		if ui.game.history.size() >= 2: break
	ok(ui.game.history.size() == 2 and ui.board.last_move == Vector2i(ui.game.history[1].board,ui.game.history[1].cell),"online rival move highlighted")
	ui.open_online(); ui.create_online(true); ui.invite_demo_rival()
	ok(ui.board.last_move.x < 0 and ui.game.history.is_empty(),"online rematch clears highlight")
	ui.go_home(); Loopback.reset_service()
	await frames()

# ------------------------------------------------------------------ 3. pops
func pops(ui):
	ui.set_view_size(Vector2(390,844))
	ui.start_game("local"); ui._debug_capture = false
	var children = ui.cinematic.get_child_count()
	# Several fast claims: one panel, replaced, never stacked.
	for board_index in [0,1,2]:
		var p = blank(); p[board_index] = "XX.OO...."
		ui.debug_load_position(F.position(p,1,board_index).serialize(),"local"); ui._debug_capture = false
		ui._input_beat = 0; ui.play_cell(board_index,2)
		ok(ui.cinematic.active and ui.cinematic.kind == "pop" and ui.cinematic._claimed_board == board_index,"pop for claim %d" % board_index)
	ok(ui.cinematic.get_child_count() == children,"fast claims reuse one pop (no stacking)")
	ok(ui.cinematic.hero.hero_id == ui.hero_for(1) and ui.cinematic.player == 1,"pop shows the claiming side's hero")
	# Rotate mid-pop: the panel is re-placed and still leaves the claimed board visible.
	ui.set_view_size(Vector2(844,390))
	var b: Rect2 = ui.layout.board; var pad = b.size.x*.022; var gap = b.size.x*.018; var edge = (b.size.x-pad*2-gap*2)/3
	var tile = Rect2(b.position+Vector2(pad+2*(edge+gap),pad),Vector2.ONE*edge)
	ok(ui.cinematic.region == Cinema.pop_region(ui.layout,2) and not ui.cinematic.region.intersects(tile),"pop re-placed after resize, claimed board visible")
	# Opening settings drops the pop so it never paints over the modal.
	ui.show_settings(); ok(not ui.cinematic.active,"settings clears pop")
	ui._close_overlay()
	var p2 = blank(); p2[0] = "OO.XX...."
	ui.debug_load_position(F.position(p2,2,0).serialize(),"local"); ui._debug_capture = false; ui.play_cell(0,2)
	ok(ui.cinematic.active and ui.cinematic.hero.hero_id == ui.hero_for(2) and ui.cinematic.player == 2,"O claim pops O's hero")
	ui.go_home(); ok(not ui.cinematic.active and not ui.cinematic.visible,"scene change frees pop")
	ui.set_view_size(Vector2(390,844))
	await frames()

# ------------------------------------------------------------------ 7. live corner layout
func corner_layout(ui):
	ui.start_game("computer"); ui.thinking = false; ui._debug_capture = true
	for size in SIZES:
		var v = Vector2(size[0],size[1])
		ui.set_view_size(v); var l = ui.layout; var id = str(v)
		var hud = Layout.hud_rects(l)
		var nodes: Array = []
		for key in ["home","settings","undo","hint"]:
			if ui.controls.has(key): nodes.append([key,Rect2(ui.controls[key].position,ui.controls[key].size)])
		ok(Rect2(Vector2.ZERO,l.size).encloses(nodes[1][1]),id+" gear inside view")
		for mark in [1,2]:
			ok(ui.field_heroes.has(mark),id+" live reactor for side "+str(mark))
			var rig = ui.field_heroes[mark]; var r = Rect2(rig.position,rig.size)
			ok(not r.intersects(l.board) and rig.mouse_filter == Control.MOUSE_FILTER_IGNORE and not rig.frozen,id+" live hero off board "+str(mark))
			var hosted = (mark == ui.human_mark and l.hero_player_host == "character") or not (Layout.MIN_CORNER <= (l.hero_player if mark == ui.human_mark else l.hero_opponent).size.y)
			for n in nodes: ok(not r.intersects(n[1]),id+" hero %d clear of %s" % [mark,n[0]])
			if not hosted:
				for key in hud: ok(not r.intersects(hud[key]),id+" corner %d clear of HUD %s" % [mark,key])
			else:
				ok(r.size.y >= 36,id+" scorecard/panel figure readable "+str(r.size))
		var a = ui.field_heroes[1]; var z = ui.field_heroes[2]
		ok(not Rect2(a.position,a.size).intersects(Rect2(z.position,z.size)),id+" two live heroes apart")
	ui.set_view_size(Vector2(390,844)); ui.go_home()
	await frames()

# ------------------------------------------------------------------ 9. leaks
func leak_loop(ui):
	var picker = AI.new(77)
	var baseline_nodes = 0; var baseline_orphans = 0
	var modes = ["local","computer"]
	for n in range(56):
		ui.start_game(modes[n%2]); ui._debug_capture = false; ui.thinking = false
		var guard = 0
		while ui.game.status == 0 and guard < 90:
			var m = picker.choose_move(ui.game,"Easy"); ui._input_beat = 0; ui.thinking = false
			ui._apply_move(m.x,m.y); ui.thinking = false
			ui.board.advance(.2); ui.cinematic.advance(.2); guard += 1
		ui.board.advance(4); ui._process(.01)
		if ui.cinematic.active: ui.cinematic.advance(.85); ui.cinematic.skip()
		if n%7 == 3: ui.set_view_size(Vector2(867,553) if n%2 else Vector2(390,844))
		if n%9 == 4: ui.show_settings(); ui._close_overlay()
		ui.go_home()
		await frames(2)
		if n == 5:
			baseline_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT); baseline_orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	await frames(3)
	var nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT); var orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("LEAK games=56 nodes_after_6=",baseline_nodes," nodes_after_56=",nodes," orphans=",baseline_orphans,"→",orphans)
	ok(nodes <= baseline_nodes+2,"node count flat over 50+ games")
	ok(orphans <= baseline_orphans,"no orphan nodes accumulate")
	ok(ui.board.claims.is_empty() and ui.cinematic.get_child_count() == 3,"no lingering claim FX or cinematic rigs")
