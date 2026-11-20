extends Node
## Owner recordings first, cached PCM synthesis as a missing-resource fallback.
## Fixed pool + cached mono streams. Five fixed pan sends avoid regenerating PCM.
const Announcer = preload("res://fx/announcer.gd")
const RATE = 22050
const VERSUS_PRELUDE_PATH = "res://assets/audio/announcer/two_have_stepped_forward.ogg"
const MOTIFS = [[0,7,12,14,7,12],[0,4,7,12,9,12],[12,7,3,10,5,0],[0,0,7,5,7,12],[0,3,8,7,10,15],[0,5,9,12,7,5],[0,9,7,14,12,19],[12,11,7,4,7,0],[0,2,7,5,9,7],[0,7,14,12,16,24],[0,4,1,7,3,12],[12,7,2,9,5,0]]
const ROOTS = [0,1,2,3,4,5,6,7,8,9,10,11]
const REAL_SFX = {"claim_x":"claim_crystal_shatter","claim_o":"claim_gold_clang","claim":"claim_crystal_shatter","victory":"victory_fanfare","defeat":"defeat_sting","route":"board_whoosh_chime","ui":"button_tick","invalid":"invalid_thunk"}
const VOICES = ["ready","weave","first_claim","double_lock","triple_weave","match_point","turnaround","shutout","nineweave","clean_sweep","standoff","victory","defeat"]
signal voice_started(id: String)
signal result_victory_started
const VOICE_GAP = .1
const BRAND_FADE_START := 4.0
const BRAND_FADE_END := 4.45
## Pending lines beyond this are stale (fast claims); the oldest non-result line is dropped.
const VOICE_QUEUE_MAX = 3
const RESULT_VOICES = ["victory","defeat","nineweave","clean_sweep","standoff"]
const MIX = [[&"SFX","sfx_volume"],[&"Announcer","announcer_volume"],[&"Music","music_volume"]]
const CUES = {"unlock":.025,"place_x":.085,"place_o":.1,"invalid":.13,"route":.36,"ui":.075,"claim":1.05,"victory":2.65,"defeat":1.15,"draw":.95}
var enabled: bool = true:
	set(value):
		enabled = value
		if not value: stop_playback()
var unlocked: bool = false
var web_unlock: bool = false
## Silent unlock plays issued inside gestures: first press and first release (iOS
## Safari only treats touchend/click as an audio-activating gesture).
var unlock_plays: int = 0
var _release_unlocked: bool = false
var volumes: Dictionary = {"sfx_volume":.85,"announcer_volume":.9,"music_volume":.45}
var cache: Dictionary = {}
var duck_db: float = 0.0
var hero_video_audio: bool = false
func set_hero_video_audio(value: bool):
	if hero_video_audio == value: return
	hero_video_audio = value
	if value:
		# Cinematic dialogue replaces overlapping result/versus commentary. Do not
		# replay stale lines when the clip ends, and duck before its first sample.
		clear_announcer()
		duck_db = -12.0
		_apply_mix()
var _announcer_left: float = 0.0
var _brand_elapsed := 0.0
var _voice_base_db := 0.0
var _players: Array = []
var _voice: AudioStreamPlayer
var _result_victory: AudioStreamPlayer
var _result_victory_left := 0.0
var _unlock_player: AudioStreamPlayer
var voice_queue: Array = []
var voice_id: String = ""
var _gap_left: float = 0
var _warm: Array = []
var _job: Dictionary = {}
var generation_us: int = 0
func _ready():
	ensure_buses()
	for i in range(10):
		var p = AudioStreamPlayer.new(); add_child(p); _players.append(p)
	_voice = AudioStreamPlayer.new(); _voice.bus = "Announcer"; add_child(_voice)
	_voice.finished.connect(_voice_finished)
	_result_victory = AudioStreamPlayer.new(); _result_victory.bus = "Announcer"; add_child(_result_victory)
	_result_victory.finished.connect(stop_result_victory)
	_unlock_player = AudioStreamPlayer.new(); _unlock_player.volume_db = -80; add_child(_unlock_player)
	cache.unlock = generate("unlock")
	_warm = ["ui","place_x","place_o","invalid","route","claim","victory","defeat","draw"]
	for id in VOICES: _warm.append("ann_"+id)
	for id in REAL_SFX: _warm.append(id)
