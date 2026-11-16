extends SceneTree
const B = preload("res://tournament/bracket.gd")
const Session = preload("res://tournament/session.gd")
const View = preload("res://tournament/bracket_view.gd")
const Screen = preload("res://tournament/screen.gd")
const Roster = preload("res://characters/roster.gd")
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(n: int = 2):
	for i in range(n): await process_frame
func clean(path: String):
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
func make_session(tag: String):
	var path = "user://round5b-"+tag+".cfg"; clean(path)
	return Session.new(path)
func people(n: int) -> Array:
	var entries: Array = []
	for i in range(n): entries.append({"id":"p"+str(i),"name":"Player "+str(i),"hero_id":Roster.DATA[i].id})
	return entries
func run():
	model_cases()
	session_cases()
	await controller_cases()
	await responsive_and_motion()
	await champion_video()
	print("NINEWEAVE_ROUND5B ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func model_cases():
	for n in range(3,9):
		for seed_value in range(12):
			var model = B.generate(people(n),seed_value,"p0","p1")
			ok(B.valid(model),"valid portable bracket with "+str(n)+" entrants")
			var actual: Array = []; var player = -1; var rival = -1
			for i in range(model.rounds[0].size()):
				var game = model.rounds[0][i]
				ok(not (game.a.is_empty() and game.b.is_empty()),"no empty-vs-empty match")
				for id in [game.a,game.b]:
					if not id.is_empty(): actual.append(id)
				if "p0" in [game.a,game.b]: player = i
				if "p1" in [game.a,game.b]: rival = i
			ok(actual.size() == n and int(player/(model.rounds[0].size()/2)) != int(rival/(model.rounds[0].size()/2)),"rival seeded in opposite half with byes")
			var matches_played = 0
			for r in range(model.rounds.size()):
				for i in range(model.rounds[r].size()):
					var game = model.rounds[r][i]
					if game.resolved: continue
					ok(not B.apply_result(model,r,i,game.a).is_empty(),"result advances through byes")
					matches_played += 1
			ok(matches_played == n-1 and not model.champion.is_empty() and B.valid(model),"exactly n-1 played matches and one champion")
			ok(B.apply_result(model,0,0,"p0").is_empty(),"duplicate result rejected")
	ok(B.generate(people(2),1).is_empty() and B.generate(people(9),1).is_empty(),"supported size is 3 through 8")
	var duplicate = people(3); duplicate[2].id = duplicate[0].id
	ok(B.generate(duplicate,1).is_empty(),"duplicate entrant rejected")
	var m = B.generate(people(8),21,"p0","p1")
	for r in range(2):
		for i in range(m.rounds[r].size()):
			var game = m.rounds[r][i]
			B.apply_result(m,r,i,"p0" if "p0" in [game.a,game.b] else ("p1" if "p1" in [game.a,game.b] else game.a))
	ok(m.rounds[2][0].a in ["p0","p1"] and m.rounds[2][0].b in ["p0","p1"] and m.rounds[2][0].a != m.rounds[2][0].b,"both advancing rivals meet only in final")
func session_cases():
	var a = make_session("seed-a"); var b = make_session("seed-b")
	a.create("shard_jack",91); b.create("shard_jack",91)
	ok(a.active.model == b.active.model,"seed deterministically generates eight distinct heroes")
	ok(a.active.model.entrants.size() == 8 and a.active.model.entrants.has("james_ii") and a.active.model.entrants.has("shard_jack"),"player and canonical chess rival included")
	for round_index in range(3):
		ok(a.level() == ["Easy","Medium","Hard"][round_index],"difficulty rises each round")
		ok(a.current().round == round_index,"next round ready")
		a.finish(true); b.finish(true)
		ok(a.active == b.active,"CPU results deterministic after round "+str(round_index))
		ok(B.valid(a.active.model),"saved result topology valid")
	ok(a.active.status == "champion" and a.wins.shard_jack == 1 and a.total_trophies() == 1,"champion awards one per-hero trophy")
	ok(not a.finish(true) and a.total_trophies() == 1,"replayed result cannot duplicate trophy")
	var loaded = Session.new(a.path)
	ok(loaded.active.status == "champion" and loaded.wins.shard_jack == 1,"champion and trophies persisted together")
	loaded.abandon(); loaded = Session.new(a.path)
	ok(loaded.active.is_empty() and loaded.total_trophies() == 1,"abandon clears only active tournament")
	a.create("shard_jack",121); var before = a.active.model.duplicate(true)
	a.finish(false)
	ok(a.active.status == "eliminated" and a.current().is_empty() and a.active.round == 0,"single loss eliminates in quarterfinal")
	ok(not a.finish(true) and a.total_trophies() == 1,"eliminated hero cannot advance or earn a trophy")
	ok(Session.new(a.path).active.status == "eliminated","elimination persists")
	a.create("cryon",7); a.finish(true)
	loaded = Session.new(a.path)
	ok(loaded.active == a.active and loaded.current().round == 1 and loaded.opponent() == a.opponent(),"resume preserves seed, results, hero, opponent, round")
	a.abandon(); ok(Session.new(a.path).active.is_empty(),"abandon persisted")
	# Distribution proves rivalry is weighted, never an unconditional forced result.
	var rival_wins = 0
	for seed_value in range(200):
		var m = B.generate(people(4),seed_value)
		m.rounds[0][0].a = "rival"; m.rounds[0][0].b = "other"
		if a.cpu_winner(m,0,0,"rival") == "rival": rival_wins += 1
	ok(rival_wins > 125 and rival_wins < 190,"rival usually advances, with seeded upsets: "+str(rival_wins))
	# One damaged envelope cannot crash or restore a fabricated tournament.
	var cfg = ConfigFile.new(); cfg.set_value("tournament","active",{"hero":7,"model":before}); cfg.save(a.path)
	ok(Session.new(a.path).active.is_empty(),"invalid save rejected")
func make_ui(tag: String, fresh: bool = true):
	var prefix = "user://round5b-ui-"+tag
	if fresh:
		for suffix in [".cfg","-profile.cfg","-profile-tournament.cfg","-device.cfg"]: clean(prefix+suffix)
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.settings = Settings.new(prefix+".cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("shard_jack","Weaver")
	ui.account.store = DeviceStore.new(prefix+"-device.cfg")
	ui.account.store.keep_device("nwd_fixture","Weaver")
	ui.account.store.accept_consent("Weaver",DeviceStore.consent_payload()); ui.account.store.skip_email()
	var fake = Fake.new(); ui.account.api.request_factory = func(): return fake
	var lobby = Fake.new(); ui.online_api.request_factory = func(): return lobby
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844))
	ui.tournament.video_seen = true
	return {"ui":ui,"http":fake,"lobby":lobby}
