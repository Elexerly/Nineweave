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
