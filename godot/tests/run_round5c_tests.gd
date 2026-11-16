extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Device = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const F = preload("res://tests/round5c_fixtures.gd")
const Model = preload("res://tournament/online_model.gd")
const Cinema = preload("res://characters/cinematic.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(n: int = 2):
	for i in range(n): await process_frame
func make_ui(tag: String):
	var prefix = "user://r5c-"+tag
	for suffix in ["-settings.cfg","-profile.cfg","-device.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("shard_jack","Weaver")
	ui.account.store = Device.new(prefix+"-device.cfg"); ui.account.store.keep_device("nwd_r5c_device","Weaver")
	ui.account.store.accept_consent("Weaver",Device.consent_payload()); ui.account.store.skip_email()
	var bundle = {"ui":ui,"fakes":[]}
	ui.http_request_factory = func():
		var fake = Fake.new(); bundle.fakes.append(fake); return fake
	ui.account.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.online_tournament.set_process(false); ui.set_view_size(Vector2(390,844))
	return bundle
func pending(b, fragment: String):
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and fragment in fake.requests.back().url: return fake
	return null
func reply(b, fragment: String, data, response: int = 200):
	var fake = pending(b,fragment)
	ok(fake != null,"pending mocked endpoint "+fragment)
	if fake != null: fake.respond(response,data)
func clean(b):
	b.ui.go_home()
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and "/leave" in fake.requests.back().url: fake.respond(200,{"ok":true})
	b.ui.free(); await frames()
func run():
	await media()
	await streamed_pair()
	await fallback_and_requests()
	await tournament_lifecycle()
	await responsive()
	print("NINEWEAVE_ROUND5C ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func media():
	var b = make_ui("media"); var ui = b.ui; ui.rival_character = "james_ii"
	ui.start_game("computer",1,true,true)
	var cinema = ui.cinematic; var overlay = cinema.video_overlay
	ok(overlay.sides.size() == 2 and overlay.sides[0].id == "shard_jack" and overlay.sides[1].id == "james_ii","player left and opponent right")
	ok(overlay.sides[0].video and overlay.sides[1].video,"two native intro streams prepared together")
	ok(overlay.sides[0].frame.end.x < overlay.sides[1].frame.position.x,"simultaneous videos occupy separate lanes")
	ok(overlay.sides[0].node.buffering_msec == 500 and overlay.sides[1].node.buffering_msec == 100,"normal audible-lane buffer and bounded silent-lane buffer")
	cinema.advance(.9); cinema.skip()
	for winner in [1,2]:
		ui.game.status = winner; ui._show_spotlight()
		ok(cinema.combined_result and cinema.video_playing() and ui.controls.has_all(["again","menu"]),"video and end controls share one screen immediately")
		ok(cinema.winner_id == ui.hero_for(winner) and overlay.sides[0].id == ui.hero_for(winner),"actual winner supplies victory clip")
		ok(cinema.result_title == ("VICTORY" if winner == 1 else "DEFEAT"),"matching result heading")
		var g = cinema.result_geometry(ui.layout.size)
		ok(g.hero.end.x < g.outcome.position.x and not g.hero.intersects(g.again),"left video leaves text and buttons visible")
		var button_pos = ui.controls.again.position
		overlay.sides[0].node.finished.emit()
		ok(ui.overlay == "result" and ui.controls.again.position == button_pos and cinema.combined_result,"completion keeps the same combined screen")
		ok(overlay.holds_completed_result() and not cinema.active and cinema.video_playing(),"completed victory holds its final video texture")
		var held_player = overlay.sides[0].node
		ui.set_view_size(Vector2(844,390)); cinema.advance(100)
		ok(overlay.sides[0].node == held_player and held_player.stream != null and overlay.sides[0].node.volume == 0,"resize and time preserve silent final frame")
		ui.set_view_size(Vector2(390,844))
	var old_player = overlay.sides[0].node
	ok(is_finite(cinema.duration()),"held result does not create infinite animation duration")
	ui.controls.again.pressed.emit()
	ok(not overlay.holds_completed_result() and old_player.stream == null,"Play Again releases held video before next match")
	ui.cinematic.video_source = null; ui.game.status = 1; ui._show_spotlight()
	ok(cinema.combined_result and cinema.hero.visible and ui.controls.has("again"),"missing victory retains still art plus result controls")
	await clean(b)
func streamed_pair():
	var video = preload("res://characters/hero_video.gd").new(); video.bundled_override = 0
	video.cache.root_path = "user://r5c-sidecars-"+str(Time.get_ticks_usec())
	var fakes: Array = []
	video.cache.request_factory = func():
		var fake = Fake.new(); fakes.append(fake); return fake
	root.add_child(video); video.cache.set_process(false)
	# Selection may already occupy both slots with the player's intro + victory.
	video.prefetch_hero("shard_jack"); video.prefetch_pair("shard_jack","james_ii")
	var active: Array = []
	for fake in fakes:
		if is_instance_valid(fake) and fake.active: active.append(fake)
	ok(active.size() == 2 and active[0].requests.back().url.ends_with("/intro.ogv") and active[1].requests.back().url.ends_with("/intro.ogv"),"both streamed intros take priority over victory downloads")
	for fake in active:
		var id = "james_ii" if "james_ii" in fake.requests.back().url else "shard_jack"
		fake.respond_bytes(200,FileAccess.get_file_as_bytes("res://assets/hero_video/"+id+"/intro.ogv"))
	var overlay = preload("res://characters/hero_video_overlay.gd").new(); overlay.source = video
	root.add_child(overlay)
	ok(overlay.begin("versus","shard_jack","james_ii",1,Vector2(390,844)),"verified web sidecars enter split versus")
	ok(overlay.sides.size() == 2 and overlay.sides[0].video and overlay.sides[1].video and video.cache.pins.size() == 2,"two sidecar streams pinned together")
	overlay.clear(); ok(video.cache.pins.is_empty() and overlay.sides.is_empty(),"skip frees both streamed decoders and pins")
	video.cache.entries.erase("james_ii/intro")
	overlay.begin("versus","shard_jack","james_ii",1,Vector2(390,844))
	ok(overlay._waiting_for_intros and not overlay.sides[0].video and not overlay.sides[1].video,"one ready intro waits for its partner before either starts")
	overlay._process(overlay.INTRO_WAIT_SECONDS+.1)
	ok(not overlay._waiting_for_intros and overlay.sides[0].video and not overlay.sides[1].video and overlay.sides[1].node.hero_id == "james_ii","timeout uses available clip with opponent still art")
	overlay.clear()
	video.cache.entries.clear()
	var ended = [0]
	overlay.finished.connect(func(): ended[0] += 1)
	overlay.begin("versus","shard_jack","james_ii",1,Vector2(390,844))
	ok(overlay._waiting_for_intros,"both cold clips enter bounded waiting")
	overlay._process(overlay.INTRO_WAIT_SECONDS+.1)
	ok(ended[0] == 1 and not overlay.active and not overlay.visible,"unavailable intros time out without trapping match")
	overlay.begin("versus","shard_jack","james_ii",1,Vector2(390,844))
	overlay.clear(); overlay._process(20)
	ok(ended[0] == 1 and not overlay._waiting_for_intros,"skip during loading cancels deferred intro start")
	overlay.clear(); overlay.free(); video.free(); await frames()
func fallback_and_requests():
	for failure in ["cap404","old_caps","list404","html404"]:
		var b = make_ui(failure); var ui = b.ui; var flow = ui.online_tournament
		ui.controls.tournament.pressed.emit()
		ok(flow.state == "chooser" and ui.controls.has_all(["computer","online_tournament"]),"Tournament first asks computer or online")
		ui.controls.online_tournament.pressed.emit()
		if failure == "cap404": reply(b,"/capabilities",{"error":"Not found"},404)
		elif failure == "old_caps": reply(b,"/capabilities",{"protocol":2,"tournaments":false})
		else:
			reply(b,"/capabilities",{"tournaments":true})
			reply(b,"/tournaments","<html>Not found</html>" if failure == "html404" else {"error":"Not found"},404)
		ok(flow.unavailable and flow.status == flow.COMING_SOON and flow.timer.is_stopped(),"friendly unavailable state "+failure)
		ok(ui.controls.has("computer") and not ui.controls.has("create_tournament"),"coming soon offers playable computer alternative")
		ui.controls.computer.pressed.emit()
		ok(ui.page == "character_select" and ui._pending_game.mode == "tournament","computer chooser retains Round5b flow")
		await clean(b)
	var b = make_ui("requests"); var ui = b.ui; var flow = ui.online_tournament
	flow.request(); flow.open_online(); reply(b,"/capabilities",{"tournaments":true,"tournament_sizes":[4,8],"tournament_start_options":[2,5,10,15,30,60]})
	reply(b,"/tournaments",{"server_now":F.iso(Time.get_unix_time_from_system()),"tournaments":[{"code":"T7KQ2M","host":"Kai","size":8,"joined":3}],"poll_after_ms":5000})
	ok(ui.controls.has("join_T7KQ2M") and not flow.timer.is_stopped(),"public tournaments list and schedule")
	flow.private_tournament = true; flow.password = ""; flow.create()
	ok("password" in flow.status.to_lower(),"private creation validates password before a request")
	flow.password = "private-secret"; flow.starts_in_minutes = 5
	for count in range(3,9):
		flow.desired_players = count; flow.create()
		var fake = pending(b,"/tournaments"); var request = fake.requests.back()
		ok(request.method == HTTPClient.METHOD_POST and request.body.size == (4 if count <= 4 else 8),"3–8 picker sends exact server capacity for "+str(count))
		ok(request.body.starts_in_minutes == 5 and not request.body.has("starts_at") and request.body.private and request.body.password == "private-secret","exact create start/privacy payload")
		ok("Authorization: Bearer nwd_r5c_device" in request.headers and request.body.character_id == "shard_jack","device auth and selected hero")
		fake.respond(409,{"error":"Already in a tournament"})
	flow.join_code = "TABCDE"; flow.join_password = "join-secret"; flow.join()
	var req = pending(b,"/join").requests.back()
	ok(req.url.ends_with("/tournaments/TABCDE/join") and req.body == {"password":"join-secret","character_id":"shard_jack"},"exact private join endpoint and body")
	reply(b,"/join",{"error":"No such tournament"},404)
	ok(not flow.unavailable and "not found" in flow.status.to_lower(),"missing tournament code is distinct from missing API")
	flow.join("T7KQ2M"); reply(b,"/join",F.envelope("registering"))
	ok(flow.state == "waiting" and flow.code == "T7KQ2M" and flow.password.is_empty(),"join opens waiting room and drops password")
	flow.leave(); req = pending(b,"/leave").requests.back()
	ok(req.url.ends_with("/tournaments/T7KQ2M/leave") and req.body.is_empty() and "Authorization: Bearer nwd_r5c_device" in req.headers,"exact leave endpoint uses device credential")
	reply(b,"/leave",{"ok":true}); reply(b,"/tournaments",{"tournaments":[],"poll_after_ms":5000})
	ok(flow.code.is_empty() and flow.snapshot.is_empty(),"leave clears membership")
	await clean(b)
func tournament_lifecycle():
	var b = make_ui("lifecycle"); var ui = b.ui; var flow = ui.online_tournament
	flow.request(); flow.state = "waiting"; flow.code = "T7KQ2M"; flow.snapshot = F.envelope(); ui._rebuild()
	var model = flow.screen.model
	ok(model.entrants.size() == 6 and model.entrants["seed:1"].hero_id == model.entrants["seed:5"].hero_id,"seed identity supports duplicate heroes")
	ok(model.rounds[0][0].bye and model.rounds[0][0].resolved and model.rounds[1][0].a == "seed:1","server bye auto-advances without local reseeding")
	ok(model.rounds[0][1].score == {"a":3,"b":2} and "BYE" in flow.waiting_text(),"live small-board scores and bye status")
	flow.screen.bracket.seek(.65)
	flow.snapshot.rounds[0][1].score = {"a":4,"b":2}; flow._update()
	ok(flow.screen.bracket.age == .65 and flow.screen.bracket.model.rounds[0][1].score.a == 4,"score polls preserve ongoing animation")
	var update = F.envelope(); update.rounds[0][1].status = "done"; update.rounds[0][1].winner = "a"; update.players[4].eliminated = true
	update.rounds[1][0].b = update.players[3]; update.rounds[1][0].status = "ready"; update.you.state = "playing"; update.your_match = F.ready()
	flow.refresh(); reply(b,"/tournaments/T7KQ2M",update)
	ok(flow.screen.bracket.results.size() == 1 and flow.screen.bracket.results[0].winner == "seed:4","new result feeds shared flip/advance animations")
	ok(flow.countdown == 3 and ui.controls.ready.visible,"new opponent gives three-second countdown with Ready")
	flow._process(.9); flow.refresh(); reply(b,"/tournaments/T7KQ2M",update)
	ok(is_equal_approx(flow.countdown,2.1),"one-second server polls cannot restart the match countdown")
	flow._process(2.2)
	var req = pending(b,"/rooms/QX7P2").requests.back()
	ok(req.method == HTTPClient.METHOD_GET and "Authorization: Bearer nws_r5c_seat" in req.headers,"auto-open polls the pre-seated room immediately")
	ok(ui.human_mark == 2 and ui.transport.token == "nws_r5c_seat" and ui.account.store.data.device_token == "nwd_r5c_device","seat two handoff never overwrites device identity")
	reply(b,"/rooms/QX7P2",F.room("waiting"))
	ok(ui.cinematic.kind == "versus" and ui.remote_ready,"room handoff uses the normal versus intro")
	ui.cinematic.advance(.9); ui.cinematic.skip()
	ui.transport._poll(); reply(b,"/rooms/QX7P2",F.room("finished"))
	ui._show_spotlight()
	ok(ui.controls.again.caption == "VIEW BRACKET" and ui.cinematic.combined_result,"tournament result has combined winner and bracket action")
	var count_before = ui.transport.api._queue.size(); ui.transport.request_rematch()
	ok(ui.transport.api._queue.size() == count_before and ui.transport._inflight.is_empty(),"tournament rooms cannot submit rematches")
	flow._process(5.1)
	ok(ui.page == "online_tournament" and not flow.match_active,"result automatically returns to live waiting room")
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and "/rooms/" in fake.requests.back().url and "/leave" in fake.requests.back().url: fake.respond(200,{"ok":true})
	var waiting = F.envelope(); waiting.you.state = "waiting"
	reply(b,"/tournaments/T7KQ2M",waiting)
	ok(flow.countdown < 0 and "Waiting" in flow.waiting_text(),"no duplicate room handoff while waiting")
	var final_ready = F.envelope(); final_ready.you.state = "playing"; final_ready.your_match = F.ready()
	final_ready.your_match.room_code = "ND5Q3"; final_ready.your_match.seat = 1; final_ready.your_match.round = 3
	final_ready.your_match.opponent = {"name":"Kai","hero":"james_ii"}
	flow.refresh(); reply(b,"/tournaments/T7KQ2M",final_ready)
	ok(flow.countdown == 3,"next-round opponent triggers a fresh countdown")
	flow._process(3.1)
	ok(ui.transport.code == "ND5Q3" and ui.transport.seat == 1,"second match auto-opens with new room and seat")
	var final_room = F.room(); final_room.code = "ND5Q3"; final_room.seat = 1; final_room.match.seat = 1
	final_room.opponent = "Kai"; final_room.characters = {"1":"shard_jack","2":"james_ii"}
	final_room.players = {"1":{"name":"Weaver","hero":"shard_jack"},"2":{"name":"Kai","hero":"james_ii"}}
	reply(b,"/rooms/ND5Q3",final_room)
	ok(ui.cinematic.kind == "versus" and ui.human_mark == 1 and ui.rival_character == "james_ii","second-round versus reflects fresh opponent and seat")
	ui.cinematic.advance(.9); ui.cinematic.skip(); ui.transport._poll()
	final_room.status = "closed"; final_room.end_reason = "no_show"; final_room.result = {"winner":1}
	reply(b,"/rooms/ND5Q3",final_room)
	ok(ui.cinematic.combined_result and ui.cinematic.winner_id == "shard_jack","no-show with a winner uses combined outcome")
	flow._process(5.1)
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and "/rooms/" in fake.requests.back().url and "/leave" in fake.requests.back().url: fake.respond(200,{"ok":true})
	var ended = F.envelope("finished"); ended.poll_after_ms = 0; ended.champion = {"name":"Weaver","hero":"shard_jack"}; ended.you.state = "champion"
	reply(b,"/tournaments/T7KQ2M",ended)
	ok(flow.timer.is_stopped() and "champion" in flow.waiting_text(),"finished bracket shows champion and stops polling")
	await clean(b)
func responsive():
	var b = make_ui("responsive"); var ui = b.ui; var flow = ui.online_tournament
	for dims in [Vector2(390,844),Vector2(844,390),Vector2(1366,768)]:
		ui.set_view_size(dims)
		for winner in [1,2]:
			ui.game.status = winner; ui._show_spotlight()
			var g = Cinema.combined_geometry(ui.layout.size); var bounds = Rect2(Vector2.ZERO,ui.layout.size)
			for key in ["hero","name","names","outcome","score","again","menu"]: ok(bounds.encloses(g[key]),"combined "+key+" fits "+str(dims))
			ok(not g.outcome.intersects(g.again) and not g.score.intersects(g.again),"result copy and touch targets stay separate")
			ok(g.again.size.y >= 44 and g.menu.size.y >= 44,"result buttons remain touch-sized")
		ui.cinematic.clear(); flow.code = ""; flow.request()
		ok(ui.controls.computer.size.y >= 44 and ui.controls.online_tournament.size.y >= 44,"chooser touch targets")
		flow.state = "lobby"; ui._rebuild()
		ok(ui.controls.room_code.max_length == 6 and ui.controls.players.item_count == 6,"six-character code and six group-size options")
		flow.state = "waiting"; flow.code = "T7KQ2M"; flow.snapshot = F.envelope(); ui._rebuild()
		var view_rect = flow.screen.bracket.get_rect()
		ok(not view_rect.intersects(flow.screen.controls.leave_tournament.get_rect()) and not view_rect.intersects(flow.screen.controls.ready.get_rect()),"live bracket clears footer buttons "+str(dims))
		for cards in flow.screen.bracket.geo.cards:
			for card in cards: ok(Rect2(Vector2.ZERO,flow.screen.bracket.size).encloses(card),"live bracket card fits "+str(dims))
		ui.page = "online"; ui.online_state = "lobby"; ui._rebuild()
		ok(ui.online_view.readability_rect().has_area(),"online lobby has local gradient contrast")
	await clean(b)