func settle(ui):
	if is_instance_valid(ui.tournament.screen) and is_instance_valid(ui.tournament.screen.bracket): ui.tournament.screen.bracket.seek(5)
func win_match(ui, winner: int = 1):
	ui.thinking = false; ui.cinematic.clear(); ui.overlay = ""; ui.settings.values.tutorial_completed = true
	var patterns: Array = []
	for i in range(9): patterns.append(".........")
	patterns[0] = "XXXOO...." if winner == 1 else "OOOXX...."; patterns[1] = patterns[0]
	patterns[2] = "XX.OO...." if winner == 1 else "OO.XX...."
	ok(ui.game.deserialize({"v":1,"cells":"".join(patterns),"turn":winner,"active":2,"history":[]}),"legal staged match loads")
	ok(ui._apply_move(2,2),"normal move ends tournament match")
func controller_cases():
	var bundle = make_ui("flow"); var ui = bundle.ui
	ok(ui.controls.has_all(["computer","tournament","online","local"]),"Tournament added alongside existing modes")
	ui.controls.tournament.pressed.emit()
	ok(ui.page == "character_select" and ui._pending_game.mode == "tournament","Tournament uses existing hero selection")
	ui.hero_select._confirm()
	ok(ui.page == "tournament" and ui.tournament.session.active.hero == "shard_jack","hero lock-in enters bracket")
	ui.settings.values.tutorial_completed = false; ui.test_online_bypass = false
	settle(ui); ui.controls.play.pressed.emit()
	ok(ui.mode == "computer" and ui.tournament.match_active and ui.cinematic.kind == "versus","normal computer flow and hero intro used")
	ok(ui.rival_character == ui.tournament.session.opponent(),"bracket opponent retained through start_game")
	ui.cinematic.advance(.81); ui.cinematic.skip()
	ok(ui.tutorial.active,"first-run tutorial is unchanged")
	ui.tutorial.skip(); ui.test_online_bypass = true
	win_match(ui)
	ok(ui.tournament.recorded and ui.tournament.session.active.round == 1,"normal match win persists immediately before cutscene")
	ok(not ui.undo_move() and ui.game.status == 1,"completed tournament result cannot be undone after saving")
	ui._show_spotlight()
	ok(ui.cinematic.kind == "spotlight" and ui.cinematic.winner_id == "shard_jack","normal winner layer retained")
	ui.cinematic.complete(); ui._winner_controls(ui.layout.size)
	ok(ui.controls.again.caption == "VIEW BRACKET","result action continues tournament instead of starting a quick rematch")
	ui.controls.again.pressed.emit()
	ok(ui.page == "tournament" and not ui.tournament.screen.bracket.results.is_empty(),"bracket receives reusable result animation batch")
	settle(ui); ui.controls.play.pressed.emit()
	ui.cinematic.advance(.81); ui.cinematic.skip(); ui.game.turn = 2; ui._schedule_ai()
	ok(ui.ai.difficulty == "Medium" and ui.settings.values.difficulty == "Hard","round overrides AI without changing quick-match preference")
	ui.thinking = false
	# Reload mid-match returns to bracket and restarts this same matchup, no board cheat-save.
	var expected_opponent = ui.rival_character
	ui.free(); await frames()
	bundle = make_ui("flow",false); ui = bundle.ui
	ok(ui.page == "tournament" and ui.tournament.session.opponent() == expected_opponent,"closing mid-match resumes at bracket with same opponent")
	settle(ui); ui.controls.play.pressed.emit(); win_match(ui)
	ui.tournament.after_match(); settle(ui); ui.controls.play.pressed.emit()
	ui.cinematic.advance(.81); ui.cinematic.skip(); ui.game.turn = 2; ui._schedule_ai()
	ok(ui.ai.difficulty == "Hard","final uses strongest existing strategist")
	win_match(ui); ui.tournament.after_match()
	ok(ui.page == "tournament" and ui.tournament.screen.data.status == "champion","final win opens champion screen")
	ok(ui.tournament.session.total_trophies() == 1 and Session.new(ui.tournament.session.path).total_trophies() == 1,"champion trophy survives controller reload")
	ui.controls.retry.pressed.emit()
	ok(ui.tournament.session.active.hero == "shard_jack" and ui.tournament.session.active.round == 0 and ui.tournament.session.total_trophies() == 1,"Try again uses same hero, fresh bracket, retains trophy")
	settle(ui); ui.controls.play.pressed.emit(); win_match(ui,2); ui.tournament.after_match()
	ok(ui.tournament.screen.data.status == "eliminated" and ui.controls.has_all(["retry","menu"]),"loss shows elimination and both exit actions")
	ui.controls.retry.pressed.emit(); ui.controls.abandon.pressed.emit()
	ok(ui.tournament.screen.confirm_abandon and not ui.tournament.session.active.is_empty(),"abandon requires confirmation")
	ui.tournament.screen.controls.cancel_abandon.pressed.emit()
	ok(not ui.tournament.screen.confirm_abandon and not ui.tournament.session.active.is_empty(),"cancel preserves bracket")
	ui.controls.abandon.pressed.emit(); ui.tournament.screen.controls.confirm_abandon.pressed.emit()
	ok(ui.page == "title" and ui.tournament.session.active.is_empty(),"confirmed abandonment returns to menu")
	ui.open_character_select()
	var found = false
	for tile in ui.hero_select.portraits:
		if Roster.DATA[tile.index].id == "shard_jack": found = tile.trophies == 1
	ok(found,"hero select card displays persisted trophy count")
	ui.go_home(); ui.request_game("computer"); ui.hero_select._confirm()
	ok(ui.page == "game" and ui.mode == "computer" and not ui.tournament.match_active,"quick computer match still works")
	ui.go_home(); ui.tournament.create("shard_jack",91); settle(ui); ui.tournament.play()
	var unchanged = ui.tournament.session.active.duplicate(true)
	var same_opponent = ui.rival_character
	ui.game.status = 3; ui._save_match(); ui.tournament.after_match()
	ok(ui.tournament.session.active == unchanged and ui.rival_character == same_opponent,"a draw replays the same match without changing the bracket")
	ok(ui.tournament.match_active and ui.game.status == 0 and ui.cinematic.kind == "versus","draw replay retains normal intro and match flow")
	ok(bundle.http.requests.is_empty() and bundle.lobby.requests.is_empty(),"whole tournament flow sends no network requests")
	ui.free(); await frames()
