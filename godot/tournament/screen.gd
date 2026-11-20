extends Control
## Tournament chrome. BracketView itself is also usable without this screen.
const View = preload("res://tournament/bracket_view.gd")
const B = preload("res://tournament/bracket.gd")
const P = preload("res://ui/paint.gd")
const R = preload("res://characters/roster.gd")
const Art = preload("res://characters/art.gd")
const ButtonArt = preload("res://characters/match_button.gd")
const VideoOverlay = preload("res://characters/hero_video_overlay.gd")
signal action(kind: String)
signal victory_started
var data: Dictionary = {}
var events: Array = []
var trophies: int = 0
var hero_trophies: int = 0
var reduced_motion: bool = false
var play_victory: bool = true
var video_source
var sound_enabled: bool = true
var video_overlay
var bracket
var geo: Dictionary = {}
var controls: Dictionary = {}
var age: float = 0
var confirm_abandon: bool = false
var _dialog: Control
var _video_attempted: bool = false
var _hero_texture: Texture2D
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	geo = geometry(size,str(data.status))
	_hero_texture = Art.get_texture(str(data.hero),"victory" if data.status == "champion" else "splash")
	if data.status == "bracket":
		bracket = View.new(); bracket.position = geo.bracket.position; bracket.size = geo.bracket.size
		bracket.reduced_motion = reduced_motion; add_child(bracket); bracket.present(data.model,events,str(data.hero))
		_button("play","PLAY NEXT MATCH",geo.primary,func():
			if bracket.settled(): action.emit("play"),true)
		_button("abandon","ABANDON TOURNAMENT",geo.secondary,_show_abandon)
		_button("menu","MENU",geo.menu,func(): action.emit("menu"))
	else:
		_button("retry","TRY AGAIN",geo.primary,func(): action.emit("retry"),true)
		_button("menu","MAIN MENU",geo.secondary,func(): action.emit("menu"))
	video_overlay = VideoOverlay.new(); video_overlay.source = video_source
	video_overlay.set_sound_enabled(sound_enabled); video_overlay.z_index = 50; add_child(video_overlay)
	# Consume the complete skip gesture above the outcome buttons. A tap on a
	# full-screen clip must not accidentally start another tournament underneath.
	video_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video_overlay.gui_input.connect(_video_input)
	video_overlay.finished.connect(func(): video_overlay.clear())
	queue_redraw()
func _button(id: String, label: String, rect: Rect2, callback: Callable, accent: bool = false, parent: Node = null):
	var button = ButtonArt.new(); button.name = id; button.caption = label; button.accent = accent
	button.position = rect.position; button.size = rect.size
	button.pressed.connect(callback)
	if parent == null: add_child(button)
	else: parent.add_child(button)
	controls[id] = button
func _process(delta):
	age += minf(delta,.1)
	if is_instance_valid(bracket): controls.play.disabled = not bracket.settled()
	if data.status == "champion" and age >= .95 and not _video_attempted:
		_video_attempted = true
		if play_victory and not reduced_motion:
			victory_started.emit(); video_overlay.display_lane = geo.hero; video_overlay.begin("spotlight",data.hero,"",1,size)
	queue_redraw()
func _gui_input(event):
	var tap = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tap and is_instance_valid(video_overlay) and video_overlay.visible:
		video_overlay.clear(); accept_event()
func _video_input(event):
	var release = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if release: video_overlay.clear()
	video_overlay.accept_event()
func _unhandled_key_input(event):
	if event.is_action_pressed("ui_cancel"):
		if video_overlay.visible: video_overlay.clear()
		elif confirm_abandon: _close_dialog()
		else: action.emit("menu")
		accept_event()
func _show_abandon():
	if confirm_abandon: return
	confirm_abandon = true
	_dialog = Control.new(); _dialog.size = size; _dialog.z_index = 40; _dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog.draw.connect(func():
		_dialog.draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,.85))
		P.panel(_dialog,geo.dialog,false,1,true)
		P.text(_dialog,"ABANDON THIS RUN?",Rect2(geo.dialog.position+Vector2(12,18),Vector2(geo.dialog.size.x-24,36)),22,P.PALE,P.SERIF)
		P.text(_dialog,"Your earned trophies stay yours.",Rect2(geo.dialog.position+Vector2(12,64),Vector2(geo.dialog.size.x-24,30)),18,P.WHITE)
		P.text(_dialog,"This bracket will be cleared.",Rect2(geo.dialog.position+Vector2(12,94),Vector2(geo.dialog.size.x-24,28)),16,P.MUTED))
	add_child(_dialog)
	var r: Rect2 = geo.dialog
	_button("cancel_abandon","KEEP PLAYING",Rect2(r.position+Vector2(14,140),Vector2(r.size.x-28,48)),_close_dialog,true,_dialog)
	_button("confirm_abandon","ABANDON RUN",Rect2(r.position+Vector2(14,198),Vector2(r.size.x-28,48)),func(): action.emit("abandon"),false,_dialog)
