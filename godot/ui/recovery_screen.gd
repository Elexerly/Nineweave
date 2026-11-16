extends Control
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Store = preload("res://net/device_store.gd")
signal action(kind: String)
var flow
var controls = {}
func _ready():
	var scroll = ScrollContainer.new(); scroll.position = Vector2(16,16); scroll.size = size-Vector2(32,32)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",16); scroll.add_child(box)
	label(box,"WELCOME BACK",28)
	label(box,"Sign in to your existing account using its verified email. Your screen name and online record stay the same.",18)
	label(box,"Signing in replaces your previous device login. That device will be signed out.",16)
	var address = LineEdit.new(); address.text = flow.email; address.placeholder_text = "Verified email address"; address.max_length = 254
	address.custom_minimum_size.y = 52; address.editable = not flow.busy and flow.challenge.is_empty()
	address.text_changed.connect(func(value): flow.email = value); box.add_child(address); controls.recovery_email = address
	button(box,"send_recovery","Send sign-in code" if flow.challenge.is_empty() else "Send new code","send").disabled = flow.busy
	if not flow.challenge.is_empty():
		var code = LineEdit.new(); code.text = flow.code; code.placeholder_text = "6-digit email code"; code.max_length = 6; code.custom_minimum_size.y = 52
		code.editable = not flow.busy; code.text_changed.connect(func(value): flow.code = value); code.text_submitted.connect(func(_v): action.emit("confirm"))
		box.add_child(code); controls.recovery_code = code
		button(box,"confirm_recovery","Continue · Sign in","confirm").disabled = flow.busy
		button(box,"edit_recovery","Use a different email","edit").disabled = flow.busy
	label(box,flow.message,18)
	label(box,"No verified email on your old account? Email sign-in cannot recover it. Use the device where you still play.",16)
	button(box,"cancel_recovery","Back · Create screen name","cancel")
	set_process(true)
func _process(_delta):
	if controls.has("send_recovery"):
		controls.send_recovery.disabled = flow.busy or Time.get_unix_time_from_system() < maxf(flow.retry_until,Store.email_timestamp(str(flow.challenge.get("resend_available_at",""))))
func label(box, text: String, font_size: int):
	var item = Label.new(); item.text = text; item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; item.add_theme_font_override("font",P.SANS)
	item.add_theme_font_size_override("font_size",font_size); item.add_theme_color_override("font_color",P.PALE); box.add_child(item)
func button(box,id: String,caption: String,kind: String):
	var item = ButtonArt.new(); item.caption = caption; item.font_size = 18; item.custom_minimum_size.y = 56
	item.pressed.connect(func(): action.emit(kind)); box.add_child(item); controls[id] = item; return item
