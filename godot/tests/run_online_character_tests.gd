extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Store = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func make_ui(id):
	var prefix = "user://online-character-"+id
	for suffix in ["-settings.cfg","-profile.cfg","-device.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	var ui = Main.instantiate()
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.data.character_id = "cryon"; ui.profile.data.onboarded = true
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.account.store.keep_device("nwd_fixture_"+id,id); ui.account.store.accept_consent(id,Store.consent_payload()); ui.account.store.skip_email()
	ui.test_online_bypass = true
	ui.account.api.request_factory = func(): return Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false); ui.set_view_size(Vector2(390,844))
	return ui
func run():
	var host = make_ui("Host"); var guest = make_ui("Guest")
	await process_frame; await process_frame
	host.request_online()
	ok(host.page == "character_select" and host._pending_game.mode == "online_lobby","Online opens selector before lobby")
	ok(host.hero_select.selected_id == "cryon" and host.hero_select.confirm_button.caption == "CONTINUE","preselect last hero and clear continuation")
	ok(not is_instance_valid(host.transport),"no room or transport before choice")
	host.hero_select.back.emit()
	ok(host.page == "title" and host._pending_game.is_empty() and host.profile.data.character_id == "cryon","cancel returns home without changing saved hero")
	host.request_game("online")
	ok(host.page == "character_select","alternate online entry also selects first")
	host._confirm_hero("not-a-hero","Host")
	ok(host.page == "character_select", "invalid selection cannot enter matchmaking")
	host._confirm_hero("sara","Host")
	ok(host.page == "online" and host.online_state == "lobby" and host._pending_game.is_empty(),"confirm enters lobby rather than game")
	ok(host.profile.data.character_id == "sara","choice persisted before room creation")
	host.create_online(true)
	var room = host.room_code
	ok(host.transport.character_id == "sara","host transports selected hero")
	guest.request_online(); guest._confirm_hero("cryon","Guest")
	guest.join_online(room,true)
	ok(guest.page == "game" and host.page == "game","instant join starts both without another selector")
	ok(host.transport.remote_character_id == guest.profile.data.character_id and guest.transport.remote_character_id == "sara","both perspectives receive chosen heroes")
	ok(host.transport.character_id == "sara","authoritative match retains host selection")
	for ui in [host,guest]:
		ui.cinematic.clear(); ui.thinking = false; ui._input_beat = 0; ui._refresh_labels()
	ok(host.board.is_active(4) != guest.board.is_active(4),"exactly one actual peer sees the blue move highlight")
	ok(host.board.is_active(4) == (host.human_mark == host.game.turn) and guest.board.is_active(4) == (guest.human_mark == guest.game.turn),"both peers map highlight to their own authoritative seat")
	var mover = host if host.human_mark == host.game.turn else guest
	var waiting = guest if mover == host else host
	ok(mover.play_cell(4,4),"active peer can submit first move")
	host._refresh_labels(); guest._refresh_labels()
	ok(not mover.board.is_active(4) and waiting.board.is_active(4),"authoritative broadcast switches blue highlight between actual peers")
	ok(host.game.turn == guest.game.turn and host.game.cells[40] == guest.game.cells[40],"both peers share the same acknowledged move")
	host.request_online()
	ok(host.page == "character_select" and host.hero_select.selected_id == "sara" and not is_instance_valid(host.transport),"new online entry leaves old room and remembers hero")
	host._confirm_hero("sara","Host"); host._online_action("lobby","")
	ok(host.page == "online","internal lobby navigation does not reselect")
	host.go_home(); host.request_game("computer")
	ok(host.page == "character_select" and host._pending_game.mode == "computer" and host.hero_select.confirm_button.caption == "LOCK IN","bot selector unchanged")
	host.go_home(); host.request_game("local")
	ok(host._select_player == 1 and host._pending_game.mode == "local","local two-player selection unchanged")
	host._confirm_hero("sara","Host")
	ok(host._select_player == 2 and host.page == "character_select","local second player still chooses")
	host.go_home(); host.page = "email"; host._onboarding_destination = "online"; host._onboarding_email_confirmation = true
	host._account_email_verified()
	ok(host.page == "character_select" and host._pending_game.mode == "online_lobby","verified onboarding goes through hero choice")
	host.go_home(); host.page = "email"; host._onboarding_destination = "online"
	host._email_action("continue_email","")
	ok(host.page == "character_select","skip-email onboarding also selects before online lobby")
	host._leave_online(); guest._leave_online(); host.queue_free(); guest.queue_free()
	await process_frame; await process_frame
	print("NINEWEAVE_ONLINE_CHARACTER ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
