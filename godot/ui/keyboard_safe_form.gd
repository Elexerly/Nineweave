extends Node
## Reserve keyboard overlap in canvas coordinates. iOS reports pixels; its
## CanvasItem screen transform can describe points instead of device pixels.
var view: Control
var scroll: ScrollContainer
var original: Rect2
var last_metrics := Vector4(-1,-1,-1,-1)
var original_bottom := 12.0

static func logical_keyboard_height(raw_height: float, pixel_height: float, canvas_height: float, transform_scale: float, native_ios: bool) -> float:
	if raw_height <= 0: return 0.0
	if native_ios and pixel_height > 0 and canvas_height > 0:
		return raw_height * canvas_height / pixel_height
	return raw_height / maxf(absf(transform_scale),0.001)

static func available_height(view_height: float, top: float, keyboard_height: float) -> float:
	var without_keyboard := maxf(1.0,view_height-top-12.0)
	# Transitional keyboard/window metrics may disagree during fold or rotate.
	# Keep an aperture at least one full control tall; the rest is scrollable.
	var minimum := minf(without_keyboard,clampf(view_height*.25,72.0,132.0))
	return floorf(clampf(without_keyboard-maxf(0.0,keyboard_height),minimum,without_keyboard))
static func complete_code(value: String) -> bool:
	if value.length() != 6: return false
	for character in value:
		if character < "0" or character > "9": return false
	return true
func attach(owner_view: Control, container: ScrollContainer):
	view = owner_view; scroll = container; original = Rect2(scroll.position,scroll.size)
	original_bottom = maxf(0.0,view.size.y-original.end.y)
	view.add_child(self)
func _process(_delta):
	if not is_instance_valid(view) or not is_instance_valid(scroll): return
	var height := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	var canvas_height := view.get_viewport_rect().size.y
	var window_height := float(DisplayServer.window_get_size(view.get_window().get_window_id()).y) if OS.has_feature("ios") and is_instance_valid(view.get_window()) else 0.0
	var scale_y := view.get_screen_transform().get_scale().y
	apply_keyboard_metrics(float(height),window_height,canvas_height,scale_y,OS.has_feature("ios"))
func apply_keyboard_metrics(raw_height: float, pixel_height: float, canvas_height: float, transform_scale: float, native_ios: bool):
	var metrics := Vector4(raw_height,pixel_height,canvas_height,transform_scale)
	if metrics == last_metrics: return
	last_metrics = metrics
	apply_height(logical_keyboard_height(raw_height,pixel_height,canvas_height,transform_scale,native_ios),canvas_height)
func apply_height(height: float, canvas_height: float = 0.0):
	var extent := minf(view.size.y,canvas_height) if canvas_height > 0 else view.size.y
	scroll.position.y = minf(original.position.y,12.0) if height > 0 else original.position.y
	var base_height := maxf(1.0,extent-original.position.y-original_bottom)
	scroll.size.y = minf(base_height,available_height(extent,scroll.position.y,height)) if height > 0 else base_height
	var focused = view.get_viewport().gui_get_focus_owner()
	if focused != null and scroll.is_ancestor_of(focused):
		scroll.ensure_control_visible.call_deferred(focused)
func code_changed(value: String, field: LineEdit, next_control: Control):
	if not complete_code(value): return
	# Numeric iOS keyboards have no Return key. Dismiss, never auto-submit.
	field.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	if is_instance_valid(next_control): scroll.ensure_control_visible.call_deferred(next_control)
