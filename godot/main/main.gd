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
const JsonAPI = preload("res://net/json_api.gd")
const DeviceAccount = preload("res://net/device_account.gd")
const OnlineScreen = preload("res://ui/online_screen.gd")
const Announcer = preload("res://fx/announcer.gd")
const Callout = preload("res://fx/comic_callout.gd")
const Themes = preload("res://themes/registry.gd")
const Roster = preload("res://characters/roster.gd")
const Profile = preload("res://characters/profile.gd")
const HeroRig = preload("res://characters/art.gd")
const HeroSelect = preload("res://characters/select.gd")
const Cinematic = preload("res://characters/cinematic.gd")
const Sound = preload("res://fx/sound.gd")
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
var profile = Profile.new()
var account = DeviceAccount.new()
var online_api = JsonAPI.new()
## Explicit harness/capture opt-out; never derived from character-select onboarding.
var test_online_bypass: bool = false
var online_view
var lobby_timer: Timer
var public_rooms: Array = []
var leaderboard_players: Array = []
var leaderboard_me: Dictionary = {}
var _lobby_pending: bool = false
var _onboarding_destination: String = "title"
var _onboarding_name: String = ""
var _room_password: String = ""
var _hero_changed: bool = false
var rival_character: String = "auric_rex"
var hero_select
var cinematic
var field_heroes: Dictionary = {}
var _pending_game: Dictionary = {}
var _select_player: int = 0
var _local_picked: bool = false
var _selection_page: int = 0
var _hero_focus: String = ""
var _name_draft: String = ""
var _spotlight_done: bool = false
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
var hinge_overlay: Layer
var sound
var callout
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
## Round 3b: one skip gesture (touch + emulated mouse + release) never reaches the UI behind.
const SKIP_GUARD_MS = 350
var _skip_guard_until: int = 0
var _hint_ply: int = -1

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
	callout = Callout.new(); callout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(callout)
	cinematic = Cinematic.new(); cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cinematic)
	cinematic.finished.connect(_cinematic_finished)
	cinematic.buttons_ready.connect(func(): _result_shown = true; overlay = "result"; _rebuild())
	sound.voice_started.connect(func(id): callout.show_callout(id))
	hinge_overlay = Layer.new(); hinge_overlay.name = "FoldGutter"; hinge_overlay.painter = _draw_hinge
	hinge_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; hinge_overlay.z_index = 100
	hinge_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(hinge_overlay)
	title_label = Label.new(); title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font",P.DISPLAY)
	title_label.add_theme_color_override("font_outline_color",Color("1a0f05")); title_label.add_theme_constant_override("outline_size",7)
	title_label.add_theme_color_override("font_shadow_color",Color(0,0,0,.85)); title_label.add_theme_constant_override("shadow_offset_y",4)
	title_label.add_theme_constant_override("shadow_outline_size",9)
	var mat = ShaderMaterial.new(); mat.shader = preload("res://assets/shaders/gold.gdshader"); title_label.material = mat
	add_child(title_label)
	if not profile.data.onboarded: profile.data.display_name = str(settings.values.player_name)
	account.player_received.connect(_account_player)
	account.name_updated.connect(_account_name)
	account.onboarding_complete.connect(_account_completed)
	account.error.connect(_account_error); add_child(account)
	online_api.completed.connect(_online_response); add_child(online_api)
	lobby_timer = Timer.new(); lobby_timer.wait_time = 2.5; add_child(lobby_timer); lobby_timer.timeout.connect(_refresh_lobby)
	if not test_online_bypass:
		if not account.store.complete(): page = "onboarding"; _onboarding_name = account.store.data.screen_name
		else: _account_name(account.store.data.screen_name)
		account.refresh()
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
	if hinge_overlay: hinge_overlay.queue_redraw()
	_last_size = logical
	board.place(layout.board)
	# Rotation/resize mid-cinematic: recompute its panels against the new board/HUD.
	if cinematic and cinematic.visible: cinematic.relayout(layout)
	callout.region = Rect2(layout.board.position+Vector2(8,-8),Vector2(layout.board.size.x-16,52))
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
	P.board_theme = str(settings.values.board_theme)
	board._dirty = true
	backdrop.background_theme = str(settings.values.background_theme)
	board.reduced_motion = bool(settings.values.reduced_motion)
	backdrop.reduced_motion = bool(settings.values.reduced_motion)
	sound.configure(settings.values)
	callout.reduced_motion = board.reduced_motion
	cinematic.reduced_motion = board.reduced_motion
	if is_instance_valid(hero_select): hero_select.reduced_motion = board.reduced_motion
	for rig in field_heroes.values(): rig.reduced_motion = board.reduced_motion
func _process(delta):
	if _resize_pending and not get_viewport().gui_get_focus_owner() is LineEdit:
		_resize_pending = false; _relayout(); _rebuild()
	clock += delta
	if cinematic: cinematic.advance(delta)
	_update_hero_states()
	P.clock = clock
	_input_beat = maxf(0,_input_beat-delta)
	if page == "game" and overlay.is_empty() and game.status == 0 and not _debug_capture and not (cinematic.active and cinematic.kind == "versus"): match_seconds += delta
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
		if hint_ai.done:
			hint_busy = false
			# Only show a hint computed for the position still on the board.
			if _hint_ply == game.history.size() and game.is_legal(hint_ai.best_move.x,hint_ai.best_move.y): board.hint_move = hint_ai.best_move
	if page == "game" and game.status != 0 and not board.win_fx.is_empty() and board.win_progress() >= RESULT_AT and not _result_shown:
		if not _spotlight_done:
			if not cinematic.active:
				board.frozen = true
				_show_spotlight()
		else:
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
	if cinematic.kind in ["spotlight","draw"]:
		var g = Cinematic.card_geometry(layout.size,cinematic.kind)
		var progress = cinematic.buttons_progress()
		for id in ["again","menu"]:
			if controls.has(id) and is_instance_valid(controls[id]):
				controls[id].position = g[id].position+Vector2(0,0 if cinematic.reduced_motion else (1-Cinematic.Motion.out_cubic(progress))*maxf(0,minf(24,layout.size.y-g[id].end.y-2)))
				controls[id].modulate.a = progress
		return
	var e = Board.back_out(_result_t)
	for id in _result_bases:
		if controls.has(id) and is_instance_valid(controls[id]):
			controls[id].position = _result_bases[id]+Vector2(0,(1-e)*60)
			controls[id].modulate.a = clampf(_result_t*1.4,0,1)
func request_game(new_mode: String = "computer", mark: int = 1):
	if new_mode == "online": open_online(); return
	_pending_game = {"mode":new_mode,"mark":mark}
	_select_player = 1 if new_mode == "local" else 0; _local_picked = false
	open_character_select()
func open_character_select():
	thinking = false; page = "character_select"; overlay = ""
	_hero_focus = str(profile.data.character_id); _name_draft = str(profile.data.display_name)
	_rebuild()
