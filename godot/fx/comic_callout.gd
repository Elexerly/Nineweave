extends Control
const P = preload("res://ui/paint.gd")
const A = preload("res://fx/announcer.gd")
var callout: String = ""
var age: float = 2
var rank: int = 1
var reduced_motion: bool = false
var frozen: bool = false
var region: Rect2
func _ready(): mouse_filter = Control.MOUSE_FILTER_IGNORE; z_index = 40
func show_callout(id: String):
	if not A.TEXT.has(id): return
	callout = id; rank = int(A.WEIGHT[id]); age = 0; queue_redraw()
func _process(delta):
	if not frozen: age += delta
	if age <= 1.2: queue_redraw()
func _draw():
	var duration = .55 if reduced_motion else .95
	if callout.is_empty() or age >= duration: return
	var t = age/duration
	var enter = 1-pow(1-clampf(t/.16,0,1),3)
	var alpha = 1-smoothstep(.72,1.0,t)
	var r = region; var center = r.get_center()
	if r.size.x < 8 or r.size.y < 8: return
	var sc = 1.0 if reduced_motion else lerpf(.72,1.0,enter)+sin(enter*PI)*.1
	var shake = Vector2.ZERO if reduced_motion else Vector2(sin(t*83),cos(t*69))*maxf(0,1-t*5)*2
	draw_set_transform(center+shake,-.035 if not reduced_motion else 0.0,Vector2.ONE*sc)
	var burst = PackedVector2Array()
	for i in range(32):
		var a = i*TAU/32
		burst.append(Vector2(cos(a)*r.size.x*.52,sin(a)*r.size.y*.6)*(1 if i%2 == 0 else .79))
	draw_colored_polygon(burst,Color("030917",alpha))
	draw_polyline(burst+PackedVector2Array([burst[0]]),Color(P.GOLD,alpha),2,true)
	P.text(self,A.TEXT[callout],Rect2(-r.size*.5,r.size),int(minf(40,r.size.y*.65)),Color(P.PALE,alpha),P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,.6)
	if not reduced_motion:
		for i in range(rank*2):
			var a = i*2.39996; var d = Vector2.from_angle(a)
			var pos = d*Vector2(r.size.x*.5,r.size.y*.7)*(1+t*.6)
			# Sparks shrink to nothing at the end; skip them before they degenerate.
			var spark = (1-t)*3
			if spark >= P.DIAMOND_MIN: P.diamond(self,pos,spark,Color(P.GOLD,alpha))
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
