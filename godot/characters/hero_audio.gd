extends RefCounted
## Demux unchanged Vorbis pages from the cached OGV. AudioStreamPlayer mixes these
## independently of the frame-driven Theora decoder (especially important on web).
const MAX_FILE_BYTES = 16 * 1024 * 1024
const MAX_AUDIO_BYTES = 2 * 1024 * 1024
static func load_clip(path: String) -> AudioStreamOggVorbis:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES: return null
	var pages = extract(file.get_buffer(file.get_length()))
	if pages.is_empty(): return null
	return AudioStreamOggVorbis.load_from_buffer(pages)
static func extract(data: PackedByteArray) -> PackedByteArray:
	var output = PackedByteArray()
	var offset = 0
	var serial: int = -1
	var ended = false
	while offset < data.size():
		if offset+27 > data.size() or data.slice(offset,offset+4).get_string_from_ascii() != "OggS" or data[offset+4] != 0: return PackedByteArray()
		var count = int(data[offset+26])
		var body = offset+27+count
		if body > data.size(): return PackedByteArray()
		var length = 0
		for i in range(count): length += data[offset+27+i]
		var end = body+length
		if end > data.size(): return PackedByteArray()
		var page_serial = data.decode_u32(offset+14)
		if serial < 0 and (data[offset+5] & 2) and length >= 7 and data[body] == 1 and data.slice(body+1,body+7).get_string_from_ascii() == "vorbis":
			serial = page_serial
		if page_serial == serial:
			if ended or output.size()+end-offset > MAX_AUDIO_BYTES: return PackedByteArray()
			output.append_array(data.slice(offset,end))
			ended = (data[offset+5] & 4) != 0
		offset = end
	return output if ended else PackedByteArray()
