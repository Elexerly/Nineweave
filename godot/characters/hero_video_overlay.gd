extends Control
## Event-driven playback. The existing cinematic remains underneath and owns skip/results.
const Roster = preload("res://characters/roster.gd")
const Rig = preload("res://characters/art.gd")
const P = preload("res://ui/paint.gd")
const PORTRAIT = Vector2(540,720)
# Cold web caches need time to download both intros before either starts.
# Skip remains available, and unavailable media cannot block a match forever.
const INTRO_WAIT_SECONDS = 12.0
# Leave summing headroom for other game audio; never amplify source clips.
const VIDEO_GAIN_DB = -6.0
signal finished
signal audio_active(value: bool)
var source
var sound_enabled: bool = true
var decode_enabled: bool = DisplayServer.get_name() != "headless" # Headless tests drive finished signals.
var active: bool = false
var scene_kind: String = ""
var sides: Array = []
var _held: Array = []
var _audible: bool = false
var _chrome: Control
var _play_age: float = 0
var _generation: int = 0
var display_lane: Rect2 = Rect2()
var _waiting_for_intros: bool = false
var _wait_age: float = 0
var _intro_request: Array = []
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE; visible = false
func begin(kind: String, first: String, second: String, mark: int, extent: Vector2, allow_wait: bool = true) -> bool:
	clear()
	if source == null or not kind in ["versus","spotlight"]: return false
	var ids = [Roster.canonical_id(first),Roster.canonical_id(second)] if kind == "versus" else [Roster.canonical_id(first)]
	var clip_kind = "intro" if kind == "versus" else "victory"
	_waiting_for_intros = allow_wait and kind == "versus" and _intros_pending(ids)
	if _waiting_for_intros:
		source.prefetch_pair(ids[0],ids[1])
		_intro_request = [kind,first,second,mark]
	var paths: Array = []
	for id in ids:
		var path: String = "" if _waiting_for_intros else source.acquire(id,clip_kind)
		paths.append(path)
		if not path.is_empty(): _held.append([id,clip_kind])
	if _held.is_empty() and not _waiting_for_intros: return false
	if kind == "versus": display_lane = Rect2()
	scene_kind = kind; active = true; visible = true; size = extent
	for i in range(ids.size()):
		var side = {"id":ids[i],"kind":clip_kind,"video":not paths[i].is_empty(),"done":paths[i].is_empty(),"audio":false,"node":null,"frame":Rect2(),"mark":mark if i == 0 else 3-mark}
		if side.video:
			var player = VideoStreamPlayer.new()
			player.mouse_filter = Control.MOUSE_FILTER_IGNORE; player.expand = true
			# Master already exists; video must not go through Announcer or alter bus layout.
			player.bus = &"Master"
			# Use Godot's normal audio buffer for the audible lane, not the old
			# aggressive 100ms buffer shared by two competing soundtracks.
			player.buffering_msec = 500 if i == 0 else 100
			var stream = VideoStreamTheora.new(); stream.file = paths[i]
			player.stream = stream; add_child(player); side.node = player
			side.audio = source.has_audio(ids[i],clip_kind)
			player.finished.connect(_side_finished.bind(i,_generation))
		else:
			var art = Rig.new(); art.art_key = "versus" if kind == "versus" else "victory"; art.fit_height = true
			add_child(art); art.configure(ids[i],false); art.side = side.mark; art.set_clip("idle")
			side.node = art
		sides.append(side)
	_chrome = Control.new(); _chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.draw.connect(_draw_chrome); add_child(_chrome)
	_play_age = 0
	relayout(extent); set_sound_enabled(sound_enabled)
	for side in sides:
		if side.video and decode_enabled: side.node.play()
	return true
func _intros_pending(ids: Array) -> bool:
	if source == null or not source.has_method("streaming") or not source.streaming(): return false
	for id in ids:
		if source.has_clip(id,"intro") and not source.is_ready(id,"intro") and not source.cache.missing.has(id+"/intro"):
			return true
	return false
func relayout(extent: Vector2):
	size = extent
	for i in range(sides.size()):
		var lane = display_lane if display_lane.has_area() else Rect2(0,0,size.x,size.y)
		if scene_kind == "versus": lane = Rect2(size.x*i*.5+10,58,size.x*.5-20,maxf(1,size.y-156))
		var fit = minf(lane.size.x/PORTRAIT.x,lane.size.y/PORTRAIT.y)
		var frame = Rect2(lane.get_center()-PORTRAIT*fit*.5,PORTRAIT*fit)
		sides[i].frame = frame; sides[i].node.position = frame.position; sides[i].node.size = frame.size
	queue_redraw()
	if is_instance_valid(_chrome): _chrome.queue_redraw()
