extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
const HTTP = preload("res://net/http_polling_transport.gd")
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var ui = Main.instantiate(); var prefix = "user://online-turn-"+str(Time.get_ticks_usec())
	ui.account.store = Store.new(prefix+"-device.cfg"); ui.settings = Settings.new(prefix+"-settings.cfg"); ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.account.store.keep_device("nwd_fixture","Weaver"); ui.account.store.accept_consent("Weaver",Store.consent_payload()); ui.account.store.skip_email()
	ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.account.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false)
	ui.page = "game"; ui.mode = "online"; ui.remote_ready = true; ui.overlay = ""; ui.thinking = false; ui._input_beat = 0
	ui.cinematic.active = false
	for seat in [1,2]:
		ui.human_mark = seat
		for turn in [1,2]:
			ui.game.new_game(); ui.game.turn = turn; ui.game.active_board = 4; ui._refresh_labels()
			var mine = seat == turn
			ok(ui.board.is_active(4) == mine and not ui.board.is_active(0),"board affordance follows local seat "+str(seat)+" turn "+str(turn))
			ok((ui.minimap_states()[4] == "active") == mine,"minimap follows local seat")
			ok(ui.online_turn_caption() == ("Your turn" if mine else "Opponent's turn"),"explicit ownership caption")
			if not mine:
				var before = ui.game.serialize(); ui.board.invalid_board = -1
				ok(not ui.play_cell(4,0) and ui.game.serialize() == before,"opponent tap never moves")
				ok(ui.online_turn_caption() == "Opponent's turn" and ui.board.invalid_board == -1 and ui.message.is_empty(),"opponent tap explains waiting, not illegal cell")
	ui.game.new_game(); ui.human_mark = 1; ui.remote_ready = false; ui._refresh_labels()
	ok(not ui.board.is_active(0),"waiting room has no move affordance")
	ui.remote_ready = true
	var net = HTTP.new()
	net.api.request_factory = func(): return Fake.new()
	ui.transport = net; ui.add_child(net)
	net.reconnecting = true; ui._refresh_labels()
	ok(not ui.board.is_active(0) and ui.online_turn_caption() == "Reconnecting…","reconnection suppresses clickable turn")
	net.reconnecting = false; net._inflight = "move"; ui._refresh_labels()
	ok(not ui.board.is_active(0) and not ui.play_cell(0,0),"pending authoritative move blocks duplicate tap")
	net._inflight = ""; ui._refresh_labels(); ok(ui.board.is_active(0),"failed request can retry without stuck highlight")
	ui.game.play(0,4); ui._refresh_labels(); ok(not ui.board.is_active(4),"authoritative response swaps to opponent")
	ui.game.play(4,3); ui._refresh_labels(); ok(ui.board.is_active(3),"next authoritative move restores local target")
	for mode in ["local","computer"]:
		ui.mode = mode; ui._refresh_labels(); ok(ui.board.is_active(3),"offline board behavior preserved: "+mode)
	ui.free(); await process_frame
	print("online turn: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
