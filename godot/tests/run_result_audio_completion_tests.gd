extends SceneTree
const Sound = preload("res://fx/sound.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var s = Sound.new(); root.add_child(s); s.set_process(false)
	s.unlocked = true
	# Missing recordings use bounded generated audio, never an infinite hold.
	s.cache.ann_nineweave = s.stream_for("ann_nineweave","res://missing-recording.ogg")
	s.announce("nineweave")
	ok(s.result_announcement_pending(),"winning announcement blocks automatic handoff")
	s.advance_mix(.2)
	ok(s.result_announcement_pending(),"tail not skipped at initial board threshold")
	s.advance_mix(20)
	ok(not s.result_announcement_pending(),"missing resource fallback eventually completes")
	s.clear_announcer(); s.cache.erase("ann_nineweave"); s.announce("nineweave")
	s.advance_mix(3.99)
	ok(is_equal_approx(s._voice.volume_db,s._voice_base_db),"no attenuation before four seconds")
	s.advance_mix(.22)
	ok(s._voice.volume_db < s._voice_base_db and s.result_announcement_pending(),"midfade is quieter, tail remains protected")
	s.advance_mix(.3)
	ok(not s.result_announcement_pending(),"handoff releases at fade end, without playing remaining original tail")
	s.clear_announcer(); s.announce("defeat")
	ok(is_equal_approx(s._voice.volume_db,s._voice_base_db),"defeat unaffected by previous fade")
	# Actual playback takes precedence over estimated game-frame duration.
	s.clear_announcer(); s.announce("nineweave")
	s._voice.play()
	s.advance_mix(20)
	ok(s._voice.playing and s.result_announcement_pending(),"real player tail survives expired estimate")
	s._voice.stop(); s._voice.finished.emit()
	ok(not s.result_announcement_pending(),"actual finished signal releases hold")
	s.clear_announcer()
	s.cache.ann_nineweave = s.generate("unlock")
	s.announce("nineweave"); s._voice.play()
	await s._voice.finished
	ok(not s.result_announcement_pending(),"engine emits natural completion and releases gate")
	s.clear_announcer(); s.announce("nineweave"); s.announce("victory")
	s._voice.finished.emit()
	ok(s.result_announcement_pending(),"queued result line remains protected")
	s.advance_mix(.2)
	ok(s.voice_id == "victory","queued result drains after gap")
	s.clear_announcer()
	ok(not s.result_announcement_pending(),"skip or screen change cancels hold and queue")
	s.announce("nineweave"); s.volumes.announcer_volume = 0
	ok(not s.result_announcement_pending(),"zero announcer volume never blocks")
	s.volumes.announcer_volume = .9; s.enabled = false
	ok(not s.result_announcement_pending(),"master mute cancels")
	s.enabled = true; s.unlocked = false; s.announce("nineweave")
	ok(not s.result_announcement_pending(),"locked web audio cannot trap result")
	s.clear_announcer(); s.unlocked = true; s.announce("first_claim")
	ok(not s.result_announcement_pending(),"ordinary commentary does not block")
	s.clear_announcer(); s.announce("standoff")
	ok(s.result_announcement_pending(),"draw result follows same safe lifecycle")
	s.set_hero_video_audio(true)
	ok(not s.result_announcement_pending(),"cinematic ownership clears stale commentary")
	var main = FileAccess.get_file_as_string("res://main/main.gd")
	ok(main.contains("not _result_shown and not sound.result_announcement_pending()"),"automatic result path gates handoff")
	ok(main.contains("if skipped and not event is InputEventKey: _skip_guard_until"),"intentional cinematic skip keeps release guard")
	s.stop_playback(); s.queue_free()
	await process_frame
	await process_frame
	print("RESULT_AUDIO_COMPLETION ", checks," checks, ",failures," failures")
	quit(1 if failures else 0)
