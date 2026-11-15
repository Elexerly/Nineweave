extends Control
## Scene/controller. Rules, AI, layout and networking remain independently testable.
const Rules = preload("res://kernel/rules.gd")
const AI = preload("res://ai/strategist.gd")
const Layout = preload("res://ui/layout.gd")
const P = preload("res://ui/paint.gd")
const Board = preload("res://ui/board.gd")
const Backdrop = preload("res://ui/backdrop.gd")
const OrnateButton = preload("res://ui/ornate_button.gd")
const Store = preload("res://settings/store.gd")
const Loopback = preload("res://net/loopback_transport.gd")
const HTTP = preload("res://net/http_polling_transport.gd")
const Sound = preload("res://fx/sound.gd")
const GODDESS_PORTRAIT = preload("res://assets/art/goddess_portrait.png")
const KNIGHT_PORTRAIT = preload("res://assets/art/knight_portrait.png")
## Result panel appears at this fraction of the game-win animation (real flow and debug poses).
const RESULT_AT = .75
const FIREWORK_BURSTS = 7
const FIREWORK_SPARKS = 36
## Real legal game used by the midgame capture (26 plies, X to move in Center).
const MIDGAME = [[1,0],[0,4],[4,6],[6,5],[5,7],[7,2],[2,3],[3,2],[2,7],[7,4],[4,1],[1,3],[3,8],[8,8],[8,3],[3,6],[6,1],[1,5],[5,8],[8,1],[1,4],[4,5],[5,5],[5,2],[2,2],[2,4]]
## Continuation in which X's last move (Center, cell 2) claims Center with its top row.
const CLAIM_TAIL = [[4,0],[0,0],[0,3],[3,4],[4,2]]
## Medium (X) vs Easy (O), seed 1: X's last move claims Bottom and wins on the middle column 1-4-7.
const WIN_GAME = [[4,4],[4,8],[8,4],[4,6],[6,2],[2,1],[1,2],[2,3],[3,6],[6,7],[7,0],[0,4],[4,7],[7,3],[3,8],[8,6],[6,0],[0,1],[1,8],[8,5],[5,2],[2,6],[6,1],[1,7],[7,8],[8,0],[0,7],[7,4],[4,1],[1,1],[1,5],[5,4],[3,7],[7,6],[2,0],[0,6],[7,2],[2,7],[7,5]]

class Layer extends Control:
	var painter: Callable
	func _draw():
		if painter.is_valid(): painter.call(self)

var game = Rules.new()
var settings = Store.new()
var ai = AI.new(19)
var hint_ai = AI.new(271)
var page: String = "title"
var overlay: String = ""
var mode: String = "computer"
var human_mark: int = 1
var clock: float = 0
var match_seconds: float = 0
var thinking: bool = false
var thinking_age: float = 0
var hint_busy: bool = false
var ai_seed: int = 719
var hinge_rect: Rect2 = Rect2()
var layout: Dictionary = {}
var board
var backdrop
var fx_overlay: Layer
var sound
var controls: Dictionary = {}
var ui_nodes: Array = []
var title_label: Label
var history_label: RichTextLabel
var message: String = ""
var turn_label: String = "Turn: X"
var active_label: String = "Active Board: Any"
var transport
var demo_rival
var room_code: String = ""
var _room_entry: String = ""
var online_state: String = "lobby"
var online_sequence: int = 0
var opponent_name: String = "Remote player"
var remote_ready: bool = false
var _result_shown: bool = false
var _result_t: float = 1.0
var _result_bases: Dictionary = {}
var _input_beat: float = 0
var _last_size = Vector2.ZERO
var _manual_size = Vector2.ZERO
var _resize_pending: bool = false
var _modal_rect: Rect2
var _debug_capture: bool = false
var _title: Dictionary = {}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.new(); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	board = Board.new(); board.game = game; board.cell_pressed.connect(play_cell); add_child(board)
	# Screen flash and fireworks: additive, above the board, below every UI control.
	fx_overlay = Layer.new(); fx_overlay.name = "FxOverlay"; fx_overlay.painter = _draw_fx_overlay
	fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; fx_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add = CanvasItemMaterial.new(); add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; fx_overlay.material = add
	add_child(fx_overlay)
	sound = Sound.new(); add_child(sound)
	title_label = Label.new(); title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font",P.DISPLAY)
	title_label.add_theme_color_override("font_outline_color",Color("1a0f05")); title_label.add_theme_constant_override("outline_size",7)
	title_label.add_theme_color_override("font_shadow_color",Color(0,0,0,.85)); title_label.add_theme_constant_override("shadow_offset_y",4)
	title_label.add_theme_constant_override("shadow_outline_size",9)
	var mat = ShaderMaterial.new(); mat.shader = preload("res://assets/shaders/gold.gdshader"); title_label.material = mat
	add_child(title_label)
	_apply_preferences(); _relayout(); _rebuild()
	get_viewport().size_changed.connect(_on_viewport_resize)
func _on_viewport_resize():
	if _manual_size != Vector2.ZERO: return
	_resize_pending = true
func set_view_size(physical: Vector2):
	_manual_size = physical
	var logical = Layout.logical_size(physical)
	get_window().content_scale_size = Vector2i(logical)
	# Explicit sizing: drop the full-rect anchors first so Control never warns about set_size.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO; size = logical
	_relayout(); _rebuild()
func set_hinge_rect(rect: Rect2):
	hinge_rect = rect; _relayout(); _rebuild()
func _relayout():
	var physical = _manual_size if _manual_size != Vector2.ZERO else Vector2(get_window().size)
	var logical = Layout.logical_size(physical)
	if OS.has_feature("web") and _manual_size == Vector2.ZERO:
		var css = Vector2(float(JavaScriptBridge.eval("window.innerWidth")),float(JavaScriptBridge.eval("window.innerHeight")))
		if css.x > 0 and css.y > 0: logical = css
	if get_window().content_scale_size != Vector2i(logical): get_window().content_scale_size = Vector2i(logical)
	layout = Layout.compute(logical,hinge_rect)
	layout.scale = physical.x/logical.x
	_last_size = logical
	board.place(layout.board)
	_title = _title_geometry()
	backdrop.title_anchor = _title.anchor; backdrop.title_region = _title.region
	var fs: int = _title.font_size
	title_label.text = "NINEWEAVE"; title_label.add_theme_font_size_override("font_size",fs)
	title_label.position = _title.label.position; title_label.size = _title.label.size
	var font_h = P.DISPLAY.get_height(fs); var ascent = P.DISPLAY.get_ascent(fs)
	var line_top = (_title.label.size.y-font_h)*.5
	title_label.material.set_shader_parameter("band_top",line_top+ascent-fs*.74)
	title_label.material.set_shader_parameter("band_height",fs*.78)
## Title composition, matching the art: crystal crown, NINEWEAVE, framed ribbon, then menu.
func _title_geometry() -> Dictionary:
	var s: Vector2 = layout.size
	var hinge = layout.hinge.size.x > 0
	var region = Rect2(0,0,layout.hinge.position.x,s.y) if hinge else Rect2(Vector2.ZERO,s)
	var landscape = s.x > s.y and not hinge
	var fs: float; var title_y: float
	if hinge:
		fs = clampf(region.size.x*.11,26,68); title_y = s.y*.36
	elif landscape:
		fs = clampf(minf(s.y*.12,s.x*.065),30,84); title_y = s.y*.24
	else:
		fs = clampf(s.x*.125,34,84); title_y = s.y*.175
	fs = minf(fs,region.size.x*.86/6.6)
	var crown = fs*.44
	title_y = maxf(title_y,fs*.62+crown*2.3+6)
	var cx = region.get_center().x
	var g = {"region":region,"landscape":landscape,"hinge":hinge,"font_size":int(fs)}
	g.anchor = Vector2(cx,title_y)
	g.crown = Vector2(cx,title_y-fs*.62-crown*1.05); g.crown_size = crown
	g.label = Rect2(region.position.x,title_y-fs*.75,region.size.x,fs*1.5)
	var rh = clampf(fs*.6,26,44)
	g.ribbon = Rect2(cx-minf(region.size.x*.78,fs*5.8)*.5,title_y+fs*.6,minf(region.size.x*.78,fs*5.8),rh)
	g.tagline = Rect2(region.position.x+16,g.ribbon.end.y+6,region.size.x-32,22)
	return g
