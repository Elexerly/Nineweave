extends SceneTree
const Sound = preload("res://fx/sound.gd")
const A = preload("res://fx/announcer.gd")
const Themes = preload("res://themes/registry.gd")
const Loopback = preload("res://net/loopback_transport.gd")
const Main = preload("res://main/main.tscn")
const Roster = preload("res://characters/roster.gd")
const Profile = preload("res://characters/profile.gd")
const Reactions = preload("res://characters/reactions.gd")
const Rig = preload("res://characters/art.gd")
const Select = preload("res://characters/select.gd")
const F = preload("res://tests/fixtures.gd")
const Paint = preload("res://ui/paint.gd")
const Cinema = preload("res://characters/cinematic.gd")
const Layout = preload("res://ui/layout.gd")
const Store = preload("res://settings/store.gd")
class RecordingHTTP extends "res://net/http_polling_transport.gd":
	var sent: Dictionary = {}
	func _send(_path: String, _method: int, body: Dictionary, _operation_name: String) -> void: sent = body.duplicate(true)
var checks = 0
var failures = 0
func ok(value: bool, msg: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",msg)
func _initialize(): run.call_deferred()
func position(owners: Array, turn: int = 1, status: int = 0) -> Dictionary:
	return {"owners":owners,"turn":turn,"status":status,"moves":0}
func run():
	var standard_x = Paint.x_mesh(); var standard_o = Paint.o_mesh()
	ok(Paint.x_mesh(true) != standard_x and Paint.o_mesh(true) != standard_o,"large emblems use separate meshes")
	ok(Paint.x_mesh() == standard_x and Paint.o_mesh() == standard_o,"normal mark cache unchanged")
	var sound = Sound.new(); root.add_child(sound)
	ok(not sound.unlocked and not sound._unlock_player.playing,"no audio before input")
	var tick = Time.get_ticks_usec()
	for cue in Sound.CUES:
		var stream = sound.stream_for(cue)
		ok(stream is AudioStream and stream.get_length() > .02,"valid cue "+cue)
		ok(sound.stream_for(cue) == stream,"cached cue "+cue)
	for id in A.TEXT:
		var stream = sound.stream_for("ann_"+id)
		ok(stream is AudioStreamOggVorbis and stream.resource_path == Sound.real_path("ann_"+id),"real callout "+id)
	for id in Sound.REAL_SFX:
		var stream = sound.stream_for(id)
		ok(stream is AudioStreamOggVorbis and stream.resource_path == Sound.real_path(id),"real sfx "+id)
	ok(sound.stream_for("claim_x","res://assets/audio/missing.ogg") is AudioStreamWAV,"missing file synth fallback")
	for id in ["place_x","place_o"]:
		ok(sound.stream_for(id).get_length() >= .06 and sound.stream_for(id).get_length() <= .12,"short soft place "+id)
	var motifs = {}
	for i in range(12):
		for length in ["tag","stab","full"]:
			var stream = sound.stream_for("hero_%d_%s" % [i,length])
			ok(stream.data.size() > 200,"hero stream %d %s" % [i,length])
			if length == "full": motifs[hash(stream.data)] = true
	ok(motifs.size() == 12,"12 distinct original full stingers")
	print("AUDIO synthesis_all_ms=",(Time.get_ticks_usec()-tick)/1000.0," (lazy; startup only unlock)")
	for bus in ["Master","SFX","Music","Announcer"]: ok(AudioServer.get_bus_index(bus) >= 0,"bus "+bus)
	var event = InputEventKey.new(); event.pressed = true; event.keycode = KEY_SPACE; sound._input(event)
	ok(sound.unlocked,"first key unlock")
	var spoken: Array = []; sound.voice_started.connect(func(id): spoken.append(id))
	sound.announce("ready")
	ok(sound.voice_id == "ready" and sound.voice_queue[0].id == "weave","ready then weave queued")
	sound.advance_mix(sound._announcer_left+.05)
	ok(sound.voice_id.is_empty(),"100ms voice gap")
	sound.advance_mix(.06); ok(sound.voice_id == "weave","weave follows ready")
	sound.clear_announcer(); sound.announce("nineweave"); sound.announce("victory","victory")
	ok(sound.voice_id == "nineweave" and sound.voice_queue[0].id == "victory","win queues victory after ladder")
	sound.advance_mix(sound._announcer_left+.11); ok(sound.voice_id == "victory","victory follows without overlap")
	sound.clear_announcer(); sound.announce("defeat","defeat"); ok(sound.voice_id == "defeat","loss voice")
	sound.advance_mix(.1)
	ok(sound.duck_db < -3,"announcer ducks")
	sound.advance_mix(3); sound.advance_mix(1)
	ok(sound.duck_db > -.1,"duck releases")
	var path = "user://r3-sound.cfg"
	DirAccess.remove_absolute(path)
	var store = Store.new(path); ok(store.values.sound,"fresh defaults on")
	store.set_value("sound",false); store.set_value("sfx_volume",.42); store.set_value("announcer_volume",.61)
	var loaded = Store.new(path)
	ok(not loaded.values.sound and is_equal_approx(loaded.values.sfx_volume,.42) and is_equal_approx(loaded.values.announcer_volume,.61),"intentional mute and gains persist")
	var old = ConfigFile.new(); old.set_value("settings","sound",false); old.save(path)
	loaded = Store.new(path); ok(loaded.values.sound and loaded.values.audio_version == 3,"legacy bug mute migrates once")
	loaded.set_value("sound",false); ok(not Store.new(path).values.sound,"migrated mute stays intentional")
	var empty = position([0,0,0,0,0,0,0,0,0]); ok(A.detect({},empty) == "ready","ready")
	var cases = [
		[empty,position([1,0,0,0,0,0,0,0,0]),"first_claim"],
		[position([1,0,0,0,0,0,0,0,0]),position([1,0,0,0,1,0,0,0,0]),"double_lock"],
		[position([1,0,0,0,1,0,0,0,0]),position([1,0,0,1,1,0,0,0,0]),"triple_weave"],
		[position([1,0,0,0,0,0,0,0,0]),position([1,1,0,0,0,0,0,0,0]),"match_point"],
		[position([2,0,0,0,0,0,0,0,0]),position([2,0,1,0,0,0,0,0,0]),"turnaround"],
		[position([2,2,0,0,0,0,0,0,0]),position([2,2,1,0,0,0,0,0,0]),"shutout"],
		[position([1,1,0,2,0,0,0,0,0]),position([1,1,1,2,0,0,0,0,0],2,1),"nineweave"],
		[position([1,1,0,0,0,0,0,0,0]),position([1,1,1,0,0,0,0,0,0],2,1),"clean_sweep"],
		[empty,position([1,2,1,1,2,2,2,1,1],2,3),"standoff"]]
	for c in cases: ok(c[2] in A.events(c[0],c[1]),"detect "+c[2])
	ok(A.detect(empty,empty).is_empty(),"no repeated call on ordinary move")
	var unique = {}
	for key in ["id","name","pop","victory","mark","action"]:
		unique.clear()
		for h in Roster.DATA: unique[h[key]] = true
		ok(unique.size() == Roster.DATA.size(),"unique roster "+key)
	var theme_path = "user://r3-themes.cfg"; DirAccess.remove_absolute(theme_path)
	var themed = Store.new(theme_path)
	ok(themed.values.background_theme == Themes.DEFAULT_BACKGROUND and themed.values.board_theme == Themes.DEFAULT_BOARD,"crystal defaults")
	themed.set_value("background_theme","tidal"); themed.set_value("board_theme","sandstone")
	var theme_copy = Store.new(theme_path)
	ok(theme_copy.values.background_theme == "tidal" and theme_copy.values.board_theme == "sandstone","local theme persists")
	Paint.board_theme = "crystal"
	ok(Paint.themed_mesh(1) == standard_x and Paint.themed_mesh(2) == standard_o,"default theme exact original mesh")
	Paint.board_theme = "sandstone"; var alternate = Paint.themed_mesh(1)
	ok(alternate != standard_x and Paint.themed_mesh(1) == alternate,"optional theme cached separately")
	Paint.board_theme = "crystal"
	ok(Paint.themed_mesh(1) == standard_x,"restoring crystal preserves source")
	Loopback.reset_service()
	var host = Loopback.new(); var guest = Loopback.new(); root.add_child(host); root.add_child(guest)
	host.character_id = "nyx_thread"; guest.character_id = "patrick_laquin"
	host.create_room(); guest.join_room(host.code)
	ok(host.remote_character_id == "patrick_laquin" and guest.remote_character_id == "nyx_thread","loopback shares both characters")
	ok(host.character_payload() == {"character_id":"nyx_thread"},"shared cosmetic payload only character id")
	var room_json = JSON.stringify(Loopback.rooms[host.code].characters)
	ok(not "theme" in room_json and not "background" in room_json and not "sandstone" in room_json,"room metadata excludes local cosmetics")
	var errors = []; host.error.connect(func(message): errors.append(message))
	var remote_before = host.remote_character_id
	ok(not host.receive_characters({"1":"auric_rex","2":"unknown"}) and host.remote_character_id == remote_before and errors.size() == 1,"invalid character map transactional")
	host.leave(); host.queue_free(); guest.queue_free(); Loopback.reset_service()
	var http = RecordingHTTP.new(); root.add_child(http); http.character_id = "professor_gilt"
	http.create_room()
	ok(http.sent.has("character_id") and http.sent.character_id == "professor_gilt" and not http.sent.has("board_theme") and not http.sent.has("background_theme"),"HTTP lobby carries character only")
	http.send_move(4,2,1)
	ok(http.sent.has_all(["board","cell","seq","token"]) and http.sent.size() == 4,"HTTP moves unchanged and cosmetic-free")
	http.queue_free()
	var profile_path = "user://r3-profile-test.cfg"; DirAccess.remove_absolute(profile_path)
	var profile = Profile.new(profile_path)
	ok(not profile.data.onboarded and profile.data.identity.kind == "local","local identity scaffold")
	ok(profile.choose("siren_coil","  Ada  "),"profile choice")
	var profile_copy = Profile.new(profile_path)
	ok(profile_copy.data.onboarded and profile_copy.data.character_id == "siren_coil" and profile_copy.data.display_name == "Ada","profile save/load")
	ok(not profile.choose("unknown","Bad"),"unknown hero rejected")
	var ui = Main.instantiate(); ui.test_online_bypass = true; ui.settings = Store.new("user://r3-ui.cfg"); ui.profile = Profile.new(profile_path)
	ui.settings.values.sound = false; ui.settings.values.reduced_motion = false
	ui.settings.values.background_theme = "crystal"; ui.settings.values.board_theme = "crystal"; ui.profile.data.onboarded = false
	root.add_child(ui); ui.set_view_size(Vector2(390,844))
	ok(ui.controls.has("hero"),"Hero reachable from title")
	ui.request_game("local")
	ok(ui.page == "character_select" and ui.hero_select.portraits.size() == 32,"first match gates through illustrated 32-hero selection")
	ui.hero_select.focus_hero("cobalt_bastion")
	ok(ui.hero_select.hero.hero_id == "cobalt_bastion" and ui.hero_select.hero.clip == "hover_react","focus reacts with selected hero")
	ui.hero_select.field.text = "Ada"; ui.hero_select._confirm()
	ok(ui.page == "character_select" and ui._select_player == 2 and ui.hero_select.blocked_id == "cobalt_bastion","P1 lock-in advances to distinct P2 pick")
	ui.hero_select.focus_hero("ryan_blaze"); ui.hero_select._confirm()
	ok(ui.cinematic.active and ui.cinematic.kind == "versus","both picks start versus")
	ok(not ui.cinematic.skip(),"versus protects first 600ms")
	ui.cinematic.advance(.61); ok(ui.cinematic.skip() and ui.page == "game","versus tap skip starts game")
	ok(Profile.new(profile_path).data.character_id == "cobalt_bastion","selection persists")
	ok(ui.rival_character != ui.profile.data.character_id,"different rival")
	ui.debug_load_position(F.position(["XX.OO....",".........",".........",".........",".........",".........",".........",".........","........."],1,0).serialize(),"local")
	ui._debug_capture = false; ui.play_cell(0,2)
	ok(ui.cinematic.active and ui.cinematic.kind == "pop" and ui.overlay.is_empty(),"claim spawns nonmodal pop")
	ui._process(.21)
	var legal = ui.game.legal_moves()[0]
	ok(ui.play_cell(legal.x,legal.y),"next legal move accepted after 210ms during pop")
	ok(ui.cinematic.skip(),"pop skippable")
	ui.debug_load_position(F.big_tactic(1).serialize(),"local"); ui._debug_capture = false; ui.play_cell(2,2)
	ui.board.advance(2.7); ui._process(.01)
	ok(ui.cinematic.active and ui.cinematic.kind == "spotlight" and ui.board.frozen,"spotlight follows R2 win beat")
	ui.cinematic.advance(.81); ok(ui.cinematic.skip() and ui.overlay == "result" and not ui.board.frozen,"spotlight skip returns to R2 result")
	for size_value in [Vector2(390,844),Vector2(844,390),Vector2(867,553),Vector2(669,787),Vector2(1366,1024)]:
		ui.set_view_size(size_value); ui.debug_scenario("duo_panel")
		for mark in [ui.human_mark,3-ui.human_mark]:
			var rig = ui.field_heroes[mark]; var rect = Rect2(rig.position,rig.size)
			ok(not rect.intersects(ui.layout.board) and rig.mouse_filter == Control.MOUSE_FILTER_IGNORE and rig.clip_contents,"nonblocking corner "+str(size_value))
		ok(ui.layout.has("character") == (ui.layout.mode in ["duo_landscape","duo_portrait"]),"Duo-only side panel "+str(size_value))
		ok(ui.hero_state(1) == "idle_power" and ui.hero_state(2) == "idle_stagger","board count controls stance "+str(ui.game.owners)+" states="+ui.hero_state(1)+"/"+ui.hero_state(2))
		var geo = Select.geometry(size_value)
		for rect in geo.tiles: ok(Rect2(Vector2.ZERO,size_value).encloses(rect) and rect.size.x >= 44 and rect.size.y >= 44,"all roster tiles fit touch targets "+str(size_value))
		for scenario in ["character_select","lock_in","claim_pop","win_spotlight","duo_panel"]:
			ui.debug_scenario(scenario,.5); ui.debug_refresh()
			await process_frame
			await process_frame
			ok(ui.page in ["game","character_select"],"posed scenario "+scenario)
	for view in [Vector2(360,640),Vector2(375,667),Vector2(390,844),Vector2(844,390),Vector2(568,320),Vector2(867,553),Vector2(669,787),Vector2(1366,1024)]:
		var l = Layout.compute(view); var b: Rect2 = l.board
		for claimed in range(9):
			var pop = Cinema.pop_region(l,claimed)
			var pad = b.size.x*.022; var gap = b.size.x*.018; var edge = (b.size.x-pad*2-gap*2)/3
			var tile = Rect2(b.position+Vector2(pad+claimed%3*(edge+gap),pad+(claimed/3)*(edge+gap)),Vector2.ONE*edge)
			ok(not pop.grow(5).intersects(tile),"pop leaves claimed board visible "+str(view)+" "+str(claimed))
			# Round 3c: the pop never sits on the board, so the old on-board width cap is gone.
			ok(Rect2(Vector2.ZERO,view).encloses(pop) and not pop.intersects(b),"pop inside view, off the board")
	ui.start_game("computer",1); ui._debug_capture = true; ui.thinking = false
	ui._apply_move(0,4); ok(ui.board.last_move.x < 0,"own move does not highlight")
	ui._apply_move(4,0)
	ok(ui.board.last_move == Vector2i(4,0) and not ui.board.last_move_whole,"AI reply cell highlighted")
	var cell_highlight = ui.board.last_move_rect(); ui.board.advance(8)
	ok(ui.board.last_move_rect() == cell_highlight,"white highlight persists without a pulse")
	ui._apply_move(0,3); ok(ui.board.last_move.x < 0,"own next move clears highlight")
	ui._apply_move(3,1); ok(ui.board.last_move == Vector2i(3,1),"next opponent reply replaces highlight")
	ui.undo_move(); ui.thinking = false
	ok(ui.board.last_move == Vector2i(4,0),"undo restores previous AI highlight")
	ui._debug_capture = false; ui._save_match(); ui.go_home(); ui.resume_game(); ui.thinking = false; ui._debug_capture = true
	ok(ui.board.last_move == Vector2i(4,0),"save resume restores AI highlight from history")
	ui.start_game("local"); ui._debug_capture = true
	ui._apply_move(0,4); ok(ui.board.last_move == Vector2i(0,4),"pass play previous X")
	ui._apply_move(4,0); ok(ui.board.last_move == Vector2i(4,0),"pass play previous O")
	var claim_move = ui._debug_stage(ui.MIDGAME+ui.CLAIM_TAIL); ui.human_mark = 2; ui._refresh_labels()
	ok(ui.board.last_move == claim_move and ui.board.last_move_whole,"opponent claim highlights whole board")
	ok(ui.board.last_move_rect().size.x > ui.board.tile_rect(claim_move.x).size.x*.8,"whole-board highlight geometry")
	ui.start_game("computer"); ui._debug_capture = true; ui.thinking = false
	ok(ui.board.last_move.x < 0,"new game clears last move")
	ui.debug_scenario("last_move"); ok(ui.board.last_move.x >= 0,"last move capture after opponent reply")
	for event_id in Reactions.EVENTS:
		var choices: Array = Reactions.EVENTS[event_id].choices
		ok(not choices.is_empty(),"event has weighted reaction "+event_id)
		for choice in choices: ok(Reactions.CLIPS.has(choice[0]) and int(choice[1]) > 0,"valid weighted reaction")
	for hero_index in range(12):
		for reaction_id in Reactions.CLIPS:
			var face = Reactions.expression_for(hero_index,reaction_id)
			ok(face.id in Reactions.EXPRESSIONS and face.dialect == Reactions.DIALECTS[hero_index],"hero expression resolves %d %s" % [hero_index,reaction_id])
	var cooldown = Reactions.new()
	ok(cooldown.request("own_move",0) and not cooldown.request("opponent_move",0),"ordinary reactions respect cooldown")
	ok(cooldown.request("own_claim",0) and not cooldown.request("own_claim",0),"claim can interrupt move, never repeat spam")
	ok(cooldown.request("near_loss",0),"near loss can interrupt claim")
	cooldown.advance(3); ok(cooldown.remaining == 0 and cooldown.request("opponent_move",0),"reaction cooldown releases")
	var quiet = Reactions.new(); quiet.request("win",2,true)
	ok(quiet.remaining <= .5,"reduced motion reaction shortened")
	for event_case in [
		[F.position(["XX.OO....",".........",".........",".........",".........",".........",".........",".........","........."],1,0),0,2,"own_claim","opponent_claim"],
		[F.position(["XXXOO....","XX.OO....",".........",".........",".........",".........",".........",".........","........."],1,1),1,2,"own_claim","near_loss"],
		[F.position(["OOOXX....","XX.OO....",".........",".........",".........",".........",".........",".........","........."],1,1),1,2,"comeback","opponent_claim"],
		[F.position(["X........",".........",".........",".........",".........",".........",".........",".........","........."],1,0),0,1,"own_move","opponent_good"],
		[F.big_tactic(1),2,2,"win","loss"]]:
		ui.debug_load_position(event_case[0].serialize(),"computer")
		for rig in ui.field_heroes.values(): rig.reaction = Reactions.new()
		ui._apply_move(event_case[1],event_case[2])
		ok(ui.field_heroes[1].reaction.event == event_case[3] and ui.field_heroes[2].reaction.event == event_case[4],"game routes reactions "+event_case[3]+"/"+event_case[4])
	for mark in [1,2]:
		ui.debug_load_position(F.big_tactic(mark).serialize(),"computer"); ui.sound.enabled = true; ui.sound.unlocked = true; ui.sound.clear_announcer()
		ui._apply_move(2,2)
		ok(ui.sound.voice_id in ["nineweave","clean_sweep"] and ui.sound.voice_queue.back().id == ("victory" if mark == 1 else "defeat"),"real match result voice routing "+str(mark))
	ui.debug_load_position(F.big_tactic(1).serialize(),"local"); ui.sound.clear_announcer(); ui._apply_move(2,2)
	ok(ui.sound.voice_id == "nineweave" and ui.sound.voice_queue.is_empty(),"local result has no player victory/defeat")
	ui.sound.enabled = false
	ui.debug_scenario("reaction"); ui.debug_refresh()
	ok(ui.field_heroes[1].reaction.remaining > 0 and ui.field_heroes[2].reaction.remaining > 0,"deterministic reaction capture")
	var small_geo = Select.geometry(Vector2(568,320))
	for rect in small_geo.tiles: ok(rect.size.x >= 44 and rect.size.y >= 44,"short landscape roster touch targets")
	for size_value in [Vector2(867,553),Vector2(669,787)]:
		var seam = Rect2(size_value.x*.5-11,0,22,size_value.y)
		var geo = Select.geometry(size_value,seam)
		for key in ["hero","plaque","field","confirm","heading","back"]: ok(not geo[key].intersects(seam),"hero selection hinge-safe "+key)
		for rect in geo.tiles: ok(not rect.intersects(seam),"roster stays clear of hinge")
	for h in Roster.DATA:
		var rig = Rig.new(); rig.hero_id = h.id; rig.size = Vector2(260,455); rig.frozen = true; root.add_child(rig)
		ok(rig.texture != null and rig.bust and rig.clip_contents,"illustrated head replaces articulated polygons "+h.name)
		for face in ["neutral","smug","panic","doubletake","eyeroll","cheer","pout"]:
			rig.expression = face; rig.refresh_texture()
			ok(rig.texture == Rig.get_texture(h.id,"head_"+face) and rig.texture.get_size() == Vector2(256,256),"all illustrated faces registered "+h.name+" "+face)
		for animation in Rig.CLIPS: rig.set_clip(animation); rig.clip_age = .5; rig.pose(1.4)
		rig.queue_free()
	ui.set_view_size(Vector2(390,844)); ui.go_home(); ui.show_settings()
	ok(ui.controls.has("cosmetics") and ui.controls.has_all(["sfx_volume","announcer_volume"]),"settings exposes cosmetics and audio gains")
	ui.controls.cosmetics.pressed.emit(); ui.controls.background_theme.pressed.emit(); ui.controls.board_theme.pressed.emit()
	ok(ui.settings.values.background_theme == "tidal" and ui.settings.values.board_theme == "sandstone","settings theme selection")
	for bg in ["crystal","tidal","desert"]:
		ui.settings.values.background_theme = bg; ui._apply_preferences(); ui.debug_scenario("midgame"); ui.debug_refresh()
		await process_frame; await process_frame
		ok(ui.backdrop.background_theme == bg,"headless theme traversal "+bg)
	ui.settings.values.background_theme = "crystal"; ui.settings.values.board_theme = "crystal"; ui._apply_preferences()
	ui.queue_free(); await process_frame
	sound.enabled = false; sound._unlock_player.stop()
	await create_timer(.06).timeout
	sound.queue_free(); await process_frame
	print("NINEWEAVE_ROUND3 ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
