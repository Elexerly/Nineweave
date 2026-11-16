extends Node
## Verified Ogg files only. Readiness is an O(1) lookup; prefetch never awaits HTTP.
const Roster = preload("res://characters/roster.gd")
# Bump when approved media replaces clips at the same sidecar URLs.
const CONTENT_VERSION = "r5v"
const MAX_BYTES = 64 * 1024 * 1024 # 64 MiB, with an additional eight-clip ceiling.
const MAX_CLIPS = 8
const MAX_ATTEMPTS = 3
const MAX_DOWNLOADS = 2
const RETRY_SECONDS = .25
var root_path: String = "user://hero_video"
var max_bytes: int = MAX_BYTES
var max_clips: int = MAX_CLIPS
var catalog: Dictionary = {}
var request_factory: Callable
var url_resolver: Callable
var entries: Dictionary = {}
var pending: Dictionary = {}
var missing: Dictionary = {} # Terminal for this session (404, exhausted retries).
var pins: Dictionary = {}
var _tick: int = 0
signal downloaded(hero_id: String, kind: String)
static func key(hero_id: String, kind: String) -> String: return Roster.canonical_id(hero_id)+"/"+kind
func allowed(hero_id: String, kind: String) -> bool:
	var id = Roster.canonical_id(hero_id)
	return Roster.valid(id) and kind in ["intro","victory"] and kind in catalog.get(id,[])
func _ready():
	if not DirAccess.dir_exists_absolute(root_path): return
	# Drop stale kinds removed from the catalog and abandoned writes, so they
	# cannot sit outside the indexed size cap after a manifest update/restart.
	for folder in DirAccess.get_directories_at(root_path):
		for name in DirAccess.get_files_at(root_path.path_join(folder)):
			if name.ends_with(".part") or (name.ends_with(".ogv") and (folder != Roster.canonical_id(folder) or not allowed(folder,name.trim_suffix(".ogv")))):
				_remove(root_path.path_join(folder).path_join(name))
	# Validate persisted files once. Never infer a clip from an uncatalogued file.
	# A current-version, size-matching .ok sidecar means this file was verified, so mark it
	# ready immediately instead of re-walking every Ogg page on each web start.
	for id in catalog:
		for kind in catalog[id]:
			if not allowed(id,kind): continue
			var path = _path(id,kind)
			_remove(path+".part")
			if not FileAccess.file_exists(path):
				_remove(path+".ok"); continue
			# Legacy pilot stamps must not preserve the replaced Jack/Max clips.
			if FileAccess.file_exists(path+".ok") and not FileAccess.get_file_as_string(path+".ok").begins_with(CONTENT_VERSION+":"):
				_remove(path); continue
			var stamped = _stamped_bytes(path)
			if stamped > 0:
				_remember(key(id,kind),path,stamped); continue
			var info = ogg_info(path)
			if info.is_empty(): _remove(path)
			else:
				_stamp(path,int(info.size))
				_remember(key(id,kind),path,int(info.size))
	_evict()
func _path(hero_id: String, kind: String) -> String: return root_path.path_join(key(hero_id,kind)+".ogv")
func is_ready(hero_id: String, kind: String) -> bool: return entries.has(key(hero_id,kind))
func local_path(hero_id: String, kind: String) -> String:
	var k = key(hero_id,kind)
	if not entries.has(k): return ""
	_touch(k); return entries[k].path
func pin(hero_id: String, kind: String):
	var k = key(hero_id,kind); pins[k] = int(pins.get(k,0))+1
	if entries.has(k): _touch(k)
func unpin(hero_id: String, kind: String):
	var k = key(hero_id,kind)
	if int(pins.get(k,0)) <= 1: pins.erase(k)
	else: pins[k] -= 1
	_evict()
func prefetch(hero_id: String, kind: String):
	var id = Roster.canonical_id(hero_id); var k = key(id,kind)
	if not allowed(id,kind) or missing.has(k) or pending.has(k): return
	if entries.has(k): _touch(k); return
	pending[k] = {"id":id,"kind":kind,"attempt":0,"wait":0.0,"request":null}
	_pump()
