extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames():
	await process_frame; await process_frame
func tap(control):
	var point = control.get_global_rect().get_center()
	for pressed in [true,false]:
		var event = InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.position = point
		root.push_input(event,true)
func run():
	var ui = Main.instantiate(); var prefix = "user://entry-"+str(Time.get_ticks_usec())
	ui.account.store = Store.new(prefix+"-device.cfg"); ui.settings = Settings.new(prefix+"-settings.cfg"); ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.settings.values.sound = false
	var http = Fake.new(); ui.account.api.request_factory = func(): return http
	ui.online_api.request_factory = func(): return Fake.new(); ui.recovery.api.request_factory = func(): return Fake.new(); ui.http_request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); ui.account.set_process(false); ui.set_view_size(Vector2(390,844)); await frames()
	ok(ui.controls.has_all(["begin_create","sign_in"]) and not ui.controls.has("screen_name"),"first launch offers buttons, not an autofocused field")
	ok(http.requests.is_empty(),"welcome sends no account request")
	tap(ui.controls.begin_create); await frames()
	ok(ui.controls.has_all(["screen_name","create_name","account_back"]),"create opens separate form through real pointer events")
	var field = ui.controls.screen_name
	ok(field.get_parent() is VBoxContainer and field.editable and field.virtual_keyboard_enabled,"standard scroll form input supports virtual keyboard")
	ok(not field.has_focus(),"form does not force keyboard before deliberate field tap")
	tap(field); await frames(); ok(field.has_focus(),"deliberate tap focuses create input")
	for code in [78,105,103,104,116]:
		var event = InputEventKey.new(); event.pressed = true; event.unicode = code; root.push_input(event)
	await frames(); ok(field.text == "Night" and ui._onboarding_name == "Night","typing reaches field and draft without rebuild")
	ok(http.requests.is_empty(),"typing never submits registration")
	ui.controls.account_back.pressed.emit(); await frames()
	ok(ui.controls.has("begin_create") and not ui.controls.has("screen_name"),"Back returns to choice even with a draft")
	ui.controls.begin_create.pressed.emit(); await frames(); ok(ui.controls.screen_name.text == "Night","reopening preserves draft")
	for dimensions in [Vector2(320,568),Vector2(844,390),Vector2(768,1024)]:
		ui.set_view_size(dimensions); await frames()
		ok(ui.controls.screen_name.text == "Night" and ui.controls.screen_name.get_global_rect().size.x > 100,"rotation/size keeps usable field and draft")
		ok(ui.online_view.agreement.get_parsed_text() == ui.online_view.AGREEMENT,"consent unchanged")
	ui.controls.sign_in.pressed.emit(); await frames()
	ok(ui.page == "recovery" and ui.controls.has("recovery_email"),"create can switch to existing sign-in")
	ui._recovery_action("cancel"); await frames()
	ok(ui.controls.has("begin_create"),"sign-in Back returns to account choice")
	ui.controls.begin_create.pressed.emit(); await frames()
	ui.account.busy = true; ui._rebuild(); await frames()
	ok(ui.controls.create_name.disabled and ui.controls.account_back.disabled and not ui.controls.screen_name.editable,"busy form blocks duplicate submit/navigation/edit")
	ui.account.busy = false; ui.free(); await frames()
	print("account entry: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