func _confirm_hero(id: String, display_name: String):
	if not Roster.valid(id): return
	id = Roster.canonical_id(id)
	if _select_player == 2:
		if id == str(profile.data.character_id): return
		rival_character = id; _local_picked = true; _select_player = 0
		_pending_game = {}; start_game("local",1,false,true); return
	var saved_name = str(profile.data.display_name) if _select_player == 1 else display_name
	if not test_online_bypass and account.store.complete():
		if saved_name.strip_edges() != account.store.data.screen_name: account.rename(saved_name)
		saved_name = account.store.data.screen_name
	profile.choose(id,saved_name); settings.set_value("player_name",profile.data.display_name)
	_hero_changed = true
	if not test_online_bypass: account.choose_hero(id)
	sound.prepare_character(Roster.audio_index(id)); sound.cue("ui")
	if not _pending_game.is_empty():
		if _pending_game.mode == "local":
			_select_player = 2
			_hero_focus = "aurelia" if id != "aurelia" else "cryon"; _name_draft = "PLAYER 2"
			_rebuild(); return
		var pending = _pending_game; _pending_game = {}; _select_player = 0
		if pending.mode == "resume": resume_game()
		else: start_game(pending.mode,pending.mark,false,true)
	else:
		sound.stinger(Roster.audio_index(id),"tag",-.35)
		cinematic.show_scene("lock_in",id,rival_character,human_mark,layout)
func _cinematic_finished(kind: String):
	if kind == "lock_in": go_home()
	elif kind == "versus":
		board.frozen = false; overlay = ""; _rebuild(); _schedule_ai(); _announce("ready")
	elif kind in ["spotlight","draw"]:
		_spotlight_done = true; board.frozen = false
		_result_shown = true; overlay = "result"; _rebuild(); _sync_fx()
func _input(event):
	var pointer = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	# A touch that skipped a modal cinematic is followed by its emulated mouse press and the
	# release; swallow that one gesture so it cannot land on the newly shown Play Again/Menu.
	if pointer and Time.get_ticks_msec() < _skip_guard_until:
		if not event.pressed: _skip_guard_until = 0
		get_viewport().set_input_as_handled(); return
	var tap = (pointer and event.pressed) or (event is InputEventKey and event.pressed and not event.echo)
	if tap and cinematic and cinematic.active and not cinematic.buttons_shown:
		var was = cinematic.kind
		var skipped = cinematic.skip()
		if was != "pop":
			get_viewport().set_input_as_handled()
			if skipped and not event is InputEventKey: _skip_guard_until = Time.get_ticks_msec()+SKIP_GUARD_MS
func hero_for(mark: int) -> String:
	return str(profile.data.character_id) if mark == human_mark else rival_character
func _show_spotlight():
	var winner = game.status if game.status in [1,2] else human_mark
	cinematic.winner_name = side_name(winner); cinematic.loser_name = side_name(3-winner)
	cinematic.result_score = "%d — %d  BOARDS CLAIMED" % [game.owners.count(winner),game.owners.count(3-winner)]
	cinematic.show_scene("draw" if game.status == 3 else "spotlight",hero_for(winner),hero_for(3-winner),winner,layout)
	if game.status != 3: sound.stinger(Roster.audio_index(hero_for(winner)),"full",-.35 if winner == human_mark else .35)
func _begin_versus():
	thinking = false; board.frozen = true
	cinematic.winner_name = side_name(human_mark); cinematic.loser_name = side_name(3-human_mark)
	cinematic.show_scene("versus",hero_for(human_mark),hero_for(3-human_mark),human_mark,layout)
	sound.cue("route"); sound.stinger(Roster.audio_index(hero_for(human_mark)),"tag",-.35)
func rematch():
	if mode == "online":
		message = ""
		if is_instance_valid(transport):
			transport.request_rematch()
			if is_instance_valid(demo_rival) and transport.local_rematch:
				var peer = weakref(demo_rival); var round_number = transport.match_round
				get_tree().create_timer(1.0).timeout.connect(func():
					var other = peer.get_ref()
					if is_instance_valid(other) and other.match_round == round_number: other.request_rematch())
		_result_controls_refresh(); return
	start_game(mode,3-human_mark if mode == "local" else human_mark,true,true)
func _result_controls_refresh():
	if overlay == "result": _rebuild()

## `rematch` (Play Again) keeps the same rival hero; a new game from the menu/setup
## re-rolls. Round 3c product default, reversible: pass rematch=false to always re-roll.
func start_game(new_mode: String = "computer", mark: int = 1, rematch: bool = false, present: bool = false):
	_leave_online()
	cinematic.clear(); callout.callout = ""; _spotlight_done = false
	var keep = (rematch or (new_mode == "local" and _local_picked)) and Roster.valid(rival_character) and rival_character != str(profile.data.character_id)
	if not keep:
		var available: Array = []
		for h in Roster.DATA:
			if h.id != profile.data.character_id: available.append(h.id)
		rival_character = str(available[randi()%available.size()])
	sound.prepare_character(Roster.audio_index(profile.data.character_id)); sound.prepare_character(Roster.audio_index(rival_character))
	mode = new_mode; human_mark = mark; page = "game"; overlay = ""; _debug_capture = false
	game.new_game(); board.game = game; board.clear_effects(); board.hint_move = Vector2i(-1,-1)
	thinking = false; hint_busy = false; _result_shown = false; match_seconds = 0; message = ""; online_sequence = 0
	_refresh_labels(); _rebuild()
	sound.clear_announcer()
	if present: _begin_versus()
	else: _schedule_ai(); _announce("ready")
func _schedule_ai():
	if _debug_capture or game.status != 0 or not overlay.is_empty() or (cinematic.active and cinematic.kind == "versus"): return
	var should = mode == "computer" and game.turn != human_mark
	should = should or (mode == "online" and demo_rival != null and remote_ready and game.turn != human_mark)
	if should:
		thinking = true; thinking_age = 0
		ai.begin(game,str(settings.values.difficulty),ai_seed+game.history.size()*17)
func play_cell(b: int, c: int) -> bool:
	if cinematic.active and cinematic.kind == "versus": return false
	if page != "game" or not overlay.is_empty() or thinking or game.status != 0 or _input_beat > 0: return false
	if mode == "computer" and game.turn != human_mark: return false
	if mode == "online":
		if not remote_ready or game.turn != human_mark or not game.is_legal(b,c): _invalid(b); return false
		transport.send_move(b,c,online_sequence+1); return true
	return _apply_move(b,c)
func _apply_move(b: int, c: int) -> bool:
	var previous = Announcer.snapshot(game)
	var player: int = game.turn
	var pan = -.35 if player == human_mark else .35
	var before: int = game.owners[b] if b >= 0 and b < 9 else 0
	if not game.play(b,c): _invalid(b); return false
	message = ""; hint_busy = false
	board.notify_move(b,c); sound.cue("place_x" if player == 1 else "place_o",pan)
	if game.active_board >= 0: sound.cue("route",(game.active_board%3-1)*.35)
	if before == 0 and game.owners[b] != 0:
		board.start_claim(b,game.owners[b]); sound.cue("claim_x" if player == 1 else "claim_o",pan); _input_beat = .16 if not board.reduced_motion else .05
		if game.owners[b] in [1,2] and game.status == 0:
			cinematic.show_scene("pop",hero_for(player),hero_for(3-player),player,layout,b)
			sound.stinger(Roster.audio_index(hero_for(player)),"stab",pan)
			if field_heroes.has(player): field_heroes[player].set_clip("mark_push")
			if player == human_mark and field_heroes.has("panel"): field_heroes.panel.set_clip("score_flash")
	if game.status != 0:
		var line = game.big_lines[0] if not game.big_lines.is_empty() else []
		board.start_win(line,game.status); thinking = false
		if game.status == 3: sound.cue("draw")
		elif mode == "local": sound.cue("victory")
	var line_id = Announcer.detect(previous,Announcer.snapshot(game))
	if mode == "local" and game.status in [1,2]: line_id = "nineweave"
	_announce(line_id)
	if game.status in [1,2] and mode != "local":
		var result_id = "victory" if game.status == human_mark else "defeat"
		sound.announce(result_id,result_id)
	_react_to_move(previous,player,b)
	_refresh_labels(); _save_match(); _refresh_history(); _schedule_ai()
	return true
