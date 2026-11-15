extends SceneTree
const Main = preload("res://main/main.tscn")
const R = preload("res://characters/roster.gd")
const Art = preload("res://characters/art.gd")
const Select = preload("res://characters/select.gd")
const Cinema = preload("res://characters/cinematic.gd")
const Layout = preload("res://ui/layout.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://settings/store.gd")
const Loopback = preload("res://net/loopback_transport.gd")
const Reactions = preload("res://characters/reactions.gd")
const F = preload("res://tests/fixtures.gd")
const SIZES = [[360,640],[390,664],[390,844],[867,553],[1366,1024],[568,320],[669,787],[768,1024],[390,620],[430,932],[844,390],[2601,1659]]
var checks = 0
var failures = 0
func ok(value: bool, message: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func frames(count: int = 2):
	for i in range(count): await process_frame
func run():
	ok(Art.textures.is_empty(),"no illustrated texture eagerly preloaded")
	roster_assets()
	var ui = Main.instantiate(); ui.profile = Profile.new("user://r4-main-profile.cfg"); ui.settings = Store.new("user://r4-main-settings.cfg")
	ui.profile.data.character_id = "cryon"; ui.profile.data.display_name = "Patrick"; ui.profile.data.onboarded = true
	ui.settings.values.sound = false; ui.settings.values.player_name = "Patrick"; ui.settings.values.reduced_motion = false
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	await selection(ui)
	versus_flow(ui)
	winner_flow(ui)
	await capture_scenarios(ui)
	await corners(ui)
	reactions(ui)
	await online_flow(ui)
	ui.go_home(); ui.queue_free(); await frames(3)
	print("NINEWEAVE_ROUND4 ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func roster_assets():
	var order = ["cryon","aurelia","vesper_vale","auric_rex","nyx_thread","cobalt_bastion","ember_quill","lumen_pike","shard_jack","madame_solstice","bramble_ox","kite_hollow","professor_gilt","siren_coil","ryan_blaze","tempest_vega"]
	var ids = {}
	ok(R.DATA.size() == 16,"16 heroes")
	for i in range(R.DATA.size()):
		var hero = R.DATA[i]; ids[hero.id] = true
		ok(hero.id == order[i],"approved display order "+hero.id)
		for key in ["splash","versus","victory","head_neutral","head_smug","head_panic","head_doubletake","head_eyeroll","head_cheer","head_pout"]:
			var tex = Art.get_texture(hero.id,key)
			ok(tex is Texture2D and tex.get_width() > 0 and tex.get_height() > 0,"load "+hero.id+"/"+key)
			if key.begins_with("head_"): ok(tex.get_size() == Vector2(256,256),"unchanged head canvas "+hero.id+key)
			var cfg = ConfigFile.new(); cfg.load("res://assets/heroes/%s/%s.webp.import" % [hero.id,key])
			ok(cfg.get_value("params","compress/mode") == 1 and cfg.get_value("params","compress/lossy_quality") == .85 and not cfg.get_value("params","mipmaps/generate"),"hero-only lossy settings "+hero.id+key)
	for i in range(R.AUDIO_IDS.size()): ok(R.audio_index(R.AUDIO_IDS[i]) == i,"original audio motif retained "+R.AUDIO_IDS[i])
	for id in ["cryon","aurelia","ryan_blaze","tempest_vega"]: ok(R.audio_index(id) in range(12),"new hero reuses existing audio "+id)
	ok(ids.size() == 16 and R.get_hero("shard_jack").name == "Jack Riot","unique stable IDs and Jack rename")
	ok(not "she" in R.get_hero("kite_hollow").defeat and R.get_hero("siren_coil").body == "diver","updated concepts")
	ok(R.valid(R.get_hero("bad-id").id) and Art.get_texture("bad-id","head_neutral") != null,"unknown renderer ID safe fallback")
	var path = "user://r4-corrupt-profile.cfg"; var cfg = ConfigFile.new()
	cfg.set_value("profile","character_id","removed-hero"); cfg.save(path)
	ok(R.valid(Profile.new(path).data.character_id),"unknown saved ID safe fallback")
func visible_tiles(select) -> Array:
	return select.portraits.filter(func(tile): return tile.visible)
func selection(ui):
	for entry in SIZES:
		var s = Layout.logical_size(Vector2(entry[0],entry[1])); ui.set_view_size(s); ui.request_game("computer")
		var select = ui.hero_select; var phone = Layout.mode_for(s) == "phone_portrait"
		ok(select.geo.paged == phone and select.geo.per_page == (8 if phone else 16),"select mode "+str(s))
		ok(visible_tiles(select).size() == (8 if phone else 16),"visible count "+str(s))
		ok(select.paging_controls.size() == (4 if phone else 0),"arrows and dots only on phone "+str(s))
		for p in range(2 if phone else 1):
			select.set_page(p)
			for tile in visible_tiles(select):
				ok(tile.size.x >= 44 and tile.size.y >= 44 and Rect2(Vector2.ZERO,s).encloses(tile.get_rect()),"tile touch and viewport %s %d" % [s,tile.index])
		if phone:
			select.set_page(0); select.paging_controls[1].pressed.emit(); ok(select.page == 1,"next arrow")
			select.paging_controls[0].pressed.emit(); ok(select.page == 0,"previous arrow")
			select.paging_controls[3].pressed.emit(); ok(select.page == 1,"second page dot")
			select.paging_controls[2].pressed.emit(); ok(select.page == 0,"first page dot")
			var press = InputEventScreenTouch.new(); press.pressed = true; press.position = Vector2(280,440); select._input(press)
			var release = InputEventScreenTouch.new(); release.pressed = false; release.position = Vector2(100,440); select._input(release)
			ok(select.page == 1,"real touch swipe")
			select.swipe(Vector2(100,0)); ok(select.page == 0,"right swipe")
			select.change_page(-1); ok(select.page == 1,"page wraps consistently")
		await frames(1)
	ui.set_view_size(Vector2(390,844)); ui.request_game("local")
	ok(ui.hero_select.heading.begins_with("PLAYER 1"),"P1 select header")
	ui.hero_select.focus_hero("shard_jack"); ui.hero_select._confirm()
	ok(ui.page == "character_select" and ui.hero_select.heading.begins_with("PLAYER 2"),"P2 separately picks")
	ui.hero_select.focus_hero("shard_jack")
	ok(ui.hero_select.selected_id != "shard_jack" and ui.hero_select.portraits[8].disabled,"P2 cannot take P1 hero")
	ui._confirm_hero("shard_jack","PLAYER 2"); ok(ui.page == "character_select","controller also rejects duplicate P2")
	ui.hero_select.focus_hero("ryan_blaze"); ui.hero_select._confirm()
	ok(ui.mode == "local" and ui.cinematic.kind == "versus" and ui.hero_for(1) == "shard_jack" and ui.hero_for(2) == "ryan_blaze","two picks enter versus")
	ui.cinematic.advance(2.81)
	var p1 = ui.hero_for(1); var p2 = ui.hero_for(2)
	ui.game.status = 1; ui.overlay = "result"; ui._rebuild(); ui.controls.again.pressed.emit()
	ok(ui.human_mark == 2 and ui.game.turn == 1 and ui.game.history.is_empty(),"one-tap pass-and-play rematch swaps X/O and X starts")
	ok(ui.hero_for(1) == p2 and ui.hero_for(2) == p1 and ui.side_name(1) == "PLAYER 2","heroes and names stay with players")
	ok(ui.cinematic.active and ui.cinematic.kind == "versus","rematch plays versus again")
	ui.cinematic.advance(2.81); ok(ui.play_cell(4,4) and ui.game.cells[40] == 1,"new X moves first")
	ui.request_online(); ok(ui.page == "online" and ui.hero_select == null,"online bypasses select")
func versus_flow(ui):
	for s in [Vector2(390,844),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(s); ui.request_game("computer",1); ui._confirm_hero("vesper_vale","Patrick")
		ok(ui.cinematic.kind == "versus" and ui.rival_character != "vesper_vale","computer pick gets different random rival")
		ok(ui.cinematic.duration() >= 2.5 and ui.cinematic.duration() <= 3,"versus duration")
		ok(ui.cinematic.arrangement == ("vertical" if s.x < s.y else "horizontal"),"versus arrangement")
		ok(ui.cinematic.hero.art_key == "versus" and ui.cinematic.loser.art_key == "versus" and ui.cinematic.mouse_filter == Control.MOUSE_FILTER_STOP,"versus full-body art and modal shield")
		ok(not ui.play_cell(4,4) and not ui.cinematic.skip(),"early skip and board input guarded")
		ui.cinematic.advance(.59); ok(not ui.cinematic.skip(),"skip unavailable before 600ms")
		ui.cinematic.advance(.02); ok(ui.cinematic.skip() and not ui.board.frozen,"versus skip starts match")
		ui.rematch(); ui.cinematic.advance(2.79); ok(ui.cinematic.active and ui.game.history.is_empty(),"holds until 2.8 seconds")
		ui.cinematic.advance(.02); ok(not ui.cinematic.active and not ui.board.frozen,"automatic start at 2.8 seconds")
	ui.thinking = false; ui.go_home()
func winner_flow(ui):
	ui.set_view_size(Vector2(390,844)); ui.profile.data.character_id = "shard_jack"; ui.rival_character = "ryan_blaze"
	ui.settings.values.player_name = "Patrick"; ui.opponent_name = "Dana"
	for case in [["computer",1,1,"PATRICK WINS!","shard_jack"],["computer",1,2,"RIVAL AI WINS!","ryan_blaze"],["local",1,2,"PLAYER 2 WINS!","ryan_blaze"],["local",2,1,"PLAYER 2 WINS!","ryan_blaze"],["online",1,2,"DANA WINS!","ryan_blaze"]]:
		ui.debug_load_position(F.big_tactic(case[2]).serialize(),case[0]); ui.human_mark = case[1]; ui.game.play(2,2)
		ui._show_spotlight()
		ok(ui.cinematic.winner_caption() == case[3] and ui.cinematic.hero.hero_id == case[4],"winner identity "+case[3])
		ok(ui.cinematic.hero.art_key == "victory" and ui.cinematic.duration() == 5,"victory pose and 5-second cutscene")
		ui.cinematic.advance(.79); ok(not ui.cinematic.skip() and not ui.controls.has("again"),"winner short protected entrance")
		ui.cinematic.advance(.02); ok(ui.cinematic.skip() and ui.controls.has_all(["again","menu"]),"tap skips to buttons after 800ms")
		ok(ui.cinematic.visible and not ui.cinematic.active,"victory art persists behind buttons")
		ui.controls.menu.pressed.emit(); ok(ui.page == "title" and not ui.cinematic.visible,"main menu button works")
	ui.debug_scenario("winner",.25); ui.cinematic.frozen = false
	ok(not ui.controls.has("again"),"buttons hidden during entrance")
	ui.cinematic.advance(.56); ok(ui.cinematic.buttons_shown and ui.controls.has("again"),"buttons appear at 1.8s")
	ui.cinematic.advance(4); ok(not ui.cinematic.active and ui.cinematic.visible,"5s beat settles into persistent result")
	ui.set_view_size(Vector2(867,553))
	ok(ui.cinematic.hero_rect == Cinema.card_geometry(Vector2(867,553),"spotlight").hero and ui.cinematic.arrangement == "horizontal","settled winner relayouts on rotation")
	ui.set_view_size(Vector2(390,844))
	ui.controls.again.pressed.emit(); ok(ui.cinematic.kind == "versus" and ui.game.status == 0,"winner rematch starts clean game through versus")
	ui.debug_scenario("draw",.6)
	ok(ui.game.status == 3 and ui.cinematic.kind == "draw" and ui.cinematic.winner_caption() == "DRAW" and ui.cinematic.loser.visible,"draw standoff with both heroes")
	ok(ui.controls.has_all(["again","menu"]),"draw has both actions")
	ui.controls.menu.pressed.emit()
func capture_scenarios(ui):
	# Validate all 28 capture fixtures even when the sandbox cannot open a display.
	for s in [Vector2(390,844),Vector2(390,664),Vector2(867,553),Vector2(1366,1024)]:
		ui.set_view_size(s)
		for scene in ["select_p1","select_p2","versus","midgame_heads","winner","winner_cpu","draw"]:
			ui.debug_scenario(scene,.6); ui.debug_refresh()
			ok(ui.page in ["game","character_select"],"capture fixture runs %s %s" % [s,scene])
			if scene in ["winner","winner_cpu","draw"]:
				ok(ui.controls.has_all(["again","menu"]) and ui.cinematic.visible,"capture result art and actions %s %s" % [s,scene])
				for id in ["again","menu"]:
					var rect = ui.controls[id].get_rect()
					ok(Rect2(Vector2.ZERO,s).encloses(rect) and rect.size.x >= 44 and rect.size.y >= 44,"result touch bounds %s %s" % [s,id])
			await frames(1)
func corners(ui):
	for entry in SIZES:
		var s = Layout.logical_size(Vector2(entry[0],entry[1])); ui.set_view_size(s); ui.start_game("computer")
		var layout = Layout.compute(s); ok(ui.layout.board == layout.board,"board rect identical "+str(s))
		for mark in [1,2]:
			var rig = ui.field_heroes[mark]; var rect = rig.get_rect()
			ok(rig.get_script() == Art and rig.bust and rig.texture != null,"only illustrated heads in match")
			ok(not rect.intersects(layout.board) and rig.clip_contents and rig.mouse_filter == Control.MOUSE_FILTER_IGNORE,"clipped nonblocking head off board "+str(s))
			var corner: Rect2 = layout.hero_player if mark == ui.human_mark else layout.hero_opponent
			if corner.size.y >= Layout.MIN_CORNER and layout.get("hero_player_host","") != "character":
				ok(rect.is_equal_approx(corner),"reuses approved corner region %s %s %s" % [s,rect,corner])
				for key in ["board","players","turn","info","controls","message","minimap","stats"]:
					if layout.has(key) and layout[key].has_area(): ok(not rect.intersects(layout[key]),"corner misses HUD "+key+str(s))
			elif not corner.has_area(): ok(rect != corner,"no room: no standalone corner drawn")
		await frames(1)
	ui.go_home()
func reactions(ui):
	var art = Art.new(); art.hero_id = "ryan_blaze"; root.add_child(art); art.set_process(false)
	for event in ["own_claim","opponent_claim","win","loss","near_loss"]:
		art.reaction = Reactions.new(); art.expression = "neutral"; art.react(event)
		art.advance(.30)
		var want = {"own_claim":"smug","opponent_claim":"pout","win":"cheer","loss":"pout","near_loss":"panic"}[event]
		ok(art.expression == want and art.texture == Art.get_texture("ryan_blaze","head_"+want),"reaction face "+event)
		art.advance(1.5); ok(art.expression == "neutral","returns to neutral "+event)
	art.reduced_motion = true; art.reaction = Reactions.new(); art.react("opponent_claim")
	ok(art.expression == "pout" and art._delay == 0,"reduced motion instant face swap")
	art.advance(8); ok(art.expression == "neutral","reduced motion has no idle beat")
	art.reduced_motion = false; art.advance(9); ok(art.expression in ["smug","eyeroll"],"subtle occasional idle beat")
	art.queue_free()
	ui.set_view_size(Vector2(390,844)); ui.debug_load_position(F.big_tactic(1).serialize(),"local")
	ui._apply_move(2,2)
	ui.cinematic.show_scene("pop",ui.hero_for(1),ui.hero_for(2),1,ui.layout,2)
	ok(not ui.cinematic.front.visible,"claim pop hides cached full-screen lettering")
	for mark in [1,2]:
		ui.field_heroes[mark].advance(.3)
		ok(ui.field_heroes[mark].expression == ("cheer" if mark == 1 else "pout"),"game result drives correct corner face")
func online_flow(ui):
	ui.go_home(); Loopback.reset_service()
	var seats = {}
	for seed_value in range(1,17):
		Loopback.assignment_rng.seed = seed_value
		var a = Loopback.new(); var b = Loopback.new(); root.add_child(a); root.add_child(b)
		a.character_id = "shard_jack"; b.character_id = "ryan_blaze"
		a.create_room(); b.join_room(a.code); seats[a.seat] = true
		ok(a.seat in [1,2] and b.seat == 3-a.seat,"seeded initial sides")
		a.request_rematch(); ok(not a.local_rematch,"cannot rematch an unfinished game")
		var initial = a.seat
		for round_index in range(2,5):
			var room = Loopback.rooms[a.code]; room.game = F.big_tactic(1); room.game.play(2,2)
			a.request_rematch(); a.request_rematch()
			ok(a.local_rematch and not a.remote_rematch and a.rematch_status() == "WAITING FOR OPPONENT…","own request waits")
			ok(b.remote_rematch and not b.local_rematch and b.rematch_status() == "OPPONENT WANTS A REMATCH","peer sees accept state")
			ok(room.round == round_index-1 and room.game.status != 0,"one agreement cannot restart")
			var old_seat = a.seat; b.request_rematch()
			ok(a.seat == 3-old_seat and b.seat == old_seat and a.match_round == round_index,"both agree: swap sides each round")
			ok(room.game.turn == 1 and room.game.history.is_empty() and room.seq == 0,"authoritative fresh X-first match")
			ok(a.remote_character_id == "ryan_blaze" and b.remote_character_id == "shard_jack","online heroes stay with players")
			ok(not a.local_rematch and not b.remote_rematch,"agreements cleared")
		ok(a.seat == 3-initial,"three rematches swap three times")
		a.leave(); a.free(); b.free()
	ok(seats.size() == 2,"first assignment random across fixed seeds")
	Loopback.assignment_rng.seed = 18; ui.request_online(); ui.create_online(true); ui.invite_demo_rival(); await frames(1)
	ok(ui.mode == "online" and ui.cinematic.kind == "versus","online enters versus with profile hero")
	ui.cinematic.advance(2.81); ui.thinking = false
	var old_mark = ui.human_mark; var room = Loopback.rooms[ui.room_code]
	room.game = F.big_tactic(1); room.game.play(2,2); ui.game.deserialize(room.game.serialize()); ui._show_spotlight(); ui.cinematic.advance(5.1)
	ui.controls.again.pressed.emit()
	ok(ui.transport.local_rematch and ui.controls.again.disabled and ui.transport.rematch_status() == "WAITING FOR OPPONENT…","real result UI waits for peer")
	ui.demo_rival.request_rematch()
	ok(ui.human_mark == 3-old_mark and ui.game.turn == 1 and ui.cinematic.kind == "versus","transport agreement reaches main controller")
	# Opponent-first request must expose ACCEPT on the actual winner screen.
	ui.cinematic.advance(2.81); ui.thinking = false
	room = Loopback.rooms[ui.room_code]; room.game = F.big_tactic(1); room.game.play(2,2)
	ui.game.deserialize(room.game.serialize()); ui._show_spotlight(); ui.cinematic.advance(5.1)
	ui.demo_rival.request_rematch()
	ok(ui.transport.remote_rematch and ui.controls.again.caption == "ACCEPT" and not ui.controls.again.disabled,"opponent-first request exposes accept button")
	ui.controls.again.pressed.emit()
	ok(ui.game.status == 0 and ui.cinematic.kind == "versus" and ui.human_mark == old_mark,"accept alone supplies second agreement and swaps back")
	ui.go_home(); Loopback.reset_service(); await frames(2)