## Buses normally come from res://default_bus_layout.tres. Runtime creation is only a
## fallback, and it must NOT use AudioServer.add_bus: on Web (sample playback) Godot
## 4.7's JS mirror (GodotAudio.Bus.addAt(-1)) reorders its bus array, so later
## set_bus_send() calls wire Master into a loop that never reaches ctx.destination and
## every sound is silent. Growing bus_count appends in the same order on both sides.
func ensure_buses():
	for bus in ["SFX","Music","Announcer"]:
		if AudioServer.get_bus_index(bus) < 0:
			var index = _append_bus()
			AudioServer.set_bus_name(index,bus); AudioServer.set_bus_send(index,"Master")
	for i in range(5):
		var bus = "CrystalPan"+str(i)
		if AudioServer.get_bus_index(bus) < 0:
			var index = _append_bus()
			AudioServer.set_bus_name(index,bus); AudioServer.set_bus_send(index,"SFX")
			var pan = AudioEffectPanner.new(); pan.pan = (i-2)*.35
			AudioServer.add_bus_effect(index,pan)
	_apply_mix()
static func _append_bus() -> int:
	AudioServer.bus_count = AudioServer.bus_count+1
	return AudioServer.bus_count-1
## Stop stale gameplay on a screen change without changing the saved mute setting.
func stop_playback():
	for p in _players: p.stop()
	if is_instance_valid(_voice): _voice.stop()
	stop_result_victory()
	clear_announcer()
func configure(values: Dictionary):
	enabled = bool(values.get("sound",true))
	for key in volumes: volumes[key] = clampf(float(values.get(key,volumes[key])),0,1)
	_apply_mix()
func _apply_mix():
	for pair in MIX:
		var index = AudioServer.get_bus_index(pair[0])
		if index >= 0:
			var gain = float(volumes[pair[1]])
			AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.00001,gain))+(duck_db if pair[0] != &"Announcer" else 0.0))
func _input(event):
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		if event.pressed: unlock()
		elif unlocked and not _release_unlocked:
			_release_unlocked = true; _silent_play()
func unlock():
	if unlocked: return
	unlocked = true; web_unlock = OS.has_feature("web")
	# This playback deliberately runs INSIDE the first input callback. Godot's web
	# audio driver resumes its AudioContext here; no pre-gesture play is attempted.
	_silent_play()
	_drain_voice()
func _silent_play():
	unlock_plays += 1
	_unlock_player.stream = cache.unlock
	if DisplayServer.get_name() != "headless": _unlock_player.play()
func _process(delta):
	advance_mix(delta)
	# Incremental prewarm keeps synthesis below a 2ms frame budget. Requested cues
	# can finish synchronously; commonly used cues are warmed before the first move.
	var start = Time.get_ticks_usec()
	while Time.get_ticks_usec()-start < 1800:
		if _job.is_empty():
			if _warm.is_empty(): break
			var kind = str(_warm.pop_front())
			if cache.has(kind): continue
			var real = load_real(real_path(kind))
			if real != null: cache[kind] = real; continue
			_job = _begin(kind)
		_step(_job,128)
		if _job.i >= _job.count:
			cache[_job.kind] = _finish(_job); _job = {}
	generation_us += Time.get_ticks_usec()-start
func advance_mix(delta: float):
	if voice_id == "nineweave": _advance_brand_fade(delta)
	if _result_victory_left > 0 and (not enabled or float(volumes.announcer_volume) <= 0): stop_result_victory()
	elif _result_victory_left > 0 and not _result_victory.playing: _result_victory_left = maxf(0,_result_victory_left-delta)
	var remaining = delta
	if _announcer_left > 0:
		remaining = maxf(0,delta-_announcer_left)
		_announcer_left = maxf(0,_announcer_left-delta)
		if versus_prelude_playing() or _result_voice_playing(): _announcer_left = maxf(.001,_announcer_left)
		if _announcer_left == 0: voice_id = ""; _gap_left = VOICE_GAP
	if _announcer_left == 0: _gap_left = maxf(0,_gap_left-remaining); _drain_voice()
	# Lines waiting for the first gesture are silent; they must not hold music/SFX ducked.
	var target = -12.0 if enabled and hero_video_audio else (-4.5 if _announcer_left > 0 or (unlocked and enabled and not voice_queue.is_empty()) else 0.0)
	duck_db = lerpf(duck_db,target,1.0-exp(-delta/(.035 if target < duck_db else .16)))
	if absf(duck_db-target) < .01: duck_db = target
	_apply_mix()