func set_sound_enabled(value: bool):
	sound_enabled = value
	var audible = false
	for i in range(sides.size()):
		var side = sides[i]
		if side.video:
			# The first lane is local on versus, or the featured winner on results.
			# Never promote opponent audio when the local clip ends or is absent.
			var enabled = i == 0 and side.audio and not side.done and sound_enabled
			side.node.volume = db_to_linear(VIDEO_GAIN_DB) if enabled else 0.0
			audible = audible or enabled
	_set_audio(active and audible)
func holds_completed_result() -> bool:
	return scene_kind == "spotlight" and visible and not active and sides.size() == 1 and sides[0].video and sides[0].done
func _set_audio(value: bool):
	if value == _audible: return
	_audible = value; audio_active.emit(value)
func _side_finished(index: int, generation: int):
	if generation != _generation or not active or index >= sides.size(): return
	sides[index].done = true
	set_sound_enabled(sound_enabled)
	for side in sides:
		if side.video and not side.done: return
	active = false; _set_audio(false); finished.emit()
func clear():
	_generation += 1
	_waiting_for_intros = false; _wait_age = 0; _intro_request.clear()
	active = false; visible = false; _set_audio(false)
	for side in sides:
		if side.video: side.node.stop(); side.node.stream = null
		side.node.visible = false; side.node.queue_free()
	sides.clear()
	if source != null:
		for clip in _held: source.release(clip[0],clip[1])
	_held.clear(); scene_kind = ""
	if is_instance_valid(_chrome): _chrome.visible = false; _chrome.queue_free()
	_chrome = null
func _process(delta):
	if not active: return
	if _waiting_for_intros:
		_wait_age += delta
		var ids = [Roster.canonical_id(_intro_request[1]),Roster.canonical_id(_intro_request[2])]
		if _intros_pending(ids) and _wait_age < INTRO_WAIT_SECONDS: return
		var request = _intro_request.duplicate()
		# Restart atomically so both ready players begin on the same frame.
		# A timeout may use one ready clip plus the other hero's still art.
		if not begin(request[0],request[1],request[2],request[3],size,false):
			finished.emit()
		return
	if not decode_enabled: return
	_play_age += delta
	# A decoder/open failure must never strand a modal screen. Normal completion
	# uses finished; this only catches a player that stopped without emitting it.
	if _play_age < .5: return
	for i in range(sides.size()):
		if sides[i].video and not sides[i].done and not sides[i].node.is_playing():
			# Keep the still portrait visible if a decoder cannot open this side.
			var side = sides[i]; side.node.stop(); side.node.stream = null; side.node.queue_free()
			var art = Rig.new(); art.art_key = "versus" if scene_kind == "versus" else "victory"; art.fit_height = true
			add_child(art); art.configure(side.id,false); art.side = side.mark; side.node = art
			side.video = false; _side_finished(i,_generation)
			relayout(size)
			if not active: return
func _exit_tree(): clear()
func _draw():
	if not visible: return
	if scene_kind == "versus": draw_rect(Rect2(Vector2.ZERO,size),Color("050c1a"))
func _draw_chrome():
	if not visible: return
	if scene_kind == "versus":
		P.text(_chrome,"NINEWEAVE  /  HERO CLASH",Rect2(12,12,size.x-24,32),P.fit_size("NINEWEAVE  /  HERO CLASH",size.x-24,24),P.GOLD)
		for side in sides:
			var frame: Rect2 = side.frame
			P.outline(_chrome,frame.grow(3),P.GOLD,2)
			var caption = Roster.get_hero(side.id).name.to_upper()
			var box = Rect2(frame.position.x,frame.end.y+10,frame.size.x,44)
			var color = P.mark_color(side.mark)
			var fs = P.fit_size(caption,box.size.x,20)
			var at = caption.rfind(" ")
			if fs < 14 and at > 0:
				var first = caption.substr(0,at); var second = caption.substr(at+1)
				fs = mini(P.fit_size(first,box.size.x,16),P.fit_size(second,box.size.x,16))
				P.text(_chrome,first,Rect2(box.position,Vector2(box.size.x,box.size.y*.5)),fs,color)
				P.text(_chrome,second,Rect2(box.position+Vector2(0,box.size.y*.5),Vector2(box.size.x,box.size.y*.5)),fs,color)
			else:
				P.text(_chrome,caption,box,fs,color)
		_chrome.draw_line(Vector2(size.x*.5,58),Vector2(size.x*.5,size.y-98),Color("776239"),1,true)
		P.text(_chrome,"VS",Rect2(size.x*.5-25,size.y*.5-22,50,44),24,P.GOLD)
	if scene_kind != "versus": return
	_chrome.draw_rect(Rect2(size.x*.5-64,size.y-38,128,26),Color(.02,.04,.09,.8))
	P.text(_chrome,"LOADING INTROS · TAP TO SKIP" if _waiting_for_intros else "TAP TO SKIP",Rect2(12,size.y-38,size.x-24,26),14,P.MUTED)
