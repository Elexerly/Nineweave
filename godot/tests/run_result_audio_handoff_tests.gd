extends SceneTree
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
	ui.page = "game"; ui.overlay = ""; ui.mode = "local"; ui.game.status = 1
	ui.tutorial.active = false; ui.cinematic.clear()
	ui.board.start_win([],1)
	# Board animation completed long before the 6.8s recording.
	ui.board.win_fx.age = 100
	ui.sound.clear_announcer(); ui.sound.announce("nineweave")
	ui._process(0)
	ok(not ui.cinematic.active and not ui._result_shown,"result waits while announcement pending")
	ui.sound.clear_announcer()
	ui._process(0)
	ok(ui.cinematic.active,"normal spotlight handoff resumes after audio ends")
	ui.cinematic.clear(); ui.sound.stop_playback(); ui.queue_free()
	await process_frame; await process_frame
	print("RESULT_AUDIO_HANDOFF ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
