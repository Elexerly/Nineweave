extends SceneTree
## Round 3d audio regression suite: the web build was silent because runtime add_bus()
## scrambled Godot's JS bus mirror (Master looped back into itself). These checks pin the
## bus layout, the no-add_bus rule, stream loading and the cue -> Master routing.
const Sound = preload("res://fx/sound.gd")
const Store = preload("res://settings/store.gd")
const LAYOUT_PATH = "res://default_bus_layout.tres"
const EXPECTED = [["Master",""],["SFX","Master"],["Music","Master"],["Announcer","Master"],["CrystalPan0","SFX"],["CrystalPan1","SFX"],["CrystalPan2","SFX"],["CrystalPan3","SFX"],["CrystalPan4","SFX"]]
const PANS = [-.7,-.35,0.0,.35,.7]
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame

func run():
	layout_file()
	startup_layout("engine loads default_bus_layout.tres at startup")
	static_guards()
	var sound = Sound.new(); root.add_child(sound); await frames()
	startup_layout("after Sound._ready()")
	sound.ensure_buses(); sound.ensure_buses()
	startup_layout("after repeated ensure_buses()")
	fallback(sound)
	streams(sound)
	cue_routing(sound)
	defaults(sound)
	sound.queue_free(); await frames(3)
	print("NINEWEAVE_AUDIO ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func bus_names() -> Array:
	var names: Array = []
	for i in range(AudioServer.bus_count): names.append(str(AudioServer.get_bus_name(i)))
	return names

# ------------------------------------------------------------------ layout resource
func layout_file():
	ok(FileAccess.file_exists(LAYOUT_PATH),"project ships default_bus_layout.tres")
	var layout = load(LAYOUT_PATH)
	ok(layout is AudioBusLayout,"default_bus_layout.tres loads as AudioBusLayout")
	if not layout is AudioBusLayout: return
	for i in range(1,EXPECTED.size()):
		ok(str(layout.get("bus/%d/name" % i)) == EXPECTED[i][0],"layout bus %d is %s" % [i,EXPECTED[i][0]])
		ok(str(layout.get("bus/%d/send" % i)) == EXPECTED[i][1],"layout %s sends to %s" % [EXPECTED[i][0],EXPECTED[i][1]])
		ok(is_zero_approx(float(layout.get("bus/%d/volume_db" % i))) and not layout.get("bus/%d/mute" % i),"layout %s at 0 dB, unmuted" % EXPECTED[i][0])
	for i in range(5):
		var effect = layout.get("bus/%d/effect/0/effect" % (4+i))
		ok(effect is AudioEffectPanner and is_equal_approx(effect.pan,PANS[i]),"CrystalPan%d panner at %s" % [i,PANS[i]])
	ok(str(ProjectSettings.get_setting("audio/buses/default_bus_layout",LAYOUT_PATH)) == LAYOUT_PATH,"project uses default_bus_layout.tres")

## Engine bus order must equal the layout exactly: same count, order, sends, no duplicates.
func startup_layout(label: String):
	var names = bus_names()
	ok(AudioServer.bus_count == EXPECTED.size(),"%s: bus count %d (got %d %s)" % [label,EXPECTED.size(),AudioServer.bus_count,names])
	var seen = {}
	for n in names: seen[n] = seen.get(n,0)+1
	ok(seen.size() == names.size(),"%s: no duplicate buses %s" % [label,names])
	for i in range(mini(EXPECTED.size(),AudioServer.bus_count)):
		ok(names[i] == EXPECTED[i][0],"%s: bus %d is %s (got %s)" % [label,i,EXPECTED[i][0],names[i]])
		if i > 0: ok(str(AudioServer.get_bus_send(i)) == EXPECTED[i][1],"%s: %s sends to %s" % [label,names[i],EXPECTED[i][1]])
	ok(AudioServer.get_bus_index("Master") == 0 and not AudioServer.is_bus_mute(0),"%s: Master is bus 0, unmuted" % label)

# ------------------------------------------------------------------ static guards
func static_guards():
	var src = FileAccess.get_file_as_string("res://fx/sound.gd")
	ok(not src.is_empty(),"fx/sound.gd source readable")
	ok(not "add_bus(" in src,"fx/sound.gd never calls AudioServer.add_bus() (reorders web JS bus mirror)")
	ok("bus_count" in src,"fx/sound.gd fallback appends via bus_count")
	var preset = FileAccess.get_file_as_string("res://export_presets.cfg")
	if not preset.is_empty():
		ok("navigator.audioSession" in preset and "playback" in preset and "try{" in preset,"web head_include sets audioSession.type=playback inside try/catch")
		ok("variant/thread_support=false" in preset,"web preset is single-threaded (sample playback path)")

## The runtime fallback (no layout loaded) must rebuild the same order without add_bus().
func fallback(sound):
	AudioServer.bus_count = 1
	ok(AudioServer.bus_count == 1,"fallback: buses stripped to Master")
	sound.ensure_buses()
	startup_layout("fallback ensure_buses() from Master only")
	for i in range(5):
		var index = AudioServer.get_bus_index("CrystalPan%d" % i)
		var effect = AudioServer.get_bus_effect(index,0) if index >= 0 and AudioServer.get_bus_effect_count(index) > 0 else null
		ok(effect is AudioEffectPanner and is_equal_approx(effect.pan,PANS[i]),"fallback CrystalPan%d panner at %s" % [i,PANS[i]])
	AudioServer.set_bus_layout(load(LAYOUT_PATH))
	startup_layout("layout restored")

# ------------------------------------------------------------------ streams
func streams(sound):
	var paths: Array = []
	for id in Sound.REAL_SFX: paths.append(Sound.real_path(id))
	for id in Sound.VOICES: paths.append(Sound.real_path("ann_"+id))
	for path in paths:
		ok(path.ends_with(".ogg") and ResourceLoader.exists(path,"AudioStream"),"ogg exists "+path)
		var stream = Sound.load_real(path)
		ok(stream is AudioStream and stream.get_length() > 0,"ogg loads as AudioStream "+path)
	for id in Sound.REAL_SFX: ok(sound.stream_for(id) is AudioStreamOggVorbis,"cue %s plays the owner recording" % id)

# ------------------------------------------------------------------ cue routing
func reaches_master(bus_name: String) -> bool:
	var name = StringName(bus_name)
	for hop in range(AudioServer.bus_count+1):
		var index = AudioServer.get_bus_index(name)
		if index < 0 or AudioServer.is_bus_mute(index): return false
		if index == 0: return true
		name = AudioServer.get_bus_send(index)
	return false

func cue_routing(sound):
	sound.configure({"sound":true})
	ok(not sound.unlocked,"locked before first gesture")
	sound.cue("place_x"); var any = false
	for p in sound._players: any = any or p.stream != null
	ok(not any,"locked cue is skipped, not queued")
	var press = InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	var release = InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	sound._input(press)
	ok(sound.unlocked and sound.unlock_plays == 1,"first press unlocks inside the gesture")
	sound._input(release)
	ok(sound.unlock_plays == 2,"first release replays silent unlock inside the gesture")
	ok(sound._unlock_player.stream != null and str(sound._unlock_player.bus) == "Master","unlock sample routed to Master")
	for kind in ["place_x","place_o","ui","claim_x","route"]:
		for pan in [-.7,0.0,.7]:
			for p in sound._players: p.stream = null
			sound.cue(kind,pan)
			var player = null
			for p in sound._players:
				if p.stream != null: player = p
			ok(player != null and player.stream == sound.stream_for(kind),"cue %s pan %s assigns its stream" % [kind,pan])
			if player == null: continue
			var bus = str(player.bus)
			ok(bus.begins_with("CrystalPan") and AudioServer.get_bus_index(bus) >= 0,"cue %s on an existing CrystalPan bus (%s)" % [kind,bus])
			ok(reaches_master(bus),"cue %s bus %s send chain reaches Master" % [kind,bus])
			ok(player.volume_db > -20,"cue %s player volume audible" % kind)
	sound.clear_announcer(); sound.announce("ready")
	ok(sound.voice_id == "ready" and sound._voice.stream != null and reaches_master(str(sound._voice.bus)),"announcer line plays on a bus reaching Master")
	sound.clear_announcer()

# ------------------------------------------------------------------ defaults
func defaults(sound):
	var path = "user://audio-defaults.cfg"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var settings = Store.new(path)
	ok(settings.values.sound == true,"default settings: sound on")
	for key in ["sfx_volume","announcer_volume","music_volume"]:
		ok(float(settings.values[key]) > 0,"default settings: %s non-zero" % key)
	sound.duck_db = 0.0; sound.configure(settings.values)
	ok(sound.enabled,"default settings leave sound enabled")
	for bus in ["Master","SFX","Announcer","CrystalPan2"]:
		var index = AudioServer.get_bus_index(bus)
		ok(index >= 0 and AudioServer.get_bus_volume_db(index) > -12 and not AudioServer.is_bus_mute(index),"default mix: %s audible (%s dB)" % [bus,AudioServer.get_bus_volume_db(index)])
	# Mute persists only as an explicit choice, and unmuting restores cues.
	sound.configure({"sound":false}); sound.cue("place_x")
	ok(not sound.enabled,"sound=false mutes")
	sound.configure(settings.values); ok(sound.enabled,"sound=true restores")
