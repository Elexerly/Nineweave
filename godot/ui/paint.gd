class_name NineweavePaint
extends RefCounted
## Round 2 paint kit. Marks are cached vertex-coloured meshes (one draw call each, plus
## a shadow and two soft halo quads), frames are lit per-edge bevel bands, glows are
## soft radial textures or StyleBoxFlat shadows. Compatibility-renderer safe.
const SERIF = preload("res://assets/fonts/Cinzel-Variable.ttf")
const DISPLAY = preload("res://assets/fonts/CinzelDecorative-Bold.ttf")
const SANS = preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const GOLD = Color("d6ad65")
const PALE = Color("fff0be")
const BLUE = Color("42dcff")
const WHITE = Color("e1effb")
const MUTED = Color("89a6bf")
const NAVY = Color("07172b")
const GOLD_DARK = Color("2a1806")
const LIGHT = Vector2(-0.6,-0.8)
## Shared animation clock for shimmer/glints; the controller advances it, captures pin it.
static var clock: float = 0.0
static var _glow: Texture2D
static var _x_mesh: ArrayMesh
static var _o_mesh: ArrayMesh
static var _glow_box: StyleBoxFlat

static func glow_texture() -> Texture2D:
	if _glow == null:
		var g = Gradient.new()
		g.offsets = PackedFloat32Array([0.0,.22,.5,.78,1.0])
		g.colors = PackedColorArray([Color(1,1,1,1),Color(1,1,1,.62),Color(1,1,1,.2),Color(1,1,1,.05),Color(1,1,1,0)])
		var t = GradientTexture2D.new()
		t.gradient = g; t.width = 128; t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(.5,.5); t.fill_to = Vector2(1,.5)
		_glow = t
	return _glow
## Soft round light, centred; normal blend on dark art reads as bloom.
static func halo(node: CanvasItem, center: Vector2, radius: float, color: Color):
	if radius <= .5 or color.a <= .003: return
	node.draw_texture_rect(glow_texture(),Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2),false,color)
## Elliptical/stretched variant (title glow, beams).
static func halo_rect(node: CanvasItem, r: Rect2, color: Color):
	if color.a <= .003: return
	node.draw_texture_rect(glow_texture(),r,false,color)
## Soft rectangular glow around a rounded rect (StyleBoxFlat shadow).
static func box_glow(node: CanvasItem, r: Rect2, color: Color, spread: float, radius: float = 10):
	if color.a <= .003: return
	if _glow_box == null:
		_glow_box = StyleBoxFlat.new(); _glow_box.draw_center = false; _glow_box.anti_aliasing = true
	_glow_box.bg_color = Color(0,0,0,0)
	_glow_box.set_corner_radius_all(int(radius))
	_glow_box.shadow_color = color; _glow_box.shadow_size = int(maxf(1,spread))
	node.draw_style_box(_glow_box,r)

## Soft glow hugging a chamfered rect: gradient band from `color` at the edge to transparent
## `spread` px away (outward if spread > 0, inward rim light if < 0). No interior fill.
static func edge_glow(node: CanvasItem, r: Rect2, color: Color, spread: float, cut: float = 9):
	if color.a <= .003 or absf(spread) < .5: return
	var a = polygon(r,cut); var b = polygon(r.grow(spread),maxf(0,cut+spread*.41))
	var clear = Color(color,0)
	for i in range(8):
		var j = (i+1)%8
		node.draw_primitive(PackedVector2Array([a[i],a[j],b[j],b[i]]),PackedColorArray([color,color,clear,clear]),PackedVector2Array())
static func polygon(r: Rect2, cut: float = 9) -> PackedVector2Array:
	var x = r.position.x; var y = r.position.y; var w = r.size.x; var h = r.size.y
	var c = maxf(0,minf(cut,minf(w,h)*.22))
	return PackedVector2Array([Vector2(x+c,y),Vector2(x+w-c,y),Vector2(x+w,y+c),Vector2(x+w,y+h-c),Vector2(x+w-c,y+h),Vector2(x+c,y+h),Vector2(x,y+h-c),Vector2(x,y+c)])