func responsive_and_motion():
	var bundle = make_ui("layout"); var ui = bundle.ui
	ui.tournament.create("shard_jack",91)
	for dims in [Vector2(390,844),Vector2(1366,768)]:
		for stage in ["bracket","champion","eliminated"]:
			ui.tournament.session.active.status = stage; ui.page = "tournament"; ui.set_view_size(dims); await frames()
			var screen = ui.tournament.screen; screen.set_process(false)
			var bounds = Rect2(Vector2.ZERO,dims)
			var keys = ["eyebrow","title","subtitle","primary","secondary"]
			keys.append_array(["bracket","preview","menu"] if stage == "bracket" else ["hero","trophy","name","count"])
			for key in keys: ok(bounds.encloses(screen.geo[key]),stage+" "+key+" inside "+str(dims))
			for a in range(keys.size()):
				for b in range(a+1,keys.size()): ok(not screen.geo[keys[a]].intersects(screen.geo[keys[b]]),"no overlap: "+stage+" "+keys[a]+" / "+keys[b]+str(dims))
			for button in screen.controls.values(): ok(button.size.y >= 44 and bounds.encloses(button.get_global_rect()),"touch target fits")
			if stage == "bracket":
				for round_cards in screen.bracket.geo.cards:
					for card in round_cards: ok(Rect2(Vector2.ZERO,screen.bracket.size).encloses(card),"bracket card inside canvas")
	ui.tournament.session.active.status = "bracket"; ui.tournament.session.finish(true)
	ui.tournament.pending_events = ui.tournament.session.last_events; ui.tournament.show()
	var view = ui.tournament.screen.bracket; view.set_process(false); view.seek(.25)
	ok(not view.settled() and view.progress(0) > 0 and view.progress(0) < 1,"advance supports a deterministic mid-animation frame")
	view.reduced_motion = true; view.seek(0)
	ok(view.settled() and view.progress(0) == 1,"reduced motion settles all results immediately")
	# Test future online clients with opaque IDs, partial live results, and all bye sizes.
	for n in range(3,9):
		for dims in [Vector2(358,470),Vector2(900,500)]:
			var generic = View.new(); generic.size = dims; generic.reduced_motion = true; root.add_child(generic)
			var model = B.generate(people(n),31,"p0")
			generic.present(model,[],"p0"); await frames()
			ok(generic.model.entrants.size() == n and generic.settled(),"reusable view renders "+str(n)+" participants with byes")
			var match_data = B.next_match(model,"p0")
			if not match_data.is_empty():
				var result = B.apply_result(model,match_data.round,match_data.index,"p0")
				generic.present(model,[result],"p0"); ok(generic.model != {} and generic.settled(),"live result batch accepted without local session")
			# A complete tournament replays all player advance paths, including
			# the final flight into the crown. Sample both layouts densely.
			for r in range(model.rounds.size()):
				for i in range(model.rounds[r].size()):
					var game = model.rounds[r][i]
					if game.resolved: continue
					var winner = "p0" if "p0" in [game.a,game.b] else game.a
					var result = B.apply_result(model,r,i,winner)
					if winner == "p0":
						generic.reduced_motion = false; generic.present(model,[result],"p0")
						for step in range(21):
							generic.seek(View.ADVANCE_SECONDS*step/20.0)
							var pose = generic.advance_pose(0)
							var extent = Rect2(pose.position-Vector2.ONE*(pose.radius+1),Vector2.ONE*(pose.radius+1)*2)
							ok(Rect2(Vector2.ZERO,dims).encloses(extent),"moving portrait stays inside reusable view "+str(n)+" "+str(dims)+" round "+str(r))
			generic.free()
	ui.free(); await frames()
