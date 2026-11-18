extends "res://tests/run_round5a_tests.gd"
## Reuses isolated fake-HTTP fixtures; no real server/database is contacted.
func run():
	T0 = Time.get_unix_time_from_datetime_string("2026-11-15T12:00:00")
	device_now = T0-300+3
	var bundle = make_ui("idle-warning")
	var ui = bundle.ui
	start_match(bundle,{"consecutive_late_turns":2,"opponent_consecutive_late_turns":0,"turn_late_limit":3,"turn_expires_at":iso(T0+25)})
	ok(is_instance_valid(ui.timer_overlay) and ui.timer_overlay.z_index == 20 and ui.timer_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,"timer HUD is foreground and never intercepts taps")
	ok(ui.timer_hud_visible(),"real online game shows timer HUD")
	for child in ui.get_children():
		if child.get_script() == preload("res://characters/art.gd"): ok(child.z_index < ui.timer_overlay.z_index,"hero portrait cannot cover countdown HUD")
	ui.overlay = "settings"; ok(not ui.timer_hud_visible(),"modal hides timer HUD"); ui.overlay = ""
	ui.tutorial.active = true; ok(not ui.timer_hud_visible(),"tutorial hides timer HUD"); ui.tutorial.active = false
	ui.mode = "computer"; ok(not ui.timer_hud_visible(),"offline games hide timer HUD"); ui.mode = "online"
	ok(ui.idle_turn_warning() == "Final warning: move in 0:22 or lose","third consecutive own turn warns from its beginning")
	ok(ui.online_lines()[1] == ui.idle_turn_warning(),"warning displayed beside game, not hidden behind the prompt")
	device_now += 5
	ok(ui.idle_turn_warning() == "Final warning: move in 0:17 or lose","warning countdown decreases without polling")
	ui.transport.reconnecting = true
	ok("timer continues" in ui.online_lines()[0] and "0:17" in ui.online_lines()[1],"reconnect does not conceal or restart final warning")
	ui.transport.reconnecting = false
	device_now = T0-300+25
	ui.tick_online(); ui._sync_fx() # Mirrors the frame loop after deadline evaluation.
	ok(ui.turn_info().phase == "expired" and ui.prompt_state().is_empty(),"third prompt boundary is terminal: no false 10-second extension")
	ok(not ui.transport.still_here(),"no third-strike acknowledgment sent at expired boundary")
	ok("checking result" in ui.online_lines()[0],"expired client waits for authoritative result, never awards itself win")
	ok(not ui.local_online_turn() and not ui.board.active_highlights_enabled and ui.online_turn_caption() == "Checking result…","expired turn has no misleading blue playable highlight or Your turn caption")
	ok(not ui.play_cell(4,4),"expired client cannot queue another move while waiting for server result")
	# A successful first/second acknowledgment is a 10-second red countdown, both clients.
	device_now = T0-300+30
	ui.transport._absorb_room(env(30,0,{"still_here_used":true,"turn_expires_at":iso(T0+36),"consecutive_late_turns":1,"opponent_consecutive_late_turns":2,"turn_late_limit":3}))
	ok(ui.turn_info().tier == "red" and absf(ui.turn_info().remaining-6)<.01,"confirmed extension is visibly red and has actual six seconds left")
	ok(ui.idle_turn_warning().begins_with("Late turns: 1/3"),"local warning uses own streak, not opponent's")
	# Same server turn viewed as opponent, preserving deadline and seat identity.
	ui.transport.seat = 2; ui.human_mark = 2
	ui.transport._absorb_room(env(30,0,{"still_here_used":true,"turn_expires_at":iso(T0+36),"consecutive_late_turns":2,"opponent_consecutive_late_turns":1,"turn_late_limit":3}))
	ok(not ui.turn_info().mine and absf(ui.turn_info().remaining-6)<.01,"opponent sees same clock and not a fake local turn")
	ok(ui.idle_turn_warning() == "Opponent late turns: 1/3","opponent warning uses active opponent's streak")
	for size in [Vector2(320,568),Vector2(390,844),Vector2(430,932),Vector2(844,390),Vector2(553,867),Vector2(780,900),Vector2(867,553),Vector2(1366,768)]:
		ui.set_view_size(size)
		for mark in [1,2]:
			var ring = ui.timer_ring_rect(mark)
			ok(Rect2(Vector2.ZERO,size).encloses(ring) and not ring.intersects(ui.layout.board),"portrait timer remains on-screen and clear of board at %s mark%d" % [size,mark])
		ok(not ui.timer_ring_rect(1).intersects(ui.timer_ring_rect(2)),"player timer rings stay separate at "+str(size))
	# Older API envelopes must still show a ring with real server expiry only.
	ui.transport.room.erase("still_there_at")
	var legacy = ui.timer_ring_info()
	ok(legacy.phase == "legacy" and absf(legacy.remaining-6)<.01,"legacy ring retains actual server deadline")
	ok(absf(legacy.fraction-6.0/36.0)<.01,"legacy arc uses server start-to-expiry duration, not invented25seconds")
	ui.transport.room.erase("turn_started_at")
	legacy = ui.timer_ring_info()
	ok(legacy.fraction == 1.0 and legacy.remaining == 6,"missing duration keeps neutral full rail with real remainingseconds")
	ui.free(); await frames()
	print("NINEWEAVE_IDLE_WARNING ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