func _react_to_move(previous: Dictionary, mover: int, board_index: int):
	var claimed = previous.owners[board_index] == 0 and game.owners[board_index] == mover
	var threats = Announcer.threats(Array(game.owners),mover)
	var mask: int = game.x_masks[board_index] if mover == 1 else game.o_masks[board_index]
	var other_mask: int = game.o_masks[board_index] if mover == 1 else game.x_masks[board_index]
	var good = false
	for line_mask in Rules.MASKS:
		var occupied = mask & line_mask
		if occupied != 0 and (occupied & (occupied-1)) != 0 and occupied != line_mask and (other_mask & line_mask) == 0: good = true
	for key in field_heroes:
		var mark: int = human_mark if key is String else int(key)
		var own = mark == mover
		var event = "own_move" if own else "opponent_move"
		if game.status in [1,2]: event = "win" if game.status == mark else "loss"
		elif not own and not threats.is_empty(): event = "near_loss"
		elif claimed:
			if own:
				event = "comeback" if previous.owners.count(mark) < previous.owners.count(3-mark) or not Announcer.threats(previous.owners,3-mark).is_empty() else "own_claim"
			else: event = "opponent_claim"
		elif not own and good: event = "opponent_good"
		field_heroes[key].react(event)
func _announce(id: String):
	if id.is_empty(): return
	if id == "ready": sound.clear_announcer()
	sound.announce(id)
	if not sound.enabled: callout.show_callout(id)
func _invalid(b: int):
	sound.cue("invalid")
	board.invalid_board = b; board.invalid_age = 0; message = "Choose an empty cell in the glowing board."
func _refresh_labels():
	board.sync_last_move(mode == "local",human_mark)
	turn_label = "Turn: "+("X" if game.turn == 1 else "O")
	active_label = "Active Board: "+("Any" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board])
	if game.status != 0:
		turn_label = "Draw" if game.status == 3 else ("X" if game.status == 1 else "O")+" wins"
		active_label = result_line()
func side_name(mark: int) -> String:
	if mark == human_mark and mode != "local": return str(settings.values.player_name)
	if mode == "local": return "PLAYER 1" if mark == human_mark else "PLAYER 2"
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
	# Round 3e: Undo exists only against the computer (spec item 1).
	if mode == "online": message = "Online moves are final. Start another room to play again."; return false
	if mode != "computer": return false
	thinking = false; hint_busy = false; sound.clear_announcer(); callout.callout = ""
	var did = game.undo()
	if mode == "computer" and did and game.turn != human_mark and not game.history.is_empty(): game.undo()
	board.clear_effects(); board.hint_move = Vector2i(-1,-1); _result_shown = false; overlay = ""; _input_beat = 0; cinematic.clear(); _spotlight_done = false
	_refresh_labels(); _save_match(); _rebuild(); _schedule_ai()
	return did
func request_hint():
	if game.status != 0 or thinking or not settings.values.show_hints: return
	if mode == "online": message = "Hints are disabled in online games."; return
	if mode != "computer": return
	hint_ai.begin(game,"Hard",444+game.history.size()); hint_busy = true; _hint_ply = game.history.size()
func _save_match():
	if mode == "computer" and page == "game" and not _debug_capture:
		settings.saved_game = {"state":game.serialize(),"human":human_mark,"seconds":match_seconds,"character":profile.data.character_id,"rival_character":rival_character} if game.status == 0 else {}
		settings.save()
func resume_game():
	if settings.saved_game.is_empty(): return
	if not game.deserialize(settings.saved_game.state): settings.saved_game = {}; return
	mode = "computer"; _debug_capture = false; human_mark = int(settings.saved_game.human)
	var seconds = settings.saved_game.get("seconds",0)
	match_seconds = maxf(0,float(seconds)) if seconds is int or seconds is float else 0.0
	rival_character = str(settings.saved_game.get("rival_character","auric_rex"))
	# A hand-edited/legacy save may name an unknown hero or the player's own; pick a valid rival.
	if not Roster.valid(rival_character) or rival_character == str(profile.data.character_id):
		rival_character = "auric_rex" if profile.data.character_id != "auric_rex" else "vesper_vale"
	page = "game"; overlay = ""; board.clear_effects(); _result_shown = false; _spotlight_done = false; cinematic.clear()
	_refresh_labels(); _rebuild(); _schedule_ai()
func go_home():
	_pending_game = {}; _select_player = 0
	sound.clear_announcer()
	_save_match(); _leave_online(); thinking = false; page = "title"; overlay = ""; board.clear_effects(); cinematic.clear(); callout.callout = ""; _rebuild()
func show_settings():
	# A non-modal claim pop (z 30) would paint over the modal; it is only flavour, drop it.
	if cinematic.active and cinematic.kind == "pop": cinematic.clear()
	overlay = "settings"; thinking = false; _rebuild()
func _close_overlay():
	overlay = ""; _rebuild(); _schedule_ai()
func _leave_online():
	if is_instance_valid(demo_rival): demo_rival.leave(); demo_rival.queue_free()
	if is_instance_valid(transport): transport.leave(); transport.queue_free()
	demo_rival = null; transport = null; remote_ready = false
func request_online():
	_pending_game = {}; _select_player = 0; open_online()
func request_resume():
	if not profile.data.onboarded:
		_pending_game = {"mode":"resume","mark":human_mark}; open_character_select(); return
	resume_game()
func open_online():
	_leave_online(); message = ""; room_code = ""; _room_password = ""
	if not test_online_bypass and not _debug_capture and not account.store.complete():
		_show_onboarding("online"); return
	page = "online"; overlay = ""; online_state = "lobby"; _rebuild(); _refresh_lobby()
func _attach_transport(t):
	_leave_online(); transport = t
	if t is HTTP: t.device_token = account.store.data.device_token
	add_child(t)
	lobby_timer.stop(); online_api.cancel_all(); _lobby_pending = false
	t.player_name = str(settings.values.player_name)
	t.character_id = str(profile.data.character_id)
	t.character_received.connect(func(mark,id):
		if mark != t.seat: rival_character = id)
	t.room_created.connect(func(code): room_code = code; online_state = "waiting"; message = "Waiting for opponent…"; _rebuild())
	t.joined.connect(func(code,seat): room_code = code; human_mark = seat)
	t.opponent_joined.connect(_online_ready)
	t.rematch_changed.connect(func(_local,_remote): _result_controls_refresh())
	t.match_started.connect(func(seat,_round):
		human_mark = seat
		if remote_ready: _reset_online_match())
	t.move_received.connect(_receive_move)
	t.state_received.connect(_receive_state)
	t.opponent_left.connect(func(): remote_ready = false; thinking = false; message = "Your opponent has left the room."; _rebuild())
	t.error.connect(func(msg): message = msg; _rebuild())
	if t is HTTP: t.room_updated.connect(_online_room_update)
func create_online(demo: bool = false, private_game: bool = false, password: String = ""):
	if not demo and not test_online_bypass and not account.store.complete(): _show_onboarding("online"); return
	if private_game and (password.is_empty() or password.length() > 64):
		message = "Use a private-room password with 1–64 characters."; _online_status(); return
	_attach_transport(Loopback.new() if demo else HTTP.new())
	if transport is HTTP: transport.private_room = private_game; transport.password = password
	transport.create_room()