func _process(delta):
	for job in pending.values(): job.wait = maxf(0.0,float(job.wait)-delta)
	_pump()
func _pump():
	if not is_inside_tree(): return
	var count = 0
	for job in pending.values():
		if is_instance_valid(job.request): count += 1
	for k in pending.keys():
		if count >= MAX_DOWNLOADS: break
		if not pending.has(k): continue
		var job = pending[k]
		if is_instance_valid(job.request) or job.wait > 0: continue
		count += 1; _start(k)
func _start(k: String):
	var job = pending[k]; job.attempt += 1
	var path = _path(job.id,job.kind)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: _failed(k,false); return
	_remove(path+".part")
	var request = request_factory.call() if request_factory.is_valid() else HTTPRequest.new()
	job.request = request; request.timeout = 60.0
	# HTML5 HTTPRequest frequently ignores download_file and then also delivers
	# an empty body. Native can stream to disk; web always collects the body.
	if not OS.has_feature("web"):
		request.download_file = path+".part"
	# Bound temporary disk use too. Encoded clips are typically 2–5MB each.
	request.body_size_limit = max_bytes
	add_child(request)
	request.request_completed.connect(func(result,response,headers,body):
		if pending.has(k) and pending[k].request == request: _completed(k,result,response,headers,body))
	var relative = "hero_video/%s/%s.ogv" % [job.id,job.kind]
	var url = str(url_resolver.call(relative)) if url_resolver.is_valid() else relative
	var error = request.request(url,PackedStringArray(),HTTPClient.METHOD_GET,"")
	if error != OK: _failed(k,false)
func _dispose(job: Dictionary):
	if is_instance_valid(job.request):
		job.request.cancel_request(); job.request.queue_free()
	job.request = null
func _completed(k: String, result: int, response: int, headers: PackedStringArray, _body: PackedByteArray):
	if not pending.has(k): return
	var job = pending[k]; var path = _path(job.id,job.kind)
	if response == 404: _failed(k,true); return
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		_failed(k,response >= 400 and response < 500 and response != 408 and response != 429); return
	# HTML5 HTTPRequest may ignore download_file and only deliver the body buffer.
	var part = path+".part"
	if (not FileAccess.file_exists(part) or FileAccess.get_file_as_bytes(part).is_empty()) and _body.size() > 0:
		var file = FileAccess.open(part,FileAccess.WRITE)
		if file != null: file.store_buffer(_body); file.close()
	# Prefer the in-memory body so web user:// does not re-read the whole file.
	var info = ogg_info_bytes(_body) if _body.size() > 0 else ogg_info(part)
	var expected = -1
	for header in headers:
		if header.to_lower().begins_with("content-length:"): expected = int(header.get_slice(":",1).strip_edges())
	if info.is_empty() or (expected >= 0 and expected != int(info.get("size",0))): _failed(k,false); return
	if DirAccess.rename_absolute(path+".part",path) != OK: _failed(k,false); return
	_dispose(job); pending.erase(k)
	_stamp(path,int(info.size))
	_remember(k,path,int(info.size)); _evict()
	if entries.has(k): downloaded.emit(job.id,job.kind)
	_pump()
func _failed(k: String, terminal: bool):
	var job = pending[k]; _dispose(job); _remove(_path(job.id,job.kind)+".part")
	if terminal or job.attempt >= MAX_ATTEMPTS:
		missing[k] = true; pending.erase(k)
	else: job.wait = RETRY_SECONDS*pow(2,job.attempt-1)
func _remember(k: String, path: String, bytes: int):
	entries[k] = {"path":path,"bytes":bytes,"used":0}; _touch(k)
func _touch(k: String):
	_tick += 1; entries[k].used = _tick
func _evict():
	var bytes = 0
	for entry in entries.values(): bytes += int(entry.bytes)
	while bytes > max_bytes or entries.size() > max_clips:
		var victim = ""; var oldest = 0x7fffffffffffffff
		for k in entries:
			if not pins.has(k) and int(entries[k].used) < oldest: oldest = int(entries[k].used); victim = k
		if victim.is_empty(): break # Playing files may temporarily exceed the cap.
		bytes -= int(entries[victim].bytes); _remove(entries[victim].path); entries.erase(victim)