const EDGE_NORMALS = [Vector2(0,-1),Vector2(.7071,-.7071),Vector2(1,0),Vector2(.7071,.7071),Vector2(0,1),Vector2(-.7071,.7071),Vector2(-1,0),Vector2(-.7071,-.7071)]
static func outline(node: CanvasItem, r: Rect2, color: Color, width: float = 1.0, cut: float = 9):
	var points = polygon(r,cut); points.append(points[0]); node.draw_polyline(points,color,width,true)
static func _lit(n: Vector2) -> float: return n.dot(LIGHT.normalized())
## Gold ramp: 0 deep bronze, .5 rich gold, 1 pale highlight.
static func gold_ramp(t: float, alpha: float = 1) -> Color:
	t = clampf(t,0,1)
	var c = Color("5c3a0e").lerp(Color("d9a446"),t*2) if t < .5 else Color("d9a446").lerp(Color("fff3c4"),(t-.5)*2)
	c.a = alpha; return c
## Lit bevel band between two chamfered polygons (one quad per edge, vertex coloured).
static func _band(node: CanvasItem, outer: PackedVector2Array, inner: PackedVector2Array, outer_t: float, inner_t: float, spread: float, alpha: float):
	for i in range(8):
		var j = (i+1)%8
		var b = _lit(EDGE_NORMALS[i])
		var co = gold_ramp(outer_t+b*spread,alpha); var ci = gold_ramp(inner_t+b*spread*.6,alpha)
		if outer[i].distance_squared_to(outer[j]) < .01: continue
		node.draw_primitive(PackedVector2Array([outer[i],outer[j],inner[j],inner[i]]),PackedColorArray([co,co,ci,ci]),PackedVector2Array())
## Heavy multi-band bevelled gold frame: dark rim, lit outer bevel, bright ridge, mid gold, inner dark line.
static func gold_frame(node: CanvasItem, r: Rect2, thickness: float = 4.0, cut: float = 9, alpha: float = 1.0):
	var t = maxf(2.0,thickness)
	var o0 = polygon(r.grow(1.2),cut+.5)
	var o1 = polygon(r,cut)
	var o2 = polygon(r.grow(-t*.45),cut-t*.19)
	var o3 = polygon(r.grow(-t),cut-t*.41)
	var o4 = polygon(r.grow(-t-1.1),cut-t*.41-.45)
	_ring(node,o0,o1,Color(GOLD_DARK,.95*alpha))
	_band(node,o1,o2,.62,.86,.36,alpha)
	_band(node,o2,o3,.5,.36,.3,alpha)
	_ring(node,o3,o4,Color(.07,.04,.01,.9*alpha))
	# Bright ridge between the two bevel bands, strongest on the lit (top-left) edges.
	var ridge = PackedVector2Array(); var colors = PackedColorArray()
	for i in range(9):
		var k = i%8
		ridge.append(o2[k])
		var n = (EDGE_NORMALS[k]+EDGE_NORMALS[(k+7)%8]).normalized()
		colors.append(Color(1,.96,.8,clampf(.25+_lit(n)*.6,.05,.85)*alpha))
	node.draw_polyline_colors(ridge,colors,maxf(.8,t*.16),true)
static func _ring(node: CanvasItem, outer: PackedVector2Array, inner: PackedVector2Array, color: Color):
	for i in range(8):
		var j = (i+1)%8
		node.draw_primitive(PackedVector2Array([outer[i],outer[j],inner[j],inner[i]]),PackedColorArray([color,color,color,color]),PackedVector2Array())
## Travelling glint along the top edge of a frame (draw-based shimmer).
static func glint(node: CanvasItem, r: Rect2, alpha: float = 1.0, period: float = 5.5):
	var phase = fmod(clock/period+fmod(r.position.x*.0031+r.position.y*.0017,1.0),1.0)
	var span = r.size.x*1.6
	var x = r.position.x-r.size.x*.3+phase*span
	var half = minf(42,r.size.x*.18)
	var a = maxf(r.position.x+4,x-half); var b = minf(r.end.x-4,x+half)
	if b <= a: return
	var m = clampf(x,a,b)
	var y = r.position.y+.6
	node.draw_polyline_colors(PackedVector2Array([Vector2(a,y),Vector2(m,y),Vector2(b,y)]),PackedColorArray([Color(1,.95,.75,0),Color(1,.98,.88,.9*alpha),Color(1,.95,.75,0)]),2.2,true)
	halo(node,Vector2(m,y),5,Color(1,.93,.7,.55*alpha))
