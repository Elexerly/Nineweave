extends SceneTree
const Safe = preload("res://ui/keyboard_safe_form.gd")
var failures = 0
var checks = 0
func ok(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	for value in ["123456","000123"]: ok(Safe.complete_code(value),"six digit code accepted")
	for value in ["12345","1234567","123a56","+12345","-12345",""]: ok(not Safe.complete_code(value),"partial/invalid code keeps keyboard")
	for dims in [Vector2(390,640),Vector2(390,844),Vector2(867,553)]:
		var view = Control.new(); view.size = dims; root.add_child(view)
		var scroll = ScrollContainer.new(); scroll.position = Vector2(12,24); scroll.size = dims-Vector2(24,48); view.add_child(scroll)
		var content = VBoxContainer.new(); content.custom_minimum_size.y = 900; scroll.add_child(content)
		var field = LineEdit.new(); field.custom_minimum_size = Vector2(220,52); content.add_child(field)
		var submit = Button.new(); submit.custom_minimum_size.y = 56; content.add_child(submit)
		var helper = Safe.new(); helper.attach(view,scroll); helper.set_process(false)
		await process_frame
		var original = scroll.size.y
		helper.apply_height(300)
		ok(scroll.position.y+scroll.size.y <= dims.y-300,"scroll bottom above keyboard")
		field.grab_focus(); field.text = "123456"; helper.code_changed(field.text,field,submit)
		ok(not field.has_focus() and field.editable and field.text == "123456","complete code dismissed but retained editable")
		field.grab_focus(); field.text = "12345"; helper.code_changed(field.text,field,submit)
		ok(field.has_focus(),"can edit code without losing focus")
		helper.apply_height(0); ok(is_equal_approx(scroll.size.y,original),"full scroll height restored")
		view.queue_free(); await process_frame
	# Native screenshots show keyboard pixels, while the Godot controls use
	# logical points. Folded, unfolded and landscape must not collapse the clip.
	for item in [
		{"view":Vector2(480,712),"raw":910.0,"pixels":2034.0},
		{"view":Vector2(390,844),"raw":948.0,"pixels":2532.0},
		{"view":Vector2(320,568),"raw":636.0,"pixels":1704.0},
		{"view":Vector2(867,390),"raw":588.0,"pixels":1170.0}
	]:
		var view = load("res://ui/recovery_screen.gd").new()
		view.flow = load("res://net/account_recovery.gd").new()
		view.add_child(view.flow)
		view.size = item.view
		root.add_child(view); await process_frame
		var helper = view.keyboard_safe; helper.set_process(false)
		var scroll = helper.scroll
		var field = view.controls.recovery_email
		field.grab_focus(); field.text = "qa-layout@example.invalid"
		var original = scroll.get_rect()
		var logical = Safe.logical_keyboard_height(item.raw,item.pixels,item.view.y,1,true)
		ok(logical < item.view.y*.55,"native ratio converts physical pixels despite wrong point transform")
		helper.apply_keyboard_metrics(item.raw,item.pixels,item.view.y,1,true)
		await process_frame; await process_frame
		ok(scroll.size.y >= 72 and scroll.get_rect().end.y <= item.view.y-logical,"full scroll aperture stays above keyboard")
		ok(scroll.get_global_rect().encloses(field.get_global_rect()),"focused email stays completely in visible aperture")
		ok(field.has_focus() and field.text == "qa-layout@example.invalid","email focus and draft stay intact")
		ok(scroll.get_v_scroll_bar().max_value > scroll.size.y,"form below the keyboard remains scrollable")
		if item.view == Vector2(480,712):
			helper.apply_keyboard_metrics(item.raw,1170.0,390.0,1,true)
			await process_frame; await process_frame
			ok(scroll.size.y >= 72 and scroll.size.y < 370,"orientation change reapplies despite identical raw keyboard pixels")
			ok(scroll.get_global_rect().encloses(field.get_global_rect()) and field.has_focus(),"orientation preserves editable field visibility and focus")
			helper.apply_keyboard_metrics(item.raw,0.0,item.view.y,1,true)
			await process_frame; await process_frame
			ok(scroll.size.y >= 132 and scroll.get_global_rect().encloses(field.get_global_rect()),"stale native metrics cannot blank the pane")
		helper.apply_keyboard_metrics(0.0,item.pixels,item.view.y,1,true)
		await process_frame; await process_frame
		ok(scroll.get_rect() == original and field.has_focus() and field.text == "qa-layout@example.invalid","keyboard close restores canvas while preserving email")
		view.queue_free(); await process_frame
	for recovery in [false,true]:
		var form = load("res://ui/recovery_screen.gd" if recovery else "res://ui/email_screen.gd").new()
		form.size = Vector2(390,640)
		var sent = [0]
		if recovery:
			form.flow = load("res://net/account_recovery.gd").new()
			form.add_child(form.flow)
			form.flow.challenge = {"challenge_id":"synthetic"}
			form.action.connect(func(_kind): sent[0] += 1)
		else:
			form.pending = true; form.challenge = {"challenge_id":"synthetic"}
			form.action.connect(func(_kind,_value): sent[0] += 1)
		root.add_child(form); await process_frame
		var field = form.controls.recovery_code if recovery else form.controls.email_code
		field.grab_focus(); field.text = "123456"; field.text_changed.emit(field.text)
		ok(not field.has_focus() and field.editable,"real code form dismisses while remaining editable")
		ok(sent[0] == 0,"real form never auto-submits code")
		form.queue_free(); await process_frame
	print("KEYBOARD_SAFE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
