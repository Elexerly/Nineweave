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
const PORTRAIT = preload("res://assets/art/goddess_portrait.png")
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
var _input_beat: float = 0
var _last_size = Vector2.ZERO
var _manual_size = Vector2.ZERO
var _resize_pending: bool = false
var _modal_rect: Rect2
var _debug_capture: bool = false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.new(); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	board = Board.new(); board.game = game; board.cell_pressed.connect(play_cell); add_child(board)
	sound = Sound.new(); add_child(sound)
	title_label = Label.new(); title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font",P.DISPLAY)
	title_label.add_theme_color_override("font_outline_color",Color("130e13")); title_label.add_theme_constant_override("outline_size",5)
	title_label.add_theme_color_override("font_shadow_color",Color(0,0,0,.8)); title_label.add_theme_constant_override("shadow_offset_y",4)
	var mat = ShaderMaterial.new(); mat.shader = preload("res://assets/shaders/gold.gdshader"); title_label.material = mat
	add_child(title_label)
	_apply_preferences(); _relayout(); _rebuild()
	get_viewport().size_changed.connect(_on_viewport_resize)
func _on_viewport_resize():
	if _manual_size != Vector2.ZERO: return
	_resize_pending = true
func set_view_size(physical: Vector2):
	_manual_size = physical
	get_window().content_scale_size = Vector2i(Layout.logical_size(physical))
	size = Layout.logical_size(physical)
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
	board.position = layout.board.position; board.size = layout.board.size
	backdrop.set_deferred("size",logical)
	var fs = clampi(int(logical.x*.075),30,76)
	if logical.x > logical.y: fs = clampi(int(logical.y*.105),38,82)
	title_label.text = "NINEWEAVE"; title_label.add_theme_font_size_override("font_size",fs)
	title_label.position = Vector2(logical.x*.06,logical.y*.205)
	title_label.size = Vector2(logical.x*.88,fs*1.5)
	if logical.x > logical.y:
		fs = clampi(int(logical.y*.12),30,80)
		title_label.add_theme_font_size_override("font_size",fs)
		title_label.position = Vector2(logical.x*.025,logical.y*.27)
		title_label.size = Vector2(logical.x*.48,fs*1.5)
	if layout.hinge.size.x > 0:
		fs = clampi(int(layout.hinge.position.x*.10),25,68)
		title_label.add_theme_font_size_override("font_size",fs)
		title_label.position = Vector2(16,logical.y*.27)
		title_label.size = Vector2(layout.hinge.position.x-32,fs*1.5)
func _apply_preferences():
	board.reduced_motion = bool(settings.values.reduced_motion)
	backdrop.reduced_motion = bool(settings.values.reduced_motion)
	sound.enabled = bool(settings.values.sound)
func _process(delta):
	if _resize_pending and not get_viewport().gui_get_focus_owner() is LineEdit:
		_resize_pending = false; _relayout(); _rebuild()
	clock += delta
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
	if page == "game" and game.status != 0 and not board.win_fx.is_empty() and board.win_progress() >= .78 and not _result_shown:
		_result_shown = true; overlay = "result"; _rebuild()
	queue_redraw()
func start_game(new_mode: String = "computer", mark: int = 1):
	_leave_online()
	mode = new_mode; human_mark = mark; page = "game"; overlay = ""
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
	if game.status != 0: turn_label = "Draw" if game.status == 3 else ("X" if game.status == 1 else "O")+" wins"
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
	if mode == "computer" and page == "game":
		settings.saved_game = {"state":game.serialize(),"human":human_mark,"seconds":match_seconds} if game.status == 0 else {}
		settings.save()
func resume_game():
	if settings.saved_game.is_empty(): return
	if not game.deserialize(settings.saved_game.state): settings.saved_game = {}; return
	mode = "computer"; human_mark = int(settings.saved_game.human); match_seconds = float(settings.saved_game.get("seconds",0))
	page = "game"; overlay = ""; board.clear_effects(); _result_shown = false
	_refresh_labels(); _rebuild(); _schedule_ai()
func go_home():
	_save_match(); _leave_online(); thinking = false; page = "title"; overlay = ""; _rebuild()
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
	ui_nodes.clear(); controls.clear(); history_label = null
func _button(id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false):
	var b = OrnateButton.new(); b.name = id; b.caption = caption; b.tooltip_text = caption
	b.position = rect.position; b.size = rect.size; b.accent = accent
	b.pressed.connect(callback); add_child(b); ui_nodes.append(b); controls[id] = b
	return b
