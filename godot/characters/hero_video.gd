extends Node
## Single source policy: native/editor uses res:// only; web uses the sidecar cache.
const Roster = preload("res://characters/roster.gd")
const Cache = preload("res://characters/hero_video_cache.gd")
const MANIFEST = "res://assets/hero_video/manifest.json"
const KINDS = ["intro","victory"]
# Revision query prevents an old browser/CDN sidecar from shadowing replaced media.
const MEDIA_REVISIONS = {
	"kellen_byte/intro":"60713ca", "professor_gilt/intro":"fd1c7e0",
	"nyx_thread/intro":"d1e7b84", "cobalt_bastion/intro":"d1e7b84",
	"sara/intro":"d1e7b84", "pope_slam/intro":"d1e7b84",
	"jason_danger/victory":"d1e7b84", "max_granite/victory":"d1e7b84",
	"alex_wilder/victory":"d1e7b84", "rose_valor/victory":"d1e7b84",
	"devin_torque/victory":"d1e7b84", "patrick_laquin/intro":"d1e7b84",
	"patrick_laquin/victory":"d1e7b84"
}
static func versioned_relative_path(relative: String) -> String:
	var key = relative.trim_prefix("hero_video/").trim_suffix(".ogv")
	return relative + ("?v=" + str(MEDIA_REVISIONS[key]) if MEDIA_REVISIONS.has(key) else "")
# -1 = actual platform; 0/1 are explicit test seams, never saved settings.
var bundled_override: int = -1
var catalog: Dictionary = {}
var cache = Cache.new()
signal prefetch_requested(hero_id: String, kind: String)
func _init():
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		for raw_id in parsed:
			var id = Roster.canonical_id(str(raw_id))
			if Roster.valid(id) and parsed[raw_id] is Array:
				catalog[id] = []
				for kind in KINDS:
					if kind in parsed[raw_id]: catalog[id].append(kind)
func _ready():
	cache.catalog = catalog
	cache.url_resolver = sidecar_url
	# Native must never create a cache directory or HTTP request.
	if streaming(): add_child(cache)
func _exit_tree():
	if not cache.is_inside_tree(): cache.free()
func bundled() -> bool: return bundled_override == 1 if bundled_override >= 0 else not OS.has_feature("web")
func streaming() -> bool: return not bundled()
func has_clip(hero_id: String, kind: String) -> bool:
	var id = Roster.canonical_id(hero_id)
	return Roster.valid(id) and kind in KINDS and kind in catalog.get(id,[])
static func relative_path(hero_id: String, kind: String) -> String:
	return "hero_video/%s/%s.ogv" % [Roster.canonical_id(hero_id),kind]
func sidecar_url(relative: String) -> String:
	# HTTPRequest needs an absolute URL. Resolve the relative sidecar beside index.html,
	# preserving project-pages subdirectories; never use the online API origin.
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("new URL("+JSON.stringify(versioned_relative_path(relative))+", document.baseURI).href"))
	return relative # fake HTTP on native tests receives the portable relative URL.
func prefetch_hero(hero_id: String):
	var id = Roster.canonical_id(hero_id)
	if not Roster.valid(id): return
	for kind in KINDS:
		prefetch_requested.emit(id,kind)
		if streaming() and has_clip(id,kind): cache.prefetch(id,kind)
func prefetch_pair(first: String, second: String):
	# Both intros share the two download slots before either victory is queued.
	for kind in KINDS:
		for raw_id in [first,second]:
			var id = Roster.canonical_id(raw_id)
			if not Roster.valid(id): continue
			prefetch_requested.emit(id,kind)
			if streaming() and has_clip(id,kind): cache.prefetch(id,kind)
	if streaming(): cache.prioritize_intros(first,second)
func is_ready(hero_id: String, kind: String) -> bool:
	if not has_clip(hero_id,kind): return false
	if streaming(): return cache.is_ready(hero_id,kind)
	var path = "res://assets/"+relative_path(hero_id,kind)
	var file = FileAccess.open(path,FileAccess.READ) if FileAccess.file_exists(path) else null
	return file != null and file.get_length() > 0
func local_path(hero_id: String, kind: String) -> String:
	if not is_ready(hero_id,kind): return ""
	return "res://assets/"+relative_path(hero_id,kind) if bundled() else cache.local_path(hero_id,kind)
func acquire(hero_id: String, kind: String) -> String:
	var path = local_path(hero_id,kind)
	if not path.is_empty() and streaming(): cache.pin(hero_id,kind)
	return path
func release(hero_id: String, kind: String):
	if streaming(): cache.unpin(hero_id,kind)
func has_audio(hero_id: String, kind: String) -> bool:
	return Cache.ogg_info(local_path(hero_id,kind)).get("audio",false)
