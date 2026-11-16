extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames():
	await process_frame; await process_frame
func run():
	var ui = Main.instantiate(); ui.test_online_bypass = true
	var prefix = "user://versus-flow-"+str(Time.get_ticks_usec())
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("shard_jack","Weaver")
	ui.http_request_factory = func(): return Fake.new()
	ui.account.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	var c = ui.cinematic; var v = c.video_overlay; v.set_process(false)
	ui.rival_character = "max_granite"; ui.start_game("computer",1,true,true)
	ok(c.active and ui.board.frozen and v._waiting_for_intros,"cached match starts in single anticipation screen")
	ok(not v.sides[0].node.visible and not v.sides[1].node.visible and not v._audible,"no portraits/audio before reveal")
	v._process(v.INTRO_LEAD_SECONDS-.01)
	ok(v._waiting_for_intros,"cached lead-in is brief but not skipped")
	v._process(.02)
	ok(not v._waiting_for_intros and v.sides[0].video and v.sides[1].video and v._reveal_age == 0,"one atomic reveal starts both cached intros")
	ok(v.sides[0].node.visible and v.sides[1].node.visible,"split videos visible together")
	v._process(v.FLASH_SECONDS+.01)
	ok(v._reveal_age > v.FLASH_SECONDS,"single flash expires")
	v._process(2)
	ok(not v._waiting_for_intros and v._reveal_age > 2,"no second anticipation or flash")
	v.sides[0].node.finished.emit()
	ok(c.active and ui.board.frozen,"shorter video never cuts off partner")
	v.sides[1].node.finished.emit()
	ok(not c.active and not ui.board.frozen,"both complete straight into game")
	# Dispatch genuine input events through the SceneTree, not a direct skip call.
	ui._begin_versus(); c.advance(.7)
	var tap = InputEventScreenTouch.new(); tap.pressed = true; tap.position = Vector2(195,400)
	Input.parse_input_event(tap); await frames()
	ok(not c.active and not ui.board.frozen and not v._waiting_for_intros,"touch skips preloader through real input dispatch")
	ok(ui._skip_guard_until > Time.get_ticks_msec(),"skip tap cannot leak onto board")
	v._process(20); ok(not v.visible,"late load cannot reopen skipped preloader")
	ui._begin_versus(); c.advance(.7)
	var key = InputEventKey.new(); key.pressed = true; key.keycode = KEY_ESCAPE
	Input.parse_input_event(key); await frames()
	ok(not c.active and not v.visible,"keyboard skips repeated preload")
	ui._begin_versus(); ui.go_home(); v._process(20)
	ok(ui.page == "title" and not c.active and not v.visible,"navigation cancels deferred reveal")
	for size in [Vector2(390,844),Vector2(844,390),Vector2(1366,1024)]:
		ui.set_view_size(size); ui.start_game("computer",1,true,true); v._process(v.INTRO_LEAD_SECONDS)
		ok(v.sides[0].frame.end.x < v.sides[1].frame.position.x,"bolt divider gap at "+str(size))
		for side in v.sides: ok(Rect2(Vector2.ZERO,size).encloses(side.frame),"video in viewport")
		c.clear()
	ui.settings.values.sound = true; ui._apply_preferences(); ui.sound.unlocked = true; ui.sound.set_process(false)
	ui._begin_versus()
	var speech = ui.sound._voice.stream
	ok(speech != null and speech.get_length() > 2 and speech.get_length() < 2.2,"owner recording loaded with measured duration")
	ok(ui.sound.voice_id == "versus_prelude" and ui.sound._voice.bus == &"Announcer" and ui.sound._voice.volume_db == -3,"speech respects Announcer bus with headroom")
	ok(ui.sound.duck_db <= -4.5 and not ui.sound.hero_video_audio,"speech ducks music before videos")
	ok(v.minimum_lead >= speech.get_length()+.119,"lead covers full speech plus safety")
	v._process(speech.get_length())
	ok(v._waiting_for_intros and not v._audible,"video cannot overlap spoken line")
	v._process(.13)
	ok(not v._waiting_for_intros and ui.sound.voice_id != "versus_prelude" and ui.sound._announcer_left == 0,"reveal stops prelude before intro audio")
	ok(ui.sound.hero_video_audio and ui.sound.duck_db == -12,"normal intro duck preserved")
	ok(ui.sound._players[0].volume_db == -9,"clash gain is reduced independent of duck")
	ui._begin_versus()
	var speech_pending = [true]
	v.prelude_active = func(): return speech_pending[0]
	v._process(v.minimum_lead+.1)
	ok(v._waiting_for_intros,"actual playing signal gates reveal beyond nominal duration")
	speech_pending[0] = false; v._process(.01)
	ok(not v._waiting_for_intros,"actual completion releases reveal")
	ui._begin_versus(); speech_pending[0] = true
	v._process(v.minimum_lead+v.PRELUDE_GRACE_SECONDS+.1)
	ok(not v._waiting_for_intros and ui.sound.voice_id != "versus_prelude","stalled audio watchdog stops speech and cannot hang match")
	v.prelude_active = ui.sound.versus_prelude_playing
	ui._begin_versus(); c.advance(.7); Input.parse_input_event(tap); await frames()
	ok(ui.sound.voice_id != "versus_prelude" and ui.sound._voice.stream != speech,"real skip stops unfinished speech")
	ui._begin_versus(); ui.go_home()
	ok(ui.sound.voice_id != "versus_prelude","navigation stops unfinished speech")
	ui.sound.volumes.announcer_volume = 0; ui._begin_versus()
	ok(ui.sound.voice_id != "versus_prelude" and v.minimum_lead == v.INTRO_LEAD_SECONDS,"muted announcer keeps brief cached lead")
	ui.sound.volumes.announcer_volume = .9; ui.settings.values.sound = false; ui._apply_preferences(); ui._begin_versus()
	ok(ui.sound.voice_id != "versus_prelude" and v.minimum_lead == v.INTRO_LEAD_SECONDS,"Sound off never starts recording")
	ui.settings.values.sound = true; ui._apply_preferences()
	var catalog = ui.hero_video.catalog; ui.hero_video.catalog = {}
	ui._begin_versus(); v._process(v.minimum_lead)
	ok(v._still_only and not ui.sound.hero_video_audio and ui.sound._players[0].volume_db == -9,"still fallback clash has explicit low gain without video duck")
	ui.hero_video.catalog = catalog
	ui.cinematic.reduced_motion = true; ui._begin_versus()
	ok(not v.visible and ui.sound.voice_id != "versus_prelude","reduced motion uses existing no-flash fallback without delayed speech")
	ui.go_home(); ui.queue_free(); await frames()
	print("NINEWEAVE_VERSUS_FLOW ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