func _stamp(path: String, bytes: int):
	var file = FileAccess.open(path+".ok",FileAccess.WRITE)
	if file != null: file.store_string(CONTENT_VERSION+":"+str(bytes)); file.close()
func _stamped_bytes(path: String) -> int:
	var mark = path+".ok"
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(mark): return 0
	var stamp = FileAccess.get_file_as_string(mark).strip_edges()
	if not stamp.begins_with(CONTENT_VERSION+":"): return 0
	var listed = stamp.trim_prefix(CONTENT_VERSION+":")
	if not listed.is_valid_int(): return 0
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return 0
	var size = int(file.get_length()); file.close()
	return size if size == int(listed) and size > 0 else 0
static func _remove(path: String):
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if path.ends_with(".ogv") and FileAccess.file_exists(path+".ok"): DirAccess.remove_absolute(path+".ok")
static func ogg_info(path: String) -> Dictionary:
	# Walk page boundaries and logical stream sequences, including EOS for EVERY
	# stream. A partial page, header-only file, HTML error, or truncated tail fails.
	# The whole file is read once: thousands of tiny FileAccess seeks are too slow
	# on the web user:// (IndexedDB) backend and delayed readiness by ~20s.
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	return ogg_info_bytes(FileAccess.get_file_as_bytes(path))
static func ogg_info_bytes(data: PackedByteArray) -> Dictionary:
	var length = data.size()
	if length < 35: return {}
	var streams = {}; var video = false; var audio = false
	var pos = 0
	while pos < length:
		if length-pos < 27: return {}
		if data[pos] != 79 or data[pos+1] != 103 or data[pos+2] != 103 or data[pos+3] != 83 or data[pos+4] != 0: return {} # OggS, version 0
		var flags = data[pos+5]; var serial = data.decode_u32(pos+14); var sequence = data.decode_u32(pos+18)
		if not streams.has(serial):
			if flags & 2 == 0 or sequence != 0: return {}
			streams[serial] = {"sequence":-1,"eos":false}
		if streams[serial].eos or sequence != int(streams[serial].sequence)+1: return {}
		streams[serial].sequence = sequence; streams[serial].eos = flags & 4 != 0
		var segments = int(data[pos+26])
		if length-pos-27 < segments: return {}
		var payload = 0
		for i in range(segments): payload += int(data[pos+27+i])
		var start = pos+27+segments
		if length-start < payload: return {}
		if flags & 2 != 0 and payload >= 7:
			var signature_kind = data[start]
			# "theora" / "vorbis" follow the ident byte.
			var name = data.slice(start+1,start+7).get_string_from_ascii()
			video = video or (signature_kind == 128 and name == "theora")
			audio = audio or (signature_kind == 1 and name == "vorbis")
		pos = start+payload
	if not video or streams.is_empty(): return {}
	for stream in streams.values():
		if not stream.eos or stream.sequence < 1: return {}
	return {"size":length,"audio":audio}

func _exit_tree():
	for job in pending.values(): _dispose(job); _remove(_path(job.id,job.kind)+".part")
	pending.clear()

func prioritize_intros(first: String, second: String):
	# Hero selection may already be downloading a victory. Give the opponent's
	# intro its slot, preserving that victory job for later (no extra decoder).
	var priority: Array = [key(first,"intro"),key(second,"intro")]
	var waiting = false
	for k in priority:
		if pending.has(k) and not is_instance_valid(pending[k].request): waiting = true
	if not waiting: return
	for job in pending.values():
		if job.kind == "victory" and is_instance_valid(job.request):
			_dispose(job); job.attempt = maxi(0,job.attempt-1)
			_remove(_path(job.id,job.kind)+".part")
	var ordered = {}
	for k in priority:
		if pending.has(k): ordered[k] = pending[k]
	for k in pending:
		if not ordered.has(k): ordered[k] = pending[k]
	pending = ordered; _pump()
