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
	var display_index: int = 0
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
		if selected or has_focus(): P.outline(self,r.grow(-1),P.BLUE,2)
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
var unlocked_heroes: Array = []
var visible_indices: Array = []
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
var grid_view: Control
var grid_content: Control
var scroll_offset := 0.0
const DRAG_SLOP := 10.0
var _pointer_index := -2 # -2 idle, -1 mouse, >= 0 touch ID
var _pointer_start := Vector2.ZERO
var _scroll_start := 0.0
var _dragged := false
var _pressed_tile := -1
func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible_indices = R.selectable_indices(unlocked_heroes)
	if not R.selectable(selected_id,unlocked_heroes) or selected_id == blocked_id:
		for i in visible_indices:
			if R.DATA[i].id != blocked_id:
				selected_id = R.DATA[i].id
				break
	geo = geometry(size,hinge,visible_indices.size())
	hero = Rig.new(); hero.hero_id = selected_id; hero.bust = false; hero.art_key = "splash"
	hero.position = geo.hero.position; hero.size = geo.hero.size; hero.reduced_motion = reduced_motion; add_child(hero)
	grid_view = Control.new(); grid_view.position = geo.grid.position; grid_view.size = geo.grid.size
	grid_view.clip_contents = true; grid_view.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(grid_view)
	grid_content = Control.new(); grid_content.mouse_filter = Control.MOUSE_FILTER_IGNORE; grid_view.add_child(grid_content)
	for display_index in range(visible_indices.size()):
		var i = visible_indices[display_index]
		var tile = Portrait.new(); tile.index = i; tile.display_index = display_index; tile.selected = R.DATA[i].id == selected_id
		tile.trophies = int(trophy_counts.get(R.DATA[i].id,0))
		tile.position = geo.tiles[display_index].position-geo.grid.position; tile.size = geo.tiles[display_index].size
		tile.disabled = R.DATA[i].id == blocked_id; tile.modulate.a = .28 if tile.disabled else 1.0
		tile.pressed.connect(func(): focus_hero(R.DATA[i].id))
		tile.focus_entered.connect(func(): reveal_index(display_index); focus_hero(R.DATA[i].id); tile.queue_redraw())
		tile.focus_exited.connect(tile.queue_redraw)
		tile.tooltip_text = R.get_hero(R.DATA[i].id).name
		tile.hide() # Only load portrait textures once they enter the viewport.
		grid_content.add_child(tile); portraits.append(tile)
	_wire_grid_focus()
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
	reveal_hero(selected_id)
	_update_visible_tiles()
func _wire_grid_focus():
	for tile in portraits:
		var column: int = tile.display_index % geo.columns
		for link in [["focus_neighbor_left",-1,column],["focus_neighbor_right",1,geo.columns-1-column],["focus_neighbor_top",-geo.columns,geo.rows],["focus_neighbor_bottom",geo.columns,geo.rows]]:
			for distance in range(1,link[2]+1):
				var target: int = tile.display_index+link[1]*distance
				if target < 0 or target >= portraits.size(): break
				if portraits[target].disabled: continue
				tile.set(link[0],tile.get_path_to(portraits[target]))
				break
		# Offscreen neighbors cannot receive built-in focus, so reveal them first.
		tile.gui_input.connect(func(event): _grid_key(event,tile))
func _grid_key(event: InputEvent, tile):
	for link in [["ui_left",tile.focus_neighbor_left],["ui_right",tile.focus_neighbor_right],["ui_up",tile.focus_neighbor_top],["ui_down",tile.focus_neighbor_bottom]]:
		if not event.is_action_pressed(link[0]) or link[1].is_empty(): continue
		var target = tile.get_node_or_null(link[1])
		if target:
			reveal_index(target.display_index)
			target.grab_focus()
			tile.accept_event()
		return
func _input(event):
	if not is_instance_valid(grid_view) or not is_visible_in_tree(): return
	var local: Vector2
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse or event is InputEventPanGesture:
		local = get_global_transform_with_canvas().affine_inverse()*event.position
	else: return
	if event is InputEventPanGesture:
		if geo.grid.has_point(local):
			_set_scroll(scroll_offset+event.delta.y*32)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed and geo.grid.has_point(local):
			_set_scroll(scroll_offset+(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)*maxf(1.0,event.factor)*48)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION: return
		if event.pressed: _begin_pointer(event.index,local)
		else: _end_pointer(event.index,local,event.canceled)
	elif event is InputEventScreenDrag:
		if event.device != InputEvent.DEVICE_ID_EMULATION: _move_pointer(event.index,local)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Godot can dispatch a second, emulated mouse event for a real touch.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if _pointer_index >= 0 or geo.grid.has_point(local): get_viewport().set_input_as_handled()
			return
		if event.pressed: _begin_pointer(-1,local)
		else: _end_pointer(-1,local,false)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_move_pointer(-1,local)
func _begin_pointer(index: int, at: Vector2):
	if not geo.grid.has_point(at): return
	get_viewport().set_input_as_handled()
	if _pointer_index != -2: return
	_pointer_index = index
	_pointer_start = at
	_scroll_start = scroll_offset
	_dragged = false
	_pressed_tile = _tile_at(at)
func _move_pointer(index: int, at: Vector2):
	if _pointer_index != index: return
	get_viewport().set_input_as_handled()
	var delta = at-_pointer_start
	_dragged = _dragged or delta.length() >= DRAG_SLOP
	if _dragged: _set_scroll(_scroll_start-delta.y)
