extends Node
## Tiny procedural PCM cues, generated in memory. No imported sound assets.
var enabled: bool = true
var _players: Array = []
func cue(kind: String):
	if not enabled: return
	var player = AudioStreamPlayer.new()
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = 22050
	var length = .16 if kind == "move" else .55
	var samples = int(22050*length)
	var bytes = PackedByteArray(); bytes.resize(samples*2)
	for i in range(samples):
		var t = i/22050.0; var env = pow(1-float(i)/samples,2)
		var hz = 520 if kind == "move" else (760 if kind == "claim" else 380)
		var value = (sin(TAU*hz*t)+sin(TAU*hz*1.5*t)*.3)*env*.16
		bytes.encode_s16(i*2,int(value*30000))
	wav.data = bytes; player.stream = wav; player.volume_db = -10
	add_child(player); player.finished.connect(player.queue_free); player.play()
