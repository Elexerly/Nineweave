extends SceneTree
## Real renderer only. This tool never attempts to open a display in headless mode.
const Main = preload("res://main/main.tscn")
func _initialize(): capture.call_deferred()
func capture():
	if DisplayServer.get_name() == "headless":
		print("CAPTURE FAIL: a real display is required (use Xvfb/Mesa). Headless cannot read viewport pixels.")
		quit(2); return
	var scenario = "midgame"; var out = "user://nineweave.png"; var progress = .45
	var seconds = -1.0; var fps = 0; var duration = 0.0; var sequence = ""
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		var arg = args[i]
		if arg in ["--scenario","--out","--progress","--time","--fps","--duration","--sequence"] and i+1 < args.size():
			i += 1
			if arg == "--scenario": scenario = args[i]
			elif arg == "--out": out = args[i]
			elif arg == "--time": seconds = float(args[i])
			elif arg == "--fps": fps = int(args[i])
			elif arg == "--duration": duration = float(args[i])
			elif arg == "--sequence": sequence = args[i]
			else: progress = float(args[i])
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--time="): seconds = float(arg.trim_prefix("--time="))
		elif arg.begins_with("--progress="): progress = float(arg.trim_prefix("--progress="))
		i += 1
	if not scenario in ["onboarding","online_lobby","online_private","online_leaderboard","online_unranked","select_p1","select_p2","select_p3","select_p4","versus_t","winner_t","winner_cpu_t","draw_t","versus","midgame_heads","winner","winner_cpu","draw","title","midgame","thinking","claim","claim_end","win","win_end","duo","duo_hinge","hinge","settings","online","character_select","lock_in","claim_pop","win_spotlight","duo_panel","last_move","reaction"]:
		print("CAPTURE FAIL: unknown scenario ",scenario); quit(2); return
	var main = Main.instantiate(); main.test_online_bypass = true; root.add_child(main)
	main.set_view_size(Vector2(root.size)); main.settings.values.sound = false; main.sound.enabled = false
	main.settings.saved_game = {}; main.settings.values.reduced_motion = false
	main.profile.data.character_id = OS.get_environment("NW_HERO") if OS.has_environment("NW_HERO") else "vesper_vale"; main.profile.data.display_name = "Weaver"; main.profile.data.onboarded = true
	main.rival_character = OS.get_environment("NW_RIVAL") if OS.has_environment("NW_RIVAL") else "auric_rex"; main.settings.values.player_name = "You"
	main.settings.values.background_theme = "crystal"; main.settings.values.board_theme = "crystal"; main._apply_preferences()
	var timed = scenario.ends_with("_t")
	var base = scenario.trim_suffix("_t") if timed else scenario
	main.debug_scenario(base,progress)
	if timed or seconds >= 0: main.debug_seek_cinematic(maxf(0,seconds))
	# Fixed decorative pose; animations are posed by the debug hooks.
	main.set_process(false); main.backdrop.set_process(false); main.board.set_process(false)
	main.clock = 4; main.backdrop.clock = 4; main.board.clock = 4
	for particle in main.backdrop.find_children("*","CPUParticles2D",true,false): particle.emitting = false
	# Posed effects (particles, flashes, rays, result panel) are pure functions of progress;
	# repaint every layer once with the pinned clocks.
	main.debug_refresh()
	if not sequence.is_empty():
		if fps <= 0 or duration < 0 or not base in ["versus","winner","winner_cpu","draw"]:
			print("CAPTURE FAIL: sequences need a cinematic, positive FPS and nonnegative duration"); quit(2); return
		DirAccess.make_dir_recursive_absolute(sequence)
		for frame in range(int(floor(duration*fps))+1):
			main.debug_seek_cinematic(float(frame)/fps)
			# Two redraws avoid reading a stale viewport after a result-button rebuild.
			await process_frame; await process_frame; await RenderingServer.frame_post_draw
			if not save(sequence.path_join("frame_%04d.png" % frame)): quit(1); return
		print("CAPTURE SEQUENCE PASS scenario=",scenario," fps=",fps," duration=",duration," out=",sequence)
		quit(); return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var success = save(out)
	print("CAPTURE ","PASS" if success else "FAIL"," scenario=",scenario," progress=",progress," time=",seconds," size=",root.size," out=",out)
	quit(0 if success else 1)
func save(out: String) -> bool:
	var image = root.get_texture().get_image()
	if image == null or image.is_empty(): print("CAPTURE FAIL: empty viewport"); return false
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	return image.save_png(out) == OK
