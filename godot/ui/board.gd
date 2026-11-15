extends Control
## Live 81-cell board. Round 2 splits drawing into:
##  - the board itself: static base (frames, tiles, grid, marks, claimed emblems), only
##    redrawn when state/hover/animation changes;
##  - Under (additive, behind the base): soft glows that bleed out around tiles;
##  - Over (additive, in front): pulsing active border, glints, beams, flashes, shockwaves;
##  - Top (normal blend, in front): crystal shards / gold sparks and the scaling emblem.
## Every effect is a pure function of its age, so debug poses show particles, flashes and
## rays exactly as a live frame would.
signal cell_pressed(board: int, cell: int)
const P = preload("res://ui/paint.gd")
const Rules = preload("res://kernel/rules.gd")
const CLAIM_TIME = 1.6
const WIN_TIME = 3.5
const CLAIM_PARTICLES = 96
const CLAIM_PARTICLES_REDUCED = 14

class Layer extends Control:
	var painter: Callable
	func _draw():
		if painter.is_valid(): painter.call(self)

var game
var clock: float = 0
var reduced_motion: bool = false
var hint_move = Vector2i(-1,-1)
var claims: Array = []
var win_fx: Dictionary = {}
var mark_ages: Dictionary = {}
var invalid_board: int = -1
var invalid_age: float = 1
var active_age: float = 1
var frozen: bool = false
var hover_move = Vector2i(-1,-1)
var rest_position: Vector2 = Vector2.ZERO
var under: Layer
var over: Layer
var top: Layer
var _last_touch_ms: int = -1000
var _signature: String = ""
var _dirty: bool = true

func _ready():
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func(): hover_move = Vector2i(-1,-1))
	under = _layer("Under",_draw_under,true,true)
	over = _layer("Over",_draw_over,false,true)
	top = _layer("Top",_draw_top,false,false)
func _layer(id: String, painter: Callable, behind: bool, additive: bool) -> Layer:
	var l = Layer.new(); l.name = id; l.painter = painter
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; l.show_behind_parent = behind
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if additive:
		var m = CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; l.material = m
	add_child(l)
	return l
## Layout entry point; keeps the rest position for camera punch/shake.
func place(rect: Rect2):
	rest_position = rect.position; position = rect.position; size = rect.size
	pivot_offset = size*.5; _dirty = true; _apply_camera()
func _process(delta): advance(delta)
func advance(delta: float):
	if not frozen:
		clock += delta
		invalid_age += delta; active_age += delta
		for key in mark_ages: mark_ages[key] += delta
		for fx in claims: fx.age += delta
		claims = claims.filter(func(fx): return fx.age < claim_duration())
		if not win_fx.is_empty(): win_fx.age = minf(win_fx.age+delta,win_duration())
	refresh()
## Redraw what changed. Over/Top are cheap and animate every frame; the base only on change.
func refresh():
	_apply_camera()
	if game != null:
		var sig = "%d|%d|%d|%d|%d|%s|%s|%s|%d" % [game.history.size(),game.status,game.active_board,game.turn,game.cells.count(1)*100+game.cells.count(2),hover_move,hint_move,size,int(reduced_motion)]
		if sig != _signature: _signature = sig; _dirty = true
	if _dirty or animating(): queue_redraw(); _dirty = false
	if under: under.queue_redraw()
	if over: over.queue_redraw()
	if top: top.queue_redraw()
func animating() -> bool:
	if not claims.is_empty() or invalid_age < .4 or frozen: return true
	if not win_fx.is_empty() and win_fx.age < win_duration(): return true
	if hint_move.x >= 0: return true
	for key in mark_ages:
		if mark_ages[key] < .45: return true
	return false
func claim_duration() -> float: return .45 if reduced_motion else CLAIM_TIME
func win_duration() -> float: return 1.2 if reduced_motion else WIN_TIME
func start_claim(board: int, player: int): claims.append({"board":board,"player":player,"age":0.0}); _dirty = true
func start_win(line: Array, player: int): win_fx = {"line":line.duplicate(),"player":player,"age":0.0}; _dirty = true
func win_progress() -> float: return clampf(float(win_fx.get("age",0))/win_duration(),0,1)
func notify_move(board: int, cell: int):
	mark_ages[board*9+cell] = 0.0; hint_move = Vector2i(-1,-1); active_age = 0; _dirty = true
