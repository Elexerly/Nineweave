extends SceneTree
## Real rendered clips and mocked online3 screens. No live API calls.
const Main = preload("res://main/main.tscn")
const Profile = preload("res://characters/profile.gd")
const Settings = preload("res://settings/store.gd")
const Fake = preload("res://tests/fake_http.gd")
const F = preload("res://tests/round5c_fixtures.gd")
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless": print("CAPTURE FAIL: needs Xvfb"); quit(2); return
	var scenario = "versus"; var out = "user://r5c.png"
	var args = OS.get_cmdline_user_args(); var i = 0
	while i < args.size():
		if args[i] in ["--scenario","--out"] and i+1 < args.size():
			if args[i] == "--scenario": scenario = args[i+1]
			else: out = args[i+1]
			i += 1
		i += 1
	var main = Main.instantiate(); main.test_online_bypass = true
	main.settings = Settings.new("user://r5c-shots-settings.cfg"); main.settings.values.sound = false
	main.settings.values.reduced_motion = false; main.settings.values.tutorial_completed = true
	main.profile = Profile.new("user://r5c-shots-profile.cfg"); main.profile.choose("shard_jack","Weaver")
	main.http_request_factory = func(): return Fake.new()
	root.add_child(main); main.set_view_size(Vector2(root.size)); main.set_process(false)
	main.online_tournament.set_process(false); main._apply_preferences(); main.rival_character = "james_ii"
	match scenario:
		"versus": main.start_game("computer",1,true,true)
		"victory","defeat","victory_still":
			main.start_game("computer",1,true,false); main.game.status = 2 if scenario == "defeat" else 1
			main.cinematic.clear()
			if scenario == "victory_still": main.cinematic.video_source = null
			main._show_spotlight()
		"chooser": main.online_tournament.request()
		"tournament_lobby","tournament_private","coming_soon":
			main.online_tournament.state = "lobby"; main.page = "online_tournament"
			main.online_tournament.unavailable = scenario == "coming_soon"
			main.online_tournament.private_tournament = scenario == "tournament_private"
			main.online_tournament.listing = [{"code":"T7KQ2M","host":"Kai","size":8,"joined":6}]
			main._rebuild()
		"bracket","countdown","registered","eliminated","champion":
			var flow = main.online_tournament
			flow.state = "waiting"; flow.code = "T7KQ2M"; flow.snapshot = F.envelope("registering" if scenario == "registered" else "running")
			if scenario == "countdown": flow.countdown = 3
			if scenario == "eliminated": flow.snapshot.you.state = "eliminated"; flow.snapshot.players[0].eliminated = true
			if scenario == "champion":
				flow.snapshot.status = "finished"; flow.snapshot.you.state = "champion"; flow.snapshot.champion = {"name":"Weaver","hero":"shard_jack"}
			main.page = "online_tournament"; main._rebuild(); flow.screen.bracket.seek(5)
		"online_lobby": main.open_online()
		_: print("CAPTURE FAIL: unknown scenario"); quit(2); return
	for frame in range(8): await process_frame
	# Exercise the real native decoder, rather than capturing its still first frame.
	if scenario in ["versus","victory","defeat"]:
		await create_timer(.65).timeout
		var positions: Array = []
		for side in main.cinematic.video_overlay.sides:
			if side.video: positions.append(side.node.stream_position)
		print("VIDEO_PLAYBACK positions=",positions," bytes=",OS.get_static_memory_usage())
		if positions.is_empty() or (scenario == "versus" and positions.size() != 2): print("CAPTURE FAIL: missing decoder"); quit(1); return
		for p in positions:
			if p <= 0: print("CAPTURE FAIL: video did not advance"); quit(1); return
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image(); DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var success = not image.is_empty() and image.save_png(out) == OK
	print("CAPTURE ","PASS" if success else "FAIL"," scenario=",scenario," size=",root.size," out=",out)
	main.free()
	for frame in range(2): await process_frame
	quit(0 if success else 1)