## Ornate corner: cut jewel with gold setting and two tapered scroll flourishes.
static func corner_ornament(node: CanvasItem, pos: Vector2, inward: Vector2, s: float, jewel: Color = BLUE, alpha: float = 1.0):
	var ax = Vector2(inward.x,0); var ay = Vector2(0,inward.y)
	for axis in [ax,ay]:
		var p0 = pos+axis*s*.6
		var p1 = pos+axis*s*2.6
		var w = s*.34
		var perp = Vector2(-axis.y,axis.x)
		node.draw_colored_polygon(PackedVector2Array([p0+perp*w,p1,p0-perp*w]),gold_ramp(.72,alpha))
		node.draw_line(p0,p1,Color(1,.95,.75,.55*alpha),maxf(.6,s*.1),true)
		node.draw_circle(p1,s*.17,gold_ramp(.85,alpha))
	diamond(node,pos,s*1.05,Color(GOLD_DARK,alpha))
	diamond(node,pos,s*.9,gold_ramp(.66,alpha))
	diamond(node,pos-Vector2(0,s*.08),s*.52,Color(jewel.darkened(.25),alpha))
	diamond(node,pos-Vector2(s*.06,s*.18),s*.22,Color(1,1,1,.85*alpha))
	halo(node,pos,s*2.2,Color(jewel,.18*alpha))

static func panel(node: CanvasItem, r: Rect2, active: bool = false, alpha: float = 1.0, ornament: bool = false):
	if r.size.x < 4 or r.size.y < 4: return
	var cut = minf(9,minf(r.size.x,r.size.y)*.2)
	var t = clampf(minf(r.size.x,r.size.y)*.07,2.6,5.0)
	node.draw_colored_polygon(polygon(r.grow(3),cut+1),Color(0,0,0,.5*alpha))
	var body = polygon(r.grow(-1),cut)
	var top = Color(.055,.13,.24,.97*alpha); var bottom = Color(.012,.035,.08,.97*alpha)
	var cols = PackedColorArray()
	for p in body: cols.append(top.lerp(bottom,clampf((p.y-r.position.y)/r.size.y,0,1)))
	node.draw_polygon(body,cols)
	# Glassy sheen in the upper half.
	node.draw_colored_polygon(polygon(Rect2(r.position+Vector2(t+1,t+1),Vector2(r.size.x-t*2-2,(r.size.y-t*2)*.42)),cut*.5),Color(.35,.6,.85,.05*alpha))
	if active:
		box_glow(node,r,Color(.1,.75,1,.32*alpha),10,6)
	gold_frame(node,r,t,cut,alpha)
	if active:
		outline(node,r.grow(-t-.6),Color(BLUE,.95*alpha),1.6,cut)
		outline(node,r.grow(1.5),Color(BLUE,.45*alpha),1.4,cut+1)
	glint(node,r,alpha)
	if ornament and minf(r.size.x,r.size.y) >= 26:
		var s = clampf(minf(r.size.x,r.size.y)*.07,2.6,5.5)
		for c in [[r.position,Vector2(1,1)],[Vector2(r.end.x,r.position.y),Vector2(-1,1)],[r.end,Vector2(-1,-1)],[Vector2(r.position.x,r.end.y),Vector2(1,-1)]]:
			corner_ornament(node,c[0]+c[1]*1.5,c[1],s,BLUE if active else PALE,alpha)
static func diamond(node: CanvasItem, center: Vector2, radius: float, color: Color):
	node.draw_colored_polygon(PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius*.7,0),center+Vector2(0,radius),center+Vector2(-radius*.7,0)]),color)
static func fit_size(value: String, width: float, font_size: int, font: Font = SANS) -> int:
	var fs = font_size
	while font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > width-4 and fs > 9: fs -= 1
	return fs
