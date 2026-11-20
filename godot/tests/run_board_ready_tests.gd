extends "res://tests/run_round5c_tests.gd"
const HTTP = preload("res://net/http_polling_transport.gd")
var clock_time: float
func run():
	clock_time = floorf(Time.get_unix_time_from_system())
	await two_seats()
	await rematch_and_legacy()
	await tournament_and_expiry()
	print("LEXERLY_BOARD_READY_CLIENT ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func server_room(seat: int, round_number: int, state: String, ready: Array, legacy: bool = false) -> Dictionary:
	var e := F.room(state)
	e.seat = seat; e.match.seat = seat; e.match.round = round_number; e.token = "nws_ready_%d" % seat
	e.server_now = F.iso(clock_time); e.opponent = "Rival" if state != "waiting" else ""
	e.erase("tournament")
	if ready.size() == 2 and not legacy:
		e.opening = {"waiting":not (ready[0] and ready[1]),"you_ready":ready[seat-1],"opponent_ready":ready[2-seat],"deadline_at":F.iso(clock_time+40.0)}
	if state == "active" and (legacy or (ready.size() == 2 and ready[0] and ready[1])):
		e.turn_started_at = F.iso(clock_time); e.still_there_at = F.iso(clock_time+25); e.turn_expires_at = F.iso(clock_time+35)
	else:
		e.turn_started_at = null; e.still_there_at = null; e.turn_expires_at = null
	return e

func attach(b):
	var transport = HTTP.new()
	b.ui.page = "online"; b.ui.online_state = "waiting"; b.ui._attach_transport(transport)
	transport.now_source = func(): return clock_time
	return transport

func finish_intro(ui):
	ui._joined_beat_done()
	ok(ui.page == "game" and ui.cinematic.active,"fixture reaches blocking versus cinematic")
	ui.cinematic.complete()
	ui.tick_online()

func two_seats():
	var a = make_ui("board-ready-a"); var b = make_ui("board-ready-b")
	var ta = attach(a); var tb = attach(b)
	ta.create_room()
	ok(pending(a,"/rooms").requests.back().body.board_ready_v1 == true,"creator opts in")
	reply(a,"/rooms",server_room(1,1,"waiting",[]),201)
	tb.join_room("QX7P2")
	ok(pending(b,"/join").requests.back().body.board_ready_v1 == true,"joiner opts in")
	reply(b,"/join",server_room(2,1,"active",[false,false]))
	ta._poll(); reply(a,"/rooms/QX7P2?",server_room(1,1,"active",[false,false]))
	a.ui._joined_beat_done(); b.ui._joined_beat_done()
	a.ui.tick_online(); b.ui.tick_online()
	ok(pending(a,"/board-ready") == null and pending(b,"/board-ready") == null,"neither acknowledges during intro")
	ok(not a.ui.play_cell(0,0) and a.ui.turn_info().phase == "none","X cannot move; pending handshake has no clock")
	a.ui.cinematic.complete(); a.ui.overlay = "settings"; a.ui.tick_online()
	ok(pending(a,"/board-ready") == null,"blocking settings prevents acknowledgement")
	a.ui.overlay = ""; ta.set_background(true); a.ui.tick_online()
	ok(pending(a,"/board-ready") == null,"backgrounded client does not claim board ready")
	ta.set_background(false); a.ui.tick_online()
	var request = pending(a,"/board-ready")
	ok(request != null and request.requests.back().body == {"round":1.0,"token":"nws_ready_1"} and request.requests.back().headers.has("Authorization: Bearer nws_ready_1"),"ready send binds current round to the authenticated seat")
	request.respond(0,{},HTTPRequest.RESULT_TIMEOUT)
	a.ui.tick_online(); ok(pending(a,"/board-ready") == null,"transient reply does not spin/retry within a frame")
	clock_time += 2.0
	a.ui.tick_online(); ok(pending(a,"/board-ready") != null,"ready retries after lost acknowledgement")
	reply(a,"/board-ready",server_room(1,1,"active",[true,false]))
	a.ui.tick_online(); ta.send_move(0,0,1)
	ok(pending(a,"/board-ready") == null and pending(a,"/moves") == null and not a.ui.local_online_turn(),"one ready player waits and both movement layers stay disabled")
	ok(a.ui.online_lines()[0] == "Waiting for both boards…" and not a.ui.board.active_highlights_enabled,"pending state has waiting copy and no actionable board highlight")
	clock_time += 8.0
	b.ui.tick_online()
	ok(pending(b,"/board-ready") == null,"slow versus never asserts readiness early")
	b.ui.cinematic.age = 0.9; b.ui.cinematic.skip(); b.ui.tick_online()
	ok(pending(b,"/board-ready") != null,"skipping sets board ready after versus navigation")
	reply(b,"/board-ready",server_room(2,1,"active",[true,true]))
	ta._poll(); reply(a,"/rooms/QX7P2?",server_room(1,1,"active",[true,true]))
	ok(a.ui.turn_info().phase == "turn" and is_equal_approx(float(a.ui.turn_info().remaining),25.0),"X gets full 25 seconds only after both ready")
	ta._envelope(server_room(1,1,"active",[true,false]))
	ok(a.ui.turn_info().phase == "turn" and is_equal_approx(float(a.ui.turn_info().remaining),25.0),"equal-stamp older opening envelope cannot erase first active clock")
	ok(a.ui.play_cell(0,0) and pending(a,"/moves") != null,"first move releases after authoritative start")
	await clean(a); await clean(b)

func rematch_and_legacy():
	var b = make_ui("board-ready-rematch"); var ui = b.ui; var t = attach(b)
	t.join_room("QX7P2"); reply(b,"/join",server_room(1,1,"active",[],true))
	finish_intro(ui)
	ok(pending(b,"/board-ready") == null and ui.local_online_turn(),"legacy envelope never sends new endpoint")
	t.request_rematch()
	ok(pending(b,"/rematch").requests.back().body.board_ready_v1 == true,"rematch negotiates the fresh round")
	reply(b,"/rematch",server_room(2,2,"active",[false,false]))
	ui.tick_online()
	ok(pending(b,"/board-ready") == null and ui.cinematic.active,"new round waits through fresh intro")
	ui.cinematic.complete(); ui.tick_online()
	ok(pending(b,"/board-ready").requests.back().body.round == 2,"acknowledgement is scoped to new round")
	reply(b,"/board-ready",server_room(2,2,"active",[false,true]))
	ui.tick_online(); ok(pending(b,"/board-ready") == null,"rematch never repeats acknowledged readiness")
	t._envelope(server_room(2,1,"active",[true,true]))
	ok(t.opening_pending(),"stale previous-round envelope cannot start a rematch")
	await clean(b)

func tournament_and_expiry():
	var b = make_ui("board-ready-tournament"); var ui = b.ui; var flow = ui.online_tournament
	flow.code = "T7KQ2M"; flow.snapshot = F.envelope(); flow._pending_match = F.ready()
	flow.enter_match()
	ok(pending(b,"/rooms/QX7P2?").requests.back().url.contains("board_ready_v1=1"),"tournament room polls opt into board-ready protocol")
	var e = server_room(2,1,"active",[false,false]); e.tournament = F.room().tournament
	reply(b,"/rooms/QX7P2?",e)
	ui.cinematic.complete(); ui.tick_online()
	ok(pending(b,"/board-ready") != null,"tournament acknowledges only after reaching board")
	var timeout = e.duplicate(true)
	timeout.status = "closed"; timeout.end_reason = "no_show"; timeout.opening.expired = true; timeout.opening.waiting = false
	timeout.result = {"winner":0,"reason":"no_show"}
	reply(b,"/board-ready",timeout,409)
	ok(ui.page == "online_tournament" and ui.game.status == 0 and not ui.cinematic.active,"expired tournament skips fake draw and returns to bracket")
	await clean(b)
	var c = make_ui("board-ready-casual-expiry"); var t = attach(c)
	t.join_room("QX7P2"); reply(c,"/join",server_room(1,1,"active",[false,false]))
	c.ui._joined_beat_done(); t._poll()
	var casual = timeout.duplicate(true); casual.erase("tournament"); casual.seat = 1; casual.match.seat = 1; casual.result = null
	reply(c,"/rooms/QX7P2?",casual)
	ok(c.ui.overlay == "online_end" and c.ui.game.status == 0 and not c.ui.cinematic.active,"casual expiry shows cancellation without score or intro blocking")
	await clean(c)
