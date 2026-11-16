extends Control
## Shared address editor and optional code-entry stage for onboarding/Settings.
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const Store = preload("res://net/device_store.gd")
const HELPER = "Add an email so you can recover your account on a new device. Enter the code to verify it."
const VERIFICATION_LABELS = {"none":"Not verified","unverified":"Not verified","not_verified":"Not verified","verified":"Verified"}
signal action(kind: String, value: String)
signal draft_changed(value: String)
signal code_changed(value: String)
var email: String = ""
var code: String = ""
var verification_status: String = "not_verified"
var onboarding: bool = true
var status: String = ""
var busy: bool = false
var pending: bool = false
var challenge: Dictionary = {}
var retry_until: float = 0.0
var controls: Dictionary = {}
var status_label: Label
var helper_label: Label
var card: Panel
var _helper_pos: Vector2 = Vector2.ZERO
var _helper_size: Vector2 = Vector2.ZERO
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage = pending and verification_status != "verified"
	var height = 800.0 if stage else 648.0
	var width = minf(460,size.x-32)
	var scroll = ScrollContainer.new(); scroll.position = Vector2((size.x-width)/2,maxf(12,(size.y-height)/2))
	scroll.size = Vector2(width,minf(height,size.y-24)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	card = Panel.new(); card.custom_minimum_size = Vector2(width-14,height); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new(); style.bg_color = P.NAVY; style.border_color = P.GOLD_DARK
	style.set_border_width_all(2); style.set_corner_radius_all(10); card.add_theme_stylebox_override("panel",style); card.clip_contents = true; scroll.add_child(card)
	var x = 18.0; var w = width-50
	_label(card,"ACCOUNT EMAIL" if not onboarding else "ONE OPTIONAL STEP",Rect2(x,16,w,32),19,P.GOLD)
	var title = "Check your email" if not challenge.is_empty() else "Verify your email"
	_label(card,title if stage else ("Add an email (optional)" if onboarding else "Add or change your email"),Rect2(x,56,w,80),26,P.PALE)
	var helper_rect = Rect2(x,140,w,104)
	helper_label = _label(card,HELPER,helper_rect,18,P.WHITE)
	helper_label.name = "EmailHelper"; helper_label.clip_text = false
	_helper_pos = helper_rect.position; _helper_size = helper_rect.size
	helper_label.resized.connect(_lock_helper)
	_lock_helper(); call_deferred("_lock_helper")
	var field = _field("email",email,"name@example.com",Rect2(x,256,w,48),254)
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS; field.editable = not busy
	field.visible = not stage
	field.text_changed.connect(func(value): draft_changed.emit(value))
	field.text_submitted.connect(func(value): action.emit("save_email",value))
	controls["verification_status"] = _label(card,VERIFICATION_LABELS.get(verification_status,"Not verified"),Rect2(x,312,w,28),18,P.GOLD)
	_button(card,"save_email","Save",Rect2(x,352,w,48),func(): action.emit("save_email",field.text),true)
	controls.save_email.visible = not stage; controls.save_email.disabled = busy
	var continue_y = 412.0
	if stage:
		var code_field = _field("email_code",code,"6-digit code",Rect2(x,256,w,48),16)
		code_field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER; code_field.editable = not busy and not challenge.is_empty()
		code_field.text_changed.connect(func(value): code_changed.emit(value))
		code_field.text_submitted.connect(func(value): action.emit("confirm_email",value))
		controls["email_expiry"] = _label(card,"",Rect2(x,344,w,48),18,P.WHITE)
		_button(card,"confirm_email","Verify email",Rect2(x,404,w,48),func(): action.emit("confirm_email",code_field.text),true)
		_button(card,"resend_email","Resend code",Rect2(x,464,w,48),func(): action.emit("resend_email",""))
		_button(card,"change_email","Change email",Rect2(x,524,w,44),func(): action.emit("change_email",""))
		controls.change_email.disabled = busy
		continue_y = 578.0
	var continue_text = "Return"
	if onboarding:
		continue_text = "Continue without verifying" if pending else ("Continue" if verification_status == "verified" else "Continue without email")
	_button(card,"continue_email",continue_text,Rect2(x,continue_y,w,48),func(): action.emit("continue_email",""))
	status_label = _label(card,status,Rect2(x,continue_y+60,w,148 if not stage else 146),18,P.PALE)
	_update_timers()
func _field(id: String, value: String, placeholder: String, rect: Rect2, limit: int) -> LineEdit:
	var field = LineEdit.new(); field.name = id; field.text = value; field.placeholder_text = placeholder
	field.position = rect.position; field.size = rect.size; field.max_length = limit
	field.add_theme_font_override("font",P.SANS); field.add_theme_font_size_override("font_size",21)
	field.add_theme_color_override("font_color",P.PALE); field.add_theme_color_override("caret_color",P.BLUE)
	var style = StyleBoxFlat.new(); style.bg_color = Color("041425"); style.border_color = P.GOLD
	style.set_border_width_all(1); style.content_margin_left = 10
	field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("focus",style)
	card.add_child(field); controls[id] = field; return field
func _label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.text = value; parent.add_child(label)
	# Set the width after wrapping/font setup, before Label computes its minimum.
	label.position = rect.position; label.size = rect.size
	label.custom_minimum_size = Vector2(rect.size.x,0)
	label.set_meta("lock_pos",rect.position); label.set_meta("lock_size",rect.size)
	label.resized.connect(_lock_label.bind(label))
	_lock_label(label)
	return label
func _button(parent: Node, id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false):
	var button = ButtonArt.new(); button.name = id; button.caption = caption; button.font_size = 21
	button.position = rect.position; button.size = rect.size; button.accent = accent
	button.pressed.connect(callback); parent.add_child(button); controls[id] = button
func _process(_delta: float):
	_lock_helper()
	_update_timers()
func _update_timers():
	if not controls.has("resend_email"): return
	var now = Time.get_unix_time_from_system()
	var wait_seconds = maxi(0,int(ceil(maxf(retry_until,Store.email_timestamp(str(challenge.get("resend_available_at",""))))-now)))
	controls.resend_email.caption = "Resend in %ds" % wait_seconds if wait_seconds > 0 else ("Send code" if challenge.is_empty() else "Resend code")
	controls.resend_email.disabled = busy or wait_seconds > 0
	var expires = Store.email_timestamp(str(challenge.get("expires_at","")))
	var remaining = maxi(0,int(ceil(expires-now)))
	controls.email_expiry.text = "Request a new code to verify your email." if challenge.is_empty() else ("Code expired. Request a new code." if remaining == 0 else "Code expires in %d:%02d (UTC %s)." % [remaining/60,remaining%60,str(challenge.get("expires_at","")).substr(11,5)])
	controls.confirm_email.disabled = busy or challenge.is_empty() or remaining == 0 or now < retry_until
	controls.resend_email.queue_redraw()
func _lock_label(label: Label):
	if not is_instance_valid(label) or not label.has_meta("lock_size"): return
	# A Label under a Panel inside a ScrollContainer can have its height inflated
	# after the container layouts (observed ~1968 px). Reassert the assigned box.
	var pos: Vector2 = label.get_meta("lock_pos"); var size: Vector2 = label.get_meta("lock_size")
	if label.size != size or label.position != pos:
		label.position = pos; label.size = size
func _lock_helper():
	if is_instance_valid(helper_label): _lock_label(helper_label)
	for child in card.get_children() if is_instance_valid(card) else []:
		if child is Label: _lock_label(child)
func set_status(value: String):
	status = value
	if is_instance_valid(status_label): status_label.text = value
func set_verification_status(value: String):
	verification_status = value if VERIFICATION_LABELS.has(value) else "not_verified"
	if controls.has("verification_status"): controls.verification_status.text = VERIFICATION_LABELS[verification_status]
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color(.001,.005,.015,.96))
