extends SceneTree
const Screen = preload("res://ui/recovery_screen.gd")
const Flow = preload("res://net/account_recovery.gd")
const Fake = preload("res://tests/fake_http.gd")
var checks = 0
var failures = 0
func ok(value,label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func frames(): await process_frame; await process_frame
func run():
	var flow = Flow.new(); flow.api.request_factory = func(): return Fake.new()
	root.add_child(flow)
	flow.active = true; flow.email = "known@example.com"; flow.challenge = {"challenge_id":"example"}
	flow.message = "If this email belongs to a verified account, a code will arrive. Check spam too."
	for extent in [Vector2(320,568),Vector2(390,844),Vector2(844,390),Vector2(1280,720),Vector2(2048,920)]:
		root.size = Vector2i(extent)
		var screen = Screen.new(); screen.size = extent; screen.flow = flow; root.add_child(screen); await frames()
		var scroll = screen.get_child(0); var box = scroll.get_child(0)
		ok(screen.panel_rect.size.x <= 620 and Rect2(Vector2.ZERO,extent).encloses(screen.panel_rect),"bounded pale form panel "+str(extent))
		ok(not screen.controls.has("edit_recovery") and screen.controls.recovery_email.editable,"directly editable address without redundant edit button")
		ok(screen.controls.recovery_email.get_theme_color("font_uneditable_color") == screen.INK,"locked email retains readable dark ink")
		ok(screen.controls.recovery_email.get_theme_stylebox("read_only").bg_color.a >= .95,"locked email has opaque backing")
		for child in box.get_children():
			scroll.ensure_control_visible(child); await frames()
			ok(scroll.get_global_rect().grow(1).encloses(child.get_global_rect()),"all content reachable via scroll "+str(extent))
			if child is Label: ok(child.get_theme_color("font_color") == screen.INK,"dark readable label on white gradient")
		screen.queue_free(); await frames()
	flow.queue_free(); await frames()
	print("NINEWEAVE_RECOVERY_LAYOUT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
