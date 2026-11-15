extends Control
## Same account form for onboarding and later edits. Verification status is model
## data, independent of the editor; a future code-entry stage can live here.
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
signal action(kind: String, value: String)
signal draft_changed(value: String)
var email: String = ""
var verification_status: String = "not_verified"
var onboarding: bool = true
var status: String = ""
var controls: Dictionary = {}
var status_label: Label
const VERIFICATION_LABELS = {"not_verified":"Not verified","pending":"Verification pending","verified":"Verified"}
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var width = minf(460,size.x-32)
	var scroll = ScrollContainer.new(); scroll.position = Vector2((size.x-width)/2,maxf(12,(size.y-540)/2))
	scroll.size = Vector2(width,minf(540,size.y-24)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body = Panel.new(); body.custom_minimum_size = Vector2(width-14,540); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new(); style.bg_color = P.NAVY; style.border_color = P.GOLD_DARK
	style.set_border_width_all(2); style.set_corner_radius_all(10); body.add_theme_stylebox_override("panel",style); scroll.add_child(body)
	var x = 18.0; var w = width-50
	_label(body,"ACCOUNT EMAIL" if not onboarding else "ONE OPTIONAL STEP",Rect2(x,16,w,32),19,P.GOLD)
	_label(body,"Add an email to back up your account (optional)" if onboarding else "Add or change your email",Rect2(x,56,w,88),26,P.PALE)
	_label(body,"Saved on this device only for now. Backup and transfer will need email verification when it becomes available.",Rect2(x,152,w,82),18,P.WHITE)
	var field = LineEdit.new(); field.name = "email"; field.text = email; field.placeholder_text = "name@example.com"
	field.position = Vector2(x,246); field.size = Vector2(w,48); field.max_length = 254
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS; field.add_theme_font_override("font",P.SANS)
	field.add_theme_font_size_override("font_size",21); field.add_theme_color_override("font_color",P.PALE)
	field.add_theme_color_override("caret_color",P.BLUE)
	var input_style = StyleBoxFlat.new(); input_style.bg_color = Color("041425"); input_style.border_color = P.GOLD
	input_style.set_border_width_all(1); input_style.content_margin_left = 10
	field.add_theme_stylebox_override("normal",input_style); field.add_theme_stylebox_override("focus",input_style)
	field.text_changed.connect(func(value): draft_changed.emit(value))
	field.text_submitted.connect(func(value): action.emit("save_email",value))
	body.add_child(field); controls["email"] = field
	controls["verification_status"] = _label(body,VERIFICATION_LABELS.get(verification_status,"Not verified"),Rect2(x,300,w,28),18,P.GOLD)
	_button(body,"save_email","Save",Rect2(x,340,w,48),func(): action.emit("save_email",field.text),true)
	_button(body,"continue_email","Continue without email" if onboarding else "Return",Rect2(x,400,w,48),func(): action.emit("continue_email",""))
	status_label = _label(body,status,Rect2(x,460,w,68),18,P.PALE)
func _label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label = Label.new(); label.text = value; label.position = rect.position; label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label); return label
func _button(parent: Node, id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false):
	var button = ButtonArt.new(); button.name = id; button.caption = caption; button.font_size = 21
	button.position = rect.position; button.size = rect.size; button.accent = accent
	button.pressed.connect(callback); parent.add_child(button); controls[id] = button
func set_status(value: String):
	status = value
	if is_instance_valid(status_label): status_label.text = value
func set_verification_status(value: String):
	verification_status = value if VERIFICATION_LABELS.has(value) else "not_verified"
	if controls.has("verification_status"): controls.verification_status.text = VERIFICATION_LABELS[verification_status]
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color(.001,.005,.015,.96))