func join_online(code: String, demo: bool = false, password: String = ""):
	if not demo and not test_online_bypass and not account.store.complete(): _show_onboarding("online"); return
	_attach_transport(Loopback.new() if demo else HTTP.new())
	if transport is HTTP: transport.password = password
	transport.join_room(code)
func invite_demo_rival():
	if not transport is Loopback: return
	demo_rival = Loopback.new(); demo_rival.player_name = "Legend · Demo"
	demo_rival.character_id = "auric_rex" if profile.data.character_id != "auric_rex" else "vesper_vale"
	add_child(demo_rival)
	demo_rival.join_room(room_code)
func _online_ready():
	remote_ready = true; opponent_name = transport.remote_name; rival_character = transport.remote_character_id
	human_mark = transport.seat; _reset_online_match()
func _reset_online_match():
	_spotlight_done = false; cinematic.clear(); _debug_capture = false
	game.new_game(); mode = "online"; page = "game"; overlay = ""; online_sequence = 0
	board.clear_effects(); thinking = false; _result_shown = false; match_seconds = 0; message = ""
	_refresh_labels(); _rebuild(); _begin_versus()
func _receive_move(b: int, c: int, seq: int):
	if seq <= online_sequence: return
	if seq != online_sequence+1: message = "Resynchronizing room…"; return
	if _apply_move(b,c): online_sequence = seq
func _receive_state(state: Dictionary, seq: int):
	if seq == online_sequence and state.get("cells","") == game.serialize().cells: return
	if game.deserialize(state):
		online_sequence = seq; board.clear_effects(); _refresh_labels(); _refresh_history(); _schedule_ai()
		if game.status != 0:
			board.start_win(game.big_lines[0] if not game.big_lines.is_empty() else [],game.status)

func _online_room_update(data: Dictionary):
	# Forfeits/timeouts are authoritative full-match results, outside board mechanics.
	var result = data.get("result")
	if data.get("status","") in ["finished","closed"] and result is Dictionary and game.status == 0:
		var winner = int(result.get("winner",-1))
		if winner in [0,1,2]:
			game.status = 3 if winner == 0 else winner; thinking = false
			board.start_win([],game.status); _refresh_labels()
	if data.get("status","") == "closed" and page == "online":
		message = "This room is closed. Return to the lobby to play again."; _online_status()
func _show_onboarding(destination: String):
	_leave_online(); _onboarding_destination = destination; page = "onboarding"; overlay = ""
	_onboarding_name = account.store.data.screen_name; message = ""; cinematic.clear(); _rebuild()
func _account_name(value: String):
	settings.set_value("player_name",value); profile.data.display_name = value; profile.save()
	if overlay == "settings": message = "Screen name saved."; _settings_name_status()
func _account_player(player: Dictionary):
	var id = str(player.get("last_hero_id",""))
	if not _hero_changed and Roster.valid(id):
		profile.data.character_id = Roster.canonical_id(id); profile.save()
		if page == "character_select": _hero_focus = profile.data.character_id; _rebuild()
func _account_completed():
	message = ""
	if page != "onboarding": return
	if _onboarding_destination == "online": open_online()
	else: go_home()
func _account_error(value: String):
	message = value
	if page == "onboarding":
		if "not available" in value or "configured" in value or "reach" in value:
			message = "Online server not available. You can still play vs Computer or Pass & Play."
		if is_instance_valid(online_view):
			online_view.set_status(message)
			if online_view.controls.has("create_name"): online_view.controls.create_name.disabled = false
	elif overlay == "settings": _settings_name_status()
	elif page == "online": _online_status()
func _settings_name_status():
	if controls.has("name_status"): controls.name_status.text = message
func _online_status():
	if is_instance_valid(online_view): online_view.set_status(message)
func _refresh_lobby():
	if test_online_bypass or _debug_capture or page != "online" or online_state != "lobby" or _lobby_pending: return
	_lobby_pending = true
	online_api.submit("/rooms",HTTPClient.METHOD_GET,{},"lobby",account.store.data.device_token)
func open_leaderboard():
	_leave_online(); page = "leaderboard"; overlay = ""; message = "Loading match records…"; _rebuild()
	if not test_online_bypass: online_api.submit("/leaderboard",HTTPClient.METHOD_GET,{},"leaderboard",account.store.data.device_token)
func _online_response(operation: String, _response: int, data: Dictionary, problem: String):
	if operation == "lobby":
		_lobby_pending = false
		if page != "online" or online_state != "lobby": return
		message = problem if not problem.is_empty() else "Public games refresh automatically."
		if problem.is_empty(): public_rooms = data.get("rooms",[]) if data.get("rooms") is Array else []
		if is_instance_valid(online_view): online_view.set_rooms(public_rooms); online_view.set_status(message)
	elif operation == "leaderboard" and page == "leaderboard":
		message = problem
		if problem.is_empty():
			var mapped = leaderboard_payload(data); leaderboard_players = mapped.players; leaderboard_me = mapped.me
		_rebuild()
static func leaderboard_payload(data: Dictionary) -> Dictionary:
	# Public UI deliberately selects only full-match wins; internal boards_won is omitted.
	var players: Array = []
	if data.get("players") is Array:
		for player in data.players:
			if player is Dictionary:
				var rank = player.get("rank")
				players.append({"rank":int(rank) if rank != null else null,"screen_name":str(player.get("screen_name","Player")),"matches_won":int(player.get("matches_won",0))})
	var me: Dictionary = {}
	if data.get("me") is Dictionary:
		for key in ["rank","screen_name","matches_won","matches_played"]: me[key] = data.me.get(key,0 if key in ["matches_won","matches_played"] else null)
		for key in ["matches_won","matches_played"]: me[key] = int(me[key])
		if me.rank != null: me.rank = int(me.rank)
	return {"players":players,"me":me}
func _online_action(kind: String, value: String):
	sound.cue("ui")
	match kind:
		"home": go_home()
		"lobby": open_online()
		"leaderboard": open_leaderboard()
		"register":
			account.create_screen_name(_onboarding_name if value.is_empty() else value)
			if is_instance_valid(online_view) and online_view.controls.has("create_name"): online_view.controls.create_name.disabled = account.busy
		"create_public": create_online()
		"private": online_state = "private"; message = ""; _rebuild()
		"create_private": create_online(false,true,_room_password)
		"join", "join_private": join_online(_room_entry if value.is_empty() else value,false,_room_password if kind == "join_private" else "")
		"demo": create_online(true)
		"invite": invite_demo_rival()
		"copy": DisplayServer.clipboard_set(room_code); message = "Room code copied."; _online_status()
func _online_draft(kind: String, value: String):
	match kind:
		"screen_name": _onboarding_name = value
		"room_code": _room_entry = value
		"password": _room_password = value
func _build_online_screen(s: Vector2):
	online_view = OnlineScreen.new(); online_view.size = s
	online_view.screen = page if page in ["onboarding","leaderboard"] else online_state
	online_view.screen_name = _onboarding_name if page == "onboarding" else str(account.store.data.screen_name)
	online_view.room_code = room_code if online_state == "waiting" else _room_entry
	online_view.password = _room_password; online_view.status = message; online_view.rooms = public_rooms
	online_view.players = leaderboard_players; online_view.me = leaderboard_me
	online_view.local_demo = transport is Loopback
	online_view.private_room = transport.private_room if transport is HTTP else false
	online_view.busy = account.busy
	online_view.action.connect(_online_action); online_view.draft_changed.connect(_online_draft)
	add_child(online_view); ui_nodes.append(online_view); controls.merge(online_view.controls)

