extends Node
## Reserve the actual keyboard overlap rather than assuming a device model.
var view: Control
var scroll: ScrollContainer
var original: Rect2
var last_height = -1
static func available_height(view_height: float, top: float, keyboard_height: float) -> float:
	return maxf(1.0,view_height-top-12.0-maxf(0.0,keyboard_height))
static func complete_code(value: String) -> bool:
	if value.length() != 6: return false
	for character in value:
		if character < "0" or character > "9": return false
	return true
func attach(owner_view: Control, container: ScrollContainer):
	view = owner_view; scroll = container; original = Rect2(scroll.position,scroll.size)
	view.add_child(self)
func _process(_delta):
	if not is_instance_valid(view) or not is_instance_valid(scroll): return
	var height = DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	if height == last_height: return
	last_height = height
	# Keyboard height and screen transform are in physical screen pixels.
	var scale_y = maxf(absf(view.get_screen_transform().get_scale().y),0.001)
	apply_height(float(height)/scale_y)
func apply_height(height: float):
	scroll.position.y = minf(original.position.y,12.0) if height > 0 else original.position.y
	scroll.size.y = minf(original.size.y,available_height(view.size.y,scroll.position.y,height))
	var focused = view.get_viewport().gui_get_focus_owner()
	if focused != null and scroll.is_ancestor_of(focused):
		scroll.ensure_control_visible.call_deferred(focused)
func code_changed(value: String, field: LineEdit, next_control: Control):
	if not complete_code(value): return
	# Numeric iOS keyboards have no Return key. Dismiss, never auto-submit.
	field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	if is_instance_valid(next_control): scroll.ensure_control_visible.call_deferred(next_control)