func clear_effects():
	claims.clear(); win_fx = {}; mark_ages.clear(); frozen = false; _dirty = true
	scale = Vector2.ONE; position = rest_position
func preview_claim(board: int, player: int, progress: float):
	win_fx = {}
	claims = [{"board":board,"player":player,"age":clampf(progress,0,1)*claim_duration()}]; frozen = true; _dirty = true; refresh()
func preview_win(line: Array, player: int, progress: float):
	claims = []
	win_fx = {"line":line.duplicate(),"player":player,"age":clampf(progress,0,1)*win_duration()}; frozen = true; _dirty = true; refresh()
func tile_rect(board: int) -> Rect2:
	var pad = size.x*.022; var gap = size.x*.018
	var edge = (size.x-pad*2-gap*2)/3
	return Rect2(Vector2(pad+(board%3)*(edge+gap),pad+(board/3)*(edge+gap)),Vector2(edge,edge))
func cell_center(board: int, cell: int) -> Vector2:
	var r = tile_rect(board).grow(-size.x*.018)
	return r.position+Vector2((cell%3+.5)*r.size.x/3,(cell/3+.5)*r.size.y/3)
func move_at(pos: Vector2) -> Vector2i:
	for b in range(9):
		var r = tile_rect(b)
		if r.has_point(pos):
			var inner = r.grow(-size.x*.018)
			var local = (pos-inner.position)/inner.size*3
			var c = clampi(int(local.x),0,2)+clampi(int(local.y),0,2)*3
			return Vector2i(b,c)
	return Vector2i(-1,-1)
func _gui_input(event):
	if event is InputEventScreenTouch: _last_touch_ms = Time.get_ticks_msec()
	if event is InputEventMouseButton and event.device == -1 and Time.get_ticks_msec()-_last_touch_ms < 150: return
	if event is InputEventMouseMotion: hover_move = move_at(event.position)
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		var m = move_at(event.position)
		if m.x >= 0: cell_pressed.emit(m.x,m.y); accept_event()

# ------------------------------------------------------------ timing helpers
static func ease_out(t: float) -> float: t = clampf(t,0,1); return 1.0-pow(1.0-t,3)
static func back_out(t: float) -> float:
	t = clampf(t,0,1); var c1 = 2.2; var c3 = c1+1
	return 1+c3*pow(t-1,3)+c1*pow(t-1,2)
static func window(p: float, a: float, b: float) -> float: return clampf((p-a)/(b-a),0,1)
static func rnd(i: int, k: int) -> float: return fposmod(sin(i*12.9898+k*78.233)*43758.5453,1.0)
func player_color(player: int) -> Color: return P.mark_color(player)
func claim_phase(fx: Dictionary) -> float: return clampf(fx.age/claim_duration(),0,1)
## Camera punch-in around the claimed board / winning line, plus a decaying shake.
func _apply_camera():
	var z = 1.0; var pivot = size*.5; var shake = Vector2.ZERO
	if not reduced_motion:
		for fx in claims:
			var p = claim_phase(fx)
			var env = window(p,0,.08)*(1-ease_out(window(p,.1,.62)))
			if env*.055 > z-1: z = 1+env*.055; pivot = tile_rect(fx.board).get_center()
			if p < .42: shake += Vector2(sin(p*150+fx.board),cos(p*123))*4.5*(1-p/.42)
		if not win_fx.is_empty():
			var p = win_progress()
			var env = window(p,0,.06)*(1-ease_out(window(p,.1,.5)))
			z = maxf(z,1+env*.065+sin(window(p,.3,.75)*PI*3)*.008)
			if win_fx.line.size() >= 3: pivot = tile_rect(win_fx.line[1]).get_center()
			if p < .32: shake += Vector2(sin(p*190),cos(p*161))*7*(1-p/.32)
	pivot_offset = pivot; scale = Vector2.ONE*z; position = rest_position+shake
