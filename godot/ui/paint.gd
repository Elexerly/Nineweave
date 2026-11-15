class_name NineweavePaint
extends RefCounted
const SERIF = preload("res://assets/fonts/Cinzel-Variable.ttf")
const DISPLAY = preload("res://assets/fonts/CinzelDecorative-Bold.ttf")
const SANS = preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const GOLD = Color("d6ad65")
const PALE = Color("fff0be")
const BLUE = Color("42dcff")
const WHITE = Color("e1effb")
const MUTED = Color("89a6bf")
const NAVY = Color("07172b")
static func polygon(r: Rect2, cut: float = 9) -> PackedVector2Array:
	var x = r.position.x; var y = r.position.y; var w = r.size.x; var h = r.size.y
	var c = minf(cut,minf(w,h)*.22)
	return PackedVector2Array([Vector2(x+c,y),Vector2(x+w-c,y),Vector2(x+w,y+c),Vector2(x+w,y+h-c),Vector2(x+w-c,y+h),Vector2(x+c,y+h),Vector2(x,y+h-c),Vector2(x,y+c)])
static func outline(node: CanvasItem, r: Rect2, color: Color, width: float = 1.0, cut: float = 9):
	var points = polygon(r,cut); points.append(points[0]); node.draw_polyline(points,color,width,true)
static func panel(node: CanvasItem, r: Rect2, active: bool = false, alpha: float = 1.0, ornament: bool = false):
	var gold = GOLD; gold.a = alpha
	node.draw_colored_polygon(polygon(r.grow(3)),Color(0,0,0,.65*alpha))
	node.draw_colored_polygon(polygon(r),Color(.025,.065,.12,.96*alpha))
	node.draw_colored_polygon(polygon(Rect2(r.position+Vector2(2,2),Vector2(r.size.x-4,r.size.y*.48))),Color(.06,.14,.22,.32*alpha))
	outline(node,r,gold.darkened(.5),3)
	outline(node,r.grow(-1),gold,1.2)
	outline(node,r.grow(-4),Color(.22,.29,.31,.7*alpha),.8,7)
	node.draw_line(r.position+Vector2(10,1),Vector2(r.end.x-10,r.position.y+1),PALE*Color(1,1,1,.7*alpha),1,true)
	if active:
		for k in range(4,0,-1): outline(node,r.grow(k*1.3),Color(.1,.8,1,.12/k),k*2.0)
		outline(node,r,BLUE,2)
	if ornament:
		for pos in [r.position+Vector2(6,6),Vector2(r.end.x-6,r.position.y+6),r.end-Vector2(6,6),Vector2(r.position.x+6,r.end.y-6)]:
			diamond(node,pos,3.2,gold)
static func diamond(node: CanvasItem, center: Vector2, radius: float, color: Color):
	node.draw_colored_polygon(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius*.7,0),center+Vector2(0,radius),center+Vector2(-radius*.7,0)]),color)
static func text(node: CanvasItem, value: String, r: Rect2, font_size: int = 18, color: Color = WHITE, font: Font = SANS, align: int = HORIZONTAL_ALIGNMENT_CENTER):
	var fs = font_size
	while font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > r.size.x-4 and fs > 9: fs -= 1
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var x = r.position.x+(r.size.x-width)*.5
	if align == HORIZONTAL_ALIGNMENT_LEFT: x = r.position.x+3
	if align == HORIZONTAL_ALIGNMENT_RIGHT: x = r.end.x-width-3
	var y = r.position.y+(r.size.y-font.get_height(fs))*.5+font.get_ascent(fs)
	node.draw_string(font,Vector2(x+1,y+2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color(0,0,0,.8))
	node.draw_string(font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
static func line_glow(node: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float):
	for i in [5,3,2]: node.draw_line(a,b,Color(color,i*.016),width*i,true)
	node.draw_line(a,b,color,width,true)
	node.draw_line(a,b,Color("edfdff") if color.b > .8 else PALE,maxf(.7,width*.28),true)
static func mark(node: CanvasItem, center: Vector2, radius: float, player: int, alpha: float = 1, power: float = 1):
	var color = BLUE if player == 1 else GOLD.lightened(.12)
	color.a = alpha
	if player == 1:
		var d = Vector2(radius*.64,radius*.64)
		for k in [5,3,2]:
			var glow = Color(color,.035*alpha*power)
			node.draw_line(center-d,center+d,glow,maxf(1.2,radius*.17)*k,true)
			node.draw_line(center+Vector2(-d.x,d.y),center+Vector2(d.x,-d.y),glow,maxf(1.2,radius*.17)*k,true)
		for endpoints in [[center-d,center+d],[center+Vector2(-d.x,d.y),center+Vector2(d.x,-d.y)]]:
			node.draw_line(endpoints[0]+Vector2(1,2),endpoints[1]+Vector2(1,2),Color(.005,.17,.28,alpha),maxf(2,radius*.24),true)
			node.draw_line(endpoints[0],endpoints[1],color,maxf(1.8,radius*.15),true)
			node.draw_line(endpoints[0]-Vector2(0,.8),endpoints[1]-Vector2(0,.8),Color(.8,1,1,alpha),maxf(.7,radius*.045),true)
	else:
		for k in [5,3,2]: node.draw_arc(center,radius*.78,0,TAU,48,Color(color,.04*alpha*power),maxf(1,radius*.14)*k,true)
		node.draw_arc(center+Vector2(1,2),radius*.78,0,TAU,48,Color(.22,.1,.01,alpha),maxf(2,radius*.2),true)
		node.draw_arc(center,radius*.78,0,TAU,48,color,maxf(1.6,radius*.13),true)
		node.draw_arc(center-Vector2(0,.7),radius*.81,PI,TAU*1.4,40,Color(1,.96,.75,alpha),maxf(.7,radius*.05),true)
		for i in range(3): diamond(node,center+Vector2.from_angle(-.8+i*2.5)*radius*.8,radius*.085,Color(1,1,.85,alpha))
static func crown(node: CanvasItem, pos: Vector2, scale_value: float = 1):
	var points = PackedVector2Array([Vector2(-13,4),Vector2(-16,-7),Vector2(-6,-1),Vector2(0,-14),Vector2(6,-1),Vector2(16,-7),Vector2(13,4)])
	for i in points.size(): points[i] = pos+points[i]*scale_value
	node.draw_colored_polygon(points,GOLD)
	node.draw_line(pos+Vector2(-12,6)*scale_value,pos+Vector2(12,6)*scale_value,PALE,2,true)
	for x in [-16,0,16]: diamond(node,pos+Vector2(x,-7 if x != 0 else -14)*scale_value,2.5*scale_value,PALE)
static func crystal(node: CanvasItem, pos: Vector2, scale_value: float, color: Color, rotation: float = 0):
	var local = [Vector2(0,-1),Vector2(.28,-.38),Vector2(.22,.64),Vector2(0,1),Vector2(-.23,.6),Vector2(-.28,-.38)]
	var p = PackedVector2Array()
	for v in local: p.append(pos+v.rotated(rotation)*scale_value)
	node.draw_colored_polygon(p,color.darkened(.48))
	node.draw_colored_polygon(PackedVector2Array([p[0],p[1],pos,p[5]]),color.lightened(.25))
	node.draw_colored_polygon(PackedVector2Array([p[1],p[2],p[3],pos]),color.darkened(.16))
	node.draw_polyline(PackedVector2Array([p[0],pos,p[3],p[4],p[5],p[0],p[1],p[2],p[3]]),color.lightened(.4),1,true)