func cue(kind: String, pan: float = 0.0, gain_db: float = -3.0):
	if not enabled or not unlocked: return
	kind = {"move":"place_x","win":"victory"}.get(kind,kind)
	var stream = stream_for(kind)
	if stream == null: return
	var player = _players[0]
	for p in _players:
		if not p.playing: player = p; break
	player.stop(); player.stream = stream
	player.bus = "CrystalPan"+str(clampi(roundi(pan/.35)+2,0,4)); player.volume_db = minf(gain_db,-3.0)
	if DisplayServer.get_name() != "headless": player.play()
func play_versus_prelude() -> float:
	clear_announcer()
	if not enabled or not unlocked or hero_video_audio or float(volumes.announcer_volume) <= 0: return 0.0
	var stream = load_real(VERSUS_PRELUDE_PATH)
	if stream == null: return 0.0
	_voice.stream = stream; _voice.volume_db = -3.0
	voice_id = "versus_prelude"; _announcer_left = stream.get_length()
	# Duck before the first spoken sample, not on a later frame.
	duck_db = minf(duck_db,-4.5); _apply_mix()
	if DisplayServer.get_name() != "headless": _voice.play()
	return _announcer_left
func versus_prelude_playing() -> bool:
	return enabled and voice_id == "versus_prelude" and is_instance_valid(_voice) and _voice.playing
## Keep the board celebration visible until result speech AND its recorded tail
## complete. Check the player, not just estimated stream duration: Web audio may
## start late. Headless tests retain the deterministic duration fallback.
static func brand_fade_gain(seconds: float) -> float:
	return 1.0-smoothstep(BRAND_FADE_START,BRAND_FADE_END,seconds)
func _advance_brand_fade(delta: float):
	# Use the actual player clock on devices so buffering or a late audio start
	# never shortens the audible clip. Headless fixtures retain a deterministic clock.
	if _voice.playing:
		_brand_elapsed = maxf(_brand_elapsed,_voice.get_playback_position()+AudioServer.get_time_since_last_mix())
	else:
		_brand_elapsed += delta
	var gain := brand_fade_gain(_brand_elapsed)
	if gain <= 0.0:
		_voice.stop()
		_voice_finished()
	else:
		_voice.volume_db = _voice_base_db+linear_to_db(gain)
func _voice_finished():
	if voice_id in RESULT_VOICES:
		_announcer_left = 0; voice_id = ""; _gap_left = VOICE_GAP
func _result_voice_playing() -> bool:
	return voice_id in RESULT_VOICES and is_instance_valid(_voice) and _voice.playing
func result_announcement_pending() -> bool:
	if not enabled or not unlocked or hero_video_audio or float(volumes.announcer_volume) <= 0: return false
	if voice_id in RESULT_VOICES and (_announcer_left > 0 or _result_voice_playing()): return true
	for entry in voice_queue:
		if entry.id in RESULT_VOICES: return true
	return false
## A one-shot presentation cue intentionally lives outside the gameplay queue:
## revealing a hero video may clear that queue, but never this dedicated line.
func can_play_result_victory() -> bool:
	return enabled and unlocked and float(volumes.announcer_volume) > 0 and load_real(real_path("ann_victory")) != null
func play_result_victory():
	if not can_play_result_victory(): return
	var stream = stream_for("ann_victory")
	_result_victory.stream = stream
	_result_victory.volume_db = -1.0
	_result_victory_left = stream.get_length()
	if DisplayServer.get_name() != "headless": _result_victory.play()
	result_victory_started.emit()
func result_victory_playing() -> bool:
	return _result_victory_left > 0 and enabled and float(volumes.announcer_volume) > 0
func stop_result_victory():
	if is_instance_valid(_result_victory): _result_victory.stop()
	_result_victory_left = 0
func stop_versus_prelude():
	if voice_id == "versus_prelude": clear_announcer()
func play_versus_clash():
	stop_versus_prelude()
	# Explicit -6dB below ordinary cues, even if a still fallback has no video duck.
	cue("claim_o",0,-9.0)
