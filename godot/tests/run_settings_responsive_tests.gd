extends SceneTree
const Main = preload("res://main/main.tscn")
const Store = preload("res://net/device_store.gd")
const Settings = preload("res://settings/store.gd")
const Profile = preload("res://characters/profile.gd")
const Fake = preload("res://tests/fake_http.gd")
const Paint = preload("res://ui/paint.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var ui = Main.instantiate()
	var prefix = "user://settings-responsive-isolated"
	ui.account.store = Store.new(prefix+"-device.cfg")
	ui.account.store.accept_consent("Weaver",Store.consent_payload()); ui.account.store.keep_device("nwd_test_settings","Weaver")
	ui.account.store.data.email_prompt_done = true; ui.account.store.data.tutorial_completed = true
	ui.settings = Settings.new(prefix+"-settings.cfg"); ui.settings.values.sound = false
	ui.profile = Profile.new(prefix+"-profile.cfg")
	ui.account.api.request_factory = func(): return Fake.new()
	ui.online_api.request_factory = func(): return Fake.new()
	ui.http_request_factory = func(): return Fake.new()
	ui.social.api.request_factory = func(): return Fake.new()
	root.add_child(ui); ui.set_process(false); await process_frame; await process_frame
	ui.social.capabilities = {"chat":true}
	for extent in [Vector2(320,568),Vector2(390,844),Vector2(568,320),Vector2(844,390),Vector2(867,553),Vector2(553,867),Vector2(768,1024),Vector2(1366,768)]:
		root.size = Vector2i(extent); ui.set_view_size(extent); ui.page = "title"; ui.overlay = "settings"; ui._rebuild()
		ui._layout_settings_footer(ui._modal_rect,true)
		await process_frame; await process_frame
		var ids = ["done","cosmetics","report_last_ad"]
		for i in range(ids.size()):
			var b = ui.controls[ids[i]]; var r = b.get_global_rect()
			ok(ui._modal_rect.encloses(r),str(extent)+" footer inside "+ids[i])
			ok(r.size.x >= 44 and r.size.y >= 44,"minimum tap size")
			ok(Paint.text_width(b.caption,b.font_size) <= r.size.x-12,"readable fitted caption "+ids[i])
			ok(b.pressed.get_connections().size() >= 2,"action wired "+ids[i])
			for j in range(i): ok(not r.intersects(ui.controls[ids[j]].get_global_rect()),"footer separated")
			ok(not r.intersects(ui.controls.settings_scroll.get_global_rect()),"footer outside scrolling content")
		var body = ui.controls.settings_scroll.get_child(0)
		var actions = []
		for node in body.get_children():
			if node is Button or node is LineEdit or node is HSlider: actions.append(node)
		for i in range(actions.size()):
			var a = actions[i]
			ok(a.position.y >= 0 and a.position.y+a.size.y <= body.custom_minimum_size.y,"body action reachable")
			for j in range(i): ok(not a.get_rect().intersects(actions[j].get_rect()),"body separated "+a.name+"/"+actions[j].name)
		ui.controls.report_last_ad.pressed.emit(); ok(ui.overlay == "ad_report","report action responsive")
		ui.overlay = "settings"; ui._rebuild(); ui.controls.done.pressed.emit(); ok(ui.overlay.is_empty(),"Return responsive")
	ui.free(); await process_frame
	print("NINEWEAVE_SETTINGS_RESPONSIVE ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