func _clear_nodes():
	for n in ui_nodes:
		if is_instance_valid(n): remove_child(n); n.queue_free()
	ui_nodes.clear(); controls.clear(); online_view = null; history_label = null; _result_bases.clear(); field_heroes.clear(); hero_select = null
func _button(id: String, caption: String, rect: Rect2, callback: Callable, accent: bool = false, icon: String = ""):
	var b = OrnateButton.new(); b.name = id; b.caption = caption; b.tooltip_text = caption if not caption.is_empty() else id.capitalize()
	b.icon_kind = icon
	b.position = rect.position; b.size = rect.size; b.accent = accent
	b.font_size = int(clampf(rect.size.y*.4,17,26))
	b.pressed.connect(func(): sound.cue("ui")); b.pressed.connect(callback); add_child(b); ui_nodes.append(b); controls[id] = b
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
func _volume_slider(key: String, caption: String, rect: Rect2):
	var slider = HSlider.new(); slider.name = key; slider.position = rect.position+Vector2(rect.size.x*.43,0); slider.size = Vector2(rect.size.x*.57,44)
	slider.min_value = 0; slider.max_value = 1; slider.step = .01; slider.value = settings.values[key]
	slider.value_changed.connect(func(value): settings.set_value(key,value); _apply_preferences())
	add_child(slider); ui_nodes.append(slider); controls[key] = slider
	var label = Label.new(); label.position = rect.position; label.size = Vector2(rect.size.x*.41,44); label.text = caption
	label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",18); label.add_theme_color_override("font_color",P.PALE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label); ui_nodes.append(label)
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
	elif page == "character_select":
		hero_select = HeroSelect.new(); hero_select.size = s; hero_select.hinge = layout.hinge
		hero_select.selected_id = _hero_focus if not _hero_focus.is_empty() else str(profile.data.character_id)
		hero_select.display_name = _name_draft if not _name_draft.is_empty() else str(profile.data.display_name)
		hero_select.reduced_motion = board.reduced_motion
		hero_select.heading = "PLAYER %d · CHOOSE HERO" % _select_player if _select_player > 0 else "CHOOSE YOUR HERO"
		hero_select.blocked_id = str(profile.data.character_id) if _select_player == 2 else ""
		if _select_player > 0: hero_select.display_name = "PLAYER %d" % _select_player
		hero_select.focused.connect(func(id): _hero_changed = true; _hero_focus = id; sound.prepare_character(Roster.audio_index(id)); sound.cue("ui",-.35))
		hero_select.name_changed.connect(func(value): _name_draft = value)
		hero_select.confirmed.connect(_confirm_hero)
		hero_select.back.connect(func(): _pending_game = {}; go_home())
		add_child(hero_select); ui_nodes.append(hero_select)
		if _select_player > 0: hero_select.field.editable = false
	elif page == "game":
		var hdr: Rect2 = layout.header
		var big = layout.mode == "landscape"
		var hb = 52.0 if big else 44.0
		_button("home","" if not big else "",Rect2(hdr.position,Vector2(hb,hb)),go_home,false,"home" if big else "back")
		_button("settings","⚙",Rect2(Vector2(hdr.end.x-hb,hdr.position.y),Vector2(hb,hb)),show_settings)
		var cr: Rect2 = layout.controls
		# Round 3e: Undo/Hint only vs the computer; the X/O tiles stay centred without them.
		if mode != "computer": pass
		elif layout.mode in ["phone_portrait","tablet_portrait"]:
			var unit = minf(cr.size.x/4-9,84 if layout.mode == "tablet_portrait" else 72)
			_button("undo","Undo",Rect2(cr.position,Vector2(unit,cr.size.y)),undo_move,false,"undo")
			_button("hint","Hint",Rect2(cr.end-Vector2(unit,cr.size.y),Vector2(unit,cr.size.y)),request_hint,false,"hint")
		else:
			_button("undo","Undo",Rect2(cr.position,Vector2(cr.size.x*.48,cr.size.y)),undo_move,false,"undo")
			_button("hint","Hint",Rect2(cr.position+Vector2(cr.size.x*.52,0),Vector2(cr.size.x*.48,cr.size.y)),request_hint,false,"hint")
		if controls.has("hint"): controls.hint.disabled = not settings.values.show_hints
		if layout.has("history"): _create_history(layout.history)
		_create_field_heroes()
	elif page in ["online","onboarding","leaderboard"]: _build_online_screen(s)
	if is_instance_valid(lobby_timer):
		if page == "online" and online_state == "lobby" and not test_online_bypass and not _debug_capture:
			if lobby_timer.is_stopped(): lobby_timer.start()
		else:
			lobby_timer.stop(); online_api.cancel_all(); _lobby_pending = false
	if overlay == "result": _winner_controls(s)
	elif not overlay.is_empty(): _overlay_controls(s)
	queue_redraw()
func _create_field_heroes():
	var r: Rect2 = layout.players
	for mark in [human_mark,3-human_mark]:
		var hero_r: Rect2
		var is_vertical = layout.mode == "landscape"
		if is_vertical:
			var hh = (r.size.y-52*_u())*.5
			var y = r.position.y if mark == human_mark else r.end.y-hh
			hero_r = Rect2(r.position.x+6,y+8,r.size.x-12,hh*.62)
		else:
			var gap = minf(46,r.size.x*.12); var width = (r.size.x-gap)*.5
			var rr = Rect2(r.position,Vector2(width,r.size.y)) if mark == human_mark else Rect2(r.end.x-width,r.position.y,width,r.size.y)
			var radius = minf(rr.size.y*.5,rr.size.x*.24)*.82
			var cx = rr.position.x+radius if mark == human_mark else rr.end.x-radius
			hero_r = Rect2(Vector2(cx-radius,rr.get_center().y-radius),Vector2.ONE*radius*2)
		var rig = HeroRig.new(); rig.hero_id = hero_for(mark); rig.side = mark; rig.facing = 1 if mark == human_mark else -1
		rig.bust = true; rig.position = hero_r.position; rig.size = hero_r.size; rig.reduced_motion = board.reduced_motion
		add_child(rig); ui_nodes.append(rig)
		var corner_r: Rect2 = layout.hero_player if mark == human_mark else layout.hero_opponent
		var hosted = mark == human_mark and not str(layout.get("hero_player_host","")).is_empty()
		# Scorecard portraits are frozen while a corner (or the Duo panel) reacts. A side
		# without readable corner space reacts live in its own scorecard instead.
		rig.frozen = hosted or corner_r.size.y >= Layout.MIN_CORNER
		if hosted: continue
		if not rig.frozen:
			field_heroes[mark] = rig; continue
		var corner = HeroRig.new(); corner.hero_id = hero_for(mark); corner.side = mark
		corner.facing = 1 if mark == human_mark else -1; corner.bust = true
		corner.position = corner_r.position; corner.size = corner_r.size; corner.reduced_motion = board.reduced_motion
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(corner); ui_nodes.append(corner); field_heroes[mark] = corner
	if layout.has("character"):
		var rig = HeroRig.new(); rig.hero_id = hero_for(human_mark); rig.side = human_mark
		rig.position = layout.character.position+Vector2(4,24); rig.size = layout.character.size-Vector2(8,28)
		rig.bust = true; rig.reduced_motion = board.reduced_motion
		add_child(rig); ui_nodes.append(rig)
		if layout.get("hero_player_host","") == "character": field_heroes[human_mark] = rig
		else: field_heroes["panel"] = rig
	_update_hero_states()