func clear_announcer():
	if is_instance_valid(_voice): _voice.stop()
	voice_queue.clear(); voice_id = ""; _announcer_left = 0; _gap_left = 0; _brand_elapsed = 0.0
func announce(id: String, paired_sfx: String = ""):
	if not id in VOICES or not enabled or hero_video_audio: return
	voice_queue.append({"id":id,"sfx":paired_sfx})
	if id == "ready": voice_queue.append({"id":"weave","sfx":""})
	while voice_queue.size() > VOICE_QUEUE_MAX:
		var drop = 0
		for i in range(voice_queue.size()):
			if not voice_queue[i].id in RESULT_VOICES: drop = i; break
		voice_queue.remove_at(drop)
	_drain_voice()
func _drain_voice():
	if hero_video_audio or not enabled or not unlocked or _announcer_left > 0 or _gap_left > 0 or voice_queue.is_empty(): return
	var entry = voice_queue.pop_front(); voice_id = entry.id
	var stream = stream_for("ann_"+voice_id)
	_voice.stop(); _voice.stream = stream
	_voice_base_db = -3.0+float(Announcer.WEIGHT.get(voice_id,2))*.45
	_voice.volume_db = _voice_base_db; _brand_elapsed = 0.0
	_announcer_left = stream.get_length()
	if DisplayServer.get_name() != "headless": _voice.play()
	if not entry.sfx.is_empty(): cue(entry.sfx)
	voice_started.emit(voice_id)
func prepare_character(character_index: int):
	for length in ["tag","stab","full"]:
		var id = "hero_%d_%s" % [character_index,length]
		if not cache.has(id) and not id in _warm: _warm.append(id)
func stinger(character_index: int, length: String = "tag", pan: float = 0):
	cue("hero_%d_%s" % [character_index,length],pan)
static func real_path(kind: String) -> String:
	if kind.begins_with("ann_") and kind.trim_prefix("ann_") in VOICES:
		return "res://assets/audio/announcer/"+kind.trim_prefix("ann_")+".ogg"
	if REAL_SFX.has(kind): return "res://assets/audio/sfx/"+str(REAL_SFX[kind])+".ogg"
	return ""
static func load_real(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path,"AudioStream"): return null
	return ResourceLoader.load(path,"AudioStream") as AudioStream
func stream_for(kind: String, override_path: String = "") -> AudioStream:
	# An override is intentionally uncached: diagnostic/fallback checks cannot poison the bank.
	if not override_path.is_empty():
		var replacement = load_real(override_path)
		return replacement if replacement != null else generate(kind)
	if not cache.has(kind):
		var real = load_real(real_path(kind))
		cache[kind] = real if real != null else generate(kind)
	return cache[kind]
func duration(kind: String) -> float:
	if kind.begins_with("ann_"): return .65+float(Announcer.WEIGHT.get(kind.trim_prefix("ann_"),1))*.085
	if kind.begins_with("hero_"): return 2.3 if kind.ends_with("full") else (.24 if kind.ends_with("stab") else .72)
	return float(CUES.get("claim" if kind in ["claim_x","claim_o"] else kind,.1))
func _begin(kind: String) -> Dictionary:
	var count = int(RATE*duration(kind)); var bytes = PackedByteArray(); bytes.resize(count*2)
	return {"kind":kind,"count":count,"i":0,"bytes":bytes,"noise":19791,"previous":0.0}
func generate(kind: String) -> AudioStreamWAV:
	var job = _begin(kind); _step(job,job.count); return _finish(job)
func _finish(job: Dictionary) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE; wav.stereo = false; wav.data = job.bytes
	return wav