func _end_pointer(index: int, at: Vector2, canceled: bool):
	if _pointer_index != index: return
	_move_pointer(index,at)
	var target = _tile_at(at)
	if not canceled and not _dragged and target >= 0 and target == _pressed_tile and not portraits[target].disabled:
		portraits[target].grab_focus()
		focus_hero(R.DATA[portraits[target].index].id)
	_pointer_index = -2
func _tile_at(at: Vector2) -> int:
	if not geo.grid.has_point(at): return -1
	var content_at = at+Vector2(0,scroll_offset)
	for tile in portraits:
		if tile.visible and geo.tiles[tile.display_index].has_point(content_at): return tile.display_index
	return -1
func reveal_hero(id: String):
	reveal_index(visible_indices.find(R.index_of(id)))
func reveal_index(index: int):
	if index < 0 or index >= geo.tiles.size(): return
	var tile: Rect2 = geo.tiles[index]
	var top: float = tile.position.y-geo.grid.position.y
	var bottom: float = tile.end.y-geo.grid.position.y
	if top < scroll_offset: _set_scroll(top)
	elif bottom > scroll_offset+geo.grid.size.y: _set_scroll(bottom-geo.grid.size.y)
func _set_scroll(value: float):
	scroll_offset = clampf(value,0,geo.scroll_max)
	grid_content.position.y = -scroll_offset
	_update_visible_tiles()
	queue_redraw()
func _update_visible_tiles():
	var view: Rect2 = geo.grid
	view.position.y += scroll_offset
	for tile in portraits:
		tile.visible = geo.tiles[tile.display_index].intersects(view)
		if tile.visible and tile.rig.texture == null: tile.rig.refresh_texture()
func _confirm():
	if confirm_button.disabled or selected_id == blocked_id or not R.selectable(selected_id,unlocked_heroes): return
	confirm_button.disabled = true; field.release_focus(); confirmed.emit(selected_id,display_name)
func focus_hero(id: String):
	if not R.selectable(id,unlocked_heroes) or id == blocked_id or (confirm_button != null and confirm_button.disabled): return
	if id == selected_id: return
	selected_id = id; hero.configure(id); hero.art_key = "splash"; hero.refresh_texture(); hero.set_clip("hover_react"); focused.emit(id)
	for tile in portraits: tile.selected = R.DATA[tile.index].id == id; tile.queue_redraw()
	queue_redraw()
static func geometry(s: Vector2, seam: Rect2 = Rect2(), hero_count: int = R.DATA.size()) -> Dictionary:
	var mode = Layout.mode_for(s)
	var phone = mode == "phone_portrait" and seam.size.x <= 0
	var g = {"tiles":[],"back":Rect2(12,12,44,44),"columns":4,"rows":ceili(float(hero_count)/4.0)}
	var grid: Rect2
	if phone:
		g.heading = Rect2(66,12,s.x-78,40)
		g.hero = Rect2(12,60,s.x-24,s.y-480)
		g.plaque = Rect2(20,s.y-412,s.x-40,60)
		grid = Rect2(16,s.y-348,s.x-32,228)
		g.field = Rect2(24,s.y-112,s.x-48,44)
		g.confirm = Rect2(24,s.y-60,s.x-48,48)
	else:
		# Split hero preview and four-column scrolling roster.
		var split = seam.end.x+12 if seam.size.x > 0 else s.x*(.46 if s.y < 360 else .42)
		var left_end = seam.position.x-12 if seam.size.x > 0 else split-12
		g.hero = Rect2(12,58,left_end-24,s.y-146)
		g.plaque = Rect2(16,s.y-80,left_end-32,64)
		g.heading = Rect2(split,12,s.x-split-16,38)
		grid = Rect2(split,58,s.x-split-12,s.y-132)
		g.field = Rect2(split,s.y-62,(s.x-split-20)*.55,44)
		g.confirm = Rect2(g.field.end.x+8,s.y-62,(s.x-split-20)*.45,44)
		if s.y < 360:
			# Put the form below the splash so the roster has full-height scrolling.
			g.hero = Rect2(12,58,left_end-24,s.y-234)
			g.plaque = Rect2(16,s.y-172,left_end-32,60)
			g.field = Rect2(24,s.y-104,left_end-48,44)
			g.confirm = Rect2(24,s.y-52,left_end-48,44)
			grid = Rect2(split,58,s.x-split-12,s.y-68)
	g.grid = grid
	var width = grid.size.x/g.columns
	var row_height = clampf(width*1.1,58,156)
	for i in range(hero_count):
		g.tiles.append(Rect2(grid.position+Vector2(i%g.columns*width,floorf(float(i)/g.columns)*row_height),Vector2(width-6,row_height-4)))
	g.scroll_max = maxf(0,g.rows*row_height-grid.size.y)
	return g

func _draw():
	if geo.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("081326"))
	if geo.scroll_max > 0:
		var grid: Rect2 = geo.grid
		var thumb = maxf(20.0,grid.size.y*grid.size.y/(grid.size.y+geo.scroll_max))
		draw_rect(Rect2(grid.end.x-3,grid.position.y+(grid.size.y-thumb)*scroll_offset/geo.scroll_max,3,thumb),P.GOLD)
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
