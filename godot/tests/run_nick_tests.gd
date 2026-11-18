extends SceneTree
const R = preload("res://characters/roster.gd")
const Select = preload("res://characters/select.gd")
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const Audio = preload("res://characters/hero_audio.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	ok(R.DATA.size() == 35 and R.selectable_indices().size() == 32,"32 default heroes plus Nick, hidden Professor and JB")
	ok(not R.selectable("nick",[]) and R.selectable("nick",["nick"]),"Nick requires entitlement")
	ok(R.selectable_indices(["nick","nick","fake"]).size() == 33,"duplicate/unknown grants cannot add roster entries")
	for size in [Vector2(390,844),Vector2(867,553)]:
		var g = Select.geometry(size,Rect2(),33)
		ok(g.pages == (5 if size.x < size.y else 3),"unlocked Nick adds final page")
	for kind in ["intro","victory"]:
		var clip = Audio.load_clip("res://assets/hero_video/nick/"+kind+".ogv")
		ok(clip != null and clip.get_length() > 6.0 and clip.get_length() < 6.1,"separate Vorbis track " + kind)
	var ui = Main.instantiate(); ui.test_online_bypass = true; ui.settings = Store.new("user://nick-test.cfg")
	ui.account.store = DeviceStore.new("user://nick-device.cfg")
	ui.account.api.request_factory = func(): return Fake.new()
	ui.settings.values.sound = false; ui.profile.data.onboarded = true
	root.add_child(ui); await process_frame; await process_frame
	ui.account.store.accept_consent("Tester",DeviceStore.consent_payload()); ui.account.store.keep_device("nwd_nick","Tester"); ui.account.store.data.signed_out = false
	ui._code_pending = true; ui._code_owner = "nwd_nick"
	ui._code_completed("cosmetic_unlock",200,{"unlocked_backgrounds":[],"unlocked_heroes":["nick"],"unlock":{"kind":"hero","id":"nick"}},"")
	ok(ui.settings.values.unlocked_heroes == ["nick"] and "Nick" in ui._code_message,"Nick redemption updates account inventory")
	ui.page = "character_select"; ui._rebuild()
	ok(ui.hero_select.portraits.size() == 33,"owned Nick appended to regular selection")
	ui.hero_select.focus_hero("nick"); ui.hero_select.set_page(4)
	ok(ui.hero_select.selected_id == "nick" and ui.hero_select.portraits[-1].visible,"Nick selectable on fifth phone page")
	ui._account_player({"unlocked_heroes":[],"last_hero_id":"nick"})
	ui._rebuild()
	ok(ui.hero_select.portraits.size() == 32,"account switch removes previous owner hero")
	ui.hero_select.focus_hero("nick")
	ok(ui.hero_select.selected_id != "nick","cannot focus locked Nick")
	ui.queue_free(); await process_frame
	print("Nick checks: ",checks," failures: ",failures); quit(1 if failures else 0)
