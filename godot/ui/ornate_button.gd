extends Button
const P = preload("res://ui/paint.gd")
var caption: String = ""
## Optional procedural icon: gear, home, back, undo, hint, info, x, o.
var icon_kind: String = ""
var hot: bool = false
var accent: bool = false
var font_size: int = 18
var pulse: float = 0
func _init():
	custom_minimum_size = Vector2(44,44)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	for state in ["normal","hover","pressed","focus","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func(): hot = true)
	mouse_exited.connect(func(): hot = false)
func _process(delta):
	pulse = move_toward(pulse,1.0 if hot or has_focus() else 0.0,delta*7)
	queue_redraw()
func _draw():
	var r = Rect2(Vector2(2,2),size-Vector2(4,4))
	if accent: P.box_glow(self,r,Color(.1,.75,1,.28+.12*sin(P.clock*TAU/1.6)),8,8)
	P.panel(self,r,accent or pulse > .1,1,minf(r.size.x,r.size.y) >= 40)
	if pulse > 0: draw_colored_polygon(P.polygon(r.grow(-5)),Color(.12,.52,.68,pulse*.18))
	if is_pressed(): draw_colored_polygon(P.polygon(r.grow(-3)),Color(0,0,0,.3))
	var kind = icon_kind
	if caption == "⚙": kind = "gear"
	var color = P.PALE if not disabled else P.MUTED
	var label = "" if caption == "⚙" else caption
	if kind.is_empty():
		P.text(self,label,r,font_size,color,P.SANS)
	elif label.is_empty():
		_icon(kind,r.get_center(),minf(r.size.x,r.size.y)*.3,color)
	elif r.size.y >= 62:
		var s = r.size.y*.2
		_icon(kind,Vector2(r.get_center().x,r.position.y+r.size.y*.36),s,color)
		P.text(self,label,Rect2(r.position.x,r.position.y+r.size.y*.6,r.size.x,r.size.y*.34),font_size,color,P.SANS)
	else:
		var s = minf(r.size.y*.26,12)
		var tw = P.text_width(label,P.fit_size(label,r.size.x-s*3,font_size))
		var left = r.get_center().x-(tw+s*2.6)*.5
		_icon(kind,Vector2(left+s,r.get_center().y),s,color)
		P.text(self,label,Rect2(left+s*2.6,r.position.y,tw+6,r.size.y),font_size,color,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	if has_focus(): P.outline(self,r.grow(-7),P.BLUE,.8)
func _icon(kind: String, center: Vector2, s: float, color: Color):
	if kind == "x": P.mark(self,center,s*1.1,1)
	elif kind == "o": P.mark(self,center,s*1.1,2)
	else: P.icon(self,kind,center,s,color)