## Screen-wide tint the controller paints above the board (claims and the game win).
func screen_flash() -> Color:
	var best = Color(0,0,0,0)
	var k = .45 if reduced_motion else 1.0
	for fx in claims:
		if fx.player == 3: continue
		var p = claim_phase(fx)
		var a = window(p,.02,.08)*(1-window(p,.08,.65))*.22*k
		if a > best.a: best = Color(player_color(fx.player).lerp(Color.WHITE,.35),a)
	if not win_fx.is_empty():
		var p = win_progress()
		# White-hot burst, then a lingering colour wash.
		var a = (window(p,0,.015)*(1-window(p,.02,.2)))*.82*k+(1-window(p,.2,.7))*window(p,0,.05)*.09*k
		if a > best.a: best = Color(Color.WHITE.lerp(player_color(win_fx.player),window(p,.0,.09)),a)
	return best

# ------------------------------------------------------------ static base
func _draw():
	if game == null: return
	var whole = Rect2(Vector2.ZERO,size)
	# Heavy outer frame around the whole 3x3.
	draw_colored_polygon(P.polygon(whole.grow(2),16),Color(0,0,0,.6))
	draw_colored_polygon(P.polygon(whole,14),Color(.012,.03,.07,.97))
	P.gold_frame(self,whole.grow(-1),clampf(size.x*.012,3.5,9),14)
	for b in range(9): _draw_tile(b)
	var s = clampf(size.x*.016,4,11)
	for c in [[Vector2.ZERO,Vector2(1,1)],[Vector2(size.x,0),Vector2(-1,1)],[size,Vector2(-1,-1)],[Vector2(0,size.y),Vector2(1,-1)]]:
		P.corner_ornament(self,c[0]+c[1]*s*.35,c[1],s,P.BLUE)
	# Mid-edge jewels, as on the reference board frame.
	for m in [Vector2(size.x*.5,1),Vector2(size.x*.5,size.y-1),Vector2(1,size.y*.5),Vector2(size.x-1,size.y*.5)]:
		P.diamond(self,m,s*.7,P.gold_ramp(.7)); P.diamond(self,m,s*.32,P.BLUE)
func is_active(b: int) -> bool:
	return game.status == 0 and game.owners[b] == 0 and (game.active_board == b or game.active_board == -1)
func _tile_body(r: Rect2, center_color: Color, edge_color: Color):
	var poly = P.polygon(r,8)
	var c = r.get_center()+Vector2(0,-r.size.y*.08)
	for i in range(8):
		var j = (i+1)%8
		draw_polygon(PackedVector2Array([c,poly[i],poly[j]]),PackedColorArray([center_color,edge_color,edge_color]))
