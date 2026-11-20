extends Control
## Brief cold-start overlay. It never changes a player account or menu route.
const P = preload("res://ui/paint.gd")
const GoldLabel = preload("res://ui/gold_label.gd")
const CASTLE = preload("res://assets/art/distant_castle.png")
const DURATION := 3.8
const FADE_IN := .46
const FADE_OUT := .47
const THANK_YOU := "Thanks for playing Lexerly!"
const SIGNATURE := "Patrick Booth"
signal dismissed
var elapsed := 0.0
var active := true
var reduced_motion := false
var seam := Rect2():
	set(value):
		seam = value
		if is_instance_valid(_signature): _relayout()
var _signature: Label

func _ready():
	z_index = 150
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_signature = GoldLabel.new()
	add_child(_signature)
	resized.connect(_relayout)
	_relayout()
func _relayout():
	var rect := card_rect(size,seam)
	var sign := Rect2(rect.position+Vector2(18,rect.size.y*.75),Vector2(maxf(1,rect.size.x-36),rect.size.y*.16))
	_signature.place(sign,SIGNATURE,P.SERIF,P.fit_box(SIGNATURE,sign,31,P.SERIF),reduced_motion)
	_signature.modulate.a = ink_alpha(elapsed)
	queue_redraw()
func _process(delta: float):
	elapsed += delta
	if elapsed >= DURATION:
		dismiss()
	else:
		_signature.modulate.a = ink_alpha(elapsed)
		queue_redraw()
func dismiss():
	if not active: return
	active = false
	set_process(false)
	hide()
	dismissed.emit()
static func card_rect(view: Vector2, hinge: Rect2 = Rect2()) -> Rect2:
	var pane := Rect2(Vector2.ZERO,view)
	if hinge.has_area() and hinge.position.x > 0 and hinge.end.x < view.x:
		var right := view.x-hinge.end.x
		pane = Rect2(0,0,hinge.position.x,view.y) if hinge.position.x >= right else Rect2(hinge.end.x,0,right,view.y)
	var dimensions := Vector2(clampf(pane.size.x-40,1,580),clampf(pane.size.y-36,1,340))
	return Rect2(pane.get_center()-dimensions*.5,dimensions)
static func art_rect(card: Rect2) -> Rect2:
	var width := maxf(1,minf(card.size.x-34,card.size.y*.43*float(CASTLE.get_width())/CASTLE.get_height()))
	var extent := Vector2(width,width*float(CASTLE.get_height())/CASTLE.get_width())
	return Rect2(Vector2(card.get_center().x-extent.x*.5,card.position.y+card.size.y*.095),extent)
static func ink_alpha(seconds: float) -> float:
	return smoothstep(0.0,FADE_IN,seconds)*(1.0-smoothstep(DURATION-FADE_OUT,DURATION,seconds))
func _draw():
	var alpha := ink_alpha(elapsed)
	var veil := 1.0-smoothstep(DURATION-FADE_OUT,DURATION,elapsed)
	draw_rect(Rect2(Vector2.ZERO,size),Color(Color("080d1b"),veil))
	var rect := card_rect(size,seam)
	P.panel(self,rect,false,alpha,true)
	var art := art_rect(rect)
	P.halo(self,art.get_center(),art.size.x*.48,Color(P.GOLD,.19*alpha))
	draw_texture_rect(CASTLE,art,false,Color(1,1,1,alpha))
	P.outline(self,art.grow(2),Color(P.GOLD,.68*alpha),1.4)
	P.diamond(self,Vector2(art.get_center().x,art.end.y+3),4.0,Color(P.GOLD,.88*alpha))
	var w := rect.size.x
	var h := rect.size.y
	var line := Rect2(rect.position.x+16,rect.position.y+h*.58,w-32,h*.15)
	var rule := rect.position+Vector2(w*.5,h*.743)
	var stroke := minf(w*.27,101.0)
	draw_line(rule-Vector2(stroke,0),rule+Vector2(stroke,0),Color(P.GOLD,.48*alpha),1.0,true)
	P.diamond(self,rule,3.0,Color(P.GOLD,.92*alpha))
	P.text(self,THANK_YOU,line,P.fit_box(THANK_YOU,line,32,P.SERIF),Color(P.PALE,alpha),P.SERIF)
