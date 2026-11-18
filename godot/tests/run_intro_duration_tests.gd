extends SceneTree
const Overlay = preload("res://characters/hero_video_overlay.gd")
class Source extends RefCounted:
	var missing = false
	func acquire(id: String, kind: String) -> String: return "" if missing else "res://assets/hero_video/"+id+"/"+kind+".ogv"
	func release(_id: String, _kind: String): pass
	func has_audio(_id: String, _kind: String) -> bool: return true
var checks = 0
var failures = 0
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ", label)
func _initialize(): run.call_deferred()
func run():
	var v = Overlay.new(); v.source = Source.new(); root.add_child(v)
	v.set_process(false); v.decode_enabled = false
	var ended = [0]; v.finished.connect(func(): ended[0] += 1)
	for completion in ["long", "one_short", "both_short", "missing"]:
		v.source.missing = completion == "missing"
		v.begin("versus","kellen_byte","shard_jack",1,Vector2(800,600),false)
		var generation = v._generation
		if completion in ["one_short", "both_short"]:
			v.sides[0].node.finished.emit()
			check(v.active and v.sides[0].node.visible and v.sides[0].done,"short local holds frame")
			check(not v._audible and v.sides[1].sound == null,"short local never promotes rival audio")
		if completion == "both_short": v.sides[1].node.finished.emit()
		v._process(5.99)
		check(v.active,"not before six seconds: "+completion)
		var before = ended[0]
		v._process(.01)
		check(not v.active and ended[0] == before+1,"ends at six seconds: "+completion)
		for side in v.sides:
			if side.video: check(side.node.paused,"long decoder paused at deadline")
			if side.sound != null: check(not side.sound.playing,"sound stops at deadline")
		v._side_finished(0,generation); v._process(20)
		check(ended[0] == before+1,"late decoder cannot double-finish")
		v.clear()
	v.source.missing = false
	v.begin("versus","nick","shard_jack",1,Vector2(800,600))
	v._process(v.minimum_lead)
	check(v._reveal_age == 0,"prelude excluded from six-second window")
	v._process(5.9); check(v.active,"full window after reveal")
	var old = v._generation; v.clear(); var before = ended[0]
	v._side_finished(0,old); v._process(20)
	check(ended[0] == before and not v.visible,"skip/navigation cancels timer and callback")
	for duration in [5.33,6.0,8.04]:
		var end = minf(duration,6.0)
		check(is_equal_approx(Overlay.soundtrack_tail_gain("nick","intro",end-.3,duration),1),"full before fade")
		check(is_equal_approx(Overlay.soundtrack_tail_gain("nick","intro",end-.15,duration),.5),"half fade")
		check(Overlay.soundtrack_tail_gain("nick","intro",end,duration) == 0,"silent at clip/window end")
	v.begin("spotlight","nick","shard_jack",1,Vector2(800,600),false)
	v._process(6.1); check(v.active,"victory has no six-second cutoff")
	v.sides[0].node.finished.emit()
	check(v.holds_completed_result(),"victory still holds completed frame")
	v.clear()
	# Exercise actual Theora completion and wall-clock cutoff, not just synthetic signals.
	v.decode_enabled = true; v.set_process(true)
	v.begin("versus","shard_jack","kellen_byte",1,Vector2(800,600),false)
	await create_timer(5.5).timeout
	check(v.active and v.sides[0].done and v.sides[0].node.visible,"real short clip holds final frame while longer rival continues")
	check(v.sides[1].node.is_playing(),"real longer rival still playing before deadline")
	await create_timer(.6).timeout
	check(not v.active and v.sides[1].node.paused and not v.sides[0].sound.playing,"real playback stops at shared deadline")
	v.clear(); v.queue_free(); await process_frame
	print("NINEWEAVE_INTRO_DURATION ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(failures)