func _draw_tile(b: int):
	var r = tile_rect(b)
	if invalid_board == b and invalid_age < .35 and not reduced_motion: r.position.x += sin(invalid_age*80)*(1-invalid_age/.35)*5
	var active = is_active(b)
	var owner: int = game.owners[b]
	var t = clampf(r.size.x*.035,2.6,6)
	draw_colored_polygon(P.polygon(r.grow(2),9),Color(0,0,0,.55))
	var inner_body = r.grow(-t*.6)
	if P.board_theme == "sandstone":
		_tile_body(inner_body,Color("84765e") if active else Color("514b40"),Color("252c32"))
		for vein in range(3):
			var a = inner_body.position+Vector2(inner_body.size.x*(.12+vein*.27),4)
			var z = a+Vector2(inner_body.size.x*.22,inner_body.size.y-8)
			draw_polyline(PackedVector2Array([a,a.lerp(z,.4)+Vector2(6,-4),a.lerp(z,.65)-Vector2(4,2),z]),Color(.9,.82,.65,.09),1,true)
	elif active: _tile_body(inner_body,Color("175a78"),Color("08263a"))
	else: _tile_body(inner_body,Color("142b4f"),Color("050d1d"))
	# Inset shadow under the top frame edge and a faint diagonal sheen.
	var ih = r.size.y*.13
	draw_polygon(PackedVector2Array([inner_body.position,Vector2(inner_body.end.x,inner_body.position.y),Vector2(inner_body.end.x,inner_body.position.y+ih),Vector2(inner_body.position.x,inner_body.position.y+ih)]),PackedColorArray([Color(0,0,0,.5),Color(0,0,0,.5),Color(0,0,0,0),Color(0,0,0,0)]))
	var ip = inner_body.position; var isz = inner_body.size
	draw_colored_polygon(PackedVector2Array([ip+Vector2(isz.x*.18,0),ip+Vector2(isz.x*.34,0),ip+Vector2(0,isz.y*.34),ip+Vector2(0,isz.y*.18)]),Color(.6,.8,1,.03))
	draw_colored_polygon(PackedVector2Array([ip+Vector2(isz.x*.62,isz.y),ip+Vector2(isz.x,isz.y*.62),ip+Vector2(isz.x,isz.y*.7),ip+Vector2(isz.x*.7,isz.y)]),Color(.6,.8,1,.025))
	var inner = r.grow(-size.x*.018)
	var gw = maxf(1.0,size.x/560)
	for i in [1,2]:
		var x = inner.position.x+inner.size.x*i/3
		var y = inner.position.y+inner.size.y*i/3
		draw_line(Vector2(x+1,inner.position.y),Vector2(x+1,inner.end.y),Color(0,0,0,.45),gw,true)
		draw_line(Vector2(inner.position.x,y+1),Vector2(inner.end.x,y+1),Color(0,0,0,.45),gw,true)
		draw_line(Vector2(x,inner.position.y),Vector2(x,inner.end.y),Color(.45,.58,.74,.34 if not active else .5),gw,true)
		draw_line(Vector2(inner.position.x,y),Vector2(inner.end.x,y),Color(.45,.58,.74,.34 if not active else .5),gw,true)
	P.gold_frame(self,r,t,9)
	if active:
		P.outline(self,r.grow(-t-.5),Color(.35,.95,1,.9),maxf(1.5,t*.45),8)
	var reveal = 1.0
	var claiming = false
	for fx in claims:
		if fx.board == b: reveal = back_out(window(claim_phase(fx),.4,.68)); claiming = true
	var mark_alpha = 1.0
	if owner in [1,2]: mark_alpha = lerpf(1.0,.3,reveal if claiming else 1.0)
	for c in range(9):
		var mark: int = game.cells[b*9+c]
		if mark == 0:
			if hover_move == Vector2i(b,c) and game.is_legal(b,c):
				P.mark(self,cell_center(b,c),inner.size.x*.115,game.turn,.28)
			continue
		var age: float = mark_ages.get(b*9+c,1.0)
		var pop = 1.0
		if age < .32 and not reduced_motion: pop = 1+sin(age/.32*PI)*.28
		P.mark(self,cell_center(b,c),inner.size.x*.115*pop,mark,mark_alpha,1.6 if age < .3 else 1.0)
	if owner != 0:
		var col = player_color(owner)
		var k = reveal if claiming else 1.0
		draw_colored_polygon(P.polygon(r.grow(-t),8),Color(col.darkened(.55),.42*k) if owner != 3 else Color(.05,.08,.12,.55))
		if owner == 3:
			P.crystal(self,r.get_center(),r.size.x*.28,Color(.5,.62,.72,.6))
			P.text(self,"SEALED",Rect2(r.position+Vector2(0,r.size.y*.72),Vector2(r.size.x,r.size.y*.16)),maxi(9,int(r.size.x*.11)),P.MUTED,P.SERIF)
		else:
			P.outline(self,r.grow(-t*.5),Color(col,.9*k),maxf(2,t*.7),9)
			if k > .01:
				# The giant emblem: ~90% of the board, same bevelled style, big halo.
				P.halo(self,r.get_center(),r.size.x*.75*k,Color(col,.28*minf(k,1)))
				P.mark(self,r.get_center(),r.size.x*.62*k,owner,1.0,1.8,true)
	if hint_move.x == b and hint_move.y >= 0:
		var center = cell_center(b,hint_move.y)
		var pulse = .75+.25*sin(clock*5)
		draw_arc(center,inner.size.x*.15,0,TAU,32,Color(1,.92,.53,pulse),2,true)
		for i in range(4): P.diamond(self,center+Vector2.from_angle(clock*.5+i*PI/2)*inner.size.x*.17,2.2,Color(1,.94,.6,pulse))
	if game.status in [1,2] and not win_fx.is_empty() and b in win_fx.line:
		P.outline(self,r.grow(-1),Color(player_color(game.status).lightened(.3),.9),2.5,9)
	if r.size.x > 60:
		var s = clampf(r.size.x*.035,2.6,5)
		for c in [[r.position,Vector2(1,1)],[Vector2(r.end.x,r.position.y),Vector2(-1,1)],[r.end,Vector2(-1,-1)],[Vector2(r.position.x,r.end.y),Vector2(1,-1)]]:
			P.corner_ornament(self,c[0]+c[1]*s*.5,c[1],s,P.BLUE if active else P.PALE)