func _close_dialog():
	confirm_abandon = false
	if is_instance_valid(_dialog): _dialog.queue_free()
	controls.erase("cancel_abandon"); controls.erase("confirm_abandon")
static func geometry(s: Vector2, status: String) -> Dictionary:
	var phone = s.x < 700
	var g = {"phone":phone,"menu":Rect2(s.x-94,12,80,44),"dialog":Rect2((s.x-minf(360,s.x-32))*.5,(s.y-276)*.5,minf(360,s.x-32),276)}
	if phone:
		g.eyebrow = Rect2(16,24,s.x-120,24)
		g.title = Rect2(16,58,s.x-32,42)
		g.subtitle = Rect2(16,102,s.x-32,25)
		g.bracket = Rect2(16,134,s.x-32,maxf(260,minf(470,s.y-364)))
		g.preview = Rect2(16,s.y-218,s.x-32,92)
		g.primary = Rect2(16,s.y-116,s.x-32,52)
		g.secondary = Rect2(16,s.y-58,s.x-32,46)
		g.hero = Rect2(44,278,s.x-88,maxf(120,s.y-554))
		g.trophy = Rect2(s.x*.5-40,188,80,80)
		g.name = Rect2(16,s.y-276,s.x-32,40)
		g.count = Rect2(28,s.y-218,s.x-56,72)
		if status != "bracket":
			g.eyebrow = Rect2(16,44,s.x-32,26)
			g.title = Rect2(12,82,s.x-24,70)
			g.subtitle = Rect2(16,156,s.x-32,24)
	else:
		var left = s.x*.70
		g.eyebrow = Rect2(32,25,s.x-160,26)
		g.title = Rect2(32,56,s.x-64,54)
		g.subtitle = Rect2(32,112,s.x-64,28)
		g.bracket = Rect2(32,168,left-58,s.y-220)
		g.preview = Rect2(left+12,168,s.x-left-44,s.y-322)
		g.primary = Rect2(left+12,s.y-132,s.x-left-44,54)
		g.secondary = Rect2(left+12,s.y-68,s.x-left-44,48)
		g.hero = Rect2(s.x*.08,120,s.x*.36,s.y-156)
		g.trophy = Rect2(s.x*.73-50,282,100,100)
		g.name = Rect2(s.x*.48,400,s.x*.46,60)
		g.count = Rect2(s.x*.51,490,s.x*.40,80)
		if status != "bracket":
			g.eyebrow = Rect2(s.x*.48,94,s.x*.46,28)
			g.title = Rect2(s.x*.47,136,s.x*.48,108)
			g.subtitle = Rect2(s.x*.49,244,s.x*.44,30)
			g.primary = Rect2(s.x*.52,s.y-126,s.x*.19,54)
			g.secondary = Rect2(s.x*.73,s.y-126,s.x*.20,54)
	return g
func _draw():
	if geo.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("071222"))
	_background()
	if data.status == "bracket": _draw_bracket_chrome()
	else: _draw_outcome()
func _background():
	var origin = Vector2(size.x*.5,size.y*.38)
	for i in range(3):
		draw_arc(origin,minf(size.x,size.y)*(.35+i*.16),0,TAU,96,Color(P.GOLD,.045),1,true)
	for i in range(32):
		var at = Vector2(fposmod(i*137.31+31,size.x),fposmod(i*93.47+15,size.y))
		P.diamond(self,at,1.1 if i%3 else 2,Color(P.GOLD,.14 if i%3 else .3))
	draw_line(Vector2(16,12),Vector2(size.x-16,12),Color(P.GOLD,.38),1,true)
	P.diamond(self,Vector2(size.x*.5,12),4,P.GOLD)
