extends RefCounted
## One inked comic-book splash, not an extra scene. No external assets, flashes,
## camera motion or timing changes. Static artwork also suits a frozen capture.
const P = preload("res://ui/paint.gd")
const INK = Color("081223")
const PAPER = Color("fff2c9")
const GOLD = Color("ffc84c")
const BLUE = Color("35cbe8")
static func layout(extent: Vector2) -> Dictionary:
	var unit = minf(extent.x,extent.y)
	var width = minf(extent.x-32,extent.y*1.45)
	var height = minf(extent.y*.50,width*.65)
	var panel = Rect2((extent.x-width)*.5,(extent.y-height)*.5,width,height)
	return {"unit":unit,"panel":panel,"skip":Rect2(16,extent.y-42,extent.x-32,28)}
static func draw_at(canvas: CanvasItem, extent: Vector2, _age: float) -> void:
	if extent.x <= 0 or extent.y <= 0: return
	var g = layout(extent); var w = extent.x; var h = extent.y
	var center = extent*.5; var unit: float = g.unit
	canvas.draw_rect(Rect2(Vector2.ZERO,extent),INK)
	# Opposing printed color plates, deliberately offset at the central slash.
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(8,8),Vector2(w*.59,8),Vector2(w*.39,h-8),Vector2(8,h-8)]),GOLD)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(w*.61,8),Vector2(w-8,8),Vector2(w-8,h-8),Vector2(w*.41,h-8)]),BLUE)
	# Thick speed rays radiate OUT of the lettering, rather than moving/flashing.
	for i in range(32):
		var angle = float(i)*TAU/32
		var radius = extent.length()
		var tip = center+Vector2.from_angle(angle)*unit*.18
		var a = center+Vector2.from_angle(angle-.022)*radius
		var b = center+Vector2.from_angle(angle+.022)*radius
		canvas.draw_colored_polygon(PackedVector2Array([tip,a,b]),Color(INK,.18 if i%3 else .46))
	# Coarse halftone corners: bounded dot count at every viewport size.
	for row in range(16):
		for col in range(12):
			var at = Vector2((col+.5)*w/24,(row+.5)*h/16)
			if at.distance_to(center) < unit*.36: continue
			var radius = minf(w/24,h/16)*(.10+.07*float((col+row)%3))
			canvas.draw_circle(at,radius,Color(INK,.25))
			canvas.draw_circle(extent-at,radius,Color(INK,.25))
	# Inked arena floor and paired monumental gates anchor the comic to a clash.
	for side in [-1,1]:
		var edge = 12.0 if side < 0 else w-12
		var inner = w*.16 if side < 0 else w*.84
		var points = PackedVector2Array([Vector2(edge,h*.12),Vector2(inner,h*.21),Vector2(inner,h*.77),Vector2(edge,h*.90)])
		canvas.draw_colored_polygon(points,INK)
		canvas.draw_line(Vector2(inner,h*.24),Vector2(inner,h*.74),PAPER,2,true)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0,h),Vector2(w*.36,h*.76),Vector2(w*.64,h*.76),Vector2(w,h)]),INK)
	for i in range(-3,4):
		canvas.draw_line(Vector2(w*.5+i*w*.025,h*.77),Vector2(w*.5+i*w*.24,h),Color(PAPER,.25),1,true)
	# Staggered ink shadow and irregular burst, with a quiet solid title panel.
	var r: Rect2 = g.panel
	var burst = PackedVector2Array()
	for i in range(24):
		var a = i*TAU/24
		var scale = 1.13 if i%2 == 0 else .95
		burst.append(center+Vector2(cos(a)*r.size.x*.52,sin(a)*r.size.y*.60)*scale)
	canvas.draw_colored_polygon(burst,INK)
	canvas.draw_polyline(burst+PackedVector2Array([burst[0]]),PAPER,3,true)
	var plate = PackedVector2Array([r.position+Vector2(r.size.x*.05,0),Vector2(r.end.x,r.position.y+r.size.y*.04),r.end-Vector2(r.size.x*.05,0),Vector2(r.position.x,r.end.y-r.size.y*.04)])
	canvas.draw_colored_polygon(plate,PAPER)
	canvas.draw_polyline(plate+PackedVector2Array([plate[0]]),INK,5,true)
	var top = Rect2(r.position.x+r.size.x*.09,r.position.y+r.size.y*.06,r.size.x*.82,r.size.y*.20)
	var title = Rect2(r.position.x+r.size.x*.05,r.position.y+r.size.y*.25,r.size.x*.90,r.size.y*.26)
	var second = Rect2(title.position.x,r.position.y+r.size.y*.50,title.size.x,r.size.y*.26)
	var tag = Rect2(r.position.x+r.size.x*.13,r.position.y+r.size.y*.81,r.size.x*.74,r.size.y*.12)
	P.text(canvas,"TWO HAVE",top,P.fit_box("TWO HAVE",top,52,P.SANS),INK,P.SANS)
	# Offset print registration shadows give the headline depth without fuzzy glow.
	var fs = mini(P.fit_box("STEPPED",title,84,P.SANS),P.fit_box("FORWARD",second,84,P.SANS))
	for item in [["STEPPED",title],["FORWARD",second]]:
		var shadow = Rect2(item[1].position+Vector2(3,3),item[1].size)
		P.text(canvas,item[0],shadow,fs,Color("d88c28"),P.SANS)
		P.text(canvas,item[0],item[1],fs,INK,P.SANS)
	canvas.draw_rect(tag,INK)
	P.text(canvas,"THE CLASH AWAITS",tag,P.fit_box("THE CLASH AWAITS",tag,20,P.SANS),PAPER,P.SANS)
	# Always a solid dark reading surface behind the existing skip affordance.
	canvas.draw_rect(Rect2(0,h-48,w,48),INK)
	P.text(canvas,"TAP TO SKIP",g.skip,14,PAPER,P.SANS)
