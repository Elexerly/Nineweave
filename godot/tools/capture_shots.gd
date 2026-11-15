extends SceneTree
## Real renderer only. This tool never attempts to open a display in headless mode.
const Main = preload("res://main/main.tscn")
func _initialize(): capture.call_deferred()
func capture():
	if DisplayServer.get_name() == "headless":
		print("CAPTURE FAIL: a real display is required (use Xvfb/Mesa). Headless cannot read viewport pixels.")
		quit(2); return
	var scenario = "midgame"; var out = "user://nineweave.png"; var progress = .45
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		var arg = args[i]
		if arg in ["--scenario","--out","--progress"] and i+1 < args.size():
			i += 1
			if arg == "--scenario": scenario = args[i]
			elif arg == "--out": out = args[i]
			else: progress = float(args[i])
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--progress="): progress = float(arg.trim_prefix("--progress="))
		i += 1
	if not scenario in ["title","midgame","thinking","claim","claim_end","win","win_end","duo","duo_hinge","hinge","settings","online"]:
		print("CAPTURE FAIL: unknown scenario ",scenario); quit(2); return
	var main = Main.instantiate(); root.add_child(main)
	main.set_view_size(Vector2(root.size)); main.settings.values.sound = false; main.sound.enabled = false
	main.settings.saved_game = {}; main.debug_scenario(scenario,progress)
	# Fixed decorative pose; animations are posed by the debug hooks.
	main.set_process(false); main.backdrop.set_process(false); main.board.set_process(false)
	main.clock = 4; main.backdrop.clock = 4; main.board.clock = 4
	for particle in main.backdrop.find_children("*","CPUParticles2D",true,false): particle.emitting = false
	# Posed effects (particles, flashes, rays, result panel) are pure functions of progress;
	# repaint every layer once with the pinned clocks.
	main.debug_refresh()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image == null or image.is_empty(): print("CAPTURE FAIL: empty viewport"); quit(1); return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err = image.save_png(out)
	print("CAPTURE ","PASS" if err == OK else "FAIL"," scenario=",scenario," progress=",progress," size=",image.get_size()," out=",out)
	quit(0 if err == OK else 1)