# ------------------------------------------------------------ additive glows (behind)
func _draw_under(n: Control):
	# Only light that spills outside the whole board belongs behind the opaque base.
	if game == null: return
	if not win_fx.is_empty():
		var p = win_progress(); var col = player_color(win_fx.player)
		var beat = .5+.5*sin(clock*5.5)
		P.box_glow(n,Rect2(Vector2.ZERO,size),Color(col,(.3+.3*beat)*minf(1,p*6)),int(size.x*.09),18)
	for fx in claims:
		if fx.player == 3: continue
		P.box_glow(n,Rect2(Vector2.ZERO,size),Color(player_color(fx.player),sin(window(claim_phase(fx),0,.6)*PI)*.35),int(size.x*.05),18)

# ------------------------------------------------------------ additive light (front)
func _draw_over(n: Control):
	if game == null: return
	var pulse = .5+.5*sin(clock*TAU/1.2)
	for b in range(9):
		if is_active(b):
			var r = tile_rect(b)
			var boost = maxf(0,1-active_age*1.6)
			# Wide outer bloom + tight hot rim + inner rim light, pulsing every 1.2 s.
			P.edge_glow(n,r,Color(.05,.6,1,.32+.26*pulse+boost*.3),r.size.x*(.13+.05*pulse),9)
			P.edge_glow(n,r,Color(.25,.9,1,.45+.3*pulse),r.size.x*.04,9)
			P.edge_glow(n,r,Color(.2,.85,1,.22+.14*pulse),-r.size.x*.09,9)
			for k in range(3,0,-1): P.outline(n,r.grow(k*1.5),Color(.1,.75,1,(.05+.05*pulse)/k*2.2),k*2.4,10)
			P.outline(n,r,Color(.3,.95,1,.55+.4*pulse),2.6,9)
			# A bright spark travels around the active frame.
			var t = fposmod(clock*.35+b*.11,1.0)
			var per = (r.size.x+r.size.y)*2; var d = t*per
			var pt = r.position+(Vector2(d,0) if d < r.size.x else (Vector2(r.size.x,d-r.size.x) if d < r.size.x+r.size.y else (Vector2(r.size.x-(d-r.size.x-r.size.y),r.size.y) if d < r.size.x*2+r.size.y else Vector2(0,r.size.y-(d-r.size.x*2-r.size.y)))))
			P.halo(n,pt,r.size.x*.12,Color(.4,.95,1,.75))
		elif game.owners[b] in [1,2]:
			P.edge_glow(n,tile_rect(b),Color(player_color(game.owners[b]),.22),tile_rect(b).size.x*.06,9)
	# Gold shimmer sweeps along frames.
	P.glint(n,Rect2(Vector2.ZERO,size),.9,6.5)
	P.glint(n,Rect2(Vector2(0,size.y-1.5),Vector2(size.x,2)),.6,7.5)
	for b in range(9): P.glint(n,tile_rect(b),.55,5+b*.37)
	for fx in claims: _claim_light(n,fx)
	if not win_fx.is_empty(): _win_light(n,win_progress())
