extends SceneTree
## Run headless with --main-pack <release/index.pck> and this external script.
## The release excludes tests, so this check has no fixture-resource dependency.
const Main = preload("res://main/main.tscn")
const Settings = preload("res://settings/store.gd")
const DeviceStore = preload("res://net/device_store.gd")
var failures: int = 0
func check(value: bool, message: String):
	if not value: failures += 1; print("FAIL ",message)
func _initialize(): run.call_deferred()
func run():
	var settings_path = "user://round4e-pack-settings.cfg"
	var device_path = "user://round4e-pack-device.cfg"
	for path in [settings_path,device_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var ui = Main.instantiate(); ui.test_online_bypass = true
	ui.settings = Settings.new(settings_path); ui.settings.values.sound = false
	ui.account.store = DeviceStore.new(device_path)
	root.add_child(ui); ui.set_process(false); ui.set_view_size(Vector2(390,844))
	# Enable first-play checks only after tree entry; startup HTTP stays disabled.
	ui.test_online_bypass = false; ui.start_game("local")
	check(ui.tutorial.active and ui.board.frozen,"packed first-play tutorial starts")
	check(ui.tutorial.caption.text == "You play in any open square.","packed tutorial text loaded")
	ui.tutorial.skip()
	check(ui.board.game == ui.game and Settings.new(settings_path).values.tutorial_completed,"packed skip persists and restores board")
	ui.start_game("local"); check(not ui.tutorial.active,"packed next match skips guide")
	ui.go_home(); ui.controls.how.pressed.emit()
	check(ui.tutorial.active and ui.board.visible,"packed menu replay works")
	for i in range(6): ui.tutorial.next_step()
	check(ui.page == "title" and not ui.tutorial.active,"packed replay finishes at menu")
	ui.open_account_email(); check(ui.controls.verification_status.text == "Not verified","packed account form is unverified")
	ui.controls.email.text = "pack@example.com"; ui.controls.save_email.pressed.emit()
	check(ui.overlay == "settings" and DeviceStore.new(device_path).data.email == "pack@example.com","packed email saves locally")
	ui.page = "onboarding"; ui.overlay = ""; ui._rebuild()
	check(ui.controls.create_name.caption == "Create Screen Name" and "13 or older" in ui.online_view.agreement.get_parsed_text(),"packed screen-name consent retained")
	ui.page = "email"; ui._email_draft = ""; ui._rebuild()
	check(ui.controls.continue_email.caption == "Continue without email","packed optional email path loaded")
	ui.controls.continue_email.pressed.emit()
	check(ui.page == "title" and DeviceStore.new(device_path).data.email_prompt_done,"packed optional continue works")
	ui.free(); await process_frame
	print("NINEWEAVE_ROUND4E_PACK ","PASS" if failures == 0 else "FAIL"," failures=",failures)
	quit(0 if failures == 0 else 1)
