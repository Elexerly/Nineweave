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
		# Round 3c: icon + caption fitted inside the frame; narrow phone buttons stack.
		var g = caption_layout(size,label,font_size)
		_icon(kind,g.icon_center,g.icon_size,color)
		P.text(self,label,g.text_rect,g.fs,color,P.SANS,HORIZONTAL_ALIGNMENT_LEFT if not g.stacked else HORIZONTAL_ALIGNMENT_CENTER)
	if has_focus(): P.outline(self,r.grow(-7),P.BLUE,.8)
func _icon(kind: String, center: Vector2, s: float, color: Color):
	if kind in ["sound_on","sound_off"]:
		var speaker = PackedVector2Array([center+Vector2(-s,-s*.35),center+Vector2(-s*.45,-s*.35),center+Vector2(s*.1,-s*.85),center+Vector2(s*.1,s*.85),center+Vector2(-s*.45,s*.35),center+Vector2(-s,s*.35)])
		draw_colored_polygon(speaker,color)
		if kind == "sound_on":
			draw_arc(center+Vector2(-s*.05,0),s*.65,-PI*.35,PI*.35,16,color,2,true)
			draw_arc(center+Vector2(-s*.05,0),s,-PI*.32,PI*.32,16,color,2,true)
		else:
			draw_line(center+Vector2(s*.4,-s*.4),center+Vector2(s,s*.4),color,2,true)
			draw_line(center+Vector2(s*.4,s*.4),center+Vector2(s,-s*.4),color,2,true)
	elif kind == "x": P.mark(self,center,s*1.1,1)
	elif kind == "o": P.mark(self,center,s*1.1,2)
	else: P.icon(self,kind,center,s,color)
## Round 3c: geometry for an icon + caption button shorter than 62 px. `ink` is the
## caption's drawn extent; it always stays inside `inner` (inside the gold frame).
static func caption_layout(button_size: Vector2, label: String, font_size: int) -> Dictionary:
	var r = Rect2(Vector2(2,2),button_size-Vector2(4,4))
	var t = clampf(minf(r.size.x,r.size.y)*.07,2.6,5.0)
	var inner = r.grow(-(t+3))
	var s = minf(r.size.y*.26,12)
	var fs = font_size
	while fs > 9 and P.text_width(label,fs)+s*2.6+2 > inner.size.x: fs -= 1
	if fs >= mini(font_size,15) or r.size.y < 44:
		var tw = P.text_width(label,fs)
		var left = r.get_center().x-(tw+s*2.6)*.5
		return {"stacked":false,"fs":fs,"icon_center":Vector2(left+s,r.get_center().y),"icon_size":s,
			"text_rect":Rect2(left+s*2.6-3,r.position.y,tw+6,r.size.y),"ink":Rect2(left+s*2.6,r.get_center().y-fs*.5,tw,fs),"inner":inner}
	var si = minf(inner.size.y*.2,10)
	var tr = Rect2(inner.position.x,inner.position.y+inner.size.y*.5,inner.size.x,inner.size.y*.5)
	var sfs = P.fit_box(label,tr,font_size)
	while sfs > 9 and P.text_width(label,sfs)+2 > inner.size.x: sfs -= 1
	var w = P.text_width(label,sfs)
	return {"stacked":true,"fs":sfs,"icon_center":Vector2(inner.get_center().x,inner.position.y+inner.size.y*.26),"icon_size":si,
		"text_rect":tr,"ink":Rect2(tr.get_center().x-w*.5,tr.position.y,w,tr.size.y),"inner":inner}
