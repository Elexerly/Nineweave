extends SceneTree
const Main = preload("res://main/main.tscn")
const Account = preload("res://net/device_account.gd")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var prefix = "user://hero-sync-test"
	for suffix in ["-device.cfg","-settings.cfg","-profile.cfg","-profile-tournament.cfg"]:
		if FileAccess.file_exists(prefix+suffix): DirAccess.remove_absolute(prefix+suffix)
	var ui = Main.instantiate()
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.account.store.accept_consent("Original",Store.consent_payload())
	ui.account.store.keep_device("nwd_original","Original")
	ui.account.store.data.email_prompt_done = true
	var clients = []; ui.account.api.request_factory = func(): var f = Fake.new(); clients.append(f); return f
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	ui.recovery.api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false); await process_frame
	var http = clients[0]
	http.respond(200,{"screen_name":"Original","last_hero_id":"vesper_vale"})
	var a = ui.account
	a.choose_hero("cryon")
	ok(http.requests.back().body == {"last_hero_id":"cryon"},"lock in queues exact hero patch")
	http.respond(503,{"error":"offline"})
	ok(a.pending_hero() == "cryon","failed PATCH retains pending choice")
	var saved = Store.new(prefix+"-device.cfg")
	ok(saved.data.pending_hero == "cryon" and saved.data.pending_hero_owner == "nwd_original".sha256_text(),"pending persisted with account binding")
	var reloaded = Account.new(); reloaded.store = Store.new(prefix+"-device.cfg")
	var reload_http = Fake.new(); reloaded.api.request_factory = func(): return reload_http
	root.add_child(reloaded); reloaded.set_process(false); reloaded.refresh()
	reload_http.respond(200,{"screen_name":"Original","last_hero_id":"vesper_vale"})
	ok(reloaded.pending_hero() == "cryon" and reload_http.requests.back().body == {"last_hero_id":"cryon"},"fresh account instance retries durable hero after reload")
	reload_http.respond(503,{"error":"offline"})
	reloaded._sync_hero(); reload_http.respond(401,{"error":"Unknown token"})
	ok(reloaded.store.data.pending_hero.is_empty(),"stale-token replacement never carries old identity hero")
	reloaded.api.cancel_all(); reloaded.queue_free()
	ui._hero_changed = false; ui._account_player({"last_hero_id":"vesper_vale"})
	ok(ui.profile.data.character_id == "cryon","stale startup server hero cannot overwrite pending choice")
	var before = http.requests.size(); a._process(30.0)
	ok(http.requests.size() == before+1,"timer retries pending PATCH")
	a.choose_hero("sara")
	ok(a.pending_hero() == "sara" and http.requests.size() == before+1,"newest lock in persists while prior PATCH in flight")
	http.respond(200,{"last_hero_id":"cryon","capabilities":{"email":true},"email":"original@example.com","email_status":"verified"})
	ok(a.email_capable and a.store.data.email_status == "verified","successful hero PATCH merges account capabilities while newer hero remains pending")
	ok(a.pending_hero() == "sara" and http.requests.back().body == {"last_hero_id":"sara"},"old acknowledgment cannot clear newest choice")
	http.respond(200,{"last_hero_id":"sara"})
	ok(a.pending_hero().is_empty() and Store.new(prefix+"-device.cfg").data.pending_hero.is_empty(),"matching server confirmation clears durable pending")
	a.choose_hero("cryon"); http.respond(200,{"screen_name":"Original"})
	ok(a.pending_hero() == "cryon","sparse response cannot falsely acknowledge hero")
	a.refresh(); http.respond(200,{"screen_name":"Original","last_hero_id":"sara"})
	ok(http.requests.back().body == {"last_hero_id":"cryon"},"successful refresh retries pending")
	http.respond(200,{"last_hero_id":"cryon"})
	a.store.data.pending_sync = true; before = http.requests.size(); a.choose_hero("sara")
	ok(a.pending_hero() == "sara" and http.requests.size() == before,"offline pending registration saves hero without PATCH")
	a.store.data.pending_sync = false
	ui.page = "recovery"
	var player = Store.consent_payload(); player.screen_name = "Different"; player.last_hero_id = "vesper_vale"
	ui._account_recovered("nwd_different",player)
	ok(a.pending_hero().is_empty() and a.store.data.pending_hero.is_empty(),"recovery cannot carry previous account pending hero")
	ok(ui.profile.data.character_id == "vesper_vale","recovered account loads own hero")
	a.choose_hero("cryon"); http.respond(503,{"error":"offline"}); ui._confirm_signout()
	ok(ui.account.store.data.pending_hero.is_empty() and ui.account.store.data.signed_out,"signout discards pending identity choice")
	var local = Store.new(prefix+"-local.cfg")
	local.data.device_token = ""; local.data.pending_hero = "sara"; local.data.pending_hero_owner = ""
	local.keep_device("nwd_first","First")
	ok(local.data.pending_hero == "sara" and local.data.pending_hero_owner == "nwd_first".sha256_text(),"local pre-registration hero binds to first server account")
	local.keep_device("nwd_second","Second")
	ok(local.data.pending_hero.is_empty(),"credential replacement never inherits pending hero")
	ui.queue_free(); await process_frame; await process_frame
	print("NINEWEAVE_HERO_SYNC ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
