extends SceneTree
const Video = preload("res://characters/hero_video.gd")
const Cache = preload("res://characters/hero_video_cache.gd")
const Roster = preload("res://characters/roster.gd")
const Fake = preload("res://tests/fake_http.gd")
const Main = preload("res://main/main.tscn")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://settings/store.gd")
const Motion = preload("res://characters/cinematic_motion.gd")
const TEST_ROOT = "user://hero-video-suite"
# Two ready intro streams are a playback seam, not additions to the real manifest.
class TwoIntros extends RefCounted:
	var held = 0
	func acquire(_id: String, kind: String) -> String:
		if kind != "intro": return ""
		held += 1; return "res://assets/hero_video/shard_jack/intro.ogv"
	func release(_id: String, _kind: String): held -= 1
	func has_audio(_id: String, _kind: String) -> bool: return true
var checks = 0
var failures = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(n: int = 2):
	for i in range(n): await process_frame
func clean(path: String):
	if not DirAccess.dir_exists_absolute(path): return
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path): clean(path.path_join(name))
	DirAccess.remove_absolute(path)
func run():
	clean(TEST_ROOT)
	catalog()
	beth_labels()
	await beth_screens()
	await cache_cases()
	await late_download()
	await controller()
	clean(TEST_ROOT)
	print("NINEWEAVE_HERO_VIDEO ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func beth_labels():
	var hero = Roster.get_hero("madame_solstice")
	ok(hero.id == "madame_solstice","Beth Solstice keeps the madame_solstice id")
	ok(hero.name == "Beth Solstice","roster display name is Beth Solstice")
	ok(Roster.tile_label("madame_solstice") == "BETH SOLSTICE","select tile label is BETH SOLSTICE")
	ok(Roster.tile_lines("madame_solstice") == PackedStringArray(["BETH","SOLSTICE"]),"select tile wraps BETH / SOLSTICE")
	ok(hero.name.to_upper() == "BETH SOLSTICE","versus, winner and select plaque use BETH SOLSTICE")
	ok(not "MADAME" in Roster.tile_label("madame_solstice") and not "MADAME" in hero.name.to_upper(),"old MADAME tile label is gone")
	ok(Roster.tile_label("simon_shade") == "SIMON" and Roster.tile_label("james_ii") == "JAMES II","other tile-label rules stay the same")
func beth_screens():
	var Select = load("res://characters/select.gd")
	var select = Select.new(); select.selected_id = "cryon"; select.size = Vector2(390,844)
	root.add_child(select); await frames()
	select.focus_hero("madame_solstice")
	ok(select.selected_id == "madame_solstice","select focuses Beth Solstice")
	ok(Roster.tile_label(select.selected_id) == "BETH SOLSTICE","focused select tile stays BETH SOLSTICE")
	ok(Roster.get_hero(select.selected_id).name.to_upper() == "BETH SOLSTICE","select plaque name is BETH SOLSTICE")
	var tile_ok = false
	for tile in select.portraits:
		if Roster.DATA[tile.index].id == "madame_solstice":
			tile_ok = Roster.tile_label(Roster.DATA[tile.index].id) == "BETH SOLSTICE"
	ok(tile_ok,"Beth Solstice portrait tile is labelled BETH SOLSTICE")
	select.queue_free(); await frames()
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.profile = Profile.new(TEST_ROOT.path_join("beth-profile.cfg")); ui.settings = Store.new(TEST_ROOT.path_join("beth-settings.cfg"))
	ui.profile.data.character_id = "madame_solstice"; ui.profile.data.display_name = "Patrick"; ui.profile.data.onboarded = true
	ui.settings.values.sound = false; ui.settings.values.player_name = "Patrick"; ui.settings.values.reduced_motion = false
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	ui.rival_character = "cryon"; ui.start_game("computer",1,true,true); await frames()
	ok(ui.cinematic.kind == "versus" and ui.cinematic.winner_id == "madame_solstice","versus stars Beth Solstice")
	ok(Roster.get_hero(ui.cinematic.winner_id).name.to_upper() == "BETH SOLSTICE","versus hero caption is BETH SOLSTICE")
	ok(not "BETH" in Roster.get_hero(ui.cinematic.loser_id).name.to_upper(),"rival caption is not Beth Solstice")
	# Stage a Beth Solstice win and open her maskless victory clip.
	var patterns: Array = []
	for i in range(9): patterns.append(".........")
	patterns[0] = "XXXOO...."; patterns[1] = patterns[0]; patterns[2] = "XX.OO...."
	var staged = load("res://kernel/rules.gd").new(); staged.deserialize({"v":1,"cells":"".join(patterns),"turn":1,"active":2,"history":[]})
	ui.debug_load_position(staged.serialize()); ui.game.play(2,2)
	ui._refresh_labels(); ui._show_spotlight(); await frames()
	ok(ui.cinematic.kind == "spotlight" and ui.cinematic.winner_id == "madame_solstice","winner cutscene is Beth Solstice")
	ok(Roster.get_hero(ui.cinematic.winner_id).name.to_upper() == "BETH SOLSTICE","winner subtitle is BETH SOLSTICE")
	ok(ui.cinematic.video_playing(),"Beth maskless victory clip plays")
	ui.go_home(); ui.queue_free(); await frames(3)
	await long_name_layout()
func long_name_layout():
	var Paint = load("res://ui/paint.gd")
	var Select = load("res://characters/select.gd")
	var Cinema = load("res://characters/cinematic.gd")
	var Overlay = load("res://characters/hero_video_overlay.gd")
	var name = "BETH SOLSTICE"
	for extent in [Vector2(360,640),Vector2(390,844),Vector2(1366,1024)]:
		var select = Select.new(); select.selected_id = "madame_solstice"; select.size = extent
		root.add_child(select); await frames()
		var view = Rect2(Vector2.ZERO,extent)
		var tile_found = false
		for tile in select.portraits:
			if Roster.DATA[tile.index].id != "madame_solstice" or not tile.visible: continue
			tile_found = true
			var lines = Roster.tile_lines("madame_solstice")
			ok(lines.size() == 2 and lines[0] == "BETH" and lines[1] == "SOLSTICE","two-line tile caption "+str(extent))
			ok(view.encloses(tile.get_rect()),"Beth Solstice tile stays in view "+str(extent))
			for line in lines:
				var fs = Paint.fit_size(line,tile.size.x-8,13)
				ok(fs >= 9 and Paint.text_width(line,fs) <= tile.size.x-8,"tile line fits inside the tile "+line+" "+str(extent)+str(tile.size))
		ok(tile_found,"Beth Solstice tile is visible "+str(extent))
		var lanes = Select.plaque_lanes(select.geo.plaque)
		var plaque_fs = Paint.fit_box(name,lanes.name,25,Paint.SERIF)
		ok(view.encloses(lanes.name) and plaque_fs >= 9 and Paint.text_width(name,plaque_fs,Paint.SERIF) <= lanes.name.size.x,"select plaque fits BETH SOLSTICE "+str(extent))
		select.queue_free(); await frames()
		var lane = Rect2(10,58,extent.x*.5-20,maxf(1,extent.y-156))
		var fit = minf(lane.size.x/Overlay.PORTRAIT.x,lane.size.y/Overlay.PORTRAIT.y)
		var frame = Rect2(lane.get_center()-Overlay.PORTRAIT*fit*.5,Overlay.PORTRAIT*fit)
		var box = Rect2(frame.position.x,frame.end.y+10,frame.size.x,44)
		ok(view.encloses(frame) and view.encloses(box),"versus name plate stays on screen "+str(extent))
		var vs_fs = Paint.fit_size(name,box.size.x,20)
		if vs_fs < 14:
			for line in ["BETH","SOLSTICE"]:
				var line_fs = Paint.fit_size(line,box.size.x,16)
				ok(line_fs >= 9 and Paint.text_width(line,line_fs) <= box.size.x,"versus wrapped caption fits "+line+" "+str(extent))
		else:
			ok(vs_fs >= 9 and Paint.text_width(name,vs_fs) <= box.size.x,"versus caption fits "+str(extent))
		var plaque = Cinema.spotlight_plaque(view)
		var name_box = Rect2(plaque.position+Vector2(6,2),Vector2(plaque.size.x-12,plaque.size.y*.48))
		var win_fs = Paint.fit_box(name,name_box,28,Paint.SERIF)
		ok(view.encloses(name_box) and win_fs >= 9 and Paint.text_width(name,win_fs,Paint.SERIF) <= name_box.size.x,"winner plaque fits BETH SOLSTICE "+str(extent))
func catalog():
	var v = Video.new(); v.bundled_override = 1; root.add_child(v)
	ok(v.bundled() and not v.streaming(),"bundled source policy seam")
	ok(Roster.DATA.size() == 32 and v.catalog.size() == 32,"manifest covers exactly 32 roster heroes")
	var clips = 0
	for hero in Roster.DATA:
		ok(v.catalog.get(hero.id,[]) == ["intro","victory"],"both clip kinds catalogued for "+hero.id)
		for kind in Video.KINDS:
			var path = "res://assets/hero_video/%s/%s.ogv" % [hero.id,kind]
			ok(v.has_clip(hero.id,kind) and v.is_ready(hero.id,kind) and v.local_path(hero.id,kind) == path,"native bundled clip "+hero.id+"/"+kind)
			ok(not Cache.ogg_info(path).is_empty(),"complete Theora Ogg "+hero.id+"/"+kind)
			clips += 1
	ok(clips == 64,"64 complete roster clips")
	for alias in Roster.ALIASES:
		for kind in Video.KINDS:
			ok(v.has_clip(alias,kind) and v.local_path(alias,kind) == v.local_path(Roster.ALIASES[alias],kind),"alias resolves canonical clip "+alias+"/"+kind)
	ok(Cache.key("derrick_torque","intro") == "devin_torque/intro","cache canonicalizes aliases")
	ok(not v.has_clip("../bad","intro") and not v.has_clip("shard_jack","bad"),"unknown/kind rejected")
	ok(v.local_path("shard_jack","intro") == "res://assets/hero_video/shard_jack/intro.ogv","native res path")
	ok(v.local_path("shard_jack","victory") == "res://assets/hero_video/shard_jack/victory.ogv","Jack victory is bundled")
	ok(v.local_path("max_granite","intro") == "res://assets/hero_video/max_granite/intro.ogv","Max intro is bundled")
	v.catalog.erase("cryon")
	ok(not v.is_ready("cryon","intro") and v.local_path("cryon","intro").is_empty(),"uncatalogued native file is not ready")
	ok(Cache.key("shard_jack","intro") != Cache.key("shard_jack","victory"),"kind participates in cache key")
	ok(v.cache.get_parent() == null and v.cache.pending.is_empty(),"native never activates HTTP/cache")
	ok(Cache.ogg_info(v.local_path("shard_jack","intro")).get("audio",false),"pilot is complete Theora with Vorbis")
	v.free()
func make_cache(suffix: String) -> Dictionary:
	var cache = Cache.new(); cache.root_path = TEST_ROOT.path_join(suffix)
	cache.catalog = {"shard_jack":["intro"],"max_granite":["victory"]}
	var requests: Array = []
	cache.request_factory = func():
		var fake = Fake.new(); requests.append(fake); return fake
	root.add_child(cache); cache.set_process(false)
	return {"cache":cache,"requests":requests}
func pilot(id: String, kind: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes("res://assets/hero_video/%s/%s.ogv" % [id,kind])
func cache_cases():
	var jack = pilot("shard_jack","intro"); var max_clip = pilot("max_granite","victory")
	var setup = make_cache("basic"); var c = setup.cache; var requests = setup.requests
	c.prefetch("shard_jack","intro"); c.prefetch("shard_jack","intro")
	ok(requests.size() == 1 and c.pending.size() == 1,"inflight request deduped")
	ok(not c.is_ready("shard_jack","intro") and c.local_path("shard_jack","intro").is_empty(),"readiness never awaits a pending download")
	ok(requests[0].requests[0].url == "hero_video/shard_jack/intro.ogv","relative project-path sidecar URL")
	c.prefetch("shard_jack","victory"); c.prefetch("max_granite","intro"); c.prefetch("unknown","intro"); c.prefetch("derrick_torque","intro")
	ok(requests.size() == 1,"no HTTP for absent manifest kind/unknown/alias")
	requests[0].respond_bytes(200,jack.slice(0,jack.size()-1))
	ok(not c.is_ready("shard_jack","intro") and not FileAccess.file_exists(c.root_path+"/shard_jack/intro.ogv"),"truncated download not published")
	c._process(.3); ok(requests.size() == 2,"incomplete write retried with backoff")
	requests[1].respond_bytes(200,jack)
	ok(c.is_ready("shard_jack","intro") and not FileAccess.file_exists(c.local_path("shard_jack","intro")+".part"),"verified file atomically installed")
	c.prefetch("shard_jack","intro"); ok(requests.size() == 2,"ready cache avoids HTTP")
	c.prefetch("max_granite","victory"); requests[2].respond_bytes(404,PackedByteArray())
	c.prefetch("max_granite","victory"); c._process(10)
	ok(requests.size() == 3 and c.missing.has("max_granite/victory"),"404 terminal for session")
	c.free(); await frames()
	setup = make_cache("retry"); c = setup.cache; requests = setup.requests
	c.prefetch("max_granite","victory"); requests[0].respond_bytes(503,PackedByteArray())
	c._process(.1); ok(requests.size() == 1,"short retry backoff")
	c._process(.2); requests[1].respond_bytes(0,PackedByteArray(),HTTPRequest.RESULT_CANT_CONNECT)
	c._process(.6); requests[2].respond_bytes(200,max_clip)
	ok(c.is_ready("max_granite","victory") and requests.size() == 3,"503/network retry then success")
	c.free(); await frames()
	setup = make_cache("exhaust"); c = setup.cache; requests = setup.requests
	c.prefetch("max_granite","victory")
	for i in range(3):
		requests[i].respond_bytes(503,PackedByteArray()); c._process(1)
	c.prefetch("max_granite","victory")
	ok(requests.size() == 3 and c.pending.is_empty(),"bounded retries do not hammer")
	c.free(); await frames()
	setup = make_cache("lru"); c = setup.cache; requests = setup.requests
	c.prefetch("shard_jack","intro"); requests[0].respond_bytes(200,jack)
	c.prefetch("max_granite","victory"); requests[1].respond_bytes(200,max_clip)
	c.local_path("shard_jack","intro"); c.max_clips = 1; c._evict()
	ok(c.is_ready("shard_jack","intro") and not c.is_ready("max_granite","victory"),"least-recently-used evicted by clip cap")
	c.pin("shard_jack","intro"); c.max_bytes = 1; c._evict()
	ok(c.is_ready("shard_jack","intro"),"playing file pinned above size cap")
	c.unpin("shard_jack","intro")
	ok(not c.is_ready("shard_jack","intro"),"size cap applied on release")
	c.free(); await frames()
	setup = make_cache("restart"); c = setup.cache; requests = setup.requests
	c.prefetch("shard_jack","intro"); requests[0].respond_bytes(200,jack,HTTPRequest.RESULT_SUCCESS,PackedStringArray(["Content-Length: 1"]))
	ok(not c.is_ready("shard_jack","intro"),"content-length mismatch rejected")
	c._process(1); requests[1].respond_bytes(200,jack)
	var path = c.root_path; c.free(); await frames()
	var stale = FileAccess.open(path+"/shard_jack/victory.ogv",FileAccess.WRITE); stale.store_buffer(jack); stale.close()
	var partial = FileAccess.open(path+"/shard_jack/intro.ogv.part",FileAccess.WRITE); partial.store_buffer(jack.slice(0,30)); partial.close()
	c = Cache.new(); c.root_path = path; c.catalog = {"shard_jack":["intro"]}; root.add_child(c)
	ok(c.is_ready("shard_jack","intro"),"persistent complete cache rediscovered")
	ok(FileAccess.file_exists(path+"/shard_jack/intro.ogv.ok"),"verified cache writes a versioned size stamp")
	ok(not FileAccess.file_exists(path+"/shard_jack/victory.ogv") and not FileAccess.file_exists(path+"/shard_jack/intro.ogv.part"),"restart drops uncatalogued clips and abandoned writes")
	c.free(); await frames()
	c = Cache.new(); c.root_path = path; c.catalog = {"shard_jack":["intro"]}; root.add_child(c)
	ok(c.is_ready("shard_jack","intro"),"stamped cache is ready immediately")
	c.free(); await frames()
	var intro = path+"/shard_jack/intro.ogv"
	var kept = FileAccess.get_file_as_bytes(intro)
	var chopped = FileAccess.open(intro,FileAccess.WRITE); chopped.store_buffer(kept.slice(0,kept.size()-1)); chopped.close()
	c = Cache.new(); c.root_path = path; c.catalog = {"shard_jack":["intro"]}; root.add_child(c)
	ok(not c.is_ready("shard_jack","intro") and not FileAccess.file_exists(intro),"stale stamp does not rescue a truncated file")
	c.free(); await frames()
	# A previous pilot's verified file must be downloaded again even if its size still matches.
	var legacy = FileAccess.open(intro,FileAccess.WRITE); legacy.store_buffer(kept); legacy.close()
	var old_stamp = FileAccess.open(intro+".ok",FileAccess.WRITE); old_stamp.store_string(str(kept.size())); old_stamp.close()
	c = Cache.new(); c.root_path = path; c.catalog = {"shard_jack":["intro"]}; root.add_child(c)
	ok(not c.is_ready("shard_jack","intro") and not FileAccess.file_exists(intro) and not FileAccess.file_exists(intro+".ok"),"legacy pilot stamp invalidates replaced clip despite matching size")
	c.free(); await frames()
	# Restore a complete file without a stamp so later cases can still copy from disk if needed.
	var restore = FileAccess.open(intro,FileAccess.WRITE); restore.store_buffer(kept); restore.close()
	var v = Video.new(); v.bundled_override = 0; v.cache.root_path = TEST_ROOT.path_join("stream")
	var streaming_requests: Array = []
	v.cache.request_factory = func():
		var fake = Fake.new(); streaming_requests.append(fake); return fake
	root.add_child(v)
	ok(v.streaming() and not v.bundled() and not v.is_ready("shard_jack","intro"),"streaming never reads bundled pilot")
	v.prefetch_hero("shard_jack")
	ok(streaming_requests.size() == 2,"web lazily requests both catalogued Jack clips")
	streaming_requests[0].respond_bytes(200,jack)
	ok(v.local_path("shard_jack","intro").begins_with("user://"),"streaming only returns verified user cache")
	v.free(); await frames()
func pair_requested(requests: Array, first: String, second: String) -> bool:
	for id in [first,second]:
		for kind in ["intro","victory"]:
			if not requests.has(id+"/"+kind): return false
	return true
func late_download():
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.profile = Profile.new(TEST_ROOT+"/late-profile.cfg"); ui.settings = Store.new(TEST_ROOT+"/late-settings.cfg")
	ui.profile.data.onboarded = true; ui.profile.data.character_id = "shard_jack"
	ui.hero_video.bundled_override = 0; ui.hero_video.cache.root_path = TEST_ROOT+"/late-cache"
	var requests: Array = []
	ui.hero_video.cache.request_factory = func():
		var fake = Fake.new(); requests.append(fake); return fake
	root.add_child(ui); ui.set_process(false); ui.hero_video.cache.set_process(false); await frames()
	ui.rival_character = "max_granite"; ui.start_game("computer",1,true,true)
	ok(requests.size() == 2 and ui.cinematic.video_playing() and ui.cinematic.video_overlay._waiting_for_intros,"cold web intros keep versus open while loading")
	ui.cinematic.advance(4.0)
	ok(ui.cinematic.active and ui.board.frozen and ui.cinematic.duration() == INF,"loading intros hold versus beyond old three-second timeout")
	var delivered = {}
	for i in range(6):
		for req in requests:
			if req in delivered or req.requests.is_empty(): continue
			var url = str(req.requests[0].url)
			if "shard_jack/intro" in url: req.respond_bytes(200,pilot("shard_jack","intro")); delivered[req] = true
			elif "shard_jack/victory" in url: req.respond_bytes(200,pilot("shard_jack","victory")); delivered[req] = true
			elif "max_granite/intro" in url: req.respond_bytes(200,pilot("max_granite","intro")); delivered[req] = true
			elif "max_granite/victory" in url: req.respond_bytes(200,pilot("max_granite","victory")); delivered[req] = true
		ui.hero_video.cache._process(0)
	ui.cinematic.video_overlay._process(ui.cinematic.video_overlay.minimum_lead)
	ok(ui.hero_video.is_ready("shard_jack","intro") and not ui.cinematic.video_overlay._waiting_for_intros and ui.cinematic.video_overlay.sides[0].video and ui.cinematic.video_overlay.sides[1].video,"cold cache completion starts both intro videos")
	ui.cinematic.advance(.7); ui.cinematic.skip(); ok(not ui.board.frozen and ui.play_cell(4,4),"skip exits loaded intros into playable match")
	ui.rematch(); ok(ui.cinematic.video_playing(),"next versus uses completed cache")
	ui.cinematic.advance(.7); ui.cinematic.skip()
	ui.game.status = 2; ui._show_spotlight()
	ok(ui.cinematic.video_playing() and ui.hero_video.cache.pins.has("max_granite/victory"),"cached opponent victory plays and pins")
	ui.hero_video.cache.max_bytes = 1; ui.hero_video.cache._evict()
	ok(ui.hero_video.is_ready("max_granite","victory"),"active victory survives cache eviction")
	ui.cinematic.advance(.9); ui.cinematic.skip()
	ok(ui.overlay == "result" and ui.hero_video.cache.pins.is_empty() and not ui.hero_video.is_ready("max_granite","victory"),"video skip releases cache pin into LRU")
	ui.go_home(); ui.queue_free(); await frames(3)
func controller():
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.profile = Profile.new(TEST_ROOT+"/profile.cfg"); ui.settings = Store.new(TEST_ROOT+"/settings.cfg")
	ui.profile.data.onboarded = true; ui.profile.data.character_id = "shard_jack"
	ui.settings.values.sound = true; ui.settings.values.reduced_motion = false
	root.add_child(ui); ui.set_process(false); await frames()
	var requested: Array = []
	ui.hero_video.prefetch_requested.connect(func(id,kind): requested.append(id+"/"+kind))
	ui.request_game("local")
	ok(requested.has("shard_jack/intro") and requested.has("shard_jack/victory"),"initial selection prefetches both kinds")
	requested.clear(); ui.hero_select.focus_hero("max_granite")
	ok(requested == ["max_granite/intro","max_granite/victory"],"focus prefetches before Confirm")
	ui.hero_select.focus_hero("shard_jack"); ui.hero_select._confirm()
	ok(requested.has("aurelia/intro") and requested.has("aurelia/victory"),"initial second-pass hero prefetched")
	requested.clear()
	ui.hero_select.focus_hero("max_granite"); ui.hero_select._confirm()
	ok(pair_requested(requested,"shard_jack","max_granite"),"second local selection and match pair prefetch")
	var cinema = ui.cinematic
	cinema.video_overlay._process(cinema.video_overlay.minimum_lead)
	ok(cinema.video_playing() and cinema.video_overlay.sides.size() == 2,"versus uses split overlay")
	ok(cinema.video_overlay.sides[0].video and cinema.video_overlay.sides[1].video,"Jack and Max intros both play")
	var video = cinema.video_overlay
	video.set_sound_enabled(true)
	ok(is_equal_approx(video.sides[0].node.volume_db,-6.0) and video.sides[1].node.volume == 0,"only local left intro is audible")
	video.set_sound_enabled(false)
	ok(video.sides[0].node.volume == 0 and video.sides[1].node.volume == 0,"sound off fully silences both lanes")
	video.set_sound_enabled(true); video.sides[0].done = true; video.set_sound_enabled(true)
	ok(video.sides[0].node.volume == 0 and video.sides[1].node.volume == 0 and not video._audible,"opponent stays silent after local intro ends")
	video.sides[0].done = false; video.set_sound_enabled(true)
	for extent in [Vector2(390,844),Vector2(844,390),Vector2(1366,1024)]:
		cinema.relayout(ui.layout)
		ok(cinema.position == Vector2.ZERO and cinema.scale == Vector2.ONE,"video relayout keeps viewport transform")
		cinema.video_overlay.relayout(extent)
		for side in cinema.video_overlay.sides:
			ok(Rect2(Vector2.ZERO,extent).encloses(side.frame) and is_equal_approx(side.frame.size.x/side.frame.size.y,540.0/720.0),"portrait letterbox frame fits "+str(extent))
	cinema.video_overlay.relayout(ui.layout.size)
	cinema.advance(3.2); ok(cinema.active and ui.board.frozen and not cinema.buttons_shown,"video not cut at old versus deadline")
	ok(cinema.skip() and not ui.board.frozen and not cinema.video_playing(),"video skip enters play")
	requested.clear(); ui.rematch()
	ok(pair_requested(requested,"shard_jack","max_granite"),"rematch prefetches same pair")
	cinema.advance(.7)
	var tap = InputEventScreenTouch.new(); tap.pressed = true; ui._input(tap)
	ok(ui._skip_guard_until > Time.get_ticks_msec(),"video skip shares touch guard")
	requested.clear(); ui.profile.data.character_id = "vesper_vale"; ui.start_game("computer",1)
	ok(pair_requested(requested,"vesper_vale",ui.rival_character),"computer rolled rival prefetch")
	ui.settings.saved_game = {"state":ui.game.serialize(),"human":1,"character":"vesper_vale","rival_character":"max_granite"}; requested.clear(); ui.resume_game()
	ok(pair_requested(requested,"vesper_vale","max_granite"),"resume prefetches both kinds")
	requested.clear(); ui.create_online(true); ui.invite_demo_rival(); await frames()
	ok(ui.mode == "online" and pair_requested(requested,str(ui.profile.data.character_id),ui.rival_character),"local online demo still starts and prefetches remote")
	ui.go_home(); ui.profile.data.character_id = "max_granite"; ui.rival_character = "shard_jack"
	ui.debug_load_position(ui.game.serialize()); ui.game.status = 1; ui._show_spotlight()
	ok(cinema.kind == "spotlight" and cinema.video_playing() and ui.controls.has_all(["again","menu"]),"Max victory video shares the combined results screen")
	cinema.advance(6); ok(cinema.active and cinema.buttons_shown,"result controls remain visible while video plays")
	ui.sound.announce("victory","victory_fanfare")
	ok(ui.sound.voice_queue.is_empty() and ui.sound.voice_id.is_empty(),"audible video suppresses competing commentary")
	ui.sound.advance_mix(.2)
	ok(ui.sound.hero_video_audio and ui.sound.duck_db <= -12,"video reserves mix headroom")
	ok(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < linear_to_db(float(ui.sound.volumes.music_volume))-4,"video duck reaches configured Music bus")
	var announcer_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Announcer"))
	cinema.video_overlay.sides[0].node.finished.emit()
	ui.sound.advance_mix(2)
	ok(ui.overlay == "result" and ui.controls.has_all(["again","menu"]) and cinema.video_overlay.holds_completed_result() and not cinema.active,"video completion retains silent last frame on results")
	ok(not ui.sound.hero_video_audio and ui.sound.duck_db > -.1 and is_equal_approx(announcer_db,AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Announcer"))),"duck clears; announcer never ducked")
	ui.overlay = ""; ui._rebuild(); ui._show_spotlight(); cinema.advance(.81); cinema.skip()
	ok(ui.controls.has_all(["again","menu"]) and not ui.sound.hero_video_audio,"winner skip shows results and releases audio")
	ui.overlay = ""; ui._rebuild(); ui._show_spotlight(); ui.settings.values.sound = false; ui._apply_preferences(); ui.sound.advance_mix(2)
	ok(not ui.sound.hero_video_audio and cinema.video_overlay.sides[0].node.volume_db <= -80,"sound off mutes video and releases duck")
	cinema.clear(); ui.sound.advance_mix(2); ok(not ui.sound.hero_video_audio,"clear releases video duck")
	ui.sound.enabled = true; ui.sound.unlocked = true
	ui.sound.announce("victory")
	ok(ui.sound.voice_id == "victory","normal commentary returns after video")
	ui.sound.set_hero_video_audio(true)
	ok(ui.sound.voice_id.is_empty() and ui.sound.voice_queue.is_empty() and ui.sound._announcer_left == 0 and ui.sound.duck_db == -12,"video immediately clears active commentary and applies headroom")
	ui.sound.set_hero_video_audio(false); ui.sound.advance_mix(2)
	ok(absf(ui.sound.duck_db) < .1,"interrupted video restores normal mix")
	ui._show_spotlight(); cinema.seek(.4)
	ok(not cinema.video_playing() and cinema.frozen and cinema.duration() == 5 and is_finite(cinema.age),"ready video also yields to analytic seek")
	ui._show_spotlight(); cinema.reduced_motion = true; cinema.advance(.1)
	ok(not cinema.video_playing() and cinema.duration() == 1,"enabling reduced motion stops active video")
	cinema.reduced_motion = false
	ui.profile.data.character_id = "shard_jack"; ui.game.status = 1; ui._show_spotlight()
	ok(cinema.video_playing(),"Jack full-motion victory now plays")
	ui.game.status = 3; ui._show_spotlight(); ok(cinema.kind == "draw" and not cinema.video_playing(),"draw never uses victory")
	ui.profile.data.character_id = "max_granite"; ui.game.status = 1; cinema.reduced_motion = true; ui._show_spotlight()
	ok(not cinema.video_playing() and cinema.duration() == 1,"reduced winner uses short code animation")
	ui.profile.data.character_id = "shard_jack"; ui._begin_versus()
	ok(not cinema.video_playing() and cinema.duration() == .65,"reduced intro disables video")
	var live_source = cinema.video_source
	cinema.video_source = null # Explicitly exercise missing/download-pending fallback with a full roster.
	cinema.reduced_motion = false; ui.profile.data.character_id = "vesper_vale"; ui.rival_character = "auric_rex"; ui._begin_versus()
	ok(not cinema.video_playing() and cinema.duration() == Motion.VERSUS_SECONDS,"no intro original duration")
	cinema.seek(1.4); var position_before = cinema.hero.position; cinema.seek(.1); cinema.seek(1.4)
	ok(cinema.hero.position == position_before and cinema.position == Motion.shake(1.4,false),"fallback analytic motion and seek unchanged")
	for scene in ["versus","winner","winner_cpu","draw"]:
		ui.debug_scenario(scene,0); ui.debug_seek_cinematic(.2); var position = cinema.hero.position
		ui.debug_seek_cinematic(3.5); ui.debug_seek_cinematic(.2)
		ok(not cinema.video_playing() and position == cinema.hero.position,"analytic debug capture "+scene)
	var both = TwoIntros.new(); cinema.video_source = both
	cinema.reduced_motion = false; ui._begin_versus()
	cinema.video_overlay._process(cinema.video_overlay.minimum_lead)
	ok(cinema.video_overlay.sides[0].video and cinema.video_overlay.sides[1].video and both.held == 2,"two ready intros play together")
	cinema.advance(8.1); cinema.video_overlay.sides[0].node.finished.emit()
	ok(cinema.active and ui.board.frozen,"first intro finishing waits for longer intro")
	cinema.video_overlay.sides[1].node.finished.emit()
	ok(not cinema.active and not ui.board.frozen and both.held == 0,"longer intro finishes match entry and releases both")
	ui._begin_versus(); cinema.video_overlay._process(cinema.video_overlay.minimum_lead); cinema.video_overlay.decode_enabled = true
	cinema.video_overlay._process(.6)
	ok(not cinema.active and not ui.board.frozen,"decoder stop without finished cannot strand modal")
	cinema.video_overlay.decode_enabled = false; cinema.video_source = live_source
	ui.go_home(); ui.queue_free(); await frames(3)
