extends SceneTree
const Overlay = preload("res://characters/hero_video_overlay.gd")
class Source extends RefCounted:
	func acquire(id: String, kind: String) -> String: return "res://assets/hero_video/"+id+"/"+kind+".ogv"
	func release(_id: String,_kind: String): pass
	func has_audio(_id: String,_kind: String) -> bool: return true
var failed = 0
var checks = 0
func check(value: bool, label: String):
	checks += 1
	if not value: failed += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	check(Overlay.soundtrack_tail_position(5.9,4.9) == 5.9,"lagging web audio clock cannot postpone fade")
	check(Overlay.soundtrack_tail_position(5.8,5.9) == 5.9,"ahead audio clock still fades")
	check(Overlay.soundtrack_tail_position(-1,0) == 0,"tail clock nonnegative")
	for kind in ["intro","victory"]:
		var end = Overlay.BETH_VIDEO_SECONDS
		for elapsed in [0.0,end-.3]:
			check(is_equal_approx(Overlay.soundtrack_tail_gain("madame_solstice",kind,elapsed,end),1.0),"Beth full gain before fade "+kind)
		check(is_equal_approx(Overlay.soundtrack_tail_gain("madame_solstice",kind,end-.15,end),.5),"Beth half amplitude at fade midpoint "+kind)
		var lagging_mid = Overlay.soundtrack_tail_position(end-.15,end-1.15)
		check(is_equal_approx(Overlay.soundtrack_tail_gain("madame_solstice",kind,lagging_mid,end),.5),"web one-second lag still fades at midpoint "+kind)
		var lagging_end = Overlay.soundtrack_tail_position(end,end-1)
		check(Overlay.soundtrack_tail_gain("madame_solstice",kind,lagging_end,end) == 0,"web one-second lag silent at video end "+kind)
		check(Overlay.soundtrack_tail_gain("madame_solstice",kind,end,end) == 0,"Beth silent at end "+kind)
		check(Overlay.soundtrack_tail_gain("madame_solstice",kind,end+1,end) == 0,"Beth silent after end "+kind)
		for id in ["ryan_blaze","shard_jack","aurelia"]:
			check(Overlay.soundtrack_tail_gain(id,kind,end,end) == 1,"other heroes unchanged "+id+kind)
	var overlay = Overlay.new(); overlay.source = Source.new(); root.add_child(overlay)
	overlay.decode_enabled = true
	for id in ["ryan_blaze","shard_jack","madame_solstice"]:
		var rival = "shard_jack" if id == "ryan_blaze" else "ryan_blaze"
		for kind in ["versus","spotlight"]:
			overlay.begin(kind,id,rival,1,Vector2(800,600),false)
			var label = id+"/"+kind
			var sound: AudioStreamPlayer = overlay.sides[0].sound
			await create_timer(.15).timeout
			check(sound.playing,"separate soundtrack started "+label)
			check(overlay.sides[0].node.is_playing(),"silent Theora video started "+label)
			check(overlay.sides[0].node.volume == 0 and overlay.sides[0].node.audio_track == -1,"embedded track silent "+label)
			if kind == "versus":
				check(overlay.sides[1].sound == null and overlay.sides[1].node.volume == 0 and overlay.sides[1].node.audio_track == -1,"opponent has no soundtrack "+label)
			overlay.set_sound_enabled(false)
			check(sound.volume_db == -80 and sound.playing,"mute keeps clock running "+label)
			overlay.set_sound_enabled(true)
			check(is_equal_approx(sound.volume_db,-8),"unmute retains gain "+label)
			if id == "madame_solstice":
				var end = overlay._soundtrack_end(overlay.sides[0])
				check(end > 6.0 and end <= Overlay.BETH_VIDEO_SECONDS+.001,"Beth end bounded by video "+kind)
				sound.seek(end-.15)
				await create_timer(.025).timeout
				overlay.set_sound_enabled(true)
				check(sound.volume_db < -10,"Beth tail ramps down "+kind)
				overlay.set_sound_enabled(false)
				check(sound.volume_db == -80,"Beth mute overrides envelope "+kind)
				overlay.set_sound_enabled(true)
				check(sound.volume_db < -10 and sound.volume_db > -80,"Beth unmute resumes faded level "+kind)
			overlay.clear()
			check(not sound.playing and sound.stream == null,"skip immediately stops and releases soundtrack "+label)
			await process_frame
			overlay.decode_enabled = false
			overlay.begin(kind,id,rival,1,Vector2(800,600),false)
			sound = overlay.sides[0].sound; sound.play()
			overlay._side_finished(0,overlay._generation)
			check(not sound.playing and not overlay._audible,"video completion stops audio and duck "+label)
			if kind == "versus":
				check(overlay.sides[1].sound == null and overlay.sides[1].node.volume == 0,"no opponent promotion "+label)
			overlay.clear(); overlay.decode_enabled = true
	overlay.begin("spotlight","ryan_blaze","shard_jack",1,Vector2(800,600),false)
	check(is_equal_approx(overlay.sides[0].sound.volume_db,-8),"Beth fade does not leak to next Ryan clip")
	overlay.clear()
	overlay.queue_free(); await create_timer(.2).timeout
	print("NINEWEAVE_HERO_AUDIO_PLAYBACK ","PASS" if failed == 0 else "FAIL"," checks=",checks," failures=",failed)
	quit(failed)
