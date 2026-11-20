extends Control
## Brief cold-start overlay. It never changes a player account or menu route.
const P = preload("res://ui/paint.gd")
const DURATION := 3.0
const FADE_IN := .28
const FADE_OUT := .32
const THANK_YOU := "Thanks for playing Lexerly!"
const SIGNATURE := "Patrick Booth"
signal dismissed
var elapsed := 0.0
var active := true

func _ready():
	z_index = 150
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
func _process(delta: float):
	elapsed += delta
	if elapsed >= DURATION:
		dismiss()
	else:
		queue_redraw()
func dismiss():
	if not active: return
	active = false
	set_process(false)
	hide()
	dismissed.emit()
static func card_rect(view: Vector2) -> Rect2:
	var dimensions := Vector2(clampf(view.x-40,1,550),clampf(view.y-36,1,278))
	return Rect2((view-dimensions)*.5,dimensions)
static func ink_alpha(seconds: float) -> float:
	return smoothstep(0.0,FADE_IN,seconds)*(1.0-smoothstep(DURATION-FADE_OUT,DURATION,seconds))
func _draw():
	var alpha := ink_alpha(elapsed)
	var veil := 1.0-smoothstep(DURATION-FADE_OUT,DURATION,elapsed)
	draw_rect(Rect2(Vector2.ZERO,size),Color(Color("080d1b"),veil))
	var rect := card_rect(size)
	P.panel(self,rect,false,alpha,true)
	var crest := Vector2(rect.get_center().x,rect.position.y+rect.size.y*.22)
	P.halo(self,crest,64.0,Color(P.GOLD,.14*alpha))
	var cell := minf(10.0,rect.size.y*.045)
	for row in 3:
		for col in 3:
			var center := crest+Vector2(col-1,row-1)*(cell+3.0)
			var square := Rect2(center-Vector2.ONE*cell*.5,Vector2.ONE*cell)
			draw_rect(square,Color(P.GOLD,(.35 if row == 1 and col == 1 else .075)*alpha))
			draw_rect(square,Color(P.GOLD,.53*alpha),false,1.0)
	var w := rect.size.x
	var h := rect.size.y
	var line := Rect2(rect.position.x+16,rect.position.y+h*.39,w-32,h*.23)
	var sign := Rect2(rect.position.x+18,rect.position.y+h*.70,w-36,h*.18)
	var rule := rect.position+Vector2(w*.5,h*.66)
	var stroke := minf(w*.27,101.0)
	draw_line(rule-Vector2(stroke,0),rule+Vector2(stroke,0),Color(P.GOLD,.48*alpha),1.0,true)
	P.diamond(self,rule,3.0,Color(P.GOLD,.92*alpha))
	P.text(self,THANK_YOU,line,P.fit_box(THANK_YOU,line,32,P.SERIF),Color(P.PALE,alpha),P.SERIF)
	P.text(self,SIGNATURE,sign,P.fit_box(SIGNATURE,sign,27,P.SERIF),Color(P.GOLD,alpha),P.SERIF)