func _claim_light(n: Control, fx: Dictionary):
	var r = tile_rect(fx.board); var p = claim_phase(fx)
	var col = player_color(fx.player); var center = r.get_center()
	if fx.player != 3: P.edge_glow(n,r,Color(col,sin(window(p,0,.7)*PI)*.8),r.size.x*.3,9)
	if fx.player == 3:
		n.draw_arc(center,r.size.x*(.1+p*.5),0,TAU,48,Color(P.MUTED,(1-p)*.5),2,true)
		return
	# Full board flash, white into the player colour.
	var f = window(p,.03,.1)*(1-window(p,.1,.7))
	if f > 0: n.draw_colored_polygon(P.polygon(r.grow(-2),8),Color(Color.WHITE.lerp(col,window(p,.08,.3)),f*.6))
	# Light rays bursting from the claimed board, slowly turning.
	var ray_a = window(p,.04,.14)*(1-window(p,.25,.88))
	if ray_a > 0:
		var count = 6 if reduced_motion else 14
		for i in range(count):
			var ang = i*TAU/count+p*1.2+fx.board
			var reach = r.size.x*(1.1+.5*rnd(i,fx.board+2))*(.6+.4*ease_out(window(p,.04,.4)))
			var wdt = .07+.05*rnd(i,fx.board+4)
			n.draw_polygon(PackedVector2Array([center,center+Vector2.from_angle(ang-wdt)*reach,center+Vector2.from_angle(ang+wdt)*reach]),PackedColorArray([Color(col.lightened(.4),ray_a*.55),Color(col,0),Color(col,0)]))
	# Beam drawn through the three winning cells, overshooting slightly.
	var lines: Array = game.small_lines[fx.board]
	var beam_alpha = 1.0-window(p,.55,.85)
	for line in lines:
		var a = cell_center(fx.board,line[0]); var z = cell_center(fx.board,line[2])
		var dir = (z-a)*.22
		var start = a-dir; var stop = (z+dir)
		var tip = start.lerp(stop,ease_out(window(p,0,.2)))
		if beam_alpha > 0:
			P.line_glow(n,start,tip,Color(col,beam_alpha),maxf(3,r.size.x*.06)*(1+.25*sin(window(p,0,.2)*PI)))
			P.halo(n,tip,r.size.x*.32,Color(1,1,1,beam_alpha*.5))
	# Expanding shockwave rings past the board edges.
	for k in range(3):
		var q = window(p,.1+k*.08,.62+k*.08)
		if q <= 0 or q >= 1: continue
		var rad = r.size.x*(.12+ease_out(q)*(1.15+k*.25))
		n.draw_arc(center,rad,0,TAU,72,Color(col.lightened(.3),(1-q)*.85),maxf(1.5,r.size.x*.05*(1-q)),true)
		n.draw_arc(center,rad*.97,0,TAU,72,Color(col,(1-q)*.3),maxf(3,r.size.x*.12*(1-q)),true)
	# Emblem bloom as it lands.
	var e = window(p,.4,.75)
	if e > 0: P.halo(n,center,r.size.x*(.5+.5*e),Color(col,sin(e*PI)*.6))
	# Particle glow halos (shapes drawn in Top).
	var amount = CLAIM_PARTICLES_REDUCED if reduced_motion else CLAIM_PARTICLES
	for i in range(0,amount,3):
		var s = _particle(fx,i,r,p)
		if s.alpha > 0: P.halo(n,s.pos,s.size*3.2,Color(col,s.alpha*.45))
