extends SceneTree
const Main = preload("res://main/main.tscn")
const Profile = preload("res://characters/profile.gd")
const Settings = preload("res://settings/store.gd")
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless": print("CAPTURE FAIL: needs Xvfb"); quit(2); return
	var scenario = "bracket_start"; var out = "user://r5b.png"
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		if args[i] in ["--scenario","--out"] and i+1 < args.size():
			var key = args[i]; i += 1
			if key == "--scenario": scenario = args[i]
			else: out = args[i]
		i += 1
	var main = Main.instantiate(); main.test_online_bypass = true
	main.settings = Settings.new("user://r5b-capture.cfg"); main.settings.values.sound = false
	main.profile = Profile.new("user://r5b-capture-profile.cfg"); main.profile.choose("shard_jack","Weaver")
	root.add_child(main); main.set_view_size(Vector2(root.size)); main.set_process(false)
	main.settings.values.reduced_motion = false; main._apply_preferences()
	main.tournament.video_seen = true
	var session = main.tournament.session
	# A real seeded simulation in which both chess rivals reach the final.
	var chosen_seed = 1
	for seed_value in range(1,100):
		session.create("shard_jack",seed_value); session.finish(true); session.finish(true)
		if session.opponent() == "james_ii": chosen_seed = seed_value; break
	session.wins = {}; session.create("shard_jack",chosen_seed)
	if scenario in ["bracket_semis","animation_advance"]: session.finish(true)
	elif scenario == "bracket_final_rival": session.finish(true); session.finish(true)
	elif scenario == "eliminated": session.finish(false)
	elif scenario == "champion": session.finish(true); session.finish(true); session.finish(true)
	elif scenario != "bracket_start": print("CAPTURE FAIL: unknown scenario"); quit(2); return
	main.tournament.pending_events = session.last_events if scenario == "animation_advance" else []
	main.tournament.show()
	var screen = main.tournament.screen; screen.set_process(false); screen.age = 1.8
	if is_instance_valid(screen.bracket):
		screen.bracket.set_process(false); screen.bracket.seek(.23 if scenario == "animation_advance" else 5)
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var capture = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var success = not capture.is_empty() and capture.save_png(out) == OK
	print("CAPTURE ","PASS" if success else "FAIL"," scenario=",scenario," size=",root.size," seed=",chosen_seed," out=",out)
	quit(0 if success else 1)
