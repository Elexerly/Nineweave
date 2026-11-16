extends Control
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
signal action(kind: String)
var flow
var local_only = false
var controls = {}
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new(); shade.color = Color("07101f"); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	var scroll = ScrollContainer.new(); scroll.position = Vector2(16,16); scroll.size = size-Vector2(32,32)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",16); scroll.add_child(box)
	if local_only:
		label(box,"CLEAR THIS DEVICE" if flow.stage == 1 else "CONFIRM LOCAL RESET",26)
		label(box,"This clears this device's saved account details, sign-in token, profile, scores and saved game. It cannot be undone on this device.",18)
		label(box,"This does NOT delete your server account or confirm the earlier deletion. That outcome remains unknown. You may lose access unless your account still exists and has a verified recovery email.",18)
		label(box,"You will return to an empty create-name screen. No new account is created automatically.",18)
	else:
		label(box,"DELETE ACCOUNT" if flow.stage == 1 else "FINAL CONFIRMATION",26)
		label(box,"This permanently deletes your profile, verified email, screen name, own scores, stored chat messages, reports involving your account and identifying links from the active game database. It cannot be undone.",18)
		label(box,"This does not erase hosting/email-provider records, backups or copies held by others.",18)
		label(box,"Shared gameplay records remain under ####. Opponents keep their results and statistics. Your saved game and local profile will also be cleared on this device.",18)
		label(box,"Finish or leave active matches first. Active tournaments must finish or be canceled before deletion.",16)
	var required_phrase = "CLEAR THIS DEVICE" if local_only else "DELETE MY ACCOUNT"
	if flow.stage == 1:
		button(box,"delete_review","I understand · Continue","review")
	else:
		label(box,"Type CLEAR THIS DEVICE, then press Clear local details." if local_only else "To permanently delete your account, type DELETE MY ACCOUNT, then press Permanently delete.",18)
		var field = LineEdit.new(); field.placeholder_text = required_phrase; field.text = flow.phrase; field.max_length = 17; field.custom_minimum_size.y = 52; field.editable = not flow.busy
		field.text_changed.connect(func(value): flow.phrase = value; controls.delete_final.disabled = flow.busy or value != required_phrase)
		box.add_child(field); controls.delete_phrase = field
		button(box,"delete_final","Clear local details" if local_only else "Permanently delete","submit").disabled = flow.busy or flow.phrase != required_phrase
	label(box,flow.message,18)
	button(box,"delete_cancel","Back" if flow.store != null and flow.store.data.deletion_uncertain else "Keep my account","cancel").disabled = flow.busy
func label(box,text: String,font_size: int):
	var item = Label.new(); item.text = text; item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_override("font",P.SANS); item.add_theme_font_size_override("font_size",font_size); item.add_theme_color_override("font_color",P.PALE); box.add_child(item)
func button(box,id: String,caption: String,kind: String):
	var item = ButtonArt.new(); item.caption = caption; item.font_size = 18; item.custom_minimum_size.y = 54
	item.pressed.connect(func(): action.emit(kind)); box.add_child(item); controls[id] = item; return item
