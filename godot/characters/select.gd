extends Control
const R = preload("res://characters/roster.gd")
const Rig = preload("res://characters/rig.gd")
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
signal focused(id: String)
signal confirmed(id: String, display_name: String)
signal back
signal name_changed(value: String)
class Portrait extends Button:
	var index: int = 0
	var selected: bool = false
	var rig
	func _ready():
		for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rig = Rig.new(); rig.hero_id = R.DATA[index].id; rig.bust = true; rig.frozen = true
		rig.position = Vector2(5,4); rig.size = Vector2(size.x-10,size.y-23); add_child(rig); rig.pose(1.4)
	func _draw():
		P.panel(self,Rect2(Vector2(2,2),size-Vector2(4,4)),selected or has_focus())
		P.text(self,R.DATA[index].name.get_slice(" ",0),Rect2(4,size.y-22,size.x-8,19),14,P.PALE)
		if selected: P.outline(self,Rect2(Vector2(5,5),size-Vector2(10,10)),P.BLUE,1.5)
var selected_id: String = "vesper_vale"
var display_name: String = "You"
var reduced_motion: bool = false
var hinge: Rect2
var geo: Dictionary
var hero
var portraits: Array = []
var field: LineEdit
var confirm_button
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	geo = geometry(size,hinge)
	hero = Rig.new(); hero.hero_id = selected_id; hero.position = geo.hero.position; hero.size = geo.hero.size; hero.reduced_motion = reduced_motion; add_child(hero)
	for i in range(12):
		var tile = Portrait.new(); tile.index = i; tile.position = geo.tiles[i].position; tile.size = geo.tiles[i].size
		tile.selected = R.DATA[i].id == selected_id
		tile.pressed.connect(func(): focus_hero(R.DATA[i].id))
		tile.mouse_entered.connect(func(): focus_hero(R.DATA[i].id))
		tile.focus_entered.connect(func(): focus_hero(R.DATA[i].id))
		add_child(tile); portraits.append(tile)
	var exit_button = ButtonArt.new(); exit_button.icon_kind = "back"; exit_button.position = geo.back.position; exit_button.size = geo.back.size
	exit_button.pressed.connect(func(): back.emit()); add_child(exit_button)
	field = LineEdit.new(); field.position = geo.field.position; field.size = geo.field.size; field.text = display_name
	field.placeholder_text = "Your screen name"; field.max_length = 24
	field.add_theme_font_override("font",P.SANS); field.add_theme_font_size_override("font_size",20)
	var style = StyleBoxFlat.new(); style.bg_color = P.NAVY; style.border_color = P.GOLD; style.set_border_width_all(2); style.content_margin_left = 10
	field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("focus",style)
	field.add_theme_color_override("font_color",P.PALE); field.add_theme_color_override("caret_color",P.BLUE)
	field.text_changed.connect(func(value): display_name = value; name_changed.emit(value))
	field.text_submitted.connect(func(_value): _confirm())
	add_child(field)
	confirm_button = ButtonArt.new(); confirm_button.caption = "LOCK IN" if size.y < 360 else "WEAVE YOUR LEGEND"; confirm_button.accent = true
	confirm_button.position = geo.confirm.position; confirm_button.size = geo.confirm.size
	confirm_button.pressed.connect(_confirm); add_child(confirm_button)
func _confirm():
	if confirm_button.disabled: return
	confirm_button.disabled = true; field.release_focus(); confirmed.emit(selected_id,display_name)
func focus_hero(id: String):
	if confirm_button != null and confirm_button.disabled: return
	if id == selected_id: return
	selected_id = id; hero.configure(id); hero.set_clip("hover_react"); focused.emit(id)
	for tile in portraits: tile.selected = R.DATA[tile.index].id == id; tile.queue_redraw()
	queue_redraw()
