extends SceneTree
const Overlay = preload("res://characters/hero_video_overlay.gd")
class Source extends RefCounted:
	func acquire(_id: String, kind: String) -> String: return "res://assets/hero_video/shard_jack/"+kind+".ogv"
	func release(_id: String,_kind: String): pass
	func has_audio(_id: String,_kind: String) -> bool: return true
var failed = 0
var checks = 0
func check(value: bool, label: String):
	checks += 1
	if not value: failed += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var overlay = Overlay.new(); overlay.source = Source.new(); root.add_child(overlay)
	overlay.decode_enabled = true
	for kind in ["versus","spotlight"]:
		overlay.begin(kind,"shard_jack","max_granite",1,Vector2(800,600),false)
		var sound: AudioStreamPlayer = overlay.sides[0].sound
		await create_timer(.15).timeout
		check(sound.playing,"separate soundtrack started "+kind)
		check(overlay.sides[0].node.is_playing(),"silent Theora video started "+kind)
		overlay.set_sound_enabled(false)
		check(sound.volume_db == -80 and sound.playing,"mute keeps clock running "+kind)
		overlay.set_sound_enabled(true)
		check(is_equal_approx(sound.volume_db,-8),"unmute retains gain "+kind)
		overlay.clear()
		check(not sound.playing and sound.stream == null,"skip immediately stops and releases soundtrack "+kind)
		await process_frame
		overlay.decode_enabled = false
		overlay.begin(kind,"shard_jack","max_granite",1,Vector2(800,600),false)
		sound = overlay.sides[0].sound; sound.play()
		overlay._side_finished(0,overlay._generation)
		check(not sound.playing,"video completion stops audio "+kind)
		overlay.clear(); overlay.decode_enabled = true
	overlay.queue_free(); await create_timer(.2).timeout
	print("NINEWEAVE_HERO_AUDIO_PLAYBACK ","PASS" if failed == 0 else "FAIL"," checks=",checks," failures=",failed)
	quit(failed)