func champion_video():
	var bundle = make_ui("champion-video"); var ui = bundle.ui
	for hero in ["max_granite","shard_jack"]:
		ui.tournament.session.create(hero,91)
		for round_index in range(3): ui.tournament.session.finish(true)
		ui.tournament.video_seen = false; ui.tournament.show()
		var screen = ui.tournament.screen; screen.set_process(false)
		for dims in [Vector2(390,844),Vector2(1366,768)]:
			screen.geo = Screen.geometry(dims,"champion")
			for step in range(31):
				var trophy = screen.trophy_pose(step/30.0)
				ok(Rect2(Vector2.ZERO,dims).encloses(trophy),"trophy drop fits viewport")
				for key in ["title","subtitle","hero","name","count","primary","secondary"]: ok(not trophy.intersects(screen.geo[key]),"trophy drop never overlaps "+key)
		screen.geo = Screen.geometry(ui.layout.size,"champion")
		screen.age = 1; screen._process(0)
		# Round 5v supplies victory clips for both heroes, including Jack.
		ok(screen.video_overlay.visible,"champion plays available victory clip for "+hero)
		ok(screen.video_overlay.scene_kind == "spotlight" and screen.video_overlay.sides[0].kind == "victory","champion uses existing victory video layer")
		ok(screen.video_overlay.mouse_filter == Control.MOUSE_FILTER_STOP,"video shields Try Again and Main Menu")
		var release = InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
		screen._video_input(release)
		ok(not screen.video_overlay.visible and ui.tournament.session.active.status == "champion","clip skip reveals champion without activating another run")
		# Explicitly simulate missing/download-pending media with the full roster.
		ui.tournament.video_seen = false; ui.tournament.show()
		screen = ui.tournament.screen; screen.set_process(false); screen.video_overlay.source = null
		screen.age = 1; screen._process(0)
		ok(not screen.video_overlay.visible and screen.data.status == "champion" and screen.controls.has_all(["retry","menu"]),"unavailable clip keeps illustrated champion and outcome controls")
		ui.settings.values.reduced_motion = true; ui.tournament.video_seen = false; ui.tournament.show()
		screen = ui.tournament.screen; screen.set_process(false); screen.age = 1; screen._process(0)
		ok(not screen.video_overlay.visible and screen.reduced_motion,"reduced motion skips champion video and drop")
		ui.settings.values.reduced_motion = false
	ok(bundle.http.requests.is_empty() and bundle.lobby.requests.is_empty(),"champion media tests have no network requests")
	ui.free(); await frames()
