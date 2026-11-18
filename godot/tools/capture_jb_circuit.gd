extends SceneTree
const Main = preload("res://main/main.tscn")
const Profile = preload("res://characters/profile.gd")
const Settings = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const Art = preload("res://characters/art.gd")
func _initialize(): run.call_deferred()
func run():
	var args = OS.get_cmdline_user_args()
	var scenario = args[0] if args.size() > 0 else "selection"
	var out = args[1] if args.size() > 1 else "user://jb.png"
	var main = Main.instantiate(); main.test_online_bypass = true
	main.settings = Settings.new("user://jb-capture-settings.cfg"); main.settings.values.sound = false
	main.settings.values.tutorial_completed = true
	main.settings.values.unlocked_heroes = ["nick","professor_gilt","jb_rocker"]
	main.profile = Profile.new("user://jb-capture-profile.cfg"); main.profile.choose(args[2] if args.size() > 2 else "jb_circuit","Weaver")
	main.account.store = DeviceStore.new("user://jb-capture-device.cfg")
	main.http_request_factory = func(): return Fake.new()
	main.account.api.request_factory = func(): return Fake.new()
	root.add_child(main); main.set_view_size(Vector2(root.size)); main.set_process(false)
	main.online_tournament.set_process(false); main._apply_preferences(); main.rival_character = "james_ii"
	if scenario == "title":
		main.page = "title"; main._rebuild()
	elif scenario == "expressions":
		main.visible = false
		for i in range(7):
			var key = ["neutral","smug","panic","doubletake","eyeroll","cheer","pout"][i]
			var a = Art.new(); a.hero_id = "jb_circuit"; a.bust = true; a.art_key = "head_"+key; a.frozen = true
			a.position = Vector2((i%4)*210+8,int(i/4)*245+12); a.size = Vector2(200,210); root.add_child(a)
			var label = Label.new(); label.text = key; label.position = a.position+Vector2(10,208); label.add_theme_font_size_override("font_size",22);root.add_child(label)
	elif scenario in ["selection","professor_unlocked"]:
		main.settings.values.unlocked_heroes = ["nick","professor_gilt","jb_rocker"]
		if scenario == "professor_unlocked": main.settings.values.unlocked_heroes = ["nick","professor_gilt"]
		main.page = "character_select"; main._rebuild()
		main.hero_select.focus_hero("professor_gilt" if scenario == "professor_unlocked" else main.profile.data.character_id)
		if scenario == "professor_unlocked": main.hero_select.set_page(main.hero_select.geo.pages-1)
	elif scenario in ["versus","versus_still"]:
		if scenario == "versus_still": main.cinematic.video_source.catalog = {}
		main.start_game("computer",1,true,true)
	else:
		main.start_game("computer",1,true,false); main.game.status = 1; main.cinematic.clear()
		if scenario == "victory_still": main.cinematic.video_source.catalog = {}
		main._show_spotlight()
	for i in range(10): await process_frame
	main.callout.callout = ""
	if scenario in ["versus","victory","versus_still","victory_still"]:
		await create_timer(2.0).timeout
	if scenario in ["versus","victory"]:
		var positions: Array = []
		for side in main.cinematic.video_overlay.sides:
			if side.video: positions.append(side.node.stream_position)
		print("JB_VIDEO_PLAYBACK ",scenario," positions=",positions)
		if positions.is_empty(): print("CAPTURE FAIL no video"); quit(1); return
		for value in positions:
			if value <= 0: print("CAPTURE FAIL video did not advance"); quit(1); return
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image(); DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var success = not image.is_empty() and image.save_png(out) == OK
	print("JB_CAPTURE ","PASS" if success else "FAIL"," ",scenario," ",root.size," ",out)
	main.queue_free(); await process_frame; quit(0 if success else 1)