func _apply_preferences():
	board.reduced_motion = bool(settings.values.reduced_motion)
	backdrop.reduced_motion = bool(settings.values.reduced_motion)
	sound.enabled = bool(settings.values.sound)
func _process(delta):
	if _resize_pending and not get_viewport().gui_get_focus_owner() is LineEdit:
		_resize_pending = false; _relayout(); _rebuild()
	clock += delta
	P.clock = clock
	_input_beat = maxf(0,_input_beat-delta)
	if page == "game" and overlay.is_empty() and game.status == 0 and not _debug_capture: match_seconds += delta
	if thinking and overlay.is_empty() and not _debug_capture:
		thinking_age += delta
		ai.step(4500)
		if ai.done and thinking_age >= .38:
			thinking = false
			var m = ai.best_move
			if mode == "online" and demo_rival != null:
				demo_rival.send_move(m.x,m.y,online_sequence+1)
			elif mode == "computer": _apply_move(m.x,m.y)
	if hint_busy:
		hint_ai.step(3500)
		if hint_ai.done: hint_busy = false; board.hint_move = hint_ai.best_move
	if page == "game" and game.status != 0 and not board.win_fx.is_empty() and board.win_progress() >= RESULT_AT and not _result_shown:
		_result_shown = true; overlay = "result"; _rebuild()
	_sync_fx()
	queue_redraw()
## Effects that depend on the board's animation clock: statue glow, result panel entrance.
func _sync_fx():
	if board.win_fx.is_empty():
		backdrop.win_player = 0; backdrop.win_glow = 0; _result_t = 1.0
	else:
		var p = board.win_progress()
		backdrop.win_player = int(board.win_fx.player) if board.win_fx.player in [1,2] else 0
		backdrop.win_glow = clampf(p*3,0,1)*(.75+.25*sin(clock*4))
		_result_t = clampf((p-RESULT_AT)/.2,0,1)
	if overlay == "result": _apply_result_anim()
	if fx_overlay: fx_overlay.queue_redraw()
func _apply_result_anim():
	var e = Board.back_out(_result_t)
	for id in _result_bases:
		if controls.has(id) and is_instance_valid(controls[id]):
			controls[id].position = _result_bases[id]+Vector2(0,(1-e)*60)
			controls[id].modulate.a = clampf(_result_t*1.4,0,1)
func start_game(new_mode: String = "computer", mark: int = 1):
	_leave_online()
	mode = new_mode; human_mark = mark; page = "game"; overlay = ""; _debug_capture = false
	game.new_game(); board.game = game; board.clear_effects(); board.hint_move = Vector2i(-1,-1)
	thinking = false; hint_busy = false; _result_shown = false; match_seconds = 0; message = ""; online_sequence = 0
	_refresh_labels(); _rebuild(); _schedule_ai()
func _schedule_ai():
	if _debug_capture or game.status != 0 or not overlay.is_empty(): return
	var should = mode == "computer" and game.turn != human_mark
	should = should or (mode == "online" and demo_rival != null and remote_ready and game.turn != human_mark)
	if should:
		thinking = true; thinking_age = 0
		ai.begin(game,str(settings.values.difficulty),ai_seed+game.history.size()*17)
func play_cell(b: int, c: int) -> bool:
	if page != "game" or not overlay.is_empty() or thinking or game.status != 0 or _input_beat > 0: return false
	if mode == "computer" and game.turn != human_mark: return false
	if mode == "online":
		if not remote_ready or game.turn != human_mark or not game.is_legal(b,c): _invalid(b); return false
		transport.send_move(b,c,online_sequence+1); return true
	return _apply_move(b,c)
func _apply_move(b: int, c: int) -> bool:
	var before: int = game.owners[b] if b >= 0 and b < 9 else 0
	if not game.play(b,c): _invalid(b); return false
	message = ""
	board.notify_move(b,c); sound.cue("move")
	if before == 0 and game.owners[b] != 0:
		board.start_claim(b,game.owners[b]); sound.cue("claim"); _input_beat = .16 if not board.reduced_motion else .05
	if game.status != 0:
		var line = game.big_lines[0] if not game.big_lines.is_empty() else []
		board.start_win(line,game.status); sound.cue("win"); thinking = false
	_refresh_labels(); _save_match(); _refresh_history(); _schedule_ai()
	return true
func _invalid(b: int):
	board.invalid_board = b; board.invalid_age = 0; message = "Choose an empty cell in the glowing board."
