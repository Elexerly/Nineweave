extends RefCounted
## Lightweight, resolution-independent arena entrance for the single versus lead-in.
## No external texture or extra scene; deterministic motion freezes at age zero.
const BLUE = Color("65d9ff")
const GOLD = Color("f5c66b")
static func draw_at(canvas: CanvasItem, extent: Vector2, age: float) -> void:
	if extent.x <= 0 or extent.y <= 0: return
	# Design in normalised coordinates so the vanishing point survives rotation.
	var w = extent.x; var h = extent.y
	var center = Vector2(w*.5,h*.44)
	canvas.draw_rect(Rect2(Vector2.ZERO,extent),Color("030713"))
	# Atmospheric arena beyond the entrance, not a second screen.
	for i in range(20,0,-1):
		var r = float(i)/20
		canvas.draw_circle(center, minf(w*.65,h*.54)*r,Color(.055,.16,.25,.025))
	# Receding bronze/obsidian arch bays, far to near.
	for i in range(6,0,-1):
		var t = float(i)/6
		var half = lerpf(w*.58,w*.15,t)
		var top = lerpf(-h*.12,h*.17,t)
		var foot = lerpf(h*1.08,h*.66,t)
		var shoulder = top+(foot-top)*.15
		var thickness = lerpf(w*.055,w*.009,t)
		var arch = PackedVector2Array([
			Vector2(center.x-half,foot), Vector2(center.x-half,shoulder),
			Vector2(center.x-half*.66,top),Vector2(center.x+half*.66,top),
			Vector2(center.x+half,shoulder),Vector2(center.x+half,foot)])
		canvas.draw_polyline(arch,Color("101b2b"),maxf(3,thickness*2.4),true)
		canvas.draw_polyline(arch,Color("263141"),maxf(2,thickness*1.2),true)
		canvas.draw_polyline(arch,Color(.49,.39,.24,lerpf(.75,.25,t)),maxf(1,thickness*.18),true)
		# Split light belongs to the two competitors, gold left / cyan right.
		for side in [-1,1]:
			var tint = GOLD if side == -1 else BLUE
			var x = center.x+half*side
			var a = Vector2(x,shoulder+thickness); var b = Vector2(x,foot-thickness)
			canvas.draw_line(a,b,Color(tint,.055),thickness*2.8,true)
			canvas.draw_line(a,b,Color(tint,.36),maxf(1.5,thickness*.24),true)
			canvas.draw_line(a,b,Color(tint,.75),maxf(1,thickness*.065),true)
	# A dark polished floor reaches into the arena.
	var horizon = h*.66
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0,h),Vector2(0,h*.77),Vector2(w*.35,horizon),Vector2(w*.65,horizon),Vector2(w,h*.77),Vector2(w,h)]),Color("070e1a"))
	for i in range(-4,5):
		var end = Vector2(w*.5+i*w*.23,h)
		canvas.draw_line(Vector2(w*.5+i*w*.018,horizon),end,Color(.24,.35,.46,.25),1,true)
	for i in range(1,7):
		var t = float(i)/7
		var y = lerpf(horizon,h,t*t)
		canvas.draw_line(Vector2(0,y),Vector2(w,y),Color(.27,.38,.48,.17),1,true)
	# Paired runway glows converge at the central gateway.
	for side in [-1,1]:
		var tint = GOLD if side == -1 else BLUE
		var a = Vector2(center.x+side*w*.12,horizon)
		var b = Vector2(center.x+side*w*.38,h)
		canvas.draw_line(a,b,Color(tint,.045),maxf(12,w*.04),true)
		canvas.draw_line(a,b,Color(tint,.3),2,true)
		canvas.draw_line(a,b,Color(tint,.8),.8,true)
	# High overhead light shafts keep the center legible, with subtle floor haze.
	for side in [-1,1]:
		var tint = GOLD if side == -1 else BLUE
		var top = Vector2(center.x+side*w*.21,0)
		canvas.draw_colored_polygon(PackedVector2Array([top,Vector2(center.x+side*w*.08,h*.67),Vector2(center.x+side*w*.3,h*.7)]),Color(tint,.035))
	for i in range(14):
		var y = h*.68+i*h*.018
		canvas.draw_rect(Rect2(0,y,w,h*.02),Color(.14,.24,.3,.035*(1-float(i)/14)))
	# Fine drifting motes, never flashes; deterministic and bounded.
	for i in range(22):
		var seed = float(i)
		var x = fposmod(seed*137.31+sin(age*.28+seed)*8,w)
		var y = fposmod(seed*89.17-age*(3+i%3),h)
		var tint = GOLD if x < w*.5 else BLUE
		canvas.draw_circle(Vector2(x,y),.6+float(i%3)*.3,Color(tint,.25))
	# Letterbox-grade top/bottom vignette. Central translucent scrim protects copy.
	for i in range(12):
		var a = .045+float(i)*.007
		canvas.draw_rect(Rect2(0,i*h*.013,w,h*.013),Color(0,.01,.025,a))
		canvas.draw_rect(Rect2(0,h-(i+1)*h*.014,w,h*.014),Color(0,.01,.025,a))
	canvas.draw_rect(Rect2(0,h*.37,w,h*.22),Color(.01,.025,.055,.72))