func _field(id: String, placeholder: String, rect: Rect2, value: String = ""):
	var e = LineEdit.new(); e.name = id; e.placeholder_text = placeholder; e.text = value
	e.position = rect.position; e.size = rect.size; e.add_theme_font_override("font",P.SANS); e.add_theme_font_size_override("font_size",22)
	e.add_theme_color_override("font_color",P.PALE); e.add_theme_color_override("caret_color",P.BLUE)
	var style = StyleBoxFlat.new(); style.bg_color = Color("041425"); style.border_color = P.GOLD
	style.set_border_width_all(1); style.set_corner_radius_all(6); style.content_margin_left = 12
	e.add_theme_stylebox_override("normal",style); e.add_theme_stylebox_override("focus",style)
	e.text_submitted.connect(func(_value): e.release_focus())
	add_child(e); ui_nodes.append(e); controls[id] = e
	return e
func _rebuild():
	if not is_instance_valid(board): return
	_clear_nodes()
	board.visible = page == "game"
	board.mouse_filter = Control.MOUSE_FILTER_STOP if overlay.is_empty() else Control.MOUSE_FILTER_IGNORE
	backdrop.title_mode = page != "game"
	title_label.visible = page == "title"
	var s: Vector2 = layout.size
	if page == "title":
		var bw = minf(320,s.x-64); var bh = clampf(s.y*.064,44,56)
		var y = s.y*.48; var gap = bh+10
		var menu_x = (s.x-bw)/2
		if s.x > s.y or layout.hinge.size.x > 0:
			bw = minf(320,s.x*.40); menu_x = s.x*.56
			if layout.hinge.size.x > 0:
				menu_x = layout.hinge.end.x+12; bw = minf(320,s.x-menu_x-12)
			y = (s.y-(gap*3+44+(54 if not settings.saved_game.is_empty() else 0)))/2
		_button("computer","Play vs Computer",Rect2(menu_x,y,bw,bh),func(): overlay = "setup"; _rebuild(),true)
		_button("online","Play Online",Rect2(menu_x,y+gap,bw,bh),open_online)
		_button("local","Pass & Play",Rect2(menu_x,y+gap*2,bw,bh),func(): start_game("local"))
		_button("settings","Settings",Rect2(menu_x,y+gap*3,bw*.48,44),show_settings)
		_button("how","How to Play",Rect2(menu_x+bw*.52,y+gap*3,bw*.48,44),func(): overlay = "how"; _rebuild())
		if not settings.saved_game.is_empty(): _button("resume","Resume Journey",Rect2(menu_x,y+gap*3+54,bw,44),resume_game)
	elif page == "game":
		var hdr: Rect2 = layout.header
		_button("home","‹",Rect2(hdr.position,Vector2(44,44)),go_home)
		_button("settings","⚙",Rect2(hdr.end-Vector2(44,44),Vector2(44,44)),show_settings)
		var cr: Rect2 = layout.controls
		if layout.mode in ["phone_portrait","tablet_portrait"]:
			var unit = minf(cr.size.x/4-9,72)
			_button("undo","↶  Undo",Rect2(cr.position,Vector2(unit,cr.size.y)),undo_move)
			_button("hint","Hint  ✧",Rect2(cr.end-Vector2(unit,cr.size.y),Vector2(unit,cr.size.y)),request_hint)
		else:
			_button("undo","↶ Undo",Rect2(cr.position,Vector2(cr.size.x*.48,cr.size.y)),undo_move)
			_button("hint","✧ Hint",Rect2(cr.position+Vector2(cr.size.x*.52,0),Vector2(cr.size.x*.48,cr.size.y)),request_hint)
		controls.undo.disabled = mode == "online"
		controls.hint.disabled = mode == "online" or not settings.values.show_hints
		if layout.has("history"): _create_history(layout.history)
	elif page == "online": _online_controls(s)
	if not overlay.is_empty(): _overlay_controls(s)
	queue_redraw()
func _create_history(rect: Rect2):
	history_label = RichTextLabel.new(); history_label.position = rect.position+Vector2(8,21); history_label.size = rect.size-Vector2(16,25)
	history_label.add_theme_font_override("normal_font",P.SANS); history_label.add_theme_font_size_override("normal_font_size",14)
	history_label.add_theme_color_override("default_color",P.WHITE); history_label.scroll_following = true
	add_child(history_label); ui_nodes.append(history_label); _refresh_history()
