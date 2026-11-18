extends "res://tools/capture_r5a.gd"
## Local fake-HTTP visual proof. Args: -- <blue|amber|red|confirmed|final|expired|tutorial> <output.png> [opponent]
func run():
	if DisplayServer.get_name() == "headless": print("Need a graphical display"); quit(2); return
	var args = OS.get_cmdline_user_args()
	var scenario = args[0] if args.size() else "final"
	var out = args[1] if args.size()>1 else "/tmp/nineweave-idle.png"
	var opponent = args.size()>2 and args[2] == "opponent"
	T0 = Time.get_unix_time_from_datetime_string("2026-11-15T12:00:00")
	device_now = T0-42+3
	var main = Main.instantiate(); main.test_online_bypass = true
	main.http_request_factory = func():
		var fake = Fake.new(); fakes.append(fake); return fake
	root.add_child(main); main.set_view_size(Vector2(root.size))
	main.settings.values.sound = false; main.sound.enabled = false
	main.profile.data.character_id = "patrick_laquin"; main.profile.data.display_name = "Nightly"; main.profile.data.onboarded = true
	main.set_process(false); main.social.capabilities = NEW_CAPS.duplicate(true)
	main.open_online(); main.create_online(); main.transport.now_source = func(): return device_now
	respond_end("/rooms",201,waiting_env()); stop(main)
	main.transport._poll(); respond("/rooms/N7QKD?",200,env(3,0)); stop(main)
	main._joined_beat_done(); main.cinematic.advance(3.01); main.cinematic.skip()
	var at = {"blue":3,"amber":19,"red":23,"confirmed":30,"final":3,"expired":25}.get(scenario,3)
	device_now = T0-42+at
	var flags = {"consecutive_late_turns":0,"opponent_consecutive_late_turns":0,"turn_late_limit":3}
	if scenario in ["final","expired"]:
		flags.consecutive_late_turns = 2; flags.turn_expires_at = iso(T0+25)
	elif scenario == "confirmed":
		flags.consecutive_late_turns = 1; flags.still_here_used = true; flags.turn_expires_at = iso(T0+36)
	if opponent:
		flags.opponent_consecutive_late_turns = flags.consecutive_late_turns; flags.consecutive_late_turns = 0
		main.transport.seat = 2; main.human_mark = 2
	main.transport._absorb_room(env(at,0,flags)); main.tick_online()
	main.callout.callout = ""; main.backdrop.set_process(false); main.board.set_process(false)
	main.clock = 4; main.backdrop.clock = 4; main.board.clock = 4
	if scenario == "tutorial":
		main.mode = "computer"; main.page = "title"; main.overlay = ""; main.start_tutorial()
	main.debug_refresh()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var saved = root.get_texture().get_image().save_png(out) == OK
	print("CAPTURE ","PASS" if saved else "FAIL"," scenario=",scenario," size=",root.size," out=",out)
	quit(0 if saved else 1)
