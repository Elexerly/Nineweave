extends Button
const P = preload("res://ui/paint.gd")
var caption: String = ""
var hot: bool = false
var accent: bool = false
var font_size: int = 18
var pulse: float = 0
func _init():
	custom_minimum_size = Vector2(44,44)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
	add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
	mouse_entered.connect(func(): hot = true)
	mouse_exited.connect(func(): hot = false)
func _process(delta):
	pulse = move_toward(pulse,1.0 if hot or has_focus() else 0.0,delta*7)
	queue_redraw()
func _draw():
	var r = Rect2(Vector2(2,2),size-Vector2(4,4))
	P.panel(self,r,accent or pulse > .1,1,true)
	if pulse > 0: draw_colored_polygon(P.polygon(r.grow(-5)),Color(.12,.52,.68,pulse*.18))
	if is_pressed(): draw_colored_polygon(P.polygon(r.grow(-3)),Color(0,0,0,.3))
	if caption == "⚙":
		var center = r.get_center()
		for i in range(8):
			var angle = i*TAU/8
			draw_line(center+Vector2.from_angle(angle)*8,center+Vector2.from_angle(angle)*13,P.GOLD,4,true)
		draw_arc(center,8,0,TAU,32,P.PALE,3,true)
		draw_arc(center,3,0,TAU,24,P.GOLD,1.5,true)
	else: P.text(self,caption,r,font_size,P.PALE if not disabled else P.MUTED,P.SANS)
	if has_focus(): P.outline(self,r.grow(-7),P.BLUE,.8)