func hero_state(mark: int) -> String:
	var delta_score = game.owners.count(mark)-game.owners.count(3-mark)
	return "idle_power" if delta_score > 0 else ("idle_stagger" if delta_score < 0 else "idle")
func _update_hero_states():
	for key in field_heroes:
		var rig = field_heroes[key]; var mark = human_mark if key is String else int(key)
		if rig.reaction.remaining > 0: continue
		if rig.clip in ["mark_push","score_flash"] and rig.clip_age < .8: continue
		rig.set_clip(hero_state(mark))
func _title_controls(s: Vector2):
	_button("hero","Hero",Rect2(s.x-100,12,84,44),open_character_select)
	var items = [["computer","Play vs Computer",func(): overlay = "setup"; _rebuild(),true],["online","Play Online",request_online,false],["local","Pass & Play",func(): request_game("local"),false]]
	if not settings.saved_game.is_empty(): items.append(["resume","Resume Journey",request_resume,false])
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
		lines.append("%d. %s > %s · %s" % [i+1,"Crystal X" if m.player == 1 else "Gold O",Rules.BOARD_NAMES[m.board],Rules.BOARD_NAMES[m.cell]])
	history_label.text = "\n".join(lines) if not lines.is_empty() else "Your story begins here."
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
		_button("choose_x","Play first",Rect2(r.position.x+24,y+(60 if short else 88),pw-48,48 if short else 56),func(): request_game("computer",1),true,"x")
		_button("choose_o","Play second",Rect2(r.position.x+24,y+(118 if short else 156),pw-48,48 if short else 56),func(): request_game("computer",2),false,"o")
	elif overlay == "settings":
		var sw = (pw-72)*.5 if short else pw-48
		var lx = r.position.x+24
		var rx = r.position.x+pw*.5+12 if short else lx
		var y = r.position.y+70
		for pair in [["sound","Sound"],["reduced_motion","Reduced motion"],["show_hints","Show hints"]]:
			var key = pair[0]; var caption = pair[1]
			_button("toggle_"+key,caption+"    "+("ON" if settings.values[key] else "OFF"),Rect2(lx,y,sw,44),func(): settings.set_value(key,not settings.values[key]); _apply_preferences(); _rebuild(),settings.values[key])
			y += 50
		if short: y = r.position.y+70
		for pair in [["sfx_volume","SFX"],["announcer_volume","Announcer"]]:
			_volume_slider(pair[0],pair[1],Rect2(rx,y,sw,44)); y += 50
		_button("difficulty","AI: "+str(settings.values.difficulty),Rect2(rx,y,sw,44),func():
			var levels = ["Easy","Medium","Hard"]; settings.set_value("difficulty",levels[(levels.find(settings.values.difficulty)+1)%3]); _rebuild())
		y += 52
		var name_field = _field("player_name","Screen name",Rect2(rx,y,sw,44),str(settings.values.player_name))
		name_field.max_length = 24
		if not test_online_bypass and not str(account.store.data.device_token).is_empty():
			name_field.size.x = sw-90
			_button("save_name","Save",Rect2(rx+sw-82,y,82,44),func(): account.rename(str(controls.player_name.text)))
			name_field.text_submitted.connect(account.rename)
			var notice = Label.new(); notice.position = Vector2(rx,y+46); notice.size = Vector2(sw,34)
			notice.text = message; notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			notice.add_theme_font_override("font",P.SANS); notice.add_theme_font_size_override("font_size",16); notice.add_theme_color_override("font_color",P.PALE)
			add_child(notice); ui_nodes.append(notice); controls["name_status"] = notice
		else:
			name_field.text_changed.connect(func(value):
				var clean = value.strip_edges().left(24)
				settings.set_value("player_name",clean); profile.data.display_name = clean; profile.save())
		_button("done","Return",Rect2(lx,r.end.y-62,sw*.48,44),_close_overlay,true)
		_button("cosmetics","Cosmetics",Rect2(lx+sw*.52,r.end.y-62,sw*.48,44),func(): overlay = "cosmetics"; _rebuild())
	elif overlay == "cosmetics":
		var x = r.position.x+24; var y = r.position.y+74; var w = r.size.x-48
		_button("background_theme","Sky: "+Themes.item(settings.values.background_theme,Themes.BACKGROUNDS).name,Rect2(x,y,w,44),func():
			settings.set_value("background_theme",Themes.next(settings.values.background_theme,Themes.BACKGROUNDS)); _apply_preferences(); _rebuild())
		_button("board_theme","Board: "+Themes.item(settings.values.board_theme,Themes.BOARDS).name,Rect2(x,y+50,w,44),func():
			settings.set_value("board_theme",Themes.next(settings.values.board_theme,Themes.BOARDS)); _apply_preferences(); _rebuild())
		_button("classic","Restore crystal",Rect2(x,y+100,w,44),func():
			settings.set_value("background_theme","crystal"); settings.set_value("board_theme","crystal"); _apply_preferences(); _rebuild())
		_button("profile_hero","Hero: "+Roster.get_hero(str(profile.data.character_id)).name,Rect2(x,y+150,w,44),func(): _pending_game = {}; _select_player = 0; open_character_select())
		_button("done","Settings",Rect2(x,r.end.y-62,w,44),func(): overlay = "settings"; _rebuild(),true)

	elif overlay == "how":
		_button("done","I’m ready",Rect2(r.position.x+24,r.end.y-70,pw-48,48),_close_overlay,true)
	elif overlay == "result":
		_button("again","Play Again",Rect2(r.position.x+26,r.end.y-122,pw-52,50),func():
			if mode == "online": open_online()
			else: start_game(mode,human_mark,true),true)
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
func _draw_hinge(node: Control):
	if layout.is_empty() or layout.hinge.size.x <= 0: return
	node.draw_rect(layout.hinge,Color("01040b"))
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
	if layout.info.size.y > 0: _draw_info(layout.info,layout.mode == "landscape",u)
	if layout.has("minimap"): _draw_minimap(layout.minimap)
	if layout.has("stats"): _draw_stats(layout.stats)
	if layout.has("character"):
		P.panel(self,layout.character,false,1,true)
		P.text(self,Roster.get_hero(hero_for(human_mark)).name.to_upper(),Rect2(layout.character.position+Vector2(4,2),Vector2(layout.character.size.x-8,20)),12,P.PALE,P.SERIF)
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
	if layout.mode == "phone_portrait":
		_draw_phone_lane(layout.message)
		return
	if not message.is_empty():
		P.text(self,message,layout.message,12,P.GOLD)
	if hint_busy: P.text(self,"Reading the threads…",Rect2(layout.board.position.x,layout.board.end.y-22,layout.board.size.x,20),14,P.PALE)