func _refresh_labels():
	turn_label = "Turn: "+("X" if game.turn == 1 else "O")
	active_label = "Active Board: "+("Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board])
	if game.status != 0:
		turn_label = "Draw" if game.status == 3 else ("X" if game.status == 1 else "O")+" wins"
		active_label = result_line()
func side_name(mark: int) -> String:
	if mark == human_mark and mode != "local": return str(settings.values.player_name)
	if mode == "local": return "Player "+("X" if mark == 1 else "O")
	return _rival_name()
## One-line result for the info pill / panels after game over.
func result_line() -> String:
	if game.status == 3: return "Draw — all boards sealed"
	if game.status == 0: return ""
	var mark = "X" if game.status == 1 else "O"
	if mode == "computer": return ("Victory! "+mark+" wins the game") if game.status == human_mark else "Rival AI wins the game"
	if mode == "online": return ("Victory! "+mark+" wins the game") if game.status == human_mark else _rival_name()+" wins the game"
	return mark+" wins the game"
func info_lines() -> Array:
	if game.status != 0:
		var detail = "Nine boards woven. Play again?" if game.status == 3 else "Three boards in a row."
		return [result_line(),detail]
	var board_name = "Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
	var tail = "in any open board." if game.active_board == -1 else "in this 3×3 board."
	return ["Active Board: "+board_name,"Play your "+("X" if game.turn == 1 else "O")+" "+tail]
func undo_move() -> bool:
	if mode == "online": message = "Online moves are final. Start another room to play again."; return false
	thinking = false; hint_busy = false
	var did = game.undo()
	if mode == "computer" and did and game.turn != human_mark and not game.history.is_empty(): game.undo()
	board.clear_effects(); board.hint_move = Vector2i(-1,-1); _result_shown = false; overlay = ""; _input_beat = 0
	_refresh_labels(); _save_match(); _rebuild(); _schedule_ai()
	return did
func request_hint():
	if game.status != 0 or thinking or not settings.values.show_hints: return
	if mode == "online": message = "Hints are disabled in online games."; return
	hint_ai.begin(game,"Hard",444+game.history.size()); hint_busy = true
func _save_match():
	if mode == "computer" and page == "game" and not _debug_capture:
		settings.saved_game = {"state":game.serialize(),"human":human_mark,"seconds":match_seconds} if game.status == 0 else {}
		settings.save()
func resume_game():
	if settings.saved_game.is_empty(): return
	if not game.deserialize(settings.saved_game.state): settings.saved_game = {}; return
	mode = "computer"; _debug_capture = false; human_mark = int(settings.saved_game.human); match_seconds = float(settings.saved_game.get("seconds",0))
	page = "game"; overlay = ""; board.clear_effects(); _result_shown = false
	_refresh_labels(); _rebuild(); _schedule_ai()
func go_home():
	_save_match(); _leave_online(); thinking = false; page = "title"; overlay = ""; board.clear_effects(); _rebuild()
func show_settings(): overlay = "settings"; thinking = false; _rebuild()
func _close_overlay():
	overlay = ""; _rebuild(); _schedule_ai()
func _leave_online():
	if is_instance_valid(demo_rival): demo_rival.leave(); demo_rival.queue_free()
	if is_instance_valid(transport): transport.leave(); transport.queue_free()
	demo_rival = null; transport = null; remote_ready = false
func open_online():
	_leave_online(); page = "online"; overlay = ""; online_state = "lobby"; message = ""; room_code = ""; _rebuild()
func _attach_transport(t):
	_leave_online(); transport = t; add_child(t)
	t.player_name = str(settings.values.player_name)
	t.room_created.connect(func(code): room_code = code; online_state = "waiting"; message = "Waiting for opponent…"; _rebuild())
	t.joined.connect(func(code,seat): room_code = code; human_mark = seat)
	t.opponent_joined.connect(_online_ready)
	t.move_received.connect(_receive_move)
	t.state_received.connect(_receive_state)
	t.opponent_left.connect(func(): remote_ready = false; thinking = false; message = "Your opponent has left the room."; _rebuild())
	t.error.connect(func(msg): message = msg; _rebuild())
func create_online(demo: bool = false):
	_attach_transport(Loopback.new() if demo else HTTP.new())
	transport.create_room()
func join_online(code: String, demo: bool = false):
	_attach_transport(Loopback.new() if demo else HTTP.new())
	transport.join_room(code)
func invite_demo_rival():
	if not transport is Loopback: return
	demo_rival = Loopback.new(); demo_rival.player_name = "Crystal Knight · Demo"; add_child(demo_rival)
	demo_rival.join_room(room_code)
func _online_ready():
	remote_ready = true; opponent_name = transport.remote_name
	game.new_game(); mode = "online"; page = "game"; overlay = ""; online_sequence = 0
	board.clear_effects(); thinking = false; _result_shown = false; match_seconds = 0; message = ""
	_refresh_labels(); _rebuild()
func _receive_move(b: int, c: int, seq: int):
	if seq <= online_sequence: return
	if seq != online_sequence+1: message = "Resynchronizing room…"; return
	if _apply_move(b,c): online_sequence = seq
func _receive_state(state: Dictionary, seq: int):
	if seq == online_sequence and state.get("cells","") == game.serialize().cells: return
	if game.deserialize(state):
		online_sequence = seq; board.clear_effects(); _refresh_labels(); _refresh_history(); _schedule_ai()

func _clear_nodes():
	for n in ui_nodes:
		if is_instance_valid(n): remove_child(n); n.queue_free()
	ui_nodes.clear(); controls.clear(); history_label = null; _result_bases.clear()
func _button(id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false, icon: String = ""):
	var b = OrnateButton.new(); b.name = id; b.caption = caption; b.tooltip_text = caption if not caption.is_empty() else id.capitalize()
	b.icon_kind = icon
	b.position = rect.position; b.size = rect.size; b.accent = accent
	b.font_size = int(clampf(rect.size.y*.4,17,26))
	b.pressed.connect(callback); add_child(b); ui_nodes.append(b); controls[id] = b
	return b
func _field(id: String, placeholder: String, rect: Rect2, value: String = ""):
	var e = LineEdit.new(); e.name = id; e.placeholder_text = placeholder; e.text = value
	e.position = rect.position; e.size = rect.size; e.add_theme_font_override("font",P.SANS); e.add_theme_font_size_override("font_size",22)
	e.add_theme_color_override("font_color",P.PALE); e.add_theme_color_override("caret_color",P.BLUE)
	var style = StyleBoxFlat.new(); style.bg_color = Color("041425"); style.border_color = P.GOLD
	style.set_border_width_all(2); style.set_corner_radius_all(6); style.content_margin_left = 12
	e.add_theme_stylebox_override("normal",style); e.add_theme_stylebox_override("focus",style)
	e.text_submitted.connect(func(_value): e.release_focus())
	add_child(e); ui_nodes.append(e); controls[id] = e
	return e
func _u() -> float:
	if layout.mode == "landscape": return clampf(layout.size.y/700.0,1,1.5)
	if layout.mode == "tablet_portrait": return 1.25
	return 1.0
func _rebuild():
	if not is_instance_valid(board): return
	_clear_nodes()
	board.visible = page == "game"
	board.mouse_filter = Control.MOUSE_FILTER_STOP if overlay.is_empty() else Control.MOUSE_FILTER_IGNORE
	backdrop.title_mode = page != "game"
	title_label.visible = page == "title"
	var s: Vector2 = layout.size
	if page == "title": _title_controls(s)
	elif page == "game":
		var hdr: Rect2 = layout.header
		var big = layout.mode == "landscape"
		var hb = 52.0 if big else 44.0
		_button("home","" if not big else "",Rect2(hdr.position,Vector2(hb,hb)),go_home,false,"home" if big else "back")
		_button("settings","⚙",Rect2(Vector2(hdr.end.x-hb,hdr.position.y),Vector2(hb,hb)),show_settings)
		var cr: Rect2 = layout.controls
		if layout.mode in ["phone_portrait","tablet_portrait"]:
			var unit = minf(cr.size.x/4-9,84 if layout.mode == "tablet_portrait" else 72)
			_button("undo","Undo",Rect2(cr.position,Vector2(unit,cr.size.y)),undo_move,false,"undo")
			_button("hint","Hint",Rect2(cr.end-Vector2(unit,cr.size.y),Vector2(unit,cr.size.y)),request_hint,false,"hint")
		else:
			_button("undo","Undo",Rect2(cr.position,Vector2(cr.size.x*.48,cr.size.y)),undo_move,false,"undo")
			_button("hint","Hint",Rect2(cr.position+Vector2(cr.size.x*.52,0),Vector2(cr.size.x*.48,cr.size.y)),request_hint,false,"hint")
		controls.undo.disabled = mode == "online"
		controls.hint.disabled = mode == "online" or not settings.values.show_hints
		if layout.has("history"): _create_history(layout.history)
	elif page == "online": _online_controls(s)
	if not overlay.is_empty(): _overlay_controls(s)
	queue_redraw()
func _title_controls(s: Vector2):
	var items = [["computer","Play vs Computer",func(): overlay = "setup"; _rebuild(),true],["online","Play Online",open_online,false],["local","Pass & Play",func(): start_game("local"),false]]
	if not settings.saved_game.is_empty(): items.append(["resume","Resume Journey",resume_game,false])
	var bh = clampf(s.y*.064,44,58)
	if _title.hinge:
		var menu_x = layout.hinge.end.x+12; var bw = minf(320,s.x-menu_x-12)
		var gap = bh+10
		var y = (s.y-(gap*(items.size()+1)))/2
		for item in items:
			_button(item[0],item[1],Rect2(menu_x,y,bw,bh),item[2],item[3]); y += gap
		_button("settings","Settings",Rect2(menu_x,y,bw*.48,44),show_settings)
		_button("how","How to Play",Rect2(menu_x+bw*.52,y,bw*.48,44),func(): overlay = "how"; _rebuild())
	elif _title.landscape:
		bh = clampf(s.y*.12,44,58)
		var bw = minf(310,(s.x-40)*.36); var gap = bh+(8 if s.y < 420 else 14)
		items.append(["settings","Settings",show_settings,false])
		items.append(["how","How to Play",func(): overlay = "how"; _rebuild(),false])
		var y = maxf(_title.tagline.end.y+(8 if s.y < 420 else 12),s.y*.4 if s.y >= 420 else 0)
		for i in range(items.size()):
			var item = items[i]
			var x = s.x*.5-bw-6 if i%2 == 0 else s.x*.5+6
			_button(item[0],item[1],Rect2(x,y+int(i/2)*gap,bw,bh),item[2],item[3])
	else:
		var bw = minf(330,s.x-64); var gap = bh+10
		var y = maxf(s.y*.47,_title.tagline.end.y+s.y*.14)
		var x = (s.x-bw)/2
		for item in items:
			_button(item[0],item[1],Rect2(x,y,bw,bh),item[2],item[3]); y += gap
		_button("settings","Settings",Rect2(x,y,bw*.48,44),show_settings)
		_button("how","How to Play",Rect2(x+bw*.52,y,bw*.48,44),func(): overlay = "how"; _rebuild())
func _create_history(rect: Rect2):
	history_label = RichTextLabel.new(); history_label.position = rect.position+Vector2(10,24); history_label.size = rect.size-Vector2(20,30)
	history_label.add_theme_font_override("normal_font",P.SANS); history_label.add_theme_font_size_override("normal_font_size",15)
	history_label.add_theme_color_override("default_color",P.WHITE); history_label.scroll_following = true
	add_child(history_label); ui_nodes.append(history_label); _refresh_history()
func _refresh_history():
	if not is_instance_valid(history_label): return
	var lines: Array = []
	for i in range(game.history.size()):
		var m = game.history[i]
		# Named sides avoid the ambiguous "O 0" glyph pairing in Rajdhani.
		lines.append("%d. %s → %s · %s" % [i+1,"Crystal X" if m.player == 1 else "Gold O",Rules.BOARD_NAMES[m.board],Rules.BOARD_NAMES[m.cell]])
	history_label.text = "\n".join(lines) if not lines.is_empty() else "Your story begins here."
func _online_controls(s: Vector2):
	var short = (s.x > s.y and s.y < 500) or hinge_rect.size.x > 0
	var pw = s.x*.44 if short else minf(460,s.x-32); var x = s.x*.53 if short else (s.x-pw)/2
	_button("back","Menu",Rect2(16,16,110,44),go_home,false,"back")
	var y = 64.0 if short else maxf(140,s.y*.3)
	if online_state == "waiting":
		_button("copy","Copy code",Rect2(x+24,y+(124 if short else 150),pw-48,44 if short else 48),func(): DisplayServer.clipboard_set(room_code); message = "Room code copied")
		if transport is Loopback: _button("demo_join","Invite demo rival",Rect2(x+24,y+(180 if short else 210),pw-48,44 if short else 48),invite_demo_rival,true)
		_button("cancel","Leave room",Rect2(20,s.y-60,minf(200,s.x*.42),44) if short else Rect2(x+24,y+270,pw-48,44),open_online)
	else:
		_button("create","Create Room",Rect2(x+24,y,pw-48,50),func(): create_online(false),true)
		var field = _field("room_code","Enter 5-character code",Rect2(x+24,y+(62 if short else 70),pw-48,48),_room_entry)
		field.max_length = 5
		field.text_changed.connect(func(value): _room_entry = value)
		field.text_submitted.connect(func(value): join_online(value))
		_button("join","Join Room",Rect2(x+24,y+(120 if short else 130),pw-48,48),func(): join_online(str(controls.room_code.text)))
		_button("demo","Try Local Online Demo",Rect2(x+24,y+(180 if short else 200),pw-48,48),func(): create_online(true))
func _overlay_controls(s: Vector2):
	for item in controls.values():
		item.release_focus(); item.focus_mode = Control.FOCUS_NONE
	# An actual input shield prevents taps from reaching controls beneath a modal.
	var shield = Control.new(); shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(shield); ui_nodes.append(shield)
	var short = s.x > s.y and s.y < 500
	var pw = minf(740 if short else 480,s.x-28); var ph = minf(600,s.y-24)
	if overlay == "setup": ph = minf(410,s.y-24)
	if overlay == "result": pw = minf(pw,460); ph = minf(340,s.y-24)
	_modal_rect = Rect2((s.x-pw)/2,(s.y-ph)/2,pw,ph)
	if layout.hinge.size.x > 0:
		pw = minf(pw,s.x-layout.hinge.end.x-24)
		_modal_rect = Rect2(layout.hinge.end.x+12,(s.y-ph)/2,pw,ph)
	# Modal painting belongs above the shield and all underlay controls.
	var painter = Control.new(); painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE; painter.draw.connect(_draw_modal.bind(painter)); add_child(painter); ui_nodes.append(painter)
	var r = _modal_rect
	if overlay != "result": _button("close","×",Rect2(r.end.x-56,r.position.y+10,44,44),_close_overlay)
	if overlay == "setup":
		var y = r.position.y+(76 if short else 94); var step = (pw-56)/3
		for i in range(3):
			var level = ["Easy","Medium","Hard"][i]
			_button("difficulty_"+level,level,Rect2(r.position.x+20+i*step,y,step-8,48),func(): settings.set_value("difficulty",level); _rebuild(),settings.values.difficulty == level)
		_button("choose_x","Play first",Rect2(r.position.x+24,y+(60 if short else 88),pw-48,48 if short else 56),func(): start_game("computer",1),true,"x")
		_button("choose_o","Play second",Rect2(r.position.x+24,y+(118 if short else 156),pw-48,48 if short else 56),func(): start_game("computer",2),false,"o")
	elif overlay == "settings":
		var y = r.position.y+74
		var sw = (pw-72)*.5 if short else pw-48
		var right_x = r.position.x+pw*.5+12 if short else r.position.x+24
		var rows = [["sound","Sound"],["reduced_motion","Reduced motion"],["show_hints","Show hints"]]
		for pair in rows:
			var key = pair[0]; var caption = pair[1]
			_button("toggle_"+key,caption+"    "+("ON" if settings.values[key] else "OFF"),Rect2(r.position.x+24,y,sw,46),func(): settings.set_value(key,not settings.values[key]); _apply_preferences(); _rebuild(),settings.values[key])
			y += 56
		if short: y = r.position.y+74
		_button("difficulty","AI difficulty: "+str(settings.values.difficulty),Rect2(right_x,y,sw,46),func():
			var levels = ["Easy","Medium","Hard"]; settings.set_value("difficulty",levels[(levels.find(settings.values.difficulty)+1)%3]); _rebuild())
		y += 76
		var name_field = _field("player_name","Player name",Rect2(right_x,y,sw,46),str(settings.values.player_name))
		name_field.max_length = 24
		name_field.text_changed.connect(func(value): settings.set_value("player_name",value.strip_edges().left(24)))
		_button("done","Return to the stars",Rect2(right_x,r.end.y-70,sw,48),_close_overlay,true)
	elif overlay == "how":
		_button("done","I’m ready",Rect2(r.position.x+24,r.end.y-70,pw-48,48),_close_overlay,true)
	elif overlay == "result":
		_button("again","Play Again",Rect2(r.position.x+26,r.end.y-122,pw-52,50),func():
			if mode == "online": open_online()
			else: start_game(mode,human_mark),true)
		_button("menu","Menu",Rect2(r.position.x+26,r.end.y-62,pw-52,44),go_home,false,"home")
		for id in ["again","menu"]: _result_bases[id] = controls[id].position
		_apply_result_anim()

# ------------------------------------------------------------------ drawing
func _draw():
	if layout.is_empty(): return
	if page == "title": _draw_title()
	elif page == "game": _draw_game()
	elif page == "online": _draw_online()
	if hinge_rect.size.x > 0:
		var seam: Rect2 = layout.hinge
		draw_rect(seam,Color("01040b")); draw_line(seam.position,seam.position+Vector2(0,seam.size.y),Color(.4,.3,.15,.5),1)
func _draw_title():
	var s: Vector2 = layout.size; var g = _title
	var fs: float = g.font_size
	var tw = P.DISPLAY.get_string_size("NINEWEAVE",HORIZONTAL_ALIGNMENT_LEFT,-1,int(fs)).x
	# Warm bloom behind the lettering, cool glow behind the crown.
	P.halo_rect(self,Rect2(g.anchor.x-tw*.68,g.anchor.y-fs*1.1,tw*1.36,fs*2.2),Color(1,.72,.3,.34))
	P.halo_rect(self,Rect2(g.anchor.x-tw*.55,g.anchor.y-fs*.6,tw*1.1,fs*1.2),Color(0,0,0,.35))
	P.title_crown(self,g.crown,g.crown_size)
	_draw_ribbon(g.ribbon,"T I C   T A C   T O E")
	P.text(self,"NINE BOARDS. ONE DESTINY.",g.tagline,int(clampf(fs*.3,12,20)),P.WHITE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.5)
	if s.y >= 420:
		var foot_w = (layout.hinge.position.x if layout.hinge.size.x > 0 else s.x)-40
		P.text(self,"A CELESTIAL GAME OF STRATEGY",Rect2(20,s.y-30,foot_w,20),12,P.GOLD,P.SERIF)
## Dark gold-framed ribbon plate with pointed ends and jewelled rails, as under the art's logo.
func _draw_ribbon(r: Rect2, caption: String):
	var cy = r.get_center().y; var tip = r.size.y*.5
	for side in [-1.0,1.0]:
		var edge = r.position.x if side < 0 else r.end.x
		var a = Vector2(edge+side*tip*.4,cy); var b = Vector2(edge+side*minf(tip*3.2,r.size.x*.22),cy)
		draw_line(a,b,P.gold_ramp(.7),2,true)
		draw_line(a+Vector2(0,-1),b+Vector2(0,-1),Color(1,.95,.8,.5),1,true)
		P.diamond(self,b,4.5,P.gold_ramp(.8)); P.diamond(self,b,2,P.BLUE)
	var pts = PackedVector2Array([Vector2(r.position.x+tip,r.position.y),Vector2(r.end.x-tip,r.position.y),Vector2(r.end.x,cy),Vector2(r.end.x-tip,r.end.y),Vector2(r.position.x+tip,r.end.y),Vector2(r.position.x,cy)])
	draw_colored_polygon(pts,Color(.01,.03,.07,.95))
	draw_polygon(PackedVector2Array([pts[0],pts[1],Vector2(pts[1].x,cy),Vector2(pts[0].x,cy)]),PackedColorArray([Color(.2,.35,.55,.25),Color(.2,.35,.55,.25),Color(0,0,0,0),Color(0,0,0,0)]))
	var closed = pts.duplicate(); closed.append(pts[0])
	draw_polyline(closed,P.GOLD_DARK,5,true)
	draw_polyline(closed,P.gold_ramp(.62),2.6,true)
	var inner = PackedVector2Array()
	for p in closed: inner.append(r.get_center()+(p-r.get_center())*Vector2((r.size.x-8)/r.size.x,(r.size.y-8)/r.size.y))
	draw_polyline(inner,Color(P.GOLD,.55),1,true)
	P.glint(self,r,.8)
	P.text(self,caption,r.grow_individual(-tip,0,-tip,0),int(r.size.y*.56),P.PALE,P.SERIF)
func display_player() -> int:
	return game.status if game.status in [1,2] else game.turn
func _draw_game():
	var s: Vector2 = layout.size
	var u = _u()
	if not board.win_fx.is_empty(): _draw_victory_rays(board.win_progress(),int(board.win_fx.player))
	_draw_players(layout.players,layout.mode == "landscape")
	_draw_turn(layout.turn,u)
	_draw_info(layout.info,layout.mode == "landscape",u)
	if layout.has("minimap"): _draw_minimap(layout.minimap)
	if layout.has("stats"): _draw_stats(layout.stats)
	if layout.has("history"):
		P.panel(self,layout.history)
		P.text(self,"CHRONICLE",Rect2(layout.history.position+Vector2(0,4),Vector2(layout.history.size.x,18)),12,P.GOLD,P.SERIF)
	if layout.mode in ["phone_portrait","tablet_portrait"]:
		var cr: Rect2 = layout.controls
		var tile = minf(cr.size.y+8,84)
		for p in [1,2]:
			var x = cr.get_center().x+(p-1.5)*(tile+10)-tile/2
			var rr = Rect2(x,cr.position.y-4,tile,tile)
			var on = display_player() == p and game.status == 0
			if on: P.box_glow(self,rr,Color(P.mark_color(p),.35+.15*sin(clock*TAU/1.2)),12,10)
			P.panel(self,rr,on and p == 1,1,true)
			if on and p == 2: P.outline(self,rr.grow(-5),Color(1,.8,.35,.9),2)
			P.mark(self,rr.get_center(),tile*.3,p,1 if on or game.status != 0 else .55,1.3 if on else .8)
	if not message.is_empty():
		P.text(self,message,Rect2(16,s.y-20,s.x-32,18),12,P.GOLD)
	if hint_busy: P.text(self,"Reading the threads…",Rect2(layout.board.position.x,layout.board.end.y-22,layout.board.size.x,20),14,P.PALE)
func _draw_turn(r: Rect2, u: float):
	P.panel(self,r,false,1,r.size.y >= 34)
	var fs = int(clampf(r.size.y*.56,15,28)*minf(u,1.2))
	var icon_r = fs*.62
	var caption = "Turn:"
	var mark = game.turn
	if game.status == 3: caption = "Draw"; mark = 0
	elif game.status != 0: caption = "wins"; mark = game.status
	var tw = P.text_width(caption,fs,P.SERIF)
	var total = tw+(icon_r*2.4 if mark != 0 else 0)
	var x = r.get_center().x-total*.5
	if game.status in [1,2]:
		P.mark(self,Vector2(x+icon_r,r.get_center().y),icon_r,mark,1,1.4)
		P.text(self,caption,Rect2(x+icon_r*2.4,r.position.y,tw+8,r.size.y),fs,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_LEFT,.6)
	else:
		P.text(self,caption,Rect2(x,r.position.y,tw+8,r.size.y),fs,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_LEFT)
		if mark != 0: P.mark(self,Vector2(x+tw+icon_r*1.5,r.get_center().y),icon_r,mark,1,1.3)
	if r.size.x > 200:
		for side in [-1.0,1.0]:
			var y = r.get_center().y
			var a = Vector2(r.get_center().x+side*(total*.5+16),y); var b = Vector2(r.get_center().x+side*minf(total*.5+60,r.size.x*.46),y)
			if absf(b.x-a.x) > 8:
				draw_line(a,b,Color(P.GOLD,.7),1.2,true); P.diamond(self,b,3,P.GOLD)
func _draw_players(r: Rect2, vertical: bool):
	if vertical:
		var vs_h = 52.0*_u()
		var hh = (r.size.y-vs_h)*.5
		_draw_player(Rect2(r.position,Vector2(r.size.x,hh)),human_mark,side_name(human_mark),display_player() == human_mark,"vertical")
		P.text(self,"VS",Rect2(r.position.x,r.position.y+hh,r.size.x,vs_h),int(30*_u()),P.GOLD,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.8)
		_draw_player(Rect2(r.position.x,r.end.y-hh,r.size.x,hh),3-human_mark,side_name(3-human_mark),display_player() != human_mark,"vertical")
	else:
		var gap = minf(46,r.size.x*.12); var width = (r.size.x-gap)/2
		_draw_player(Rect2(r.position,Vector2(width,r.size.y)),human_mark,side_name(human_mark),display_player() == human_mark,"left")
		P.text(self,"VS",Rect2(r.position.x+width,r.position.y,gap,r.size.y),22,P.GOLD,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.8)
		_draw_player(Rect2(r.end.x-width,r.position.y,width,r.size.y),3-human_mark,side_name(3-human_mark),display_player() != human_mark,"right")
func _rival_name() -> String:
	if mode == "local": return "Player O" if human_mark == 1 else "Player X"
	if mode == "online": return opponent_name
	return "Rival AI"
func is_rival_ai_shown() -> bool: return page == "game" and mode == "computer"
func _rival_portrait(mark: int) -> Texture2D:
	return KNIGHT_PORTRAIT if mark == 1 else GODDESS_PORTRAIT
## Circular gold-framed medallion: portrait (rival) or bevelled mark, crown and thinking ring.
func _medallion(center: Vector2, radius: float, mark: int, portrait: bool, active: bool, rival_thinking: bool):
	var col = P.mark_color(mark)
	if active:
		P.halo(self,center,radius*1.9,Color(col,.28+.12*sin(clock*TAU/1.2)))
	draw_circle(center,radius,Color("020a16"))
	if portrait:
		var pr = radius*.86
		draw_texture_rect(_rival_portrait(mark),Rect2(center-Vector2.ONE*pr,Vector2.ONE*pr*2),false)
	else:
		P.halo(self,center,radius*.9,Color(col,.18))
		P.mark(self,center,radius*.62,mark,1,1.2)
	var w = maxf(2.5,radius*.13)
	draw_arc(center,radius,0,TAU,64,P.GOLD_DARK,w+2.5,true)
	draw_arc(center,radius,0,TAU,64,P.gold_ramp(.55),w,true)
	draw_arc(center,radius-w*.15,PI*.95,PI*1.75,32,Color(1,.96,.8,.85),w*.35,true)
	draw_arc(center,radius+w*.1,-PI*.05,PI*.7,32,Color(.25,.13,.02,.8),w*.35,true)
	draw_arc(center,radius-w*.5-1,0,TAU,64,Color(.05,.03,.01,.9),1,true)
	if active: draw_arc(center,radius+w*.5+1.5,0,TAU,64,Color(col.lightened(.2),.75),1.6,true)
	if rival_thinking:
		var a = clock*3.2
		draw_arc(center,radius+w+3,a,a+PI*.9,32,Color(P.BLUE,.95),2.4,true)
		P.halo(self,center+Vector2.from_angle(a+PI*.9)*(radius+w+3),6,Color(.6,.95,1,.9))
func _draw_player(r: Rect2, mark: int, caption: String, active: bool, style: String):
	var rival = mark != human_mark and mode != "local"
	var portrait = rival and mode == "computer"
	var rival_thinking = rival and thinking
	var col = P.mark_color(mark)
	if style == "vertical":
		P.panel(self,r,active,1,true)
		var u = _u()
		var radius = minf(r.size.x*.34,r.size.y*.25)
		var center = Vector2(r.get_center().x,r.position.y+r.size.y*.12+radius+14*u)
		_medallion(center,radius,mark,portrait,active,rival_thinking)
		if active: P.crown(self,center-Vector2(0,radius+12*u),.9*u)
		var name_y = center.y+radius+10
		var shown = "Thinking"+".".repeat(1+int(clock*3)%3) if rival_thinking else caption
		P.text(self,shown,Rect2(r.position.x+6,name_y,r.size.x-12,30*u),int(22*u),P.WHITE)
		var ir = 12*u
		P.mark(self,Vector2(r.get_center().x,name_y+30*u+ir+4),ir,mark)
		P.text(self,"%d claimed" % game.owners.count(mark),Rect2(r.position.x+6,name_y+30*u+ir*2+10,r.size.x-12,24*u),int(17*u),col if mark == 1 else P.PALE)
		return
	var radius = minf(r.size.y*.5,r.size.x*.24)
	var right = style == "right"
	var center = Vector2(r.end.x-radius*.82 if right else r.position.x+radius*.82,r.get_center().y)
	var body = r.grow_individual(-radius*.6 if not right else 0,0,-radius*.6 if right else 0,0)
	P.panel(self,body,active,1,r.size.y >= 40)
	var text_r = Rect2(body.position.x+(8 if right else radius*1.2),r.position.y+3,body.size.x-radius*1.2-8,r.size.y-6)
	var shown = "Thinking"+".".repeat(1+int(clock*3)%3) if rival_thinking else caption
	var align = HORIZONTAL_ALIGNMENT_CENTER
	P.text(self,shown,Rect2(text_r.position,Vector2(text_r.size.x,text_r.size.y*.52)),17 if r.size.y < 70 else 20,P.WHITE,P.SANS,align)
	var ir = clampf(r.size.y*.13,6,10)
	var line = "%d claimed" % game.owners.count(mark)
	var lfs = 14 if r.size.y < 70 else 16
	var lw = P.text_width(line,lfs)
	var lx = text_r.get_center().x-(lw+ir*2.6)*.5
	var ly = text_r.position.y+text_r.size.y*.74
	P.mark(self,Vector2(lx+ir,ly),ir,mark)
	P.text(self,line,Rect2(lx+ir*2.6,ly-10,lw+6,20),lfs,col if mark == 1 else P.PALE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	_medallion(center,radius,mark,portrait,active,rival_thinking)
	# Crown rides above the name, clear of the corner header buttons.
	if active: P.crown(self,Vector2(text_r.get_center().x,r.position.y+1),.5)
func _draw_info(r: Rect2, large: bool, u: float):
	P.panel(self,r,false,1,true)
	var lines = info_lines()
	var over = game.status != 0
	var board_name = "Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
	if large:
		var y = r.position.y+12*u
		if over:
			P.text(self,"Game Over",Rect2(r.position.x+6,y,r.size.x-12,28*u),int(22*u),P.WHITE)
			P.text(self,lines[0],Rect2(r.position.x+6,y+30*u,r.size.x-12,30*u),int(21*u),P.mark_color(game.status) if game.status != 3 else P.MUTED,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.7)
		else:
			P.text(self,"Active Board:",Rect2(r.position.x+6,y,r.size.x-12,28*u),int(22*u),P.WHITE)
			P.text(self,board_name,Rect2(r.position.x+6,y+30*u,r.size.x-12,30*u),int(25*u),P.BLUE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.7)
		var foot = 70*u
		var map_size = minf(r.size.x-48,r.size.y-(y-r.position.y)-74*u-foot)
		var map_y = y+74*u+(r.size.y-(y-r.position.y)-74*u-foot-map_size)*.5
		_draw_minimap(Rect2(r.get_center().x-map_size/2,map_y,map_size,map_size))
		var tail = lines[1] if over else "Play your "+("X" if game.turn == 1 else "O")+(" in this board." if game.active_board != -1 else " in any board.")
		var words = tail.split(" ")
		var half = int(ceil(words.size()*.5))
		var l1 = " ".join(words.slice(0,half)); var l2 = " ".join(words.slice(half))
		P.text(self,l1,Rect2(r.position.x+8,r.end.y-foot+6,r.size.x-16,26*u),int(19*u),P.WHITE)
		P.text(self,l2,Rect2(r.position.x+8,r.end.y-foot+6+28*u,r.size.x-16,26*u),int(19*u),P.WHITE)
		return
	var two = r.size.y >= 46
	var icon_s = minf(r.size.y*.32,16)
	var text_x = r.position.x+8
	if two and r.size.x > 260:
		P.icon(self,"info",Vector2(r.position.x+18+icon_s,r.get_center().y),icon_s,P.PALE)
		text_x = r.position.x+26+icon_s*2
	var tr = Rect2(text_x,r.position.y,r.end.x-text_x-8,r.size.y)
	if over:
		var col = P.mark_color(game.status) if game.status != 3 else P.MUTED
		P.text(self,lines[0],Rect2(tr.position+Vector2(0,2),Vector2(tr.size.x,tr.size.y*(.55 if two else 1.0)-2)),19 if two else 17,col,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.6)
		if two: P.text(self,lines[1],Rect2(tr.position+Vector2(0,tr.size.y*.53),Vector2(tr.size.x,tr.size.y*.42)),14,P.WHITE)
		return
	var head = "Active Board: "; var fs = 19 if two else 17
	var hw = P.text_width(head,fs); var bw = P.text_width(board_name,fs)
	var hy = Rect2(tr.position+Vector2(0,2),Vector2(tr.size.x,tr.size.y*(.55 if two else 1.0)-2))
	if hw+bw < tr.size.x-8:
		var x0 = hy.get_center().x-(hw+bw)*.5
		P.text(self,head,Rect2(x0,hy.position.y,hw+4,hy.size.y),fs,P.WHITE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		P.text(self,board_name,Rect2(x0+hw,hy.position.y,bw+6,hy.size.y),fs,P.BLUE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	else: P.text(self,lines[0],hy,fs,P.BLUE)
	if two: P.text(self,lines[1],Rect2(tr.position+Vector2(0,tr.size.y*.53),Vector2(tr.size.x,tr.size.y*.42)),14,P.WHITE)
## Per-board mini-map state: "active" (only while the game is live), "x"/"o" owner tint,
## "sealed" grey, otherwise "open". Nothing is active after game over.
func minimap_states() -> Array:
	var states: Array = []
	for b in range(9):
		var owner: int = game.owners[b]
		if owner == 1: states.append("x")
		elif owner == 2: states.append("o")
		elif owner == 3: states.append("sealed")
		elif game.status == 0 and (game.active_board == -1 or game.active_board == b): states.append("active")
		else: states.append("open")
	return states
## Mini 3x3 map: active board(s) only while playing, owners tinted, sealed grey, winning line drawn.
func _draw_minimap(r: Rect2):
	P.panel(self,r)
	var edge = minf(r.size.x,r.size.y)-14
	var origin = r.get_center()-Vector2.ONE*edge/2
	var pitch = edge/3
	var states = minimap_states()
	for b in range(9):
		var rr = Rect2(origin+Vector2(b%3,b/3)*pitch+Vector2.ONE,Vector2.ONE*(pitch-2))
		var owner: int = game.owners[b]
		var active: bool = states[b] == "active"
		var fill = Color("08182a")
		if active: fill = Color(.05,.45,.62,.9)
		elif states[b] in ["x","o"]: fill = Color(P.mark_color(owner).darkened(.55),.85)
		elif states[b] == "sealed": fill = Color(.22,.26,.3,.9)
		draw_rect(rr,fill)
		if pitch > 30:
			for i in [1,2]:
				draw_line(rr.position+Vector2(rr.size.x*i/3,2),rr.position+Vector2(rr.size.x*i/3,rr.size.y-2),Color(.5,.65,.8,.18),1)
				draw_line(rr.position+Vector2(2,rr.size.y*i/3),rr.position+Vector2(rr.size.x-2,rr.size.y*i/3),Color(.5,.65,.8,.18),1)
		draw_rect(rr,Color(P.BLUE,.95) if active else Color(.35,.47,.56,.6),false,1.5 if active else 1.0)
		if active: P.halo(self,rr.get_center(),pitch*.6,Color(P.BLUE,.25))
		if owner in [1,2]: P.mark(self,rr.get_center(),pitch*.3,owner)
		elif owner == 3: P.diamond(self,rr.get_center(),pitch*.16,P.MUTED)
	if game.status in [1,2] and not game.big_lines.is_empty():
		var line: Array = game.big_lines[0]
		var a = origin+Vector2(line[0]%3+.5,line[0]/3+.5)*pitch; var z = origin+Vector2(line[2]%3+.5,line[2]/3+.5)*pitch
		P.line_glow(self,a,z,P.mark_color(game.status),maxf(2,pitch*.08))
func _draw_stats(r: Rect2):
	P.panel(self,r)
	var elapsed = "%02d:%02d" % [int(match_seconds)/60,int(match_seconds)%60]
	var fs = 16
	var ir = clampf(r.size.y*.24,6,9)
	var parts = [[1,str(game.owners.count(1))],[2,str(game.owners.count(2))],[0,"%d moves" % game.history.size()],[0,elapsed]]
	var widths = []; var total = 0.0
	for part in parts:
		var w = P.text_width(part[1],fs)+(ir*2.4 if part[0] != 0 else 0)
		widths.append(w); total += w
	var gap = minf(22,(r.size.x-total-12)/3)
	var x = r.get_center().x-(total+gap*3)*.5
	for i in range(parts.size()):
		var part = parts[i]
		if part[0] != 0:
			P.mark(self,Vector2(x+ir,r.get_center().y),ir,part[0]); x += ir*2.4
		P.text(self,part[1],Rect2(x,r.position.y,widths[i]+6,r.size.y),fs,P.GOLD if part[0] == 0 else P.mark_color(part[0]),P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
		x += widths[i]-(ir*2.4 if part[0] != 0 else 0)+gap
		if i < parts.size()-1: P.diamond(self,Vector2(x-gap*.5,r.get_center().y),2.5,Color(P.GOLD,.7))
## Rotating light rays behind the board, filling the screen during the game win.
func _draw_victory_rays(p: float, player: int):
	var s: Vector2 = layout.size
	var center = layout.board.get_center()
	var color = P.mark_color(player) if player in [1,2] else P.MUTED
	var alpha = minf(1,p*5)*(.3+.06*sin(clock*3))
	var number = 12 if board.reduced_motion else 30
	var reach = s.length()
	for i in range(number):
		var angle = i*TAU/number+clock*.12
		var wdt = .05+.03*sin(i*1.7)
		var a = center+Vector2.from_angle(angle-wdt)*reach
		var b = center+Vector2.from_angle(angle+wdt)*reach
		draw_polygon(PackedVector2Array([center,a,b]),PackedColorArray([Color(color.lerp(Color.WHITE,.4),alpha),Color(color,0),Color(color,0)]))
	P.halo(self,center,layout.board.size.x*.9,Color(color,alpha*.8))
## Additive overlay: screen-wide flash, opening shockwave and full-screen fireworks.
func _draw_fx_overlay(n: Control):
	if page != "game": return
	var s: Vector2 = layout.size
	var flash: Color = board.screen_flash()
	if flash.a > .003: n.draw_rect(Rect2(Vector2.ZERO,s),flash)
	if board.win_fx.is_empty(): return
	var p = board.win_progress()
	var col = P.mark_color(board.win_fx.player) if board.win_fx.player in [1,2] else P.MUTED
	var center = layout.board.get_center()
	var q = Board.window(p,0,.35)
	if q > 0 and q < 1:
		var rad = s.length()*.6*Board.ease_out(q)
		n.draw_arc(center,rad,0,TAU,96,Color(col.lightened(.4),(1-q)*.8),maxf(2,24*(1-q)),true)
		n.draw_arc(center,rad*.8,0,TAU,96,Color(col,(1-q)*.35),maxf(2,40*(1-q)),true)
	var bursts = 2 if board.reduced_motion else FIREWORK_BURSTS
	var sparks = 16 if board.reduced_motion else FIREWORK_SPARKS
	for k in range(bursts):
		var t0 = .05+k*.1
		var bq = Board.window(p,t0,t0+.34)
		if bq <= 0 or bq >= 1: continue
		var origin = Vector2(s.x*(.12+Board.rnd(k,41)*.76),s.y*(.1+Board.rnd(k,43)*.6))
		var bc = [col,Color.WHITE.lerp(col,.4),P.GOLD.lightened(.2) if board.win_fx.player == 1 else P.BLUE][k%3]
		var reach = minf(s.x,s.y)*(.16+Board.rnd(k,47)*.12)
		if bq < .25: P.halo(n,origin,reach*.8*(bq/.25),Color(bc,.6*(1-bq/.25)))
		for i in range(sparks):
			var ang = i*TAU/sparks+Board.rnd(i,k)*.25
			var sp = reach*(.6+Board.rnd(i,k+5)*.5)
			var e = Board.ease_out(bq)
			var pos = origin+Vector2.from_angle(ang)*sp*e+Vector2(0,bq*bq*reach*.35)
			var tail = origin+Vector2.from_angle(ang)*sp*maxf(0,e-.14)+Vector2(0,bq*bq*reach*.3)
			var a = (1-bq)
			n.draw_line(tail,pos,Color(bc,a*.75),2,true)
			if i%4 == 0: P.halo(n,pos,5,Color(bc,a*.8))
func _draw_online():
	var s: Vector2 = layout.size
	var short = (s.x > s.y and s.y < 500) or hinge_rect.size.x > 0
	var title_w = s.x*.46 if short else s.x-40
	P.text(self,"THE CELESTIAL ARENA",Rect2(20,70,title_w,48),27,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.6)
	P.text(self,"A friend. Nine boards. One shared sky.",Rect2(20,118,title_w,30),17,P.WHITE)
	var pw = s.x*.44 if short else minf(460,s.x-32); var y = 64.0 if short else maxf(140,s.y*.3); var x = s.x*.53 if short else (s.x-pw)/2
	if online_state == "waiting":
		P.panel(self,Rect2(x+16,y-10,pw-32,142),true,1,true)
		P.text(self,room_code,Rect2(x+24,y+14,pw-48,56),44,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.8)
		P.text(self,"Waiting for opponent…",Rect2(x+24,y+78,pw-48,34),18,P.WHITE)
		P.crystal(self,Vector2(s.x*.5,y-48),18,P.BLUE,clock*.6)
	else:
		P.text(self,"ONLINE  ·  PRIVATE ROOMS",Rect2(x,y-34,pw,24),15,P.GOLD,P.SERIF)
	if transport is Loopback:
		P.text(self,"LOCAL DEMO · simulated remote opponent",Rect2(20,170 if short else y+330,title_w if short else s.x-40,28),14,P.BLUE)
	if not message.is_empty():
		var lines = message.replace(". Try ",".\nTry ")
		for i in lines.split("\n").size(): P.text(self,lines.split("\n")[i],Rect2(20,(202 if short else minf(s.y-76,y+370))+i*22,title_w if short else s.x-40,24),15,P.GOLD)
func _draw_modal(node: Control):
	var s: Vector2 = layout.size; var r = _modal_rect
	var short = s.x > s.y and s.y < 500
	if overlay == "result":
		_draw_result(node,r,short); return
	node.draw_rect(Rect2(Vector2.ZERO,s),Color(.001,.005,.015,.88))
	P.panel(node,r,false,1,true); P.outline(node,r.grow(-8),P.GOLD.darkened(.4),1)
	var heading = {"settings":"SETTINGS","setup":"CHOOSE YOUR PATH","how":"HOW TO PLAY"}.get(overlay,"")
	P.text(node,heading,Rect2(r.position+Vector2(20,23),Vector2(r.size.x-72,44)),25,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.6)
	if overlay == "setup":
		if not short: P.text(node,"Choose difficulty, then your sigil",Rect2(r.position+Vector2(20,65),Vector2(r.size.x-40,25)),17,P.MUTED)
		if not short: P.text(node,"X always weaves the first thread.",Rect2(r.position.x+20,r.end.y-48,r.size.x-40,24),16,P.GOLD)
	elif overlay == "settings":
		P.text(node,"PLAYER NAME",Rect2(r.position+Vector2(r.size.x*.5+12 if short else 24,126 if short else 294),Vector2((r.size.x-72)*.5 if short else r.size.x-48,24)),13,P.GOLD,P.SERIF)
		if not short: P.text(node,"Preferences saved on this device.",Rect2(r.position.x+24,r.end.y-104,r.size.x-48,24),14,P.MUTED)
	elif overlay == "how":
		var items = ["01   Win three cells to claim a small board.","02   Your cell sends your rival to that board.","03   A closed target means a free choice.","04   Claim three boards in a row to win.","05   All boards closed, no line? A draw."]
		var y = r.position.y+(68 if short else 92)
		for item in items:
			P.text(node,item,Rect2(r.position.x+22,y,r.size.x-44,28 if short else 42),19,P.WHITE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
			y += 30 if short else minf(65,(r.size.y-190)/5)
		if not short: P.text(node,"Follow the cyan frame. Think one board ahead.",Rect2(r.position.x+20,r.end.y-115,r.size.x-40,28),16,P.BLUE)
## Ornate VICTORY / DEFEAT / X WINS / O WINS / DRAW panel; scales and slides in with overshoot.
func _draw_result(node: Control, r: Rect2, short: bool):
	var s: Vector2 = layout.size
	var t = _result_t; var e = Board.back_out(t)
	node.draw_rect(Rect2(Vector2.ZERO,s),Color(.001,.005,.015,.55*clampf(t*1.5,0,1)))
	if t <= 0: return
	var sc = lerpf(.82,1.0,e)
	var c = r.get_center()
	node.draw_set_transform(c*(1-sc)+Vector2(0,(1-e)*60),0,Vector2.ONE*sc)
	var col = P.mark_color(game.status) if game.status in [1,2] else P.MUTED
	var a = clampf(t*1.4,0,1)
	P.box_glow(node,r,Color(col,.45*a),28,14)
	P.panel(node,r,false,a,true); P.outline(node,r.grow(-9),Color(P.GOLD.darkened(.35),a),1)
	var title = _victory_title()
	var fs = 40 if not short else 34
	P.text(node,title,Rect2(r.position+Vector2(16,16),Vector2(r.size.x-32,54)),fs,Color(col.lightened(.35) if game.status != 3 else P.PALE,a),P.DISPLAY,HORIZONTAL_ALIGNMENT_CENTER,1.4)
	var ec = Vector2(c.x,r.position.y+108)
	P.halo(node,ec,70,Color(col,.35*a))
	if game.status == 3: P.crystal(node,ec,34,P.MUTED)
	else: P.mark(node,ec,30,game.status,a,2)
	for side in [-1.0,1.0]:
		node.draw_line(ec+Vector2(side*48,0),ec+Vector2(side*minf(150,r.size.x*.36),0),Color(P.GOLD,.7*a),1.4,true)
		P.diamond(node,ec+Vector2(side*minf(150,r.size.x*.36),0),4,Color(P.GOLD,a))
	P.text(node,result_line(),Rect2(r.position.x+20,r.position.y+148,r.size.x-40,28),18,Color(P.WHITE,a))
	node.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
func _victory_title() -> String:
	if game.status == 3: return "DRAW"
	if mode == "local": return ("X" if game.status == 1 else "O")+" WINS"
	return "VICTORY" if game.status == human_mark else "DEFEAT"

# Debug-only deterministic hooks. Preview hooks never alter rules state.
func debug_preview_claim(board_index: int, player: int, progress: float):
	if OS.is_debug_build(): board.preview_claim(board_index,player,progress); _sync_fx()
func debug_preview_win(line: Array, player: int, progress: float):
	if not OS.is_debug_build(): return
	board.preview_win(line,player,progress)
	if progress >= RESULT_AT and game.status != 0 and page == "game":
		_result_shown = true; overlay = "result"; _rebuild()
	_sync_fx()
func debug_load_position(serialized, as_mode: String = "computer") -> bool:
	if not OS.is_debug_build(): return false
	thinking = false; hint_busy = false; _input_beat = 0; _debug_capture = true
	if not game.deserialize(serialized): return false
	page = "game"; mode = as_mode; human_mark = 1; overlay = ""; board.clear_effects(); _result_shown = false
	_refresh_labels(); _rebuild(); return true
func debug_simulate_hinge(width: float = 22):
	if OS.is_debug_build(): set_hinge_rect(Rect2((layout.size.x-width)/2,0,width,layout.size.y))
## Replays `moves` minus the last one, loads that, then plays the last move for real so the
## claimed board's marks and the game's winning line are genuine.
func _debug_stage(moves: Array) -> Vector2i:
	var staged = Rules.new()
	for i in range(moves.size()-1): staged.play(moves[i][0],moves[i][1])
	debug_load_position(staged.serialize())
	var last: Array = moves[moves.size()-1]
	game.play(last[0],last[1])
	_refresh_labels(); _rebuild()
	return Vector2i(last[0],last[1])
func debug_scenario(scenario: String, progress: float = .45):
	if not OS.is_debug_build(): return
	_debug_capture = true; clock = 4; backdrop.clock = 4; P.clock = 4
	if scenario == "title": page = "title"; overlay = ""; board.clear_effects(); _rebuild(); return
	if scenario == "online":
		open_online(); create_online(true); return
	if scenario in ["claim","claim_end"]:
		var m = _debug_stage(MIDGAME+CLAIM_TAIL)
		debug_preview_claim(m.x,game.owners[m.x],1.0 if scenario == "claim_end" else progress)
		return
	if scenario in ["win","win_end"]:
		_debug_stage(WIN_GAME)
		debug_preview_win(game.big_lines[0],game.status,.95 if scenario == "win_end" else progress)
		return
	var staged = Rules.new()
	for m in MIDGAME: staged.play(m[0],m[1])
	debug_load_position(staged.serialize())
	if scenario in ["duo_hinge","hinge"]: debug_simulate_hinge()
	if scenario == "thinking":
		var m = MIDGAME_REPLY
		game.play(m[0],m[1]); _refresh_labels(); thinking = true; _rebuild()
	if scenario == "settings": overlay = "settings"; _rebuild()
const MIDGAME_REPLY = [4,8]
## Capture helper: pin shared clocks and repaint every layer once (processing is paused).
func debug_refresh():
	P.clock = clock
	_sync_fx(); board.refresh(); backdrop.refresh(); queue_redraw()
	for n in ui_nodes:
		if is_instance_valid(n): n.queue_redraw()