func _refresh_history():
	if not is_instance_valid(history_label): return
	var lines: Array = []
	for i in range(game.history.size()):
		var m = game.history[i]
		lines.append("%d. %s → %s · %s" % [i+1,"X" if m.player == 1 else "O",Rules.BOARD_NAMES[m.board],Rules.BOARD_NAMES[m.cell]])
	history_label.text = "\n".join(lines) if not lines.is_empty() else "Your story begins here."
func _online_controls(s: Vector2):
	var short = (s.x > s.y and s.y < 500) or hinge_rect.size.x > 0
	var pw = s.x*.44 if short else minf(460,s.x-32); var x = s.x*.53 if short else (s.x-pw)/2
	_button("back","‹  Menu",Rect2(16,16,100,44),go_home)
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
	if overlay == "result": ph = minf(330,s.y-24)
	_modal_rect = Rect2((s.x-pw)/2,(s.y-ph)/2,pw,ph)
	if layout.hinge.size.x > 0:
		pw = minf(pw,s.x-layout.hinge.end.x-24)
		_modal_rect = Rect2(layout.hinge.end.x+12,(s.y-ph)/2,pw,ph)
	# Modal painting belongs above the shield and all underlay controls.
	var painter = Control.new(); painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE; painter.draw.connect(_draw_modal.bind(painter)); add_child(painter); ui_nodes.append(painter)
	var r = _modal_rect
	_button("close","×",Rect2(r.end.x-56,r.position.y+10,44,44),_close_overlay)
	if overlay == "setup":
		var y = r.position.y+(76 if short else 94); var step = (pw-56)/3
		for i in range(3):
			var level = ["Easy","Medium","Hard"][i]
			_button("difficulty_"+level,level,Rect2(r.position.x+20+i*step,y,step-8,48),func(): settings.set_value("difficulty",level); _rebuild(),settings.values.difficulty == level)
		_button("choose_x","X  ·  Play first",Rect2(r.position.x+24,y+(60 if short else 88),pw-48,48 if short else 56),func(): start_game("computer",1),true)
		_button("choose_o","O  ·  Play second",Rect2(r.position.x+24,y+(118 if short else 156),pw-48,48 if short else 56),func(): start_game("computer",2))
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
		_button("again","Play Again",Rect2(r.position.x+26,r.end.y-128,pw-52,50),func():
			if mode == "online": open_online()
			else: start_game(mode,human_mark),true)
		_button("menu","Menu",Rect2(r.position.x+26,r.end.y-66,pw-52,44),go_home)

func _draw():
	if layout.is_empty(): return
	if page == "title": _draw_title()
	elif page == "game": _draw_game()
	elif page == "online": _draw_online()
	if hinge_rect.size.x > 0:
		var seam: Rect2 = layout.hinge
		draw_rect(seam,Color("01040b")); draw_line(seam.position,seam.position+Vector2(0,seam.size.y),Color(.4,.3,.15,.5),1)
func _draw_title():
	var s: Vector2 = layout.size
	var landscape = s.x > s.y or layout.hinge.size.x > 0
	var cy = s.y*(.20 if landscape else .177)
	var logo_x = layout.hinge.position.x*.5 if layout.hinge.size.x > 0 else s.x*(.265 if landscape else .5)
	var scale_value = minf(s.x/390.0,s.y/700.0)
	for i in [-1,0,1]:
		P.crystal(self,Vector2(logo_x+i*23*scale_value,cy+abs(i)*14*scale_value),(36 if i == 0 else 22)*scale_value,P.BLUE,i*.18)
	P.line_glow(self,Vector2(logo_x-70*scale_value,cy+42*scale_value),Vector2(logo_x+70*scale_value,cy+42*scale_value),P.GOLD,1)
	var r = Rect2(s.x*.23,s.y*.326,s.x*.54,36)
	if landscape: r = Rect2(s.x*.09,s.y*.51,s.x*.35,36)
	if layout.hinge.size.x > 0: r = Rect2(20,s.y*.51,layout.hinge.position.x-40,36)
	P.panel(self,r,false,1,true); P.text(self,"T I C   T A C   T O E",r,17,P.PALE,P.SERIF)
	P.text(self,"NINE BOARDS. ONE DESTINY.",Rect2(20,s.y*(.67 if landscape else .4),(layout.hinge.position.x if layout.hinge.size.x > 0 else s.x*(.48 if landscape else 1))-40,28),15,P.WHITE,P.SERIF)
	P.text(self,"A CELESTIAL GAME OF STRATEGY",Rect2(20,s.y-34,(layout.hinge.position.x if layout.hinge.size.x > 0 else s.x)-40,20),11,P.GOLD,P.SERIF)