## Round 3e phone portrait has no info panel: one slim lane under the board carries
## messages, "Reading the threads…", the result, else a quiet "Play X in Center" hint.
func _draw_phone_lane(r: Rect2):
	var fs = int(minf(13,r.size.y-2))
	if not message.is_empty(): P.text(self,fit_label(message,r.size.x,fs),r,fs,P.GOLD)
	elif hint_busy: P.text(self,"Reading the threads…",r,fs,P.PALE)
	elif game.status != 0: P.text(self,result_line(),r,fs,P.mark_color(game.status) if game.status != 3 else P.MUTED)
	else:
		var where = "any open board" if game.active_board == -1 else Rules.BOARD_NAMES[game.active_board]
		P.text(self,"Play "+("X" if game.turn == 1 else "O")+" in "+where,r,fs,Color(P.MUTED,.9))
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
## Circular gold-framed medallion: portrait (rival) or bevelled mark, crown and thinking ring.
func _medallion(center: Vector2, radius: float, mark: int, _portrait: bool, active: bool, rival_thinking: bool):
	var col = P.mark_color(mark)
	if active:
		P.halo(self,center,radius*1.9,Color(col,.28+.12*sin(clock*TAU/1.2)))
	draw_circle(center,radius,Color("020a16"))
	P.halo(self,center,radius*.95,Color(col,.18))
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
		P.halo(self,center,radius*1.7,Color(col,.22))
		if active: P.crown(self,center-Vector2(0,radius+12*u),.9*u)
		var name_y = r.position.y+r.size.y*.64
		var shown = "Thinking"+".".repeat(1+int(clock*3)%3) if rival_thinking else caption
		P.text(self,shown,Rect2(r.position.x+6,name_y,r.size.x-12,30*u),int(22*u),P.WHITE)
		var ir = 12*u
		P.mark(self,Vector2(r.get_center().x,name_y+30*u+ir+4),ir,mark)
		P.text(self,"%d claimed" % game.owners.count(mark),Rect2(r.position.x+6,name_y+30*u+ir*2+10,r.size.x-12,24*u),int(17*u),col if mark == 1 else P.PALE)
		return
	var right = style == "right"
	var g = scorecard_geometry(r,right)
	var radius: float = g.radius; var center: Vector2 = g.center
	P.panel(self,g.body,active,1,r.size.y >= 40)
	var shown = "Thinking"+".".repeat(1+int(clock*3)%3) if rival_thinking else caption
	var name_r: Rect2 = g.name
	P.text(self,fit_label(shown,name_r.size.x,17 if r.size.y < 70 else 20),name_r,17 if r.size.y < 70 else 20,P.WHITE,P.SANS,HORIZONTAL_ALIGNMENT_CENTER)
	var c = claimed_line(game.owners.count(mark),g.line.size.x,r.size.y)
	var ly = g.line.get_center().y
	var lx = g.line.get_center().x-c.width*.5
	if c.icon > 0: P.mark(self,Vector2(lx+c.icon,ly),c.icon,mark)
	P.text(self,c.text,Rect2(lx+c.icon*2.6,ly-10,c.width-c.icon*2.6+6,20),c.fs,col if mark == 1 else P.PALE,P.SANS,HORIZONTAL_ALIGNMENT_LEFT)
	_medallion(center,radius,mark,portrait,active,rival_thinking)
	# Crown rides above the name, clear of the corner header buttons.
	if active: P.crown(self,Vector2(g.text.get_center().x,r.position.y+1),.5)
## Round 3c: horizontal scorecard geometry. The name and "claimed" lanes end before the
## medallion's outer ring (radius + ring stroke + gap), so text never runs under it.
static func scorecard_geometry(r: Rect2, right: bool) -> Dictionary:
	var radius = minf(r.size.y*.5,r.size.x*.24)
	var center = Vector2(r.end.x-radius*.82 if right else r.position.x+radius*.82,r.get_center().y)
	var body = r.grow_individual(-radius*.6 if not right else 0,0,-radius*.6 if right else 0,0)
	var ring = radius+maxf(2.5,radius*.13)*.5+1.25+3
	var x0 = body.position.x+8 if right else center.x+ring
	var x1 = center.x-ring if right else body.end.x-8
	var text_r = Rect2(x0,r.position.y+3,x1-x0,r.size.y-6)
	return {"radius":radius,"center":center,"body":body,"ring":ring,"text":text_r,
		"name":Rect2(text_r.position,Vector2(text_r.size.x,text_r.size.y*.52)),
		"line":Rect2(text_r.position.x,text_r.position.y+text_r.size.y*.74-10,text_r.size.x,20)}
## Name shrinks to fit (down to 10 px), then truncates with an ellipsis.
static func fit_label(value: String, width: float, font_size: int) -> String:
	if P.text_width(value,10)+4 <= width or value.length() <= 1: return value
	var cut = value
	while cut.length() > 1 and P.text_width(cut+"…",10)+4 > width: cut = cut.substr(0,cut.length()-1)
	return cut.strip_edges()+"…"
## "N claimed" with its mark: shrink, then drop the mark, then drop the word.
static func claimed_line(count: int, width: float, card_h: float) -> Dictionary:
	var ir = clampf(card_h*.13,6,10)
	var lfs = 14 if card_h < 70 else 16
	for option in [["%d claimed" % count,ir],["%d claimed" % count,0.0],[str(count),ir]]:
		for fs in range(lfs,10,-1):
			var w = P.text_width(option[0],fs)+option[1]*2.6
			if w+4 <= width: return {"text":option[0],"icon":option[1],"fs":fs,"width":w}
	return {"text":str(count),"icon":0.0,"fs":11,"width":P.text_width(str(count),11)}
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
	pass # OnlineScreen owns its chrome.
