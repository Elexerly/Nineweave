extends Control
signal cell_pressed(board: int, cell: int)
const P = preload("res://ui/paint.gd")
const Rules = preload("res://kernel/rules.gd")
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
var _last_touch_ms: int = -1000
var _sheen: ShaderMaterial
func _ready():
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func(): hover_move = Vector2i(-1,-1))
	var sheen = ColorRect.new(); sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheen = ShaderMaterial.new(); _sheen.shader = preload("res://assets/shaders/frame_shimmer.gdshader")
	sheen.material = _sheen; add_child(sheen)
func _process(delta): advance(delta)
func advance(delta: float):
	if _sheen: _sheen.set_shader_parameter("motion",0.0 if reduced_motion or frozen else 1.0)
	if frozen: queue_redraw(); return
	clock += delta
	invalid_age += delta; active_age += delta
	for key in mark_ages: mark_ages[key] += delta
	for fx in claims: fx.age += delta
	claims = claims.filter(func(fx): return fx.age < claim_duration())
	if not win_fx.is_empty(): win_fx.age += delta
	queue_redraw()
func claim_duration() -> float: return .45 if reduced_motion else 1.55
func win_duration() -> float: return 1.2 if reduced_motion else 3.6
func start_claim(board: int, player: int): claims.append({"board":board,"player":player,"age":0.0})
func start_win(line: Array, player: int): win_fx = {"line":line.duplicate(),"player":player,"age":0.0}
func win_progress() -> float: return clampf(float(win_fx.get("age",0))/win_duration(),0,1)
func notify_move(board: int, cell: int):
	mark_ages[board*9+cell] = 0.0; hint_move = Vector2i(-1,-1); active_age = 0
func clear_effects(): claims.clear(); win_fx = {}; mark_ages.clear(); frozen = false
func preview_claim(board: int, player: int, progress: float):
	claims = [{"board":board,"player":player,"age":clampf(progress,0,1)*claim_duration()}]; clock = progress*claim_duration(); frozen = true; queue_redraw()
func preview_win(line: Array, player: int, progress: float):
	win_fx = {"line":line.duplicate(),"player":player,"age":clampf(progress,0,1)*win_duration()}; clock = progress*win_duration(); frozen = true; queue_redraw()
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
func _draw():
	if game == null: return
	var shake = Vector2.ZERO
	var zoom = 1.0
	if not reduced_motion:
		for fx in claims:
			var phase = fx.age/claim_duration()
			if phase < .45: shake += Vector2(sin(phase*140),cos(phase*117))*3*(1-phase/.45)
		if not win_fx.is_empty(): zoom = 1.0+sin(win_progress()*PI*6)*.018*(1-win_progress())
	draw_set_transform(size*.5*(1-zoom)+shake,0,Vector2.ONE*zoom)
	var whole = Rect2(Vector2(2,2),size-Vector2(4,4))
	var win_p = win_progress()
	P.panel(self,whole,false,1,true)
	P.outline(self,whole.grow(-4),P.PALE,.8)
	for b in range(9): _draw_tile(b)
	for fx in claims: _draw_claim(fx)
	if not win_fx.is_empty(): _draw_win(win_p)
	# Cut crystal ornaments at outer frame corners.
	for pos in [Vector2(5,5),Vector2(size.x-5,5),size-Vector2(5,5),Vector2(5,size.y-5)]:
		P.diamond(self,pos,size.x*.018,P.GOLD)
		P.diamond(self,pos,size.x*.009,P.PALE)
