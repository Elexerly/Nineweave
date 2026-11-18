extends Control
## Guided examples on the actual board renderer, with a separate rules model.
## No demo move enters the real match, undo stack, transport or resume save.
## Auto-advances until a player takes control. Back/Next pause auto-play; Skip remains.
const Rules = preload("res://kernel/rules.gd")
const P = preload("res://ui/paint.gd")
const ButtonArt = preload("res://ui/ornate_button.gd")
const STEPS = [
	"You play in any open square.",
	"Where you play sends your opponent to the matching board.",
	"Their square sends you to the matching board, too.",
	"Win three squares in a row to claim a small board.",
	"Win three big boards in a row to win the match.",
	"If sent to a full or won board, play in any open square.",
]
## Long enough for the arrow to finish (0.65s) with a readable pause after.
const STEP_SECONDS = 3.0
signal finished(skipped: bool)
var active: bool = false
var manual: bool = false
var step: int = 0
var age: float = 0
var reduced_motion: bool = false
var replay: bool = false
var demo = Rules.new()
var board
var controls: Dictionary = {}
var caption: Label
var counter: Label
var _board_rect: Rect2
var _caption_rect: Rect2
var _advance_guard_until: int = 0
var _mouse_echo: bool = false
var _ignore_next_delta: bool = false
func _ready():
	z_index = 80; mouse_filter = Control.MOUSE_FILTER_STOP; hide()
	counter = _label(17,P.GOLD); caption = _label(22,P.PALE)
	var button = ButtonArt.new(); button.name = "skip"; button.font_size = 20
	button.caption = "Skip"; button.pressed.connect(skip)
	add_child(button); controls.skip = button
	for id in ["back", "next"]:
		var nav = ButtonArt.new(); nav.name = id; nav.font_size = 20
		nav.caption = "Back" if id == "back" else "Next"
		nav.pressed.connect(previous_step if id == "back" else manual_next)
		add_child(nav); controls[id] = nav
func _label(font_size: int, color: Color) -> Label:
	var label = Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color); add_child(label); return label
func begin(live_board, layout: Dictionary, is_replay: bool = false):
	board = live_board; active = true; replay = is_replay; step = 0; manual = false
	_advance_guard_until = 0; _mouse_echo = false
	reduced_motion = board.reduced_motion
	board.clear_effects(); board.game = demo; board.frozen = true
	show(); relayout(layout); _show_step()
func relayout(layout: Dictionary):
	size = layout.size; _board_rect = layout.board
	var portrait = size.x <= size.y
	var x = 16.0 if portrait else _board_rect.end.x+16
	var w = size.x-x-16
	counter.position = Vector2(x,12); counter.size = Vector2(w-100,44)
	controls.skip.position = Vector2(x+w-90,12); controls.skip.size = Vector2(90,44)
	var nav_y = minf(size.y-60, _board_rect.end.y+16) if portrait else size.y-60
	var nav_w = (w-12)/2
	controls.back.position = Vector2(x,nav_y); controls.back.size = Vector2(nav_w,44)
	controls.next.position = Vector2(x+nav_w+12,nav_y); controls.next.size = Vector2(nav_w,44)
	_caption_rect = Rect2(x,62,w,maxf(56,_board_rect.position.y-70)) if portrait else Rect2(x,76,w,size.y-152)
	caption.position = _caption_rect.position; caption.size = _caption_rect.size
	queue_redraw()
func _show_step():
	age = 0; _ignore_next_delta = true
	demo.new_game(); board.clear_effects(); board.frozen = true
	if step <= 2:
		demo.play(0,5)
		if step == 0: demo.active_board = -1 # Reveal the destination on the next tap.
		if step == 2: demo.play(5,7)
	else:
		var patterns = ["XX.OO....",".........",".........",".........",".........",".........",".........",".........","........."]
		if step == 4:
			patterns[0] = "XXXOO...."; patterns[1] = "XXXOO...."; patterns[2] = "XX.OO...."
		demo.deserialize({"v":1,"cells":"".join(patterns),"turn":1,"active":2 if step == 4 else 0,"history":[]})
		demo.play(2 if step == 4 else 0,2)
		if step == 5: demo.play(2,0) # A real rules-kernel move to a won destination.
	if step == 0: board.notify_move(0,5)
	elif step == 2: board.notify_move(5,7)
	counter.text = "HOW TO PLAY · %d / %d" % [step+1,STEPS.size()]
	caption.text = STEPS[step]
	controls.back.disabled = step == 0
	controls.next.caption = "Done" if step == STEPS.size()-1 else "Next"
	board._dirty = true; board.refresh(); queue_redraw()
func previous_step():
	if not active: return
	manual = true
	if step > 0: step -= 1; _show_step()