func _draw_modal(node: Control):
	var s: Vector2 = layout.size; var r = _modal_rect
	var short = s.x > s.y and s.y < 500
	if overlay == "result":
		_draw_result(node,r,short); return
	node.draw_rect(Rect2(Vector2.ZERO,s),Color(.001,.005,.015,.88))
	P.panel(node,r,false,1,true); P.outline(node,r.grow(-8),P.GOLD.darkened(.4),1)
	var heading = {"settings":"SETTINGS","setup":"CHOOSE YOUR PATH","how":"HOW TO PLAY","cosmetics":"LOCAL COSMETICS"}.get(overlay,"")
	P.text(node,heading,Rect2(r.position+Vector2(20,23),Vector2(r.size.x-72,44)),25,P.PALE,P.SERIF,HORIZONTAL_ALIGNMENT_CENTER,.6)
	if overlay == "setup":
		if not short: P.text(node,"Choose difficulty, then your sigil",Rect2(r.position+Vector2(20,65),Vector2(r.size.x-40,25)),17,P.MUTED)
		if not short: P.text(node,"X always weaves the first thread.",Rect2(r.position.x+20,r.end.y-48,r.size.x-40,24),16,P.GOLD)
	elif overlay == "settings":
		pass
		if not short: P.text(node,"Preferences saved on this device.",Rect2(r.position.x+24,r.end.y-93,r.size.x-48,24),14,P.MUTED)
	elif overlay == "cosmetics":
		if not short: P.text(node,"Only your view changes. Heroes are shared.",Rect2(r.position.x+24,r.position.y+242,r.size.x-48,34),17,P.MUTED)
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
	else: P.mark(node,ec,30,game.status,a,2,true)
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
	page = "game"; mode = as_mode; human_mark = 1; overlay = ""; board.clear_effects(); _result_shown = false; _spotlight_done = false; cinematic.clear(); callout.callout = ""
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
	if scenario in ["onboarding","online_lobby","online_private","online_leaderboard","online_unranked"]:
		_leave_online(); cinematic.clear(); overlay = ""; message = ""
		_onboarding_name = ""; _room_entry = ""; _room_password = ""
		public_rooms = [{"code":"N9ABC","host_name":"Dana","host_hero":"aiden_vortex"},{"code":"SKY42","host_name":"Patrick","host_hero":"erick_comet"}]
		leaderboard_players = [{"rank":1,"screen_name":"Dana","matches_won":12},{"rank":2,"screen_name":"Patrick","matches_won":8}]
		leaderboard_me = {"screen_name":"Weaver","rank":80,"matches_won":2,"matches_played":9}
		if scenario == "onboarding": page = "onboarding"
		elif scenario in ["online_leaderboard","online_unranked"]:
			page = "leaderboard"
			if scenario == "online_unranked": leaderboard_me = {"screen_name":"Weaver","rank":1,"matches_won":0,"matches_played":0}
		else:
			page = "online"; online_state = "private" if scenario == "online_private" else "lobby"
		_rebuild(); return
	if scenario in ["select_p1","select_p2","select_p3","select_p4"]:
		request_game("local"); _hero_focus = "vesper_vale"
		if scenario == "select_p2":
			_confirm_hero("vesper_vale","PLAYER 1"); _hero_focus = "ryan_blaze"; _rebuild()
		if is_instance_valid(hero_select):
			hero_select.set_page(int(scenario.right(1))-1)
			if scenario in ["select_p3","select_p4"]: hero_select.focus_hero(Roster.DATA[(int(scenario.right(1))-1)*8].id)
		return
	if scenario == "versus":
		profile.data.character_id = OS.get_environment("NW_HERO") if OS.has_environment("NW_HERO") else "vesper_vale"; profile.data.display_name = "Patrick"; settings.values.player_name = "Patrick"
		rival_character = OS.get_environment("NW_RIVAL") if OS.has_environment("NW_RIVAL") else "auric_rex"; start_game("computer",1,true,true)
		cinematic.seek(1.4); _debug_capture = true; return
	if scenario in ["winner","winner_cpu","draw"]:
		profile.data.character_id = OS.get_environment("NW_HERO") if OS.has_environment("NW_HERO") else "vesper_vale"; settings.values.player_name = "Patrick"; rival_character = OS.get_environment("NW_RIVAL") if OS.has_environment("NW_RIVAL") else "auric_rex"
		if scenario == "draw":
			var rows = ["XXXOO....","OOOXX....","XXXOO....","XXXOO....","OOOXX....","OOOXX....","OOOXX....","XXXOO....","XXXOO...."]
			var staged_draw = Rules.new(); staged_draw.deserialize({"v":1,"cells":"".join(rows),"turn":1,"active":-1,"history":[]})
			debug_load_position(staged_draw.serialize())
		else:
			var patterns: Array = []
			for i in range(9): patterns.append(".........")
			var result_mark = 2 if scenario == "winner_cpu" else 1
			patterns[0] = "OOOXX...." if result_mark == 2 else "XXXOO...."; patterns[1] = patterns[0]
			patterns[2] = "OO.XX...." if result_mark == 2 else "XX.OO...."
			var staged_winner = Rules.new(); staged_winner.deserialize({"v":1,"cells":"".join(patterns),"turn":result_mark,"active":2,"history":[]})
			debug_load_position(staged_winner.serialize())
			game.play(2,2)
		_refresh_labels(); _show_spotlight(); cinematic.age = progress*5; cinematic.buttons_shown = cinematic.age >= cinematic.buttons_at()
		cinematic.frozen = true; cinematic.pose(); _result_shown = true
		if cinematic.buttons_shown: overlay = "result"; _rebuild()
		return
	if scenario in ["character_select","lock_in"]:
		open_character_select(); _hero_focus = "vesper_vale"; _name_draft = "Weaver"; _rebuild()
		if scenario == "lock_in":
			cinematic.show_scene("lock_in",_hero_focus,"auric_rex",1,layout)
			cinematic.age = progress*cinematic.duration(); cinematic.frozen = true; cinematic.pose()
		return
	if scenario == "claim_pop":
		var m = _debug_stage(MIDGAME+CLAIM_TAIL)
		debug_preview_claim(m.x,game.owners[m.x],progress)
		cinematic.show_scene("pop",hero_for(1),hero_for(2),1,layout,m.x)
		cinematic.age = progress*cinematic.duration(); cinematic.frozen = true; cinematic.pose()
		return
	if scenario == "win_spotlight":
		_debug_stage(WIN_GAME); board.preview_win(game.big_lines[0],game.status,RESULT_AT)
		_show_spotlight(); cinematic.age = progress*cinematic.duration(); cinematic.frozen = true; cinematic.pose()
		return
	if scenario == "duo_panel":
		var ahead = Rules.new()
		for i in range(WIN_GAME.size()-1): ahead.play(WIN_GAME[i][0],WIN_GAME[i][1])
		debug_load_position(ahead.serialize())
		board.clear_effects(); _update_hero_states(); return
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
	if scenario in ["reaction","midgame_heads"]:
		field_heroes[human_mark].react("own_claim"); field_heroes[3-human_mark].react("opponent_claim")
		field_heroes[3-human_mark].advance(.3)
		for rig in field_heroes.values(): rig.frozen = true; rig.clip_age = .45; rig.pose(1.4)
	if scenario == "last_move":
		game.play(MIDGAME_REPLY[0],MIDGAME_REPLY[1]); _refresh_labels(); _rebuild()
		var next = game.legal_moves()[0]; game.play(next.x,next.y); _refresh_labels(); _rebuild()
		board.last_move_age = 1
	if scenario == "thinking":
		var m = MIDGAME_REPLY
		game.play(m[0],m[1]); _refresh_labels(); thinking = true; _rebuild()
	if scenario == "settings": overlay = "settings"; _rebuild()
const MIDGAME_REPLY = [4,8]
## Capture helper: pin shared clocks and repaint every layer once (processing is paused).
func debug_refresh():
	P.clock = clock
	board.last_move_age = 1
	_sync_fx(); board.refresh(); backdrop.refresh(); queue_redraw()
	for rig in field_heroes.values(): rig.frozen = true; rig.clip_age = 1.4; rig.pose(1.4)
	if is_instance_valid(hero_select): hero_select.hero.frozen = true; hero_select.hero.clip_age = .5; hero_select.hero.pose(1.4)
	if cinematic.visible:
		for rig in [cinematic.hero,cinematic.loser]: rig.frozen = true; rig.clip_age = cinematic.age; rig.pose(1.4)
		cinematic.pose()
	callout.frozen = true
	for n in ui_nodes:
		if is_instance_valid(n): n.queue_redraw()

func _winner_controls(s: Vector2):
	var g = Cinematic.card_geometry(s,"draw" if game.status == 3 else "spotlight")
	for item in [["again","REMATCH",g.again,rematch,true],["menu","MAIN MENU",g.menu,go_home,false]]:
		var button = preload("res://characters/match_button.gd").new()
		button.caption = item[1]; button.position = item[2].position; button.size = item[2].size; button.accent = item[4]
		button.z_index = 31; button.pressed.connect(item[3]); button.pressed.connect(func(): sound.cue("ui"))
		add_child(button); ui_nodes.append(button); controls[item[0]] = button
	_apply_result_anim()
	if mode == "online" and is_instance_valid(transport):
		controls.again.disabled = transport.local_rematch or not remote_ready
		controls.again.caption = "ACCEPT" if transport.remote_rematch and not transport.local_rematch else "REMATCH"
		var label = Label.new(); label.z_index = 31; label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = message if not message.is_empty() else transport.rematch_status(); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(s.x*.04,g.again.position.y-38); label.size = Vector2(s.x*.92,32)
		label.add_theme_font_override("font",P.SANS); label.add_theme_font_size_override("font_size",18)
		add_child(label); ui_nodes.append(label)

## Deterministic arbitrary-time capture, including seeking backwards across actions.
func debug_seek_cinematic(seconds: float):
	cinematic.seek(seconds); _debug_capture = true; thinking = false
	board.frozen = cinematic.kind != "versus" or cinematic.active
	var want = "result" if cinematic.buttons_shown else ""
	if overlay != want: overlay = want; _rebuild()
	_result_shown = cinematic.kind in ["spotlight","draw"]
	debug_refresh()