static func geometry(s: Vector2, seam: Rect2 = Rect2()) -> Dictionary:
	var wide = s.x > s.y or seam.size.x > 0
	var g = {"tiles":[],"back":Rect2(12,12,44,44)}
	var grid: Rect2; var cols = 4
	if wide:
		var split = seam.end.x+12 if seam.size.x > 0 else s.x*.49
		var left_end = seam.position.x-12 if seam.size.x > 0 else split-12
		g.hero = Rect2(12,54,left_end-24,s.y-149)
		g.plaque = Rect2(16,s.y-90,left_end-32,70)
		grid = Rect2(split,62,s.x-split-16,s.y-190)
		g.field = Rect2(split,s.y-116,s.x-split-16,44)
		g.confirm = Rect2(split,s.y-62,s.x-split-16,48)
		g.heading = Rect2(split,12,s.x-split-16,38)
		if s.y < 360:
			var right_width = s.x-split-16
			grid.size.y = s.y-134
			g.field = Rect2(split,s.y-60,right_width*.46,44)
			g.confirm = Rect2(split+right_width*.5,s.y-60,right_width*.5,44)
	else:
		var grid_y = s.y*.605
		g.hero = Rect2(12,60,s.x-24,grid_y-164)
		g.plaque = Rect2(20,grid_y-104,s.x-40,56)
		g.field = Rect2(24,grid_y-46,s.x-48,44)
		grid = Rect2(16,grid_y+8,s.x-32,s.y-grid_y-80)
		g.confirm = Rect2(24,s.y-62,s.x-48,48)
		g.heading = Rect2(66,12,s.x-88,40)
	g.grid = grid
	var pitch = Vector2(grid.size.x/cols,grid.size.y/3)
	for i in range(12):
		# A shallow gold arc: the centre columns sit 3px lower.
		var arc = 3 if i%4 in [1,2] else 0
		g.tiles.append(Rect2(grid.position+Vector2(i%cols*pitch.x,int(i/cols)*pitch.y+arc),pitch-Vector2(6,6)))
	return g
func _draw():
	if geo.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("061126"))
	var h = R.get_hero(selected_id); var col = Color(h.palette[0])
	P.text(self,"CHOOSE YOUR LEGEND",geo.heading,24,P.PALE,P.SERIF)
	var r: Rect2 = geo.hero
	P.halo(self,r.get_center(),minf(r.size.x,r.size.y)*.8,Color(col,.3))
	# Graphic crystal rays stay behind the character and never enter the fold gutter.
	for i in range(11):
		var x = r.position.x+r.size.x*i/10
		draw_line(Vector2(x,r.end.y),r.get_center()+Vector2(0,-r.size.y*.35),Color(col,.08),2)
	P.outline(self,r.grow(-3),Color(P.GOLD,.3),1)
	var plaque: Rect2 = geo.plaque
	P.panel(self,plaque,false,1,true)
	var lanes = plaque_lanes(plaque)
	P.text(self,h.name.to_upper(),lanes.name,P.fit_box(h.name.to_upper(),lanes.name,25,P.SERIF),P.PALE,P.SERIF)
	P.text(self,h.pop,lanes.line,P.fit_box(h.pop,lanes.line,18),P.WHITE)
	draw_mark_preview(self,Vector2(plaque.end.x-27,plaque.position.y+plaque.size.y*.27),15,R.index_of(selected_id))
## Round 3c: text lanes inside the plaque's gold frame (the name used to rise into the
## top border). The mark preview keeps the right 52 px of the name lane.
static func plaque_lanes(plaque: Rect2) -> Dictionary:
	var t = clampf(minf(plaque.size.x,plaque.size.y)*.07,2.6,5.0)+2
	var split = plaque.size.y*.54
	return {"frame":t,"name":Rect2(plaque.position.x+9,plaque.position.y+t,plaque.size.x-52,split-t),
		"line":Rect2(plaque.position.x+8,plaque.position.y+split,plaque.size.x-16,plaque.size.y-split-t)}
static func draw_mark_preview(node: CanvasItem, center: Vector2, radius: float, index: int):
	var col = Color(R.DATA[index].palette[0]); var trim = Color(R.DATA[index].palette[2])
	if index%2 == 0:
		for side in [-1,1]:
			var a = center+Vector2(-radius,-radius*side); var b = center+Vector2(radius,radius*side)
			node.draw_line(a,b,INK(),radius*.4,true); node.draw_line(a,b,col,radius*.22,true)
			for j in range(3):
				var at = a.lerp(b,.2+j*.3)
				P.diamond(node,at,radius*(.12 if index != 8 else .19),trim)
	else:
		node.draw_arc(center,radius,0,TAU,40,col,radius*.24,true)
		for j in range(4+index%3):
			var a = j*TAU/(4+index%3)
			P.diamond(node,center+Vector2.from_angle(a)*radius,radius*.18,trim)
		if index in [5,11]: P.crystal(node,center,radius*.48,trim,.2)
		if index == 9: node.draw_arc(center,radius*.58,.4,TAU*1.4,30,trim,1.5,true)
static func INK() -> Color: return Color("071426")