static func text(node: CanvasItem, value: String, r: Rect2, font_size: int = 18, color: Color = WHITE, font: Font = SANS, align: int = HORIZONTAL_ALIGNMENT_CENTER, glow: float = 0.0):
	var fs = fit_size(value,r.size.x,font_size,font)
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var x = r.position.x+(r.size.x-width)*.5
	if align == HORIZONTAL_ALIGNMENT_LEFT: x = r.position.x+3
	if align == HORIZONTAL_ALIGNMENT_RIGHT: x = r.end.x-width-3
	var y = r.position.y+(r.size.y-font.get_height(fs))*.5+font.get_ascent(fs)
	if glow > 0:
		halo_rect(node,Rect2(x-fs*.6,r.get_center().y-fs*.9,width+fs*1.2,fs*1.8),Color(color,.22*glow))
		node.draw_string_outline(font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,maxi(4,int(fs*.32)),Color(color,.10*glow))
	node.draw_string_outline(font,Vector2(x,y+1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,maxi(2,int(fs*.14)),Color(0,0,0,.75*color.a))
	node.draw_string(font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
	return width
static func text_width(value: String, font_size: int, font: Font = SANS) -> float:
	return font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
static func line_glow(node: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float):
	if a.distance_squared_to(b) < .01: return
	var alpha = color.a
	for i in [7.0,4.5,2.8,1.8]: node.draw_line(a,b,Color(color,alpha*(.05 if i > 5 else (.09 if i > 3 else .2))),width*i,true)
	node.draw_line(a,b,Color(color.lightened(.15),alpha),width,true)
	node.draw_line(a,b,Color(.92,1,1,alpha) if color.b > .8 else Color(1,.98,.85,alpha),maxf(.8,width*.38),true)
	for p in [a,b]: halo(node,p,width*2.2,Color(color,.5*alpha))

# ---------------------------------------------------------------- marks
static func _tri(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, d: Vector2, ca: Color, cb: Color, cd: Color):
	v.append(a); v.append(b); v.append(d); c.append(ca); c.append(cb); c.append(cd)
static func _quad(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, d: Vector2, e: Vector2, ca: Color, cb: Color, cd: Color, ce: Color):
	_tri(v,c,a,b,d,ca,cb,cd); _tri(v,c,a,d,e,ca,cd,ce)
static func _mesh(v: PackedVector2Array, c: PackedColorArray) -> ArrayMesh:
	var arrays = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v; arrays[Mesh.ARRAY_COLOR] = c
	var m = ArrayMesh.new(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return m
## Unit X (arms reach ±0.7, stroke 0.42): faceted crystal bars with chamfered tips,
## dark bevel rim, lit upper-left facets, darker lower-right facets and a white core.
static func x_mesh() -> ArrayMesh:
	if _x_mesh: return _x_mesh
	var v = PackedVector2Array(); var c = PackedColorArray()
	var rim = Color(.01,.1,.26); var dark = Color(.04,.36,.74); var lit = Color(.5,.9,1); var ridge = Color(.78,.98,1)
	var arms = [[Vector2(-.7,-.7),Vector2(.7,.7)],[Vector2(-.7,.7),Vector2(.7,-.7)]]
	var hw = .21; var tip = .2
	for pass_index in range(3):
		for arm in arms:
			var a: Vector2 = arm[0]; var b: Vector2 = arm[1]
			var u = (b-a).normalized(); var n = u.orthogonal()
			if pass_index == 0:
				var e = .055
				var ea = a-u*e; var eb = b+u*e
				var poly = [ea,ea+u*tip+n*(hw+e),eb-u*tip+n*(hw+e),eb,eb-u*tip-n*(hw+e),ea+u*tip-n*(hw+e)]
				for i in range(1,5): _tri(v,c,poly[0],poly[i],poly[i+1],rim,rim,rim)
			elif pass_index == 1:
				for side in [1.0,-1.0]:
					var bright = (n*side).dot(LIGHT.normalized())
					var face = dark.lerp(lit,clampf(.5+bright*.62,0,1))
					var edge = face.darkened(.12)
					var p1 = a+u*tip+n*hw*side; var p2 = b-u*tip+n*hw*side
					_tri(v,c,a,p1,p2,ridge.lerp(face,.35),edge,edge)
					_tri(v,c,a,p2,b,ridge.lerp(face,.35),edge,ridge.lerp(face,.35))
			else:
				var off = n*(.035 if n.dot(LIGHT) > 0 else -.035)
				var q0 = a+u*tip*1.2+off; var q1 = b-u*tip*1.2+off
				var w = n*.03
				var core = Color(.96,1,1,1); var fade = Color(.85,1,1,.15)
				_quad(v,c,q0+w,q1+w,q1-w,q0-w,fade,core,core,fade)
	_x_mesh = _mesh(v,c)
	return _x_mesh
## Unit O ring (outer .82, inner .44): outer bevel lit top-left, inner wall lit bottom-right.
static func o_mesh() -> ArrayMesh:
	if _o_mesh: return _o_mesh
	var v = PackedVector2Array(); var c = PackedColorArray()
	var r_out = .82; var r_mid = .63; var r_in = .44; var seg = 64
	var rim = Color(.17,.08,.01)
	var l = LIGHT.normalized()
	for i in range(seg):
		var a0 = TAU*i/seg; var a1 = TAU*(i+1)/seg
		var d0 = Vector2.from_angle(a0); var d1 = Vector2.from_angle(a1)
		_quad(v,c,d0*(r_out+.05),d1*(r_out+.05),d1*(r_in-.05),d0*(r_in-.05),rim,rim,rim,rim)
	for i in range(seg):
		var a0 = TAU*i/seg; var a1 = TAU*(i+1)/seg
		var d0 = Vector2.from_angle(a0); var d1 = Vector2.from_angle(a1)
		var bo0 = d0.dot(l); var bo1 = d1.dot(l)
		var ridge0 = gold_ramp(.66+maxf(bo0,-bo0)*.18); var ridge1 = gold_ramp(.66+maxf(bo1,-bo1)*.18)
		_quad(v,c,d0*r_mid,d1*r_mid,d1*r_out,d0*r_out,ridge0,ridge1,gold_ramp(.42+bo1*.42),gold_ramp(.42+bo0*.42))
		_quad(v,c,d0*r_in,d1*r_in,d1*r_mid,d0*r_mid,gold_ramp(.36-bo0*.36),gold_ramp(.36-bo1*.36),ridge1,ridge0)
	for i in range(seg):
		var a0 = TAU*i/seg; var a1 = TAU*(i+1)/seg
		var d0 = Vector2.from_angle(a0); var d1 = Vector2.from_angle(a1)
		var k0 = clampf(.15+d0.dot(l)*.85,0,1); var k1 = clampf(.15+d1.dot(l)*.85,0,1)
		var w0 = Color(1,.98,.86,k0); var w1 = Color(1,.98,.86,k1)
		_quad(v,c,d0*(r_mid-.025),d1*(r_mid-.025),d1*(r_mid+.035),d0*(r_mid+.035),w0,w1,w1,w0)
	_o_mesh = _mesh(v,c)
	return _o_mesh
static func mark_color(player: int) -> Color:
	return BLUE if player == 1 else (Color("ffc95a") if player == 2 else MUTED)
## Bevelled neon mark. radius ~ 0.35 of a cell gives a stroke ~15% of the cell.
static func mark(node: CanvasItem, center: Vector2, radius: float, player: int, alpha: float = 1, power: float = 1):
	if player != 1 and player != 2: return
	var col = mark_color(player)
	if radius > 5:
		halo(node,center,radius*2.3,Color(col,.26*alpha*power))
		halo(node,center,radius*1.25,Color(col.lightened(.25),.3*alpha*minf(power,1.6)))
	var mesh = x_mesh() if player == 1 else o_mesh()
	var sc = Vector2.ONE*radius
	node.draw_mesh(mesh,null,Transform2D(0,sc,0,center+Vector2(.5,1.4)*maxf(1,radius*.07)),Color(0,0,0,.55*alpha))
	node.draw_mesh(mesh,null,Transform2D(0,sc,0,center),Color(1,1,1,alpha))
	if power > 1.2 and radius > 8:
		diamond(node,center+Vector2(-.45,-.52)*radius,radius*.08,Color(1,1,1,.8*alpha))
static func crown(node: CanvasItem, pos: Vector2, scale_value: float = 1):
	var points = PackedVector2Array([Vector2(-14,5),Vector2(-17,-8),Vector2(-7,-1),Vector2(0,-15),Vector2(7,-1),Vector2(17,-8),Vector2(14,5)])
	for i in points.size(): points[i] = pos+points[i]*scale_value
	halo(node,pos-Vector2(0,4)*scale_value,24*scale_value,Color(1,.8,.3,.3))
	var cols = PackedColorArray()
	for p in points: cols.append(gold_ramp(.9-(p.y-pos.y+15*scale_value)/(20*scale_value)*.55))
	node.draw_polygon(points,cols)
	node.draw_polyline(points+PackedVector2Array([points[0]]),GOLD_DARK,1,true)
	node.draw_line(pos+Vector2(-13,6)*scale_value,pos+Vector2(13,6)*scale_value,PALE,2*scale_value,true)
	for x in [-17,0,17]: diamond(node,pos+Vector2(x,-8 if x != 0 else -15)*scale_value,2.8*scale_value,PALE)
	diamond(node,pos+Vector2(0,1)*scale_value,2.6*scale_value,BLUE)
static func crystal(node: CanvasItem, pos: Vector2, scale_value: float, color: Color, rotation: float = 0):
	var local = [Vector2(0,-1),Vector2(.28,-.38),Vector2(.22,.64),Vector2(0,1),Vector2(-.23,.6),Vector2(-.28,-.38)]
	var p = PackedVector2Array()
	for v in local: p.append(pos+v.rotated(rotation)*scale_value)
	node.draw_colored_polygon(p,color.darkened(.48))
	node.draw_colored_polygon(PackedVector2Array([p[0],p[1],pos,p[5]]),color.lightened(.25))
	node.draw_colored_polygon(PackedVector2Array([p[1],p[2],p[3],pos]),color.darkened(.16))
	node.draw_polyline(PackedVector2Array([p[0],pos,p[3],p[4],p[5],p[0],p[1],p[2],p[3]]),color.lightened(.4),1,true)
## Crystal shard for particles: cheap 4-point faceted sliver.
static func shard(node: CanvasItem, pos: Vector2, length: float, angle: float, color: Color):
	if length < .4 or color.a <= .01: return
	var d = Vector2.from_angle(angle)*length; var n = d.orthogonal()*.28
	node.draw_colored_polygon(PackedVector2Array([pos-d,pos+n,pos+d,pos-n]),color)
	node.draw_line(pos-d*.7,pos+d*.7,Color(1,1,1,color.a*.8),maxf(.5,length*.12),true)
## Title ornament: crystal crown with gold crescent wings and a jewel, as in the reference logo.
static func title_crown(node: CanvasItem, pos: Vector2, s: float):
	halo(node,pos+Vector2(0,s*.1),s*2.6,Color(.3,.75,1,.32))
	halo(node,pos+Vector2(0,s*.6),s*1.6,Color(1,.85,.5,.22))
	for side in [-1.0,1.0]:
		var pts = PackedVector2Array(); var cols = PackedColorArray()
		for i in range(13):
			var t = i/12.0
			var ang = lerpf(PI*.98,PI*.56,t)
			var outer = pos+Vector2(cos(ang)*-side*1.55*s,sin(ang)*-1.0*s*1.3)+Vector2(0,s*.95)
			pts.append(outer); cols.append(gold_ramp(.55+t*.4))
		for i in range(12,-1,-1):
			var t = i/12.0
			var ang = lerpf(PI*.98,PI*.56,t)
			var inner = pos+Vector2(cos(ang)*-side*1.33*s,sin(ang)*-1.0*s*1.05)+Vector2(0,s*.95)
			pts.append(inner); cols.append(gold_ramp(.3+t*.3))
		node.draw_polygon(pts,cols)
	crystal(node,pos+Vector2(-s*.55,s*.12),s*.55,Color(.25,.7,1),-.32)
	crystal(node,pos+Vector2(s*.55,s*.12),s*.55,Color(.25,.7,1),.32)
	crystal(node,pos+Vector2(-s*.28,-s*.05),s*.72,Color(.3,.8,1),-.14)
	crystal(node,pos+Vector2(s*.28,-s*.05),s*.72,Color(.3,.8,1),.14)
	crystal(node,pos+Vector2(0,-s*.25),s*1.05,Color(.42,.88,1),0)
	# Gold setting band, jewel and the line that carries down to the title.
	var band = PackedVector2Array([pos+Vector2(-s*.9,s*.62),pos+Vector2(s*.9,s*.62),pos+Vector2(s*.62,s*.86),pos+Vector2(-s*.62,s*.86)])
	node.draw_polygon(band,PackedColorArray([gold_ramp(.9),gold_ramp(.9),gold_ramp(.35),gold_ramp(.35)]))
	diamond(node,pos+Vector2(0,s*.72),s*.26,Color(GOLD_DARK))
	diamond(node,pos+Vector2(0,s*.72),s*.2,BLUE.lightened(.2))
	halo(node,pos+Vector2(0,s*.72),s*.6,Color(.5,.9,1,.6))
## Procedural icons for buttons (fonts lack reliable symbol glyphs).
static func icon(node: CanvasItem, kind: String, center: Vector2, s: float, color: Color = PALE):
	match kind:
		"gear":
			for i in range(8):
				var a = i*TAU/8
				node.draw_line(center+Vector2.from_angle(a)*s*.55,center+Vector2.from_angle(a)*s*.9,GOLD,s*.3,true)
			node.draw_arc(center,s*.55,0,TAU,32,color,s*.2,true)
			node.draw_arc(center,s*.2,0,TAU,24,GOLD,s*.1,true)
		"home":
			var roof = PackedVector2Array([center+Vector2(-s*.85,-s*.05),center+Vector2(0,-s*.85),center+Vector2(s*.85,-s*.05)])
			node.draw_polyline(roof,color,s*.16,true)
			node.draw_polyline(PackedVector2Array([center+Vector2(-s*.55,-s*.2),center+Vector2(-s*.55,s*.75),center+Vector2(s*.55,s*.75),center+Vector2(s*.55,-s*.2)]),color,s*.14,true)
			node.draw_rect(Rect2(center+Vector2(-s*.16,s*.25),Vector2(s*.32,s*.5)),GOLD)
		"back":
			node.draw_polyline(PackedVector2Array([center+Vector2(s*.3,-s*.62),center+Vector2(-s*.3,0),center+Vector2(s*.3,s*.62)]),color,s*.2,true)
		"undo":
			node.draw_arc(center+Vector2(s*.1,s*.1),s*.55,-PI*.95,PI*.6,24,color,s*.17,true)
			node.draw_colored_polygon(PackedVector2Array([center+Vector2(-s*.75,-s*.2),center+Vector2(-s*.25,-s*.55),center+Vector2(-s*.2,s*.12)]),color)
		"hint":
			node.draw_arc(center-Vector2(0,s*.2),s*.48,PI*.75,PI*2.25,24,color,s*.14,true)
			node.draw_line(center+Vector2(-s*.22,s*.42),center+Vector2(s*.22,s*.42),color,s*.14,true)
			node.draw_line(center+Vector2(-s*.16,s*.64),center+Vector2(s*.16,s*.64),color,s*.12,true)
			for i in range(5):
				var a = -PI*.5+(i-2)*.55
				node.draw_line(center-Vector2(0,s*.2)+Vector2.from_angle(a)*s*.66,center-Vector2(0,s*.2)+Vector2.from_angle(a)*s*.86,Color(color,.7),s*.08,true)
		"info":
			node.draw_arc(center,s*.8,0,TAU,32,color,s*.1,true)
			node.draw_circle(center+Vector2(0,-s*.38),s*.11,color)
			node.draw_line(center+Vector2(0,-s*.1),center+Vector2(0,s*.45),color,s*.16,true)
