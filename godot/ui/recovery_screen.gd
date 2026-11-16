extends Control
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Store = preload("res://net/device_store.gd")
signal action(kind: String)
var flow
var controls = {}
const INK = Color("17243b")
var panel_rect: Rect2
func _ready():
	var width = minf(620,size.x-24)
	panel_rect = Rect2((size.x-width)*.5,12,width,size.y-24)
	queue_redraw()
	var scroll = ScrollContainer.new(); scroll.position = panel_rect.position+Vector2(18,18); scroll.size = panel_rect.size-Vector2(36,36)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",14); scroll.add_child(box)
	label(box,"WELCOME BACK",28)
	label(box,"Sign in to your existing account using its verified email. Your screen name and online record stay the same.",18)
	label(box,"Signing in replaces your previous device login. That device will be signed out.",16)
	var row = HBoxContainer.new(); box.add_child(row)
	var address_title = Label.new(); address_title.text = "EMAIL ADDRESS"; address_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_title.add_theme_color_override("font_color",INK); row.add_child(address_title)
	if not flow.challenge.is_empty():
		var edit = Button.new(); edit.text = "Edit email"; edit.custom_minimum_size = Vector2(96,44); edit.disabled = flow.busy
		var edit_style = StyleBoxFlat.new(); edit_style.bg_color = Color("e0e9f5"); edit_style.set_corner_radius_all(4)
		for state in ["normal","hover","pressed","disabled"]: edit.add_theme_stylebox_override(state,edit_style)
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]: edit.add_theme_color_override(state,INK)
		edit.pressed.connect(func(): action.emit("edit")); row.add_child(edit); controls.edit_recovery = edit
	var address = LineEdit.new(); address.text = flow.email; address.placeholder_text = "Verified email address"; address.max_length = 254
	style_field(address); address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	address.text_submitted.connect(func(_v): if flow.challenge.is_empty(): action.emit("send"))
	address.custom_minimum_size.y = 52; address.editable = not flow.busy and flow.challenge.is_empty()
	address.text_changed.connect(func(value): flow.email = value); box.add_child(address); controls.recovery_email = address
	button(box,"send_recovery","Send sign-in code" if flow.challenge.is_empty() else "Send new code","send").disabled = flow.busy
	if not flow.challenge.is_empty():
		var code = LineEdit.new(); code.text = flow.code; code.placeholder_text = "6-digit email code"; code.max_length = 6; code.custom_minimum_size.y = 52
		style_field(code); code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		code.editable = not flow.busy; code.text_changed.connect(func(value): flow.code = value); code.text_submitted.connect(func(_v): action.emit("confirm"))
		box.add_child(code); controls.recovery_code = code
		button(box,"confirm_recovery","Continue · Sign in","confirm").disabled = flow.busy
	label(box,flow.message,18)
	label(box,"No verified email on your old account? Email sign-in cannot recover it. Use the device where you still play.",16)
	button(box,"cancel_recovery","Back","cancel")
	set_process(true)
func _process(_delta):
	if controls.has("send_recovery"):
		controls.send_recovery.disabled = flow.busy or Time.get_unix_time_from_system() < maxf(flow.retry_until,Store.email_timestamp(str(flow.challenge.get("resend_available_at",""))))
func label(box, text: String, font_size: int):
	var item = Label.new(); item.text = text; item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; item.add_theme_font_override("font",P.SANS)
	item.add_theme_font_size_override("font_size",font_size); item.add_theme_color_override("font_color",INK); box.add_child(item)
func button(box,id: String,caption: String,kind: String):
	var item = ButtonArt.new(); item.caption = caption; item.font_size = 18; item.custom_minimum_size.y = 56
	item.pressed.connect(func(): action.emit(kind)); box.add_child(item); controls[id] = item; return item

func style_field(field: LineEdit):
	var style = StyleBoxFlat.new(); style.bg_color = Color(1,1,1,.98); style.border_color = Color("8796ad")
	style.set_border_width_all(1); style.set_corner_radius_all(5); style.content_margin_left = 12; style.content_margin_right = 12
	field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("read_only",style)
	field.add_theme_color_override("font_color",INK); field.add_theme_color_override("font_uneditable_color",INK)
	field.add_theme_color_override("font_placeholder_color",Color("53627a")); field.add_theme_color_override("caret_color",INK)
	field.add_theme_font_size_override("font_size",18)
func _draw():
	# A pale, near-opaque gradient keeps the arena visible around the form,
	# without letting hero artwork compete with instructions or disabled fields.
	for i in range(48):
		var t = float(i)/48
		var color = Color("ffffff").lerp(Color("dbe5f3"),t); color.a = .97
		draw_rect(Rect2(panel_rect.position+Vector2(0,panel_rect.size.y*t),Vector2(panel_rect.size.x,panel_rect.size.y/48+1)),color)
	draw_rect(panel_rect,Color("b7c6dc"),false,1)
