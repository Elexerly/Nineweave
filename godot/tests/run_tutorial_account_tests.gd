extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Account = preload("res://net/device_account.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var prefix = "user://tutorial-account-"+str(Time.get_ticks_usec())
	var store = Store.new(prefix+".cfg")
	store.keep_device("nwd_first","First")
	store.accept_consent("First",Store.consent_payload())
	store.data.email_prompt_done = true
	var account = Account.new(); account.store = store
	var http = Fake.new(); account.api.request_factory = func(): return http
	root.add_child(account)
	account.complete_tutorial()
	ok(store.data.tutorial_completed and store.data.tutorial_pending,"completion is saved offline and queued")
	ok(http.requests.is_empty(),"old server receives no unsupported completion write")
	account._accept_email_player({"tutorial_completed":false,"capabilities":{"tutorial_completion":true}})
	await process_frame; await process_frame
	ok(account._tutorial_inflight,"server capability flushes pending completion")
	account._completed(account._tutorial_operation,200,{"player":{"tutorial_completed":true,"capabilities":{"tutorial_completion":true}}},"")
	ok(store.data.tutorial_completed and not store.data.tutorial_pending,"server completion settles monotonic local flag")
	account._accept_email_player({"tutorial_completed":false,"capabilities":{}})
	ok(store.data.tutorial_completed,"stale false response cannot erase completed tutorial")
	store.keep_device("nwd_second","Second")
	ok(not store.data.tutorial_completed,"new identity cannot inherit old completion")
	account._accept_email_player({"tutorial_completed":true,"capabilities":{"tutorial_completion":true}})
	ok(store.data.tutorial_completed,"recovered account uses server seen flag")
	var count = http.requests.size()
	account.complete_tutorial()
	ok(http.requests.size() == count and not store.data.tutorial_pending,"replay does not re-upload confirmed completion")
	account._tutorial_owner = "nwd_second"; account._tutorial_inflight = true
	store.keep_device("nwd_third","Third")
	account._completed(account._tutorial_operation,200,{"player":{"tutorial_completed":true}},"")
	ok(not store.data.tutorial_completed,"late completion from old identity cannot mark new identity seen")
	account._tutorial_owner = "nwd_third"; account._tutorial_inflight = true; store.data.signed_out = true
	account._completed(account._tutorial_operation,200,{"player":{"tutorial_completed":true}},"")
	ok(not account._tutorial_inflight and account._tutorial_owner.is_empty(),"cross-tab signout clears tutorial request state")
	store.data.signed_out = false
	store.data.tutorial_completed = true; store.data.tutorial_pending = true
	account._tutorial_owner = "nwd_third"; account._tutorial_inflight = true
	account._tutorial_operation = "tutorial_complete:retired"
	var retired_operation = account._tutorial_operation
	account._recover_device("me")
	ok(not account._tutorial_inflight and account._tutorial_owner.is_empty() and not account.tutorial_capable,"stale-token recovery retires queued tutorial write and capability")
	ok(not store.data.tutorial_completed and not store.data.tutorial_pending,"replacement registration cannot inherit old completion")
	account._completed(retired_operation,200,{"player":{"tutorial_completed":true}},"")
	ok(not store.data.tutorial_completed,"late retired completion cannot resurrect flag while token is empty")
	store.keep_device("nwd_replacement","Replacement")
	account.tutorial_capable = true; store.data.pending_sync = false
	account.complete_tutorial()
	var fresh_operation = account._tutorial_operation
	ok(account._tutorial_inflight and fresh_operation != retired_operation,"replacement can queue its own completion without stuck inflight flag")
	account._completed(retired_operation,200,{"player":{"tutorial_completed":true}},"")
	ok(account._tutorial_inflight and store.data.tutorial_pending,"old callback cannot settle or cancel replacement tutorial write")
	account._completed(fresh_operation,200,{"player":{"tutorial_completed":true}},"")
	ok(not account._tutorial_inflight and not store.data.tutorial_pending,"fresh replacement response alone settles its completion")
	account.free()
	var ui = Main.instantiate()
	ui.test_online_bypass = true
	ui.account.store = store; ui.settings.values.sound = false
	ui.http_request_factory = func(): return Fake.new()
	ui.account.api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); await process_frame; await process_frame
	ui.test_online_bypass = false; ui.account._refreshing = false; ui.account.busy = false
	ui.page = "title"; ui.mode = "computer"; store.data.tutorial_completed = false
	ui.account._refreshing = true
	ui.request_online()
	ok(not ui.tutorial.active and ui._tutorial_waiting,"online entry waits for account refresh before deciding seen")
	ui.account._refreshing = false
	ui._account_error("Temporary outage")
	await process_frame; await process_frame; await process_frame
	ok(not ui._tutorial_waiting,"failed refresh releases waiting navigation")
	ok(ui.tutorial.active and ui.page != "online","online entry teaches before creating or joining a room")
	ok(not store.data.tutorial_completed,"starting tutorial never marks it seen")
	var key = InputEventKey.new(); key.keycode = KEY_A; key.pressed = true
	ui.tutorial._input(key); ui.tutorial._gui_input(key)
	ok(ui.tutorial.active and ui.tutorial.step == 0,"ordinary keyboard input safely passes tutorial pointer handling")
	ui.tutorial.skip(); await process_frame; await process_frame
	ok(store.data.tutorial_completed and ui.page == "character_select","skip saves completion then continues to hero selection")
	ui.page = "game"; ui.mode = "online"; ui.game.status = 0; store.data.tutorial_completed = false
	ui.start_tutorial(true)
	ok(not ui.tutorial.active,"How to Play cannot block a live online opponent")
	ui._cinematic_finished("versus")
	ok(not ui.tutorial.active,"versus completion never opens onboarding tutorial")
	ui.free()
	print("tutorial account: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