func _draw_tile(b: int):
	var r = tile_rect(b)
	if invalid_board == b and invalid_age < .35 and not reduced_motion: r.position.x += sin(invalid_age*80)*(1-invalid_age/.35)*4
	var active: bool = game.status == 0 and game.owners[b] == 0 and (game.active_board == b or game.active_board == -1)
	var tint = Color("071323") if not active else Color("09273c")
	P.panel(self,r,false,1,true)
	draw_colored_polygon(P.polygon(r.grow(-4),7),tint)
	for i in range(6):
		var rr = Rect2(r.position+Vector2(5,5+i*(r.size.y-10)/6),Vector2(r.size.x-10,(r.size.y-10)/6+1))
		draw_rect(rr,Color(.1,.25,.35,(1-i/6.0)*.07))
	if active:
		var pulse = .7+.3*sin(clock*2.4)+maxf(0,1-active_age*2)*.4
		for k in range(5,0,-1): P.outline(self,r.grow(k*.8),Color(.06,.72,1,.04*pulse),k*1.8,9)
		P.outline(self,r,Color(.15,.88,1,.8+pulse*.2),2.2)
		P.outline(self,r.grow(-3),Color(.3,1,1,.3),.8,7)
		var point = r.position+Vector2(r.size.x*(.5+.45*sin(clock*.6+b)),0)
		P.diamond(self,point,2.4,P.BLUE)
	var inner = r.grow(-size.x*.018)
	for i in [1,2]:
		var x = inner.position.x+inner.size.x*i/3
		var y = inner.position.y+inner.size.y*i/3
		draw_line(Vector2(x,inner.position.y),Vector2(x,inner.end.y),Color(.35,.49,.59,.43),maxf(.7,size.x/650),true)
		draw_line(Vector2(inner.position.x,y),Vector2(inner.end.x,y),Color(.35,.49,.59,.43),maxf(.7,size.x/650),true)
	var owner: int = game.owners[b]
	for c in range(9):
		var mark: int = game.cells[b*9+c]
		if mark == 0:
			if hover_move == Vector2i(b,c) and game.is_legal(b,c):
				P.mark(self,cell_center(b,c),inner.size.x*.11,game.turn,.22)
			continue
		var age: float = mark_ages.get(b*9+c,1.0)
		var pop = 1.0
		if age < .32 and not reduced_motion: pop = 1+sin(age/.32*PI)*.25
		P.mark(self,cell_center(b,c),inner.size.x*.115*pop,mark,.22 if owner != 0 else 1.0,1.4 if age < .3 else 1.0)
		if age < .4 and not reduced_motion:
			for i in range(6):
				var pos = cell_center(b,c)+Vector2.from_angle(i*TAU/6)*age*inner.size.x*.7
				P.diamond(self,pos,1.5,Color(P.BLUE if mark == 1 else P.GOLD,(1-age/.4)*.6))
	if owner != 0:
		var col = P.BLUE if owner == 1 else (P.GOLD if owner == 2 else P.MUTED)
		draw_colored_polygon(P.polygon(r.grow(-4)),Color(col,.09))
		P.outline(self,r,Color(col,.75),1.8)
		var reveal = 1.0
		for fx in claims:
			if fx.board == b: reveal = clampf((fx.age/claim_duration()-.42)*3.0,0,1)
		if owner == 3:
			P.crystal(self,r.get_center(),r.size.x*.28,Color(.5,.65,.75,.5))
			P.text(self,"SEALED",Rect2(r.position+Vector2(0,r.size.y*.72),Vector2(r.size.x,r.size.y*.16)),maxi(9,int(r.size.x*.11)),P.MUTED,P.SERIF)
		elif reveal > 0:
			var pop = reveal*(1.0+.15*sin(reveal*PI))
			P.mark(self,r.get_center(),r.size.x*.38*pop,owner,.95,1.8)
	if hint_move.x == b and hint_move.y >= 0:
		var center = cell_center(b,hint_move.y)
		var pulse = .75+.25*sin(clock*5)
		draw_arc(center,inner.size.x*.14,0,TAU,32,Color(1,.92,.53,pulse),1.7,true)
		for i in range(4): P.diamond(self,center+Vector2.from_angle(clock*.5+i*PI/2)*inner.size.x*.16,2,Color(1,.94,.6,pulse))
func _draw_claim(fx: Dictionary):
	var r = tile_rect(fx.board)
	var p = clampf(fx.age/claim_duration(),0,1)
	var color = P.BLUE if fx.player == 1 else P.GOLD
	if fx.player == 3:
		draw_arc(r.get_center(),r.size.x*(.1+p*.4),0,TAU,48,Color(P.MUTED,(1-p)*.5),1,true)
		return
	if p > .42 and game.owners[fx.board] != fx.player:
		var reveal = clampf((p-.42)*3,0,1)
		draw_colored_polygon(P.polygon(r.grow(-3)),Color(.01,.04,.08,reveal*.8))
		P.outline(self,r,Color(color,reveal),2)
		P.mark(self,r.get_center(),r.size.x*.38*reveal*(1+.15*sin(reveal*PI)),fx.player,.95,2)
	if p < .6:
		draw_colored_polygon(P.polygon(r.grow(-2)),Color(color,sin(p/.6*PI)*.28))
	var lines: Array = game.small_lines[fx.board]
	if lines.is_empty(): lines = [[0,4,8]]
	for line in lines:
		var a = cell_center(fx.board,line[0]); var z = cell_center(fx.board,line[2])
		P.line_glow(self,a,a.lerp(z,clampf(p*5,0,1)),Color(color,1-p*.65),maxf(2,size.x*.008)*(1-p*.4))
	if p > .13:
		var q = (p-.13)/.87
		draw_arc(r.get_center(),r.size.x*(.08+q*.8),0,TAU,64,Color(color,(1-q)*.85),maxf(1,4*(1-q)),true)
		var amount = 10 if reduced_motion else 32
		for i in range(amount):
			var angle = i*2.39996
			var travel = q*r.size.x*(.35+fmod(i*.37,1)*.55)
			var pos = r.get_center()+Vector2.from_angle(angle)*travel+Vector2(0,q*q*18)
			if fx.player == 1: P.crystal(self,pos,(1-q)*(3+i%4),Color(color,(1-q)*.9),angle+q*2)
			else: P.diamond(self,pos,(1-q)*(2+i%3),Color(color,1-q))
func _draw_win(p: float):
	var color = P.BLUE if win_fx.player == 1 else P.GOLD
	var line: Array = win_fx.line
	if line.size() >= 3:
		var a = tile_rect(line[0]).get_center(); var z = tile_rect(line[2]).get_center()
		P.line_glow(self,a,a.lerp(z,clampf(p*3.5,0,1)),color,size.x*.018*(1+.15*sin(clock*8)))
		for b in line: draw_arc(tile_rect(b).get_center(),tile_rect(b).size.x*.43,0,TAU,64,Color(color,.8*(1-p)),size.x*.008,true)
	if p < .5:
		draw_rect(Rect2(Vector2.ZERO,size),Color(color,sin(clampf(p*2,0,1)*PI)*.18))