func _step(job: Dictionary, amount: int):
	var kind: String = job.kind; var n: int = job.count
	for i in range(int(job.i),mini(n,int(job.i)+amount)):
		var t = float(i)/RATE; var u = float(i)/n
		job.noise = (int(job.noise)*1664525+1013904223)&0x7fffffff
		var noise = float(job.noise)/1073741824.0-1.0
		var high = noise-float(job.previous); job.previous = noise
		var value = 0.0
		match kind:
			"unlock": value = sin(TAU*80*t)*.0001
			"place_x","place_o":
				var base = 1560.0 if kind == "place_x" else 1170.0
				var env = (1-exp(-t*1500))*exp(-t*65)*(1-smoothstep(.55,1.0,u))
				value = (sin(TAU*base*t)*.25+sin(TAU*base*2.71*t)*.055+sin(TAU*base*4.08*t)*.018)*env
				value += sin(TAU*320*t)*.1*exp(-t*120)
			"ui":
				var base = 1420.0 if kind == "place_x" else (730.0 if kind == "place_o" else 1840.0)
				value = (sin(TAU*base*t)*.36+sin(TAU*base*2.73*t)*.21+sin(TAU*base*4.16*t)*.1)*exp(-t*(26 if kind == "ui" else 18))
				value += high*.19*exp(-t*130)+sin(TAU*210*t)*.17*exp(-t*65)
			"invalid": value = noise*.34*exp(-t*65)+sin(TAU*(180*t-180*t*t))*.26*exp(-t*30)
			"route":
				value = noise*.12*sin(PI*u)*exp(-u*3)+sin(TAU*1320*t)*.15*exp(-absf(t-.2)*32)
				value += sin(TAU*1980*t)*.1*exp(-absf(t-.23)*38)
			"claim","claim_x","claim_o":
				value = high*.32*exp(-t*23)+sin(TAU*(57*t+2.2*(1-exp(-t*24))))*.5*exp(-t*7)
				value += sin(TAU*(420*t+160*t*t))*.12*sin(PI*u)*exp(-t*4)
				value += (sin(TAU*2140*t)+sin(TAU*2870*t))*.12*exp(-t*4)*pow(sin(t*27),8)
			"victory","defeat","draw":
				var step = mini(3,int(t/.55)); var notes = [261.63,349.23,392.0,523.25] if kind == "victory" else [261.63,233.08,196.0,174.61]
				var hz: float = notes[step]; var local = fmod(t,.55)
				var env = (1-exp(-local*35))*exp(-local*3.3)*(1-smoothstep(.78,1.0,u))
				for ratio in [1.0,1.25992 if kind == "victory" else 1.1892,1.4983]:
					value += (sin(TAU*hz*ratio*t)*.17+sin(TAU*hz*ratio*2*t)*.055+sin(TAU*hz*ratio*3*t)*.025)*env
				value += sin(TAU*65.4*t)*.14*exp(-t*3)
			_:
				if kind.begins_with("ann_"):
					var rank = float(Announcer.WEIGHT.get(kind.trim_prefix("ann_"),1))
					# A theatrical formant choir/stinger, deliberately not a speech clone.
					# Gold burst text supplies the actual words. Each rung expands its tail.
					var syllable = fmod(t,.24); var env = sin(PI*clampf(syllable/.23,0,1))*exp(-t*.9)
					var fundamental = 104.0+rank*7+sin(t*18)*4
					value = (sin(TAU*fundamental*t)*.24+sin(TAU*fundamental*2*t)*.12)*env
					value += (sin(TAU*690*t)*.17+sin(TAU*1220*t)*.12+sin(TAU*2470*t)*.045)*env
					value += high*.2*exp(-t*32)+sin(TAU*52*t)*.26*exp(-t*5)
				elif kind.begins_with("hero_"):
					var index = clampi(int(kind.split("_")[1]),0,11); var notes: Array = MOTIFS[index]
					var beat = .32 if kind.ends_with("full") else .17
					var hz = 196.0*pow(2.0,(float(ROOTS[index])+notes[mini(5,int(t/beat))])/12.0)
					var e = sin(PI*clampf(fmod(t,beat)/beat,0,1))*exp(-u*1.6)
					value = (sin(TAU*hz*t)*.32+sin(TAU*hz*2*t)*(.07+.015*(index%4))+sin(TAU*hz*3.01*t)*(.025+.018*(index/4)))*e
		# Smooth safety edges, soft limiting, headroom for layered playback.
		value *= smoothstep(0.0,.003,t)*(1-smoothstep(.94,1.0,u))
		job.bytes.encode_s16(i*2,int(clampf(value/(1+absf(value)*.35),-.95,.95)*28000))
	job.i = mini(n,int(job.i)+amount)

func _exit_tree():
	for p in _players: p.stop()
	if is_instance_valid(_voice): _voice.stop()
	if is_instance_valid(_unlock_player): _unlock_player.stop()
