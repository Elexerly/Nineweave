extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Fake = preload("res://tests/fake_http.gd")
const Themes = preload("res://themes/registry.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	ok(Themes.BACKGROUND_CODES["0704027"] == "fourth_july","exact July code")
	ok(Themes.RESERVED_HERO_CODES.size() == 10,"ten reserved hero codes after Nick")
	ok(Themes.available([]).size() == 3,"locked backgrounds absent")
	ok(Themes.available(["blizzard","blizzard","unknown"]).size() == 4,"available whitelist unique")
	var store = Store.new("user://unlock-test.cfg")
	store.values.unlocked_backgrounds = ["blizzard"]; store.save()
	ok(Store.new("user://unlock-test.cfg").values.unlocked_backgrounds.is_empty(),"local cache cannot grant ownership")
	var ui = Main.instantiate(); ui.test_online_bypass = true; ui.settings = store
	ui.account.store = DeviceStore.new("user://unlock-device.cfg")
	ui.account.api.request_factory = func(): return Fake.new()
	store.values.unlocked_backgrounds = []
	ui.settings.values.sound = false; ui.profile.data.onboarded = true
	root.add_child(ui); await process_frame; await process_frame
	ui.overlay = "settings"; ui._rebuild()
	for i in range(6): ui.controls.difficulty.pressed.emit()
	ok(ui.overlay == "settings","six taps do not open")
	ui.controls.difficulty.pressed.emit()
	ok(ui.overlay == "secret_codes" and ui.controls.has("secret_code"),"seventh tap opens code entry")
	ui.controls.codes_back.pressed.emit()
	for i in range(4): ui.controls.difficulty.pressed.emit()
	ui.controls.cosmetics.pressed.emit(); ui.controls.done.pressed.emit()
	for i in range(3): ui.controls.difficulty.pressed.emit()
	ok(ui.overlay == "settings","other button breaks consecutive sequence")
	ui.account.store.accept_consent("Tester",DeviceStore.consent_payload()); ui.account.store.keep_device("nwd_test","Tester"); ui.account.store.data.signed_out = false
	ui._code_pending = true; ui._code_owner = "nwd_old"
	ui._code_completed("cosmetic_unlock",200,{"unlocked_backgrounds":["blizzard"],"unlock":{"kind":"background","id":"blizzard"}},"")
	ok(not "blizzard" in ui.settings.values.unlocked_backgrounds,"old identity response ignored")
	ui._code_pending = true; ui._code_owner = "nwd_test"
	ui._code_completed("cosmetic_unlock",200,{"unlocked_backgrounds":["blizzard"],"unlock":{"kind":"background","id":"blizzard"}},"")
	ok(ui.settings.values.background_theme == "blizzard","server grant selected")
	ui._account_player({"unlocked_backgrounds":[]})
	ok(ui.settings.values.background_theme == "crystal","new account restores allowed background")
	ui.queue_free(); await process_frame
	print("Unlock checks: ",checks," failures: ",failures); quit(1 if failures else 0)