func display_player() -> int:
	return game.status if game.status in [1,2] else game.turn
func _draw_game():
	var s: Vector2 = layout.size
	# A restrained vignette makes the live board luminous against the art.
	_draw_players(layout.players,layout.mode == "landscape")
	P.panel(self,layout.turn,false,1,true)
	P.text(self,turn_label,layout.turn,22,P.BLUE if display_player() == 1 else P.PALE,P.SERIF)
	_draw_info(layout.info,layout.mode == "landscape")
	if layout.has("minimap"): _draw_minimap(layout.minimap)
	if layout.has("stats"):
		P.panel(self,layout.stats)
		var elapsed = "%02d:%02d" % [int(match_seconds)/60,int(match_seconds)%60]
		P.text(self,"X  %d    ·    O  %d    |    %d moves    |    %s" % [game.owners.count(1),game.owners.count(2),game.history.size(),elapsed],layout.stats,15,P.GOLD)
	if layout.has("history"):
		P.panel(self,layout.history)
		P.text(self,"CHRONICLE",Rect2(layout.history.position,Vector2(layout.history.size.x,20)),11,P.GOLD,P.SERIF)
	if layout.mode in ["phone_portrait","tablet_portrait"]:
		var cr: Rect2 = layout.controls
		var tile = minf(cr.size.y+6,74)
		for p in [1,2]:
			var x = cr.get_center().x+(p-1.5)*(tile+9)-tile/2
			var rr = Rect2(x,cr.position.y-3,tile,tile)
			P.panel(self,rr,display_player() == p,1,true)
			P.mark(self,rr.get_center(),tile*.36,p,1,1.3)
	if not message.is_empty() and clock-fmod(clock,1) >= 0:
		P.text(self,message,Rect2(16,s.y-20,s.x-32,18),12,P.GOLD)
	if hint_busy: P.text(self,"Reading the threads…",Rect2(layout.board.position.x,layout.board.end.y-22,layout.board.size.x,20),14,P.PALE)
	if not board.win_fx.is_empty(): _draw_victory_rays(board.win_progress(),int(board.win_fx.player))
func _draw_players(r: Rect2, vertical: bool):
	if vertical:
		var hh = minf(230,(r.size.y-48)*.5)
		r.position.y += maxf(0,(r.size.y-hh*2-48)*.5)
		_draw_player(Rect2(r.position,Vector2(r.size.x,hh)),human_mark,str(settings.values.player_name),display_player() == human_mark,true)
		P.text(self,"VS",Rect2(r.position.x,r.position.y+hh+2,r.size.x,40),24,P.GOLD,P.SERIF)
		_draw_player(Rect2(r.position.x,r.position.y+hh+48,r.size.x,hh),3-human_mark,_rival_name(),display_player() != human_mark,true)
	else:
		var gap = minf(42,r.size.x*.12); var width = (r.size.x-gap)/2
		_draw_player(Rect2(r.position,Vector2(width,r.size.y)),human_mark,str(settings.values.player_name),display_player() == human_mark,false)
		P.text(self,"VS",Rect2(r.position.x+width,r.position.y,gap,r.size.y),20,P.GOLD,P.SERIF)
		_draw_player(Rect2(r.end.x-width,r.position.y,width,r.size.y),3-human_mark,_rival_name(),display_player() != human_mark,false)
func _rival_name() -> String:
	if mode == "local": return "Player O" if human_mark == 1 else "Player X"
	if mode == "online": return opponent_name
	return "Rival AI"
