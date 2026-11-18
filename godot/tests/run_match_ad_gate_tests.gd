extends SceneTree
const Gate = preload("res://native/ads/match_gate.gd")
const Adapter = preload("res://native/ads/test_admob.gd")
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const FakeHTTP = preload("res://tests/fake_http.gd")
class Entitlement extends Node:
	signal entitlement_changed
	var available = true
	var removed = false
	func entitlement_ready(): return available
	func ads_removed(): return removed
class Provider extends Node:
	signal completed
	var available = true
	var shown = 0
	var preloads = 0
	var succeed = true
	func is_ready(): return available
	func preload_ad(): preloads += 1
	func show_interstitial(): shown += 1; return succeed
class RematchTransport extends Node:
	var requested = 0
	var local_rematch = false
	func request_rematch(): requested += 1; local_rematch = true
	func leave(): pass
class Mobile extends Node:
	signal on_initialization_complete(status: Dictionary)
	var calls = 0
	func initialize(): calls += 1
class Ads extends Node:
	signal on_interstitial_ad_loaded(uid: int)
	signal on_interstitial_ad_showed_full_screen_content(uid: int)
	signal on_interstitial_ad_failed_to_load(uid: int, error: Dictionary)
	signal on_interstitial_ad_dismissed_full_screen_content(uid: int)
	signal on_interstitial_ad_failed_to_show_full_screen_content(uid: int, error: Dictionary)
	var loads = []
	var shown = []
	var destroyed = []
	var next_id = 0
	func create(): next_id += 1; return next_id
	func load(unit, request, keywords, uid): loads.append([unit,request,keywords,uid])
	func show(uid): shown.append(uid)
	func get_response_info(_uid): return {"response_id":"test-response", "email":"private@example.test", "device_token":"secret"}
	func destroy(uid): destroyed.append(uid)
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(): await process_frame; await process_frame
func run():
	await pacing_and_report_cases()
	await gate_cases()
	await store_contract()
	await sdk_cases()
	await controller_cases()
	print("NINEWEAVE_MATCH_AD_GATE ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
func gate_cases():
	var gate = Gate.new(); gate.minimum_match_seconds = 0; gate.minimum_ad_interval_seconds = 0; var ads = Provider.new(); var entitlement = Entitlement.new()
	root.add_child(gate); root.add_child(ads); root.add_child(entitlement)
	gate.provider = ads; gate.entitlements = entitlement; gate.enabled = true; gate.consent_allowed = func(): return true
	var calls = [0]; var proceed = func(): calls[0] += 1
	gate.before_next(proceed); ok(calls[0] == 1 and ads.shown == 0,"first match ad-free")
	gate.match_completed(); gate.match_completed(); gate.before_next(proceed)
	ok(gate.busy and calls[0] == 1 and ads.shown == 1,"completed match gates next action once")
	gate.before_next(proceed); ok(ads.shown == 1,"repeated click cannot show second ad")
	ads.completed.emit(); ads.completed.emit()
	ok(calls[0] == 2 and not gate.busy,"duplicate dismiss resumes once")
	gate.before_next(proceed); ok(ads.shown == 1,"same result cannot show again")
	for reason in ["unready","removed","consent","disabled","no_fill"]:
		gate.begin_match(); gate.match_completed()
		entitlement.available = reason != "unready"; entitlement.removed = reason == "removed"
		gate.enabled = reason != "disabled"; gate.consent_allowed = func(): return reason != "consent"
		ads.available = reason != "no_fill"
		var before = calls[0]; gate.before_next(proceed)
		ok(calls[0] == before+1 and not gate.busy and ads.shown == 1,"continue without ad: "+reason)
	entitlement.available = true; entitlement.removed = false; gate.enabled = true; gate.consent_allowed = func(): return true
	ads.available = true
	gate.begin_match(); gate.match_completed(); ads.succeed = false
	var before = calls[0]; gate.before_next(proceed)
	ok(calls[0] == before+1 and not gate.busy,"synchronous show failure continues")
	ads.succeed = true; gate.begin_match(); gate.match_completed(); gate.before_next(proceed)
	before = calls[0]; gate.cancel(); gate.before_next(proceed)
	ok(gate.busy and calls[0] == before,"cancel keeps active ad gate until native dismissal")
	ads.completed.emit()
	ok(calls[0] == before and not gate.busy,"cancel invalidates late callback")
	gate.begin_match(); gate.match_completed(); gate.skip_unsafe_boundary(); before = ads.shown
	gate.before_next(proceed); ok(ads.shown == before,"already-clocked tournament skips ad")
	gate.free(); ads.free(); entitlement.free(); await frames()
func sdk_cases():
	var adapter = Adapter.new(); var mobile = Mobile.new(); var ads = Ads.new()
	root.add_child(adapter); root.add_child(mobile); root.add_child(ads)
	ok(not adapter.start(false) and not adapter.is_ready(),"no SDK/consent means disabled")
	ok(not adapter.attach_plugins(mobile,ads,"iOS",false) and mobile.calls == 0,"no initialization without consent")
	ok(adapter.attach_plugins(mobile,ads,"iOS",true) and mobile.calls == 1,"native singleton initialization")
	mobile.on_initialization_complete.emit({}); await frames()
	ok(ads.loads.size() == 1 and ads.loads[0][0] == Adapter.IOS_TEST_UNIT,"only official iOS test unit")
	ok(ads.loads[0][1].extras.npa == "1","non-personalized test request")
	adapter.preload_ad(); ok(ads.loads.size() == 1,"duplicate preloads coalesce")
	ads.on_interstitial_ad_loaded.emit(99); await frames(); ok(not adapter.is_ready(),"foreign callback ignored")
	ads.on_interstitial_ad_loaded.emit(1); await frames(); ok(adapter.is_ready(),"loaded callback enables show")
	var completed = [0]; adapter.completed.connect(func(): completed[0] += 1)
	ok(adapter.show_interstitial() and not adapter.show_interstitial(),"loaded ad single use")
	ok(not adapter.last_report.available(),"show attempt alone does not fabricate report evidence")
	ads.on_interstitial_ad_showed_full_screen_content.emit(1); await frames()
	ok(adapter.last_report.available() and adapter.last_report.draft("Misleading ad").contains("test-response"),"SDK showed callback captures allowlisted report context")
	ads.on_interstitial_ad_dismissed_full_screen_content.emit(1); await frames()
	ads.on_interstitial_ad_dismissed_full_screen_content.emit(1); await frames()
	ok(completed[0] == 1 and ads.destroyed == [1],"dismiss destroys ad and completes once")
	adapter.preload_ad(); ads.on_interstitial_ad_failed_to_load.emit(2,{}); await frames()
	ok(not adapter.is_ready() and ads.destroyed == [1,2],"no-fill cleans up without blocking")
	adapter.preload_ad(); ads.on_interstitial_ad_loaded.emit(3); await frames(); adapter.show_interstitial()
	ads.on_interstitial_ad_failed_to_show_full_screen_content.emit(3,{}); await frames()
	ok(completed[0] == 2,"show failure completes gate")
	adapter.preload_ad(); adapter.revoke_consent(); ads.on_interstitial_ad_loaded.emit(4); await frames()
	ok(not adapter.is_ready(),"consent revocation ignores late load")
	ok(ads.destroyed.count(4) == 2,"late native allocation after revoked load is released")
	adapter.free(); mobile.free(); ads.free(); await frames()
func controller_cases():
	var ui = Main.instantiate(); ui.test_online_bypass = true
	var prefix = "user://ad-controller-"+str(Time.get_ticks_usec())
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false; ui.settings.values.tutorial_completed = true
	ui.profile = Profile.new(prefix+"-profile.cfg"); ui.profile.choose("shard_jack","Weaver")
	ui.http_request_factory = func(): return FakeHTTP.new()
	ui.account.api.request_factory = func(): return FakeHTTP.new()
	ui.online_api.request_factory = func(): return FakeHTTP.new()
	root.add_child(ui); ui.ad_report_details = "Old ad details"; ui.ad_report_reason = "Misleading ad"; ui.test_admob.report_context_changed.emit()
	ok(ui.ad_report_details.is_empty() and ui.ad_report_reason == "Inappropriate content","new ad clears old report text and reason")
	ui.match_ads.minimum_match_seconds = 0; ui.match_ads.minimum_ad_interval_seconds = 0; ui.set_process(false); await frames()
	ok(not ui.match_ads.enabled,"shipping/web default remains ad-disabled")
	var ads = Provider.new(); var entitlement = Entitlement.new(); root.add_child(ads); root.add_child(entitlement)
	ui.match_ads.provider = ads; ui.match_ads.entitlements = entitlement; ui.match_ads.enabled = true; ui.match_ads.consent_allowed = func(): return true
	ui.start_game("computer",1,false,false)
	ui.game.status = 1; ui.match_ads.match_completed(); ui.rematch()
	ok(ui.match_ads.busy and ui.game.status == 1 and ui.human_mark == 1,"offline rematch waits for dismissal")
	ads.completed.emit()
	ok(ui.game.status == 0 and ui.human_mark == 2,"dismiss starts opposite mark")
	ui.match_ads.match_completed(); ui.start_game("computer",1,false,false); ui.go_home(); ads.completed.emit()
	ok(ui.page == "title","navigation cancels late start")
	var remote = RematchTransport.new(); ui.add_child(remote); ui.transport = remote
	ui.mode = "online"; ui.overlay = ""; ui.match_ads.begin_match(); ui.match_ads.match_completed()
	ui.rematch(); ui.rematch()
	ok(remote.requested == 0 and ui.match_ads.busy,"online readiness never sent during ad")
	ads.completed.emit(); ads.completed.emit()
	ok(remote.requested == 1,"online readiness exactly once after ad closes")
	var bus = AudioServer.get_bus_index("Master"); var original_mute = AudioServer.is_bus_mute(bus)
	for muted in [false,true]:
		AudioServer.set_bus_mute(bus,muted)
		ui.match_ads.begin_match(); ui.match_ads.match_completed(); ui.start_game("computer",1,false,false)
		ok(ui.match_ads.busy and AudioServer.is_bus_mute(bus),"game audio muted throughout ad")
		ui.go_home()
		ok(ui.match_ads.busy and AudioServer.is_bus_mute(bus),"cancel keeps audio muted until native close")
		ads.completed.emit()
		ok(not ui.match_ads.busy and AudioServer.is_bus_mute(bus) == muted,"native close restores exact prior mute")
	AudioServer.set_bus_mute(bus,original_mute)
	ui.free(); ads.free(); entitlement.free(); await frames()

func store_contract():
	var gate = Gate.new(); gate.minimum_match_seconds = 0; gate.minimum_ad_interval_seconds = 0; var ads = Provider.new()
	var store = load("res://native/store_entitlement.gd").new()
	root.add_child(gate); root.add_child(ads); root.add_child(store)
	store._product_id = "test.remove_ads"
	gate.provider = ads; gate.entitlements = store; gate.enabled = true; gate.consent_allowed = func(): return true
	ok(not gate.can_serve(),"real provider unknown suppresses ads")
	store._handle_event({"kind":"entitlement","product_id":"test.remove_ads","owned":false,"verified":true})
	ok(gate.can_serve(),"real provider confirmed non-owner can serve")
	store._handle_event({"kind":"entitlement","product_id":"test.remove_ads","owned":true,"verified":true})
	ok(not gate.can_serve(),"real provider verified owner suppresses ads")
	store._handle_event({"kind":"error","operation":"verification","message":"unconfirmed"})
	ok(not gate.can_serve(),"real provider unconfirmed snapshot suppresses ads")
	gate.free(); ads.free(); store.free(); await frames()

func pacing_and_report_cases():
	var gate = Gate.new(); var ads = Provider.new(); var entitlement = Entitlement.new()
	root.add_child(gate); root.add_child(ads); root.add_child(entitlement)
	gate.provider = ads; gate.entitlements = entitlement; gate.enabled = true; gate.consent_allowed = func(): return true
	var clock = [100.0]; gate.time_source = func(): return clock[0]
	var calls = [0]; var next = func(): calls[0] += 1
	gate.begin_match(); clock[0] += 10; gate.match_completed(); gate.before_next(next)
	ok(ads.shown == 0 and calls[0] == 1,"short match does not trigger ad")
	gate.begin_match(); clock[0] += 31; gate.match_completed(); gate.before_next(next)
	ok(ads.shown == 1 and gate.busy,"meaningful match eligible for one ad")
	clock[0] += 150 # Long ad must not consume the next cooldown.
	ads.completed.emit(); gate.begin_match(); clock[0] += 31; gate.match_completed(); gate.before_next(next)
	ok(ads.shown == 1 and calls[0] == 3,"cooldown continues gameplay without back-to-back ads")
	clock[0] += 120; gate.begin_match(); clock[0] += 31; gate.match_completed(); gate.before_next(next)
	ok(ads.shown == 2,"later meaningful match eligible after cooldown")
	ads.completed.emit()
	var report = Adapter.Report.new()
	ok(not report.available() and report.draft("Misleading ad").contains("No ad"),"no invented ad report")
	ok(report.email_draft_uri("Misleading ad").is_empty(),"no email draft without real presentation context")
	report.capture({"response_id":"abc", "email":"secret@example.test", "device_token":"private"},"between_matches")
	var draft = report.draft("Misleading ad","User explanation")
	ok(draft.contains("abc") and draft.contains("not sent") and not draft.contains("secret") and not draft.contains("private"),"report allowlist excludes account fields and is honestly unsent")
	ok(report.draft("invalid").contains("Choose"),"report requires known reason")
	var uri = report.email_draft_uri("Misleading ad","A&B? #test\nNext line")
	ok(uri.begins_with("mailto:escapetheavalanchedeux@gmail.com?subject=Nineweave%20ad%20report&body="),"draft targets only approved games support")
	ok(uri.count("&") == 1 and not uri.contains("#") and not uri.contains("\n") and uri.contains("A%26B%3F%20%23test%0ANext%20line"),"report text encoded without injecting mail headers or recipients")
	ok(report.email_draft_uri("invalid").is_empty(),"invalid reason cannot create email draft")
	gate.free(); ads.free(); entitlement.free(); await frames()
