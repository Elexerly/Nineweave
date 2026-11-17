extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(): await process_frame; await process_frame
func run():
	var ui = Main.instantiate()
	ui.test_online_bypass = true
	ui.settings = Settings.new("user://online-audio-settings.cfg")
	ui.settings.values.sound = true; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new("user://online-audio-profile.cfg")
	ui.profile.choose("cryon","Tester")
	root.add_child(ui); ui.set_process(false); await frames()
	ui.sound.set_process(false)
	ui.page = "game"; ui.mode = "computer"; ui.human_mark = 2
	ui.thinking = true; ui.hint_busy = true; ui.sound.announce("ready")
	ui.open_online()
	ok(not ui.thinking and not ui.hint_busy,"entering lobby stops stale solo search")
	ok(ui.sound.voice_queue.is_empty() and ui.sound.voice_id.is_empty(),"lobby clears old gameplay audio")
	ok(ui.sound.enabled and ui.settings.values.sound,"waiting does not change user's sound preference")
	ui.online_state = "waiting"
	for seq in range(1,6):
		ui._receive_state(ui.game.serialize(),seq)
		ok(not ui.thinking,"waiting snapshot never schedules solo AI " + str(seq))
	ok(ui.sound.voice_queue.is_empty(),"waiting snapshots stay silent")
	ui.page = "game"; ui.mode = "online"; ui.remote_ready = true
	for extent in [Vector2(320,568),Vector2(390,844),Vector2(568,320),Vector2(844,390),Vector2(1024,768),Vector2(1800,1000)]:
		ui.set_view_size(extent); ui._rebuild(); await frames()
		ok(ui.controls.has("match_sound"),"quick sound toggle present " + str(extent))
		var r = ui.controls.match_sound.get_global_rect()
		ok(Rect2(Vector2.ZERO,extent).encloses(r),"sound toggle stays in viewport")
		ok(not r.intersects(ui.controls.home.get_global_rect()) and not r.intersects(ui.controls.settings.get_global_rect()),"sound does not overlap navigation")
		ok(not r.intersects(ui.chat_button_rect()),"sound does not overlap chat slot")
	ui.toggle_match_sound()
	ok(not ui.sound.enabled and not ui.settings.values.sound,"quick mute updates same setting as Options")
	ok(not ui.cinematic.video_overlay.sound_enabled,"quick mute reaches separated hero video audio")
	ok(ui.controls.match_sound.icon_kind == "sound_off","mute icon reflects state")
	var saved = Settings.new("user://online-audio-settings.cfg")
	ok(not saved.values.sound,"mute persists across reload")
	ui.toggle_match_sound()
	ok(ui.sound.enabled and ui.cinematic.video_overlay.sound_enabled,"unmute restores all audio without changing gains")
	ui.sound.announce("ready")
	ok(not ui.sound.voice_queue.is_empty(),"match-start audio still allowed after waiting")
	ui.queue_free(); await frames()
	print("NINEWEAVE_ONLINE_AUDIO ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