func _draw_player(r: Rect2, mark: int, caption: String, active: bool, vertical: bool):
	P.panel(self,r,false,1,true)
	var radius = minf(r.size.y*.34,r.size.x*.28) if not vertical else r.size.x*.32
	var center = Vector2(r.position.x+radius+7,r.get_center().y) if not vertical else Vector2(r.get_center().x,r.position.y+radius+17)
	for i in range(3,0,-1): draw_arc(center,radius+i,0,TAU,48,Color(P.BLUE if mark == 1 else P.GOLD,.06),3*i,true)
	draw_circle(center,radius,Color("031324")); draw_arc(center,radius,0,TAU,48,P.GOLD,1.8,true)
	# The rival wears the reference statue portrait inside the gold medallion.
	if caption != str(settings.values.player_name) and mode != "local":
		draw_texture_rect(PORTRAIT,Rect2(center-Vector2.ONE*(radius-2),Vector2.ONE*(radius-2)*2),false,Color(1,1,1,.85))
		if thinking:
			draw_arc(center,radius+3,clock*2,clock*2+PI*1.3,32,Color(P.BLUE,.8),1.8,true)
	else: P.mark(self,center,radius*.76,mark)
	if active: P.crown(self,center-Vector2(0,radius+2),.56 if not vertical else .8)
	var tr = Rect2(center.x+radius+4,r.position.y+6,r.end.x-center.x-radius-8,r.size.y-12)
	if vertical: tr = Rect2(r.position.x+4,center.y+radius+7,r.size.x-8,r.end.y-center.y-radius-12)
	var display_name = caption
	if thinking and mark != human_mark: display_name = "Thinking"+".".repeat(1+int(clock*3)%3)
	P.text(self,display_name,Rect2(tr.position,tr.size*Vector2(1,.52)),17,P.WHITE)
	P.text(self,("X" if mark == 1 else "O")+"  ·  %d claimed" % game.owners.count(mark),Rect2(tr.position+Vector2(0,tr.size.y*.52),tr.size*Vector2(1,.48)),14,P.BLUE if mark == 1 else P.PALE)
func _draw_info(r: Rect2, large: bool):
	P.panel(self,r,false,1,true)
	var board_name = "Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
	if large:
		P.text(self,"Active Board",Rect2(r.position+Vector2(4,8),Vector2(r.size.x-8,25)),19,P.WHITE)
		P.text(self,board_name,Rect2(r.position+Vector2(4,33),Vector2(r.size.x-8,26)),20,P.BLUE,P.SERIF)
		var map_size = minf(r.size.x-42,r.size.y-116)
		_draw_minimap(Rect2(r.get_center().x-map_size/2,r.position.y+66,map_size,map_size))
		P.text(self,"Play your "+("X" if game.turn == 1 else "O")+" in this board.",Rect2(r.position.x+8,r.end.y-38,r.size.x-16,28),16,P.WHITE)
	else:
		P.text(self,"Active Board: "+board_name,Rect2(r.position+Vector2(4,2),Vector2(r.size.x-8,r.size.y*.55)),18,P.BLUE)
		if r.size.y >= 46: P.text(self,"Play your "+("X" if game.turn == 1 else "O")+" in the glowing board.",Rect2(r.position+Vector2(4,r.size.y*.52),Vector2(r.size.x-8,r.size.y*.44)),13,P.WHITE)
func _draw_minimap(r: Rect2):
	P.panel(self,r)
	var edge = minf(r.size.x,r.size.y)-12
	var origin = r.get_center()-Vector2.ONE*edge/2
	for b in range(9):
		var rr = Rect2(origin+Vector2(b%3,b/3)*edge/3,Vector2.ONE*(edge/3-2))
		var active: bool = game.owners[b] == 0 and (game.active_board == -1 or game.active_board == b)
		draw_rect(rr,Color(.04,.4,.55,.7) if active else Color("08182a"))
		draw_rect(rr,Color(P.BLUE,.9) if active else Color(.3,.42,.5,.5),false,.8)
		if game.owners[b] in [1,2]: P.mark(self,rr.get_center(),edge*.1,game.owners[b])
		elif game.owners[b] == 3: P.diamond(self,rr.get_center(),edge*.05,P.MUTED)
func _draw_victory_rays(p: float, player: int):
	var s: Vector2 = layout.size; var center = s*.5
	var color = P.BLUE if player == 1 else P.GOLD
	var alpha = sin(p*PI)*.12
	var number = 12 if board.reduced_motion else 28
	for i in range(number):
		var angle = i*TAU/number+clock*.08
		var a = center+Vector2.from_angle(angle)*s.length()
		var b = center+Vector2.from_angle(angle+.025)*s.length()
		draw_colored_polygon(PackedVector2Array([center,a,b]),Color(color,alpha))
	if p < .35: draw_rect(Rect2(Vector2.ZERO,s),Color(color,sin(p/.35*PI)*.13))
	for i in range(24 if board.reduced_motion else 100):
		var a = i*2.39996
		var pos = center+Vector2.from_angle(a)*s.length()*.55*p*(.4+fmod(i*.13,1))
		P.diamond(self,pos,(1-p)*(2+i%4),Color(color,(1-p)*.9))