## Deterministic particle state: pure function of index and claim progress.
func _particle(fx: Dictionary, i: int, r: Rect2, p: float) -> Dictionary:
	var start = .1+rnd(i,fx.board)*.08
	var q = window(p,start,start+.62+rnd(i,7)*.25)
	if q <= 0 or q >= 1: return {"alpha":0.0,"pos":Vector2.ZERO,"size":0.0,"angle":0.0}
	var ang = i*2.39996+rnd(i,3)*.6
	var speed = r.size.x*(.55+rnd(i,5)*1.35)
	var pos = r.get_center()+Vector2.from_angle(ang)*speed*ease_out(q)+Vector2(0,q*q*r.size.x*.45)
	var sz = r.size.x*(.025+rnd(i,9)*.045)*(1-q*.7)
	return {"alpha":(1-q)*(1-q*.3),"pos":pos,"size":sz,"angle":ang+q*(4+rnd(i,11)*8)}
func _win_light(n: Control, p: float):
	var col = player_color(win_fx.player)
	var line: Array = win_fx.line
	if line.size() >= 3:
		var a = tile_rect(line[0]).get_center(); var z = tile_rect(line[2]).get_center()
		var ext = (z-a).normalized()*tile_rect(0).size.x*.42
		var start = a-ext; var stop = z+ext
		var tip = start.lerp(stop,ease_out(window(p,.02,.24)))
		var w = size.x*.034*(1+.18*sin(clock*9))
		P.line_glow(n,start,tip,col,w)
		P.line_glow(n,start,tip,Color(1,1,1,.5),w*.45)
		P.halo(n,tip,size.x*.22,Color(1,1,1,.6*(1-window(p,.24,.4))))
		for b in line:
			var rr = tile_rect(b)
			var beat = .5+.5*sin(clock*6+b)
			P.edge_glow(n,rr,Color(col,(.35+.25*beat)*minf(1,p*4)),rr.size.x*.12,9)
			n.draw_arc(rr.get_center(),rr.size.x*(.5+.06*beat),0,TAU,72,Color(col,.55*minf(1,p*5)),size.x*.007,true)
			P.halo(n,rr.get_center(),rr.size.x*.7,Color(col,.3*minf(1,p*5)))
	var flash = window(p,0,.03)*(1-window(p,.03,.6))
	if flash > 0: n.draw_rect(Rect2(Vector2.ZERO,size),Color(Color.WHITE.lerp(col,window(p,0,.15)),flash*.35))

# ------------------------------------------------------------ shards / sparks (front, normal blend)
func _draw_top(n: Control):
	if game == null: return
	for fx in claims:
		if fx.player == 3: continue
		var r = tile_rect(fx.board); var p = claim_phase(fx); var col = player_color(fx.player)
		var amount = CLAIM_PARTICLES_REDUCED if reduced_motion else CLAIM_PARTICLES
		for i in range(amount):
			var s = _particle(fx,i,r,p)
			if s.alpha <= 0: continue
			var tint = col.lerp(Color.WHITE,rnd(i,13)*.6); tint.a = s.alpha
			if fx.player == 1:
				P.shard(n,s.pos,s.size*1.5,s.angle,tint)
			else:
				var vel = Vector2.from_angle(i*2.39996)*s.size*2.5
				n.draw_line(s.pos-vel,s.pos,Color(tint,s.alpha*.6),maxf(1,s.size*.45),true)
				P.diamond(n,s.pos,s.size,tint)
	if not win_fx.is_empty():
		# Shards bursting from each of the three winning boards.
		var p = win_progress(); var col = player_color(win_fx.player)
		var per = 8 if reduced_motion else 34
		for b in win_fx.line:
			var r = tile_rect(b)
			var fx = {"board":b+20}
			var q = window(p,.08+win_fx.line.find(b)*.07,1.0)
			for i in range(per):
				var s = _particle(fx,i,r,.1+q*.8)
				if s.alpha <= 0: continue
				var tint = col.lerp(Color.WHITE,rnd(i,b)*.5); tint.a = s.alpha
				if win_fx.player == 1: P.shard(n,s.pos,s.size*1.8,s.angle,tint)
				else: P.diamond(n,s.pos,s.size*1.2,tint)