func manual_next():
	if not active: return
	manual = true
	next_step()
func next_step():
	if not active: return
	if step == STEPS.size()-1: _finish(false)
	else: step += 1; _show_step()
func skip():
	if active: _finish(true)
func _finish(skipped: bool):
	active = false; hide(); finished.emit(skipped)
func _process(delta: float):
	if not active: return
	if _ignore_next_delta:
		_ignore_next_delta = false
		delta = 0
	age += delta
	for key in board.mark_ages: board.mark_ages[key] = age
	board.refresh(); queue_redraw()
	if not manual and age >= STEP_SECONDS: next_step()
func arrow_progress() -> float:
	return 1.0 if reduced_motion else smoothstep(0,.65,age)
func _over_skip(point: Vector2) -> bool:
	# Let the buttons receive their own press/release; never advance behind them.
	for button in controls.values():
		if is_instance_valid(button) and button.get_global_rect().grow(6).has_point(point): return true
	return false
func _clear_mouse_echo(): _mouse_echo = false
func _pointer_release(event) -> bool:
	# Prefer _input so a sibling game-chrome button cannot swallow the gesture on web.
	# Touch plus its emulated mouse must only advance once (350ms guard).
	# The same mouse event can also arrive through both _input and _gui_input;
	# _mouse_echo swallows that duplicate without blocking a later touch.
	var is_touch = event is InputEventScreenTouch
	var is_mouse = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if not is_touch and not is_mouse: return false
	if event.pressed: return true
	var now = Time.get_ticks_msec()
	if is_touch:
		if now >= _advance_guard_until:
			manual_next(); _advance_guard_until = now+350
		return true
	if _mouse_echo or now < _advance_guard_until: return true
	manual_next(); _mouse_echo = true; _clear_mouse_echo.call_deferred()
	return true
func _input(event):
	if not active or not visible: return
	if _over_skip(event.position if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag else Vector2(-1,-1)): return
	if _pointer_release(event): get_viewport().set_input_as_handled()
func _gui_input(event):
	# Keep a GUI-path advance so a click on this overlay still jumps ahead when
	# _input is not dispatched (unit tests call _gui_input directly).
	if _over_skip(event.position if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag else Vector2(-1,-1)): return
	if _pointer_release(event): accept_event()
func _unhandled_key_input(event):
	if not active or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE: skip()
	elif event.keycode in [KEY_SPACE,KEY_ENTER,KEY_RIGHT]: manual_next()
	elif event.keycode == KEY_LEFT: previous_step()
	else: return
	get_viewport().set_input_as_handled()
func _center(b: int, c: int) -> Vector2:
	return _board_rect.position+board.cell_center(b,c)
func _arrow(a: Vector2, z: Vector2):
	var progress = arrow_progress()
	if progress <= .001: return
	var points = PackedVector2Array(); var bend = Vector2(-(z-a).y,(z-a).x).normalized()*minf(30,a.distance_to(z)*.18)
	for i in range(25):
		var t = progress*i/24.0
		points.append(a.lerp(z,t)+bend*sin(t*PI))
	draw_polyline(points,Color(0,0,0,.9),7,true); draw_polyline(points,P.PALE,3,true)
	var tip = points[-1]; var direction = (tip-points[-2]).normalized()
	var side = Vector2(-direction.y,direction.x)
	draw_colored_polygon(PackedVector2Array([tip,tip-direction*13+side*7,tip-direction*13-side*7]),P.PALE)
func _draw():
	if not active: return
	# Dim the surrounding match chrome, retaining the locked board's exact geometry.
	var r = _board_rect.grow(5); var shade = Color(.001,.005,.015,.97)
	draw_rect(Rect2(0,0,size.x,r.position.y),shade)
	draw_rect(Rect2(0,r.end.y,size.x,size.y-r.end.y),shade)
	draw_rect(Rect2(0,r.position.y,r.position.x,r.size.y),shade)
	draw_rect(Rect2(r.end.x,r.position.y,size.x-r.end.x,r.size.y),shade)
	if step == 0:
		var target = _center(0,5)
		_arrow(target+Vector2(60,-45),target+Vector2(9,-5))
	elif step in [1,2,5]:
		var source = _center(0,5) if step == 1 else (_center(5,7) if step == 2 else _center(2,0))
		var destination = 5 if step == 1 else (7 if step == 2 else 0)
		var target = _board_rect.position+board.tile_rect(destination).get_center()
		_arrow(source,target)
	elif step == 3:
		_arrow(_center(0,0),_center(0,2))
	else:
		_arrow(_board_rect.position+board.tile_rect(0).get_center(),_board_rect.position+board.tile_rect(2).get_center())