func _draw_online():
	var s: Vector2 = layout.size
	var short = (s.x > s.y and s.y < 500) or hinge_rect.size.x > 0
	var title_w = s.x*.46 if short else s.x-40
	P.text(self,"THE CELESTIAL ARENA",Rect2(20,70,title_w,48),27,P.PALE,P.SERIF)
	P.text(self,"A friend. Nine boards. One shared sky.",Rect2(20,118,title_w,30),17,P.WHITE)
	var pw = s.x*.44 if short else minf(460,s.x-32); var y = 64.0 if short else maxf(140,s.y*.3); var x = s.x*.53 if short else (s.x-pw)/2
	if online_state == "waiting":
		P.panel(self,Rect2(x+16,y-10,pw-32,142),true,1,true)
		P.text(self,room_code,Rect2(x+24,y+14,pw-48,56),44,P.PALE,P.SERIF)
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
	node.draw_rect(Rect2(Vector2.ZERO,s),Color(.001,.005,.015,.88))
	P.panel(node,r,false,1,true); P.outline(node,r.grow(-6),P.GOLD.darkened(.4),1)
	var heading = {"settings":"SETTINGS","setup":"CHOOSE YOUR PATH","how":"HOW TO PLAY","result":_victory_title()}.get(overlay,"")
	P.text(node,heading,Rect2(r.position+Vector2(20,23),Vector2(r.size.x-72,44)),25,P.PALE,P.SERIF)
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
	elif overlay == "result":
		if game.status == 3: P.crystal(node,Vector2(r.get_center().x,r.position.y+119),36,P.MUTED)
		else: P.mark(node,Vector2(r.get_center().x,r.position.y+119),36,game.status,.95,2)
		if not short: P.text(node,"The threads of fate are woven.",Rect2(r.position.x+20,r.position.y+158,r.size.x-40,28),18,P.WHITE)
func _victory_title() -> String:
	if game.status == 3: return "DRAW"
	if mode == "local": return ("X" if game.status == 1 else "O")+" WINS"
	return "VICTORY" if game.status == human_mark else "DEFEAT"

# Debug-only deterministic hooks. Preview hooks never alter rules state.
func debug_preview_claim(board_index: int, player: int, progress: float):
	if OS.is_debug_build(): board.preview_claim(board_index,player,progress)
func debug_preview_win(line: Array, player: int, progress: float):
	if OS.is_debug_build(): board.preview_win(line,player,progress)
func debug_load_position(serialized) -> bool:
	if not OS.is_debug_build(): return false
	thinking = false; hint_busy = false; _input_beat = 0; _debug_capture = true
	if not game.deserialize(serialized): return false
	page = "game"; mode = "local"; overlay = ""; board.clear_effects(); _result_shown = false
	_refresh_labels(); _rebuild(); return true
func debug_simulate_hinge(width: float = 22):
	if OS.is_debug_build(): set_hinge_rect(Rect2((layout.size.x-width)/2,0,width,layout.size.y))
func debug_scenario(scenario: String, progress: float = .45):
	if not OS.is_debug_build(): return
	_debug_capture = true; clock = 4; backdrop.clock = 4
	if scenario == "title": page = "title"; overlay = ""; _rebuild(); return
	if scenario == "online":
		open_online(); create_online(true); return
	var patterns = ["X..O....X","..O.X....","..X.O....","O....X.X.","O...X...O",".X.O.....","..X.X.O..",".O....X..",".X...OO.."]
	var staged = Rules.new()
	# A real legal 26-ply game, X to move in Center, with a useful live chronicle.
	for m in [[1,0],[0,4],[4,6],[6,5],[5,7],[7,2],[2,3],[3,2],[2,7],[7,4],[4,1],[1,3],[3,8],[8,8],[8,3],[3,6],[6,1],[1,5],[5,8],[8,1],[1,4],[4,5],[5,5],[5,2],[2,2],[2,4]]: staged.play(m[0],m[1])
	debug_load_position(staged.serialize())
	if scenario in ["duo_hinge","hinge"]: debug_simulate_hinge()
	if scenario == "claim": debug_preview_claim(4,1,progress)
	if scenario == "win":
		var data = game.serialize(); data.history = []; data.cells = "XXXOO...."+patterns[1]+patterns[2]+patterns[3]+"XXXOO...."+patterns[5]+patterns[6]+patterns[7]+"XXXOO...."
		debug_load_position(data.merged({"active":-1},true)); debug_preview_win([0,4,8],1,progress)
	if scenario == "settings": overlay = "settings"; _rebuild()