func _draw_bracket_chrome():
	P.text(self,"LEXERLY / TOURNAMENT",geo.eyebrow,14,P.GOLD,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	P.text(self,"THE CROWN AWAITS",geo.title,30 if geo.phone else 42,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_LEFT)
	P.text(self,"8 HEROES    /    3 ROUNDS    /    1 CROWN",geo.subtitle,15,P.MUTED,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	var next = B.next_match(data.model,data.hero)
	if next.is_empty(): return
	var r: Rect2 = geo.preview; P.panel(self,r,false,1,false)
	var opponent: String = next.match.b if next.match.a == data.hero else next.match.a
	var level = ["Easy","Medium","Hard"][clampi(next.round,0,2)]
	var title = B.round_name(data.model,next.round)+" · "+level
	if geo.phone:
		P.text(self,title,Rect2(r.position+Vector2(12,7),Vector2(r.size.x-24,22)),18,P.GOLD,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		var icon = Rect2(r.position+Vector2(12,33),Vector2(46,46))
		draw_texture_rect(Art.get_texture(opponent,"head_neutral"),icon,false)
		P.text(self,"VS  "+R.get_hero(opponent).name.to_upper(),Rect2(r.position+Vector2(66,34),Vector2(r.size.x-78,23)),20,P.WHITE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		P.text(self,"CHESS RIVAL" if opponent == data.rival else "ONE LOSS ENDS YOUR RUN",Rect2(r.position+Vector2(66,60),Vector2(r.size.x-78,18)),12,P.BLUE if opponent == data.rival else P.MUTED,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	else:
		P.text(self,"YOUR NEXT MATCH",Rect2(r.position+Vector2(12,14),Vector2(r.size.x-24,26)),15,P.MUTED)
		P.text(self,title,Rect2(r.position+Vector2(12,48),Vector2(r.size.x-24,32)),24,P.GOLD)
		var art = Rect2(r.position+Vector2(24,90),Vector2(r.size.x-48,r.size.y-186))
		var texture = Art.get_texture(opponent,"versus")
		var dimensions = texture.get_size()*minf(art.size.x/texture.get_width(),art.size.y/texture.get_height())
		draw_texture_rect(texture,Rect2(art.get_center()-dimensions*.5,dimensions),false)
		P.text(self,R.get_hero(opponent).name.to_upper(),Rect2(r.position.x+12,r.end.y-86,r.size.x-24,32),24,P.WHITE,P.SERIF)
		P.text(self,"CHESS RIVAL" if opponent == data.rival else "ONE LOSS ENDS YOUR RUN",Rect2(r.position.x+12,r.end.y-44,r.size.x-24,24),14,P.BLUE if opponent == data.rival else P.MUTED)
func _draw_outcome():
	var champion = data.status == "champion"
	var col = P.GOLD if champion else P.MUTED
	if champion: _celebration()
	P.text(self,"LEXERLY / TOURNAMENT",geo.eyebrow,15,P.GOLD)
	P.text(self,"CHAMPION" if champion else "ELIMINATED",geo.title,46 if geo.phone else 66,P.PALE if champion else P.WHITE,P.DISPLAY)
	var subtitle = "THREE VICTORIES. ONE UNBROKEN THREAD." if champion else "Eliminated in the "+B.round_name(data.model,int(data.round))
	P.text(self,subtitle,geo.subtitle,15 if champion else 18,col)
	var t = 1.0 if reduced_motion else clampf(age/.75,0,1)
	var hero: Rect2 = geo.hero
	if _hero_texture:
		var dim = _hero_texture.get_size()*minf(hero.size.x/_hero_texture.get_width(),hero.size.y/_hero_texture.get_height())*lerpf(.92,1,t)
		draw_texture_rect(_hero_texture,Rect2(hero.get_center()-dim*.5,dim),false,Color(1,1,1,t) if champion else Color(.48,.55,.64,.75*t))
	if champion:
		var trophy_rect = trophy_pose(age)
		P.halo(self,trophy_rect.get_center(),66,Color(P.GOLD,.24)); View.trophy(self,trophy_rect,P.GOLD)
	P.text(self,R.get_hero(data.hero).name.to_upper(),geo.name,26 if geo.phone else 36,P.PALE,P.SERIF)
	if champion:
		var r: Rect2 = geo.count
		P.panel(self,r,false,1,false)
		P.text(self,"TROPHY EARNED  ·  %d WITH THIS HERO" % hero_trophies,Rect2(r.position+Vector2(12,8),Vector2(r.size.x-24,26)),17,P.GOLD)
		P.text(self,"%d TOTAL TROPHIES  /  SAVED ON THIS DEVICE" % trophies,Rect2(r.position+Vector2(12,37),Vector2(r.size.x-24,24)),13,P.MUTED)
func trophy_pose(seconds: float) -> Rect2:
	# Reserve the whole drop lane in layout; even the spring's overshoot stays
	# between the subtitle and hero, on both phone and desktop.
	var slot: Rect2 = geo.trophy
	var drop = 1.0 if reduced_motion else clampf(seconds/.62,0,1)
	var c = drop-1
	var bounce = 1+c*c*(2.70158*c+1.70158)
	return Rect2(slot.position+Vector2(slot.size.x*.1,slot.size.y*.16*bounce),slot.size*.8)
func _celebration():
	var at = geo.trophy.get_center()
	var t = 1.0 if reduced_motion else clampf(age/.8,0,1)
	for i in range(20):
		var a = i*TAU/20+(0 if reduced_motion else age*.035)
		var v = Vector2.from_angle(a); var n = v.orthogonal()
		draw_colored_polygon(PackedVector2Array([at+v*40,at+v*size.length()+n*18,at+v*size.length()-n*18]),Color(P.GOLD,.035*t))
	if reduced_motion: return
	for i in range(64):
		var phase = fposmod(age*.13+i*.618,1)
		var x = fposmod(i*97.13+sin(age+i)*12,size.x)
		var y = -20+phase*(size.y+40)
		var angle = age*(1+i%3)+i*2.4; var v = Vector2.from_angle(angle)*float(2+i%3)
		var c = P.BLUE if i%3 == 0 else P.GOLD
		if age < 5: draw_line(Vector2(x,y)-v,Vector2(x,y)+v,Color(c,t*.8),2,true)
