extends Node
## Original PCM synthesis; no samples, plugins, threads, filesystem or web fetches.
## Fixed pool + cached mono streams. Five fixed pan sends avoid regenerating PCM.
const Announcer = preload("res://fx/announcer.gd")
const RATE = 22050
const MOTIFS = [[0,7,12,14,7,12],[0,4,7,12,9,12],[12,7,3,10,5,0],[0,0,7,5,7,12],[0,3,8,7,10,15],[0,5,9,12,7,5],[0,9,7,14,12,19],[12,11,7,4,7,0],[0,2,7,5,9,7],[0,7,14,12,16,24],[0,4,1,7,3,12],[12,7,2,9,5,0]]
const ROOTS = [0,1,2,3,4,5,6,7,8,9,10,11]
const CUES = {"unlock":.025,"place_x":.20,"place_o":.27,"invalid":.13,"route":.36,"ui":.075,"claim":1.05,"victory":2.65,"defeat":1.15,"draw":.95}
var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			for p in _players: p.stop()
			if is_instance_valid(_voice): _voice.stop()
			_announcer_left = 0; _pending_callout = ""
var unlocked: bool = false
var web_unlock: bool = false
var volumes: Dictionary = {"sfx_volume":.85,"announcer_volume":.9,"music_volume":.45}
var cache: Dictionary = {}
var duck_db: float = 0.0
var _announcer_left: float = 0.0
var _players: Array = []
var _voice: AudioStreamPlayer
var _unlock_player: AudioStreamPlayer
var _pending_callout: String = ""
var _warm: Array = []
var _job: Dictionary = {}
var generation_us: int = 0
func _ready():
	ensure_buses()
	for i in range(10):
		var p = AudioStreamPlayer.new(); add_child(p); _players.append(p)
	_voice = AudioStreamPlayer.new(); _voice.bus = "Announcer"; add_child(_voice)
	_unlock_player = AudioStreamPlayer.new(); _unlock_player.volume_db = -80; add_child(_unlock_player)
	cache.unlock = generate("unlock")
	_warm = ["ui","place_x","place_o","invalid","route","claim","victory","defeat","draw"]
	for id in Announcer.TEXT: _warm.append("ann_"+id)
func ensure_buses():
	for bus in ["SFX","Music","Announcer"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus(); var index = AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus); AudioServer.set_bus_send(index,"Master")
	for i in range(5):
		var bus = "CrystalPan"+str(i)
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus(); var index = AudioServer.bus_count-1
			AudioServer.set_bus_name(index,bus); AudioServer.set_bus_send(index,"SFX")
			var pan = AudioEffectPanner.new(); pan.pan = (i-2)*.35
			AudioServer.add_bus_effect(index,pan)
	_apply_mix()
func configure(values: Dictionary):
	enabled = bool(values.get("sound",true))
	for key in volumes: volumes[key] = clampf(float(values.get(key,volumes[key])),0,1)
	_apply_mix()
func _apply_mix():
	for pair in [["SFX","sfx_volume"],["Announcer","announcer_volume"],["Music","music_volume"]]:
		var index = AudioServer.get_bus_index(pair[0])
		if index >= 0:
			var gain = float(volumes[pair[1]])
			AudioServer.set_bus_volume_db(index,linear_to_db(maxf(.00001,gain))+(duck_db if pair[0] != "Announcer" else 0.0))
func _input(event):
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed): unlock()
func unlock():
	if unlocked: return
	unlocked = true; web_unlock = OS.has_feature("web")
	# This playback deliberately runs INSIDE the first input callback. Godot's web
	# audio driver resumes its AudioContext here; no pre-gesture play is attempted.
	_unlock_player.stream = cache.unlock
	if DisplayServer.get_name() != "headless": _unlock_player.play()
	if not _pending_callout.is_empty():
		var id = _pending_callout; _pending_callout = ""; announce(id)
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
			_job = _begin(kind)
		_step(_job,128)
		if _job.i >= _job.count:
			cache[_job.kind] = _finish(_job); _job = {}
	generation_us += Time.get_ticks_usec()-start
func advance_mix(delta: float):
	_announcer_left = maxf(0,_announcer_left-delta)
	var target = -4.5 if _announcer_left > 0 else 0.0
	duck_db = lerpf(duck_db,target,1.0-exp(-delta/(.035 if target < duck_db else .16)))
	if absf(duck_db-target) < .01: duck_db = target
	_apply_mix()
func cue(kind: String, pan: float = 0.0):
	if not enabled or not unlocked: return
	kind = {"move":"place_x","win":"victory"}.get(kind,kind)
	var stream = stream_for(kind)
	if stream == null: return
	var player = _players[0]
	for p in _players:
		if not p.playing: player = p; break
	player.stop(); player.stream = stream
	player.bus = "CrystalPan"+str(clampi(roundi(pan/.35)+2,0,4)); player.volume_db = -3
	if DisplayServer.get_name() != "headless": player.play()
func announce(id: String):
	if not Announcer.TEXT.has(id) or not enabled: return
	if not unlocked: _pending_callout = id; return
	var stream = stream_for("ann_"+id)
	_voice.stop(); _voice.stream = stream
	_voice.volume_db = -3.0+float(Announcer.WEIGHT[id])*.45
	if DisplayServer.get_name() != "headless": _voice.play()
	_announcer_left = stream.get_length(); advance_mix(.016)
func prepare_character(character_index: int):
	for length in ["tag","stab","full"]:
		var id = "hero_%d_%s" % [character_index,length]
		if not cache.has(id) and not id in _warm: _warm.append(id)
func stinger(character_index: int, length: String = "tag", pan: float = 0):
	cue("hero_%d_%s" % [character_index,length],pan)
func stream_for(kind: String) -> AudioStreamWAV:
	if not cache.has(kind): cache[kind] = generate(kind)
	return cache[kind]
func duration(kind: String) -> float:
	if kind.begins_with("ann_"): return .65+float(Announcer.WEIGHT.get(kind.trim_prefix("ann_"),1))*.085
	if kind.begins_with("hero_"): return 2.3 if kind.ends_with("full") else (.24 if kind.ends_with("stab") else .72)
	return float(CUES.get(kind,.1))
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
			"place_x","place_o","ui":
				var base = 1420.0 if kind == "place_x" else (730.0 if kind == "place_o" else 1840.0)
				value = (sin(TAU*base*t)*.36+sin(TAU*base*2.73*t)*.21+sin(TAU*base*4.16*t)*.1)*exp(-t*(26 if kind == "ui" else 18))
				value += high*.19*exp(-t*130)+sin(TAU*210*t)*.17*exp(-t*65)
			"invalid": value = noise*.34*exp(-t*65)+sin(TAU*(180*t-180*t*t))*.26*exp(-t*30)
			"route":
				value = noise*.12*sin(PI*u)*exp(-u*3)+sin(TAU*1320*t)*.15*exp(-absf(t-.2)*32)
				value += sin(TAU*1980*t)*.1*exp(-absf(t-.23)*38)
			"claim":
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
