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
	await tournament_ready_before_result()
	await responsive()
	await tournament_hub()
	print("NINEWEAVE_ROUND5C ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func media():
	var b = make_ui("media"); var ui = b.ui; ui.rival_character = "james_ii"
	ui.start_game("computer",1,true,true)
	var cinema = ui.cinematic; var overlay = cinema.video_overlay
	overlay._process(overlay.INTRO_LEAD_SECONDS)
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
	overlay._process(overlay.INTRO_LEAD_SECONDS)
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
	ok(overlay._still_only and overlay.active,"unavailable intros reveal still fallback")
	overlay._process(overlay.STILL_SECONDS)
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
	ui.controls.show_join.pressed.emit()
	ok(ui.controls.has("join_T7KQ2M") and not flow.timer.is_stopped(),"public tournaments list and schedule")
	ui.controls.back.pressed.emit(); ui.controls.show_create.pressed.emit()
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
	ui.controls.back.pressed.emit(); ui.controls.show_join.pressed.emit(); ui.controls.join_private.pressed.emit()
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
	ok(ui.controls.again.caption == "CONTINUE" and ui.cinematic.combined_result,"tournament result has combined winner and bracket action")
	var count_before = ui.transport.api._queue.size(); ui.transport.request_rematch()
	ok(ui.transport.api._queue.size() == count_before and ui.transport._inflight.is_empty(),"tournament rooms cannot submit rematches")
	var waiting = F.envelope(); waiting.you.state = "waiting"
	var stale = F.envelope(); stale.you.state = "playing"; stale.your_match = F.ready()
	reply(b,"/tournaments/T7KQ2M",stale)
	flow._process(5.1)
	ok(ui.page == "game" and flow.match_active,"waiting does not interrupt the victory animation")
	ui.cinematic.complete()
	flow._process(1.0)
	ok(ui.page == "online_tournament" and not flow.match_active,"finished animation returns to live waiting room")
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and "/rooms/" in fake.requests.back().url and "/leave" in fake.requests.back().url: fake.respond(200,{"ok":true})
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
	ok(ui.controls.again.caption == "VIEW BRACKET","final keeps the bracket action rather than promising another match")
	flow._process(5.1)
	ok(ui.page == "game","final victory animation remains on screen")
	ui.cinematic.complete()
	flow._process(5.1)
	for fake in b.fakes:
		if is_instance_valid(fake) and fake.active and "/rooms/" in fake.requests.back().url and "/leave" in fake.requests.back().url: fake.respond(200,{"ok":true})
	var ended = F.envelope("finished"); ended.poll_after_ms = 0; ended.champion = {"name":"Weaver","hero":"shard_jack"}; ended.you.state = "champion"
	reply(b,"/tournaments/T7KQ2M",ended)
	ok(flow.timer.is_stopped() and "champion" in flow.waiting_text(),"finished bracket shows champion and stops polling")
	await clean(b)
func tournament_ready_before_result():
	var b = make_ui("ready-before-result"); var ui = b.ui; var flow = ui.online_tournament
	flow.code = "T7KQ2M"; flow.snapshot = F.envelope(); flow._pending_match = F.ready()
	flow.enter_match()
	reply(b,"/rooms/QX7P2",F.room("waiting"))
	ui.cinematic.complete(); ui.transport._poll()
	reply(b,"/rooms/QX7P2",F.room("finished"))
	var ready = F.envelope(); ready.you.state = "playing"; ready.your_match = F.ready()
	ready.your_match.room_code = "ND5Q3"; ready.your_match.round = 3
	ready.your_match.opponent = {"name":"Kai","hero":"james_ii"}
	reply(b,"/tournaments/T7KQ2M",ready)
	flow._process(8)
	ok(ui.page == "game" and pending(b,"/rooms/ND5Q3") == null,"assigned opponent does not interrupt winner video or start a room early")
	ui.cinematic.complete()
	ui.sound.enabled = true; ui.sound.unlocked = true; ui.sound.play_result_victory()
	ok(ui.sound.result_victory_playing(),"fixture has the spoken Victory playing")
	flow._process(1)
	ok(ui.page == "game" and pending(b,"/rooms/ND5Q3") == null,"next match never cuts off spoken Victory")
	ui.sound.stop_result_victory()
	flow._process(1)
	ok(ui.page == "online" and flow.entered_room == "ND5Q3" and pending(b,"/rooms/ND5Q3") != null,"queued assigned match opens directly after results without a tap or bracket flash")
	var token = ui.transport.token
	flow._process(12)
	ok(flow.entered_room == "ND5Q3" and token == ui.transport.token,"winner handoff cannot start the match twice")
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
		flow.state = "lobby"; flow.lobby_view = "hub"; ui._rebuild()
		ok(ui.controls.has_all(["show_create","show_join"]) and not ui.controls.has("room_code"),"first visit is an action hub")
		ui.controls.show_create.pressed.emit()
		ok(ui.controls.players.item_count == 6 and not ui.controls.has("room_code"),"create-only six group-size options")
		ui.controls.back.pressed.emit(); ui.controls.show_join.pressed.emit()
		ok(ui.controls.room_code.max_length == 6 and not ui.controls.has("players"),"join-only six-character code")
		flow.state = "waiting"; flow.code = "T7KQ2M"; flow.snapshot = F.envelope(); ui._rebuild()
		var view_rect = flow.screen.bracket.get_rect()
		ok(not view_rect.intersects(flow.screen.controls.leave_tournament.get_rect()) and not view_rect.intersects(flow.screen.controls.ready.get_rect()),"live bracket clears footer buttons "+str(dims))
		for cards in flow.screen.bracket.geo.cards:
			for card in cards: ok(Rect2(Vector2.ZERO,flow.screen.bracket.size).encloses(card),"live bracket card fits "+str(dims))
		ui.page = "online"; ui.online_state = "lobby"; ui._rebuild()
		ok(ui.online_view.readability_rect().has_area(),"online lobby has local gradient contrast")
	await clean(b)

func tournament_hub():
	var b = make_ui("hub"); var ui = b.ui; var flow = ui.online_tournament
	flow.request(); flow.open_online()
	reply(b,"/capabilities",{"tournaments":true,"tournament_start_options":[2,5,10]})
	reply(b,"/tournaments",{"tournaments":[]})
	for dims in [Vector2(320,568),Vector2(510,725),Vector2(867,610),Vector2(568,320),Vector2(1536,1081)]:
		ui.set_view_size(dims); await frames()
		var left = ui.controls.show_create.get_rect(); var right = ui.controls.show_join.get_rect()
		ok(ui.controls.tournament_header.get_line_count() == 1 and ui.controls.arena_heading.get_line_count() == 1,"lobby headings stay on separate single lines "+str(dims))
		ok(left.size.y >= 44 and right.size.y >= 44 and not left.intersects(right),"two accessible nonoverlapping hub actions "+str(dims))
		ok(left.position.y < right.position.y if flow.screen._form_width < 610 else left.position.x < right.position.x and left.position.y == right.position.y,"responsive card stack or row "+str(dims))
		ui.controls.show_create.pressed.emit(); await frames()
		var rules = ui.controls.create_rules.get_rect()
		ok(rules.position.x >= 0 and rules.end.x <= flow.screen._form_width and rules.end.y <= ui.controls.create_tournament.position.y,"create helper stays wrapped in its panel %s %s %s" % [str(rules),str(flow.screen._form_width),str(ui.controls.create_tournament.position)])
		ui.controls.back.pressed.emit(); ui.controls.show_join.pressed.emit(); await frames()
		ok(flow.screen._listing_note.visible and flow.screen._listing_note.text == "No public tournaments yet." and flow.screen.status_label.text.is_empty(),"empty state displayed once, only in public listing")
		ok(not ui.controls.join_password.visible,"private join password is opt-in")
		ui.controls.back.pressed.emit()
	ui.set_view_size(Vector2(390,640)); ui.controls.show_join.pressed.emit(); await frames()
	var original_screen = flow.screen
	var code_field: LineEdit = ui.controls.room_code
	code_field.text = "TABCDE"; code_field.text_changed.emit(code_field.text)
	code_field.grab_focus(); code_field.caret_column = 3
	ok(code_field.has_focus(),"code field focused before refresh")
	flow.refresh()
	var entries = []
	for i in range(12): entries.append({"code":"T%05d" % i,"host":"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW%s" % i,"joined":4,"size":8})
	reply(b,"/tournaments",{"tournaments":entries})
	await frames()
	ok(flow.screen == original_screen and code_field.has_focus() and code_field.caret_column == 3 and code_field.text == "TABCDE","listing refresh preserves screen, keyboard focus, caret and draft")
	var first = ui.controls.join_T00000
	ok(first.size.x < flow.screen._form_width and first.tooltip_text.length() > 24,"large entry clipped for display, full name retained")
	flow.screen._scroll.scroll_vertical = 200; await frames()
	var offset: int = flow.screen._scroll.scroll_vertical
	flow.refresh(); reply(b,"/tournaments",{"tournaments":entries}); await frames()
	ok(offset > 0 and flow.screen._scroll.scroll_vertical == offset and ui.controls.join_T00000 == first,"unchanged listing refresh retains scroll and card nodes")
	flow.join_code = "bad"; flow.join(); var expected: String = flow.status
	flow.refresh(); reply(b,"/tournaments",{"tournaments":entries}); await frames()
	ok(not expected.is_empty() and flow.status == expected and flow.screen.status_label.text == expected,"background refresh does not erase actionable join error")
	ui.controls.join_private.pressed.emit(); var secret: LineEdit = ui.controls.join_password
	secret.text = "remember-me"; secret.text_changed.emit(secret.text)
	ok(secret.visible and secret.secret,"private join mode reveals masked input")
	ui.controls.join_private.pressed.emit()
	flow.join_code = "TABCDE"; ui.controls.join_tournament.pressed.emit()
	var req = pending(b,"/join").requests.back()
	ok(req.body == {"character_id":"shard_jack"},"code-only join never sends a hidden password draft")
	reply(b,"/join",{"error":"Room closed"},409)
	ui.controls.join_private.pressed.emit(); ui.controls.join_tournament.pressed.emit()
	req = pending(b,"/join").requests.back()
	ok(req.body.get("password","") == "remember-me","private join restores and submits explicit draft")
	reply(b,"/join",{"error":"Room closed"},409)
	ui.controls.back.pressed.emit()
	ok(flow.lobby_view == "hub" and not ui.controls.has("room_code"),"back returns to lobby hub, not chooser")
	ui.controls.show_join.pressed.emit()
	ok(ui.controls.room_code.text == "TABCDE","returning to Join restores all six code characters")
	ui.controls.back.pressed.emit()
	ui.controls.show_create.pressed.emit()
	var password: LineEdit = ui.controls.password
	ok(not password.visible,"public create starts without password")
	ui.controls.privacy.pressed.emit(); password.text = "create-draft"; password.text_changed.emit(password.text)
	ui.controls.back.pressed.emit(); ui.controls.show_create.pressed.emit()
	ok(ui.controls.password.visible and ui.controls.password.text == "create-draft","create draft survives hub navigation")
	flow.refresh(); ui.controls.create_tournament.pressed.emit()
	req = pending(b,"/tournaments").requests.back()
	ok(req.method == HTTPClient.METHOD_POST and req.body.get("password","") == "create-draft","interactive create supersedes background polling")
	reply(b,"/tournaments",{"error":"Room closed"},409)
	ui.controls.privacy.pressed.emit(); ui.controls.create_tournament.pressed.emit()
	req = pending(b,"/tournaments").requests.back()
	ok(not req.body.private and not req.body.has("password"),"public creation omits hidden password")
	reply(b,"/tournaments",{"error":"Room closed"},409)
	ui.controls.back.pressed.emit(); ui.controls.back.pressed.emit()
	ok(flow.state == "chooser","second Back returns to existing chooser")
	await clean(b)
