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
	await ui.sound._voice.finished
	ui._process(0)
	ok(ui.cinematic.active,"spotlight starts only after natural completion of full recording")
	ui.cinematic.clear(); ui.sound.stop_playback(); ui.queue_free()
	await process_frame; await process_frame
	print("RESULT_AUDIO_HANDOFF ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func game_win(ui) -> bool:
	return ui.game.status == 1 and ui.game.owners.count(2) == 0
