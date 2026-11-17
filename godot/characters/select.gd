extends Control
const R = preload("res://characters/roster.gd")
const Rig = preload("res://characters/art.gd")
const P = preload("res://ui/paint.gd")
const Layout = preload("res://ui/layout.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
signal focused(id: String)
signal confirmed(id: String, display_name: String)
signal back
signal name_changed(value: String)
class Portrait extends Button:
	var index: int = 0
	var selected: bool = false
	var trophies: int = 0
	var rig
	func _ready():
		for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rig = Rig.new(); rig.hero_id = R.DATA[index].id; rig.bust = true; rig.frozen = true
		var band = caption_height()
		rig.position = Vector2(3,0); rig.size = Vector2(size.x-6,size.y-band); add_child(rig)
	func _draw():
		var r = Rect2(Vector2(2,2),size-Vector2(4,4))
		draw_style_box(_frame(),r)
		var lines = caption_lines()
		var band = caption_height()
		if lines.size() == 1:
			P.text(self,lines[0],Rect2(3,size.y-band,size.x-6,band),P.fit_size(lines[0],size.x-8,14),P.PALE,P.SANS)
		else:
			var fs = mini(P.fit_size(lines[0],size.x-8,13),P.fit_size(lines[1],size.x-8,13))
			var half = band*.5
			P.text(self,lines[0],Rect2(3,size.y-band,size.x-6,half),fs,P.PALE,P.SANS)
			P.text(self,lines[1],Rect2(3,size.y-band+half,size.x-6,half),fs,P.PALE,P.SANS)
		if selected: P.outline(self,r.grow(-1),P.BLUE,2)
		if trophies > 0:
			draw_rect(Rect2(size.x-27,3,24,17),Color("091224"))
			preload("res://tournament/bracket_view.gd").trophy(self,Rect2(size.x-26,5,12,12),P.GOLD)
			P.text(self,str(trophies),Rect2(size.x-14,3,12,17),11,P.GOLD)
	func caption_lines() -> PackedStringArray:
		# Compact tiles use the familiar first name; the selected plaque keeps the full name.
		if R.DATA[index].id == "madame_solstice": return PackedStringArray(["BETH"])
		return R.tile_lines(R.DATA[index].id)
	func caption_height() -> int:
		return 28 if caption_lines().size() > 1 else 18
	func _frame() -> StyleBoxFlat:
		var style = StyleBoxFlat.new(); style.bg_color = Color("14243a") if not selected else Color("25425c")
		style.border_color = P.GOLD if selected else Color("35445a"); style.set_border_width_all(2)
		return style
var selected_id: String = "cryon"
var display_name: String = "You"
var heading: String = "CHOOSE YOUR HERO"
var confirm_caption: String = "LOCK IN"
var blocked_id: String = ""
var reduced_motion: bool = false
var trophy_counts: Dictionary = {}
var hinge: Rect2
var geo: Dictionary
var hero
var portraits: Array = []
var field: LineEdit
var confirm_button
var page: int = 0
var paging_controls: Array = []
var _drag_start = Vector2.ZERO
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	geo = geometry(size,hinge)
	page = int(R.index_of(selected_id)/geo.per_page) if geo.paged else 0
	hero = Rig.new(); hero.hero_id = selected_id; hero.bust = false; hero.art_key = "splash"
	hero.position = geo.hero.position; hero.size = geo.hero.size; hero.reduced_motion = reduced_motion; add_child(hero)
	for i in range(R.DATA.size()):
		var tile = Portrait.new(); tile.index = i; tile.selected = R.DATA[i].id == selected_id
		tile.trophies = int(trophy_counts.get(R.DATA[i].id,0))
		tile.position = geo.tiles[i%geo.per_page].position; tile.size = geo.tiles[i%geo.per_page].size
		tile.disabled = R.DATA[i].id == blocked_id; tile.modulate.a = .28 if tile.disabled else 1.0
		tile.pressed.connect(func(): focus_hero(R.DATA[i].id))
		tile.focus_entered.connect(func(): focus_hero(R.DATA[i].id))
		tile.visible = not geo.paged or int(i/geo.per_page) == page
		add_child(tile); portraits.append(tile)
	var exit_button = ButtonArt.new(); exit_button.icon_kind = "back"; exit_button.position = geo.back.position; exit_button.size = geo.back.size
	exit_button.pressed.connect(func(): back.emit()); add_child(exit_button)
	field = LineEdit.new(); field.position = geo.field.position; field.size = geo.field.size; field.text = display_name
	field.placeholder_text = "Your screen name"; field.max_length = 24
	field.add_theme_font_override("font",P.SANS); field.add_theme_font_size_override("font_size",20)
	var style = StyleBoxEmpty.new(); style.content_margin_left = 16; style.content_margin_right = 16; style.content_margin_top = 12
	field.add_theme_stylebox_override("normal",style); field.add_theme_stylebox_override("focus",style)
	field.add_theme_stylebox_override("read_only",style)
	field.add_theme_color_override("font_color",P.PALE); field.add_theme_color_override("caret_color",P.BLUE)
	field.add_theme_color_override("font_placeholder_color",P.MUTED)
	field.add_theme_color_override("font_uneditable_color",P.PALE)
	field.focus_entered.connect(queue_redraw); field.focus_exited.connect(queue_redraw)
	field.text_changed.connect(func(value): display_name = value; name_changed.emit(value))
	field.text_submitted.connect(func(_value): _confirm()); add_child(field)
	confirm_button = ButtonArt.new(); confirm_button.caption = confirm_caption; confirm_button.accent = true
	confirm_button.position = geo.confirm.position; confirm_button.size = geo.confirm.size
	confirm_button.pressed.connect(_confirm); add_child(confirm_button)
	if geo.paged:
		for direction in [-1,1]:
			var arrow = ButtonArt.new(); arrow.caption = "‹" if direction < 0 else "›"
			arrow.position = Vector2(geo.nav.position.x if direction < 0 else geo.nav.end.x-44,geo.nav.position.y); arrow.size = Vector2(44,44)
			arrow.pressed.connect(func(): change_page(direction)); add_child(arrow); paging_controls.append(arrow)
		for dot in range(geo.pages):
			var button = Button.new(); button.text = "•"; button.position = Vector2(geo.nav.get_center().x-geo.pages*22+dot*44,geo.nav.position.y); button.size = Vector2(44,44)
			button.add_theme_font_override("font",P.SANS); button.add_theme_font_size_override("font_size",36)
			for state in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			button.pressed.connect(func(): set_page(dot)); add_child(button); paging_controls.append(button)
	_sync_page()
func _input(event):
	if not geo.get("paged",false) or not is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		if event.pressed: _drag_start = event.position
		else: swipe(event.position-_drag_start)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _drag_start = event.position
		else: swipe(event.position-_drag_start)
func swipe(distance: Vector2):
	if absf(distance.x) > 48 and absf(distance.x) > absf(distance.y)*1.3:
		change_page(1 if distance.x < 0 else -1)
func change_page(direction: int): set_page(page+direction)
func set_page(value: int):
	page = posmod(value,geo.pages) if geo.paged else 0; _sync_page()
func _sync_page():
	for tile in portraits:
		var local_index = tile.index%geo.per_page
		tile.position = geo.tiles[local_index].position; tile.size = geo.tiles[local_index].size
		tile.visible = not geo.paged or int(tile.index/geo.per_page) == page
		if is_instance_valid(tile.rig):
			tile.rig.size = Vector2(tile.size.x-6,tile.size.y-tile.caption_height())
			if tile.visible and tile.rig.texture == null: tile.rig.refresh_texture()
	if geo.paged:
		for dot in range(geo.pages): paging_controls[2+dot].add_theme_color_override("font_color",P.BLUE if page == dot else P.MUTED)
	queue_redraw()
func _confirm():
	if confirm_button.disabled or selected_id == blocked_id: return
	confirm_button.disabled = true; field.release_focus(); confirmed.emit(selected_id,display_name)
func focus_hero(id: String):
	if not R.valid(id) or id == blocked_id or (confirm_button != null and confirm_button.disabled): return
	if id == selected_id: return
	selected_id = id; hero.configure(id); hero.art_key = "splash"; hero.refresh_texture(); hero.set_clip("hover_react"); focused.emit(id)
	for tile in portraits: tile.selected = R.DATA[tile.index].id == id; tile.queue_redraw()
	queue_redraw()
static func geometry(s: Vector2, seam: Rect2 = Rect2()) -> Dictionary:
	var mode = Layout.mode_for(s)
	var phone = mode == "phone_portrait" and seam.size.x <= 0
	var g = {"tiles":[],"back":Rect2(12,12,44,44),"paged":true,"pages":4 if phone else 2,"per_page":8 if phone else 16,"nav":Rect2(),"columns":4,"rows":2}
	var grid: Rect2
	if phone:
		g.heading = Rect2(66,12,s.x-78,40)
		g.hero = Rect2(12,60,s.x-24,s.y-480)
		g.plaque = Rect2(20,s.y-412,s.x-40,60)
		grid = Rect2(16,s.y-348,s.x-32,176)
		g.nav = Rect2(20,s.y-164,s.x-40,44)
		g.field = Rect2(24,s.y-112,s.x-48,44)
		g.confirm = Rect2(24,s.y-60,s.x-48,48)
	else:
		# Split hero preview and four-column paginated roster.
		var split = seam.end.x+12 if seam.size.x > 0 else s.x*(.46 if s.y < 360 else .42)
		var left_end = seam.position.x-12 if seam.size.x > 0 else split-12
		g.hero = Rect2(12,58,left_end-24,s.y-146)
		g.plaque = Rect2(16,s.y-80,left_end-32,64)
		g.heading = Rect2(split,12,s.x-split-16,38)
		grid = Rect2(split,58,s.x-split-12,s.y-132)
		# Sixteen larger portraits per wide page; narrow phones keep eight.
		g.paged = true; g.pages = 2; g.per_page = 16
		g.columns = 4; g.rows = 4
		grid.size.y -= 48
		g.nav = Rect2(split, s.y-116,s.x-split-12,44)
		g.field = Rect2(split,s.y-62,(s.x-split-20)*.55,44)
		g.confirm = Rect2(g.field.end.x+8,s.y-62,(s.x-split-20)*.45,44)
		if s.y < 360:
			# Put the form below the splash so four touchable rows have real room.
			g.paged = true; g.pages = 2; g.per_page = 16; g.columns = 4; g.rows = 4
			g.hero = Rect2(12,58,left_end-24,s.y-234)
			g.plaque = Rect2(16,s.y-172,left_end-32,60)
			g.field = Rect2(24,s.y-104,left_end-48,44)
			g.confirm = Rect2(24,s.y-52,left_end-48,44)
			grid = Rect2(split,58,s.x-split-12,s.y-114)
			g.nav = Rect2(split,s.y-52,s.x-split-12,44)
	g.grid = grid
	var pitch = Vector2(grid.size.x/g.columns,minf(grid.size.y/g.rows,grid.size.x/g.columns*1.30))
	var top = grid.position+Vector2(0,(grid.size.y-pitch.y*g.rows)*.5)
	for i in range(g.per_page): g.tiles.append(Rect2(top+Vector2(i%g.columns*pitch.x,int(i/g.columns)*pitch.y),pitch-Vector2(4,3)))
	return g

func _draw():
	if geo.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("081326"))
	var r: Rect2 = geo.field
	var edge = P.BLUE if is_instance_valid(field) and field.has_focus() else P.GOLD
	var points = PackedVector2Array([r.position+Vector2(10,0),Vector2(r.end.x,r.position.y),r.end-Vector2(10,0),Vector2(r.position.x,r.end.y)])
	draw_colored_polygon(points,P.NAVY)
	draw_polyline(points+PackedVector2Array([points[0]]),P.GOLD_DARK,5,true)
	draw_polyline(points+PackedVector2Array([points[0]]),edge,1.5,true)
	draw_line(points[0]+Vector2(3,2),points[3]+Vector2(3,-2),edge,3,true)
	P.diamond(self,Vector2(r.end.x-12,r.position.y+10),3,edge)
	P.text(self,"SCREEN NAME",Rect2(r.position+Vector2(16,1),Vector2(r.size.x-32,13)),11,P.GOLD,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	var h = R.get_hero(selected_id); var col = Color(h.palette[0])
	P.text(self,heading,geo.heading,P.fit_box(heading,geo.heading,25,P.SANS),P.PALE,P.SANS)
	P.halo(self,geo.hero.get_center(),minf(geo.hero.size.x,geo.hero.size.y)*.8,Color(col,.3))
	var plaque: Rect2 = geo.plaque
	P.panel(self,plaque,false,1,true)
	var lanes = plaque_lanes(plaque)
	P.text(self,h.name.to_upper(),lanes.name,P.fit_box(h.name.to_upper(),lanes.name,25,P.SERIF),P.PALE,P.SERIF)
	P.text(self,h.pop,lanes.line,P.fit_box(h.pop,lanes.line,18),P.WHITE)
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
