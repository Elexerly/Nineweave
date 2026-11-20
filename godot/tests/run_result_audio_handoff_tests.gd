extends SceneTree
const F = preload("res://tests/fixtures.gd")
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var ui = Main.instantiate()
	ui.test_online_bypass = true
	ui.settings = Settings.new("user://win-audio-settings.cfg")
	ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new("user://win-audio-profile.cfg")
	ui.profile.choose("cryon","Tester")
	root.add_child(ui); ui.set_process(false); await process_frame
	ui.sound.set_process(false); ui.sound.unlocked = true
	var reveals: Array[String] = []
	ui.sound.result_victory_started.connect(func(): reveals.append(ui.cinematic.kind))
	var started: Array[String] = []
	ui.sound.voice_started.connect(func(id): started.append(id))
	for mode in ["computer","local","online"]:
		ui.debug_load_position(F.big_tactic(1).serialize(),mode)
		ui.sound.announce("ready")
		started.clear()
		if mode == "online": ui._receive_move(2,2,1)
		else: ui._apply_move(2,2)
		ok(game_win(ui) and started == ["nineweave"],mode+" clean sweep starts branded speech, not stale Ready or Clean Sweep")
		ok(ui.sound._voice.stream is AudioStreamOggVorbis and absf(ui.sound._voice.stream.get_length()-6.8) < .08,mode+" selects full imported recording")
		ok(ui.sound.result_announcement_pending(),mode+" keeps result audio protected")
		ok(ui.sound.voice_queue.is_empty(),mode+" results not delayed by a second victory voice")
	ui.debug_load_position(F.big_tactic(2).serialize(),"computer")
	started.clear(); ui._apply_move(2,2)
	ok(started == ["defeat"],"AI victory gives the player the defeat call only")
	var final = F.big_tactic(1); final.play(2,2)
	ui.debug_load_position(F.big_tactic(1).serialize(),"online")
	ui.online_sequence = 0
	started.clear(); ui._receive_state(final.serialize(),1); ui._receive_state(final.serialize(),1)
	ui._receive_state(final.serialize(),2); ui._online_room_update({"status":"finished","result":{"winner":1}})
	ok(started == ["nineweave"],"terminal snapshot starts speech once even with later snapshot/room updates")
	ui.debug_load_position(F.big_tactic(1).serialize(),"online")
	started.clear(); ui._online_room_update({"status":"finished","result":{"winner":1}})
	ui._online_room_update({"status":"finished","result":{"winner":1}})
	ok(started == ["nineweave"],"authoritative forfeit result announces once")
	ui.debug_load_position(F.big_tactic(1).serialize(),"local")
	ui.profile.choose("shard_jack","Tester")
	ui.sound.set_hero_video_audio(true)
	started.clear(); ui._apply_move(2,2)
	ok(started.is_empty() and ui._pending_result_voice,"ongoing intro defers rather than drops result voice")
	ui.sound.set_hero_video_audio(false)
	ui.board.win_fx.age = 100
	ui._process(0)
	ok(started == ["nineweave"] and not ui.cinematic.active,"ending intro lets result voice start before cinema")
	var tap = InputEventScreenTouch.new(); tap.position = Vector2(200,250); tap.pressed = true
	root.push_input(tap,true)
	tap = InputEventScreenTouch.new(); tap.position = Vector2(200,250); tap.pressed = false
	root.push_input(tap,true)
	ok(ui.sound.result_announcement_pending(),"ordinary tap/release cannot cancel the result recording")
	ui.sound._voice.play()
	ui.sound.advance_mix(100)
	ui._process(0)
	ok(ui.sound._voice.playing and not ui.cinematic.active,"real recording remains playing after animation and estimate expire")
	var start := Time.get_ticks_msec()
	var saw_fade := false
	while ui.sound.result_announcement_pending() and Time.get_ticks_msec()-start < 6000:
		await process_frame
		ui.sound.advance_mix(0)
		if ui.sound._voice.playing and ui.sound._voice.volume_db < ui.sound._voice_base_db-.5: saw_fade = true
	var seconds := float(Time.get_ticks_msec()-start)/1000.0
	ok(saw_fade and ui.sound._brand_elapsed >= 4.45 and ui.sound._brand_elapsed < 4.57 and not ui.sound._voice.playing,"live recording fades audibly to silence around 4.45s (measured %.3fs)" % seconds)
	print("RESULT_AUDIO_FADE playback_seconds=",ui.sound._brand_elapsed," wall_seconds=",seconds)
	ui._process(0)
	ok(ui.cinematic.active,"next ready board frame immediately hands off to results")
	ok(reveals == ["spotlight"] and ui.sound.result_victory_playing(),"spoken Victory starts exactly on existing result card reveal")
	ok(ui.cinematic.video_playing() and ui.cinematic.video_overlay.victory_voice_ducked,"hero video starts with the card; only soundtrack is ducked")
	var video_audio = ui.cinematic.video_overlay.sides[0].sound
	ok(video_audio != null and video_audio.volume_db < -15.0,"competing hero soundtrack is quieter during the spoken clip")
	ui.sound.clear_announcer()
	ok(ui.sound.result_victory_playing(),"legacy queue clear cannot cut off the separate clip")
	ui._process(.25); ui._process(.25)
	ok(reveals.size() == 1,"subsequent result frames do not repeat Victory")
	var voice_length: float = ui.sound._result_victory.stream.get_length()
	ok(ui.sound._result_victory.stream is AudioStreamOggVorbis,"full existing spoken recording is used")
	ui.sound._result_victory.play()
	ui.sound.advance_mix(100)
	ok(ui.sound.result_victory_playing(),"result speech follows real completion, not frame estimates")
	await ui.sound._result_victory.finished
	ok(not ui.sound.result_victory_playing(),"separate spoken clip plays through natural completion")
	ui._process(0)
	ok(not ui.cinematic.video_overlay.victory_voice_ducked and video_audio.volume_db > -15.0,"hero soundtrack restored after word ends")
	print("VICTORY_REVEAL clip_seconds=",voice_length)
	ui.cinematic.clear(); ui.sound.stop_playback()
	ui.debug_load_position(F.big_tactic(1).serialize(),"computer"); ui.sound.enabled = false
	ui._apply_move(2,2); ui.board.win_fx.age = 100; ui._process(0)
	ok(reveals.size() == 1 and not ui.sound.result_victory_playing(),"mute suppresses dedicated victory cue")
	ui.cinematic.clear(); ui.sound.enabled = true
	ui.debug_load_position(F.big_tactic(1).serialize(),"computer"); ui._apply_move(2,2)
	ui.sound.advance_mix(5); ui.board.win_fx.age = 100; ui._process(0)
	ui.cinematic.age = 1.0
	var skip := InputEventKey.new(); skip.keycode = KEY_ESCAPE; skip.pressed = true
	root.push_input(skip,true)
	ok(reveals.size() == 2 and not ui.sound.result_victory_playing() and not ui.cinematic.active,"explicit result skip stops dedicated word and keeps result card")
	ui.cinematic.clear(); ui.sound.stop_playback()
	var initial_page: String = ui.page
	ui._show_startup_card()
	var startup = ui.startup_card
	ok(startup.active and startup.THANK_YOU == "Thanks for playing Lexerly!" and startup.SIGNATURE == "Patrick Booth","startup thanks players and uses personal signature")
	for view in [Vector2(320,568),Vector2(390,844),Vector2(867,553),Vector2(1366,1024)]:
		var rect: Rect2 = startup.card_rect(view)
		ok(Rect2(Vector2.ZERO,view).encloses(rect) and rect.encloses(startup.art_rect(rect)) and rect.get_center() == view*.5,"startup centered and safe for "+str(view))
	var seam := Rect2(412,0,43,553)
	ok(not startup.card_rect(Vector2(867,553),seam).intersects(seam),"startup card stays clear of a real fold hinge")
	ok(startup.ink_alpha(0) == 0 and startup.ink_alpha(.5) == 1 and startup.ink_alpha(3.7) < 1,"startup fades gently at both ends")
	startup._process(3.79)
	ok(startup.active,"startup card remains before timeout")
	startup._process(.02)
	ui._show_startup_card()
	ok(not startup.active and not startup.visible and ui.startup_card == startup and ui.page == initial_page,"startup auto-dismisses once and preserves existing route")
	startup.queue_free()
	await process_frame
	ui._show_startup_card()
	startup = ui.startup_card
	var dismiss := InputEventScreenTouch.new()
	dismiss.position = Vector2(90,120); dismiss.pressed = true
	root.push_input(dismiss,true)
	ok(startup.active,"press alone does not leak past cold-start card")
	dismiss = InputEventScreenTouch.new()
	dismiss.position = Vector2(90,120); dismiss.pressed = false
	root.push_input(dismiss,true)
	ok(not startup.active and ui.page == initial_page,"release dismisses welcome without acting on the underlying screen")

	ui.cinematic.clear(); ui.sound.stop_playback(); ui.queue_free()
	await process_frame; await process_frame
	print("RESULT_AUDIO_HANDOFF ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func game_win(ui) -> bool:
	return ui.game.status == 1 and ui.game.owners.count(2) == 0
