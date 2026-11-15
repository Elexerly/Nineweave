extends SceneTree
const Main = preload("res://main/main.tscn")
const R = preload("res://characters/roster.gd")
const Art = preload("res://characters/art.gd")
const Select = preload("res://characters/select.gd")
const Cinema = preload("res://characters/cinematic.gd")
const M = preload("res://characters/cinematic_motion.gd")
const Layout = preload("res://ui/layout.gd")
const P = preload("res://ui/paint.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://settings/store.gd")
const F = preload("res://tests/fixtures.gd")
const Net = preload("res://net/net_transport.gd")
const NEW_IDS = ["james_ii","sara","daphne","jason_danger","dylan_volt","max_granite","kellen_byte","simon_shade","alex_wilder","rose_valor","grayson_quake","erick_comet","devin_torque","pope_slam","ethan_ricochet","aiden_vortex"]
const KEYS = ["splash","versus","victory","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]
const SIZES = [Vector2(360,640),Vector2(390,664),Vector2(390,844),Vector2(867,553),Vector2(1366,1024),Vector2(1920,1080),Vector2(568,320),Vector2(844,390),Vector2(669,787)]
var checks = 0
var failures = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(n: int = 2):
	for i in range(n): await process_frame
func run():
	await lazy_selection()
	assets()
	aliases()
	var ui = Main.instantiate(); ui.test_online_bypass = true; ui.profile = Profile.new("user://r4b-profile.cfg"); ui.settings = Store.new("user://r4b-settings.cfg")
	ui.profile.data.character_id = "cryon"; ui.profile.data.display_name = "Patrick"; ui.profile.data.onboarded = true
	ui.settings.values.sound = false; ui.settings.values.player_name = "Patrick"; ui.settings.values.reduced_motion = false
	root.add_child(ui); ui.set_process(false); await frames()
	await selection(ui)
	versus(ui)
	winners(ui)
	winner_polish(ui)
	reduced(ui)
	await surfaces(ui)
	glyphs()
	await flip_render_probe()
	ui.go_home(); ui.queue_free(); await frames(3)
	print("NINEWEAVE_ROUND4B ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func lazy_selection():
	ok(Art.textures.is_empty(),"no eager hero texture loads")
	var select = Select.new(); select.selected_id = "kellen_byte"; select.size = Vector2(390,844); root.add_child(select)
	ok(select.page == 2 and Art.textures.size() == 9,"only selected splash plus eight current-page heads")
	for path in Art.textures:
		ok(path.ends_with("/splash.webp") if "kellen_byte" in path and path.ends_with("/splash.webp") else path.ends_with("/head_neutral.webp"),"no versus/victory/expressions loaded by selection")
	select.set_page(3)
	ok(Art.textures.size() == 17,"paging loads only the next eight heads")
	ok(not Art.textures.has("res://assets/heroes/cryon/head_neutral.webp"),"unvisited pages remain unloaded")
	select.queue_free(); await frames()
func assets():
	ok(R.DATA.size() == 32,"32 heroes")
	var unique = {}; var count = 0
	for i in range(R.DATA.size()):
		var h = R.DATA[i]; unique[h.id] = true
		if i >= 16: ok(h.id == NEW_IDS[i-16],"appended order "+h.id)
		for field in ["concept","pop","victory","defeat","action","body","prop","mark"]: ok(not str(h[field]).is_empty(),"hero copy "+h.id+" "+field)
		ok(R.audio_index(h.id) in range(12),"reused sound index "+h.id)
		for key in KEYS:
			var tex = Art.get_texture(h.id,key); count += 1
			ok(tex != null and tex.get_width() > 0 and tex.get_height() > 0,"load "+h.id+" "+key)
			if key.begins_with("head_"): ok(tex.get_size() == Vector2(256,256),"256px registered heads "+h.id+key)
			var path = "res://assets/heroes/%s/%s.webp" % [h.id,key]
			var cfg = ConfigFile.new(); ok(cfg.load(path+".import") == OK,"import exists "+path)
			ok(cfg.get_value("deps","source_file","") == path,"correct import source "+path)
			ok(cfg.get_value("params","compress/mode",-1) == 1 and cfg.get_value("params","compress/lossy_quality",0) >= .75 and cfg.get_value("params","compress/lossy_quality",1) <= .85 and not cfg.get_value("params","mipmaps/generate",true),"lossy, quality floor and mipmaps off "+path)
	ok(unique.size() == 32 and count == 320,"32 unique IDs and 320 resources")
	for i in range(R.AUDIO_IDS.size()): ok(R.audio_index(R.AUDIO_IDS[i]) == i,"original motif unchanged")
	for pair in [["cryon",0],["aurelia",1],["ryan_blaze",4],["tempest_vega",9]]: ok(R.audio_index(pair[0]) == pair[1],"Round 4 mascot motif unchanged")
func aliases():
	var expected = {"erik_comet":"erick_comet","ak_shade":"simon_shade","derrick_torque":"devin_torque","nova_sable":"aiden_vortex","mateo_ricochet":"ethan_ricochet"}
	var motifs = {"erik_comet":0,"ak_shade":2,"derrick_torque":4,"nova_sable":11,"mateo_ricochet":5}
	ok(R.ALIASES == expected,"exact five backwards-compatible roster aliases")
	var net = Net.new(); net.seat = 1
	var received: Array = []; net.character_received.connect(func(seat,id): received.append([seat,id]))
	for old in expected:
		var id: String = expected[old]
		ok(R.valid(old) and R.valid(id) and R.canonical_id(old) == id and R.index_of(old) == R.index_of(id) and R.get_hero(old).id == id,"alias lookup "+old)
		ok(R.audio_index(old) == motifs[old] and R.audio_index(id) == motifs[old],"alias keeps exact audio index "+old)
		var path = "user://r4b-alias-profile.cfg"; var cfg = ConfigFile.new(); cfg.set_value("profile","character_id",old); cfg.set_value("profile","display_name","Saved Weaver"); cfg.save(path)
		var profile = Profile.new(path)
		ok(profile.data.character_id == id and profile.data.display_name == "Saved Weaver","legacy saved profile migrates "+old)
		profile.save(); cfg.load(path); ok(cfg.get_value("profile","character_id") == id,"profile persists canonical ID "+old)
		ok(profile.choose(old,"Alias Weaver") and Profile.new(path).data.character_id == id,"choosing alias persists canonical ID "+old)
		net.character_id = old; ok(net.character_payload().character_id == id and net.lobby_payload().character_id == id,"canonical online outgoing ID "+old)
		ok(net.receive_characters({"2":old}) and net.remote_character_id == id and received.back() == [2,id],"legacy online incoming ID "+old)
		ok(Art.get_texture(old,"head_neutral") == Art.get_texture(id,"head_neutral"),"alias loads canonical hero art "+old)
	net.free()
	ok(not R.valid("removed-hero") and R.index_of("removed-hero") == 0,"unknown IDs remain invalid with safe art fallback")
	ok(R.tile_label("james_ii") == "JAMES II" and R.tile_label("simon_shade") == "SIMON","owner tile-label exception")
	for spec in [["shard_jack","Jack Sovereign",["8a4dff","15121f","e8c060"],"Checkmate was decided three moves ago."],["sara","Sara",["7cc4ff","2a3a5a","fff4dc"],"Be kind, or be outfoxed."],["aiden_vortex","Aiden Vortex",["2f6bff","1a2240","ff3b3b"],"Let it rip!"],["ethan_ricochet","Ethan Ricochet",["3a7bff","1c2450","eef2ff"],"Bank shot!"],["dylan_volt","Dylan Volt",["b26bff","2a2050","ffd34d"],"Flip a gold token. Blink and you lost."]]:
		var h = R.get_hero(spec[0]); ok(h.name == spec[1] and h.palette == spec[2] and h.pop == spec[3],"approved redesign copy/palette "+h.id)
		var copy = " ".join([h.concept,h.pop,h.victory,h.defeat,h.action,h.prop,h.mark]).to_lower()
		for word in ["hoverboard","jack be nimble","jack riot","terminator","cannon","soldier","gun","beyblade","beyblades"]: ok(not word in copy,"no retired/brand copy "+h.id+" "+word)
	for field in ["concept","pop","action"]: ok("gold" in R.get_hero("dylan_volt")[field].to_lower() and "token" in R.get_hero("dylan_volt")[field].to_lower(),"Dylan gold token "+field)
func selection(ui):
	for s in SIZES:
		ui.set_view_size(s); ui.request_game("computer")
		var select = ui.hero_select; var g = select.geo; var view = Rect2(Vector2.ZERO,s)
		var phone = Layout.mode_for(s) == "phone_portrait"
		ok(g.pages == 4 and g.per_page == 8 and g.columns == 4 and g.rows == 2 if phone else (g.per_page == 32 and g.pages == 1 and g.columns == 8 and g.rows == 4) or (g.pages == 2 and g.per_page == 16),"adaptive grid "+str(s))
		ok(select.paging_controls.size() == (g.pages+2 if g.paged else 0),"arrow and dot count "+str(s))
		var seen = {}
		for page in range(g.pages):
			select.set_page(page)
			for tile in select.portraits:
				if not tile.visible: continue
				seen[tile.index] = true
				var minimum = 56 if g.per_page == 32 else 44
				ok(tile.size.x >= minimum and tile.size.y >= minimum and view.encloses(tile.get_rect()),"tile size/viewport "+str(s)+str(tile.index))
				var lines = R.tile_lines(R.DATA[tile.index].id)
				for line in lines:
					ok(P.text_width(line,P.fit_size(line,tile.size.x-8,14)) <= tile.size.x-8,"tile label fits "+line+str(s)+str(tile.size))
				ok(tile.rig.texture != null and tile.rig.visible_art_rect().has_area(),"visible page head "+str(tile.index))
		ok(seen.size() == 32,"every hero reachable "+str(s))
		for key in ["hero","plaque","field","confirm"]: ok(view.encloses(g[key]) and g[key].has_area(),"detail/control fits "+key+str(s))
		ok(not g.hero.intersects(g.grid) and not g.plaque.intersects(g.grid),"splash/detail clear of grid "+str(s))
		ok(select.field.get_theme_stylebox("normal") is StyleBoxEmpty and select.field.placeholder_text == "Your screen name","styled screen name retains placeholder")
		select.field.text = "Test Weaver"; select.field.text_changed.emit(select.field.text)
		ok(select.display_name == "Test Weaver","screen name editing retained")
		if g.paged:
			select.set_page(0); select.paging_controls[0].pressed.emit(); ok(select.page == g.pages-1,"left arrow wraps")
			select.paging_controls[1].pressed.emit(); ok(select.page == 0,"right arrow wraps")
			for dot in range(g.pages): select.paging_controls[2+dot].pressed.emit(); ok(select.page == dot,"page dot "+str(dot))
			select.set_page(0)
			var touch = InputEventScreenTouch.new(); touch.pressed = true; touch.position = Vector2(280,400); select._input(touch)
			touch = InputEventScreenTouch.new(); touch.pressed = false; touch.position = Vector2(100,400); select._input(touch)
			ok(select.page == 1,"left touch swipe advances")
			select.swipe(Vector2(100,0)); ok(select.page == 0,"right swipe reverses")
		await frames(1)
	var folded = Select.geometry(Vector2(867,553),Rect2(426,0,15,553))
	for tile in folded.tiles:
		ok(not tile.intersects(Rect2(426,0,15,553)) and tile.size.x >= 44 and tile.size.y >= 44,"fold-safe roster")
		for h in R.DATA:
			var lines = R.tile_lines(h.id)
			for line in lines:
				ok(P.text_width(line,P.fit_size(line,tile.size.x-8,14)) <= tile.size.x-8,"folded tile captions fit "+line)
	ui.set_view_size(Vector2(390,844)); ui.profile.data.character_id = "ethan_ricochet"
	var rivals = {}; seed(42004)
	for i in range(320):
		ui.start_game("computer"); rivals[ui.rival_character] = true
		ok(ui.rival_character != "ethan_ricochet" and R.valid(ui.rival_character),"different valid random rival")
	ok(rivals.size() == 31,"random rival pool covers all other 31 heroes")
func snap(c) -> Array:
	return [c.hero.position,c.hero.scale,c.loser.position,c.loser.scale,c.loser.rotation,c.loser.art_key,c.position,c.scale,c.letter_count(),c.letter_count(true),c.buttons_shown]
func versus(ui):
	for s in [Vector2(390,844),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(s); ui.profile.data.character_id = "james_ii"; ui.rival_character = "sara"; ui.start_game("computer",1,true,true)
		var c = ui.cinematic; var view = Rect2(Vector2.ZERO,s)
		ok(c.duration() == 3 and not Rect2(c.hero.position,c.hero.size).intersects(view) and not Rect2(c.loser.position,c.loser.size).intersects(view),"dash begins fully offscreen "+str(s))
		for t in [0.0,.05]:
			c.seek(t)
			ok(c.visible and c.modulate.a == 1 and c.versus_cover_alpha() == 1 and c.get_transform()*c.versus_cover_rect() == (c.get_transform()*view) and (c.get_transform()*c.versus_cover_rect()).encloses(view),"opaque backdrop covers board from first frame "+str(s)+str(t))
		c.seek(0); c.frozen = false
		var seconds = ui.match_seconds; ui._debug_capture = false; ui._process(.2)
		ok(ui.match_seconds == seconds and not ui.thinking and ui.board.frozen and not ui.play_cell(4,4),"match clock, AI and input wait")
		c.seek(.4)
		ok(Rect2(c.hero.position,c.hero.size).intersects(view) and Rect2(c.loser.position,c.loser.size).intersects(view),"both heroes arrive by .4 "+str(s))
		ok(c.loser.facing == -1,"rival mirrored")
		ok(c.particle_limit() == 88 and not M.particle(4,.5,s,true).is_empty(),"clash uses 44 seeded particles per side")
		check_flip(c.loser)
		ok(M.vs_scale(.3501,false).x > 2 and M.vs_scale(.44,false).x < 1 and M.vs_scale(.56,false).is_equal_approx(Vector2.ONE),"VS slam overshoot, squash, settle")
		ok(M.shake(.35,false).length() > 9 and M.shake(.55,false).length() < 1 and M.shake(.60,false) == Vector2.ZERO,"clash shake decays to zero")
		var flashes = 0
		for i in range(6):
			if M.flash(.35+i/60.0+.0001,false) != 0: flashes += 1
		ok(flashes == 3,"three-frame white/ink impact")
		c.seek(1.5); var first = snap(c); var particles = M.particle(14,.5,s,true)
		c.seek(.2); c.seek(1.5)
		ok(snap(c) == first and M.particle(14,.5,s,true) == particles,"arbitrary seek is deterministic")
		c.seek(2.60); ok(c.scale.x > 1.059,"slow camera push")
		c.seek(2.80); ok(c.front.modulate.a < 1 and c.hero.position.distance_to(c.hero_rect.position) > 30,"swift card/hero exit")
		ok((c.hero.position-c.hero_rect.position).dot(M.travel(s,false)) < 0 and (c.loser.position-c.loser_rect.position).dot(M.travel(s,true)) < 0,"exit continues each hero's incoming heading")
		ok(c.front.modulate.a == 0 and M.vs_scale(2.80,false) == Vector2.ZERO,"VS and plates gone within .15s of exit")
		for t in [3.0,3.05,3.2]:
			c.seek(t); ok(not c.visible and not c.hero.is_visible_in_tree() and not c.loser.is_visible_in_tree() and not c.front.is_visible_in_tree() and not c.versus_cover_rect().has_area(),"no versus residue at/after 3s "+str(s)+str(t))
		c.seek(.599); ok(not c.skip(),"skip protected before .6")
		c.seek(.60); ok(c.skip() and not ui.board.frozen,"skip at .6 starts match")
		ui.start_game("computer",1,true,true); c.advance(2.999)
		ok(c.active and ui.board.frozen,"intro holds through 2.999 seconds")
		c.advance(.002); ok(not c.active and not c.visible and not ui.board.frozen,"three-second intro reveals board")
		ui._process(.01); ok(ui.match_seconds > 0,"clock starts after intro")
	ui.go_home()
func winners(ui):
	ui.set_view_size(Vector2(1366,1024)); ui.profile.data.character_id = "aiden_vortex"; ui.rival_character = "grayson_quake"; ui.opponent_name = "Dana"; ui.settings.values.player_name = "Patrick"
	for case in [["computer",1,1,"PATRICK WINS!","aiden_vortex"],["computer",1,2,"RIVAL AI WINS!","grayson_quake"],["local",1,2,"PLAYER 2 WINS!","grayson_quake"],["local",2,1,"PLAYER 2 WINS!","grayson_quake"],["online",1,2,"DANA WINS!","grayson_quake"]]:
		ui.debug_load_position(F.big_tactic(case[2]).serialize(),case[0]); ui.human_mark = case[1]; ui.game.play(2,2); ui._show_spotlight()
		var c = ui.cinematic
		ok(c.winner_caption() == case[3] and c.winner_id == case[4] and c.hero.hero_id == case[4],"actual winner identity "+case[3])
		ok(c.winner_accent() == P.mark_color(case[2]),"actual winning side colour "+case[3])
		if case[0] == "computer" and case[2] == 2: ok(c.winner_accent() != P.BLUE,"computer winner no longer old cyan")
		ok(c.particle_limit() == 140 and c.live_particle_count(.5) == 108 and c.live_particle_count(.5) <= 150,"108 landing particles and smaller second burst capped below 150")
		ok(c.score_font_size() >= 16 and c.duration() == 5 and c.hero.art_key == "victory","readable score and five-second victory")
		c.seek(.49); ok(c.letter_count() == 0 and c.letter_count(true) == 0,"letters initially hidden")
		c.seek(.501); ok(c.letter_count() == 1,"name starts with first letter")
		c.seek(.55); ok(c.letter_count() == 2 and c.letter_count(true) == 0,"name letters stagger before WINS")
		var wins_at = M.letter_start(c.winner_name.length(),true,false)
		c.seek(wins_at+.001); ok(c.letter_count() == c.winner_name.length() and c.letter_count(true) == 1,"WINS follows full name")
		c.seek(1.12); ok(c.loser.visible and c.loser.art_key == "head_panic" and absf(c.loser.rotation) > 0,"loser shakes and panics")
		c.seek(1.5); ok(c.loser.art_key == "head_pout" and c.loser.position.y > c.loser_rect.position.y,"loser droops and pouts")
		var first = snap(c); var sway_time = c._sway.get_shader_parameter("cinematic_time")
		c.seek(.1); c.seek(1.5); ok(first == snap(c) and sway_time == c._sway.get_shader_parameter("cinematic_time"),"winner seek and feet-anchored sway deterministic")
		c.seek(2.99); c.frozen = false; ok(not c.buttons_shown and not ui.controls.has("again"),"actions hidden before 3s")
		c.advance(.02); ok(c.buttons_shown and ui.controls.has_all(["again","menu"]),"actions arrive at 3s")
		ui._apply_result_anim(); ok(ui.controls.again.modulate.a < .1,"actions start with a fade")
		c.advance(.30); ui._apply_result_anim(); ok(ui.controls.again.modulate.a == 1,"actions finish fading/sliding")
		c.advance(2); ok(not c.active and c.visible,"readable final pose persists")
		ui._show_spotlight(); c.advance(.79); ok(not c.skip(),"result skip protected before .8")
		c.advance(.02); ok(c.skip() and c.buttons_shown and ui.controls.has_all(["again","menu"]) and ui.controls.again.modulate.a == 1,"skip reveals actions immediately")
		ui.cinematic.clear(); ui.overlay = ""; ui._rebuild()
	ui.debug_scenario("draw",.0)
	var c = ui.cinematic; c.seek(.2)
	ok(c.kind == "draw" and c.winner_caption() == "DRAW" and c.hero.position != c.hero_rect.position and c.loser.position != c.loser_rect.position,"draw heads slide into standoff")
	c.seek(.5); ok(c.letter_count() == 1 and c.loser.visible,"DRAW slams letter by letter with both heads")
	ui.debug_seek_cinematic(3.5); ok(ui.controls.has_all(["again","menu"]),"draw actions at 3.5")
	for s in [Vector2(390,844),Vector2(390,664),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(s)
		for scenario in ["versus","winner","winner_cpu","draw"]:
			ui.debug_scenario(scenario,0); ui.debug_seek_cinematic(.2); var a = snap(ui.cinematic)
			ui.debug_seek_cinematic(3.5); ui.debug_seek_cinematic(.2)
			ok(a == snap(ui.cinematic),"capture fixture exact seek roundtrip "+str(s)+scenario)
			if scenario != "versus":
				ok(not ui.controls.has("again"),"backward seek hides buttons")
				ui.debug_seek_cinematic(3.5)
				for id in ["again","menu"]: ok(Rect2(Vector2.ZERO,s).encloses(ui.controls[id].get_rect()),"captured actions stay inside viewport")
func winner_polish(ui):
	for s in [Vector2(360,640),Vector2(390,844),Vector2(867,553),Vector2(1366,1024),Vector2(669,787),Vector2(844,390)]:
		ui.set_view_size(s)
		for scenario in ["winner","winner_cpu"]:
			ui.debug_scenario(scenario,0); var c = ui.cinematic; var view = Rect2(Vector2.ZERO,s)
			c.seek(0); ok(c.hero.position.y > s.y*.8,"winner leaps from below "+str(s))
			c.seek(.2); ok(c.hero.position.x < c.hero_rect.position.x,"short leap arc "+str(s))
			c.seek(.35); ok(c.hero.position.is_equal_approx(c.hero_rect.position),"landing at .35 "+str(s))
			c.seek(.42); ok(c.hero.scale.x > 1.09 and c.hero.scale.y < .92,"visible landing squash "+str(s))
			var live = c.live_particle_count(.5); ok(live >= 80 and live == 108,"big visible landing burst "+str(s))
			for i in range(108):
				var p = c.particle_pose(i,.5)
				ok(not p.is_empty() and p.length >= 6*minf(s.x,s.y)/390.0 and p.length <= 14*minf(s.x,s.y)/390.0 and p.alpha > .9,"bright scaled 6-14px particles "+str(s)+str(i))
			var second = M.letter_start(c.winner_name.length(),true,false)+4*M.LETTER_STEP+.27
			ok(c.live_particle_count(second+.06) == 140 and c.particle_pose(108,second-.01).is_empty() and not c.particle_pose(108,second+.06).is_empty(),"second 32-particle burst when WINS finishes")
			for t in [.4,.45,.65,.9,1.12,1.5,3.5]:
				c.seek(t); var badge = c.loser_badge_rect()
				ok(badge.size.x >= 80 and badge.size.y >= 80 and view.encloses(badge.grow(5)),"proper framed badge inside viewport "+str(s)+str(t))
				ok(not badge.grow(5).intersects(Cinema.winner_head_rect(s)),"badge clears winner head "+str(s)+str(t))
				for ink in c.headline_ink_rects(): ok(not badge.grow(5).intersects(ink),"badge clears actual headline ink "+str(s)+str(t))
			c.seek(.45); ok(c.loser.position.x != c.loser_rect.position.x,"loser hit shake at .4")
			c.seek(.7); ok(c.loser.art_key == "head_pout" and c.loser.rotation > 0,"pout and droop precede panic")
			c.seek(1.12); ok(c.loser.art_key == "head_panic","panic follows pout")
			for name in ["Patrick","WWWWWWWWWWWWWWWWWWWWWWWW"]:
				c.winner_name = name; c.relayout(ui.layout)
				for frame in range(210):
					for ink in c.headline_ink_rects(frame/100.0): ok(ink.position.x >= 18 and ink.end.x <= s.x-18,"18px margin including shear/keyline/bouncing letters "+str(s)+name)
func reduced(ui):
	ui.settings.values.reduced_motion = true; ui._apply_preferences(); ui.set_view_size(Vector2(390,844)); ui.start_game("computer",1,true,true)
	var c = ui.cinematic
	for t in [0.0,.05]:
		c.seek(t); ok(c.versus_cover_alpha() == 1 and c.modulate.a == 1 and c.versus_cover_rect().encloses(Rect2(0,0,390,844)),"reduced intro also covers the board at t=0/0.05")
	c.seek(.36)
	ok(c.position == Vector2.ZERO and c.scale == Vector2.ONE and c.hero.position == c.hero_rect.position,"reduced intro only fades")
	ok(M.flash(.36,true) == 0 and M.shake(.36,true) == Vector2.ZERO,"reduced motion no flash or shake")
	ok(c.reduced_motion and c.duration() <= 1,"reduced intro is short")
	ui.debug_scenario("winner",0); c.seek(.4)
	ok(c._sway.get_shader_parameter("sway_pixels") == 0 and c.hero.position == c.hero_rect.position and c.loser.rotation == 0,"reduced victory no sway/leap/stagger motion")
	ok(c.buttons_shown and c.letter_count() == c.winner_name.length(),"reduced victory uses short fades without letter motion")
	ok(c.particle_limit() == 0,"reduced motion disables every cinematic particle")
	ok(c.live_particle_count(.5) == 0 and c.live_particle_count(.9) == 0,"reduced motion disables landing and second burst")
	ui.settings.values.reduced_motion = false; ui._apply_preferences()
func check_flip(art):
	var r: Rect2 = art.texture_rect(); var mirrored: Rect2 = art.mirror_transform()*r
	ok(r.size.x > 0 and r.size.y > 0 and mirrored.size.x > 0 and mirrored.size.y > 0,"renderer never receives a negative-width texture rect")
	ok(art.mirror_transform().determinant() < 0 and mirrored.is_equal_approx(r),"reflection stays centred inside the same canvas")
	ok(art.visible_art_rect().has_area() and Rect2(Vector2.ZERO,art.size).encloses(art.visible_art_rect()),"flipped drawn area remains visible inside the clip")
func surfaces(ui):
	for h in R.DATA:
		ui.profile.data.character_id = h.id; ui.rival_character = R.DATA[(R.index_of(h.id)+1)%32].id
		for s in [Vector2(390,844),Vector2(867,553)]:
			ui.set_view_size(s); ui.start_game("computer",1,true)
			for side in [1,2]:
				var art = ui.field_heroes[side]
				ok(art.hero_id == ui.hero_for(side) and art.texture != null and art.bust,"all heroes in corners/scorecards/Duo "+h.id+str(s))
				if art.facing < 0: check_flip(art)
			ui.cinematic.show_scene("pop",h.id,ui.rival_character,1,ui.layout,4)
			if ui.cinematic.visible:
				ok(ui.cinematic.hero.texture != null and ui.cinematic.hero.hero_id == h.id and not ui.cinematic.region.intersects(ui.layout.board),"all hero claim pops safe "+h.id)
			ui.cinematic.clear()
		await frames(1)
func glyphs():
	ok(P.SANS.has_char(">".unicode_at(0)),"bundled move-history font contains replacement arrow")
	for value in ["•","‹","›"]: ok(P.SANS.has_char(value.unicode_at(0)),"bundled paging glyph exists "+value)
	var source = FileAccess.get_file_as_string("res://main/main.gd")
	ok(not "→" in source and "%s > %s" in source,"missing arrow removed from visible move list")
## Pixel regression when run with a display; the normal headless runner checks the
## exact positive draw rect + reflection transform above on the actual hero nodes.
func flip_render_probe():
	if DisplayServer.get_name() == "headless":
		print("FLIP_VISIBILITY transform/clip=PASS; real-pixel probe requires a display")
		return
	var viewport = SubViewport.new(); viewport.size = Vector2i(96,96); viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var art = Art.new(); art.size = Vector2(96,96); art.facing = -1; art.frozen = true; viewport.add_child(art)
	# Synthetic asymmetric alpha canvas avoids depending on producer art pixels.
	var image = Image.create(32,32,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
	for y in range(5,27):
		for x in range(2,12): image.set_pixel(x,y,Color.WHITE)
	art.texture = ImageTexture.create_from_image(image); art.queue_redraw()
	await frames(3); await RenderingServer.frame_post_draw
	var pixels = viewport.get_texture().get_image(); var left = 0; var right = 0
	for y in range(96):
		for x in range(96):
			if pixels.get_pixel(x,y).a > .5:
				if x < 48: left += 1
				else: right += 1
	ok(right > 100 and left == 0,"real flipped texture pixels visible in the correct half of its rect")
	viewport.queue_free(); await frames()
