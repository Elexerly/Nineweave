extends SceneTree
const Main = preload("res://main/main.tscn")
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless":
		print("CAPTURE FAIL: need a real display (xvfb)"); quit(2); return
	var scenario = "onboarding"
	var out = "user://r4f.png"
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		var arg = args[i]
		if arg in ["--scenario","--out"] and i+1 < args.size():
			i += 1
			if arg == "--scenario": scenario = args[i]
			else: out = args[i]
		i += 1
	var main = Main.instantiate(); main.test_online_bypass = true; root.add_child(main)
	main.set_view_size(Vector2(root.size)); main.settings.values.sound = false; main.sound.enabled = false
	main.settings.saved_game = {}; main.settings.values.reduced_motion = false
	main.profile.data.character_id = "vesper_vale"; main.profile.data.display_name = "Weaver"; main.profile.data.onboarded = true
	main.rival_character = "auric_rex"; main.settings.values.player_name = "You"
	main.settings.values.background_theme = "crystal"; main.settings.values.board_theme = "crystal"; main._apply_preferences()
	if scenario == "onboarding":
		main.debug_scenario("onboarding")
	elif scenario == "email":
		main.debug_scenario("email")
	elif scenario == "tutorial":
		main.debug_scenario("tutorial")
		# Fixture advances once; rewind to the first step and show a completed arrow.
		if main.tutorial.active:
			main.tutorial.step = 0; main.tutorial._show_step(); main.tutorial.age = 1
			main.tutorial.set_process(false); main.tutorial.queue_redraw()
	else:
		print("CAPTURE FAIL: unknown scenario ",scenario); quit(2); return
	main.set_process(false); main.backdrop.set_process(false); main.board.set_process(false)
	main.clock = 4; main.backdrop.clock = 4; main.board.clock = 4
	main.debug_refresh()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image == null or image.is_empty():
		print("CAPTURE FAIL: empty viewport"); quit(1); return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var ok = image.save_png(out) == OK
	print("CAPTURE ","PASS" if ok else "FAIL"," scenario=",scenario," size=",root.size," out=",out)
	quit(0 if ok else 1)
