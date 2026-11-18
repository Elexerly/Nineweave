extends SceneTree
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/unlock_contract_fixture.json"))
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.settings = Settings.new("user://contract-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new("user://contract-profile.cfg"); ui.profile.data.onboarded = true
	ui.account.store = DeviceStore.new("user://contract-device.cfg")
	ui.account.store.accept_consent("Tester",DeviceStore.consent_payload()); ui.account.store.keep_device("nwd_contract","Tester")
	var fake = Fake.new(); ui.account.api.request_factory = func(): return fake
	root.add_child(ui); await process_frame; await process_frame
	ui.account.api.cancel_all()
	ui.overlay = "secret_codes"; ui._rebuild()
	for step in fixture.steps:
		var previous = ui.settings.values.unlocked_backgrounds.duplicate()
		ui._redeem_code(step.code)
		var request = fake.requests.back()
		ok(request.url.ends_with("/me/unlocks") and request.body == {"code":step.code},"correct authenticated request "+step.code)
		ok("Authorization: Bearer nwd_contract" in request.headers,"account token "+step.code)
		fake.respond(int(step.status),step.body)
		if int(step.status) == 200:
			if step.body.unlock.kind == "background":
				ok(ui.settings.values.background_theme == step.body.unlock.id,"selected server grant "+step.code)
			else:
				ok(step.body.unlock.id in ui.settings.values.unlocked_heroes,"server hero grant "+step.code)
			ok(ui.settings.values.unlocked_backgrounds == step.body.unlocked_backgrounds,"server ownership "+step.code)
		else:
			ok(ui.settings.values.unlocked_backgrounds == previous,"failed code grants nothing "+step.code)
			ok(ui._code_message == step.body.error,"readable server error "+step.code)
		ok(not ui._code_pending,"request released "+step.code)
	ui._account_player(fixture.me.body)
	ok(ui.settings.values.unlocked_backgrounds.size() == 5,"server profile restores all five")
	ui._account_player(fixture.other.body)
	ok(ui.settings.values.unlocked_backgrounds.is_empty(),"other account owns none")
	ok(ui.settings.values.background_theme == "crystal","account switch removes unavailable selection")
	for dimensions in [Vector2(320,568),Vector2(390,844),Vector2(844,390),Vector2(1024,768)]:
		ui.set_view_size(dimensions); ui.overlay = "secret_codes"; ui._rebuild(); await process_frame
		ok(ui.controls.secret_code.get_parent().get_parent() is ScrollContainer,"scrollable dialog "+str(dimensions))
		ok(ui.controls.codes_back.get_global_rect().end.y <= dimensions.y,"back button visible "+str(dimensions))
	ui.queue_free(); await process_frame
	print("UNLOCK_CONTRACT checks=",checks," failures=",failures); quit(1 if failures else 0)
